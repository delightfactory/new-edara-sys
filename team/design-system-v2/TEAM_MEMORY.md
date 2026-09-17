# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-FIN-002`.
- Current integrated product HEAD: `1a9509d598b9b462397838db7adc261c4746c52f` from PR #39.
- Development coordination HEAD immediately before this memory write: `0914c1817575bd0f12603c16172747d90f441e0a`.
- Current single READY slice: `DS2-HR-001 — Mobile operational tasks`.
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
- consumer-owned logical spacing proof around globally marginless shared form/card contracts;
- Finance Vault overview V2 using shared `MetricGrid`, `ResponsiveCollection`, neutral categorical metadata, semantic status, and canonical `AppAction + resolveActionSet` placement;
- Finance Payment Receipt transaction-detail header/action foundation using the same shared `TransactionHeader + StatusBadge + AppAction/resolveActionSet` grammar already proven in Sales;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-FIN-002 — Payment Receipt transaction-detail header/action foundation`

Result:
- PR #39 exact reviewed HEAD `0389bb0748a4eb84d40b57707b4b1da47000b369` received `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS`.
- Evidence remained honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview PASS is claimed.
- Squash merge commit: `1a9509d598b9b462397838db7adc261c4746c52f`.
- Live `PaymentReceiptDetail` now uses a thin Finance adapter over shared `TransactionHeader`; receipt number, customer/date context and back route remain page-owned.
- Finance-owned `pending / confirmed / rejected` mapping now renders through shared text-backed `StatusBadge` warning/success/danger semantics.
- Existing `isSelfCashCustody`, `isAdmin`, `canConfirm`, `finance.payments.confirm`, confirm callback and reject callback remain page-owned. `AppAction[]` only expresses authorized review actions to the shared placement layer.
- Shared action placement preserves Mobile max-one direct review action, Tablet max-two and Desktop direct actions, with any remaining authorized action retained in accessible RTL native-details overflow.
- `DocumentActions kind="payment-receipt"` remains separate output tooling rather than workflow eligibility.
- Shared TransactionHeader overflow presentation is hardened so closed native `<details>` cannot visually leak action content.
- Payment Receipt query/service/custody/vault/destination/validation/invalidation/modal/accounting/workflow truth remains unchanged.
- No hosted CI, Vercel preview, backend/business behavior or `main` change occurred.

## Current single READY slice

`DS2-HR-001 — Mobile operational tasks`

Intent:
- continue the North-Star roadmap into HR/People rather than collapsing into ad-hoc Finance polishing;
- Product Design Director must inspect live HR/People Mobile operational surfaces on the exact latest Development baseline and bound one smallest representative presentation-only concern before implementation begins;
- preserve every attendance/time, leave, payroll, employee-management, permission, query/cache, service, validation, route and device-capability truth exactly;
- prefer a recurring real operational task that proves shared Mobile action/form/state grammar and can later generalize across HR/field work;
- Mobile remains the primary task surface; Tablet is deliberate; Desktop remains capability-equivalent where the selected surface exists;
- do not include backend/business/workflow changes, broad HR redesign, deployment, preview or `main` work.

## Latest role positions

### Product Design Director
- Its current file bounded FIN002 from an earlier Development lifecycle point and recorded blocker `NONE`.
- That FIN002 boundary has now been implemented, exact-head reviewed and merged; the lifecycle portion of that state is consumed/stale.
- Next action is to inspect live HR/People operational surfaces on the exact latest Development baseline and bound the smallest dependency-safe HR001 presentation concern.

### UI Production Engineer
- The feature-head state for PR #39 implemented the bounded Payment Receipt header/action foundation and focused tests with `TESTS_AUTHORED_NOT_EXECUTED` evidence.
- That implementation handoff is consumed by the merge.
- Next implementation must start only after Product Design Director explicitly bounds HR001 from the latest Development baseline.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` on `0389bb0748a4eb84d40b57707b4b1da47000b369` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Confirmed UI/Test/Governance-only scope, preserved Finance predicates/services/workflows, no known build/type failure, no unresolved inline thread and no current material contradiction.
- Approval is consumed by the merge and must not be reused for HR001.

