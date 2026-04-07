-- ============================================================
-- 75_analytics_schema_wave1.sql
-- Description: Core Reporting & Analytics Schema for EDARA
-- Scope: Wave 1 (Dimensions, Facts, Snapshots, RLS, and Security Fixes)
-- ============================================================

-- ------------------------------------------------------------
-- 1. Security & Schema Foundation
-- ------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS analytics;

-- Block unauthorized public access by default
REVOKE ALL ON SCHEMA analytics FROM PUBLIC;

-- Explicitly allow authenticated connections and the internal service role
GRANT USAGE ON SCHEMA analytics TO authenticated;
GRANT ALL ON SCHEMA analytics TO service_role;

-- FIX: Close the operational reconciliation views previously left exposed to 'authenticated'
REVOKE SELECT ON public.v_reconcile_customer_balances FROM authenticated;
REVOKE SELECT ON public.v_reconcile_supplier_balances FROM authenticated;
REVOKE SELECT ON public.v_reconcile_vault_balances FROM authenticated;
REVOKE SELECT ON public.v_reconcile_ar_control_account FROM authenticated;
REVOKE SELECT ON public.v_reconcile_ap_control_account FROM authenticated;
REVOKE SELECT ON public.v_reconcile_treasury_control_accounts FROM authenticated;
REVOKE SELECT ON public.v_documents_missing_journal_entries FROM authenticated;

-- Instead, grant access strictly to service_role. 
-- The UI will interact via secure definer functions testing `check_permission(uid, 'reports.financial')` or similar.
GRANT SELECT ON public.v_reconcile_customer_balances TO service_role;
GRANT SELECT ON public.v_reconcile_supplier_balances TO service_role;
GRANT SELECT ON public.v_reconcile_vault_balances TO service_role;
GRANT SELECT ON public.v_reconcile_ar_control_account TO service_role;
GRANT SELECT ON public.v_reconcile_ap_control_account TO service_role;
GRANT SELECT ON public.v_reconcile_treasury_control_accounts TO service_role;
GRANT SELECT ON public.v_documents_missing_journal_entries TO service_role;


-- ------------------------------------------------------------
-- 2. Metadata Tracking
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS analytics.etl_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  table_name text NOT NULL,
  started_at timestamptz DEFAULT now(),
  completed_at timestamptz,
  records_processed integer DEFAULT 0,
  drift_value numeric,
  status text NOT NULL CHECK (status IN ('RUNNING', 'SUCCESS', 'FAILED', 'VERIFIED', 'BLOCKED', 'POSTING_CONSISTENCY_ONLY', 'RECONCILED_WITH_WARNING', 'PARTIAL_FAILURE')),
  metric_states jsonb,
  log_output jsonb
);

-- Removed SELECT on analytics.etl_runs for authenticated (P1 Fix)
-- Only the service_role executing the cron job can query/insert/update runs.
GRANT ALL ON analytics.etl_runs TO service_role;

-- Secure View Path for Frontend to monitor status (Extracts granular metric states)
CREATE OR REPLACE FUNCTION analytics.get_system_trust_state()
RETURNS TABLE (
  component_name text,
  status text,
  drift_value numeric,
  last_completed_at timestamptz,
  is_stale boolean
)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT 
    CASE WHEN metric.key IS NOT NULL THEN latest.table_name || '.' || metric.key ELSE latest.table_name END as component_name, 
    CASE WHEN metric.key IS NOT NULL THEN (metric.value->>'status')::text ELSE latest.status END as status,
    CASE WHEN metric.key IS NOT NULL THEN (metric.value->>'drift_value')::numeric ELSE latest.drift_value END as drift_value,
    latest.completed_at as last_completed_at,
    CASE 
      WHEN (CASE WHEN metric.key IS NOT NULL THEN (metric.value->>'status')::text ELSE latest.status END) IN ('FAILED', 'PARTIAL_FAILURE', 'BLOCKED', 'RUNNING') THEN true 
      WHEN latest.completed_at < now() - interval '24 hours' THEN true
      ELSE false 
    END as is_stale
  FROM (
    SELECT 
      table_name, status, drift_value, completed_at, metric_states,
      ROW_NUMBER() OVER (PARTITION BY table_name ORDER BY started_at DESC) as rn
    FROM analytics.etl_runs
  ) latest
  LEFT JOIN jsonb_each(latest.metric_states) metric ON true
  WHERE latest.rn = 1;
