# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-WORK-002`.
- Current integrated product HEAD: `add39ea8ee76b61d9a5a5938aa6cd03e2cc13456` from PR #46.
- Development coordination HEAD immediately before this memory write: `add39ea8ee76b61d9a5a5938aa6cd03e2cc13456`.
- Current single READY slice: `DS2-WORK-003 — Work detail/management state-surface convergence`.
- `main` remains frozen until explicit owner approval.
- Vercel preview is user-requested only.
- GitHub Actions / hosted CI remain forbidden for normal Design System development.
- Product target remains one deep, premium Arabic-first operational Design System across the entire EDARA interface.
- Mobile is the primary daily operational surface; Tablet is deliberate and touch-first; Desktop preserves management/review/data-entry density and speed.
- Repository-native shared memory remains active: every DS2 role reads Team Memory and all peer role states before acting.

## Current integrated system

Development now includes:
- semantic foundations and V2 primitives/patterns;
- responsive shell/navigation/form/collection/action composition foundations;
- navigation registry and deliberate Tablet shell behavior;
- Dashboard V2;
- Customers List and Customer form/detail migrations with shared form/Tabs grammar;
- Sales list/form/detail foundations including shared Stepper and transaction action placement;
- Inventory stock and transfer collections using one `ResponsiveCollection` boundary per live surface;
- Procurement Purchase Invoice list/form-shell migrations, initial-vs-filtered empty semantics and bounded DataTable paginator hardening;
- Finance Vault overview with shared `MetricGrid + ResponsiveCollection` and Payment Receipt detail using shared `TransactionHeader + StatusBadge + AppAction/resolveActionSet`;
- HR Attendance Check-in operational-task controls using shared `ProcessProgress + PrimaryTaskAction + AlertPanel` while Attendance/GPS/business truth remains page/domain-owned;
- HR Employees administration list using one live `ResponsiveCollection<HREmployee>`, shared semantic status/action/card grammar and shared presentation-only `Pagination` with canonical Tablet touch targets;
- Field Activities list using one live `ResponsiveCollection<ActivityRow>`, semantic outcome state, neutral category metadata, shared Pagination/action placement and deliberate device-specific persistent-create ownership;
- Field Activity normal create/edit flow using shared `FormSection + FormGrid + FormActions + Button` while all Field business/GPS/query/validation/mutation truth remains page/domain-owned;
- Work Create Task flow using shared `FormSection + FormGrid + Field + FormActions + Button`, plus Field-scoped semantic native-control sizing that preserves legacy consumers outside V2 `Field`;
- Work Hub view-mode selection using shared `SegmentedControl` for `actions | work | attention` while Work mode/filter/query/workflow truth remains page/domain-owned;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-WORK-002 — Work Hub view-mode selector convergence`

Result:
- PR #46 exact reviewed HEAD `e3d557d59a811f3c896ffe90922e9512bbb3cdee` received `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- Product Design independently accepted the same exact HEAD with `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Evidence remains honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview PASS is claimed.
- Squash merge commit: `add39ea8ee76b61d9a5a5938aa6cd03e2cc13456`.
- `/work` now consumes shared `SegmentedControl` instead of the page-local `.work-segmented` renderer.
- Exact mode values/order/Arabic labels/default remain `actions | work | attention` → `مطلوب مني الآن | كل الأعمال | يحتاج انتباه`, with page-owned `mode` and `setMode` unchanged.
- Shared native-button, `aria-pressed`, focus-visible, selected-surface/elevation, canonical Mobile/Tablet touch geometry and Mobile horizontal-containment behavior now apply to this selector.
- Selector-specific Work CSS was retired without broad Work styling cleanup.
- `useMyActionInbox(100)`, `useVisibleWorkItems({ limit: 150 })`, operational flags, filtering/search, summary-card callbacks, permissions, request routing, Mobile create behavior and all Work service/query/workflow/state-machine truth remain unchanged and page/domain-owned.

## Current single READY slice

`DS2-WORK-003 — Work detail/management state-surface convergence`

Intent:
- continue Work Management convergence before Reports/Analytics without reopening completed WORK001/WORK002 for ad-hoc polishing;
- Product Design Director must inspect representative Work detail, Supervisor/Team, management/configuration and state surfaces on the exact latest Development baseline and bound one smallest dependency-safe presentation-only concern;
- prefer established V2 shell, action, status, collection, form, feedback and state grammar before inventing Work-local patterns;
- preserve Work query/service/permission/ownership/responsibility/validation/workflow/state-machine truth exactly;
- Mobile remains operational-first, Tablet deliberate/touch-first, Desktop efficient for planning/review/management;
- no backend/business/workflow/query-cache/permission/validation-semantic change, deployment, preview or `main` work.

Remaining Field create/detail convergence and further Work convergence beyond WORK003 remain explicit backlog debt and must be reactivated only through separately bounded dependency-safe slices.

## Latest role positions

### Product Design Director
- Independently accepted PR #46 exact HEAD `e3d557d59a811f3c896ffe90922e9512bbb3cdee` with `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Confirmed shared `SegmentedControl` is the correct system primitive for the bounded Work Hub view-mode concern while Work functional truth remains page/domain-owned.
- WORK002 acceptance is consumed by the merge; next responsibility is to inspect the latest Development baseline and bound one smallest WORK003 concern.

