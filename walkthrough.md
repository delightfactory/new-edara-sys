# Phase 1: Analytics Foundation Closeout

> [!IMPORTANT]
> The Phase 1 UI Scope explicitly **includes only**:
> - Sales Revenue views
> - AR creation / receivables views
> - Treasury cashflow views
> - Customer health views
> - System Trust/Freshness states
> 
> It explicitly **excludes**:
> - Accounting P&L
> - Managerial P&L
> - Financial-ledger-driven executive profitability surfaces
> (These will be certified independently in later phases).

> [!NOTE]
> **Semantic Definition: "VERIFIED" on Treasury**
> The `VERIFIED` state for true treasury cashflow indicates that the metrics exactly match operational execution records tracked physically in EDARA (`vault_transactions` and `custody_transactions`). This signifies internal absolute systemic alignment, not an external independent 3rd-party financial audit.

## Final Closeout Matrix

| Item | Fixed? | File Modified | Effect on Final Certification |
|---|---|---|---|
| P1-A: Return Tax Formula Alignment | **YES** | `76_analytics_incremental_jobs.sql` | Aligns analytical tax deductions with GL proportion exactly (`subtotal/tax_amount`), preventing systematic drift in tax mode. |
| Customer Health Recency Null Semantics | **YES** | `76_analytics_incremental_jobs.sql` | `recency_days` is now strictly `NULL` for customers with no sales. New customers are not falsely flagged as `is_dormant`. |
| Add Explicit REVOKE on Sensitive Dimensions | **YES** | `75_analytics_schema_wave1.sql` | Proactive security posture. Direct queries to `dim_product`, `dim_customer`, etc. are blocked at the DB level for `authenticated`. |
| Finalize Treasury Verification Label Semantics | **YES** | `walkthrough.md`, `task.md` | Contractually isolates the scope of "Treasury Verified" to mean 100% matched with Vault/Custody Systemic Truth. |
| Lock Phase-1 Dashboard Scope | **YES** | `walkthrough.md`, `task.md` | Excludes profitability and broader P&L scopes strictly until their data origins are built and double-reviewed. |

## What Changed:
- `supabase/migrations/75_analytics_schema_wave1.sql`: Added explicit schema-native `REVOKE SELECT` statements blocking all dimensions from frontend users.
- `supabase/migrations/76_analytics_incremental_jobs.sql`:
  1. Updated `internal_refresh_fact_sales_daily_grain` return CTE to compute precise return tax deductibles using `NULLIF(so.subtotal, 0)` exactly like `confirm_sales_return()`.
  2. Updated `internal_refresh_snapshot_customer_health` to return `NULL` for `recency_days` on zero historical sales + prevented false `is_dormant = true`.

*(Files copied to project root for direct review).*
