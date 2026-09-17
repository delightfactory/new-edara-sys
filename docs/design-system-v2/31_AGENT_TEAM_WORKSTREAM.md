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
| Design QA | Independent exact-head review | hourly | No | No |
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

Product UI is integrated through `DS2-FIELD-001`.

Latest product integration:
- PR: `#42 — DS2-FIELD-001: Activities list V2 foundation`
- Exact reviewed PR HEAD: `6b7569f3b98f7d8cd9a7588b3ae624e606f82f6b`
- Squash merge commit: `cac61006d5c6ac402a509c2f15fb09ce51bafd50`
- Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
- Runtime/preview/release evidence: not claimed

The development branch now includes semantic foundations, responsive shell/navigation/form/collection/action patterns, Dashboard V2, Customers migrations, Sales list/form/detail foundations, Inventory list/transfer migrations, Procurement list/form-shell migrations, Finance overview/detail foundations, HR operational-task/admin collection proofs, and a Field Activities list proof with one live responsive collection, semantic outcome state, neutral category metadata, canonical action placement and deliberate per-device persistent-create ownership.

## Completed slices

- `DS2-UI-001 — Customer Form: basic-info composition` — `DONE` — PR #28 — merge `cdcc1a57cc3367fdd161fddb3d9e5b42e92e4829` — `SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-UI-002 — Customer detail secondary tabs/patterns` — `DONE` — PR #29 — merge `773085994502401a7368eded20926b1308b62e3f` — `SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-UI-003 — Sales Orders list V2` — `DONE` — PR #30 — merge `e42910fb2bb7c945e67262f610d9e0b630d960a6` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-UI-004 — Sales Order form V2 foundation` — `DONE` — PR #31 — merge `d00faf8e36d40c9dde9df0b2de6dc89737419c5d` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-UI-005 — Sales transaction detail V2` — `DONE` — PR #32 — merge `58b0f3f8f54f04636d3a35dd7d658edb7bcf5068` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-INV-001 — Inventory list surfaces` — `DONE` — PR #34 — merge `805995a5c0d9a118c415d647ed34e63dee326527` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-INV-002 — Transfer/adjustment operational flows` — `DONE` — PR #35 — merge `9328464542b1ca429fd1ec134667f45244215b67` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-PROC-001 — Purchase list surfaces` — `DONE` — PR #36 — merge `936129c69a51237ceeefc7880d9735aa5f584879` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.

### DS2-PROC-002 — Purchase Invoice form decomposition
Status: `DONE`
Merged PR: `#37`
Reviewed HEAD: `4fa613edad180de140b9c7a1c41ceeb9b7e55ee3`
Squash merge: `5b10b9fb578c91798d28526d8de407f63ffcc417`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Runtime/preview/release evidence: not claimed

System result:
- new/editable-draft Purchase Invoice flow uses a thin `PurchaseInvoiceDraftStepper` over shared V2 `Stepper`, preserving page-owned reachability/validation;
- invoice data uses shared `FormSection + FormGrid`; editable wizard actions use shared `FormActions + Button`; status uses semantic `StatusBadge`;
- consumer-owned logical spacing restores inter-section hierarchy without changing shared primitive external margins;
- supplier/product/warehouse, quantity/pricing/tax/totals/landed-cost/accounting/payment/workflow/permissions/services/query/cache/validation truth remains page/domain-owned.

### DS2-FIN-001 — Finance lists and summaries
Status: `DONE`
Merged PR: `#38`
Reviewed HEAD: `b2450e22f9cf58d06780b608dbe6a7b871b53639`
Squash merge: `7a70beccaf961b248f0df045f6bf610df4dfdc84`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Runtime/preview/release evidence: not claimed

System result:
- `VaultsPage` uses shared `MetricGrid + StatCard` and one live `ResponsiveCollection<Vault>` with deliberate Desktop/Tablet/Mobile composition;
- vault type remains neutral categorical metadata and active/inactive remains semantic status;
- page-owned `AppAction` eligibility/order feeds shared `resolveActionSet` placement;
- Finance calculations, balances, posting, permissions, services, query/cache, validation and modal/workflow truth remain page/domain-owned.

### DS2-FIN-002 — Payment Receipt transaction-detail header/action foundation
Status: `DONE`
Merged PR: `#39`
Reviewed HEAD: `0389bb0748a4eb84d40b57707b4b1da47000b369`
Squash merge: `1a9509d598b9b462397838db7adc261c4746c52f`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Runtime/preview/release evidence: not claimed

System result:
- live `PaymentReceiptDetail` consumes a thin Finance adapter over shared `TransactionHeader` with semantic `StatusBadge`;
- existing Finance predicates/callbacks remain page-owned and are declared as `AppAction[]` only for shared device placement;
- `DocumentActions` remains separate output tooling;
- Finance services, custody/vault/destination, validation, invalidation, amount/proof/review-modal and workflow truth remain unchanged.

### DS2-HR-001 — Attendance Check-in operational task controls
Status: `DONE`
Merged PR: `#40`
Reviewed HEAD: `c2a1c0298eaed3b7e1bc38c591d4ca55c91e0f13`
Squash merge: `e9a37c6ade6661bdaf6260f9c93c72dabba60768`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Runtime/preview/release evidence: not claimed

