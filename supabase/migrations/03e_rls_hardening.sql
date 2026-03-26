-- ════════════════════════════════════════════════════════════
-- EDARA v2 — Migration 06: RLS Hardening
-- تقوية عزل البيانات: Context-Aware Row-Level Security
-- ════════════════════════════════════════════════════════════
-- 
-- المشكلة: صلاحية "read" كانت تعني "يرى الكل"
-- الحل: read = يرى ما يخصه فقط، read_all = يرى كل شيء
--
-- Idempotent: آمن للتشغيل المتكرر
-- ════════════════════════════════════════════════════════════


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 1. دالة مساعدة: get_my_warehouse_ids()                   ║
-- ║    تُرجع مصفوفة UUIDs لمخازن المستخدم الحالي              ║
-- ╚═══════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION get_my_warehouse_ids()
RETURNS UUID[]
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(array_agg(DISTINCT wid), '{}')
  FROM (
    -- مدير مباشر للمخزن
    SELECT id AS wid FROM warehouses WHERE manager_id = auth.uid()
    UNION
    -- ضمن فريق إدارة المخزن
    SELECT warehouse_id AS wid FROM warehouse_managers WHERE profile_id = auth.uid()
  ) sub;
$$;


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 2. صلاحيات جديدة: _all للأدوار القيادية                    ║
-- ╚═══════════════════════════════════════════════════════════╝

-- CEO: يرى كل شيء في المالية والمخزون
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('finance.custody.read_all'),
  ('finance.expenses.read_all'),
  ('finance.payments.read_all'),
  ('finance.vaults.read_all')
) AS p(perm)
WHERE r.name = 'ceo'
ON CONFLICT DO NOTHING;

-- Branch Manager: يرى كل شيء في المالية
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('finance.custody.read_all'),
  ('finance.expenses.read_all'),
  ('finance.payments.read_all'),
  ('finance.vaults.read_all')
) AS p(perm)
WHERE r.name = 'branch_manager'
ON CONFLICT DO NOTHING;

-- Accountant: يرى كل شيء في المالية
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('finance.custody.read_all'),
  ('finance.expenses.read_all'),
  ('finance.payments.read_all'),
  ('finance.vaults.read_all')
) AS p(perm)
WHERE r.name = 'accountant'
ON CONFLICT DO NOTHING;

-- Sales Supervisor: يرى عهد فريقه (ليس الكل)
-- لا يحتاج _all — سيرى فقط حسب السياق


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 3. سياسات RLS ذكية — المخازن والمخزون                     ║
-- ╚═══════════════════════════════════════════════════════════╝

-- ─── warehouses: يرى مخازنه أو الكل ───
DROP POLICY IF EXISTS "warehouses_read" ON warehouses;
CREATE POLICY "warehouses_read" ON warehouses FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR (
    check_permission(auth.uid(), 'inventory.read')
    AND (
      manager_id = auth.uid()
      OR id = ANY(get_my_warehouse_ids())
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
      OR warehouse_id = ANY(get_my_warehouse_ids())
    )
  )
);

-- ─── stock: يرى مخزون مخازنه أو الكل ───
DROP POLICY IF EXISTS "stock_read" ON stock;
CREATE POLICY "stock_read" ON stock FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR (
    check_permission(auth.uid(), 'inventory.read')
    AND warehouse_id = ANY(get_my_warehouse_ids())
  )
);

-- ─── stock_batches: يتبع عزل stock ───
DROP POLICY IF EXISTS "stock_batches_read" ON stock_batches;
CREATE POLICY "stock_batches_read" ON stock_batches FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR (
    check_permission(auth.uid(), 'inventory.read')
    AND stock_id IN (
      SELECT id FROM stock WHERE warehouse_id = ANY(get_my_warehouse_ids())
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
    AND warehouse_id = ANY(get_my_warehouse_ids())
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
      from_warehouse_id = ANY(get_my_warehouse_ids())
      OR to_warehouse_id = ANY(get_my_warehouse_ids())
    )
  )
);

-- ─── stock_transfer_items: يتبع عزل التحويلات ───
DROP POLICY IF EXISTS "transfer_items_read" ON stock_transfer_items;
CREATE POLICY "transfer_items_read" ON stock_transfer_items FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR transfer_id IN (
    SELECT id FROM stock_transfers
    WHERE requested_by = auth.uid()
    OR from_warehouse_id = ANY(get_my_warehouse_ids())
    OR to_warehouse_id = ANY(get_my_warehouse_ids())
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
    AND warehouse_id = ANY(get_my_warehouse_ids())
  )
);

-- ─── stock_adjustment_items: يتبع عزل التسويات ───
DROP POLICY IF EXISTS "adjustment_items_read" ON stock_adjustment_items;
CREATE POLICY "adjustment_items_read" ON stock_adjustment_items FOR SELECT
USING (
  check_permission(auth.uid(), 'inventory.read_all')
  OR adjustment_id IN (
    SELECT id FROM stock_adjustments
    WHERE created_by = auth.uid()
    OR warehouse_id = ANY(get_my_warehouse_ids())
  )
);


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 4. سياسات RLS ذكية — المالية                              ║
-- ╚═══════════════════════════════════════════════════════════╝

