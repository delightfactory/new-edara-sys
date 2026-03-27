-- ============================================================
-- 10_audit_fixes.sql
-- EDARA v2 — إصلاحات المراجعة المزدوجة (Gemini Audit)
-- الإصلاحات:
--   BE-01: فحص الائتمان المبكر في confirm_sales_order
--   BE-03: تسجيل الإيراد الإجمالي + الخصومات (حساب 4300)
--   BE-04: trigger الضريبة يحترم sales.tax_enabled
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- BE-04: تحديث trigger التحقق من بنود الطلب
--        ليحترم إعداد sales.tax_enabled من company_settings
-- ────────────────────────────────────────────────────────────

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

-- إعادة ربط الـ trigger (لا تغيير في binding — فقط الدالة تحدّثت)
DROP TRIGGER IF EXISTS trg_validate_sales_item ON sales_order_items;
CREATE TRIGGER trg_validate_sales_item
  BEFORE INSERT OR UPDATE ON sales_order_items
  FOR EACH ROW EXECUTE FUNCTION validate_sales_item_amounts();


-- ────────────────────────────────────────────────────────────
-- BE-01 + BE-03: تحديث confirm_sales_order
--   - إضافة فحص ائتمان مبكر من ملف العميل (BE-01)
--   ملاحظة: BE-03 يُطبَّق على deliver_sales_order أدناه
-- ────────────────────────────────────────────────────────────

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

GRANT EXECUTE ON FUNCTION confirm_sales_order(UUID, UUID) TO authenticated;


-- ────────────────────────────────────────────────────────────
-- BE-03: تحديث deliver_sales_order
--        تسجيل الإيراد الإجمالي (subtotal) + الخصومات (4300)
--        بدلاً من تسجيل الصافي فقط
-- ────────────────────────────────────────────────────────────

-- حذف الإصدار القديم (11 params) إن وُجد — نُحلّ بنفس الـ signature
DROP FUNCTION IF EXISTS deliver_sales_order(UUID, UUID, TEXT, TEXT, UUID, UUID, NUMERIC, BOOLEAN, TEXT, TEXT, DATE);

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

  -- النقدي الفعلي = cash فقط
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
        bank_reference, check_number, check_date,
        notes
      ) VALUES (
        v_order.customer_id, p_cash_amount,
        COALESCE(p_payment_method, 'bank_transfer'), 'pending',
        p_order_id, p_user_id, p_user_id,
        p_bank_reference, p_check_number, p_check_date,
        'بانتظار التأكيد المالي — فاتورة #' || v_order.order_number
      );

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
  -- ٥. القيد المحاسبي — [BE-03] تسجيل الإجمالي + الخصومات
  -- ════════════════════════════════════════════════════════════

  -- [BE-03] الإيرادات (دائن) — بالإجمالي (subtotal) قبل الخصم
  v_journal_lines := v_journal_lines || jsonb_build_object(
    'account_code', '4100', 'debit', 0,
    'credit', v_order.subtotal,
    'description', 'إيراد بيع إجمالي #' || v_order.order_number
  );

  -- [BE-03] الخصومات الممنوحة (مدين) — حساب 4300
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

GRANT EXECUTE ON FUNCTION deliver_sales_order TO authenticated;
