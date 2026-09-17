# Design QA State

## Reviewed baseline

- Review date: `2026-09-17`
- Development branch: `design-system-v2-development`
- Exact Development HEAD inspected before this review/state write: `b0b5240f19bbdcb889e68753e20c308539072e67`
- Active slice: `DS2-FIELD-001 — Activities/visit/call/target lists`
- Active representative concern: `ActivitiesPage` list presentation only
- Active implementation PR: `#42 — DS2-FIELD-001: Activities list V2 foundation`
- PR base: `design-system-v2-development`
- PR base SHA: `def098978efbe796306f882014e69652f014efa6`
- Exact current PR HEAD independently reviewed: `6b7569f3b98f7d8cd9a7588b3ae624e606f82f6b`
- Live PR state at disposition: `OPEN / DRAFT / mergeable=true`
- Changed-file scope: 7 files — Activities live page, thin Field presentation adapter, focused tests, bounded Field CSS, workstream state and UI Implementation owned state.
- Current disposition: `AGENT-REVIEW: GREEN-DEV`
- `SOURCE_REVIEW_PASS`: **granted on exact HEAD `6b7569f3b98f7d8cd9a7588b3ae624e606f82f6b`**.
- Test evidence: `TESTS_AUTHORED_NOT_EXECUTED`.
- Exact-head build/test/lint/runtime/preview evidence: not claimed.

## Independent QA disposition

**GREEN-DEV on exact PR HEAD `6b7569f3b98f7d8cd9a7588b3ae624e606f82f6b`.**

I formed this judgment from the exact current PR diff, the exact bounded correction delta from previously reviewed HEAD `8ac8ed1e46fd8e48f1b7b065f74ab6f1dfac21df`, and the current shell/device/action contracts before comparing peer states. The Product Design P2 Mobile persistent-create duplication is source-resolved on the moved HEAD, the earlier Tablet/category P2 corrections remain intact, the slice remains functionally isolated, and no new material source-level blocker is present.

## Exact-head findings

### Product Design P2 Mobile create-ownership blocker — CLOSED at source level

The prior same-head contradiction on `8ac8ed1...` was valid: the Activities PageHeader create control had become visible on Mobile while the existing shell already owns the same creation capability through the registered `new-activity` FAB.

Exact current HEAD `6b7569f3...` applies the requested bounded correction:

- `ActivitiesPage` imports and uses the canonical `useDeviceMode()` contract.
- PageHeader `نشاط جديد` is passed only when `deviceMode !== 'mobile'`.
- Canonical device truth remains Mobile `<=768px`, Tablet `769–1024px`, Desktop `>=1025px`.
- The existing shell action registry remains unchanged and still declares `new-activity` for `/activities/list` -> `/activities/new` under `activities.create`.
- `FAB` still resolves that registry action and owns Mobile persistent creation; no shell/FAB/registry file is changed by this PR.
- Tablet/Desktop retain the authorized PageHeader create action under the same `PERMISSIONS.ACTIVITIES_CREATE` predicate and `/activities/new` route.
- The existing permission-projected empty-state CTA remains unchanged, matching the Director's explicit bounded scope; global empty-state CTA/FAB convergence remains later debt.
- Focused source-contract protection now asserts the canonical device hook and Mobile-vs-Tablet/Desktop PageHeader ownership boundary.

The delta from `8ac8ed1...` to `6b7569f3...` is limited to `ActivitiesPage.tsx`, `ActivitiesPage.v2.test.ts`, and the UI Implementer owned state. No unrelated product/shared behavior moved with the correction.

### Earlier QA P2 blockers — remain CLOSED

1. **Tablet start-time parity:** optional `activity.start_time` is still projected through one page-owned `fmtTime` formatter and rendered for Tablet; Desktop uses the same formatter. Mobile intentionally retains its prior information density.
2. **Duplicate category hierarchy:** category is still represented once as neutral `Badge` metadata while activity outcome remains semantic `StatusBadge`.

Focused authored regressions remain present for both corrections.

### Scope / functional isolation — PASS

No DB/migration/RPC/service/RBAC/RLS/route-guard/business-calculation/query-cache/validation/workflow/deployment file is changed.

