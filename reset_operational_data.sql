-- ============================================================
-- reset_operational_data.sql
-- تفريغ الجداول التشغيلية والمالية مع الحفاظ على البيانات الاعتمادية
--
-- الجداول المحفوظة (لا تُمسح):
--   profiles, roles, role_permissions, permissions,
--   governorates, cities, areas, branches,
--   products, product_categories, brands, units,
--   product_units, product_bundles, product_bundle_items,
--   price_lists, price_list_items, price_list_assignments,
--   customers, customer_branches, customer_contacts,
--   suppliers, supplier_contacts,
--   warehouses, warehouse_managers,
--   chart_of_accounts, expense_categories,
--   vaults, custody_accounts,
--   approval_rules, shipping_companies,
--   company_settings
--
-- ⚠️ تحذير: هذا الأمر لا يمكن التراجع عنه!
-- ============================================================

BEGIN;

-- ١. المبيعات (الأبناء أولاً)
TRUNCATE TABLE sales_return_items CASCADE;
TRUNCATE TABLE sales_returns CASCADE;
TRUNCATE TABLE sales_order_items CASCADE;
TRUNCATE TABLE sales_orders CASCADE;

-- ١ب. العملاء وبياناتهم
TRUNCATE TABLE customer_contacts CASCADE;
TRUNCATE TABLE customer_branches CASCADE;
TRUNCATE TABLE customer_credit_history CASCADE;
TRUNCATE TABLE customers CASCADE;

-- ٢. المالية — الحركات والقيود
TRUNCATE TABLE journal_entry_lines CASCADE;
TRUNCATE TABLE journal_entries CASCADE;
TRUNCATE TABLE payment_receipts CASCADE;
TRUNCATE TABLE expenses CASCADE;
TRUNCATE TABLE customer_ledger CASCADE;
TRUNCATE TABLE supplier_ledger CASCADE;
TRUNCATE TABLE customer_credit_history CASCADE;
TRUNCATE TABLE supplier_payment_reminders CASCADE;

-- ٣. العهد والخزائن — الحركات فقط (الحسابات تبقى)
TRUNCATE TABLE custody_transactions CASCADE;
TRUNCATE TABLE vault_transactions CASCADE;

-- ٤. المخزون — الحركات (المخزون الفعلي + الحجز يتصفر)
TRUNCATE TABLE stock_adjustment_items CASCADE;
TRUNCATE TABLE stock_adjustments CASCADE;
TRUNCATE TABLE stock_transfer_items CASCADE;
TRUNCATE TABLE stock_transfers CASCADE;
TRUNCATE TABLE stock_movements CASCADE;
TRUNCATE TABLE stock_batches CASCADE;

-- ٥. تصفير أرصدة المخزون
UPDATE stock SET quantity = 0, reserved_quantity = 0;

-- ٦. تصفير أرصدة الخزائن والعهد
UPDATE vaults SET current_balance = 0;
UPDATE custody_accounts SET current_balance = 0;

-- ٨. إعادة تعداد التسلسلات
ALTER SEQUENCE IF EXISTS sales_order_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS sales_return_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS journal_entry_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS payment_receipt_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS expense_seq RESTART WITH 1;

COMMIT;

-- ✅ تم التفريغ بنجاح — جميع البيانات الاعتمادية محفوظة
