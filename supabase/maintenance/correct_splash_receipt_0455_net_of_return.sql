-- One-off production maintenance script
-- Purpose: correct REC-20260730-0455 from EGP 550 to the actual EGP 400
--          received in the InstaPay vault, and allocate the customer's existing
--          EGP 150 sales-return credit to SO-20260729-0389.
--
-- Business truth
--   Invoice SO-20260729-0389       550
--   Less return credit              150  (SR-20260730-0001)
--   Actual InstaPay receipt         400  (REC-20260730-0455)
--   Customer balance                  0
--
-- IMPORTANT
--   1. This is intentionally NOT a migration. Never add it to the migration chain.
--   2. Executed successfully once on 2026-07-30. v_execute was reset to FALSE
--      immediately afterward; the audit guard also prevents any rerun.
--   3. Any changed identity, amount, allocation, journal, vault sequence, custody,
--      stock, or balance guard aborts and rolls back the entire transaction.
--   4. The return and stock rows are validated but never modified.
--   5. Ahmed El-Ebshehy's custody is validated but never modified.

BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $maintenance$
DECLARE
  -- Safety switch. Keep FALSE until explicit approval after review.
  v_execute CONSTANT BOOLEAN := FALSE;

  v_customer_id       CONSTANT UUID := 'cf7fbbb5-f7dd-46d7-b56c-4be78377ad0c'; -- CUS-01215 Splash
  v_order_id          CONSTANT UUID := '018734d2-0826-4284-b3d8-a1781ed3b5ad'; -- SO-20260729-0389
  v_order_number      CONSTANT TEXT := 'SO-20260729-0389';
  v_order_debit_id    CONSTANT UUID := '3c5a7c98-5413-42e8-ab40-48a95a0e83a0';

  v_return_id         CONSTANT UUID := '52e1db6a-a657-4d80-911b-2757dce15317'; -- SR-20260730-0001
  v_return_number     CONSTANT TEXT := 'SR-20260730-0001';
  v_return_credit_id  CONSTANT UUID := 'c91d3353-235f-4deb-8bb1-137a7fd1091e';

  v_receipt_id        CONSTANT UUID := '030b6485-66c4-42f5-ac66-175d22bd3cea'; -- REC-20260730-0455
  v_receipt_number    CONSTANT TEXT := 'REC-20260730-0455';
  v_receipt_ledger_id CONSTANT UUID := 'be75dda4-7596-457a-af67-74ff7d562c3b';
  v_receipt_created_at  CONSTANT TIMESTAMPTZ := '2026-07-30 09:55:18.466815+00';
  v_receipt_reviewed_at CONSTANT TIMESTAMPTZ := '2026-07-30 09:57:19.186851+00';

  v_vault_id          CONSTANT UUID := '0d487441-0313-4a7e-9fed-f3b9421e94e5'; -- InstaPay
  v_vault_tx_id       CONSTANT UUID := 'c12aba91-f9ba-4e74-a60d-abfa88954814';

  v_journal_id        CONSTANT UUID := '37564442-4227-469b-9fb5-35764e571693';
  v_journal_number    CONSTANT TEXT := 'JE-20260730-8650';
  v_journal_1130_id   CONSTANT UUID := 'ea31af35-a50e-4655-bd7d-1d1825246f79';
  v_journal_1200_id   CONSTANT UUID := 'b3a5442f-d5a4-46b3-8b77-f369e16104d6';

  v_collector_user_id CONSTANT UUID := '9a158123-f511-4536-be8c-27d605741f5f'; -- Ahmed El-Ebshehy
  v_collector_emp_id  CONSTANT UUID := '4fe586b1-d591-4621-b3af-54596455ab06';
  v_reviewer_user_id  CONSTANT UUID := '410c04bc-b571-49f8-89cf-8b78b7305fd6';
  v_custody_id        CONSTANT UUID := '4689bfe4-97b0-42bc-bca3-f4b139911fa6'; -- protected, no mutation

  v_old_amount        CONSTANT NUMERIC(14,2) := 550.00;
  v_actual_amount     CONSTANT NUMERIC(14,2) := 400.00;
  v_return_amount     CONSTANT NUMERIC(14,2) := 150.00;
  v_difference        CONSTANT NUMERIC(14,2) := 150.00;

  v_notification_ids CONSTANT UUID[] := ARRAY[
    '1a4fdd91-6861-496d-8d0d-c812d5c3e6b6'::UUID,
    'f68bd678-2f96-4454-88e8-676e5d1b28be'::UUID
  ];

  v_receipt       public.payment_receipts%ROWTYPE;
  v_order         public.sales_orders%ROWTYPE;
  v_return        public.sales_returns%ROWTYPE;
  v_vault         public.vaults%ROWTYPE;
  v_vault_tx      public.vault_transactions%ROWTYPE;
  v_journal       public.journal_entries%ROWTYPE;
  v_custody       public.custody_accounts%ROWTYPE;
  v_count         BIGINT;
  v_known_count   BIGINT;
  v_affected      BIGINT;
  v_later_count   BIGINT;
  v_chain_errors  BIGINT;
  v_expected_vault_balance NUMERIC(14,2);
  v_customer_balance       NUMERIC(14,2);
  v_cached_customer_balance NUMERIC(14,2);
  v_latest_vault_balance   NUMERIC(14,2);
  v_custody_balance_before NUMERIC(14,2);
  v_fact_treasury_before   NUMERIC(14,2);
  v_fact_ar_before         NUMERIC(14,2);
  v_fact_1130_debit_before NUMERIC(14,2);
  v_fact_1130_credit_before NUMERIC(14,2);
  v_fact_1200_debit_before NUMERIC(14,2);
  v_fact_1200_credit_before NUMERIC(14,2);
  v_snapshot      JSONB;