Preserved product/domain truth includes:
- `useActivities(queryParams)` still receives `typeCategory`, `outcomeType`, `dateFrom`, `dateTo`, `employeeId`, `customerId`, `page`, `pageSize: 25` from page-owned state;
- client-side text search remains immediate and still matches customer name, activity type name and outcome notes on the current server page;
- search/filter changes still reset `page` to 1;
- team-employee visibility remains `ACTIVITIES_READ_TEAM || ACTIVITIES_READ_ALL`;
- create eligibility remains `ACTIVITIES_CREATE`; only PageHeader placement changes by device;
- delete eligibility remains `ACTIVITIES_UPDATE_OWN || ACTIVITIES_READ_TEAM || ACTIVITIES_READ_ALL`;
- deletion still delegates to `useSoftDeleteActivity().mutate(deleteTarget.id)`; backend time-window authority is not duplicated in UI code;
- detail/create routes remain `/activities/${activity.id}` and `/activities/new`;
- customer deep-link filtering still initializes from `customerId` and can be cleared;
- `useActivityTypes()` remains unchanged;
- GPS remains read-only list metadata; false is neutral `—`, with no acquisition/verification semantics moved into presentation;
- outcome mapping remains presentation-only and does not change workflow values or transitions.

Development drift from the PR base to inspected Development HEAD remains governance-only and does not overlap the product/shared implementation.

### Shared-system fit / hierarchy — PASS at source level

- One live `ResponsiveCollection<ActivityRow>` owns device composition rather than mounting parallel hidden interaction trees.
- Desktop retains the dense `DataTable` management surface.
- Tablet intentionally uses two-column cards; Mobile uses one-column operational cards.
- Outcome state uses shared semantic `StatusBadge`; activity category uses neutral `Badge` metadata.
- `Card`, `KeyValueList`, `Button`, `Pagination` and canonical `AppAction + resolveActionSet` are reused instead of creating a Field-local parallel grammar.
- Page/domain code owns action eligibility, ordering and callbacks; shared resolution owns device placement only.
- Persistent create placement now follows the existing system ownership contract: shell FAB on Mobile, PageHeader on Tablet/Desktop.
- Initial-empty and filtered-empty copy remain distinct.
- Existing immediate filter/search semantics are preserved rather than silently adopting a different debounce/query contract.

### Device / RTL / accessibility / state judgment — PASS at source level

- **Desktop (`>=1025px`):** dense table preserves customer, date + optional start time, outcome, notes, GPS and authorized view/delete actions; authorized PageHeader create remains present; table overflow stays contained.
- **Tablet (`769–1024px`):** deliberate two-column cards preserve optional start time and operational metadata, expose up to two eligible direct record actions, retain touch-safe identity/actions, and keep the authorized PageHeader create action.
- **Mobile (`<=768px`):** one-column cards retain prior information density, expose one direct eligible record action plus accessible RTL overflow when needed, use touch-safe controls, avoid a parallel Desktop interaction tree, and no longer render a competing persistent PageHeader create action. Existing shell FAB remains the single persistent create owner.
- **RTL / Arabic / long content:** logical alignment, Arabic accessible labels, flex wrapping, `min-width: 0` and `overflow-wrap: anywhere` protect ordinary long-content composition; category/outcome semantics are text-backed rather than color-only.
- **Focus / keyboard:** card identity is a native button with visible focus treatment; actions are native shared Buttons; shared Pagination retains navigation landmark, labels, disabled boundaries and `aria-current="page"`.
- **States:** loading, initial-empty, filtered-empty, permission-projected create/delete, destructive confirmation, one-page pagination suppression and empty live-filter pagination suppression remain preserved. Broader query-error/offline convergence is existing program debt, not a new FIELD001 regression.

No runtime visual PASS is claimed.

### Test Artifact Gate / evidence honesty

Focused authored artifacts protect:
- one responsive renderer boundary;
- preserved query/search/filter inputs and paging behavior;
- permission/delete mutation boundaries;
- semantic outcome mapping and neutral category/GPS treatment;
- Mobile/Tablet record-action placement and callback delegation;
- Tablet start-time parity and unchanged Mobile time density;
- single category representation;
- canonical device breakpoints/touch sizing;
- Mobile persistent-create ownership through canonical `useDeviceMode`, while Tablet/Desktop retain PageHeader create and the existing empty-state CTA remains present.

