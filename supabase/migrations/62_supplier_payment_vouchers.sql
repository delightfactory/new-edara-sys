-- ============================================================
-- 62_supplier_payment_vouchers.sql  [v2 — REVIEWED & PATCHED]
-- EDARA v2 — سندات صرف الموردين (دفعات مستقلة بدون فاتورة)
--
-- الغرض:
--   تمكين تسجيل دفعات للموردين غير مرتبطة بفاتورة شراء محددة.
--   مثال: سداد رصيد افتتاحي، دفعة مقدمة، سداد دين تراكمي.
--
-- سجل التغيير:
--   v1 — الإصدار الأول
--   v2 — إصلاح حرج: journal_entries_source_type_check
--        يجب أن يتضمن كل الأنواع المُضافة في المهاجرات السابقة:
--          16_procurement: purchase_cancellation
--          19c_advances:   hr_advance
--          20d_fix_je:     hr_payroll
--        تجاهل أي منها يُعطّل الدوال المالية لـ HR والمشتريات.
--
-- مبدأ التوافق مع النظام المالي المعتمد:
--   1. vault_transactions: type='vendor_payment' (migration 16)
--   2. supplier_ledger: source_type='payment', source_id=UUID فريد
--      (نفس الأسلوب المُتبع في pay_supplier و bill_purchase_invoice)
--   3. journal_entries: source_type='supplier_payment' (مُضاف هنا)
--   4. الصلاحية: procurement.invoices.pay (migration 14)
--   5. UNIQUE supplier_ledger(source_type, source_id) → source_id فريد دائماً
--
-- القيد المحاسبي:
--   نقدي/بنكي/محفظة: DR:2100 / CR:1110/1120/1130
--   شيك:              DR:2100 / CR:2110 (أوراق دفع للموردين)
--
-- Idempotent: آمن للتشغيل أكثر من مرة
-- ============================================================


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  Step 1: ترقية CHECK constraint لـ journal_entries        ║
-- ║                                                           ║
-- ║  تحذير: يجب دائماً تضمين كل الأنواع من المهاجرات السابقة ║
-- ║  لأن DROP + ADD يُلغي الـ constraint القديم كاملاً.        ║
-- ║                                                           ║
-- ║  الأنواع المُجمَّعة من كل المهاجرات السابقة:              ║
-- ║    03_financial: sales_order, sales_return, payment,      ║
-- ║                  purchase_order, expense, custody,        ║
-- ║                  transfer, manual                         ║
-- ║    16_procurement: purchase_return, purchase_cancellation ║
-- ║    19c_advances:   hr_advance                             ║
-- ║    20d_fix_je:     hr_payroll                             ║
-- ║    62 (هذا الملف): supplier_payment ← جديد               ║
-- ╚═══════════════════════════════════════════════════════════╝

ALTER TABLE journal_entries
  DROP CONSTRAINT IF EXISTS journal_entries_source_type_check;

ALTER TABLE journal_entries
  ADD CONSTRAINT journal_entries_source_type_check
  CHECK (source_type IN (
    -- من 03_financial_infrastructure ----------------------------
    'sales_order',
    'sales_return',
    'payment',
    'purchase_order',
    'expense',
    'custody',
    'transfer',
    'manual',
    -- من 16_procurement_returns_and_cancellations ---------------
    'purchase_return',
    'purchase_cancellation',
    -- من 19c_advances_finance_sync ------------------------------
    'hr_advance',
    -- من 20d_fix_je_source_type ---------------------------------
    'hr_payroll',
    -- من 62 (هذا الملف) ← الإضافة الجديدة ---------------------
    'supplier_payment'
  ));


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  Step 2: جدول سندات صرف الموردين                          ║
-- ╚═══════════════════════════════════════════════════════════╝

CREATE SEQUENCE IF NOT EXISTS supplier_payment_voucher_seq START WITH 1;

CREATE TABLE IF NOT EXISTS supplier_payment_vouchers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  number          TEXT UNIQUE,
  supplier_id     UUID NOT NULL REFERENCES suppliers(id),
  amount          NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  payment_date    DATE NOT NULL DEFAULT CURRENT_DATE,
  payment_method  TEXT NOT NULL CHECK (payment_method IN (
    'cash', 'bank_transfer', 'cheque', 'mobile_wallet'
  )),
  vault_id        UUID REFERENCES vaults(id),   -- NULL للشيكات
  vault_txn_id    UUID,                          -- UUID حركة الخزينة
  notes           TEXT,
  status          TEXT NOT NULL DEFAULT 'posted'
                  CHECK (status IN ('posted', 'reversed')),
  created_by      UUID REFERENCES profiles(id),
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

