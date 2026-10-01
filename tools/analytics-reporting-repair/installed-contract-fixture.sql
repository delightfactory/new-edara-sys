CREATE ROLE postgres SUPERUSER;
ALTER TABLE public.sales_orders OWNER TO postgres; ALTER TABLE public.sales_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_order_items OWNER TO postgres; ALTER TABLE public.sales_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_returns OWNER TO postgres; ALTER TABLE public.sales_returns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_return_items OWNER TO postgres; ALTER TABLE public.sales_return_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_receipts OWNER TO postgres; ALTER TABLE public.payment_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_ledger OWNER TO postgres; ALTER TABLE public.customer_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vault_transactions OWNER TO postgres; ALTER TABLE public.vault_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.custody_transactions OWNER TO postgres; ALTER TABLE public.custody_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.journal_entries OWNER TO postgres; ALTER TABLE public.journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.journal_entry_lines OWNER TO postgres; ALTER TABLE public.journal_entry_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers OWNER TO postgres; ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses OWNER TO postgres; ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_payroll_runs OWNER TO postgres; ALTER TABLE public.hr_payroll_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chart_of_accounts OWNER TO postgres; ALTER TABLE public.chart_of_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_employees OWNER TO postgres; ALTER TABLE public.hr_employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.profitability_allocation_rule_sets OWNER TO postgres; ALTER TABLE analytics.profitability_allocation_rule_sets ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.profitability_allocation_rules OWNER TO postgres; ALTER TABLE analytics.profitability_allocation_rules ENABLE ROW LEVEL SECURITY;
ALTER PROCEDURE analytics.compute_double_review_trust_state(uuid,text,date[]) OWNER TO postgres;
ALTER FUNCTION analytics.detect_affected_dates(timestamp with time zone) OWNER TO postgres;
ALTER FUNCTION analytics.effective_sale_date(timestamp with time zone,date) OWNER TO postgres;
ALTER FUNCTION analytics.get_system_trust_state() OWNER TO postgres;
ALTER PROCEDURE analytics.internal_refresh_fact_ar_collections_attributed(date[]) OWNER TO postgres;
ALTER PROCEDURE analytics.internal_refresh_fact_branch_profit_daily(date[]) OWNER TO postgres;
ALTER PROCEDURE analytics.internal_refresh_fact_branch_profit_final_monthly(date[]) OWNER TO postgres;
ALTER PROCEDURE analytics.internal_refresh_fact_financial_ledgers_daily(date[]) OWNER TO postgres;
ALTER PROCEDURE analytics.internal_refresh_fact_geography_daily(date[]) OWNER TO postgres;
ALTER PROCEDURE analytics.internal_refresh_fact_gross_profit_daily_grain(date[]) OWNER TO postgres;
ALTER PROCEDURE analytics.internal_refresh_fact_profit_daily(date[]) OWNER TO postgres;
ALTER PROCEDURE analytics.internal_refresh_fact_sales_daily_grain(date[]) OWNER TO postgres;
ALTER PROCEDURE analytics.internal_refresh_fact_treasury_cashflow_daily(date[]) OWNER TO postgres;
ALTER PROCEDURE analytics.internal_refresh_profitability_data_quality_daily(date[]) OWNER TO postgres;
ALTER PROCEDURE analytics.internal_refresh_snapshot_branch_allocation_weights_monthly(date[]) OWNER TO postgres;
ALTER PROCEDURE analytics.internal_refresh_snapshot_customer_health(date[]) OWNER TO postgres;
ALTER PROCEDURE analytics.internal_refresh_snapshot_customer_risk(date[]) OWNER TO postgres;
ALTER PROCEDURE analytics.internal_refresh_snapshot_target_attainment(date[]) OWNER TO postgres;
ALTER PROCEDURE analytics.orchestrate_incremental_refresh(uuid,text,date[]) OWNER TO postgres;
CREATE OR REPLACE PROCEDURE analytics.run_analytics_watermark_sweep(IN p_fallback_days integer DEFAULT 3)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $procedure$
DECLARE
    v_watermark      TIMESTAMPTZ;
    v_sweep_start    TIMESTAMPTZ := now();
    v_target_dates   DATE[];
    v_lock_obtained  BOOLEAN;
    v_failed_subjobs INTEGER := 0;
    v_sweep_id       UUID := gen_random_uuid();
    v_run_id_1       UUID := gen_random_uuid(); v_run_id_2 UUID := gen_random_uuid(); v_run_id_3 UUID := gen_random_uuid();
    v_run_id_4       UUID := gen_random_uuid(); v_run_id_5 UUID := gen_random_uuid(); v_run_id_6 UUID := gen_random_uuid();
    v_run_id_7       UUID := gen_random_uuid(); v_run_id_8 UUID := gen_random_uuid(); v_run_id_9 UUID := gen_random_uuid();
    v_run_id_10      UUID := gen_random_uuid(); v_run_id_11 UUID := gen_random_uuid(); v_run_id_12 UUID := gen_random_uuid();
    v_run_id_13      UUID := gen_random_uuid(); v_run_id_14 UUID := gen_random_uuid();
