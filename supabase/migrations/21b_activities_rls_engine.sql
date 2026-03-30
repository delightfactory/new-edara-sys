-- =============================================================================
-- 21b_activities_rls_engine.sql
-- إكمال موديول الأنشطة — يعتمد على 21_activities_module_mvp.sql
--
-- ما يُعالَج هنا:
--   [P0] إصلاح v_rep_performance (Cartesian product → subqueries منفصلة)
--   [P0] قفل target_progress و target_adjustments: DENY ALL + كتابة عبر RPC فقط
--   [P1] دعم company/branch/department في دالة الحساب
--   [P1] scope validation موجود في 21a عبر validate_target_scope Trigger ✅
-- =============================================================================

BEGIN;

-- =============================================================================
-- 7) RLS — تأمين كل الجداول
-- =============================================================================

ALTER TABLE public.activity_types        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.target_types          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visit_plan_templates  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visit_plans           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visit_plan_items      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_plan_templates   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_plans            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_plan_items       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activities            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_details          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.targets               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.target_progress       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.target_adjustments    ENABLE ROW LEVEL SECURITY;

-- ── activity_types / target_types: جميع المستخدمين يقرؤون، الإدارة فقط تكتب ──
DROP POLICY IF EXISTS "act_types_read"  ON public.activity_types;
CREATE POLICY "act_types_read"  ON public.activity_types FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "act_types_write" ON public.activity_types;
CREATE POLICY "act_types_write" ON public.activity_types FOR ALL
  USING (check_permission(auth.uid(), 'settings.update'));

DROP POLICY IF EXISTS "tgt_types_read"  ON public.target_types;
CREATE POLICY "tgt_types_read"  ON public.target_types  FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "tgt_types_write" ON public.target_types;
CREATE POLICY "tgt_types_write" ON public.target_types  FOR ALL
  USING (check_permission(auth.uid(), 'settings.update'));

-- ── activities ──
DROP POLICY IF EXISTS "acts_read"   ON public.activities;
CREATE POLICY "acts_read" ON public.activities FOR SELECT USING (
  -- المندوب: نشاطاته فقط
  employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
  -- المشرف: فريقه في نفس الفرع
  OR (check_permission(auth.uid(), 'activities.read_team') AND employee_id IN (
    SELECT id FROM hr_employees WHERE branch_id = (
      SELECT branch_id FROM hr_employees WHERE user_id = auth.uid() LIMIT 1
    )
  ))
  -- الإدارة: الكل
  OR check_permission(auth.uid(), 'activities.read_all')
);

DROP POLICY IF EXISTS "acts_insert" ON public.activities;
CREATE POLICY "acts_insert" ON public.activities FOR INSERT WITH CHECK (
  -- ✅ المندوب يُنشئ لنفسه فقط (employee_id + created_by = uidه هو)
  employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
  AND created_by = auth.uid()
  AND check_permission(auth.uid(), 'activities.create')
);

DROP POLICY IF EXISTS "acts_update" ON public.activities;
CREATE POLICY "acts_update" ON public.activities FOR UPDATE USING (
  (
    employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    AND check_permission(auth.uid(), 'activities.update_own')
    AND created_at > now() - INTERVAL '24 hours'
  )
  OR check_permission(auth.uid(), 'activities.read_all')
);

-- ✅ [FINAL FIX] سياسة الحذف الناعم — RPC بدلاً من FOR UPDATE Policy
-- السبب: WITH CHECK في PostgreSQL تتحقق من قيمة عمود بعد التعديل وليس من الأعمدة المعدّلة
-- أي: FOR UPDATE + WITH CHECK(deleted_at IS NOT NULL) لا تمنع تعديل outcome_notes في نفس الاستدعاء
-- الحل الصحيح: RPC مع SECURITY DEFINER تفرض deleted_at فقط ولا شيء غيره
DROP POLICY IF EXISTS "acts_delete" ON public.activities;
-- لا نُنشئ policy — الحذف يتم حصراً عبر soft_delete_activity() الموجودة تحت

