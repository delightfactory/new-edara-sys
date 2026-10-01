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

Product UI is integrated through `DS2-REPORT-051`.

Latest product integration:
- PR: `#100 — DS2-REPORT-051: adopt shared Churn Risk chart tooltip`
- Exact reviewed PR HEAD: `8af587a2b6ecf03fde3903290d8bbfab3cf8b0a5`
- Squash merge commit: `27d37f6d4c3a2ab184f9c7f47f86e637af6835f6`
- Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
- Product Design exact-head closeout: `PASS — NO DESIGN-SYSTEM BLOCKER`
- Runtime/preview/release evidence: not claimed

The development branch includes semantic foundations, responsive shell/navigation/form/collection/action patterns, Dashboard V2, representative Customers/Sales/Inventory/Procurement/Finance/HR/Field/Work migrations, Reports route/date/filter convergence, shared `ChartPanel`, `ChartTooltip`, `MetricGrid`, `StatePanel`, `AlertPanel`, `SectionHeader`, shared V2 Field controls in representative report headers, responsive detail-collection proofs, Customer Re-engagement single-renderer `ResponsiveCollection` orchestration across Mobile/Tablet/Desktop, and shared `ChartTooltip` adoption in Receivables, Sales, Treasury, Product Performance, Rep Performance and Churn Risk while preserving caller-owned analytical/business truth.

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
- `DS2-REPORT-049 — Product Performance shared chart-tooltip adoption` — `DONE` — PR #97 — reviewed HEAD `426bb9a76ad968d670473150e35ef4cfeb43372e` — merge `055aa6587ff2f08e9e89cbf604c15d58b46c86ff` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-050 — Rep Performance shared chart-tooltip adoption` — `DONE` — PR #98 — reviewed HEAD `007d1174c09f1808a261fa49b133e4201d25ca68` — merge `22983eff7ce4d11113c2b10de5468bb33bb86936` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.
- `DS2-REPORT-051 — Churn Risk shared chart-tooltip adoption` — `DONE` — PR #100 — reviewed HEAD `8af587a2b6ecf03fde3903290d8bbfab3cf8b0a5` — merge `27d37f6d4c3a2ab184f9c7f47f86e637af6835f6` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED` — Product Design PASS.

## REPORT051 system result

- Churn Risk now delegates only the `توزيع تصنيف العملاء` Pie-tooltip presentation/anatomy to the existing shared domain-agnostic `ChartTooltip`.
- Churn Risk retains caller ownership of active/payload gating, category heading, exact `عملاء` row label, `FMT` count formatting, caller Pie color, explicit LTR numeric direction and all analytical/trust/business truth.
- Exact ready-only chart presence, 260px geometry, Pie data/order/keys/radii/padding/colors, Legend, Trust/Freshness, report filters, KPI summary and responsive detail composition remain unchanged.
- Shared `ChartTooltip` API/CSS/tokens/breakpoints were not widened; Receivables, Sales, Treasury, Product Performance, Rep Performance and Churn Risk are now bounded consumers.
- Focused Churn Risk adapter/device/state/chart regression tests were authored but not executed under the hosted-CI quota policy.

## Current single READY slice

### DS2-REPORT-052 — Target Attainment shared chart-tooltip adoption
Status: `READY — BOUNDED`.
Owner role for immediate next action: UI Production Engineer.

Representative surface:
- `src/pages/reports/TargetAttainmentPage.tsx` → the default Recharts tooltip inside `نسبة الإنجاز — المندوبون الفرديون`.

System intent:
- replace only the default Recharts tooltip presentation with the already-proven shared `ChartTooltip`;
- keep chart-library payload interpretation in a local Target Attainment adapter;
- keep the current representative name heading, exact row label `الإنجاز`, percentage formatting, caller achievement color and explicit LTR numeric direction caller-owned;
- do not widen `ChartTooltip` API/CSS/tokens/breakpoints and do not introduce a second tooltip grammar.

Acceptance boundary:
- preserve the exact chart presence rule `chartData.length > 0`; do not add loading/empty chart UI where none exists;
- preserve `individualRows = rows.filter(r => r.scope === 'individual' && r.rep_name)`;
- preserve chart mapping `{ name: r.rep_name!, pct: Math.round(r.achievement_pct ?? 0) }`;
- preserve `ResponsiveContainer width="100%" height={Math.max(chartData.length * 40, 200)}`;
- preserve vertical `BarChart` layout, margins `{ top: 4, left: 10, right: 40, bottom: 0 }`, grid, X/Y axes, percentage tick/domain behavior and `ReferenceLine x={100}`;
- preserve `Bar dataKey="pct" name="الإنجاز%" radius={[0, 3, 3, 0]} maxBarSize={20}`;
- preserve caller `barColor` thresholds/colors: `>=100 -> #10b981`, `>=80 -> #f59e0b`, otherwise `#ef4444`;
- preserve ChartPanel title/description, Trust/Freshness action behavior, report-header filters, KPI summary, responsive target-detail collection/table/cards, blocked/loading/empty precedence and all query/trust/business semantics;
- Mobile 390 / Tablet 900 / Desktop 1440 use the same shared RTL passive tooltip grammar with long-Arabic representative-name containment; percentage values remain LTR/bidi-safe;
- tooltip remains informational only: no focus target, tab stop, `role`, `aria-live` or keyboard/action semantics.

Focused test expectations:
- inactive / empty-payload adapter guards;
- exact representative heading, one-row `الإنجاز` label, preserved percentage formatting, caller achievement color and LTR direction;
- CSSOM-normalized representative achievement color evidence;
- shared-tooltip adoption at 390 / 900 / 1440 and long-Arabic/passive anatomy;
- no chart/tooltip leakage when `chartData.length === 0`;
- unchanged individual-only filtering, rounded chart mapping, dynamic height, layout/margins/grid/axes/reference-line/bar/color contracts and Trust/Freshness presence rules.

Explicitly excluded:
- any other report tooltip or chart;
- `ChartTooltip` implementation/API/tests/CSS/tokens/breakpoints;
- `ChartPanel`, `ResponsiveCollection`, `Card`, `KeyValueList`, `MetricCard` or other shared-pattern changes;
- Target Attainment filter-control convergence, KPI cards, detail collection/table/cards, export/print/navigation;
- any hook/query/cache/RPC/Supabase/calculation/trust/permission/RBAC/RLS/routing/validation/backend/business change.

If the existing shared `ChartTooltip` cannot serve this chart unchanged, or preserving current chart semantics requires functional change, mark REPORT052 `BLOCKED` rather than widening scope.

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
- `DS2-REPORT-001` through `DS2-REPORT-051` — `DONE`
- `DS2-REPORT-052 — Target Attainment shared chart-tooltip adoption` — `READY — BOUNDED`
- further Reports/Analytics convergence beyond REPORT052 — `BACKLOG` / each concern must be bounded separately

### J. Settings / Administration
- `DS2-ADMIN-001` Users/roles/settings/audit surfaces — `BACKLOG`

### K. Global convergence and cleanup
- `DS2-GLOBAL-001` Global style debt and inline-style reduction — `BACKLOG`
- `DS2-GLOBAL-002` Dark mode / RTL / long Arabic / numeric stress pass — `BACKLOG`
- `DS2-GLOBAL-003` Accessibility/focus/touch/motion pass — `BACKLOG`
- `DS2-GLOBAL-004` Legacy component/CSS retirement — `BACKLOG`
- `DS2-GLOBAL-005` Final visual/system consistency audit — `BACKLOG`
