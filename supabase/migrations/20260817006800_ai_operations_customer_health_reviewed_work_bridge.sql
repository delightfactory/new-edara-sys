-- ============================================================================
-- AI Operations Planner — Customer Health Human-Approved Work Bridge
--
-- DESIGN-TIME MIGRATION ONLY.
--
-- Adds reviewed CREATE_WORK execution for Customer Health while preserving the
-- existing Receivables/Sales bridge as an audited private primitive.
-- Operational mutation is limited to Work + AI provenance after human approval.
-- Customers, targets, sales, activities, visits, calls and credit records remain
-- read-only.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION private.work_create_ai_reviewed_customer_health_task(
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
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_sc ai_ops.snapshot_cases%ROWTYPE;
  v_existing_work public.work_items%ROWTYPE;
  v_work public.work_items%ROWTYPE;
  v_issues JSONB;
  v_now TIMESTAMPTZ:=clock_timestamp();
  v_source_key TEXT;
  v_priority public.work_priority;
  v_title TEXT;
  v_description TEXT;
  v_fingerprint TEXT;
  v_customer_id UUID;
  v_target_id UUID;
  v_department_id UUID;
  v_branch_id UUID;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('ai_ops:commit:'||p_decision_id::TEXT,0));

  IF p_approved_execution_by IS NULL
     OR NOT private.work_actor_is_active(p_approved_execution_by) THEN
    RAISE EXCEPTION 'approved execution actor is not an active Work actor';
  END IF;

  SELECT * INTO v_decision
  FROM ai_ops.decisions
  WHERE id=p_decision_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'AI Operations decision not found';
  END IF;

  IF v_decision.decision_type<>'CREATE_WORK' THEN
    RETURN jsonb_build_object(
      'committed',false,'blocked',true,
      'reason','bridge_supports_create_work_only',
      'decision_type',v_decision.decision_type
    );
  END IF;

  IF v_decision.committed_work_item_id IS NOT NULL THEN
    SELECT * INTO v_existing_work
    FROM public.work_items
    WHERE id=v_decision.committed_work_item_id;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'committed',true,
        'idempotent_reuse',true,
        'decision_id',p_decision_id,
        'work_item_id',v_existing_work.id,
        'work_number',v_existing_work.work_number
      );
    END IF;

    RAISE EXCEPTION 'decision references missing committed Work item';
  END IF;

  SELECT * INTO v_settings
  FROM ai_ops.settings
  WHERE singleton=true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'AI Operations settings are not initialized';
  END IF;

  IF NOT v_settings.planner_enabled THEN
    RETURN jsonb_build_object(
      'committed',false,'blocked',true,'reason','planner_disabled_kill_switch'
    );
  END IF;
  IF v_settings.shadow_mode THEN
    RETURN jsonb_build_object(
      'committed',false,'blocked',true,'reason','shadow_mode_blocks_operational_commit'
    );
  END IF;

  v_source_key:='ai_ops:decision:'||p_decision_id::TEXT;

  SELECT * INTO v_existing_work
  FROM public.work_items wi
  WHERE wi.source_kind='system'::public.work_source_kind
    AND wi.source_key=v_source_key
  ORDER BY wi.created_at,wi.id
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'committed',false,'blocked',true,
      'reason','unexpected_source_key_collision',
      'work_item_id',v_existing_work.id,
      'work_number',v_existing_work.work_number
    );
  END IF;

  SELECT * INTO v_review
  FROM ai_ops.decision_reviews
  WHERE decision_id=p_decision_id;

  IF NOT FOUND OR v_review.review_state<>'approved' THEN
    RETURN jsonb_build_object(
      'committed',false,'blocked',true,'reason','human_approval_required'
    );
  END IF;

  IF v_decision.validation_state<>'validated' THEN
    RETURN jsonb_build_object(
      'committed',false,'blocked',true,'reason','decision_not_validated'
    );
  END IF;

  v_fingerprint:=md5(jsonb_build_object(
    'id',v_decision.id,
    'run_id',v_decision.run_id,
    'case_id',v_decision.case_id,
    'revision',v_decision.revision,
    'decision_type',v_decision.decision_type,
    'recommended_owner_user_id',v_decision.recommended_owner_user_id,
    'recommended_assignee_user_id',v_decision.recommended_assignee_user_id,
    'responsibility_basis',v_decision.responsibility_basis,
    'concise_rationale',v_decision.concise_rationale,
    'confidence',v_decision.confidence,
    'expected_outcome',v_decision.expected_outcome,
    'next_action_text',v_decision.next_action_text,
    'due_at',v_decision.due_at,
    'review_after',v_decision.review_after,
    'linked_work_item_id',v_decision.linked_work_item_id
  )::TEXT);

  IF v_review.decision_fingerprint IS DISTINCT FROM v_fingerprint
     OR v_review.decision_revision<>v_decision.revision THEN
    RETURN jsonb_build_object(
      'committed',false,'blocked',true,'reason','review_fingerprint_mismatch'
    );
  END IF;

  v_issues:=ai_ops.current_decision_issues(p_decision_id);
  IF jsonb_array_length(v_issues)>0 THEN
    UPDATE ai_ops.decisions
    SET
      validation_state='rejected',
      commit_status='rejected',
      validation_detail=validation_detail||jsonb_build_object(
        'commit_revalidation_failed',true,
        'commit_revalidation_codes',v_issues,
        'commit_revalidation_at',v_now,
        'stage_only',true
      ),
      validated_at=v_now,
      validated_by_user_id=NULL,
      updated_at=v_now
    WHERE id=p_decision_id;

    RETURN jsonb_build_object(
      'committed',false,'blocked',true,
      'reason','current_state_changed',
      'validation_codes',v_issues
    );
  END IF;

  IF v_decision.recommended_owner_user_id IS NULL
     OR v_decision.recommended_assignee_user_id IS NULL
     OR v_decision.due_at IS NULL THEN
    RETURN jsonb_build_object(
      'committed',false,'blocked',true,
      'reason','explicit_owner_assignee_and_due_required'
    );
  END IF;

  IF v_decision.due_at<=v_now THEN
    RETURN jsonb_build_object(
      'committed',false,'blocked',true,'reason','proposed_due_at_not_future'
    );
  END IF;

  IF NOT private.work_actor_is_active(v_decision.recommended_owner_user_id)
     OR NOT private.work_actor_is_active(v_decision.recommended_assignee_user_id) THEN
    RETURN jsonb_build_object(
      'committed',false,'blocked',true,'reason','work_actor_became_unavailable'
    );
  END IF;

  SELECT * INTO v_snapshot
  FROM ai_ops.snapshots
  WHERE run_id=v_decision.run_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'decision snapshot missing';
  END IF;

  SELECT * INTO v_sc
  FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id=v_snapshot.id
    AND sc.case_id=v_decision.case_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'decision-time frozen evidence missing';
  END IF;

  IF v_sc.domain<>'customer_health'
     OR v_sc.case_type NOT IN ('reactivation_gap','high_value_reactivation_opportunity') THEN
    RAISE EXCEPTION 'Customer Health Work bridge received unsupported frozen case';
  END IF;

  v_customer_id:=COALESCE(v_sc.entity_id,NULLIF(v_sc.facts->>'customer_id','')::UUID);
  IF v_customer_id IS NULL
     OR NOT private.work_link_entity_exists('customer',v_customer_id) THEN
    RAISE EXCEPTION 'customer entity no longer exists or is unsupported by Work link contract';
  END IF;

  v_target_id:=NULLIF(v_sc.facts->>'target_id','')::UUID;
  IF v_target_id IS NOT NULL
     AND NOT private.work_link_entity_exists('target',v_target_id) THEN
    RAISE EXCEPTION 'reactivation target no longer exists or is unsupported by Work link contract';
  END IF;

  SELECT e.department_id,e.branch_id
  INTO v_department_id,v_branch_id
  FROM public.hr_employees e
  WHERE e.user_id=v_decision.recommended_assignee_user_id
    AND e.status::TEXT='active'
  ORDER BY e.updated_at DESC NULLS LAST,e.id
  LIMIT 1;

  IF v_department_id IS NULL AND v_branch_id IS NULL THEN
    SELECT e.department_id,e.branch_id
    INTO v_department_id,v_branch_id
    FROM public.hr_employees e
    WHERE e.user_id=v_decision.recommended_owner_user_id
      AND e.status::TEXT='active'
    ORDER BY e.updated_at DESC NULLS LAST,e.id
    LIMIT 1;
  END IF;

  v_priority:=CASE v_sc.severity
    WHEN 'critical' THEN 'urgent'::public.work_priority
    WHEN 'high' THEN 'high'::public.work_priority
    WHEN 'medium' THEN 'normal'::public.work_priority
    ELSE 'low'::public.work_priority
  END;

  v_title:=left(
    'متابعة إعادة تنشيط العميل — '||
      COALESCE(NULLIF(v_sc.facts->>'customer_name',''),'عميل'),
    240
  );

  v_description:=left(
    concat_ws(E'\n',
      'إجراء تشغيلي ناتج عن مراجعة معتمدة لصحة العلاقة مع العميل وفرصة إعادة تنشيطه.',
      'نفّذ الإجراء المحدد دون تكرار تواصل أو زيارة قائمة بالفعل.',
      'سجّل النتيجة الفعلية والخطوة التالية داخل Work ليتمكن النظام من قياس المخرجات.'
    ),
    2000
  );

  INSERT INTO public.work_items(
    kind,source_kind,source_key,title,description,expected_outcome,
    status,priority,visibility,creator_user_id,requester_user_id,
    accountable_owner_user_id,current_assignee_user_id,
    owning_department_id,branch_id,due_at,first_due_at,next_action_text,
    next_action_at,acknowledgement_required,completion_mode,
    last_meaningful_activity_at,state_version,metadata
  ) VALUES (
    'task'::public.work_item_kind,
    'system'::public.work_source_kind,
    v_source_key,
    v_title,
    v_description,
    v_decision.expected_outcome,
    'draft'::public.work_item_status,
    v_priority,
    'standard'::public.work_visibility,
    NULL,
    NULL,
    v_decision.recommended_owner_user_id,
    v_decision.recommended_assignee_user_id,
    v_department_id,
    v_branch_id,
    v_decision.due_at,
    v_decision.due_at,
    v_decision.next_action_text,
    NULL,
    false,
    'assignee_closes'::public.work_completion_mode,
    v_now,
    1,
    jsonb_build_object(
      'origin','ai_ops',
      'ai_domain','customer_health',
      'ai_case_type',v_sc.case_type,
      'ai_decision_id',v_decision.id,
      'ai_case_id',v_decision.case_id,
      'ai_run_id',v_decision.run_id,
      'ai_snapshot_id',v_snapshot.id,
      'human_review_id',v_review.id,
      'approved_execution_by',p_approved_execution_by,
      'employee_safe_reason',v_decision.employee_safe_reason,
      'management_rationale_exposed',false
    )
  )
  RETURNING * INTO v_work;

  PERFORM private.ai_ops_append_work_system_event(
    v_work.id,
    'work.created',
    NULL,
    'draft'::public.work_item_status,
    jsonb_build_object(
      'source_kind','system',
      'source_key',v_source_key,
      'origin','ai_ops',
      'domain','customer_health',
      'case_type',v_sc.case_type,
      'decision_id',v_decision.id,
      'review_id',v_review.id,
      'owner_user_id',v_work.accountable_owner_user_id,
      'assignee_user_id',v_work.current_assignee_user_id,
      'due_at',v_work.due_at
    )
  );

  UPDATE public.work_items
  SET
    status='open'::public.work_item_status,
    activated_at=v_now,
    assigned_at=v_now,
    state_version=state_version+1,
    last_meaningful_activity_at=v_now,
    updated_at=v_now
  WHERE id=v_work.id
  RETURNING * INTO v_work;

  INSERT INTO public.work_links(
    work_item_id,entity_type,entity_id,relation_type,label,created_by_user_id
  ) VALUES (
    v_work.id,'customer',v_customer_id,'primary',
    left(COALESCE(v_sc.facts->>'customer_name','عميل'),240),NULL
  )
  ON CONFLICT(work_item_id,entity_type,entity_id,relation_type) DO NOTHING;

  IF v_target_id IS NOT NULL THEN
    INSERT INTO public.work_links(
      work_item_id,entity_type,entity_id,relation_type,label,created_by_user_id
    ) VALUES (
      v_work.id,'target',v_target_id,'governed_by',
      left(COALESCE(v_sc.facts->>'target_name','هدف إعادة التنشيط'),240),NULL
    )
    ON CONFLICT(work_item_id,entity_type,entity_id,relation_type) DO NOTHING;
  END IF;

  PERFORM private.ai_ops_append_work_system_event(
    v_work.id,
    'work.activated',
    'draft'::public.work_item_status,
    'open'::public.work_item_status,
    jsonb_build_object(
      'source','ai_ops_human_approved',
      'domain','customer_health',
      'case_type',v_sc.case_type,
      'decision_id',v_decision.id,
      'approved_by_user_id',p_approved_execution_by,
      'assignee_user_id',v_work.current_assignee_user_id,
      'owner_user_id',v_work.accountable_owner_user_id
    )
  );

  UPDATE ai_ops.decisions
  SET
    committed_work_item_id=v_work.id,
    committed_at=v_now,
    commit_status='committed',
    validation_detail=validation_detail||jsonb_build_object(
      'commit_revalidated_against_current_state',true,
      'commit_revalidated_at',v_now,
      'human_review_id',v_review.id,
      'approved_execution_by',p_approved_execution_by,
      'domain','customer_health',
      'stage_only',false
    ),
    updated_at=v_now
  WHERE id=p_decision_id;

  UPDATE ai_ops.cases
  SET status='actioned',updated_at=v_now,state_version=state_version+1
  WHERE id=v_decision.case_id;

  UPDATE ai_ops.planner_runs
  SET
    checkpoint='reviewed_work_committed',
    work_created_count=work_created_count+1,
    result_summary=result_summary||jsonb_build_object(
      'last_committed_decision_id',v_decision.id,
      'last_committed_work_item_id',v_work.id,
      'last_commit_at',v_now,
      'last_commit_domain','customer_health'
    ),
    updated_at=v_now
  WHERE id=v_decision.run_id;

  RETURN jsonb_build_object(
    'committed',true,
    'idempotent_reuse',false,
    'decision_id',p_decision_id,
    'work_item_id',v_work.id,
    'work_number',v_work.work_number,
    'source_key',v_source_key,
    'domain','customer_health',
    'case_type',v_sc.case_type,
    'operational_mutation','work_create_only'
  );
