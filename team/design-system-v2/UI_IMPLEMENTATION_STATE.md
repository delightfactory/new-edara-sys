# UI Implementation State

## Reviewed baseline

- Run date: `2026-09-17`
- Development branch: `design-system-v2-development`
- Exact slice baseline: `def098978efbe796306f882014e69652f014efa6`
- Current Development HEAD inspected this run: `b0b5240f19bbdcb889e68753e20c308539072e67`.
- Development drift from the slice baseline is governance-only: `DESIGN_DIRECTOR_STATE.md`, `DESIGN_QA_STATE.md`, `INTEGRATION_STATE.md`; no overlapping product/shared implementation change was found.
- Feature branch: `ds2/field-activities-list-v2`
- Draft PR: `#42 — DS2-FIELD-001: Activities list V2 foundation`
- Previous QA-blocked HEAD: `823c89d10201a8db68e7189803bd003c3fd9fd2f`
- Previous QA-GREEN / Product-Design-blocked HEAD: `8ac8ed1e46fd8e48f1b7b065f74ab6f1dfac21df`
- Product/test HEAD after the bounded Product Design correction and before this owned-state write: `408569579e2c516b312e18d1f482dc89d0617c41`
- Active slice: `DS2-FIELD-001 — Activities/visit/call/target lists`
- Active representative concern: `ActivitiesPage` list presentation only
- Disposition: `REVIEW — PRODUCT DESIGN P2 FIX APPLIED / FRESH EXACT-HEAD DIRECTOR + QA REVIEW REQUIRED`
- Evidence: `TESTS_AUTHORED_NOT_EXECUTED`

## Independent implementation judgment

The Product Design Director's P2 finding on exact HEAD `8ac8ed1...` is valid and source-proven: PR #42 had removed the pre-slice Mobile suppression from the PageHeader `نشاط جديد` action while the shell already owns the same `/activities/new` capability on `/activities/list` through the registered Mobile FAB under the same create permission. That creates two persistent primary create surfaces for authorized Mobile users during normal non-empty use.

The bounded correction keeps creation ownership consistent without broadening FIELD001: `ActivitiesPage` now uses the canonical `useDeviceMode()` contract and does not pass a PageHeader create action when `deviceMode === 'mobile'`. Tablet/Desktop retain the existing PageHeader create action with the same `PERMISSIONS.ACTIVITIES_CREATE` guard and `/activities/new` route. The existing empty-state CTA remains unchanged, matching the Director's explicit boundary that global empty-state/FAB convergence is later debt rather than scope for this slice.

The previously accepted collection/status/device corrections also remain intact: one live `ResponsiveCollection<ActivityRow>`, dense Desktop table, deliberate Tablet/Mobile cards, restored Tablet `start_time` parity, category represented once as neutral `Badge`, semantic outcome state, shared Pagination and page-owned action eligibility.

## Material implementation progress

- Read the fresh Product Design Director and Integration `P2 / BLOCKING` states on exact HEAD `8ac8ed1...` before modifying the PR.
- Independently revalidated the live page and canonical `useDeviceMode` boundaries before choosing the correction.
- Added `useDeviceMode()` at the Activities page composition boundary; no shared primitive or shell contract was changed.
- PageHeader `نشاط جديد` is now rendered only when `deviceMode !== 'mobile'`; Tablet/Desktop keep the page-header create capability.
- Mobile persistent creation remains shell-owned by the existing registered FAB; this PR does not alter the FAB, creation registry, AppLayout or global action system.
- Existing empty-state `StatePanel` create CTA remains permission-projected and unchanged, per the explicit bounded-fix instruction.
- Added focused source-contract protection proving the canonical device hook is used and that PageHeader create is excluded on Mobile while the permission/route/empty-state create contract remains present.
- Exact correction delta `8ac8ed1... -> 40856957...` is only two files: `ActivitiesPage.tsx` and `ActivitiesPage.v2.test.ts`.
- Development drift check `def09897... -> b0b5240...` is governance-only (`DESIGN_DIRECTOR_STATE.md`, `DESIGN_QA_STATE.md`, `INTEGRATION_STATE.md`) and does not overlap the product/shared implementation.
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

Current Product Design reviewer-fix delta is limited to the live Activities page and its focused source-contract test. No DB/migration/RPC/service/query-cache/RBAC/RLS/route-guard/GPS acquisition/business/workflow/validation/deployment file is in scope.

## Preserve / verified boundaries

