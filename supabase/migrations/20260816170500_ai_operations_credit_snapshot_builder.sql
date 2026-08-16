-- ============================================================================
-- AI Operations Planner — Atomic Credit Snapshot Builder
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply until explicitly reviewed/approved.
-- Depends on:
--   * 20260816163504_ai_operations_foundation.sql
--   * 20260816164500_ai_operations_snapshot_case_evidence.sql
--   * 20260816165500_ai_operations_credit_case_engine.sql
--   * 20260816170000_ai_operations_credit_snapshot_capture.sql
--
-- Builds one immutable first-domain snapshot for an already-created planner run.
-- It is planner-internal: no browser/worker grants are added here.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.build_credit_snapshot(
  p_run_id UUID,
  p_case_limit INTEGER DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_run ai_ops.planner_runs%ROWTYPE;
  v_settings ai_ops.settings%ROWTYPE;
  v_existing ai_ops.snapshots%ROWTYPE;
  v_snapshot_id UUID;
  v_now TIMESTAMPTZ := clock_timestamp();
  v_case_limit INTEGER;
  v_total_cases BIGINT := 0;
  v_total_overdue NUMERIC := 0;
  v_customer_count BIGINT := 0;
  v_max_days INTEGER := 0;
  v_critical_count BIGINT := 0;
  v_high_count BIGINT := 0;
  v_medium_count BIGINT := 0;
  v_new_count BIGINT := 0;
  v_returned_cases INTEGER := 0;
  v_circuit_breaker BOOLEAN := false;
  v_ar_status TEXT;
  v_ar_completed_at TIMESTAMPTZ;
  v_ar_stale BOOLEAN := true;
  v_domain_state TEXT := 'partial';
  v_snapshot_status TEXT := 'ready';
  v_trust JSONB;
  v_pulse JSONB;
  v_coverage JSONB;
  v_payload JSONB;
  v_payload_bytes INTEGER;
  v_capture JSONB;
BEGIN
  -- One builder at a time per run, including retry races.
  PERFORM pg_advisory_xact_lock(hashtextextended('ai_ops:credit_snapshot:' || p_run_id::TEXT, 0));

  SELECT * INTO v_run
  FROM ai_ops.planner_runs
  WHERE id = p_run_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ai_ops planner run not found: %', p_run_id;
  END IF;

  SELECT * INTO v_existing
  FROM ai_ops.snapshots
  WHERE run_id = p_run_id;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'snapshot_id', v_existing.id,
      'run_id', p_run_id,
      'business_date', v_run.business_date,
      'status', v_existing.snapshot_status,
      'idempotent_reuse', true,
      'generated_at', v_existing.generated_at,
      'data_as_of', v_existing.data_as_of,
      'coverage', v_existing.coverage,
      'payload_bytes', v_existing.payload_bytes
    );
  END IF;

  IF v_run.status NOT IN ('pending', 'claimed', 'reasoning') THEN
    RAISE EXCEPTION 'planner run status does not allow snapshot build: %', v_run.status;
  END IF;

  SELECT * INTO v_settings
  FROM ai_ops.settings
  WHERE singleton = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AI Operations settings are not initialized';
  END IF;

  v_case_limit := LEAST(
    GREATEST(COALESCE(p_case_limit, v_settings.max_cases_per_snapshot), 1),
    v_settings.max_cases_per_snapshot
  );

  -- Full aggregate over the same deployed overdue semantics used by the
  -- candidate kernel. This is one bounded-domain scan of the current orders;
  -- candidate/evidence extraction is the second scan. No historical raw dump.
  SELECT
    count(*)::BIGINT,
    COALESCE(sum(base.remaining_amount), 0)::NUMERIC,
    count(DISTINCT base.customer_id)::BIGINT,
    COALESCE(max(base.days_overdue), 0)::INTEGER,
    count(*) FILTER (WHERE base.days_overdue >= 60)::BIGINT,
    count(*) FILTER (WHERE base.days_overdue >= 30 AND base.days_overdue < 60)::BIGINT,
    count(*) FILTER (WHERE base.days_overdue >= 7 AND base.days_overdue < 30)::BIGINT,
    count(*) FILTER (WHERE base.days_overdue < 7)::BIGINT
  INTO
    v_total_cases,
    v_total_overdue,
    v_customer_count,
    v_max_days,
    v_critical_count,
    v_high_count,
    v_medium_count,
    v_new_count
  FROM (
    SELECT
      so.customer_id,
      (v_run.business_date - so.due_date)::INTEGER AS days_overdue,
      GREATEST(
        0::NUMERIC,
        COALESCE(so.total_amount, 0)
          - COALESCE(so.paid_amount, 0)
          - COALESCE(so.returned_amount, 0)
      )::NUMERIC AS remaining_amount
    FROM public.sales_orders so
    WHERE so.status IN (
      'delivered'::public.sales_order_status,
      'partially_delivered'::public.sales_order_status
    )
      AND so.payment_terms IN ('credit', 'mixed')
      AND so.delivered_at IS NOT NULL
      AND so.due_date IS NOT NULL
      AND so.due_date < v_run.business_date
      AND GREATEST(
        0::NUMERIC,
        COALESCE(so.total_amount, 0)
          - COALESCE(so.paid_amount, 0)
          - COALESCE(so.returned_amount, 0)
      ) > 0
  ) base;

  v_returned_cases := LEAST(v_total_cases, v_case_limit)::INTEGER;

  -- A sudden >10x overflow (with a floor of 100) is treated as an operational
  -- anomaly first, never as permission to create hundreds of actions.
  v_circuit_breaker := v_total_cases > GREATEST(v_settings.max_cases_per_snapshot * 10, 100);

  BEGIN
    SELECT t.status, t.last_completed_at, t.is_stale
    INTO v_ar_status, v_ar_completed_at, v_ar_stale
    FROM analytics.get_system_trust_state() t
    WHERE t.component_name = 'fact_ar_collections_attributed_to_origin_sale_date'
    LIMIT 1;
  EXCEPTION
    WHEN undefined_function OR undefined_table OR invalid_schema_name THEN
      v_ar_status := 'NOT_DEPLOYED';
      v_ar_completed_at := NULL;
      v_ar_stale := true;
  END;

  -- This source is operational/current-state, not an accounting close. Even
  -- with healthy AR analytics we deliberately expose it as partial evidence.
  IF v_ar_stale OR v_ar_status IN ('FAILED', 'PARTIAL_FAILURE', 'BLOCKED', 'RUNNING', 'NOT_DEPLOYED') THEN
    v_domain_state := 'partial';
  ELSE
    v_domain_state := 'partial';
  END IF;

  IF v_circuit_breaker THEN
    v_snapshot_status := 'partial';
  END IF;

  v_trust := jsonb_build_object(
    'domain_status', jsonb_build_array(jsonb_build_object(
      'domain', 'receivables',
      'state', v_domain_state,
      'as_of', v_now,
      'note', CASE
        WHEN v_ar_stale THEN
          'مصدر التأخير تشغيلي مباشر؛ إشارة Analytics AR قديمة/غير مكتملة، لذلك لا يُسمح باعتبار القيمة إقفالًا محاسبيًا.'
        ELSE
          'مصدر التأخير تشغيلي مباشر ويطابق تقرير overdue الحالي؛ Analytics AR سليمة كإشارة مساندة، لكن القيمة ليست إقفالًا محاسبيًا نهائيًا.'
      END,
      'analytics_component_status', COALESCE(v_ar_status, 'UNKNOWN'),
      'analytics_completed_at', v_ar_completed_at
    ))
  );

  v_pulse := jsonb_build_object(
    'metrics', jsonb_build_array(
      jsonb_build_object(
        'key', 'overdue_ar',
        'label', 'مديونيات متأخرة',
        'value', round(v_total_overdue, 2)::TEXT,
        'trend', 'unknown',
        'tone', CASE WHEN v_total_overdue > 0 THEN 'danger' ELSE 'good' END,
        'hint', 'تعرض التعرض المتأخر التشغيلي؛ المسؤولية لا تُستنتج من الرقم وحده.'
      ),
      jsonb_build_object(
        'key', 'overdue_invoices',
        'label', 'فواتير متأخرة',
        'value', v_total_cases::TEXT,
        'trend', 'unknown',
        'tone', CASE WHEN v_total_cases > 0 THEN 'warning' ELSE 'good' END,
        'hint', 'عدد الفواتير ذات رصيد موجب بعد تاريخ الاستحقاق.'
      ),
      jsonb_build_object(
        'key', 'overdue_customers',
        'label', 'عملاء عليهم تأخير',
        'value', v_customer_count::TEXT,
        'trend', 'unknown',
        'tone', 'neutral',
        'hint', 'عدد العملاء المميزين داخل التعرض المتأخر.'
      ),
      jsonb_build_object(
        'key', 'max_days_overdue',
        'label', 'أقصى تأخير',
        'value', v_max_days::TEXT || ' يوم',
        'trend', 'unknown',
        'tone', CASE WHEN v_max_days >= 60 THEN 'danger' WHEN v_max_days >= 30 THEN 'warning' ELSE 'neutral' END,
        'hint', 'أقدم تعرض متأخر ضمن الصورة الحالية.'
      )
    )
  );

  v_coverage := jsonb_build_object(
    'total_cases', v_total_cases,
    'returned_cases', v_returned_cases,
    'case_limit', v_case_limit,
    'has_more', v_total_cases > v_returned_cases,
    'circuit_breaker', v_circuit_breaker,
    'buckets', jsonb_build_object(
      'critical', v_critical_count,
      'high', v_high_count,
      'medium', v_medium_count,
      'new', v_new_count
    )
  );

  v_payload := jsonb_build_object(
    'domains', jsonb_build_array('receivables'),
    'case_family', 'overdue_invoice',
    'business_date', v_run.business_date,
    'planner_policy_version', v_run.planner_policy_version,
    'tool_contract_version', v_run.tool_contract_version,
    'normal_context_contains_raw_history', false,
    'free_text_policy', 'bounded_untrusted_data'
  );

  v_payload_bytes := octet_length(convert_to(
    jsonb_build_object(
      'trust', v_trust,
      'company_pulse', v_pulse,
      'coverage', v_coverage,
      'payload', v_payload
    )::TEXT,
    'UTF8'
  ));

  INSERT INTO ai_ops.snapshots(
    run_id,
    payload_version,
    generated_at,
    data_as_of,
    snapshot_status,
    trust,
    company_pulse,
    coverage,
    payload,
    payload_bytes
  ) VALUES (
    p_run_id,
    'credit-overdue-v1',
    v_now,
    v_now,
    v_snapshot_status,
    v_trust,
    v_pulse,
    v_coverage,
    v_payload,
    v_payload_bytes
  )
  RETURNING id INTO v_snapshot_id;

  -- Same transaction: if evidence capture fails, the snapshot insert rolls back.
  v_capture := ai_ops.refresh_credit_cases(v_snapshot_id, v_run.business_date, v_case_limit);

  RETURN jsonb_build_object(
    'snapshot_id', v_snapshot_id,
    'run_id', p_run_id,
    'business_date', v_run.business_date,
    'status', v_snapshot_status,
    'idempotent_reuse', false,
    'generated_at', v_now,
    'data_as_of', v_now,
    'coverage', v_coverage,
    'payload_bytes', v_payload_bytes,
    'capture', v_capture
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.build_credit_snapshot(UUID, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION ai_ops.build_credit_snapshot(UUID, INTEGER) FROM anon;
REVOKE ALL ON FUNCTION ai_ops.build_credit_snapshot(UUID, INTEGER) FROM authenticated;

COMMENT ON FUNCTION ai_ops.build_credit_snapshot(UUID, INTEGER) IS
  'Atomic/idempotent planner-internal Credit snapshot builder. Bounded cases, immutable evidence, explicit business date and circuit-breaker coverage.';

RESET lock_timeout;
RESET statement_timeout;
