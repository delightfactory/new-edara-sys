-- ============================================================
-- 85_analytics_query_performance_fix.sql
-- Performance Optimization & Blockers Fixes (Cairo Timezone Hardened + Immutable Safe)
-- ============================================================

-- 1. Standard Indexes on Raw Timestamps (Immutable natively without COALESCE casting)
CREATE INDEX IF NOT EXISTS idx_so_delivered_at ON public.sales_orders (delivered_at);
CREATE INDEX IF NOT EXISTS idx_so_order_date ON public.sales_orders (order_date);
CREATE INDEX IF NOT EXISTS idx_vault_txn_raw_date ON public.vault_transactions (created_at);
CREATE INDEX IF NOT EXISTS idx_custody_txn_raw_date ON public.custody_transactions (created_at);
CREATE INDEX IF NOT EXISTS idx_cust_ledger_raw_date ON public.customer_ledger (created_at);

-- ------------------------------------------------------------
-- 2. Fact: Sales Daily Grain (Using Cairo-explicit Range Joins + OR split for Indexing)
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE analytics.internal_refresh_fact_sales_daily_grain(p_target_dates DATE[])
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF array_length(p_target_dates, 1) IS NULL THEN RETURN; END IF;

  DELETE FROM analytics.fact_sales_daily_grain WHERE date = ANY(p_target_dates);

  WITH aggregated_sales AS (
    SELECT 
      tgt_date as sale_date,
      so.customer_id,
      sol.product_id,
      so.rep_id,
      SUM(sol.line_total) as tax_incl_amt,
      SUM(sol.line_total - COALESCE(sol.tax_amount, 0)) as tax_excl_amt,
      SUM(COALESCE(sol.tax_amount, 0)) as tax_amt,
      SUM(sol.base_quantity) as qty,
      SUM(COALESCE(sol.line_total / NULLIF(so.total_amount, 0), 0) * COALESCE(so.credit_amount, 0)) as ar_credit_portion_amount,
      SUM(COALESCE((SELECT SUM(sri.line_total) FROM public.sales_return_items sri JOIN public.sales_returns sr ON sr.id = sri.return_id WHERE sri.order_item_id = sol.id AND sr.status = 'confirmed'), 0)) as return_tax_incl_amt,
      SUM(COALESCE((SELECT SUM(sri.line_total - (sri.line_total * (so.tax_amount / NULLIF(so.subtotal, 0)))) FROM public.sales_return_items sri JOIN public.sales_returns sr ON sr.id = sri.return_id WHERE sri.order_item_id = sol.id AND sr.status = 'confirmed'), 0)) as return_tax_excl_amt,
      SUM(COALESCE((SELECT SUM(sri.base_quantity) FROM public.sales_return_items sri JOIN public.sales_returns sr ON sr.id = sri.return_id WHERE sri.order_item_id = sol.id AND sr.status = 'confirmed'), 0)) as return_qty
    FROM public.sales_orders so
    JOIN unnest(p_target_dates) AS tgt_date
      ON (so.delivered_at IS NOT NULL AND so.delivered_at >= (tgt_date::timestamp AT TIME ZONE 'Africa/Cairo') AND so.delivered_at < ((tgt_date + 1)::timestamp AT TIME ZONE 'Africa/Cairo'))
      OR (so.delivered_at IS NULL AND so.order_date = tgt_date)
    JOIN public.sales_order_items sol ON so.id = sol.order_id
    WHERE so.status IN ('delivered', 'completed')
    GROUP BY 1, 2, 3, 4
  )
  INSERT INTO analytics.fact_sales_daily_grain 
    (date, customer_id, product_id, rep_id, tax_inclusive_amount, ar_credit_portion_amount, return_tax_inclusive_amount,
     tax_exclusive_amount, tax_amount, return_tax_exclusive_amount, net_tax_exclusive_revenue, gross_quantity, return_quantity, net_quantity)
  SELECT 
    sale_date, customer_id, product_id, COALESCE(rep_id, '00000000-0000-0000-0000-000000000000'::uuid), 
    tax_incl_amt, ar_credit_portion_amount, return_tax_incl_amt,
    tax_excl_amt, tax_amt, return_tax_excl_amt, (tax_excl_amt - return_tax_excl_amt), qty, return_qty, (qty - return_qty)
  FROM aggregated_sales
  ON CONFLICT (date, customer_id, product_id, rep_id) DO UPDATE SET
    tax_inclusive_amount = EXCLUDED.tax_inclusive_amount,
    ar_credit_portion_amount = EXCLUDED.ar_credit_portion_amount,
    return_tax_inclusive_amount = EXCLUDED.return_tax_inclusive_amount,
    tax_exclusive_amount = EXCLUDED.tax_exclusive_amount,
    tax_amount = EXCLUDED.tax_amount,
    return_tax_exclusive_amount = EXCLUDED.return_tax_exclusive_amount,
    net_tax_exclusive_revenue = EXCLUDED.net_tax_exclusive_revenue,
    gross_quantity = EXCLUDED.gross_quantity,
    return_quantity = EXCLUDED.return_quantity,
    net_quantity = EXCLUDED.net_quantity,
    updated_at = now();
