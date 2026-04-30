-- ============================================================
-- Migration 113: HR Payroll Disbursement
-- EDARA v2 — نظام صرف الرواتب
-- ============================================================

-- 1. ترقية القيود (Check Constraints) للخزائن والقيود المحاسبية
ALTER TABLE vault_transactions
  DROP CONSTRAINT IF EXISTS vault_transactions_type_check;

ALTER TABLE vault_transactions
  ADD CONSTRAINT vault_transactions_type_check
  CHECK (type IN (
    'deposit', 'withdrawal', 'transfer_in', 'transfer_out',
    'collection', 'expense', 'custody_load', 'custody_return',
    'opening_balance', 'vendor_payment', 'vendor_refund', 'payroll_payment'
  ));

ALTER TABLE journal_entries
  DROP CONSTRAINT IF EXISTS journal_entries_source_type_check;

ALTER TABLE journal_entries
  ADD CONSTRAINT journal_entries_source_type_check
  CHECK (source_type IN (
    'sales_order', 'sales_return', 'payment',
    'purchase_order', 'purchase_return', 'purchase_cancellation',
    'expense', 'custody', 'transfer', 'manual',
    'hr_advance', 'hr_payroll', 'supplier_payment', 'hr_payroll_payment'
  ));


-- 2. تحديث دالة add_vault_transaction لدعم payroll_payment كسحب
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

GRANT EXECUTE ON FUNCTION add_vault_transaction(UUID, TEXT, NUMERIC, TEXT, UUID, TEXT, UUID) TO authenticated;


-- 3. إنشاء جدول دفعات الرواتب
CREATE TABLE IF NOT EXISTS hr_payroll_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payroll_run_id UUID NOT NULL REFERENCES hr_payroll_runs(id),
  vault_id UUID NOT NULL REFERENCES vaults(id),
  amount NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  payment_date DATE NOT NULL DEFAULT CURRENT_DATE,
  vault_txn_id UUID REFERENCES vault_transactions(id),
  journal_entry_id UUID REFERENCES journal_entries(id),
  status TEXT NOT NULL CHECK (status IN ('posted', 'voided')) DEFAULT 'posted',
  notes TEXT,

  -- للحفاظ على السجل المالي في حال الإلغاء
  voided_by UUID REFERENCES profiles(id),
  voided_at TIMESTAMPTZ,
  void_reason TEXT,
  reversal_journal_entry_id UUID REFERENCES journal_entries(id),

  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_hr_pay_run ON hr_payroll_payments(payroll_run_id);
CREATE INDEX IF NOT EXISTS idx_hr_pay_vault ON hr_payroll_payments(vault_id);
CREATE INDEX IF NOT EXISTS idx_hr_pay_date ON hr_payroll_payments(payment_date DESC);
CREATE INDEX IF NOT EXISTS idx_hr_pay_je ON hr_payroll_payments(journal_entry_id);

DROP TRIGGER IF EXISTS trg_hr_payroll_payments_updated_at ON hr_payroll_payments;
CREATE TRIGGER trg_hr_payroll_payments_updated_at
  BEFORE UPDATE ON hr_payroll_payments
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 4. صلاحيات RLS (حماية ضد الإدراج والتعديل المباشر من الواجهة)
ALTER TABLE hr_payroll_payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "hr_ppay_read" ON hr_payroll_payments;
CREATE POLICY "hr_ppay_read" ON hr_payroll_payments FOR SELECT
  USING (
    check_permission(auth.uid(), 'hr.payroll.read') 
    OR check_permission(auth.uid(), 'finance.vaults.read')
  );

-- لا توجد سياسات INSERT/UPDATE/DELETE. يُسمح فقط للدوال (RPCs) التي تعمل كـ SECURITY DEFINER.


-- 5. الصلاحية الجديدة لصرف الرواتب
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES ('hr.payroll.disburse')) AS p(perm)
WHERE r.name IN ('accountant', 'ceo')
ON CONFLICT DO NOTHING;


-- 6. الدالة المحورية: صرف دفعة رواتب
CREATE OR REPLACE FUNCTION disburse_payroll_payment(
  p_run_id       UUID,
  p_vault_id     UUID,
  p_amount       NUMERIC,
  p_payment_date DATE DEFAULT CURRENT_DATE,
  p_notes        TEXT DEFAULT NULL,
  p_user_id      UUID DEFAULT auth.uid()
) RETURNS JSONB
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_run             hr_payroll_runs%ROWTYPE;
  v_period          hr_payroll_periods%ROWTYPE;
  v_vault           vaults%ROWTYPE;
  v_total_net_lines NUMERIC;
  v_total_paid      NUMERIC;
  v_remaining       NUMERIC;
  v_payment_id      UUID;
  v_vault_txn_id    UUID;
  v_je_id           UUID;
  v_coa_vault       TEXT;
  v_journal_lines   JSONB := '[]'::JSONB;
