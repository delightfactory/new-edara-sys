BEGIN;

-- TYPE sales_return_status from 04_sales_system.sql:119
DO $$ BEGIN
  CREATE TYPE sales_return_status AS ENUM ('draft', 'confirmed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;

-- TABLE product_units from 02_master_data.sql:121
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

-- TABLE price_list_items from 02_master_data.sql:171
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

-- TABLE price_list_assignments from 02_master_data.sql:182
CREATE TABLE IF NOT EXISTS price_list_assignments (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  price_list_id  UUID NOT NULL REFERENCES price_lists(id) ON DELETE CASCADE,
  entity_type    TEXT NOT NULL CHECK (entity_type IN ('customer', 'city', 'governorate')),
  entity_id      UUID NOT NULL,
  created_at     TIMESTAMPTZ DEFAULT now(),
  UNIQUE (price_list_id, entity_type, entity_id)
);

-- TABLE stock_movements from 02_master_data.sql:397
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

-- TABLE chart_of_accounts from 03_financial_infrastructure.sql:20
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

-- TABLE customer_ledger from 03_financial_infrastructure.sql:81
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

-- TABLE supplier_ledger from 03_financial_infrastructure.sql:119
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

-- TABLE vault_transactions from 03_financial_infrastructure.sql:176
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

-- TABLE custody_transactions from 03_financial_infrastructure.sql:217
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

-- TABLE payment_receipts from 03_financial_infrastructure.sql:244
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

-- TABLE journal_entries from 03_financial_infrastructure.sql:401
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

-- TABLE journal_entry_lines from 03_financial_infrastructure.sql:424
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

-- TABLE sales_order_items from 04_sales_system.sql:209
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

-- TABLE sales_returns from 04_sales_system.sql:288
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

-- TABLE sales_return_items from 04_sales_system.sql:322
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

-- TABLE purchase_invoice_items from 14_procurement_schema_and_coa.sql:220
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

-- TABLE purchase_returns from 16_procurement_returns_and_cancellations.sql:143
CREATE TABLE IF NOT EXISTS purchase_returns (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  number               TEXT UNIQUE,

  supplier_id          UUID NOT NULL REFERENCES suppliers(id),
  warehouse_id         UUID NOT NULL REFERENCES warehouses(id),
  original_invoice_id  UUID REFERENCES purchase_invoices(id),

  status               TEXT NOT NULL CHECK (status IN ('draft', 'confirmed')) DEFAULT 'draft',
  return_date          DATE NOT NULL DEFAULT CURRENT_DATE,
  notes                TEXT,

  -- [Bug-4 Fix] subtotal = الخام قبل الخصم | discount_amount = صريح منفصل
  subtotal             NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
  discount_amount      NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
  tax_amount           NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
  total_amount         NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
  refunded_amount      NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (refunded_amount >= 0),

  confirmed_by         UUID REFERENCES profiles(id),
  confirmed_at         TIMESTAMPTZ,
  created_by           UUID REFERENCES profiles(id),
  created_at           TIMESTAMPTZ DEFAULT now(),
  updated_at           TIMESTAMPTZ DEFAULT now(),

  CONSTRAINT chk_pr_refunded_lte_total   CHECK (refunded_amount <= total_amount),
  CONSTRAINT chk_pr_discount_lte_subtotal CHECK (discount_amount <= subtotal)
);

-- TABLE purchase_return_items from 16_procurement_returns_and_cancellations.sql:199
CREATE TABLE IF NOT EXISTS purchase_return_items (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  return_id    UUID NOT NULL REFERENCES purchase_returns(id) ON DELETE CASCADE,
  product_id   UUID NOT NULL REFERENCES products(id),
  unit_id      UUID REFERENCES units(id),

  quantity          NUMERIC(14,4) NOT NULL CHECK (quantity > 0),
  unit_price        NUMERIC(14,4) NOT NULL CHECK (unit_price >= 0),
  discount_rate     NUMERIC(5,2)  NOT NULL DEFAULT 0
                      CHECK (discount_rate >= 0 AND discount_rate <= 100),
  tax_rate          NUMERIC(5,2)  NOT NULL DEFAULT 0
                      CHECK (tax_rate >= 0 AND tax_rate <= 100),

  -- [Bug-4 Fix] حقول تفصيلية للتوثيق والتدقيق
  ap_line_gross     NUMERIC(14,4) DEFAULT 0,  -- qty × unit_price (خام)
  ap_line_discount  NUMERIC(14,4) DEFAULT 0,  -- قيمة الخصم
  ap_line_net       NUMERIC(14,4) DEFAULT 0,  -- بعد الخصم قبل الضريبة
  ap_line_tax       NUMERIC(14,4) DEFAULT 0,  -- الضريبة
  ap_line_total     NUMERIC(14,4) DEFAULT 0,  -- net + tax
  cogs_value        NUMERIC(14,4) DEFAULT 0,  -- qty × WAC الحالي
  wac_variance      NUMERIC(14,4) DEFAULT 0,  -- cogs - ap_line_net

  line_total        NUMERIC(14,4) GENERATED ALWAYS AS (
    quantity * unit_price * (1 - discount_rate / 100.0) * (1 + tax_rate / 100.0)
  ) STORED,

  created_at   TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT uq_pri_return_product UNIQUE (return_id, product_id)
);

-- TABLE notification_alert_state from 52_notification_wave1a_events.sql:49
CREATE TABLE IF NOT EXISTS notification_alert_state (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_key      TEXT        NOT NULL,
  event_key      TEXT        NOT NULL,
  entity_type    TEXT,
  entity_id      UUID,
  last_sent_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at    TIMESTAMPTZ,                    -- NULL = still active
  send_count     INTEGER     NOT NULL DEFAULT 1,
  cooldown_hours INTEGER     NOT NULL DEFAULT 24,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT uq_nas_alert_key UNIQUE (alert_key)
);

-- TABLE sales_order_due_date_history from 118_invoice_credit_due_date_adjustments.sql:15
CREATE TABLE IF NOT EXISTS public.sales_order_due_date_history (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id        UUID NOT NULL REFERENCES public.sales_orders(id) ON DELETE CASCADE,
  customer_id     UUID NOT NULL REFERENCES public.customers(id),
  old_due_date    DATE,
  new_due_date    DATE NOT NULL,
  old_credit_days INTEGER,
  new_credit_days INTEGER NOT NULL,
  changed_by      UUID NOT NULL REFERENCES public.profiles(id),
  reason          TEXT NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT sales_order_due_date_history_reason_not_blank
    CHECK (length(btrim(reason)) > 0),
  CONSTRAINT sales_order_due_date_history_new_credit_days_nonnegative
    CHECK (new_credit_days >= 0)
);

-- SEQUENCE payment_receipt_seq from 03_financial_infrastructure.sql:242
CREATE SEQUENCE IF NOT EXISTS payment_receipt_seq START WITH 1;

-- SEQUENCE journal_entry_seq from 03_financial_infrastructure.sql:399
CREATE SEQUENCE IF NOT EXISTS journal_entry_seq START WITH 1;

-- SEQUENCE sales_order_seq from 04_sales_system.sql:131
CREATE SEQUENCE IF NOT EXISTS sales_order_seq START 1;

-- SEQUENCE sales_return_seq from 04_sales_system.sql:132
CREATE SEQUENCE IF NOT EXISTS sales_return_seq START 1;

-- SEQUENCE purchase_invoice_seq from 14_procurement_schema_and_coa.sql:114
CREATE SEQUENCE IF NOT EXISTS purchase_invoice_seq START WITH 1;

-- SEQUENCE purchase_return_seq from 16_procurement_returns_and_cancellations.sql:141
CREATE SEQUENCE IF NOT EXISTS purchase_return_seq START WITH 1;

-- COLUMN customers from 02_master_data.sql:1143
ALTER TABLE customers ADD COLUMN IF NOT EXISTS opening_balance NUMERIC(14,2) DEFAULT 0;

-- COLUMN customers from 02_master_data.sql:1144
ALTER TABLE customers ADD COLUMN IF NOT EXISTS current_balance NUMERIC(14,2) DEFAULT 0;

-- COLUMN suppliers from 02_master_data.sql:1149
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS opening_balance NUMERIC(14,2) DEFAULT 0;

-- COLUMN suppliers from 02_master_data.sql:1150
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS current_balance NUMERIC(14,2) DEFAULT 0;

-- COLUMN customer_ledger from 04_sales_system.sql:13
ALTER TABLE customer_ledger
  ADD COLUMN IF NOT EXISTS allocated_to UUID REFERENCES customer_ledger(id);

-- COLUMN payment_receipts from 07_payment_integration.sql:16
ALTER TABLE payment_receipts
  ADD COLUMN IF NOT EXISTS sales_order_id UUID REFERENCES sales_orders(id);

-- CONSTRAINT_DROP supplier_ledger:uq_supp_ledger_source from 03_financial_infrastructure.sql:138
ALTER TABLE supplier_ledger DROP CONSTRAINT IF EXISTS uq_supp_ledger_source;

-- CONSTRAINT_DROP journal_entries:chk_balanced_entry from 03_financial_infrastructure.sql:420
ALTER TABLE journal_entries DROP CONSTRAINT IF EXISTS chk_balanced_entry;

-- CONSTRAINT_DROP customer_ledger:uq_cust_ledger_source from 04_sales_system.sql:20
ALTER TABLE customer_ledger DROP CONSTRAINT IF EXISTS uq_cust_ledger_source;

-- CONSTRAINT_DROP payment_receipts:payment_receipts_payment_method_check from 08_payment_receipts_refactor.sql:27
ALTER TABLE payment_receipts
  DROP CONSTRAINT IF EXISTS payment_receipts_payment_method_check;

-- CONSTRAINT_DROP customer_ledger:customer_ledger_source_type_check from 12_fix_ledger_source_type.sql:13
ALTER TABLE customer_ledger
  DROP CONSTRAINT IF EXISTS customer_ledger_source_type_check;

-- CONSTRAINT_DROP supplier_ledger:supplier_ledger_source_type_check from 16_procurement_returns_and_cancellations.sql:31
ALTER TABLE supplier_ledger
  DROP CONSTRAINT IF EXISTS supplier_ledger_source_type_check;

-- CONSTRAINT_DROP stock_movements:stock_movements_type_check from 16_procurement_returns_and_cancellations.sql:41
ALTER TABLE stock_movements
  DROP CONSTRAINT IF EXISTS stock_movements_type_check;

-- CONSTRAINT_DROP vault_transactions:vault_transactions_type_check from 113_hr_payroll_disbursement.sql:7
ALTER TABLE vault_transactions
  DROP CONSTRAINT IF EXISTS vault_transactions_type_check;

-- CONSTRAINT_DROP journal_entries:journal_entries_source_type_check from 113_hr_payroll_disbursement.sql:18
ALTER TABLE journal_entries
  DROP CONSTRAINT IF EXISTS journal_entries_source_type_check;

-- CONSTRAINT_ADD supplier_ledger:uq_supp_ledger_source from 03_financial_infrastructure.sql:139
ALTER TABLE supplier_ledger ADD CONSTRAINT uq_supp_ledger_source
  UNIQUE (source_type, source_id);

-- CONSTRAINT_ADD journal_entries:chk_balanced_entry from 03_financial_infrastructure.sql:421
ALTER TABLE journal_entries ADD CONSTRAINT chk_balanced_entry
  CHECK (total_debit = total_credit);

-- CONSTRAINT_ADD payment_receipts:payment_receipts_payment_method_check from 08_payment_receipts_refactor.sql:30
ALTER TABLE payment_receipts
  ADD CONSTRAINT payment_receipts_payment_method_check
  CHECK (payment_method IN (
    'cash', 'bank_transfer', 'instapay', 'cheque', 'mobile_wallet'
  ));

-- CONSTRAINT_ADD customer_ledger:customer_ledger_source_type_check from 12_fix_ledger_source_type.sql:16
ALTER TABLE customer_ledger
  ADD CONSTRAINT customer_ledger_source_type_check
  CHECK (source_type IN (
    'sales_order',
    'sales_return',
    'payment',
    'payment_receipt',   -- ← الإضافة الجديدة
    'opening_balance',
    'adjustment'
  ));

-- CONSTRAINT_ADD supplier_ledger:supplier_ledger_source_type_check from 16_procurement_returns_and_cancellations.sql:34
ALTER TABLE supplier_ledger
  ADD CONSTRAINT supplier_ledger_source_type_check
  CHECK (source_type IN (
    'purchase_order', 'purchase_return', 'purchase_cancellation',
    'payment', 'opening_balance', 'adjustment'
  ));

-- CONSTRAINT_ADD stock_movements:stock_movements_type_check from 16_procurement_returns_and_cancellations.sql:44
ALTER TABLE stock_movements
  ADD CONSTRAINT stock_movements_type_check
  CHECK (type IN (
    'in', 'out',
    'transfer_in', 'transfer_out',
    'adjustment_add', 'adjustment_remove',
    'return_in', 'return_out',
    'purchase_cancellation', 'purchase_return'
  ));

-- CONSTRAINT_ADD vault_transactions:vault_transactions_type_check from 113_hr_payroll_disbursement.sql:10
ALTER TABLE vault_transactions
  ADD CONSTRAINT vault_transactions_type_check
  CHECK (type IN (
    'deposit', 'withdrawal', 'transfer_in', 'transfer_out',
    'collection', 'expense', 'custody_load', 'custody_return',
    'opening_balance', 'vendor_payment', 'vendor_refund', 'payroll_payment'
  ));

-- CONSTRAINT_ADD journal_entries:journal_entries_source_type_check from 113_hr_payroll_disbursement.sql:21
ALTER TABLE journal_entries
  ADD CONSTRAINT journal_entries_source_type_check
  CHECK (source_type IN (
    'sales_order', 'sales_return', 'payment',
    'purchase_order', 'purchase_return', 'purchase_cancellation',
    'expense', 'custody', 'transfer', 'manual',
    'hr_advance', 'hr_payroll', 'supplier_payment', 'hr_payroll_payment'
  ));

-- COA_SEED 03_financial_infrastructure.sql:33 from 03_financial_infrastructure.sql:33
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

-- COA_SEED 03_financial_infrastructure.sql:60 from 03_financial_infrastructure.sql:60
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '1000')
WHERE code IN ('1100','1200','1300','1400') AND parent_id IS NULL;

-- COA_SEED 03_financial_infrastructure.sql:62 from 03_financial_infrastructure.sql:62
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '1100')
WHERE code IN ('1110','1120','1130') AND parent_id IS NULL;

-- COA_SEED 03_financial_infrastructure.sql:64 from 03_financial_infrastructure.sql:64
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '2000')
WHERE code IN ('2100','2200') AND parent_id IS NULL;

-- COA_SEED 03_financial_infrastructure.sql:66 from 03_financial_infrastructure.sql:66
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '3000')
WHERE code IN ('3100') AND parent_id IS NULL;

-- COA_SEED 03_financial_infrastructure.sql:68 from 03_financial_infrastructure.sql:68
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '4000')
WHERE code IN ('4100','4200','4300') AND parent_id IS NULL;

-- COA_SEED 03_financial_infrastructure.sql:70 from 03_financial_infrastructure.sql:70
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '5000')
WHERE code IN ('5100','5200') AND parent_id IS NULL;

-- COA_SEED 03_financial_infrastructure.sql:72 from 03_financial_infrastructure.sql:72
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '5200')
WHERE code IN ('5210','5220','5230') AND parent_id IS NULL;

-- COA_SEED 08_payment_receipts_refactor.sql:47 from 08_payment_receipts_refactor.sql:47
INSERT INTO chart_of_accounts (code, name, name_en, type, sort_order)
VALUES ('1210', 'أوراق قبض — شيكات معلقة', 'Notes Receivable (Cheques Pending)', 'asset', 7)
ON CONFLICT (code) DO NOTHING;

-- COA_SEED 08_payment_receipts_refactor.sql:52 from 08_payment_receipts_refactor.sql:52
UPDATE chart_of_accounts
  SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '1200')
  WHERE code = '1210' AND parent_id IS NULL;

-- COA_SEED 14_procurement_schema_and_coa.sql:23 from 14_procurement_schema_and_coa.sql:23
UPDATE chart_of_accounts
  SET name    = 'ضريبة القيمة المضافة — مخرجات (مبيعات)',
      name_en = 'Output VAT (Sales)'
WHERE code = '2200';

-- COA_SEED 14_procurement_schema_and_coa.sql:34 from 14_procurement_schema_and_coa.sql:34
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

-- COA_SEED 14_procurement_schema_and_coa.sql:56 from 14_procurement_schema_and_coa.sql:56
UPDATE chart_of_accounts
  SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '1000')
WHERE code = '1500' AND parent_id IS NULL;

-- COA_SEED 14_procurement_schema_and_coa.sql:61 from 14_procurement_schema_and_coa.sql:61
UPDATE chart_of_accounts
  SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '1500')
WHERE code = '1510' AND parent_id IS NULL;

-- COA_SEED 14_procurement_schema_and_coa.sql:66 from 14_procurement_schema_and_coa.sql:66
UPDATE chart_of_accounts
  SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '2100')
WHERE code = '2110' AND parent_id IS NULL;

-- COA_SEED 14_procurement_schema_and_coa.sql:71 from 14_procurement_schema_and_coa.sql:71
UPDATE chart_of_accounts
  SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '5000')
WHERE code = '5300' AND parent_id IS NULL;

-- COA_SEED 14_procurement_schema_and_coa.sql:76 from 14_procurement_schema_and_coa.sql:76
UPDATE chart_of_accounts
  SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '3000')
WHERE code = '3200' AND parent_id IS NULL;

-- COA_SEED 15_procurement_core_rpcs.sql:730 from 15_procurement_core_rpcs.sql:730
INSERT INTO chart_of_accounts (code, name, name_en, type, sort_order)
VALUES ('5900', 'فروق تقريب', 'Rounding Differences', 'expense', 99)
ON CONFLICT (code) DO NOTHING;

-- COA_SEED 15_procurement_core_rpcs.sql:735 from 15_procurement_core_rpcs.sql:735
UPDATE chart_of_accounts
SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '5000')
WHERE code = '5900' AND parent_id IS NULL;

-- FUNCTION get_available_stock from 02c_inventory_functions.sql:34
CREATE OR REPLACE FUNCTION get_available_stock(
  p_warehouse_id UUID,
  p_product_id UUID
) RETURNS NUMERIC
  LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_available NUMERIC;
BEGIN
  SELECT available_quantity INTO v_available
  FROM stock
  WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id;

  RETURN COALESCE(v_available, 0);
END; $$;

