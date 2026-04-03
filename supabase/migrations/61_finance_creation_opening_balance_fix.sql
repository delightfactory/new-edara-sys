-- ============================================================
-- 61: Finance — Initial Creation Opening Balance Fix
-- ============================================================
-- ROOT CAUSE:
--   21c_fix_opening_balance_audit_actor.sql (L13-14) drops
--   trg_customer_init_balance + trg_supplier_init_balance
--   WITHOUT recreating them. It defines sync_* functions but
--   the trg_customer_opening_ledger / trg_supplier_opening_ledger
--   triggers (from 03_financial_infrastructure.sql L1480/L1506)
--   remain active and post to customer_ledger/supplier_ledger.
--   HOWEVER: they do NOT create GL (journal_entries) entries.
--   Net result for records created after 21c:
--     a) current_balance stays 0 on INSERT (init_balance trigger gone)
--     b) customer_ledger/supplier_ledger HAS opening entry ✅
--     c) journal_entries has NO GL debit/credit ❌ ← the real gap
--   And for very old records (before 03): possibly both missing.
--
-- THIS MIGRATION:
--   Part 1 — NOT RESTORED (see detailed explanation below)
--   Part 2 — Update sync_customer_opening_balance to also post GL
--   Part 3 — Update sync_supplier_opening_balance to also post GL
--   Part 4 — Historical backfill: GL for records missing journal entry
--
-- DEPENDENCY ANALYSIS:
--   ✅ Existing triggers trg_customer_opening_ledger (03 L1480) and
--      trg_supplier_opening_ledger (03 L1506) already handle subledger.
--      We replace their functions to ALSO post GL.
--   ✅ create_manual_journal_entry() — 03c_atomic_journal_entry.sql
--   ✅ chart_of_accounts: 1200(AR), 2100(AP), 3200(Retained Earnings)
--   ✅ suppliers table has NO created_by column (02_master_data L288-305).
--      21c fixed this using COALESCE(to_jsonb(NEW)->>'created_by', auth.uid())
--      We use the same safe pattern.
--   ✅ double-count prevention: initialize_balance NOT restored (see Part 1).
--      trg_cust_ledger_update_balance (03h) is authoritative for current_balance.
-- ============================================================


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  Part 1: initialize_balance triggers — NOT RESTORED       ║
-- ╚═══════════════════════════════════════════════════════════╝
--
-- INTENTIONAL DESIGN DECISION:
--   02_master_data.sql originally had trg_customer_init_balance
--   and trg_supplier_init_balance which called initialize_balance():
--     IF current_balance = 0 THEN current_balance = opening_balance
--
--   21c dropped these triggers with explicit comment:
--     "some environments had init_balance triggers enabled, which caused
--      current_balance duplication when opening_balance was also written
--      into the ledger and then re-applied by ledger triggers."
--
--   We do NOT restore them because:
--   03h_extreme_performance.sql added trg_cust_ledger_update_balance
--   which fires AFTER INSERT on customer_ledger and increments
--   customers.current_balance by the ledger entry amount.
--
--   If we restored initialize_balance:
--     BEFORE INSERT → current_balance = opening_balance (e.g. 1000)
--     AFTER INSERT ledger → current_balance += opening_balance = 2000 🔴
--
--   Without initialize_balance:
--     BEFORE INSERT → current_balance stays 0
--     AFTER INSERT ledger (debit 1000) → current_balance = 0 + 1000 = 1000 ✅
--
--   The ledger trigger (03h) IS the authoritative source of current_balance.



-- ╔═══════════════════════════════════════════════════════════╗
-- ║  Part 2: Upgrade sync_customer_opening_balance            ║
-- ║          to also post GL (journal_entries)                ║
-- ╚═══════════════════════════════════════════════════════════╝
--
-- EXISTING TRIGGER: trg_customer_opening_ledger (03 L1480)
--   fires AFTER INSERT on customers → inserts into customer_ledger ✅
--   but posts NO GL entry ❌
--
-- APPROACH: Replace the trigger function body to ALSO post GL.
-- The trigger itself (trg_customer_opening_ledger) stays attached.
-- The NOT EXISTS guard on the ledger prevents double-posting.
-- A separate NOT EXISTS guard on journal_entries prevents double GL.
--
-- ACCOUNTING:
--   Opening balance for a customer = money they OWE us (AR asset).
--   Dr 1200 (Accounts Receivable — control account)
--   Cr 3200 (Retained Earnings — equity offset for opening entries)
--
-- SAFE created_by resolution:
--   customers table HAS created_by column → NEW.created_by works.
--   suppliers table does NOT have created_by → use to_jsonb safe access.

