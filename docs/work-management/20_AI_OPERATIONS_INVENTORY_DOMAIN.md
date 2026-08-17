# AI Operations — Inventory Domain

**Status:** branch implementation artifacts only — no production AI Operations migration applied  
**Branch:** `feature/work-management`  
**Domain:** `inventory`  
**Acceptance:** follows `18_AI_OPERATIONS_BUILD_ALL_DOMAINS_ACCEPTANCE_STRATEGY.md`.

## 1. Production reality used by this domain

Inventory v1 was designed after read-only inspection of the deployed NEW-EDARA-SYS database rather than from a generic inventory model.

The deployed sources used are:

- `public.stock` for current quantity, reservations, available quantity and WAC;
- `public.stock_movements` for actual movement history;
- `public.stock_transfers` / `stock_transfer_items` for inter-warehouse supply movement;
- `public.warehouses` / `warehouse_managers` for location and responsibility;
- `public.products` for active product identity;
- existing Work links and AI Ops governed operational context.

Important observed constraints:

- none of the 140 active products currently has an operational `min_stock_level`, so v1 must not fabricate a reorder rule from that field;
- recent real outbound activity provides a usable demand signal;
- current production includes real stockouts/low-cover positions and at least one materially stalled `in_transit` transfer;
- warehouse responsibility data is not uniformly singular: some warehouses have no declared manager while others have multiple rows marked primary;
- batch structures exist, but positive operational batch balances are not currently populated enough to support a trustworthy expiry Case.

These observations validate which Case families are real today; counts are not hard-coded into the engine.

## 2. Deterministic Case families

### A. `local_shortage`

Raised only where an active product/warehouse has positive `stock_movements.type='out'` demand during the last 30 business-date days and either:

- available quantity is zero or negative; or
- available cover is below 7 days using `available_quantity / (30-day outbound / 30)`.

The kernel starts from outbound demand and left-joins current stock, so a missing stock row does not hide a real zero-balance shortage.

Supporting feasibility evidence includes:

- current quantity / reserved / available / WAC;
- recent outbound quantity and movement count;
- computed average daily outbound and cover;
- available stock in up to five alternate active warehouses;
- inbound `in_transit` quantity for the same product/location.

This evidence may support a human decision to transfer, procure, investigate, or monitor. The AI domain itself performs none of those mutations.

### B. `stalled_transfer`

Raised when a transfer remains `in_transit` for more than 7 days from `sent_at` (`created_at` fallback).

There is no deployed transfer SLA authority yet, so 7 days is explicitly marked as a conservative Inventory-v1 fallback rather than represented as company policy. Once a governed transfer SLA exists, the detector should read it instead.

Evidence includes source/destination warehouses, transfer number, sent reference time, age, item count and sent/received quantities.

## 3. Intentionally excluded v1 cases

### `expiry_risk`

Not emitted in v1. Batch schema existence alone is insufficient evidence of operational batch tracking. Enabling expiry action before positive batch balances are trustworthy would create false operational precision.

### `min_stock_breach`

Not emitted in v1 because `min_stock_level` is currently unconfigured. A future governed reorder/min-stock policy can become authority without replacing the current demand-backed shortage Case.

## 4. Responsibility contract

Inventory does not silently choose a responsible employee.

A warehouse is considered unambiguous only when it has exactly one `warehouse_managers.is_primary=true` profile and any `warehouses.manager_id` either agrees with that user or is null.

The candidate remains visible when responsibility is ambiguous, because management still needs to see the operational exception. Consequential `CREATE_WORK` / `ESCALATE` fails closed until responsibility is singular and the proposed assignee matches the currently resolved warehouse manager.

For a stalled transfer, the destination warehouse is the operational responsibility anchor; the source warehouse remains linked as supporting transfer context.

## 5. Immutable snapshot and four-domain budget

`ai_ops.refresh_inventory_cases` freezes selected Inventory evidence into the same `snapshot_cases` / `snapshot_domain_captures` model used by the earlier domains.

Capture version: `inventory-v1`.

The canonical operational snapshot now allocates one hard Case limit across:

1. Receivables;
2. Sales;
3. Customer Health;
4. Inventory.

Allocation continues to use the existing deterministic round-robin water-fill allocator. It never compares a Sales severity label with an Inventory severity label.

If Inventory has demand but receives zero capacity, an immutable zero-case `partial` marker records global budget exhaustion. If a selected Inventory Case is fully frozen but lower-ranked Inventory Cases were omitted only because of the bounded Case limit, the shared selected-Case actionability gate can allow that selected Case while evidence/source partials remain fail closed.

## 6. Current-state validation

Immediately before consequential action the Inventory guard re-runs the exact deterministic candidate kernel and checks current operational state.

It blocks execution when, among other things:

- the Case is no longer current;
- warehouse/product identity became invalid;
- stock balance, recent demand or cover changed after the snapshot;
- alternate/inbound supply feasibility changed;
- a stalled transfer changed state or quantity evidence;
- warehouse responsibility became ambiguous or changed;
- the recommended assignee is no longer the resolved responsible warehouse manager;
- owner/assignee became unavailable;
- an active Work item already covers the same shortage or transfer;
- escalation lost continuity with active linked Work;
- newer governed warehouse/product/branch context exists;
- the selected frozen evidence is not actionable under the shared bounded-partial gate.

## 7. Human-reviewed Work execution

Inventory uses the existing reviewed Work pipeline and the same deterministic source key:

`ai_ops:decision:<decision_id>`

The bridge requires planner enabled, Shadow Mode off, approved human review, unchanged decision fingerprint/revision, validated decision, active actors, future due date and same-transaction current-state revalidation.

Work links are explicit:

- `local_shortage`: product as `primary`, warehouse as `affected_at`;
- `stalled_transfer`: stock transfer as `primary`, destination warehouse as `destination`, source warehouse as `source` when present.

The generic Work entity resolver is extended with `stock_transfer -> public.stock_transfers` rather than hiding transfer identity in opaque metadata.

Employee-facing Work text states the operational condition and required follow-up without exposing management-only rationale.

## 8. Mutation boundary

Inventory AI Operations may mutate only:

- Work Engine rows/events/links created after approved review;
- AI Ops decision/case/run provenance and execution state.

It must not automatically mutate:

- `stock`;
- `stock_movements`;
- `stock_transfers` or `stock_transfer_items`;
- `products`;
- `warehouses` / `warehouse_managers`;
- batches;
- purchasing records.

Actual transfer, receipt, adjustment, procurement or stock correction remains an explicit operational action performed through the authoritative business workflow.

## 9. Increment acceptance gate

Before Inventory is considered closed, branch evidence should show:

- deterministic candidate contract tests;
- immutable snapshot contract tests;
- four-domain global budget / bounded actionability contract tests;
- current-state drift and responsibility contract tests;
- reviewed Work bridge / no-inventory-mutation contract tests;
- repository tests, TypeScript check, production build and clean-install CI on the exact commit.

The expensive all-domain local database runtime acceptance remains deferred until all planned domains are implemented. No production migration, merge or deployment is authorized by this document.
