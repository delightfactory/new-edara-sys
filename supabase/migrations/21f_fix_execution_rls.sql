-- ============================================================================
-- 21f: إصلاح سياسة RLS لتنفيذ الزيارات والمكالمات
-- 
-- المشكلة: المندوب لا يستطيع تحديث بنود خطته أثناء التنفيذ
-- السبب: سياسة vpi_write/vpi_update تتطلب visit_plans.create لكن المندوب
--         يملك activities.create فقط
-- الحل: فصل السياسات (INSERT/UPDATE/DELETE) مع شرط خاص للتنفيذ الميداني
--
-- ═══ خريطة السياسات بعد التنفيذ ═══
-- visit_plan_items:
--   vpi_read   (SELECT) → من 21b — لم يُمس
--   vpi_insert (INSERT) → جديد — يستبدل القديم من 21_mvp + vpi_write من 21b
--   vpi_update (UPDATE) → جديد — يستبدل القديم من 21_mvp + vpi_write من 21b
--   vpi_delete (DELETE) → جديد
-- call_plan_items:
--   cpi_read   (SELECT) → من 21b — لم يُمس
--   cpi_insert (INSERT) → جديد
--   cpi_update (UPDATE) → جديد
--   cpi_delete (DELETE) → جديد
-- ============================================================================

BEGIN;

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  visit_plan_items — إزالة السياسات القديمة المتعارضة              ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- سياسة vpi_update القديمة (من 21_mvp) — تتطلب visit_plans.create + branch check
DROP POLICY IF EXISTS vpi_update ON public.visit_plan_items;
-- سياسة vpi_write (من 21b) — FOR ALL تتطلب visit_plans.create فقط
DROP POLICY IF EXISTS vpi_write  ON public.visit_plan_items;
-- سياسة vpi_insert القديمة (من 21_mvp) — ستُستبدل بنسخة أبسط
DROP POLICY IF EXISTS vpi_insert ON public.visit_plan_items;
-- سياسة vpi_delete (قد لا تكون موجودة — safety)
DROP POLICY IF EXISTS vpi_delete ON public.visit_plan_items;

-- ─────────────────────────────────────────────────────────────────────
-- 1) INSERT — إنشاء بنود خطة زيارات
-- ─────────────────────────────────────────────────────────────────────
-- من يستطيع إضافة بنود: من لديه صلاحية إنشاء/تعديل الخطة
-- + يشترط أن تكون الخطة ضمن نطاقه (خطته أو فريقه أو إدارة عليا)
CREATE POLICY vpi_insert ON public.visit_plan_items
  FOR INSERT
  WITH CHECK (
    -- صاحب الخطة (المندوب) مع صلاحية إنشاء خطة
    (
      check_permission(auth.uid(), 'visit_plans.create')
      AND EXISTS (
        SELECT 1 FROM public.visit_plans vp
        WHERE vp.id = plan_id
          AND (
            vp.employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
            OR check_permission(auth.uid(), 'visit_plans.read_team')
          )
      )
    )
    -- المشرف مع صلاحية تعديل
    OR (
      check_permission(auth.uid(), 'visit_plans.update')
      AND EXISTS (
        SELECT 1 FROM public.visit_plans vp
        WHERE vp.id = plan_id
          AND vp.employee_id IN (
            SELECT id FROM hr_employees
            WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid() LIMIT 1)
          )
      )
    )
    -- الإدارة العليا
    OR check_permission(auth.uid(), 'visit_plans.read_all')
  );

-- ─────────────────────────────────────────────────────────────────────
-- 2) UPDATE — الأهم: تحديث حالة البنود أثناء التنفيذ الميداني
-- ─────────────────────────────────────────────────────────────────────
-- كل العمليات التالية تحتاج UPDATE:
--   • بدء الزيارة (status → in_progress, gps_lat/lng, actual_start_time)
--   • إنهاء الزيارة (status → completed, actual_end_time, end_gps)
--   • تخطي (status → skipped, skip_reason)
--   • إعادة ترتيب البنود (sequence)
--   • تعديل الأولوية / الغرض

