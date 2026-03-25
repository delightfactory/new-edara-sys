-- ============================================================
-- EDARA v2 — Migration 02f: Hotfixes (Audit Findings)
-- Idempotent: safe to run multiple times
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. TRIGGER: منع المستخدم من تغيير حالته الخاصة
--    الثغرة: سياسة profiles_update تسمح id = auth.uid()
--    بدون قيود على الأعمدة، فيمكن لمستخدم موقوف تغيير
--    status = 'active' عبر API مباشر
--    الحل: trigger يمنع تعديل status ذاتياً
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION prevent_self_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- إذا لم يتغير status، لا حاجة لفحص
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- إذا كان المعدّل هو نفس المستخدم (وليس service_role)
  IF auth.uid() IS NOT NULL AND auth.uid() = OLD.id THEN
    -- تحقق: هل يملك صلاحية تعديل مستخدمين آخرين؟
    -- حتى لو كان admin — لا يُسمح بتغيير حالته الذاتية
    RAISE EXCEPTION 'لا يمكنك تغيير حالة حسابك بنفسك'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_self_status_change ON profiles;
CREATE TRIGGER trg_prevent_self_status_change
  BEFORE UPDATE ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION prevent_self_status_change();

-- ────────────────────────────────────────────────────────────
-- 2. INDEXES: فهارس مفقودة لجداول البنود
--    تحسين الأداء عند JOIN مع الجداول الأب
-- ────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_stock_adj_items_adj_id
  ON stock_adjustment_items(adjustment_id);

CREATE INDEX IF NOT EXISTS idx_stock_trans_items_trans_id
  ON stock_transfer_items(transfer_id);

CREATE INDEX IF NOT EXISTS idx_product_bundle_items_bundle_id
  ON product_bundle_items(bundle_id);

-- ────────────────────────────────────────────────────────────
-- 3. FIX: get_product_price — ضمان الحتمية (Determinism)
--    المشكلة: LIMIT 1 بدون ترتيب كافٍ يجعل النتيجة عشوائية
--    عند وجود قائمتين نشطتين بنفس min_qty
--    الحل: إضافة pl.created_at DESC كعامل فصل ثانوي
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

  -- 2. قائمة أسعار العميل المخصصة
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
-- 4. RPC: get_low_stock — فلتر المخزون المنخفض على مستوى DB
--    المشكلة: الفلتر البرمجي يكسر الـ Pagination
--    الحل: دالة SQL تُرجع البيانات مفلترة + count صحيح
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_low_stock(
  p_warehouse_id UUID DEFAULT NULL,
  p_offset INTEGER DEFAULT 0,
  p_limit INTEGER DEFAULT 50
)
RETURNS TABLE (
  id UUID,
  warehouse_id UUID,
  product_id UUID,
  quantity NUMERIC,
  reserved_quantity NUMERIC,
  available_quantity NUMERIC,
  wac NUMERIC,
  total_cost_value NUMERIC,
  warehouse_name TEXT,
  product_name TEXT,
  product_sku TEXT,
  min_stock_level NUMERIC,
  unit_name TEXT,
  unit_symbol TEXT,
  total_count BIGINT
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    s.id,
    s.warehouse_id,
    s.product_id,
    s.quantity,
    s.reserved_quantity,
    s.available_quantity,
    s.wac,
    s.total_cost_value,
    w.name AS warehouse_name,
    p.name AS product_name,
    p.sku  AS product_sku,
    COALESCE(p.min_stock_level, 0)::NUMERIC AS min_stock_level,
    u.name AS unit_name,
    u.symbol AS unit_symbol,
    COUNT(*) OVER() AS total_count
  FROM stock s
  JOIN warehouses w ON w.id = s.warehouse_id
  JOIN products p ON p.id = s.product_id
  LEFT JOIN units u ON u.id = p.base_unit_id
  WHERE s.available_quantity <= COALESCE(p.min_stock_level, 0)
    AND (p_warehouse_id IS NULL OR s.warehouse_id = p_warehouse_id)
  ORDER BY s.available_quantity ASC
  OFFSET p_offset LIMIT p_limit;
$$;

-- Grant
GRANT EXECUTE ON FUNCTION get_low_stock(UUID, INTEGER, INTEGER) TO authenticated;

-- ────────────────────────────────────────────────────────────
-- 5. FIX: إضافة عمود grade لجدول roles
--    لتمكين التحقق من هرمية الأدوار في Edge Functions
--    Grade أعلى = صلاحيات أعلى (super_admin = 100, etc.)
-- ────────────────────────────────────────────────────────────

DO $$ BEGIN
  ALTER TABLE roles ADD COLUMN grade INTEGER NOT NULL DEFAULT 10;
EXCEPTION
  WHEN duplicate_column THEN NULL;
END; $$;

-- تعيين الدرجات للأدوار النظامية المعروفة
UPDATE roles SET grade = 100 WHERE name = 'super_admin' AND grade = 10;
UPDATE roles SET grade = 90  WHERE name = 'ceo' AND grade = 10;
UPDATE roles SET grade = 70  WHERE name = 'branch_manager' AND grade = 10;
UPDATE roles SET grade = 50  WHERE name = 'accountant' AND grade = 10;
UPDATE roles SET grade = 40  WHERE name = 'warehouse_keeper' AND grade = 10;
UPDATE roles SET grade = 30  WHERE name = 'sales_rep' AND grade = 10;

-- دالة مساعدة: جلب أعلى grade للمستخدم
CREATE OR REPLACE FUNCTION get_user_max_grade(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_grade INTEGER;
BEGIN
  SELECT COALESCE(MAX(r.grade), 0) INTO v_grade
  FROM user_roles ur
  JOIN roles r ON r.id = ur.role_id
  WHERE ur.user_id = p_user_id;
  RETURN v_grade;
END;
$$;

-- دالة مساعدة: جلب أعلى grade لمجموعة أدوار
CREATE OR REPLACE FUNCTION get_roles_max_grade(p_role_ids UUID[])
RETURNS INTEGER
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_grade INTEGER;
BEGIN
  SELECT COALESCE(MAX(r.grade), 0) INTO v_grade
  FROM roles r
  WHERE r.id = ANY(p_role_ids);
  RETURN v_grade;
END;
$$;

GRANT EXECUTE ON FUNCTION get_user_max_grade(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_roles_max_grade(UUID[]) TO authenticated;
