-- ============================================================
-- Migration 09: Extreme Performance Hardening
-- EDARA v2 — القضاء على نقاط الاختناق
-- ============================================================
-- 1. Triggers لتحديث current_balance تلقائياً من الحركات
-- 2. Backfill أرصدة العملاء والموردين من البيانات الحالية
-- 3. تحسين RLS المخازن (EXISTS بدلاً من ANY(function()))
-- 4. ANALYZE الجداول المتأثرة
-- ============================================================
-- آمن للتشغيل أكثر من مرة (Idempotent)
-- ============================================================


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 1. TRIGGER: تحديث رصيد العميل عند حركة في customer_ledger ║
-- ╚═══════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION update_customer_cached_balance()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old_delta NUMERIC;
  v_new_delta NUMERIC;
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- عكس الأثر من العميل
    v_old_delta := CASE WHEN OLD.type = 'debit' THEN -OLD.amount ELSE OLD.amount END;
    UPDATE customers SET current_balance = current_balance + v_old_delta
    WHERE id = OLD.customer_id;
    RETURN OLD;

  ELSIF TG_OP = 'INSERT' THEN
    -- مدين = رصيد العميل يزيد (العميل مدين لنا)
    v_new_delta := CASE WHEN NEW.type = 'debit' THEN NEW.amount ELSE -NEW.amount END;
    UPDATE customers SET current_balance = current_balance + v_new_delta
    WHERE id = NEW.customer_id;
    RETURN NEW;

  ELSE -- UPDATE
    -- عكس الأثر القديم من العميل القديم
    v_old_delta := CASE WHEN OLD.type = 'debit' THEN OLD.amount ELSE -OLD.amount END;
    UPDATE customers SET current_balance = current_balance - v_old_delta
    WHERE id = OLD.customer_id;
    -- تطبيق الأثر الجديد على العميل الجديد (قد يكون نفسه أو مختلف)
    v_new_delta := CASE WHEN NEW.type = 'debit' THEN NEW.amount ELSE -NEW.amount END;
    UPDATE customers SET current_balance = current_balance + v_new_delta
    WHERE id = NEW.customer_id;
    RETURN NEW;
  END IF;
END; $$;

DROP TRIGGER IF EXISTS trg_cust_ledger_update_balance ON customer_ledger;
CREATE TRIGGER trg_cust_ledger_update_balance
  AFTER INSERT OR UPDATE OR DELETE ON customer_ledger
  FOR EACH ROW EXECUTE FUNCTION update_customer_cached_balance();


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 2. TRIGGER: تحديث رصيد المورد عند حركة في supplier_ledger  ║
-- ╚═══════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION update_supplier_cached_balance()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old_delta NUMERIC;
  v_new_delta NUMERIC;
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- عكس الأثر من المورد
    v_old_delta := CASE WHEN OLD.type = 'credit' THEN -OLD.amount ELSE OLD.amount END;
    UPDATE suppliers SET current_balance = current_balance + v_old_delta
    WHERE id = OLD.supplier_id;
    RETURN OLD;

  ELSIF TG_OP = 'INSERT' THEN
    -- دائن = رصيد المورد يزيد (نحن مدينون للمورد)
    v_new_delta := CASE WHEN NEW.type = 'credit' THEN NEW.amount ELSE -NEW.amount END;
    UPDATE suppliers SET current_balance = current_balance + v_new_delta
    WHERE id = NEW.supplier_id;
    RETURN NEW;

  ELSE -- UPDATE
    -- عكس الأثر القديم من المورد القديم
    v_old_delta := CASE WHEN OLD.type = 'credit' THEN OLD.amount ELSE -OLD.amount END;
    UPDATE suppliers SET current_balance = current_balance - v_old_delta
    WHERE id = OLD.supplier_id;
    -- تطبيق الأثر الجديد على المورد الجديد (قد يكون نفسه أو مختلف)
    v_new_delta := CASE WHEN NEW.type = 'credit' THEN NEW.amount ELSE -NEW.amount END;
    UPDATE suppliers SET current_balance = current_balance + v_new_delta
    WHERE id = NEW.supplier_id;
    RETURN NEW;
  END IF;
END; $$;

DROP TRIGGER IF EXISTS trg_supp_ledger_update_balance ON supplier_ledger;
CREATE TRIGGER trg_supp_ledger_update_balance
  AFTER INSERT OR UPDATE OR DELETE ON supplier_ledger
  FOR EACH ROW EXECUTE FUNCTION update_supplier_cached_balance();


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 3. BACKFILL: مزامنة الأرصدة من بيانات الدفتر الموجودة     ║
-- ╚═══════════════════════════════════════════════════════════╝

