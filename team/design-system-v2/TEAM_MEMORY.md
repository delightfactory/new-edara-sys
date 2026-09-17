# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-FIELD-002`.
- Current integrated product HEAD: `2492fa475e7bc5beb9148124f31a4b4837057c19` from PR #43.
- Development coordination HEAD immediately before this memory write: `019441d0f2fcfc243b7881ed6919f010132298bd`.
- Current single READY slice: `DS2-WORK-001 — Reconcile Work UI island with V2`.
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
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-FIELD-002 — Activity create/edit form composition foundation`

Result:
- PR #43 exact reviewed HEAD `a31addc60e5b0eaf8ee89a0fea11bded2a6e4c4a` received `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- Product Design independently accepted the same exact HEAD with `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Evidence remains honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview PASS is claimed.
- Squash merge commit: `2492fa475e7bc5beb9148124f31a4b4837057c19`.
- The live normal `ActivityForm` create/edit path now uses shared `FormSection + FormGrid + FormActions + Button` instead of its page-local outer form/timing/action mini-system.
- Existing task order remains activity data -> outcome/link/call conditional content -> timing/notes; conditional business meaning was not reordered.
- Date/start/end composition resolves to one column on Mobile, max two on Tablet and three on Desktop inside the retained 640px form bound.
- Cancel/submit remain non-sticky and touch-safe. Callbacks, labels, save loading/disabled truth and `gpsBlocking` submit suppression remain page-owned.
- Composition-touched native controls have explicit Arabic label associations while native required/disabled semantics remain unchanged.
- Visit-plan routing, GPS acquisition/verification/distance, target/history queries, order/collection linking, call-detail behavior, validation, payload construction, create/update/save-call-detail mutations, navigation and all backend/business/workflow truth remain unchanged.

## Current single READY slice

`DS2-WORK-001 — Reconcile Work UI island with V2`

Intent:
- continue the North-Star module roadmap into Work Management rather than reopen completed Field slices for ad-hoc polishing;
- Product Design Director must inspect representative Work Management surfaces on the exact latest Development baseline and bound one smallest dependency-safe presentation-only concern with explicit acceptance criteria;
- prefer the established V2 shell, collection, form, action, status, feedback and device grammar before inventing Work-local presentation patterns;
- preserve Work business/query/service/permission/ownership/workflow/validation truth exactly;
- Mobile remains operational-first, Tablet deliberate/touch-first, Desktop efficient for planning, review and management;
- no backend/business/workflow/query-cache/permission/validation-semantic change, deployment, preview or `main` work.

Remaining Field create/detail convergence is explicit backlog debt and must be reactivated only through a separately bounded dependency-safe slice; FIELD002 does not declare the whole Field module converged.

## Latest role positions

### Product Design Director
- Independently accepted PR #43 exact HEAD `a31addc60e5b0eaf8ee89a0fea11bded2a6e4c4a` with `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Confirmed the shared ActivityForm composition is coherent across Mobile/Tablet/Desktop and preserves Field functional truth.
- The excluded legacy call/link sub-controls remain a non-blocking convergence WATCH and must not be copied as canonical Field form grammar.
- FIELD002 acceptance is consumed by the merge; next responsibility is to bound `DS2-WORK-001` from the exact latest Development baseline.