-- RPC الحذف الناعم — المسار الوحيد المضمون لتعيين deleted_at
CREATE OR REPLACE FUNCTION public.soft_delete_activity(
  p_activity_id UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_act    public.activities%ROWTYPE;
  v_caller UUID := auth.uid();
BEGIN
  SELECT * INTO v_act FROM public.activities WHERE id = p_activity_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'النشاط غير موجود';
  END IF;
  IF v_act.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'النشاط محذوف مسبقاً';
  END IF;

  -- تحقق الصلاحية حسب الدور
  IF v_act.employee_id IN (SELECT id FROM hr_employees WHERE user_id = v_caller)
     AND check_permission(v_caller, 'activities.update_own')
     AND v_act.created_at > now() - INTERVAL '24 hours'
  THEN
    NULL; -- المندوب: يحذف نشاطاته خلال 24ساعة
  ELSIF check_permission(v_caller, 'activities.read_team')
    AND v_act.employee_id IN (
      SELECT id FROM hr_employees WHERE branch_id = (
        SELECT branch_id FROM hr_employees WHERE user_id = v_caller LIMIT 1
      )
    )
    AND v_act.created_at > now() - INTERVAL '48 hours'
  THEN
    NULL; -- المشرف: يحذف أنشطة فريقه خلال 48ساعة
  ELSIF check_permission(v_caller, 'activities.read_all') THEN
    NULL; -- الإدارة: تحذف أي نشاط بدون قيد
  ELSE
    RAISE EXCEPTION 'ليس لديك صلاحية حذف هذا النشاط أو انتهت المهلة المسموح بها';
  END IF;

  -- ✅ تعديل deleted_at فقط — لا شيء خلافه
  UPDATE public.activities
  SET deleted_at = now(),
      updated_at = now()
  WHERE id = p_activity_id;
END;
$$;

-- ── call_details: تتبع أمان النشاط الأصلي ──
DROP POLICY IF EXISTS "cd_rls" ON public.call_details;
CREATE POLICY "cd_rls" ON public.call_details FOR ALL USING (
  activity_id IN (
    SELECT id FROM public.activities WHERE
      employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
      OR check_permission(auth.uid(), 'activities.read_all')
  )
);

-- ── visit_plan_templates ──
DROP POLICY IF EXISTS "vpt_read"  ON public.visit_plan_templates;
CREATE POLICY "vpt_read" ON public.visit_plan_templates FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "vpt_write" ON public.visit_plan_templates;
CREATE POLICY "vpt_write" ON public.visit_plan_templates FOR ALL
  USING (check_permission(auth.uid(), 'visit_plans.create'));

-- ── visit_plans ──
DROP POLICY IF EXISTS "vp_read"  ON public.visit_plans;
CREATE POLICY "vp_read" ON public.visit_plans FOR SELECT USING (
  employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
  OR (check_permission(auth.uid(), 'visit_plans.read_team') AND employee_id IN (
    SELECT id FROM hr_employees WHERE branch_id = (
      SELECT branch_id FROM hr_employees WHERE user_id = auth.uid() LIMIT 1
    )
  ))
  OR check_permission(auth.uid(), 'visit_plans.read_all')
);
DROP POLICY IF EXISTS "vp_write" ON public.visit_plans;
CREATE POLICY "vp_write" ON public.visit_plans FOR ALL
  USING (check_permission(auth.uid(), 'visit_plans.create'));

-- ── visit_plan_items ──
DROP POLICY IF EXISTS "vpi_read"  ON public.visit_plan_items;
CREATE POLICY "vpi_read" ON public.visit_plan_items FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.visit_plans vp WHERE vp.id = plan_id AND (
    vp.employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR check_permission(auth.uid(), 'visit_plans.read_all')
  ))
);
DROP POLICY IF EXISTS "vpi_write" ON public.visit_plan_items;
CREATE POLICY "vpi_write" ON public.visit_plan_items FOR ALL
  USING (check_permission(auth.uid(), 'visit_plans.create'));

-- ── call_plan_templates ──
DROP POLICY IF EXISTS "cpt_read"  ON public.call_plan_templates;
CREATE POLICY "cpt_read" ON public.call_plan_templates FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "cpt_write" ON public.call_plan_templates;
CREATE POLICY "cpt_write" ON public.call_plan_templates FOR ALL
  USING (check_permission(auth.uid(), 'call_plans.create'));