-- العملاء: جمع كل الحركات وتحديث current_balance
UPDATE customers c
SET current_balance = COALESCE(sub.balance, 0)
FROM (
  SELECT
    customer_id,
    SUM(CASE WHEN type = 'debit' THEN amount ELSE -amount END) AS balance
  FROM customer_ledger
  GROUP BY customer_id
) sub
WHERE c.id = sub.customer_id;

-- الموردين: جمع كل الحركات وتحديث current_balance
UPDATE suppliers s
SET current_balance = COALESCE(sub.balance, 0)
FROM (
  SELECT
    supplier_id,
    SUM(CASE WHEN type = 'credit' THEN amount ELSE -amount END) AS balance
  FROM supplier_ledger
  GROUP BY supplier_id
) sub
WHERE s.id = sub.supplier_id;


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 3.1 حذف الـ Views الثقيلة — لم تعد مستخدمة               ║
-- ╚═══════════════════════════════════════════════════════════╝

DROP VIEW IF EXISTS v_customer_balances;
DROP VIEW IF EXISTS v_supplier_balances;


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 4. تحسين RLS المخازن — EXISTS بدلاً من ANY(function())     ║
-- ║    يسمح لـ PostgreSQL باستخدام الفهارس بكفاءة              ║
-- ╚═══════════════════════════════════════════════════════════╝

-- دالة محسّنة: بدلاً من array_agg + ANY
-- نستخدم EXISTS مع الجداول مباشرة لتفعيل Index Nested Loop

-- ─── stock: يرى مخزون مخازنه أو الكل ───
DROP POLICY IF EXISTS "stock_read" ON stock;
CREATE POLICY "stock_read" ON stock FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR (
    check_permission(auth.uid(), 'inventory.read')
    AND EXISTS (
      SELECT 1 FROM warehouses w
      WHERE w.id = stock.warehouse_id
      AND (
        w.manager_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM warehouse_managers wm
          WHERE wm.warehouse_id = w.id AND wm.profile_id = auth.uid()
        )
      )
    )
  )
);

-- ─── stock_movements: يرى حركات مخازنه أو الكل ───
DROP POLICY IF EXISTS "stock_movements_read" ON stock_movements;
CREATE POLICY "stock_movements_read" ON stock_movements FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR (
    check_permission(auth.uid(), 'inventory.read')
    AND EXISTS (
      SELECT 1 FROM warehouses w
      WHERE w.id = stock_movements.warehouse_id
      AND (
        w.manager_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM warehouse_managers wm
          WHERE wm.warehouse_id = w.id AND wm.profile_id = auth.uid()
        )
      )
    )
  )
);

-- ─── stock_batches: يتبع عزل stock ───
DROP POLICY IF EXISTS "stock_batches_read" ON stock_batches;
CREATE POLICY "stock_batches_read" ON stock_batches FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR (
    check_permission(auth.uid(), 'inventory.read')
    AND EXISTS (
      SELECT 1 FROM stock s
      JOIN warehouses w ON w.id = s.warehouse_id
      WHERE s.id = stock_batches.stock_id
      AND (
        w.manager_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM warehouse_managers wm
          WHERE wm.warehouse_id = w.id AND wm.profile_id = auth.uid()
        )
      )
    )
  )
);

-- ─── warehouses: يرى مخازنه أو الكل ───
DROP POLICY IF EXISTS "warehouses_read" ON warehouses;
CREATE POLICY "warehouses_read" ON warehouses FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR (
    check_permission(auth.uid(), 'inventory.read')
    AND (
      manager_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM warehouse_managers wm
        WHERE wm.warehouse_id = warehouses.id AND wm.profile_id = auth.uid()
      )
    )
  )
);

-- ─── warehouse_managers: يرى فريق مخازنه أو الكل ───
DROP POLICY IF EXISTS "wh_managers_read" ON warehouse_managers;
CREATE POLICY "wh_managers_read" ON warehouse_managers FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR (
    check_permission(auth.uid(), 'inventory.read')
    AND (
      profile_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM warehouses w
        WHERE w.id = warehouse_managers.warehouse_id AND w.manager_id = auth.uid()
      )
    )
  )
);

