-- Synthetic producer schema uses source-derived column names/types.
-- It is not a full installed-schema/permission/trigger replica.
CREATE SCHEMA analytics;
CREATE SCHEMA auth;
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE ROLE service_role BYPASSRLS;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE TABLE public.sales_orders (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),customer_id UUID,rep_id UUID,branch_id UUID,status TEXT,order_date DATE,delivered_at TIMESTAMPTZ,total_amount NUMERIC DEFAULT 0,credit_amount NUMERIC DEFAULT 0,subtotal NUMERIC DEFAULT 0,tax_amount NUMERIC DEFAULT 0,updated_at TIMESTAMPTZ DEFAULT now());
CREATE TABLE public.sales_order_items (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),order_id UUID,product_id UUID,line_total NUMERIC DEFAULT 0,tax_amount NUMERIC DEFAULT 0,base_quantity NUMERIC DEFAULT 0,unit_cost_at_sale NUMERIC DEFAULT 0);
CREATE TABLE public.sales_returns (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),order_id UUID,customer_id UUID,status TEXT,confirmed_at TIMESTAMPTZ,updated_at TIMESTAMPTZ DEFAULT now());
CREATE TABLE public.sales_return_items (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),return_id UUID,order_item_id UUID,line_total NUMERIC DEFAULT 0,base_quantity NUMERIC DEFAULT 0);
CREATE TABLE public.payment_receipts (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),sales_order_id UUID,customer_id UUID,created_at TIMESTAMPTZ DEFAULT now(),amount NUMERIC DEFAULT 0,status TEXT,collected_by UUID,updated_at TIMESTAMPTZ DEFAULT now());
CREATE TABLE public.customer_ledger (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),customer_id UUID,created_at TIMESTAMPTZ DEFAULT now(),allocated_to UUID,source_id UUID,source_type TEXT,type TEXT,amount NUMERIC DEFAULT 0);
CREATE TABLE public.vault_transactions (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),created_at TIMESTAMPTZ DEFAULT now(),type TEXT,amount NUMERIC DEFAULT 0,reference_type TEXT,reference_id UUID);
CREATE TABLE public.custody_transactions (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),created_at TIMESTAMPTZ DEFAULT now(),type TEXT,amount NUMERIC DEFAULT 0,reference_type TEXT,reference_id UUID);
CREATE TABLE public.journal_entries (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),entry_date DATE,status TEXT,source_type TEXT,source_id UUID,created_at TIMESTAMPTZ DEFAULT now());
CREATE TABLE public.journal_entry_lines (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),entry_id UUID,account_id UUID,debit NUMERIC DEFAULT 0,credit NUMERIC DEFAULT 0);
CREATE TABLE public.customers (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),governorate_id UUID,city_id UUID,area_id UUID);
CREATE TABLE public.expenses (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),branch_id UUID);
CREATE TABLE public.hr_payroll_runs (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),branch_id UUID);
CREATE TABLE public.chart_of_accounts (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),code TEXT);
CREATE TABLE public.hr_employees (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),branch_id UUID,status TEXT,hire_date DATE,termination_date DATE,user_id UUID);

ALTER TABLE public.sales_order_items ADD FOREIGN KEY(order_id) REFERENCES public.sales_orders(id) ON DELETE CASCADE;
ALTER TABLE public.sales_return_items ADD FOREIGN KEY(return_id) REFERENCES public.sales_returns(id) ON DELETE CASCADE;
ALTER TABLE public.journal_entry_lines ADD FOREIGN KEY(entry_id) REFERENCES public.journal_entries(id) ON DELETE CASCADE;
CREATE TABLE public.targets(id uuid PRIMARY KEY,name text,type_code text,scope text,scope_id uuid,period_start date,period_end date,target_value numeric,is_active boolean DEFAULT true,is_paused boolean DEFAULT false);
CREATE TABLE public.target_progress(target_id uuid,snapshot_date date,achieved_value numeric,achievement_pct numeric,trend text);
CREATE TABLE public.profiles(id uuid PRIMARY KEY,full_name text);
CREATE TABLE public.branches(id uuid PRIMARY KEY,name text);
CREATE FUNCTION public.set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at=now(); RETURN NEW; END $$;
CREATE TRIGGER fixture_updated_at BEFORE UPDATE ON public.sales_orders FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER fixture_updated_at BEFORE UPDATE ON public.sales_returns FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER fixture_updated_at BEFORE UPDATE ON public.payment_receipts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TABLE analytics.fixture_assertions(label text PRIMARY KEY,passed_at timestamptz DEFAULT clock_timestamp());
CREATE FUNCTION analytics.fixture_assert(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',label; END IF;
INSERT INTO analytics.fixture_assertions(label) VALUES(label) ON CONFLICT DO NOTHING;
RAISE NOTICE 'PASS: %',label; END $$;
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
  updated_at         timestamptz DEFAULT now()
  -- NOTE: no inline UNIQUE constraint here — NULLable geo columns require an
  -- expression index with COALESCE to make ON CONFLICT work correctly.
  -- See CREATE UNIQUE INDEX below.
);
CREATE UNIQUE INDEX IF NOT EXISTS fact_geo_daily_unique_idx
  ON analytics.fact_geography_daily (
    date,
    COALESCE(governorate_id, '00000000-0000-0000-0000-000000000000'::uuid),
    COALESCE(city_id,        '00000000-0000-0000-0000-000000000000'::uuid),
    COALESCE(area_id,        '00000000-0000-0000-0000-000000000000'::uuid)
  );
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
CREATE TABLE IF NOT EXISTS analytics.fact_gross_profit_daily_grain (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- أبعاد تحليلية — كلها من البيع الأصلي، حتى في حالة المرتجع
    sale_date         DATE        NOT NULL,
    branch_id         UUID        NULL,   -- NULL = unassigned
    customer_id       UUID        NOT NULL,
    product_id        UUID        NOT NULL,
    rep_id            UUID        NOT NULL,
    -- مقاييس المبيعات (قبل المرتجع)
    gross_revenue     NUMERIC(15,2) NOT NULL DEFAULT 0,
    gross_quantity    NUMERIC(15,4) NOT NULL DEFAULT 0,
    -- مقاييس المرتجعات — تاريخ الانعكاس هو تاريخ البيع الأصلي
    -- (يُجمَّع مرة واحدة لكل order_item_id ثم JOIN)
    return_revenue    NUMERIC(15,2) NOT NULL DEFAULT 0,
    return_quantity   NUMERIC(15,4) NOT NULL DEFAULT 0,
    -- التكلفة من unit_cost_at_sale
    gross_cogs        NUMERIC(15,2) NOT NULL DEFAULT 0,
    return_cogs       NUMERIC(15,2) NOT NULL DEFAULT 0,
    -- مشتقات محسوبة
    net_revenue       NUMERIC(15,2) GENERATED ALWAYS AS (gross_revenue - return_revenue) STORED,
    net_quantity      NUMERIC(15,4) GENERATED ALWAYS AS (gross_quantity - return_quantity) STORED,
    net_cogs          NUMERIC(15,2) GENERATED ALWAYS AS (gross_cogs - return_cogs) STORED,
    gross_profit      NUMERIC(15,2) GENERATED ALWAYS AS (
                          (gross_revenue - return_revenue) - (gross_cogs - return_cogs)
                      ) STORED,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (sale_date, branch_id, customer_id, product_id, rep_id)
);
CREATE TABLE IF NOT EXISTS analytics.fact_branch_profit_daily (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profit_date           DATE    NOT NULL,
    branch_id             UUID    NULL,   -- NULL = unassigned
    -- إجمالي ربح (مجمَّع من fact_gross_profit_daily_grain)
    gross_revenue         NUMERIC(15,2) NOT NULL DEFAULT 0,
    gross_cogs            NUMERIC(15,2) NOT NULL DEFAULT 0,
    gross_profit          NUMERIC(15,2) NOT NULL DEFAULT 0,
    -- مصروفات تشغيلية مباشرة مرتبطة بالفرع
    direct_operating_exp  NUMERIC(15,2) NOT NULL DEFAULT 0,
    direct_payroll_exp    NUMERIC(15,2) NOT NULL DEFAULT 0,
    -- صافي ربح مباشر (ليس صافيًا نهائيًا — لا يوجد توزيع إداري)
    direct_net_profit     NUMERIC(15,2) GENERATED ALWAYS AS (
                              gross_profit - direct_operating_exp - direct_payroll_exp
                          ) STORED,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (profit_date, branch_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS uidx_fact_gp_grain_null_branch
    ON analytics.fact_gross_profit_daily_grain (sale_date, customer_id, product_id, rep_id)
    WHERE branch_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uidx_fact_branch_profit_null_branch
    ON analytics.fact_branch_profit_daily (profit_date)
    WHERE branch_id IS NULL;
CREATE TABLE IF NOT EXISTS analytics.profitability_allocation_rule_sets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    applies_to TEXT NOT NULL CHECK (applies_to IN ('operating_expenses', 'payroll_expenses')),
    basis TEXT NOT NULL CHECK (basis IN ('revenue_share', 'gross_profit_share', 'direct_payroll_share', 'headcount_share', 'fixed_pct')),
    effective_from DATE NOT NULL,
    effective_to DATE,
    is_active BOOLEAN NOT NULL DEFAULT true,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by UUID REFERENCES auth.users(id)
);
CREATE TABLE IF NOT EXISTS analytics.profitability_allocation_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_set_id UUID NOT NULL REFERENCES analytics.profitability_allocation_rule_sets(id) ON DELETE CASCADE,
    branch_id UUID NOT NULL,
    weight_value NUMERIC(7,6) NULL,
    UNIQUE(rule_set_id, branch_id),
    CHECK (weight_value IS NULL OR (weight_value >= 0 AND weight_value <= 1))
);
CREATE TABLE IF NOT EXISTS analytics.snapshot_branch_allocation_weights_monthly (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    month_start DATE NOT NULL,
    applies_to TEXT NOT NULL CHECK (applies_to IN ('operating_expenses', 'payroll_expenses')),
    branch_id UUID NOT NULL,
    rule_set_id UUID NOT NULL REFERENCES analytics.profitability_allocation_rule_sets(id),
    basis TEXT NOT NULL,
    computed_weight NUMERIC(7,6) NOT NULL,
    raw_basis_value NUMERIC(15,2) NOT NULL DEFAULT 0,
    total_basis_value NUMERIC(15,2) NOT NULL DEFAULT 0,
    is_estimated BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(month_start, applies_to, branch_id)
);
CREATE TABLE IF NOT EXISTS analytics.fact_branch_profit_final_monthly (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    month_start DATE NOT NULL,
    branch_id UUID NULL, 
    direct_gross_revenue NUMERIC(15,2) NOT NULL DEFAULT 0,
    direct_gross_cogs NUMERIC(15,2) NOT NULL DEFAULT 0,
    direct_gross_profit NUMERIC(15,2) NOT NULL DEFAULT 0,
    direct_operating_exp NUMERIC(15,2) NOT NULL DEFAULT 0,
    direct_payroll_exp NUMERIC(15,2) NOT NULL DEFAULT 0,
    allocated_shared_op NUMERIC(15,2) NOT NULL DEFAULT 0,
    allocated_shared_pay NUMERIC(15,2) NOT NULL DEFAULT 0,
    unallocated_shared_op NUMERIC(15,2) NOT NULL DEFAULT 0,
    unallocated_shared_pay NUMERIC(15,2) NOT NULL DEFAULT 0,
    final_net_profit NUMERIC(15,2) GENERATED ALWAYS AS (
        direct_gross_profit - direct_operating_exp - direct_payroll_exp
        - allocated_shared_op - allocated_shared_pay 
        - unallocated_shared_op - unallocated_shared_pay
    ) STORED,
    rule_set_id_op UUID NULL REFERENCES analytics.profitability_allocation_rule_sets(id),
    rule_set_id_pay UUID NULL REFERENCES analytics.profitability_allocation_rule_sets(id),
    is_estimated BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(month_start, branch_id)
);
CREATE TABLE IF NOT EXISTS analytics.profitability_data_quality_daily (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    check_date DATE NOT NULL,
    check_month DATE,
    applies_to TEXT,
    check_type TEXT NOT NULL,
    severity TEXT NOT NULL CHECK (severity IN ('WARNING', 'ERROR')),
    record_count INTEGER NOT NULL DEFAULT 0,
    detail JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(check_date, check_type, check_month, applies_to)
);
CREATE UNIQUE INDEX IF NOT EXISTS uidx_fact_final_null_branch
    ON analytics.fact_branch_profit_final_monthly (month_start)
    WHERE branch_id IS NULL;
