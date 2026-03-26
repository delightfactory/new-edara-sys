-- ============================================================
-- 04_sales_system.sql
-- EDARA v2 — نظام المبيعات الشامل
-- الاعتماديات + الجداول + الأمان + الدوال الذرية
-- Idempotent: آمن للتشغيل عدة مرات
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1.0 تعديلات مطلوبة على الجداول الموجودة
-- ────────────────────────────────────────────────────────────

-- إضافة عمود allocated_to لدعم التوزيع الذكي للتحصيل
ALTER TABLE customer_ledger
  ADD COLUMN IF NOT EXISTS allocated_to UUID REFERENCES customer_ledger(id);

CREATE INDEX IF NOT EXISTS idx_cust_ledger_allocated ON customer_ledger(allocated_to);

-- إزالة القيد الفريد القديم (يمنع تسجيل credit لنفس المصدر عدة مرات)
-- لأن التحصيل الواحد يمكن أن يُوزَّع على عدة فواتير = عدة أسطر credit بنفس source
ALTER TABLE customer_ledger DROP CONSTRAINT IF EXISTS uq_cust_ledger_source;


-- ╔══════════════════════════════════════════════════════════════╗
-- ║  المرحلة ١: الاعتماديات (صلاحيات + إعدادات + شحن)         ║
-- ╚══════════════════════════════════════════════════════════════╝


-- ────────────────────────────────────────────────────────────
-- 1.1 صلاحيات جديدة
-- ────────────────────────────────────────────────────────────

-- تعديل سعر البيع → المدير فقط
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, 'sales.orders.edit_price'
FROM roles r WHERE r.name IN ('super_admin')
ON CONFLICT DO NOTHING;

-- تخطي سياسة الائتمان → المدير فقط
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, 'sales.orders.override_credit'
FROM roles r WHERE r.name IN ('super_admin')
ON CONFLICT DO NOTHING;

-- تعديل طلب مؤكد → المدير + مشرف المبيعات
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, 'sales.orders.edit_confirmed'
FROM roles r WHERE r.name IN ('super_admin', 'branch_manager', 'sales_supervisor')
ON CONFLICT DO NOTHING;

-- إدارة شركات الشحن → المدير
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, 'sales.shipping.manage'
FROM roles r WHERE r.name IN ('super_admin', 'branch_manager')
ON CONFLICT DO NOTHING;


-- ────────────────────────────────────────────────────────────
-- 1.2 إعدادات جديدة
-- ────────────────────────────────────────────────────────────

INSERT INTO company_settings (key, value, type, description, category, is_public) VALUES
  ('sales.tax_enabled',         'false', 'boolean', 'تفعيل حساب الضريبة',              'sales', false),
  ('sales.default_tax_rate',    '14',    'number',  'نسبة الضريبة الافتراضية %',        'sales', false),
  ('sales.min_order_enabled',   'false', 'boolean', 'تفعيل الحد الأدنى لقيمة الطلب',    'sales', false),
  ('sales.min_order_amount',    '0',     'number',  'الحد الأدنى لقيمة الطلب',          'sales', false),
  ('sales.max_order_enabled',   'false', 'boolean', 'تفعيل الحد الأقصى بدون موافقة',    'sales', false),
  ('sales.max_order_amount',    '0',     'number',  'الحد الأقصى بدون موافقة',          'sales', false),
  ('sales.max_discount_percent','100',   'number',  'الحد الأقصى لنسبة الخصم %',        'sales', false)
ON CONFLICT (key) DO NOTHING;


