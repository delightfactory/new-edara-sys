-- ============================================================
-- 04b_delivery_rpcs.sql
-- EDARA v2 — دوال التسليم الذكي والبحث والائتمان
-- Idempotent: آمن للتشغيل عدة مرات (CREATE OR REPLACE + ON CONFLICT)
--
-- المحتوى:
--   A) Trigger: إنشاء عهدة تلقائية لكل مستخدم جديد
--   B) RPC: check_customer_credit — فحص الائتمان الذري
--   C) RPC: search_products_with_stock — بحث مع مخزون كل المخازن
--   D) RPC: get_user_payment_options — خيارات الدفع المتاحة للمستخدم
--
-- ═══ تدقيق متقاطع مع كل ملفات الميجريشن ═══
--   ✓ جدول المخزون: stock — 02_master_data.sql:373
--     أعمدة: quantity, reserved_quantity, available_quantity (GENERATED STORED)
--     UNIQUE(warehouse_id, product_id)
--   ✓ جدول العملاء: customers — 02_master_data.sql:198
--     أعمدة: payment_terms CHECK IN('cash','credit','mixed')
--     credit_limit NUMERIC(14,2), credit_days INT
--     current_balance NUMERIC(14,2) — أُضيف في 02_master_data.sql:1131
--   ✓ جدول الطلبات: sales_orders — 04_sales_system.sql:139
--     أعمدة: total_amount, paid_amount, status (enum), customer_id, created_at
--   ✓ custody_accounts: 03_financial_infrastructure.sql:202
--     employee_id UUID UNIQUE NOT NULL
--   ✓ v_customer_balances: ⚠️  محذوفة في 03h_extreme_performance.sql:137
--     → استُبدلت بـ customers.current_balance (cached via trigger)
--   ✓ check_permission(): 01_foundation.sql:171 — STABLE SECURITY DEFINER
--   ✓ pg_trgm extension: 01_foundation.sql:9 — مفعّلة
--   ✓ handle_new_user(): 01_foundation.sql:43 — يُدرج في profiles
--     → التسلسل: auth.users → profiles → trg_auto_custody (لا تعارض)
-- ============================================================


-- ╔══════════════════════════════════════════════════════════════╗
-- ║  A) Trigger: عهدة تلقائية لكل مستخدم جديد                 ║
-- ╚══════════════════════════════════════════════════════════════╝

-- ── سلسلة إنشاء المستخدم الكاملة: ──────────────────────────
-- 1. auth.users INSERT
-- 2. → trg_on_auth_user_created → handle_new_user()
-- 3.   → profiles INSERT
-- 4.   → trg_auto_custody_on_profile (هذا الملف)
-- 5.     → custody_accounts INSERT (ON CONFLICT DO NOTHING)
-- ـ لا تعارض: handle_new_user يُدرج في profiles، والـ trigger هنا يعمل AFTER INSERT
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION auto_create_custody_account()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- عهدة افتراضية بحد 50,000 ج.م — قابلة للتعديل لاحقاً من إدارة العُهد
  -- ON CONFLICT (employee_id) DO NOTHING: Idempotent — آمن عند التكرار
  INSERT INTO custody_accounts (employee_id, max_balance, current_balance, is_active)
  VALUES (NEW.id, 50000, 0, true)
  ON CONFLICT (employee_id) DO NOTHING;

  RETURN NEW;
END;
$$;

-- إسقاط القديم (إن وُجد) وتسجيل الجديد
DROP TRIGGER IF EXISTS trg_auto_custody_on_profile ON profiles;
CREATE TRIGGER trg_auto_custody_on_profile
  AFTER INSERT ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION auto_create_custody_account();

-- ── تطبيق رجعي ───────────────────────────────────────────────
-- ينشئ عهدة لكل مستخدم موجود ليس لديه عهدة حالياً
-- آمن: WHERE NOT EXISTS + ON CONFLICT = حزام ومشبك
INSERT INTO custody_accounts (employee_id, max_balance, current_balance, is_active)
SELECT p.id, 50000, 0, true
FROM profiles p
WHERE NOT EXISTS (
  SELECT 1 FROM custody_accounts ca WHERE ca.employee_id = p.id
)
ON CONFLICT (employee_id) DO NOTHING;


