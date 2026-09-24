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

Product UI is integrated through `DS2-REPORT-048`.

Latest product integration:
- PR: `#96 — DS2-REPORT-048: adopt shared Treasury chart tooltip`
- Exact reviewed PR HEAD: `e8c718b8eb3f8be5df54627714a15166d8bd63ce`
- Squash merge commit: `9eb5489a00631f1cc7b9377893e7b0a1ebb560d6`
- Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
- Product Design exact-head closeout: `PASS — NO DESIGN-SYSTEM BLOCKER`
- Runtime/preview/release evidence: not claimed

The development branch includes semantic foundations, responsive shell/navigation/form/collection/action patterns, Dashboard V2, representative Customers/Sales/Inventory/Procurement/Finance/HR/Field/Work migrations, Reports route/date/filter convergence, shared `ChartPanel`, `ChartTooltip`, `MetricGrid`, `StatePanel`, `AlertPanel`, `SectionHeader`, shared V2 Field controls in representative report headers, responsive detail-collection proofs, Customer Re-engagement single-renderer `ResponsiveCollection` orchestration across Mobile/Tablet/Desktop, and shared `ChartTooltip` adoption in Receivables, Sales and Treasury while preserving caller-owned analytical/business truth.

## Completed slices

- `DS2-UI-001` through `DS2-UI-005` — `DONE`; detailed reviewed/merge SHA evidence remains preserved in Git history and prior workstream revisions.
- `DS2-INV-001` and `DS2-INV-002` — `DONE`.
- `DS2-PROC-001` and `DS2-PROC-002` — `DONE`.
- `DS2-FIN-001` and `DS2-FIN-002` — `DONE`.
- `DS2-HR-001` and `DS2-HR-002` — `DONE`.
- `DS2-FIELD-001` and `DS2-FIELD-002` — `DONE`.
- `DS2-WORK-001` through `DS2-WORK-003` — `DONE`.
- `DS2-REPORT-001` through `DS2-REPORT-025` — `DONE`; detailed reviewed/merge SHA evidence remains preserved in Git history and prior workstream revisions.
- `DS2-REPORT-026 — Product Performance summary metric-grid convergence` — `DONE` — PR #74 — merge `9ac63ca20baaeefa6fe5cb3e87a9734f59847ac5` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-027 — Churn Risk filter-control field convergence` — `DONE` — PR #75 — merge `d9a1fb373142cac8c9f7f1b7545d340f99298f8a` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-028 — Profit Dashboard summary metric-grid convergence` — `DONE` — PR #76 — merge `337cf967ab1159968866811be194aec359c43f66` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-029 — Geography summary metric-grid convergence` — `DONE` — PR #77 — merge `523f547a4259043d33ee77afc5139ffe42c1354e` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-030 — Rep Performance summary metric-grid convergence` — `DONE` — PR #78 — merge `b5f3d49cbc2f68431573174ee2b653b269ee5d2c` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-031 — Customer Health as-of-date field convergence` — `DONE` — PR #79 — merge `7271801b22a58c4280c9bdbd82b37aa9de7a0fdc` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-032 — Customer Re-engagement KPI summary shared metric convergence` — `DONE` — PR #80 — merge `e7088ed6d683b4cc714059cd7f3d07831f9485b5` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-033 — Target Attainment individual-rep chart-panel convergence` — `DONE` — PR #81 — merge `464adbfe86f9ff1e53d288babb9715a010346b15` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-034 — Churn Risk KPI summary shared metric convergence` — `DONE` — PR #82 — merge `7ba36015798df5d4aa615077adade862687a6f9c` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-035 — Product Performance shared empty-state convergence` — `DONE` — PR #83 — merge `8d1aa7e4db89b8dfee7d9ce8c536bb4c160a40fb` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-036 — Rep Performance shared empty-state convergence` — `DONE` — PR #84 — merge `9c69d2103172c950fcdaf145bfade24e604b09fc` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-037 — Customer Health responsive-detail empty-state convergence` — `DONE` — PR #85 — merge `2af5917c0b370d1bd6aaa785ef248f6084e483d3` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-038 — Receivables chart empty-state convergence` — `DONE` — PR #86 — merge `5325d99fcc3d047f1fc6aa3dac39a5423d9376e4` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-039 — Geography responsive-detail empty-state convergence` — `DONE` — PR #87 — merge `035558bb3e86026742d3658d7c1928ee75f09215` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-040 — Churn Risk responsive-detail empty-state convergence` — `DONE` — PR #88 — merge `23707a5465549613dfbde0a6637acee5fbc847e2` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-041 — Sales revenue-chart empty-state convergence` — `DONE` — PR #89 — merge `b334b07e93b7551839772d6a5cbbdb53089df06b` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-042 — Sales revenue/tax bar-chart empty-state convergence` — `DONE` — PR #90 — merge `f7479859fe5c3233c3082bad2e97c0a004213f4c` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-043 — Treasury semantic-contract notice AlertPanel convergence` — `DONE` — PR #91 — merge `c9e28bd2b98bbf65d4d916e114cebb6cdcb86bf4` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-044 — Reports Overview section-header convergence` — `DONE` — PR #92 — merge `a763a12538b9074e85af3f94365f8ccefc67f525` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-045 — Customer Re-engagement responsive-list orchestration convergence` — `DONE` — PR #93 — merge `573753d8d6c50e44d56cbb5c253604e9755118a5` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-046 — Shared chart-tooltip presentation foundation (Receivables proof)` — `DONE` — PR #94 — merge `d937088e7ee1e7f6dc6fcb1dccb5bc5e617c86d0` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-047 — Sales shared chart-tooltip adoption` — `DONE` — PR #95 — merge `c7af0b151b51d904f658f8d7df3edbc6aaace8e1` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-REPORT-048 — Treasury shared chart-tooltip adoption` — `DONE` — PR #96 — reviewed HEAD `e8c718b8eb3f8be5df54627714a15166d8bd63ce` — merge `9eb5489a00631f1cc7b9377893e7b0a1ebb560d6` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.

