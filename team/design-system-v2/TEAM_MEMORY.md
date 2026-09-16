# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-INV-002`.
- Current integrated product HEAD: `9328464542b1ca429fd1ec134667f45244215b67` from PR #35.
- Current single READY slice: `DS2-PROC-001 — Purchase list surfaces`.
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
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-INV-002 — Transfer/adjustment operational flows`

Result:
- PR #35 exact reviewed head `d39d39281549650ef4bbd18767b20728a01117af` received `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS`.
- Evidence remained honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/runtime PASS is claimed.
- Squash merge commit: `9328464542b1ca429fd1ec134667f45244215b67`.
- Earlier live-wiring, semantic-direction and Desktop accessibility blockers were all closed before the final review.
- `TransfersPage` now uses one `ResponsiveCollection<StockTransfer>` boundary instead of CSS-hidden duplicate Desktop/Mobile collection trees.
- Desktop keeps dense table review, expansion, items, notes/timestamps and authorized `finance.view_costs` unit-cost visibility.
- Tablet uses deliberate two-column `TransferCard` composition; Mobile uses one-column operational cards.
- `TransferCard` stays a thin Inventory-domain composition over shared `Card + KeyValueList + Badge + StatusBadge + Button`.
- Direction (`إرسال` / `طلب`) is neutral categorical metadata; workflow status alone owns semantic status tone.
- Ship / approve-and-ship / receive / cancel predicates and callbacks remain page-owned, including warehouse ownership, creator ownership and `approved_by !== userId` guards.
- Desktop expand/collapse has transfer-specific accessible naming + `aria-expanded`; transfer detail is a semantic `Link`; previous/next paging uses explicit Arabic RTL-safe labels and accessible names.
- Query `pageSize: 25`, filter reset, previous/next paging, create modal, confirmation flow, stock availability/reservation/validation, service calls, routes and invalidation remain unchanged.
- No hosted CI, Vercel preview, backend/business behavior or `main` change occurred.

## Current single READY slice

`DS2-PROC-001 — Purchase list surfaces`

Intent:
- continue the North-Star roadmap into Procurement with the smallest representative dependency-safe purchase-list presentation concern;
- Product Design Director should inspect live purchase-list surfaces and bound one concern before implementation expands;
- preserve purchase query/filter/pagination, supplier/warehouse/document identity, totals/taxes/currency, permission, status, approval, navigation, service and accounting semantics exactly;
- reuse proven shared responsive collection/card/status/action/state grammar where it genuinely fits;
- Mobile remains task-oriented and touch-safe; Tablet deliberate; Desktop dense for comparison/review;
- strengthen only the smallest recurring shared contract proven by the selected live Procurement surface;
- do not include Purchase Invoice form decomposition, backend/query/RBAC/RLS/permission/workflow changes, speculative global Pagination convergence, deployment or preview work.

## Latest role positions

### Product Design Director
- Independently cleared PR #35 exact head `d39d392...` with no current Design-System blocker before integration.
- Its approval is consumed by the successful merge and must not be reused for Procurement.
- Next action is to bound one representative purchase-list presentation concern for `DS2-PROC-001` from the latest Development baseline.

### UI Production Engineer
- Corrected the final three Desktop interaction/accessibility issues on PR #35 while preserving transfer behavior.
- Evidence was `TESTS_AUTHORED_NOT_EXECUTED`.
- That implementation handoff is consumed by the merge.
- Next implementation must start only from the latest Development HEAD after Product Design Director bounds PROC001.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` on `d39d392...` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Confirmed no known build/type failure, no current material peer contradiction, no forbidden backend/business/deployment scope and no unresolved review thread.
- Approval is consumed by the merge and must not be reused for the next slice.

