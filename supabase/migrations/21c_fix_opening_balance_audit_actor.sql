-- Fix opening balance triggers for customers/suppliers.
-- Root causes:
--   1) suppliers rows do not expose a created_by column,
--      but the trigger functions referenced NEW.created_by directly.
--   2) some environments historically had init_balance triggers enabled,
--      which caused current_balance duplication when opening_balance was
--      also written into the ledger and then re-applied by ledger triggers.
-- Result:
--   INSERT on suppliers fails with:
--   record "new" has no field "created_by"

-- Safety belt: ensure the legacy init triggers are not present in drifted DBs.
DROP TRIGGER IF EXISTS trg_customer_init_balance ON customers;
DROP TRIGGER IF EXISTS trg_supplier_init_balance ON suppliers;

CREATE OR REPLACE FUNCTION sync_customer_opening_balance()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(NEW.opening_balance, 0) > 0 THEN
    IF NOT EXISTS (
      SELECT 1
      FROM customer_ledger
      WHERE source_type = 'opening_balance'
        AND source_id = NEW.id
    ) THEN
      INSERT INTO customer_ledger (
        customer_id,
        type,
        amount,
        source_type,
        source_id,
        description,
        created_by
      ) VALUES (
        NEW.id,
        'debit',
        NEW.opening_balance,
        'opening_balance',
        NEW.id,
        'رصيد افتتاحي',
        COALESCE((to_jsonb(NEW) ->> 'created_by')::uuid, auth.uid())
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION sync_supplier_opening_balance()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(NEW.opening_balance, 0) > 0 THEN
    IF NOT EXISTS (
      SELECT 1
      FROM supplier_ledger
      WHERE source_type = 'opening_balance'
        AND source_id = NEW.id
    ) THEN
      INSERT INTO supplier_ledger (
        supplier_id,
        type,
        amount,
        source_type,
        source_id,
        description,
        created_by
      ) VALUES (
        NEW.id,
        'credit',
        NEW.opening_balance,
        'opening_balance',
        NEW.id,
        'رصيد افتتاحي',
        COALESCE((to_jsonb(NEW) ->> 'created_by')::uuid, auth.uid())
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