END;
$$;

-- ------------------------------------------------------------
-- 3. Fact: Net Treasury Cashflow Daily
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE analytics.internal_refresh_fact_treasury_cashflow_daily(p_target_dates DATE[])
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF array_length(p_target_dates, 1) IS NULL THEN RETURN; END IF;

  DELETE FROM analytics.fact_treasury_cashflow_daily WHERE treasury_date = ANY(p_target_dates);

  WITH vault_inflow_receipt AS (
    SELECT tgt_date as d, pr.customer_id, pr.collected_by as rep_id, SUM(vt.amount) as gross_amt
    FROM public.vault_transactions vt
    JOIN unnest(p_target_dates) AS tgt_date ON vt.created_at >= (tgt_date::timestamp AT TIME ZONE 'Africa/Cairo') AND vt.created_at < ((tgt_date + 1)::timestamp AT TIME ZONE 'Africa/Cairo')
    JOIN public.payment_receipts pr ON vt.reference_id = pr.id AND vt.reference_type = 'payment_receipt'
    WHERE vt.type = 'collection' GROUP BY 1, 2, 3
  ),
  vault_inflow_sales AS (
    SELECT tgt_date as d, so.customer_id, so.rep_id, SUM(vt.amount) as gross_amt
    FROM public.vault_transactions vt
    JOIN unnest(p_target_dates) AS tgt_date ON vt.created_at >= (tgt_date::timestamp AT TIME ZONE 'Africa/Cairo') AND vt.created_at < ((tgt_date + 1)::timestamp AT TIME ZONE 'Africa/Cairo')
    JOIN public.sales_orders so ON vt.reference_id = so.id AND vt.reference_type = 'sales_order'
    WHERE vt.type = 'collection' GROUP BY 1, 2, 3
  ),
  custody_inflow_receipt AS (
    SELECT tgt_date as d, pr.customer_id, pr.collected_by as rep_id, SUM(ct.amount) as gross_amt
    FROM public.custody_transactions ct
    JOIN unnest(p_target_dates) AS tgt_date ON ct.created_at >= (tgt_date::timestamp AT TIME ZONE 'Africa/Cairo') AND ct.created_at < ((tgt_date + 1)::timestamp AT TIME ZONE 'Africa/Cairo')
    JOIN public.payment_receipts pr ON ct.reference_id = pr.id AND ct.reference_type = 'payment_receipt'
    WHERE ct.type = 'collection' GROUP BY 1, 2, 3
  ),
  custody_inflow_sales AS (
    SELECT tgt_date as d, so.customer_id, so.rep_id, SUM(ct.amount) as gross_amt
    FROM public.custody_transactions ct
    JOIN unnest(p_target_dates) AS tgt_date ON ct.created_at >= (tgt_date::timestamp AT TIME ZONE 'Africa/Cairo') AND ct.created_at < ((tgt_date + 1)::timestamp AT TIME ZONE 'Africa/Cairo')
    JOIN public.sales_orders so ON ct.reference_id = so.id AND ct.reference_type = 'sales_order'
    WHERE ct.type = 'collection' GROUP BY 1, 2, 3
  ),
  inflow_combined AS (
    SELECT d, customer_id, rep_id, gross_amt FROM vault_inflow_receipt
    UNION ALL SELECT d, customer_id, rep_id, gross_amt FROM vault_inflow_sales
    UNION ALL SELECT d, customer_id, rep_id, gross_amt FROM custody_inflow_receipt
    UNION ALL SELECT d, customer_id, rep_id, gross_amt FROM custody_inflow_sales
  ),
  inflow_grouped AS (
    SELECT d, customer_id, rep_id, SUM(gross_amt) as gross_amt FROM inflow_combined GROUP BY 1, 2, 3
  ),
  vault_refunds_cte AS (
    SELECT tgt_date as d, sr.customer_id,
      COALESCE((SELECT pr2.collected_by FROM public.payment_receipts pr2 WHERE pr2.sales_order_id = sr.order_id AND pr2.status = 'confirmed' ORDER BY pr2.created_at ASC LIMIT 1), so.rep_id) as rep_id,
      SUM(vt.amount) as refund_amt
    FROM public.vault_transactions vt
    JOIN unnest(p_target_dates) AS tgt_date ON vt.created_at >= (tgt_date::timestamp AT TIME ZONE 'Africa/Cairo') AND vt.created_at < ((tgt_date + 1)::timestamp AT TIME ZONE 'Africa/Cairo')
    JOIN public.sales_returns sr ON vt.reference_id = sr.id JOIN public.sales_orders so ON sr.order_id = so.id
    WHERE vt.type = 'withdrawal' AND vt.reference_type = 'sales_return' GROUP BY 1, 2, 3
  ),
  custody_refunds_cte AS (
    SELECT tgt_date as d, sr.customer_id,
      COALESCE((SELECT pr2.collected_by FROM public.payment_receipts pr2 WHERE pr2.sales_order_id = sr.order_id AND pr2.status = 'confirmed' ORDER BY pr2.created_at ASC LIMIT 1), so.rep_id) as rep_id,
      SUM(ct.amount) as refund_amt
    FROM public.custody_transactions ct
    JOIN unnest(p_target_dates) AS tgt_date ON ct.created_at >= (tgt_date::timestamp AT TIME ZONE 'Africa/Cairo') AND ct.created_at < ((tgt_date + 1)::timestamp AT TIME ZONE 'Africa/Cairo')
    JOIN public.sales_returns sr ON ct.reference_id = sr.id JOIN public.sales_orders so ON sr.order_id = so.id
    WHERE ct.type = 'expense' AND ct.reference_type = 'sales_return' GROUP BY 1, 2, 3
  ),
  combined_grains AS (
    SELECT d, customer_id, rep_id FROM inflow_grouped
    UNION SELECT d, customer_id, rep_id FROM vault_refunds_cte WHERE rep_id IS NOT NULL
    UNION SELECT d, customer_id, rep_id FROM custody_refunds_cte WHERE rep_id IS NOT NULL
  ),
  net_aggregations AS (
    SELECT 
      cg.d, cg.customer_id, COALESCE(cg.rep_id, '00000000-0000-0000-0000-000000000000'::uuid) as rep_id,
      COALESCE(ig.gross_amt, 0) as inflow,
      (COALESCE(vr.refund_amt, 0) + COALESCE(cr.refund_amt, 0)) as outflow,
      COALESCE(ig.gross_amt, 0) - (COALESCE(vr.refund_amt, 0) + COALESCE(cr.refund_amt, 0)) as net_amt
    FROM combined_grains cg
    LEFT JOIN inflow_grouped ig ON cg.d = ig.d AND cg.customer_id = ig.customer_id AND cg.rep_id = ig.rep_id
    LEFT JOIN vault_refunds_cte vr ON cg.d = vr.d AND cg.customer_id = vr.customer_id AND cg.rep_id = vr.rep_id
    LEFT JOIN custody_refunds_cte cr ON cg.d = cr.d AND cg.customer_id = cr.customer_id AND cg.rep_id = cr.rep_id
  )
  INSERT INTO analytics.fact_treasury_cashflow_daily 
    (treasury_date, customer_id, collected_by, gross_inflow_amount, gross_outflow_amount, net_cashflow)
  SELECT d, customer_id, rep_id, inflow, outflow, net_amt FROM net_aggregations
  ON CONFLICT (treasury_date, customer_id, collected_by) DO UPDATE SET
    gross_inflow_amount = EXCLUDED.gross_inflow_amount, gross_outflow_amount = EXCLUDED.gross_outflow_amount, net_cashflow = EXCLUDED.net_cashflow, updated_at = now();
