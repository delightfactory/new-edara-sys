-- ============================================================
-- 88_profitability_reporting_layer.sql
-- EDARA v2 - Analytics Profitability Layer
-- Implements daily profitability fact table, data orchestration,
-- double review trust state (Phase 1 COGS only), and public RPCs.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Table Creation
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS analytics.fact_profit_daily (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    date DATE NOT NULL UNIQUE,
    net_revenue NUMERIC(15,2) NOT NULL DEFAULT 0,
    cogs NUMERIC(15,2) NOT NULL DEFAULT 0,
    gross_profit NUMERIC(15,2) GENERATED ALWAYS AS (net_revenue - cogs) STORED,
    operating_expenses NUMERIC(15,2) NOT NULL DEFAULT 0,
    payroll_expenses NUMERIC(15,2) NOT NULL DEFAULT 0,
    net_profit NUMERIC(15,2) GENERATED ALWAYS AS (net_revenue - cogs - operating_expenses - payroll_expenses) STORED,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index and Table Comments
CREATE INDEX IF NOT EXISTS idx_fact_profit_daily_date ON analytics.fact_profit_daily USING btree (date);

COMMENT ON TABLE analytics.fact_profit_daily IS 'Daily Profitability Analytics. net_revenue يمثل الإيراد الصافي من طبقة المبيعات التحليلية ويعكس الخصومات. cogs مأخوذ من 5100. 5300 مستبعد صراحة. التقارير اليومية قد تتأثر بانزياح زمني محدود. العرض الشهري هو العرض الإداري الافتراضي.';

-- RLS Enforcement
ALTER TABLE analytics.fact_profit_daily ENABLE ROW LEVEL SECURITY;

CREATE POLICY view_all_profitability ON analytics.fact_profit_daily 
FOR SELECT TO authenticated 
USING (public.check_permission(auth.uid(), 'reports.view_all') OR public.check_permission(auth.uid(), 'reports.financial'));

-- Add explicit GRANTs as indicated in the delivery report
GRANT SELECT ON analytics.fact_profit_daily TO authenticated;

-- ------------------------------------------------------------
-- 2. Internal Data Processing Routine
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE analytics.internal_refresh_fact_profit_daily(p_target_dates DATE[])
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_cogs_id UUID;
    v_op_ids UUID[];
    v_pay_ids UUID[];
BEGIN
    IF array_length(p_target_dates, 1) IS NULL THEN RETURN; END IF;

    -- Translate account codes to UUIDs once at the beginning
    SELECT id INTO v_cogs_id FROM public.chart_of_accounts WHERE code = '5100';
    SELECT array_agg(id) INTO v_op_ids FROM public.chart_of_accounts WHERE code IN ('5200','5210','5220','5230');
    SELECT array_agg(id) INTO v_pay_ids FROM public.chart_of_accounts WHERE code IN ('5310','5320','5330','5335');

    -- Idempotent setup
    DELETE FROM analytics.fact_profit_daily WHERE date = ANY(p_target_dates);

    WITH rev_agg AS (
        SELECT date as d, SUM(net_tax_exclusive_revenue) as net_rev
        FROM analytics.fact_sales_daily_grain
        WHERE date = ANY(p_target_dates)
        GROUP BY 1
    ),
    cogs_agg AS (
        SELECT date as d, SUM(debit_sum) as cogs_debit
        FROM analytics.fact_financial_ledgers_daily
        WHERE date = ANY(p_target_dates) AND account_id = v_cogs_id
        GROUP BY 1
    ),
    op_agg AS (
        SELECT date as d, SUM(debit_sum) as op_debit
        FROM analytics.fact_financial_ledgers_daily
        WHERE date = ANY(p_target_dates) AND account_id = ANY(v_op_ids)
        GROUP BY 1
    ),
    pay_agg AS (
        SELECT date as d, SUM(debit_sum) as pay_debit
        FROM analytics.fact_financial_ledgers_daily
        WHERE date = ANY(p_target_dates) AND account_id = ANY(v_pay_ids)
        GROUP BY 1
    ),
    all_dates AS (
        SELECT unnest(p_target_dates) AS d
    )
    INSERT INTO analytics.fact_profit_daily (
        date, net_revenue, cogs, operating_expenses, payroll_expenses
    )
    SELECT 
        ad.d,
        COALESCE(r.net_rev, 0),
        COALESCE(c.cogs_debit, 0),
        COALESCE(o.op_debit, 0),
        COALESCE(p.pay_debit, 0)
    FROM all_dates ad
    LEFT JOIN rev_agg r ON r.d = ad.d
    LEFT JOIN cogs_agg c ON c.d = ad.d
    LEFT JOIN op_agg o ON o.d = ad.d
    LEFT JOIN pay_agg p ON p.d = ad.d
    -- Comments enforce conditions as requested:
    -- الإيراد هنا بعد خصومات البنود
    -- COGS يعتمد على entry_date
    -- الانزياح اليومي المحتمل معروف ومقبول في المرحلة الأولى
    -- الهدف الإداري الأساسي هو الفترات المجمعة لا اليوميات الدقيقة لحالات آخر الليل
    ON CONFLICT (date) DO UPDATE SET
        net_revenue = EXCLUDED.net_revenue,
        cogs = EXCLUDED.cogs,
        operating_expenses = EXCLUDED.operating_expenses,
        payroll_expenses = EXCLUDED.payroll_expenses,
        updated_at = now();
END;
$$;


-- ------------------------------------------------------------
-- 3. Update orchestrate_incremental_refresh (From 86)
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
        ELSIF p_job_name = 'fact_profit_daily' THEN
          CALL analytics.internal_refresh_fact_profit_daily(v_chunk_dates);
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
-- 4. Update compute_double_review_trust_state (From 86)
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

  ELSIF p_job_name = 'fact_profit_daily' THEN
    -- هذه ليست مراجعة ربحية كاملة
    -- هذه مراجعة تكلفة فقط
    -- السبب: اختلاف أساس التاريخ بين بعض المكونات يجعل مراجعة الربح الكامل يوميًا غير مناسبة في المرحلة الأولى
    SELECT COALESCE(SUM(cogs), 0) INTO v_analytics_val FROM analytics.fact_profit_daily WHERE date = ANY(p_target_dates);
    
    WITH target_dates AS (SELECT unnest(p_target_dates) AS tgt_date)
    SELECT COALESCE(SUM(jel.debit), 0) INTO v_ledger_val
    FROM target_dates td
    JOIN public.journal_entries je ON je.entry_date = td.tgt_date
    JOIN public.journal_entry_lines jel ON je.id = jel.entry_id
    JOIN public.chart_of_accounts coa ON coa.id = jel.account_id
    WHERE je.status = 'posted' AND coa.code = '5100';

    v_drift := ROUND(v_analytics_val - v_ledger_val, 2);

    IF v_drift = 0 THEN       v_final_state := 'POSTING_CONSISTENCY_ONLY';
    ELSEIF ABS(v_drift) <= 5.0 THEN v_final_state := 'RECONCILED_WITH_WARNING';
    ELSE                      v_final_state := 'BLOCKED';
    END IF;

    UPDATE analytics.etl_runs
    SET drift_value = ABS(v_drift), status = v_final_state,
        metric_states = jsonb_build_object(
            'cogs_check', jsonb_build_object(
                'status', CASE WHEN ABS(v_drift) <= 0 THEN 'POSTING_CONSISTENCY_ONLY' WHEN ABS(v_drift) <= 5.0 THEN 'RECONCILED_WITH_WARNING' ELSE 'BLOCKED' END, 
                'drift_value', v_drift,
                'scope', 'cogs_only_phase1'
            )
        ),
        log_output = COALESCE(log_output, '{}'::jsonb) || jsonb_build_object(
            'cogs_fact', v_analytics_val, 
            'cogs_gl', v_ledger_val, 
            'drift', v_drift,
            'note', 'هذه مراجعة مرحلة أولى للتكلفة فقط وليست مراجعة كاملة لعناصر الربحية'
        )
    WHERE id = p_run_id;
  END IF;
END;
$$;


-- ------------------------------------------------------------
-- 5. Update run_analytics_watermark_sweep (From 85)
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
  v_run_id_3        UUID := gen_random_uuid(); v_run_id_4 UUID := gen_random_uuid();
  v_run_id_5        UUID := gen_random_uuid(); v_run_id_6 UUID := gen_random_uuid();
  v_run_id_7        UUID := gen_random_uuid(); v_run_id_8 UUID := gen_random_uuid();
  v_run_id_9        UUID := gen_random_uuid();
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
      CALL analytics.orchestrate_incremental_refresh(v_run_id_9, 'fact_profit_daily',                                  v_target_dates);
    END IF;

    -- Targets run daily independently to advance progress toward deadlines
    CALL analytics.orchestrate_incremental_refresh(v_run_id_7, 'snapshot_target_attainment', ARRAY[CURRENT_DATE]::DATE[]);

    SELECT COUNT(*) INTO v_failed_subjobs FROM analytics.etl_runs WHERE id IN (v_run_id_1, v_run_id_2, v_run_id_3, v_run_id_4, v_run_id_5, v_run_id_6, v_run_id_7, v_run_id_8, v_run_id_9) AND status IN ('FAILED', 'BLOCKED');
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
-- 6. Update run_historical_backfill (From 85)
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
      CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_profit_daily', v_chunk_dates);
      v_chunks_done := v_chunks_done + 1; v_chunk_start := v_chunk_end + 1;
    END LOOP;
    RAISE NOTICE 'Historical backfill completed. Chunks processed: %', v_chunks_done;
    PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));
  EXCEPTION WHEN OTHERS THEN PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep')); RAISE;
  END;
