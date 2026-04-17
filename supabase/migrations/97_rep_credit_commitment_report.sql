-- ============================================================
-- 97_rep_credit_commitment_report.sql  — v3 (rerunnable)
-- EDARA v2 — تقرير الالتزام الائتماني للمندوبين
--
-- RERUNNABLE DESIGN:
--   يستخدم DROP FUNCTION IF EXISTS قبل كل CREATE
--   آمن للتطبيق على قاعدة بيانات سبق تطبيق الإصدار القديم
--
-- ─── التغييرات في v3 ──────────────────────────────────────────
-- ✅ إزالة role-based filter (sales_rep_ids CTE) نهائياً
-- ✅ الظهور في التقرير يُبنى على واقع المحفظة: assigned_rep_id
--    أي مستخدم له عملاء نشطون مسندون إليه وعليهم current_balance > 0
--    يظهر في التقرير — بلا قيد على اسم الدور
-- ✅ إضافة صف صناعي "غير مسند" لعملاء:
--    is_active=true AND current_balance > 0 AND assigned_rep_id IS NULL
-- ✅ حقول مساعدة جديدة: is_unassigned, sort_order, customers_count
-- ✅ get_rep_credit_commitment_detail يدعم p_rep_id = NULL
--    (يُعيد عملاء غير مسندين فقط — بدون فواتير أو إيصالات)
-- ✅ في قسم العملاء: status_text = payment_terms، amount_3 = credit_days
--
-- الفلسفة المحافظة عليها من v2:
--   - محفظة المتابعة = customers.current_balance (تشمل الافتتاحية)
--   - المديونية المنشأة = orders.rep_id (لا تُنسب لـ "غير مسند")
--   - التحصيلات = receipts.collected_by (لا تُنسب لـ "غير مسند")
--   - التأخر: GREATEST(0, total - paid - returned) > 0
--             AND (CURRENT_DATE - delivered_at::date) > credit_days
--   - لا N+1، مطلب واحد لكل وظيفة
--   - قراءة فقط — لا INSERT، لا UPDATE، لا triggers
--
-- المصادر المعتمدة:
--   customers:        id, code, name, current_balance, opening_balance,
--                     credit_limit, credit_days, payment_terms, is_active,
--                     assigned_rep_id
--   sales_orders:     id, order_number, rep_id, customer_id, status,
--                     total_amount, paid_amount, returned_amount, delivered_at
--   payment_receipts: id, number, customer_id, amount, status,
--                     collected_by, reviewed_at
--   profiles:         id, full_name
-- ============================================================


-- ─── DROP للنسخ القديمة (return type تغيّر في v3) ─────────────
-- يضمن إعادة التشغيل الآمن بدون فشل
DROP FUNCTION IF EXISTS get_rep_credit_commitment_report();
DROP FUNCTION IF EXISTS get_rep_credit_commitment_detail(UUID);


