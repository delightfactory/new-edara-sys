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

    END IF;
END;
$$;