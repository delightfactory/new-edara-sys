-- ============================================================
-- Migration 19c: disburse_employee_advance (Atomic Finance Sync)
-- دالة ذرية لصرف السلفة تجمع في Transaction واحد:
--   1. التحقق من الحالة (pending_finance)
--   2. سحب المبلغ من الخزنة عبر add_vault_transaction
--   3. إنشاء قيد يومية متوازن (Dr: 2320 / Cr: الخزنة)
--   4. تحديث hr_advances → approved (يفعّل trigger توليد الأقساط)
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- COA المرجعية (من 03_financial_infrastructure.sql):
--   1110 = صندوق نقدي
--   1120 = بنك
--   1130 = محفظة إلكترونية
--   2320 = سلف الموظفين (الأصل: مطلوب من الموظفين — Debit)
--        عند صرف السلفة:
--          Dr 2320 (سلف الموظفين — حق الشركة على الموظف يرتفع)
--          Cr 1110/1120/1130 (النقدية تخرج من الخزنة)
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION disburse_employee_advance(
  p_advance_id      UUID,
  p_vault_id        UUID,
  p_finance_user_id UUID,
  p_notes           TEXT DEFAULT NULL
) RETURNS JSONB
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_advance       hr_advances%ROWTYPE;
  v_vault         vaults%ROWTYPE;
  v_emp           hr_employees%ROWTYPE;
  v_coa_advances  UUID;     -- 2320 سلف الموظفين
  v_coa_vault     TEXT;     -- كود حساب الخزنة (يُحدَّد حسب نوعها)
  v_je_id         UUID;
  v_txn_id        UUID;
  v_description   TEXT;
BEGIN

  -- ══════════════════════════════════════════════════════
  -- 0. فحص الصلاحية
  -- ══════════════════════════════════════════════════════
  IF NOT check_permission(p_finance_user_id, 'hr.advances.approve') THEN
    RAISE EXCEPTION 'لا تملك صلاحية صرف السلف — مطلوب: hr.advances.approve';
  END IF;

  -- ══════════════════════════════════════════════════════
  -- 1. قفل السلفة وفحص حالتها
  -- ══════════════════════════════════════════════════════
  SELECT * INTO v_advance
  FROM hr_advances
  WHERE id = p_advance_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'السلفة غير موجودة (id: %)', p_advance_id;
  END IF;

  IF v_advance.status <> 'pending_finance' THEN
    RAISE EXCEPTION
      'لا يمكن صرف السلفة — الحالة الحالية: % (المطلوب: pending_finance)',
      v_advance.status;
  END IF;

  -- ══════════════════════════════════════════════════════
  -- 2. جلب بيانات الخزنة والموظف
  -- ══════════════════════════════════════════════════════
  SELECT * INTO v_vault FROM vaults WHERE id = p_vault_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الخزنة غير موجودة (id: %)', p_vault_id;
  END IF;

  IF NOT v_vault.is_active THEN
    RAISE EXCEPTION 'الخزنة محددة غير نشطة: %', v_vault.name;
  END IF;

  SELECT * INTO v_emp FROM hr_employees WHERE id = v_advance.employee_id;

  -- ══════════════════════════════════════════════════════
  -- 3. تحديد حساب الخزنة المحاسبي بناءً على نوعها
  -- ══════════════════════════════════════════════════════
  v_coa_vault := CASE v_vault.type
    WHEN 'cash'          THEN '1110'   -- صندوق
    WHEN 'bank'          THEN '1120'   -- بنك
    WHEN 'mobile_wallet' THEN '1130'   -- محفظة إلكترونية
    ELSE                      '1110'   -- fallback: صندوق
  END;

  -- جلب معرّف حساب سلف الموظفين
  SELECT id INTO v_coa_advances
  FROM chart_of_accounts
  WHERE code = '2320';

  IF v_coa_advances IS NULL THEN
    RAISE EXCEPTION 'الحساب 2320 (سلف الموظفين) غير موجود في شجرة الحسابات';
  END IF;

  -- ══════════════════════════════════════════════════════
  -- 4. وصف العملية
  -- ══════════════════════════════════════════════════════
  v_description := format(
    'صرف سلفة — %s — %s — %s',
    COALESCE(v_advance.number, v_advance.id::text),
    COALESCE(v_emp.full_name, 'موظف'),
    COALESCE(p_notes, '')
  );

  -- ══════════════════════════════════════════════════════
  -- 5. سحب المبلغ من الخزنة (يفحص الرصيد ويقفل الصف)
  --    نوع الحركة: 'withdrawal' → يخصم ويفحص الرصيد الكافي
  -- ══════════════════════════════════════════════════════
  SELECT add_vault_transaction(
    p_vault_id,
    'withdrawal',            -- سحب = تخفيض رصيد الخزنة
    v_advance.amount,
    'hr_advance',            -- reference_type
    p_advance_id,            -- reference_id
    v_description,
    p_finance_user_id
  ) INTO v_txn_id;

  -- ══════════════════════════════════════════════════════
  -- 6. إنشاء قيد يومية محاسبي متوازن
  --    Dr: 2320 (سلف الموظفين — التزام الموظف يرتفع)
  --    Cr: 1110/1120/1130 (النقدية تخرج)
  -- ══════════════════════════════════════════════════════

  -- 6a. إنشاء رأس القيد
  INSERT INTO journal_entries (
    source_type, source_id,
    description, entry_date,
    is_auto, status,
    total_debit, total_credit,
    created_by
  ) VALUES (
    'manual',        -- source_type — سنستخدم 'manual' لأن advance ليس ضمن القائمة المقيدة
    p_advance_id,
    v_description,
    CURRENT_DATE,
    true,            -- تلقائي
    'posted',
    v_advance.amount,
    v_advance.amount,
    p_finance_user_id
  ) RETURNING id INTO v_je_id;

  -- 6b. سطر مدين: سلف الموظفين Dr 2320
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
  VALUES (
    v_je_id,
    v_coa_advances,
    v_advance.amount,
    0,
    'سلفة للموظف: ' || COALESCE(v_emp.full_name, '')
  );

  -- 6c. سطر دائن: حساب الخزنة Cr 1110/1120/1130
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
  SELECT
    v_je_id,
    coa.id,
    0,
    v_advance.amount,
    'صرف من خزنة: ' || v_vault.name
  FROM chart_of_accounts coa
  WHERE coa.code = v_coa_vault;

  -- التحقق من إنشاء السطر الدائن (الحساب موجود)
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الحساب % غير موجود في شجرة الحسابات', v_coa_vault;
  END IF;

  -- ══════════════════════════════════════════════════════
  -- 7. تحديث السلفة → approved
  --    (هذا يُفعِّل trigger handle_advance_approval الذي يُولِّد الأقساط)
  -- ══════════════════════════════════════════════════════
  UPDATE hr_advances
  SET
    status            = 'approved',
    vault_id          = p_vault_id,
    finance_user_id   = p_finance_user_id,
    finance_action_at = now(),
    finance_notes     = p_notes,
    updated_at        = now()
  WHERE id = p_advance_id;

  -- ══════════════════════════════════════════════════════
  -- 8. إرجاع ملخص العملية
  -- ══════════════════════════════════════════════════════
  RETURN jsonb_build_object(
    'success',          true,
    'advance_id',       p_advance_id,
    'journal_entry_id', v_je_id,
    'vault_txn_id',     v_txn_id,
    'amount',           v_advance.amount,
    'vault_name',       v_vault.name,
    'employee_name',    COALESCE(v_emp.full_name, ''),
    'message',          'تم صرف السلفة وخصمها من الخزنة وتسجيل القيد المحاسبي بنجاح'
  );

