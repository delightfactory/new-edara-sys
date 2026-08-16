-- ============================================================================
-- AI Operations Planner — Management UI Read Gateway
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply until explicitly reviewed/approved.
-- Depends on:
--   * 20260816163504_ai_operations_foundation.sql
--   * 20260816164500_ai_operations_snapshot_case_evidence.sql
--   * 20260816165500_ai_operations_credit_case_engine.sql
--   * 20260816170000_ai_operations_credit_snapshot_capture.sql
--
-- Purpose:
--   * expose a SMALL, read-only management presentation surface
--   * keep ai_ops tables private/non-Data-API
--   * follow the deployed Work Management auth/permission pattern
--   * read planner evidence from immutable snapshot_cases, never mutable facts
--   * keep this UI gateway separate from any future AI-worker gateway
--
-- Security:
--   * authenticated management user only
--   * auth.uid() must be an active Work actor
--   * requires work.policies.manage
--   * no anon access
--   * no mutations
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '30s';

CREATE OR REPLACE FUNCTION public.ai_ops_get_console_snapshot()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_settings ai_ops.settings%ROWTYPE;
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_attention JSONB := '[]'::JSONB;
  v_runs JSONB := '[]'::JSONB;
  v_context JSONB := '[]'::JSONB;
  v_trust JSONB := '[]'::JSONB;
  v_pulse JSONB := '[]'::JSONB;
