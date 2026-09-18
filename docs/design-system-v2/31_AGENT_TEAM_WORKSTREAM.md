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

Product UI is integrated through `DS2-REPORT-001`.

Latest product integration:
- PR: `#48 — DS2-REPORT-001: converge report route sub-navigation`
- Exact reviewed PR HEAD: `02f5d4f381d3999a9a3cda7ce8fbe0fc394926ba`
- Squash merge commit: `5d2c57d9a502a4bbb2d355d94634bcf8b53075d2`
- Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
- Product Design: `PASS — NO DESIGN-SYSTEM BLOCKER` on the same exact HEAD
- Runtime/preview/release evidence: not claimed

The development branch includes semantic foundations, responsive shell/navigation/form/collection/action patterns, Dashboard V2, Customers migrations, Sales list/form/detail foundations, Inventory list/transfer migrations, Procurement list/form-shell migrations, Finance overview/detail foundations, HR operational-task/admin collection proofs, Field Activities list/create-edit proofs, Work create-task form convergence, Work Hub shared view-mode selector convergence, Supervisor Work shared KPI summary convergence, and Reports shared route-level sub-navigation convergence.

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
- the common `ReportsLayout` route navigation now uses shared V2 `SubNav` instead of the report-local `reports-tabs` / inline `NavLink` mini-system;
- all 14 report destinations, exact order, Arabic labels/icons and permission arrays remain unchanged;
- caller-owned `tab.permissions.some(permission => can(permission))` eligibility remains in `ReportsLayout`;
- `/reports/visits` and `/reports/reengagement` remain outside `AnalyticsGate`; all other report outlets remain gated;
- shared `SubNav` owns route-link semantics, active/focus treatment, horizontal containment, RTL-safe layout and touch geometry;
- child report filters, queries, calculations, export/print, routing and business semantics remain untouched;
- focused tests are authored but were not executed.

## Current single READY slice

### DS2-REPORT-002 — Report date-preset selector convergence
Status: `READY`
Owner role: UI Production Engineer next
Dependency baseline: `DS2-REPORT-001` integrated at `5d2c57d9a502a4bbb2d355d94634bcf8b53075d2`
Primary implementation target: `src/components/reports/ReportFilterBar.tsx`
Shared pattern target: `src/components/patterns/SegmentedControl.tsx`

System intent:
- converge only the four report date-preset buttons inside the domain-local `ReportFilterBar` onto shared V2 `SegmentedControl`;
- retire the report-local preset-button mini-system for selection hierarchy, focus, selected state and touch geometry while keeping the whole `ReportFilterBar` as a Reports-domain composite;
- use the existing shared single-choice filter/view-mode grammar rather than creating a Reports-specific segmented variant;
- close the known preset touch-target debt without widening into custom-date, query, chart, metric or table redesign.

In scope:
- replace only the `report-filter-presets` button group with shared `SegmentedControl`;
- derive the selected preset from the current `{ from, to }` range by comparing it with the existing preset range calculations; a custom range that matches no preset may legitimately render with no preset selected;
- on preset selection, continue emitting the existing normalized `DateRange` through the existing `onChange` contract;
- preserve the existing four presets exactly, in the same order and Arabic copy: `آخر 7 أيام`, `آخر 30 يوماً`, `آخر 90 يوماً`, `هذا الشهر`;
- preserve the existing `applyPreset`, `normalizeDateRange` and local-date semantics unless a mechanical refactor is strictly necessary to wire the shared control without changing output;
- add/update focused source-level tests for preset order/copy, emitted ranges, selected-state semantics and custom-range no-selection behavior.

Explicit exclusions:
- no redesign or shared migration of the two custom `<input type="date">` controls in this slice;
- no change to `ReportFilterBar`'s external `value/onChange` contract, date normalization, month-boundary meaning, default ranges or report-page ownership of state;
- no change to `OverviewPage`, `SalesPage` or other report hook inputs beyond any strictly mechanical consumer/test adjustment required by unchanged `ReportFilterBar` API;
- no query/cache/service/calculation/chart/table/metric/export/print/permission/routing/`AnalyticsGate` change;
- no REPORT001 `SubNav` change, report-page redesign, backend/business change, preview/deploy, hosted CI or `main` work;
- no broad cleanup of unrelated Reports inline styles or dead code.

Device/state/accessibility acceptance:
- **Desktop (`>=1025px`)**: the four presets remain a compact, legible single-choice report filter with no unnecessary wrapping or hierarchy regression beside the existing custom-date controls;
- **Tablet (`769–1024px`)**: the selector remains touch-first with shared 44px practical target geometry and preserves the surrounding filter bar's deliberate wrapping/containment;
- **Mobile (`<=768px`)**: shared `SegmentedControl` containment/overflow keeps all four Arabic preset labels reachable without viewport overflow or compressed sub-touch targets; no hover dependency;
- **RTL/Arabic**: preserve exact Arabic labels/order and logical layout; labels stay readable and are not clipped into ambiguous abbreviations;
- **Accessibility**: provide a concise Arabic group name via `ariaLabel`, preserve native button keyboard behavior, shared visible `:focus-visible`, and `aria-pressed` selected semantics; selected meaning must not depend on color alone;
- **Custom range state**: if neither preset range equals the caller value, no preset is falsely marked selected; the two existing date inputs remain the source of custom-range editing.

Boundary / BLOCK rule:
- `SegmentedControl` already owns the needed presentation semantics (`role="group"`, `aria-pressed`, focus-visible, 44px minimum height and mobile horizontal containment), so this slice must consume that contract rather than fork it locally;
- the Reports domain remains responsible for calculating preset date ranges and for the `DateRange` value emitted to analytics consumers;
- if parity with the current four preset meanings requires a functional/query/business semantic change, mark `BLOCKED` instead of widening the slice;
- exactly one implementation PR may carry REPORT002.

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
- `DS2-REPORT-002` Report date-preset selector convergence — `READY` / shared `SegmentedControl` adoption inside `ReportFilterBar` only
- custom-date/filter-composite convergence beyond the preset selector — `BACKLOG` / must be independently bounded from report business/query semantics
- `DS2-REPORT-003` Metrics/charts/tables and responsive report composition — `BACKLOG`

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
