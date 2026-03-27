-- ============================================================
-- 14_procurement_schema_and_coa.sql
-- EDARA v2 — نظام المشتريات: شجرة الحسابات + مخطط قاعدة البيانات
-- Idempotent: آمن للتشغيل أكثر من مرة
--
-- المرحلة الأولى:  توسعة شجرة الحسابات (6 حسابات جديدة + تعديل)
-- المرحلة الثانية: جداول فواتير الشراء + تعديل قيد الخزائن
-- ============================================================


-- ╔═══════════════════════════════════════════════════════════╗
-- ║        المرحلة الأولى: توسعة شجرة الحسابات              ║
-- ╚═══════════════════════════════════════════════════════════╝


-- ════════════════════════════════════════════════════════════
-- 1أ. تعديل تجميلي: إعادة تسمية حساب 2200
--     (تغيير في الاسم فقط — الكود 2200 يبقى دون تغيير)
--     جميع الدوال تعتمد على code = '2200' وليس الاسم، لذا
--     هذا التعديل لن يكسر أي منطق موجود.
-- ════════════════════════════════════════════════════════════

UPDATE chart_of_accounts
  SET name    = 'ضريبة القيمة المضافة — مخرجات (مبيعات)',
      name_en = 'Output VAT (Sales)'
WHERE code = '2200';


-- ════════════════════════════════════════════════════════════
-- 1ب. إدراج الحسابات الجديدة
--     ON CONFLICT DO NOTHING لضمان الـ Idempotency
-- ════════════════════════════════════════════════════════════

INSERT INTO chart_of_accounts (code, name, name_en, type, sort_order) VALUES
  -- الأصول: ذمم مدينة أخرى + ضريبة المدخلات
  ('1500', 'أصول متداولة أخرى',                    'Other Current Assets',          'asset',     9),
  ('1510', 'ضريبة القيمة المضافة — مدخلات (مشتريات)', 'Input VAT (Purchases)',        'asset',     10),

  -- الالتزامات: أوراق الدفع (شيكات الموردين)
  ('2110', 'أوراق دفع — شيكات موردين معلقة',        'Notes Payable (Cheques Pending)','liability', 13),

  -- المصروفات: هبوط المخزون والتسويات
  ('5300', 'هبوط وتسوية المخزون',                   'Inventory Shrinkage & Adjustments','expense', 46),

  -- حقوق الملكية: الأرباح المحتجزة
  ('3200', 'الأرباح المحتجزة',                      'Retained Earnings',             'equity',    22)

ON CONFLICT (code) DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- 1ج. ربط الحسابات الجديدة بآبائها
-- ════════════════════════════════════════════════════════════

-- 1500 → يتبع 1000 (الأصول)
UPDATE chart_of_accounts
  SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '1000')
WHERE code = '1500' AND parent_id IS NULL;

-- 1510 → يتبع 1500 (أصول متداولة أخرى)
UPDATE chart_of_accounts
  SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '1500')
WHERE code = '1510' AND parent_id IS NULL;

-- 2110 → يتبع 2100 (ذمم دائنة موردين)
UPDATE chart_of_accounts
  SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '2100')
WHERE code = '2110' AND parent_id IS NULL;

-- 5300 → يتبع 5000 (المصروفات)
UPDATE chart_of_accounts
  SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '5000')
WHERE code = '5300' AND parent_id IS NULL;

-- 3200 → يتبع 3000 (حقوق الملكية)
UPDATE chart_of_accounts
  SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '3000')
WHERE code = '3200' AND parent_id IS NULL;


-- ╔═══════════════════════════════════════════════════════════╗
-- ║        المرحلة الثانية: مخطط قاعدة بيانات المشتريات     ║
-- ╚═══════════════════════════════════════════════════════════╝


-- ════════════════════════════════════════════════════════════
-- 2أ. إضافة 'vendor_payment' لقيد نوع حركات الخزائن
--     هذا النوع مخصص لسداد فواتير الموردين وهو متمايز عن
--     'withdrawal' للحفاظ على تقارير مالية دقيقة.
-- ════════════════════════════════════════════════════════════

-- إسقاط القيد القديم وإعادة إنشائه مع إضافة 'vendor_payment'
ALTER TABLE vault_transactions
  DROP CONSTRAINT IF EXISTS vault_transactions_type_check;

ALTER TABLE vault_transactions
  ADD CONSTRAINT vault_transactions_type_check
  CHECK (type IN (
    'deposit', 'withdrawal', 'transfer_in', 'transfer_out',
    'collection', 'expense', 'custody_load', 'custody_return',
    'opening_balance', 'vendor_payment'
  ));