-- Trigger: الترقيم التلقائي SUPAY-YYYYMMDD-XXXX
CREATE OR REPLACE FUNCTION generate_supplier_payment_number()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.number IS NULL OR NEW.number = '' THEN
    NEW.number := 'SUPAY-' || to_char(CURRENT_DATE, 'YYYYMMDD')
               || '-' || lpad(nextval('supplier_payment_voucher_seq')::text, 4, '0');
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_supplier_payment_number ON supplier_payment_vouchers;
CREATE TRIGGER trg_supplier_payment_number
  BEFORE INSERT ON supplier_payment_vouchers
  FOR EACH ROW EXECUTE FUNCTION generate_supplier_payment_number();

DROP TRIGGER IF EXISTS trg_spv_updated_at ON supplier_payment_vouchers;
CREATE TRIGGER trg_spv_updated_at
  BEFORE UPDATE ON supplier_payment_vouchers
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS idx_spv_supplier  ON supplier_payment_vouchers(supplier_id);
CREATE INDEX IF NOT EXISTS idx_spv_date      ON supplier_payment_vouchers(payment_date DESC);
CREATE INDEX IF NOT EXISTS idx_spv_status    ON supplier_payment_vouchers(status);
CREATE INDEX IF NOT EXISTS idx_spv_created   ON supplier_payment_vouchers(created_at DESC);


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  Step 3: RLS — سياسات أمان الصفوف                         ║
-- ╚═══════════════════════════════════════════════════════════╝

ALTER TABLE supplier_payment_vouchers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "spv_read"   ON supplier_payment_vouchers;
CREATE POLICY "spv_read" ON supplier_payment_vouchers FOR SELECT
  USING (
    check_permission(auth.uid(), 'procurement.invoices.pay')
    OR check_permission(auth.uid(), 'procurement.invoices.read')
  );

DROP POLICY IF EXISTS "spv_insert" ON supplier_payment_vouchers;
CREATE POLICY "spv_insert" ON supplier_payment_vouchers FOR INSERT
  WITH CHECK (check_permission(auth.uid(), 'procurement.invoices.pay'));

-- UPDATE مقيّد — التعكيس المستقبلي عبر RPC فقط
DROP POLICY IF EXISTS "spv_update" ON supplier_payment_vouchers;
CREATE POLICY "spv_update" ON supplier_payment_vouchers FOR UPDATE
  USING (check_permission(auth.uid(), 'procurement.invoices.pay'));


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  Step 4: RPC — pay_supplier_account  [v2]                 ║
-- ║                                                           ║
-- ║  دفعة مستقلة للمورد (بدون invoice_id)                     ║
-- ║                                                           ║
-- ║  التوافق المُتحقَّق منه:                                   ║
-- ║  ① add_vault_transaction: type='vendor_payment'            ║
-- ║    معتمد في migration 16 (يُعدّ سحباً من الخزينة)           ║
-- ║  ② supplier_ledger: source_type='payment'                  ║
-- ║    معتمد في CHECK constraint (migration 16 لم يغيّره)      ║
-- ║    source_id = UUID فريد (vault_txn_id أو random UUID)     ║
-- ║    → يضمن عدم تعارض UNIQUE(source_type, source_id)         ║
-- ║  ③ create_manual_journal_entry:                            ║
-- ║    p_entry_date = DATE ✅ (signature migration 03j)        ║
-- ║    source_type='supplier_payment' ✅ (مُضاف في Step 1)     ║
-- ║  ④ Security: SECURITY DEFINER + check_permission           ║
-- ║    + auth.uid() anti-spoofing guard                        ║
-- ║                                                           ║
-- ║  القيود المحاسبية:                                         ║
-- ║    نقدي:   DR:2100 / CR:1110 (صندوق نقدي)                 ║
-- ║    بنكي:   DR:2100 / CR:1120 (بنك)                        ║
-- ║    محفظة:  DR:2100 / CR:1130 (محفظة إلكترونية)            ║
-- ║    شيك:    DR:2100 / CR:2110 (أوراق دفع للموردين)         ║
-- ╚═══════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION pay_supplier_account(
  p_supplier_id    UUID,
  p_user_id        UUID,
  p_amount         NUMERIC,
  p_payment_method TEXT    DEFAULT 'cash',
  p_vault_id       UUID    DEFAULT NULL,
  p_notes          TEXT    DEFAULT NULL,
  p_payment_date   DATE    DEFAULT NULL
) RETURNS UUID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_supplier        suppliers%ROWTYPE;
  v_vault_type      TEXT;
  v_credit_account  TEXT;
  v_is_cheque       BOOLEAN := false;

  -- UUID يُستخدم كـ source_id في supplier_ledger
  -- للنقدي/بنكي/محفظة: UUID حركة الخزينة (فريد بطبيعته)
  -- للشيك: gen_random_uuid() (فريد بطبيعته)
  v_txn_id          UUID;

  v_voucher_id      UUID;
  v_voucher_number  TEXT;
  v_journal_lines   JSONB;
  v_eff_date        DATE;
