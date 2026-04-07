# EDARA Analytics Engine - Incremental Jobs Design (Revised V3)

## 1. Incremental Refresh Design Spec & Job Boundaries

### 1.1 Source Mapping
Operations read exclusively from verified operational entities with explicit and accurate filtering rules.
- `fact_sales_daily_grain`: `sales_orders` (filter: `status IN ('delivered', 'completed')`), `sales_order_items`.
- `fact_ar_collections_by_receipt_date`: `payment_receipts` (filter: `status = 'confirmed'`), balanced against `vault_transactions` and `custody_transactions` (for cash refunds).
- `fact_ar_collections_attributed_to_origin_sale_date`: `customer_ledger` (filter: `type = 'credit'` AND `allocated_to IS NOT NULL` AND `source_type = 'payment_receipt'`), `payment_receipts`, `sales_orders`.
- `fact_financial_ledgers_daily`: `journal_entries` (filter: `status = 'posted'`), `journal_entry_lines`.
- `snapshot_customer_health`: `sales_orders`, `customer_ledger`.

#### Collections Net Logic
The `fact_ar_collections_by_receipt_date` represents **net collection**. To achieve true net, we calculate the difference between gross inbound receipts and outbound cash refunds exactly as follows:
- **Gross Collections**: Sourced from `payment_receipts` matching `status = 'confirmed'`.
- **Cash Refund Source Tables**: Both `vault_transactions` and `custody_transactions`.
- **Cash Refund Exact Filters**:
  - For `vault_transactions`: `type = 'withdrawal'` AND `reference_type = 'sales_return'`.
  - For `custody_transactions`: `type = 'expense'` AND `reference_type = 'sales_return'`.
- **Rule Distinguishing Cash vs. Credit Return**:
  - *Credit Return*: A sales return that purely offsets the customer's ledger (logged via `customer_ledger` as `type = 'credit'` with `source_type = 'sales_return'`). Because no cash was disbursed from the treasury, it is **excluded** from cash collections logic.
  - *Cash Refund*: A physical transaction disbursing cash back to the customer. It is logged in `vault_transactions` as a `withdrawal` tied to `reference_type = 'sales_return'`. It strictly reduces net liquidity.
- **Exact Subtraction Formula**:
  `Net Collections = SUM(gross_receipts.amount) - (COALESCE(SUM(vault_refunds.amount), 0) + COALESCE(SUM(custody_refunds.amount), 0))` (grouped by the target execution date bucket).

### 1.2 Dependency-Aware Late-Arriving Event Strategy
The architecture relies on an intelligent **Watermark & Dependency Tracking** model, NOT a blind rolling window.
1. **Detect Changes**: A lightweight `detect_affected_dates(p_last_watermark)` function scans the `updated_at` timestamps of the source tables (`sales_orders`, `payment_receipts`, etc.).
2. **Derive Dates**: If a `sales_order` from 30 days ago was updated (e.g., status changed to `cancelled`), the function extracts `DATE(delivered_at)` or `order_date`.
3. **Targeted Rebuild**: The incremental job receives exactly the impacted `DATE` array. It rebuilds only the buckets corresponding to those specific historical dates.
4. **Safety Net Only**: Scheduled sweeps are run merely to patch edge cases (like direct manual DB fixes that skipped triggers), assuring gapless data over a minimal window.

### 1.3 ETL Transaction & Failure Semantics
To ensure `RUNNING` or `FAILED` states are irrevocably recorded even when aggregating logic fails, we employ a native Savepoint pattern inside the wrapper procedure:
```sql
-- Wrapper pattern pseudo-code guarantees log persistence
PROCEDURE refresh_fact_sales_wrapper() ...
BEGIN
  INSERT INTO etl_runs (id, status) VALUES (v_id, 'RUNNING');
  COMMIT; -- Explicit commit to persist RUNNING (Supported in PG11+ Procedures)
  
  BEGIN
    CALL internal_refresh_sales(v_dates_array);
    UPDATE etl_runs SET status = 'SUCCESS' WHERE id = v_id;
    COMMIT;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK; -- rollback bad aggregations
    UPDATE etl_runs SET status = 'FAILED', log_output = ... WHERE id = v_id;
    COMMIT;
  END;
END;
```

---

## 2. Fact Cleanup Policy & Upsert Semantics

When historical data is updated (e.g., a delivered order is cancelled or a receipt is bounced), the corresponding analytics grain might disappear entirely. Applying an `UPSERT` without cleanup would leave orphaned grains artificially inflating historical totals.

**Final Decision: Pre-Delete Date Buckets (DELETE Stale Rows)**
Orphaned grains cannot be handled blindly by `UPSERT` nor overwritten with zeros (`tax_exclusive_amount = 0` creates sparse index bloat). Thus, the exact rebuild window is purged prior to insertion.

#### Table-Specific Cleanup Matrix

The deletion logic is isolated per table based on its precise primary date grain boundary:

- `fact_sales_daily_grain`:
  `DELETE FROM analytics.fact_sales_daily_grain WHERE date = ANY(p_target_dates);`
- `fact_ar_collections_by_receipt_date`:
  `DELETE FROM analytics.fact_ar_collections_by_receipt_date WHERE receipt_date = ANY(p_target_dates);`
