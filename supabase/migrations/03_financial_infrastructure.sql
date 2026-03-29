-- ============================================================
-- 03_financial_infrastructure.sql
-- EDARA v2 — البنية المالية (الاعتماديات)
-- Idempotent: آمن للتشغيل أكثر من مرة
--
-- الجزء 1: الجداول + Views + الفهارس + التخزين + الصلاحيات + RLS
-- الجزء 2: الدوال الذرية (في نفس الملف)
-- ============================================================

-- ╔═══════════════════════════════════════════════════════════╗
-- ║                  الجزء 1: الجداول والبنية                 ║
-- ╚═══════════════════════════════════════════════════════════╝


-- ════════════════════════════════════════════════════════════
-- 1. شجرة الحسابات (Chart of Accounts)
--    أساس القيود المحاسبية — تمثل الحسابات المحاسبية المصرية
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS chart_of_accounts (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        TEXT UNIQUE NOT NULL,                    -- كود الحساب: '1100', '4100', ...
  name        TEXT NOT NULL,
  name_en     TEXT,
  type        TEXT NOT NULL CHECK (type IN ('asset', 'liability', 'equity', 'revenue', 'expense')),
  parent_id   UUID REFERENCES chart_of_accounts(id),   -- هرمي
  is_active   BOOLEAN DEFAULT true,
  sort_order  INTEGER DEFAULT 0,
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- Seed: الحسابات الأساسية المصرية
INSERT INTO chart_of_accounts (code, name, name_en, type, sort_order) VALUES
  ('1000', 'الأصول',                  'Assets',              'asset',     1),
  ('1100', 'النقدية والبنوك',         'Cash & Banks',        'asset',     2),
  ('1110', 'صندوق نقدي',              'Cash Box',            'asset',     3),
  ('1120', 'بنك',                     'Bank Account',        'asset',     4),
  ('1130', 'محفظة إلكترونية',         'Mobile Wallet',       'asset',     5),
  ('1200', 'ذمم مدينة (عملاء)',       'Accounts Receivable', 'asset',     6),
  ('1300', 'المخزون',                 'Inventory',           'asset',     7),
  ('1400', 'العُهد',                  'Custody Accounts',    'asset',     8),
  ('2000', 'الالتزامات',              'Liabilities',         'liability', 10),
  ('2100', 'ذمم دائنة (موردين)',      'Accounts Payable',    'liability', 11),
  ('2200', 'ضريبة القيمة المضافة',     'VAT Payable',         'liability', 12),
  ('3000', 'حقوق الملكية',            'Equity',              'equity',    20),
  ('3100', 'رأس المال',               'Capital',             'equity',    21),
  ('4000', 'الإيرادات',               'Revenue',             'revenue',   30),
  ('4100', 'إيرادات مبيعات',          'Sales Revenue',       'revenue',   31),
  ('4200', 'مرتجعات مبيعات',          'Sales Returns',       'revenue',   32),
  ('4300', 'خصومات مبيعات',           'Sales Discounts',     'revenue',   33),
  ('5000', 'المصروفات',               'Expenses',            'expense',   40),
  ('5100', 'تكلفة البضاعة المباعة',   'COGS',                'expense',   41),
  ('5200', 'مصروفات تشغيلية',         'Operating Expenses',  'expense',   42),
  ('5210', 'مصروفات نقل وتوزيع',      'Transport Expenses',  'expense',   43),
  ('5220', 'مصروفات إدارية',          'Admin Expenses',      'expense',   44),
  ('5230', 'مصروفات تسويقية',         'Marketing Expenses',  'expense',   45)
ON CONFLICT (code) DO NOTHING;

-- ربط الأبناء بالآباء
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '1000')
WHERE code IN ('1100','1200','1300','1400') AND parent_id IS NULL;
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '1100')
WHERE code IN ('1110','1120','1130') AND parent_id IS NULL;
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '2000')
WHERE code IN ('2100','2200') AND parent_id IS NULL;
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '3000')
WHERE code IN ('3100') AND parent_id IS NULL;
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '4000')
WHERE code IN ('4100','4200','4300') AND parent_id IS NULL;
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '5000')
WHERE code IN ('5100','5200') AND parent_id IS NULL;
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '5200')
WHERE code IN ('5210','5220','5230') AND parent_id IS NULL;


