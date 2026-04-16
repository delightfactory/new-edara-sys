-- ============================================================
-- 76_credit_management_rpcs.sql
-- EDARA v2 — دوال خدمة إدارة الائتمان
--
-- المحتوى:
--   A) get_credit_portfolio_kpis   — مؤشرات المحفظة بتجميع SQL
--   B) get_overdue_batch           — تأخر دفعة العملاء بـ SQL
--   C) get_credit_open_orders      — الفواتير المسلَّمة مع days_since_delivery
--
-- القيود:
--   - لا SUM على customer_ledger في أي موضع
--   - لا استخدام لـ opening_balance
--   - countExceeded: current_balance > credit_limit (أكبر صارم)
--   - totalAvailable: SUM(GREATEST(0, credit_limit - current_balance))
--   - حالات التأخر: 'delivered' | 'partially_delivered' فقط
--   - 'confirmed' مستبعد كليًا من كل الدوال
--   - مرجع التأخر: (CURRENT_DATE - delivered_at::date) > credit_days
--
-- مرجع حالات الطلبات: 04b_delivery_rpcs.sql:158
-- مرجع check_permission: 01_foundation.sql:171
-- ============================================================


-- ╔══════════════════════════════════════════════════════════════╗
-- ║  A) get_credit_portfolio_kpis                              ║
-- ║  مؤشرات المحفظة الائتمانية — تجميع SQL خالص               ║
-- ╚══════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION get_credit_portfolio_kpis()
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT jsonb_build_object(
    -- إجمالي الحد: يشمل فقط العملاء ذوي حد صالح (> 0)
    'total_limit', COALESCE(
      SUM(credit_limit) FILTER (
        WHERE credit_limit > 0
          AND payment_terms <> 'cash'
          AND is_active = true
      ), 0
    ),

    -- إجمالي المستخدم: رصيد كل غير النقديين النشطين
    'total_used', COALESCE(
      SUM(current_balance) FILTER (
        WHERE payment_terms <> 'cash'
          AND is_active = true
      ), 0
    ),

    -- المتاح: SUM(GREATEST(0, limit - balance)) لكل عميل ذي حد صالح
    -- صحيح حتى لو بعضهم تجاوز الحد (لا يُؤثر سلباً على مجموع المتاح)
    'total_available', COALESCE(
      SUM(GREATEST(0, credit_limit - current_balance)) FILTER (
        WHERE credit_limit > 0
          AND payment_terms <> 'cash'
          AND is_active = true
      ), 0
    ),

    -- المتجاوزون: balance > limit (أكبر صارم — لا يساوي)
    'count_exceeded', COUNT(*) FILTER (
      WHERE credit_limit > 0
        AND current_balance > credit_limit
        AND payment_terms <> 'cash'
        AND is_active = true
    ),

    -- القريبون من الحد: 80% فأكثر ولم يتجاوزوا
    'count_near_limit', COUNT(*) FILTER (
      WHERE credit_limit > 0
        AND current_balance <= credit_limit
        AND current_balance::numeric / credit_limit >= 0.8
        AND payment_terms <> 'cash'
        AND is_active = true
    ),

    -- إجمالي عملاء الائتمان النشطين (كل غير النقديين)
    'total_credit_customers', COUNT(*) FILTER (
      WHERE payment_terms <> 'cash'
        AND is_active = true
    )
  )
  FROM customers;
$$;

GRANT EXECUTE ON FUNCTION get_credit_portfolio_kpis() TO authenticated;


