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

Before material action every role reads Team Memory, all four role states, the Decision Log, this workstream, issue #27, and the active PR. Each role owns only its own state file. Integrator updates Team Memory after successful merge. Issue #27 is a concise event stream.

## GitHub Actions / preview policy

Hosted GitHub Actions remain forbidden while quota protection is active. Focused tests are still authored. Normal development evidence is exact-head `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + an honest execution label. A known real build/type failure blocks integration.

Vercel preview remains owner-requested only. Scheduled agents never merge to `main`.

## Current integrated baseline

Product UI is integrated through `DS2-UI-004`.

Latest product integration:
- PR: `#31 — DS2-UI-004: establish Sales Order form V2 presentation foundation`
- Exact reviewed PR HEAD: `198f146a3abde9efa6bfb3c98c20469f3815d3ff`
- Squash merge commit: `d00faf8e36d40c9dde9df0b2de6dc89737419c5d`
- Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
- Runtime/preview/release evidence: not claimed

The development branch now includes the shared semantic foundations, responsive shell/navigation/form/collection patterns, Dashboard V2, Customers migrations, Sales Orders list V2, and the first Sales Order form V2 foundation.

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
- Sales KPI/status/card/action/state presentation composes shared V2 grammar.
- Sales query/filter/pagination/navigation/permission/payment/Smart Transfer/map/call/business semantics remain preserved.

### DS2-UI-004 — Sales Order form V2 foundation
Status: `DONE`
Merged PR: `#31`
Reviewed HEAD: `198f146a3abde9efa6bfb3c98c20469f3815d3ff`
Squash merge: `d00faf8e36d40c9dde9df0b2de6dc89737419c5d`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Runtime/preview/release evidence: not claimed

System result:
- shared `Stepper` now supports optional page-owned guarded interaction while preserving legacy read-only behavior by default;
- Sales step navigation is a thin adapter over shared Stepper, not a parallel primitive;
- exact legacy step reachability and `goNext` validation remain page-owned;
- Step 0 composes shared `FormSection` + `FormGrid` with the corrected `3 Desktop / 2 Tablet / 1 Mobile` density contract;
- customer and credit-context rows remain intentionally full-width;
- bottom actions compose shared `FormActions` + `Button` with RTL-native cues;
- create/edit/copyFrom, customer/branch/rep, product/unit/stock, pricing/discount/tax/total/minimum-order, permissions, validation, save sequence, routes, and Mobile add-product flow remain unchanged;
- Combobox/ProductLine redesign remains deferred until separately proven by a live slice.

## Current single READY slice

### DS2-UI-005 — Sales transaction detail V2
Status: `READY`
Owner role: UI Production Engineer

System intent:
Migrate the Sales transaction-detail surface toward the shared V2 detail grammar while preserving all Sales business truth.

Initial direction:
- inspect the current detail screen and select the smallest dependency-safe presentation-only sub-slice;
- prefer shared `TransactionHeader`, status, `FinancialSummary`, `KeyValueList`, action hierarchy, timeline/state patterns when already available or when the live screen proves the smallest reusable gap;
- preserve every displayed business value, permission, workflow action, route, query and state transition;
- deliberately compose Mobile/Tablet/Desktop rather than shrinking Desktop;
- keep Arabic/RTL, long values, loading/error/permission states and destructive-action hierarchy explicit.

Explicit exclusions:
- no service/query/cache/RPC changes;
- no RBAC/RLS/permission or workflow semantic changes;
- no pricing/accounting calculation migration into visual primitives;
- no speculative shared-detail framework beyond the smallest recurring contract proven by the live screen;
- no deployment/preview/main changes.

Acceptance direction:
- one bounded detail-composition concern per implementation PR;
- shared V2 grammar owns presentation while page/domain code retains business truth;
- Mobile has clear primary/secondary/destructive action priority;
- Tablet is deliberate;
- Desktop preserves management/review density;
- focused tests are authored for material composition/behavior risk;
- evidence follows `33_TEST_AND_VALIDATION_POLICY.md`.

## Product migration roadmap

The Product Design Director may decompose an item further, but exactly one dependency-safe implementation slice becomes READY at a time.

### A. Golden flows
- `DS2-UI-001` Customer Form basic-info — `DONE`
- `DS2-UI-002` Customer detail secondary tabs/patterns — `DONE`
- `DS2-UI-003` Sales Orders list V2 — `DONE`
- `DS2-UI-004` Sales Order form V2 foundation — `DONE`
- `DS2-UI-005` Sales transaction detail V2 — `READY`

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
- `DS2-INV-001` Inventory list surfaces — `BACKLOG`
- `DS2-INV-002` Transfer/adjustment operational flows — `BACKLOG`

### D. Procurement
- `DS2-PROC-001` Purchase list surfaces — `BACKLOG`
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