END;
$$;

-- ------------------------------------------------------------
-- 4. Fact: AR Collections Attributed
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE analytics.internal_refresh_fact_ar_collections_attributed(p_target_dates DATE[])
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF array_length(p_target_dates, 1) IS NULL THEN RETURN; END IF;
  DELETE FROM analytics.fact_ar_collections_attributed_to_origin_sale_date WHERE origin_sale_delivered_at = ANY(p_target_dates);

  WITH attributed_receipts AS (
    SELECT 
      tgt_date as sale_date, cl.customer_id, pr.collected_by, so.rep_id as original_rep_id, SUM(cl.amount) as attr_receipt_amount
    FROM public.customer_ledger cl
    JOIN public.customer_ledger invoice_cl ON cl.allocated_to = invoice_cl.id
    JOIN public.sales_orders so ON invoice_cl.source_id = so.id AND invoice_cl.source_type = 'sales_order'
    JOIN unnest(p_target_dates) AS tgt_date 
      ON (so.delivered_at IS NOT NULL AND so.delivered_at >= (tgt_date::timestamp AT TIME ZONE 'Africa/Cairo') AND so.delivered_at < ((tgt_date + 1)::timestamp AT TIME ZONE 'Africa/Cairo'))
      OR (so.delivered_at IS NULL AND so.order_date = tgt_date)
    JOIN public.payment_receipts pr ON cl.source_id = pr.id
    WHERE cl.type = 'credit' AND cl.source_type = 'payment_receipt' AND so.status IN ('delivered', 'completed') GROUP BY 1, 2, 3, 4
  ),
  vault_attr_refunds AS (
    SELECT
      tgt_date as sale_date, so.customer_id,
      COALESCE((SELECT pr2.collected_by FROM public.payment_receipts pr2 WHERE pr2.sales_order_id = sr.order_id AND pr2.status = 'confirmed' ORDER BY pr2.created_at ASC LIMIT 1), so.rep_id) as collected_by,
      so.rep_id as original_rep_id, SUM(vt.amount) as attr_refund_amount
    FROM public.vault_transactions vt
    JOIN public.sales_returns sr ON vt.reference_id = sr.id JOIN public.sales_orders so ON sr.order_id = so.id
    JOIN unnest(p_target_dates) AS tgt_date
      ON (so.delivered_at IS NOT NULL AND so.delivered_at >= (tgt_date::timestamp AT TIME ZONE 'Africa/Cairo') AND so.delivered_at < ((tgt_date + 1)::timestamp AT TIME ZONE 'Africa/Cairo'))
      OR (so.delivered_at IS NULL AND so.order_date = tgt_date)
    WHERE vt.type = 'withdrawal' AND vt.reference_type = 'sales_return' GROUP BY 1, 2, 3, 4
  ),
  custody_attr_refunds AS (
    SELECT
      tgt_date as sale_date, so.customer_id,
      COALESCE((SELECT pr2.collected_by FROM public.payment_receipts pr2 WHERE pr2.sales_order_id = sr.order_id AND pr2.status = 'confirmed' ORDER BY pr2.created_at ASC LIMIT 1), so.rep_id) as collected_by,
      so.rep_id as original_rep_id, SUM(ct.amount) as attr_refund_amount
    FROM public.custody_transactions ct
    JOIN public.sales_returns sr ON ct.reference_id = sr.id JOIN public.sales_orders so ON sr.order_id = so.id
    JOIN unnest(p_target_dates) AS tgt_date 
      ON (so.delivered_at IS NOT NULL AND so.delivered_at >= (tgt_date::timestamp AT TIME ZONE 'Africa/Cairo') AND so.delivered_at < ((tgt_date + 1)::timestamp AT TIME ZONE 'Africa/Cairo'))
      OR (so.delivered_at IS NULL AND so.order_date = tgt_date)
    WHERE ct.type = 'expense' AND ct.reference_type = 'sales_return' GROUP BY 1, 2, 3, 4
  ),
  combined_attr_grains AS (
    SELECT sale_date, customer_id, collected_by, original_rep_id FROM attributed_receipts UNION SELECT sale_date, customer_id, collected_by, original_rep_id FROM vault_attr_refunds WHERE collected_by IS NOT NULL UNION SELECT sale_date, customer_id, collected_by, original_rep_id FROM custody_attr_refunds WHERE collected_by IS NOT NULL
  ),
  net_attr_aggs AS (
    SELECT cg.sale_date, cg.customer_id, 
      COALESCE(cg.collected_by, '00000000-0000-0000-0000-000000000000'::uuid) as collected_by, COALESCE(cg.original_rep_id, '00000000-0000-0000-0000-000000000000'::uuid) as original_rep_id,
      COALESCE(ar.attr_receipt_amount, 0) as r_amt, COALESCE(vr.attr_refund_amount, 0) + COALESCE(cr.attr_refund_amount, 0) as cr_amt,
      COALESCE(ar.attr_receipt_amount, 0) - (COALESCE(vr.attr_refund_amount, 0) + COALESCE(cr.attr_refund_amount, 0)) as net_amt
    FROM combined_attr_grains cg
    LEFT JOIN attributed_receipts ar ON cg.sale_date=ar.sale_date AND cg.customer_id=ar.customer_id AND cg.collected_by=ar.collected_by AND cg.original_rep_id=ar.original_rep_id
    LEFT JOIN vault_attr_refunds vr ON cg.sale_date=vr.sale_date AND cg.customer_id=vr.customer_id AND cg.collected_by=vr.collected_by AND cg.original_rep_id=vr.original_rep_id
    LEFT JOIN custody_attr_refunds cr ON cg.sale_date=cr.sale_date AND cg.customer_id=cr.customer_id AND cg.collected_by=cr.collected_by AND cg.original_rep_id=cr.original_rep_id
  )
  INSERT INTO analytics.fact_ar_collections_attributed_to_origin_sale_date
    (origin_sale_delivered_at, customer_id, collected_by, original_rep_id, receipt_amount, cash_refund_amount, net_cohort_collection)
  SELECT sale_date, customer_id, collected_by, original_rep_id, r_amt, cr_amt, net_amt FROM net_attr_aggs
  ON CONFLICT (origin_sale_delivered_at, customer_id, collected_by, original_rep_id) DO UPDATE SET
    receipt_amount = EXCLUDED.receipt_amount, cash_refund_amount = EXCLUDED.cash_refund_amount, net_cohort_collection = EXCLUDED.net_cohort_collection, updated_at = now();
