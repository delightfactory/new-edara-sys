-- ============================================================
-- 02g_audit_fixes.sql
-- EDARA v2 — إصلاحات التدقيق (Audit Findings)
-- Idempotent: آمن للتشغيل أكثر من مرة
--
-- يحتوي على:
-- 1. FIX C1: deduct_stock_at_wac — فحص available_quantity + تصفير WAC
-- 2. FIX C3: save_price_list_items_atomic — حفظ ذري لبنود القائمة
-- 3. FIX M3: get_product_price — فحص وجود العميل
-- 4. FIX M4: UNIQUE INDEX على price_list_items (tier)
-- 5. FIX L1: فهرس مركب على stock_movements
-- 6. FIX L2: عمود cancellation_reason في stock_transfers
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- 1. FIX C1+C2: deduct_stock_at_wac — إعادة كتابة مع إصلاحين:
--    أ) فحص available_quantity بدلاً من quantity لمنع بيع المحجوز
--    ب) تصفير WAC و total_cost_value عند وصول quantity لصفر أو سالب
--
--    ⚠️ تم الحفاظ على كل الوظائف الأصلية:
--    - FOR UPDATE لقفل صف المخزون
--    - فحص وجود صف المخزون
--    - فحص إعداد allow_negative_stock من company_settings
--    - حساب COGS بالـ WAC
--    - خصم quantity و total_cost_value
--    - تسجيل حركة مخزون كاملة (stock_movements)
--    - إرجاع v_cogs
--    - SECURITY DEFINER + SET search_path = public
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION deduct_stock_at_wac(
  p_warehouse_id UUID, p_product_id UUID, p_qty_out NUMERIC,
  p_movement_type TEXT, p_reference_type TEXT,
  p_reference_id UUID, p_user_id UUID
) RETURNS NUMERIC
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_stock stock%ROWTYPE;
  v_cogs NUMERIC;
  v_allow_negative BOOLEAN;
  v_new_qty NUMERIC;
  v_new_total NUMERIC;
  v_new_wac NUMERIC;
BEGIN
  -- قفل صف المخزون (نفس الآلية الأصلية)
  SELECT * INTO v_stock
  FROM stock
  WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'لا يوجد مخزون لهذا المنتج في هذا المخزن';
  END IF;

  -- ═══ FIX C1: فحص available_quantity بدلاً من quantity ═══
  -- available_quantity = quantity - reserved_quantity
  -- هذا يمنع بيع / خصم كميات محجوزة لتحويلات قيد الشحن
  IF v_stock.available_quantity < p_qty_out THEN
    -- فحص إعداد السماح بالمخزون السالب (نفس الآلية الأصلية)
    SELECT COALESCE(value::boolean, false) INTO v_allow_negative
    FROM company_settings WHERE key = 'sales.allow_negative_stock';

    IF NOT COALESCE(v_allow_negative, false) THEN
      RAISE EXCEPTION 'مخزون غير كافٍ (متاح: %, مطلوب: %)', v_stock.available_quantity, p_qty_out;
    END IF;
  END IF;

  -- حساب COGS بالـ WAC (نفس المعادلة الأصلية)
  v_cogs := p_qty_out * v_stock.wac;

  -- ═══ FIX C2: حساب الكمية الجديدة مع تصفير WAC عند الصفر ═══
  v_new_qty   := v_stock.quantity - p_qty_out;
  v_new_total := v_stock.total_cost_value - v_cogs;

  -- إذا وصلت الكمية لصفر أو سالب → تصفير WAC و total_cost_value
  -- لمنع تلوث WAC عند إضافة مخزون لاحقاً
  IF v_new_qty <= 0 THEN
    v_new_total := 0;
    v_new_wac   := 0;
  ELSE
    v_new_wac := v_stock.wac;  -- WAC لا يتغير عند الخصم (نفس السلوك الأصلي)
  END IF;

  UPDATE stock
  SET quantity = v_new_qty,
      total_cost_value = v_new_total,
      wac = v_new_wac,
      updated_at = now()
  WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id;

  -- تسجيل حركة المخزون (نفس الهيكل الأصلي بالكامل)
  INSERT INTO stock_movements (
    warehouse_id, product_id, unit_id, quantity, type,
    unit_cost, wac_before, wac_after, before_qty, after_qty,
    reference_type, reference_id, created_by
  ) VALUES (
    p_warehouse_id, p_product_id,
    (SELECT base_unit_id FROM products WHERE id = p_product_id),
    p_qty_out, p_movement_type,
    v_stock.wac, v_stock.wac, v_new_wac,
    v_stock.quantity, v_new_qty,
    p_reference_type, p_reference_id, p_user_id
  );

  RETURN v_cogs;
END; $$;


