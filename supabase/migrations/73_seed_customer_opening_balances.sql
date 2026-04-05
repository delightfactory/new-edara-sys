-- ═══════════════════════════════════════════════════════════════════
-- Migration: 73_seed_customer_opening_balances.sql
-- الهدف   : حقن أرصدة بداية المدة للعملاء كما في جرد 31 مارس 2026
-- العملاء : 40 عميل
-- الإجمالي: 165,363.60 ج.م
-- الاستراتيجية:
--   • يبحث عن العميل بالكود (CUS-XXXXX)
--   • يستدعي adjust_customer_opening_balance() الرسمية
--     → تضبط set_config('app.finance_context','opening_balance_adjustment')
--     → تتجاوز guard_customer_opening_balance trigger بأمان
--     → تُنشئ سجل في customer_ledger (type='debit', source_type='adjustment')
--     → تُنشئ قيد محاسبي في journal_entries (dr:1200 / cr:3200)
--     → تُسجل في customer_opening_balance_audit
--     → current_balance يتحدث تلقائياً عبر trigger الـ ledger
--   • idempotent: يتجاوز العميل اللي opening_balance > 0 بالفعل
-- ═══════════════════════════════════════════════════════════════════

BEGIN;


-- [1038] درفت كار — رصيد بداية المدة: 40,410.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01038'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01038 (درفت كار)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01038] درفت كار — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      40410.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01038] درفت كار — رصيد: 40,410.00 ج.م';
  END IF;
END $$;

-- [1041] اكسترا كار — رصيد بداية المدة: 1,210.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01041'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01041 (اكسترا كار)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01041] اكسترا كار — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      1210.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01041] اكسترا كار — رصيد: 1,210.00 ج.م';
  END IF;
END $$;

-- [1058] الغندور وبهاء للتجارة والتوزيع — رصيد بداية المدة: 3,999.60 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01058'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01058 (الغندور وبهاء للتجارة والتوزيع)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01058] الغندور وبهاء للتجارة والتوزيع — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      3999.6,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01058] الغندور وبهاء للتجارة والتوزيع — رصيد: 3,999.60 ج.م';
  END IF;
END $$;

-- [1108] سيتي كار — رصيد بداية المدة: 2,315.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01108'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01108 (سيتي كار)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01108] سيتي كار — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      2315.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01108] سيتي كار — رصيد: 2,315.00 ج.م';
  END IF;
END $$;

-- [1122] genius — رصيد بداية المدة: 35,524.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01122'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01122 (genius)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01122] genius — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      35524.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01122] genius — رصيد: 35,524.00 ج.م';
  END IF;
END $$;

-- [1148] سبونج — رصيد بداية المدة: 2,000.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01148'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01148 (سبونج)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01148] سبونج — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      2000.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01148] سبونج — رصيد: 2,000.00 ج.م';
  END IF;
END $$;

-- [1149] حسن شطفة — رصيد بداية المدة: 1,000.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01149'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01149 (حسن شطفة)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01149] حسن شطفة — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      1000.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01149] حسن شطفة — رصيد: 1,000.00 ج.م';
  END IF;
END $$;

-- [1193] مغسله ابو ياسين — رصيد بداية المدة: 375.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01193'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01193 (مغسله ابو ياسين)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01193] مغسله ابو ياسين — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      375.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01193] مغسله ابو ياسين — رصيد: 375.00 ج.م';
  END IF;
END $$;

-- [1239] البوب — رصيد بداية المدة: 5.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01239'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01239 (البوب)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01239] البوب — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      5.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01239] البوب — رصيد: 5.00 ج.م';
  END IF;
END $$;

-- [1279] water way — رصيد بداية المدة: 2,275.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01279'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01279 (water way)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01279] water way — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      2275.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01279] water way — رصيد: 2,275.00 ج.م';
  END IF;
END $$;

-- [1326] مغسلة الغنيمي — رصيد بداية المدة: 1,000.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01326'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01326 (مغسلة الغنيمي)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01326] مغسلة الغنيمي — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      1000.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01326] مغسلة الغنيمي — رصيد: 1,000.00 ج.م';
  END IF;
END $$;

-- [1418] El forsan — رصيد بداية المدة: 465.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01418'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01418 (El forsan)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01418] El forsan — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      465.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01418] El forsan — رصيد: 465.00 ج.م';
  END IF;
END $$;

-- [1533] auto chill — رصيد بداية المدة: 2,075.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01533'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01533 (auto chill)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01533] auto chill — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      2075.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01533] auto chill — رصيد: 2,075.00 ج.م';
  END IF;
END $$;

