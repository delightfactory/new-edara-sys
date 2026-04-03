-- ============================================================
-- 60: Finance field guards
-- Protect opening balances and vault type changes
-- ============================================================

CREATE OR REPLACE FUNCTION guard_customer_opening_balance()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.opening_balance IS DISTINCT FROM NEW.opening_balance
     AND current_setting('app.finance_context', true) IS DISTINCT FROM 'opening_balance_adjustment' THEN
    RAISE EXCEPTION 'Direct customer opening balance updates are not allowed';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_customer_opening_balance ON customers;
CREATE TRIGGER trg_guard_customer_opening_balance
  BEFORE UPDATE ON customers
  FOR EACH ROW
  EXECUTE FUNCTION guard_customer_opening_balance();

CREATE OR REPLACE FUNCTION guard_supplier_opening_balance()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.opening_balance IS DISTINCT FROM NEW.opening_balance
     AND current_setting('app.finance_context', true) IS DISTINCT FROM 'opening_balance_adjustment' THEN
    RAISE EXCEPTION 'Direct supplier opening balance updates are not allowed';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_supplier_opening_balance ON suppliers;
CREATE TRIGGER trg_guard_supplier_opening_balance
  BEFORE UPDATE ON suppliers
  FOR EACH ROW
  EXECUTE FUNCTION guard_supplier_opening_balance();

CREATE OR REPLACE FUNCTION guard_vault_type()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.type IS DISTINCT FROM NEW.type
     AND EXISTS (
       SELECT 1
       FROM vault_transactions vt
       WHERE vt.vault_id = OLD.id
     ) THEN
    RAISE EXCEPTION 'Vault type cannot be changed after financial activity exists';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_vault_type ON vaults;
CREATE TRIGGER trg_guard_vault_type
  BEFORE UPDATE ON vaults
  FOR EACH ROW
  EXECUTE FUNCTION guard_vault_type();

CREATE OR REPLACE FUNCTION create_ui_manual_journal_entry(
  p_description  TEXT,
  p_entry_date   DATE DEFAULT CURRENT_DATE,
  p_source_type  TEXT DEFAULT 'manual',
  p_source_id    UUID DEFAULT NULL,
  p_lines        JSONB DEFAULT '[]'::JSONB,
  p_user_id      UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_blocked_count INT;
BEGIN
  SELECT COUNT(*)
  INTO v_blocked_count
  FROM jsonb_array_elements(COALESCE(p_lines, '[]'::JSONB)) AS l
  WHERE (l ->> 'account_code') IN ('1200', '2100');

  IF v_blocked_count > 0 THEN
    RAISE EXCEPTION 'Direct posting to control accounts 1200 and 2100 is not allowed from the UI';
  END IF;

  RETURN create_manual_journal_entry(
    p_description,
    p_entry_date,
    p_source_type,
    p_source_id,
    p_lines,
    p_user_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION create_ui_manual_journal_entry(TEXT, DATE, TEXT, UUID, JSONB, UUID) TO authenticated;
