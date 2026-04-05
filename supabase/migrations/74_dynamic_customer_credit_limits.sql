-- ═══════════════════════════════════════════════════════════════════
-- Migration: 74_dynamic_customer_credit_limits.sql
-- الهدف: 
-- 1. دالة مستقلة ومقيدة الصلاحيات لحساب الحد الائتماني 
--    (متوسط صافي المبيعات لـ أخر 3 أشهر نشطة خلال 12 شهراً).
-- 2. تحديث سجل الـ Audit ليدعم تسجيل الأسباب المخصصة للعمليات الآلية.
-- 3. توفير دالة مجدولة لتحديث الحدود باحترافية وبدون آثار جانبية.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ────────────────────────────────────────────────────────────
-- 1. تعديل Trigger الخاص بالـ Audit لدعم أسباب ومستخدمين مخصصين
-- ────────────────────────────────────────────────────────────
-- لتجنب تسجيل "تحديث من واجهة إدارة العملاء" دائماً، نقوم بقراءة متغيرات سياقية
-- في حال تم استدعاء التعديل عبر سكريبت أو cron job.

CREATE OR REPLACE FUNCTION log_credit_limit_change()
RETURNS TRIGGER
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_custom_reason TEXT;
  v_changed_by UUID;
BEGIN
  IF OLD.credit_limit IS DISTINCT FROM NEW.credit_limit THEN
    -- محاولة قراءة سبب مخصص من الـ Session Config
    BEGIN
      v_custom_reason := current_setting('edara.credit_audit_reason', true);
    EXCEPTION WHEN OTHERS THEN
      v_custom_reason := NULL;
    END;
    
    -- محاولة قراءة مستخدم مخصص (العمليات الآلية) للاستخدام بدلاً من auth.uid()
    BEGIN
      v_changed_by := NULLIF(current_setting('edara.system_user_id', true), '')::UUID;
    EXCEPTION WHEN OTHERS THEN
      v_changed_by := NULL;
    END;

    INSERT INTO customer_credit_history (
      customer_id, limit_before, limit_after, changed_by, reason
    ) VALUES (
      NEW.id, OLD.credit_limit, NEW.credit_limit, 
      COALESCE(v_changed_by, auth.uid()),
      COALESCE(NULLIF(v_custom_reason, ''), 'تحديث من واجهة إدارة العملاء')
    );
  END IF;
  RETURN NEW;
END; $$;

-- ────────────────────────────────────────────────────────────
-- 2. دالة حساب المتوسط النشط للعميل
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_customer_active_monthly_average(
  p_customer_id UUID
) RETURNS NUMERIC
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_average NUMERIC := 0;
BEGIN
  WITH monthly_sales AS (
    -- 1. تجميع صافي المبيعات (إجمالي الفاتورة - المرتجعات المباشرة) على أساس شهري خلال آخر 12 شهر
    SELECT 
      date_trunc('month', order_date) as sales_month,
      SUM(total_amount - returned_amount) as net_sales
    FROM sales_orders
    WHERE customer_id = p_customer_id
      AND status IN ('delivered', 'completed', 'partially_delivered')
      AND order_date >= (CURRENT_DATE - INTERVAL '12 months')
    GROUP BY date_trunc('month', order_date)
  ),
  ranked_sales AS (
    -- 2. أخذ الأشهر التي كان للعميل فيها مسحوبات تزيد عن الصفر، وترتيبها من الأحدث للأقدم
    SELECT 
      net_sales,
      ROW_NUMBER() OVER(ORDER BY sales_month DESC) as rn
    FROM monthly_sales
    WHERE net_sales > 0
  )
  -- 3. أخذ متوسط أكبر/أحدث 3 شهور من الأشهر النشطة
  SELECT COALESCE(AVG(net_sales), 0) INTO v_average
  FROM ranked_sales
  WHERE rn <= 3;

  RETURN ROUND(v_average, 2);
END;
$$;

