-- One-off production maintenance script
-- Purpose: surgically remove the incorrectly confirmed receipt
--          REC-20260713-0411 and every operational/financial effect it created.
--
-- IMPORTANT
--   1. This is intentionally NOT a migration. Never add it to the migration chain.
--   2. It is safe-by-default: v_execute is FALSE. The first run performs only
--      locked preflight checks and commits no data changes.
--   3. Review the preflight notices, then change v_execute to TRUE and run the
--      complete file exactly once in the NEW-EDARA-SYS production SQL editor.
--   4. Any failed guard raises an exception and rolls back the entire operation.
--   5. Do not reset payment_receipt_seq. Gaps in receipt numbers are intentional.

BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $maintenance$
DECLARE
  -- Safety switch. Change only this value to TRUE after a successful dry run.
  v_execute CONSTANT BOOLEAN := FALSE;

  -- Immutable identity guards captured from production on 2026-07-13.
  v_receipt_id          CONSTANT UUID := '18fa297b-423d-4d5b-a753-73468cc8aa3c';
  v_receipt_number      CONSTANT TEXT := 'REC-20260713-0411';
  v_wrong_customer_id   CONSTANT UUID := '6f6a8650-896d-4038-863f-6293daf27683'; -- Bubbles
  v_custody_id          CONSTANT UUID := '3a974b07-e09c-4c71-9d1d-2b5830bdb01a';
  v_employee_user_id    CONSTANT UUID := 'de780710-d773-4450-8586-a75582741ad7'; -- كريم شيتوس
  v_employee_id         CONSTANT UUID := 'c806bf43-9afb-4756-9da6-39f73ee8976f';
  v_amount              CONSTANT NUMERIC(18,2) := 1000.00;
  v_created_at          CONSTANT TIMESTAMPTZ := '2026-07-13 14:07:59.59454+00';
  v_reviewed_at         CONSTANT TIMESTAMPTZ := '2026-07-13 14:27:15.753762+00';

  v_ledger_id           CONSTANT UUID := '6a6e6c62-b047-4451-bdca-dd3b8b513933';
  v_custody_tx_id       CONSTANT UUID := '35528cd3-4acb-4253-913f-a7af4eab5aaa';
  v_journal_id          CONSTANT UUID := '14ee2a07-8e2f-4e22-b725-841e8df097ae';
  v_journal_number      CONSTANT TEXT := 'JE-20260713-8523';
  v_notification_ids    CONSTANT UUID[] := ARRAY[
    'f2f9ebbe-8746-4b11-af6f-b7cbfcd88f86'::UUID,
    'e4808bda-d900-462d-989e-45e39ea26eb9'::UUID,
    '03cf2ef5-0e1b-4397-89ca-e1b9693e75c5'::UUID
  ];

  v_receipt             public.payment_receipts%ROWTYPE;
  v_custody             public.custody_accounts%ROWTYPE;
  v_custody_tx          public.custody_transactions%ROWTYPE;
  v_journal             public.journal_entries%ROWTYPE;
  v_count               BIGINT;
  v_known_count         BIGINT;
  v_affected            BIGINT;
  v_later_count         BIGINT;
  v_balance_mismatches  BIGINT;
  v_debit_total         NUMERIC;
  v_credit_total        NUMERIC;
  v_derived_balance     NUMERIC;
  v_expected_balance    NUMERIC;
  v_customer_balance    NUMERIC;
  v_expected_customer_balance NUMERIC;
  v_cached_customer_balance NUMERIC;
  v_snapshot            JSONB;
