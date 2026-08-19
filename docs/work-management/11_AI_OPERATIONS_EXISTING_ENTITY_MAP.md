# AI Operations Planner — Verified Existing Entity Map

**Status:** Live-schema/repository discovery gate — no AI migration applied  
**Branch:** `feature/work-management`  
**Database inspected:** `NEW-EDARA-SYS` production, read-only  
**Purpose:** make implementation decisions from verified existing objects rather than expected names or remembered architecture.

---

## 1. Discovery rule

Before adding an AI-planner object, verify whether the capability already exists under another name in the live PostgreSQL catalog and current branch.

The live catalog is authoritative for deployed structure. Repository migrations and TypeScript services are used to understand intent and current application usage.

No AI migration may introduce a parallel capability merely because an expected object name was not found.

---

## 2. Correction from discovery

A generic Work-to-business-entity link mechanism **already exists**. Its deployed name is:

```text
public.work_links
```

It must be reused. No `work_entity_links` or replacement link table is required.

### Current columns

```text
id uuid
work_item_id uuid -> work_items(id) ON DELETE CASCADE
entity_type text
entity_id uuid
relation_type text default 'relates_to'
label text nullable
created_by_user_id uuid -> profiles(id) ON DELETE SET NULL
created_at timestamptz
```

### Existing integrity/indexing

- unique `(work_item_id, entity_type, entity_id, relation_type)`;
- index `(entity_type, entity_id)`;
- index `(work_item_id)`;
- RLS enabled;
- authenticated users may only SELECT links for Work they can already see;
- browser mutations are RPC-controlled.

### Existing supported entity types

`private.work_link_entity_table()` currently validates:

```text
customer          -> public.customers
sales_order       -> public.sales_orders
payment_receipt   -> public.payment_receipts
supplier          -> public.suppliers
purchase_invoice  -> public.purchase_invoices
product           -> public.products
warehouse         -> public.warehouses
employee          -> public.hr_employees
activity          -> public.activities
target            -> public.targets
```

`private.work_link_entity_exists()` verifies that the referenced business row actually exists.

### Existing commands/application API

- `public.work_add_link(...)`
- `public.work_remove_link(...)`
- `src/features/work/extensions-api.ts`
  - `listWorkLinks()`
  - `addWorkLink()`
  - `removeWorkLink()`

Therefore AI duplicate/collision detection can query existing Work by `work_links.entity_type/entity_id`, including manually created Work, instead of relying only on AI source keys.

---

## 3. Verified Work lifecycle model

The **current deployed** `work_item_status` enum is:

```text
draft
open
in_progress
waiting
pending_approval
done
cancelled
```

`blocked`, `overdue`, `stale`, `at-risk`, and `escalated` are operational flags, not lifecycle statuses.

This is confirmed by the deployed enum and `20260813194600_work_management_state_model_correction.sql`.

### Current system provenance capability

Existing deployed values include:

```text
work_actor_kind: user | system
work_source_kind: manual | request_intake | workflow | recurrence | system
```

`work_items.creator_user_id` is nullable, `source_key` exists, and `(source_kind, source_key)` is uniquely indexed when applicable.

`private.work_append_system_event(...)` already writes append-only system events without impersonating a human actor.

No AI user/profile, AI creator column, or Work enum extension is required.

---

## 4. Verified system-created Work precedent

`private.work_generate_recurrence_occurrence(...)` is an existing production pattern for trusted system-side Work generation.

It already demonstrates:

- deterministic source keys;
- owner/assignee validation before insert;
- active-HR placement lookup for branch/department;
- `source_kind='recurrence'`;
- direct creation of an `open` Work item by a trusted private routine;
- append-only system provenance event;
- idempotent occurrence handling;
- explicit failed occurrence state instead of silent loss.

The AI Work bridge should follow this established pattern rather than wrapping the human `work_create_task()` command with a fake user identity.

---

## 5. Verified Work responsibility/availability surfaces

Existing deployed helpers include:

- `public.work_get_responsibility_snapshot(work_item_id)`;
- `public.work_list_assignment_candidates(...)`;
- `public.work_list_item_people_candidates(...)`;
- `public.work_list_request_assignment_candidates(...)`;
- `public.work_list_continuity_candidates(...)`;
- `public.work_resolve_assignment_route(target_user_id)`;
- `public.work_list_orphaned_assignments()`;
- `public.work_get_supervisor_overview(...)`;
- `private.work_actor_is_active(...)`;
- `private.work_operational_item_is_blocked(...)`;
- Work operational flag views/scanners.

The AI layer must reuse these semantics where they fit and must not independently invent a second definition of an active Work actor, blocked state, or organizational assignment route.

Causal business responsibility remains a separate AI problem because these Work helpers describe Work authority/availability, not who caused or controls an external business condition.