CREATE POLICY vpi_update ON public.visit_plan_items
  FOR UPDATE
  USING (
    -- ✅ الحالة 1: المندوب (صاحب الخطة) — ينفذ زياراته ميدانياً
    -- الشرط: activities.create + الخطة مُسندة إليه
    (
      check_permission(auth.uid(), 'activities.create')
      AND EXISTS (
        SELECT 1 FROM public.visit_plans vp
        WHERE vp.id = plan_id
          AND vp.employee_id IN (
            SELECT id FROM hr_employees WHERE user_id = auth.uid()
          )
      )
    )
    -- ✅ الحالة 2: المندوب/المنشئ مع صلاحية visit_plans.create
    OR (
      check_permission(auth.uid(), 'visit_plans.create')
      AND EXISTS (
        SELECT 1 FROM public.visit_plans vp
        WHERE vp.id = plan_id
          AND vp.employee_id IN (
            SELECT id FROM hr_employees WHERE user_id = auth.uid()
          )
      )
    )
    -- ✅ الحالة 3: المشرف — يعدل بنود خطط فريقه (إعادة ترتيب، تغيير أولوية)
    OR (
      check_permission(auth.uid(), 'visit_plans.update')
      AND EXISTS (
        SELECT 1 FROM public.visit_plans vp
        WHERE vp.id = plan_id
          AND vp.employee_id IN (
            SELECT id FROM hr_employees
            WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid() LIMIT 1)
          )
      )
    )
    -- ✅ الحالة 4: من يملك تأكيد الخطط (عادةً المشرف/المدير)
    OR (
      check_permission(auth.uid(), 'visit_plans.confirm')
      AND EXISTS (
        SELECT 1 FROM public.visit_plans vp
        WHERE vp.id = plan_id
          AND vp.employee_id IN (
            SELECT id FROM hr_employees
            WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid() LIMIT 1)
          )
      )
    )
    -- ✅ الحالة 5: الإدارة العليا — بدون قيود
    OR check_permission(auth.uid(), 'visit_plans.read_all')
  );

-- ─────────────────────────────────────────────────────────────────────
-- 3) DELETE — حذف بنود من الخطة
-- ─────────────────────────────────────────────────────────────────────
-- يحذف فقط من يملك صلاحية تعديل الخطة + ضمن نطاقه
CREATE POLICY vpi_delete ON public.visit_plan_items
  FOR DELETE
  USING (
    -- صاحب الخطة مع صلاحية إنشاء خطة
    (
      check_permission(auth.uid(), 'visit_plans.create')
      AND EXISTS (
        SELECT 1 FROM public.visit_plans vp
        WHERE vp.id = plan_id
          AND vp.employee_id IN (
            SELECT id FROM hr_employees WHERE user_id = auth.uid()
          )
      )
    )
    -- المشرف مع صلاحية تعديل
    OR (
      check_permission(auth.uid(), 'visit_plans.update')
      AND EXISTS (
        SELECT 1 FROM public.visit_plans vp
        WHERE vp.id = plan_id
          AND vp.employee_id IN (
            SELECT id FROM hr_employees
            WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid() LIMIT 1)
          )
      )
    )
    -- إدارة عليا
    OR check_permission(auth.uid(), 'visit_plans.read_all')
  );


-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  call_plan_items — نفس الإصلاح                                    ║
-- ╚══════════════════════════════════════════════════════════════════════╝

DROP POLICY IF EXISTS cpi_update ON public.call_plan_items;
DROP POLICY IF EXISTS cpi_write  ON public.call_plan_items;
DROP POLICY IF EXISTS cpi_insert ON public.call_plan_items;
DROP POLICY IF EXISTS cpi_delete ON public.call_plan_items;

-- INSERT
CREATE POLICY cpi_insert ON public.call_plan_items
  FOR INSERT
  WITH CHECK (
    (
      check_permission(auth.uid(), 'call_plans.create')
      AND EXISTS (
        SELECT 1 FROM public.call_plans cp
        WHERE cp.id = plan_id
          AND (
            cp.employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
            OR check_permission(auth.uid(), 'call_plans.read_team')
          )
      )
    )
    OR check_permission(auth.uid(), 'call_plans.read_all')
  );

-- UPDATE
CREATE POLICY cpi_update ON public.call_plan_items
  FOR UPDATE
  USING (
    -- المندوب ينفذ مكالماته
    (
      check_permission(auth.uid(), 'activities.create')
      AND EXISTS (
        SELECT 1 FROM public.call_plans cp
        WHERE cp.id = plan_id
          AND cp.employee_id IN (
            SELECT id FROM hr_employees WHERE user_id = auth.uid()
          )
      )
    )
    -- منشئ الخطة
    OR (
      check_permission(auth.uid(), 'call_plans.create')
      AND EXISTS (
        SELECT 1 FROM public.call_plans cp
        WHERE cp.id = plan_id
          AND cp.employee_id IN (
            SELECT id FROM hr_employees WHERE user_id = auth.uid()
          )
      )
    )
    -- المشرف (فريقه)
    OR (
      check_permission(auth.uid(), 'call_plans.confirm')
      AND EXISTS (
        SELECT 1 FROM public.call_plans cp
        WHERE cp.id = plan_id
          AND cp.employee_id IN (
            SELECT id FROM hr_employees
            WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid() LIMIT 1)
          )
      )
    )
    -- إدارة عليا
    OR check_permission(auth.uid(), 'call_plans.read_all')
  );

-- DELETE
CREATE POLICY cpi_delete ON public.call_plan_items
  FOR DELETE
  USING (
    (
      check_permission(auth.uid(), 'call_plans.create')
      AND EXISTS (
        SELECT 1 FROM public.call_plans cp
        WHERE cp.id = plan_id
          AND cp.employee_id IN (
            SELECT id FROM hr_employees WHERE user_id = auth.uid()
          )
      )
    )
    OR check_permission(auth.uid(), 'call_plans.read_all')
  );

COMMIT;
