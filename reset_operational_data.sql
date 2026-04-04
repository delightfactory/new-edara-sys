-- ============================================================
-- reset_operational_data.sql  [v2 — شامل]
-- تفريغ البيانات التشغيلية مع الحفاظ على الجداول المرجعية
--
-- يُفرِّغ هذا الملف:
--   - معاملات المبيعات والمرتجعات
--   - معاملات المشتريات ومرتجعاتها وسندات الصرف
--   - بيانات العملاء والموردين وكل المديونيات
--   - المعاملات المالية (خزائن، عهد، قيود، إيصالات)
--   - المخزون والحركات والتسويات والتحويلات
--   - الموارد البشرية (موظفون، عقود، رواتب، حضور، سلف)
--   - الأنشطة الميدانية والزيارات والمكالمات والأهداف
--   - الإشعارات والتنبيهات التشغيلية
--   - فتح الأرصدة والتدقيق المرتبط بها
--
-- لا يُفرِّغ هذا الملف (الماستر المرجعي):
--   profiles, roles, role_permissions, user_roles
--   user_permission_overrides, company_settings, feature_flags
--   governorates, cities, areas, branches
--   product_categories, brands, units, products, product_units
--   product_bundles, product_bundle_items
--   price_lists, price_list_items
--   warehouses, warehouse_managers
--   chart_of_accounts, expense_categories, approval_rules
--   shipping_companies, internal_config
--   vaults, custody_accounts (الجداول نفسها — يُصفَّر الرصيد فقط)
--   hr_departments, hr_positions, hr_work_locations
--   hr_public_holidays, hr_leave_types, hr_penalty_rules
--   activity_types, target_types
--   visit_checklist_templates, visit_checklist_questions
--
-- ⚠️ تحذير: لا يمكن التراجع عنه — استخدمه للاختبارات فقط
-- ============================================================

BEGIN;

-- ════════════════════════════════════════════════════════════
-- ١. الأنشطة الميدانية والزيارات
-- ════════════════════════════════════════════════════════════
TRUNCATE TABLE visit_checklist_responses  CASCADE;
TRUNCATE TABLE call_details               CASCADE;
TRUNCATE TABLE activities                 CASCADE;
TRUNCATE TABLE visit_plan_items           CASCADE;
TRUNCATE TABLE visit_plans                CASCADE;
TRUNCATE TABLE visit_plan_templates       CASCADE;
TRUNCATE TABLE call_plan_items            CASCADE;
TRUNCATE TABLE call_plans                 CASCADE;
TRUNCATE TABLE call_plan_templates        CASCADE;

-- ════════════════════════════════════════════════════════════
-- ٢. الأهداف والإنجازات
-- ════════════════════════════════════════════════════════════
TRUNCATE TABLE target_adjustments         CASCADE;
TRUNCATE TABLE target_progress            CASCADE;
TRUNCATE TABLE targets                    CASCADE;

-- ════════════════════════════════════════════════════════════
-- ٣. المبيعات
-- ════════════════════════════════════════════════════════════
TRUNCATE TABLE sales_return_items         CASCADE;
TRUNCATE TABLE sales_returns              CASCADE;
TRUNCATE TABLE sales_order_items          CASCADE;
TRUNCATE TABLE sales_orders               CASCADE;

-- ════════════════════════════════════════════════════════════
-- ٤. المشتريات وسندات الصرف
-- ════════════════════════════════════════════════════════════
TRUNCATE TABLE purchase_return_items      CASCADE;
TRUNCATE TABLE purchase_returns           CASCADE;
TRUNCATE TABLE purchase_invoice_items     CASCADE;
TRUNCATE TABLE purchase_invoices          CASCADE;
TRUNCATE TABLE supplier_payment_vouchers  CASCADE;   -- ← جديد: سندات صرف الموردين

-- ════════════════════════════════════════════════════════════
-- ٥. العملاء وبياناتهم التشغيلية
-- ════════════════════════════════════════════════════════════
DELETE FROM price_list_assignments
WHERE entity_type = 'customer';

TRUNCATE TABLE customer_credit_history    CASCADE;
TRUNCATE TABLE customer_opening_balance_audit CASCADE;  -- ← جديد
TRUNCATE TABLE customer_branches          CASCADE;
TRUNCATE TABLE customer_contacts          CASCADE;
TRUNCATE TABLE customer_ledger            CASCADE;
TRUNCATE TABLE customers                  CASCADE;

-- ════════════════════════════════════════════════════════════
-- ٦. الموردون وبياناتهم التشغيلية
-- ════════════════════════════════════════════════════════════
TRUNCATE TABLE supplier_opening_balance_audit CASCADE;  -- ← جديد
TRUNCATE TABLE supplier_payment_reminders CASCADE;
TRUNCATE TABLE supplier_contacts          CASCADE;
TRUNCATE TABLE supplier_ledger            CASCADE;
TRUNCATE TABLE suppliers                  CASCADE;

-- ════════════════════════════════════════════════════════════
-- ٧. المالية والمحاسبة
-- ════════════════════════════════════════════════════════════
TRUNCATE TABLE journal_entry_lines        CASCADE;
TRUNCATE TABLE journal_entries            CASCADE;
TRUNCATE TABLE payment_receipts           CASCADE;
TRUNCATE TABLE expenses                   CASCADE;

