-- ============================================================
-- 12_fix_ledger_source_type.sql
-- إصلاح: customer_ledger_source_type_check
--
-- المشكلة:
--   allocate_payment_to_invoices تُدرج source_type = 'payment_receipt'
--   لكن الـ CHECK constraint يقبل فقط:
--   'sales_order', 'sales_return', 'payment', 'opening_balance', 'adjustment'
--
-- الإصلاح: توسيع القيد ليشمل 'payment_receipt'
-- ============================================================

ALTER TABLE customer_ledger
  DROP CONSTRAINT IF EXISTS customer_ledger_source_type_check;

ALTER TABLE customer_ledger
  ADD CONSTRAINT customer_ledger_source_type_check
  CHECK (source_type IN (
    'sales_order',
    'sales_return',
    'payment',
    'payment_receipt',   -- ← الإضافة الجديدة
    'opening_balance',
    'adjustment'
  ));