-- FUNCTION reserve_stock from 02c_inventory_functions.sql:56
CREATE OR REPLACE FUNCTION reserve_stock(
  p_warehouse_id UUID,
  p_product_id UUID,
  p_qty NUMERIC
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_stock stock%ROWTYPE;
BEGIN
  SELECT * INTO v_stock
  FROM stock
  WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'لا يوجد مخزون لهذا المنتج (%) في هذا المخزن (%)',
      p_product_id, p_warehouse_id;
  END IF;

  IF v_stock.available_quantity < p_qty THEN
    RAISE EXCEPTION 'الكمية المتاحة غير كافية (متاح: %, مطلوب: %)',
      v_stock.available_quantity, p_qty;
  END IF;

  UPDATE stock
  SET reserved_quantity = reserved_quantity + p_qty,
      updated_at = now()
  WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id;
END; $$;

-- FUNCTION unreserve_stock from 02c_inventory_functions.sql:93
CREATE OR REPLACE FUNCTION unreserve_stock(
  p_warehouse_id UUID,
  p_product_id UUID,
  p_qty NUMERIC
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
BEGIN
  -- FOR UPDATE لمنع race condition
  PERFORM 1 FROM stock
  WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id
  FOR UPDATE;

  UPDATE stock
  SET reserved_quantity = GREATEST(reserved_quantity - p_qty, 0),
      updated_at = now()
  WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id;
END; $$;

-- FUNCTION get_product_price from 02g_audit_fixes.sql:173
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

  -- ═══ FIX M3: فحص وجود العميل ═══
  IF NOT FOUND THEN
    RAISE EXCEPTION 'العميل غير موجود: %', p_customer_id;
  END IF;

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
    ORDER BY pli.min_qty DESC NULLS LAST, pl.created_at DESC LIMIT 1;
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
    ORDER BY pli.min_qty DESC NULLS LAST, pl.created_at DESC LIMIT 1;
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
    ORDER BY pli.min_qty DESC NULLS LAST, pl.created_at DESC LIMIT 1;
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
  ORDER BY pli.min_qty DESC NULLS LAST, pl.created_at DESC LIMIT 1;
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

-- FUNCTION generate_receipt_number from 03_financial_infrastructure.sql:279
CREATE OR REPLACE FUNCTION generate_receipt_number()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.number IS NULL OR NEW.number = '' THEN
    NEW.number := 'REC-' || to_char(CURRENT_DATE, 'YYYYMMDD') || '-' || lpad(nextval('payment_receipt_seq')::text, 4, '0');
  END IF;
  RETURN NEW;
END; $$;

-- FUNCTION generate_journal_number from 03_financial_infrastructure.sql:441
CREATE OR REPLACE FUNCTION generate_journal_number()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.number IS NULL OR NEW.number = '' THEN
    NEW.number := 'JE-' || to_char(CURRENT_DATE, 'YYYYMMDD') || '-' || lpad(nextval('journal_entry_seq')::text, 4, '0');
  END IF;
  RETURN NEW;
END; $$;

-- FUNCTION get_my_warehouse_ids from 03e_rls_hardening.sql:18
CREATE OR REPLACE FUNCTION get_my_warehouse_ids()
RETURNS UUID[]
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(array_agg(DISTINCT wid), '{}')
  FROM (
    -- مدير مباشر للمخزن
    SELECT id AS wid FROM warehouses WHERE manager_id = auth.uid()
    UNION
    -- ضمن فريق إدارة المخزن
    SELECT warehouse_id AS wid FROM warehouse_managers WHERE profile_id = auth.uid()
  ) sub;
$$;

-- FUNCTION update_customer_cached_balance from 03h_extreme_performance.sql:18
CREATE OR REPLACE FUNCTION update_customer_cached_balance()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old_delta NUMERIC;
  v_new_delta NUMERIC;
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- عكس الأثر من العميل
    v_old_delta := CASE WHEN OLD.type = 'debit' THEN -OLD.amount ELSE OLD.amount END;
    UPDATE customers SET current_balance = current_balance + v_old_delta
    WHERE id = OLD.customer_id;
    RETURN OLD;

  ELSIF TG_OP = 'INSERT' THEN
    -- مدين = رصيد العميل يزيد (العميل مدين لنا)
    v_new_delta := CASE WHEN NEW.type = 'debit' THEN NEW.amount ELSE -NEW.amount END;
    UPDATE customers SET current_balance = current_balance + v_new_delta
    WHERE id = NEW.customer_id;
    RETURN NEW;

  ELSE -- UPDATE
    -- عكس الأثر القديم من العميل القديم
    v_old_delta := CASE WHEN OLD.type = 'debit' THEN OLD.amount ELSE -OLD.amount END;
    UPDATE customers SET current_balance = current_balance - v_old_delta
    WHERE id = OLD.customer_id;
    -- تطبيق الأثر الجديد على العميل الجديد (قد يكون نفسه أو مختلف)
    v_new_delta := CASE WHEN NEW.type = 'debit' THEN NEW.amount ELSE -NEW.amount END;
    UPDATE customers SET current_balance = current_balance + v_new_delta
    WHERE id = NEW.customer_id;
    RETURN NEW;
  END IF;
END; $$;

-- FUNCTION update_supplier_cached_balance from 03h_extreme_performance.sql:63
CREATE OR REPLACE FUNCTION update_supplier_cached_balance()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old_delta NUMERIC;
  v_new_delta NUMERIC;
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- عكس الأثر من المورد
    v_old_delta := CASE WHEN OLD.type = 'credit' THEN -OLD.amount ELSE OLD.amount END;
    UPDATE suppliers SET current_balance = current_balance + v_old_delta
    WHERE id = OLD.supplier_id;
    RETURN OLD;

  ELSIF TG_OP = 'INSERT' THEN
    -- دائن = رصيد المورد يزيد (نحن مدينون للمورد)
    v_new_delta := CASE WHEN NEW.type = 'credit' THEN NEW.amount ELSE -NEW.amount END;
    UPDATE suppliers SET current_balance = current_balance + v_new_delta
    WHERE id = NEW.supplier_id;
    RETURN NEW;

  ELSE -- UPDATE
    -- عكس الأثر القديم من المورد القديم
    v_old_delta := CASE WHEN OLD.type = 'credit' THEN OLD.amount ELSE -OLD.amount END;
    UPDATE suppliers SET current_balance = current_balance - v_old_delta
    WHERE id = OLD.supplier_id;
    -- تطبيق الأثر الجديد على المورد الجديد (قد يكون نفسه أو مختلف)
    v_new_delta := CASE WHEN NEW.type = 'credit' THEN NEW.amount ELSE -NEW.amount END;
    UPDATE suppliers SET current_balance = current_balance + v_new_delta
    WHERE id = NEW.supplier_id;
    RETURN NEW;
  END IF;
END; $$;

-- FUNCTION update_stock_wac from 03j_auth_guard.sql:38
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
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

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

-- FUNCTION deduct_stock_at_wac from 03j_auth_guard.sql:94
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
  v_new_qty NUMERIC;
  v_new_total NUMERIC;
  v_new_wac NUMERIC;
BEGIN
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- قفل صف المخزون (نفس الآلية الأصلية)
  SELECT * INTO v_stock
  FROM stock
  WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'لا يوجد مخزون لهذا المنتج في هذا المخزن';
  END IF;

  -- ═══ FIX C1: فحص available_quantity بدلاً من quantity ═══
  -- available_quantity = quantity - reserved_quantity
  -- هذا يمنع بيع / خصم كميات محجوزة لتحويلات قيد الشحن
  IF v_stock.available_quantity < p_qty_out THEN
    -- فحص إعداد السماح بالمخزون السالب (نفس الآلية الأصلية)
    SELECT COALESCE(value::boolean, false) INTO v_allow_negative
    FROM company_settings WHERE key = 'sales.allow_negative_stock';

    IF NOT COALESCE(v_allow_negative, false) THEN
      RAISE EXCEPTION 'مخزون غير كافٍ (متاح: %, مطلوب: %)', v_stock.available_quantity, p_qty_out;
    END IF;
  END IF;

  -- حساب COGS بالـ WAC (نفس المعادلة الأصلية)
  v_cogs := p_qty_out * v_stock.wac;

  -- ═══ FIX C2: حساب الكمية الجديدة مع تصفير WAC عند الصفر ═══
  v_new_qty   := v_stock.quantity - p_qty_out;
  v_new_total := v_stock.total_cost_value - v_cogs;

  -- إذا وصلت الكمية لصفر أو سالب → تصفير WAC و total_cost_value
  -- لمنع تلوث WAC عند إضافة مخزون لاحقاً
  IF v_new_qty <= 0 THEN
    v_new_total := 0;
    v_new_wac   := 0;
  ELSE
    v_new_wac := v_stock.wac;  -- WAC لا يتغير عند الخصم (نفس السلوك الأصلي)
  END IF;

  UPDATE stock
  SET quantity = v_new_qty,
      total_cost_value = v_new_total,
      wac = v_new_wac,
      updated_at = now()
  WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id;

  -- تسجيل حركة المخزون (نفس الهيكل الأصلي بالكامل)
  INSERT INTO stock_movements (
    warehouse_id, product_id, unit_id, quantity, type,
    unit_cost, wac_before, wac_after, before_qty, after_qty,
    reference_type, reference_id, created_by
  ) VALUES (
    p_warehouse_id, p_product_id,
    (SELECT base_unit_id FROM products WHERE id = p_product_id),
    p_qty_out, p_movement_type,
    v_stock.wac, v_stock.wac, v_new_wac,
    v_stock.quantity, v_new_qty,
    p_reference_type, p_reference_id, p_user_id
  );

  RETURN v_cogs;
END; $$;

-- FUNCTION add_custody_transaction from 03j_auth_guard.sql:949
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
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

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

-- FUNCTION create_manual_journal_entry from 03j_auth_guard.sql:1483
CREATE OR REPLACE FUNCTION create_manual_journal_entry(
  p_description    TEXT,
  p_entry_date     DATE DEFAULT CURRENT_DATE,
  p_source_type    TEXT DEFAULT 'manual',
  p_source_id      UUID DEFAULT NULL,
  p_lines          JSONB DEFAULT '[]'::JSONB,
  p_user_id        UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_entry_id       UUID;
  v_total_debit    NUMERIC(14,2) := 0;
  v_total_credit   NUMERIC(14,2) := 0;
  v_line           JSONB;
  v_account_id     UUID;
  v_line_count     INT := 0;
BEGIN
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- ─── Validate ───
  IF p_lines IS NULL OR jsonb_array_length(p_lines) < 2 THEN
    RAISE EXCEPTION 'القيد يجب أن يحتوي على سطرين على الأقل';
  END IF;

  -- ─── Calculate totals & validate accounts ───
  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    -- Validate account_code exists
    SELECT id INTO v_account_id
    FROM chart_of_accounts
    WHERE code = (v_line ->> 'account_code')
      AND is_active = true;

    IF v_account_id IS NULL THEN
      RAISE EXCEPTION 'حساب غير موجود أو غير نشط: %', (v_line ->> 'account_code');
    END IF;

    v_total_debit  := v_total_debit  + COALESCE((v_line ->> 'debit')::NUMERIC, 0);
    v_total_credit := v_total_credit + COALESCE((v_line ->> 'credit')::NUMERIC, 0);
    v_line_count   := v_line_count + 1;
  END LOOP;

  -- ─── Check balance ───
  IF v_total_debit <> v_total_credit THEN
    RAISE EXCEPTION 'القيد غير متوازن: مدين % ≠ دائن %', v_total_debit, v_total_credit;
  END IF;

  IF v_total_debit = 0 THEN
    RAISE EXCEPTION 'إجمالي القيد لا يمكن أن يكون صفراً';
  END IF;

  -- ─── Insert header ───
  INSERT INTO journal_entries (
    source_type, source_id, description, entry_date,
    is_auto, status, total_debit, total_credit, created_by
  ) VALUES (
    p_source_type, p_source_id, p_description, p_entry_date,
    false, 'posted', v_total_debit, v_total_credit, p_user_id
  )
  RETURNING id INTO v_entry_id;

  -- ─── Insert lines ───
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
  SELECT
    v_entry_id,
    ca.id,
    COALESCE((line ->> 'debit')::NUMERIC, 0),
    COALESCE((line ->> 'credit')::NUMERIC, 0),
    line ->> 'description'
  FROM jsonb_array_elements(p_lines) AS line
  JOIN chart_of_accounts ca ON ca.code = (line ->> 'account_code');

  RETURN v_entry_id;
END;
$$;

-- FUNCTION generate_sales_order_number from 04_sales_system.sql:461
CREATE OR REPLACE FUNCTION generate_sales_order_number()
RETURNS TEXT
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
BEGIN
  RETURN 'SO-' || to_char(CURRENT_DATE, 'YYYYMMDD') || '-' ||
         lpad(nextval('sales_order_seq')::text, 4, '0');
END; $$;

-- FUNCTION generate_sales_return_number from 04_sales_system.sql:476
CREATE OR REPLACE FUNCTION generate_sales_return_number()
RETURNS TEXT
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
BEGIN
  RETURN 'SR-' || to_char(CURRENT_DATE, 'YYYYMMDD') || '-' ||
         lpad(nextval('sales_return_seq')::text, 4, '0');
END; $$;

-- FUNCTION trg_auto_sales_order_number from 04_sales_system.sql:491
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

-- FUNCTION trg_auto_sales_return_number from 04_sales_system.sql:507
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

-- FUNCTION cancel_sales_order from 04_sales_system.sql:976
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

-- FUNCTION confirm_sales_return from 04_sales_system.sql:1049
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

-- FUNCTION allocate_payment_to_invoices from 04_sales_system.sql:1304
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

-- FUNCTION search_products_with_stock from 04b_delivery_rpcs.sql:210
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

-- FUNCTION get_user_payment_options from 04b_delivery_rpcs.sql:376
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

-- FUNCTION allocate_payment_to_invoices from 08_payment_receipts_refactor.sql:64
CREATE OR REPLACE FUNCTION allocate_payment_to_invoices(
  p_customer_id    UUID,
  p_amount         NUMERIC,
  p_source_type    TEXT,    -- 'payment_receipt' أو 'collection'
  p_source_id      UUID,
  p_user_id        UUID,
  p_target_order_id UUID DEFAULT NULL   -- [NEW R3] الطلب المستهدف (اختياري)
) RETURNS JSONB    -- يرجع تفاصيل التوزيع
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_remaining    NUMERIC := p_amount;
  v_allocated    JSONB := '[]'::JSONB;
  v_entry        RECORD;
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

  -- [R3] التوزيع مع الأولوية للطلب المحدد
  -- ORDER BY: الطلب المحدد أولاً (0)، ثم الأقدم (1)
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
    ORDER BY
      CASE
        WHEN p_target_order_id IS NOT NULL
          AND cl.source_type = 'sales_order'
          AND cl.source_id = p_target_order_id
        THEN 0
        ELSE 1
      END ASC,
      cl.created_at ASC,
      cl.id ASC
    FOR UPDATE OF cl
  LOOP
    EXIT WHEN v_remaining <= 0;

    v_entry_balance := v_entry.outstanding;
    IF v_entry_balance <= 0 THEN CONTINUE; END IF;

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

-- FUNCTION validate_sales_item_amounts from 10_audit_fixes.sql:16
CREATE OR REPLACE FUNCTION validate_sales_item_amounts()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
  v_expected_discount NUMERIC;
  v_expected_tax      NUMERIC;
  v_expected_line     NUMERIC;
  v_tax_enabled       BOOLEAN;
BEGIN
  -- [BE-04] جلب إعداد الضريبة من company_settings
  SELECT COALESCE((value)::boolean, false) INTO v_tax_enabled
  FROM company_settings WHERE key = 'sales.tax_enabled';

  -- حساب الخصم الصحيح
  v_expected_discount := ROUND(
    (NEW.quantity * NEW.unit_price) * (NEW.discount_percent / 100), 2
  );

  -- تصحيح تلقائي (تفادي مشاكل الأعشار — فرق <=٠.٠١ مقبول)
  IF ABS(NEW.discount_amount - v_expected_discount) > 0.01 THEN
    NEW.discount_amount := v_expected_discount;
  END IF;

  -- [BE-04] إذا الضريبة مُعطَّلة من الإعدادات → أجبر الصفر
  IF NOT COALESCE(v_tax_enabled, false) THEN
    NEW.tax_rate   := 0;
    NEW.tax_amount := 0;
  ELSE
    -- حساب الضريبة إجبارياً من tax_rate
    v_expected_tax := ROUND(
      ((NEW.quantity * NEW.unit_price) - NEW.discount_amount) * (NEW.tax_rate / 100), 2
    );
    IF ABS(COALESCE(NEW.tax_amount, 0) - v_expected_tax) > 0.01 THEN
      NEW.tax_amount := v_expected_tax;
    END IF;
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

-- FUNCTION confirm_sales_order from 10_audit_fixes.sql:78
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
  -- [BE-01]
  v_cust_terms     TEXT;
  v_credit_ok      BOOLEAN;
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
    v_order.total_amount    := v_computed_total;
    v_order.subtotal        := v_computed_sub;
    v_order.discount_amount := v_computed_disc;
  END IF;

  -- ٣ب. [DEFENSIVE] فحص حدود الخصم
  SELECT COALESCE(value::numeric, 100) INTO v_max_discount
  FROM company_settings WHERE key = 'sales.max_discount_percent';
  v_max_discount := COALESCE(v_max_discount, 100);

  IF v_max_discount < 100 THEN
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

  -- ٣ج. [BE-01] فحص الائتمان المبكر قبل حجز المخزون
  --     نقرأ من ملف العميل لأن v_order.payment_terms = NULL في هذه المرحلة
  SELECT payment_terms INTO v_cust_terms
  FROM customers WHERE id = v_order.customer_id;

  -- نفحص فقط إذا كان العميل آجل أو مختلط بطبيعته (ليس نقدياً)
  IF COALESCE(v_cust_terms, 'cash') != 'cash' THEN
    v_credit_ok := check_credit_available(v_order.customer_id, v_order.total_amount);

    IF NOT v_credit_ok THEN
      -- المدير يملك صلاحية التجاوز
      IF NOT check_permission(p_user_id, 'sales.orders.override_credit') THEN
        RAISE EXCEPTION 'تجاوز الحد الائتماني للعميل أو لديه فواتير متأخرة. لا يمكن حجز المخزون له بدون صلاحية التجاوز.';
      END IF;
    END IF;
  END IF;

  -- ٤. لكل بند: حجز المخزون
  FOR v_item IN
    SELECT * FROM sales_order_items WHERE order_id = p_order_id
    ORDER BY product_id ASC  -- [DEADLOCK FIX] ترتيب ثابت لمنع الاختناق
  LOOP
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

-- FUNCTION deliver_sales_order from 11_final_accounting_sync.sql:23
CREATE OR REPLACE FUNCTION deliver_sales_order(
  p_order_id        UUID,
  p_user_id         UUID,
  p_payment_terms   TEXT,
  p_payment_method  TEXT    DEFAULT NULL,
  p_vault_id        UUID    DEFAULT NULL,
  p_custody_id      UUID    DEFAULT NULL,
  p_cash_amount     NUMERIC DEFAULT 0,
  p_override_credit BOOLEAN DEFAULT false,
  p_bank_reference  TEXT    DEFAULT NULL,
  p_check_number    TEXT    DEFAULT NULL,
  p_check_date      DATE    DEFAULT NULL
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
  v_journal_lines JSONB   := '[]'::JSONB;
  v_is_cash       BOOLEAN;
  v_shipping      NUMERIC;  -- [FIX] تكلفة الشحن المحملة على العميل
BEGIN
  -- [SECURITY GUARD]
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- [PERMISSION]
  IF NOT check_permission(p_user_id, 'sales.orders.deliver') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية تسليم طلبات البيع';
  END IF;

  v_is_cash := (COALESCE(p_payment_method, 'cash') = 'cash');

  -- ١. قفل الطلب
  SELECT * INTO v_order FROM sales_orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'أمر البيع غير موجود'; END IF;

  IF v_order.status = 'delivered' OR v_order.status = 'completed' THEN RETURN; END IF;

  IF v_order.status != 'confirmed' THEN
    RAISE EXCEPTION 'لا يمكن تسليم طلب في حالة: % — يجب أن يكون مؤكداً', v_order.status;
  END IF;

  -- [FIX] حساب تكلفة الشحن المحملة على العميل (صفر إذا لم تكن على العميل)
  v_shipping := CASE
    WHEN v_order.shipping_on_customer = true THEN COALESCE(v_order.shipping_cost, 0)
    ELSE 0
  END;

  -- ٢. حساب التوزيع (نقدي <-> آجل)
  v_credit_amount := v_order.total_amount - p_cash_amount;

  IF p_payment_terms = 'cash' THEN
    v_credit_amount := 0;
    p_cash_amount   := v_order.total_amount;
  ELSIF p_payment_terms = 'credit' THEN
    v_credit_amount := v_order.total_amount;
    p_cash_amount   := 0;
  END IF;

  -- [VALIDATION]
  IF (p_cash_amount + v_credit_amount) != v_order.total_amount THEN
    RAISE EXCEPTION 'المبلغ النقدي + الآجل لا يساوي إجمالي الفاتورة';
  END IF;

  -- فحص الائتمان
  IF v_credit_amount > 0 THEN
    DECLARE v_customer_terms TEXT; BEGIN
      SELECT payment_terms INTO v_customer_terms FROM customers WHERE id = v_order.customer_id;
      IF v_customer_terms = 'cash' THEN
        RAISE EXCEPTION 'هذا العميل مسموح له بالدفع النقدي فقط';
      END IF;
    END;

    v_credit_ok := check_credit_available(v_order.customer_id, v_credit_amount);

    IF NOT v_credit_ok THEN
      IF p_override_credit AND check_permission(p_user_id, 'sales.orders.override_credit') THEN NULL;
      ELSE RAISE EXCEPTION 'تجاوز حد الائتمان — المبلغ الآجل: %', v_credit_amount;
      END IF;
    END IF;
  END IF;

  -- ٣. إلغاء الحجز + خصم المخزون + تكلفة البضاعة
  FOR v_item IN
    SELECT * FROM sales_order_items WHERE order_id = p_order_id ORDER BY product_id ASC
  LOOP
    PERFORM unreserve_stock(v_order.warehouse_id, v_item.product_id, v_item.base_quantity);

    v_item_cogs := deduct_stock_at_wac(
      v_order.warehouse_id, v_item.product_id, v_item.base_quantity,
      'out', 'sales_order', p_order_id, p_user_id
    );

    v_total_cogs := v_total_cogs + v_item_cogs;

    UPDATE sales_order_items
    SET delivered_quantity = base_quantity,
        unit_cost_at_sale = CASE WHEN base_quantity > 0 THEN v_item_cogs / base_quantity ELSE 0 END
    WHERE id = v_item.id;
  END LOOP;

  -- ════════════════════════════════════════════════════════════
  -- ٤. المعالجة المالية — المسار مزدوج
  -- ════════════════════════════════════════════════════════════

  IF p_cash_amount > 0 THEN

    IF v_is_cash THEN
      IF p_custody_id IS NULL AND p_vault_id IS NULL THEN
        RAISE EXCEPTION 'يجب تحديد العهدة أو الخزينة لاستقبال المبلغ النقدي';
      END IF;

      IF p_custody_id IS NOT NULL THEN
        PERFORM add_custody_transaction(
          p_custody_id, 'collection', p_cash_amount,
          p_vault_id, 'sales_order', p_order_id,
          'تحصيل فاتورة بيع #' || v_order.order_number, p_user_id
        );
      ELSE
        PERFORM add_vault_transaction(
          p_vault_id, 'collection', p_cash_amount,
          'sales_order', p_order_id,
          'تحصيل فاتورة بيع #' || v_order.order_number, p_user_id
        );
      END IF;

      INSERT INTO payment_receipts (
        customer_id, amount, payment_method, status,
        sales_order_id, custody_id, vault_id,
        collected_by, reviewed_by, reviewed_at, created_by, notes
      ) VALUES (
        v_order.customer_id, p_cash_amount, 'cash', 'confirmed',
        p_order_id, p_custody_id, p_vault_id,
        p_user_id, p_user_id, now(), p_user_id,
        'تحصيل تلقائي — فاتورة #' || v_order.order_number
      );

    ELSE
      INSERT INTO payment_receipts (
        customer_id, amount, payment_method, status,
        sales_order_id, collected_by, created_by,
        bank_reference, check_number, check_date, notes
      ) VALUES (
        v_order.customer_id, p_cash_amount,
        COALESCE(p_payment_method, 'bank_transfer'), 'pending',
        p_order_id, p_user_id, p_user_id,
        p_bank_reference, p_check_number, p_check_date,
        'بانتظار التأكيد المالي — فاتورة #' || v_order.order_number
      );

      INSERT INTO customer_ledger (
        customer_id, type, amount, source_type, source_id, description, created_by
      ) VALUES (
        v_order.customer_id, 'debit', p_cash_amount,
        'sales_order', p_order_id,
        'بانتظار تأكيد دفعة ' || COALESCE(p_payment_method, '') || ' — #' || v_order.order_number,
        p_user_id
      );

    END IF;
  END IF;

  -- ٤ب. الآجل الصريح → دفتر العميل
  IF v_credit_amount > 0 THEN
    INSERT INTO customer_ledger (
      customer_id, type, amount, source_type, source_id, description, created_by
    ) VALUES (
      v_order.customer_id, 'debit', v_credit_amount,
      'sales_order', p_order_id,
      'فاتورة بيع آجل #' || v_order.order_number, p_user_id
    );
  END IF;

  -- ════════════════════════════════════════════════════════════
  -- ٥. القيد المحاسبي — [BE-03] متوازن في جميع الحالات
  --
  -- إثبات التوازن النهائي بعد الإصلاح:
  --   DR = discount_amount + total_amount + cogs
  --      = discount + (subtotal - discount + tax + shipping) + cogs
  --      = subtotal + tax + shipping + cogs
  --   CR = subtotal(4100) + shipping(4100) + tax(2200) + cogs(1300)
  --      = subtotal + shipping + tax + cogs  ✅ متوازن في كل الحالات
  -- ════════════════════════════════════════════════════════════

  -- إيراد المبيعات (دائن) — الإجمالي قبل الخصم
  v_journal_lines := v_journal_lines || jsonb_build_object(
    'account_code', '4100', 'debit', 0,
    'credit', v_order.subtotal,
    'description', 'إيراد بيع إجمالي #' || v_order.order_number
  );

  -- [FIX] إيراد الشحن (دائن) — سطر منفصل لتكلفة الشحن المحملة على العميل
  IF v_shipping > 0 THEN
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', '4100', 'debit', 0,
      'credit', v_shipping,
      'description', 'إيراد شحن — فاتورة #' || v_order.order_number
    );
  END IF;

  -- الخصومات الممنوحة (مدين) — حساب 4300
  IF COALESCE(v_order.discount_amount, 0) > 0 THEN
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', '4300', 'debit', v_order.discount_amount, 'credit', 0,
      'description', 'خصومات مبيعات #' || v_order.order_number
    );
  END IF;

  -- الضريبة (دائن) — التزام ضريبي
  IF COALESCE(v_order.tax_amount, 0) > 0 THEN
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', '2200', 'debit', 0, 'credit', v_order.tax_amount,
      'description', 'ضريبة قيمة مضافة — بيع #' || v_order.order_number
    );
  END IF;

  -- الآجل الصريح (مدين → 1200)
  IF v_credit_amount > 0 THEN
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', '1200', 'debit', v_credit_amount, 'credit', 0,
      'description', 'ذمم عملاء — بيع آجل #' || v_order.order_number
    );
  END IF;

  -- النقدي/التحويل (مدين)
  IF p_cash_amount > 0 THEN
    IF v_is_cash THEN
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
    ELSE
      v_journal_lines := v_journal_lines || jsonb_build_object(
        'account_code', '1200', 'debit', p_cash_amount, 'credit', 0,
        'description', 'ذمم عملاء — بانتظار تأكيد '
          || COALESCE(p_payment_method, '') || ' #' || v_order.order_number
      );
    END IF;
  END IF;

  -- تكلفة البضاعة المباعة (مدين) + المخزون (دائن)
  IF v_total_cogs > 0 THEN
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', '5100', 'debit', v_total_cogs, 'credit', 0,
      'description', 'تكلفة بضاعة مباعة #' || v_order.order_number
    );
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', '1300', 'debit', 0, 'credit', v_total_cogs,
      'description', 'خصم مخزون — بيع #' || v_order.order_number
    );
  END IF;

  PERFORM create_manual_journal_entry(
    'قيد بيع — فاتورة #' || v_order.order_number,
    CURRENT_DATE, 'sales_order', p_order_id, v_journal_lines, p_user_id
  );

  -- ٦. تحديث الطلب
  UPDATE sales_orders
  SET status        = 'delivered',
      payment_terms = p_payment_terms,
      payment_method = CASE WHEN p_payment_method IS NOT NULL THEN p_payment_method::payment_method ELSE NULL END,
      vault_id      = p_vault_id,
      custody_id    = p_custody_id,
      cash_amount   = COALESCE(cash_amount, 0) + CASE WHEN v_is_cash THEN p_cash_amount ELSE 0 END,
      credit_amount = v_credit_amount + CASE WHEN NOT v_is_cash THEN p_cash_amount ELSE 0 END,
      paid_amount   = COALESCE(paid_amount, 0) + CASE WHEN v_is_cash THEN p_cash_amount ELSE 0 END,
      credit_check_passed = v_credit_ok,
      credit_override     = p_override_credit,
      credit_override_by  = CASE WHEN p_override_credit THEN p_user_id ELSE NULL END,
      delivered_by  = p_user_id,
      delivered_at  = now(),
      due_date      = CASE
        WHEN p_payment_terms = 'cash' THEN NULL
        ELSE CURRENT_DATE + COALESCE((SELECT credit_days FROM customers WHERE id = v_order.customer_id), 0)
      END
  WHERE id = p_order_id;

  -- ٧. فحص اكتمال السداد (للنقدي الفوري only)
  IF v_is_cash THEN
    IF (COALESCE(v_order.paid_amount, 0) + p_cash_amount + COALESCE(v_order.returned_amount, 0)) >= v_order.total_amount THEN
      UPDATE sales_orders SET status = 'completed' WHERE id = p_order_id;
    END IF;
  END IF;

