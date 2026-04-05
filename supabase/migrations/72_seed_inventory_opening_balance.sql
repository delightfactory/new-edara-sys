-- ═══════════════════════════════════════════════════════════════════
-- Migration: 72_seed_inventory_opening_balance.sql
-- الهدف   : حقن أرصدة المخزون الافتتاحية كما في جرد 31 مارس 2026
-- المنتجات: 78 صنف
-- القيمة  : 358,892.67 ج.م
-- الوحدة  : قطعة (افتراضي — يمكن تعديل وحدة القياس لاحقاً)
-- الاستراتيجية: update_stock_wac → idempotent (يتجاهل المنتجات ذات رصيد موجود)
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ════════════════════════════════════════════════════════════════════
-- ضمان: التأكد من وجود وحدات القياس الفعلية (للاستخدام المستقبلي)
-- ════════════════════════════════════════════════════════════════════
INSERT INTO units (name, symbol, is_base)
VALUES
  ('جركن', 'جركن', false),
  ('عبوة', 'عبوة', false),
  ('عرض', 'عرض', false),
  ('كرتونة', 'كرتونة', false)
ON CONFLICT (name) DO NOTHING;

-- ════════════════════════════════════════════════════════════════════
-- حقن أرصدة المخزون الافتتاحية
-- ════════════════════════════════════════════════════════════════════

-- [17] ENGINE GAURD (وحدة جرد: جركن)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '17' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '17', 'ENGINE GAURD';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '17', 'ENGINE GAURD';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      8.0,           -- الكمية الفعلية من الجرد
      540.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 8.0 — WAC: 540.0 ج.م', '17', 'ENGINE GAURD';
  END IF;
END $$;

-- [22] فرشة تكييف
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '22' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '22', 'فرشة تكييف';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '22', 'فرشة تكييف';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      279.0,           -- الكمية الفعلية من الجرد
      10.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 279.0 — WAC: 10.0 ج.م', '22', 'فرشة تكييف';
  END IF;
END $$;

-- [26] طقم بوليش 3 قطعة بيد
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '26' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '26', 'طقم بوليش 3 قطعة بيد';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '26', 'طقم بوليش 3 قطعة بيد';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      5.0,           -- الكمية الفعلية من الجرد
      35.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 5.0 — WAC: 35.0 ج.م', '26', 'طقم بوليش 3 قطعة بيد';
  END IF;
END $$;

-- [33] طقم تطويل بفر
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '33' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '33', 'طقم تطويل بفر';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '33', 'طقم تطويل بفر';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      5.0,           -- الكمية الفعلية من الجرد
      75.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 5.0 — WAC: 75.0 ج.م', '33', 'طقم تطويل بفر';
  END IF;
END $$;

-- [40] طقم فرشة 5 قطعة (وحدة جرد: عبوة)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '40' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '40', 'طقم فرشة 5 قطعة';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '40', 'طقم فرشة 5 قطعة';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      202.0,           -- الكمية الفعلية من الجرد
      40.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 202.0 — WAC: 40.0 ج.م', '40', 'طقم فرشة 5 قطعة';
  END IF;
END $$;

-- [53] جوانتي خفيف اوتو
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '53' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '53', 'جوانتي خفيف اوتو';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '53', 'جوانتي خفيف اوتو';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      66.0,           -- الكمية الفعلية من الجرد
      10.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 66.0 — WAC: 10.0 ج.م', '53', 'جوانتي خفيف اوتو';
  END IF;
END $$;

-- [63] فوطة جلد غزال كبير
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '63' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '63', 'فوطة جلد غزال كبير';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '63', 'فوطة جلد غزال كبير';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      149.0,           -- الكمية الفعلية من الجرد
      40.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 149.0 — WAC: 40.0 ج.م', '63', 'فوطة جلد غزال كبير';
  END IF;
END $$;