ALTER TABLE analytics.profitability_data_quality_daily ADD CONSTRAINT uq_pdqd_unique_check UNIQUE NULLS NOT DISTINCT (check_date,check_type,check_month,applies_to);
CREATE OR REPLACE FUNCTION analytics.effective_sale_date(p_del timestamp with time zone, p_ord date)
 RETURNS date
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT COALESCE((p_del AT TIME ZONE 'Africa/Cairo')::DATE, p_ord);
$function$;


CREATE OR REPLACE FUNCTION analytics.txn_date(p_ts timestamp with time zone)
 RETURNS date
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT (p_ts AT TIME ZONE 'Africa/Cairo')::DATE;
$function$;

CREATE OR REPLACE FUNCTION analytics.detect_affected_dates(p_last_watermark timestamp with time zone)
 RETURNS date[]
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_dates DATE[];
BEGIN
  WITH affected AS (
    SELECT analytics.effective_sale_date(so.delivered_at, so.order_date) as d FROM public.sales_orders so WHERE so.updated_at >= p_last_watermark
    UNION
    SELECT analytics.effective_sale_date(so.delivered_at, so.order_date) as d FROM public.sales_returns sr JOIN public.sales_orders so ON sr.order_id = so.id WHERE sr.updated_at >= p_last_watermark
    UNION
    SELECT analytics.effective_sale_date(so.delivered_at, so.order_date) as d FROM public.payment_receipts pr JOIN public.sales_orders so ON pr.sales_order_id = so.id WHERE pr.updated_at >= p_last_watermark
    UNION
    SELECT analytics.txn_date(created_at) as d FROM public.customer_ledger WHERE created_at >= p_last_watermark
    UNION 
    SELECT analytics.txn_date(created_at) as d FROM public.vault_transactions WHERE created_at >= p_last_watermark
    UNION 
    SELECT analytics.effective_sale_date(so.delivered_at, so.order_date) as d FROM public.vault_transactions vt JOIN public.sales_returns sr ON vt.reference_id = sr.id JOIN public.sales_orders so ON sr.order_id = so.id WHERE vt.created_at >= p_last_watermark AND vt.reference_type = 'sales_return'
    UNION
    SELECT analytics.txn_date(created_at) as d FROM public.custody_transactions WHERE created_at >= p_last_watermark
    UNION 
    SELECT analytics.effective_sale_date(so.delivered_at, so.order_date) as d FROM public.custody_transactions ct JOIN public.sales_returns sr ON ct.reference_id = sr.id JOIN public.sales_orders so ON sr.order_id = so.id WHERE ct.created_at >= p_last_watermark AND ct.reference_type = 'sales_return'
    UNION
    SELECT entry_date as d FROM public.journal_entries WHERE created_at >= p_last_watermark
    UNION
    SELECT analytics.effective_sale_date(so.delivered_at, so.order_date) as d FROM public.customer_ledger cl JOIN public.customer_ledger invoice_cl ON cl.allocated_to = invoice_cl.id JOIN public.sales_orders so ON invoice_cl.source_id = so.id WHERE cl.created_at >= p_last_watermark AND cl.type = 'credit' AND cl.source_type = 'payment_receipt' AND invoice_cl.source_type = 'sales_order'
  )
  SELECT array_agg(DISTINCT d) INTO v_dates FROM affected WHERE d IS NOT NULL;
  RETURN COALESCE(v_dates, ARRAY[]::DATE[]);
END;
$function$;

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
  ON CONFLICT (
    date,
    COALESCE(governorate_id, '00000000-0000-0000-0000-000000000000'::uuid),
    COALESCE(city_id,        '00000000-0000-0000-0000-000000000000'::uuid),
    COALESCE(area_id,        '00000000-0000-0000-0000-000000000000'::uuid)
  ) DO UPDATE SET
    net_revenue       = EXCLUDED.net_revenue,
    return_value      = EXCLUDED.return_value,
    tax_amount        = EXCLUDED.tax_amount,
    gross_revenue     = EXCLUDED.gross_revenue,
    customer_count    = EXCLUDED.customer_count,
    transaction_count = EXCLUDED.transaction_count,
    updated_at        = now();
