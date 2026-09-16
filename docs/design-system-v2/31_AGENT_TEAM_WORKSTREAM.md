# 31 — Design System V2 Agent Team Workstream

## Purpose

Shared operating board for the autonomous EDARA Design System V2 team.

Authoritative branch: `design-system-v2-development`.
`main` remains frozen until explicit owner approval.

Authorities:
- Product quality: `32_DESIGN_SYSTEM_NORTH_STAR.md`
- Test/evidence: `33_TEST_AND_VALIDATION_POLICY.md`
- Communication: `34_AGENT_TEAM_COMMUNICATION_PROTOCOL.md`

## Team and state machine

| Role | Responsibility | Cadence | Product code | Merge | Deploy |
|---|---|---|---:|---:|---:|
| Product Design Director | System identity, architecture, next slice, design quality | every 2 hours | No | No | No |
| UI Production Engineer | Implement/repair the single active UI slice | hourly | UI-only | No | No |
| Design QA | Independent exact-head review | hourly | No | No | No |
| Development Integrator | Merge GREEN-DEV PR and advance queue | hourly | No feature work | Development only | No |

`BACKLOG -> READY -> IN_PROGRESS -> REVIEW -> GREEN-DEV -> DONE`

Exceptional state: `BLOCKED`.
Only one implementation slice may be active. A role with nothing actionable must no-op.

## Repository-native communication

Before material action every role reads Team Memory, all four role states, the Decision Log, this workstream, issue #27, and the active PR. Each role owns only its own state file. Integrator updates Team Memory after successful merge. Issue #27 is the concise event stream.

## GitHub Actions / preview policy

Hosted GitHub Actions remain forbidden while quota protection is active. Focused tests are still authored. Normal development evidence is exact-head `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + an honest execution label. A known real build/type failure blocks integration.

Vercel preview remains owner-requested only. Scheduled agents never merge to `main`.

## Current integrated baseline

Product UI is integrated through `DS2-PROC-001`.

Latest product integration:
- PR: `#36 — DS2-PROC-001: establish purchase invoice list V2 presentation`
- Exact reviewed PR HEAD: `df3da0e6a5b00e85c8ba35f1b99481e8f0b396be`
- Squash merge commit: `936129c69a51237ceeefc7880d9735aa5f584879`
- Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
- Runtime/preview/release evidence: not claimed

The development branch now includes shared semantic foundations, responsive shell/navigation/form/collection/action patterns, Dashboard V2, Customers migrations, Sales list/form/detail foundations, Inventory list/transfer migrations, and the first Procurement purchase-list migration with deliberate Desktop/Tablet/Mobile composition plus bounded shared `DataTable` pagination hardening.

## Completed slices

### DS2-UI-001 — Customer Form: basic-info composition
Status: `DONE`
Merged PR: `#28`
Reviewed HEAD: `b6bfceeb8327437e274222c7e2f75e83c4a65061`
Squash merge: `cdcc1a57cc3367fdd161fddb3d9e5b42e92e4829`
Evidence: `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`

### DS2-UI-002 — Customer detail secondary tabs/patterns
Status: `DONE`
Merged PR: `#29`
Reviewed HEAD: `1cb3853bf3cf94b2a25edd637d0083006e5d2191`
Squash merge: `773085994502401a7368eded20926b1308b62e3f`
Evidence: `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`

### DS2-UI-003 — Sales Orders list V2
Status: `DONE`
Merged PR: `#30`
Reviewed HEAD: `d03dbf4d32e0fb1a3e4888588a5c6d685689f1ff`
Squash merge: `e42910fb2bb7c945e67262f610d9e0b630d960a6`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`

System result:
- `ResponsiveCollection` owns one Desktop/Tablet/Mobile renderer.
- Desktop retains dense paged DataTable semantics.
- Tablet uses deliberate paged cards.
- Mobile preserves accumulated infinite loading.
- Sales query/filter/pagination/navigation/permission/payment/Smart Transfer/map/call/workflow semantics remain preserved.

### DS2-UI-004 — Sales Order form V2 foundation
Status: `DONE`
Merged PR: `#31`
Reviewed HEAD: `198f146a3abde9efa6bfb3c98c20469f3815d3ff`
Squash merge: `d00faf8e36d40c9dde9df0b2de6dc89737419c5d`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Runtime/preview/release evidence: not claimed

System result:
- shared `Stepper` supports optional page-owned guarded interaction while preserving legacy read-only behavior by default;
- Step 0 composes shared `FormSection` + `FormGrid` with `3 Desktop / 2 Tablet / 1 Mobile` density;
- bottom actions compose shared `FormActions` + `Button` with RTL-native cues;
- Sales create/edit/copy/pricing/permission/validation/save/route truth remains page/domain-owned.

### DS2-UI-005 — Sales transaction detail V2
Status: `DONE`
Merged PR: `#32`
Reviewed HEAD: `de7c99cb099ac4ccff941e1eb5f2dafacebd7ca6`
Squash merge: `58b0f3f8f54f04636d3a35dd7d658edb7bcf5068`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Runtime/preview/release evidence: not claimed

