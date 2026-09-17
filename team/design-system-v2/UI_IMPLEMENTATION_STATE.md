# UI Implementation State

## Reviewed baseline

- Run date: `2026-09-17`
- Development branch: `design-system-v2-development`
- Exact slice baseline: `def098978efbe796306f882014e69652f014efa6`
- Feature branch: `ds2/field-activities-list-v2`
- Draft PR: `#42 — DS2-FIELD-001: Activities list V2 foundation`
- Product/test HEAD before this owned-state write: `3c1013ab0e5988f16317f20d8c4015cb628414d8`
- Active slice: `DS2-FIELD-001 — Activities/visit/call/target lists`
- Active representative concern: `ActivitiesPage` list presentation only
- Disposition: `IN_PROGRESS`
- Evidence: `TESTS_AUTHORED_NOT_EXECUTED`

## Independent implementation judgment

`ActivitiesPage` is the smallest dependency-safe representative Field list on the current Development baseline. It exposes the recurring V2 gaps directly — a legacy dual table/card render path through `DataTable.dataCardMapping`, local outcome color badges, direct page-owned device action placement, and local list styling — while its query, permission, delete-RPC, customer deep-link and routing truth can remain untouched.

The implementation therefore migrates only the Activities list capability. It does not broaden into call plans, visit plans, targets, activity create/detail flows, GPS acquisition, field workflow or backend semantics.

## Material implementation progress

- Created `ActivityOverviewPresentation` as a thin Field-domain adapter over shared `Card + KeyValueList + StatusBadge + Badge + Button + AppAction/resolveActionSet`.
- Replaced legacy outcome color badges on this list with readable semantic V2 outcome tones while preserving the existing Arabic outcome labels.
- `ActivitiesPage` now mounts exactly one `ResponsiveCollection<Activity>` renderer at a time: dense Desktop `DataTable`, deliberate two-column Tablet cards, and one-column Mobile cards.
- Removed `DataTable.dataCardMapping` from this live page so Desktop/Mobile interactive descendants are not duplicated in the DOM.
- Page-owned action declarations preserve view/delete eligibility and callbacks; shared action grammar owns only Mobile/Tablet placement (one direct Mobile action, two direct Tablet actions when eligible).
- Shared `Pagination` is now outside device renderers and retains caller-owned `page`, `totalPages`, `totalCount` and `setPage` truth.
- Preserved the existing client-side text-search behavior and all server query inputs exactly; no debounce or query timing change was introduced.
- Preserved the existing delete permission predicates and `useSoftDeleteActivity` mutation boundary; the backend-enforced deletion time window remains backend truth and is not duplicated in presentation code.
- Added initial-empty vs filtered-empty copy without changing create eligibility.
- Added a dedicated Field stylesheet for list/card/filter layout and Tablet touch sizing; removed the page-local `<style>` mini-system.
- Authored focused Testing Library coverage for status semantics, neutral category metadata, device action placement and callback delegation, plus source-contract tests for query/permission/mutation/collection/pagination boundaries.
- Did not mutate peer role-state files, Team Memory or Decision Log.

## Changed-file / pattern scope

Current branch scope:
- `docs/design-system-v2/31_AGENT_TEAM_WORKSTREAM.md`
- `src/components/activities/ActivityOverviewPresentation.tsx`
- `src/components/activities/ActivityOverviewPresentation.test.tsx`
- `src/pages/activities/ActivitiesPage.tsx`
- `src/pages/activities/ActivitiesPage.v2.test.ts`
- `src/styles/field-activities-v2.css`
- `team/design-system-v2/UI_IMPLEMENTATION_STATE.md` (owned state only)

No DB/migration/RPC/service/query-cache/RBAC/RLS/route-guard/GPS acquisition/business/workflow/validation/deployment file is in scope.

## Preserve / verified boundaries

