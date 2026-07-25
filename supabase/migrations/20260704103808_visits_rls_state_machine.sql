-- =============================================================================
-- EDARA v2 — 20260704103808_visits_rls_state_machine.sql
-- Migration Phase C: RLS and State Machine for Visits (Corrected and Hardened)
--
-- ⚠️ تنبيه: هذا الملف للإنشاء والتوثيق المرجعي فقط، وممنوع تطبيقه مباشرة على الإنتاج
-- =============================================================================

BEGIN;

-- ─── 1. إعداد وصيانة الصلاحيات للأدوار ───

-- إضافة صلاحيات الإغلاق الإداري ومراجعة الاستثناءات الجغرافية للمشرف والمدير والتنفيذي
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm
FROM roles r
CROSS JOIN (
  VALUES
    ('visit_plans.close_administrative'),
    ('visit_plans.review_gps')
) AS p(perm)
WHERE r.name IN ('sales_supervisor', 'branch_manager', 'ceo')
ON CONFLICT DO NOTHING;

-- منح الـ ceo صلاحيات الكتابة والتأكيد والإلغاء صراحة
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm
FROM roles r
CROSS JOIN (
  VALUES
    ('visit_plans.create'),
    ('visit_plans.update'),
    ('visit_plans.confirm'),
    ('visit_plans.cancel')
) AS p(perm)
WHERE r.name = 'ceo'
ON CONFLICT DO NOTHING;

-- منح المندوب صلاحية تحديث خططه الخاصة في المسودة
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, 'visit_plans.update_own'
FROM roles r
WHERE r.name = 'sales_rep'
ON CONFLICT DO NOTHING;


-- ─── 2. تحديث سياسات RLS لجدول الخطط (public.visit_plans) ───

DROP POLICY IF EXISTS "vp_write" ON public.visit_plans;
DROP POLICY IF EXISTS "vp_read" ON public.visit_plans;
DROP POLICY IF EXISTS "vp_update" ON public.visit_plans;
DROP POLICY IF EXISTS "vp_insert" ON public.visit_plans;

-- سياسة القراءة (SELECT)
CREATE POLICY "vp_read" ON public.visit_plans
  FOR SELECT
  TO authenticated
  USING (
    -- المالك (المندوب)
    employee_id IN (SELECT id FROM hr_employees WHERE user_id = (SELECT auth.uid())) OR
    -- المشرف/المدير في نفس الفرع التنظيمي تاريخياً
    (check_permission((SELECT auth.uid()), 'visit_plans.read_team') AND organizational_branch_id IN (SELECT branch_id FROM hr_employees WHERE user_id = (SELECT auth.uid()))) OR
    -- الإدارة العليا
    check_permission((SELECT auth.uid()), 'visit_plans.read_all')
  );

-- سياسة الإنشاء (INSERT) - تفرض بقوة تطابق فرع الموظف الحالي مع الفرع التنظيمي للخطة عند الإنشاء
CREATE POLICY "vp_insert" ON public.visit_plans
  FOR INSERT
  TO authenticated
  WITH CHECK (
    check_permission((SELECT auth.uid()), 'visit_plans.create') AND
    created_by = (SELECT auth.uid()) AND
    organizational_branch_id = (SELECT branch_id FROM hr_employees WHERE id = employee_id) AND
    (
      -- المدير العام (ceo/read_all)
      check_permission((SELECT auth.uid()), 'visit_plans.read_all') OR
      -- المشرف التنظيمي للفرع
      (check_permission((SELECT auth.uid()), 'visit_plans.read_team') AND organizational_branch_id IN (SELECT branch_id FROM hr_employees WHERE user_id = (SELECT auth.uid()))) OR
      -- المندوب لنفسه وفرعه
      (employee_id IN (SELECT id FROM hr_employees WHERE user_id = (SELECT auth.uid())))
    )
  );

