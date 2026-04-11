-- 93_profitability_branch_daily_scope_hotfix.sql
-- Fixes the remaining CTE scope/runtime issue in analytics.internal_refresh_fact_branch_profit_daily
-- after 92_profitability_runtime_hotfixes.sql.

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

-- ------------------------------------------------------------------
-- Default single-branch allocation rule bootstrap
-- Safe behavior:
-- 1) Non-destructive: never updates or deletes existing rule sets/rules.
-- 2) Idempotent: inserts only when no active overlapping rule exists.
-- 3) Guarded: runs only when exactly one active branch exists.
-- 4) Covers both operating_expenses and payroll_expenses.
-- ------------------------------------------------------------------
DO $$
DECLARE
    v_branch_count INTEGER;
    v_branch_id UUID;
    v_effective_from DATE;
    v_rule_set_id UUID;
BEGIN
    SELECT COUNT(*)
    INTO v_branch_count
    FROM public.branches
    WHERE is_active = true;

    IF v_branch_count <> 1 THEN
        RAISE NOTICE 'Skipping default allocation bootstrap: expected exactly 1 active branch, found %.', v_branch_count;
        RETURN;
    END IF;

    SELECT id
    INTO v_branch_id
    FROM public.branches
    WHERE is_active = true
    ORDER BY created_at ASC, id ASC
    LIMIT 1;

    SELECT COALESCE(
        MIN(check_month),
        date_trunc('month', CURRENT_DATE)::DATE
    )
    INTO v_effective_from
    FROM analytics.profitability_data_quality_daily
    WHERE check_type = 'NO_ACTIVE_RULE'
      AND check_month IS NOT NULL;

    IF NOT EXISTS (
        SELECT 1
        FROM analytics.profitability_allocation_rule_sets rs
        WHERE rs.is_active = true
          AND rs.applies_to = 'operating_expenses'
          AND rs.effective_from <= v_effective_from
          AND (rs.effective_to IS NULL OR rs.effective_to >= v_effective_from)
    ) THEN
        INSERT INTO analytics.profitability_allocation_rule_sets (
            name,
            applies_to,
            basis,
            effective_from,
            effective_to,
            is_active,
            notes,
            created_by
        )
        VALUES (
            'Default Operating Allocation - Single Branch',
            'operating_expenses',
            'fixed_pct',
            v_effective_from,
            NULL,
            true,
            'Auto-bootstrap default created by migration 93 for single-branch environments. Uses 100% allocation to the only active branch.',
            auth.uid()
        )
        RETURNING id INTO v_rule_set_id;

        INSERT INTO analytics.profitability_allocation_rules (
            rule_set_id,
            branch_id,
            weight_value
        )
        VALUES (
            v_rule_set_id,
            v_branch_id,
            1.000000
        );
    ELSE
        RAISE NOTICE 'Skipping operating_expenses bootstrap: active overlapping rule set already exists.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM analytics.profitability_allocation_rule_sets rs
        WHERE rs.is_active = true
          AND rs.applies_to = 'payroll_expenses'
          AND rs.effective_from <= v_effective_from
          AND (rs.effective_to IS NULL OR rs.effective_to >= v_effective_from)
    ) THEN
        INSERT INTO analytics.profitability_allocation_rule_sets (
            name,
            applies_to,
            basis,
            effective_from,
            effective_to,
            is_active,
            notes,
            created_by
        )
        VALUES (
            'Default Payroll Allocation - Single Branch',
            'payroll_expenses',
            'fixed_pct',
            v_effective_from,
            NULL,
            true,
            'Auto-bootstrap default created by migration 93 for single-branch environments. Uses 100% allocation to the only active branch.',
            auth.uid()
        )
        RETURNING id INTO v_rule_set_id;

        INSERT INTO analytics.profitability_allocation_rules (
            rule_set_id,
            branch_id,
            weight_value
        )
        VALUES (
            v_rule_set_id,
            v_branch_id,
            1.000000
        );
    ELSE
        RAISE NOTICE 'Skipping payroll_expenses bootstrap: active overlapping rule set already exists.';
    END IF;
END;
$$;
