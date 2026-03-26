-- ═══════════════════════════════════════════════════════════
-- Hotfix: إصلاح تريجرات الرصيد الافتتاحي
-- المشكلة: ON CONFLICT (source_type, source_id) يتطلب UNIQUE constraint
--          الذي تم حذفه لدعم allocate_payment_to_invoices
-- الحل:    استبدال ON CONFLICT بـ NOT EXISTS (آمن + idempotent)
-- ═══════════════════════════════════════════════════════════

-- ١. إصلاح تريجر الرصيد الافتتاحي للعملاء
CREATE OR REPLACE FUNCTION sync_customer_opening_balance()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(NEW.opening_balance, 0) > 0 THEN
    -- تحقق: لم يُسجّل سابقاً (idempotent بدون UNIQUE)
    IF NOT EXISTS (
      SELECT 1 FROM customer_ledger
      WHERE source_type = 'opening_balance' AND source_id = NEW.id
    ) THEN
      INSERT INTO customer_ledger (
        customer_id, type, amount, source_type, source_id,
        description, created_by
      ) VALUES (
        NEW.id, 'debit', NEW.opening_balance,
        'opening_balance', NEW.id,
        'رصيد افتتاحي',
        NEW.created_by
      );
    END IF;
  END IF;
  RETURN NEW;
END; $$;

-- ٢. إصلاح تريجر الرصيد الافتتاحي للموردين
CREATE OR REPLACE FUNCTION sync_supplier_opening_balance()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(NEW.opening_balance, 0) > 0 THEN
    IF NOT EXISTS (
      SELECT 1 FROM supplier_ledger
      WHERE source_type = 'opening_balance' AND source_id = NEW.id
    ) THEN
      INSERT INTO supplier_ledger (
        supplier_id, type, amount, source_type, source_id,
        description, created_by
      ) VALUES (
        NEW.id, 'credit', NEW.opening_balance,
        'opening_balance', NEW.id,
        'رصيد افتتاحي',
        NEW.created_by
      );
    END IF;
  END IF;
  RETURN NEW;
END; $$;

-- ٣. تصحيح الأرصدة المضاعفة (عملاء أُنشئوا قبل حذف التريجر القديم)
UPDATE customers
SET current_balance = opening_balance
WHERE current_balance = opening_balance * 2
  AND opening_balance > 0;
