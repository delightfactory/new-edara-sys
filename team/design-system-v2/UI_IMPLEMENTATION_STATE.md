# UI Implementation State

## Reviewed baseline

- Run date: `2026-09-17`
- Development branch: `design-system-v2-development`
- Exact slice baseline / current Development HEAD inspected: `def098978efbe796306f882014e69652f014efa6`
- Feature branch: `ds2/field-activities-list-v2`
- Draft PR: `#42 — DS2-FIELD-001: Activities list V2 foundation`
- Product/test HEAD before this owned-state write: `f012e4f3059ba7cd6ec27734faa815ba944b70c1`
- Active slice: `DS2-FIELD-001 — Activities/visit/call/target lists`
- Active representative concern: `ActivitiesPage` list presentation only
- Disposition: `IN_PROGRESS — REPRESENTATIVE LIST IMPLEMENTED / POST-CORRECTION EXACT-DIFF PASS PENDING`
- Evidence: `TESTS_AUTHORED_NOT_EXECUTED`

## Independent implementation judgment

`ActivitiesPage` is the smallest dependency-safe representative Field list on the current Development baseline. It exposes the recurring V2 gaps directly — a legacy dual table/card render path through `DataTable.dataCardMapping`, local outcome color badges, direct page-owned device action placement and page-local list styling — while its query, permission, delete-RPC, customer deep-link and routing truth can remain untouched.

The implementation therefore migrates only the Activities list capability. It does not broaden into call plans, visit plans, targets, activity create/detail flows, GPS acquisition, field workflow or backend semantics.

## Material implementation progress

- Created `ActivityOverviewPresentation` as a thin Field-domain adapter over shared `Card + KeyValueList + StatusBadge + Badge + Button + AppAction/resolveActionSet`.
- Replaced legacy outcome color badges on this list with readable semantic V2 outcome tones while preserving the existing Arabic outcome labels.
- `ActivitiesPage` now mounts exactly one `ResponsiveCollection<Activity>` renderer at a time: dense Desktop `DataTable`, deliberate two-column Tablet cards and one-column Mobile cards.
- Removed `DataTable.dataCardMapping` from this live page so Desktop/Mobile interactive descendants are not duplicated in the DOM.
- Page-owned action declarations preserve view/delete eligibility and callbacks; shared action grammar owns only Mobile/Tablet placement (one direct Mobile action, two direct Tablet actions when eligible).
- Shared `Pagination` is now outside device renderers and retains caller-owned `page`, `totalPages`, `totalCount` and `setPage` truth.
- Preserved the existing client-side text-search behavior and all server query inputs exactly; no debounce or query timing change was introduced.
- Preserved the existing delete permission predicates and `useSoftDeleteActivity` mutation boundary; the backend-enforced deletion time window remains backend truth and is not duplicated in presentation code.
- Added initial-empty vs filtered-empty copy while keeping the authorized create action available in either empty state and in the PageHeader.
- Added a dedicated Field stylesheet for list/card/filter layout and Tablet touch sizing; removed the page-local `<style>` mini-system.
- Source self-review closed five bounded presentation/capability risks before review handoff:
  - authorized create remains available in filtered-empty Mobile states;
  - shared Pagination remains suppressed when the live client-side filtered collection is empty, matching previous visible behavior;
  - the card icon uses existing semantic token `--bg-surface-2`, not a nonexistent token;
  - Field CSS now uses canonical Mobile `<=768px` exactly, matching `useDeviceMode` / `ResponsiveCollection` rather than leaving a 768px composition mismatch;
  - `gps_verified === false` remains neutral `—` metadata instead of being reinterpreted as the negative workflow-like phrase `غير موثق`.
- Authored focused Testing Library coverage for status semantics, neutral category/GPS metadata, device action placement and callback delegation, plus source-contract tests for query/permission/mutation/collection/pagination/capability/breakpoint boundaries.
- Did not mutate peer role-state files, Team Memory or Decision Log.

## Changed-file / pattern scope