END;
$$;

-- FUNCTION generate_purchase_invoice_number from 14_procurement_schema_and_coa.sql:184
CREATE OR REPLACE FUNCTION generate_purchase_invoice_number()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.number IS NULL OR NEW.number = '' THEN
    NEW.number := 'PIN-' || to_char(CURRENT_DATE, 'YYYYMMDD')
               || '-' || lpad(nextval('purchase_invoice_seq')::text, 4, '0');
  END IF;
  RETURN NEW;
END; $$;

-- FUNCTION receive_purchase_invoice from 15_procurement_core_rpcs.sql:21
CREATE OR REPLACE FUNCTION receive_purchase_invoice(
  p_invoice_id  UUID,
  p_user_id     UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_invoice         purchase_invoices%ROWTYPE;
  v_item            RECORD;

  -- ───── توزيع مصاريف الشحن ─────
  v_total_value     NUMERIC := 0;
  v_total_qty       NUMERIC := 0;
  v_use_qty_basis   BOOLEAN := false;

  -- ───── تكاليف البند ─────
  v_net_cost        NUMERIC;
  v_landed_share    NUMERIC;
  v_true_net_cost   NUMERIC;
  v_item_value      NUMERIC;

  -- ───── WAC ─────
  v_base_qty        NUMERIC;
  v_base_unit_cost  NUMERIC;    -- للـ WAC (يشمل landed costs)

  -- [Audit-Fix-1] السعر التجاري الصافي لحقل last_purchase_price (بدون landed costs)
  v_commercial_unit_price NUMERIC;

  -- ─── [Fix-1] إجماليات محسوبة على الكميات الفعلية ─────────
  v_recv_subtotal   NUMERIC := 0;
  v_recv_discount   NUMERIC := 0;
  v_recv_tax        NUMERIC := 0;   -- يُصفَّر لو tax_enabled=false
  v_recv_total      NUMERIC := 0;

  -- [Audit-Fix-2] إعداد الضريبة العام
  v_tax_enabled     BOOLEAN := true;
  v_setting_val     TEXT;
BEGIN
  -- ══════════════════════════════════════════════════════════
  -- [SECURITY GUARD]
  -- ══════════════════════════════════════════════════════════
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  IF NOT check_permission(p_user_id, 'procurement.invoices.receive') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية تسجيل استلام فواتير الشراء';
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- [Audit-Fix-2] جلب إعداد الضريبة العام من company_settings
  --    المفتاح المفضّل: purchases.tax_enabled
  --    Fallback: sales.tax_enabled (إعداد مشترك)
  -- ══════════════════════════════════════════════════════════
  SELECT value INTO v_setting_val
  FROM company_settings
  WHERE key = 'purchases.tax_enabled'
  LIMIT 1;

  IF v_setting_val IS NULL THEN
    -- Fallback للإعداد المشترك مع المبيعات
    SELECT value INTO v_setting_val
    FROM company_settings
    WHERE key = 'sales.tax_enabled'
    LIMIT 1;
  END IF;

  -- بالتفسير الأكثر أماناً: إذا لم يُعثر على الإعداد → ضريبة مُفعَّلة (conservative)
  v_tax_enabled := COALESCE(v_setting_val, 'true') = 'true';

  -- ══════════════════════════════════════════════════════════
  -- 1. قفل الفاتورة
  -- ══════════════════════════════════════════════════════════
  SELECT * INTO v_invoice
  FROM purchase_invoices
  WHERE id = p_invoice_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'فاتورة الشراء غير موجودة: %', p_invoice_id;
  END IF;

  IF v_invoice.status != 'draft' THEN
    RAISE EXCEPTION 'لا يمكن تسجيل الاستلام — الفاتورة في حالة: %. يجب أن تكون (draft)',
      v_invoice.status;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM purchase_invoice_items
    WHERE invoice_id = p_invoice_id AND received_quantity > 0
  ) THEN
    RAISE EXCEPTION 'لا توجد بنود مستلمة — سجّل الكميات المستلمة أولاً';
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- 2. حساب قاعدة توزيع مصاريف الشحن
  --    Primary:  بالقيمة الصافية
  --    Fallback: بالكمية (لو كل البنود بخصم 100%)
  -- ══════════════════════════════════════════════════════════
  SELECT
    COALESCE(SUM(
      received_quantity * unit_price * (1 - COALESCE(discount_rate, 0) / 100.0)
    ), 0),
    COALESCE(SUM(received_quantity), 0)
  INTO v_total_value, v_total_qty
  FROM purchase_invoice_items
  WHERE invoice_id = p_invoice_id AND received_quantity > 0;

  IF v_total_value = 0 AND v_total_qty > 0 THEN
    v_use_qty_basis := true;
  ELSIF v_total_value = 0 AND v_total_qty = 0 THEN
    RAISE EXCEPTION 'لا يمكن توزيع مصاريف الشحن — الكمية الإجمالية المستلمة صفر';
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- 3. معالجة كل بند: حساب التكاليف + تحديث المخزون
  -- ══════════════════════════════════════════════════════════
  FOR v_item IN
    SELECT * FROM purchase_invoice_items
    WHERE invoice_id = p_invoice_id
    ORDER BY product_id ASC  -- [DEADLOCK FIX] ترتيب ثابت لمنع الاختناق
  LOOP
    IF v_item.received_quantity <= 0 THEN CONTINUE; END IF;

    -- ─── تكلفة البند الصافية ───
    v_net_cost := v_item.received_quantity
                * v_item.unit_price
                * (1 - COALESCE(v_item.discount_rate, 0) / 100.0);

    -- ─── حصة الشحن ───
    IF COALESCE(v_invoice.landed_costs, 0) = 0 THEN
      v_landed_share := 0;
    ELSIF v_use_qty_basis THEN
      v_landed_share := v_invoice.landed_costs * (v_item.received_quantity / v_total_qty);
    ELSE
      v_item_value   := v_net_cost;         -- هو نفسه الـ net_cost
      v_landed_share := v_invoice.landed_costs * (v_item_value / v_total_value);
    END IF;

    v_true_net_cost := COALESCE(v_net_cost, 0) + COALESCE(v_landed_share, 0);

    -- ─── [Fix-1] تراكم الإجماليات للتحديث اللاحق ─────────────
    v_recv_subtotal := v_recv_subtotal
                     + (v_item.received_quantity * v_item.unit_price);
    v_recv_discount := v_recv_discount
                     + (v_item.received_quantity * v_item.unit_price
                        * COALESCE(v_item.discount_rate, 0) / 100.0);

    -- [Audit-Fix-2] الضريبة فقط لو مُفعَّلة في إعدادات الشركة
    IF v_tax_enabled THEN
      v_recv_tax := v_recv_tax
                  + (v_net_cost * COALESCE(v_item.tax_rate, 0) / 100.0);
    END IF;

    -- ─── تحويل الكمية للوحدة الأساسية ───
    IF v_item.unit_id IS NOT NULL THEN
      v_base_qty := get_base_quantity(v_item.product_id, v_item.unit_id, v_item.received_quantity);
    ELSE
      v_base_qty := v_item.received_quantity;
    END IF;

    v_base_unit_cost := CASE WHEN v_base_qty > 0 THEN v_true_net_cost / v_base_qty ELSE 0 END;

    -- ─── تحديث WAC + تسجيل حركة دخول ───
    PERFORM update_stock_wac(
      v_invoice.warehouse_id,
      v_item.product_id,
      v_base_qty,
      v_base_unit_cost,
      'in',
      'purchase_order',
      p_invoice_id,
      p_user_id
    );

    -- ─── حفظ التكاليف في بند الفاتورة ───
    UPDATE purchase_invoice_items
    SET
      net_cost          = ROUND(v_net_cost, 4),
      landed_cost_share = ROUND(v_landed_share, 4),
      true_net_cost     = ROUND(v_true_net_cost, 4)
    WHERE id = v_item.id;

    -- ─── تحديث آخر سعر شراء ───
    -- [Audit-Fix-1] نحفظ السعر التجاري الصافي حصراً (unit_price × (1 - discount%))
    --   بدون landed costs لمنع التضخم السعري الوهمي في الفواتير القادمة
    v_commercial_unit_price := CASE
      WHEN v_base_qty > 0
      THEN (v_net_cost / v_base_qty)   -- net_cost = qty * unit_price * (1-disc)
                                        -- مقسوماً على الوحدة الأساسية
      ELSE v_item.unit_price * (1 - COALESCE(v_item.discount_rate, 0) / 100.0)
    END;

    UPDATE products
    SET last_purchase_price = ROUND(v_commercial_unit_price, 4)
    WHERE id = v_item.product_id;

  END LOOP;

  -- ══════════════════════════════════════════════════════════
  -- [Fix-1] 4. إعادة حساب إجماليات رأسية الفاتورة
  --    بناءً على ما استُلم فعلياً لا ما طُلب أصلاً
  --    total = (subtotal - discount) + tax + landed_costs
  -- ══════════════════════════════════════════════════════════
  v_recv_total := (v_recv_subtotal - v_recv_discount)
               + v_recv_tax
               + COALESCE(v_invoice.landed_costs, 0);

  UPDATE purchase_invoices
  SET
    subtotal        = ROUND(v_recv_subtotal, 2),
    discount_amount = ROUND(v_recv_discount, 2),
    tax_amount      = ROUND(v_recv_tax,      2),
    total_amount    = ROUND(v_recv_total,    2),
    -- ضبط paid_amount لو كانت تتجاوز الإجمالي الجديد (حماية)
    paid_amount     = LEAST(COALESCE(paid_amount, 0), ROUND(v_recv_total, 2)),
    status          = 'received',
    received_by     = p_user_id,
    received_at     = now(),
    updated_at      = now()
  WHERE id = p_invoice_id;

END; $$;

