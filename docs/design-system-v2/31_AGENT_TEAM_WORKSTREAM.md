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

Product UI is integrated through `DS2-REPORT-017`.

Latest product integration:
- PR: `#65 — DS2-REPORT-017: converge Target Attainment responsive detail collection`
- Exact reviewed PR HEAD: `ccaaa6ede829f4d81017779c99cd76c1bf719918`
- Squash merge commit: `3474748541068600e1deae061bf68fca23b346ef`
- Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
- Product Design: `PASS — NO DESIGN-SYSTEM BLOCKER` on the same exact HEAD
- Runtime/preview/release evidence: not claimed

The development branch includes semantic foundations, responsive shell/navigation/form/collection/action patterns, Dashboard V2, Customers migrations, Sales list/form/detail foundations, Inventory list/transfer migrations, Procurement list/form-shell migrations, Finance overview/detail foundations, HR operational-task/admin collection proofs, Field Activities list/create-edit proofs, Work create-task form convergence, Work Hub shared view-mode selector convergence, Supervisor Work shared KPI summary convergence, Reports shared route-level sub-navigation convergence, Reports date-preset and native custom-date convergence, Reports Overview KPI-summary convergence, shared `ChartPanel` proofs across multiple analytical surfaces, and responsive detail-collection proofs across Product Performance, Customer Health, Churn Risk, Geography, Rep Performance and Target Attainment using `ResponsiveCollection + Card + KeyValueList` while preserving dense Desktop comparison.

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
- `DS2-REPORT-009 — Sales secondary revenue/tax chart-panel convergence` — `DONE` — PR #56 — reviewed HEAD `9f07979508c8139f579afbde0397672437eef992` — merge `5df49a61722daaeedd4c0b3f9434628b07f74c29` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-010 — Churn Risk pie-chart ChartPanel convergence` — `DONE` — PR #57 — reviewed HEAD `d5ac5becd8a9a64080022365407d60febaefe96e` — merge `5d6ee46bc716f6da39367c87e87608f30929c734` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-011 — Product Performance revenue chart-panel convergence` — `DONE` — PR #58 — reviewed HEAD `58927873f328172025f60da7c6b6d3fa3ecbcefa` — merge `9433ec1623a812d1b47d93bffad7e1c537caaa91` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-012 — Customer Health responsive detail-collection convergence` — `DONE` — PR #59 — reviewed HEAD `f92e25a4ad6afa0303235d8971c20e028fe8a9c5` — merge `7935e461e3c212eb187fe56bbb14ebe3e427f874` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-013 — Churn Risk responsive detail-collection convergence` — `DONE` — PR #61 — reviewed HEAD `eb6332a38c63935955c6057b3619cf86bfa284e8` — merge `a9c787f447780f72b7ac0a99b9b9ce0d1f636932` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-014 — Rep Performance comparison chart-panel convergence` — `DONE` — PR #62 — reviewed HEAD `6f77f2b5aab911c9fa18afd3c78268255456a0ad` — merge `a7096cdc86fb9fa55205556a10c8a5c13a6235d4` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-015 — Geography responsive detail-collection convergence` — `DONE` — PR #63 — reviewed HEAD `b3667bb27f1cc2a37805f7f2fef4a8276230cf59` — merge `fae25c2962f01aefc988b3e3ec8e0532e1c491f8` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-016 — Rep Performance responsive detail-collection convergence` — `DONE` — PR #64 — reviewed HEAD `d6f257c4060aa25a2c4ce46abe621fe76f031826` — merge `ce3db886a3eaaae15025998186cc62e1e841410e` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-017 — Target Attainment responsive detail-collection convergence` — `DONE` — PR #65 — reviewed HEAD `ccaaa6ede829f4d81017779c99cd76c1bf719918` — merge `3474748541068600e1deae061bf68fca23b346ef` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.

### REPORT017 system result

