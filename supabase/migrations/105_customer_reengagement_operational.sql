-- ============================================================
-- 105_customer_reengagement_operational.sql
--
-- صفحة قرار تشغيلية: أولويات إعادة الاستهداف
--
-- الهدف: تحديد العملاء الأعلى قيمة تاريخية الذين تراجعوا أو خمدوا،
--         ورتبهم كقائمة أولويات تنفيذية قابلة للتصرف.
--
-- قرارات معمارية:
--   - يقرأ مباشرة من public.sales_orders و public.customers فقط.
--   - لا يعتمد على أي analytics schema أو snapshot.
--   - prefix: customer_reengagement_ (ليس analytics_).
--   - الدالتان تشتركان في base CTE منطقي واحد — الأرقام متسقة دائماً.
--
-- منطق التصنيف:
--   Historical Value Tier (quartile داخل نفس الـ scoped dataset):
--     HIGH = أعلى 25% (quartile 1)
--     MED  = الوسط  (quartile 2 + 3)
--     LOW  = أدنى 25% (quartile 4)
--
--   Current Status (من operational data مباشرة — لا snapshots):
--     LOST    = recency_days > 90
--     AT_RISK = recency_days BETWEEN 46 AND 90
--     ACTIVE  = recency_days <= 45 (أو بلا طلبات مسلّمة على الإطلاق → NULL)
--
--   Priority Label:
--     CHAMPION_LOST  = HIGH + LOST
--     DECLINING_HIGH = HIGH + AT_RISK
--     MID_LOST       = MED  + LOST
--     MID_AT_RISK    = MED  + AT_RISK
--     OTHER          = الباقي (LOW أو ACTIVE أو بدون طلبات)
--
--   ترتيب نهائي: priority_rank ASC, historical_revenue DESC,
--                recency_days DESC, outstanding_balance DESC
--
-- geography filter pattern:
--   إذا cityId → نفلتر city_id مباشرة
--   إذا governorateId فقط → نغطي governorate_id المباشر
--     AND العملاء المخزنين عبر city_id (لا يحملون governorate_id مباشر)
--
-- الفلاتر المتاحة:
--   p_date_from      date     DEFAULT NULL   بداية فترة القيمة التاريخية
--   p_date_to        date     DEFAULT NULL   نهاية فترة القيمة التاريخية
--   p_rep_id         uuid     DEFAULT NULL
--   p_governorate_id uuid     DEFAULT NULL
--   p_city_id        uuid     DEFAULT NULL
--   p_priority       text     DEFAULT NULL   CHAMPION_LOST | DECLINING_HIGH | MID_LOST | MID_AT_RISK | OTHER
--   p_customer_type  text     DEFAULT NULL   retail | wholesale | distributor
--   p_active_only    boolean  DEFAULT true
--   p_limit          integer  DEFAULT 100
--
-- استعلامات التحقق المرفقة في نهاية الملف.
-- ============================================================

BEGIN;

