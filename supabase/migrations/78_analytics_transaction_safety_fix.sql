-- ============================================================
-- 78_analytics_transaction_safety_fix.sql
-- Purpose: Fix COMMIT/ROLLBACK inside analytics ETL procedures
--          that cause ERROR 2D000: invalid transaction termination
--          when called from Supabase RPC context (external transaction).
--
-- ADDITIVE ONLY — does not modify files 75/76/77.
-- Uses CREATE OR REPLACE to replace only the affected procedures.
--
-- Root Cause:
--   PostgreSQL allows COMMIT/ROLLBACK inside PROCEDUREs only when
--   the procedure is invoked at the TOP of the call stack with no
--   enclosing transaction (called via direct `CALL` by a session
--   with no active BEGIN). When Supabase calls a procedure via
--   supabase.rpc() — or when run inside Supabase's migration runner —
--   there IS an enclosing transaction. Any COMMIT inside is illegal.
--
-- Architectural Decision:
--   Model A — "Log-and-continue, never re-raise after logging":
--
--   Each procedure records its own status (RUNNING → SUCCESS/FAILED)
--   within the SAME transaction as the work itself.
--
--   The caller reads results from etl_runs after completion.
--   The UI reads etl_runs to show trust/freshness state.
--
--   WHY THIS IS SAFE:
--   - If the outer transaction commits → etl_runs records survive
--   - If the outer transaction rolls back → so does etl_runs (intentional:
--     we don't want ghost SUCCESS records for work that didn't persist)
--   - The sweep itself won't crash the caller session
--   - Advisory lock is still released in all paths (via BEGIN/EXCEPTION)
--
-- Advisory Lock:
--   pg_try_advisory_lock / pg_advisory_unlock are session-scoped and
--   NOT transaction-scoped, so they survive rollback. Safe to keep.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- Fix A: compute_double_review_trust_state
--   Removed: COMMIT on line 647 of 76_analytics_incremental_jobs.sql
--   Reason: this is a pure UPDATE to etl_runs; no COMMIT needed.
--           It will be committed with the outer transaction.
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE analytics.compute_double_review_trust_state(
  p_run_id      UUID,
  p_job_name    TEXT,
  p_target_dates DATE[]
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_analytics_rev_val NUMERIC := 0;
  v_ledger_rev_val    NUMERIC := 0;
  v_analytics_tax_val NUMERIC := 0;
  v_ledger_tax_val    NUMERIC := 0;
  v_analytics_ar_val  NUMERIC := 0;
  v_ledger_ar_val     NUMERIC := 0;
  v_drift_rev         NUMERIC := 0;
  v_drift_tax         NUMERIC := 0;
  v_drift_ar          NUMERIC := 0;
  v_analytics_val     NUMERIC := 0;
  v_ledger_val        NUMERIC := 0;
  v_drift             NUMERIC := 0;
  v_final_state       TEXT    := 'VERIFIED';
BEGIN
  IF p_job_name = 'fact_sales_daily_grain' THEN
    SELECT COALESCE(SUM(net_tax_exclusive_revenue), 0) INTO v_analytics_rev_val
    FROM analytics.fact_sales_daily_grain WHERE date = ANY(p_target_dates);

    SELECT COALESCE(SUM(tax_amount), 0) INTO v_analytics_tax_val
    FROM analytics.fact_sales_daily_grain WHERE date = ANY(p_target_dates);

    SELECT COALESCE(SUM(ar_credit_portion_amount), 0) INTO v_analytics_ar_val
    FROM analytics.fact_sales_daily_grain WHERE date = ANY(p_target_dates);

    WITH gl_agg AS (
      SELECT DATE(COALESCE(so.delivered_at, so.order_date)) as origin_date,
             coa.code, SUM(jel.credit) as cr_sum, SUM(jel.debit) as cr_debit
      FROM public.journal_entry_lines jel
      JOIN public.journal_entries je ON je.id = jel.entry_id
      JOIN public.chart_of_accounts coa ON coa.id = jel.account_id
      JOIN public.sales_orders so ON so.id = je.source_id AND je.source_type = 'sales_order'
      WHERE je.status = 'posted' AND coa.code IN ('4100', '2200', '1200')
      GROUP BY 1, 2
    ),
    gl_returns AS (
      SELECT DATE(COALESCE(so.delivered_at, so.order_date)) as origin_date,
             coa.code, SUM(jel.debit) as ret_debit
      FROM public.journal_entry_lines jel
      JOIN public.journal_entries je ON je.id = jel.entry_id
      JOIN public.chart_of_accounts coa ON coa.id = jel.account_id
      JOIN public.sales_returns sr ON sr.id = je.source_id AND je.source_type = 'sales_return'
      JOIN public.sales_orders so ON so.id = sr.order_id
      WHERE je.status = 'posted' AND coa.code = '4200'
      GROUP BY 1, 2
    )
    SELECT
      COALESCE((SELECT SUM(cr_sum)   FROM gl_agg     WHERE origin_date = ANY(p_target_dates) AND code = '4100'), 0) -
      COALESCE((SELECT SUM(ret_debit) FROM gl_returns WHERE origin_date = ANY(p_target_dates) AND code = '4200'), 0),
      COALESCE((SELECT SUM(cr_sum)   FROM gl_agg     WHERE origin_date = ANY(p_target_dates) AND code = '2200'), 0),
      COALESCE((SELECT SUM(cr_debit) FROM gl_agg     WHERE origin_date = ANY(p_target_dates) AND code = '1200'), 0)
    INTO v_ledger_rev_val, v_ledger_tax_val, v_ledger_ar_val;

    v_drift_rev := v_analytics_rev_val - v_ledger_rev_val;
    v_drift_tax := v_analytics_tax_val - v_ledger_tax_val;
    v_drift_ar  := v_analytics_ar_val  - v_ledger_ar_val;

    IF v_drift_rev = 0 AND v_drift_tax = 0 AND v_drift_ar = 0 THEN
      v_final_state := 'POSTING_CONSISTENCY_ONLY';
    ELSIF ABS(v_drift_rev) <= 5.0 AND ABS(v_drift_tax) <= 5.0 AND ABS(v_drift_ar) <= 5.0 THEN
      v_final_state := 'RECONCILED_WITH_WARNING';
    ELSE
      v_final_state := 'BLOCKED';
    END IF;

    UPDATE analytics.etl_runs
    SET drift_value   = ABS(v_drift_rev) + ABS(v_drift_tax) + ABS(v_drift_ar),
        status        = v_final_state,
        metric_states = jsonb_build_object(
          'revenue',    jsonb_build_object('status', CASE WHEN ABS(v_drift_rev) <= 0 THEN 'POSTING_CONSISTENCY_ONLY' WHEN ABS(v_drift_rev) <= 5.0 THEN 'RECONCILED_WITH_WARNING' ELSE 'BLOCKED' END, 'drift_value', v_drift_rev),
          'tax',        jsonb_build_object('status', CASE WHEN ABS(v_drift_tax) <= 0 THEN 'POSTING_CONSISTENCY_ONLY' WHEN ABS(v_drift_tax) <= 5.0 THEN 'RECONCILED_WITH_WARNING' ELSE 'BLOCKED' END, 'drift_value', v_drift_tax),
          'ar_creation',jsonb_build_object('status', CASE WHEN ABS(v_drift_ar)  <= 0 THEN 'VERIFIED'                WHEN ABS(v_drift_ar)  <= 5.0 THEN 'RECONCILED_WITH_WARNING' ELSE 'BLOCKED' END, 'drift_value', v_drift_ar)
        ),
        log_output    = jsonb_build_object(
          'rev_fact', v_analytics_rev_val, 'rev_gl', v_ledger_rev_val, 'drift_rev', v_drift_rev,
          'tax_fact', v_analytics_tax_val, 'tax_gl', v_ledger_tax_val, 'drift_tax', v_drift_tax,
          'ar_fact',  v_analytics_ar_val,  'ar_gl',  v_ledger_ar_val,  'drift_ar',  v_drift_ar
        )
    WHERE id = p_run_id;

  ELSIF p_job_name = 'fact_treasury_cashflow_daily' THEN
    SELECT COALESCE(SUM(net_cashflow), 0) INTO v_analytics_val
    FROM analytics.fact_treasury_cashflow_daily WHERE treasury_date = ANY(p_target_dates);

    SELECT
      COALESCE((SELECT SUM(amount) FROM public.vault_transactions   WHERE DATE(created_at) = ANY(p_target_dates) AND type = 'collection'), 0) +
      COALESCE((SELECT SUM(amount) FROM public.custody_transactions WHERE DATE(created_at) = ANY(p_target_dates) AND type = 'collection'), 0) -
      COALESCE((SELECT SUM(amount) FROM public.vault_transactions   WHERE DATE(created_at) = ANY(p_target_dates) AND type = 'withdrawal' AND reference_type = 'sales_return'), 0) -
      COALESCE((SELECT SUM(amount) FROM public.custody_transactions WHERE DATE(created_at) = ANY(p_target_dates) AND type = 'expense'    AND reference_type = 'sales_return'), 0)
    INTO v_ledger_val;

    v_drift := v_analytics_val - v_ledger_val;

    IF    v_drift = 0            THEN v_final_state := 'VERIFIED';
    ELSIF ABS(v_drift) <= 5.0   THEN v_final_state := 'RECONCILED_WITH_WARNING';
    ELSE                              v_final_state := 'BLOCKED';
    END IF;

    UPDATE analytics.etl_runs
    SET drift_value   = v_drift,
        status        = v_final_state,
        metric_states = jsonb_build_object('net_collection', jsonb_build_object('status', v_final_state, 'drift_value', v_drift)),
        log_output    = jsonb_build_object('analytics_val', v_analytics_val, 'ledger_val', v_ledger_val)
    WHERE id = p_run_id;
  END IF;

  -- *** NO COMMIT HERE — inherited from outer transaction ***
END;
$$;


-- ─────────────────────────────────────────────────────────────
-- Fix B: orchestrate_incremental_refresh
--   Removed: COMMIT on lines 660, 680, 691 of 76_analytics_incremental_jobs.sql
--   Replaced: the EXCEPTION handler now logs failure but does NOT re-raise,
--             so the outer sweep can continue with remaining subjobs.
--
--   Failure signal mechanism:
--     After each CALL, the sweep reads etl_runs.status to count
--     FAILED/BLOCKED rows. This replaces exception propagation.
--     The caller (run_analytics_watermark_sweep) already does this check.
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE analytics.orchestrate_incremental_refresh(
  p_run_id       UUID,
  p_job_name     TEXT,
  p_target_dates DATE[]
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Record job start (same transaction as the work — correct behaviour)
  INSERT INTO analytics.etl_runs (id, table_name, status, started_at)
  VALUES (p_run_id, p_job_name, 'RUNNING', now())
  ON CONFLICT (id) DO UPDATE SET status = 'RUNNING', started_at = now();

  -- *** NO COMMIT — work and log are in the same transaction ***

  BEGIN
    -- Dispatch to fact-specific refresh procedure
    IF    p_job_name = 'fact_sales_daily_grain' THEN
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
      RAISE EXCEPTION 'Unknown job: %', p_job_name;
    END IF;

    -- Mark SUCCESS (still same transaction — will commit with outer)
    UPDATE analytics.etl_runs
    SET status = 'SUCCESS', completed_at = now()
    WHERE id = p_run_id;

    -- *** NO COMMIT ***

    -- Run double-review trust state (reads from fact tables just written,
    -- updates etl_runs in the same transaction)
    CALL analytics.compute_double_review_trust_state(p_run_id, p_job_name, p_target_dates);

  EXCEPTION WHEN OTHERS THEN
    -- Log failure WITHOUT re-raising — sweep continues with other subjobs.
    -- The failed subjob's INSERT/DELETE in the fact table will be rolled back
    -- by the implicit savepoint that PostgreSQL uses for inner BEGIN blocks.
    -- The etl_runs UPDATE below is in the outer transaction and WILL persist.
    UPDATE analytics.etl_runs
    SET status      = 'FAILED',
        completed_at = now(),
        log_output   = jsonb_build_object(
          'error',  SQLERRM,
          'state',  SQLSTATE,
          'dates',  p_target_dates::text
        )
    WHERE id = p_run_id;

    -- *** NO COMMIT — outer sweep transaction handles persistence ***
    -- The sweep will detect FAILED status and mark itself PARTIAL_FAILURE.
  END;
END;
$$;


-- ─────────────────────────────────────────────────────────────
-- Fix C: run_analytics_watermark_sweep
--   Removed: COMMIT on lines 734, 766, 777 of 76_analytics_incremental_jobs.sql
--   Advisory lock: pg_try_advisory_lock / pg_advisory_unlock are
--     session-level and NOT transaction-scoped — they survive rollback.
--     They remain unchanged and are still released in all exit paths.
--
--   Caller contract after fix:
--     CALL analytics.run_analytics_watermark_sweep(120);
--     -- If no exception is raised, the procedure completed.
--     -- Read etl_runs WHERE table_name = 'GLOBAL_SWEEP' ORDER BY started_at DESC LIMIT 1
--     -- to determine outcome: SUCCESS | PARTIAL_FAILURE | FAILED
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE analytics.run_analytics_watermark_sweep(
  p_fallback_days INTEGER DEFAULT 3
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_watermark       TIMESTAMPTZ;
  v_sweep_start     TIMESTAMPTZ := now();
  v_target_dates    DATE[];
  v_lock_obtained   BOOLEAN;
  v_failed_subjobs  INTEGER := 0;
  v_sweep_id        UUID := gen_random_uuid();
  v_run_id_1        UUID := gen_random_uuid();
  v_run_id_2        UUID := gen_random_uuid();
  v_run_id_3        UUID := gen_random_uuid();
  v_run_id_4        UUID := gen_random_uuid();
  v_run_id_5        UUID := gen_random_uuid();
BEGIN
  -- Advisory lock: session-scoped, survives transaction rollback
  SELECT pg_try_advisory_lock(hashtext('analytics_global_sweep')) INTO v_lock_obtained;

  IF NOT v_lock_obtained THEN
    RAISE NOTICE 'Analytics sweep locked elsewhere — exiting.';
    RETURN;
  END IF;

  BEGIN
    -- ── 1. Determine watermark ────────────────────────────────
    SELECT COALESCE(
      MAX(started_at),
      now() - (p_fallback_days || ' days')::interval
    )
    INTO v_watermark
    FROM analytics.etl_runs
    WHERE table_name = 'GLOBAL_SWEEP'
      AND status IN ('SUCCESS', 'POSTING_CONSISTENCY_ONLY', 'VERIFIED', 'RECONCILED_WITH_WARNING');

    -- ── 2. Register sweep as RUNNING ─────────────────────────
    -- This INSERT is in the same transaction as the work.
    -- It will commit when the whole procedure succeeds.
    INSERT INTO analytics.etl_runs (id, table_name, status, started_at)
    VALUES (v_sweep_id, 'GLOBAL_SWEEP', 'RUNNING', v_sweep_start);

    -- *** NO COMMIT ***

    -- ── 3. Detect affected dates ──────────────────────────────
    SELECT analytics.detect_affected_dates(v_watermark) INTO v_target_dates;

    -- ── 4. Execute subjobs ────────────────────────────────────
    IF array_length(v_target_dates, 1) IS NOT NULL THEN
      CALL analytics.orchestrate_incremental_refresh(v_run_id_1, 'fact_sales_daily_grain',                              v_target_dates);
      CALL analytics.orchestrate_incremental_refresh(v_run_id_2, 'fact_financial_ledgers_daily',                        v_target_dates);
      CALL analytics.orchestrate_incremental_refresh(v_run_id_3, 'fact_treasury_cashflow_daily',                        v_target_dates);
      CALL analytics.orchestrate_incremental_refresh(v_run_id_4, 'fact_ar_collections_attributed_to_origin_sale_date',  v_target_dates);
      CALL analytics.orchestrate_incremental_refresh(v_run_id_5, 'snapshot_customer_health',                            v_target_dates);
    END IF;

    -- ── 5. Evaluate sweep-level outcome ──────────────────────
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

    -- *** NO COMMIT — outer transaction commits all writes atomically ***
    -- Advisory lock release (session-level, safe after transaction)
    PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));

  EXCEPTION WHEN OTHERS THEN
    -- Sweep-level failure: update GLOBAL_SWEEP status
    UPDATE analytics.etl_runs
    SET status      = 'FAILED',
        completed_at = now(),
        log_output   = jsonb_build_object('error', SQLERRM, 'state', SQLSTATE)
    WHERE id = v_sweep_id;

    -- *** NO COMMIT — RAISE will propagate to caller ***
    -- The caller's transaction will commit when it exits.
    PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));
    RAISE;  -- re-raise so caller knows sweep failed structurally
  END;