-- ── call_plans ──
DROP POLICY IF EXISTS "cp_read"  ON public.call_plans;
CREATE POLICY "cp_read" ON public.call_plans FOR SELECT USING (
  employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
  OR (check_permission(auth.uid(), 'call_plans.read_team') AND employee_id IN (
    SELECT id FROM hr_employees WHERE branch_id = (
      SELECT branch_id FROM hr_employees WHERE user_id = auth.uid() LIMIT 1
    )
  ))
  OR check_permission(auth.uid(), 'call_plans.read_all')
);
DROP POLICY IF EXISTS "cp_write" ON public.call_plans;
CREATE POLICY "cp_write" ON public.call_plans FOR ALL
  USING (check_permission(auth.uid(), 'call_plans.create'));

-- ── call_plan_items ──
DROP POLICY IF EXISTS "cpi_read"  ON public.call_plan_items;
CREATE POLICY "cpi_read" ON public.call_plan_items FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.call_plans cp WHERE cp.id = plan_id AND (
    cp.employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR check_permission(auth.uid(), 'call_plans.read_all')
  ))
);
DROP POLICY IF EXISTS "cpi_write" ON public.call_plan_items;
CREATE POLICY "cpi_write" ON public.call_plan_items FOR ALL
  USING (check_permission(auth.uid(), 'call_plans.create'));

-- ── targets ──
DROP POLICY IF EXISTS "tgt_read"  ON public.targets;
CREATE POLICY "tgt_read" ON public.targets FOR SELECT USING (
  -- المندوب: أهدافه الفردية فقط
  (scope = 'individual' AND scope_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid()))
  -- المشرف: أهداف فريقه (individual + branch)
  OR (check_permission(auth.uid(), 'targets.read_team') AND (
    (scope = 'branch' AND scope_id = (
      SELECT branch_id FROM hr_employees WHERE user_id = auth.uid() LIMIT 1
    ))
    OR (scope = 'individual' AND scope_id IN (
      SELECT id FROM hr_employees WHERE branch_id = (
        SELECT branch_id FROM hr_employees WHERE user_id = auth.uid() LIMIT 1
      )
    ))
  ))
  -- الإدارة: الكل
  OR check_permission(auth.uid(), 'targets.read_all')
);
-- ✅ [P1 FIX] tgt_insert مع قيد النطاق (مطابق لنسخة MVP سطر 2083-2103)
-- branch_manager ينشئ أهدافاً في فرعه فقط — CEO ينشئ لأي scope
DROP POLICY IF EXISTS "tgt_insert" ON public.targets;
CREATE POLICY "tgt_insert" ON public.targets FOR INSERT WITH CHECK (
  -- CEO وأصحاب targets.read_all: بدون قيد
  check_permission(auth.uid(), 'targets.read_all')
  OR (
    -- branch_manager / supervisor: مقيد بفرعه فقط
    (check_permission(auth.uid(), 'targets.create') OR check_permission(auth.uid(), 'targets.assign'))
    AND (
      (scope = 'individual' AND scope_id IN (
        SELECT id FROM hr_employees
        WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid() LIMIT 1)
      ))
      OR (scope = 'branch' AND scope_id = (
        SELECT branch_id FROM hr_employees WHERE user_id = auth.uid() LIMIT 1
      ))
      OR (scope = 'department' AND scope_id IN (
        SELECT id FROM hr_departments
        WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid() LIMIT 1)
      ))
    )
  )
);
-- لا UPDATE policy → UPDATE محجوب من العميل — يجب المرور عبر adjust_target() RPC
-- لا DELETE policy → DELETE محجوب (يُستخدم is_active=false بدلاً عنه)

-- ══════════════════════════════════════════════════════════════════════════════
-- [P0 FIX] target_progress و target_adjustments:
-- DENY ALL للعميل — الكتابة عبر RPC فقط (SECURITY DEFINER)
-- هذا يتوافق مع نمط EDARA الحالي (مثل customer_ledger, stock_movements)
-- ══════════════════════════════════════════════════════════════════════════════

