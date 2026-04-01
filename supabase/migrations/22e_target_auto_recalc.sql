-- ============================================================
-- 22e_target_auto_recalc.sql
-- EDARA v2 — Auto-Recalculation Engine للأهداف (v2 — Patched)
--
-- السبب الجذري: target_progress لا يتحدث بعد البيع/التحصيل تلقائياً
--
-- التصميم: PostgreSQL AFTER Triggers
--   1. sales_orders → AFTER UPDATE OF status → delivered/completed
--      يغطي: sales_value، product_qty، category_spread، upgrade_value
--
--   2. payment_receipts → AFTER UPDATE OF status أو AFTER INSERT
--      يغطي: collection
--      الفجوة المُغلقة: deliver_sales_order في 11_final_accounting_sync.sql
--      يُنشئ payment_receipts مباشرة بـ status='confirmed' عبر INSERT
--      وليس UPDATE، لذلك نحتاج Trigger على INSERT أيضًا.
--
-- نطاق التغطية (success-on-transition only):
--   ✅ sales_orders: انتقال → delivered أو → completed
--   ✅ payment_receipts: INSERT بـ status=confirmed مباشرة (cash)
--   ✅ payment_receipts: UPDATE status → confirmed (non-cash approval)
--   ⏭ خارج النطاق (intentionally deferred):
--      - عكس/إلغاء sales_orders بعد delivered/completed
--      - رفض payment_receipts بعد confirmed
--      - تعديلات تاريخية على فترات الأهداف
--      cron يُغطي هذه الحالات كـ safety net دوري
--
-- عدم الازدواجية (no double counting):
--   recalculate_target_progress() تعمل بـ INSERT ... ON CONFLICT DO UPDATE
--   على (target_id, snapshot_date) — أي إعادة حساب ليست تراكماً بل استبدال.
--   trigger + cron = نفس snapshot_date يُعاد حسابه مرتين → نفس القيمة.
--   delivered→completed لا يُطلق trigger لأن الشرط:
--   NOT IN ('delivered','completed') AND NEW IN ('delivered','completed')
--   وبالتالي delivered→completed يمر في OLD.status='delivered' → شرط يمنعه.
--
-- Idempotent: آمن للتشغيل المتكرر
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- SECTION 1: دالة الاستهداف الذكي
-- تبحث عن الأهداف النشطة التي تشمل موظفاً محدداً خلال فترتها
--
-- p_effective_date: إذا محدد، يبحث عن أهداف كانت نشطة بتاريخ الحدث الأصلي
--   (مثلاً: تاريخ البيع / التحصيل الأصلي لا تاريخ تأكيد المرتجع)
--   ويحسب كل هدف متأثر بـ LEAST(CURRENT_DATE, period_end)
-- بدون p_effective_date: يستخدم p_snapshot_date كمعتاد
-- (هذا يحل P1: Late Return Period Attribution)
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.recalculate_targets_for_employee(
  p_employee_id    UUID,     -- hr_employees.id
  p_type_codes     TEXT[],   -- أنواع الأهداف المرتبطة بالحدث
  p_snapshot_date  DATE DEFAULT CURRENT_DATE,
  p_effective_date DATE DEFAULT NULL  -- جديد: تاريخ الحدث الأصلي (مرتجعات متأخرة)
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_target_id    UUID;
  v_period_end   DATE;   -- نهاية فترة الهدف (لحساب calc_date)
  v_branch_id    UUID;
  v_dept_id      UUID;
  v_search_date  DATE;   -- التاريخ المستخدم لإيجاد الأهداف
  v_calc_date    DATE;   -- التاريخ الممرر لـ recalculate_target_progress
BEGIN
  -- p_effective_date: إذا موجود نبحث عن الأهداف بتاريخ الحدث الأصلي
  -- (مثلاً: تاريخ البيع للمرتجعات) وليس تاريخ تأكيد المرتجع
  v_search_date := COALESCE(p_effective_date, p_snapshot_date);

  -- جلب بيانات الموظف مرة واحدة لتجنب subquery متكررة
  SELECT branch_id, department_id
  INTO v_branch_id, v_dept_id
  FROM hr_employees
  WHERE id = p_employee_id AND status = 'active'
  LIMIT 1;

  -- البحث عن الأهداف النشطة المتأثرة فقط (بتاريخ الحدث الأصلي)
  FOR v_target_id, v_period_end IN
    SELECT DISTINCT t.id, t.period_end
    FROM public.targets t
    WHERE t.is_active   = true
      AND t.is_paused   = false
      AND t.period_start <= v_search_date   -- الهدف كان نشطاً عند تاريخ الحدث
      AND t.period_end   >= v_search_date   -- ولم ينتهِ بعد تاريخ الحدث
      AND t.type_code    = ANY(p_type_codes)
      AND (
        (t.scope = 'individual' AND t.scope_id = p_employee_id)
        OR (t.scope = 'branch'      AND t.scope_id = v_branch_id      AND v_branch_id IS NOT NULL)
        OR (t.scope = 'department'  AND t.scope_id = v_dept_id        AND v_dept_id   IS NOT NULL)
        OR  t.scope = 'company'
      )
  LOOP
    -- إذا p_effective_date موجود (late return):
    --   نحسب حتى LEAST(CURRENT_DATE, period_end) لذلك الهدف
    --   الجدوى: returned_amount على so وreturned_quantity على soi
    --   تعكس المرتجع بغض النظر عن تاريخ تأكيده.
    v_calc_date := CASE
      WHEN p_effective_date IS NOT NULL THEN LEAST(CURRENT_DATE, v_period_end)
      ELSE p_snapshot_date
    END;
    PERFORM public.recalculate_target_progress(v_target_id, v_calc_date);
  END LOOP;
END;
$$;

-- ════════════════════════════════════════════════════════════
-- SECTION 2: Trigger Function — sales_orders
-- يُطلق عند انتقال status إلى 'delivered' أو 'completed'
-- AFTER UPDATE OF status فقط
-- ملاحظة: delivered→completed لا يُطلق لأن OLD.status='delivered'
--         وشرط NOT IN('delivered','completed') يمنع التكرار
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trg_sales_order_recalc_targets()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_employee_id UUID;
  v_sales_codes TEXT[] := ARRAY['sales_value','product_qty','category_spread','upgrade_value'];
BEGIN
  -- شرط صريح: انتقال من غير delivered/completed إلى delivered/completed
  -- هذا يمنع: draft→confirmed، delivered→completed (تكرار)
  IF OLD.status NOT IN ('delivered','completed')
     AND NEW.status IN ('delivered','completed')
     AND NEW.rep_id IS NOT NULL
  THEN
    SELECT id INTO v_employee_id
    FROM hr_employees
    WHERE user_id = NEW.rep_id
      AND status  = 'active'
    LIMIT 1;

    IF v_employee_id IS NOT NULL THEN
      PERFORM public.recalculate_targets_for_employee(
        v_employee_id,
        v_sales_codes,
        COALESCE(NEW.delivered_at::DATE, CURRENT_DATE)
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ════════════════════════════════════════════════════════════
-- SECTION 3: Trigger Function — payment_receipts (UPDATE)
-- يُطلق عند UPDATE status → 'confirmed'
-- يغطي: تأكيد يدوي للإيصالات المُعلَّقة (non-cash)
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trg_payment_receipt_update_recalc()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_employee_id   UUID;
  v_collect_codes TEXT[] := ARRAY['collection'];
BEGIN
  -- انتقال من غير confirmed إلى confirmed عبر UPDATE
  IF (OLD.status IS DISTINCT FROM 'confirmed')
     AND NEW.status = 'confirmed'
     AND NEW.collected_by IS NOT NULL
  THEN
    SELECT id INTO v_employee_id
    FROM hr_employees
    WHERE user_id = NEW.collected_by
      AND status  = 'active'
    LIMIT 1;

    IF v_employee_id IS NOT NULL THEN
      PERFORM public.recalculate_targets_for_employee(
        v_employee_id,
        v_collect_codes,
        CURRENT_DATE
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ════════════════════════════════════════════════════════════
-- SECTION 4: Trigger Function — payment_receipts (INSERT)
-- [FIX] يُطلق عند INSERT مباشر بـ status='confirmed'
-- يغطي: مسار التسليم النقدي في deliver_sales_order
-- (11_final_accounting_sync.sql line 157 يُنشئ receipt بـ confirmed مباشرة)
-- لو أُطلق send INSERT+UPDATE على نفس اليوم → recalc idempotent → لا ازدواجية
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trg_payment_receipt_insert_recalc()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_employee_id   UUID;
  v_collect_codes TEXT[] := ARRAY['collection'];
BEGIN
  -- فقط عند INSERT مباشر بـ status=confirmed (مسار النقدي الفوري)
  IF NEW.status = 'confirmed' AND NEW.collected_by IS NOT NULL THEN

    SELECT id INTO v_employee_id
    FROM hr_employees
    WHERE user_id = NEW.collected_by
      AND status  = 'active'
    LIMIT 1;

    IF v_employee_id IS NOT NULL THEN
      PERFORM public.recalculate_targets_for_employee(
        v_employee_id,
        v_collect_codes,
        CURRENT_DATE
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ════════════════════════════════════════════════════════════
-- SECTION 5: Trigger Function — sales_returns
-- يُطلق عند تأكيد مرتجع المبيعات (status → 'confirmed')
-- أنواع الأهداف المتأثرة:
--   - sales_value   (يقل بالمرتجع المؤكد)
--   - product_qty   (يقل بالكميات المرتجعة)
--   - upgrade_value (صافي مشتريات العميل)
--   - category_spread (قد تسقط تصنيفات)
--   - collection    (فقط المرتجع النقدي)
--
-- لماذا لا يحدث Double Counting مع trigger البيع/التحصيل؟
-- recalculate_target_progress() تعمل بـ INSERT ON CONFLICT DO UPDATE
-- على (target_id, snapshot_date) — أي كل recalc يُحل محل السابق.
-- trigger المرتجع + trigger البيع = نفس snapshot يُعاد حسابه → نتيجة صحيحة.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trg_sales_return_recalc_targets()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_rep_user_id      UUID;
  v_rep_emp_id       UUID;
  v_sale_date        DATE;   -- تاريخ البيع الأصلي (effective date لأهداف البيع)
  v_collector_user   UUID;
  v_collector_emp_id UUID;
  v_payment_date     DATE;   -- تاريخ التحصيل الأصلي (effective date لأهداف التحصيل)
  v_sales_codes      TEXT[] := ARRAY['sales_value','product_qty','category_spread','upgrade_value'];
  v_collect_codes    TEXT[] := ARRAY['collection'];
BEGIN
  -- نُطلق فقط عند انتقال status إلى 'confirmed'
  IF (OLD.status IS DISTINCT FROM 'confirmed') AND NEW.status = 'confirmed' THEN

    -- الجزء 1: أهداف البيع — مخصوصة للمندوب (rep_id)
    -- effective_date = تاريخ التسليم الأصلي (ليس تاريخ تأكيد المرتجع)
    -- حل P1 Late Return: بيع مارس + مرتجع أبريل → recalc_for_employee يجد
    --   هدف مارس (فترته تغطي sold_date) ويحسب LEAST(TODAY, period_end)
    SELECT so.rep_id, so.delivered_at::DATE
    INTO v_rep_user_id, v_sale_date
    FROM sales_orders so
    WHERE so.id = NEW.order_id
    LIMIT 1;

    IF v_rep_user_id IS NOT NULL AND v_sale_date IS NOT NULL THEN
      SELECT id INTO v_rep_emp_id
      FROM hr_employees
      WHERE user_id = v_rep_user_id AND status = 'active'
      LIMIT 1;

      IF v_rep_emp_id IS NOT NULL THEN
        -- نمرر v_sale_date كـ p_effective_date → الدالة تبحث عن أهداف مارس
        --   وتحسب بـ LEAST(CURRENT_DATE, period_end) لكل منها
        PERFORM public.recalculate_targets_for_employee(
          v_rep_emp_id,
          v_sales_codes,
          CURRENT_DATE,     -- p_snapshot_date (لا يُستخدم عند وجود p_effective_date)
          v_sale_date       -- p_effective_date: تاريخ البيع = مدى فترة الهدف
        );
      END IF;
    END IF;

    -- الجزء 2: أهداف التحصيل — مخصوصة للمحصّل الفعلي (collected_by)
    -- حل P1 Collection Ownership: نبحث عن الإيصال المرتبط بالطلب
    --   وننسب الخصم للمحصّل فعلاً لا للمندوب
    -- effective_date = تاريخ الإيصال الأصلي (collected_at)
    SELECT pr.collected_by, pr.created_at::DATE
    INTO v_collector_user, v_payment_date
    FROM payment_receipts pr
    WHERE pr.sales_order_id = NEW.order_id
      AND pr.status = 'confirmed'
    ORDER BY pr.created_at ASC
    LIMIT 1;

    IF v_collector_user IS NOT NULL AND v_payment_date IS NOT NULL THEN
      SELECT id INTO v_collector_emp_id
      FROM hr_employees
      WHERE user_id = v_collector_user AND status = 'active'
      LIMIT 1;

      IF v_collector_emp_id IS NOT NULL THEN
        -- نمرر v_payment_date كـ p_effective_date → أهداف collection كانت نشطة عند التحصيل
        PERFORM public.recalculate_targets_for_employee(
          v_collector_emp_id,
          v_collect_codes,
          CURRENT_DATE,
          v_payment_date  -- p_effective_date: تاريخ التحصيل = مدى فترة الهدف
        );
      END IF;
    END IF;

  END IF;

  RETURN NEW;
END;
$$;


-- ════════════════════════════════════════════════════════════
-- SECTION 6: تركيب الـ Triggers (Idempotent)
-- ════════════════════════════════════════════════════════════

-- Trigger على sales_orders: AFTER UPDATE فقط
DROP TRIGGER IF EXISTS trg_so_recalc_targets ON public.sales_orders;
CREATE TRIGGER trg_so_recalc_targets
  AFTER UPDATE OF status ON public.sales_orders
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_sales_order_recalc_targets();

-- Trigger على payment_receipts: AFTER UPDATE (non-cash approval)
DROP TRIGGER IF EXISTS trg_pr_update_recalc_targets ON public.payment_receipts;
CREATE TRIGGER trg_pr_update_recalc_targets
  AFTER UPDATE OF status ON public.payment_receipts
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_payment_receipt_update_recalc();

-- Trigger على payment_receipts: AFTER INSERT (cash direct-confirmed)
DROP TRIGGER IF EXISTS trg_pr_insert_recalc_targets ON public.payment_receipts;
CREATE TRIGGER trg_pr_insert_recalc_targets
  AFTER INSERT ON public.payment_receipts
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_payment_receipt_insert_recalc();

-- Trigger على sales_returns: AFTER UPDATE (return confirmed)
DROP TRIGGER IF EXISTS trg_sr_recalc_targets ON public.sales_returns;
CREATE TRIGGER trg_sr_recalc_targets
  AFTER UPDATE OF status ON public.sales_returns
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_sales_return_recalc_targets();

-- ════════════════════════════════════════════════════════════
-- SECTION 7: تنظيف: حذف الـ trigger القديم (الإصدار السابق)
-- ════════════════════════════════════════════════════════════
DROP TRIGGER IF EXISTS trg_pr_recalc_targets ON public.payment_receipts;
DROP FUNCTION IF EXISTS public.trg_payment_receipt_recalc_targets();

-- ════════════════════════════════════════════════════════════
-- SECTION 8: تحقق من التركيب (Diagnostic)
-- ════════════════════════════════════════════════════════════
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE trigger_name = 'trg_so_recalc_targets'
      AND event_object_table = 'sales_orders'
  ) THEN
    RAISE NOTICE '[EDARA] ✓ trg_so_recalc_targets (sales → delivered/completed)';
  ELSE
    RAISE WARNING '[EDARA] ✗ فشل: trg_so_recalc_targets';
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE trigger_name = 'trg_pr_update_recalc_targets'
      AND event_object_table = 'payment_receipts'
  ) THEN
    RAISE NOTICE '[EDARA] ✓ trg_pr_update_recalc_targets (receipt UPDATE → confirmed)';
  ELSE
    RAISE WARNING '[EDARA] ✗ فشل: trg_pr_update_recalc_targets';
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE trigger_name = 'trg_pr_insert_recalc_targets'
      AND event_object_table = 'payment_receipts'
  ) THEN
    RAISE NOTICE '[EDARA] ✓ trg_pr_insert_recalc_targets (cash INSERT confirmed)';
  ELSE
    RAISE WARNING '[EDARA] ✗ فشل: trg_pr_insert_recalc_targets';
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE trigger_name = 'trg_sr_recalc_targets'
      AND event_object_table = 'sales_returns'
  ) THEN
    RAISE NOTICE '[EDARA] ✓ trg_sr_recalc_targets (sales_return → confirmed)';
  ELSE
    RAISE WARNING '[EDARA] ✗ فشل: trg_sr_recalc_targets';
  END IF;
END;
$$;

-- ════════════════════════════════════════════════════════════
-- Net-Engine Lifecycle Coverage:
--   ✅ سيناريو A: cancel قبل التسليم → no-op (الطلب لم يدخل أصلاً)
--   ✅ سيناريو B: delivered/completed → trg_so_recalc_targets
--   ✅ سيناريو C: confirm_sales_return (نقدي) → trg_sr_recalc_targets
--                              + Net collection ينخفض (الدالة تخصم تلقائياً)
--   ✅ سيناريو D: confirm_sales_return (آجل) → trg_sr_recalc_targets
--                              + لا يُخصم collection (الدالة تفرق بين cash/credit)
--   ✅ سيناريو E: Rewards/pool → Net (calc_target_pool_value متسقة مع recalc)
--
-- ⏭ Intentionally Deferred:
--   - عكس rejection بعد confirmed (payment or return)
--   - تعديل period_start/period_end بعد إنشاء الهدف
--   - مزامير بين مرتجعات متعددة لنفس التصنيف في حالة company scope
--   cron يغطي هذه كـ safety net دوري
-- ════════════════════════════════════════════════════════════
