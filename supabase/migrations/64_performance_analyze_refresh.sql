-- ============================================================
-- 64_performance_analyze_refresh.sql
-- تحديث إحصائيات قاعدة البيانات لجميع الجداول الفعلية
--
-- المشكلة:
--   آخر ANALYZE شامل كان في Migration 03g
--   تمت إضافة عشرات الجداول الجديدة منذ ذلك الحين
--   بدون ANALYZE = PostgreSQL يستخدم تقديرات قديمة في خطط الاستعلام
--
-- الحل:
--   ANALYZE شامل لكل الجداول الموجودة فعلاً في قاعدة البيانات
--   هذا لا يُغيّر أي بيانات — فقط يُحدّث الإحصائيات
--
-- المصدر: pg_policies snapshot (2026-04-04) — أسماء الجداول مُتحقَّق منها
-- Idempotent: آمن للتشغيل المتكرر
-- ============================================================

-- ─── المالية ──────────────────────────────────────────────
ANALYZE journal_entries;
ANALYZE journal_entry_lines;
ANALYZE customer_ledger;
ANALYZE supplier_ledger;
ANALYZE vault_transactions;
ANALYZE custody_transactions;
ANALYZE custody_accounts;
ANALYZE vaults;
ANALYZE payment_receipts;
ANALYZE expenses;
ANALYZE expense_categories;

-- ─── المبيعات ──────────────────────────────────────────────
ANALYZE sales_orders;
ANALYZE sales_order_items;
ANALYZE sales_returns;
ANALYZE sales_return_items;

-- ─── المشتريات ─────────────────────────────────────────────
ANALYZE purchase_invoices;
ANALYZE purchase_invoice_items;
ANALYZE purchase_returns;
ANALYZE purchase_return_items;
ANALYZE supplier_payment_vouchers;

-- ─── الموارد البشرية ───────────────────────────────────────
ANALYZE hr_employees;
ANALYZE hr_attendance_days;
ANALYZE hr_attendance_logs;
ANALYZE hr_attendance_alerts;
ANALYZE hr_leave_requests;
ANALYZE hr_leave_balances;
ANALYZE hr_leave_types;
ANALYZE hr_advances;
ANALYZE hr_advance_installments;
ANALYZE hr_payroll_runs;
ANALYZE hr_payroll_lines;
ANALYZE hr_payroll_periods;
ANALYZE hr_payroll_adjustments;
ANALYZE hr_commission_records;
ANALYZE hr_commission_targets;
ANALYZE hr_salary_history;
ANALYZE hr_contracts;
ANALYZE hr_delegations;
ANALYZE hr_departments;
ANALYZE hr_positions;
ANALYZE hr_penalty_instances;
ANALYZE hr_penalty_rules;
ANALYZE hr_permission_requests;
ANALYZE hr_public_holidays;
ANALYZE hr_work_locations;
ANALYZE hr_employee_documents;

-- ─── نظام الإشعارات ────────────────────────────────────────
ANALYZE notifications;
ANALYZE notification_preferences;
ANALYZE notification_delivery_log;
ANALYZE notification_event_types;
ANALYZE push_subscriptions;

-- ─── الأنشطة الميدانية ─────────────────────────────────────
ANALYZE activities;
ANALYZE call_details;
ANALYZE visit_plans;
ANALYZE visit_plan_items;
ANALYZE visit_plan_templates;
ANALYZE call_plans;
ANALYZE call_plan_items;
ANALYZE call_plan_templates;
ANALYZE visit_checklist_templates;
ANALYZE visit_checklist_questions;
ANALYZE visit_checklist_responses;

-- ─── الأهداف ───────────────────────────────────────────────
ANALYZE targets;
ANALYZE target_types;
ANALYZE target_customers;
ANALYZE target_progress;
ANALYZE target_adjustments;
ANALYZE target_reward_tiers;
ANALYZE target_reward_payouts;
ANALYZE target_payout_clawbacks;

-- ─── المنتجات والمخزون ─────────────────────────────────────
ANALYZE products;
ANALYZE product_categories;
ANALYZE product_units;
ANALYZE product_bundles;
ANALYZE product_bundle_items;
ANALYZE units;
ANALYZE brands;
ANALYZE stock;
ANALYZE stock_batches;
ANALYZE stock_transfers;
ANALYZE stock_transfer_items;
ANALYZE stock_adjustments;
ANALYZE stock_adjustment_items;
ANALYZE stock_movements;
ANALYZE warehouses;
ANALYZE warehouse_managers;

-- ─── العملاء والموردون ─────────────────────────────────────
ANALYZE customers;
ANALYZE customer_branches;
ANALYZE customer_contacts;
ANALYZE customer_credit_history;
ANALYZE suppliers;
ANALYZE supplier_contacts;
ANALYZE supplier_ledger;
ANALYZE supplier_payment_reminders;

-- ─── قوائم الأسعار ─────────────────────────────────────────
ANALYZE price_lists;
ANALYZE price_list_items;
ANALYZE price_list_assignments;

-- ─── الصلاحيات والمستخدمون ─────────────────────────────────
ANALYZE user_roles;
ANALYZE roles;
ANALYZE role_permissions;
ANALYZE user_permission_overrides;
ANALYZE profiles;

-- ─── الإعدادات والبنية الأساسية ────────────────────────────
ANALYZE branches;
ANALYZE areas;
ANALYZE cities;
ANALYZE governorates;
ANALYZE company_settings;
ANALYZE approval_rules;
ANALYZE activity_types;
ANALYZE feature_flags;
ANALYZE shipping_companies;
ANALYZE chart_of_accounts;
ANALYZE audit_logs;
