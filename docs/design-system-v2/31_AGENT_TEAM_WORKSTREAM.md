# Current REPORT053 Execution Claim

REPORT052 is DONE and integrated. REPORT053 — Visit Reports filter-field convergence is `REVIEW — BOUNDED` on Draft PR #104, exact implementation HEAD `02d17d9adcb79ff15b5cbd6b1546c80d1e7b0da5`. Product Design records `PASS — NO DESIGN-SYSTEM BLOCKER`; fresh same-head Design QA remains pending and integration is not authorized. The Vercel bot-created Preview is governance `WATCH` only and is not accepted runtime/visual evidence.

Do not start a duplicate slice or re-implement completed tooltip adoption. Existing role reviews should consume the single eventual exact branch artifact; other code mutation on this slice must coordinate with this handoff. No main, CI policy, Vercel or schedule changes are included.

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
| Development Integrator | Integrate reviewed, validated final candidate and advance queue | hourly | No feature work | Development only | No |

`BACKLOG -> READY -> IN_PROGRESS -> REVIEW -> GREEN-DEV -> DONE`

Exceptional state: `BLOCKED`.
Only one implementation slice may be active. A role with nothing actionable must no-op.

## Repository-native communication

Before material action every role reads Team Memory, all four role states, the Decision Log, this workstream, issue #27, and the active PR. Each role owns only its own state file. Integrator updates Team Memory after successful merge. Issue #27 is the concise event stream.

## GitHub Actions / preview policy

Hosted GitHub Actions remain off during normal development. Focused tests are
still authored. Draft-review evidence is exact-head `AGENT-REVIEW: GREEN-DEV` +
`SOURCE_REVIEW_PASS` + an honest execution label. These source-review markers
alone do not authorize integration. A known build/type failure blocks it.

Owner exception dated 2026-10-01: `.github/FINAL_CANDIDATE_CI.md` permits one
explicit ready transition for a frozen final candidate, with successful exact
head/base CI required before final-candidate integration. Scheduled agents keep
PRs draft and must not perform the former automatic Draft-to-Ready step without
owner final-candidate authorization. Normal development, dispatch and deployment
remain excluded; DS2 `main` remains frozen.

Integration requires all existing jobs to succeed for the reviewed head/base and
tested merge snapshot, followed by a fresh identity check and expected-head merge
protection. Record `FINAL_CANDIDATE_CI_PASS` separately from source/visual evidence.
Missing, stale, skipped or failed CI blocks integration; an owner prohibition on
merge remains binding even after successful validation.

Vercel preview remains owner-requested only. Scheduled agents never merge to `main`.

## Current integrated baseline

Product UI is integrated through `DS2-REPORT-052`.

Source baseline audited on 2026-10-01: `13e4fd9434e841a5ade7601c28254c3ad05e811b` on `design-system-v2-development`.

Latest product integration:
- PR: `#103 — DS2-REPORT-052: adopt shared Target Attainment chart tooltip`
- Exact reviewed PR HEAD: `c6d3f940e69451b0e80e68cc17dbc7c7c9bbd5ab`
- Squash merge commit: `0c858b7b71ae1142f53cf7a152533f94ca7d8a13`
- Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + bounded `LOCAL_EXECUTION_PASS`: 23/23 focused tests and focused fetched-source-closure TypeScript check PASS on the reviewed candidate
- Product Design exact-head closeout: `PASS — NO DESIGN-SYSTEM BLOCKER`
- Evidence limits: hooks/Recharts mocked; no full-application build/lint, browser runtime, visual, preview or release PASS claimed

The development branch includes semantic foundations, responsive shell/navigation/form/collection/action patterns, Dashboard V2, representative Customers/Sales/Inventory/Procurement/Finance/HR/Field/Work migrations, Reports route/date/filter convergence, shared `ChartPanel`, `ChartTooltip`, `MetricGrid`, `StatePanel`, `AlertPanel`, `SectionHeader`, shared V2 Field controls in representative report headers, responsive detail-collection proofs, Customer Re-engagement single-renderer `ResponsiveCollection` orchestration across Mobile/Tablet/Desktop, and shared `ChartTooltip` adoption in Receivables, Sales, Treasury, Product Performance, Rep Performance, Churn Risk and Target Attainment while preserving caller-owned analytical/business truth.

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