BEGIN
    SELECT pg_try_advisory_lock(hashtext('analytics_global_sweep')) INTO v_lock_obtained;
    IF NOT v_lock_obtained THEN RAISE NOTICE 'Analytics sweep locked elsewhere — exiting.'; RETURN; END IF;

    BEGIN
        SELECT COALESCE(MAX(started_at), now() - (p_fallback_days || ' days')::interval) INTO v_watermark FROM analytics.etl_runs WHERE table_name = 'GLOBAL_SWEEP' AND status IN ('SUCCESS', 'POSTING_CONSISTENCY_ONLY', 'VERIFIED', 'RECONCILED_WITH_WARNING');

        INSERT INTO analytics.etl_runs (id, table_name, status, started_at) VALUES (v_sweep_id, 'GLOBAL_SWEEP', 'RUNNING', v_sweep_start);
        SELECT analytics.detect_affected_dates(v_watermark) INTO v_target_dates;

        IF array_length(v_target_dates, 1) IS NOT NULL THEN
            CALL analytics.orchestrate_incremental_refresh(v_run_id_1,  'fact_sales_daily_grain',                             v_target_dates);
            CALL analytics.orchestrate_incremental_refresh(v_run_id_2,  'fact_financial_ledgers_daily',                       v_target_dates);
            CALL analytics.orchestrate_incremental_refresh(v_run_id_3,  'fact_treasury_cashflow_daily',                       v_target_dates);
            CALL analytics.orchestrate_incremental_refresh(v_run_id_4,  'fact_ar_collections_attributed_to_origin_sale_date', v_target_dates);
            CALL analytics.orchestrate_incremental_refresh(v_run_id_5,  'snapshot_customer_health',                           v_target_dates);
            CALL analytics.orchestrate_incremental_refresh(v_run_id_6,  'snapshot_customer_risk',                             v_target_dates);
            CALL analytics.orchestrate_incremental_refresh(v_run_id_8,  'fact_geography_daily',                               v_target_dates);
            CALL analytics.orchestrate_incremental_refresh(v_run_id_9,  'fact_profit_daily',                                  v_target_dates);
            
            -- Phase 2
            CALL analytics.orchestrate_incremental_refresh(v_run_id_10, 'fact_gross_profit_daily_grain',                      v_target_dates);
            CALL analytics.orchestrate_incremental_refresh(v_run_id_11, 'fact_branch_profit_daily',                           v_target_dates);
            
            -- Phase 3
            CALL analytics.orchestrate_incremental_refresh(v_run_id_12, 'profitability_data_quality_daily',                   v_target_dates);
            CALL analytics.orchestrate_incremental_refresh(v_run_id_13, 'snapshot_branch_allocation_weights_monthly',         v_target_dates);
            CALL analytics.orchestrate_incremental_refresh(v_run_id_14, 'fact_branch_profit_final_monthly',                   v_target_dates);
        END IF;

        CALL analytics.orchestrate_incremental_refresh(v_run_id_7, 'snapshot_target_attainment', ARRAY[CURRENT_DATE]::DATE[]);

        SELECT COUNT(*) INTO v_failed_subjobs FROM analytics.etl_runs WHERE id IN (v_run_id_1, v_run_id_2, v_run_id_3, v_run_id_4, v_run_id_5, v_run_id_6, v_run_id_7, v_run_id_8, v_run_id_9, v_run_id_10, v_run_id_11, v_run_id_12, v_run_id_13, v_run_id_14) AND status IN ('FAILED', 'BLOCKED');

        IF v_failed_subjobs > 0 THEN UPDATE analytics.etl_runs SET status = 'PARTIAL_FAILURE', completed_at = now() WHERE id = v_sweep_id;
        ELSE UPDATE analytics.etl_runs SET status = 'SUCCESS', completed_at = now() WHERE id = v_sweep_id; END IF;

        PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));
    EXCEPTION WHEN OTHERS THEN
        UPDATE analytics.etl_runs SET status = 'FAILED', completed_at = now(), log_output = jsonb_build_object('error', SQLERRM, 'state', SQLSTATE) WHERE id = v_sweep_id;
        PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));
        RAISE;
    END;
END;
$procedure$;
ALTER PROCEDURE analytics.run_analytics_watermark_sweep(integer) OWNER TO postgres;
ALTER FUNCTION analytics.txn_date(timestamp with time zone) OWNER TO postgres;
CREATE OR REPLACE FUNCTION public.analytics_refresh_now()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'analytics'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_lock_available boolean;
BEGIN
  IF NOT check_permission(v_uid, 'reports.view_all') THEN
    RAISE EXCEPTION 'analytics_unauthorized:domain=all';
  END IF;

  -- Test if the sweep lock is currently held
  SELECT pg_try_advisory_lock(hashtext('analytics_global_sweep')) INTO v_lock_available;
  IF NOT v_lock_available THEN
    RETURN FALSE;
  END IF;
  
  -- Release immediately so the procedure can take it
  PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));

  CALL analytics.run_analytics_watermark_sweep(1);
  RETURN TRUE;
END;
$function$;
ALTER FUNCTION analytics_refresh_now() OWNER TO postgres;
