-- ════════════════════════════════════════════════════════════
-- EDARA v2 — Migration 08: Performance Hardening
-- تحسينات أداء عميقة لمئات الآلاف من الصفوف
-- ════════════════════════════════════════════════════════════
--
-- التحسينات:
-- 1. تحويل check_permission() من plpgsql → SQL (inlinable)
-- 2. فهارس created_at DESC على كل الجداول المُرتبة
-- 3. فهارس trgm إضافية للبحث النصي
-- 4. ANALYZE شامل
--
-- Idempotent: آمن للتشغيل المتكرر
-- لا يُغيّر أي سلوك وظيفي — فقط يُسرّع الأداء
-- ════════════════════════════════════════════════════════════


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 1. check_permission() — تحويل من plpgsql إلى SQL        ║
-- ║                                                           ║
-- ║ المشكلة: plpgsql = "black box" → استدعاء منفصل لكل صف   ║
-- ║ الحل: SQL = inlinable → PostgreSQL يدمجها في خطة الاستعلام║
-- ║                                                           ║
-- ║ السلوك مطابق 100% للنسخة القديمة:                         ║
-- ║ - Override فردي أولاً (granted/revoked)                   ║
-- ║ - ثم صلاحيات الدور (wildcard أو محددة)                    ║
-- ╚═══════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.check_permission(
  p_user_id UUID, p_permission TEXT
) RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    -- 1) Override فردي (أعلى أولوية)
    -- إذا وُجد override → يُرجع قيمة granted (true/false)
    -- إذا لم يُوجد → NULL → ينتقل للخطوة 2
    (
      SELECT granted
      FROM user_permission_overrides
      WHERE user_id = p_user_id
        AND permission = p_permission
        AND (expires_at IS NULL OR expires_at > now())
      LIMIT 1
    ),
    -- 2) صلاحيات الدور (wildcard أو محددة)
    EXISTS (
      SELECT 1
      FROM user_roles ur
      JOIN role_permissions rp ON rp.role_id = ur.role_id
      WHERE ur.user_id = p_user_id
        AND ur.is_active = true
        AND (rp.permission = p_permission OR rp.permission = '*')
    )
  )
$$;


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 2. فهارس created_at DESC — لتسريع ORDER BY + RANGE      ║
-- ║                                                           ║
-- ║ كل استعلام قائمة يستخدم: ORDER BY created_at DESC        ║
-- ║ بدون فهرس = Sort operation مُكلف مع 100K+ صف             ║
-- ╚═══════════════════════════════════════════════════════════╝

