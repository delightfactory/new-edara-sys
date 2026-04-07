-- ============================================================
-- 83_analytics_rpc_scope_and_hardening.sql
-- Purpose: Three targeted fixes — additive only.
--
-- A. Row-scope enforcement inside public analytics RPC functions
--    Each function now mirrors the RLS policy from 75 explicitly
--    inside its own WHERE clause, so SECURITY DEFINER does not
--    bypass row-level visibility for scoped users.
--
-- B. REVOKE ALL ... FROM PUBLIC for all public.analytics_* functions
--    Closes the default function privilege surface.
--
-- C. Performance index on analytics.etl_runs(table_name, started_at DESC)
--    Speeds up get_system_trust_state() ROW_NUMBER/PARTITION BY.
--
-- Does NOT touch: 75/76/77/78/79/80/81/82, fact semantics, trust engine.
-- ============================================================


-- ─────────────────────────────────────────────────────────────
-- PART C (index first — fastest, no behavior change)
-- analytics.etl_runs(table_name, started_at DESC)
-- Supports: ROW_NUMBER() OVER (PARTITION BY table_name ORDER BY started_at DESC)
-- in analytics.get_system_trust_state() (75, line 56)
-- ─────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_etl_runs_table_name_started_at
  ON analytics.etl_runs (table_name, started_at DESC);


-- ─────────────────────────────────────────────────────────────
-- Shared helper: build the team_member_ids set for the current user.
-- Used by all scoped RPCs below.
-- Returns an empty ARRAY if user does not have reports.team_performance.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION analytics._scoped_team_ids(p_uid UUID)
RETURNS UUID[]
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, analytics
AS $$
  SELECT CASE
    WHEN check_permission(p_uid, 'reports.team_performance') THEN (
      SELECT COALESCE(array_agg(target.user_id), ARRAY[]::UUID[])
      FROM public.hr_employees target
      JOIN public.hr_employees me ON target.branch_id = me.branch_id
      WHERE me.user_id = p_uid
        AND target.user_id IS NOT NULL
    )
    ELSE ARRAY[]::UUID[]
  END;
$$;