END;
$$;


-- ─────────────────────────────────────────────────────────────
-- Preserve original grants (idempotent)
-- ─────────────────────────────────────────────────────────────
REVOKE ALL ON PROCEDURE analytics.orchestrate_incremental_refresh(UUID, TEXT, DATE[]) FROM public;
REVOKE ALL ON PROCEDURE analytics.run_analytics_watermark_sweep(INTEGER) FROM public;
REVOKE ALL ON PROCEDURE analytics.compute_double_review_trust_state(UUID, TEXT, DATE[]) FROM public;

GRANT EXECUTE ON PROCEDURE analytics.orchestrate_incremental_refresh(UUID, TEXT, DATE[]) TO service_role;
GRANT EXECUTE ON PROCEDURE analytics.run_analytics_watermark_sweep(INTEGER)             TO service_role;
GRANT EXECUTE ON PROCEDURE analytics.compute_double_review_trust_state(UUID, TEXT, DATE[]) TO service_role;

-- ─────────────────────────────────────────────────────────────
-- Verification helper: confirm no COMMIT/ROLLBACK in procedures
-- Run this after applying the migration to validate:
--   SELECT routine_definition
--   FROM information_schema.routines
--   WHERE routine_schema = 'analytics'
--     AND routine_name IN (
--       'run_analytics_watermark_sweep',
--       'orchestrate_incremental_refresh',
--       'compute_double_review_trust_state'
--     );
-- The output must NOT contain the word COMMIT or ROLLBACK.
-- ─────────────────────────────────────────────────────────────