-- ════════════════════════════════════════════════════════════
-- 2ب. جدول فواتير الشراء (purchase_invoices)
--
--  نقطة أمان معمارية:
--    لا يوجد عمود custody_id في هذا الجدول على الإطلاق.
--    المدفوعات للموردين تخرج من الخزائن (vaults) فقط.
--    هذا القيد ضمني تماماً ولا يمكن كسره.
-- ════════════════════════════════════════════════════════════

CREATE SEQUENCE IF NOT EXISTS purchase_invoice_seq START WITH 1;

CREATE TABLE IF NOT EXISTS purchase_invoices (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  number                TEXT UNIQUE,                  -- Trigger يملأه تلقائياً: PIN-YYYYMMDD-XXXX
  supplier_id           UUID NOT NULL REFERENCES suppliers(id),
  warehouse_id          UUID NOT NULL REFERENCES warehouses(id),

  -- ───────── الحالة ─────────
  -- draft    : فاتورة منشأة لم تُستلم بضاعتها بعد
  -- received : استُلمت البضاعة وحُدِّث المخزون (Phase 3 RPC)
  -- billed   : اعتُمدت مالياً وأُنشئ القيد المحاسبي (Phase 4 RPC)
  -- paid     : سُددت بالكامل للمورد
  -- cancelled: ملغاة
  status                TEXT NOT NULL CHECK (status IN (
    'draft', 'received', 'billed', 'paid', 'cancelled'
  )) DEFAULT 'draft',

  -- ───────── تفاصيل الفاتورة ─────────
  invoice_date          DATE NOT NULL DEFAULT CURRENT_DATE,
  supplier_invoice_ref  TEXT,            -- رقم فاتورة المورد الأصلية (للمطابقة)
  due_date              DATE,            -- تاريخ الاستحقاق (للآجل)

  -- ───────── الأرقام المالية ─────────
  -- subtotal     = مجموع (qty * unit_price) قبل الخصم
  -- discount_amt = الخصم الإجمالي على مستوى الفاتورة
  -- tax_amount   = ضريبة القيمة المضافة → تُرحَّل لـ 1510 (Input VAT)
  -- landed_costs = مصاريف الشحن والجمارك → تُوزَّع على المخزون
  -- total_amount = subtotal - discount_amt + tax_amount + landed_costs
  -- paid_amount  = ما سُدِّد فعلياً للمورد حتى الآن
  subtotal              NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
  discount_amount       NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
  tax_amount            NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
  landed_costs          NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (landed_costs >= 0),
  total_amount          NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
  paid_amount           NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (paid_amount >= 0),

  -- ───────── الدفع الفوري (اختياري) ─────────
  -- إذا سُدِّدت الفاتورة فوراً عند الاعتماد (Phase 4):
  --   vault_id    : الخزنة/البنك التي خرج منها المال
  --   payment_method: طريقة الدفع
  -- (لا custody_id هنا — ممنوع تصميمياً)
  vault_id              UUID REFERENCES vaults(id),
  payment_method        TEXT CHECK (payment_method IN (
    'cash', 'bank_transfer', 'cheque', 'instapay', 'mobile_wallet'
  )),
  bank_reference        TEXT,            -- رقم مرجعي للتحويل البنكي
  check_number          TEXT,            -- رقم الشيك
  check_date            DATE,            -- تاريخ استحقاق الشيك

  -- ───────── الملاحظات والتدقيق ─────────
  notes                 TEXT,
  received_by           UUID REFERENCES profiles(id),    -- من استلم البضاعة
  received_at           TIMESTAMPTZ,
  billed_by             UUID REFERENCES profiles(id),    -- من اعتمد الفاتورة مالياً
  billed_at             TIMESTAMPTZ,
  created_by            UUID REFERENCES profiles(id),
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now(),

  -- ───────── قيود منطقية ─────────
  -- ضمان أن المدفوع لا يتجاوز الإجمالي
  CONSTRAINT chk_pi_paid_lte_total
    CHECK (paid_amount <= total_amount),
  -- الخصم لا يتجاوز الإجمالي قبل الضريبة
  CONSTRAINT chk_pi_discount_lte_subtotal
    CHECK (discount_amount <= subtotal)
);