-- ════════════════════════════════════════════════════════════
-- ٨. الخزائن والعهد — الحركات فقط
-- ════════════════════════════════════════════════════════════
TRUNCATE TABLE custody_transactions       CASCADE;
TRUNCATE TABLE vault_transactions         CASCADE;

-- ════════════════════════════════════════════════════════════
-- ٩. المخزون — الحركات والتسويات والتحويلات والدُّفعات
-- ════════════════════════════════════════════════════════════
TRUNCATE TABLE stock_adjustment_items     CASCADE;
TRUNCATE TABLE stock_adjustments          CASCADE;
TRUNCATE TABLE stock_transfer_items       CASCADE;
TRUNCATE TABLE stock_transfers            CASCADE;
TRUNCATE TABLE stock_movements            CASCADE;
TRUNCATE TABLE stock_batches              CASCADE;

-- ════════════════════════════════════════════════════════════
-- ١٠. الموارد البشرية — البيانات التشغيلية
-- ════════════════════════════════════════════════════════════

-- أ. الرواتب والاقتطاعات
TRUNCATE TABLE hr_payroll_adjustments     CASCADE;
TRUNCATE TABLE hr_commission_records      CASCADE;
TRUNCATE TABLE hr_commission_targets      CASCADE;
TRUNCATE TABLE hr_payroll_lines           CASCADE;
TRUNCATE TABLE hr_payroll_runs            CASCADE;
TRUNCATE TABLE hr_payroll_periods         CASCADE;

-- ب. السلف والأقساط
TRUNCATE TABLE hr_advance_installments    CASCADE;
TRUNCATE TABLE hr_advances                CASCADE;

-- ج. الإجازات والصلاحيات والعقوبات
TRUNCATE TABLE hr_permission_requests     CASCADE;
TRUNCATE TABLE hr_leave_requests          CASCADE;
TRUNCATE TABLE hr_leave_balances          CASCADE;
TRUNCATE TABLE hr_penalty_instances       CASCADE;

-- د. الحضور والتنبيهات
TRUNCATE TABLE hr_attendance_alerts       CASCADE;   -- ← جديد
TRUNCATE TABLE hr_attendance_logs         CASCADE;
TRUNCATE TABLE hr_attendance_days         CASCADE;

-- هـ. بيانات الموظف الأساسية
TRUNCATE TABLE hr_employee_documents      CASCADE;
TRUNCATE TABLE hr_delegations             CASCADE;
TRUNCATE TABLE hr_salary_history          CASCADE;
TRUNCATE TABLE hr_contracts               CASCADE;
TRUNCATE TABLE hr_employees               CASCADE;

-- ════════════════════════════════════════════════════════════
-- ١١. الإشعارات والتنبيهات التشغيلية
-- ════════════════════════════════════════════════════════════
TRUNCATE TABLE notification_alert_state   CASCADE;   -- ← جديد: حالة التنبيهات

-- ════════════════════════════════════════════════════════════
-- ١٢. تصفير أرصدة المخزون
-- ════════════════════════════════════════════════════════════
UPDATE stock
SET quantity          = 0,
    reserved_quantity = 0;

-- ════════════════════════════════════════════════════════════
-- ١٣. تصفير أرصدة الخزائن والعهد
-- ════════════════════════════════════════════════════════════
UPDATE vaults
SET current_balance = 0;

UPDATE custody_accounts
SET current_balance = 0;

-- ════════════════════════════════════════════════════════════
-- ١٤. إعادة تعيين كل التسلسلات (Sequences)
-- ════════════════════════════════════════════════════════════

-- المبيعات
ALTER SEQUENCE IF EXISTS sales_order_seq              RESTART WITH 1;
ALTER SEQUENCE IF EXISTS sales_return_seq             RESTART WITH 1;

-- المشتريات
ALTER SEQUENCE IF EXISTS purchase_invoice_seq         RESTART WITH 1;
ALTER SEQUENCE IF EXISTS purchase_return_seq          RESTART WITH 1;
ALTER SEQUENCE IF EXISTS supplier_payment_voucher_seq RESTART WITH 1;  -- ← جديد

-- العملاء والموردون
ALTER SEQUENCE IF EXISTS customer_code_seq            RESTART WITH 1;
ALTER SEQUENCE IF EXISTS supplier_code_seq            RESTART WITH 1;

-- المالية
ALTER SEQUENCE IF EXISTS payment_receipt_seq          RESTART WITH 1;
ALTER SEQUENCE IF EXISTS expense_seq                  RESTART WITH 1;
ALTER SEQUENCE IF EXISTS journal_entry_seq            RESTART WITH 1;

-- المخزون
ALTER SEQUENCE IF EXISTS transfer_number_seq          RESTART WITH 1;
ALTER SEQUENCE IF EXISTS adjustment_number_seq        RESTART WITH 1;

-- الموارد البشرية
ALTER SEQUENCE IF EXISTS hr_employee_number_seq       RESTART WITH 1;
ALTER SEQUENCE IF EXISTS hr_payroll_run_seq           RESTART WITH 1;
ALTER SEQUENCE IF EXISTS hr_advance_seq               RESTART WITH 1;

COMMIT;

-- ════════════════════════════════════════════════════════════
-- ✅ اكتمل تفريغ البيانات التشغيلية
-- الجداول المرجعية والإعدادية محفوظة كما هي
-- ════════════════════════════════════════════════════════════
