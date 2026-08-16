-- ============================================================================
-- AI Operations Planner — Credit / Receivables Case Engine
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply until explicitly reviewed/approved.
-- Depends on: 20260816163504_ai_operations_foundation.sql
--
-- Scope:
--   * internal read kernel for overdue credit invoices
--   * deterministic Cairo business-date semantics
--   * causal/responsibility evidence without unsupported blame inference
--   * exact Work collision detection through existing public.work_links
--   * optional persistence into ai_ops.cases for an already-created snapshot
--
-- Explicitly NOT included:
--   * no source-table ALTER
--   * no source trigger
--   * no source index
--   * no Sales mutation
--   * no Work creation
--   * no browser grant / public RPC
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

-- --------------------------------------------------------------------------
-- Bounded source kernel.
-- Preserves the factual overdue definition already used by the application,
-- but accepts an explicit business date instead of relying on UTC CURRENT_DATE.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ai_ops.credit_overdue_candidates(
  p_business_date DATE,
  p_limit INTEGER DEFAULT 100
)
RETURNS TABLE(
  case_key TEXT,
  severity TEXT,
  order_id UUID,
  order_number TEXT,
  customer_id UUID,
  customer_code TEXT,
  customer_name TEXT,
  remaining_amount NUMERIC,
  delivered_at TIMESTAMPTZ,
  due_date DATE,
  days_overdue INTEGER,
  overdue_bucket TEXT,
  current_customer_rep_id UUID,
  current_customer_rep_name TEXT,
  current_customer_rep_active BOOLEAN,
  order_rep_id UUID,
  order_rep_name TEXT,
  order_rep_active BOOLEAN,
  order_creator_id UUID,
  credit_override BOOLEAN,
  credit_override_by UUID,
  last_due_date_changed_at TIMESTAMPTZ,
  last_due_date_changed_by UUID,
  last_due_date_changed_by_name TEXT,
  last_due_date_reason TEXT,
  linked_work_item_id UUID,
  linked_work_number BIGINT,
  linked_work_status public.work_item_status,
  facts JSONB,
  responsibility_evidence JSONB,
  trust JSONB
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH bounded AS (
    SELECT
      so.id AS order_id,
      so.order_number::TEXT AS order_number,
      so.customer_id,
      c.code::TEXT AS customer_code,
      c.name::TEXT AS customer_name,
      GREATEST(
        0::NUMERIC,
        COALESCE(so.total_amount, 0)
          - COALESCE(so.paid_amount, 0)
          - COALESCE(so.returned_amount, 0)
      )::NUMERIC AS remaining_amount,
      so.delivered_at,
      so.due_date,
      (p_business_date - so.due_date)::INTEGER AS days_overdue,
      CASE
        WHEN (p_business_date - so.due_date) >= 60 THEN 'critical'
        WHEN (p_business_date - so.due_date) >= 30 THEN 'high'
        WHEN (p_business_date - so.due_date) >= 7 THEN 'medium'
        ELSE 'new'
      END AS overdue_bucket,
      CASE
        WHEN (p_business_date - so.due_date) >= 60 THEN 'critical'
        WHEN (p_business_date - so.due_date) >= 30 THEN 'high'
        WHEN (p_business_date - so.due_date) >= 7 THEN 'medium'
        ELSE 'low'
      END AS severity,
      c.assigned_rep_id AS current_customer_rep_id,
      customer_rep.full_name::TEXT AS current_customer_rep_name,
      CASE
        WHEN c.assigned_rep_id IS NULL THEN false
        ELSE private.work_actor_is_active(c.assigned_rep_id)
      END AS current_customer_rep_active,
      so.rep_id AS order_rep_id,
      order_rep.full_name::TEXT AS order_rep_name,
      CASE
        WHEN so.rep_id IS NULL THEN false
        ELSE private.work_actor_is_active(so.rep_id)
      END AS order_rep_active,
      so.created_by_id AS order_creator_id,
      COALESCE(so.credit_override, false) AS credit_override,
      so.credit_override_by,
      due_hist.created_at AS last_due_date_changed_at,
      due_hist.changed_by AS last_due_date_changed_by,
      due_actor.full_name::TEXT AS last_due_date_changed_by_name,
      due_hist.reason::TEXT AS last_due_date_reason,
      linked.work_item_id AS linked_work_item_id,
      linked.work_number AS linked_work_number,
      linked.status AS linked_work_status
    FROM public.sales_orders so
    JOIN public.customers c ON c.id = so.customer_id
    LEFT JOIN public.profiles customer_rep ON customer_rep.id = c.assigned_rep_id
    LEFT JOIN public.profiles order_rep ON order_rep.id = so.rep_id
    LEFT JOIN LATERAL (
      SELECT
        h.created_at,
        h.changed_by,
        h.reason
      FROM public.sales_order_due_date_history h
      WHERE h.order_id = so.id
      ORDER BY h.created_at DESC
      LIMIT 1
    ) due_hist ON true
    LEFT JOIN public.profiles due_actor ON due_actor.id = due_hist.changed_by
    LEFT JOIN LATERAL (
      SELECT
        wi.id AS work_item_id,
        wi.work_number,
        wi.status
      FROM public.work_links wl
      JOIN public.work_items wi ON wi.id = wl.work_item_id
      WHERE wl.entity_type = 'sales_order'
        AND wl.entity_id = so.id
        AND wi.status NOT IN ('done'::public.work_item_status, 'cancelled'::public.work_item_status)
      ORDER BY wi.updated_at DESC, wi.id
      LIMIT 1
    ) linked ON true
    WHERE so.status IN (
      'delivered'::public.sales_order_status,
      'partially_delivered'::public.sales_order_status
    )
      AND so.payment_terms IN ('credit', 'mixed')
      AND so.delivered_at IS NOT NULL
      AND so.due_date IS NOT NULL
      AND so.due_date < p_business_date
      AND GREATEST(
        0::NUMERIC,
        COALESCE(so.total_amount, 0)
          - COALESCE(so.paid_amount, 0)
          - COALESCE(so.returned_amount, 0)
      ) > 0
    ORDER BY
      (p_business_date - so.due_date) DESC,
      GREATEST(
        0::NUMERIC,
        COALESCE(so.total_amount, 0)
          - COALESCE(so.paid_amount, 0)
          - COALESCE(so.returned_amount, 0)
      ) DESC,
      so.id
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500)
  )
  SELECT
    'receivables:overdue_invoice:' || b.order_id::TEXT AS case_key,
    b.severity,
    b.order_id,
    b.order_number,
    b.customer_id,
    b.customer_code,
    b.customer_name,
    b.remaining_amount,
    b.delivered_at,
    b.due_date,
    b.days_overdue,
    b.overdue_bucket,
    b.current_customer_rep_id,
    b.current_customer_rep_name,
    b.current_customer_rep_active,
    b.order_rep_id,
    b.order_rep_name,
    b.order_rep_active,
    b.order_creator_id,
    b.credit_override,
    b.credit_override_by,
    b.last_due_date_changed_at,
    b.last_due_date_changed_by,
    b.last_due_date_changed_by_name,
    b.last_due_date_reason,
    b.linked_work_item_id,
    b.linked_work_number,
    b.linked_work_status,
    jsonb_build_object(
      'order_id', b.order_id,
      'order_number', b.order_number,
      'customer_id', b.customer_id,
      'customer_code', b.customer_code,
      'customer_name', b.customer_name,
      'remaining_amount', b.remaining_amount,
      'delivered_at', b.delivered_at,
      'due_date', b.due_date,
      'days_overdue', b.days_overdue,
      'overdue_bucket', b.overdue_bucket,
      'credit_override', b.credit_override,
      'last_due_date_changed_at', b.last_due_date_changed_at,
      'last_due_date_reason', b.last_due_date_reason,
      'existing_active_work', CASE
        WHEN b.linked_work_item_id IS NULL THEN NULL
        ELSE jsonb_build_object(
          'work_item_id', b.linked_work_item_id,
          'work_number', b.linked_work_number,
          'status', b.linked_work_status
        )
      END
    ) AS facts,
    jsonb_build_object(
      'current_customer_rep', CASE
        WHEN b.current_customer_rep_id IS NULL THEN NULL
        ELSE jsonb_build_object(
          'user_id', b.current_customer_rep_id,
          'full_name', b.current_customer_rep_name,
          'active_work_actor', b.current_customer_rep_active,
          'evidence_type', 'current_customer_assignment'
        )
      END,
      'order_rep', CASE
        WHEN b.order_rep_id IS NULL THEN NULL
        ELSE jsonb_build_object(
          'user_id', b.order_rep_id,
          'full_name', b.order_rep_name,
          'active_work_actor', b.order_rep_active,
          'evidence_type', 'order_rep'
        )
      END,
      'order_creator', jsonb_build_object(
        'user_id', b.order_creator_id,
        'evidence_type', 'order_creator_not_necessarily_accountable'
      ),
      'credit_override', CASE
        WHEN NOT b.credit_override THEN NULL
        ELSE jsonb_build_object(
          'user_id', b.credit_override_by,
          'evidence_type', 'explicit_credit_override'
        )
      END,
      'last_due_date_change', CASE
        WHEN b.last_due_date_changed_at IS NULL THEN NULL
        ELSE jsonb_build_object(
          'changed_at', b.last_due_date_changed_at,
          'user_id', b.last_due_date_changed_by,
          'full_name', b.last_due_date_changed_by_name,
          'reason', b.last_due_date_reason,
          'evidence_type', 'governed_due_date_change'
        )
      END
    ) AS responsibility_evidence,
    jsonb_build_object(
      'source', 'sales_orders',
      'confidence', 'system_record',
      'business_date', p_business_date,
      'remaining_balance_formula', 'total-paid-returned',
      'timezone_semantics', 'explicit_business_date'
    ) AS trust
  FROM bounded b;