Current branch scope remains 7 UI/Test/Governance-owned files:
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
- Create remains gated by `ACTIVITIES_CREATE`; the migration does not remove the authorized creation path from a filtered-empty Mobile state.
- Delete action eligibility remains `ACTIVITIES_UPDATE_OWN || ACTIVITIES_READ_TEAM || ACTIVITIES_READ_ALL`; deletion still delegates to `useSoftDeleteActivity().mutate`.
- Activity detail navigation remains `/activities/${activity.id}` and creation remains `/activities/new`.
- Customer deep-link filtering remains initialized from the `customerId` URL search parameter and can still be cleared.
- Outcome status mapping is presentation-only; no outcome value or workflow transition is changed.
- GPS is read-only list metadata here; `true` is shown as verified while false remains the same neutral absence marker used by the prior list. No GPS/device acquisition or verification behavior moved into V2 presentation.
- Pagination remains hidden while loading, on one page, and when the live filtered collection is empty, preserving the previous visible paging behavior while using shared `Pagination`.
- `useActivityTypes()` remains invoked exactly as on the baseline; this slice does not alter its query/service behavior.

## Device / state coverage

- **Desktop (`>=1025px`):** dense DataTable remains the active management surface with customer link, date/time, semantic outcome, notes, GPS and existing view/delete capability.
- **Tablet (`769–1024px`):** two-column Activity cards with type/customer/outcome/date/notes/GPS and up to two direct eligible actions; identity/open control uses the canonical touch target.
- **Mobile (`<=768px`):** one-column Activity cards; one primary direct action with secondary delete in canonical overflow when eligible; touch-safe identity/actions; authorized create remains available; CSS composition uses the same exact canonical breakpoint as `useDeviceMode`.
- **RTL/accessibility:** logical CSS, Arabic labels, explicit filter/action aria labels, readable semantic status text and focus-visible identity control.
- **States:** loading remains shared `ResponsiveCollection` presentation; initial-empty and filtered-empty are distinct; create remains permission-projected; delete remains omitted when unauthorized; empty filtered result does not expose a misleading paginator; unverified GPS remains neutral metadata.

## Test / execution evidence

Evidence: **`TESTS_AUTHORED_NOT_EXECUTED`**.

Focused Vitest/Testing Library and source-contract tests were authored, but the automation sandbox contains no executable repository checkout / `package.json`, so `npm test`, `npm run build` and `npm run lint` were not executed. No PASS is claimed. No GitHub Actions/hosted CI was triggered and no Vercel preview/deploy was used.

No known TypeScript/build error was identified during source-level inspection. This is not an executed build/type PASS claim.

## Risks / next implementation boundary

- Draft PR #42 remains `IN_PROGRESS`; exact-head Design Director/QA review is not requested yet because the exact diff moved during the final source pass and needs one post-correction re-read.
- Runtime/build evidence remains unavailable in this environment.
- The existing `FilterBar` shared component introduces its own debounced search behavior and a large embedded style block; adopting it here would alter current Activities search timing and expand component-depth scope, so this concern deliberately keeps existing immediate `SearchInput`/select/date behavior while moving layout CSS out of the page.
- Legacy `ActivityStatusBadge` remains used by other plan/target surfaces; this concern does not refactor it globally.
- No review submissions or inline review threads existed before the latest bounded corrections.
- Next action on this same PR is one post-correction exact-diff source pass; if no material defect is found, move this bounded Activities-list concern to `REVIEW` and request fresh Product Design Director + Design QA exact-head review. Do not start another Field surface while #42 remains active.

### Cross-role handoff
- **To:** Product Design Director + Design QA only after implementation marks this PR `REVIEW`; Development Integrator only after required gates.
- **What changed:** Activities list now has one responsive collection capability, semantic outcome state, canonical page-owned action declarations/shared placement, shared Pagination, deliberate canonical-breakpoint Tablet/Mobile cards and focused authored regression protection; self-review has already closed create/paging/token/breakpoint/GPS presentation risks.
- **Preserve:** all activity query inputs/search timing; team/create/delete permissions; delete mutation/RPC authority; activity/customer routes; customer URL filter; `useActivityTypes()` invocation; GPS/device truth; all workflow/validation/service/query-cache semantics.
- **Need from reviewers:** once moved to REVIEW, inspect the exact PR HEAD for Arabic/RTL hierarchy, semantic outcome mapping, Mobile/Tablet action placement, Desktop density and functional isolation.
- **Blocker level:** `NONE` known at source level; implementation remains active pending one post-correction exact-diff pass.
- **Baseline:** `def098978efbe796306f882014e69652f014efa6`.
- **Evidence:** `TESTS_AUTHORED_NOT_EXECUTED`.
