-- ============================================================
-- 58: Vault safe posting
-- Cross-type transfer posting + controlled manual vault adjustments
-- ============================================================

CREATE OR REPLACE FUNCTION transfer_between_vaults(
  p_from_vault_id  UUID,
  p_to_vault_id    UUID,
  p_amount         NUMERIC,
  p_description    TEXT DEFAULT '',
  p_user_id        UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_from_vault   vaults%ROWTYPE;
  v_to_vault     vaults%ROWTYPE;
  v_from_balance NUMERIC;
  v_to_balance   NUMERIC;
  v_txn_id       UUID;
  v_desc_out     TEXT;
  v_desc_in      TEXT;
  v_from_acct    TEXT;
  v_to_acct      TEXT;
BEGIN
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  IF p_from_vault_id IS NULL OR p_to_vault_id IS NULL THEN
    RAISE EXCEPTION 'Vault identifiers are required';
  END IF;

  IF p_from_vault_id = p_to_vault_id THEN
    RAISE EXCEPTION 'Source and destination vaults must differ';
  END IF;

  IF p_from_vault_id < p_to_vault_id THEN
    SELECT * INTO v_from_vault FROM vaults WHERE id = p_from_vault_id FOR UPDATE;
    SELECT * INTO v_to_vault   FROM vaults WHERE id = p_to_vault_id   FOR UPDATE;
  ELSE
    SELECT * INTO v_to_vault   FROM vaults WHERE id = p_to_vault_id   FOR UPDATE;
    SELECT * INTO v_from_vault FROM vaults WHERE id = p_from_vault_id FOR UPDATE;
  END IF;

  IF NOT FOUND THEN
    -- no-op, the row checks below will raise clearer errors
    NULL;
  END IF;

  IF v_from_vault.id IS NULL THEN
    RAISE EXCEPTION 'Source vault not found';
  END IF;
  IF v_to_vault.id IS NULL THEN
    RAISE EXCEPTION 'Destination vault not found';
  END IF;
  IF NOT v_from_vault.is_active THEN
    RAISE EXCEPTION 'Source vault is inactive';
  END IF;
  IF NOT v_to_vault.is_active THEN
    RAISE EXCEPTION 'Destination vault is inactive';
  END IF;

  IF v_from_vault.current_balance < p_amount THEN
    RAISE EXCEPTION 'Insufficient source vault balance';
  END IF;

  v_from_balance := v_from_vault.current_balance - p_amount;
  v_to_balance := v_to_vault.current_balance + p_amount;

  IF COALESCE(TRIM(p_description), '') = '' THEN
    v_desc_out := 'Transfer -> ' || v_to_vault.name;
    v_desc_in := 'Transfer <- ' || v_from_vault.name;
  ELSE
    v_desc_out := TRIM(p_description) || ' -> ' || v_to_vault.name;
    v_desc_in := TRIM(p_description) || ' <- ' || v_from_vault.name;
  END IF;

  INSERT INTO vault_transactions (
    vault_id, type, amount, balance_after,
    reference_type, reference_id, description, created_by
  ) VALUES (
    p_from_vault_id, 'transfer_out', p_amount, v_from_balance,
    'vault_transfer', p_to_vault_id, v_desc_out, p_user_id
  )
  RETURNING id INTO v_txn_id;

  INSERT INTO vault_transactions (
    vault_id, type, amount, balance_after,
    reference_type, reference_id, description, created_by
  ) VALUES (
    p_to_vault_id, 'transfer_in', p_amount, v_to_balance,
    'vault_transfer', p_from_vault_id, v_desc_in, p_user_id
  );

  UPDATE vaults SET current_balance = v_from_balance WHERE id = p_from_vault_id;
  UPDATE vaults SET current_balance = v_to_balance   WHERE id = p_to_vault_id;

  v_from_acct := CASE v_from_vault.type
    WHEN 'bank' THEN '1120'
    WHEN 'mobile_wallet' THEN '1130'
    ELSE '1110'
  END;
  v_to_acct := CASE v_to_vault.type
    WHEN 'bank' THEN '1120'
    WHEN 'mobile_wallet' THEN '1130'
    ELSE '1110'
  END;

  IF v_from_acct <> v_to_acct THEN
    PERFORM create_auto_journal_entry(
      'transfer',
      v_txn_id,
      COALESCE(NULLIF(TRIM(p_description), ''), 'Vault transfer'),
      v_to_acct,
      v_from_acct,
      p_amount,
      p_user_id
    );
  END IF;

  RETURN v_txn_id;
END;
$$;

CREATE OR REPLACE FUNCTION post_manual_vault_adjustment(
  p_vault_id    UUID,
  p_direction   TEXT,
  p_amount      NUMERIC,
  p_reason_code TEXT,
  p_description TEXT,
  p_user_id     UUID
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_vault       vaults%ROWTYPE;
  v_vault_acct  TEXT;
  v_contra_acct TEXT;
  v_txn_type    TEXT;
  v_txn_id      UUID;
BEGIN
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  SELECT *
  INTO v_vault
  FROM vaults
  WHERE id = p_vault_id
    AND is_active = true
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Vault not found or inactive';
  END IF;

  v_vault_acct := CASE v_vault.type
    WHEN 'bank' THEN '1120'
    WHEN 'mobile_wallet' THEN '1130'
    ELSE '1110'
  END;

  v_contra_acct := CASE p_reason_code
    WHEN 'opening_balance' THEN '3200'
    WHEN 'owner_funding' THEN '3100'
    WHEN 'owner_withdrawal' THEN '3100'
    WHEN 'cash_shortage' THEN '5900'
    WHEN 'cash_overage' THEN '5900'
    WHEN 'treasury_adjustment' THEN '3200'
    ELSE NULL
  END;

  IF v_contra_acct IS NULL THEN
    RAISE EXCEPTION 'Unknown reason code: %', p_reason_code;
  END IF;

  IF p_direction NOT IN ('deposit', 'withdrawal', 'opening_balance') THEN
    RAISE EXCEPTION 'Invalid direction: %', p_direction;
  END IF;

  v_txn_type := p_direction;

  SELECT add_vault_transaction(
    p_vault_id,
    v_txn_type,
    p_amount,
    'manual',
    NULL,
    COALESCE(NULLIF(TRIM(p_description), ''), 'Manual vault adjustment'),
    p_user_id
  ) INTO v_txn_id;

  IF p_direction IN ('deposit', 'opening_balance') THEN
    PERFORM create_auto_journal_entry(
      'manual',
      v_txn_id,
      COALESCE(NULLIF(TRIM(p_description), ''), 'Manual vault adjustment'),
      v_vault_acct,
      v_contra_acct,
      p_amount,
      p_user_id
    );
  ELSE
    PERFORM create_auto_journal_entry(
      'manual',
      v_txn_id,
      COALESCE(NULLIF(TRIM(p_description), ''), 'Manual vault adjustment'),
      v_contra_acct,
      v_vault_acct,
      p_amount,
      p_user_id
    );
  END IF;

  RETURN v_txn_id;
END;
$$;

GRANT EXECUTE ON FUNCTION transfer_between_vaults(UUID, UUID, NUMERIC, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION post_manual_vault_adjustment(UUID, TEXT, NUMERIC, TEXT, TEXT, UUID) TO authenticated;