-- ✅ target_progress: قراءة مربوطة بالهدف عبر RLS الأهداف
-- المستخدم يرى target_progress للأهداف التي يملك تصفحها فقط (inheritance من tgt_read)
DROP POLICY IF EXISTS "tp_read"  ON public.target_progress;
CREATE POLICY "tp_read" ON public.target_progress FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.targets t WHERE t.id = target_id
    AND (
      (t.scope = 'individual' AND t.scope_id IN (
        SELECT id FROM hr_employees WHERE user_id = auth.uid()
      ))
      OR (check_permission(auth.uid(), 'targets.read_team') AND (
        (t.scope = 'branch' AND t.scope_id = (
          SELECT branch_id FROM hr_employees WHERE user_id = auth.uid() LIMIT 1
        ))
        OR (t.scope = 'individual' AND t.scope_id IN (
          SELECT id FROM hr_employees WHERE branch_id = (
            SELECT branch_id FROM hr_employees WHERE user_id = auth.uid() LIMIT 1
          )
        ))
      ))
      OR check_permission(auth.uid(), 'targets.read_all')
    )
  )
);
-- لا INSERT/UPDATE/DELETE policy → الكتابة عبر recalculate_target_progress() SECURITY DEFINER فقط

-- ✅ target_adjustments: CEO أيضاً يرى سجل التعديلات
DROP POLICY IF EXISTS "ta_read"  ON public.target_adjustments;
CREATE POLICY "ta_read" ON public.target_adjustments FOR SELECT USING (
  check_permission(auth.uid(), 'targets.read_team')
  OR check_permission(auth.uid(), 'targets.read_all')
);
-- لا INSERT/UPDATE policy → الكتابة عبر adjust_target() RPC فقط

-- =============================================================================
-- 8) دالة الحساب المركزية — مع دعم جميع الـ scopes [P1 FIX]
-- =============================================================================

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
  -- [P1] قائمة hr_employees.id ضمن النطاق
  v_employee_ids UUID[];
BEGIN
  SELECT * INTO v_target FROM public.targets
  WHERE id = p_target_id AND is_active = true AND is_paused = false;
  IF NOT FOUND THEN RETURN; END IF;

  -- ════════════════════════════════════════════════════════
  -- [P1 FIX] تجميع الموظفين المستهدفين حسب النطاق
  -- ════════════════════════════════════════════════════════
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

  -- ════════════════════════════════════════════════════════
  -- حساب القيمة المحققة
  -- ════════════════════════════════════════════════════════
  CASE v_target.type_code

    WHEN 'sales_value' THEN
      -- ✅ [P1 FIX] إضافة city_id و area_id من جدول Codex (21a: targets سطر 498-499)
      SELECT COALESCE(SUM(so.total_amount), 0) INTO v_achieved
      FROM sales_orders so
      JOIN hr_employees he ON he.user_id = so.rep_id
      JOIN customers c ON c.id = so.customer_id
      WHERE he.id = ANY(v_employee_ids)
        AND so.status IN ('delivered','completed')
        AND so.delivered_at::DATE BETWEEN v_target.period_start AND p_snapshot_date
        AND (v_target.product_id IS NULL OR EXISTS (
          SELECT 1 FROM sales_order_items soi
          WHERE soi.order_id = so.id AND soi.product_id = v_target.product_id
        ))
        AND (v_target.category_id IS NULL OR EXISTS (
          SELECT 1 FROM sales_order_items soi
          JOIN products p ON p.id = soi.product_id
          WHERE soi.order_id = so.id AND p.category_id = v_target.category_id
        ))
        AND (v_target.governorate_id IS NULL OR c.governorate_id = v_target.governorate_id)
        AND (v_target.city_id       IS NULL OR c.city_id       = v_target.city_id)
        AND (v_target.area_id       IS NULL OR c.area_id       = v_target.area_id);

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
      -- ✅ [P2 FIX] إضافة agreed_order كمعادل order_placed (مطابق MVP سطر 1221)
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
        AND (v_target.product_id IS NULL OR soi.product_id = v_target.product_id)
        AND (v_target.category_id IS NULL OR soi.product_id IN (
          SELECT id FROM products WHERE category_id = v_target.category_id
        ));

    ELSE
      v_achieved := 0;
  END CASE;

  -- حساب النسبة والاتجاه
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

  -- Idempotent upsert
  INSERT INTO public.target_progress (
    target_id, snapshot_date, achieved_value, achievement_pct, trend, last_calc_at
  ) VALUES (
    p_target_id, p_snapshot_date, v_achieved, v_pct, v_trend, now()
  )
  ON CONFLICT (target_id, snapshot_date) DO UPDATE SET
    achieved_value  = EXCLUDED.achieved_value,
    achievement_pct = EXCLUDED.achievement_pct,
    trend           = EXCLUDED.trend,
    last_calc_at    = EXCLUDED.last_calc_at;
END;
$$;

