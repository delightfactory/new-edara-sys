-- ============================================================
-- 96_financial_balance_sheet_rpc.sql
-- EDARA v2 — Financial Balance Sheet & Trial Balance RPCs
-- 
-- Two functions:
--   1. get_financial_summary     → Balance Sheet + Income Statement + Health KPIs (JSONB)
--   2. get_trial_balance_detail  → Trial Balance rows (TABLE)
--
-- Security: finance.journal.read
-- Source of truth: journal_entries (posted) + journal_entry_lines
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- 1. get_financial_summary
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_financial_summary(
  p_as_of_date   DATE DEFAULT CURRENT_DATE,
  p_period_start DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_period_start DATE;

  -- Balance Sheet aggregates (cumulative to p_as_of_date)
  v_total_assets       NUMERIC := 0;
  v_total_liabilities  NUMERIC := 0;
  v_total_equity_gl    NUMERIC := 0;

  -- Unclosed P&L (cumulative to p_as_of_date)
  v_rev_cumulative     NUMERIC := 0;  -- credit - debit for revenue accounts
  v_exp_cumulative     NUMERIC := 0;  -- debit - credit for expense accounts
  v_unclosed_pnl       NUMERIC := 0;

  -- Balance check
  v_balance_diff       NUMERIC := 0;
  v_balance_check      BOOLEAN := false;

  -- Section breakdown (cumulative as-of balances)
  v_cash               NUMERIC := 0;
  v_receivables        NUMERIC := 0;
  v_inventory          NUMERIC := 0;
  v_custody            NUMERIC := 0;
  v_other_assets       NUMERIC := 0;
  v_payables           NUMERIC := 0;
  v_tax_payable        NUMERIC := 0;
  v_emp_liabilities    NUMERIC := 0;
  v_capital            NUMERIC := 0;
  v_retained_earnings  NUMERIC := 0;

  -- Income Statement (period only)
  v_gross_revenue      NUMERIC := 0;
  v_sales_returns      NUMERIC := 0;
  v_sales_discounts    NUMERIC := 0;
  v_cogs               NUMERIC := 0;
  v_operating_exp      NUMERIC := 0;
  v_payroll_exp        NUMERIC := 0;
  v_inventory_adj      NUMERIC := 0;
  v_rounding_diffs     NUMERIC := 0;
  v_net_revenue        NUMERIC := 0;
  v_gross_profit       NUMERIC := 0;
  v_total_expenses     NUMERIC := 0;
  v_net_profit_period  NUMERIC := 0;
  v_gross_margin_pct   NUMERIC := 0;
  v_net_margin_pct     NUMERIC := 0;

  -- Health Indicators (as-of only)
  v_current_assets     NUMERIC := 0;
  v_current_liabs      NUMERIC := 0;
  v_quick_assets       NUMERIC := 0;
  v_current_ratio      NUMERIC := NULL;
  v_quick_ratio        NUMERIC := NULL;
  v_working_capital    NUMERIC := 0;
  v_debt_to_equity     NUMERIC := NULL;
  v_cr_status TEXT; v_qr_status TEXT; v_de_status TEXT;
BEGIN
  -- ── Security ────────────────────────────────────────────────
  IF NOT check_permission(auth.uid(), 'finance.journal.read') THEN
    RAISE EXCEPTION 'Access denied. Requires finance.journal.read';
  END IF;

  -- ── Default period start = first day of current month ───────
  v_period_start := COALESCE(p_period_start, date_trunc('month', p_as_of_date)::DATE);

  -- ══════════════════════════════════════════════════════════════
  -- PART A: Balance Sheet (cumulative to p_as_of_date)
  -- ══════════════════════════════════════════════════════════════
  WITH cumulative AS (
    SELECT coa.code, coa.type,
           COALESCE(SUM(jel.debit), 0)  AS total_debit,
           COALESCE(SUM(jel.credit), 0) AS total_credit
    FROM journal_entry_lines jel
    JOIN journal_entries je ON je.id = jel.entry_id
    JOIN chart_of_accounts coa ON coa.id = jel.account_id
    WHERE je.status = 'posted'
      AND je.entry_date <= p_as_of_date
    GROUP BY coa.code, coa.type
  )
  SELECT
    -- Assets: debit - credit
    COALESCE(SUM(CASE WHEN type = 'asset' THEN total_debit - total_credit END), 0),
    -- Liabilities: credit - debit
    COALESCE(SUM(CASE WHEN type = 'liability' THEN total_credit - total_debit END), 0),
    -- Equity: credit - debit
    COALESCE(SUM(CASE WHEN type = 'equity' THEN total_credit - total_debit END), 0),
    -- Revenue cumulative: credit - debit
    COALESCE(SUM(CASE WHEN type = 'revenue' THEN total_credit - total_debit END), 0),
    -- Expense cumulative: debit - credit
    COALESCE(SUM(CASE WHEN type = 'expense' THEN total_debit - total_credit END), 0),

    -- Section breakdown — Assets
    COALESCE(SUM(CASE WHEN code IN ('1110','1120','1130') THEN total_debit - total_credit END), 0),
    COALESCE(SUM(CASE WHEN code IN ('1200','1210') THEN total_debit - total_credit END), 0),
    COALESCE(SUM(CASE WHEN code = '1300' THEN total_debit - total_credit END), 0),
    COALESCE(SUM(CASE WHEN code = '1400' THEN total_debit - total_credit END), 0),
    COALESCE(SUM(CASE WHEN code IN ('1500','1510') THEN total_debit - total_credit END), 0),

    -- Section breakdown — Liabilities
    COALESCE(SUM(CASE WHEN code IN ('2100','2110') THEN total_credit - total_debit END), 0),
    COALESCE(SUM(CASE WHEN code = '2200' THEN total_credit - total_debit END), 0),
    COALESCE(SUM(CASE WHEN code IN ('2300','2310','2320','2330') THEN total_credit - total_debit END), 0),

    -- Section breakdown — Equity
    COALESCE(SUM(CASE WHEN code = '3100' THEN total_credit - total_debit END), 0),
    COALESCE(SUM(CASE WHEN code = '3200' THEN total_credit - total_debit END), 0)
  INTO
    v_total_assets, v_total_liabilities, v_total_equity_gl,
    v_rev_cumulative, v_exp_cumulative,
    v_cash, v_receivables, v_inventory, v_custody, v_other_assets,
    v_payables, v_tax_payable, v_emp_liabilities,
    v_capital, v_retained_earnings
  FROM cumulative;

  -- Unclosed P&L = Revenue - Expenses (cumulative)
  v_unclosed_pnl := v_rev_cumulative - v_exp_cumulative;

  -- Balance check: Assets = Liabilities + Equity + Unclosed P&L
  v_balance_diff := ROUND(v_total_assets - v_total_liabilities - v_total_equity_gl - v_unclosed_pnl, 2);
  v_balance_check := ABS(v_balance_diff) <= 0.01;

  -- ══════════════════════════════════════════════════════════════
  -- PART B: Income Statement (period only)
  -- ══════════════════════════════════════════════════════════════
  WITH period_data AS (
    SELECT coa.code,
           COALESCE(SUM(jel.debit), 0)  AS total_debit,
           COALESCE(SUM(jel.credit), 0) AS total_credit
    FROM journal_entry_lines jel
    JOIN journal_entries je ON je.id = jel.entry_id
    JOIN chart_of_accounts coa ON coa.id = jel.account_id
    WHERE je.status = 'posted'
      AND je.entry_date >= v_period_start
      AND je.entry_date <= p_as_of_date
      AND coa.type IN ('revenue', 'expense')
    GROUP BY coa.code
  )
  SELECT
    -- Revenue lines (credit - debit)
    COALESCE(SUM(CASE WHEN code = '4100' THEN total_credit - total_debit END), 0),
    COALESCE(SUM(CASE WHEN code = '4200' THEN total_debit - total_credit END), 0),
    COALESCE(SUM(CASE WHEN code = '4300' THEN total_debit - total_credit END), 0),
    -- Expense lines (debit - credit)
    COALESCE(SUM(CASE WHEN code = '5100' THEN total_debit - total_credit END), 0),
    COALESCE(SUM(CASE WHEN code IN ('5200','5210','5220','5230') THEN total_debit - total_credit END), 0),
    COALESCE(SUM(CASE WHEN code IN ('5310','5320','5330','5335') THEN total_debit - total_credit END), 0),
    COALESCE(SUM(CASE WHEN code = '5300' THEN total_debit - total_credit END), 0),
    COALESCE(SUM(CASE WHEN code = '5900' THEN total_debit - total_credit END), 0)
  INTO
    v_gross_revenue, v_sales_returns, v_sales_discounts,
    v_cogs, v_operating_exp, v_payroll_exp,
    v_inventory_adj, v_rounding_diffs
  FROM period_data;

  v_net_revenue    := v_gross_revenue - v_sales_returns - v_sales_discounts;
  v_gross_profit   := v_net_revenue - v_cogs;
  v_total_expenses := v_operating_exp + v_payroll_exp + v_inventory_adj + v_rounding_diffs;
  v_net_profit_period := v_gross_profit - v_total_expenses;

  IF v_net_revenue > 0 THEN
    v_gross_margin_pct := ROUND((v_gross_profit / v_net_revenue) * 100, 2);
    v_net_margin_pct   := ROUND((v_net_profit_period / v_net_revenue) * 100, 2);
  END IF;

  -- ══════════════════════════════════════════════════════════════
  -- PART C: Health Indicators (as-of only — NOT affected by period)
  -- ══════════════════════════════════════════════════════════════
  v_current_assets  := v_cash + v_receivables + v_inventory + v_custody + v_other_assets;
  v_current_liabs   := v_payables + v_tax_payable + v_emp_liabilities;
  v_quick_assets    := v_current_assets - v_inventory;
  v_working_capital := v_current_assets - v_current_liabs;

  IF v_current_liabs > 0 THEN
    v_current_ratio := ROUND(v_current_assets / v_current_liabs, 3);
    v_quick_ratio   := ROUND(v_quick_assets / v_current_liabs, 3);
  END IF;

  IF (v_total_equity_gl + v_unclosed_pnl) > 0 THEN
    v_debt_to_equity := ROUND(v_total_liabilities / (v_total_equity_gl + v_unclosed_pnl), 3);
  END IF;

  -- Status classification
  v_cr_status := CASE
    WHEN v_current_liabs = 0 AND v_current_assets > 0 THEN 'excellent'
    WHEN v_current_liabs = 0 AND v_current_assets = 0 THEN 'warning'
    WHEN v_current_ratio >= 2.0 THEN 'excellent'
    WHEN v_current_ratio >= 1.5 THEN 'good'
    WHEN v_current_ratio >= 1.0 THEN 'warning'
    ELSE 'critical' END;
  
  v_qr_status := CASE
    WHEN v_current_liabs = 0 AND v_quick_assets > 0 THEN 'excellent'
    WHEN v_current_liabs = 0 AND v_quick_assets = 0 THEN 'warning'
    WHEN v_quick_ratio >= 2.0 THEN 'excellent'
    WHEN v_quick_ratio >= 1.5 THEN 'good'
    WHEN v_quick_ratio >= 1.0 THEN 'warning'
    ELSE 'critical' END;
  
  v_de_status := CASE
    WHEN (v_total_equity_gl + v_unclosed_pnl) <= 0 THEN 'critical'
    WHEN v_debt_to_equity < 1.0 THEN 'good'
    WHEN v_debt_to_equity < 2.0 THEN 'warning'
    ELSE 'critical' END;

  -- ══════════════════════════════════════════════════════════════
  -- Return combined JSONB
  -- ══════════════════════════════════════════════════════════════
  RETURN jsonb_build_object(
    'as_of_date', p_as_of_date,
    'period_start', v_period_start,

    'balance_sheet', jsonb_build_object(
      'total_assets', v_total_assets,
      'total_liabilities', v_total_liabilities,
      'total_equity_gl', v_total_equity_gl,
      'unclosed_pnl_to_date', v_unclosed_pnl,
      'net_profit_current_period', v_net_profit_period,
      'balance_check', v_balance_check,
      'balance_diff', v_balance_diff,
      'sections', jsonb_build_object(
        'cash', jsonb_build_object('codes', '["1110","1120","1130"]'::jsonb, 'total', v_cash, 'label', 'النقدية والبنوك'),
        'receivables', jsonb_build_object('codes', '["1200","1210"]'::jsonb, 'total', v_receivables, 'label', 'ذمم مدينة'),
        'inventory', jsonb_build_object('codes', '["1300"]'::jsonb, 'total', v_inventory, 'label', 'المخزون'),
        'custody', jsonb_build_object('codes', '["1400"]'::jsonb, 'total', v_custody, 'label', 'العُهد'),
        'other_assets', jsonb_build_object('codes', '["1500","1510"]'::jsonb, 'total', v_other_assets, 'label', 'أصول أخرى'),
        'payables', jsonb_build_object('codes', '["2100","2110"]'::jsonb, 'total', v_payables, 'label', 'ذمم دائنة'),
        'tax_payable', jsonb_build_object('codes', '["2200"]'::jsonb, 'total', v_tax_payable, 'label', 'ضريبة مستحقة'),
        'employee_liabilities', jsonb_build_object('codes', '["2300","2310","2320","2330"]'::jsonb, 'total', v_emp_liabilities, 'label', 'التزامات موظفين'),
        'capital', jsonb_build_object('codes', '["3100"]'::jsonb, 'total', v_capital, 'label', 'رأس المال'),
        'retained_earnings', jsonb_build_object('codes', '["3200"]'::jsonb, 'total', v_retained_earnings, 'label', 'أرباح محتجزة')
      )
    ),

    'income_statement', jsonb_build_object(
      'gross_revenue', v_gross_revenue,
      'sales_returns', v_sales_returns,
      'sales_discounts', v_sales_discounts,
      'net_revenue', v_net_revenue,
      'cogs', v_cogs,
      'gross_profit', v_gross_profit,
      'gross_margin_pct', v_gross_margin_pct,
      'operating_expenses', v_operating_exp,
      'payroll_expenses', v_payroll_exp,
      'inventory_adjustments', v_inventory_adj,
      'rounding_diffs', v_rounding_diffs,
      'total_expenses', v_total_expenses,
      'net_profit', v_net_profit_period,
      'net_margin_pct', v_net_margin_pct
    ),

    'health_indicators', jsonb_build_object(
      'current_assets', v_current_assets,
      'current_liabilities', v_current_liabs,
      'current_ratio', v_current_ratio,
      'current_ratio_status', v_cr_status,
      'quick_assets', v_quick_assets,
      'quick_ratio', v_quick_ratio,
      'quick_ratio_status', v_qr_status,
      'working_capital', v_working_capital,
      'debt_to_equity', v_debt_to_equity,
      'debt_to_equity_status', v_de_status,
      'cash_position', v_cash,
      'ar_total', v_receivables,
      'ap_total', v_payables,
      'inventory_value', v_inventory
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_financial_summary(DATE, DATE) TO authenticated;


-- ────────────────────────────────────────────────────────────
-- 2. get_trial_balance_detail
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_trial_balance_detail(
  p_as_of_date   DATE DEFAULT CURRENT_DATE,
  p_show_parents BOOLEAN DEFAULT false
)
RETURNS TABLE (
  account_id      UUID,
  account_code    TEXT,
  account_name    TEXT,
  account_name_en TEXT,
  account_type    TEXT,
  parent_code     TEXT,
  depth           INTEGER,
  total_debit     NUMERIC,
  total_credit    NUMERIC,
  net_balance     NUMERIC,
  is_leaf         BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- ── Security ────────────────────────────────────────────────
  IF NOT check_permission(auth.uid(), 'finance.journal.read') THEN
    RAISE EXCEPTION 'Access denied. Requires finance.journal.read';
  END IF;

  IF p_show_parents THEN
    -- ══════════════════════════════════════════════════════════
    -- Mode: show parents with recursive rollup
    -- ══════════════════════════════════════════════════════════
    RETURN QUERY
    WITH RECURSIVE
    -- Compute depth for each account (root = 0)
    depth_cte AS (
      SELECT a.id, 0 AS lvl
      FROM chart_of_accounts a
      WHERE a.parent_id IS NULL AND a.is_active = true
      UNION ALL
      SELECT c.id, d.lvl + 1
      FROM chart_of_accounts c
      JOIN depth_cte d ON d.id = c.parent_id
      WHERE c.is_active = true
    ),
    account_flags AS (
      SELECT a.id, a.code, a.name, a.name_en, a.type, a.parent_id,
             NOT EXISTS (
               SELECT 1 FROM chart_of_accounts c
               WHERE c.parent_id = a.id AND c.is_active = true
             ) AS a_is_leaf,
             COALESCE(dc.lvl, 0) AS a_depth
      FROM chart_of_accounts a
      LEFT JOIN depth_cte dc ON dc.id = a.id
      WHERE a.is_active = true
    ),
    -- Direct balances for ALL accounts with journal entries
    direct_balances AS (
      SELECT jel.account_id,
             SUM(jel.debit)  AS d_total_debit,
             SUM(jel.credit) AS d_total_credit
      FROM journal_entry_lines jel
      JOIN journal_entries je ON je.id = jel.entry_id
      WHERE je.status = 'posted' AND je.entry_date <= p_as_of_date
      GROUP BY jel.account_id
    ),
    -- Recursive rollup: start from every account with direct balance, walk UP
    rolled AS (
      -- Base: every account with direct movement
      SELECT af.id AS source_id,
             af.id AS target_id,
             af.parent_id AS target_parent_id,
             db.d_total_debit  AS rolled_debit,
             db.d_total_credit AS rolled_credit
      FROM account_flags af
      JOIN direct_balances db ON db.account_id = af.id

      UNION ALL

      -- Recursive: parent inherits child amounts
      SELECT r.source_id,
             p.id,
             p.parent_id,
             r.rolled_debit,
             r.rolled_credit
      FROM rolled r
      JOIN account_flags p ON p.id = r.target_parent_id
    ),
    -- Aggregate: each account appears once
    aggregated AS (
      SELECT target_id AS agg_id,
             SUM(rolled_debit)  AS agg_debit,
             SUM(rolled_credit) AS agg_credit
      FROM rolled
      GROUP BY target_id
    )
    SELECT af.id,
           af.code,
           af.name,
           af.name_en,
           af.type,
           pc.code,
           af.a_depth,
           COALESCE(agg.agg_debit, 0),
           COALESCE(agg.agg_credit, 0),
           CASE WHEN af.type IN ('asset','expense')
                THEN COALESCE(agg.agg_debit, 0) - COALESCE(agg.agg_credit, 0)
                ELSE COALESCE(agg.agg_credit, 0) - COALESCE(agg.agg_debit, 0)
           END,
           af.a_is_leaf
    FROM account_flags af
    JOIN aggregated agg ON agg.agg_id = af.id
    LEFT JOIN chart_of_accounts pc ON pc.id = af.parent_id
    WHERE COALESCE(agg.agg_debit, 0) > 0 OR COALESCE(agg.agg_credit, 0) > 0
    ORDER BY af.code;

  ELSE
    -- ══════════════════════════════════════════════════════════
    -- Mode: direct balances only (no rollup)
    -- ══════════════════════════════════════════════════════════
    RETURN QUERY
    WITH RECURSIVE
    depth_cte AS (
      SELECT a.id, 0 AS lvl
      FROM chart_of_accounts a
      WHERE a.parent_id IS NULL AND a.is_active = true
      UNION ALL
      SELECT c.id, d.lvl + 1
      FROM chart_of_accounts c
      JOIN depth_cte d ON d.id = c.parent_id
      WHERE c.is_active = true
    ),
    direct_balances AS (
      SELECT jel.account_id,
             SUM(jel.debit)  AS d_total_debit,
             SUM(jel.credit) AS d_total_credit
      FROM journal_entry_lines jel
      JOIN journal_entries je ON je.id = jel.entry_id
      WHERE je.status = 'posted' AND je.entry_date <= p_as_of_date
      GROUP BY jel.account_id
    )
    SELECT a.id,
           a.code,
           a.name,
           a.name_en,
           a.type,
           pc.code,
           COALESCE(dc.lvl, 0),
           COALESCE(db.d_total_debit, 0),
           COALESCE(db.d_total_credit, 0),
           CASE WHEN a.type IN ('asset','expense')
                THEN COALESCE(db.d_total_debit, 0) - COALESCE(db.d_total_credit, 0)
                ELSE COALESCE(db.d_total_credit, 0) - COALESCE(db.d_total_debit, 0)
           END,
           NOT EXISTS (
             SELECT 1 FROM chart_of_accounts c2
             WHERE c2.parent_id = a.id AND c2.is_active = true
           )
    FROM chart_of_accounts a
    JOIN direct_balances db ON db.account_id = a.id
    LEFT JOIN chart_of_accounts pc ON pc.id = a.parent_id
    LEFT JOIN depth_cte dc ON dc.id = a.id
    WHERE a.is_active = true
    ORDER BY a.code;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_trial_balance_detail(DATE, BOOLEAN) TO authenticated;


-- ────────────────────────────────────────────────────────────
-- Verification
-- ────────────────────────────────────────────────────────────
DO $$
BEGIN
  RAISE NOTICE '[96] ✅ get_financial_summary(DATE, DATE) created';
  RAISE NOTICE '[96] ✅ get_trial_balance_detail(DATE, BOOLEAN) created';
  RAISE NOTICE '[96] ✅ Security: finance.journal.read';
  RAISE NOTICE '[96] ✅ Balance check: Assets = Liabilities + Equity + Unclosed P&L';
  RAISE NOTICE '[96] ✅ Trial Balance: supports direct+rollup, depth, is_leaf';
END $$;