Evidence is **`TESTS_AUTHORED_NOT_EXECUTED`**. No approved environment executed tests/build/lint; no hosted GitHub Actions/CI or Vercel preview was used. No known real build/type failure is recorded. This is not an executed PASS claim.

## Peer-state comparison / contradiction handling

The independent disposition above was formed first.

- **UI Production Engineer feature-head state:** fresh and aligned. It records the same bounded correction, unchanged functional boundaries and `TESTS_AUTHORED_NOT_EXECUTED` evidence.
- **Product Design Director state on Development:** materially relevant but stale because its `P2 / BLOCKING` disposition is explicitly anchored to superseded HEAD `8ac8ed1...`. The exact minimum correction it requested is present on `6b7569f3...`. Classification for this QA review: stale `WATCH`, not current same-head `BLOCKING` evidence. Product Design Director still needs an independent fresh review of `6b7569f3...` before Integration may treat the cross-role contradiction as formally closed.
- **Integration state on Development:** also blocks superseded HEAD `8ac8ed1...` for the same now-corrected source defect. Classification: stale `WATCH`; Integrator should remain `NO_MERGE` until the Director refreshes the same exact head and normal integration gates are revalidated.
- **Team Memory / Development workstream:** lifecycle-stale relative to the current moved FIELD001 review head; the active PR and feature-head Implementer state carry the current correction handoff.
- **PR review threads:** none open.

No current exact-head source evidence supports retaining the old P2 blocker on `6b7569f3b98f7d8cd9a7588b3ae624e606f82f6b`.

## Non-blocking watch

On Mobile initial/filtered-empty states, the permission-projected `StatePanel` CTA can coexist with the shell FAB. This duplication predates the bounded correction and was explicitly kept outside FIELD001 by Product Design; it remains a later action-convergence/runtime-density `WATCH`, not a regression introduced by this HEAD and not a reason to expand the current slice.

## System-fit judgment

FIELD001 now advances the North Star cleanly: a single responsive capability, semantic Field status grammar, neutral categorical metadata, canonical record-action placement, correct persistent-create ownership by device, and deliberate Tablet/Mobile compositions without moving Field business truth into shared presentation.

Any movement of PR HEAD after `6b7569f3b98f7d8cd9a7588b3ae624e606f82f6b` invalidates this exact-head GREEN-DEV and requires fresh Design QA.

### Cross-role handoff
- **To:** Product Design Director, Development Integrator, UI Production Engineer.
- **What changed:** Design QA independently reviewed PR #42 exact HEAD `6b7569f3b98f7d8cd9a7588b3ae624e606f82f6b`, confirmed the Product Design Mobile create-ownership blocker is source-resolved by the bounded device-placement correction, and issued `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- **Preserve:** every activity query/search/filter input and timing; team/create/delete permissions; `/activities/new` and detail routes; delete mutation/backend authority; customer deep-link; GPS/device/workflow/validation/service/query-cache truth; one live `ResponsiveCollection`; shared Pagination; semantic outcome status; neutral category treatment; Desktop density; restored Tablet time parity; existing shell `new-activity` FAB ownership on Mobile; PageHeader create on Tablet/Desktop.
- **Need from you:** Product Design Director should independently review the same exact HEAD and explicitly close or restate the prior P2 contradiction. Integrator must remain `NO_MERGE` until that fresh same-head design gate exists, PR HEAD is unchanged, no current BLOCKING contradiction remains, and base/mergeability/drift are revalidated.
- **Blocker level:** `NONE` from Design QA; stale Director/Integrator state is a same-head-review `WATCH` for Integration, not a current source blocker.
- **Baseline:** Development inspected `b0b5240f19bbdcb889e68753e20c308539072e67`; exact reviewed PR HEAD `6b7569f3b98f7d8cd9a7588b3ae624e606f82f6b`.
- **Evidence:** `SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`; no executed build/test/lint/runtime/preview/release PASS claimed.
