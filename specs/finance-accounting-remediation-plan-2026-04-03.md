# EDARA Financial And Accounting Remediation Plan

Date: 2026-04-03

Status: Draft for implementation

Scope:
- Review based on the current repository code and the active database schema as defined by the Supabase migrations in this workspace.
- No direct remote-database session was available in this review, so "actual database" here means the effective schema and posting logic currently declared by the checked-in migrations and application code.
- This document targets the live logic implemented in:
  - `src/lib/services/*`
  - `src/pages/finance/*`
  - `src/pages/customers/*`
  - `src/pages/suppliers/*`
  - `supabase/migrations/*`

Out of scope for now:
- Customer and supplier cheque clearing cycles.
- These are deferred intentionally because cheques are not an active operational flow at the moment.
- They must remain documented and blocked from being treated as complete accounting cycles.

## 1. Evidence Reviewed

The plan below is based on the current implementation in these key files:

- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\supabase\migrations\02_master_data.sql`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\supabase\migrations\03_financial_infrastructure.sql`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\supabase\migrations\03c_atomic_journal_entry.sql`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\supabase\migrations\03d_vault_transfer.sql`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\supabase\migrations\03h_extreme_performance.sql`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\supabase\migrations\03j_auth_guard.sql`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\supabase\migrations\04_sales_system.sql`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\supabase\migrations\08_payment_receipts_refactor.sql`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\supabase\migrations\11_final_accounting_sync.sql`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\supabase\migrations\14_procurement_schema_and_coa.sql`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\supabase\migrations\15_procurement_core_rpcs.sql`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\supabase\migrations\16_procurement_returns_and_cancellations.sql`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\supabase\migrations\19c_advances_finance_sync.sql`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\supabase\migrations\21c_fix_opening_balance_audit_actor.sql`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\supabase\migrations\22d_payroll_sync.sql`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\lib\services\customers.ts`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\lib\services\suppliers.ts`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\lib\services\vaults.ts`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\lib\services\finance.ts`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\pages\customers\CustomerFormPage.tsx`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\pages\customers\CustomerDetailPage.tsx`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\pages\suppliers\SupplierFormPage.tsx`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\pages\suppliers\SupplierDetailPage.tsx`
- `C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\pages\finance\VaultsPage.tsx`

## 2. Current State Summary

### 2.1 Flows that are already materially covered

These flows currently appear to have both operational movement and accounting posting:

- Sales delivery and revenue posting
- Customer collections except the deferred cheque clearing leg
- Supplier invoice billing
- Supplier payments except the deferred cheque clearing leg
- Sales returns
- Purchase returns
- Approved expenses
- Custody load and settlement
- Employee advance disbursement
- Payroll approval

### 2.2 Flows that remain structurally exposed

These are the remaining priority gaps:

- Editing customer and supplier opening balances after creation
- Manual vault adjustments
- Cross-type vault transfers
- Missing hard guards against direct mutation of financial master fields
- Lack of systematic reconciliation views and blocking audits

## 3. Deferred Item: Cheque Cycle

Decision:
- The cheque lifecycle is intentionally deferred.
- No implementation work is required for this phase.

Required documentation status:
- Customer cheque confirmation currently parks into `1210`.
- Supplier cheque issuance currently parks into `2110`.
- There is no later clearing step.
- These flows must not be treated internally as full treasury completion.

Operational rule until future phase:
- The product team should not activate cheque-based operating procedures.
- Finance documentation should state clearly that cheques are recorded only as interim paper positions in the current phase.

Future phase placeholder:
- Customer cheque clearing: `Dr 1120 / Cr 1210`
- Supplier cheque clearing: `Dr 2110 / Cr 1120`

## 4. Main Design Principle For The Fixes

We will not remove user capabilities where a safe accounting implementation can preserve them.

The goal is:
- Keep the same business screens where possible
- Avoid extra complexity for end users
- Move sensitive posting logic into controlled RPCs
- Make the database reject unsafe direct edits
- Ensure every financially material operation ends in one of these outcomes:
  - fully posted
  - explicitly deferred by design
  - explicitly blocked

## 5. Workstream A: Opening Balance Editing For Customers And Suppliers

### 5.1 What exists now

Current behavior:
- `opening_balance` exists on `customers` and `suppliers` in `02_master_data.sql`
- initial insert used to seed `current_balance`
- `sync_customer_opening_balance()` and `sync_supplier_opening_balance()` insert opening rows into subledgers on insert only
- later cached balances are maintained from `customer_ledger` and `supplier_ledger` by triggers in `03h_extreme_performance.sql`
- frontend edit forms still allow changing `opening_balance`
- service layer updates the master row directly with `.update(input)`

Current risk:
- after creation, changing `opening_balance` does not create a ledger delta
- does not create a journal entry
- does not safely realign `current_balance`
- can leave:
  - master opening balance
  - cached current balance
  - subledger totals
  - general ledger
  all inconsistent with each other

### 5.2 Target behavior

Target rule:
- `opening_balance` remains editable in the UI.
- But any edit after creation must be treated as a formal financial adjustment, not a plain master-data edit.

Target implementation:
- Add a dedicated RPC for customers:
  - `adjust_customer_opening_balance(p_customer_id uuid, p_new_opening_balance numeric, p_reason text, p_user_id uuid)`
- Add a dedicated RPC for suppliers:
  - `adjust_supplier_opening_balance(p_supplier_id uuid, p_new_opening_balance numeric, p_reason text, p_user_id uuid)`

RPC behavior:
1. Lock the customer or supplier row.
2. Read old `opening_balance`.
3. Compute `delta = p_new_opening_balance - old_opening_balance`.
4. If `delta = 0`, update nothing and return success.
5. Update the `opening_balance` field on the master row.
6. Insert a subledger delta:
   - customer:
     - `delta > 0` -> `debit`
     - `delta < 0` -> `credit`
   - supplier:
     - `delta > 0` -> `credit`
     - `delta < 0` -> `debit`
7. Create a journal entry against an equity-side balancing account.
8. Record a structured audit trail.

### 5.3 Contra account choice

Current schema evidence:
- `3100` exists: capital
- `3200` exists: retained earnings, added in `14_procurement_schema_and_coa.sql`

Recommended phase-1 accounting choice:
- Use `3200` as the balancing account for opening-balance adjustments.

Reason:
- It already exists in the current chart.
- It avoids adding a new account just to unblock the feature safely.
- It minimizes migration risk.

Optional later refinement:
- Add a dedicated child account under equity such as `3210 Opening Balance Adjustments`.
- This is optional, not required for the current safe rollout.

### 5.4 Journal posting rule

Customer opening balance adjustment:
- Increase opening balance:
  - `Dr 1200`
  - `Cr 3200`
- Decrease opening balance:
  - `Dr 3200`
  - `Cr 1200`

Supplier opening balance adjustment:
- Increase opening balance:
  - `Dr 3200`
  - `Cr 2100`
- Decrease opening balance:
  - `Dr 2100`
  - `Cr 3200`

### 5.5 Subledger source typing

Current source enums already allow:
- `opening_balance`
- `adjustment`

Recommendation:
- Preserve original insert-time seed as `opening_balance`
- Use `adjustment` for later edits after creation

Reason:
- This gives better audit clarity than repeatedly reusing `opening_balance`.

### 5.6 Audit requirements

Add dedicated audit table:
- `customer_opening_balance_audit`
- `supplier_opening_balance_audit`

Minimum fields:
- `id`
- target entity id
- old opening balance
- new opening balance
- delta
- linked journal entry id
- linked ledger row id
- reason
- changed_by
- changed_at

### 5.7 Frontend and service-layer change

Keep the field visible in:
- `CustomerFormPage.tsx`
- `SupplierFormPage.tsx`

Change submit behavior:
- create mode:
  - same as now
- edit mode:
  - split payload into:
    - non-financial fields
    - opening balance field
  - update non-financial fields with normal update
  - if opening balance changed:
    - call the new RPC

Service-layer change:
- in `customers.ts` and `suppliers.ts`, do not pass changed opening balances through plain `.update()` once the RPC exists

### 5.8 Database guard

Add a trigger guard on `customers` and `suppliers`:
- reject direct update to `opening_balance` unless a controlled DB context flag is set

Suggested pattern:
- inside RPC:
  - `PERFORM set_config('app.finance_context', 'opening_balance_adjustment', true);`
- trigger checks:
  - if `OLD.opening_balance IS DISTINCT FROM NEW.opening_balance`
  - and `current_setting('app.finance_context', true) <> 'opening_balance_adjustment'`
  - then raise exception

This protects against accidental direct updates from future code.

### 5.9 UI display correction

Current detail pages use:
- `current_balance || opening_balance || 0`

This must be corrected after the rollout.

Target display behavior:
- current balance card:
  - show `current_balance` only
- opening balance:
  - show as a separate reference field

Reason:
- fallback rendering can mask real accounting drift.

## 6. Workstream B: Vault Transfers

### 6.1 What exists now

Current behavior:
- `transfer_between_vaults()` updates vault balances and inserts source and target vault transactions
- no journal entry is created

### 6.2 Target behavior

Target rule:
- Same-type transfer:
  - no general ledger movement is required if both vaults roll up to the same GL account
  - example: cash vault to cash vault under `1110`
- Cross-type transfer:
  - must create a journal entry
  - examples:
    - cash -> bank: `Dr 1120 / Cr 1110`
    - bank -> wallet: `Dr 1130 / Cr 1120`

### 6.3 Implementation

Update:
- `transfer_between_vaults()` in the active function definition

Add logic:
1. Read source vault type and target vault type.
2. Map each to:
   - `cash` -> `1110`
   - `bank` -> `1120`
   - `mobile_wallet` -> `1130`
3. If mapped account codes are different:
   - create a journal entry using `create_manual_journal_entry()`
4. If account codes are equal:
   - skip GL posting

### 6.4 Acceptance criteria

- Same-type transfer changes vault balances only
- Cross-type transfer changes:
  - source vault balance
  - target vault balance
  - one posted journal entry

## 7. Workstream C: Manual Vault Adjustments

### 7.1 What exists now

Current behavior:
- `VaultsPage.tsx` exposes:
  - deposit
  - withdrawal
  - opening balance
- these call `add_vault_transaction()` directly
- no contra account and no journal entry

### 7.2 Target behavior

We should preserve the business action, but not as a free cash mutation.

Recommended phase-1 UX:
- keep the same actions
- add a required simple reason selector
- do not expose chart of accounts to the end user

Recommended reason codes:
- `opening_balance`
- `owner_funding`
- `owner_withdrawal`
- `cash_shortage`
- `cash_overage`
- `treasury_adjustment`

Mapping rule:
- each reason code maps to a predefined contra account code

Suggested initial mapping:
- `opening_balance` -> `3200`
- `owner_funding` -> `3100`
- `owner_withdrawal` -> `3100`
- `cash_shortage` -> `5900`
- `cash_overage` -> `5900`
- `treasury_adjustment` -> `3200`

Note:
- This is intentionally simple for phase 1.
- If finance later needs richer control, reason-to-account mapping can be moved into a dedicated configuration table.

### 7.3 Implementation

Add RPC:
- `post_manual_vault_adjustment(p_vault_id uuid, p_direction text, p_amount numeric, p_reason_code text, p_description text, p_user_id uuid)`

Behavior:
1. Validate vault.
2. Resolve reason code to contra account.
3. Create vault transaction.
4. Create journal entry:
   - deposit:
     - `Dr vault account`
     - `Cr contra account`
   - withdrawal:
     - `Dr contra account`
     - `Cr vault account`

For opening balance:
- keep the same UX button if desired
- route it through the same safe RPC

### 7.4 Transitional UI rule

If product wants zero friction:
- prefill the most common reason by action
- for example:
  - opening -> `opening_balance`
  - deposit -> `owner_funding`
  - withdrawal -> `owner_withdrawal`

But finance should still be able to change the reason when needed.

## 8. Workstream D: Financial Field Guards

### 8.1 Why this is required

Even after fixing the main workflows, the system remains exposed if future code can directly update financial fields from service methods or ad-hoc pages.

### 8.2 Fields to protect

Protect direct mutation on:
- `customers.opening_balance`
- `suppliers.opening_balance`
- `customers.current_balance`
- `suppliers.current_balance`
- `vaults.current_balance`
- `sales_orders.paid_amount`
- `sales_orders.returned_amount`
- `purchase_invoices.paid_amount`

Policy:
- these fields should only change through controlled posting functions or ledger/cached-balance triggers.

### 8.3 Enforcement style

Use `BEFORE UPDATE` triggers with context checks.

Examples:
- `app.finance_context = opening_balance_adjustment`
- `app.finance_context = payment_allocation`
- `app.finance_context = sales_return_confirmation`
- `app.finance_context = procurement_payment`
- `app.finance_context = vault_posting`

This avoids accidental direct edits while keeping the existing trusted RPC model.

## 9. Workstream E: Reconciliation Views And Blocking Audits

### 9.1 Required SQL views

Add these views:

- `v_reconcile_customer_balances`
  - master `current_balance`
  - computed balance from `customer_ledger`
  - difference

- `v_reconcile_supplier_balances`
  - master `current_balance`
  - computed balance from `supplier_ledger`
  - difference

- `v_reconcile_vault_balances`
  - vault `current_balance`
  - computed balance from `vault_transactions`
  - mapped GL balance by account code
  - difference vs GL

- `v_documents_missing_journal_entries`
  - finalized financial documents with no journal entries

- `v_documents_missing_subledger_entries`
  - finalized sales or procurement documents with no matching ledger effect where required

### 9.2 Required operational use

These views should be used in:
- a finance audit page later
- pre-release manual verification
- automated acceptance tests

### 9.3 Blocking policy

Phase 1:
- reporting only

Phase 2:
- selected guards should block new finalization if baseline conditions are not met

## 10. Workstream F: Data Repair And Backfill

### 10.1 Opening balance repair

Backfill queries are required for historical consistency.

For customers and suppliers:
- identify rows where:
  - master `opening_balance`
  - opening-related ledger rows
  - current cached balance
  do not match expected historical state

Repair strategy:
- do not overwrite history blindly
- instead:
  - compute expected opening delta
  - insert explicit `adjustment` ledger rows
  - insert balancing journal entries
  - record one migration-level audit note

### 10.2 Manual vault movement repair

Historical manual vault transactions may not always be auto-repairable because the intended contra side is not fully inferable from description text.

Repair plan:
- classify historical records into:
  - automatically repairable
  - finance-review required

Automatically repairable examples:
- explicit opening balance

Manual finance review required:
- generic deposit or withdrawal with ambiguous business meaning

### 10.3 Cross-type transfer backfill

Historical vault transfers can be backfilled more safely:
- if source and target types differ
- and no existing journal entry is found for the transfer reference
- create missing `Dr target / Cr source` journal entries

## 11. Files Expected To Change

### 11.1 Database

Likely new migration files:
- `supabase/migrations/54_finance_opening_balance_adjustments.sql`
- `supabase/migrations/55_finance_vault_safe_posting.sql`
- `supabase/migrations/56_finance_reconciliation_views.sql`
- `supabase/migrations/57_finance_field_guards.sql`
- `supabase/migrations/58_finance_backfill_opening_and_vault_gaps.sql`

### 11.2 Frontend and services

Likely touched files:
- `src/lib/services/customers.ts`
- `src/lib/services/suppliers.ts`
- `src/lib/services/vaults.ts`
- `src/pages/customers/CustomerFormPage.tsx`
- `src/pages/customers/CustomerDetailPage.tsx`
- `src/pages/suppliers/SupplierFormPage.tsx`
- `src/pages/suppliers/SupplierDetailPage.tsx`
- `src/pages/finance/VaultsPage.tsx`

## 12. Acceptance Tests

The following scenarios must pass before the work is considered complete.

### 12.1 Opening balances

- Create customer with opening balance:
  - customer ledger row exists
  - customer current balance equals ledger total
  - journal entry exists

- Edit customer opening balance upward:
  - adjustment ledger row exists
  - `current_balance` updated via trigger outcome
  - journal entry exists
  - audit row exists

- Edit customer opening balance downward:
  - same guarantees as above

- Create supplier with opening balance:
  - supplier ledger row exists
  - supplier current balance equals ledger total
  - journal entry exists

- Edit supplier opening balance up and down:
  - same guarantees

### 12.2 Vault transfers

- Cash vault -> cash vault:
  - no GL transfer entry
  - vault balances correct

- Cash vault -> bank vault:
  - posted journal entry
  - `Dr 1120 / Cr 1110`

### 12.3 Manual vault adjustments

- Deposit with reason `owner_funding`
  - vault transaction created
  - matching journal entry created

- Withdrawal with reason `owner_withdrawal`
  - vault transaction created
  - matching journal entry created

- Opening balance on vault
  - vault transaction created
  - matching journal entry created

### 12.4 Guards

- Direct SQL update to protected field without context:
  - rejected

- Same update through approved RPC:
  - succeeds

### 12.5 Reconciliation

- All seeded scenario balances reconcile to zero difference in:
  - customer reconciliation view
  - supplier reconciliation view
  - vault reconciliation view

## 13. Recommended Delivery Sequence

Phase 1:
- Opening balance adjustment RPCs
- frontend integration
- detail-page balance display correction

Phase 2:
- cross-type vault transfer posting
- manual vault adjustment safe posting

Phase 3:
- field guards
- reconciliation views

Phase 4:
- historical backfill scripts
- acceptance and audit verification

Deferred phase:
- cheque clearing lifecycle

## 14. Final Recommendation

The highest-priority implementation order is:

1. Fix opening-balance editing safely without removing the feature.
2. Fix cross-type vault transfers.
3. Convert manual vault adjustments into controlled accounting postings.
4. Add financial field guards.
5. Add reconciliation views and backfill scripts.

This sequence preserves current user flows, minimizes UI disruption, and closes the highest-risk accounting gaps first.