-- سياسة التحديث (UPDATE) - لا تشترط مساواة فرع الموظف الحالي بالفرع التنظيمي للخطة التاريخية لتمكين المندوب المنقول من تعديل سجلاته القديمة
CREATE POLICY "vp_update" ON public.visit_plans
  FOR UPDATE
  TO authenticated
  USING (
    -- المندوب في حالة draft فقط لخطته مع التحقق من تطابق الفرع التنظيمي مع فرع موظفه التاريخي المسجل بالخطة
    (
      status = 'draft'
      AND employee_id IN (SELECT id FROM hr_employees WHERE user_id = (SELECT auth.uid()))
      AND organizational_branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = (SELECT auth.uid()) LIMIT 1)
      AND check_permission((SELECT auth.uid()), 'visit_plans.update_own')
    ) OR
    -- المشرف والمدير للخطط التابعة لفرعهم
    (check_permission((SELECT auth.uid()), 'visit_plans.update') AND (
      check_permission((SELECT auth.uid()), 'visit_plans.read_all') OR
      (check_permission((SELECT auth.uid()), 'visit_plans.read_team') AND organizational_branch_id IN (SELECT branch_id FROM hr_employees WHERE user_id = (SELECT auth.uid())))
    ))
  )
  WITH CHECK (
    -- تم حذف شرط الفرع الحالي من التحديث للاحتفاظ بالفرع التاريخي ولقطة التأكيد كلقطة تاريخية صحيحة
    (
      status = 'draft' AND
      employee_id IN (SELECT id FROM hr_employees WHERE user_id = (SELECT auth.uid())) AND
      check_permission((SELECT auth.uid()), 'visit_plans.update_own')
    ) OR
    (
      check_permission((SELECT auth.uid()), 'visit_plans.update') AND (
        check_permission((SELECT auth.uid()), 'visit_plans.read_all') OR
        (check_permission((SELECT auth.uid()), 'visit_plans.read_team') AND organizational_branch_id IN (SELECT branch_id FROM hr_employees WHERE user_id = (SELECT auth.uid())))
      ) AND (
        -- في حال انتقال الحالة إلى التأكيد، يشترط صلاحية التأكيد صراحة
        (status != 'confirmed') OR check_permission((SELECT auth.uid()), 'visit_plans.confirm')
      ) AND (
        -- في حال انتقال الحالة إلى الإلغاء، يشترط صلاحية الإلغاء صراحة
        (status != 'cancelled') OR check_permission((SELECT auth.uid()), 'visit_plans.cancel')
      )
    )
  );


-- ─── 3. تحديث سياسات RLS لجدول البنود (public.visit_plan_items) ───

DROP POLICY IF EXISTS "vpi_write" ON public.visit_plan_items;
DROP POLICY IF EXISTS "vpi_read" ON public.visit_plan_items;
DROP POLICY IF EXISTS "vpi_insert" ON public.visit_plan_items;
DROP POLICY IF EXISTS "vpi_update" ON public.visit_plan_items;
DROP POLICY IF EXISTS "vpi_delete" ON public.visit_plan_items;

-- سياسة القراءة (SELECT)
CREATE POLICY "vpi_read" ON public.visit_plan_items
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.visit_plans vp
      WHERE vp.id = plan_id AND (
        vp.employee_id IN (SELECT id FROM hr_employees WHERE user_id = (SELECT auth.uid())) OR
        (check_permission((SELECT auth.uid()), 'visit_plans.read_team') AND vp.organizational_branch_id IN (SELECT branch_id FROM hr_employees WHERE user_id = (SELECT auth.uid()))) OR
        check_permission((SELECT auth.uid()), 'visit_plans.read_all')
      )
    )
  );

-- سياسة الإنشاء (INSERT) - مسموح في draft فقط
CREATE POLICY "vpi_insert" ON public.visit_plan_items
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.visit_plans vp
      WHERE vp.id = plan_id
        AND vp.status = 'draft'
        AND (
          (vp.employee_id IN (SELECT id FROM hr_employees WHERE user_id = (SELECT auth.uid())) AND check_permission((SELECT auth.uid()), 'visit_plans.create')) OR
          (check_permission((SELECT auth.uid()), 'visit_plans.create') AND (
            check_permission((SELECT auth.uid()), 'visit_plans.read_all') OR
            (check_permission((SELECT auth.uid()), 'visit_plans.read_team') AND vp.organizational_branch_id IN (SELECT branch_id FROM hr_employees WHERE user_id = (SELECT auth.uid())))
          ))
        )
    )
  );

-- سياسة التحديث (UPDATE) - للمندوب أثناء المسودة والتنفيذ وللمشرف
CREATE POLICY "vpi_update" ON public.visit_plan_items
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.visit_plans vp
      WHERE vp.id = plan_id AND (
        -- المندوب في حالة draft مع الصلاحية الخاصة
        (vp.status = 'draft' AND vp.employee_id IN (SELECT id FROM hr_employees WHERE user_id = (SELECT auth.uid())) AND check_permission((SELECT auth.uid()), 'visit_plans.update_own')) OR
        -- المندوب أثناء التنفيذ (الخطة confirmed أو in_progress)
        (vp.status IN ('confirmed', 'in_progress') AND vp.employee_id IN (SELECT id FROM hr_employees WHERE user_id = (SELECT auth.uid()))) OR
        -- المشرف والمدير عبر صلاحية update
        (check_permission((SELECT auth.uid()), 'visit_plans.update') AND (
          check_permission((SELECT auth.uid()), 'visit_plans.read_all') OR
          (check_permission((SELECT auth.uid()), 'visit_plans.read_team') AND vp.organizational_branch_id IN (SELECT branch_id FROM hr_employees WHERE user_id = (SELECT auth.uid())))
        ))
      )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.visit_plans vp
      WHERE vp.id = plan_id AND (
        -- المندوب في حالة draft (يجب أن تظل حالة البند pending)
        (vp.status = 'draft' AND vp.employee_id IN (SELECT id FROM hr_employees WHERE user_id = (SELECT auth.uid())) AND check_permission((SELECT auth.uid()), 'visit_plans.update_own') AND status = 'pending') OR
        -- المندوب أثناء التنفيذ يتطلب activities.create
        (vp.status IN ('confirmed', 'in_progress') AND vp.employee_id IN (SELECT id FROM hr_employees WHERE user_id = (SELECT auth.uid())) AND check_permission((SELECT auth.uid()), 'activities.create')) OR
        -- المشرف والمدير
        (check_permission((SELECT auth.uid()), 'visit_plans.update') AND (
          check_permission((SELECT auth.uid()), 'visit_plans.read_all') OR
          (check_permission((SELECT auth.uid()), 'visit_plans.read_team') AND vp.organizational_branch_id IN (SELECT branch_id FROM hr_employees WHERE user_id = (SELECT auth.uid())))
        ))
      )
    )
  );

