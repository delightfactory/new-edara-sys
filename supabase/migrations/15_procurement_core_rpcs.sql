-- ============================================================
-- 15_procurement_core_rpcs.sql  [v3 — AUDIT PATCH]
-- EDARA v2 — المشتريات: RPCs الأساسية (المرحلتان 3 و 4)
-- Idempotent: آمن للتشغيل أكثر من مرة
--
-- الإصلاحات v2:
--   Fix-1: إعادة حساب إجماليات الفاتورة بعد الاستلام الجزئي
--   Fix-2: استخدام UUID الحركة كـ source_id لمنع تكرار دفتر الموردين
--   Fix-3: معالجة الشيكات (2110) بمسار منفصل بدون لمس الخزائن
--
-- الإصلاحات v3 (Audit Patch):
--   Audit-Fix-1: last_purchase_price = سعر تجاري صافٍ (بدون landed costs)
--   Audit-Fix-2: احترام إعداد tax_enabled من company_settings
-- ============================================================


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  RPC 1: receive_purchase_invoice  [v3]                    ║
-- ╚═══════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION receive_purchase_invoice(
  p_invoice_id  UUID,
  p_user_id     UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_invoice         purchase_invoices%ROWTYPE;
  v_item            RECORD;

  -- ───── توزيع مصاريف الشحن ─────
  v_total_value     NUMERIC := 0;
  v_total_qty       NUMERIC := 0;
  v_use_qty_basis   BOOLEAN := false;

  -- ───── تكاليف البند ─────
  v_net_cost        NUMERIC;
  v_landed_share    NUMERIC;
  v_true_net_cost   NUMERIC;
  v_item_value      NUMERIC;

  -- ───── WAC ─────
  v_base_qty        NUMERIC;
  v_base_unit_cost  NUMERIC;    -- للـ WAC (يشمل landed costs)

  -- [Audit-Fix-1] السعر التجاري الصافي لحقل last_purchase_price (بدون landed costs)
  v_commercial_unit_price NUMERIC;

  -- ─── [Fix-1] إجماليات محسوبة على الكميات الفعلية ─────────
  v_recv_subtotal   NUMERIC := 0;
  v_recv_discount   NUMERIC := 0;
  v_recv_tax        NUMERIC := 0;   -- يُصفَّر لو tax_enabled=false
  v_recv_total      NUMERIC := 0;

  -- [Audit-Fix-2] إعداد الضريبة العام
  v_tax_enabled     BOOLEAN := true;
  v_setting_val     TEXT;
BEGIN
  -- ══════════════════════════════════════════════════════════
  -- [SECURITY GUARD]
  -- ══════════════════════════════════════════════════════════
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  IF NOT check_permission(p_user_id, 'procurement.invoices.receive') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية تسجيل استلام فواتير الشراء';
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- [Audit-Fix-2] جلب إعداد الضريبة العام من company_settings
  --    المفتاح المفضّل: purchases.tax_enabled
  --    Fallback: sales.tax_enabled (إعداد مشترك)
  -- ══════════════════════════════════════════════════════════
  SELECT value INTO v_setting_val
  FROM company_settings
  WHERE key = 'purchases.tax_enabled'
  LIMIT 1;

  IF v_setting_val IS NULL THEN
    -- Fallback للإعداد المشترك مع المبيعات
    SELECT value INTO v_setting_val
    FROM company_settings
    WHERE key = 'sales.tax_enabled'
    LIMIT 1;
  END IF;

  -- بالتفسير الأكثر أماناً: إذا لم يُعثر على الإعداد → ضريبة مُفعَّلة (conservative)
  v_tax_enabled := COALESCE(v_setting_val, 'true') = 'true';

  -- ══════════════════════════════════════════════════════════
  -- 1. قفل الفاتورة
  -- ══════════════════════════════════════════════════════════
  SELECT * INTO v_invoice
  FROM purchase_invoices
  WHERE id = p_invoice_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'فاتورة الشراء غير موجودة: %', p_invoice_id;
  END IF;

  IF v_invoice.status != 'draft' THEN
    RAISE EXCEPTION 'لا يمكن تسجيل الاستلام — الفاتورة في حالة: %. يجب أن تكون (draft)',
      v_invoice.status;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM purchase_invoice_items
    WHERE invoice_id = p_invoice_id AND received_quantity > 0
  ) THEN
    RAISE EXCEPTION 'لا توجد بنود مستلمة — سجّل الكميات المستلمة أولاً';
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- 2. حساب قاعدة توزيع مصاريف الشحن
  --    Primary:  بالقيمة الصافية
  --    Fallback: بالكمية (لو كل البنود بخصم 100%)
  -- ══════════════════════════════════════════════════════════
  SELECT
    COALESCE(SUM(
      received_quantity * unit_price * (1 - COALESCE(discount_rate, 0) / 100.0)
    ), 0),
    COALESCE(SUM(received_quantity), 0)
  INTO v_total_value, v_total_qty
  FROM purchase_invoice_items
  WHERE invoice_id = p_invoice_id AND received_quantity > 0;

  IF v_total_value = 0 AND v_total_qty > 0 THEN
    v_use_qty_basis := true;
  ELSIF v_total_value = 0 AND v_total_qty = 0 THEN
    RAISE EXCEPTION 'لا يمكن توزيع مصاريف الشحن — الكمية الإجمالية المستلمة صفر';
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- 3. معالجة كل بند: حساب التكاليف + تحديث المخزون
  -- ══════════════════════════════════════════════════════════
  FOR v_item IN
    SELECT * FROM purchase_invoice_items
    WHERE invoice_id = p_invoice_id
    ORDER BY id
  LOOP
    IF v_item.received_quantity <= 0 THEN CONTINUE; END IF;

    -- ─── تكلفة البند الصافية ───
    v_net_cost := v_item.received_quantity
                * v_item.unit_price
                * (1 - COALESCE(v_item.discount_rate, 0) / 100.0);

    -- ─── حصة الشحن ───
    IF COALESCE(v_invoice.landed_costs, 0) = 0 THEN
      v_landed_share := 0;
    ELSIF v_use_qty_basis THEN
      v_landed_share := v_invoice.landed_costs * (v_item.received_quantity / v_total_qty);
    ELSE
      v_item_value   := v_net_cost;         -- هو نفسه الـ net_cost
      v_landed_share := v_invoice.landed_costs * (v_item_value / v_total_value);
    END IF;

    v_true_net_cost := COALESCE(v_net_cost, 0) + COALESCE(v_landed_share, 0);

    -- ─── [Fix-1] تراكم الإجماليات للتحديث اللاحق ─────────────
    v_recv_subtotal := v_recv_subtotal
                     + (v_item.received_quantity * v_item.unit_price);
    v_recv_discount := v_recv_discount
                     + (v_item.received_quantity * v_item.unit_price
                        * COALESCE(v_item.discount_rate, 0) / 100.0);

    -- [Audit-Fix-2] الضريبة فقط لو مُفعَّلة في إعدادات الشركة
    IF v_tax_enabled THEN
      v_recv_tax := v_recv_tax
                  + (v_net_cost * COALESCE(v_item.tax_rate, 0) / 100.0);
    END IF;

    -- ─── تحويل الكمية للوحدة الأساسية ───
    IF v_item.unit_id IS NOT NULL THEN
      v_base_qty := get_base_quantity(v_item.product_id, v_item.unit_id, v_item.received_quantity);
    ELSE
      v_base_qty := v_item.received_quantity;
    END IF;

    v_base_unit_cost := CASE WHEN v_base_qty > 0 THEN v_true_net_cost / v_base_qty ELSE 0 END;

    -- ─── تحديث WAC + تسجيل حركة دخول ───
    PERFORM update_stock_wac(
      v_invoice.warehouse_id,
      v_item.product_id,
      v_base_qty,
      v_base_unit_cost,
      'in',
      'purchase_order',
      p_invoice_id,
      p_user_id
    );

    -- ─── حفظ التكاليف في بند الفاتورة ───
    UPDATE purchase_invoice_items
    SET
      net_cost          = ROUND(v_net_cost, 4),
      landed_cost_share = ROUND(v_landed_share, 4),
      true_net_cost     = ROUND(v_true_net_cost, 4)
    WHERE id = v_item.id;

    -- ─── تحديث آخر سعر شراء ───
    -- [Audit-Fix-1] نحفظ السعر التجاري الصافي حصراً (unit_price × (1 - discount%))
    --   بدون landed costs لمنع التضخم السعري الوهمي في الفواتير القادمة
    v_commercial_unit_price := CASE
      WHEN v_base_qty > 0
      THEN (v_net_cost / v_base_qty)   -- net_cost = qty * unit_price * (1-disc)
                                        -- مقسوماً على الوحدة الأساسية
      ELSE v_item.unit_price * (1 - COALESCE(v_item.discount_rate, 0) / 100.0)
    END;

    UPDATE products
    SET last_purchase_price = ROUND(v_commercial_unit_price, 4)
    WHERE id = v_item.product_id;

  END LOOP;

  -- ══════════════════════════════════════════════════════════
  -- [Fix-1] 4. إعادة حساب إجماليات رأسية الفاتورة
  --    بناءً على ما استُلم فعلياً لا ما طُلب أصلاً
  --    total = (subtotal - discount) + tax + landed_costs
  -- ══════════════════════════════════════════════════════════
  v_recv_total := (v_recv_subtotal - v_recv_discount)
               + v_recv_tax
               + COALESCE(v_invoice.landed_costs, 0);

  UPDATE purchase_invoices
  SET
    subtotal        = ROUND(v_recv_subtotal, 2),
    discount_amount = ROUND(v_recv_discount, 2),
    tax_amount      = ROUND(v_recv_tax,      2),
    total_amount    = ROUND(v_recv_total,    2),
    -- ضبط paid_amount لو كانت تتجاوز الإجمالي الجديد (حماية)
    paid_amount     = LEAST(COALESCE(paid_amount, 0), ROUND(v_recv_total, 2)),
    status          = 'received',
    received_by     = p_user_id,
    received_at     = now(),
    updated_at      = now()
  WHERE id = p_invoice_id;