-- ╔══════════════════════════════════════════════════════════════╗
-- ║  B) RPC: check_customer_credit                             ║
-- ║  فحص ذري وسريع لائتمان العميل قبل التسليم                  ║
-- ║                                                            ║
-- ║  ═══ مصادر البيانات: ═══                                    ║
-- ║  ✓ customers.current_balance: رصيد مُخزّن (cached)         ║
-- ║    يُحدّث تلقائياً عبر trigger في 03h_extreme_performance   ║
-- ║    ⚠️  لا نستخدم v_customer_balances (محذوفة في 03h)        ║
-- ║  ✓ sales_orders: لفحص الفواتير المتأخرة (المفتوحة فعلاً)   ║
-- ║    بدلاً من customer_ledger (لا يتغير بعد السداد)           ║
-- ╚══════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION check_customer_credit(
  p_customer_id  UUID,
  p_amount       NUMERIC   -- المبلغ الآجل المطلوب فحصه
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cust            RECORD;
  v_available       NUMERIC  := 0;
  v_overdue_days    INTEGER  := 0;
  v_oldest_invoice  TEXT     := NULL;
  v_overdue_count   BIGINT   := 0;   -- COUNT() يُعيد BIGINT في PostgreSQL
BEGIN
  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  -- 1. جلب بيانات العميل + الرصيد المُخزّن (استعلام واحد)
  --    customers.current_balance: يُحدّث بـ trigger على customer_ledger
  --    customers.credit_limit:    NUMERIC(14,2) DEFAULT 0
  --    customers.credit_days:     INT DEFAULT 0
  --    customers.payment_terms:   CHECK IN ('cash','credit','mixed')
  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  SELECT
    c.name,
    c.payment_terms,
    COALESCE(c.credit_limit, 0)     AS credit_limit,
    COALESCE(c.credit_days, 0)      AS credit_days,
    COALESCE(c.current_balance, 0)  AS current_balance
  INTO v_cust
  FROM customers c
  WHERE c.id = p_customer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'العميل غير موجود: %', p_customer_id;
  END IF;

  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  -- 2. حساب الائتمان المتاح
  --    current_balance موجب = العميل مدين لنا
  --    available = الحد - المدين الحالي
  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  v_available := v_cust.credit_limit - v_cust.current_balance;

  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  -- 3. فحص الفواتير المتأخرة
  --    نعتمد على sales_orders مباشرة (وليس customer_ledger)
  --    لأن customer_ledger سجل تاريخي لا يُحذف منه شيء →
  --    الاعتماد عليه سيعتبر كل فاتورة قديمة "متأخرة" حتى لو سُددت
  --
  --    الفاتورة المتأخرة = طلب:
  --      • مسلَّم (delivered | partially_delivered)
  --      • غير مسدد بالكامل (total_amount > paid_amount)
  --      • مر عليها أكثر من credit_days يوم من تاريخ التسليم الفعلي
  --    نستخدم delivered_at (وليس created_at) لأن:
  --      - المهلة تبدأ من لحظة التسليم لا من لحظة إنشاء المسودة
  --      - طلب ظل مسودة أسبوعاً ثم سُلِّم لا يحتسب الأسبوع ضمن المهلة
  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  IF v_cust.credit_days > 0 THEN
    SELECT
      COUNT(*)                                                    AS cnt,
      COALESCE(MAX(CURRENT_DATE - so.delivered_at::date), 0)       AS max_days,
      MIN(so.order_number)                                         AS oldest
    INTO v_overdue_count, v_overdue_days, v_oldest_invoice
    FROM sales_orders so
    WHERE so.customer_id  = p_customer_id
      AND so.status       IN ('delivered', 'partially_delivered')
      AND so.total_amount > so.paid_amount
      AND so.delivered_at IS NOT NULL
      AND (CURRENT_DATE - so.delivered_at::date) > v_cust.credit_days;
  END IF;
  -- إذا credit_days = 0 (عميل نقدي) → لا فحص أصلاً → القيم الافتراضية (0) سليمة

  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  -- 4. إعادة النتيجة الكاملة دفعة واحدة
  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  RETURN jsonb_build_object(
    -- بيانات العميل
    'customer_name',    v_cust.name,
    'payment_terms',    v_cust.payment_terms,
    'credit_limit',     v_cust.credit_limit,

    -- الرصيد المدين (من العمود المُخزّن)
    'current_balance',  v_cust.current_balance,
    'available_credit', v_available,
    'requested_amount', p_amount,

    -- قرارات الائتمان
    'can_use_credit',   (v_cust.payment_terms <> 'cash'),
    'credit_ok',        (v_available >= p_amount AND v_cust.payment_terms <> 'cash'),
    'exceeds_limit',    (v_available < p_amount),

    -- الفواتير المتأخرة
    'overdue_count',    COALESCE(v_overdue_count, 0),
    'overdue_days',     COALESCE(v_overdue_days, 0),
    'oldest_invoice',   v_oldest_invoice,
    'has_overdue',      (COALESCE(v_overdue_count, 0) > 0)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION check_customer_credit TO authenticated;


-- ╔══════════════════════════════════════════════════════════════╗
-- ║  C) RPC: search_products_with_stock                        ║
-- ║  بحث ذكي يجمع المخزون عبر كل المخازن المتاحة              ║
-- ║                                                            ║
-- ║  ═══ تدقيق الأعمدة: ═══                                    ║
-- ║  ✓ stock.quantity            NUMERIC(14,4)                 ║
-- ║  ✓ stock.reserved_quantity   NUMERIC(14,4)                 ║
-- ║  ✓ stock.available_quantity  GENERATED (quantity - reserved)║
-- ║  ✓ stock.warehouse_id       → warehouses.is_active         ║
-- ║  ✓ products.min_stock_level NUMERIC(12,2) DEFAULT 0        ║
-- ║  ✓ products.base_unit_id    → units(id,name,symbol)        ║
-- ║  ✓ product_units(product_id,unit_id,...) → units            ║
-- ╚══════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION search_products_with_stock(
  p_query     TEXT,         -- نص البحث (اسم أو SKU)
  p_limit     INT DEFAULT 15
)
RETURNS TABLE (
  id             UUID,
  name           TEXT,
  sku            TEXT,
  selling_price  NUMERIC,
  tax_rate       NUMERIC,
  base_unit_id   UUID,
  base_unit      JSONB,      -- { id, name, symbol }
  product_units  JSONB,      -- [ { id, unit_id, conversion_factor, selling_price, is_sales_unit, unit: {...} } ]
  total_qty      NUMERIC,
  available_qty  NUMERIC,
  reserved_qty   NUMERIC,
  stock_status   TEXT        -- 'available' | 'low' | 'out'
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  WITH
  -- ── مجموع المخزون من جدول stock ──────────────────
  -- stock(warehouse_id, product_id) UNIQUE
  -- available_quantity = GENERATED ALWAYS AS (quantity - reserved_quantity) STORED
  stock_agg AS (
    SELECT
      s.product_id,
      SUM(s.quantity)            AS total_qty,
      SUM(s.available_quantity)  AS available_qty,
      SUM(s.reserved_quantity)   AS reserved_qty
    FROM stock s
    JOIN warehouses w ON w.id = s.warehouse_id AND w.is_active = true
    GROUP BY s.product_id
  ),

  -- ── بحث المنتجات النشطة ────────────────────────
  matching_products AS (
    SELECT
      p.id,
      p.name,
      p.sku,
      p.selling_price,
      COALESCE(p.tax_rate, 0)          AS tax_rate,
      p.base_unit_id,
      COALESCE(p.min_stock_level, 0)   AS min_stock_level,
      jsonb_build_object(
        'id',     u.id,
        'name',   u.name,
        'symbol', u.symbol
      ) AS base_unit_obj
    FROM products p
    JOIN units u ON u.id = p.base_unit_id
    WHERE p.is_active = true
      AND (
        p.name ILIKE '%' || p_query || '%'
        OR p.sku ILIKE '%' || p_query || '%'
      )
    LIMIT p_limit * 3
  )

  SELECT
    mp.id,
    mp.name,
    mp.sku,
    mp.selling_price,
    mp.tax_rate,
    mp.base_unit_id,
    mp.base_unit_obj AS base_unit,

    -- وحدات البيع (correlated subquery)
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id',                pu.id,
            'unit_id',           pu.unit_id,
            'conversion_factor', pu.conversion_factor,
            'selling_price',     pu.selling_price,
            'is_sales_unit',     pu.is_sales_unit,
            'unit', jsonb_build_object(
              'id',     u2.id,
              'name',   u2.name,
              'symbol', u2.symbol
            )
          )
          ORDER BY pu.conversion_factor ASC
        )
        FROM product_units pu
        JOIN units u2 ON u2.id = pu.unit_id
        WHERE pu.product_id = mp.id
      ),
      '[]'::jsonb
    ) AS product_units,

    -- المخزون
    COALESCE(sa.total_qty, 0)     AS total_qty,
    COALESCE(sa.available_qty, 0) AS available_qty,
    COALESCE(sa.reserved_qty, 0)  AS reserved_qty,

    -- حالة المخزون
    CASE
      WHEN COALESCE(sa.available_qty, 0) <= 0 THEN 'out'
      WHEN mp.min_stock_level > 0
       AND COALESCE(sa.available_qty, 0) <= mp.min_stock_level THEN 'low'
      ELSE 'available'
    END AS stock_status

  FROM matching_products mp
  LEFT JOIN stock_agg sa ON sa.product_id = mp.id
  ORDER BY
    CASE
      WHEN COALESCE(sa.available_qty, 0) <= 0 THEN 3
      WHEN mp.min_stock_level > 0
       AND COALESCE(sa.available_qty, 0) <= mp.min_stock_level THEN 2
      ELSE 1
    END ASC,
    COALESCE(sa.available_qty, 0) DESC,
    mp.name ASC
  LIMIT p_limit;