-- سياسة الحذف (DELETE) - مسموح في draft فقط
CREATE POLICY "vpi_delete" ON public.visit_plan_items
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.visit_plans vp
      WHERE vp.id = plan_id
        AND vp.status = 'draft'
        AND (
          (vp.employee_id IN (SELECT id FROM hr_employees WHERE user_id = (SELECT auth.uid())) AND check_permission((SELECT auth.uid()), 'visit_plans.create')) OR
          (check_permission((SELECT auth.uid()), 'visit_plans.create') AND (
            check_permission((SELECT auth.uid()), 'visit_plans.read_all') OR
            (check_permission((SELECT auth.uid()), 'visit_plans.read_team') AND vp.organizational_branch_id IN (SELECT branch_id FROM hr_employees WHERE user_id = (SELECT auth.uid())))
          ))
        )
    )
  );


-- ─── 4. إسقاط التريجر القديم والدوال العامة المعتمدة عليه (حسب الترتيب الهيكلي الصحيح وبدون CASCADE) ───
DROP TRIGGER IF EXISTS trg_visit_plan_items_recalc ON public.visit_plan_items;
DROP FUNCTION IF EXISTS public.trg_recalculate_visit_plan_counts();
DROP FUNCTION IF EXISTS public.recalculate_visit_plan_counts(UUID);


-- ─── 5. دالة احتساب العدادات وحالة إغلاق الخطة (private.recalculate_visit_plan_counts) ───

CREATE OR REPLACE FUNCTION private.recalculate_visit_plan_counts(p_plan_id UUID)
RETURNS pg_catalog.void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  v_total          pg_catalog.int4 := 0;
  v_completed      pg_catalog.int4 := 0;
  v_skipped        pg_catalog.int4 := 0;
  v_missed         pg_catalog.int4 := 0;
  v_rescheduled    pg_catalog.int4 := 0;
  v_pending        pg_catalog.int4 := 0;
  v_in_progress    pg_catalog.int4 := 0;
  v_plan_date      pg_catalog.date;
  v_current_status pg_catalog.varchar(20);
  v_new_status     pg_catalog.varchar(20);
BEGIN
  -- جلب بيانات خطة الزيارة الحالية
  SELECT plan_date, status INTO v_plan_date, v_current_status
  FROM public.visit_plans
  WHERE id = p_plan_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- احتساب العدادات الفعلية من جدول البنود
  SELECT
    pg_catalog.count(id),
    pg_catalog.count(id) FILTER (WHERE status = 'completed'),
    pg_catalog.count(id) FILTER (WHERE status = 'skipped'),
    pg_catalog.count(id) FILTER (WHERE status = 'missed'),
    pg_catalog.count(id) FILTER (WHERE status = 'rescheduled'),
    pg_catalog.count(id) FILTER (WHERE status = 'pending'),
    pg_catalog.count(id) FILTER (WHERE status = 'in_progress')
  INTO v_total, v_completed, v_skipped, v_missed, v_rescheduled, v_pending, v_in_progress
  FROM public.visit_plan_items
  WHERE plan_id = p_plan_id;

  -- تطبيق آلة الحالات وصيغة إغلاق الخطة
  v_new_status := CASE
    WHEN v_current_status = 'draft' THEN 'draft'
    WHEN v_current_status = 'cancelled' THEN 'cancelled'
    WHEN v_total = 0 THEN v_current_status
    WHEN v_pending = v_total THEN 'confirmed'
    WHEN (v_completed + v_skipped + v_missed + v_rescheduled) = v_total THEN
      CASE
        WHEN v_completed = v_total THEN 'completed'
        WHEN v_missed = v_total THEN 'missed'
        ELSE 'partial'
      END
    ELSE 'in_progress'
  END;

  UPDATE public.visit_plans
  SET total_customers = v_total,
      completed_count = v_completed,
      skipped_count = v_skipped,
      missed_count = v_missed,
      rescheduled_count = v_rescheduled,
      status = v_new_status,
      started_at = CASE
        WHEN started_at IS NULL AND (v_in_progress > 0 OR v_completed > 0 OR v_skipped > 0 OR v_rescheduled > 0) THEN pg_catalog.clock_timestamp()
        ELSE started_at
      END,
      completed_at = CASE
        WHEN v_new_status IN ('completed', 'partial', 'missed') THEN pg_catalog.coalesce(completed_at, pg_catalog.clock_timestamp())
        ELSE NULL
      END,
      updated_at = pg_catalog.clock_timestamp()
  WHERE id = p_plan_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION private.recalculate_visit_plan_counts(uuid) FROM PUBLIC, anon, authenticated;