-- ════════════════════════════════════════════════════════════
-- 2. دفتر حسابات العملاء (Customer Ledger)
--    المبدأ: لا نُخزّن current_balance — الرصيد يُحسب من الحركات
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS customer_ledger (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id    UUID NOT NULL REFERENCES customers(id),
  type           TEXT NOT NULL CHECK (type IN ('debit', 'credit')),
  amount         NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  source_type    TEXT NOT NULL CHECK (source_type IN (
    'sales_order', 'sales_return', 'payment', 'opening_balance', 'adjustment'
  )),
  source_id      UUID,
  description    TEXT,
  created_by     UUID REFERENCES profiles(id),
  created_at     TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cust_ledger_customer  ON customer_ledger(customer_id);
CREATE INDEX IF NOT EXISTS idx_cust_ledger_source    ON customer_ledger(source_type, source_id);
CREATE INDEX IF NOT EXISTS idx_cust_ledger_date      ON customer_ledger(created_at DESC);

-- قيد فريد: يمنع تكرار نفس المصدر (idempotency)
ALTER TABLE customer_ledger DROP CONSTRAINT IF EXISTS uq_cust_ledger_source;
ALTER TABLE customer_ledger ADD CONSTRAINT uq_cust_ledger_source
  UNIQUE (source_type, source_id);

-- View: أرصدة العملاء (رصيد موجب = العميل مدين لنا)
CREATE OR REPLACE VIEW v_customer_balances AS
SELECT
  customer_id,
  SUM(CASE WHEN type = 'debit' THEN amount ELSE -amount END) AS balance,
  COUNT(*) AS transaction_count,
  MAX(created_at) AS last_transaction_at
FROM customer_ledger
GROUP BY customer_id;


-- ════════════════════════════════════════════════════════════
-- 3. دفتر حسابات الموردين (Supplier Ledger)
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS supplier_ledger (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id    UUID NOT NULL REFERENCES suppliers(id),
  type           TEXT NOT NULL CHECK (type IN ('debit', 'credit')),
  amount         NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  source_type    TEXT NOT NULL CHECK (source_type IN (
    'purchase_order', 'purchase_return', 'payment', 'opening_balance', 'adjustment'
  )),
  source_id      UUID,
  description    TEXT,
  created_by     UUID REFERENCES profiles(id),
  created_at     TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_supp_ledger_supplier  ON supplier_ledger(supplier_id);
CREATE INDEX IF NOT EXISTS idx_supp_ledger_source    ON supplier_ledger(source_type, source_id);
CREATE INDEX IF NOT EXISTS idx_supp_ledger_date      ON supplier_ledger(created_at DESC);

-- قيد فريد: يمنع تكرار نفس المصدر (idempotency)
ALTER TABLE supplier_ledger DROP CONSTRAINT IF EXISTS uq_supp_ledger_source;
ALTER TABLE supplier_ledger ADD CONSTRAINT uq_supp_ledger_source
  UNIQUE (source_type, source_id);

-- View: أرصدة الموردين (رصيد موجب = نحن مدينون للمورد)
CREATE OR REPLACE VIEW v_supplier_balances AS
SELECT
  supplier_id,
  SUM(CASE WHEN type = 'credit' THEN amount ELSE -amount END) AS balance,
  COUNT(*) AS transaction_count,
  MAX(created_at) AS last_transaction_at
FROM supplier_ledger
GROUP BY supplier_id;


-- ════════════════════════════════════════════════════════════
-- 4. الخزائن (Vaults)
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS vaults (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name              TEXT NOT NULL,
  type              TEXT NOT NULL CHECK (type IN ('cash', 'bank', 'mobile_wallet')),
  account_number    TEXT,                                  -- رقم الحساب البنكي
  bank_name         TEXT,                                  -- اسم البنك
  responsible_id    UUID REFERENCES profiles(id),          -- المسؤول عن الخزنة
  branch_id         UUID REFERENCES branches(id),
  current_balance   NUMERIC(14,2) NOT NULL DEFAULT 0,      -- cached من الحركات
  is_active         BOOLEAN DEFAULT true,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_vaults_updated_at ON vaults;
CREATE TRIGGER trg_vaults_updated_at
  BEFORE UPDATE ON vaults
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS vault_transactions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vault_id          UUID NOT NULL REFERENCES vaults(id),
  type              TEXT NOT NULL CHECK (type IN (
    'deposit', 'withdrawal', 'transfer_in', 'transfer_out',
    'collection', 'expense', 'custody_load', 'custody_return',
    'opening_balance'
  )),
  amount            NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  balance_after     NUMERIC(14,2) NOT NULL,                -- الرصيد بعد العملية
  reference_type    TEXT,                                  -- 'sales_order' | 'payment_receipt' | 'expense' | ...
  reference_id      UUID,
  description       TEXT,
  created_by        UUID REFERENCES profiles(id),
  created_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_vault_txn_vault     ON vault_transactions(vault_id);
CREATE INDEX IF NOT EXISTS idx_vault_txn_date      ON vault_transactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_vault_txn_ref       ON vault_transactions(reference_type, reference_id);


-- ════════════════════════════════════════════════════════════
-- 5. العُهد (Custody Accounts)
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS custody_accounts (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id       UUID UNIQUE NOT NULL REFERENCES profiles(id),  -- كل موظف عهدة واحدة
  max_balance       NUMERIC(14,2) DEFAULT 50000,                   -- الحد الأقصى
  current_balance   NUMERIC(14,2) NOT NULL DEFAULT 0,              -- cached
  is_active         BOOLEAN DEFAULT true,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_custody_updated_at ON custody_accounts;
CREATE TRIGGER trg_custody_updated_at
  BEFORE UPDATE ON custody_accounts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS custody_transactions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  custody_id        UUID NOT NULL REFERENCES custody_accounts(id),
  type              TEXT NOT NULL CHECK (type IN (
    'load', 'collection', 'expense', 'settlement', 'return'
  )),
  amount            NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  balance_after     NUMERIC(14,2) NOT NULL,
  vault_id          UUID REFERENCES vaults(id),            -- مصدر/وجهة التحميل/التسوية
  reference_type    TEXT,
  reference_id      UUID,
  description       TEXT,
  created_by        UUID REFERENCES profiles(id),
  created_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_custody_txn_custody  ON custody_transactions(custody_id);
CREATE INDEX IF NOT EXISTS idx_custody_txn_date     ON custody_transactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_custody_txn_ref      ON custody_transactions(reference_type, reference_id);


-- ════════════════════════════════════════════════════════════
-- 6. إيصالات الدفع (Payment Receipts)
-- ════════════════════════════════════════════════════════════

CREATE SEQUENCE IF NOT EXISTS payment_receipt_seq START WITH 1;

CREATE TABLE IF NOT EXISTS payment_receipts (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  number            TEXT UNIQUE,  -- Trigger يملأه تلقائياً
  customer_id       UUID NOT NULL REFERENCES customers(id),
  amount            NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  payment_method    TEXT NOT NULL CHECK (payment_method IN (
    'cash', 'bank_transfer', 'instapay', 'check', 'mobile_wallet'
  )),
  status            TEXT NOT NULL CHECK (status IN ('pending', 'confirmed', 'rejected')) DEFAULT 'pending',
  vault_id          UUID REFERENCES vaults(id),               -- الخزنة المُستلمة (عند التأكيد)
  custody_id        UUID REFERENCES custody_accounts(id),     -- أو العهدة (للنقدي الميداني)
  branch_id         UUID REFERENCES branches(id),             -- F3: الفرع للتقارير
  proof_url         TEXT,                                     -- صورة إثبات الدفع
  bank_reference    TEXT,                                     -- رقم مرجعي بنكي
  check_number      TEXT,                                     -- رقم الشيك
  check_date        DATE,                                     -- تاريخ استحقاق الشيك
  notes             TEXT,
  collected_by      UUID REFERENCES profiles(id),             -- من حصّل
  reviewed_by       UUID REFERENCES profiles(id),             -- من راجع
  reviewed_at       TIMESTAMPTZ,
  rejection_reason  TEXT,
  created_by        UUID REFERENCES profiles(id),
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_receipts_updated_at ON payment_receipts;
CREATE TRIGGER trg_receipts_updated_at
  BEFORE UPDATE ON payment_receipts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS idx_receipts_customer  ON payment_receipts(customer_id);
CREATE INDEX IF NOT EXISTS idx_receipts_status    ON payment_receipts(status);
CREATE INDEX IF NOT EXISTS idx_receipts_date      ON payment_receipts(created_at DESC);

CREATE OR REPLACE FUNCTION generate_receipt_number()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.number IS NULL OR NEW.number = '' THEN
    NEW.number := 'REC-' || to_char(CURRENT_DATE, 'YYYYMMDD') || '-' || lpad(nextval('payment_receipt_seq')::text, 4, '0');
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_receipt_auto_number ON payment_receipts;
CREATE TRIGGER trg_receipt_auto_number
  BEFORE INSERT ON payment_receipts
  FOR EACH ROW EXECUTE FUNCTION generate_receipt_number();


-- ════════════════════════════════════════════════════════════
-- 7. المصروفات (Expenses)
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS expense_categories (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL UNIQUE,                      -- F1: فريد لمنع التكرار
  parent_id   UUID REFERENCES expense_categories(id),    -- هرمي
  is_active   BOOLEAN DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- Seed: تصنيفات المصروفات الأساسية
INSERT INTO expense_categories (name) VALUES
  ('مصروفات نقل وتوزيع'),
  ('مصروفات إدارية'),
  ('مصروفات تسويقية'),
  ('صيانة ونظافة'),
  ('مرافق (كهرباء / مياه / غاز)'),
  ('مستلزمات مكتبية'),
  ('بنزين ووقود'),
  ('ضيافة'),
  ('أخرى')
ON CONFLICT (name) DO NOTHING;

CREATE SEQUENCE IF NOT EXISTS expense_seq START WITH 1;

CREATE TABLE IF NOT EXISTS expenses (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  number            TEXT UNIQUE,  -- Trigger يملأه تلقائياً
  category_id       UUID REFERENCES expense_categories(id),
  amount            NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  description       TEXT NOT NULL,
  expense_date      DATE DEFAULT CURRENT_DATE,
  status            TEXT NOT NULL CHECK (status IN (
    'draft', 'pending_approval', 'approved', 'rejected'
  )) DEFAULT 'draft',
  payment_source    TEXT CHECK (payment_source IN ('vault', 'custody')),
  vault_id          UUID REFERENCES vaults(id),
  custody_id        UUID REFERENCES custody_accounts(id),
  receipt_url       TEXT,                                     -- صورة الفاتورة/الإيصال
  branch_id         UUID REFERENCES branches(id),
  approved_by       UUID REFERENCES profiles(id),
  approved_at       TIMESTAMPTZ,
  rejection_reason  TEXT,
  created_by        UUID REFERENCES profiles(id),
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_expenses_updated_at ON expenses;
CREATE TRIGGER trg_expenses_updated_at
  BEFORE UPDATE ON expenses
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS idx_expenses_status   ON expenses(status);
CREATE INDEX IF NOT EXISTS idx_expenses_date     ON expenses(expense_date DESC);
CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses(category_id);

CREATE OR REPLACE FUNCTION generate_expense_number()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.number IS NULL OR NEW.number = '' THEN
    NEW.number := 'EXP-' || to_char(CURRENT_DATE, 'YYYYMMDD') || '-' || lpad(nextval('expense_seq')::text, 4, '0');
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_expense_auto_number ON expenses;
CREATE TRIGGER trg_expense_auto_number
  BEFORE INSERT ON expenses
  FOR EACH ROW EXECUTE FUNCTION generate_expense_number();


-- ════════════════════════════════════════════════════════════
-- 8. قواعد الموافقات (Approval Rules)
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS approval_rules (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type        TEXT NOT NULL CHECK (type IN ('expense', 'purchase_order', 'sales_discount')),
  role_id     UUID NOT NULL REFERENCES roles(id),
  max_amount  NUMERIC(14,2) NOT NULL,                    -- الحد الأقصى لهذا المستوى
  sort_order  INTEGER DEFAULT 0,                         -- ترتيب المستويات (الأدنى أولاً)
  is_active   BOOLEAN DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT now(),
  UNIQUE(type, role_id)                                  -- F2: منع تكرار الدور في نفس النوع
);

-- Seed: قواعد موافقة المصروفات الافتراضية
INSERT INTO approval_rules (type, role_id, max_amount, sort_order)
SELECT 'expense', id, 2000, 1 FROM roles WHERE name = 'accountant'
ON CONFLICT (type, role_id) DO NOTHING;
INSERT INTO approval_rules (type, role_id, max_amount, sort_order)
SELECT 'expense', id, 10000, 2 FROM roles WHERE name = 'branch_manager'
ON CONFLICT (type, role_id) DO NOTHING;
INSERT INTO approval_rules (type, role_id, max_amount, sort_order)
SELECT 'expense', id, 50000, 3 FROM roles WHERE name = 'ceo'
ON CONFLICT (type, role_id) DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- 9. القيود المحاسبية (Journal Entries)
-- ════════════════════════════════════════════════════════════

CREATE SEQUENCE IF NOT EXISTS journal_entry_seq START WITH 1;

CREATE TABLE IF NOT EXISTS journal_entries (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  number          TEXT UNIQUE,  -- Trigger يملأه تلقائياً
  entry_date      DATE DEFAULT CURRENT_DATE,
  source_type     TEXT NOT NULL CHECK (source_type IN (
    'sales_order', 'sales_return', 'payment', 'purchase_order',
    'purchase_return', 'expense', 'custody', 'transfer', 'manual'
  )),
  source_id       UUID,
  description     TEXT,
  is_auto         BOOLEAN DEFAULT true,                     -- تلقائي أم يدوي
  status          TEXT NOT NULL CHECK (status IN ('draft', 'posted')) DEFAULT 'posted',
  total_debit     NUMERIC(14,2) NOT NULL DEFAULT 0,
  total_credit    NUMERIC(14,2) NOT NULL DEFAULT 0,
  created_by      UUID REFERENCES profiles(id),
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- CHECK: القيد المتوازن — مدين = دائن
ALTER TABLE journal_entries DROP CONSTRAINT IF EXISTS chk_balanced_entry;
ALTER TABLE journal_entries ADD CONSTRAINT chk_balanced_entry
  CHECK (total_debit = total_credit);

CREATE TABLE IF NOT EXISTS journal_entry_lines (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_id        UUID NOT NULL REFERENCES journal_entries(id) ON DELETE CASCADE,
  account_id      UUID NOT NULL REFERENCES chart_of_accounts(id),
  debit           NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
  credit          NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
  description     TEXT,
  -- أحد الاتجاهين فقط لكل سطر
  CONSTRAINT chk_debit_or_credit CHECK (
    (debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0)
  )
);

CREATE INDEX IF NOT EXISTS idx_je_date          ON journal_entries(entry_date DESC);
CREATE INDEX IF NOT EXISTS idx_je_source        ON journal_entries(source_type, source_id);
CREATE INDEX IF NOT EXISTS idx_je_lines_entry   ON journal_entry_lines(entry_id);

CREATE OR REPLACE FUNCTION generate_journal_number()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.number IS NULL OR NEW.number = '' THEN
    NEW.number := 'JE-' || to_char(CURRENT_DATE, 'YYYYMMDD') || '-' || lpad(nextval('journal_entry_seq')::text, 4, '0');
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_journal_auto_number ON journal_entries;
CREATE TRIGGER trg_journal_auto_number
  BEFORE INSERT ON journal_entries
  FOR EACH ROW EXECUTE FUNCTION generate_journal_number();
CREATE INDEX IF NOT EXISTS idx_je_lines_account ON journal_entry_lines(account_id);


-- ════════════════════════════════════════════════════════════
-- 10. التخزين (Storage Buckets) — إثباتات الدفع والمصروفات
-- ════════════════════════════════════════════════════════════

-- Bucket: إثباتات الدفع (صور الحوالات / InstaPay / الشيكات)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'payment-proofs',
  'payment-proofs',
  true,                                 -- عام — يُعرض بـ getPublicUrl
  5242880,                              -- 5MB حد أقصى
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
) ON CONFLICT (id) DO NOTHING;

-- Bucket: إيصالات المصروفات
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'expense-receipts',
  'expense-receipts',
  true,                                 -- عام — يُعرض بـ getPublicUrl
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
) ON CONFLICT (id) DO NOTHING;

-- سياسات التخزين — payment-proofs
DROP POLICY IF EXISTS "payment_proofs_select" ON storage.objects;
CREATE POLICY "payment_proofs_select" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'payment-proofs' AND auth.uid() IS NOT NULL
  );

DROP POLICY IF EXISTS "payment_proofs_insert" ON storage.objects;
CREATE POLICY "payment_proofs_insert" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'payment-proofs' AND auth.uid() IS NOT NULL
  );

DROP POLICY IF EXISTS "payment_proofs_update" ON storage.objects;
CREATE POLICY "payment_proofs_update" ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'payment-proofs' AND auth.uid() IS NOT NULL
  );

DROP POLICY IF EXISTS "payment_proofs_delete" ON storage.objects;
CREATE POLICY "payment_proofs_delete" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'payment-proofs'
    AND check_permission(auth.uid(), 'finance.payments.confirm')
  );

-- سياسات التخزين — expense-receipts
DROP POLICY IF EXISTS "expense_receipts_select" ON storage.objects;
CREATE POLICY "expense_receipts_select" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'expense-receipts' AND auth.uid() IS NOT NULL
  );

DROP POLICY IF EXISTS "expense_receipts_insert" ON storage.objects;
CREATE POLICY "expense_receipts_insert" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'expense-receipts' AND auth.uid() IS NOT NULL
  );

