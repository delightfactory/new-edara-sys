-- ============================================================
-- Migration 20d: إصلاح CHECK constraint لـ source_type في journal_entries
-- إضافة 'hr_advance' و 'hr_payroll' للقائمة المسموحة
-- ============================================================

ALTER TABLE journal_entries DROP CONSTRAINT IF EXISTS journal_entries_source_type_check;

ALTER TABLE journal_entries ADD CONSTRAINT journal_entries_source_type_check
  CHECK (source_type IN (
    'sales_order',
    'sales_return',
    'payment',
    'purchase_order',
    'purchase_return',
    'purchase_cancellation',  -- موجود في البيانات الحالية
    'expense',
    'custody',
    'transfer',
    'manual',
    'hr_advance',
    'hr_payroll'
  ));
