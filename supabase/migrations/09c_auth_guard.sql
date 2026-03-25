-- =========================================================================
-- 09c_auth_guard.sql
-- التحقق من هوية المستخدم في جميع دوال RPC لضمان عدم تمرير p_user_id مزيف
-- =========================================================================
-- Generated: 2026-03-25T20:16:31.203Z
-- Excluded sources: 09c_auth_guard.sql, 09d_atomic_fixes.sql (already contain guards)

-- Source: 01_foundation.sql -> Function: public.get_user_permissions
CREATE OR REPLACE FUNCTION public.get_user_permissions(p_user_id UUID)
RETURNS TABLE(permission TEXT) LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- Overrides (granted only)
  RETURN QUERY
    SELECT upo.permission FROM user_permission_overrides upo
    WHERE upo.user_id = p_user_id AND upo.granted = true
      AND (upo.expires_at IS NULL OR upo.expires_at > now());

  -- Role permissions (excluding revoked overrides)
  RETURN QUERY
    SELECT DISTINCT rp.permission FROM role_permissions rp
    JOIN user_roles ur ON ur.role_id = rp.role_id
    WHERE ur.user_id = p_user_id AND ur.is_active = true
      AND rp.permission NOT IN (
        SELECT upo2.permission FROM user_permission_overrides upo2
        WHERE upo2.user_id = p_user_id AND upo2.granted = false
          AND (upo2.expires_at IS NULL OR upo2.expires_at > now())
      );
END; $$;

