# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-FIELD-001`.
- Current integrated product HEAD: `cac61006d5c6ac402a509c2f15fb09ce51bafd50` from PR #42.
- Development coordination HEAD immediately before this memory write: `66ccd3842f0b925834679e9df3b6d49817a71f83`.
- Current single READY slice: `DS2-FIELD-002 — Field create/detail flows`.
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
- HR Employees administration list using one live `ResponsiveCollection<HREmployee>`, shared semantic status/action/card grammar and shared presentation-only `Pagination` with canonical Tablet touch targets;
- Field Activities list using one live `ResponsiveCollection<ActivityRow>`, semantic outcome state, neutral category metadata, shared Pagination/action placement and deliberate device-specific persistent-create ownership;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-FIELD-001 — Activities/visit/call/target lists` — representative concern: Activities list

Result:
- PR #42 exact reviewed HEAD `6b7569f3b98f7d8cd9a7588b3ae624e606f82f6b` received `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- Evidence remains honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview PASS is claimed.
- Squash merge commit: `cac61006d5c6ac402a509c2f15fb09ce51bafd50`.
- Live `ActivitiesPage` now uses one `ResponsiveCollection<ActivityRow>` with dense Desktop `DataTable`, deliberate Tablet two-column cards and Mobile one-column operational cards rather than duplicate hidden device interaction trees.
- `ActivityCard` is a thin Field projection over shared `Card`, `KeyValueList`, neutral `Badge`, semantic `StatusBadge`, `Button` and canonical `AppAction/resolveActionSet` placement.
- Tablet preserves optional `start_time` through the same page-owned formatter as Desktop; Mobile intentionally keeps its prior information density.
- Activity outcome is semantic workflow/result state; category is neutral categorical metadata and appears once; false GPS remains neutral read-only `—` rather than an invented negative workflow state.
- Mobile persistent creation remains owned by the existing shell `new-activity` FAB; Tablet/Desktop retain the permission-gated PageHeader create action to `/activities/new`.
- Initial-empty and filtered-empty remain distinct. The pre-existing Mobile empty-state CTA + shell FAB coexistence is accepted only as a later non-blocking action-convergence/runtime watch.
- Activity query/search/filter/page inputs and timing, team/create/delete permissions, delete mutation/backend authority, routes/customer deep-link, GPS/device/workflow/service/query-cache/validation truth remain unchanged and page/domain-owned.

## Current single READY slice

`DS2-FIELD-002 — Field create/detail flows`

Intent:
- continue the North-Star Field roadmap from the proven list grammar into one smallest representative create/detail concern, not reopen FIELD001 polishing;
- Product Design Director must inspect representative Field create/detail surfaces on the exact latest Development baseline and bound one dependency-safe presentation-only concern with explicit acceptance criteria;
- prefer established V2 form/detail/action/status/device patterns before adding Field-local presentation grammar;
- preserve activity/visit/call/target query, service, permission, routing, GPS/device, validation, ownership and workflow truth exactly;
- Mobile remains the primary operational Field surface; Tablet must be deliberately composed; Desktop must preserve efficient management/data-entry density and capability parity;
- no backend/business/workflow/query-cache/permission/validation-semantic change, broad Field redesign, deployment, preview or `main` work.

## Latest role positions

### Product Design Director
- Independently accepted FIELD001 / PR #42 exact HEAD `6b7569f3b98f7d8cd9a7588b3ae624e606f82f6b` with `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Explicitly closed the prior Mobile PageHeader/FAB P2 contradiction after verifying shell FAB ownership on Mobile and PageHeader create retention on Tablet/Desktop.
- Accepted the Activities collection/status/device grammar; the pre-existing empty-state CTA + FAB coexistence remains a non-blocking later WATCH.
- FIELD001 acceptance is consumed by the merge; next responsibility is to bound FIELD002 from the exact latest Development baseline.

