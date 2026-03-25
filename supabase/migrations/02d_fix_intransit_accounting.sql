-- ============================================================
-- 02d_fix_intransit_accounting.sql
-- EDARA v2 — إصلاح فجوة البضائع أثناء النقل (IAS 2)
--
-- المبدأ: البضاعة تبقى محجوزة (reserved) في المخزن المصدر
-- أثناء النقل. عند الاستلام يتم خصم + إضافة بشكل ذري.
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- 5. confirm_transfer_shipment — تأكيد الشحن (Push)
--    الآن: لا يخصم المخزون — يترك الحجز كما هو ويسجل WAC فقط
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

  -- لكل بند: تسجيل WAC الحالي في البند (للاستخدام عند الاستلام)
  -- لا نخصم ولا نلغي الحجز — البضاعة تبقى محجوزة أثناء النقل
  FOR v_item IN
    SELECT * FROM stock_transfer_items WHERE transfer_id = p_transfer_id
  LOOP
    -- قراءة WAC الحالي
    SELECT wac INTO v_wac
    FROM stock
    WHERE warehouse_id = v_transfer.from_warehouse_id
      AND product_id = v_item.product_id
    FOR UPDATE;

    -- تسجيل unit_cost في البند
    UPDATE stock_transfer_items
    SET unit_cost = COALESCE(v_wac, 0)
    WHERE id = v_item.id;
  END LOOP;

  -- تحديث حالة التحويل — البضاعة مازالت محجوزة في المصدر
  UPDATE stock_transfers
  SET status = 'in_transit',
      sent_by = p_user_id,
      sent_at = now(),
      updated_at = now()
  WHERE id = p_transfer_id;
END; $$;


-- ────────────────────────────────────────────────────────────
-- 6. approve_and_ship_transfer — موافقة وشحن (Pull)
--    الآن: يحجز الكمية بدلاً من خصمها مباشرة
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

  -- لكل بند: حجز الكمية + تسجيل WAC
  FOR v_item IN
    SELECT * FROM stock_transfer_items WHERE transfer_id = p_transfer_id
  LOOP
    -- reserve_stock يتحقق من الكمية المتاحة ويفعل FOR UPDATE
    PERFORM reserve_stock(
      v_transfer.from_warehouse_id, v_item.product_id, v_item.quantity
    );

    -- قراءة WAC بعد الحجز
    SELECT wac INTO v_wac
    FROM stock
    WHERE warehouse_id = v_transfer.from_warehouse_id
      AND product_id = v_item.product_id;

    -- تسجيل WAC في البند
    UPDATE stock_transfer_items
    SET unit_cost = COALESCE(v_wac, 0)
    WHERE id = v_item.id;
  END LOOP;

  -- تحديث الحالة: موافقة + شحن معاً — البضاعة محجوزة في المصدر
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
--    الآن: إلغاء حجز + خصم من المصدر + إضافة للمستلم (ذري)
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

  -- لكل بند: إلغاء حجز + خصم من المصدر + إضافة للمستلم
  FOR v_item IN
    SELECT * FROM stock_transfer_items WHERE transfer_id = p_transfer_id
  LOOP
    -- 1. إلغاء الحجز من المخزن المصدر (يعمل FOR UPDATE على stock)
    PERFORM unreserve_stock(
      v_transfer.from_warehouse_id, v_item.product_id, v_item.quantity
    );

    -- 2. خصم فعلي من المخزن المصدر + تسجيل حركة خروج
    PERFORM deduct_stock_at_wac(
      v_transfer.from_warehouse_id,
      v_item.product_id,
      v_item.quantity,
      'transfer_out',
      'transfer',
      p_transfer_id,
      p_user_id
    );

    -- 3. تسجيل الكمية المستلمة
    UPDATE stock_transfer_items
    SET received_quantity = quantity
    WHERE id = v_item.id;

    -- 4. إضافة المخزون في المخزن المستلم + تسجيل حركة دخول
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
--    الآن: يدعم الإلغاء من حالة pending و in_transit
--    كلتا الحالتين تحتاج إلغاء حجز
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
    -- Pull pending: المُنشئ أو مدير المصدر
    -- Pull in_transit: مدير المصدر فقط (لأنه من وافق)
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
      -- in_transit: مدير المصدر فقط (لأنه من وافق والبضاعة محجوزة عنده)
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

  -- إلغاء الحجز — مطلوب في حالتي pending و in_transit
  -- Push pending: حجز موجود من الإنشاء
  -- Push in_transit: حجز موجود ولم يُخصم بعد (التصميم الجديد)
  -- Pull in_transit: حجز موجود من الموافقة
  -- Pull pending: لا حجز (لم تتم الموافقة بعد)
  IF NOT (v_transfer.direction = 'pull' AND v_transfer.status = 'pending') THEN
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
