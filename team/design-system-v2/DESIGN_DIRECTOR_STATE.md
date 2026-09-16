# Design Director State

## Reviewed baseline

- Review date: `2026-09-16`
- Development branch: `design-system-v2-development`
- Exact development HEAD reviewed before this state write: `7783d25b9a0fa4da919b3d4b0973553863561d87`
- Active slice: `DS2-UI-004 — Sales Order form V2 foundation`
- Active Draft PR: `#31 — DS2-UI-004: establish Sales Order form V2 presentation foundation`
- Feature branch: `ds2/sales-order-form-v2`
- Slice starting baseline: `a6c9705ab56442c7c1d1722b442aa374a7556e81`
- Exact current PR HEAD independently reviewed: `6841ceb3094ec6f85a14d4e9bdfb77869fc4444c`
- Live PR state: `OPEN / DRAFT / mergeable`
- Current disposition: `BLOCKED — one bounded presentation-density correction`
- Current evidence: `TESTS_AUTHORED_NOT_EXECUTED`

## Independent professional judgment

**ALIGN WITH DESIGN QA: KEEP THE SLICE, FIX ONE P2 DESKTOP DENSITY REGRESSION, THEN RE-REVIEW THE NEW EXACT HEAD.**

The earlier Design Director blocker is resolved on current source. PR #31 now reuses/evolves the shared `Stepper` rather than creating a parallel Sales primitive; page-owned step reachability is preserved; the review step is not made freely future-clickable; RTL next/previous cues are corrected; Mobile can use the shared wrapped Stepper mode without hiding the Arabic labels. Functional isolation remains intact.

The new QA blocker is valid and consistent with the North Star rather than a competing opinion. The migrated Step 0 section currently uses `columns={2}`. The baseline used `repeat(auto-fill, minmax(220px, 1fr))`, so after the two full-width customer/credit rows the representative, order date and delivery branch could share one Desktop row when width allowed. The V2 change therefore imposes a lower two-column ceiling and creates an avoidable extra row on a dense management/data-entry surface.

The existing shared `FormGrid` already expresses the correct device contract: requested 3 columns on Desktop, automatically capped to 2 on Tablet, and collapsed to 1 on Mobile. This is exactly the North Star requirement: dense-but-legible Desktop, deliberate Tablet, task-clear Mobile. No new component or CSS contract is needed.

## Required correction

### P2 — restore device-appropriate Step 0 density

**BLOCKING for GREEN-DEV / integration, bounded to presentation.**

Minimum change:
- change the live Step 0 `SalesOrderFormSection` from `columns={2}` to `columns={3}`;
- update focused composition/source-contract coverage so the 3→2→1 intent is protected at source level;
- preserve the two intentionally full-width customer/credit rows through their existing `gridColumn: '1 / -1'` behavior;
- do not change field order, values, validation, permissions, customer/branch/rep behavior, or any Sales business truth.

Do not use this blocker to expand into Combobox/ProductLine/DataTable/overlay redesign. Those remain deferred until separately proven by the live form.

## Current architecture/system fit

- **Shared Stepper:** PASS on current head; previous duplicate-primitive contradiction is resolved.
- **Exact Sales reachability:** PASS; remains page-owned and matches legacy behavior.
- **RTL directional actions:** PASS at source level.
- **Mobile Stepper labels/overflow:** PASS at source level for the bounded contract; runtime visual acceptance remains a later milestone gate.
- **FormSection/FormGrid ownership:** PASS; only the selected Desktop column count is wrong.
- **FormActions/Button ownership:** PASS.
- **Functional isolation:** PASS; no DB/RPC/service/query-cache/RBAC/RLS/permission/business calculation/workflow/validation/deployment drift found.
- **Evidence honesty:** PASS; tests are authored but not executed, and no CI/Vercel/local PASS is claimed.

## Coordination / freshness

- PR #31 is the only open PR targeting `design-system-v2-development`.
- Current exact PR HEAD is `6841ceb3094ec6f85a14d4e9bdfb77869fc4444c`; it is Draft and mergeable but must not merge while QA/Director blocker is current.
- Design QA state on the same exact head is fresh and `BLOCKING`; this Director synthesis agrees with it.
- UI Implementation State stored on the development branch is stale for this slice; the feature-branch implementation state is materially newer but predates the QA density disposition.
- Integration State is stale by PR HEAD but its `NO_MERGE` disposition remains correct.
- Team Memory / Workstream still call DS2-UI-004 READY; the live PR and current states make it the single active blocked/review slice. This is coordination metadata drift, not permission to open another slice.
- Do not merge-sync the feature branch merely to absorb governance/state-only development commits.

## Preserve

- create/edit and `copyFrom` behavior;
- customer selection/clear, branch loading, credit presentation and rep assignment/read-only behavior;
- product search/unit/quantity/stock warning/add-remove behavior;
- price-edit permission and discount-override limits;
- tax, discount, shipping and total calculations;
- minimum-order blocking;
- exact step reachability, `goNext` validation/toasts and progression;
- `createSalesOrder` / `updateSalesOrder` / `saveSalesOrderItems` / `recalcOrderTotals` save sequence;
- save/cancel routes;
- existing Mobile add-product `ResponsiveModal` flow;
- shared Stepper/FormSection/FormGrid/FormActions/Button ownership;
- one active implementation slice only;
- no hosted CI, Vercel preview, backend/business or `main` activity.

## Cross-role handoff

- **To:** UI Production Engineer, Design QA, Development Integrator
- **What changed:** Product Design Director independently revalidated PR #31 exact HEAD `6841ceb3094ec6f85a14d4e9bdfb77869fc4444c`. The previous Stepper/RTL/reachability blocker is resolved. I agree with QA's new single P2 blocker: Step 0 uses `columns={2}` and unnecessarily reduces Desktop data-entry density versus the baseline, while shared FormGrid already supports the correct `3 Desktop / 2 Tablet / 1 Mobile` contract.
- **Preserve:** all Sales Order business/query/permission/validation/calculation/save/route/workflow truth; shared Stepper and form/action contracts; full-width customer/credit rows; deferred Combobox/ProductLine scope; no hosted CI/Vercel/`main` activity.
- **Need from you:** UI Production Engineer should make only the minimum `columns={3}` correction plus focused density-contract coverage and hand off a new exact HEAD. Design QA must re-review that new exact HEAD. Integrator must remain NO_MERGE until exact-head `GREEN-DEV` + `SOURCE_REVIEW_PASS` and no current BLOCKING state remain.
- **Blocker level:** `BLOCKING` for integration; bounded presentation-only fix.
- **Baseline:** development `7783d25b9a0fa4da919b3d4b0973553863561d87`; PR #31 HEAD `6841ceb3094ec6f85a14d4e9bdfb77869fc4444c`