END;
$$;

REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_customer_health_task(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;

ALTER FUNCTION private.work_create_ai_reviewed_task(UUID,UUID)
  RENAME TO work_create_ai_reviewed_task_receivables_sales_v3;

REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_task_receivables_sales_v3(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;

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
  v_domain TEXT;
BEGIN
  SELECT sc.domain INTO v_domain
  FROM ai_ops.decisions d
  JOIN ai_ops.snapshots s ON s.run_id=d.run_id
  JOIN ai_ops.snapshot_cases sc
    ON sc.snapshot_id=s.id
   AND sc.case_id=d.case_id
  WHERE d.id=p_decision_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'decision-time frozen evidence missing';
  END IF;

  IF v_domain='customer_health' THEN
    RETURN private.work_create_ai_reviewed_customer_health_task(
      p_decision_id,p_approved_execution_by
    );
  END IF;

  RETURN private.work_create_ai_reviewed_task_receivables_sales_v3(
    p_decision_id,p_approved_execution_by
  );
END;
$$;

REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_task(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION private.work_create_ai_reviewed_customer_health_task(UUID,UUID) IS
  'Human-approved Customer Health CREATE_WORK bridge with kill switches, immutable review fingerprint, commit-time current-state revalidation and customer/target Work links.';
COMMENT ON FUNCTION private.work_create_ai_reviewed_task(UUID,UUID) IS
  'Canonical reviewed Work bridge dispatcher for Receivables, Sales and Customer Health.';

RESET lock_timeout;
RESET statement_timeout;