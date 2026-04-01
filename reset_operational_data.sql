-- ============================================================
-- reset_operational_data.sql
-- تفريغ البيانات التشغيلية مع الحفاظ على الجداول المرجعية والإعدادية
--
-- هذا الملف يفرغ:
--   - المعاملات التشغيلية والمالية والمخزنية
--   - بيانات العملاء والموردين التشغيلية
--   - بيانات التشغيل الخاصة بالموارد البشرية
--   - بيانات تشغيل موديول الأنشطة
--
-- هذا الملف لا يفرغ:
--   - المستخدمين والصلاحيات والإعدادات العامة
--   - الجغرافيا والفروع
--   - جداول الأنواع والتصنيفات والماستر المرجعي
--   - المخازن والخزن والعهد نفسها، وإنما يُصفَّر رصيدها فقط
--   - قوالب وخيارات الأنشطة والاستبيانات والإعدادات المرجعية للموارد البشرية
--
-- أمثلة للجداول المحفوظة:
--   profiles, roles, role_permissions, user_roles, user_permission_overrides
--   company_settings, feature_flags, audit_logs
--   governorates, cities, areas, branches
--   product_categories, brands, units, products, product_units
--   product_bundles, product_bundle_items
--   price_lists, price_list_items
--   warehouses, warehouse_managers
--   chart_of_accounts, expense_categories, approval_rules, shipping_companies
--   vaults, custody_accounts
--   hr_departments, hr_positions, hr_work_locations
--   hr_public_holidays, hr_leave_types, hr_penalty_rules
--   activity_types, target_types
--   visit_checklist_templates, visit_checklist_questions
--
-- ⚠️ تحذير: هذا الأمر لا يمكن التراجع عنه
-- ============================================================

BEGIN;

-- ١. الأنشطة والاستبيانات التشغيلية
TRUNCATE TABLE visit_checklist_responses CASCADE;
TRUNCATE TABLE call_details CASCADE;
TRUNCATE TABLE activities CASCADE;
TRUNCATE TABLE visit_plan_items CASCADE;
TRUNCATE TABLE visit_plans CASCADE;
TRUNCATE TABLE visit_plan_templates CASCADE;
TRUNCATE TABLE call_plan_items CASCADE;
TRUNCATE TABLE call_plans CASCADE;
TRUNCATE TABLE call_plan_templates CASCADE;
TRUNCATE TABLE target_adjustments CASCADE;
TRUNCATE TABLE target_progress CASCADE;
TRUNCATE TABLE targets CASCADE;

-- ٢. المبيعات
TRUNCATE TABLE sales_return_items CASCADE;
TRUNCATE TABLE sales_returns CASCADE;
TRUNCATE TABLE sales_order_items CASCADE;
TRUNCATE TABLE sales_orders CASCADE;

-- ٣. المشتريات
TRUNCATE TABLE purchase_return_items CASCADE;
TRUNCATE TABLE purchase_returns CASCADE;
TRUNCATE TABLE purchase_invoice_items CASCADE;
TRUNCATE TABLE purchase_invoices CASCADE;

-- ٤. العملاء والموردون وبياناتهم التشغيلية
-- حذف تخصيصات قوائم الأسعار الخاصة بالعملاء فقط
-- مع الإبقاء على التخصيصات المرجعية الخاصة بالمدن والمحافظات
DELETE FROM price_list_assignments
WHERE entity_type = 'customer';

TRUNCATE TABLE customer_contacts CASCADE;
TRUNCATE TABLE customer_branches CASCADE;
TRUNCATE TABLE customer_credit_history CASCADE;
TRUNCATE TABLE customers CASCADE;

TRUNCATE TABLE supplier_contacts CASCADE;
TRUNCATE TABLE supplier_payment_reminders CASCADE;
TRUNCATE TABLE suppliers CASCADE;

-- ٥. المالية والمحاسبة
TRUNCATE TABLE journal_entry_lines CASCADE;
TRUNCATE TABLE journal_entries CASCADE;
TRUNCATE TABLE payment_receipts CASCADE;
TRUNCATE TABLE expenses CASCADE;
TRUNCATE TABLE customer_ledger CASCADE;
TRUNCATE TABLE supplier_ledger CASCADE;

-- ٦. العهد والخزائن - الحركات فقط
TRUNCATE TABLE custody_transactions CASCADE;
TRUNCATE TABLE vault_transactions CASCADE;

-- ٧. المخزون - الحركات فقط
TRUNCATE TABLE stock_adjustment_items CASCADE;
TRUNCATE TABLE stock_adjustments CASCADE;
TRUNCATE TABLE stock_transfer_items CASCADE;
TRUNCATE TABLE stock_transfers CASCADE;
TRUNCATE TABLE stock_movements CASCADE;
TRUNCATE TABLE stock_batches CASCADE;

-- ٨. الموارد البشرية - بيانات التشغيل
TRUNCATE TABLE hr_payroll_adjustments CASCADE;
TRUNCATE TABLE hr_advance_installments CASCADE;
TRUNCATE TABLE hr_commission_targets CASCADE;
TRUNCATE TABLE hr_commission_records CASCADE;
TRUNCATE TABLE hr_payroll_lines CASCADE;
TRUNCATE TABLE hr_payroll_runs CASCADE;
TRUNCATE TABLE hr_payroll_periods CASCADE;
TRUNCATE TABLE hr_advances CASCADE;
TRUNCATE TABLE hr_permission_requests CASCADE;
TRUNCATE TABLE hr_leave_requests CASCADE;
TRUNCATE TABLE hr_leave_balances CASCADE;
TRUNCATE TABLE hr_penalty_instances CASCADE;
TRUNCATE TABLE hr_attendance_logs CASCADE;
TRUNCATE TABLE hr_attendance_days CASCADE;
TRUNCATE TABLE hr_employee_documents CASCADE;
TRUNCATE TABLE hr_delegations CASCADE;
TRUNCATE TABLE hr_salary_history CASCADE;
TRUNCATE TABLE hr_contracts CASCADE;
TRUNCATE TABLE hr_employees CASCADE;

-- ٩. تصفير أرصدة المخزون
UPDATE stock
SET quantity = 0,
    reserved_quantity = 0;

-- ١٠. تصفير أرصدة الخزائن والعهد
UPDATE vaults
SET current_balance = 0;

UPDATE custody_accounts
SET current_balance = 0;

-- ١١. إعادة تعيين التسلسلات
ALTER SEQUENCE IF EXISTS customer_code_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS supplier_code_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS transfer_number_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS adjustment_number_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS payment_receipt_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS expense_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS journal_entry_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS sales_order_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS sales_return_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS purchase_invoice_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS purchase_return_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS hr_employee_number_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS hr_payroll_run_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS hr_advance_seq RESTART WITH 1;

COMMIT;

-- ✅ تم تفريغ البيانات التشغيلية مع الحفاظ على الجداول المرجعية والإعدادية