-- ────────────────────────────────────────────────────────────
-- 1.3 جدول شركات الشحن
-- ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS shipping_companies (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  phone       TEXT,
  email       TEXT,
  notes       TEXT,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  created_by  UUID REFERENCES profiles(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_shipping_companies_updated_at ON shipping_companies;
CREATE TRIGGER trg_shipping_companies_updated_at
  BEFORE UPDATE ON shipping_companies
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE shipping_companies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "shipping_read" ON shipping_companies;
CREATE POLICY "shipping_read" ON shipping_companies FOR SELECT
  USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "shipping_write" ON shipping_companies;
CREATE POLICY "shipping_write" ON shipping_companies FOR ALL
  USING (check_permission(auth.uid(), 'sales.shipping.manage'));


-- ╔══════════════════════════════════════════════════════════════╗
-- ║  المرحلة ٢: الجداول الأساسية                                ║
-- ╚══════════════════════════════════════════════════════════════╝


-- ────────────────────────────────────────────────────────────
-- 2.0 ENUM + تسلسل الترقيم
-- ────────────────────────────────────────────────────────────

DO $$ BEGIN
  CREATE TYPE sales_order_status AS ENUM (
    'draft', 'confirmed', 'partially_delivered', 'delivered', 'completed', 'cancelled'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;

DO $$ BEGIN
  CREATE TYPE sales_return_status AS ENUM ('draft', 'confirmed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;

DO $$ BEGIN
  CREATE TYPE delivery_method AS ENUM ('direct', 'shipping', 'pickup');
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;

DO $$ BEGIN
  CREATE TYPE payment_method AS ENUM ('cash', 'bank_transfer', 'instapay', 'cheque', 'wallet');
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;

CREATE SEQUENCE IF NOT EXISTS sales_order_seq START 1;
CREATE SEQUENCE IF NOT EXISTS sales_return_seq START 1;


-- ────────────────────────────────────────────────────────────
-- 2.1 جدول أوامر البيع (الرأسية)
-- ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS sales_orders (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_number          TEXT UNIQUE NOT NULL,
  
  -- الأطراف
  customer_id           UUID NOT NULL REFERENCES customers(id),
  rep_id                UUID REFERENCES profiles(id),           -- المندوب المسؤول
  created_by_id         UUID NOT NULL REFERENCES profiles(id),  -- المُنشئ (قد يختلف عن المندوب)
  branch_id             UUID REFERENCES branches(id),
  
  -- الحالة
  status                sales_order_status NOT NULL DEFAULT 'draft',
  order_date            DATE NOT NULL DEFAULT CURRENT_DATE,
  expected_delivery     DATE,
  
  -- التسليم
  delivery_method       delivery_method NOT NULL DEFAULT 'direct',
  warehouse_id          UUID REFERENCES warehouses(id),          -- المخزن المُسلِّم
  shipping_company_id   UUID REFERENCES shipping_companies(id),
  tracking_number       TEXT,
  shipping_cost         NUMERIC(14,2) DEFAULT 0,
  shipping_on_customer  BOOLEAN DEFAULT false,
  delivery_address_id   UUID REFERENCES customer_branches(id),   -- فرع العميل
  
  -- الدفع (يُحدد عند التسليم)
  payment_terms         TEXT CHECK (payment_terms IN ('cash', 'credit', 'mixed')),
  payment_method        payment_method,
  vault_id              UUID REFERENCES vaults(id),
  custody_id            UUID REFERENCES custody_accounts(id),
  cash_amount           NUMERIC(14,2) DEFAULT 0,
  credit_amount         NUMERIC(14,2) DEFAULT 0,
  
  -- الإجماليات
  subtotal              NUMERIC(14,2) NOT NULL DEFAULT 0,
  discount_amount       NUMERIC(14,2) NOT NULL DEFAULT 0,
  tax_amount            NUMERIC(14,2) NOT NULL DEFAULT 0,
  total_amount          NUMERIC(14,2) NOT NULL DEFAULT 0,
  paid_amount           NUMERIC(14,2) NOT NULL DEFAULT 0,       -- المسدد فعلياً
  returned_amount       NUMERIC(14,2) NOT NULL DEFAULT 0,       -- إجمالي المرتجعات المعتمدة
  
  -- فحص الائتمان
  credit_check_passed   BOOLEAN,
  credit_override       BOOLEAN DEFAULT false,
  credit_override_by    UUID REFERENCES profiles(id),
  
  -- التدقيق
  confirmed_by          UUID REFERENCES profiles(id),
  confirmed_at          TIMESTAMPTZ,
  delivered_by          UUID REFERENCES profiles(id),
  delivered_at          TIMESTAMPTZ,
  cancelled_by          UUID REFERENCES profiles(id),
  cancelled_at          TIMESTAMPTZ,
  cancel_reason         TEXT,
  
  due_date              DATE,                                   -- تاريخ الاستحقاق (يُحسب تلقائياً عند التسليم)
  notes                 TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_sales_orders_updated_at ON sales_orders;
CREATE TRIGGER trg_sales_orders_updated_at
  BEFORE UPDATE ON sales_orders
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ────────────────────────────────────────────────────────────
-- 2.2 جدول بنود أمر البيع
-- ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS sales_order_items (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id              UUID NOT NULL REFERENCES sales_orders(id) ON DELETE CASCADE,
  product_id            UUID NOT NULL REFERENCES products(id),
  unit_id               UUID NOT NULL REFERENCES units(id),
  conversion_factor     NUMERIC(12,4) NOT NULL DEFAULT 1,
  
  quantity              NUMERIC(12,2) NOT NULL CHECK (quantity > 0),      -- بوحدة البيع
  base_quantity         NUMERIC(12,2) NOT NULL CHECK (base_quantity > 0), -- بالأساسية
  delivered_quantity    NUMERIC(12,2) NOT NULL DEFAULT 0,                 -- المسلَّم (بالأساسية)
  returned_quantity     NUMERIC(12,2) NOT NULL DEFAULT 0,                 -- المرتجع (بالأساسية)
  
  unit_price            NUMERIC(14,4) NOT NULL,                           -- مُثبَّت لحظة الإضافة
  discount_percent      NUMERIC(5,2)  NOT NULL DEFAULT 0 CHECK (discount_percent >= 0 AND discount_percent <= 100),
  discount_amount       NUMERIC(14,2) NOT NULL DEFAULT 0,
  tax_rate              NUMERIC(5,2)  NOT NULL DEFAULT 0,
  tax_amount            NUMERIC(14,2) NOT NULL DEFAULT 0,
  line_total            NUMERIC(14,2) NOT NULL DEFAULT 0,                 -- بعد الخصم والضريبة
  
  unit_cost_at_sale     NUMERIC(14,4) DEFAULT 0,                          -- WAC لحظة التسليم
  
  UNIQUE (order_id, product_id)
);

-- ────────────────────────────────────────────────────────────
-- 2.2a [DEFENSIVE] Trigger: فرض اتساق حسابات البند
--   discount_amount = ROUND(quantity × unit_price × discount_percent / 100, 2)
--   line_total      = (quantity × unit_price) - discount_amount + tax_amount
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION validate_sales_item_amounts()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
  v_expected_discount NUMERIC;
  v_expected_tax      NUMERIC;
  v_expected_line     NUMERIC;
BEGIN
  -- حساب الخصم الصحيح
  v_expected_discount := ROUND(
    (NEW.quantity * NEW.unit_price) * (NEW.discount_percent / 100), 2
  );

  -- تصحيح تلقائي (تفادي مشاكل الأعشار — فرق <=٠.٠١ مقبول)
  IF ABS(NEW.discount_amount - v_expected_discount) > 0.01 THEN
    NEW.discount_amount := v_expected_discount;
  END IF;

  -- حساب الضريبة إجبارياً من tax_rate
  v_expected_tax := ROUND(
    ((NEW.quantity * NEW.unit_price) - NEW.discount_amount) * (NEW.tax_rate / 100), 2
  );
  IF ABS(COALESCE(NEW.tax_amount, 0) - v_expected_tax) > 0.01 THEN
    NEW.tax_amount := v_expected_tax;
  END IF;

  -- حساب إجمالي السطر
  v_expected_line := (NEW.quantity * NEW.unit_price)
                     - NEW.discount_amount
                     + NEW.tax_amount;

  IF ABS(NEW.line_total - v_expected_line) > 0.01 THEN
    NEW.line_total := ROUND(v_expected_line, 2);
  END IF;

  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_validate_sales_item ON sales_order_items;
CREATE TRIGGER trg_validate_sales_item
  BEFORE INSERT OR UPDATE ON sales_order_items
  FOR EACH ROW EXECUTE FUNCTION validate_sales_item_amounts();



-- ────────────────────────────────────────────────────────────
-- 2.3 جدول مرتجعات المبيعات
-- ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS sales_returns (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  return_number         TEXT UNIQUE NOT NULL,
  order_id              UUID NOT NULL REFERENCES sales_orders(id),  -- إلزامي
  customer_id           UUID NOT NULL REFERENCES customers(id),
  warehouse_id          UUID REFERENCES warehouses(id),
  
  status                sales_return_status NOT NULL DEFAULT 'draft',
  return_date           DATE NOT NULL DEFAULT CURRENT_DATE,
  
  total_amount          NUMERIC(14,2) NOT NULL DEFAULT 0,
  reason                TEXT,
  notes                 TEXT,
  
  confirmed_by          UUID REFERENCES profiles(id),
  confirmed_at          TIMESTAMPTZ,
  cancelled_by          UUID REFERENCES profiles(id),
  cancelled_at          TIMESTAMPTZ,
  
  created_by            UUID NOT NULL REFERENCES profiles(id),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_sales_returns_updated_at ON sales_returns;
CREATE TRIGGER trg_sales_returns_updated_at
  BEFORE UPDATE ON sales_returns
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ────────────────────────────────────────────────────────────
-- 2.4 جدول بنود مرتجع المبيعات
-- ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS sales_return_items (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  return_id             UUID NOT NULL REFERENCES sales_returns(id) ON DELETE CASCADE,
  order_item_id         UUID NOT NULL REFERENCES sales_order_items(id),  -- ربط ببند الفاتورة
  product_id            UUID NOT NULL REFERENCES products(id),
  unit_id               UUID NOT NULL REFERENCES units(id),
  conversion_factor     NUMERIC(12,4) NOT NULL DEFAULT 1,
  
  quantity              NUMERIC(12,2) NOT NULL CHECK (quantity > 0),
  base_quantity         NUMERIC(12,2) NOT NULL CHECK (base_quantity > 0),
  unit_price            NUMERIC(14,4) NOT NULL,     -- من الفاتورة الأصلية
  line_total            NUMERIC(14,2) NOT NULL DEFAULT 0,
  unit_cost_at_sale     NUMERIC(14,4) DEFAULT 0,    -- تكلفة الوحدة لحظة البيع الأصلي
  
  UNIQUE (return_id, order_item_id)
);


-- ╔══════════════════════════════════════════════════════════════╗
-- ║  المرحلة ٢ب: الأمان والفهارس                                ║
-- ╚══════════════════════════════════════════════════════════════╝


-- ────────────────────────────────────────────────────────────
-- 2.5 أمان الصفوف (RLS)
-- ────────────────────────────────────────────────────────────

ALTER TABLE sales_orders       ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_order_items  ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_returns      ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_return_items ENABLE ROW LEVEL SECURITY;

-- أوامر البيع: يرى طلباته أو الكل بصلاحية
DROP POLICY IF EXISTS "so_read" ON sales_orders;
CREATE POLICY "so_read" ON sales_orders FOR SELECT USING (
  rep_id = auth.uid()
  OR created_by_id = auth.uid()
  OR check_permission(auth.uid(), 'sales.orders.read_all')
);

DROP POLICY IF EXISTS "so_insert" ON sales_orders;
CREATE POLICY "so_insert" ON sales_orders FOR INSERT WITH CHECK (
  check_permission(auth.uid(), 'sales.orders.create')
);

DROP POLICY IF EXISTS "so_update" ON sales_orders;
CREATE POLICY "so_update" ON sales_orders FOR UPDATE USING (
  (status = 'draft' AND (rep_id = auth.uid() OR created_by_id = auth.uid()))
  OR check_permission(auth.uid(), 'sales.orders.read_all')
);

-- بنود أوامر البيع: تتبع أمان الأمر نفسه
DROP POLICY IF EXISTS "soi_read" ON sales_order_items;
CREATE POLICY "soi_read" ON sales_order_items FOR SELECT USING (
  EXISTS (SELECT 1 FROM sales_orders so WHERE so.id = order_id
    AND (so.rep_id = auth.uid() OR so.created_by_id = auth.uid()
         OR check_permission(auth.uid(), 'sales.orders.read_all')))
);

DROP POLICY IF EXISTS "soi_write" ON sales_order_items;
CREATE POLICY "soi_write" ON sales_order_items FOR ALL USING (
  EXISTS (SELECT 1 FROM sales_orders so WHERE so.id = order_id
    AND (so.status = 'draft' AND (so.rep_id = auth.uid() OR so.created_by_id = auth.uid()))
    OR check_permission(auth.uid(), 'sales.orders.read_all'))
);

-- مرتجعات المبيعات
DROP POLICY IF EXISTS "sr_read" ON sales_returns;
CREATE POLICY "sr_read" ON sales_returns FOR SELECT USING (
  created_by = auth.uid()
  OR check_permission(auth.uid(), 'sales.returns.read')
);

DROP POLICY IF EXISTS "sr_insert" ON sales_returns;
CREATE POLICY "sr_insert" ON sales_returns FOR INSERT WITH CHECK (
  check_permission(auth.uid(), 'sales.returns.create')
);

DROP POLICY IF EXISTS "sr_update" ON sales_returns;
CREATE POLICY "sr_update" ON sales_returns FOR UPDATE USING (
  (status = 'draft' AND created_by = auth.uid())
  OR check_permission(auth.uid(), 'sales.returns.confirm')
);

-- بنود المرتجعات
DROP POLICY IF EXISTS "sri_read" ON sales_return_items;
CREATE POLICY "sri_read" ON sales_return_items FOR SELECT USING (
  EXISTS (SELECT 1 FROM sales_returns sr WHERE sr.id = return_id
    AND (sr.created_by = auth.uid() OR check_permission(auth.uid(), 'sales.returns.read')))
);

DROP POLICY IF EXISTS "sri_write" ON sales_return_items;
CREATE POLICY "sri_write" ON sales_return_items FOR ALL USING (
  EXISTS (SELECT 1 FROM sales_returns sr WHERE sr.id = return_id
    AND sr.status = 'draft'
    AND (sr.created_by = auth.uid() OR check_permission(auth.uid(), 'sales.returns.confirm')))
);


-- ────────────────────────────────────────────────────────────
-- 2.6 الفهارس
-- ────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_so_customer     ON sales_orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_so_rep          ON sales_orders(rep_id);
CREATE INDEX IF NOT EXISTS idx_so_status       ON sales_orders(status);
CREATE INDEX IF NOT EXISTS idx_so_date         ON sales_orders(order_date DESC);
CREATE INDEX IF NOT EXISTS idx_so_branch       ON sales_orders(branch_id);
CREATE INDEX IF NOT EXISTS idx_so_warehouse    ON sales_orders(warehouse_id);
CREATE INDEX IF NOT EXISTS idx_soi_order       ON sales_order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_soi_product     ON sales_order_items(product_id);
CREATE INDEX IF NOT EXISTS idx_sr_order        ON sales_returns(order_id);
CREATE INDEX IF NOT EXISTS idx_sr_customer     ON sales_returns(customer_id);
CREATE INDEX IF NOT EXISTS idx_sr_status       ON sales_returns(status);
CREATE INDEX IF NOT EXISTS idx_sri_return      ON sales_return_items(return_id);
CREATE INDEX IF NOT EXISTS idx_sri_order_item  ON sales_return_items(order_item_id);


-- ╔══════════════════════════════════════════════════════════════╗
-- ║  المرحلة ٣: الدوال الذرية                                   ║
-- ╚══════════════════════════════════════════════════════════════╝

-- ملاحظة: الدوال المساعدة التالية موجودة فعلاً:
--   get_base_quantity(product, unit, qty) → NUMERIC
--   get_product_price(product, customer, unit, qty) → NUMERIC
--   reserve_stock(warehouse, product, qty) → VOID
--   unreserve_stock(warehouse, product, qty) → VOID
--   deduct_stock_at_wac(warehouse, product, qty, move_type, ref_type, ref_id, user) → NUMERIC (COGS)
--   update_stock_wac(warehouse, product, qty, cost, move_type, ref_type, ref_id, user) → VOID
--   check_credit_available(customer, amount) → BOOLEAN
--   add_vault_transaction(vault, type, amount, ref_type, ref_id, desc, user) → UUID
--   add_custody_transaction(custody, type, amount, vault, ref_type, ref_id, desc, user) → UUID
--   create_manual_journal_entry(desc, date, source_type, source_id, lines, user) → UUID


-- ────────────────────────────────────────────────────────────
-- 3.1 دالة ترقيم أمر البيع
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION generate_sales_order_number()
RETURNS TEXT
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
BEGIN
  RETURN 'SO-' || to_char(CURRENT_DATE, 'YYYYMMDD') || '-' ||
         lpad(nextval('sales_order_seq')::text, 4, '0');
END; $$;


-- ────────────────────────────────────────────────────────────
-- 3.2 دالة ترقيم مرتجع المبيعات
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION generate_sales_return_number()
RETURNS TEXT
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
BEGIN
  RETURN 'SR-' || to_char(CURRENT_DATE, 'YYYYMMDD') || '-' ||
         lpad(nextval('sales_return_seq')::text, 4, '0');
END; $$;


-- ────────────────────────────────────────────────────────────
-- 3.3 ترقيم تلقائي عبر Triggers
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION trg_auto_sales_order_number()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.order_number IS NULL OR NEW.order_number = '' THEN
    NEW.order_number := generate_sales_order_number();
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_so_auto_number ON sales_orders;
CREATE TRIGGER trg_so_auto_number
  BEFORE INSERT ON sales_orders
  FOR EACH ROW EXECUTE FUNCTION trg_auto_sales_order_number();

CREATE OR REPLACE FUNCTION trg_auto_sales_return_number()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.return_number IS NULL OR NEW.return_number = '' THEN
    NEW.return_number := generate_sales_return_number();
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_sr_auto_number ON sales_returns;
CREATE TRIGGER trg_sr_auto_number
  BEFORE INSERT ON sales_returns
  FOR EACH ROW EXECUTE FUNCTION trg_auto_sales_return_number();


-- ════════════════════════════════════════════════════════════
-- نهاية المرحلة ١ و ٢ — الجداول والاعتماديات جاهزة
-- ════════════════════════════════════════════════════════════


-- ────────────────────────────────────────────────────────────
-- 3.4 دالة تأكيد أمر البيع
--   المدخلات: معرف الطلب + معرف المستخدم
--   المنطق:
--     ١. فحص الصلاحية
--     ٢. قفل الطلب + فحص الحالة (يجب أن يكون draft)
--     ٣. فحص وجود المخزن
--     ٤. لكل بند: حجز المخزون (تستخدم reserve_stock الذرية)
--     ٥. تحديث الحالة → confirmed
--   الحماية:
--     - إذا كان الطلب مؤكد بالفعل → لا شيء (تكرار آمن)
--     - قفل الصف يمنع السباقات المتزامنة
--     - reserve_stock تتحقق من الكمية المتاحة بعد قفل صف المخزون
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION confirm_sales_order(
  p_order_id UUID,
  p_user_id  UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_order          sales_orders%ROWTYPE;
  v_item           RECORD;
  v_computed_total NUMERIC;
  v_computed_sub   NUMERIC;
  v_computed_disc  NUMERIC;
  v_computed_tax   NUMERIC;
  v_max_discount   NUMERIC;
  v_has_override   BOOLEAN := false;
BEGIN
  -- [SECURITY GUARD] التحقق من هوية المستخدم
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- [PERMISSION] فحص صلاحية تأكيد الطلب
  IF NOT check_permission(p_user_id, 'sales.orders.confirm') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية تأكيد طلبات البيع';
  END IF;

  -- ١. قفل الطلب
  SELECT * INTO v_order
  FROM sales_orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'أمر البيع غير موجود';
  END IF;

  -- ٢. فحص الحالة — تكرار آمن (idempotent)
  IF v_order.status = 'confirmed' THEN
    RETURN; -- مؤكد بالفعل — لا شيء يحدث
  END IF;

  IF v_order.status != 'draft' THEN
    RAISE EXCEPTION 'لا يمكن تأكيد طلب في حالة: %', v_order.status;
  END IF;

  -- ٣. فحص وجود المخزن
  IF v_order.warehouse_id IS NULL THEN
    RAISE EXCEPTION 'يجب تحديد المخزن قبل تأكيد الطلب';
  END IF;

  -- ٣أ. [DEFENSIVE] إعادة حساب الإجماليات من البنود (لا نثق بأرقام الواجهة)
  SELECT
    COALESCE(SUM(quantity * unit_price), 0),
    COALESCE(SUM(discount_amount), 0),
    COALESCE(SUM(tax_amount), 0),
    COALESCE(SUM(line_total), 0)
  INTO v_computed_sub, v_computed_disc, v_computed_tax, v_computed_total
  FROM sales_order_items WHERE order_id = p_order_id;

  IF v_computed_total = 0 THEN
    RAISE EXCEPTION 'لا يمكن تأكيد طلب بدون بنود';
  END IF;

  -- [FIX] إضافة تكلفة الشحن على العميل إن وُجدت
  IF v_order.shipping_on_customer = true AND COALESCE(v_order.shipping_cost, 0) > 0 THEN
    v_computed_total := v_computed_total + v_order.shipping_cost;
  END IF;

  -- تصحيح الرأسية إذا كانت غير متطابقة
  IF v_computed_total != v_order.total_amount
     OR v_computed_sub != v_order.subtotal
     OR v_computed_disc != v_order.discount_amount
     OR v_computed_tax != v_order.tax_amount THEN
    UPDATE sales_orders
    SET subtotal        = v_computed_sub,
        discount_amount = v_computed_disc,
        tax_amount      = v_computed_tax,
        total_amount    = v_computed_total
    WHERE id = p_order_id;
    v_order.total_amount := v_computed_total;
  END IF;

  -- ٣ب. [DEFENSIVE] فحص حدود الخصم
  SELECT COALESCE(value::numeric, 100) INTO v_max_discount
  FROM company_settings WHERE key = 'sales.max_discount_percent';
  v_max_discount := COALESCE(v_max_discount, 100);

  IF v_max_discount < 100 THEN
    -- فحص: هل يملك صلاحية التجاوز؟
    v_has_override := check_permission(p_user_id, 'sales.discounts.override');

    FOR v_item IN
      SELECT product_id, discount_percent
      FROM sales_order_items
      WHERE order_id = p_order_id AND discount_percent > v_max_discount
    LOOP
      IF NOT v_has_override THEN
        RAISE EXCEPTION 'خصم % يتجاوز الحد المسموح (%). يلزم صلاحية تجاوز حد الخصم',
          v_item.discount_percent, v_max_discount;
      END IF;
    END LOOP;
  END IF;

  -- ٤. لكل بند: حجز المخزون
  FOR v_item IN
    SELECT * FROM sales_order_items WHERE order_id = p_order_id
    ORDER BY product_id ASC  -- [DEADLOCK FIX] ترتيب ثابت لمنع الاختناق
  LOOP
    -- reserve_stock تقوم بـ: FOR UPDATE + فحص الكمية المتاحة + زيادة reserved_quantity
    -- إذا الكمية غير كافية تُلقي استثناء يُوقف كل شيء (ذري)
    PERFORM reserve_stock(
      v_order.warehouse_id,
      v_item.product_id,
      v_item.base_quantity
    );
  END LOOP;

  -- ٥. تحديث الحالة
  UPDATE sales_orders
  SET status       = 'confirmed',
      confirmed_by = p_user_id,
      confirmed_at = now()
  WHERE id = p_order_id;
END; $$;


-- ────────────────────────────────────────────────────────────
-- 3.5 دالة تسليم أمر البيع (كامل)
--   المدخلات: معرف الطلب + المستخدم + بيانات الدفع
--   المنطق:
--     ١. فحص الصلاحية + قفل الطلب + فحص الحالة
--     ٢. فحص الائتمان (للدفع الآجل/المقسط)
--     ٣. لكل بند: إلغاء حجز + خصم مخزون + تسجيل تكلفة البضاعة
--     ٤. المعالجة المالية حسب طريقة الدفع
--     ٥. تسجيل في دفتر العميل (للآجل)
--     ٦. القيد المحاسبي
--     ٧. تحديث الحالة
--   الحماية:
--     - ذري بالكامل (كل شيء أو لا شيء)
--     - قفل الصف يمنع التسليم المزدوج
--     - check_credit_available تفحص الحد + فترة السماح
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION deliver_sales_order(
  p_order_id       UUID,
  p_user_id        UUID,
  p_payment_terms  TEXT,          -- 'cash' | 'credit' | 'mixed'
  p_payment_method TEXT DEFAULT NULL,  -- 'cash' | 'bank_transfer' | 'instapay' etc.
  p_vault_id       UUID DEFAULT NULL,
  p_custody_id     UUID DEFAULT NULL,
  p_cash_amount    NUMERIC DEFAULT 0,
  p_override_credit BOOLEAN DEFAULT false
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_order         sales_orders%ROWTYPE;
  v_item          RECORD;
  v_total_cogs    NUMERIC := 0;
  v_item_cogs     NUMERIC;
  v_credit_amount NUMERIC;
  v_credit_ok     BOOLEAN;
  v_journal_lines JSONB := '[]'::JSONB;
BEGIN
  -- [SECURITY GUARD]
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- [PERMISSION]
  IF NOT check_permission(p_user_id, 'sales.orders.deliver') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية تسليم طلبات البيع';
  END IF;

  -- ١. قفل الطلب
  SELECT * INTO v_order
  FROM sales_orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'أمر البيع غير موجود';
  END IF;

  -- تكرار آمن
  IF v_order.status = 'delivered' OR v_order.status = 'completed' THEN
    RETURN;
  END IF;

  IF v_order.status != 'confirmed' THEN
    RAISE EXCEPTION 'لا يمكن تسليم طلب في حالة: % — يجب أن يكون مؤكداً', v_order.status;
  END IF;

  -- ٢. حساب المبلغ الآجل + فحص الائتمان
  v_credit_amount := v_order.total_amount - p_cash_amount;

  IF p_payment_terms = 'cash' THEN
    v_credit_amount := 0;
    p_cash_amount := v_order.total_amount;
  ELSIF p_payment_terms = 'credit' THEN
    v_credit_amount := v_order.total_amount;
    p_cash_amount := 0;
  END IF;
  -- 'mixed' → يستخدم القيم المُرسلة

  -- [GAP FIX] فحص: مجموع النقدي + الآجل يجب أن يساوي الإجمالي
  IF (p_cash_amount + v_credit_amount) != v_order.total_amount THEN
    RAISE EXCEPTION 'المبلغ النقدي (%) + الآجل (%) لا يساوي إجمالي الفاتورة (%)',
      p_cash_amount, v_credit_amount, v_order.total_amount;
  END IF;

  -- فحص الائتمان إذا هناك مبلغ آجل
  IF v_credit_amount > 0 THEN
    -- فحص: هل العميل مسموح له بالآجل؟
    DECLARE
      v_customer_terms TEXT;
    BEGIN
      SELECT payment_terms INTO v_customer_terms
      FROM customers WHERE id = v_order.customer_id;

      IF v_customer_terms = 'cash' THEN
        RAISE EXCEPTION 'هذا العميل مسموح له بالدفع النقدي فقط';
      END IF;
    END;

    -- فحص الحد الائتماني
    v_credit_ok := check_credit_available(v_order.customer_id, v_credit_amount);

    IF NOT v_credit_ok THEN
      IF p_override_credit AND check_permission(p_user_id, 'sales.orders.override_credit') THEN
        -- تخطي مسموح بصلاحية
        NULL;
      ELSE
        RAISE EXCEPTION 'تجاوز حد الائتمان — المبلغ الآجل: % — يرجى تقليل المبلغ أو الحصول على موافقة', v_credit_amount;
      END IF;
    END IF;
  END IF;

  -- ٣. لكل بند: إلغاء حجز + خصم مخزون + تسجيل التكلفة
  FOR v_item IN
    SELECT * FROM sales_order_items WHERE order_id = p_order_id
    ORDER BY product_id ASC  -- [DEADLOCK FIX]
  LOOP
    -- إلغاء الحجز (تم عند التأكيد)
    PERFORM unreserve_stock(
      v_order.warehouse_id,
      v_item.product_id,
      v_item.base_quantity
    );

    -- خصم فعلي + حساب تكلفة البضاعة المباعة
    v_item_cogs := deduct_stock_at_wac(
      v_order.warehouse_id,
      v_item.product_id,
      v_item.base_quantity,
      'out',               -- نوع الحركة (يتوافق مع CHECK على stock_movements.type)
      'sales_order',       -- نوع المرجع
      p_order_id,          -- معرف المرجع
      p_user_id
    );

    v_total_cogs := v_total_cogs + v_item_cogs;

    -- تسجيل تكلفة الوحدة في البند (للمرتجعات لاحقاً)
    UPDATE sales_order_items
    SET delivered_quantity = base_quantity,
        unit_cost_at_sale = CASE
          WHEN base_quantity > 0 THEN v_item_cogs / base_quantity
          ELSE 0
        END
    WHERE id = v_item.id;
  END LOOP;

  -- ٤. المعالجة المالية
  -- ٤أ. النقدي → عهدة أو خزينة
  IF p_cash_amount > 0 THEN
    -- [GAP FIX] يجب تحديد وجهة التحصيل النقدي
    IF p_custody_id IS NULL AND p_vault_id IS NULL THEN
      RAISE EXCEPTION 'يجب تحديد العهدة أو الخزينة لاستقبال المبلغ النقدي';
    END IF;

    IF p_custody_id IS NOT NULL THEN
      PERFORM add_custody_transaction(
        p_custody_id, 'collection', p_cash_amount,
        p_vault_id,                    -- الخزينة المرجعية (اختياري)
        'sales_order', p_order_id,
        'تحصيل فاتورة بيع #' || v_order.order_number,
        p_user_id
      );
    ELSE
      PERFORM add_vault_transaction(
        p_vault_id, 'collection', p_cash_amount,
        'sales_order', p_order_id,
        'تحصيل فاتورة بيع #' || v_order.order_number,
        p_user_id
      );
    END IF;
  END IF;

  -- ٤ب. الآجل → دفتر العميل (مدين)
  IF v_credit_amount > 0 THEN
    INSERT INTO customer_ledger (
      customer_id, type, amount,
      source_type, source_id,
      description, created_by
    ) VALUES (
      v_order.customer_id, 'debit', v_credit_amount,
      'sales_order', p_order_id,
      'فاتورة بيع #' || v_order.order_number,
      p_user_id
    );
  END IF;

  -- ٥. القيد المحاسبي
  --   مدين: العملاء (المبلغ الآجل) + النقدية (المبلغ النقدي)
  --   دائن: الإيرادات (إجمالي البيع) — مبسّط
  --   مدين: تكلفة البضاعة المباعة
  --   دائن: المخزون (تكلفة البضاعة)
  v_journal_lines := '[]'::JSONB;

  -- سطر الإيرادات (دائن) — بالصافي (بعد الخصم، بدون الضريبة)
  v_journal_lines := v_journal_lines || jsonb_build_object(
    'account_code', '4100', 'debit', 0,
    'credit', v_order.total_amount - COALESCE(v_order.tax_amount, 0),
    'description', 'إيراد بيع #' || v_order.order_number
  );

  -- سطر الضريبة (دائن) — التزام ضريبي
  IF COALESCE(v_order.tax_amount, 0) > 0 THEN
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', '2200', 'debit', 0,
      'credit', v_order.tax_amount,
      'description', 'ضريبة قيمة مضافة — بيع #' || v_order.order_number
    );
  END IF;

  -- سطر العملاء — الآجل (مدين)
  IF v_credit_amount > 0 THEN
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', '1200', 'debit', v_credit_amount, 'credit', 0,
      'description', 'ذمم عملاء — بيع آجل #' || v_order.order_number
    );
  END IF;

  -- سطر النقدية (مدين) — توجيه ديناميكي للحساب الصحيح
  IF p_cash_amount > 0 THEN
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', CASE
        WHEN p_custody_id IS NOT NULL THEN '1400'
        ELSE (
          SELECT CASE type
            WHEN 'cash'          THEN '1110'
            WHEN 'bank'          THEN '1120'
            WHEN 'mobile_wallet' THEN '1130'
            ELSE '1110'
          END FROM vaults WHERE id = p_vault_id
        )
      END,
      'debit', p_cash_amount, 'credit', 0,
      'description', 'تحصيل نقدي — بيع #' || v_order.order_number
    );
  END IF;

  -- سطر تكلفة البضاعة المباعة (مدين)
  IF v_total_cogs > 0 THEN
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', '5100', 'debit', v_total_cogs, 'credit', 0,
      'description', 'تكلفة بضاعة مباعة #' || v_order.order_number
    );

    -- سطر المخزون (دائن)
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', '1300', 'debit', 0, 'credit', v_total_cogs,
      'description', 'خصم مخزون — بيع #' || v_order.order_number
    );
  END IF;

  PERFORM create_manual_journal_entry(
    'قيد بيع — فاتورة #' || v_order.order_number,
    CURRENT_DATE,
    'sales_order',
    p_order_id,
    v_journal_lines,
    p_user_id
  );

  -- ٦. تحديث الطلب
  UPDATE sales_orders
  SET status           = 'delivered',
      payment_terms    = p_payment_terms,
      payment_method   = CASE
        WHEN p_payment_method IS NOT NULL THEN p_payment_method::payment_method
        ELSE NULL
      END,
      vault_id         = p_vault_id,
      custody_id       = p_custody_id,
      cash_amount      = COALESCE(cash_amount, 0) + p_cash_amount,
      credit_amount    = v_credit_amount,
      paid_amount      = COALESCE(paid_amount, 0) + p_cash_amount,
      credit_check_passed = v_credit_ok,
      credit_override  = p_override_credit,
      credit_override_by = CASE WHEN p_override_credit THEN p_user_id ELSE NULL END,
      delivered_by     = p_user_id,
      delivered_at     = now(),
      due_date         = CASE
        WHEN p_payment_terms = 'cash' THEN NULL
        ELSE CURRENT_DATE + COALESCE(
          (SELECT credit_days FROM customers WHERE id = v_order.customer_id), 0
        )
      END
  WHERE id = p_order_id;

  -- ٧. التحقق من اكتمال الفاتورة بناءً على التراكمي
  IF (COALESCE(v_order.paid_amount, 0) + p_cash_amount + COALESCE(v_order.returned_amount, 0)) >= v_order.total_amount THEN
    UPDATE sales_orders
    SET status = 'completed'
    WHERE id = p_order_id;
  END IF;
END; $$;


-- ────────────────────────────────────────────────────────────
-- 3.6 دالة إلغاء أمر البيع
--   المنطق:
--     ١. فحص الصلاحية + قفل + فحص الحالة
--     ٢. إذا مؤكد: إلغاء حجز المخزون لكل بند
--     ٣. تحديث الحالة + تسجيل السبب
--   الحماية: لا يمكن إلغاء طلب مُسلَّم أو مكتمل (مرتجع فقط)
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION cancel_sales_order(
  p_order_id UUID,
  p_user_id  UUID,
  p_reason   TEXT DEFAULT NULL
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_order sales_orders%ROWTYPE;
  v_item  RECORD;
BEGIN
  -- [SECURITY GUARD]
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  IF NOT check_permission(p_user_id, 'sales.orders.cancel') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية إلغاء طلبات البيع';
  END IF;

  SELECT * INTO v_order
  FROM sales_orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'أمر البيع غير موجود';
  END IF;

  -- تكرار آمن
  IF v_order.status = 'cancelled' THEN RETURN; END IF;

  -- لا يمكن إلغاء بعد التسليم
  IF v_order.status IN ('delivered', 'partially_delivered', 'completed') THEN
    RAISE EXCEPTION 'لا يمكن إلغاء طلب تم تسليمه — استخدم المرتجعات بدلاً من ذلك';
  END IF;

  -- إلغاء حجز المخزون (إذا كان مؤكداً = محجوز)
  IF v_order.status = 'confirmed' THEN
    FOR v_item IN
      SELECT * FROM sales_order_items WHERE order_id = p_order_id
      ORDER BY product_id ASC  -- [DEADLOCK FIX]
    LOOP
      PERFORM unreserve_stock(
        v_order.warehouse_id,
        v_item.product_id,
        v_item.base_quantity
      );
    END LOOP;
  END IF;

  UPDATE sales_orders
  SET status       = 'cancelled',
      cancelled_by = p_user_id,
      cancelled_at = now(),
      cancel_reason = p_reason
  WHERE id = p_order_id;
END; $$;


-- ────────────────────────────────────────────────────────────
-- 3.7 دالة تأكيد مرتجع المبيعات
--   المنطق:
--     ١. فحص الصلاحية + قفل + فحص الحالة
--     ٢. فحص: هل الطلب الأصلي مُسلَّم/مكتمل؟
--     ٣. لكل بند: فحص الكمية (لا تتجاوز المتبقي بعد المرتجعات السابقة)
--     ٤. إعادة المخزون (update_stock_wac بتكلفة البيع الأصلي)
--     ٥. التسوية المالية:
--        - آجل → خصم من مديونية العميل (credit في الدفتر)
--        - نقدي → رد من العهدة/الخزينة (فحص الرصيد أولاً)
--     ٦. القيد المحاسبي (عكس قيد البيع)
--     ٧. تحديث الكميات المرتجعة في بنود الفاتورة
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION confirm_sales_return(
  p_return_id   UUID,
  p_user_id     UUID,
  p_custody_id  UUID DEFAULT NULL,
  p_vault_id    UUID DEFAULT NULL
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_return        sales_returns%ROWTYPE;
  v_order         sales_orders%ROWTYPE;
  v_item          RECORD;
  v_available_qty NUMERIC;
  v_total_cost    NUMERIC := 0;
  v_item_cost     NUMERIC;
  v_journal_lines JSONB := '[]'::JSONB;
BEGIN
  -- [SECURITY GUARD]
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  IF NOT check_permission(p_user_id, 'sales.returns.confirm') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية تأكيد المرتجعات';
  END IF;

  -- ١. قفل المرتجع
  SELECT * INTO v_return
  FROM sales_returns WHERE id = p_return_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'المرتجع غير موجود';
  END IF;

  IF v_return.status = 'confirmed' THEN RETURN; END IF;

  IF v_return.status != 'draft' THEN
    RAISE EXCEPTION 'لا يمكن تأكيد مرتجع في حالة: %', v_return.status;
  END IF;

  -- ٢. فحص الطلب الأصلي
  SELECT * INTO v_order
  FROM sales_orders WHERE id = v_return.order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'الطلب الأصلي غير موجود';
  END IF;

  IF v_order.status NOT IN ('delivered', 'completed') THEN
    RAISE EXCEPTION 'لا يمكن عمل مرتجع لطلب لم يُسلَّم بعد (حالة الطلب: %)', v_order.status;
  END IF;

  -- ٣. فحص الكميات + إعادة المخزون
  FOR v_item IN
    SELECT sri.*, soi.base_quantity AS orig_base_qty,
           soi.delivered_quantity AS orig_delivered,
           soi.returned_quantity AS orig_returned,
           soi.unit_cost_at_sale AS orig_unit_cost
    FROM sales_return_items sri
    JOIN sales_order_items soi ON soi.id = sri.order_item_id
    WHERE sri.return_id = p_return_id
    ORDER BY sri.product_id ASC  -- [DEADLOCK FIX]
  LOOP
    -- الكمية المتاحة للمرتجع = المسلَّم - المرتجع سابقاً
    v_available_qty := v_item.orig_delivered - v_item.orig_returned;

    IF v_item.base_quantity > v_available_qty THEN
      RAISE EXCEPTION 'كمية المرتجع (%) تتجاوز المتاح (%) للمنتج',
        v_item.base_quantity, v_available_qty;
    END IF;

    -- تكلفة هذا البند (بتكلفة البيع الأصلي — ليس WAC الحالي)
    v_item_cost := v_item.base_quantity * COALESCE(v_item.orig_unit_cost, 0);
    v_total_cost := v_total_cost + v_item_cost;

    -- تسجيل تكلفة الوحدة في بند المرتجع
    UPDATE sales_return_items
    SET unit_cost_at_sale = v_item.orig_unit_cost
    WHERE id = v_item.id;

    -- إعادة المخزون (بالتكلفة الأصلية)
    PERFORM update_stock_wac(
      COALESCE(v_return.warehouse_id, v_order.warehouse_id),
      v_item.product_id,
      v_item.base_quantity,
      COALESCE(v_item.orig_unit_cost, 0),
      'return_in',          -- يتوافق مع CHECK على stock_movements.type
      'sales_return',
      p_return_id,
      p_user_id
    );

    -- تحديث الكمية المرتجعة في بند الفاتورة الأصلي
    UPDATE sales_order_items
    SET returned_quantity = returned_quantity + v_item.base_quantity
    WHERE id = v_item.order_item_id;
  END LOOP;

  -- ٤. التسوية المالية — نحسب الإجمالي من البنود لا من الرأسية
  -- [GAP FIX] استخدام المبلغ المحسوب من البنود بدلاً من v_return.total_amount
  DECLARE
    v_computed_total NUMERIC;
  BEGIN
    SELECT COALESCE(SUM(sri.line_total), 0) INTO v_computed_total
    FROM sales_return_items sri WHERE sri.return_id = p_return_id;

    -- تحديث الرأسية بالمبلغ المحسوب (إذا اختلف)
    IF v_computed_total != v_return.total_amount THEN
      UPDATE sales_returns SET total_amount = v_computed_total
      WHERE id = p_return_id;
      v_return.total_amount := v_computed_total;
    END IF;
  END;

  IF v_order.payment_terms = 'credit' OR v_order.credit_amount > 0 THEN
    -- مرتجع آجل → خصم من مديونية العميل
    INSERT INTO customer_ledger (
      customer_id, type, amount,
      source_type, source_id,
      description, created_by
    ) VALUES (
      v_return.customer_id, 'credit', v_return.total_amount,
      'sales_return', p_return_id,
      'مرتجع بيع #' || v_return.return_number || ' — أصل الفاتورة #' || v_order.order_number,
      p_user_id
    );
  ELSE
    -- مرتجع نقدي → رد من العهدة أو الخزينة
    IF p_custody_id IS NOT NULL THEN
      -- add_custody_transaction ستفحص الرصيد وتُلقي استثناء إذا غير كافٍ
      PERFORM add_custody_transaction(
        p_custody_id, 'expense', v_return.total_amount,
        p_vault_id,
        'sales_return', p_return_id,
        'رد مرتجع بيع #' || v_return.return_number,
        p_user_id
      );
    ELSIF p_vault_id IS NOT NULL THEN
      -- add_vault_transaction ستفحص الرصيد
      PERFORM add_vault_transaction(
        p_vault_id, 'withdrawal', v_return.total_amount,
        'sales_return', p_return_id,
        'رد مرتجع بيع #' || v_return.return_number,
        p_user_id
      );
    ELSE
      RAISE EXCEPTION 'يجب تحديد مصدر الرد (عهدة أو خزينة) للمرتجع النقدي';
    END IF;
  END IF;

  -- ٥. القيد المحاسبي (عكس قيد البيع)
  v_journal_lines := '[]'::JSONB;

  -- حساب نسبة الضريبة من الفاتورة الأصلية (نسبياً)
  DECLARE
    v_return_tax_amount NUMERIC := 0;
    v_return_net        NUMERIC := 0;
  BEGIN
    IF COALESCE(v_order.tax_amount, 0) > 0 AND COALESCE(v_order.subtotal, 0) > 0 THEN
      v_return_tax_amount := ROUND(
        v_return.total_amount * (v_order.tax_amount / v_order.subtotal), 2
      );
    END IF;
    v_return_net := v_return.total_amount - v_return_tax_amount;

    -- مرتجعات المبيعات (مدين — حساب مستقل 4200)
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', '4200', 'debit', v_return_net, 'credit', 0,
      'description', 'مرتجع بيع #' || v_return.return_number
    );

    -- عكس الضريبة (مدين 2200)
    IF v_return_tax_amount > 0 THEN
      v_journal_lines := v_journal_lines || jsonb_build_object(
        'account_code', '2200', 'debit', v_return_tax_amount, 'credit', 0,
        'description', 'عكس ضريبة — مرتجع #' || v_return.return_number
      );
    END IF;
  END;

  -- النقدية أو العملاء (دائن)
  IF v_order.payment_terms = 'credit' OR v_order.credit_amount > 0 THEN
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', '1200', 'debit', 0, 'credit', v_return.total_amount,
      'description', 'تخفيض ذمم عملاء — مرتجع #' || v_return.return_number
    );
  ELSE
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', CASE
        WHEN p_custody_id IS NOT NULL THEN '1400'
        ELSE COALESCE((
          SELECT CASE type
            WHEN 'cash'          THEN '1110'
            WHEN 'bank'          THEN '1120'
            WHEN 'mobile_wallet' THEN '1130'
            ELSE '1110'
          END FROM vaults WHERE id = p_vault_id
        ), '1110')
      END,
      'debit', 0, 'credit', v_return.total_amount,
      'description', 'رد نقدي — مرتجع #' || v_return.return_number
    );
  END IF;

  -- عكس تكلفة البضاعة
  IF v_total_cost > 0 THEN
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', '1300', 'debit', v_total_cost, 'credit', 0,
      'description', 'إعادة مخزون — مرتجع #' || v_return.return_number
    );
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', '5100', 'debit', 0, 'credit', v_total_cost,
      'description', 'تخفيض تكلفة — مرتجع #' || v_return.return_number
    );
  END IF;

  PERFORM create_manual_journal_entry(
    'قيد مرتجع بيع #' || v_return.return_number,
    CURRENT_DATE,
    'sales_return',
    p_return_id,
    v_journal_lines,
    p_user_id
  );

  -- ٦. تحديث المرتجع
  UPDATE sales_returns
  SET status       = 'confirmed',
      confirmed_by = p_user_id,
      confirmed_at = now()
  WHERE id = p_return_id;

  -- ٧. تحديث returned_amount في الفاتورة الأصلية (لا تمس paid_amount أبداً)
  UPDATE sales_orders
  SET returned_amount = COALESCE(returned_amount, 0) + v_return.total_amount,
      -- تحديث حالة الطلب إذا تمت تغطيته بالمدفوع + المرتجع
      status = CASE
        WHEN (paid_amount + COALESCE(returned_amount, 0) + v_return.total_amount) >= total_amount
        THEN 'completed'::sales_order_status
        ELSE status
      END
  WHERE id = v_return.order_id;
