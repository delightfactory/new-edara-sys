# KPI Truth Dictionary - FINAL V5

This document strictly defines KPIs using verified pure SQL relationships, ensuring explicit Tax alignment, definitive AR attribution handling, and exact Invoice vs Credit portion splits.

## 1. Sales & Revenue

### Invoice Gross Sales (Tax Inclusive)
- **Business Definition**: Total invoice value billed to the customer including taxes, irrespective of whether it was paid in cash on delivery or deferred to AR.
- **SQL Formula**: `SUM(total_amount)` from `sales_orders` WHERE `status IN ('delivered', 'completed')`.
- **Grain**: Order level.
- **Primary Source**: `sales_orders`.
- **Independent Validation**: Matches the aggregate DEBIT side of the exact `journal_entries` linked to the sales. (Because cash terms redirect to Treasury and credit terms redirect to AR).
- **Type**: Gross / Tax-Inclusive.
- **Confidence Level**: `verified-operational`

### AR Debt Creation / Credit Sales Portion
- **Business Definition**: The exact, specific portion of the sales orders that increases the customer's Accounts Receivable debt (i.e. deferred payment).
- **SQL Formula**: `SUM(credit_amount)` from `sales_orders` WHERE `status IN ('delivered', 'completed')`.
- **Grain**: Order level.
- **Primary Source**: `sales_orders`.
- **Independent Validation**: Matches exclusively and exactly the total AR Debit lines injected into the `customer_ledger` representing these invoices.
- **Type**: Gross / Accrual / Sub-ledger Increment.
- **Confidence Level**: `official`

### Recognized Sales Revenue (Tax Exclusive)
- **Business Definition**: The actual revenue recognized by the business, explicitly excluding collected tax liabilities.
- **SQL Formula**: `SUM(total_amount - tax_amount)` from `sales_orders` WHERE `status IN ('delivered', 'completed')`.
- **Grain**: Order level.
- **Primary Source**: `sales_orders`.
- **Independent Validation**: Journal Entries explicitly mapping to the Sales Revenue (`chart_of_accounts` Revenue nodes) which excludes the tax account.
- **Type**: Gross / Accrual / Tax-Exclusive.
- **Confidence Level**: `official`

### Net Revenue After Returns (Tax Exclusive)
- **Business Definition**: The final retained revenue of the business after all returned goods have been processed, excluding prior taxes.
- **SQL Formula**: `SUM(so.total_amount - so.tax_amount) - SUM(sr.total_amount - sr.tax_amount)` via confirmed returns.
- **Primary Source**: `sales_orders` / `sales_returns`.
- **Type**: Net / Accrual / Tax-Exclusive.
- **Confidence Level**: `official`

## 2. Liquidity & Collections

### Cash Inflow (Vault Level)
- **Business Definition**: All periodic physical cash/bank additions deposited, excluding opening accounts balances.
- **SQL Formula**: `SUM(amount)` from `vault_transactions` WHERE `type IN ('deposit', 'collection')` (Note: `opening_balance` is separated into its own Position KPI).
- **Primary Source**: `vault_transactions`.
- **Type**: Gross / Cash.
- **Confidence Level**: `official`

### AR Collections (Cashflow Lens)
- **Business Definition**: Cash collected directly against accounts receivable, processed by the date the cash was received.
- **SQL Formula**: `SUM(payment_receipts.amount)` (status='confirmed') - `SUM(sales_returns.total_amount)` (for cash refunds).
- **Attribution Rule**: Assigned to `receipt.created_at`.
- **Independent Validation**: Matches credits explicitly logged in `customer_ledger` minus credit memos.
- **Type**: Net / Cash against AR.
- **Confidence Level**: `verified-operational`

### AR Collections (Target Attribution Lens)
- **Business Definition**: Cash collected against receivable debt, mapped backward to the date the original sale occurred to measure cohort conversion.
- **SQL Formula**: `SUM(payment_receipts.amount)` minus cash refunds on same order.
- **Attribution Rule**: Inherits the `delivered_at` date of the `sales_order` linked to the `payment_receipts.sales_order_id`.
- **Type**: Net / Cohort Attribution.
- **Confidence Level**: `verified-operational`

## 3. Profitability

### Accounting P&L
- **Business Definition**: Official financial profit verified by double-entry bookkeeping.
- **SQL Formula**: `SUM(debit - credit)` for Revenue, COGS, and Expenses via `journal_entries`.
- **Primary Source**: `journal_entry_lines`, `chart_of_accounts`.
- **Type**: Net / Accrual / Tax-Exclusive.
- **Confidence Level**: `official`

### Managerial P&L
- **Business Definition**: Analytical profit margin per invoice/item guiding sales initiatives.
- **SQL Formula**: `Recognized Sales Revenue (Tax Exclusive) - Approximate COGS` (Priority: `sales_order_items.unit_cost_at_sale` if available, falling back to `products.cost_price` as a lower-confidence proxy).
- **Caveat**: Utilizing `products.cost_price` introduces historical distortion. It is strictly a fallback until the actual `unit_cost_at_sale` mapping is fully mature and guaranteed by a valuation layer.
- **Type**: Net / Accrual.
- **Confidence Level**: `approximate / operational-only`
