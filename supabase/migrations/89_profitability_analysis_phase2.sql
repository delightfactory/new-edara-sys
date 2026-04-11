-- ============================================================
-- 89_profitability_analysis_phase2.sql
-- EDARA v2 - Profitability Analysis Phase 2
--
-- Adds:
--   1. analytics.fact_gross_profit_daily_grain
--      — بند × يوم البيع; المرتجعات تعكس أبعاد البيع الأصلي
--   2. analytics.fact_branch_profit_daily
--      — صافي ربح مباشر للفرع + unassigned كسلة مستقلة (branch_id IS NULL)
--   3. إجراءات التحديث الداخلي للجدولين
--   4. تحديث orchestrate_incremental_refresh ليشمل job_names الجديدة
--   5. تحديث compute_double_review_trust_state بتحقق فعلي للجدولين
--   6. تحديث run_analytics_watermark_sweep وrun_historical_backfill
--   7. دوال قراءة عامة RLS-guarded
--
-- القيود المحاسبية:
--   - المنتج / العميل / المندوب: إجمالي ربح مباشر فقط (لا صافي)
--   - الفرع: صافي ربح مباشر (gross profit - مصروفات مباشرة - رواتب مباشرة)
--             وليس صافي ربح نهائي بعد توزيع إداري
--   - branch_id IS NULL يُعرض دائمًا كـ unassigned مستقل — يُمنع توزيعه
--   - 5300 مُستبعد صراحةً
--   - RLS: reports.view_all أو reports.financial فقط
-- ============================================================

-- ============================================================
-- SECTION 1: fact_gross_profit_daily_grain
-- إجمالي ربح على مستوى البند × تاريخ البيع
-- ============================================================

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

-- لا UNIQUE قياسي على NULL؛ سنستخدم partial unique index بدلًا منه
-- حتى نضمن تفرد السجل عند branch_id IS NULL أيضًا
CREATE UNIQUE INDEX IF NOT EXISTS uidx_fact_gp_grain_null_branch
    ON analytics.fact_gross_profit_daily_grain (sale_date, customer_id, product_id, rep_id)
    WHERE branch_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_fact_gp_grain_sale_date
    ON analytics.fact_gross_profit_daily_grain (sale_date);
CREATE INDEX IF NOT EXISTS idx_fact_gp_grain_product_date
    ON analytics.fact_gross_profit_daily_grain (product_id, sale_date);
CREATE INDEX IF NOT EXISTS idx_fact_gp_grain_customer_date
    ON analytics.fact_gross_profit_daily_grain (customer_id, sale_date);
CREATE INDEX IF NOT EXISTS idx_fact_gp_grain_rep_date
    ON analytics.fact_gross_profit_daily_grain (rep_id, sale_date);
CREATE INDEX IF NOT EXISTS idx_fact_gp_grain_branch_date
    ON analytics.fact_gross_profit_daily_grain (branch_id, sale_date);

COMMENT ON TABLE analytics.fact_gross_profit_daily_grain IS
    'إجمالي ربح يومي بمستوى البند. branch_id NULL = unassigned. '
    'المرتجعات تحمل أبعاد البيع الأصلي (branch/customer/product/rep). '
    'يمنع توزيع الـ unassigned على الفروع.';

ALTER TABLE analytics.fact_gross_profit_daily_grain ENABLE ROW LEVEL SECURITY;

CREATE POLICY gp_grain_view ON analytics.fact_gross_profit_daily_grain
    FOR SELECT TO authenticated
    USING (
        public.check_permission(auth.uid(), 'reports.view_all')
        OR public.check_permission(auth.uid(), 'reports.financial')
    );

GRANT SELECT ON analytics.fact_gross_profit_daily_grain TO authenticated;

-- ============================================================
-- SECTION 2: fact_branch_profit_daily
-- صافي ربح مباشر للفرع (gross profit - مصروفات/رواتب مباشرة)
-- branch_id IS NULL = unassigned
-- ============================================================

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

-- partial unique index للـ NULL branch_id
CREATE UNIQUE INDEX IF NOT EXISTS uidx_fact_branch_profit_null_branch
    ON analytics.fact_branch_profit_daily (profit_date)
    WHERE branch_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_fact_branch_profit_date
    ON analytics.fact_branch_profit_daily (profit_date);
CREATE INDEX IF NOT EXISTS idx_fact_branch_profit_branch_date
    ON analytics.fact_branch_profit_daily (branch_id, profit_date);

COMMENT ON TABLE analytics.fact_branch_profit_daily IS
    'صافي ربح مباشر للفرع = gross_profit - مصروفات/رواتب مباشرة للفرع. '
    'branch_id NULL = unassigned (لا توزيع). '
    'هذا صافي ربح مباشر وليس صافي ربح نهائي بعد التوزيع الإداري.';

ALTER TABLE analytics.fact_branch_profit_daily ENABLE ROW LEVEL SECURITY;

CREATE POLICY branch_profit_view ON analytics.fact_branch_profit_daily
    FOR SELECT TO authenticated
    USING (
        public.check_permission(auth.uid(), 'reports.view_all')
        OR public.check_permission(auth.uid(), 'reports.financial')
    );

GRANT SELECT ON analytics.fact_branch_profit_daily TO authenticated;

-- ============================================================
-- SECTION 3: internal_refresh_fact_gross_profit_daily_grain
-- ============================================================
-- هيكل المسارين:
--   PATH 1 (SALES)  : event_date = delivered_at/order_date من SO
--                     الأبعاد الأربعة من SO + SOI
--                     gross_revenue/cogs مملوءة، return_* = 0
--   PATH 2 (RETURNS): event_date = sr.confirmed_at AT TIME ZONE 'Africa/Cairo'
--                     الأبعاد من البيع الأصلي (SOI → SO)
--                     return_revenue/cogs مملوءة، gross_* = 0
-- تاريخ انعكاس المرتجع = تاريخ المرتجع الفعلي (ليس تاريخ البيع الأصلي)
-- ============================================================