-- FUNCTION bill_purchase_invoice from 15_procurement_core_rpcs.sql:255
CREATE OR REPLACE FUNCTION bill_purchase_invoice(
  p_invoice_id     UUID,
  p_user_id        UUID,
  p_vault_id       UUID    DEFAULT NULL,
  p_payment_method TEXT    DEFAULT NULL
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_invoice         purchase_invoices%ROWTYPE;
  v_supplier_name   TEXT;
  v_vault_type      TEXT;
  v_credit_account  TEXT;   -- حساب دائن للسداد (1110/1120/1130 أو 2110 للشيك)
  v_is_cheque       BOOLEAN := false;

  v_inventory_dr    NUMERIC;
  v_tax_dr          NUMERIC;
  v_ap_cr           NUMERIC;

  v_bill_lines      JSONB := '[]'::JSONB;
  v_payment_lines   JSONB := '[]'::JSONB;

  -- [Fix-2] UUID حركة الخزنة → يُستخدم كـ source_id في دفتر الموردين
  v_txn_id          UUID;
BEGIN
  -- ══════════════════════════════════════════════════════════
  -- [SECURITY GUARD]
  -- ══════════════════════════════════════════════════════════
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  IF NOT check_permission(p_user_id, 'procurement.invoices.bill') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية الاعتماد المالي لفواتير الشراء';
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- 1. قفل الفاتورة
  -- ══════════════════════════════════════════════════════════
  SELECT * INTO v_invoice
  FROM purchase_invoices
  WHERE id = p_invoice_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'فاتورة الشراء غير موجودة: %', p_invoice_id;
  END IF;

  IF v_invoice.status != 'received' THEN
    RAISE EXCEPTION 'لا يمكن الاعتماد المالي — الفاتورة في حالة: %. يجب أن تكون (received)',
      v_invoice.status;
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- 2. تحقق من الدفع الفوري (إن طُلب)
  -- ══════════════════════════════════════════════════════════
  IF p_vault_id IS NOT NULL OR p_payment_method = 'cheque' THEN
    IF NOT check_permission(p_user_id, 'procurement.invoices.pay') THEN
      RAISE EXCEPTION 'ليس لديك صلاحية سداد فواتير الموردين';
    END IF;
  END IF;

  -- [Fix-3] الشيك: تحديد نوع السداد
  v_is_cheque := (COALESCE(p_payment_method, '') = 'cheque');

  IF NOT v_is_cheque AND p_vault_id IS NOT NULL THEN
    -- سداد نقدي/بنكي: تحديد الحساب من نوع الخزنة
    SELECT type INTO v_vault_type FROM vaults WHERE id = p_vault_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'الخزنة المحددة غير موجودة: %', p_vault_id;
    END IF;
    v_credit_account := CASE v_vault_type
      WHEN 'cash'          THEN '1110'
      WHEN 'bank'          THEN '1120'
      WHEN 'mobile_wallet' THEN '1130'
      ELSE '1110'
    END;
  ELSIF v_is_cheque THEN
    -- [Fix-3] الشيك: الحساب الدائن = 2110 (أوراق دفع - شيكات موردين)
    v_credit_account := '2110';
  END IF;

  SELECT name INTO v_supplier_name FROM suppliers WHERE id = v_invoice.supplier_id;

  -- ══════════════════════════════════════════════════════════
  -- 3. مبالغ قيد الفاتورة
  -- ══════════════════════════════════════════════════════════
  v_inventory_dr := COALESCE(v_invoice.subtotal, 0)
                  - COALESCE(v_invoice.discount_amount, 0)
                  + COALESCE(v_invoice.landed_costs, 0);
  v_tax_dr       := COALESCE(v_invoice.tax_amount, 0);
  v_ap_cr        := COALESCE(v_invoice.total_amount, 0);

  IF ABS((v_inventory_dr + v_tax_dr) - v_ap_cr) > 0.01 THEN
    RAISE EXCEPTION
      'عدم توازن في القيد: DR_مخزون(%) + DR_ضريبة(%) ≠ CR_موردون(%). راجع الأرقام المالية.',
      v_inventory_dr, v_tax_dr, v_ap_cr;
  END IF;

  IF v_ap_cr <= 0 THEN
    RAISE EXCEPTION 'إجمالي الفاتورة يجب أن يكون أكبر من صفر';
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- 4. قيد الفاتورة: DR:1300 + DR:1510 → CR:2100
  -- ══════════════════════════════════════════════════════════
  v_bill_lines := v_bill_lines || jsonb_build_object(
    'account_code', '1300',
    'debit',        v_inventory_dr, 'credit', 0,
    'description',  'بضاعة مشتراه — ' || COALESCE(v_invoice.number, '')
                    || ' / ' || COALESCE(v_supplier_name, '')
  );

  IF v_tax_dr > 0 THEN
    v_bill_lines := v_bill_lines || jsonb_build_object(
      'account_code', '1510',
      'debit',        v_tax_dr, 'credit', 0,
      'description',  'ضريبة مدخلات — ' || COALESCE(v_invoice.number, '')
    );
  END IF;

  v_bill_lines := v_bill_lines || jsonb_build_object(
    'account_code', '2100',
    'debit',        0, 'credit', v_ap_cr,
    'description',  'التزام مورد — ' || COALESCE(v_supplier_name, '')
                    || ' / ' || COALESCE(v_invoice.number, '')
  );

  PERFORM create_manual_journal_entry(
    'قيد شراء — فاتورة ' || COALESCE(v_invoice.number, ''),
    CURRENT_DATE, 'purchase_order', p_invoice_id, v_bill_lines, p_user_id
  );

  -- ══════════════════════════════════════════════════════════
  -- 5. دفتر الموردين — AP Credit (الالتزام)
  -- ══════════════════════════════════════════════════════════
  INSERT INTO supplier_ledger (
    supplier_id, type,     amount,  source_type,     source_id,
    description,           created_by
  ) VALUES (
    v_invoice.supplier_id, 'credit', v_ap_cr, 'purchase_order', p_invoice_id,
    'فاتورة مشتريات — ' || COALESCE(v_invoice.number, ''),
    p_user_id
  );

  -- ══════════════════════════════════════════════════════════
  -- 6. ساق الدفع الفوري (Atomic Payment Leg)
  -- ══════════════════════════════════════════════════════════
  IF p_vault_id IS NOT NULL OR v_is_cheque THEN

    IF v_is_cheque THEN
      -- ─── [Fix-3] مسار الشيك: لا حركة في الخزينة ────────────
      -- نولّد UUID فريداً ليكون مرجعاً في دفتر الموردين
      v_txn_id := gen_random_uuid();

      -- قيد السداد: DR:2100 → CR:2110 (أوراق دفع)
      v_payment_lines := jsonb_build_array(
        jsonb_build_object(
          'account_code', '2100',
          'debit',        v_ap_cr, 'credit', 0,
          'description',  'تسوية ذمم مورد بشيك — ' || COALESCE(v_supplier_name, '')
        ),
        jsonb_build_object(
          'account_code', '2110',
          'debit',        0, 'credit', v_ap_cr,
          'description',  'شيك مُصدر للمورد — ' || COALESCE(v_invoice.number, '')
        )
      );

    ELSE
      -- ─── [Fix-2] مسار نقدي/بنكي: سحب من الخزينة ────────────
      -- نستقبل UUID الحركة لاستخدامه كـ source_id في دفتر الموردين
      v_txn_id := add_vault_transaction(
        p_vault_id,
        'vendor_payment',
        v_ap_cr,
        'purchase_order',
        p_invoice_id,
        'سداد فاتورة مورد — ' || COALESCE(v_supplier_name, '')
          || ' / ' || COALESCE(v_invoice.number, ''),
        p_user_id
      );

      -- قيد السداد: DR:2100 → CR:خزينة
      v_payment_lines := jsonb_build_array(
        jsonb_build_object(
          'account_code', '2100',
          'debit',        v_ap_cr, 'credit', 0,
          'description',  'تسوية ذمم مورد — ' || COALESCE(v_supplier_name, '')
        ),
        jsonb_build_object(
          'account_code', v_credit_account,
          'debit',        0, 'credit', v_ap_cr,
          'description',  'سداد نقدي/بنكي — ' || COALESCE(v_invoice.number, '')
        )
      );
    END IF;

    -- قيد السداد المحاسبي (مشترك بين المسارين)
    PERFORM create_manual_journal_entry(
      'سداد مورد — ' || COALESCE(v_invoice.number, ''),
      CURRENT_DATE, 'purchase_order', p_invoice_id, v_payment_lines, p_user_id
    );

    -- ─── [Fix-2] دفتر الموردين — AP Debit (السداد) ───────────
    -- source_id = v_txn_id (UUID الحركة) يضمن عدم التكرار
    INSERT INTO supplier_ledger (
      supplier_id, type,    amount,  source_type, source_id,
      description,          created_by
    ) VALUES (
      v_invoice.supplier_id, 'debit', v_ap_cr, 'payment', v_txn_id,
      'سداد فوري — ' || COALESCE(v_invoice.number, ''),
      p_user_id
    );

    -- ─── تحديث الفاتورة → paid ────────────────────────────────
    UPDATE purchase_invoices
    SET
      status         = 'paid',
      paid_amount    = v_ap_cr,
      vault_id       = p_vault_id,            -- NULL للشيك
      payment_method = COALESCE(p_payment_method, 'cash'),
      billed_by      = p_user_id,
      billed_at      = now(),
      updated_at     = now()
    WHERE id = p_invoice_id;

  ELSE
    -- ─── لا دفع فوري → billed (دين مؤجل) ───────────────────
    UPDATE purchase_invoices
    SET
      status    = 'billed',
      billed_by = p_user_id,
      billed_at = now(),
      updated_at = now()
    WHERE id = p_invoice_id;
  END IF;

END; $$;

-- FUNCTION pay_supplier from 15_procurement_core_rpcs.sql:506
CREATE OR REPLACE FUNCTION pay_supplier(
  p_invoice_id     UUID,
  p_user_id        UUID,
  p_amount         NUMERIC,
  p_payment_method TEXT    DEFAULT 'cash',
  p_vault_id       UUID    DEFAULT NULL,      -- مطلوب لغير الشيكات
  p_notes          TEXT    DEFAULT NULL
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_invoice         purchase_invoices%ROWTYPE;
  v_supplier_name   TEXT;
  v_vault_type      TEXT;
  v_credit_account  TEXT;
  v_is_cheque       BOOLEAN := false;
  v_outstanding     NUMERIC;
  v_payment_lines   JSONB;

  -- [Fix-2] UUID حركة الخزينة للتوحيد مع دفتر الموردين
  v_txn_id          UUID;

  -- [AUDIT FIX] فرق التقريب عند إغلاق الفاتورة بالسماحية
  v_rounding_diff   NUMERIC;
BEGIN
  -- ══════════════════════════════════════════════════════════
  -- [SECURITY GUARD]
  -- ══════════════════════════════════════════════════════════
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  IF NOT check_permission(p_user_id, 'procurement.invoices.pay') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية سداد فواتير الموردين';
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- 1. قفل وتحقق
  -- ══════════════════════════════════════════════════════════
  SELECT * INTO v_invoice
  FROM purchase_invoices
  WHERE id = p_invoice_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'فاتورة الشراء غير موجودة';
  END IF;

  IF v_invoice.status != 'billed' THEN
    RAISE EXCEPTION 'لا يمكن السداد — الفاتورة في حالة: %. يجب أن تكون (billed)', v_invoice.status;
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'مبلغ السداد يجب أن يكون أكبر من صفر';
  END IF;

  v_outstanding := v_invoice.total_amount - COALESCE(v_invoice.paid_amount, 0);

  IF p_amount > v_outstanding + 0.01 THEN
    RAISE EXCEPTION 'مبلغ السداد (%) يتجاوز المتبقي (%)', p_amount, v_outstanding;
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- 2. تحديد مسار الدفع
  -- ══════════════════════════════════════════════════════════
  v_is_cheque := (COALESCE(p_payment_method, '') = 'cheque');

  IF NOT v_is_cheque THEN
    IF p_vault_id IS NULL THEN
      RAISE EXCEPTION 'يجب تحديد الخزينة للسداد النقدي/البنكي';
    END IF;
    SELECT type INTO v_vault_type FROM vaults WHERE id = p_vault_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'الخزينة غير موجودة: %', p_vault_id;
    END IF;
    v_credit_account := CASE v_vault_type
      WHEN 'cash'          THEN '1110'
      WHEN 'bank'          THEN '1120'
      WHEN 'mobile_wallet' THEN '1130'
      ELSE '1110'
    END;
  ELSE
    -- [Fix-3] الشيك
    v_credit_account := '2110';
  END IF;

  SELECT name INTO v_supplier_name FROM suppliers WHERE id = v_invoice.supplier_id;

  -- ══════════════════════════════════════════════════════════
  -- 3. معالجة حركة الدفع
  -- ══════════════════════════════════════════════════════════
  IF v_is_cheque THEN
    -- [Fix-3] لا حركة في الخزينة — نولّد UUID للمرجعية
    v_txn_id := gen_random_uuid();
  ELSE
    -- [Fix-2] سحب من الخزينة + استقبال UUID الحركة
    v_txn_id := add_vault_transaction(
      p_vault_id,
      'vendor_payment',
      p_amount,
      'purchase_order',
      p_invoice_id,
      COALESCE(p_notes, 'سداد مورد — ' || COALESCE(v_supplier_name, '')),
      p_user_id
    );
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- 4. القيد المحاسبي: DR:2100 → CR:خزينة أو CR:2110
  -- ══════════════════════════════════════════════════════════
  v_payment_lines := jsonb_build_array(
    jsonb_build_object(
      'account_code', '2100',
      'debit',        p_amount, 'credit', 0,
      'description',  'تسوية ذمم مورد — ' || COALESCE(v_supplier_name, '')
    ),
    jsonb_build_object(
      'account_code', v_credit_account,
      'debit',        0, 'credit', p_amount,
      'description',
      CASE WHEN v_is_cheque
        THEN 'شيك مُصدر — ' || COALESCE(v_invoice.number, '')
        ELSE 'سداد نقدي/بنكي — ' || COALESCE(v_invoice.number, '')
      END
    )
  );

  PERFORM create_manual_journal_entry(
    'سداد مورد — ' || COALESCE(v_invoice.number, ''),
    CURRENT_DATE, 'purchase_order', p_invoice_id, v_payment_lines, p_user_id
  );

  -- ══════════════════════════════════════════════════════════
  -- [Fix-2] 5. دفتر الموردين — AP Debit
  --    source_id = v_txn_id (UUID فريد) يمنع تكرار القيد
  -- ══════════════════════════════════════════════════════════
  INSERT INTO supplier_ledger (
    supplier_id, type,    amount,  source_type, source_id,
    description,          created_by
  ) VALUES (
    v_invoice.supplier_id, 'debit', p_amount, 'payment', v_txn_id,
    COALESCE(p_notes, 'سداد — ' || COALESCE(v_invoice.number, '')),
    p_user_id
  );

  -- ══════════════════════════════════════════════════════════
  -- 6. تحديث الفاتورة
  -- ══════════════════════════════════════════════════════════
  UPDATE purchase_invoices
  SET
    paid_amount    = ROUND(COALESCE(paid_amount, 0) + p_amount, 2),
    vault_id       = COALESCE(p_vault_id, vault_id),     -- يحتفظ بالخزينة الأولى للشيك
    payment_method = p_payment_method,
    status = CASE
               WHEN (COALESCE(paid_amount, 0) + p_amount) >= total_amount - 0.01
               THEN 'paid'
               ELSE 'billed'
             END,
    updated_at = now()
  WHERE id = p_invoice_id;

  -- ══════════════════════════════════════════════════════════
  -- [AUDIT FIX] 7. تسوية فروق التقريب تلقائياً
  --    عند إغلاق فاتورة بالسماحية (مثلاً دفع 999.99 من 1000.00)
  --    نُنشئ قيد بالفارق (0.01) لحساب فروق التقريب (5900)
  --    لمنع تراكم أرصدة وهمية في حساب ذمم الموردين (2100)
  -- ══════════════════════════════════════════════════════════
  v_rounding_diff := v_invoice.total_amount - (COALESCE(v_invoice.paid_amount, 0) + p_amount);

  IF v_rounding_diff > 0 AND v_rounding_diff <= 0.01 THEN
    -- سداد فارق التقريب تلقائياً في دفتر الأستاذ
    PERFORM create_manual_journal_entry(
      'تسوية فروق تقريب — فاتورة ' || COALESCE(v_invoice.number, ''),
      CURRENT_DATE, 'purchase_order', p_invoice_id,
      jsonb_build_array(
        jsonb_build_object(
          'account_code', '2100',
          'debit', ROUND(v_rounding_diff, 2), 'credit', 0,
          'description', 'تسوية فرق تقريب — ذمم مورد / ' || COALESCE(v_supplier_name, '')
        ),
        jsonb_build_object(
          'account_code', '5900',
          'debit', 0, 'credit', ROUND(v_rounding_diff, 2),
          'description', 'فروق تقريب — سداد مورد / ' || COALESCE(v_invoice.number, '')
        )
      ),
      p_user_id
    );

    -- تحديث دفتر الموردين بالفارق
    INSERT INTO supplier_ledger (
      supplier_id, type, amount, source_type, source_id, description, created_by
    ) VALUES (
      v_invoice.supplier_id, 'debit', ROUND(v_rounding_diff, 2),
      'adjustment', gen_random_uuid(),
      'تسوية فرق تقريب — ' || COALESCE(v_invoice.number, ''),
      p_user_id
    );
  END IF;

END; $$;

-- FUNCTION generate_purchase_return_number from 16_procurement_returns_and_cancellations.sql:172
CREATE OR REPLACE FUNCTION generate_purchase_return_number()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.number IS NULL OR NEW.number = '' THEN
    NEW.number := 'PRT-' || to_char(CURRENT_DATE, 'YYYYMMDD')
               || '-' || lpad(nextval('purchase_return_seq')::text, 4, '0');
  END IF;
  RETURN NEW;
END; $$;

-- FUNCTION cancel_purchase_invoice from 16_procurement_returns_and_cancellations.sql:304
CREATE OR REPLACE FUNCTION cancel_purchase_invoice(
  p_invoice_id UUID,
  p_user_id    UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_invoice          purchase_invoices%ROWTYPE;
  v_item             RECORD;
  v_stock_qty        NUMERIC;
  v_base_qty         NUMERIC;

  -- [Bug-5] تتبع COGS الفعلي (qty × WAC) من deduct_stock_at_wac
  v_item_cogs        NUMERIC;
  v_total_cogs       NUMERIC := 0;

  -- [Bug-2] الأرقام التاريخية من رأسية الفاتورة — لا إعادة حساب
  v_original_inv_dr  NUMERIC;  -- subtotal - discount + landed
  v_tax_cr           NUMERIC;  -- tax_amount كما سُجّل
  v_ap_dr            NUMERIC;  -- total_amount كما سُجّل → DR:2100

  -- [Bug-5] فرق WAC الفعلي vs. التكلفة الأصلية → ±5300
  v_variance         NUMERIC;

  v_supplier_name    TEXT;
  v_journal_lines    JSONB := '[]'::JSONB;
BEGIN
  -- ══ SECURITY GUARD ══════════════════════════════════════════
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  IF NOT check_permission(p_user_id, 'procurement.invoices.cancel') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية إلغاء فواتير الشراء';
  END IF;

  -- ══ 1. قفل الفاتورة ═════════════════════════════════════════
  SELECT * INTO v_invoice
  FROM purchase_invoices
  WHERE id = p_invoice_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'فاتورة الشراء غير موجودة: %', p_invoice_id;
  END IF;

  -- المسودة: إلغاء فوري بلا محركات
  IF v_invoice.status = 'draft' THEN
    UPDATE purchase_invoices SET status = 'cancelled', updated_at = now()
    WHERE id = p_invoice_id;
    RETURN;
  END IF;

  IF v_invoice.status = 'cancelled' THEN
    RAISE EXCEPTION 'الفاتورة ملغاة بالفعل';
  END IF;

  IF v_invoice.status = 'paid' THEN
    RAISE EXCEPTION 'لا يمكن إلغاء فاتورة مسددة بالكامل — استخدم مرتجع المشتريات';
  END IF;

  IF COALESCE(v_invoice.paid_amount, 0) > 0 THEN
    RAISE EXCEPTION
      'لا يمكن الإلغاء — تم سداد % ج.م. ألغِ الدفع أولاً أو استخدم مرتجع المشتريات',
      v_invoice.paid_amount;
  END IF;

  IF v_invoice.status NOT IN ('received', 'billed') THEN
    RAISE EXCEPTION 'حالة الفاتورة غير قابلة للإلغاء: %', v_invoice.status;
  END IF;

  -- ══ 2. الحراسة المخزنية الصارمة ═════════════════════════════
  --    تجاهل allow_negative_stock | قفل FOR UPDATE لكل صف
  FOR v_item IN
    SELECT pii.*
    FROM purchase_invoice_items pii
    WHERE pii.invoice_id = p_invoice_id
      AND pii.received_quantity > 0
    ORDER BY pii.product_id ASC  -- [DEADLOCK FIX]
  LOOP
    v_base_qty := CASE
      WHEN v_item.unit_id IS NOT NULL
      THEN get_base_quantity(v_item.product_id, v_item.unit_id, v_item.received_quantity)
      ELSE v_item.received_quantity
    END;

    SELECT quantity INTO v_stock_qty
    FROM stock
    WHERE warehouse_id = v_invoice.warehouse_id
      AND product_id   = v_item.product_id
    FOR UPDATE;

    IF v_stock_qty IS NULL THEN
      RAISE EXCEPTION
        'لا يوجد سجل مخزون للمنتج % في المخزن % — لا يمكن الإلغاء',
        v_item.product_id, v_invoice.warehouse_id;
    END IF;

    IF v_stock_qty < v_base_qty THEN
      RAISE EXCEPTION
        'لا يمكن الإلغاء: الكمية المتوفرة (%) أقل من المستلمة (%) للمنتج %. يُرجَّح بيع أو نقل هذه البضاعة — استخدم مرتجع المشتريات.',
        v_stock_qty, v_base_qty, v_item.product_id;
    END IF;
  END LOOP;

  -- ══ 3. عكس المخزون ══════════════════════════════════════════
  --    [Bug-5] استقبال COGS الفعلي وتراكمه
  FOR v_item IN
    SELECT pii.*
    FROM purchase_invoice_items pii
    WHERE pii.invoice_id = p_invoice_id
      AND pii.received_quantity > 0
    ORDER BY pii.product_id ASC  -- [DEADLOCK FIX]
  LOOP
    v_base_qty := CASE
      WHEN v_item.unit_id IS NOT NULL
      THEN get_base_quantity(v_item.product_id, v_item.unit_id, v_item.received_quantity)
      ELSE v_item.received_quantity
    END;

    -- [Bug-5] نستقبل COGS = qty × WAC الحالي (لا التاريخي)
    v_item_cogs := deduct_stock_at_wac(
      v_invoice.warehouse_id,
      v_item.product_id,
      v_base_qty,
      'purchase_cancellation',
      'purchase_cancellation',
      p_invoice_id,
      p_user_id
    );

    v_total_cogs := v_total_cogs + COALESCE(v_item_cogs, 0);
  END LOOP;

  -- ══ 4. القيد المحاسبي العكسي ════════════════════════════════
  --    [Bug-1] يعمل فقط إذا كانت الفاتورة billed
  IF v_invoice.status = 'billed' THEN

    -- [Bug-2] الأرقام التاريخية من رأسية الفاتورة
    v_original_inv_dr := COALESCE(v_invoice.subtotal, 0)
                       - COALESCE(v_invoice.discount_amount, 0)
                       + COALESCE(v_invoice.landed_costs, 0);
    v_tax_cr          := COALESCE(v_invoice.tax_amount, 0);
    v_ap_dr           := COALESCE(v_invoice.total_amount, 0);

    -- [Bug-5] فرق WAC الفعلي مقابل التكلفة الأصلية
    v_variance := ROUND(v_total_cogs, 2) - ROUND(v_original_inv_dr, 2);

    -- سلامة البيانات المسجّلة في رأسية الفاتورة
    IF ABS(v_ap_dr - (v_original_inv_dr + v_tax_cr)) > 0.02 THEN
      RAISE EXCEPTION
        'عدم توازن في بيانات الفاتورة: AP(%) ≠ Inv(%) + Tax(%). راجع الفاتورة يدوياً.',
        v_ap_dr, v_original_inv_dr, v_tax_cr;
    END IF;

    IF v_ap_dr <= 0 THEN
      RAISE EXCEPTION 'إجمالي الفاتورة يجب أن يكون أكبر من صفر قبل الإلغاء';
    END IF;

    SELECT name INTO v_supplier_name FROM suppliers WHERE id = v_invoice.supplier_id;

    -- DR: 2100 ← إجمالي الالتزام الأصلي (تاريخي)
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', '2100',
      'debit',        ROUND(v_ap_dr, 2), 'credit', 0,
      'description',  'عكس التزام مورد — إلغاء ' || COALESCE(v_invoice.number, '')
    );

    -- CR: 1300 ← WAC الفعلي المسحوب (لا التاريخي) [Bug-5]
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', '1300',
      'debit',        0, 'credit', ROUND(v_total_cogs, 2),
      'description',  'عكس مخزون بالـ WAC الحالي — إلغاء ' || COALESCE(v_invoice.number, '')
    );

    -- CR: 1510 ← ضريبة المدخلات (تاريخية) [Bug-2]
    IF v_tax_cr > 0.001 THEN
      v_journal_lines := v_journal_lines || jsonb_build_object(
        'account_code', '1510',
        'debit',        0, 'credit', ROUND(v_tax_cr, 2),
        'description',  'عكس ضريبة مدخلات — إلغاء ' || COALESCE(v_invoice.number, '')
      );
    END IF;

    -- ±5300 ← فرق WAC vs. التكلفة الأصلية [Bug-5]
    --   موجب: WAC ارتفع  → خسارة     → DR:5300
    --   سالب: WAC انخفض → مكسب      → CR:5300
    IF ABS(v_variance) > 0.005 THEN
      IF v_variance > 0 THEN
        v_journal_lines := v_journal_lines || jsonb_build_object(
          'account_code', '5300',
          'debit',        ROUND(v_variance, 2), 'credit', 0,
          'description',  'فرق إلغاء — WAC ارتفع عن التكلفة الأصلية / '
                          || COALESCE(v_invoice.number, '')
        );
      ELSE
        v_journal_lines := v_journal_lines || jsonb_build_object(
          'account_code', '5300',
          'debit',        0, 'credit', ROUND(ABS(v_variance), 2),
          'description',  'فرق إلغاء — WAC انخفض عن التكلفة الأصلية / '
                          || COALESCE(v_invoice.number, '')
        );
      END IF;
    END IF;

    PERFORM create_manual_journal_entry(
      'قيد إلغاء فاتورة مشتريات — ' || COALESCE(v_invoice.number, '')
      || ' / ' || COALESCE(v_supplier_name, ''),
      CURRENT_DATE, 'purchase_cancellation', p_invoice_id,
      v_journal_lines, p_user_id
    );

    -- ══ 5. عكس دفتر الموردين ══════════════════════════════════
    INSERT INTO supplier_ledger (
      supplier_id, type, amount, source_type, source_id, description, created_by
    ) VALUES (
      v_invoice.supplier_id, 'debit', ROUND(v_ap_dr, 2),
      'purchase_cancellation', p_invoice_id,
      'إلغاء فاتورة مشتريات — ' || COALESCE(v_invoice.number, ''),
      p_user_id
    )
    ON CONFLICT (source_type, source_id) DO NOTHING;

  END IF;  -- END IF billed

  -- ══ 6. تأكيد الإلغاء ════════════════════════════════════════
  UPDATE purchase_invoices
  SET status = 'cancelled', updated_at = now()
  WHERE id = p_invoice_id;

END; $$;

-- FUNCTION confirm_purchase_return from 16_procurement_returns_and_cancellations.sql:548
CREATE OR REPLACE FUNCTION confirm_purchase_return(
  p_return_id UUID,
  p_user_id   UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_return         purchase_returns%ROWTYPE;
  v_item           RECORD;
  v_base_qty       NUMERIC;

  -- [Bug-3] إعداد الضريبة
  v_tax_enabled    BOOLEAN := true;
  v_setting_val    TEXT;

  -- [Bug-4] مجاميع منفصلة
  v_total_subtotal    NUMERIC := 0;  -- SUM(qty × unit_price) الخام
  v_total_discount    NUMERIC := 0;  -- SUM(قيمة الخصم)
  v_total_ap_net      NUMERIC := 0;  -- subtotal - discount
  v_total_tax         NUMERIC := 0;  -- ضريبة (0 إذا معطّلة)
  v_total_ap_gross    NUMERIC := 0;  -- ap_net + tax → DR:2100

  -- مجاميع القيد
  v_total_cogs        NUMERIC := 0;  -- qty × WAC → CR:1300
  v_total_variance    NUMERIC := 0;  -- cogs - ap_net → ±5300

  -- مستوى البند
  v_item_gross        NUMERIC;
  v_item_discount     NUMERIC;
  v_item_ap_net       NUMERIC;
  v_item_tax          NUMERIC;
  v_item_cogs         NUMERIC;

  v_supplier_name     TEXT;
  v_journal_lines     JSONB := '[]'::JSONB;
BEGIN
  -- ══ SECURITY GUARD ══════════════════════════════════════════
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  IF NOT check_permission(p_user_id, 'procurement.returns.confirm') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية تأكيد مرتجعات الشراء';
  END IF;

  -- ══ [Bug-3] جلب إعداد الضريبة ═══════════════════════════════
  SELECT value INTO v_setting_val
  FROM company_settings WHERE key = 'purchases.tax_enabled' LIMIT 1;

  IF v_setting_val IS NULL THEN
    SELECT value INTO v_setting_val
    FROM company_settings WHERE key = 'sales.tax_enabled' LIMIT 1;
  END IF;

  v_tax_enabled := COALESCE(v_setting_val, 'true') = 'true';

  -- ══ 1. قفل المرتجع ══════════════════════════════════════════
  SELECT * INTO v_return
  FROM purchase_returns
  WHERE id = p_return_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'مرتجع الشراء غير موجود: %', p_return_id;
  END IF;

  IF v_return.status = 'confirmed' THEN
    RAISE EXCEPTION 'المرتجع مؤكد بالفعل: %', v_return.number;
  END IF;

  IF v_return.status != 'draft' THEN
    RAISE EXCEPTION 'لا يمكن تأكيد المرتجع — الحالة: %', v_return.status;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM purchase_return_items WHERE return_id = p_return_id) THEN
    RAISE EXCEPTION 'لا توجد بنود في المرتجع — أضف المنتجات أولاً';
  END IF;

  IF v_return.original_invoice_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM purchase_invoices
      WHERE id = v_return.original_invoice_id AND status IN ('billed', 'paid')
    ) THEN
      RAISE EXCEPTION 'الفاتورة المرتبطة يجب أن تكون في حالة (billed) أو (paid)';
    END IF;
  END IF;

  SELECT name INTO v_supplier_name FROM suppliers WHERE id = v_return.supplier_id;

  -- ══ 2. معالجة كل بند ════════════════════════════════════════
  FOR v_item IN
    SELECT pri.* FROM purchase_return_items pri
    WHERE pri.return_id = p_return_id
    ORDER BY pri.product_id ASC  -- [DEADLOCK FIX]
  LOOP
    v_base_qty := CASE
      WHEN v_item.unit_id IS NOT NULL
      THEN get_base_quantity(v_item.product_id, v_item.unit_id, v_item.quantity)
      ELSE v_item.quantity
    END;

    -- خصم المخزون بالـ WAC الحالي
    v_item_cogs := deduct_stock_at_wac(
      v_return.warehouse_id, v_item.product_id, v_base_qty,
      'purchase_return', 'purchase_return', p_return_id, p_user_id
    );

    -- [Bug-4] قيم AP منفصلة
    v_item_gross    := ROUND(v_item.quantity * COALESCE(v_item.unit_price, 0), 4);
    v_item_discount := ROUND(v_item_gross * COALESCE(v_item.discount_rate, 0) / 100.0, 4);
    v_item_ap_net   := v_item_gross - v_item_discount;

    -- [Bug-3] الضريبة فقط إذا مُفعَّلة
    v_item_tax := CASE
      WHEN v_tax_enabled
      THEN ROUND(v_item_ap_net * COALESCE(v_item.tax_rate, 0) / 100.0, 4)
      ELSE 0
    END;

    v_total_subtotal := v_total_subtotal + v_item_gross;
    v_total_discount := v_total_discount + v_item_discount;
    v_total_ap_net   := v_total_ap_net   + v_item_ap_net;
    v_total_tax      := v_total_tax      + v_item_tax;
    v_total_cogs     := v_total_cogs     + COALESCE(v_item_cogs, 0);
    v_total_variance := v_total_variance + (COALESCE(v_item_cogs, 0) - v_item_ap_net);

    UPDATE purchase_return_items SET
      ap_line_gross    = ROUND(v_item_gross, 4),
      ap_line_discount = ROUND(v_item_discount, 4),
      ap_line_net      = ROUND(v_item_ap_net, 4),
      ap_line_tax      = ROUND(v_item_tax, 4),
      ap_line_total    = ROUND(v_item_ap_net + v_item_tax, 4),
      cogs_value       = ROUND(COALESCE(v_item_cogs, 0), 4),
      wac_variance     = ROUND(COALESCE(v_item_cogs, 0) - v_item_ap_net, 4)
    WHERE id = v_item.id;

  END LOOP;

  -- ══ 3. تحديث رأسية المرتجع [Bug-4] ═════════════════════════
  v_total_ap_gross := ROUND(v_total_ap_net + v_total_tax, 2);

  UPDATE purchase_returns SET
    subtotal        = ROUND(v_total_subtotal, 2),
    discount_amount = ROUND(v_total_discount, 2),
    tax_amount      = ROUND(v_total_tax,      2),
    total_amount    = ROUND(v_total_ap_gross,  2),
    updated_at      = now()
  WHERE id = p_return_id;

  -- ══ 4. القيد المحاسبي (IAS 2) ══════════════════════════════
  -- DR: 2100
  v_journal_lines := v_journal_lines || jsonb_build_object(
    'account_code', '2100',
    'debit',  ROUND(v_total_ap_gross, 2), 'credit', 0,
    'description', 'مرتجع مشتريات — تخفيض ذمة مورد / ' || COALESCE(v_return.number, '')
  );

  -- CR: 1300 (WAC الفعلي)
  v_journal_lines := v_journal_lines || jsonb_build_object(
    'account_code', '1300',
    'debit', 0, 'credit', ROUND(v_total_cogs, 2),
    'description', 'مرتجع مشتريات — إخراج مخزون بالـ WAC / ' || COALESCE(v_return.number, '')
  );

  -- CR: 1510
  IF v_total_tax > 0.001 THEN
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', '1510',
      'debit', 0, 'credit', ROUND(v_total_tax, 2),
      'description', 'عكس ضريبة مدخلات — مرتجع / ' || COALESCE(v_return.number, '')
    );
  END IF;

  -- ±5300
  IF ABS(v_total_variance) > 0.005 THEN
    IF v_total_variance > 0 THEN
      v_journal_lines := v_journal_lines || jsonb_build_object(
        'account_code', '5300',
        'debit', ROUND(v_total_variance, 2), 'credit', 0,
        'description', 'فرق WAC > سعر الإرجاع / ' || COALESCE(v_return.number, '')
      );
    ELSE
      v_journal_lines := v_journal_lines || jsonb_build_object(
        'account_code', '5300',
        'debit', 0, 'credit', ROUND(ABS(v_total_variance), 2),
        'description', 'فرق WAC < سعر الإرجاع / ' || COALESCE(v_return.number, '')
      );
    END IF;
  END IF;

  PERFORM create_manual_journal_entry(
    'قيد مرتجع مشتريات — ' || COALESCE(v_return.number, '')
    || ' / ' || COALESCE(v_supplier_name, ''),
    CURRENT_DATE, 'purchase_return', p_return_id,
    v_journal_lines, p_user_id
  );

  -- ══ 5. دفتر الموردين ════════════════════════════════════════
  INSERT INTO supplier_ledger (
    supplier_id, type, amount, source_type, source_id, description, created_by
  ) VALUES (
    v_return.supplier_id, 'debit', ROUND(v_total_ap_gross, 2),
    'purchase_return', p_return_id,
    'مرتجع مشتريات — ' || COALESCE(v_return.number, ''),
    p_user_id
  )
  ON CONFLICT (source_type, source_id) DO NOTHING;

  -- ══ 6. تأكيد المرتجع ════════════════════════════════════════
  UPDATE purchase_returns SET
    status       = 'confirmed',
    confirmed_by = p_user_id,
    confirmed_at = now(),
    updated_at   = now()
  WHERE id = p_return_id;