DROP POLICY IF EXISTS "expense_receipts_update" ON storage.objects;
CREATE POLICY "expense_receipts_update" ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'expense-receipts' AND auth.uid() IS NOT NULL
  );

DROP POLICY IF EXISTS "expense_receipts_delete" ON storage.objects;
CREATE POLICY "expense_receipts_delete" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'expense-receipts'
    AND check_permission(auth.uid(), 'finance.expenses.approve')
  );


-- ════════════════════════════════════════════════════════════
-- 11. الصلاحيات الجديدة
--     الصلاحيات الموجودة مسبقاً في 01_foundation:
--       finance.vaults.read, finance.vaults.create
--       finance.expenses.read, finance.expenses.approve
--       finance.payments.read, finance.payments.create
--       finance.journal.read, finance.journal.create
--     الجديد المُضاف:
-- ════════════════════════════════════════════════════════════

-- صلاحيات جديدة للمحاسب
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('finance.vaults.update'),          -- تعديل بيانات الخزنة
  ('finance.vaults.transact'),        -- إجراء حركات (إيداع/سحب)
  ('finance.custody.read'),           -- عرض العُهد
  ('finance.custody.create'),         -- إنشاء عهدة
  ('finance.custody.transact'),       -- تحميل/تسوية عهدة
  ('finance.expenses.create'),        -- إنشاء مصروف
  ('finance.payments.confirm'),       -- تأكيد/رفض إيصالات الدفع
  ('finance.ledger.read'),            -- عرض دفتر الحسابات
  ('finance.ledger.adjust')           -- تسوية يدوية للأرصدة
) AS p(perm)
WHERE r.name = 'accountant'
ON CONFLICT DO NOTHING;

