-- ============================================================
-- 03d: Vault-to-Vault Transfer (Atomic)
-- Wraps two vault_transactions inserts in one transaction
-- Source: transfer_out, Target: transfer_in
-- ============================================================

CREATE OR REPLACE FUNCTION transfer_between_vaults(
  p_from_vault_id  UUID,
  p_to_vault_id    UUID,
  p_amount         NUMERIC,
  p_description    TEXT DEFAULT '',
  p_user_id        UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_from_vault   vaults%ROWTYPE;
  v_to_vault     vaults%ROWTYPE;
  v_from_balance NUMERIC;
  v_to_balance   NUMERIC;
  v_txn_id       UUID;  -- return the outgoing transaction ID
  v_desc_out     TEXT;
  v_desc_in      TEXT;
BEGIN
  -- ─── 1. Input validation ───
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
  END IF;

  IF p_from_vault_id IS NULL OR p_to_vault_id IS NULL THEN
    RAISE EXCEPTION 'معرّف الخزنة مطلوب';
  END IF;

  IF p_from_vault_id = p_to_vault_id THEN
    RAISE EXCEPTION 'لا يمكن التحويل من وإلى نفس الخزنة';
  END IF;

  -- ─── 2. Lock both vaults (consistent order by UUID to prevent deadlock) ───
  IF p_from_vault_id < p_to_vault_id THEN
    SELECT * INTO v_from_vault FROM vaults WHERE id = p_from_vault_id FOR UPDATE;
    SELECT * INTO v_to_vault   FROM vaults WHERE id = p_to_vault_id   FOR UPDATE;
  ELSE
    SELECT * INTO v_to_vault   FROM vaults WHERE id = p_to_vault_id   FOR UPDATE;
    SELECT * INTO v_from_vault FROM vaults WHERE id = p_from_vault_id FOR UPDATE;
  END IF;

  -- ─── 3. Existence check ───
  IF v_from_vault.id IS NULL THEN
    RAISE EXCEPTION 'خزنة المصدر غير موجودة';
  END IF;
  IF v_to_vault.id IS NULL THEN
    RAISE EXCEPTION 'خزنة الوجهة غير موجودة';
  END IF;

  -- ─── 4. Active check ───
  IF NOT v_from_vault.is_active THEN
    RAISE EXCEPTION 'خزنة المصدر معطلة';
  END IF;
  IF NOT v_to_vault.is_active THEN
    RAISE EXCEPTION 'خزنة الوجهة معطلة';
  END IF;

  -- ─── 5. Sufficient balance check ───
  IF v_from_vault.current_balance < p_amount THEN
    RAISE EXCEPTION 'رصيد خزنة المصدر غير كافٍ (المتاح: %، المطلوب: %)',
      v_from_vault.current_balance, p_amount;
  END IF;

  -- ─── 6. Calculate new balances ───
  v_from_balance := v_from_vault.current_balance - p_amount;
  v_to_balance   := v_to_vault.current_balance   + p_amount;

  -- ─── 7. Build descriptions ───
  -- Format: "user description → target_name" / "user description ← source_name"
  -- If no user description, just show the vault name
  IF COALESCE(TRIM(p_description), '') = '' THEN
    v_desc_out := 'تحويل → ' || v_to_vault.name;
    v_desc_in  := 'تحويل ← ' || v_from_vault.name;
  ELSE
    v_desc_out := TRIM(p_description) || ' → ' || v_to_vault.name;
    v_desc_in  := TRIM(p_description) || ' ← ' || v_from_vault.name;
  END IF;

  -- ─── 8. Insert transfer_out (source) ───
  INSERT INTO vault_transactions (
    vault_id, type, amount, balance_after,
    reference_type, reference_id, description, created_by
  ) VALUES (
    p_from_vault_id, 'transfer_out', p_amount, v_from_balance,
    'vault_transfer', p_to_vault_id, v_desc_out, p_user_id
  )
  RETURNING id INTO v_txn_id;

  -- ─── 9. Insert transfer_in (target) ───
  INSERT INTO vault_transactions (
    vault_id, type, amount, balance_after,
    reference_type, reference_id, description, created_by
  ) VALUES (
    p_to_vault_id, 'transfer_in', p_amount, v_to_balance,
    'vault_transfer', p_from_vault_id, v_desc_in, p_user_id
  );

  -- ─── 10. Update cached balances ───
  UPDATE vaults SET current_balance = v_from_balance WHERE id = p_from_vault_id;
  UPDATE vaults SET current_balance = v_to_balance   WHERE id = p_to_vault_id;

  RETURN v_txn_id;
END;
$$;
