-- ============================================================================
-- AI Operations Planner — Human-Approved Credit Work Bridge
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply until explicitly reviewed/approved.
-- Depends on:
--   * 20260816172600_ai_operations_current_state_guard.sql
--   * 20260816173100_ai_operations_human_review_revalidation_fix.sql
--   * deployed Work Management system-source/event/link infrastructure
--
-- FIRST BRIDGE SCOPE:
--   * CREATE_WORK only
--   * reviewed + approved + currently validated decision only
--   * exact current-state guard re-run in the SAME transaction
--   * explicit owner + assignee + future due_at required (no routing guesses)
--   * source_kind=system / deterministic source_key for idempotency
--   * normal Work event path, so existing notification handling remains canonical
--
-- NOT INCLUDED:
--   * ESCALATE execution (recommendation remains review-only for now)
--   * autonomous/auto-commit execution
--   * Sales/Customer/Credit mutation
--   * user impersonation
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

-- Adapter deliberately calls the existing system-event helper dynamically after
-- checking one of the supported deployed signatures. This avoids inventing a
-- second Work event writer while still failing migration/runtime closed if the
-- Work helper contract has drifted before future application.
CREATE OR REPLACE FUNCTION private.ai_ops_append_work_system_event(
  p_work_item_id UUID,
  p_event_type TEXT,
  p_payload JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF to_regprocedure('private.work_append_system_event(uuid,text,jsonb)') IS NOT NULL THEN
    EXECUTE 'select private.work_append_system_event($1,$2,$3)'
      USING p_work_item_id, p_event_type, COALESCE(p_payload, '{}'::JSONB);
    RETURN;
  END IF;

  RAISE EXCEPTION 'deployed Work system-event helper signature is not compatible; re-run schema discovery before applying AI bridge';
END;
$$;

REVOKE ALL ON FUNCTION private.ai_ops_append_work_system_event(UUID, TEXT, JSONB)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.work_create_ai_reviewed_task(
  p_decision_id UUID,
  p_approved_execution_by UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_settings ai_ops.settings%ROWTYPE;
  v_decision ai_ops.decisions%ROWTYPE;
  v_review ai_ops.decision_reviews%ROWTYPE;
  v_run ai_ops.planner_runs%ROWTYPE;
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_sc ai_ops.snapshot_cases%ROWTYPE;
  v_existing_work public.work_items%ROWTYPE;
  v_work public.work_items%ROWTYPE;
  v_issues JSONB;
  v_now TIMESTAMPTZ := clock_timestamp();
  v_source_key TEXT;
  v_priority public.work_priority;
  v_title TEXT;
  v_description TEXT;
  v_fingerprint TEXT;
  v_customer_id UUID;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('ai_ops:commit:' || p_decision_id::TEXT, 0));

  IF p_approved_execution_by IS NULL
     OR NOT private.work_actor_is_active(p_approved_execution_by) THEN
    RAISE EXCEPTION 'approved execution actor is not an active Work actor';
  END IF;

  SELECT * INTO v_settings FROM ai_ops.settings WHERE singleton = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations settings are not initialized'; END IF;

  -- Autonomous mode is intentionally not used by this bridge. It is a reviewed
  -- management action even if auto_commit_enabled is later introduced elsewhere.
  SELECT * INTO v_decision
  FROM ai_ops.decisions
  WHERE id = p_decision_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations decision not found'; END IF;

  IF v_decision.decision_type <> 'CREATE_WORK' THEN
    RETURN jsonb_build_object(
      'committed', false,
      'blocked', true,
      'reason', 'bridge_supports_create_work_only',
      'decision_type', v_decision.decision_type
    );
  END IF;

  IF v_decision.committed_work_item_id IS NOT NULL THEN
    SELECT * INTO v_existing_work
    FROM public.work_items
    WHERE id = v_decision.committed_work_item_id;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'committed', true,
        'idempotent_reuse', true,
        'decision_id', p_decision_id,
        'work_item_id', v_existing_work.id,
        'work_number', v_existing_work.work_number
      );
    END IF;

    RAISE EXCEPTION 'decision references missing committed Work item';
  END IF;

  v_source_key := 'ai_ops:decision:' || p_decision_id::TEXT;

  SELECT * INTO v_existing_work
  FROM public.work_items wi
  WHERE wi.source_kind = 'system'::public.work_source_kind
    AND wi.source_key = v_source_key
  ORDER BY wi.created_at ASC, wi.id ASC
  LIMIT 1;

  IF FOUND THEN
    UPDATE ai_ops.decisions
    SET
      committed_work_item_id = v_existing_work.id,
      committed_at = COALESCE(committed_at, v_now),
      validation_detail = validation_detail || jsonb_build_object(
        'work_bridge_recovered_existing_source_key', true,
        'stage_only', false
      )
    WHERE id = p_decision_id;

    RETURN jsonb_build_object(
      'committed', true,
      'idempotent_reuse', true,
      'decision_id', p_decision_id,
      'work_item_id', v_existing_work.id,
      'work_number', v_existing_work.work_number
    );
  END IF;

  SELECT * INTO v_review
  FROM ai_ops.decision_reviews
  WHERE decision_id = p_decision_id;

  IF NOT FOUND OR v_review.review_state <> 'approved' THEN
    RETURN jsonb_build_object('committed', false, 'blocked', true, 'reason', 'human_approval_required');
  END IF;

  IF v_decision.validation_state <> 'validated' THEN
    RETURN jsonb_build_object('committed', false, 'blocked', true, 'reason', 'decision_not_validated');
  END IF;

  v_fingerprint := md5(jsonb_build_object(
    'id', v_decision.id,
    'run_id', v_decision.run_id,
    'case_id', v_decision.case_id,
    'revision', v_decision.revision,
    'decision_type', v_decision.decision_type,
    'recommended_owner_user_id', v_decision.recommended_owner_user_id,
    'recommended_assignee_user_id', v_decision.recommended_assignee_user_id,
    'responsibility_basis', v_decision.responsibility_basis,
    'concise_rationale', v_decision.concise_rationale,
    'confidence', v_decision.confidence,
    'expected_outcome', v_decision.expected_outcome,
    'next_action_text', v_decision.next_action_text,
    'due_at', v_decision.due_at,
    'review_after', v_decision.review_after,
    'linked_work_item_id', v_decision.linked_work_item_id
  )::TEXT);

  IF v_review.decision_fingerprint IS DISTINCT FROM v_fingerprint
     OR v_review.decision_revision <> v_decision.revision THEN
    RETURN jsonb_build_object('committed', false, 'blocked', true, 'reason', 'review_fingerprint_mismatch');
  END IF;

  -- Re-run the shared source of safety truth immediately before Work mutation.
  v_issues := ai_ops.current_decision_issues(p_decision_id);
  IF jsonb_array_length(v_issues) > 0 THEN
    UPDATE ai_ops.decisions
    SET
      validation_state = 'rejected',
      validation_detail = validation_detail || jsonb_build_object(
        'commit_revalidation_failed', true,
        'commit_revalidation_codes', v_issues,
        'commit_revalidation_at', v_now,
        'stage_only', true
      ),
      validated_at = v_now,
      validated_by_user_id = NULL
    WHERE id = p_decision_id;

    RETURN jsonb_build_object(
      'committed', false,
      'blocked', true,
      'reason', 'current_state_changed',
      'validation_codes', v_issues
    );
  END IF;

  -- The bridge refuses to invent execution routing or deadline.
  IF v_decision.recommended_owner_user_id IS NULL
     OR v_decision.recommended_assignee_user_id IS NULL
     OR v_decision.due_at IS NULL THEN
    RETURN jsonb_build_object(
      'committed', false,
      'blocked', true,
      'reason', 'explicit_owner_assignee_and_due_required'
    );
  END IF;

  IF v_decision.due_at <= v_now THEN
    RETURN jsonb_build_object('committed', false, 'blocked', true, 'reason', 'proposed_due_at_not_future');
  END IF;

  IF NOT private.work_actor_is_active(v_decision.recommended_owner_user_id)
     OR NOT private.work_actor_is_active(v_decision.recommended_assignee_user_id) THEN
    RETURN jsonb_build_object('committed', false, 'blocked', true, 'reason', 'work_actor_became_unavailable');
  END IF;

  SELECT * INTO v_run FROM ai_ops.planner_runs WHERE id = v_decision.run_id;
  SELECT * INTO v_snapshot FROM ai_ops.snapshots WHERE run_id = v_decision.run_id;
  SELECT * INTO v_sc
  FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id = v_snapshot.id AND sc.case_id = v_decision.case_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'decision-time frozen evidence missing'; END IF;

  v_customer_id := NULLIF(v_sc.facts->>'customer_id', '')::UUID;

  v_priority := CASE v_sc.severity
    WHEN 'critical' THEN 'urgent'::public.work_priority
    WHEN 'high' THEN 'high'::public.work_priority
    WHEN 'medium' THEN 'normal'::public.work_priority
    ELSE 'low'::public.work_priority
  END;

  v_title := left(
    'مراجعة تحصيل فاتورة ' || COALESCE(NULLIF(v_sc.facts->>'order_number',''), 'ائتمان')
      || ' — ' || COALESCE(NULLIF(v_sc.facts->>'customer_name',''), 'عميل'),
    240
  );

  v_description := left(
    concat_ws(E'\n',
      'إجراء تشغيلي ناتج عن مراجعة حالة ائتمانية متأخرة.',
      'الرصيد المتبقي: ' || COALESCE(v_sc.facts->>'remaining_amount','—') || ' EGP',
      'أيام التأخير وقت التحليل: ' || COALESCE(v_sc.facts->>'days_overdue','—'),
      'تاريخ الاستحقاق وقت التحليل: ' || COALESCE(v_sc.facts->>'due_date','—'),
      'نفّذ الإجراء التالي وسجّل النتيجة الفعلية داخل Work.'
    ),
    2000
  );

  -- Follow the deployed system-generated Work shape: system source, nullable
  -- human creator, explicit accountable owner/executor, open lifecycle state,
  -- optimistic version 1 and normal Work events/links below.
  INSERT INTO public.work_items(
    kind,
    status,
    title,
    description,
    expected_outcome,
    priority,
    owner_user_id,
    assignee_user_id,
    due_at,
    next_action_text,
    source_kind,
    source_key,
    metadata,
    created_by_user_id,
    version
  ) VALUES (
    'task'::public.work_item_kind,
    'open'::public.work_item_status,
    v_title,
    v_description,
    v_decision.expected_outcome,
    v_priority,
    v_decision.recommended_owner_user_id,
    v_decision.recommended_assignee_user_id,
    v_decision.due_at,
    v_decision.next_action_text,
    'system'::public.work_source_kind,
    v_source_key,
    jsonb_build_object(
      'origin', 'ai_ops',
      'ai_decision_id', v_decision.id,
      'ai_case_id', v_decision.case_id,
      'ai_run_id', v_decision.run_id,
      'ai_snapshot_id', v_snapshot.id,
      'human_review_id', v_review.id,
      'approved_execution_by', p_approved_execution_by,
      'management_rationale_exposed', false
    ),
    NULL,
    1
  )
  RETURNING * INTO v_work;

  INSERT INTO public.work_links(
    work_item_id, entity_type, entity_id, relation_type, label, created_by_user_id
  ) VALUES (
    v_work.id,
    'sales_order',
    v_sc.entity_id,
    'primary',
    left(COALESCE(v_sc.facts->>'order_number', 'فاتورة بيع'), 240),
    NULL
  ) ON CONFLICT (work_item_id, entity_type, entity_id, relation_type) DO NOTHING;

  IF v_customer_id IS NOT NULL THEN
    INSERT INTO public.work_links(
      work_item_id, entity_type, entity_id, relation_type, label, created_by_user_id
    ) VALUES (
      v_work.id,
      'customer',
      v_customer_id,
      'relates_to',
      left(COALESCE(v_sc.facts->>'customer_name', 'عميل'), 240),
      NULL
    ) ON CONFLICT (work_item_id, entity_type, entity_id, relation_type) DO NOTHING;
  END IF;

  PERFORM private.ai_ops_append_work_system_event(
    v_work.id,
    'work.created',
    jsonb_build_object(
      'source_kind', 'system',
      'source_key', v_source_key,
      'origin', 'ai_ops',
      'decision_id', v_decision.id,
      'review_id', v_review.id,
      'owner_user_id', v_work.owner_user_id,
      'assignee_user_id', v_work.assignee_user_id,
      'due_at', v_work.due_at
    )
  );

  PERFORM private.ai_ops_append_work_system_event(
    v_work.id,
    'work.activated',
    jsonb_build_object(
      'source', 'ai_ops_human_approved',
      'decision_id', v_decision.id,
      'approved_by_user_id', p_approved_execution_by,
      'assignee_user_id', v_work.assignee_user_id,
      'owner_user_id', v_work.owner_user_id
    )
  );

  UPDATE ai_ops.decisions
  SET
    committed_work_item_id = v_work.id,
    committed_at = v_now,
    validation_detail = validation_detail || jsonb_build_object(
      'commit_revalidated_against_current_state', true,
      'commit_revalidated_at', v_now,
      'human_review_id', v_review.id,
      'approved_execution_by', p_approved_execution_by,
      'stage_only', false
    )
  WHERE id = p_decision_id;

  UPDATE ai_ops.cases
  SET
    status = 'actioned',
    updated_at = v_now,
    state_version = state_version + 1
  WHERE id = v_decision.case_id;

  UPDATE ai_ops.planner_runs
  SET
    checkpoint = 'reviewed_work_committed',
    work_created_count = work_created_count + 1,
    result_summary = result_summary || jsonb_build_object(
      'last_committed_decision_id', v_decision.id,
      'last_committed_work_item_id', v_work.id,
      'last_commit_at', v_now
    ),
    updated_at = v_now
  WHERE id = v_decision.run_id;

  RETURN jsonb_build_object(
    'committed', true,
    'idempotent_reuse', false,
    'decision_id', p_decision_id,
    'work_item_id', v_work.id,
    'work_number', v_work.work_number,
    'source_key', v_source_key,
    'operational_mutation', 'work_create_only'
  );