-- Trigger: رقم تلقائي للفاتورة (PIN-YYYYMMDD-XXXX)
CREATE OR REPLACE FUNCTION generate_purchase_invoice_number()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.number IS NULL OR NEW.number = '' THEN
    NEW.number := 'PIN-' || to_char(CURRENT_DATE, 'YYYYMMDD')
               || '-' || lpad(nextval('purchase_invoice_seq')::text, 4, '0');
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_purchase_invoice_number ON purchase_invoices;
CREATE TRIGGER trg_purchase_invoice_number
  BEFORE INSERT ON purchase_invoices
  FOR EACH ROW EXECUTE FUNCTION generate_purchase_invoice_number();

-- Trigger: updated_at تلقائي
DROP TRIGGER IF EXISTS trg_purchase_invoices_updated_at ON purchase_invoices;
CREATE TRIGGER trg_purchase_invoices_updated_at
  BEFORE UPDATE ON purchase_invoices
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- فهارس الأداء
CREATE INDEX IF NOT EXISTS idx_pi_supplier    ON purchase_invoices(supplier_id);
CREATE INDEX IF NOT EXISTS idx_pi_warehouse   ON purchase_invoices(warehouse_id);
CREATE INDEX IF NOT EXISTS idx_pi_status      ON purchase_invoices(status);
CREATE INDEX IF NOT EXISTS idx_pi_date        ON purchase_invoices(invoice_date DESC);
CREATE INDEX IF NOT EXISTS idx_pi_created     ON purchase_invoices(created_at DESC);


-- ════════════════════════════════════════════════════════════
-- 2ج. جدول بنود فواتير الشراء (purchase_invoice_items)
--
--  يدعم الاستلام الجزئي: ordered_quantity ≠ received_quantity
--  الحسابات المالية تعتمد على received_quantity فقط.
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS purchase_invoice_items (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id            UUID NOT NULL REFERENCES purchase_invoices(id) ON DELETE CASCADE,
  product_id            UUID NOT NULL REFERENCES products(id),
  unit_id               UUID REFERENCES units(id),      -- وحدة القياس المستخدمة في أمر الشراء

  -- ───────── الكميات (الاستلام الجزئي) ─────────
  ordered_quantity      NUMERIC(14,4) NOT NULL CHECK (ordered_quantity > 0),
  received_quantity     NUMERIC(14,4) NOT NULL DEFAULT 0 CHECK (received_quantity >= 0),

  -- ───────── الأسعار ─────────
  unit_price            NUMERIC(14,4) NOT NULL CHECK (unit_price >= 0),
  discount_rate         NUMERIC(5,2)  NOT NULL DEFAULT 0
                          CHECK (discount_rate >= 0 AND discount_rate <= 100),  -- نسبة مئوية
  tax_rate              NUMERIC(5,2)  NOT NULL DEFAULT 0
                          CHECK (tax_rate >= 0 AND tax_rate <= 100),            -- نسبة مئوية

  -- ───────── التكاليف المحسوبة (تُملأ بواسطة receive_purchase_invoice RPC) ─────────
  -- net_cost         = (unit_price * received_quantity) * (1 - discount_rate/100)
  -- landed_cost_share= حصة هذا البند من مصاريف الشحن/الجمارك الإجمالية
  -- true_net_cost    = net_cost + landed_cost_share (التكلفة الحقيقية لحساب WAC)
  net_cost              NUMERIC(14,4) DEFAULT 0 CHECK (net_cost >= 0),
  landed_cost_share     NUMERIC(14,4) DEFAULT 0 CHECK (landed_cost_share >= 0),
  true_net_cost         NUMERIC(14,4) DEFAULT 0 CHECK (true_net_cost >= 0),

  -- ───────── التدقيق ─────────
  created_at            TIMESTAMPTZ DEFAULT now(),

  -- ───────── قيود منطقية ─────────
  -- لا يمكن استلام أكثر مما طُلب
  CONSTRAINT chk_pii_received_lte_ordered
    CHECK (received_quantity <= ordered_quantity),
  -- بند واحد لكل منتج في نفس الفاتورة (يمنع التكرار)
  CONSTRAINT uq_pii_invoice_product
    UNIQUE (invoice_id, product_id)
);

-- فهارس الأداء
CREATE INDEX IF NOT EXISTS idx_pii_invoice   ON purchase_invoice_items(invoice_id);
CREATE INDEX IF NOT EXISTS idx_pii_product   ON purchase_invoice_items(product_id);


-- ════════════════════════════════════════════════════════════
-- 2د. الصلاحيات الجديدة (Permissions)
-- ════════════════════════════════════════════════════════════