- `DS2-REPORT-052 — Target Attainment shared chart-tooltip adoption` — `DONE` — PR #103 — reviewed HEAD `c6d3f940e69451b0e80e68cc17dbc7c7c9bbd5ab` — merge `0c858b7b71ae1142f53cf7a152533f94ca7d8a13` — `GREEN-DEV + SOURCE_REVIEW_PASS` plus bounded 23/23 focused tests and focused source-closure TypeScript PASS — Product Design PASS; no full-app/runtime/visual/release qualification.

## REPORT051 system result

- Churn Risk now delegates only the `توزيع تصنيف العملاء` Pie-tooltip presentation/anatomy to the existing shared domain-agnostic `ChartTooltip`.
- Churn Risk retains caller ownership of active/payload gating, category heading, exact `عملاء` row label, `FMT` count formatting, caller Pie color, explicit LTR numeric direction and all analytical/trust/business truth.
- Exact ready-only chart presence, 260px geometry, Pie data/order/keys/radii/padding/colors, Legend, Trust/Freshness, report filters, KPI summary and responsive detail composition remain unchanged.
- Shared `ChartTooltip` API/CSS/tokens/breakpoints were not widened; Receivables, Sales, Treasury, Product Performance, Rep Performance and Churn Risk are now bounded consumers.
- Focused Churn Risk adapter/device/state/chart regression tests were authored but not executed under the hosted-CI quota policy.

## Historical REPORT052 boundary — completed, not active

The original scope below is retained for traceability; its implementation is complete. Do not restart it.

### DS2-REPORT-052 — Target Attainment shared chart-tooltip adoption
Status: `DONE — INTEGRATED`.
No implementation action remains for this slice.

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

Historical stop rule: if the existing shared `ChartTooltip` could not serve this chart unchanged, or preserving current chart semantics required functional change, REPORT052 was to become `BLOCKED` rather than widen scope.

## REPORT052 result and tooltip-track closure

- Target Attainment now uses the existing shared `ChartTooltip` through its caller-owned adapter; percentage formatting, achievement thresholds/colors, LTR values, chart geometry, presence and trust/business semantics remain unchanged.
- Full source inventory at the audited baseline covers all 23 non-test TSX files under `src/pages/reports/`, including profitability subpages. All eight Recharts `<Tooltip>` mounts across seven pages use adapters rendering the existing shared `ChartTooltip`: Receivables (1), Sales (2), Treasury (1), Product Performance (1), Rep Performance (1), Churn Risk (1), Target Attainment (1).
- No remaining chart-tooltip adoption candidate was found in this Reports source inventory. This closes the current adoption track only; it is not a runtime/visual audit, a claim about charts outside this directory, or completion of Reports/Analytics or Design System V2.
- The earlier Director selection `Reports chart-tooltip convergence follow-up audit` is superseded by this completed source inventory and the concrete next surface below. Do not create a no-op tooltip implementation or reselect Target Attainment.

## Current single active slice

### DS2-REPORT-053 — Visit Reports filter-field convergence
Status: `REVIEW — BOUNDED`.
Owner role for immediate next action: Design QA. Development Integrator acts only after same-head `AGENT-REVIEW: GREEN-DEV`.