-- ╔══════════════════════════════════════════════════════════════╗
-- ║  B) get_overdue_batch                                      ║
-- ║  تأخر دفعة العملاء — الحكم النهائي كليًا في SQL            ║
-- ║                                                            ║
-- ║  تربط sales_orders مع customers داخلياً للحصول على          ║
-- ║  credit_days لكل عميل، ثم تُطبّق:                         ║
-- ║    (CURRENT_DATE - delivered_at::date) > credit_days       ║
-- ║  وتُعيد per-customer aggregates جاهزة للواجهة              ║
-- ║                                                            ║
-- ║  منطق التأخر (04b_delivery_rpcs.sql:158):                  ║
-- ║    status IN ('delivered', 'partially_delivered')           ║
-- ║    total_amount > paid_amount                               ║
-- ║    delivered_at IS NOT NULL                                 ║
-- ║    (CURRENT_DATE - delivered_at::date) > customers.credit_days ║
-- ║                                                            ║
-- ║  الواجهة لا تُجري أي مقارنة — تقرأ النتيجة مباشرة          ║
-- ╚══════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION get_overdue_batch(
  p_customer_ids UUID[]
)
RETURNS TABLE (
  customer_id    UUID,
  overdue_count  BIGINT,
  has_overdue    BOOLEAN
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT
    c.id                        AS customer_id,
    COUNT(so.id)                AS overdue_count,
    COUNT(so.id) > 0            AS has_overdue
  FROM customers c
  -- طلب واحد لكل العملاء في الدفعة — لا N+1
  LEFT JOIN sales_orders so
         ON so.customer_id  = c.id
        AND so.status       IN ('delivered', 'partially_delivered')
        AND so.delivered_at IS NOT NULL
        AND so.total_amount  > so.paid_amount              -- متبقٍ فعلي
        -- ✅ الحكم النهائي على التأخر داخل SQL
        AND (CURRENT_DATE - so.delivered_at::date) > c.credit_days
  WHERE c.id = ANY(p_customer_ids)
  GROUP BY c.id;
$$;

GRANT EXECUTE ON FUNCTION get_overdue_batch(UUID[]) TO authenticated;


-- ╔══════════════════════════════════════════════════════════════╗
-- ║  C) get_credit_open_orders                                 ║
-- ║  فواتير العميل المسلَّمة للوحة التفاصيل                    ║
-- ║                                                            ║
-- ║  'confirmed' مستبعد كليًا — التبويب = ديون فعلية بعد التسليم ║
-- ║  'draft' مستبعد                                            ║
-- ║                                                            ║
-- ║  يُعيد:                                                    ║
-- ║    net_remaining       = total - paid - returned (SQL)     ║
-- ║    days_since_delivery = CURRENT_DATE - delivered_at (SQL) ║
-- ╚══════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION get_credit_open_orders(
  p_customer_id UUID
)
RETURNS TABLE (
  id                   UUID,
  order_number         TEXT,
  total_amount         NUMERIC,
  paid_amount          NUMERIC,
  returned_amount      NUMERIC,
  delivered_at         TIMESTAMPTZ,
  status               TEXT,
  net_remaining        NUMERIC,
  days_since_delivery  INTEGER
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT
    so.id,
    so.order_number,
    so.total_amount,
    so.paid_amount,
    COALESCE(so.returned_amount, 0)                             AS returned_amount,

    so.delivered_at,
    so.status::text,

    -- الصافي المتبقي محسوب في SQL
    (so.total_amount - so.paid_amount - COALESCE(so.returned_amount, 0)) AS net_remaining,

    -- الأيام منذ التسليم محسوبة في SQL
    (CURRENT_DATE - so.delivered_at::date)::integer             AS days_since_delivery

  FROM sales_orders so
  WHERE so.customer_id = p_customer_id
    -- ✅ 'confirmed' مستبعد — المسلَّم فقط
    AND so.status IN ('delivered', 'partially_delivered')
    AND so.delivered_at IS NOT NULL
    -- نعرض فقط الفواتير ذات متبقٍ فعلي
    AND (so.total_amount - so.paid_amount - COALESCE(so.returned_amount, 0)) > 0

  ORDER BY so.delivered_at DESC;
$$;

GRANT EXECUTE ON FUNCTION get_credit_open_orders(UUID) TO authenticated;