### UI Production Engineer
- Completed FIELD001 list migration plus bounded QA/Director corrections: Tablet start-time parity, single category representation and Mobile persistent-create ownership.
- Preserved all Field business/query/permission/GPS/workflow truth and added focused authored source/test contracts.
- Evidence remained `TESTS_AUTHORED_NOT_EXECUTED`; the completed FIELD001 handoff is consumed by the merge.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` on `6b7569f3b98f7d8cd9a7588b3ae624e606f82f6b` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Confirmed the prior Tablet/category and Mobile create-ownership P2 findings were closed, the 7-file slice remained functionally isolated, no known build/type failure existed and no review thread remained.
- Approval is consumed by the merge and must not be reused for FIELD002.

### Development Integrator
- Revalidated PR #42 base/head/reviews/threads/diff, exact-head Director/QA freshness and Development drift.
- Confirmed Development drift from the feature baseline was governance-only and did not overlap product/shared implementation.
- Transitioned the draft PR to ready-for-review without moving its head, then squash-merged with expected-head protection as `cac61006d5c6ac402a509c2f15fb09ce51bafd50`.
- Integration state is `MERGED_GREEN_DEV` for FIELD001; workstream marks FIELD001 DONE and exactly one next slice, FIELD002, READY.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Customer, Sales, Inventory, Procurement, Finance, HR and Field business/query/permission/workflow truths remain page/domain/service-owned.
- Field activity query/search/filter/paging, delete/backend authority, routes/customer deep-link, GPS/device semantics and workflow/validation truth must not leak into shared presentation.
- Persistent primary-action ownership must be deliberate by device: on the Activities list Mobile uses the shell `new-activity` FAB while Tablet/Desktop use the PageHeader create action; do not reintroduce competing persistent primary create controls.
- Neutral categorical metadata uses `Badge`; semantic operational/workflow/result state uses `StatusBadge`.
- Page/domain code owns action eligibility/order/callback truth; shared `AppAction + resolveActionSet` owns device placement when adopted.
- Shared `Pagination` owns presentation, accessible paging controls and page-change requests only; caller/domain code owns page/query truth.
- Shared Pagination's established five-page window, logical Arabic previous/next, accessible names, disabled boundaries and `aria-current="page"` remain stable unless a declared component-depth slice changes the contract.
- Shared `TransactionHeader` owns presentation/device placement, not business eligibility or workflow truth.
- Shared Stepper owns visual/interaction mechanics only; page/domain code owns workflow reachability and validation truth.
- Shared `ProcessProgress` owns progress presentation/accessibility only; caller/domain code owns process state truth and transition meaning.
- Shared `PrimaryTaskAction` owns presentation over `Button` only; caller/domain code owns eligibility, label/action meaning and callback truth.
- A single context-dependent operational next action should not be forced into `AppAction/resolveActionSet`; that registry remains for multi-action placement.
- Dynamic success/error feedback should use shared semantic live-region contracts such as `AlertPanel` without moving result/business semantics into the shared layer.
- Shared `FormSection`/`Card` own internal structure, not automatic external sibling spacing; consumer composition may own tokenized logical separation where required.
- Complete shared Tabs keyboard/focus/ARIA/RTL semantics remain system-owned; do not reintroduce partial page-local ARIA.
- Canonical touch targets remain first-class through Tablet for touch-active controls; Desktop may intentionally preserve denser pointer-oriented controls.
- The Employees filter/search row and Activities filter/search row are local page composition, not reusable system FilterBar contracts.
- Mobile operational actions remain clear and touch-ready; Tablet must be deliberate; Desktop must remain efficient for management/review/data entry.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Initial-empty and filtered-empty are distinct states when filtering/search exists.
- Search affordance copy must match actual service/query truth.
- Hidden duplicate device interaction trees should be avoided where device-aware composition exists.
- Each agent writes only its own specialist state; all agents read every specialist state.
- Durable decisions belong in the Decision Log; routine progress does not.
- No hosted CI, Vercel preview or `main` activity from scheduled agents.

## Known evidence / risks

- Development evidence through FIELD001 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- The pre-existing Mobile Activities empty-state CTA + shell FAB coexistence remains a later action-convergence/runtime-density watch; it is not a FIELD001 regression.
- Field create/detail work may involve GPS/device/routing/validation semantics, so functional isolation is especially important in FIELD002.
- Full shared Pagination convergence remains incomplete even though it is proven in DataTable, Employees responsive cards and Activities.
- The Employees `fieldEmpCount` metric remains intentionally current-page scoped; any semantic change requires separate product/query work.
- Local Employees/Activities filter composition must not be copied as the system filter answer; FilterBar/search/filter convergence remains component-depth debt.
- Generic `DataTable` clickable-row keyboard semantics and `SearchInput` clear-affordance accessibility remain broader shared debt.
- Error/offline-state convergence and dense-table overflow semantics remain broader system debt.
- `DocumentActions` Mobile density/touch geometry remains a runtime-review watch.
- `InlineCombobox` / product chooser keyboard-accessibility debt remains outside completed Procurement work.

## Reusable patterns learned

- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared navigation/action declarations should own placement decisions rather than pages inventing coordinates.
- A page-level persistent primary action may intentionally have different owners by device when ownership is singular and canonical: shell FAB on Mobile, PageHeader on Tablet/Desktop for Activities.
- `TransactionHeader` has cross-module proof in Sales and Finance while domains retain eligibility/workflow truth.
- Canonical `AppAction + resolveActionSet` can preserve page-owned multi-action truth while enforcing device placement limits; FIELD001 extends that proof to Field record actions.
- A single operational next action benefits from a dedicated thin presentation composition (`PrimaryTaskAction`) rather than being forced into the multi-action registry.
- Operational process progress can be standardized without absorbing domain state: caller maps business state to presentation states, shared `ProcessProgress` renders semantics/accessibility.
- Existing semantic `AlertPanel` can unify transient operational success/error feedback while domain copy/result meaning remains caller-owned.
- Form composition can be standardized independently from business field semantics.
- Shared `PageHeader + FormSection + FormGrid + FormActions` has proof across Customer, Sales and Procurement.
- Complete shared Tabs semantics can be reused through thin domain wrappers.
- Shared `ResponsiveCollection` now has proof across Sales Orders, Inventory Stock, Inventory Transfers, Procurement Purchase Invoices, Finance Vaults, HR Employees and Field Activities.
- Responsive composition must preserve meaningful Tablet capability parity even when the representation changes; FIELD001 proved this with optional start time.
- Shared `MetricGrid + StatCard` can project page-owned summary values without owning calculations or inferring semantics.
- Shared `Pagination` can serve dense tables and responsive cards without absorbing page/query truth.
- Canonical Tablet touch sizing can be strengthened at the shared/presentation boundary without reducing intentional Desktop density.
- Initial-empty and filtered-empty require distinct product language when filters/search are active.
- Search copy should describe actual service capability rather than promise unsupported matching.
- A live migrated surface may justify narrow shared-component hardening without opening a speculative framework rewrite.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect representative Field create/detail surfaces on the exact latest `design-system-v2-development` baseline and bound the smallest presentation-only concern for `DS2-FIELD-002`, explicitly preserving activity/visit/call/target query/service/permission/routing/GPS/device/validation/ownership/workflow truth and avoiding a broad Field framework redesign.

UI Production Engineer should bootstrap from the exact latest Development HEAD and take only that bounded concern. Design QA should independently review the next stable exact PR HEAD. Development Integrator should no-op until that head receives fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and all normal gates pass.
