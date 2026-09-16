# 31 — Design System V2 Agent Team Workstream

## Purpose

Shared operating board for the autonomous, around-the-clock Design System V2 team.

Authoritative branch: `design-system-v2-development`

`main` remains frozen until explicit owner approval of the completed Design System V2 rollout.

Product-quality authority: `32_DESIGN_SYSTEM_NORTH_STAR.md`.
Test/evidence authority: `33_TEST_AND_VALIDATION_POLICY.md`.
Communication authority: `34_AGENT_TEAM_COMMUNICATION_PROTOCOL.md`.

## Team and continuous state machine

| Role | Responsibility | Normal cadence | Product code | Merge | Deploy |
|---|---|---|---:|---:|---:|
| Product Design Director | System identity, architecture, next slice, design quality | every 2 hours | No | No | No |
| UI Production Engineer | Implement/repair the single active UI slice | hourly | UI-only | No | No |
| Design QA | Independent exact-head product/design/technical review | hourly | No | No | No |
| Development Integrator | Merge GREEN-DEV PR and advance queue | hourly | No feature work | Development only | No |

`BACKLOG -> READY -> IN_PROGRESS -> REVIEW -> GREEN-DEV -> DONE`

Exceptional state: `BLOCKED`.

Only one implementation slice may be `IN_PROGRESS` or `REVIEW` at a time. A role with nothing actionable must no-op. Preview/runtime/release evidence remains separate from development integration.

## Repository-native team communication

Before material action every role reads Team Memory, all four role-state files, the Decision Log, this workstream, issue #27, and the active PR. Each role owns only its own state file in normal operation. Integrator updates Team Memory after successful merge. Issue #27 is a concise event stream, not hourly chatter.

A mismatch between Workstream, Team Memory, active PR, and role states is a coordination blocker until reconciled.

## GitHub Actions / execution budget

Hosted GitHub Actions remain forbidden while quota protection is active. Agents continue to author focused tests. Normal development integration evidence is `SOURCE_REVIEW_PASS` plus an honest execution label, commonly `TESTS_AUTHORED_NOT_EXECUTED`. A known real build/type failure always blocks integration. Vercel preview is owner-requested only.

## Current integrated baseline

Product UI is integrated through `DS2-UI-003`.

Latest product integration:
- PR: `#30 — DS2-UI-003: migrate Sales Orders list to shared V2 grammar`
- Exact reviewed PR HEAD: `d03dbf4d32e0fb1a3e4888588a5c6d685689f1ff`
- Squash merge commit: `e42910fb2bb7c945e67262f610d9e0b630d960a6`
- Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
- Runtime/preview/release evidence: not claimed

The development branch now includes:
- Design System V2 semantic foundations and shared primitives/patterns
- responsive collection/action/form composition foundations
- navigation registry and deliberate Tablet shell behavior
- Sidebar V2 isolated renderer behind feature flag
- Dashboard V2 migration
- Customers List V2 migration
- Customer basic-info V2 form composition (`DS2-UI-001`)
- Customer secondary Tabs/Branches/Contacts/Credit V2 composition (`DS2-UI-002`)
- complete shared Tabs semantics reused by Customer detail surfaces
- Sales Orders list V2 composition (`DS2-UI-003`) with shared responsive collection, KPI/status/card/action/state grammar
- North Star, test policy, repository-native Team Memory/role-state communication and durable Decision Log

## Completed slices

### DS2-UI-001 — Customer Form: basic-info composition
Status: `DONE`
Merged PR: `#28`
Reviewed exact PR HEAD: `b6bfceeb8327437e274222c7e2f75e83c4a65061`
Squash merge commit: `cdcc1a57cc3367fdd161fddb3d9e5b42e92e4829`
Evidence: `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`

System result:
- shared `PageHeader`, `FormSection`, `FormGrid`, and `FormActions`
- existing create/update, GPS, lookup, credit and default branch/contact semantics preserved
- no partial ARIA Tabs contract retained

### DS2-UI-002 — Customer detail secondary tabs/patterns
Status: `DONE`
Merged PR: `#29`
Reviewed exact PR HEAD: `1cb3853bf3cf94b2a25edd637d0083006e5d2191`
Squash merge commit: `773085994502401a7368eded20926b1308b62e3f`
Evidence: `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Runtime/preview/release evidence: not claimed

System result:
- Customer edit sections now compose through the existing complete shared `Tabs` contract
- Customer-owned labels/counts/credit visibility remain thin domain composition
- Branch/Contact surfaces reuse shared `Card`, `SectionHeader`, `KeyValueList`, `StatePanel`, `Button`, neutral `Badge`, and semantic `StatusBadge`
- duplicate legacy section switcher and secondary render trees were removed
- Branch/Contact mutation visibility and Credit visibility permissions remain preserved
- existing ResponsiveModal/delete flows and credit-history table behavior remain intentionally outside shared overlay/DataTable redesign
- non-blocking future WATCH: permission-limited empty-state microcopy should become neutral in the later shared state/microcopy convergence pass
- non-blocking future WATCH: dense-table overflow-region semantics should be standardized in later DataTable/accessibility hardening

### DS2-UI-003 — Sales Orders list V2
Status: `DONE`
Merged PR: `#30`
Reviewed exact PR HEAD: `d03dbf4d32e0fb1a3e4888588a5c6d685689f1ff`
Squash merge commit: `e42910fb2bb7c945e67262f610d9e0b630d960a6`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Runtime/preview/release evidence: not claimed

