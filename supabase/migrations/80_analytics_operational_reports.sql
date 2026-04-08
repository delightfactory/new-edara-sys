-- ============================================================
-- 80_analytics_operational_reports.sql
-- Wave 2: Operational & Strategic Reports
--
-- ADDITIVE ONLY:
--   • 3 new analytics tables
--   • 3 new refresh procedures
--   • CREATE OR REPLACE orchestrate_incremental_refresh (adds 3 ELSIFs)
--   • CREATE OR REPLACE run_analytics_watermark_sweep   (adds 3 run_ids)
--   • CREATE OR REPLACE run_historical_backfill          (adds 3 CALLs)
--   • 10 new public RPC functions
--
-- PREREQUISITES (must already be deployed):
--   75_analytics_schema_wave1.sql
--   76_analytics_incremental_jobs.sql
--   77_analytics_public_rpc_layer.sql
--   78_analytics_transaction_safety_fix.sql   ← defines orchestrate/sweep
--   79_analytics_performance_and_backfill.sql ← defines run_historical_backfill
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. snapshot_customer_risk
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS analytics.snapshot_customer_risk (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  as_of_date     date NOT NULL,
  customer_id    uuid NOT NULL,

  -- RFM inputs (copied from snapshot_customer_health)
  recency_days   integer,
  frequency_l90d integer NOT NULL DEFAULT 0,
  monetary_l90d  numeric NOT NULL DEFAULT 0,

  -- Computed scoring
  r_score        integer NOT NULL DEFAULT 0,   -- 0–333
  f_score        integer NOT NULL DEFAULT 0,   -- 0–333
  m_score        integer NOT NULL DEFAULT 0,   -- 0–333
  rfm_score      integer NOT NULL DEFAULT 0,   -- 0–999

  -- Risk classification
  risk_label     text NOT NULL
                 CHECK (risk_label IN ('VIP','LOYAL','ENGAGED','AT_RISK','DORMANT')),

  created_at     timestamptz DEFAULT now(),
  updated_at     timestamptz DEFAULT now(),

  CONSTRAINT snapshot_cust_risk_unique UNIQUE (as_of_date, customer_id)
);

CREATE INDEX IF NOT EXISTS idx_snap_cust_risk_date_cust
  ON analytics.snapshot_customer_risk (as_of_date, customer_id);
CREATE INDEX IF NOT EXISTS idx_snap_cust_risk_date_label
  ON analytics.snapshot_customer_risk (as_of_date, risk_label);

GRANT SELECT ON analytics.snapshot_customer_risk TO authenticated;
GRANT ALL    ON analytics.snapshot_customer_risk TO service_role;

-- ─────────────────────────────────────────────────────────────
-- 2. snapshot_target_attainment
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS analytics.snapshot_target_attainment (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  as_of_date      date NOT NULL,
  target_id       uuid NOT NULL,

  -- Target metadata (denormalized)
  target_name     text,
  type_code       text,
  scope           text,
  period_start    date,
  period_end      date,
  target_value    numeric,

  -- Rep info (NULL when scope != 'individual')
  rep_id          uuid,   -- profiles.id (NOT hr_employees.id)
  rep_name        text,
  branch_id       uuid,
  branch_name     text,

  -- Progress (from target_progress)
  achieved_value  numeric,
  achievement_pct numeric,
  trend           text,   -- 'on_track' | 'at_risk' | 'behind' | 'achieved' | 'exceeded'

  created_at      timestamptz DEFAULT now(),
  updated_at      timestamptz DEFAULT now(),

  CONSTRAINT snapshot_target_attain_unique UNIQUE (as_of_date, target_id)
);

CREATE INDEX IF NOT EXISTS idx_snap_target_date_rep
  ON analytics.snapshot_target_attainment (as_of_date, rep_id);
CREATE INDEX IF NOT EXISTS idx_snap_target_date_trend
  ON analytics.snapshot_target_attainment (as_of_date, trend);

GRANT SELECT ON analytics.snapshot_target_attainment TO authenticated;
GRANT ALL    ON analytics.snapshot_target_attainment TO service_role;

-- ─────────────────────────────────────────────────────────────
-- 3. fact_geography_daily
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS analytics.fact_geography_daily (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  date               date NOT NULL,

  -- Geo dimensions (lowest = area; NULLable when customer.area_id IS NULL)
  area_id            uuid,
  city_id            uuid,
  governorate_id     uuid,

  -- Metrics (from fact_sales_daily_grain JOIN customers)
  net_revenue        numeric NOT NULL DEFAULT 0,
  return_value       numeric NOT NULL DEFAULT 0,
  tax_amount         numeric NOT NULL DEFAULT 0,
  gross_revenue      numeric NOT NULL DEFAULT 0,
  customer_count     integer NOT NULL DEFAULT 0,
  transaction_count  integer NOT NULL DEFAULT 0,

  created_at         timestamptz DEFAULT now(),
  updated_at         timestamptz DEFAULT now(),

  CONSTRAINT fact_geo_daily_unique UNIQUE (date, governorate_id, city_id, area_id)
);

CREATE INDEX IF NOT EXISTS idx_fact_geo_date
  ON analytics.fact_geography_daily (date);
CREATE INDEX IF NOT EXISTS idx_fact_geo_gov_date
  ON analytics.fact_geography_daily (governorate_id, date);
CREATE INDEX IF NOT EXISTS idx_fact_geo_city_date
  ON analytics.fact_geography_daily (city_id, date);
CREATE INDEX IF NOT EXISTS idx_fact_geo_area_date
  ON analytics.fact_geography_daily (area_id, date);

