-- ============================================================
-- 02c_inventory_functions.sql
-- EDARA v2 — دوال ذرية لنظام المخازن
-- التحويلات اللامركزية + التسويات + الحجز
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 0. تعديلات Schema
-- ────────────────────────────────────────────────────────────

ALTER TABLE stock_transfers
  ADD COLUMN IF NOT EXISTS direction TEXT DEFAULT 'push'
    CHECK (direction IN ('push','pull')),
  ADD COLUMN IF NOT EXISTS sent_by UUID REFERENCES profiles(id),
  ADD COLUMN IF NOT EXISTS sent_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS received_at TIMESTAMPTZ;

-- حقل unit_cost في transfer_items لتسجيل تكلفة الوحدة لحظة الشحن
-- (موجود فعلاً ولكن نتأكد من وجوده)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'stock_transfer_items' AND column_name = 'unit_cost'
  ) THEN
    ALTER TABLE stock_transfer_items ADD COLUMN unit_cost NUMERIC(14,4) DEFAULT 0;
  END IF;
END $$;


-- ────────────────────────────────────────────────────────────
-- 1. get_available_stock — الكمية المتاحة (بعد خصم المحجوز)
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_available_stock(
  p_warehouse_id UUID,
  p_product_id UUID
) RETURNS NUMERIC
  LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_available NUMERIC;
BEGIN
  SELECT available_quantity INTO v_available
  FROM stock
  WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id;

  RETURN COALESCE(v_available, 0);
END; $$;


