-- Analytics IO repair: approved as-of population and reporting invalidation.
-- ONE atomic statement; no source business data or cron commands are executed.
DO $atomic_reporting_release$
BEGIN
 PERFORM set_config('lock_timeout','1500ms',true);
 PERFORM set_config('statement_timeout','30s',true);
 EXECUTE $reviewed_release_sql$
-- Exact object/body preconditions for NEW-EDARA-SYS; no business data scan.
DO $release_preflight$
DECLARE x RECORD; rel REGCLASS; actual TEXT; legacy_ok BOOLEAN:=true; final_ok BOOLEAN:=true;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'Release must run as the verified postgres migration owner'; END IF;
 IF current_setting('server_version_num')::int<170000 OR current_setting('server_version_num')::int>=180000 THEN
  RAISE EXCEPTION 'This release was qualified for PostgreSQL 17'; END IF;
 IF NOT pg_has_role(current_user,'pg_read_all_stats','USAGE') THEN RAISE EXCEPTION 'Migration owner lacks statistics visibility'; END IF;
 IF EXISTS(SELECT 1 FROM pg_prepared_xacts WHERE database=current_database()) THEN RAISE EXCEPTION 'Resolve prepared transactions first'; END IF;
 IF NOT pg_try_advisory_xact_lock(hashtext('analytics_global_sweep')) THEN RAISE EXCEPTION 'Analytics sweep/backfill is active'; END IF;
 FOR x IN SELECT * FROM (VALUES
('analytics.compute_double_review_trust_state(uuid,text,date[])','dbebdc527883bc3cdc84b3929ef56922','dbebdc527883bc3cdc84b3929ef56922','postgres',true),
('analytics.detect_affected_dates(timestamp with time zone)','65a54520e389cb3071fe5296aec33140','65a54520e389cb3071fe5296aec33140','postgres',true),
('analytics.effective_sale_date(timestamp with time zone,date)','4786d33f6b4c26afeafac3f3f7cf09e7','4786d33f6b4c26afeafac3f3f7cf09e7','postgres',false),
('analytics.get_system_trust_state()','3f9e753044b8b75196956dbe9bb0962b','1358adc4db7aa36b7d3a67989feb7ecb','postgres',true),
('analytics.internal_refresh_fact_ar_collections_attributed(date[])','554e5b5a1d5bbfd33684d989add4faf4','554e5b5a1d5bbfd33684d989add4faf4','postgres',true),
('analytics.internal_refresh_fact_branch_profit_daily(date[])','0a2d4982753daae12966a421188bd1bc','0a2d4982753daae12966a421188bd1bc','postgres',true),
('analytics.internal_refresh_fact_branch_profit_final_monthly(date[])','d24b67a506de001dbd0fedafc6b71ea9','d24b67a506de001dbd0fedafc6b71ea9','postgres',true),
('analytics.internal_refresh_fact_financial_ledgers_daily(date[])','1a4dbed297c43ad179821400a6db16d8','1a4dbed297c43ad179821400a6db16d8','postgres',true),
('analytics.internal_refresh_fact_geography_daily(date[])','ffc122da9467a7202c27663355eaa919','ffc122da9467a7202c27663355eaa919','postgres',true),
('analytics.internal_refresh_fact_gross_profit_daily_grain(date[])','15eabee552cdc9503f01a5ff362ab880','15eabee552cdc9503f01a5ff362ab880','postgres',true),
('analytics.internal_refresh_fact_profit_daily(date[])','df1bb9ccf727b0f86cadb71447231930','df1bb9ccf727b0f86cadb71447231930','postgres',true),
('analytics.internal_refresh_fact_sales_daily_grain(date[])','fec8afe2b94039a37b4b12edf7577448','fec8afe2b94039a37b4b12edf7577448','postgres',true),
('analytics.internal_refresh_fact_treasury_cashflow_daily(date[])','f33ea44c27b5715a742de017d14759b1','f33ea44c27b5715a742de017d14759b1','postgres',true),
('analytics.internal_refresh_profitability_data_quality_daily(date[])','90853249aae60f6922c463b66e0b4d02','90853249aae60f6922c463b66e0b4d02','postgres',true),
('analytics.internal_refresh_snapshot_branch_allocation_weights_monthly(date[])','e139a3d0ae3be822c6ccf2e51a4180c0','e139a3d0ae3be822c6ccf2e51a4180c0','postgres',true),
('analytics.internal_refresh_snapshot_customer_health(date[])','c0ae539bbe475d2ba99d7f3835017253','87513be1f5bc3fbdbf107a5f9bb5485e','postgres',true),
('analytics.internal_refresh_snapshot_customer_risk(date[])','169484c4ac9508dbd15c2ba5795c2e08','169484c4ac9508dbd15c2ba5795c2e08','postgres',true),
('analytics.internal_refresh_snapshot_target_attainment(date[])','7fda80609a729166b92ad066c5c87289','7fda80609a729166b92ad066c5c87289','postgres',true),
('analytics.orchestrate_incremental_refresh(uuid,text,date[])','0c132670fa426561c19e7d5b6f335611','0c132670fa426561c19e7d5b6f335611','postgres',true),
('analytics.run_analytics_watermark_sweep(integer)','535a686bbc079f524b99e88775abf486','9b2b3bd8a4b3fcaec6f5019a1754de22','postgres',true),
('analytics.txn_date(timestamp with time zone)','86ba55f1301d3aa7ad80e97a5e06e1a1','86ba55f1301d3aa7ad80e97a5e06e1a1','postgres',false),
('analytics_refresh_now()','1adaae9e10015863b370dd34c369096a','1adaae9e10015863b370dd34c369096a','postgres',true)
 ) f(signature,legacy_md5,final_md5,expected_owner,expected_definer) LOOP
  SELECT md5(replace(p.prosrc,E'\r\n',E'\n')) INTO actual FROM pg_proc p
  WHERE p.oid=to_regprocedure(x.signature) AND pg_get_userbyid(p.proowner)=x.expected_owner AND p.prosecdef=x.expected_definer;
  IF actual IS NULL THEN RAISE EXCEPTION 'Missing/changed routine contract: %',x.signature; END IF;
  legacy_ok:=legacy_ok AND actual=x.legacy_md5;
  final_ok:=final_ok AND actual=x.final_md5;
 END LOOP;
 IF NOT legacy_ok AND NOT final_ok THEN RAISE EXCEPTION 'Analytics routine drift or partial preparation version; review before applying'; END IF;
 IF legacy_ok AND (to_regclass('analytics.component_checkpoints') IS NOT NULL OR to_regclass('analytics.reporting_invalidation_events') IS NOT NULL
 OR to_regprocedure('analytics.capture_reporting_invalidation()') IS NOT NULL
 OR to_regprocedure('analytics.reporting_reference(jsonb,text[])') IS NOT NULL
 OR to_regprocedure('analytics.reporting_event_dates(text,text,jsonb,jsonb)') IS NOT NULL
 OR to_regprocedure('analytics.reporting_batch_dates(bigint[])') IS NOT NULL) THEN
  RAISE EXCEPTION 'Existing candidate objects need explicit compatibility review'; END IF;
 IF final_ok THEN FOR x IN SELECT * FROM (VALUES ('analytics.reporting_reference(jsonb,text[])','55e42d71f1bad98d6a503f2390b76c1e',false),('analytics.capture_reporting_invalidation()','4b0941633a49f2fda1111eb897d38d98',true),('analytics.reporting_event_dates(text,text,jsonb,jsonb)','ecf9bada319a90c9a84d7d61049aa895',true),('analytics.reporting_batch_dates(bigint[])','cee75c0a48d953ec75a70b4f73c1a437',true)) h(signature,body_md5,expected_definer) LOOP
 SELECT md5(replace(p.prosrc,E'\r\n',E'\n')) INTO actual FROM pg_proc p WHERE p.oid=to_regprocedure(x.signature) AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef=x.expected_definer;
 IF actual IS DISTINCT FROM x.body_md5 THEN RAISE EXCEPTION 'Reporting helper drift: %',x.signature; END IF;
 END LOOP; END IF;
 FOR x IN SELECT * FROM (VALUES
('public','sales_orders','id','uuid'),
('public','sales_orders','customer_id','uuid'),
('public','sales_orders','rep_id','uuid'),
('public','sales_orders','branch_id','uuid'),
('public','sales_orders','status','sales_order_status'),
('public','sales_orders','order_date','date'),
('public','sales_orders','delivered_at','timestamp with time zone'),
('public','sales_orders','total_amount','numeric(14,2)'),
('public','sales_orders','credit_amount','numeric(14,2)'),
('public','sales_orders','subtotal','numeric(14,2)'),
('public','sales_orders','tax_amount','numeric(14,2)'),
('public','sales_order_items','id','uuid'),
('public','sales_order_items','order_id','uuid'),
('public','sales_order_items','product_id','uuid'),
('public','sales_order_items','line_total','numeric(14,2)'),
('public','sales_order_items','tax_amount','numeric(14,2)'),
('public','sales_order_items','base_quantity','numeric(12,2)'),
('public','sales_order_items','unit_cost_at_sale','numeric(14,4)'),
('public','sales_returns','id','uuid'),
('public','sales_returns','order_id','uuid'),
('public','sales_returns','customer_id','uuid'),
('public','sales_returns','status','sales_return_status'),
('public','sales_returns','confirmed_at','timestamp with time zone'),
('public','sales_returns','updated_at','timestamp with time zone'),
('public','sales_return_items','id','uuid'),
('public','sales_return_items','return_id','uuid'),
('public','sales_return_items','order_item_id','uuid'),
('public','sales_return_items','line_total','numeric(14,2)'),
('public','sales_return_items','base_quantity','numeric(12,2)'),
('public','payment_receipts','id','uuid'),
('public','payment_receipts','sales_order_id','uuid'),
('public','payment_receipts','customer_id','uuid'),
('public','payment_receipts','created_at','timestamp with time zone'),
('public','payment_receipts','amount','numeric(14,2)'),
('public','payment_receipts','status','text'),
('public','payment_receipts','collected_by','uuid'),
('public','customer_ledger','id','uuid'),
('public','customer_ledger','customer_id','uuid'),
('public','customer_ledger','created_at','timestamp with time zone'),
('public','customer_ledger','allocated_to','uuid'),
('public','customer_ledger','source_id','uuid'),
('public','customer_ledger','source_type','text'),
('public','customer_ledger','type','text'),
('public','customer_ledger','amount','numeric(14,2)'),
('public','vault_transactions','id','uuid'),
('public','vault_transactions','created_at','timestamp with time zone'),
('public','vault_transactions','type','text'),
('public','vault_transactions','amount','numeric(14,2)'),
('public','vault_transactions','reference_type','text'),
('public','vault_transactions','reference_id','uuid'),
('public','custody_transactions','id','uuid'),
('public','custody_transactions','created_at','timestamp with time zone'),
('public','custody_transactions','type','text'),
('public','custody_transactions','amount','numeric(14,2)'),
('public','custody_transactions','reference_type','text'),
('public','custody_transactions','reference_id','uuid'),
('public','journal_entries','id','uuid'),
('public','journal_entries','entry_date','date'),
('public','journal_entries','status','text'),
('public','journal_entries','source_type','text'),
('public','journal_entries','source_id','uuid'),
('public','journal_entry_lines','id','uuid'),
('public','journal_entry_lines','entry_id','uuid'),
('public','journal_entry_lines','account_id','uuid'),
('public','journal_entry_lines','debit','numeric(14,2)'),
('public','journal_entry_lines','credit','numeric(14,2)'),
('public','customers','id','uuid'),
('public','customers','governorate_id','uuid'),
('public','customers','city_id','uuid'),
('public','customers','area_id','uuid'),
('public','expenses','id','uuid'),
('public','expenses','branch_id','uuid'),
('public','hr_payroll_runs','id','uuid'),
('public','hr_payroll_runs','branch_id','uuid'),
('public','chart_of_accounts','id','uuid'),
('public','chart_of_accounts','code','text'),
('public','hr_employees','id','uuid'),
('public','hr_employees','branch_id','uuid'),
('public','hr_employees','status','hr_employee_status'),
('public','hr_employees','hire_date','date'),
('public','hr_employees','termination_date','date'),
('analytics','profitability_allocation_rule_sets','id','uuid'),
('analytics','profitability_allocation_rule_sets','applies_to','text'),
('analytics','profitability_allocation_rule_sets','basis','text'),
('analytics','profitability_allocation_rule_sets','effective_from','date'),
('analytics','profitability_allocation_rule_sets','effective_to','date'),
('analytics','profitability_allocation_rule_sets','is_active','boolean'),
('analytics','profitability_allocation_rules','id','uuid'),
('analytics','profitability_allocation_rules','rule_set_id','uuid'),
('analytics','profitability_allocation_rules','branch_id','uuid'),
('analytics','profitability_allocation_rules','weight_value','numeric(7,6)')
 ) c(schema_name,table_name,column_name,type_name) LOOP
  rel:=to_regclass(format('%I.%I',x.schema_name,x.table_name));
  IF rel IS NULL OR NOT EXISTS(SELECT 1 FROM pg_class c WHERE c.oid=rel AND pg_get_userbyid(c.relowner)='postgres' AND c.relrowsecurity AND NOT c.relforcerowsecurity) THEN
   RAISE EXCEPTION 'Missing/changed source ownership or RLS: %.%',x.schema_name,x.table_name; END IF;
  SELECT format_type(a.atttypid,a.atttypmod) INTO actual FROM pg_attribute a WHERE a.attrelid=rel AND a.attname=x.column_name AND a.attnum>0 AND NOT a.attisdropped;
  IF actual IS DISTINCT FROM x.type_name THEN RAISE EXCEPTION 'Source type drift: %.%.%',x.schema_name,x.table_name,x.column_name; END IF;
 END LOOP;
