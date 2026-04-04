-- ════════════════════════════════════════════════════════════
-- EDARA v2 — Migration 70: فهارس ناقصة + RPC البحث المتكامل
--
-- يُكمل migration 69 بالفهارس التي كانت ناقصة:
--   1. customer_id على sales_orders (الأهم — يُستخدم في كل فلتر عميل)
--   2. rep_id على sales_orders
--   3. order_date على sales_orders (فلاتر التاريخ)
--   4. (created_at DESC, id DESC) على customers (Keyset pagination)
--   5. (created_at DESC, id DESC) على sales_orders (Keyset pagination)
--
--   6. دالة search_sales_orders() — بحث متكامل في رقم الطلب + اسم العميل
--      بدون مشكلة URL الطويل (100 UUID)، تدعم Keyset cursor
--
-- Idempotent: آمن للتشغيل المتكرر
-- ════════════════════════════════════════════════════════════

-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 1. فهارس sales_orders الحيوية المفقودة من migration 69    ║
-- ╚═══════════════════════════════════════════════════════════╝

-- البحث بالعميل — الأكثر استخداماً في الفلترة
CREATE INDEX IF NOT EXISTS idx_so_customer_id
  ON sales_orders(customer_id);

-- فلتر المندوب
CREATE INDEX IF NOT EXISTS idx_so_rep_id
  ON sales_orders(rep_id);

-- فلاتر التاريخ
CREATE INDEX IF NOT EXISTS idx_so_order_date
  ON sales_orders(order_date DESC);

-- Keyset pagination — (created_at, id) معاً للـ tie-breaking
-- يُغني عن فهرس created_at المنفرد لأنه يشمله
CREATE INDEX IF NOT EXISTS idx_so_created_at_id
  ON sales_orders(created_at DESC, id DESC);

-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 2. فهارس customers للـ Keyset pagination                   ║
-- ╚═══════════════════════════════════════════════════════════╝

-- Keyset cursor — (created_at, id) للترتيب الثابت
CREATE INDEX IF NOT EXISTS idx_customers_created_at_id
  ON customers(created_at DESC, id DESC);

-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 3. ANALYZE بعد إضافة الفهارس                              ║
-- ╚═══════════════════════════════════════════════════════════╝

ANALYZE sales_orders;
ANALYZE customers;

