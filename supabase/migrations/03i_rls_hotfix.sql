-- ============================================================
-- Migration 09b: RLS Recursion Hotfix
-- ============================================================
-- المشكلة: استخدام EXISTS المباشر بين warehouses و warehouse_managers
-- أدى إلى (Infinite Recursion) 500 Internal Server Error في صفحة التحويلات والمخزون
-- 
-- الحل: العودة لنمط SECURITY DEFINER لتجاوز حلقة الـ RLS 
-- لكن باستخدام أداء (SETOF UUID) بدلاً من (ARRAY) لتغليفها كـ SubQuery سريعة 
-- ============================================================

-- 1. الدالة السريعة الخالية من حلقة RLS (Security Definer)
CREATE OR REPLACE FUNCTION user_warehouse_ids_set()
RETURNS SETOF UUID -- ترجع كجدول وليس مصفوفة
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id FROM warehouses WHERE manager_id = auth.uid()
  UNION
  SELECT warehouse_id FROM warehouse_managers WHERE profile_id = auth.uid();
$$;

-- 2. تطبيقها على الجداول دون الدخول في حلقة تكرار (Loop)

-- ─── warehouses ───
DROP POLICY IF EXISTS "warehouses_read" ON warehouses;
CREATE POLICY "warehouses_read" ON warehouses FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR (
    check_permission(auth.uid(), 'inventory.read')
    AND id IN (SELECT user_warehouse_ids_set())
  )
);

-- ─── warehouse_managers ───
DROP POLICY IF EXISTS "wh_managers_read" ON warehouse_managers;
CREATE POLICY "wh_managers_read" ON warehouse_managers FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR (
    check_permission(auth.uid(), 'inventory.read')
    AND warehouse_id IN (SELECT user_warehouse_ids_set())
  )
);

-- ─── stock ───
DROP POLICY IF EXISTS "stock_read" ON stock;
CREATE POLICY "stock_read" ON stock FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR (
    check_permission(auth.uid(), 'inventory.read')
    AND warehouse_id IN (SELECT user_warehouse_ids_set())
  )
);

-- ─── stock_movements ───
DROP POLICY IF EXISTS "stock_movements_read" ON stock_movements;
CREATE POLICY "stock_movements_read" ON stock_movements FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR (
    check_permission(auth.uid(), 'inventory.read')
    AND warehouse_id IN (SELECT user_warehouse_ids_set())
  )
);

-- ─── stock_batches ───
DROP POLICY IF EXISTS "stock_batches_read" ON stock_batches;
CREATE POLICY "stock_batches_read" ON stock_batches FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR (
    check_permission(auth.uid(), 'inventory.read')
    AND stock_id IN (
      SELECT id FROM stock WHERE warehouse_id IN (SELECT user_warehouse_ids_set())
    )
  )
);

-- ─── stock_transfers ───
DROP POLICY IF EXISTS "transfers_read" ON stock_transfers;
CREATE POLICY "transfers_read" ON stock_transfers FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR requested_by = auth.uid()
  OR (
    check_permission(auth.uid(), 'inventory.transfers.read')
    AND (
      from_warehouse_id IN (SELECT user_warehouse_ids_set())
      OR to_warehouse_id IN (SELECT user_warehouse_ids_set())
    )
  )
);

-- ─── stock_transfer_items ───
DROP POLICY IF EXISTS "transfer_items_read" ON stock_transfer_items;
CREATE POLICY "transfer_items_read" ON stock_transfer_items FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR transfer_id IN (
    SELECT id FROM stock_transfers
    WHERE requested_by = auth.uid()
    OR from_warehouse_id IN (SELECT user_warehouse_ids_set())
    OR to_warehouse_id IN (SELECT user_warehouse_ids_set())
  )
);

-- ─── stock_adjustments ───
DROP POLICY IF EXISTS "adjustments_read" ON stock_adjustments;
CREATE POLICY "adjustments_read" ON stock_adjustments FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR created_by = auth.uid()
  OR (
    check_permission(auth.uid(), 'inventory.adjustments.read')
    AND warehouse_id IN (SELECT user_warehouse_ids_set())
  )
);

-- ─── stock_adjustment_items ───
DROP POLICY IF EXISTS "adjustment_items_read" ON stock_adjustment_items;
CREATE POLICY "adjustment_items_read" ON stock_adjustment_items FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR adjustment_id IN (
    SELECT id FROM stock_adjustments
    WHERE created_by = auth.uid()
    OR warehouse_id IN (SELECT user_warehouse_ids_set())
  )
);