END $release_preflight$;

-- Reviewed component: 20261001095213_analytics_component_checkpoints.sql
-- Processing progress is independent of reconciliation trust. No source/fact
-- formulas, detector definitions, cron schedules or public RPCs are replaced.
CREATE TABLE IF NOT EXISTS analytics.component_checkpoints (
    table_name TEXT PRIMARY KEY,
    scanned_through TIMESTAMPTZ NOT NULL,
    refresh_dates DATE[] NOT NULL DEFAULT '{}',
    reconciliation_dates DATE[] NOT NULL DEFAULT '{}',
    last_run_id UUID REFERENCES analytics.etl_runs(id)
);
ALTER TABLE analytics.component_checkpoints ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON analytics.component_checkpoints FROM PUBLIC, anon, authenticated;
GRANT ALL ON analytics.component_checkpoints TO service_role;

CREATE OR REPLACE PROCEDURE analytics.run_analytics_watermark_sweep(p_fallback_days INTEGER DEFAULT 3)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, analytics
AS $$
DECLARE
    v_sweep_id UUID := gen_random_uuid();
    v_run_id UUID;
    v_started TIMESTAMPTZ := clock_timestamp();
    v_cutoff TIMESTAMPTZ;
    v_initial TIMESTAMPTZ;
    v_scan TIMESTAMPTZ;
    v_cached_scan TIMESTAMPTZ;
    v_changed DATE[];
    v_refresh DATE[];
    v_review DATE[];
    v_failed_dates DATE[] := '{}';
    v_checkpoint analytics.component_checkpoints%ROWTYPE;
    v_previous RECORD;
    v_job TEXT;
    v_status TEXT;
    v_pending INTEGER;
    v_refreshed INTEGER := 0;
    v_reviewed INTEGER := 0;
BEGIN
    IF p_fallback_days IS NULL OR p_fallback_days < 1 THEN
        RAISE EXCEPTION 'p_fallback_days must be positive';
    END IF;
    -- A transaction lock also conflicts with the existing session lock used by
    -- backfill/admin refresh, and survives until the caller commits or rolls back.
    IF NOT pg_try_advisory_xact_lock(hashtext('analytics_global_sweep')) THEN
        RAISE NOTICE 'Analytics sweep locked elsewhere - exiting.';
        RETURN;
    END IF;
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'Analytics checkpoint scans require READ COMMITTED';
    END IF;
    IF NOT pg_has_role(current_user, 'pg_read_all_stats', 'USAGE') THEN
        RAISE EXCEPTION 'Sweep owner must see all transaction start times';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_prepared_xacts WHERE database = current_database()) THEN
        RAISE EXCEPTION 'Resolve prepared transactions before checkpoint scanning';
    END IF;
    -- Source timestamps use transaction time. An uncommitted older writer must
    -- remain inside the next scan even if it commits after this scan's snapshot.
    SELECT LEAST(v_started, COALESCE(MIN(xact_start), v_started)) - interval '1 microsecond'
    INTO v_cutoff FROM pg_stat_activity WHERE datname = current_database();
    SELECT COALESCE(MAX(started_at), v_started - make_interval(days => p_fallback_days))
    INTO v_initial FROM analytics.etl_runs
    WHERE table_name = 'GLOBAL_SWEEP'
      AND status IN ('SUCCESS', 'VERIFIED', 'POSTING_CONSISTENCY_ONLY', 'RECONCILED_WITH_WARNING');

    INSERT INTO analytics.etl_runs(id, table_name, status, started_at)
    VALUES (v_sweep_id, 'GLOBAL_SWEEP', 'RUNNING', v_started);

    -- Preserve the existing dependency order. On a real refresh failure, later
    -- components conservatively retain those dates rather than consume stale facts.
    FOREACH v_job IN ARRAY ARRAY[
        'fact_sales_daily_grain', 'fact_financial_ledgers_daily',
        'fact_treasury_cashflow_daily', 'fact_ar_collections_attributed_to_origin_sale_date',
        'snapshot_customer_health', 'snapshot_customer_risk', 'fact_geography_daily',
        'fact_profit_daily', 'fact_gross_profit_daily_grain', 'fact_branch_profit_daily',
        'profitability_data_quality_daily', 'snapshot_branch_allocation_weights_monthly',
        'fact_branch_profit_final_monthly'
    ] LOOP
        IF NOT EXISTS (SELECT 1 FROM analytics.component_checkpoints WHERE table_name = v_job) THEN
            SELECT status, log_output INTO v_previous FROM analytics.etl_runs
            WHERE table_name = v_job ORDER BY started_at DESC LIMIT 1;
            IF v_previous.status IN ('BLOCKED', 'FAILED') THEN
                IF v_previous.log_output->>'min_affected_date' IS NULL
                    OR v_previous.log_output->>'max_affected_date' IS NULL THEN
                    RAISE EXCEPTION 'Seed exact pending dates for % before initializing its checkpoint', v_job;
                END IF;
                -- Legacy logs have bounds rather than an exact date array. A
                -- conservative contiguous range preserves every unresolved bucket.
                INSERT INTO analytics.component_checkpoints(table_name, scanned_through, refresh_dates)
                SELECT v_job, v_initial, array_agg(d::DATE ORDER BY d)
                FROM generate_series((v_previous.log_output->>'min_affected_date')::DATE,
                    (v_previous.log_output->>'max_affected_date')::DATE, interval '1 day') d;
            END IF;
        END IF;
        INSERT INTO analytics.component_checkpoints(table_name, scanned_through)
        VALUES (v_job, v_initial) ON CONFLICT DO NOTHING;
        SELECT * INTO STRICT v_checkpoint FROM analytics.component_checkpoints
        WHERE table_name = v_job FOR UPDATE;
        v_scan := v_checkpoint.scanned_through;
        IF v_cached_scan IS DISTINCT FROM v_scan THEN
            v_changed := analytics.detect_affected_dates(v_scan);
            v_cached_scan := v_scan;
        END IF;
        SELECT COALESCE(array_agg(DISTINCT d ORDER BY d), '{}'::DATE[]) INTO v_refresh
        FROM unnest(COALESCE(v_changed, '{}') || v_checkpoint.refresh_dates || v_failed_dates) d
        WHERE d IS NOT NULL;
        SELECT COALESCE(array_agg(DISTINCT d ORDER BY d), '{}'::DATE[]) INTO v_review
        FROM unnest(v_refresh || v_checkpoint.reconciliation_dates) d WHERE d IS NOT NULL;
        IF v_job IN ('snapshot_branch_allocation_weights_monthly', 'fact_branch_profit_final_monthly') THEN
            SELECT COALESCE(array_agg(DISTINCT date_trunc('month', d)::DATE ORDER BY date_trunc('month', d)::DATE), '{}')
            INTO v_refresh FROM unnest(v_refresh) d;
            SELECT COALESCE(array_agg(DISTINCT date_trunc('month', d)::DATE ORDER BY date_trunc('month', d)::DATE), '{}')
            INTO v_review FROM unnest(v_review) d;
        END IF;
        v_run_id := NULL;
        v_status := NULL;
        IF cardinality(v_review) > 0 THEN
            v_run_id := gen_random_uuid();
            IF cardinality(v_failed_dates) > 0 THEN
                v_status := 'FAILED';
                INSERT INTO analytics.etl_runs(id, table_name, status, started_at, completed_at, log_output)
                VALUES (v_run_id, v_job, v_status, clock_timestamp(), clock_timestamp(),
                    jsonb_build_object('error', 'Upstream refresh incomplete', 'pending_dates', v_review));
            ELSE
                IF cardinality(v_refresh) > 0 THEN
                    CALL analytics.orchestrate_incremental_refresh(v_run_id, v_job, v_refresh);
                    SELECT status INTO STRICT v_status FROM analytics.etl_runs WHERE id = v_run_id;
                ELSE
                    -- Reuse the real trust calculation; never rebuild facts merely
                    -- because an unchanged reconciliation remains blocked.
                    INSERT INTO analytics.etl_runs(id, table_name, status, started_at, completed_at, log_output)
                    VALUES (v_run_id, v_job, 'SUCCESS', clock_timestamp(), clock_timestamp(),
                        jsonb_build_object('reconciliation_only', true));
                    v_status := 'SUCCESS';
                END IF;
                IF v_status IN ('SUCCESS', 'VERIFIED', 'POSTING_CONSISTENCY_ONLY', 'RECONCILED_WITH_WARNING', 'BLOCKED') THEN
                    v_refreshed := v_refreshed + cardinality(v_refresh);
                    -- The orchestrator already reviewed a newly rebuilt batch.
                    -- Review again only to include older unresolved comparisons.
                    IF cardinality(v_refresh) = 0 OR cardinality(v_checkpoint.reconciliation_dates) > 0 THEN
                        BEGIN
                            CALL analytics.compute_double_review_trust_state(v_run_id, v_job, v_review);
                            v_reviewed := v_reviewed + cardinality(v_review);
                        EXCEPTION WHEN OTHERS THEN
                            -- Metric-level monitoring takes precedence over row status.
                            -- Drop the fresh batch's success metrics when the wider
                            -- pending-date review fails; expose FAILED at component level.
                            UPDATE analytics.etl_runs SET status = 'FAILED', metric_states = NULL, drift_value = NULL, log_output =
                                COALESCE(log_output, '{}') || jsonb_build_object('error', SQLERRM, 'state', SQLSTATE)
                            WHERE id = v_run_id;
                        END;
                    ELSE
                        v_reviewed := v_reviewed + cardinality(v_refresh);
                    END IF;
                    -- A trust-calculation failure must retry review, not replay an
                    -- already committed rebuild; an orchestrator failure retries both.
                    v_refresh := '{}';
                END IF;
                SELECT status INTO STRICT v_status FROM analytics.etl_runs WHERE id = v_run_id;
            END IF;
            IF v_status IN ('SUCCESS', 'VERIFIED', 'POSTING_CONSISTENCY_ONLY', 'RECONCILED_WITH_WARNING') THEN
                v_review := '{}';
            END IF;
            IF cardinality(v_refresh) > 0 THEN
                SELECT COALESCE(array_agg(DISTINCT d ORDER BY d), '{}') INTO v_failed_dates
                FROM unnest(v_failed_dates || v_refresh) d;
            END IF;
            UPDATE analytics.etl_runs SET completed_at = clock_timestamp(), log_output =
                COALESCE(log_output, '{}') || jsonb_build_object('refresh_pending_dates', v_refresh,
                    'reconciliation_pending_dates', v_review)
            WHERE id = v_run_id;
        END IF;
        UPDATE analytics.component_checkpoints SET
            scanned_through = GREATEST(scanned_through, v_cutoff),
            refresh_dates = v_refresh, reconciliation_dates = v_review,
            last_run_id = COALESCE(v_run_id, last_run_id)
        WHERE table_name = v_job;
    END LOOP;

    -- Target attainment has its separate existing daily behavior and cron.
    v_run_id := gen_random_uuid();
    CALL analytics.orchestrate_incremental_refresh(v_run_id, 'snapshot_target_attainment', ARRAY[CURRENT_DATE]);
    SELECT COUNT(*) INTO v_pending FROM analytics.component_checkpoints
    WHERE cardinality(refresh_dates) > 0 OR cardinality(reconciliation_dates) > 0;
    IF EXISTS (SELECT 1 FROM analytics.etl_runs WHERE id = v_run_id
        AND status NOT IN ('SUCCESS', 'VERIFIED', 'POSTING_CONSISTENCY_ONLY', 'RECONCILED_WITH_WARNING')) THEN
        v_pending := v_pending + 1;
    END IF;
    UPDATE analytics.etl_runs SET status = CASE WHEN v_pending > 0 THEN 'PARTIAL_FAILURE' ELSE 'SUCCESS' END,
        completed_at = clock_timestamp(), log_output = jsonb_build_object(
            'pending_components', v_pending, 'refreshed_buckets', v_refreshed,
            'reviewed_buckets', v_reviewed, 'scan_cutoff', v_cutoff)
    WHERE id = v_sweep_id;
