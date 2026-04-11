-- ============================================================
-- 90_profitability_allocation_and_governance.sql
-- EDARA v2 - Phase 3: Profitability Allocation Engine (v5)
-- Implements configurable rule-based allocation for shared expenses and payroll.
-- ============================================================

-- ============================================================
-- SECTION 1: Tables Creation
-- ============================================================

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

CREATE UNIQUE INDEX IF NOT EXISTS uidx_fact_final_null_branch
    ON analytics.fact_branch_profit_final_monthly (month_start)
    WHERE branch_id IS NULL;

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

-- Handle dropping old constraints if table existed
ALTER TABLE analytics.profitability_data_quality_daily DROP CONSTRAINT IF EXISTS uq_pdqd_unique_check;
ALTER TABLE analytics.profitability_data_quality_daily ADD CONSTRAINT uq_pdqd_unique_check UNIQUE NULLS NOT DISTINCT (check_date, check_type, check_month, applies_to);

-- ============================================================
-- SECTION 2: Comments & RLS
-- ============================================================

COMMENT ON TABLE analytics.profitability_allocation_rule_sets IS 'مجموعات قواعد التوزيع (مرحلة 3). لا نستخدم fallback — في حال عدم وجود قاعدة، لا يتم التوزيع ويوضع في pool غير موزع.';
COMMENT ON TABLE analytics.profitability_allocation_rules IS 'قواعد التوزيع نفسها مع الوزن النهائي أو النسبي (حسب fixed_pct).';
COMMENT ON TABLE analytics.snapshot_branch_allocation_weights_monthly IS 'لقطة شهرية للأوزان لضمان عدم إعادة التوزيع عند العودة للماضي. الأوزان المحسوبة لا تختلط.';
COMMENT ON TABLE analytics.fact_branch_profit_final_monthly IS 'الجدول المالي النهائي الشهري متضمنًا المصاريف الموزعة. يحتوي على صف branch_id IS NULL كpool خاص بالمصروفات غير الموزعة.';
COMMENT ON TABLE analytics.profitability_data_quality_daily IS 'جدول مراقب جودة البيانات لعمليات الاستخراج والربحية (يومي / شهري).';

ALTER TABLE analytics.profitability_allocation_rule_sets ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.profitability_allocation_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.snapshot_branch_allocation_weights_monthly ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.fact_branch_profit_final_monthly ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.profitability_data_quality_daily ENABLE ROW LEVEL SECURITY;

-- Reports access policies
CREATE POLICY rule_sets_view ON analytics.profitability_allocation_rule_sets FOR SELECT TO authenticated USING (public.check_permission(auth.uid(), 'reports.view_all') OR public.check_permission(auth.uid(), 'reports.financial'));
CREATE POLICY rule_sets_manage ON analytics.profitability_allocation_rule_sets FOR ALL TO authenticated USING (public.check_permission(auth.uid(), 'reports.financial'));

CREATE POLICY rules_view ON analytics.profitability_allocation_rules FOR SELECT TO authenticated USING (public.check_permission(auth.uid(), 'reports.view_all') OR public.check_permission(auth.uid(), 'reports.financial'));
CREATE POLICY rules_manage ON analytics.profitability_allocation_rules FOR ALL TO authenticated USING (public.check_permission(auth.uid(), 'reports.financial'));

CREATE POLICY snapshot_view ON analytics.snapshot_branch_allocation_weights_monthly FOR SELECT TO authenticated USING (public.check_permission(auth.uid(), 'reports.view_all') OR public.check_permission(auth.uid(), 'reports.financial'));

CREATE POLICY fact_final_view ON analytics.fact_branch_profit_final_monthly FOR SELECT TO authenticated USING (public.check_permission(auth.uid(), 'reports.view_all') OR public.check_permission(auth.uid(), 'reports.financial'));

CREATE POLICY dq_view ON analytics.profitability_data_quality_daily FOR SELECT TO authenticated USING (public.check_permission(auth.uid(), 'reports.view_all') OR public.check_permission(auth.uid(), 'reports.financial'));

