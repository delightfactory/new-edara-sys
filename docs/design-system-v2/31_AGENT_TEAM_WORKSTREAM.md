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

Hosted GitHub Actions remain forbidden while quota protection is active. Focused tests are still authored. Normal development evidence is exact-head `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + an honest execution label. A known build/type failure blocks integration.

Vercel preview remains owner-requested only. Scheduled agents never merge to `main`.

## Current integrated baseline

Product UI is integrated through `DS2-REPORT-043`.

Latest product integration:
- PR: `#91 — DS2-REPORT-043: converge Treasury semantic notice on AlertPanel`
- Exact reviewed PR HEAD: `932457d5cf34c0eaa17404614f697bc5cf100eb3`
- Squash merge commit: `c9e28bd2b98bbf65d4d916e114cebb6cdcb86bf4`
- Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
- Product Design exact-head closeout: `PASS — NO DESIGN-SYSTEM BLOCKER`
- Runtime/preview/release evidence: not claimed

The development branch includes semantic foundations, responsive shell/navigation/form/collection/action patterns, Dashboard V2, representative Customers/Sales/Inventory/Procurement/Finance/HR/Field/Work migrations, Reports route/date/filter convergence, shared `ChartPanel`, shared `MetricGrid`, shared `StatePanel`, shared `AlertPanel`, shared V2 `Field` controls in representative report headers, and responsive detail-collection proofs using `ResponsiveCollection + Card + KeyValueList` while preserving dense Desktop comparison and caller-owned business truth.

## Completed slices

