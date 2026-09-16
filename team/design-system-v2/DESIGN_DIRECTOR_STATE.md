# Design Director State

## Reviewed baseline

- Review date: `2026-09-16`
- Development branch: `design-system-v2-development`
- Exact development HEAD independently inspected before this state write: `8a0c34751344ca466754d06980093c501b536cd9`
- Active slice: `DS2-UI-005 — Sales transaction detail V2`
- Active Draft PR: `#32 — DS2-UI-005: establish Sales transaction detail V2 header pattern`
- Feature branch: `ds2/sales-order-detail-v2`
- Slice baseline: `8a0c34751344ca466754d06980093c501b536cd9`
- Exact current PR HEAD reviewed: `97b3da7c84f567a85ab7d55d1c7fdd9196332c73`
- Live PR state: `OPEN / DRAFT / mergeable`
- Current disposition: `BLOCKED — shared action-orchestration contract must be reused before live page wiring`
- Current evidence: `TESTS_AUTHORED_NOT_EXECUTED`

## Independent professional judgment

**KEEP THE TRANSACTION-HEADER SLICE, BUT DO NOT WIRE IT INTO THE LIVE SALES PAGE YET. FIX THE SHARED ACTION ARCHITECTURE FIRST.**

Selecting the Sales transaction identity/status/action header as the first bounded concern is correct. The live `SalesOrderDetail.tsx` header is a clear recurring-system gap: local sticky hero, local status styling, raw back/action controls, horizontally scrolling actions and mixed workflow/document actions. Creating a shared `TransactionHeader` pattern is therefore justified and aligned with the North Star.

The current PR foundation, however, introduces a second action model inside that shared pattern: `TransactionHeaderAction` plus separate `primaryAction`, `secondaryActions` and `destructiveActions`. That conflicts with the already-established V2 `ActionRegistry` / `AppAction` contract and bypasses its device-aware placement algorithm.

This is not theoretical duplication. The existing `ActionRegistry` already defines the system rule that a page declares action meaning/importance and the presentation layer resolves placement by device: one visible action on Mobile, two on Tablet and four on Desktop, with the remainder moved to overflow. The V2 page-pattern and device blueprints explicitly require Mobile secondary actions to move into overflow/action-sheet treatment instead of crowding the header.

Current `TransactionHeader` CSS does the opposite on Mobile: it renders the primary full-width but then keeps all secondary and destructive actions visibly mounted in 2-column/1-column grids. On the real Sales detail screen the authorized action set can include edit, confirm/deliver, due-date adjustment, return, copy, cancel plus `DocumentActions`. In a sticky Mobile header this can consume a large portion of the viewport and recreates action-placement logic parallel to `ActionRegistry`.

The shared header should become the renderer of the existing action system, not a second registry.

## Required correction before live page wiring

### P1 — reuse the existing ActionRegistry contract

**BLOCKING for live `SalesOrderDetail.tsx` wiring and later GREEN-DEV. Presentation/system architecture only.**

Minimum acceptable direction:
- remove or stop exporting the parallel `TransactionHeaderAction` action model;
- consume the existing `AppAction` contract (or an exact `ResolvedActionSet` derived from it) rather than inventing another action descriptor;
- keep permission/status/workflow availability page-owned exactly as it is today; the page should only declare actions after its existing conditions resolve;
- use the existing device-aware `resolveActionSet` rule so Mobile exposes one visible workflow action, Tablet at most two, Desktop at most four, with remaining actions moved to an overflow surface;
- if an overflow renderer does not yet exist, add only the smallest shared accessible overflow/action surface proven necessary by this live screen; do not create a Sales-only menu;
- keep destructive tone semantic through the existing action tone/importance fields; danger does not mean it must remain permanently visible on Mobile;
- preserve `DocumentActions` behavior. It may remain a utility slot for this bounded slice, preferably using its compact form where appropriate, rather than being reimplemented;
- ensure the action region has complete accessible grouping semantics if it carries an accessible label; do not rely on `aria-label` on an otherwise generic container without a grouping/region role.

Do not expand this correction into FinancialSummary, receipts, line items, modals, output-system redesign or Sales business logic.

## Current architecture/system fit

- **Choosing TransactionHeader as the first detail pattern:** PASS.
- **Identity/title/customer/status adapter:** PASS directionally; reuse of existing Sales status semantics is correct.
- **Shared Button/touch/loading mechanics:** PASS directionally.
- **Long Arabic / RTL logical spacing:** PASS directionally at source level.
- **Sticky capability:** KEEP as optional; final Mobile stickiness must not create a permanently oversized header after action resolution.
- **Action ownership:** BLOCKING until `ActionRegistry` becomes the single shared action declaration/placement truth.
- **Mobile progressive disclosure:** BLOCKING in current form because all secondary/destructive actions remain visible instead of using the established one-visible-action + overflow contract.
- **Functional isolation:** PASS on current PR; the live Sales page has not yet been changed and no backend/query/permission/workflow/calculation semantics moved.
- **Evidence honesty:** PASS; authored tests are not claimed as executed.

## Peer-state comparison / freshness

After forming the source/blueprint judgment above, peer states were compared:
- UI Production Engineer correctly identified the header as the smallest bounded concern and correctly kept the live page untouched so far. Its `NONE` blocker disposition is superseded by this architecture finding before the next edit.
- Design QA state belongs to completed PR #31 and is stale for DS2-UI-005; it provides no approval or blocker for PR #32.
- Integration State correctly shows DS2-UI-004 merged and has no authority to integrate the new Draft slice yet.
- Team Memory correctly asks the Design Director to bound reusable transaction-header/action direction from the live screen; this state now supplies that boundary.

No competing implementation slice is authorized.

## Preserve

- every existing Sales detail permission/status/workflow decision and callback;
- all queries, services, calculations, modal state, invalidation, routes and business transitions;
- existing `DocumentActions` capability behavior;
- existing Sales status semantic mapping;
- Mobile-primary / deliberate Tablet / dense Desktop strategy;
- one shared V2 action orchestration model, not page/pattern-specific registries;
- one active implementation slice only;
- no GitHub Actions, hosted CI, Vercel preview, backend/business or `main` activity.

## Cross-role handoff

- **To:** UI Production Engineer, Design QA, Development Integrator
- **What changed:** Product Design Director independently reviewed PR #32 exact HEAD `97b3da7c84f567a85ab7d55d1c7fdd9196332c73`. The TransactionHeader slice is correct, but its new `TransactionHeaderAction` model and always-visible Mobile secondary/destructive grids duplicate and bypass the existing shared `ActionRegistry` device-placement contract.
- **Preserve:** live Sales business/query/permission/workflow/calculation/modal/output truth; shared Button/status semantics; bounded header-only scope; no CI/Vercel/main activity.
- **Need from you:** UI Production Engineer should correct the shared header to consume the existing `AppAction`/`resolveActionSet` contract and provide the smallest shared overflow treatment needed by the live screen before wiring `SalesOrderDetail.tsx`. Design QA should wait for a stable wired exact head and verify ActionRegistry reuse, Mobile one-primary-plus-overflow behavior, accessible action grouping, RTL/touch/long-content behavior and exact functional parity. Integrator remains NO_MERGE until exact-head GREEN-DEV.
- **Blocker level:** `BLOCKING` before live page wiring / integration; bounded Design System architecture correction.
- **Baseline:** development `8a0c34751344ca466754d06980093c501b536cd9`; PR #32 HEAD `97b3da7c84f567a85ab7d55d1c7fdd9196332c73`