BEGIN
  -- أ) التحقق من الصلاحيات
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  IF NOT check_permission(p_user_id, 'hr.payroll.disburse') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية صرف الرواتب';
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'مبلغ الصرف يجب أن يكون أكبر من صفر';
  END IF;

  -- ب) قفل المسير
  SELECT * INTO v_run FROM hr_payroll_runs WHERE id = p_run_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'مسير الرواتب غير موجود'; END IF;

  IF v_run.status NOT IN ('approved', 'paid') THEN
    RAISE EXCEPTION 'لا يمكن صرف مسير في حالة: %', v_run.status;
  END IF;

  -- التأكد من أن المسير معتمد محاسبيًا (له قيد)
  IF v_run.journal_entry_id IS NULL THEN
    RAISE EXCEPTION 'هذا المسير غير مرتبط بقيد استحقاق (journal_entry_id = null)، لا يمكن الصرف.';
  END IF;

  SELECT * INTO v_period FROM hr_payroll_periods WHERE id = v_run.period_id;

  -- ج) التأكد من صحة الخزنة (نفس الفرع أو خزنة مركزية)
  SELECT * INTO v_vault FROM vaults WHERE id = p_vault_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'الخزنة غير موجودة'; END IF;

  IF v_run.branch_id IS NOT NULL AND v_vault.branch_id IS NOT NULL AND v_run.branch_id != v_vault.branch_id THEN
    RAISE EXCEPTION 'لا يمكن صرف رواتب فرع من خزنة تابعة لفرع آخر. اختر خزنة نفس الفرع أو خزنة مركزية.';
  END IF;

  -- د) حساب الإجمالي المستحق من سطور الرواتب لضمان الدقة
  SELECT COALESCE(SUM(net_salary), 0) INTO v_total_net_lines
  FROM hr_payroll_lines
  WHERE payroll_run_id = p_run_id;

  -- حساب ما تم دفعه مسبقاً
  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM hr_payroll_payments
  WHERE payroll_run_id = p_run_id AND status = 'posted';

  v_remaining := ROUND(v_total_net_lines - v_total_paid, 2);

  IF ROUND(p_amount, 2) > v_remaining + 0.05 THEN
    RAISE EXCEPTION 'المبلغ المطلوب صرفه (%) يتجاوز المتبقي من المستحقات (%)', p_amount, v_remaining;
  END IF;

  -- هـ) إدراج سجل مبدئي لدفعة الصرف للحصول على الـ ID
  INSERT INTO hr_payroll_payments (
    payroll_run_id, vault_id, amount, payment_date, notes, created_by
  ) VALUES (
    p_run_id, p_vault_id, p_amount, p_payment_date, p_notes, p_user_id
  ) RETURNING id INTO v_payment_id;

  -- و) خصم المبلغ من الخزنة
  v_vault_txn_id := add_vault_transaction(
    p_vault_id,
    'payroll_payment',
    p_amount,
    'hr_payroll_payment',
    v_payment_id,
    'صرف رواتب ' || v_period.name || COALESCE(' - ' || p_notes, ''),
    p_user_id
  );

  -- ز) إعداد وإنشاء القيد المحاسبي
  
  -- تحديد حساب الخزنة حسب نوعها
  IF v_vault.type = 'cash' THEN
    v_coa_vault := '1110';
  ELSIF v_vault.type = 'bank' THEN
    v_coa_vault := '1120';
  ELSIF v_vault.type = 'mobile_wallet' THEN
    v_coa_vault := '1130';
  ELSE
    RAISE EXCEPTION 'نوع الخزنة غير معروف المحاسبة: %', v_vault.type;
  END IF;

  -- DR 2310 (رواتب مستحقة الدفع)
  v_journal_lines := v_journal_lines || jsonb_build_object(
    'account_code', '2310',
    'debit', ROUND(p_amount, 2),
    'credit', 0,
    'description', 'سداد رواتب مستحقة - ' || v_period.name
  );

  -- CR 1110/1120/1130 (حساب الخزنة)
  v_journal_lines := v_journal_lines || jsonb_build_object(
    'account_code', v_coa_vault,
    'debit', 0,
    'credit', ROUND(p_amount, 2),
    'description', 'سداد رواتب من الخزنة - ' || v_vault.name
  );

  v_je_id := create_manual_journal_entry(
    'صرف رواتب ' || v_period.name || ' من ' || v_vault.name,
    p_payment_date,
    'hr_payroll_payment',
    v_payment_id,
    v_journal_lines,
    p_user_id
  );

  -- ح) ربط العمليات بالدفعة
  UPDATE hr_payroll_payments
  SET vault_txn_id = v_vault_txn_id,
      journal_entry_id = v_je_id
  WHERE id = v_payment_id;

  -- ط) تحديث حالة المسير إذا تم سداد كامل المبلغ
  v_total_paid := v_total_paid + p_amount;
  IF v_total_paid >= v_total_net_lines - 0.05 THEN
    UPDATE hr_payroll_runs
    SET status = 'paid',
        paid_by = p_user_id,
        paid_at = now(),
        updated_at = now()
    WHERE id = p_run_id;
    
    -- لضمان التوافق مع أي واجهات، نجعل v_run.status للتأكيد
    v_run.status := 'paid';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'payroll_run_id', p_run_id,
    'payment_id', v_payment_id,
    'journal_entry_id', v_je_id,
    'vault_txn_id', v_vault_txn_id,
    'amount', p_amount,
    'total_net', v_total_net_lines,
    'total_paid', v_total_paid,
    'remaining_after_payment', ROUND(v_total_net_lines - v_total_paid, 2),
    'run_status', v_run.status
  );
END; $$;

GRANT EXECUTE ON FUNCTION disburse_payroll_payment(UUID, UUID, NUMERIC, DATE, TEXT, UUID) TO authenticated;