Current review checkpoint:
- Draft PR: `#104 — DS2-REPORT-053: converge Visit Reports filter fields`, targeting `design-system-v2-development`.
- Exact implementation HEAD: `02d17d9adcb79ff15b5cbd6b1546c80d1e7b0da5`; current Development coordination HEAD before this Workstream write: `24e94ba4aebacee271daffb3c7d93a55edb0b9a6`.
- Product Design exact-head disposition: `PASS — NO DESIGN-SYSTEM BLOCKER`, recorded in `team/design-system-v2/DESIGN_DIRECTOR_STATE.md`.
- Design QA exact-head review is still pending; no REPORT053 `GREEN-DEV` exists yet. Do not integrate and do not start a competing product slice while PR #104 is active.
- Evidence remains bounded: baseline `8/8` and candidate `22/22` focused tests PASS plus focused source-closure TypeScript PASS; no full-app build/lint PASS and no browser/runtime visual/RTL/overflow PASS are claimed.
- A Vercel bot created an automatic Preview for PR #104 despite `DS2-DEC-004 — Manual preview only`. Product Design did not trigger or use it as evidence; treat it as governance `WATCH`, not runtime/visual qualification.

Actor and benefit:
- Field supervisors and managers narrowing visit reports by branch, representative, purpose, status, recording quality and contact outcome receive the same Arabic-first labelled native-select grammar and touch sizing as other migrated screens, without changing which visits are returned.

Evidenced gap and exact surface:
- `src/pages/reports/VisitReportsPage.tsx`, only the six bare `<label><select className="form-input">` controls within `.visit-report-filter-grid` (audited lines 629–677).
- Existing `src/components/ui/Select.tsx` already composes a native select through `Field`, forwards the existing value/onChange/options and supplies unique label/control relationships; no new shared component/API is needed.
- `src/pages/reports/VisitReportsPage.css` currently adds local label grammar and a 42px minimum to this grid. Remove only `.visit-report-filter-grid label` and `.visit-report-filter-grid select` declarations so existing shared Field/Select styling owns label/control anatomy and standard/touch sizing. Preserve the grid/container and all media-query composition.

Implementation file allowlist:
- `src/pages/reports/VisitReportsPage.tsx`: import existing `Select`; replace only those six label/select pairs with labelled V2 `Select`, keeping native option children and handlers intact.
- `src/pages/reports/VisitReportsPage.css`: only removal of the two obsolete descendant rules named above; no breakpoint, grid, other selector, token or global stylesheet change.
- `src/pages/reports/VisitReportsPage.test.tsx`: extend focused integration coverage; preserve existing assertions.
- UI Production Engineer's own `team/design-system-v2/UI_IMPLEMENTATION_STATE.md` for exact-head evidence/handoff.

Acceptance boundary:
- Preserve exact Arabic labels and option labels/order/values, including empty-string “all” choices; branch IDs/names, employee IDs/full names, purpose exclusion of `unspecified`, all status/quality mappings, and `summary?.contact_results ?? []` mapping.
- Preserve current six controlled string states and every handler's exact setter plus `resetPage()` call. Empty values still become `undefined` only in the existing caller filter object.
- Preserve visibility: branch/representative/purpose in every tab; visit status only in `visits` or `quality`; recording quality/contact result only in `visits`.
- Preserve `changeTab`: page resets to 1; leaving `visits` clears recording quality/contact result; leaving both `visits` and `quality` clears visit status. Do not add dependent-filter resets, loading locks or new validation.
- Preserve date `ReportFilterBar`, grid order and current responsive layout (390: one column; 900: two columns; 1440: four columns), query keys/functions/enabled conditions/page size/exception mode, data-hook options, permission checks, export payload/CSV, summary metrics and every report/collection loading/error/empty/ready branch.
- Use existing native keyboard/focus behavior and one programmatically associated visible Arabic label per control, with unique IDs and no duplicate wrapping label. No added live region, custom popup, focus trap, required state or new tab stop.
- Existing shared control sizing applies: standard 42px and touch minimum 44px through canonical V2 tokens at <=1024px. Long Arabic labels/options and RTL must remain usable without widening the page; preserve native select behavior rather than inventing a popup.