END; $$;

-- FUNCTION guard_customer_opening_balance from 60_finance_field_guards.sql:6
CREATE OR REPLACE FUNCTION guard_customer_opening_balance()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.opening_balance IS DISTINCT FROM NEW.opening_balance
     AND current_setting('app.finance_context', true) IS DISTINCT FROM 'opening_balance_adjustment' THEN
    RAISE EXCEPTION 'Direct customer opening balance updates are not allowed';
  END IF;

  RETURN NEW;
END;
$$;

-- FUNCTION guard_supplier_opening_balance from 60_finance_field_guards.sql:26
CREATE OR REPLACE FUNCTION guard_supplier_opening_balance()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.opening_balance IS DISTINCT FROM NEW.opening_balance
     AND current_setting('app.finance_context', true) IS DISTINCT FROM 'opening_balance_adjustment' THEN
    RAISE EXCEPTION 'Direct supplier opening balance updates are not allowed';
  END IF;

  RETURN NEW;
END;
$$;

-- FUNCTION guard_vault_type from 60_finance_field_guards.sql:46
CREATE OR REPLACE FUNCTION guard_vault_type()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.type IS DISTINCT FROM NEW.type
     AND EXISTS (
       SELECT 1
       FROM vault_transactions vt
       WHERE vt.vault_id = OLD.id
     ) THEN
    RAISE EXCEPTION 'Vault type cannot be changed after financial activity exists';
  END IF;

  RETURN NEW;
END;
$$;