CREATE OR REPLACE FUNCTION sync_customer_opening_balance()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lines  JSONB;
  v_je_id  UUID;
  v_actor  UUID;
BEGIN
  IF COALESCE(NEW.opening_balance, 0) <= 0 THEN
    RETURN NEW;
  END IF;

  -- Safe actor resolution (customers HAS created_by column)
  v_actor := COALESCE(NEW.created_by, auth.uid());

  -- ─── (أ) Subledger: customer_ledger ─────────────────────────
  -- Guard: idempotent — trg_customer_opening_ledger (03) may have
  -- already inserted this if the old trigger was active.
  IF NOT EXISTS (
    SELECT 1 FROM customer_ledger
    WHERE source_type = 'opening_balance'
      AND source_id   = NEW.id
  ) THEN
    INSERT INTO customer_ledger (
      customer_id, type, amount, source_type, source_id, description, created_by
    ) VALUES (
      NEW.id, 'debit', NEW.opening_balance,
      'opening_balance', NEW.id, 'رصيد افتتاحي', v_actor
    );
  END IF;

  -- ─── (ب) General Ledger: journal_entries ────────────────────
  -- Guard: only post GL if no GL entry exists for this customer's opening balance.
  -- Checks journal_entries with source_type='manual' and source_id=customer.id.
  IF NOT EXISTS (
    SELECT 1 FROM journal_entries
    WHERE source_type = 'manual'
      AND source_id   = NEW.id
  ) THEN
    v_lines := jsonb_build_array(
      jsonb_build_object(
        'account_code', '1200',
        'debit',        NEW.opening_balance,
        'credit',       0,
        'description',  'ذمم عملاء — رصيد افتتاحي: ' || NEW.name
      ),
      jsonb_build_object(
        'account_code', '3200',
        'debit',        0,
        'credit',       NEW.opening_balance,
        'description',  'أرباح محتجزة — مقابل رصيد افتتاحي عميل'
      )
    );

    SELECT create_manual_journal_entry(
      'رصيد افتتاحي للعميل: ' || NEW.name,
      CURRENT_DATE,
      'manual',
      NEW.id,
      v_lines,
      v_actor
    ) INTO v_je_id;
  END IF;

  RETURN NEW;
END;
$$;

-- The trigger trg_customer_opening_ledger is ALREADY attached (03 L1480).
-- We only replaced the function body — no need to recreate the trigger.
-- Drop the now-redundant separate GL trigger if it was created before this fix.
DROP TRIGGER IF EXISTS trg_customer_opening_journal ON customers;


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  Part 3: Upgrade sync_supplier_opening_balance            ║
-- ║          to also post GL (journal_entries)                ║
-- ╚═══════════════════════════════════════════════════════════╝
--
-- CRITICAL: suppliers table has NO created_by column!
-- (02_master_data.sql L288-305 — column not present)
-- 21c documented this: "suppliers rows do not expose a created_by column,
-- but the trigger functions referenced NEW.created_by directly."
-- Fix: use COALESCE((to_jsonb(NEW)->>'created_by')::uuid, auth.uid())
-- This safely returns NULL (not an error) if the field doesn't exist in NEW.
--
-- ACCOUNTING (reversed from customer):
--   Opening balance for a supplier = money WE OWE them (AP liability).
--   Dr 3200 (Retained Earnings — equity offset, historical opening)
--   Cr 2100 (Accounts Payable — control account, liability increases)

CREATE OR REPLACE FUNCTION sync_supplier_opening_balance()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lines  JSONB;
  v_je_id  UUID;
  v_actor  UUID;