END; $$;

GRANT EXECUTE ON FUNCTION receive_purchase_invoice(UUID, UUID) TO authenticated;


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  RPC 2: bill_purchase_invoice                             ║
-- ║  [Fix-2] v_txn_id كـ source_id في دفتر الموردين          ║
-- ║  [Fix-3] مسار الشيك → 2110 بدون لمس الخزينة             ║
-- ╚═══════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION bill_purchase_invoice(
  p_invoice_id     UUID,
  p_user_id        UUID,
  p_vault_id       UUID    DEFAULT NULL,
  p_payment_method TEXT    DEFAULT NULL
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_invoice         purchase_invoices%ROWTYPE;
  v_supplier_name   TEXT;
  v_vault_type      TEXT;
  v_credit_account  TEXT;   -- حساب دائن للسداد (1110/1120/1130 أو 2110 للشيك)
  v_is_cheque       BOOLEAN := false;

  v_inventory_dr    NUMERIC;
  v_tax_dr          NUMERIC;
  v_ap_cr           NUMERIC;

  v_bill_lines      JSONB := '[]'::JSONB;
  v_payment_lines   JSONB := '[]'::JSONB;

  -- [Fix-2] UUID حركة الخزنة → يُستخدم كـ source_id في دفتر الموردين
  v_txn_id          UUID;
BEGIN
  -- ══════════════════════════════════════════════════════════
  -- [SECURITY GUARD]
  -- ══════════════════════════════════════════════════════════
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  IF NOT check_permission(p_user_id, 'procurement.invoices.bill') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية الاعتماد المالي لفواتير الشراء';
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- 1. قفل الفاتورة
  -- ══════════════════════════════════════════════════════════
  SELECT * INTO v_invoice
  FROM purchase_invoices
  WHERE id = p_invoice_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'فاتورة الشراء غير موجودة: %', p_invoice_id;
  END IF;

  IF v_invoice.status != 'received' THEN
    RAISE EXCEPTION 'لا يمكن الاعتماد المالي — الفاتورة في حالة: %. يجب أن تكون (received)',
      v_invoice.status;
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- 2. تحقق من الدفع الفوري (إن طُلب)
  -- ══════════════════════════════════════════════════════════
  IF p_vault_id IS NOT NULL OR p_payment_method = 'cheque' THEN
    IF NOT check_permission(p_user_id, 'procurement.invoices.pay') THEN
      RAISE EXCEPTION 'ليس لديك صلاحية سداد فواتير الموردين';
    END IF;
  END IF;

  -- [Fix-3] الشيك: تحديد نوع السداد
  v_is_cheque := (COALESCE(p_payment_method, '') = 'cheque');

  IF NOT v_is_cheque AND p_vault_id IS NOT NULL THEN
    -- سداد نقدي/بنكي: تحديد الحساب من نوع الخزنة
    SELECT type INTO v_vault_type FROM vaults WHERE id = p_vault_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'الخزنة المحددة غير موجودة: %', p_vault_id;
    END IF;
    v_credit_account := CASE v_vault_type
      WHEN 'cash'          THEN '1110'
      WHEN 'bank'          THEN '1120'
      WHEN 'mobile_wallet' THEN '1130'
      ELSE '1110'
    END;
  ELSIF v_is_cheque THEN
    -- [Fix-3] الشيك: الحساب الدائن = 2110 (أوراق دفع - شيكات موردين)
    v_credit_account := '2110';
  END IF;

  SELECT name INTO v_supplier_name FROM suppliers WHERE id = v_invoice.supplier_id;

  -- ══════════════════════════════════════════════════════════
  -- 3. مبالغ قيد الفاتورة
  -- ══════════════════════════════════════════════════════════
  v_inventory_dr := COALESCE(v_invoice.subtotal, 0)
                  - COALESCE(v_invoice.discount_amount, 0)
                  + COALESCE(v_invoice.landed_costs, 0);
  v_tax_dr       := COALESCE(v_invoice.tax_amount, 0);
  v_ap_cr        := COALESCE(v_invoice.total_amount, 0);

  IF ABS((v_inventory_dr + v_tax_dr) - v_ap_cr) > 0.01 THEN
    RAISE EXCEPTION
      'عدم توازن في القيد: DR_مخزون(%) + DR_ضريبة(%) ≠ CR_موردون(%). راجع الأرقام المالية.',
      v_inventory_dr, v_tax_dr, v_ap_cr;
  END IF;

  IF v_ap_cr <= 0 THEN
    RAISE EXCEPTION 'إجمالي الفاتورة يجب أن يكون أكبر من صفر';
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- 4. قيد الفاتورة: DR:1300 + DR:1510 → CR:2100
  -- ══════════════════════════════════════════════════════════
  v_bill_lines := v_bill_lines || jsonb_build_object(
    'account_code', '1300',
    'debit',        v_inventory_dr, 'credit', 0,
    'description',  'بضاعة مشتراه — ' || COALESCE(v_invoice.number, '')
                    || ' / ' || COALESCE(v_supplier_name, '')
  );

  IF v_tax_dr > 0 THEN
    v_bill_lines := v_bill_lines || jsonb_build_object(
      'account_code', '1510',
      'debit',        v_tax_dr, 'credit', 0,
      'description',  'ضريبة مدخلات — ' || COALESCE(v_invoice.number, '')
    );
  END IF;

  v_bill_lines := v_bill_lines || jsonb_build_object(
    'account_code', '2100',
    'debit',        0, 'credit', v_ap_cr,
    'description',  'التزام مورد — ' || COALESCE(v_supplier_name, '')
                    || ' / ' || COALESCE(v_invoice.number, '')
  );

  PERFORM create_manual_journal_entry(
    'قيد شراء — فاتورة ' || COALESCE(v_invoice.number, ''),
    CURRENT_DATE, 'purchase_order', p_invoice_id, v_bill_lines, p_user_id
  );

  -- ══════════════════════════════════════════════════════════
  -- 5. دفتر الموردين — AP Credit (الالتزام)
  -- ══════════════════════════════════════════════════════════
  INSERT INTO supplier_ledger (
    supplier_id, type,     amount,  source_type,     source_id,
    description,           created_by
  ) VALUES (
    v_invoice.supplier_id, 'credit', v_ap_cr, 'purchase_order', p_invoice_id,
    'فاتورة مشتريات — ' || COALESCE(v_invoice.number, ''),
    p_user_id
  );

  -- ══════════════════════════════════════════════════════════
  -- 6. ساق الدفع الفوري (Atomic Payment Leg)
  -- ══════════════════════════════════════════════════════════
  IF p_vault_id IS NOT NULL OR v_is_cheque THEN

    IF v_is_cheque THEN
      -- ─── [Fix-3] مسار الشيك: لا حركة في الخزينة ────────────
      -- نولّد UUID فريداً ليكون مرجعاً في دفتر الموردين
      v_txn_id := gen_random_uuid();

      -- قيد السداد: DR:2100 → CR:2110 (أوراق دفع)
      v_payment_lines := jsonb_build_array(
        jsonb_build_object(
          'account_code', '2100',
          'debit',        v_ap_cr, 'credit', 0,
          'description',  'تسوية ذمم مورد بشيك — ' || COALESCE(v_supplier_name, '')
        ),
        jsonb_build_object(
          'account_code', '2110',
          'debit',        0, 'credit', v_ap_cr,
          'description',  'شيك مُصدر للمورد — ' || COALESCE(v_invoice.number, '')
        )
      );

    ELSE
      -- ─── [Fix-2] مسار نقدي/بنكي: سحب من الخزينة ────────────
      -- نستقبل UUID الحركة لاستخدامه كـ source_id في دفتر الموردين
      v_txn_id := add_vault_transaction(
        p_vault_id,
        'vendor_payment',
        v_ap_cr,
        'purchase_order',
        p_invoice_id,
        'سداد فاتورة مورد — ' || COALESCE(v_supplier_name, '')
          || ' / ' || COALESCE(v_invoice.number, ''),
        p_user_id
      );

      -- قيد السداد: DR:2100 → CR:خزينة
      v_payment_lines := jsonb_build_array(
        jsonb_build_object(
          'account_code', '2100',
          'debit',        v_ap_cr, 'credit', 0,
          'description',  'تسوية ذمم مورد — ' || COALESCE(v_supplier_name, '')
        ),
        jsonb_build_object(
          'account_code', v_credit_account,
          'debit',        0, 'credit', v_ap_cr,
          'description',  'سداد نقدي/بنكي — ' || COALESCE(v_invoice.number, '')
        )
      );
    END IF;

    -- قيد السداد المحاسبي (مشترك بين المسارين)
    PERFORM create_manual_journal_entry(
      'سداد مورد — ' || COALESCE(v_invoice.number, ''),
      CURRENT_DATE, 'purchase_order', p_invoice_id, v_payment_lines, p_user_id
    );

    -- ─── [Fix-2] دفتر الموردين — AP Debit (السداد) ───────────
    -- source_id = v_txn_id (UUID الحركة) يضمن عدم التكرار
    INSERT INTO supplier_ledger (
      supplier_id, type,    amount,  source_type, source_id,
      description,          created_by
    ) VALUES (
      v_invoice.supplier_id, 'debit', v_ap_cr, 'payment', v_txn_id,
      'سداد فوري — ' || COALESCE(v_invoice.number, ''),
      p_user_id
    );

    -- ─── تحديث الفاتورة → paid ────────────────────────────────
    UPDATE purchase_invoices
    SET
      status         = 'paid',
      paid_amount    = v_ap_cr,
      vault_id       = p_vault_id,            -- NULL للشيك
      payment_method = COALESCE(p_payment_method, 'cash'),
      billed_by      = p_user_id,
      billed_at      = now(),
      updated_at     = now()
    WHERE id = p_invoice_id;

  ELSE
    -- ─── لا دفع فوري → billed (دين مؤجل) ───────────────────
    UPDATE purchase_invoices
    SET
      status    = 'billed',
      billed_by = p_user_id,
      billed_at = now(),
      updated_at = now()
    WHERE id = p_invoice_id;
  END IF;

END; $$;

GRANT EXECUTE ON FUNCTION bill_purchase_invoice(UUID, UUID, UUID, TEXT) TO authenticated;


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  RPC 3: pay_supplier                                      ║
-- ║  [Fix-2] v_txn_id كـ source_id في دفتر الموردين          ║
-- ║  [Fix-3] مسار الشيك → 2110 بدون لمس الخزينة             ║
-- ║  يدعم السداد الجزئي للفواتير المؤجلة (billed)            ║
-- ╚═══════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION pay_supplier(
  p_invoice_id     UUID,
  p_user_id        UUID,
  p_amount         NUMERIC,
  p_payment_method TEXT    DEFAULT 'cash',
  p_vault_id       UUID    DEFAULT NULL,      -- مطلوب لغير الشيكات
  p_notes          TEXT    DEFAULT NULL
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_invoice         purchase_invoices%ROWTYPE;
  v_supplier_name   TEXT;
  v_vault_type      TEXT;
  v_credit_account  TEXT;
  v_is_cheque       BOOLEAN := false;
  v_outstanding     NUMERIC;
  v_payment_lines   JSONB;

  -- [Fix-2] UUID حركة الخزينة للتوحيد مع دفتر الموردين
  v_txn_id          UUID;
BEGIN
  -- ══════════════════════════════════════════════════════════
  -- [SECURITY GUARD]
  -- ══════════════════════════════════════════════════════════
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  IF NOT check_permission(p_user_id, 'procurement.invoices.pay') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية سداد فواتير الموردين';
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- 1. قفل وتحقق
  -- ══════════════════════════════════════════════════════════
  SELECT * INTO v_invoice
  FROM purchase_invoices
  WHERE id = p_invoice_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'فاتورة الشراء غير موجودة';
  END IF;

  IF v_invoice.status != 'billed' THEN
    RAISE EXCEPTION 'لا يمكن السداد — الفاتورة في حالة: %. يجب أن تكون (billed)', v_invoice.status;
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'مبلغ السداد يجب أن يكون أكبر من صفر';
  END IF;

  v_outstanding := v_invoice.total_amount - COALESCE(v_invoice.paid_amount, 0);

  IF p_amount > v_outstanding + 0.01 THEN
    RAISE EXCEPTION 'مبلغ السداد (%) يتجاوز المتبقي (%)', p_amount, v_outstanding;
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- 2. تحديد مسار الدفع
  -- ══════════════════════════════════════════════════════════
  v_is_cheque := (COALESCE(p_payment_method, '') = 'cheque');

  IF NOT v_is_cheque THEN
    IF p_vault_id IS NULL THEN
      RAISE EXCEPTION 'يجب تحديد الخزينة للسداد النقدي/البنكي';
    END IF;
    SELECT type INTO v_vault_type FROM vaults WHERE id = p_vault_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'الخزينة غير موجودة: %', p_vault_id;
    END IF;
    v_credit_account := CASE v_vault_type
      WHEN 'cash'          THEN '1110'
      WHEN 'bank'          THEN '1120'
      WHEN 'mobile_wallet' THEN '1130'
      ELSE '1110'
    END;
  ELSE
    -- [Fix-3] الشيك
    v_credit_account := '2110';
  END IF;

  SELECT name INTO v_supplier_name FROM suppliers WHERE id = v_invoice.supplier_id;

  -- ══════════════════════════════════════════════════════════
  -- 3. معالجة حركة الدفع
  -- ══════════════════════════════════════════════════════════
  IF v_is_cheque THEN
    -- [Fix-3] لا حركة في الخزينة — نولّد UUID للمرجعية
    v_txn_id := gen_random_uuid();
  ELSE
    -- [Fix-2] سحب من الخزينة + استقبال UUID الحركة
    v_txn_id := add_vault_transaction(
      p_vault_id,
      'vendor_payment',
      p_amount,
      'purchase_order',
      p_invoice_id,
      COALESCE(p_notes, 'سداد مورد — ' || COALESCE(v_supplier_name, '')),
      p_user_id
    );
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- 4. القيد المحاسبي: DR:2100 → CR:خزينة أو CR:2110
  -- ══════════════════════════════════════════════════════════
  v_payment_lines := jsonb_build_array(
    jsonb_build_object(
      'account_code', '2100',
      'debit',        p_amount, 'credit', 0,
      'description',  'تسوية ذمم مورد — ' || COALESCE(v_supplier_name, '')
    ),
    jsonb_build_object(
      'account_code', v_credit_account,
      'debit',        0, 'credit', p_amount,
      'description',
      CASE WHEN v_is_cheque
        THEN 'شيك مُصدر — ' || COALESCE(v_invoice.number, '')
        ELSE 'سداد نقدي/بنكي — ' || COALESCE(v_invoice.number, '')
      END
    )
  );

  PERFORM create_manual_journal_entry(
    'سداد مورد — ' || COALESCE(v_invoice.number, ''),
    CURRENT_DATE, 'purchase_order', p_invoice_id, v_payment_lines, p_user_id
  );

  -- ══════════════════════════════════════════════════════════
  -- [Fix-2] 5. دفتر الموردين — AP Debit
  --    source_id = v_txn_id (UUID فريد) يمنع تكرار القيد
  -- ══════════════════════════════════════════════════════════
  INSERT INTO supplier_ledger (
    supplier_id, type,    amount,  source_type, source_id,
    description,          created_by
  ) VALUES (
    v_invoice.supplier_id, 'debit', p_amount, 'payment', v_txn_id,
    COALESCE(p_notes, 'سداد — ' || COALESCE(v_invoice.number, '')),
    p_user_id
  );

  -- ══════════════════════════════════════════════════════════
  -- 6. تحديث الفاتورة
  -- ══════════════════════════════════════════════════════════
  UPDATE purchase_invoices
  SET
    paid_amount    = ROUND(COALESCE(paid_amount, 0) + p_amount, 2),
    vault_id       = COALESCE(p_vault_id, vault_id),     -- يحتفظ بالخزينة الأولى للشيك
    payment_method = p_payment_method,
    status = CASE
               WHEN (COALESCE(paid_amount, 0) + p_amount) >= total_amount - 0.01
               THEN 'paid'
               ELSE 'billed'
             END,
    updated_at = now()
  WHERE id = p_invoice_id;

END; $$;

GRANT EXECUTE ON FUNCTION pay_supplier(UUID, UUID, NUMERIC, TEXT, UUID, TEXT) TO authenticated;


-- ============================================================
-- [Audit Patch v3.1] — Fix 1: Missing Column
-- إضافة حقل "آخر سعر شراء" لجدول المنتجات
-- Idempotent — آمن للتشغيل أكثر من مرة
-- ============================================================

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS last_purchase_price NUMERIC(14,4);

COMMENT ON COLUMN products.last_purchase_price
  IS 'آخر سعر شراء تجاري صافٍ (بدون landed costs) — يُحدَّث تلقائياً عند كل استلام';
