-- Production schema snapshot primitives
-- Source: NEW-EDARA-SYS production, captured read-only on 2026-08-07.
-- Scope: application-owned schemas only (public, analytics, private).
-- Supabase-managed schemas (auth, storage, realtime, cron, vault internals, etc.)
-- are provided by the isolated local Supabase runtime and are not dumped here.

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_min_messages = warning;

CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS private;
CREATE SCHEMA IF NOT EXISTS public;

-- Application extensions currently enabled in production. The local Supabase
-- runtime already supplies Supabase-managed extensions; IF NOT EXISTS keeps this
-- snapshot idempotent against that baseline.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;

CREATE TYPE public.delivery_method AS ENUM ('direct', 'shipping', 'pickup');
CREATE TYPE public.hr_advance_status AS ENUM ('pending_supervisor', 'pending_hr', 'pending_finance', 'approved', 'rejected', 'paid', 'fully_repaid', 'cancelled');
CREATE TYPE public.hr_advance_type AS ENUM ('instant', 'scheduled');
CREATE TYPE public.hr_attendance_status AS ENUM ('present', 'late', 'half_day', 'absent_unauthorized', 'absent_authorized', 'on_leave', 'weekly_off', 'public_holiday');
CREATE TYPE public.hr_checkout_status AS ENUM ('on_time', 'early_authorized', 'early_unauthorized', 'overtime', 'auto');
CREATE TYPE public.hr_contract_type AS ENUM ('permanent', 'fixed_term', 'part_time', 'freelance', 'probation');
CREATE TYPE public.hr_day_of_week AS ENUM ('saturday', 'sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday');
CREATE TYPE public.hr_deduction_type AS ENUM ('none', 'warning', 'quarter_day', 'half_day', 'full_day', 'custom_minutes');
CREATE TYPE public.hr_document_type AS ENUM ('national_id', 'passport', 'driving_license', 'employment_contract', 'educational_certificate', 'social_insurance', 'medical_certificate', 'other');
CREATE TYPE public.hr_employee_status AS ENUM ('active', 'on_leave', 'suspended', 'terminated');
CREATE TYPE public.hr_gender AS ENUM ('male', 'female');
CREATE TYPE public.hr_installment_status AS ENUM ('pending', 'deducted', 'deferred', 'skipped');
CREATE TYPE public.hr_leave_request_status AS ENUM ('draft', 'pending_supervisor', 'approved_supervisor', 'pending_hr', 'approved', 'rejected', 'cancelled');
CREATE TYPE public.hr_marital_status AS ENUM ('single', 'married', 'divorced', 'widowed');
CREATE TYPE public.hr_payroll_run_status AS ENUM ('draft', 'calculating', 'review', 'approved', 'paid', 'cancelled');
CREATE TYPE public.hr_penalty_type AS ENUM ('late', 'absent_unauthorized', 'early_leave_unauthorized', 'out_of_range');
CREATE TYPE public.hr_review_status AS ENUM ('ok', 'needs_review', 'reviewed');
CREATE TYPE public.notification_category AS ENUM ('system', 'hr_attendance', 'hr_payroll', 'hr_leaves', 'finance_expenses', 'finance_approvals', 'inventory', 'sales', 'procurement', 'tasks', 'alerts');
CREATE TYPE public.notification_delivery_channel AS ENUM ('in_app', 'push', 'email');
CREATE TYPE public.notification_delivery_status AS ENUM ('sent', 'delivered', 'clicked', 'dismissed', 'failed', 'skipped');
CREATE TYPE public.notification_priority AS ENUM ('low', 'medium', 'high', 'critical');
CREATE TYPE public.payment_method AS ENUM ('cash', 'bank_transfer', 'instapay', 'cheque', 'wallet');
CREATE TYPE public.sales_order_status AS ENUM ('draft', 'confirmed', 'partially_delivered', 'delivered', 'completed', 'cancelled');
CREATE TYPE public.sales_return_status AS ENUM ('draft', 'confirmed', 'cancelled');
CREATE TYPE public.user_status AS ENUM ('active', 'inactive', 'suspended');

CREATE SEQUENCE public.adjustment_number_seq AS bigint START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 NO CYCLE;
CREATE SEQUENCE public.customer_code_seq AS bigint START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 NO CYCLE;
CREATE SEQUENCE public.expense_seq AS bigint START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 NO CYCLE;
CREATE SEQUENCE public.hr_advance_seq AS bigint START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 NO CYCLE;
CREATE SEQUENCE public.hr_employee_number_seq AS bigint START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 NO CYCLE;
CREATE SEQUENCE public.hr_payroll_run_seq AS bigint START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 NO CYCLE;
CREATE SEQUENCE public.journal_entry_seq AS bigint START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 NO CYCLE;
CREATE SEQUENCE public.payment_receipt_seq AS bigint START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 NO CYCLE;
CREATE SEQUENCE public.purchase_invoice_seq AS bigint START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 NO CYCLE;
CREATE SEQUENCE public.purchase_return_seq AS bigint START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 NO CYCLE;
CREATE SEQUENCE public.sales_order_seq AS bigint START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 NO CYCLE;
CREATE SEQUENCE public.sales_return_seq AS bigint START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 NO CYCLE;
CREATE SEQUENCE public.supplier_code_seq AS bigint START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 NO CYCLE;
CREATE SEQUENCE public.supplier_payment_voucher_seq AS bigint START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 NO CYCLE;
CREATE SEQUENCE public.transfer_number_seq AS bigint START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 NO CYCLE;