EXCEPTION
  -- إذا فشل add_vault_transaction (رصيد غير كافٍ) أو أي خطوة أخرى
  -- PostgreSQL يُلغي كل الـ transaction تلقائياً (ROLLBACK)
  WHEN OTHERS THEN
    RAISE; -- إعادة رفع الخطأ كما هو للـ Frontend
END;
$$;

-- ── صلاحيات تشغيل الدالة الجديدة ──
GRANT EXECUTE ON FUNCTION disburse_employee_advance(UUID, UUID, UUID, TEXT) TO authenticated;

-- ── تحديث source_type المسموح به في journal_entries لإضافة السلف ──
-- ملاحظة: إذا كان الـ CHECK constraint يحول دون ذلك، نُضيف hr_advance للقائمة
-- نفحص أولاً هل source_type يحتوي CHECK constraint:
DO $$
BEGIN
  -- محاولة إضافة hr_advance لـ source_type CHECK إن كانت القائمة محدودة
  -- عبر إعادة تعريف الـ constraint
  ALTER TABLE journal_entries DROP CONSTRAINT IF EXISTS journal_entries_source_type_check;
  ALTER TABLE journal_entries ADD CONSTRAINT journal_entries_source_type_check
    CHECK (source_type IN (
      'sales_order', 'sales_return', 'payment', 'purchase_order',
      'purchase_return', 'expense', 'custody', 'transfer', 'manual',
      'hr_advance'     -- ✅ مُضاف
    ));
EXCEPTION
  WHEN OTHERS THEN
    -- إذا لم تكن القيد موجوداً — تجاهل
    NULL;
END;
$$;