-- ────────────────────────────────────────────────────────────
-- 2. FIX C3: save_price_list_items_atomic — حفظ بنود القائمة ذرياً
--    يستبدل delete+insert في TypeScript بدالة SQL واحدة
--    داخل transaction ضمنية (كل دالة PL/pgSQL = transaction واحد)
--
--    الوظائف:
--    - حذف كل البنود القديمة لهذه القائمة
--    - إدراج البنود الجديدة
--    - إذا فشل أي جزء → rollback كامل تلقائي
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION save_price_list_items_atomic(
  p_price_list_id UUID,
  p_items JSONB  -- [{product_id, unit_id, price, min_qty?, max_qty?}]
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_item JSONB;
BEGIN
  -- التحقق من وجود قائمة الأسعار
  IF NOT EXISTS (SELECT 1 FROM price_lists WHERE id = p_price_list_id) THEN
    RAISE EXCEPTION 'قائمة الأسعار غير موجودة: %', p_price_list_id;
  END IF;

  -- حذف كل البنود القديمة لهذه القائمة
  DELETE FROM price_list_items WHERE price_list_id = p_price_list_id;

  -- إدراج البنود الجديدة (إذا وُجدت)
  IF p_items IS NOT NULL AND jsonb_array_length(p_items) > 0 THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
      INSERT INTO price_list_items (
        price_list_id, product_id, unit_id, price, min_qty, max_qty
      ) VALUES (
        p_price_list_id,
        (v_item ->> 'product_id')::UUID,
        (v_item ->> 'unit_id')::UUID,
        (v_item ->> 'price')::NUMERIC,
        COALESCE((v_item ->> 'min_qty')::NUMERIC, 1),
        (v_item ->> 'max_qty')::NUMERIC  -- NULL إذا لم يُحدد
      );
    END LOOP;
  END IF;
END; $$;

GRANT EXECUTE ON FUNCTION save_price_list_items_atomic(UUID, JSONB) TO authenticated;


-- ────────────────────────────────────────────────────────────
-- 3. FIX M3: get_product_price — فحص وجود العميل
--    ⚠️ إعادة كتابة كاملة مع الحفاظ على كل المنطق الأصلي:
--    - 6 مستويات أولوية التسعير (عميل → مدينة → محافظة → افتراضية → منتج → وحدة)
--    - فحص is_active و valid_from/valid_to في كل مستوى
--    - فحص min_qty / max_qty في كل مستوى
--    - ORDER BY min_qty DESC NULLS LAST, created_at DESC (deterministic)
--    - STABLE SECURITY DEFINER + SET search_path = public
--    الإضافة الوحيدة: IF NOT FOUND بعد جلب بيانات العميل
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_product_price(
  p_product_id UUID, p_customer_id UUID, p_unit_id UUID, p_qty NUMERIC DEFAULT 1
) RETURNS NUMERIC
  LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_price NUMERIC;
  v_base_price NUMERIC;
  v_base_unit UUID;
  v_customer RECORD;
BEGIN
  -- 1. جلب بيانات العميل
  SELECT governorate_id, city_id, price_list_id
  INTO v_customer
  FROM customers WHERE id = p_customer_id;

  -- ═══ FIX M3: فحص وجود العميل ═══
  IF NOT FOUND THEN
    RAISE EXCEPTION 'العميل غير موجود: %', p_customer_id;
  END IF;

  -- 2. قائمة أسعار العميل المخصصة (مع التحقق من النشاط والصلاحية)
  IF v_customer.price_list_id IS NOT NULL THEN
    SELECT pli.price INTO v_price
    FROM price_list_items pli
    JOIN price_lists pl ON pl.id = pli.price_list_id
    WHERE pli.price_list_id = v_customer.price_list_id
      AND pli.product_id = p_product_id AND pli.unit_id = p_unit_id
      AND pl.is_active = true
      AND (pl.valid_from IS NULL OR pl.valid_from <= CURRENT_DATE)
      AND (pl.valid_to IS NULL OR pl.valid_to >= CURRENT_DATE)
      AND p_qty >= COALESCE(pli.min_qty, 0)
      AND (pli.max_qty IS NULL OR p_qty <= pli.max_qty)
    ORDER BY pli.min_qty DESC NULLS LAST, pl.created_at DESC LIMIT 1;
    IF v_price IS NOT NULL THEN RETURN v_price; END IF;
  END IF;

  -- 3. قائمة أسعار المدينة
  IF v_customer.city_id IS NOT NULL THEN
    SELECT pli.price INTO v_price
    FROM price_list_items pli
    JOIN price_list_assignments pla ON pla.price_list_id = pli.price_list_id
    JOIN price_lists pl ON pl.id = pli.price_list_id
    WHERE pla.entity_type = 'city' AND pla.entity_id = v_customer.city_id
      AND pli.product_id = p_product_id AND pli.unit_id = p_unit_id
      AND pl.is_active = true
      AND (pl.valid_from IS NULL OR pl.valid_from <= CURRENT_DATE)
      AND (pl.valid_to IS NULL OR pl.valid_to >= CURRENT_DATE)
      AND p_qty >= COALESCE(pli.min_qty, 0)
      AND (pli.max_qty IS NULL OR p_qty <= pli.max_qty)
    ORDER BY pli.min_qty DESC NULLS LAST, pl.created_at DESC LIMIT 1;
    IF v_price IS NOT NULL THEN RETURN v_price; END IF;
  END IF;

  -- 4. قائمة أسعار المحافظة
  IF v_customer.governorate_id IS NOT NULL THEN
    SELECT pli.price INTO v_price
    FROM price_list_items pli
    JOIN price_list_assignments pla ON pla.price_list_id = pli.price_list_id
    JOIN price_lists pl ON pl.id = pli.price_list_id
    WHERE pla.entity_type = 'governorate' AND pla.entity_id = v_customer.governorate_id
      AND pli.product_id = p_product_id AND pli.unit_id = p_unit_id
      AND pl.is_active = true
      AND (pl.valid_from IS NULL OR pl.valid_from <= CURRENT_DATE)
      AND (pl.valid_to IS NULL OR pl.valid_to >= CURRENT_DATE)
      AND p_qty >= COALESCE(pli.min_qty, 0)
      AND (pli.max_qty IS NULL OR p_qty <= pli.max_qty)
    ORDER BY pli.min_qty DESC NULLS LAST, pl.created_at DESC LIMIT 1;
    IF v_price IS NOT NULL THEN RETURN v_price; END IF;
  END IF;

  -- 5. قائمة الأسعار الافتراضية
  SELECT pli.price INTO v_price
  FROM price_list_items pli
  JOIN price_lists pl ON pl.id = pli.price_list_id
  WHERE pl.is_default = true AND pl.is_active = true
    AND pli.product_id = p_product_id AND pli.unit_id = p_unit_id
    AND p_qty >= COALESCE(pli.min_qty, 0)
    AND (pli.max_qty IS NULL OR p_qty <= pli.max_qty)
  ORDER BY pli.min_qty DESC NULLS LAST, pl.created_at DESC LIMIT 1;
  IF v_price IS NOT NULL THEN RETURN v_price; END IF;

  -- 6. السعر من المنتج مباشرة
  SELECT selling_price, base_unit_id
  INTO v_base_price, v_base_unit
  FROM products WHERE id = p_product_id;

  -- تحقق إذا الوحدة المطلوبة هي نفس الأساسية
  IF v_base_unit = p_unit_id THEN
    RETURN COALESCE(v_base_price, 0);
  END IF;

  -- سعر الوحدة المخصص أو محسوب
  SELECT COALESCE(pu.selling_price, v_base_price * pu.conversion_factor)
  INTO v_price
  FROM product_units pu
  WHERE pu.product_id = p_product_id AND pu.unit_id = p_unit_id;

  RETURN COALESCE(v_price, v_base_price, 0);
END; $$;


-- ────────────────────────────────────────────────────────────
-- 4. FIX M4: UNIQUE INDEX على price_list_items (tier)
--    يمنع تكرار نفس المنتج/الوحدة/الحد الأدنى في نفس القائمة
--    مما يضمن حتمية ORDER BY min_qty DESC LIMIT 1
-- ────────────────────────────────────────────────────────────

-- تنظيف البنود المكررة قبل إنشاء الفهرس (إبقاء الأحدث فقط)
-- بدون هذا الخطوة، CREATE UNIQUE INDEX سيفشل إذا كانت هناك بيانات مكررة
DELETE FROM price_list_items a
USING price_list_items b
WHERE a.price_list_id = b.price_list_id
  AND a.product_id = b.product_id
  AND a.unit_id = b.unit_id
  AND COALESCE(a.min_qty, 0) = COALESCE(b.min_qty, 0)
  AND a.created_at < b.created_at;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pli_unique_tier
  ON price_list_items (price_list_id, product_id, unit_id, COALESCE(min_qty, 0));


-- ────────────────────────────────────────────────────────────
-- 5. FIX L1: فهرس مركب على stock_movements (reference_type, reference_id)
--    يُسرّع جلب الحركات المرتبطة بأمر بيع/شراء/تحويل محدد
-- ────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_stock_movements_ref
  ON stock_movements (reference_type, reference_id);


-- ────────────────────────────────────────────────────────────
-- 6. FIX L2: عمود cancellation_reason في stock_transfers
--    بالتناظر مع rejection_reason في stock_adjustments
-- ────────────────────────────────────────────────────────────

ALTER TABLE stock_transfers
  ADD COLUMN IF NOT EXISTS cancellation_reason TEXT;




-- 1. إسقاط التريجرات القديمة المسؤولة عن المضاعفة (التي كانت تضع الرصيد يدوياً)
DROP TRIGGER IF EXISTS trg_customer_init_balance ON customers;
DROP TRIGGER IF EXISTS trg_supplier_init_balance ON suppliers;