- `fact_ar_collections_attributed_to_origin_sale_date`:
  `DELETE FROM analytics.fact_ar_collections_attributed_to_origin_sale_date WHERE origin_sale_delivered_at = ANY(p_target_dates);`
- `fact_financial_ledgers_daily`:
  `DELETE FROM analytics.fact_financial_ledgers_daily WHERE date = ANY(p_target_dates);`
- `snapshot_customer_health`:
  `DELETE FROM analytics.snapshot_customer_health WHERE as_of_date = ANY(p_target_dates);`

### 2.1 The `fact_sales_daily_grain` Reference Pattern
```sql
CREATE OR REPLACE PROCEDURE analytics.internal_refresh_fact_sales(p_target_dates DATE[])
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- 1. Fact Cleanup Policy: Explicit Pre-Delete of the targeted window
  DELETE FROM analytics.fact_sales_daily_grain 
  WHERE date = ANY(p_target_dates);

  -- 2. Targeted Extraction & Aggregation
  WITH aggregated_sales AS (
    SELECT 
      DATE(so.delivered_at) as sale_date,
      so.customer_id,
      sol.product_id,
      so.rep_id, -- Maps identically to auth.uid() / profiles.id
      -- Explicit derivation based on schema: line_total (net) - tax_amount = tax_exclusive
      SUM(sol.line_total - COALESCE(sol.tax_amount, 0)) as tax_excl_amt,
      SUM(COALESCE(sol.tax_amount, 0)) as tax_amt,
      SUM(sol.quantity) as qty
    FROM public.sales_orders so
    JOIN public.sales_order_items sol ON so.id = sol.order_id
    WHERE DATE(so.delivered_at) = ANY(p_target_dates)
      AND so.status IN ('delivered', 'completed') -- Covers operational valid delivery states
    GROUP BY 1, 2, 3, 4
  )
  -- 3. Idempotent Upsert leveraging explicit grain constraints
  INSERT INTO analytics.fact_sales_daily_grain 
    (date, customer_id, product_id, rep_id, tax_exclusive_amount, tax_amount, gross_quantity)
  SELECT sale_date, customer_id, product_id, rep_id, tax_excl_amt, tax_amt, qty 
  FROM aggregated_sales
  ON CONFLICT (date, customer_id, product_id, rep_id) 
  DO UPDATE SET
    tax_exclusive_amount = EXCLUDED.tax_exclusive_amount,
    tax_amount = EXCLUDED.tax_amount,
    gross_quantity = EXCLUDED.gross_quantity,
    updated_at = now();

END;
$$;
```

---

## 3. Concurrency, Performance & Scheduling Plan

1. **Job Execution Hierarchy**:
   Jobs run via `pg_cron` under `service_role`.
   - *Phase 1*: `fact_sales_daily_grain` & `fact_financial_ledgers_daily` (core base).
   - *Phase 2*: `fact_ar_collections_by_receipt_date` (requires up-to-date receipts).
   - *Phase 3*: `fact_ar_collections_attributed_to_origin_sale_date` (requires ledgers and sales order mapping).
   - *Phase 4*: `snapshot_customer_health` (runs last relying on base facts).

2. **Chunking & Concurrency Lock Policy**:
   - Updates are chunked to a maximum of 7-day batches to protect temp memory. 
   - We utilize `pg_try_advisory_xact_lock` during procedure execution on logical job keys to eliminate race conditions if cron sweeps while a targeted rebuild is ongoing.

---

## 4. Double Review Verification Contract

The integration mapping aligns meticulously with the Double Review Engine:

1. **Family A (Revenue) = `POSTING_CONSISTENCY_ONLY`**:
   `fact_sales_daily_grain.tax_exclusive_amount` is checked against `journal_entry_lines` (Revenue GL Accounts). This proves system parity but is **NOT** `VERIFIED` truth because both originate from the identically operational invoice creation trigger.
   
2. **Family B (AR Creation) & Family D (Collections) = `VERIFIED`**:
   Values are independently validated against distinct treasury deposits or sub-ledger operational allocations. 

3. **Drift Handling**: If any comparison breaches `0.00`, the `etl_runs` status is immediately flagged as `BLOCKED` causing UI requests for that metric to fail safely.

---

## 5. Reporting UX State Contract

The frontend must adhere to strict display semantics when presenting analytics:

| Internal State | UI Display Label | Visual Behavior |
| :--- | :--- | :--- |
| `VERIFIED` | "مُعتمد مالياً" (Financially Verified) | Green check mark. Values displayed prominently. |
| `POSTING_CONSISTENCY_ONLY` | "متسق دفترياً" (System Consistent) | Soft blue icon. Displays normally but hints it shares origins with operational logs. |
| `RECONCILED_WITH_WARNING` | "تحذير: كسور" (Warning: Rounding) | Orange highlight. Displayed but flags fractional deviations. |
| `OPERATIONAL_ONLY` | "تقديري" (Approximate/Operational) | Gray icon. Permanently fixed warning ensuring users know this lacks accounting grade exactness. |
| `BLOCKED` | "معلق للمراجعة" (Blocked) | **Redacted value**. Disables the chart/number entirely, replacing it with an error skeleton and contact support badge. |

**Freshness Stamp**:
All charts must explicitly render the timestamp of the last successful `etl_runs` related to their specific dimension. Empty or Error states immediately revert to skeletons or `BLOCKED` visuals.
