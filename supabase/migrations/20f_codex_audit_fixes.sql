-- ============================================================
-- Migration 20f: Codex Audit Fixes (v3 — إغلاق نهائي بعد 3 جولات مراجعة)
-- إصلاحات مراجعة الأمان — مؤكدة من مراجعة ثلاثية داخلية
--
--   P0-1: Guard trigger يمنع approved بدون vault_transaction فعلية
--   P0-2: إصلاح رصيد الإجازات عند رفض pending_hr
--   P0-3: RPC الصرف يفحص finance.payments.create (ليس hr.advances.approve فقط)
--   P1-1: Audit trail مدمج في handle_leave_approval (لحل مشكلة ترتيب Triggers)
--   P1-2: Audit trail تلقائي للسلف
--
-- Idempotent: آمن للتشغيل أكثر من مرة
-- ============================================================


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  P0-1: Guard Trigger — حماية مسار السلف (v2)             ║
-- ║                                                           ║
-- ║  v1 كان يكتفي بفحص vault_id IS NOT NULL — غير كافٍ      ║
-- ║  v2 يتحقق من وجود vault_transaction فعلية بـ             ║
-- ║  reference_type = 'hr_advance' في نفس الـ transaction     ║
-- ║                                                           ║
-- ║  disburse_employee_advance تُنشئ vault_transaction أولاً  ║
-- ║  ثم تُحدّث hr_advances → approved. لذا عندما يعمل هذا   ║
-- ║  الـ trigger، vault_transaction ستكون مرئية               ║
-- ╚═══════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION guard_advance_finance_crossing()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- فقط عند الانتقال إلى approved
  IF NEW.status = 'approved' AND OLD.status <> 'approved' THEN

    -- 1. يجب أن تأتي من pending_finance
    IF OLD.status <> 'pending_finance' THEN
      RAISE EXCEPTION 'لا يمكن اعتماد السلفة إلا من حالة pending_finance (الحالة الحالية: %)', OLD.status;
    END IF;

    -- 2. يجب أن تكون الحقول المالية مملوءة
    IF NEW.vault_id IS NULL OR NEW.finance_user_id IS NULL OR NEW.finance_action_at IS NULL THEN
      RAISE EXCEPTION 'يجب صرف السلفة عبر disburse_employee_advance() — الحقول المالية ناقصة';
    END IF;

    -- 3. [v3-FINAL] فحص صلاحيات مزدوج على المستخدم الحالي
    -- sales_rep يملك finance.payments.create (للتحصيل) لكن ليس hr.advances.approve
    -- لذا نفحص الاثنين معاً
    IF NOT check_permission(auth.uid(), 'finance.payments.create') THEN
      RAISE EXCEPTION 'صلاحية مرفوضة: finance.payments.create مطلوب لصرف السلف';
    END IF;

    IF NOT check_permission(auth.uid(), 'hr.advances.approve') THEN
      RAISE EXCEPTION 'صلاحية مرفوضة: hr.advances.approve مطلوب لصرف السلف';
    END IF;

    -- 4. [v2] يجب أن توجد حركة خزنة فعلية لهذه السلفة
    IF NOT EXISTS (
      SELECT 1 FROM vault_transactions
      WHERE reference_type = 'hr_advance'
        AND reference_id = NEW.id
    ) THEN
      RAISE EXCEPTION 'لا توجد حركة خزنة لهذه السلفة — الاعتماد يتم فقط عبر disburse_employee_advance()';
    END IF;

    -- 5. [v3] يجب أن يوجد قيد محاسبي لهذه السلفة
    -- يمنع الالتفاف عبر إنشاء vault_transaction ثم UPDATE بدون journal entry
    IF NOT EXISTS (
      SELECT 1 FROM journal_entries
      WHERE source_type = 'hr_advance'
        AND source_id = NEW.id
    ) THEN
      RAISE EXCEPTION 'لا يوجد قيد محاسبي لهذه السلفة — الاعتماد يتم فقط عبر disburse_employee_advance()';
    END IF;

  END IF;

  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_guard_advance_finance ON hr_advances;