BEGIN
  IF COALESCE(NEW.opening_balance, 0) <= 0 THEN
    RETURN NEW;
  END IF;

  -- Safe actor: suppliers has NO created_by column.
  -- to_jsonb(NEW)->>'created_by' returns NULL (not error) if field absent.
  v_actor := COALESCE(
    (to_jsonb(NEW) ->> 'created_by')::uuid,
    auth.uid()
  );

  -- ─── (أ) Subledger: supplier_ledger ─────────────────────────
  IF NOT EXISTS (
    SELECT 1 FROM supplier_ledger
    WHERE source_type = 'opening_balance'
      AND source_id   = NEW.id
  ) THEN
    INSERT INTO supplier_ledger (
      supplier_id, type, amount, source_type, source_id, description, created_by
    ) VALUES (
      NEW.id, 'credit', NEW.opening_balance,
      'opening_balance', NEW.id, 'رصيد افتتاحي', v_actor
    );
  END IF;

  -- ─── (ب) General Ledger ──────────────────────────────────────
  IF NOT EXISTS (
    SELECT 1 FROM journal_entries
    WHERE source_type = 'manual'
      AND source_id   = NEW.id
  ) THEN
    v_lines := jsonb_build_array(
      jsonb_build_object(
        'account_code', '3200',
        'debit',        NEW.opening_balance,
        'credit',       0,
        'description',  'أرباح محتجزة — مقابل رصيد افتتاحي مورد'
      ),
      jsonb_build_object(
        'account_code', '2100',
        'debit',        0,
        'credit',       NEW.opening_balance,
        'description',  'ذمم دائنة موردين — رصيد افتتاحي: ' || NEW.name
      )
    );

    SELECT create_manual_journal_entry(
      'رصيد افتتاحي للمورد: ' || NEW.name,
      CURRENT_DATE,
      'manual',
      NEW.id,
      v_lines,
      v_actor
    ) INTO v_je_id;
  END IF;

  RETURN NEW;
END;
$$;

-- The trigger trg_supplier_opening_ledger is ALREADY attached (03 L1506).
DROP TRIGGER IF EXISTS trg_supplier_opening_journal ON suppliers;


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  Part 4: Historical Backfill                              ║
-- ╚═══════════════════════════════════════════════════════════╝
--
-- REALITY CHECK on existing data:
--
--   Case A: Records created before migration 03 ran (very old)
--     → No customer_ledger entry, no journal_entries entry
--
--   Case B: Records created after 03 but before 21c
--     → trg_customer_opening_ledger (03) fired → customer_ledger HAS entry
--     → BUT: 03's sync function used ON CONFLICT DO NOTHING with UNIQUE constraint
--       which was later dropped (04). No GL entry existed then.
--       So: customer_ledger entry EXISTS, journal_entries MISSING.
--
--   Case C: Records created after 21c (the reported gap period)
--     → 21c updated sync functions to use NOT EXISTS instead of ON CONFLICT
--     → trigger still fires (trg_customer_opening_ledger) → ledger HAS entry
--     → Still no GL. Same as Case B.
--
--   Case A+B+C combined: The common missing piece is GL (journal_entries).
--   The ledger entries are mostly present (Cases B and C).
--
--   BACKFILL STRATEGY:
--     1. Fix missing ledger entries (for Case A records)
--     2. Fix missing GL entries (for ALL cases — the real gap)
--     3. current_balance repair is handled by trg_cust_ledger_update_balance
--        (03h) firing when we INSERT into customer_ledger.

-- ─── Customer backfill ────────────────────────────────────────
DO $$
DECLARE
  r       RECORD;
  v_lines JSONB;
  v_je_id UUID;
  v_actor UUID;
