-- ============================================================
-- 82_analytics_customer_health_split_aggregation.sql
-- Purpose: Fix P0 aggregation multiplication bug in
--          internal_refresh_snapshot_customer_health
--
-- Bug in migration 81:
--   health_stats joined BOTH full_sales_history (n rows/customer) AND
--   recent_sales (m rows/customer) in the same FROM block before GROUP BY.
--   This produced up to n × m intermediate rows per (customer, date).
--   MAX(fsh.sale_date) was still correct (MAX survives duplication),
--   but COUNT(rs.*) and SUM(rs.total_amount) were each multiplied by n,
--   making frequency_l90d and monetary_l90d wrong by a factor of n.
--
-- Fix:
--   Two fully independent CTEs, each joined and aggregated separately:
--
--   recency_agg:  dates_cross × full_sales_history → GROUP BY (date, customer)
--                 produces one column: last_sale_date
--                 No contact with recent_sales at all.
--
--   recent_agg:   dates_cross × recent_sales → GROUP BY (date, customer)
--                 produces two columns: freq_l90d, monetary_l90d
--                 No contact with full_sales_history at all.
--
--   final_stats:  JOIN recency_agg and recent_agg on (as_of_date, customer_id)
--                 — a JOIN of two already-aggregated result sets, so
--                 each (customer, date) appears exactly once in both sides.
--                 No multiplication possible.
--
-- Chunk architecture (plan/chunk) from migration 80 is NOT touched.
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

  SELECT MIN(d) - 90 INTO v_history_from FROM unnest(p_target_dates) d;

  DELETE FROM analytics.snapshot_customer_health WHERE as_of_date = ANY(p_target_dates);

  WITH

  -- Customers active in this chunk's target dates
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

  -- Full sales history — used ONLY by recency_agg
  -- Cannot be bounded to 90 days: a customer's last sale may be years ago
  full_sales_history AS (
    SELECT
      so.customer_id,
      DATE(COALESCE(so.delivered_at, so.order_date)) AS sale_date
    FROM public.sales_orders so
    JOIN active_customers ac ON ac.customer_id = so.customer_id
    WHERE so.status IN ('delivered', 'completed')
  ),

  -- Bounded history — used ONLY by recent_agg
  -- 90-day lookback from earliest candidate date is sufficient for
  -- freq_l90d and monetary_l90d across all dates in this chunk
  recent_sales AS (
    SELECT
      so.customer_id,
      DATE(COALESCE(so.delivered_at, so.order_date)) AS sale_date,
      so.total_amount
    FROM public.sales_orders so
    JOIN active_customers ac ON ac.customer_id = so.customer_id
    WHERE so.status IN ('delivered', 'completed')
      AND DATE(COALESCE(so.delivered_at, so.order_date)) >= v_history_from
  ),

  -- Unavoidable (D × C) cross — bounded by chunk size
  dates_cross AS (
    SELECT d.candidate_date, ac.customer_id
    FROM unnest(p_target_dates) AS d(candidate_date)
    CROSS JOIN active_customers ac
  ),

  -- ── Path A: recency only ─────────────────────────────────────
  -- Joins dates_cross with full_sales_history EXCLUSIVELY.
  -- Produces one row per (as_of_date, customer_id).
  -- MAX with FILTER restores the as-of-date-correct semantics:
  -- only sales at or before candidate_date are considered.
  recency_agg AS (
    SELECT
      dc.candidate_date                              AS as_of_date,
      dc.customer_id,
      MAX(fsh.sale_date) FILTER (
        WHERE fsh.sale_date <= dc.candidate_date
      )                                              AS last_sale_date
    FROM dates_cross dc
    LEFT JOIN full_sales_history fsh
      ON fsh.customer_id = dc.customer_id
    GROUP BY dc.candidate_date, dc.customer_id
  ),

  -- ── Path B: frequency + monetary only ───────────────────────
  -- Joins dates_cross with recent_sales EXCLUSIVELY.
  -- Produces one row per (as_of_date, customer_id).
  -- No contact with full_sales_history → no multiplication.
  recent_agg AS (
    SELECT
      dc.candidate_date                              AS as_of_date,
      dc.customer_id,
      COUNT(rs.sale_date) FILTER (
        WHERE rs.sale_date >= (dc.candidate_date - INTERVAL '90 days')
          AND rs.sale_date <= dc.candidate_date
      )                                              AS freq_l90d,
      COALESCE(SUM(rs.total_amount) FILTER (
        WHERE rs.sale_date >= (dc.candidate_date - INTERVAL '90 days')
          AND rs.sale_date <= dc.candidate_date
      ), 0)                                          AS monetary_l90d
    FROM dates_cross dc
    LEFT JOIN recent_sales rs
      ON rs.customer_id = dc.customer_id
    GROUP BY dc.candidate_date, dc.customer_id
  ),

  -- ── Join two already-aggregated results ─────────────────────
  -- Both sides are 1 row per (as_of_date, customer_id).
  -- JOIN of two 1:1 keyed sets → no multiplication possible.
  final_stats AS (
    SELECT
      r.as_of_date,
      r.customer_id,
      r.last_sale_date,
      COALESCE(f.freq_l90d, 0)     AS freq_l90d,
      COALESCE(f.monetary_l90d, 0) AS monetary_l90d
    FROM recency_agg r
    JOIN recent_agg  f USING (as_of_date, customer_id)
  )

  INSERT INTO analytics.snapshot_customer_health
    (as_of_date, customer_id, recency_days, frequency_l90d, monetary_l90d, is_dormant)
  SELECT
    as_of_date,
    customer_id,
    CASE WHEN last_sale_date IS NOT NULL
         THEN (as_of_date - last_sale_date)
         ELSE NULL
    END                                                  AS recency_days,
    freq_l90d,
    monetary_l90d,
    CASE WHEN last_sale_date IS NULL              THEN false
         WHEN (as_of_date - last_sale_date) > 90  THEN true
         ELSE                                          false
    END                                                  AS is_dormant
  FROM final_stats
  ON CONFLICT (as_of_date, customer_id) DO UPDATE SET
    recency_days   = EXCLUDED.recency_days,
    frequency_l90d = EXCLUDED.frequency_l90d,
    monetary_l90d  = EXCLUDED.monetary_l90d,
    is_dormant     = EXCLUDED.is_dormant;
END;
$$;

GRANT EXECUTE ON PROCEDURE analytics.internal_refresh_snapshot_customer_health(DATE[]) TO service_role;