CREATE TRIGGER trg_guard_advance_finance
  BEFORE UPDATE ON hr_advances
  FOR EACH ROW EXECUTE FUNCTION guard_advance_finance_crossing();


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  P0-2: إصلاح رصيد الإجازات عند رفض pending_hr           ║
-- ║  + P1-1: دمج Audit Trail في handle_leave_approval        ║
-- ║                                                           ║
-- ║  لماذا الدمج؟ trigger منفصل للـ audit كان يعمل بعد      ║
-- ║  تحويل الحالة (approved_supervisor → approved)           ║
-- ║  وبالتالي لا يرى الحالة الأصلية ←  لا يملأ audit       ║
-- ║                                                           ║
-- ║  الحل: نملأ audit fields أولاً ← ثم نحوّل الحالة        ║
-- ╚═══════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION handle_leave_approval()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_approval_levels INTEGER;
BEGIN
  -- جلب عدد مستويات الاعتماد لهذا النوع
  SELECT approval_levels INTO v_approval_levels
  FROM hr_leave_types WHERE id = NEW.leave_type_id;

  -- ══════════════════════════════════════════════════════════
  -- [P1-1] ملء حقول Audit قبل تحويل الحالة
  -- (يعمل على الحالة الأصلية قبل أي transformation)
  -- ══════════════════════════════════════════════════════════

  -- المشرف وافق (approved_supervisor من pending_supervisor)
  IF NEW.status = 'approved_supervisor' AND OLD.status = 'pending_supervisor' THEN
    NEW.supervisor_action_at := COALESCE(NEW.supervisor_action_at, now());
  END IF;

  -- HR وافق (approved من pending_hr)
  IF NEW.status = 'approved' AND OLD.status = 'pending_hr' THEN
    NEW.hr_action_at := COALESCE(NEW.hr_action_at, now());
  END IF;

  -- رفض من أي مرحلة
  IF NEW.status = 'rejected' AND OLD.status <> 'rejected' THEN
    NEW.rejected_at := COALESCE(NEW.rejected_at, now());
    IF NEW.rejected_by IS NULL THEN
      SELECT id INTO NEW.rejected_by
      FROM hr_employees WHERE user_id = auth.uid() LIMIT 1;
    END IF;
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- تحويل الحالات (State Machine)
  -- ══════════════════════════════════════════════════════════

  -- المشرف وافق + النوع يحتاج مستوى واحد فقط → اعتماد نهائي
  IF NEW.status = 'approved_supervisor' AND v_approval_levels = 1 THEN
    NEW.status := 'approved';
    -- [P1-1] في حالة المستوى الواحد: supervisor_action_at مملوء أعلاه
  END IF;

  -- المشرف وافق + النوع يحتاج مستويين → ينتقل لـ HR
  IF NEW.status = 'approved_supervisor' AND v_approval_levels = 2 THEN
    NEW.status := 'pending_hr';
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- عمليات الرصيد
  -- ══════════════════════════════════════════════════════════

  -- عند الاعتماد النهائي → خصم من الرصيد
  IF NEW.status = 'approved' AND OLD.status <> 'approved' THEN
    UPDATE hr_leave_balances
    SET
      used_days    = used_days + NEW.days_count,
      pending_days = GREATEST(0, pending_days - NEW.days_count),
      updated_at   = now()
    WHERE employee_id  = NEW.employee_id
      AND leave_type_id = NEW.leave_type_id
      AND year          = EXTRACT(YEAR FROM NEW.start_date)::INTEGER;
  END IF;

  -- [CODEX FIX] عند الإلغاء أو الرفض → إعادة الأيام المعلقة
  -- الشرط القديم: OLD.status = 'pending_supervisor' فقط
  -- الإصلاح: يشمل كل الحالات التي فيها pending_days محجوزة
  IF NEW.status IN ('rejected', 'cancelled')
     AND OLD.status IN ('pending_supervisor', 'approved_supervisor', 'pending_hr')
  THEN
    UPDATE hr_leave_balances
    SET
      pending_days = GREATEST(0, pending_days - NEW.days_count),
      updated_at   = now()
    WHERE employee_id  = NEW.employee_id
      AND leave_type_id = NEW.leave_type_id
      AND year          = EXTRACT(YEAR FROM NEW.start_date)::INTEGER;
  END IF;

  RETURN NEW;
