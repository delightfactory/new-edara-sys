-- ============================================================================
-- AI Operations Planner — Management Case Replay Correction
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply until explicitly reviewed/approved.
-- Depends on: 20260816171000_ai_operations_admin_read_gateway.sql
--
-- Corrects two audit invariants:
--   1) a decision is reviewed against evidence from THE SAME run, not a newer run
--   2) relevant operational context comes from the frozen snapshot evidence,
--      not from mutable current operational_context rows
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '30s';

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
  v_context_items JSONB := '[]'::JSONB;
  v_context_ids JSONB := '[]'::JSONB;
  v_context_coverage JSONB := '{}'::JSONB;
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

  SELECT d.* INTO v_decision
  FROM ai_ops.decisions d
  WHERE d.case_id = v_case.id
  ORDER BY d.created_at DESC, d.revision DESC, d.id DESC
  LIMIT 1;

  IF v_decision.id IS NOT NULL THEN
    SELECT sc.* INTO v_snapshot_case
    FROM ai_ops.snapshot_cases sc
    JOIN ai_ops.snapshots s ON s.id = sc.snapshot_id
    WHERE sc.case_id = v_case.id
      AND s.run_id = v_decision.run_id
    ORDER BY sc.snapshot_rank ASC
    LIMIT 1;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'decision-time immutable evidence not found for decision %', v_decision.id;
    END IF;
  ELSE
    SELECT sc.* INTO v_snapshot_case
    FROM ai_ops.snapshot_cases sc
    JOIN ai_ops.snapshots s ON s.id = sc.snapshot_id
    WHERE sc.case_id = v_case.id
    ORDER BY s.generated_at DESC, sc.snapshot_rank ASC
    LIMIT 1;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'AI Operations immutable case evidence not found';
    END IF;
  END IF;

  v_context_items := CASE
    WHEN jsonb_typeof(v_snapshot_case.operational_context->'items') = 'array'
      THEN v_snapshot_case.operational_context->'items'
    ELSE '[]'::JSONB
  END;

  SELECT COALESCE(jsonb_agg(item->'id'), '[]'::JSONB)
  INTO v_context_ids
  FROM jsonb_array_elements(v_context_items) item
  WHERE jsonb_typeof(item->'id') = 'string';

  v_context_coverage := jsonb_build_object(
    'total', COALESCE((v_snapshot_case.operational_context->>'total')::INTEGER, 0),
    'captured', COALESCE((v_snapshot_case.operational_context->>'captured')::INTEGER, 0),
    'truncated', COALESCE((v_snapshot_case.operational_context->>'truncated')::BOOLEAN, false)
  );

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
    'frozen_context', v_context_items,
    'context_coverage', v_context_coverage,
    'decision_review', jsonb_build_object(
      'decision_type', v_decision.decision_type,
      'concise_rationale', COALESCE(v_decision.concise_rationale, 'لم يصدر قرار Planner لهذه الحالة بعد.'),
      'why_this_owner', v_decision.responsibility_basis->>'why_this_owner',
      'why_now', COALESCE(v_decision.responsibility_basis->>'why_now', v_decision.management_only_metadata->>'why_now'),
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
  'Management case review aligned to the exact decision run and its immutable facts/causal evidence/governed context. Read-only and permission-gated.';

RESET lock_timeout;
RESET statement_timeout;