System result:
- live `AttendanceCheckin` now consumes shared `ProcessProgress`, shared `PrimaryTaskAction` over the canonical `Button`, and existing semantic `AlertPanel` feedback;
- `ProcessProgress` receives caller-owned `completed/current/pending` truth, exposes readable non-color state and `aria-current="step"`, and contains no Attendance/GPS/workflow inference;
- `PrimaryTaskAction` remains one in-flow context-dependent operational action, not an `AppAction/resolveActionSet` registry and not a business-eligibility layer;
- `بدء الدوام` / `إنهاء الدوام`, `btn-check-in` / `btn-check-out`, `handleAction(primaryActionType)`, offline/GPS suppression, permission flow, services/RPC/query/cache/tracking/timing/result mapping and `SUCCESS_RESET_MS = 2500` remain page/domain-owned and unchanged;
- only the superseded local action/progress/feedback mini-system and dead visual CSS were retired; broader Attendance/HR surfaces remain outside the slice;
- focused shared-control and live source-contract tests were authored; no executed test/build/lint/runtime/preview PASS is claimed.

### DS2-HR-002 — HR admin lists/forms — Employees administration list
Status: `DONE`
Merged PR: `#41`
Reviewed HEAD: `984750b5d933e26fea62995d3bf782f89a85b509`
Squash merge: `b1c9ae6dd78b57f9708e3e5d40fe0b2baac6adbc`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Runtime/preview/release evidence: not claimed

System result:
- live `EmployeesPage` now uses one `ResponsiveCollection<HREmployee>` with dense Desktop `DataTable`, deliberate Tablet two-column cards and Mobile one-column cards;
- employee summary/card presentation reuses shared `MetricGrid + StatCard + Card + KeyValueList + StatusBadge + Badge + Button`, with semantic workflow status and neutral field/office categorical metadata;
- card action eligibility/callback truth remains page-owned and feeds canonical `AppAction + resolveActionSet`; salary/create/edit/view permissions and the profile route remain unchanged;
- shared `Pagination` was extracted from `DataTable` as presentation only, preserving the established five-page window, callbacks, disabled boundaries, Arabic labels and `aria-current="page"` while applying canonical touch targets through Tablet;
- initial-empty and filtered-empty presentation are distinct; employee search/department/status/page/pageSize, page resets, stats behavior including the pre-existing current-page field metric, and `EmployeeForm` remain unchanged;
- the local Employees filter/search row remains page composition only, not a reusable HR filter grammar; shared filter convergence stays in the component-depth roadmap.

### DS2-FIELD-001 — Activities/visit/call/target lists — Activities list
Status: `DONE`
Merged PR: `#42`
Reviewed HEAD: `6b7569f3b98f7d8cd9a7588b3ae624e606f82f6b`
Squash merge: `cac61006d5c6ac402a509c2f15fb09ce51bafd50`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Runtime/preview/release evidence: not claimed

System result:
- live `ActivitiesPage` now uses one `ResponsiveCollection<ActivityRow>` with dense Desktop `DataTable`, deliberate Tablet two-column cards and Mobile one-column operational cards;
- `ActivityCard` is a thin Field projection over shared `Card + KeyValueList + Badge + StatusBadge + Button + AppAction/resolveActionSet`, while the page owns action eligibility and callbacks;
- Tablet preserves optional `start_time` through the same page-owned formatter used by Desktop; Mobile intentionally retains its prior information density;
- activity outcome is semantic `StatusBadge`; category is represented once as neutral `Badge`; `gps_verified === false` remains neutral read-only metadata (`—`);
- Mobile persistent creation remains owned by the existing shell `new-activity` FAB; Tablet/Desktop retain the PageHeader create action under the unchanged permission and `/activities/new` route;
- initial-empty and filtered-empty presentation remain distinct, and the pre-existing Mobile empty-state CTA + shell FAB coexistence remains a later non-blocking action-convergence/runtime watch;
- activity query/search/filter/paging, team/create/delete permissions, delete mutation/backend authority, routes/customer deep-link, GPS/device/workflow/service/query-cache/validation truth remain page/domain-owned and unchanged.

## Current single READY slice

### DS2-FIELD-002 — Field create/detail flows
Status: `READY`
Owner role: Product Design Director -> UI Production Engineer

Intent:
- continue the Field roadmap from the proven Activities list grammar into one smallest dependency-safe create/detail concern rather than reopening FIELD001 list polishing;
- Product Design Director must inspect representative Field create/detail surfaces on the exact latest Development baseline and bound one presentation-only concern with explicit acceptance criteria;
- prefer established V2 form/detail/action/status/device patterns before adding Field-local presentation grammar;
- preserve activity/visit/call/target query, service, permission, routing, GPS/device, validation, ownership and workflow truth exactly;
- Mobile remains the primary operational field surface; Tablet must be deliberate; Desktop must preserve efficient management/data-entry density and capability parity;
- no DB/migration/RPC/service/RBAC/RLS/business/workflow/query-cache/validation-semantic change, no deployment/preview and no `main` work.

Stop condition:
If the representative Field create/detail concern cannot be improved without changing route/GPS/permission/service/workflow/validation truth, narrow the slice and record the functional issue separately rather than absorbing it into Design System scope.

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
- `DS2-FIELD-002` Field create/detail flows — `READY`

### H. Work Management
- `DS2-WORK-001` Reconcile Work UI island with V2 — `BACKLOG`

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