BEGIN
  -- ══════════════════════════════════════════════════════════
  -- [SECURITY GUARD A] — منع انتحال الهوية
  -- ══════════════════════════════════════════════════════════
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL
     AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- [SECURITY GUARD B] — التحقق من الصلاحية
  -- ══════════════════════════════════════════════════════════
  IF NOT check_permission(p_user_id, 'procurement.invoices.pay') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية سداد مستحقات الموردين';
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- 1. التحقق من بيانات الإدخال
  -- ══════════════════════════════════════════════════════════
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'مبلغ الدفعة يجب أن يكون أكبر من صفر (المُستلم: %)',
      COALESCE(p_amount::TEXT, 'NULL');
  END IF;

  IF p_payment_method NOT IN ('cash', 'bank_transfer', 'cheque', 'mobile_wallet') THEN
    RAISE EXCEPTION 'طريقة دفع غير صالحة: %. القيم المقبولة: cash, bank_transfer, cheque, mobile_wallet',
      p_payment_method;
  END IF;

  v_is_cheque := (p_payment_method = 'cheque');

  IF NOT v_is_cheque AND p_vault_id IS NULL THEN
    RAISE EXCEPTION 'يجب تحديد معرّف الخزينة (p_vault_id) للسداد النقدي / البنكي / المحفظة';
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- 2. قفل المورد (FOR UPDATE) والتحقق من صحة بياناته
  -- ══════════════════════════════════════════════════════════
  SELECT * INTO v_supplier
  FROM suppliers
  WHERE id = p_supplier_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'المورد غير موجود: %', p_supplier_id;
  END IF;

  IF NOT v_supplier.is_active THEN
    RAISE EXCEPTION 'المورد غير نشط: % — لا يمكن السداد لمورد معطل',
      v_supplier.name;
  END IF;

  v_eff_date := COALESCE(p_payment_date, CURRENT_DATE);

  -- ══════════════════════════════════════════════════════════
  -- 3. تحديد مسار الدفع والحساب الدائن
  -- ══════════════════════════════════════════════════════════
  IF v_is_cheque THEN
    -- مسار الشيك: لا خصم فوري من الخزينة
    -- القيد: DR:2100 / CR:2110 (أوراق دفع للموردين)
    v_credit_account := '2110';
    v_txn_id         := gen_random_uuid();

  ELSE
    -- مسار نقدي/بنكي/محفظة: سحب فعلي من الخزينة
    -- add_vault_transaction تُقفل الخزينة (FOR UPDATE) وتتحقق من الرصيد

    SELECT type INTO v_vault_type
    FROM vaults
    WHERE id = p_vault_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'الخزينة غير موجودة: %', p_vault_id;
    END IF;

    -- تحديد حساب GL الدائن بناءً على نوع الخزينة
    v_credit_account := CASE v_vault_type
      WHEN 'cash'          THEN '1110'   -- صندوق نقدي
      WHEN 'bank'          THEN '1120'   -- حساب بنكي
      WHEN 'mobile_wallet' THEN '1130'   -- محفظة إلكترونية
      ELSE '1110'                        -- fallback آمن
    END;

    -- استدعاء add_vault_transaction بـ type='vendor_payment'
    -- (مُعتمد في migration 16 — يُعدّ سحباً يُخفّض الرصيد)
    v_txn_id := add_vault_transaction(
      p_vault_id,
      'vendor_payment',              -- معتمد في migration 16
      p_amount,
      'supplier_payment',            -- reference_type (حقل TEXT حر — لا CHECK)
      NULL,                          -- reference_id: يُحدَّث بعد إنشاء السند
      COALESCE(
        p_notes,
        'سداد مورد — ' || v_supplier.name
      ),
      p_user_id
    );
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- 4. إنشاء سند الصرف (رقم تلقائي عبر Trigger)
  -- ══════════════════════════════════════════════════════════
  INSERT INTO supplier_payment_vouchers (
    supplier_id, amount, payment_date, payment_method,
    vault_id, vault_txn_id, notes, created_by
  ) VALUES (
    p_supplier_id,
    p_amount,
    v_eff_date,
    p_payment_method,
    CASE WHEN v_is_cheque THEN NULL ELSE p_vault_id END,
    v_txn_id,
    p_notes,
    p_user_id
  )
  RETURNING id, number INTO v_voucher_id, v_voucher_number;

  -- ربط حركة الخزينة بالسند (بعد معرفة UUID السند)
  IF NOT v_is_cheque THEN
    UPDATE vault_transactions
    SET reference_id = v_voucher_id
    WHERE id = v_txn_id;
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- 5. القيد المحاسبي
  --    DR:2100 (ذمم الموردين — تقليل الدين)
  --    CR:1110/1120/1130 أو CR:2110 (خروج النقدية أو الشيك)
  -- ══════════════════════════════════════════════════════════
  v_journal_lines := jsonb_build_array(
    jsonb_build_object(
      'account_code', '2100',
      'debit',        p_amount,
      'credit',       0,
      'description',  'تسوية ذمم مورد — ' || v_supplier.name
                      || ' / ' || COALESCE(v_voucher_number, '')
    ),
    jsonb_build_object(
      'account_code', v_credit_account,
      'debit',        0,
      'credit',       p_amount,
      'description',
      CASE WHEN v_is_cheque
        THEN 'شيك مُصدر للمورد — ' || v_supplier.name
             || ' / ' || COALESCE(v_voucher_number, '')
        ELSE 'دفعة مورد — ' || v_supplier.name
             || ' / ' || COALESCE(v_voucher_number, '')
      END
    )
  );

  -- استدعاء create_manual_journal_entry:
  --   p_description  TEXT
  --   p_entry_date   DATE  ← مطابق للـ signature في 03j
  --   p_source_type  TEXT  ← 'supplier_payment' (مُضاف في Step 1)
  --   p_source_id    UUID  ← UUID السند
  --   p_lines        JSONB
  --   p_user_id      UUID
  PERFORM create_manual_journal_entry(
    'سداد مورد — ' || v_supplier.name || ' / ' || COALESCE(v_voucher_number, ''),
    v_eff_date,
    'supplier_payment',
    v_voucher_id,
    v_journal_lines,
    p_user_id
  );

  -- ══════════════════════════════════════════════════════════
  -- 6. دفتر الموردين — Debit (تخفيض الدين)
  --    source_type = 'payment' (معتمد في CHECK constraint)
  --    source_id   = v_txn_id (UUID فريد دائماً)
  --    → لا تعارض مع UNIQUE(source_type, source_id)
  --
  --    ملاحظة: للشيك v_txn_id = gen_random_uuid() (فريد).
  --    للنقدي/بنكي v_txn_id = UUID حركة الخزينة (فريد).
  -- ══════════════════════════════════════════════════════════
  INSERT INTO supplier_ledger (
    supplier_id, type,    amount,
    source_type, source_id,
    description, created_by
  ) VALUES (
    p_supplier_id,
    'debit',
    p_amount,
    'payment',   -- معتمد في constraint (migration 16)
    v_txn_id,    -- UUID فريد — يضمن UNIQUE(source_type, source_id)
    COALESCE(
      p_notes,
      'دفعة مستقلة — ' || v_supplier.name
      || ' / ' || COALESCE(v_voucher_number, '')
    ),
    p_user_id
  );

  RETURN v_voucher_id;