-- صلاحيات المدير: عرض + موافقات
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('finance.custody.read'),
  ('finance.ledger.read'),
  ('finance.payments.confirm'),
  ('finance.vaults.transact')
) AS p(perm)
WHERE r.name = 'branch_manager'
ON CONFLICT DO NOTHING;

-- صلاحيات CEO: عرض كل شيء
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('finance.custody.read'),
  ('finance.ledger.read'),
  ('finance.payments.confirm'),
  ('finance.vaults.transact'),
  ('finance.ledger.adjust')
) AS p(perm)
WHERE r.name = 'ceo'
ON CONFLICT DO NOTHING;

-- صلاحيات المندوب: إنشاء إيصال + مصروف
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('finance.payments.create'),        -- إنشاء إيصال تحصيل
  ('finance.expenses.create')         -- إنشاء مصروف ميداني
) AS p(perm)
WHERE r.name = 'sales_rep'
ON CONFLICT DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- 12. RLS — تأمين كل الجداول الجديدة
-- ════════════════════════════════════════════════════════════

ALTER TABLE chart_of_accounts   ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_ledger     ENABLE ROW LEVEL SECURITY;
ALTER TABLE supplier_ledger     ENABLE ROW LEVEL SECURITY;
ALTER TABLE vaults              ENABLE ROW LEVEL SECURITY;
ALTER TABLE vault_transactions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE custody_accounts    ENABLE ROW LEVEL SECURITY;
ALTER TABLE custody_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_receipts    ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_categories  ENABLE ROW LEVEL SECURITY;
ALTER TABLE expenses            ENABLE ROW LEVEL SECURITY;
ALTER TABLE approval_rules      ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_entries     ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_entry_lines ENABLE ROW LEVEL SECURITY;

-- شجرة الحسابات: الكل يقرأ — المحاسب فقط يعدّل
DROP POLICY IF EXISTS "coa_read" ON chart_of_accounts;
CREATE POLICY "coa_read" ON chart_of_accounts FOR SELECT
  USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "coa_write" ON chart_of_accounts;
CREATE POLICY "coa_write" ON chart_of_accounts FOR ALL
  USING (check_permission(auth.uid(), 'finance.journal.create'));

-- دفتر العملاء
DROP POLICY IF EXISTS "cust_ledger_read" ON customer_ledger;
CREATE POLICY "cust_ledger_read" ON customer_ledger FOR SELECT
  USING (check_permission(auth.uid(), 'finance.ledger.read'));
DROP POLICY IF EXISTS "cust_ledger_write" ON customer_ledger;
CREATE POLICY "cust_ledger_write" ON customer_ledger FOR ALL
  USING (check_permission(auth.uid(), 'finance.ledger.adjust'));

-- دفتر الموردين
DROP POLICY IF EXISTS "supp_ledger_read" ON supplier_ledger;
CREATE POLICY "supp_ledger_read" ON supplier_ledger FOR SELECT
  USING (check_permission(auth.uid(), 'finance.ledger.read'));
DROP POLICY IF EXISTS "supp_ledger_write" ON supplier_ledger;
CREATE POLICY "supp_ledger_write" ON supplier_ledger FOR ALL
  USING (check_permission(auth.uid(), 'finance.ledger.adjust'));

-- الخزائن
DROP POLICY IF EXISTS "vaults_read" ON vaults;
CREATE POLICY "vaults_read" ON vaults FOR SELECT
  USING (check_permission(auth.uid(), 'finance.vaults.read'));
-- T5: فصل INSERT عن UPDATE ومنع DELETE
DROP POLICY IF EXISTS "vaults_write" ON vaults;
DROP POLICY IF EXISTS "vaults_insert" ON vaults;
CREATE POLICY "vaults_insert" ON vaults FOR INSERT
  WITH CHECK (check_permission(auth.uid(), 'finance.vaults.create'));
DROP POLICY IF EXISTS "vaults_update" ON vaults;
CREATE POLICY "vaults_update" ON vaults FOR UPDATE
  USING (check_permission(auth.uid(), 'finance.vaults.update'));

-- حركات الخزائن
DROP POLICY IF EXISTS "vault_txn_read" ON vault_transactions;
CREATE POLICY "vault_txn_read" ON vault_transactions FOR SELECT
  USING (check_permission(auth.uid(), 'finance.vaults.read'));
DROP POLICY IF EXISTS "vault_txn_write" ON vault_transactions;
CREATE POLICY "vault_txn_write" ON vault_transactions FOR ALL
  USING (check_permission(auth.uid(), 'finance.vaults.transact'));

-- العُهد
DROP POLICY IF EXISTS "custody_read" ON custody_accounts;
CREATE POLICY "custody_read" ON custody_accounts FOR SELECT
  USING (
    employee_id = auth.uid()
    OR check_permission(auth.uid(), 'finance.custody.read')
  );
DROP POLICY IF EXISTS "custody_write" ON custody_accounts;
CREATE POLICY "custody_write" ON custody_accounts FOR ALL
  USING (check_permission(auth.uid(), 'finance.custody.create'));

-- حركات العُهد
DROP POLICY IF EXISTS "custody_txn_read" ON custody_transactions;
CREATE POLICY "custody_txn_read" ON custody_transactions FOR SELECT
  USING (
    custody_id IN (SELECT id FROM custody_accounts WHERE employee_id = auth.uid())
    OR check_permission(auth.uid(), 'finance.custody.read')
  );
DROP POLICY IF EXISTS "custody_txn_write" ON custody_transactions;
CREATE POLICY "custody_txn_write" ON custody_transactions FOR ALL
  USING (check_permission(auth.uid(), 'finance.custody.transact'));

-- إيصالات الدفع
DROP POLICY IF EXISTS "receipts_read" ON payment_receipts;
CREATE POLICY "receipts_read" ON payment_receipts FOR SELECT
  USING (
    created_by = auth.uid()
    OR collected_by = auth.uid()
    OR check_permission(auth.uid(), 'finance.payments.read')
  );
DROP POLICY IF EXISTS "receipts_insert" ON payment_receipts;
CREATE POLICY "receipts_insert" ON payment_receipts FOR INSERT
  WITH CHECK (check_permission(auth.uid(), 'finance.payments.create'));
DROP POLICY IF EXISTS "receipts_update" ON payment_receipts;
CREATE POLICY "receipts_update" ON payment_receipts FOR UPDATE
  USING (check_permission(auth.uid(), 'finance.payments.confirm'));