GRANT SELECT ON analytics.fact_geography_daily TO authenticated;
GRANT ALL    ON analytics.fact_geography_daily TO service_role;

-- ─────────────────────────────────────────────────────────────
-- 4. RLS Policies
-- ─────────────────────────────────────────────────────────────

-- snapshot_customer_risk
ALTER TABLE analytics.snapshot_customer_risk ENABLE ROW LEVEL SECURITY;

CREATE POLICY snap_cust_risk_read ON analytics.snapshot_customer_risk
  FOR SELECT TO authenticated
  USING (
    check_permission(auth.uid(), 'reports.view_all')
    OR check_permission(auth.uid(), 'reports.sales')
  );

-- snapshot_target_attainment
ALTER TABLE analytics.snapshot_target_attainment ENABLE ROW LEVEL SECURITY;

CREATE POLICY snap_target_attain_read ON analytics.snapshot_target_attainment
  FOR SELECT TO authenticated
  USING (
    check_permission(auth.uid(), 'reports.view_all')
    OR check_permission(auth.uid(), 'reports.targets')
    OR (
      check_permission(auth.uid(), 'reports.sales')
      AND (rep_id = auth.uid() OR rep_id IS NULL)
    )
  );

-- fact_geography_daily
ALTER TABLE analytics.fact_geography_daily ENABLE ROW LEVEL SECURITY;

CREATE POLICY fact_geo_daily_read ON analytics.fact_geography_daily
  FOR SELECT TO authenticated
  USING (
    check_permission(auth.uid(), 'reports.view_all')
    OR check_permission(auth.uid(), 'reports.sales')
  );