-- Cron entry point
CREATE OR REPLACE FUNCTION public.recalculate_all_active_targets()
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID;
BEGIN
  FOR v_id IN
    SELECT id FROM public.targets
    WHERE is_active = true AND is_paused = false
      AND period_start <= CURRENT_DATE AND period_end >= CURRENT_DATE
  LOOP
    PERFORM public.recalculate_target_progress(v_id, CURRENT_DATE);
  END LOOP;
END;
$$;
-- تفعيل في Supabase Dashboard:
-- SELECT cron.schedule('recalc-targets', '*/5 * * * *', 'SELECT public.recalculate_all_active_targets();');

-- ✅ [GAP FIX] تحقق GPS: إشباع validate_activity_payload بفحص gps_lat/gps_lng
-- المشكلة: الدالة الأصلية تتحقق من requires_customer لكنها لا تتحقق من requires_gps → gps_lat/gps_lng
-- الحل: نُضيف التحقق هنا عبر CREATE OR REPLACE لنفس الدالة (idempotent override)
CREATE OR REPLACE FUNCTION public.validate_activity_payload()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type       public.activity_types%ROWTYPE;
  v_visit_item public.visit_plan_items%ROWTYPE;
  v_visit_plan public.visit_plans%ROWTYPE;
  v_call_item  public.call_plan_items%ROWTYPE;
  v_call_plan  public.call_plans%ROWTYPE;
BEGIN
  -- تحقق من نوع النشاط
  SELECT * INTO v_type
  FROM public.activity_types
  WHERE id = NEW.type_id AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'نوع النشاط غير موجود أو غير نشط';
  END IF;

  -- ✅ [GAP FIX] تحقق GPS إلزامي: إذا كان requires_gps = true يجب وجود إحداثيات
  IF v_type.requires_gps AND (NEW.gps_lat IS NULL OR NEW.gps_lng IS NULL) THEN
    RAISE EXCEPTION 'هذا النوع من الأنشطة يتطلب إحداثيات GPS (gps_lat و gps_lng)';
  END IF;

  -- تحقق وجود عميل
  IF v_type.requires_customer AND NEW.customer_id IS NULL THEN
    RAISE EXCEPTION 'هذا النوع من الأنشطة يتطلب عميلاً';
  END IF;

  -- منع الربط ببندين في آن واحد
  IF NEW.visit_plan_item_id IS NOT NULL AND NEW.call_plan_item_id IS NOT NULL THEN
    RAISE EXCEPTION 'لا يمكن ربط النشاط ببند زيارة وبند مكالمة معاً';
  END IF;

  -- تحقق تطابق بند الزيارة
  IF NEW.visit_plan_item_id IS NOT NULL THEN
    IF v_type.category <> 'visit' THEN
      RAISE EXCEPTION 'ربط بند زيارة يتطلب activity_type من فئة visit';
    END IF;
    SELECT * INTO v_visit_item FROM public.visit_plan_items WHERE id = NEW.visit_plan_item_id;
    SELECT * INTO v_visit_plan FROM public.visit_plans   WHERE id = v_visit_item.plan_id;
    IF v_visit_plan.employee_id <> NEW.employee_id THEN
      RAISE EXCEPTION 'employee_id لا يطابق صاحب خطة الزيارة';
    END IF;
    IF NEW.customer_id IS NULL OR NEW.customer_id <> v_visit_item.customer_id THEN
      RAISE EXCEPTION 'customer_id لا يطابق عميل بند الزيارة';
    END IF;
  END IF;

  -- تحقق تطابق بند المكالمة
  IF NEW.call_plan_item_id IS NOT NULL THEN
    IF v_type.category <> 'call' THEN
      RAISE EXCEPTION 'ربط بند مكالمة يتطلب activity_type من فئة call';
    END IF;
    SELECT * INTO v_call_item FROM public.call_plan_items WHERE id = NEW.call_plan_item_id;
    SELECT * INTO v_call_plan FROM public.call_plans     WHERE id = v_call_item.plan_id;
    IF v_call_plan.employee_id <> NEW.employee_id THEN
      RAISE EXCEPTION 'employee_id لا يطابق صاحب خطة المكالمات';
    END IF;
    IF v_call_item.customer_id IS NOT NULL AND NEW.customer_id IS DISTINCT FROM v_call_item.customer_id THEN
      RAISE EXCEPTION 'customer_id لا يطابق عميل بند المكالمة';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ✅ [P2 FIX] حذف Trigger log_target_adjustments من 21_activities_module_mvp.sql (سطر 1073)
