-- ============================================================
-- 80_analytics_backfill_architecture_fix.sql
-- Replaces the flawed backfill design from migration 79.
-- Additive only — does not touch 75/76/77/78 or remove 79.
--
-- What this migration does:
--   PART A: Re-apply the correct sales grain rewrite from 79
--           (the pre-aggregated returns CTE was directionally correct)
--
--   PART B: Honest customer health rewrite
--           The (dates × customers × history) cross product is
--           unavoidable in this computation. This migration explains
--           WHY, keeps the correct approach, and bounds it correctly.
--           The only real fix for the backfill case is small chunk sizes
--           — not a different SQL pattern.
--
--   PART C: plan_historical_backfill() — returns chunk rows only, no execution
--
--   PART D: run_historical_backfill_chunk(start, end) — ONE chunk per CALL
--           No loops. No internal iteration. Single bounded execution.
-- ============================================================


-- ─────────────────────────────────────────────────────────────
-- PART A: internal_refresh_fact_sales_daily_grain
--
-- WHY this was slow:
--   For every row in sales_order_items (sol), 3 correlated subqueries ran:
--     SELECT SUM(sri.line_total) FROM sales_return_items WHERE order_item_id = sol.id ...
--     SELECT SUM(sri.line_total - ...) FROM sales_return_items WHERE order_item_id = sol.id ...
--     SELECT SUM(sri.base_quantity) FROM sales_return_items WHERE order_item_id = sol.id ...
--   Each subquery = index lookup + aggregation, repeated N_items × 3 times.
--   On a 120-day backfill with thousands of items → millions of subquery executions.
--
-- WHY the pre-CTE approach is correct:
--   We build returns_per_item once: scan sales_return_items+sales_returns once,
--   scoped to the target date window, then LEFT JOIN to the main query.
--   Result: 1 scan instead of N_items × 3 scans.
--
-- Tax-exclusive formula preserved exactly:
--   Original: sri.line_total - (sri.line_total × (so.tax_amount / NULLIF(so.subtotal, 0)))
--           = sri.line_total × (1 − tax_rate_of_order)
--   New:      rpi.ret_tax_incl × (1 − so.tax_amount / NULLIF(so.subtotal, 0))
--   Identical — we carry ret_tax_incl from the CTE, apply the order-level rate at JOIN time.
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE analytics.internal_refresh_fact_sales_daily_grain(
  p_target_dates DATE[]
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF array_length(p_target_dates, 1) IS NULL THEN RETURN; END IF;

  DELETE FROM analytics.fact_sales_daily_grain WHERE date = ANY(p_target_dates);

  WITH

  -- Single scan of sales_return_items, scoped to target-date order items only.
  -- This replaces 3 correlated subqueries.
  returns_per_item AS (
    SELECT
      sri.order_item_id,
      SUM(sri.line_total)    AS ret_tax_incl,
      SUM(sri.base_quantity) AS ret_qty
    FROM public.sales_return_items sri
    JOIN public.sales_returns sr
      ON sr.id = sri.return_id AND sr.status = 'confirmed'
    -- Narrow scope to items whose parent order falls in target dates
    JOIN public.sales_order_items sol_scope
      ON sol_scope.id = sri.order_item_id
    JOIN public.sales_orders so_scope
      ON so_scope.id = sol_scope.order_id
     AND DATE(COALESCE(so_scope.delivered_at, so_scope.order_date)) = ANY(p_target_dates)
     AND so_scope.status IN ('delivered', 'completed')
    GROUP BY sri.order_item_id
  ),

  -- Main aggregation — LEFT JOIN the pre-built returns
  aggregated_sales AS (
    SELECT
      DATE(COALESCE(so.delivered_at, so.order_date))      AS sale_date,
      so.customer_id,
      sol.product_id,
      so.rep_id,

      SUM(sol.line_total)                                  AS tax_incl_amt,
      SUM(sol.line_total - COALESCE(sol.tax_amount, 0))   AS tax_excl_amt,
      SUM(COALESCE(sol.tax_amount, 0))                    AS tax_amt,
      SUM(sol.base_quantity)                               AS qty,

      SUM(
        COALESCE(sol.line_total / NULLIF(so.total_amount, 0), 0)
        * COALESCE(so.credit_amount, 0)
      )                                                    AS ar_credit_portion_amount,

      -- Return tax-inclusive: from CTE, no sub-SELECT
      SUM(COALESCE(rpi.ret_tax_incl, 0))                  AS return_tax_incl_amt,

      -- Return tax-exclusive: same formula as original, applied after JOIN
      SUM(
        COALESCE(rpi.ret_tax_incl, 0)
        * (1.0 - COALESCE(so.tax_amount / NULLIF(so.subtotal, 0), 0))
      )                                                    AS return_tax_excl_amt,

      SUM(COALESCE(rpi.ret_qty, 0))                        AS return_qty

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
-- PART B: internal_refresh_snapshot_customer_health
--
-- Honest statement about the inherent cross product:
--
--   Computing "as-of-date" stats per (customer, date) pair
--   fundamentally requires: for each (customer × date), look
--   at that customer's sale history relative to that date.
--   This means intermediate size = |customers| × |dates| × |history_per_customer|.
--   There is no SQL pattern that avoids this completely.
--
-- What WAS wrong in the original (76):
--   customer_ops = customers active ON THE TARGET DATES (good, bounded)
--   dates_cross = unnest(p_target_dates) CROSS JOIN customer_ops
--   → for D dates × C customers × H_full_history = problematic at large D
--
-- What we change:
--   1. Bound sales_history to the relevant lookback window:
--      We only need history from MIN(p_target_dates) - 90 days onward
--      to compute freq_l90d and monetary_l90d for the target dates.
--      For recency (last_sale_date), we still need full history — but
--      we separate that into a lightweight MAX scan.
--   2. Split into two focused CTEs rather than one giant join:
--      (a) recent_sales: history within 90-day window (bounded by lookback)
--      (b) last_sale_lookup: just MAX(sale_date) per customer (lightweight)
--   3. This reduces intermediate size significantly for large D values:
--      Before: D × C × H_ALL
--      After:  D × C × H_90days  (for monetary/freq)
--            + C × 1              (for recency — just one MAX per customer)
--
-- Residual honest statement:
--   The (D × C) cross product in dates_cross is still present and unavoidable.
--   The fix is: keep D small — use run_historical_backfill_chunk with D ≤ 7.
--   For incremental sweep, detect_affected_dates typically returns D = 1–5.
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE analytics.internal_refresh_snapshot_customer_health(
  p_target_dates DATE[]
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_history_from DATE;
BEGIN
  IF array_length(p_target_dates, 1) IS NULL THEN RETURN; END IF;

  -- The lookback window for freq/monetary is 90 days from the earliest target date.
  -- We only need history from this point forward for the monetary calculation.
  SELECT MIN(d) - 90 INTO v_history_from FROM unnest(p_target_dates) d;

  DELETE FROM analytics.snapshot_customer_health WHERE as_of_date = ANY(p_target_dates);

  WITH

  -- Customers active in the target date window
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

  -- Per-customer last sale date (full history scan, but cheaply via index on sale_date)
  -- This is a single aggregation — not per (customer × date)
  last_sale_per_customer AS (
    SELECT so.customer_id, MAX(DATE(COALESCE(so.delivered_at, so.order_date))) AS last_sale_date
    FROM public.sales_orders so
    JOIN active_customers ac ON ac.customer_id = so.customer_id
    WHERE so.status IN ('delivered', 'completed')
    GROUP BY so.customer_id
  ),

  -- Sales history bounded to the 90-day lookback window
  -- (reduced from full history to H_90days rows per customer)
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

  -- (D × C) cross product — unavoidable for as-of-date computation
  -- Bounded by: D = chunk size (≤ 7 for backfill, ≤ 5 for incremental)
  --             C = active customers in window (typically tens to hundreds)
  dates_cross AS (
    SELECT d.candidate_date, ac.customer_id
    FROM unnest(p_target_dates) AS d(candidate_date)
    CROSS JOIN active_customers ac
  ),

  -- Aggregate stats: join dates_cross with bounded recent_sales
  -- Intermediate size: (D × C) × H_90days — not (D × C) × H_ALL
  health_stats AS (
    SELECT
      dc.candidate_date                            AS as_of_date,
      dc.customer_id,
      ls.last_sale_date,
      COUNT(rs.sale_date) FILTER (
        WHERE rs.sale_date >= (dc.candidate_date - INTERVAL '90 days')
          AND rs.sale_date <= dc.candidate_date
      )                                            AS freq_l90d,
      COALESCE(SUM(rs.total_amount) FILTER (
        WHERE rs.sale_date >= (dc.candidate_date - INTERVAL '90 days')
          AND rs.sale_date <= dc.candidate_date
      ), 0)                                        AS monetary_l90d
    FROM dates_cross dc
    LEFT JOIN last_sale_per_customer ls ON ls.customer_id = dc.customer_id
    LEFT JOIN recent_sales rs          ON rs.customer_id = dc.customer_id
    GROUP BY dc.candidate_date, dc.customer_id, ls.last_sale_date
  )

  INSERT INTO analytics.snapshot_customer_health
    (as_of_date, customer_id, recency_days, frequency_l90d, monetary_l90d, is_dormant)
  SELECT
    as_of_date,
    customer_id,
    CASE WHEN last_sale_date IS NOT NULL
         THEN (as_of_date - last_sale_date)
         ELSE NULL
    END                                                AS recency_days,
    freq_l90d,
    monetary_l90d,
    CASE WHEN last_sale_date IS NULL              THEN false
         WHEN (as_of_date - last_sale_date) > 90  THEN true
         ELSE                                          false
    END                                                AS is_dormant
  FROM health_stats
  ON CONFLICT (as_of_date, customer_id) DO UPDATE SET
    recency_days   = EXCLUDED.recency_days,
    frequency_l90d = EXCLUDED.frequency_l90d,
    monetary_l90d  = EXCLUDED.monetary_l90d,
    is_dormant     = EXCLUDED.is_dormant;
END;
$$;


-- ─────────────────────────────────────────────────────────────
-- PART C: analytics.plan_historical_backfill()
--
-- FUNCTION (not procedure) — returns chunk plan, executes nothing.
-- The caller inspects the plan, then executes each chunk manually
-- as a separate independent CALL.
--
-- Usage:
--   SELECT * FROM analytics.plan_historical_backfill(
--     current_date - 120, current_date, 7
--   );
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION analytics.plan_historical_backfill(
  p_start_date  DATE,
  p_end_date    DATE    DEFAULT CURRENT_DATE,
  p_chunk_days  INTEGER DEFAULT 7
)
RETURNS TABLE (
  chunk_num   integer,
  chunk_start date,
  chunk_end   date,
  call_sql    text
)
LANGUAGE sql SECURITY DEFINER STABLE
AS $$
  WITH chunks AS (
    SELECT
      ROW_NUMBER() OVER (ORDER BY gs)::integer AS chunk_num,
      gs::date                                  AS chunk_start,
      LEAST(gs::date + (p_chunk_days - 1), p_end_date)::date AS chunk_end
    FROM generate_series(p_start_date, p_end_date, (p_chunk_days || ' days')::interval) gs
  )
  SELECT
    chunk_num,
    chunk_start,
    chunk_end,
    format(
      'CALL analytics.run_historical_backfill_chunk(%L, %L);',
      chunk_start, chunk_end
    ) AS call_sql
  FROM chunks
  ORDER BY chunk_num;
$$;


-- ─────────────────────────────────────────────────────────────
-- PART D: analytics.run_historical_backfill_chunk(start, end)
--
-- Executes exactly ONE date range — no loops, no iteration.
-- Each call is a single bounded transaction.
-- Caller is responsible for calling this once per chunk
-- from separate independent requests.
--
-- Architectural contract:
--   - This procedure runs the 5 fact refreshes once for [start, end]
--   - It records etl_runs rows for each subjob (via orchestrate_incremental_refresh)
--   - It does NOT set GLOBAL_SWEEP — that is done by watermark sweep after backfill
--   - Advisory lock: acquired for the duration of this single call only
--   - If the call times out or fails, only this chunk is lost — previous
--     chunks already committed in their own calls are preserved
--
-- Performance contract:
--   Maximum date array size = p_end_date - p_start_date + 1
--   For chunk_days = 7 → max 7 dates per call
--   This bounds:
--     fact_sales cross product:         7 days of orders × items × CTE scan
--     snapshot_customer cross product:  7 × C_active × H_90days  (see Part B)
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE analytics.run_historical_backfill_chunk(
  p_start_date DATE,
  p_end_date   DATE
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_chunk_dates   DATE[];
  v_lock_obtained BOOLEAN;
  v_chunk_label   TEXT;
BEGIN
  IF p_start_date > p_end_date THEN
    RAISE EXCEPTION 'start_date (%) must be <= end_date (%)', p_start_date, p_end_date;
  END IF;

  IF (p_end_date - p_start_date + 1) > 30 THEN
    RAISE EXCEPTION 'Chunk too large: % days. Use plan_historical_backfill() to see bounded chunks.',
      (p_end_date - p_start_date + 1);
  END IF;

  v_chunk_label := format('%s→%s', p_start_date, p_end_date);

  -- Advisory lock: same key as incremental sweep — prevents overlap
  SELECT pg_try_advisory_lock(hashtext('analytics_global_sweep')) INTO v_lock_obtained;
  IF NOT v_lock_obtained THEN
    RAISE EXCEPTION 'Analytics sweep is running elsewhere. Retry after it completes.';
  END IF;

  BEGIN
    -- Build date array for this chunk
    SELECT array_agg(d::date ORDER BY d)
    INTO   v_chunk_dates
    FROM   generate_series(p_start_date, p_end_date, '1 day'::interval) d;

    RAISE NOTICE 'Backfill chunk [%]: % dates', v_chunk_label, array_length(v_chunk_dates, 1);

    -- Execute all 5 fact refreshes for this chunk
    -- Each CALL is transaction-safe (no COMMIT inside, per migration 78)
    -- All 5 share the same transaction with this chunk call — they commit together
    CALL analytics.orchestrate_incremental_refresh(
      gen_random_uuid(), 'fact_sales_daily_grain', v_chunk_dates
    );
    CALL analytics.orchestrate_incremental_refresh(
      gen_random_uuid(), 'fact_financial_ledgers_daily', v_chunk_dates
    );
    CALL analytics.orchestrate_incremental_refresh(
      gen_random_uuid(), 'fact_treasury_cashflow_daily', v_chunk_dates
    );
    CALL analytics.orchestrate_incremental_refresh(
      gen_random_uuid(), 'fact_ar_collections_attributed_to_origin_sale_date', v_chunk_dates
    );
    CALL analytics.orchestrate_incremental_refresh(
      gen_random_uuid(), 'snapshot_customer_health', v_chunk_dates
    );

    RAISE NOTICE 'Backfill chunk [%]: complete', v_chunk_label;

    PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));

  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));
    RAISE;  -- re-raise so caller sees the failure; previous chunks are unaffected
  END;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- Grants
-- ─────────────────────────────────────────────────────────────
REVOKE ALL ON PROCEDURE analytics.run_historical_backfill_chunk(DATE, DATE)          FROM public;
REVOKE ALL ON FUNCTION  analytics.plan_historical_backfill(DATE, DATE, INTEGER)       FROM public;

GRANT EXECUTE ON PROCEDURE analytics.internal_refresh_fact_sales_daily_grain(DATE[])  TO service_role;
GRANT EXECUTE ON PROCEDURE analytics.internal_refresh_snapshot_customer_health(DATE[]) TO service_role;
GRANT EXECUTE ON PROCEDURE analytics.run_historical_backfill_chunk(DATE, DATE)         TO service_role;
GRANT EXECUTE ON FUNCTION  analytics.plan_historical_backfill(DATE, DATE, INTEGER)     TO service_role;