END;
$$;
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
CREATE OR REPLACE PROCEDURE analytics.internal_refresh_fact_gross_profit_daily_grain(
    p_target_dates DATE[]
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    IF array_length(p_target_dates, 1) IS NULL THEN
        RETURN;
    END IF;

    DELETE FROM analytics.fact_gross_profit_daily_grain
    WHERE sale_date = ANY(p_target_dates);

    DROP TABLE IF EXISTS tmp_gpg_aggregated;

    CREATE TEMP TABLE tmp_gpg_aggregated ON COMMIT DROP AS
    WITH sales_items AS (
        SELECT
            CASE
                WHEN so.delivered_at IS NOT NULL
                    THEN (so.delivered_at AT TIME ZONE 'Africa/Cairo')::DATE
                ELSE so.order_date
            END AS event_date,
            so.branch_id,
            so.customer_id,
            soi.product_id,
            COALESCE(so.rep_id, '00000000-0000-0000-0000-000000000000'::UUID) AS rep_id,
            soi.line_total AS item_revenue,
            soi.base_quantity AS item_quantity,
            COALESCE(soi.unit_cost_at_sale, 0) AS unit_cost
        FROM public.sales_orders so
        JOIN public.sales_order_items soi ON soi.order_id = so.id
        JOIN unnest(p_target_dates) AS tgt_date
          ON (
                (so.delivered_at IS NOT NULL
                    AND so.delivered_at >= (tgt_date::timestamp AT TIME ZONE 'Africa/Cairo')
                    AND so.delivered_at < ((tgt_date + 1)::timestamp AT TIME ZONE 'Africa/Cairo'))
             OR (so.delivered_at IS NULL AND so.order_date = tgt_date)
          )
        WHERE so.status IN ('delivered', 'completed')
    ),
    sales_agg AS (
        SELECT
            event_date AS sale_date,
            branch_id,
            customer_id,
            product_id,
            rep_id,
            SUM(item_revenue) AS gross_revenue,
            SUM(item_quantity) AS gross_quantity,
            SUM(unit_cost * item_quantity) AS gross_cogs,
            0::NUMERIC AS return_revenue,
            0::NUMERIC AS return_quantity,
            0::NUMERIC AS return_cogs
        FROM sales_items
        GROUP BY event_date, branch_id, customer_id, product_id, rep_id
    ),
    return_items AS (
        SELECT
            (sr.confirmed_at AT TIME ZONE 'Africa/Cairo')::DATE AS event_date,
            so.branch_id,
            so.customer_id,
            soi.product_id,
            COALESCE(so.rep_id, '00000000-0000-0000-0000-000000000000'::UUID) AS rep_id,
            sri.line_total AS ret_revenue,
            sri.base_quantity AS ret_quantity,
            COALESCE(soi.unit_cost_at_sale, 0) AS unit_cost
        FROM public.sales_return_items sri
        JOIN public.sales_returns sr ON sr.id = sri.return_id
        JOIN public.sales_order_items soi ON soi.id = sri.order_item_id
        JOIN public.sales_orders so ON so.id = soi.order_id
        JOIN unnest(p_target_dates) AS tgt_date
          ON (sr.confirmed_at AT TIME ZONE 'Africa/Cairo')::DATE = tgt_date
        WHERE sr.status = 'confirmed'
    ),
    returns_agg AS (
        SELECT
            event_date AS sale_date,
            branch_id,
            customer_id,
            product_id,
            rep_id,
            0::NUMERIC AS gross_revenue,
            0::NUMERIC AS gross_quantity,
            0::NUMERIC AS gross_cogs,
            SUM(ret_revenue) AS return_revenue,
            SUM(ret_quantity) AS return_quantity,
            SUM(ret_quantity * unit_cost) AS return_cogs
        FROM return_items
        GROUP BY event_date, branch_id, customer_id, product_id, rep_id
    ),
    all_events AS (
        SELECT * FROM sales_agg
        UNION ALL
        SELECT * FROM returns_agg
    )
    SELECT
        sale_date,
        branch_id,
        customer_id,
        product_id,
        rep_id,
        SUM(gross_revenue) AS gross_revenue,
        SUM(gross_quantity) AS gross_quantity,
        SUM(gross_cogs) AS gross_cogs,
        SUM(return_revenue) AS return_revenue,
        SUM(return_quantity) AS return_quantity,
        SUM(return_cogs) AS return_cogs
    FROM all_events
    GROUP BY sale_date, branch_id, customer_id, product_id, rep_id;

    INSERT INTO analytics.fact_gross_profit_daily_grain (
        sale_date, branch_id, customer_id, product_id, rep_id,
        gross_revenue, gross_quantity, return_revenue, return_quantity,
        gross_cogs, return_cogs
    )
    SELECT
        sale_date, branch_id, customer_id, product_id, rep_id,
        gross_revenue, gross_quantity, return_revenue, return_quantity,
        gross_cogs, return_cogs
    FROM tmp_gpg_aggregated
    WHERE branch_id IS NOT NULL
    ON CONFLICT (sale_date, branch_id, customer_id, product_id, rep_id)
        WHERE branch_id IS NOT NULL
    DO UPDATE SET
        gross_revenue = EXCLUDED.gross_revenue,
        gross_quantity = EXCLUDED.gross_quantity,
        return_revenue = EXCLUDED.return_revenue,
        return_quantity = EXCLUDED.return_quantity,
        gross_cogs = EXCLUDED.gross_cogs,
        return_cogs = EXCLUDED.return_cogs,
        updated_at = now();

    INSERT INTO analytics.fact_gross_profit_daily_grain (
        sale_date, branch_id, customer_id, product_id, rep_id,
        gross_revenue, gross_quantity, return_revenue, return_quantity,
        gross_cogs, return_cogs
    )
    SELECT
        sale_date, branch_id, customer_id, product_id, rep_id,
        gross_revenue, gross_quantity, return_revenue, return_quantity,
        gross_cogs, return_cogs
    FROM tmp_gpg_aggregated
    WHERE branch_id IS NULL
    ON CONFLICT (sale_date, customer_id, product_id, rep_id)
        WHERE branch_id IS NULL
    DO UPDATE SET
        gross_revenue = EXCLUDED.gross_revenue,
        gross_quantity = EXCLUDED.gross_quantity,
        return_revenue = EXCLUDED.return_revenue,
        return_quantity = EXCLUDED.return_quantity,
        gross_cogs = EXCLUDED.gross_cogs,
        return_cogs = EXCLUDED.return_cogs,
        updated_at = now();
END;
$$;
CREATE OR REPLACE PROCEDURE analytics.internal_refresh_profitability_data_quality_daily(p_target_dates DATE[])
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    d DATE;
    v_cnt INT;
    v_dtl JSONB;
BEGIN
    IF array_length(p_target_dates, 1) IS NULL THEN
        RETURN;
    END IF;

    DELETE FROM analytics.profitability_data_quality_daily
    WHERE check_date = ANY(p_target_dates)
      AND check_month IS NULL;

    FOREACH d IN ARRAY p_target_dates LOOP
        SELECT COUNT(*), COALESCE(jsonb_agg(sub.id) FILTER (WHERE sub.num <= 10), '[]'::jsonb)
        INTO v_cnt, v_dtl
        FROM (
            SELECT soi.id, row_number() OVER () AS num
            FROM public.sales_orders so
            JOIN public.sales_order_items soi ON soi.order_id = so.id
            WHERE ((so.delivered_at IS NOT NULL AND (so.delivered_at AT TIME ZONE 'Africa/Cairo')::DATE = d) OR (so.delivered_at IS NULL AND so.order_date = d))
              AND so.status IN ('delivered', 'completed')
              AND COALESCE(soi.unit_cost_at_sale, 0) = 0
        ) sub;
        IF v_cnt > 0 THEN
            INSERT INTO analytics.profitability_data_quality_daily (check_date, check_type, severity, record_count, detail)
            VALUES (d, 'zero_cost_delivered_items', 'WARNING', v_cnt, jsonb_build_object('sample_ids', v_dtl));
        END IF;

        SELECT COUNT(*), COALESCE(jsonb_agg(sub.id) FILTER (WHERE sub.num <= 10), '[]'::jsonb)
        INTO v_cnt, v_dtl
        FROM (
            SELECT soi.id, row_number() OVER () AS num
            FROM public.sales_orders so
            JOIN public.sales_order_items soi ON soi.order_id = so.id
            WHERE ((so.delivered_at IS NOT NULL AND (so.delivered_at AT TIME ZONE 'Africa/Cairo')::DATE = d) OR (so.delivered_at IS NULL AND so.order_date = d))
              AND so.status IN ('delivered', 'completed')
              AND soi.unit_cost_at_sale IS NULL
        ) sub;
        IF v_cnt > 0 THEN
            INSERT INTO analytics.profitability_data_quality_daily (check_date, check_type, severity, record_count, detail)
            VALUES (d, 'null_cost_delivered_items', 'ERROR', v_cnt, jsonb_build_object('sample_ids', v_dtl));
        END IF;

        SELECT COUNT(*), COALESCE(jsonb_agg(sub.id) FILTER (WHERE sub.num <= 10), '[]'::jsonb)
        INTO v_cnt, v_dtl
        FROM (
            SELECT sr.id, row_number() OVER () AS num
            FROM public.sales_returns sr
            WHERE sr.status = 'confirmed'
              AND sr.confirmed_at IS NULL
              AND (sr.updated_at AT TIME ZONE 'Africa/Cairo')::DATE = d
        ) sub;
        IF v_cnt > 0 THEN
            INSERT INTO analytics.profitability_data_quality_daily (check_date, check_type, severity, record_count, detail)
            VALUES (d, 'confirmed_return_no_confirmed_at', 'ERROR', v_cnt, jsonb_build_object('sample_ids', v_dtl));
        END IF;

        SELECT COUNT(*), COALESCE(jsonb_agg(sub.id) FILTER (WHERE sub.num <= 10), '[]'::jsonb)
        INTO v_cnt, v_dtl
        FROM (
            SELECT so.id, row_number() OVER () AS num
            FROM public.sales_orders so
            WHERE ((so.delivered_at IS NOT NULL AND (so.delivered_at AT TIME ZONE 'Africa/Cairo')::DATE = d) OR (so.delivered_at IS NULL AND so.order_date = d))
              AND so.status IN ('delivered', 'completed')
              AND so.branch_id IS NULL
        ) sub;
        IF v_cnt > 0 THEN
            INSERT INTO analytics.profitability_data_quality_daily (check_date, check_type, severity, record_count, detail)
            VALUES (d, 'sales_with_null_branch', 'WARNING', v_cnt, jsonb_build_object('sample_ids', v_dtl));
        END IF;

        SELECT COUNT(*), COALESCE(jsonb_agg(sub.id) FILTER (WHERE sub.num <= 10), '[]'::jsonb)
        INTO v_cnt, v_dtl
        FROM (
            SELECT so.id, row_number() OVER () AS num
            FROM public.sales_orders so
            WHERE ((so.delivered_at IS NOT NULL AND (so.delivered_at AT TIME ZONE 'Africa/Cairo')::DATE = d) OR (so.delivered_at IS NULL AND so.order_date = d))
              AND so.status IN ('delivered', 'completed')
              AND (so.rep_id IS NULL OR so.rep_id = '00000000-0000-0000-0000-000000000000'::UUID)
        ) sub;
        IF v_cnt > 0 THEN
            INSERT INTO analytics.profitability_data_quality_daily (check_date, check_type, severity, record_count, detail)
            VALUES (d, 'sentinel_rep_usage', 'WARNING', v_cnt, jsonb_build_object('sample_ids', v_dtl));
        END IF;
    END LOOP;
END;
$$;
CREATE OR REPLACE PROCEDURE analytics.internal_refresh_snapshot_branch_allocation_weights_monthly(p_months DATE[])
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    m DATE;
    pool_type TEXT;
    v_rs_count INT;
    v_rs_id UUID;
    v_rs_basis TEXT;
    v_rs_name TEXT;
    v_month_start DATE;
    v_month_end DATE;
    v_total_basis NUMERIC;
    v_sum_weight NUMERIC;
BEGIN
    IF array_length(p_months, 1) IS NULL THEN
        RETURN;
    END IF;

    FOR i IN 1..array_length(p_months, 1) LOOP
        m := date_trunc('month', p_months[i])::DATE;
        v_month_start := m;
        v_month_end := (m + interval '1 month' - interval '1 day')::DATE;

        DELETE FROM analytics.snapshot_branch_allocation_weights_monthly WHERE month_start = m;
        DELETE FROM analytics.profitability_data_quality_daily
        WHERE check_month = m
          AND check_type IN ('RULE_CONFLICT_BLOCKED', 'NO_ACTIVE_RULE', 'WEIGHT_SUM_INVALID', 'HEADCOUNT_SHARE_ESTIMATE');

        FOREACH pool_type IN ARRAY ARRAY['operating_expenses', 'payroll_expenses'] LOOP
            SELECT count(*)
            INTO v_rs_count
            FROM analytics.profitability_allocation_rule_sets
            WHERE is_active = true
              AND applies_to = pool_type
              AND effective_from <= v_month_end
              AND (effective_to IS NULL OR effective_to >= v_month_start);

            IF v_rs_count > 1 THEN
                INSERT INTO analytics.profitability_data_quality_daily (check_date, check_month, applies_to, check_type, severity, record_count, detail)
                VALUES (v_month_start, v_month_start, pool_type, 'RULE_CONFLICT_BLOCKED', 'ERROR', v_rs_count, jsonb_build_object('msg', 'Multiple active rule sets found for period. No allocation will occur.'));
                CONTINUE;
            ELSIF v_rs_count = 0 THEN
                INSERT INTO analytics.profitability_data_quality_daily (check_date, check_month, applies_to, check_type, severity, record_count)
                VALUES (v_month_start, v_month_start, pool_type, 'NO_ACTIVE_RULE', 'WARNING', 1);
                CONTINUE;
            END IF;

            SELECT id, basis, name
            INTO v_rs_id, v_rs_basis, v_rs_name
            FROM analytics.profitability_allocation_rule_sets
            WHERE is_active = true
              AND applies_to = pool_type
              AND effective_from <= v_month_end
              AND (effective_to IS NULL OR effective_to >= v_month_start)
            ORDER BY effective_from DESC, created_at DESC, id
            LIMIT 1;

            IF v_rs_basis = 'fixed_pct' THEN
                SELECT COALESCE(SUM(weight_value), 0)
                INTO v_sum_weight
                FROM analytics.profitability_allocation_rules
                WHERE rule_set_id = v_rs_id;

                IF ROUND(v_sum_weight, 4) != 1.0000 THEN
                    INSERT INTO analytics.profitability_data_quality_daily (check_date, check_month, applies_to, check_type, severity, record_count, detail)
                    VALUES (v_month_start, v_month_start, pool_type, 'WEIGHT_SUM_INVALID', 'ERROR', 1, jsonb_build_object('sum', v_sum_weight));
                    CONTINUE;
                END IF;

                INSERT INTO analytics.snapshot_branch_allocation_weights_monthly
                    (month_start, applies_to, branch_id, rule_set_id, basis, computed_weight, raw_basis_value, total_basis_value, is_estimated)
                SELECT
                    v_month_start, pool_type, branch_id, v_rs_id, v_rs_basis, weight_value, 0, 0, false
                FROM analytics.profitability_allocation_rules
                WHERE rule_set_id = v_rs_id
                  AND weight_value > 0;

            ELSIF v_rs_basis IN ('revenue_share', 'gross_profit_share', 'direct_payroll_share') THEN
                DROP TABLE IF EXISTS tmp_basis;

                CREATE TEMP TABLE tmp_basis ON COMMIT DROP AS
                SELECT branch_id,
                       SUM(CASE
                             WHEN v_rs_basis = 'revenue_share' THEN gross_revenue
                             WHEN v_rs_basis = 'gross_profit_share' THEN gross_profit
                             WHEN v_rs_basis = 'direct_payroll_share' THEN direct_payroll_exp
                           END) AS basis_val
                FROM analytics.fact_branch_profit_daily
                WHERE profit_date >= v_month_start AND profit_date <= v_month_end
                  AND branch_id IS NOT NULL
                  AND branch_id IN (SELECT branch_id FROM analytics.profitability_allocation_rules WHERE rule_set_id = v_rs_id)
                GROUP BY branch_id;

                SELECT COALESCE(SUM(basis_val), 0) INTO v_total_basis FROM tmp_basis;

                IF v_total_basis > 0 THEN
                    INSERT INTO analytics.snapshot_branch_allocation_weights_monthly
                        (month_start, applies_to, branch_id, rule_set_id, basis, computed_weight, raw_basis_value, total_basis_value, is_estimated)
                    SELECT
                        v_month_start, pool_type, branch_id, v_rs_id, v_rs_basis,
                        ROUND(basis_val / v_total_basis, 6), basis_val, v_total_basis, false
                    FROM tmp_basis WHERE basis_val > 0;

                    SELECT COALESCE(SUM(computed_weight), 0)
                    INTO v_sum_weight
                    FROM analytics.snapshot_branch_allocation_weights_monthly
                    WHERE month_start = v_month_start
                      AND applies_to = pool_type
                      AND rule_set_id = v_rs_id;

                    IF ROUND(v_sum_weight, 4) != 1.0000 THEN
                        DELETE FROM analytics.snapshot_branch_allocation_weights_monthly
                        WHERE month_start = v_month_start
                          AND applies_to = pool_type;

                        INSERT INTO analytics.profitability_data_quality_daily (check_date, check_month, applies_to, check_type, severity, record_count, detail)
                        VALUES (v_month_start, v_month_start, pool_type, 'WEIGHT_SUM_INVALID', 'ERROR', 1, jsonb_build_object('sum', v_sum_weight, 'msg', 'Precision distribution resulted in invalid total sum'));
                    END IF;
                ELSE
                    INSERT INTO analytics.profitability_data_quality_daily (check_date, check_month, applies_to, check_type, severity, record_count, detail)
                    VALUES (v_month_start, v_month_start, pool_type, 'WEIGHT_SUM_INVALID', 'ERROR', 1, jsonb_build_object('msg', 'Total basis pool is zero', 'basis', v_rs_basis));
                END IF;

                DROP TABLE IF EXISTS tmp_basis;

            ELSIF v_rs_basis = 'headcount_share' THEN
                DROP TABLE IF EXISTS tmp_hc_basis;

                CREATE TEMP TABLE tmp_hc_basis ON COMMIT DROP AS
                SELECT branch_id, COUNT(*) AS basis_val
                FROM public.hr_employees
                WHERE status IN ('active', 'on_leave')
                  AND hire_date <= v_month_end
                  AND (termination_date IS NULL OR termination_date > v_month_start)
                  AND branch_id IN (SELECT branch_id FROM analytics.profitability_allocation_rules WHERE rule_set_id = v_rs_id)
                GROUP BY branch_id;

                SELECT COALESCE(SUM(basis_val), 0) INTO v_total_basis FROM tmp_hc_basis;

                IF v_total_basis > 0 THEN
                    INSERT INTO analytics.snapshot_branch_allocation_weights_monthly
                        (month_start, applies_to, branch_id, rule_set_id, basis, computed_weight, raw_basis_value, total_basis_value, is_estimated)
                    SELECT
                        v_month_start, pool_type, branch_id, v_rs_id, v_rs_basis,
                        ROUND(basis_val / v_total_basis, 6), basis_val, v_total_basis, true
                    FROM tmp_hc_basis WHERE basis_val > 0;

                    INSERT INTO analytics.profitability_data_quality_daily (check_date, check_month, applies_to, check_type, severity, record_count, detail)
                    VALUES (v_month_start, v_month_start, pool_type, 'HEADCOUNT_SHARE_ESTIMATE', 'WARNING', 1, jsonb_build_object('msg', 'Headcount logic used, considered estimated distribution'));

                    SELECT COALESCE(SUM(computed_weight), 0)
                    INTO v_sum_weight
                    FROM analytics.snapshot_branch_allocation_weights_monthly
                    WHERE month_start = v_month_start
                      AND applies_to = pool_type
                      AND rule_set_id = v_rs_id;

                    IF ROUND(v_sum_weight, 4) != 1.0000 THEN
                        DELETE FROM analytics.snapshot_branch_allocation_weights_monthly
                        WHERE month_start = v_month_start
                          AND applies_to = pool_type;

                        INSERT INTO analytics.profitability_data_quality_daily (check_date, check_month, applies_to, check_type, severity, record_count, detail)
                        VALUES (v_month_start, v_month_start, pool_type, 'WEIGHT_SUM_INVALID', 'ERROR', 1, jsonb_build_object('sum', v_sum_weight, 'msg', 'Precision distribution resulted in invalid total sum'));
                    END IF;
                ELSE
                    INSERT INTO analytics.profitability_data_quality_daily (check_date, check_month, applies_to, check_type, severity, record_count, detail)
                    VALUES (v_month_start, v_month_start, pool_type, 'WEIGHT_SUM_INVALID', 'ERROR', 1, jsonb_build_object('msg', 'Total headcount basis pool is zero or empty', 'basis', v_rs_basis));
                END IF;

                DROP TABLE IF EXISTS tmp_hc_basis;
            END IF;
        END LOOP;
    END LOOP;
END;
$$;
CREATE OR REPLACE PROCEDURE analytics.internal_refresh_fact_branch_profit_final_monthly(p_months DATE[])
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    m DATE;
    v_month_start DATE;
    v_month_end DATE;
    v_total_unassigned_op NUMERIC := 0;
    v_total_unassigned_pay NUMERIC := 0;
    v_sum_shared_op NUMERIC := 0;
    v_sum_shared_pay NUMERIC := 0;
    v_rs_op UUID;
    v_rs_pay UUID;
    v_total_direct NUMERIC := 0;
    v_large_unassigned_threshold NUMERIC := 0.5;
BEGIN
    IF array_length(p_months, 1) IS NULL THEN
        RETURN;
    END IF;

    FOR i IN 1..array_length(p_months, 1) LOOP
        m := date_trunc('month', p_months[i])::DATE;
        v_month_start := m;
        v_month_end := (m + interval '1 month' - interval '1 day')::DATE;

        DELETE FROM analytics.fact_branch_profit_final_monthly WHERE month_start = m;
        DELETE FROM analytics.profitability_data_quality_daily WHERE check_month = m AND check_type = 'large_unassigned_shared_pool';

        SELECT COALESCE(SUM(direct_operating_exp), 0), COALESCE(SUM(direct_payroll_exp), 0)
        INTO v_total_unassigned_op, v_total_unassigned_pay
        FROM analytics.fact_branch_profit_daily
        WHERE profit_date >= v_month_start AND profit_date <= v_month_end
          AND branch_id IS NULL;

        SELECT rule_set_id INTO v_rs_op
        FROM analytics.snapshot_branch_allocation_weights_monthly
        WHERE month_start = m AND applies_to = 'operating_expenses'
        ORDER BY rule_set_id
        LIMIT 1;

        SELECT rule_set_id INTO v_rs_pay
        FROM analytics.snapshot_branch_allocation_weights_monthly
        WHERE month_start = m AND applies_to = 'payroll_expenses'
        ORDER BY rule_set_id
        LIMIT 1;

        DROP TABLE IF EXISTS tmp_branch_aggregates;

        CREATE TEMP TABLE tmp_branch_aggregates ON COMMIT DROP AS
        SELECT branch_id,
               SUM(gross_revenue) AS direct_gross_revenue,
               SUM(gross_cogs) AS direct_gross_cogs,
               SUM(gross_profit) AS direct_gross_profit,
               SUM(direct_operating_exp) AS direct_operating_exp,
               SUM(direct_payroll_exp) AS direct_payroll_exp
        FROM analytics.fact_branch_profit_daily
        WHERE profit_date >= v_month_start AND profit_date <= v_month_end
          AND branch_id IS NOT NULL
        GROUP BY branch_id;

        INSERT INTO analytics.fact_branch_profit_final_monthly (
            month_start, branch_id,
            direct_gross_revenue, direct_gross_cogs, direct_gross_profit,
            direct_operating_exp, direct_payroll_exp,
            allocated_shared_op, allocated_shared_pay,
            unallocated_shared_op, unallocated_shared_pay,
            rule_set_id_op, rule_set_id_pay
        )
        SELECT
            v_month_start, t.branch_id,
            t.direct_gross_revenue, t.direct_gross_cogs, t.direct_gross_profit,
            t.direct_operating_exp, t.direct_payroll_exp,
            ROUND(v_total_unassigned_op * COALESCE(sw_op.computed_weight, 0), 2) AS allocated_shared_op,
            ROUND(v_total_unassigned_pay * COALESCE(sw_pay.computed_weight, 0), 2) AS allocated_shared_pay,
            0, 0,
            v_rs_op, v_rs_pay
        FROM tmp_branch_aggregates t
        LEFT JOIN analytics.snapshot_branch_allocation_weights_monthly sw_op
               ON sw_op.branch_id = t.branch_id AND sw_op.month_start = m AND sw_op.applies_to = 'operating_expenses'
        LEFT JOIN analytics.snapshot_branch_allocation_weights_monthly sw_pay
               ON sw_pay.branch_id = t.branch_id AND sw_pay.month_start = m AND sw_pay.applies_to = 'payroll_expenses';

        SELECT COALESCE(SUM(allocated_shared_op), 0), COALESCE(SUM(allocated_shared_pay), 0)
        INTO v_sum_shared_op, v_sum_shared_pay
        FROM analytics.fact_branch_profit_final_monthly
        WHERE month_start = m AND branch_id IS NOT NULL;

        IF (v_total_unassigned_op - v_sum_shared_op) > 0 OR (v_total_unassigned_pay - v_sum_shared_pay) > 0 THEN
            INSERT INTO analytics.fact_branch_profit_final_monthly (
                month_start, branch_id,
                direct_gross_revenue, direct_gross_cogs, direct_gross_profit,
                direct_operating_exp, direct_payroll_exp,
                allocated_shared_op, allocated_shared_pay,
                unallocated_shared_op, unallocated_shared_pay,
                rule_set_id_op, rule_set_id_pay
            )
            VALUES (
                v_month_start, NULL,
                0, 0, 0,
                0, 0,
                0, 0,
                v_total_unassigned_op - v_sum_shared_op,
                v_total_unassigned_pay - v_sum_shared_pay,
                NULL, NULL
            );
        END IF;

        SELECT COALESCE(SUM(direct_operating_exp + direct_payroll_exp), 0)
        INTO v_total_direct
        FROM tmp_branch_aggregates;

        IF (v_total_unassigned_op + v_total_unassigned_pay) > 0
           AND (v_total_unassigned_op + v_total_unassigned_pay) > (v_total_direct * v_large_unassigned_threshold) THEN
            INSERT INTO analytics.profitability_data_quality_daily (check_date, check_month, applies_to, check_type, severity, record_count, detail)
            VALUES (v_month_start, v_month_start, 'both', 'large_unassigned_shared_pool', 'WARNING', 1,
                    jsonb_build_object('unassigned_sum', v_total_unassigned_op + v_total_unassigned_pay, 'direct_sum', v_total_direct));
        END IF;

        DROP TABLE IF EXISTS tmp_branch_aggregates;
    END LOOP;
END;
$$;
CREATE OR REPLACE PROCEDURE analytics.internal_refresh_fact_branch_profit_daily(
    p_target_dates DATE[]
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_op_ids UUID[];
    v_pay_ids UUID[];
BEGIN
    IF array_length(p_target_dates, 1) IS NULL THEN
        RETURN;
    END IF;

    SELECT array_agg(id) INTO v_op_ids
    FROM public.chart_of_accounts
    WHERE code IN ('5200', '5210', '5220', '5230');

    SELECT array_agg(id) INTO v_pay_ids
    FROM public.chart_of_accounts
    WHERE code IN ('5310', '5320', '5330', '5335');

    DELETE FROM analytics.fact_branch_profit_daily
    WHERE profit_date = ANY(p_target_dates);

    DROP TABLE IF EXISTS tmp_bpd_gp_agg;
    DROP TABLE IF EXISTS tmp_bpd_op_exp_agg;
    DROP TABLE IF EXISTS tmp_bpd_pay_exp_agg;
    DROP TABLE IF EXISTS tmp_bpd_all_keys;

    CREATE TEMP TABLE tmp_bpd_gp_agg ON COMMIT DROP AS
    SELECT
        sale_date AS profit_date,
        branch_id,
        SUM(net_revenue) AS gross_revenue,
        SUM(net_cogs) AS gross_cogs,
        SUM(gross_profit) AS gross_profit
    FROM analytics.fact_gross_profit_daily_grain
    WHERE sale_date = ANY(p_target_dates)
    GROUP BY sale_date, branch_id;

    CREATE TEMP TABLE tmp_bpd_op_exp_agg ON COMMIT DROP AS
    SELECT
        je.entry_date AS profit_date,
        e.branch_id,
        SUM(jel.debit) AS direct_op
    FROM public.journal_entries je
    JOIN public.journal_entry_lines jel ON jel.entry_id = je.id
    JOIN public.expenses e
      ON je.source_type = 'expense'
     AND je.source_id = e.id
    WHERE je.status = 'posted'
      AND je.entry_date = ANY(p_target_dates)
      AND jel.account_id = ANY(v_op_ids)
    GROUP BY je.entry_date, e.branch_id;

    CREATE TEMP TABLE tmp_bpd_pay_exp_agg ON COMMIT DROP AS
    SELECT
        je.entry_date AS profit_date,
        pr.branch_id,
        SUM(jel.debit) AS direct_pay
    FROM public.journal_entries je
    JOIN public.journal_entry_lines jel ON jel.entry_id = je.id
    JOIN public.hr_payroll_runs pr
      ON pr.id = je.source_id
     AND je.source_type IN ('hr_payroll', 'manual')
    WHERE je.status = 'posted'
      AND je.entry_date = ANY(p_target_dates)
      AND jel.account_id = ANY(v_pay_ids)
    GROUP BY je.entry_date, pr.branch_id;

    CREATE TEMP TABLE tmp_bpd_all_keys ON COMMIT DROP AS
    SELECT profit_date, branch_id FROM tmp_bpd_gp_agg
    UNION
    SELECT profit_date, branch_id FROM tmp_bpd_op_exp_agg
    UNION
    SELECT profit_date, branch_id FROM tmp_bpd_pay_exp_agg;

    INSERT INTO analytics.fact_branch_profit_daily (
        profit_date, branch_id,
        gross_revenue, gross_cogs, gross_profit,
        direct_operating_exp, direct_payroll_exp
    )
    SELECT
        k.profit_date,
        k.branch_id,
        COALESCE(g.gross_revenue, 0),
        COALESCE(g.gross_cogs, 0),
        COALESCE(g.gross_profit, 0),
        COALESCE(o.direct_op, 0),
        COALESCE(p.direct_pay, 0)
    FROM tmp_bpd_all_keys k
    LEFT JOIN tmp_bpd_gp_agg g
           ON g.profit_date = k.profit_date
          AND (g.branch_id = k.branch_id OR (g.branch_id IS NULL AND k.branch_id IS NULL))
    LEFT JOIN tmp_bpd_op_exp_agg o
           ON o.profit_date = k.profit_date
          AND (o.branch_id = k.branch_id OR (o.branch_id IS NULL AND k.branch_id IS NULL))
    LEFT JOIN tmp_bpd_pay_exp_agg p
           ON p.profit_date = k.profit_date
          AND (p.branch_id = k.branch_id OR (p.branch_id IS NULL AND k.branch_id IS NULL))
    WHERE k.branch_id IS NOT NULL
    ON CONFLICT (profit_date, branch_id)
        WHERE branch_id IS NOT NULL
    DO UPDATE SET
        gross_revenue = EXCLUDED.gross_revenue,
        gross_cogs = EXCLUDED.gross_cogs,
        gross_profit = EXCLUDED.gross_profit,
        direct_operating_exp = EXCLUDED.direct_operating_exp,
        direct_payroll_exp = EXCLUDED.direct_payroll_exp,
        updated_at = now();

    INSERT INTO analytics.fact_branch_profit_daily (
        profit_date, branch_id,
        gross_revenue, gross_cogs, gross_profit,
        direct_operating_exp, direct_payroll_exp
    )
    SELECT
        k.profit_date,
        NULL::UUID,
        COALESCE(g.gross_revenue, 0),
        COALESCE(g.gross_cogs, 0),
        COALESCE(g.gross_profit, 0),
        COALESCE(o.direct_op, 0),
        COALESCE(p.direct_pay, 0)
    FROM tmp_bpd_all_keys k
    LEFT JOIN tmp_bpd_gp_agg g
           ON g.profit_date = k.profit_date
          AND g.branch_id IS NULL
    LEFT JOIN tmp_bpd_op_exp_agg o
           ON o.profit_date = k.profit_date
          AND o.branch_id IS NULL
    LEFT JOIN tmp_bpd_pay_exp_agg p
           ON p.profit_date = k.profit_date
          AND p.branch_id IS NULL
    WHERE k.branch_id IS NULL
    ON CONFLICT (profit_date)
        WHERE branch_id IS NULL
    DO UPDATE SET
        gross_revenue = EXCLUDED.gross_revenue,
        gross_cogs = EXCLUDED.gross_cogs,
        gross_profit = EXCLUDED.gross_profit,
        direct_operating_exp = EXCLUDED.direct_operating_exp,
        direct_payroll_exp = EXCLUDED.direct_payroll_exp,
        updated_at = now();
END;
$$;
CREATE OR REPLACE PROCEDURE analytics.compute_double_review_trust_state(
    p_run_id       UUID,
    p_job_name     TEXT,
    p_target_dates DATE[]
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    -- متغيرات مشتركة
    v_analytics_rev_val NUMERIC := 0; v_ledger_rev_val NUMERIC := 0;
    v_analytics_tax_val NUMERIC := 0; v_ledger_tax_val NUMERIC := 0;
    v_analytics_ar_val  NUMERIC := 0; v_ledger_ar_val  NUMERIC := 0;
    v_drift_rev NUMERIC := 0; v_drift_tax NUMERIC := 0; v_drift_ar NUMERIC := 0;

    v_analytics_val NUMERIC := 0; v_ledger_val NUMERIC := 0; v_drift NUMERIC := 0;
    v_final_state TEXT := 'VERIFIED';

    -- متغيرات المرحلة الثانية
    -- fact_gross_profit_daily_grain
    v_fact_gp_revenue   NUMERIC := 0;
    v_src_gp_revenue    NUMERIC := 0;
    v_drift_gp_revenue  NUMERIC := 0;

    v_fact_gp_cogs      NUMERIC := 0;
    v_src_gp_cogs       NUMERIC := 0;
    v_drift_gp_cogs     NUMERIC := 0;

    v_fact_gp_profit    NUMERIC := 0;
    v_src_gp_profit     NUMERIC := 0;
    v_drift_gp_profit   NUMERIC := 0;

    -- fact_branch_profit_daily
    v_fact_branch_gp    NUMERIC := 0;
    v_grain_branch_gp   NUMERIC := 0;
    v_drift_branch_gp   NUMERIC := 0;

    v_fact_branch_op    NUMERIC := 0;
    v_je_branch_op      NUMERIC := 0;
    v_drift_branch_op   NUMERIC := 0;

    v_fact_branch_pay   NUMERIC := 0;
    v_je_branch_pay     NUMERIC := 0;
    v_drift_branch_pay  NUMERIC := 0;

    v_op_ids  UUID[];
    v_pay_ids UUID[];
BEGIN

    -- ══════════════════════════════════════════════════════════
    -- BRANCH 1: fact_sales_daily_grain
    -- يطابق صافي الإيراد التحليلي مع الدفتر وفق البنية المحاسبية الحالية:
    --   4100 إيراد إجمالي
    -- - 4300 خصومات مبيعات
    -- - 4200 مرتجعات مبيعات
    -- ══════════════════════════════════════════════════════════
    IF p_job_name = 'fact_sales_daily_grain' THEN
        SELECT COALESCE(SUM(net_tax_exclusive_revenue), 0) INTO v_analytics_rev_val FROM analytics.fact_sales_daily_grain WHERE date = ANY(p_target_dates);
        SELECT COALESCE(SUM(tax_amount), 0)                INTO v_analytics_tax_val FROM analytics.fact_sales_daily_grain WHERE date = ANY(p_target_dates);
        SELECT COALESCE(SUM(ar_credit_portion_amount), 0)  INTO v_analytics_ar_val  FROM analytics.fact_sales_daily_grain WHERE date = ANY(p_target_dates);

        WITH target_dates AS (SELECT unnest(p_target_dates) AS tgt_date),
        gl_agg AS (
            SELECT td.tgt_date as origin_date, coa.code,
                   SUM(jel.credit) as cr_sum, SUM(jel.debit) as cr_debit
            FROM target_dates td
            JOIN public.sales_orders so ON (
                 (so.delivered_at IS NOT NULL AND so.delivered_at >= (td.tgt_date::timestamp AT TIME ZONE 'Africa/Cairo') AND so.delivered_at < ((td.tgt_date + 1)::timestamp AT TIME ZONE 'Africa/Cairo'))
                 OR (so.delivered_at IS NULL AND so.order_date = td.tgt_date)
            )
            JOIN public.journal_entries     je  ON je.source_id = so.id AND je.source_type = 'sales_order'
            JOIN public.journal_entry_lines jel ON je.id = jel.entry_id
            JOIN public.chart_of_accounts   coa ON coa.id = jel.account_id
            WHERE je.status = 'posted' AND coa.code IN ('4100', '4300', '2200', '1200')
            GROUP BY 1, 2
        ),
        gl_returns AS (
            SELECT td.tgt_date as origin_date, coa.code, SUM(jel.debit) as ret_debit
            FROM target_dates td
            JOIN public.sales_orders so ON (
                 (so.delivered_at IS NOT NULL AND so.delivered_at >= (td.tgt_date::timestamp AT TIME ZONE 'Africa/Cairo') AND so.delivered_at < ((td.tgt_date + 1)::timestamp AT TIME ZONE 'Africa/Cairo'))
                 OR (so.delivered_at IS NULL AND so.order_date = td.tgt_date)
            )
            JOIN public.sales_returns       sr  ON sr.order_id = so.id
            JOIN public.journal_entries     je  ON je.source_id = sr.id AND je.source_type = 'sales_return'
            JOIN public.journal_entry_lines jel ON je.id = jel.entry_id
            JOIN public.chart_of_accounts   coa ON coa.id = jel.account_id
            WHERE je.status = 'posted' AND coa.code = '4200'
            GROUP BY 1, 2
        )
        SELECT
            COALESCE((SELECT SUM(cr_sum)  FROM gl_agg     WHERE code = '4100'), 0)
            - COALESCE((SELECT SUM(cr_debit) FROM gl_agg  WHERE code = '4300'), 0)
            - COALESCE((SELECT SUM(ret_debit) FROM gl_returns WHERE code = '4200'), 0),
            COALESCE((SELECT SUM(cr_sum)  FROM gl_agg     WHERE code = '2200'), 0),
            COALESCE((SELECT SUM(cr_debit) FROM gl_agg    WHERE code = '1200'), 0)
        INTO v_ledger_rev_val, v_ledger_tax_val, v_ledger_ar_val;

        v_drift_rev := ROUND(v_analytics_rev_val - v_ledger_rev_val, 2);
        v_drift_tax := ROUND(v_analytics_tax_val - v_ledger_tax_val, 2);
        v_drift_ar  := ROUND(v_analytics_ar_val  - v_ledger_ar_val,  2);

        IF v_drift_rev = 0 AND v_drift_tax = 0 AND v_drift_ar = 0 THEN
            v_final_state := 'POSTING_CONSISTENCY_ONLY';
        ELSEIF ABS(v_drift_rev) <= 5.0 AND ABS(v_drift_tax) <= 5.0 AND ABS(v_drift_ar) <= 5.0 THEN
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
                'ar_creation',jsonb_build_object('status', CASE WHEN ABS(v_drift_ar)  <= 0 THEN 'VERIFIED'                 WHEN ABS(v_drift_ar) <= 5.0  THEN 'RECONCILED_WITH_WARNING' ELSE 'BLOCKED' END, 'drift_value', v_drift_ar)
            ),
            log_output = COALESCE(log_output, '{}'::jsonb) || jsonb_build_object(
                'rev_fact', v_analytics_rev_val, 'rev_gl', v_ledger_rev_val, 'drift_rev', v_drift_rev,
                'tax_fact', v_analytics_tax_val, 'tax_gl', v_ledger_tax_val, 'drift_tax', v_drift_tax,
                'ar_fact',  v_analytics_ar_val,  'ar_gl',  v_ledger_ar_val,  'drift_ar',  v_drift_ar
            )
        WHERE id = p_run_id;

    -- ══════════════════════════════════════════════════════════
    -- BRANCH 2: fact_treasury_cashflow_daily (من 88 — بدون تغيير)
    -- ══════════════════════════════════════════════════════════
    ELSIF p_job_name = 'fact_treasury_cashflow_daily' THEN
        SELECT COALESCE(SUM(net_cashflow), 0) INTO v_analytics_val
        FROM analytics.fact_treasury_cashflow_daily
        WHERE treasury_date = ANY(p_target_dates);

        SELECT
            COALESCE((SELECT SUM(amount) FROM public.vault_transactions vt JOIN unnest(p_target_dates) AS td ON vt.created_at >= (td::timestamp AT TIME ZONE 'Africa/Cairo') AND vt.created_at < ((td + 1)::timestamp AT TIME ZONE 'Africa/Cairo') WHERE vt.type = 'collection'), 0)
            + COALESCE((SELECT SUM(amount) FROM public.custody_transactions ct JOIN unnest(p_target_dates) AS td ON ct.created_at >= (td::timestamp AT TIME ZONE 'Africa/Cairo') AND ct.created_at < ((td + 1)::timestamp AT TIME ZONE 'Africa/Cairo') WHERE ct.type = 'collection'), 0)
            - COALESCE((SELECT SUM(amount) FROM public.vault_transactions vt JOIN unnest(p_target_dates) AS td ON vt.created_at >= (td::timestamp AT TIME ZONE 'Africa/Cairo') AND vt.created_at < ((td + 1)::timestamp AT TIME ZONE 'Africa/Cairo') WHERE vt.type = 'withdrawal' AND vt.reference_type = 'sales_return'), 0)
            - COALESCE((SELECT SUM(amount) FROM public.custody_transactions ct JOIN unnest(p_target_dates) AS td ON ct.created_at >= (td::timestamp AT TIME ZONE 'Africa/Cairo') AND ct.created_at < ((td + 1)::timestamp AT TIME ZONE 'Africa/Cairo') WHERE ct.type = 'expense' AND ct.reference_type = 'sales_return'), 0)
        INTO v_ledger_val;

        v_drift := ROUND(v_analytics_val - v_ledger_val, 2);

        IF    v_drift = 0          THEN v_final_state := 'VERIFIED';
        ELSIF ABS(v_drift) <= 5.0  THEN v_final_state := 'RECONCILED_WITH_WARNING';
        ELSE                            v_final_state := 'BLOCKED';
        END IF;

        UPDATE analytics.etl_runs
        SET drift_value   = ABS(v_drift),
            status        = v_final_state,
            metric_states = jsonb_build_object(
                'net_collection', jsonb_build_object(
                    'status', CASE WHEN ABS(v_drift) <= 0 THEN 'VERIFIED' WHEN ABS(v_drift) <= 5.0 THEN 'RECONCILED_WITH_WARNING' ELSE 'BLOCKED' END,
                    'drift_value', v_drift)
            ),
            log_output = COALESCE(log_output, '{}'::jsonb) || jsonb_build_object(
                'val_fact', v_analytics_val, 'val_gl', v_ledger_val, 'drift', v_drift
            )
        WHERE id = p_run_id;

    -- ══════════════════════════════════════════════════════════
    -- BRANCH 3: fact_profit_daily — مراجعة تكلفة (Phase 1 COGS — من 88)
    -- ══════════════════════════════════════════════════════════
    ELSIF p_job_name = 'fact_profit_daily' THEN
        SELECT COALESCE(SUM(cogs), 0) INTO v_analytics_val
        FROM analytics.fact_profit_daily
        WHERE date = ANY(p_target_dates);

        WITH target_dates AS (SELECT unnest(p_target_dates) AS tgt_date)
        SELECT COALESCE(SUM(jel.debit), 0) INTO v_ledger_val
        FROM target_dates td
        JOIN public.journal_entries     je  ON je.entry_date = td.tgt_date
        JOIN public.journal_entry_lines jel ON je.id = jel.entry_id
        JOIN public.chart_of_accounts   coa ON coa.id = jel.account_id
        WHERE je.status = 'posted' AND coa.code = '5100';

        v_drift := ROUND(v_analytics_val - v_ledger_val, 2);

        IF    v_drift = 0          THEN v_final_state := 'POSTING_CONSISTENCY_ONLY';
        ELSIF ABS(v_drift) <= 5.0  THEN v_final_state := 'RECONCILED_WITH_WARNING';
        ELSE                            v_final_state := 'BLOCKED';
        END IF;

        UPDATE analytics.etl_runs
        SET drift_value   = ABS(v_drift),
            status        = v_final_state,
            metric_states = jsonb_build_object(
                'cogs_check', jsonb_build_object(
                    'status', CASE WHEN ABS(v_drift) <= 0 THEN 'POSTING_CONSISTENCY_ONLY' WHEN ABS(v_drift) <= 5.0 THEN 'RECONCILED_WITH_WARNING' ELSE 'BLOCKED' END,
                    'drift_value', v_drift,
                    'scope', 'cogs_only_phase1'
                )
            ),
            log_output = COALESCE(log_output, '{}'::jsonb) || jsonb_build_object(
                'cogs_fact', v_analytics_val,
                'cogs_gl',   v_ledger_val,
                'drift',     v_drift,
                'note',      'مراجعة تكلفة فقط — المرحلة الأولى'
            )
        WHERE id = p_run_id;

    -- ══════════════════════════════════════════════════════════
    -- BRANCH 4: fact_gross_profit_daily_grain — تحقق داخلي ثلاثي
    --
    -- يعيد حساب net_revenue + net_cogs من مصدرين منفصلين بتاريخ مستقل:
    --   مبيعات: delivered_at/order_date في p_target_dates
    --   مرتجعات: sr.confirmed_at (Cairo) في p_target_dates — تاريخ الاعتماد المحاسبي
    -- ثم يقارن النتيجة بما في الجدول
    -- الحالة عند drift=0: POSTING_CONSISTENCY_ONLY (اتساق داخلي — لا اعتماد دفتري)
    -- ══════════════════════════════════════════════════════════
    ELSIF p_job_name = 'fact_gross_profit_daily_grain' THEN

        -- ── قراءة ما في الجدول ──────────────────────────────
        SELECT
            COALESCE(SUM(net_revenue),  0),
            COALESCE(SUM(net_cogs),     0),
            COALESCE(SUM(gross_profit), 0)
        INTO v_fact_gp_revenue, v_fact_gp_cogs, v_fact_gp_profit
        FROM analytics.fact_gross_profit_daily_grain
        WHERE sale_date = ANY(p_target_dates);

        -- ── إعادة التجميع من المصادر بمسارين منفصلين ────────
        -- PATH 1: مبيعات (p_target_dates على yom البيع)
        -- PATH 2: مرتجعات (p_target_dates على yom المرتجع الفعلي)
        WITH sales_src AS (
            SELECT
                COALESCE(SUM(soi.line_total), 0)                                     AS src_gross_rev,
                COALESCE(SUM(COALESCE(soi.unit_cost_at_sale, 0) * soi.base_quantity), 0) AS src_gross_cogs
            FROM public.sales_orders      so
            JOIN public.sales_order_items soi ON soi.order_id = so.id
            JOIN unnest(p_target_dates)   AS tgt_date
              ON (
                    (so.delivered_at IS NOT NULL
                        AND so.delivered_at >= (tgt_date::timestamp AT TIME ZONE 'Africa/Cairo')
                        AND so.delivered_at <  ((tgt_date + 1)::timestamp AT TIME ZONE 'Africa/Cairo'))
                 OR (so.delivered_at IS NULL AND so.order_date = tgt_date)
              )
            WHERE so.status IN ('delivered', 'completed')
        ),
        returns_src AS (
            SELECT
                COALESCE(SUM(sri.line_total), 0)                                     AS src_ret_rev,
                COALESCE(SUM(sri.base_quantity * COALESCE(soi.unit_cost_at_sale, 0)), 0) AS src_ret_cogs
            FROM public.sales_return_items sri
            JOIN public.sales_returns       sr  ON sr.id  = sri.return_id
            JOIN public.sales_order_items   soi ON soi.id = sri.order_item_id
            JOIN unnest(p_target_dates)     AS tgt_date
              ON (sr.confirmed_at AT TIME ZONE 'Africa/Cairo')::DATE = tgt_date
            WHERE sr.status = 'confirmed'
        )
        SELECT
            s.src_gross_rev  - r.src_ret_rev,
            s.src_gross_cogs - r.src_ret_cogs,
            (s.src_gross_rev - r.src_ret_rev) - (s.src_gross_cogs - r.src_ret_cogs)
        INTO v_src_gp_revenue, v_src_gp_cogs, v_src_gp_profit
        FROM sales_src s, returns_src r;

        v_drift_gp_revenue := ROUND(v_fact_gp_revenue - v_src_gp_revenue, 2);
        v_drift_gp_cogs    := ROUND(v_fact_gp_cogs    - v_src_gp_cogs,    2);
        v_drift_gp_profit  := ROUND(v_fact_gp_profit  - v_src_gp_profit,  2);

        -- POSTING_CONSISTENCY_ONLY عند drift=0: اتساق داخلي تحليلي — ليس اعتمادًا دفتريًا
        IF v_drift_gp_revenue = 0 AND v_drift_gp_cogs = 0 AND v_drift_gp_profit = 0 THEN
            v_final_state := 'POSTING_CONSISTENCY_ONLY';
        ELSIF ABS(v_drift_gp_revenue) <= 5.0 AND ABS(v_drift_gp_cogs) <= 5.0 AND ABS(v_drift_gp_profit) <= 5.0 THEN
            v_final_state := 'RECONCILED_WITH_WARNING';
        ELSE
            v_final_state := 'BLOCKED';
        END IF;

        UPDATE analytics.etl_runs
        SET drift_value   = ABS(v_drift_gp_revenue) + ABS(v_drift_gp_cogs) + ABS(v_drift_gp_profit),
            status        = v_final_state,
            metric_states = jsonb_build_object(
                'gp_grain_revenue', jsonb_build_object(
                    'fact_value', v_fact_gp_revenue, 'src_value', v_src_gp_revenue,
                    'drift',      v_drift_gp_revenue,
                    'status', CASE WHEN ABS(v_drift_gp_revenue) = 0 THEN 'POSTING_CONSISTENCY_ONLY' WHEN ABS(v_drift_gp_revenue) <= 5.0 THEN 'RECONCILED_WITH_WARNING' ELSE 'BLOCKED' END
                ),
                'gp_grain_cogs', jsonb_build_object(
                    'fact_value', v_fact_gp_cogs,    'src_value', v_src_gp_cogs,
                    'drift',      v_drift_gp_cogs,
                    'status', CASE WHEN ABS(v_drift_gp_cogs) = 0 THEN 'POSTING_CONSISTENCY_ONLY' WHEN ABS(v_drift_gp_cogs) <= 5.0 THEN 'RECONCILED_WITH_WARNING' ELSE 'BLOCKED' END
                ),
                'gp_grain_profit', jsonb_build_object(
                    'fact_value', v_fact_gp_profit,  'src_value', v_src_gp_profit,
                    'drift',      v_drift_gp_profit,
                    'status', CASE WHEN ABS(v_drift_gp_profit) = 0 THEN 'POSTING_CONSISTENCY_ONLY' WHEN ABS(v_drift_gp_profit) <= 5.0 THEN 'RECONCILED_WITH_WARNING' ELSE 'BLOCKED' END
                )
            ),
            log_output = COALESCE(log_output, '{}'::jsonb) || jsonb_build_object(
                'fact_gp_revenue', v_fact_gp_revenue, 'src_gp_revenue', v_src_gp_revenue, 'drift_revenue', v_drift_gp_revenue,
                'fact_gp_cogs',    v_fact_gp_cogs,    'src_gp_cogs',    v_src_gp_cogs,    'drift_cogs',    v_drift_gp_cogs,
                'fact_gp_profit',  v_fact_gp_profit,  'src_gp_profit',  v_src_gp_profit,  'drift_profit',  v_drift_gp_profit,
                'note', 'اتساق داخلي ثلاثي (مبيعات بتاريخ البيع + مرتجعات بتاريخ المرتجع) — POSTING_CONSISTENCY_ONLY عند صفر انحراف'
            )
        WHERE id = p_run_id;

    -- ══════════════════════════════════════════════════════════
    -- BRANCH 5: fact_branch_profit_daily — تحقق فعلي ثلاثي
    --
    -- يتحقق من:
    --  (a) gross_profit == SUM من fact_gross_profit_daily_grain
    --  (b) direct_operating_exp == SUM من journal_entries (5200 series)
    --  (c) direct_payroll_exp   == SUM من journal_entries (5310-5335)
    -- ══════════════════════════════════════════════════════════
    ELSIF p_job_name = 'fact_branch_profit_daily' THEN

        -- ترجمة رموز الحسابات
        SELECT array_agg(id) INTO v_op_ids
        FROM public.chart_of_accounts
        WHERE code IN ('5200','5210','5220','5230');

        SELECT array_agg(id) INTO v_pay_ids
        FROM public.chart_of_accounts
        WHERE code IN ('5310','5320','5330','5335');

        -- ── (a) فحص gross_profit ────────────────────────────
        -- ما في جدول الفرع
        SELECT COALESCE(SUM(gross_profit), 0)
        INTO v_fact_branch_gp
        FROM analytics.fact_branch_profit_daily
        WHERE profit_date = ANY(p_target_dates);

        -- ما في مصدره (grain مجمعًا)
        SELECT COALESCE(SUM(gross_profit), 0)
        INTO v_grain_branch_gp
        FROM analytics.fact_gross_profit_daily_grain
        WHERE sale_date = ANY(p_target_dates);

        v_drift_branch_gp := ROUND(v_fact_branch_gp - v_grain_branch_gp, 2);

        -- ── (b) فحص direct_operating_exp ────────────────────
        SELECT COALESCE(SUM(direct_operating_exp), 0)
        INTO v_fact_branch_op
        FROM analytics.fact_branch_profit_daily
        WHERE profit_date = ANY(p_target_dates);

        SELECT COALESCE(SUM(jel.debit), 0)
        INTO v_je_branch_op
        FROM public.journal_entries     je
        JOIN public.journal_entry_lines jel ON jel.entry_id = je.id
        WHERE je.status     = 'posted'
          AND je.entry_date = ANY(p_target_dates)
          AND jel.account_id = ANY(v_op_ids);

        v_drift_branch_op := ROUND(v_fact_branch_op - v_je_branch_op, 2);

        -- ── (c) فحص direct_payroll_exp ──────────────────────
        SELECT COALESCE(SUM(direct_payroll_exp), 0)
        INTO v_fact_branch_pay
        FROM analytics.fact_branch_profit_daily
        WHERE profit_date = ANY(p_target_dates);

        SELECT COALESCE(SUM(jel.debit), 0)
        INTO v_je_branch_pay
        FROM public.journal_entries     je
        JOIN public.journal_entry_lines jel ON jel.entry_id = je.id
        WHERE je.status     = 'posted'
          AND je.entry_date = ANY(p_target_dates)
          AND jel.account_id = ANY(v_pay_ids);

        v_drift_branch_pay := ROUND(v_fact_branch_pay - v_je_branch_pay, 2);

        -- ── تحديد الحالة النهائية ────────────────────────────
        -- POSTING_CONSISTENCY_ONLY: اتساق داخلي — ليس اعتمادًا دفتريًا نهائيًا
        IF v_drift_branch_gp = 0 AND v_drift_branch_op = 0 AND v_drift_branch_pay = 0 THEN
            v_final_state := 'POSTING_CONSISTENCY_ONLY';
        ELSIF ABS(v_drift_branch_gp) <= 5.0 AND ABS(v_drift_branch_op) <= 5.0 AND ABS(v_drift_branch_pay) <= 5.0 THEN
            v_final_state := 'RECONCILED_WITH_WARNING';
        ELSE
            v_final_state := 'BLOCKED';
        END IF;

        UPDATE analytics.etl_runs
        SET drift_value   = ABS(v_drift_branch_gp) + ABS(v_drift_branch_op) + ABS(v_drift_branch_pay),
            status        = v_final_state,
            metric_states = jsonb_build_object(
                'branch_gross_profit', jsonb_build_object(
                    'fact_value',  v_fact_branch_gp,
                    'grain_value', v_grain_branch_gp,
                    'drift',       v_drift_branch_gp,
                    'status', CASE WHEN ABS(v_drift_branch_gp) = 0 THEN 'POSTING_CONSISTENCY_ONLY' WHEN ABS(v_drift_branch_gp) <= 5.0 THEN 'RECONCILED_WITH_WARNING' ELSE 'BLOCKED' END
                ),
                'branch_direct_op_exp', jsonb_build_object(
                    'fact_value',  v_fact_branch_op,
                    'je_value',    v_je_branch_op,
                    'drift',       v_drift_branch_op,
                    'status', CASE WHEN ABS(v_drift_branch_op) = 0 THEN 'POSTING_CONSISTENCY_ONLY' WHEN ABS(v_drift_branch_op) <= 5.0 THEN 'RECONCILED_WITH_WARNING' ELSE 'BLOCKED' END
                ),
                'branch_direct_pay_exp', jsonb_build_object(
                    'fact_value',  v_fact_branch_pay,
                    'je_value',    v_je_branch_pay,
                    'drift',       v_drift_branch_pay,
                    'status', CASE WHEN ABS(v_drift_branch_pay) = 0 THEN 'POSTING_CONSISTENCY_ONLY' WHEN ABS(v_drift_branch_pay) <= 5.0 THEN 'RECONCILED_WITH_WARNING' ELSE 'BLOCKED' END
                )
            ),
            log_output = COALESCE(log_output, '{}'::jsonb) || jsonb_build_object(
                'fact_branch_gp',  v_fact_branch_gp,  'grain_gp',   v_grain_branch_gp, 'drift_gp',  v_drift_branch_gp,
                'fact_branch_op',  v_fact_branch_op,  'je_op',      v_je_branch_op,    'drift_op',  v_drift_branch_op,
                'fact_branch_pay', v_fact_branch_pay, 'je_pay',     v_je_branch_pay,   'drift_pay', v_drift_branch_pay,
                'note', 'اتساق داخلي ثلاثي: gross_profit من grain + op/pay من journal_entries — POSTING_CONSISTENCY_ONLY عند صفر انحراف'
            )
        WHERE id = p_run_id;
    -- ══════════════════════════════════════════════════════════
    -- BRANCH 6: snapshot_branch_allocation_weights_monthly
    -- ══════════════════════════════════════════════════════════
    ELSIF p_job_name = 'snapshot_branch_allocation_weights_monthly' THEN
        DECLARE
            v_monthly_month DATE;
            v_pool TEXT;
            v_weight_sum NUMERIC;
            v_has_error BOOLEAN := false;
            v_blocked BOOLEAN := false;
            v_total_months_checked INT := 0;
            v_failed_months INT := 0;
            v_warn_months INT := 0;
        BEGIN
            FOR v_monthly_month IN SELECT DISTINCT date_trunc('month', d)::DATE FROM unnest(p_target_dates) AS d LOOP
                FOREACH v_pool IN ARRAY ARRAY['operating_expenses', 'payroll_expenses'] LOOP
                    v_total_months_checked := v_total_months_checked + 1;
                    
                    SELECT COALESCE(SUM(computed_weight), 0) INTO v_weight_sum
                    FROM analytics.snapshot_branch_allocation_weights_monthly
                    WHERE month_start = v_monthly_month AND applies_to = v_pool;
                    
                    IF v_weight_sum = 0 THEN
                        -- Check if NO_ACTIVE_RULE or RULE_CONFLICT_BLOCKED error holds
                        PERFORM 1 FROM analytics.profitability_data_quality_daily
                        WHERE check_month = v_monthly_month AND applies_to = v_pool
                          AND check_type IN ('NO_ACTIVE_RULE', 'RULE_CONFLICT_BLOCKED', 'WEIGHT_SUM_INVALID');
                          
                        IF FOUND THEN
                            v_warn_months := v_warn_months + 1;
                        ELSE
                            v_failed_months := v_failed_months + 1;
                        END IF;
                    ELSIF NOT (v_weight_sum BETWEEN 0.9999 AND 1.0001) THEN
                        v_failed_months := v_failed_months + 1;
                    END IF;
                END LOOP;
            END LOOP;
            
            IF v_failed_months > 0 THEN
                v_final_state := 'BLOCKED';
            ELSIF v_warn_months > 0 THEN
                v_final_state := 'RECONCILED_WITH_WARNING';
            ELSE
                v_final_state := 'POSTING_CONSISTENCY_ONLY';
            END IF;

            UPDATE analytics.etl_runs
            SET drift_value = v_failed_months,
                status = v_final_state,
                log_output = COALESCE(log_output, '{}'::jsonb) || jsonb_build_object(
                    'total_checks', v_total_months_checked,
                    'failed_checks', v_failed_months,
                    'note', 'Snapshot Weight Assurance (Phase 3)'
                )
            WHERE id = p_run_id;
        END;

    -- ══════════════════════════════════════════════════════════
    -- BRANCH 7: fact_branch_profit_final_monthly
    -- ══════════════════════════════════════════════════════════
    ELSIF p_job_name = 'fact_branch_profit_final_monthly' THEN
        DECLARE
            v_monthly_month DATE;
            v_direct_gross_profit NUMERIC;
            v_daily_gross_profit NUMERIC;
            v_sum_alloc_op NUMERIC;
            v_daily_pool_op NUMERIC;
            v_sum_alloc_pay NUMERIC;
            v_daily_pool_pay NUMERIC;
            v_unalloc_op NUMERIC;
            v_unalloc_pay NUMERIC;
            v_null_exists INT;
            v_failed_checks INT := 0;
            v_drift_gp NUMERIC;
            v_drift_op NUMERIC;
            v_drift_pay NUMERIC;
        BEGIN
            FOR v_monthly_month IN SELECT DISTINCT date_trunc('month', d)::DATE FROM unnest(p_target_dates) AS d LOOP
                SELECT COALESCE(SUM(direct_gross_profit), 0) INTO v_direct_gross_profit FROM analytics.fact_branch_profit_final_monthly WHERE month_start = v_monthly_month;
                SELECT COALESCE(SUM(gross_profit), 0) INTO v_daily_gross_profit FROM analytics.fact_branch_profit_daily WHERE date_trunc('month', profit_date) = v_monthly_month AND branch_id IS NOT NULL;
                v_drift_gp := ROUND(v_direct_gross_profit - v_daily_gross_profit, 2);
                
                SELECT COALESCE(SUM(allocated_shared_op), 0), COALESCE(SUM(allocated_shared_pay), 0), COALESCE(SUM(unallocated_shared_op), 0), COALESCE(SUM(unallocated_shared_pay), 0)
                INTO v_sum_alloc_op, v_sum_alloc_pay, v_unalloc_op, v_unalloc_pay
                FROM analytics.fact_branch_profit_final_monthly WHERE month_start = v_monthly_month;
                
                SELECT COALESCE(SUM(direct_operating_exp), 0), COALESCE(SUM(direct_payroll_exp), 0)
                INTO v_daily_pool_op, v_daily_pool_pay
                FROM analytics.fact_branch_profit_daily WHERE date_trunc('month', profit_date) = v_monthly_month AND branch_id IS NULL;
                
                v_drift_op := ROUND(v_sum_alloc_op - v_daily_pool_op, 2);
                v_drift_pay := ROUND(v_sum_alloc_pay - v_daily_pool_pay, 2);

                SELECT COUNT(*) INTO v_null_exists FROM analytics.fact_branch_profit_final_monthly WHERE month_start = v_monthly_month AND branch_id IS NULL;

                IF v_drift_gp != 0 OR v_drift_op > 0 OR v_drift_pay > 0 OR ((v_unalloc_op > 0 OR v_unalloc_pay > 0) AND v_null_exists = 0) THEN
                    v_failed_checks := v_failed_checks + 1;
                END IF;
            END LOOP;
            
            IF v_failed_checks > 0 THEN v_final_state := 'BLOCKED';
            ELSE v_final_state := 'POSTING_CONSISTENCY_ONLY'; END IF;

            UPDATE analytics.etl_runs
            SET drift_value = v_failed_checks,
                status = v_final_state,
                log_output = COALESCE(log_output, '{}'::jsonb) || jsonb_build_object(
                    'failed_checks', v_failed_checks,
                    'note', 'Final Monthly Distribution Assurance (Phase 3)'
                )
            WHERE id = p_run_id;
        END;

    -- ══════════════════════════════════════════════════════════
    -- BRANCH 8: profitability_data_quality_daily
    -- ══════════════════════════════════════════════════════════
    ELSIF p_job_name = 'profitability_data_quality_daily' THEN
        DECLARE
            v_err_count INT;
            v_warn_count INT;
        BEGIN
            SELECT count(*) INTO v_err_count FROM analytics.profitability_data_quality_daily WHERE check_date = ANY(p_target_dates) AND severity = 'ERROR';
            SELECT count(*) INTO v_warn_count FROM analytics.profitability_data_quality_daily WHERE check_date = ANY(p_target_dates) AND severity = 'WARNING';

            IF v_err_count > 0 THEN
                v_final_state := 'RECONCILED_WITH_WARNING';  -- Not blocking sweep, just warning
            ELSIF v_warn_count > 0 THEN
                v_final_state := 'RECONCILED_WITH_WARNING';
            ELSE
                v_final_state := 'POSTING_CONSISTENCY_ONLY';
            END IF;

            UPDATE analytics.etl_runs
            SET drift_value = v_err_count + v_warn_count,
                status = v_final_state,
                log_output = COALESCE(log_output, '{}'::jsonb) || jsonb_build_object(
                    'errors', v_err_count,
                    'warnings', v_warn_count,
                    'note', 'Data Quality Assurance (Phase 3)'
                )
            WHERE id = p_run_id;
        END;


    END IF;
END;
$$;
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
    v_target_months    DATE[];
BEGIN
    INSERT INTO analytics.etl_runs (id, table_name, status, started_at)
    VALUES (p_run_id, p_job_name, 'RUNNING', now())
    ON CONFLICT (id) DO UPDATE SET status = 'RUNNING', started_at = now();

    SELECT array_agg(d ORDER BY d ASC) INTO v_normalized_dates
    FROM (SELECT DISTINCT unnest(p_target_dates) AS d) sub;

    v_total := coalesce(array_length(v_normalized_dates, 1), 0);

    IF v_total = 0 THEN
        UPDATE analytics.etl_runs SET status = 'SUCCESS', completed_at = now(), log_output = jsonb_build_object('message', 'No dates to process') WHERE id = p_run_id;
        RETURN;
    END IF;

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
                ELSIF p_job_name = 'snapshot_customer_risk' THEN
                    CALL analytics.internal_refresh_snapshot_customer_risk(v_chunk_dates);
                ELSIF p_job_name = 'snapshot_target_attainment' THEN
                    CALL analytics.internal_refresh_snapshot_target_attainment(v_chunk_dates);
                ELSIF p_job_name = 'fact_geography_daily' THEN
                    CALL analytics.internal_refresh_fact_geography_daily(v_chunk_dates);
                ELSIF p_job_name = 'fact_profit_daily' THEN
                    CALL analytics.internal_refresh_fact_profit_daily(v_chunk_dates);
                ELSIF p_job_name = 'fact_gross_profit_daily_grain' THEN
                    CALL analytics.internal_refresh_fact_gross_profit_daily_grain(v_chunk_dates);
                ELSIF p_job_name = 'fact_branch_profit_daily' THEN
                    CALL analytics.internal_refresh_fact_branch_profit_daily(v_chunk_dates);
                    
                -- ── المرحلة الثالثة ────────────────────────────────
                ELSIF p_job_name = 'profitability_data_quality_daily' THEN
                    CALL analytics.internal_refresh_profitability_data_quality_daily(v_chunk_dates);
                ELSIF p_job_name = 'snapshot_branch_allocation_weights_monthly' THEN
                    SELECT array_agg(d ORDER BY d ASC) INTO v_target_months FROM (SELECT DISTINCT date_trunc('month', unnest(v_chunk_dates))::DATE AS d) sub;
                    CALL analytics.internal_refresh_snapshot_branch_allocation_weights_monthly(v_target_months);
                ELSIF p_job_name = 'fact_branch_profit_final_monthly' THEN
                    SELECT array_agg(d ORDER BY d ASC) INTO v_target_months FROM (SELECT DISTINCT date_trunc('month', unnest(v_chunk_dates))::DATE AS d) sub;
                    CALL analytics.internal_refresh_fact_branch_profit_final_monthly(v_target_months);
                ELSE
                    RAISE EXCEPTION 'Unknown job: %', p_job_name;
                END IF;

                v_chunks_detail := v_chunks_detail || jsonb_build_object('idx', v_chunk_idx, 'count', v_chunk_count, 'min_date', v_min_date, 'max_date', v_max_date, 'status', 'SUCCESS');
            END IF;

            v_chunk_idx := v_chunk_idx + 1;
        END LOOP;

        UPDATE analytics.etl_runs SET status = 'SUCCESS', completed_at = now(), log_output = jsonb_build_object('affected_dates_count', v_total, 'min_affected_date', v_normalized_dates[1], 'max_affected_date', v_normalized_dates[v_total], 'chunks_processed', v_chunk_idx, 'chunks_detail', v_chunks_detail) WHERE id = p_run_id;

        CALL analytics.compute_double_review_trust_state(p_run_id, p_job_name, v_normalized_dates);

    EXCEPTION WHEN OTHERS THEN
        UPDATE analytics.etl_runs SET status = 'FAILED', completed_at = now(), log_output = jsonb_build_object('error', SQLERRM, 'state', SQLSTATE, 'failed_at_chunk_idx', v_chunk_idx, 'total_normalized_dates', v_total) WHERE id = p_run_id;
    END;
END;
$$;