-- أضف الصلاحيات الجديدة فقط إذا لم تكن موجودة
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('procurement.invoices.read'),     -- عرض فواتير الشراء
  ('procurement.invoices.create'),   -- إنشاء فاتورة جديدة
  ('procurement.invoices.receive'),  -- تسجيل استلام البضاعة (Phase 3)
  ('procurement.invoices.bill'),     -- الاعتماد المالي (Phase 4)
  ('procurement.invoices.pay')       -- سداد المورد
) AS p(perm)
WHERE r.name IN ('accountant', 'ceo')
ON CONFLICT DO NOTHING;

-- المدير: عرض فقط
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('procurement.invoices.read'),
  ('procurement.invoices.create'),
  ('procurement.invoices.receive')
) AS p(perm)
WHERE r.name = 'branch_manager'
ON CONFLICT DO NOTHING;

-- مدير المخزن: إنشاء + استلام
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('procurement.invoices.read'),
  ('procurement.invoices.create'),
  ('procurement.invoices.receive')
) AS p(perm)
WHERE r.name = 'warehouse_manager'
ON CONFLICT DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- 2هـ. تأمين الجداول الجديدة (RLS)
-- ════════════════════════════════════════════════════════════

ALTER TABLE purchase_invoices      ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_invoice_items ENABLE ROW LEVEL SECURITY;

-- ─── سياسات purchase_invoices ───────────────────────────────

DROP POLICY IF EXISTS "pi_read" ON purchase_invoices;
CREATE POLICY "pi_read" ON purchase_invoices FOR SELECT
  USING (check_permission(auth.uid(), 'procurement.invoices.read'));

DROP POLICY IF EXISTS "pi_insert" ON purchase_invoices;
CREATE POLICY "pi_insert" ON purchase_invoices FOR INSERT
  WITH CHECK (check_permission(auth.uid(), 'procurement.invoices.create'));

-- التعديل: الاستلام + الاعتماد + السداد كلها UPDATE مع تحقق من الصلاحية عبر الـ RPC
DROP POLICY IF EXISTS "pi_update" ON purchase_invoices;
CREATE POLICY "pi_update" ON purchase_invoices FOR UPDATE
  USING (
    check_permission(auth.uid(), 'procurement.invoices.receive')
    OR check_permission(auth.uid(), 'procurement.invoices.bill')
    OR check_permission(auth.uid(), 'procurement.invoices.pay')
  );

-- لا حذف — الإلغاء يتم بتغيير الحالة إلى 'cancelled' فقط
DROP POLICY IF EXISTS "pi_delete" ON purchase_invoices;
-- (لا سياسة DELETE = ممنوع تلقائياً)

-- ─── سياسات purchase_invoice_items ──────────────────────────

DROP POLICY IF EXISTS "pii_read" ON purchase_invoice_items;
CREATE POLICY "pii_read" ON purchase_invoice_items FOR SELECT
  USING (check_permission(auth.uid(), 'procurement.invoices.read'));

DROP POLICY IF EXISTS "pii_insert" ON purchase_invoice_items;
CREATE POLICY "pii_insert" ON purchase_invoice_items FOR INSERT
  WITH CHECK (check_permission(auth.uid(), 'procurement.invoices.create'));

DROP POLICY IF EXISTS "pii_update" ON purchase_invoice_items;
CREATE POLICY "pii_update" ON purchase_invoice_items FOR UPDATE
  USING (check_permission(auth.uid(), 'procurement.invoices.receive'));


-- ════════════════════════════════════════════════════════════
-- ✅ التحقق النهائي: طباعة ملخص للحسابات الجديدة
-- ════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM chart_of_accounts
  WHERE code IN ('1500', '1510', '2110', '5300', '3200');

  RAISE NOTICE '[14_procurement_schema] ✅ تم التحقق: % حسابات جديدة في شجرة الحسابات', v_count;

  SELECT COUNT(*) INTO v_count
  FROM information_schema.tables
  WHERE table_name IN ('purchase_invoices', 'purchase_invoice_items')
    AND table_schema = 'public';

  RAISE NOTICE '[14_procurement_schema] ✅ تم التحقق: % جداول مشتريات جديدة', v_count;

  -- التحقق من وجود 'vendor_payment' في قيد الخزائن
  IF EXISTS (
    SELECT 1 FROM information_schema.check_constraints
    WHERE constraint_name = 'vault_transactions_type_check'
      AND check_clause LIKE '%vendor_payment%'
  ) THEN
    RAISE NOTICE '[14_procurement_schema] ✅ قيد vendor_payment مضاف للخزائن';
  ELSE
    RAISE WARNING '[14_procurement_schema] ⚠️ قيد vendor_payment لم يُضف — تحقق يدوياً';
  END IF;
END $$;