-- ─── stock_transfers: يرى تحويلات مخازنه أو التي أنشأها ───
DROP POLICY IF EXISTS "transfers_read" ON stock_transfers;
CREATE POLICY "transfers_read" ON stock_transfers FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR requested_by = auth.uid()
  OR (
    check_permission(auth.uid(), 'inventory.transfers.read')
    AND (
      EXISTS (
        SELECT 1 FROM warehouses w
        WHERE w.id = stock_transfers.from_warehouse_id
        AND (w.manager_id = auth.uid() OR EXISTS (
          SELECT 1 FROM warehouse_managers wm WHERE wm.warehouse_id = w.id AND wm.profile_id = auth.uid()
        ))
      )
      OR EXISTS (
        SELECT 1 FROM warehouses w
        WHERE w.id = stock_transfers.to_warehouse_id
        AND (w.manager_id = auth.uid() OR EXISTS (
          SELECT 1 FROM warehouse_managers wm WHERE wm.warehouse_id = w.id AND wm.profile_id = auth.uid()
        ))
      )
    )
  )
);

-- ─── stock_transfer_items: يتبع عزل التحويلات ───
DROP POLICY IF EXISTS "transfer_items_read" ON stock_transfer_items;
CREATE POLICY "transfer_items_read" ON stock_transfer_items FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR EXISTS (
    SELECT 1 FROM stock_transfers t
    WHERE t.id = stock_transfer_items.transfer_id
    AND (
      t.requested_by = auth.uid()
      OR EXISTS (
        SELECT 1 FROM warehouses w
        WHERE (w.id = t.from_warehouse_id OR w.id = t.to_warehouse_id)
        AND (w.manager_id = auth.uid() OR EXISTS (
          SELECT 1 FROM warehouse_managers wm WHERE wm.warehouse_id = w.id AND wm.profile_id = auth.uid()
        ))
      )
    )
  )
);

-- ─── stock_adjustments: يرى تسويات مخازنه أو التي أنشأها ───
DROP POLICY IF EXISTS "adjustments_read" ON stock_adjustments;
CREATE POLICY "adjustments_read" ON stock_adjustments FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR created_by = auth.uid()
  OR (
    check_permission(auth.uid(), 'inventory.adjustments.read')
    AND EXISTS (
      SELECT 1 FROM warehouses w
      WHERE w.id = stock_adjustments.warehouse_id
      AND (w.manager_id = auth.uid() OR EXISTS (
        SELECT 1 FROM warehouse_managers wm WHERE wm.warehouse_id = w.id AND wm.profile_id = auth.uid()
      ))
    )
  )
);

-- ─── stock_adjustment_items: يتبع عزل التسويات ───
DROP POLICY IF EXISTS "adjustment_items_read" ON stock_adjustment_items;
CREATE POLICY "adjustment_items_read" ON stock_adjustment_items FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR EXISTS (
    SELECT 1 FROM stock_adjustments sa
    WHERE sa.id = stock_adjustment_items.adjustment_id
    AND (
      sa.created_by = auth.uid()
      OR EXISTS (
        SELECT 1 FROM warehouses w
        WHERE w.id = sa.warehouse_id
        AND (w.manager_id = auth.uid() OR EXISTS (
          SELECT 1 FROM warehouse_managers wm WHERE wm.warehouse_id = w.id AND wm.profile_id = auth.uid()
        ))
      )
    )
  )
);


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 5. فهارس إضافية لدعم EXISTS في RLS                       ║
-- ╚═══════════════════════════════════════════════════════════╝

-- warehouse_managers: بحث سريع عن مخازن المستخدم
CREATE INDEX IF NOT EXISTS idx_wh_managers_profile
  ON warehouse_managers(profile_id);

-- warehouses: بحث سريع بالمدير
CREATE INDEX IF NOT EXISTS idx_warehouses_manager
  ON warehouses(manager_id) WHERE manager_id IS NOT NULL;


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 6. ANALYZE — تحديث إحصائيات الجداول المتأثرة              ║
-- ╚═══════════════════════════════════════════════════════════╝

ANALYZE customers;
ANALYZE suppliers;
ANALYZE customer_ledger;
ANALYZE supplier_ledger;
ANALYZE warehouses;
ANALYZE warehouse_managers;
ANALYZE stock;
ANALYZE stock_movements;
ANALYZE stock_batches;
ANALYZE stock_transfers;
ANALYZE stock_transfer_items;
ANALYZE stock_adjustments;
ANALYZE stock_adjustment_items;