-- ─────────────────────────────────────────────────────────────
-- 5. Refresh Procedure: snapshot_customer_risk
-- ─────────────────────────────────────────────────────────────
-- RFM Scoring:
--   R: NULL→1, =0→333, ≤30→280, ≤60→180, ≤90→90, >90→1
--   F: =0→1, ≥10→333, ≥5→250, ≥3→180, ≥2→120, =1→50
--   M: =0→1, ≥50000→333, ≥20000→250, ≥10000→180, ≥3000→100, >0→50
--   rfm_score = r + f + m (0–999)
-- Risk Label:
--   rfm≥800 AND monetary≥10000 → VIP
--   rfm≥550                   → LOYAL
--   recency>90 OR recency NULL → DORMANT
--   rfm≥300 AND recency>45    → AT_RISK
--   else                       → ENGAGED
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE analytics.internal_refresh_snapshot_customer_risk(
  p_target_dates DATE[]
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF array_length(p_target_dates, 1) IS NULL THEN RETURN; END IF;

  DELETE FROM analytics.snapshot_customer_risk
  WHERE as_of_date = ANY(p_target_dates);

  WITH scored AS (
    SELECT
      sh.as_of_date,
      sh.customer_id,
      sh.recency_days,
      sh.frequency_l90d,
      sh.monetary_l90d,
      CASE
        WHEN sh.recency_days IS NULL  THEN 1
        WHEN sh.recency_days = 0      THEN 333
        WHEN sh.recency_days <= 30    THEN 280
        WHEN sh.recency_days <= 60    THEN 180
        WHEN sh.recency_days <= 90    THEN 90
        ELSE 1
      END AS r_score,
      CASE
        WHEN sh.frequency_l90d = 0   THEN 1
        WHEN sh.frequency_l90d >= 10 THEN 333
        WHEN sh.frequency_l90d >= 5  THEN 250
        WHEN sh.frequency_l90d >= 3  THEN 180
        WHEN sh.frequency_l90d >= 2  THEN 120
        ELSE 50
      END AS f_score,
      CASE
        WHEN COALESCE(sh.monetary_l90d, 0) = 0     THEN 1
        WHEN sh.monetary_l90d >= 50000              THEN 333
        WHEN sh.monetary_l90d >= 20000              THEN 250
        WHEN sh.monetary_l90d >= 10000              THEN 180
        WHEN sh.monetary_l90d >= 3000               THEN 100
        ELSE 50
      END AS m_score
    FROM analytics.snapshot_customer_health sh
    WHERE sh.as_of_date = ANY(p_target_dates)
  ),
  labeled AS (
    SELECT
      as_of_date,
      customer_id,
      recency_days,
      frequency_l90d,
      monetary_l90d,
      r_score,
      f_score,
      m_score,
      (r_score + f_score + m_score) AS rfm_score,
      CASE
        WHEN (r_score + f_score + m_score) >= 800
             AND COALESCE(monetary_l90d, 0) >= 10000 THEN 'VIP'
        WHEN (r_score + f_score + m_score) >= 550    THEN 'LOYAL'
        WHEN recency_days > 90 OR recency_days IS NULL THEN 'DORMANT'
        WHEN (r_score + f_score + m_score) >= 300
             AND recency_days > 45                   THEN 'AT_RISK'
        ELSE 'ENGAGED'
      END AS risk_label
    FROM scored
  )
  INSERT INTO analytics.snapshot_customer_risk
    (as_of_date, customer_id, recency_days, frequency_l90d, monetary_l90d,
     r_score, f_score, m_score, rfm_score, risk_label)
  SELECT
    as_of_date, customer_id, recency_days, frequency_l90d, monetary_l90d,
    r_score, f_score, m_score, rfm_score, risk_label
  FROM labeled
  ON CONFLICT (as_of_date, customer_id) DO UPDATE SET
    recency_days   = EXCLUDED.recency_days,
    frequency_l90d = EXCLUDED.frequency_l90d,
    monetary_l90d  = EXCLUDED.monetary_l90d,
    r_score        = EXCLUDED.r_score,
    f_score        = EXCLUDED.f_score,
    m_score        = EXCLUDED.m_score,
    rfm_score      = EXCLUDED.rfm_score,
    risk_label     = EXCLUDED.risk_label,
    updated_at     = now();
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 6. Refresh Procedure: snapshot_target_attainment
-- ─────────────────────────────────────────────────────────────
-- Reads from target_progress (populated by triggers in 22e).
-- Does NOT recalculate actuals — trusts target_progress.
-- Bridge: targets.scope_id = hr_employees.id
--         hr_employees.user_id = profiles.id  →  rep_id = profiles.id
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE analytics.internal_refresh_snapshot_target_attainment(
  p_target_dates DATE[]
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF array_length(p_target_dates, 1) IS NULL THEN RETURN; END IF;

  DELETE FROM analytics.snapshot_target_attainment
  WHERE as_of_date = ANY(p_target_dates);

  INSERT INTO analytics.snapshot_target_attainment
    (as_of_date, target_id, target_name, type_code, scope,
     period_start, period_end, target_value,
     rep_id, rep_name, branch_id, branch_name,
     achieved_value, achievement_pct, trend)
  SELECT
    tp.snapshot_date              AS as_of_date,
    t.id                          AS target_id,
    t.name                        AS target_name,
    t.type_code,
    t.scope,
    t.period_start,
    t.period_end,
    t.target_value,
    he.user_id                    AS rep_id,
    p.full_name                   AS rep_name,
    he.branch_id,
    b.name                        AS branch_name,
    tp.achieved_value,
    tp.achievement_pct,
    tp.trend
  FROM public.target_progress tp
  JOIN public.targets t ON t.id = tp.target_id
  LEFT JOIN public.hr_employees he
    ON t.scope = 'individual' AND he.id = t.scope_id
  LEFT JOIN public.profiles p    ON p.id  = he.user_id
  LEFT JOIN public.branches b    ON b.id  = he.branch_id
  WHERE tp.snapshot_date = ANY(p_target_dates)
    AND t.is_active = true
    AND t.is_paused = false
  ON CONFLICT (as_of_date, target_id) DO UPDATE SET
    target_name     = EXCLUDED.target_name,
    type_code       = EXCLUDED.type_code,
    scope           = EXCLUDED.scope,
    target_value    = EXCLUDED.target_value,
    rep_id          = EXCLUDED.rep_id,
    rep_name        = EXCLUDED.rep_name,
    branch_id       = EXCLUDED.branch_id,
    branch_name     = EXCLUDED.branch_name,
    achieved_value  = EXCLUDED.achieved_value,
    achievement_pct = EXCLUDED.achievement_pct,
    trend           = EXCLUDED.trend,
    updated_at      = now();
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 7. Refresh Procedure: fact_geography_daily
-- ─────────────────────────────────────────────────────────────
-- Aggregates fact_sales_daily_grain × customers geo dimensions.
-- Customers with NULL area_id → area_id = NULL (row still inserted).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE analytics.internal_refresh_fact_geography_daily(
  p_target_dates DATE[]
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF array_length(p_target_dates, 1) IS NULL THEN RETURN; END IF;

  DELETE FROM analytics.fact_geography_daily
  WHERE date = ANY(p_target_dates);

  INSERT INTO analytics.fact_geography_daily
    (date, area_id, city_id, governorate_id,
     net_revenue, return_value, tax_amount, gross_revenue,
     customer_count, transaction_count)
  SELECT
    f.date,
    c.area_id,
    c.city_id,
    c.governorate_id,
    SUM(f.net_tax_exclusive_revenue)    AS net_revenue,
    SUM(f.return_tax_exclusive_amount)  AS return_value,
    SUM(f.tax_amount)                   AS tax_amount,
    SUM(f.tax_inclusive_amount)         AS gross_revenue,
    COUNT(DISTINCT f.customer_id)       AS customer_count,
    COUNT(*)                            AS transaction_count
  FROM analytics.fact_sales_daily_grain f
  JOIN public.customers c ON c.id = f.customer_id
  WHERE f.date = ANY(p_target_dates)
  GROUP BY f.date, c.area_id, c.city_id, c.governorate_id
  ON CONFLICT (date, governorate_id, city_id, area_id) DO UPDATE SET
    net_revenue       = EXCLUDED.net_revenue,
    return_value      = EXCLUDED.return_value,
    tax_amount        = EXCLUDED.tax_amount,
    gross_revenue     = EXCLUDED.gross_revenue,
    customer_count    = EXCLUDED.customer_count,
    transaction_count = EXCLUDED.transaction_count,
    updated_at        = now();
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 8. UPDATE orchestrate_incremental_refresh — add 3 ELSIFs
--    (exact copy of migration 78 + 3 new branches)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE analytics.orchestrate_incremental_refresh(
  p_run_id       UUID,
  p_job_name     TEXT,
  p_target_dates DATE[]
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO analytics.etl_runs (id, table_name, status, started_at)
  VALUES (p_run_id, p_job_name, 'RUNNING', now())
  ON CONFLICT (id) DO UPDATE SET status = 'RUNNING', started_at = now();

  BEGIN
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
    -- ── Wave 2 ────────────────────────────────────────────────
    ELSIF p_job_name = 'snapshot_customer_risk' THEN
      CALL analytics.internal_refresh_snapshot_customer_risk(p_target_dates);
    ELSIF p_job_name = 'snapshot_target_attainment' THEN
      CALL analytics.internal_refresh_snapshot_target_attainment(p_target_dates);
    ELSIF p_job_name = 'fact_geography_daily' THEN
      CALL analytics.internal_refresh_fact_geography_daily(p_target_dates);
    -- ─────────────────────────────────────────────────────────
    ELSE
      RAISE EXCEPTION 'Unknown job: %', p_job_name;
    END IF;

    UPDATE analytics.etl_runs
    SET status = 'SUCCESS', completed_at = now()
    WHERE id = p_run_id;

    CALL analytics.compute_double_review_trust_state(p_run_id, p_job_name, p_target_dates);

  EXCEPTION WHEN OTHERS THEN
    UPDATE analytics.etl_runs
    SET status       = 'FAILED',
        completed_at = now(),
        log_output   = jsonb_build_object(
          'error', SQLERRM, 'state', SQLSTATE, 'dates', p_target_dates::text
        )
    WHERE id = p_run_id;
  END;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 9. UPDATE run_analytics_watermark_sweep — add 3 run_ids + 3 CALLs
--    (exact copy of migration 78 + 3 new run_ids + 3 new CALLs)
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
  -- Wave 2
  v_run_id_6        UUID := gen_random_uuid();
  v_run_id_7        UUID := gen_random_uuid();
  v_run_id_8        UUID := gen_random_uuid();
BEGIN
  SELECT pg_try_advisory_lock(hashtext('analytics_global_sweep')) INTO v_lock_obtained;
  IF NOT v_lock_obtained THEN
    RAISE NOTICE 'Analytics sweep locked elsewhere — exiting.';
    RETURN;
  END IF;

  BEGIN
    SELECT COALESCE(
      MAX(started_at),
      now() - (p_fallback_days || ' days')::interval
    )
    INTO v_watermark
    FROM analytics.etl_runs
    WHERE table_name = 'GLOBAL_SWEEP'
      AND status IN ('SUCCESS', 'POSTING_CONSISTENCY_ONLY', 'VERIFIED', 'RECONCILED_WITH_WARNING');

    INSERT INTO analytics.etl_runs (id, table_name, status, started_at)
    VALUES (v_sweep_id, 'GLOBAL_SWEEP', 'RUNNING', v_sweep_start);

    SELECT analytics.detect_affected_dates(v_watermark) INTO v_target_dates;

    IF array_length(v_target_dates, 1) IS NOT NULL THEN
      -- Wave 1: existing jobs
      CALL analytics.orchestrate_incremental_refresh(v_run_id_1, 'fact_sales_daily_grain',                             v_target_dates);
      CALL analytics.orchestrate_incremental_refresh(v_run_id_2, 'fact_financial_ledgers_daily',                       v_target_dates);
      CALL analytics.orchestrate_incremental_refresh(v_run_id_3, 'fact_treasury_cashflow_daily',                       v_target_dates);
      CALL analytics.orchestrate_incremental_refresh(v_run_id_4, 'fact_ar_collections_attributed_to_origin_sale_date', v_target_dates);
      CALL analytics.orchestrate_incremental_refresh(v_run_id_5, 'snapshot_customer_health',                           v_target_dates);
      -- Wave 2: depends on Wave 1 (snapshot_customer_risk needs snapshot_customer_health)
      CALL analytics.orchestrate_incremental_refresh(v_run_id_6, 'snapshot_customer_risk',     v_target_dates);
      CALL analytics.orchestrate_incremental_refresh(v_run_id_7, 'snapshot_target_attainment', v_target_dates);
      CALL analytics.orchestrate_incremental_refresh(v_run_id_8, 'fact_geography_daily',        v_target_dates);
    END IF;

    SELECT COUNT(*) INTO v_failed_subjobs
    FROM analytics.etl_runs
    WHERE id IN (v_run_id_1, v_run_id_2, v_run_id_3, v_run_id_4, v_run_id_5,
                 v_run_id_6, v_run_id_7, v_run_id_8)
      AND status IN ('FAILED', 'BLOCKED');

    IF v_failed_subjobs > 0 THEN
      UPDATE analytics.etl_runs SET status = 'PARTIAL_FAILURE', completed_at = now() WHERE id = v_sweep_id;
    ELSE
      UPDATE analytics.etl_runs SET status = 'SUCCESS',          completed_at = now() WHERE id = v_sweep_id;
    END IF;

    PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));

  EXCEPTION WHEN OTHERS THEN
    UPDATE analytics.etl_runs
    SET status      = 'FAILED',
        completed_at = now(),
        log_output   = jsonb_build_object('error', SQLERRM, 'state', SQLSTATE)
    WHERE id = v_sweep_id;
    PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));
    RAISE;
  END;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 10. UPDATE run_historical_backfill — add 3 CALLs inside loop