-- FUNCTION create_ui_manual_journal_entry from 60_finance_field_guards.sql:70
CREATE OR REPLACE FUNCTION create_ui_manual_journal_entry(
  p_description  TEXT,
  p_entry_date   DATE DEFAULT CURRENT_DATE,
  p_source_type  TEXT DEFAULT 'manual',
  p_source_id    UUID DEFAULT NULL,
  p_lines        JSONB DEFAULT '[]'::JSONB,
  p_user_id      UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_blocked_count INT;
BEGIN
  SELECT COUNT(*)
  INTO v_blocked_count
  FROM jsonb_array_elements(COALESCE(p_lines, '[]'::JSONB)) AS l
  WHERE (l ->> 'account_code') IN ('1200', '2100');

  IF v_blocked_count > 0 THEN
    RAISE EXCEPTION 'Direct posting to control accounts 1200 and 2100 is not allowed from the UI';
  END IF;

  RETURN create_manual_journal_entry(
    p_description,
    p_entry_date,
    p_source_type,
    p_source_id,
    p_lines,
    p_user_id
  );
END;
$$;

-- FUNCTION sync_customer_opening_balance from 61_finance_creation_opening_balance_fix.sql:92
CREATE OR REPLACE FUNCTION sync_customer_opening_balance()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lines  JSONB;
  v_je_id  UUID;
  v_actor  UUID;
BEGIN
  IF COALESCE(NEW.opening_balance, 0) <= 0 THEN
    RETURN NEW;
  END IF;

  -- Safe actor resolution (customers HAS created_by column)
  v_actor := COALESCE(NEW.created_by, auth.uid());

  -- ─── (أ) Subledger: customer_ledger ─────────────────────────
  -- Guard: idempotent — trg_customer_opening_ledger (03) may have
  -- already inserted this if the old trigger was active.
  IF NOT EXISTS (
    SELECT 1 FROM customer_ledger
    WHERE source_type = 'opening_balance'
      AND source_id   = NEW.id
  ) THEN
    INSERT INTO customer_ledger (
      customer_id, type, amount, source_type, source_id, description, created_by
    ) VALUES (
      NEW.id, 'debit', NEW.opening_balance,
      'opening_balance', NEW.id, 'رصيد افتتاحي', v_actor
    );
  END IF;

  -- ─── (ب) General Ledger: journal_entries ────────────────────
  -- Guard: only post GL if no GL entry exists for this customer's opening balance.
  -- Checks journal_entries with source_type='manual' and source_id=customer.id.
  IF NOT EXISTS (
    SELECT 1 FROM journal_entries
    WHERE source_type = 'manual'
      AND source_id   = NEW.id
  ) THEN
    v_lines := jsonb_build_array(
      jsonb_build_object(
        'account_code', '1200',
        'debit',        NEW.opening_balance,
        'credit',       0,
        'description',  'ذمم عملاء — رصيد افتتاحي: ' || NEW.name
      ),
      jsonb_build_object(
        'account_code', '3200',
        'debit',        0,
        'credit',       NEW.opening_balance,
        'description',  'أرباح محتجزة — مقابل رصيد افتتاحي عميل'
      )
    );

    SELECT create_manual_journal_entry(
      'رصيد افتتاحي للعميل: ' || NEW.name,
      CURRENT_DATE,
      'manual',
      NEW.id,
      v_lines,
      v_actor
    ) INTO v_je_id;
  END IF;

  RETURN NEW;
END;
$$;

-- FUNCTION sync_supplier_opening_balance from 61_finance_creation_opening_balance_fix.sql:184
CREATE OR REPLACE FUNCTION sync_supplier_opening_balance()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lines  JSONB;
  v_je_id  UUID;
  v_actor  UUID;
BEGIN
  IF COALESCE(NEW.opening_balance, 0) <= 0 THEN
    RETURN NEW;
  END IF;

  -- Safe actor: suppliers has NO created_by column.
  -- to_jsonb(NEW)->>'created_by' returns NULL (not error) if field absent.
  v_actor := COALESCE(
    (to_jsonb(NEW) ->> 'created_by')::uuid,
    auth.uid()
  );

  -- ─── (أ) Subledger: supplier_ledger ─────────────────────────
  IF NOT EXISTS (
    SELECT 1 FROM supplier_ledger
    WHERE source_type = 'opening_balance'
      AND source_id   = NEW.id
  ) THEN
    INSERT INTO supplier_ledger (
      supplier_id, type, amount, source_type, source_id, description, created_by
    ) VALUES (
      NEW.id, 'credit', NEW.opening_balance,
      'opening_balance', NEW.id, 'رصيد افتتاحي', v_actor
    );
  END IF;

  -- ─── (ب) General Ledger ──────────────────────────────────────
  IF NOT EXISTS (
    SELECT 1 FROM journal_entries
    WHERE source_type = 'manual'
      AND source_id   = NEW.id
  ) THEN
    v_lines := jsonb_build_array(
      jsonb_build_object(
        'account_code', '3200',
        'debit',        NEW.opening_balance,
        'credit',       0,
        'description',  'أرباح محتجزة — مقابل رصيد افتتاحي مورد'
      ),
      jsonb_build_object(
        'account_code', '2100',
        'debit',        0,
        'credit',       NEW.opening_balance,
        'description',  'ذمم دائنة موردين — رصيد افتتاحي: ' || NEW.name
      )
    );

    SELECT create_manual_journal_entry(
      'رصيد افتتاحي للمورد: ' || NEW.name,
      CURRENT_DATE,
      'manual',
      NEW.id,
      v_lines,
      v_actor
    ) INTO v_je_id;
  END IF;

  RETURN NEW;
END;
$$;

-- FUNCTION confirm_payment_receipt from 63_cash_custody_self_confirm.sql:34
CREATE OR REPLACE FUNCTION confirm_payment_receipt(
  p_receipt_id  UUID,
  p_action      TEXT,      -- 'confirm' أو 'reject'
  p_vault_id    UUID,      -- الخزنة أو البنك أو المحفظة (NULL للشيكات والرفض)
  p_reason      TEXT,      -- سبب الرفض (للرفض فقط)
  p_user_id     UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_receipt       payment_receipts%ROWTYPE;
  v_cust_name     TEXT;
  v_debit_account TEXT;
  v_vault_type    TEXT;
  v_is_own_cash_custody BOOLEAN := false;   -- [NEW] للتأكيد الذاتي للنقدي في العهدة الشخصية
BEGIN
  -- [SECURITY GUARD]
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- S3: فحص الصلاحية
  -- [NEW] استثناء العهدة الذاتية: إذا كان الإيصال نقدياً وفي عهدة المستخدم نفسه
  --       يُسمح له بالتأكيد دون الحاجة لـ finance.payments.confirm الإدارية.
  --       الرفض يبقى إدارياً حصراً في جميع الحالات.
  IF p_action = 'confirm' THEN
    SELECT EXISTS (
      SELECT 1
      FROM payment_receipts pr
      JOIN custody_accounts ca ON ca.id = pr.custody_id
      WHERE pr.id        = p_receipt_id
        AND pr.payment_method = 'cash'
        AND pr.custody_id IS NOT NULL
        AND ca.employee_id    = p_user_id
        AND ca.is_active      = true
    ) INTO v_is_own_cash_custody;
  END IF;

  IF NOT v_is_own_cash_custody THEN
    IF NOT check_permission(p_user_id, 'finance.payments.confirm') THEN
      RAISE EXCEPTION 'لا تملك صلاحية مراجعة إيصالات الدفع';
    END IF;
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

    -- ── التحقق من وجهة التحصيل ──────────────────────────────
    -- الشيكات: لا تحتاج vault (تذهب لـ 1210 أوراق قبض)
    -- باقي الطرق: يجب vault أو custody
    IF v_receipt.payment_method != 'cheque' THEN
      IF p_vault_id IS NULL AND v_receipt.custody_id IS NULL THEN
        RAISE EXCEPTION 'يجب تحديد الخزنة أو العهدة لتأكيد هذا الإيصال';
      END IF;
    END IF;

    -- جلب اسم العميل
    SELECT name INTO v_cust_name FROM customers WHERE id = v_receipt.customer_id;

    -- ── R4: تحديد الحساب المدين حسب طريقة الدفع ────────────
    IF v_receipt.payment_method = 'cheque' THEN
      -- الشيكات → أوراق قبض (1210) — لا تدخل خزنة أو عهدة
      v_debit_account := '1210';

    ELSIF v_receipt.custody_id IS NOT NULL THEN
      -- النقدي الميداني (عهدة المندوب)
      v_debit_account := '1400';

    ELSIF p_vault_id IS NOT NULL THEN
      -- تحديد الحساب بناءً على نوع الخزنة/البنك
      SELECT type INTO v_vault_type FROM vaults WHERE id = p_vault_id;
      v_debit_account := CASE v_vault_type
        WHEN 'cash'          THEN '1110'   -- صندوق نقدي
        WHEN 'bank'          THEN '1120'   -- بنك
        WHEN 'mobile_wallet' THEN '1130'   -- محفظة إلكترونية
        ELSE '1110'                        -- fallback
      END;
    ELSE
      -- فحص إضافي (لا يجب الوصول هنا)
      RAISE EXCEPTION 'لا يمكن تحديد الحساب المدين — تحقق من وجهة التحصيل';
    END IF;

    -- ── تسجيل حركة الخزنة أو العهدة (غير الشيكات) ──────────
    IF v_receipt.payment_method = 'cheque' THEN
      -- الشيكات: لا حركة في الخزنة — القيد المحاسبي فقط (1210)
      NULL;

    ELSIF v_receipt.custody_id IS NOT NULL THEN
      -- مسار العهدة (ميداني)
      PERFORM add_custody_transaction(
        v_receipt.custody_id, 'collection', v_receipt.amount,
        NULL, 'payment_receipt', p_receipt_id,
        'تحصيل من ' || COALESCE(v_cust_name, ''),
        p_user_id
      );

    ELSE
      -- مسار الخزنة (نقدي/بنك/محفظة)
      PERFORM add_vault_transaction(
        p_vault_id, 'collection', v_receipt.amount,
        'payment_receipt', p_receipt_id,
        'تحصيل من ' || COALESCE(v_cust_name, ''),
        p_user_id
      );
    END IF;

    -- ── القيد المحاسبي: DR: [حسب الطريقة] → CR: 1200 ────────
    PERFORM create_auto_journal_entry(
      'payment', p_receipt_id,
      'تحصيل ' || v_receipt.payment_method || ' من ' || COALESCE(v_cust_name, ''),
      v_debit_account,
      '1200',   -- ذمم مدينة (عملاء)
      v_receipt.amount,
      p_user_id
    );

    -- ── R4 Core: استدعاء الدالة الذكية للتوزيع ───────────────
    -- تحل محل INSERT اليدوي في customer_ledger
    -- وتُحدّث paid_amount في الفواتير تلقائياً
    PERFORM allocate_payment_to_invoices(
      v_receipt.customer_id,
      v_receipt.amount,
      'payment_receipt',
      p_receipt_id,
      p_user_id,
      v_receipt.sales_order_id   -- الطلب المستهدف (NULL = FIFO على كل الفواتير)
    );

    -- ── تحديث الإيصال ────────────────────────────────────────
    UPDATE payment_receipts
    SET status       = 'confirmed',
        vault_id     = CASE WHEN v_receipt.payment_method != 'cheque' AND v_receipt.custody_id IS NULL
                            THEN p_vault_id ELSE vault_id END,
        reviewed_by  = p_user_id,
        reviewed_at  = now()
    WHERE id = p_receipt_id;

  ELSIF p_action = 'reject' THEN
    -- رفض الإيصال
    -- [NEW] الرفض الذاتي محظور: المندوب لا يرفض إيصاله — يُعاد للإدارة
    IF v_is_own_cash_custody THEN
      RAISE EXCEPTION 'لا يمكنك رفض إيصال مرتبط بعهدتك الشخصية — يجب أن يراجعه المدير المالي';
    END IF;

    UPDATE payment_receipts
    SET status           = 'rejected',
        rejection_reason = p_reason,
        reviewed_by      = p_user_id,
        reviewed_at      = now()
    WHERE id = p_receipt_id;

  ELSE
    RAISE EXCEPTION 'الإجراء يجب أن يكون confirm أو reject';
  END IF;
END; $$;

-- FUNCTION search_customers from 70_missing_indexes_and_search_rpc.sql:167
CREATE OR REPLACE FUNCTION search_customers(
  p_search        TEXT        DEFAULT NULL,
  p_type          TEXT        DEFAULT NULL,
  p_governorate   UUID        DEFAULT NULL,
  p_city          UUID        DEFAULT NULL,
  p_rep_id        UUID        DEFAULT NULL,
  p_is_active     BOOLEAN     DEFAULT NULL,
  p_cursor_ts     TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id     UUID        DEFAULT NULL,
  p_limit         INT         DEFAULT 30
)
RETURNS TABLE (
  id               UUID,
  name             TEXT,
  code             TEXT,
  phone            TEXT,
  mobile           TEXT,
  type             TEXT,
  payment_terms    TEXT,
  credit_limit     NUMERIC,
  current_balance  NUMERIC,
  is_active        BOOLEAN,
  assigned_rep_id  UUID,
  latitude         DOUBLE PRECISION,
  longitude        DOUBLE PRECISION,
  address          TEXT,
  governorate_id   UUID,
  governorate_name TEXT,
  city_id          UUID,
  city_name        TEXT,
  rep_name         TEXT,
  created_at       TIMESTAMPTZ,
  has_more         BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH filtered AS (
    SELECT
      c.id,
      c.name,
      c.code,
      c.phone,
      c.mobile,
      c.type,
      c.payment_terms,
      c.credit_limit,
      c.current_balance,
      c.is_active,
      c.assigned_rep_id,
      c.latitude,
      c.longitude,
      c.address,
      c.governorate_id,
      g.name  AS governorate_name,
      c.city_id,
      ci.name AS city_name,
      p.full_name AS rep_name,
      c.created_at
    FROM customers c
    LEFT JOIN governorates g  ON g.id  = c.governorate_id
    LEFT JOIN cities ci       ON ci.id = c.city_id
    LEFT JOIN profiles p      ON p.id  = c.assigned_rep_id
    WHERE
      (
        p_search IS NULL
        OR c.name   ILIKE '%' || p_search || '%'
        OR c.code   ILIKE '%' || p_search || '%'
        OR c.phone  ILIKE '%' || p_search || '%'
        OR c.mobile ILIKE '%' || p_search || '%'
      )
      AND (p_type        IS NULL OR c.type          = p_type)
      AND (p_governorate IS NULL OR c.governorate_id = p_governorate)
      AND (p_city        IS NULL OR c.city_id        = p_city)
      AND (p_rep_id      IS NULL OR c.assigned_rep_id = p_rep_id)
      AND (p_is_active   IS NULL OR c.is_active      = p_is_active)
      -- Keyset cursor
      AND (
        p_cursor_ts IS NULL
        OR c.created_at < p_cursor_ts
        OR (c.created_at = p_cursor_ts AND c.id < p_cursor_id)
      )
    ORDER BY c.created_at DESC, c.id DESC
    LIMIT p_limit + 1
  )
  SELECT
    id, name, code, phone, mobile, type,
    payment_terms, credit_limit, current_balance, is_active,
    assigned_rep_id, latitude, longitude, address,
    governorate_id, governorate_name, city_id, city_name,
    rep_name, created_at,
    (COUNT(*) OVER () > p_limit) AS has_more
  FROM filtered
  LIMIT p_limit;
$$;

-- FUNCTION search_sales_orders from 71_sales_filter_enhancements.sql:78
CREATE OR REPLACE FUNCTION search_sales_orders(
  p_search          TEXT        DEFAULT NULL,
  p_status          TEXT        DEFAULT NULL,
  p_rep_id          UUID        DEFAULT NULL,
  p_date_from       DATE        DEFAULT NULL,
  p_date_to         DATE        DEFAULT NULL,
  p_payment_terms   TEXT        DEFAULT NULL,
  p_governorate_id  UUID        DEFAULT NULL,
  p_city_id         UUID        DEFAULT NULL,
  p_cursor_ts       TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id       UUID        DEFAULT NULL,
  p_limit           INT         DEFAULT 25
)
RETURNS TABLE (
  id               UUID,
  order_number     TEXT,
  status           TEXT,           -- TEXT وليس ENUM — للاتساق مع frontend
  order_date       DATE,
  created_at       TIMESTAMPTZ,
  total_amount     NUMERIC,
  paid_amount      NUMERIC,
  returned_amount  NUMERIC,
  payment_terms    TEXT,
  customer_id      UUID,
  customer_name    TEXT,
  customer_code    TEXT,
  customer_phone   TEXT,
  rep_id           UUID,
  rep_name         TEXT,
  branch_id        UUID,
  branch_name      TEXT,
  has_more         BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH filtered AS (
    SELECT
      so.id,
      so.order_number,
      so.status::TEXT,                          -- cast إلى TEXT للاتساق
      so.order_date,
      so.created_at,
      so.total_amount,
      so.paid_amount,
      so.returned_amount,
      so.payment_terms::TEXT,
      so.customer_id,
      c.name                          AS customer_name,
      c.code                          AS customer_code,
      COALESCE(c.phone, c.mobile)     AS customer_phone,
      so.rep_id,
      p.full_name                     AS rep_name,
      so.branch_id,
      b.name                          AS branch_name
    FROM sales_orders so
    JOIN customers   c ON c.id = so.customer_id
    LEFT JOIN profiles  p ON p.id = so.rep_id
    LEFT JOIN branches  b ON b.id = so.branch_id
    WHERE
      -- 1. البحث النصي: رقم الطلب | اسم/كود/هاتف/موبايل العميل
      (
        p_search IS NULL
        OR so.order_number ILIKE '%' || p_search || '%'
        OR c.name          ILIKE '%' || p_search || '%'
        OR c.code          ILIKE '%' || p_search || '%'
        OR c.phone         ILIKE '%' || p_search || '%'
        OR c.mobile        ILIKE '%' || p_search || '%'
      )
      -- 2. حالة الطلب
      AND (p_status IS NULL OR so.status = p_status::sales_order_status)
      -- 3. المندوب
      AND (p_rep_id IS NULL OR so.rep_id = p_rep_id)
      -- 4. نطاق التاريخ
      AND (p_date_from IS NULL OR so.order_date >= p_date_from)
      AND (p_date_to   IS NULL OR so.order_date <= p_date_to)
      -- 5. طريقة الدفع
      AND (p_payment_terms IS NULL OR so.payment_terms::TEXT = p_payment_terms)
      -- 6. فلتر المحافظة:
      --    العملاء يُخزَّن لديهم city_id وليس governorate_id مباشرة في معظم الحالات
      --    لذا نُغطي الحالتين: governorate_id مباشر أو city ينتمي للمحافظة
      AND (
        p_governorate_id IS NULL
        OR c.governorate_id = p_governorate_id
        OR c.city_id IN (
          SELECT id FROM cities WHERE governorate_id = p_governorate_id
        )
      )
      -- 7. مدينة العميل (مباشر — دقيق)
      AND (p_city_id IS NULL OR c.city_id = p_city_id)
      -- 8. Keyset cursor — O(log N) بدون OFFSET
      AND (
        p_cursor_ts IS NULL
        OR  so.order_date <  p_cursor_ts::DATE
        OR (so.order_date =  p_cursor_ts::DATE AND so.created_at <  p_cursor_ts)
        OR (so.order_date =  p_cursor_ts::DATE AND so.created_at =  p_cursor_ts AND so.id < p_cursor_id)
      )
    ORDER BY so.order_date DESC, so.created_at DESC, so.id DESC
    LIMIT p_limit + 1   -- +1 لمعرفة هل يوجد المزيد بدون COUNT(*)
  )
  SELECT
    id, order_number, status, order_date, created_at,
    total_amount, paid_amount, returned_amount, payment_terms,
    customer_id, customer_name, customer_code, customer_phone,
    rep_id, rep_name,
    branch_id, branch_name,
    (COUNT(*) OVER () > p_limit) AS has_more
  FROM filtered
  LIMIT p_limit;
$$;

-- FUNCTION add_vault_transaction from 113_hr_payroll_disbursement.sql:32
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
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
  END IF;

  SELECT * INTO v_vault
  FROM vaults
  WHERE id = p_vault_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'الخزنة غير موجودة'; END IF;
  IF NOT v_vault.is_active THEN RAISE EXCEPTION 'الخزنة معطلة'; END IF;

  IF p_type IN (
    'deposit', 'transfer_in', 'collection',
    'custody_return', 'opening_balance', 'vendor_refund'
  ) THEN
    v_new_balance := v_vault.current_balance + p_amount;

  ELSIF p_type IN (
    'withdrawal', 'transfer_out', 'expense', 'custody_load', 'vendor_payment', 'payroll_payment'
  ) THEN
    IF v_vault.current_balance < p_amount THEN
      RAISE EXCEPTION 'رصيد الخزنة غير كافٍ (المتاح: %، المطلوب: %)',
        v_vault.current_balance, p_amount;
    END IF;
    v_new_balance := v_vault.current_balance - p_amount;

  ELSE
    RAISE EXCEPTION 'نوع حركة غير صالح: %', p_type;
  END IF;

  INSERT INTO vault_transactions (
    vault_id, type, amount, balance_after,
    reference_type, reference_id, description, created_by
  ) VALUES (
    p_vault_id, p_type, p_amount, v_new_balance,
    p_ref_type, p_ref_id, p_description, p_user_id
  )
  RETURNING id INTO v_txn_id;

  UPDATE vaults SET current_balance = v_new_balance WHERE id = p_vault_id;

  RETURN v_txn_id;
END; $$;

-- FUNCTION update_sales_order_due_date from 118_invoice_credit_due_date_adjustments.sql:53
CREATE OR REPLACE FUNCTION public.update_sales_order_due_date(
  p_order_id     UUID,
  p_credit_days  INTEGER,
  p_reason       TEXT
) RETURNS JSONB
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_order           sales_orders%ROWTYPE;
  v_user_id         UUID := auth.uid();
  v_old_due_date    DATE;
  v_new_due_date    DATE;
  v_old_credit_days INTEGER;
  v_remaining       NUMERIC;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: authentication required';
  END IF;

  IF NOT check_permission(v_user_id, 'customers.credit.update') THEN
    RAISE EXCEPTION 'غير مصرح: يتطلب صلاحية إدارة الائتمان';
  END IF;

  IF p_credit_days IS NULL OR p_credit_days < 0 OR p_credit_days > 3650 THEN
    RAISE EXCEPTION 'مدة الائتمان يجب أن تكون بين 0 و 3650 يوم';
  END IF;

  IF p_reason IS NULL OR length(btrim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'سبب تعديل مدة الائتمان مطلوب';
  END IF;

  SELECT * INTO v_order
  FROM sales_orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'فاتورة البيع غير موجودة';
  END IF;

  IF v_order.status::text NOT IN ('delivered', 'partially_delivered') THEN
    RAISE EXCEPTION 'لا يمكن تعديل مدة الائتمان إلا لفاتورة مسلمة ومفتوحة';
  END IF;

  IF COALESCE(v_order.payment_terms, 'cash') NOT IN ('credit', 'mixed') THEN
    RAISE EXCEPTION 'لا يمكن تعديل مدة الائتمان لفاتورة نقدية';
  END IF;

  IF v_order.delivered_at IS NULL THEN
    RAISE EXCEPTION 'لا يمكن تعديل مدة الائتمان قبل تسجيل تاريخ التسليم';
  END IF;

  v_remaining :=
    COALESCE(v_order.total_amount, 0)
    - COALESCE(v_order.paid_amount, 0)
    - COALESCE(v_order.returned_amount, 0);

  IF v_remaining <= 0 THEN
    RAISE EXCEPTION 'لا يمكن تعديل مدة الائتمان لفاتورة مكتملة السداد';
  END IF;

  v_old_due_date := v_order.due_date;
  v_new_due_date := v_order.delivered_at::date + p_credit_days;
  v_old_credit_days := CASE
    WHEN v_old_due_date IS NULL THEN NULL
    ELSE v_old_due_date - v_order.delivered_at::date
  END;

  IF v_old_due_date IS NOT DISTINCT FROM v_new_due_date THEN
    RETURN jsonb_build_object(
      'order_id', v_order.id,
      'old_due_date', v_old_due_date,
      'new_due_date', v_new_due_date,
      'old_credit_days', v_old_credit_days,
      'new_credit_days', p_credit_days,
      'changed', false
    );
  END IF;

  UPDATE sales_orders
  SET due_date = v_new_due_date,
      updated_at = now()
  WHERE id = v_order.id;

  INSERT INTO sales_order_due_date_history (
    order_id,
    customer_id,
    old_due_date,
    new_due_date,
    old_credit_days,
    new_credit_days,
    changed_by,
    reason
  ) VALUES (
    v_order.id,
    v_order.customer_id,
    v_old_due_date,
    v_new_due_date,
    v_old_credit_days,
    p_credit_days,
    v_user_id,
    btrim(p_reason)
  );

  IF v_new_due_date >= CURRENT_DATE THEN
    UPDATE notification_alert_state
    SET resolved_at = now()
    WHERE alert_key = 'sales.invoice.overdue::' || v_order.id::text
      AND event_key = 'sales.invoice.overdue'
      AND resolved_at IS NULL;
  END IF;

  RETURN jsonb_build_object(
    'order_id', v_order.id,
    'old_due_date', v_old_due_date,
    'new_due_date', v_new_due_date,
    'old_credit_days', v_old_credit_days,
    'new_credit_days', p_credit_days,
    'changed', true
  );
END;
$$;

-- FUNCTION check_credit_available from 118_invoice_credit_due_date_adjustments.sql:181
CREATE OR REPLACE FUNCTION public.check_credit_available(
  p_customer_id UUID,
  p_amount      NUMERIC
) RETURNS BOOLEAN
  LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_limit       NUMERIC;
  v_days        INTEGER;
  v_balance     NUMERIC;
  v_has_overdue BOOLEAN := false;
  v_strict      BOOLEAN;
BEGIN
  SELECT credit_limit, credit_days, COALESCE(current_balance, 0)
  INTO v_limit, v_days, v_balance
  FROM customers
  WHERE id = p_customer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'العميل غير موجود';
  END IF;

  IF COALESCE(v_limit, 0) = 0 THEN
    RETURN false;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM sales_orders so
    WHERE so.customer_id = p_customer_id
      AND so.status IN ('delivered', 'partially_delivered')
      AND COALESCE(so.payment_terms, 'cash') IN ('credit', 'mixed')
      AND so.delivered_at IS NOT NULL
      AND GREATEST(
            0,
            COALESCE(so.total_amount, 0)
            - COALESCE(so.paid_amount, 0)
            - COALESCE(so.returned_amount, 0)
          ) > 0
      AND so.due_date IS NOT NULL
      AND so.due_date < CURRENT_DATE
  ) INTO v_has_overdue;

  IF v_has_overdue AND v_balance > 0 THEN
    SELECT COALESCE(value::boolean, true) INTO v_strict
    FROM company_settings WHERE key = 'sales.credit_check_strict';

    IF COALESCE(v_strict, true) THEN
      RETURN false;
    END IF;
  END IF;

  RETURN (v_balance + p_amount) <= v_limit;
END;
$$;

-- FUNCTION check_customer_credit from 118_invoice_credit_due_date_adjustments.sql:240
CREATE OR REPLACE FUNCTION public.check_customer_credit(
  p_customer_id UUID,
  p_amount      NUMERIC
) RETURNS JSONB
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_cust            RECORD;
  v_available       NUMERIC := 0;
  v_overdue_days    INTEGER := 0;
  v_oldest_invoice  TEXT := NULL;
  v_overdue_count   BIGINT := 0;
BEGIN
  SELECT
    c.name,
    c.payment_terms,
    COALESCE(c.credit_limit, 0) AS credit_limit,
    COALESCE(c.credit_days, 0) AS credit_days,
    COALESCE(c.current_balance, 0) AS current_balance
  INTO v_cust
  FROM customers c
  WHERE c.id = p_customer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'العميل غير موجود: %', p_customer_id;
  END IF;

  v_available := v_cust.credit_limit - v_cust.current_balance;

  SELECT
    COUNT(*) AS cnt,
    COALESCE(MAX(CURRENT_DATE - so.due_date), 0) AS max_days,
    MIN(so.order_number) AS oldest
  INTO v_overdue_count, v_overdue_days, v_oldest_invoice
  FROM sales_orders so
  WHERE so.customer_id = p_customer_id
    AND so.status IN ('delivered', 'partially_delivered')
    AND so.delivered_at IS NOT NULL
    AND GREATEST(
          0,
          COALESCE(so.total_amount, 0)
          - COALESCE(so.paid_amount, 0)
          - COALESCE(so.returned_amount, 0)
        ) > 0
    AND so.due_date IS NOT NULL
    AND so.due_date < CURRENT_DATE;

  RETURN jsonb_build_object(
    'customer_name',    v_cust.name,
    'payment_terms',    v_cust.payment_terms,
    'credit_limit',     v_cust.credit_limit,
    'current_balance',  v_cust.current_balance,
    'available_credit', v_available,
    'requested_amount', p_amount,
    'can_use_credit',   (v_cust.payment_terms <> 'cash'),
    'credit_ok',        (v_available >= p_amount AND v_cust.payment_terms <> 'cash'),
    'exceeds_limit',    (v_available < p_amount),
    'overdue_count',    COALESCE(v_overdue_count, 0),
    'overdue_days',     COALESCE(v_overdue_days, 0),
    'oldest_invoice',   v_oldest_invoice,
    'has_overdue',      (COALESCE(v_overdue_count, 0) > 0)
  );
END;
$$;

-- TRIGGER trg_receipts_updated_at from 03_financial_infrastructure.sql:271
CREATE TRIGGER trg_receipts_updated_at
  BEFORE UPDATE ON payment_receipts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- TRIGGER trg_receipt_auto_number from 03_financial_infrastructure.sql:289
CREATE TRIGGER trg_receipt_auto_number
  BEFORE INSERT ON payment_receipts
  FOR EACH ROW EXECUTE FUNCTION generate_receipt_number();

-- TRIGGER trg_journal_auto_number from 03_financial_infrastructure.sql:451
CREATE TRIGGER trg_journal_auto_number
  BEFORE INSERT ON journal_entries
  FOR EACH ROW EXECUTE FUNCTION generate_journal_number();

-- TRIGGER trg_customer_opening_ledger from 03_financial_infrastructure.sql:1480
CREATE TRIGGER trg_customer_opening_ledger
  AFTER INSERT ON customers
  FOR EACH ROW EXECUTE FUNCTION sync_customer_opening_balance();

-- TRIGGER trg_supplier_opening_ledger from 03_financial_infrastructure.sql:1506
CREATE TRIGGER trg_supplier_opening_ledger
  AFTER INSERT ON suppliers
  FOR EACH ROW EXECUTE FUNCTION sync_supplier_opening_balance();

-- TRIGGER trg_cust_ledger_update_balance from 03h_extreme_performance.sql:54
CREATE TRIGGER trg_cust_ledger_update_balance
  AFTER INSERT OR UPDATE OR DELETE ON customer_ledger
  FOR EACH ROW EXECUTE FUNCTION update_customer_cached_balance();

-- TRIGGER trg_supp_ledger_update_balance from 03h_extreme_performance.sql:99
CREATE TRIGGER trg_supp_ledger_update_balance
  AFTER INSERT OR UPDATE OR DELETE ON supplier_ledger
  FOR EACH ROW EXECUTE FUNCTION update_supplier_cached_balance();

-- TRIGGER trg_sales_orders_updated_at from 04_sales_system.sql:200
CREATE TRIGGER trg_sales_orders_updated_at
  BEFORE UPDATE ON sales_orders
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- TRIGGER trg_sales_returns_updated_at from 04_sales_system.sql:313
CREATE TRIGGER trg_sales_returns_updated_at
  BEFORE UPDATE ON sales_returns
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- TRIGGER trg_so_auto_number from 04_sales_system.sql:503
CREATE TRIGGER trg_so_auto_number
  BEFORE INSERT ON sales_orders
  FOR EACH ROW EXECUTE FUNCTION trg_auto_sales_order_number();

-- TRIGGER trg_sr_auto_number from 04_sales_system.sql:519
CREATE TRIGGER trg_sr_auto_number
  BEFORE INSERT ON sales_returns
  FOR EACH ROW EXECUTE FUNCTION trg_auto_sales_return_number();

-- TRIGGER trg_validate_sales_item from 10_audit_fixes.sql:67
CREATE TRIGGER trg_validate_sales_item
  BEFORE INSERT OR UPDATE ON sales_order_items
  FOR EACH ROW EXECUTE FUNCTION validate_sales_item_amounts();

-- TRIGGER trg_purchase_invoice_number from 14_procurement_schema_and_coa.sql:195
CREATE TRIGGER trg_purchase_invoice_number
  BEFORE INSERT ON purchase_invoices
  FOR EACH ROW EXECUTE FUNCTION generate_purchase_invoice_number();

-- TRIGGER trg_purchase_invoices_updated_at from 14_procurement_schema_and_coa.sql:201
CREATE TRIGGER trg_purchase_invoices_updated_at
  BEFORE UPDATE ON purchase_invoices
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- TRIGGER trg_purchase_return_number from 16_procurement_returns_and_cancellations.sql:183
CREATE TRIGGER trg_purchase_return_number
  BEFORE INSERT ON purchase_returns
  FOR EACH ROW EXECUTE FUNCTION generate_purchase_return_number();

-- TRIGGER trg_purchase_returns_updated_at from 16_procurement_returns_and_cancellations.sql:188
CREATE TRIGGER trg_purchase_returns_updated_at
  BEFORE UPDATE ON purchase_returns
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- TRIGGER trg_guard_customer_opening_balance from 60_finance_field_guards.sql:21
CREATE TRIGGER trg_guard_customer_opening_balance
  BEFORE UPDATE ON customers
  FOR EACH ROW
  EXECUTE FUNCTION guard_customer_opening_balance();

-- TRIGGER trg_guard_supplier_opening_balance from 60_finance_field_guards.sql:41
CREATE TRIGGER trg_guard_supplier_opening_balance
  BEFORE UPDATE ON suppliers
  FOR EACH ROW
  EXECUTE FUNCTION guard_supplier_opening_balance();

-- TRIGGER trg_guard_vault_type from 60_finance_field_guards.sql:65
CREATE TRIGGER trg_guard_vault_type
  BEFORE UPDATE ON vaults
  FOR EACH ROW
  EXECUTE FUNCTION guard_vault_type();

-- RLS chart_of_accounts from 03_financial_infrastructure.sql:601
ALTER TABLE chart_of_accounts   ENABLE ROW LEVEL SECURITY;

-- RLS customer_ledger from 03_financial_infrastructure.sql:602
ALTER TABLE customer_ledger     ENABLE ROW LEVEL SECURITY;

-- RLS supplier_ledger from 03_financial_infrastructure.sql:603
ALTER TABLE supplier_ledger     ENABLE ROW LEVEL SECURITY;

-- RLS vault_transactions from 03_financial_infrastructure.sql:605
ALTER TABLE vault_transactions  ENABLE ROW LEVEL SECURITY;

-- RLS custody_transactions from 03_financial_infrastructure.sql:607
ALTER TABLE custody_transactions ENABLE ROW LEVEL SECURITY;

-- RLS payment_receipts from 03_financial_infrastructure.sql:608
ALTER TABLE payment_receipts    ENABLE ROW LEVEL SECURITY;

-- RLS journal_entries from 03_financial_infrastructure.sql:612
ALTER TABLE journal_entries     ENABLE ROW LEVEL SECURITY;

-- RLS journal_entry_lines from 03_financial_infrastructure.sql:613
ALTER TABLE journal_entry_lines ENABLE ROW LEVEL SECURITY;

-- RLS sales_order_items from 04_sales_system.sql:350
ALTER TABLE sales_order_items  ENABLE ROW LEVEL SECURITY;

-- RLS sales_returns from 04_sales_system.sql:351
ALTER TABLE sales_returns      ENABLE ROW LEVEL SECURITY;

-- RLS sales_return_items from 04_sales_system.sql:352
ALTER TABLE sales_return_items ENABLE ROW LEVEL SECURITY;

-- RLS purchase_invoice_items from 14_procurement_schema_and_coa.sql:307
ALTER TABLE purchase_invoice_items ENABLE ROW LEVEL SECURITY;

-- RLS purchase_returns from 16_procurement_returns_and_cancellations.sql:233
ALTER TABLE purchase_returns      ENABLE ROW LEVEL SECURITY;

-- RLS purchase_return_items from 16_procurement_returns_and_cancellations.sql:234
ALTER TABLE purchase_return_items ENABLE ROW LEVEL SECURITY;

-- RLS notification_alert_state from 52_notification_wave1a_events.sql:83
ALTER TABLE notification_alert_state ENABLE ROW LEVEL SECURITY;

-- RLS sales_order_due_date_history from 118_invoice_credit_due_date_adjustments.sql:38
ALTER TABLE public.sales_order_due_date_history ENABLE ROW LEVEL SECURITY;

-- POLICY_DROP chart_of_accounts:coa_read from 66_rls_initplan_safe.sql:287
DROP POLICY IF EXISTS "coa_read" ON chart_of_accounts;

-- POLICY_DROP chart_of_accounts:coa_write from 66_rls_initplan_safe.sql:291
DROP POLICY IF EXISTS "coa_write" ON chart_of_accounts;

-- POLICY_DROP custody_transactions:custody_txn_read from 66_rls_initplan_safe.sql:323
DROP POLICY IF EXISTS "custody_txn_read" ON custody_transactions;

-- POLICY_DROP custody_transactions:custody_txn_write from 66_rls_initplan_safe.sql:329
DROP POLICY IF EXISTS "custody_txn_write" ON custody_transactions;

-- POLICY_DROP customer_ledger:cust_ledger_read from 66_rls_initplan_safe.sql:373
DROP POLICY IF EXISTS "cust_ledger_read" ON customer_ledger;

-- POLICY_DROP customer_ledger:cust_ledger_write from 66_rls_initplan_safe.sql:377
DROP POLICY IF EXISTS "cust_ledger_write" ON customer_ledger;

-- POLICY_DROP journal_entries:je_read from 66_rls_initplan_safe.sql:772
DROP POLICY IF EXISTS "je_read" ON journal_entries;

-- POLICY_DROP journal_entries:je_write from 66_rls_initplan_safe.sql:776
DROP POLICY IF EXISTS "je_write" ON journal_entries;

-- POLICY_DROP journal_entry_lines:je_lines_read from 66_rls_initplan_safe.sql:782
DROP POLICY IF EXISTS "je_lines_read" ON journal_entry_lines;

-- POLICY_DROP journal_entry_lines:je_lines_write from 66_rls_initplan_safe.sql:786
DROP POLICY IF EXISTS "je_lines_write" ON journal_entry_lines;

-- POLICY_DROP payment_receipts:receipts_insert from 66_rls_initplan_safe.sql:817
DROP POLICY IF EXISTS "receipts_insert" ON payment_receipts;

-- POLICY_DROP payment_receipts:receipts_read from 66_rls_initplan_safe.sql:821
DROP POLICY IF EXISTS "receipts_read" ON payment_receipts;

-- POLICY_DROP payment_receipts:receipts_update from 66_rls_initplan_safe.sql:825
DROP POLICY IF EXISTS "receipts_update" ON payment_receipts;

-- POLICY_DROP price_list_assignments:price_list_assignments_read from 66_rls_initplan_safe.sql:831
DROP POLICY IF EXISTS "price_list_assignments_read" ON price_list_assignments;

-- POLICY_DROP price_list_assignments:price_list_assignments_write from 66_rls_initplan_safe.sql:835
DROP POLICY IF EXISTS "price_list_assignments_write" ON price_list_assignments;

-- POLICY_DROP price_list_items:price_list_items_read from 66_rls_initplan_safe.sql:841
DROP POLICY IF EXISTS "price_list_items_read" ON price_list_items;

-- POLICY_DROP price_list_items:price_list_items_write from 66_rls_initplan_safe.sql:845
DROP POLICY IF EXISTS "price_list_items_write" ON price_list_items;

-- POLICY_DROP product_units:product_units_read from 66_rls_initplan_safe.sql:891
DROP POLICY IF EXISTS "product_units_read" ON product_units;

-- POLICY_DROP product_units:product_units_write from 66_rls_initplan_safe.sql:895
DROP POLICY IF EXISTS "product_units_write" ON product_units;

-- POLICY_DROP purchase_invoice_items:pii_insert from 66_rls_initplan_safe.sql:921
DROP POLICY IF EXISTS "pii_insert" ON purchase_invoice_items;

-- POLICY_DROP purchase_invoice_items:pii_read from 66_rls_initplan_safe.sql:925
DROP POLICY IF EXISTS "pii_read" ON purchase_invoice_items;

-- POLICY_DROP purchase_invoice_items:pii_update from 66_rls_initplan_safe.sql:929
DROP POLICY IF EXISTS "pii_update" ON purchase_invoice_items;

-- POLICY_DROP purchase_return_items:pri_insert from 66_rls_initplan_safe.sql:949
DROP POLICY IF EXISTS "pri_insert" ON purchase_return_items;

-- POLICY_DROP purchase_return_items:pri_read from 66_rls_initplan_safe.sql:953
DROP POLICY IF EXISTS "pri_read" ON purchase_return_items;

-- POLICY_DROP purchase_return_items:pri_update from 66_rls_initplan_safe.sql:957
DROP POLICY IF EXISTS "pri_update" ON purchase_return_items;

-- POLICY_DROP purchase_returns:pr_insert from 66_rls_initplan_safe.sql:963
DROP POLICY IF EXISTS "pr_insert" ON purchase_returns;

-- POLICY_DROP purchase_returns:pr_read from 66_rls_initplan_safe.sql:967
DROP POLICY IF EXISTS "pr_read" ON purchase_returns;

-- POLICY_DROP purchase_returns:pr_update from 66_rls_initplan_safe.sql:971
DROP POLICY IF EXISTS "pr_update" ON purchase_returns;

-- POLICY_DROP sales_order_items:soi_read from 66_rls_initplan_safe.sql:1031
DROP POLICY IF EXISTS "soi_read" ON sales_order_items;

-- POLICY_DROP sales_order_items:soi_write from 66_rls_initplan_safe.sql:1037
DROP POLICY IF EXISTS "soi_write" ON sales_order_items;

-- POLICY_DROP sales_return_items:sri_read from 66_rls_initplan_safe.sql:1059
DROP POLICY IF EXISTS "sri_read" ON sales_return_items;

-- POLICY_DROP sales_return_items:sri_write from 66_rls_initplan_safe.sql:1065
DROP POLICY IF EXISTS "sri_write" ON sales_return_items;

-- POLICY_DROP sales_returns:sr_insert from 66_rls_initplan_safe.sql:1073
DROP POLICY IF EXISTS "sr_insert" ON sales_returns;

-- POLICY_DROP sales_returns:sr_read from 66_rls_initplan_safe.sql:1077
DROP POLICY IF EXISTS "sr_read" ON sales_returns;

-- POLICY_DROP sales_returns:sr_update from 66_rls_initplan_safe.sql:1081
DROP POLICY IF EXISTS "sr_update" ON sales_returns;

-- POLICY_DROP stock_movements:stock_movements_read from 66_rls_initplan_safe.sql:1133
DROP POLICY IF EXISTS "stock_movements_read" ON stock_movements;

-- POLICY_DROP supplier_ledger:supp_ledger_read from 66_rls_initplan_safe.sql:1171
DROP POLICY IF EXISTS "supp_ledger_read" ON supplier_ledger;

-- POLICY_DROP supplier_ledger:supp_ledger_write from 66_rls_initplan_safe.sql:1175
DROP POLICY IF EXISTS "supp_ledger_write" ON supplier_ledger;

-- POLICY_DROP vault_transactions:vault_txn_read from 66_rls_initplan_safe.sql:1402
DROP POLICY IF EXISTS "vault_txn_read" ON vault_transactions;

-- POLICY_DROP vault_transactions:vault_txn_write from 66_rls_initplan_safe.sql:1408
DROP POLICY IF EXISTS "vault_txn_write" ON vault_transactions;

-- POLICY_DROP sales_order_due_date_history:sales_order_due_date_history_select from 118_invoice_credit_due_date_adjustments.sql:40
DROP POLICY IF EXISTS "sales_order_due_date_history_select" ON public.sales_order_due_date_history;

-- POLICY chart_of_accounts:coa_read from 66_rls_initplan_safe.sql:288
CREATE POLICY "coa_read" ON chart_of_accounts FOR SELECT
USING (((SELECT auth.uid()) IS NOT NULL));

-- POLICY chart_of_accounts:coa_write from 66_rls_initplan_safe.sql:292
CREATE POLICY "coa_write" ON chart_of_accounts FOR ALL
USING ((SELECT check_permission((SELECT auth.uid()), 'finance.journal.create'::text)));

-- POLICY custody_transactions:custody_txn_read from 66_rls_initplan_safe.sql:324
CREATE POLICY "custody_txn_read" ON custody_transactions FOR SELECT
USING (((SELECT check_permission((SELECT auth.uid()), 'finance.custody.read_all'::text)) OR (custody_id IN ( SELECT custody_accounts.id
   FROM custody_accounts
  WHERE (custody_accounts.employee_id = (SELECT auth.uid()))))));

-- POLICY custody_transactions:custody_txn_write from 66_rls_initplan_safe.sql:330
CREATE POLICY "custody_txn_write" ON custody_transactions FOR ALL
USING ((SELECT check_permission((SELECT auth.uid()), 'finance.custody.transact'::text)));

-- POLICY customer_ledger:cust_ledger_read from 66_rls_initplan_safe.sql:374
CREATE POLICY "cust_ledger_read" ON customer_ledger FOR SELECT
USING ((SELECT check_permission((SELECT auth.uid()), 'finance.ledger.read'::text)));

-- POLICY customer_ledger:cust_ledger_write from 66_rls_initplan_safe.sql:378
CREATE POLICY "cust_ledger_write" ON customer_ledger FOR ALL
USING ((SELECT check_permission((SELECT auth.uid()), 'finance.ledger.adjust'::text)));

-- POLICY journal_entries:je_read from 66_rls_initplan_safe.sql:773
CREATE POLICY "je_read" ON journal_entries FOR SELECT
USING ((SELECT check_permission((SELECT auth.uid()), 'finance.journal.read'::text)));

-- POLICY journal_entries:je_write from 66_rls_initplan_safe.sql:777
CREATE POLICY "je_write" ON journal_entries FOR ALL
USING ((SELECT check_permission((SELECT auth.uid()), 'finance.journal.create'::text)));

-- POLICY journal_entry_lines:je_lines_read from 66_rls_initplan_safe.sql:783
CREATE POLICY "je_lines_read" ON journal_entry_lines FOR SELECT
USING ((SELECT check_permission((SELECT auth.uid()), 'finance.journal.read'::text)));

-- POLICY journal_entry_lines:je_lines_write from 66_rls_initplan_safe.sql:787
CREATE POLICY "je_lines_write" ON journal_entry_lines FOR ALL
USING ((SELECT check_permission((SELECT auth.uid()), 'finance.journal.create'::text)));

-- POLICY payment_receipts:receipts_insert from 66_rls_initplan_safe.sql:818
CREATE POLICY "receipts_insert" ON payment_receipts FOR INSERT
WITH CHECK ((SELECT check_permission((SELECT auth.uid()), 'finance.payments.create'::text)));

-- POLICY payment_receipts:receipts_read from 66_rls_initplan_safe.sql:822
CREATE POLICY "receipts_read" ON payment_receipts FOR SELECT
USING (((created_by = (SELECT auth.uid())) OR (collected_by = (SELECT auth.uid())) OR (SELECT check_permission((SELECT auth.uid()), 'finance.payments.read_all'::text))));

-- POLICY payment_receipts:receipts_update from 66_rls_initplan_safe.sql:826
CREATE POLICY "receipts_update" ON payment_receipts FOR UPDATE
USING ((SELECT check_permission((SELECT auth.uid()), 'finance.payments.confirm'::text)));

-- POLICY price_list_assignments:price_list_assignments_read from 66_rls_initplan_safe.sql:832
CREATE POLICY "price_list_assignments_read" ON price_list_assignments FOR SELECT
USING ((SELECT check_permission((SELECT auth.uid()), 'price_lists.read'::text)));

-- POLICY price_list_assignments:price_list_assignments_write from 66_rls_initplan_safe.sql:836
CREATE POLICY "price_list_assignments_write" ON price_list_assignments FOR ALL
USING ((SELECT check_permission((SELECT auth.uid()), 'price_lists.update'::text)));

-- POLICY price_list_items:price_list_items_read from 66_rls_initplan_safe.sql:842
CREATE POLICY "price_list_items_read" ON price_list_items FOR SELECT
USING ((SELECT check_permission((SELECT auth.uid()), 'price_lists.read'::text)));

-- POLICY price_list_items:price_list_items_write from 66_rls_initplan_safe.sql:846
CREATE POLICY "price_list_items_write" ON price_list_items FOR ALL
USING ((SELECT check_permission((SELECT auth.uid()), 'price_lists.update'::text)));

-- POLICY product_units:product_units_read from 66_rls_initplan_safe.sql:892
CREATE POLICY "product_units_read" ON product_units FOR SELECT
USING ((SELECT check_permission((SELECT auth.uid()), 'products.read'::text)));

-- POLICY product_units:product_units_write from 66_rls_initplan_safe.sql:896
CREATE POLICY "product_units_write" ON product_units FOR ALL
USING ((SELECT check_permission((SELECT auth.uid()), 'products.create'::text)));

-- POLICY purchase_invoice_items:pii_insert from 66_rls_initplan_safe.sql:922
CREATE POLICY "pii_insert" ON purchase_invoice_items FOR INSERT
WITH CHECK ((SELECT check_permission((SELECT auth.uid()), 'procurement.invoices.create'::text)));

-- POLICY purchase_invoice_items:pii_read from 66_rls_initplan_safe.sql:926
CREATE POLICY "pii_read" ON purchase_invoice_items FOR SELECT
USING ((SELECT check_permission((SELECT auth.uid()), 'procurement.invoices.read'::text)));

-- POLICY purchase_invoice_items:pii_update from 66_rls_initplan_safe.sql:930
CREATE POLICY "pii_update" ON purchase_invoice_items FOR UPDATE
USING ((SELECT check_permission((SELECT auth.uid()), 'procurement.invoices.receive'::text)));

-- POLICY purchase_return_items:pri_insert from 66_rls_initplan_safe.sql:950
CREATE POLICY "pri_insert" ON purchase_return_items FOR INSERT
WITH CHECK ((SELECT check_permission((SELECT auth.uid()), 'procurement.returns.create'::text)));

-- POLICY purchase_return_items:pri_read from 66_rls_initplan_safe.sql:954
CREATE POLICY "pri_read" ON purchase_return_items FOR SELECT
USING ((SELECT check_permission((SELECT auth.uid()), 'procurement.returns.read'::text)));

-- POLICY purchase_return_items:pri_update from 66_rls_initplan_safe.sql:958
CREATE POLICY "pri_update" ON purchase_return_items FOR UPDATE
USING ((SELECT check_permission((SELECT auth.uid()), 'procurement.returns.confirm'::text)));

-- POLICY purchase_returns:pr_insert from 66_rls_initplan_safe.sql:964
CREATE POLICY "pr_insert" ON purchase_returns FOR INSERT
WITH CHECK ((SELECT check_permission((SELECT auth.uid()), 'procurement.returns.create'::text)));

-- POLICY purchase_returns:pr_read from 66_rls_initplan_safe.sql:968
CREATE POLICY "pr_read" ON purchase_returns FOR SELECT
USING ((SELECT check_permission((SELECT auth.uid()), 'procurement.returns.read'::text)));

-- POLICY purchase_returns:pr_update from 66_rls_initplan_safe.sql:972
CREATE POLICY "pr_update" ON purchase_returns FOR UPDATE
USING (((SELECT check_permission((SELECT auth.uid()), 'procurement.returns.create'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'procurement.returns.confirm'::text))));

-- POLICY sales_order_items:soi_read from 66_rls_initplan_safe.sql:1032
CREATE POLICY "soi_read" ON sales_order_items FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM sales_orders so
  WHERE ((so.id = sales_order_items.order_id) AND ((so.rep_id = (SELECT auth.uid())) OR (so.created_by_id = (SELECT auth.uid())) OR (SELECT check_permission((SELECT auth.uid()), 'sales.orders.read_all'::text)))))));

-- POLICY sales_order_items:soi_write from 66_rls_initplan_safe.sql:1038
CREATE POLICY "soi_write" ON sales_order_items FOR ALL
USING ((EXISTS ( SELECT 1
   FROM sales_orders so
  WHERE (((so.id = sales_order_items.order_id) AND ((so.status = 'draft'::sales_order_status) AND ((so.rep_id = (SELECT auth.uid())) OR (so.created_by_id = (SELECT auth.uid()))))) OR (SELECT check_permission((SELECT auth.uid()), 'sales.orders.read_all'::text))))));

-- POLICY sales_return_items:sri_read from 66_rls_initplan_safe.sql:1060
CREATE POLICY "sri_read" ON sales_return_items FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM sales_returns sr
  WHERE ((sr.id = sales_return_items.return_id) AND ((sr.created_by = (SELECT auth.uid())) OR (SELECT check_permission((SELECT auth.uid()), 'sales.returns.read'::text)))))));

