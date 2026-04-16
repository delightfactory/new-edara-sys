-- ============================================================
-- Migration 75: update_customer_credit_terms RPC
-- ============================================================
-- PURPOSE: إنشاء دالة خلفية مخصصة لتعديل البنود الائتمانية فقط
--          (payment_terms, credit_limit, credit_days)
--
-- SECURITY: SECURITY DEFINER مع check_permission صريح داخل الدالة
-- SCOPE:    تعدّل 3 حقول فقط — لا رصيد افتتاحي — لا استدعاء لمسار قائم
-- NOTE:     لا تُعدّل أي دالة أو trigger قائمة
--           لا columns جديدة — لا جداول جديدة — لا triggers جديدة
-- ============================================================

CREATE OR REPLACE FUNCTION update_customer_credit_terms(
  p_customer_id UUID,
  p_payment_terms TEXT,
  p_credit_limit  NUMERIC,
  p_credit_days   INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- ─────────────────────────────────────────────────────────────
  -- حماية خلفية صريحة — مستقلة تماماً عن الواجهة
  -- لا تعتمد على ما تفعله الواجهة لأن أي مستخدم يمكنه استدعاء RPC مباشرة
  -- ─────────────────────────────────────────────────────────────
  IF NOT check_permission(auth.uid(), 'customers.credit.update') THEN
    RAISE EXCEPTION 'غير مصرح: يتطلب صلاحية customers.credit.update'
      USING ERRCODE = '42501';
  END IF;

  -- ─────────────────────────────────────────────────────────────
  -- تعديل البنود الائتمانية الثلاثة فقط
  -- الـ Trigger على credit_limit سيُسجّل تلقائياً في customer_credit_history
  -- ─────────────────────────────────────────────────────────────
  UPDATE customers
  SET
    payment_terms = p_payment_terms,
    credit_limit  = p_credit_limit,
    credit_days   = p_credit_days,
    updated_at    = now()
  WHERE id = p_customer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'العميل غير موجود: %', p_customer_id
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- منح الصلاحية للمستخدمين المصادق عليهم فقط
-- الحماية الحقيقية داخل الدالة بـ check_permission
-- ─────────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION update_customer_credit_terms(UUID, TEXT, NUMERIC, INTEGER) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION update_customer_credit_terms(UUID, TEXT, NUMERIC, INTEGER) TO authenticated;