-- السبب: يولد ازدواجية — يكتب سجلاً بدون reason من Trigger وسجلاً مع reason من adjust_target()
-- الحل الوحيد: adjust_target() RPC هو المسار الوحيد للتسجيل
DROP TRIGGER IF EXISTS trg_targets_log_adjustments ON public.targets;
-- ملاحظة: لا نحذف الدالة log_target_adjustments() لأنها SECURITY DEFINER وقد تُرجع في مرحلة لاحقة

-- =============================================================================
-- 9) RPC: adjust_target — الكتابة الوحيدة المسموحة على target_adjustments
-- =============================================================================

CREATE OR REPLACE FUNCTION public.adjust_target(
  p_target_id   UUID,
  p_field       TEXT,
  p_new_value   TEXT,
  p_reason      TEXT,
  p_user_id     UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_old TEXT;
BEGIN
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;
  IF NOT check_permission(p_user_id, 'targets.update') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية تعديل الأهداف';
  END IF;
  IF p_field NOT IN ('target_value','min_value','stretch_value','period_end','is_paused','is_active','filter_criteria') THEN
    RAISE EXCEPTION 'الحقل غير مسموح بتعديله: %', p_field;
  END IF;
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'يجب إدخال سبب التعديل';
  END IF;

  -- قراءة القيمة الحالية
  EXECUTE format('SELECT (%I)::TEXT FROM public.targets WHERE id = $1', p_field)
  INTO v_old USING p_target_id;

  -- تطبيق التعديل
  EXECUTE format('UPDATE public.targets SET %I = $1::' ||
    CASE p_field
      WHEN 'target_value' THEN 'NUMERIC'
      WHEN 'min_value'    THEN 'NUMERIC'
      WHEN 'stretch_value' THEN 'NUMERIC'
      WHEN 'period_end'   THEN 'DATE'
      WHEN 'is_paused'    THEN 'BOOLEAN'
      WHEN 'is_active'    THEN 'BOOLEAN'
      WHEN 'filter_criteria' THEN 'JSONB'
    END || ', paused_at = CASE WHEN $2 = ''is_paused'' AND $1::BOOLEAN THEN now() ELSE paused_at END, updated_at = now() WHERE id = $3',
    p_field)
  USING p_new_value, p_field, p_target_id;

  -- تسجيل في target_adjustments (SECURITY DEFINER — يتجاوز RLS)
  INSERT INTO public.target_adjustments (target_id, field_changed, old_value, new_value, reason, adjusted_by)
  VALUES (p_target_id, p_field, v_old, p_new_value, p_reason, p_user_id);

  -- إعادة حساب فورية بعد التعديل
  PERFORM public.recalculate_target_progress(p_target_id, CURRENT_DATE);
END;
$$;

-- =============================================================================
-- 10) Views — [P0 FIX] v_rep_performance بدون Cartesian product
-- =============================================================================

-- ✅ v_rep_performance — security_invoker + all_periods UNION (لا Cartesian product)
DROP VIEW IF EXISTS public.v_rep_performance;
CREATE VIEW public.v_rep_performance
WITH (security_invoker = true)
AS
WITH
  act_agg AS (
    SELECT
      a.employee_id,
      DATE_TRUNC('month', a.activity_date) AS month,
      COUNT(*) FILTER (WHERE at_.category = 'visit')                                     AS visits_count,
      COUNT(*) FILTER (WHERE at_.category = 'call')                                      AS calls_count,
      COUNT(*) FILTER (WHERE a.outcome_type IN ('order_placed','agreed_order'))           AS orders_from_activities,
      COUNT(DISTINCT a.customer_id) FILTER (WHERE a.outcome_type IN ('order_placed','agreed_order')) AS active_customers
    FROM public.activities a
    JOIN public.activity_types at_ ON at_.id = a.type_id
    WHERE a.deleted_at IS NULL
    GROUP BY a.employee_id, DATE_TRUNC('month', a.activity_date)
  ),
  sales_agg AS (
    SELECT
      he.id AS employee_id,
      DATE_TRUNC('month', so.delivered_at) AS month,
      COALESCE(SUM(so.total_amount), 0) AS sales_value
    FROM sales_orders so
    JOIN hr_employees he ON he.user_id = so.rep_id
    WHERE so.status IN ('delivered','completed') AND so.delivered_at IS NOT NULL
    GROUP BY he.id, DATE_TRUNC('month', so.delivered_at)
  ),
  coll_agg AS (
    SELECT
      he.id AS employee_id,
      DATE_TRUNC('month', pr.created_at) AS month,
      COALESCE(SUM(pr.amount), 0) AS collection_value
    FROM payment_receipts pr
    JOIN hr_employees he ON he.user_id = pr.collected_by
    WHERE pr.status = 'confirmed'
    GROUP BY he.id, DATE_TRUNC('month', pr.created_at)
  ),
  all_periods AS (
    SELECT employee_id, month FROM act_agg
    UNION
    SELECT employee_id, month FROM sales_agg
    UNION
    SELECT employee_id, month FROM coll_agg
  )