END;
$$;


-- ------------------------------------------------------------
-- 7. Public Read Functions
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.analytics_profit_summary(date_from DATE, date_to DATE)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_net_rev NUMERIC; v_cogs NUMERIC; v_gp NUMERIC; v_gp_pct NUMERIC;
    v_op NUMERIC; v_pay NUMERIC; v_np NUMERIC; v_np_pct NUMERIC;
BEGIN
    IF NOT public.check_permission(auth.uid(), 'reports.view_all') AND NOT public.check_permission(auth.uid(), 'reports.financial') THEN
        RAISE EXCEPTION 'Access denied. Requires reports.view_all or reports.financial';
    END IF;

    SELECT 
        COALESCE(SUM(net_revenue), 0), COALESCE(SUM(cogs), 0), COALESCE(SUM(gross_profit), 0),
        COALESCE(SUM(operating_expenses), 0), COALESCE(SUM(payroll_expenses), 0), COALESCE(SUM(net_profit), 0)
    INTO v_net_rev, v_cogs, v_gp, v_op, v_pay, v_np
    FROM analytics.fact_profit_daily
    WHERE date >= date_from AND date <= date_to;

    IF v_net_rev > 0 THEN
        v_gp_pct := ROUND((v_gp / v_net_rev) * 100, 2);
        v_np_pct := ROUND((v_np / v_net_rev) * 100, 2);
    ELSE
        v_gp_pct := 0; v_np_pct := 0;
    END IF;

    -- الإيراد يعكس خصومات البند. اليومية قد تتأثر بانزياح محدود. العرض الشهري هو الافتراضي الإداري الموصى به.
    RETURN jsonb_build_object(
        'net_revenue', v_net_rev, 'cogs', v_cogs, 'gross_profit', v_gp, 'gross_margin_pct', v_gp_pct,
        'operating_expenses', v_op, 'payroll_expenses', v_pay, 'net_profit', v_np, 'net_margin_pct', v_np_pct
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.analytics_profit_summary(DATE, DATE) TO authenticated;

CREATE OR REPLACE FUNCTION public.analytics_profit_trend(date_from DATE, date_to DATE, granularity TEXT DEFAULT 'monthly')
RETURNS TABLE (
    period TEXT,
    net_revenue NUMERIC,
    cogs NUMERIC,
    gross_profit NUMERIC,
    operating_expenses NUMERIC,
    payroll_expenses NUMERIC,
    net_profit NUMERIC
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    IF NOT public.check_permission(auth.uid(), 'reports.view_all') AND NOT public.check_permission(auth.uid(), 'reports.financial') THEN
        RAISE EXCEPTION 'Access denied. Requires reports.view_all or reports.financial';
    END IF;

    IF granularity NOT IN ('daily', 'monthly') THEN
        RAISE EXCEPTION 'Unsupported granularity %. Only daily, monthly are allowed in this phase', granularity;
    END IF;

    -- الإيراد يعكس خصومات البند. اليومية قد تتأثر بانزياح محدود. العرض الشهري هو الافتراضي الإداري الموصى به.
    IF granularity = 'daily' THEN
        RETURN QUERY
        SELECT 
            to_char(fp.date, 'YYYY-MM-DD') AS period, 
            fp.net_revenue, fp.cogs, fp.gross_profit,
            fp.operating_expenses, fp.payroll_expenses, fp.net_profit
        FROM analytics.fact_profit_daily fp
        WHERE fp.date >= date_from AND fp.date <= date_to
        ORDER BY fp.date ASC;
    ELSE
        RETURN QUERY
        SELECT 
            to_char(date_trunc('month', fp.date)::DATE, 'YYYY-MM') AS period,
            SUM(fp.net_revenue)::NUMERIC, 
            SUM(fp.cogs)::NUMERIC, 
            SUM(fp.gross_profit)::NUMERIC,
            SUM(fp.operating_expenses)::NUMERIC, 
            SUM(fp.payroll_expenses)::NUMERIC, 
            SUM(fp.net_profit)::NUMERIC
        FROM analytics.fact_profit_daily fp
        WHERE fp.date >= date_from AND fp.date <= date_to
        GROUP BY 1
        ORDER BY 1 ASC;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.analytics_profit_trend(DATE, DATE, TEXT) TO authenticated;