-- [81] ULTRA SHINE 4 L NEW (وحدة جرد: جركن)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '81' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '81', 'ULTRA SHINE 4 L NEW';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '81', 'ULTRA SHINE 4 L NEW';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      19.0,           -- الكمية الفعلية من الجرد
      590.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 19.0 — WAC: 590.0 ج.م', '81', 'ULTRA SHINE 4 L NEW';
  END IF;
END $$;

-- [82] ULTRA SHINE 1 L NEW (وحدة جرد: جركن)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '82' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '82', 'ULTRA SHINE 1 L NEW';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '82', 'ULTRA SHINE 1 L NEW';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      103.0,           -- الكمية الفعلية من الجرد
      127.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 103.0 — WAC: 127.0 ج.م', '82', 'ULTRA SHINE 1 L NEW';
  END IF;
END $$;

-- [83] DEEP BLACK 4 L NEW (وحدة جرد: جركن)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '83' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '83', 'DEEP BLACK 4 L NEW';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '83', 'DEEP BLACK 4 L NEW';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      14.0,           -- الكمية الفعلية من الجرد
      465.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 14.0 — WAC: 465.0 ج.م', '83', 'DEEP BLACK 4 L NEW';
  END IF;
END $$;

-- [84] DEEP BLACK 1 L NEW (وحدة جرد: جركن)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '84' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '84', 'DEEP BLACK 1 L NEW';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '84', 'DEEP BLACK 1 L NEW';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      70.0,           -- الكمية الفعلية من الجرد
      126.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 70.0 — WAC: 126.0 ج.م', '84', 'DEEP BLACK 1 L NEW';
  END IF;
END $$;

-- [85] ULTRA MAX GREEN 4 L (وحدة جرد: جركن)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '85' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '85', 'ULTRA MAX GREEN 4 L';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '85', 'ULTRA MAX GREEN 4 L';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      11.0,           -- الكمية الفعلية من الجرد
      357.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 11.0 — WAC: 357.0 ج.م', '85', 'ULTRA MAX GREEN 4 L';
  END IF;
END $$;

-- [86] ULTRA MAX GREEN 1 L NEW (وحدة جرد: جركن)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '86' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '86', 'ULTRA MAX GREEN 1 L NEW';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '86', 'ULTRA MAX GREEN 1 L NEW';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      84.0,           -- الكمية الفعلية من الجرد
      111.5,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 84.0 — WAC: 111.5 ج.م', '86', 'ULTRA MAX GREEN 1 L NEW';
  END IF;
END $$;

-- [87] D-WAX 4 L NEW (وحدة جرد: جركن)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '87' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '87', 'D-WAX 4 L NEW';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '87', 'D-WAX 4 L NEW';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      21.0,           -- الكمية الفعلية من الجرد
      382.5,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 21.0 — WAC: 382.5 ج.م', '87', 'D-WAX 4 L NEW';
  END IF;
END $$;

-- [88] D-WAX 1 L NEW (وحدة جرد: جركن)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '88' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '88', 'D-WAX 1 L NEW';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '88', 'D-WAX 1 L NEW';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      72.0,           -- الكمية الفعلية من الجرد
      111.5,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 72.0 — WAC: 111.5 ج.م', '88', 'D-WAX 1 L NEW';
  END IF;
END $$;

-- [89] SHAMPOO WAX 4 L NEW (وحدة جرد: جركن)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '89' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '89', 'SHAMPOO WAX 4 L NEW';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '89', 'SHAMPOO WAX 4 L NEW';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      30.0,           -- الكمية الفعلية من الجرد
      127.5,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 30.0 — WAC: 127.5 ج.م', '89', 'SHAMPOO WAX 4 L NEW';
  END IF;
END $$;

-- [91] MAGNATIC SHIELD 4 L NEW (وحدة جرد: جركن)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '91' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '91', 'MAGNATIC SHIELD 4 L NEW';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '91', 'MAGNATIC SHIELD 4 L NEW';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      6.0,           -- الكمية الفعلية من الجرد
      310.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 6.0 — WAC: 310.0 ج.م', '91', 'MAGNATIC SHIELD 4 L NEW';
  END IF;