CREATE OR REPLACE PROCEDURE analytics.internal_refresh_fact_gross_profit_daily_grain(
    p_target_dates DATE[]
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    IF array_length(p_target_dates, 1) IS NULL THEN RETURN; END IF;

    -- إيدمبوتنت: حذف جميع الأحداث (مبيعات ومرتجعات) على التواريخ المستهدفة
    DELETE FROM analytics.fact_gross_profit_daily_grain
    WHERE sale_date = ANY(p_target_dates);

    -- ──────────────────────────────────────────────────────────
    -- PATH 1: SALES
    -- event_date مأخوذ من يوم التسليم / الأمر
    -- ──────────────────────────────────────────────────────────
    WITH sales_items AS (
        SELECT
            CASE
                WHEN so.delivered_at IS NOT NULL
                    THEN (so.delivered_at AT TIME ZONE 'Africa/Cairo')::DATE
                ELSE so.order_date
            END                                        AS event_date,
            so.branch_id,
            so.customer_id,
            soi.product_id,
            COALESCE(so.rep_id, '00000000-0000-0000-0000-000000000000'::UUID) AS rep_id,
            soi.line_total                             AS item_revenue,
            soi.base_quantity                          AS item_quantity,
            COALESCE(soi.unit_cost_at_sale, 0)         AS unit_cost
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
    sales_agg AS (
        SELECT
            event_date                     AS sale_date,
            branch_id, customer_id, product_id, rep_id,
            SUM(item_revenue)              AS gross_revenue,
            SUM(item_quantity)             AS gross_quantity,
            SUM(unit_cost * item_quantity) AS gross_cogs,
            0::NUMERIC                     AS return_revenue,
            0::NUMERIC                     AS return_quantity,
            0::NUMERIC                     AS return_cogs
        FROM sales_items
        GROUP BY event_date, branch_id, customer_id, product_id, rep_id
    ),

    -- ──────────────────────────────────────────────────────────
    -- PATH 2: RETURNS
    -- event_date = تاريخ اعتماد المرتجع المحاسبي (sr.confirmed_at بتوقيت Cairo)
    -- الأبعاد من البيع الأصلي: sri.order_item_id → SOI → SO
    -- ──────────────────────────────────────────────────────────
    return_items AS (
        SELECT
            -- تاريخ الانعكاس = تاريخ المرتجع الفعلي
            (sr.confirmed_at AT TIME ZONE 'Africa/Cairo')::DATE AS event_date,
            so.branch_id,      -- من البيع الأصلي
            so.customer_id,    -- من البيع الأصلي
            soi.product_id,    -- من بند البيع الأصلي
            COALESCE(so.rep_id, '00000000-0000-0000-0000-000000000000'::UUID) AS rep_id,
            sri.line_total                             AS ret_revenue,
            sri.base_quantity                          AS ret_quantity,
            COALESCE(soi.unit_cost_at_sale, 0)         AS unit_cost
        FROM public.sales_return_items sri
        JOIN public.sales_returns       sr  ON sr.id  = sri.return_id
        JOIN public.sales_order_items   soi ON soi.id = sri.order_item_id
        JOIN public.sales_orders        so  ON so.id  = soi.order_id
        JOIN unnest(p_target_dates)     AS tgt_date
          ON (sr.confirmed_at AT TIME ZONE 'Africa/Cairo')::DATE = tgt_date
        WHERE sr.status = 'confirmed'
    ),
    returns_agg AS (
        SELECT
            event_date                     AS sale_date,
            branch_id, customer_id, product_id, rep_id,
            0::NUMERIC                     AS gross_revenue,
            0::NUMERIC                     AS gross_quantity,
            0::NUMERIC                     AS gross_cogs,
            SUM(ret_revenue)               AS return_revenue,
            SUM(ret_quantity)              AS return_quantity,
            SUM(ret_quantity * unit_cost)  AS return_cogs
        FROM return_items
        GROUP BY event_date, branch_id, customer_id, product_id, rep_id
    ),

    -- ──────────────────────────────────────────────────────────
    -- دمج المسارين: نفس (تاريخ + أبعاد) قد يظهر من المسارين معًا
    -- مثال: بيع Sept-1 ومرتجع لأمر آخر Sept-1 = يُدمجان
    -- ──────────────────────────────────────────────────────────
    all_events AS (
        SELECT * FROM sales_agg
        UNION ALL
        SELECT * FROM returns_agg
    ),
    aggregated AS (
        SELECT
            sale_date, branch_id, customer_id, product_id, rep_id,
            SUM(gross_revenue)   AS gross_revenue,
            SUM(gross_quantity)  AS gross_quantity,
            SUM(gross_cogs)      AS gross_cogs,
            SUM(return_revenue)  AS return_revenue,
            SUM(return_quantity) AS return_quantity,
            SUM(return_cogs)     AS return_cogs
        FROM all_events
        GROUP BY sale_date, branch_id, customer_id, product_id, rep_id
    )

    -- INSERT: branch_id IS NOT NULL
    INSERT INTO analytics.fact_gross_profit_daily_grain (
        sale_date, branch_id, customer_id, product_id, rep_id,
        gross_revenue, gross_quantity, return_revenue, return_quantity,
        gross_cogs, return_cogs
    )
    SELECT
        sale_date, branch_id, customer_id, product_id, rep_id,
        gross_revenue, gross_quantity, return_revenue, return_quantity,
        gross_cogs, return_cogs
    FROM aggregated
    WHERE branch_id IS NOT NULL
    ON CONFLICT (sale_date, branch_id, customer_id, product_id, rep_id)
        WHERE branch_id IS NOT NULL
    DO UPDATE SET
        gross_revenue   = EXCLUDED.gross_revenue,
        gross_quantity  = EXCLUDED.gross_quantity,
        return_revenue  = EXCLUDED.return_revenue,
        return_quantity = EXCLUDED.return_quantity,
        gross_cogs      = EXCLUDED.gross_cogs,
        return_cogs     = EXCLUDED.return_cogs,
        updated_at      = now();

    -- INSERT: branch_id IS NULL (unassigned) — partial index
    INSERT INTO analytics.fact_gross_profit_daily_grain (
        sale_date, branch_id, customer_id, product_id, rep_id,
        gross_revenue, gross_quantity, return_revenue, return_quantity,
        gross_cogs, return_cogs
    )
    SELECT
        sale_date, branch_id, customer_id, product_id, rep_id,
        gross_revenue, gross_quantity, return_revenue, return_quantity,
        gross_cogs, return_cogs
    FROM aggregated
    WHERE branch_id IS NULL
    ON CONFLICT (sale_date, customer_id, product_id, rep_id)
        WHERE branch_id IS NULL
    DO UPDATE SET
        gross_revenue   = EXCLUDED.gross_revenue,
        gross_quantity  = EXCLUDED.gross_quantity,
        return_revenue  = EXCLUDED.return_revenue,
        return_quantity = EXCLUDED.return_quantity,
        gross_cogs      = EXCLUDED.gross_cogs,
        return_cogs     = EXCLUDED.return_cogs,
        updated_at      = now();

END;
$$;

-- ============================================================
-- SECTION 4: internal_refresh_fact_branch_profit_daily
-- صافي ربح مباشر للفرع
-- يعتمد على:
--   - fact_gross_profit_daily_grain (إجمالي ربح)
--   - journal_entries.branch_id للمصروفات والرواتب المباشرة
-- ============================================================

CREATE OR REPLACE PROCEDURE analytics.internal_refresh_fact_branch_profit_daily(
    p_target_dates DATE[]
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_op_ids  UUID[];
    v_pay_ids UUID[];
BEGIN
    IF array_length(p_target_dates, 1) IS NULL THEN RETURN; END IF;

    -- ترجمة رموز الحسابات مرة واحدة
    -- المصروفات التشغيلية المباشرة (5200 series)
    SELECT array_agg(id) INTO v_op_ids
    FROM public.chart_of_accounts
    WHERE code IN ('5200','5210','5220','5230');

    -- الرواتب المباشرة (5310/5320/5330/5335) — 5300 مستبعد
    SELECT array_agg(id) INTO v_pay_ids
    FROM public.chart_of_accounts
    WHERE code IN ('5310','5320','5330','5335');

    -- إيدمبوتنت
    DELETE FROM analytics.fact_branch_profit_daily
    WHERE profit_date = ANY(p_target_dates);

    WITH

    -- ──────────────────────────────────────────────────────────
    -- A. إجمالي ربح من fact_gross_profit_daily_grain
    --    مجمَّع على (sale_date, branch_id) — branch_id IS NULL مسموح
    -- ──────────────────────────────────────────────────────────
    gp_agg AS (
        SELECT
            sale_date        AS profit_date,
            branch_id,
            SUM(net_revenue) AS gross_revenue,
            SUM(net_cogs)    AS gross_cogs,
            SUM(gross_profit) AS gross_profit
        FROM analytics.fact_gross_profit_daily_grain
        WHERE sale_date = ANY(p_target_dates)
        GROUP BY sale_date, branch_id
    ),

    -- ──────────────────────────────────────────────────────────
    -- B. مصروفات تشغيلية مباشرة مرتبطة بالفرع
    --    من journal_entries.branch_id + entry_date
    --    branch_id IS NULL = unassigned
    -- ──────────────────────────────────────────────────────────
    op_exp_agg AS (
        SELECT
            je.entry_date  AS profit_date,
            je.branch_id,
            SUM(jel.debit) AS direct_op
        FROM public.journal_entries      je
        JOIN public.journal_entry_lines  jel ON jel.entry_id = je.id
        WHERE je.status     = 'posted'
          AND je.entry_date = ANY(p_target_dates)
          AND jel.account_id = ANY(v_op_ids)
        GROUP BY je.entry_date, je.branch_id
    ),

    -- ──────────────────────────────────────────────────────────
    -- C. رواتب مباشرة مرتبطة بالفرع (5310-5335 فقط)
    -- ──────────────────────────────────────────────────────────
    pay_exp_agg AS (
        SELECT
            je.entry_date  AS profit_date,
            je.branch_id,
            SUM(jel.debit) AS direct_pay
        FROM public.journal_entries      je
        JOIN public.journal_entry_lines  jel ON jel.entry_id = je.id
        WHERE je.status     = 'posted'
          AND je.entry_date = ANY(p_target_dates)
          AND jel.account_id = ANY(v_pay_ids)
        GROUP BY je.entry_date, je.branch_id
    ),

    -- ──────────────────────────────────────────────────────────
    -- D. union جميع (profit_date, branch_id) الممكنة
    -- ──────────────────────────────────────────────────────────
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
        COALESCE(g.gross_revenue,  0),
        COALESCE(g.gross_cogs,     0),
        COALESCE(g.gross_profit,   0),
        COALESCE(o.direct_op,      0),
        COALESCE(p.direct_pay,     0)
    FROM all_keys k
    LEFT JOIN gp_agg      g ON g.profit_date = k.profit_date
                           AND (g.branch_id = k.branch_id
                                OR (g.branch_id IS NULL AND k.branch_id IS NULL))
    LEFT JOIN op_exp_agg  o ON o.profit_date = k.profit_date
                           AND (o.branch_id = k.branch_id
                                OR (o.branch_id IS NULL AND k.branch_id IS NULL))
    LEFT JOIN pay_exp_agg p ON p.profit_date = k.profit_date
                           AND (p.branch_id = k.branch_id
                                OR (p.branch_id IS NULL AND k.branch_id IS NULL))
    ON CONFLICT (profit_date, branch_id)
        WHERE branch_id IS NOT NULL
    DO UPDATE SET
        gross_revenue        = EXCLUDED.gross_revenue,
        gross_cogs           = EXCLUDED.gross_cogs,
        gross_profit         = EXCLUDED.gross_profit,
        direct_operating_exp = EXCLUDED.direct_operating_exp,
        direct_payroll_exp   = EXCLUDED.direct_payroll_exp,
        updated_at           = now();

    -- معالجة NULL branch_id (unassigned)
    INSERT INTO analytics.fact_branch_profit_daily (
        profit_date, branch_id,
        gross_revenue, gross_cogs, gross_profit,
        direct_operating_exp, direct_payroll_exp
    )
    SELECT
        k.profit_date,
        NULL::UUID,
        COALESCE(g.gross_revenue,  0),
        COALESCE(g.gross_cogs,     0),
        COALESCE(g.gross_profit,   0),
        COALESCE(o.direct_op,      0),
        COALESCE(p.direct_pay,     0)
    FROM all_keys k
    LEFT JOIN gp_agg      g ON g.profit_date = k.profit_date AND g.branch_id IS NULL
    LEFT JOIN op_exp_agg  o ON o.profit_date = k.profit_date AND o.branch_id IS NULL
    LEFT JOIN pay_exp_agg p ON p.profit_date = k.profit_date AND p.branch_id IS NULL
    WHERE k.branch_id IS NULL
    ON CONFLICT (profit_date)
        WHERE branch_id IS NULL
    DO UPDATE SET
        gross_revenue        = EXCLUDED.gross_revenue,
        gross_cogs           = EXCLUDED.gross_cogs,
        gross_profit         = EXCLUDED.gross_profit,
        direct_operating_exp = EXCLUDED.direct_operating_exp,
        direct_payroll_exp   = EXCLUDED.direct_payroll_exp,
        updated_at           = now();

END;
$$;

-- ============================================================
-- SECTION 5: compute_double_review_trust_state
-- تحديث شامل يضيف التحقق الفعلي للجدولين الجديدين
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

    END IF;
END;
$$;

-- ============================================================
-- SECTION 6: orchestrate_incremental_refresh
-- إضافة job names الجديدة — أحدث جسم من 88
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
BEGIN
    -- 1. سجل البداية
    INSERT INTO analytics.etl_runs (id, table_name, status, started_at)
    VALUES (p_run_id, p_job_name, 'RUNNING', now())
    ON CONFLICT (id) DO UPDATE SET status = 'RUNNING', started_at = now();

    -- 2. تنظيف التواريخ
    SELECT array_agg(d ORDER BY d ASC) INTO v_normalized_dates
    FROM (SELECT DISTINCT unnest(p_target_dates) AS d) sub;

    v_total := coalesce(array_length(v_normalized_dates, 1), 0);

    IF v_total = 0 THEN
        UPDATE analytics.etl_runs
        SET status = 'SUCCESS', completed_at = now(),
            log_output = jsonb_build_object('message', 'No dates to process')
        WHERE id = p_run_id;
        RETURN;
    END IF;

    -- 3. تنفيذ بالشرائح
    BEGIN
        WHILE (v_chunk_idx * v_chunk_size) < v_total LOOP
            v_chunk_dates := v_normalized_dates[
                (v_chunk_idx * v_chunk_size) + 1 :
                LEAST((v_chunk_idx + 1) * v_chunk_size, v_total)
            ];
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
                -- ── المرحلة الثانية ────────────────────────────────
                ELSIF p_job_name = 'fact_gross_profit_daily_grain' THEN
                    CALL analytics.internal_refresh_fact_gross_profit_daily_grain(v_chunk_dates);
                ELSIF p_job_name = 'fact_branch_profit_daily' THEN
                    CALL analytics.internal_refresh_fact_branch_profit_daily(v_chunk_dates);
                ELSE
                    RAISE EXCEPTION 'Unknown job: %', p_job_name;
                END IF;

                v_chunks_detail := v_chunks_detail || jsonb_build_object(
                    'idx', v_chunk_idx, 'count', v_chunk_count,
                    'min_date', v_min_date, 'max_date', v_max_date, 'status', 'SUCCESS'
                );
            END IF;

            v_chunk_idx := v_chunk_idx + 1;
        END LOOP;

        UPDATE analytics.etl_runs
        SET status = 'SUCCESS', completed_at = now(),
            log_output = jsonb_build_object(
                'affected_dates_count', v_total,
                'min_affected_date',    v_normalized_dates[1],
                'max_affected_date',    v_normalized_dates[v_total],
                'chunks_processed',     v_chunk_idx,
                'chunks_detail',        v_chunks_detail
            )
        WHERE id = p_run_id;

        -- trust state
        CALL analytics.compute_double_review_trust_state(p_run_id, p_job_name, v_normalized_dates);

    EXCEPTION WHEN OTHERS THEN
        UPDATE analytics.etl_runs
        SET status       = 'FAILED',
            completed_at = now(),
            log_output   = jsonb_build_object(
                'error', SQLERRM, 'state', SQLSTATE,
                'failed_at_chunk_idx', v_chunk_idx, 'total_normalized_dates', v_total
            )
        WHERE id = p_run_id;
    END;
END;
$$;

-- ============================================================
-- SECTION 7: run_analytics_watermark_sweep
-- إضافة الجدولين الجديدين — أحدث جسم من 88
-- ملاحظة: fact_gross_profit_daily_grain أولًا ثم fact_branch_profit_daily
--         لأن الثاني يقرأ من الأول
-- ============================================================

CREATE OR REPLACE PROCEDURE analytics.run_analytics_watermark_sweep(
    p_fallback_days INTEGER DEFAULT 3
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_watermark      TIMESTAMPTZ;
    v_sweep_start    TIMESTAMPTZ := now();
    v_target_dates   DATE[];
    v_lock_obtained  BOOLEAN;
    v_failed_subjobs INTEGER := 0;
    v_sweep_id       UUID := gen_random_uuid();
    v_run_id_1       UUID := gen_random_uuid();
    v_run_id_2       UUID := gen_random_uuid();
    v_run_id_3       UUID := gen_random_uuid();
    v_run_id_4       UUID := gen_random_uuid();
    v_run_id_5       UUID := gen_random_uuid();
    v_run_id_6       UUID := gen_random_uuid();
    v_run_id_7       UUID := gen_random_uuid();
    v_run_id_8       UUID := gen_random_uuid();
    v_run_id_9       UUID := gen_random_uuid();
    v_run_id_10      UUID := gen_random_uuid();
    v_run_id_11      UUID := gen_random_uuid();
BEGIN
    SELECT pg_try_advisory_lock(hashtext('analytics_global_sweep')) INTO v_lock_obtained;
    IF NOT v_lock_obtained THEN
        RAISE NOTICE 'Analytics sweep locked elsewhere — exiting.';
        RETURN;
    END IF;

    BEGIN
        SELECT COALESCE(MAX(started_at), now() - (p_fallback_days || ' days')::interval)
        INTO v_watermark
        FROM analytics.etl_runs
        WHERE table_name = 'GLOBAL_SWEEP'
          AND status IN ('SUCCESS', 'POSTING_CONSISTENCY_ONLY', 'VERIFIED', 'RECONCILED_WITH_WARNING');

        INSERT INTO analytics.etl_runs (id, table_name, status, started_at)
        VALUES (v_sweep_id, 'GLOBAL_SWEEP', 'RUNNING', v_sweep_start);

        SELECT analytics.detect_affected_dates(v_watermark) INTO v_target_dates;

        IF array_length(v_target_dates, 1) IS NOT NULL THEN
            -- ── الجداول الأساسية ─────────────────────────────
            CALL analytics.orchestrate_incremental_refresh(v_run_id_1,  'fact_sales_daily_grain',                             v_target_dates);
            CALL analytics.orchestrate_incremental_refresh(v_run_id_2,  'fact_financial_ledgers_daily',                       v_target_dates);
            CALL analytics.orchestrate_incremental_refresh(v_run_id_3,  'fact_treasury_cashflow_daily',                       v_target_dates);
            CALL analytics.orchestrate_incremental_refresh(v_run_id_4,  'fact_ar_collections_attributed_to_origin_sale_date', v_target_dates);
            CALL analytics.orchestrate_incremental_refresh(v_run_id_5,  'snapshot_customer_health',                           v_target_dates);
            CALL analytics.orchestrate_incremental_refresh(v_run_id_6,  'snapshot_customer_risk',                             v_target_dates);
            CALL analytics.orchestrate_incremental_refresh(v_run_id_8,  'fact_geography_daily',                               v_target_dates);
            CALL analytics.orchestrate_incremental_refresh(v_run_id_9,  'fact_profit_daily',                                  v_target_dates);
            -- ── المرحلة الثانية: grain أولًا ثم branch ──────
            CALL analytics.orchestrate_incremental_refresh(v_run_id_10, 'fact_gross_profit_daily_grain',                      v_target_dates);
            CALL analytics.orchestrate_incremental_refresh(v_run_id_11, 'fact_branch_profit_daily',                           v_target_dates);
        END IF;

        -- الأهداف تعمل يوميًا بشكل مستقل
        CALL analytics.orchestrate_incremental_refresh(v_run_id_7, 'snapshot_target_attainment', ARRAY[CURRENT_DATE]::DATE[]);

        SELECT COUNT(*) INTO v_failed_subjobs
        FROM analytics.etl_runs
        WHERE id IN (
            v_run_id_1, v_run_id_2, v_run_id_3, v_run_id_4,
            v_run_id_5, v_run_id_6, v_run_id_7, v_run_id_8,
            v_run_id_9, v_run_id_10, v_run_id_11
        ) AND status IN ('FAILED', 'BLOCKED');

        IF v_failed_subjobs > 0 THEN
            UPDATE analytics.etl_runs SET status = 'PARTIAL_FAILURE', completed_at = now() WHERE id = v_sweep_id;
        ELSE
            UPDATE analytics.etl_runs SET status = 'SUCCESS', completed_at = now() WHERE id = v_sweep_id;
        END IF;

        PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));

    EXCEPTION WHEN OTHERS THEN
        UPDATE analytics.etl_runs
        SET status = 'FAILED', completed_at = now(),
            log_output = jsonb_build_object('error', SQLERRM, 'state', SQLSTATE)
        WHERE id = v_sweep_id;
        PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));
        RAISE;
    END;