---

## 6. Verified Work collision/dependency surfaces

### Existing entity collision path

Use `public.work_links(entity_type, entity_id)` to find current Work attached to the same customer/order/payment/etc.

A case is not considered collision-free merely because an AI source key is absent.

### Existing Work dependencies

`public.work_dependencies` currently contains both:

- `dependency_type work_dependency_type`;
- `dependency_strength work_dependency_strength` (`hard`/`soft` in the application contract);
- resolution timestamps/reason.

AI planning must read the current deployed shape, not the original foundation migration shape alone.

---

## 7. Verified Receivables/Credit source capabilities

Existing production reporting/operational functions include:

- `get_overdue_sales_invoices(...)`;
- `get_credit_open_orders_v2(customer_id)`;
- `get_credit_portfolio_kpis()`;
- `get_filtered_credit_kpis(...)`;
- `get_filtered_credit_customers(...)`;
- `get_customer_ar_aging(customer_id)`;
- `get_customer_360_kpis(customer_id)`;
- `get_rep_credit_commitment_report()`;
- `get_rep_credit_commitment_detail(rep_id)`;
- `customer_reengagement_list/summary(...)`.

### `get_overdue_sales_invoices(...)` current factual semantics

It already calculates from live `sales_orders + customers`:

- remaining invoice balance;
- assigned customer rep;
- order rep;
- due date;
- days overdue and overdue bucket;
- last due-date change timestamp/reason;
- aggregate overdue counts/amount.

It is a human-facing `SECURITY DEFINER` RPC that requires `auth.uid()` and existing customer/sales permissions. **Do not weaken this authorization for AI.**

The AI implementation should preserve/reuse the business calculation through a private/internal kernel or an equivalent bounded internal query, while leaving the public RPC contract unchanged.

### Verified causal credit evidence

Live schema contains:

```text
sales_orders.created_by_id
sales_orders.rep_id
sales_orders.credit_override_by
customers.assigned_rep_id
customer_credit_history.changed_by
customer_credit_history.reason
sales_order_due_date_history.changed_by
sales_order_due_date_history.reason
```

`update_sales_order_due_date(...)` is the governed human command for due-date changes. It requires `customers.credit.update`, locks the order, validates delivery/open balance/credit terms, records `changed_by + reason`, and resolves the deterministic overdue alert when the new due date is no longer overdue.

The AI planner must never mutate a due date directly.

---

## 8. Verified existing generic configuration objects

Existing generic configuration tables include:

- `public.company_settings` — public/application company key-value settings;
- `public.internal_config` — internal low-level configuration;
- `public.work_operational_settings` — Work operational thresholds/cooldowns.

None of these represents planner run state, immutable AI snapshots, AI cases, governed operational context, or AI decision feedback.

AI planner runtime/governance state should therefore remain in a dedicated `ai_ops` boundary rather than overloading these existing settings tables.

---

## 9. Verified absence of an AI planner runtime boundary

At inspection time:

- schema `ai_ops` does not exist;
- no planner-run table exists;
- no generic operational-context table exists;
- no generic AI decision/feedback table exists.

Analytics has `etl_runs` and domain snapshots, and Work has `work_workflow_runs`, but their semantics are specific to ETL/workflows and must not be repurposed as AI-planner run state.

This is a verified capability gap suitable for an additive isolated migration.

---

## 10. Existing Work trigger surface

Current Work triggers are limited to established Work concerns such as:

- updated-at maintenance;
- immutable Work events;
- Work notification dispatch from appended events;
- workflow completion validation;
- published approval/workflow definition immutability.

The initial AI implementation must add **no trigger** to Sales, Customers, Inventory, HR, Visits, or existing Work source tables.

Internal triggers on new `ai_ops` tables are allowed only when they enforce planner-local invariants/immutability and have no synchronous effect on transaction modules.

---

## 11. Implementation consequences

The first implementation must therefore:

1. create only the missing `ai_ops` planner-state boundary;
2. reuse `work_links` for business-entity collision detection;
3. reuse existing Work active-actor/operational semantics;
4. use system provenance already supported by Work;
5. preserve existing report authorization and extract only a private internal read path where necessary;
6. avoid any Work schema ALTER for AI provenance/linking;
7. avoid source-table triggers and new source-table indexes in the foundation;
8. treat the live deployed schema as authoritative if an old migration differs from current shape.

---

## 12. Gate

No AI migration should be authored against an assumed entity name. For every subsequent vertical slice, first record:

```text
existing source tables/views/functions
current deployed columns/types
existing indexes
existing permission boundary
existing mutation commands
existing Work link entity type (if any)
source-of-truth semantics
```

Only then decide what is genuinely missing.