SELECT
  he.id           AS employee_id,
  he.full_name    AS employee_name,
  b.id            AS branch_id,
  b.name          AS branch_name,
  ap.month        AS period,
  COALESCE(aa.visits_count, 0)           AS visits_count,
  COALESCE(aa.calls_count, 0)            AS calls_count,
  COALESCE(aa.orders_from_activities, 0) AS orders_from_activities,
  COALESCE(sa.sales_value, 0)            AS sales_value,
  COALESCE(ca.collection_value, 0)       AS collection_value,
  COALESCE(aa.active_customers, 0)       AS active_customers
FROM all_periods ap
JOIN hr_employees he ON he.id = ap.employee_id AND he.status = 'active'
JOIN branches b     ON b.id = he.branch_id
LEFT JOIN act_agg   aa ON aa.employee_id = ap.employee_id AND aa.month = ap.month
LEFT JOIN sales_agg sa ON sa.employee_id = ap.employee_id AND sa.month = ap.month
LEFT JOIN coll_agg  ca ON ca.employee_id = ap.employee_id AND ca.month = ap.month;

-- ── v_plan_daily_summary ──
-- ✅ [P2 FIX] إضافة call_plans عبر UNION ALL (مطابق MVP سطر 2165-2205)
DROP VIEW IF EXISTS public.v_plan_daily_summary;
CREATE VIEW public.v_plan_daily_summary
WITH (security_invoker = true)
AS
SELECT
  'visit'::TEXT AS plan_module,
  vp.id, vp.employee_id, vp.plan_date, vp.plan_type,
  vp.status AS plan_status,
  vp.total_customers AS total_items,
  vp.completed_count, vp.skipped_count, vp.missed_count, vp.completion_pct,
  COUNT(vpi.id) FILTER (WHERE vpi.status = 'pending')                           AS pending_count,
  COUNT(vpi.id) FILTER (WHERE vpi.priority = 'high' AND vpi.status = 'pending') AS high_priority_pending
FROM public.visit_plans vp
LEFT JOIN public.visit_plan_items vpi ON vpi.plan_id = vp.id
GROUP BY vp.id
UNION ALL
SELECT
  'call'::TEXT AS plan_module,
  cp.id, cp.employee_id, cp.plan_date, cp.plan_type,
  cp.status AS plan_status,
  cp.total_calls AS total_items,
  cp.completed_count, cp.skipped_count, cp.missed_count, cp.completion_pct,
  COUNT(cpi.id) FILTER (WHERE cpi.status = 'pending')                           AS pending_count,
  COUNT(cpi.id) FILTER (WHERE cpi.priority = 'high' AND cpi.status = 'pending') AS high_priority_pending
FROM public.call_plans cp
LEFT JOIN public.call_plan_items cpi ON cpi.plan_id = cp.id
GROUP BY cp.id;

-- ── v_target_status ──
-- ✅ [P1 FIX] security_invoker = true لضمان RLS عبر API
-- ✅ [P2 FIX] آخر snapshot متاح عبر LATERAL
DROP VIEW IF EXISTS public.v_target_status;
CREATE VIEW public.v_target_status
WITH (security_invoker = true)
AS
SELECT
  t.id, t.name, t.type_code, t.scope, t.scope_id,
  t.period_start, t.period_end,
  t.target_value, t.min_value, t.stretch_value,
  t.is_active, t.is_paused,
  tp.achieved_value, tp.achievement_pct, tp.trend, tp.last_calc_at,
  tp.snapshot_date                                 AS data_as_of,
  t.target_value - COALESCE(tp.achieved_value, 0) AS remaining_value,
  t.period_end - CURRENT_DATE                      AS days_remaining,
  CASE
    WHEN (CURRENT_DATE - t.period_start) > 0
    THEN ROUND(
      COALESCE(tp.achieved_value, 0)
      / (CURRENT_DATE - t.period_start)
      * (t.period_end - t.period_start + 1), 2)
    ELSE 0
  END AS forecasted_value
