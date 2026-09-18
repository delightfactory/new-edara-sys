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

Product UI is integrated through `DS2-REPORT-002`.

Latest product integration:
- PR: `#49 — DS2-REPORT-002: converge report date preset selector`
- Exact reviewed PR HEAD: `3e0f11d52de77f07953dd2a226c82ff19ec2f75f`
- Squash merge commit: `cc91792263d9fc606b9c2f28a531daa826997c75`
- Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
- Product Design: `PASS — NO DESIGN-SYSTEM BLOCKER` on the same exact HEAD
- Runtime/preview/release evidence: not claimed

The development branch includes semantic foundations, responsive shell/navigation/form/collection/action patterns, Dashboard V2, Customers migrations, Sales list/form/detail foundations, Inventory list/transfer migrations, Procurement list/form-shell migrations, Finance overview/detail foundations, HR operational-task/admin collection proofs, Field Activities list/create-edit proofs, Work create-task form convergence, Work Hub shared view-mode selector convergence, Supervisor Work shared KPI summary convergence, Reports shared route-level sub-navigation convergence, and Reports shared date-preset selector convergence with hardened shared `SegmentedControl` long-content geometry.

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
- the common `ReportsLayout` route navigation uses shared V2 `SubNav` instead of the report-local route-navigation mini-system;
- all 14 report destinations, order, Arabic labels/icons and permission arrays remain unchanged;
- permission eligibility and `AnalyticsGate` ownership remain caller/domain-owned;
- shared `SubNav` owns route-link semantics, active/focus treatment, horizontal containment, RTL-safe layout and touch geometry;
- child report filters, queries, calculations, export/print, routing and business semantics remain untouched.

### DS2-REPORT-002 — Report date-preset selector convergence
Status: `DONE`
Merged PR: `#49`
Reviewed HEAD: `3e0f11d52de77f07953dd2a226c82ff19ec2f75f`
Squash merge: `cc91792263d9fc606b9c2f28a531daa826997c75`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Product Design: `PASS — NO DESIGN-SYSTEM BLOCKER`
Runtime/preview/release evidence: not claimed

System result:
- the four report date presets now use shared V2 `SegmentedControl` inside domain-local `ReportFilterBar`;
- exact preset labels/order/range outputs, external `DateRange value/onChange`, both custom date inputs and all date normalization/current-month semantics remain unchanged;
- all report query/cache/service/calculation/chart/table/metric/export/print/permission/routing/`AnalyticsGate` truth remains domain-owned and unchanged;
- shared default/non-block segmented items now retain intrinsic width through `flex: 0 0 auto`, while `--block` preserves equal-width `flex: 1 1 0` and Mobile containment remains `overflow-x: auto` in the shared layer;
- focused behavior and CSS-contract tests are authored but were not executed.

## Current single READY slice

### DS2-REPORT-003 — Report custom-date field convergence
Status: `READY`
Owner role: UI Production Engineer
Dependency baseline: `DS2-REPORT-002` integrated at `cc91792263d9fc606b9c2f28a531daa826997c75`
Representative surface: `src/components/reports/ReportFilterBar.tsx`
Shared-system target: V2 `DateField` form composite built from the existing `Field` / `Input` grammar; no date-range or analytics semantics inside the shared component

System-pattern intent:
- retire the two raw, inline-styled `<input type="date">` controls in `ReportFilterBar` as a local primitive family;
- establish the blueprint-declared shared V2 `DateField` presentation contract using native `input[type="date"]` semantics and the existing V2 Field/Input anatomy rather than inventing a Reports-only date-control variant;
- make the shared layer own input surface, border/radius, typography, dark-mode tokens, focus/invalid/disabled treatment, standard control geometry and touch geometry;
- keep Reports responsible for from/to meaning, ordering, normalization, presets and every analytics/query effect;
- preserve compact Desktop report review while allowing deliberate wrap/stack containment on Tablet/Mobile without viewport-level overflow or compressed touch targets.

Implementation boundary:
- add/evolve exactly one domain-agnostic shared `DateField` form composite under the existing V2 field system; it may forward normal native date-input props and Field metadata but must not parse, normalize, compare or mutate dates;
- migrate only the two custom date inputs in `ReportFilterBar` to that shared contract;
- retain local ReportFilterBar composition/layout ownership for the date pair; only obsolete raw-input visual styling may be removed;
- each date input must have an independent Arabic accessible name (`من تاريخ` / `إلى تاريخ`) that does not rely on the calendar icon or separator; visible label treatment may use the existing Field grammar only if it preserves compact filter density without a Reports-specific primitive variant;
- preserve the decorative calendar/date-range cue only if it remains non-essential to meaning;
- author focused tests for the shared DateField contract and ReportFilterBar custom-date behavior; evidence must be reported honestly under `33_TEST_AND_VALIDATION_POLICY.md`.

Preserve exactly:
- `ReportFilterBar` external `value: DateRange` / `onChange(DateRange)` contract;
- existing `normalizeDateRange(...)` calls and their current from/to normalization behavior;
- local-date/current-month/preset calculations and the exact four REPORT002 preset labels/order/meaning;
- REPORT001 `SubNav` and REPORT002 `SegmentedControl` behavior/geometry;
- report query parameters, hook/cache/service contracts, analytics calculations, metrics/charts/tables, permissions, routing, `AnalyticsGate`, export/print and all business truth;
- native browser date-input semantics; no custom date picker, timezone reinterpretation, locale parser or new validation rule.

Device / state / accessibility acceptance:
- **Desktop (`>=1025px`)**: date editing stays compact and visually subordinate to report content while using canonical V2 control styling/focus; no unnecessary full-width field expansion.
- **Tablet (`769–1024px`)**: both controls retain at least the shared touch control height and may wrap deliberately with the surrounding filter composition instead of shrinking into ambiguous controls.
- **Mobile (`<=768px`)**: no page-level horizontal overflow; both date controls remain independently reachable/readable with at least shared touch geometry, and wrapping/stacking is allowed when width is constrained.
- **RTL/Arabic**: from/to order and Arabic accessible naming remain unambiguous; layout uses logical flow and does not depend on physical left/right assumptions.
- **Dark mode**: date controls consume existing shared semantic input tokens; no report-local hard-coded light surface/border/text colors.
- **Focus/keyboard**: native focusability is preserved with the shared visible focus treatment; no custom keyboard model is introduced.
- **Disabled/read-only/error plumbing**: if exposed by the shared DateField API, it must forward existing Field/Input semantics only; this slice must not invent new report states or validation rules.
- **Behavior**: editing either date must still emit the same normalized `DateRange` through the parent callback; changing to a custom range must not falsely select a preset.

Explicit exclusions / BLOCK rule:
- no generic FilterBar redesign or Mobile filter-sheet work;
- no metrics/charts/tables/responsive report composition work (deferred to `DS2-REPORT-004`);
- no loading/empty/error/offline/sync report-state redesign;
- no query/cache/service/RPC/DB, permissions/RBAC/RLS, routing, `AnalyticsGate`, export/print or backend work;
- no custom calendar/date-picker implementation;
- no preview/deploy, hosted CI or `main` work;
- if the implementation requires changing date normalization, range semantics, query parameters or business meaning, mark `BLOCKED` instead of widening the slice.

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
- `DS2-REPORT-003` Report custom-date field convergence — `READY`
- `DS2-REPORT-004` Metrics/charts/tables and responsive report composition — `BACKLOG`

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