END;
$$;

-- ------------------------------------------------------------
-- 5. Fact: Financial Ledgers Daily (Date native)
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE analytics.internal_refresh_fact_financial_ledgers_daily(p_target_dates DATE[])
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF array_length(p_target_dates, 1) IS NULL THEN RETURN; END IF;
  DELETE FROM analytics.fact_financial_ledgers_daily WHERE date = ANY(p_target_dates);
  WITH daily_aggs AS (
    SELECT je.entry_date as d, jel.account_id, SUM(jel.debit) as debits, SUM(jel.credit) as credits FROM public.journal_entries je
    JOIN public.journal_entry_lines jel ON je.id = jel.entry_id WHERE je.status = 'posted' AND je.entry_date = ANY(p_target_dates) GROUP BY 1, 2
  )
  INSERT INTO analytics.fact_financial_ledgers_daily (date, account_id, debit_sum, credit_sum, net_movement)
  SELECT d, account_id, debits, credits, (debits - credits) FROM daily_aggs
  ON CONFLICT (date, account_id) DO UPDATE SET debit_sum = EXCLUDED.debit_sum, credit_sum = EXCLUDED.credit_sum, net_movement = EXCLUDED.net_movement, updated_at = now();
END;
$$;

-- ------------------------------------------------------------
-- 6. Snapshot Customer Health (Cairo Time Range Joins)
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE analytics.internal_refresh_snapshot_customer_health(p_target_dates DATE[])
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF array_length(p_target_dates, 1) IS NULL THEN RETURN; END IF;
  DELETE FROM analytics.snapshot_customer_health WHERE as_of_date = ANY(p_target_dates);

  WITH customer_ops AS (
    SELECT DISTINCT so.customer_id FROM public.sales_orders so
    JOIN unnest(p_target_dates) AS tgt_date 
      ON (so.delivered_at IS NOT NULL AND so.delivered_at >= (tgt_date::timestamp AT TIME ZONE 'Africa/Cairo') AND so.delivered_at < ((tgt_date + 1)::timestamp AT TIME ZONE 'Africa/Cairo'))
      OR (so.delivered_at IS NULL AND so.order_date = tgt_date)
    UNION SELECT DISTINCT cl.customer_id FROM public.customer_ledger cl
    JOIN unnest(p_target_dates) AS tgt_date ON cl.created_at >= (tgt_date::timestamp AT TIME ZONE 'Africa/Cairo') AND cl.created_at < ((tgt_date + 1)::timestamp AT TIME ZONE 'Africa/Cairo')
  ),
  dates_cross AS (SELECT d, customer_id FROM unnest(p_target_dates) d CROSS JOIN customer_ops),
  sales_history AS (SELECT so.customer_id, COALESCE((so.delivered_at AT TIME ZONE 'Africa/Cairo')::DATE, so.order_date) as sale_date, so.total_amount FROM public.sales_orders so JOIN customer_ops co ON co.customer_id = so.customer_id WHERE so.status IN ('delivered', 'completed')),
  health_stats AS (
    SELECT dx.d as as_of_date, dx.customer_id, MAX(sh.sale_date) FILTER (WHERE sh.sale_date <= dx.d) as last_sale_date, COUNT(sh.sale_date) FILTER (WHERE sh.sale_date BETWEEN (dx.d - INTERVAL '90 days') AND dx.d) as freq_l90d, COALESCE(SUM(sh.total_amount) FILTER (WHERE sh.sale_date BETWEEN (dx.d - INTERVAL '90 days') AND dx.d), 0) as monetary_l90d
    FROM dates_cross dx LEFT JOIN sales_history sh ON sh.customer_id = dx.customer_id GROUP BY dx.d, dx.customer_id
  )
  INSERT INTO analytics.snapshot_customer_health (as_of_date, customer_id, recency_days, frequency_l90d, monetary_l90d, is_dormant)
  SELECT as_of_date, customer_id, CASE WHEN last_sale_date IS NOT NULL THEN (as_of_date - last_sale_date) ELSE NULL END as recency_days, freq_l90d, monetary_l90d, CASE WHEN last_sale_date IS NULL THEN false WHEN (as_of_date - last_sale_date) > 90 THEN true ELSE false END as is_dormant
  FROM health_stats ON CONFLICT (as_of_date, customer_id) DO UPDATE SET recency_days = EXCLUDED.recency_days, frequency_l90d = EXCLUDED.frequency_l90d, monetary_l90d = EXCLUDED.monetary_l90d, is_dormant = EXCLUDED.is_dormant;