FROM public.targets t
LEFT JOIN LATERAL (
  SELECT snapshot_date, achieved_value, achievement_pct, trend, last_calc_at
  FROM public.target_progress
  WHERE target_id = t.id
  ORDER BY snapshot_date DESC
  LIMIT 1
) tp ON true
WHERE t.is_active = true;


-- =============================================================================
-- 11) Seed Data
-- =============================================================================

INSERT INTO public.activity_types (name, code, category, requires_gps, requires_customer, default_duration_min, sort_order)
VALUES
  ('زيارة مخططة',          'visit_planned',       'visit', true,  true,  45, 1),
  ('زيارة مفاجئة',          'visit_unplanned',     'visit', true,  true,  30, 2),
  ('زيارة استكشافية',       'visit_exploratory',   'visit', true,  false, 60, 3),
  ('زيارة تحصيل',          'visit_collection',    'visit', true,  true,  20, 4),
  ('زيارة ترويج',           'visit_promo',         'visit', true,  true,  30, 5),
  ('مكالمة مبيعات صادرة',  'call_out_sales',      'call',  false, true,  10, 6),
  ('مكالمة تحصيل صادرة',   'call_out_collect',    'call',  false, true,  10, 7),
  ('مكالمة متابعة صادرة',  'call_out_followup',   'call',  false, true,   5, 8),
  ('مكالمة واردة',          'call_inbound',        'call',  false, true,  15, 9),
  ('مكالمة تنشيط صادرة',   'call_out_activation', 'call',  false, true,  10, 10)
ON CONFLICT (code) DO NOTHING;

INSERT INTO public.target_types (name, code, unit, category, auto_source, auto_calc_enabled)
VALUES
  ('مبيعات مالية',   'sales_value',    'currency', 'financial', 'sales_orders',     true),
  ('تحصيلات',       'collection',     'currency', 'financial', 'payment_receipts', true),
  ('كميات منتج',    'product_qty',    'quantity', 'product',   'sales_orders',     true),
  ('عدد زيارات',    'visits_count',   'count',    'activity',  'activities',       true),
  ('عدد مكالمات',   'calls_count',    'count',    'activity',  'activities',       true),
  ('عملاء جدد',     'new_customers',  'count',    'customer',  'customers',        true),
  ('تنشيط خاملين',  'reactivation',   'count',    'customer',  'activities',       true),
  ('رفع قيمة عميل', 'upgrade_value',  'currency', 'customer',  'sales_orders',     false),
  ('توسيع تصنيفات', 'category_spread','count',    'product',   'sales_orders',     false)
ON CONFLICT (code) DO NOTHING;

-- =============================================================================
-- 12) تفعيل Cron Job — [FINAL FIX] إضافة Idempotency كاملة
-- =============================================================================
-- ✅ تحقق من وجود المهمة قبل التسجيل — آمن لإعادة التشغيل على نفس البيئة
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- حذف أي job بنفس الاسم إن وُجد (idempotent)
    IF EXISTS (
      SELECT 1 FROM cron.job WHERE jobname = 'recalc-targets'
    ) THEN
      PERFORM cron.unschedule('recalc-targets');
    END IF;
    -- تسجيل Job جديد (أو إعادة تسجيله)
    PERFORM cron.schedule(
      'recalc-targets',
      '*/5 * * * *',
      'SELECT public.recalculate_all_active_targets();'
    );
    RAISE NOTICE '[EDARA] Cron job recalc-targets مفعّل — كل 5 دقائق';
  ELSE
    RAISE NOTICE '[EDARA] pg_cron غير مُفعَّل — يُرجى تفعيل Cron Job يدوياً من Supabase Dashboard:';
    RAISE NOTICE 'SELECT cron.schedule(''recalc-targets'', ''*/5 * * * *'', ''SELECT public.recalculate_all_active_targets();'');';
  END IF;
END;
$$;

COMMIT;
