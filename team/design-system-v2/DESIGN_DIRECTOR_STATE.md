# Design Director State

## Reviewed baseline

- Review date: `2026-09-17`
- Development branch: `design-system-v2-development`
- Exact Development HEAD inspected before this state write: `6037b0eb08fc698eb079acfa5b4f563c151ee6a5`
- Active slice: `DS2-FIELD-001 — Activities/visit/call/target lists`
- Active representative concern: `ActivitiesPage` list presentation only
- Active implementation PR: `#42 — DS2-FIELD-001: Activities list V2 foundation`
- PR base: `design-system-v2-development`
- PR base SHA: `def098978efbe796306f882014e69652f014efa6`
- Exact PR HEAD independently reviewed: `8ac8ed1e46fd8e48f1b7b065f74ab6f1dfac21df`
- Live PR state at review: `OPEN / DRAFT`; exact HEAD unchanged from Design QA GREEN review.
- Design QA disposition on the same exact HEAD: `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- Current Product Design disposition: `BLOCKED — P2 MOBILE PRIMARY-ACTION DUPLICATION`.
- Evidence level: exact-head source review. Focused tests exist but remain `TESTS_AUTHORED_NOT_EXECUTED`; no build/test/lint/runtime/preview PASS is claimed.

## Independent professional judgment

**FIELD001 is directionally and architecturally sound in its collection/status/device work, but exact PR HEAD `8ac8ed1e46fd8e48f1b7b065f74ab6f1dfac21df` is not ready to integrate because the slice introduces a source-proven Mobile primary-action duplication.**

I formed this judgment from the exact live page, Field adapter, shell creation-action registry/FAB contract and pre-slice baseline before comparing peer states.

### Collection / hierarchy / semantic grammar — PASS

- `ActivitiesPage` uses one live `ResponsiveCollection<ActivityRow>` rather than parallel mounted Desktop/Mobile interaction trees.
- Desktop keeps the dense management `DataTable`; Tablet deliberately uses two-column cards; Mobile uses one-column operational cards.
- The two previous QA P2 defects are correctly closed: Tablet preserves optional `start_time` with the same page-owned formatter as Desktop, and category is exposed once as neutral `Badge` metadata while outcome uses semantic `StatusBadge`.
- `ActivityCard` is a thin Field projection over shared `Card`, `KeyValueList`, `Badge`, `StatusBadge`, `Button`, `Pagination` and canonical `AppAction + resolveActionSet` placement.
- GPS false remains neutral read-only metadata (`—`), not an invented failure state.
- Initial-empty and filtered-empty language are distinct.

### Functional isolation / capability parity — PASS

The slice preserves page/domain truth: `useActivities(queryParams)` inputs, immediate client-side text search, page resets, `pageSize: 25`, team/create/delete permission predicates, delete mutation/backend time-window authority, routes, customer deep-link, activity-type lookup, GPS meaning, workflow values and service/query/validation semantics remain outside shared presentation.

No backend/business/RBAC/RLS/query-cache/deployment change is part of the implementation.

### Device / RTL / accessibility — PASS except action ownership blocker

- Desktop density is preserved.
- Tablet has deliberate two-column composition, restored start-time parity and touch-safe card controls.
- Mobile card identity/actions are touch-safe, one direct eligible record action is shown before overflow, and long Arabic content has wrap/min-width protection.
- Shared Pagination retains its established accessible Arabic paging contract.

## P2 BLOCKER — Mobile now exposes the same create action through two persistent primary surfaces

This is a current-slice regression, not merely pre-existing global action debt:

1. On the pre-slice Activities baseline, the PageHeader `نشاط جديد` button carried `desktop-only-btn`, with a local `<=768px` rule hiding it on Mobile.
2. PR #42 removes that Mobile suppression and now renders the authorized PageHeader `نشاط جديد` action on Mobile.
3. The existing shell already owns the same Mobile creation capability: `CREATION_ACTIONS` declares `new-activity` for `/activities/list` -> `/activities/new` under the same `activities.create` permission; `FAB` resolves that registry action; its existing test explicitly proves `+ نشاط` is present on `/activities/list`; `AppLayout` documents the context-aware FAB as part of the Mobile shell.

Therefore an authorized user on the Mobile Activities list receives both the shell FAB and the new PageHeader create button for the same action during ordinary non-empty use. On empty states the page CTA may add a third visible copy, but that empty-state/FAB convergence is older debt and does not need to be expanded in this slice.

This conflicts with the North Star's one-obvious-primary-action rule and with the existing central creation-action ownership already proven by the shell registry. It also reverses the pre-slice Mobile placement decision without an explicit system-level action-convergence change.

### Minimum bounded correction

Keep PR #42 and its current concern. Do **not** redesign the global FAB, PageHeader, ActionRegistry or Field creation flow.

Required outcome only:
- on Mobile (`<=768px`) for the Activities list, the persistent create action must remain shell-owned by the existing registered FAB; the PageHeader create control must not render/compete there;
- keep the PageHeader create action available on Tablet/Desktop;
- preserve the exact `activities.create` permission, `/activities/new` route and all existing empty-state/business semantics;
- add focused authored protection proving Mobile does not gain a second persistent create surface while Tablet/Desktop retain the page-header create capability.

The existing Mobile empty-state CTA + FAB duplication remains a non-blocking action-convergence/runtime watch because it predates this PR; do not broaden FIELD001 to solve the global action system.

## Peer-state comparison / contradiction synthesis

After the independent review above:

- **Design QA:** fresh on the same exact HEAD and GREEN for the earlier Tablet/category fixes, but its non-blocking action-density watch under-scopes the current source evidence because it considers PageHeader + StatePanel while the shell's existing `/activities/list` FAB creates a persistent duplicate even when the list is non-empty. This is a material Product Design disagreement and is `BLOCKING` until bounded as above.
- **UI Production Engineer:** feature-head state is otherwise fresh/aligned and correctly preserves Field business truth; it did not identify the PageHeader/FAB ownership regression.
- **Integration State:** stale blocker applies only to superseded HEAD `823c89d...`; those two findings are closed. It is not the current blocker.
- **Team Memory / Development workstream:** lifecycle-stale relative to the live FIELD001 review phase. No competing implementation slice exists.

No Team Memory or Decision Log update is warranted: the durable rule has not changed. This blocker enforces already-established Mobile action clarity and central creation-action ownership rather than introducing a new system decision.

## What changed since previous state

Product Design moved from the completed HR002 acceptance to an independent exact-head FIELD001 review. The previous QA P2 issues are accepted as fixed, but a new source-proven Mobile action-ownership regression is now explicitly blocking integration on PR #42 exact HEAD `8ac8ed1e46fd8e48f1b7b065f74ab6f1dfac21df`.

### Cross-role handoff
- **To:** UI Production Engineer, Design QA, Development Integrator
- **What changed:** Product Design independently found a P2 blocker on PR #42 exact HEAD `8ac8ed1e46fd8e48f1b7b065f74ab6f1dfac21df`: Mobile now shows the Activities create action both in PageHeader and the already-registered shell FAB.
- **Preserve:** all activity query/search/filter timing and page resets; team/create/delete permissions; delete mutation/backend authority; routes/customer deep-link; GPS/device/workflow/service/validation truth; one live `ResponsiveCollection`; semantic outcome / neutral category treatment; shared Pagination; Desktop density; restored Tablet start-time parity; existing shell `new-activity` registry/FAB ownership on Mobile.
- **Need from you:** UI Production Engineer should make only the bounded Mobile PageHeader-create placement correction on the same PR and author focused protection; Design QA must re-review the new exact HEAD. Integrator must remain `NO_MERGE` until the moved HEAD receives fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and this Product Design contradiction is closed.
- **Blocker level:** `P2 / BLOCKING`.
- **Baseline:** Development `6037b0eb08fc698eb079acfa5b4f563c151ee6a5`; blocked PR HEAD `8ac8ed1e46fd8e48f1b7b065f74ab6f1dfac21df`.
