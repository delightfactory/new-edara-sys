# Architecture Audit Report (Reporting & Analytics) - FINAL V5

## 1. Executive Summary
This document provides a strictly verified inventory of EDARA's database schema as it currently exists in the `supabase/migrations/` files, assessing its readiness for a scheduled, `pg_cron` (or external scheduler) driven Reporting/Analytics Engine.

## 2. Inventory of Confirmed Existing Entities
The following operational tables have been explicitly verified via the migration files as existing in the `public` schema and will be the sole sources for the Analytics Engine.

### Sales & Customers
- **Confirmed**: `sales_orders`, `sales_order_items`, `sales_returns`, `sales_return_items`, `customers`, `customer_ledger`.

### Finance & Accounting
- **Confirmed**: `chart_of_accounts`, `journal_entries`, `journal_entry_lines`, `payment_receipts`, `vaults`, `vault_transactions`, `custody_accounts`, `custody_transactions`.

### Inventory & Products
- **Confirmed**: `products`, `product_categories`, `brands`, `units`, `stock`, `stock_movements`, `stock_transfers`, `stock_adjustments`.

### Target Engine
- **Confirmed**: `targets`, `target_progress`.

### Existing Views
- **Confirmed**: `v_plan_daily_summary`, `v_target_status`, `v_rep_performance`, `v_reconcile_customer_balances`, `v_reconcile_supplier_balances`, `v_reconcile_vault_balances`, `v_reconcile_ar_control_account`, `v_reconcile_ap_control_account`, `v_reconcile_treasury_control_accounts`.

## 3. Do Not Use / Forbidden Source Table

| Concept/Field | Why Forbidden for Reporting? | Mandatory Alternative |
| --- | --- | --- |
| `current_balance` (Customers, Vaults, Suppliers) | Fast cache for operations, vulnerable to race conditions. | `customer_ledger` / `vault_transactions` |
| `stock` (table acting as current balance) | Cannot provide historical point-in-time snapshots easily. | `stock_movements` |
| `v_rep_performance` | Mixed grain definitions not strictly bound by ledger constraints. | A strictly built `fact_sales` and `fact_activities` |
| Generalized "Gross Sales" | Misses the critical accounting split between tax-inclusive AR debt and tax-exclusive mapped GL revenue. | Strict dual-metric tracking (Tax Inclusive vs Tax Exclusive). |
| `target_progress` as validation | Targets are business goals, not an independent source of financial truth. | Trial Balance (GL/JE) |

## 4. Mapping Future Reports to True Source
| Report | Verified Source of Truth | Notes & Constraints |
| --- | --- | --- |
| **Recognized Sales Revenue (Tax Exclusive)** | `sales_orders` (total_amount - tax_amount) | Maps exactly to GL Revenue accounts. |
| **AR Debt Creation (Credit Portion)** | `sales_orders.credit_amount` | Maps exactly to `customer_ledger` debit lines. |
| **Invoice Gross Sales (Tax Inclusive)** | `sales_orders.total_amount` | Does NOT map solely to AR. Cash portion hits vaults. Reconciled via full accounting journal debits. |
| **AR Collections (Cashflow Date)** | `payment_receipts` by `created_at` | Used for standard treasury reporting. |
| **AR Collections (Origin Sale Date)** | `payment_receipts` attributed backward to `sales_order.delivered_at` | Crucial for Target progress alignment. Requires robust late-arriving handler. |
| **Accounting P&L**| `journal_entry_lines` + `chart_of_accounts` | None |
| **Managerial P&L**| Net Sales - `cost_price` proxy | **Major GAP**: Managerial P&L is explicitly operational/approximate until a valuation layer is built. |

## Appendix: Unsupported Assumptions Removed
*(Maintained from prior versions with exact tax and billing adjustments)*
1. Removed assumption of `stock_summaries` table.
2. Removed assumption of `products.current_stock`.
3. Removed arbitrary permissions (`analytics.finance_view` & `analytics.sales_view`).
4. Removed `current_rep()` functions.
5. Removed trigger-based invalidation mechanism in favor of chron scheduling.
6. Removed `current_balance` from `dim_customer`.
7. Removed the naive 30-day lookback strategy, replacing it with explicit Late-Arriving Events policy.
8. Refused `target_progress` as an independent reconciliation source for financial numbers.
9. Removed arbitrary `base_cost` assumption.
10. Removed `cost_center_id` from ledger facts.
11. **(V5) Clarified Invoice Settlement Limits**: We expressly removed the assumption that `sales_orders.total_amount` maps 1:1 to `customer_ledger`, as partial cash terms split the invoice settlement between Vaults and AR.