-- حماية: منع الاستدعاء من العامة لتفادي استغلال الدالة (SECURITY DEFINER)
REVOKE EXECUTE ON FUNCTION get_customer_active_monthly_average(UUID) FROM PUBLIC;

-- ────────────────────────────────────────────────────────────
-- 3. دالة التطبيق الشامل للحدود الائتمانية
-- ────────────────────────────────────────────────────────────

-- هذه الدالة يمكن جدولتها (Scheduled Cron) كل أول شهر.
CREATE OR REPLACE FUNCTION apply_dynamic_credit_limits()
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer RECORD;
  v_new_limit NUMERIC;
  v_system_user UUID;
  v_explicit_reason TEXT;
BEGIN
  -- المعالجة للعمليات الآلية: إيجاد مستخدم إداري لتسجيل الـ Audit إذا كنا في خلفية العمل (Cron) ولم يتم التمرير
  IF auth.uid() IS NULL AND current_setting('edara.system_user_id', true) IS NULL THEN
    SELECT p.id INTO v_system_user
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;
    
    IF v_system_user IS NOT NULL THEN
      PERFORM set_config('edara.system_user_id', v_system_user::text, true);
    END IF;
  END IF;

  -- فحص إذا كان هناك سبب معين للـ Audit أو تعيين الافتراضي للعمليات الآلية
  v_explicit_reason := current_setting('edara.credit_audit_reason', true);
  IF v_explicit_reason IS NULL OR v_explicit_reason = '' THEN
    PERFORM set_config('edara.credit_audit_reason', 'تحديث آلي للحد الائتماني', true);
  END IF;

  -- المعالجة للعملاء النشطين والمسموح لهم بالشراء الآجل/المختلط فقط
  FOR v_customer IN 
    SELECT id, credit_limit 
    FROM customers 
    WHERE is_active = true 
      AND payment_terms IN ('mixed', 'credit')
  LOOP
    -- حساب متوسط آخر 3 أشهر نشطة (إن وجدت)
    v_new_limit := get_customer_active_monthly_average(v_customer.id);
    
    -- قاعدة حماية: 
    -- نقوم بالتحديث فقط إذا كان للعميل متوسط نشط (> 0).
    IF v_new_limit > 0 THEN
      UPDATE customers
      SET credit_limit = v_new_limit,
          updated_at = now()
      WHERE id = v_customer.id
        AND credit_limit != v_new_limit;
    END IF;
  END LOOP;
  
  -- مسح السبب والمستخدم المخصص إذا نحن من قمنا بتعيينهما لتفادي تسربهما للجلسة
  IF auth.uid() IS NULL AND v_system_user IS NOT NULL THEN
    PERFORM set_config('edara.system_user_id', '', true);
  END IF;
  IF v_explicit_reason IS NULL OR v_explicit_reason = '' THEN
    PERFORM set_config('edara.credit_audit_reason', '', true);
  END IF;
END;
$$;

-- حماية: منع الاستدعاء من العامة (تُستدعى داخلياً أو عبر service_role)
REVOKE EXECUTE ON FUNCTION apply_dynamic_credit_limits() FROM PUBLIC;

-- ────────────────────────────────────────────────────────────
-- 4. التنفيذ الأولي كجزء من المايجريشن
-- ────────────────────────────────────────────────────────────

DO $$
DECLARE
  v_admin_id UUID;
BEGIN
  -- إيجاد مستخدم إداري ليُنْسَب له التحديث لتفادي فشل القيد (NOT NULL) في جدول הـ Audit
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;
  
  IF v_admin_id IS NOT NULL THEN
    PERFORM set_config('edara.system_user_id', v_admin_id::text, true);
    PERFORM set_config('edara.credit_audit_reason', 'استكمال متطلبات المايجريشن (حساب أولي)', true);
    
    PERFORM apply_dynamic_credit_limits();
    
    -- تنظيف المتغيرات
    PERFORM set_config('edara.system_user_id', '', true);
    PERFORM set_config('edara.credit_audit_reason', '', true);
  END IF;
END $$;

COMMIT;