-- ── إعادة إنشاء الدالة باستخدام source_type = 'hr_advance' ──
-- (نُعيد INSERTالإنشاء بعد إضافة hr_advance للقائمة)
CREATE OR REPLACE FUNCTION disburse_employee_advance(
  p_advance_id      UUID,
  p_vault_id        UUID,
  p_finance_user_id UUID,
  p_notes           TEXT DEFAULT NULL
) RETURNS JSONB
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_advance       hr_advances%ROWTYPE;
  v_vault         vaults%ROWTYPE;
  v_emp           hr_employees%ROWTYPE;
  v_coa_advances  UUID;
  v_coa_vault     TEXT;
  v_je_id         UUID;
  v_txn_id        UUID;
  v_description   TEXT;
BEGIN
  -- [v3-FINAL] Anti-spoofing: يمنع تمرير UUID لمستخدم آخر
  IF p_finance_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'انتحال هوية مرفوض: p_finance_user_id يجب أن يساوي المستخدم المصادق الحالي';
  END IF;

  IF NOT check_permission(auth.uid(), 'hr.advances.approve') THEN
    RAISE EXCEPTION 'صلاحية مرفوضة: hr.advances.approve مطلوب';
  END IF;

  IF NOT check_permission(auth.uid(), 'finance.payments.create') THEN
    RAISE EXCEPTION 'صلاحية مرفوضة: finance.payments.create مطلوب — فقط المحاسب يصرف السلف';
  END IF;

  SELECT * INTO v_advance FROM hr_advances WHERE id = p_advance_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'السلفة غير موجودة'; END IF;
  IF v_advance.status <> 'pending_finance' THEN
    RAISE EXCEPTION 'الحالة غير صالحة للصرف: % (المطلوب pending_finance)', v_advance.status;
  END IF;

  SELECT * INTO v_vault FROM vaults WHERE id = p_vault_id;
  IF NOT FOUND OR NOT v_vault.is_active THEN
    RAISE EXCEPTION 'الخزنة غير موجودة أو غير نشطة';
  END IF;

  SELECT * INTO v_emp FROM hr_employees WHERE id = v_advance.employee_id;

  v_coa_vault := CASE v_vault.type
    WHEN 'cash'          THEN '1110'
    WHEN 'bank'          THEN '1120'
    WHEN 'mobile_wallet' THEN '1130'
    ELSE '1110'
  END;

  SELECT id INTO v_coa_advances FROM chart_of_accounts WHERE code = '2320';
  IF v_coa_advances IS NULL THEN
    RAISE EXCEPTION 'الحساب 2320 غير موجود في شجرة الحسابات';
  END IF;

  v_description := format(
    'صرف سلفة — %s — %s',
    COALESCE(v_advance.number, v_advance.id::text),
    COALESCE(v_emp.full_name, 'موظف')
  );

  -- ① سحب من الخزنة (يُفشل التعامل إذا الرصيد غير كافٍ)
  SELECT add_vault_transaction(
    p_vault_id, 'withdrawal', v_advance.amount,
    'hr_advance', p_advance_id, v_description, p_finance_user_id
  ) INTO v_txn_id;

  -- ② القيد المحاسبي
  INSERT INTO journal_entries (
    source_type, source_id, description, entry_date,
    is_auto, status, total_debit, total_credit, created_by
  ) VALUES (
    'hr_advance', p_advance_id, v_description, CURRENT_DATE,
    true, 'posted', v_advance.amount, v_advance.amount, p_finance_user_id
  ) RETURNING id INTO v_je_id;

  -- Dr 2320: سلف الموظفين
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
  VALUES (v_je_id, v_coa_advances, v_advance.amount, 0, 'سلفة: ' || COALESCE(v_emp.full_name, ''));

  -- Cr 1110/1120/1130: الخزنة
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
  SELECT v_je_id, coa.id, 0, v_advance.amount, 'من خزنة: ' || v_vault.name
  FROM chart_of_accounts coa WHERE coa.code = v_coa_vault;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الحساب % (الخزنة) غير موجود', v_coa_vault;
  END IF;

  -- ③ تحديث السلفة → approved (يُفعِّل trigger توليد الأقساط)
  UPDATE hr_advances SET
    status            = 'approved',
    vault_id          = p_vault_id,
    finance_user_id   = p_finance_user_id,
    finance_action_at = now(),
    finance_notes     = p_notes,
    updated_at        = now()
  WHERE id = p_advance_id;

  RETURN jsonb_build_object(
    'success',          true,
    'advance_id',       p_advance_id,
    'journal_entry_id', v_je_id,
    'vault_txn_id',     v_txn_id,
    'amount',           v_advance.amount,
    'vault_name',       v_vault.name,
    'employee_name',    COALESCE(v_emp.full_name, ''),
    'message',          'تم الصرف وتسجيل القيد المحاسبي وتوليد جدول الأقساط بنجاح'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION disburse_employee_advance(UUID, UUID, UUID, TEXT) TO authenticated;