- `DS2-UI-001 — Customer Form: basic-info composition` — `DONE` — PR #28 — merge `cdcc1a57cc3367fdd161fddb3d9e5b42e92e4829` — `SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-UI-002 — Customer detail secondary tabs/patterns` — `DONE` — PR #29 — merge `773085994502401a7368eded20926b1308b62e3f` — `SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-UI-003 — Sales Orders list V2` — `DONE` — PR #30 — merge `e42910fb2bb7c945e67262f610d9e0b630d960a6` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-UI-004 — Sales Order form V2 foundation` — `DONE` — PR #31 — merge `d00faf8e36d40c9dde9df0b2de6dc89737419c5d` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-UI-005 — Sales transaction detail V2` — `DONE` — PR #32 — merge `58b0f3f8f54f04636d3a35dd7d658edb7bcf5068` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-INV-001 — Inventory list surfaces` — `DONE` — PR #34 — merge `805995a5c0d9a118c415d647ed34e63dee326527` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-INV-002 — Transfer/adjustment operational flows` — `DONE` — PR #35 — merge `9328464542b1ca429fd1ec134667f45244215b67` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-PROC-001 — Purchase list surfaces` — `DONE` — PR #36 — merge `936129c69a51237ceeefc7880d9735aa5f584879` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-PROC-002 — Purchase Invoice form decomposition` — `DONE` — PR #37 — merge `5b10b9fb578c91798d28526d8de407f63ffcc417` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-FIN-001 — Finance lists and summaries` — `DONE` — PR #38 — merge `7a70beccaf961b248f0df045f6bf610df4dfdc84` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-FIN-002 — Payment Receipt transaction-detail header/action foundation` — `DONE` — PR #39 — merge `1a9509d598b9b462397838db7adc261c4746c52f` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-HR-001 — Attendance Check-in operational task controls` — `DONE` — PR #40 — merge `e9a37c6ade6661bdaf6260f9c93c72dabba60768` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-HR-002 — HR admin lists/forms — Employees administration list` — `DONE` — PR #41 — merge `b1c9ae6dd78b57f9708e3e5d40fe0b2baac6adbc` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-FIELD-001 — Activities/visit/call/target lists — Activities list` — `DONE` — PR #42 — merge `cac61006d5c6ac402a509c2f15fb09ce51bafd50` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-FIELD-002 — Activity create/edit form composition foundation` — `DONE` — PR #43 — merge `2492fa475e7bc5beb9148124f31a4b4837057c19` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-WORK-001 — Create Task form composition foundation` — `DONE` — PR #44 — merge `57747123643d0dd846cbda3ef340e9463a5f7647` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-WORK-002 — Work Hub view-mode selector convergence` — `DONE` — PR #46 — merge `add39ea8ee76b61d9a5a5938aa6cd03e2cc13456` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-WORK-003 — Supervisor operational summary metric convergence` — `DONE` — PR #47 — merge `95a84a8109f45cf9ac32c92d5d950f64d38dbaa0` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-001` through `DS2-REPORT-025` — `DONE`; detailed reviewed/merge SHA evidence remains preserved in Git history and prior workstream revisions.
- `DS2-REPORT-026 — Product Performance summary metric-grid convergence` — `DONE` — PR #74 — reviewed HEAD `f3b2386130924ee375f1912190a6ad82befe0065` — merge `9ac63ca20baaeefa6fe5cb3e87a9734f59847ac5` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-027 — Churn Risk filter-control field convergence` — `DONE` — PR #75 — reviewed HEAD `2beb65da6a2b46f3e1bf831471c55b9a5bbf8f5a` — merge `d9a1fb373142cac8c9f7f1b7545d340f99298f8a` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-028 — Profit Dashboard summary metric-grid convergence` — `DONE` — PR #76 — reviewed HEAD `cd7ac87d0839a7e7706858afb4efbdea2025ff8e` — merge `337cf967ab1159968866811be194aec359c43f66` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-029 — Geography summary metric-grid convergence` — `DONE` — PR #77 — reviewed HEAD `8c955d7d4507150d0d4bfaaa6bfe652166268797` — merge `523f547a4259043d33ee77afc5139ffe42c1354e` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-030 — Rep Performance summary metric-grid convergence` — `DONE` — PR #78 — reviewed HEAD `0a2b828d3896b561adbcc6dc495c086b4d14f1d3` — merge `b5f3d49cbc2f68431573174ee2b653b269ee5d2c` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-031 — Customer Health as-of-date field convergence` — `DONE` — PR #79 — reviewed HEAD `acc79751b2e24903a7d63842eb5b962e2ab19d0b` — merge `7271801b22a58c4280c9bdbd82b37aa9de7a0fdc` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-032 — Customer Re-engagement KPI summary shared metric convergence` — `DONE` — PR #80 — reviewed HEAD `2177d3ca687434a0185a5787639ee2138148d341` — merge `e7088ed6d683b4cc714059cd7f3d07831f9485b5` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-033 — Target Attainment individual-rep chart-panel convergence` — `DONE` — PR #81 — reviewed HEAD `1d67d89e57c150542cea487e0cafc8d520d5c30a` — merge `464adbfe86f9ff1e53d288babb9715a010346b15` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-034 — Churn Risk KPI summary shared metric convergence` — `DONE` — PR #82 — reviewed HEAD `8bec856b57aff490092c68b948fdac52078c2bf2` — merge `7ba36015798df5d4aa615077adade862687a6f9c` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-035 — Product Performance shared empty-state convergence` — `DONE` — PR #83 — reviewed HEAD `1b9870cb92fe660a527ca4e521c42fd538bb5d30` — merge `8d1aa7e4db89b8dfee7d9ce8c536bb4c160a40fb` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-036 — Rep Performance shared empty-state convergence` — `DONE` — PR #84 — reviewed HEAD `3850c40095465528e317fcde675f427307e8e856` — merge `9c69d2103172c950dcdaf145bfade24e604b09fc` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-037 — Customer Health responsive-detail empty-state convergence` — `DONE` — PR #85 — reviewed HEAD `a20442ca930ef957bdf79a156145aeec2771f196` — merge `2af5917c0b370d1bd6aaa785ef248f6084e483d3` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-038 — Receivables chart empty-state convergence` — `DONE` — PR #86 — reviewed HEAD `1055c5bb2394177e0a6ea55c4651567bbfb119e2` — merge `5325d99fcc3d047f1fc6aa3dac39a5423d9376e4` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-039 — Geography responsive-detail empty-state convergence` — `DONE` — PR #87 — reviewed HEAD `2877257b3f04b84c01a058a47f82c2cd6e0ccb59` — merge `035558bb3e86026742d3658d7c1928ee75f09215` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-040 — Churn Risk responsive-detail empty-state convergence` — `DONE` — PR #88 — reviewed HEAD `1e916d2d7e7ec9618d1ae7f6294fdfe00f08c6a1` — merge `23707a5465549613dfbde0a6637acee5fbc847e2` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-041 — Sales revenue-chart empty-state convergence` — `DONE` — PR #89 — reviewed HEAD `1f3195250b9d6f964389090efc3acd8c7bdcc85a` — merge `b334b07e93b7551839772d6a5cbbdb53089df06b` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-042 — Sales revenue/tax bar-chart empty-state convergence` — `DONE` — PR #90 — reviewed HEAD `dbabddc56743f2d448bbefbab4998b6f0b98e9bb` — merge `f7479859fe5c3233c3082bad2e97c0a004213f4c` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-043 — Treasury semantic-contract notice AlertPanel convergence` — `DONE` — PR #91 — reviewed HEAD `932457d5cf34c0eaa17404614f697bc5cf100eb3` — merge `c9e28bd2b98bbf65d4d916e114cebb6cdcb86bf4` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.