$$;
GRANT EXECUTE ON FUNCTION analytics.get_system_trust_state() TO authenticated;



-- ------------------------------------------------------------
-- 3. Dimensions (Views on Operational Layer)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.dim_date AS
SELECT
  d::date AS date,
  EXTRACT(year FROM d) AS year,
  EXTRACT(month FROM d) AS month,
  EXTRACT(day FROM d) AS day,
  EXTRACT(dow FROM d) AS day_of_week
FROM generate_series('2020-01-01'::timestamp, '2030-12-31'::timestamp, '1 day'::interval) d;

CREATE OR REPLACE VIEW analytics.dim_employee AS
SELECT id, user_id, full_name, branch_id, status 
FROM public.hr_employees;

CREATE OR REPLACE VIEW analytics.dim_customer AS
SELECT id, name, governorate_id, city_id, area_id, assigned_rep_id, is_active 
FROM public.customers;

CREATE OR REPLACE VIEW analytics.dim_product AS
SELECT id, name, category_id, brand_id, cost_price, selling_price, is_active 
FROM public.products;

-- Dimensions are NO LONGER implicitly granted to authenticated.
-- Direct queries are blocked; wrapper functions / service_role handles authorized read workflows.
REVOKE SELECT ON analytics.dim_product FROM authenticated;
REVOKE SELECT ON analytics.dim_customer FROM authenticated;
REVOKE SELECT ON analytics.dim_employee FROM authenticated;
REVOKE SELECT ON analytics.dim_date FROM authenticated;


-- ------------------------------------------------------------
-- 4. Fact Tables (Materialized and Incremental)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS analytics.fact_sales_daily_grain (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  date date NOT NULL,
  customer_id uuid NOT NULL,
  product_id uuid NOT NULL,
  rep_id uuid NOT NULL,
  
  -- Tax Inclusive (Invoice Gross Debt Creation)
  tax_inclusive_amount numeric DEFAULT 0,
  ar_credit_portion_amount numeric DEFAULT 0,
  return_tax_inclusive_amount numeric DEFAULT 0,
  
  -- Tax Exclusive (Recognized Sales Revenue)
  tax_exclusive_amount numeric DEFAULT 0,
  tax_amount numeric DEFAULT 0,
  return_tax_exclusive_amount numeric DEFAULT 0,
  net_tax_exclusive_revenue numeric DEFAULT 0,
  
  -- Quantities
  gross_quantity numeric DEFAULT 0,
  return_quantity numeric DEFAULT 0,
  net_quantity numeric DEFAULT 0,
  
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT fact_sales_daily_grain_unique UNIQUE (date, customer_id, product_id, rep_id)
);

-- Indexing for rapid queries
CREATE INDEX IF NOT EXISTS idx_fact_sales_date ON analytics.fact_sales_daily_grain(date);
CREATE INDEX IF NOT EXISTS idx_fact_sales_rep ON analytics.fact_sales_daily_grain(rep_id, date);
CREATE INDEX IF NOT EXISTS idx_fact_sales_cust ON analytics.fact_sales_daily_grain(customer_id, date);


CREATE TABLE IF NOT EXISTS analytics.fact_treasury_cashflow_daily (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  treasury_date date NOT NULL,
  customer_id uuid NOT NULL,
  collected_by uuid NOT NULL,
  
  gross_inflow_amount numeric DEFAULT 0,
  gross_outflow_amount numeric DEFAULT 0,
  net_cashflow numeric DEFAULT 0,
  
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT fact_treasury_cashflow_daily_unique UNIQUE (treasury_date, customer_id, collected_by)
);

