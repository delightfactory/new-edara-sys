# Double Review Spec - FINAL V5

## 1. Overview
The Double Review engine mathematically compares the aggregated values in the `analytics` schema against verified independent accounting and ledger sources.

## 2. Independent Reconciliation Sources by Metric Family

### Family A: Revenue Posting Consistency (Accounting Alignment)
- **Analytics Metric**: Recognized Sales Revenue (Tax Exclusive) via `analytics.fact_sales_daily_grain.tax_exclusive_amount`.
- **Posting Consistency Source**: The Accounting Ledger (`journal_entry_lines`).
- **Logic**: Must mathematically mirror the sum of **GL Revenue Accounts (Credit)** over that exact period, completely ignoring tax GL accounts.
- **Disclaimer**: This family proves *Systems Posting Consistency* (i.e., the operational invoice properly generated its exact mapping in GL). It does not prove independent financial truth since both originate from the same operational trigger.

### Family B: AR Debt Creation vs Customer Sub-Ledger
- **Analytics Metric**: AR Debt Creation / Credit Portion via `analytics.fact_sales_daily_grain.ar_credit_portion_amount`.
- **Independent Reconciliation Source**: The Customer Ledger.
- **Logic**: Must strictly match the total Debit entries injected into `customer_ledger` representing sales invoices. 
- **Exclusion**: Cash portions of invoices bypass this family to map to Treasury validations.

### Family C: Invoice Gross Sales vs Total Debits
- **Analytics Metric**: Invoice Gross Sales (Tax Inclusive) via `analytics.fact_sales_daily_grain.tax_inclusive_amount`.
- **Independent Reconciliation Source**: Total Debit mapping inside `journal_entry_lines` linked to the sales.
- **Logic**: Since the settlement of an invoice can be split into Cash (Vault) and Credit (AR), the *total* invoice value can only be reconciled by summing the entire debit ledger posting resulting from the origin of the sale.

### Family D: AR Collections vs Treasury Sub-Ledgers
- **Analytics Metric**: Net AR Collection from `analytics.fact_ar_collections_by_receipt_date`.
- **Independent Reconciliation Source**: Credit distributions in `customer_ledger` explicitly tied to receipt flows.
- **Logic**: Validates cash matching, ensuring treasury cash flow isn't falsified by target attribution logic. 

## 3. Metric State Mapping & Governance

### `VERIFIED`
- **Applicability**: Family B (AR Creation), Family D (Collections).
- **State Behavior**: Fully trusted, exposed without warning in UI.

### `POSTING_CONSISTENCY_ONLY`
- **Applicability**: Family A (Revenue).
- **State Behavior**: Trusted as system-consistent with Accounting GL, but flagged in UI (NOT independent) since both originate from the same operational invoice creation logic.

### `RECONCILED_WITH_WARNING`
- **Applicability**: Family C (Gross Sales Full Invoice Summation), AR caching anomalies.
- **State Behavior**: Allowed variance up to `+/- 5.0` solely to accommodate fractional decimal rounding errors over 100,000s of lines, or partial cash fraction rounding mismatch.

### `OPERATIONAL_ONLY`
- **Applicability**: Managerial P&L.
- **State Behavior**: Displayed ONLY in Sales / Operational scopes with a permanent disclaimer `[Approximate / Operational Only]`. Skips Double Review due to missing exact valuation tables.

### `BLOCKED`
- **Applicability**: Any `VERIFIED` family metric that diverges by > 0.00, or any `WARNING` metric diverging > 5.00.
- **State Behavior**: Component immediately triggers an Error Fallback. Executive dashboards are hidden for the affected component.
