-- Owned local qualification dependency only; do not replay the full financial migration.
-- Exact create_auto_journal_entry source from20b_audit_fixes.sql; ACL is set by the new migration.
CREATE OR REPLACE FUNCTION create_auto_journal_entry(
  p_source_type   TEXT,
  p_source_id     UUID,
  p_description   TEXT,
  p_debit_account TEXT,     -- ÙƒÙˆØ¯ Ø§Ù„Ø­Ø³Ø§Ø¨ Ø§Ù„Ù…Ø¯ÙŠÙ†
  p_credit_account TEXT,    -- ÙƒÙˆØ¯ Ø§Ù„Ø­Ø³Ø§Ø¨ Ø§Ù„Ø¯Ø§Ø¦Ù†
  p_amount        NUMERIC,
  p_user_id       UUID
) RETURNS UUID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_entry_id    UUID;
  v_debit_acct  UUID;
  v_credit_acct UUID;
BEGIN
  -- FIX-AUDIT-04: Ø±ÙØ¶ Ù…Ø¨Ø§Ù„Øº ØµÙØ±ÙŠØ© Ø£Ùˆ Ø³Ø§Ù„Ø¨Ø©
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'create_auto_journal_entry: Ø§Ù„Ù…Ø¨Ù„Øº ÙŠØ¬Ø¨ Ø£Ù† ÙŠÙƒÙˆÙ† Ø£ÙƒØ¨Ø± Ù…Ù† ØµÙØ± (Ø§Ù„Ù‚ÙŠÙ…Ø©: %)', COALESCE(p_amount, 0);
  END IF;

  -- Ø¬Ù„Ø¨ Ù…Ø¹Ø±Ù‘ÙØ§Øª Ø§Ù„Ø­Ø³Ø§Ø¨Ø§Øª Ù…Ù† Ø§Ù„Ø£ÙƒÙˆØ§Ø¯
  SELECT id INTO v_debit_acct FROM chart_of_accounts WHERE code = p_debit_account;
  IF v_debit_acct IS NULL THEN
    RAISE EXCEPTION 'Ø­Ø³Ø§Ø¨ Ù…Ø¯ÙŠÙ† ØºÙŠØ± Ù…ÙˆØ¬ÙˆØ¯: %', p_debit_account;
  END IF;

  SELECT id INTO v_credit_acct FROM chart_of_accounts WHERE code = p_credit_account;
  IF v_credit_acct IS NULL THEN
    RAISE EXCEPTION 'Ø­Ø³Ø§Ø¨ Ø¯Ø§Ø¦Ù† ØºÙŠØ± Ù…ÙˆØ¬ÙˆØ¯: %', p_credit_account;
  END IF;

  -- Ø¥Ù†Ø´Ø§Ø¡ Ø§Ù„Ù‚ÙŠØ¯ (total_debit = total_credit â†’ ÙŠÙ…Ø± Ù…Ù† CHECK constraint)
  INSERT INTO journal_entries (
    source_type, source_id, description, is_auto,
    total_debit, total_credit, created_by
  ) VALUES (
    p_source_type, p_source_id, p_description, true,
    p_amount, p_amount, p_user_id
  )
  RETURNING id INTO v_entry_id;

  -- Ø¥Ø¯Ø±Ø§Ø¬ Ø§Ù„Ø³Ø·Ø± Ø§Ù„Ù…Ø¯ÙŠÙ†
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
  VALUES (v_entry_id, v_debit_acct, p_amount, 0, p_description);

  -- Ø¥Ø¯Ø±Ø§Ø¬ Ø§Ù„Ø³Ø·Ø± Ø§Ù„Ø¯Ø§Ø¦Ù†
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
  VALUES (v_entry_id, v_credit_acct, 0, p_amount, p_description);

  RETURN v_entry_id;
END; $$;