## REPORT043 system result

- Treasury's static semantic-contract notice now uses the existing shared `AlertPanel tone="info"` instead of a page-local rgba/border/padding/emoji information surface.
- The notice remains in the exact same hierarchy position immediately after the page header/filter area and before `SystemHealthBar`.
- Disclosure meaning and exact technical literals remain unchanged: `مطابق لسجلات الخزينة`, `vault_transactions / custody_transactions`, and `net_cashflow`, with technical literals preserved as inline `<code>`.
- The notice remains passive and static: no `announce`, action slot, click target, explicit focus target or live-region behavior was introduced; the shared default icon remains decorative/aria-hidden.
- Treasury chart precedence `isBlocked -> dailyLoading -> empty -> ready`, 280px analytical geometry, blocked/empty/ready renderers, Recharts contract, Trust/Freshness action area, KPI `MetricGrid` / `MetricCard`, filters and `SystemHealthBar` remain unchanged.
- No shared `AlertPanel` API/CSS/token/breakpoint widening and no query/cache/aggregation/calculation/trust/permission/RBAC/RLS/routing/export/print/backend/business/workflow behavior change occurred.
- Focused regression tests were authored but not executed under the hosted-CI quota policy.

## Current single READY slice

### DS2-REPORT-044 — Next bounded Reports metrics/charts/tables/responsive-composition convergence
Status: `READY — UNBOUNDED`.
Owner role for immediate next action: Product Design Director.

Intent:
- inspect representative remaining Reports/Analytics surfaces on the exact latest Development baseline before implementation;
- select exactly one smallest dependency-safe presentation-only concern and name its representative surface/file plus explicit acceptance/exclusion boundary;
- prefer existing shared V2 primitives/patterns, or strengthen a shared contract only when a real consumer demonstrates the need;
- preserve REPORT001-043 contracts and all analytics/query/calculation/trust/permission/RBAC/RLS/routing/export/print/backend/business semantics;
- preserve Settings/Admin, Global convergence, remaining Work and Field debt and shared component-depth work in the roadmap;
- do not turn REPORT044 into broad multi-page report beautification.

Implementation is not authorized until Product Design records the exact bounded concern from the then-current Development HEAD.

## Product migration roadmap

The Product Design Director may decompose an item further, but exactly one dependency-safe implementation slice becomes READY at a time.

### A. Golden flows
- `DS2-UI-001` through `DS2-UI-005` — `DONE`

### B. Shared component-depth program
Open only when a real migrated screen proves the recurring gap:
- PageHeader / ActionRegistry / ActionSlot completion
- SearchInput clear-button accessibility and Field/search convergence
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
- `DS2-INV-001` and `DS2-INV-002` — `DONE`

### D. Procurement
- `DS2-PROC-001` and `DS2-PROC-002` — `DONE`

### E. Finance
- `DS2-FIN-001` and `DS2-FIN-002` — `DONE`

### F. HR / People
- `DS2-HR-001` and `DS2-HR-002` — `DONE`

### G. Field Activities / Targets
- `DS2-FIELD-001` and `DS2-FIELD-002` — `DONE`
- additional Field create/detail convergence — `BACKLOG` / must be explicitly bounded before activation

### H. Work Management
- `DS2-WORK-001` through `DS2-WORK-003` — `DONE`
- further Work detail/feedback/management convergence beyond WORK003 — `BACKLOG` / explicitly bounded only

### I. Reports / Analytics
- `DS2-REPORT-001` through `DS2-REPORT-043` — `DONE`
- `DS2-REPORT-044 — Next bounded Reports metrics/charts/tables/responsive-composition convergence` — `READY — UNBOUNDED`
- further Reports/Analytics convergence beyond REPORT044 — `BACKLOG` / each concern must be bounded separately

### J. Settings / Administration
- `DS2-ADMIN-001` Users/roles/settings/audit surfaces — `BACKLOG`

### K. Global convergence and cleanup
- `DS2-GLOBAL-001` Global style debt and inline-style reduction — `BACKLOG`
- `DS2-GLOBAL-002` Dark mode / RTL / long Arabic / numeric stress pass — `BACKLOG`
- `DS2-GLOBAL-003` Accessibility/focus/touch/motion pass — `BACKLOG`
- `DS2-GLOBAL-004` Legacy component/CSS retirement — `BACKLOG`
- `DS2-GLOBAL-005` Final visual/system consistency audit — `BACKLOG`