-- ────────────────────────────────────────────────────────────
-- 1. customer_reengagement_list
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
  outstanding_balance numeric,
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
  -- Permission gate — reports.sales أو reports.view_all
  IF NOT public.check_permission(auth.uid(), 'reports.sales')
     AND NOT public.check_permission(auth.uid(), 'reports.view_all') THEN
    RAISE EXCEPTION 'reengagement_unauthorized';
  END IF;

  -- ── Geography pre-resolve ──────────────────────────────────
  -- إذا governorate فقط (بدون city)، نجمع معرفات مدن المحافظة
  -- لتغطية العملاء اللي city_id فيهم بس (بدون governorate_id مباشر)
  IF p_governorate_id IS NOT NULL AND p_city_id IS NULL THEN
    SELECT ARRAY(
      SELECT c.id FROM public.cities c
      WHERE c.governorate_id = p_governorate_id
    ) INTO v_gov_city_ids;
  END IF;

  RETURN QUERY
  WITH
  -- ── Base CTE: كل الطلبات المسلّمة/المكتملة ──────────────────
  base_orders AS (
    SELECT
      so.customer_id,
      -- القيمة التاريخية: صافي بعد خصم المرتجعات
      -- WHYCOALESCE(returned_amount,0): بعض الطلبات لا تحمل returned_amount لأنه NULL وليس 0
      SUM(so.total_amount - COALESCE(so.returned_amount, 0))
        AS hist_revenue,
      -- آخر 90 يوم من الآن
      SUM(so.total_amount - COALESCE(so.returned_amount, 0))
        FILTER (WHERE COALESCE(so.delivered_at::date, so.order_date) >= CURRENT_DATE - 90)
        AS rev_l90d,
      -- 90 يوم قبلها (من 180 إلى 91 يوم)
      SUM(so.total_amount - COALESCE(so.returned_amount, 0))
        FILTER (WHERE COALESCE(so.delivered_at::date, so.order_date)
                      BETWEEN CURRENT_DATE - 180 AND CURRENT_DATE - 91)
        AS rev_p90d,
      COUNT(so.id) AS order_count,
      MAX(COALESCE(so.delivered_at::date, so.order_date)) AS last_order_date,
      (CURRENT_DATE - MAX(COALESCE(so.delivered_at::date, so.order_date)))::integer AS recency_days
    FROM public.sales_orders so
    WHERE so.status IN ('delivered', 'completed')
      -- فلترة فترة القيمة التاريخية (اختيارية — الدافتراضي: كل التاريخ)
      AND (p_date_from IS NULL OR COALESCE(so.delivered_at::date, so.order_date) >= p_date_from)
      AND (p_date_to   IS NULL OR COALESCE(so.delivered_at::date, so.order_date) <= p_date_to)
    GROUP BY so.customer_id
  ),

  -- ── تجميع مع بيانات العميل قبل التصنيف ─────────────────────
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
      -- current_balance من جدول customers (يُحدَّث بالـ ledger triggers)
      -- مستحق إيجابي = ذمم على العميل
      GREATEST(COALESCE(c.current_balance, 0), 0) AS outstanding_balance,
      COALESCE(bo.hist_revenue, 0)    AS historical_revenue,
      COALESCE(bo.rev_l90d, 0)        AS revenue_last_90d,
      COALESCE(bo.rev_p90d, 0)        AS revenue_prev_90d,
      bo.order_count,
      bo.last_order_date,
      bo.recency_days
    FROM public.customers c
    LEFT JOIN base_orders bo ON bo.customer_id = c.id
    WHERE
      -- فلتر المندوب
      (p_rep_id IS NULL OR c.assigned_rep_id = p_rep_id)
      -- فلتر نوع العميل
      AND (p_customer_type IS NULL OR c.type = p_customer_type)
      -- فلتر الحالة
      AND (NOT p_active_only OR c.is_active = true)
      -- ── Geography filter (legacy/new pattern) ───────────────
      AND (
        -- لا فلتر جغرافي
        (p_city_id IS NULL AND p_governorate_id IS NULL)
        -- مدينة محددة — أدق وأسرع
        OR (p_city_id IS NOT NULL AND c.city_id = p_city_id)
        -- محافظة فقط: نُغطي governorate_id المباشر + city_id التابعة للمحافظة
        OR (
          p_governorate_id IS NOT NULL
          AND p_city_id IS NULL
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

  -- ── Quartile ranking داخل نفس الـ scoped dataset ─────────────
  quartile_base AS (
    SELECT
      cb.*,
      -- NTILE(4) على العملاء الذين لديهم مبيعات فعلية
      -- العملاء بلا مبيعات (historical_revenue=0) → NULL quartile → LOW
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

  -- ── Value Tier + Status Label + Priority ───────────────────
  classified AS (
    SELECT
      qb.*,
      -- Value Tier
      CASE
        WHEN qb.quartile = 1 THEN 'HIGH'
        WHEN qb.quartile IN (2, 3) THEN 'MED'
        ELSE 'LOW'
      END AS value_tier,
      -- Current Status (من operational data — لا snapshots)
      CASE
        WHEN qb.recency_days IS NULL         THEN 'NO_ORDERS'
        WHEN qb.recency_days > 90            THEN 'LOST'
        WHEN qb.recency_days BETWEEN 46 AND 90 THEN 'AT_RISK'
        ELSE                                      'ACTIVE'
      END AS status_label,
      -- Priority Label (المنطق المركب)
      CASE
        WHEN (CASE WHEN qb.quartile = 1 THEN 'HIGH' WHEN qb.quartile IN (2,3) THEN 'MED' ELSE 'LOW' END) = 'HIGH'
             AND qb.recency_days > 90
             THEN 'CHAMPION_LOST'
        WHEN (CASE WHEN qb.quartile = 1 THEN 'HIGH' WHEN qb.quartile IN (2,3) THEN 'MED' ELSE 'LOW' END) = 'HIGH'
             AND qb.recency_days BETWEEN 46 AND 90
             THEN 'DECLINING_HIGH'
        WHEN (CASE WHEN qb.quartile = 1 THEN 'HIGH' WHEN qb.quartile IN (2,3) THEN 'MED' ELSE 'LOW' END) = 'MED'
             AND qb.recency_days > 90
             THEN 'MID_LOST'
        WHEN (CASE WHEN qb.quartile = 1 THEN 'HIGH' WHEN qb.quartile IN (2,3) THEN 'MED' ELSE 'LOW' END) = 'MED'
             AND qb.recency_days BETWEEN 46 AND 90
             THEN 'MID_AT_RISK'
        ELSE 'OTHER'
      END AS priority_label,
      -- Priority rank للترتيب
      CASE
        WHEN (CASE WHEN qb.quartile = 1 THEN 'HIGH' WHEN qb.quartile IN (2,3) THEN 'MED' ELSE 'LOW' END) = 'HIGH'
             AND qb.recency_days > 90
             THEN 1
        WHEN (CASE WHEN qb.quartile = 1 THEN 'HIGH' WHEN qb.quartile IN (2,3) THEN 'MED' ELSE 'LOW' END) = 'HIGH'
             AND qb.recency_days BETWEEN 46 AND 90
             THEN 2
        WHEN (CASE WHEN qb.quartile = 1 THEN 'HIGH' WHEN qb.quartile IN (2,3) THEN 'MED' ELSE 'LOW' END) = 'MED'
             AND qb.recency_days > 90
             THEN 3
        WHEN (CASE WHEN qb.quartile = 1 THEN 'HIGH' WHEN qb.quartile IN (2,3) THEN 'MED' ELSE 'LOW' END) = 'MED'
             AND qb.recency_days BETWEEN 46 AND 90
             THEN 4
        ELSE 5
      END AS priority_rank
    FROM quartile_base qb
  )

  -- ── Final SELECT ────────────────────────────────────────────
  SELECT
    cl.customer_id,
    cl.customer_name,
    cl.customer_code,
    cl.customer_type,
    COALESCE(go.name, '')  AS governorate_name,
    COALESCE(ci.name, '')  AS city_name,
    COALESCE(pr.full_name, '') AS rep_name,
    cl.rep_id,
    cl.priority_label,
    cl.priority_rank,
    cl.value_tier,
    cl.status_label,
    cl.historical_revenue,
    cl.revenue_last_90d  AS revenue_last_90d,
    cl.revenue_prev_90d  AS revenue_prev_90d,
    cl.recency_days,
    cl.last_order_date,
    cl.outstanding_balance,
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
-- 2. customer_reengagement_summary
--    نفس base CTE تماماً — مضمون تطابق الأرقام مع list
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
  total_customers       bigint,
  champion_lost_count   bigint,
  declining_high_count  bigint,
  mid_lost_count        bigint,
  mid_at_risk_count     bigint,
  other_count           bigint,
  total_outstanding     numeric,
  avg_historical_revenue numeric,
  avg_recency_days      numeric
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

  -- Geography pre-resolve (نفس منطق list)
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
      GREATEST(COALESCE(c.current_balance, 0), 0) AS outstanding_balance,
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
        WHEN qb.quartile = 1 THEN 'HIGH'
        WHEN qb.quartile IN (2, 3) THEN 'MED'
        ELSE 'LOW'
      END AS value_tier,
      CASE
        WHEN qb.recency_days IS NULL          THEN 'NO_ORDERS'
        WHEN qb.recency_days > 90             THEN 'LOST'
        WHEN qb.recency_days BETWEEN 46 AND 90 THEN 'AT_RISK'
        ELSE                                       'ACTIVE'
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
    SUM(wp.outstanding_balance)                                                    AS total_outstanding,
    ROUND(AVG(NULLIF(wp.historical_revenue, 0)), 0)                               AS avg_historical_revenue,
    ROUND(AVG(wp.recency_days::numeric), 0)                                       AS avg_recency_days
  FROM with_priority wp
  WHERE (p_priority IS NULL OR wp.priority_label = p_priority);
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 3. GRANTs
-- ────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.customer_reengagement_list(
  date, date, uuid, uuid, uuid, text, text, boolean, integer
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.customer_reengagement_summary(
  date, date, uuid, uuid, uuid, text, text, boolean
) TO authenticated;

-- ────────────────────────────────────────────────────────────
-- 4. استعلامات التحقق (للتشغيل اليدوي بعد التطبيق)
-- ────────────────────────────────────────────────────────────

-- ١. Sanity: مقارنة عدد الصفوف بين summary و list
--    يجب أن يتساوى total_customers مع عدد صفوف list (بدون p_priority)
/*
SELECT total_customers FROM public.customer_reengagement_summary();
SELECT COUNT(*) FROM public.customer_reengagement_list(p_limit => 10000);
*/

-- ٢. Edge case: عملاء بلا أي طلبات مسلّمة
--    يجب أن يظهروا بـ priority_label = 'OTHER' و recency_days = NULL
/*
SELECT customer_id, customer_name, priority_label, recency_days, historical_revenue, order_count
FROM public.customer_reengagement_list()
WHERE order_count = 0 OR historical_revenue = 0
LIMIT 10;
*/

-- ٣. Edge case: عملاء لديهم مرتجعات
--    تحقق أن historical_revenue لا يتجاوز صفراً بشكل غير مبرر
/*
SELECT
  so.customer_id,
  SUM(so.total_amount) AS gross,
  SUM(COALESCE(so.returned_amount, 0)) AS returns,
  SUM(so.total_amount - COALESCE(so.returned_amount, 0)) AS net
FROM public.sales_orders so
WHERE so.status IN ('delivered','completed')
GROUP BY so.customer_id
HAVING SUM(so.total_amount - COALESCE(so.returned_amount, 0)) < 0
ORDER BY net ASC
LIMIT 10;
*/

-- ٤. Anomaly: طلبات فيها returned_amount > total_amount
/*
SELECT id, order_number, total_amount, returned_amount,
       total_amount - COALESCE(returned_amount,0) AS net_value
FROM public.sales_orders
WHERE status IN ('delivered','completed')
  AND COALESCE(returned_amount, 0) > total_amount
ORDER BY (total_amount - COALESCE(returned_amount,0)) ASC
LIMIT 20;
*/

-- ٥. Edge case: delivered_at فارغ و order_date مستخدم
/*
SELECT COUNT(*) AS using_order_date_fallback
FROM public.sales_orders
WHERE status IN ('delivered','completed')
  AND delivered_at IS NULL
  AND order_date IS NOT NULL;
*/

-- ٦. Edge case: عملاء city-only (بلا governorate_id مباشر)
/*
SELECT COUNT(*) AS city_only_customers
FROM public.customers
WHERE city_id IS NOT NULL AND governorate_id IS NULL;
*/

-- ٧. Sanity: priority distribution يجب أن يكون منطقياً (HIGH ≈ 25%)
/*
SELECT priority_label, COUNT(*) AS cnt,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM public.customer_reengagement_list(p_limit => 10000)
GROUP BY priority_label
ORDER BY MIN(priority_rank);
*/

COMMIT;
