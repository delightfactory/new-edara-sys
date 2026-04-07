-- ============================================================
-- 77_analytics_public_rpc_layer.sql
-- Purpose: Expose analytics data securely to frontend via
--          public-schema SECURITY DEFINER functions.
--
-- WHY THIS APPROACH:
--   Supabase PostgREST exposes only schemas listed in
--   db.schemas config (default: public). The analytics schema
--   is NOT in that list. Rather than exposing the raw schema
--   (which widens attack surface), we create thin SECURITY
--   DEFINER wrapper functions in the public schema.
--
--   These functions:
--   1. Run as service_role internally → can bypass RLS on analytics tables
--   2. Enforce their own permission checks via check_permission()
--   3. Are callable from the frontend via supabase.rpc()
--   4. Return pre-aggregated summaries → zero overfetch to browser
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. Availability Probe  (P0 Gate)
--    Frontend calls this first to check if analytics is live.
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.analytics_ping()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, analytics
AS $$
DECLARE
  v_count integer;
BEGIN
  -- Lightweight probe — just count etl_runs rows (no scan of fact tables)
  SELECT COUNT(*) INTO v_count FROM analytics.etl_runs LIMIT 1;

  RETURN jsonb_build_object(
    'available', true,
    'schema',    'analytics',
    'etl_rows',  v_count,
    'checked_at', now()
  );
EXCEPTION
  WHEN undefined_table THEN
    RETURN jsonb_build_object('available', false, 'reason', 'schema_not_deployed');
  WHEN insufficient_privilege THEN
    RETURN jsonb_build_object('available', false, 'reason', 'unauthorized');
  WHEN OTHERS THEN
    RETURN jsonb_build_object('available', false, 'reason', SQLERRM);
END;
$$;
GRANT EXECUTE ON FUNCTION public.analytics_ping() TO authenticated;