BEGIN
  IF v_actor IS NULL OR NOT private.work_actor_is_active(v_actor) THEN
    RAISE EXCEPTION 'المستخدم غير متاح لعرض AI Operations'
      USING ERRCODE = '42501';
  END IF;

  IF NOT COALESCE(public.check_permission(v_actor, 'work.policies.manage'), false) THEN
    RAISE EXCEPTION 'لا تملك صلاحية إدارة سياسات التشغيل الذكي'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_settings
  FROM ai_ops.settings
  WHERE singleton = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AI Operations settings are not initialized';
  END IF;

  SELECT s.* INTO v_snapshot
  FROM ai_ops.snapshots s
  ORDER BY s.generated_at DESC, s.id DESC
  LIMIT 1;

  SELECT COALESCE(jsonb_agg(run_row ORDER BY scheduled_for DESC), '[]'::JSONB)
  INTO v_runs
  FROM (
    SELECT jsonb_build_object(
      'id', r.id,
      'run_key', r.run_key,
      'run_type', r.run_type,
      'business_date', r.business_date,
      'scheduled_for', r.scheduled_for,
      'status', r.status,
      'checkpoint', r.checkpoint,
      'attempt_no', r.attempt_no,
      'cases_seen', r.cases_seen,
      'cases_investigated', r.cases_investigated,
      'decisions_count', r.decisions_count,
      'work_created_count', r.work_created_count,
      'started_at', r.started_at,
      'completed_at', r.completed_at,
      'error_class', r.error_class,
      'error_message', r.error_message
    ) AS run_row,
    r.scheduled_for
    FROM ai_ops.planner_runs r
    ORDER BY r.scheduled_for DESC, r.id DESC
    LIMIT 10
  ) q;

  SELECT COALESCE(jsonb_agg(ctx_row ORDER BY ctx_row_sort DESC), '[]'::JSONB)
  INTO v_context
  FROM (
    SELECT
      c.updated_at AS ctx_row_sort,
      jsonb_build_object(
        'id', c.id,
        'subject_type', c.subject_type,
        'subject_id', c.subject_id,
        'subject_label', COALESCE(
          NULLIF(c.context_payload->>'subject_label', ''),
          CASE WHEN c.subject_type = 'customer' THEN customer.name END,
          CASE WHEN c.subject_type = 'employee' THEN employee_profile.full_name END,
          c.subject_type || ':' || c.subject_id::TEXT
        ),
        'context_type', c.context_type,
        'summary', COALESCE(NULLIF(c.context_payload->>'summary', ''), c.context_type),
        'owner_label', owner_profile.full_name,
        'source_type', c.source_type,
        'confidence_class', c.confidence_class,
        'lifecycle_type', c.lifecycle_type,
        'valid_until', c.valid_until,
        'review_on', c.review_on,
        'status', c.status
      ) AS ctx_row
    FROM ai_ops.operational_context c
    LEFT JOIN public.customers customer
      ON c.subject_type = 'customer' AND customer.id = c.subject_id
    LEFT JOIN public.profiles employee_profile
      ON c.subject_type = 'employee' AND employee_profile.id = c.subject_id
    LEFT JOIN public.profiles owner_profile
      ON owner_profile.id = c.owner_user_id
    WHERE c.status = 'active'
      AND (c.valid_until IS NULL OR c.valid_until > clock_timestamp())
    ORDER BY c.updated_at DESC, c.id DESC
    LIMIT 30
  ) q;

  IF v_snapshot.id IS NULL THEN
    RETURN jsonb_build_object(
      'mode', 'rpc',
      'integration_state', 'database_not_ready',
      'generated_at', clock_timestamp(),
      'data_as_of', clock_timestamp(),
      'settings', jsonb_build_object(
        'planner_enabled', v_settings.planner_enabled,
        'shadow_mode', v_settings.shadow_mode,
        'auto_commit_enabled', v_settings.auto_commit_enabled,
        'max_cases_per_snapshot', v_settings.max_cases_per_snapshot,
        'max_actions_per_run', v_settings.max_actions_per_run,
        'planner_policy_version', v_settings.planner_policy_version,
        'tool_contract_version', v_settings.tool_contract_version,
        'state_version', v_settings.state_version,
        'updated_at', v_settings.updated_at
      ),
      'trust', '[]'::JSONB,
      'pulse', '[]'::JSONB,
      'attention', '[]'::JSONB,
      'recent_runs', v_runs,
      'context', v_context
    );
  END IF;

  v_trust := CASE
    WHEN jsonb_typeof(v_snapshot.trust->'domain_status') = 'array'
      THEN v_snapshot.trust->'domain_status'
    ELSE '[]'::JSONB
  END;

  v_pulse := CASE
    WHEN jsonb_typeof(v_snapshot.company_pulse->'metrics') = 'array'
      THEN v_snapshot.company_pulse->'metrics'
    ELSE '[]'::JSONB
  END;

  SELECT COALESCE(jsonb_agg(case_row ORDER BY snapshot_rank ASC), '[]'::JSONB)
  INTO v_attention
  FROM (
    SELECT
      sc.snapshot_rank,
      jsonb_build_object(
        'id', c.id,
        'case_key', sc.case_key,
        'domain', sc.domain,
        'case_type', sc.case_type,
        'entity_type', sc.entity_type,
        'entity_id', sc.entity_id,
        'entity_label', CASE
          WHEN sc.domain = 'receivables' AND sc.case_type = 'overdue_invoice' THEN
            concat_ws(' · ', NULLIF(sc.facts->>'order_number', ''), NULLIF(sc.facts->>'customer_name', ''))
          ELSE COALESCE(NULLIF(sc.facts->>'entity_label', ''), sc.case_key)
        END,
        'attention_class', sc.attention_class,
        'severity', sc.severity,
        'status', c.status,
        'title', CASE
          WHEN sc.domain = 'receivables' AND sc.case_type = 'overdue_invoice' THEN
            'فاتورة متأخرة تحتاج مراجعة ائتمانية'
          ELSE COALESCE(NULLIF(sc.facts->>'title', ''), sc.case_type)
        END,
        'reason', CASE
          WHEN sc.domain = 'receivables' AND sc.case_type = 'overdue_invoice' THEN
            format(
              'الرصيد المتبقي %s؛ التأخير %s يوم. الحالة تحتاج تفسيرًا سببيًا قبل توجيه أي عمل.',
              COALESCE(sc.facts->>'remaining_amount', '—'),
              COALESCE(sc.facts->>'days_overdue', '—')
            )
          ELSE COALESCE(NULLIF(sc.facts->>'reason', ''), 'تحتاج الحالة مراجعة الأدلة قبل اتخاذ إجراء.')
        END,
        'first_seen_at', c.first_seen_at,
        'last_seen_at', c.last_seen_at,
        'source_as_of', sc.source_as_of,
        'responsibility_label', owner_profile.full_name,
        'responsibility_basis', latest_decision.responsibility_basis->>'summary',
        'value_label', CASE
          WHEN sc.facts ? 'remaining_amount' THEN (sc.facts->>'remaining_amount') || ' EGP'
          ELSE sc.facts->>'value_label'
        END,
        'has_existing_work', COALESCE((sc.facts->'existing_active_work') IS NOT NULL, false),
        'linked_work_number', CASE
          WHEN jsonb_typeof(sc.facts->'existing_active_work') = 'object'
            THEN (sc.facts->'existing_active_work'->>'work_number')::BIGINT
          ELSE NULL
        END,
        'recommended_decision', latest_decision.decision_type,
        'review_after', latest_decision.review_after
      ) AS case_row
    FROM ai_ops.snapshot_cases sc
    JOIN ai_ops.cases c ON c.id = sc.case_id
    LEFT JOIN LATERAL (
      SELECT d.*
      FROM ai_ops.decisions d
      WHERE d.case_id = c.id
      ORDER BY d.created_at DESC, d.revision DESC, d.id DESC
      LIMIT 1
    ) latest_decision ON true
    LEFT JOIN public.profiles owner_profile
      ON owner_profile.id = latest_decision.recommended_owner_user_id
    WHERE sc.snapshot_id = v_snapshot.id
    ORDER BY sc.snapshot_rank ASC
    LIMIT v_settings.max_cases_per_snapshot
  ) q;

  RETURN jsonb_build_object(
    'mode', 'rpc',
    'integration_state', 'ready',
    'generated_at', v_snapshot.generated_at,
    'data_as_of', v_snapshot.data_as_of,
    'settings', jsonb_build_object(
      'planner_enabled', v_settings.planner_enabled,
      'shadow_mode', v_settings.shadow_mode,
      'auto_commit_enabled', v_settings.auto_commit_enabled,
      'max_cases_per_snapshot', v_settings.max_cases_per_snapshot,
      'max_actions_per_run', v_settings.max_actions_per_run,
      'planner_policy_version', v_settings.planner_policy_version,
      'tool_contract_version', v_settings.tool_contract_version,
      'state_version', v_settings.state_version,
      'updated_at', v_settings.updated_at
    ),
    'trust', v_trust,
    'pulse', v_pulse,
    'attention', v_attention,
    'recent_runs', v_runs,
    'context', v_context
  );
