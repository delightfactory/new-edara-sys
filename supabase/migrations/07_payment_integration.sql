-- ============================================================
-- 07_payment_integration.sql
-- ربط نظام المبيعات بإيصالات الدفع
-- 
-- الإصلاحات:
--   G1: التسليم النقدي ينشئ إيصال confirmed تلقائياً
--   G2: تأكيد الإيصال يُحدِّث paid_amount في sales_orders
--   G3: إضافة sales_order_id لجدول payment_receipts
-- ============================================================


-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ١. إضافة عمود sales_order_id لجدول payment_receipts       ║
-- ╚══════════════════════════════════════════════════════════════╝

ALTER TABLE payment_receipts
  ADD COLUMN IF NOT EXISTS sales_order_id UUID REFERENCES sales_orders(id);

CREATE INDEX IF NOT EXISTS idx_pr_sales_order
  ON payment_receipts(sales_order_id) WHERE sales_order_id IS NOT NULL;


-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ٢. إعادة تعريف deliver_sales_order                        ║
-- ║     المصدر الأصلي: 04_sales_system.sql:L688-L964           ║
-- ║     التعديل: إضافة INSERT INTO payment_receipts بعد ٤أ     ║
-- ╚══════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION deliver_sales_order(
  p_order_id       UUID,
  p_user_id        UUID,
  p_payment_terms  TEXT,          -- 'cash' | 'credit' | 'mixed'
  p_payment_method TEXT DEFAULT NULL,  -- 'cash' | 'bank_transfer' | 'instapay' etc.
  p_vault_id       UUID DEFAULT NULL,
  p_custody_id     UUID DEFAULT NULL,
  p_cash_amount    NUMERIC DEFAULT 0,
  p_override_credit BOOLEAN DEFAULT false
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
  v_journal_lines JSONB := '[]'::JSONB;
BEGIN
  -- [SECURITY GUARD]
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- [PERMISSION]
  IF NOT check_permission(p_user_id, 'sales.orders.deliver') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية تسليم طلبات البيع';
  END IF;

  -- ١. قفل الطلب
  SELECT * INTO v_order
  FROM sales_orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'أمر البيع غير موجود';
  END IF;

  -- تكرار آمن
  IF v_order.status = 'delivered' OR v_order.status = 'completed' THEN
    RETURN;
  END IF;

  IF v_order.status != 'confirmed' THEN
    RAISE EXCEPTION 'لا يمكن تسليم طلب في حالة: % — يجب أن يكون مؤكداً', v_order.status;
  END IF;

  -- ٢. حساب المبلغ الآجل + فحص الائتمان
  v_credit_amount := v_order.total_amount - p_cash_amount;

  IF p_payment_terms = 'cash' THEN
    v_credit_amount := 0;
    p_cash_amount := v_order.total_amount;
  ELSIF p_payment_terms = 'credit' THEN
    v_credit_amount := v_order.total_amount;
    p_cash_amount := 0;
  END IF;
  -- 'mixed' → يستخدم القيم المُرسلة

  -- [GAP FIX] فحص: مجموع النقدي + الآجل يجب أن يساوي الإجمالي
  IF (p_cash_amount + v_credit_amount) != v_order.total_amount THEN
    RAISE EXCEPTION 'المبلغ النقدي (%) + الآجل (%) لا يساوي إجمالي الفاتورة (%)',
      p_cash_amount, v_credit_amount, v_order.total_amount;
  END IF;

  -- فحص الائتمان إذا هناك مبلغ آجل
  IF v_credit_amount > 0 THEN
    -- فحص: هل العميل مسموح له بالآجل؟
    DECLARE
      v_customer_terms TEXT;
    BEGIN
      SELECT payment_terms INTO v_customer_terms
      FROM customers WHERE id = v_order.customer_id;

      IF v_customer_terms = 'cash' THEN
        RAISE EXCEPTION 'هذا العميل مسموح له بالدفع النقدي فقط';
      END IF;
    END;

    -- فحص الحد الائتماني
    v_credit_ok := check_credit_available(v_order.customer_id, v_credit_amount);

    IF NOT v_credit_ok THEN
      IF p_override_credit AND check_permission(p_user_id, 'sales.orders.override_credit') THEN
        -- تخطي مسموح بصلاحية
        NULL;
      ELSE
        RAISE EXCEPTION 'تجاوز حد الائتمان — المبلغ الآجل: % — يرجى تقليل المبلغ أو الحصول على موافقة', v_credit_amount;
      END IF;
    END IF;
  END IF;

  -- ٣. لكل بند: إلغاء حجز + خصم مخزون + تسجيل التكلفة
  FOR v_item IN
    SELECT * FROM sales_order_items WHERE order_id = p_order_id
    ORDER BY product_id ASC  -- [DEADLOCK FIX]
  LOOP
    -- إلغاء الحجز (تم عند التأكيد)
    PERFORM unreserve_stock(
      v_order.warehouse_id,
      v_item.product_id,
      v_item.base_quantity
    );

    -- خصم فعلي + حساب تكلفة البضاعة المباعة
    v_item_cogs := deduct_stock_at_wac(
      v_order.warehouse_id,
      v_item.product_id,
      v_item.base_quantity,
      'out',               -- نوع الحركة (يتوافق مع CHECK على stock_movements.type)
      'sales_order',       -- نوع المرجع
      p_order_id,          -- معرف المرجع
      p_user_id
    );

    v_total_cogs := v_total_cogs + v_item_cogs;

    -- تسجيل تكلفة الوحدة في البند (للمرتجعات لاحقاً)
    UPDATE sales_order_items
    SET delivered_quantity = base_quantity,
        unit_cost_at_sale = CASE
          WHEN base_quantity > 0 THEN v_item_cogs / base_quantity
          ELSE 0
        END
    WHERE id = v_item.id;
  END LOOP;

  -- ٤. المعالجة المالية
  -- ٤أ. النقدي → عهدة أو خزينة
  IF p_cash_amount > 0 THEN
    -- [GAP FIX] يجب تحديد وجهة التحصيل النقدي
    IF p_custody_id IS NULL AND p_vault_id IS NULL THEN
      RAISE EXCEPTION 'يجب تحديد العهدة أو الخزينة لاستقبال المبلغ النقدي';
    END IF;

    IF p_custody_id IS NOT NULL THEN
      PERFORM add_custody_transaction(
        p_custody_id, 'collection', p_cash_amount,
        p_vault_id,                    -- الخزينة المرجعية (اختياري)
        'sales_order', p_order_id,
        'تحصيل فاتورة بيع #' || v_order.order_number,
        p_user_id
      );
    ELSE
      PERFORM add_vault_transaction(
        p_vault_id, 'collection', p_cash_amount,
        'sales_order', p_order_id,
        'تحصيل فاتورة بيع #' || v_order.order_number,
        p_user_id
      );
    END IF;

    -- ═══════════════════════════════════════════════════════════
    -- [NEW — G1 FIX] إنشاء إيصال تحصيل تلقائي (confirmed)
    -- لأن النقد مُستلَم فعلياً في هذه اللحظة
    -- ═══════════════════════════════════════════════════════════
    INSERT INTO payment_receipts (
      customer_id, amount, payment_method, status,
      sales_order_id, custody_id, vault_id,
      collected_by, reviewed_by, reviewed_at, created_by,
      notes
    ) VALUES (
      v_order.customer_id, p_cash_amount,
      COALESCE(p_payment_method, 'cash'), 'confirmed',
      p_order_id, p_custody_id, p_vault_id,
      p_user_id, p_user_id, now(), p_user_id,
      'تحصيل تلقائي — فاتورة #' || v_order.order_number
    );
  END IF;

  -- ٤ب. الآجل → دفتر العميل (مدين)
  IF v_credit_amount > 0 THEN
    INSERT INTO customer_ledger (
      customer_id, type, amount,
      source_type, source_id,
      description, created_by
    ) VALUES (
      v_order.customer_id, 'debit', v_credit_amount,
      'sales_order', p_order_id,
      'فاتورة بيع #' || v_order.order_number,
      p_user_id
    );
  END IF;

  -- ٥. القيد المحاسبي
  --   مدين: العملاء (المبلغ الآجل) + النقدية (المبلغ النقدي)
  --   دائن: الإيرادات (إجمالي البيع) — مبسّط
  --   مدين: تكلفة البضاعة المباعة
  --   دائن: المخزون (تكلفة البضاعة)
  v_journal_lines := '[]'::JSONB;

  -- سطر الإيرادات (دائن) — بالصافي (بعد الخصم، بدون الضريبة)
  v_journal_lines := v_journal_lines || jsonb_build_object(
    'account_code', '4100', 'debit', 0,
    'credit', v_order.total_amount - COALESCE(v_order.tax_amount, 0),
    'description', 'إيراد بيع #' || v_order.order_number
  );

  -- سطر الضريبة (دائن) — التزام ضريبي
  IF COALESCE(v_order.tax_amount, 0) > 0 THEN
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', '2200', 'debit', 0,
      'credit', v_order.tax_amount,
      'description', 'ضريبة قيمة مضافة — بيع #' || v_order.order_number
    );
  END IF;

  -- سطر العملاء — الآجل (مدين)
  IF v_credit_amount > 0 THEN
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', '1200', 'debit', v_credit_amount, 'credit', 0,
      'description', 'ذمم عملاء — بيع آجل #' || v_order.order_number
    );
  END IF;

  -- سطر النقدية (مدين) — توجيه ديناميكي للحساب الصحيح
  IF p_cash_amount > 0 THEN
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
  END IF;

  -- سطر تكلفة البضاعة المباعة (مدين)
  IF v_total_cogs > 0 THEN
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', '5100', 'debit', v_total_cogs, 'credit', 0,
      'description', 'تكلفة بضاعة مباعة #' || v_order.order_number
    );

    -- سطر المخزون (دائن)
    v_journal_lines := v_journal_lines || jsonb_build_object(
      'account_code', '1300', 'debit', 0, 'credit', v_total_cogs,
      'description', 'خصم مخزون — بيع #' || v_order.order_number
    );
  END IF;

  PERFORM create_manual_journal_entry(
    'قيد بيع — فاتورة #' || v_order.order_number,
    CURRENT_DATE,
    'sales_order',
    p_order_id,
    v_journal_lines,
    p_user_id
  );

  -- ٦. تحديث الطلب
  UPDATE sales_orders
  SET status           = 'delivered',
      payment_terms    = p_payment_terms,
      payment_method   = CASE
        WHEN p_payment_method IS NOT NULL THEN p_payment_method::payment_method
        ELSE NULL
      END,
      vault_id         = p_vault_id,
      custody_id       = p_custody_id,
      cash_amount      = COALESCE(cash_amount, 0) + p_cash_amount,
      credit_amount    = v_credit_amount,
      paid_amount      = COALESCE(paid_amount, 0) + p_cash_amount,
      credit_check_passed = v_credit_ok,
      credit_override  = p_override_credit,
      credit_override_by = CASE WHEN p_override_credit THEN p_user_id ELSE NULL END,
      delivered_by     = p_user_id,
      delivered_at     = now(),
      due_date         = CASE
        WHEN p_payment_terms = 'cash' THEN NULL
        ELSE CURRENT_DATE + COALESCE(
          (SELECT credit_days FROM customers WHERE id = v_order.customer_id), 0
        )
      END
  WHERE id = p_order_id;

  -- ٧. التحقق من اكتمال الفاتورة بناءً على التراكمي
  IF (COALESCE(v_order.paid_amount, 0) + p_cash_amount + COALESCE(v_order.returned_amount, 0)) >= v_order.total_amount THEN
    UPDATE sales_orders
    SET status = 'completed'
    WHERE id = p_order_id;
  END IF;
END; $$;


-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ٣. إعادة تعريف confirm_payment_receipt                    ║
-- ║     المصدر الأصلي: 03j_auth_guard.sql:L1162-L1293          ║
-- ║     التعديل: إضافة UPDATE sales_orders قبل ELSIF reject    ║
-- ╚══════════════════════════════════════════════════════════════╝

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
  -- [SECURITY GUARD] Verify user identity to prevent spoofing
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

    -- ═══════════════════════════════════════════════════════════
    -- [NEW — G2 FIX] ربط الإيصال بالطلب: تحديث paid_amount
    -- ═══════════════════════════════════════════════════════════
    IF v_receipt.sales_order_id IS NOT NULL THEN
      UPDATE sales_orders
      SET paid_amount = COALESCE(paid_amount, 0) + v_receipt.amount
      WHERE id = v_receipt.sales_order_id;

      -- تحقق من اكتمال السداد → تحويل لمكتمل تلقائياً
      UPDATE sales_orders
      SET status = 'completed'
      WHERE id = v_receipt.sales_order_id
        AND status = 'delivered'
        AND COALESCE(paid_amount, 0) >= total_amount;
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
