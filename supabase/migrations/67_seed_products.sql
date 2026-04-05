-- ================================================================
-- Seed File: المنتجات والتصنيفات والبراندات
-- المصدر   : export result.xlsx + merged_products_classified_v2.csv
-- المنتجات : 137
-- التصنيفات: 7
-- البراندات: 9
-- ملاحظة   : يعتمد على وجود وحدة 'قطعة' في جدول units
-- ================================================================

BEGIN;

-- ────────────────────────────────────────
-- 1. الوحدة الأساسية (قطعة)
-- ────────────────────────────────────────
INSERT INTO units (name, symbol, is_base)
VALUES ('قطعة', 'قطعة', true)
ON CONFLICT (name) DO NOTHING;

-- ────────────────────────────────────────
-- 2. البراندات
-- ────────────────────────────────────────
INSERT INTO brands (name, is_active)
VALUES ('CRAX', true)
ON CONFLICT DO NOTHING;
INSERT INTO brands (name, is_active)
VALUES ('Crystal', true)
ON CONFLICT DO NOTHING;
INSERT INTO brands (name, is_active)
VALUES ('End User', true)
ON CONFLICT DO NOTHING;
INSERT INTO brands (name, is_active)
VALUES ('FALS', true)
ON CONFLICT DO NOTHING;
INSERT INTO brands (name, is_active)
VALUES ('Tools', true)
ON CONFLICT DO NOTHING;
INSERT INTO brands (name, is_active)
VALUES ('Turtle Wax', true)
ON CONFLICT DO NOTHING;
INSERT INTO brands (name, is_active)
VALUES ('عروض', true)
ON CONFLICT DO NOTHING;
INSERT INTO brands (name, is_active)
VALUES ('غير محدد', true)
ON CONFLICT DO NOTHING;
INSERT INTO brands (name, is_active)
VALUES ('مستلزمات', true)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────
-- 3. تصنيفات المنتجات
-- ────────────────────────────────────────
INSERT INTO product_categories (name, sort_order, is_active)
VALUES ('العناية بالإطارات', 1, true)
ON CONFLICT DO NOTHING;
INSERT INTO product_categories (name, sort_order, is_active)
VALUES ('العناية بالتابلوه', 2, true)
ON CONFLICT DO NOTHING;
INSERT INTO product_categories (name, sort_order, is_active)
VALUES ('العناية بالسطح الخارجي', 3, true)
ON CONFLICT DO NOTHING;
INSERT INTO product_categories (name, sort_order, is_active)
VALUES ('العناية بالفرش الداخلي', 4, true)
ON CONFLICT DO NOTHING;
INSERT INTO product_categories (name, sort_order, is_active)
VALUES ('العناية بالمحرك', 5, true)
ON CONFLICT DO NOTHING;
INSERT INTO product_categories (name, sort_order, is_active)
VALUES ('المستلزمات والأدوات', 6, true)
ON CONFLICT DO NOTHING;
INSERT INTO product_categories (name, sort_order, is_active)
VALUES ('عروض', 7, true)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────
-- 4. المنتجات
-- ────────────────────────────────────────
-- نستخدم subquery لجلب UUID من الاسم (بدلًا من hard-coded UUIDs)
-- هذا يجعل الملف قابلًا للتطبيق على أي بيئة (dev/staging/prod)

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00100',
  'فوطة جلد غزال صغير',
  '100',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'مستلزمات' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  45.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00102',
  'فرشة جنط فردى جديد',
  '102',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  60.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00103',
  'فرشة كاوتش كبيرة  جديد',
  '103',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'مستلزمات' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  35.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00104',
  'فرشة كاوتش صغيرة جديد',
  '104',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'مستلزمات' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  30.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00105',
  'NOVA SPONG',
  '105',
  (SELECT id FROM product_categories WHERE name = 'العناية بالتابلوه' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  6.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00106',
  'pistol 700',
  '106',
  (SELECT id FROM product_categories WHERE name = 'العناية بالمحرك' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  75.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00107',
  'فوطة 40*50 اوتو',
  '107',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  40.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00108',
  'MAX EFFECT 1 L NEW',
  '108',
  (SELECT id FROM product_categories WHERE name = 'العناية بالفرش الداخلي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  200.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00109',
  'MAX EFFECTE 4  L NEW',
  '109',
  (SELECT id FROM product_categories WHERE name = 'العناية بالفرش الداخلي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  750.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00110',
  'ULTRA SHINE TANK 125',
  '110',
  (SELECT id FROM product_categories WHERE name = 'العناية بالإطارات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  15000.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00112',
  'SHAMPOO WAX TANK 125',
  '112',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  5500.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00113',
  'MAGNATIC SHIELD 25',
  '113',
  (SELECT id FROM product_categories WHERE name = 'العناية بالمحرك' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  3000.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00114',
  'shampoo wax 25 l new',
  '114',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  1100.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00115',
  'engine gaurd limeted 25 l',
  '115',
  (SELECT id FROM product_categories WHERE name = 'العناية بالمحرك' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'CRAX' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  2250.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00116',
  'engine gaurd limeted 1 L',
  '116',
  (SELECT id FROM product_categories WHERE name = 'العناية بالمحرك' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'CRAX' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  200.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00117',
  'Crystal doom 1 l',
  '117',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  200.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00118',
  'Crystal doom 4 l',
  '118',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  725.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00119',
  'eco wax',
  '119',
  (SELECT id FROM product_categories WHERE name = 'العناية بالتابلوه' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  350.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00120',
  'express touch 1 l',
  '120',
  (SELECT id FROM product_categories WHERE name = 'العناية بالتابلوه' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'CRAX' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  325.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00121',
  'wind shield 1 li',
  '121',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'CRAX' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  40.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00122',
  'فوطة فريكلا وش واحد',
  '122',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  30.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00123',
  'فوطة فريكلا وشين',
  '123',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  40.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00124',
  'فوطة 40*40 دبل 850 جرام',
  '124',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  48.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00125',
  'eco wax 5 k.g',
  '125',
  (SELECT id FROM product_categories WHERE name = 'العناية بالتابلوه' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'CRAX' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  320.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00126',
  'shine & black 1 k.g',
  '126',
  (SELECT id FROM product_categories WHERE name = 'العناية بالإطارات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'CRAX' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  150.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00127',
  'كارت فابريكا vip كبير',
  '127',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  25.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00128',
  'ECO WAX 1 K.G',
  '128',
  (SELECT id FROM product_categories WHERE name = 'العناية بالتابلوه' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  120.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00129',
  'engine gaurd unlimeted 1 L',
  '129',
  (SELECT id FROM product_categories WHERE name = 'العناية بالمحرك' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'CRAX' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  350.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00130',
  'max effect 25 li',
  '130',
  (SELECT id FROM product_categories WHERE name = 'العناية بالفرش الداخلي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  4095.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00131',
  'pistol 25 li',
  '131',
  (SELECT id FROM product_categories WHERE name = 'العناية بالمحرك' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  1500.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00132',
  'Magnetic shield tank 120 li',
  '132',
  (SELECT id FROM product_categories WHERE name = 'العناية بالمحرك' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  13250.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00133',
  'SUPER NOVA 200 ML',
  '133',
  (SELECT id FROM product_categories WHERE name = 'العناية بالتابلوه' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  80.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00134',
  'SUPER NOVA100 ML',
  '134',
  (SELECT id FROM product_categories WHERE name = 'العناية بالتابلوه' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  50.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00135',
  'SUPER NOVA 50 ML',
  '135',
  (SELECT id FROM product_categories WHERE name = 'العناية بالتابلوه' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  30.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00136',
  'D WAX 200 ML',
  '136',
  (SELECT id FROM product_categories WHERE name = 'العناية بالتابلوه' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  70.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00137',
  'D WAX 100 ML',
  '137',
  (SELECT id FROM product_categories WHERE name = 'العناية بالتابلوه' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  45.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00138',
  'D WAX 50 ML',
  '138',
  (SELECT id FROM product_categories WHERE name = 'العناية بالتابلوه' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  25.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00139',
  'ECO WAX 200 ML',
  '139',
  (SELECT id FROM product_categories WHERE name = 'العناية بالتابلوه' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  55.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00014',
  'EXPRESS TOUCH 5 L',
  '14',
  (SELECT id FROM product_categories WHERE name = 'العناية بالتابلوه' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'CRAX' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  950.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00140',
  'ECO WAX 100 ML',
  '140',
  (SELECT id FROM product_categories WHERE name = 'العناية بالتابلوه' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  40.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00141',
  'ECO WAX 50 ML',
  '141',
  (SELECT id FROM product_categories WHERE name = 'العناية بالتابلوه' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  22.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00142',
  'CRYSTAL DOOM 100 ML',
  '142',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  40.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00143',
  'CRYSTAL DOOM 50 ML',
  '143',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  25.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00144',
  'SHAMPOO WAX UNLIMITED 1 LI',
  '144',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  125.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00145',
  'SHAMPOO WAX UNLIMITED 2OO ML',
  '145',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  40.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00146',
  'MAX EFFECT 100 ML',
  '146',
  (SELECT id FROM product_categories WHERE name = 'العناية بالفرش الداخلي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  30.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00147',
  'ULTRA MAX GREEN 200 ML',
  '147',
  (SELECT id FROM product_categories WHERE name = 'العناية بالفرش الداخلي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  45.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00148',
  'LTRA SHINE 700 ML',
  '148',
  (SELECT id FROM product_categories WHERE name = 'العناية بالإطارات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  185.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00149',
  'ULTRA SHINE 200 ML',
  '149',
  (SELECT id FROM product_categories WHERE name = 'العناية بالإطارات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  70.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00150',
  'DEEP BLACK 200 ML',
  '150',
  (SELECT id FROM product_categories WHERE name = 'العناية بالإطارات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  60.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00151',
  'GLOW AWAY 200 ML',
  '151',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  50.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00152',
  'GLOW AWAY 100 ML',
  '152',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  35.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00153',
  'SHINE& SHIELD 700 ML',
  '153',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  135.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00154',
  'BLACK RECHARGE 700 ML',
  '154',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  165.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00155',
  'BLACK RECHARGE 200 ML',
  '155',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'End User' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  65.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00156',
  'عرض 25%كرتونة 12 لتر',
  '156',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'عروض' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  1460.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00158',
  'عرض 20%كرتونة 4 لتر×3',
  '158',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'عروض' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  1240.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00159',
  'eco wax 25 li',
  '159',
  (SELECT id FROM product_categories WHERE name = 'العناية بالتابلوه' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  2000.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00016',
  'SHINE & BLACK 5 L',
  '16',
  (SELECT id FROM product_categories WHERE name = 'العناية بالإطارات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'CRAX' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  450.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00160',
  'ULTRA shine 25 li',
  '160',
  (SELECT id FROM product_categories WHERE name = 'العناية بالإطارات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  4200.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00161',
  'فوطة ماكرو رمادى',
  '161',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  125.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00162',
  'pistol tank 125',
  '162',
  (SELECT id FROM product_categories WHERE name = 'العناية بالمحرك' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  7500.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00163',
  'pisto tank 250',
  '163',
  (SELECT id FROM product_categories WHERE name = 'العناية بالمحرك' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  14500.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00164',
  'دواسة سلوفان ربع 4 لون',
  '164',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  3.25, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00165',
  'فوطة 35 *70 اوتو',
  '165',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  50.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00166',
  'فوطة 40*75 اوتو',
  '166',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  55.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00167',
  'فوطة 30*60 اوتو',
  '167',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  40.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00168',
  'فوطة 40*40 عش النحل اوتو',
  '168',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  50.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00169',
  'فوطة 40*40 اكس اوتو',
  '169',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  45.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00017',
  'ENGINE GAURD',
  '17',
  (SELECT id FROM product_categories WHERE name = 'العناية بالمحرك' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'CRAX' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  910.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00170',
  'فوطة 40*40 خفيفة اوتو',
  '170',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  30.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00171',
  'فوطة 40*60 عش النحل اوتو',
  '171',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  50.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00172',
  'سفنجة شرشوبة اوتو',
  '172',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  50.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00173',
  'سفنجة مصرى اوتو',
  '173',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  35.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00174',
  'فرشة علبة زرقا متعدد اوتو',
  '174',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  150.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00175',
  'مسدس مياه 8 مرحلة اوتو',
  '175',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  150.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00176',
  'طقم صيانة اوتو',
  '176',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  10.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00177',
  'طفاية بدون غطا اوتو',
  '177',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  25.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00186',
  'TURTLE 51796',
  '186',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Turtle Wax' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  250.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00187',
  'GRAPHITE HIGHT END 85/20',
  '187',
  (SELECT id FROM product_categories WHERE name = 'العناية بالإطارات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  500.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00188',
  'GRAPHITE SELECTED 70/30',
  '188',
  (SELECT id FROM product_categories WHERE name = 'العناية بالإطارات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  500.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00189',
  'GRAPHITE CLASSIC 125/13',
  '189',
  (SELECT id FROM product_categories WHERE name = 'العناية بالإطارات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  500.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00193',
  'deep black 25 li',
  '193',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'غير محدد' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  3575.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00194',
  'ULTRA  MAX GREEN 25 LI',
  '194',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'غير محدد' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  3500.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00195',
  'فوطة 30*40 حز احمر',
  '195',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'غير محدد' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  45.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00196',
  'فوطة 40*40حز احمر',
  '196',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'غير محدد' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  60.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00197',
  'فوطة ماركات',
  '197',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'غير محدد' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  30.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00198',
  'فوطة زجاج ابيض كبيرة',
  '198',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'غير محدد' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  60.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00199',
  'فوطة زجاج ابيض صغيرة',
  '199',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'غير محدد' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  40.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00200',
  'فوطة 40*40 مضلع تقيل',
  '200',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'غير محدد' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  60.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00201',
  'استيكة فرد نانو',
  '201',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'غير محدد' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  30.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00202',
  'عرض ايكو 310',
  '202',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'غير محدد' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  310.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00203',
  'عرض 355 دي واكس',
  '203',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'غير محدد' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  355.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00204',
  'عرض 395 سوبر نوفا',
  '204',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'غير محدد' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  395.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00205',
  'عرض 1215 كيماوي 4 لتر',
  '205',
  (SELECT id FROM product_categories WHERE name = 'عروض' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'غير محدد' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  1215.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00206',
  'عرض 450 مستلزمات',
  '206',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'غير محدد' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  450.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00207',
  'عرض 1360 سوبر نوفا',
  '207',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'غير محدد' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  1360.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00208',
  'عرض 1350 دي واكس 4 لتر',
  '208',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'غير محدد' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  1350.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00209',
  'عرض 1315 دي واكس',
  '209',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'غير محدد' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  1315.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00210',
  'عرض الترا ماكس 4 لتر + 2 شامبو هدية',
  '210',
  (SELECT id FROM product_categories WHERE name = 'عروض' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'غير محدد' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  600.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00211',
  'عرض ماكس ايفيكت 4 لتر + 2 شامبو هدية',
  '211',
  (SELECT id FROM product_categories WHERE name = 'عروض' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'غير محدد' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  750.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00212',
  'pistol 1 li',
  '212',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'غير محدد' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  75.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00213',
  'الترا ماكس جرين 950 ملي مفروشات',
  '213',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'غير محدد' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  100.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00214',
  'pistol 700 black',
  '214',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'غير محدد' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  90.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00022',
  'فرشة تكييف',
  '22',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  20.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00026',
  'طقم بوليش 3 قطعة بيد',
  '26',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  125.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00033',
  'طقم تطويل بفر',
  '33',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  250.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00039',
  'بفر فرو 7 بوصة',
  '39',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  95.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00040',
  'طقم فرشة 5 قطعة',
  '40',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  125.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00053',
  'جوانتى خفيف اوتو',
  '53',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  17.5, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00059',
  'سفنجة غسيل على كارت كبيرة',
  '59',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  30.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00063',
  'فوطة جلد غزال كبير',
  '63',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  75.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00065',
  'فرشة تكيف علي كرت',
  '65',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  25.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00066',
  'سفنجة غسيل علي كارت صغيرة',
  '66',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  15.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00069',
  'D-wax personal user',
  '69',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'FALS' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  50.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00070',
  'super nova personal user',
  '70',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'FALS' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  60.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00071',
  'shampo wax personal user',
  '71',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'FALS' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  50.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00072',
  'ultra max personal user',
  '72',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'FALS' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  48.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00073',
  'ultra shine personal user',
  '73',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'FALS' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  85.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00080',
  'معطر فابريكا جديد',
  '80',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  20.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00081',
  'ULTRA SHINE 4 L NEW',
  '81',
  (SELECT id FROM product_categories WHERE name = 'العناية بالإطارات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  750.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00082',
  'ULTRA SHINE 1 L NEW',
  '82',
  (SELECT id FROM product_categories WHERE name = 'العناية بالإطارات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  200.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00083',
  'DEEP BLACK 4 L NEW',
  '83',
  (SELECT id FROM product_categories WHERE name = 'العناية بالإطارات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  600.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00084',
  'DEEP BLACK 1 L NEW',
  '84',
  (SELECT id FROM product_categories WHERE name = 'العناية بالإطارات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  165.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00085',
  'ULTRA MAX GREEN 4 L NEW',
  '85',
  (SELECT id FROM product_categories WHERE name = 'العناية بالفرش الداخلي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  600.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00086',
  'ULTRA MAX GREEN 1 L NEW',
  '86',
  (SELECT id FROM product_categories WHERE name = 'العناية بالفرش الداخلي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  175.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00087',
  'D-WAX 4 L NEW',
  '87',
  (SELECT id FROM product_categories WHERE name = 'العناية بالتابلوه' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  600.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00088',
  'D-WAX 1 L NEW',
  '88',
  (SELECT id FROM product_categories WHERE name = 'العناية بالتابلوه' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  175.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00089',
  'SHAMPOO WAX 4 L NEW',
  '89',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  200.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00090',
  'SHAMPOO WAX 1 L NEW',
  '90',
  (SELECT id FROM product_categories WHERE name = 'العناية بالسطح الخارجي' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  60.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00091',
  'MAGNATIC SHIELD 4 L NEW',
  '91',
  (SELECT id FROM product_categories WHERE name = 'العناية بالمحرك' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  525.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00092',
  'MAGNATICE SHIELD 1 L NEW',
  '92',
  (SELECT id FROM product_categories WHERE name = 'العناية بالمحرك' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  150.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00093',
  'SUPER NOVA 4 L NEW',
  '93',
  (SELECT id FROM product_categories WHERE name = 'العناية بالتابلوه' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  775.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00094',
  'SUPER NOVA 1 L NEW',
  '94',
  (SELECT id FROM product_categories WHERE name = 'العناية بالتابلوه' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Crystal' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  200.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00095',
  'بادة طابلو زرقا جديد',
  '95',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  50.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00097',
  'فوطة 30*70 جديد',
  '97',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  30.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

INSERT INTO products (
  sku, name, barcode,
  category_id, brand_id, base_unit_id,
  selling_price, cost_price,
  description, is_active
)
SELECT
  'PRD-00099',
  'فوطة 40 *30جديد جديد',
  '99',
  (SELECT id FROM product_categories WHERE name = 'المستلزمات والأدوات' LIMIT 1),
  (SELECT id FROM brands WHERE name = 'Tools' LIMIT 1),
  (SELECT id FROM units WHERE name = 'قطعة' LIMIT 1),
  20.0, 0,
  NULL, true
ON CONFLICT (sku) DO UPDATE SET
  name          = EXCLUDED.name,
  selling_price = EXCLUDED.selling_price,
  category_id   = EXCLUDED.category_id,
  brand_id      = EXCLUDED.brand_id,
  updated_at    = now();

COMMIT;

-- ✓ انتهى ملف الـ Seed