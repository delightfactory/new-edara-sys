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

Product UI is integrated through `DS2-WORK-002`.

Latest product integration:
- PR: `#46 — DS2-WORK-002: converge Work Hub view-mode selector`
- Exact reviewed PR HEAD: `e3d557d59a811f3c896ffe90922e9512bbb3cdee`
- Squash merge commit: `add39ea8ee76b61d9a5a5938aa6cd03e2cc13456`
- Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
- Product Design: `PASS — NO DESIGN-SYSTEM BLOCKER` on the same exact HEAD
- Runtime/preview/release evidence: not claimed

The development branch now includes semantic foundations, responsive shell/navigation/form/collection/action patterns, Dashboard V2, Customers migrations, Sales list/form/detail foundations, Inventory list/transfer migrations, Procurement list/form-shell migrations, Finance overview/detail foundations, HR operational-task/admin collection proofs, Field Activities list/create-edit proofs, Work create-task form convergence, and Work Hub shared view-mode selector convergence.

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

### DS2-FIELD-002 — Activity create/edit form composition foundation
Status: `DONE`
Merged PR: `#43`
Reviewed HEAD: `a31addc60e5b0eaf8ee89a0fea11bded2a6e4c4a`
Squash merge: `2492fa475e7bc5beb9148124f31a4b4837057c19`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Runtime/preview/release evidence: not claimed

System result:
- live normal `ActivityForm` create/edit path now composes through shared `FormSection + FormGrid + FormActions + Button` instead of the page-local outer form/timing/action mini-system;
- task order remains activity data -> outcome/link/call conditional content -> timing/notes; conditional business meaning was not reordered;
- timing composition is one column on Mobile, capped at two on Tablet and three on Desktop inside the retained 640px form bound;
- cancel/submit remain non-sticky and touch-safe, with exact callbacks, save labels/loading state, `saving` disabled truth and `gpsBlocking` submit suppression page-owned;
- composition-touched native controls have explicit Arabic label associations while required/disabled semantics remain unchanged;
- visit-plan routing, GPS acquisition/verification/distance, target/history queries, order/collection linking, call-detail behavior, validation, payload construction, mutations, navigation and all backend/business/workflow truth remain page/domain-owned.

### DS2-WORK-001 — Create Task form composition foundation
Status: `DONE`
Merged PR: `#44`
Reviewed HEAD: `6eb3be28216ec1370ccd5fceced7ea8c5c224cd0`
Squash merge: `57747123643d0dd846cbda3ef340e9463a5f7647`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Product Design: `PASS — NO DESIGN-SYSTEM BLOCKER`
Runtime/preview/release evidence: not claimed

System result:
- `/work/new` now uses shared `FormSection + FormGrid + Field + FormActions + Button` while retaining the existing four-section Arabic operational order;
- safe paired fields remain one column on Mobile and two on Tablet/Desktop; narrative/full-width controls remain unsqueezed;
- V2 native input/select sizing is owned by the explicit `.ds-field` boundary, with `--ds-control-height-touch` through Tablet/Mobile and `--ds-control-height-standard` on Desktop; textarea preserves its larger 80px floor;
- cancel/create actions remain non-sticky, touch-safe and preserve existing secondary/primary hierarchy plus pending/loading truth;
- Arabic label/hint/error relationships now use the shared `Field` accessibility contract;
- `toIso`, assignment/defaulting, owner-vs-assignee meaning, acknowledgement eligibility/reset, validation wording/date rule, priority/visibility/completion mode, `useCreateTask`, payload/`activate: true`, toasts/navigation, queries/services/permissions/RBAC/RLS/workflow/backend truth remain page/domain-owned and unchanged.

### DS2-WORK-002 — Work Hub view-mode selector convergence
Status: `DONE`
Merged PR: `#46`
Reviewed HEAD: `e3d557d59a811f3c896ffe90922e9512bbb3cdee`
Squash merge: `add39ea8ee76b61d9a5a5938aa6cd03e2cc13456`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Product Design: `PASS — NO DESIGN-SYSTEM BLOCKER`
Runtime/preview/release evidence: not claimed

System result:
- `/work` now uses shared `SegmentedControl` for the existing `actions | work | attention` view modes instead of the page-local `.work-segmented` mini-system;
- exact Arabic labels/order/default and page-owned `mode` / `setMode` behavior remain unchanged;
- Work query hooks, operational flags, filtering/search calculations, summary-card mode callbacks, permissions, request routing, Mobile create behavior and workflow/state-machine truth remain page/domain-owned;
- selector-specific Work CSS was retired without broad Work styling cleanup;
- shared native button, `aria-pressed`, focus-visible, selected-surface, canonical Mobile/Tablet touch geometry and Mobile horizontal-containment contracts are reused;
- focused behavior/source tests protect the exact selector contract and retained functional ownership; evidence remains non-executed.

## Current single READY slice

### DS2-WORK-003 — Work detail/management state-surface convergence
Status: `READY`
Owner role: Product Design Director for boundary selection before implementation
Dependency baseline: `DS2-WORK-002` integrated at `add39ea8ee76b61d9a5a5938aa6cd03e2cc13456`

Intent:
- continue Work Management convergence before Reports/Analytics while preserving the North-Star roadmap;
- inspect representative Work detail, Supervisor/Team, management/configuration and state surfaces on the exact latest Development baseline;
- bound exactly one smallest dependency-safe presentation-only concern before UI implementation begins;
- prefer existing shared V2 shell, action, status, collection, form, feedback and state grammar over Work-local invention;
- preserve all Work query/service/permission/ownership/responsibility/validation/workflow/state-machine truth exactly.

Explicit guardrails:
- this READY state authorizes Product Design boundary selection, not a broad multi-surface implementation;
- no backend/business/query-cache/permission/validation/workflow change;
- no reopening WORK001/WORK002 for ad-hoc polish;
- no preview, deployment, hosted CI or `main` work;
- if the smallest safe concern cannot be isolated from functional semantics, mark the slice `BLOCKED` rather than widening scope.

Remaining Field create/detail convergence stays backlog debt and must be separately bounded later. Reports/Analytics, Settings/Admin and Global convergence remain preserved below.

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
- `DS2-WORK-003` Work detail/management state-surface convergence — `READY` / Product Design must bound one smallest concern before implementation
- further Work convergence beyond WORK003 — `BACKLOG` / explicitly bounded only

### I. Reports / Analytics
- `DS2-REPORT-001` Report shell/navigation/filter grammar — `BACKLOG`
- `DS2-REPORT-002` Metrics/charts/tables and responsive report composition — `BACKLOG`

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