END;
$$;

REVOKE ALL ON FUNCTION public.ai_ops_get_console_snapshot() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ai_ops_get_console_snapshot() FROM anon;
GRANT EXECUTE ON FUNCTION public.ai_ops_get_console_snapshot() TO authenticated;
GRANT EXECUTE ON FUNCTION public.ai_ops_get_console_snapshot() TO service_role;

COMMENT ON FUNCTION public.ai_ops_get_console_snapshot() IS
  'Management UI read gateway for AI Operations. Requires active authenticated actor + work.policies.manage. Reads immutable snapshot evidence. Not a worker gateway.';

CREATE OR REPLACE FUNCTION public.ai_ops_get_case_detail(p_case_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_case ai_ops.cases%ROWTYPE;
  v_snapshot_case ai_ops.snapshot_cases%ROWTYPE;
  v_decision ai_ops.decisions%ROWTYPE;
  v_evidence JSONB := '[]'::JSONB;
  v_work JSONB := '[]'::JSONB;
  v_context_ids JSONB := '[]'::JSONB;
BEGIN
  IF v_actor IS NULL OR NOT private.work_actor_is_active(v_actor) THEN
    RAISE EXCEPTION 'المستخدم غير متاح لعرض AI Operations'
      USING ERRCODE = '42501';
  END IF;

  IF NOT COALESCE(public.check_permission(v_actor, 'work.policies.manage'), false) THEN
    RAISE EXCEPTION 'لا تملك صلاحية إدارة سياسات التشغيل الذكي'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_case
  FROM ai_ops.cases
  WHERE id = p_case_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AI Operations case not found';
  END IF;

  SELECT sc.* INTO v_snapshot_case
  FROM ai_ops.snapshot_cases sc
  JOIN ai_ops.snapshots s ON s.id = sc.snapshot_id
  WHERE sc.case_id = v_case.id
  ORDER BY s.generated_at DESC, sc.snapshot_rank ASC
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AI Operations immutable case evidence not found';
  END IF;

  SELECT d.* INTO v_decision
  FROM ai_ops.decisions d
  WHERE d.case_id = v_case.id
  ORDER BY d.created_at DESC, d.revision DESC, d.id DESC
  LIMIT 1;

  IF v_snapshot_case.domain = 'receivables' AND v_snapshot_case.case_type = 'overdue_invoice' THEN
    WITH evidence_rows AS (
      SELECT * FROM (VALUES
        ('credit_override', 'صاحب قرار تجاوز الائتمان', 'direct', 'دليل مباشر على قرار استثناء ائتماني لهذه الفاتورة.'),
        ('last_due_date_change', 'آخر من عدّل تاريخ الاستحقاق', 'direct', 'دليل مباشر على حوكمة موعد التحصيل لهذه الفاتورة.'),
        ('customer_credit_change', 'آخر من عدّل حد ائتمان العميل', 'supporting', 'دليل حوكمة ائتمانية للعميل؛ لا يثبت وحده ملكية تحصيل هذه الفاتورة.'),
        ('current_customer_rep', 'مندوب العميل الحالي', 'supporting', 'علاقة تشغيل حالية بالعميل وليست قاعدة توجيه جامدة.'),
        ('order_rep', 'مندوب الفاتورة', 'supporting', 'علاقة تجارية بالمعاملة وليست إثباتًا لملكية قرار الائتمان.'),
        ('order_creator', 'منشئ الفاتورة', 'contextual', 'سياق إدخال المعاملة فقط؛ الإنشاء لا يساوي المسؤولية.')
      ) AS x(evidence_key, label, strength, fixed_note)
    )
    SELECT COALESCE(jsonb_agg(
      jsonb_build_object(
        'evidence_type', COALESCE(v_snapshot_case.responsibility_evidence->e.evidence_key->>'evidence_type', e.evidence_key),
        'label', e.label,
        'user_id', v_snapshot_case.responsibility_evidence->e.evidence_key->>'user_id',
        'user_label', v_snapshot_case.responsibility_evidence->e.evidence_key->>'full_name',
        'strength', e.strength,
        'active_work_actor', CASE
          WHEN jsonb_typeof(v_snapshot_case.responsibility_evidence->e.evidence_key->'active_work_actor') = 'boolean'
            THEN (v_snapshot_case.responsibility_evidence->e.evidence_key->>'active_work_actor')::BOOLEAN
          ELSE NULL
        END,
        'occurred_at', v_snapshot_case.responsibility_evidence->e.evidence_key->>'changed_at',
        'note', CASE
          WHEN NULLIF(v_snapshot_case.responsibility_evidence->e.evidence_key->>'reason', '') IS NOT NULL THEN
            e.fixed_note || ' السبب المسجل: ' || left(v_snapshot_case.responsibility_evidence->e.evidence_key->>'reason', 500)
          ELSE e.fixed_note
        END
      )
      ORDER BY CASE e.strength WHEN 'direct' THEN 1 WHEN 'supporting' THEN 2 ELSE 3 END, e.evidence_key
    ), '[]'::JSONB)
    INTO v_evidence
    FROM evidence_rows e
    WHERE jsonb_typeof(v_snapshot_case.responsibility_evidence->e.evidence_key) = 'object';

    IF jsonb_typeof(v_snapshot_case.facts->'existing_active_work') = 'object' THEN
      v_work := jsonb_build_array(jsonb_build_object(
        'work_item_id', v_snapshot_case.facts->'existing_active_work'->>'work_item_id',
        'work_number', (v_snapshot_case.facts->'existing_active_work'->>'work_number')::BIGINT,
        'status', v_snapshot_case.facts->'existing_active_work'->>'status',
        'relation_type', COALESCE(v_snapshot_case.facts->'existing_active_work'->>'relation_type', 'relates_to'),
        'title', COALESCE(v_snapshot_case.facts->'existing_active_work'->>'title', 'Work قائمة مرتبطة بالفاتورة')
      ));
    END IF;

    SELECT COALESCE(jsonb_agg(c.id ORDER BY c.updated_at DESC), '[]'::JSONB)
    INTO v_context_ids
    FROM ai_ops.operational_context c
    WHERE c.status = 'active'
      AND (c.valid_until IS NULL OR c.valid_until > clock_timestamp())
      AND (
        (c.subject_type = 'sales_order' AND c.subject_id = v_snapshot_case.entity_id)
        OR (
          c.subject_type = 'customer'
          AND c.subject_id = NULLIF(v_snapshot_case.facts->>'customer_id', '')::UUID
        )
      );
  END IF;

  RETURN jsonb_build_object(
    'case_id', v_case.id,
    'case_key', v_snapshot_case.case_key,
    'business_date', COALESCE(v_snapshot_case.trust->>'business_date', v_snapshot_case.created_at::DATE::TEXT),
    'facts', CASE
      WHEN v_snapshot_case.domain = 'receivables' AND v_snapshot_case.case_type = 'overdue_invoice' THEN
        jsonb_build_array(
          jsonb_build_object('label', 'الرصيد المتبقي', 'value', COALESCE(v_snapshot_case.facts->>'remaining_amount', '—') || ' EGP'),
          jsonb_build_object('label', 'أيام التأخير', 'value', COALESCE(v_snapshot_case.facts->>'days_overdue', '—') || ' يوم'),
          jsonb_build_object('label', 'تاريخ الاستحقاق', 'value', COALESCE(v_snapshot_case.facts->>'due_date', '—')),
          jsonb_build_object('label', 'حد ائتمان العميل', 'value', COALESCE(v_snapshot_case.facts->>'customer_credit_limit', '—') || ' EGP'),
          jsonb_build_object('label', 'أيام الائتمان الحالية', 'value', COALESCE(v_snapshot_case.facts->>'customer_credit_days', '—') || ' يوم')
        )
      ELSE '[]'::JSONB
    END,
    'responsibility_evidence', v_evidence,
    'existing_work', v_work,
    'relevant_context_ids', v_context_ids,
    'decision_review', jsonb_build_object(
      'decision_type', v_decision.decision_type,
      'concise_rationale', COALESCE(v_decision.concise_rationale, 'لم يصدر قرار Planner لهذه الحالة بعد.'),
      'why_this_owner', v_decision.responsibility_basis->>'why_this_owner',
      'why_now', COALESCE(
        v_decision.responsibility_basis->>'why_now',
        v_decision.management_only_metadata->>'why_now'
      ),
      'confidence', v_decision.confidence,
      'requires_human_review', CASE
        WHEN jsonb_typeof(v_decision.validation_detail->'requires_human_review') = 'boolean'
          THEN (v_decision.validation_detail->>'requires_human_review')::BOOLEAN
        ELSE true
      END
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.ai_ops_get_case_detail(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ai_ops_get_case_detail(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.ai_ops_get_case_detail(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ai_ops_get_case_detail(UUID) TO service_role;

COMMENT ON FUNCTION public.ai_ops_get_case_detail(UUID) IS
  'Lazy management-only AI Operations case drill-down from immutable snapshot evidence. Read-only, permission-gated and separate from worker execution APIs.';

RESET lock_timeout;
RESET statement_timeout;