END $$;

-- [92] MAGNATICE SHIELD 1 L NEW (وحدة جرد: جركن)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '92' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '92', 'MAGNATICE SHIELD 1 L NEW';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '92', 'MAGNATICE SHIELD 1 L NEW';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      15.0,           -- الكمية الفعلية من الجرد
      82.5,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 15.0 — WAC: 82.5 ج.م', '92', 'MAGNATICE SHIELD 1 L NEW';
  END IF;
END $$;

-- [94] SUPER NOVA 1 L NEW (وحدة جرد: جركن)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '94' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '94', 'SUPER NOVA 1 L NEW';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '94', 'SUPER NOVA 1 L NEW';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      37.0,           -- الكمية الفعلية من الجرد
      145.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 37.0 — WAC: 145.0 ج.م', '94', 'SUPER NOVA 1 L NEW';
  END IF;
END $$;

-- [100] فوطة جلد غزال صغير
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '100' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '100', 'فوطة جلد غزال صغير';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '100', 'فوطة جلد غزال صغير';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      165.0,           -- الكمية الفعلية من الجرد
      25.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 165.0 — WAC: 25.0 ج.م', '100', 'فوطة جلد غزال صغير';
  END IF;
END $$;

-- [106] pistol 700
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '106' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '106', 'pistol 700';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '106', 'pistol 700';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      35.0,           -- الكمية الفعلية من الجرد
      52.5,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 35.0 — WAC: 52.5 ج.م', '106', 'pistol 700';
  END IF;
END $$;

-- [108] MAX EFFECT 1 L NEW (وحدة جرد: جركن)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '108' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '108', 'MAX EFFECT 1 L NEW';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '108', 'MAX EFFECT 1 L NEW';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      7.0,           -- الكمية الفعلية من الجرد
      110.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 7.0 — WAC: 110.0 ج.م', '108', 'MAX EFFECT 1 L NEW';
  END IF;
END $$;

-- [117] CRYSTAL DOOM 1 L (وحدة جرد: جركن)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '117' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '117', 'CRYSTAL DOOM 1 L';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '117', 'CRYSTAL DOOM 1 L';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      29.0,           -- الكمية الفعلية من الجرد
      125.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 29.0 — WAC: 125.0 ج.م', '117', 'CRYSTAL DOOM 1 L';
  END IF;
END $$;

-- [118] CRYSTAL DOOM 4 L (وحدة جرد: جركن)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '118' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '118', 'CRYSTAL DOOM 4 L';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '118', 'CRYSTAL DOOM 4 L';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      3.0,           -- الكمية الفعلية من الجرد
      300.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 3.0 — WAC: 300.0 ج.م', '118', 'CRYSTAL DOOM 4 L';
  END IF;
END $$;

-- [119] eco wax (وحدة جرد: جركن)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '119' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '119', 'eco wax';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '119', 'eco wax';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      2.0,           -- الكمية الفعلية من الجرد
      290.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 2.0 — WAC: 290.0 ج.م', '119', 'eco wax';
  END IF;
END $$;

-- [120] express touch 1 l (وحدة جرد: جركن)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '120' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '120', 'express touch 1 l';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '120', 'express touch 1 l';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      2.0,           -- الكمية الفعلية من الجرد
      180.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 2.0 — WAC: 180.0 ج.م', '120', 'express touch 1 l';
  END IF;
END $$;

-- [121] wind shield 1 l (وحدة جرد: عبوة)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '121' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '121', 'wind shield 1 l';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '121', 'wind shield 1 l';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      10.0,           -- الكمية الفعلية من الجرد
      16.667,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 10.0 — WAC: 16.667 ج.م', '121', 'wind shield 1 l';
  END IF;
END $$;

-- [122] فوطة فريكلا وش واحد
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '122' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '122', 'فوطة فريكلا وش واحد';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '122', 'فوطة فريكلا وش واحد';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      204.0,           -- الكمية الفعلية من الجرد
      20.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 204.0 — WAC: 20.0 ج.م', '122', 'فوطة فريكلا وش واحد';
  END IF;