-- POLICY sales_return_items:sri_write from 66_rls_initplan_safe.sql:1066
CREATE POLICY "sri_write" ON sales_return_items FOR ALL
USING ((EXISTS ( SELECT 1
   FROM sales_returns sr
  WHERE ((sr.id = sales_return_items.return_id) AND (sr.status = 'draft'::sales_return_status) AND ((sr.created_by = (SELECT auth.uid())) OR (SELECT check_permission((SELECT auth.uid()), 'sales.returns.confirm'::text)))))));

-- POLICY sales_returns:sr_insert from 66_rls_initplan_safe.sql:1074
CREATE POLICY "sr_insert" ON sales_returns FOR INSERT
WITH CHECK ((SELECT check_permission((SELECT auth.uid()), 'sales.returns.create'::text)));

-- POLICY sales_returns:sr_read from 66_rls_initplan_safe.sql:1078
CREATE POLICY "sr_read" ON sales_returns FOR SELECT
USING (((created_by = (SELECT auth.uid())) OR (SELECT check_permission((SELECT auth.uid()), 'sales.returns.read'::text))));

-- POLICY sales_returns:sr_update from 66_rls_initplan_safe.sql:1082
CREATE POLICY "sr_update" ON sales_returns FOR UPDATE
USING ((((status = 'draft'::sales_return_status) AND (created_by = (SELECT auth.uid()))) OR (SELECT check_permission((SELECT auth.uid()), 'sales.returns.confirm'::text))));

-- POLICY stock_movements:stock_movements_read from 66_rls_initplan_safe.sql:1134
CREATE POLICY "stock_movements_read" ON stock_movements FOR SELECT
USING (((SELECT check_permission((SELECT auth.uid()), 'inventory.read_all'::text)) OR ((SELECT check_permission((SELECT auth.uid()), 'inventory.read'::text)) AND (warehouse_id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set)))));

-- POLICY supplier_ledger:supp_ledger_read from 66_rls_initplan_safe.sql:1172
CREATE POLICY "supp_ledger_read" ON supplier_ledger FOR SELECT
USING ((SELECT check_permission((SELECT auth.uid()), 'finance.ledger.read'::text)));

-- POLICY supplier_ledger:supp_ledger_write from 66_rls_initplan_safe.sql:1176
CREATE POLICY "supp_ledger_write" ON supplier_ledger FOR ALL
USING ((SELECT check_permission((SELECT auth.uid()), 'finance.ledger.adjust'::text)));

-- POLICY vault_transactions:vault_txn_read from 66_rls_initplan_safe.sql:1403
CREATE POLICY "vault_txn_read" ON vault_transactions FOR SELECT
USING (((SELECT check_permission((SELECT auth.uid()), 'finance.vaults.read_all'::text)) OR ((SELECT check_permission((SELECT auth.uid()), 'finance.vaults.read'::text)) AND (vault_id IN ( SELECT vaults.id
   FROM vaults
  WHERE (vaults.responsible_id = (SELECT auth.uid())))))));

-- POLICY vault_transactions:vault_txn_write from 66_rls_initplan_safe.sql:1409
CREATE POLICY "vault_txn_write" ON vault_transactions FOR ALL
USING ((SELECT check_permission((SELECT auth.uid()), 'finance.vaults.transact'::text)));

-- POLICY sales_order_due_date_history:sales_order_due_date_history_select from 118_invoice_credit_due_date_adjustments.sql:41
CREATE POLICY "sales_order_due_date_history_select"
  ON public.sales_order_due_date_history
  FOR SELECT
  USING (
    public.check_permission(auth.uid(), 'customers.credit.update')
    OR public.check_permission(auth.uid(), 'settings.audit.read')
    OR public.check_permission(auth.uid(), '*')
  );

-- INDEX idx_product_units_product from 02_master_data.sql:1097
CREATE INDEX IF NOT EXISTS idx_product_units_product ON product_units(product_id);

-- INDEX idx_price_list_items_product from 02_master_data.sql:1098
CREATE INDEX IF NOT EXISTS idx_price_list_items_product ON price_list_items(product_id);

-- INDEX idx_stock_movements_wh from 02_master_data.sql:1106
CREATE INDEX IF NOT EXISTS idx_stock_movements_wh ON stock_movements(warehouse_id);

-- INDEX idx_stock_movements_product from 02_master_data.sql:1107
CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON stock_movements(product_id);

-- INDEX idx_pli_unique_tier from 02g_audit_fixes.sql:292
CREATE UNIQUE INDEX IF NOT EXISTS idx_pli_unique_tier
  ON price_list_items (price_list_id, product_id, unit_id, COALESCE(min_qty, 0));

-- INDEX idx_stock_movements_ref from 02g_audit_fixes.sql:301
CREATE INDEX IF NOT EXISTS idx_stock_movements_ref
  ON stock_movements (reference_type, reference_id);

-- INDEX idx_cust_ledger_customer from 03_financial_infrastructure.sql:95
CREATE INDEX IF NOT EXISTS idx_cust_ledger_customer  ON customer_ledger(customer_id);

-- INDEX idx_cust_ledger_source from 03_financial_infrastructure.sql:96
CREATE INDEX IF NOT EXISTS idx_cust_ledger_source    ON customer_ledger(source_type, source_id);

-- INDEX idx_cust_ledger_date from 03_financial_infrastructure.sql:97
CREATE INDEX IF NOT EXISTS idx_cust_ledger_date      ON customer_ledger(created_at DESC);

-- INDEX idx_supp_ledger_supplier from 03_financial_infrastructure.sql:133
CREATE INDEX IF NOT EXISTS idx_supp_ledger_supplier  ON supplier_ledger(supplier_id);

-- INDEX idx_supp_ledger_source from 03_financial_infrastructure.sql:134
CREATE INDEX IF NOT EXISTS idx_supp_ledger_source    ON supplier_ledger(source_type, source_id);

-- INDEX idx_supp_ledger_date from 03_financial_infrastructure.sql:135
CREATE INDEX IF NOT EXISTS idx_supp_ledger_date      ON supplier_ledger(created_at DESC);

-- INDEX idx_vault_txn_vault from 03_financial_infrastructure.sql:193
CREATE INDEX IF NOT EXISTS idx_vault_txn_vault     ON vault_transactions(vault_id);

-- INDEX idx_vault_txn_date from 03_financial_infrastructure.sql:194
CREATE INDEX IF NOT EXISTS idx_vault_txn_date      ON vault_transactions(created_at DESC);

-- INDEX idx_vault_txn_ref from 03_financial_infrastructure.sql:195
CREATE INDEX IF NOT EXISTS idx_vault_txn_ref       ON vault_transactions(reference_type, reference_id);

-- INDEX idx_custody_txn_custody from 03_financial_infrastructure.sql:233
CREATE INDEX IF NOT EXISTS idx_custody_txn_custody  ON custody_transactions(custody_id);

-- INDEX idx_custody_txn_date from 03_financial_infrastructure.sql:234
CREATE INDEX IF NOT EXISTS idx_custody_txn_date     ON custody_transactions(created_at DESC);

-- INDEX idx_custody_txn_ref from 03_financial_infrastructure.sql:235
CREATE INDEX IF NOT EXISTS idx_custody_txn_ref      ON custody_transactions(reference_type, reference_id);

-- INDEX idx_receipts_customer from 03_financial_infrastructure.sql:275
CREATE INDEX IF NOT EXISTS idx_receipts_customer  ON payment_receipts(customer_id);

-- INDEX idx_receipts_date from 03_financial_infrastructure.sql:277
CREATE INDEX IF NOT EXISTS idx_receipts_date      ON payment_receipts(created_at DESC);

-- INDEX idx_je_date from 03_financial_infrastructure.sql:437
CREATE INDEX IF NOT EXISTS idx_je_date          ON journal_entries(entry_date DESC);

-- INDEX idx_je_source from 03_financial_infrastructure.sql:438
CREATE INDEX IF NOT EXISTS idx_je_source        ON journal_entries(source_type, source_id);

-- INDEX idx_je_lines_entry from 03_financial_infrastructure.sql:439
CREATE INDEX IF NOT EXISTS idx_je_lines_entry   ON journal_entry_lines(entry_id);

-- INDEX idx_je_lines_account from 03_financial_infrastructure.sql:454
CREATE INDEX IF NOT EXISTS idx_je_lines_account ON journal_entry_lines(account_id);

-- INDEX idx_receipts_created_by from 03f_performance_indexes.sql:58
CREATE INDEX IF NOT EXISTS idx_receipts_created_by
  ON payment_receipts(created_by);

-- INDEX idx_receipts_collected_by from 03f_performance_indexes.sql:60
CREATE INDEX IF NOT EXISTS idx_receipts_collected_by
  ON payment_receipts(collected_by);

-- INDEX idx_movements_wh_date from 03f_performance_indexes.sql:77
CREATE INDEX IF NOT EXISTS idx_movements_wh_date
  ON stock_movements(warehouse_id, created_at DESC);

-- INDEX idx_receipts_created_at_desc from 03g_performance_hardening.sql:70
CREATE INDEX IF NOT EXISTS idx_receipts_created_at_desc
  ON payment_receipts(created_at DESC);

-- INDEX idx_vault_txn_created_at_desc from 03g_performance_hardening.sql:73
CREATE INDEX IF NOT EXISTS idx_vault_txn_created_at_desc
  ON vault_transactions(vault_id, created_at DESC);

-- INDEX idx_custody_txn_created_at_desc from 03g_performance_hardening.sql:76
CREATE INDEX IF NOT EXISTS idx_custody_txn_created_at_desc
  ON custody_transactions(custody_id, created_at DESC);

-- INDEX idx_je_created_at_desc from 03g_performance_hardening.sql:79
CREATE INDEX IF NOT EXISTS idx_je_created_at_desc
  ON journal_entries(created_at DESC);

-- INDEX idx_customer_ledger_created_at_desc from 03g_performance_hardening.sql:82
CREATE INDEX IF NOT EXISTS idx_customer_ledger_created_at_desc
  ON customer_ledger(customer_id, created_at DESC);

-- INDEX idx_supplier_ledger_created_at_desc from 03g_performance_hardening.sql:85
CREATE INDEX IF NOT EXISTS idx_supplier_ledger_created_at_desc
  ON supplier_ledger(supplier_id, created_at DESC);

-- INDEX idx_stock_movements_created_at_desc from 03g_performance_hardening.sql:95
CREATE INDEX IF NOT EXISTS idx_stock_movements_created_at_desc
  ON stock_movements(created_at DESC);

-- INDEX idx_receipts_status from 03g_performance_hardening.sql:121
CREATE INDEX IF NOT EXISTS idx_receipts_status
  ON payment_receipts(status);

-- INDEX idx_je_source_type from 03g_performance_hardening.sql:133
CREATE INDEX IF NOT EXISTS idx_je_source_type
  ON journal_entries(source_type);

-- INDEX idx_vault_txn_vault_id from 03g_performance_hardening.sql:180
CREATE INDEX IF NOT EXISTS idx_vault_txn_vault_id
  ON vault_transactions(vault_id);

-- INDEX idx_custody_txn_custody_id from 03g_performance_hardening.sql:184
CREATE INDEX IF NOT EXISTS idx_custody_txn_custody_id
  ON custody_transactions(custody_id);

-- INDEX idx_je_lines_entry_id from 03g_performance_hardening.sql:192
CREATE INDEX IF NOT EXISTS idx_je_lines_entry_id
  ON journal_entry_lines(entry_id);

-- INDEX idx_cust_ledger_allocated from 04_sales_system.sql:16
CREATE INDEX IF NOT EXISTS idx_cust_ledger_allocated ON customer_ledger(allocated_to);

-- INDEX idx_soi_order from 04_sales_system.sql:431
CREATE INDEX IF NOT EXISTS idx_soi_order       ON sales_order_items(order_id);

-- INDEX idx_soi_product from 04_sales_system.sql:432
CREATE INDEX IF NOT EXISTS idx_soi_product     ON sales_order_items(product_id);

-- INDEX idx_sr_order from 04_sales_system.sql:433
CREATE INDEX IF NOT EXISTS idx_sr_order        ON sales_returns(order_id);

