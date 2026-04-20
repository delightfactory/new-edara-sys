-- ============================================================
-- 105b_customer_reengagement_fixes.sql
--
-- تصحيحات جوهرية لـ customer_reengagement_operational.sql
--
-- الإصلاحات:
--
-- 1. outstanding_balance — إزالة GREATEST clamp
--    السبب: GREATEST(COALESCE(current_balance,0), 0) يُخفي أرصدة
--    سالبة (رصيد دائن على العميل) ويُعطي انطباعاً زائفاً بأن الرصيد
--    صفر. الخسارة المُبلَّغ عنها: anomalies محاسبية غير مكتشفة.
--    الحل: COALESCE(c.current_balance, 0) — بلا clamp.
--    القرار الواضح: "إجمالي الرصيد" يشمل الأرصدة السالبة (دائنة)،
--    والـ UI يُظهر اللون المناسب.
--
-- 2. avg_historical_revenue — إزالة NULLIF(x, 0)
--    السبب: AVG(NULLIF(hist_revenue, 0)) يحذف صامتاً العملاء
--    ذوي المبيعات الصفرية من قاعدة حساب المتوسط، بينما يُدرجهم
--    في total_customers. هذا يُضخّم المتوسط المُعلن ويُخالف
--    "نفس base dataset" المذكورة في التوجيه.
--    الحل: AVG(wp.historical_revenue) — يشمل الأصفار.
--
-- 3. الـ NTILE PARTITION تصحيح
--    السبب: PARTITION BY (cb.historical_revenue > 0) يُنشئ
--    partition ثم يُطبق NTILE عليها — هذا يعني العملاء
--    ذوو revenue = 0 يحصلون على quartile = NULL (صحيح).
--    لكن العملاء ذوو revenue > 0 يُقسَّمون في partition واحدة
--    فقط — هذا صحيح ونريد الإبقاء عليه.
--
-- ملاحظة التحقق:
--   استعلامات التحقق الآن قابلة للتنفيذ في قسم VERIFICATION
--   وموثقة في التعليق أدناه.
-- ============================================================

BEGIN;

