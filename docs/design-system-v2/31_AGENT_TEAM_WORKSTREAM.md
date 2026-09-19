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

Product UI is integrated through `DS2-REPORT-006`.

Latest product integration:
- PR: `#53 — DS2-REPORT-006: converge Product Performance details`
- Exact reviewed PR HEAD: `dafd5d36f2b360b1fd93b60d6573b4b717aec635`
- Squash merge commit: `ffda5aeb23684ea981c341761d1dde2cef7c3283`
- Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
- Product Design: `PASS — NO DESIGN-SYSTEM BLOCKER` on the same exact HEAD
- Runtime/preview/release evidence: not claimed

The development branch includes semantic foundations, responsive shell/navigation/form/collection/action patterns, Dashboard V2, Customers migrations, Sales list/form/detail foundations, Inventory list/transfer migrations, Procurement list/form-shell migrations, Finance overview/detail foundations, HR operational-task/admin collection proofs, Field Activities list/create-edit proofs, Work create-task form convergence, Work Hub shared view-mode selector convergence, Supervisor Work shared KPI summary convergence, Reports shared route-level sub-navigation convergence, Reports shared date-preset selector convergence with hardened `SegmentedControl` geometry, Reports shared native `DateField` convergence for the custom date pair, Reports Overview primary KPI-summary layout convergence onto shared `MetricGrid` while preserving report-domain `MetricCard` trust/freshness semantics, shared domain-agnostic `ChartPanel` proven on the primary Sales revenue chart, and Product Performance responsive detail-collection convergence using shared `ResponsiveCollection + Card + KeyValueList` while preserving the dense Desktop table.

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

### DS2-REPORT-001 — Report route sub-navigation convergence
Status: `DONE`
Merged PR: `#48`
Reviewed HEAD: `02f5d4f381d3999a9a3cda7ce8fbe0fc394926ba`
Squash merge: `5d2c57d9a502a4bbb2d355d94634bcf8b53075d2`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Product Design: `PASS — NO DESIGN-SYSTEM BLOCKER`
Runtime/preview/release evidence: not claimed

System result:
- common `ReportsLayout` route navigation uses shared V2 `SubNav`;
- all 14 destinations/order/Arabic labels/icons/permission arrays remain unchanged;
- eligibility, `AnalyticsGate`, routing, filters, queries, calculations and export/print remain domain-owned.

### DS2-REPORT-002 — Report date-preset selector convergence
Status: `DONE`
Merged PR: `#49`
Reviewed HEAD: `3e0f11d52de77f07953dd2a226c82ff19ec2f75f`
Squash merge: `cc91792263d9fc606b9c2f28a531daa826997c75`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Product Design: `PASS — NO DESIGN-SYSTEM BLOCKER`
Runtime/preview/release evidence: not claimed

System result:
- four report date presets use shared V2 `SegmentedControl` inside domain-local `ReportFilterBar`;
- preset labels/order/range outputs and all date/query/business semantics remain unchanged;
- default/non-block segmented items retain intrinsic width while block mode and Mobile containment remain shared-layer contracts.

### DS2-REPORT-003 — Report custom-date field convergence
Status: `DONE`
Merged PR: `#50`
Reviewed HEAD: `4b81eee69d4a8722333db165041e481fa80f24fe`
Squash merge: `cec34dcdc2fec5ac7b3cd4821d942f224f9f52f2`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Product Design: `PASS — NO DESIGN-SYSTEM BLOCKER`
Runtime/preview/release evidence: not claimed

System result:
- shared V2 `DateField` composes `Input -> Field` and owns native date-input presentation/accessibility only;
- only the two custom date editors in `ReportFilterBar` migrated;
- range normalization, local-date/preset/query/business semantics remain caller-owned.

### DS2-REPORT-004 — Reports Overview summary metric-grid convergence
Status: `DONE`
Merged PR: `#51`
Reviewed HEAD: `0dad8a5eb73e1a4fac73475dda5a247182db2e51`
Squash merge: `38b53912c1b3ff8c933ec0d5cfc9d3dc69488f85`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Product Design: `PASS — NO DESIGN-SYSTEM BLOCKER`
Runtime/preview/release evidence: not claimed

System result:
- only the primary Reports Overview KPI wrapper migrated to shared `MetricGrid columns={4}`;
- report-domain `MetricCard` retains trust/freshness/status semantics;
- all values, formatting, loading and report business/query semantics remain unchanged.

### DS2-REPORT-005 — Shared ChartPanel foundation + Sales primary revenue-chart migration
Status: `DONE`
Merged PR: `#52`
Reviewed HEAD: `eec9f05772babd40be61803b39d90bd9b859b28d`
Squash merge: `3776e7defc83a1376a571dd38256c6a7bbf87e17`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Product Design: `PASS — NO DESIGN-SYSTEM BLOCKER`
Runtime/preview/release evidence: not claimed

