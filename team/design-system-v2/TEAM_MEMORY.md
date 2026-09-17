# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-PROC-002`.
- Current integrated product HEAD: `5b10b9fb578c91798d28526d8de407f63ffcc417` from PR #37.
- Current single READY slice: `DS2-FIN-001 — Finance lists and summaries`.
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
- Customers List and Customer form/detail migrations;
- complete shared Tabs semantics reused by Customer detail;
- Sales Orders list V2;
- Sales Order form V2 foundation and guarded shared Stepper contract;
- Sales transaction-detail header V2 using canonical `AppAction + resolveActionSet` placement;
- Inventory stock and transfer collections V2 using one `ResponsiveCollection` boundary per live surface;
- Procurement Purchase Invoice list V2 with deliberate device composition, initial-vs-filtered empty semantics and bounded shared DataTable paginator hardening;
- Procurement Purchase Invoice form-shell V2 using shared `Stepper`, `FormSection`, `FormGrid`, `FormActions`, `Button` and semantic `StatusBadge` while purchase/accounting/workflow truth stays page/domain-owned;
- consumer-owned logical spacing proof: local composition may add tokenized external sibling rhythm without changing globally marginless shared `FormSection`/`Card` contracts;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-PROC-002 — Purchase Invoice form decomposition`

Result:
- PR #37 exact reviewed HEAD `4fa613edad180de140b9c7a1c41ceeb9b7e55ee3` received `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS`.
- Evidence remained honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview PASS is claimed.
- Squash merge commit: `5b10b9fb578c91798d28526d8de407f63ffcc417`.
- Earlier completeness and inter-section-spacing blockers were closed before final review.
- New/editable-draft wizard composition now reuses shared Stepper through a thin Purchase adapter while page-owned validation/reachability remains unchanged and review/final is not newly direct-reachable.
- **بيانات الفاتورة** uses shared `FormSection + FormGrid columns={3}` for the intended `3 Desktop / 2 Tablet / 1 Mobile` density.
- Wizard actions use shared `FormActions + Button` with unchanged cancel/back/next/save callbacks, unchanged save-disabled truth, touch targets and RTL-native cues.
- Workflow status now uses the shared semantic Purchase vocabulary instead of a page-local raw-color badge.
- Purchase-scoped logical `margin-block-end: var(--space-4)` restores major-section separation without altering shared primitive spacing globally.
- Supplier/product/warehouse identity, pricing/quantity/discount/tax/total/landed-cost/WAC/accounting/payment, receive/bill/cancel transitions, permissions, services/query/cache, routes, validation semantics, mobile item flow, `ResponsiveModal` and `DocumentActions` remain unchanged.
- No hosted CI, Vercel preview, backend/business behavior or `main` change occurred.

## Current single READY slice

`DS2-FIN-001 — Finance lists and summaries`

Intent:
- continue the module roadmap into Finance with the smallest representative list/summary presentation concern;
- Product Design Director must inspect live Finance surfaces on the exact latest Development baseline and bound one dependency-safe presentation-only concern before implementation expands;
- preserve ledger/account/balance/payment/receipt/treasury/credit/debit/aging/calculation/posting/approval/permission/query/cache/service/route truth exactly;
- reuse proven shared collection/card/table/status/summary/action grammar where live Finance proves fit;
- strengthen a shared Finance-summary or state pattern only when a real migrated screen proves the recurring need and the change remains presentation-only;
- Mobile remains operational and touch-safe; Tablet deliberate; Desktop dense for financial review/comparison;
- do not include accounting calculation/posting changes, backend/query/RBAC/RLS changes, speculative global report/chart work, deployment or preview work.

## Latest role positions

### Product Design Director
- The prior PROC002 BLOCKING state referred to superseded HEAD `751d5427...` and requested the local token-based spacing correction now integrated.
- That blocker is consumed by exact-head QA plus successful integration and must not carry into Finance.
- Next action is to inspect the live Finance surfaces from the exact latest Development baseline and bound one smallest representative concern for FIN001.

### UI Production Engineer
- Implemented the PROC002 shell and the final bounded local spacing correction on PR #37.
- Exact feature-head implementation state recorded no remaining UI blocker; evidence was `TESTS_AUTHORED_NOT_EXECUTED`.
- That implementation handoff is consumed by the merge.
- Next implementation must start only after Product Design Director bounds FIN001 from the latest Development baseline.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` on `4fa613edad180de140b9c7a1c41ceeb9b7e55ee3` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Confirmed the prior P2 spacing regression closed, no known build/type failure, no unresolved inline thread, no current material peer contradiction and no forbidden backend/business/deployment scope.
- Approval is consumed by the merge and must not be reused for Finance.