END $$;

-- [129] engine gaurd unlimited 1 li (وحدة جرد: جركن)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '129' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '129', 'engine gaurd unlimited 1 li';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '129', 'engine gaurd unlimited 1 li';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      44.0,           -- الكمية الفعلية من الجرد
      250.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 44.0 — WAC: 250.0 ج.م', '129', 'engine gaurd unlimited 1 li';
  END IF;
END $$;

-- [133] super nova 200 ml
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '133' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '133', 'super nova 200 ml';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '133', 'super nova 200 ml';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      37.0,           -- الكمية الفعلية من الجرد
      60.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 37.0 — WAC: 60.0 ج.م', '133', 'super nova 200 ml';
  END IF;
END $$;

-- [134] super nova 100 ml
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '134' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '134', 'super nova 100 ml';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '134', 'super nova 100 ml';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      326.0,           -- الكمية الفعلية من الجرد
      37.5,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 326.0 — WAC: 37.5 ج.م', '134', 'super nova 100 ml';
  END IF;
END $$;

-- [135] super nova 50 ml
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '135' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '135', 'super nova 50 ml';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '135', 'super nova 50 ml';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      325.0,           -- الكمية الفعلية من الجرد
      22.5,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 325.0 — WAC: 22.5 ج.م', '135', 'super nova 50 ml';
  END IF;
END $$;

-- [136] d wax 200 ml
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '136' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '136', 'd wax 200 ml';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '136', 'd wax 200 ml';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      49.0,           -- الكمية الفعلية من الجرد
      52.5,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 49.0 — WAC: 52.5 ج.م', '136', 'd wax 200 ml';
  END IF;
END $$;

-- [137] d wax 100 ml
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '137' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '137', 'd wax 100 ml';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '137', 'd wax 100 ml';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      412.0,           -- الكمية الفعلية من الجرد
      33.75,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 412.0 — WAC: 33.75 ج.م', '137', 'd wax 100 ml';
  END IF;
END $$;

-- [138] d wax 50 ml
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '138' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '138', 'd wax 50 ml';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '138', 'd wax 50 ml';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      338.0,           -- الكمية الفعلية من الجرد
      18.75,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 338.0 — WAC: 18.75 ج.م', '138', 'd wax 50 ml';
  END IF;
END $$;

-- [139] eco wax 200 ml
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '139' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '139', 'eco wax 200 ml';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '139', 'eco wax 200 ml';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      34.0,           -- الكمية الفعلية من الجرد
      41.5,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 34.0 — WAC: 41.5 ج.م', '139', 'eco wax 200 ml';
  END IF;
END $$;

-- [140] eco wax 100 ml
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '140' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '140', 'eco wax 100 ml';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '140', 'eco wax 100 ml';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      393.0,           -- الكمية الفعلية من الجرد
      30.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 393.0 — WAC: 30.0 ج.م', '140', 'eco wax 100 ml';
  END IF;
END $$;

-- [141] eco wax 50 ml
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '141' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '141', 'eco wax 50 ml';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '141', 'eco wax 50 ml';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      349.0,           -- الكمية الفعلية من الجرد
      16.5,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 349.0 — WAC: 16.5 ج.م', '141', 'eco wax 50 ml';
  END IF;
END $$;

-- [142] crystal doom 100 ml
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '142' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '142', 'crystal doom 100 ml';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '142', 'crystal doom 100 ml';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      16.0,           -- الكمية الفعلية من الجرد
      30.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 16.0 — WAC: 30.0 ج.م', '142', 'crystal doom 100 ml';
  END IF;
END $$;

-- [143] crystal doom 50 ml
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '143' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '143', 'crystal doom 50 ml';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '143', 'crystal doom 50 ml';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      136.0,           -- الكمية الفعلية من الجرد
      18.75,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 136.0 — WAC: 18.75 ج.م', '143', 'crystal doom 50 ml';
  END IF;
