-- Stored generated percentages are not populated in NEW during BEFORE UPDATE.
-- Compare writable fields only; generated percentages and all business guards remain unchanged.
CREATE OR REPLACE FUNCTION private.trg_visit_plans_state_machine()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
    IF (to_jsonb(NEW) - ARRAY['updated_at', 'administrative_closed_by', 'administrative_closed_at', 'administrative_close_reason', 'completion_pct', 'closure_pct']) IS DISTINCT FROM
       (to_jsonb(OLD) - ARRAY['updated_at', 'administrative_closed_by', 'administrative_closed_at', 'administrative_close_reason', 'completion_pct', 'closure_pct']) THEN
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
    IF NOT (SELECT public.check_permission((SELECT auth.uid()), 'visit_plans.confirm')) THEN
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
    IF NOT (SELECT public.check_permission((SELECT auth.uid()), 'visit_plans.cancel')) THEN
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
    IF NOT (SELECT public.check_permission((SELECT auth.uid()), 'visit_plans.close_administrative')) THEN
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
$function$