END;
$$;

-- ============================================================
-- SECTION 8: run_historical_backfill
-- إضافة الجدولين الجديدين — أحدث جسم من 88
-- ============================================================

CREATE OR REPLACE PROCEDURE analytics.run_historical_backfill(
    p_start_date DATE,
    p_end_date   DATE    DEFAULT CURRENT_DATE,
    p_chunk_days INTEGER DEFAULT 7
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_chunk_start   DATE;
    v_chunk_end     DATE;
    v_chunk_dates   DATE[];
    v_lock_obtained BOOLEAN;
    v_chunks_done   INTEGER := 0;
BEGIN
    IF p_start_date > p_end_date THEN
        RAISE EXCEPTION 'start_date (%) must be <= end_date (%)', p_start_date, p_end_date;
    END IF;
    IF p_chunk_days < 1 OR p_chunk_days > 30 THEN
        RAISE EXCEPTION 'p_chunk_days must be between 1 and 30 (got %)', p_chunk_days;
    END IF;

    SELECT pg_try_advisory_lock(hashtext('analytics_global_sweep')) INTO v_lock_obtained;
    IF NOT v_lock_obtained THEN
        RAISE EXCEPTION 'Analytics sweep is running elsewhere. Backfill cannot start.';
    END IF;

    BEGIN
        v_chunk_start := p_start_date;
        WHILE v_chunk_start <= p_end_date LOOP
            v_chunk_end := LEAST(v_chunk_start + (p_chunk_days - 1), p_end_date);
            RAISE NOTICE 'Backfilling chunk %: % to %', v_chunks_done + 1, v_chunk_start, v_chunk_end;

            SELECT array_agg(d::date) INTO v_chunk_dates
            FROM generate_series(v_chunk_start, v_chunk_end, '1 day'::interval) d;

            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_sales_daily_grain',                             v_chunk_dates);
            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_financial_ledgers_daily',                       v_chunk_dates);
            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_treasury_cashflow_daily',                       v_chunk_dates);
            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_ar_collections_attributed_to_origin_sale_date', v_chunk_dates);
            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'snapshot_customer_health',                           v_chunk_dates);
            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'snapshot_customer_risk',                             v_chunk_dates);
            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_geography_daily',                               v_chunk_dates);
            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_profit_daily',                                  v_chunk_dates);
            -- ── المرحلة الثانية: grain أولًا ────────────────
            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_gross_profit_daily_grain',                      v_chunk_dates);
            CALL analytics.orchestrate_incremental_refresh(gen_random_uuid(), 'fact_branch_profit_daily',                           v_chunk_dates);

            v_chunks_done := v_chunks_done + 1;
            v_chunk_start := v_chunk_end + 1;
        END LOOP;

        RAISE NOTICE 'Historical backfill completed. Chunks processed: %', v_chunks_done;
        PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));

    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));
        RAISE;
    END;
