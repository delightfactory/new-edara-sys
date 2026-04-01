-- ============================================================
-- 22b_target_calc.sql
-- EDARA v2 — محرك الأهداف: الحساب والمنطق
-- يُصلح خلل احتساب المبيعات المفلترة (soi.line_total)
-- يُضيف منطق upgrade_value وcategory_spread
-- يُنشئ دالة calc_target_pool_value() للمكافأة النسبية
-- Idempotent: آمن للتشغيل أكثر من مرة
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- SECTION 1: تحديث target_types — تفعيل upgrade_value وcategory_spread
-- ════════════════════════════════════════════════════════════

-- إصلاح upgrade_value:
-- target_value = عدد العملاء المطلوب ترقيتهم   (unit='count')
-- نسبة النمو المطلوبة تُخزَّن في filter_criteria->>'growth_pct'
-- مثال: target_value=8, filter_criteria={"growth_pct":30} = ارفع 8 عملاء بنسبة 30%
UPDATE public.target_types SET
  unit               = 'count',            -- عدد العملاء (ليس نسبة — تصحيح نهائي)
  auto_source        = 'sales_orders',
  auto_calc_enabled  = true,
  description        = 'رفع قيمة مشتريات عملاء محددين — target_value=عدد العملاء، filter_criteria.growth_pct=نسبة النمو المطلوبة'
WHERE code = 'upgrade_value';

-- تفعيل category_spread
UPDATE public.target_types SET
  auto_source        = 'sales_orders',
  auto_calc_enabled  = true,
  description        = 'رفع عدد تصنيفات المنتجات التي يتعامل عليها عملاء محددون'
WHERE code = 'category_spread';

