-- ============================================================
-- 86_analytics_sweep_chunking_fix.sql
-- EDARA v2 - Reporting Analytics: Sweep Chunking & Trust State Optimization
-- Secures atomicity, eliminates full table scans in trust checks,
-- and preserves complete parent-job observational semantics.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Chunked Orchestrator with Atomic Exclusivity
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE analytics.orchestrate_incremental_refresh(
  p_run_id       UUID,
  p_job_name     TEXT,
  p_target_dates DATE[]
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_normalized_dates DATE[];
  v_total            INTEGER;
  v_chunk_size       INTEGER := 15;
  v_chunk_idx        INTEGER := 0;
  v_chunk_dates      DATE[];
  v_chunk_count      INTEGER;
  v_min_date         DATE;
  v_max_date         DATE;
  v_chunks_detail    JSONB := '[]'::jsonb;
BEGIN
  -- 1. Always create the unified parent run log first
  INSERT INTO analytics.etl_runs (id, table_name, status, started_at)
  VALUES (p_run_id, p_job_name, 'RUNNING', now())
  ON CONFLICT (id) DO UPDATE SET status = 'RUNNING', started_at = now();

  -- 2. Normalize input dates (dedupe + sort)
  SELECT array_agg(d ORDER BY d ASC) INTO v_normalized_dates
  FROM (SELECT DISTINCT unnest(p_target_dates) AS d) sub;

  v_total := coalesce(array_length(v_normalized_dates, 1), 0);

  IF v_total = 0 THEN
    UPDATE analytics.etl_runs
    SET status = 'SUCCESS', completed_at = now(), log_output = jsonb_build_object('message', 'No dates to process')
    WHERE id = p_run_id;
    RETURN;
  END IF;

  -- 3. Execute logic within a savepoint (BEGIN block catches and implicitly rolls back on exception)
  BEGIN
    WHILE (v_chunk_idx * v_chunk_size) < v_total LOOP
      v_chunk_dates := v_normalized_dates[ (v_chunk_idx * v_chunk_size) + 1 : LEAST((v_chunk_idx + 1) * v_chunk_size, v_total) ];
      v_chunk_count := coalesce(array_length(v_chunk_dates, 1), 0);
      
      IF v_chunk_count > 0 THEN
        v_min_date := v_chunk_dates[1];
        v_max_date := v_chunk_dates[v_chunk_count];

        IF    p_job_name = 'fact_sales_daily_grain' THEN
          CALL analytics.internal_refresh_fact_sales_daily_grain(v_chunk_dates);
        ELSIF p_job_name = 'fact_treasury_cashflow_daily' THEN
          CALL analytics.internal_refresh_fact_treasury_cashflow_daily(v_chunk_dates);
        ELSIF p_job_name = 'fact_ar_collections_attributed_to_origin_sale_date' THEN
          CALL analytics.internal_refresh_fact_ar_collections_attributed(v_chunk_dates);
        ELSIF p_job_name = 'fact_financial_ledgers_daily' THEN
          CALL analytics.internal_refresh_fact_financial_ledgers_daily(v_chunk_dates);
        ELSIF p_job_name = 'snapshot_customer_health' THEN
          CALL analytics.internal_refresh_snapshot_customer_health(v_chunk_dates);
        -- ── Wave 2 ────────────────────────────────────────────────
        ELSIF p_job_name = 'snapshot_customer_risk' THEN
          CALL analytics.internal_refresh_snapshot_customer_risk(v_chunk_dates);
        ELSIF p_job_name = 'snapshot_target_attainment' THEN
          CALL analytics.internal_refresh_snapshot_target_attainment(v_chunk_dates);
        ELSIF p_job_name = 'fact_geography_daily' THEN
          CALL analytics.internal_refresh_fact_geography_daily(v_chunk_dates);
        ELSE
          RAISE EXCEPTION 'Unknown job: %', p_job_name;
        END IF;

        v_chunks_detail := v_chunks_detail || jsonb_build_object(
          'idx', v_chunk_idx, 'count', v_chunk_count, 'min_date', v_min_date, 'max_date', v_max_date, 'status', 'SUCCESS'
        );
      END IF;

      v_chunk_idx := v_chunk_idx + 1;
    END LOOP;

    -- Update parent log to reflect successful chunk completion prior to trust check
    UPDATE analytics.etl_runs
    SET status = 'SUCCESS', completed_at = now(),
        log_output = jsonb_build_object(
          'affected_dates_count', v_total, 
          'min_affected_date', v_normalized_dates[1],
          'max_affected_date', v_normalized_dates[v_total],
          'chunks_processed', v_chunk_idx, 
          'chunks_detail', v_chunks_detail
        )
    WHERE id = p_run_id;

    -- 4. Execute the trust state exactly ONCE for the entirety of normalized dates
    CALL analytics.compute_double_review_trust_state(p_run_id, p_job_name, v_normalized_dates);

  EXCEPTION WHEN OTHERS THEN
    -- In PostgreSQL, catching an exception inherently rolls back everything done in this BEGIN block
    UPDATE analytics.etl_runs
    SET status       = 'FAILED',
        completed_at = now(),
        log_output   = jsonb_build_object(
          'error', SQLERRM, 'state', SQLSTATE, 'failed_at_chunk_idx', v_chunk_idx, 'total_normalized_dates', v_total
        )
    WHERE id = p_run_id;
  END;
END;
$$;

-- ------------------------------------------------------------
-- 2. Heavy Optimized Trust State (Cairo Timezone + Range Joins)
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE analytics.compute_double_review_trust_state(p_run_id UUID, p_job_name TEXT, p_target_dates DATE[])
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_analytics_rev_val NUMERIC := 0; v_ledger_rev_val NUMERIC := 0;
  v_analytics_tax_val NUMERIC := 0; v_ledger_tax_val NUMERIC := 0;
  v_analytics_ar_val NUMERIC := 0;  v_ledger_ar_val  NUMERIC := 0;
  v_drift_rev NUMERIC := 0; v_drift_tax NUMERIC := 0; v_drift_ar NUMERIC := 0;
  
  v_analytics_val NUMERIC := 0; v_ledger_val NUMERIC := 0; v_drift NUMERIC := 0;
  v_final_state TEXT := 'VERIFIED';
BEGIN
  IF p_job_name = 'fact_sales_daily_grain' THEN
    SELECT COALESCE(SUM(net_tax_exclusive_revenue), 0) INTO v_analytics_rev_val FROM analytics.fact_sales_daily_grain WHERE date = ANY(p_target_dates);
    SELECT COALESCE(SUM(tax_amount), 0) INTO v_analytics_tax_val FROM analytics.fact_sales_daily_grain WHERE date = ANY(p_target_dates);
    SELECT COALESCE(SUM(ar_credit_portion_amount), 0) INTO v_analytics_ar_val FROM analytics.fact_sales_daily_grain WHERE date = ANY(p_target_dates);

    WITH target_dates AS (SELECT unnest(p_target_dates) AS tgt_date),
    gl_agg AS (
      SELECT 
        td.tgt_date as origin_date, coa.code, SUM(jel.credit) as cr_sum, SUM(jel.debit) as cr_debit
      FROM target_dates td
      JOIN public.sales_orders so ON (
           (so.delivered_at IS NOT NULL AND so.delivered_at >= (td.tgt_date::timestamp AT TIME ZONE 'Africa/Cairo') AND so.delivered_at < ((td.tgt_date + 1)::timestamp AT TIME ZONE 'Africa/Cairo'))
           OR
           (so.delivered_at IS NULL AND so.order_date = td.tgt_date)
      )
      JOIN public.journal_entries je ON je.source_id = so.id AND je.source_type = 'sales_order'
      JOIN public.journal_entry_lines jel ON je.id = jel.entry_id
      JOIN public.chart_of_accounts coa ON coa.id = jel.account_id
      WHERE je.status = 'posted' AND coa.code IN ('4100', '2200', '1200')
      GROUP BY 1, 2
    ),
    gl_returns AS (
      SELECT 
        td.tgt_date as origin_date, coa.code, SUM(jel.debit) as ret_debit
      FROM target_dates td
      JOIN public.sales_orders so ON (
           (so.delivered_at IS NOT NULL AND so.delivered_at >= (td.tgt_date::timestamp AT TIME ZONE 'Africa/Cairo') AND so.delivered_at < ((td.tgt_date + 1)::timestamp AT TIME ZONE 'Africa/Cairo'))
           OR
           (so.delivered_at IS NULL AND so.order_date = td.tgt_date)
      )
      JOIN public.sales_returns sr ON sr.order_id = so.id
      JOIN public.journal_entries je ON je.source_id = sr.id AND je.source_type = 'sales_return'
      JOIN public.journal_entry_lines jel ON je.id = jel.entry_id
      JOIN public.chart_of_accounts coa ON coa.id = jel.account_id
      WHERE je.status = 'posted' AND coa.code = '4200'
      GROUP BY 1, 2
    )
    SELECT 
      COALESCE((SELECT SUM(cr_sum) FROM gl_agg WHERE code = '4100'), 0) - COALESCE((SELECT SUM(ret_debit) FROM gl_returns WHERE code = '4200'), 0),
      COALESCE((SELECT SUM(cr_sum) FROM gl_agg WHERE code = '2200'), 0),
      COALESCE((SELECT SUM(cr_debit) FROM gl_agg WHERE code = '1200'), 0)
    INTO v_ledger_rev_val, v_ledger_tax_val, v_ledger_ar_val;

    v_drift_rev := ROUND(v_analytics_rev_val - v_ledger_rev_val, 2);
    v_drift_tax := ROUND(v_analytics_tax_val - v_ledger_tax_val, 2);
    v_drift_ar  := ROUND(v_analytics_ar_val - v_ledger_ar_val, 2);

    IF v_drift_rev = 0 AND v_drift_tax = 0 AND v_drift_ar = 0 THEN
      v_final_state := 'POSTING_CONSISTENCY_ONLY';
    ELSEIF ABS(v_drift_rev) <= 5.0 AND ABS(v_drift_tax) <= 5.0 AND ABS(v_drift_ar) <= 5.0 THEN
      v_final_state := 'RECONCILED_WITH_WARNING';
    ELSE
      v_final_state := 'BLOCKED';
    END IF;

    UPDATE analytics.etl_runs 
    SET drift_value = ABS(v_drift_rev) + ABS(v_drift_tax) + ABS(v_drift_ar), status = v_final_state,
        metric_states = jsonb_build_object(
          'revenue', jsonb_build_object('status', CASE WHEN ABS(v_drift_rev) <= 0 THEN 'POSTING_CONSISTENCY_ONLY' WHEN ABS(v_drift_rev) <= 5.0 THEN 'RECONCILED_WITH_WARNING' ELSE 'BLOCKED' END, 'drift_value', v_drift_rev),
          'tax', jsonb_build_object('status', CASE WHEN ABS(v_drift_tax) <= 0 THEN 'POSTING_CONSISTENCY_ONLY' WHEN ABS(v_drift_tax) <= 5.0 THEN 'RECONCILED_WITH_WARNING' ELSE 'BLOCKED' END, 'drift_value', v_drift_tax),
          'ar_creation', jsonb_build_object('status', CASE WHEN ABS(v_drift_ar) <= 0 THEN 'VERIFIED' WHEN ABS(v_drift_ar) <= 5.0 THEN 'RECONCILED_WITH_WARNING' ELSE 'BLOCKED' END, 'drift_value', v_drift_ar)
        ),
        log_output = COALESCE(log_output, '{}'::jsonb) || jsonb_build_object(
          'rev_fact', v_analytics_rev_val, 'rev_gl', v_ledger_rev_val, 'drift_rev', v_drift_rev,
          'tax_fact', v_analytics_tax_val, 'tax_gl', v_ledger_tax_val, 'drift_tax', v_drift_tax,
          'ar_fact', v_analytics_ar_val, 'ar_gl', v_ledger_ar_val, 'drift_ar', v_drift_ar
        )
    WHERE id = p_run_id;

  ELSIF p_job_name = 'fact_treasury_cashflow_daily' THEN
    SELECT COALESCE(SUM(net_cashflow), 0) INTO v_analytics_val FROM analytics.fact_treasury_cashflow_daily WHERE treasury_date = ANY(p_target_dates);

    SELECT 
      COALESCE((SELECT SUM(amount) FROM public.vault_transactions vt JOIN unnest(p_target_dates) AS td ON vt.created_at >= (td::timestamp AT TIME ZONE 'Africa/Cairo') AND vt.created_at < ((td + 1)::timestamp AT TIME ZONE 'Africa/Cairo') WHERE vt.type = 'collection'), 0)
      +
      COALESCE((SELECT SUM(amount) FROM public.custody_transactions ct JOIN unnest(p_target_dates) AS td ON ct.created_at >= (td::timestamp AT TIME ZONE 'Africa/Cairo') AND ct.created_at < ((td + 1)::timestamp AT TIME ZONE 'Africa/Cairo') WHERE ct.type = 'collection'), 0)
      -
      COALESCE((SELECT SUM(amount) FROM public.vault_transactions vt JOIN unnest(p_target_dates) AS td ON vt.created_at >= (td::timestamp AT TIME ZONE 'Africa/Cairo') AND vt.created_at < ((td + 1)::timestamp AT TIME ZONE 'Africa/Cairo') WHERE vt.type = 'withdrawal' AND vt.reference_type = 'sales_return'), 0)
      -
      COALESCE((SELECT SUM(amount) FROM public.custody_transactions ct JOIN unnest(p_target_dates) AS td ON ct.created_at >= (td::timestamp AT TIME ZONE 'Africa/Cairo') AND ct.created_at < ((td + 1)::timestamp AT TIME ZONE 'Africa/Cairo') WHERE ct.type = 'expense' AND ct.reference_type = 'sales_return'), 0)
    INTO v_ledger_val;

    v_drift := ROUND(v_analytics_val - v_ledger_val, 2);

    IF v_drift = 0 THEN       v_final_state := 'VERIFIED';
    ELSEIF ABS(v_drift) <= 5.0 THEN v_final_state := 'RECONCILED_WITH_WARNING';
    ELSE                      v_final_state := 'BLOCKED';
    END IF;

    UPDATE analytics.etl_runs 
    SET drift_value = ABS(v_drift), status = v_final_state,
        metric_states = jsonb_build_object(
          'net_collection', jsonb_build_object('status', CASE WHEN ABS(v_drift) <= 0 THEN 'VERIFIED' WHEN ABS(v_drift) <= 5.0 THEN 'RECONCILED_WITH_WARNING' ELSE 'BLOCKED' END, 'drift_value', v_drift)
        ),
        log_output = COALESCE(log_output, '{}'::jsonb) || jsonb_build_object('val_fact', v_analytics_val, 'val_gl', v_ledger_val, 'drift', v_drift)
    WHERE id = p_run_id;
  END IF;
END;
$$;
