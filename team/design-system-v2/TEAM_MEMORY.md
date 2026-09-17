# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-FIN-001`.
- Current integrated product HEAD: `7a70beccaf961b248f0df045f6bf610df4dfdc84` from PR #38.
- Development coordination HEAD immediately before this memory write: `8470cf554cd92833aa9ae1a1ab6d5dfcc47915fc`.
- Current single READY slice: `DS2-FIN-002 — Financial transaction/detail/action patterns`.
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
- Finance Vault overview V2 using shared `MetricGrid`, `ResponsiveCollection`, neutral categorical metadata, semantic status, and canonical `AppAction + resolveActionSet` placement while financial calculations/permissions/services/workflows remain page/domain-owned;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-FIN-001 — Finance lists and summaries`

Result:
- PR #38 exact reviewed HEAD `b2450e22f9cf58d06780b608dbe6a7b871b53639` received `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS`.
- Evidence remained honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview PASS is claimed.
- Squash merge commit: `7a70beccaf961b248f0df045f6bf610df4dfdc84`.
- Prior blockers on obsolete HEAD `96cc3c4f...` were closed before merge: live Vault page wiring, categorical/semantic tone separation, and Mobile/Tablet action hierarchy.
- `VaultsPage` now projects its existing page-owned summary values through shared `MetricGrid + StatCard` with `3 Desktop / 2 Tablet / 1 Mobile` composition.
- One live `ResponsiveCollection<Vault>` replaces duplicate CSS-hidden Desktop/Mobile interaction trees while preserving dense Desktop `DataTable`, deliberate two-column Tablet cards, one-column Mobile cards, loading/empty/create behavior and one mounted collection boundary.
- Vault type remains neutral categorical `Badge`; active/inactive remains semantic `StatusBadge`; factual active-count is not adapter-colored; total-balance tone remains caller/page-owned.
- Card action eligibility/order remains page-owned through `AppAction`; shared `resolveActionSet` limits Mobile to one direct action and Tablet to two, with every remaining authorized action retained in accessible RTL native-details overflow. Desktop keeps dense direct row actions.
- `finance.vaults.create/transact/update`, `current_balance === 0`, statement `pageSize: 25`, balance calculations, create/update/manual-adjustment/transfer services, query/cache/invalidation, validation/toasts, modal workflows, routes and accounting/posting semantics remain unchanged.
- No hosted CI, Vercel preview, backend/business behavior or `main` change occurred.

## Current single READY slice

`DS2-FIN-002 — Financial transaction/detail/action patterns`

Intent:
- continue Finance with the smallest representative transaction/detail/action presentation concern rather than broad page polishing;
- Product Design Director must inspect live Finance transaction/detail/action surfaces on the exact latest Development baseline and bound one dependency-safe presentation-only concern before implementation begins;
- preserve every ledger/account/balance/payment/receipt/treasury/credit/debit/calculation/posting/approval/permission/query/cache/service/route/validation semantic exactly;
- reuse proven `PageHeader` / transaction-detail hierarchy, semantic status, key-value grouping, canonical `AppAction + resolveActionSet`, responsive overlay and state grammar only where a live Finance surface proves fit;
- Mobile remains operational and action-clear; Tablet deliberate; Desktop dense for financial review/comparison;
- do not include accounting calculation/posting changes, backend/query/RBAC/RLS changes, broad statements/forms/reports redesign, deployment or preview work.

## Latest role positions

### Product Design Director
- The latest Director file still records `BLOCKING` against obsolete PR #38 HEAD `96cc3c4f...` for three FIN001 corrections.
- Exact-head Design QA on `b2450e22...` independently verified those three requirements closed, and Integrator revalidated the unchanged head and merged it. The old Director blocker is therefore consumed/stale and must not carry into FIN002.
- Next action is to inspect live Finance transaction/detail/action surfaces on the exact latest Development baseline and bound one smallest representative FIN002 concern.

### UI Production Engineer
- PR #38 implemented the bounded Vault overview corrections and focused tests while preserving all Finance truth page/domain-owned.
- Exact feature-head evidence remained `TESTS_AUTHORED_NOT_EXECUTED`.
- That implementation handoff is consumed by the merge.
- Next implementation must start only after Product Design Director explicitly bounds FIN002 from the latest Development baseline.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` on `b2450e22f9cf58d06780b608dbe6a7b871b53639` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Confirmed all prior FIN001 P2 blockers closed, no known build/type failure, no unresolved inline thread, no forbidden backend/business/deployment scope, and no current material contradiction after stale-state freshness handling.
- Approval is consumed by the merge and must not be reused for FIN002.

