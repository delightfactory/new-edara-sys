-- ============================================================
-- 02e_inventory_hardening.sql
-- EDARA v2 — تقوية نظام المخازن (التسويات + التحويلات)
--
-- يحتوي على:
-- 0. تعديلات Schema
-- 1. create_adjustment_with_items (ذرية جديدة)
-- 2. confirm_adjustment (إعادة كتابة — system_qty لحظي + حماية المحجوز)
-- 3. reject_adjustment (إعادة كتابة — صلاحية + سبب الرفض)
-- 4. create_transfer_with_reservation (تحديث — منع التكرار)
-- 5. cancel_transfer (تحديث — تسجيل المُلغي والوقت)
-- 6. GRANT
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- 0. تعديلات Schema
-- ────────────────────────────────────────────────────────────

-- تتبع من ألغى التحويل ومتى
ALTER TABLE stock_transfers
  ADD COLUMN IF NOT EXISTS cancelled_by UUID REFERENCES profiles(id),
  ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;

-- سبب رفض التسوية
ALTER TABLE stock_adjustments
  ADD COLUMN IF NOT EXISTS rejection_reason TEXT;


-- ────────────────────────────────────────────────────────────
-- 1. create_adjustment_with_items — إنشاء تسوية ذرية
--    تقرأ system_qty من stock.quantity لحظياً
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION create_adjustment_with_items(
  p_warehouse_id UUID,
  p_type TEXT,           -- 'add' | 'remove' | 'count'
  p_reason TEXT,
  p_user_id UUID,
  p_items JSONB          -- [{product_id, actual_qty, unit_cost?, notes?}]
) RETURNS UUID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_adjustment_id UUID;
  v_item JSONB;
  v_product_id UUID;
  v_actual_qty NUMERIC;
  v_unit_cost NUMERIC;
  v_notes TEXT;
  v_system_qty NUMERIC;
  v_wac NUMERIC;
BEGIN
  -- التحقق أن المستخدم مدير المخزن
  IF NOT EXISTS (
    SELECT 1 FROM warehouse_managers
    WHERE warehouse_id = p_warehouse_id AND profile_id = p_user_id
  ) AND NOT EXISTS (
    SELECT 1 FROM warehouses
    WHERE id = p_warehouse_id AND manager_id = p_user_id
  ) THEN
    RAISE EXCEPTION 'ليس لديك صلاحية إنشاء تسوية في هذا المخزن';
  END IF;

  -- التحقق من وجود بنود
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'يجب إضافة بند واحد على الأقل';
  END IF;

  -- إنشاء التسوية
  INSERT INTO stock_adjustments (
    warehouse_id, type, reason, created_by, status
  ) VALUES (
    p_warehouse_id, p_type, p_reason, p_user_id, 'pending'
  ) RETURNING id INTO v_adjustment_id;

  -- إدراج البنود مع system_qty لحظي من stock
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_product_id := (v_item ->> 'product_id')::UUID;
    v_actual_qty := (v_item ->> 'actual_qty')::NUMERIC;
    v_unit_cost  := COALESCE((v_item ->> 'unit_cost')::NUMERIC, 0);
    v_notes      := v_item ->> 'notes';

    -- قراءة الكمية الفعلية والـ WAC من المخزون لحظياً
    SELECT COALESCE(s.quantity, 0), COALESCE(s.wac, 0)
    INTO v_system_qty, v_wac
    FROM stock s
    WHERE s.warehouse_id = p_warehouse_id AND s.product_id = v_product_id;

    -- إذا لم يوجد صف مخزون → الكمية = 0
    IF NOT FOUND THEN
      v_system_qty := 0;
      v_wac := 0;
    END IF;

    -- استخدام WAC كتكلفة وحدة افتراضية إذا لم تُحدد
    IF v_unit_cost = 0 THEN
      v_unit_cost := v_wac;
    END IF;

    INSERT INTO stock_adjustment_items (
      adjustment_id, product_id, system_qty, actual_qty, unit_cost, notes
    ) VALUES (
      v_adjustment_id, v_product_id, v_system_qty, v_actual_qty, v_unit_cost, v_notes
    );
  END LOOP;

  RETURN v_adjustment_id;
END; $$;


