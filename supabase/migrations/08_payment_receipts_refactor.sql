-- ============================================================
-- 08_payment_receipts_refactor.sql
-- إصلاح نظام إيصالات التحصيل المنفصلة
--
-- الإصلاحات:
--   R1: توحيد enum طرق الدفع ('check' → 'cheque')
--   R2: إضافة حساب أوراق القبض 1210
--   R3: تطوير allocate_payment_to_invoices — targeted allocation
--   R4: إعادة كتابة confirm_payment_receipt — allocate + توجيه محاسبي دقيق
-- ============================================================


-- ╔══════════════════════════════════════════════════════════════╗
-- ║  R1: توحيد Enum طرق الدفع                                  ║
-- ║  DB كانت: 'cash','bank_transfer','instapay','check',        ║
-- ║            'mobile_wallet'                                   ║
-- ║  الهدف:   'cash','bank_transfer','instapay','cheque',       ║
-- ║            'mobile_wallet'                                   ║
-- ╚══════════════════════════════════════════════════════════════╝

-- ١. ترقية البيانات الحالية (أولاً لتفادي الخرق)
UPDATE payment_receipts
  SET payment_method = 'cheque'
  WHERE payment_method = 'check';

-- ٢. إسقاط القيد القديم وتعريف قيد جديد
ALTER TABLE payment_receipts
  DROP CONSTRAINT IF EXISTS payment_receipts_payment_method_check;

ALTER TABLE payment_receipts
  ADD CONSTRAINT payment_receipts_payment_method_check
  CHECK (payment_method IN (
    'cash', 'bank_transfer', 'instapay', 'cheque', 'mobile_wallet'
  ));

-- ٣. تحديث الحقل في sales_orders (payment_method type)
-- payment_method في sales_orders عبارة عن custom type — لا يتأثر بهذا التعديل


-- ╔══════════════════════════════════════════════════════════════╗
-- ║  R2: إضافة حساب أوراق القبض (1210)                         ║
-- ║  الاستخدام: الشيكات المستلمة حتى تاريخ استحقاقها           ║
-- ║  DR: 1210 → CR: 1200 عند استلام الشيك                      ║
-- ║  DR: 1120 → CR: 1210 عند تحصيل الشيك (مرحلة مستقبلية)    ║
-- ╚══════════════════════════════════════════════════════════════╝

INSERT INTO chart_of_accounts (code, name, name_en, type, sort_order)
VALUES ('1210', 'أوراق قبض — شيكات معلقة', 'Notes Receivable (Cheques Pending)', 'asset', 7)
ON CONFLICT (code) DO NOTHING;

-- ربط بالحساب الأب 1200
UPDATE chart_of_accounts
  SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '1200')
  WHERE code = '1210' AND parent_id IS NULL;


-- ╔══════════════════════════════════════════════════════════════╗
-- ║  R3: تطوير allocate_payment_to_invoices                     ║
-- ║  الإضافة: p_target_order_id UUID DEFAULT NULL               ║
-- ║  المنطق:  إذا تم تمريره → الطلب المحدد يأخذ الأولوية أولاً║
-- ║            ثم FIFO على باقي الفواتير                        ║
-- ╚══════════════════════════════════════════════════════════════╝

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


-- ╔══════════════════════════════════════════════════════════════╗
-- ║  R4: إعادة كتابة confirm_payment_receipt                    ║
-- ║  التغييرات:                                                 ║
-- ║  1. إزالة INSERT اليدوي في customer_ledger                  ║
-- ║  2. استدعاء allocate_payment_to_invoices                    ║
-- ║  3. توجيه القيد المحاسبي حسب طريقة الدفع:                  ║
-- ║     cash (custody)  → DR:1400 CR:1200                       ║
-- ║     cash (vault)    → DR:1110/1120/1130 CR:1200             ║
-- ║     bank_transfer   → DR:1120 CR:1200                       ║
-- ║     instapay        → DR:1130 CR:1200                       ║
-- ║     mobile_wallet   → DR:1130 CR:1200                       ║
-- ║     cheque          → DR:1210 CR:1200 (أوراق قبض)           ║
-- ║  4. vault_transactions للتحويلات البنكية/المحافظ            ║
-- ╚══════════════════════════════════════════════════════════════╝

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
BEGIN
  -- [SECURITY GUARD]
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

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
GRANT EXECUTE ON FUNCTION allocate_payment_to_invoices(UUID, NUMERIC, TEXT, UUID, UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION confirm_payment_receipt(UUID, TEXT, UUID, TEXT, UUID) TO authenticated;