END $$;

-- [144] shampoo wax unlimited 1 li
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '144' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '144', 'shampoo wax unlimited 1 li';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '144', 'shampoo wax unlimited 1 li';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      34.0,           -- الكمية الفعلية من الجرد
      93.75,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 34.0 — WAC: 93.75 ج.م', '144', 'shampoo wax unlimited 1 li';
  END IF;
END $$;

-- [145] shampoo wax unlimited 200 ml
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '145' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '145', 'shampoo wax unlimited 200 ml';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '145', 'shampoo wax unlimited 200 ml';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      40.0,           -- الكمية الفعلية من الجرد
      30.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 40.0 — WAC: 30.0 ج.م', '145', 'shampoo wax unlimited 200 ml';
  END IF;
END $$;

-- [146] max effect 100 ml
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '146' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '146', 'max effect 100 ml';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '146', 'max effect 100 ml';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      258.0,           -- الكمية الفعلية من الجرد
      22.5,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 258.0 — WAC: 22.5 ج.م', '146', 'max effect 100 ml';
  END IF;
END $$;

-- [147] ultra max green 200 ml
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '147' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '147', 'ultra max green 200 ml';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '147', 'ultra max green 200 ml';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      44.0,           -- الكمية الفعلية من الجرد
      33.75,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 44.0 — WAC: 33.75 ج.م', '147', 'ultra max green 200 ml';
  END IF;
END $$;

-- [148] ultra shine 700 ml
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '148' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '148', 'ultra shine 700 ml';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '148', 'ultra shine 700 ml';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      21.0,           -- الكمية الفعلية من الجرد
      138.75,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 21.0 — WAC: 138.75 ج.م', '148', 'ultra shine 700 ml';
  END IF;
END $$;

-- [149] ultra shine 200 ml
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '149' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '149', 'ultra shine 200 ml';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '149', 'ultra shine 200 ml';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      17.0,           -- الكمية الفعلية من الجرد
      52.5,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 17.0 — WAC: 52.5 ج.م', '149', 'ultra shine 200 ml';
  END IF;
END $$;

-- [150] deep black 200 ml
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '150' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '150', 'deep black 200 ml';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '150', 'deep black 200 ml';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      67.0,           -- الكمية الفعلية من الجرد
      45.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 67.0 — WAC: 45.0 ج.م', '150', 'deep black 200 ml';
  END IF;
END $$;

-- [151] glow away 200 ml
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '151' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '151', 'glow away 200 ml';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '151', 'glow away 200 ml';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      2.0,           -- الكمية الفعلية من الجرد
      37.5,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 2.0 — WAC: 37.5 ج.م', '151', 'glow away 200 ml';
  END IF;
END $$;

-- [152] glow away 100 ml
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '152' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '152', 'glow away 100 ml';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '152', 'glow away 100 ml';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      18.0,           -- الكمية الفعلية من الجرد
      26.25,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 18.0 — WAC: 26.25 ج.م', '152', 'glow away 100 ml';
  END IF;
END $$;

-- [153] shine &shield 700 ml
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '153' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '153', 'shine &shield 700 ml';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '153', 'shine &shield 700 ml';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      18.0,           -- الكمية الفعلية من الجرد
      101.25,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 18.0 — WAC: 101.25 ج.م', '153', 'shine &shield 700 ml';
  END IF;
END $$;

-- [154] black recharge 700 ml
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '154' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '154', 'black recharge 700 ml';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '154', 'black recharge 700 ml';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      3.0,           -- الكمية الفعلية من الجرد
      123.75,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 3.0 — WAC: 123.75 ج.م', '154', 'black recharge 700 ml';
  END IF;
END $$;

-- [155] black recharge 200 ml
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '155' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '155', 'black recharge 200 ml';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '155', 'black recharge 200 ml';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      41.0,           -- الكمية الفعلية من الجرد
      48.75,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 41.0 — WAC: 48.75 ج.م', '155', 'black recharge 200 ml';
  END IF;