$$;

-- ── فهارس الأداء ──────────────────────────────────

-- فهرس GIN لبحث ILIKE '%query%' (pg_trgm مفعّلة في 01_foundation.sql)
-- B-Tree لا يعمل مع leading wildcard — GIN ضروري هنا
CREATE INDEX IF NOT EXISTS idx_products_name_trgm
  ON products USING GIN (name gin_trgm_ops)
  WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_products_sku_trgm
  ON products USING GIN (sku gin_trgm_ops)
  WHERE is_active = true;

-- فهرس لتسريع تجميع المخزون (stock GROUP BY product_id)
CREATE INDEX IF NOT EXISTS idx_stock_product_wh
  ON stock (product_id, warehouse_id);

-- فهرس لتسريع فحص الفواتير المتأخرة في check_customer_credit
-- يغطي: WHERE customer_id = ? AND status IN (...) AND total_amount > paid_amount
CREATE INDEX IF NOT EXISTS idx_so_customer_status
  ON sales_orders(customer_id, status);

GRANT EXECUTE ON FUNCTION search_products_with_stock TO authenticated;


-- ╔══════════════════════════════════════════════════════════════╗
-- ║  D) RPC: get_user_payment_options                          ║
-- ║  يُحدد خيارات الدفع والخزينة/العهدة المتاحة للمستخدم       ║
-- ║                                                            ║
-- ║  ═══ تدقيق: ═══                                            ║
-- ║  ✓ custody_accounts.employee_id UNIQUE (O(1) lookup)       ║
-- ║  ✓ check_permission() — 01_foundation.sql:171              ║
-- ║  ✓ 'finance.vaults.transact' — صلاحية في role_permissions  ║
-- ║  ✓ vaults.branch_id — REFERENCES branches(id)              ║
-- ║  ✓ vaults: id, name, type, current_balance, is_active      ║
-- ║                                                            ║
-- ║  منطق الأولوية:                                            ║
-- ║    1. عهدة نشطة → cash_destination = 'custody'            ║
-- ║    2. صلاحية خزائن → cash_destination = 'vault'           ║
-- ║    3. لا شيء → cash_destination = NULL                    ║
-- ║       (UI تعرض رسالة خطأ صريحة بدلاً من crash)            ║
-- ╚══════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION get_user_payment_options(
  p_user_id   UUID,
  p_branch_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_custody           RECORD;
  v_has_custody       BOOLEAN := false;
  v_vaults            JSONB   := '[]'::jsonb;
  v_can_manage_vaults BOOLEAN := false;
BEGIN
  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  -- [SECURITY GUARD] منع Spoofing — نفس النمط المعتمد في 04_sales_system.sql
  -- يمنع أي مستخدم من الاستعلام عن عهدة/خزائن مستخدم آخر
  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  -- 1. فحص عهدة المستخدم
  --    custody_accounts.employee_id UNIQUE → O(1)
  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  SELECT
    ca.id,
    ca.current_balance,
    ca.max_balance
  INTO v_custody
  FROM custody_accounts ca
  WHERE ca.employee_id = p_user_id
    AND ca.is_active   = true;

  v_has_custody := FOUND;

  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  -- 2. فحص صلاحية إدارة الخزائن
  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  v_can_manage_vaults := check_permission(p_user_id, 'finance.vaults.transact');

  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  -- 3. جلب الخزائن (فقط لمن لديه صلاحية)
  --    vaults: id, name, type TEXT CHECK('cash','bank','mobile_wallet'),
  --            current_balance, is_active, branch_id
  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  IF v_can_manage_vaults THEN
    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id',      v.id,
          'name',    v.name,
          'type',    v.type,
          'balance', v.current_balance
        )
        ORDER BY v.name
      ),
      '[]'::jsonb
    )
    INTO v_vaults
    FROM vaults v
    WHERE v.is_active = true
      AND (p_branch_id IS NULL OR v.branch_id = p_branch_id);
  END IF;

  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  -- 4. إعادة القرار الكامل للـ UI
  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  RETURN jsonb_build_object(
    -- بيانات العهدة
    'has_custody',      v_has_custody,
    'custody_id',       CASE WHEN v_has_custody THEN v_custody.id              ELSE NULL END,
    'custody_balance',  CASE WHEN v_has_custody THEN v_custody.current_balance ELSE 0    END,
    'custody_max',      CASE WHEN v_has_custody THEN v_custody.max_balance     ELSE 0    END,

    -- بيانات الخزائن
    'can_manage_vaults',  v_can_manage_vaults,
    'available_vaults',   v_vaults,

    -- القرار: أين يذهب التحصيل النقدي؟
    -- NULL = لا وجهة متاحة → UI تمنع المتابعة وتعرض رسالة خطأ صريحة
    'cash_destination',
      CASE
        WHEN v_has_custody       THEN 'custody'
        WHEN v_can_manage_vaults THEN 'vault'
        ELSE                          NULL
      END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_user_payment_options TO authenticated;
