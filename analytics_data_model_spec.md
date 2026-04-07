# Reporting Data Model Spec - FINAL V5

## 1. Design Constraints
- **Absolute No Triggers**: Scheduled external jobs (`pg_cron` or daemon) will execute data refresh.
- **No Caches in Dimensions**: Dimensions strictly map attributes and foreign keys.

## 2. Dimensions
- `analytics.dim_date`: Generated calendar table.
- `analytics.dim_employee`: `SELECT id, user_id, full_name, branch_id, status FROM hr_employees`.
- `analytics.dim_customer`: `SELECT id, name, governorate_id, city_id, area_id FROM customers`. 
- `analytics.dim_product`: `SELECT id, name, category_id, brand_id FROM products`.

## 3. Facts
### `analytics.fact_sales_daily_grain`
- **Grain**: `date` (based on `delivered_at`) + `customer_id` + `product_id` + `rep_id`.
- **Facts**: 
  - `tax_inclusive_amount` (Invoice Total Value, split across cash & credit)
  - `ar_credit_portion_amount` (The exact slice generating Customer AR Debt)
  - `tax_exclusive_amount` (Recognized Revenue)
  - `tax_amount` (Tax Liability)
  - `return_tax_inclusive_amount`, `return_tax_exclusive_amount`
  - `net_tax_exclusive_revenue` (Net Revenue After Returns)
  - `net_quantity`

### AR Collections Split (Decision-Complete Design)
#### `analytics.fact_ar_collections_by_receipt_date`
- **Grain**: `receipt_date` + `customer_id` + `collected_by`.
- **Facts**: `receipt_amount`, `cash_refund_amount`, `net_collection`.

#### `analytics.fact_ar_collections_attributed_to_origin_sale_date`
- **Grain**: `origin_sale_delivered_at` + `customer_id` + `collected_by` + `original_rep_id`.
- **Facts**: `receipt_amount`, `cash_refund_amount`, `net_cohort_collection`.

### `analytics.fact_financial_ledgers_daily`
- **Grain**: `date` + `account_id`.
- **Facts**: `debit_sum`, `credit_sum`, `net_movement`.

## 4. Late-Arriving Events and Historical Rebuild Policy
The Analytics Engine must faithfully support back-attribution. A target collection made today for an invoice from October must retroactively update the `fact_ar_collections_attributed_to_origin_sale_date` for the October period.

**Policy Rules:**
1. **Watermark / Dependency Tracking**: The synchronization engine will query the operational audit/update log (`updated_at` on `sales_orders`, `sales_returns`, `payment_receipts`).
2. **Date Re-Calculation Window**: If a document updated in the last run traces back to an origin transaction date `X`, the engine will explicitly trigger a bounded recalculation for day `X` in all attributed Fact tables, regardless of how deep into the past `X` is.
3. **End-of-Month Deep Rebuild**: A scheduled off-peak complete rebuild of the trailing 12 months for active fiscal periods, functioning as a brute-force sweep to guarantee 100% data integrity continuously.

## 5. Snapshots (Nightly Point-in-Time)
### `analytics.snapshot_customer_health`
- Fields: `as_of_date`, `customer_id`, `recency_days`, `frequency_L90d`, `monetary_L90d`, `is_dormant`.
