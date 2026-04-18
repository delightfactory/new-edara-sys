-- ============================================================
-- 104_customer_360_production_bootstrap.sql
--
-- Canonical production bootstrap for Customer Intelligence 360.
--
-- Why this file exists:
--   - Migration 99 was designed as the first Customer 360 rollout, but it is
--     not safe to rely on re-running it manually in production SQL Editor.
--   - Current production state may still be pre-99 (only legacy overloads of
--     analytics_customer_risk_list and analytics_gross_profit_by_customer).
--   - Later migrations 100-103 assume that 99 already succeeded.
--
-- Safety goals:
--   1. Add the final Customer 360 RPC layer in one atomic migration.
--   2. Preserve legacy overloads already used by production dashboards.
--   3. Avoid DROP FUNCTION and avoid modifying business data.
--   4. Rebuild the few fragile parts (notably category mix / payment behavior)
--      without DECLARE variables so execution is friendlier to SQL Editor.
--   5. Avoid overload ambiguity by making additive parameters explicit on the
--      new overloads and reordering parameters where required for valid
--      PostgreSQL syntax.
--
-- Compatibility guarantees:
--   - Existing overloads remain untouched:
--       public.analytics_customer_risk_list(date, text, uuid, integer)
--       public.analytics_gross_profit_by_customer(date, date, uuid, text, integer)
--   - New overloads are additive only and require the new differentiator arg
--     explicitly so old 3/4/5-arg calls do not become ambiguous.
--   - GRANTs are idempotent.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. get_customer_360_kpis
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_customer_360_kpis(p_customer_id uuid)
RETURNS TABLE (
  net_revenue numeric,
  total_collected numeric,
  outstanding_balance numeric,
  order_count bigint,
  monthly_avg_orders numeric,
  return_rate_pct numeric,
  latest_order_date date,
  customer_since_days integer,
  credit_limit numeric,
  credit_utilization_pct numeric
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  IF public.check_permission(auth.uid(), 'customers.read_all') THEN
    NULL;
  ELSIF public.check_permission(auth.uid(), 'customers.read')
        AND EXISTS (
          SELECT 1
          FROM public.customers
          WHERE id = p_customer_id
            AND assigned_rep_id = auth.uid()
        ) THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'analytics_unauthorized:domain=customer_360';
  END IF;

  RETURN QUERY
  WITH stats AS (
    SELECT
      COUNT(so.id) FILTER (
        WHERE so.status IN ('confirmed', 'partially_delivered', 'delivered', 'completed')
      ) AS o_count,
      COALESCE(SUM(so.total_amount - COALESCE(so.returned_amount, 0)) FILTER (
        WHERE so.status IN ('delivered', 'completed')
      ), 0) AS net_r,
      COALESCE(SUM(so.paid_amount) FILTER (
        WHERE so.status IN ('delivered', 'completed')
      ), 0) AS total_c,
      COALESCE(SUM(so.returned_amount) FILTER (
        WHERE so.status IN ('delivered', 'completed')
      ), 0) AS ret_amt,
      COALESCE(SUM(so.total_amount) FILTER (
        WHERE so.status IN ('delivered', 'completed')
      ), 0) AS gross_amt,
      MIN(COALESCE(so.delivered_at, so.order_date::timestamptz)) AS first_order_date,
      MAX(COALESCE(so.delivered_at, so.order_date::timestamptz))::date AS last_order_date
    FROM public.sales_orders so
    WHERE so.customer_id = p_customer_id
  ),
  cust AS (
    SELECT c.current_balance, c.created_at, c.credit_limit
    FROM public.customers c
    WHERE c.id = p_customer_id
  )
  SELECT
    stats.net_r AS net_revenue,
    stats.total_c AS total_collected,
    cust.current_balance AS outstanding_balance,
    stats.o_count AS order_count,
    ROUND(
      CASE
        WHEN stats.o_count = 0 THEN 0
        ELSE stats.o_count::numeric
          / GREATEST(
              EXTRACT(epoch FROM (now() - COALESCE(stats.first_order_date, now()))) / (30 * 86400),
              1::numeric
            )
      END,
      1
    ) AS monthly_avg_orders,
    ROUND(
      CASE
        WHEN stats.gross_amt = 0 THEN 0
        ELSE (stats.ret_amt / stats.gross_amt) * 100
      END,
      1
    ) AS return_rate_pct,
    stats.last_order_date AS latest_order_date,
    GREATEST(EXTRACT(DAY FROM (now() - COALESCE(stats.first_order_date, cust.created_at)))::int, 0) AS customer_since_days,
    COALESCE(cust.credit_limit, 0) AS credit_limit,
    ROUND(
      CASE
        WHEN COALESCE(cust.credit_limit, 0) = 0 THEN 0
        WHEN cust.current_balance <= 0 THEN 0
        ELSE (cust.current_balance / cust.credit_limit) * 100
      END,
      1
    ) AS credit_utilization_pct
  FROM stats, cust;
END;
$$;

-- ------------------------------------------------------------
-- 2. get_customer_sales_by_month
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_customer_sales_by_month(
  p_customer_id uuid,
  p_months int DEFAULT 18
)
RETURNS TABLE (
  month text,
  net_revenue numeric,
  returns_value numeric,
  order_count bigint
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  IF public.check_permission(auth.uid(), 'customers.read_all') THEN
    NULL;
  ELSIF public.check_permission(auth.uid(), 'customers.read')
        AND EXISTS (
          SELECT 1
          FROM public.customers
          WHERE id = p_customer_id
            AND assigned_rep_id = auth.uid()
        ) THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'analytics_unauthorized:domain=customer_360';
  END IF;

  RETURN QUERY
  SELECT
    to_char(date_trunc('month', d), 'YYYY-MM') AS month,
    COALESCE(SUM(so.total_amount - COALESCE(so.returned_amount, 0)), 0) AS net_revenue,
    COALESCE(SUM(so.returned_amount), 0) AS returns_value,
    COUNT(so.id) AS order_count
  FROM generate_series(
    date_trunc('month', CURRENT_DATE - ((p_months - 1) || ' months')::interval),
    date_trunc('month', CURRENT_DATE),
    '1 month'::interval
  ) d
  LEFT JOIN public.sales_orders so
    ON so.customer_id = p_customer_id
   AND so.status IN ('delivered', 'completed')
   AND date_trunc('month', COALESCE(so.delivered_at, so.order_date::timestamptz)) = d
  GROUP BY d
  ORDER BY d ASC;
END;
$$;

-- ------------------------------------------------------------
-- 3. get_customer_top_products
-- DROP required: return type changed (added order_count column).
-- CREATE OR REPLACE cannot change RETURNS TABLE structure.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_customer_top_products(uuid, int);
CREATE OR REPLACE FUNCTION public.get_customer_top_products(
  p_customer_id uuid,
  p_limit int DEFAULT 15
)
RETURNS TABLE (
  product_id uuid,
  product_sku text,
  product_name text,
  category_name text,
  total_qty numeric,
  total_value numeric,
  value_l90d numeric,
  order_count bigint,
  return_rate_pct numeric,
  status text,
  last_purchase_date date,
  avg_price numeric
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  IF public.check_permission(auth.uid(), 'customers.read_all') THEN
    NULL;
  ELSIF public.check_permission(auth.uid(), 'customers.read')
        AND EXISTS (
          SELECT 1
          FROM public.customers
          WHERE id = p_customer_id
            AND assigned_rep_id = auth.uid()
        ) THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'analytics_unauthorized:domain=customer_360';
  END IF;

  RETURN QUERY
  WITH product_stats AS (
    SELECT
      soi.product_id,
      SUM(soi.base_quantity) AS t_qty,
      SUM(soi.line_total) AS t_val,
      SUM(soi.line_total) FILTER (WHERE COALESCE(so.delivered_at::date, so.order_date) >= CURRENT_DATE - 90) AS val_l90d,
      SUM(sri.line_total) AS ret_val,
      COUNT(DISTINCT so.id) AS order_count,
      MIN(COALESCE(so.delivered_at::date, so.order_date)) AS first_purchase,
      MAX(COALESCE(so.delivered_at::date, so.order_date)) AS last_purchase,
      COUNT(DISTINCT so.id) FILTER (
        WHERE COALESCE(so.delivered_at::date, so.order_date) BETWEEN CURRENT_DATE - 180 AND CURRENT_DATE - 90
      ) AS count_180_90
    FROM public.sales_orders so
    JOIN public.sales_order_items soi ON soi.order_id = so.id
    LEFT JOIN public.sales_returns sr
      ON sr.order_id = so.id
     AND sr.status = 'confirmed'
    LEFT JOIN public.sales_return_items sri
      ON sri.return_id = sr.id
     AND sri.order_item_id = soi.id
    WHERE so.customer_id = p_customer_id
      AND so.status IN ('delivered', 'completed')
    GROUP BY soi.product_id
  )
  SELECT
    ps.product_id,
    p.sku AS product_sku,
    p.name AS product_name,
    COALESCE(pc.name, 'بدون تصنيف') AS category_name,
    ps.t_qty AS total_qty,
    ps.t_val AS total_value,
    COALESCE(ps.val_l90d, 0) AS value_l90d,
    ps.order_count,
    ROUND(
      CASE
        WHEN ps.t_val = 0 THEN 0
        ELSE (COALESCE(ps.ret_val, 0) / ps.t_val) * 100
      END,
      1
    ) AS return_rate_pct,
    -- حالة المنتج (تعريف إيجابي لكل حالة):
    -- مستمر = اشترى في آخر 90 يومًا
    -- جديد  = أول شراء في آخر 90 يومًا مع طلبات قليلة (≤ 2)
    -- خامد  = لم يشترِ منذ أكثر من 90 يومًا مع وجود تاريخ شراء
    CASE
      WHEN ps.last_purchase >= CURRENT_DATE - 90 THEN 'مستمر'
      WHEN ps.first_purchase >= CURRENT_DATE - 90
        AND ps.order_count <= 2 THEN 'جديد'
      ELSE 'خامد'
    END AS status,
    ps.last_purchase AS last_purchase_date,
    ROUND(
      CASE
        WHEN ps.t_qty = 0 THEN 0
        ELSE ps.t_val / ps.t_qty
      END,
      2
    ) AS avg_price
  FROM product_stats ps
  JOIN public.products p ON p.id = ps.product_id
  LEFT JOIN public.product_categories pc ON pc.id = p.category_id
  ORDER BY ps.t_val DESC
  LIMIT p_limit;
END;
$$;

-- ------------------------------------------------------------
-- 4. get_customer_category_mix
-- Rewritten without DECLARE variables to avoid SQL Editor confusion.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_customer_category_mix(p_customer_id uuid)
RETURNS TABLE (
  category_id uuid,
  category_name text,
  all_time_value numeric,
  all_time_pct numeric,
  recent_90d_value numeric,
  recent_90d_pct numeric
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  IF public.check_permission(auth.uid(), 'customers.read_all') THEN
    NULL;
  ELSIF public.check_permission(auth.uid(), 'customers.read')
        AND EXISTS (
          SELECT 1
          FROM public.customers
          WHERE id = p_customer_id
            AND assigned_rep_id = auth.uid()
        ) THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'analytics_unauthorized:domain=customer_360';
  END IF;

  RETURN QUERY
  WITH line_rows AS (
    SELECT
      soi.product_id,
      soi.line_total,
      COALESCE(so.delivered_at::date, so.order_date) AS created_at
    FROM public.sales_orders so
    JOIN public.sales_order_items soi ON soi.order_id = so.id
    WHERE so.customer_id = p_customer_id
      AND so.status IN ('delivered', 'completed')
  ),
  totals AS (
    SELECT
      COALESCE(NULLIF(SUM(lr.line_total), 0), 1)::numeric AS total_all_time,
      COALESCE(NULLIF(SUM(lr.line_total) FILTER (WHERE lr.created_at >= CURRENT_DATE - 90), 0), 1)::numeric AS total_90d
    FROM line_rows lr
  )
  SELECT
    pc.id AS category_id,
    COALESCE(pc.name, 'بدون تصنيف') AS category_name,
    SUM(lr.line_total) AS all_time_value,
    ROUND((SUM(lr.line_total) / t.total_all_time) * 100, 2) AS all_time_pct,
    COALESCE(SUM(lr.line_total) FILTER (WHERE lr.created_at >= CURRENT_DATE - 90), 0) AS recent_90d_value,
    ROUND(
      (
        COALESCE(SUM(lr.line_total) FILTER (WHERE lr.created_at >= CURRENT_DATE - 90), 0)
        / t.total_90d
      ) * 100,
      2
    ) AS recent_90d_pct
  FROM line_rows lr
  LEFT JOIN public.products p ON p.id = lr.product_id
  LEFT JOIN public.product_categories pc ON pc.id = p.category_id
  CROSS JOIN totals t
  GROUP BY pc.id, pc.name, t.total_all_time, t.total_90d
  ORDER BY SUM(lr.line_total) DESC;
END;
$$;

-- ------------------------------------------------------------
-- 5. get_customer_ar_aging
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_customer_ar_aging(p_customer_id uuid)
RETURNS TABLE (
  bucket text,
  amount numeric,
  invoice_count bigint,
  oldest_invoice_date date
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  IF public.check_permission(auth.uid(), 'customers.read_all') THEN
    NULL;
  ELSIF public.check_permission(auth.uid(), 'customers.read')
        AND EXISTS (
          SELECT 1
          FROM public.customers
          WHERE id = p_customer_id
            AND assigned_rep_id = auth.uid()
        ) THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'analytics_unauthorized:domain=customer_360';
  END IF;

  RETURN QUERY
  WITH unpaid AS (
    SELECT
      (CURRENT_DATE - so.delivered_at::date)::numeric AS days_aged,
      so.total_amount - so.paid_amount - COALESCE(so.returned_amount, 0) AS open_amount,
      so.delivered_at::date AS d_date
    FROM public.sales_orders so
    WHERE so.customer_id = p_customer_id
      AND so.status IN ('delivered', 'completed')
      AND (so.total_amount - so.paid_amount - COALESCE(so.returned_amount, 0)) > 0
  )
  SELECT
    b.bucket_name AS bucket,
    COALESCE(SUM(u.open_amount), 0) AS amount,
    COUNT(u.days_aged) AS invoice_count,
    MIN(u.d_date) AS oldest_invoice_date
  FROM (
    VALUES
      ('0-30', 0, 30),
      ('31-60', 31, 60),
      ('61-90', 61, 90),
      ('90+', 91, 99999)
  ) AS b(bucket_name, min_days, max_days)
  LEFT JOIN unpaid u
    ON u.days_aged >= b.min_days
   AND u.days_aged <= b.max_days
  GROUP BY b.bucket_name
  ORDER BY CASE b.bucket_name
    WHEN '0-30' THEN 1
    WHEN '31-60' THEN 2
    WHEN '61-90' THEN 3
    WHEN '90+' THEN 4
  END;
END;
$$;

-- ------------------------------------------------------------
-- 6. get_customer_payment_behavior
-- Rewritten without DECLARE variables to avoid SQL Editor confusion.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_customer_payment_behavior(p_customer_id uuid)
RETURNS TABLE (
  avg_payment_delay_days numeric,
  min_delay_days numeric,
  max_delay_days numeric,
  payment_samples bigint,
  payment_methods_breakdown jsonb,
  recent_receipts jsonb
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  IF public.check_permission(auth.uid(), 'customers.read_all') THEN
    NULL;
  ELSIF public.check_permission(auth.uid(), 'customers.read')
        AND EXISTS (
          SELECT 1
          FROM public.customers
          WHERE id = p_customer_id
            AND assigned_rep_id = auth.uid()
        ) THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'analytics_unauthorized:domain=customer_360';
  END IF;

  RETURN QUERY
  WITH receipts AS (
    SELECT
      pr.id,
      pr.number,
      pr.amount,
      pr.payment_method,
      pr.sales_order_id,
      COALESCE(pr.reviewed_at, pr.created_at) AS r_date
    FROM public.payment_receipts pr
    WHERE pr.customer_id = p_customer_id
      AND pr.status = 'confirmed'
  ),
  payment_methods AS (
    SELECT COALESCE(jsonb_object_agg(pm_sub.pm, pm_sub.amt), '{}'::jsonb) AS breakdown
    FROM (
      SELECT r.payment_method AS pm, SUM(r.amount) AS amt
      FROM receipts r
      GROUP BY r.payment_method
    ) pm_sub
  ),
  recent AS (
    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'number', rec_sub.number,
          'amount', rec_sub.amount,
          'payment_method', rec_sub.payment_method,
          'date', rec_sub.r_date
        )
        ORDER BY rec_sub.r_date DESC
      ),
      '[]'::jsonb
    ) AS recent_receipts
    FROM (
      SELECT r.number, r.amount, r.payment_method, r.r_date
      FROM receipts r
      ORDER BY r.r_date DESC
      LIMIT 5
    ) rec_sub
  ),
  allocated_path AS (
    SELECT
      so.delivered_at,
      COALESCE(pr.reviewed_at, pr.created_at) AS payment_ts
    FROM public.customer_ledger cl_credit
    JOIN public.payment_receipts pr ON pr.id = cl_credit.source_id
    JOIN public.customer_ledger cl_debit ON cl_debit.id = cl_credit.allocated_to
    JOIN public.sales_orders so ON so.id = cl_debit.source_id
    WHERE cl_credit.customer_id = p_customer_id
      AND cl_credit.source_type = 'payment'
      AND cl_credit.type = 'credit'
      AND cl_credit.allocated_to IS NOT NULL
      AND pr.status = 'confirmed'
      AND so.delivered_at IS NOT NULL
  ),
  cash_direct_path AS (
    SELECT
      so.delivered_at,
      COALESCE(pr.reviewed_at, pr.created_at) AS payment_ts
    FROM public.payment_receipts pr
    JOIN public.sales_orders so ON so.id = pr.sales_order_id
    WHERE pr.customer_id = p_customer_id
      AND pr.status = 'confirmed'
      AND pr.sales_order_id IS NOT NULL
      AND so.delivered_at IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.customer_ledger cl
        JOIN public.customer_ledger cl_d ON cl_d.id = cl.allocated_to
        WHERE cl.source_id = pr.id
          AND cl_d.source_id = pr.sales_order_id
      )
  ),
  all_events AS (
    SELECT EXTRACT(DAY FROM ap.payment_ts - ap.delivered_at) AS delay_days
    FROM allocated_path ap
    UNION ALL
    SELECT EXTRACT(DAY FROM cdp.payment_ts - cdp.delivered_at) AS delay_days
    FROM cash_direct_path cdp
  ),
  stats AS (
    SELECT
      ROUND(AVG(ae.delay_days)) AS avg_payment_delay_days,
      MIN(ae.delay_days)::numeric AS min_delay_days,
      MAX(ae.delay_days)::numeric AS max_delay_days,
      COUNT(*)::bigint AS payment_samples
    FROM all_events ae
  )
  SELECT
    s.avg_payment_delay_days,
    s.min_delay_days,
    s.max_delay_days,
    COALESCE(s.payment_samples, 0),
    pm.breakdown,
    r.recent_receipts
  FROM stats s
  CROSS JOIN payment_methods pm
  CROSS JOIN recent r;
END;
$$;

-- ------------------------------------------------------------
-- 7. get_customer_unified_timeline
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_customer_unified_timeline(
  p_customer_id uuid,
  p_limit int DEFAULT 30,
  p_before_ts timestamptz DEFAULT NULL,
  p_before_id uuid DEFAULT NULL
)
RETURNS TABLE (
  event_id uuid,
  event_ts timestamptz,
  event_type text,
  title text,
  amount numeric,
  status text,
  actor text,
  source_id uuid,
  extra jsonb
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  IF public.check_permission(auth.uid(), 'customers.read_all') THEN
    NULL;
  ELSIF public.check_permission(auth.uid(), 'customers.read')
        AND EXISTS (
          SELECT 1
          FROM public.customers
          WHERE id = p_customer_id
            AND assigned_rep_id = auth.uid()
        ) THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'analytics_unauthorized:domain=customer_360';
  END IF;

  RETURN QUERY
  WITH events AS (
    SELECT
      so.id AS event_id,
      COALESCE(so.delivered_at, so.order_date::timestamptz) AS event_ts,
      'order' AS event_type,
      'طلب #' || COALESCE(so.order_number, '') AS title,
      so.total_amount AS amount,
      so.status::text AS status,
      (SELECT pr.full_name FROM public.profiles pr WHERE pr.id = so.created_by_id) AS actor,
      so.id AS source_id,
      jsonb_build_object(
        'order_number', so.order_number,
        'total_amount', so.total_amount,
        'status', so.status
      ) AS extra
    FROM public.sales_orders so
    WHERE so.customer_id = p_customer_id

    UNION ALL

    SELECT
      sr.id AS event_id,
      COALESCE(sr.confirmed_at, sr.created_at) AS event_ts,
      'return' AS event_type,
      'مرتجع #' || COALESCE(sr.return_number, '') AS title,
      sr.total_amount AS amount,
      sr.status::text AS status,
      (SELECT pr.full_name FROM public.profiles pr WHERE pr.id = sr.created_by) AS actor,
      sr.id AS source_id,
      jsonb_build_object(
        'return_number', sr.return_number,
        'total_amount', sr.total_amount,
        'reason', sr.reason
      ) AS extra
    FROM public.sales_returns sr
    WHERE sr.customer_id = p_customer_id

    UNION ALL

    SELECT
      prc.id AS event_id,
      COALESCE(prc.reviewed_at, prc.created_at) AS event_ts,
      'payment' AS event_type,
      'إيصال #' || COALESCE(prc.number, '') AS title,
      prc.amount AS amount,
      prc.status::text AS status,
      (SELECT pr.full_name FROM public.profiles pr WHERE pr.id = prc.created_by) AS actor,
      prc.id AS source_id,
      jsonb_build_object(
        'number', prc.number,
        'payment_method', prc.payment_method
      ) AS extra
    FROM public.payment_receipts prc
    WHERE prc.customer_id = p_customer_id

    UNION ALL

    SELECT
      act.id AS event_id,
      act.created_at AS event_ts,
      'activity' AS event_type,
      COALESCE(act.subject, atyp.name, 'نشاط 360') AS title,
      0::numeric AS amount,
      act.outcome_type::text AS status,
      (SELECT pr.full_name FROM public.profiles pr WHERE pr.id = act.created_by) AS actor,
      act.id AS source_id,
      jsonb_build_object(
        'type_name', atyp.name,
        'outcome_type', act.outcome_type,
        'outcome_notes', act.outcome_notes
      ) AS extra
    FROM public.activities act
    LEFT JOIN public.activity_types atyp ON atyp.id = act.type_id
    WHERE act.customer_id = p_customer_id
      AND act.deleted_at IS NULL

    UNION ALL

    SELECT
      cch.id AS event_id,
      cch.created_at AS event_ts,
      'credit_change' AS event_type,
      'تعديل ائتمان (' || cch.limit_before::text || ' ← ' || cch.limit_after::text || ')' AS title,
      cch.limit_after - cch.limit_before AS amount,
      'completed' AS status,
      (SELECT pr.full_name FROM public.profiles pr WHERE pr.id = cch.changed_by) AS actor,
      cch.id AS source_id,
      jsonb_build_object(
        'limit_before', cch.limit_before,
        'limit_after', cch.limit_after,
        'reason', cch.reason
      ) AS extra
    FROM public.customer_credit_history cch
    WHERE cch.customer_id = p_customer_id
  )
  SELECT
    e.event_id,
    e.event_ts,
    e.event_type,
    e.title,
    e.amount,
    e.status,
    e.actor,
    e.source_id,
    e.extra
  FROM events e
  WHERE (
    p_before_ts IS NULL
    OR e.event_ts < p_before_ts
    OR (e.event_ts = p_before_ts AND e.event_id < p_before_id)
  )
  ORDER BY e.event_ts DESC, e.event_id DESC
  LIMIT p_limit;
END;
$$;

-- ------------------------------------------------------------
-- 8-A. get_customer_ledger_with_balance (4-arg deterministic overload)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_customer_ledger_with_balance(
  p_customer_id uuid,
  p_limit int DEFAULT 15,
  p_before_ts timestamptz DEFAULT NULL,
  p_before_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  type text,
  amount numeric,
  source_type text,
  source_id uuid,
  description text,
  created_at timestamptz,
  running_balance numeric
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  IF public.check_permission(auth.uid(), 'customers.read_all') THEN
    NULL;
  ELSIF public.check_permission(auth.uid(), 'customers.read')
        AND EXISTS (
          SELECT 1
          FROM public.customers
          WHERE id = p_customer_id
            AND assigned_rep_id = auth.uid()
        ) THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'analytics_unauthorized:domain=customer_360';
  END IF;

  RETURN QUERY
  WITH all_entries AS (
    SELECT
      cl.id,
      cl.type::text,
      cl.amount,
      cl.source_type::text,
      cl.source_id,
      cl.description,
      cl.created_at,
      SUM(
        CASE
          WHEN cl.type = 'debit' THEN cl.amount
          ELSE -cl.amount
        END
      ) OVER (
        ORDER BY cl.created_at ASC, cl.id ASC
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) AS running_balance
    FROM public.customer_ledger cl
    WHERE cl.customer_id = p_customer_id
  )
  SELECT
    ae.id,
    ae.type,
    ae.amount,
    ae.source_type,
    ae.source_id,
    ae.description,
    ae.created_at,
    ae.running_balance
  FROM all_entries ae
  WHERE (
    p_before_ts IS NULL
    OR ae.created_at < p_before_ts
    OR (ae.created_at = p_before_ts AND p_before_id IS NOT NULL AND ae.id < p_before_id)
  )
  ORDER BY ae.created_at DESC, ae.id DESC
  LIMIT p_limit;
END;
$$;

-- ------------------------------------------------------------
-- 8-B. get_customer_ledger_with_balance (3-arg compatibility overload)
-- Keeps backward compatibility for any caller that only passes p_before_ts.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_customer_ledger_with_balance(
  p_customer_id uuid,
  p_limit int DEFAULT 15,
  p_before_ts timestamptz DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  type text,
  amount numeric,
  source_type text,
  source_id uuid,
  description text,
  created_at timestamptz,
  running_balance numeric
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  IF public.check_permission(auth.uid(), 'customers.read_all') THEN
    NULL;
  ELSIF public.check_permission(auth.uid(), 'customers.read')
        AND EXISTS (
          SELECT 1
          FROM public.customers
          WHERE id = p_customer_id
            AND assigned_rep_id = auth.uid()
        ) THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'analytics_unauthorized:domain=customer_360';
  END IF;

  RETURN QUERY
  SELECT *
  FROM public.get_customer_ledger_with_balance(
    p_customer_id => p_customer_id,
    p_before_id => NULL::uuid,
    p_limit => p_limit,
    p_before_ts => p_before_ts
  );
END;
$$;

-- ------------------------------------------------------------
-- 9. get_customer_360_health_snapshot
-- Final canonical contract returns risk_label (not rfm_segment).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_customer_360_health_snapshot(p_customer_id uuid)
RETURNS TABLE (
  health_status text,
  risk_label text,
  recency_days integer,
  frequency_l90d integer,
  monetary_l90d numeric,
  last_snapshot_date date
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  IF public.check_permission(auth.uid(), 'customers.read_all') THEN
    NULL;
  ELSIF public.check_permission(auth.uid(), 'customers.read')
        AND EXISTS (
          SELECT 1
          FROM public.customers
          WHERE id = p_customer_id
            AND assigned_rep_id = auth.uid()
        ) THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'analytics_unauthorized:domain=customer_360';
  END IF;

  RETURN QUERY
  SELECT
    CASE
      WHEN sh.is_dormant THEN 'خامد'
      ELSE 'نشط'
    END AS health_status,
    cr.risk_label,
    sh.recency_days,
    sh.frequency_l90d,
    sh.monetary_l90d,
    sh.as_of_date AS last_snapshot_date
  FROM analytics.snapshot_customer_health sh
  LEFT JOIN analytics.snapshot_customer_risk cr
    ON cr.customer_id = sh.customer_id
   AND cr.as_of_date = sh.as_of_date
  WHERE sh.customer_id = p_customer_id
  ORDER BY sh.as_of_date DESC
  LIMIT 1;

EXCEPTION
  WHEN undefined_table THEN
    RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;

-- ------------------------------------------------------------
-- 10. get_customer_360_risk_snapshot
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_customer_360_risk_snapshot(p_customer_id uuid)
RETURNS TABLE (
  risk_label text,
  rfm_score integer,
  recency_days integer,
  frequency_l90d integer,
  monetary_l90d numeric
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  IF public.check_permission(auth.uid(), 'customers.read_all') THEN
    NULL;
  ELSIF public.check_permission(auth.uid(), 'customers.read')
        AND EXISTS (
          SELECT 1
          FROM public.customers
          WHERE id = p_customer_id
            AND assigned_rep_id = auth.uid()
        ) THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'analytics_unauthorized:domain=customer_360';
  END IF;

  RETURN QUERY
  SELECT
    cr.risk_label,
    cr.rfm_score,
    cr.recency_days,
    cr.frequency_l90d,
    cr.monetary_l90d
  FROM analytics.snapshot_customer_risk cr
  WHERE cr.customer_id = p_customer_id
  ORDER BY cr.as_of_date DESC
  LIMIT 1;

EXCEPTION
  WHEN undefined_table THEN
    RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;

-- ------------------------------------------------------------
-- 11. analytics_customer_risk_list (NEW additive overload with p_customer_id)
-- Legacy 4-arg overload remains untouched.
-- IMPORTANT: p_customer_id is explicit (no DEFAULT) to avoid overload ambiguity.
-- It is placed before optional parameters to satisfy PostgreSQL syntax rules.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.analytics_customer_risk_list(
  p_as_of_date date,
  p_customer_id uuid,
  p_risk_label text DEFAULT NULL,
  p_rep_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 50
)
RETURNS TABLE (
  customer_id uuid,
  customer_name text,
  risk_label text,
  rfm_score integer,
  recency_days integer,
  frequency_l90d integer,
  monetary_l90d numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, analytics
AS $$
BEGIN
  IF NOT public.check_permission(auth.uid(), 'reports.sales')
     AND NOT public.check_permission(auth.uid(), 'reports.view_all') THEN
    RAISE EXCEPTION 'analytics_unauthorized:domain=customers';
  END IF;

  RETURN QUERY
  SELECT
    cr.customer_id,
    COALESCE(c.name, cr.customer_id::text) AS customer_name,
    cr.risk_label,
    cr.rfm_score,
    cr.recency_days,
    cr.frequency_l90d,
    cr.monetary_l90d
  FROM analytics.snapshot_customer_risk cr
  LEFT JOIN public.customers c ON c.id = cr.customer_id
  WHERE cr.as_of_date = p_as_of_date
    AND (p_risk_label IS NULL OR cr.risk_label = p_risk_label)
    AND (p_rep_id IS NULL OR c.assigned_rep_id = p_rep_id)
    AND (p_customer_id IS NULL OR cr.customer_id = p_customer_id)
  ORDER BY
    CASE cr.risk_label
      WHEN 'AT_RISK' THEN 1
      WHEN 'DORMANT' THEN 2
      WHEN 'VIP' THEN 3
      WHEN 'LOYAL' THEN 4
      ELSE 5
    END,
    cr.rfm_score DESC
  LIMIT p_limit;

EXCEPTION
  WHEN undefined_table THEN
    RAISE EXCEPTION 'analytics_not_deployed';
END;
$$;

-- ------------------------------------------------------------
-- 12. analytics_gross_profit_by_customer (NEW additive overload with p_customer_id)
-- Legacy 5-arg overload remains untouched.
-- IMPORTANT: p_customer_id is explicit (no DEFAULT) to avoid overload ambiguity.
-- Param names are reordered for valid PostgreSQL syntax while keeping the same
-- underlying type signature as the already-approved 6-arg path.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.analytics_gross_profit_by_customer(
  date_from date,
  date_to date,
  p_customer_id uuid,
  p_branch_id uuid DEFAULT NULL,
  p_granularity text DEFAULT 'aggregate',
  p_limit_count integer DEFAULT NULL
)
RETURNS TABLE (
  period text,
  customer_id uuid,
  gross_revenue numeric,
  net_cogs numeric,
  gross_profit numeric,
  net_quantity numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, analytics
AS $$
BEGIN
  IF NOT public.check_permission(auth.uid(), 'reports.view_all')
     AND NOT public.check_permission(auth.uid(), 'reports.financial') THEN
    RAISE EXCEPTION 'Access denied. Requires reports.view_all or reports.financial';
  END IF;

  IF p_granularity NOT IN ('aggregate', 'daily', 'monthly') THEN
    RAISE EXCEPTION 'Unsupported granularity: %. Use aggregate, daily, or monthly', p_granularity;
  END IF;

  IF p_granularity = 'daily' THEN
    RETURN QUERY
    SELECT
      g.sale_date::text AS period,
      g.customer_id,
      SUM(g.net_revenue) AS gross_revenue,
      SUM(g.net_cogs) AS net_cogs,
      SUM(g.gross_profit) AS gross_profit,
      SUM(g.net_quantity) AS net_quantity
    FROM analytics.fact_gross_profit_daily_grain g
    WHERE g.sale_date >= date_from
      AND g.sale_date <= date_to
      AND (p_branch_id IS NULL OR g.branch_id = p_branch_id)
      AND (p_customer_id IS NULL OR g.customer_id = p_customer_id)
    GROUP BY g.sale_date, g.customer_id
    ORDER BY g.sale_date ASC, SUM(g.gross_profit) DESC NULLS LAST
    LIMIT p_limit_count;

  ELSIF p_granularity = 'monthly' THEN
    RETURN QUERY
    SELECT
      to_char(date_trunc('month', g.sale_date)::date, 'YYYY-MM') AS period,
      g.customer_id,
      SUM(g.net_revenue)::numeric AS gross_revenue,
      SUM(g.net_cogs)::numeric AS net_cogs,
      SUM(g.gross_profit)::numeric AS gross_profit,
      SUM(g.net_quantity)::numeric AS net_quantity
    FROM analytics.fact_gross_profit_daily_grain g
    WHERE g.sale_date >= date_from
      AND g.sale_date <= date_to
      AND (p_branch_id IS NULL OR g.branch_id = p_branch_id)
      AND (p_customer_id IS NULL OR g.customer_id = p_customer_id)
    GROUP BY date_trunc('month', g.sale_date), g.customer_id
    ORDER BY 1 ASC, SUM(g.gross_profit) DESC NULLS LAST
    LIMIT p_limit_count;

  ELSE
    RETURN QUERY
    SELECT
      (date_from::text || ' / ' || date_to::text) AS period,
      g.customer_id,
      SUM(g.net_revenue) AS gross_revenue,
      SUM(g.net_cogs) AS net_cogs,
      SUM(g.gross_profit) AS gross_profit,
      SUM(g.net_quantity) AS net_quantity
    FROM analytics.fact_gross_profit_daily_grain g
    WHERE g.sale_date >= date_from
      AND g.sale_date <= date_to
      AND (p_branch_id IS NULL OR g.branch_id = p_branch_id)
      AND (p_customer_id IS NULL OR g.customer_id = p_customer_id)
    GROUP BY g.customer_id
    ORDER BY SUM(g.gross_profit) DESC NULLS LAST
    LIMIT p_limit_count;
  END IF;
END;
$$;

-- ------------------------------------------------------------
-- 13. Grants
-- Re-granting legacy signatures is harmless and protects mixed environments.
-- ------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.get_customer_360_kpis(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_customer_sales_by_month(uuid, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_customer_top_products(uuid, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_customer_category_mix(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_customer_ar_aging(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_customer_payment_behavior(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_customer_unified_timeline(uuid, int, timestamptz, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_customer_ledger_with_balance(uuid, int, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_customer_ledger_with_balance(uuid, int, timestamptz, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_customer_360_health_snapshot(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_customer_360_risk_snapshot(uuid) TO authenticated;

DO $$
BEGIN
  GRANT EXECUTE ON FUNCTION public.analytics_customer_risk_list(date, text, uuid, integer) TO authenticated;
EXCEPTION
  WHEN undefined_function THEN
    NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.analytics_customer_risk_list(date, uuid, text, uuid, integer) TO authenticated;

DO $$
BEGIN
  GRANT EXECUTE ON FUNCTION public.analytics_gross_profit_by_customer(date, date, uuid, text, integer) TO authenticated;
EXCEPTION
  WHEN undefined_function THEN
    NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.analytics_gross_profit_by_customer(date, date, uuid, uuid, text, integer) TO authenticated;

COMMIT;
