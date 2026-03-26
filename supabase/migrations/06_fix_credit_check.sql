-- ============================================================
-- 06_fix_credit_check.sql
-- إصلاح: check_credit_available تستخدم v_customer_balances المحذوفة
-- الحل: استبدالها بـ customers.current_balance (مُخزَّن بـ trigger)
-- ============================================================

CREATE OR REPLACE FUNCTION check_credit_available(
  p_customer_id UUID,
  p_amount      NUMERIC
) RETURNS BOOLEAN
  LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_limit          NUMERIC;
  v_days           INTEGER;
  v_balance        NUMERIC;
  v_oldest_unpaid  DATE;
  v_strict         BOOLEAN;
BEGIN
  -- 1. جلب بيانات العميل الائتمانية + الرصيد المُخزَّن (cached)
  SELECT credit_limit, credit_days, COALESCE(current_balance, 0)
  INTO v_limit, v_days, v_balance
  FROM customers
  WHERE id = p_customer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'العميل غير موجود';
  END IF;

  -- عميل نقدي فقط (بدون ائتمان)
  IF COALESCE(v_limit, 0) = 0 THEN
    RETURN false;
  END IF;

  -- 2. الرصيد الحالي جاهز من customers.current_balance (بدلاً من v_customer_balances المحذوفة)
  -- current_balance يُحدَّث تلقائياً عبر trigger على customer_ledger

  -- 3. فحص هل تجاوز فترة السماح (credit_days)
  IF COALESCE(v_days, 0) > 0 THEN
    SELECT MIN(cl.created_at::date) INTO v_oldest_unpaid
    FROM customer_ledger cl
    WHERE cl.customer_id = p_customer_id
      AND cl.type = 'debit'
      AND cl.source_type = 'sales_order'
      AND cl.created_at > COALESCE(
        (
          SELECT sub.created_at
          FROM (
            SELECT cl2.created_at,
                   SUM(CASE WHEN cl2.type = 'debit' THEN cl2.amount ELSE -cl2.amount END)
                     OVER (ORDER BY cl2.created_at, cl2.id) AS running_balance
            FROM customer_ledger cl2
            WHERE cl2.customer_id = p_customer_id
          ) sub
          WHERE sub.running_balance <= 0
          ORDER BY sub.created_at DESC
          LIMIT 1
        ),
        '1970-01-01'::timestamptz
      );

    IF v_oldest_unpaid IS NOT NULL
       AND v_balance > 0
       AND (CURRENT_DATE - v_oldest_unpaid) > v_days THEN
      SELECT COALESCE(value::boolean, true) INTO v_strict
      FROM company_settings WHERE key = 'sales.credit_check_strict';

      IF COALESCE(v_strict, true) THEN
        RAISE EXCEPTION 'العميل تجاوز فترة السماح (% يوم) — أقدم فاتورة: % — يرجى التسوية أولاً',
          v_days, v_oldest_unpaid;
      END IF;
    END IF;
  END IF;

  -- 4. فحص الحد الائتماني
  RETURN (v_balance + p_amount) <= v_limit;
END; $$;