REVOKE ALL ON FUNCTION analytics._scoped_team_ids(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION analytics._scoped_team_ids(UUID) TO service_role;


-- ─────────────────────────────────────────────────────────────
-- PART B: REVOKE PUBLIC execute surface from all analytics_* functions in 77
-- Then re-grant to authenticated only.
-- analytics_ping() is also revoked from public; authenticated can still call it.
-- ─────────────────────────────────────────────────────────────

REVOKE ALL ON FUNCTION public.analytics_ping()                                        FROM PUBLIC;
REVOKE ALL ON FUNCTION public.analytics_get_trust_state(text)                         FROM PUBLIC;
REVOKE ALL ON FUNCTION public.analytics_sales_summary(date, date, uuid, uuid)         FROM PUBLIC;
REVOKE ALL ON FUNCTION public.analytics_sales_daily(date, date, uuid)                 FROM PUBLIC;
REVOKE ALL ON FUNCTION public.analytics_treasury_summary(date, date, uuid)            FROM PUBLIC;
REVOKE ALL ON FUNCTION public.analytics_treasury_daily(date, date, uuid)              FROM PUBLIC;
REVOKE ALL ON FUNCTION public.analytics_ar_summary(date, date, uuid)                  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.analytics_ar_daily(date, date, uuid)                    FROM PUBLIC;
REVOKE ALL ON FUNCTION public.analytics_customer_health_summary(date, uuid, integer)  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.analytics_ping()                                       TO authenticated;
GRANT EXECUTE ON FUNCTION public.analytics_get_trust_state(text)                        TO authenticated;
GRANT EXECUTE ON FUNCTION public.analytics_sales_summary(date, date, uuid, uuid)        TO authenticated;
GRANT EXECUTE ON FUNCTION public.analytics_sales_daily(date, date, uuid)                TO authenticated;
GRANT EXECUTE ON FUNCTION public.analytics_treasury_summary(date, date, uuid)           TO authenticated;
GRANT EXECUTE ON FUNCTION public.analytics_treasury_daily(date, date, uuid)             TO authenticated;
GRANT EXECUTE ON FUNCTION public.analytics_ar_summary(date, date, uuid)                 TO authenticated;
GRANT EXECUTE ON FUNCTION public.analytics_ar_daily(date, date, uuid)                   TO authenticated;
GRANT EXECUTE ON FUNCTION public.analytics_customer_health_summary(date, uuid, integer) TO authenticated;


-- ─────────────────────────────────────────────────────────────
-- PART A: Row-scope enforcement
--
-- Scope model (mirrors 75 RLS exactly):
--
--   view_all  → full aggregate, no row filter
--   financial → full treasury only (no filter on collected_by)
--               no access to sales/AR/customers beyond their other perms
--   sales     → rep_id / collected_by / original_rep_id = auth.uid()
--               OR team scope if reports.team_performance
--   targets   → collected_by / original_rep_id = auth.uid() (AR only)
--               OR team scope if reports.team_performance
--   customers → customer_id IN (assigned to auth.uid() or team)
--
-- Implementation pattern for all scoped functions:
--   1. Pre-compute v_uid, v_view_all, v_team_ids once in DECLARE
--   2. Add a scope condition (v_scope_filter) to every fact-table WHERE clause
--   3. view_all users receive no extra WHERE → full aggregate
-- ─────────────────────────────────────────────────────────────


-- ── analytics_sales_summary ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.analytics_sales_summary(
  p_date_from   date,
  p_date_to     date,
  p_rep_id      uuid DEFAULT NULL,
  p_customer_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, analytics
AS $$
DECLARE
  v_uid      uuid    := auth.uid();
  v_view_all boolean := check_permission(v_uid, 'reports.view_all');
  v_team_ids uuid[];
  v_result   jsonb;
BEGIN
  IF NOT check_permission(v_uid, 'reports.sales') AND NOT v_view_all THEN
    RAISE EXCEPTION 'analytics_unauthorized:domain=sales';
  END IF;

  IF NOT v_view_all THEN
    v_team_ids := analytics._scoped_team_ids(v_uid);
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
    AND (p_rep_id      IS NULL OR rep_id      = p_rep_id)
    AND (p_customer_id IS NULL OR customer_id = p_customer_id)
    -- Row-scope enforcement (view_all bypasses):
    AND (
      v_view_all
      OR rep_id = v_uid
      OR (array_length(v_team_ids, 1) > 0 AND rep_id = ANY(v_team_ids))
    );

  RETURN COALESCE(v_result, '{}'::jsonb);
EXCEPTION
  WHEN SQLSTATE 'P0001' THEN RAISE;
  WHEN undefined_table  THEN RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;


-- ── analytics_sales_daily ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.analytics_sales_daily(
  p_date_from date,
  p_date_to   date,
  p_rep_id    uuid DEFAULT NULL
)
RETURNS TABLE (
  sale_date     date,
  net_revenue   numeric,
  tax_amount    numeric,
  returns_value numeric,
  gross_qty     numeric,
  net_qty       numeric
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, analytics
AS $$
DECLARE
  v_uid      uuid    := auth.uid();
  v_view_all boolean := check_permission(v_uid, 'reports.view_all');
  v_team_ids uuid[];
BEGIN
  IF NOT check_permission(v_uid, 'reports.sales') AND NOT v_view_all THEN
    RAISE EXCEPTION 'analytics_unauthorized:domain=sales';
  END IF;

  IF NOT v_view_all THEN
    v_team_ids := analytics._scoped_team_ids(v_uid);
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
    AND (
      v_view_all
      OR f.rep_id = v_uid
      OR (array_length(v_team_ids, 1) > 0 AND f.rep_id = ANY(v_team_ids))
    )
  GROUP BY f.date
  ORDER BY f.date;
EXCEPTION
  WHEN SQLSTATE 'P0001' THEN RAISE;
  WHEN undefined_table  THEN RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;


-- ── analytics_treasury_summary ───────────────────────────────
-- Scope rules for treasury (from 75 RLS):
--   view_all    → full aggregate
--   financial   → full aggregate (financial role sees all treasury)
--   sales alone → only rows WHERE collected_by = uid OR team
CREATE OR REPLACE FUNCTION public.analytics_treasury_summary(
  p_date_from date,
  p_date_to   date,
  p_rep_id    uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, analytics
AS $$
DECLARE
  v_uid       uuid    := auth.uid();
  v_view_all  boolean := check_permission(v_uid, 'reports.view_all');
  v_financial boolean := check_permission(v_uid, 'reports.financial');
  v_sales     boolean := check_permission(v_uid, 'reports.sales');
  v_team_ids  uuid[];
  v_result    jsonb;
BEGIN
  IF NOT v_view_all AND NOT v_financial AND NOT v_sales THEN
    RAISE EXCEPTION 'analytics_unauthorized:domain=treasury';
  END IF;

  -- sales-only users (no financial, no view_all) get team-scoped rows
  IF NOT v_view_all AND NOT v_financial THEN
    v_team_ids := analytics._scoped_team_ids(v_uid);
  END IF;

  SELECT jsonb_build_object(
    'total_inflow',  COALESCE(SUM(gross_inflow_amount), 0),
    'total_outflow', COALESCE(SUM(gross_outflow_amount), 0),
    'net_cashflow',  COALESCE(SUM(net_cashflow), 0)
  ) INTO v_result
  FROM analytics.fact_treasury_cashflow_daily
  WHERE treasury_date BETWEEN p_date_from AND p_date_to
    AND (p_rep_id IS NULL OR collected_by = p_rep_id)
    AND (
      v_view_all
      OR v_financial                    -- financial sees all treasury rows
      OR collected_by = v_uid
      OR (array_length(v_team_ids, 1) > 0 AND collected_by = ANY(v_team_ids))
    );

  RETURN COALESCE(v_result, '{}'::jsonb);
EXCEPTION
  WHEN SQLSTATE 'P0001' THEN RAISE;
  WHEN undefined_table  THEN RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;


-- ── analytics_treasury_daily ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.analytics_treasury_daily(
  p_date_from date,
  p_date_to   date,
  p_rep_id    uuid DEFAULT NULL
)
RETURNS TABLE (
  treasury_date date,
  gross_inflow  numeric,
  gross_outflow numeric,
  net_cashflow  numeric
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, analytics
AS $$
DECLARE
  v_uid       uuid    := auth.uid();
  v_view_all  boolean := check_permission(v_uid, 'reports.view_all');
  v_financial boolean := check_permission(v_uid, 'reports.financial');
  v_sales     boolean := check_permission(v_uid, 'reports.sales');
  v_team_ids  uuid[];
BEGIN
  IF NOT v_view_all AND NOT v_financial AND NOT v_sales THEN
    RAISE EXCEPTION 'analytics_unauthorized:domain=treasury';
  END IF;

  IF NOT v_view_all AND NOT v_financial THEN
    v_team_ids := analytics._scoped_team_ids(v_uid);
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
    AND (
      v_view_all
      OR v_financial
      OR f.collected_by = v_uid
      OR (array_length(v_team_ids, 1) > 0 AND f.collected_by = ANY(v_team_ids))
    )
  GROUP BY f.treasury_date
  ORDER BY f.treasury_date;
EXCEPTION
  WHEN SQLSTATE 'P0001' THEN RAISE;
  WHEN undefined_table  THEN RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;


-- ── analytics_ar_summary ─────────────────────────────────────
-- Scope: collected_by OR original_rep_id = uid OR team (from 75 RLS)
CREATE OR REPLACE FUNCTION public.analytics_ar_summary(
  p_date_from date,
  p_date_to   date,
  p_rep_id    uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, analytics
AS $$
DECLARE
  v_uid      uuid    := auth.uid();
  v_view_all boolean := check_permission(v_uid, 'reports.view_all');
  v_team_ids uuid[];
  v_result   jsonb;
BEGIN
  IF NOT check_permission(v_uid, 'reports.sales')
     AND NOT check_permission(v_uid, 'reports.targets')
     AND NOT v_view_all THEN
    RAISE EXCEPTION 'analytics_unauthorized:domain=ar';
  END IF;

  IF NOT v_view_all THEN
    v_team_ids := analytics._scoped_team_ids(v_uid);
  END IF;

  SELECT jsonb_build_object(
    'total_receipt_amount', COALESCE(SUM(receipt_amount), 0),
    'total_refunds',        COALESCE(SUM(cash_refund_amount), 0),
    'total_net_cohort',     COALESCE(SUM(net_cohort_collection), 0)
  ) INTO v_result
  FROM analytics.fact_ar_collections_attributed_to_origin_sale_date
  WHERE origin_sale_delivered_at BETWEEN p_date_from AND p_date_to
    AND (p_rep_id IS NULL OR collected_by = p_rep_id OR original_rep_id = p_rep_id)
    AND (
      v_view_all
      OR collected_by    = v_uid
      OR original_rep_id = v_uid
      OR (array_length(v_team_ids, 1) > 0
          AND (collected_by = ANY(v_team_ids) OR original_rep_id = ANY(v_team_ids)))
    );

  RETURN COALESCE(v_result, '{}'::jsonb);
EXCEPTION
  WHEN SQLSTATE 'P0001' THEN RAISE;
  WHEN undefined_table  THEN RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;


-- ── analytics_ar_daily ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.analytics_ar_daily(
  p_date_from date,
  p_date_to   date,
  p_rep_id    uuid DEFAULT NULL
)
RETURNS TABLE (
  sale_date      date,
  receipt_amount numeric,
  refund_amount  numeric,
  net_cohort     numeric
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, analytics
AS $$
DECLARE
  v_uid      uuid    := auth.uid();
  v_view_all boolean := check_permission(v_uid, 'reports.view_all');
  v_team_ids uuid[];
BEGIN
  IF NOT check_permission(v_uid, 'reports.sales')
     AND NOT check_permission(v_uid, 'reports.targets')
     AND NOT v_view_all THEN
    RAISE EXCEPTION 'analytics_unauthorized:domain=ar';
  END IF;

  IF NOT v_view_all THEN
    v_team_ids := analytics._scoped_team_ids(v_uid);
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
    AND (
      v_view_all
      OR f.collected_by    = v_uid
      OR f.original_rep_id = v_uid
      OR (array_length(v_team_ids, 1) > 0
          AND (f.collected_by = ANY(v_team_ids) OR f.original_rep_id = ANY(v_team_ids)))
    )
  GROUP BY f.origin_sale_delivered_at
  ORDER BY f.origin_sale_delivered_at;
EXCEPTION
  WHEN SQLSTATE 'P0001' THEN RAISE;
  WHEN undefined_table  THEN RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;


-- ── analytics_customer_health_summary ────────────────────────
-- Scope: customer_id IN (assigned to uid) OR team (from 75 RLS)
CREATE OR REPLACE FUNCTION public.analytics_customer_health_summary(
  p_as_of_date  date,
  p_customer_id uuid    DEFAULT NULL,
  p_limit       integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, analytics
AS $$
DECLARE
  v_uid            uuid    := auth.uid();
  v_view_all       boolean := check_permission(v_uid, 'reports.view_all');
  v_team_ids       uuid[];
  v_allowed_custs  uuid[];
  v_stats          jsonb;
  v_rows           jsonb;
BEGIN
  IF NOT check_permission(v_uid, 'reports.sales') AND NOT v_view_all THEN
    RAISE EXCEPTION 'analytics_unauthorized:domain=customers';
  END IF;

  IF NOT v_view_all THEN
    v_team_ids := analytics._scoped_team_ids(v_uid);

    -- Build set of customer IDs this user is allowed to see
    SELECT array_agg(id) INTO v_allowed_custs
    FROM public.customers
    WHERE assigned_rep_id = v_uid
      OR (array_length(v_team_ids, 1) > 0 AND assigned_rep_id = ANY(v_team_ids));
  END IF;

  -- Aggregate stats (scoped)
  SELECT jsonb_build_object(
    'total',        COUNT(*),
    'dormant',      COUNT(*) FILTER (WHERE is_dormant),
    'active',       COUNT(*) FILTER (WHERE NOT is_dormant),
    'avg_monetary', ROUND(AVG(monetary_l90d)::numeric, 2),
    'avg_recency',  ROUND(AVG(recency_days)::numeric, 1)
  ) INTO v_stats
  FROM analytics.snapshot_customer_health
  WHERE as_of_date = p_as_of_date
    AND (p_customer_id IS NULL OR customer_id = p_customer_id)
    AND (
      v_view_all
      OR (array_length(v_allowed_custs, 1) > 0 AND customer_id = ANY(v_allowed_custs))
    );

  -- Top-N rows (scoped)
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
      AND (
        v_view_all
        OR (array_length(v_allowed_custs, 1) > 0 AND customer_id = ANY(v_allowed_custs))
      )
    ORDER BY monetary_l90d DESC NULLS LAST
    LIMIT p_limit
  ) sub;

  RETURN jsonb_build_object(
    'stats', COALESCE(v_stats, '{}'::jsonb),
    'rows',  COALESCE(v_rows,  '[]'::jsonb)
  );
EXCEPTION
  WHEN SQLSTATE 'P0001' THEN RAISE;
  WHEN undefined_table  THEN RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;

-- Re-apply grants (REVOKE already done above, these are explicit re-grants)
GRANT EXECUTE ON FUNCTION public.analytics_sales_summary(date, date, uuid, uuid)        TO authenticated;
GRANT EXECUTE ON FUNCTION public.analytics_sales_daily(date, date, uuid)                TO authenticated;
GRANT EXECUTE ON FUNCTION public.analytics_treasury_summary(date, date, uuid)           TO authenticated;
GRANT EXECUTE ON FUNCTION public.analytics_treasury_daily(date, date, uuid)             TO authenticated;
GRANT EXECUTE ON FUNCTION public.analytics_ar_summary(date, date, uuid)                 TO authenticated;
GRANT EXECUTE ON FUNCTION public.analytics_ar_daily(date, date, uuid)                   TO authenticated;
GRANT EXECUTE ON FUNCTION public.analytics_customer_health_summary(date, uuid, integer) TO authenticated;
