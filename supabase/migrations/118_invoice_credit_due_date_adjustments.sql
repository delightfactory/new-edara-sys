-- 118_invoice_credit_due_date_adjustments.sql
-- Purpose:
--   Allow authorized credit managers to adjust the credit duration for a
--   specific delivered sales invoice by updating sales_orders.due_date only.
--
-- Safety rules:
--   - Do not touch confirm_sales_order() or deliver_sales_order().
--   - Do not touch ledger, journals, stock, receipts, customer balances, or
--     customers.credit_days.
--   - Keep existing function signatures intact when redefining existing RPCs.
--   - Preserve the credit override behavior introduced in migration 117:
--     check_credit_available returns false for credit policy blocks instead of
--     raising an exception.

CREATE TABLE IF NOT EXISTS public.sales_order_due_date_history (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id        UUID NOT NULL REFERENCES public.sales_orders(id) ON DELETE CASCADE,
  customer_id     UUID NOT NULL REFERENCES public.customers(id),
  old_due_date    DATE,
  new_due_date    DATE NOT NULL,
  old_credit_days INTEGER,
  new_credit_days INTEGER NOT NULL,
  changed_by      UUID NOT NULL REFERENCES public.profiles(id),
  reason          TEXT NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT sales_order_due_date_history_reason_not_blank
    CHECK (length(btrim(reason)) > 0),
  CONSTRAINT sales_order_due_date_history_new_credit_days_nonnegative
    CHECK (new_credit_days >= 0)
);

