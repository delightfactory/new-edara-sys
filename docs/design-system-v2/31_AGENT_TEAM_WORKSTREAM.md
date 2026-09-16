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

Product UI is integrated through `DS2-INV-002`.

Latest product integration:
- PR: `#35 — DS2-INV-002: establish transfer flow V2 presentation`
- Exact reviewed PR HEAD: `d39d39281549650ef4bbd18767b20728a01117af`
- Squash merge commit: `9328464542b1ca429fd1ec134667f45244215b67`
- Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
- Runtime/preview/release evidence: not claimed

The development branch now includes shared semantic foundations, responsive shell/navigation/form/collection/action patterns, Dashboard V2, Customers migrations, Sales list/form/detail foundations, Inventory stock-list V2, and the first Inventory transfer collection migration with deliberate Desktop/Tablet/Mobile composition and source-level accessibility hardening.

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

## Current single READY slice

### DS2-PROC-001 — Purchase list surfaces
Status: `READY`
Owner role: Product Design Director -> UI Production Engineer after the concern is bounded

System intent:
Continue the North-Star roadmap into Procurement using the smallest representative purchase-list presentation concern, reusing the proven responsive collection, status, action and state grammar without changing procurement/accounting truth.

Initial direction:
- Product Design Director must inspect the live purchase-list surfaces and bound one representative dependency-safe concern before implementation expands;
- preserve purchase query/filter/pagination, supplier/warehouse/document identity, totals/taxes/currency, permission, status, approval, navigation and service semantics exactly;
- prefer one device-aware collection boundary, deliberate Tablet composition, touch-safe Mobile actions and dense Desktop comparison/review;
- reuse shared `ResponsiveCollection`, `Card`, `KeyValueList`, `Badge`/`StatusBadge`, `Button`, PageHeader/action/state grammar where they fit;
- strengthen only the smallest recurring shared gap proven by the selected live Procurement surface;
- author focused tests for material device/action/permission/state wiring; evidence follows `33_TEST_AND_VALIDATION_POLICY.md`.

Explicit exclusions:
- no purchase/accounting calculations or workflow changes;
- no DB/migration/RPC/service/query/cache/RBAC/RLS/permission/route-guard/validation semantic changes;
- no speculative broad Procurement redesign, Purchase Invoice form rewrite, or unrelated shared-component rewrite;
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
- `DS2-PROC-001` Purchase list surfaces — `READY`
- `DS2-PROC-002` Purchase Invoice form decomposition — `BACKLOG`

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