System result:
- shared `ResponsiveCollection` owns one mounted Desktop/Tablet/Mobile collection renderer
- Desktop retains the existing dense paged `DataTable` and numbered pagination
- Tablet uses deliberate Sales cards while preserving the paged Desktop dataset and numbered-pagination semantics
- Mobile preserves accumulated `useMobileInfiniteList` data, sentinel, load-more and terminal-state behavior
- Sales KPI truth projects through shared `StatCard` grammar; existing Sales stats/business truth remains page/hook-owned
- Sales status projects through a thin domain adapter over shared semantic `StatusBadge`
- `SalesOrderCard` composes shared `Card`, `KeyValueList`, `Button`, and `StatusBadge` rather than creating a Sales-only primitive system
- Smart Transfer action surfaces and empty state use shared `Button` / `StatePanel`
- legacy Mobile `DataCard` and CSS-hidden duplicate Desktop/Mobile collection trees were removed from this page
- page-owned payment percentage truth remains separate from bounded progress geometry/ARIA
- all existing Sales query/filter/pagination/infinite-loading/navigation/permission/status/payment/Smart Transfer/map/call/business semantics remain preserved
- non-blocking future WATCH: converge Desktop/Tablet numbered pagination into one shared accessible Pagination/DataTable contract when the real hardening program opens
- non-blocking future WATCH: consider `aria-valuetext` in later progress/accessibility hardening for projected percentages above 100 while geometry remains bounded

## Current single READY slice

### DS2-UI-004 — Sales Order form V2 foundation
Status: `READY`
Owner role: UI Production Engineer

System intent:
Move the next Sales golden-flow form surface toward the shared V2 form/action grammar in small presentation-only sub-slices, while preserving every pricing, customer, product-line, validation, query and submit contract.

Initial scope direction:
- inspect the current Sales Order create/edit form and identify the smallest dependency-safe presentation slice
- reuse existing shared Field/FormSection/FormGrid/FormActions/Button/Combobox patterns before inventing new primitives
- strengthen only the smallest shared form/combobox/product-line presentation contract proven necessary by the real form
- deliberate Mobile/Tablet/Desktop composition and long Arabic/value tolerance
- preserve loading/error/disabled/read-only/permission states already present in the form contract

Must preserve:
- customer selection semantics
- product-line add/edit/remove semantics
- price resolution, discounts, taxes/totals and all monetary calculations
- validation meaning and submit wiring
- permission visibility
- service/query/cache contracts
- route/navigation behavior
- all Sales workflow/business-state transitions

Explicit exclusions:
- no pricing/accounting/business-calculation migration into UI primitives
- no service/query/cache changes
- no permission/RBAC/RLS/route-guard changes
- no transaction-detail redesign
- no speculative global form/combobox/stepper rewrite beyond the smallest recurring contract proven by the selected sub-slice
- no overlay/deployment/workflow changes

Acceptance direction:
- one bounded form-composition concern per implementation PR
- shared V2 grammar owns presentation while page/domain code retains business truth
- Mobile has clear task/action priority without ordinary horizontal overflow
- Tablet is deliberate rather than compressed Desktop
- Desktop retains efficient data-entry density
- focused tests are authored for the specific composition/behavior risk of each sub-slice
- evidence follows `33_TEST_AND_VALIDATION_POLICY.md`

## Product migration roadmap

The Product Design Director may further decompose a roadmap item, but only one dependency-safe implementation slice becomes READY at a time.

### A. Golden flows

#### DS2-UI-003 — Sales Orders list V2
`DONE`
- merged PR #30
- exact reviewed HEAD `d03dbf4d32e0fb1a3e4888588a5c6d685689f1ff`
- squash merge `e42910fb2bb7c945e67262f610d9e0b630d960a6`
- `GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`

#### DS2-UI-004 — Sales Order form V2 foundation
`READY`
- presentation decomposition into shared Field/Combobox/FormSection/FormGrid/FormActions/ProductLine patterns
- implement only the smallest safe sub-slice selected from the live form
- no pricing/customer/product business-logic migration

#### DS2-UI-005 — Sales transaction detail V2
`BACKLOG`
- TransactionHeader / status / FinancialSummary / action hierarchy

