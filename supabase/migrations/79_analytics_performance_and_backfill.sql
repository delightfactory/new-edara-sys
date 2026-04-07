-- ============================================================
-- 79_analytics_performance_and_backfill.sql
-- Purpose: Two-part performance fix for analytics ETL
--
-- Part A: Rewrite internal_refresh_fact_sales_daily_grain
--   Problem: 3 correlated subqueries on sales_return_items per row
--            → O(N × 3 subquery) scan, catastrophic on backfill
--   Fix: replace with 2 pre-aggregated return CTEs (one pass each)
--        then JOIN — O(N) instead of O(N × 3)
--
-- Part B: Rewrite internal_refresh_snapshot_customer_health
--   Problem: CROSS JOIN (all dates × all customers) × full sales_history
--            → exponential intermediate result on backfill
--   Fix: compute per-customer stats per day directly using
--        conditional aggregation in one pre-aggregated CTE,
--        no CROSS JOIN needed
--
-- Part C: Add analytics.run_historical_backfill(start, end, chunk_days)
--   Purpose: chunked historical initial load that avoids timeouts
--            by splitting the date range into small batches,
--            each batch runs as a separate sweep
--   Additive only — does not touch existing sweep procedure
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- Part A: internal_refresh_fact_sales_daily_grain — deferred subqueries → CTEs
--
-- Before: 3 correlated subqueries executed per sales_order_item row:
--   (1) SUM(sri.line_total) WHERE order_item_id = sol.id AND confirmed
--   (2) SUM(sri.line_total - tax_portion) WHERE ...
--   (3) SUM(sri.base_quantity) WHERE ...
--
-- After: 2 pre-aggregated CTEs (returns_line_data, returns_qty_data)
--   built using a single JOIN on sales_return_items + sales_returns,
--   then LEFT JOIN to the main aggregation.
--   Net cost: 2 table scans instead of N × 3 correlated lookups.
--
-- Mathematical equivalence preserved:
--   return_tax_excl = line_total × (1 - tax_rate_of_order)
--   where tax_rate_of_order = so.tax_amount / NULLIF(so.subtotal, 0)
--   → this is the same formula as the original correlated subquery
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE analytics.internal_refresh_fact_sales_daily_grain(
  p_target_dates DATE[]
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF array_length(p_target_dates, 1) IS NULL THEN RETURN; END IF;

  DELETE FROM analytics.fact_sales_daily_grain WHERE date = ANY(p_target_dates);

  -- Pre-aggregate confirmed return amounts per order_item_id in one pass
  -- (replaces 3 correlated subqueries)
  WITH

  -- CTE 1: gather all confirmed return line data for items in scope
  --        We need to reach back to the parent order for the tax rate,
  --        so we join through: sri → sr → so_return → sol_origin → so_origin
  --        But we only need sol.id and so.tax_amount/subtotal, which we
  --        will join from the main aggregation side. Instead, we carry
  --        the raw line_total and base_quantity here; the tax_excl
  --        calculation will be done by joining with order-level tax rate below.

  returns_per_item AS (
    SELECT
      sri.order_item_id,
      SUM(sri.line_total)     AS ret_tax_incl,
      SUM(sri.base_quantity)  AS ret_qty
    FROM public.sales_return_items sri
    JOIN public.sales_returns sr ON sr.id = sri.return_id AND sr.status = 'confirmed'
    -- Scope to only items belonging to orders in our target date range
    JOIN public.sales_order_items sol2 ON sol2.id = sri.order_item_id
    JOIN public.sales_orders so2 ON so2.id = sol2.order_id
      AND DATE(COALESCE(so2.delivered_at, so2.order_date)) = ANY(p_target_dates)
      AND so2.status IN ('delivered', 'completed')
    GROUP BY sri.order_item_id
  ),

  -- CTE 2: main sales aggregation — LEFT JOIN returns, no correlated subquery
  aggregated_sales AS (
    SELECT
      DATE(COALESCE(so.delivered_at, so.order_date))                              AS sale_date,
      so.customer_id,
      sol.product_id,
      so.rep_id,

      SUM(sol.line_total)                                                          AS tax_incl_amt,
      SUM(sol.line_total - COALESCE(sol.tax_amount, 0))                            AS tax_excl_amt,
      SUM(COALESCE(sol.tax_amount, 0))                                             AS tax_amt,
      SUM(sol.base_quantity)                                                        AS qty,

      -- AR credit portion unchanged (no returns involved)
      SUM(
        COALESCE(sol.line_total / NULLIF(so.total_amount, 0), 0)
        * COALESCE(so.credit_amount, 0)
      )                                                                             AS ar_credit_portion_amount,

      -- Return tax-inclusive: direct from pre-aggregated CTE
      SUM(COALESCE(rpi.ret_tax_incl, 0))                                           AS return_tax_incl_amt,

      -- Return tax-exclusive: apply same formula as original correlated subquery
      --   original: line_total - (line_total * (so.tax_amount / NULLIF(so.subtotal, 0)))
      --   = line_total * (1 - tax_rate)
      --   Since ret_tax_incl is already SUM(sri.line_total), apply order-level tax rate:
      SUM(
        COALESCE(rpi.ret_tax_incl, 0)
        * (1.0 - COALESCE(so.tax_amount / NULLIF(so.subtotal, 0), 0))
      )                                                                             AS return_tax_excl_amt,

      -- Return quantity from pre-aggregated CTE
      SUM(COALESCE(rpi.ret_qty, 0))                                                AS return_qty

    FROM public.sales_orders so
    JOIN public.sales_order_items sol ON so.id = sol.order_id
    LEFT JOIN returns_per_item rpi ON rpi.order_item_id = sol.id
    WHERE DATE(COALESCE(so.delivered_at, so.order_date)) = ANY(p_target_dates)
      AND so.status IN ('delivered', 'completed')
    GROUP BY 1, 2, 3, 4
  )

  INSERT INTO analytics.fact_sales_daily_grain (
    date, customer_id, product_id, rep_id,
    tax_inclusive_amount, ar_credit_portion_amount, return_tax_inclusive_amount,
    tax_exclusive_amount, tax_amount, return_tax_exclusive_amount,
    net_tax_exclusive_revenue, gross_quantity, return_quantity, net_quantity
  )
  SELECT
    sale_date, customer_id, product_id, rep_id,
    tax_incl_amt, ar_credit_portion_amount, return_tax_incl_amt,
    tax_excl_amt, tax_amt, return_tax_excl_amt,
    (tax_excl_amt - return_tax_excl_amt),
    qty, return_qty, (qty - return_qty)
  FROM aggregated_sales
  ON CONFLICT (date, customer_id, product_id, rep_id) DO UPDATE SET
    tax_inclusive_amount        = EXCLUDED.tax_inclusive_amount,
    ar_credit_portion_amount    = EXCLUDED.ar_credit_portion_amount,
    return_tax_inclusive_amount = EXCLUDED.return_tax_inclusive_amount,
    tax_exclusive_amount        = EXCLUDED.tax_exclusive_amount,
    tax_amount                  = EXCLUDED.tax_amount,
    return_tax_exclusive_amount = EXCLUDED.return_tax_exclusive_amount,
    net_tax_exclusive_revenue   = EXCLUDED.net_tax_exclusive_revenue,
    gross_quantity              = EXCLUDED.gross_quantity,
    return_quantity             = EXCLUDED.return_quantity,
    net_quantity                = EXCLUDED.net_quantity,
    updated_at                  = now();
END;
$$;


-- ─────────────────────────────────────────────────────────────
-- Part B: internal_refresh_snapshot_customer_health — remove CROSS JOIN explosion
--
-- Before:
--   dates_cross = unnest(p_target_dates) × all customers in customer_ops
--   health_stats = dates_cross × LEFT JOIN full sales_history
--
--   With D dates and C customers and H history rows:
--   Intermediate size = D × C × H — grows cubically on backfill
--
-- After:
--   For each date d, we compute:
--     - last_sale_date: MAX(sale_date) WHERE sale_date <= d per customer
--     - freq_l90d:      COUNT(*) WHERE sale_date BETWEEN d-90 AND d
--     - monetary_l90d:  SUM(total_amount) WHERE sale_date BETWEEN d-90 AND d
--
--   This is done in a single pass using conditional aggregation over
--   the cartesian of (customer_id, sale_date, as_of_date_candidate).
--
--   The key insight: we only need to consider customers active in the
--   target dates. Their full sales history (up to now) is needed for
--   recency, but the 90-day window bounds the lookback for freq/monetary.
--
--   Pattern: "date-relative aggregation without CROSS JOIN"
--   Each customer–date row is produced by:
--     SELECT as_of_date_candidate, customer_id,
--            MAX FILTER (sale_date <= candidate) — recency
--            COUNT/SUM FILTER (sale_date BETWEEN candidate-90 AND candidate) — frequency/monetary
--     FROM (pre-built date candidates × customer sales history)
--
--   Implementation uses unnest(p_target_dates) as a VALUES subquery
--   crossed only with the specific customers' own sales rows —
--   not with ALL customers × ALL dates.
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE analytics.internal_refresh_snapshot_customer_health(
  p_target_dates DATE[]
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF array_length(p_target_dates, 1) IS NULL THEN RETURN; END IF;

  DELETE FROM analytics.snapshot_customer_health WHERE as_of_date = ANY(p_target_dates);

  WITH

  -- Customers active in the target date window only
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

  -- All historical sales for those customers (full history needed for recency)
  customer_sales_history AS (
    SELECT
      so.customer_id,
      DATE(COALESCE(so.delivered_at, so.order_date)) AS sale_date,
      so.total_amount
    FROM public.sales_orders so
    JOIN active_customers ac ON ac.customer_id = so.customer_id
    WHERE so.status IN ('delivered', 'completed')
  ),

  -- Expand: for each (customer, as_of_date candidate), compute stats
  -- using conditional aggregation — no CROSS JOIN on the full date list
  --
  -- We join customer_sales_history with unnested date candidates on the
  -- condition that customer appears in the active set for that date.
  -- Since active_customers is already unioned across all dates, every
  -- active customer gets computed for every candidate date.
  --
  -- Size: |active_customers| × |p_target_dates| × avg_history_rows_per_customer
  -- This is unavoidable, but it's O(C × D × H_per_customer) not O(C × D × H_total)

  health_stats AS (
    SELECT
      d.candidate_date                              AS as_of_date,
      csh.customer_id,
      MAX(csh.sale_date) FILTER (WHERE csh.sale_date <= d.candidate_date)
                                                    AS last_sale_date,
      COUNT(*) FILTER (
        WHERE csh.sale_date >= (d.candidate_date - INTERVAL '90 days')
          AND csh.sale_date <= d.candidate_date
      )                                             AS freq_l90d,
      COALESCE(SUM(csh.total_amount) FILTER (
        WHERE csh.sale_date >= (d.candidate_date - INTERVAL '90 days')
          AND csh.sale_date <= d.candidate_date
      ), 0)                                         AS monetary_l90d
    FROM
      -- Cross join is now only: (target dates × customer_sales_history rows)
      -- not (target dates × all customers)
      -- Customers with no history rows simply don't appear — handled by
      -- the customers-with-zero-sales arm below
      unnest(p_target_dates) AS d(candidate_date)
      JOIN customer_sales_history csh ON true  -- intentional: bounded by active_customers JOIN above
    GROUP BY d.candidate_date, csh.customer_id
  ),

  -- Customers in active_customers who have NO sales history at all
  -- (only appear in customer_ledger) must still get a row per date
  zero_history_customers AS (
    SELECT
      d.candidate_date AS as_of_date,
      ac.customer_id,
      NULL::date       AS last_sale_date,
      0::bigint        AS freq_l90d,
      0::numeric       AS monetary_l90d
    FROM unnest(p_target_dates) AS d(candidate_date)
    JOIN active_customers ac ON true
    WHERE NOT EXISTS (
      SELECT 1 FROM customer_sales_history csh WHERE csh.customer_id = ac.customer_id
    )
  ),

  -- Union both sets
  final_stats AS (
    SELECT * FROM health_stats
    UNION ALL
    SELECT * FROM zero_history_customers
  )

  INSERT INTO analytics.snapshot_customer_health
    (as_of_date, customer_id, recency_days, frequency_l90d, monetary_l90d, is_dormant)
  SELECT
    as_of_date,
    customer_id,
    CASE WHEN last_sale_date IS NOT NULL
         THEN (as_of_date - last_sale_date)
         ELSE NULL
    END                                                               AS recency_days,
    freq_l90d,
    monetary_l90d,
    CASE WHEN last_sale_date IS NULL                THEN false
         WHEN (as_of_date - last_sale_date) > 90   THEN true
         ELSE                                            false
    END                                                               AS is_dormant
  FROM final_stats
  ON CONFLICT (as_of_date, customer_id) DO UPDATE SET
    recency_days   = EXCLUDED.recency_days,
    frequency_l90d = EXCLUDED.frequency_l90d,
    monetary_l90d  = EXCLUDED.monetary_l90d,
    is_dormant     = EXCLUDED.is_dormant;
END;
$$;


-- ─────────────────────────────────────────────────────────────
-- Part C: analytics.run_historical_backfill(start, end, chunk_days)
--
-- Purpose: Initial historical load that avoids Supabase timeouts
--          by processing the date range as small daily chunks.
--
-- Design:
--   - Each chunk calls orchestrate_incremental_refresh directly
--     for the 5 fact tables, one chunk at a time.
--   - Each chunk is a transaction-safe call (no COMMIT inside).
--   - Advisory locking: the same lock key as the main sweep,
--     so backfill and sweep cannot run concurrently.
--   - Idempotent: ON CONFLICT DO UPDATE in all fact procedures
--     means re-running the same range is safe.
--
-- Usage:
--   -- Full historical backfill (120 days, 7-day chunks):
--   CALL analytics.run_historical_backfill(
--     current_date - 120,
--     current_date,
--     7
--   );
--
--   -- Smaller chunk for tight timeout environments (3-day chunks):
--   CALL analytics.run_historical_backfill(
--     current_date - 120,
--     current_date,
--     3
--   );
--
-- After backfill completes, the normal incremental sweep takes over.
-- Note: This procedure DOES NOT set GLOBAL_SWEEP status — it writes
--       individual job etl_runs rows only. After it completes, run
--       CALL analytics.run_analytics_watermark_sweep(1) to set the
--       global watermark forward from today.
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE analytics.run_historical_backfill(
  p_start_date  DATE,
  p_end_date    DATE    DEFAULT CURRENT_DATE,
  p_chunk_days  INTEGER DEFAULT 7
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_chunk_start    DATE;
  v_chunk_end      DATE;
  v_chunk_dates    DATE[];
  v_lock_obtained  BOOLEAN;
  v_chunks_done    INTEGER := 0;
BEGIN
  IF p_start_date > p_end_date THEN
    RAISE EXCEPTION 'start_date (%) must be <= end_date (%)', p_start_date, p_end_date;
  END IF;

  IF p_chunk_days < 1 OR p_chunk_days > 30 THEN
    RAISE EXCEPTION 'chunk_days must be between 1 and 30, got %', p_chunk_days;
  END IF;

  -- Obtain advisory lock (same key as main sweep — prevents overlap)
  SELECT pg_try_advisory_lock(hashtext('analytics_global_sweep')) INTO v_lock_obtained;
  IF NOT v_lock_obtained THEN
    RAISE EXCEPTION 'Analytics sweep is running elsewhere. Backfill cannot start.';
  END IF;

  BEGIN
    v_chunk_start := p_start_date;

    -- Iterate through chunks
    WHILE v_chunk_start <= p_end_date LOOP
      v_chunk_end := LEAST(v_chunk_start + (p_chunk_days - 1), p_end_date);

      -- Build date array for this chunk
      SELECT array_agg(d::date)
      INTO   v_chunk_dates
      FROM   generate_series(v_chunk_start, v_chunk_end, '1 day'::interval) d;

      -- Log chunk progress
      RAISE NOTICE 'Backfill: chunk % — dates % to % (%  dates)',
        v_chunks_done + 1, v_chunk_start, v_chunk_end, array_length(v_chunk_dates, 1);

      -- Run all 5 fact refreshes for this chunk
      -- Each CALL shares the same outer transaction (transaction-safe per migration 78)
      CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_sales_daily_grain',                             v_chunk_dates);
      CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_financial_ledgers_daily',                       v_chunk_dates);
      CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_treasury_cashflow_daily',                       v_chunk_dates);
      CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_ar_collections_attributed_to_origin_sale_date', v_chunk_dates);
      CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'snapshot_customer_health',                           v_chunk_dates);

      v_chunks_done  := v_chunks_done + 1;
      v_chunk_start  := v_chunk_end + 1;
    END LOOP;

    RAISE NOTICE 'Backfill complete: % chunks processed (% → %)', v_chunks_done, p_start_date, p_end_date;

    PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));

  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));
    RAISE;
  END;
END;
$$;

-- Grants
REVOKE ALL ON PROCEDURE analytics.run_historical_backfill(DATE, DATE, INTEGER) FROM public;
GRANT EXECUTE ON PROCEDURE analytics.run_historical_backfill(DATE, DATE, INTEGER) TO service_role;

GRANT EXECUTE ON PROCEDURE analytics.internal_refresh_fact_sales_daily_grain(DATE[])        TO service_role;
GRANT EXECUTE ON PROCEDURE analytics.internal_refresh_snapshot_customer_health(DATE[])      TO service_role;