END;
$$;

-- ------------------------------------------------------------
-- 7. Sweep Refactor (extract target attainment)
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE analytics.run_analytics_watermark_sweep(p_fallback_days INTEGER DEFAULT 3)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_watermark       TIMESTAMPTZ;
  v_sweep_start     TIMESTAMPTZ := now();
  v_target_dates    DATE[];
  v_lock_obtained   BOOLEAN;
  v_failed_subjobs  INTEGER := 0;
  v_sweep_id        UUID := gen_random_uuid();
  v_run_id_1        UUID := gen_random_uuid(); v_run_id_2 UUID := gen_random_uuid();
  v_run_id_3    UUID := gen_random_uuid(); v_run_id_4     UUID := gen_random_uuid();
  v_run_id_5        UUID := gen_random_uuid(); v_run_id_6 UUID := gen_random_uuid();
  v_run_id_7        UUID := gen_random_uuid(); v_run_id_8 UUID := gen_random_uuid();
BEGIN
  SELECT pg_try_advisory_lock(hashtext('analytics_global_sweep')) INTO v_lock_obtained;
  IF NOT v_lock_obtained THEN RAISE NOTICE 'Analytics sweep locked elsewhere — exiting.'; RETURN; END IF;
  BEGIN
    SELECT COALESCE(MAX(started_at), now() - (p_fallback_days || ' days')::interval) INTO v_watermark FROM analytics.etl_runs WHERE table_name = 'GLOBAL_SWEEP' AND status IN ('SUCCESS', 'POSTING_CONSISTENCY_ONLY', 'VERIFIED', 'RECONCILED_WITH_WARNING');
    INSERT INTO analytics.etl_runs (id, table_name, status, started_at) VALUES (v_sweep_id, 'GLOBAL_SWEEP', 'RUNNING', v_sweep_start);
    SELECT analytics.detect_affected_dates(v_watermark) INTO v_target_dates;

    IF array_length(v_target_dates, 1) IS NOT NULL THEN
      CALL analytics.orchestrate_incremental_refresh(v_run_id_1, 'fact_sales_daily_grain',                             v_target_dates);
      CALL analytics.orchestrate_incremental_refresh(v_run_id_2, 'fact_financial_ledgers_daily',                       v_target_dates);
      CALL analytics.orchestrate_incremental_refresh(v_run_id_3, 'fact_treasury_cashflow_daily',                       v_target_dates);
      CALL analytics.orchestrate_incremental_refresh(v_run_id_4, 'fact_ar_collections_attributed_to_origin_sale_date', v_target_dates);
      CALL analytics.orchestrate_incremental_refresh(v_run_id_5, 'snapshot_customer_health',                           v_target_dates);
      CALL analytics.orchestrate_incremental_refresh(v_run_id_6, 'snapshot_customer_risk',                             v_target_dates);
      CALL analytics.orchestrate_incremental_refresh(v_run_id_8, 'fact_geography_daily',                               v_target_dates);
    END IF;

    -- Targets run daily independently to advance progress toward deadlines
    CALL analytics.orchestrate_incremental_refresh(v_run_id_7, 'snapshot_target_attainment', ARRAY[CURRENT_DATE]::DATE[]);

    SELECT COUNT(*) INTO v_failed_subjobs FROM analytics.etl_runs WHERE id IN (v_run_id_1, v_run_id_2, v_run_id_3, v_run_id_4, v_run_id_5, v_run_id_6, v_run_id_7, v_run_id_8) AND status IN ('FAILED', 'BLOCKED');
    IF v_failed_subjobs > 0 THEN UPDATE analytics.etl_runs SET status = 'PARTIAL_FAILURE', completed_at = now() WHERE id = v_sweep_id;
    ELSE UPDATE analytics.etl_runs SET status = 'SUCCESS', completed_at = now() WHERE id = v_sweep_id; END IF;
    PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));
  EXCEPTION WHEN OTHERS THEN
    UPDATE analytics.etl_runs SET status = 'FAILED', completed_at = now(), log_output = jsonb_build_object('error', SQLERRM, 'state', SQLSTATE) WHERE id = v_sweep_id;
    PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));
    RAISE;
  END;