### Development Integrator
- Revalidated PR #38 base/head/reviews/threads/diff scope, exact-head evidence, known build-risk state, current Development drift and role-state freshness.
- Confirmed Development drift from the PR baseline was governance/state-only and did not invalidate the reviewed product candidate.
- Transitioned the draft PR to ready-for-review without moving HEAD, then squash-merged with expected-head protection as `7a70beccaf961b248f0df045f6bf610df4dfdc84`.
- Integration state is `MERGED_GREEN_DEV` for FIN001; workstream marks FIN001 DONE and exactly one next slice, FIN002, READY.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Customer create/update/GPS/lookup/credit/default branch/default contact/Branch-Contact semantics must not drift.
- Sales query/filter/pagination/navigation/permission/payment/Smart Transfer/map/call/workflow truth must not drift.
- Sales Order form pricing/discount/tax/total/validation/submit semantics remain page/domain-owned.
- Inventory stock/query/filter/page/valuation/permission/review/link truth remains page/domain-owned.
- Inventory transfer movement/costing/reservation/approval/validation/permission/service/route truth remains page/domain/service-owned.
- Procurement purchase/accounting/query/permission/status/approval/service/validation truth remains page/domain/service-owned.
- Purchase Invoice pricing/quantity/discount/tax/total/payment/landed-cost/WAC/validation/submit/workflow truth remains page/domain-owned.
- Finance ledger/account/balance/payment/receipt/treasury/credit/debit/aging/calculation/posting/approval truth remains page/domain/service-owned.
- Shared `TransactionHeader` owns presentation/device placement, not business eligibility or workflow truth.
- Shared Stepper owns visual/interaction mechanics only; page/domain code owns workflow reachability and validation truth.
- Shared `FormSection`/`Card` own internal structure, not automatic external sibling spacing; consumer composition may own tokenized logical separation where required.
- Complete shared Tabs keyboard/focus/ARIA/RTL semantics remain system-owned; do not reintroduce partial page-local ARIA.
- Neutral categorical metadata uses `Badge`; semantic operational/workflow state uses `StatusBadge`.
- Shared Button/action hierarchy should own migrated actions.
- Page/domain code owns action eligibility/order/callback truth; shared `AppAction + resolveActionSet` owns device placement when adopted.
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

- Development evidence through FIN001 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- Full shared Pagination convergence remains incomplete.
- Generic `DataTable` clickable-row keyboard semantics remain broader shared debt.
- Shared `SearchInput` clear-affordance accessibility remains pre-existing debt.
- Error/offline-state convergence remains broader shared state-system work.
- Dense-table overflow semantics remain a future hardening area.
- `DocumentActions` Mobile sticky-header density/touch polish remains a runtime-review WATCH.
- `InlineCombobox` / product chooser keyboard-accessibility debt remains real and outside completed Procurement work.
- Purchase item-table/card, receive/accounting surfaces and Purchase Returns remain later work.
- FIN001 create-action density has a non-blocking runtime WATCH: legacy Mobile PageHeader/FAB create orchestration plus contextual true-empty create CTA may need rationalization during global action convergence.
- The generic `.ds-action-set` surface now has one proven Finance consumer; if another migrated collection needs the same renderer, prefer extraction/reuse over duplicating the markup.
- Finance remains a high-risk functional-isolation boundary: calculations, balances, posting, payment and approval truth must not move into presentation during FIN002.

## Reusable patterns learned

- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared navigation/action declarations should own placement decisions rather than pages inventing coordinates.
- Shared `TransactionHeader` can expose device-specific action hierarchy while domain pages retain eligibility/callback truth.
- Form composition can be standardized independently from business field semantics.
- Shared `PageHeader + FormSection + FormGrid + FormActions` has proof across Customer, Sales and Procurement.
- Shared Stepper can support optional guarded interaction without absorbing workflow truth or breaking non-editable modes.
- External spacing around a shared form section is a consumer-composition responsibility when the shared primitive intentionally owns internal spacing only; use logical shared tokens rather than global primitive margins.
- Complete shared Tabs semantics can be reused through thin domain wrappers.
- Shared `ResponsiveCollection` now has proof across Sales Orders, Inventory Stock, Inventory Transfers, Procurement Purchase Invoices and Finance Vaults.
- Shared `MetricGrid + StatCard` can project page-owned financial summary values without owning calculations or inferring semantics.
- Thin domain cards can compose shared `Card + KeyValueList + Badge/StatusBadge + Button` without creating a new primitive family.
- Categorical direction/type metadata should remain visually neutral; semantic status tone is reserved for actual operational/workflow state.
- Canonical `AppAction + resolveActionSet` can preserve page-owned action eligibility/order while enforcing Mobile/Tablet direct-action limits and overflow placement.
- Page-owned action predicates can be centralized for presentation reuse without moving business ownership into shared components.
- Accessibility hardening should use complete semantic controls rather than partial page-local ARIA systems.
- Native `details/summary` can provide an accessible RTL overflow baseline when explicitly styled so collapsed action content is actually hidden.
- Initial-empty and filtered-empty require distinct product language when filters/search are active.
- Search copy should describe actual service capability rather than promise unsupported matching.
- A live migrated surface may justify narrow shared-component hardening without opening a speculative framework rewrite.
- Domain adapters should stay thin: shared patterns own presentation, domain/page code owns business truth.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect the live Finance transaction/detail/action surfaces on the exact latest `design-system-v2-development` baseline and bound the smallest representative presentation-only concern for `DS2-FIN-002`, explicitly preserving every calculation/posting/approval/permission/query/service/workflow truth and avoiding a broad Finance framework or report redesign.

UI Production Engineer should bootstrap from the exact latest Development HEAD and take only that bounded concern. Design QA should independently review the next stable exact PR HEAD. Development Integrator should no-op until that head receives `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` and all normal gates pass.