END $$;

-- [165] فوطة 35x70اوتو
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '165' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '165', 'فوطة 35*70اوتو';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '165', 'فوطة 35*70اوتو';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      28.0,           -- الكمية الفعلية من الجرد
      35.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 28.0 — WAC: 35.0 ج.م', '165', 'فوطة 35*70اوتو';
  END IF;
END $$;

-- [166] فوطة 40x75 اوتو
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '166' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '166', 'فوطة 40*75 اوتو';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '166', 'فوطة 40*75 اوتو';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      31.0,           -- الكمية الفعلية من الجرد
      40.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 31.0 — WAC: 40.0 ج.م', '166', 'فوطة 40*75 اوتو';
  END IF;
END $$;

-- [169] فوطة 40x40 اكس اوتو
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '169' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '169', 'فوطة 40*40 اكس اوتو';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '169', 'فوطة 40*40 اكس اوتو';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      8.0,           -- الكمية الفعلية من الجرد
      30.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 8.0 — WAC: 30.0 ج.م', '169', 'فوطة 40*40 اكس اوتو';
  END IF;
END $$;

-- [172] سفنجة شرشوبة اوتو
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '172' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '172', 'سفنجة شرشوبة اوتو';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '172', 'سفنجة شرشوبة اوتو';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      50.0,           -- الكمية الفعلية من الجرد
      35.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 50.0 — WAC: 35.0 ج.م', '172', 'سفنجة شرشوبة اوتو';
  END IF;
END $$;

-- [173] سفنجة مصرى اوتو
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '173' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '173', 'سفنجة مصرى اوتو';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '173', 'سفنجة مصرى اوتو';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      44.0,           -- الكمية الفعلية من الجرد
      20.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 44.0 — WAC: 20.0 ج.م', '173', 'سفنجة مصرى اوتو';
  END IF;
END $$;

-- [187] GRAPHITE HIGHT END 85/20 (وحدة جرد: عبوة)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '187' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '187', 'GRAPHITE HIGHT END 85/20';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '187', 'GRAPHITE HIGHT END 85/20';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      16.0,           -- الكمية الفعلية من الجرد
      200.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 16.0 — WAC: 200.0 ج.م', '187', 'GRAPHITE HIGHT END 85/20';
  END IF;
END $$;

-- [188] GRAPHITE SELECTED 70/30 (وحدة جرد: عبوة)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '188' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '188', 'GRAPHITE SELECTED 70/30';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '188', 'GRAPHITE SELECTED 70/30';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      81.0,           -- الكمية الفعلية من الجرد
      200.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 81.0 — WAC: 200.0 ج.م', '188', 'GRAPHITE SELECTED 70/30';
  END IF;
END $$;

-- [189] GRAPHITE CLASSIC 125/13 (وحدة جرد: عبوة)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '189' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '189', 'GRAPHITE CLASSIC 125/13';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '189', 'GRAPHITE CLASSIC 125/13';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      91.0,           -- الكمية الفعلية من الجرد
      200.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 91.0 — WAC: 200.0 ج.م', '189', 'GRAPHITE CLASSIC 125/13';
  END IF;
END $$;

-- [195] فوطة 30x40 حز احمر
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '195' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '195', 'فوطة 30*40 حز احمر';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '195', 'فوطة 30*40 حز احمر';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      272.0,           -- الكمية الفعلية من الجرد
      30.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 272.0 — WAC: 30.0 ج.م', '195', 'فوطة 30*40 حز احمر';
  END IF;
END $$;

-- [196] فوطة 40x40 حز احمر
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '196' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '196', 'فوطة 40*40 حز احمر';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '196', 'فوطة 40*40 حز احمر';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      248.0,           -- الكمية الفعلية من الجرد
      40.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 248.0 — WAC: 40.0 ج.م', '196', 'فوطة 40*40 حز احمر';
  END IF;
END $$;