### UI Production Engineer
- Completed the bounded FIELD002 ActivityForm composition using established V2 form patterns and authored focused regression/source contracts.
- Preserved visit-plan/GPS/query/validation/payload/mutation/link/call-detail behavior; evidence remained `TESTS_AUTHORED_NOT_EXECUTED`.
- The FIELD002 implementation handoff is consumed by the merge. The Development-side role-state file may be lifecycle-stale until the next implementation run and must not be treated as an active competing slice.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` on `a31addc60e5b0eaf8ee89a0fea11bded2a6e4c4a` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Confirmed six-file UI/Test/Governance-only scope, no known build/type failure, no review threads and no functional-isolation breach.
- Approval is consumed by the merge and must not be reused for WORK001.

### Development Integrator
- Revalidated PR #43 base/head/reviews/threads/diff, fresh same-head Product Design + QA gates, Development drift and mergeability.
- Confirmed drift from the feature baseline was role-state governance only and did not overlap product/shared implementation.
- Transitioned the draft PR to ready-for-review without moving its head, then squash-merged with expected-head protection as `2492fa475e7bc5beb9148124f31a4b4837057c19`.
- Integration state is `MERGED_GREEN_DEV` for FIELD002; workstream marks FIELD002 DONE and exactly one next slice, WORK001, READY.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Customer, Sales, Inventory, Procurement, Finance, HR, Field and Work business/query/permission/workflow truths remain page/domain/service-owned.
- Field activity query/search/filter/paging, routes, GPS/device semantics, validation, payloads, mutations and workflow truth must not leak into shared presentation.
- The ActivityForm shared form composition is presentation-only: page/domain code still owns required/disabled truth, GPS blocking, selected type/category, customer requirement, outcome/reason visibility, dates/times, payload construction, mutations and navigation.
- FIELD002 uses non-sticky Mobile actions and retains the bounded 640px form width; do not change those as an incidental follow-up.
- The excluded legacy call/link sub-controls are debt, not canonical V2 patterns.
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
- Local Employees/Activities filter rows and legacy Field call/link controls are not reusable system contracts.
- Each agent writes only its own specialist state; all agents read every specialist state.
- Durable decisions belong in the Decision Log; routine progress does not.
- No hosted CI, Vercel preview or `main` activity from scheduled agents.

## Known evidence / risks

- Development evidence through FIELD002 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- The excluded legacy ActivityForm call/link sub-controls remain a presentation/accessibility convergence WATCH.
- Remaining Field create/detail surfaces still need later bounded convergence before the module can be considered fully aligned.
- The pre-existing Mobile Activities empty-state CTA + shell FAB coexistence remains a later action-convergence/runtime-density watch.
- Full shared Pagination convergence, FilterBar/search/filter convergence, generic DataTable row keyboard semantics, SearchInput clear accessibility, error/offline-state convergence and dense-table overflow semantics remain broader shared debt.
- `DocumentActions` Mobile density/touch geometry, Procurement `InlineCombobox` keyboard accessibility and similar component-depth debt remain outside completed slices.
- Work Management may contain its own local UI island; Product Design must bound the first Work slice before implementation rather than perform a broad rewrite.

## Reusable patterns learned

- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared navigation/action declarations should own placement decisions rather than pages inventing coordinates.
- `TransactionHeader` has cross-module proof in Sales and Finance while domains retain eligibility/workflow truth.
- `AppAction + resolveActionSet` can preserve page-owned multi-action truth while enforcing device placement limits; a single context-dependent operational next action may instead use a thin `PrimaryTaskAction` composition.
- Operational process progress and feedback can be standardized without absorbing domain truth through `ProcessProgress` and `AlertPanel`.
- Shared form composition can be standardized independently from business field semantics. `PageHeader + FormSection + FormGrid + FormActions` now has proof across Customer, Sales, Procurement and Field.
- `FormGrid` can express deliberate one-column Mobile, capped-two-column Tablet and denser Desktop grouping without changing page-owned field semantics.
- Consumer-owned tokenized section spacing can preserve hierarchy without adding external margins to shared sections.
- Shared `ResponsiveCollection` has proof across Sales Orders, Inventory Stock, Inventory Transfers, Procurement Purchase Invoices, Finance Vaults, HR Employees and Field Activities.
- Responsive composition must preserve meaningful Tablet capability parity even when representation changes.
- Shared `MetricGrid + StatCard` and `Pagination` can project page-owned values/query state without absorbing calculations or query truth.
- A live migrated surface may justify narrow shared-component hardening, but excluded legacy sub-controls should be left as explicit debt rather than accidentally blessed as the new system pattern.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect representative Work Management surfaces on the exact latest `design-system-v2-development` baseline and bound the smallest presentation-only concern for `DS2-WORK-001`, explicitly preserving Work query/service/permission/ownership/workflow/validation truth and the full Reports/Admin/Global roadmap.

UI Production Engineer should bootstrap only from the exact latest Development HEAD after that boundary is recorded and implement one coherent concern. Design QA should independently review the exact stable PR HEAD. Development Integrator should no-op until that head receives fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and all normal gates pass.