END;
$$;
REVOKE ALL ON PROCEDURE analytics.run_analytics_watermark_sweep(INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON PROCEDURE analytics.run_analytics_watermark_sweep(INTEGER) TO service_role;

-- Reviewed component: 20261001100454_analytics_reporting_invalidations.sql

DO $preflight$
DECLARE s RECORD; col TEXT; rel REGCLASS;
BEGIN
 IF to_regclass('analytics.component_checkpoints') IS NULL THEN RAISE EXCEPTION 'Apply component checkpoints before reporting invalidations'; END IF;
 IF to_regprocedure('analytics.effective_sale_date(timestamp with time zone,date)') IS NULL
 OR to_regprocedure('analytics.txn_date(timestamp with time zone)') IS NULL THEN
  RAISE EXCEPTION 'Exact installed date helpers are required; do not substitute source definitions';
 END IF;
 FOR s IN SELECT * FROM (VALUES ('public','sales_orders',ARRAY['id','customer_id','rep_id','branch_id','status','order_date','delivered_at','total_amount','credit_amount','subtotal','tax_amount'],ARRAY['id','customer_id','order_date','delivered_at']),
('public','sales_order_items',ARRAY['id','order_id','product_id','line_total','tax_amount','base_quantity','unit_cost_at_sale'],ARRAY['id','order_id']),
('public','sales_returns',ARRAY['id','order_id','customer_id','status','confirmed_at','updated_at'],ARRAY['id','order_id','confirmed_at','updated_at']),
('public','sales_return_items',ARRAY['id','return_id','order_item_id','line_total','base_quantity'],ARRAY['id','return_id','order_item_id']),
('public','payment_receipts',ARRAY['id','sales_order_id','customer_id','created_at','amount','status','collected_by'],ARRAY['id','sales_order_id','customer_id','created_at']),
('public','customer_ledger',ARRAY['id','customer_id','created_at','allocated_to','source_id','source_type','type','amount'],ARRAY['id','customer_id','created_at','allocated_to','source_id','source_type','type']),
('public','vault_transactions',ARRAY['id','created_at','type','amount','reference_type','reference_id'],ARRAY['id','created_at','reference_type','reference_id']),
('public','custody_transactions',ARRAY['id','created_at','type','amount','reference_type','reference_id'],ARRAY['id','created_at','reference_type','reference_id']),
('public','journal_entries',ARRAY['id','entry_date','status','source_type','source_id'],ARRAY['id','entry_date','source_type','source_id']),
('public','journal_entry_lines',ARRAY['id','entry_id','account_id','debit','credit'],ARRAY['id','entry_id','account_id']),
('public','customers',ARRAY['id','governorate_id','city_id','area_id'],ARRAY['id']),
('public','expenses',ARRAY['id','branch_id'],ARRAY['id']),
('public','hr_payroll_runs',ARRAY['id','branch_id'],ARRAY['id']),
('public','chart_of_accounts',ARRAY['id','code'],ARRAY['id']),
('public','hr_employees',ARRAY['id','branch_id','status','hire_date','termination_date'],ARRAY['id','branch_id','hire_date','termination_date']),
('analytics','profitability_allocation_rule_sets',ARRAY['id','applies_to','basis','effective_from','effective_to','is_active'],ARRAY['id','effective_from','effective_to']),
('analytics','profitability_allocation_rules',ARRAY['id','rule_set_id','branch_id','weight_value'],ARRAY['id','rule_set_id'])) src(schema_name,table_name,watched,refs) LOOP
  rel:=to_regclass(format('%I.%I',s.schema_name,s.table_name));
  IF rel IS NULL THEN RAISE EXCEPTION 'Missing reporting source %.%',s.schema_name,s.table_name; END IF;
  FOREACH col IN ARRAY s.watched||s.refs LOOP
   IF NOT EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=rel AND a.attname=col AND a.attnum>0 AND NOT a.attisdropped) THEN
    RAISE EXCEPTION 'Missing reporting source column %.%.%',s.schema_name,s.table_name,col;
   END IF;
  END LOOP;
 END LOOP;
END
$preflight$;


-- Reporting-only invalidations for the thirteen date-driven analytics components.
-- Requires the timestamped component-checkpoint migration. No source formulas,
-- financial values, source permissions, cron cadence or public report RPCs change.
-- Source hooks record only bounded identity/date metadata; expansion happens here.
CREATE TABLE IF NOT EXISTS analytics.reporting_invalidation_events (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_schema TEXT NOT NULL,
    source_table TEXT NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT','UPDATE','DELETE')),
    old_ref JSONB NOT NULL DEFAULT '{}',
    new_ref JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CHECK (jsonb_typeof(old_ref)='object' AND jsonb_typeof(new_ref)='object')
);
ALTER TABLE analytics.reporting_invalidation_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON analytics.reporting_invalidation_events FROM PUBLIC, anon, authenticated;
GRANT SELECT ON analytics.reporting_invalidation_events TO service_role;
REVOKE ALL ON SEQUENCE analytics.reporting_invalidation_events_id_seq FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION analytics.reporting_reference(p_row JSONB,p_keys TEXT[])
RETURNS JSONB LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path=pg_catalog AS $$
    SELECT COALESCE(jsonb_object_agg(e.key,e.value),'{}'::jsonb)
    FROM jsonb_each(COALESCE(p_row,'{}'::jsonb)) e WHERE e.key=ANY(p_keys)
$$;
REVOKE ALL ON FUNCTION analytics.reporting_reference(JSONB,TEXT[]) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION analytics.capture_reporting_invalidation()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,analytics AS $$
DECLARE
    v_old JSONB := '{}';
    v_new JSONB := '{}';
    v_old_ref JSONB;
    v_new_ref JSONB;
    v_period JSONB;
BEGIN
    IF TG_OP <> 'INSERT' THEN v_old := to_jsonb(OLD); END IF;
    IF TG_OP <> 'DELETE' THEN v_new := to_jsonb(NEW); END IF;
    IF TG_OP='UPDATE' AND
       analytics.reporting_reference(v_old,string_to_array(TG_ARGV[0],',')) IS NOT DISTINCT FROM
       analytics.reporting_reference(v_new,string_to_array(TG_ARGV[0],',')) THEN
        RETURN NULL;
    END IF;
    v_old_ref := analytics.reporting_reference(v_old,string_to_array(TG_ARGV[1],','));
    v_new_ref := analytics.reporting_reference(v_new,string_to_array(TG_ARGV[1],','));
    -- Rule-item events keep the parent's effective range with a single PK lookup.
    -- A cascading parent deletion also records its own complete old period.
    IF TG_TABLE_SCHEMA='analytics' AND TG_TABLE_NAME='profitability_allocation_rules' THEN
        SELECT jsonb_build_object('effective_from',s.effective_from,'effective_to',s.effective_to)
        INTO v_period FROM analytics.profitability_allocation_rule_sets s
        WHERE s.id=(v_old_ref->>'rule_set_id')::uuid;
        v_old_ref := v_old_ref || COALESCE(v_period,'{}');
        SELECT jsonb_build_object('effective_from',s.effective_from,'effective_to',s.effective_to)
        INTO v_period FROM analytics.profitability_allocation_rule_sets s
        WHERE s.id=(v_new_ref->>'rule_set_id')::uuid;
        v_new_ref := v_new_ref || COALESCE(v_period,'{}');
    END IF;
    INSERT INTO analytics.reporting_invalidation_events(source_schema,source_table,operation,old_ref,new_ref)
    VALUES(TG_TABLE_SCHEMA,TG_TABLE_NAME,TG_OP,v_old_ref,v_new_ref);
    RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION analytics.capture_reporting_invalidation() FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION analytics.reporting_event_dates(
    p_source_schema TEXT,p_source_table TEXT,p_old JSONB,p_new JSONB
)
RETURNS TABLE(component TEXT,bucket DATE)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,analytics,public AS $$
DECLARE
    r JSONB;
    j RECORD;
    v_dates DATE[] := '{}';
    v_orders UUID[] := '{}';
    v_returns UUID[] := '{}';
    v_receipts UUID[] := '{}';
    v_journals UUID[] := '{}';
    v_customers UUID[] := '{}';
    v_ids UUID[] := '{}';
    v_min DATE;
    v_all_components TEXT[] := ARRAY[
        'fact_sales_daily_grain','fact_financial_ledgers_daily','fact_treasury_cashflow_daily',
        'fact_ar_collections_attributed_to_origin_sale_date','snapshot_customer_health',
        'snapshot_customer_risk','fact_geography_daily','fact_profit_daily',
        'fact_gross_profit_daily_grain','fact_branch_profit_daily',
        'profitability_data_quality_daily','snapshot_branch_allocation_weights_monthly',
        'fact_branch_profit_final_monthly'];