-- ─── المالية ───
CREATE INDEX IF NOT EXISTS idx_expenses_created_at_desc
  ON expenses(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_receipts_created_at_desc
  ON payment_receipts(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_vault_txn_created_at_desc
  ON vault_transactions(vault_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_custody_txn_created_at_desc
  ON custody_transactions(custody_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_je_created_at_desc
  ON journal_entries(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_customer_ledger_created_at_desc
  ON customer_ledger(customer_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_supplier_ledger_created_at_desc
  ON supplier_ledger(supplier_id, created_at DESC);

-- ─── المخزون ───
CREATE INDEX IF NOT EXISTS idx_transfers_created_at_desc
  ON stock_transfers(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_adjustments_created_at_desc
  ON stock_adjustments(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_stock_movements_created_at_desc
  ON stock_movements(created_at DESC);

-- ─── البيانات الأساسية ───
CREATE INDEX IF NOT EXISTS idx_customers_created_at_desc
  ON customers(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_suppliers_created_at_desc
  ON suppliers(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_products_created_at_desc
  ON products(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at_desc
  ON audit_logs(created_at DESC);


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 3. فهارس تصفية إضافية — الأكثر طلباً في القوائم         ║
-- ╚═══════════════════════════════════════════════════════════╝

-- expenses: تصفية بالحالة (أكثر فلتر شيوعاً)
CREATE INDEX IF NOT EXISTS idx_expenses_status
  ON expenses(status);

-- payment_receipts: تصفية بالحالة
CREATE INDEX IF NOT EXISTS idx_receipts_status
  ON payment_receipts(status);

-- stock_transfers: تصفية بالحالة
CREATE INDEX IF NOT EXISTS idx_transfers_status
  ON stock_transfers(status);

-- stock_adjustments: تصفية بالحالة
CREATE INDEX IF NOT EXISTS idx_adjustments_status
  ON stock_adjustments(status);

-- journal_entries: تصفية بالمصدر + الحالة
CREATE INDEX IF NOT EXISTS idx_je_source_type
  ON journal_entries(source_type);

-- customers: تصفية بالمحافظة والمندوب
CREATE INDEX IF NOT EXISTS idx_customers_governorate
  ON customers(governorate_id)
  WHERE governorate_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_customers_rep
  ON customers(assigned_rep_id)
  WHERE assigned_rep_id IS NOT NULL;

-- products: تصفية بالتصنيف والعلامة
CREATE INDEX IF NOT EXISTS idx_products_category
  ON products(category_id)
  WHERE category_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_products_brand
  ON products(brand_id)
  WHERE brand_id IS NOT NULL;


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 4. فهارس trgm إضافية — البحث النصي المرن                ║
-- ║                                                           ║
-- ║ 07 أضاف trgm على customers.name و products.name فقط     ║
-- ║ لكن البحث ilike يُستخدم على حقول أخرى أيضاً              ║
-- ╚═══════════════════════════════════════════════════════════╝

-- suppliers: بحث بالاسم
CREATE INDEX IF NOT EXISTS idx_suppliers_name_trgm
  ON suppliers USING gin (name gin_trgm_ops);

-- customers: بحث بالكود والهاتف
CREATE INDEX IF NOT EXISTS idx_customers_code_trgm
  ON customers USING gin (code gin_trgm_ops);

-- products: بحث بالـ SKU
CREATE INDEX IF NOT EXISTS idx_products_sku_trgm
  ON products USING gin (sku gin_trgm_ops);


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 5. فهارس RLS المُحسّنة — تقليل subquery cost             ║
-- ╚═══════════════════════════════════════════════════════════╝

-- vault_transactions: RLS يستخدم vault_id IN (SELECT id FROM vaults WHERE ...)
CREATE INDEX IF NOT EXISTS idx_vault_txn_vault_id
  ON vault_transactions(vault_id);

-- custody_transactions: RLS يستخدم custody_id IN (SELECT id FROM custody_accounts WHERE ...)
CREATE INDEX IF NOT EXISTS idx_custody_txn_custody_id
  ON custody_transactions(custody_id);

-- stock_batches: RLS يستخدم stock_id IN (SELECT id FROM stock WHERE ...)
CREATE INDEX IF NOT EXISTS idx_stock_batches_stock_id
  ON stock_batches(stock_id);

-- journal_entry_lines: JOIN مع journal_entries
CREATE INDEX IF NOT EXISTS idx_je_lines_entry_id
  ON journal_entry_lines(entry_id);


-- ╔═══════════════════════════════════════════════════════════╗
-- ║ 6. ANALYZE شامل — تحديث إحصائيات المُخطط                 ║
-- ╚═══════════════════════════════════════════════════════════╝

ANALYZE expenses;
ANALYZE payment_receipts;
ANALYZE vault_transactions;
ANALYZE custody_transactions;
ANALYZE journal_entries;
ANALYZE journal_entry_lines;
ANALYZE customer_ledger;
ANALYZE supplier_ledger;
ANALYZE stock_transfers;
ANALYZE stock_adjustments;
ANALYZE stock_batches;
ANALYZE stock_movements;
ANALYZE customers;
ANALYZE suppliers;
ANALYZE products;
ANALYZE user_permission_overrides;
ANALYZE role_permissions;
ANALYZE user_roles;