BEGIN
  FOR r IN
    SELECT c.id, c.name, c.opening_balance, c.created_by, c.created_at,
           EXISTS (
             SELECT 1 FROM customer_ledger cl
             WHERE cl.source_type = 'opening_balance' AND cl.customer_id = c.id
           ) AS has_ledger,
           EXISTS (
             SELECT 1 FROM journal_entries je
             WHERE je.source_type = 'manual' AND je.source_id = c.id
           ) AS has_gl
    FROM customers c
    WHERE c.opening_balance > 0
      AND NOT EXISTS (
        -- Only process records missing GL entry (the primary gap)
        SELECT 1 FROM journal_entries je
        WHERE je.source_type = 'manual' AND je.source_id = c.id
      )
    ORDER BY c.created_at ASC
  LOOP
    v_actor := COALESCE(r.created_by, auth.uid());

    -- Backfill ledger ONLY if also missing (Case A records)
    IF NOT r.has_ledger THEN
      INSERT INTO customer_ledger (
        customer_id, type, amount, source_type, source_id, description, created_by
      ) VALUES (
        r.id, 'debit', r.opening_balance,
        'opening_balance', r.id,
        'رصيد افتتاحي (ترحيل تاريخي)',
        v_actor
      );
      -- Note: trg_cust_ledger_update_balance (03h) fires here automatically
      -- and updates current_balance += opening_balance ✅
    END IF;

    -- Backfill GL for ALL cases (Cases A, B, C)
    v_lines := jsonb_build_array(
      jsonb_build_object(
        'account_code', '1200',
        'debit',        r.opening_balance,
        'credit',       0,
        'description',  'ذمم عملاء — رصيد افتتاحي (ترحيل تاريخي): ' || r.name
      ),
      jsonb_build_object(
        'account_code', '3200',
        'debit',        0,
        'credit',       r.opening_balance,
        'description',  'أرباح محتجزة — مقابل رصيد افتتاحي عميل (ترحيل تاريخي)'
      )
    );

    SELECT create_manual_journal_entry(
      'رصيد افتتاحي عميل — ترحيل تاريخي: ' || r.name,
      CURRENT_DATE,
      'manual',
      r.id,
      v_lines,
      v_actor
    ) INTO v_je_id;

    RAISE NOTICE '[backfill] Customer: % — ledger_existed: %, gl_posted: %',
      r.name, r.has_ledger, v_je_id;
  END LOOP;

  RAISE NOTICE '[backfill] Customer backfill complete.';
END;
$$;

-- Repair current_balance for customers where ledger was JUST inserted above.
-- Records that already had ledger entries (Cases B, C) will have correct
-- current_balance already (trg_cust_ledger_update_balance tracks it).
-- This UPDATE handles Case A records that had 0 balance before backfill.
UPDATE customers
SET current_balance = opening_balance
WHERE opening_balance > 0
  AND COALESCE(current_balance, 0) = 0
  AND NOT EXISTS (
    SELECT 1 FROM customer_ledger cl
    WHERE cl.customer_id = customers.id
      AND cl.source_type <> 'opening_balance'
  );

-- ─── Supplier backfill ────────────────────────────────────────
DO $$
DECLARE
  r       RECORD;
  v_lines JSONB;
  v_je_id UUID;
  v_actor UUID;
BEGIN
  FOR r IN
    SELECT s.id, s.name, s.opening_balance, s.created_at,
           -- suppliers has no created_by column → always NULL here
           EXISTS (
             SELECT 1 FROM supplier_ledger sl
             WHERE sl.source_type = 'opening_balance' AND sl.supplier_id = s.id
           ) AS has_ledger,
           EXISTS (
             SELECT 1 FROM journal_entries je
             WHERE je.source_type = 'manual' AND je.source_id = s.id
           ) AS has_gl
    FROM suppliers s
    WHERE s.opening_balance > 0
      AND NOT EXISTS (
        SELECT 1 FROM journal_entries je
        WHERE je.source_type = 'manual' AND je.source_id = s.id
      )
    ORDER BY s.created_at ASC
  LOOP
    -- suppliers has NO created_by column — use auth.uid() as actor
    v_actor := auth.uid();

    IF NOT r.has_ledger THEN
      INSERT INTO supplier_ledger (
        supplier_id, type, amount, source_type, source_id, description, created_by
      ) VALUES (
        r.id, 'credit', r.opening_balance,
        'opening_balance', r.id,
        'رصيد افتتاحي (ترحيل تاريخي)',
        v_actor
      );
      -- trg_supp_ledger_update_balance (03h) fires and updates current_balance ✅
    END IF;

    v_lines := jsonb_build_array(
      jsonb_build_object(
        'account_code', '3200',
        'debit',        r.opening_balance,
        'credit',       0,
        'description',  'أرباح محتجزة — مقابل رصيد افتتاحي مورد (ترحيل تاريخي)'
      ),
      jsonb_build_object(
        'account_code', '2100',
        'debit',        0,
        'credit',       r.opening_balance,
        'description',  'ذمم دائنة موردين — رصيد افتتاحي (ترحيل تاريخي): ' || r.name
      )
    );

    SELECT create_manual_journal_entry(
      'رصيد افتتاحي مورد — ترحيل تاريخي: ' || r.name,
      CURRENT_DATE,
      'manual',
      r.id,
      v_lines,
      v_actor
    ) INTO v_je_id;

    RAISE NOTICE '[backfill] Supplier: % — ledger_existed: %, gl_posted: %',
      r.name, r.has_ledger, v_je_id;
  END LOOP;

  RAISE NOTICE '[backfill] Supplier backfill complete.';