BEGIN
    IF p_source_schema NOT IN ('public','analytics') THEN
        RAISE EXCEPTION 'Unknown reporting invalidation source %.%',p_source_schema,p_source_table;
    END IF;
    IF p_source_schema='public' AND p_source_table='customers' THEN
        -- Only geography keys are watched. Existing grain retains old customer IDs
        -- even when the dimension row is deleted; no recent-date cutoff is used.
        RETURN QUERY
        SELECT 'fact_geography_daily'::text,f.date
        FROM analytics.fact_sales_daily_grain f
        WHERE f.customer_id IN ((p_old->>'id')::uuid,(p_new->>'id')::uuid)
        GROUP BY f.date;
        RETURN;
    END IF;
    IF (p_source_schema='analytics' AND p_source_table IN
        ('profitability_allocation_rule_sets','profitability_allocation_rules'))
        OR (p_source_schema='public' AND p_source_table='hr_employees') THEN
        -- Enumerate actual existing monthly footprints, not an arbitrary lookback
        -- or unbounded future series. Future business facts trigger their own month.
        RETURN QUERY
        WITH months AS (
            SELECT s.month_start AS m FROM analytics.snapshot_branch_allocation_weights_monthly s
            UNION SELECT f.month_start FROM analytics.fact_branch_profit_final_monthly f
            UNION SELECT date_trunc('month',f.profit_date)::date FROM analytics.fact_branch_profit_daily f
        ), refs AS (
            SELECT x.ref FROM (VALUES(p_old),(p_new)) x(ref)
        ), affected AS (
            SELECT DISTINCT m.m
            FROM months m CROSS JOIN refs r
            WHERE CASE WHEN p_source_table='hr_employees' THEN
                (r.ref->>'hire_date')::date <= (m.m+interval '1 month'-interval '1 day')::date
                AND ((r.ref->>'termination_date') IS NULL OR (r.ref->>'termination_date')::date>m.m)
            ELSE
                (r.ref->>'effective_from')::date <= (m.m+interval '1 month'-interval '1 day')::date
                AND ((r.ref->>'effective_to') IS NULL OR (r.ref->>'effective_to')::date>=m.m)
            END
        )
        SELECT n.name,a.m FROM affected a CROSS JOIN unnest(ARRAY[
            'snapshot_branch_allocation_weights_monthly','fact_branch_profit_final_monthly']) n(name);
        RETURN;
    END IF;

    IF p_source_schema<>'public' OR p_source_table NOT IN (
        'sales_orders','sales_order_items','sales_returns','sales_return_items',
        'payment_receipts','customer_ledger','vault_transactions','custody_transactions',
        'journal_entries','journal_entry_lines','expenses','hr_payroll_runs','chart_of_accounts') THEN
        RAISE EXCEPTION 'Unknown reporting invalidation source %.%',p_source_schema,p_source_table;
    END IF;

    FOR r IN SELECT x.ref FROM (VALUES(p_old),(p_new)) x(ref) LOOP
        IF r='{}'::jsonb THEN CONTINUE; END IF;
        CASE p_source_table
        WHEN 'sales_orders' THEN
            v_orders:=v_orders || (r->>'id')::uuid;
            v_customers:=v_customers || (r->>'customer_id')::uuid;
            v_dates:=v_dates || analytics.effective_sale_date((r->>'delivered_at')::timestamptz,(r->>'order_date')::date);
        WHEN 'sales_order_items' THEN
            v_orders:=v_orders || (r->>'order_id')::uuid;
        WHEN 'sales_returns' THEN
            v_returns:=v_returns || (r->>'id')::uuid;
            v_orders:=v_orders || (r->>'order_id')::uuid;
            v_dates:=v_dates || analytics.txn_date((r->>'confirmed_at')::timestamptz)
                || analytics.txn_date((r->>'updated_at')::timestamptz);
        WHEN 'sales_return_items' THEN
            v_returns:=v_returns || (r->>'return_id')::uuid;
            SELECT i.order_id INTO j FROM public.sales_order_items i WHERE i.id=(r->>'order_item_id')::uuid;
            v_orders:=v_orders || j.order_id;
        WHEN 'payment_receipts' THEN
            v_receipts:=v_receipts || (r->>'id')::uuid;
            v_orders:=v_orders || (r->>'sales_order_id')::uuid;
            v_dates:=v_dates || analytics.txn_date((r->>'created_at')::timestamptz);
        WHEN 'customer_ledger' THEN
            v_dates:=v_dates || analytics.txn_date((r->>'created_at')::timestamptz);
            IF r->>'source_type'='sales_order' THEN v_orders:=v_orders || (r->>'source_id')::uuid; END IF;
            IF r->>'source_type'='payment_receipt' THEN v_receipts:=v_receipts || (r->>'source_id')::uuid; END IF;
            SELECT l.source_id INTO j FROM public.customer_ledger l
            WHERE l.id=(r->>'allocated_to')::uuid AND l.source_type='sales_order';
            v_orders:=v_orders || j.source_id;
        WHEN 'vault_transactions','custody_transactions' THEN
            v_dates:=v_dates || analytics.txn_date((r->>'created_at')::timestamptz);
            IF r->>'reference_type'='sales_order' THEN v_orders:=v_orders || (r->>'reference_id')::uuid;
            ELSIF r->>'reference_type'='sales_return' THEN v_returns:=v_returns || (r->>'reference_id')::uuid;
            ELSIF r->>'reference_type'='payment_receipt' THEN v_receipts:=v_receipts || (r->>'reference_id')::uuid;
            END IF;
        WHEN 'journal_entries' THEN
            v_journals:=v_journals || (r->>'id')::uuid;
            v_dates:=v_dates || (r->>'entry_date')::date;
            IF r->>'source_type'='sales_order' THEN v_orders:=v_orders || (r->>'source_id')::uuid;
            ELSIF r->>'source_type'='sales_return' THEN v_returns:=v_returns || (r->>'source_id')::uuid;
            END IF;
        WHEN 'journal_entry_lines' THEN
            v_journals:=v_journals || (r->>'entry_id')::uuid;
        WHEN 'expenses','hr_payroll_runs' THEN
            SELECT COALESCE(array_agg(e.id),'{}'::uuid[]) INTO v_ids FROM public.journal_entries e
            WHERE e.source_id=(r->>'id')::uuid
              AND ((p_source_table='expenses' AND e.source_type='expense')
                OR (p_source_table='hr_payroll_runs' AND e.source_type IN ('hr_payroll','manual')));
            v_journals:=v_journals || v_ids;
        WHEN 'chart_of_accounts' THEN
            SELECT COALESCE(array_agg(DISTINCT l.entry_id),'{}'::uuid[]) INTO v_ids
            FROM public.journal_entry_lines l WHERE l.account_id=(r->>'id')::uuid;
            v_journals:=v_journals || v_ids;
            SELECT v_dates || COALESCE(array_agg(DISTINCT f.date),'{}'::date[]) INTO v_dates
            FROM analytics.fact_financial_ledgers_daily f WHERE f.account_id=(r->>'id')::uuid;
        END CASE;
    END LOOP;

    FOR j IN SELECT e.entry_date,e.source_type,e.source_id FROM public.journal_entries e WHERE e.id=ANY(v_journals) LOOP
        v_dates:=v_dates || j.entry_date;
        IF j.source_type='sales_order' THEN v_orders:=v_orders || j.source_id;
        ELSIF j.source_type='sales_return' THEN v_returns:=v_returns || j.source_id; END IF;
    END LOOP;
    FOR j IN SELECT p.sales_order_id,p.created_at FROM public.payment_receipts p WHERE p.id=ANY(v_receipts) LOOP
        v_orders:=v_orders || j.sales_order_id;
        v_dates:=v_dates || analytics.txn_date(j.created_at);
    END LOOP;
    -- Receipts without a direct order can allocate to many older invoices.
    SELECT v_orders || COALESCE(array_agg(DISTINCT inv.source_id),'{}'::uuid[]) INTO v_orders
    FROM public.customer_ledger c JOIN public.customer_ledger inv ON inv.id=c.allocated_to
    WHERE c.source_type='payment_receipt' AND c.source_id=ANY(v_receipts) AND inv.source_type='sales_order';
    FOR j IN SELECT s.order_id,s.confirmed_at,s.updated_at FROM public.sales_returns s WHERE s.id=ANY(v_returns) LOOP
        v_orders:=v_orders || j.order_id;
        v_dates:=v_dates || analytics.txn_date(j.confirmed_at) || analytics.txn_date(j.updated_at);
    END LOOP;
    FOR j IN SELECT s.id,s.customer_id,s.delivered_at,s.order_date FROM public.sales_orders s WHERE s.id=ANY(v_orders) LOOP
        v_dates:=v_dates || analytics.effective_sale_date(j.delivered_at,j.order_date);
        v_customers:=v_customers || j.customer_id;
    END LOOP;
    -- Source metadata changes also alter existing treasury/refund attribution on
    -- transaction dates that may differ from both sale and receipt creation dates.
    SELECT v_returns || COALESCE(array_agg(DISTINCT s.id),'{}'::uuid[]) INTO v_returns
    FROM public.sales_returns s WHERE s.order_id=ANY(v_orders);
    SELECT v_receipts || COALESCE(array_agg(DISTINCT p.id),'{}'::uuid[]) INTO v_receipts
    FROM public.payment_receipts p WHERE p.sales_order_id=ANY(v_orders);
    SELECT v_dates || COALESCE(array_agg(DISTINCT analytics.txn_date(t.created_at)),'{}'::date[]) INTO v_dates
    FROM (SELECT created_at,reference_type,reference_id FROM public.vault_transactions
          UNION ALL SELECT created_at,reference_type,reference_id FROM public.custody_transactions) t
    WHERE (t.reference_type='sales_order' AND t.reference_id=ANY(v_orders))
       OR (t.reference_type='sales_return' AND t.reference_id=ANY(v_returns))
       OR (t.reference_type='payment_receipt' AND t.reference_id=ANY(v_receipts));
    -- Gross-profit returns use confirmation dates, whereas sales facts use origin dates.
    SELECT v_dates || COALESCE(array_agg(DISTINCT analytics.txn_date(s.confirmed_at)),'{}'::date[]) INTO v_dates
    FROM public.sales_returns s WHERE s.order_id=ANY(v_orders);
    SELECT COALESCE(array_agg(DISTINCT d.val ORDER BY d.val),'{}'::date[]) INTO v_dates
    FROM unnest(v_dates) d(val) WHERE d.val IS NOT NULL;
    RETURN QUERY SELECT c.name,d.val FROM unnest(v_all_components) c(name) CROSS JOIN unnest(v_dates) d(val);

    IF p_source_table IN ('sales_orders','sales_order_items') AND cardinality(v_dates)>0 THEN
        SELECT min(d.val) INTO v_min FROM unnest(v_dates) d(val);
        -- A historical sale change can alter recency/90-day statistics on later
        -- already-materialized snapshots, not just the sale's own day.
        RETURN QUERY
        WITH affected AS (
            SELECT h.as_of_date AS d FROM analytics.snapshot_customer_health h
            WHERE h.customer_id=ANY(v_customers) AND h.as_of_date>=v_min
            UNION SELECT r.as_of_date FROM analytics.snapshot_customer_risk r
            WHERE r.customer_id=ANY(v_customers) AND r.as_of_date>=v_min
        )
        SELECT c.name,a.d FROM affected a CROSS JOIN unnest(ARRAY[
            'snapshot_customer_health','snapshot_customer_risk']) c(name);
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION analytics.reporting_event_dates(TEXT,TEXT,JSONB,JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION analytics.reporting_batch_dates(p_ids BIGINT[])
RETURNS JSONB LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,analytics AS $$
    SELECT COALESCE(jsonb_object_agg(q.component,q.dates),'{}'::jsonb)
    FROM (
        SELECT d.component,jsonb_agg(DISTINCT d.bucket ORDER BY d.bucket) AS dates
        FROM analytics.reporting_invalidation_events e
        CROSS JOIN LATERAL analytics.reporting_event_dates(e.source_schema,e.source_table,e.old_ref,e.new_ref) d
        WHERE e.id=ANY(p_ids) AND d.bucket IS NOT NULL
        GROUP BY d.component
    ) q
$$;
REVOKE ALL ON FUNCTION analytics.reporting_batch_dates(BIGINT[]) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE PROCEDURE analytics.run_analytics_watermark_sweep(p_fallback_days INTEGER DEFAULT 3)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, analytics
AS $$
DECLARE
    v_sweep_id UUID := gen_random_uuid();
    v_run_id UUID;
    v_started TIMESTAMPTZ := clock_timestamp();
    v_cutoff TIMESTAMPTZ;
    v_initial TIMESTAMPTZ;
    v_scan TIMESTAMPTZ;
    v_cached_scan TIMESTAMPTZ;
    v_changed DATE[];
    v_refresh DATE[];
    v_review DATE[];
    v_failed_dates DATE[] := '{}';
    v_checkpoint analytics.component_checkpoints%ROWTYPE;
    v_previous RECORD;
    v_job TEXT;
    v_status TEXT;
    v_pending INTEGER;
    v_refreshed INTEGER := 0;
    v_reviewed INTEGER := 0;
    v_event_ids BIGINT[] := '{}';
    v_event_dates JSONB := '{}';
    v_events_remaining BOOLEAN := false;
BEGIN
    IF p_fallback_days IS NULL OR p_fallback_days < 1 THEN
        RAISE EXCEPTION 'p_fallback_days must be positive';
    END IF;
    -- A transaction lock also conflicts with the existing session lock used by
    -- backfill/admin refresh, and survives until the caller commits or rolls back.
    IF NOT pg_try_advisory_xact_lock(hashtext('analytics_global_sweep')) THEN
        RAISE NOTICE 'Analytics sweep locked elsewhere - exiting.';
        RETURN;
    END IF;
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'Analytics checkpoint scans require READ COMMITTED';
    END IF;
    IF NOT pg_has_role(current_user, 'pg_read_all_stats', 'USAGE') THEN
        RAISE EXCEPTION 'Sweep owner must see all transaction start times';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_prepared_xacts WHERE database = current_database()) THEN
        RAISE EXCEPTION 'Resolve prepared transactions before checkpoint scanning';
    END IF;
    -- Source timestamps use transaction time. An uncommitted older writer must
    -- remain inside the next scan even if it commits after this scan's snapshot.
    SELECT LEAST(v_started, COALESCE(MIN(xact_start), v_started)) - interval '1 microsecond'
    INTO v_cutoff FROM pg_stat_activity WHERE datname = current_database();
    SELECT COALESCE(MAX(started_at), v_started - make_interval(days => p_fallback_days))
    INTO v_initial FROM analytics.etl_runs
    WHERE table_name = 'GLOBAL_SWEEP'
      AND status IN ('SUCCESS', 'VERIFIED', 'POSTING_CONSISTENCY_ONLY', 'RECONCILED_WITH_WARNING');

    INSERT INTO analytics.etl_runs(id, table_name, status, started_at)
    VALUES (v_sweep_id, 'GLOBAL_SWEEP', 'RUNNING', v_started);

    -- Snapshot explicit visible IDs; do not use a max-ID cursor, since a lower
    -- sequence value may commit after a higher one. Process at most 1000 events.
    SELECT COALESCE(array_agg(e.id ORDER BY e.id),'{}'::bigint[]) INTO v_event_ids
    FROM (SELECT id FROM analytics.reporting_invalidation_events ORDER BY id LIMIT 1000) e;
    v_event_dates := analytics.reporting_batch_dates(v_event_ids);

    -- Preserve the existing dependency order. On a real refresh failure, later
    -- components conservatively retain those dates rather than consume stale facts.
    FOREACH v_job IN ARRAY ARRAY[
        'fact_sales_daily_grain', 'fact_financial_ledgers_daily',
        'fact_treasury_cashflow_daily', 'fact_ar_collections_attributed_to_origin_sale_date',
        'snapshot_customer_health', 'snapshot_customer_risk', 'fact_geography_daily',
        'fact_profit_daily', 'fact_gross_profit_daily_grain', 'fact_branch_profit_daily',
        'profitability_data_quality_daily', 'snapshot_branch_allocation_weights_monthly',
        'fact_branch_profit_final_monthly'
    ] LOOP
        IF NOT EXISTS (SELECT 1 FROM analytics.component_checkpoints WHERE table_name = v_job) THEN
            SELECT status, log_output INTO v_previous FROM analytics.etl_runs
            WHERE table_name = v_job ORDER BY started_at DESC LIMIT 1;
            IF v_previous.status IN ('BLOCKED', 'FAILED') THEN
                IF v_previous.log_output->>'min_affected_date' IS NULL
                    OR v_previous.log_output->>'max_affected_date' IS NULL THEN
                    RAISE EXCEPTION 'Seed exact pending dates for % before initializing its checkpoint', v_job;
                END IF;
                -- Legacy logs have bounds rather than an exact date array. A
                -- conservative contiguous range preserves every unresolved bucket.
                INSERT INTO analytics.component_checkpoints(table_name, scanned_through, refresh_dates)
                SELECT v_job, v_initial, array_agg(d::DATE ORDER BY d)
                FROM generate_series((v_previous.log_output->>'min_affected_date')::DATE,
                    (v_previous.log_output->>'max_affected_date')::DATE, interval '1 day') d;
            END IF;
        END IF;
        INSERT INTO analytics.component_checkpoints(table_name, scanned_through)
        VALUES (v_job, v_initial) ON CONFLICT DO NOTHING;
        SELECT * INTO STRICT v_checkpoint FROM analytics.component_checkpoints
        WHERE table_name = v_job FOR UPDATE;
        v_scan := v_checkpoint.scanned_through;
        IF v_cached_scan IS DISTINCT FROM v_scan THEN
            v_changed := analytics.detect_affected_dates(v_scan);
            v_cached_scan := v_scan;
        END IF;
        SELECT COALESCE(array_agg(DISTINCT d ORDER BY d), '{}'::DATE[]) INTO v_refresh
        FROM unnest(COALESCE(v_changed, '{}') || v_checkpoint.refresh_dates || v_failed_dates
            || ARRAY(SELECT x.d::date FROM jsonb_array_elements_text(v_event_dates->v_job) x(d))) d
        WHERE d IS NOT NULL;
        SELECT COALESCE(array_agg(DISTINCT d ORDER BY d), '{}'::DATE[]) INTO v_review
        FROM unnest(v_refresh || v_checkpoint.reconciliation_dates) d WHERE d IS NOT NULL;
        IF v_job IN ('snapshot_branch_allocation_weights_monthly', 'fact_branch_profit_final_monthly') THEN
            SELECT COALESCE(array_agg(DISTINCT date_trunc('month', d)::DATE ORDER BY date_trunc('month', d)::DATE), '{}')
            INTO v_refresh FROM unnest(v_refresh) d;
            SELECT COALESCE(array_agg(DISTINCT date_trunc('month', d)::DATE ORDER BY date_trunc('month', d)::DATE), '{}')
            INTO v_review FROM unnest(v_review) d;
        END IF;
        v_run_id := NULL;
        v_status := NULL;
        IF cardinality(v_review) > 0 THEN
            v_run_id := gen_random_uuid();
            IF cardinality(v_failed_dates) > 0 THEN
                v_status := 'FAILED';
                INSERT INTO analytics.etl_runs(id, table_name, status, started_at, completed_at, log_output)
                VALUES (v_run_id, v_job, v_status, clock_timestamp(), clock_timestamp(),
                    jsonb_build_object('error', 'Upstream refresh incomplete', 'pending_dates', v_review));
            ELSE
                IF cardinality(v_refresh) > 0 THEN
                    CALL analytics.orchestrate_incremental_refresh(v_run_id, v_job, v_refresh);
                    SELECT status INTO STRICT v_status FROM analytics.etl_runs WHERE id = v_run_id;
                ELSE
                    -- Reuse the real trust calculation; never rebuild facts merely
                    -- because an unchanged reconciliation remains blocked.
                    INSERT INTO analytics.etl_runs(id, table_name, status, started_at, completed_at, log_output)
                    VALUES (v_run_id, v_job, 'SUCCESS', clock_timestamp(), clock_timestamp(),
                        jsonb_build_object('reconciliation_only', true));
                    v_status := 'SUCCESS';
                END IF;
                IF v_status IN ('SUCCESS', 'VERIFIED', 'POSTING_CONSISTENCY_ONLY', 'RECONCILED_WITH_WARNING', 'BLOCKED') THEN
                    v_refreshed := v_refreshed + cardinality(v_refresh);
                    -- The orchestrator already reviewed a newly rebuilt batch.
                    -- Review again only to include older unresolved comparisons.
                    IF cardinality(v_refresh) = 0 OR cardinality(v_checkpoint.reconciliation_dates) > 0 THEN
                        BEGIN
                            CALL analytics.compute_double_review_trust_state(v_run_id, v_job, v_review);
                            v_reviewed := v_reviewed + cardinality(v_review);
                        EXCEPTION WHEN OTHERS THEN
                            -- Metric-level monitoring takes precedence over row status.
                            -- Drop the fresh batch's success metrics when the wider
                            -- pending-date review fails; expose FAILED at component level.
                            UPDATE analytics.etl_runs SET status = 'FAILED', metric_states = NULL, drift_value = NULL, log_output =
                                COALESCE(log_output, '{}') || jsonb_build_object('error', SQLERRM, 'state', SQLSTATE)
                            WHERE id = v_run_id;
                        END;
                    ELSE
                        v_reviewed := v_reviewed + cardinality(v_refresh);
                    END IF;
                    -- A trust-calculation failure must retry review, not replay an
                    -- already committed rebuild; an orchestrator failure retries both.
                    v_refresh := '{}';
                END IF;
                SELECT status INTO STRICT v_status FROM analytics.etl_runs WHERE id = v_run_id;
            END IF;
            IF v_status IN ('SUCCESS', 'VERIFIED', 'POSTING_CONSISTENCY_ONLY', 'RECONCILED_WITH_WARNING') THEN
                v_review := '{}';
            END IF;
            IF cardinality(v_refresh) > 0 THEN
                SELECT COALESCE(array_agg(DISTINCT d ORDER BY d), '{}') INTO v_failed_dates
                FROM unnest(v_failed_dates || v_refresh) d;
            END IF;
            UPDATE analytics.etl_runs SET completed_at = clock_timestamp(), log_output =
                COALESCE(log_output, '{}') || jsonb_build_object('refresh_pending_dates', v_refresh,
                    'reconciliation_pending_dates', v_review)
            WHERE id = v_run_id;
        END IF;
        UPDATE analytics.component_checkpoints SET
            scanned_through = GREATEST(scanned_through, v_cutoff),
            refresh_dates = v_refresh, reconciliation_dates = v_review,
            last_run_id = COALESCE(v_run_id, last_run_id)
        WHERE table_name = v_job;
    END LOOP;

    -- Target attainment has its separate existing daily behavior and cron.
    v_run_id := gen_random_uuid();
    CALL analytics.orchestrate_incremental_refresh(v_run_id, 'snapshot_target_attainment', ARRAY[CURRENT_DATE]);
    SELECT COUNT(*) INTO v_pending FROM analytics.component_checkpoints
    WHERE cardinality(refresh_dates) > 0 OR cardinality(reconciliation_dates) > 0;
    IF EXISTS (SELECT 1 FROM analytics.etl_runs WHERE id = v_run_id
        AND status NOT IN ('SUCCESS', 'VERIFIED', 'POSTING_CONSISTENCY_ONLY', 'RECONCILED_WITH_WARNING')) THEN
        v_pending := v_pending + 1;
    END IF;
    -- Every consumed event's dates are now either processed or durably retained
    -- in component retry arrays. A caller rollback restores both events and state.
    DELETE FROM analytics.reporting_invalidation_events WHERE id=ANY(v_event_ids);
    SELECT EXISTS(SELECT 1 FROM analytics.reporting_invalidation_events) INTO v_events_remaining;
    IF v_events_remaining THEN v_pending:=v_pending+1; END IF;
    UPDATE analytics.etl_runs SET status = CASE WHEN v_pending > 0 THEN 'PARTIAL_FAILURE' ELSE 'SUCCESS' END,
        completed_at = clock_timestamp(), log_output = jsonb_build_object(
            'pending_components', v_pending, 'refreshed_buckets', v_refreshed,
            'reviewed_buckets', v_reviewed, 'scan_cutoff', v_cutoff,
            'invalidation_events_consumed',cardinality(v_event_ids),
            'has_pending_invalidation_events',v_events_remaining)
    WHERE id = v_sweep_id;