BEGIN
  IF v_old_amount - v_actual_amount IS DISTINCT FROM v_difference
     OR v_actual_amount + v_return_amount IS DISTINCT FROM v_old_amount
  THEN
    RAISE EXCEPTION 'ABORT: arithmetic constants are inconsistent';
  END IF;

  -- Only one copy of this exact maintenance operation may run.
  PERFORM pg_advisory_xact_lock(
    hashtextextended('maintenance:correct-splash-receipt:' || v_receipt_id::TEXT, 0)
  );

  -- Prevent accidental rerun after a successful execution.
  SELECT COUNT(*)
  INTO v_count
  FROM public.audit_logs
  WHERE action = 'correct_splash_receipt_net_of_return'
    AND entity_type = 'payment_receipt_maintenance'
    AND entity_id = v_receipt_id;

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'ABORT: this correction already has % audit record(s)', v_count;
  END IF;

  -- Lock source documents before their financial effects.
  SELECT * INTO v_receipt
  FROM public.payment_receipts
  WHERE id = v_receipt_id AND number = v_receipt_number
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ABORT: target receipt was not found';
  END IF;

  IF v_receipt.amount IS DISTINCT FROM v_old_amount
     OR v_receipt.status IS DISTINCT FROM 'confirmed'
     OR v_receipt.payment_method IS DISTINCT FROM 'instapay'
     OR v_receipt.customer_id IS DISTINCT FROM v_customer_id
     OR v_receipt.sales_order_id IS DISTINCT FROM v_order_id
     OR v_receipt.vault_id IS DISTINCT FROM v_vault_id
     OR v_receipt.custody_id IS NOT NULL
     OR v_receipt.collected_by IS DISTINCT FROM v_collector_user_id
     OR v_receipt.reviewed_by IS DISTINCT FROM v_reviewer_user_id
     OR v_receipt.created_at IS DISTINCT FROM v_receipt_created_at
     OR v_receipt.reviewed_at IS DISTINCT FROM v_receipt_reviewed_at
  THEN
    RAISE EXCEPTION 'ABORT: receipt identity/state no longer matches the reviewed snapshot';
  END IF;

  SELECT * INTO v_order
  FROM public.sales_orders
  WHERE id = v_order_id AND order_number = v_order_number
  FOR UPDATE;

  IF NOT FOUND
     OR v_order.customer_id IS DISTINCT FROM v_customer_id
     OR v_order.status IS DISTINCT FROM 'completed'
     OR v_order.total_amount IS DISTINCT FROM v_old_amount
     OR v_order.paid_amount IS DISTINCT FROM v_old_amount
     OR COALESCE(v_order.returned_amount, 0) IS DISTINCT FROM 0::NUMERIC
     OR v_order.payment_terms IS DISTINCT FROM 'cash'
     OR v_order.payment_method IS DISTINCT FROM 'instapay'
  THEN
    RAISE EXCEPTION 'ABORT: invoice identity/settlement state changed';
  END IF;

  SELECT * INTO v_return
  FROM public.sales_returns
  WHERE id = v_return_id AND return_number = v_return_number
  FOR UPDATE;

  IF NOT FOUND
     OR v_return.customer_id IS DISTINCT FROM v_customer_id
     OR v_return.status IS DISTINCT FROM 'confirmed'
     OR v_return.total_amount IS DISTINCT FROM v_return_amount
  THEN
    RAISE EXCEPTION 'ABORT: sales return identity/state changed';
  END IF;

  -- The return's operational result is correct and must stay untouched.
  SELECT
    (SELECT COUNT(*) FROM public.sales_return_items WHERE return_id = v_return_id),
    (SELECT COUNT(*) FROM public.stock_movements
     WHERE reference_type = 'sales_return' AND reference_id = v_return_id),
    (SELECT COUNT(*) FROM public.journal_entries
     WHERE source_type = 'sales_return' AND source_id = v_return_id)
  INTO v_count, v_known_count, v_affected;

  IF v_count <> 1 OR v_known_count <> 1 OR v_affected <> 1 THEN
    RAISE EXCEPTION
      'ABORT: return effects changed (items %, stock %, journals %)',
      v_count, v_known_count, v_affected;
  END IF;

  -- No money was physically refunded from a custody or vault for this return.
  SELECT
    (SELECT COUNT(*) FROM public.custody_transactions
     WHERE reference_type = 'sales_return' AND reference_id = v_return_id)
    +
    (SELECT COUNT(*) FROM public.vault_transactions
     WHERE reference_type = 'sales_return' AND reference_id = v_return_id)
  INTO v_count;

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'ABORT: a cash refund movement now exists for the return';
  END IF;

  -- Protect Ahmed El-Ebshehy's custody: lock it and take an immutable within-tx snapshot.
  SELECT * INTO v_custody
  FROM public.custody_accounts
  WHERE id = v_custody_id
    AND employee_id = v_collector_user_id
  FOR UPDATE;

  IF NOT FOUND OR NOT v_custody.is_active THEN
    RAISE EXCEPTION 'ABORT: protected custody identity/state changed';
  END IF;
  v_custody_balance_before := v_custody.current_balance;

  -- Lock and validate the customer subledger rows.
  PERFORM 1
  FROM public.customer_ledger
  WHERE customer_id = v_customer_id
  ORDER BY created_at, id
  FOR UPDATE;

  -- Neither source may have been split into additional ledger rows since review.
  SELECT COUNT(*), COALESCE(SUM(amount), 0)
  INTO v_count, v_customer_balance
  FROM public.customer_ledger
  WHERE customer_id = v_customer_id
    AND source_type = 'payment_receipt'
    AND source_id = v_receipt_id;
  IF v_count <> 1 OR v_customer_balance IS DISTINCT FROM v_old_amount THEN
    RAISE EXCEPTION
      'ABORT: receipt ledger source changed (rows %, total %)',
      v_count, v_customer_balance;
  END IF;

  SELECT COUNT(*), COALESCE(SUM(amount), 0)
  INTO v_count, v_customer_balance
  FROM public.customer_ledger
  WHERE customer_id = v_customer_id
    AND source_type = 'sales_return'
    AND source_id = v_return_id;
  IF v_count <> 1 OR v_customer_balance IS DISTINCT FROM v_return_amount THEN
    RAISE EXCEPTION
      'ABORT: return ledger source changed (rows %, total %)',
      v_count, v_customer_balance;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.customer_ledger
  WHERE id = v_order_debit_id
    AND customer_id = v_customer_id
    AND type = 'debit'
    AND amount = v_old_amount
    AND source_type = 'sales_order'
    AND source_id = v_order_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'ABORT: exact invoice debit row is missing or changed';
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.customer_ledger
  WHERE id = v_receipt_ledger_id
    AND customer_id = v_customer_id
    AND type = 'credit'
    AND amount = v_old_amount
    AND source_type = 'payment_receipt'
    AND source_id = v_receipt_id
    AND allocated_to = v_order_debit_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'ABORT: exact receipt credit row is missing or changed';
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.customer_ledger
  WHERE id = v_return_credit_id
    AND customer_id = v_customer_id
    AND type = 'credit'
    AND amount = v_return_amount
    AND source_type = 'sales_return'
    AND source_id = v_return_id
    AND allocated_to IS NULL;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'ABORT: exact unallocated return credit is missing or changed';
  END IF;

  SELECT COUNT(*), COALESCE(SUM(amount), 0)
  INTO v_count, v_customer_balance
  FROM public.customer_ledger
  WHERE customer_id = v_customer_id
    AND type = 'credit'
    AND allocated_to = v_order_debit_id;
  IF v_count <> 1 OR v_customer_balance IS DISTINCT FROM v_old_amount THEN
    RAISE EXCEPTION
      'ABORT: invoice allocations changed (rows %, amount %)',
      v_count, v_customer_balance;
  END IF;

  SELECT COALESCE(SUM(CASE WHEN type = 'debit' THEN amount ELSE -amount END), 0)
  INTO v_customer_balance
  FROM public.customer_ledger
  WHERE customer_id = v_customer_id;

  SELECT current_balance INTO v_cached_customer_balance
  FROM public.customers
  WHERE id = v_customer_id
  FOR UPDATE;

  IF NOT FOUND
     OR v_customer_balance IS DISTINCT FROM -v_difference
     OR v_cached_customer_balance IS DISTINCT FROM v_customer_balance
  THEN
    RAISE EXCEPTION
      'ABORT: customer balance is not the reviewed -150 (ledger %, cached %)',
      v_customer_balance, v_cached_customer_balance;
  END IF;

  -- Lock the InstaPay vault and its transaction history in deterministic order.
  SELECT * INTO v_vault
  FROM public.vaults
  WHERE id = v_vault_id AND type = 'mobile_wallet'
  FOR UPDATE;

  IF NOT FOUND OR NOT v_vault.is_active THEN
    RAISE EXCEPTION 'ABORT: InstaPay vault identity/state changed';
  END IF;

  PERFORM 1
  FROM public.vault_transactions
  WHERE vault_id = v_vault_id
  ORDER BY created_at, id
  FOR UPDATE;

  SELECT * INTO v_vault_tx
  FROM public.vault_transactions
  WHERE id = v_vault_tx_id
    AND vault_id = v_vault_id
    AND reference_type = 'payment_receipt'
    AND reference_id = v_receipt_id
  FOR UPDATE;

  IF NOT FOUND
     OR v_vault_tx.type IS DISTINCT FROM 'collection'
     OR v_vault_tx.amount IS DISTINCT FROM v_old_amount
     OR v_vault_tx.created_at IS DISTINCT FROM v_receipt_reviewed_at
  THEN
    RAISE EXCEPTION 'ABORT: exact InstaPay collection movement is missing or changed';
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.vault_transactions
  WHERE reference_type = 'payment_receipt' AND reference_id = v_receipt_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'ABORT: expected one vault movement for receipt, found %', v_count;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.vault_transactions
  WHERE vault_id = v_vault_id AND created_at = v_vault_tx.created_at;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'ABORT: target vault timestamp is not unique';
  END IF;

  -- Validate every balance transition from the target collection onward.
  SELECT COUNT(*)
  INTO v_chain_errors
  FROM (
    SELECT
      id,
      created_at,
      type,
      amount,
      balance_after,
      LAG(balance_after) OVER (ORDER BY created_at, id) AS previous_balance
    FROM public.vault_transactions
    WHERE vault_id = v_vault_id
  ) AS chain
  WHERE (created_at, id) >= (v_vault_tx.created_at, v_vault_tx.id)
    AND balance_after IS DISTINCT FROM
      previous_balance + CASE
        WHEN type IN (
          'deposit', 'transfer_in', 'collection', 'custody_return',
          'opening_balance', 'vendor_refund'
        ) THEN amount
        WHEN type IN (
          'withdrawal', 'transfer_out', 'expense', 'custody_load',
          'vendor_payment', 'payroll_payment'
        ) THEN -amount
        ELSE NULL
      END;

  IF v_chain_errors <> 0 THEN
    RAISE EXCEPTION 'ABORT: % vault running-balance transition(s) are inconsistent', v_chain_errors;
  END IF;

  SELECT balance_after
  INTO v_latest_vault_balance
  FROM public.vault_transactions
  WHERE vault_id = v_vault_id
  ORDER BY created_at DESC, id DESC
  LIMIT 1;

  IF v_latest_vault_balance IS DISTINCT FROM v_vault.current_balance THEN
    RAISE EXCEPTION
      'ABORT: vault current balance % differs from latest running balance %',
      v_vault.current_balance, v_latest_vault_balance;
  END IF;

  SELECT COUNT(*) INTO v_later_count
  FROM public.vault_transactions
  WHERE vault_id = v_vault_id
    AND (created_at, id) > (v_vault_tx.created_at, v_vault_tx.id);

  v_expected_vault_balance := v_vault.current_balance - v_difference;
  IF v_expected_vault_balance < 0 THEN
    RAISE EXCEPTION 'ABORT: correction would make the InstaPay vault negative';
  END IF;

  -- Validate the exact posted payment journal.
  SELECT * INTO v_journal
  FROM public.journal_entries
  WHERE id = v_journal_id
    AND number = v_journal_number
    AND source_type = 'payment'
    AND source_id = v_receipt_id
  FOR UPDATE;

  IF NOT FOUND
     OR v_journal.status IS DISTINCT FROM 'posted'
     OR v_journal.total_debit IS DISTINCT FROM v_old_amount
     OR v_journal.total_credit IS DISTINCT FROM v_old_amount
  THEN
    RAISE EXCEPTION 'ABORT: receipt journal header is missing or changed';
  END IF;

  SELECT
    COUNT(*),
    COUNT(*) FILTER (
      WHERE jel.id = v_journal_1130_id AND coa.code = '1130'
        AND jel.debit = v_old_amount AND jel.credit = 0
    ),
    COUNT(*) FILTER (
      WHERE jel.id = v_journal_1200_id AND coa.code = '1200'
        AND jel.debit = 0 AND jel.credit = v_old_amount
    )
  INTO v_count, v_known_count, v_affected
  FROM public.journal_entry_lines jel
  JOIN public.chart_of_accounts coa ON coa.id = jel.account_id
  WHERE jel.entry_id = v_journal_id;

  IF v_count <> 2 OR v_known_count <> 1 OR v_affected <> 1 THEN
    RAISE EXCEPTION 'ABORT: receipt journal lines are not the reviewed DR 1130 / CR 1200 pair';
  END IF;

  -- Only the two receipt notifications contain the overstated received amount.
  SELECT COUNT(*), COUNT(*) FILTER (WHERE id = ANY(v_notification_ids))
  INTO v_count, v_known_count
  FROM public.notifications
  WHERE entity_type = 'payment_receipt' AND entity_id = v_receipt_id;

  IF v_count <> 2 OR v_known_count <> 2 THEN
    RAISE EXCEPTION
      'ABORT: receipt notifications changed (total %, known %)',
      v_count, v_known_count;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.notifications
  WHERE id = ANY(v_notification_ids)
    AND body LIKE '%550.00%';
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'ABORT: expected two receipt notification bodies containing 550.00';
  END IF;

  -- The operational correction also changes three derived analytics facts.
  -- Capture their reviewed state so they can be rebuilt and delta-verified
  -- atomically; otherwise dashboards would temporarily continue to show 550.
  SELECT COUNT(*),
         COUNT(*) FILTER (
           WHERE gross_inflow_amount = v_old_amount
             AND gross_outflow_amount = 0
             AND net_cashflow = v_old_amount
         ),
         COALESCE(MAX(gross_inflow_amount), 0)
  INTO v_count, v_known_count, v_fact_treasury_before
  FROM analytics.fact_treasury_cashflow_daily
  WHERE treasury_date = DATE '2026-07-30'
    AND customer_id = v_customer_id
    AND collected_by = v_collector_user_id;
  IF v_count <> 1 OR v_known_count <> 1
     OR v_fact_treasury_before IS DISTINCT FROM v_old_amount THEN
    RAISE EXCEPTION
      'ABORT: treasury analytics changed (rows %, inflow %)',
      v_count, v_fact_treasury_before;
  END IF;

  SELECT COUNT(*),
         COUNT(*) FILTER (
           WHERE receipt_amount = v_old_amount
             AND cash_refund_amount = 0
             AND net_cohort_collection = v_old_amount
         ),
         COALESCE(MAX(receipt_amount), 0)
  INTO v_count, v_known_count, v_fact_ar_before
  FROM analytics.fact_ar_collections_attributed_to_origin_sale_date
  WHERE origin_sale_delivered_at = DATE '2026-07-30'
    AND customer_id = v_customer_id
    AND collected_by = v_collector_user_id;
  IF v_count <> 1 OR v_known_count <> 1
     OR v_fact_ar_before IS DISTINCT FROM v_old_amount THEN
    RAISE EXCEPTION
      'ABORT: attributed-collection analytics changed (rows %, receipts %)',
      v_count, v_fact_ar_before;
  END IF;

  SELECT f.debit_sum, f.credit_sum
  INTO v_fact_1130_debit_before, v_fact_1130_credit_before
  FROM analytics.fact_financial_ledgers_daily f
  JOIN public.chart_of_accounts coa ON coa.id = f.account_id
  WHERE f.date = DATE '2026-07-30' AND coa.code = '1130';
  IF NOT FOUND THEN RAISE EXCEPTION 'ABORT: analytics account 1130 row is missing'; END IF;

  SELECT f.debit_sum, f.credit_sum
  INTO v_fact_1200_debit_before, v_fact_1200_credit_before
  FROM analytics.fact_financial_ledgers_daily f
  JOIN public.chart_of_accounts coa ON coa.id = f.account_id
  WHERE f.date = DATE '2026-07-30' AND coa.code = '1200';
  IF NOT FOUND THEN RAISE EXCEPTION 'ABORT: analytics account 1200 row is missing'; END IF;

  RAISE NOTICE 'PREFLIGHT OK: actual receipt 400 + return credit 150 = invoice 550';
  RAISE NOTICE 'PREFLIGHT OK: customer balance -150 -> 0';
  RAISE NOTICE 'PREFLIGHT OK: InstaPay vault % -> %, later rows to rebase: %',
    v_vault.current_balance, v_expected_vault_balance, v_later_count;
  RAISE NOTICE 'PREFLIGHT OK: custody % remains unchanged at %',
    v_custody_id, v_custody_balance_before;

  IF NOT v_execute THEN
    RAISE NOTICE 'DRY RUN ONLY: no rows were changed. Await explicit approval before setting TRUE.';
    RETURN;
  END IF;

  -- Preserve a complete non-operational audit snapshot before correction.
  SELECT jsonb_build_object(
    'receipt_before', to_jsonb(v_receipt),
    'invoice_before', to_jsonb(v_order),
    'return_unchanged', to_jsonb(v_return),
    'vault_before', to_jsonb(v_vault),
    'vault_transaction_before', to_jsonb(v_vault_tx),
    'journal_before', to_jsonb(v_journal),
    'journal_lines_before', (
      SELECT jsonb_agg(to_jsonb(jel) ORDER BY jel.id)
      FROM public.journal_entry_lines jel WHERE jel.entry_id = v_journal_id
    ),
    'customer_ledger_before', (
      SELECT jsonb_agg(to_jsonb(cl) ORDER BY cl.created_at, cl.id)
      FROM public.customer_ledger cl
      WHERE cl.id IN (v_order_debit_id, v_receipt_ledger_id, v_return_credit_id)
    ),
    'receipt_notifications_before', (
      SELECT jsonb_agg(to_jsonb(n) ORDER BY n.created_at, n.id)
      FROM public.notifications n WHERE n.id = ANY(v_notification_ids)
    ),
    'analytics_before', jsonb_build_object(
      'treasury_gross_inflow', v_fact_treasury_before,
      'attributed_receipt_amount', v_fact_ar_before,
      'account_1130_debit', v_fact_1130_debit_before,
      'account_1130_credit', v_fact_1130_credit_before,
      'account_1200_debit', v_fact_1200_debit_before,
      'account_1200_credit', v_fact_1200_credit_before
    ),
    'protected_custody_before', to_jsonb(v_custody)
  ) INTO v_snapshot;

  INSERT INTO public.audit_logs (
    user_id, action, entity_type, entity_id, old_data, new_data, user_agent
  ) VALUES (
    NULL,
    'correct_splash_receipt_net_of_return',
    'payment_receipt_maintenance',
    v_receipt_id,
    v_snapshot,
    jsonb_build_object(
      'reason', 'Actual InstaPay payment was 400; customer used 150 sales-return credit against invoice 550',
      'receipt_amount_before', v_old_amount,
      'receipt_amount_after', v_actual_amount,
      'return_credit_allocated', v_return_amount,
      'vault_balance_before', v_vault.current_balance,
      'vault_balance_after', v_expected_vault_balance,
      'customer_balance_before', v_customer_balance,
      'customer_balance_after', 0,
      'custody_balance_unchanged', v_custody_balance_before,
      'analytics_rebuilt_for_date', DATE '2026-07-30',
      'executed_at', clock_timestamp()
    ),
    'one-off SQL maintenance script'
  );

  -- Correct the source receipt. Its updated_at trigger may record correction time.
  UPDATE public.payment_receipts
  SET amount = v_actual_amount
  WHERE id = v_receipt_id
    AND number = v_receipt_number
    AND amount = v_old_amount;
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 1 THEN
    RAISE EXCEPTION 'ABORT: receipt compare-and-set updated % rows', v_affected;
  END IF;

  -- Correct the exact receipt credit, then allocate the existing return credit.
  -- The customer-ledger trigger recalculates customers.current_balance on UPDATE.
  UPDATE public.customer_ledger
  SET amount = v_actual_amount,
      description = 'تسديد 400 ج.م — إيصال ' || v_receipt_number
        || ' — فاتورة #' || v_order_number
  WHERE id = v_receipt_ledger_id
    AND amount = v_old_amount
    AND allocated_to = v_order_debit_id;
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 1 THEN
    RAISE EXCEPTION 'ABORT: receipt ledger correction updated % rows', v_affected;
  END IF;

  UPDATE public.customer_ledger
  SET allocated_to = v_order_debit_id,
      description = 'تخصيص رصيد مرتجع #' || v_return_number
        || ' على فاتورة #' || v_order_number
  WHERE id = v_return_credit_id
    AND amount = v_return_amount
    AND allocated_to IS NULL;
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 1 THEN
    RAISE EXCEPTION 'ABORT: return-credit allocation updated % rows', v_affected;
  END IF;

  -- Restate the receipt's exact vault movement and every later running balance.
  UPDATE public.vault_transactions
  SET amount = v_actual_amount,
      balance_after = balance_after - v_difference
  WHERE id = v_vault_tx_id
    AND vault_id = v_vault_id
    AND amount = v_old_amount
    AND balance_after = v_vault_tx.balance_after;
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 1 THEN
    RAISE EXCEPTION 'ABORT: target vault movement correction updated % rows', v_affected;
  END IF;

  UPDATE public.vault_transactions
  SET balance_after = balance_after - v_difference
  WHERE vault_id = v_vault_id
    AND (created_at, id) > (v_vault_tx.created_at, v_vault_tx.id);
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> v_later_count THEN
    RAISE EXCEPTION
      'ABORT: rebased % later vault rows; expected %',
      v_affected, v_later_count;
  END IF;

  UPDATE public.vaults
  SET current_balance = v_expected_vault_balance
  WHERE id = v_vault_id
    AND current_balance = v_vault.current_balance;
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 1 THEN
    RAISE EXCEPTION 'ABORT: InstaPay vault balance compare-and-set failed';
  END IF;

  -- Restate only the receipt journal; the sales-return journal remains untouched.
  UPDATE public.journal_entries
  SET total_debit = v_actual_amount,
      total_credit = v_actual_amount,
      description = 'تحصيل instapay بقيمة 400 ج.م من Splash — صافي بعد رصيد مرتجع 150 ج.م'
  WHERE id = v_journal_id
    AND total_debit = v_old_amount
    AND total_credit = v_old_amount;
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 1 THEN
    RAISE EXCEPTION 'ABORT: receipt journal header correction updated % rows', v_affected;
  END IF;

  UPDATE public.journal_entry_lines
  SET debit = CASE WHEN id = v_journal_1130_id THEN v_actual_amount ELSE 0 END,
      credit = CASE WHEN id = v_journal_1200_id THEN v_actual_amount ELSE 0 END,
      description = 'تحصيل instapay بقيمة 400 ج.م من Splash — صافي بعد رصيد مرتجع 150 ج.م'
  WHERE id IN (v_journal_1130_id, v_journal_1200_id)
    AND entry_id = v_journal_id;
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 2 THEN
    RAISE EXCEPTION 'ABORT: receipt journal-line correction updated % rows', v_affected;
  END IF;

  UPDATE public.notifications
  SET body = replace(body, '550.00', '400.00')
  WHERE id = ANY(v_notification_ids)
    AND entity_type = 'payment_receipt'
    AND entity_id = v_receipt_id
    AND body LIKE '%550.00%';
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 2 THEN
    RAISE EXCEPTION 'ABORT: receipt notification correction updated % rows', v_affected;
  END IF;

  -- Collection targets/reports use receipt.amount; recalculate the affected collector.
  PERFORM public.recalculate_targets_for_employee(
    v_collector_emp_id,
    ARRAY['collection']::TEXT[],
    CURRENT_DATE,
    DATE '2026-07-30'
  );

  -- Rebuild only the three affected daily analytics facts. These canonical
  -- procedures derive their values from the corrected operational ledgers.
  CALL analytics.internal_refresh_fact_treasury_cashflow_daily(
    ARRAY[DATE '2026-07-30']::DATE[]
  );
  CALL analytics.internal_refresh_fact_ar_collections_attributed(
    ARRAY[DATE '2026-07-30']::DATE[]
  );
  CALL analytics.internal_refresh_fact_financial_ledgers_daily(
    ARRAY[DATE '2026-07-30']::DATE[]
  );

  -- Post-mutation invariants.
  SELECT COUNT(*) INTO v_count
  FROM public.payment_receipts
  WHERE id = v_receipt_id AND amount = v_actual_amount
    AND status = 'confirmed' AND vault_id = v_vault_id;
  IF v_count <> 1 THEN RAISE EXCEPTION 'ABORT: receipt final state failed'; END IF;

  SELECT COUNT(*), COALESCE(SUM(amount), 0)
  INTO v_count, v_customer_balance
  FROM public.customer_ledger
  WHERE customer_id = v_customer_id
    AND type = 'credit'
    AND allocated_to = v_order_debit_id;
  IF v_count <> 2 OR v_customer_balance IS DISTINCT FROM v_old_amount THEN
    RAISE EXCEPTION
      'ABORT: invoice final allocation is not 400 receipt + 150 return (rows %, total %)',
      v_count, v_customer_balance;
  END IF;

  SELECT COALESCE(SUM(CASE WHEN type = 'debit' THEN amount ELSE -amount END), 0)
  INTO v_customer_balance
  FROM public.customer_ledger WHERE customer_id = v_customer_id;

  SELECT current_balance INTO v_cached_customer_balance
  FROM public.customers WHERE id = v_customer_id;

  IF v_customer_balance IS DISTINCT FROM 0::NUMERIC
     OR v_cached_customer_balance IS DISTINCT FROM 0::NUMERIC
  THEN
    RAISE EXCEPTION
      'ABORT: customer final balance is not zero (ledger %, cached %)',
      v_customer_balance, v_cached_customer_balance;
  END IF;

  SELECT current_balance INTO v_latest_vault_balance
  FROM public.vaults WHERE id = v_vault_id;
  IF v_latest_vault_balance IS DISTINCT FROM v_expected_vault_balance THEN
    RAISE EXCEPTION 'ABORT: final InstaPay vault balance is %; expected %',
      v_latest_vault_balance, v_expected_vault_balance;
  END IF;

  SELECT COUNT(*) INTO v_chain_errors
  FROM (
    SELECT
      created_at, id, type, amount, balance_after,
      LAG(balance_after) OVER (ORDER BY created_at, id) AS previous_balance
    FROM public.vault_transactions WHERE vault_id = v_vault_id
  ) AS chain
  WHERE (created_at, id) >= (v_vault_tx.created_at, v_vault_tx.id)
    AND balance_after IS DISTINCT FROM
      previous_balance + CASE
        WHEN type IN (
          'deposit', 'transfer_in', 'collection', 'custody_return',
          'opening_balance', 'vendor_refund'
        ) THEN amount
        WHEN type IN (
          'withdrawal', 'transfer_out', 'expense', 'custody_load',
          'vendor_payment', 'payroll_payment'
        ) THEN -amount
        ELSE NULL
      END;
  IF v_chain_errors <> 0 THEN
    RAISE EXCEPTION 'ABORT: final vault chain has % error(s)', v_chain_errors;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.journal_entry_lines jel
  JOIN public.chart_of_accounts coa ON coa.id = jel.account_id
  WHERE jel.entry_id = v_journal_id
    AND (
      (coa.code = '1130' AND jel.debit = v_actual_amount AND jel.credit = 0)
      OR
      (coa.code = '1200' AND jel.debit = 0 AND jel.credit = v_actual_amount)
    );
  IF v_count <> 2 THEN RAISE EXCEPTION 'ABORT: final receipt journal lines failed'; END IF;

  SELECT current_balance INTO v_cached_customer_balance
  FROM public.custody_accounts WHERE id = v_custody_id;
  IF v_cached_customer_balance IS DISTINCT FROM v_custody_balance_before THEN
    RAISE EXCEPTION 'ABORT: protected custody changed from % to %',
      v_custody_balance_before, v_cached_customer_balance;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.sales_orders
  WHERE id = v_order_id AND status = 'completed'
    AND total_amount = v_old_amount AND paid_amount = v_old_amount;
  IF v_count <> 1 THEN RAISE EXCEPTION 'ABORT: invoice final state changed unexpectedly'; END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.sales_returns
  WHERE id = v_return_id AND status = 'confirmed' AND total_amount = v_return_amount;
  IF v_count <> 1 THEN RAISE EXCEPTION 'ABORT: return final state changed unexpectedly'; END IF;

  SELECT COUNT(*) INTO v_count
  FROM analytics.fact_treasury_cashflow_daily
  WHERE treasury_date = DATE '2026-07-30'
    AND customer_id = v_customer_id
    AND collected_by = v_collector_user_id
    AND gross_inflow_amount = v_actual_amount
    AND gross_outflow_amount = 0
    AND net_cashflow = v_actual_amount;
  IF v_count <> 1 THEN RAISE EXCEPTION 'ABORT: final treasury analytics failed'; END IF;

  SELECT COUNT(*) INTO v_count
  FROM analytics.fact_ar_collections_attributed_to_origin_sale_date
  WHERE origin_sale_delivered_at = DATE '2026-07-30'
    AND customer_id = v_customer_id
    AND collected_by = v_collector_user_id
    AND receipt_amount = v_actual_amount
    AND cash_refund_amount = 0
    AND net_cohort_collection = v_actual_amount;
  IF v_count <> 1 THEN RAISE EXCEPTION 'ABORT: final attributed-collection analytics failed'; END IF;

  SELECT COUNT(*) INTO v_count
  FROM analytics.fact_financial_ledgers_daily f
  JOIN public.chart_of_accounts coa ON coa.id = f.account_id
  WHERE f.date = DATE '2026-07-30'
    AND (
      (coa.code = '1130'
       AND f.debit_sum = v_fact_1130_debit_before - v_difference
       AND f.credit_sum = v_fact_1130_credit_before)
      OR
      (coa.code = '1200'
       AND f.debit_sum = v_fact_1200_debit_before
       AND f.credit_sum = v_fact_1200_credit_before - v_difference)
    );
  IF v_count <> 2 THEN RAISE EXCEPTION 'ABORT: final financial analytics failed'; END IF;

  RAISE NOTICE 'EXECUTION OK: receipt 550 -> 400 and return credit 150 allocated to invoice 550';
  RAISE NOTICE 'EXECUTION OK: customer balance is 0; InstaPay vault is %; custody unchanged at %',
    v_expected_vault_balance, v_custody_balance_before;
