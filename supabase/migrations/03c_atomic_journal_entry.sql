-- ============================================================
-- 03c: Atomic Manual Journal Entry RPC
-- Fixes atomicity issue: header + lines in single transaction
-- ============================================================

CREATE OR REPLACE FUNCTION create_manual_journal_entry(
  p_description    TEXT,
  p_entry_date     DATE DEFAULT CURRENT_DATE,
  p_source_type    TEXT DEFAULT 'manual',
  p_source_id      UUID DEFAULT NULL,
  p_lines          JSONB DEFAULT '[]'::JSONB,
  p_user_id        UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_entry_id       UUID;
  v_total_debit    NUMERIC(14,2) := 0;
  v_total_credit   NUMERIC(14,2) := 0;
  v_line           JSONB;
  v_account_id     UUID;
  v_line_count     INT := 0;
BEGIN
  -- ─── Validate ───
  IF p_lines IS NULL OR jsonb_array_length(p_lines) < 2 THEN
    RAISE EXCEPTION 'القيد يجب أن يحتوي على سطرين على الأقل';
  END IF;

  -- ─── Calculate totals & validate accounts ───
  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    -- Validate account_code exists
    SELECT id INTO v_account_id
    FROM chart_of_accounts
    WHERE code = (v_line ->> 'account_code')
      AND is_active = true;

    IF v_account_id IS NULL THEN
      RAISE EXCEPTION 'حساب غير موجود أو غير نشط: %', (v_line ->> 'account_code');
    END IF;

    v_total_debit  := v_total_debit  + COALESCE((v_line ->> 'debit')::NUMERIC, 0);
    v_total_credit := v_total_credit + COALESCE((v_line ->> 'credit')::NUMERIC, 0);
    v_line_count   := v_line_count + 1;
  END LOOP;

  -- ─── Check balance ───
  IF v_total_debit <> v_total_credit THEN
    RAISE EXCEPTION 'القيد غير متوازن: مدين % ≠ دائن %', v_total_debit, v_total_credit;
  END IF;

  IF v_total_debit = 0 THEN
    RAISE EXCEPTION 'إجمالي القيد لا يمكن أن يكون صفراً';
  END IF;

  -- ─── Insert header ───
  INSERT INTO journal_entries (
    source_type, source_id, description, entry_date,
    is_auto, status, total_debit, total_credit, created_by
  ) VALUES (
    p_source_type, p_source_id, p_description, p_entry_date,
    false, 'posted', v_total_debit, v_total_credit, p_user_id
  )
  RETURNING id INTO v_entry_id;

  -- ─── Insert lines ───
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
  SELECT
    v_entry_id,
    ca.id,
    COALESCE((line ->> 'debit')::NUMERIC, 0),
    COALESCE((line ->> 'credit')::NUMERIC, 0),
    line ->> 'description'
  FROM jsonb_array_elements(p_lines) AS line
  JOIN chart_of_accounts ca ON ca.code = (line ->> 'account_code');

  RETURN v_entry_id;
END;
$$;