END;
$$;
REVOKE ALL ON PROCEDURE analytics.run_analytics_watermark_sweep(INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON PROCEDURE analytics.run_analytics_watermark_sweep(INTEGER) TO service_role;




-- Install only the bounded, reviewed source inventory. No row values are expanded
-- in these source-writing transactions except a rule-set PK lookup.
DO $install$
DECLARE s RECORD;
BEGIN
 FOR s IN SELECT * FROM (VALUES ('public','sales_orders',ARRAY['id','customer_id','rep_id','branch_id','status','order_date','delivered_at','total_amount','credit_amount','subtotal','tax_amount'],ARRAY['id','customer_id','order_date','delivered_at']),
('public','sales_order_items',ARRAY['id','order_id','product_id','line_total','tax_amount','base_quantity','unit_cost_at_sale'],ARRAY['id','order_id']),
('public','sales_returns',ARRAY['id','order_id','customer_id','status','confirmed_at','updated_at'],ARRAY['id','order_id','confirmed_at','updated_at']),
('public','sales_return_items',ARRAY['id','return_id','order_item_id','line_total','base_quantity'],ARRAY['id','return_id','order_item_id']),
('public','payment_receipts',ARRAY['id','sales_order_id','customer_id','created_at','amount','status','collected_by'],ARRAY['id','sales_order_id','customer_id','created_at']),
('public','customer_ledger',ARRAY['id','customer_id','created_at','allocated_to','source_id','source_type','type','amount'],ARRAY['id','customer_id','created_at','allocated_to','source_id','source_type','type']),
('public','vault_transactions',ARRAY['id','created_at','type','amount','reference_type','reference_id'],ARRAY['id','created_at','reference_type','reference_id']),
('public','custody_transactions',ARRAY['id','created_at','type','amount','reference_type','reference_id'],ARRAY['id','created_at','reference_type','reference_id']),
('public','journal_entries',ARRAY['id','entry_date','status','source_type','source_id'],ARRAY['id','entry_date','source_type','source_id']),
('public','journal_entry_lines',ARRAY['id','entry_id','account_id','debit','credit'],ARRAY['id','entry_id','account_id']),
('public','customers',ARRAY['id','governorate_id','city_id','area_id'],ARRAY['id']),
('public','expenses',ARRAY['id','branch_id'],ARRAY['id']),
('public','hr_payroll_runs',ARRAY['id','branch_id'],ARRAY['id']),
('public','chart_of_accounts',ARRAY['id','code'],ARRAY['id']),
('public','hr_employees',ARRAY['id','branch_id','status','hire_date','termination_date'],ARRAY['id','branch_id','hire_date','termination_date']),
('analytics','profitability_allocation_rule_sets',ARRAY['id','applies_to','basis','effective_from','effective_to','is_active'],ARRAY['id','effective_from','effective_to']),
('analytics','profitability_allocation_rules',ARRAY['id','rule_set_id','branch_id','weight_value'],ARRAY['id','rule_set_id'])) src(schema_name,table_name,watched,refs) LOOP
  IF EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid=to_regclass(format('%I.%I',s.schema_name,s.table_name))
      AND t.tgname='trg_reporting_invalidation'
      AND t.tgfoid<>'analytics.capture_reporting_invalidation()'::regprocedure) THEN
   RAISE EXCEPTION 'An unrelated reporting trigger already exists on %.%',s.schema_name,s.table_name;
  END IF;
  EXECUTE format('DROP TRIGGER IF EXISTS trg_reporting_invalidation ON %I.%I',s.schema_name,s.table_name);
  EXECUTE format('CREATE TRIGGER trg_reporting_invalidation AFTER INSERT OR UPDATE OR DELETE ON %I.%I FOR EACH ROW EXECUTE FUNCTION analytics.capture_reporting_invalidation(%L,%L)',
      s.schema_name,s.table_name,array_to_string(s.watched,','),array_to_string(s.refs,','));
 END LOOP;
