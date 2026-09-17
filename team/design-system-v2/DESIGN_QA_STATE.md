# Design QA State

## Reviewed baseline

- Review date: `2026-09-17`
- Development branch: `design-system-v2-development`
- Exact Development HEAD inspected before this review/state write: `59e8bdc692c9e46571d52e602eb8c5ef78187cf4`
- Active slice: `DS2-FIELD-001 — Activities/visit/call/target lists`
- Active representative concern: `ActivitiesPage` list presentation only
- Active implementation PR: `#42 — DS2-FIELD-001: Activities list V2 foundation`
- PR base: `design-system-v2-development`
- PR base SHA: `def098978efbe796306f882014e69652f014efa6`
- Exact current PR HEAD independently reviewed: `8ac8ed1e46fd8e48f1b7b065f74ab6f1dfac21df`
- Live PR state at disposition: `OPEN / DRAFT / mergeable=true`
- Changed-file scope: 7 files — Activities live page, thin Field presentation adapter, focused tests, bounded Field CSS, workstream state and UI Implementation owned state.
- Current disposition: `AGENT-REVIEW: GREEN-DEV`
- `SOURCE_REVIEW_PASS`: **granted on exact HEAD `8ac8ed1e46fd8e48f1b7b065f74ab6f1dfac21df`**.
- Test evidence: `TESTS_AUTHORED_NOT_EXECUTED`.
- Exact-head build/test/lint/runtime/preview evidence: not claimed.

## Independent QA disposition

**GREEN-DEV on exact PR HEAD `8ac8ed1e46fd8e48f1b7b065f74ab6f1dfac21df`.**

I formed this judgment from the exact current PR diff, the bounded correction delta from blocked HEAD `823c89d10201a8db68e7189803bd003c3fd9fd2f`, and the current shared V2 contracts before comparing peer states. Both prior P2 findings are closed, the slice remains functionally isolated, and no new material source-level blocker is present.

## Exact-head findings

### Prior P2 blockers — CLOSED

1. **Tablet start-time parity:** `ActivitiesPage` now projects optional `activity.start_time` through one page-owned `fmtTime` formatter, and `ActivityCard` renders that datum for `mode="tablet"`. Desktop uses the same formatter. Mobile intentionally retains its prior information density and does not gain a time row.
2. **Duplicate category hierarchy:** `ActivityCard` no longer renders a second category subtitle beneath the title. Category appears once as neutral `Badge` metadata while activity outcome remains semantic `StatusBadge`.

Focused authored regressions protect both corrections.

### Scope / functional isolation — PASS

No DB/migration/RPC/service/RBAC/RLS/route-guard/business-calculation/query-cache/validation/deployment file is changed.

Preserved product/domain truth includes:
- `useActivities(queryParams)` still receives `typeCategory`, `outcomeType`, `dateFrom`, `dateTo`, `employeeId`, `customerId`, `page`, `pageSize: 25` from page-owned state;
- client-side text search remains immediate and still matches customer name, activity type name and outcome notes on the current server page;
- search/filter changes still reset `page` to 1;
- team-employee visibility remains `ACTIVITIES_READ_TEAM || ACTIVITIES_READ_ALL`;
- create remains `ACTIVITIES_CREATE`;
- delete eligibility remains `ACTIVITIES_UPDATE_OWN || ACTIVITIES_READ_TEAM || ACTIVITIES_READ_ALL`;
- deletion still delegates to `useSoftDeleteActivity().mutate(deleteTarget.id)`; backend time-window authority is not duplicated in UI code;
- detail/create routes remain `/activities/${activity.id}` and `/activities/new`;
- customer deep-link filtering still initializes from `customerId` and can be cleared;
- `useActivityTypes()` remains unchanged;
- GPS remains read-only list metadata; false is neutral `—`, with no acquisition/verification semantics moved into presentation;
- outcome mapping is presentation-only and does not change workflow values or transitions.

Development drift from the PR base to inspected Development HEAD is governance-only (`DESIGN_QA_STATE.md` / `INTEGRATION_STATE.md`) and does not overlap product/shared implementation.

### Shared-system fit / hierarchy — PASS at source level

- One live `ResponsiveCollection<ActivityRow>` owns device composition rather than mounting separate hidden interaction trees.
- Desktop retains the dense `DataTable` management surface.
- Tablet intentionally uses two-column cards; Mobile uses one-column operational cards.
- Outcome state uses shared semantic `StatusBadge`; activity category uses neutral `Badge` metadata.
- `Card`, `KeyValueList`, `Button`, `Pagination` and canonical `AppAction + resolveActionSet` are reused instead of creating a Field-local parallel grammar.
- Page/domain code owns action eligibility, ordering and callbacks; shared resolution owns device placement only.
- Initial-empty and filtered-empty copy are distinct.
- Existing immediate filter/search semantics are preserved rather than silently adopting a debounced filter contract.

### Device / RTL / accessibility / state judgment — PASS at source level

