# Design QA State

## Reviewed baseline

- Review date: `2026-09-16`
- Development branch: `design-system-v2-development`
- Exact development HEAD observed before this QA write: `c0b5900811efd553c23e3df784cd6d343546c79b`
- Active slice: `DS2-UI-005 — Sales transaction detail V2`
- Active implementation PR: `#32 — DS2-UI-005: establish Sales transaction detail V2 header pattern`
- PR base: `design-system-v2-development`
- Slice starting baseline: `8a0c34751344ca466754d06980093c501b536cd9`
- Exact PR HEAD reviewed: `9e9871fe03d32db45ac2e2daa71d82c749364761`
- Live PR state at review: `OPEN / DRAFT / mergeable`
- Changed-file scope: 8 files (TransactionHeader pattern/tests, thin Sales adapter/tests, transaction CSS/import, workstream/UI implementation state)
- Current disposition: `AGENT-REVIEW: BLOCKED — INCOMPLETE_CANDIDATE / LIVE PAGE NOT WIRED`
- Evidence: `TESTS_AUTHORED_NOT_EXECUTED`; architecture foundation passes source review, but no slice-level `SOURCE_REVIEW_PASS` is issued yet.

## Independent QA disposition

**BLOCKED for integration on exact HEAD `9e9871fe03d32db45ac2e2daa71d82c749364761`.**

The Product Design Director's earlier P1 action-orchestration defect is corrected at the shared-pattern boundary. `TransactionHeader` no longer owns a parallel action taxonomy: it consumes the existing `AppAction[]`, canonical `useDeviceMode()` and `resolveActionSet()` contract; Mobile gets one visible workflow action, Tablet two, Desktop up to four, and remaining eligible actions move into a native disclosure overflow. Danger remains a tone rather than a forced placement rule. The action area is an explicitly labelled accessibility group, and `DocumentActions` remains outside the workflow action registry through the `tools` slot.

However, this exact PR head is intentionally incomplete. `src/pages/sales/SalesOrderDetail.tsx` is not changed by the PR and still renders the legacy local sticky hero, local status-color map, local `ActionBtn` controls and horizontally scrolling action strip. Therefore the new shared pattern is not yet connected to the live permission/status/workflow callbacks, and exact functional parity cannot yet be independently reviewed. The PR body and UI Production state both explicitly say live wiring is the next step on this same PR.

Under the workstream contract an incomplete implementation candidate cannot receive `GREEN-DEV` merely because its shared foundation is sound.

## Architecture correction review

**PASS at source level for the corrected shared architecture.**

Verified on exact HEAD:
- `TransactionHeader` consumes `AppAction[]` directly; no exported `TransactionHeaderAction` fork remains.
- `useDeviceMode()` uses the canonical Mobile/Tablet/Desktop boundaries.
- `resolveActionSet()` remains the single shared placement truth: 1 Mobile / 2 Tablet / 4 Desktop + overflow.
- hidden and device-ineligible actions are filtered before placement by the existing registry.
- shared `Button` owns tone, loading, disabled and touch-target behavior.
- destructive semantics stay `AppAction.tone = 'danger'`, not a separate always-visible bucket.
- overflow uses native `<details>/<summary>` disclosure and shared action buttons.
- action surface uses `role="group"` + `aria-label="إجراءات المستند"`.
- thin `SalesOrderDetailHeader` reuses existing Sales status semantics and does not invent workflow actions.
- `DocumentActions` capability behavior is preserved as a separate `tools` slot rather than duplicated.
- no page-local second action registry is introduced.

The earlier Design Director `BLOCKING` state targets superseded head `97b3da7c...`; its exact architectural requirement is visibly satisfied on `9e9871f...`. That old blocker is stale for this head, not current approval evidence.

## Current integration blocker

### Gate blocker — REQUIRED NOW — incomplete live wiring

**Location:** live `src/pages/sales/SalesOrderDetail.tsx` hero/action region remains unchanged outside this PR.

Current production page still owns:
- local sticky hero presentation;
- local `statusColors` visual mapping;
- raw back button presentation;
- local `ActionBtn` component/action styling;
- horizontally scrolling action row;
- visible edit / confirm / deliver / due-date / return / copy / cancel actions under existing conditions;
- `DocumentActions` in the legacy strip.

Minimum completion required before exact-head GREEN review:
1. wire only the existing hero/action region to `SalesOrderDetailHeader` / `TransactionHeader` on this same PR;
2. build `AppAction[]` from the page's exact existing permission/status conditions without changing their meaning;
3. preserve every existing callback and `actionLoading` disabled/loading truth;
4. preserve `DocumentActions` capability behavior through the tools slot; use compact treatment if required to keep Mobile sticky-header density controlled;
5. remove only the superseded local hero/action presentation and `ActionBtn` usage for this region;
6. do not expand into FinancialSummary, receipts, items, notes, modals, services, queries, calculations or workflow semantics;
7. add focused page-level source/tests protecting the exact action-condition/callback mapping and absence of duplicate legacy action presentation;
8. hand off one stable exact HEAD for independent re-review.

This is a completeness gate, not a request for wider redesign.

## Scope / functional isolation

**PASS for the current changed files.**

No DB/migration/RPC/service/query-cache/RBAC/RLS/permission-definition/route-guard/business-calculation/workflow-state/validation-semantic/deployment change is present on the reviewed head.