-- ─── 6. تريجر آلة حالات الخطط والتحقق والعدادات (private.trg_visit_plans_state_machine) ───

CREATE OR REPLACE FUNCTION private.trg_visit_plans_state_machine()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_total_items     INTEGER := 0;
  v_pending_items   INTEGER := 0;
  v_computed_status VARCHAR(20);
  v_total           INTEGER := 0;
  v_completed       INTEGER := 0;
  v_skipped         INTEGER := 0;
  v_missed          INTEGER := 0;
  v_rescheduled     INTEGER := 0;
  v_pending         INTEGER := 0;
  v_in_progress     INTEGER := 0;
BEGIN
  -- 1. حماية الخطط النهائية: قفل كامل لجميع الحقول باستثناء حقول الإغلاق الإداري وتحديث الوقت
  IF OLD.status IN ('completed', 'partial', 'cancelled', 'missed') THEN
    IF (to_jsonb(NEW) - ARRAY['updated_at', 'administrative_closed_by', 'administrative_closed_at', 'administrative_close_reason']) IS DISTINCT FROM
       (to_jsonb(OLD) - ARRAY['updated_at', 'administrative_closed_by', 'administrative_closed_at', 'administrative_close_reason']) THEN
      RAISE EXCEPTION 'يمنع تعديل خطة زيارة مغلقة أو ملغاة نهائياً';
    END IF;
  END IF;

  -- 2. تثبيت ومنع تعديل البيانات التعريفية الأساسية للخطة (id, created_at, created_by) دائماً
  IF NEW.id IS DISTINCT FROM OLD.id OR
     NEW.created_at IS DISTINCT FROM OLD.created_at OR
     NEW.created_by IS DISTINCT FROM OLD.created_by THEN
    RAISE EXCEPTION 'يمنع تعديل البيانات التعريفية الأساسية للخطة (معرف الخطة، وقت الإنشاء، منشئ الخطة)';
  END IF;

  -- 3. أثناء بقاء الخطة draft، يمنع تسجيل confirmed_by و confirmed_at ويجب بقائهما فارغين
  IF NEW.status = 'draft' AND (NEW.confirmed_by IS NOT NULL OR NEW.confirmed_at IS NOT NULL) THEN
    RAISE EXCEPTION 'يمنع تسجيل بيانات تأكيد الخطة أثناء بقائها في حالة مسودة (draft)';
  END IF;

  -- 4. بعد خروج الخطة من draft، يمنع تعديل confirmed_by و confirmed_at بواسطة العميل
  IF OLD.status != 'draft' AND (NEW.confirmed_by IS DISTINCT FROM OLD.confirmed_by OR NEW.confirmed_at IS DISTINCT FROM OLD.confirmed_at) THEN
    RAISE EXCEPTION 'يمنع تعديل بيانات تأكيد الخطة بعد تأكيدها';
  END IF;

  -- 5. حماية العدادات المشتقة ومطابقتها بالتجميع الفعلي من جدول البنود
  SELECT
    COUNT(id),
    COUNT(id) FILTER (WHERE status = 'completed'),
    COUNT(id) FILTER (WHERE status = 'skipped'),
    COUNT(id) FILTER (WHERE status = 'missed'),
    COUNT(id) FILTER (WHERE status = 'rescheduled')
  INTO v_total, v_completed, v_skipped, v_missed, v_rescheduled
  FROM public.visit_plan_items
  WHERE plan_id = NEW.id;

  IF (NEW.total_customers IS DISTINCT FROM OLD.total_customers OR
      NEW.completed_count IS DISTINCT FROM OLD.completed_count OR
      NEW.skipped_count IS DISTINCT FROM OLD.skipped_count OR
      NEW.missed_count IS DISTINCT FROM OLD.missed_count OR
      NEW.rescheduled_count IS DISTINCT FROM OLD.rescheduled_count) THEN
    IF NEW.total_customers IS DISTINCT FROM v_total OR
       NEW.completed_count IS DISTINCT FROM v_completed OR
       NEW.skipped_count IS DISTINCT FROM v_skipped OR
       NEW.missed_count IS DISTINCT FROM v_missed OR
       NEW.rescheduled_count IS DISTINCT FROM v_rescheduled THEN
      RAISE EXCEPTION 'يمنع تعديل العدادات المشتقة للخطط مباشرة إلا بمطابقة حالة البنود الفعلية';
    END IF;
  END IF;

  -- 6. التحقق من تطابق الفرع التنظيمي مع فرع الموظف المسند إليه أثناء المسودة وعند الانتقال للتأكيد
  IF NEW.status = 'draft' AND (NEW.employee_id IS DISTINCT FROM OLD.employee_id OR NEW.organizational_branch_id IS DISTINCT FROM OLD.organizational_branch_id) THEN
    IF NEW.organizational_branch_id IS DISTINCT FROM (SELECT branch_id FROM public.hr_employees WHERE id = NEW.employee_id) THEN
      RAISE EXCEPTION 'يجب أن يتطابق الفرع التنظيمي مع فرع الموظف المسند إليه أثناء المسودة';
    END IF;
  END IF;

  -- منع تغيير الموظف أو الفرع التنظيمي بعد خروج الخطة من حالة draft
  IF NEW.employee_id IS DISTINCT FROM OLD.employee_id OR NEW.organizational_branch_id IS DISTINCT FROM OLD.organizational_branch_id THEN
    IF OLD.status != 'draft' THEN
      RAISE EXCEPTION 'يمنع تغيير الموظف أو الفرع التنظيمي بعد تأكيد خطة الزيارة';
    END IF;
  END IF;

  -- 7. التحقق من انتقالات حالات الخطة المسموحة
  IF NEW.status != OLD.status THEN
    -- draft -> confirmed / cancelled
    IF OLD.status = 'draft' AND NEW.status NOT IN ('confirmed', 'cancelled') THEN
      RAISE EXCEPTION 'انتقال غير مسموح لحالة الخطة من draft إلى %', NEW.status;
    END IF;

    -- confirmed -> in_progress / cancelled / missed / completed / partial
    IF OLD.status = 'confirmed' AND NEW.status NOT IN ('in_progress', 'cancelled', 'missed', 'completed', 'partial') THEN
      RAISE EXCEPTION 'انتقال غير مسموح لحالة الخطة من confirmed إلى %', NEW.status;
    END IF;

    -- in_progress -> completed / partial / missed
    IF OLD.status = 'in_progress' AND NEW.status NOT IN ('completed', 'partial', 'missed') THEN
      RAISE EXCEPTION 'انتقال غير مسموح لحالة الخطة من in_progress إلى %', NEW.status;
    END IF;
  END IF;

  -- 8. شروط تأكيد الخطة (confirmed) وتثبيت هوية وتوقيت التأكيد من السيرفر
  IF NEW.status = 'confirmed' AND OLD.status = 'draft' THEN
    IF NOT (SELECT check_permission((SELECT auth.uid()), 'visit_plans.confirm')) THEN
      RAISE EXCEPTION 'ليس لديك صلاحية تأكيد خطط الزيارات';
    END IF;

    IF NEW.organizational_branch_id IS DISTINCT FROM (SELECT branch_id FROM public.hr_employees WHERE id = NEW.employee_id) THEN
      RAISE EXCEPTION 'يجب أن يتطابق الفرع التنظيمي مع فرع الموظف عند تأكيد الخطة';
    END IF;

    SELECT COUNT(id), COUNT(id) FILTER (WHERE status = 'pending')
    INTO v_total_items, v_pending_items
    FROM public.visit_plan_items
    WHERE plan_id = NEW.id;

    IF v_total_items = 0 THEN
      RAISE EXCEPTION 'يمنع تأكيد خطة زيارة لا تحتوي على بنود';
    END IF;
    IF v_pending_items != v_total_items THEN
      RAISE EXCEPTION 'جميع بنود خطة الزيارة المؤكدة يجب أن تكون في حالة معلقة (pending)';
    END IF;

    NEW.confirmed_by := (SELECT auth.uid());
    NEW.confirmed_at := pg_catalog.clock_timestamp();
  END IF;

  -- 9. شروط إلغاء الخطة (cancelled)
  IF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
    IF NOT (SELECT check_permission((SELECT auth.uid()), 'visit_plans.cancel')) THEN
      RAISE EXCEPTION 'ليس لديك صلاحية إلغاء خطط الزيارات';
    END IF;
    IF NULLIF(BTRIM(NEW.cancellation_reason), '') IS NULL THEN
      RAISE EXCEPTION 'إلغاء الخطة يتطلب تسجيل سبب الإلغاء';
    END IF;

    SELECT pg_catalog.count(id), pg_catalog.count(id) FILTER (WHERE status = 'pending')
    INTO v_total_items, v_pending_items
    FROM public.visit_plan_items
    WHERE plan_id = NEW.id;

    IF v_pending_items IS DISTINCT FROM v_total_items THEN
      RAISE EXCEPTION 'لا يمكن إلغاء خطة زيارة تم البدء في تنفيذها (يجب أن تكون جميع بنودها pending)';
    END IF;
  END IF;

  -- 10. التحقق من مطابقة الحالات التنفيذية مع بنود الخطة
  IF NEW.status IN ('in_progress', 'completed', 'partial', 'missed') THEN
    SELECT
      COUNT(id),
      COUNT(id) FILTER (WHERE status = 'completed'),
      COUNT(id) FILTER (WHERE status = 'skipped'),
      COUNT(id) FILTER (WHERE status = 'missed'),
      COUNT(id) FILTER (WHERE status = 'rescheduled'),
      COUNT(id) FILTER (WHERE status = 'pending'),
      COUNT(id) FILTER (WHERE status = 'in_progress')
    INTO v_total_items, v_completed, v_skipped, v_missed, v_rescheduled, v_pending, v_in_progress
    FROM public.visit_plan_items
    WHERE plan_id = NEW.id;

    v_computed_status := CASE
      WHEN v_total_items = 0 THEN NEW.status
      WHEN v_pending = v_total_items THEN 'confirmed'
      WHEN (v_completed + v_skipped + v_missed + v_rescheduled) = v_total_items THEN
        CASE
          WHEN v_completed = v_total_items THEN 'completed'
          WHEN v_missed = v_total_items THEN 'missed'
          ELSE 'partial'
        END
      ELSE 'in_progress'
    END;

    IF NEW.status != v_computed_status THEN
      RAISE EXCEPTION 'حالة الخطة (%) لا تطابق حالة البنود الفعلية (%)', NEW.status, v_computed_status;
    END IF;
  END IF;

  -- 11. التحقق من شروط وصلاحيات الإغلاق الإداري (يتم تثبيت الهوية والتاريخ من السيرفر)
  IF (NEW.administrative_closed_at IS DISTINCT FROM OLD.administrative_closed_at OR
      NEW.administrative_closed_by IS DISTINCT FROM OLD.administrative_closed_by OR
      NEW.administrative_close_reason IS DISTINCT FROM OLD.administrative_close_reason) THEN
    -- الإغلاق الإداري غير مسموح به إلا للخطة الجارية المنتهية (completed, partial, missed) وليس cancelled
    IF OLD.status NOT IN ('completed', 'partial', 'missed') THEN
      RAISE EXCEPTION 'الإغلاق الإداري غير مسموح به إلا للخطة الجارية المنتهية (completed, partial, missed)';
    END IF;
    -- منع الإغلاق الإداري لخطط اكتملت طبيعياً دون تدخل إداري (بدون بنود skipped)
    IF OLD.skipped_count = 0 THEN
      RAISE EXCEPTION 'الإغلاق الإداري غير مسموح به لخطط لا تحتوي على بنود تم تخطيها';
    END IF;
    -- منع تعديل بيانات الإغلاق الإداري بعد تسجيلها (تجميد كامل)
    IF OLD.administrative_closed_at IS NOT NULL OR OLD.administrative_closed_by IS NOT NULL THEN
      RAISE EXCEPTION 'يمنع تعديل بيانات الإغلاق الإداري بعد تسجيلها وحفظها';
    END IF;
    IF NOT (SELECT check_permission((SELECT auth.uid()), 'visit_plans.close_administrative')) THEN
      RAISE EXCEPTION 'ليس لديك صلاحية الإغلاق الإداري لخطط الزيارات';
    END IF;
    IF NULLIF(BTRIM(NEW.administrative_close_reason), '') IS NULL THEN
      RAISE EXCEPTION 'سبب الإغلاق الإداري يجب ألا يكون فارغاً';
    END IF;

    NEW.administrative_closed_by := (SELECT auth.uid());
    NEW.administrative_closed_at := pg_catalog.clock_timestamp();
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION private.trg_visit_plans_state_machine() FROM PUBLIC, anon, authenticated;


