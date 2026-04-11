-- 92_profitability_runtime_hotfixes.sql
-- Runtime hotfixes for profitability phases 88-91 after first production-style execution.

-- ============================================================
-- 1) Phase 2: gross profit grain refresh
-- ============================================================
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

-- ============================================================
-- 2) Phase 2: branch direct profit refresh
-- ============================================================
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

    WITH gp_agg AS (
        SELECT
            sale_date AS profit_date,
            branch_id,
            SUM(net_revenue) AS gross_revenue,
            SUM(net_cogs) AS gross_cogs,
            SUM(gross_profit) AS gross_profit
        FROM analytics.fact_gross_profit_daily_grain
        WHERE sale_date = ANY(p_target_dates)
        GROUP BY sale_date, branch_id
    ),
    op_exp_agg AS (
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
        GROUP BY je.entry_date, e.branch_id
    ),
    pay_exp_agg AS (
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
        GROUP BY je.entry_date, pr.branch_id
    ),
    all_keys AS (
        SELECT profit_date, branch_id FROM gp_agg
        UNION
        SELECT profit_date, branch_id FROM op_exp_agg
        UNION
        SELECT profit_date, branch_id FROM pay_exp_agg
    )
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
    FROM all_keys k
    LEFT JOIN gp_agg g ON g.profit_date = k.profit_date
                       AND (g.branch_id = k.branch_id OR (g.branch_id IS NULL AND k.branch_id IS NULL))
    LEFT JOIN op_exp_agg o ON o.profit_date = k.profit_date
                           AND (o.branch_id = k.branch_id OR (o.branch_id IS NULL AND k.branch_id IS NULL))
    LEFT JOIN pay_exp_agg p ON p.profit_date = k.profit_date
                            AND (p.branch_id = k.branch_id OR (p.branch_id IS NULL AND k.branch_id IS NULL))
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
    FROM all_keys k
    LEFT JOIN gp_agg g ON g.profit_date = k.profit_date AND g.branch_id IS NULL
    LEFT JOIN op_exp_agg o ON o.profit_date = k.profit_date AND o.branch_id IS NULL
    LEFT JOIN pay_exp_agg p ON p.profit_date = k.profit_date AND p.branch_id IS NULL
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

-- ============================================================
-- 3) Phase 3: data quality refresh
-- ============================================================
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

-- ============================================================
-- 4) Phase 3: monthly allocation snapshots
-- ============================================================
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

-- ============================================================
-- 5) Phase 3: final monthly branch profitability
-- ============================================================
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