-- [197] فوطة ماركات
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '197' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '197', 'فوطة ماركات';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '197', 'فوطة ماركات';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      16.0,           -- الكمية الفعلية من الجرد
      19.5,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 16.0 — WAC: 19.5 ج.م', '197', 'فوطة ماركات';
  END IF;
END $$;

-- [198] فوطة زجاج ابيض كبير
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '198' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '198', 'فوطة زجاج ابيض كبير';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '198', 'فوطة زجاج ابيض كبير';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      356.0,           -- الكمية الفعلية من الجرد
      40.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 356.0 — WAC: 40.0 ج.م', '198', 'فوطة زجاج ابيض كبير';
  END IF;
END $$;

-- [199] فوطة زجاج ابيض صغير
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '199' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '199', 'فوطة زجاج ابيض صغير';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '199', 'فوطة زجاج ابيض صغير';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      106.0,           -- الكمية الفعلية من الجرد
      25.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 106.0 — WAC: 25.0 ج.م', '199', 'فوطة زجاج ابيض صغير';
  END IF;
END $$;

-- [200] فوطة 40x40 مضلع تقيل
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '200' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '200', 'فوطة 40*40 مضلع تقيل';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '200', 'فوطة 40*40 مضلع تقيل';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      221.0,           -- الكمية الفعلية من الجرد
      45.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 221.0 — WAC: 45.0 ج.م', '200', 'فوطة 40*40 مضلع تقيل';
  END IF;
END $$;

-- [201] استيكة فرد نانو
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '201' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '201', 'استيكة فرد نانو';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '201', 'استيكة فرد نانو';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      55.0,           -- الكمية الفعلية من الجرد
      20.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 55.0 — WAC: 20.0 ج.م', '201', 'استيكة فرد نانو';
  END IF;
END $$;

-- [203] عرض 355 دى واكس
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '203' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '203', 'عرض 355 دى واكس';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '203', 'عرض 355 دى واكس';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      18.0,           -- الكمية الفعلية من الجرد
      302.25,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 18.0 — WAC: 302.25 ج.م', '203', 'عرض 355 دى واكس';
  END IF;
END $$;

-- [204] عرض 395 سوبر نوفا
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '204' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '204', 'عرض 395 سوبر نوفا';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '204', 'عرض 395 سوبر نوفا';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      3.0,           -- الكمية الفعلية من الجرد
      335.75,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 3.0 — WAC: 335.75 ج.م', '204', 'عرض 395 سوبر نوفا';
  END IF;
END $$;

-- [205] عرض 1215 كيماوي 4 لتر
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '205' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '205', 'عرض 1215 كيماوي 4 لتر';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '205', 'عرض 1215 كيماوي 4 لتر';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      7.0,           -- الكمية الفعلية من الجرد
      1033.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 7.0 — WAC: 1033.0 ج.م', '205', 'عرض 1215 كيماوي 4 لتر';
  END IF;
END $$;

-- [207] عرض 1360 سوبر نوفا
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '207' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '207', 'عرض 1360 سوبر نوفا';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '207', 'عرض 1360 سوبر نوفا';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      11.0,           -- الكمية الفعلية من الجرد
      1222.25,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 11.0 — WAC: 1222.25 ج.م', '207', 'عرض 1360 سوبر نوفا';
  END IF;
END $$;

-- [209] عرض 1315 دي واكس
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '209' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '209', 'عرض 1315 دي واكس';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '209', 'عرض 1315 دي واكس';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      3.0,           -- الكمية الفعلية من الجرد
      1224.5,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 3.0 — WAC: 1224.5 ج.م', '209', 'عرض 1315 دي واكس';
  END IF;
END $$;

-- [202] عرض 310 ايكو
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '202' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '202', 'عرض 310 ايكو';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '202', 'عرض 310 ايكو';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      29.0,           -- الكمية الفعلية من الجرد
      265.75,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 29.0 — WAC: 265.75 ج.م', '202', 'عرض 310 ايكو';
  END IF;
END $$;

