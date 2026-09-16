# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-PROC-001`.
- Current integrated product HEAD: `936129c69a51237ceeefc7880d9735aa5f584879` from PR #36.
- Current single READY slice: `DS2-PROC-002 — Purchase Invoice form decomposition`.
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
- Sales Order form V2 outer foundation and guarded shared Stepper contract;
- Sales transaction-detail header V2 using canonical `AppAction + resolveActionSet` placement;
- Inventory stock list V2 using one `ResponsiveCollection<Stock>` boundary with deliberate Desktop/Tablet/Mobile paging composition;
- Inventory transfer collection V2 using one `ResponsiveCollection<StockTransfer>` boundary with thin `TransferCard`, semantic metadata/status separation and source-level Desktop accessibility hardening;
- Procurement Purchase Invoice list V2 using one `ResponsiveCollection<PurchaseInvoice>` boundary with thin `PurchaseInvoiceCard`, deliberate device composition, correct initial-vs-filtered empty states and source-level search/status semantics;
- bounded shared `DataTable` pagination hardening: labeled pagination navigation, logical Arabic previous/next controls, accessible names, `aria-current="page"`, and width-safe previous/next controls while numeric pages stay compact;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-PROC-001 — Purchase list surfaces`

Result:
- PR #36 exact reviewed HEAD `df3da0e6a5b00e85c8ba35f1b99481e8f0b396be` received `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS`.
- Evidence remained honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview PASS is claimed.
- Squash merge commit: `936129c69a51237ceeefc7880d9735aa5f584879`.
- Earlier pagination semantics, filtered-empty, search-copy and Arabic paginator visual-fit blockers were all closed before final review.
- `PurchaseInvoicesPage` now uses one `ResponsiveCollection<PurchaseInvoice>` boundary instead of CSS-hidden duplicate Desktop/Mobile trees.
- Desktop keeps dense `DataTable` comparison/review and numbered direct jumps.
- Tablet uses deliberate two-column `PurchaseInvoiceCard` composition with numbered direct jumps; Mobile uses one-column operational cards with touch-safe previous/next paging.
- `PurchaseInvoiceCard` stays a thin Procurement-domain composition over shared `Card + KeyValueList + StatusBadge + Button`.
- True initial-empty and filtered-empty states are distinct.
- Search affordance accurately describes the unchanged service search truth: invoice `number` or `supplier_invoice_ref`; no supplier-name query behavior was invented.
- Shared `DataTable` previous/next controls use logical Arabic labels with explicit accessible names inside a labeled pagination `nav`; numeric current page exposes `aria-current="page"`; previous/next have the bounded `pagination-btn-nav` width-safe contract while numeric page buttons remain compact.
- Existing `DataTable` page-window algorithm, callback targets and disabled boundaries remain unchanged.
- `getPurchaseInvoices`, `queryKey: ['purchase-invoices', search, statusFilter, page]`, `PAGE_SIZE = 20`, search/status reset-to-page-1 behavior, supplier/warehouse/document identity, total/paid values, purchase status/workflow/accounting/permission/service truth and create/detail routes remain unchanged.
- No hosted CI, Vercel preview, backend/business behavior or `main` change occurred.

## Current single READY slice

`DS2-PROC-002 — Purchase Invoice form decomposition`

Intent:
- continue Procurement with the smallest representative Purchase Invoice create/edit form presentation concern;
- Product Design Director must inspect the live form from the exact latest Development baseline and bound one dependency-safe concern before implementation expands;
- preserve supplier/warehouse/product/document identity, quantities, pricing, discounts, taxes, totals, paid/due values, currency, accounting, approval/status/workflow, validation, permissions, submit/save, query/cache, services and routes exactly;
- reuse proven shared `PageHeader`, `FormSection`, `FormGrid`, `FormActions`, `Button` and existing field grammar where the live form proves fit;
- strengthen a shared form/combobox interaction contract only if the selected live surface proves a recurring need and the correction remains presentation/interaction-only;
- Mobile remains task-oriented and touch-safe; Tablet deliberate; Desktop dense and efficient for data entry/review;
- do not include Purchase Returns, backend/query/RBAC/RLS/permission/accounting/workflow changes, speculative global Combobox/Pagination redesign, deployment or preview work.

## Latest role positions

### Product Design Director
- Independently cleared PR #36 exact HEAD `df3da0e6...` with no current Design-System blocker before integration.
- Confirmed the representative Procurement architecture, empty/search semantics and narrow shared DataTable paginator correction fit the North Star.
- That approval is consumed by the successful merge and must not be reused for PROC002.
- Next action is to inspect the live Purchase Invoice form on the latest Development baseline and bound one smallest presentation-only concern for PROC002.

### UI Production Engineer
- Implemented the Purchase Invoice list migration and the final bounded shared paginator correction on PR #36.
- Evidence was `TESTS_AUTHORED_NOT_EXECUTED`.
- That implementation handoff is consumed by the merge.
- Next implementation must start from the latest Development baseline after Product Design Director bounds PROC002.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` on `df3da0e6...` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Confirmed no known build/type failure, no current material peer contradiction, no forbidden backend/business/deployment scope and no unresolved review thread.
- Approval is consumed by the merge and must not be reused for the next slice.