END;
$$;

-- ------------------------------------------------------------
-- 8. Backfill Refactor
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE analytics.run_historical_backfill(
  p_start_date  DATE, p_end_date    DATE    DEFAULT CURRENT_DATE, p_chunk_days  INTEGER DEFAULT 7
) LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_chunk_start DATE; v_chunk_end DATE; v_chunk_dates DATE[]; v_lock_obtained BOOLEAN; v_chunks_done INTEGER := 0;
BEGIN
  IF p_start_date > p_end_date THEN RAISE EXCEPTION 'start_date (%) must be <= end_date (%)', p_start_date, p_end_date; END IF;
  IF p_chunk_days < 1 OR p_chunk_days > 30 THEN RAISE EXCEPTION 'p_chunk_days must be between 1 and 30 (got %)', p_chunk_days; END IF;
  SELECT pg_try_advisory_lock(hashtext('analytics_global_sweep')) INTO v_lock_obtained;
  IF NOT v_lock_obtained THEN RAISE EXCEPTION 'Analytics sweep is running elsewhere. Backfill cannot start.'; END IF;
  BEGIN
    v_chunk_start := p_start_date;
    WHILE v_chunk_start <= p_end_date LOOP
      v_chunk_end := LEAST(v_chunk_start + (p_chunk_days - 1), p_end_date);
      RAISE NOTICE 'Backfilling chunk %: % to %', v_chunks_done + 1, v_chunk_start, v_chunk_end;
      SELECT array_agg(d::date) INTO v_chunk_dates FROM generate_series(v_chunk_start, v_chunk_end, '1 day'::interval) d;
      CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_sales_daily_grain', v_chunk_dates);
      CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_financial_ledgers_daily', v_chunk_dates);
      CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_treasury_cashflow_daily', v_chunk_dates);
      CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_ar_collections_attributed_to_origin_sale_date', v_chunk_dates);
      CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'snapshot_customer_health', v_chunk_dates);
      CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'snapshot_customer_risk', v_chunk_dates);
      CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_geography_daily', v_chunk_dates);
      v_chunks_done := v_chunks_done + 1; v_chunk_start := v_chunk_end + 1;
    END LOOP;
    RAISE NOTICE 'Historical backfill completed. Chunks processed: %', v_chunks_done;
    PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));
  EXCEPTION WHEN OTHERS THEN PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep')); RAISE;
  END;
END;
$$;
