# Analytics Security & Access Spec (Addendum)

## 1. Schema Security Posture
The `analytics` schema will be strictly locked down by default to prevent unauthorized operational leakage.
- **Default Action**: `REVOKE ALL ON SCHEMA analytics FROM PUBLIC;`
- **GRANT USAGE**: `authenticated`, `service_role`.
- **System Executive Role**: The `service_role` is the **only** role permitted to run the `SELECT/INSERT/UPDATE/DELETE` operations required by the scheduled refresh jobs (`pg_cron` or daemon). No standard user, no matter the permission, can trigger or calculate analytical refreshes directly via the application connection.

## 2. RLS Policies for Reporting Data Model
All tables (`fact_*`, `snapshot_*`, and materialized reconciliation views) within the `analytics` schema must have Row Level Security enabled. 

Access is evaluated through EDARA's native `check_permission()` function matched against the user's roles.
- `reports.view_all`: Bypasses rep/branch filters. User sees all facts and snapshots.
- `reports.sales`: Evaluates the `rep_id` on the fact tables. The user can only `SELECT` records where `rep_id = auth.uid()` (Identity Domain is strictly locked to `profiles.id` / User ID) OR branches they manage if they hold `reports.team_performance`.
- `reports.financial`: Evaluates access to ledger aggregations (`fact_financial_ledgers_daily` and P&L snapshots). Standard reps are blocked entirely.
- `reports.targets`: Allows reading cohort-attributed AR (`fact_ar_collections_attributed_to_origin_sale_date`) and `snapshot_target_gaps`.
- `reports.export`: Hard gate applied at the API/Application level to prevent downloading heavy extracts.

## 3. Remedy for Existing Open Reconciliations
The current `v_reconcile_*` views deployed in `59_finance_reconciliation_views.sql` are openly granted to `authenticated`. This is a severe financial security flaw.
- **Immediate Correction in Migration**:
  `REVOKE SELECT ON v_reconcile_customer_balances FROM authenticated;` (And all sibling views).
- **Corrected Access**: 
  Only users possessing `reports.financial` or `analytics.admin` should query these views. A dedicated read policy or a secure definer wrapper function validates the permission before returning rows.