-- [1539] brillince — رصيد بداية المدة: 825.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01539'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01539 (brillince)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01539] brillince — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      825.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01539] brillince — رصيد: 825.00 ج.م';
  END IF;
END $$;

-- [1555] chillout الجلاء — رصيد بداية المدة: 2,225.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01555'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01555 (chillout الجلاء)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01555] chillout الجلاء — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      2225.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01555] chillout الجلاء — رصيد: 2,225.00 ج.م';
  END IF;
END $$;

-- [1564] camp garage — رصيد بداية المدة: 2,480.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01564'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01564 (camp garage)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01564] camp garage — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      2480.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01564] camp garage — رصيد: 2,480.00 ج.م';
  END IF;
END $$;

-- [1584] الدوليه 2 — رصيد بداية المدة: 450.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01584'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01584 (الدوليه 2)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01584] الدوليه 2 — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      450.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01584] الدوليه 2 — رصيد: 450.00 ج.م';
  END IF;
END $$;

-- [1596] مغسله ابو أسر — رصيد بداية المدة: 1,425.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01596'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01596 (مغسله ابو أسر)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01596] مغسله ابو أسر — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      1425.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01596] مغسله ابو أسر — رصيد: 1,425.00 ج.م';
  END IF;
END $$;

-- [1613] Eco clean — رصيد بداية المدة: 30.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01613'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01613 (Eco clean)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01613] Eco clean — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      30.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01613] Eco clean — رصيد: 30.00 ج.م';
  END IF;
END $$;

-- [1616] بازوكا كورنيش — رصيد بداية المدة: 1,620.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01616'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01616 (بازوكا كورنيش)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01616] بازوكا كورنيش — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      1620.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01616] بازوكا كورنيش — رصيد: 1,620.00 ج.م';
  END IF;
END $$;

-- [1628] for cars tanta — رصيد بداية المدة: 730.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01628'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01628 (for cars tanta)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01628] for cars tanta — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      730.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01628] for cars tanta — رصيد: 730.00 ج.م';
  END IF;
END $$;

-- [1629] track — رصيد بداية المدة: 675.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01629'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01629 (track)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01629] track — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      675.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01629] track — رصيد: 675.00 ج.م';
  END IF;
END $$;

-- [1650] ابو زياد مركز صيانه — رصيد بداية المدة: 660.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01650'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01650 (ابو زياد مركز صيانه)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01650] ابو زياد مركز صيانه — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      660.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01650] ابو زياد مركز صيانه — رصيد: 660.00 ج.م';
  END IF;
END $$;

-- [1656] global — رصيد بداية المدة: 500.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-01656'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-01656 (global)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-01656] global — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      500.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-01656] global — رصيد: 500.00 ج.م';
  END IF;
END $$;

-- [172] افندينا دمنهور — رصيد بداية المدة: 1,260.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-00172'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-00172 (افندينا دمنهور)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-00172] افندينا دمنهور — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      1260.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-00172] افندينا دمنهور — رصيد: 1,260.00 ج.م';
  END IF;
END $$;

-- [191] we care — رصيد بداية المدة: 1,000.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-00191'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-00191 (we care)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-00191] we care — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      1000.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-00191] we care — رصيد: 1,000.00 ج.م';
  END IF;
END $$;

-- [202] القطان* — رصيد بداية المدة: 1,590.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-00202'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-00202 (القطان*)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-00202] القطان* — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      1590.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-00202] القطان* — رصيد: 1,590.00 ج.م';
  END IF;
END $$;

-- [227] بلاك & يلو* — رصيد بداية المدة: 1,475.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-00227'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-00227 (بلاك & يلو*)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-00227] بلاك & يلو* — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      1475.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-00227] بلاك & يلو* — رصيد: 1,475.00 ج.م';
  END IF;
END $$;

-- [229] Ristereto — رصيد بداية المدة: 315.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-00229'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-00229 (Ristereto)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-00229] Ristereto — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      315.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-00229] Ristereto — رصيد: 315.00 ج.م';
  END IF;
END $$;

-- [275] مركز ابو بكر لخدمة السيارات — رصيد بداية المدة: 1,310.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-00275'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-00275 (مركز ابو بكر لخدمة السيارات)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-00275] مركز ابو بكر لخدمة السيارات — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      1310.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-00275] مركز ابو بكر لخدمة السيارات — رصيد: 1,310.00 ج.م';
  END IF;
END $$;

-- [308] Nitros — رصيد بداية المدة: 2,555.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-00308'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-00308 (Nitros)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-00308] Nitros — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      2555.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-00308] Nitros — رصيد: 2,555.00 ج.م';
  END IF;