System result:
- shared `TransactionHeader` consumes canonical `AppAction[] + useDeviceMode + resolveActionSet`;
- live Sales detail maps existing eligibility/callback truth into shared presentation without moving workflow ownership;
- Mobile/Tablet/Desktop action placement is system-owned while business truth remains page/domain-owned.

### DS2-INV-001 — Inventory list surfaces
Status: `DONE`
Merged PR: `#34`
Reviewed HEAD: `819832d23cb9aafc895f56dc4b9f5ba2d21530b3`
Squash merge: `805995a5c0d9a118c415d647ed34e63dee326527`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Runtime/preview/release evidence: not claimed

System result:
- `StockPage` uses one `ResponsiveCollection<Stock>` boundary;
- Desktop keeps dense paged table review and authorized cost/value columns;
- Tablet uses deliberate two-column cards with numbered direct jumps;
- Mobile uses one-column operational cards with previous/next paging;
- `StockBalanceCard` remains a thin Inventory-domain composition over shared patterns;
- stock/query/filter/page/valuation/permission/review/link truth remains page/domain-owned.

### DS2-INV-002 — Transfer/adjustment operational flows
Status: `DONE`
Merged PR: `#35`
Reviewed HEAD: `d39d39281549650ef4bbd18767b20728a01117af`
Squash merge: `9328464542b1ca429fd1ec134667f45244215b67`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Runtime/preview/release evidence: not claimed

System result:
- the representative live `TransfersPage` collection now uses one `ResponsiveCollection<StockTransfer>` boundary instead of CSS-hidden duplicate device trees;
- Desktop preserves dense table review, row expansion, notes/timestamps and authorized `finance.view_costs` visibility;
- Tablet uses deliberate two-column `TransferCard` composition and Mobile uses one-column operational cards with touch-safe workflow/detail actions;
- `TransferCard` stays a thin Inventory-domain composition over shared `Card + KeyValueList + Badge + StatusBadge + Button`;
- transfer direction (`إرسال` / `طلب`) is neutral categorical metadata while actual workflow status owns semantic tone;
- exact ship / approve-and-ship / receive / cancel predicates and callbacks remain page-owned, including warehouse ownership, creator ownership and `approved_by !== userId` guards;
- Desktop expand/collapse has accessible naming + `aria-expanded`, transfer detail is a semantic `Link`, and previous/next paging uses explicit Arabic RTL-safe labels;
- query `pageSize: 25`, filter/page behavior, create modal, confirmation flow, stock availability/reservation/validation, services, routes and invalidation remain unchanged;
- Transfer Detail, Adjustments, create-flow/Combobox redesign and global Pagination convergence remain outside this completed representative slice.

### DS2-PROC-001 — Purchase list surfaces
Status: `DONE`
Merged PR: `#36`
Reviewed HEAD: `df3da0e6a5b00e85c8ba35f1b99481e8f0b396be`
Squash merge: `936129c69a51237ceeefc7880d9735aa5f584879`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Runtime/preview/release evidence: not claimed

System result:
- live `PurchaseInvoicesPage` now uses one `ResponsiveCollection<PurchaseInvoice>` boundary instead of CSS-hidden duplicate device trees;
- Desktop preserves dense `DataTable` comparison/review and numbered direct jumps;
- Tablet uses deliberate two-column `PurchaseInvoiceCard` composition with numbered direct jumps; Mobile uses one-column operational cards with touch-safe previous/next paging;
- `PurchaseInvoiceCard` remains a thin Procurement-domain composition over shared `Card + KeyValueList + StatusBadge + Button`;
- true initial-empty and filtered-empty states are distinct, and search copy matches the unchanged service search truth (`number` + `supplier_invoice_ref`);
- shared `DataTable` pagination now exposes a labeled navigation boundary, logical Arabic previous/next controls, accessible names, numeric `aria-current="page"`, and a bounded width-safe nav-button modifier while numeric page controls remain compact;
- purchase query/page/filter/reset, supplier/warehouse/document identity, total/paid values, status/workflow/accounting/permission/service and create/detail route truth remain page/domain/service-owned and unchanged;
- broad/global Pagination convergence, generic clickable-row hardening, Purchase Returns and Purchase Invoice form decomposition remain outside this completed representative slice.

## Current single active slice

### DS2-PROC-002 — Purchase Invoice form decomposition
Status: `REVIEW`
Owner role: UI Production Engineer
Draft PR: `#37`
Exact baseline: `e4866c9350c507bce260beb07d880fbce55718f3`

System intent:
Continue Procurement with the smallest representative Purchase Invoice form presentation concern, reusing the proven V2 form grammar without moving purchase/accounting/business truth into presentation.