BEGIN
  -- Prevent another copy of this maintenance operation from running concurrently.
  PERFORM pg_advisory_xact_lock(
    hashtextextended('maintenance:delete-payment-receipt:' || v_receipt_id::TEXT, 0)
  );

  -- Lock the receipt first, matching the lock order used by confirm_payment_receipt().
  SELECT *
  INTO v_receipt
  FROM public.payment_receipts
  WHERE id = v_receipt_id
    AND number = v_receipt_number
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ABORT: target receipt % / % was not found',
      v_receipt_number, v_receipt_id;
  END IF;

  -- Exact receipt guards: abort rather than deleting a changed/reused record.
  IF v_receipt.customer_id IS DISTINCT FROM v_wrong_customer_id
     OR v_receipt.amount IS DISTINCT FROM v_amount
     OR v_receipt.payment_method IS DISTINCT FROM 'cash'
     OR v_receipt.status IS DISTINCT FROM 'confirmed'
     OR v_receipt.custody_id IS DISTINCT FROM v_custody_id
     OR v_receipt.vault_id IS NOT NULL
     OR v_receipt.sales_order_id IS NOT NULL
     OR v_receipt.proof_url IS NOT NULL
     OR v_receipt.created_by IS DISTINCT FROM v_employee_user_id
     OR v_receipt.collected_by IS DISTINCT FROM v_employee_user_id
     OR v_receipt.reviewed_by IS DISTINCT FROM v_employee_user_id
     OR v_receipt.created_at IS DISTINCT FROM v_created_at
     OR v_receipt.reviewed_at IS DISTINCT FROM v_reviewed_at
  THEN
    RAISE EXCEPTION 'ABORT: receipt identity/state no longer matches the reviewed production snapshot';
  END IF;

  -- Lock the custody account. All normal custody writers lock this row before insert.
  SELECT *
  INTO v_custody
  FROM public.custody_accounts
  WHERE id = v_custody_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ABORT: custody account % was not found', v_custody_id;
  END IF;

  IF NOT v_custody.is_active
     OR v_custody.employee_id IS DISTINCT FROM v_employee_user_id
  THEN
    RAISE EXCEPTION 'ABORT: custody ownership/state does not match the reviewed snapshot';
  END IF;

  -- Lock all custody history rows in deterministic order while validating/rebasing.
  PERFORM 1
  FROM public.custody_transactions
  WHERE custody_id = v_custody_id
  ORDER BY created_at, id
  FOR UPDATE;

  -- Verify that current_balance is fully explained by the immutable transaction ledger.
  SELECT COALESCE(SUM(
    CASE
      WHEN type IN ('load', 'collection') THEN amount
      WHEN type IN ('expense', 'settlement', 'return') THEN -amount
      ELSE NULL
    END
  ), 0)
  INTO v_derived_balance
  FROM public.custody_transactions
  WHERE custody_id = v_custody_id;

  IF v_derived_balance IS DISTINCT FROM v_custody.current_balance THEN
    RAISE EXCEPTION
      'ABORT: custody already has a balance drift (stored %, ledger-derived %)',
      v_custody.current_balance, v_derived_balance;
  END IF;

  -- Verify every historical balance_after before making a surgical rebase.
  SELECT COUNT(*)
  INTO v_balance_mismatches
  FROM (
    SELECT
      balance_after,
      SUM(
        CASE
          WHEN type IN ('load', 'collection') THEN amount
          WHEN type IN ('expense', 'settlement', 'return') THEN -amount
          ELSE NULL
        END
      ) OVER (ORDER BY created_at, id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS calculated_balance
    FROM public.custody_transactions
    WHERE custody_id = v_custody_id
  ) AS balances
  WHERE balance_after IS DISTINCT FROM calculated_balance;

  IF v_balance_mismatches <> 0 THEN
    RAISE EXCEPTION 'ABORT: % custody balance_after row(s) were already inconsistent',
      v_balance_mismatches;
  END IF;

  -- The exact collection movement must be the only custody movement for this receipt.
  SELECT *
  INTO v_custody_tx
  FROM public.custody_transactions
  WHERE id = v_custody_tx_id
    AND custody_id = v_custody_id
    AND reference_type = 'payment_receipt'
    AND reference_id = v_receipt_id
  FOR UPDATE;

  IF NOT FOUND
     OR v_custody_tx.type IS DISTINCT FROM 'collection'
     OR v_custody_tx.amount IS DISTINCT FROM v_amount
     OR v_custody_tx.created_at IS DISTINCT FROM v_reviewed_at
  THEN
    RAISE EXCEPTION 'ABORT: exact custody collection movement is missing or changed';
  END IF;

  SELECT COUNT(*)
  INTO v_count
  FROM public.custody_transactions
  WHERE reference_type = 'payment_receipt'
    AND reference_id = v_receipt_id;

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'ABORT: expected 1 custody movement for receipt, found %', v_count;
  END IF;

  -- Ordering must be unambiguous before reducing every later balance_after by 1,000.
  SELECT COUNT(*)
  INTO v_count
  FROM public.custody_transactions
  WHERE custody_id = v_custody_id
    AND created_at = v_custody_tx.created_at;

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'ABORT: custody transaction timestamp is not unique; manual ordering review required';
  END IF;

  SELECT COUNT(*)
  INTO v_later_count
  FROM public.custody_transactions
  WHERE custody_id = v_custody_id
    AND created_at > v_custody_tx.created_at;

  -- The receipt created exactly one unallocated advance credit and no invoice allocation.
  SELECT COUNT(*)
  INTO v_count
  FROM public.customer_ledger
  WHERE source_type = 'payment_receipt'
    AND source_id = v_receipt_id;

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'ABORT: expected 1 customer-ledger effect, found %', v_count;
  END IF;

  SELECT COUNT(*)
  INTO v_count
  FROM public.customer_ledger
  WHERE id = v_ledger_id
    AND customer_id = v_wrong_customer_id
    AND type = 'credit'
    AND amount = v_amount
    AND source_type = 'payment_receipt'
    AND source_id = v_receipt_id
    AND allocated_to IS NULL;

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'ABORT: expected unallocated advance-credit ledger row is missing or changed';
  END IF;

  SELECT COALESCE(SUM(CASE WHEN type = 'debit' THEN amount ELSE -amount END), 0)
  INTO v_customer_balance
  FROM public.customer_ledger
  WHERE customer_id = v_wrong_customer_id;

  v_expected_customer_balance := v_customer_balance + v_amount;

  -- customer_ledger has an AFTER DELETE trigger that updates customers.current_balance.
  -- Lock and verify the cache before relying on that trigger during the purge.
  SELECT current_balance
  INTO v_cached_customer_balance
  FROM public.customers
  WHERE id = v_wrong_customer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ABORT: wrong-customer row % was not found', v_wrong_customer_id;
  END IF;

  IF v_cached_customer_balance IS DISTINCT FROM v_customer_balance THEN
    RAISE EXCEPTION
      'ABORT: customer cached balance % differs from ledger-derived balance %',
      v_cached_customer_balance, v_customer_balance;
  END IF;

  -- The exact posted journal must be the only journal header for this receipt.
  SELECT *
  INTO v_journal
  FROM public.journal_entries
  WHERE id = v_journal_id
    AND number = v_journal_number
    AND source_type = 'payment'
    AND source_id = v_receipt_id
  FOR UPDATE;

  IF NOT FOUND
     OR v_journal.status IS DISTINCT FROM 'posted'
     OR v_journal.is_auto IS DISTINCT FROM TRUE
     OR v_journal.total_debit IS DISTINCT FROM v_amount
     OR v_journal.total_credit IS DISTINCT FROM v_amount
  THEN
    RAISE EXCEPTION 'ABORT: exact posted journal entry is missing or changed';
  END IF;

  SELECT COUNT(*)
  INTO v_count
  FROM public.journal_entries
  WHERE source_type = 'payment'
    AND source_id = v_receipt_id;

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'ABORT: expected 1 journal entry for receipt, found %', v_count;
  END IF;

  SELECT COUNT(*), COALESCE(SUM(jel.debit), 0), COALESCE(SUM(jel.credit), 0)
  INTO v_count, v_debit_total, v_credit_total
  FROM public.journal_entry_lines jel
  WHERE jel.entry_id = v_journal_id;

  IF v_count <> 2
     OR v_debit_total IS DISTINCT FROM v_amount
     OR v_credit_total IS DISTINCT FROM v_amount
  THEN
    RAISE EXCEPTION 'ABORT: journal lines are not the expected balanced two-line entry';
  END IF;

  SELECT COUNT(*) FILTER (
           WHERE coa.code = '1400' AND jel.debit = v_amount AND jel.credit = 0
         ),
         COUNT(*) FILTER (
           WHERE coa.code = '1200' AND jel.credit = v_amount AND jel.debit = 0
         )
  INTO v_count, v_known_count
  FROM public.journal_entry_lines jel
  JOIN public.chart_of_accounts coa ON coa.id = jel.account_id
  WHERE jel.entry_id = v_journal_id;

  IF v_count <> 1 OR v_known_count <> 1 THEN
    RAISE EXCEPTION 'ABORT: journal accounts are not DR 1400 / CR 1200 as reviewed';
  END IF;

  -- There must be no effects outside the reviewed dependency graph.
  SELECT COUNT(*) INTO v_count
  FROM public.vault_transactions
  WHERE reference_id = v_receipt_id;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'ABORT: unexpected vault transaction(s) found: %', v_count;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.activities
  WHERE collection_id = v_receipt_id;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'ABORT: unexpected linked activity row(s) found: %', v_count;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.hr_commission_records
  WHERE source_id = v_receipt_id;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'ABORT: unexpected commission record(s) found: %', v_count;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.notification_alert_state
  WHERE entity_id = v_receipt_id;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'ABORT: unexpected notification alert state row(s) found: %', v_count;
  END IF;

  SELECT COUNT(*), COUNT(*) FILTER (WHERE id = ANY(v_notification_ids))
  INTO v_count, v_known_count
  FROM public.notifications
  WHERE entity_type = 'payment_receipt'
    AND entity_id = v_receipt_id;

  IF v_count <> 3 OR v_known_count <> 3 THEN
    RAISE EXCEPTION
      'ABORT: receipt notifications changed (total %, known %); re-review dependencies',
      v_count, v_known_count;
  END IF;

  v_expected_balance := v_custody.current_balance - v_amount;
  IF v_expected_balance < 0 THEN
    RAISE EXCEPTION 'ABORT: removal would make custody balance negative (%)', v_expected_balance;
  END IF;

  RAISE NOTICE 'PREFLIGHT OK: receipt %, amount %, customer %, custody %',
    v_receipt_number, v_amount, v_wrong_customer_id, v_custody_id;
  RAISE NOTICE 'PREFLIGHT OK: custody balance % -> %, later rows to rebase: %',
    v_custody.current_balance, v_expected_balance, v_later_count;
  RAISE NOTICE 'PREFLIGHT OK: customer ledger balance % -> %',
    v_customer_balance, v_expected_customer_balance;

  IF NOT v_execute THEN
    RAISE NOTICE 'DRY RUN ONLY: no rows were changed. Set v_execute := TRUE after review.';
    RETURN;
  END IF;

  -- Preserve a non-operational audit snapshot. This record does not feed balances,
  -- journals, reports, targets, or receipt UI, and deliberately survives the purge.
  SELECT jsonb_build_object(
    'receipt', to_jsonb(v_receipt),
    'custody_account_before', to_jsonb(v_custody),
    'custody_transaction', to_jsonb(v_custody_tx),
    'customer_ledger', (
      SELECT COALESCE(jsonb_agg(to_jsonb(cl) ORDER BY cl.created_at, cl.id), '[]'::JSONB)
      FROM public.customer_ledger cl
      WHERE cl.source_type = 'payment_receipt' AND cl.source_id = v_receipt_id
    ),
    'journal_entry', to_jsonb(v_journal),
    'journal_lines', (
      SELECT COALESCE(jsonb_agg(to_jsonb(jel) ORDER BY jel.id), '[]'::JSONB)
      FROM public.journal_entry_lines jel
      WHERE jel.entry_id = v_journal_id
    ),
    'notifications', (
      SELECT COALESCE(jsonb_agg(to_jsonb(n) ORDER BY n.created_at, n.id), '[]'::JSONB)
      FROM public.notifications n
      WHERE n.entity_type = 'payment_receipt' AND n.entity_id = v_receipt_id
    ),
    'notification_delivery_log', (
      SELECT COALESCE(jsonb_agg(to_jsonb(ndl) ORDER BY ndl.processed_at, ndl.id), '[]'::JSONB)
      FROM public.notification_delivery_log ndl
      WHERE ndl.notification_id = ANY(v_notification_ids)
    )
  )
  INTO v_snapshot;

  INSERT INTO public.audit_logs (
    user_id, action, entity_type, entity_id, old_data, new_data, user_agent
  ) VALUES (
    NULL,
    'hard_delete_wrong_customer_receipt',
    'payment_receipt_maintenance',
    v_receipt_id,
    v_snapshot,
    jsonb_build_object(
      'reason', 'Receipt was confirmed for the wrong customer; exact operational effects purged',
      'receipt_number', v_receipt_number,
      'custody_balance_before', v_custody.current_balance,
      'custody_balance_after', v_expected_balance,
      'customer_balance_before', v_customer_balance,
      'customer_balance_after', v_expected_customer_balance,
      'executed_at', clock_timestamp()
    ),
    'one-off SQL maintenance script'
  );

  -- Notification delivery rows are removed by their ON DELETE CASCADE FK.
  DELETE FROM public.notifications
  WHERE entity_type = 'payment_receipt'
    AND entity_id = v_receipt_id
    AND id = ANY(v_notification_ids);
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 3 THEN
    RAISE EXCEPTION 'ABORT: deleted % notifications instead of 3', v_affected;
  END IF;

  -- Journal lines are removed by journal_entry_lines_entry_id_fkey ON DELETE CASCADE.
  DELETE FROM public.journal_entries
  WHERE id = v_journal_id
    AND source_type = 'payment'
    AND source_id = v_receipt_id;
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 1 THEN
    RAISE EXCEPTION 'ABORT: deleted % journal headers instead of 1', v_affected;
  END IF;

  DELETE FROM public.customer_ledger
  WHERE id = v_ledger_id
    AND source_type = 'payment_receipt'
    AND source_id = v_receipt_id
    AND allocated_to IS NULL;
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 1 THEN
    RAISE EXCEPTION 'ABORT: deleted % customer-ledger rows instead of 1', v_affected;
  END IF;

  DELETE FROM public.custody_transactions
  WHERE id = v_custody_tx_id
    AND custody_id = v_custody_id
    AND reference_type = 'payment_receipt'
    AND reference_id = v_receipt_id;
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 1 THEN
    RAISE EXCEPTION 'ABORT: deleted % custody movements instead of 1', v_affected;
  END IF;

  -- Rebase every later stored running balance by the removed collection amount.
  UPDATE public.custody_transactions
  SET balance_after = balance_after - v_amount
  WHERE custody_id = v_custody_id
    AND created_at > v_custody_tx.created_at;
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> v_later_count THEN
    RAISE EXCEPTION 'ABORT: rebased % later rows; expected %', v_affected, v_later_count;
  END IF;

  UPDATE public.custody_accounts
  SET current_balance = v_expected_balance
  WHERE id = v_custody_id
    AND current_balance = v_custody.current_balance;
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 1 THEN
    RAISE EXCEPTION 'ABORT: custody current_balance compare-and-set failed';
  END IF;

  DELETE FROM public.payment_receipts
  WHERE id = v_receipt_id
    AND number = v_receipt_number;
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 1 THEN
    RAISE EXCEPTION 'ABORT: deleted % receipt headers instead of 1', v_affected;
  END IF;

  -- Deletion/status-away-from-confirmed has no automatic target trigger in the
  -- current schema, so explicitly recalculate any collection target that covered
  -- the original event date. Currently there are no matching active targets.
  PERFORM public.recalculate_targets_for_employee(
    v_employee_id,
    ARRAY['collection']::TEXT[],
    CURRENT_DATE,
    v_created_at::DATE
  );

  -- Post-mutation invariants. Any failure rolls the whole transaction back.
  SELECT COUNT(*) INTO v_count
  FROM public.payment_receipts
  WHERE id = v_receipt_id OR number = v_receipt_number;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'ABORT: receipt still exists after delete';
  END IF;

  SELECT
    (SELECT COUNT(*) FROM public.customer_ledger
     WHERE source_type = 'payment_receipt' AND source_id = v_receipt_id)
    +
    (SELECT COUNT(*) FROM public.custody_transactions
     WHERE reference_type = 'payment_receipt' AND reference_id = v_receipt_id)
    +
    (SELECT COUNT(*) FROM public.vault_transactions
     WHERE reference_id = v_receipt_id)
    +
    (SELECT COUNT(*) FROM public.journal_entries
     WHERE source_id = v_receipt_id)
    +
    (SELECT COUNT(*) FROM public.notifications
     WHERE entity_id = v_receipt_id)
    +
    (SELECT COUNT(*) FROM public.activities
     WHERE collection_id = v_receipt_id)
  INTO v_count;

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'ABORT: % operational source reference(s) remain after purge', v_count;
  END IF;

  SELECT current_balance
  INTO v_derived_balance
  FROM public.custody_accounts
  WHERE id = v_custody_id;

  IF v_derived_balance IS DISTINCT FROM v_expected_balance THEN
    RAISE EXCEPTION 'ABORT: custody stored balance is %, expected %',
      v_derived_balance, v_expected_balance;
  END IF;

  SELECT COALESCE(SUM(
    CASE
      WHEN type IN ('load', 'collection') THEN amount
      WHEN type IN ('expense', 'settlement', 'return') THEN -amount
      ELSE NULL
    END
  ), 0)
  INTO v_derived_balance
  FROM public.custody_transactions
  WHERE custody_id = v_custody_id;

  IF v_derived_balance IS DISTINCT FROM v_expected_balance THEN
    RAISE EXCEPTION 'ABORT: custody ledger-derived balance is %, expected %',
      v_derived_balance, v_expected_balance;
  END IF;

  SELECT COUNT(*)
  INTO v_balance_mismatches
  FROM (
    SELECT
      balance_after,
      SUM(
        CASE
          WHEN type IN ('load', 'collection') THEN amount
          WHEN type IN ('expense', 'settlement', 'return') THEN -amount
          ELSE NULL
        END
      ) OVER (ORDER BY created_at, id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS calculated_balance
    FROM public.custody_transactions
    WHERE custody_id = v_custody_id
  ) AS balances
  WHERE balance_after IS DISTINCT FROM calculated_balance;

  IF v_balance_mismatches <> 0 THEN
    RAISE EXCEPTION 'ABORT: % custody balance_after row(s) became inconsistent',
      v_balance_mismatches;
  END IF;

  SELECT COALESCE(SUM(CASE WHEN type = 'debit' THEN amount ELSE -amount END), 0)
  INTO v_customer_balance
  FROM public.customer_ledger
  WHERE customer_id = v_wrong_customer_id;

  IF v_customer_balance IS DISTINCT FROM v_expected_customer_balance THEN
    RAISE EXCEPTION 'ABORT: customer balance is %, expected %',
      v_customer_balance, v_expected_customer_balance;
  END IF;

  SELECT current_balance
  INTO v_cached_customer_balance
  FROM public.customers
  WHERE id = v_wrong_customer_id;

  IF v_cached_customer_balance IS DISTINCT FROM v_expected_customer_balance THEN
    RAISE EXCEPTION 'ABORT: customer cached balance is %, expected %',
      v_cached_customer_balance, v_expected_customer_balance;
  END IF;

  RAISE NOTICE 'EXECUTION OK: receipt % and all reviewed effects were removed',
    v_receipt_number;
  RAISE NOTICE 'EXECUTION OK: custody balance is %, customer balance is %',
    v_expected_balance, v_expected_customer_balance;
END;
$maintenance$;

COMMIT;

-- Read-only result summary. With v_execute=FALSE it reports dry_run_not_deleted.
-- With v_execute=TRUE it must report deleted_and_verified and zero references.
SELECT
  CASE
    WHEN EXISTS (
      SELECT 1 FROM public.payment_receipts
      WHERE id = '18fa297b-423d-4d5b-a753-73468cc8aa3c'::UUID
         OR number = 'REC-20260713-0411'
    ) THEN 'dry_run_not_deleted'
    ELSE 'deleted_and_verified'
  END AS operation_state,
  (
    SELECT current_balance
    FROM public.custody_accounts
    WHERE id = '3a974b07-e09c-4c71-9d1d-2b5830bdb01a'::UUID
  ) AS custody_current_balance,
  (
    SELECT COALESCE(SUM(CASE WHEN type = 'debit' THEN amount ELSE -amount END), 0)
    FROM public.customer_ledger
    WHERE customer_id = '6f6a8650-896d-4038-863f-6293daf27683'::UUID
  ) AS wrong_customer_ledger_balance,
  (
    SELECT COUNT(*) FROM public.audit_logs
    WHERE action = 'hard_delete_wrong_customer_receipt'
      AND entity_id = '18fa297b-423d-4d5b-a753-73468cc8aa3c'::UUID
  ) AS retained_maintenance_audit_rows;