GRANT SELECT ON analytics.profitability_allocation_rule_sets TO authenticated;
GRANT SELECT ON analytics.profitability_allocation_rules TO authenticated;
GRANT SELECT ON analytics.snapshot_branch_allocation_weights_monthly TO authenticated;
GRANT SELECT ON analytics.fact_branch_profit_final_monthly TO authenticated;
GRANT SELECT ON analytics.profitability_data_quality_daily TO authenticated;

GRANT INSERT, UPDATE, DELETE ON analytics.profitability_allocation_rule_sets TO authenticated;
GRANT INSERT, UPDATE, DELETE ON analytics.profitability_allocation_rules TO authenticated;

-- ============================================================
-- SECTION 3: Refresh Procedures (Phase 3 Core Logic)
-- ============================================================

-- 3.A Data Quality (Daily Track)
CREATE OR REPLACE PROCEDURE analytics.internal_refresh_profitability_data_quality_daily(p_target_dates DATE[])
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    d DATE;
    v_cnt INT;
    v_dtl JSONB;
BEGIN
    IF array_length(p_target_dates, 1) IS NULL THEN RETURN; END IF;

    -- Cleanup checks for specific dates (daily checks only)
    DELETE FROM analytics.profitability_data_quality_daily 
    WHERE check_date = ANY(p_target_dates) AND check_month IS NULL;

    FOREACH d IN ARRAY p_target_dates LOOP
        -- 1. zero_cost_delivered_items (WARNING)
        SELECT COUNT(*), coalesce(jsonb_agg(soi.id) FILTER (WHERE num <= 10), '[]'::jsonb) 
        INTO v_cnt, v_dtl
        FROM (
            SELECT soi.id, row_number() over() as num 
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

        -- 2. null_cost_delivered_items (ERROR)
        SELECT COUNT(*), coalesce(jsonb_agg(soi.id) FILTER (WHERE num <= 10), '[]'::jsonb) 
        INTO v_cnt, v_dtl
        FROM (
            SELECT soi.id, row_number() over() as num 
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

        -- 3. confirmed_return_no_confirmed_at (ERROR)
        SELECT COUNT(*), coalesce(jsonb_agg(sr.id) FILTER (WHERE num <= 10), '[]'::jsonb) 
        INTO v_cnt, v_dtl
        FROM (
            SELECT sr.id, row_number() over() as num 
            FROM public.sales_returns sr
            WHERE sr.status = 'confirmed' 
              AND sr.confirmed_at IS NULL
              AND (sr.updated_at AT TIME ZONE 'Africa/Cairo')::DATE = d
        ) sub;
        IF v_cnt > 0 THEN 
            INSERT INTO analytics.profitability_data_quality_daily (check_date, check_type, severity, record_count, detail)
            VALUES (d, 'confirmed_return_no_confirmed_at', 'ERROR', v_cnt, jsonb_build_object('sample_ids', v_dtl));
        END IF;

        -- 4. sales_with_null_branch (WARNING)
        SELECT COUNT(*), coalesce(jsonb_agg(so.id) FILTER (WHERE num <= 10), '[]'::jsonb) 
        INTO v_cnt, v_dtl
        FROM (
            SELECT so.id, row_number() over() as num 
            FROM public.sales_orders so 
            WHERE ((so.delivered_at IS NOT NULL AND (so.delivered_at AT TIME ZONE 'Africa/Cairo')::DATE = d) OR (so.delivered_at IS NULL AND so.order_date = d))
              AND so.status IN ('delivered', 'completed')
              AND so.branch_id IS NULL
        ) sub;
        IF v_cnt > 0 THEN 
            INSERT INTO analytics.profitability_data_quality_daily (check_date, check_type, severity, record_count, detail)
            VALUES (d, 'sales_with_null_branch', 'WARNING', v_cnt, jsonb_build_object('sample_ids', v_dtl));
        END IF;

        -- 5. sentinel_rep_usage (WARNING)
         SELECT COUNT(*), coalesce(jsonb_agg(so.id) FILTER (WHERE num <= 10), '[]'::jsonb) 
        INTO v_cnt, v_dtl
        FROM (
            SELECT so.id, row_number() over() as num 
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

-- 3.B Allocation Weights (Monthly Track)
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
    IF array_length(p_months, 1) IS NULL THEN RETURN; END IF;

    FOR i IN 1..array_length(p_months, 1) LOOP
        -- Always trunc back exactly to month to ensure idempotency.
        m := date_trunc('month', p_months[i])::DATE;
        v_month_start := m;
        v_month_end := (m + interval '1 month' - interval '1 day')::DATE;

        -- Cleanup
        DELETE FROM analytics.snapshot_branch_allocation_weights_monthly WHERE month_start = m;
        DELETE FROM analytics.profitability_data_quality_daily WHERE check_month = m AND check_type IN ('RULE_CONFLICT_BLOCKED', 'NO_ACTIVE_RULE', 'WEIGHT_SUM_INVALID', 'HEADCOUNT_SHARE_ESTIMATE');

        FOREACH pool_type IN ARRAY ARRAY['operating_expenses', 'payroll_expenses'] LOOP
            -- 1. Check overlap
            SELECT count(*), max(id), max(basis), max(name) 
            INTO v_rs_count, v_rs_id, v_rs_basis, v_rs_name
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

            -- 2. We have exactly 1 active rule set for this pool type.
            IF v_rs_basis = 'fixed_pct' THEN
                -- check valid sum
                SELECT COALESCE(SUM(weight_value), 0) INTO v_sum_weight
                FROM analytics.profitability_allocation_rules WHERE rule_set_id = v_rs_id;

                IF ROUND(v_sum_weight, 4) != 1.0000 THEN
                    INSERT INTO analytics.profitability_data_quality_daily (check_date, check_month, applies_to, check_type, severity, record_count, detail)
                    VALUES (v_month_start, v_month_start, pool_type, 'WEIGHT_SUM_INVALID', 'ERROR', 1, jsonb_build_object('sum', v_sum_weight));
                    CONTINUE;
                END IF;

                INSERT INTO analytics.snapshot_branch_allocation_weights_monthly 
                    (month_start, applies_to, branch_id, rule_set_id, basis, computed_weight, raw_basis_value, total_basis_value, is_estimated)
                SELECT 
                    v_month_start, pool_type, branch_id, v_rs_id, v_rs_basis, weight_value, 0, 0, false
                FROM analytics.profitability_allocation_rules WHERE rule_set_id = v_rs_id AND weight_value > 0;
            
            ELSIF v_rs_basis IN ('revenue_share', 'gross_profit_share', 'direct_payroll_share') THEN
                
                -- Calculate base values from fact_branch_profit_daily (excluding branch_id IS NULL)
                CREATE TEMP TABLE tmp_basis ON COMMIT DROP AS
                SELECT branch_id,
                       SUM(CASE WHEN v_rs_basis = 'revenue_share' THEN gross_revenue 
                                WHEN v_rs_basis = 'gross_profit_share' THEN gross_profit
                                WHEN v_rs_basis = 'direct_payroll_share' THEN direct_payroll_exp END) as basis_val
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

                    -- Re-validate sum just to be sure
                    SELECT COALESCE(SUM(computed_weight), 0) INTO v_sum_weight FROM analytics.snapshot_branch_allocation_weights_monthly WHERE month_start = v_month_start AND applies_to = pool_type AND rule_set_id = v_rs_id;
                    IF ROUND(v_sum_weight, 4) != 1.0000 THEN
                        DELETE FROM analytics.snapshot_branch_allocation_weights_monthly WHERE month_start = v_month_start AND applies_to = pool_type;
                        INSERT INTO analytics.profitability_data_quality_daily (check_date, check_month, applies_to, check_type, severity, record_count, detail)
                        VALUES (v_month_start, v_month_start, pool_type, 'WEIGHT_SUM_INVALID', 'ERROR', 1, jsonb_build_object('sum', v_sum_weight, 'msg', 'Precision distribution resulted in invalid total sum'));
                    END IF;
                ELSE
                    -- total basis is zero. cannot distribute
                    INSERT INTO analytics.profitability_data_quality_daily (check_date, check_month, applies_to, check_type, severity, record_count, detail)
                    VALUES (v_month_start, v_month_start, pool_type, 'WEIGHT_SUM_INVALID', 'ERROR', 1, jsonb_build_object('msg', 'Total basis pool is zero', 'basis', v_rs_basis));
                END IF;
                DROP TABLE tmp_basis;

            ELSIF v_rs_basis = 'headcount_share' THEN
                CREATE TEMP TABLE tmp_hc_basis ON COMMIT DROP AS
                SELECT branch_id, COUNT(*) as basis_val
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

                    -- Warn that it is an estimate
                    INSERT INTO analytics.profitability_data_quality_daily (check_date, check_month, applies_to, check_type, severity, record_count, detail)
                    VALUES (v_month_start, v_month_start, pool_type, 'HEADCOUNT_SHARE_ESTIMATE', 'WARNING', 1, jsonb_build_object('msg', 'Headcount logic used, considered estimated distribution'));

                    -- Re-validate sum
                    SELECT COALESCE(SUM(computed_weight), 0) INTO v_sum_weight FROM analytics.snapshot_branch_allocation_weights_monthly WHERE month_start = v_month_start AND applies_to = pool_type AND rule_set_id = v_rs_id;
                    IF ROUND(v_sum_weight, 4) != 1.0000 THEN
                        DELETE FROM analytics.snapshot_branch_allocation_weights_monthly WHERE month_start = v_month_start AND applies_to = pool_type;
                        INSERT INTO analytics.profitability_data_quality_daily (check_date, check_month, applies_to, check_type, severity, record_count, detail)
                        VALUES (v_month_start, v_month_start, pool_type, 'WEIGHT_SUM_INVALID', 'ERROR', 1, jsonb_build_object('sum', v_sum_weight, 'msg', 'Precision distribution resulted in invalid total sum'));
                    END IF;
                ELSE
                    INSERT INTO analytics.profitability_data_quality_daily (check_date, check_month, applies_to, check_type, severity, record_count, detail)
                    VALUES (v_month_start, v_month_start, pool_type, 'WEIGHT_SUM_INVALID', 'ERROR', 1, jsonb_build_object('msg', 'Total headcount basis pool is zero or empty', 'basis', v_rs_basis));
                END IF;
                DROP TABLE tmp_hc_basis;
            END IF;
        END LOOP;
    END LOOP;
END;
$$;

-- 3.C Fact Final Monthly Generation
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
    v_large_unassigned_threshold NUMERIC := 0.5; -- نسبة عتبة التحذير 50% من المباشر
BEGIN
    IF array_length(p_months, 1) IS NULL THEN RETURN; END IF;

    FOR i IN 1..array_length(p_months, 1) LOOP
        m := date_trunc('month', p_months[i])::DATE;
        v_month_start := m;
        v_month_end := (m + interval '1 month' - interval '1 day')::DATE;

        -- Clean final table + warning for this month
        DELETE FROM analytics.fact_branch_profit_final_monthly WHERE month_start = m;
        DELETE FROM analytics.profitability_data_quality_daily WHERE check_month = m AND check_type = 'large_unassigned_shared_pool';

        -- Get shared pools from fact_branch_profit_daily WHERE branch_id IS NULL
        SELECT COALESCE(SUM(direct_operating_exp), 0), COALESCE(SUM(direct_payroll_exp), 0)
        INTO v_total_unassigned_op, v_total_unassigned_pay
        FROM analytics.fact_branch_profit_daily
        WHERE profit_date >= v_month_start AND profit_date <= v_month_end
          AND branch_id IS NULL;

        -- Get active rule sets used for this month from snapshot
        SELECT MAX(rule_set_id) INTO v_rs_op FROM analytics.snapshot_branch_allocation_weights_monthly WHERE month_start = m AND applies_to = 'operating_expenses';
        SELECT MAX(rule_set_id) INTO v_rs_pay FROM analytics.snapshot_branch_allocation_weights_monthly WHERE month_start = m AND applies_to = 'payroll_expenses';

        -- Step 1: Generate Branch aggregates (EXCLUDING NULL)
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

        -- Insert all existing branches
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
            0 AS unallocated_shared_op,
            0 AS unallocated_shared_pay,
            v_rs_op, v_rs_pay
        FROM tmp_branch_aggregates t
        LEFT JOIN analytics.snapshot_branch_allocation_weights_monthly sw_op 
               ON sw_op.branch_id = t.branch_id AND sw_op.month_start = m AND sw_op.applies_to = 'operating_expenses'
        LEFT JOIN analytics.snapshot_branch_allocation_weights_monthly sw_pay 
               ON sw_pay.branch_id = t.branch_id AND sw_pay.month_start = m AND sw_pay.applies_to = 'payroll_expenses';

        -- Gather allocated sums accurately post-rounding
        SELECT COALESCE(SUM(allocated_shared_op), 0), COALESCE(SUM(allocated_shared_pay), 0)
        INTO v_sum_shared_op, v_sum_shared_pay
        FROM analytics.fact_branch_profit_final_monthly
        WHERE month_start = m AND branch_id IS NOT NULL;

        -- Step 2: Insert NULL branch (captures remaining unassigned pool naturally)
        -- Option A: NULL branch only holds residual shared pools (Direct P&L holds zero here)
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

        -- Step 3: Check total unassigned proportion
        SELECT COALESCE(SUM(direct_operating_exp + direct_payroll_exp), 0) INTO v_total_direct
        FROM tmp_branch_aggregates;

        IF (v_total_unassigned_op + v_total_unassigned_pay) > 0 AND (v_total_unassigned_op + v_total_unassigned_pay) > (v_total_direct * v_large_unassigned_threshold) THEN
            INSERT INTO analytics.profitability_data_quality_daily (check_date, check_month, applies_to, check_type, severity, record_count, detail)
            VALUES (v_month_start, v_month_start, 'both', 'large_unassigned_shared_pool', 'WARNING', 1, 
                    jsonb_build_object('unassigned_sum', v_total_unassigned_op + v_total_unassigned_pay, 'direct_sum', v_total_direct));
        END IF;

        DROP TABLE tmp_branch_aggregates;
    END LOOP;
END;
$$;

-- ============================================================
-- SECTION 4: Trust State Expansion (Phase 3 Core Logic)
-- ============================================================
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
    -- BRANCH 1: fact_sales_daily_grain (من 88 — بدون تغيير)
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
            WHERE je.status = 'posted' AND coa.code IN ('4100', '2200', '1200')
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
-- SECTION 5: Orchestrator Adjustments
-- ============================================================

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

CREATE OR REPLACE PROCEDURE analytics.run_analytics_watermark_sweep(p_fallback_days INTEGER DEFAULT 3)
LANGUAGE plpgsql SECURITY DEFINER AS $$
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
$$;

CREATE OR REPLACE PROCEDURE analytics.run_historical_backfill(
    p_start_date DATE,
    p_end_date   DATE    DEFAULT CURRENT_DATE,
    p_chunk_days INTEGER DEFAULT 7
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_chunk_start   DATE; v_chunk_end DATE; v_chunk_dates DATE[]; v_lock_obtained BOOLEAN; v_chunks_done INTEGER := 0;
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

            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_sales_daily_grain',                             v_chunk_dates);
            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_financial_ledgers_daily',                       v_chunk_dates);
            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_treasury_cashflow_daily',                       v_chunk_dates);
            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_ar_collections_attributed_to_origin_sale_date', v_chunk_dates);
            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'snapshot_customer_health',                           v_chunk_dates);
            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'snapshot_customer_risk',                             v_chunk_dates);
            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_geography_daily',                               v_chunk_dates);
            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_profit_daily',                                  v_chunk_dates);
            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_gross_profit_daily_grain',                      v_chunk_dates);
            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_branch_profit_daily',                           v_chunk_dates);
            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'profitability_data_quality_daily',                   v_chunk_dates);
            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'snapshot_branch_allocation_weights_monthly',         v_chunk_dates);
            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_branch_profit_final_monthly',                   v_chunk_dates);

            v_chunks_done := v_chunks_done + 1;
            v_chunk_start := v_chunk_end + 1;
        END LOOP;

        RAISE NOTICE 'Historical backfill completed. Chunks processed: %', v_chunks_done;
        PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));
    EXCEPTION WHEN OTHERS THEN PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep')); RAISE;
    END;