-- تصنيفات المصروفات
DROP POLICY IF EXISTS "exp_cat_read" ON expense_categories;
CREATE POLICY "exp_cat_read" ON expense_categories FOR SELECT
  USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "exp_cat_write" ON expense_categories;
CREATE POLICY "exp_cat_write" ON expense_categories FOR ALL
  USING (check_permission(auth.uid(), 'finance.expenses.approve'));

-- المصروفات
DROP POLICY IF EXISTS "expenses_read" ON expenses;
CREATE POLICY "expenses_read" ON expenses FOR SELECT
  USING (
    created_by = auth.uid()
    OR check_permission(auth.uid(), 'finance.expenses.read')
  );
DROP POLICY IF EXISTS "expenses_insert" ON expenses;
CREATE POLICY "expenses_insert" ON expenses FOR INSERT
  WITH CHECK (check_permission(auth.uid(), 'finance.expenses.create'));
DROP POLICY IF EXISTS "expenses_update" ON expenses;
CREATE POLICY "expenses_update" ON expenses FOR UPDATE
  USING (
    (created_by = auth.uid() AND status = 'draft')
    OR check_permission(auth.uid(), 'finance.expenses.approve')
  )
  -- T3: منع تجاوز الحالة مباشرةً
  WITH CHECK (
    check_permission(auth.uid(), 'finance.expenses.approve')
    OR status IN ('draft', 'pending_approval')
  );

-- قواعد الموافقات
DROP POLICY IF EXISTS "approval_rules_read" ON approval_rules;
CREATE POLICY "approval_rules_read" ON approval_rules FOR SELECT
  USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "approval_rules_write" ON approval_rules;
CREATE POLICY "approval_rules_write" ON approval_rules FOR ALL
  USING (check_permission(auth.uid(), 'settings.update'));

-- القيود المحاسبية
DROP POLICY IF EXISTS "je_read" ON journal_entries;
CREATE POLICY "je_read" ON journal_entries FOR SELECT
  USING (check_permission(auth.uid(), 'finance.journal.read'));
DROP POLICY IF EXISTS "je_write" ON journal_entries;
CREATE POLICY "je_write" ON journal_entries FOR ALL
  USING (check_permission(auth.uid(), 'finance.journal.create'));

DROP POLICY IF EXISTS "je_lines_read" ON journal_entry_lines;
CREATE POLICY "je_lines_read" ON journal_entry_lines FOR SELECT
  USING (check_permission(auth.uid(), 'finance.journal.read'));
DROP POLICY IF EXISTS "je_lines_write" ON journal_entry_lines;
CREATE POLICY "je_lines_write" ON journal_entry_lines FOR ALL
  USING (check_permission(auth.uid(), 'finance.journal.create'));


-- ╔═══════════════════════════════════════════════════════════╗
-- ║          الجزء 2: الدوال الذرية (Atomic Functions)         ║
-- ╚═══════════════════════════════════════════════════════════╝


-- ════════════════════════════════════════════════════════════
-- دالة 1: add_vault_transaction
--   الأساس — تُستخدم من كل العمليات التي تمس الخزنة
--   تضمن: قفل الصف + فحص الرصيد + حساب balance_after
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION add_vault_transaction(
  p_vault_id      UUID,
  p_type          TEXT,
  p_amount        NUMERIC,
  p_ref_type      TEXT,
  p_ref_id        UUID,
  p_description   TEXT,
  p_user_id       UUID
) RETURNS UUID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_vault        vaults%ROWTYPE;
  v_new_balance  NUMERIC;
  v_txn_id       UUID;
BEGIN
  -- F6: فحص المبلغ
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
  END IF;

  -- 1. قفل صف الخزنة
  SELECT * INTO v_vault
  FROM vaults
  WHERE id = p_vault_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'الخزنة غير موجودة';
  END IF;

  IF NOT v_vault.is_active THEN
    RAISE EXCEPTION 'الخزنة معطلة';
  END IF;

  -- 2. حساب الرصيد الجديد حسب نوع العملية
  IF p_type IN ('deposit', 'transfer_in', 'collection', 'custody_return', 'opening_balance') THEN
    -- عمليات إيجابية (إيداع)
    v_new_balance := v_vault.current_balance + p_amount;
  ELSIF p_type IN ('withdrawal', 'transfer_out', 'expense', 'custody_load') THEN
    -- عمليات سلبية (سحب)
    IF v_vault.current_balance < p_amount THEN
      RAISE EXCEPTION 'رصيد الخزنة غير كافٍ (المتاح: %، المطلوب: %)', v_vault.current_balance, p_amount;
    END IF;
    v_new_balance := v_vault.current_balance - p_amount;
  ELSE
    RAISE EXCEPTION 'نوع حركة غير صالح: %', p_type;
  END IF;

  -- 3. إدراج الحركة
  INSERT INTO vault_transactions (
    vault_id, type, amount, balance_after,
    reference_type, reference_id, description, created_by
  ) VALUES (
    p_vault_id, p_type, p_amount, v_new_balance,
    p_ref_type, p_ref_id, p_description, p_user_id
  )
  RETURNING id INTO v_txn_id;

  -- 4. تحديث الرصيد المُخزَّن
  UPDATE vaults
  SET current_balance = v_new_balance
  WHERE id = p_vault_id;

  RETURN v_txn_id;
END; $$;


-- ════════════════════════════════════════════════════════════
-- دالة 2: add_custody_transaction
--   الأساس — تُستخدم لكل عمليات العُهد
--   تضمن: قفل الصف + فحص الرصيد/الحد الأقصى
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION add_custody_transaction(
  p_custody_id    UUID,
  p_type          TEXT,
  p_amount        NUMERIC,
  p_vault_id      UUID,       -- مصدر/وجهة (NULL إذا لم يرتبط بخزنة)
  p_ref_type      TEXT,
  p_ref_id        UUID,
  p_description   TEXT,
  p_user_id       UUID
) RETURNS UUID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_custody      custody_accounts%ROWTYPE;
  v_new_balance  NUMERIC;
  v_txn_id       UUID;
BEGIN
  -- F6: فحص المبلغ
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
  END IF;

  -- 1. قفل صف العهدة
  SELECT * INTO v_custody
  FROM custody_accounts
  WHERE id = p_custody_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'حساب العهدة غير موجود';
  END IF;

  IF NOT v_custody.is_active THEN
    RAISE EXCEPTION 'حساب العهدة معطل';
  END IF;

  -- 2. حساب الرصيد الجديد
  IF p_type IN ('load', 'collection') THEN
    -- عمليات إيجابية
    v_new_balance := v_custody.current_balance + p_amount;
    -- فحص الحد الأقصى
    IF v_new_balance > v_custody.max_balance THEN
      RAISE EXCEPTION 'تجاوز الحد الأقصى للعهدة (الحد: %، الرصيد بعد: %)', v_custody.max_balance, v_new_balance;
    END IF;
  ELSIF p_type IN ('expense', 'settlement', 'return') THEN
    -- عمليات سلبية
    IF v_custody.current_balance < p_amount THEN
      RAISE EXCEPTION 'رصيد العهدة غير كافٍ (المتاح: %، المطلوب: %)', v_custody.current_balance, p_amount;
    END IF;
    v_new_balance := v_custody.current_balance - p_amount;
  ELSE
    RAISE EXCEPTION 'نوع حركة عهدة غير صالح: %', p_type;
  END IF;

  -- 3. إدراج الحركة
  INSERT INTO custody_transactions (
    custody_id, type, amount, balance_after,
    vault_id, reference_type, reference_id, description, created_by
  ) VALUES (
    p_custody_id, p_type, p_amount, v_new_balance,
    p_vault_id, p_ref_type, p_ref_id, p_description, p_user_id
  )
  RETURNING id INTO v_txn_id;

  -- 4. تحديث الرصيد
  UPDATE custody_accounts
  SET current_balance = v_new_balance
  WHERE id = p_custody_id;

  RETURN v_txn_id;