END;
$$;

UPDATE suppliers
SET current_balance = opening_balance
WHERE opening_balance > 0
  AND COALESCE(current_balance, 0) = 0
  AND NOT EXISTS (
    SELECT 1 FROM supplier_ledger sl
    WHERE sl.supplier_id = suppliers.id
      AND sl.source_type <> 'opening_balance'
  );


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  Verification Summary                                     ║
-- ╚═══════════════════════════════════════════════════════════╝
DO $$
DECLARE
  v_customers_without_ledger   INT;
  v_suppliers_without_ledger   INT;
  v_customers_without_gl       INT;
  v_suppliers_without_gl       INT;
  v_customers_balance_mismatch INT;
  v_suppliers_balance_mismatch INT;
BEGIN
  SELECT COUNT(*) INTO v_customers_without_ledger
  FROM customers
  WHERE opening_balance > 0
    AND NOT EXISTS (
      SELECT 1 FROM customer_ledger cl
      WHERE cl.source_type = 'opening_balance' AND cl.customer_id = customers.id
    );

  SELECT COUNT(*) INTO v_suppliers_without_ledger
  FROM suppliers
  WHERE opening_balance > 0
    AND NOT EXISTS (
      SELECT 1 FROM supplier_ledger sl
      WHERE sl.source_type = 'opening_balance' AND sl.supplier_id = suppliers.id
    );

  SELECT COUNT(*) INTO v_customers_without_gl
  FROM customers
  WHERE opening_balance > 0
    AND NOT EXISTS (
      SELECT 1 FROM journal_entries je
      WHERE je.source_type = 'manual' AND je.source_id = customers.id
    );

  SELECT COUNT(*) INTO v_suppliers_without_gl
  FROM suppliers
  WHERE opening_balance > 0
    AND NOT EXISTS (
      SELECT 1 FROM journal_entries je
      WHERE je.source_type = 'manual' AND je.source_id = suppliers.id
    );

  SELECT COUNT(*) INTO v_customers_balance_mismatch
  FROM customers
  WHERE opening_balance > 0
    AND opening_balance <> COALESCE(current_balance, 0)
    AND NOT EXISTS (
      SELECT 1 FROM customer_ledger cl
      WHERE cl.customer_id = customers.id AND cl.source_type <> 'opening_balance'
    );

  SELECT COUNT(*) INTO v_suppliers_balance_mismatch
  FROM suppliers
  WHERE opening_balance > 0
    AND opening_balance <> COALESCE(current_balance, 0)
    AND NOT EXISTS (
      SELECT 1 FROM supplier_ledger sl
      WHERE sl.supplier_id = suppliers.id AND sl.source_type <> 'opening_balance'
    );

  RAISE NOTICE '════════════════════════════════════════════════';
  RAISE NOTICE '[61_finance] Verification Results:';
  RAISE NOTICE '  Customers missing ledger entry : % (expect 0)', v_customers_without_ledger;
  RAISE NOTICE '  Suppliers missing ledger entry : % (expect 0)', v_suppliers_without_ledger;
  RAISE NOTICE '  Customers missing GL entry     : % (expect 0)', v_customers_without_gl;
  RAISE NOTICE '  Suppliers missing GL entry     : % (expect 0)', v_suppliers_without_gl;
  RAISE NOTICE '  Customers balance mismatch     : % (expect 0)', v_customers_balance_mismatch;
  RAISE NOTICE '  Suppliers balance mismatch     : % (expect 0)', v_suppliers_balance_mismatch;
  RAISE NOTICE '════════════════════════════════════════════════';

  IF v_customers_without_gl > 0 OR v_suppliers_without_gl > 0 THEN
    RAISE WARNING '[61_finance] ⚠️ Some records still missing GL entries — check manually!';
  ELSE
    RAISE NOTICE '[61_finance] ✅ All opening balance records have subledger + GL entries.';
  END IF;
END;
$$;