-- ────────────────────────────────────────────────────────────
-- 2. confirm_adjustment — اعتماد التسوية (إعادة كتابة)
--    يعيد حساب system_qty لحظياً + يحمي المحجوز
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION confirm_adjustment(
  p_adjustment_id UUID,
  p_user_id UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_adj stock_adjustments%ROWTYPE;
  v_item RECORD;
  v_current_qty NUMERIC;
  v_available NUMERIC;
  v_wac NUMERIC;
  v_diff NUMERIC;
BEGIN
  -- قفل التسوية
  SELECT * INTO v_adj
  FROM stock_adjustments
  WHERE id = p_adjustment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'التسوية غير موجودة';
  END IF;

  IF v_adj.status NOT IN ('pending', 'draft') THEN
    RAISE EXCEPTION 'التسوية ليست في حالة قابلة للاعتماد (الحالة: %)', v_adj.status;
  END IF;

  -- التحقق أن المستخدم مدير المخزن
  IF NOT EXISTS (
    SELECT 1 FROM warehouse_managers
    WHERE warehouse_id = v_adj.warehouse_id AND profile_id = p_user_id
  ) AND NOT EXISTS (
    SELECT 1 FROM warehouses
    WHERE id = v_adj.warehouse_id AND manager_id = p_user_id
  ) THEN
    RAISE EXCEPTION 'ليس لديك صلاحية اعتماد تسوية في هذا المخزن';
  END IF;

  -- لكل بند: إعادة حساب الفرق مع المخزون الحالي
  FOR v_item IN
    SELECT * FROM stock_adjustment_items WHERE adjustment_id = p_adjustment_id
  LOOP
    -- قراءة المخزون الفعلي الآن (مع قفل الصف)
    SELECT COALESCE(s.quantity, 0), COALESCE(s.available_quantity, 0), COALESCE(s.wac, 0)
    INTO v_current_qty, v_available, v_wac
    FROM stock s
    WHERE s.warehouse_id = v_adj.warehouse_id AND s.product_id = v_item.product_id
    FOR UPDATE;

    -- إذا لم يوجد صف مخزون
    IF NOT FOUND THEN
      v_current_qty := 0;
      v_available := 0;
      v_wac := 0;
    END IF;

    -- تحديث system_qty في البند ليعكس القيمة الحقيقية لحظة الاعتماد
    -- (difference يُعاد حسابه تلقائياً لأنه GENERATED ALWAYS AS)
    UPDATE stock_adjustment_items
    SET system_qty = v_current_qty
    WHERE id = v_item.id;

    -- حساب الفرق الحقيقي
    v_diff := v_item.actual_qty - v_current_qty;

    IF v_diff > 0 THEN
      -- فرق موجب: إضافة مخزون
      PERFORM update_stock_wac(
        v_adj.warehouse_id,
        v_item.product_id,
        v_diff,
        COALESCE(v_item.unit_cost, v_wac, 0),
        'adjustment_add',
        'adjustment',
        p_adjustment_id,
        p_user_id
      );
    ELSIF v_diff < 0 THEN
      -- فرق سالب: التحقق أن الخصم لا يتعدى الكمية المتاحة (حماية المحجوز)
      IF ABS(v_diff) > v_available THEN
        RAISE EXCEPTION 'لا يمكن خصم % من المنتج — المتاح فقط % (باقي الكمية محجوزة لتحويلات)',
          ABS(v_diff), v_available;
      END IF;

      -- خصم المخزون
      PERFORM deduct_stock_at_wac(
        v_adj.warehouse_id,
        v_item.product_id,
        ABS(v_diff),
        'adjustment_remove',
        'adjustment',
        p_adjustment_id,
        p_user_id
      );
    END IF;
    -- إذا diff = 0 → لا شيء
  END LOOP;

  -- تحديث الحالة
  UPDATE stock_adjustments
  SET status = 'approved',
      approved_by = p_user_id,
      updated_at = now()
  WHERE id = p_adjustment_id;
END; $$;


-- ────────────────────────────────────────────────────────────
-- 3. reject_adjustment — رفض التسوية (إعادة كتابة)
--    يضيف فحص صلاحية + سبب الرفض
-- ────────────────────────────────────────────────────────────

-- إسقاط النسخة القديمة (2 معاملات) قبل إنشاء النسخة الجديدة (3 معاملات)
-- PostgreSQL يعتبرهما دالتين مختلفتين بسبب اختلاف عدد المعاملات
DROP FUNCTION IF EXISTS reject_adjustment(UUID, UUID);

CREATE OR REPLACE FUNCTION reject_adjustment(
  p_adjustment_id UUID,
  p_user_id UUID,
  p_reason TEXT DEFAULT NULL
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_adj stock_adjustments%ROWTYPE;
BEGIN
  -- قفل التسوية
  SELECT * INTO v_adj
  FROM stock_adjustments
  WHERE id = p_adjustment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'التسوية غير موجودة';
  END IF;

  IF v_adj.status NOT IN ('pending', 'draft') THEN
    RAISE EXCEPTION 'التسوية ليست في حالة قابلة للرفض (الحالة: %)', v_adj.status;
  END IF;

  -- التحقق أن المستخدم مدير المخزن
  IF NOT EXISTS (
    SELECT 1 FROM warehouse_managers
    WHERE warehouse_id = v_adj.warehouse_id AND profile_id = p_user_id
  ) AND NOT EXISTS (
    SELECT 1 FROM warehouses
    WHERE id = v_adj.warehouse_id AND manager_id = p_user_id
  ) THEN
    RAISE EXCEPTION 'ليس لديك صلاحية رفض تسوية في هذا المخزن';
  END IF;

  UPDATE stock_adjustments
  SET status = 'rejected',
      approved_by = p_user_id,
      rejection_reason = p_reason,
      updated_at = now()
  WHERE id = p_adjustment_id;
END; $$;


-- ────────────────────────────────────────────────────────────
-- 4. create_transfer_with_reservation — منع المنتجات المكررة
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION create_transfer_with_reservation(
  p_from_warehouse_id UUID,
  p_to_warehouse_id UUID,
  p_direction TEXT,
  p_notes TEXT,
  p_user_id UUID,
  p_items JSONB  -- [{product_id, unit_id, quantity}]
) RETURNS UUID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_transfer_id UUID;
  v_item JSONB;
  v_product_id UUID;
  v_unit_id UUID;
  v_qty NUMERIC;
  v_base_qty NUMERIC;
BEGIN
  -- التحقق من المخازن مختلفة
  IF p_from_warehouse_id = p_to_warehouse_id THEN
    RAISE EXCEPTION 'لا يمكن التحويل من وإلى نفس المخزن';
  END IF;

  -- فحص المنتجات المكررة
  IF (SELECT count(*) != count(DISTINCT val ->> 'product_id')
      FROM jsonb_array_elements(p_items) val) THEN
    RAISE EXCEPTION 'لا يمكن تكرار نفس المنتج في بنود التحويل';
  END IF;

  -- التحقق أن المستخدم مرتبط بالمخزن المناسب
  IF p_direction = 'push' THEN
    IF NOT EXISTS (
      SELECT 1 FROM warehouse_managers
      WHERE warehouse_id = p_from_warehouse_id AND profile_id = p_user_id
    ) AND NOT EXISTS (
      SELECT 1 FROM warehouses
      WHERE id = p_from_warehouse_id AND manager_id = p_user_id
    ) THEN
      RAISE EXCEPTION 'ليس لديك صلاحية على المخزن المُرسل';
    END IF;
  ELSIF p_direction = 'pull' THEN
    IF NOT EXISTS (
      SELECT 1 FROM warehouse_managers
      WHERE warehouse_id = p_to_warehouse_id AND profile_id = p_user_id
    ) AND NOT EXISTS (
      SELECT 1 FROM warehouses
      WHERE id = p_to_warehouse_id AND manager_id = p_user_id
    ) THEN
      RAISE EXCEPTION 'ليس لديك صلاحية على المخزن المُستلم';
    END IF;
  END IF;

  -- إنشاء التحويل
  INSERT INTO stock_transfers (
    from_warehouse_id, to_warehouse_id, direction,
    requested_by, notes, status
  ) VALUES (
    p_from_warehouse_id, p_to_warehouse_id, p_direction,
    p_user_id, p_notes, 'pending'
  ) RETURNING id INTO v_transfer_id;

  -- إدراج البنود + حجز (Push فقط)
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_product_id := (v_item ->> 'product_id')::UUID;
    v_unit_id    := (v_item ->> 'unit_id')::UUID;
    v_qty        := (v_item ->> 'quantity')::NUMERIC;

    IF v_qty <= 0 THEN
      RAISE EXCEPTION 'الكمية يجب أن تكون أكبر من صفر';
    END IF;

    -- تحويل الكمية للوحدة الأساسية
    v_base_qty := get_base_quantity(v_product_id, v_unit_id, v_qty);

    INSERT INTO stock_transfer_items (transfer_id, product_id, unit_id, quantity)
    VALUES (v_transfer_id, v_product_id, v_unit_id, v_base_qty);

    -- حجز فوري للـ Push
    IF p_direction = 'push' THEN
      PERFORM reserve_stock(p_from_warehouse_id, v_product_id, v_base_qty);
    END IF;
  END LOOP;

  RETURN v_transfer_id;
END; $$;


-- ────────────────────────────────────────────────────────────
-- 5. cancel_transfer — تسجيل المُلغي والوقت
--    نفس المنطق من 02d مع إضافة cancelled_by + cancelled_at
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION cancel_transfer(
  p_transfer_id UUID,
  p_user_id UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_transfer stock_transfers%ROWTYPE;
  v_item RECORD;
BEGIN
  SELECT * INTO v_transfer
  FROM stock_transfers
  WHERE id = p_transfer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'التحويل غير موجود';
  END IF;

  -- لا يمكن الإلغاء بعد الاستلام
  IF v_transfer.status = 'received' THEN
    RAISE EXCEPTION 'لا يمكن إلغاء تحويل تم استلامه';
  END IF;

  IF v_transfer.status = 'cancelled' THEN
    RAISE EXCEPTION 'التحويل ملغي بالفعل';
  END IF;

  -- التحقق من صلاحية الإلغاء
  IF v_transfer.direction = 'push' THEN
    IF NOT EXISTS (
      SELECT 1 FROM warehouse_managers
      WHERE warehouse_id = v_transfer.from_warehouse_id AND profile_id = p_user_id
    ) AND NOT EXISTS (
      SELECT 1 FROM warehouses
      WHERE id = v_transfer.from_warehouse_id AND manager_id = p_user_id
    ) THEN
      RAISE EXCEPTION 'ليس لديك صلاحية إلغاء هذا التحويل';
    END IF;
  ELSIF v_transfer.direction = 'pull' THEN
    IF v_transfer.status = 'pending' THEN
      IF v_transfer.requested_by != p_user_id
         AND NOT EXISTS (
           SELECT 1 FROM warehouse_managers
           WHERE warehouse_id = v_transfer.from_warehouse_id AND profile_id = p_user_id
         ) AND NOT EXISTS (
           SELECT 1 FROM warehouses
           WHERE id = v_transfer.from_warehouse_id AND manager_id = p_user_id
         ) THEN
        RAISE EXCEPTION 'ليس لديك صلاحية إلغاء هذا الطلب';
      END IF;
    ELSIF v_transfer.status = 'in_transit' THEN
      IF NOT EXISTS (
        SELECT 1 FROM warehouse_managers
        WHERE warehouse_id = v_transfer.from_warehouse_id AND profile_id = p_user_id
      ) AND NOT EXISTS (
        SELECT 1 FROM warehouses
        WHERE id = v_transfer.from_warehouse_id AND manager_id = p_user_id
      ) THEN
        RAISE EXCEPTION 'ليس لديك صلاحية إلغاء تحويل قيد الشحن';
      END IF;
    END IF;
  END IF;

  -- إلغاء الحجز
  IF NOT (v_transfer.direction = 'pull' AND v_transfer.status = 'pending') THEN
    FOR v_item IN
      SELECT * FROM stock_transfer_items WHERE transfer_id = p_transfer_id
    LOOP
      PERFORM unreserve_stock(
        v_transfer.from_warehouse_id, v_item.product_id, v_item.quantity
      );
    END LOOP;
  END IF;

  -- تحديث الحالة مع تسجيل المُلغي والوقت
  UPDATE stock_transfers
  SET status = 'cancelled',
      cancelled_by = p_user_id,
      cancelled_at = now(),
      updated_at = now()
  WHERE id = p_transfer_id;
END; $$;


-- ────────────────────────────────────────────────────────────
-- 6. GRANT — صلاحيات التنفيذ
-- ────────────────────────────────────────────────────────────

GRANT EXECUTE ON FUNCTION create_adjustment_with_items(UUID, TEXT, TEXT, UUID, JSONB) TO authenticated;
-- reject_adjustment الآن بـ 3 parameters (p_reason مع default)
-- لكن GRANT يحتاج التوقيع الجديد
GRANT EXECUTE ON FUNCTION reject_adjustment(UUID, UUID, TEXT) TO authenticated;
