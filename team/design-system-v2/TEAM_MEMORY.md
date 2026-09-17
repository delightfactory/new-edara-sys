# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-HR-002`.
- Current integrated product HEAD: `b1c9ae6dd78b57f9708e3e5d40fe0b2baac6adbc` from PR #41.
- Development coordination HEAD immediately before this memory write: `b1d14a4b3ce81e48814f96f2956d1418ecc4d934`.
- Current single READY slice: `DS2-FIELD-001 — Activities/visit/call/target lists`.
- `main` remains frozen until explicit owner approval.
- Vercel preview is user-requested only.
- GitHub Actions / hosted CI remain forbidden for normal Design System development.
- Product target remains one deep, premium Arabic-first operational Design System across the entire EDARA interface.
- Mobile is the primary daily operational surface; Tablet is deliberate; Desktop preserves management/review/data-entry density and speed.
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
- HR Employees administration list using one live `ResponsiveCollection<HREmployee>`, shared semantic status/action/card grammar, and shared presentation-only `Pagination` with canonical Tablet touch targets;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-HR-002 — HR admin lists/forms` — representative concern: Employees administration list

Result:
- PR #41 exact reviewed HEAD `984750b5d933e26fea62995d3bf782f89a85b509` received `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- Evidence remains honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview PASS is claimed.
- Squash merge commit: `b1c9ae6dd78b57f9708e3e5d40fe0b2baac6adbc`.
- Live `EmployeesPage` now uses one `ResponsiveCollection<HREmployee>` with dense Desktop `DataTable`, deliberate Tablet two-column cards and Mobile one-column cards rather than duplicate hidden device interaction trees.
- Employee summary/card presentation reuses shared `MetricGrid`, `StatCard`, `Card`, `KeyValueList`, `StatusBadge`, neutral `Badge`, `Button` and canonical `AppAction/resolveActionSet` placement.
- Employee workflow status remains semantic; field/office is neutral categorical metadata; caller/page code retains action eligibility and callbacks.
- Shared `Pagination` was extracted from `DataTable` as presentation only. It preserves the established five-page window, callback targets, disabled boundaries, Arabic labels and `aria-current="page"`, and canonical touch targets now apply through Tablet while compact Desktop density remains intact.
- Initial-empty and filtered-empty presentation are distinct without changing employee data/query behavior.
- Employee search/department/status/page/pageSize inputs, page resets, stats behavior including the pre-existing current-page field metric, salary/create/edit/view permissions, profile route, `EmployeeForm`, service/query/workflow truth remain unchanged.
- The Employees filter/search row is accepted only as page composition; it is not a reusable HR filter grammar and does not supersede future shared filter convergence.

## Current single READY slice

`DS2-FIELD-001 — Activities/visit/call/target lists`

Intent:
- continue the North-Star roadmap into Field Activities / Targets rather than extending HR polishing;
- Product Design Director must inspect representative field activity/visit/call/target list surfaces on the exact latest Development baseline and bound the smallest dependency-safe presentation-only concern;
- prefer established `ResponsiveCollection`, semantic status, `AppAction/resolveActionSet`, shared summary/state patterns and current V2 primitives before adding field-local presentation grammar;
- preserve activity/visit/call/target query, service, permission, route, GPS/device, validation, ownership and workflow truth exactly;
- Mobile remains the primary operational field surface; Tablet must be deliberately composed; Desktop must preserve management density and capability parity;
- no backend/business/workflow/query-cache/permission/validation-semantic change, broad field redesign, deployment, preview or `main` work.

## Latest role positions

### Product Design Director
- Independently accepted HR002 / PR #41 exact HEAD `984750b5d933e26fea62995d3bf782f89a85b509` with no Design-System blocker.
- Confirmed one live responsive employee collection, semantic status vs neutral categorical metadata, presentation-only Pagination and preservation of HR query/permission/workflow truth.
- Recorded only a WATCH that the local Employees filter row must not become the reusable filter-system answer.
- HR002 acceptance is consumed by the merge; next responsibility is to bound FIELD001 from the exact latest Development baseline.

### UI Production Engineer
- HR002 feature work completed the Employees list migration and the bounded Tablet touch correction with focused authored tests.
- Evidence remained `TESTS_AUTHORED_NOT_EXECUTED`; no product/test code moved after exact-head QA approval.
- That handoff is consumed by the merge; next implementation must wait for the Director's explicit FIELD001 boundary and start from the latest Development HEAD.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` on `984750b5d933e26fea62995d3bf782f89a85b509` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Confirmed the prior P2 Tablet touch blocker was closed, the 11-file slice remained functionally isolated, no known build/type failure existed, and no unresolved review thread remained.
- Approval is consumed by the merge and must not be reused for FIELD001.