## REPORT048 system result

- Treasury now delegates only its daily-cashflow tooltip presentation/anatomy to the existing shared domain-agnostic `ChartTooltip`.
- Treasury retains caller ownership of `active` / payload gating, payload order, `p.name`, `p.color`, exact `${fmt(p.value)} ج.م` formatting, explicit LTR values, Recharts trigger wiring and all analytical/business/trust truth.
- Exact `isBlocked -> dailyLoading -> empty -> ready`, 280px analytical geometry, blocked/empty Arabic copy, Trust/Freshness, data mapping, margins, axes/grid, zero `ReferenceLine`, gradients and all three Area series remain unchanged.
- Shared `ChartTooltip` API/CSS/tokens/breakpoints were not widened; Receivables, Sales and Treasury are now bounded consumers.
- Focused Treasury adapter/device/state/chart regression tests were authored but not executed under the hosted-CI quota policy.

## Current single READY slice

### DS2-REPORT-049 — Product Performance shared chart-tooltip adoption
Status: `READY — BOUNDED`.
Owner role for immediate next action: UI Production Engineer.
Representative surface: `src/pages/reports/ProductPerformancePage.tsx` → the page-local Recharts `CustomTooltip` used by the “أعلى 15 منتجاً بالإيراد” chart.

### System-pattern intent

Product Performance currently recreates the same neutral chart-tooltip surface/anatomy already proven by the shared domain-agnostic `ChartTooltip`. REPORT049 removes that remaining page-local presentation mini-system on this one representative chart only. The shared component must continue to own presentation/anatomy only; Product Performance remains the owner of Recharts payload interpretation, row order, labels, series color, value formatting/direction and every analytical/business/trust decision.

### Required implementation boundary

