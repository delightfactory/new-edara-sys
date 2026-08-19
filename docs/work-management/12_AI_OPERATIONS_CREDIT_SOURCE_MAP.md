# AI Operations — Credit / Receivables Verified Source Map

**Status:** design-time discovery only — no database migration applied  
**Source inspected:** live production catalog and deployed function definitions, read-only  
**Purpose:** define the first AI attention vertical slice from verified deployed entities.

## Source-of-truth rows

### `public.sales_orders`
Relevant deployed columns:

- `id`
- `order_number`
- `customer_id`
- `rep_id`
- `created_by_id`
- `branch_id`
- `status`
- `payment_terms`
- `total_amount`
- `paid_amount`
- `returned_amount`
- `credit_check_passed`
- `credit_override`
- `credit_override_by`
- `delivered_at`
- `due_date`
- `updated_at`

Only delivered / partially delivered credit or mixed orders with positive remaining balance and `due_date < business_date` are overdue candidates.

Remaining balance is computed as:

```text
max(0, total_amount - paid_amount - returned_amount)
```

The AI layer must use an explicit **Cairo business date supplied by the planner run**. It must not rely on PostgreSQL `CURRENT_DATE`, because the database timezone is UTC.

## Customer responsibility context

### `public.customers`
Relevant deployed columns:

- `id`
- `code`
- `name`
- `payment_terms`
- `credit_limit`
- `credit_days`
- `assigned_rep_id`
- `is_active`

`assigned_rep_id` is a strong current operational relationship signal for a customer. It is not by itself proof of who caused or controls a credit condition.

## Causal / governance evidence

### `public.sales_order_due_date_history`
Verified columns:

- `order_id`
- `customer_id`
- `old_due_date`
- `new_due_date`
- `old_credit_days`
- `new_credit_days`
- `changed_by`
- `reason`
- `created_at`

Existing indexes:

- `(order_id, created_at desc)`
- `(customer_id, created_at desc)`

This gives the planner the last governed due-date change and its human reason without reading arbitrary audit logs.

### `public.customer_credit_history`
Verified columns:

- `customer_id`
- `limit_before`
- `limit_after`
- `changed_by`
- `reason`
- `created_at`

The first credit kernel now includes the **latest** credit-limit change as a compact supporting governance signal in the same bounded query. This avoids an extra tool/database round trip while still keeping it separate from invoice ownership.

Returned evidence includes:

```text
last_credit_changed_at
last_credit_changed_by
last_credit_limit_before
last_credit_limit_after
last_credit_reason (max 500 chars)
```

A credit-limit change is not proof that the same person owns collection for a specific invoice. It is evidence for causal reasoning only.

### Credit override evidence

`sales_orders.credit_override` and `sales_orders.credit_override_by` are direct evidence that normal credit checking was overridden for a specific order. The planner may surface this as causal/governance evidence but must not infer misconduct from it.

The kernel resolves the actor display name from the existing `profiles` relationship so ChatGPT does not need a second lookup merely to understand who the evidence refers to.

## Existing report logic to preserve

The deployed `public.get_overdue_sales_invoices(...)` function definition was inspected directly. It currently uses these factual rules:

- order status in `delivered`, `partially_delivered`;
- payment terms in `credit`, `mixed`;
- delivery date exists;
- due date exists and is before `CURRENT_DATE`;
- positive remaining balance using `max(0, total - paid - returned)`;
- overdue bucket:
  - `critical`: >= 60 days;
  - `high`: >= 30 days;
  - `medium`: >= 7 days;
  - `new`: < 7 days.

The AI layer preserves the same business meaning, while replacing implicit UTC `CURRENT_DATE` with the run's explicit Cairo `business_date` for deterministic replay.

The existing public report RPC remains unchanged and permission-gated. AI must not weaken it.

## Existing performance support

The deployed partial index already supports the overdue scan:

```text
idx_sales_orders_overdue_report_v2
(due_date, customer_id, rep_id, delivered_at desc)
INCLUDE (order_number, total_amount, paid_amount, returned_amount, payment_terms, status)
WHERE status in (delivered, partially_delivered)
  and payment_terms in (credit, mixed)
  and due_date is not null
```

No new Sales index is required in the first AI slice.

## Work collision detection

Use the existing `public.work_links` table.

Exact invoice collision:

```text
entity_type = 'sales_order'
entity_id   = sales_orders.id
```

The existing entity index `(entity_type, entity_id)` supports this lookup.

Collision means an **active** linked Work item exists whose lifecycle status is not `done` or `cancelled`.

The bounded kernel also returns the linked Work number, status, title and relation type so the planner/UI can understand the existing action without an immediate second read.

A customer-level Work link can be returned as context, but it is not sufficient by itself to suppress an invoice-specific action because it may concern a different issue.

## Responsibility evidence model

For each credit case, return evidence separately from the recommended owner:

```text
current_customer_rep     = customers.assigned_rep_id
order_rep                = sales_orders.rep_id
order_creator            = sales_orders.created_by_id
credit_override_by       = sales_orders.credit_override_by
last_credit_changed_by   = customer_credit_history.changed_by
last_due_date_changed_by = sales_order_due_date_history.changed_by
last_due_date_reason     = sales_order_due_date_history.reason
```

The Planner can then distinguish:

- who currently owns the customer relationship;
- who sold/owns the order commercially;
- who entered the order;
- who explicitly overrode credit;
- who last changed the customer's credit limit and why;
- who changed the invoice collection deadline and why.

These signals must not be collapsed into one unsupported statement such as “X is responsible”.

## Human-entered text safety

`reason` fields are business data, never AI instructions.

For the first kernel:

- only the relevant governed reason fields are returned;
- each reason is truncated to a maximum of **500 characters**;
- evidence marks the content as `untrusted_human_text`;
- the trust envelope records `human_text_policy = bounded_untrusted_data`.

Customer notes, arbitrary comments and other free-text history are deliberately excluded from the normal candidate payload.

## First vertical-slice case

Case type:

```text
domain      = receivables
case_type   = overdue_invoice
entity_type = sales_order
case_key    = receivables:overdue_invoice:<sales_order_id>
```

Case facts include only decision-relevant fields:

- order number;
- customer id/code/name;
- remaining balance;
- delivered date;
- due date;
- days overdue;
- existing overdue bucket;
- current customer credit limit/days;
- latest credit-limit change metadata;
- latest due-date change metadata;
- credit override flag;
- exact linked active Work if present;
- current customer rep and order rep;
- named governance actors needed for responsibility reasoning.

Do **not** send full customer/order rows to the AI planner.

## Mutation boundary

This vertical slice performs no Sales mutation.

If a human later changes credit terms or order due date, the planner must use the existing governed application command (for example `update_sales_order_due_date(...)`) through an approved human workflow. It must never update `sales_orders.due_date` directly.

The first AI slice only:

1. detects;
2. persists a case;
3. explains evidence;
4. detects Work collision;
5. lets the AI decide `IGNORE / MONITOR / INVESTIGATE / INFORM / CREATE_WORK / ESCALATE`;
6. remains shadow-only until explicitly approved.