- `useActivities(queryParams)` still receives `typeCategory`, `outcomeType`, `dateFrom`, `dateTo`, `employeeId`, `customerId`, `page`, `pageSize: 25` exactly from page-owned state.
- Existing client-side search still matches customer name, activity type name and outcome notes on the current server page; no debounce/timing change was introduced.
- Search and every filter still reset `page` to 1.
- Team-employee visibility remains `ACTIVITIES_READ_TEAM || ACTIVITIES_READ_ALL`.
- Create eligibility remains exactly `ACTIVITIES_CREATE`; the correction changes only persistent PageHeader placement by device, not permission or route truth.
- `/activities/new` remains the create route; Mobile persistent access is shell/FAB-owned, Tablet/Desktop retain PageHeader access, and the existing empty-state CTA remains unchanged.
- Delete eligibility remains `ACTIVITIES_UPDATE_OWN || ACTIVITIES_READ_TEAM || ACTIVITIES_READ_ALL`; deletion still delegates to `useSoftDeleteActivity().mutate(deleteTarget.id)` and backend time-window authority is not duplicated.
- Detail route remains `/activities/${activity.id}`.
- Customer deep-link filtering still initializes from `customerId` and can still be cleared.
- `useActivityTypes()` invocation remains unchanged.
- GPS remains read-only list metadata; false remains neutral `—` and no acquisition/verification meaning moved into shared presentation.
- Outcome mapping remains presentation-only semantic state; no workflow value/transition changed.
- Shared Pagination remains caller-owned for page/query truth and remains suppressed while loading, on one page, and when the live client-filtered collection is empty.

## Device / state coverage

- **Desktop (`>=1025px`):** dense DataTable remains the active management surface; PageHeader create remains available when authorized; customer/date + optional time/outcome/notes/GPS/view-delete capability are unchanged.
- **Tablet (`769–1024px`):** two-column cards retain restored optional start time, type/customer/outcome/date/notes/GPS/actions and touch-safe identity/actions; PageHeader create remains available when authorized.
- **Mobile (`<=768px`):** one-column cards retain prior information density and canonical action placement; the PageHeader persistent create action is not rendered, leaving the existing shell FAB as the persistent create owner. Existing initial/filtered-empty CTA behavior remains unchanged.
- **RTL/accessibility:** logical CSS, Arabic labels, neutral category metadata, readable semantic outcome text, explicit action/filter labels and focus-visible identity control remain intact. The device correction is render ownership, not CSS hiding.
- **States:** loading, initial-empty, filtered-empty, permission-projected create/delete, destructive confirmation and paginator suppression remain unchanged by the correction.

## Test / execution evidence

Evidence remains **`TESTS_AUTHORED_NOT_EXECUTED`**.

Focused Vitest/Testing Library and source-contract tests exist for renderer selection, query/permission/deletion boundaries, status semantics, paging, canonical breakpoints, Tablet time parity, single category representation and now Mobile persistent-create ownership. The available sandbox was inspected and contains no executable repository checkout or `package.json`, so `npm test`, `npm run build` and `npm run lint` were not executed. No PASS is claimed.

No GitHub Actions/hosted CI was triggered and no Vercel preview/deploy was used. No known TypeScript/build error was found during source inspection; this is not an executed build/type PASS claim.

## Risks / review boundary

- Exact-head Product Design Director and Design QA review is mandatory because the PR HEAD moved after the prior QA GREEN and Product Design blocker.
- The pre-existing Mobile empty-state CTA + shell FAB duplication remains a documented non-blocking later action-convergence/runtime watch and was intentionally not expanded into this slice.
- Runtime/build evidence remains unavailable in this environment.
- The local Activities filter composition still deliberately preserves immediate search/filter semantics rather than adopting legacy `FilterBar`; shared filter convergence remains later component-depth work.
- Legacy activity plan/target/create/detail surfaces remain outside this representative concern.

### Cross-role handoff
- **To:** Product Design Director + Design QA for fresh exact-head review; Development Integrator only after both fresh gates.
- **What changed:** the Director's P2 Mobile action-ownership blocker is corrected on the same PR: PageHeader create is omitted on Mobile via canonical `useDeviceMode`, while Tablet/Desktop retain it and Mobile persistent creation remains shell-FAB-owned.
- **Preserve:** every activity query/search/filter input and timing; team/create/delete permissions; `/activities/new` and detail routes; delete mutation/backend authority; customer deep-link; GPS/device/workflow/service/validation/query-cache truth; one live `ResponsiveCollection`; shared Pagination; semantic outcome/neutral category treatment; restored Tablet time parity; existing shell creation registry/FAB ownership.
- **Need from you:** independently review the exact final PR HEAD produced by this owned-state write. QA must issue fresh `SOURCE_REVIEW_PASS + AGENT-REVIEW: GREEN-DEV` only if the moved head is clean; Product Design Director must explicitly close the same-head P2 contradiction. Integrator remains `NO_MERGE` until both are fresh and no material blocker remains.
- **Blocker level:** `NONE` from implementation after the bounded correction; external review gates remain pending.
- **Baseline:** slice `def098978efbe796306f882014e69652f014efa6`; Development inspected `b0b5240f19bbdcb889e68753e20c308539072e67`; product/test correction HEAD before state write `408569579e2c516b312e18d1f482dc89d0617c41`.
- **Evidence:** `TESTS_AUTHORED_NOT_EXECUTED`.