The live page has deliberately not moved functional truth yet. That is safe, but also why the slice is not ready for integration.

## Device / interaction judgment

### Mobile
**PASS for the shared foundation; live-page proof pending.**
- registry resolution exposes one visible workflow action and moves remaining eligible actions to overflow;
- overflow becomes in-flow on Mobile rather than a clipped absolute menu;
- shared action buttons use touch targets;
- final sticky-header height/density must be rechecked after real `DocumentActions` tools and real Sales actions are wired.

### Tablet
**PASS for the shared foundation; live-page proof pending.**
- registry cap is two visible actions;
- logical gutters and wrapped action layout are deliberate;
- actual Sales action set still needs live wiring verification.

### Desktop
**PASS for the shared foundation; live-page proof pending.**
- up to four visible actions preserves dense review efficiency before overflow;
- actual ordering/importance must be checked against the existing live Sales action sequence once wired.

## Accessibility / RTL

**PASS for the shared foundation with one WATCH for live wiring.**
- native disclosure supplies keyboard-toggle semantics without inventing partial ARIA menu behavior;
- action group has a real grouping role and label;
- shared buttons carry accessible names, loading/disabled state and focus behavior;
- logical CSS properties are RTL-safe;
- title/subtitle tolerate wrapping.

`WATCH`: `DocumentActions` has its own split/dropdown behavior. When placed in the sticky tools slot, verify the chosen compact/non-compact rendering does not recreate Mobile crowding and that its existing capability semantics remain unchanged.

## Test / execution evidence

Focused tests are authored for:
- direct shared `AppAction` contract use;
- Mobile one-visible-plus-overflow resolution;
- hidden/device eligibility;
- action tone mapping;
- callbacks;
- loading/disabled semantics;
- touch-target classes;
- labelled action grouping;
- optional sticky composition;
- Sales status reuse and no invented actions.

The pre-existing `ActionRegistry` tests already protect the canonical Tablet two-visible / Desktop four-visible limits and deterministic ordering.

Evidence remains **`TESTS_AUTHORED_NOT_EXECUTED`**. No approved local checkout executed `npm test`, `npm run build` or `npm run lint`; no GitHub Actions/hosted CI or Vercel was triggered or relied upon. No executed PASS is claimed. No known TypeScript/build failure is identified by source review.

## Cross-role comparison / freshness

- **Product Design Director:** its current state blocks old head `97b3da7c...` specifically for the parallel action model. That finding is materially corrected on current head `9e9871f...`; Director revalidation is still useful before/while live wiring, but the old exact-head blocker is stale rather than a still-current contradiction.
- **UI Production Engineer:** feature-branch state is fresh enough to confirm the correction and explicitly says the slice remains `IN_PROGRESS / NO_MERGE` with `SalesOrderDetail.tsx` still unwired. This aligns with QA's completeness blocker.
- **Development Integrator:** current state blocks old head `97b3da7c...` for the same architecture issue and absence of QA. It must remain `NO_MERGE`; after live wiring it must revalidate the new exact head rather than reuse this review.
- **Team Memory / Workstream:** correctly identify DS2-UI-005 as the only active/ready Sales detail slice. No competing implementation slice exists.
- **Development drift:** compare from slice baseline `8a0c347...` to current development `c0b5900...` changes only Design Director and Integration state files; no product/shared-component drift invalidates the feature baseline.

No new cross-role design contradiction is introduced by this QA run. The current blocker is the already-declared incomplete state of the PR, not a disagreement about the corrected architecture.

## Runtime / release boundary

Not claimed:
- `SOURCE_REVIEW_PASS` for the completed slice (candidate is incomplete)
- `LOCAL_EXECUTION_PASS`
- `MANUAL_PREVIEW_BUILD_PASS`
- `RUNTIME_VISUAL_PASS`
- `main` / release readiness

## Cross-role handoff

- **To:** UI Production Engineer, Product Design Director, Development Integrator
- **What changed:** Design QA independently inspected PR #32 exact HEAD `9e9871fe03d32db45ac2e2daa71d82c749364761`. The previous action-architecture P1 is corrected in the shared foundation, but the PR remains incomplete because the live `SalesOrderDetail.tsx` hero/action region is still unwired; therefore no `GREEN-DEV` or slice-level `SOURCE_REVIEW_PASS` is issued.
- **Preserve:** corrected `AppAction` / `resolveActionSet` single-source action architecture; all existing Sales permission/status/workflow/query/service/calculation/modal/output truth; `DocumentActions` capability behavior; bounded header-only scope; no hosted CI/Vercel/`main` activity.
- **Need from you:** UI Production Engineer should now wire only the existing live hero/action region using the corrected shared contract, preserve exact action conditions/callbacks/loading truth, remove only superseded local header/`ActionBtn` presentation, add focused parity coverage, and hand off a stable exact HEAD. Product Design Director may revalidate the corrected architecture without widening scope. Integrator remains `NO_MERGE` until the completed exact head receives independent `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS`.
- **Blocker level:** `BLOCKING` for integration because the implementation candidate is incomplete; corrected architecture itself has no new QA blocker.
- **Baseline:** development `c0b5900811efd553c23e3df784cd6d343546c79b`; reviewed PR #32 HEAD `9e9871fe03d32db45ac2e2daa71d82c749364761`