END $$;

-- [321] spot8 — رصيد بداية المدة: 2,600.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-00321'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-00321 (spot8)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-00321] spot8 — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      2600.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-00321] spot8 — رصيد: 2,600.00 ج.م';
  END IF;
END $$;

-- [403] غيث — رصيد بداية المدة: 5,850.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-00403'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-00403 (غيث)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-00403] غيث — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      5850.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-00403] غيث — رصيد: 5,850.00 ج.م';
  END IF;
END $$;

-- [64] Shell دوس بنزينه — رصيد بداية المدة: 3,000.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-00064'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-00064 (Shell دوس بنزينه)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-00064] Shell دوس بنزينه — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      3000.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-00064] Shell دوس بنزينه — رصيد: 3,000.00 ج.م';
  END IF;
END $$;

-- [645] يحى الشال — رصيد بداية المدة: 200.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-00645'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-00645 (يحى الشال)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-00645] يحى الشال — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      200.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-00645] يحى الشال — رصيد: 200.00 ج.م';
  END IF;
END $$;

-- [702] وان ستوب الاشرف — رصيد بداية المدة: 21,775.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-00702'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-00702 (وان ستوب الاشرف)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-00702] وان ستوب الاشرف — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      21775.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-00702] وان ستوب الاشرف — رصيد: 21,775.00 ج.م';
  END IF;
END $$;

-- [718] pro guys — رصيد بداية المدة: 14,710.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-00718'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-00718 (pro guys)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-00718] pro guys — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      14710.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-00718] pro guys — رصيد: 14,710.00 ج.م';
  END IF;
END $$;

-- [75] M.H — رصيد بداية المدة: 950.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-00075'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-00075 (M.H)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-00075] M.H — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      950.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-00075] M.H — رصيد: 950.00 ج.م';
  END IF;
END $$;

-- [855] مستر bubles — رصيد بداية المدة: 500.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-00855'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-00855 (مستر bubles)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-00855] مستر bubles — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      500.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-00855] مستر bubles — رصيد: 500.00 ج.م';
  END IF;
END $$;

-- [928] مغسلة النجم — رصيد بداية المدة: 2,000.00 ج.م
DO $$
DECLARE
  v_customer_id UUID;
  v_admin_id    UUID;
BEGIN
  -- البحث عن العميل بالكود المعتمد في النظام
  SELECT id INTO v_customer_id
  FROM customers
  WHERE code = 'CUS-00928'
  LIMIT 1;

  -- البحث عن أول مستخدم owner/admin
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
    AND ur.is_active = true
  ORDER BY p.created_at LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE WARNING '⚠️ عميل غير موجود: كود = CUS-00928 (مغسلة النجم)';
  ELSIF v_admin_id IS NULL THEN
    RAISE WARNING '⚠️ لا يوجد مستخدم super_admin/ceo';
  ELSIF COALESCE((SELECT opening_balance FROM customers WHERE id = v_customer_id), 0) > 0 THEN
    RAISE NOTICE '⏭️  تجاوز [CUS-00928] مغسلة النجم — رصيد افتتاحي موجود بالفعل';
  ELSE
    -- الدالة الرسمية: تضبط context + تُنشئ ledger + journal + audit
    PERFORM adjust_customer_opening_balance(
      v_customer_id,
      2000.0,
      'رصيد بداية المدة — جرد 31 مارس 2026',
      v_admin_id
    );
    RAISE NOTICE '✅ [CUS-00928] مغسلة النجم — رصيد: 2,000.00 ج.م';
  END IF;
END $$;

COMMIT;

-- ════════════════════════════════════════════════════════════════════
-- للتحقق من نتائج الحقن:
-- SELECT c.code, c.name, c.opening_balance, c.current_balance
-- FROM customers c
-- WHERE c.opening_balance > 0
-- ORDER BY c.opening_balance DESC;
--
-- للتحقق من customer_ledger (يجب أن يكون source_type = 'adjustment'):
-- SELECT c.code, c.name, cl.amount, cl.type, cl.source_type, cl.description
-- FROM customer_ledger cl
-- JOIN customers c ON c.id = cl.customer_id
-- WHERE cl.description LIKE '%31 مارس 2026%'
-- ORDER BY cl.amount DESC;
--
-- للتحقق من audit trail:
-- SELECT c.code, a.old_opening_balance, a.new_opening_balance, a.delta, a.changed_at
-- FROM customer_opening_balance_audit a
-- JOIN customers c ON c.id = a.customer_id
-- ORDER BY a.changed_at;
-- ════════════════════════════════════════════════════════════════════
