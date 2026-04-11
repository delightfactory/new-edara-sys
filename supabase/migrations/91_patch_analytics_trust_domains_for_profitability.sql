-- ==============================================================================================
-- Migration 91: Patch Analytics Trust Domains for Profitability
-- Consolidates Phase 1, Phase 2, and Phase 3 components into public trust state domains.
-- ==============================================================================================

CREATE OR REPLACE FUNCTION public.analytics_get_trust_state(
  p_domain  text DEFAULT NULL
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
  IF v_has_view_all THEN
    v_authorized := true;
  ELSIF p_domain = 'treasury' THEN
    v_authorized := v_has_financial OR v_has_sales;
  ELSIF p_domain = 'ar' THEN
    v_authorized := v_has_targets OR v_has_sales;
  ELSIF p_domain = 'targets' THEN
    v_authorized := v_has_targets OR v_has_sales;
  ELSIF p_domain IN ('profit_overview', 'branch_profitability', 'allocation_quality') THEN
    v_authorized := v_has_financial;
  ELSE
    -- 'all' | 'sales' | 'customers' | NULL => sales required
    -- NOTE: 'all' intentionally does NOT grant access to reports.financial-only users.
    -- Financial users access profitability trust state through their dedicated domains
    -- (profit_overview, branch_profitability, allocation_quality).
    -- This preserves the baseline contract from migration 80.
    v_authorized := v_has_sales;
  END IF;

  IF NOT v_authorized THEN
    RAISE EXCEPTION 'analytics_unauthorized:domain=%', COALESCE(p_domain, 'all');
  END IF;

  RETURN QUERY
  SELECT t.component_name, t.status, t.drift_value, t.last_completed_at, t.is_stale
  FROM analytics.get_system_trust_state() t
  WHERE
    p_domain IS NULL
    OR p_domain = 'all'
    OR (p_domain = 'treasury'  AND t.component_name LIKE '%treasury%')
    OR (p_domain = 'sales'     AND (t.component_name LIKE '%sales%'
                                    OR t.component_name LIKE '%geography%'
                                    OR t.component_name = 'GLOBAL_SWEEP'))
    OR (p_domain = 'ar'        AND t.component_name LIKE '%ar_collection%')
    OR (p_domain = 'customers' AND (t.component_name LIKE '%customer_health%'
                                    OR t.component_name LIKE '%customer_risk%'))
    OR (p_domain = 'targets'   AND t.component_name LIKE '%target_attainment%')
    OR (p_domain = 'profit_overview' AND t.component_name = 'fact_profit_daily')
    OR (p_domain = 'branch_profitability' AND (t.component_name LIKE '%branch_profit%' OR t.component_name LIKE '%gross_profit_daily_grain%'))
    OR (p_domain = 'allocation_quality' AND (t.component_name LIKE '%data_quality_daily' OR t.component_name LIKE '%snapshot_branch_allocation_weights%'));

EXCEPTION
  WHEN SQLSTATE 'P0001' THEN
    RAISE;
  WHEN undefined_function THEN
    RETURN QUERY SELECT
      'analytics_engine'::text, 'NOT_DEPLOYED'::text,
      NULL::numeric, NULL::timestamptz, true;
  WHEN undefined_table THEN
    RETURN QUERY SELECT
      'analytics_engine'::text, 'NOT_DEPLOYED'::text,
      NULL::numeric, NULL::timestamptz, true;
END;
$$;
GRANT EXECUTE ON FUNCTION public.analytics_get_trust_state(text) TO authenticated;