END; $$;

-- إزالة Trigger الـ audit المنفصل (تم دمج منطقه أعلاه)
DROP TRIGGER IF EXISTS trg_leave_audit_fields ON hr_leave_requests;
DROP FUNCTION IF EXISTS auto_fill_leave_audit_fields();


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  P0-3: إصلاح RPC الصرف — فحص finance.payments.create    ║
-- ║                                                           ║
-- ║  المشكلة: الـ RPC يفحص hr.advances.approve فقط          ║
-- ║  وهذه الصلاحية ممنوحة لـ branch_manager و               ║
-- ║  sales_supervisor — وهؤلاء ليسوا ماليين!                ║
-- ║                                                           ║
-- ║  الحل: فحص finance.payments.create (ممنوحة للمحاسب فقط) ║
-- ║  مع الاحتفاظ بفحص hr.advances.approve كشرط ثانٍ         ║
-- ╚═══════════════════════════════════════════════════════════╝

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
  -- ══════════════════════════════════════════════════════
  -- 0. [v3-FINAL] Anti-spoofing: فرض أن المنفّذ = المستخدم المصادق
  -- يمنع تمرير UUID لمستخدم آخر أعلى صلاحية
  -- ══════════════════════════════════════════════════════
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

  -- ③ تحديث السلفة → approved (يُفعِّل trigger توليد الأقساط + guard trigger)
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


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  P1-2: Audit Trail تلقائي — سلف                          ║
-- ╚═══════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION auto_fill_advance_audit_fields()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- المشرف وافق → pending_hr
  IF NEW.status = 'pending_hr'
     AND OLD.status = 'pending_supervisor'
  THEN
    NEW.supervisor_action_at := COALESCE(NEW.supervisor_action_at, now());
    IF NEW.supervisor_id IS NULL THEN
      SELECT id INTO NEW.supervisor_id
      FROM hr_employees WHERE user_id = auth.uid() LIMIT 1;
    END IF;
  END IF;

  -- HR وافق → pending_finance
  IF NEW.status = 'pending_finance'
     AND OLD.status = 'pending_hr'
  THEN
    NEW.hr_action_at := COALESCE(NEW.hr_action_at, now());
    IF NEW.hr_manager_id IS NULL THEN
      SELECT id INTO NEW.hr_manager_id
      FROM hr_employees WHERE user_id = auth.uid() LIMIT 1;
    END IF;
  END IF;

  -- رفض من أي مرحلة
  IF NEW.status = 'rejected' AND OLD.status <> 'rejected' THEN
    IF NEW.rejected_by IS NULL THEN
      SELECT id INTO NEW.rejected_by
      FROM hr_employees WHERE user_id = auth.uid() LIMIT 1;
    END IF;
  END IF;

  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_advance_audit_fields ON hr_advances;
CREATE TRIGGER trg_advance_audit_fields
  BEFORE UPDATE ON hr_advances
  FOR EACH ROW EXECUTE FUNCTION auto_fill_advance_audit_fields();

