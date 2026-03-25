-- ════════════════════════════════════════════════════════════
-- EDARA v2 — Migration 07: Performance Indexes
-- فهارس أداء لتسريع سياسات RLS و check_permission()
-- ════════════════════════════════════════════════════════════
--
-- المشكلة: check_permission() تُستدعى لكل صف في كل استعلام
--   وتقوم بـ 3 JOINs (user_permission_overrides → role_permissions → user_roles)
--   بدون فهارس مركّبة = Full Table Scan لكل صف
--
-- Idempotent: آمن للتشغيل المتكرر
-- ════════════════════════════════════════════════════════════


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 1. فهارس check_permission() — القلب الأمني                ║
-- ╚═══════════════════════════════════════════════════════════╝

-- user_permission_overrides: البحث بـ user_id + permission
CREATE INDEX IF NOT EXISTS idx_upo_user_perm_composite
  ON user_permission_overrides(user_id, permission);

-- role_permissions: البحث بـ role_id + permission
-- (idx_role_perms_role موجود لكنه على role_id فقط)
CREATE INDEX IF NOT EXISTS idx_rp_role_perm_composite
  ON role_permissions(role_id, permission);

-- user_roles: البحث بـ user_id + is_active
-- (idx_user_roles_active موجود لكنه على user_id, is_active)
-- نضيف covering index يشمل role_id للتخلص من heap lookup
CREATE INDEX IF NOT EXISTS idx_ur_user_active_role
  ON user_roles(user_id, role_id)
  WHERE is_active = true;


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 2. فهارس get_my_warehouse_ids() — العزل بالمخازن          ║
-- ╚═══════════════════════════════════════════════════════════╝

-- warehouses: البحث بـ manager_id
CREATE INDEX IF NOT EXISTS idx_wh_manager_id
  ON warehouses(manager_id)
  WHERE manager_id IS NOT NULL;

-- warehouse_managers: البحث بـ profile_id
CREATE INDEX IF NOT EXISTS idx_whm_profile_id
  ON warehouse_managers(profile_id);


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 3. فهارس RLS Context Filters — الجداول الحساسة            ║
-- ╚═══════════════════════════════════════════════════════════╝

-- expenses: فلتر created_by
CREATE INDEX IF NOT EXISTS idx_expenses_created_by
  ON expenses(created_by);

-- payment_receipts: فلتر created_by + collected_by
CREATE INDEX IF NOT EXISTS idx_receipts_created_by
  ON payment_receipts(created_by);
CREATE INDEX IF NOT EXISTS idx_receipts_collected_by
  ON payment_receipts(collected_by);

-- custody_accounts: فلتر employee_id (قد يكون موجوداً عبر UNIQUE)
CREATE INDEX IF NOT EXISTS idx_custody_employee_id
  ON custody_accounts(employee_id);

-- vaults: فلتر responsible_id
CREATE INDEX IF NOT EXISTS idx_vaults_responsible_id
  ON vaults(responsible_id)
  WHERE responsible_id IS NOT NULL;

-- stock: فلتر warehouse_id (موجود لكن نتأكد)
CREATE INDEX IF NOT EXISTS idx_stock_wh_product
  ON stock(warehouse_id, product_id);

-- stock_movements: فلتر warehouse_id (موجود لكن نضيف created_at)
CREATE INDEX IF NOT EXISTS idx_movements_wh_date
  ON stock_movements(warehouse_id, created_at DESC);

-- stock_transfers: فلتر from/to warehouse + requested_by
CREATE INDEX IF NOT EXISTS idx_transfers_from_wh
  ON stock_transfers(from_warehouse_id);
CREATE INDEX IF NOT EXISTS idx_transfers_to_wh
  ON stock_transfers(to_warehouse_id);
CREATE INDEX IF NOT EXISTS idx_transfers_requested_by
  ON stock_transfers(requested_by);

-- stock_adjustments: فلتر warehouse_id + created_by
CREATE INDEX IF NOT EXISTS idx_adjustments_wh
  ON stock_adjustments(warehouse_id);
CREATE INDEX IF NOT EXISTS idx_adjustments_created_by
  ON stock_adjustments(created_by);


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 4. فهارس البحث النصي — الأكثر استخداماً                   ║
-- ╚═══════════════════════════════════════════════════════════╝

-- customers: بحث بالاسم (trigram للبحث المرن ilike)
CREATE INDEX IF NOT EXISTS idx_customers_name_trgm
  ON customers USING gin (name gin_trgm_ops);

-- products: بحث بالاسم
CREATE INDEX IF NOT EXISTS idx_products_name_trgm
  ON products USING gin (name gin_trgm_ops);


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 5. تحليل وتحسين الإحصائيات                                ║
-- ╚═══════════════════════════════════════════════════════════╝

ANALYZE role_permissions;
ANALYZE user_roles;
ANALYZE user_permission_overrides;
ANALYZE warehouses;
ANALYZE warehouse_managers;
ANALYZE customers;
ANALYZE products;
ANALYZE stock;
ANALYZE expenses;
ANALYZE payment_receipts;
ANALYZE custody_accounts;
ANALYZE vaults;