END
$install$;


-- Preserve the installed trust reader's definition/ACL and add one backlog guard.
-- Its existing metric trust states remain unchanged; only freshness becomes stale
-- while committed source events are waiting. Unknown reader shapes fail closed.
DO $monitor_guard$
DECLARE
    v_def TEXT;
    v_anchor TEXT := 'WHEN latest.completed_at < now() - interval ''24 hours'' THEN true';
    v_guard TEXT := 'WHEN EXISTS (SELECT 1 FROM analytics.reporting_invalidation_events) THEN true';
BEGIN
    SELECT pg_get_functiondef('analytics.get_system_trust_state()'::regprocedure) INTO v_def;
    IF strpos(v_def,v_guard)>0 THEN RETURN; END IF;
    IF length(v_def)-length(replace(v_def,v_anchor,''))<>length(v_anchor) THEN
        RAISE EXCEPTION 'Review installed analytics.get_system_trust_state before adding backlog freshness guard';
    END IF;
    EXECUTE replace(v_def,v_anchor,v_guard||E'\n      '||v_anchor);
END
$monitor_guard$;


-- Reviewed component: 20261001142858_analytics_customer_asof_aging.sql
-- Nonproduction-qualified as-of population and bounded daily aging.
-- Requires the two earlier analytics checkpoint/invalidation migrations.
DO $preflight$ BEGIN
 IF to_regclass('analytics.reporting_invalidation_events') IS NULL
 OR to_regclass('analytics.component_checkpoints') IS NULL THEN
  RAISE EXCEPTION 'Apply checkpoint and invalidation migrations first';
 END IF;
 IF NOT pg_try_advisory_xact_lock(hashtext('analytics_global_sweep')) THEN
  RAISE EXCEPTION 'Analytics maintenance lock is busy';
 END IF;
END $preflight$;
ALTER TABLE analytics.component_checkpoints ADD COLUMN IF NOT EXISTS daily_enqueued_through DATE;
ALTER TABLE analytics.component_checkpoints ADD COLUMN IF NOT EXISTS current_day_enqueued DATE;
ALTER TABLE analytics.component_checkpoints ADD COLUMN IF NOT EXISTS asof_seed_version SMALLINT NOT NULL DEFAULT 0;

-- Approved: deterministic population of customers with qualifying activity on/before
-- each Cairo as-of date, including dormant customers. RFM formulas are unchanged.
CREATE OR REPLACE PROCEDURE analytics.internal_refresh_snapshot_customer_health(IN p_target_dates date[])
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,analytics AS $$
DECLARE v_dates DATE[];
BEGIN
  SELECT array_agg(DISTINCT d ORDER BY d) INTO v_dates FROM unnest(p_target_dates) d WHERE d IS NOT NULL;
  IF cardinality(v_dates) IS NULL THEN RETURN; END IF;
  DELETE FROM analytics.snapshot_customer_health WHERE as_of_date=ANY(v_dates);
  WITH requested AS (SELECT unnest(v_dates) AS d),
  sales_history AS MATERIALIZED (
    SELECT so.customer_id,analytics.effective_sale_date(so.delivered_at,so.order_date) AS sale_date,so.total_amount
    FROM public.sales_orders so
    WHERE so.status IN ('delivered','completed') AND so.customer_id IS NOT NULL
      AND analytics.effective_sale_date(so.delivered_at,so.order_date) <= (SELECT max(d) FROM requested)
  ), first_activity AS (
    SELECT a.customer_id,min(a.activity_date) AS first_date FROM (
      SELECT customer_id,min(sale_date) AS activity_date FROM sales_history GROUP BY customer_id
      UNION ALL
      SELECT cl.customer_id,min(analytics.txn_date(cl.created_at)) AS activity_date
      FROM public.customer_ledger cl
      WHERE cl.customer_id IS NOT NULL
        AND cl.created_at < ((SELECT max(d)+1 FROM requested)::timestamp AT TIME ZONE 'Africa/Cairo')
      GROUP BY cl.customer_id
    ) a GROUP BY a.customer_id
  ), dates_cross AS (
    SELECT r.d,a.customer_id FROM requested r JOIN first_activity a ON a.first_date<=r.d
  ), health_stats AS (
    SELECT dx.d AS as_of_date,dx.customer_id,
      max(sh.sale_date) FILTER(WHERE sh.sale_date<=dx.d) AS last_sale_date,
      count(sh.sale_date) FILTER(WHERE sh.sale_date BETWEEN (dx.d-INTERVAL '90 days') AND dx.d) AS freq_l90d,
      coalesce(sum(sh.total_amount) FILTER(WHERE sh.sale_date BETWEEN (dx.d-INTERVAL '90 days') AND dx.d),0) AS monetary_l90d
    FROM dates_cross dx LEFT JOIN sales_history sh ON sh.customer_id=dx.customer_id
    GROUP BY dx.d,dx.customer_id
  )
  INSERT INTO analytics.snapshot_customer_health(as_of_date,customer_id,recency_days,frequency_l90d,monetary_l90d,is_dormant)
  SELECT as_of_date,customer_id,
    CASE WHEN last_sale_date IS NOT NULL THEN as_of_date-last_sale_date ELSE NULL END,
    freq_l90d,monetary_l90d,
    CASE WHEN last_sale_date IS NULL THEN false WHEN as_of_date-last_sale_date>90 THEN true ELSE false END
  FROM health_stats
  ON CONFLICT(as_of_date,customer_id) DO UPDATE SET
    recency_days=EXCLUDED.recency_days,frequency_l90d=EXCLUDED.frequency_l90d,
    monetary_l90d=EXCLUDED.monetary_l90d,is_dormant=EXCLUDED.is_dormant;
END;
$$;

CREATE OR REPLACE FUNCTION analytics.reporting_event_dates(
    p_source_schema TEXT,p_source_table TEXT,p_old JSONB,p_new JSONB
)
RETURNS TABLE(component TEXT,bucket DATE)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,analytics,public AS $$
DECLARE
    r JSONB;
    j RECORD;
    v_dates DATE[] := '{}';
    v_orders UUID[] := '{}';
    v_returns UUID[] := '{}';
    v_receipts UUID[] := '{}';
    v_journals UUID[] := '{}';
    v_customers UUID[] := '{}';
    v_ids UUID[] := '{}';
    v_min DATE;
    v_all_components TEXT[] := ARRAY[
        'fact_sales_daily_grain','fact_financial_ledgers_daily','fact_treasury_cashflow_daily',
        'fact_ar_collections_attributed_to_origin_sale_date','snapshot_customer_health',
        'snapshot_customer_risk','fact_geography_daily','fact_profit_daily',
        'fact_gross_profit_daily_grain','fact_branch_profit_daily',
        'profitability_data_quality_daily','snapshot_branch_allocation_weights_monthly',
        'fact_branch_profit_final_monthly'];
BEGIN
    IF p_source_schema NOT IN ('public','analytics') THEN
        RAISE EXCEPTION 'Unknown reporting invalidation source %.%',p_source_schema,p_source_table;
    END IF;
    IF p_source_schema='public' AND p_source_table='customers' THEN
        -- Only geography keys are watched. Existing grain retains old customer IDs
        -- even when the dimension row is deleted; no recent-date cutoff is used.
        RETURN QUERY
        SELECT 'fact_geography_daily'::text,f.date
        FROM analytics.fact_sales_daily_grain f
        WHERE f.customer_id IN ((p_old->>'id')::uuid,(p_new->>'id')::uuid)
        GROUP BY f.date;
        RETURN;
    END IF;
    IF (p_source_schema='analytics' AND p_source_table IN
        ('profitability_allocation_rule_sets','profitability_allocation_rules'))
        OR (p_source_schema='public' AND p_source_table='hr_employees') THEN
        -- Enumerate actual existing monthly footprints, not an arbitrary lookback
        -- or unbounded future series. Future business facts trigger their own month.
        RETURN QUERY
        WITH months AS (
            SELECT s.month_start AS m FROM analytics.snapshot_branch_allocation_weights_monthly s
            UNION SELECT f.month_start FROM analytics.fact_branch_profit_final_monthly f
            UNION SELECT date_trunc('month',f.profit_date)::date FROM analytics.fact_branch_profit_daily f
        ), refs AS (
            SELECT x.ref FROM (VALUES(p_old),(p_new)) x(ref)
        ), affected AS (
            SELECT DISTINCT m.m
            FROM months m CROSS JOIN refs r
            WHERE CASE WHEN p_source_table='hr_employees' THEN
                (r.ref->>'hire_date')::date <= (m.m+interval '1 month'-interval '1 day')::date
                AND ((r.ref->>'termination_date') IS NULL OR (r.ref->>'termination_date')::date>m.m)
            ELSE
                (r.ref->>'effective_from')::date <= (m.m+interval '1 month'-interval '1 day')::date
                AND ((r.ref->>'effective_to') IS NULL OR (r.ref->>'effective_to')::date>=m.m)
            END
        )
        SELECT n.name,a.m FROM affected a CROSS JOIN unnest(ARRAY[
            'snapshot_branch_allocation_weights_monthly','fact_branch_profit_final_monthly']) n(name);
        RETURN;
    END IF;

    IF p_source_schema<>'public' OR p_source_table NOT IN (
        'sales_orders','sales_order_items','sales_returns','sales_return_items',
        'payment_receipts','customer_ledger','vault_transactions','custody_transactions',
        'journal_entries','journal_entry_lines','expenses','hr_payroll_runs','chart_of_accounts') THEN
        RAISE EXCEPTION 'Unknown reporting invalidation source %.%',p_source_schema,p_source_table;
    END IF;

    FOR r IN SELECT x.ref FROM (VALUES(p_old),(p_new)) x(ref) LOOP
        IF r='{}'::jsonb THEN CONTINUE; END IF;
        CASE p_source_table
        WHEN 'sales_orders' THEN
            v_orders:=v_orders || (r->>'id')::uuid;
            v_customers:=v_customers || (r->>'customer_id')::uuid;
            v_dates:=v_dates || analytics.effective_sale_date((r->>'delivered_at')::timestamptz,(r->>'order_date')::date);
        WHEN 'sales_order_items' THEN
            v_orders:=v_orders || (r->>'order_id')::uuid;
        WHEN 'sales_returns' THEN
            v_returns:=v_returns || (r->>'id')::uuid;
            v_orders:=v_orders || (r->>'order_id')::uuid;
            v_dates:=v_dates || analytics.txn_date((r->>'confirmed_at')::timestamptz)
                || analytics.txn_date((r->>'updated_at')::timestamptz);
        WHEN 'sales_return_items' THEN
            v_returns:=v_returns || (r->>'return_id')::uuid;
            SELECT i.order_id INTO j FROM public.sales_order_items i WHERE i.id=(r->>'order_item_id')::uuid;
            v_orders:=v_orders || j.order_id;
        WHEN 'payment_receipts' THEN
            v_receipts:=v_receipts || (r->>'id')::uuid;
            v_orders:=v_orders || (r->>'sales_order_id')::uuid;
            v_dates:=v_dates || analytics.txn_date((r->>'created_at')::timestamptz);
        WHEN 'customer_ledger' THEN
            v_dates:=v_dates || analytics.txn_date((r->>'created_at')::timestamptz);
            IF r->>'source_type'='sales_order' THEN v_orders:=v_orders || (r->>'source_id')::uuid; END IF;
            IF r->>'source_type'='payment_receipt' THEN v_receipts:=v_receipts || (r->>'source_id')::uuid; END IF;
            SELECT l.source_id INTO j FROM public.customer_ledger l
            WHERE l.id=(r->>'allocated_to')::uuid AND l.source_type='sales_order';
            v_orders:=v_orders || j.source_id;
        WHEN 'vault_transactions','custody_transactions' THEN
            v_dates:=v_dates || analytics.txn_date((r->>'created_at')::timestamptz);
            IF r->>'reference_type'='sales_order' THEN v_orders:=v_orders || (r->>'reference_id')::uuid;
            ELSIF r->>'reference_type'='sales_return' THEN v_returns:=v_returns || (r->>'reference_id')::uuid;
            ELSIF r->>'reference_type'='payment_receipt' THEN v_receipts:=v_receipts || (r->>'reference_id')::uuid;
            END IF;
        WHEN 'journal_entries' THEN
            v_journals:=v_journals || (r->>'id')::uuid;
            v_dates:=v_dates || (r->>'entry_date')::date;
            IF r->>'source_type'='sales_order' THEN v_orders:=v_orders || (r->>'source_id')::uuid;
            ELSIF r->>'source_type'='sales_return' THEN v_returns:=v_returns || (r->>'source_id')::uuid;
            END IF;
        WHEN 'journal_entry_lines' THEN
            v_journals:=v_journals || (r->>'entry_id')::uuid;
        WHEN 'expenses','hr_payroll_runs' THEN
            SELECT COALESCE(array_agg(e.id),'{}'::uuid[]) INTO v_ids FROM public.journal_entries e
            WHERE e.source_id=(r->>'id')::uuid
              AND ((p_source_table='expenses' AND e.source_type='expense')
                OR (p_source_table='hr_payroll_runs' AND e.source_type IN ('hr_payroll','manual')));
            v_journals:=v_journals || v_ids;
        WHEN 'chart_of_accounts' THEN
            SELECT COALESCE(array_agg(DISTINCT l.entry_id),'{}'::uuid[]) INTO v_ids
            FROM public.journal_entry_lines l WHERE l.account_id=(r->>'id')::uuid;
            v_journals:=v_journals || v_ids;
            SELECT v_dates || COALESCE(array_agg(DISTINCT f.date),'{}'::date[]) INTO v_dates
            FROM analytics.fact_financial_ledgers_daily f WHERE f.account_id=(r->>'id')::uuid;
        END CASE;
    END LOOP;

    FOR j IN SELECT e.entry_date,e.source_type,e.source_id FROM public.journal_entries e WHERE e.id=ANY(v_journals) LOOP
        v_dates:=v_dates || j.entry_date;
        IF j.source_type='sales_order' THEN v_orders:=v_orders || j.source_id;
        ELSIF j.source_type='sales_return' THEN v_returns:=v_returns || j.source_id; END IF;
    END LOOP;
    FOR j IN SELECT p.sales_order_id,p.created_at FROM public.payment_receipts p WHERE p.id=ANY(v_receipts) LOOP
        v_orders:=v_orders || j.sales_order_id;
        v_dates:=v_dates || analytics.txn_date(j.created_at);
    END LOOP;
    -- Receipts without a direct order can allocate to many older invoices.
    SELECT v_orders || COALESCE(array_agg(DISTINCT inv.source_id),'{}'::uuid[]) INTO v_orders
    FROM public.customer_ledger c JOIN public.customer_ledger inv ON inv.id=c.allocated_to
    WHERE c.source_type='payment_receipt' AND c.source_id=ANY(v_receipts) AND inv.source_type='sales_order';
    FOR j IN SELECT s.order_id,s.confirmed_at,s.updated_at FROM public.sales_returns s WHERE s.id=ANY(v_returns) LOOP
        v_orders:=v_orders || j.order_id;
        v_dates:=v_dates || analytics.txn_date(j.confirmed_at) || analytics.txn_date(j.updated_at);
    END LOOP;
    FOR j IN SELECT s.id,s.customer_id,s.delivered_at,s.order_date FROM public.sales_orders s WHERE s.id=ANY(v_orders) LOOP
        v_dates:=v_dates || analytics.effective_sale_date(j.delivered_at,j.order_date);
        v_customers:=v_customers || j.customer_id;
    END LOOP;
    -- Source metadata changes also alter existing treasury/refund attribution on
    -- transaction dates that may differ from both sale and receipt creation dates.
    SELECT v_returns || COALESCE(array_agg(DISTINCT s.id),'{}'::uuid[]) INTO v_returns
    FROM public.sales_returns s WHERE s.order_id=ANY(v_orders);
    SELECT v_receipts || COALESCE(array_agg(DISTINCT p.id),'{}'::uuid[]) INTO v_receipts
    FROM public.payment_receipts p WHERE p.sales_order_id=ANY(v_orders);
    SELECT v_dates || COALESCE(array_agg(DISTINCT analytics.txn_date(t.created_at)),'{}'::date[]) INTO v_dates
    FROM (SELECT created_at,reference_type,reference_id FROM public.vault_transactions
          UNION ALL SELECT created_at,reference_type,reference_id FROM public.custody_transactions) t
    WHERE (t.reference_type='sales_order' AND t.reference_id=ANY(v_orders))
       OR (t.reference_type='sales_return' AND t.reference_id=ANY(v_returns))
       OR (t.reference_type='payment_receipt' AND t.reference_id=ANY(v_receipts));
    -- Gross-profit returns use confirmation dates, whereas sales facts use origin dates.
    SELECT v_dates || COALESCE(array_agg(DISTINCT analytics.txn_date(s.confirmed_at)),'{}'::date[]) INTO v_dates
    FROM public.sales_returns s WHERE s.order_id=ANY(v_orders);
    SELECT COALESCE(array_agg(DISTINCT d.val ORDER BY d.val),'{}'::date[]) INTO v_dates
    FROM unnest(v_dates) d(val) WHERE d.val IS NOT NULL;
    RETURN QUERY SELECT c.name,d.val FROM unnest(v_all_components) c(name) CROSS JOIN unnest(v_dates) d(val);

    -- Cross-date health/risk population closure is batched once in
    -- reporting_batch_dates, including customers without prior snapshot rows.
