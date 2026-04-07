# Analytics Integrity and Trust Engine (Final Rewrite)

This plan implements the final strict backend specifications mandated for the EDARA Analytics and Reporting Engine. It ensures mathematical trust by enforcing the Double Review mechanism at the backend level, resolving join topologies, and securing the frontend exposure contract.

## 1. JOIN Refactoring: `fact_ar_collections_attributed`
**Problem**: The current implementation utilizes a correlated scalar subquery inside a `JOIN ON` clause (`cl.allocated_to IN (SELECT id FROM ... WHERE source_id = so.id)`), which causes severe optimizer degradation and violates relational patterns for the attribution logic.
**Solution**:
Refactor the queries to strictly use direct path joins:
```sql
FROM public.customer_ledger cl
JOIN public.customer_ledger invoice_cl ON cl.allocated_to = invoice_cl.id
JOIN public.sales_orders so ON invoice_cl.source_id = so.id 
WHERE invoice_cl.source_type = 'sales_order'
```
This applies to all attribution models inside the AR routines.

## 2. Complete Rewrite: `snapshot_customer_health`
**Problem**: Executing grouped functions inside the `SELECT` clause (Scalar Correlated Subqueries) per customer/date intersection limits scalability and induces N+1 row evaluation characteristics on the database engine.
**Solution**:
1. Remove all subselects.
2. Develop a `sales_history` Pre-Aggregation Common Table Expression (CTE).
3. Cross-join the discrete `dates_cross` against customers, then strictly `LEFT JOIN` the `sales_history` arrayed within the `90-day` lookback criteria relying purely on aggregate masks (`COUNT(...) FILTER`, `SUM(...) FILTER`, `MAX(...) FILTER`).

## 3. Double Review Verification Engine (Phase 1 Code)
**Problem**: The `Double Review` currently only lives as a specification (`analytics_double_review_spec.md`). It must be executed after the facts are calculated.
**Solution**:
1. **Schema Enhancements**: Update `analytics.etl_runs` status constraints in `75_analytics_schema_wave1.sql` to accept `POSTING_CONSISTENCY_ONLY`, `RECONCILED_WITH_WARNING`, and `PARTIAL_FAILURE`.
2. **Review Procedure**: Create `analytics.compute_double_review_trust_state(p_run_id UUID, p_job_name TEXT, p_target_dates DATE[])` that operates concurrently after the load:
   - For `fact_sales_daily_grain`: Diff Revenue (fact) against Accounting Ledger (GL income). Output -> `POSTING_CONSISTENCY_ONLY` (var = 0) or `BLOCKED`.
   - For `fact_ar_collections`: Diff Analytics net collections against Treasury Ledger. Output -> `VERIFIED` (var = 0) or `BLOCKED`.
3. Save explicit `drift_value`, `status`, and JSON context to `etl_runs`.

## 4. Secure Freshness & Trust Access Path
**Problem**: The frontend currently lacks a secure, non-admin way to understand if the data is stale, partial, or blocked. Exposing `etl_runs` tables directly is insecure.
**Solution**:
Create a secure RPC function:
```sql
CREATE OR REPLACE FUNCTION analytics.get_system_trust_state()
RETURNS TABLE (
  component_name text,
  status text,
  drift_value numeric,
  last_completed_at timestamptz,
  is_stale boolean
)
LANGUAGE sql SECURITY DEFINER;
```
It returns only the most recent run state per `table_name` and safely evaluates if jobs have stalled.

## 5. GLOBAL_SWEEP Semantics
**Problem**: A master sweep currently reports `SUCCESS` even if an internal job fails, masking problems.
**Solution**:
Before resolving `GLOBAL_SWEEP` status, evaluate all children from that specific `sweep_id`. If `COUNT(status = 'FAILED' OR status = 'BLOCKED') > 0`, terminate as `PARTIAL_FAILURE` or `FAILED`.

## 6. Closing Trust Gaps (NULL collected_by)
**Problem**: If cash returns exist via Treasury processes missing a `payment_receipt`, the nested queries returning `collected_by` yield `NULL`.
**Solution**: 
Wrap the `rep_id / collected_by` extraction in `COALESCE(..., so.rep_id)` to gracefully attribute refunds to the origin sales representative if specific collection receipts are mysteriously absent from legacy data boundaries. Also, remove nonexistent `analytics.admin` mentions if present.

## User Feedback Resolved
The system will implement an explicit whitelist for GL Accounts to calculate exact double-review drift without inadvertently capturing COGS or non-revenue credits.

The mapping will be strict:
- `fact.tax_exclusive_amount` matches GL Account `4100` Credits (Sales Order).
- `fact.tax_amount` matches GL Account `2200` Credits (Sales Order).
- `fact.ar_credit_portion_amount` matches GL Account `1200` Debits (Sales Order).
- `fact.return_tax_exclusive_amount` matches GL Account `4200` Debits (Sales Return).

Additionally, any reliance on the `so.rep_id` fallback for `NULL collected_by` scenarios will safely trigger an explicit metadata warning alerting the analyst that the allocation is operational, not natively guaranteed by a receipt.