### Development Integrator
- Revalidated PR #36 base/head/review marker/threads/diff scope, known build-risk state and role-state freshness.
- Confirmed Development drift since PR base was governance-only and did not invalidate the reviewed product candidate.
- Marked the unchanged GREEN head Ready and squash-merged it with expected-head protection as `936129c69a51237ceeefc7880d9735aa5f584879`.
- Integration state is `MERGED_GREEN_DEV` for DS2-PROC-001.
- Workstream marks PROC001 DONE and exactly one next slice, DS2-PROC-002, READY.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Customer create/update/GPS/lookup/credit/default branch/default contact/Branch-Contact semantics must not drift.
- Sales query/filter/pagination/navigation/permission/payment/Smart Transfer/map/call/workflow truth must not drift.
- Sales Order form pricing/discount/tax/total/validation/submit semantics remain page/domain-owned.
- Sales transaction-detail permission/status/workflow/callback/query/service/calculation truth remains page/domain-owned.
- Inventory stock/query/filter/page/valuation/permission/review/link truth remains page/domain-owned.
- Inventory transfer movement/costing/reservation/approval/validation/permission/service/route truth remains page/domain/service-owned.
- Procurement purchase/accounting/query/permission/status/approval/service/validation truth remains page/domain/service-owned.
- Purchase Invoice form pricing/quantity/discount/tax/total/payment/validation/submit/workflow truth must remain page/domain-owned during PROC002.
- Shared `TransactionHeader` owns presentation/device placement, not business eligibility or workflow truth.
- Shared Stepper owns visual/interaction mechanics only; page/domain code owns workflow reachability and validation truth.
- Complete shared Tabs keyboard/focus/ARIA/RTL semantics remain system-owned; do not reintroduce partial page-local ARIA.
- Neutral categorical metadata uses `Badge`; semantic operational/workflow state uses `StatusBadge`.
- Shared Button/action hierarchy should own migrated actions.
- Shared `DataTable` paginator semantics now include logical Arabic previous/next, labeled navigation, accessible names, current-page semantics and width-safe previous/next controls; this does not imply full global Pagination convergence.
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

- Development evidence through DS2-PROC-001 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- Full shared Pagination convergence is still incomplete; PROC001 only hardened the proven `DataTable` pagination contract narrowly.
- Generic `DataTable` clickable-row keyboard semantics remain broader shared debt.
- Shared `SearchInput` clear-affordance accessibility remains pre-existing debt.
- Error/offline-state convergence remains broader shared state-system work.
- Dense-table overflow semantics remain a future hardening area.
- Permission-limited empty-state microcopy should later converge toward neutral explanatory language.
- `DocumentActions` Mobile sticky-header density/touch polish remains a runtime-review WATCH.
- Combobox/ProductLine interaction debt remains real; PROC002 may prove a reusable need, but agents must not pre-emptively open a global redesign.
- Purchase Returns remain outside the completed PROC001 slice.
- PROC002 is a high-risk functional-isolation boundary because purchase form totals/tax/payment/accounting/validation/workflow truth must remain untouched.

## Reusable patterns learned

- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared navigation/action declarations should own placement decisions rather than pages inventing coordinates.
- Canonical `AppAction + resolveActionSet` can drive shared transaction headers while domain pages retain eligibility/callback truth.
- Shared `TransactionHeader` can expose Mobile/Tablet/Desktop action hierarchy without creating a new action taxonomy.
- Form composition can be standardized independently from business field semantics.
- Shared `PageHeader + FormSection + FormGrid + FormActions` has real Customer and Sales proof points.
- Shared Stepper can support optional guarded interaction without absorbing workflow truth or breaking read-only consumers.
- Complete shared Tabs semantics can be reused through thin domain wrappers.
- Shared `ResponsiveCollection` now has proof across Sales Orders, Inventory Stock, Inventory Transfers and Procurement Purchase Invoices.
- Thin domain cards can compose shared `Card + KeyValueList + Badge/StatusBadge + Button` without creating a new primitive family.
- Categorical direction/type metadata should remain visually neutral; semantic status tone is reserved for actual operational/workflow state.
- Page-owned action predicates can be centralized once for presentation reuse across device renderers without moving business ownership into shared components.
- Accessibility hardening should use complete semantic controls (`Button`, `Link`, labels/state) rather than partial page-local ARIA systems.
- Initial-empty and filtered-empty require distinct product language when filters/search are active.
- Search copy should describe actual service capability rather than promise unsupported matching.
- A live migrated surface may justify a narrow shared-component hardening (`DataTable` paginator here) without opening a speculative framework rewrite.
- Domain adapters should stay thin: shared patterns own presentation, domain/page code owns business truth.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect the live Purchase Invoice create/edit form on the exact latest `design-system-v2-development` baseline and bound the smallest representative presentation-only concern for `DS2-PROC-002`, explicitly preserving supplier/warehouse/product/pricing/tax/total/payment/accounting/validation/permission/workflow/service truth and avoiding speculative shared-component expansion.

UI Production Engineer should bootstrap from the exact latest Development HEAD and take only that bounded concern. Design QA should independently review the next stable exact PR HEAD. Development Integrator should no-op until that head receives `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` and all normal gates pass.
