-- ============================================================
-- 63_cash_custody_self_confirm.sql
-- استثناء التأكيد الذاتي للإيصالات النقدية في العهدة الشخصية
--
-- المشكلة:
--   المندوب ينشئ إيصال نقدي يُحوَّل تلقائياً لعهدته الشخصية.
--   لكن دالة confirm_payment_receipt تتحقق من finance.payments.confirm
--   وهي صلاحية إدارية غير مناسبة لمنحها للمندوبين.
--
-- الحل:
--   إضافة استثناء محدود وآمن داخل فحص الصلاحية فقط:
--   يُسمح للمستخدم بتأكيد الإيصال إذا تحققت جميع الشروط:
--     1. طريقة الدفع = cash
--     2. الإيصال مرتبط بعهدة (custody_id IS NOT NULL)
--     3. العهدة المرتبطة تعود لنفس المستخدم (employee_id = p_user_id)
--     4. العهدة نشطة (is_active = true)
--     5. الإجراء = confirm (لا يُطبَّق على reject)
--
--   ما لم يتغير:
--   ─ توقيع الدالة: مطابق تماماً
--   ─ SECURITY DEFINER / search_path: مطابق
--   ─ DECLARE: مطابق + متغير واحد مضاف (v_is_own_cash_custody)
--   ─ ترتيب العمليات: Security Guard → Permission Check → Lock Row → ...
--     (الترتيب الأصلي محفوظ بالكامل)
--   ─ كل منطق: التحقق من الوجهة، تحديد الحساب، حركات الخزنة/العهدة،
--     القيد المحاسبي، التوزيع الذكي، تحديث الإيصال، منطق الرفض:
--     مطابق حرفياً للنسخة الأصلية في 08_payment_receipts_refactor.sql
--
--   الإضافة الوحيدة:
--   ─ v_is_own_cash_custody: يُحسب داخل فحص الصلاحية قبل check_permission
--   ─ في مسار reject: حماية إضافية تمنع الرفض الذاتي
-- ============================================================

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


-- ────────────────────────────────────────────────────────────
-- صلاحيات التنفيذ
-- ────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION confirm_payment_receipt(UUID, TEXT, UUID, TEXT, UUID) TO authenticated;