--     (exact copy of migration 79 + 3 new CALLs)
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

  SELECT pg_try_advisory_lock(hashtext('analytics_global_sweep')) INTO v_lock_obtained;
  IF NOT v_lock_obtained THEN
    RAISE EXCEPTION 'Analytics sweep is running elsewhere. Backfill cannot start.';
  END IF;

  BEGIN
    v_chunk_start := p_start_date;

    WHILE v_chunk_start <= p_end_date LOOP
      v_chunk_end := LEAST(v_chunk_start + (p_chunk_days - 1), p_end_date);

      SELECT array_agg(d::date)
      INTO   v_chunk_dates
      FROM   generate_series(v_chunk_start, v_chunk_end, '1 day'::interval) d;

      RAISE NOTICE 'Backfill: chunk % — dates % to % (%  dates)',
        v_chunks_done + 1, v_chunk_start, v_chunk_end, array_length(v_chunk_dates, 1);

      -- Wave 1 jobs
      CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_sales_daily_grain',                             v_chunk_dates);
      CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_financial_ledgers_daily',                       v_chunk_dates);
      CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_treasury_cashflow_daily',                       v_chunk_dates);
      CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_ar_collections_attributed_to_origin_sale_date', v_chunk_dates);
      CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'snapshot_customer_health',                           v_chunk_dates);
      -- Wave 2 jobs (snapshot_customer_risk depends on snapshot_customer_health)
      CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'snapshot_customer_risk',     v_chunk_dates);
      CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'snapshot_target_attainment', v_chunk_dates);
      CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_geography_daily',        v_chunk_dates);

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