Concrete focused acceptance tests:
1. Within the filter section, assert three labelled native selects on overview/surveys, four on quality and six on visits; migrated controls render `.ds-field` / `.form-select` and unique label htmlFor/control IDs. Survey template/question controls are excluded and unchanged.
2. Assert exact option value/text/order/defaults for all six controls, including branch/employee fixtures, absence of `unspecified`, all status/quality choices, dynamic contact results and empty contact-results fallback.
3. Select and clear every filter; assert existing service mock arguments retain exact value vs `undefined` semantics. From page 2, changing a filter returns the existing rows request to page 1 with pageSize 25; date range and other filter values are preserved.
4. Exercise visits -> quality -> overview -> visits and surveys transitions: preserve visibility, cleared/persisted filter values, page reset and `exceptionsOnly` / query enablement semantics. Repeat a selection/clear to catch stale state or duplicate controls.
5. At simulated widths 390/900/1440 and long Arabic branch/employee/contact strings, assert the same single filter control tree, exact labels, value retention and no duplicate IDs. Check stylesheet/source contract retains the existing grid/media rules and shared touch token path; do not label DOM width loops as visual geometry evidence.
6. Retain and run the existing Visit Reports tests for Desktop table, Mobile/Tablet single renderer, ten-fact order, drill-down destinations, quality facts, loading/error/empty, pagination and survey loading. Add focused assertions that export permission visibility and current filter payload construction have not changed where practical; do not invoke live export/backend services.
7. Verify diff is limited to the allowlist and the two local CSS-rule removals. Run focused local tests and scoped/full type checks only when an approved runtime is available; record exact command/HEAD and scope. A source inspection is not an executed PASS, and a known type/build failure blocks integration.

Explicit exclusions:
- All chart/tooltip work and all Target Attainment changes.
- Survey-template/question selectors outside the filter grid, tabs, ReportFilterBar, metrics, report tables/cards, state notices, output/export behavior and navigation.
- Shared Select/Field/component implementation/tests/APIs, global CSS/tokens/breakpoints and unrelated page-local styling.
- Hooks/queries/cache/services/RPC/Supabase, permissions/RBAC/RLS, validation, workflow, calculations and business semantics.
- Hosted CI, Vercel, main, schedule or governance-policy changes.

Dependencies and handoff:
- Existing Select/Field and global V2 form styles are integrated; no shared-layer prerequisite is missing.
- REPORT052 is DONE. At audit time only governance PR #101 was open against Development; it overlaps Workstream/policy files, not this product surface. Recheck live branch/PR overlap before adoption and implementation; preserve its separate governance review and quota restrictions.
- Director/Workstream owner adopts this boundary and reconciles its owned state; Integrator/Director reconciles stale Team Memory through authorized ownership. Do not overwrite QA or Implementer states as a substitute.
- UI Production branches from the exact latest Development HEAD, implements only this slice and opens one Draft PR. Fresh same-head Design QA/Product Design review precedes Development-only integration.
- If existing Select cannot preserve these contracts unchanged, or an overlapping active implementation/product-behavior dependency appears, report the exact blocker instead of widening scope.

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
- `DS2-REPORT-001` through `DS2-REPORT-052` — `DONE`
- `DS2-REPORT-053 — Visit Reports filter-field convergence` — `REVIEW — BOUNDED`
- further Reports/Analytics convergence beyond REPORT053 — `BACKLOG` / each concern must be bounded separately

### J. Settings / Administration
- `DS2-ADMIN-001` Users/roles/settings/audit surfaces — `BACKLOG`

### K. Global convergence and cleanup
- `DS2-GLOBAL-001` Global style debt and inline-style reduction — `BACKLOG`
- `DS2-GLOBAL-002` Dark mode / RTL / long Arabic / numeric stress pass — `BACKLOG`
- `DS2-GLOBAL-003` Accessibility/focus/touch/motion pass — `BACKLOG`
- `DS2-GLOBAL-004` Legacy component/CSS retirement — `BACKLOG`
- `DS2-GLOBAL-005` Final visual/system consistency audit — `BACKLOG`