-- [210] عرض الترا ماكس 4 لتر +2 شامبو هدية (وحدة جرد: عرض)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '210' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '210', 'عرض الترا ماكس 4 لتر +2 شامبو هدية';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '210', 'عرض الترا ماكس 4 لتر +2 شامبو هدية';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      5.0,           -- الكمية الفعلية من الجرد
      525.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 5.0 — WAC: 525.0 ج.م', '210', 'عرض الترا ماكس 4 لتر +2 شامبو هدية';
  END IF;
END $$;

-- [211] عرض ماكس ايفيكت 4 لتر + 2 شامبو هدية (وحدة جرد: كرتونة)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '211' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '211', 'عرض ماكس ايفيكت 4 لتر + 2 شامبو هدية';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '211', 'عرض ماكس ايفيكت 4 لتر + 2 شامبو هدية';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      7.0,           -- الكمية الفعلية من الجرد
      560.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 7.0 — WAC: 560.0 ج.م', '211', 'عرض ماكس ايفيكت 4 لتر + 2 شامبو هدية';
  END IF;
END $$;

-- [212] pistol 1 li
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '212' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '212', 'pistol 1 li';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '212', 'pistol 1 li';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      9.0,           -- الكمية الفعلية من الجرد
      50.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 9.0 — WAC: 50.0 ج.م', '212', 'pistol 1 li';
  END IF;
END $$;

-- [213] الترا ماكس جرين 950 ملي مفروشات (وحدة جرد: عبوة)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '213' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '213', 'الترا ماكس جرين 950 ملي مفروشات';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '213', 'الترا ماكس جرين 950 ملي مفروشات';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      33.0,           -- الكمية الفعلية من الجرد
      50.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 33.0 — WAC: 50.0 ج.م', '213', 'الترا ماكس جرين 950 ملي مفروشات';
  END IF;
END $$;

-- [214] بيستول بلاك 700 (وحدة جرد: عبوة)
DO $$
DECLARE
  v_product_id   UUID;
  v_warehouse_id UUID;
  v_admin_id     UUID;
BEGIN
  SELECT id INTO v_product_id   FROM products   WHERE barcode = '214' LIMIT 1;
  SELECT id INTO v_warehouse_id FROM warehouses WHERE is_active = true ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_admin_id
    FROM profiles p
    JOIN user_roles ur ON ur.user_id = p.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name IN ('super_admin', 'ceo')
      AND ur.is_active = true
    ORDER BY p.created_at LIMIT 1;

  IF v_product_id IS NULL THEN
    RAISE WARNING '⚠️ منتج غير موجود: [%] %', '214', 'بيستول بلاك 700';
  ELSIF v_warehouse_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مخزن مفعّل في النظام';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم owner/admin';
  ELSIF EXISTS (
    SELECT 1 FROM stock
    WHERE warehouse_id = v_warehouse_id
      AND product_id   = v_product_id
      AND quantity > 0
  ) THEN
    RAISE NOTICE '⏭️  تجاوز [%] % — رصيد موجود بالفعل', '214', 'بيستول بلاك 700';
  ELSE
    PERFORM update_stock_wac(
      v_warehouse_id,
      v_product_id,
      31.0,           -- الكمية الفعلية من الجرد
      60.0,          -- WAC الافتتاحي (سعر التكلفة)
      'adjustment_add',
      'opening_balance',
      v_product_id,
      v_admin_id
    );
    RAISE NOTICE '✅ [%] % — كمية: 31.0 — WAC: 60.0 ج.م', '214', 'بيستول بلاك 700';
  END IF;
END $$;
COMMIT;

-- ════════════════════════════════════════════════════════════════════
-- للتحقق من نتائج الحقن:
-- SELECT p.barcode, p.name, s.quantity, s.wac, s.total_cost_value,
--        s.available_quantity, w.name as warehouse
-- FROM stock s
-- JOIN products p ON p.id = s.product_id
-- JOIN warehouses w ON w.id = s.warehouse_id
-- ORDER BY p.barcode::int;
-- ════════════════════════════════════════════════════════════════════
