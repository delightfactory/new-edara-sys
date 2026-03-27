-- ============================================================
-- 09_delivery_finance_sync.sql
-- EDARA v2 — دمج التسليم مع المعمارية المالية الجديدة
--
-- يحل مشكلة "Double-Accounting Bomb":
-- الطرق غير النقدية (تحويل/إنستاباي/محفظة) عند التسليم
-- تُعامَل محاسبياً كـ آجل (1200) — لا تلمس البنوك/الخزائن.
-- التأكيد النهائي يتم لاحقاً عبر confirm_payment_receipt (M08).
--
-- منطق المسارين:
--   cash    → DR: استلام نقدي (1400/1110) + إيصال confirmed + paid_amount تُحدَّث
--   else    → DR: ذمم مدينة  (1200)       + إيصال pending  + paid_amount تبقى
-- ============================================================

-- حذف الإصدار القديم (8 params) من M07 — CREATE OR REPLACE لا يستطيع إحلاله لأن
-- الـ signature اختلف (أضفنا 3 params جديدة) فيُنشئ overload بدل الاستبدال
DROP FUNCTION IF EXISTS deliver_sales_order(UUID, UUID, TEXT, TEXT, UUID, UUID, NUMERIC, BOOLEAN);

CREATE OR REPLACE FUNCTION deliver_sales_order(
  p_order_id        UUID,
  p_user_id         UUID,
  p_payment_terms   TEXT,                    -- 'cash' | 'credit' | 'mixed'
  p_payment_method  TEXT    DEFAULT NULL,    -- 'cash' | 'bank_transfer' | 'instapay' | 'mobile_wallet' | 'cheque'
  p_vault_id        UUID    DEFAULT NULL,
  p_custody_id      UUID    DEFAULT NULL,
  p_cash_amount     NUMERIC DEFAULT 0,
  p_override_credit BOOLEAN DEFAULT false,
  p_bank_reference  TEXT    DEFAULT NULL,    -- مرجع التحويل البنكي/إنستاباي
  p_check_number    TEXT    DEFAULT NULL,    -- رقم الشيك
  p_check_date      DATE    DEFAULT NULL     -- تاريخ استحقاق الشيك
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
  -- هل طريقة الدفع نقدية فعلية (تُحتسب فورياً) أم مؤجلة التأكيد؟
  v_is_cash       BOOLEAN;
BEGIN
  -- [SECURITY GUARD]
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- [PERMISSION]
  IF NOT check_permission(p_user_id, 'sales.orders.deliver') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية تسليم طلبات البيع';
  END IF;

  -- النقدي الفعلي = cash فقط (تدخل العهدة أو الخزينة فوراً)
  -- كل الطرق الأخرى (تحويل/إنستاباي/محفظة/شيك) = pending — تنتظر مراجعة المحاسب
  v_is_cash := (COALESCE(p_payment_method, 'cash') = 'cash');

  -- ١. قفل الطلب
  SELECT * INTO v_order FROM sales_orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'أمر البيع غير موجود'; END IF;

  IF v_order.status = 'delivered' OR v_order.status = 'completed' THEN RETURN; END IF;

  IF v_order.status != 'confirmed' THEN
    RAISE EXCEPTION 'لا يمكن تسليم طلب في حالة: % — يجب أن يكون مؤكداً', v_order.status;
  END IF;

  -- ٢. حساب التوزيع (نقدي <-> آجل)
  v_credit_amount := v_order.total_amount - p_cash_amount;

  IF p_payment_terms = 'cash' THEN
    v_credit_amount := 0;
    p_cash_amount   := v_order.total_amount;
  ELSIF p_payment_terms = 'credit' THEN
    v_credit_amount := v_order.total_amount;
    p_cash_amount   := 0;
  END IF;
  -- 'mixed' → يستخدم القيم المُرسَلة

  -- [VALIDATION] مجموع النقدي + الآجل = الإجمالي
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
  -- ٤. المعالجة المالية — المسار مزدوج (نقدي فوري vs مؤجل)
  -- ════════════════════════════════════════════════════════════

  IF p_cash_amount > 0 THEN

    IF v_is_cash THEN
      -- ─────────────────────────────────────────────
      -- مسار النقدي الفوري (cash only)
      -- المبلغ يدخل العهدة أو الخزينة فوراً
      -- ─────────────────────────────────────────────
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

      -- إيصال confirmed تلقائي (المبلغ مُستَلم فعلياً)
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
      -- ─────────────────────────────────────────────
      -- مسار التحويل/الشيك/المحفظة
      -- لا تلمس البنوك أو الخزائن الآن
      -- ينتظر مراجعة المحاسب → يُكمله confirm_payment_receipt (M08)
      -- ─────────────────────────────────────────────

      -- إيصال pending فقط (لا حركة مالية فعلية بعد)
      -- الحقول المرجعية تجعل الإيصال قابلاً للعمل دون اتصال بالمندوب
      INSERT INTO payment_receipts (
        customer_id, amount, payment_method, status,
        sales_order_id, collected_by, created_by,
        bank_reference, check_number, check_date,
        notes
      ) VALUES (
        v_order.customer_id, p_cash_amount,
        COALESCE(p_payment_method, 'bank_transfer'), 'pending',
        p_order_id, p_user_id, p_user_id,
        p_bank_reference, p_check_number, p_check_date,
        'بانتظار التأكيد المالي — فاتورة #' || v_order.order_number
      );

      -- الجزء الذي يُشغّله المحاسب لاحقاً (confirm_payment_receipt):
      -- DR: 1120/1130/1210 → CR: 1200 + paid_amount + status='completed'

      -- تُعامَل كـ آجل مؤقت في الدفتر (تُعكس بمجرد تأكيد الإيصال)
      INSERT INTO customer_ledger (
        customer_id, type, amount, source_type, source_id,
        description, created_by
      ) VALUES (
        v_order.customer_id, 'debit', p_cash_amount,
        'sales_order', p_order_id,
        'بانتظار تأكيد دفعة '  || COALESCE(p_payment_method, '') || ' — #' || v_order.order_number,
        p_user_id
      );

    END IF; -- v_is_cash
  END IF; -- p_cash_amount > 0

  -- ٤ب. الآجل الصريح → دفتر العميل (مدين)
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
  -- ٥. القيد المحاسبي الخاص بالتسليم
  -- ════════════════════════════════════════════════════════════

  -- الإيرادات (دائن)
  v_journal_lines := v_journal_lines || jsonb_build_object(
    'account_code', '4100', 'debit', 0,
    'credit', v_order.total_amount - COALESCE(v_order.tax_amount, 0),
    'description', 'إيراد بيع #' || v_order.order_number
  );

  -- الضريبة (دائن)
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

  IF p_cash_amount > 0 THEN
    IF v_is_cash THEN
      -- النقدي الفوري → عهدة أو خزينة
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
      -- غير نقدي: يُعامَل كذمم مدينة مؤقتاً (سيُعكس عند تأكيد الإيصال)
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
      -- paid_amount يُحدَّث فقط للنقدي الفوري
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

  -- ٧. فحص اكتمال السداد (للنقدي الفوري only — التحويلات تنتظر confirm_payment_receipt)
  IF v_is_cash THEN
    IF (COALESCE(v_order.paid_amount, 0) + p_cash_amount + COALESCE(v_order.returned_amount, 0)) >= v_order.total_amount THEN
      UPDATE sales_orders SET status = 'completed' WHERE id = p_order_id;
    END IF;
  END IF;

END;
$$;

GRANT EXECUTE ON FUNCTION deliver_sales_order TO authenticated;
