-- 119_overdue_sales_invoices_report.sql
-- Purpose:
--   Production-grade overdue sales invoice report.
--   Uses the adjusted sales_orders.due_date as the source of truth and surfaces
--   latest due-date adjustment metadata when available.

CREATE INDEX IF NOT EXISTS idx_sales_orders_overdue_report_v2
  ON public.sales_orders (due_date, customer_id, rep_id, delivered_at DESC)
  INCLUDE (order_number, total_amount, paid_amount, returned_amount, payment_terms, status)
  WHERE status IN ('delivered', 'partially_delivered')
    AND payment_terms IN ('credit', 'mixed')
    AND due_date IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_customers_overdue_report_search
  ON public.customers (assigned_rep_id, is_active, name);

CREATE OR REPLACE FUNCTION public.get_overdue_sales_invoices(
  p_search            TEXT DEFAULT NULL,
  p_rep_id            UUID DEFAULT NULL,
  p_customer_id       UUID DEFAULT NULL,
  p_min_days_overdue  INTEGER DEFAULT NULL,
  p_sort_by           TEXT DEFAULT 'days_overdue_desc',
  p_limit             INTEGER DEFAULT 25,
  p_offset            INTEGER DEFAULT 0
) RETURNS TABLE (
  id                         UUID,
  order_number               TEXT,
  customer_id                UUID,
  customer_code              TEXT,
  customer_name              TEXT,
  assigned_rep_id            UUID,
  assigned_rep_name          TEXT,
  order_rep_id               UUID,
  order_rep_name             TEXT,
  payment_terms              TEXT,
  status                     TEXT,
  total_amount               NUMERIC,
  paid_amount                NUMERIC,
  returned_amount            NUMERIC,
  net_remaining              NUMERIC,
  delivered_at               TIMESTAMPTZ,
  due_date                   DATE,
  credit_days_effective      INTEGER,
  days_since_delivery        INTEGER,
  days_overdue               INTEGER,
  overdue_bucket             TEXT,
  last_due_date_changed_at   TIMESTAMPTZ,
  last_due_date_reason       TEXT,
  total_count                BIGINT,
  total_overdue_amount       NUMERIC,
  overdue_customers_count    BIGINT,
  max_days_overdue           INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
STABLE
AS $$
DECLARE
  v_user_id            UUID := auth.uid();
  v_limit              INTEGER := LEAST(GREATEST(COALESCE(p_limit, 25), 1), 100);
  v_offset             INTEGER := GREATEST(COALESCE(p_offset, 0), 0);
  v_sort_by            TEXT := COALESCE(NULLIF(p_sort_by, ''), 'days_overdue_desc');
  v_can_customers_read BOOLEAN := false;
  v_can_sales_read     BOOLEAN := false;
  v_can_read_all       BOOLEAN := false;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: authentication required';
  END IF;

  v_can_read_all :=
       check_permission(v_user_id, 'customers.read_all')
    OR check_permission(v_user_id, 'sales.orders.read_all')
    OR check_permission(v_user_id, '*');

  v_can_customers_read := check_permission(v_user_id, 'customers.read');
  v_can_sales_read     := check_permission(v_user_id, 'sales.orders.read');

  IF NOT (
    v_can_customers_read
    OR v_can_sales_read
    OR v_can_read_all
  ) THEN
    RAISE EXCEPTION 'Unauthorized: Requires customer or sales read permission';
  END IF;

  RETURN QUERY
  WITH base AS (
    SELECT
      so.id,
      so.order_number::text AS order_number,
      so.customer_id,
      c.code::text AS customer_code,
      c.name::text AS customer_name,
      c.assigned_rep_id,
      assigned_rep.full_name::text AS assigned_rep_name,
      so.rep_id AS order_rep_id,
      order_rep.full_name::text AS order_rep_name,
      so.payment_terms::text AS payment_terms,
      so.status::text AS status,
      COALESCE(so.total_amount, 0) AS total_amount,
      COALESCE(so.paid_amount, 0) AS paid_amount,
      COALESCE(so.returned_amount, 0) AS returned_amount,
      GREATEST(
        0,
        COALESCE(so.total_amount, 0)
        - COALESCE(so.paid_amount, 0)
        - COALESCE(so.returned_amount, 0)
      ) AS net_remaining,
      so.delivered_at,
      so.due_date,
      CASE
        WHEN so.due_date IS NULL OR so.delivered_at IS NULL THEN NULL
        ELSE (so.due_date - so.delivered_at::date)::integer
      END AS credit_days_effective,
      CASE
        WHEN so.delivered_at IS NULL THEN NULL
        ELSE (CURRENT_DATE - so.delivered_at::date)::integer
      END AS days_since_delivery,
      GREATEST(0, (CURRENT_DATE - so.due_date))::integer AS days_overdue,
      CASE
        WHEN (CURRENT_DATE - so.due_date) >= 60 THEN 'critical'
        WHEN (CURRENT_DATE - so.due_date) >= 30 THEN 'high'
        WHEN (CURRENT_DATE - so.due_date) >= 7  THEN 'medium'
        ELSE 'new'
      END AS overdue_bucket,
      due_hist.created_at AS last_due_date_changed_at,
      due_hist.reason::text AS last_due_date_reason
    FROM public.sales_orders so
    JOIN public.customers c ON c.id = so.customer_id
    LEFT JOIN public.profiles assigned_rep ON assigned_rep.id = c.assigned_rep_id
    LEFT JOIN public.profiles order_rep ON order_rep.id = so.rep_id
    LEFT JOIN LATERAL (
      SELECT h.created_at, h.reason
      FROM public.sales_order_due_date_history h
      WHERE h.order_id = so.id
      ORDER BY h.created_at DESC
      LIMIT 1
    ) due_hist ON true
    WHERE so.status IN ('delivered', 'partially_delivered')
      AND so.payment_terms IN ('credit', 'mixed')
      AND so.delivered_at IS NOT NULL
      AND so.due_date IS NOT NULL
      AND so.due_date < CURRENT_DATE
      AND GREATEST(
            0,
            COALESCE(so.total_amount, 0)
            - COALESCE(so.paid_amount, 0)
            - COALESCE(so.returned_amount, 0)
          ) > 0
      AND (p_customer_id IS NULL OR so.customer_id = p_customer_id)
      AND (p_rep_id IS NULL OR c.assigned_rep_id = p_rep_id OR so.rep_id = p_rep_id)
      AND (
        v_can_read_all
        OR (v_can_customers_read AND c.assigned_rep_id = v_user_id)
        OR (v_can_sales_read AND (so.rep_id = v_user_id OR so.created_by_id = v_user_id))
      )
      AND (
        p_search IS NULL
        OR btrim(p_search) = ''
        OR so.order_number ILIKE '%' || btrim(p_search) || '%'
        OR c.name ILIKE '%' || btrim(p_search) || '%'
        OR c.code ILIKE '%' || btrim(p_search) || '%'
      )
  ),
  filtered AS (
    SELECT b.*
    FROM base b
    WHERE p_min_days_overdue IS NULL
       OR p_min_days_overdue <= 0
       OR b.days_overdue >= p_min_days_overdue
  ),
  stats AS (
    SELECT
      COUNT(*)::bigint AS total_count,
      COALESCE(SUM(fl.net_remaining), 0)::numeric AS total_overdue_amount,
      COUNT(DISTINCT fl.customer_id)::bigint AS overdue_customers_count,
      COALESCE(MAX(fl.days_overdue), 0)::integer AS max_days_overdue
    FROM filtered fl
  )
  SELECT
    f.id,
    f.order_number,
    f.customer_id,
    f.customer_code,
    f.customer_name,
    f.assigned_rep_id,
    f.assigned_rep_name,
    f.order_rep_id,
    f.order_rep_name,
    f.payment_terms,
    f.status,
    f.total_amount,
    f.paid_amount,
    f.returned_amount,
    f.net_remaining,
    f.delivered_at,
    f.due_date,
    f.credit_days_effective,
    f.days_since_delivery,
    f.days_overdue,
    f.overdue_bucket,
    f.last_due_date_changed_at,
    f.last_due_date_reason,
    s.total_count,
    s.total_overdue_amount,
    s.overdue_customers_count,
    s.max_days_overdue
  FROM filtered f
  CROSS JOIN stats s
  ORDER BY
    CASE WHEN v_sort_by = 'due_date_asc' THEN f.due_date END ASC,
    CASE WHEN v_sort_by = 'remaining_desc' THEN f.net_remaining END DESC,
    CASE WHEN v_sort_by = 'customer_name' THEN f.customer_name END ASC,
    CASE WHEN v_sort_by = 'days_overdue_desc' THEN f.days_overdue END DESC,
    f.due_date ASC,
    f.order_number ASC
  LIMIT v_limit
  OFFSET v_offset;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_overdue_sales_invoices(TEXT, UUID, UUID, INTEGER, TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_overdue_sales_invoices(TEXT, UUID, UUID, INTEGER, TEXT, INTEGER, INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_overdue_sales_invoices(TEXT, UUID, UUID, INTEGER, TEXT, INTEGER, INTEGER) TO authenticated;