CREATE INDEX IF NOT EXISTS idx_fact_treasury_rcpt_date ON analytics.fact_treasury_cashflow_daily(treasury_date);
CREATE INDEX IF NOT EXISTS idx_fact_treasury_rcpt_rep ON analytics.fact_treasury_cashflow_daily(collected_by, treasury_date);


CREATE TABLE IF NOT EXISTS analytics.fact_ar_collections_attributed_to_origin_sale_date (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  origin_sale_delivered_at date NOT NULL,
  customer_id uuid NOT NULL,
  collected_by uuid NOT NULL,
  original_rep_id uuid NOT NULL,
  
  receipt_amount numeric DEFAULT 0,
  cash_refund_amount numeric DEFAULT 0,
  net_cohort_collection numeric DEFAULT 0,
  
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT fact_ar_collections_orig_date_unique UNIQUE (origin_sale_delivered_at, customer_id, collected_by, original_rep_id)
);

CREATE INDEX IF NOT EXISTS idx_fact_col_orig_date ON analytics.fact_ar_collections_attributed_to_origin_sale_date(origin_sale_delivered_at);
CREATE INDEX IF NOT EXISTS idx_fact_col_orig_rep ON analytics.fact_ar_collections_attributed_to_origin_sale_date(original_rep_id, origin_sale_delivered_at);


CREATE TABLE IF NOT EXISTS analytics.fact_financial_ledgers_daily (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  date date NOT NULL,
  account_id uuid NOT NULL,
  
  debit_sum numeric DEFAULT 0,
  credit_sum numeric DEFAULT 0,
  net_movement numeric DEFAULT 0,
  
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT fact_fin_ledgers_daily_unique UNIQUE (date, account_id)
);

CREATE INDEX IF NOT EXISTS idx_fact_ledger_date ON analytics.fact_financial_ledgers_daily(date);
CREATE INDEX IF NOT EXISTS idx_fact_ledger_acc ON analytics.fact_financial_ledgers_daily(account_id, date);


-- ------------------------------------------------------------
-- 5. Snapshots
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS analytics.snapshot_customer_health (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  as_of_date date NOT NULL,
  customer_id uuid NOT NULL,
  
  recency_days integer DEFAULT 0,
  frequency_l90d integer DEFAULT 0,
  monetary_l90d numeric DEFAULT 0,
  is_dormant boolean DEFAULT false,
  
  created_at timestamptz DEFAULT now(),
  CONSTRAINT snapshot_cust_health_unique UNIQUE (as_of_date, customer_id)
);

CREATE INDEX IF NOT EXISTS idx_snap_cust_health ON analytics.snapshot_customer_health(as_of_date, customer_id);


-- Grants for Tables
GRANT SELECT ON analytics.fact_sales_daily_grain TO authenticated;
GRANT ALL ON analytics.fact_sales_daily_grain TO service_role;

GRANT SELECT ON analytics.fact_treasury_cashflow_daily TO authenticated;
GRANT ALL ON analytics.fact_treasury_cashflow_daily TO service_role;

GRANT SELECT ON analytics.fact_ar_collections_attributed_to_origin_sale_date TO authenticated;
GRANT ALL ON analytics.fact_ar_collections_attributed_to_origin_sale_date TO service_role;

GRANT SELECT ON analytics.fact_financial_ledgers_daily TO authenticated;
GRANT ALL ON analytics.fact_financial_ledgers_daily TO service_role;

GRANT SELECT ON analytics.snapshot_customer_health TO authenticated;
GRANT ALL ON analytics.snapshot_customer_health TO service_role;


