-- ============================================================
-- 57: Finance opening balance adjustments
-- New RPCs only, no historical backfill
-- ============================================================

CREATE TABLE IF NOT EXISTS customer_opening_balance_audit (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id         UUID NOT NULL REFERENCES customers(id),
  old_opening_balance NUMERIC(14,2) NOT NULL,
  new_opening_balance NUMERIC(14,2) NOT NULL,
  delta               NUMERIC(14,2) NOT NULL,
  journal_entry_id    UUID REFERENCES journal_entries(id),
  ledger_row_id       UUID,
  reason              TEXT,
  changed_by          UUID REFERENCES profiles(id),
  changed_at          TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS supplier_opening_balance_audit (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id         UUID NOT NULL REFERENCES suppliers(id),
  old_opening_balance NUMERIC(14,2) NOT NULL,
  new_opening_balance NUMERIC(14,2) NOT NULL,
  delta               NUMERIC(14,2) NOT NULL,
  journal_entry_id    UUID REFERENCES journal_entries(id),
  ledger_row_id       UUID,
  reason              TEXT,
  changed_by          UUID REFERENCES profiles(id),
  changed_at          TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_customer_opening_balance_audit_customer_id
  ON customer_opening_balance_audit(customer_id);

CREATE INDEX IF NOT EXISTS idx_supplier_opening_balance_audit_supplier_id
  ON supplier_opening_balance_audit(supplier_id);

CREATE OR REPLACE FUNCTION adjust_customer_opening_balance(
  p_customer_id         UUID,
  p_new_opening_balance  NUMERIC,
  p_reason              TEXT,
  p_user_id             UUID
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old       NUMERIC(14,2);
  v_delta     NUMERIC(14,2);
  v_lines     JSONB;
  v_je_id     UUID;
  v_ledger_id UUID;
BEGIN
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  IF p_new_opening_balance IS NULL THEN
    RAISE EXCEPTION 'New opening balance is required';
  END IF;

  SELECT opening_balance
  INTO v_old
  FROM customers
  WHERE id = p_customer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Customer not found: %', p_customer_id;
  END IF;

  v_old := COALESCE(v_old, 0);
  v_delta := ROUND(COALESCE(p_new_opening_balance, 0) - v_old, 2);

  IF v_delta = 0 THEN
    RETURN;
  END IF;

  PERFORM set_config('app.finance_context', 'opening_balance_adjustment', true);

  UPDATE customers
  SET opening_balance = p_new_opening_balance
  WHERE id = p_customer_id;

  INSERT INTO customer_ledger (
    customer_id, type, amount, source_type, source_id, description, created_by
  ) VALUES (
    p_customer_id,
    CASE WHEN v_delta > 0 THEN 'debit' ELSE 'credit' END,
    ABS(v_delta),
    'adjustment',
    gen_random_uuid(),
    'Opening balance adjustment: ' || COALESCE(p_reason, ''),
    p_user_id
  )
  RETURNING id INTO v_ledger_id;

  v_lines := jsonb_build_array(
    jsonb_build_object(
      'account_code', '1200',
      'debit',        CASE WHEN v_delta > 0 THEN ABS(v_delta) ELSE 0 END,
      'credit',       CASE WHEN v_delta < 0 THEN ABS(v_delta) ELSE 0 END,
      'description',  'AR opening balance adjustment'
    ),
    jsonb_build_object(
      'account_code', '3200',
      'debit',        CASE WHEN v_delta < 0 THEN ABS(v_delta) ELSE 0 END,
      'credit',       CASE WHEN v_delta > 0 THEN ABS(v_delta) ELSE 0 END,
      'description',  'Retained earnings offset'
    )
  );

  SELECT create_manual_journal_entry(
    'Customer opening balance adjustment: ' || COALESCE(p_reason, ''),
    CURRENT_DATE,
    'manual',
    p_customer_id,
    v_lines,
    p_user_id
  ) INTO v_je_id;

  INSERT INTO customer_opening_balance_audit (
    customer_id, old_opening_balance, new_opening_balance, delta,
    journal_entry_id, ledger_row_id, reason, changed_by
  ) VALUES (
    p_customer_id, v_old, p_new_opening_balance, v_delta,
    v_je_id, v_ledger_id, p_reason, p_user_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION adjust_supplier_opening_balance(
  p_supplier_id         UUID,
  p_new_opening_balance  NUMERIC,
  p_reason              TEXT,
  p_user_id             UUID
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old       NUMERIC(14,2);
  v_delta     NUMERIC(14,2);
  v_lines     JSONB;
  v_je_id     UUID;
  v_ledger_id UUID;
BEGIN
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  IF p_new_opening_balance IS NULL THEN
    RAISE EXCEPTION 'New opening balance is required';
  END IF;

  SELECT opening_balance
  INTO v_old
  FROM suppliers
  WHERE id = p_supplier_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Supplier not found: %', p_supplier_id;
  END IF;

  v_old := COALESCE(v_old, 0);
  v_delta := ROUND(COALESCE(p_new_opening_balance, 0) - v_old, 2);

  IF v_delta = 0 THEN
    RETURN;
  END IF;

  PERFORM set_config('app.finance_context', 'opening_balance_adjustment', true);

  UPDATE suppliers
  SET opening_balance = p_new_opening_balance
  WHERE id = p_supplier_id;

  INSERT INTO supplier_ledger (
    supplier_id, type, amount, source_type, source_id, description, created_by
  ) VALUES (
    p_supplier_id,
    CASE WHEN v_delta > 0 THEN 'credit' ELSE 'debit' END,
    ABS(v_delta),
    'adjustment',
    gen_random_uuid(),
    'Opening balance adjustment: ' || COALESCE(p_reason, ''),
    p_user_id
  )
  RETURNING id INTO v_ledger_id;

  v_lines := jsonb_build_array(
    jsonb_build_object(
      'account_code', '3200',
      'debit',        CASE WHEN v_delta > 0 THEN ABS(v_delta) ELSE 0 END,
      'credit',       CASE WHEN v_delta < 0 THEN ABS(v_delta) ELSE 0 END,
      'description',  'Retained earnings offset'
    ),
    jsonb_build_object(
      'account_code', '2100',
      'debit',        CASE WHEN v_delta < 0 THEN ABS(v_delta) ELSE 0 END,
      'credit',       CASE WHEN v_delta > 0 THEN ABS(v_delta) ELSE 0 END,
      'description',  'AP opening balance adjustment'
    )
  );

  SELECT create_manual_journal_entry(
    'Supplier opening balance adjustment: ' || COALESCE(p_reason, ''),
    CURRENT_DATE,
    'manual',
    p_supplier_id,
    v_lines,
    p_user_id
  ) INTO v_je_id;

  INSERT INTO supplier_opening_balance_audit (
    supplier_id, old_opening_balance, new_opening_balance, delta,
    journal_entry_id, ledger_row_id, reason, changed_by
  ) VALUES (
    p_supplier_id, v_old, p_new_opening_balance, v_delta,
    v_je_id, v_ledger_id, p_reason, p_user_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION update_customer_with_opening_balance(
  p_customer_id          UUID,
  p_non_financial_patch  JSONB DEFAULT '{}'::JSONB,
  p_new_opening_balance  NUMERIC DEFAULT NULL,
  p_reason               TEXT DEFAULT NULL,
  p_user_id              UUID DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer customers%ROWTYPE;
  v_patch    JSONB := COALESCE(p_non_financial_patch, '{}'::JSONB);
BEGIN
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  SELECT *
  INTO v_customer
  FROM customers
  WHERE id = p_customer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Customer not found: %', p_customer_id;
  END IF;

  UPDATE customers
  SET
    name = CASE WHEN v_patch ? 'name' THEN v_patch->>'name' ELSE v_customer.name END,
    type = CASE WHEN v_patch ? 'type' THEN v_patch->>'type' ELSE v_customer.type END,
    governorate_id = CASE WHEN v_patch ? 'governorate_id' THEN (v_patch->>'governorate_id')::UUID ELSE v_customer.governorate_id END,
    city_id = CASE WHEN v_patch ? 'city_id' THEN (v_patch->>'city_id')::UUID ELSE v_customer.city_id END,
    area_id = CASE WHEN v_patch ? 'area_id' THEN (v_patch->>'area_id')::UUID ELSE v_customer.area_id END,
    address = CASE WHEN v_patch ? 'address' THEN v_patch->>'address' ELSE v_customer.address END,
    phone = CASE WHEN v_patch ? 'phone' THEN v_patch->>'phone' ELSE v_customer.phone END,
    mobile = CASE WHEN v_patch ? 'mobile' THEN v_patch->>'mobile' ELSE v_customer.mobile END,
    email = CASE WHEN v_patch ? 'email' THEN v_patch->>'email' ELSE v_customer.email END,
    tax_number = CASE WHEN v_patch ? 'tax_number' THEN v_patch->>'tax_number' ELSE v_customer.tax_number END,
    payment_terms = CASE WHEN v_patch ? 'payment_terms' THEN v_patch->>'payment_terms' ELSE v_customer.payment_terms END,
    credit_limit = CASE WHEN v_patch ? 'credit_limit' THEN (v_patch->>'credit_limit')::NUMERIC ELSE v_customer.credit_limit END,
    credit_days = CASE WHEN v_patch ? 'credit_days' THEN (v_patch->>'credit_days')::INT ELSE v_customer.credit_days END,
    price_list_id = CASE WHEN v_patch ? 'price_list_id' THEN (v_patch->>'price_list_id')::UUID ELSE v_customer.price_list_id END,
    assigned_rep_id = CASE WHEN v_patch ? 'assigned_rep_id' THEN (v_patch->>'assigned_rep_id')::UUID ELSE v_customer.assigned_rep_id END,
    is_active = CASE WHEN v_patch ? 'is_active' THEN (v_patch->>'is_active')::BOOLEAN ELSE v_customer.is_active END,
    notes = CASE WHEN v_patch ? 'notes' THEN v_patch->>'notes' ELSE v_customer.notes END
  WHERE id = p_customer_id;

  IF p_new_opening_balance IS NOT NULL THEN
    PERFORM adjust_customer_opening_balance(
      p_customer_id, p_new_opening_balance, p_reason, p_user_id
    );
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION update_supplier_with_opening_balance(
  p_supplier_id          UUID,
  p_non_financial_patch  JSONB DEFAULT '{}'::JSONB,
  p_new_opening_balance  NUMERIC DEFAULT NULL,
  p_reason               TEXT DEFAULT NULL,
  p_user_id              UUID DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_supplier suppliers%ROWTYPE;
  v_patch    JSONB := COALESCE(p_non_financial_patch, '{}'::JSONB);
BEGIN
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  SELECT *
  INTO v_supplier
  FROM suppliers
  WHERE id = p_supplier_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Supplier not found: %', p_supplier_id;
  END IF;

  UPDATE suppliers
  SET
    name = CASE WHEN v_patch ? 'name' THEN v_patch->>'name' ELSE v_supplier.name END,
    type = CASE WHEN v_patch ? 'type' THEN v_patch->>'type' ELSE v_supplier.type END,
    governorate_id = CASE WHEN v_patch ? 'governorate_id' THEN (v_patch->>'governorate_id')::UUID ELSE v_supplier.governorate_id END,
    city_id = CASE WHEN v_patch ? 'city_id' THEN (v_patch->>'city_id')::UUID ELSE v_supplier.city_id END,
    phone = CASE WHEN v_patch ? 'phone' THEN v_patch->>'phone' ELSE v_supplier.phone END,
    email = CASE WHEN v_patch ? 'email' THEN v_patch->>'email' ELSE v_supplier.email END,
    tax_number = CASE WHEN v_patch ? 'tax_number' THEN v_patch->>'tax_number' ELSE v_supplier.tax_number END,
    payment_terms = CASE WHEN v_patch ? 'payment_terms' THEN v_patch->>'payment_terms' ELSE v_supplier.payment_terms END,
    credit_limit = CASE WHEN v_patch ? 'credit_limit' THEN (v_patch->>'credit_limit')::NUMERIC ELSE v_supplier.credit_limit END,
    credit_days = CASE WHEN v_patch ? 'credit_days' THEN (v_patch->>'credit_days')::INT ELSE v_supplier.credit_days END,
    bank_account = CASE WHEN v_patch ? 'bank_account' THEN v_patch->>'bank_account' ELSE v_supplier.bank_account END,
    is_active = CASE WHEN v_patch ? 'is_active' THEN (v_patch->>'is_active')::BOOLEAN ELSE v_supplier.is_active END
  WHERE id = p_supplier_id;

  IF p_new_opening_balance IS NOT NULL THEN
    PERFORM adjust_supplier_opening_balance(
      p_supplier_id, p_new_opening_balance, p_reason, p_user_id
    );
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION adjust_customer_opening_balance(UUID, NUMERIC, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION adjust_supplier_opening_balance(UUID, NUMERIC, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION update_customer_with_opening_balance(UUID, JSONB, NUMERIC, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION update_supplier_with_opening_balance(UUID, JSONB, NUMERIC, TEXT, UUID) TO authenticated;