-- ─── vaults: يرى خزائنه (المسؤول عنها) أو الكل ───
DROP POLICY IF EXISTS "vaults_read" ON vaults;
CREATE POLICY "vaults_read" ON vaults FOR SELECT
USING (
  check_permission(auth.uid(), 'finance.vaults.read_all')
  OR (
    check_permission(auth.uid(), 'finance.vaults.read')
    AND responsible_id = auth.uid()
  )
);

-- ─── vault_transactions: يرى حركات خزائنه أو الكل ───
DROP POLICY IF EXISTS "vault_txn_read" ON vault_transactions;
CREATE POLICY "vault_txn_read" ON vault_transactions FOR SELECT
USING (
  check_permission(auth.uid(), 'finance.vaults.read_all')
  OR (
    check_permission(auth.uid(), 'finance.vaults.read')
    AND vault_id IN (SELECT id FROM vaults WHERE responsible_id = auth.uid())
  )
);

-- ─── custody_accounts: يرى عهدته أو الكل ───
DROP POLICY IF EXISTS "custody_read" ON custody_accounts;
CREATE POLICY "custody_read" ON custody_accounts FOR SELECT
USING (
  employee_id = auth.uid()
  OR check_permission(auth.uid(), 'finance.custody.read_all')
);

-- ─── custody_transactions: يرى حركات عهدته أو الكل ───
DROP POLICY IF EXISTS "custody_txn_read" ON custody_transactions;
CREATE POLICY "custody_txn_read" ON custody_transactions FOR SELECT
USING (
  check_permission(auth.uid(), 'finance.custody.read_all')
  OR custody_id IN (
    SELECT id FROM custody_accounts WHERE employee_id = auth.uid()
  )
);

-- ─── expenses: يرى مصروفاته أو الكل ───
DROP POLICY IF EXISTS "expenses_read" ON expenses;
CREATE POLICY "expenses_read" ON expenses FOR SELECT
USING (
  created_by = auth.uid()
  OR check_permission(auth.uid(), 'finance.expenses.read_all')
);

-- ─── payment_receipts: يرى إيصالاته أو الكل ───
DROP POLICY IF EXISTS "receipts_read" ON payment_receipts;
CREATE POLICY "receipts_read" ON payment_receipts FOR SELECT
USING (
  created_by = auth.uid()
  OR collected_by = auth.uid()
  OR check_permission(auth.uid(), 'finance.payments.read_all')
);


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 5. تأمين القيود المحاسبية (Journal Entries)                ║
-- ╚═══════════════════════════════════════════════════════════╝

-- القيود: فقط من يملك finance.journal.read
-- (السياسة الحالية صحيحة ولكن نعيد تأكيدها)
DROP POLICY IF EXISTS "je_read" ON journal_entries;
CREATE POLICY "je_read" ON journal_entries FOR SELECT
USING (check_permission(auth.uid(), 'finance.journal.read'));

DROP POLICY IF EXISTS "je_lines_read" ON journal_entry_lines;
CREATE POLICY "je_lines_read" ON journal_entry_lines FOR SELECT
USING (check_permission(auth.uid(), 'finance.journal.read'));


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 6. ملخص التغييرات                                         ║
-- ╚═══════════════════════════════════════════════════════════╝
-- 
-- الجداول المُعاد تأمينها:
--   ✅ warehouses         → inventory.read = مخازنه، read_all = الكل
--   ✅ warehouse_managers → يتبع warehouses
--   ✅ stock              → inventory.read = مخزون مخازنه
--   ✅ stock_batches      → يتبع stock
--   ✅ stock_movements    → يتبع warehouses
--   ✅ stock_transfers    → مخازنه أو أنشأها
--   ✅ stock_transfer_items → يتبع transfers
--   ✅ stock_adjustments  → مخازنه أو أنشأها
--   ✅ stock_adjustment_items → يتبع adjustments
--   ✅ vaults             → responsible_id أو read_all
--   ✅ vault_transactions → يتبع vaults
--   ✅ custody_accounts   → employee_id أو read_all
--   ✅ custody_transactions → يتبع custody_accounts
--   ✅ expenses           → created_by أو read_all
--   ✅ payment_receipts   → created_by/collected_by أو read_all
--   ✅ journal_entries    → finance.journal.read فقط
--   ✅ journal_entry_lines → finance.journal.read فقط
--
-- الصلاحيات الجديدة:
--   finance.custody.read_all  → CEO, Branch Manager, Accountant
--   finance.expenses.read_all → CEO, Branch Manager, Accountant
--   finance.payments.read_all → CEO, Branch Manager, Accountant
--   finance.vaults.read_all   → CEO, Branch Manager, Accountant