### Development Integrator
- Revalidated PR #35 base/head/review marker/threads/diff scope and stale-vs-current role-state contradictions.
- Marked the unchanged GREEN head Ready and squash-merged it with expected-head protection as `9328464542b1ca429fd1ec134667f45244215b67`.
- Integration state is `MERGED_GREEN_DEV` for DS2-INV-002.
- Workstream marks DS2-INV-002 DONE and exactly one next slice, DS2-PROC-001, READY.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Customer create/update/GPS/lookup/credit/default branch/default contact/Branch-Contact semantics must not drift.
- Sales query/filter/pagination/navigation/permission/payment/Smart Transfer/map/call/workflow truth must not drift.
- Sales Order form pricing/discount/tax/total/validation/submit semantics remain page/domain-owned.
- Sales transaction-detail permission/status/workflow/callback/query/service/calculation truth remains page/domain-owned.
- Inventory stock/query/filter/page/valuation/permission/review/link truth remains page/domain-owned.
- Inventory transfer movement/costing/reservation/approval/validation/permission/service/route truth remains page/domain/service-owned.
- Procurement purchase/accounting/query/permission/status/approval/service truth must remain page/domain/service-owned.
- Shared `TransactionHeader` owns presentation/device placement, not business eligibility or workflow truth.
- Shared Stepper owns visual/interaction mechanics only; page/domain code owns workflow reachability and validation truth.
- Complete shared Tabs keyboard/focus/ARIA/RTL semantics remain system-owned; do not reintroduce partial page-local ARIA.
- Neutral categorical metadata uses `Badge`; semantic operational/workflow state uses `StatusBadge`.
- Shared Button/action hierarchy should own migrated actions.
- Mobile operational actions remain clear and touch-ready.
- Tablet must not collapse into oversized Mobile or cramped Desktop.
- Desktop must remain efficient for dense management/review/data-entry work.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Hidden duplicate device interaction trees should be avoided where device-aware composition exists.
- Each agent writes only its own specialist state; all agents read every specialist state.
- Durable decisions belong in the Decision Log; routine progress does not.
- No hosted CI, Vercel preview or `main` activity from scheduled agents.

## Known evidence / risks

- Development evidence through DS2-INV-002 remains source-level: no exact-head executed test suite, local build, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- Shared numbered/previous-next Pagination still lacks a converged reusable pattern; local hardening in Inventory should not trigger speculative framework work without a live need.
- Dense-table overflow semantics remain a future hardening area.
- Permission-limited empty-state microcopy should later converge toward neutral explanatory language.
- `DocumentActions` Mobile sticky-header density/touch polish remains a runtime-review WATCH.
- Combobox/ProductLine interaction debt remains real but deferred until a live screen proves a reusable need.
- Transfer Detail, Adjustments and transfer create-flow modernization remain outside the completed representative INV002 slice.
- Procurement is the next module; purchase totals/status/approval/accounting semantics create a high-risk functional-isolation boundary and must remain untouched by the UI slice.

## Reusable patterns learned

- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared navigation/action declarations should own placement decisions rather than pages inventing coordinates.
- Canonical `AppAction + resolveActionSet` can drive shared transaction headers while domain pages retain eligibility/callback truth.
- Shared `TransactionHeader` can expose Mobile/Tablet/Desktop action hierarchy without creating a new action taxonomy.
- Form composition can be standardized independently from business field semantics.
- Shared `PageHeader + FormSection + FormGrid + FormActions` has real Customer and Sales proof points.
- Shared Stepper can support optional guarded interaction without absorbing workflow truth or breaking read-only consumers.
- Complete shared Tabs semantics can be reused through thin domain wrappers.
- Shared `ResponsiveCollection` now has proof across Sales Orders, Inventory Stock and Inventory Transfers.
- Thin domain cards can compose shared `Card + KeyValueList + Badge/StatusBadge + Button` without creating a new primitive family.
- Categorical direction/type metadata should remain visually neutral; semantic status tone is reserved for actual operational/workflow state.
- Page-owned action predicates can be centralized once for presentation reuse across device renderers without moving business ownership into shared components.
- Accessibility hardening should use complete semantic controls (`Button`, `Link`, labels/state) rather than partial page-local ARIA systems.
- Domain adapters should stay thin: shared patterns own presentation, domain/page code owns business truth.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect the live Procurement purchase-list surfaces on the exact latest `design-system-v2-development` baseline and bound the smallest representative presentation-only concern for `DS2-PROC-001`, explicitly preserving purchase/accounting/query/permission/status/approval/service truth and avoiding speculative framework expansion.

UI Production Engineer should bootstrap from the exact latest Development HEAD and take only that bounded concern. Design QA should independently review the next stable exact PR HEAD. Development Integrator should no-op until that head receives `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` and all normal gates pass.
