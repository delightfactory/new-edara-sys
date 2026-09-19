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

Product UI is integrated through `DS2-REPORT-008`.

Latest product integration:
- PR: `#55 — DS2-REPORT-008: converge Receivables AR chart panel`
- Exact reviewed PR HEAD: `3248057b52188d821f6e87f7b4624a8c14f00c3d`
- Squash merge commit: `cdacc180e1e163b6dcb3d16cb80ff0beee1e701f`
- Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
- Product Design: `PASS — NO DESIGN-SYSTEM BLOCKER` on the same exact HEAD
- Runtime/preview/release evidence: not claimed

The development branch includes semantic foundations, responsive shell/navigation/form/collection/action patterns, Dashboard V2, Customers migrations, Sales list/form/detail foundations, Inventory list/transfer migrations, Procurement list/form-shell migrations, Finance overview/detail foundations, HR operational-task/admin collection proofs, Field Activities list/create-edit proofs, Work create-task form convergence, Work Hub shared view-mode selector convergence, Supervisor Work shared KPI summary convergence, Reports shared route-level sub-navigation convergence, Reports shared date-preset selector convergence with hardened `SegmentedControl` geometry, Reports shared native `DateField` convergence for the custom date pair, Reports Overview primary KPI-summary layout convergence onto shared `MetricGrid` while preserving report-domain `MetricCard` trust/freshness semantics, shared domain-agnostic `ChartPanel` proven on Sales and Receivables, Product Performance responsive detail-collection convergence using shared `ResponsiveCollection + Card + KeyValueList` while preserving the dense Desktop table, and Geography analysis-level control convergence onto shared `Select -> Field` while retaining report-domain state/filter ownership.

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
- `DS2-REPORT-001 — Report route sub-navigation convergence` — `DONE` — PR #48 — merge `5d2c57d9a502a4bbb2d355d94634bcf8b53075d2` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-002 — Report date-preset selector convergence` — `DONE` — PR #49 — merge `cc91792263d9fc606b9c2f28a531daa826997c75` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-003 — Report custom-date field convergence` — `DONE` — PR #50 — merge `cec34dcdc2fec5ac7b3cd4821d942f224f9f52f2` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-004 — Reports Overview summary metric-grid convergence` — `DONE` — PR #51 — merge `38b53912c1b3ff8c933ec0d5cfc9d3dc69488f85` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-005 — Shared ChartPanel foundation + Sales primary revenue-chart migration` — `DONE` — PR #52 — merge `3776e7defc83a1376a571dd38256c6a7bbf87e17` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-006 — Product Performance responsive detail-collection convergence` — `DONE` — PR #53 — merge `ffda5aeb23684ea981c341761d1dde2cef7c3283` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-007 — Geography analysis-level selector convergence` — `DONE` — PR #54 — merge `9ab20b3ca467b1d42eae0fb9fd6936d156e11662` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-008 — Receivables AR chart-panel convergence` — `DONE` — PR #55 — reviewed HEAD `3248057b52188d821f6e87f7b4624a8c14f00c3d` — merge `cdacc180e1e163b6dcb3d16cb80ff0beee1e701f` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.

### REPORT008 system result

- only the Receivables chart section `تحصيلات AR مجمّعة بتاريخ البيع الأصلي` moved from a page-local analytical shell to existing shared V2 `ChartPanel`;
- exact Arabic title/description, `TrustStateBadge + FreshnessIndicator` sources/content, blocked/loading/empty/data branches and the 260px body contract remain unchanged;
- chart-data mapping, Recharts axes/grid/tooltip/margins/formatters and all three series contracts remain caller-owned and unchanged;
- no shared `ChartPanel` API/CSS widening, second chart/report, backend/business/query/permission/routing/export/print or deployment/workflow change entered the slice.

## Current single READY slice

### DS2-REPORT-009 — Sales secondary revenue/tax chart-panel convergence
Status: `READY`
Owner role for immediate next action: UI Production Engineer
Selection baseline: exact Development HEAD `e893339de9c43b9b3a3006a743a100dcb09ea0e7`.
Representative surface: `src/pages/reports/SalesPage.tsx` → second chart section `توزيع الإيرادات اليومي (إيراد + ضريبة)` only.