-- ─── 7. تريجر آلة حالات البنود والتحقق والـ GPS (private.trg_visit_plan_items_state_machine) ───

CREATE OR REPLACE FUNCTION private.trg_visit_plan_items_state_machine()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_plan_status        VARCHAR(20);
  v_is_gps_review_only BOOLEAN;
BEGIN
  -- 1. احتساب حالة مراجعة الـ GPS كأول خطوة قبل التحقق من حالة الخطة الأم
  v_is_gps_review_only := (to_jsonb(NEW) - ARRAY['gps_review_status', 'gps_exception_reviewed_by', 'gps_exception_reviewed_at', 'updated_at']) =
                          (to_jsonb(OLD) - ARRAY['gps_review_status', 'gps_exception_reviewed_by', 'gps_exception_reviewed_at', 'updated_at']);

  -- 2. منع تعديل البيانات التعريفية الأساسية للبند (id, created_at) دائماً وتجميد plan_id
  IF NEW.id IS DISTINCT FROM OLD.id OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'يمنع تعديل البيانات التعريفية الأساسية للبند (معرف البند، وقت الإنشاء)';
  END IF;
  IF NEW.plan_id IS DISTINCT FROM OLD.plan_id THEN
    RAISE EXCEPTION 'يمنع تغيير معرف الخطة (plan_id) للبند نهائياً';
  END IF;

  -- الحصول على حالة الخطة الأب
  SELECT status INTO v_plan_status
  FROM public.visit_plans
  WHERE id = NEW.plan_id;

  -- 3. منع تعديل هوية العميل والفرع وإحداثيات الموقع المتوقع للبند بعد خروج الخطة من draft
  IF v_plan_status IS DISTINCT FROM 'draft' THEN
    IF NEW.customer_id IS DISTINCT FROM OLD.customer_id OR
       NEW.customer_branch_id IS DISTINCT FROM OLD.customer_branch_id OR
       NEW.expected_location_source IS DISTINCT FROM OLD.expected_location_source OR
       NEW.expected_location_id IS DISTINCT FROM OLD.expected_location_id OR
       NEW.expected_lat IS DISTINCT FROM OLD.expected_lat OR
       NEW.expected_lng IS DISTINCT FROM OLD.expected_lng THEN
      RAISE EXCEPTION 'يمنع تغيير العميل أو الفرع أو لقطة الموقع المتوقع بعد تأكيد خطة الزيارة';
    END IF;
  END IF;

  -- 4. إلزام البنود بحالة pending داخل المسودة draft
  IF v_plan_status = 'draft' AND NEW.status != 'pending' THEN
    RAISE EXCEPTION 'يمنع تغيير حالة البند عن معلق (pending) أثناء مرحلة المسودة (draft)';
  END IF;

  -- 5. منع أي تعديل على بنود خطة ملغاة أو منتهية (ويُستثنى تعديل حقول مراجعة الـ GPS فقط)
  IF v_plan_status IN ('completed', 'partial', 'cancelled', 'missed') AND NOT v_is_gps_review_only THEN
    RAISE EXCEPTION 'يمنع تعديل بند تابع لخطة زيارة مغلقة أو ملغاة باستثناء حقول المراجعة الجغرافية';
  END IF;

  -- 6. حماية وحظر تعديل البنود المغلقة بعد اكتمالها باستثناء حقول المراجعة الجغرافية
  IF OLD.status IN ('completed', 'skipped', 'missed', 'rescheduled') AND NOT v_is_gps_review_only THEN
    RAISE EXCEPTION 'يمنع تعديل بيانات البند بعد الوصول للحالة النهائية باستثناء حقول المراجعة الجغرافية';
  END IF;

  -- 7. تقييد التعديل وحالات التنفيذ للخطة المؤكدة أو قيد التنفيذ فقط
  IF NEW.status != OLD.status THEN
    IF v_plan_status NOT IN ('confirmed', 'in_progress') THEN
      RAISE EXCEPTION 'يمنع تغيير حالة البند إلا إذا كانت الخطة مؤكدة أو قيد التنفيذ';
    END IF;

    -- الحالات النهائية لا تعاد فتحها أو تعديلها
    IF OLD.status IN ('completed', 'skipped', 'missed', 'rescheduled') THEN
      RAISE EXCEPTION 'يمنع إعادة فتح أو تعديل بند وصل إلى حالة نهائية (%)', OLD.status;
    END IF;

    -- pending -> in_progress / completed / skipped / missed / rescheduled
    IF OLD.status = 'pending' AND NEW.status NOT IN ('in_progress', 'completed', 'skipped', 'missed', 'rescheduled') THEN
      RAISE EXCEPTION 'انتقال غير مسموح لحالة البند من pending إلى %', NEW.status;
    END IF;

    -- in_progress -> completed / skipped / rescheduled
    IF OLD.status = 'in_progress' AND NEW.status NOT IN ('completed', 'skipped', 'rescheduled') THEN
      RAISE EXCEPTION 'انتقال غير مسموح لحالة البند من in_progress إلى %', NEW.status;
    END IF;
  END IF;

  -- 8. شروط طلب الاستثناء الجغرافي المعلق وتأكيد هوية الطالب من السيرفر
  IF NEW.gps_review_status = 'pending' THEN
    -- أثناء pending لا تسمح بتغيير requested_by عن صاحبه الأصلي
    IF OLD.gps_exception_requested_by IS NOT NULL AND NEW.gps_exception_requested_by IS DISTINCT FROM OLD.gps_exception_requested_by THEN
      RAISE EXCEPTION 'يمنع تعديل هوية مقدم طلب الاستثناء الجغرافي الأصلي';
    END IF;
    -- طلب الاستثناء الجديد يتطلب تطابق الطالب مع المستخدم الحالي
    IF OLD.gps_review_status IS DISTINCT FROM 'pending' THEN
      NEW.gps_exception_requested_by := (SELECT auth.uid());
    END IF;
    -- أثناء الحالة pending يمنع وجود مراجع أو تاريخ مراجعة
    IF NEW.gps_exception_reviewed_by IS NOT NULL OR NEW.gps_exception_reviewed_at IS NOT NULL THEN
      RAISE EXCEPTION 'حالة الاستثناء المعلقة (pending) تمنع وجود مراجع أو تاريخ مراجعة';
    END IF;
  END IF;

  -- 9. صيانة وتأمين انتقالات حالة مراجعة الاستثناء الجغرافي GPS للقرار النهائي
  IF NEW.gps_review_status IS DISTINCT FROM OLD.gps_review_status THEN
    -- الحالات approved و rejected هي حالات نهائية لا رجعة فيها
    IF OLD.gps_review_status IN ('approved', 'rejected') THEN
      RAISE EXCEPTION 'حالة مراجعة الاستثناء الجغرافي (%) نهائية ولا يمكن تعديلها أو إلغاؤها', OLD.gps_review_status;
    END IF;

    -- الانتقالات المسموحة الحصرية:
    -- a) not_required -> pending
    IF OLD.gps_review_status = 'not_required' AND NEW.gps_review_status != 'pending' THEN
      RAISE EXCEPTION 'انتقال غير مسموح لحالة مراجعة الاستثناء من not_required إلى %', NEW.gps_review_status;
    END IF;

    -- b) pending -> approved / rejected (المراجعة)
    IF OLD.gps_review_status = 'pending' AND NEW.gps_review_status NOT IN ('approved', 'rejected') THEN
      RAISE EXCEPTION 'انتقال غير مسموح لحالة مراجعة الاستثناء من pending إلى %', NEW.gps_review_status;
    END IF;
  ELSE
    -- إذا لم تتغير حالة المراجعة وكانت القرار قد اتخذ سابقاً، يمنع تعديل أي من حقول المراجعة والطلب نهائياً (تجميد كامل)
    IF OLD.gps_review_status IN ('approved', 'rejected') THEN
      IF NEW.gps_exception_reviewed_by IS DISTINCT FROM OLD.gps_exception_reviewed_by OR
         NEW.gps_exception_reviewed_at IS DISTINCT FROM OLD.gps_exception_reviewed_at OR
         NEW.gps_exception_requested_by IS DISTINCT FROM OLD.gps_exception_requested_by OR
         NEW.gps_exception_reason IS DISTINCT FROM OLD.gps_exception_reason THEN
        RAISE EXCEPTION 'يمنع تعديل بيانات الاستثناء الجغرافي بعد صدور القرار النهائي';
      END IF;
    END IF;
  END IF;

  -- 10. تفاصيل وموثوقية اتخاذ قرار الاعتماد أو الرفض وتثبيت الهوية والتواريخ من السيرفر
  IF NEW.gps_review_status IN ('approved', 'rejected') AND OLD.gps_review_status = 'pending' THEN
    -- حقول الطلب والمبرر لا تتغير أثناء المراجعة واتخاذ القرار
    IF NEW.gps_exception_reason IS DISTINCT FROM OLD.gps_exception_reason OR NEW.gps_exception_requested_by IS DISTINCT FROM OLD.gps_exception_requested_by THEN
      RAISE EXCEPTION 'يمنع تعديل مبرر الاستثناء الجغرافي أو مقدم الطلب أثناء عملية المراجعة واتخاذ القرار';
    END IF;
    IF NOT (SELECT check_permission((SELECT auth.uid()), 'visit_plans.review_gps')) THEN
      RAISE EXCEPTION 'ليس لديك صلاحية مراجعة الاستثناءات الجغرافية لخطط الزيارات';
    END IF;

    NEW.gps_exception_reviewed_by := (SELECT auth.uid());
    NEW.gps_exception_reviewed_at := pg_catalog.clock_timestamp();
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION private.trg_visit_plan_items_state_machine() FROM PUBLIC, anon, authenticated;