### UI Production Engineer
- Completed bounded WORK002 selector convergence and authored focused behavior/source contracts.
- Preserved Work query/filter/search/summary-card/permission/request/routing/Mobile-create/workflow truth; evidence remained `TESTS_AUTHORED_NOT_EXECUTED`.
- Development copy of UI state may remain lifecycle-stale after the merge until the next implementation run; no competing implementation slice is active before Product Design bounds WORK003.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` on `e3d557d59a811f3c896ffe90922e9512bbb3cdee` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Confirmed six-file UI/Test/Governance-only scope, no review threads, no functional-isolation breach and no known source-visible build/type blocker.
- Approval is consumed by the merge and must not be reused for WORK003.

### Development Integrator
- Revalidated PR #46 base/head/reviews/threads/diff, same-head Product Design + QA gates, Development drift and mergeability.
- Confirmed Development drift from the PR base was governance-only and did not overlap WORK002 product/shared files.
- Transitioned the draft PR to ready-for-review without moving its head, then squash-merged with expected-head protection as `add39ea8ee76b61d9a5a5938aa6cd03e2cc13456`.
- Integration state is `MERGED_GREEN_DEV` for WORK002; workstream marks WORK002 DONE and exactly one next slice, WORK003, READY.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Customer, Sales, Inventory, Procurement, Finance, HR, Field and Work business/query/permission/workflow truths remain page/domain/service-owned.
- Work shared form composition is presentation-only: page/domain code still owns validation, assignment/defaulting, owner-vs-assignee meaning, acknowledgement eligibility/reset, completion mode, priority/visibility, ISO conversion, payload/activation, mutation/toast/navigation and all state-machine truth.
- Work Hub view-mode presentation is now shared through `SegmentedControl`; page/domain code still owns mode values, filtering/search/query ownership, summary-card callbacks, permissions, request routing, Mobile create behavior and workflow/state-machine meaning.
- Native form-control geometry introduced through V2 form convergence is owned by the explicit `.ds-field` boundary; generic legacy `.form-*` consumers outside V2 Field must not be redefined incidentally by a bounded slice.
- Canonical semantic control-height roles are `--ds-control-height-touch` for touch-first Mobile/Tablet and `--ds-control-height-standard` for deliberate Desktop density; textarea keeps its larger content floor where defined.
- Field activity query/search/filter/paging, routes, GPS/device semantics, validation, payloads, mutations and workflow truth must not leak into shared presentation.
- The ActivityForm shared form composition is presentation-only; excluded legacy call/link sub-controls remain debt, not canonical V2 patterns.
- Persistent primary-action ownership must be deliberate by device: Activities list Mobile uses the shell `new-activity` FAB while Tablet/Desktop use the PageHeader create action.
- Neutral categorical metadata uses `Badge`; semantic operational/workflow/result state uses `StatusBadge`.
- Page/domain code owns action eligibility/order/callback truth; shared `AppAction + resolveActionSet` owns device placement when adopted.
- Shared `Pagination` owns presentation/accessibility/page-change requests only; caller/domain code owns page/query truth.
- Shared `TransactionHeader`, Stepper, `ProcessProgress`, `PrimaryTaskAction`, form patterns, `SegmentedControl` and other V2 components own presentation/interaction mechanics, never business eligibility or workflow truth.
- Shared `FormSection`/`Card` own internal structure, not automatic external sibling spacing; consumer composition may own tokenized logical separation where required.
- Canonical touch targets remain first-class through Tablet for touch-active controls; Desktop may intentionally preserve denser pointer-oriented controls.
- Mobile operational actions remain clear and touch-ready; Tablet must be deliberate; Desktop must remain efficient for management/review/data entry.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Initial-empty and filtered-empty remain distinct when filtering/search exists; search affordance copy must match actual service/query truth.
- Hidden duplicate device interaction trees should be avoided where device-aware composition exists.
- Each agent writes only its own specialist state; all agents read every specialist state.
- Durable decisions belong in the Decision Log; routine progress does not.
- No hosted CI, Vercel preview or `main` activity from scheduled agents.

## Known evidence / risks

- Development evidence through WORK002 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- Work detail, Supervisor/Team, management/configuration and broader loading/empty/error/offline/state surfaces remain unbounded convergence debt; WORK003 must select one smallest representative concern rather than become a broad rewrite.
- Existing Work responsibility summary and acknowledgement checkbox remain Work-owned sub-surfaces and are not yet canonical shared patterns.
- Remaining Field create/detail surfaces still need later bounded convergence before the module can be considered fully aligned.
- The pre-existing Mobile Activities empty-state CTA + shell FAB coexistence remains a later action-convergence/runtime-density watch.
- Full shared Pagination convergence, FilterBar/search/filter convergence, generic DataTable row keyboard semantics, SearchInput clear accessibility, error/offline-state convergence and dense-table overflow semantics remain broader shared debt.
- `DocumentActions` Mobile density/touch geometry, Procurement `InlineCombobox` keyboard accessibility and similar component-depth debt remain outside completed slices.

## Reusable patterns learned

- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared navigation/action declarations should own placement decisions rather than pages inventing coordinates.
- `TransactionHeader` has cross-module proof in Sales and Finance while domains retain eligibility/workflow truth.
- `AppAction + resolveActionSet` can preserve page-owned multi-action truth while enforcing device placement limits; a single context-dependent operational next action may instead use a thin `PrimaryTaskAction` composition.
- Operational process progress and feedback can be standardized without absorbing domain truth through `ProcessProgress` and `AlertPanel`.
- Shared form composition can be standardized independently from business field semantics. `PageHeader + FormSection + FormGrid + Field + FormActions` now has proof across Customer, Sales, Procurement, Field and Work.
- Shared CSS hardening should be attached to an explicit adopted V2 boundary such as `.ds-field` when generic legacy classes have wider unreviewed consumers; this preserves migration discipline and avoids incidental product-wide blast radius.
- `FormGrid` can express deliberate one-column Mobile, capped/two-column Tablet and denser Desktop grouping without changing page-owned field semantics.
- Consumer-owned tokenized section spacing can preserve hierarchy without adding external margins to shared sections.
- Shared `ResponsiveCollection` has proof across Sales Orders, Inventory Stock, Inventory Transfers, Procurement Purchase Invoices, Finance Vaults, HR Employees and Field Activities.
- `SegmentedControl` is the canonical compact single-choice view/filter presentation when the page/domain continues to own the selected value and business meaning; replacing a local selector can converge touch/focus/ARIA behavior without moving filtering or workflow truth.
- Responsive composition must preserve meaningful Tablet capability parity even when representation changes.
- Shared `MetricGrid + StatCard` and `Pagination` can project page-owned values/query state without absorbing calculations or query truth.
- A live migrated surface may justify narrow shared-component hardening, but excluded legacy sub-controls should be left as explicit debt rather than accidentally blessed as the new system pattern.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect representative Work detail, Supervisor/Team, management/configuration and state surfaces on the exact latest `design-system-v2-development` baseline and bound the smallest presentation-only concern for `DS2-WORK-003`, explicitly preserving Work query/service/permission/ownership/responsibility/validation/workflow/state-machine truth and the full Reports/Admin/Global roadmap.

UI Production Engineer should bootstrap only from the exact latest Development HEAD after that boundary is recorded and implement one coherent concern. Design QA should independently review the exact stable PR HEAD. Development Integrator should no-op until that head receives fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and all normal gates pass.