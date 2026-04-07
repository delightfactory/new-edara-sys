-- ============================================================
-- 81_analytics_customer_health_correctness_fix.sql
-- Purpose: Fix P0 semantic bug in internal_refresh_snapshot_customer_health
--
-- Bug in migration 80:
--   last_sale_per_customer computed MAX(sale_date) across ALL history globally,
--   then applied this single value to every candidate_date.
--   This broke the as-of-date contract:
--     customer bought on 2026-01-05,
--     as_of_date = 2026-01-01 → last_sale_date = 2026-01-05 (future leak)
--     → recency_days = 01-01 - 01-05 = negative
--     → is_dormant becomes meaningless
--
-- Fix:
--   Restore MAX(sale_date) FILTER (WHERE sale_date <= candidate_date)
--   computed per (customer, candidate_date) inside health_stats.
--   This is the original correct semantics from migration 76.
--
--   Performance approach is preserved correctly:
--   - full_sales_history: ALL history for active customers
--     (required for accurate last_sale_date — cannot be bounded by 90 days)
--   - recent_sales: bounded to (min_target_date - 90) onward
--     (sufficient for freq_l90d and monetary_l90d)
--   - health_stats LEFT JOINs both sources and applies FILTER per date
--
-- Backfill architecture (plan/chunk) from migration 80 is NOT touched.
-- Sales grain rewrite from migration 80 is NOT touched.
-- ============================================================

CREATE OR REPLACE PROCEDURE analytics.internal_refresh_snapshot_customer_health(
  p_target_dates DATE[]
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_history_from DATE;
BEGIN
  IF array_length(p_target_dates, 1) IS NULL THEN RETURN; END IF;

  -- Earliest point we need for the 90-day monetary/freq window.
  -- History beyond this date is NOT needed for freq/monetary.
  -- Full history IS still needed for last_sale_date recency.
  SELECT MIN(d) - 90 INTO v_history_from FROM unnest(p_target_dates) d;

  DELETE FROM analytics.snapshot_customer_health WHERE as_of_date = ANY(p_target_dates);

  WITH

  -- Customers active in the target chunk only
  active_customers AS (
    SELECT DISTINCT customer_id
    FROM public.sales_orders
    WHERE DATE(COALESCE(delivered_at, order_date)) = ANY(p_target_dates)
      AND status IN ('delivered', 'completed')
    UNION
    SELECT DISTINCT customer_id
    FROM public.customer_ledger
    WHERE DATE(created_at) = ANY(p_target_dates)
  ),

  -- Full sales history for active customers
  -- Used for: MAX(sale_date) FILTER (WHERE sale_date <= candidate_date)
  -- Cannot be bounded to 90 days — a customer's last sale might be 200 days ago
  full_sales_history AS (
    SELECT
      so.customer_id,
      DATE(COALESCE(so.delivered_at, so.order_date)) AS sale_date,
      so.total_amount
    FROM public.sales_orders so
    JOIN active_customers ac ON ac.customer_id = so.customer_id
    WHERE so.status IN ('delivered', 'completed')
  ),

  -- Bounded history for frequency/monetary (90-day lookback from earliest target date)
  -- Eliminates old records that would never appear in any 90-day window
  -- for any of the candidate dates in this chunk
  recent_sales AS (
    SELECT customer_id, sale_date, total_amount
    FROM full_sales_history
    WHERE sale_date >= v_history_from
  ),

  -- (D × C) cross product: unavoidable for as-of-date computation.
  -- Bounded by chunk size (D ≤ 7) and active customers (C).
  dates_cross AS (
    SELECT d.candidate_date, ac.customer_id
    FROM unnest(p_target_dates) AS d(candidate_date)
    CROSS JOIN active_customers ac
  ),

  -- Aggregate per (customer, candidate_date):
  --   last_sale_date → from full_sales_history with FILTER (sale_date <= candidate_date)
  --                    This is the as-of-date-correct semantics restored from migration 76.
  --                    No future sale leaks into an earlier as_of_date row.
  --   freq_l90d      → from recent_sales (bounded source, same result as full_sales filtered)
  --   monetary_l90d  → from recent_sales (same)
  health_stats AS (
    SELECT
      dc.candidate_date                           AS as_of_date,
      dc.customer_id,

      -- ← THE FIX: filter-based per date, not a global pre-computed MAX
      MAX(fsh.sale_date) FILTER (
        WHERE fsh.sale_date <= dc.candidate_date
      )                                           AS last_sale_date,

      COUNT(rs.sale_date) FILTER (
        WHERE rs.sale_date >= (dc.candidate_date - INTERVAL '90 days')
          AND rs.sale_date <= dc.candidate_date
      )                                           AS freq_l90d,

      COALESCE(SUM(rs.total_amount) FILTER (
        WHERE rs.sale_date >= (dc.candidate_date - INTERVAL '90 days')
          AND rs.sale_date <= dc.candidate_date
      ), 0)                                       AS monetary_l90d

    FROM dates_cross dc
    LEFT JOIN full_sales_history fsh ON fsh.customer_id = dc.customer_id
    LEFT JOIN recent_sales       rs  ON rs.customer_id  = dc.customer_id
    GROUP BY dc.candidate_date, dc.customer_id
  )

  INSERT INTO analytics.snapshot_customer_health
    (as_of_date, customer_id, recency_days, frequency_l90d, monetary_l90d, is_dormant)
  SELECT
    as_of_date,
    customer_id,
    -- recency_days is null if customer has no sales at or before as_of_date
    CASE WHEN last_sale_date IS NOT NULL
         THEN (as_of_date - last_sale_date)
         ELSE NULL
    END                                               AS recency_days,
    freq_l90d,
    monetary_l90d,
    CASE WHEN last_sale_date IS NULL             THEN false
         WHEN (as_of_date - last_sale_date) > 90 THEN true
         ELSE                                         false
    END                                               AS is_dormant
  FROM health_stats
  ON CONFLICT (as_of_date, customer_id) DO UPDATE SET
    recency_days   = EXCLUDED.recency_days,
    frequency_l90d = EXCLUDED.frequency_l90d,
    monetary_l90d  = EXCLUDED.monetary_l90d,
    is_dormant     = EXCLUDED.is_dormant;
END;
$$;

GRANT EXECUTE ON PROCEDURE analytics.internal_refresh_snapshot_customer_health(DATE[]) TO service_role;