END; $$;


-- ════════════════════════════════════════════════════════════
-- دالة 3: load_custody_from_vault
--   عملية مزدوجة: سحب من الخزنة → تحميل في العهدة
--   ذرية — كلتا العمليتين في نفس الـ transaction
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION load_custody_from_vault(
  p_custody_id  UUID,
  p_vault_id    UUID,
  p_amount      NUMERIC,
  p_user_id     UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_employee_name TEXT;
BEGIN
  -- S3: فحص الصلاحية
  IF NOT check_permission(p_user_id, 'finance.custody.transact') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تحميل العهدة';
  END IF;

  -- جلب اسم الموظف للوصف
  SELECT p.full_name INTO v_employee_name
  FROM custody_accounts ca
  JOIN profiles p ON p.id = ca.employee_id
  WHERE ca.id = p_custody_id;

  -- 1. سحب من الخزنة
  PERFORM add_vault_transaction(
    p_vault_id, 'custody_load', p_amount,
    'custody', p_custody_id,
    'تحميل عهدة — ' || COALESCE(v_employee_name, ''),
    p_user_id
  );

  -- 2. إضافة في العهدة
  PERFORM add_custody_transaction(
    p_custody_id, 'load', p_amount,
    p_vault_id, 'vault', p_vault_id,
    'تحميل من خزنة',
    p_user_id
  );

  -- S1: قيد محاسبي — DR: عُهد (1400) → CR: صندوق/بنك/محفظة
  PERFORM create_auto_journal_entry(
    'custody', p_custody_id,
    'تحميل عهدة — ' || COALESCE(v_employee_name, ''),
    '1400',                              -- عُهد
    CASE (SELECT type FROM vaults WHERE id = p_vault_id)
      WHEN 'cash' THEN '1110'
      WHEN 'bank' THEN '1120'
      WHEN 'mobile_wallet' THEN '1130'
      ELSE '1110'                          -- T2: fallback
    END,
    p_amount,
    p_user_id
  );
END; $$;


-- ════════════════════════════════════════════════════════════
-- دالة 4: settle_custody_to_vault
--   عملية مزدوجة: سحب من العهدة → إيداع في الخزنة
--   p_type: 'settlement' (جزئي) أو 'return' (كامل)
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION settle_custody_to_vault(
  p_custody_id  UUID,
  p_vault_id    UUID,
  p_amount      NUMERIC,
  p_type        TEXT,         -- 'settlement' أو 'return'
  p_user_id     UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_employee_name TEXT;
BEGIN
  -- التحقق من نوع العملية
  IF p_type NOT IN ('settlement', 'return') THEN
    RAISE EXCEPTION 'نوع التسوية يجب أن يكون settlement أو return';
  END IF;

  -- S3: فحص الصلاحية
  IF NOT check_permission(p_user_id, 'finance.custody.transact') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تسوية العهدة';
  END IF;

  -- جلب اسم الموظف
  SELECT p.full_name INTO v_employee_name
  FROM custody_accounts ca
  JOIN profiles p ON p.id = ca.employee_id
  WHERE ca.id = p_custody_id;

  -- 1. سحب من العهدة
  PERFORM add_custody_transaction(
    p_custody_id, p_type, p_amount,
    p_vault_id, 'vault', p_vault_id,
    CASE p_type
      WHEN 'settlement' THEN 'تسوية عهدة'
      WHEN 'return' THEN 'إرجاع عهدة كامل'
    END,
    p_user_id
  );

  -- 2. إيداع في الخزنة
  PERFORM add_vault_transaction(
    p_vault_id, 'custody_return', p_amount,
    'custody', p_custody_id,
    'تسوية عهدة — ' || COALESCE(v_employee_name, ''),
    p_user_id
  );

  -- S2: قيد محاسبي — DR: صندوق/بنك → CR: عُهد (1400)
  PERFORM create_auto_journal_entry(
    'custody', p_custody_id,
    CASE p_type
      WHEN 'settlement' THEN 'تسوية عهدة — '
      WHEN 'return' THEN 'إرجاع عهدة — '
    END || COALESCE(v_employee_name, ''),
    CASE (SELECT type FROM vaults WHERE id = p_vault_id)
      WHEN 'cash' THEN '1110'
      WHEN 'bank' THEN '1120'
      WHEN 'mobile_wallet' THEN '1130'
      ELSE '1110'                          -- T2: fallback
    END,
    '1400',                              -- عُهد
    p_amount,
    p_user_id
  );
END; $$;


-- ════════════════════════════════════════════════════════════
-- دالة 5: confirm_payment_receipt
--   مراجعة إيصال الدفع: تأكيد أو رفض
--   عند التأكيد: customer_ledger credit + خزنة/عهدة + قيد محاسبي
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION confirm_payment_receipt(
  p_receipt_id  UUID,
  p_action      TEXT,      -- 'confirm' أو 'reject'
  p_vault_id    UUID,      -- الخزنة (للتأكيد فقط، NULL للرفض)
  p_reason      TEXT,      -- سبب الرفض (للرفض فقط، NULL للتأكيد)
  p_user_id     UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_receipt  payment_receipts%ROWTYPE;
  v_cust_name TEXT;
BEGIN
  -- S3: فحص الصلاحية
  IF NOT check_permission(p_user_id, 'finance.payments.confirm') THEN
    RAISE EXCEPTION 'لا تملك صلاحية مراجعة إيصالات الدفع';
  END IF;

  -- 1. قفل الإيصال
  SELECT * INTO v_receipt
  FROM payment_receipts
  WHERE id = p_receipt_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'إيصال الدفع غير موجود';
  END IF;

  IF v_receipt.status != 'pending' THEN
    RAISE EXCEPTION 'الإيصال ليس في حالة معلقة (الحالة: %)', v_receipt.status;
  END IF;

  IF p_action = 'confirm' THEN
    -- التحقق من وجود وجهة التحصيل (خزنة أو عهدة)
    IF p_vault_id IS NULL AND v_receipt.custody_id IS NULL THEN
      RAISE EXCEPTION 'يجب تحديد الخزنة أو العهدة للتأكيد';
    END IF;

    -- جلب اسم العميل للأوصاف
    SELECT name INTO v_cust_name FROM customers WHERE id = v_receipt.customer_id;

    -- 2a. إدراج حركة في دفتر العميل (credit = تقليل الدين)
    INSERT INTO customer_ledger (
      customer_id, type, amount, source_type, source_id,
      description, created_by
    ) VALUES (
      v_receipt.customer_id, 'credit', v_receipt.amount,
      'payment', p_receipt_id,
      'تحصيل ' || v_receipt.payment_method || ' — ' || COALESCE(v_receipt.bank_reference, v_receipt.check_number, ''),
      p_user_id
    );

    -- F7+F8: مساران — خزنة أو عهدة
    IF v_receipt.custody_id IS NOT NULL THEN
      -- مسار العهدة (تحصيل ميداني — المندوب)
      PERFORM add_custody_transaction(
        v_receipt.custody_id, 'collection', v_receipt.amount,
        NULL, 'payment_receipt', p_receipt_id,
        'تحصيل من ' || COALESCE(v_cust_name, ''),
        p_user_id
      );

      -- قيد محاسبي: DR: عهد (1400) → CR: ذمم مدينة (1200)
      PERFORM create_auto_journal_entry(
        'payment', p_receipt_id,
        'تحصيل ميداني من عميل — ' || COALESCE(v_cust_name, ''),
        '1400',                            -- عُهد
        '1200',                            -- ذمم مدينة
        v_receipt.amount,
        p_user_id
      );

      -- تحديث الإيصال
      UPDATE payment_receipts
      SET status = 'confirmed',
          custody_id = v_receipt.custody_id,
          reviewed_by = p_user_id,
          reviewed_at = now()
      WHERE id = p_receipt_id;

    ELSE
      -- مسار الخزنة (تحصيل مكتبي)
      PERFORM add_vault_transaction(
        p_vault_id, 'collection', v_receipt.amount,
        'payment_receipt', p_receipt_id,
        'تحصيل من ' || COALESCE(v_cust_name, ''),
        p_user_id
      );

      -- قيد محاسبي: DR: صندوق/بنك → CR: ذمم مدينة
      PERFORM create_auto_journal_entry(
        'payment', p_receipt_id,
        'تحصيل من عميل — ' || COALESCE(v_cust_name, ''),
        CASE (SELECT type FROM vaults WHERE id = p_vault_id)
          WHEN 'cash' THEN '1110'         -- صندوق
          WHEN 'bank' THEN '1120'         -- بنك
          WHEN 'mobile_wallet' THEN '1130' -- محفظة
          ELSE '1110'                     -- T2: fallback
        END,
        '1200',                            -- ذمم مدينة
        v_receipt.amount,
        p_user_id
      );

      -- تحديث الإيصال
      UPDATE payment_receipts
      SET status = 'confirmed',
          vault_id = p_vault_id,
          reviewed_by = p_user_id,
          reviewed_at = now()
      WHERE id = p_receipt_id;
    END IF;

  ELSIF p_action = 'reject' THEN
    -- رفض الإيصال
    UPDATE payment_receipts
    SET status = 'rejected',
        rejection_reason = p_reason,
        reviewed_by = p_user_id,
        reviewed_at = now()
    WHERE id = p_receipt_id;

  ELSE
    RAISE EXCEPTION 'الإجراء يجب أن يكون confirm أو reject';
  END IF;
END; $$;


-- ════════════════════════════════════════════════════════════
-- دالة 6: approve_expense
--   موافقة على مصروف مع فحص سلسلة الموافقات
--   عند الموافقة: خصم من خزنة/عهدة + قيد محاسبي
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION approve_expense(
  p_expense_id  UUID,
  p_action      TEXT,      -- 'approve' أو 'reject'
  p_reason      TEXT,      -- سبب الرفض (NULL للموافقة)
  p_user_id     UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_expense     expenses%ROWTYPE;
  v_can_approve BOOLEAN;
  v_cat_name    TEXT;
BEGIN
  -- S3: فحص الصلاحية
  IF NOT check_permission(p_user_id, 'finance.expenses.approve') THEN
    RAISE EXCEPTION 'لا تملك صلاحية الموافقة على المصروفات';
  END IF;

  -- 1. قفل المصروف
  SELECT * INTO v_expense
  FROM expenses
  WHERE id = p_expense_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'المصروف غير موجود';
  END IF;

  IF v_expense.status != 'pending_approval' THEN
    RAISE EXCEPTION 'المصروف ليس في حالة انتظار الموافقة (الحالة: %)', v_expense.status;
  END IF;

  IF p_action = 'approve' THEN
    -- 2. فحص صلاحية الموافقة بناءً على سلسلة الموافقات
    SELECT EXISTS (
      SELECT 1 FROM approval_rules ar
      JOIN user_roles ur ON ur.role_id = ar.role_id
      WHERE ar.type = 'expense'
        AND ar.max_amount >= v_expense.amount
        AND ar.is_active = true
        AND ur.user_id = p_user_id
        AND ur.is_active = true
    ) INTO v_can_approve;

    IF NOT v_can_approve THEN
      RAISE EXCEPTION 'لا تملك صلاحية اعتماد مصروف بقيمة %', v_expense.amount;
    END IF;

    -- 3. خصم من المصدر
    IF v_expense.payment_source = 'vault' AND v_expense.vault_id IS NOT NULL THEN
      PERFORM add_vault_transaction(
        v_expense.vault_id, 'expense', v_expense.amount,
        'expense', p_expense_id,
        v_expense.description,
        p_user_id
      );
    ELSIF v_expense.payment_source = 'custody' AND v_expense.custody_id IS NOT NULL THEN
      PERFORM add_custody_transaction(
        v_expense.custody_id, 'expense', v_expense.amount,
        NULL, 'expense', p_expense_id,
        v_expense.description,
        p_user_id
      );
    ELSE
      RAISE EXCEPTION 'يجب تحديد مصدر الدفع (خزنة أو عهدة)';
    END IF;

    -- 4. جلب اسم التصنيف للقيد
    SELECT name INTO v_cat_name FROM expense_categories WHERE id = v_expense.category_id;

    -- 5. إنشاء قيد محاسبي تلقائي
    --    DR: مصروفات   →   CR: صندوق/بنك/عهدة
    PERFORM create_auto_journal_entry(
      'expense', p_expense_id,
      'مصروف — ' || COALESCE(v_cat_name, v_expense.description),
      '5200',                             -- مصروفات تشغيلية
      -- F10: تحديد الحساب الدائن حسب المصدر ونوع الخزنة
      CASE v_expense.payment_source
        WHEN 'custody' THEN '1400'        -- عُهد
        WHEN 'vault' THEN
          CASE (SELECT type FROM vaults WHERE id = v_expense.vault_id)
            WHEN 'cash' THEN '1110'
            WHEN 'bank' THEN '1120'
            WHEN 'mobile_wallet' THEN '1130'
            ELSE '1110'                    -- T2: fallback
          END
        ELSE '1110'                        -- U3: safety net
      END,
      v_expense.amount,
      p_user_id
    );

    -- 6. تحديث المصروف
    UPDATE expenses
    SET status = 'approved',
        approved_by = p_user_id,
        approved_at = now()
    WHERE id = p_expense_id;

  ELSIF p_action = 'reject' THEN
    UPDATE expenses
    SET status = 'rejected',
        rejection_reason = p_reason,
        approved_by = p_user_id,
        approved_at = now()
    WHERE id = p_expense_id;

  ELSE
    RAISE EXCEPTION 'الإجراء يجب أن يكون approve أو reject';
  END IF;
END; $$;


-- ════════════════════════════════════════════════════════════
-- دالة 7: create_auto_journal_entry
--   مساعد — تُنشئ قيد محاسبي بسيط (طرفين: مدين + دائن)
--   تُستدعى من الدوال الأخرى — لا تُستدعى مباشرة
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION create_auto_journal_entry(
  p_source_type   TEXT,
  p_source_id     UUID,
  p_description   TEXT,
  p_debit_account TEXT,     -- كود الحساب المدين
  p_credit_account TEXT,    -- كود الحساب الدائن
  p_amount        NUMERIC,
  p_user_id       UUID
) RETURNS UUID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_entry_id    UUID;
  v_debit_acct  UUID;
  v_credit_acct UUID;
BEGIN
  -- FIX-AUDIT-04: رفض مبالغ صفرية أو سالبة
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'create_auto_journal_entry: المبلغ يجب أن يكون أكبر من صفر (القيمة: %)', COALESCE(p_amount, 0);
  END IF;

  -- جلب معرّفات الحسابات من الأكواد
  SELECT id INTO v_debit_acct FROM chart_of_accounts WHERE code = p_debit_account;
  IF v_debit_acct IS NULL THEN
    RAISE EXCEPTION 'حساب مدين غير موجود: %', p_debit_account;
  END IF;

  SELECT id INTO v_credit_acct FROM chart_of_accounts WHERE code = p_credit_account;
  IF v_credit_acct IS NULL THEN
    RAISE EXCEPTION 'حساب دائن غير موجود: %', p_credit_account;
  END IF;

  -- إنشاء القيد (total_debit = total_credit → يمر من CHECK constraint)
  INSERT INTO journal_entries (
    source_type, source_id, description, is_auto,
    total_debit, total_credit, created_by
  ) VALUES (
    p_source_type, p_source_id, p_description, true,
    p_amount, p_amount, p_user_id
  )
  RETURNING id INTO v_entry_id;

  -- إدراج السطر المدين
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
  VALUES (v_entry_id, v_debit_acct, p_amount, 0, p_description);

  -- إدراج السطر الدائن
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
  VALUES (v_entry_id, v_credit_acct, 0, p_amount, p_description);

  RETURN v_entry_id;
END; $$;


-- ════════════════════════════════════════════════════════════
-- دالة 8: check_credit_available
--   فحص ائتمان العميل — تُستخدم عند تأكيد طلب البيع
--   تفحص: الحد الائتماني + فترة السماح
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION check_credit_available(
  p_customer_id UUID,
  p_amount      NUMERIC
) RETURNS BOOLEAN
  LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_limit          NUMERIC;
  v_days           INTEGER;
  v_balance        NUMERIC;
  v_oldest_unpaid  DATE;
  v_strict         BOOLEAN;
BEGIN
  -- 1. جلب بيانات العميل الائتمانية
  SELECT credit_limit, credit_days
  INTO v_limit, v_days
  FROM customers
  WHERE id = p_customer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'العميل غير موجود';
  END IF;

  -- عميل نقدي فقط (بدون ائتمان)
  IF COALESCE(v_limit, 0) = 0 THEN
    RETURN false;
  END IF;

  -- 2. حساب الرصيد الحالي من الدفتر
  SELECT COALESCE(balance, 0) INTO v_balance
  FROM v_customer_balances
  WHERE customer_id = p_customer_id;

  v_balance := COALESCE(v_balance, 0);

  -- 3. فحص هل تجاوز فترة السماح (credit_days)
  IF COALESCE(v_days, 0) > 0 THEN
    -- أقدم حركة مدينة فعلاً غير مسددة
    -- المنطق: نجد أقدم debit بتاريخ > آخر نقطة كان فيها الرصيد = 0
    -- (بدلاً من MIN المطلق الذي يرجع فواتير مسددة قديمة)
    SELECT MIN(cl.created_at::date) INTO v_oldest_unpaid
    FROM customer_ledger cl
    WHERE cl.customer_id = p_customer_id
      AND cl.type = 'debit'
      AND cl.source_type = 'sales_order'
      AND cl.created_at > COALESCE(
        (
          -- آخر نقطة أصبح فيها الرصيد التراكمي <= 0 (مسدد بالكامل)
          SELECT sub.created_at
          FROM (
            SELECT cl2.created_at,
                   SUM(CASE WHEN cl2.type = 'debit' THEN cl2.amount ELSE -cl2.amount END)
                     OVER (ORDER BY cl2.created_at, cl2.id) AS running_balance
            FROM customer_ledger cl2
            WHERE cl2.customer_id = p_customer_id
          ) sub
          WHERE sub.running_balance <= 0
          ORDER BY sub.created_at DESC
          LIMIT 1
        ),
        '1970-01-01'::timestamptz  -- إذا لم يكن هناك نقطة صفر → كل الفواتير
      );

    IF v_oldest_unpaid IS NOT NULL
       AND v_balance > 0
       AND (CURRENT_DATE - v_oldest_unpaid) > v_days THEN
      -- هل الفحص صارم (يمنع) أم تحذيري فقط؟
      SELECT COALESCE(value::boolean, true) INTO v_strict
      FROM company_settings WHERE key = 'sales.credit_check_strict';

      IF COALESCE(v_strict, true) THEN
        RAISE EXCEPTION 'العميل تجاوز فترة السماح (% يوم) — أقدم فاتورة: % — يرجى التسوية أولاً',
          v_days, v_oldest_unpaid;
      END IF;
    END IF;
  END IF;

  -- 4. فحص الحد الائتماني
  RETURN (v_balance + p_amount) <= v_limit;
END; $$;


-- ════════════════════════════════════════════════════════════
-- دالة 9: تسجيل الرصيد الافتتاحي تلقائياً في الدفتر
--   عند إدراج عميل/مورد بـ opening_balance > 0
--   تُنشئ سطر opening_balance في الـ Ledger المناسب
-- ════════════════════════════════════════════════════════════

-- Trigger: العملاء — إدراج رصيد افتتاحي في customer_ledger
CREATE OR REPLACE FUNCTION sync_customer_opening_balance()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(NEW.opening_balance, 0) > 0 THEN
    INSERT INTO customer_ledger (
      customer_id, type, amount, source_type, source_id,
      description, created_by
    ) VALUES (
      NEW.id, 'debit', NEW.opening_balance,
      'opening_balance', NEW.id,
      'رصيد افتتاحي',
      NEW.created_by
    )
    ON CONFLICT (source_type, source_id) DO NOTHING;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_customer_opening_ledger ON customers;
CREATE TRIGGER trg_customer_opening_ledger
  AFTER INSERT ON customers
  FOR EACH ROW EXECUTE FUNCTION sync_customer_opening_balance();

-- Trigger: الموردين — إدراج رصيد افتتاحي في supplier_ledger
CREATE OR REPLACE FUNCTION sync_supplier_opening_balance()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(NEW.opening_balance, 0) > 0 THEN
    INSERT INTO supplier_ledger (
      supplier_id, type, amount, source_type, source_id,
      description, created_by
    ) VALUES (
      NEW.id, 'credit', NEW.opening_balance,
      'opening_balance', NEW.id,
      'رصيد افتتاحي',
      NEW.created_by
    )
    ON CONFLICT (source_type, source_id) DO NOTHING;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_supplier_opening_ledger ON suppliers;
CREATE TRIGGER trg_supplier_opening_ledger
  AFTER INSERT ON suppliers
  FOR EACH ROW EXECUTE FUNCTION sync_supplier_opening_balance();


-- ════════════════════════════════════════════════════════════
-- GRANTS — السماح للمستخدمين المصادقين باستدعاء الدوال
-- ════════════════════════════════════════════════════════════

GRANT EXECUTE ON FUNCTION add_vault_transaction       TO authenticated;
GRANT EXECUTE ON FUNCTION add_custody_transaction     TO authenticated;
GRANT EXECUTE ON FUNCTION load_custody_from_vault     TO authenticated;
GRANT EXECUTE ON FUNCTION settle_custody_to_vault     TO authenticated;
GRANT EXECUTE ON FUNCTION confirm_payment_receipt     TO authenticated;
GRANT EXECUTE ON FUNCTION approve_expense             TO authenticated;
GRANT EXECUTE ON FUNCTION create_auto_journal_entry   TO authenticated;
GRANT EXECUTE ON FUNCTION check_credit_available      TO authenticated;







-- إضافة قاعدة موافقة لمدير النظام بحد أقصى لا نهائي عملياً
INSERT INTO approval_rules (type, role_id, max_amount, sort_order)
SELECT 'expense', id, 99999999.99, 0
FROM roles WHERE name = 'admin'
ON CONFLICT (type, role_id) DO UPDATE SET max_amount = 99999999.99, sort_order = 0;