CREATE INDEX IF NOT EXISTS idx_soddh_order_created
  ON public.sales_order_due_date_history(order_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_soddh_customer_created
  ON public.sales_order_due_date_history(customer_id, created_at DESC);

ALTER TABLE public.sales_order_due_date_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "sales_order_due_date_history_select" ON public.sales_order_due_date_history;
CREATE POLICY "sales_order_due_date_history_select"
  ON public.sales_order_due_date_history
  FOR SELECT
  USING (
    public.check_permission(auth.uid(), 'customers.credit.update')
    OR public.check_permission(auth.uid(), 'settings.audit.read')
    OR public.check_permission(auth.uid(), '*')
  );

REVOKE ALL ON public.sales_order_due_date_history FROM PUBLIC;
GRANT SELECT ON public.sales_order_due_date_history TO authenticated;

CREATE OR REPLACE FUNCTION public.update_sales_order_due_date(
  p_order_id     UUID,
  p_credit_days  INTEGER,
  p_reason       TEXT
) RETURNS JSONB
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_order           sales_orders%ROWTYPE;
  v_user_id         UUID := auth.uid();
  v_old_due_date    DATE;
  v_new_due_date    DATE;
  v_old_credit_days INTEGER;
  v_remaining       NUMERIC;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: authentication required';
  END IF;

  IF NOT check_permission(v_user_id, 'customers.credit.update') THEN
    RAISE EXCEPTION 'غير مصرح: يتطلب صلاحية إدارة الائتمان';
  END IF;

  IF p_credit_days IS NULL OR p_credit_days < 0 OR p_credit_days > 3650 THEN
    RAISE EXCEPTION 'مدة الائتمان يجب أن تكون بين 0 و 3650 يوم';
  END IF;

  IF p_reason IS NULL OR length(btrim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'سبب تعديل مدة الائتمان مطلوب';
  END IF;

  SELECT * INTO v_order
  FROM sales_orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'فاتورة البيع غير موجودة';
  END IF;

  IF v_order.status::text NOT IN ('delivered', 'partially_delivered') THEN
    RAISE EXCEPTION 'لا يمكن تعديل مدة الائتمان إلا لفاتورة مسلمة ومفتوحة';
  END IF;

  IF COALESCE(v_order.payment_terms, 'cash') NOT IN ('credit', 'mixed') THEN
    RAISE EXCEPTION 'لا يمكن تعديل مدة الائتمان لفاتورة نقدية';
  END IF;

  IF v_order.delivered_at IS NULL THEN
    RAISE EXCEPTION 'لا يمكن تعديل مدة الائتمان قبل تسجيل تاريخ التسليم';
  END IF;

  v_remaining :=
    COALESCE(v_order.total_amount, 0)
    - COALESCE(v_order.paid_amount, 0)
    - COALESCE(v_order.returned_amount, 0);

  IF v_remaining <= 0 THEN
    RAISE EXCEPTION 'لا يمكن تعديل مدة الائتمان لفاتورة مكتملة السداد';
  END IF;

  v_old_due_date := v_order.due_date;
  v_new_due_date := v_order.delivered_at::date + p_credit_days;
  v_old_credit_days := CASE
    WHEN v_old_due_date IS NULL THEN NULL
    ELSE v_old_due_date - v_order.delivered_at::date
  END;

  IF v_old_due_date IS NOT DISTINCT FROM v_new_due_date THEN
    RETURN jsonb_build_object(
      'order_id', v_order.id,
      'old_due_date', v_old_due_date,
      'new_due_date', v_new_due_date,
      'old_credit_days', v_old_credit_days,
      'new_credit_days', p_credit_days,
      'changed', false
    );
  END IF;

  UPDATE sales_orders
  SET due_date = v_new_due_date,
      updated_at = now()
  WHERE id = v_order.id;

  INSERT INTO sales_order_due_date_history (
    order_id,
    customer_id,
    old_due_date,
    new_due_date,
    old_credit_days,
    new_credit_days,
    changed_by,
    reason
  ) VALUES (
    v_order.id,
    v_order.customer_id,
    v_old_due_date,
    v_new_due_date,
    v_old_credit_days,
    p_credit_days,
    v_user_id,
    btrim(p_reason)
  );

  IF v_new_due_date >= CURRENT_DATE THEN
    UPDATE notification_alert_state
    SET resolved_at = now()
    WHERE alert_key = 'sales.invoice.overdue::' || v_order.id::text
      AND event_key = 'sales.invoice.overdue'
      AND resolved_at IS NULL;
  END IF;

  RETURN jsonb_build_object(
    'order_id', v_order.id,
    'old_due_date', v_old_due_date,
    'new_due_date', v_new_due_date,
    'old_credit_days', v_old_credit_days,
    'new_credit_days', p_credit_days,
    'changed', true
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_sales_order_due_date(UUID, INTEGER, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_sales_order_due_date(UUID, INTEGER, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.check_credit_available(
  p_customer_id UUID,
  p_amount      NUMERIC
) RETURNS BOOLEAN
  LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_limit       NUMERIC;
  v_days        INTEGER;
  v_balance     NUMERIC;
  v_has_overdue BOOLEAN := false;
  v_strict      BOOLEAN;
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

  SELECT EXISTS (
    SELECT 1
    FROM sales_orders so
    WHERE so.customer_id = p_customer_id
      AND so.status IN ('delivered', 'partially_delivered')
      AND COALESCE(so.payment_terms, 'cash') IN ('credit', 'mixed')
      AND so.delivered_at IS NOT NULL
      AND GREATEST(
            0,
            COALESCE(so.total_amount, 0)
            - COALESCE(so.paid_amount, 0)
            - COALESCE(so.returned_amount, 0)
          ) > 0
      AND so.due_date IS NOT NULL
      AND so.due_date < CURRENT_DATE
  ) INTO v_has_overdue;

  IF v_has_overdue AND v_balance > 0 THEN
    SELECT COALESCE(value::boolean, true) INTO v_strict
    FROM company_settings WHERE key = 'sales.credit_check_strict';

    IF COALESCE(v_strict, true) THEN
      RETURN false;
    END IF;
  END IF;

  RETURN (v_balance + p_amount) <= v_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_credit_available(UUID, NUMERIC) TO authenticated;

CREATE OR REPLACE FUNCTION public.check_customer_credit(
  p_customer_id UUID,
  p_amount      NUMERIC
) RETURNS JSONB
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_cust            RECORD;
  v_available       NUMERIC := 0;
  v_overdue_days    INTEGER := 0;
  v_oldest_invoice  TEXT := NULL;
  v_overdue_count   BIGINT := 0;
BEGIN
  SELECT
    c.name,
    c.payment_terms,
    COALESCE(c.credit_limit, 0) AS credit_limit,
    COALESCE(c.credit_days, 0) AS credit_days,
    COALESCE(c.current_balance, 0) AS current_balance
  INTO v_cust
  FROM customers c
  WHERE c.id = p_customer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'العميل غير موجود: %', p_customer_id;
  END IF;

  v_available := v_cust.credit_limit - v_cust.current_balance;

  SELECT
    COUNT(*) AS cnt,
    COALESCE(MAX(CURRENT_DATE - so.due_date), 0) AS max_days,
    MIN(so.order_number) AS oldest
  INTO v_overdue_count, v_overdue_days, v_oldest_invoice
  FROM sales_orders so
  WHERE so.customer_id = p_customer_id
    AND so.status IN ('delivered', 'partially_delivered')
    AND so.delivered_at IS NOT NULL
    AND GREATEST(
          0,
          COALESCE(so.total_amount, 0)
          - COALESCE(so.paid_amount, 0)
          - COALESCE(so.returned_amount, 0)
        ) > 0
    AND so.due_date IS NOT NULL
    AND so.due_date < CURRENT_DATE;

  RETURN jsonb_build_object(
    'customer_name',    v_cust.name,
    'payment_terms',    v_cust.payment_terms,
    'credit_limit',     v_cust.credit_limit,
    'current_balance',  v_cust.current_balance,
    'available_credit', v_available,
    'requested_amount', p_amount,
    'can_use_credit',   (v_cust.payment_terms <> 'cash'),
    'credit_ok',        (v_available >= p_amount AND v_cust.payment_terms <> 'cash'),
    'exceeds_limit',    (v_available < p_amount),
    'overdue_count',    COALESCE(v_overdue_count, 0),
    'overdue_days',     COALESCE(v_overdue_days, 0),
    'oldest_invoice',   v_oldest_invoice,
    'has_overdue',      (COALESCE(v_overdue_count, 0) > 0)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_customer_credit(UUID, NUMERIC) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_overdue_batch(
  p_customer_ids UUID[]
) RETURNS TABLE (
  customer_id   UUID,
  overdue_count BIGINT,
  has_overdue   BOOLEAN
)
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO 'public'
  STABLE
AS $$
  SELECT
    c.id AS customer_id,
    COUNT(so.id) AS overdue_count,
    COUNT(so.id) > 0 AS has_overdue
  FROM customers c
  LEFT JOIN sales_orders so
         ON so.customer_id = c.id
        AND so.status IN ('delivered', 'partially_delivered')
        AND so.delivered_at IS NOT NULL
        AND GREATEST(
              0,
              COALESCE(so.total_amount, 0)
              - COALESCE(so.paid_amount, 0)
              - COALESCE(so.returned_amount, 0)
            ) > 0
        AND so.due_date IS NOT NULL
        AND so.due_date < CURRENT_DATE
  WHERE c.id = ANY(p_customer_ids)
  GROUP BY c.id;
$$;

GRANT EXECUTE ON FUNCTION public.get_overdue_batch(UUID[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_credit_open_orders_v2(
  p_customer_id UUID
) RETURNS TABLE (
  id                  UUID,
  order_number        TEXT,
  total_amount        NUMERIC,
  paid_amount         NUMERIC,
  returned_amount     NUMERIC,
  delivered_at        TIMESTAMPTZ,
  due_date            DATE,
  status              TEXT,
  net_remaining       NUMERIC,
  days_since_delivery INTEGER,
  credit_days_effective INTEGER,
  days_overdue        INTEGER
)
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO 'public'
  STABLE
AS $$
  SELECT
    so.id,
    so.order_number,
    so.total_amount,
    so.paid_amount,
    COALESCE(so.returned_amount, 0) AS returned_amount,
    so.delivered_at,
    so.due_date AS due_date,
    so.status::text AS status,
    (
      COALESCE(so.total_amount, 0)
      - COALESCE(so.paid_amount, 0)
      - COALESCE(so.returned_amount, 0)
    ) AS net_remaining,
    (CURRENT_DATE - so.delivered_at::date)::integer AS days_since_delivery,
    CASE
      WHEN so.due_date IS NULL THEN NULL
      ELSE (so.due_date - so.delivered_at::date)::integer
    END AS credit_days_effective,
    CASE
      WHEN so.due_date IS NULL THEN 0
      ELSE GREATEST(0, CURRENT_DATE - so.due_date)::integer
    END AS days_overdue
  FROM sales_orders so
  JOIN customers c ON c.id = so.customer_id
  WHERE so.customer_id = p_customer_id
    AND so.status IN ('delivered', 'partially_delivered')
    AND so.delivered_at IS NOT NULL
    AND (
      COALESCE(so.total_amount, 0)
      - COALESCE(so.paid_amount, 0)
      - COALESCE(so.returned_amount, 0)
    ) > 0
  ORDER BY so.delivered_at DESC;
$$;

REVOKE EXECUTE ON FUNCTION public.get_credit_open_orders_v2(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_credit_open_orders_v2(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_filtered_credit_customers(
    p_search TEXT DEFAULT NULL,
    p_payment_terms TEXT DEFAULT NULL,
    p_rep_id UUID DEFAULT NULL,
    p_balance_state TEXT DEFAULT 'all',
    p_current_balance_min NUMERIC DEFAULT NULL,
    p_current_balance_max NUMERIC DEFAULT NULL,
    p_credit_limit_min NUMERIC DEFAULT NULL,
    p_credit_limit_max NUMERIC DEFAULT NULL,
    p_sort_by TEXT DEFAULT 'name',
    p_limit INT DEFAULT 25,
    p_offset INT DEFAULT 0
) RETURNS TABLE (
    id UUID,
    code TEXT,
    name TEXT,
    payment_terms TEXT,
    credit_limit NUMERIC,
    credit_days INT,
    current_balance NUMERIC,
    is_active BOOLEAN,
    assigned_rep_id UUID,
    assigned_rep JSON,
    available_balance NUMERIC,
    utilization_pct NUMERIC,
    overdue_count INT,
    total_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT check_permission(auth.uid(), 'customers.read') AND NOT check_permission(auth.uid(), 'customers.read_all') THEN
        RAISE EXCEPTION 'Unauthorized: Requires customers.read or customers.read_all permission';
    END IF;

    RETURN QUERY
    WITH base_customers AS (
        SELECT
            c.id, c.code, c.name, c.payment_terms, c.credit_limit, c.credit_days, c.current_balance, c.is_active, c.assigned_rep_id,
            CASE
                WHEN c.assigned_rep_id IS NOT NULL THEN (
                    SELECT json_build_object('id', p.id, 'full_name', p.full_name)
                    FROM profiles p WHERE p.id = c.assigned_rep_id
                )
                ELSE NULL
            END AS assigned_rep,
            GREATEST(0, (c.credit_limit - c.current_balance)) AS available_balance,
            CASE
                WHEN c.credit_limit > 0 THEN (c.current_balance / c.credit_limit)
                ELSE 0
            END AS utilization_pct,
            (SELECT COUNT(*)::INT
             FROM sales_orders so
             WHERE so.customer_id = c.id
               AND so.status IN ('delivered', 'partially_delivered')
               AND so.delivered_at IS NOT NULL
               AND GREATEST(
                    0,
                    COALESCE(so.total_amount, 0)
                    - COALESCE(so.paid_amount, 0)
                    - COALESCE(so.returned_amount, 0)
               ) > 0
               AND so.due_date IS NOT NULL
               AND so.due_date < CURRENT_DATE
            ) AS overdue_count
        FROM customers c
        WHERE c.payment_terms != 'cash'
          AND c.is_active = true
          AND (p_payment_terms IS NULL OR p_payment_terms = '' OR c.payment_terms = p_payment_terms)
          AND (p_rep_id IS NULL OR c.assigned_rep_id = p_rep_id)
          AND (p_search IS NULL OR p_search = '' OR c.name ILIKE '%' || p_search || '%' OR c.code ILIKE '%' || p_search || '%')
    ),
    filtered_customers AS (
        SELECT bc.*
        FROM base_customers bc
        WHERE 1=1
          AND (
               p_balance_state = 'all'
            OR (p_balance_state = 'with-balance-only' AND bc.current_balance > 0)
            OR (p_balance_state = 'near-limit' AND bc.credit_limit > 0 AND bc.utilization_pct >= 0.8 AND bc.utilization_pct <= 1)
            OR (p_balance_state = 'exceeded' AND bc.credit_limit > 0 AND bc.current_balance > bc.credit_limit)
            OR (p_balance_state = 'no-limit' AND bc.credit_limit = 0)
          )
          AND (p_current_balance_min IS NULL OR bc.current_balance >= p_current_balance_min)
          AND (p_current_balance_max IS NULL OR bc.current_balance <= p_current_balance_max)
          AND (p_credit_limit_min IS NULL OR bc.credit_limit >= p_credit_limit_min)
          AND (p_credit_limit_max IS NULL OR bc.credit_limit <= p_credit_limit_max)
    ),
    counted AS (
        SELECT COUNT(*) AS total_count FROM filtered_customers
    )
    SELECT
        fc.id, fc.code, fc.name, fc.payment_terms, fc.credit_limit, fc.credit_days, fc.current_balance, fc.is_active,
        fc.assigned_rep_id, fc.assigned_rep, fc.available_balance, fc.utilization_pct, fc.overdue_count,
        ct.total_count::BIGINT
    FROM filtered_customers fc
    CROSS JOIN counted ct
    ORDER BY
        CASE WHEN p_sort_by = 'name' THEN fc.name END ASC,
        CASE WHEN p_sort_by = 'current_balance_desc' THEN fc.current_balance END DESC,
        CASE WHEN p_sort_by = 'available_asc' THEN fc.available_balance END ASC,
        CASE WHEN p_sort_by = 'utilization_desc' AND fc.credit_limit > 0 THEN fc.utilization_pct END DESC,
        CASE WHEN p_sort_by = 'utilization_desc' AND fc.credit_limit = 0 THEN 0 END DESC,
        CASE WHEN p_sort_by = 'overdue_count_desc' THEN fc.overdue_count END DESC,
        fc.name ASC
    LIMIT COALESCE(p_limit, 25)
    OFFSET COALESCE(p_offset, 0);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_filtered_credit_customers FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_filtered_credit_customers FROM anon;
GRANT EXECUTE ON FUNCTION public.get_filtered_credit_customers TO authenticated;

CREATE OR REPLACE FUNCTION public.get_rep_credit_commitment_report()
RETURNS TABLE (
  rep_id uuid,
  rep_name text,
  is_unassigned boolean,
  sort_order integer,
  portfolio_balance numeric,
  customers_count bigint,
  customers_with_balance bigint,
  overdue_customers_count bigint,
  created_debt numeric,
  confirmed_collections numeric
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH
  all_reps AS (
    SELECT DISTINCT assigned_rep_id AS rep_id
    FROM customers
    WHERE is_active = true
      AND current_balance > 0
      AND assigned_rep_id IS NOT NULL
  ),
  portfolio AS (
    SELECT
      c.assigned_rep_id AS rep_id,
      SUM(c.current_balance) AS portfolio_balance,
      COUNT(*) AS customers_count,
      COUNT(*) FILTER (WHERE c.current_balance > 0) AS customers_with_balance
    FROM customers c
    WHERE c.is_active = true
      AND c.assigned_rep_id IS NOT NULL
    GROUP BY c.assigned_rep_id
  ),
  overdue AS (
    SELECT
      c.assigned_rep_id AS rep_id,
      COUNT(DISTINCT c.id) AS overdue_customers_count
    FROM customers c
    INNER JOIN sales_orders so
           ON so.customer_id = c.id
          AND so.status IN ('delivered', 'partially_delivered')
          AND so.delivered_at IS NOT NULL
          AND GREATEST(
                0,
                COALESCE(so.total_amount, 0)
                - COALESCE(so.paid_amount, 0)
                - COALESCE(so.returned_amount, 0)
              ) > 0
          AND so.due_date IS NOT NULL
          AND so.due_date < CURRENT_DATE
    WHERE c.is_active = true
      AND c.assigned_rep_id IS NOT NULL
    GROUP BY c.assigned_rep_id
  ),
  created AS (
    SELECT
      so.rep_id,
      SUM(
        GREATEST(
          0,
          COALESCE(so.total_amount, 0)
          - COALESCE(so.paid_amount, 0)
          - COALESCE(so.returned_amount, 0)
        )
      ) AS created_debt
    FROM sales_orders so
    WHERE so.rep_id IS NOT NULL
      AND so.status IN ('delivered', 'partially_delivered')
    GROUP BY so.rep_id
  ),
  collections AS (
    SELECT
      pr.collected_by AS rep_id,
      SUM(pr.amount) AS confirmed_collections
    FROM payment_receipts pr
    WHERE pr.status = 'confirmed'
      AND pr.collected_by IS NOT NULL
    GROUP BY pr.collected_by
  ),
  unassigned_portfolio AS (
    SELECT
      SUM(c.current_balance) AS portfolio_balance,
      COUNT(*) AS customers_count,
      COUNT(*) FILTER (WHERE c.current_balance > 0) AS customers_with_balance
    FROM customers c
    WHERE c.is_active = true
      AND c.current_balance > 0
      AND c.assigned_rep_id IS NULL
  ),
  unassigned_overdue AS (
    SELECT COUNT(DISTINCT c.id) AS overdue_customers_count
    FROM customers c
    INNER JOIN sales_orders so
           ON so.customer_id = c.id
          AND so.status IN ('delivered', 'partially_delivered')
          AND so.delivered_at IS NOT NULL
          AND GREATEST(
                0,
                COALESCE(so.total_amount, 0)
                - COALESCE(so.paid_amount, 0)
                - COALESCE(so.returned_amount, 0)
              ) > 0
          AND so.due_date IS NOT NULL
          AND so.due_date < CURRENT_DATE
    WHERE c.is_active = true
      AND c.assigned_rep_id IS NULL
  )
  SELECT
    ar.rep_id,
    COALESCE(pr_prof.full_name, ar.rep_id::text) AS rep_name,
    false AS is_unassigned,
    0 AS sort_order,
    COALESCE(pf.portfolio_balance, 0) AS portfolio_balance,
    COALESCE(pf.customers_count, 0) AS customers_count,
    COALESCE(pf.customers_with_balance, 0) AS customers_with_balance,
    COALESCE(ov.overdue_customers_count, 0) AS overdue_customers_count,
    COALESCE(cr.created_debt, 0) AS created_debt,
    COALESCE(co.confirmed_collections, 0) AS confirmed_collections
  FROM all_reps ar
  LEFT JOIN profiles pr_prof ON pr_prof.id = ar.rep_id
  LEFT JOIN portfolio pf ON pf.rep_id = ar.rep_id
  LEFT JOIN overdue ov ON ov.rep_id = ar.rep_id
  LEFT JOIN created cr ON cr.rep_id = ar.rep_id
  LEFT JOIN collections co ON co.rep_id = ar.rep_id

  UNION ALL

  SELECT
    NULL::uuid AS rep_id,
    'غير مسند' AS rep_name,
    true AS is_unassigned,
    1 AS sort_order,
    COALESCE(up.portfolio_balance, 0) AS portfolio_balance,
    COALESCE(up.customers_count, 0) AS customers_count,
    COALESCE(up.customers_with_balance, 0) AS customers_with_balance,
    COALESCE(uo.overdue_customers_count, 0) AS overdue_customers_count,
    0 AS created_debt,
    0 AS confirmed_collections
  FROM unassigned_portfolio up
  CROSS JOIN unassigned_overdue uo
  WHERE COALESCE(up.portfolio_balance, 0) > 0

  ORDER BY sort_order ASC, portfolio_balance DESC NULLS LAST;
$$;

GRANT EXECUTE ON FUNCTION public.get_rep_credit_commitment_report() TO authenticated;





REVOKE ALL ON TABLE public.sales_order_due_date_history FROM PUBLIC;
REVOKE ALL ON TABLE public.sales_order_due_date_history FROM anon;
REVOKE ALL ON TABLE public.sales_order_due_date_history FROM authenticated;
REVOKE ALL ON TABLE public.sales_order_due_date_history FROM service_role;

GRANT SELECT ON TABLE public.sales_order_due_date_history TO authenticated;

REVOKE EXECUTE ON FUNCTION public.update_sales_order_due_date(UUID, INTEGER, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_sales_order_due_date(UUID, INTEGER, TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.update_sales_order_due_date(UUID, INTEGER, TEXT) FROM service_role;
GRANT EXECUTE ON FUNCTION public.update_sales_order_due_date(UUID, INTEGER, TEXT) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_credit_open_orders_v2(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_credit_open_orders_v2(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_credit_open_orders_v2(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_credit_open_orders_v2(UUID) TO service_role;