$$;

REVOKE ALL ON FUNCTION ai_ops.credit_overdue_candidates(DATE, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION ai_ops.credit_overdue_candidates(DATE, INTEGER) FROM anon;
REVOKE ALL ON FUNCTION ai_ops.credit_overdue_candidates(DATE, INTEGER) FROM authenticated;

COMMENT ON FUNCTION ai_ops.credit_overdue_candidates(DATE, INTEGER) IS
  'Internal bounded overdue-credit candidate kernel. Read-only and deterministic for an explicit business date.';

-- --------------------------------------------------------------------------
-- Persist the bounded candidates into the durable attention-case ledger.
-- Does not resolve missing cases because p_limit may intentionally truncate the
-- candidate set. Case reconciliation is a separate reliability concern.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ai_ops.refresh_credit_cases(
  p_snapshot_id UUID,
  p_business_date DATE,
  p_limit INTEGER DEFAULT 100
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_candidate RECORD;
  v_count INTEGER := 0;
BEGIN
  SELECT * INTO v_snapshot
  FROM ai_ops.snapshots
  WHERE id = p_snapshot_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ai_ops snapshot not found: %', p_snapshot_id;
  END IF;

  FOR v_candidate IN
    SELECT *
    FROM ai_ops.credit_overdue_candidates(p_business_date, p_limit)
  LOOP
    INSERT INTO ai_ops.cases(
      case_key,
      first_snapshot_id,
      last_snapshot_id,
      domain,
      case_type,
      entity_type,
      entity_id,
      attention_class,
      severity,
      first_seen_at,
      last_seen_at,
      source_as_of,
      facts,
      responsibility_evidence,
      trust,
      status,
      state_version,
      updated_at
    ) VALUES (
      v_candidate.case_key,
      p_snapshot_id,
      p_snapshot_id,
      'receivables',
      'overdue_invoice',
      'sales_order',
      v_candidate.order_id,
      'exception',
      v_candidate.severity,
      v_snapshot.generated_at,
      v_snapshot.generated_at,
      v_snapshot.data_as_of,
      v_candidate.facts,
      v_candidate.responsibility_evidence,
      v_candidate.trust,
      'open',
      1,
      clock_timestamp()
    )
    ON CONFLICT (case_key) DO UPDATE
    SET
      last_snapshot_id = EXCLUDED.last_snapshot_id,
      severity = EXCLUDED.severity,
      last_seen_at = EXCLUDED.last_seen_at,
      source_as_of = EXCLUDED.source_as_of,
      facts = EXCLUDED.facts,
      responsibility_evidence = EXCLUDED.responsibility_evidence,
      trust = EXCLUDED.trust,
      status = CASE
        WHEN ai_ops.cases.status IN ('resolved', 'expired') THEN 'open'
        WHEN ai_ops.cases.status = 'suppressed'
          AND ai_ops.cases.suppressed_until IS NOT NULL
          AND ai_ops.cases.suppressed_until > clock_timestamp()
          THEN 'suppressed'
        ELSE ai_ops.cases.status
      END,
      state_version = ai_ops.cases.state_version + 1,
      updated_at = clock_timestamp();

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'snapshot_id', p_snapshot_id,
    'business_date', p_business_date,
    'domain', 'receivables',
    'case_type', 'overdue_invoice',
    'candidates_upserted', v_count,
    'resolution_performed', false
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.refresh_credit_cases(UUID, DATE, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION ai_ops.refresh_credit_cases(UUID, DATE, INTEGER) FROM anon;
REVOKE ALL ON FUNCTION ai_ops.refresh_credit_cases(UUID, DATE, INTEGER) FROM authenticated;

COMMENT ON FUNCTION ai_ops.refresh_credit_cases(UUID, DATE, INTEGER) IS
  'Persists bounded overdue-invoice cases for an existing AI snapshot; never mutates Sales or Work.';

RESET lock_timeout;
RESET statement_timeout;