-- ─────────────────────────────────────────────────────────────
-- 11. Grants for new procedures
-- ─────────────────────────────────────────────────────────────
GRANT EXECUTE ON PROCEDURE analytics.internal_refresh_snapshot_customer_risk(DATE[])     TO service_role;
GRANT EXECUTE ON PROCEDURE analytics.internal_refresh_snapshot_target_attainment(DATE[]) TO service_role;
GRANT EXECUTE ON PROCEDURE analytics.internal_refresh_fact_geography_daily(DATE[])       TO service_role;

REVOKE ALL ON PROCEDURE analytics.orchestrate_incremental_refresh(UUID, TEXT, DATE[]) FROM public;
REVOKE ALL ON PROCEDURE analytics.run_analytics_watermark_sweep(INTEGER)              FROM public;
REVOKE ALL ON PROCEDURE analytics.run_historical_backfill(DATE, DATE, INTEGER)        FROM public;
GRANT EXECUTE ON PROCEDURE analytics.orchestrate_incremental_refresh(UUID, TEXT, DATE[]) TO service_role;
GRANT EXECUTE ON PROCEDURE analytics.run_analytics_watermark_sweep(INTEGER)              TO service_role;
GRANT EXECUTE ON PROCEDURE analytics.run_historical_backfill(DATE, DATE, INTEGER)        TO service_role;