END; $$;

GRANT EXECUTE ON FUNCTION pay_supplier_account(UUID, UUID, NUMERIC, TEXT, UUID, TEXT, DATE)
  TO authenticated;


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  Step 5: حقوق الاطلاع                                     ║
-- ╚═══════════════════════════════════════════════════════════╝

-- procurement.invoices.pay موجودة بالفعل لـ accountant و ceo
-- procurement.invoices.read موجودة بالفعل لـ branch_manager
-- لا نضيف صلاحيات جديدة — نستخدم الموجودة


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  Step 6: التحقق النهائي الشامل                            ║
-- ╚═══════════════════════════════════════════════════════════╝

DO $$
DECLARE
  v_count      INTEGER;
  v_constraint TEXT;
BEGIN
  -- ── 1. الجدول موجود ──
  SELECT COUNT(*) INTO v_count FROM information_schema.tables
  WHERE table_name = 'supplier_payment_vouchers' AND table_schema = 'public';
  RAISE NOTICE '[62-v2] جدول supplier_payment_vouchers: % (يجب = 1)', v_count;
  IF v_count = 0 THEN RAISE EXCEPTION '[62-v2] ❌ الجدول غير موجود!'; END IF;

  -- ── 2. journal constraint يشمل كل الأنواع المطلوبة ──
  SELECT check_clause INTO v_constraint
  FROM information_schema.check_constraints
  WHERE constraint_name = 'journal_entries_source_type_check';

  RAISE NOTICE '[62-v2] journal constraint: %', COALESCE(v_constraint, 'NOT FOUND');

  IF v_constraint NOT LIKE '%supplier_payment%' THEN
    RAISE EXCEPTION '[62-v2] ❌ supplier_payment غير موجود في journal constraint!';
  END IF;
  IF v_constraint NOT LIKE '%hr_advance%' THEN
    RAISE EXCEPTION '[62-v2] ❌ hr_advance مفقود من journal constraint — تحذير: يُعطّل صرف السلف!';
  END IF;
  IF v_constraint NOT LIKE '%hr_payroll%' THEN
    RAISE EXCEPTION '[62-v2] ❌ hr_payroll مفقود من journal constraint!';
  END IF;
  IF v_constraint NOT LIKE '%purchase_cancellation%' THEN
    RAISE EXCEPTION '[62-v2] ❌ purchase_cancellation مفقود من journal constraint!';
  END IF;

  -- ── 3. supplier_ledger constraint لم يتغيّر ──
  SELECT check_clause INTO v_constraint
  FROM information_schema.check_constraints
  WHERE constraint_name = 'supplier_ledger_source_type_check';

  IF v_constraint NOT LIKE '%payment%' THEN
    RAISE EXCEPTION '[62-v2] ❌ supplier_ledger لا يقبل source_type=payment!';
  END IF;
  RAISE NOTICE '[62-v2] supplier_ledger constraint: ✅ يقبل payment';

  -- ── 4. vault_transactions constraint يشمل vendor_payment ──
  SELECT check_clause INTO v_constraint
  FROM information_schema.check_constraints
  WHERE constraint_name = 'vault_transactions_type_check';

  IF v_constraint NOT LIKE '%vendor_payment%' THEN
    RAISE EXCEPTION '[62-v2] ❌ vault_transactions لا يقبل type=vendor_payment — راجع migration 16!';
  END IF;
  RAISE NOTICE '[62-v2] vault_transactions constraint: ✅ يقبل vendor_payment';

  -- ── 5. RPC موجود ──
  SELECT COUNT(*) INTO v_count
  FROM information_schema.routines
  WHERE routine_name = 'pay_supplier_account' AND routine_schema = 'public';
  RAISE NOTICE '[62-v2] RPC pay_supplier_account: % (يجب = 1)', v_count;
  IF v_count = 0 THEN RAISE EXCEPTION '[62-v2] ❌ RPC غير موجود!'; END IF;

  -- ── 6. الحسابات الجوهرية موجودة ──
  SELECT COUNT(*) INTO v_count FROM chart_of_accounts
  WHERE code IN ('2100', '1110', '1120', '1130', '2110');
  RAISE NOTICE '[62-v2] حسابات COA المطلوبة: % / 5', v_count;
  IF v_count < 5 THEN
    RAISE WARNING '[62-v2] ⚠️ بعض الحسابات قد تكون غير موجودة — راجع COA';
  END IF;

  RAISE NOTICE '[62-v2] ✅ كل الفحوصات اجتازت — سندات صرف الموردين جاهزة';
END $$;