-- ─────────────────────────────────────────────────────────────
-- 2. Trust State (P0) — domain-aware permission model
--
--   p_domain controls:
--     NULL or 'all'      → requires reports.sales OR reports.view_all
--     'treasury'         → also accepts reports.financial
--     'ar'               → also accepts reports.targets
--
--   This matches the route-level permission topology in App.tsx exactly.
--   A finance-only user can fetch treasury trust state without needing
--   reports.sales, which would be a privilege escalation.
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.analytics_get_trust_state(
  p_domain  text DEFAULT NULL   -- NULL='all', 'treasury', 'sales', 'ar', 'customers'
)
RETURNS TABLE (
  component_name    text,
  status            text,
  drift_value       numeric,
  last_completed_at timestamptz,
  is_stale          boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, analytics
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_has_view_all   boolean := check_permission(v_uid, 'reports.view_all');
  v_has_sales      boolean := check_permission(v_uid, 'reports.sales');
  v_has_financial  boolean := check_permission(v_uid, 'reports.financial');
  v_has_targets    boolean := check_permission(v_uid, 'reports.targets');
  v_authorized     boolean := false;
BEGIN
  -- Permission check per domain
  -- view_all grants access to everything
  IF v_has_view_all THEN
    v_authorized := true;
  -- Per-domain checks
  ELSIF p_domain = 'treasury' THEN
    -- treasury page is accessible to financial OR sales users
    v_authorized := v_has_financial OR v_has_sales;
  ELSIF p_domain = 'ar' THEN
    -- AR page is accessible to targets OR sales users
    v_authorized := v_has_targets OR v_has_sales;
  ELSE
    -- overview / sales / customers / NULL = sales required
    v_authorized := v_has_sales;
  END IF;

  IF NOT v_authorized THEN
    RAISE EXCEPTION 'analytics_unauthorized:domain=%', COALESCE(p_domain, 'all');
  END IF;

  -- Return all rows, filtered by domain if provided
  RETURN QUERY
  SELECT t.component_name, t.status, t.drift_value, t.last_completed_at, t.is_stale
  FROM analytics.get_system_trust_state() t
  WHERE
    p_domain IS NULL
    OR p_domain = 'all'
    OR (p_domain = 'treasury'  AND t.component_name LIKE '%treasury%')
    OR (p_domain = 'sales'     AND (t.component_name LIKE '%sales%' OR t.component_name = 'GLOBAL_SWEEP'))
    OR (p_domain = 'ar'        AND t.component_name LIKE '%ar_collection%')
    OR (p_domain = 'customers' AND t.component_name LIKE '%customer_health%');

EXCEPTION
  WHEN SQLSTATE 'P0001' THEN
    -- Re-raise our own explicit exceptions
    RAISE;
  WHEN undefined_function THEN
    -- analytics schema deployed but get_system_trust_state() not yet created
    RETURN QUERY SELECT
      'analytics_engine'::text,
      'NOT_DEPLOYED'::text,
      NULL::numeric,
      NULL::timestamptz,
      true;
  WHEN undefined_table THEN
    RETURN QUERY SELECT
      'analytics_engine'::text,
      'NOT_DEPLOYED'::text,
      NULL::numeric,
      NULL::timestamptz,
      true;
END;
$$;

-- Drop old no-arg version if it exists (idempotent)
DROP FUNCTION IF EXISTS public.analytics_get_trust_state();
GRANT EXECUTE ON FUNCTION public.analytics_get_trust_state(text) TO authenticated;




-- ─────────────────────────────────────────────────────────────
-- 3. Sales Summary  (P1 — pre-aggregated, zero overfetch)
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.analytics_sales_summary(
  p_date_from  date,
  p_date_to    date,
  p_rep_id     uuid DEFAULT NULL,
  p_customer_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, analytics
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT check_permission(auth.uid(), 'reports.sales')
     AND NOT check_permission(auth.uid(), 'reports.view_all') THEN
    RAISE EXCEPTION 'Unauthorized: reports.sales permission required';
  END IF;

  SELECT jsonb_build_object(
    'total_revenue',       COALESCE(SUM(net_tax_exclusive_revenue), 0),
    'total_tax',           COALESCE(SUM(tax_amount), 0),
    'total_ar_credit',     COALESCE(SUM(ar_credit_portion_amount), 0),
    'total_gross_revenue', COALESCE(SUM(tax_inclusive_amount), 0),
    'total_returns_value', COALESCE(SUM(return_tax_exclusive_amount), 0),
    'total_gross_qty',     COALESCE(SUM(gross_quantity), 0),
    'total_return_qty',    COALESCE(SUM(return_quantity), 0),
    'total_net_qty',       COALESCE(SUM(net_quantity), 0),
    'row_count',           COUNT(*)
  ) INTO v_result
  FROM analytics.fact_sales_daily_grain
  WHERE date BETWEEN p_date_from AND p_date_to
    AND (p_rep_id IS NULL OR rep_id = p_rep_id)
    AND (p_customer_id IS NULL OR customer_id = p_customer_id);

  RETURN COALESCE(v_result, '{}'::jsonb);
EXCEPTION
  WHEN undefined_table THEN
    RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;
GRANT EXECUTE ON FUNCTION public.analytics_sales_summary(date, date, uuid, uuid) TO authenticated;


-- ─────────────────────────────────────────────────────────────
-- 4. Sales Daily Series (for chart) — aggregated by date only
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.analytics_sales_daily(
  p_date_from  date,
  p_date_to    date,
  p_rep_id     uuid DEFAULT NULL
)
RETURNS TABLE (
  sale_date             date,
  net_revenue           numeric,
  tax_amount            numeric,
  returns_value         numeric,
  gross_qty             numeric,
  net_qty               numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, analytics
AS $$
BEGIN
  IF NOT check_permission(auth.uid(), 'reports.sales')
     AND NOT check_permission(auth.uid(), 'reports.view_all') THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  RETURN QUERY
  SELECT
    f.date,
    SUM(f.net_tax_exclusive_revenue),
    SUM(f.tax_amount),
    SUM(f.return_tax_exclusive_amount),
    SUM(f.gross_quantity),
    SUM(f.net_quantity)
  FROM analytics.fact_sales_daily_grain f
  WHERE f.date BETWEEN p_date_from AND p_date_to
    AND (p_rep_id IS NULL OR f.rep_id = p_rep_id)
  GROUP BY f.date
  ORDER BY f.date;
EXCEPTION
  WHEN undefined_table THEN
    RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;
GRANT EXECUTE ON FUNCTION public.analytics_sales_daily(date, date, uuid) TO authenticated;


-- ─────────────────────────────────────────────────────────────
-- 5. Treasury Summary (pre-aggregated)
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.analytics_treasury_summary(
  p_date_from  date,
  p_date_to    date,
  p_rep_id     uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, analytics
AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Treasury needs broader permission
  IF NOT check_permission(auth.uid(), 'reports.sales')
     AND NOT check_permission(auth.uid(), 'reports.financial')
     AND NOT check_permission(auth.uid(), 'reports.view_all') THEN
    RAISE EXCEPTION 'Unauthorized: reports.financial or reports.sales required';
  END IF;

  SELECT jsonb_build_object(
    'total_inflow',   COALESCE(SUM(gross_inflow_amount), 0),
    'total_outflow',  COALESCE(SUM(gross_outflow_amount), 0),
    'net_cashflow',   COALESCE(SUM(net_cashflow), 0)
  ) INTO v_result
  FROM analytics.fact_treasury_cashflow_daily
  WHERE treasury_date BETWEEN p_date_from AND p_date_to
    AND (p_rep_id IS NULL OR collected_by = p_rep_id);

  RETURN COALESCE(v_result, '{}'::jsonb);
EXCEPTION
  WHEN undefined_table THEN
    RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;
GRANT EXECUTE ON FUNCTION public.analytics_treasury_summary(date, date, uuid) TO authenticated;


-- ─────────────────────────────────────────────────────────────
-- 6. Treasury Daily Series (for chart)
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.analytics_treasury_daily(
  p_date_from  date,
  p_date_to    date,
  p_rep_id     uuid DEFAULT NULL
)
RETURNS TABLE (
  treasury_date       date,
  gross_inflow        numeric,
  gross_outflow       numeric,
  net_cashflow        numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, analytics
AS $$
BEGIN
  IF NOT check_permission(auth.uid(), 'reports.sales')
     AND NOT check_permission(auth.uid(), 'reports.financial')
     AND NOT check_permission(auth.uid(), 'reports.view_all') THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  RETURN QUERY
  SELECT
    f.treasury_date,
    SUM(f.gross_inflow_amount),
    SUM(f.gross_outflow_amount),
    SUM(f.net_cashflow)
  FROM analytics.fact_treasury_cashflow_daily f
  WHERE f.treasury_date BETWEEN p_date_from AND p_date_to
    AND (p_rep_id IS NULL OR f.collected_by = p_rep_id)
  GROUP BY f.treasury_date
  ORDER BY f.treasury_date;
EXCEPTION
  WHEN undefined_table THEN
    RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;
GRANT EXECUTE ON FUNCTION public.analytics_treasury_daily(date, date, uuid) TO authenticated;


-- ─────────────────────────────────────────────────────────────
-- 7. AR Collections Summary (pre-aggregated)
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.analytics_ar_summary(
  p_date_from  date,
  p_date_to    date,
  p_rep_id     uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, analytics
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT check_permission(auth.uid(), 'reports.sales')
     AND NOT check_permission(auth.uid(), 'reports.targets')
     AND NOT check_permission(auth.uid(), 'reports.view_all') THEN
    RAISE EXCEPTION 'Unauthorized: reports.sales or reports.targets required';
  END IF;

  SELECT jsonb_build_object(
    'total_receipt_amount', COALESCE(SUM(receipt_amount), 0),
    'total_refunds',        COALESCE(SUM(cash_refund_amount), 0),
    'total_net_cohort',     COALESCE(SUM(net_cohort_collection), 0)
  ) INTO v_result
  FROM analytics.fact_ar_collections_attributed_to_origin_sale_date
  WHERE origin_sale_delivered_at BETWEEN p_date_from AND p_date_to
    AND (p_rep_id IS NULL OR collected_by = p_rep_id OR original_rep_id = p_rep_id);

  RETURN COALESCE(v_result, '{}'::jsonb);
EXCEPTION
  WHEN undefined_table THEN
    RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;
GRANT EXECUTE ON FUNCTION public.analytics_ar_summary(date, date, uuid) TO authenticated;


-- ─────────────────────────────────────────────────────────────
-- 8. AR Collections Daily Series (for chart)
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.analytics_ar_daily(
  p_date_from  date,
  p_date_to    date,
  p_rep_id     uuid DEFAULT NULL
)
RETURNS TABLE (
  sale_date         date,
  receipt_amount    numeric,
  refund_amount     numeric,
  net_cohort        numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, analytics
AS $$
BEGIN
  IF NOT check_permission(auth.uid(), 'reports.sales')
     AND NOT check_permission(auth.uid(), 'reports.targets')
     AND NOT check_permission(auth.uid(), 'reports.view_all') THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  RETURN QUERY
  SELECT
    f.origin_sale_delivered_at,
    SUM(f.receipt_amount),
    SUM(f.cash_refund_amount),
    SUM(f.net_cohort_collection)
  FROM analytics.fact_ar_collections_attributed_to_origin_sale_date f
  WHERE f.origin_sale_delivered_at BETWEEN p_date_from AND p_date_to
    AND (p_rep_id IS NULL OR f.collected_by = p_rep_id OR f.original_rep_id = p_rep_id)
  GROUP BY f.origin_sale_delivered_at
  ORDER BY f.origin_sale_delivered_at;
EXCEPTION
  WHEN undefined_table THEN
    RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;
GRANT EXECUTE ON FUNCTION public.analytics_ar_daily(date, date, uuid) TO authenticated;


-- ─────────────────────────────────────────────────────────────
-- 9. Customer Health Summary (pre-aggregated + top-N rows)
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.analytics_customer_health_summary(
  p_as_of_date   date,
  p_customer_id  uuid DEFAULT NULL,
  p_limit        integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, analytics
AS $$
DECLARE
  v_stats jsonb;
  v_rows  jsonb;
BEGIN
  IF NOT check_permission(auth.uid(), 'reports.sales')
     AND NOT check_permission(auth.uid(), 'reports.view_all') THEN
    RAISE EXCEPTION 'Unauthorized: reports.sales required';
  END IF;

  -- Aggregate stats
  SELECT jsonb_build_object(
    'total',        COUNT(*),
    'dormant',      COUNT(*) FILTER (WHERE is_dormant),
    'active',       COUNT(*) FILTER (WHERE NOT is_dormant),
    'avg_monetary', ROUND(AVG(monetary_l90d)::numeric, 2),
    'avg_recency',  ROUND(AVG(recency_days)::numeric, 1)
  ) INTO v_stats
  FROM analytics.snapshot_customer_health
  WHERE as_of_date = p_as_of_date
    AND (p_customer_id IS NULL OR customer_id = p_customer_id);

  -- Top-N rows (ordered by monetary value descending)
  SELECT jsonb_agg(row_data ORDER BY (row_data->>'monetary_l90d')::numeric DESC)
  INTO v_rows
  FROM (
    SELECT jsonb_build_object(
      'customer_id',    customer_id,
      'as_of_date',     as_of_date,
      'recency_days',   recency_days,
      'frequency_l90d', frequency_l90d,
      'monetary_l90d',  monetary_l90d,
      'is_dormant',     is_dormant
    ) AS row_data
    FROM analytics.snapshot_customer_health
    WHERE as_of_date = p_as_of_date
      AND (p_customer_id IS NULL OR customer_id = p_customer_id)
    ORDER BY monetary_l90d DESC NULLS LAST
    LIMIT p_limit
  ) sub;

  RETURN jsonb_build_object(
    'stats', COALESCE(v_stats, '{}'::jsonb),
    'rows',  COALESCE(v_rows, '[]'::jsonb)
  );
EXCEPTION
  WHEN undefined_table THEN
    RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;
GRANT EXECUTE ON FUNCTION public.analytics_customer_health_summary(date, uuid, integer) TO authenticated;

-- End of public RPC layer