- `useActivities(queryParams)` still receives `typeCategory`, `outcomeType`, `dateFrom`, `dateTo`, `employeeId`, `customerId`, `page`, `pageSize: 25` exactly from page-owned state.
- Existing client-side search still matches customer name, activity type name and outcome notes on the current server page.
- Search and every filter still reset `page` to 1; no debounce was introduced.
- Team-employee visibility remains gated by `ACTIVITIES_READ_TEAM || ACTIVITIES_READ_ALL`.
- Create remains gated by `ACTIVITIES_CREATE`.
- Delete action eligibility remains `ACTIVITIES_UPDATE_OWN || ACTIVITIES_READ_TEAM || ACTIVITIES_READ_ALL`; deletion still delegates to `useSoftDeleteActivity().mutate`.
- Activity detail navigation remains `/activities/${activity.id}` and creation remains `/activities/new`.
- Customer deep-link filtering remains initialized from the `customerId` URL search parameter and can still be cleared.
- Outcome status mapping is presentation-only; no outcome value or workflow transition is changed.
- GPS is read-only list metadata here; no GPS/device acquisition or verification behavior moved into V2 presentation.

## Device / state coverage

- **Desktop (`>=1025px`):** dense DataTable remains the active management surface with customer link, date/time, semantic outcome, notes, GPS and existing view/delete capability.
- **Tablet (`768–1024px`):** two-column Activity cards with type/customer/outcome/date/notes/GPS and up to two direct eligible actions; identity/open control uses the canonical touch target.
- **Mobile (`<=767px`):** one-column Activity cards; one primary direct action with secondary delete in canonical overflow when eligible; touch-safe identity/actions.
- **RTL/accessibility:** logical CSS, Arabic labels, explicit filter/action aria labels, readable semantic status text and focus-visible identity control.
- **States:** loading remains shared `ResponsiveCollection` presentation; initial-empty and filtered-empty are distinct; create action appears only when already eligible; delete remains omitted when unauthorized.

## Test / execution evidence

Evidence: **`TESTS_AUTHORED_NOT_EXECUTED`**.

Focused Vitest/Testing Library and source-contract tests were authored, but the automation sandbox contains no executable repository checkout / `package.json`, so `npm test`, `npm run build` and `npm run lint` were not executed. No PASS is claimed. No GitHub Actions/hosted CI was triggered and no Vercel preview/deploy was used.

No known TypeScript/build error was identified during source-level inspection. This is not an executed build/type PASS claim.

## Risks / next implementation boundary

- Draft PR #42 is still `IN_PROGRESS`; exact-head Design Director/QA review is not requested yet.
- Runtime/build evidence remains unavailable in this environment.
- The existing `FilterBar` shared component introduces its own debounced search behavior and a large embedded style block; adopting it here would alter current Activities search timing and expand component-depth scope, so this concern deliberately keeps existing immediate SearchInput/select/date behavior while moving layout CSS out of the page.
- Legacy `ActivityStatusBadge` remains used by other plan/target surfaces; this concern does not refactor it globally.
- Next action on this same PR is source-review the exact branch diff for type/composition risks and decide whether the bounded Activities-list concern is complete enough for `REVIEW`; do not start another Field surface while #42 remains active.

### Cross-role handoff
- **To:** future Product Design Director + Design QA after implementation marks this PR `REVIEW`; Development Integrator only after required gates.
- **What changed:** Activities list now has one responsive collection capability, semantic outcome state, canonical page-owned action declarations/shared placement, shared Pagination, deliberate Tablet/Mobile cards and focused authored regression protection.
- **Preserve:** all activity query inputs/search timing; team/create/delete permissions; delete mutation/RPC authority; activity/customer routes; customer URL filter; GPS/device truth; all workflow/validation/service/query-cache semantics.
- **Need from reviewers:** when requested, inspect exact PR HEAD for Arabic/RTL hierarchy, semantic outcome mapping, Mobile/Tablet action placement, Desktop density and functional isolation.
- **Blocker level:** `NONE` known at source level; implementation remains active.
- **Baseline:** `def098978efbe796306f882014e69652f014efa6`.
- **Evidence:** `TESTS_AUTHORED_NOT_EXECUTED`.