END;
$$;

REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_task(UUID, UUID)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ai_ops_commit_reviewed_decision(p_decision_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
BEGIN
  IF v_actor IS NULL OR NOT private.work_actor_is_active(v_actor) THEN
    RAISE EXCEPTION 'المستخدم غير متاح لتنفيذ قرار AI Operations'
      USING ERRCODE = '42501';
  END IF;

  IF NOT COALESCE(public.check_permission(v_actor, 'work.policies.manage'), false) THEN
    RAISE EXCEPTION 'لا تملك صلاحية تنفيذ قرارات التشغيل الذكي'
      USING ERRCODE = '42501';
  END IF;

  RETURN private.work_create_ai_reviewed_task(p_decision_id, v_actor);
END;
$$;

REVOKE ALL ON FUNCTION public.ai_ops_commit_reviewed_decision(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ai_ops_commit_reviewed_decision(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.ai_ops_commit_reviewed_decision(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ai_ops_commit_reviewed_decision(UUID) TO service_role;

COMMENT ON FUNCTION public.ai_ops_commit_reviewed_decision(UUID) IS
  'Human-approved first-slice Work commit RPC. Accepts decision_id only, revalidates current reality inside the commit transaction, creates system-source Work and performs no Sales/Credit mutation.';

RESET lock_timeout;
RESET statement_timeout;
