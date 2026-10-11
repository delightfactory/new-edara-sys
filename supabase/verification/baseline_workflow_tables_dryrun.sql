BEGIN;
DO $$ BEGIN
  CREATE TYPE sales_return_status AS ENUM ('draft', 'confirmed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;
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
ALTER TABLE public.product_units ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chart_of_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vault_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.custody_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.journal_entry_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_returns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_return_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_invoice_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_returns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_return_items ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r') <> 44 THEN RAISE EXCEPTION 'Unexpected table closure'; END IF; IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND NOT c.relrowsecurity) THEN RAISE EXCEPTION 'RLS missing'; END IF; END; $$;
ROLLBACK;