END;
$$;
REVOKE ALL ON FUNCTION analytics.reporting_event_dates(TEXT,TEXT,JSONB,JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION analytics.reporting_batch_dates(p_ids BIGINT[])
RETURNS JSONB LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,analytics AS $$
 WITH refs AS MATERIALIZED (
   SELECT DISTINCT source_schema,source_table,old_ref,new_ref
   FROM analytics.reporting_invalidation_events WHERE id=ANY(p_ids)
 ), expanded AS MATERIALIZED (
   SELECT r.source_schema,r.source_table,d.component,d.bucket
   FROM refs r CROSS JOIN LATERAL analytics.reporting_event_dates(r.source_schema,r.source_table,r.old_ref,r.new_ref) d
   WHERE d.bucket IS NOT NULL
 ), changed_since AS (
   SELECT min(bucket) AS d FROM expanded
   WHERE source_schema='public' AND source_table IN ('sales_orders','sales_order_items','customer_ledger')
     AND component='snapshot_customer_health'
 ), later_dates AS (
   SELECT h.as_of_date AS d FROM analytics.snapshot_customer_health h WHERE h.as_of_date>=(SELECT d FROM changed_since)
   UNION SELECT k.as_of_date FROM analytics.snapshot_customer_risk k WHERE k.as_of_date>=(SELECT d FROM changed_since)
 ), all_dates AS (
   SELECT component,bucket FROM expanded
   UNION ALL
   SELECT c.component,l.d FROM later_dates l CROSS JOIN unnest(ARRAY['snapshot_customer_health','snapshot_customer_risk']) c(component)
 )
 SELECT coalesce(jsonb_object_agg(q.component,q.dates),'{}'::jsonb) FROM (
   SELECT component,jsonb_agg(DISTINCT bucket ORDER BY bucket) AS dates FROM all_dates GROUP BY component
 ) q
$$;
REVOKE ALL ON FUNCTION analytics.reporting_batch_dates(BIGINT[]) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE PROCEDURE analytics.run_analytics_watermark_sweep(p_fallback_days INTEGER DEFAULT 3)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, analytics
AS $$
DECLARE
    v_sweep_id UUID := gen_random_uuid();
    v_run_id UUID;
    v_started TIMESTAMPTZ := clock_timestamp();
    v_cutoff TIMESTAMPTZ;
    v_initial TIMESTAMPTZ;
    v_scan TIMESTAMPTZ;
    v_cached_scan TIMESTAMPTZ;
    v_changed DATE[];
    v_refresh DATE[];
    v_review DATE[];
    v_failed_dates DATE[] := '{}';
    v_checkpoint analytics.component_checkpoints%ROWTYPE;
    v_previous RECORD;
    v_job TEXT;
    v_status TEXT;
    v_pending INTEGER;
    v_refreshed INTEGER := 0;
    v_reviewed INTEGER := 0;
    v_event_ids BIGINT[] := '{}';
    v_event_dates JSONB := '{}';
    v_events_remaining BOOLEAN := false;
    v_cairo_today DATE := (v_started AT TIME ZONE 'Africa/Cairo')::date;
    v_daily_dates DATE[] := '{}';
    v_daily_through DATE;
    v_current_day DATE;
    v_population_dates DATE[] := '{}';
    v_all_snapshot_dates DATE[];
    v_waiting_dates DATE[] := '{}';
    v_blocked_dates DATE[] := '{}';
BEGIN
    IF p_fallback_days IS NULL OR p_fallback_days < 1 THEN
        RAISE EXCEPTION 'p_fallback_days must be positive';
    END IF;
    -- A transaction lock also conflicts with the existing session lock used by
    -- backfill/admin refresh, and survives until the caller commits or rolls back.
    IF NOT pg_try_advisory_xact_lock(hashtext('analytics_global_sweep')) THEN
        RAISE NOTICE 'Analytics sweep locked elsewhere - exiting.';
        RETURN;
    END IF;
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'Analytics checkpoint scans require READ COMMITTED';
    END IF;
    IF NOT pg_has_role(current_user, 'pg_read_all_stats', 'USAGE') THEN
        RAISE EXCEPTION 'Sweep owner must see all transaction start times';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_prepared_xacts WHERE database = current_database()) THEN
        RAISE EXCEPTION 'Resolve prepared transactions before checkpoint scanning';
    END IF;
    -- Source timestamps use transaction time. An uncommitted older writer must
    -- remain inside the next scan even if it commits after this scan's snapshot.
    SELECT LEAST(v_started, COALESCE(MIN(xact_start), v_started)) - interval '1 microsecond'
    INTO v_cutoff FROM pg_stat_activity WHERE datname = current_database();
    SELECT COALESCE(MAX(started_at), v_started - make_interval(days => p_fallback_days))
    INTO v_initial FROM analytics.etl_runs
    WHERE table_name = 'GLOBAL_SWEEP'
      AND status IN ('SUCCESS', 'VERIFIED', 'POSTING_CONSISTENCY_ONLY', 'RECONCILED_WITH_WARNING');

    INSERT INTO analytics.etl_runs(id, table_name, status, started_at)
    VALUES (v_sweep_id, 'GLOBAL_SWEEP', 'RUNNING', v_started);

    -- Snapshot explicit visible IDs; do not use a max-ID cursor, since a lower
    -- sequence value may commit after a higher one. Process at most 1000 events.
    SELECT COALESCE(array_agg(e.id ORDER BY e.id),'{}'::bigint[]) INTO v_event_ids
    FROM (SELECT id FROM analytics.reporting_invalidation_events ORDER BY id LIMIT 1000) e;
    v_event_dates := analytics.reporting_batch_dates(v_event_ids);

    -- Preserve the existing dependency order. On a real refresh failure, later
    -- components conservatively retain those dates rather than consume stale facts.
    FOREACH v_job IN ARRAY ARRAY[
        'fact_sales_daily_grain', 'fact_financial_ledgers_daily',
        'fact_treasury_cashflow_daily', 'fact_ar_collections_attributed_to_origin_sale_date',
        'snapshot_customer_health', 'snapshot_customer_risk', 'fact_geography_daily',
        'fact_profit_daily', 'fact_gross_profit_daily_grain', 'fact_branch_profit_daily',
        'profitability_data_quality_daily', 'snapshot_branch_allocation_weights_monthly',
        'fact_branch_profit_final_monthly'
    ] LOOP
        IF NOT EXISTS (SELECT 1 FROM analytics.component_checkpoints WHERE table_name = v_job) THEN
            SELECT status, log_output INTO v_previous FROM analytics.etl_runs
            WHERE table_name = v_job ORDER BY started_at DESC LIMIT 1;
            IF v_previous.status IN ('BLOCKED', 'FAILED') THEN
                IF v_previous.log_output->>'min_affected_date' IS NULL
                    OR v_previous.log_output->>'max_affected_date' IS NULL THEN
                    RAISE EXCEPTION 'Seed exact pending dates for % before initializing its checkpoint', v_job;
                END IF;
                -- Legacy logs have bounds rather than an exact date array. A
                -- conservative contiguous range preserves every unresolved bucket.
                INSERT INTO analytics.component_checkpoints(table_name, scanned_through, refresh_dates)
                SELECT v_job, v_initial, array_agg(d::DATE ORDER BY d)
                FROM generate_series((v_previous.log_output->>'min_affected_date')::DATE,
                    (v_previous.log_output->>'max_affected_date')::DATE, interval '1 day') d;
            END IF;
        END IF;
        INSERT INTO analytics.component_checkpoints(table_name, scanned_through)
        VALUES (v_job, v_initial) ON CONFLICT DO NOTHING;
        SELECT * INTO STRICT v_checkpoint FROM analytics.component_checkpoints
        WHERE table_name = v_job FOR UPDATE;
        v_daily_dates := '{}';
        v_population_dates := '{}';
        v_daily_through := v_checkpoint.daily_enqueued_through;
        v_current_day := v_checkpoint.current_day_enqueued;
        IF v_job IN ('snapshot_customer_health','snapshot_customer_risk') THEN
            -- Record scheduled-through only alongside durable refresh retry dates.
            -- A calendar catch-up is bounded to fifteen new dates per sweep.
            IF v_daily_through IS NULL OR v_daily_through<v_cairo_today THEN
                v_daily_through := least(v_cairo_today,coalesce(v_daily_through+15,v_cairo_today));
                SELECT coalesce(array_agg(d::date ORDER BY d),'{}') INTO v_daily_dates
                FROM generate_series(coalesce(v_checkpoint.daily_enqueued_through+1,v_cairo_today)::timestamp,
                    v_daily_through::timestamp,interval '1 day') d
                WHERE d::date<>v_cairo_today OR v_checkpoint.current_day_enqueued IS DISTINCT FROM v_cairo_today;
            END IF;
            IF v_current_day IS NULL OR v_current_day<v_cairo_today THEN
                v_daily_dates := v_daily_dates || v_cairo_today;
                v_current_day := v_cairo_today;
            END IF;
            IF v_checkpoint.asof_seed_version<1 THEN
                IF v_all_snapshot_dates IS NULL THEN
                    SELECT coalesce(array_agg(d ORDER BY d),'{}') INTO v_all_snapshot_dates FROM (
                        SELECT as_of_date AS d FROM analytics.snapshot_customer_health
                        UNION SELECT as_of_date FROM analytics.snapshot_customer_risk
                    ) old_dates;
                END IF;
                v_population_dates := v_all_snapshot_dates;
            END IF;
        END IF;
        v_scan := v_checkpoint.scanned_through;
        IF v_cached_scan IS DISTINCT FROM v_scan THEN
            v_changed := analytics.detect_affected_dates(v_scan);
            v_cached_scan := v_scan;
        END IF;
        SELECT COALESCE(array_agg(DISTINCT d ORDER BY d), '{}'::DATE[]) INTO v_refresh
        FROM unnest(COALESCE(v_changed, '{}') || v_checkpoint.refresh_dates || v_daily_dates || v_population_dates
            || ARRAY(SELECT x.d::date FROM jsonb_array_elements_text(v_event_dates->v_job) x(d))) d
        WHERE d IS NOT NULL;
        SELECT COALESCE(array_agg(DISTINCT d ORDER BY d), '{}'::DATE[]) INTO v_review
        FROM unnest(v_refresh || v_checkpoint.reconciliation_dates) d WHERE d IS NOT NULL;
        IF v_job IN ('snapshot_branch_allocation_weights_monthly', 'fact_branch_profit_final_monthly') THEN
            SELECT COALESCE(array_agg(DISTINCT date_trunc('month', d)::DATE ORDER BY date_trunc('month', d)::DATE), '{}')
            INTO v_refresh FROM unnest(v_refresh) d;
            SELECT COALESCE(array_agg(DISTINCT date_trunc('month', d)::DATE ORDER BY date_trunc('month', d)::DATE), '{}')
            INTO v_review FROM unnest(v_review) d;
        END IF;
        SELECT coalesce(array_agg(DISTINCT CASE WHEN v_job IN ('snapshot_branch_allocation_weights_monthly','fact_branch_profit_final_monthly')
            THEN date_trunc('month',d)::date ELSE d END),'{}') INTO v_blocked_dates FROM unnest(v_failed_dates) d;
        v_waiting_dates := v_refresh;
        SELECT coalesce(array_agg(d ORDER BY priority,d),'{}') INTO v_refresh FROM (
            SELECT d,CASE WHEN d=CASE WHEN v_job IN ('snapshot_branch_allocation_weights_monthly','fact_branch_profit_final_monthly')
                THEN date_trunc('month',v_cairo_today)::date ELSE v_cairo_today END THEN 0 ELSE 1 END AS priority
            FROM unnest(v_waiting_dates) d WHERE NOT(d=ANY(v_blocked_dates))
            ORDER BY priority,d LIMIT 15
        ) bounded;
        SELECT coalesce(array_agg(d ORDER BY d),'{}') INTO v_waiting_dates FROM unnest(v_waiting_dates) d WHERE NOT(d=ANY(v_refresh));
        SELECT coalesce(array_agg(d ORDER BY d),'{}') INTO v_review FROM unnest(v_review) d
        WHERE NOT(d=ANY(v_waiting_dates)) AND NOT(d=ANY(v_blocked_dates));
        v_run_id := NULL;
        v_status := NULL;
        IF cardinality(v_review) > 0 THEN
            v_run_id := gen_random_uuid();
                IF cardinality(v_refresh) > 0 THEN
                    CALL analytics.orchestrate_incremental_refresh(v_run_id, v_job, v_refresh);
                    SELECT status INTO STRICT v_status FROM analytics.etl_runs WHERE id = v_run_id;
                ELSE
                    -- Reuse the real trust calculation; never rebuild facts merely
                    -- because an unchanged reconciliation remains blocked.
                    INSERT INTO analytics.etl_runs(id, table_name, status, started_at, completed_at, log_output)
                    VALUES (v_run_id, v_job, 'SUCCESS', clock_timestamp(), clock_timestamp(),
                        jsonb_build_object('reconciliation_only', true));
                    v_status := 'SUCCESS';
                END IF;
                IF v_status IN ('SUCCESS', 'VERIFIED', 'POSTING_CONSISTENCY_ONLY', 'RECONCILED_WITH_WARNING', 'BLOCKED') THEN
                    v_refreshed := v_refreshed + cardinality(v_refresh);
                    -- The orchestrator already reviewed a newly rebuilt batch.
                    -- Review again only to include older unresolved comparisons.
                    IF cardinality(v_refresh) = 0 OR cardinality(v_checkpoint.reconciliation_dates) > 0 THEN
                        BEGIN
                            CALL analytics.compute_double_review_trust_state(v_run_id, v_job, v_review);
                            v_reviewed := v_reviewed + cardinality(v_review);
                        EXCEPTION WHEN OTHERS THEN
                            -- Metric-level monitoring takes precedence over row status.
                            -- Drop the fresh batch's success metrics when the wider
                            -- pending-date review fails; expose FAILED at component level.
                            UPDATE analytics.etl_runs SET status = 'FAILED', metric_states = NULL, drift_value = NULL, log_output =
                                COALESCE(log_output, '{}') || jsonb_build_object('error', SQLERRM, 'state', SQLSTATE)
                            WHERE id = v_run_id;
                        END;
                    ELSE
                        v_reviewed := v_reviewed + cardinality(v_refresh);
                    END IF;
                    -- A trust-calculation failure must retry review, not replay an
                    -- already committed rebuild; an orchestrator failure retries both.
                    v_refresh := '{}';
                END IF;
                SELECT status INTO STRICT v_status FROM analytics.etl_runs WHERE id = v_run_id;
            IF v_status IN ('SUCCESS', 'VERIFIED', 'POSTING_CONSISTENCY_ONLY', 'RECONCILED_WITH_WARNING') THEN
                v_review := '{}';
            END IF;
            UPDATE analytics.etl_runs SET completed_at = clock_timestamp(), log_output =
                COALESCE(log_output, '{}') || jsonb_build_object('refresh_pending_dates', v_refresh,
                    'reconciliation_pending_dates', v_review)
            WHERE id = v_run_id;
        END IF;
        SELECT coalesce(array_agg(DISTINCT d ORDER BY d),'{}') INTO v_refresh
        FROM unnest(v_refresh||v_waiting_dates) d;
        IF cardinality(v_refresh)>0 THEN
            SELECT coalesce(array_agg(DISTINCT d ORDER BY d),'{}') INTO v_failed_dates
            FROM unnest(v_failed_dates||v_refresh) d;
        END IF;
        IF v_run_id IS NOT NULL THEN
            UPDATE analytics.etl_runs SET log_output=coalesce(log_output,'{}')||jsonb_build_object('refresh_pending_dates',v_refresh,'refresh_bucket_limit',15)
            WHERE id=v_run_id;
        END IF;
        UPDATE analytics.component_checkpoints SET
            scanned_through = GREATEST(scanned_through, v_cutoff),
            refresh_dates = v_refresh, reconciliation_dates = v_review,
            last_run_id = COALESCE(v_run_id, last_run_id),
            daily_enqueued_through = v_daily_through,
            current_day_enqueued = v_current_day,
            asof_seed_version = CASE WHEN v_job IN ('snapshot_customer_health','snapshot_customer_risk') THEN 1 ELSE asof_seed_version END
        WHERE table_name = v_job;
    END LOOP;

    -- Target attainment has its separate existing daily behavior and cron.
    v_run_id := gen_random_uuid();
    CALL analytics.orchestrate_incremental_refresh(v_run_id, 'snapshot_target_attainment', ARRAY[CURRENT_DATE]);
    SELECT COUNT(*) INTO v_pending FROM analytics.component_checkpoints
    WHERE cardinality(refresh_dates) > 0 OR cardinality(reconciliation_dates) > 0
       OR (table_name IN ('snapshot_customer_health','snapshot_customer_risk')
           AND (daily_enqueued_through IS NULL OR daily_enqueued_through<v_cairo_today));
    IF EXISTS (SELECT 1 FROM analytics.etl_runs WHERE id = v_run_id
        AND status NOT IN ('SUCCESS', 'VERIFIED', 'POSTING_CONSISTENCY_ONLY', 'RECONCILED_WITH_WARNING')) THEN
        v_pending := v_pending + 1;
    END IF;
    -- Every consumed event's dates are now either processed or durably retained
    -- in component retry arrays. A caller rollback restores both events and state.
    DELETE FROM analytics.reporting_invalidation_events WHERE id=ANY(v_event_ids);
    SELECT EXISTS(SELECT 1 FROM analytics.reporting_invalidation_events) INTO v_events_remaining;
    IF v_events_remaining THEN v_pending:=v_pending+1; END IF;
    UPDATE analytics.etl_runs SET status = CASE WHEN v_pending > 0 THEN 'PARTIAL_FAILURE' ELSE 'SUCCESS' END,
        completed_at = clock_timestamp(), log_output = jsonb_build_object(
            'pending_components', v_pending, 'refreshed_buckets', v_refreshed,
            'reviewed_buckets', v_reviewed, 'scan_cutoff', v_cutoff,
            'invalidation_events_consumed',cardinality(v_event_ids),
            'has_pending_invalidation_events',v_events_remaining, 'cairo_snapshot_date',v_cairo_today,'per_component_refresh_bucket_limit',15)
    WHERE id = v_sweep_id;