-- ════════════════════════════════════════════════════════════
-- SECTION 2: إعادة كتابة recalculate_target_progress
-- إصلاح: sales_value المفلترة → SUM(soi.line_total) لا SUM(so.total_amount)
-- إضافة: CASE لـ upgrade_value وcategory_spread
-- إضافة: حساب expected_reward في calc_details
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.recalculate_target_progress(
  p_target_id     UUID,
  p_snapshot_date DATE DEFAULT CURRENT_DATE
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_target       public.targets%ROWTYPE;
  v_achieved     NUMERIC := 0;
  v_trend        VARCHAR(20);
  v_days_elapsed NUMERIC;
  v_total_days   NUMERIC;
  v_expected_pct NUMERIC;
  v_pct          NUMERIC;
  v_employee_ids UUID[];
  -- لحساب expected_reward
  v_best_tier    public.target_reward_tiers%ROWTYPE;
  v_expected_rwd NUMERIC := 0;
BEGIN
  SELECT * INTO v_target FROM public.targets
  WHERE id = p_target_id AND is_active = true AND is_paused = false;
  IF NOT FOUND THEN RETURN; END IF;

  -- ══════════════════════════════════════════════════════════
  -- تجميع الموظفين حسب النطاق
  -- ══════════════════════════════════════════════════════════
  CASE v_target.scope
    WHEN 'individual' THEN
      v_employee_ids := ARRAY[v_target.scope_id];

    WHEN 'branch' THEN
      SELECT ARRAY_AGG(id) INTO v_employee_ids
      FROM hr_employees
      WHERE branch_id = v_target.scope_id AND status = 'active';

    WHEN 'department' THEN
      SELECT ARRAY_AGG(id) INTO v_employee_ids
      FROM hr_employees
      WHERE department_id = v_target.scope_id AND status = 'active';

    WHEN 'company' THEN
      SELECT ARRAY_AGG(id) INTO v_employee_ids
      FROM hr_employees WHERE status = 'active';

    ELSE
      v_employee_ids := ARRAY[]::UUID[];
  END CASE;

  IF v_employee_ids IS NULL OR array_length(v_employee_ids, 1) IS NULL THEN
    v_employee_ids := ARRAY[]::UUID[];
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- حساب القيمة المحققة — بالمنطق الصحيح لكل نوع
  -- ══════════════════════════════════════════════════════════
  CASE v_target.type_code

    WHEN 'sales_value' THEN
      -- ★ الإصلاح الجوهري: فلتر منتج/تصنيف → نجمع فقط line_total البنود المطابقة
      IF v_target.product_id IS NOT NULL OR v_target.category_id IS NOT NULL THEN
        SELECT COALESCE(SUM(soi.line_total), 0) INTO v_achieved
        FROM sales_orders so
        JOIN hr_employees he ON he.user_id = so.rep_id
        JOIN sales_order_items soi ON soi.order_id = so.id
        JOIN customers c ON c.id = so.customer_id
        LEFT JOIN products p ON p.id = soi.product_id
        WHERE he.id = ANY(v_employee_ids)
          AND so.status IN ('delivered','completed')
          AND so.delivered_at::DATE BETWEEN v_target.period_start AND p_snapshot_date
          AND (v_target.product_id  IS NULL OR soi.product_id = v_target.product_id)
          AND (v_target.category_id IS NULL OR p.category_id  = v_target.category_id)
          AND (v_target.governorate_id IS NULL OR c.governorate_id = v_target.governorate_id)
          AND (v_target.city_id        IS NULL OR c.city_id        = v_target.city_id)
          AND (v_target.area_id        IS NULL OR c.area_id        = v_target.area_id);
      ELSE
        -- بدون فلتر منتج: إجمالي الطلب صحيح (لا مشكلة)
        SELECT COALESCE(SUM(so.total_amount), 0) INTO v_achieved
        FROM sales_orders so
        JOIN hr_employees he ON he.user_id = so.rep_id
        JOIN customers c ON c.id = so.customer_id
        WHERE he.id = ANY(v_employee_ids)
          AND so.status IN ('delivered','completed')
          AND so.delivered_at::DATE BETWEEN v_target.period_start AND p_snapshot_date
          AND (v_target.governorate_id IS NULL OR c.governorate_id = v_target.governorate_id)
          AND (v_target.city_id        IS NULL OR c.city_id        = v_target.city_id)
          AND (v_target.area_id        IS NULL OR c.area_id        = v_target.area_id);
      END IF;

    WHEN 'collection' THEN
      SELECT COALESCE(SUM(pr.amount), 0) INTO v_achieved
      FROM payment_receipts pr
      JOIN hr_employees he ON he.user_id = pr.collected_by
      WHERE he.id = ANY(v_employee_ids)
        AND pr.status = 'confirmed'
        AND pr.created_at::DATE BETWEEN v_target.period_start AND p_snapshot_date;

    WHEN 'visits_count' THEN
      SELECT COUNT(*) INTO v_achieved
      FROM public.activities a
      JOIN public.activity_types at_ ON at_.id = a.type_id
      WHERE a.employee_id = ANY(v_employee_ids)
        AND at_.category = 'visit'
        AND a.activity_date BETWEEN v_target.period_start AND p_snapshot_date
        AND a.deleted_at IS NULL;

    WHEN 'calls_count' THEN
      SELECT COUNT(*) INTO v_achieved
      FROM public.activities a
      JOIN public.activity_types at_ ON at_.id = a.type_id
      WHERE a.employee_id = ANY(v_employee_ids)
        AND at_.category = 'call'
        AND a.activity_date BETWEEN v_target.period_start AND p_snapshot_date
        AND a.deleted_at IS NULL;

    WHEN 'new_customers' THEN
      SELECT COUNT(*) INTO v_achieved
      FROM customers c
      WHERE c.assigned_rep_id IN (
          SELECT user_id FROM hr_employees WHERE id = ANY(v_employee_ids)
        )
        AND c.created_at::DATE BETWEEN v_target.period_start AND p_snapshot_date
        AND c.is_active = true;

    WHEN 'reactivation' THEN
      SELECT COUNT(DISTINCT a.customer_id) INTO v_achieved
      FROM public.activities a
      LEFT JOIN customers c ON c.id = a.customer_id
      WHERE a.employee_id = ANY(v_employee_ids)
        AND a.outcome_type IN ('order_placed', 'agreed_order')
        AND a.customer_id IS NOT NULL
        AND a.activity_date BETWEEN v_target.period_start AND p_snapshot_date
        AND a.deleted_at IS NULL
        AND (v_target.governorate_id IS NULL OR c.governorate_id = v_target.governorate_id)
        AND (v_target.city_id        IS NULL OR c.city_id        = v_target.city_id)
        AND (v_target.area_id        IS NULL OR c.area_id        = v_target.area_id)
        AND NOT EXISTS (
          SELECT 1 FROM sales_orders so
          WHERE so.customer_id = a.customer_id
            AND so.status IN ('delivered','completed')
            AND so.delivered_at >= v_target.period_start
                - (COALESCE(v_target.dormancy_days, 60) || ' days')::INTERVAL
            AND so.delivered_at < v_target.period_start
        );

    WHEN 'product_qty' THEN
      SELECT COALESCE(SUM(soi.base_quantity), 0) INTO v_achieved
      FROM sales_order_items soi
      JOIN sales_orders so ON so.id = soi.order_id
      JOIN hr_employees he ON he.user_id = so.rep_id
      WHERE he.id = ANY(v_employee_ids)
        AND so.status IN ('delivered','completed')
        AND so.delivered_at::DATE BETWEEN v_target.period_start AND p_snapshot_date
        AND (v_target.product_id  IS NULL OR soi.product_id = v_target.product_id)
        AND (v_target.category_id IS NULL OR soi.product_id IN (
          SELECT id FROM products WHERE category_id = v_target.category_id
        ));

    -- ★ جديد: upgrade_value — عدد العملاء الذين حققوا نمو المشتريات المستهدف
    -- [P1 FIX] target_value = عدد العملاء المطلوب ترقيتهم (مثلاً 8 عملاء)
    -- growth_pct مُخزَّن في filter_criteria->>'growth_pct' (مثلاً 30%)
    -- achievement_pct = v_achieved / target_value × 100 (صحيح تماماً)
    WHEN 'upgrade_value' THEN
      DECLARE
        v_required_growth NUMERIC;
      BEGIN
        v_required_growth := COALESCE((v_target.filter_criteria->>'growth_pct')::NUMERIC, 0);
        SELECT COUNT(*) INTO v_achieved
        FROM public.target_customers tc
        LEFT JOIN LATERAL (
          SELECT COALESCE(SUM(so.total_amount), 0) AS period_sales
          FROM sales_orders so
          WHERE so.customer_id = tc.customer_id
            AND so.status IN ('delivered','completed')
            AND so.delivered_at::DATE BETWEEN v_target.period_start AND p_snapshot_date
        ) pa ON true
        WHERE tc.target_id = p_target_id
          -- العميل نجح إذا تجاوزت مشترياته: baseline × (1 + growth_pct%)
          AND pa.period_sales >= COALESCE(tc.baseline_value, 0) * (1 + v_required_growth / 100.0);
        -- v_achieved = عدد العملاء الناجحين
        -- v_pct = v_achieved / target_value × 100 (صحيح: عدد/عدد × 100)
      END;

    -- ★ جديد: category_spread — عدد العملاء الذين وصلوا للعدد المستهدف من التصنيفات
    WHEN 'category_spread' THEN
      SELECT COUNT(*) INTO v_achieved
      FROM (
        SELECT tc.customer_id, COUNT(DISTINCT p.category_id) AS cat_count
        FROM public.target_customers tc
        JOIN sales_orders so ON so.customer_id = tc.customer_id
          AND so.status IN ('delivered','completed')
          AND so.delivered_at::DATE BETWEEN v_target.period_start AND p_snapshot_date
        JOIN sales_order_items soi ON soi.order_id = so.id
        JOIN products p ON p.id = soi.product_id
        WHERE tc.target_id = p_target_id
        GROUP BY tc.customer_id
      ) sub
      WHERE sub.cat_count >= v_target.target_value;
      -- target_value = عدد التصنيفات المستهدف لكل عميل

    ELSE
      v_achieved := 0;
  END CASE;

  -- ══════════════════════════════════════════════════════════
  -- حساب النسبة والاتجاه
  -- ══════════════════════════════════════════════════════════
  v_pct := CASE WHEN v_target.target_value = 0 THEN 0
                ELSE ROUND((v_achieved / v_target.target_value * 100), 2) END;

  v_days_elapsed := p_snapshot_date - v_target.period_start + 1;
  v_total_days   := v_target.period_end - v_target.period_start + 1;
  v_expected_pct := ROUND((v_days_elapsed / GREATEST(v_total_days, 1)) * 100, 2);

  v_trend := CASE
    WHEN v_achieved >= COALESCE(v_target.stretch_value, v_target.target_value * 1.2) THEN 'exceeded'
    WHEN v_achieved >= v_target.target_value        THEN 'achieved'
    WHEN v_pct < (v_expected_pct - 20)              THEN 'behind'
    WHEN v_pct < (v_expected_pct - 10)              THEN 'at_risk'
    ELSE 'on_track'
  END;

  -- ══════════════════════════════════════════════════════════
  -- ★ حساب expected_reward التقديرية (للعرض في الواجهة)
  -- ══════════════════════════════════════════════════════════
  IF v_target.reward_type IS NOT NULL AND v_target.auto_payout = true THEN
    SELECT * INTO v_best_tier
    FROM public.target_reward_tiers
    WHERE target_id = p_target_id AND threshold_pct <= v_pct
    ORDER BY threshold_pct DESC
    LIMIT 1;

    IF FOUND THEN
      IF v_target.reward_type = 'fixed' THEN
        v_expected_rwd := ROUND(
          COALESCE(v_target.reward_base_value, 0) * (v_best_tier.reward_pct / 100.0),
          2
        );
      END IF;
      -- للـ percentage: العرض التقديري يحتاج pool_value — يُحسب في الواجهة فقط
    END IF;
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- Idempotent upsert في target_progress
  -- ══════════════════════════════════════════════════════════
  INSERT INTO public.target_progress (
    target_id, snapshot_date, achieved_value, achievement_pct, trend, last_calc_at, calc_details
  ) VALUES (
    p_target_id, p_snapshot_date, v_achieved, v_pct, v_trend, now(),
    jsonb_build_object(
      'expected_reward',   v_expected_rwd,
      'tier_label',        v_best_tier.label,
      'days_elapsed',      v_days_elapsed,
      'total_days',        v_total_days,
      'expected_pct',      v_expected_pct
    )
  )
  ON CONFLICT (target_id, snapshot_date) DO UPDATE SET
    achieved_value  = EXCLUDED.achieved_value,
    achievement_pct = EXCLUDED.achievement_pct,
    trend           = EXCLUDED.trend,
    last_calc_at    = EXCLUDED.last_calc_at,
    calc_details    = EXCLUDED.calc_details;
END;
$$;

-- ════════════════════════════════════════════════════════════
-- SECTION 3: دالة calc_target_pool_value
-- تحسب الوعاء المالي للمكافأة النسبية بنفس فلاتر الهدف
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.calc_target_pool_value(
  p_target_id    UUID,
  p_employee_id  UUID,
  p_period_start DATE,
  p_period_end   DATE
) RETURNS NUMERIC
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_target  public.targets%ROWTYPE;
  v_pool    NUMERIC := 0;
BEGIN
  SELECT * INTO v_target FROM public.targets WHERE id = p_target_id;
  IF NOT FOUND OR v_target.reward_pool_basis IS NULL THEN RETURN 0; END IF;

  CASE v_target.reward_pool_basis

    WHEN 'sales_value' THEN
      -- هل هناك عملاء محددون (upgrade_value / category_spread)؟
      IF EXISTS (SELECT 1 FROM public.target_customers WHERE target_id = p_target_id) THEN
        -- ★ الوعاء من العملاء المستهدفين فقط
        IF v_target.product_id IS NOT NULL OR v_target.category_id IS NOT NULL THEN
          -- + فلتر منتج/تصنيف → line_total
          SELECT COALESCE(SUM(soi.line_total), 0) INTO v_pool
          FROM public.target_customers tc
          JOIN sales_orders so ON so.customer_id = tc.customer_id
          JOIN hr_employees he ON he.user_id = so.rep_id
          JOIN sales_order_items soi ON soi.order_id = so.id
          LEFT JOIN products p ON p.id = soi.product_id
          WHERE tc.target_id = p_target_id
            AND he.id = p_employee_id
            AND so.status IN ('delivered','completed')
            AND so.delivered_at::DATE BETWEEN p_period_start AND p_period_end
            AND (v_target.product_id  IS NULL OR soi.product_id = v_target.product_id)
            AND (v_target.category_id IS NULL OR p.category_id  = v_target.category_id);
        ELSE
          -- إجمالي الطلب من العملاء المحددين
          SELECT COALESCE(SUM(so.total_amount), 0) INTO v_pool
          FROM public.target_customers tc
          JOIN sales_orders so ON so.customer_id = tc.customer_id
          JOIN hr_employees he ON he.user_id = so.rep_id
          WHERE tc.target_id = p_target_id
            AND he.id = p_employee_id
            AND so.status IN ('delivered','completed')
            AND so.delivered_at::DATE BETWEEN p_period_start AND p_period_end;
        END IF;

      ELSE
        -- بدون عملاء محددين: مبيعات الموظف مع فلاتر الهدف
        IF v_target.product_id IS NOT NULL OR v_target.category_id IS NOT NULL THEN
          -- ★ فلتر منتج/تصنيف → line_total لا total_amount
          SELECT COALESCE(SUM(soi.line_total), 0) INTO v_pool
          FROM sales_orders so
          JOIN hr_employees he ON he.user_id = so.rep_id
          JOIN sales_order_items soi ON soi.order_id = so.id
          JOIN customers c ON c.id = so.customer_id
          LEFT JOIN products p ON p.id = soi.product_id
          WHERE he.id = p_employee_id
            AND so.status IN ('delivered','completed')
            AND so.delivered_at::DATE BETWEEN p_period_start AND p_period_end
            AND (v_target.product_id  IS NULL OR soi.product_id = v_target.product_id)
            AND (v_target.category_id IS NULL OR p.category_id  = v_target.category_id)
            AND (v_target.governorate_id IS NULL OR c.governorate_id = v_target.governorate_id)
            AND (v_target.city_id        IS NULL OR c.city_id        = v_target.city_id)
            AND (v_target.area_id        IS NULL OR c.area_id        = v_target.area_id);
        ELSE
          -- بدون فلاتر: إجمالي الطلب (صحيح)
          SELECT COALESCE(SUM(so.total_amount), 0) INTO v_pool
          FROM sales_orders so
          JOIN hr_employees he ON he.user_id = so.rep_id
          JOIN customers c ON c.id = so.customer_id
          WHERE he.id = p_employee_id
            AND so.status IN ('delivered','completed')
            AND so.delivered_at::DATE BETWEEN p_period_start AND p_period_end
            AND (v_target.governorate_id IS NULL OR c.governorate_id = v_target.governorate_id)
            AND (v_target.city_id        IS NULL OR c.city_id        = v_target.city_id)
            AND (v_target.area_id        IS NULL OR c.area_id        = v_target.area_id);
        END IF;
      END IF;

    WHEN 'collection_value' THEN
      -- وعاء التحصيل مع الفلاتر الجغرافية
      SELECT COALESCE(SUM(pr.amount), 0) INTO v_pool
      FROM payment_receipts pr
      JOIN hr_employees he ON he.user_id = pr.collected_by
      LEFT JOIN customers c ON c.id = pr.customer_id
      WHERE he.id = p_employee_id
        AND pr.status = 'confirmed'
        AND pr.created_at::DATE BETWEEN p_period_start AND p_period_end
        AND (v_target.governorate_id IS NULL OR c.governorate_id = v_target.governorate_id)
        AND (v_target.city_id        IS NULL OR c.city_id        = v_target.city_id)
        AND (v_target.area_id        IS NULL OR c.area_id        = v_target.area_id);

    ELSE
      v_pool := 0;
  END CASE;

  RETURN GREATEST(v_pool, 0);
END; $$;

-- ════════════════════════════════════════════════════════════
-- نهاية 22b_target_calc.sql
-- الخطوة التالية: 22c_target_payouts.sql
-- ════════════════════════════════════════════════════════════
