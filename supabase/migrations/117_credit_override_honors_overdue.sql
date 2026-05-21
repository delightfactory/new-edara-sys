-- 117_credit_override_honors_overdue.sql
-- Purpose:
--   Keep the strict overdue/limit credit policy, but let callers that already
--   check sales.orders.override_credit decide whether to bypass it.
--
-- Root cause:
--   check_credit_available raised an exception for overdue invoices before
--   confirm_sales_order / deliver_sales_order could inspect the override
--   permission. Returning false preserves the block for normal users and lets
--   the existing permission gates work.

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
  SELECT credit_limit, credit_days, COALESCE(current_balance, 0)
  INTO v_limit, v_days, v_balance
  FROM customers
  WHERE id = p_customer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'العميل غير موجود';
  END IF;

  IF COALESCE(v_limit, 0) = 0 THEN
    RETURN false;
  END IF;

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
        RETURN false;
      END IF;
    END IF;
  END IF;

  RETURN (v_balance + p_amount) <= v_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION check_credit_available(UUID, NUMERIC) TO authenticated;
