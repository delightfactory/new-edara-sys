-- ════════════════════════════════════════════════════════════
-- EDARA v2 — Migration 69: Sales Performance Indexes + Stats RPC
-- فهارس الأداء المفقودة لجدول sales_orders + دالة الإحصائيات
--
-- المشاكل المُعالَجة:
--   1. غياب فهرس created_at على sales_orders (الترتيب الافتراضي)
--   2. غياب فهرس trigram على order_number (البحث النصي ilike)
--   3. غياب فهرس composite (status, created_at) للاستعلامات الشائعة
--   4. غياب فهرس assigned_rep_id على customers (يُستخدم في سياسة RLS)
--   5. غياب فهرس is_active على customers (يُستخدم في الفلترة)
--   6. get_sales_stats(): استبدال 6 استعلامات بدالة واحدة مُجمَّعة
--
-- Idempotent: آمن للتشغيل المتكرر
-- ════════════════════════════════════════════════════════════

-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 1. فهارس sales_orders المفقودة                             ║
-- ╚═══════════════════════════════════════════════════════════╝

-- الترتيب الافتراضي في كل قائمة مبيعات ORDER BY created_at DESC
CREATE INDEX IF NOT EXISTS idx_so_created_at
  ON sales_orders(created_at DESC);

-- Composite: (status, created_at) — الاستعلام الأكثر شيوعاً
-- مثال: جلب الطلبات المعلقة مرتبةً بالتاريخ
CREATE INDEX IF NOT EXISTS idx_so_status_created_at
  ON sales_orders(status, created_at DESC);

-- البحث النصي في رقم الطلب (ilike '%...%')
-- يتطلب امتداد pg_trgm (مُفعَّل منذ migration 03f)
CREATE INDEX IF NOT EXISTS idx_so_number_trgm
  ON sales_orders USING gin (order_number gin_trgm_ops);

-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 2. فهارس customers المفقودة (مُستخدَمة في RLS + الفلترة)  ║
-- ╚═══════════════════════════════════════════════════════════╝

-- assigned_rep_id — يُستخدم في سياسة RLS لكل استعلام على customers
-- بدونه: Seq Scan لكل مستخدم ليس لديه customers.read_all
CREATE INDEX IF NOT EXISTS idx_customers_assigned_rep
  ON customers(assigned_rep_id)
  WHERE assigned_rep_id IS NOT NULL;

-- is_active — فلتر شائع في قائمة العملاء وفي useCustomerSearch
CREATE INDEX IF NOT EXISTS idx_customers_is_active
  ON customers(is_active);

-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 3. تحديث الإحصائيات بعد حقن البيانات                      ║
-- ╚═══════════════════════════════════════════════════════════╝

-- ضروري لأن PostgreSQL planner يعمل بإحصائيات قديمة
-- بعد حقن 7600+ فاتورة و1860+ عميل
ANALYZE sales_orders;
ANALYZE sales_order_items;
ANALYZE customers;
ANALYZE customer_ledger;


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 4. RPC: get_sales_stats — استعلام واحد بدلاً من 6          ║
-- ╚═══════════════════════════════════════════════════════════╝
--
-- قبل الإصلاح:
--   - 5 استعلامات منفصلة (واحد لكل status) = 5 round-trips
--   - جلب كل صفوف total_amount للجمع في JavaScript
--   - مع 7600 فاتورة = تحميل آلاف الصفوف في الذاكرة
--
-- بعد الإصلاح:
--   - استعلام واحد مُجمَّع بالكامل في PostgreSQL
--   - يُرجع JSON بالإحصائيات كاملة

CREATE OR REPLACE FUNCTION get_sales_stats()
RETURNS json
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT json_build_object(
    'status_counts', (
      SELECT COALESCE(
        json_object_agg(status, cnt),
        '{}'::json
      )
      FROM (
        SELECT status, COUNT(*) AS cnt
        FROM sales_orders
        GROUP BY status
      ) t
    ),
    'total_sales', (
      SELECT COALESCE(SUM(total_amount), 0)
      FROM sales_orders
      WHERE status IN ('delivered', 'completed')
    ),
    'total_orders', (
      SELECT COUNT(*) FROM sales_orders
    )
  );
$$;

GRANT EXECUTE ON FUNCTION get_sales_stats() TO authenticated;