-- ╔═══════════════════════════════════════════════════════════╗
-- ║  P0-4: DB-Level State Machine — حماية الانتقالات         ║
-- ║                                                           ║
-- ║  المشكلة: RLS تسمح لأي صاحب hr.advances.approve          ║
-- ║  بتغيير الحالة لأي قيمة (approved→rejected مثلاً)        ║
-- ║  والأقساط تبقى pending → تُخصم من الرواتب بالخطأ         ║
-- ║                                                           ║
-- ║  الحل:                                                    ║
-- ║  1. Trigger يفحص الانتقالات المسموحة فقط                  ║
-- ║  2. عند cancelled/rejected بعد approved → إلغاء الأقساط  ║
-- ╚═══════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION enforce_advance_state_machine()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_allowed TEXT[];
BEGIN
  -- لا شيء إذا لم تتغير الحالة
  IF NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;

  -- تعريف الانتقالات المسموحة
  -- ملاحظة:
  --   approved → cancelled ممنوع (المال صُرف فعلاً)
  --   approved → fully_repaid يتم تلقائياً عبر handle_installment_deducted trigger
  --   approved → paid غير مستخدم حالياً ولكن محجوز لسداد مبكر مستقبلي
  v_allowed := CASE OLD.status::TEXT
    WHEN 'pending_supervisor' THEN ARRAY['pending_hr', 'rejected', 'cancelled']
    WHEN 'pending_hr'         THEN ARRAY['pending_finance', 'rejected', 'cancelled']
    WHEN 'pending_finance'    THEN ARRAY['approved', 'rejected']
    WHEN 'approved'           THEN ARRAY['fully_repaid']  -- تلقائي عبر trigger الأقساط فقط
    WHEN 'paid'               THEN ARRAY['fully_repaid']  -- fallback لبيانات قديمة
    ELSE ARRAY[]::TEXT[]  -- rejected, cancelled, fully_repaid = حالات نهائية
  END;

  IF NOT (NEW.status::TEXT = ANY(v_allowed)) THEN
    RAISE EXCEPTION 'انتقال غير مسموح: % → % (المسموح: %)',
      OLD.status, NEW.status, array_to_string(v_allowed, ', ');
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- عند رفض سلفة قبل الصرف → إلغاء الأقساط المعلقة (إن وُجدت)
  -- بعد approved يتم الانتقال فقط إلى paid → لا حاجة لتنظيف
  -- ══════════════════════════════════════════════════════════
  IF NEW.status = 'rejected'
     AND OLD.status IN ('pending_supervisor', 'pending_hr', 'pending_finance')
  THEN
    -- لا أقساط مُنشأة في هذه المرحلة، لكن احتراز أمني
    UPDATE hr_advance_installments
    SET status = 'skipped'
    WHERE advance_id = NEW.id
      AND status = 'pending';
  END IF;

  RETURN NEW;
END; $$;

-- يجب أن يعمل قبل guard_advance_finance_crossing
DROP TRIGGER IF EXISTS trg_advance_state_machine ON hr_advances;
CREATE TRIGGER trg_advance_state_machine
  BEFORE UPDATE ON hr_advances
  FOR EACH ROW EXECUTE FUNCTION enforce_advance_state_machine();


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  P2-1: إضافة rejected_at للسلف — audit trail مكتمل     ║
-- ╚═══════════════════════════════════════════════════════════╝

ALTER TABLE hr_advances ADD COLUMN IF NOT EXISTS rejected_at TIMESTAMPTZ;

-- تحديث الـ audit trigger ليملأ rejected_at أيضاً
CREATE OR REPLACE FUNCTION auto_fill_advance_audit_fields()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- المشرف وافق → pending_hr
  IF NEW.status = 'pending_hr'
     AND OLD.status = 'pending_supervisor'
  THEN
    NEW.supervisor_action_at := COALESCE(NEW.supervisor_action_at, now());
    IF NEW.supervisor_id IS NULL THEN
      SELECT id INTO NEW.supervisor_id
      FROM hr_employees WHERE user_id = auth.uid() LIMIT 1;
    END IF;
  END IF;

  -- HR وافق → pending_finance
  IF NEW.status = 'pending_finance'
     AND OLD.status = 'pending_hr'
  THEN
    NEW.hr_action_at := COALESCE(NEW.hr_action_at, now());
    IF NEW.hr_manager_id IS NULL THEN
      SELECT id INTO NEW.hr_manager_id
      FROM hr_employees WHERE user_id = auth.uid() LIMIT 1;
    END IF;
  END IF;

  -- رفض من أي مرحلة
  IF NEW.status = 'rejected' AND OLD.status <> 'rejected' THEN
    NEW.rejected_at := COALESCE(NEW.rejected_at, now());
    IF NEW.rejected_by IS NULL THEN
      SELECT id INTO NEW.rejected_by
      FROM hr_employees WHERE user_id = auth.uid() LIMIT 1;
    END IF;
  END IF;

  RETURN NEW;