- Target Attainment `تفاصيل الأهداف` now uses the established `ResponsiveCollection + Card + KeyValueList` grammar for Tablet/Mobile while preserving caller-owned `TargetAttainmentRow[]` truth, fallbacks and ordering.
- Desktop keeps the dense semantic eight-column table, exact comparison order, hover behavior and achievement/trend presentation, with `scope="col"` headers.
- Tablet uses two-column and Mobile one-column passive shared card/key-value composition, with exactly one ready renderer mounted per device and no ordinary compact-device horizontal-table dependency.
- All eight facts remain unchanged: target, type, responsible, branch, target value, achieved value, achievement percentage and trend; responsible/branch fallbacks remain `—`.
- Achievement thresholds remain `>=100` success, `>=80` warning, otherwise danger; `TrendBadge` labels/colors and unknown fallback remain caller-owned and unchanged.
- Long Arabic target/type/responsible/branch values are wrap-safe; money/percentage values retain intentional LTR presentation inside RTL composition.
- Trust/Freshness and `BLOCKED/FAILED -> loading -> empty -> ready` precedence remain unchanged, including exact blocked/empty copy and five × 44px loading rows.
- Header/date/scope controls, KPI summary, individual-rep chart, hooks/queries/calculations, permissions, routing, export/print and all business semantics remain unchanged.
- No shared API/CSS/token widening occurred.

## Current single READY slice

### DS2-REPORT-018 — Treasury daily cashflow chart-panel convergence
Status: `READY`
Owner role for immediate next action: UI Production Engineer
Representative surface: `src/pages/reports/TreasuryPage.tsx` → `التدفق النقدي اليومي` chart section only.

System intent:
- converge the remaining page-local analytical Card/header shell onto the already-proven shared `ChartPanel` presentation contract;
- preserve Treasury data, trust/freshness, state precedence and chart semantics entirely in the caller;
- make the section hierarchy semantic (`h1` page → shared `h2` chart section) while retaining Arabic-first wrapping, RTL composition and responsive containment;
- prove the neutral shared chart-panel grammar on Treasury without widening shared APIs, CSS or tokens.

Acceptance boundary:
- replace only the local surface/header composition around `التدفق النقدي اليومي` with `ChartPanel`;
- preserve exact title `التدفق النقدي اليومي` and exact description `net_cashflow — مجمّع يومياً في قاعدة البيانات`;
- preserve the existing TrustStateBadge + FreshnessIndicator action cluster and allow it to wrap safely on compact widths;
- preserve state precedence and copy exactly: blocked/failed surface at `280px`, loading `SkeletonCard height={280}`, empty `لا توجد تدفقات خزينية في هذه الفترة`, then ready chart;
- preserve `chartData` mapping (`date / inflow / outflow / net`), caller-owned ordering and all current `ResponsiveContainer`, `AreaChart`, margin, gradient ids/colors/opacities, grid, axes, tooltip, reference line and three Area-series names/strokes/fills/widths unchanged;
- Mobile/Tablet/Desktop must retain 100% chart containment with no new page-level horizontal overflow; compact header/action wrapping must remain legible and touch-neutral because the badges are informational, not actions;
- preserve dark-mode/RTL behavior through existing semantic surfaces/tokens; do not introduce a page-local palette or alter current chart-series colors;
- focused tests must protect the shared `ChartPanel` adoption, semantic heading hierarchy, exact title/description/action presence, blocked/loading/empty/ready precedence and unchanged chart configuration/data mapping; evidence remains `TESTS_AUTHORED_NOT_EXECUTED` unless an approved runtime actually executes them.

Explicit exclusions:
- Treasury page header and `ReportFilterBar`;
- the semantic-contract notice;
- `SystemHealthBar`;
- all three `MetricCard` KPIs and summary loading behavior;
- `CustomTooltip` behavior/content;
- hook/query/cache/data mapping semantics beyond verifying they remain unchanged;
- calculations, trust resolution, permissions/RBAC/RLS, routing, backend/service contracts, validation, export/print and workflow/business semantics;
- `ChartPanel` API, shared CSS/tokens or any other report surface.

Stop rule:
If implementation requires any excluded shared-system widening or functional/data-semantic change, mark REPORT018 `BLOCKED` instead of broadening the PR.

## Product migration roadmap

The Product Design Director may decompose an item further, but exactly one dependency-safe implementation slice becomes READY at a time.

### A. Golden flows
- `DS2-UI-001` through `DS2-UI-005` — `DONE`

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
- `DS2-REPORT-001` through `DS2-REPORT-017` — `DONE`
- `DS2-REPORT-018 — Treasury daily cashflow chart-panel convergence` — `READY`
- further Reports/Analytics convergence beyond REPORT018 — `BACKLOG` / each concern must be bounded separately

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