END;
$$;
REVOKE ALL ON PROCEDURE analytics.run_analytics_watermark_sweep(INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON PROCEDURE analytics.run_analytics_watermark_sweep(INTEGER) TO service_role;
-- Preserve the installed reader and ACL; add a health/risk calendar gate.
DO $calendar_guard$
DECLARE v_def TEXT;
 v_anchor TEXT := 'WHEN latest.completed_at < now() - interval ''24 hours'' THEN true';
 v_guard TEXT := 'WHEN EXISTS (SELECT 1 FROM analytics.component_checkpoints pending WHERE pending.table_name=latest.table_name AND (cardinality(pending.refresh_dates)>0 OR cardinality(pending.reconciliation_dates)>0)) THEN true WHEN latest.table_name IN (''snapshot_customer_health'',''snapshot_customer_risk'') AND NOT EXISTS (SELECT 1 FROM analytics.component_checkpoints cp WHERE cp.table_name=latest.table_name AND cp.asof_seed_version=1 AND cp.daily_enqueued_through>=(now() AT TIME ZONE ''Africa/Cairo'')::date AND cp.current_day_enqueued>=(now() AT TIME ZONE ''Africa/Cairo'')::date AND cardinality(cp.refresh_dates)=0) THEN true';
BEGIN
 SELECT pg_get_functiondef('analytics.get_system_trust_state()'::regprocedure) INTO v_def;
 IF strpos(v_def,v_guard)>0 THEN RETURN; END IF;
 IF length(v_def)-length(replace(v_def,v_anchor,''))<>length(v_anchor) THEN
  RAISE EXCEPTION 'Review installed trust reader before adding daily freshness guard';
 END IF;
 EXECUTE replace(v_def,v_anchor,v_guard||E'\n      '||v_anchor);
END $calendar_guard$;

$reviewed_release_sql$;
END $atomic_reporting_release$;