### B. Shared component-depth program

Open only when a real migrated screen proves the recurring gap:
- FilterBar decomposition and Mobile filter-sheet contract
- DataTable V2 hardening and table action/accessibility/overflow-region contract
- shared Pagination convergence for Desktop/Tablet list surfaces
- MobileDataCard semantic migration from legacy DataCard
- Modal/ResponsiveSheet/ConfirmDialog V2 convergence
- Combobox/AsyncCombobox keyboard/focus hardening
- Tabs/SubNav/SegmentedControl adoption cleanup
- EntityHeader / TransactionHeader
- Timeline / ActivityFeed / AuditTimeline
- FinancialSummary / InventorySummary / ApprovalPanel
- BulkActionBar / CommandBar
- progress/accessibility contract including projected-value `aria-valuetext` where needed
- file/proof upload, camera and GPS interaction grammar
- toast/alert/inline-validation convergence
- Skeleton/Loading/Empty/Error/Permission/Offline/Sync state grammar, including neutral permission-limited microcopy
- chart/report legend/metric grammar

### C. Inventory

#### DS2-INV-001 — Inventory list surfaces
`BACKLOG`
Warehouses / stock / movements / valuation list grammar.

#### DS2-INV-002 — Transfer/adjustment operational flows
`BACKLOG`
Mobile-first transaction forms/actions while preserving inventory semantics.

### D. Procurement

#### DS2-PROC-001 — Purchase list surfaces
`BACKLOG`
Invoices/returns responsive grammar.

#### DS2-PROC-002 — Purchase Invoice form decomposition
`BACKLOG`
Large form presentation decomposition only; business behavior preserved.

### E. Finance

#### DS2-FIN-001 — Finance lists and summaries
`BACKLOG`
Vault/custody/payment/expense/account/journal/ledger visual grammar.

#### DS2-FIN-002 — Financial transaction/detail/action patterns
`BACKLOG`
High-trust money/status/confirmation hierarchy.

### F. HR / People

#### DS2-HR-001 — Mobile operational tasks
`BACKLOG`
Attendance/check-in as reference for OperationalTaskScreen / progress / connectivity / GPS grammar.

#### DS2-HR-002 — HR admin lists/forms
`BACKLOG`
Employees, attendance, leave, advances and payroll-related presentation.

### G. Field Activities / Targets

#### DS2-FIELD-001 — Activities/visit/call/target lists
`BACKLOG`
Mobile-first field operations, GPS/phone/action priority.

#### DS2-FIELD-002 — Field create/detail flows
`BACKLOG`
Shared operational forms/timelines/actions.

### H. Work Management

#### DS2-WORK-001 — Reconcile Work UI island with V2
`BACKLOG`
Preserve its strong responsive architecture while replacing standalone visual language with shared V2 grammar.

### I. Reports / Analytics

#### DS2-REPORT-001 — Report shell/navigation/filter grammar
`BACKLOG`

#### DS2-REPORT-002 — Metrics/charts/tables and responsive report composition
`BACKLOG`

### J. Settings / Administration

#### DS2-ADMIN-001 — Users/roles/settings/audit surfaces
`BACKLOG`
Includes PermissionMatrix pattern and touch/accessibility behavior.

### K. Global convergence and cleanup

#### DS2-GLOBAL-001 — Global style debt and inline-style reduction
`BACKLOG`
Only after shared patterns are proven.

#### DS2-GLOBAL-002 — Dark mode / RTL / long Arabic / numeric stress pass
`BACKLOG`

#### DS2-GLOBAL-003 — Accessibility/focus/touch/motion pass
`BACKLOG`

#### DS2-GLOBAL-004 — Legacy component/CSS retirement
`BACKLOG`
Repository search must prove no remaining consumers.

#### DS2-GLOBAL-005 — Final visual/system consistency audit
`BACKLOG`
Verify all major modules read as one product and satisfy North Star completion definition.

## Integrator development gate

Before merge:
- exact current PR HEAD has `AGENT-REVIEW: GREEN-DEV`
- reviewer records `SOURCE_REVIEW_PASS` and honest test evidence
- no known build/type failure
- no unresolved material blocker or current `BLOCKING` role-state contradiction
- PR base is `design-system-v2-development`
- diff contains no forbidden backend/business/query/permission/deployment change

After merge:
- completed slice becomes DONE with reviewed/merge SHA and evidence
- exactly one next dependency-safe roadmap item becomes READY
- Integration State and Team Memory are synchronized
- no preview deployment
- no merge to `main`

## Preview rule

Preview is created only when the user explicitly asks to see the current version, from a frozen development baseline using a dedicated preview branch. Preview-only switches/deployment configuration never merge back into development.

## End condition

The autonomous workstream continues until the North Star completion definition is met across the major modules, shared component grammar, device behavior, RTL/dark/state/accessibility convergence and final controlled runtime review.
