-- ╔═══════════════════════════════════════════════════════════════════════╗
-- ║  Migration 71 — Sales Filter Enhancements                            ║
-- ║                                                                        ║
-- ║  الهدف:                                                                ║
-- ║  1. إضافة فلاتر جغرافية (محافظة / مدينة) لـ search_sales_orders      ║
-- ║  2. دعم البحث برقم هاتف العميل                                        ║
-- ║  3. إضافة فلتر طريقة الدفع (payment_terms)                            ║
-- ║  4. فهرس مركّب للعميل × المحافظة لتأمين الأداء                       ║
-- ║                                                                        ║
-- ║  استراتيجية الأداء:                                                    ║
-- ║  - الفلاتر الجغرافية تعمل عبر sub-select على customers               ║
-- ║    بدلاً من JOIN إضافي — يُستغل فهرس customers.governorate_id         ║
-- ║  - البحث بالهاتف يستخدم ILIKE فقط عند وجود p_search                 ║
-- ║    (لا overhead إذا كان البحث فارغاً)                                 ║
-- ╚═══════════════════════════════════════════════════════════════════════╝

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. فهرس مركّب: customers (governorate_id, city_id)
--    يُستخدم عند الفلترة الجغرافية في المبيعات
-- ─────────────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_customers_geo
  ON customers (governorate_id, city_id)
  WHERE governorate_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. فهرس: customers (phone, mobile) — للبحث برقم الهاتف
--    نستخدم partial index لتجاهل الأرقام الفارغة
-- ─────────────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_customers_phone
  ON customers (phone, mobile)
  WHERE phone IS NOT NULL OR mobile IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. فهرس: sales_orders (payment_terms) — لفلتر طريقة الدفع
-- ─────────────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_so_payment_terms
  ON sales_orders (payment_terms)
  WHERE payment_terms IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. إعادة كتابة search_sales_orders مع الفلاتر الجديدة
--
-- ⚠️  يجب حذف النسخة القديمة أولاً بـ signature دقيقة
-- ─────────────────────────────────────────────────────────────────────────────
-- حذف كل الـ overloads الموجودة — كل signature ممكنة
-- (قد تكون نُفِّذت محاولة سابقة جزئية وتركت نسخة بـ return type مختلف)
-- ─────────────────────────────────────────────────────────────────────────────

-- النسخة الأصلية من migration 70 (8 معاملات)
DROP FUNCTION IF EXISTS search_sales_orders(
  TEXT,         -- p_search
  TEXT,         -- p_status
  UUID,         -- p_rep_id
  DATE,         -- p_date_from
  DATE,         -- p_date_to
  TIMESTAMPTZ,  -- p_cursor_ts
  UUID,         -- p_cursor_id
  INT           -- p_limit
);

-- النسخة من المحاولة السابقة لـ migration 71 (11 معاملات — return type قديم بدون customer_phone)
-- الـ signature التي أفادت بها رسالة الخطأ الدقيقة من PostgreSQL
DROP FUNCTION IF EXISTS search_sales_orders(
  TEXT,         -- p_search
  TEXT,         -- p_status
  UUID,         -- p_rep_id
  DATE,         -- p_date_from
  DATE,         -- p_date_to
  TEXT,         -- p_payment_terms
  UUID,         -- p_governorate_id
  UUID,         -- p_city_id
  TIMESTAMPTZ,  -- p_cursor_ts
  UUID,         -- p_cursor_id
  INT           -- p_limit
);