System-pattern intent:
- retire the remaining page-local analytical card/header shell on the second Sales chart by composing it through the already-proven shared V2 `ChartPanel`;
- keep `ChartPanel` presentation-only and do not widen its API/CSS contract;
- create one coherent analytical hierarchy on the Sales report without altering chart/report truth.

Acceptance boundary:
- replace only the second chart's local outer surface/title shell with `ChartPanel`;
- preserve the exact Arabic title `توزيع الإيرادات اليومي (إيراد + ضريبة)`;
- do not invent a description, trust/freshness action or new report semantics for this panel;
- preserve the current branch exactly: `dailyLoading ? <SkeletonCard height={200} /> : <ResponsiveContainer ... height={200}>`;
- preserve the current absence of additional blocked/empty gating on this second chart; adding such semantics is not part of this presentation slice;
- preserve `chartData`, `BarChart` margin `{ top: 4, left: -10, right: 4, bottom: 0 }`, grid, axes, tick formatting, `CustomTooltip`, and both Bars unchanged: `revenue / الإيراد / #2563eb` and `tax / الضريبة / #0284c7`, each `radius={[3,3,0,0]}` and `maxBarSize={24}`;
- preserve the first `ChartPanel` (`تطور الإيراد اليومي`), all four `MetricCard`s, `ReportFilterBar`, `SystemHealthBar`, hooks, range/filter state, trust calculations, `chartData` mapping and all query/cache/service/permission/routing/`AnalyticsGate`/export/print/business semantics;
- focused tests should update `SalesPage.test.tsx` to prove both analytical sections use shared `ChartPanel`, the second panel has semantic `h2` with the exact title, the first panel's existing title/description/trust/blocked/empty contracts remain intact, and the second chart's 200px/two-series configuration remains unchanged.

Device/state/accessibility acceptance:
- **Desktop:** preserve compact report density and 200px comparison-chart body; no decorative height inflation;
- **Tablet:** shared panel/header must fit deliberately without introducing fixed-width pressure or ordinary horizontal overflow;
- **Mobile:** title must wrap safely in the shared panel, chart containment remains `min-width: 0`, and no duplicate interaction/render tree is introduced;
- **RTL / Arabic:** exact Arabic title is retained and shared logical layout/tokens own the surface;
- **Dark mode:** surface/border/title styling must come through the existing V2 semantic-token path;
- **Accessibility:** page hierarchy remains `h1 -> h2`; this chart introduces no new interactive control, so focus/touch behavior must not be fabricated;
- evidence remains source/test-artifact based unless an approved execution environment actually runs tests.

Explicit exclusions:
- no change to the first Sales chart beyond tests needed to prove it remains unchanged;
- no `ChartPanel` API/CSS redesign, no shared chart/recharts abstraction, no new legend/tooltip primitive;
- no MetricCard/report-grid/filter/header/system-health cleanup;
- no new trust/freshness/blocked/empty semantics for the second chart;
- no second page/report and no backend/business/query/calculation/permission/routing/export/print/deployment/workflow change.

Escalation rule: if the existing `ChartPanel` contract proves materially insufficient, if exact current Sales semantics cannot be preserved, or if completing the slice would require new trust/business behavior, mark REPORT009 `BLOCKED` and return to Product Design rather than widening the PR.

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
- `DS2-REPORT-007` Geography analysis-level selector convergence — `DONE` / PR #54 / merge `9ab20b3ca467b1d42eae0fb9fd6936d156e11662`
- `DS2-REPORT-008` Receivables AR chart-panel convergence — `DONE` / PR #55 / merge `cdacc180e1e163b6dcb3d16cb80ff0beee1e701f`
- `DS2-REPORT-009` Sales secondary revenue/tax chart-panel convergence — `READY` / bounded to the second Sales chart only
- further Reports/Analytics convergence beyond REPORT009 — `BACKLOG` / each concern must be bounded separately

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