-- ─────────────────────────────────────────────────────────────
-- 12. RPC-1: analytics_rep_performance_summary
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.analytics_rep_performance_summary(
  p_date_from date,
  p_date_to   date
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, analytics
AS $$
BEGIN
  IF NOT check_permission(auth.uid(), 'reports.sales')
     AND NOT check_permission(auth.uid(), 'reports.view_all') THEN
    RAISE EXCEPTION 'analytics_unauthorized:domain=sales';
  END IF;

  RETURN (
    SELECT jsonb_build_object(
      'total_reps',          COUNT(DISTINCT f.rep_id),
      'total_revenue',       COALESCE(SUM(f.net_tax_exclusive_revenue), 0),
      'total_returns_value', COALESCE(SUM(f.return_tax_exclusive_amount), 0),
      'avg_revenue_per_rep', COALESCE(
        SUM(f.net_tax_exclusive_revenue) / NULLIF(COUNT(DISTINCT f.rep_id), 0), 0
      )
    )
    FROM analytics.fact_sales_daily_grain f
    WHERE f.date BETWEEN p_date_from AND p_date_to
  );
EXCEPTION
  WHEN undefined_table THEN RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;
GRANT EXECUTE ON FUNCTION public.analytics_rep_performance_summary(date, date) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- 13. RPC-2: analytics_rep_performance_table
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.analytics_rep_performance_table(
  p_date_from date,
  p_date_to   date
)
RETURNS TABLE (
  rep_id             uuid,
  rep_name           text,
  branch_name        text,
  net_revenue        numeric,
  returns_value      numeric,
  return_rate_pct    numeric,
  net_qty            numeric,
  distinct_customers bigint,
  rank               bigint
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, analytics
AS $$
BEGIN
  IF NOT check_permission(auth.uid(), 'reports.sales')
     AND NOT check_permission(auth.uid(), 'reports.view_all') THEN
    RAISE EXCEPTION 'analytics_unauthorized:domain=sales';
  END IF;

  RETURN QUERY
  WITH agg AS (
    SELECT
      f.rep_id,
      COALESCE(SUM(f.net_tax_exclusive_revenue), 0)   AS net_rev,
      COALESCE(SUM(f.return_tax_exclusive_amount), 0) AS ret_val,
      COALESCE(SUM(f.net_quantity), 0)                AS net_q,
      COUNT(DISTINCT f.customer_id)                    AS dist_cust
    FROM analytics.fact_sales_daily_grain f
    WHERE f.date BETWEEN p_date_from AND p_date_to
    GROUP BY f.rep_id
  )
  SELECT
    a.rep_id,
    COALESCE(p.full_name, a.rep_id::text)              AS rep_name,
    COALESCE(b.name, '—')                              AS branch_name,
    a.net_rev,
    a.ret_val,
    ROUND(
      CASE WHEN a.net_rev + a.ret_val > 0
           THEN (a.ret_val / (a.net_rev + a.ret_val)) * 100
           ELSE 0 END,
      1
    )                                                   AS return_rate_pct,
    a.net_q,
    a.dist_cust,
    RANK() OVER (ORDER BY a.net_rev DESC)               AS rank
  FROM agg a
  LEFT JOIN public.profiles     p  ON p.id = a.rep_id
  LEFT JOIN public.hr_employees he ON he.user_id = a.rep_id
  LEFT JOIN public.branches     b  ON b.id = he.branch_id
  ORDER BY a.net_rev DESC;

EXCEPTION
  WHEN undefined_table THEN RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;
GRANT EXECUTE ON FUNCTION public.analytics_rep_performance_table(date, date) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- 14. RPC-3: analytics_product_performance_summary
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.analytics_product_performance_summary(
  p_date_from   date,
  p_date_to     date,
  p_category_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, analytics
AS $$
BEGIN
  IF NOT check_permission(auth.uid(), 'reports.sales')
     AND NOT check_permission(auth.uid(), 'reports.view_all') THEN
    RAISE EXCEPTION 'analytics_unauthorized:domain=sales';
  END IF;

  RETURN (
    SELECT jsonb_build_object(
      'total_products',      COUNT(DISTINCT f.product_id),
      'total_revenue',       COALESCE(SUM(f.net_tax_exclusive_revenue), 0),
      'top_product_revenue', COALESCE(MAX(sub.prod_rev), 0)
    )
    FROM analytics.fact_sales_daily_grain f
    LEFT JOIN public.products pr ON pr.id = f.product_id
    LEFT JOIN (
      SELECT product_id, SUM(net_tax_exclusive_revenue) AS prod_rev
      FROM analytics.fact_sales_daily_grain
      WHERE date BETWEEN p_date_from AND p_date_to
      GROUP BY product_id
    ) sub ON sub.product_id = f.product_id
    WHERE f.date BETWEEN p_date_from AND p_date_to
      AND (p_category_id IS NULL OR pr.category_id = p_category_id)
  );
EXCEPTION
  WHEN undefined_table THEN RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;
GRANT EXECUTE ON FUNCTION public.analytics_product_performance_summary(date, date, uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- 15. RPC-4: analytics_product_performance_table
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.analytics_product_performance_table(
  p_date_from   date,
  p_date_to     date,
  p_category_id uuid    DEFAULT NULL,
  p_limit       integer DEFAULT 50
)
RETURNS TABLE (
  product_id         uuid,
  product_name       text,
  category_name      text,
  net_revenue        numeric,
  net_qty            numeric,
  return_rate_pct    numeric,
  distinct_customers bigint,
  revenue_share_pct  numeric
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, analytics
AS $$
BEGIN
  IF NOT check_permission(auth.uid(), 'reports.sales')
     AND NOT check_permission(auth.uid(), 'reports.view_all') THEN
    RAISE EXCEPTION 'analytics_unauthorized:domain=sales';
  END IF;

  RETURN QUERY
  WITH total AS (
    SELECT NULLIF(SUM(net_tax_exclusive_revenue), 0) AS grand_total
    FROM analytics.fact_sales_daily_grain
    WHERE date BETWEEN p_date_from AND p_date_to
  ),
  agg AS (
    SELECT
      f.product_id,
      COALESCE(SUM(f.net_tax_exclusive_revenue), 0)   AS net_rev,
      COALESCE(SUM(f.return_tax_exclusive_amount), 0) AS ret_val,
      COALESCE(SUM(f.net_quantity), 0)                AS net_q,
      COUNT(DISTINCT f.customer_id)                    AS dist_cust
    FROM analytics.fact_sales_daily_grain f
    LEFT JOIN public.products pr ON pr.id = f.product_id
    WHERE f.date BETWEEN p_date_from AND p_date_to
      AND (p_category_id IS NULL OR pr.category_id = p_category_id)
    GROUP BY f.product_id
  )
  SELECT
    a.product_id,
    COALESCE(pr.name, a.product_id::text)                     AS product_name,
    COALESCE(pc.name, '—')                                    AS category_name,
    a.net_rev,
    a.net_q,
    ROUND(
      CASE WHEN a.net_rev + a.ret_val > 0
           THEN (a.ret_val / (a.net_rev + a.ret_val)) * 100
           ELSE 0 END, 1
    )                                                          AS return_rate_pct,
    a.dist_cust,
    ROUND(COALESCE((a.net_rev / t.grand_total) * 100, 0), 1) AS revenue_share_pct
  FROM agg a, total t
  LEFT JOIN public.products          pr ON pr.id = a.product_id
  LEFT JOIN public.product_categories pc ON pc.id = pr.category_id
  ORDER BY a.net_rev DESC
  LIMIT p_limit;

EXCEPTION
  WHEN undefined_table THEN RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;
GRANT EXECUTE ON FUNCTION public.analytics_product_performance_table(date, date, uuid, integer) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- 16. RPC-5: analytics_customer_risk_summary
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.analytics_customer_risk_summary(
  p_as_of_date date,
  p_risk_label text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, analytics
AS $$
BEGIN
  IF NOT check_permission(auth.uid(), 'reports.sales')
     AND NOT check_permission(auth.uid(), 'reports.view_all') THEN
    RAISE EXCEPTION 'analytics_unauthorized:domain=customers';
  END IF;

  RETURN (
    SELECT jsonb_build_object(
      'total',          COUNT(*),
      'vip',            COUNT(*) FILTER (WHERE risk_label = 'VIP'),
      'loyal',          COUNT(*) FILTER (WHERE risk_label = 'LOYAL'),
      'engaged',        COUNT(*) FILTER (WHERE risk_label = 'ENGAGED'),
      'at_risk',        COUNT(*) FILTER (WHERE risk_label = 'AT_RISK'),
      'dormant',        COUNT(*) FILTER (WHERE risk_label = 'DORMANT'),
      'avg_rfm_score',  ROUND(AVG(rfm_score)::numeric, 0)
    )
    FROM analytics.snapshot_customer_risk
    WHERE as_of_date = p_as_of_date
      AND (p_risk_label IS NULL OR risk_label = p_risk_label)
  );
EXCEPTION
  WHEN undefined_table THEN RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;
GRANT EXECUTE ON FUNCTION public.analytics_customer_risk_summary(date, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- 17. RPC-6: analytics_customer_risk_list
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.analytics_customer_risk_list(
  p_as_of_date date,
  p_risk_label text    DEFAULT NULL,
  p_rep_id     uuid    DEFAULT NULL,
  p_limit      integer DEFAULT 50
)
RETURNS TABLE (
  customer_id    uuid,
  customer_name  text,
  risk_label     text,
  rfm_score      integer,
  recency_days   integer,
  frequency_l90d integer,
  monetary_l90d  numeric
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, analytics
AS $$
BEGIN
  IF NOT check_permission(auth.uid(), 'reports.sales')
     AND NOT check_permission(auth.uid(), 'reports.view_all') THEN
    RAISE EXCEPTION 'analytics_unauthorized:domain=customers';
  END IF;

  RETURN QUERY
  SELECT
    cr.customer_id,
    COALESCE(c.name, cr.customer_id::text) AS customer_name,
    cr.risk_label,
    cr.rfm_score,
    cr.recency_days,
    cr.frequency_l90d,
    cr.monetary_l90d
  FROM analytics.snapshot_customer_risk cr
  LEFT JOIN public.customers c ON c.id = cr.customer_id
  WHERE cr.as_of_date = p_as_of_date
    AND (p_risk_label IS NULL OR cr.risk_label = p_risk_label)
    AND (p_rep_id     IS NULL OR c.assigned_rep_id = p_rep_id)
  ORDER BY
    CASE cr.risk_label
      WHEN 'AT_RISK'  THEN 1
      WHEN 'DORMANT'  THEN 2
      WHEN 'VIP'      THEN 3
      WHEN 'LOYAL'    THEN 4
      ELSE 5
    END,
    cr.rfm_score DESC
  LIMIT p_limit;

EXCEPTION
  WHEN undefined_table THEN RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;
GRANT EXECUTE ON FUNCTION public.analytics_customer_risk_list(date, text, uuid, integer) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- 18. RPC-7: analytics_geography_summary
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.analytics_geography_summary(
  p_date_from date,
  p_date_to   date,
  p_level     text DEFAULT 'governorate'
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, analytics
AS $$
BEGIN
  IF NOT check_permission(auth.uid(), 'reports.sales')
     AND NOT check_permission(auth.uid(), 'reports.view_all') THEN
    RAISE EXCEPTION 'analytics_unauthorized:domain=sales';
  END IF;

  RETURN (
    SELECT jsonb_build_object(
      'total_revenue',  COALESCE(SUM(net_revenue), 0),
      'covered_areas',  COUNT(DISTINCT
        CASE p_level
          WHEN 'area' THEN area_id::text
          WHEN 'city' THEN city_id::text
          ELSE             governorate_id::text
        END
      ),
      'zero_revenue_areas', 0
    )
    FROM analytics.fact_geography_daily
    WHERE date BETWEEN p_date_from AND p_date_to
  );
EXCEPTION
  WHEN undefined_table THEN RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;
GRANT EXECUTE ON FUNCTION public.analytics_geography_summary(date, date, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- 19. RPC-8: analytics_geography_table
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.analytics_geography_table(
  p_date_from date,
  p_date_to   date,
  p_level     text DEFAULT 'governorate'
)
RETURNS TABLE (
  geo_id            uuid,
  geo_name          text,
  parent_name       text,
  net_revenue       numeric,
  customer_count    bigint,
  transaction_count bigint,
  revenue_share_pct numeric
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, analytics
AS $$
DECLARE
  v_grand_total numeric;
BEGIN
  IF NOT check_permission(auth.uid(), 'reports.sales')
     AND NOT check_permission(auth.uid(), 'reports.view_all') THEN
    RAISE EXCEPTION 'analytics_unauthorized:domain=sales';
  END IF;

  SELECT NULLIF(SUM(net_revenue), 0)
  INTO   v_grand_total
  FROM   analytics.fact_geography_daily
  WHERE  date BETWEEN p_date_from AND p_date_to;

  IF p_level = 'area' THEN
    RETURN QUERY
    SELECT
      fg.area_id                                                           AS geo_id,
      COALESCE(ar.name, fg.area_id::text)                                 AS geo_name,
      ci.name                                                              AS parent_name,
      COALESCE(SUM(fg.net_revenue), 0)                                    AS net_revenue,
      COALESCE(SUM(fg.customer_count), 0)::bigint                         AS customer_count,
      COALESCE(SUM(fg.transaction_count), 0)::bigint                      AS transaction_count,
      ROUND(COALESCE((SUM(fg.net_revenue) / v_grand_total) * 100, 0), 1) AS revenue_share_pct
    FROM analytics.fact_geography_daily fg
    LEFT JOIN public.areas  ar ON ar.id = fg.area_id
    LEFT JOIN public.cities ci ON ci.id = ar.city_id
    WHERE fg.date BETWEEN p_date_from AND p_date_to
    GROUP BY fg.area_id, ar.name, ci.name
    ORDER BY net_revenue DESC;

  ELSIF p_level = 'city' THEN
    RETURN QUERY
    SELECT
      fg.city_id                                                           AS geo_id,
      COALESCE(ci.name, fg.city_id::text)                                 AS geo_name,
      go.name                                                              AS parent_name,
      COALESCE(SUM(fg.net_revenue), 0)                                    AS net_revenue,
      COALESCE(SUM(fg.customer_count), 0)::bigint                         AS customer_count,
      COALESCE(SUM(fg.transaction_count), 0)::bigint                      AS transaction_count,
      ROUND(COALESCE((SUM(fg.net_revenue) / v_grand_total) * 100, 0), 1) AS revenue_share_pct
    FROM analytics.fact_geography_daily fg
    LEFT JOIN public.cities       ci ON ci.id = fg.city_id
    LEFT JOIN public.governorates go ON go.id = ci.governorate_id
    WHERE fg.date BETWEEN p_date_from AND p_date_to
    GROUP BY fg.city_id, ci.name, go.name
    ORDER BY net_revenue DESC;

  ELSE
    -- Default: governorate
    RETURN QUERY
    SELECT
      fg.governorate_id                                                    AS geo_id,
      COALESCE(go.name, fg.governorate_id::text)                          AS geo_name,
      NULL::text                                                           AS parent_name,
      COALESCE(SUM(fg.net_revenue), 0)                                    AS net_revenue,
      COALESCE(SUM(fg.customer_count), 0)::bigint                         AS customer_count,
      COALESCE(SUM(fg.transaction_count), 0)::bigint                      AS transaction_count,
      ROUND(COALESCE((SUM(fg.net_revenue) / v_grand_total) * 100, 0), 1) AS revenue_share_pct
    FROM analytics.fact_geography_daily fg
    LEFT JOIN public.governorates go ON go.id = fg.governorate_id
    WHERE fg.date BETWEEN p_date_from AND p_date_to
    GROUP BY fg.governorate_id, go.name
    ORDER BY net_revenue DESC;
  END IF;

EXCEPTION
  WHEN undefined_table THEN RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;
GRANT EXECUTE ON FUNCTION public.analytics_geography_table(date, date, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- 20. RPC-9: analytics_target_attainment_summary
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.analytics_target_attainment_summary(
  p_as_of_date date
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, analytics
AS $$
BEGIN
  IF NOT check_permission(auth.uid(), 'reports.targets')
     AND NOT check_permission(auth.uid(), 'reports.view_all') THEN
    RAISE EXCEPTION 'analytics_unauthorized:domain=targets';
  END IF;

  RETURN (
    SELECT jsonb_build_object(
      'total_targets',      COUNT(*),
      'achieved',           COUNT(*) FILTER (WHERE trend IN ('achieved', 'exceeded')),
      'on_track',           COUNT(*) FILTER (WHERE trend = 'on_track'),
      'at_risk',            COUNT(*) FILTER (WHERE trend = 'at_risk'),
      'behind',             COUNT(*) FILTER (WHERE trend = 'behind'),
      'avg_achievement_pct', ROUND(AVG(achievement_pct)::numeric, 1)
    )
    FROM analytics.snapshot_target_attainment
    WHERE as_of_date = p_as_of_date
  );
EXCEPTION
  WHEN undefined_table THEN RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;
GRANT EXECUTE ON FUNCTION public.analytics_target_attainment_summary(date) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- 21. RPC-10: analytics_target_attainment_table
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.analytics_target_attainment_table(
  p_as_of_date date,
  p_scope      text DEFAULT NULL
)
RETURNS TABLE (
  target_id       uuid,
  target_name     text,
  type_code       text,
  scope           text,
  rep_name        text,
  branch_name     text,
  period_start    date,
  period_end      date,
  target_value    numeric,
  achieved_value  numeric,
  achievement_pct numeric,
  trend           text
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, analytics
AS $$
BEGIN
  IF NOT check_permission(auth.uid(), 'reports.targets')
     AND NOT check_permission(auth.uid(), 'reports.view_all') THEN
    RAISE EXCEPTION 'analytics_unauthorized:domain=targets';
  END IF;

  RETURN QUERY
  SELECT
    sta.target_id,
    sta.target_name,
    sta.type_code,
    sta.scope,
    sta.rep_name,
    sta.branch_name,
    sta.period_start,
    sta.period_end,
    sta.target_value,
    sta.achieved_value,
    sta.achievement_pct,
    sta.trend
  FROM analytics.snapshot_target_attainment sta
  WHERE sta.as_of_date = p_as_of_date
    AND (p_scope IS NULL OR sta.scope = p_scope)
  ORDER BY sta.achievement_pct DESC;

EXCEPTION
  WHEN undefined_table THEN RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;
GRANT EXECUTE ON FUNCTION public.analytics_target_attainment_table(date, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- Verification (run after applying migration):
--
-- SELECT public.analytics_ping();
-- SELECT component_name, status FROM public.analytics_get_trust_state('all')
--   WHERE component_name IN ('snapshot_customer_risk','snapshot_target_attainment','fact_geography_daily');
-- CALL analytics.run_analytics_watermark_sweep(7);
-- SELECT COUNT(*) FROM analytics.snapshot_customer_risk;
-- SELECT COUNT(*) FROM analytics.snapshot_target_attainment;
-- SELECT COUNT(*) FROM analytics.fact_geography_daily;
-- SELECT public.analytics_rep_performance_summary('2025-01-01', '2025-04-07');
-- SELECT public.analytics_product_performance_summary('2025-01-01', '2025-04-07', NULL);
-- SELECT public.analytics_customer_risk_summary(CURRENT_DATE, NULL);
-- SELECT public.analytics_geography_summary('2025-01-01', '2025-04-07', 'governorate');
-- SELECT public.analytics_target_attainment_summary(CURRENT_DATE);
-- ─────────────────────────────────────────────────────────────