-- ------------------------------------------------------------
-- 6. Row Level Security (RLS) Configuration
-- ------------------------------------------------------------
ALTER TABLE analytics.fact_sales_daily_grain ENABLE ROW LEVEL SECURITY;
CREATE POLICY fact_sales_read ON analytics.fact_sales_daily_grain
  FOR SELECT TO authenticated
  USING (
    public.check_permission(auth.uid(), 'reports.view_all')
    OR (
      public.check_permission(auth.uid(), 'reports.sales')
      AND (
        -- Identity Domain Choice: rep_id maps to profiles.id (auth.uid()) to align with sales_orders/customers structures
        rep_id = auth.uid()
        OR (
          public.check_permission(auth.uid(), 'reports.team_performance')
          AND rep_id IN (
            SELECT target.user_id FROM public.hr_employees target
            JOIN public.hr_employees me ON target.branch_id = me.branch_id
            WHERE me.user_id = auth.uid()
            AND target.user_id IS NOT NULL
          )
        )
      )
    )
  );

ALTER TABLE analytics.fact_treasury_cashflow_daily ENABLE ROW LEVEL SECURITY;
CREATE POLICY fact_treasury_cashflow_daily_read ON analytics.fact_treasury_cashflow_daily
  FOR SELECT TO authenticated
  USING (
    public.check_permission(auth.uid(), 'reports.view_all')
    OR (
      public.check_permission(auth.uid(), 'reports.sales')
      AND (
        collected_by = auth.uid()
        OR (
          public.check_permission(auth.uid(), 'reports.team_performance')
          AND collected_by IN (
            SELECT target.user_id FROM public.hr_employees target
            JOIN public.hr_employees me ON target.branch_id = me.branch_id
            WHERE me.user_id = auth.uid()
            AND target.user_id IS NOT NULL
          )
        )
      )
    )
  );

ALTER TABLE analytics.fact_ar_collections_attributed_to_origin_sale_date ENABLE ROW LEVEL SECURITY;
CREATE POLICY fact_ar_collections_orig_read ON analytics.fact_ar_collections_attributed_to_origin_sale_date
  FOR SELECT TO authenticated
  USING (
    public.check_permission(auth.uid(), 'reports.view_all')
    OR (
      public.check_permission(auth.uid(), 'reports.targets')
      AND (
        collected_by = auth.uid() OR 
        original_rep_id = auth.uid()
        OR (
          public.check_permission(auth.uid(), 'reports.team_performance')
          AND (
            collected_by IN (
              SELECT target.user_id FROM public.hr_employees target
              JOIN public.hr_employees me ON target.branch_id = me.branch_id
              WHERE me.user_id = auth.uid()
              AND target.user_id IS NOT NULL
            )
            OR original_rep_id IN (
              SELECT target.user_id FROM public.hr_employees target
              JOIN public.hr_employees me ON target.branch_id = me.branch_id
              WHERE me.user_id = auth.uid()
              AND target.user_id IS NOT NULL
            )
          )
        )
      )
    )
  );

ALTER TABLE analytics.fact_financial_ledgers_daily ENABLE ROW LEVEL SECURITY;
CREATE POLICY fact_fin_ledger_read ON analytics.fact_financial_ledgers_daily
  FOR SELECT TO authenticated
  USING (
    public.check_permission(auth.uid(), 'reports.view_all')
    OR public.check_permission(auth.uid(), 'reports.financial')
  );

ALTER TABLE analytics.snapshot_customer_health ENABLE ROW LEVEL SECURITY;
CREATE POLICY snap_cust_health_read ON analytics.snapshot_customer_health
  FOR SELECT TO authenticated
  USING (
    public.check_permission(auth.uid(), 'reports.view_all')
    OR (
      public.check_permission(auth.uid(), 'reports.sales')
      AND customer_id IN (
        SELECT id FROM public.customers
        WHERE assigned_rep_id = auth.uid()
        OR (
          public.check_permission(auth.uid(), 'reports.team_performance')
          AND assigned_rep_id IN (
            SELECT target.user_id FROM public.hr_employees target
            JOIN public.hr_employees me ON target.branch_id = me.branch_id
            WHERE me.user_id = auth.uid()
            AND target.user_id IS NOT NULL
          )
        )
      )
    )
  );

-- End of Wave 1 Base Schema Migration
