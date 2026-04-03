-- ============================================================
-- 59: Finance reconciliation views
-- Read-only checks for subledger and GL alignment
-- ============================================================

CREATE OR REPLACE VIEW v_reconcile_customer_balances AS
SELECT
  c.id,
  c.name,
  COALESCE(c.current_balance, 0) AS master_balance,
  COALESCE(SUM(CASE WHEN cl.type = 'debit' THEN cl.amount ELSE -cl.amount END), 0) AS ledger_balance,
  COALESCE(c.current_balance, 0) - COALESCE(SUM(CASE WHEN cl.type = 'debit' THEN cl.amount ELSE -cl.amount END), 0) AS drift
FROM customers c
LEFT JOIN customer_ledger cl
  ON cl.customer_id = c.id
GROUP BY c.id, c.name, c.current_balance;

CREATE OR REPLACE VIEW v_reconcile_supplier_balances AS
SELECT
  s.id,
  s.name,
  COALESCE(s.current_balance, 0) AS master_balance,
  COALESCE(SUM(CASE WHEN sl.type = 'credit' THEN sl.amount ELSE -sl.amount END), 0) AS ledger_balance,
  COALESCE(s.current_balance, 0) - COALESCE(SUM(CASE WHEN sl.type = 'credit' THEN sl.amount ELSE -sl.amount END), 0) AS drift
FROM suppliers s
LEFT JOIN supplier_ledger sl
  ON sl.supplier_id = s.id
GROUP BY s.id, s.name, s.current_balance;

CREATE OR REPLACE VIEW v_reconcile_vault_balances AS
SELECT
  v.id,
  v.name,
  v.type,
  COALESCE(v.current_balance, 0) AS master_balance,
  COALESCE(SUM(
    CASE
      WHEN vt.type IN (
        'deposit', 'transfer_in', 'collection', 'custody_return',
        'opening_balance', 'vendor_refund'
      ) THEN vt.amount
      ELSE -vt.amount
    END
  ), 0) AS txn_balance,
  COALESCE(v.current_balance, 0) - COALESCE(SUM(
    CASE
      WHEN vt.type IN (
        'deposit', 'transfer_in', 'collection', 'custody_return',
        'opening_balance', 'vendor_refund'
      ) THEN vt.amount
      ELSE -vt.amount
    END
  ), 0) AS drift
FROM vaults v
LEFT JOIN vault_transactions vt
  ON vt.vault_id = v.id
GROUP BY v.id, v.name, v.type, v.current_balance;

CREATE OR REPLACE VIEW v_reconcile_ar_control_account AS
WITH subledger AS (
  SELECT COALESCE(SUM(CASE WHEN type = 'debit' THEN amount ELSE -amount END), 0) AS balance
  FROM customer_ledger
),
gl AS (
  SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS balance
  FROM journal_entry_lines jl
  JOIN journal_entries je ON je.id = jl.entry_id AND je.status = 'posted'
  JOIN chart_of_accounts coa ON coa.id = jl.account_id
  WHERE coa.code = '1200'
)
SELECT
  '1200'::TEXT AS account_code,
  subledger.balance AS subledger_balance,
  gl.balance AS gl_balance,
  subledger.balance - gl.balance AS drift
FROM subledger, gl;

CREATE OR REPLACE VIEW v_reconcile_ap_control_account AS
WITH subledger AS (
  SELECT COALESCE(SUM(CASE WHEN type = 'credit' THEN amount ELSE -amount END), 0) AS balance
  FROM supplier_ledger
),
gl AS (
  SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS balance
  FROM journal_entry_lines jl
  JOIN journal_entries je ON je.id = jl.entry_id AND je.status = 'posted'
  JOIN chart_of_accounts coa ON coa.id = jl.account_id
  WHERE coa.code = '2100'
)
SELECT
  '2100'::TEXT AS account_code,
  subledger.balance AS subledger_balance,
  gl.balance AS gl_balance,
  subledger.balance - gl.balance AS drift
FROM subledger, gl;

CREATE OR REPLACE VIEW v_reconcile_treasury_control_accounts AS
WITH account_map AS (
  SELECT '1110'::TEXT AS account_code, 'cash'::TEXT AS vault_type
  UNION ALL
  SELECT '1120'::TEXT AS account_code, 'bank'::TEXT AS vault_type
  UNION ALL
  SELECT '1130'::TEXT AS account_code, 'mobile_wallet'::TEXT AS vault_type
),
vault_totals AS (
  SELECT
    CASE v.type
      WHEN 'bank' THEN '1120'
      WHEN 'mobile_wallet' THEN '1130'
      ELSE '1110'
    END AS account_code,
    COALESCE(SUM(v.current_balance), 0) AS vault_balance
  FROM vaults v
  GROUP BY 1
),
gl_totals AS (
  SELECT
    coa.code AS account_code,
    COALESCE(SUM(jl.debit - jl.credit), 0) AS gl_balance
  FROM journal_entry_lines jl
  JOIN journal_entries je ON je.id = jl.entry_id AND je.status = 'posted'
  JOIN chart_of_accounts coa ON coa.id = jl.account_id
  WHERE coa.code IN ('1110', '1120', '1130')
  GROUP BY coa.code
)
SELECT
  m.account_code,
  m.vault_type,
  COALESCE(vt.vault_balance, 0) AS subledger_balance,
  COALESCE(g.gl_balance, 0) AS gl_balance,
  COALESCE(vt.vault_balance, 0) - COALESCE(g.gl_balance, 0) AS drift
FROM account_map m
LEFT JOIN vault_totals vt ON vt.account_code = m.account_code
LEFT JOIN gl_totals g ON g.account_code = m.account_code;

CREATE OR REPLACE VIEW v_documents_missing_journal_entries AS
SELECT
  'sales_order'::TEXT AS doc_type,
  so.id,
  so.order_number AS reference,
  so.created_at
FROM sales_orders so
WHERE so.status IN ('delivered', 'completed')
  AND NOT EXISTS (
    SELECT 1
    FROM journal_entries je
    WHERE je.source_type = 'sales_order'
      AND je.source_id = so.id
  )
UNION ALL
SELECT
  'purchase_invoice'::TEXT AS doc_type,
  pi.id,
  pi.number AS reference,
  pi.created_at
FROM purchase_invoices pi
WHERE pi.status IN ('billed', 'paid')
  AND NOT EXISTS (
    SELECT 1
    FROM journal_entries je
    WHERE je.source_type = 'purchase_order'
      AND je.source_id = pi.id
  );

GRANT SELECT ON v_reconcile_customer_balances TO authenticated;
GRANT SELECT ON v_reconcile_supplier_balances TO authenticated;
GRANT SELECT ON v_reconcile_vault_balances TO authenticated;
GRANT SELECT ON v_reconcile_ar_control_account TO authenticated;
GRANT SELECT ON v_reconcile_ap_control_account TO authenticated;
GRANT SELECT ON v_reconcile_treasury_control_accounts TO authenticated;
GRANT SELECT ON v_documents_missing_journal_entries TO authenticated;