END; $$;


-- ────────────────────────────────────────────────────────────
-- 3.8 دالة التوزيع الذكي للتحصيل
--   المنطق: توزيع مبلغ تحصيل على ذمم العميل بالأقدم أولاً
--     ١. البدء بالرصيد الافتتاحي (opening_balance) إن وُجد
--     ٢. ثم الفواتير المستحقة بالترتيب الزمني
--     ٣. تسجيل credit في دفتر العميل لكل فاتورة
--     ٤. تحديث paid_amount في كل فاتورة
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION allocate_payment_to_invoices(
  p_customer_id UUID,
  p_amount      NUMERIC,
  p_source_type TEXT,    -- 'payment_receipt' أو 'collection'
  p_source_id   UUID,
  p_user_id     UUID
) RETURNS JSONB    -- يرجع تفاصيل التوزيع
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_remaining   NUMERIC := p_amount;
  v_allocated   JSONB := '[]'::JSONB;
  v_entry       RECORD;
  v_alloc_amount NUMERIC;
  v_entry_balance NUMERIC;
BEGIN
  -- [SECURITY GUARD]
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
  END IF;

  -- [IDEMPOTENCY FIX] منع تكرار التخصيص لنفس الإيصال
  IF EXISTS (
    SELECT 1 FROM customer_ledger
    WHERE source_type = p_source_type
      AND source_id = p_source_id
      AND type = 'credit'
      AND allocated_to IS NOT NULL
  ) THEN
    RETURN '[]'::JSONB;  -- تم توزيعه سابقاً — تكرار آمن
  END IF;

  -- التوزيع على المستحقات بالترتيب الزمني (الأقدم أولاً)
  -- نبحث عن حركات مدينة لم تُسدد بالكامل
  FOR v_entry IN
    SELECT
      cl.id,
      cl.source_type,
      cl.source_id,
      cl.amount AS debit_amount,
      cl.created_at,
      COALESCE(
        cl.amount - (
          SELECT COALESCE(SUM(cl2.amount), 0)
          FROM customer_ledger cl2
          WHERE cl2.customer_id = p_customer_id
            AND cl2.type = 'credit'
            AND cl2.allocated_to = cl.id
        ), cl.amount
      ) AS outstanding
    FROM customer_ledger cl
    WHERE cl.customer_id = p_customer_id
      AND cl.type = 'debit'
    ORDER BY cl.created_at ASC, cl.id ASC
    FOR UPDATE OF cl
  LOOP
    EXIT WHEN v_remaining <= 0;

    v_entry_balance := v_entry.outstanding;
    IF v_entry_balance <= 0 THEN CONTINUE; END IF;

    -- المبلغ المخصص لهذه الحركة
    v_alloc_amount := LEAST(v_remaining, v_entry_balance);

    -- تسجيل credit مرتبط
    INSERT INTO customer_ledger (
      customer_id, type, amount,
      source_type, source_id,
      allocated_to,
      description, created_by
    ) VALUES (
      p_customer_id, 'credit', v_alloc_amount,
      p_source_type, p_source_id,
      v_entry.id,
      'تسديد — ' || v_entry.source_type || ' #' || v_entry.source_id::text,
      p_user_id
    );

    -- تحديث paid_amount في الفاتورة (إن كانت sales_order)
    IF v_entry.source_type = 'sales_order' THEN
      UPDATE sales_orders
      SET paid_amount = paid_amount + v_alloc_amount,
          status = CASE
            WHEN (paid_amount + v_alloc_amount + COALESCE(returned_amount, 0)) >= total_amount
            THEN 'completed'::sales_order_status
            ELSE status
          END
      WHERE id = v_entry.source_id;
    END IF;

    v_remaining := v_remaining - v_alloc_amount;

    -- تسجيل في مصفوفة التوزيع
    v_allocated := v_allocated || jsonb_build_object(
      'ledger_entry_id', v_entry.id,
      'source_type', v_entry.source_type,
      'source_id', v_entry.source_id,
      'allocated', v_alloc_amount,
      'remaining_after', v_entry_balance - v_alloc_amount
    );
  END LOOP;

  -- إذا تبقى مبلغ → تسجيله كـ credit عام (دفعة مقدمة)
  IF v_remaining > 0 THEN
    INSERT INTO customer_ledger (
      customer_id, type, amount,
      source_type, source_id,
      description, created_by
    ) VALUES (
      p_customer_id, 'credit', v_remaining,
      p_source_type, p_source_id,
      'دفعة مقدمة / رصيد زائد',
      p_user_id
    );

    v_allocated := v_allocated || jsonb_build_object(
      'ledger_entry_id', NULL,
      'source_type', 'advance_payment',
      'source_id', NULL,
      'allocated', v_remaining,
      'remaining_after', 0
    );
  END IF;

  RETURN v_allocated;
END; $$;


-- ────────────────────────────────────────────────────────────
-- صلاحيات التنفيذ
-- ────────────────────────────────────────────────────────────

GRANT EXECUTE ON FUNCTION generate_sales_order_number()  TO authenticated;
GRANT EXECUTE ON FUNCTION generate_sales_return_number() TO authenticated;
GRANT EXECUTE ON FUNCTION confirm_sales_order(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION deliver_sales_order(UUID, UUID, TEXT, TEXT, UUID, UUID, NUMERIC, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION cancel_sales_order(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION confirm_sales_return(UUID, UUID, UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION allocate_payment_to_invoices(UUID, NUMERIC, TEXT, UUID, UUID) TO authenticated;