END; $$;


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  P0-5: حماية الحقول الحساسة من التعديل المباشر          ║
-- ║                                                           ║
-- ║  المشكلة: RLS تسمح لأي صاحب hr.advances.approve          ║
-- ║  بتعديل أي حقل (amount, paid_amount, vault_id...)        ║
-- ║  بدون تغيير status → state machine لا يتدخل             ║
-- ║                                                           ║
-- ║  الحل: trigger يحمي الحقول المالية من التعديل المباشر    ║
-- ║  عبر API (current_user = 'authenticated')                 ║
-- ║  لكن يسمح لـ SECURITY DEFINER RPCs/triggers              ║
-- ╚═══════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION guard_advance_immutable_fields()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- فقط للاستدعاءات المباشرة من العميل
  -- SECURITY DEFINER RPCs (disburse, installment trigger) تعمل كـ postgres
  IF current_user = 'authenticated' THEN

    -- ═══ paid_amount: لا يُعدَّل مباشرة أبداً (فقط عبر trigger الأقساط) ═══
    IF NEW.paid_amount IS DISTINCT FROM OLD.paid_amount THEN
      RAISE EXCEPTION 'لا يمكن تعديل المبلغ المسدد مباشرة — يتم تلقائياً عبر خصم الأقساط';
    END IF;

    -- ═══ بعد الصرف: الحقول المالية والجوهرية محمية ═══
    IF OLD.status IN ('approved', 'paid', 'fully_repaid') THEN
      IF NEW.amount IS DISTINCT FROM OLD.amount
         OR NEW.installments_count IS DISTINCT FROM OLD.installments_count
         OR NEW.monthly_installment IS DISTINCT FROM OLD.monthly_installment
         OR NEW.employee_id IS DISTINCT FROM OLD.employee_id
         OR NEW.vault_id IS DISTINCT FROM OLD.vault_id
         OR NEW.finance_user_id IS DISTINCT FROM OLD.finance_user_id
         OR NEW.finance_action_at IS DISTINCT FROM OLD.finance_action_at
      THEN
        RAISE EXCEPTION 'لا يمكن تعديل الحقول المالية بعد صرف السلفة';
      END IF;
    END IF;

  END IF;

  RETURN NEW;
END; $$;

-- يعمل أولاً (قبل كل الـ triggers الأخرى)
DROP TRIGGER IF EXISTS trg_aaa_advance_immutable ON hr_advances;
CREATE TRIGGER trg_aaa_advance_immutable
  BEFORE UPDATE ON hr_advances
  FOR EACH ROW EXECUTE FUNCTION guard_advance_immutable_fields();


-- ════════════════════════════════════════════════════════════
-- تحقق نهائي
-- ════════════════════════════════════════════════════════════
DO $$
BEGIN
  RAISE NOTICE '✅ Migration 20f v4-FINAL: إصلاحات Codex Audit — إغلاق شامل';
  RAISE NOTICE '   P0-1: guard_advance_finance_crossing — vault_txn + journal + auth.uid() ✓';
  RAISE NOTICE '   P0-2: handle_leave_approval — pending_hr + audit مدمج ✓';
  RAISE NOTICE '   P0-3: disburse_employee_advance — anti-spoofing + dual permission ✓';
  RAISE NOTICE '   P0-4: enforce_advance_state_machine — DB state machine ✓';
  RAISE NOTICE '   P0-5: guard_advance_immutable_fields — حماية الحقول المالية ✓';
  RAISE NOTICE '   P1-2: auto_fill_advance_audit_fields — مع rejected_at ✓';
  RAISE NOTICE '   P2-1: rejected_at column added ✓';
END;
$$;