### Development Integrator
- Revalidated PR #41 base/head/reviews/threads/diff, Development drift and role-state freshness.
- Confirmed the previous Integration blocker applied only to superseded HEAD `1c0ad8b...`; fresh Director/QA states on `984750b5...` recorded no blocker.
- Transitioned the draft PR to ready-for-review without moving its head, then squash-merged with expected-head protection as `b1c9ae6dd78b57f9708e3e5d40fe0b2baac6adbc`.
- Integration state is `MERGED_GREEN_DEV` for HR002; workstream marks HR002 DONE and exactly one next slice, FIELD001, READY.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Customer, Sales, Inventory, Procurement, Finance, HR and Field business/query/permission/workflow truths remain page/domain/service-owned.
- HR attendance/time, GPS/device capability, leave, payroll, employee/permission/query/service/workflow truth must not leak into shared presentation.
- Shared `TransactionHeader` owns presentation/device placement, not business eligibility or workflow truth.
- Shared Stepper owns visual/interaction mechanics only; page/domain code owns workflow reachability and validation truth.
- Shared `ProcessProgress` owns progress presentation/accessibility only; caller/domain code owns process state truth and transition meaning.
- Shared `PrimaryTaskAction` owns presentation over `Button` only; caller/domain code owns eligibility, label/action meaning and callback truth.
- A single context-dependent operational next action should not be forced into `AppAction/resolveActionSet`; that registry remains for multi-action placement.
- Dynamic success/error feedback should use shared semantic live-region contracts such as `AlertPanel` without moving result/business semantics into the shared layer.
- Shared `FormSection`/`Card` own internal structure, not automatic external sibling spacing; consumer composition may own tokenized logical separation where required.
- Complete shared Tabs keyboard/focus/ARIA/RTL semantics remain system-owned; do not reintroduce partial page-local ARIA.
- Neutral categorical metadata uses `Badge`; semantic operational/workflow state uses `StatusBadge`.
- Page/domain code owns action eligibility/order/callback truth; shared `AppAction + resolveActionSet` owns device placement when adopted.
- Shared `Pagination` owns presentation, accessible paging controls and page-change requests only; caller/domain code owns page/query truth.
- Shared Pagination's established five-page window, logical Arabic previous/next, accessible names, disabled boundaries and `aria-current="page"` must remain stable unless a declared component-depth slice changes the contract.
- Canonical touch targets remain first-class through Tablet for touch-active controls; Desktop may intentionally preserve denser pointer-oriented controls.
- The Employees filter/search row is local page composition, not a reusable HR/filter-system contract.
- Mobile operational actions remain clear and touch-ready; Tablet must be deliberate; Desktop must remain efficient for management/review/data entry.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Initial-empty and filtered-empty are distinct states when filtering/search exists.
- Search affordance copy must match actual service/query truth.
- Hidden duplicate device interaction trees should be avoided where device-aware composition exists.
- Each agent writes only its own specialist state; all agents read every specialist state.
- Durable decisions belong in the Decision Log; routine progress does not.
- No hosted CI, Vercel preview or `main` activity from scheduled agents.

## Known evidence / risks

- Development evidence through HR002 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- Full shared Pagination convergence remains incomplete: the shared extraction is now proven in `DataTable` and the Employees responsive-card surface, but broader consumers have not all converged.
- The Employees `fieldEmpCount` metric remains intentionally current-page scoped while neighboring metrics are global; that is preserved pre-existing data behavior and any semantic change requires separate product/query work.
- The local Employees filter/search composition must not be copied as the system filter answer; FilterBar/search/filter convergence remains component-depth debt.
- Generic `DataTable` clickable-row keyboard semantics and `SearchInput` clear-affordance accessibility remain broader shared debt.
- Error/offline-state convergence and dense-table overflow semantics remain broader system debt.
- `DocumentActions` Mobile density/touch geometry remains a runtime-review watch.
- `InlineCombobox` / product chooser keyboard-accessibility debt remains outside completed Procurement work.
- Field Activities / Targets are the next roadmap area and may involve GPS/device/routing semantics, so functional isolation is especially important.

## Reusable patterns learned

- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared navigation/action declarations should own placement decisions rather than pages inventing coordinates.
- `TransactionHeader` has cross-module proof in Sales and Finance while domains retain eligibility/workflow truth.
- Canonical `AppAction + resolveActionSet` can preserve page-owned multi-action truth while enforcing device placement limits.
- A single operational next action benefits from a dedicated thin presentation composition (`PrimaryTaskAction`) rather than being forced into the multi-action registry.
- Operational process progress can be standardized without absorbing domain state: caller maps business state to presentation states, shared `ProcessProgress` renders semantics/accessibility.
- Existing semantic `AlertPanel` can unify transient operational success/error feedback while domain copy/result meaning remains caller-owned.
- Form composition can be standardized independently from business field semantics.
- Shared `PageHeader + FormSection + FormGrid + FormActions` has proof across Customer, Sales and Procurement.
- Complete shared Tabs semantics can be reused through thin domain wrappers.
- Shared `ResponsiveCollection` now has proof across Sales Orders, Inventory Stock, Inventory Transfers, Procurement Purchase Invoices, Finance Vaults and HR Employees.
- Shared `MetricGrid + StatCard` can project page-owned summary values without owning calculations or inferring semantics.
- Shared `Pagination` can be extracted from a live collection without absorbing page/query truth, while one contract serves dense tables and responsive cards.
- Canonical Tablet touch sizing can be strengthened at the shared/presentation boundary without reducing intentional Desktop density.
- Initial-empty and filtered-empty require distinct product language when filters/search are active.
- Search copy should describe actual service capability rather than promise unsupported matching.
- A live migrated surface may justify narrow shared-component hardening without opening a speculative framework rewrite.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect representative Field Activities / Targets list surfaces on the exact latest `design-system-v2-development` baseline and bound the smallest presentation-only concern for `DS2-FIELD-001`, explicitly preserving activity/visit/call/target query/service/permission/routing/GPS/device/validation/ownership/workflow truth and avoiding a broad Field framework redesign.

UI Production Engineer should bootstrap from the exact latest Development HEAD and take only that bounded concern. Design QA should independently review the next stable exact PR HEAD. Development Integrator should no-op until that head receives fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and all normal gates pass.