-- ╔══════════════════════════════════════════════════════════════╗
-- ║  A) get_rep_credit_commitment_report()   v3                ║
-- ║  تقرير الالتزام الائتماني — تجميع كامل بطلب واحد           ║
-- ║                                                            ║
-- ║  الفرز:                                                    ║
-- ║    sort_order=0: مسؤولو المحافظ الحقيقيون                  ║
-- ║      → تنازلياً بقيمة المحفظة                             ║
-- ║    sort_order=1: صف "غير مسند"                             ║
-- ║      → يظهر دائماً في نهاية الجدول                        ║
-- ╚══════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION get_rep_credit_commitment_report()
RETURNS TABLE (
  rep_id                   UUID,       -- NULL للصف الصناعي "غير مسند"
  rep_name                 TEXT,       -- 'غير مسند' للصف الصناعي
  is_unassigned            BOOLEAN,    -- true للصف الصناعي فقط
  sort_order               INTEGER,    -- 0=مسؤول حقيقي، 1=غير مسند
  -- محفظة المتابعة الحالية
  portfolio_balance        NUMERIC,    -- SUM(current_balance) — يشمل الافتتاحية
  customers_count          BIGINT,     -- إجمالي العملاء المسندين (نشطون)
  customers_with_balance   BIGINT,     -- منهم: لديهم current_balance > 0
  overdue_customers_count  BIGINT,     -- منهم: لديهم فواتير متأخرة صافيها > 0
  -- المديونية المنشأة (attribution: sales_orders.rep_id)
  created_debt             NUMERIC,    -- 0 للصف الصناعي
  -- التحصيلات (attribution: payment_receipts.collected_by)
  confirmed_collections    NUMERIC     -- 0 للصف الصناعي
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  WITH

  -- ─── 1. قائمة مسؤولي المحافظ الحاليين ──────────────────────
  -- الظهور في التقرير = وجود عملاء نشطون مدينون مسندون فعلاً
  -- لا قيد على role name — المسؤولية الفعلية هي المعيار
  all_reps AS (
    SELECT DISTINCT assigned_rep_id AS rep_id
    FROM customers
    WHERE is_active     = true
      AND current_balance > 0
      AND assigned_rep_id IS NOT NULL
  ),

  -- ─── 2. محفظة المتابعة: تجميع حسب assigned_rep_id ───────────
  -- يشمل كل العملاء النشطين المسندين (حتى من رصيدهم صفر)
  -- لإظهار الحجم الحقيقي للمحفظة
  portfolio AS (
    SELECT
      c.assigned_rep_id                                          AS rep_id,
      SUM(c.current_balance)                                     AS portfolio_balance,
      COUNT(*)                                                   AS customers_count,
      COUNT(*) FILTER (WHERE c.current_balance > 0)             AS customers_with_balance
    FROM customers c
    WHERE c.is_active = true
      AND c.assigned_rep_id IS NOT NULL
    GROUP BY c.assigned_rep_id
  ),

  -- ─── 3. العملاء المتأخرون (مسندون) ──────────────────────────
  -- الشرط: صافي المتبقي الفعلي > 0 BAnd أيام التسليم > credit_days
  -- متسق مع created_debt (يشمل returned_amount)
  overdue AS (
    SELECT
      c.assigned_rep_id                                          AS rep_id,
      COUNT(DISTINCT c.id)                                       AS overdue_customers_count
    FROM customers c
    INNER JOIN sales_orders so
           ON so.customer_id  = c.id
          AND so.status       IN ('delivered', 'partially_delivered')
          AND so.delivered_at IS NOT NULL
          AND GREATEST(0,
                so.total_amount
                - COALESCE(so.paid_amount,    0)
                - COALESCE(so.returned_amount, 0)
              ) > 0
          AND (CURRENT_DATE - so.delivered_at::date) > c.credit_days
    WHERE c.is_active = true
      AND c.assigned_rep_id IS NOT NULL
    GROUP BY c.assigned_rep_id
  ),

  -- ─── 4. المديونية المنشأة (attribution: orders.rep_id) ───────
  -- لا تُنسب إلى "غير مسند" — الإسناد التاريخي عبر orders.rep_id
  created AS (
    SELECT
      so.rep_id,
      SUM(
        GREATEST(0,
          so.total_amount
          - COALESCE(so.paid_amount,     0)
          - COALESCE(so.returned_amount, 0)
        )
      )                                                          AS created_debt
    FROM sales_orders so
    WHERE so.rep_id IS NOT NULL
      AND so.status IN ('delivered', 'partially_delivered')
    GROUP BY so.rep_id
  ),

  -- ─── 5. التحصيلات المؤكدة (attribution: receipts.collected_by) ─
  -- لا تُنسب إلى "غير مسند" — الإسناد التاريخي عبر collected_by
  collections AS (
    SELECT
      pr.collected_by                                            AS rep_id,
      SUM(pr.amount)                                             AS confirmed_collections
    FROM payment_receipts pr
    WHERE pr.status       = 'confirmed'
      AND pr.collected_by IS NOT NULL
    GROUP BY pr.collected_by
  ),

  -- ─── 6. الصف الصناعي: محفظة العملاء غير المسندين ────────────
  -- شرط: is_active=true AND current_balance > 0 AND assigned_rep_id IS NULL
  -- هذا الصف يمثل مسؤولية بلا مسؤول — تحتاج متابعة يدوية
  unassigned_portfolio AS (
    SELECT
      SUM(c.current_balance)                                     AS portfolio_balance,
      COUNT(*)                                                   AS customers_count,
      COUNT(*) FILTER (WHERE c.current_balance > 0)             AS customers_with_balance
    FROM customers c
    WHERE c.is_active     = true
      AND c.current_balance > 0
      AND c.assigned_rep_id IS NULL
  ),

  -- ─── 7. المتأخرون من العملاء غير المسندين ────────────────────
  unassigned_overdue AS (
    SELECT COUNT(DISTINCT c.id)                                  AS overdue_customers_count
    FROM customers c
    INNER JOIN sales_orders so
           ON so.customer_id  = c.id
          AND so.status       IN ('delivered', 'partially_delivered')
          AND so.delivered_at IS NOT NULL
          AND GREATEST(0,
                so.total_amount
                - COALESCE(so.paid_amount,    0)
                - COALESCE(so.returned_amount, 0)
              ) > 0
          AND (CURRENT_DATE - so.delivered_at::date) > c.credit_days
    WHERE c.is_active = true
      AND c.assigned_rep_id IS NULL
  )

  -- ── صفوف مسؤولي المحافظ الحقيقيين (sort_order = 0) ──────────
  SELECT
    ar.rep_id,
    COALESCE(pr_prof.full_name, ar.rep_id::text)                AS rep_name,
    false                                                        AS is_unassigned,
    0                                                            AS sort_order,
    COALESCE(pf.portfolio_balance,       0)                     AS portfolio_balance,
    COALESCE(pf.customers_count,         0)                     AS customers_count,
    COALESCE(pf.customers_with_balance,  0)                     AS customers_with_balance,
    COALESCE(ov.overdue_customers_count, 0)                     AS overdue_customers_count,
    COALESCE(cr.created_debt,            0)                     AS created_debt,
    COALESCE(co.confirmed_collections,   0)                     AS confirmed_collections

  FROM all_reps ar
  LEFT JOIN profiles    pr_prof ON pr_prof.id   = ar.rep_id
  LEFT JOIN portfolio   pf      ON pf.rep_id    = ar.rep_id
  LEFT JOIN overdue     ov      ON ov.rep_id    = ar.rep_id
  LEFT JOIN created     cr      ON cr.rep_id    = ar.rep_id
  LEFT JOIN collections co      ON co.rep_id    = ar.rep_id

  UNION ALL

  -- ── صف "غير مسند" (sort_order = 1، يظهر دائماً في نهاية الجدول) ─
  -- يُدرج فقط إذا وُجد عملاء غير مسندين ذوو رصيد فعلي
  SELECT
    NULL::uuid                                                   AS rep_id,
    'غير مسند'                                                   AS rep_name,
    true                                                         AS is_unassigned,
    1                                                            AS sort_order,
    COALESCE(up.portfolio_balance,      0)                       AS portfolio_balance,
    COALESCE(up.customers_count,        0)                       AS customers_count,
    COALESCE(up.customers_with_balance, 0)                       AS customers_with_balance,
    COALESCE(uo.overdue_customers_count,0)                       AS overdue_customers_count,
    0                                                            AS created_debt,
    0                                                            AS confirmed_collections

  FROM unassigned_portfolio up
  CROSS JOIN unassigned_overdue uo
  -- فقط إذا كان هناك رصيد فعلي لعملاء غير مسندين
  WHERE COALESCE(up.portfolio_balance, 0) > 0

  ORDER BY sort_order ASC, portfolio_balance DESC NULLS LAST;
$$;

GRANT EXECUTE ON FUNCTION get_rep_credit_commitment_report() TO authenticated;


-- ╔══════════════════════════════════════════════════════════════╗
-- ║  B) get_rep_credit_commitment_detail(UUID)   v3            ║
-- ║  تفصيل مسؤول واحد — 3 أقسام (أو صف "غير مسند")           ║
-- ║                                                            ║
-- ║  p_rep_id IS NOT NULL:                                     ║
-- ║    القسم 1: عملاء المسند إليهم حالياً (is_active=true)    ║
-- ║    القسم 2: فواتيره المسلَّمة ذات صافي متبقٍ > 0            ║
-- ║    القسم 3: إيصالاته المؤكدة                               ║
-- ║                                                            ║
-- ║  p_rep_id IS NULL (صف "غير مسند"):                        ║
-- ║    القسم 1: عملاء غير مسندين نشطون وعليهم رصيد > 0        ║
-- ║    القسم 2: فارغ (لا attribution لـ "غير مسند")           ║
-- ║    القسم 3: فارغ (لا attribution لـ "غير مسند")           ║
-- ║                                                            ║
-- ║  تعيين الحقول للعملاء (توثيق الاستخدام المزدوج):          ║
-- ║    amount_1   = current_balance                            ║
-- ║    amount_2   = credit_limit                               ║
-- ║    amount_3   = credit_days (INTEGER → NUMERIC)            ║
-- ║    status_text = payment_terms                             ║
-- ║    date_1     = NULL                                       ║
-- ║    extra_int  = NULL                                       ║
-- ╚══════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION get_rep_credit_commitment_detail(
  p_rep_id UUID  -- NULL = عرض تفاصيل "غير مسند"
)
RETURNS TABLE (
  section_type   TEXT,       -- 'customer' | 'order' | 'receipt'
  entity_id      UUID,
  entity_ref     TEXT,       -- كود العميل | رقم الطلب | رقم الإيصالة
  entity_name    TEXT,
  amount_1       NUMERIC,    -- current_balance | net_remaining | receipt_amount
  amount_2       NUMERIC,    -- credit_limit    | total_amount  | NULL
  amount_3       NUMERIC,    -- credit_days     | paid_amount   | NULL
  date_1         DATE,       -- NULL            | delivered_at  | reviewed_at
  status_text    TEXT,       -- payment_terms   | order_status  | receipt_status
  extra_int      INTEGER     -- NULL            | days_since_delivery | NULL
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$

  -- ─── القسم 1: العملاء ─────────────────────────────────────────
  -- p_rep_id IS NULL     → عملاء غير مسندين (current_balance > 0)
  -- p_rep_id IS NOT NULL → العملاء المسندون لهذا المسؤول
  SELECT
    'customer'::text                                             AS section_type,
    c.id                                                         AS entity_id,
    c.code                                                       AS entity_ref,
    c.name                                                       AS entity_name,
    c.current_balance                                            AS amount_1,
    c.credit_limit                                               AS amount_2,
    c.credit_days::numeric                                       AS amount_3,   -- credit_days
    NULL::date                                                   AS date_1,
    c.payment_terms                                              AS status_text, -- payment_terms
    NULL::integer                                                AS extra_int

  FROM customers c
  WHERE c.is_active = true
    AND (
      -- مسار الصف الصناعي
      (p_rep_id IS NULL     AND c.assigned_rep_id IS NULL AND c.current_balance > 0)
      OR
      -- مسار المسؤول الحقيقي
      (p_rep_id IS NOT NULL AND c.assigned_rep_id = p_rep_id)
    )

  UNION ALL

  -- ─── القسم 2: الفواتير المنشأة بواسطة المسؤول ─────────────────
  -- فقط عند p_rep_id IS NOT NULL
  -- 'confirmed' مستبعد كليًا — الديون الفعلية بعد التسليم فقط
  SELECT
    'order'::text                                                AS section_type,
    so.id                                                        AS entity_id,
    so.order_number                                              AS entity_ref,
    c2.name                                                      AS entity_name,
    GREATEST(0,
      so.total_amount
      - COALESCE(so.paid_amount,     0)
      - COALESCE(so.returned_amount, 0)
    )                                                            AS amount_1,    -- net_remaining
    so.total_amount                                              AS amount_2,
    COALESCE(so.paid_amount, 0)                                  AS amount_3,    -- paid_amount
    so.delivered_at::date                                        AS date_1,
    so.status::text                                              AS status_text,
    (CURRENT_DATE - so.delivered_at::date)::integer              AS extra_int

  FROM sales_orders so
  INNER JOIN customers c2 ON c2.id = so.customer_id
  WHERE p_rep_id IS NOT NULL
    AND so.rep_id = p_rep_id
    AND so.status IN ('delivered', 'partially_delivered')
    AND so.delivered_at IS NOT NULL
    AND GREATEST(0,
          so.total_amount
          - COALESCE(so.paid_amount,     0)
          - COALESCE(so.returned_amount, 0)
        ) > 0

  UNION ALL

  -- ─── القسم 3: الإيصالات التي حصّلها المسؤول ──────────────────
  -- فقط عند p_rep_id IS NOT NULL
  -- status = 'confirmed' فقط
  SELECT
    'receipt'::text                                              AS section_type,
    pr.id                                                        AS entity_id,
    pr.number                                                    AS entity_ref,  -- ✅ payment_receipts.number
    c3.name                                                      AS entity_name,
    pr.amount                                                    AS amount_1,
    NULL::numeric                                                AS amount_2,
    NULL::numeric                                                AS amount_3,
    pr.reviewed_at::date                                         AS date_1,
    pr.status::text                                              AS status_text,
    NULL::integer                                                AS extra_int

  FROM payment_receipts pr
  INNER JOIN customers c3 ON c3.id = pr.customer_id
  WHERE p_rep_id IS NOT NULL
    AND pr.collected_by = p_rep_id
    AND pr.status = 'confirmed'

  ORDER BY section_type, date_1 DESC NULLS LAST;
$$;

GRANT EXECUTE ON FUNCTION get_rep_credit_commitment_detail(UUID) TO authenticated;