-- INDEX idx_sr_customer from 04_sales_system.sql:434
CREATE INDEX IF NOT EXISTS idx_sr_customer     ON sales_returns(customer_id);

-- INDEX idx_sr_status from 04_sales_system.sql:435
CREATE INDEX IF NOT EXISTS idx_sr_status       ON sales_returns(status);

-- INDEX idx_sri_return from 04_sales_system.sql:436
CREATE INDEX IF NOT EXISTS idx_sri_return      ON sales_return_items(return_id);

-- INDEX idx_sri_order_item from 04_sales_system.sql:437
CREATE INDEX IF NOT EXISTS idx_sri_order_item  ON sales_return_items(order_item_id);

-- INDEX idx_pr_sales_order from 07_payment_integration.sql:19
CREATE INDEX IF NOT EXISTS idx_pr_sales_order
  ON payment_receipts(sales_order_id) WHERE sales_order_id IS NOT NULL;

-- INDEX idx_pii_invoice from 14_procurement_schema_and_coa.sql:258
CREATE INDEX IF NOT EXISTS idx_pii_invoice   ON purchase_invoice_items(invoice_id);

-- INDEX idx_pii_product from 14_procurement_schema_and_coa.sql:259
CREATE INDEX IF NOT EXISTS idx_pii_product   ON purchase_invoice_items(product_id);

-- INDEX idx_pr_supplier from 16_procurement_returns_and_cancellations.sql:192
CREATE INDEX IF NOT EXISTS idx_pr_supplier  ON purchase_returns(supplier_id);

-- INDEX idx_pr_warehouse from 16_procurement_returns_and_cancellations.sql:193
CREATE INDEX IF NOT EXISTS idx_pr_warehouse ON purchase_returns(warehouse_id);

-- INDEX idx_pr_invoice from 16_procurement_returns_and_cancellations.sql:194
CREATE INDEX IF NOT EXISTS idx_pr_invoice   ON purchase_returns(original_invoice_id);

-- INDEX idx_pr_status from 16_procurement_returns_and_cancellations.sql:195
CREATE INDEX IF NOT EXISTS idx_pr_status    ON purchase_returns(status);

-- INDEX idx_pr_date from 16_procurement_returns_and_cancellations.sql:196
CREATE INDEX IF NOT EXISTS idx_pr_date      ON purchase_returns(return_date DESC);

-- INDEX idx_pri_return from 16_procurement_returns_and_cancellations.sql:229
CREATE INDEX IF NOT EXISTS idx_pri_return  ON purchase_return_items(return_id);

-- INDEX idx_pri_product from 16_procurement_returns_and_cancellations.sql:230
CREATE INDEX IF NOT EXISTS idx_pri_product ON purchase_return_items(product_id);

-- INDEX idx_nas_event_key from 52_notification_wave1a_events.sql:64
CREATE INDEX IF NOT EXISTS idx_nas_event_key  ON notification_alert_state(event_key, resolved_at);

-- INDEX idx_nas_entity_id from 52_notification_wave1a_events.sql:65
CREATE INDEX IF NOT EXISTS idx_nas_entity_id  ON notification_alert_state(entity_id, resolved_at);

-- INDEX idx_nas_last_sent from 52_notification_wave1a_events.sql:66
CREATE INDEX IF NOT EXISTS idx_nas_last_sent  ON notification_alert_state(last_sent_at) WHERE resolved_at IS NULL;

-- INDEX idx_vault_txn_raw_date from 85_analytics_query_performance_fix.sql:9
CREATE INDEX IF NOT EXISTS idx_vault_txn_raw_date ON public.vault_transactions (created_at);

-- INDEX idx_custody_txn_raw_date from 85_analytics_query_performance_fix.sql:10
CREATE INDEX IF NOT EXISTS idx_custody_txn_raw_date ON public.custody_transactions (created_at);

-- INDEX idx_cust_ledger_raw_date from 85_analytics_query_performance_fix.sql:11
CREATE INDEX IF NOT EXISTS idx_cust_ledger_raw_date ON public.customer_ledger (created_at);

-- INDEX idx_stock_movements_product_type_date from 95_inventory_analytics_rpcs.sql:9
CREATE INDEX IF NOT EXISTS idx_stock_movements_product_type_date
  ON stock_movements (product_id, type, created_at DESC);

-- INDEX idx_customer_ledger_unallocated_receipt_credit from 116_customer_advance_credit_auto_allocation.sql:35
CREATE INDEX IF NOT EXISTS idx_customer_ledger_unallocated_receipt_credit
  ON public.customer_ledger (customer_id, created_at, id)
  WHERE type = 'credit'
    AND source_type = 'payment_receipt'
    AND allocated_to IS NULL;

-- INDEX idx_customer_ledger_sales_order_debit from 116_customer_advance_credit_auto_allocation.sql:41
CREATE INDEX IF NOT EXISTS idx_customer_ledger_sales_order_debit
  ON public.customer_ledger (customer_id, source_id, created_at, id)
  WHERE type = 'debit'
    AND source_type = 'sales_order';

-- INDEX idx_soddh_order_created from 118_invoice_credit_due_date_adjustments.sql:32
CREATE INDEX IF NOT EXISTS idx_soddh_order_created
  ON public.sales_order_due_date_history(order_id, created_at DESC);

-- INDEX idx_soddh_customer_created from 118_invoice_credit_due_date_adjustments.sql:35
CREATE INDEX IF NOT EXISTS idx_soddh_customer_created
  ON public.sales_order_due_date_history(customer_id, created_at DESC);

-- FUNCTION_ACL get_available_stock from 02c_inventory_functions.sql:646
GRANT EXECUTE ON FUNCTION get_available_stock(UUID, UUID) TO authenticated;

-- FUNCTION_ACL reserve_stock from 02c_inventory_functions.sql:647
GRANT EXECUTE ON FUNCTION reserve_stock(UUID, UUID, NUMERIC) TO authenticated;

-- FUNCTION_ACL unreserve_stock from 02c_inventory_functions.sql:648
GRANT EXECUTE ON FUNCTION unreserve_stock(UUID, UUID, NUMERIC) TO authenticated;

-- FUNCTION_ACL_NOARGS add_vault_transaction from 03_financial_infrastructure.sql:1515
GRANT EXECUTE ON FUNCTION add_vault_transaction       TO authenticated;

-- FUNCTION_ACL_NOARGS add_custody_transaction from 03_financial_infrastructure.sql:1516
GRANT EXECUTE ON FUNCTION add_custody_transaction     TO authenticated;

-- FUNCTION_ACL_NOARGS confirm_payment_receipt from 03_financial_infrastructure.sql:1519
GRANT EXECUTE ON FUNCTION confirm_payment_receipt     TO authenticated;

-- FUNCTION_ACL_NOARGS check_credit_available from 03_financial_infrastructure.sql:1522
GRANT EXECUTE ON FUNCTION check_credit_available      TO authenticated;

-- FUNCTION_ACL generate_sales_order_number from 04_sales_system.sql:1441
GRANT EXECUTE ON FUNCTION generate_sales_order_number()  TO authenticated;

-- FUNCTION_ACL generate_sales_return_number from 04_sales_system.sql:1442
GRANT EXECUTE ON FUNCTION generate_sales_return_number() TO authenticated;

-- FUNCTION_ACL confirm_sales_order from 04_sales_system.sql:1443
GRANT EXECUTE ON FUNCTION confirm_sales_order(UUID, UUID) TO authenticated;

-- FUNCTION_ACL cancel_sales_order from 04_sales_system.sql:1445
GRANT EXECUTE ON FUNCTION cancel_sales_order(UUID, UUID, TEXT) TO authenticated;

-- FUNCTION_ACL confirm_sales_return from 04_sales_system.sql:1446
GRANT EXECUTE ON FUNCTION confirm_sales_return(UUID, UUID, UUID, UUID) TO authenticated;

-- FUNCTION_ACL allocate_payment_to_invoices from 04_sales_system.sql:1447
GRANT EXECUTE ON FUNCTION allocate_payment_to_invoices(UUID, NUMERIC, TEXT, UUID, UUID) TO authenticated;

-- FUNCTION_ACL_NOARGS check_customer_credit from 04b_delivery_rpcs.sql:193
GRANT EXECUTE ON FUNCTION check_customer_credit TO authenticated;

-- FUNCTION_ACL_NOARGS search_products_with_stock from 04b_delivery_rpcs.sql:355
GRANT EXECUTE ON FUNCTION search_products_with_stock TO authenticated;

-- FUNCTION_ACL_NOARGS get_user_payment_options from 04b_delivery_rpcs.sql:469
GRANT EXECUTE ON FUNCTION get_user_payment_options TO authenticated;

-- FUNCTION_ACL allocate_payment_to_invoices from 08_payment_receipts_refactor.sql:370
GRANT EXECUTE ON FUNCTION allocate_payment_to_invoices(UUID, NUMERIC, TEXT, UUID, UUID, UUID) TO authenticated;

-- FUNCTION_ACL confirm_payment_receipt from 08_payment_receipts_refactor.sql:371
GRANT EXECUTE ON FUNCTION confirm_payment_receipt(UUID, TEXT, UUID, TEXT, UUID) TO authenticated;

-- FUNCTION_ACL_NOARGS deliver_sales_order from 09_delivery_finance_sync.sql:320
GRANT EXECUTE ON FUNCTION deliver_sales_order TO authenticated;

-- FUNCTION_ACL confirm_sales_order from 10_audit_fixes.sql:223
GRANT EXECUTE ON FUNCTION confirm_sales_order(UUID, UUID) TO authenticated;

-- FUNCTION_ACL_NOARGS deliver_sales_order from 10_audit_fixes.sql:521
GRANT EXECUTE ON FUNCTION deliver_sales_order TO authenticated;

-- FUNCTION_ACL_NOARGS deliver_sales_order from 11_final_accounting_sync.sql:330
GRANT EXECUTE ON FUNCTION deliver_sales_order TO authenticated;

-- FUNCTION_ACL receive_purchase_invoice from 15_procurement_core_rpcs.sql:246
GRANT EXECUTE ON FUNCTION receive_purchase_invoice(UUID, UUID) TO authenticated;

-- FUNCTION_ACL bill_purchase_invoice from 15_procurement_core_rpcs.sql:496
GRANT EXECUTE ON FUNCTION bill_purchase_invoice(UUID, UUID, UUID, TEXT) TO authenticated;

-- FUNCTION_ACL pay_supplier from 15_procurement_core_rpcs.sql:709
GRANT EXECUTE ON FUNCTION pay_supplier(UUID, UUID, NUMERIC, TEXT, UUID, TEXT) TO authenticated;

-- FUNCTION_ACL add_vault_transaction from 16_procurement_returns_and_cancellations.sql:133
GRANT EXECUTE ON FUNCTION add_vault_transaction(UUID, TEXT, NUMERIC, TEXT, UUID, TEXT, UUID)
  TO authenticated;

-- FUNCTION_ACL cancel_purchase_invoice from 16_procurement_returns_and_cancellations.sql:537
GRANT EXECUTE ON FUNCTION cancel_purchase_invoice(UUID, UUID) TO authenticated;

-- FUNCTION_ACL confirm_purchase_return from 16_procurement_returns_and_cancellations.sql:767
GRANT EXECUTE ON FUNCTION confirm_purchase_return(UUID, UUID) TO authenticated;

-- FUNCTION_ACL create_ui_manual_journal_entry from 60_finance_field_guards.sql:105
GRANT EXECUTE ON FUNCTION create_ui_manual_journal_entry(TEXT, DATE, TEXT, UUID, JSONB, UUID) TO authenticated;

-- FUNCTION_ACL confirm_payment_receipt from 63_cash_custody_self_confirm.sql:208
GRANT EXECUTE ON FUNCTION confirm_payment_receipt(UUID, TEXT, UUID, TEXT, UUID) TO authenticated;

-- FUNCTION_ACL_NOARGS search_sales_orders from 70_missing_indexes_and_search_rpc.sql:159
GRANT EXECUTE ON FUNCTION search_sales_orders TO authenticated;

-- FUNCTION_ACL_NOARGS search_customers from 70_missing_indexes_and_search_rpc.sql:265
GRANT EXECUTE ON FUNCTION search_customers TO authenticated;

-- FUNCTION_ACL_NOARGS search_sales_orders from 71_sales_filter_enhancements.sql:191
GRANT EXECUTE ON FUNCTION search_sales_orders TO authenticated;

-- FUNCTION_ACL add_vault_transaction from 113_hr_payroll_disbursement.sql:94
GRANT EXECUTE ON FUNCTION add_vault_transaction(UUID, TEXT, NUMERIC, TEXT, UUID, TEXT, UUID) TO authenticated;

-- FUNCTION_ACL check_credit_available from 117_credit_override_honors_overdue.sql:78
GRANT EXECUTE ON FUNCTION check_credit_available(UUID, NUMERIC) TO authenticated;

-- FUNCTION_ACL update_sales_order_due_date from 118_invoice_credit_due_date_adjustments.sql:178
REVOKE EXECUTE ON FUNCTION public.update_sales_order_due_date(UUID, INTEGER, TEXT) FROM PUBLIC;

-- FUNCTION_ACL update_sales_order_due_date from 118_invoice_credit_due_date_adjustments.sql:179
GRANT EXECUTE ON FUNCTION public.update_sales_order_due_date(UUID, INTEGER, TEXT) TO authenticated;

-- FUNCTION_ACL check_credit_available from 118_invoice_credit_due_date_adjustments.sql:238
GRANT EXECUTE ON FUNCTION public.check_credit_available(UUID, NUMERIC) TO authenticated;

-- FUNCTION_ACL check_customer_credit from 118_invoice_credit_due_date_adjustments.sql:307
GRANT EXECUTE ON FUNCTION public.check_customer_credit(UUID, NUMERIC) TO authenticated;

-- FUNCTION_ACL update_sales_order_due_date from 118_invoice_credit_due_date_adjustments.sql:681
REVOKE EXECUTE ON FUNCTION public.update_sales_order_due_date(UUID, INTEGER, TEXT) FROM PUBLIC;

-- FUNCTION_ACL update_sales_order_due_date from 118_invoice_credit_due_date_adjustments.sql:682
REVOKE EXECUTE ON FUNCTION public.update_sales_order_due_date(UUID, INTEGER, TEXT) FROM anon;

-- FUNCTION_ACL update_sales_order_due_date from 118_invoice_credit_due_date_adjustments.sql:683
REVOKE EXECUTE ON FUNCTION public.update_sales_order_due_date(UUID, INTEGER, TEXT) FROM service_role;

-- FUNCTION_ACL update_sales_order_due_date from 118_invoice_credit_due_date_adjustments.sql:684
GRANT EXECUTE ON FUNCTION public.update_sales_order_due_date(UUID, INTEGER, TEXT) TO authenticated;

-- TABLE_ACL sales_order_due_date_history from 118_invoice_credit_due_date_adjustments.sql:50
REVOKE ALL ON public.sales_order_due_date_history FROM PUBLIC;

-- TABLE_ACL sales_order_due_date_history from 118_invoice_credit_due_date_adjustments.sql:51
GRANT SELECT ON public.sales_order_due_date_history TO authenticated;

-- TABLE_ACL sales_order_due_date_history from 118_invoice_credit_due_date_adjustments.sql:674
REVOKE ALL ON TABLE public.sales_order_due_date_history FROM PUBLIC;

-- TABLE_ACL sales_order_due_date_history from 118_invoice_credit_due_date_adjustments.sql:675
REVOKE ALL ON TABLE public.sales_order_due_date_history FROM anon;

-- TABLE_ACL sales_order_due_date_history from 118_invoice_credit_due_date_adjustments.sql:676
REVOKE ALL ON TABLE public.sales_order_due_date_history FROM authenticated;

-- TABLE_ACL sales_order_due_date_history from 118_invoice_credit_due_date_adjustments.sql:677
REVOKE ALL ON TABLE public.sales_order_due_date_history FROM service_role;

-- TABLE_ACL sales_order_due_date_history from 118_invoice_credit_due_date_adjustments.sql:679
GRANT SELECT ON TABLE public.sales_order_due_date_history TO authenticated;

-- Separate owned local safety setup (not canonical policy/grant source)
ALTER TABLE public.product_units ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.price_list_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.price_list_assignments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "areas_read" ON areas;
CREATE POLICY "areas_read" ON areas FOR SELECT
USING (((SELECT auth.uid()) IS NOT NULL));

DROP POLICY IF EXISTS "areas_write" ON areas;
CREATE POLICY "areas_write" ON areas FOR ALL
USING ((SELECT check_permission((SELECT auth.uid()), 'branches.create'::text)));

DROP POLICY IF EXISTS "branches_read" ON branches;
CREATE POLICY "branches_read" ON branches FOR SELECT
USING ((SELECT check_permission((SELECT auth.uid()), 'branches.read'::text)));

DROP POLICY IF EXISTS "branches_write" ON branches;
CREATE POLICY "branches_write" ON branches FOR ALL
USING ((SELECT check_permission((SELECT auth.uid()), 'branches.create'::text)));

DROP POLICY IF EXISTS "brands_read" ON brands;
CREATE POLICY "brands_read" ON brands FOR SELECT
USING ((SELECT check_permission((SELECT auth.uid()), 'products.read'::text)));

DROP POLICY IF EXISTS "brands_write" ON brands;
CREATE POLICY "brands_write" ON brands FOR ALL
USING ((SELECT check_permission((SELECT auth.uid()), 'products.create'::text)));

DROP POLICY IF EXISTS "cities_read" ON cities;
CREATE POLICY "cities_read" ON cities FOR SELECT
USING (((SELECT auth.uid()) IS NOT NULL));

DROP POLICY IF EXISTS "custody_read" ON custody_accounts;
CREATE POLICY "custody_read" ON custody_accounts FOR SELECT
USING (((employee_id = (SELECT auth.uid())) OR (SELECT check_permission((SELECT auth.uid()), 'finance.custody.read_all'::text))));

DROP POLICY IF EXISTS "custody_write" ON custody_accounts;
CREATE POLICY "custody_write" ON custody_accounts FOR ALL
USING ((SELECT check_permission((SELECT auth.uid()), 'finance.custody.create'::text)));

DROP POLICY IF EXISTS "customer_branches_delete" ON customer_branches;
CREATE POLICY "customer_branches_delete" ON customer_branches FOR DELETE
USING ((SELECT check_permission((SELECT auth.uid()), 'customers.update'::text)));

DROP POLICY IF EXISTS "customer_branches_insert" ON customer_branches;
CREATE POLICY "customer_branches_insert" ON customer_branches FOR INSERT
WITH CHECK (((SELECT check_permission((SELECT auth.uid()), 'customers.create'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'customers.update'::text))));

DROP POLICY IF EXISTS "customer_branches_modify" ON customer_branches;
CREATE POLICY "customer_branches_modify" ON customer_branches FOR UPDATE
USING ((SELECT check_permission((SELECT auth.uid()), 'customers.update'::text)));

DROP POLICY IF EXISTS "customer_branches_read" ON customer_branches;
CREATE POLICY "customer_branches_read" ON customer_branches FOR SELECT
USING (((SELECT check_permission((SELECT auth.uid()), 'customers.read_all'::text)) OR ((SELECT check_permission((SELECT auth.uid()), 'customers.read'::text)) AND (customer_id IN ( SELECT customers.id
   FROM customers
  WHERE (customers.assigned_rep_id = (SELECT auth.uid())))))));

DROP POLICY IF EXISTS "geo_read" ON governorates;
CREATE POLICY "geo_read" ON governorates FOR SELECT
USING (((SELECT auth.uid()) IS NOT NULL));

DROP POLICY IF EXISTS "price_lists_read" ON price_lists;
CREATE POLICY "price_lists_read" ON price_lists FOR SELECT
USING ((SELECT check_permission((SELECT auth.uid()), 'price_lists.read'::text)));

DROP POLICY IF EXISTS "price_lists_write" ON price_lists;
CREATE POLICY "price_lists_write" ON price_lists FOR ALL
USING ((SELECT check_permission((SELECT auth.uid()), 'price_lists.update'::text)));

DROP POLICY IF EXISTS "categories_read" ON product_categories;
CREATE POLICY "categories_read" ON product_categories FOR SELECT
USING ((SELECT check_permission((SELECT auth.uid()), 'products.read'::text)));

DROP POLICY IF EXISTS "categories_write" ON product_categories;
CREATE POLICY "categories_write" ON product_categories FOR ALL
USING ((SELECT check_permission((SELECT auth.uid()), 'categories.create'::text)));

DROP POLICY IF EXISTS "shipping_read" ON shipping_companies;
CREATE POLICY "shipping_read" ON shipping_companies FOR SELECT
USING (((SELECT auth.uid()) IS NOT NULL));

DROP POLICY IF EXISTS "shipping_write" ON shipping_companies;
CREATE POLICY "shipping_write" ON shipping_companies FOR ALL
USING ((SELECT check_permission((SELECT auth.uid()), 'sales.shipping.manage'::text)));

DROP POLICY IF EXISTS "suppliers_delete" ON suppliers;
CREATE POLICY "suppliers_delete" ON suppliers FOR DELETE
USING ((SELECT check_permission((SELECT auth.uid()), 'suppliers.delete'::text)));

DROP POLICY IF EXISTS "suppliers_read" ON suppliers;
CREATE POLICY "suppliers_read" ON suppliers FOR SELECT
USING ((SELECT check_permission((SELECT auth.uid()), 'suppliers.read'::text)));

DROP POLICY IF EXISTS "suppliers_update" ON suppliers;
CREATE POLICY "suppliers_update" ON suppliers FOR UPDATE
USING ((SELECT check_permission((SELECT auth.uid()), 'suppliers.update'::text)));

DROP POLICY IF EXISTS "suppliers_write" ON suppliers;
CREATE POLICY "suppliers_write" ON suppliers FOR INSERT
WITH CHECK ((SELECT check_permission((SELECT auth.uid()), 'suppliers.create'::text)));

DROP POLICY IF EXISTS "units_read" ON units;
CREATE POLICY "units_read" ON units FOR SELECT
USING (((SELECT auth.uid()) IS NOT NULL));

DROP POLICY IF EXISTS "units_write" ON units;
CREATE POLICY "units_write" ON units FOR ALL
USING ((SELECT check_permission((SELECT auth.uid()), 'products.create'::text)));

DROP POLICY IF EXISTS "vaults_insert" ON vaults;
CREATE POLICY "vaults_insert" ON vaults FOR INSERT
WITH CHECK ((SELECT check_permission((SELECT auth.uid()), 'finance.vaults.create'::text)));

DROP POLICY IF EXISTS "vaults_read" ON vaults;
CREATE POLICY "vaults_read" ON vaults FOR SELECT
USING (((SELECT check_permission((SELECT auth.uid()), 'finance.vaults.read_all'::text)) OR ((SELECT check_permission((SELECT auth.uid()), 'finance.vaults.read'::text)) AND (responsible_id = (SELECT auth.uid())))));

DROP POLICY IF EXISTS "vaults_update" ON vaults;
CREATE POLICY "vaults_update" ON vaults FOR UPDATE
USING ((SELECT check_permission((SELECT auth.uid()), 'finance.vaults.update'::text)));

ROLLBACK;
