-- ============================================================
-- Migration 02: Master Data — بيانات الأساس
-- ============================================================
-- الجداول: جغرافيا، فروع، تصنيفات، منتجات، وحدات، أسعار،
--          عملاء، موردين، مخازن، مخزون
-- الدوال: تحويل وحدات، تسعير، WAC
-- ============================================================

-- ============================================================
-- 1. GEOGRAPHY — الجغرافيا
-- ============================================================

CREATE TABLE IF NOT EXISTS governorates (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  name_en    TEXT,
  code       TEXT UNIQUE NOT NULL,        -- 01-27
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS cities (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  governorate_id  UUID NOT NULL REFERENCES governorates(id),
  name            TEXT NOT NULL,
  name_en         TEXT,
  sort_order      INT DEFAULT 0,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS areas (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  city_id    UUID NOT NULL REFERENCES cities(id),
  name       TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- 2. BRANCHES — الفروع
-- ============================================================

CREATE TABLE IF NOT EXISTS branches (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  type       TEXT NOT NULL DEFAULT 'distribution'
             CHECK (type IN ('distribution', 'retail', 'warehouse')),
  city_id    UUID REFERENCES cities(id),
  address    TEXT,
  phone      TEXT,
  manager_id UUID REFERENCES profiles(id),
  is_active  BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- 3. PRODUCTS — المنتجات
-- ============================================================

CREATE TABLE IF NOT EXISTS product_categories (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  parent_id  UUID REFERENCES product_categories(id),
  icon       TEXT,
  sort_order INT DEFAULT 0,
  is_active  BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
-- حماية من الحلقات الدائرية: parent_id لا يساوي id
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_category_no_self_ref'
  ) THEN
    ALTER TABLE product_categories
      ADD CONSTRAINT chk_category_no_self_ref CHECK (parent_id IS DISTINCT FROM id);
  END IF;
END; $$;

CREATE TABLE IF NOT EXISTS brands (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  logo_url   TEXT,
  is_active  BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS units (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL UNIQUE,
  symbol     TEXT NOT NULL,
  is_base    BOOLEAN DEFAULT false,   -- وحدة أساسية عامة
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS products (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sku             TEXT UNIQUE NOT NULL,
  name            TEXT NOT NULL,
  barcode         TEXT,
  category_id     UUID REFERENCES product_categories(id),
  brand_id        UUID REFERENCES brands(id),
  base_unit_id    UUID NOT NULL REFERENCES units(id),
  selling_price   NUMERIC(12,2) NOT NULL DEFAULT 0,
  cost_price      NUMERIC(12,2) NOT NULL DEFAULT 0,
  tax_rate        NUMERIC(5,2) DEFAULT 0,        -- نسبة الضريبة %
  description     TEXT,
  image_url       TEXT,
  is_active       BOOLEAN DEFAULT true,
  min_stock_level NUMERIC(12,2) DEFAULT 0,       -- بالوحدة الأساسية
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS product_units (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id        UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  unit_id           UUID NOT NULL REFERENCES units(id),
  conversion_factor NUMERIC(12,4) NOT NULL CHECK (conversion_factor > 0),
  selling_price     NUMERIC(12,2),    -- NULL = يُحسب من السعر الأساسي × conversion
  is_purchase_unit  BOOLEAN DEFAULT false,
  is_sales_unit     BOOLEAN DEFAULT true,
  created_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE (product_id, unit_id)        -- لا تكرار وحدة لنفس المنتج
);

CREATE TABLE IF NOT EXISTS product_bundles (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  sku        TEXT UNIQUE,
  price      NUMERIC(12,2) NOT NULL DEFAULT 0,
  is_active  BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS product_bundle_items (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bundle_id  UUID NOT NULL REFERENCES product_bundles(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id),
  unit_id    UUID NOT NULL REFERENCES units(id),
  quantity   NUMERIC(12,2) NOT NULL CHECK (quantity > 0),
  UNIQUE (bundle_id, product_id)
);

-- ============================================================
-- 4. PRICE LISTS — قوائم الأسعار
-- ============================================================

CREATE TABLE IF NOT EXISTS price_lists (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  description TEXT,
  is_default  BOOLEAN DEFAULT false,
  is_active   BOOLEAN DEFAULT true,
  valid_from  DATE,
  valid_to    DATE,
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now()
);
-- قائمة افتراضية واحدة فقط
CREATE UNIQUE INDEX IF NOT EXISTS idx_price_lists_single_default
  ON price_lists (is_default) WHERE is_default = true;

CREATE TABLE IF NOT EXISTS price_list_items (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  price_list_id  UUID NOT NULL REFERENCES price_lists(id) ON DELETE CASCADE,
  product_id     UUID NOT NULL REFERENCES products(id),
  unit_id        UUID NOT NULL REFERENCES units(id),
  price          NUMERIC(12,2) NOT NULL CHECK (price >= 0),
  min_qty        NUMERIC(12,2) DEFAULT 1,
  max_qty        NUMERIC(12,2),
  created_at     TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS price_list_assignments (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  price_list_id  UUID NOT NULL REFERENCES price_lists(id) ON DELETE CASCADE,
  entity_type    TEXT NOT NULL CHECK (entity_type IN ('customer', 'city', 'governorate')),
  entity_id      UUID NOT NULL,
  created_at     TIMESTAMPTZ DEFAULT now(),
  UNIQUE (price_list_id, entity_type, entity_id)
);

-- ============================================================
-- 5. CUSTOMERS — العملاء
-- ============================================================

-- تسلسل أكواد العملاء
CREATE SEQUENCE IF NOT EXISTS customer_code_seq START WITH 1;

CREATE TABLE IF NOT EXISTS customers (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code                 TEXT UNIQUE,    -- Trigger يملأه تلقائياً
  name                 TEXT NOT NULL,
  type                 TEXT NOT NULL DEFAULT 'retail'
                       CHECK (type IN ('retail', 'wholesale', 'distributor')),
  governorate_id       UUID REFERENCES governorates(id),
  city_id              UUID REFERENCES cities(id),
  area_id              UUID REFERENCES areas(id),
  address              TEXT,
  phone                TEXT,
  mobile               TEXT,
  email                TEXT,
  tax_number           TEXT,
  payment_terms        TEXT NOT NULL DEFAULT 'cash'
                       CHECK (payment_terms IN ('cash', 'credit', 'mixed')),
  credit_limit         NUMERIC(14,2) DEFAULT 0,
  credit_days          INT DEFAULT 0,
  price_list_id        UUID REFERENCES price_lists(id),
  assigned_rep_id      UUID REFERENCES profiles(id),
  latitude             NUMERIC(10,7),
  longitude            NUMERIC(10,7),
  location_accuracy    NUMERIC(8,2),
  location_updated_at  TIMESTAMPTZ,
  location_updated_by  UUID REFERENCES profiles(id),
  is_active            BOOLEAN DEFAULT true,
  notes                TEXT,
  created_by           UUID REFERENCES profiles(id),
  created_at           TIMESTAMPTZ DEFAULT now(),
  updated_at           TIMESTAMPTZ DEFAULT now()
);

-- Trigger: توليد كود العميل تلقائياً
CREATE OR REPLACE FUNCTION generate_customer_code()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.code IS NULL OR NEW.code = '' THEN
    NEW.code := 'CUS-' || lpad(nextval('customer_code_seq')::text, 5, '0');
  END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE TRIGGER trg_customer_auto_code
  BEFORE INSERT ON customers
  FOR EACH ROW EXECUTE FUNCTION generate_customer_code();

CREATE TABLE IF NOT EXISTS customer_branches (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id  UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  address      TEXT,
  phone        TEXT,
  contact_name TEXT,
  latitude     NUMERIC(10,7),
  longitude    NUMERIC(10,7),
  is_primary   BOOLEAN DEFAULT false,
  created_at   TIMESTAMPTZ DEFAULT now(),
  updated_at   TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS customer_contacts (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id  UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  role         TEXT,
  phone        TEXT,
  email        TEXT,
  is_primary   BOOLEAN DEFAULT false,
  created_at   TIMESTAMPTZ DEFAULT now()
);

-- سجل تغييرات حد الائتمان
CREATE TABLE IF NOT EXISTS customer_credit_history (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id  UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  limit_before NUMERIC(14,2) NOT NULL,
  limit_after  NUMERIC(14,2) NOT NULL,
  changed_by   UUID NOT NULL REFERENCES profiles(id),
  reason       TEXT,
  created_at   TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- 6. SUPPLIERS — الموردين
-- ============================================================

CREATE SEQUENCE IF NOT EXISTS supplier_code_seq START WITH 1;

CREATE TABLE IF NOT EXISTS suppliers (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code           TEXT UNIQUE,    -- Trigger يملأه تلقائياً
  name           TEXT NOT NULL,
  type           TEXT,
  governorate_id UUID REFERENCES governorates(id),
  city_id        UUID REFERENCES cities(id),
  phone          TEXT,
  email          TEXT,
  tax_number     TEXT,
  payment_terms  TEXT DEFAULT 'cash',
  credit_limit   NUMERIC(14,2) DEFAULT 0,
  credit_days    INT DEFAULT 0,
  bank_account   TEXT,
  is_active      BOOLEAN DEFAULT true,
  created_at     TIMESTAMPTZ DEFAULT now(),
  updated_at     TIMESTAMPTZ DEFAULT now()
);

-- Trigger: توليد كود المورد تلقائياً
CREATE OR REPLACE FUNCTION generate_supplier_code()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.code IS NULL OR NEW.code = '' THEN
    NEW.code := 'SUP-' || lpad(nextval('supplier_code_seq')::text, 5, '0');
  END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE TRIGGER trg_supplier_auto_code
  BEFORE INSERT ON suppliers
  FOR EACH ROW EXECUTE FUNCTION generate_supplier_code();

CREATE TABLE IF NOT EXISTS supplier_contacts (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id UUID NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  role        TEXT,
  phone       TEXT,
  email       TEXT,
  created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS supplier_payment_reminders (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id       UUID NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
  due_date          DATE NOT NULL,
  amount            NUMERIC(14,2) NOT NULL,
  invoice_ref       TEXT,
  status            TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'paid', 'overdue')),
  notify_before_days INT DEFAULT 3,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- 7. WAREHOUSES & STOCK — المخازن والمخزون
-- ============================================================

CREATE TABLE IF NOT EXISTS warehouses (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  type       TEXT NOT NULL DEFAULT 'fixed'
             CHECK (type IN ('fixed', 'vehicle', 'retail')),
  branch_id  UUID REFERENCES branches(id),
  address    TEXT,
  manager_id UUID REFERENCES profiles(id),
  is_active  BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS warehouse_managers (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  warehouse_id         UUID NOT NULL REFERENCES warehouses(id) ON DELETE CASCADE,
  profile_id           UUID NOT NULL REFERENCES profiles(id),
  is_primary           BOOLEAN DEFAULT false,
  can_approve_receipts BOOLEAN DEFAULT false,
  created_at           TIMESTAMPTZ DEFAULT now(),
  UNIQUE (warehouse_id, profile_id)
);

CREATE TABLE IF NOT EXISTS stock (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  warehouse_id       UUID NOT NULL REFERENCES warehouses(id),
  product_id         UUID NOT NULL REFERENCES products(id),
  quantity           NUMERIC(14,4) NOT NULL DEFAULT 0,
  reserved_quantity  NUMERIC(14,4) NOT NULL DEFAULT 0,
  available_quantity NUMERIC(14,4) GENERATED ALWAYS AS (quantity - reserved_quantity) STORED,
  wac                NUMERIC(14,4) NOT NULL DEFAULT 0,   -- Weighted Average Cost
  total_cost_value   NUMERIC(16,4) NOT NULL DEFAULT 0,
  created_at         TIMESTAMPTZ DEFAULT now(),
  updated_at         TIMESTAMPTZ DEFAULT now(),
  UNIQUE (warehouse_id, product_id)
);

CREATE TABLE IF NOT EXISTS stock_batches (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  stock_id     UUID NOT NULL REFERENCES stock(id) ON DELETE CASCADE,
  batch_number TEXT NOT NULL,
  expiry_date  DATE,
  quantity     NUMERIC(14,4) NOT NULL DEFAULT 0,
  cost_price   NUMERIC(14,4) NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS stock_movements (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  warehouse_id    UUID NOT NULL REFERENCES warehouses(id),
  product_id      UUID NOT NULL REFERENCES products(id),
  unit_id         UUID REFERENCES units(id),
  quantity        NUMERIC(14,4) NOT NULL,
  type            TEXT NOT NULL CHECK (type IN (
                    'in', 'out',
                    'transfer_in', 'transfer_out',
                    'adjustment_add', 'adjustment_remove',
                    'return_in', 'return_out'
                  )),
  unit_cost       NUMERIC(14,4),
  wac_before      NUMERIC(14,4),
  wac_after       NUMERIC(14,4),
  before_qty      NUMERIC(14,4),
  after_qty       NUMERIC(14,4),
  reference_type  TEXT,         -- 'purchase_order', 'sales_order', 'transfer', etc.
  reference_id    UUID,
  notes           TEXT,
  created_by      UUID REFERENCES profiles(id),
  created_at      TIMESTAMPTZ DEFAULT now()
  -- لا updated_at — هذا جدول INSERT-ONLY
);

-- ============================================================
-- 7.1 STOCK TRANSFERS — تحويلات المخزون
-- ============================================================

CREATE SEQUENCE IF NOT EXISTS transfer_number_seq START WITH 1;

CREATE TABLE IF NOT EXISTS stock_transfers (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  number            TEXT UNIQUE,    -- Trigger يملأه تلقائياً
  from_warehouse_id UUID NOT NULL REFERENCES warehouses(id),
  to_warehouse_id   UUID NOT NULL REFERENCES warehouses(id),
  status            TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'approved', 'in_transit', 'received', 'cancelled')),
  requested_by      UUID NOT NULL REFERENCES profiles(id),
  approved_by       UUID REFERENCES profiles(id),
  received_by       UUID REFERENCES profiles(id),
  notes             TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT chk_transfer_diff_warehouse CHECK (from_warehouse_id != to_warehouse_id)
);

-- Trigger: توليد رقم التحويل تلقائياً
CREATE OR REPLACE FUNCTION generate_transfer_number()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.number IS NULL OR NEW.number = '' THEN
    NEW.number := 'TRN-' || lpad(nextval('transfer_number_seq')::text, 6, '0');
  END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE TRIGGER trg_transfer_auto_number
  BEFORE INSERT ON stock_transfers
  FOR EACH ROW EXECUTE FUNCTION generate_transfer_number();

CREATE TABLE IF NOT EXISTS stock_transfer_items (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transfer_id       UUID NOT NULL REFERENCES stock_transfers(id) ON DELETE CASCADE,
  product_id        UUID NOT NULL REFERENCES products(id),
  unit_id           UUID NOT NULL REFERENCES units(id),
  quantity          NUMERIC(14,4) NOT NULL CHECK (quantity > 0),
  received_quantity NUMERIC(14,4) DEFAULT 0,
  unit_cost         NUMERIC(14,4) DEFAULT 0,
  UNIQUE (transfer_id, product_id)
);

-- ============================================================
-- 7.2 STOCK ADJUSTMENTS — تسويات المخزون (جرد)
-- ============================================================

CREATE SEQUENCE IF NOT EXISTS adjustment_number_seq START WITH 1;

CREATE TABLE IF NOT EXISTS stock_adjustments (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  number       TEXT UNIQUE,    -- Trigger يملأه تلقائياً
  warehouse_id UUID NOT NULL REFERENCES warehouses(id),
  type         TEXT NOT NULL DEFAULT 'count'
               CHECK (type IN ('add', 'remove', 'count')),
  status       TEXT NOT NULL DEFAULT 'draft'
               CHECK (status IN ('draft', 'pending', 'approved', 'rejected')),
  reason       TEXT,
  approved_by  UUID REFERENCES profiles(id),
  created_by   UUID NOT NULL REFERENCES profiles(id),
  created_at   TIMESTAMPTZ DEFAULT now(),
  updated_at   TIMESTAMPTZ DEFAULT now()
);

-- Trigger: توليد رقم التسوية تلقائياً
CREATE OR REPLACE FUNCTION generate_adjustment_number()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.number IS NULL OR NEW.number = '' THEN
    NEW.number := 'ADJ-' || lpad(nextval('adjustment_number_seq')::text, 6, '0');
  END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE TRIGGER trg_adjustment_auto_number
  BEFORE INSERT ON stock_adjustments
  FOR EACH ROW EXECUTE FUNCTION generate_adjustment_number();

CREATE TABLE IF NOT EXISTS stock_adjustment_items (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  adjustment_id  UUID NOT NULL REFERENCES stock_adjustments(id) ON DELETE CASCADE,
  product_id     UUID NOT NULL REFERENCES products(id),
  system_qty     NUMERIC(14,4) NOT NULL DEFAULT 0,
  actual_qty     NUMERIC(14,4) NOT NULL DEFAULT 0,
  difference     NUMERIC(14,4) GENERATED ALWAYS AS (actual_qty - system_qty) STORED,
  unit_cost      NUMERIC(14,4) DEFAULT 0,
  notes          TEXT,
  UNIQUE (adjustment_id, product_id)
);

-- ============================================================
-- 8. FUNCTIONS — الدوال
-- ============================================================

-- 8.1 تحويل وحدة → وحدة أساسية
CREATE OR REPLACE FUNCTION get_base_quantity(
  p_product_id UUID, p_unit_id UUID, p_quantity NUMERIC
) RETURNS NUMERIC
  LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE v_factor NUMERIC; v_base_unit UUID;
BEGIN
  SELECT base_unit_id INTO v_base_unit FROM products WHERE id = p_product_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'المنتج غير موجود'; END IF;

  -- إذا كانت نفس الوحدة الأساسية
  IF v_base_unit = p_unit_id THEN RETURN p_quantity; END IF;

  SELECT conversion_factor INTO v_factor
  FROM product_units
  WHERE product_id = p_product_id AND unit_id = p_unit_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'الوحدة غير مرتبطة بهذا المنتج';
  END IF;

  RETURN p_quantity * v_factor;
END; $$;

-- 8.2 جلب السعر بالأولوية
CREATE OR REPLACE FUNCTION get_product_price(
  p_product_id UUID, p_customer_id UUID, p_unit_id UUID, p_qty NUMERIC DEFAULT 1
) RETURNS NUMERIC
  LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_price NUMERIC;
  v_base_price NUMERIC;
  v_base_unit UUID;
  v_customer RECORD;
BEGIN
  -- 1. جلب بيانات العميل
  SELECT governorate_id, city_id, price_list_id
  INTO v_customer
  FROM customers WHERE id = p_customer_id;

  -- 2. قائمة أسعار العميل المخصصة (مع التحقق من النشاط والصلاحية)
  IF v_customer.price_list_id IS NOT NULL THEN
    SELECT pli.price INTO v_price
    FROM price_list_items pli
    JOIN price_lists pl ON pl.id = pli.price_list_id
    WHERE pli.price_list_id = v_customer.price_list_id
      AND pli.product_id = p_product_id AND pli.unit_id = p_unit_id
      AND pl.is_active = true
      AND (pl.valid_from IS NULL OR pl.valid_from <= CURRENT_DATE)
      AND (pl.valid_to IS NULL OR pl.valid_to >= CURRENT_DATE)
      AND p_qty >= COALESCE(pli.min_qty, 0)
      AND (pli.max_qty IS NULL OR p_qty <= pli.max_qty)
    ORDER BY pli.min_qty DESC NULLS LAST LIMIT 1;
    IF v_price IS NOT NULL THEN RETURN v_price; END IF;
  END IF;

  -- 3. قائمة أسعار المدينة
  IF v_customer.city_id IS NOT NULL THEN
    SELECT pli.price INTO v_price
    FROM price_list_items pli
    JOIN price_list_assignments pla ON pla.price_list_id = pli.price_list_id
    JOIN price_lists pl ON pl.id = pli.price_list_id
    WHERE pla.entity_type = 'city' AND pla.entity_id = v_customer.city_id
      AND pli.product_id = p_product_id AND pli.unit_id = p_unit_id
      AND pl.is_active = true
      AND (pl.valid_from IS NULL OR pl.valid_from <= CURRENT_DATE)
      AND (pl.valid_to IS NULL OR pl.valid_to >= CURRENT_DATE)
      AND p_qty >= COALESCE(pli.min_qty, 0)
      AND (pli.max_qty IS NULL OR p_qty <= pli.max_qty)
    ORDER BY pli.min_qty DESC NULLS LAST LIMIT 1;
    IF v_price IS NOT NULL THEN RETURN v_price; END IF;
  END IF;

  -- 4. قائمة أسعار المحافظة
  IF v_customer.governorate_id IS NOT NULL THEN
    SELECT pli.price INTO v_price
    FROM price_list_items pli
    JOIN price_list_assignments pla ON pla.price_list_id = pli.price_list_id
    JOIN price_lists pl ON pl.id = pli.price_list_id
    WHERE pla.entity_type = 'governorate' AND pla.entity_id = v_customer.governorate_id
      AND pli.product_id = p_product_id AND pli.unit_id = p_unit_id
      AND pl.is_active = true
      AND (pl.valid_from IS NULL OR pl.valid_from <= CURRENT_DATE)
      AND (pl.valid_to IS NULL OR pl.valid_to >= CURRENT_DATE)
      AND p_qty >= COALESCE(pli.min_qty, 0)
      AND (pli.max_qty IS NULL OR p_qty <= pli.max_qty)
    ORDER BY pli.min_qty DESC NULLS LAST LIMIT 1;
    IF v_price IS NOT NULL THEN RETURN v_price; END IF;
  END IF;

  -- 5. قائمة الأسعار الافتراضية
  SELECT pli.price INTO v_price
  FROM price_list_items pli
  JOIN price_lists pl ON pl.id = pli.price_list_id
  WHERE pl.is_default = true AND pl.is_active = true
    AND pli.product_id = p_product_id AND pli.unit_id = p_unit_id
    AND p_qty >= COALESCE(pli.min_qty, 0)
    AND (pli.max_qty IS NULL OR p_qty <= pli.max_qty)
  ORDER BY pli.min_qty DESC NULLS LAST LIMIT 1;
  IF v_price IS NOT NULL THEN RETURN v_price; END IF;

  -- 6. السعر من المنتج مباشرة
  SELECT selling_price, base_unit_id
  INTO v_base_price, v_base_unit
  FROM products WHERE id = p_product_id;

  -- تحقق إذا الوحدة المطلوبة هي نفس الأساسية
  IF v_base_unit = p_unit_id THEN
    RETURN COALESCE(v_base_price, 0);
  END IF;

  -- سعر الوحدة المخصص أو محسوب
  SELECT COALESCE(pu.selling_price, v_base_price * pu.conversion_factor)
  INTO v_price
  FROM product_units pu
  WHERE pu.product_id = p_product_id AND pu.unit_id = p_unit_id;

  RETURN COALESCE(v_price, v_base_price, 0);
END; $$;

-- 8.3 تحديث WAC عند استلام مخزون
CREATE OR REPLACE FUNCTION update_stock_wac(
  p_warehouse_id UUID, p_product_id UUID,
  p_qty_in NUMERIC, p_unit_cost NUMERIC,
  p_movement_type TEXT, p_reference_type TEXT,
  p_reference_id UUID, p_user_id UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_stock stock%ROWTYPE;
  v_new_wac NUMERIC;
  v_new_qty NUMERIC;
  v_new_total NUMERIC;
BEGIN
  SELECT * INTO v_stock
  FROM stock
  WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO stock (warehouse_id, product_id, quantity, reserved_quantity, wac, total_cost_value)
    VALUES (p_warehouse_id, p_product_id, p_qty_in, 0, p_unit_cost, p_qty_in * p_unit_cost);
    v_new_qty := p_qty_in;
    v_new_wac := p_unit_cost;
  ELSE
    v_new_qty   := v_stock.quantity + p_qty_in;
    v_new_total := v_stock.total_cost_value + (p_qty_in * p_unit_cost);
    v_new_wac   := CASE WHEN v_new_qty > 0 THEN v_new_total / v_new_qty ELSE 0 END;

    UPDATE stock
    SET quantity = v_new_qty, wac = v_new_wac, total_cost_value = v_new_total,
        updated_at = now()
    WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id;
  END IF;

  INSERT INTO stock_movements (
    warehouse_id, product_id, unit_id, quantity, type,
    unit_cost, wac_before, wac_after, before_qty, after_qty,
    reference_type, reference_id, created_by
  ) VALUES (
    p_warehouse_id, p_product_id,
    (SELECT base_unit_id FROM products WHERE id = p_product_id),
    p_qty_in, p_movement_type,
    p_unit_cost, COALESCE(v_stock.wac, p_unit_cost), v_new_wac,
    COALESCE(v_stock.quantity, 0), v_new_qty,
    p_reference_type, p_reference_id, p_user_id
  );
END; $$;

-- 8.4 خصم مخزون بالـ WAC (عند البيع/التسليم)
CREATE OR REPLACE FUNCTION deduct_stock_at_wac(
  p_warehouse_id UUID, p_product_id UUID, p_qty_out NUMERIC,
  p_movement_type TEXT, p_reference_type TEXT,
  p_reference_id UUID, p_user_id UUID
) RETURNS NUMERIC
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_stock stock%ROWTYPE;
  v_cogs NUMERIC;
  v_allow_negative BOOLEAN;
BEGIN
  SELECT * INTO v_stock
  FROM stock
  WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'لا يوجد مخزون لهذا المنتج في هذا المخزن';
  END IF;

  IF v_stock.quantity < p_qty_out THEN
    SELECT COALESCE(value::boolean, false) INTO v_allow_negative
    FROM company_settings WHERE key = 'sales.allow_negative_stock';

    IF NOT COALESCE(v_allow_negative, false) THEN
      RAISE EXCEPTION 'مخزون غير كافٍ (متاح: %, مطلوب: %)', v_stock.quantity, p_qty_out;
    END IF;
  END IF;

  v_cogs := p_qty_out * v_stock.wac;

  UPDATE stock
  SET quantity = quantity - p_qty_out,
      total_cost_value = total_cost_value - v_cogs,
      updated_at = now()
  WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id;

  INSERT INTO stock_movements (
    warehouse_id, product_id, unit_id, quantity, type,
    unit_cost, wac_before, wac_after, before_qty, after_qty,
    reference_type, reference_id, created_by
  ) VALUES (
    p_warehouse_id, p_product_id,
    (SELECT base_unit_id FROM products WHERE id = p_product_id),
    p_qty_out, p_movement_type,
    v_stock.wac, v_stock.wac, v_stock.wac,
    v_stock.quantity, v_stock.quantity - p_qty_out,
    p_reference_type, p_reference_id, p_user_id
  );

  RETURN v_cogs;
END; $$;

-- ============================================================
-- 9. TRIGGERS — المحفزات
-- ============================================================

-- 9.1 updated_at تلقائي لكل الجداول
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END; $$;

-- تطبيق Trigger على كل الجداول التي تحتوي updated_at
DO $$
DECLARE
  tbl TEXT;
BEGIN
  FOR tbl IN
    SELECT unnest(ARRAY[
      'governorates', 'cities', 'areas', 'branches',
      'product_categories', 'brands', 'units', 'products',
      'product_bundles', 'price_lists',
      'customers', 'customer_branches',
      'suppliers', 'supplier_payment_reminders',
      'warehouses', 'stock',
      'stock_transfers', 'stock_adjustments'
    ])
  LOOP
    EXECUTE format(
      'CREATE OR REPLACE TRIGGER trg_%I_updated_at
       BEFORE UPDATE ON %I
       FOR EACH ROW EXECUTE FUNCTION set_updated_at()',
      tbl, tbl
    );
  END LOOP;
END; $$;

-- 9.2 تسجيل تغييرات حد الائتمان تلقائياً
CREATE OR REPLACE FUNCTION log_credit_limit_change()
RETURNS TRIGGER
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
BEGIN
  IF OLD.credit_limit IS DISTINCT FROM NEW.credit_limit THEN
    INSERT INTO customer_credit_history (
      customer_id, limit_before, limit_after, changed_by, reason
    ) VALUES (
      NEW.id, OLD.credit_limit, NEW.credit_limit, auth.uid(),
      'تحديث من واجهة إدارة العملاء'
    );
  END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE TRIGGER trg_customer_credit_log
  AFTER UPDATE ON customers
  FOR EACH ROW
  WHEN (OLD.credit_limit IS DISTINCT FROM NEW.credit_limit)
  EXECUTE FUNCTION log_credit_limit_change();

-- ============================================================
-- 10. RLS POLICIES — سياسات الأمان
-- ============================================================

-- تفعيل RLS على كل الجداول
DO $$
DECLARE tbl TEXT;
BEGIN
  FOR tbl IN
    SELECT unnest(ARRAY[
      'governorates', 'cities', 'areas', 'branches',
      'product_categories', 'brands', 'units', 'products', 'product_units',
      'product_bundles', 'product_bundle_items',
      'price_lists', 'price_list_items', 'price_list_assignments',
      'customers', 'customer_branches', 'customer_contacts', 'customer_credit_history',
      'suppliers', 'supplier_contacts', 'supplier_payment_reminders',
      'warehouses', 'warehouse_managers', 'stock', 'stock_batches', 'stock_movements',
      'stock_transfers', 'stock_transfer_items',
      'stock_adjustments', 'stock_adjustment_items'
    ])
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', tbl);
  END LOOP;
END; $$;

-- ===== جغرافيا (قراءة للجميع المصرح لهم) =====
DROP POLICY IF EXISTS "geo_read" ON governorates;
CREATE POLICY "geo_read" ON governorates FOR SELECT
  USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "cities_read" ON cities;
CREATE POLICY "cities_read" ON cities FOR SELECT
  USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "areas_read" ON areas;
CREATE POLICY "areas_read" ON areas FOR SELECT
  USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "areas_write" ON areas;
CREATE POLICY "areas_write" ON areas FOR ALL
  USING (check_permission(auth.uid(), 'branches.create'));

-- ===== فروع =====
DROP POLICY IF EXISTS "branches_read" ON branches;
CREATE POLICY "branches_read" ON branches FOR SELECT
  USING (check_permission(auth.uid(), 'branches.read'));
DROP POLICY IF EXISTS "branches_write" ON branches;
CREATE POLICY "branches_write" ON branches FOR ALL
  USING (check_permission(auth.uid(), 'branches.create'));

-- ===== منتجات (قراءة عامة لمن لديه صلاحية) =====
DROP POLICY IF EXISTS "products_read" ON products;
CREATE POLICY "products_read" ON products FOR SELECT
  USING (check_permission(auth.uid(), 'products.read'));
DROP POLICY IF EXISTS "products_write" ON products;
CREATE POLICY "products_write" ON products FOR ALL
  USING (check_permission(auth.uid(), 'products.create'));

DROP POLICY IF EXISTS "categories_read" ON product_categories;
CREATE POLICY "categories_read" ON product_categories FOR SELECT
  USING (check_permission(auth.uid(), 'products.read'));
DROP POLICY IF EXISTS "categories_write" ON product_categories;
CREATE POLICY "categories_write" ON product_categories FOR ALL
  USING (check_permission(auth.uid(), 'categories.create'));

DROP POLICY IF EXISTS "brands_read" ON brands;
CREATE POLICY "brands_read" ON brands FOR SELECT
  USING (check_permission(auth.uid(), 'products.read'));
DROP POLICY IF EXISTS "brands_write" ON brands;
CREATE POLICY "brands_write" ON brands FOR ALL
  USING (check_permission(auth.uid(), 'products.create'));

DROP POLICY IF EXISTS "units_read" ON units;
CREATE POLICY "units_read" ON units FOR SELECT
  USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "units_write" ON units;
CREATE POLICY "units_write" ON units FOR ALL
  USING (check_permission(auth.uid(), 'products.create'));

DROP POLICY IF EXISTS "product_units_read" ON product_units;
CREATE POLICY "product_units_read" ON product_units FOR SELECT
  USING (check_permission(auth.uid(), 'products.read'));
DROP POLICY IF EXISTS "product_units_write" ON product_units;
CREATE POLICY "product_units_write" ON product_units FOR ALL
  USING (check_permission(auth.uid(), 'products.create'));

DROP POLICY IF EXISTS "bundles_read" ON product_bundles;
CREATE POLICY "bundles_read" ON product_bundles FOR SELECT
  USING (check_permission(auth.uid(), 'products.read'));
DROP POLICY IF EXISTS "bundles_write" ON product_bundles;
CREATE POLICY "bundles_write" ON product_bundles FOR ALL
  USING (check_permission(auth.uid(), 'products.create'));

DROP POLICY IF EXISTS "bundle_items_read" ON product_bundle_items;
CREATE POLICY "bundle_items_read" ON product_bundle_items FOR SELECT
  USING (check_permission(auth.uid(), 'products.read'));
DROP POLICY IF EXISTS "bundle_items_write" ON product_bundle_items;
CREATE POLICY "bundle_items_write" ON product_bundle_items FOR ALL
  USING (check_permission(auth.uid(), 'products.create'));

-- ===== قوائم أسعار =====
DROP POLICY IF EXISTS "price_lists_read" ON price_lists;
CREATE POLICY "price_lists_read" ON price_lists FOR SELECT
  USING (check_permission(auth.uid(), 'price_lists.read'));
DROP POLICY IF EXISTS "price_lists_write" ON price_lists;
CREATE POLICY "price_lists_write" ON price_lists FOR ALL
  USING (check_permission(auth.uid(), 'price_lists.update'));

DROP POLICY IF EXISTS "price_list_items_read" ON price_list_items;
CREATE POLICY "price_list_items_read" ON price_list_items FOR SELECT
  USING (check_permission(auth.uid(), 'price_lists.read'));
DROP POLICY IF EXISTS "price_list_items_write" ON price_list_items;
CREATE POLICY "price_list_items_write" ON price_list_items FOR ALL
  USING (check_permission(auth.uid(), 'price_lists.update'));

DROP POLICY IF EXISTS "price_list_assignments_read" ON price_list_assignments;
CREATE POLICY "price_list_assignments_read" ON price_list_assignments FOR SELECT
  USING (check_permission(auth.uid(), 'price_lists.read'));
DROP POLICY IF EXISTS "price_list_assignments_write" ON price_list_assignments;
CREATE POLICY "price_list_assignments_write" ON price_list_assignments FOR ALL
  USING (check_permission(auth.uid(), 'price_lists.update'));

-- ===== عملاء (RLS ذكي: read = عملاءه فقط، read_all = الكل) =====
DROP POLICY IF EXISTS "customers_read" ON customers;
CREATE POLICY "customers_read" ON customers FOR SELECT
  USING (
    check_permission(auth.uid(), 'customers.read_all')
    OR (
      check_permission(auth.uid(), 'customers.read')
      AND assigned_rep_id = auth.uid()
    )
  );
DROP POLICY IF EXISTS "customers_write" ON customers;
CREATE POLICY "customers_write" ON customers FOR INSERT
  WITH CHECK (check_permission(auth.uid(), 'customers.create'));
DROP POLICY IF EXISTS "customers_update" ON customers;
CREATE POLICY "customers_update" ON customers FOR UPDATE
  USING (check_permission(auth.uid(), 'customers.update'));
DROP POLICY IF EXISTS "customers_delete" ON customers;
CREATE POLICY "customers_delete" ON customers FOR DELETE
  USING (check_permission(auth.uid(), 'customers.delete'));

DROP POLICY IF EXISTS "customer_branches_read" ON customer_branches;
CREATE POLICY "customer_branches_read" ON customer_branches FOR SELECT
  USING (
    check_permission(auth.uid(), 'customers.read_all')
    OR (
      check_permission(auth.uid(), 'customers.read')
      AND customer_id IN (SELECT id FROM customers WHERE assigned_rep_id = auth.uid())
    )
  );
DROP POLICY IF EXISTS "customer_branches_write" ON customer_branches;
CREATE POLICY "customer_branches_write" ON customer_branches FOR ALL
  USING (check_permission(auth.uid(), 'customers.update'));

DROP POLICY IF EXISTS "customer_contacts_read" ON customer_contacts;
CREATE POLICY "customer_contacts_read" ON customer_contacts FOR SELECT
  USING (
    check_permission(auth.uid(), 'customers.read_all')
    OR (
      check_permission(auth.uid(), 'customers.read')
      AND customer_id IN (SELECT id FROM customers WHERE assigned_rep_id = auth.uid())
    )
  );
DROP POLICY IF EXISTS "customer_contacts_write" ON customer_contacts;
CREATE POLICY "customer_contacts_write" ON customer_contacts FOR ALL
  USING (check_permission(auth.uid(), 'customers.update'));

DROP POLICY IF EXISTS "credit_history_read" ON customer_credit_history;
CREATE POLICY "credit_history_read" ON customer_credit_history FOR SELECT
  USING (check_permission(auth.uid(), 'customers.read'));
-- INSERT يتم فقط عبر Trigger (SECURITY DEFINER) — لا يحتاج سياسة INSERT

-- ===== موردين =====
DROP POLICY IF EXISTS "suppliers_read" ON suppliers;
CREATE POLICY "suppliers_read" ON suppliers FOR SELECT
  USING (check_permission(auth.uid(), 'suppliers.read'));
DROP POLICY IF EXISTS "suppliers_write" ON suppliers;
CREATE POLICY "suppliers_write" ON suppliers FOR INSERT
  WITH CHECK (check_permission(auth.uid(), 'suppliers.create'));
DROP POLICY IF EXISTS "suppliers_update" ON suppliers;
CREATE POLICY "suppliers_update" ON suppliers FOR UPDATE
  USING (check_permission(auth.uid(), 'suppliers.update'));
DROP POLICY IF EXISTS "suppliers_delete" ON suppliers;
CREATE POLICY "suppliers_delete" ON suppliers FOR DELETE
  USING (check_permission(auth.uid(), 'suppliers.delete'));

DROP POLICY IF EXISTS "supplier_contacts_read" ON supplier_contacts;
CREATE POLICY "supplier_contacts_read" ON supplier_contacts FOR SELECT
  USING (check_permission(auth.uid(), 'suppliers.read'));
DROP POLICY IF EXISTS "supplier_contacts_write" ON supplier_contacts;
CREATE POLICY "supplier_contacts_write" ON supplier_contacts FOR ALL
  USING (check_permission(auth.uid(), 'suppliers.update'));

DROP POLICY IF EXISTS "payment_reminders_read" ON supplier_payment_reminders;
CREATE POLICY "payment_reminders_read" ON supplier_payment_reminders FOR SELECT
  USING (check_permission(auth.uid(), 'suppliers.read'));
DROP POLICY IF EXISTS "payment_reminders_write" ON supplier_payment_reminders;
CREATE POLICY "payment_reminders_write" ON supplier_payment_reminders FOR ALL
  USING (check_permission(auth.uid(), 'suppliers.update'));

-- ===== مخازن ومخزون =====
DROP POLICY IF EXISTS "warehouses_read" ON warehouses;
CREATE POLICY "warehouses_read" ON warehouses FOR SELECT
  USING (check_permission(auth.uid(), 'inventory.read'));
DROP POLICY IF EXISTS "warehouses_write" ON warehouses;
CREATE POLICY "warehouses_write" ON warehouses FOR ALL
  USING (check_permission(auth.uid(), 'inventory.create'));

DROP POLICY IF EXISTS "wh_managers_read" ON warehouse_managers;
CREATE POLICY "wh_managers_read" ON warehouse_managers FOR SELECT
  USING (check_permission(auth.uid(), 'inventory.read'));
DROP POLICY IF EXISTS "wh_managers_write" ON warehouse_managers;
CREATE POLICY "wh_managers_write" ON warehouse_managers FOR ALL
  USING (check_permission(auth.uid(), 'inventory.create'));

DROP POLICY IF EXISTS "stock_read" ON stock;
CREATE POLICY "stock_read" ON stock FOR SELECT
  USING (check_permission(auth.uid(), 'inventory.read'));
-- stock يُعدّل فقط عبر الدوال (SECURITY DEFINER) — لا UPDATE مباشر

DROP POLICY IF EXISTS "stock_batches_read" ON stock_batches;
CREATE POLICY "stock_batches_read" ON stock_batches FOR SELECT
  USING (check_permission(auth.uid(), 'inventory.read'));

DROP POLICY IF EXISTS "stock_movements_read" ON stock_movements;
CREATE POLICY "stock_movements_read" ON stock_movements FOR SELECT
  USING (check_permission(auth.uid(), 'inventory.read'));
-- INSERT-ONLY: لا UPDATE ولا DELETE

DROP POLICY IF EXISTS "transfers_read" ON stock_transfers;
CREATE POLICY "transfers_read" ON stock_transfers FOR SELECT
  USING (check_permission(auth.uid(), 'inventory.transfers.read'));
DROP POLICY IF EXISTS "transfers_write" ON stock_transfers;
CREATE POLICY "transfers_write" ON stock_transfers FOR ALL
  USING (check_permission(auth.uid(), 'inventory.transfers.create'));

DROP POLICY IF EXISTS "transfer_items_read" ON stock_transfer_items;
CREATE POLICY "transfer_items_read" ON stock_transfer_items FOR SELECT
  USING (check_permission(auth.uid(), 'inventory.transfers.read'));
DROP POLICY IF EXISTS "transfer_items_write" ON stock_transfer_items;
CREATE POLICY "transfer_items_write" ON stock_transfer_items FOR ALL
  USING (check_permission(auth.uid(), 'inventory.transfers.create'));

DROP POLICY IF EXISTS "adjustments_read" ON stock_adjustments;
CREATE POLICY "adjustments_read" ON stock_adjustments FOR SELECT
  USING (check_permission(auth.uid(), 'inventory.adjustments.read'));
DROP POLICY IF EXISTS "adjustments_write" ON stock_adjustments;
CREATE POLICY "adjustments_write" ON stock_adjustments FOR ALL
  USING (check_permission(auth.uid(), 'inventory.adjustments.create'));

DROP POLICY IF EXISTS "adjustment_items_read" ON stock_adjustment_items;
CREATE POLICY "adjustment_items_read" ON stock_adjustment_items FOR SELECT
  USING (check_permission(auth.uid(), 'inventory.adjustments.read'));
DROP POLICY IF EXISTS "adjustment_items_write" ON stock_adjustment_items;
CREATE POLICY "adjustment_items_write" ON stock_adjustment_items FOR ALL
  USING (check_permission(auth.uid(), 'inventory.adjustments.create'));

-- ============================================================
-- 11. INDEXES — الفهارس للأداء
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_cities_gov ON cities(governorate_id);
CREATE INDEX IF NOT EXISTS idx_areas_city ON areas(city_id);
CREATE INDEX IF NOT EXISTS idx_branches_city ON branches(city_id);
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_brand ON products(brand_id);
CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);
CREATE INDEX IF NOT EXISTS idx_product_units_product ON product_units(product_id);
CREATE INDEX IF NOT EXISTS idx_price_list_items_product ON price_list_items(product_id);
CREATE INDEX IF NOT EXISTS idx_customers_rep ON customers(assigned_rep_id);
CREATE INDEX IF NOT EXISTS idx_customers_gov ON customers(governorate_id);
CREATE INDEX IF NOT EXISTS idx_customers_city ON customers(city_id);
CREATE INDEX IF NOT EXISTS idx_customers_code ON customers(code);
CREATE INDEX IF NOT EXISTS idx_suppliers_code ON suppliers(code);
CREATE INDEX IF NOT EXISTS idx_stock_warehouse ON stock(warehouse_id);
CREATE INDEX IF NOT EXISTS idx_stock_product ON stock(product_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_wh ON stock_movements(warehouse_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON stock_movements(product_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_ref ON stock_movements(reference_type, reference_id);

-- ============================================================
-- 12. SEED DATA — بيانات أولية
-- ============================================================
-- ملاحظة: بيانات المحافظات والمدن في ملف منفصل: 02_seed_egypt_geography.sql

-- 12.1 وحدات القياس الأساسية
INSERT INTO units (name, symbol, is_base) VALUES
  ('قطعة', 'قطعة', true),
  ('كرتونة', 'كرتونة', false),
  ('جركن', 'جركن', true),
  ('كيلو', 'كجم', true),
  ('لتر', 'لتر', true),
  ('دزينة', 'دزينة', false),
  ('باليت', 'باليت', false),
  ('علبة', 'علبة', true),
  ('كيس', 'كيس', true),
  ('طن', 'طن', false)
ON CONFLICT (name) DO NOTHING;

-- 12.3 قائمة أسعار افتراضية
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM price_lists WHERE is_default = true) THEN
    INSERT INTO price_lists (name, description, is_default, is_active)
    VALUES ('القائمة العامة', 'قائمة الأسعار الافتراضية للبيع', true, true);
  END IF;
END; $$;

-- ============================================================
-- 13. BALANCE COLUMNS — أرصدة العملاء والموردين
-- ============================================================

-- 13.1 إضافة أعمدة الرصيد للعملاء
ALTER TABLE customers ADD COLUMN IF NOT EXISTS opening_balance NUMERIC(14,2) DEFAULT 0;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS current_balance NUMERIC(14,2) DEFAULT 0;
COMMENT ON COLUMN customers.opening_balance IS 'الرصيد الافتتاحي عند تسجيل العميل';
COMMENT ON COLUMN customers.current_balance IS 'الرصيد الحالي (مدين = موجب، دائن = سالب)';

-- 13.2 إضافة أعمدة الرصيد للموردين
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS opening_balance NUMERIC(14,2) DEFAULT 0;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS current_balance NUMERIC(14,2) DEFAULT 0;
COMMENT ON COLUMN suppliers.opening_balance IS 'الرصيد الافتتاحي عند تسجيل المورد';
COMMENT ON COLUMN suppliers.current_balance IS 'الرصيد الحالي (دائن = موجب، مدين = سالب)';

-- 13.3 Trigger: تعيين الرصيد الحالي = الافتتاحي عند الإنشاء
CREATE OR REPLACE FUNCTION initialize_balance()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' AND (NEW.current_balance = 0 OR NEW.current_balance IS NULL) THEN
    NEW.current_balance := COALESCE(NEW.opening_balance, 0);
  END IF;
  RETURN NEW;
END; $$;

-- تطبيق على العملاء
DROP TRIGGER IF EXISTS trg_customer_init_balance ON customers;
CREATE TRIGGER trg_customer_init_balance
  BEFORE INSERT ON customers
  FOR EACH ROW EXECUTE FUNCTION initialize_balance();

-- تطبيق على الموردين
DROP TRIGGER IF EXISTS trg_supplier_init_balance ON suppliers;
CREATE TRIGGER trg_supplier_init_balance
  BEFORE INSERT ON suppliers
  FOR EACH ROW EXECUTE FUNCTION initialize_balance();
