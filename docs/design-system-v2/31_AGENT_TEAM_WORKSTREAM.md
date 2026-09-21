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

Product UI is integrated through `DS2-REPORT-014`.

Latest product integration:
- PR: `#62 — DS2-REPORT-014: converge Rep Performance comparison chart panel`
- Exact reviewed PR HEAD: `6f77f2b5aab911c9fa18afd3c78268255456a0ad`
- Squash merge commit: `a7096cdc86fb9fa55205556a10c8a5c13a6235d4`
- Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
- Product Design: `PASS — NO DESIGN-SYSTEM BLOCKER` on the same exact HEAD
- Runtime/preview/release evidence: not claimed

The development branch includes semantic foundations, responsive shell/navigation/form/collection/action patterns, Dashboard V2, Customers migrations, Sales list/form/detail foundations, Inventory list/transfer migrations, Procurement list/form-shell migrations, Finance overview/detail foundations, HR operational-task/admin collection proofs, Field Activities list/create-edit proofs, Work create-task form convergence, Work Hub shared view-mode selector convergence, Supervisor Work shared KPI summary convergence, Reports shared route-level sub-navigation convergence, Reports shared date-preset selector convergence with hardened `SegmentedControl` geometry, Reports shared native `DateField` convergence for custom dates, Reports Overview KPI-summary layout convergence onto shared `MetricGrid`, Product Performance, Customer Health and Churn Risk responsive detail-collection convergence via `ResponsiveCollection + Card + KeyValueList`, Geography analysis-level convergence onto shared `Select -> Field`, and shared domain-agnostic `ChartPanel` proven across Sales, Receivables, Churn Risk, Product Performance and Rep Performance analytical sections.

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

### REPORT014 system result

- Rep Performance chart `مقارنة المندوبين — أعلى 15` now consumes the existing presentation-only `ChartPanel` instead of a page-local Card/header shell.
- Exact title/description, `salesTrust` Trust/Freshness presence and props, 300px loading/empty behavior and exact empty copy, `rows.slice(0, 15)` mapping/order, dynamic `Math.max(chartData.length * 40, 200)` height and complete BarChart/grid/axes/tooltip/revenue/returns configuration remain caller-owned and unchanged.
- The shared shell now supplies the established semantic `h1 -> h2` hierarchy, Arabic/RTL containment, semantic dark-mode surfaces and shared Card/SectionHeader spacing without widening `ChartPanel` API/CSS.
- The Rep Performance detail table, KPIs, filters/date controls, `SystemHealthBar`, `CustomTooltip`, hooks, queries, calculations, ranking, trust semantics, permissions/RBAC/RLS, routing, export/print and business behavior remain outside the slice and unchanged.

## Current single READY slice

### DS2-REPORT-015 — Geography responsive detail-collection convergence
Status: `READY`
Owner role for immediate next action: UI Production Engineer
Representative surface: `src/pages/reports/GeographyPage.tsx` → `التوزيع حسب {LEVEL_LABELS[level]}` collection only.

System-pattern intent:
- converge the Geography report's current Desktop-only wide table onto the already-proven `ResponsiveCollection + Card + KeyValueList` grammar;
- preserve Desktop as the dense comparative heatmap table while giving Tablet/Mobile deliberate card composition from the exact same caller-owned `GeographyRow[]` data;
- mount exactly one device renderer at a time; do not duplicate the table and cards behind CSS hiding;
- consume existing shared patterns unchanged unless the implementation proves a real blocker. Any shared API/CSS widening requires Product Design re-bounding before implementation continues.

Required preservation / acceptance boundary:
- **Data/source truth:** keep `useGeographyTable(filters)`, row ordering, `geo_id`, `geo_name`, `parent_name`, `net_revenue`, `customer_count`, `transaction_count`, `revenue_share_pct`, and `maxRev` semantics unchanged.
- **Level semantics:** preserve the existing `governorate | city | area` controlled state/filter meaning from REPORT007; Desktop keeps the conditional `الأم` column only when `level !== 'governorate'`; Tablet/Mobile must represent the same parent field conditionally with the current `parent_name ?? '—'` fallback.
- **Desktop:** preserve the current table shell, dynamic heading, Trust/Freshness cluster, six/conditional-five column order, heatmap opacity/background calculation, zero-row treatment, hover affordance, exact numeric formatting/direction and row ordering. Add semantic `scope="col"` to Desktop headers while keeping their labels unchanged.
- **Tablet:** use the same Geography identity/data in touch-first cards, with `geo_name` as the card identity and a two-column compact `KeyValueList` for conditional parent, net revenue, customers, transactions and revenue share. No ordinary horizontal scrolling.
- **Mobile:** use the same card anatomy in a one-column compact `KeyValueList`; long Arabic geography names/parent names must wrap without overflow, while money/count/share values retain readable LTR numeric treatment where already applicable. No ordinary horizontal scrolling.
- **States:** preserve `tableLoading` precedence and the exact five `SkeletonCard height={44}` loading composition; preserve the exact empty condition/copy `لا توجد بيانات — شغّل watermark sweep أولاً`; do not invent blocked/error/business-state semantics not present in the current collection.
- **Accessibility / interaction:** only one renderer mounted per device; semantic Desktop column headers; no new click target, hover dependency, keyboard path or business action; Card remains non-interactive presentation.
- **RTL / dark mode:** use existing semantic Card/KeyValueList surfaces and Arabic-first wrapping; do not add a page-local palette or mirrored-LTR assumptions.

Explicit exclusions:
- page header, analysis-level `Select`, `ReportFilterBar`, KPI `report-grid`, `MetricCard`, `SystemHealthBar`, collection outer shell/header, Trust/Freshness behavior, and all other report pages;
- any change to `ResponsiveCollection`, `Card`, `KeyValueList` APIs/CSS unless Product Design explicitly re-bounds the slice after a demonstrated blocker;
- all hooks, queries, cache behavior, calculations, geography aggregation, ranking/order, permissions/RBAC/RLS, routes, export/print, backend, deployment or business semantics.

Focused test-artifact expectation:
- Desktop preserves exact dynamic columns/labels/order, `scope="col"`, row facts and no card renderer;
- Mobile mounts only the one-column card renderer with all current source fields represented and conditional parent behavior;
- Tablet mounts only the two-column card renderer with the same data truth;
- loading and exact empty-copy branches preserve precedence and suppress ready renderers;
- level change continues to preserve REPORT007 controlled filter semantics and changes the parent-field presence only through existing level truth.

Evidence must remain honestly labeled under `33_TEST_AND_VALIDATION_POLICY.md`; no executed build/test/runtime claim without an approved execution environment.

If implementation requires functional/data-semantic change or shared-contract widening, mark REPORT015 `BLOCKED` rather than broadening the PR.

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
- `DS2-REPORT-001` through `DS2-REPORT-014` — `DONE`
- `DS2-REPORT-015 — Geography responsive detail-collection convergence` — `READY`
- further Reports/Analytics convergence beyond REPORT015 — `BACKLOG` / each concern must be bounded separately

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