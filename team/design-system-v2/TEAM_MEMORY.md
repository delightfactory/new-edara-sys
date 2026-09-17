# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-HR-001`.
- Current integrated product HEAD: `e9a37c6ade6661bdaf6260f9c93c72dabba60768` from PR #40.
- Development coordination HEAD immediately before this memory write: `039027ae7a7e90f5d40f5b4ca0ae56a5da1cbec8`.
- Current single READY slice: `DS2-HR-002 — HR admin lists/forms`.
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
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-HR-001 — Attendance Check-in operational task controls`

Result:
- PR #40 exact reviewed HEAD `c2a1c0298eaed3b7e1bc38c591d4ca55c91e0f13` received `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- Evidence remained honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview PASS is claimed.
- Squash merge commit: `e9a37c6ade6661bdaf6260f9c93c72dabba60768`.
- Shared `ProcessProgress` accepts caller-owned `completed/current/pending` state, exposes readable non-color state and `aria-current="step"`, and contains no Attendance/GPS/workflow inference.
- Shared `PrimaryTaskAction` is a thin presentation composition over canonical `Button` for one context-dependent operational next action; it is not a second eligibility system or multi-action registry.
- Live `AttendanceCheckin` now consumes `ProcessProgress`, `PrimaryTaskAction` and existing semantic `AlertPanel`, replacing only the superseded local task-control action/progress/feedback mini-system.
- Existing `بدء الدوام` / `إنهاء الدوام`, action IDs, `handleAction(primaryActionType)`, offline/GPS suppression, permission flow, attendance services/RPC/query/cache/tracking/timing/result mapping and `SUCCESS_RESET_MS = 2500` remain page/domain-owned and unchanged.
- No confirmation layer, sticky/fixed task action, `AppAction`, destructive checkout semantic, broad Attendance redesign, backend/business change, hosted CI, Vercel preview or `main` activity occurred.

## Current single READY slice

`DS2-HR-002 — HR admin lists/forms`

Intent:
- continue the North-Star roadmap through HR/People rather than polishing Attendance ad hoc;
- Product Design Director must inspect representative HR administration list/form surfaces on the exact latest Development baseline and bound one smallest dependency-safe presentation-only concern;
- prefer the established V2 collection/form/action/status grammar before adding HR-local patterns;
- preserve employee, attendance, leave, payroll, advances/delegations, permissions, query/cache, service, validation, route and workflow truth exactly;
- Mobile/Tablet/Desktop must be deliberately composed and capability-equivalent for the selected surface;
- no backend/business/workflow/query-cache/permission change, broad HR redesign, deployment, preview or `main` work.

## Latest role positions

### Product Design Director
- Independently accepted HR001 exact PR HEAD `c2a1c0298eaed3b7e1bc38c591d4ca55c91e0f13` with no Design-System blocker.
- Confirmed shared task controls remain presentation-only and the live Attendance boundary preserves business/device truth.
- HR001 acceptance is consumed by the merge; next responsibility is to bound HR002 from the exact latest Development baseline.

### UI Production Engineer
- Feature-head implementation completed the live HR001 wiring and focused source-contract protection with `TESTS_AUTHORED_NOT_EXECUTED` evidence.
- That handoff is consumed by the merge.
- Next implementation must wait for the Director's explicit HR002 boundary and start from the latest Development HEAD.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` on `c2a1c0298eaed3b7e1bc38c591d4ca55c91e0f13` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Confirmed 7-file UI/Test/owned-state scope, preserved Attendance/GPS/service/query/tracking/workflow truth, no known build/type failure and no unresolved review thread.
- Approval is consumed by the merge and must not be reused for HR002.

### Development Integrator
- Revalidated PR #40 base/head/reviews/threads/diff, Development drift and role-state freshness.
- Confirmed Development drift from the PR base was role-state coordination only and did not invalidate the reviewed product candidate.
- Transitioned the draft PR to ready-for-review without moving its head, then squash-merged with expected-head protection as `e9a37c6ade6661bdaf6260f9c93c72dabba60768`.
- Integration state is `MERGED_GREEN_DEV` for HR001; workstream marks HR001 DONE and exactly one next slice, HR002, READY.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Customer, Sales, Inventory, Procurement, Finance and HR business/query/permission/workflow truths remain page/domain/service-owned.
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
- Shared `DataTable` paginator semantics include logical Arabic previous/next, labeled navigation, accessible names, current-page semantics and width-safe controls; this does not imply full global Pagination convergence.
- Mobile operational actions remain clear and touch-ready; Tablet must be deliberate; Desktop must remain efficient for management/review/data entry.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Initial-empty and filtered-empty are distinct states when filtering/search exists.
- Search affordance copy must match actual service/query truth.
- Hidden duplicate device interaction trees should be avoided where device-aware composition exists.
- Each agent writes only its own specialist state; all agents read every specialist state.
- Durable decisions belong in the Decision Log; routine progress does not.
- No hosted CI, Vercel preview or `main` activity from scheduled agents.

## Known evidence / risks

- Development evidence through HR001 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- `ProcessProgress` is proven here for a short two-step Attendance operation; high-step-count responsive behavior remains future evidence, not HR001 scope.
- HR administration surfaces remain largely unmigrated and are the next work area; their permissions/payroll/leave semantics make functional isolation important.
- Full shared Pagination convergence remains incomplete.
- Generic `DataTable` clickable-row keyboard semantics and `SearchInput` clear-affordance accessibility remain broader shared debt.
- Error/offline-state convergence and dense-table overflow semantics remain broader system debt.
- `DocumentActions` Mobile density/touch geometry remains a runtime-review watch.
- `InlineCombobox` / product chooser keyboard-accessibility debt remains outside completed Procurement work.

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
- Shared `ResponsiveCollection` has proof across Sales Orders, Inventory Stock, Inventory Transfers, Procurement Purchase Invoices and Finance Vaults.
- Shared `MetricGrid + StatCard` can project page-owned financial summary values without owning calculations or inferring semantics.
- Initial-empty and filtered-empty require distinct product language when filters/search are active.
- Search copy should describe actual service capability rather than promise unsupported matching.
- A live migrated surface may justify narrow shared-component hardening without opening a speculative framework rewrite.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect representative HR administration list/form surfaces on the exact latest `design-system-v2-development` baseline and bound the smallest presentation-only concern for `DS2-HR-002`, explicitly preserving employee/attendance/leave/payroll/permission/query/service/workflow truth and avoiding a broad HR framework redesign.

UI Production Engineer should bootstrap from the exact latest Development HEAD and take only that bounded concern. Design QA should independently review the next stable exact PR HEAD. Development Integrator should no-op until that head receives fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and all normal gates pass.
