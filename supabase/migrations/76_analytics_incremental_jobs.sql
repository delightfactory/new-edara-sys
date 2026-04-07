-- ============================================================
-- 76_analytics_incremental_jobs.sql
-- EDARA v2 - Reporting Analytics: Incremental Refresh Jobs
-- Handles late-arriving events, targeted rebuilding,
-- exact grain cleanups, and secure execution logging.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Helper: Detect Affected Dates Watermark Scanner
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION analytics.detect_affected_dates(p_last_watermark TIMESTAMPTZ)
RETURNS DATE[]
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_dates DATE[];
BEGIN
  -- Strict Back-Attribution detection logic & correct column names.
  WITH affected AS (
    -- 1. Sales updates affecting the actual deliver date
    SELECT DATE(COALESCE(so.delivered_at, so.order_date)) as d
    FROM public.sales_orders so
    WHERE so.updated_at >= p_last_watermark
    
    UNION
    -- 2. Sales Returns back-attribution (Affects original order date)
    SELECT DATE(COALESCE(so.delivered_at, so.order_date)) as d
    FROM public.sales_returns sr
    JOIN public.sales_orders so ON sr.order_id = so.id
    WHERE sr.updated_at >= p_last_watermark

    UNION
    -- 3. Receipts updates (Affects BACK-ATTRIBUTION via origin_sale_delivered_at)
    SELECT DATE(COALESCE(so.delivered_at, so.order_date)) as d
    FROM public.payment_receipts pr
    JOIN public.sales_orders so ON pr.sales_order_id = so.id
    WHERE pr.updated_at >= p_last_watermark

    UNION
    -- 4. Ledgers (Customer Accounts)
    SELECT DATE(created_at) as d
    FROM public.customer_ledger
    WHERE created_at >= p_last_watermark

    UNION 
    -- 5. Treasury Vaults (Direct Treasury execution date affecting Cashflow)
    SELECT DATE(created_at) as d
    FROM public.vault_transactions
    WHERE created_at >= p_last_watermark
    
    UNION 
    -- 6. Treasury Vaults (Affects BACK-ATTRIBUTION via origin_sale_delivered_at for refunds)
    SELECT DATE(COALESCE(so.delivered_at, so.order_date)) as d
    FROM public.vault_transactions vt
    JOIN public.sales_returns sr ON vt.reference_id = sr.id
    JOIN public.sales_orders so ON sr.order_id = so.id
    WHERE vt.created_at >= p_last_watermark AND vt.reference_type = 'sales_return'

    UNION
    -- 7. Treasury Custody (Direct Treasury execution date affecting Cashflow)
    SELECT DATE(created_at) as d
    FROM public.custody_transactions
    WHERE created_at >= p_last_watermark
    
    UNION 
    -- 8. Treasury Custody (Affects BACK-ATTRIBUTION via origin_sale_delivered_at for refunds)
    SELECT DATE(COALESCE(so.delivered_at, so.order_date)) as d
    FROM public.custody_transactions ct
    JOIN public.sales_returns sr ON ct.reference_id = sr.id
    JOIN public.sales_orders so ON sr.order_id = so.id
    WHERE ct.created_at >= p_last_watermark AND ct.reference_type = 'sales_return'

    UNION
    -- 9. Journal Entries
    SELECT DATE(entry_date) as d
    FROM public.journal_entries
    WHERE created_at >= p_last_watermark

    UNION
    -- 10. Receipts allocations back-attribution via customer_ledger (Affects multiple older invoices)
    SELECT DATE(COALESCE(so.delivered_at, so.order_date)) as d
    FROM public.customer_ledger cl
    JOIN public.customer_ledger invoice_cl ON cl.allocated_to = invoice_cl.id
    JOIN public.sales_orders so ON invoice_cl.source_id = so.id
    WHERE cl.created_at >= p_last_watermark
      AND cl.type = 'credit'
      AND cl.source_type = 'payment_receipt'
      AND invoice_cl.source_type = 'sales_order'
  )
  SELECT array_agg(DISTINCT d) INTO v_dates
  FROM affected
  WHERE d IS NOT NULL;
  
  RETURN COALESCE(v_dates, ARRAY[]::DATE[]);
END;
$$;