CREATE OR REPLACE FUNCTION search_sales_orders(
  p_search          TEXT        DEFAULT NULL,
  p_status          TEXT        DEFAULT NULL,
  p_rep_id          UUID        DEFAULT NULL,
  p_date_from       DATE        DEFAULT NULL,
  p_date_to         DATE        DEFAULT NULL,
  p_payment_terms   TEXT        DEFAULT NULL,
  p_governorate_id  UUID        DEFAULT NULL,
  p_city_id         UUID        DEFAULT NULL,
  p_cursor_ts       TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id       UUID        DEFAULT NULL,
  p_limit           INT         DEFAULT 25
)
RETURNS TABLE (
  id               UUID,
  order_number     TEXT,
  status           TEXT,           -- TEXT وليس ENUM — للاتساق مع frontend
  order_date       DATE,
  created_at       TIMESTAMPTZ,
  total_amount     NUMERIC,
  paid_amount      NUMERIC,
  returned_amount  NUMERIC,
  payment_terms    TEXT,
  customer_id      UUID,
  customer_name    TEXT,
  customer_code    TEXT,
  customer_phone   TEXT,
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
      so.status::TEXT,                          -- cast إلى TEXT للاتساق
      so.order_date,
      so.created_at,
      so.total_amount,
      so.paid_amount,
      so.returned_amount,
      so.payment_terms::TEXT,
      so.customer_id,
      c.name                          AS customer_name,
      c.code                          AS customer_code,
      COALESCE(c.phone, c.mobile)     AS customer_phone,
      so.rep_id,
      p.full_name                     AS rep_name,
      so.branch_id,
      b.name                          AS branch_name
    FROM sales_orders so
    JOIN customers   c ON c.id = so.customer_id
    LEFT JOIN profiles  p ON p.id = so.rep_id
    LEFT JOIN branches  b ON b.id = so.branch_id
    WHERE
      -- 1. البحث النصي: رقم الطلب | اسم/كود/هاتف/موبايل العميل
      (
        p_search IS NULL
        OR so.order_number ILIKE '%' || p_search || '%'
        OR c.name          ILIKE '%' || p_search || '%'
        OR c.code          ILIKE '%' || p_search || '%'
        OR c.phone         ILIKE '%' || p_search || '%'
        OR c.mobile        ILIKE '%' || p_search || '%'
      )
      -- 2. حالة الطلب
      AND (p_status IS NULL OR so.status = p_status::sales_order_status)
      -- 3. المندوب
      AND (p_rep_id IS NULL OR so.rep_id = p_rep_id)
      -- 4. نطاق التاريخ
      AND (p_date_from IS NULL OR so.order_date >= p_date_from)
      AND (p_date_to   IS NULL OR so.order_date <= p_date_to)
      -- 5. طريقة الدفع
      AND (p_payment_terms IS NULL OR so.payment_terms::TEXT = p_payment_terms)
      -- 6. فلتر المحافظة:
      --    العملاء يُخزَّن لديهم city_id وليس governorate_id مباشرة في معظم الحالات
      --    لذا نُغطي الحالتين: governorate_id مباشر أو city ينتمي للمحافظة
      AND (
        p_governorate_id IS NULL
        OR c.governorate_id = p_governorate_id
        OR c.city_id IN (
          SELECT id FROM cities WHERE governorate_id = p_governorate_id
        )
      )
      -- 7. مدينة العميل (مباشر — دقيق)
      AND (p_city_id IS NULL OR c.city_id = p_city_id)
      -- 8. Keyset cursor — O(log N) بدون OFFSET
      AND (
        p_cursor_ts IS NULL
        OR  so.order_date <  p_cursor_ts::DATE
        OR (so.order_date =  p_cursor_ts::DATE AND so.created_at <  p_cursor_ts)
        OR (so.order_date =  p_cursor_ts::DATE AND so.created_at =  p_cursor_ts AND so.id < p_cursor_id)
      )
    ORDER BY so.order_date DESC, so.created_at DESC, so.id DESC
    LIMIT p_limit + 1   -- +1 لمعرفة هل يوجد المزيد بدون COUNT(*)
  )
  SELECT
    id, order_number, status, order_date, created_at,
    total_amount, paid_amount, returned_amount, payment_terms,
    customer_id, customer_name, customer_code, customer_phone,
    rep_id, rep_name,
    branch_id, branch_name,
    (COUNT(*) OVER () > p_limit) AS has_more
  FROM filtered
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION search_sales_orders TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- ملاحظة: إضافة customer_phone للتوافق مع الخريطة الجديدة في الـ frontend
-- التوافق مع الدالة القديمة: search_sales_orders بدون p_payment_terms/geo
-- يعمل تلقائياً بسبب DEFAULT NULL على كل المعاملات الجديدة
-- ─────────────────────────────────────────────────────────────────────────────
