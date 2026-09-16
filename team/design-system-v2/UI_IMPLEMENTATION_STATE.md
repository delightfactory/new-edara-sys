# UI Implementation State

## Reviewed baseline

- Run date: `2026-09-16`
- Development branch: `design-system-v2-development`
- Exact slice baseline: `8a0c34751344ca466754d06980093c501b536cd9`
- Development HEAD inspected during this run: `design-system-v2-development` (mandatory shared-memory bootstrap completed before implementation)
- Feature branch: `ds2/sales-order-detail-v2`
- Draft PR: `#32 — DS2-UI-005: establish Sales transaction detail V2 header pattern`
- Exact implementation HEAD before this state write: `4f88098b719c9057cd34a3a8d6b23bd0c8cccd57`
- Active slice: `DS2-UI-005 — Sales transaction detail V2`
- Implementation disposition: `IN_PROGRESS — PRODUCT DESIGN DIRECTOR P1 ACTION-ARCHITECTURE CORRECTION IMPLEMENTED; LIVE PAGE STILL UNWIRED`
- Evidence: `TESTS_AUTHORED_NOT_EXECUTED`

## Independent implementation judgment

The transaction identity/status/action header remains the correct first bounded concern for the large live `SalesOrderDetail.tsx` screen. The earlier foundation correctly kept Sales permissions, workflow reachability, callbacks, calculations, queries, modal state and services page-owned, but it introduced a parallel `TransactionHeaderAction` contract and header-specific primary/secondary/destructive placement buckets.

That duplication was not acceptable once the existing shared `ActionRegistry` / `AppAction` contract was inspected. The correct system architecture is one action declaration and device-resolution truth: the page declares eligible actions after its existing business/permission checks; `resolveActionSet` decides one visible action on Mobile, two on Tablet and up to four on Desktop; the transaction header renders that resolved result and an accessible shared overflow surface.

## Material progress this run

1. Re-ran the mandatory shared-memory bootstrap in the required order and inspected issue #27, current Development, PR #32 and all open PRs targeting Development.
2. Formed the implementation judgment above before comparing peer states; Product Design Director then confirmed the same issue as a blocking P1 and explicitly prohibited live-page wiring until the shared action architecture was corrected.
3. Located the existing `src/components/patterns/ActionRegistry.ts` contract and verified that its `AppAction` tone set already maps directly to shared `Button` variants; no ActionRegistry fork or schema extension was necessary.
4. Removed the parallel exported `TransactionHeaderAction` model and the `primaryAction` / `secondaryActions` / `destructiveActions` props from `TransactionHeader`.
5. `TransactionHeader` now consumes `AppAction[]`, uses canonical `useDeviceMode()` plus `resolveActionSet()`, and renders only the registry-resolved visible actions for the current device.
6. Added the smallest shared overflow treatment proven by this slice: remaining registry actions move into an accessible disclosure surface instead of remaining permanently visible in the sticky Mobile header.
7. Preserved destructive semantics through `AppAction.tone = 'danger'`; danger no longer implies permanent Mobile visibility. Primary visual fallback is derived from existing `AppAction.importance`, not a new header taxonomy.
8. Kept `DocumentActions` accommodation as a separate `tools` slot rather than reimplementing or converting its capability behavior into a second workflow-action model.
9. Added `role="group"` plus `aria-label="إجراءات المستند"` to the action region, closing the Design Director accessibility requirement for labelled grouping semantics.
10. Updated the thin `SalesOrderDetailHeader` adapter to accept the same shared `AppAction[]` contract and keep Sales status mapping external.
11. Updated focused tests to protect registry identity, Mobile one-visible-plus-overflow resolution, device eligibility/hidden filtering, tone mapping, callbacks, touch targets, loading/disabled semantics, accessible action grouping, sticky composition and Sales status reuse.
12. The live `SalesOrderDetail.tsx` file remains deliberately untouched in this run; the P1 architecture correction was completed first exactly as directed.
13. No GitHub Actions, hosted CI, Vercel deployment or `main` activity occurred.

## Changed-file / pattern scope

Material architecture-fix commits in this run touched only:

- `src/components/patterns/TransactionHeader.tsx`
- `src/components/patterns/TransactionHeader.test.tsx`
- `src/components/sales/SalesOrderDetailPresentation.tsx`
- `src/components/sales/SalesOrderDetailPresentation.test.tsx`
- `src/styles/design-system-v2-transaction.css`
- `team/design-system-v2/UI_IMPLEMENTATION_STATE.md` (this owned state write)

No DB, migration, RPC, service, query/cache, RBAC/RLS, route guard, business calculation, validation or workflow file was changed.

## Preserved functional contracts

This correction does not modify or relocate:

- `getSalesOrder`, payment-receipt query or query/cache ownership;
- warehouse lookup, stock checks, confirmation or delivery behavior;
- customer-credit checks, payment-option selection, proof upload or delivery RPC behavior;
- cancellation or due-date adjustment behavior;
- financial calculations including remaining balance, paid ratio, credit amount or minimum cash;
- any permission definition/check such as `sales.orders.update`, `sales.orders.confirm`, `sales.orders.deliver`, `customers.credit.update`, `sales.returns.create`, `sales.orders.create` or `sales.orders.cancel`;
- routes, modal transitions, toasts, invalidation or workflow states;
- existing `DocumentActions` capability behavior.

## Device / state coverage

- **Mobile:** canonical ActionRegistry rule now exposes one eligible visible workflow action; all remaining eligible actions are available through the shared overflow disclosure. No secondary/destructive action grid remains permanently mounted in the sticky header.
- **Tablet:** registry exposes at most two visible actions, with the remainder in overflow; Tablet gutters and wrapping remain deliberate.
- **Desktop:** registry exposes up to four visible actions before overflow, preserving dense operational review behavior.
- **Hidden / device eligibility:** `AppAction.hidden` and `availableOn` are resolved before placement by the existing shared registry.
- **Loading / disabled:** shared Button preserves disabled/loading mechanics and accessible action names.
- **Destructive:** danger remains a tone, not a placement rule.
- **RTL / accessibility:** logical spacing is retained; the action surface is now an explicitly labelled accessibility group; overflow uses a native disclosure primitive; all workflow buttons retain shared touch targets.

## Test / execution evidence

Evidence is **`TESTS_AUTHORED_NOT_EXECUTED`**.

Focused tests were authored/updated for:
- direct use of the shared `AppAction` contract;
- canonical Mobile registry resolution and overflow placement;
- hidden/device-ineligible filtering;
- action tone to shared Button variant mapping;
- callbacks, loading/disabled and touch-target behavior;
- complete accessible action grouping;
- sticky composition;
- Sales status tone reuse and absence of invented actions.

The sandbox still has no project checkout and direct GitHub access from the terminal fails with `Could not resolve host: github.com`, so `npm test`, `npm run build` and `npm run lint` were not executed. No hosted CI was triggered and no PASS is claimed.

## Peer-state comparison / freshness

- **Product Design Director:** current state reviewed PR #32 exact old HEAD `97b3da7...` and issued a blocking P1 requiring ActionRegistry reuse, Mobile one-visible-plus-overflow behavior, preserved `DocumentActions`, and real action-group semantics. This run implements those requirements at exact implementation HEAD `4f88098...` before this state write.
- **Design QA:** must still wait for the later stable wired exact head; no GREEN-DEV exists for PR #32.
- **Development Integrator:** remains `NO_MERGE`; no integration authority is implied by this correction.
- **Implementation:** no competing slice was started and `SalesOrderDetail.tsx` remains unwired until the architecture correction can be re-read from the new head.

## Risks / deferred work

- Runtime/browser evidence remains unavailable; current evidence is source inspection plus authored tests only.
- The live page still uses its legacy sticky hero, local `ActionBtn` and horizontal action strip. That is intentional until the corrected shared action architecture is accepted for continued wiring.
- When live wiring resumes, the page must build `AppAction[]` only after its exact existing permission/status conditions resolve, preserving each existing callback and `actionLoading` behavior.
- `DocumentActions` must remain capability-equivalent and be passed through the `tools` slot; do not reimplement output behavior.
- Financial summary, receipts, items, notes and all modals remain outside this bounded concern.

## Cross-role handoff

- **To:** Product Design Director, Design QA, Development Integrator
- **What changed:** the P1 architecture blocker on PR #32 has been corrected before live-page wiring. `TransactionHeaderAction` and the header-specific primary/secondary/destructive placement model are gone; the pattern now consumes shared `AppAction[]`, canonical `useDeviceMode()` and `resolveActionSet()`, with Mobile/Tablet/Desktop limits and a shared accessible overflow disclosure. The Sales adapter uses the same contract and `DocumentActions` remains a separate tools slot.
- **Baseline:** slice baseline `8a0c34751344ca466754d06980093c501b536cd9`; exact implementation HEAD before this state write `4f88098b719c9057cd34a3a8d6b23bd0c8cccd57`.
- **Preserve:** all live Sales permission/status/workflow/query/service/calculation/modal/output truth.
- **Need:** Product Design Director should re-check the corrected action architecture. After that, UI Production Engineer can wire only the existing live hero/action region on this same PR, preserving exact action conditions/callbacks and removing only the superseded local header/`ActionBtn` presentation.
- **Blocker level:** original architecture P1 is implemented in source; slice remains `IN_PROGRESS` and `NO_MERGE` pending live wiring, stable-head Design QA and exact-head `GREEN-DEV`.
- **Evidence:** `TESTS_AUTHORED_NOT_EXECUTED`.