- **Desktop (`>=1025px`):** dense table preserves customer, date + optional start time, outcome, notes, GPS and authorized view/delete actions; table overflow remains contained.
- **Tablet (`769–1024px`):** deliberate two-column cards preserve the existing optional start-time datum, use two-column metadata, expose up to two eligible direct actions and retain canonical touch-safe identity/actions.
- **Mobile (`<=768px`):** one-column cards retain prior information density, expose one direct eligible action plus accessible RTL overflow when needed, use touch-safe controls and avoid a parallel Desktop interaction tree.
- **RTL / Arabic / long content:** logical alignment, Arabic accessible labels, flex wrapping, `min-width: 0` and `overflow-wrap: anywhere` protect ordinary long-content composition; category/outcome semantics are text-backed rather than color-only.
- **Focus / keyboard:** card identity is a native button with visible focus treatment; actions are native shared Buttons; shared Pagination retains navigation landmark, labels, disabled boundaries and `aria-current="page"`.
- **States:** loading, initial-empty, filtered-empty, permission-projected create/delete, destructive confirmation, one-page pagination suppression and empty live-filter pagination suppression are preserved. Broader query-error/offline convergence is existing program debt, not a new FIELD001 regression.

No runtime visual PASS is claimed.

### Test Artifact Gate / evidence honesty

Focused authored artifacts protect:
- one responsive renderer boundary;
- preserved query/search/filter inputs and paging behavior;
- permission/delete mutation boundaries;
- semantic outcome mapping and neutral category/GPS treatment;
- Mobile/Tablet action placement and callback delegation;
- Tablet start-time parity and unchanged Mobile time density;
- single category representation;
- canonical device breakpoints/touch sizing.

Evidence is **`TESTS_AUTHORED_NOT_EXECUTED`**. No approved environment executed tests/build/lint; no hosted GitHub Actions/CI or Vercel preview was used. No known real build/type failure is recorded. This is not an executed PASS claim.

## Peer-state comparison / contradiction handling

The independent disposition above was formed first.

- **UI Production Engineer feature-head state:** fresh and aligned; it records both bounded P2 corrections, exact review handoff and the same `TESTS_AUTHORED_NOT_EXECUTED` evidence.
- **Product Design Director state on Development:** lifecycle-stale from HR002 and contains no current FIELD001 exact-head judgment. Classification: `WATCH`, not a contradictory blocker.
- **Integration state on Development:** correctly blocks only superseded HEAD `823c89d...` on the two findings now closed. Classification: stale `WATCH`, not current `BLOCKING` evidence.
- **Team Memory / Development workstream:** lifecycle-stale relative to the live FIELD001 review phase; the active PR itself carries the current bounded workstream update.
- **PR review threads:** none open.

No current material cross-role `BLOCKING` contradiction exists for exact HEAD `8ac8ed1e46fd8e48f1b7b065f74ab6f1dfac21df`.

## Non-blocking watch

On Mobile empty states, the authorized create affordance can be present in both the `PageHeader` and `StatePanel`. This is consistent with an already-seen action-convergence/runtime-density watch and does not alter permission or business truth. It should be judged in the later global action-convergence/runtime pass rather than expanding this bounded FIELD001 slice.

## System-fit judgment

FIELD001 now advances the North Star cleanly: a single responsive capability, semantic Field status grammar, neutral categorical metadata, canonical action placement and deliberate Tablet/Mobile compositions without moving Field business truth into shared presentation. The previously identified information-parity and hierarchy defects are closed.

Any movement of PR HEAD after `8ac8ed1e46fd8e48f1b7b065f74ab6f1dfac21df` invalidates this exact-head GREEN-DEV and requires fresh QA.

### Cross-role handoff
- **To:** Development Integrator; Product Design Director for awareness; UI Production Engineer.
- **What changed:** Design QA re-reviewed PR #42 exact HEAD `8ac8ed1e46fd8e48f1b7b065f74ab6f1dfac21df`, confirmed both prior P2 blockers closed and issued `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- **Preserve:** every activity query/search/filter input and timing; team/create/delete permissions; delete mutation/backend authority; routes/customer deep-link; GPS/device/workflow/validation/service/query-cache truth; one live `ResponsiveCollection`; shared Pagination; semantic outcome status; neutral category treatment; canonical action placement; Desktop density and restored Tablet time parity.
- **Need from you:** Integrator should revalidate exact PR HEAD/base, Development governance drift, review threads and mergeability and may integrate only while HEAD remains `8ac8ed1e46fd8e48f1b7b065f74ab6f1dfac21df` and no fresh BLOCKING contradiction appears. Product Design Director may refresh the lifecycle-stale FIELD001 view independently without invalidating this QA evidence unless it records a material contradiction.
- **Blocker level:** `NONE`; Mobile create-density and release/runtime evidence remain `WATCH`/later gates.
- **Baseline:** Development inspected `59e8bdc692c9e46571d52e602eb8c5ef78187cf4`; exact reviewed PR HEAD `8ac8ed1e46fd8e48f1b7b065f74ab6f1dfac21df`.
- **Evidence:** `SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`; no executed build/test/lint/runtime/preview/release PASS claimed.