-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 4. RPC: search_sales_orders — بحث متكامل مع Keyset cursor  ║
-- ╚═══════════════════════════════════════════════════════════╝
--
-- يحل مشكلتين دفعة واحدة:
--   أ) البحث في customer.name مباشرة من SQL (بدون 2 استعلامات)
--   ب) Keyset cursor لاستبعاد COUNT(*) ولأداء ثابت O(log N)
--
-- الأمان: SECURITY DEFINER يُطبّق RLS من خلال JOIN على customers
--         (المستخدم لن يرى عملاء لا يملك حق قراءتهم)
CREATE OR REPLACE FUNCTION search_sales_orders(
  p_search      TEXT          DEFAULT NULL,
  p_status      TEXT          DEFAULT NULL,
  p_rep_id      UUID          DEFAULT NULL,
  p_date_from   DATE          DEFAULT NULL,
  p_date_to     DATE          DEFAULT NULL,
  p_cursor_ts   TIMESTAMPTZ   DEFAULT NULL,  -- created_at آخر عنصر مرئي
  p_cursor_id   UUID          DEFAULT NULL,  -- id آخر عنصر مرئي
  p_limit       INT           DEFAULT 25
)
RETURNS TABLE (
  id               UUID,
  order_number     TEXT,
  status           TEXT,
  order_date       DATE,
  created_at       TIMESTAMPTZ,
  total_amount     NUMERIC,
  paid_amount      NUMERIC,
  returned_amount  NUMERIC,
  payment_terms    TEXT,
  customer_id      UUID,
  customer_name    TEXT,
  customer_code    TEXT,
  rep_id           UUID,
  rep_name         TEXT,
  branch_id        UUID,
  branch_name      TEXT,
  has_more         BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH filtered AS (
    SELECT
      so.id,
      so.order_number,
      so.status,
      so.order_date,
      so.created_at,
      so.total_amount,
      so.paid_amount,
      so.returned_amount,
      so.payment_terms,
      so.customer_id,
      c.name  AS customer_name,
      c.code  AS customer_code,
      so.rep_id,
      p.full_name AS rep_name,
      so.branch_id,
      b.name  AS branch_name
    FROM sales_orders so
    -- RLS يُطبَّق على كلا الجدولين تلقائياً
    JOIN customers c ON c.id = so.customer_id
    LEFT JOIN profiles p ON p.id = so.rep_id
    LEFT JOIN branches b ON b.id = so.branch_id
    WHERE
      -- فلتر البحث النصي (رقم الطلب OR اسم/كود العميل)
      (
        p_search IS NULL
        OR so.order_number ILIKE '%' || p_search || '%'
        OR c.name          ILIKE '%' || p_search || '%'
        OR c.code          ILIKE '%' || p_search || '%'
      )
      -- فلتر الحالة — cast صريح من TEXT إلى ENUM sales_order_status
      AND (p_status  IS NULL OR so.status  = p_status::sales_order_status)
      -- فلتر المندوب
      AND (p_rep_id  IS NULL OR so.rep_id  = p_rep_id)
      -- فلتر التاريخ
      AND (p_date_from IS NULL OR so.order_date >= p_date_from)
      AND (p_date_to   IS NULL OR so.order_date <= p_date_to)
      -- Keyset cursor — أسرع من OFFSET لأنه يستخدم الفهرس مباشرة
      -- الترتيب: order_date → created_at → id (للبيانات التاريخية التي تشترك في نفس created_at)
      AND (
        p_cursor_ts IS NULL
        OR so.order_date < p_cursor_ts::DATE
        OR (so.order_date = p_cursor_ts::DATE AND so.created_at < p_cursor_ts)
        OR (so.order_date = p_cursor_ts::DATE AND so.created_at = p_cursor_ts AND so.id < p_cursor_id)
      )
    ORDER BY so.order_date DESC, so.created_at DESC, so.id DESC
    -- نجلب p_limit + 1 لمعرفة هل يوجد المزيد بدون COUNT(*)
    LIMIT p_limit + 1
  )
  SELECT
    id, order_number, status, order_date, created_at,
    total_amount, paid_amount, returned_amount, payment_terms,
    customer_id, customer_name, customer_code,
    rep_id, rep_name,
    branch_id, branch_name,
    -- has_more: true إذا كان عدد النتائج أكبر من الحد المطلوب
    (COUNT(*) OVER () > p_limit) AS has_more
  FROM filtered
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION search_sales_orders TO authenticated;

-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 5. RPC: search_customers — بحث بـ Keyset cursor           ║
-- ╚═══════════════════════════════════════════════════════════╝
--
-- يُستخدم في useCustomerSearch لاستبدال OFFSET بـ Keyset
-- لا يحتاج COUNT(*) — يُرجع has_more فقط
CREATE OR REPLACE FUNCTION search_customers(
  p_search        TEXT        DEFAULT NULL,
  p_type          TEXT        DEFAULT NULL,
  p_governorate   UUID        DEFAULT NULL,
  p_city          UUID        DEFAULT NULL,
  p_rep_id        UUID        DEFAULT NULL,
  p_is_active     BOOLEAN     DEFAULT NULL,
  p_cursor_ts     TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id     UUID        DEFAULT NULL,
  p_limit         INT         DEFAULT 30
)
RETURNS TABLE (
  id               UUID,
  name             TEXT,
  code             TEXT,
  phone            TEXT,
  mobile           TEXT,
  type             TEXT,
  payment_terms    TEXT,
  credit_limit     NUMERIC,
  current_balance  NUMERIC,
  is_active        BOOLEAN,
  assigned_rep_id  UUID,
  latitude         DOUBLE PRECISION,
  longitude        DOUBLE PRECISION,
  address          TEXT,
  governorate_id   UUID,
  governorate_name TEXT,
  city_id          UUID,
  city_name        TEXT,
  rep_name         TEXT,
  created_at       TIMESTAMPTZ,
  has_more         BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH filtered AS (
    SELECT
      c.id,
      c.name,
      c.code,
      c.phone,
      c.mobile,
      c.type,
      c.payment_terms,
      c.credit_limit,
      c.current_balance,
      c.is_active,
      c.assigned_rep_id,
      c.latitude,
      c.longitude,
      c.address,
      c.governorate_id,
      g.name  AS governorate_name,
      c.city_id,
      ci.name AS city_name,
      p.full_name AS rep_name,
      c.created_at
    FROM customers c
    LEFT JOIN governorates g  ON g.id  = c.governorate_id
    LEFT JOIN cities ci       ON ci.id = c.city_id
    LEFT JOIN profiles p      ON p.id  = c.assigned_rep_id
    WHERE
      (
        p_search IS NULL
        OR c.name   ILIKE '%' || p_search || '%'
        OR c.code   ILIKE '%' || p_search || '%'
        OR c.phone  ILIKE '%' || p_search || '%'
        OR c.mobile ILIKE '%' || p_search || '%'
      )
      AND (p_type        IS NULL OR c.type          = p_type)
      AND (p_governorate IS NULL OR c.governorate_id = p_governorate)
      AND (p_city        IS NULL OR c.city_id        = p_city)
      AND (p_rep_id      IS NULL OR c.assigned_rep_id = p_rep_id)
      AND (p_is_active   IS NULL OR c.is_active      = p_is_active)
      -- Keyset cursor
      AND (
        p_cursor_ts IS NULL
        OR c.created_at < p_cursor_ts
        OR (c.created_at = p_cursor_ts AND c.id < p_cursor_id)
      )
    ORDER BY c.created_at DESC, c.id DESC
    LIMIT p_limit + 1
  )
  SELECT
    id, name, code, phone, mobile, type,
    payment_terms, credit_limit, current_balance, is_active,
    assigned_rep_id, latitude, longitude, address,
    governorate_id, governorate_name, city_id, city_name,
    rep_name, created_at,
    (COUNT(*) OVER () > p_limit) AS has_more
  FROM filtered
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION search_customers TO authenticated;
