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

Product UI is integrated through `DS2-PROC-002`.

Latest product integration:
- PR: `#37 — DS2-PROC-002: establish purchase invoice form V2 shell`
- Exact reviewed PR HEAD: `4fa613edad180de140b9c7a1c41ceeb9b7e55ee3`
- Squash merge commit: `5b10b9fb578c91798d28526d8de407f63ffcc417`
- Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
- Runtime/preview/release evidence: not claimed

The development branch now includes semantic foundations, responsive shell/navigation/form/collection/action patterns, Dashboard V2, Customers migrations, Sales list/form/detail foundations, Inventory list/transfer migrations, Procurement purchase-list migration, bounded shared `DataTable` pagination hardening, and the first Purchase Invoice form-shell migration using the shared Stepper/FormSection/FormGrid/FormActions/StatusBadge grammar.

## Completed slices

- `DS2-UI-001 — Customer Form: basic-info composition` — `DONE` — PR #28 — merge `cdcc1a57cc3367fdd161fddb3d9e5b42e92e4829` — `SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-UI-002 — Customer detail secondary tabs/patterns` — `DONE` — PR #29 — merge `773085994502401a7368eded20926b1308b62e3f` — `SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-UI-003 — Sales Orders list V2` — `DONE` — PR #30 — merge `e42910fb2bb7c945e67262f610d9e0b630d960a6` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-UI-004 — Sales Order form V2 foundation` — `DONE` — PR #31 — merge `d00faf8e36d40c9dde9df0b2de6dc89737419c5d` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-UI-005 — Sales transaction detail V2` — `DONE` — PR #32 — merge `58b0f3f8f54f04636d3a35dd7d658edb7bcf5068` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-INV-001 — Inventory list surfaces` — `DONE` — PR #34 — merge `805995a5c0d9a118c415d647ed34e63dee326527` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-INV-002 — Transfer/adjustment operational flows` — `DONE` — PR #35 — merge `9328464542b1ca429fd1ec134667f45244215b67` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-PROC-001 — Purchase list surfaces` — `DONE` — PR #36 — merge `936129c69a51237ceeefc7880d9735aa5f584879` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.

### DS2-PROC-002 — Purchase Invoice form decomposition
Status: `DONE`
Merged PR: `#37`
Reviewed HEAD: `4fa613edad180de140b9c7a1c41ceeb9b7e55ee3`
Squash merge: `5b10b9fb578c91798d28526d8de407f63ffcc417`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Runtime/preview/release evidence: not claimed

System result:
- new/editable-draft Purchase Invoice flow uses a thin `PurchaseInvoiceDraftStepper` over the shared V2 `Stepper`, preserving page-owned reachability and validation and not unlocking review/final direct navigation;
- **بيانات الفاتورة** uses shared `FormSection + FormGrid` with deliberate `3 Desktop / 2 Tablet / 1 Mobile` composition while preserving supplier/warehouse/date/reference/landed-cost/notes truth and disabled rules;
- editable wizard actions use shared `FormActions + Button`, preserving cancel/back/next/save callbacks, save-disabled truth and RTL-native cues;
- Purchase workflow status uses shared semantic `StatusBadge` with the same Procurement vocabulary as the list surface;
- consumer-owned logical `margin-block-end: var(--space-4)` restores inter-section hierarchy at the Purchase Invoice composition boundary without adding external margin to shared `FormSection`/`Card`;
- supplier/product/warehouse identity, quantities, pricing, discounts, taxes, totals, landed costs/WAC/accounting/payment, receive/bill/cancel transitions, permissions, services/query/cache, routes, validation semantics, `ResponsiveModal`, mobile item flow and `DocumentActions` remain unchanged and page/domain-owned;
- `InlineCombobox`, item-table/card convergence, receive/accounting presentation, Purchase Returns and broad form-field convergence remain outside this completed slice.

## Current single active slice

### DS2-FIN-001 — Finance lists and summaries
Status: `REVIEW`
Owner role: UI Production Engineer

System intent:
Continue the roadmap into Finance using one representative, dependency-safe list/summary presentation concern that proves shared collection, summary, state and action grammar without moving financial truth into presentation.

Current bounded candidate result:
- representative live surface remains `VaultsPage` overview only (summary metrics + vault collection presentation);
- summary values remain page-owned and now project through shared `MetricGrid + StatCard`; total-balance semantic tone is caller-owned and factual active-count receives no inferred success tone;
- one live `ResponsiveCollection<Vault>` replaces the CSS-hidden Desktop/Mobile dual trees, preserving dense Desktop `DataTable`, adding deliberate two-column Tablet cards and one-column Mobile cards, and keeping loading/empty/create behavior in one mounted collection boundary;
- vault type is neutral categorical `Badge` metadata while active/inactive uses semantic `StatusBadge`;
- Mobile/Tablet card actions consume canonical `AppAction + resolveActionSet` semantics with the existing page-owned action order and eligibility: maximum 1 direct action on Mobile, 2 on Tablet, remaining actions in accessible RTL overflow; Desktop retains dense direct table actions;
- `finance.vaults.create/transact/update`, `current_balance === 0`, create/update/manual-adjustment/transfer services, totals/balances, statement `pageSize: 25`, query/cache/invalidation, modal workflows and validations remain page/domain-owned and unchanged;
- forms, statement/transaction/transfer modal redesign, posting/accounting semantics and other Finance pages remain outside this bounded concern;
- focused component and live-page source-contract tests are authored; evidence remains `TESTS_AUTHORED_NOT_EXECUTED`.

Initial direction:
- preserve ledger/account/balance/payment/receipt/treasury/credit/debit/aging/calculation/posting/approval/permission/query/cache/service/route semantics exactly;
- prefer already-proven shared `PageHeader`, collection/card/table, semantic status, summary and action patterns when the live surface proves fit;
- Mobile remains operational and touch-safe, Tablet deliberate, Desktop dense and efficient for financial review/comparison;
- author focused tests for material responsive/state/action/permission presentation contracts; evidence follows `33_TEST_AND_VALIDATION_POLICY.md`.

Explicit exclusions:
- no accounting calculations or posting/workflow changes;
- no DB/migration/RPC/service/query/cache/RBAC/RLS/permission/route-guard changes;
- no speculative global financial framework or chart/report redesign;
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
- `DS2-PROC-002` Purchase Invoice form decomposition — `DONE`

### E. Finance
- `DS2-FIN-001` Finance lists and summaries — `REVIEW`
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