-- ─── 8. إنشاء تريجر إعادة الاحتساب في المخطط الخاص SECURITY DEFINER ومسار pg_catalog ───

CREATE OR REPLACE FUNCTION private.trg_recalculate_visit_plan_counts()
RETURNS pg_catalog.trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM private.recalculate_visit_plan_counts(OLD.plan_id);
    RETURN OLD;
  END IF;

  PERFORM private.recalculate_visit_plan_counts(NEW.plan_id);

  IF TG_OP = 'UPDATE' AND OLD.plan_id IS DISTINCT FROM NEW.plan_id THEN
    PERFORM private.recalculate_visit_plan_counts(OLD.plan_id);
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION private.trg_recalculate_visit_plan_counts() FROM PUBLIC, anon, authenticated;

-- ربط دوال آلة الحالات بالتريجرات الفعلية قبل الـ COMMIT
DROP TRIGGER IF EXISTS trg_visit_plans_state_machine ON public.visit_plans;
CREATE TRIGGER trg_visit_plans_state_machine
  BEFORE UPDATE ON public.visit_plans
  FOR EACH ROW
  EXECUTE FUNCTION private.trg_visit_plans_state_machine();

DROP TRIGGER IF EXISTS trg_visit_plan_items_state_machine ON public.visit_plan_items;
CREATE TRIGGER trg_visit_plan_items_state_machine
  BEFORE UPDATE ON public.visit_plan_items
  FOR EACH ROW
  EXECUTE FUNCTION private.trg_visit_plan_items_state_machine();

-- إعادة ربط التريجر trg_visit_plan_items_recalc بعد تحديث حقول استهدافه المحددة
DROP TRIGGER IF EXISTS trg_visit_plan_items_recalc ON public.visit_plan_items;
CREATE TRIGGER trg_visit_plan_items_recalc
  AFTER INSERT OR DELETE OR UPDATE OF status, plan_id ON public.visit_plan_items
  FOR EACH ROW EXECUTE FUNCTION private.trg_recalculate_visit_plan_counts();

COMMIT;
