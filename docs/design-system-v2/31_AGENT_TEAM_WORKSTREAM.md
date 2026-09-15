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

Product UI is integrated through `DS2-UI-002`.

Latest product integration:
- PR: `#29 — DS2-UI-002: migrate customer secondary surfaces to shared V2 patterns`
- Exact reviewed PR HEAD: `1cb3853bf3cf94b2a25edd637d0083006e5d2191`
- Squash merge commit: `773085994502401a7368eded20926b1308b62e3f`
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

## Current single READY slice

### DS2-UI-003 — Sales Orders list V2
Status: `READY`
Owner role: UI Production Engineer

System intent:
Move the next golden-flow collection screen into the shared V2 grammar while proving reusable list/filter/status/action patterns for later modules.

Scope direction:
- Sales Orders list presentation only
- responsive collection/table-card behavior using existing shared patterns before inventing new ones
- filter/search/status/action hierarchy
- loading/empty/error/permission states already present in the page contract
- deliberate Mobile/Tablet/Desktop composition
- Arabic/RTL and long-value tolerance

Must preserve:
- existing data retrieval/query semantics
- pagination/infinite-loading behavior already owned by the page/service contract
- route/navigation destinations
- permission visibility
- status values/mapping and business meaning
- all sales/order calculations and workflow transitions

Explicit exclusions:
- no service/query/cache changes
- no sales business-state or pricing changes
- no order-form work
- no transaction-detail redesign
- no speculative global DataTable/FilterBar rewrite unless the real Sales Orders list proves the smallest reusable shared contract needed for this slice
- no overlay/deployment/workflow changes

Acceptance direction:
- solution uses or minimally strengthens shared V2 patterns rather than creating a Sales-only mini design system
- Mobile exposes clear primary record/action hierarchy without ordinary horizontal overflow
- Tablet is intentionally composed, not compressed Desktop
- Desktop preserves efficient comparison density
- filters/status/action hierarchy is predictable and semantic
- relevant focused tests are authored for behavior/composition at risk
- no backend/business/query/permission semantics change
- evidence follows `33_TEST_AND_VALIDATION_POLICY.md`

## Product migration roadmap

The Product Design Director may further decompose a roadmap item, but only one dependency-safe implementation slice becomes READY at a time.

### A. Golden flows

#### DS2-UI-003 — Sales Orders list V2
`READY`
- responsive collection
- filters/status/action hierarchy
- preserve data/navigation/permissions

#### DS2-UI-004 — Sales Order form V2 foundation
`BACKLOG`
- presentation decomposition into shared Field/Combobox/FormSection/Stepper/ProductLine patterns
- small sub-slices; no pricing/customer/product business-logic migration

#### DS2-UI-005 — Sales transaction detail V2
`BACKLOG`
- TransactionHeader / status / FinancialSummary / action hierarchy

### B. Shared component-depth program

Open only when a real migrated screen proves the recurring gap:
- FilterBar decomposition and Mobile filter-sheet contract
- DataTable V2 hardening and table action/accessibility/overflow-region contract
- MobileDataCard semantic migration from legacy DataCard
- Modal/ResponsiveSheet/ConfirmDialog V2 convergence
- Combobox/AsyncCombobox keyboard/focus hardening
- Tabs/SubNav/SegmentedControl adoption cleanup
- EntityHeader / TransactionHeader
- Timeline / ActivityFeed / AuditTimeline
- FinancialSummary / InventorySummary / ApprovalPanel
- BulkActionBar / CommandBar
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