### Development Integrator
- Revalidated PR #37 base/head/reviews/threads/diff scope, exact-head evidence, known build-risk state and role-state freshness.
- Confirmed Development drift from the PR baseline was governance-only and did not invalidate the reviewed product candidate.
- Transitioned the draft PR to ready-for-review without moving HEAD, then squash-merged with expected-head protection as `5b10b9fb578c91798d28526d8de407f63ffcc417`.
- Integration state is `MERGED_GREEN_DEV` for PROC002; workstream marks PROC002 DONE and exactly one next slice, FIN001, READY.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Customer create/update/GPS/lookup/credit/default branch/default contact/Branch-Contact semantics must not drift.
- Sales query/filter/pagination/navigation/permission/payment/Smart Transfer/map/call/workflow truth must not drift.
- Sales Order form pricing/discount/tax/total/validation/submit semantics remain page/domain-owned.
- Inventory stock/query/filter/page/valuation/permission/review/link truth remains page/domain-owned.
- Inventory transfer movement/costing/reservation/approval/validation/permission/service/route truth remains page/domain/service-owned.
- Procurement purchase/accounting/query/permission/status/approval/service/validation truth remains page/domain/service-owned.
- Purchase Invoice pricing/quantity/discount/tax/total/payment/landed-cost/WAC/validation/submit/workflow truth remains page/domain-owned.
- Finance ledger/account/balance/payment/receipt/treasury/credit/debit/aging/calculation/posting/approval truth must remain page/domain/service-owned during FIN001.
- Shared `TransactionHeader` owns presentation/device placement, not business eligibility or workflow truth.
- Shared Stepper owns visual/interaction mechanics only; page/domain code owns workflow reachability and validation truth.
- Shared `FormSection`/`Card` own internal structure, not automatic external sibling spacing; consumer composition may own tokenized logical separation where required.
- Complete shared Tabs keyboard/focus/ARIA/RTL semantics remain system-owned; do not reintroduce partial page-local ARIA.
- Neutral categorical metadata uses `Badge`; semantic operational/workflow state uses `StatusBadge`.
- Shared Button/action hierarchy should own migrated actions.
- Shared `DataTable` paginator semantics include logical Arabic previous/next, labeled navigation, accessible names, current-page semantics and width-safe previous/next controls; this does not imply full global Pagination convergence.
- Mobile operational actions remain clear and touch-ready.
- Tablet must not collapse into oversized Mobile or cramped Desktop.
- Desktop must remain efficient for dense management/review/data-entry work.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Initial-empty and filtered-empty are distinct states when filtering/search exists.
- Search affordance copy must match actual service/query truth; UI work must not silently expand backend search semantics.
- Hidden duplicate device interaction trees should be avoided where device-aware composition exists.
- Each agent writes only its own specialist state; all agents read every specialist state.
- Durable decisions belong in the Decision Log; routine progress does not.
- No hosted CI, Vercel preview or `main` activity from scheduled agents.

## Known evidence / risks

- Development evidence through PROC002 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- Full shared Pagination convergence remains incomplete.
- Generic `DataTable` clickable-row keyboard semantics remain broader shared debt.
- Shared `SearchInput` clear-affordance accessibility remains pre-existing debt.
- Error/offline-state convergence remains broader shared state-system work.
- Dense-table overflow semantics remain a future hardening area.
- `DocumentActions` Mobile sticky-header density/touch polish remains a runtime-review WATCH.
- `InlineCombobox` / product chooser keyboard-accessibility debt remains real and outside completed PROC002.
- Purchase item-table/card, receive/accounting surfaces and Purchase Returns remain later work.
- Finance is a high-risk functional-isolation boundary: calculations, balances, posting, payment and approval truth must not move into presentation.

## Reusable patterns learned

- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared navigation/action declarations should own placement decisions rather than pages inventing coordinates.
- Shared `TransactionHeader` can expose device-specific action hierarchy while domain pages retain eligibility/callback truth.
- Form composition can be standardized independently from business field semantics.
- Shared `PageHeader + FormSection + FormGrid + FormActions` has proof across Customer, Sales and Procurement.
- Shared Stepper can support optional guarded interaction without absorbing workflow truth or breaking non-editable modes.
- External spacing around a shared form section is a consumer-composition responsibility when the shared primitive intentionally owns internal spacing only; use logical shared tokens rather than global primitive margins.
- Complete shared Tabs semantics can be reused through thin domain wrappers.
- Shared `ResponsiveCollection` has proof across Sales Orders, Inventory Stock, Inventory Transfers and Procurement Purchase Invoices.
- Thin domain cards can compose shared `Card + KeyValueList + Badge/StatusBadge + Button` without creating a new primitive family.
- Categorical direction/type metadata should remain visually neutral; semantic status tone is reserved for actual operational/workflow state.
- Page-owned action predicates can be centralized for presentation reuse without moving business ownership into shared components.
- Accessibility hardening should use complete semantic controls rather than partial page-local ARIA systems.
- Initial-empty and filtered-empty require distinct product language when filters/search are active.
- Search copy should describe actual service capability rather than promise unsupported matching.
- A live migrated surface may justify narrow shared-component hardening without opening a speculative framework rewrite.
- Domain adapters should stay thin: shared patterns own presentation, domain/page code owns business truth.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect the live Finance lists/summaries on the exact latest `design-system-v2-development` baseline and bound the smallest representative presentation-only concern for `DS2-FIN-001`, explicitly preserving every accounting/balance/payment/posting/approval/permission/query/service truth and avoiding speculative global Finance/report redesign.

UI Production Engineer should bootstrap from the exact latest Development HEAD and take only that bounded concern. Design QA should independently review the next stable exact PR HEAD. Development Integrator should no-op until that head receives `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` and all normal gates pass.