-- ────────────────────────────────────────────────────────────
-- 1. إعادة تعريف customer_reengagement_list بالتصحيحات
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.customer_reengagement_list(
  p_date_from      date    DEFAULT NULL,
  p_date_to        date    DEFAULT NULL,
  p_rep_id         uuid    DEFAULT NULL,
  p_governorate_id uuid    DEFAULT NULL,
  p_city_id        uuid    DEFAULT NULL,
  p_priority       text    DEFAULT NULL,
  p_customer_type  text    DEFAULT NULL,
  p_active_only    boolean DEFAULT true,
  p_limit          integer DEFAULT 100
)
RETURNS TABLE (
  customer_id         uuid,
  customer_name       text,
  customer_code       text,
  customer_type       text,
  governorate_name    text,
  city_name           text,
  rep_name            text,
  rep_id              uuid,
  priority_label      text,
  priority_rank       integer,
  value_tier          text,
  status_label        text,
  historical_revenue  numeric,
  revenue_last_90d    numeric,
  revenue_prev_90d    numeric,
  recency_days        integer,
  last_order_date     date,
  outstanding_balance numeric,   -- FIX: بلا clamp — يشمل الأرصدة الدائنة
  order_count         bigint,
  is_active           boolean
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  v_gov_city_ids uuid[];
BEGIN
  IF NOT public.check_permission(auth.uid(), 'reports.sales')
     AND NOT public.check_permission(auth.uid(), 'reports.view_all') THEN
    RAISE EXCEPTION 'reengagement_unauthorized';
  END IF;

  IF p_governorate_id IS NOT NULL AND p_city_id IS NULL THEN
    SELECT ARRAY(
      SELECT c.id FROM public.cities c
      WHERE c.governorate_id = p_governorate_id
    ) INTO v_gov_city_ids;
  END IF;

  RETURN QUERY
  WITH
  base_orders AS (
    SELECT
      so.customer_id,
      SUM(so.total_amount - COALESCE(so.returned_amount, 0)) AS hist_revenue,
      SUM(so.total_amount - COALESCE(so.returned_amount, 0))
        FILTER (WHERE COALESCE(so.delivered_at::date, so.order_date) >= CURRENT_DATE - 90)
        AS rev_l90d,
      SUM(so.total_amount - COALESCE(so.returned_amount, 0))
        FILTER (WHERE COALESCE(so.delivered_at::date, so.order_date)
                      BETWEEN CURRENT_DATE - 180 AND CURRENT_DATE - 91)
        AS rev_p90d,
      COUNT(so.id) AS order_count,
      MAX(COALESCE(so.delivered_at::date, so.order_date)) AS last_order_date,
      (CURRENT_DATE - MAX(COALESCE(so.delivered_at::date, so.order_date)))::integer AS recency_days
    FROM public.sales_orders so
    WHERE so.status IN ('delivered', 'completed')
      AND (p_date_from IS NULL OR COALESCE(so.delivered_at::date, so.order_date) >= p_date_from)
      AND (p_date_to   IS NULL OR COALESCE(so.delivered_at::date, so.order_date) <= p_date_to)
    GROUP BY so.customer_id
  ),

  customer_base AS (
    SELECT
      c.id              AS customer_id,
      c.name            AS customer_name,
      c.code            AS customer_code,
      c.type            AS customer_type,
      c.assigned_rep_id AS rep_id,
      c.governorate_id,
      c.city_id,
      c.is_active,
      -- FIX: بلا GREATEST clamp — نُظهر الرصيد الحقيقي
      -- رصيد موجب = ذمم على العميل (مديونية)
      -- رصيد سالب = رصيد دائن (العميل له رصيد مسبق)
      COALESCE(c.current_balance, 0) AS outstanding_balance,
      COALESCE(bo.hist_revenue, 0)   AS historical_revenue,
      COALESCE(bo.rev_l90d, 0)       AS revenue_last_90d,
      COALESCE(bo.rev_p90d, 0)       AS revenue_prev_90d,
      bo.order_count,
      bo.last_order_date,
      bo.recency_days
    FROM public.customers c
    LEFT JOIN base_orders bo ON bo.customer_id = c.id
    WHERE
      (p_rep_id IS NULL OR c.assigned_rep_id = p_rep_id)
      AND (p_customer_type IS NULL OR c.type = p_customer_type)
      AND (NOT p_active_only OR c.is_active = true)
      AND (
        (p_city_id IS NULL AND p_governorate_id IS NULL)
        OR (p_city_id IS NOT NULL AND c.city_id = p_city_id)
        OR (
          p_governorate_id IS NOT NULL AND p_city_id IS NULL
          AND (
            c.governorate_id = p_governorate_id
            OR (
              v_gov_city_ids IS NOT NULL
              AND array_length(v_gov_city_ids, 1) > 0
              AND c.city_id = ANY(v_gov_city_ids)
            )
          )
        )
      )
  ),

  quartile_base AS (
    SELECT
      cb.*,
      CASE
        WHEN cb.historical_revenue > 0 THEN
          NTILE(4) OVER (
            PARTITION BY (cb.historical_revenue > 0)
            ORDER BY cb.historical_revenue DESC
          )
        ELSE NULL
      END AS quartile
    FROM customer_base cb
  ),

  classified AS (
    SELECT
      qb.*,
      CASE
        WHEN qb.quartile = 1           THEN 'HIGH'
        WHEN qb.quartile IN (2, 3)     THEN 'MED'
        ELSE                                'LOW'
      END AS value_tier,
      CASE
        WHEN qb.recency_days IS NULL         THEN 'NO_ORDERS'
        WHEN qb.recency_days > 90            THEN 'LOST'
        WHEN qb.recency_days BETWEEN 46 AND 90 THEN 'AT_RISK'
        ELSE                                     'ACTIVE'
      END AS status_label,
      CASE
        WHEN qb.quartile = 1 AND qb.recency_days > 90                  THEN 'CHAMPION_LOST'
        WHEN qb.quartile = 1 AND qb.recency_days BETWEEN 46 AND 90     THEN 'DECLINING_HIGH'
        WHEN qb.quartile IN (2,3) AND qb.recency_days > 90             THEN 'MID_LOST'
        WHEN qb.quartile IN (2,3) AND qb.recency_days BETWEEN 46 AND 90 THEN 'MID_AT_RISK'
        ELSE 'OTHER'
      END AS priority_label,
      CASE
        WHEN qb.quartile = 1 AND qb.recency_days > 90                  THEN 1
        WHEN qb.quartile = 1 AND qb.recency_days BETWEEN 46 AND 90     THEN 2
        WHEN qb.quartile IN (2,3) AND qb.recency_days > 90             THEN 3
        WHEN qb.quartile IN (2,3) AND qb.recency_days BETWEEN 46 AND 90 THEN 4
        ELSE 5
      END AS priority_rank
    FROM quartile_base qb
  )

  SELECT
    cl.customer_id,
    cl.customer_name,
    cl.customer_code,
    cl.customer_type,
    COALESCE(go.name, '')       AS governorate_name,
    COALESCE(ci.name, '')       AS city_name,
    COALESCE(pr.full_name, '')  AS rep_name,
    cl.rep_id,
    cl.priority_label,
    cl.priority_rank,
    cl.value_tier,
    cl.status_label,
    cl.historical_revenue,
    cl.revenue_last_90d,
    cl.revenue_prev_90d,
    cl.recency_days,
    cl.last_order_date,
    cl.outstanding_balance,    -- FIX: الرصيد الحقيقي بلا clamp
    COALESCE(cl.order_count, 0) AS order_count,
    cl.is_active
  FROM classified cl
  LEFT JOIN public.profiles     pr ON pr.id = cl.rep_id
  LEFT JOIN public.governorates go ON go.id = cl.governorate_id
  LEFT JOIN public.cities       ci ON ci.id = cl.city_id
  WHERE (p_priority IS NULL OR cl.priority_label = p_priority)
  ORDER BY
    cl.priority_rank ASC,
    cl.historical_revenue DESC NULLS LAST,
    cl.recency_days DESC NULLS LAST,
    cl.outstanding_balance DESC NULLS LAST
  LIMIT p_limit;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 2. إعادة تعريف customer_reengagement_summary بالتصحيحات
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.customer_reengagement_summary(
  p_date_from      date    DEFAULT NULL,
  p_date_to        date    DEFAULT NULL,
  p_rep_id         uuid    DEFAULT NULL,
  p_governorate_id uuid    DEFAULT NULL,
  p_city_id        uuid    DEFAULT NULL,
  p_priority       text    DEFAULT NULL,
  p_customer_type  text    DEFAULT NULL,
  p_active_only    boolean DEFAULT true
)
RETURNS TABLE (
  total_customers        bigint,
  champion_lost_count    bigint,
  declining_high_count   bigint,
  mid_lost_count         bigint,
  mid_at_risk_count      bigint,
  other_count            bigint,
  total_outstanding      numeric,   -- FIX: يشمل الأرصدة الدائنة (سالبة)
  avg_historical_revenue numeric,   -- FIX: يشمل العملاء ذوي revenue=0
  avg_recency_days       numeric
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  v_gov_city_ids uuid[];
BEGIN
  IF NOT public.check_permission(auth.uid(), 'reports.sales')
     AND NOT public.check_permission(auth.uid(), 'reports.view_all') THEN
    RAISE EXCEPTION 'reengagement_unauthorized';
  END IF;

  IF p_governorate_id IS NOT NULL AND p_city_id IS NULL THEN
    SELECT ARRAY(
      SELECT c.id FROM public.cities c
      WHERE c.governorate_id = p_governorate_id
    ) INTO v_gov_city_ids;
  END IF;

  RETURN QUERY
  WITH
  base_orders AS (
    SELECT
      so.customer_id,
      SUM(so.total_amount - COALESCE(so.returned_amount, 0)) AS hist_revenue,
      COUNT(so.id) AS order_count,
      MAX(COALESCE(so.delivered_at::date, so.order_date)) AS last_order_date,
      (CURRENT_DATE - MAX(COALESCE(so.delivered_at::date, so.order_date)))::integer AS recency_days
    FROM public.sales_orders so
    WHERE so.status IN ('delivered', 'completed')
      AND (p_date_from IS NULL OR COALESCE(so.delivered_at::date, so.order_date) >= p_date_from)
      AND (p_date_to   IS NULL OR COALESCE(so.delivered_at::date, so.order_date) <= p_date_to)
    GROUP BY so.customer_id
  ),
  customer_base AS (
    SELECT
      c.id AS customer_id,
      c.type AS customer_type,
      c.assigned_rep_id AS rep_id,
      c.governorate_id,
      c.city_id,
      c.is_active,
      -- FIX: بلا clamp
      COALESCE(c.current_balance, 0) AS outstanding_balance,
      COALESCE(bo.hist_revenue, 0) AS historical_revenue,
      bo.recency_days
    FROM public.customers c
    LEFT JOIN base_orders bo ON bo.customer_id = c.id
    WHERE
      (p_rep_id IS NULL OR c.assigned_rep_id = p_rep_id)
      AND (p_customer_type IS NULL OR c.type = p_customer_type)
      AND (NOT p_active_only OR c.is_active = true)
      AND (
        (p_city_id IS NULL AND p_governorate_id IS NULL)
        OR (p_city_id IS NOT NULL AND c.city_id = p_city_id)
        OR (
          p_governorate_id IS NOT NULL AND p_city_id IS NULL
          AND (
            c.governorate_id = p_governorate_id
            OR (
              v_gov_city_ids IS NOT NULL
              AND array_length(v_gov_city_ids, 1) > 0
              AND c.city_id = ANY(v_gov_city_ids)
            )
          )
        )
      )
  ),
  quartile_base AS (
    SELECT
      cb.*,
      CASE
        WHEN cb.historical_revenue > 0 THEN
          NTILE(4) OVER (
            PARTITION BY (cb.historical_revenue > 0)
            ORDER BY cb.historical_revenue DESC
          )
        ELSE NULL
      END AS quartile
    FROM customer_base cb
  ),
  classified AS (
    SELECT
      qb.*,
      CASE
        WHEN qb.quartile = 1       THEN 'HIGH'
        WHEN qb.quartile IN (2, 3) THEN 'MED'
        ELSE                           'LOW'
      END AS value_tier,
      CASE
        WHEN qb.recency_days IS NULL            THEN 'NO_ORDERS'
        WHEN qb.recency_days > 90               THEN 'LOST'
        WHEN qb.recency_days BETWEEN 46 AND 90  THEN 'AT_RISK'
        ELSE                                        'ACTIVE'
      END AS status_label
    FROM quartile_base qb
  ),
  with_priority AS (
    SELECT
      cl.*,
      CASE
        WHEN cl.value_tier = 'HIGH' AND cl.status_label = 'LOST'    THEN 'CHAMPION_LOST'
        WHEN cl.value_tier = 'HIGH' AND cl.status_label = 'AT_RISK' THEN 'DECLINING_HIGH'
        WHEN cl.value_tier = 'MED'  AND cl.status_label = 'LOST'    THEN 'MID_LOST'
        WHEN cl.value_tier = 'MED'  AND cl.status_label = 'AT_RISK' THEN 'MID_AT_RISK'
        ELSE 'OTHER'
      END AS priority_label
    FROM classified cl
  )
  SELECT
    COUNT(*)::bigint                                                               AS total_customers,
    COUNT(*) FILTER (WHERE wp.priority_label = 'CHAMPION_LOST')::bigint           AS champion_lost_count,
    COUNT(*) FILTER (WHERE wp.priority_label = 'DECLINING_HIGH')::bigint          AS declining_high_count,
    COUNT(*) FILTER (WHERE wp.priority_label = 'MID_LOST')::bigint                AS mid_lost_count,
    COUNT(*) FILTER (WHERE wp.priority_label = 'MID_AT_RISK')::bigint             AS mid_at_risk_count,
    COUNT(*) FILTER (WHERE wp.priority_label = 'OTHER')::bigint                   AS other_count,
    -- FIX: SUM شامل أرصدة دائنة — الإجمالي الحقيقي للمحفظة
    SUM(wp.outstanding_balance)                                                    AS total_outstanding,
    -- FIX: AVG يشمل العملاء ذوي revenue=0 لمطابقة base dataset
    ROUND(AVG(wp.historical_revenue), 0)                                          AS avg_historical_revenue,
    ROUND(AVG(wp.recency_days::numeric), 0)                                       AS avg_recency_days
  FROM with_priority wp
  WHERE (p_priority IS NULL OR wp.priority_label = p_priority);
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 3. استعلامات التحقق القابلة للتنفيذ
--    شغّلها في SQL Editor بعد تطبيق الـ migration
-- ────────────────────────────────────────────────────────────

-- ‼️ لتنفيذ استعلامات التحقق مباشرة، افتح Supabase SQL Editor وشغّل:

-- A. Sanity: total_customers في summary يجب أن يساوي COUNT في list
/*
WITH
  s AS (SELECT total_customers FROM public.customer_reengagement_summary()),
  l AS (SELECT COUNT(*) AS cnt FROM public.customer_reengagement_list(p_limit => 99999))
SELECT
  s.total_customers,
  l.cnt,
  CASE WHEN s.total_customers = l.cnt THEN 'PASS ✅' ELSE 'FAIL ❌' END AS sanity_check
FROM s, l;
*/

-- B. AVG check: يجب أن يساوي حساب يدوي يشمل الأصفار
/*
WITH raw AS (
  SELECT historical_revenue FROM public.customer_reengagement_list(p_limit => 99999)
),
summary_avg AS (
  SELECT avg_historical_revenue FROM public.customer_reengagement_summary()
)
SELECT
  ROUND(AVG(raw.historical_revenue), 0) AS manual_avg_with_zeros,
  summary_avg.avg_historical_revenue    AS rpc_avg,
  CASE
    WHEN ABS(COALESCE(ROUND(AVG(raw.historical_revenue), 0), 0)
             - COALESCE(summary_avg.avg_historical_revenue, 0)) < 1
    THEN 'PASS ✅' ELSE 'FAIL ❌'
  END AS avg_check
FROM raw, summary_avg
GROUP BY summary_avg.avg_historical_revenue;
*/

-- C. Balance check: أرصدة سالبة مُدرجة (ولا clamp)
/*
SELECT
  COUNT(*) FILTER (WHERE outstanding_balance < 0) AS negative_balance_customers,
  MIN(outstanding_balance)                         AS most_negative,
  SUM(outstanding_balance)                         AS net_total
FROM public.customer_reengagement_list(p_limit => 99999);
*/

-- D. Anomaly: طلبات فيها returned_amount > total_amount
/*
SELECT id, order_number, total_amount, returned_amount,
       total_amount - COALESCE(returned_amount, 0) AS net_value
FROM public.sales_orders
WHERE status IN ('delivered', 'completed')
  AND COALESCE(returned_amount, 0) > total_amount
ORDER BY net_value ASC
LIMIT 20;
*/

-- E. Priority distribution (يجب أن HIGH ≈ 25% من ذوي المبيعات)
/*
SELECT priority_label, COUNT(*) AS cnt,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM public.customer_reengagement_list(p_limit => 99999)
GROUP BY priority_label
ORDER BY MIN(priority_rank);
*/

COMMIT;
