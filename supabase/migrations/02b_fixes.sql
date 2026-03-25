-- ============================================================
-- 02b_fixes.sql — إصلاح الصلاحيات الناقصة + توثيق current_balance
-- ============================================================
-- هذا الملف تكميلي لـ 01_foundation.sql و 02_master_data.sql
-- آمن للتشغيل عدة مرات (idempotent) بفضل ON CONFLICT DO NOTHING
-- ============================================================

-- ============================================================
-- 1. CEO — صلاحيات ناقصة
-- ============================================================
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('products.read'),
  ('branches.read'),
  ('price_lists.read'),
  ('customers.read_all'),
  ('suppliers.read'),
  ('inventory.adjustments.read')
) AS p(perm)
WHERE r.name = 'ceo'
ON CONFLICT DO NOTHING;

-- ============================================================
-- 2. Branch Manager — صلاحيات ناقصة
-- ============================================================
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('products.read'),
  ('branches.read'),
  ('price_lists.read'),
  ('customers.read_all'),
  ('suppliers.read'),
  ('suppliers.create'),
  ('suppliers.update'),
  ('categories.create'),
  ('inventory.adjustments.read')
) AS p(perm)
WHERE r.name = 'branch_manager'
ON CONFLICT DO NOTHING;

-- ============================================================
-- 3. Sales Supervisor — صلاحيات ناقصة
-- ============================================================
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('products.read'),
  ('branches.read'),
  ('price_lists.read')
) AS p(perm)
WHERE r.name = 'sales_supervisor'
ON CONFLICT DO NOTHING;

-- ============================================================
-- 4. Sales Rep — صلاحيات ناقصة
-- ============================================================
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('products.read')
) AS p(perm)
WHERE r.name = 'sales_rep'
ON CONFLICT DO NOTHING;

-- ============================================================
-- 5. Warehouse Keeper — صلاحيات ناقصة
-- ============================================================
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('products.read'),
  ('branches.read'),
  ('inventory.adjustments.read'),
  ('inventory.adjustments.create')
) AS p(perm)
WHERE r.name = 'warehouse_keeper'
ON CONFLICT DO NOTHING;

-- ============================================================
-- 6. Accountant — صلاحيات ناقصة
-- ============================================================
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('products.read'),
  ('branches.read'),
  ('price_lists.read'),
  ('customers.read_all'),
  ('inventory.adjustments.read')
) AS p(perm)
WHERE r.name = 'accountant'
ON CONFLICT DO NOTHING;

-- ============================================================
-- 7. HR Manager — صلاحيات ناقصة
-- ============================================================
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('branches.read')
) AS p(perm)
WHERE r.name = 'hr_manager'
ON CONFLICT DO NOTHING;

-- ============================================================
-- 8. توثيق current_balance — مؤقت حتى يُبنى Ledger في M03
-- ============================================================
COMMENT ON COLUMN customers.current_balance IS
  '⚠️ مؤقت — يُحسب حالياً من opening_balance فقط. '
  'سيُستبدل بـ computed view من customer_ledger في المرحلة 3 (M03). '
  'لا تُعدّل هذا العمود يدوياً — استخدم DB functions فقط.';

COMMENT ON COLUMN suppliers.current_balance IS
  '⚠️ مؤقت — يُحسب حالياً من opening_balance فقط. '
  'سيُستبدل بـ computed view من supplier_ledger في المرحلة 3 (M03). '
  'لا تُعدّل هذا العمود يدوياً — استخدم DB functions فقط.';