END;
$$;

-- ============================================================
-- SECTION 6: Public Read Operations (RPCs)
-- ============================================================
CREATE OR REPLACE FUNCTION public.analytics_branch_final_net_profit_monthly(
    date_from DATE,
    date_to DATE,
    p_branch_id UUID DEFAULT NULL
) RETURNS TABLE (
    month_start DATE,
    branch_id UUID,
    direct_gross_revenue NUMERIC,
    direct_gross_cogs NUMERIC,
    direct_gross_profit NUMERIC,
    direct_operating_exp NUMERIC,
    direct_payroll_exp NUMERIC,
    allocated_shared_op NUMERIC,
    allocated_shared_pay NUMERIC,
    unallocated_shared_op NUMERIC,
    unallocated_shared_pay NUMERIC,
    final_net_profit NUMERIC,
    is_estimated BOOLEAN,
    allocation_status TEXT
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    IF NOT public.check_permission(auth.uid(), 'reports.view_all')
       AND NOT public.check_permission(auth.uid(), 'reports.financial') THEN
        RAISE EXCEPTION 'Access denied. Requires reports.view_all or reports.financial';
    END IF;

    RETURN QUERY
    SELECT
        f.month_start, f.branch_id,
        f.direct_gross_revenue, f.direct_gross_cogs, f.direct_gross_profit,
        f.direct_operating_exp, f.direct_payroll_exp,
        f.allocated_shared_op, f.allocated_shared_pay,
        f.unallocated_shared_op, f.unallocated_shared_pay,
        f.final_net_profit, f.is_estimated,
        CASE WHEN f.branch_id IS NULL THEN 'Unallocated Residual'::TEXT
             WHEN (f.rule_set_id_op IS NOT NULL OR f.rule_set_id_pay IS NOT NULL) THEN 'Allocated'::TEXT
             ELSE 'No Allocation'::TEXT END AS allocation_status
    FROM analytics.fact_branch_profit_final_monthly f
    WHERE f.month_start >= date_from AND f.month_start <= date_to
      AND (p_branch_id IS NULL OR f.branch_id = p_branch_id)
    ORDER BY f.month_start ASC, (f.branch_id IS NULL) ASC, f.final_net_profit DESC NULLS LAST;
END;
$$;
GRANT EXECUTE ON FUNCTION public.analytics_branch_final_net_profit_monthly(DATE, DATE, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.analytics_allocation_quality_report(
    date_from DATE,
    date_to DATE
) RETURNS SETOF analytics.profitability_data_quality_daily
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    IF NOT public.check_permission(auth.uid(), 'reports.view_all')
       AND NOT public.check_permission(auth.uid(), 'reports.financial') THEN
        RAISE EXCEPTION 'Access denied. Requires reports.view_all or reports.financial';
    END IF;

    RETURN QUERY
    SELECT *
    FROM analytics.profitability_data_quality_daily dq
    WHERE dq.check_date >= date_from AND dq.check_date <= date_to
    ORDER BY dq.check_date DESC, dq.severity ASC, dq.check_type;
END;
$$;
GRANT EXECUTE ON FUNCTION public.analytics_allocation_quality_report(DATE, DATE) TO authenticated;
