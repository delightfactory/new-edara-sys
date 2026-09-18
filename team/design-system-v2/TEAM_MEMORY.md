# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-WORK-001`.
- Current integrated product HEAD: `57747123643d0dd846cbda3ef340e9463a5f7647` from PR #44.
- Development coordination HEAD immediately before this memory write: `1d923bca7b63d969e216625a94eb08dd0c41d585`.
- Current single READY slice: `DS2-WORK-002 — Work Hub/detail/management state-surface convergence`.
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
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-WORK-001 — Create Task form composition foundation`

Result:
- PR #44 exact reviewed HEAD `6eb3be28216ec1370ccd5fceced7ea8c5c224cd0` received `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- Product Design independently accepted the same exact HEAD with `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Evidence remains honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview PASS is claimed.
- Squash merge commit: `57747123643d0dd846cbda3ef340e9463a5f7647`.
- `/work/new` now uses the shared V2 form grammar while retaining the existing four-section Arabic operational order.
- Safe paired groups remain one column on Mobile and two on Tablet/Desktop; narrative/full-width controls remain unsqueezed.
- V2 native input/select sizing is owned by `.ds-field`: `--ds-control-height-touch` through Tablet/Mobile and `--ds-control-height-standard` on Desktop; textarea keeps the 80px floor.
- Cancel/create remain non-sticky and touch-safe with existing secondary/primary hierarchy and pending/loading truth.
- Shared `Field` owns label/hint/error relationships and invalid/description semantics without absorbing Work validation truth.
- `toIso`, assignment/defaulting, owner-vs-assignee meaning, acknowledgement eligibility/reset, validation wording/date rule, priority/visibility/completion mode, `useCreateTask`, payload/`activate: true`, toasts/navigation, queries/services/permissions/RBAC/RLS/workflow/backend truth remain unchanged and page/domain-owned.

## Current single READY slice

`DS2-WORK-002 — Work Hub/detail/management state-surface convergence`

Intent:
- continue Work Management convergence before moving deeper into Reports, without reopening completed slices for ad-hoc polishing;
- Product Design Director must inspect representative Work Hub, task-detail, management/supervisor and state surfaces on the exact latest Development baseline and bound one smallest dependency-safe presentation-only concern;
- prefer the established V2 shell, collection, form, action, status and feedback grammar before inventing Work-local presentation patterns;
- preserve Work query/service/permission/ownership/responsibility/workflow/validation/state-machine truth exactly;
- Mobile remains operational-first, Tablet deliberate/touch-first, Desktop efficient for planning/review/management;
- no backend/business/workflow/query-cache/permission/validation-semantic change, deployment, preview or `main` work.

Remaining Field create/detail convergence and further Work convergence remain explicit backlog debt and must be reactivated only through separately bounded dependency-safe slices.

## Latest role positions

### Product Design Director
- Independently accepted PR #44 exact HEAD `6eb3be28216ec1370ccd5fceced7ea8c5c224cd0` with `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Confirmed the Field-scoped control-geometry correction, Work form hierarchy and responsive composition fit the North Star while preserving Work functional truth.
- WORK001 acceptance is consumed by the merge; next responsibility is to bound one smallest WORK002 concern from the exact latest Development baseline.

### UI Production Engineer
- Completed the bounded WORK001 Create Task migration and authored focused component/source/style contracts.
- Preserved Work validation, assignment/defaulting, owner/assignee/acknowledgement, payload/activation, navigation and service/query/workflow truth; evidence remained `TESTS_AUTHORED_NOT_EXECUTED`.
- Development-side UI state is lifecycle-stale from FIELD002 and must not be treated as an active competing slice; a new WORK002 implementation begins only after Product Design records a fresh boundary.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` on `6eb3be28216ec1370ccd5fceced7ea8c5c224cd0` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Confirmed six-file UI/Test/Governance-only scope, synchronized known TypeScript fixes, no review threads and no functional-isolation breach.
- Approval is consumed by the merge and must not be reused for WORK002.

### Development Integrator
- Revalidated PR #44 base/head/reviews/threads/diff, same-head Product Design + QA gates, Development drift and mergeability.
- Confirmed post-sync Development drift was role-state governance only and did not overlap WORK001 product/shared files.
- Transitioned the draft PR to ready-for-review without moving its head, then squash-merged with expected-head protection as `57747123643d0dd846cbda3ef340e9463a5f7647`.
- Integration state is `MERGED_GREEN_DEV` for WORK001; workstream marks WORK001 DONE and exactly one next slice, WORK002, READY.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Customer, Sales, Inventory, Procurement, Finance, HR, Field and Work business/query/permission/workflow truths remain page/domain/service-owned.
- Work shared form composition is presentation-only: page/domain code still owns validation, assignment/defaulting, owner-vs-assignee meaning, acknowledgement eligibility/reset, completion mode, priority/visibility, ISO conversion, payload/activation, mutation/toast/navigation and all state-machine truth.
- Native form-control geometry introduced through V2 form convergence is owned by the explicit `.ds-field` boundary; generic legacy `.form-*` consumers outside V2 Field must not be redefined incidentally by a bounded slice.
- Canonical semantic control-height roles are `--ds-control-height-touch` for touch-first Mobile/Tablet and `--ds-control-height-standard` for deliberate Desktop density; textarea keeps its larger content floor where defined.
- Field activity query/search/filter/paging, routes, GPS/device semantics, validation, payloads, mutations and workflow truth must not leak into shared presentation.
- The ActivityForm shared form composition is presentation-only; excluded legacy call/link sub-controls remain debt, not canonical V2 patterns.
- Persistent primary-action ownership must be deliberate by device: Activities list Mobile uses the shell `new-activity` FAB while Tablet/Desktop use the PageHeader create action.
- Neutral categorical metadata uses `Badge`; semantic operational/workflow/result state uses `StatusBadge`.
- Page/domain code owns action eligibility/order/callback truth; shared `AppAction + resolveActionSet` owns device placement when adopted.
- Shared `Pagination` owns presentation/accessibility/page-change requests only; caller/domain code owns page/query truth.
- Shared `TransactionHeader`, Stepper, `ProcessProgress`, `PrimaryTaskAction`, form patterns and other V2 components own presentation/interaction mechanics, never business eligibility or workflow truth.
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

- Development evidence through WORK001 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- Work Hub/detail/management/supervisor/state surfaces remain unbounded convergence debt; WORK002 must select one smallest representative concern rather than become a broad rewrite.
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
- Responsive composition must preserve meaningful Tablet capability parity even when representation changes.
- Shared `MetricGrid + StatCard` and `Pagination` can project page-owned values/query state without absorbing calculations or query truth.
- A live migrated surface may justify narrow shared-component hardening, but excluded legacy sub-controls should be left as explicit debt rather than accidentally blessed as the new system pattern.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect representative Work Hub/detail/management/supervisor/state surfaces on the exact latest `design-system-v2-development` baseline and bound the smallest presentation-only concern for `DS2-WORK-002`, explicitly preserving Work query/service/permission/ownership/responsibility/workflow/validation/state-machine truth and the full Reports/Admin/Global roadmap.

UI Production Engineer should bootstrap only from the exact latest Development HEAD after that boundary is recorded and implement one coherent concern. Design QA should independently review the exact stable PR HEAD. Development Integrator should no-op until that head receives fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and all normal gates pass.