END;
$maintenance$;

COMMIT;

-- Read-only summary. Before execution it must report awaiting_review_not_executed.
SELECT
  CASE
    WHEN EXISTS (
      SELECT 1 FROM public.payment_receipts
      WHERE id = '030b6485-66c4-42f5-ac66-175d22bd3cea'::UUID AND amount = 550
    ) THEN 'awaiting_review_not_executed'
    WHEN EXISTS (
      SELECT 1 FROM public.payment_receipts
      WHERE id = '030b6485-66c4-42f5-ac66-175d22bd3cea'::UUID AND amount = 400
    ) THEN 'corrected_and_verified'
    ELSE 'unexpected_receipt_state'
  END AS operation_state,
  (SELECT current_balance FROM public.customers
   WHERE id = 'cf7fbbb5-f7dd-46d7-b56c-4be78377ad0c'::UUID) AS customer_balance,
  (SELECT current_balance FROM public.vaults
   WHERE id = '0d487441-0313-4a7e-9fed-f3b9421e94e5'::UUID) AS instapay_vault_balance,
  (SELECT current_balance FROM public.custody_accounts
   WHERE id = '4689bfe4-97b0-42bc-bca3-f4b139911fa6'::UUID) AS protected_custody_balance,
  (SELECT COUNT(*) FROM public.audit_logs
   WHERE action = 'correct_splash_receipt_net_of_return'
     AND entity_id = '030b6485-66c4-42f5-ac66-175d22bd3cea'::UUID) AS correction_audit_rows;