System result:
- shared V2 `ChartPanel` provides a thin domain-agnostic analytical surface over `Card + SectionHeader`;
- default semantic heading is `h2`, with explicit `2 | 3 | 4` override for genuine nesting;
- only SalesPage's first chart migrated; Recharts/trust/state/query/business semantics remain caller-owned.

### DS2-REPORT-006 — Product Performance responsive detail-collection convergence
Status: `DONE`
Merged PR: `#53`
Reviewed HEAD: `dafd5d36f2b360b1fd93b60d6573b4b717aec635`
Squash merge: `ffda5aeb23684ea981c341761d1dde2cef7c3283`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Product Design: `PASS — NO DESIGN-SYSTEM BLOCKER`
Runtime/preview/release evidence: not claimed

System result:
- only `ProductPerformancePage` section `تفاصيل المنتجات — أعلى 50 حسب الإيراد` migrated to shared `ResponsiveCollection<ProductPerformanceRow>`;
- Desktop preserves the semantic seven-column table and now uses `scope="col"` on touched headers;
- Tablet/Mobile use existing V2 `Card + KeyValueList` detail composition, with only one device renderer mounted at a time;
- all seven source fields, row source/order/top-50 contract, formatting/units, return-rate thresholds/colors, five-row loading skeleton and exact `لا توجد بيانات` remain preserved;
- chart/KPI/filter/category/header and all query/cache/service/calculation/trust/permission/routing/`AnalyticsGate`/export/print/business semantics remain caller/domain-owned and unchanged.

## Current single READY slice

### DS2-REPORT-007 — Next bounded Reports metrics/charts/tables/responsive-composition convergence
Status: `READY`
Owner role for next action: Product Design Director
Dependency baseline: exact integrated product HEAD `ffda5aeb23684ea981c341761d1dde2cef7c3283`.

System-pattern intent:
- inspect representative remaining Reports/Analytics surfaces on the exact latest Development baseline;
- select exactly one smallest dependency-safe presentation-only concern and name its representative file/surface plus explicit acceptance boundary before implementation;
- prefer reuse of existing shared V2 primitives/patterns and strengthen a shared contract only when a real consumer proves the need;
- preserve REPORT001-006 contracts and all report query/cache/service/calculation/trust/permission/routing/`AnalyticsGate`/export/print/business truth;
- preserve Settings/Admin, Global convergence, remaining Work and Field debt, and shared component-depth work in the roadmap;
- do not turn REPORT007 into a broad Reports beautification pass.

Implementation is not authorized until Product Design records the exact bounded concern from the then-current Development HEAD.

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
- `DS2-FIN-001` Finance lists and summaries — `DONE`
- `DS2-FIN-002` Payment Receipt transaction-detail header/action foundation — `DONE`

### F. HR / People
- `DS2-HR-001` Attendance Check-in operational task controls — `DONE`
- `DS2-HR-002` HR admin lists/forms — `DONE`

### G. Field Activities / Targets
- `DS2-FIELD-001` Activities/visit/call/target lists — `DONE`
- `DS2-FIELD-002` Activity create/edit form composition foundation — `DONE`
- additional Field create/detail convergence — `BACKLOG` / must be explicitly bounded before activation

### H. Work Management
- `DS2-WORK-001` Create Task form composition foundation — `DONE`
- `DS2-WORK-002` Work Hub view-mode selector convergence — `DONE` / PR #46 / merge `add39ea8ee76b61d9a5a5938aa6cd03e2cc13456`
- `DS2-WORK-003` Supervisor operational summary metric convergence — `DONE` / PR #47 / merge `95a84a8109f45cf9ac32c92d5d950f64d38dbaa0`
- further Work detail/feedback/management convergence beyond WORK003 — `BACKLOG` / explicitly bounded only

### I. Reports / Analytics
- `DS2-REPORT-001` Report route sub-navigation convergence — `DONE` / PR #48 / merge `5d2c57d9a502a4bbb2d355d94634bcf8b53075d2`
- `DS2-REPORT-002` Report date-preset selector convergence — `DONE` / PR #49 / merge `cc91792263d9fc606b9c2f28a531daa826997c75`
- `DS2-REPORT-003` Report custom-date field convergence — `DONE` / PR #50 / merge `cec34dcdc2fec5ac7b3cd4821d942f224f9f52f2`
- `DS2-REPORT-004` Reports Overview summary metric-grid convergence — `DONE` / PR #51 / merge `38b53912c1b3ff8c933ec0d5cfc9d3dc69488f85`
- `DS2-REPORT-005` Shared ChartPanel foundation + Sales primary revenue-chart migration — `DONE` / PR #52 / merge `3776e7defc83a1376a571dd38256c6a7bbf87e17`
- `DS2-REPORT-006` Product Performance responsive detail-collection convergence — `DONE` / PR #53 / merge `ffda5aeb23684ea981c341761d1dde2cef7c3283`
- `DS2-REPORT-007` Next bounded Reports metrics/charts/tables/responsive-composition convergence — `READY` / Product Design must bound exactly one concern before implementation
- further Reports/Analytics convergence beyond REPORT007 — `BACKLOG` / each concern must be bounded separately

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