-- Source: 02_master_data.sql -> Function: update_stock_wac
CREATE OR REPLACE FUNCTION update_stock_wac(
  p_warehouse_id UUID, p_product_id UUID,
  p_qty_in NUMERIC, p_unit_cost NUMERIC,
  p_movement_type TEXT, p_reference_type TEXT,
  p_reference_id UUID, p_user_id UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_stock stock%ROWTYPE;
  v_new_wac NUMERIC;
  v_new_qty NUMERIC;
  v_new_total NUMERIC;
BEGIN
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  SELECT * INTO v_stock
  FROM stock
  WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO stock (warehouse_id, product_id, quantity, reserved_quantity, wac, total_cost_value)
    VALUES (p_warehouse_id, p_product_id, p_qty_in, 0, p_unit_cost, p_qty_in * p_unit_cost);
    v_new_qty := p_qty_in;
    v_new_wac := p_unit_cost;
  ELSE
    v_new_qty   := v_stock.quantity + p_qty_in;
    v_new_total := v_stock.total_cost_value + (p_qty_in * p_unit_cost);
    v_new_wac   := CASE WHEN v_new_qty > 0 THEN v_new_total / v_new_qty ELSE 0 END;

    UPDATE stock
    SET quantity = v_new_qty, wac = v_new_wac, total_cost_value = v_new_total,
        updated_at = now()
    WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id;
  END IF;

  INSERT INTO stock_movements (
    warehouse_id, product_id, unit_id, quantity, type,
    unit_cost, wac_before, wac_after, before_qty, after_qty,
    reference_type, reference_id, created_by
  ) VALUES (
    p_warehouse_id, p_product_id,
    (SELECT base_unit_id FROM products WHERE id = p_product_id),
    p_qty_in, p_movement_type,
    p_unit_cost, COALESCE(v_stock.wac, p_unit_cost), v_new_wac,
    COALESCE(v_stock.quantity, 0), v_new_qty,
    p_reference_type, p_reference_id, p_user_id
  );
END; $$;

-- Source: 02g_audit_fixes.sql -> Function: deduct_stock_at_wac
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
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

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

-- Source: 02e_inventory_hardening.sql -> Function: create_transfer_with_reservation
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
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

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

-- Source: 02d_fix_intransit_accounting.sql -> Function: confirm_transfer_shipment
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
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

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

-- Source: 02d_fix_intransit_accounting.sql -> Function: approve_and_ship_transfer
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
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

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

-- Source: 02d_fix_intransit_accounting.sql -> Function: confirm_transfer_receipt
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
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

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

-- Source: 02e_inventory_hardening.sql -> Function: cancel_transfer
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
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

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

-- Source: 02e_inventory_hardening.sql -> Function: confirm_adjustment
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
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

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

-- Source: 02e_inventory_hardening.sql -> Function: reject_adjustment
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
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

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

-- Source: 02e_inventory_hardening.sql -> Function: create_adjustment_with_items
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
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

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

-- Source: 02f_hotfixes.sql -> Function: get_user_max_grade
CREATE OR REPLACE FUNCTION get_user_max_grade(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_grade INTEGER;
BEGIN
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  SELECT COALESCE(MAX(r.grade), 0) INTO v_grade
  FROM user_roles ur
  JOIN roles r ON r.id = ur.role_id
  WHERE ur.user_id = p_user_id;
  RETURN v_grade;
END;
$$;

-- Source: 03_financial_infrastructure.sql -> Function: add_vault_transaction
CREATE OR REPLACE FUNCTION add_vault_transaction(
  p_vault_id      UUID,
  p_type          TEXT,
  p_amount        NUMERIC,
  p_ref_type      TEXT,
  p_ref_id        UUID,
  p_description   TEXT,
  p_user_id       UUID
) RETURNS UUID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_vault        vaults%ROWTYPE;
  v_new_balance  NUMERIC;
  v_txn_id       UUID;
BEGIN
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- F6: فحص المبلغ
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
  END IF;

  -- 1. قفل صف الخزنة
  SELECT * INTO v_vault
  FROM vaults
  WHERE id = p_vault_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'الخزنة غير موجودة';
  END IF;

  IF NOT v_vault.is_active THEN
    RAISE EXCEPTION 'الخزنة معطلة';
  END IF;

  -- 2. حساب الرصيد الجديد حسب نوع العملية
  IF p_type IN ('deposit', 'transfer_in', 'collection', 'custody_return', 'opening_balance') THEN
    -- عمليات إيجابية (إيداع)
    v_new_balance := v_vault.current_balance + p_amount;
  ELSIF p_type IN ('withdrawal', 'transfer_out', 'expense', 'custody_load') THEN
    -- عمليات سلبية (سحب)
    IF v_vault.current_balance < p_amount THEN
      RAISE EXCEPTION 'رصيد الخزنة غير كافٍ (المتاح: %، المطلوب: %)', v_vault.current_balance, p_amount;
    END IF;
    v_new_balance := v_vault.current_balance - p_amount;
  ELSE
    RAISE EXCEPTION 'نوع حركة غير صالح: %', p_type;
  END IF;

  -- 3. إدراج الحركة
  INSERT INTO vault_transactions (
    vault_id, type, amount, balance_after,
    reference_type, reference_id, description, created_by
  ) VALUES (
    p_vault_id, p_type, p_amount, v_new_balance,
    p_ref_type, p_ref_id, p_description, p_user_id
  )
  RETURNING id INTO v_txn_id;

  -- 4. تحديث الرصيد المُخزَّن
  UPDATE vaults
  SET current_balance = v_new_balance
  WHERE id = p_vault_id;

  RETURN v_txn_id;
END; $$;

-- Source: 03_financial_infrastructure.sql -> Function: add_custody_transaction
CREATE OR REPLACE FUNCTION add_custody_transaction(
  p_custody_id    UUID,
  p_type          TEXT,
  p_amount        NUMERIC,
  p_vault_id      UUID,       -- مصدر/وجهة (NULL إذا لم يرتبط بخزنة)
  p_ref_type      TEXT,
  p_ref_id        UUID,
  p_description   TEXT,
  p_user_id       UUID
) RETURNS UUID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_custody      custody_accounts%ROWTYPE;
  v_new_balance  NUMERIC;
  v_txn_id       UUID;
BEGIN
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- F6: فحص المبلغ
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
  END IF;

  -- 1. قفل صف العهدة
  SELECT * INTO v_custody
  FROM custody_accounts
  WHERE id = p_custody_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'حساب العهدة غير موجود';
  END IF;

  IF NOT v_custody.is_active THEN
    RAISE EXCEPTION 'حساب العهدة معطل';
  END IF;

  -- 2. حساب الرصيد الجديد
  IF p_type IN ('load', 'collection') THEN
    -- عمليات إيجابية
    v_new_balance := v_custody.current_balance + p_amount;
    -- فحص الحد الأقصى
    IF v_new_balance > v_custody.max_balance THEN
      RAISE EXCEPTION 'تجاوز الحد الأقصى للعهدة (الحد: %، الرصيد بعد: %)', v_custody.max_balance, v_new_balance;
    END IF;
  ELSIF p_type IN ('expense', 'settlement', 'return') THEN
    -- عمليات سلبية
    IF v_custody.current_balance < p_amount THEN
      RAISE EXCEPTION 'رصيد العهدة غير كافٍ (المتاح: %، المطلوب: %)', v_custody.current_balance, p_amount;
    END IF;
    v_new_balance := v_custody.current_balance - p_amount;
  ELSE
    RAISE EXCEPTION 'نوع حركة عهدة غير صالح: %', p_type;
  END IF;

  -- 3. إدراج الحركة
  INSERT INTO custody_transactions (
    custody_id, type, amount, balance_after,
    vault_id, reference_type, reference_id, description, created_by
  ) VALUES (
    p_custody_id, p_type, p_amount, v_new_balance,
    p_vault_id, p_ref_type, p_ref_id, p_description, p_user_id
  )
  RETURNING id INTO v_txn_id;

  -- 4. تحديث الرصيد
  UPDATE custody_accounts
  SET current_balance = v_new_balance
  WHERE id = p_custody_id;

  RETURN v_txn_id;
END; $$;

-- Source: 03_financial_infrastructure.sql -> Function: load_custody_from_vault
CREATE OR REPLACE FUNCTION load_custody_from_vault(
  p_custody_id  UUID,
  p_vault_id    UUID,
  p_amount      NUMERIC,
  p_user_id     UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_employee_name TEXT;
BEGIN
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- S3: فحص الصلاحية
  IF NOT check_permission(p_user_id, 'finance.custody.transact') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تحميل العهدة';
  END IF;

  -- جلب اسم الموظف للوصف
  SELECT p.full_name INTO v_employee_name
  FROM custody_accounts ca
  JOIN profiles p ON p.id = ca.employee_id
  WHERE ca.id = p_custody_id;

  -- 1. سحب من الخزنة
  PERFORM add_vault_transaction(
    p_vault_id, 'custody_load', p_amount,
    'custody', p_custody_id,
    'تحميل عهدة — ' || COALESCE(v_employee_name, ''),
    p_user_id
  );

  -- 2. إضافة في العهدة
  PERFORM add_custody_transaction(
    p_custody_id, 'load', p_amount,
    p_vault_id, 'vault', p_vault_id,
    'تحميل من خزنة',
    p_user_id
  );

  -- S1: قيد محاسبي — DR: عُهد (1400) → CR: صندوق/بنك/محفظة
  PERFORM create_auto_journal_entry(
    'custody', p_custody_id,
    'تحميل عهدة — ' || COALESCE(v_employee_name, ''),
    '1400',                              -- عُهد
    CASE (SELECT type FROM vaults WHERE id = p_vault_id)
      WHEN 'cash' THEN '1110'
      WHEN 'bank' THEN '1120'
      WHEN 'mobile_wallet' THEN '1130'
      ELSE '1110'                          -- T2: fallback
    END,
    p_amount,
    p_user_id
  );
END; $$;

-- Source: 03_financial_infrastructure.sql -> Function: settle_custody_to_vault
CREATE OR REPLACE FUNCTION settle_custody_to_vault(
  p_custody_id  UUID,
  p_vault_id    UUID,
  p_amount      NUMERIC,
  p_type        TEXT,         -- 'settlement' أو 'return'
  p_user_id     UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_employee_name TEXT;
BEGIN
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- التحقق من نوع العملية
  IF p_type NOT IN ('settlement', 'return') THEN
    RAISE EXCEPTION 'نوع التسوية يجب أن يكون settlement أو return';
  END IF;

  -- S3: فحص الصلاحية
  IF NOT check_permission(p_user_id, 'finance.custody.transact') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تسوية العهدة';
  END IF;

  -- جلب اسم الموظف
  SELECT p.full_name INTO v_employee_name
  FROM custody_accounts ca
  JOIN profiles p ON p.id = ca.employee_id
  WHERE ca.id = p_custody_id;

  -- 1. سحب من العهدة
  PERFORM add_custody_transaction(
    p_custody_id, p_type, p_amount,
    p_vault_id, 'vault', p_vault_id,
    CASE p_type
      WHEN 'settlement' THEN 'تسوية عهدة'
      WHEN 'return' THEN 'إرجاع عهدة كامل'
    END,
    p_user_id
  );

  -- 2. إيداع في الخزنة
  PERFORM add_vault_transaction(
    p_vault_id, 'custody_return', p_amount,
    'custody', p_custody_id,
    'تسوية عهدة — ' || COALESCE(v_employee_name, ''),
    p_user_id
  );

  -- S2: قيد محاسبي — DR: صندوق/بنك → CR: عُهد (1400)
  PERFORM create_auto_journal_entry(
    'custody', p_custody_id,
    CASE p_type
      WHEN 'settlement' THEN 'تسوية عهدة — '
      WHEN 'return' THEN 'إرجاع عهدة — '
    END || COALESCE(v_employee_name, ''),
    CASE (SELECT type FROM vaults WHERE id = p_vault_id)
      WHEN 'cash' THEN '1110'
      WHEN 'bank' THEN '1120'
      WHEN 'mobile_wallet' THEN '1130'
      ELSE '1110'                          -- T2: fallback
    END,
    '1400',                              -- عُهد
    p_amount,
    p_user_id
  );
END; $$;

-- Source: 03_financial_infrastructure.sql -> Function: confirm_payment_receipt
CREATE OR REPLACE FUNCTION confirm_payment_receipt(
  p_receipt_id  UUID,
  p_action      TEXT,      -- 'confirm' أو 'reject'
  p_vault_id    UUID,      -- الخزنة (للتأكيد فقط، NULL للرفض)
  p_reason      TEXT,      -- سبب الرفض (للرفض فقط، NULL للتأكيد)
  p_user_id     UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_receipt  payment_receipts%ROWTYPE;
  v_cust_name TEXT;
BEGIN
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- S3: فحص الصلاحية
  IF NOT check_permission(p_user_id, 'finance.payments.confirm') THEN
    RAISE EXCEPTION 'لا تملك صلاحية مراجعة إيصالات الدفع';
  END IF;

  -- 1. قفل الإيصال
  SELECT * INTO v_receipt
  FROM payment_receipts
  WHERE id = p_receipt_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'إيصال الدفع غير موجود';
  END IF;

  IF v_receipt.status != 'pending' THEN
    RAISE EXCEPTION 'الإيصال ليس في حالة معلقة (الحالة: %)', v_receipt.status;
  END IF;

  IF p_action = 'confirm' THEN
    -- التحقق من وجود وجهة التحصيل (خزنة أو عهدة)
    IF p_vault_id IS NULL AND v_receipt.custody_id IS NULL THEN
      RAISE EXCEPTION 'يجب تحديد الخزنة أو العهدة للتأكيد';
    END IF;

    -- جلب اسم العميل للأوصاف
    SELECT name INTO v_cust_name FROM customers WHERE id = v_receipt.customer_id;

    -- 2a. إدراج حركة في دفتر العميل (credit = تقليل الدين)
    INSERT INTO customer_ledger (
      customer_id, type, amount, source_type, source_id,
      description, created_by
    ) VALUES (
      v_receipt.customer_id, 'credit', v_receipt.amount,
      'payment', p_receipt_id,
      'تحصيل ' || v_receipt.payment_method || ' — ' || COALESCE(v_receipt.bank_reference, v_receipt.check_number, ''),
      p_user_id
    );

    -- F7+F8: مساران — خزنة أو عهدة
    IF v_receipt.custody_id IS NOT NULL THEN
      -- مسار العهدة (تحصيل ميداني — المندوب)
      PERFORM add_custody_transaction(
        v_receipt.custody_id, 'collection', v_receipt.amount,
        NULL, 'payment_receipt', p_receipt_id,
        'تحصيل من ' || COALESCE(v_cust_name, ''),
        p_user_id
      );

      -- قيد محاسبي: DR: عهد (1400) → CR: ذمم مدينة (1200)
      PERFORM create_auto_journal_entry(
        'payment', p_receipt_id,
        'تحصيل ميداني من عميل — ' || COALESCE(v_cust_name, ''),
        '1400',                            -- عُهد
        '1200',                            -- ذمم مدينة
        v_receipt.amount,
        p_user_id
      );

      -- تحديث الإيصال
      UPDATE payment_receipts
      SET status = 'confirmed',
          custody_id = v_receipt.custody_id,
          reviewed_by = p_user_id,
          reviewed_at = now()
      WHERE id = p_receipt_id;

    ELSE
      -- مسار الخزنة (تحصيل مكتبي)
      PERFORM add_vault_transaction(
        p_vault_id, 'collection', v_receipt.amount,
        'payment_receipt', p_receipt_id,
        'تحصيل من ' || COALESCE(v_cust_name, ''),
        p_user_id
      );

      -- قيد محاسبي: DR: صندوق/بنك → CR: ذمم مدينة
      PERFORM create_auto_journal_entry(
        'payment', p_receipt_id,
        'تحصيل من عميل — ' || COALESCE(v_cust_name, ''),
        CASE (SELECT type FROM vaults WHERE id = p_vault_id)
          WHEN 'cash' THEN '1110'         -- صندوق
          WHEN 'bank' THEN '1120'         -- بنك
          WHEN 'mobile_wallet' THEN '1130' -- محفظة
          ELSE '1110'                     -- T2: fallback
        END,
        '1200',                            -- ذمم مدينة
        v_receipt.amount,
        p_user_id
      );

      -- تحديث الإيصال
      UPDATE payment_receipts
      SET status = 'confirmed',
          vault_id = p_vault_id,
          reviewed_by = p_user_id,
          reviewed_at = now()
      WHERE id = p_receipt_id;
    END IF;

  ELSIF p_action = 'reject' THEN
    -- رفض الإيصال
    UPDATE payment_receipts
    SET status = 'rejected',
        rejection_reason = p_reason,
        reviewed_by = p_user_id,
        reviewed_at = now()
    WHERE id = p_receipt_id;

  ELSE
    RAISE EXCEPTION 'الإجراء يجب أن يكون confirm أو reject';
  END IF;
END; $$;

-- Source: 03b_approval_fixes.sql -> Function: approve_expense
CREATE OR REPLACE FUNCTION approve_expense(
  p_expense_id  UUID,
  p_action      TEXT,      -- 'approve' أو 'reject'
  p_reason      TEXT,      -- سبب الرفض (NULL للموافقة)
  p_user_id     UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_expense      expenses%ROWTYPE;
  v_can_approve  BOOLEAN;
  v_is_superuser BOOLEAN;
  v_cat_name     TEXT;
BEGIN
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- S3: فحص الصلاحية الأساسية
  IF NOT check_permission(p_user_id, 'finance.expenses.approve') THEN
    RAISE EXCEPTION 'لا تملك صلاحية الموافقة على المصروفات';
  END IF;

  -- 1. قفل المصروف
  SELECT * INTO v_expense
  FROM expenses
  WHERE id = p_expense_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'المصروف غير موجود';
  END IF;

  IF v_expense.status != 'pending_approval' THEN
    RAISE EXCEPTION 'المصروف ليس في حالة انتظار الموافقة (الحالة: %)', v_expense.status;
  END IF;

  IF p_action = 'approve' THEN
    -- 2a. فحص: هل المستخدم يحمل صلاحية * (super_admin)؟
    --     إذا نعم → تجاوز فحص approval_rules بالكامل
    SELECT EXISTS (
      SELECT 1 FROM role_permissions rp
      JOIN user_roles ur ON ur.role_id = rp.role_id
      WHERE ur.user_id = p_user_id
        AND ur.is_active = true
        AND rp.permission = '*'
    ) INTO v_is_superuser;

    IF NOT v_is_superuser THEN
      -- 2b. فحص سلسلة الموافقات للمستخدمين العاديين
      SELECT EXISTS (
        SELECT 1 FROM approval_rules ar
        JOIN user_roles ur ON ur.role_id = ar.role_id
        WHERE ar.type = 'expense'
          AND ar.max_amount >= v_expense.amount
          AND ar.is_active = true
          AND ur.user_id = p_user_id
          AND ur.is_active = true
      ) INTO v_can_approve;

      IF NOT v_can_approve THEN
        RAISE EXCEPTION 'لا تملك صلاحية اعتماد مصروف بهذا المبلغ (الحد الأقصى المسموح لدورك أقل من %)', v_expense.amount;
      END IF;
    END IF;

    -- 3. خصم من المصدر
    IF v_expense.payment_source = 'vault' AND v_expense.vault_id IS NOT NULL THEN
      PERFORM add_vault_transaction(
        v_expense.vault_id, 'expense', v_expense.amount,
        'expense', p_expense_id,
        v_expense.description,
        p_user_id
      );
    ELSIF v_expense.payment_source = 'custody' AND v_expense.custody_id IS NOT NULL THEN
      PERFORM add_custody_transaction(
        v_expense.custody_id, 'expense', v_expense.amount,
        NULL, 'expense', p_expense_id,
        v_expense.description,
        p_user_id
      );
    ELSE
      RAISE EXCEPTION 'يجب تحديد مصدر الدفع (خزنة أو عهدة)';
    END IF;

    -- 4. جلب اسم التصنيف للقيد
    SELECT name INTO v_cat_name FROM expense_categories WHERE id = v_expense.category_id;

    -- 5. إنشاء قيد محاسبي تلقائي
    --    DR: مصروفات   →   CR: صندوق/بنك/عهدة
    PERFORM create_auto_journal_entry(
      'expense', p_expense_id,
      'مصروف — ' || COALESCE(v_cat_name, v_expense.description),
      '5200',                             -- مصروفات تشغيلية
      -- F10: تحديد الحساب الدائن حسب المصدر ونوع الخزنة
      CASE v_expense.payment_source
        WHEN 'custody' THEN '1400'        -- عُهد
        WHEN 'vault' THEN
          CASE (SELECT type FROM vaults WHERE id = v_expense.vault_id)
            WHEN 'cash' THEN '1110'
            WHEN 'bank' THEN '1120'
            WHEN 'mobile_wallet' THEN '1130'
            ELSE '1110'                    -- T2: fallback
          END
        ELSE '1110'                        -- U3: safety net
      END,
      v_expense.amount,
      p_user_id
    );

    -- 6. تحديث المصروف
    UPDATE expenses
    SET status = 'approved',
        approved_by = p_user_id,
        approved_at = now()
    WHERE id = p_expense_id;

  ELSIF p_action = 'reject' THEN
    UPDATE expenses
    SET status = 'rejected',
        rejection_reason = p_reason,
        approved_by = p_user_id,
        approved_at = now()
    WHERE id = p_expense_id;

  ELSE
    RAISE EXCEPTION 'الإجراء يجب أن يكون approve أو reject';
  END IF;
END; $$;

-- Source: 03_financial_infrastructure.sql -> Function: create_auto_journal_entry
CREATE OR REPLACE FUNCTION create_auto_journal_entry(
  p_source_type   TEXT,
  p_source_id     UUID,
  p_description   TEXT,
  p_debit_account TEXT,     -- كود الحساب المدين
  p_credit_account TEXT,    -- كود الحساب الدائن
  p_amount        NUMERIC,
  p_user_id       UUID
) RETURNS UUID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_entry_id    UUID;
  v_debit_acct  UUID;
  v_credit_acct UUID;
BEGIN
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- جلب معرّفات الحسابات من الأكواد
  SELECT id INTO v_debit_acct FROM chart_of_accounts WHERE code = p_debit_account;
  IF v_debit_acct IS NULL THEN
    RAISE EXCEPTION 'حساب مدين غير موجود: %', p_debit_account;
  END IF;

  SELECT id INTO v_credit_acct FROM chart_of_accounts WHERE code = p_credit_account;
  IF v_credit_acct IS NULL THEN
    RAISE EXCEPTION 'حساب دائن غير موجود: %', p_credit_account;
  END IF;

  -- إنشاء القيد (total_debit = total_credit → يمر من CHECK constraint)
  INSERT INTO journal_entries (
    source_type, source_id, description, is_auto,
    total_debit, total_credit, created_by
  ) VALUES (
    p_source_type, p_source_id, p_description, true,
    p_amount, p_amount, p_user_id
  )
  RETURNING id INTO v_entry_id;

  -- إدراج السطر المدين
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
  VALUES (v_entry_id, v_debit_acct, p_amount, 0, p_description);

  -- إدراج السطر الدائن
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
  VALUES (v_entry_id, v_credit_acct, 0, p_amount, p_description);

  RETURN v_entry_id;
END; $$;

-- Source: 03c_atomic_journal_entry.sql -> Function: create_manual_journal_entry
CREATE OR REPLACE FUNCTION create_manual_journal_entry(
  p_description    TEXT,
  p_entry_date     DATE DEFAULT CURRENT_DATE,
  p_source_type    TEXT DEFAULT 'manual',
  p_source_id      UUID DEFAULT NULL,
  p_lines          JSONB DEFAULT '[]'::JSONB,
  p_user_id        UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_entry_id       UUID;
  v_total_debit    NUMERIC(14,2) := 0;
  v_total_credit   NUMERIC(14,2) := 0;
  v_line           JSONB;
  v_account_id     UUID;
  v_line_count     INT := 0;
BEGIN
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- ─── Validate ───
  IF p_lines IS NULL OR jsonb_array_length(p_lines) < 2 THEN
    RAISE EXCEPTION 'القيد يجب أن يحتوي على سطرين على الأقل';
  END IF;

  -- ─── Calculate totals & validate accounts ───
  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    -- Validate account_code exists
    SELECT id INTO v_account_id
    FROM chart_of_accounts
    WHERE code = (v_line ->> 'account_code')
      AND is_active = true;

    IF v_account_id IS NULL THEN
      RAISE EXCEPTION 'حساب غير موجود أو غير نشط: %', (v_line ->> 'account_code');
    END IF;

    v_total_debit  := v_total_debit  + COALESCE((v_line ->> 'debit')::NUMERIC, 0);
    v_total_credit := v_total_credit + COALESCE((v_line ->> 'credit')::NUMERIC, 0);
    v_line_count   := v_line_count + 1;
  END LOOP;

  -- ─── Check balance ───
  IF v_total_debit <> v_total_credit THEN
    RAISE EXCEPTION 'القيد غير متوازن: مدين % ≠ دائن %', v_total_debit, v_total_credit;
  END IF;

  IF v_total_debit = 0 THEN
    RAISE EXCEPTION 'إجمالي القيد لا يمكن أن يكون صفراً';
  END IF;

  -- ─── Insert header ───
  INSERT INTO journal_entries (
    source_type, source_id, description, entry_date,
    is_auto, status, total_debit, total_credit, created_by
  ) VALUES (
    p_source_type, p_source_id, p_description, p_entry_date,
    false, 'posted', v_total_debit, v_total_credit, p_user_id
  )
  RETURNING id INTO v_entry_id;

  -- ─── Insert lines ───
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
  SELECT
    v_entry_id,
    ca.id,
    COALESCE((line ->> 'debit')::NUMERIC, 0),
    COALESCE((line ->> 'credit')::NUMERIC, 0),
    line ->> 'description'
  FROM jsonb_array_elements(p_lines) AS line
  JOIN chart_of_accounts ca ON ca.code = (line ->> 'account_code');

  RETURN v_entry_id;
END;
$$;

-- Source: 03d_vault_transfer.sql -> Function: transfer_between_vaults
CREATE OR REPLACE FUNCTION transfer_between_vaults(
  p_from_vault_id  UUID,
  p_to_vault_id    UUID,
  p_amount         NUMERIC,
  p_description    TEXT DEFAULT '',
  p_user_id        UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_from_vault   vaults%ROWTYPE;
  v_to_vault     vaults%ROWTYPE;
  v_from_balance NUMERIC;
  v_to_balance   NUMERIC;
  v_txn_id       UUID;  -- return the outgoing transaction ID
  v_desc_out     TEXT;
  v_desc_in      TEXT;
BEGIN
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- ─── 1. Input validation ───
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
  END IF;

  IF p_from_vault_id IS NULL OR p_to_vault_id IS NULL THEN
    RAISE EXCEPTION 'معرّف الخزنة مطلوب';
  END IF;

  IF p_from_vault_id = p_to_vault_id THEN
    RAISE EXCEPTION 'لا يمكن التحويل من وإلى نفس الخزنة';
  END IF;

  -- ─── 2. Lock both vaults (consistent order by UUID to prevent deadlock) ───
  IF p_from_vault_id < p_to_vault_id THEN
    SELECT * INTO v_from_vault FROM vaults WHERE id = p_from_vault_id FOR UPDATE;
    SELECT * INTO v_to_vault   FROM vaults WHERE id = p_to_vault_id   FOR UPDATE;
  ELSE
    SELECT * INTO v_to_vault   FROM vaults WHERE id = p_to_vault_id   FOR UPDATE;
    SELECT * INTO v_from_vault FROM vaults WHERE id = p_from_vault_id FOR UPDATE;
  END IF;

  -- ─── 3. Existence check ───
  IF v_from_vault.id IS NULL THEN
    RAISE EXCEPTION 'خزنة المصدر غير موجودة';
  END IF;
  IF v_to_vault.id IS NULL THEN
    RAISE EXCEPTION 'خزنة الوجهة غير موجودة';
  END IF;

  -- ─── 4. Active check ───
  IF NOT v_from_vault.is_active THEN
    RAISE EXCEPTION 'خزنة المصدر معطلة';
  END IF;
  IF NOT v_to_vault.is_active THEN
    RAISE EXCEPTION 'خزنة الوجهة معطلة';
  END IF;

  -- ─── 5. Sufficient balance check ───
  IF v_from_vault.current_balance < p_amount THEN
    RAISE EXCEPTION 'رصيد خزنة المصدر غير كافٍ (المتاح: %، المطلوب: %)',
      v_from_vault.current_balance, p_amount;
  END IF;

  -- ─── 6. Calculate new balances ───
  v_from_balance := v_from_vault.current_balance - p_amount;
  v_to_balance   := v_to_vault.current_balance   + p_amount;

  -- ─── 7. Build descriptions ───
  -- Format: "user description → target_name" / "user description ← source_name"
  -- If no user description, just show the vault name
  IF COALESCE(TRIM(p_description), '') = '' THEN
    v_desc_out := 'تحويل → ' || v_to_vault.name;
    v_desc_in  := 'تحويل ← ' || v_from_vault.name;
  ELSE
    v_desc_out := TRIM(p_description) || ' → ' || v_to_vault.name;
    v_desc_in  := TRIM(p_description) || ' ← ' || v_from_vault.name;
  END IF;

  -- ─── 8. Insert transfer_out (source) ───
  INSERT INTO vault_transactions (
    vault_id, type, amount, balance_after,
    reference_type, reference_id, description, created_by
  ) VALUES (
    p_from_vault_id, 'transfer_out', p_amount, v_from_balance,
    'vault_transfer', p_to_vault_id, v_desc_out, p_user_id
  )
  RETURNING id INTO v_txn_id;

  -- ─── 9. Insert transfer_in (target) ───
  INSERT INTO vault_transactions (
    vault_id, type, amount, balance_after,
    reference_type, reference_id, description, created_by
  ) VALUES (
    p_to_vault_id, 'transfer_in', p_amount, v_to_balance,
    'vault_transfer', p_from_vault_id, v_desc_in, p_user_id
  );

  -- ─── 10. Update cached balances ───
  UPDATE vaults SET current_balance = v_from_balance WHERE id = p_from_vault_id;
  UPDATE vaults SET current_balance = v_to_balance   WHERE id = p_to_vault_id;

  RETURN v_txn_id;
END;
$$;