- Reuse existing `src/components/patterns/ChartTooltip.tsx`; do not widen its API, CSS, tokens or breakpoints.
- Keep a Product Performance-local Recharts adapter. It must preserve the existing `!active || !payload?.length` guard and map ready payload rows into shared tooltip items without moving interpretation into the shared component.
- Preserve exact caller semantics: heading `label`, payload row order, `p.name`, `p.color`, exact `${fmt(p.value)} ج.م` formatting and explicit LTR monetary value direction.
- Preserve ready wiring through existing Recharts `<Tooltip content={...} />` only.
- Preserve the exact chart state sequence `tableLoading -> empty -> ready`; loading and empty branches must not mount ready chart/tooltip content.
- Preserve exact 240px chart geometry and `ResponsiveContainer width="100%"` containment.
- Preserve existing `chartData = rows.slice(0, 15)` mapping, product-name 20-character visual truncation, chart margins, Cartesian grid, axes/tick formatting/rotation and the single `revenue` Bar with name `الإيراد`, fill `#2563eb`, radius `[3, 3, 0, 0]` and `maxBarSize={32}`.
- Preserve TrustStateBadge/FreshnessIndicator presence rule and all current chart title/description/Arabic copy.
- Device acceptance: Mobile 390px, Tablet 900px and Desktop 1440px must use the same shared RTL tooltip presentation with no new breakpoint/device fork.
- Long Arabic labels must remain contained/wrappable without ordinary viewport overflow; monetary values remain bidi-safe/LTR.
- Tooltip remains passive/informational: no button/action, focus target, tab stop, role or live-region semantics.

### Required focused test artifacts

Author or extend focused Product Performance tests to protect:
- inactive and empty-payload adapter guards;
- exact heading label, payload order/label, caller color, `${fmt(value)} ج.م` and `dir="ltr"` value contract;
- CSSOM-normalized inline series-color expectation (`#2563eb -> rgb(37, 99, 235)`), not raw HEX DOM style equality;
- shared-tooltip ready wiring at representative 390 / 900 / 1440 widths;
- no tooltip leakage into chart loading or empty branches;
- preserved 240px geometry, data mapping, margins, grid/axes and Bar-series contract.

Evidence remains subject to `33_TEST_AND_VALIDATION_POLICY.md`; authoring tests does not permit claiming execution.

### Explicit exclusions

- `RepPerformancePage` or any other report tooltip consumer.
- Any modification to shared `ChartTooltip`, `ChartPanel`, `StatePanel`, `ResponsiveCollection`, `MetricGrid`, `Card`, `KeyValueList`, tokens, CSS or device breakpoints.
- Product Performance category `<select>` / Field convergence, `ReportFilterBar`, page header, summary metrics, detail collection/table/cards, return-rate visual semantics, export/print or navigation.
- Any hook/query/cache/RPC/Supabase, calculation, trust, permission, RBAC/RLS, route, validation, backend or business-semantic change.

If Product Performance cannot adopt the existing shared tooltip contract without any excluded shared-contract or functional change, mark REPORT049 `BLOCKED` instead of broadening scope.

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
- `DS2-REPORT-001` through `DS2-REPORT-048` — `DONE`
- `DS2-REPORT-049 — Product Performance shared chart-tooltip adoption` — `READY — BOUNDED`
- further Reports/Analytics convergence beyond REPORT049 — `BACKLOG` / each concern must be bounded separately

### J. Settings / Administration
- `DS2-ADMIN-001` Users/roles/settings/audit surfaces — `BACKLOG`

### K. Global convergence and cleanup
- `DS2-GLOBAL-001` Global style debt and inline-style reduction — `BACKLOG`
- `DS2-GLOBAL-002` Dark mode / RTL / long Arabic / numeric stress pass — `BACKLOG`
- `DS2-GLOBAL-003` Accessibility/focus/touch/motion pass — `BACKLOG`
- `DS2-GLOBAL-004` Legacy component/CSS retirement — `BACKLOG`
- `DS2-GLOBAL-005` Final visual/system consistency audit — `BACKLOG`