-- ────────────────────────────────────────────────────────────
-- 2. reserve_stock — حجز كمية (زيادة reserved_quantity)
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION reserve_stock(
  p_warehouse_id UUID,
  p_product_id UUID,
  p_qty NUMERIC
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_stock stock%ROWTYPE;
BEGIN
  SELECT * INTO v_stock
  FROM stock
  WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'لا يوجد مخزون لهذا المنتج (%) في هذا المخزن (%)',
      p_product_id, p_warehouse_id;
  END IF;

  IF v_stock.available_quantity < p_qty THEN
    RAISE EXCEPTION 'الكمية المتاحة غير كافية (متاح: %, مطلوب: %)',
      v_stock.available_quantity, p_qty;
  END IF;

  UPDATE stock
  SET reserved_quantity = reserved_quantity + p_qty,
      updated_at = now()
  WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id;
END; $$;


-- ────────────────────────────────────────────────────────────
-- 3. unreserve_stock — إلغاء حجز كمية
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION unreserve_stock(
  p_warehouse_id UUID,
  p_product_id UUID,
  p_qty NUMERIC
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
BEGIN
  -- FOR UPDATE لمنع race condition
  PERFORM 1 FROM stock
  WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id
  FOR UPDATE;

  UPDATE stock
  SET reserved_quantity = GREATEST(reserved_quantity - p_qty, 0),
      updated_at = now()
  WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id;
END; $$;


-- ────────────────────────────────────────────────────────────
-- 4. create_transfer_with_reservation — إنشاء تحويل مع حجز
--    يُستخدم فقط لـ Push (المُرسل هو المُنشئ)
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
-- 5. confirm_transfer_shipment — تأكيد الشحن (Push)
--    يُخصم المخزون ويُلغي الحجز
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION confirm_transfer_shipment(
  p_transfer_id UUID,
  p_user_id UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_transfer stock_transfers%ROWTYPE;
  v_item RECORD;
  v_wac NUMERIC;
BEGIN
  -- قفل التحويل
  SELECT * INTO v_transfer
  FROM stock_transfers
  WHERE id = p_transfer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'التحويل غير موجود';
  END IF;

  -- Push فقط: الحالة يجب أن تكون pending
  IF v_transfer.direction != 'push' THEN
    RAISE EXCEPTION 'هذه الدالة للتحويلات من نوع إرسال (push) فقط';
  END IF;

  IF v_transfer.status != 'pending' THEN
    RAISE EXCEPTION 'التحويل ليس في حالة معلق (الحالة الحالية: %)', v_transfer.status;
  END IF;

  -- التحقق أن المستخدم مدير المخزن المُرسل
  IF NOT EXISTS (
    SELECT 1 FROM warehouse_managers
    WHERE warehouse_id = v_transfer.from_warehouse_id AND profile_id = p_user_id
  ) AND NOT EXISTS (
    SELECT 1 FROM warehouses
    WHERE id = v_transfer.from_warehouse_id AND manager_id = p_user_id
  ) THEN
    RAISE EXCEPTION 'ليس لديك صلاحية شحن من هذا المخزن';
  END IF;

  -- لكل بند: إلغاء الحجز + خصم فعلي
  FOR v_item IN
    SELECT * FROM stock_transfer_items WHERE transfer_id = p_transfer_id
  LOOP
    -- إلغاء الحجز أولاً (يتضمن FOR UPDATE على stock)
    PERFORM unreserve_stock(
      v_transfer.from_warehouse_id, v_item.product_id, v_item.quantity
    );

    -- قراءة WAC بعد فك الحجز (stock مقفول بالفعل)
    SELECT wac INTO v_wac
    FROM stock
    WHERE warehouse_id = v_transfer.from_warehouse_id
      AND product_id = v_item.product_id;

    -- تسجيل unit_cost في البند
    UPDATE stock_transfer_items
    SET unit_cost = COALESCE(v_wac, 0)
    WHERE id = v_item.id;

    -- خصم فعلي مع تسجيل حركة (deduct_stock_at_wac يعمل FOR UPDATE أيضاً)
    PERFORM deduct_stock_at_wac(
      v_transfer.from_warehouse_id,
      v_item.product_id,
      v_item.quantity,
      'transfer_out',
      'transfer',
      p_transfer_id,
      p_user_id
    );
  END LOOP;

  -- تحديث حالة التحويل
  UPDATE stock_transfers
  SET status = 'in_transit',
      sent_by = p_user_id,
      sent_at = now(),
      updated_at = now()
  WHERE id = p_transfer_id;
END; $$;


-- ────────────────────────────────────────────────────────────
-- 6. approve_and_ship_transfer — موافقة وشحن (Pull)
--    فحص التوفر + خصم فوري (لا حجز مسبق)
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION approve_and_ship_transfer(
  p_transfer_id UUID,
  p_user_id UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_transfer stock_transfers%ROWTYPE;
  v_item RECORD;
  v_available NUMERIC;
  v_wac NUMERIC;
BEGIN
  -- قفل التحويل
  SELECT * INTO v_transfer
  FROM stock_transfers
  WHERE id = p_transfer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'التحويل غير موجود';
  END IF;

  IF v_transfer.direction != 'pull' THEN
    RAISE EXCEPTION 'هذه الدالة لطلبات التحويل (pull) فقط';
  END IF;

  IF v_transfer.status != 'pending' THEN
    RAISE EXCEPTION 'الطلب ليس في حالة معلق (الحالة الحالية: %)', v_transfer.status;
  END IF;

  -- التحقق أن المستخدم مدير المخزن المُرسل
  IF NOT EXISTS (
    SELECT 1 FROM warehouse_managers
    WHERE warehouse_id = v_transfer.from_warehouse_id AND profile_id = p_user_id
  ) AND NOT EXISTS (
    SELECT 1 FROM warehouses
    WHERE id = v_transfer.from_warehouse_id AND manager_id = p_user_id
  ) THEN
    RAISE EXCEPTION 'ليس لديك صلاحية الموافقة من هذا المخزن';
  END IF;

  -- لكل بند: فحص التوفر وخصم فوري
  FOR v_item IN
    SELECT * FROM stock_transfer_items WHERE transfer_id = p_transfer_id
  LOOP
    -- قفل صف المخزون + فحص الكمية المتاحة بعد القفل
    SELECT available_quantity, wac INTO v_available, v_wac
    FROM stock
    WHERE warehouse_id = v_transfer.from_warehouse_id
      AND product_id = v_item.product_id
    FOR UPDATE;

    IF v_available IS NULL OR v_available < v_item.quantity THEN
      RAISE EXCEPTION 'الكمية المتاحة غير كافية للمنتج (متاح: %, مطلوب: %)',
        COALESCE(v_available, 0), v_item.quantity;
    END IF;

    -- تسجيل WAC في البند
    UPDATE stock_transfer_items
    SET unit_cost = COALESCE(v_wac, 0)
    WHERE id = v_item.id;

    -- خصم فعلي مع تسجيل حركة (deduct_stock_at_wac يعمل FOR UPDATE أيضاً)
    PERFORM deduct_stock_at_wac(
      v_transfer.from_warehouse_id,
      v_item.product_id,
      v_item.quantity,
      'transfer_out',
      'transfer',
      p_transfer_id,
      p_user_id
    );
  END LOOP;

  -- تحديث الحالة: موافقة + شحن معاً
  UPDATE stock_transfers
  SET status = 'in_transit',
      approved_by = p_user_id,
      sent_by = p_user_id,
      sent_at = now(),
      updated_at = now()
  WHERE id = p_transfer_id;
END; $$;


-- ────────────────────────────────────────────────────────────
-- 7. confirm_transfer_receipt — تأكيد الاستلام
--    إضافة المخزون بالـ WAC المسجّل عند الشحن
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION confirm_transfer_receipt(
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
  -- قفل التحويل
  SELECT * INTO v_transfer
  FROM stock_transfers
  WHERE id = p_transfer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'التحويل غير موجود';
  END IF;

  IF v_transfer.status != 'in_transit' THEN
    RAISE EXCEPTION 'التحويل ليس في حالة قيد الشحن (الحالة الحالية: %)', v_transfer.status;
  END IF;

  -- التحقق أن المستخدم مدير المخزن المُستلم
  IF NOT EXISTS (
    SELECT 1 FROM warehouse_managers
    WHERE warehouse_id = v_transfer.to_warehouse_id AND profile_id = p_user_id
  ) AND NOT EXISTS (
    SELECT 1 FROM warehouses
    WHERE id = v_transfer.to_warehouse_id AND manager_id = p_user_id
  ) THEN
    RAISE EXCEPTION 'ليس لديك صلاحية الاستلام في هذا المخزن';
  END IF;

  -- لكل بند: إضافة المخزون + تسجيل الكمية المستلمة
  FOR v_item IN
    SELECT * FROM stock_transfer_items WHERE transfer_id = p_transfer_id
  LOOP
    -- received_quantity = quantity (ثابت، لا تعديل)
    UPDATE stock_transfer_items
    SET received_quantity = quantity
    WHERE id = v_item.id;

    -- إضافة المخزون بالـ WAC المسجّل عند الشحن
    PERFORM update_stock_wac(
      v_transfer.to_warehouse_id,
      v_item.product_id,
      v_item.quantity,
      COALESCE(v_item.unit_cost, 0),
      'transfer_in',
      'transfer',
      p_transfer_id,
      p_user_id
    );
  END LOOP;

  -- تحديث الحالة
  UPDATE stock_transfers
  SET status = 'received',
      received_by = p_user_id,
      received_at = now(),
      updated_at = now()
  WHERE id = p_transfer_id;
END; $$;


-- ────────────────────────────────────────────────────────────
-- 8. cancel_transfer — إلغاء التحويل
--    يُلغي الحجز إن وُجد (Push + pending فقط)
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

  -- لا يمكن الإلغاء بعد الشحن أو الاستلام
  IF v_transfer.status IN ('in_transit', 'received') THEN
    RAISE EXCEPTION 'لا يمكن إلغاء تحويل تم شحنه أو استلامه';
  END IF;

  IF v_transfer.status = 'cancelled' THEN
    RAISE EXCEPTION 'التحويل ملغي بالفعل';
  END IF;

  -- التحقق من صلاحية الإلغاء
  IF v_transfer.direction = 'push' THEN
    -- Push: المُرسل فقط يمكنه الإلغاء
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
    -- Pull: المُنشئ (الطالب) أو مدير المخزن المُرسل يمكنهم الإلغاء
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
  END IF;

  -- إلغاء الحجز (Push + pending فقط — هنا الحجز موجود)
  IF v_transfer.direction = 'push' AND v_transfer.status = 'pending' THEN
    FOR v_item IN
      SELECT * FROM stock_transfer_items WHERE transfer_id = p_transfer_id
    LOOP
      PERFORM unreserve_stock(
        v_transfer.from_warehouse_id, v_item.product_id, v_item.quantity
      );
    END LOOP;
  END IF;

  -- تحديث الحالة
  UPDATE stock_transfers
  SET status = 'cancelled',
      updated_at = now()
  WHERE id = p_transfer_id;
END; $$;


-- ────────────────────────────────────────────────────────────
-- 9. confirm_adjustment — اعتماد التسوية وتطبيق الفروق
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

  -- التحقق أن المستخدم مدير المخزن أو له صلاحية
  IF NOT EXISTS (
    SELECT 1 FROM warehouse_managers
    WHERE warehouse_id = v_adj.warehouse_id AND profile_id = p_user_id
  ) AND NOT EXISTS (
    SELECT 1 FROM warehouses
    WHERE id = v_adj.warehouse_id AND manager_id = p_user_id
  ) THEN
    RAISE EXCEPTION 'ليس لديك صلاحية اعتماد تسوية في هذا المخزن';
  END IF;

  -- لكل بند: تطبيق الفرق على المخزون
  FOR v_item IN
    SELECT * FROM stock_adjustment_items WHERE adjustment_id = p_adjustment_id
  LOOP
    v_diff := v_item.actual_qty - v_item.system_qty;

    IF v_diff > 0 THEN
      -- فرق موجب: إضافة مخزون
      PERFORM update_stock_wac(
        v_adj.warehouse_id,
        v_item.product_id,
        v_diff,
        COALESCE(v_item.unit_cost, 0),
        'adjustment_add',
        'adjustment',
        p_adjustment_id,
        p_user_id
      );
    ELSIF v_diff < 0 THEN
      -- فرق سالب: خصم مخزون
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
-- 10. reject_adjustment — رفض التسوية (بدون تطبيق)
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION reject_adjustment(
  p_adjustment_id UUID,
  p_user_id UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
BEGIN
  UPDATE stock_adjustments
  SET status = 'rejected',
      approved_by = p_user_id,
      updated_at = now()
  WHERE id = p_adjustment_id
    AND status IN ('pending', 'draft');

  IF NOT FOUND THEN
    RAISE EXCEPTION 'التسوية غير موجودة أو ليست في حالة قابلة للرفض';
  END IF;
END; $$;


-- ────────────────────────────────────────────────────────────
-- 11. RLS: منح صلاحيات التنفيذ للأدوار
-- ────────────────────────────────────────────────────────────

GRANT EXECUTE ON FUNCTION get_available_stock(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION reserve_stock(UUID, UUID, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION unreserve_stock(UUID, UUID, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION create_transfer_with_reservation(UUID, UUID, TEXT, TEXT, UUID, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION confirm_transfer_shipment(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION approve_and_ship_transfer(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION confirm_transfer_receipt(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION cancel_transfer(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION confirm_adjustment(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION reject_adjustment(UUID, UUID) TO authenticated;