### Development Integrator
- Revalidated PR #39 base/head/review/threads/diff scope, exact-head evidence, build-risk state and role-state freshness.
- Confirmed Development drift from PR base to merge time was QA-state-only and did not invalidate the reviewed product candidate.
- Transitioned the draft PR to ready-for-review without moving HEAD, then squash-merged with expected-head protection as `1a9509d598b9b462397838db7adc261c4746c52f`.
- Integration state is `MERGED_GREEN_DEV` for FIN002; workstream marks FIN002 DONE and exactly one next slice, HR001, READY.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Customer create/update/GPS/lookup/credit/default branch/default contact semantics must not drift.
- Sales query/filter/pagination/navigation/permission/payment/Smart Transfer/map/call/workflow truth must not drift.
- Sales Order form pricing/discount/tax/total/validation/submit semantics remain page/domain-owned.
- Inventory stock/query/filter/page/valuation/permission/review/link truth remains page/domain-owned.
- Inventory transfer movement/costing/reservation/approval/validation/permission/service/route truth remains page/domain/service-owned.
- Procurement purchase/accounting/query/permission/status/approval/service/validation truth remains page/domain/service-owned.
- Purchase Invoice pricing/quantity/discount/tax/total/payment/landed-cost/WAC/validation/submit/workflow truth remains page/domain-owned.
- Finance ledger/account/balance/payment/receipt/treasury/credit/debit/aging/calculation/posting/approval truth remains page/domain/service-owned.
- HR attendance/time, leave, payroll, employee/permission/query/service/workflow truth remains page/domain/service-owned.
- Shared `TransactionHeader` owns presentation/device placement, not business eligibility or workflow truth.
- Shared Stepper owns visual/interaction mechanics only; page/domain code owns workflow reachability and validation truth.
- Shared `FormSection`/`Card` own internal structure, not automatic external sibling spacing; consumer composition may own tokenized logical separation where required.
- Complete shared Tabs keyboard/focus/ARIA/RTL semantics remain system-owned; do not reintroduce partial page-local ARIA.
- Neutral categorical metadata uses `Badge`; semantic operational/workflow state uses `StatusBadge`.
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

- Development evidence through FIN002 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- Full shared Pagination convergence remains incomplete.
- Generic `DataTable` clickable-row keyboard semantics remain broader shared debt.
- Shared `SearchInput` clear-affordance accessibility remains pre-existing debt.
- Error/offline-state convergence remains broader shared state-system work.
- Dense-table overflow semantics remain a future hardening area.
- `DocumentActions` Mobile sticky-header density/touch geometry remains a runtime-review WATCH.
- Very long customer names in Payment Receipt header remain subject to the pre-existing `CustomerLink/EntityLink` ellipsis contract and should be stress-tested during the controlled long-Arabic/runtime pass.
- Payment Receipt body cards, amount summary, proof rendering and review-modal composition remain later Finance/global convergence debt.
- `InlineCombobox` / product chooser keyboard-accessibility debt remains real and outside completed Procurement work.
- HR is a high-risk functional-isolation boundary because attendance, time, payroll and leave workflows may contain domain/device semantics that must not leak into shared presentation.

## Reusable patterns learned

- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared navigation/action declarations should own placement decisions rather than pages inventing coordinates.
- Shared `TransactionHeader` now has cross-module proof in Sales and Finance: domain adapters may map identity/status/context while page code keeps eligibility, workflow and callbacks.
- Canonical `AppAction + resolveActionSet` can preserve page-owned action truth while enforcing Mobile/Tablet direct-action limits and overflow placement.
- Output tooling such as `DocumentActions` should stay distinct from workflow/review action eligibility when the two capabilities have different ownership.
- Native `details/summary` can provide an accessible RTL overflow baseline only when author CSS explicitly preserves the closed-state contract.
- Form composition can be standardized independently from business field semantics.
- Shared `PageHeader + FormSection + FormGrid + FormActions` has proof across Customer, Sales and Procurement.
- Shared Stepper can support optional guarded interaction without absorbing workflow truth or breaking non-editable modes.
- External spacing around a shared form section is a consumer-composition responsibility when the shared primitive intentionally owns internal spacing only; use logical shared tokens rather than global primitive margins.
- Complete shared Tabs semantics can be reused through thin domain wrappers.
- Shared `ResponsiveCollection` has proof across Sales Orders, Inventory Stock, Inventory Transfers, Procurement Purchase Invoices and Finance Vaults.
- Shared `MetricGrid + StatCard` can project page-owned financial summary values without owning calculations or inferring semantics.
- Thin domain cards/adapters should stay presentation-only: shared patterns own layout/interaction grammar, domain/page code owns business truth.
- Initial-empty and filtered-empty require distinct product language when filters/search are active.
- Search copy should describe actual service capability rather than promise unsupported matching.
- A live migrated surface may justify narrow shared-component hardening without opening a speculative framework rewrite.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect the live HR/People Mobile operational surfaces on the exact latest `design-system-v2-development` baseline and bound the smallest representative presentation-only concern for `DS2-HR-001`, explicitly preserving attendance/time, leave, payroll, employee, permission, query/service/workflow and device-capability truth and avoiding a broad HR framework redesign.

UI Production Engineer should bootstrap from the exact latest Development HEAD and take only that bounded concern. Design QA should independently review the next stable exact PR HEAD. Development Integrator should no-op until that head receives `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` and all normal gates pass.