Bounded implementation direction:
- use the shared V2 `Stepper` for new/editable-draft Purchase Invoice flow only, with Purchase Invoice validation/reachability remaining domain/page-owned;
- replace duplicate wrappers in the basic-information section only with shared `FormSection` / `FormGrid`;
- compose existing form actions through shared `FormActions` without changing action eligibility or callbacks;
- use shared `StatusBadge` for posted/read-only workflow status presentation where applicable;
- do not overlay editable Stepper UX over posted/finalized/read-only invoices;
- preserve supplier/warehouse/product/document identity, pricing, quantities, discounts, taxes, totals, paid/due values, currency, accounting, approval/status/workflow, validation, permission, submit/save, query/cache, service and route semantics exactly;
- Mobile must remain task-oriented and touch-safe, Tablet deliberate, and Desktop efficient for dense data entry/review;
- author focused tests for material composition/action/state wiring; evidence follows `33_TEST_AND_VALIDATION_POLICY.md`.

Explicit exclusions:
- no purchase/accounting calculations, workflow transitions or validation-meaning changes;
- no DB/migration/RPC/service/query/cache/RBAC/RLS/permission/route-guard changes;
- no Purchase Returns migration in this slice;
- no speculative broad Procurement rewrite, global Combobox redesign or global Pagination convergence;
- no deployment/preview/main changes.

## Product migration roadmap

The Product Design Director may decompose an item further, but exactly one dependency-safe implementation slice becomes READY at a time.

### A. Golden flows
- `DS2-UI-001` Customer Form basic-info — `DONE`
- `DS2-UI-002` Customer detail secondary tabs/patterns — `DONE`
- `DS2-UI-003` Sales Orders list V2 — `DONE`
- `DS2-UI-004` Sales Order form V2 foundation — `DONE`
- `DS2-UI-005` Sales transaction detail V2 — `DONE`

### B. Shared component-depth program
Open only when a real migrated screen proves the recurring gap:
- FilterBar decomposition and Mobile filter-sheet contract
- DataTable V2 hardening and table action/accessibility/overflow-region contract
- shared Pagination convergence
- MobileDataCard semantic migration from legacy DataCard
- Modal/ResponsiveSheet/ConfirmDialog convergence
- Combobox/AsyncCombobox keyboard/focus hardening
- Tabs/SubNav/SegmentedControl adoption cleanup
- EntityHeader / TransactionHeader
- Timeline / ActivityFeed / AuditTimeline
- FinancialSummary / InventorySummary / ApprovalPanel
- BulkActionBar / CommandBar
- progress/accessibility contract
- upload/camera/GPS interaction grammar
- toast/alert/inline-validation convergence
- Loading/Empty/Error/Permission/Offline/Sync state grammar
- chart/report legend/metric grammar

### C. Inventory
- `DS2-INV-001` Inventory list surfaces — `DONE`
- `DS2-INV-002` Transfer/adjustment operational flows — `DONE`

### D. Procurement
- `DS2-PROC-001` Purchase list surfaces — `DONE`
- `DS2-PROC-002` Purchase Invoice form decomposition — `REVIEW`

### E. Finance
- `DS2-FIN-001` Finance lists and summaries — `BACKLOG`
- `DS2-FIN-002` Financial transaction/detail/action patterns — `BACKLOG`

### F. HR / People
- `DS2-HR-001` Mobile operational tasks — `BACKLOG`
- `DS2-HR-002` HR admin lists/forms — `BACKLOG`

### G. Field Activities / Targets
- `DS2-FIELD-001` Activities/visit/call/target lists — `BACKLOG`
- `DS2-FIELD-002` Field create/detail flows — `BACKLOG`

### H. Work Management
- `DS2-WORK-001` Reconcile Work UI island with V2 — `BACKLOG`

### I. Reports / Analytics
- `DS2-REPORT-001` Report shell/navigation/filter grammar — `BACKLOG`
- `DS2-REPORT-002` Metrics/charts/tables and responsive report composition — `BACKLOG`

### J. Settings / Administration
- `DS2-ADMIN-001` Users/roles/settings/audit surfaces — `BACKLOG`

### K. Global convergence and cleanup
- `DS2-GLOBAL-001` Global style debt and inline-style reduction — `BACKLOG`
- `DS2-GLOBAL-002` Dark mode / RTL / long Arabic / numeric stress pass — `BACKLOG`
- `DS2-GLOBAL-003` Accessibility/focus/touch/motion pass — `BACKLOG`
- `DS2-GLOBAL-004` Legacy component/CSS retirement — `BACKLOG`
- `DS2-GLOBAL-005` Final visual/system consistency audit — `BACKLOG`

## Integrator development gate

Before merge:
- exact current PR HEAD has `AGENT-REVIEW: GREEN-DEV`;
- reviewer records `SOURCE_REVIEW_PASS` and honest test evidence;
- no known build/type failure;
- no unresolved material blocker or current `BLOCKING` role-state contradiction;
- PR base is `design-system-v2-development`;
- diff contains no forbidden backend/business/query/permission/deployment change.

After merge:
- completed slice becomes DONE with reviewed/merge SHA and evidence;
- exactly one next dependency-safe roadmap item becomes READY;
- Integration State and Team Memory are synchronized;
- no preview deployment;
- no merge to `main`.

## End condition

The autonomous workstream continues until the North Star completion definition is met across major modules, shared component grammar, device behavior, RTL/dark/state/accessibility convergence and final controlled runtime review.