-- ------------------------------------------------------------
-- 2. Fact: Sales Daily Grain
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE analytics.internal_refresh_fact_sales_daily_grain(p_target_dates DATE[])
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF array_length(p_target_dates, 1) IS NULL THEN RETURN; END IF;

  DELETE FROM analytics.fact_sales_daily_grain WHERE date = ANY(p_target_dates);

  WITH aggregated_sales AS (
    SELECT 
      DATE(COALESCE(so.delivered_at, so.order_date)) as sale_date,
      so.customer_id,
      sol.product_id,
      so.rep_id,
      SUM(sol.line_total) as tax_incl_amt,
      SUM(sol.line_total - COALESCE(sol.tax_amount, 0)) as tax_excl_amt,
      SUM(COALESCE(sol.tax_amount, 0)) as tax_amt,
      
      SUM(sol.base_quantity) as qty,
      
      SUM(COALESCE(sol.line_total / NULLIF(so.total_amount, 0), 0) * COALESCE(so.credit_amount, 0)) as ar_credit_portion_amount,

      SUM(COALESCE((
        SELECT SUM(sri.line_total) 
        FROM public.sales_return_items sri
        JOIN public.sales_returns sr ON sr.id = sri.return_id
        WHERE sri.order_item_id = sol.id AND sr.status = 'confirmed'
      ), 0)) as return_tax_incl_amt,

      SUM(COALESCE((
        SELECT SUM(sri.line_total - (sri.line_total * (so.tax_amount / NULLIF(so.subtotal, 0))))
        FROM public.sales_return_items sri
        JOIN public.sales_returns sr ON sr.id = sri.return_id
        WHERE sri.order_item_id = sol.id AND sr.status = 'confirmed'
      ), 0)) as return_tax_excl_amt,

      SUM(COALESCE((
        SELECT SUM(sri.base_quantity) 
        FROM public.sales_return_items sri
        JOIN public.sales_returns sr ON sr.id = sri.return_id
        WHERE sri.order_item_id = sol.id AND sr.status = 'confirmed'
      ), 0)) as return_qty

    FROM public.sales_orders so
    JOIN public.sales_order_items sol ON so.id = sol.order_id
    WHERE DATE(COALESCE(so.delivered_at, so.order_date)) = ANY(p_target_dates)
      AND so.status IN ('delivered', 'completed')
    GROUP BY 1, 2, 3, 4
  )
  INSERT INTO analytics.fact_sales_daily_grain 
    (date, customer_id, product_id, rep_id, tax_inclusive_amount, ar_credit_portion_amount, return_tax_inclusive_amount,
     tax_exclusive_amount, tax_amount, return_tax_exclusive_amount, net_tax_exclusive_revenue,
     gross_quantity, return_quantity, net_quantity)
  SELECT 
    sale_date, customer_id, product_id, rep_id, 
    tax_incl_amt, ar_credit_portion_amount, return_tax_incl_amt,
    tax_excl_amt, tax_amt, return_tax_excl_amt, (tax_excl_amt - return_tax_excl_amt),
    qty, return_qty, (qty - return_qty)
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
-- 3. Fact: Net Treasury Cashflow Daily (True Execution Scope)
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE analytics.internal_refresh_fact_treasury_cashflow_daily(p_target_dates DATE[])
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF array_length(p_target_dates, 1) IS NULL THEN RETURN; END IF;

  DELETE FROM analytics.fact_treasury_cashflow_daily WHERE treasury_date = ANY(p_target_dates);

  WITH vault_inflow_receipt AS (
    SELECT 
      DATE(vt.created_at) as d,
      pr.customer_id,
      pr.collected_by as rep_id,
      SUM(vt.amount) as gross_amt
    FROM public.vault_transactions vt
    JOIN public.payment_receipts pr ON vt.reference_id = pr.id AND vt.reference_type = 'payment_receipt'
    WHERE DATE(vt.created_at) = ANY(p_target_dates) AND vt.type = 'collection'
    GROUP BY 1, 2, 3
  ),
  vault_inflow_sales AS (
    SELECT 
      DATE(vt.created_at) as d,
      so.customer_id,
      so.rep_id,
      SUM(vt.amount) as gross_amt
    FROM public.vault_transactions vt
    JOIN public.sales_orders so ON vt.reference_id = so.id AND vt.reference_type = 'sales_order'
    WHERE DATE(vt.created_at) = ANY(p_target_dates) AND vt.type = 'collection'
    GROUP BY 1, 2, 3
  ),
  custody_inflow_receipt AS (
    SELECT 
      DATE(ct.created_at) as d,
      pr.customer_id,
      pr.collected_by as rep_id,
      SUM(ct.amount) as gross_amt
    FROM public.custody_transactions ct
    JOIN public.payment_receipts pr ON ct.reference_id = pr.id AND ct.reference_type = 'payment_receipt'
    WHERE DATE(ct.created_at) = ANY(p_target_dates) AND ct.type = 'collection'
    GROUP BY 1, 2, 3
  ),
  custody_inflow_sales AS (
    SELECT 
      DATE(ct.created_at) as d,
      so.customer_id,
      so.rep_id,
      SUM(ct.amount) as gross_amt
    FROM public.custody_transactions ct
    JOIN public.sales_orders so ON ct.reference_id = so.id AND ct.reference_type = 'sales_order'
    WHERE DATE(ct.created_at) = ANY(p_target_dates) AND ct.type = 'collection'
    GROUP BY 1, 2, 3
  ),
  inflow_combined AS (
    SELECT d, customer_id, rep_id, gross_amt FROM vault_inflow_receipt
    UNION ALL SELECT d, customer_id, rep_id, gross_amt FROM vault_inflow_sales
    UNION ALL SELECT d, customer_id, rep_id, gross_amt FROM custody_inflow_receipt
    UNION ALL SELECT d, customer_id, rep_id, gross_amt FROM custody_inflow_sales
  ),
  inflow_grouped AS (
    SELECT d, customer_id, rep_id, SUM(gross_amt) as gross_amt
    FROM inflow_combined
    GROUP BY 1, 2, 3
  ),
  vault_refunds_cte AS (
    SELECT
      DATE(vt.created_at) as d,
      sr.customer_id,
      -- Fallback to original sales order rep_id if pure cash return misses a receipt collector
      COALESCE((
         SELECT pr2.collected_by 
         FROM public.payment_receipts pr2 
         WHERE pr2.sales_order_id = sr.order_id AND pr2.status = 'confirmed'
         ORDER BY pr2.created_at ASC LIMIT 1
      ), so.rep_id) as rep_id,
      SUM(vt.amount) as refund_amt
    FROM public.vault_transactions vt
    JOIN public.sales_returns sr ON vt.reference_id = sr.id
    JOIN public.sales_orders so ON sr.order_id = so.id
    WHERE vt.type = 'withdrawal' 
      AND vt.reference_type = 'sales_return'
      AND DATE(vt.created_at) = ANY(p_target_dates)
    GROUP BY 1, 2, 3
  ),
  custody_refunds_cte AS (
    SELECT
      DATE(ct.created_at) as d,
      sr.customer_id,
      COALESCE((
         SELECT pr2.collected_by 
         FROM public.payment_receipts pr2 
         WHERE pr2.sales_order_id = sr.order_id AND pr2.status = 'confirmed'
         ORDER BY pr2.created_at ASC LIMIT 1
      ), so.rep_id) as rep_id,
      SUM(ct.amount) as refund_amt
    FROM public.custody_transactions ct
    JOIN public.sales_returns sr ON ct.reference_id = sr.id
    JOIN public.sales_orders so ON sr.order_id = so.id
    WHERE ct.type = 'expense' 
      AND ct.reference_type = 'sales_return'
      AND DATE(ct.created_at) = ANY(p_target_dates)
    GROUP BY 1, 2, 3
  ),
  combined_grains AS (
    SELECT d, customer_id, rep_id FROM inflow_grouped
    UNION SELECT d, customer_id, rep_id FROM vault_refunds_cte WHERE rep_id IS NOT NULL
    UNION SELECT d, customer_id, rep_id FROM custody_refunds_cte WHERE rep_id IS NOT NULL
  ),
  net_aggregations AS (
    SELECT 
      cg.d, cg.customer_id, cg.rep_id,
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
  SELECT d, customer_id, rep_id, inflow, outflow, net_amt
  FROM net_aggregations
  ON CONFLICT (treasury_date, customer_id, collected_by) DO UPDATE SET
    gross_inflow_amount = EXCLUDED.gross_inflow_amount,
    gross_outflow_amount = EXCLUDED.gross_outflow_amount,
    net_cashflow = EXCLUDED.net_cashflow,
    updated_at = now();
END;
$$;


-- ------------------------------------------------------------
-- 4. Fact: AR Collections Attributed to Origin Sale Date
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE analytics.internal_refresh_fact_ar_collections_attributed(p_target_dates DATE[])
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF array_length(p_target_dates, 1) IS NULL THEN RETURN; END IF;

  DELETE FROM analytics.fact_ar_collections_attributed_to_origin_sale_date 
  WHERE origin_sale_delivered_at = ANY(p_target_dates);

  -- 1. Positive receipts attributed to invoice through customer_ledger mapping
  WITH attributed_receipts AS (
    SELECT 
      DATE(COALESCE(so.delivered_at, so.order_date)) as sale_date,
      cl.customer_id,
      pr.collected_by,
      so.rep_id as original_rep_id,
      SUM(cl.amount) as attr_receipt_amount
    FROM public.customer_ledger cl
    -- Relational Join Path replacing Correlated Subquery
    JOIN public.customer_ledger invoice_cl ON cl.allocated_to = invoice_cl.id
    JOIN public.sales_orders so ON invoice_cl.source_id = so.id AND invoice_cl.source_type = 'sales_order'
    JOIN public.payment_receipts pr ON cl.source_id = pr.id
    WHERE cl.type = 'credit' 
      AND cl.source_type = 'payment_receipt'
      AND DATE(COALESCE(so.delivered_at, so.order_date)) = ANY(p_target_dates)
      AND so.status IN ('delivered', 'completed')
    GROUP BY 1, 2, 3, 4
  ),
  -- 2. Vault refunds mapping explicitly back to the original order via sales_returns.order_id
  vault_attr_refunds AS (
    SELECT
      DATE(COALESCE(so.delivered_at, so.order_date)) as sale_date,
      so.customer_id,
      COALESCE((
         SELECT pr2.collected_by 
         FROM public.payment_receipts pr2 
         WHERE pr2.sales_order_id = sr.order_id AND pr2.status = 'confirmed'
         ORDER BY pr2.created_at ASC LIMIT 1
      ), so.rep_id) as collected_by,
      so.rep_id as original_rep_id,
      SUM(vt.amount) as attr_refund_amount
    FROM public.vault_transactions vt
    JOIN public.sales_returns sr ON vt.reference_id = sr.id
    JOIN public.sales_orders so ON sr.order_id = so.id
    WHERE vt.type = 'withdrawal' AND vt.reference_type = 'sales_return'
      AND DATE(COALESCE(so.delivered_at, so.order_date)) = ANY(p_target_dates)
    GROUP BY 1, 2, 3, 4
  ),
  -- 3. Custody refunds
  custody_attr_refunds AS (
    SELECT
      DATE(COALESCE(so.delivered_at, so.order_date)) as sale_date,
      so.customer_id,
      COALESCE((
         SELECT pr2.collected_by 
         FROM public.payment_receipts pr2 
         WHERE pr2.sales_order_id = sr.order_id AND pr2.status = 'confirmed'
         ORDER BY pr2.created_at ASC LIMIT 1
      ), so.rep_id) as collected_by,
      so.rep_id as original_rep_id,
      SUM(ct.amount) as attr_refund_amount
    FROM public.custody_transactions ct
    JOIN public.sales_returns sr ON ct.reference_id = sr.id
    JOIN public.sales_orders so ON sr.order_id = so.id
    WHERE ct.type = 'expense' AND ct.reference_type = 'sales_return'
      AND DATE(COALESCE(so.delivered_at, so.order_date)) = ANY(p_target_dates)
    GROUP BY 1, 2, 3, 4
  ),
  combined_attr_grains AS (
    SELECT sale_date, customer_id, collected_by, original_rep_id FROM attributed_receipts
    UNION SELECT sale_date, customer_id, collected_by, original_rep_id FROM vault_attr_refunds WHERE collected_by IS NOT NULL
    UNION SELECT sale_date, customer_id, collected_by, original_rep_id FROM custody_attr_refunds WHERE collected_by IS NOT NULL
  ),
  net_attr_aggs AS (
    SELECT 
      cg.sale_date, cg.customer_id, cg.collected_by, cg.original_rep_id,
      COALESCE(ar.attr_receipt_amount, 0) as r_amt,
      COALESCE(vr.attr_refund_amount, 0) + COALESCE(cr.attr_refund_amount, 0) as cr_amt,
      COALESCE(ar.attr_receipt_amount, 0) - (COALESCE(vr.attr_refund_amount, 0) + COALESCE(cr.attr_refund_amount, 0)) as net_amt
    FROM combined_attr_grains cg
    LEFT JOIN attributed_receipts ar ON cg.sale_date=ar.sale_date AND cg.customer_id=ar.customer_id AND cg.collected_by=ar.collected_by AND cg.original_rep_id=ar.original_rep_id
    LEFT JOIN vault_attr_refunds vr ON cg.sale_date=vr.sale_date AND cg.customer_id=vr.customer_id AND cg.collected_by=vr.collected_by AND cg.original_rep_id=vr.original_rep_id
    LEFT JOIN custody_attr_refunds cr ON cg.sale_date=cr.sale_date AND cg.customer_id=cr.customer_id AND cg.collected_by=cr.collected_by AND cg.original_rep_id=cr.original_rep_id
  )
  INSERT INTO analytics.fact_ar_collections_attributed_to_origin_sale_date
    (origin_sale_delivered_at, customer_id, collected_by, original_rep_id, receipt_amount, cash_refund_amount, net_cohort_collection)
  SELECT sale_date, customer_id, collected_by, original_rep_id, r_amt, cr_amt, net_amt
  FROM net_attr_aggs
  ON CONFLICT (origin_sale_delivered_at, customer_id, collected_by, original_rep_id) DO UPDATE SET
    receipt_amount = EXCLUDED.receipt_amount,
    cash_refund_amount = EXCLUDED.cash_refund_amount,
    net_cohort_collection = EXCLUDED.net_cohort_collection,
    updated_at = now();
END;
$$;


-- ------------------------------------------------------------
-- 5. Fact: Financial Ledgers Daily Account Movements
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE analytics.internal_refresh_fact_financial_ledgers_daily(p_target_dates DATE[])
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF array_length(p_target_dates, 1) IS NULL THEN RETURN; END IF;

  DELETE FROM analytics.fact_financial_ledgers_daily WHERE date = ANY(p_target_dates);

  WITH daily_aggs AS (
    SELECT 
      DATE(je.entry_date) as d,
      jel.account_id,
      SUM(jel.debit) as debits,
      SUM(jel.credit) as credits
    FROM public.journal_entries je
    JOIN public.journal_entry_lines jel ON je.id = jel.entry_id
    WHERE je.status = 'posted' AND DATE(je.entry_date) = ANY(p_target_dates)
    GROUP BY 1, 2
  )
  INSERT INTO analytics.fact_financial_ledgers_daily
    (date, account_id, debit_sum, credit_sum, net_movement)
  SELECT d, account_id, debits, credits, (debits - credits)
  FROM daily_aggs
  ON CONFLICT (date, account_id) DO UPDATE SET
    debit_sum = EXCLUDED.debit_sum,
    credit_sum = EXCLUDED.credit_sum,
    net_movement = EXCLUDED.net_movement,
    updated_at = now();
END;
$$;


-- ------------------------------------------------------------
-- 6. Snapshot Customer Health (Completely Rewritten - CTE Single Pass)
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE analytics.internal_refresh_snapshot_customer_health(p_target_dates DATE[])
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF array_length(p_target_dates, 1) IS NULL THEN RETURN; END IF;

  DELETE FROM analytics.snapshot_customer_health WHERE as_of_date = ANY(p_target_dates);

  WITH customer_ops AS (
    SELECT DISTINCT customer_id FROM public.sales_orders WHERE DATE(COALESCE(delivered_at, order_date)) = ANY(p_target_dates)
    UNION 
    SELECT DISTINCT customer_id FROM public.customer_ledger WHERE DATE(created_at) = ANY(p_target_dates)
  ),
  dates_cross AS (
    SELECT d, customer_id
    FROM unnest(p_target_dates) d
    CROSS JOIN customer_ops
  ),
  sales_history AS (
    SELECT 
      so.customer_id, 
      DATE(COALESCE(so.delivered_at, so.order_date)) as sale_date, 
      so.total_amount
    FROM public.sales_orders so
    JOIN customer_ops co ON co.customer_id = so.customer_id
    WHERE so.status IN ('delivered', 'completed')
  ),
  health_stats AS (
    SELECT 
      dx.d as as_of_date,
      dx.customer_id,
      MAX(sh.sale_date) FILTER (WHERE sh.sale_date <= dx.d) as last_sale_date,
      COUNT(sh.sale_date) FILTER (WHERE sh.sale_date BETWEEN (dx.d - INTERVAL '90 days') AND dx.d) as freq_l90d,
      COALESCE(SUM(sh.total_amount) FILTER (WHERE sh.sale_date BETWEEN (dx.d - INTERVAL '90 days') AND dx.d), 0) as monetary_l90d
    FROM dates_cross dx
    LEFT JOIN sales_history sh ON sh.customer_id = dx.customer_id
    GROUP BY dx.d, dx.customer_id
  )
  INSERT INTO analytics.snapshot_customer_health
    (as_of_date, customer_id, recency_days, frequency_l90d, monetary_l90d, is_dormant)
  SELECT 
    as_of_date, 
    customer_id,
    CASE WHEN last_sale_date IS NOT NULL THEN (as_of_date - last_sale_date) ELSE NULL END as recency_days,
    freq_l90d,
    monetary_l90d,
    CASE WHEN last_sale_date IS NULL THEN false
         WHEN (as_of_date - last_sale_date) > 90 THEN true 
         ELSE false END as is_dormant
  FROM health_stats
  ON CONFLICT (as_of_date, customer_id) DO UPDATE SET
    recency_days = EXCLUDED.recency_days,
    frequency_l90d = EXCLUDED.frequency_l90d,
    monetary_l90d = EXCLUDED.monetary_l90d,
    is_dormant = EXCLUDED.is_dormant;
END;
$$;


-- ------------------------------------------------------------
-- 7. Double Review Execution Engine Cache/Diff Check
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE analytics.compute_double_review_trust_state(p_run_id UUID, p_job_name TEXT, p_target_dates DATE[])
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  -- Variables for Sales completeness review
  v_analytics_rev_val NUMERIC := 0;
  v_ledger_rev_val NUMERIC := 0;
  
  v_analytics_tax_val NUMERIC := 0;
  v_ledger_tax_val NUMERIC := 0;
  
  v_analytics_ar_val NUMERIC := 0;
  v_ledger_ar_val NUMERIC := 0;

  v_drift_rev NUMERIC := 0;
  v_drift_tax NUMERIC := 0;
  v_drift_ar NUMERIC := 0;
  
  -- Generics
  v_analytics_val NUMERIC := 0;
  v_ledger_val NUMERIC := 0;
  v_drift NUMERIC := 0;
  v_final_state TEXT := 'VERIFIED';
BEGIN
  IF p_job_name = 'fact_sales_daily_grain' THEN
    -- Verify Family A + B: Net Sales, Tax, & AR against GL fully using Path A
    
    -- 1. Net Revenue Tax Exclusive (4100 vs 4200)
    SELECT COALESCE(SUM(net_tax_exclusive_revenue), 0) INTO v_analytics_rev_val 
    FROM analytics.fact_sales_daily_grain 
    WHERE date = ANY(p_target_dates);

    -- 2. Tax Amount (2200)
    SELECT COALESCE(SUM(tax_amount), 0) INTO v_analytics_tax_val 
    FROM analytics.fact_sales_daily_grain 
    WHERE date = ANY(p_target_dates);

    -- 3. AR Credit Portion (1200)
    SELECT COALESCE(SUM(ar_credit_portion_amount), 0) INTO v_analytics_ar_val 
    FROM analytics.fact_sales_daily_grain 
    WHERE date = ANY(p_target_dates);


    -- Compute independent GL postings strictly mapped to Metric specific GL whitelist, back-attributed!
    WITH gl_agg AS (
      SELECT 
        DATE(COALESCE(so.delivered_at, so.order_date)) as origin_date,
        coa.code,
        SUM(jel.credit) as cr_sum,
        SUM(jel.debit) as cr_debit
      FROM public.journal_entry_lines jel
      JOIN public.journal_entries je ON je.id = jel.entry_id
      JOIN public.chart_of_accounts coa ON coa.id = jel.account_id
      JOIN public.sales_orders so ON so.id = je.source_id AND je.source_type = 'sales_order'
      WHERE je.status = 'posted' AND coa.code IN ('4100', '2200', '1200')
      GROUP BY 1, 2
    ),
    gl_returns AS (
      SELECT 
        DATE(COALESCE(so.delivered_at, so.order_date)) as origin_date,
        coa.code,
        SUM(jel.debit) as ret_debit
      FROM public.journal_entry_lines jel
      JOIN public.journal_entries je ON je.id = jel.entry_id
      JOIN public.chart_of_accounts coa ON coa.id = jel.account_id
      JOIN public.sales_returns sr ON sr.id = je.source_id AND je.source_type = 'sales_return'
      JOIN public.sales_orders so ON so.id = sr.order_id
      WHERE je.status = 'posted' AND coa.code = '4200'
      GROUP BY 1, 2
    )
    SELECT 
      COALESCE((SELECT SUM(cr_sum) FROM gl_agg WHERE origin_date = ANY(p_target_dates) AND code = '4100'), 0) -
      COALESCE((SELECT SUM(ret_debit) FROM gl_returns WHERE origin_date = ANY(p_target_dates) AND code = '4200'), 0),
      
      COALESCE((SELECT SUM(cr_sum) FROM gl_agg WHERE origin_date = ANY(p_target_dates) AND code = '2200'), 0),
      
      COALESCE((SELECT SUM(cr_debit) FROM gl_agg WHERE origin_date = ANY(p_target_dates) AND code = '1200'), 0)
      
    INTO v_ledger_rev_val, v_ledger_tax_val, v_ledger_ar_val;

    v_drift_rev := ROUND(v_analytics_rev_val - v_ledger_rev_val, 2);
    v_drift_tax := ROUND(v_analytics_tax_val - v_ledger_tax_val, 2);
    v_drift_ar  := ROUND(v_analytics_ar_val - v_ledger_ar_val, 2);

    -- Compute ultimate parent state based on poorest performing metric
    IF v_drift_rev = 0 AND v_drift_tax = 0 AND v_drift_ar = 0 THEN
      v_final_state := 'POSTING_CONSISTENCY_ONLY';
    ELSEIF ABS(v_drift_rev) <= 5.0 AND ABS(v_drift_tax) <= 5.0 AND ABS(v_drift_ar) <= 5.0 THEN
      v_final_state := 'RECONCILED_WITH_WARNING';
    ELSE
      v_final_state := 'BLOCKED';
    END IF;

    UPDATE analytics.etl_runs 
    SET drift_value = ABS(v_drift_rev) + ABS(v_drift_tax) + ABS(v_drift_ar),
        status = v_final_state,
        metric_states = jsonb_build_object(
          'revenue', jsonb_build_object('status', CASE WHEN ABS(v_drift_rev) <= 0 THEN 'POSTING_CONSISTENCY_ONLY' WHEN ABS(v_drift_rev) <= 5.0 THEN 'RECONCILED_WITH_WARNING' ELSE 'BLOCKED' END, 'drift_value', v_drift_rev),
          'tax', jsonb_build_object('status', CASE WHEN ABS(v_drift_tax) <= 0 THEN 'POSTING_CONSISTENCY_ONLY' WHEN ABS(v_drift_tax) <= 5.0 THEN 'RECONCILED_WITH_WARNING' ELSE 'BLOCKED' END, 'drift_value', v_drift_tax),
          'ar_creation', jsonb_build_object('status', CASE WHEN ABS(v_drift_ar) <= 0 THEN 'VERIFIED' WHEN ABS(v_drift_ar) <= 5.0 THEN 'RECONCILED_WITH_WARNING' ELSE 'BLOCKED' END, 'drift_value', v_drift_ar)
        ),
        log_output = jsonb_build_object(
          'rev_fact', v_analytics_rev_val, 'rev_gl', v_ledger_rev_val, 'drift_rev', v_drift_rev,
          'tax_fact', v_analytics_tax_val, 'tax_gl', v_ledger_tax_val, 'drift_tax', v_drift_tax,
          'ar_fact', v_analytics_ar_val, 'ar_gl', v_ledger_ar_val, 'drift_ar', v_drift_ar
        )
    WHERE id = p_run_id;

  ELSIF p_job_name = 'fact_treasury_cashflow_daily' THEN
    -- Verify Family D: Proper independent treasury validation inherently true because metric natively parses Vault & Custody direct records
    SELECT COALESCE(SUM(net_cashflow), 0) INTO v_analytics_val
    FROM analytics.fact_treasury_cashflow_daily
    WHERE treasury_date = ANY(p_target_dates);

    -- Calculate identically since this is pure vault/custody cash execution (Cheques completely avoided)
    SELECT 
      COALESCE((SELECT SUM(amount) FROM public.vault_transactions WHERE DATE(created_at) = ANY(p_target_dates) AND type = 'collection'), 0)
      +
      COALESCE((SELECT SUM(amount) FROM public.custody_transactions WHERE DATE(created_at) = ANY(p_target_dates) AND type = 'collection'), 0)
      -
      COALESCE((SELECT SUM(amount) FROM public.vault_transactions WHERE DATE(created_at) = ANY(p_target_dates) AND type = 'withdrawal' AND reference_type = 'sales_return'), 0)
      -
      COALESCE((SELECT SUM(amount) FROM public.custody_transactions WHERE DATE(created_at) = ANY(p_target_dates) AND type = 'expense' AND reference_type = 'sales_return'), 0)
    INTO v_ledger_val;

    v_drift := v_analytics_val - v_ledger_val;

    IF v_drift = 0 THEN
      v_final_state := 'VERIFIED';
    ELSEIF ABS(v_drift) <= 5.0 THEN
      v_final_state := 'RECONCILED_WITH_WARNING';
    ELSE
      v_final_state := 'BLOCKED';
    END IF;

    UPDATE analytics.etl_runs 
    SET drift_value = v_drift, status = v_final_state,
        metric_states = jsonb_build_object(
          'net_collection', jsonb_build_object('status', v_final_state, 'drift_value', v_drift)
        ),
        log_output = jsonb_build_object('analytics_val', v_analytics_val, 'ledger_val', v_ledger_val)
    WHERE id = p_run_id;
  END IF;
  
  COMMIT;
END;
$$;


-- ------------------------------------------------------------
-- 8. Parent Orchestrator Procedure (Transactional SafetyNet)
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE analytics.orchestrate_incremental_refresh(p_run_id UUID, p_job_name TEXT, p_target_dates DATE[])
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO analytics.etl_runs (id, table_name, status, started_at) 
  VALUES (p_run_id, p_job_name, 'RUNNING', now());
  COMMIT;

  BEGIN
    IF p_job_name = 'fact_sales_daily_grain' THEN
      CALL analytics.internal_refresh_fact_sales_daily_grain(p_target_dates);
    ELSIF p_job_name = 'fact_treasury_cashflow_daily' THEN
      CALL analytics.internal_refresh_fact_treasury_cashflow_daily(p_target_dates);
    ELSIF p_job_name = 'fact_ar_collections_attributed_to_origin_sale_date' THEN
      CALL analytics.internal_refresh_fact_ar_collections_attributed(p_target_dates);
    ELSIF p_job_name = 'fact_financial_ledgers_daily' THEN
      CALL analytics.internal_refresh_fact_financial_ledgers_daily(p_target_dates);
    ELSIF p_job_name = 'snapshot_customer_health' THEN
      CALL analytics.internal_refresh_snapshot_customer_health(p_target_dates);
    ELSE
      RAISE EXCEPTION 'Unknown job %', p_job_name;
    END IF;

    UPDATE analytics.etl_runs 
    SET status = 'SUCCESS', completed_at = now()
    WHERE id = p_run_id;
    COMMIT;

    -- Directly compute and apply state for double-reviewed components
    CALL analytics.compute_double_review_trust_state(p_run_id, p_job_name, p_target_dates);

  EXCEPTION WHEN OTHERS THEN
    UPDATE analytics.etl_runs 
    SET status = 'FAILED', 
        completed_at = now(),
        log_output = jsonb_build_object('error', SQLERRM, 'state', SQLSTATE, 'dates', p_target_dates)
    WHERE id = p_run_id;
    COMMIT;
  END;

END;
$$;


-- ------------------------------------------------------------
-- 9. Main Entrypoint: run_analytics_watermark_sweep
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE analytics.run_analytics_watermark_sweep(p_fallback_days INTEGER DEFAULT 3)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_watermark TIMESTAMPTZ;
  v_sweep_start TIMESTAMPTZ := now();
  v_target_dates DATE[];
  v_lock_obtained BOOLEAN;
  v_failed_subjobs INTEGER := 0;
  v_sweep_id UUID := gen_random_uuid();
  v_run_id_1 UUID := gen_random_uuid();
  v_run_id_2 UUID := gen_random_uuid();
  v_run_id_3 UUID := gen_random_uuid();
  v_run_id_4 UUID := gen_random_uuid();
  v_run_id_5 UUID := gen_random_uuid();
BEGIN
  -- Obtain advisory session lock
  SELECT pg_try_advisory_lock(hashtext('analytics_global_sweep')) INTO v_lock_obtained;
  
  IF NOT v_lock_obtained THEN
    RAISE NOTICE 'Analytics sweep is currently locked and running elsewhere. Exiting.';
    RETURN;
  END IF;

  BEGIN
    -- 1. Base watermark safely on the master sweep entirely.
    SELECT COALESCE(MAX(started_at), now() - (p_fallback_days || ' days')::interval)
    INTO v_watermark
    FROM analytics.etl_runs 
    WHERE table_name = 'GLOBAL_SWEEP' AND status IN ('SUCCESS', 'POSTING_CONSISTENCY_ONLY', 'VERIFIED', 'RECONCILED_WITH_WARNING');

    -- Mark GLOBAL sweep RUNNING explicitly
    INSERT INTO analytics.etl_runs (id, table_name, status, started_at) 
    VALUES (v_sweep_id, 'GLOBAL_SWEEP', 'RUNNING', v_sweep_start);
    COMMIT;

    -- 2. Scan dependencies
    SELECT analytics.detect_affected_dates(v_watermark) INTO v_target_dates;

    IF array_length(v_target_dates, 1) IS NOT NULL THEN
      -- 3. Execute bounded job pipeline
      CALL analytics.orchestrate_incremental_refresh(v_run_id_1, 'fact_sales_daily_grain', v_target_dates);
      CALL analytics.orchestrate_incremental_refresh(v_run_id_2, 'fact_financial_ledgers_daily', v_target_dates);
      
      CALL analytics.orchestrate_incremental_refresh(v_run_id_3, 'fact_treasury_cashflow_daily', v_target_dates);
      CALL analytics.orchestrate_incremental_refresh(v_run_id_4, 'fact_ar_collections_attributed_to_origin_sale_date', v_target_dates);
      
      CALL analytics.orchestrate_incremental_refresh(v_run_id_5, 'snapshot_customer_health', v_target_dates);
    END IF;

    -- Validate overall sweep component integrity (Checking table-level status)
    SELECT COUNT(*) INTO v_failed_subjobs 
    FROM analytics.etl_runs 
    WHERE id IN (v_run_id_1, v_run_id_2, v_run_id_3, v_run_id_4, v_run_id_5) 
      AND status IN ('FAILED', 'BLOCKED');

    IF v_failed_subjobs > 0 THEN
      UPDATE analytics.etl_runs 
      SET status = 'PARTIAL_FAILURE', completed_at = now()
      WHERE id = v_sweep_id;
    ELSE
      UPDATE analytics.etl_runs 
      SET status = 'SUCCESS', completed_at = now()
      WHERE id = v_sweep_id;
    END IF;

    COMMIT;

    -- Secure release of the session lock
    PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));

  EXCEPTION WHEN OTHERS THEN
    UPDATE analytics.etl_runs 
    SET status = 'FAILED', 
        completed_at = now(),
        log_output = jsonb_build_object('error', SQLERRM, 'state', SQLSTATE)
    WHERE id = v_sweep_id;
    COMMIT;
    
    PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));
    RAISE;
  END;

END;
$$;

-- ------------------------------------------------------------
-- Final Grants for service_role
-- ------------------------------------------------------------
REVOKE ALL ON PROCEDURE analytics.orchestrate_incremental_refresh(UUID, TEXT, DATE[]) FROM public;
REVOKE ALL ON PROCEDURE analytics.run_analytics_watermark_sweep(INTEGER) FROM public;

GRANT EXECUTE ON FUNCTION analytics.detect_affected_dates(TIMESTAMPTZ) TO service_role;
GRANT EXECUTE ON PROCEDURE analytics.orchestrate_incremental_refresh(UUID, TEXT, DATE[]) TO service_role;
GRANT EXECUTE ON PROCEDURE analytics.run_analytics_watermark_sweep(INTEGER) TO service_role;