END;
$$;

-- ============================================================
-- SECTION 9: دوال القراءة العامة (RLS-guarded)
-- ============================================================
-- توقيعات الدوال:
--   p_branch_id   UUID    DEFAULT NULL  → NULL = بلا فلتر (كل الفروع + unassigned)
--                                         UUID  = فرع محدد فقط
--   p_granularity TEXT    DEFAULT 'aggregate' → 'aggregate' | 'daily' | 'monthly'
--   p_limit_count INTEGER DEFAULT NULL  → NULL = بلا حد، N = أعلى N حسب gross_profit
-- ============================================================

-- ──────────────────────────────────────────────────────────────
-- 9-A: إجمالي ربح حسب المنتج (gross profit only — لا صافي)
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.analytics_gross_profit_by_product(
    date_from     DATE,
    date_to       DATE,
    p_branch_id   UUID    DEFAULT NULL,   -- NULL = بلا فلتر
    p_granularity TEXT    DEFAULT 'aggregate', -- 'aggregate' | 'daily' | 'monthly'
    p_limit_count INTEGER DEFAULT NULL    -- NULL = بلا حد عدد
)
RETURNS TABLE (
    period        TEXT,
    product_id    UUID,
    gross_revenue NUMERIC,
    net_cogs      NUMERIC,
    gross_profit  NUMERIC,
    net_quantity  NUMERIC
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    IF NOT public.check_permission(auth.uid(), 'reports.view_all')
       AND NOT public.check_permission(auth.uid(), 'reports.financial') THEN
        RAISE EXCEPTION 'Access denied. Requires reports.view_all or reports.financial';
    END IF;

    IF p_granularity NOT IN ('aggregate', 'daily', 'monthly') THEN
        RAISE EXCEPTION 'Unsupported granularity: %. Use aggregate, daily, or monthly', p_granularity;
    END IF;

    IF p_granularity = 'daily' THEN
        RETURN QUERY
        SELECT
            g.sale_date::TEXT            AS period,
            g.product_id,
            SUM(g.net_revenue)           AS gross_revenue,
            SUM(g.net_cogs)              AS net_cogs,
            SUM(g.gross_profit)          AS gross_profit,
            SUM(g.net_quantity)          AS net_quantity
        FROM analytics.fact_gross_profit_daily_grain g
        WHERE g.sale_date >= date_from AND g.sale_date <= date_to
          AND (p_branch_id IS NULL OR g.branch_id = p_branch_id)
        GROUP BY g.sale_date, g.product_id
        ORDER BY g.sale_date ASC, SUM(g.gross_profit) DESC NULLS LAST
        LIMIT p_limit_count;

    ELSIF p_granularity = 'monthly' THEN
        RETURN QUERY
        SELECT
            to_char(date_trunc('month', g.sale_date)::DATE, 'YYYY-MM') AS period,
            g.product_id,
            SUM(g.net_revenue)::NUMERIC  AS gross_revenue,
            SUM(g.net_cogs)::NUMERIC     AS net_cogs,
            SUM(g.gross_profit)::NUMERIC AS gross_profit,
            SUM(g.net_quantity)::NUMERIC AS net_quantity
        FROM analytics.fact_gross_profit_daily_grain g
        WHERE g.sale_date >= date_from AND g.sale_date <= date_to
          AND (p_branch_id IS NULL OR g.branch_id = p_branch_id)
        GROUP BY date_trunc('month', g.sale_date), g.product_id
        ORDER BY 1 ASC, SUM(g.gross_profit) DESC NULLS LAST
        LIMIT p_limit_count;

    ELSE -- 'aggregate'
        RETURN QUERY
        SELECT
            (date_from::TEXT || ' / ' || date_to::TEXT) AS period,
            g.product_id,
            SUM(g.net_revenue)           AS gross_revenue,
            SUM(g.net_cogs)              AS net_cogs,
            SUM(g.gross_profit)          AS gross_profit,
            SUM(g.net_quantity)          AS net_quantity
        FROM analytics.fact_gross_profit_daily_grain g
        WHERE g.sale_date >= date_from AND g.sale_date <= date_to
          AND (p_branch_id IS NULL OR g.branch_id = p_branch_id)
        GROUP BY g.product_id
        ORDER BY SUM(g.gross_profit) DESC NULLS LAST
        LIMIT p_limit_count;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.analytics_gross_profit_by_product(DATE, DATE, UUID, TEXT, INTEGER) TO authenticated;

-- ──────────────────────────────────────────────────────────────
-- 9-B: إجمالي ربح حسب العميل (gross profit only — لا صافي)
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.analytics_gross_profit_by_customer(
    date_from     DATE,
    date_to       DATE,
    p_branch_id   UUID    DEFAULT NULL,
    p_granularity TEXT    DEFAULT 'aggregate',
    p_limit_count INTEGER DEFAULT NULL
)
RETURNS TABLE (
    period        TEXT,
    customer_id   UUID,
    gross_revenue NUMERIC,
    net_cogs      NUMERIC,
    gross_profit  NUMERIC,
    net_quantity  NUMERIC
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    IF NOT public.check_permission(auth.uid(), 'reports.view_all')
       AND NOT public.check_permission(auth.uid(), 'reports.financial') THEN
        RAISE EXCEPTION 'Access denied. Requires reports.view_all or reports.financial';
    END IF;

    IF p_granularity NOT IN ('aggregate', 'daily', 'monthly') THEN
        RAISE EXCEPTION 'Unsupported granularity: %. Use aggregate, daily, or monthly', p_granularity;
    END IF;

    IF p_granularity = 'daily' THEN
        RETURN QUERY
        SELECT
            g.sale_date::TEXT            AS period,
            g.customer_id,
            SUM(g.net_revenue)           AS gross_revenue,
            SUM(g.net_cogs)              AS net_cogs,
            SUM(g.gross_profit)          AS gross_profit,
            SUM(g.net_quantity)          AS net_quantity
        FROM analytics.fact_gross_profit_daily_grain g
        WHERE g.sale_date >= date_from AND g.sale_date <= date_to
          AND (p_branch_id IS NULL OR g.branch_id = p_branch_id)
        GROUP BY g.sale_date, g.customer_id
        ORDER BY g.sale_date ASC, SUM(g.gross_profit) DESC NULLS LAST
        LIMIT p_limit_count;

    ELSIF p_granularity = 'monthly' THEN
        RETURN QUERY
        SELECT
            to_char(date_trunc('month', g.sale_date)::DATE, 'YYYY-MM') AS period,
            g.customer_id,
            SUM(g.net_revenue)::NUMERIC  AS gross_revenue,
            SUM(g.net_cogs)::NUMERIC     AS net_cogs,
            SUM(g.gross_profit)::NUMERIC AS gross_profit,
            SUM(g.net_quantity)::NUMERIC AS net_quantity
        FROM analytics.fact_gross_profit_daily_grain g
        WHERE g.sale_date >= date_from AND g.sale_date <= date_to
          AND (p_branch_id IS NULL OR g.branch_id = p_branch_id)
        GROUP BY date_trunc('month', g.sale_date), g.customer_id
        ORDER BY 1 ASC, SUM(g.gross_profit) DESC NULLS LAST
        LIMIT p_limit_count;

    ELSE -- 'aggregate'
        RETURN QUERY
        SELECT
            (date_from::TEXT || ' / ' || date_to::TEXT) AS period,
            g.customer_id,
            SUM(g.net_revenue)           AS gross_revenue,
            SUM(g.net_cogs)              AS net_cogs,
            SUM(g.gross_profit)          AS gross_profit,
            SUM(g.net_quantity)          AS net_quantity
        FROM analytics.fact_gross_profit_daily_grain g
        WHERE g.sale_date >= date_from AND g.sale_date <= date_to
          AND (p_branch_id IS NULL OR g.branch_id = p_branch_id)
        GROUP BY g.customer_id
        ORDER BY SUM(g.gross_profit) DESC NULLS LAST
        LIMIT p_limit_count;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.analytics_gross_profit_by_customer(DATE, DATE, UUID, TEXT, INTEGER) TO authenticated;

-- ──────────────────────────────────────────────────────────────
-- 9-C: إجمالي ربح حسب المندوب (gross profit only — لا صافي)
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.analytics_gross_profit_by_rep(
    date_from     DATE,
    date_to       DATE,
    p_branch_id   UUID    DEFAULT NULL,
    p_granularity TEXT    DEFAULT 'aggregate',
    p_limit_count INTEGER DEFAULT NULL
)
RETURNS TABLE (
    period        TEXT,
    rep_id        UUID,
    gross_revenue NUMERIC,
    net_cogs      NUMERIC,
    gross_profit  NUMERIC,
    net_quantity  NUMERIC
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    IF NOT public.check_permission(auth.uid(), 'reports.view_all')
       AND NOT public.check_permission(auth.uid(), 'reports.financial') THEN
        RAISE EXCEPTION 'Access denied. Requires reports.view_all or reports.financial';
    END IF;

    IF p_granularity NOT IN ('aggregate', 'daily', 'monthly') THEN
        RAISE EXCEPTION 'Unsupported granularity: %. Use aggregate, daily, or monthly', p_granularity;
    END IF;

    IF p_granularity = 'daily' THEN
        RETURN QUERY
        SELECT
            g.sale_date::TEXT            AS period,
            g.rep_id,
            SUM(g.net_revenue)           AS gross_revenue,
            SUM(g.net_cogs)              AS net_cogs,
            SUM(g.gross_profit)          AS gross_profit,
            SUM(g.net_quantity)          AS net_quantity
        FROM analytics.fact_gross_profit_daily_grain g
        WHERE g.sale_date >= date_from AND g.sale_date <= date_to
          AND (p_branch_id IS NULL OR g.branch_id = p_branch_id)
        GROUP BY g.sale_date, g.rep_id
        ORDER BY g.sale_date ASC, SUM(g.gross_profit) DESC NULLS LAST
        LIMIT p_limit_count;

    ELSIF p_granularity = 'monthly' THEN
        RETURN QUERY
        SELECT
            to_char(date_trunc('month', g.sale_date)::DATE, 'YYYY-MM') AS period,
            g.rep_id,
            SUM(g.net_revenue)::NUMERIC  AS gross_revenue,
            SUM(g.net_cogs)::NUMERIC     AS net_cogs,
            SUM(g.gross_profit)::NUMERIC AS gross_profit,
            SUM(g.net_quantity)::NUMERIC AS net_quantity
        FROM analytics.fact_gross_profit_daily_grain g
        WHERE g.sale_date >= date_from AND g.sale_date <= date_to
          AND (p_branch_id IS NULL OR g.branch_id = p_branch_id)
        GROUP BY date_trunc('month', g.sale_date), g.rep_id
        ORDER BY 1 ASC, SUM(g.gross_profit) DESC NULLS LAST
        LIMIT p_limit_count;

    ELSE -- 'aggregate'
        RETURN QUERY
        SELECT
            (date_from::TEXT || ' / ' || date_to::TEXT) AS period,
            g.rep_id,
            SUM(g.net_revenue)           AS gross_revenue,
            SUM(g.net_cogs)              AS net_cogs,
            SUM(g.gross_profit)          AS gross_profit,
            SUM(g.net_quantity)          AS net_quantity
        FROM analytics.fact_gross_profit_daily_grain g
        WHERE g.sale_date >= date_from AND g.sale_date <= date_to
          AND (p_branch_id IS NULL OR g.branch_id = p_branch_id)
        GROUP BY g.rep_id
        ORDER BY SUM(g.gross_profit) DESC NULLS LAST
        LIMIT p_limit_count;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.analytics_gross_profit_by_rep(DATE, DATE, UUID, TEXT, INTEGER) TO authenticated;

-- ──────────────────────────────────────────────────────────────
-- 9-D: صافي ربح مباشر للفرع
--      p_branch_id = NULL → كل الفروع + unassigned
--      p_branch_id = UUID → فرع محدد
--      branch_id IS NULL يظهر دائمًا كسطر مستقل (unassigned)
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.analytics_branch_direct_net_profit(
    date_from   DATE,
    date_to     DATE,
    p_branch_id UUID DEFAULT NULL   -- NULL = كل الفروع
)
RETURNS TABLE (
    branch_id            UUID,
    gross_revenue        NUMERIC,
    gross_cogs           NUMERIC,
    gross_profit         NUMERIC,
    direct_operating_exp NUMERIC,
    direct_payroll_exp   NUMERIC,
    direct_net_profit    NUMERIC
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    IF NOT public.check_permission(auth.uid(), 'reports.view_all')
       AND NOT public.check_permission(auth.uid(), 'reports.financial') THEN
        RAISE EXCEPTION 'Access denied. Requires reports.view_all or reports.financial';
    END IF;

    RETURN QUERY
    SELECT
        b.branch_id,
        SUM(b.gross_revenue)        AS gross_revenue,
        SUM(b.gross_cogs)           AS gross_cogs,
        SUM(b.gross_profit)         AS gross_profit,
        SUM(b.direct_operating_exp) AS direct_operating_exp,
        SUM(b.direct_payroll_exp)   AS direct_payroll_exp,
        SUM(b.direct_net_profit)    AS direct_net_profit
    FROM analytics.fact_branch_profit_daily b
    WHERE b.profit_date >= date_from AND b.profit_date <= date_to
      AND (p_branch_id IS NULL OR b.branch_id = p_branch_id)
    GROUP BY b.branch_id
    ORDER BY
        (b.branch_id IS NULL) ASC,
        SUM(b.direct_net_profit) DESC NULLS LAST;
END;
$$;

GRANT EXECUTE ON FUNCTION public.analytics_branch_direct_net_profit(DATE, DATE, UUID) TO authenticated;

-- ──────────────────────────────────────────────────────────────
-- 9-E: ترند صافي ربح الفرع (يومي / شهري)
--      p_branch_id → فلتر اختياري للفرع
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.analytics_branch_profit_trend(
    date_from    DATE,
    date_to      DATE,
    p_granularity TEXT DEFAULT 'monthly',
    p_branch_id  UUID DEFAULT NULL
)
RETURNS TABLE (
    period            TEXT,
    branch_id         UUID,
    gross_profit      NUMERIC,
    direct_net_profit NUMERIC
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    IF NOT public.check_permission(auth.uid(), 'reports.view_all')
       AND NOT public.check_permission(auth.uid(), 'reports.financial') THEN
        RAISE EXCEPTION 'Access denied. Requires reports.view_all or reports.financial';
    END IF;

    IF p_granularity NOT IN ('daily', 'monthly') THEN
        RAISE EXCEPTION 'Unsupported granularity %. Only daily, monthly are allowed', p_granularity;
    END IF;

    IF p_granularity = 'daily' THEN
        RETURN QUERY
        SELECT
            to_char(b.profit_date, 'YYYY-MM-DD') AS period,
            b.branch_id,
            SUM(b.gross_profit)      AS gross_profit,
            SUM(b.direct_net_profit) AS direct_net_profit
        FROM analytics.fact_branch_profit_daily b
        WHERE b.profit_date >= date_from AND b.profit_date <= date_to
          AND (p_branch_id IS NULL OR b.branch_id = p_branch_id)
        GROUP BY b.profit_date, b.branch_id
        ORDER BY b.profit_date ASC, (b.branch_id IS NULL) ASC, b.branch_id;
    ELSE
        RETURN QUERY
        SELECT
            to_char(date_trunc('month', b.profit_date)::DATE, 'YYYY-MM') AS period,
            b.branch_id,
            SUM(b.gross_profit)::NUMERIC      AS gross_profit,
            SUM(b.direct_net_profit)::NUMERIC AS direct_net_profit
        FROM analytics.fact_branch_profit_daily b
        WHERE b.profit_date >= date_from AND b.profit_date <= date_to
          AND (p_branch_id IS NULL OR b.branch_id = p_branch_id)
        GROUP BY date_trunc('month', b.profit_date), b.branch_id
        ORDER BY 1 ASC, (b.branch_id IS NULL) ASC, b.branch_id;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.analytics_branch_profit_trend(DATE, DATE, TEXT, UUID) TO authenticated;
