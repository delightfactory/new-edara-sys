# 31 — Design System V2 Agent Team Workstream

## Purpose

Provide one shared operating board for the autonomous, around-the-clock Design System V2 team.

Authoritative branch: `design-system-v2-development`

`main` is frozen for this workstream until explicit user approval of the completed Design System V2 rollout.

The team is building a complete product language, not completing a short page-restyle checklist. The product quality authority is `32_DESIGN_SYSTEM_NORTH_STAR.md`. Test/evidence authority is `33_TEST_AND_VALIDATION_POLICY.md`.

## Team

| Role | Responsibility | Normal cadence | May write product code? | May merge? | May deploy? |
|---|---|---|---:|---:|---:|
| Product Design Director | System identity, architecture, next slice, design quality | every 2 hours | No | No | No |
| UI Production Engineer | Implement/repair the single active UI slice | hourly | Yes, UI-only | No | No |
| Design QA | Independent exact-head product/design/technical review | hourly | No | No | No |
| Development Integrator | Merge GREEN-DEV PR and advance queue | hourly | No feature work | Development only | No |

## Continuous state machine

`BACKLOG -> READY -> IN_PROGRESS -> REVIEW -> GREEN-DEV -> DONE`

Exceptional state: `BLOCKED`

Release/runtime evidence remains separate from development integration.

Rules:
- only one implementation slice may be `IN_PROGRESS` or `REVIEW` at a time
- agents run around the clock and continue the same slice rather than waiting for a long batch window
- the Product Design Director may refine future sequencing while an active slice exists, but may not start competing implementation
- the UI Engineer may keep improving the same active PR on each hourly run
- Design QA may re-review each materially changed HEAD
- Integrator may act as soon as exact HEAD is GREEN-DEV
- a slice cannot become DONE without exact-head independent review
- next implementation slice must not start while current slice has a material blocker
- if a role has nothing actionable, it no-ops instead of inventing work
- preview deployment is outside this state machine and only happens on explicit user request

## Repository-native team communication

The repository is the team's shared room and durable memory. The four scheduled agents must behave as one informed team rather than isolated jobs.

The authoritative communication contract is:
- `docs/design-system-v2/34_AGENT_TEAM_COMMUNICATION_PROTOCOL.md`

Before any material action, every role must read, in addition to the normal governance documents:
- `docs/design-system-v2/34_AGENT_TEAM_COMMUNICATION_PROTOCOL.md`
- `team/design-system-v2/TEAM_MEMORY.md`
- `team/design-system-v2/DESIGN_DIRECTOR_STATE.md`
- `team/design-system-v2/UI_IMPLEMENTATION_STATE.md`
- `team/design-system-v2/DESIGN_QA_STATE.md`
- `team/design-system-v2/INTEGRATION_STATE.md`
- `team/design-system-v2/DECISION_LOG.md`
- issue #27 and the active PR when one exists

Communication rules:
- each role owns and updates only its own state file in normal operation
- Product Design Director and Development Integrator keep `TEAM_MEMORY.md` synchronized when direction or integrated baseline materially changes
- all material handoffs carry exact SHA/baseline, what changed, evidence, invariants to preserve, required next action, blocker level and freshness condition
- peer state is context, not a substitute for independent professional judgment
- Design QA must always judge the exact PR HEAD independently
- issue #27 is a concise chronological event stream for material events, not hourly status chatter
- no-op runs create no repository noise
- a mismatch between Workstream, Team Memory, implementation state and active PR is a coordination blocker; do not start a second slice until reconciled

This model follows the same repository-as-shared-room principle that proved effective in the Garment Ops autonomous team.

## GitHub Actions / execution budget

- Hosted GitHub Actions are forbidden to this workstream while quota protection is active.
- Development PRs target `design-system-v2-development`; the development copy of the Work Management workflow is constrained to base `main` so these PRs do not consume Actions quota.
- Agents continue to AUTHOR focused tests.
- Reviewers distinguish source review from executed evidence.
- Development merge evidence is normally `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED` unless an approved local runtime actually executed tests.
- Known real build/type failures always block GREEN-DEV.
- Manual Vercel build/runtime evidence occurs only when the owner explicitly requests a preview.

See `33_TEST_AND_VALIDATION_POLICY.md`.

## Current baseline

Integrated through `DS2-UI-001` on merge commit `cdcc1a57cc3367fdd161fddb3d9e5b42e92e4829` before the post-merge governance synchronization commits.

The development branch includes:

- Design System V2 blueprint and semantic foundations
- Button/IconButton and form primitives
- status/feedback/surface/navigation patterns
- responsive collection pattern
- action-registry core
- form-composition patterns
- App Shell navigation registry
- mobile shell registry integration
- deliberate Tablet shell behavior
- Sidebar information-architecture model
- Sidebar V2 isolated renderer
- Sidebar V2 feature flag (off by default on development)
- Dashboard V2 migration
- Customers List V2 migration
- Customer basic-info form V2 composition (`DS2-UI-001`)
- TypeScript-safe Sidebar visible-entry projection fix on development
- North Star / professional quality specification
- explicit test/validation policy without GitHub Actions
- repository-native Team Memory, role-state handoffs and durable decision log

## Completed slice

### DS2-UI-001 — Customer Form: basic-info composition
Status: `DONE`
Merged PR: `#28`
Reviewed exact PR HEAD: `b6bfceeb8327437e274222c7e2f75e83c4a65061`
Squash merge commit: `cdcc1a57cc3367fdd161fddb3d9e5b42e92e4829`
Evidence: `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Runtime/preview/release evidence: not claimed

System result:
- Customer basic-info form now uses shared `PageHeader`, `FormSection`, `FormGrid`, and `FormActions` composition.
- Existing create/update, GPS, credit permission, lookup, default branch/contact and secondary Customer behaviors remain preserved.
- Mobile/Tablet/Desktop form density remains governed by shared V2 contracts.
- Retained legacy Customer section-switch controls are explicitly non-submitting ordinary buttons; incomplete ARIA Tabs semantics were intentionally removed.
- Complete Tabs/SubNav keyboard/focus/tabpanel semantics remain future shared component-depth work.

## Active implementation slice

### DS2-UI-002 — Customer detail secondary tabs/patterns
Status: `IN_PROGRESS`
Owner role: UI Production Engineer
Draft PR: `#29`
Feature branch: `ds2/customer-secondary-tabs-v2`
Starting baseline: `d05a1d06a4214d5a4e0b222c5e7586155a9841f2`
Current implementation evidence: `TESTS_AUTHORED_NOT_EXECUTED`

System intent:
Continue the Customer golden flow by migrating secondary edit surfaces into the shared V2 language, while using the proven need for the existing shared complete Tabs contract rather than creating Customer-local navigation semantics.

Scope direction:
- branches / contacts / credit secondary surfaces
- adopt shared Tabs section-switch grammar at the minimum reusable boundary required by the real Customer screen
- preserve all existing tab visibility, counts, handlers, permissions and business behavior
- keep dialogs/destructive confirmation redesign deferred until shared overlay contracts are explicitly ready
- preserve the completed basic-info V2 composition without reopening DS2-UI-001

Acceptance direction:
- no partial ARIA Tabs widget contract
- shared Tabs keyboard/focus/panel relationships remain complete
- Mobile/Tablet/Desktop section navigation remains deliberate and touch-safe
- no Customer-local mini design system
- no backend/service/query/permission/business behavior changes
- focused test artifacts protect the material navigation/permission/composition contract; execution evidence remains governed by `33_TEST_AND_VALIDATION_POLICY.md`

## Product migration roadmap

The Director selects the smallest dependency-safe slice from this roadmap; ordering inside a module may be decomposed further.

### A. Golden flows

#### DS2-UI-002 — Customer detail secondary tabs/patterns
`IN_PROGRESS`
- branches / contacts / credit tab surfaces
- Draft PR #29 is the single active implementation PR
- dialogs and destructive confirmations only after shared overlay contracts are ready
- adopt the already-existing complete shared Tabs semantics; do not repeat partial legacy ARIA semantics

#### DS2-UI-003 — Sales Orders list V2
`BACKLOG`
- responsive collection
- filters/status/action hierarchy
- preserve data/navigation/permissions

#### DS2-UI-004 — Sales Order form V2 foundation
`BACKLOG`
- decompose presentation into shared Field/Combobox/FormSection/Stepper/ProductLine patterns
- small sub-slices; no pricing/customer/product business logic migration

#### DS2-UI-005 — Sales transaction detail V2
`BACKLOG`
- transaction header / status / financial summary / action hierarchy

### B. Shared component-depth program

These are opened when a migrated screen proves a recurring gap; they are not speculative rewrites.

- FilterBar decomposition and Mobile filter-sheet contract
- DataTable V2 hardening and table action/accessibility contract
- MobileDataCard semantic migration from legacy DataCard
- Modal/ResponsiveSheet/ConfirmDialog V2 convergence
- Combobox/AsyncCombobox keyboard/focus hardening
- Tabs/SubNav/SegmentedControl adoption cleanup — now explicitly proven by the Customer secondary-section flow; existing shared contract should be adopted before any extension
- EntityHeader / TransactionHeader
- Timeline / ActivityFeed / AuditTimeline
- FinancialSummary / InventorySummary / ApprovalPanel
- BulkActionBar / CommandBar
- File/proof upload, camera and GPS interaction grammar
- toast/alert/inline-validation convergence
- Skeleton/Loading/Empty/Error/Permission/Offline/Sync state grammar
- chart/report legend/metric grammar

### C. Inventory

#### DS2-INV-001 — Inventory list surfaces
`BACKLOG`
Warehouses / stock / movements / valuation list grammar.

#### DS2-INV-002 — Transfer/adjustment operational flows
`BACKLOG`
Mobile-first transaction forms/actions while preserving inventory semantics.

### D. Procurement

#### DS2-PROC-001 — Purchase list surfaces
`BACKLOG`
Invoices/returns responsive grammar.

#### DS2-PROC-002 — Purchase Invoice form decomposition
`BACKLOG`
Large form presentation decomposition only; business behavior preserved.

### E. Finance

#### DS2-FIN-001 — Finance lists and summaries
`BACKLOG`
Vault/custody/payment/expense/account/journal/ledger visual grammar.

#### DS2-FIN-002 — Financial transaction/detail/action patterns
`BACKLOG`
High-trust money/status/confirmation hierarchy.

### F. HR / People

#### DS2-HR-001 — Mobile operational tasks
`BACKLOG`
Attendance/check-in as reference for OperationalTaskScreen / progress / connectivity / GPS grammar.

#### DS2-HR-002 — HR admin lists/forms
`BACKLOG`
Employees, attendance, leave, advances, payroll-related presentation.

### G. Field Activities / Targets

#### DS2-FIELD-001 — Activities/visit/call/target lists
`BACKLOG`
Mobile-first field operations, GPS/phone/action priority.

#### DS2-FIELD-002 — Field create/detail flows
`BACKLOG`
Shared operational forms/timelines/actions.

### H. Work Management

#### DS2-WORK-001 — Reconcile Work UI island with V2
`BACKLOG`
Preserve its strong responsive architecture while replacing standalone visual language with shared V2 grammar.

### I. Reports / Analytics

#### DS2-REPORT-001 — Report shell/navigation/filter grammar
`BACKLOG`

#### DS2-REPORT-002 — Metrics/charts/tables and responsive report composition
`BACKLOG`

### J. Settings / Administration

#### DS2-ADMIN-001 — Users/roles/settings/audit surfaces
`BACKLOG`
Includes PermissionMatrix pattern and touch/accessibility behavior.

### K. Global convergence and cleanup

#### DS2-GLOBAL-001 — Global style debt and inline-style reduction
`BACKLOG`
Only after shared patterns are proven.

#### DS2-GLOBAL-002 — Dark mode / RTL / long Arabic / numeric stress pass
`BACKLOG`

#### DS2-GLOBAL-003 — Accessibility/focus/touch/motion pass
`BACKLOG`

#### DS2-GLOBAL-004 — Legacy component/CSS retirement
`BACKLOG`
Repository search must prove no remaining consumers.

#### DS2-GLOBAL-005 — Final visual/system consistency audit
`BACKLOG`
Verify all major modules read as one product and satisfy North Star completion definition.

## Reviewer checklist

For every implementation PR:

- [ ] PR targets `design-system-v2-development`
- [ ] branch was based on then-current development HEAD
- [ ] changed files match declared slice
- [ ] no DB/migration/RPC/service contract changes
- [ ] no permission/RBAC/RLS/route-guard changes
- [ ] no accounting/inventory/credit/HR/sales calculation changes
- [ ] no query/cache semantics changed without explicit authorization
- [ ] solution advances the shared system rather than a page-local visual fork
- [ ] hierarchy/action priority/spacing/semantic tone meet North Star
- [ ] responsive behavior explicit for Mobile/Tablet/Desktop
- [ ] loading/empty/error/disabled/read-only/permission states preserved where relevant
- [ ] RTL/Arabic wrapping/focus/touch/accessibility considered
- [ ] focused tests exist for composition/behavior at risk or rationale is documented
- [ ] executed vs non-executed evidence is honestly labeled
- [ ] known build/type failure does not remain open
- [ ] no Vercel auto-deploy enabling change
- [ ] no preview deployment was created by an agent
- [ ] no GitHub Actions/CI was triggered or rerun by an agent

## Integrator checklist

Before merge:

- [ ] reviewer explicitly reports `AGENT-REVIEW: GREEN-DEV`
- [ ] marker references exact current HEAD
- [ ] reviewer records `SOURCE_REVIEW_PASS`
- [ ] test evidence label is present
- [ ] no unresolved material blocker/review thread
- [ ] base remains `design-system-v2-development`
- [ ] no unexpected `main` targeting
- [ ] no hosted-CI requirement was invented

After merge:

- [ ] update completed slice to DONE with merge SHA/evidence
- [ ] move exactly one dependency-safe next roadmap item to READY
- [ ] preserve long-horizon full-system roadmap
- [ ] refresh `team/design-system-v2/TEAM_MEMORY.md` when integrated truth changes
- [ ] do not create preview deployment
- [ ] do not merge development into main

## Preview rule

When the user explicitly asks to see the current version, use a dedicated preview branch from the frozen current development HEAD. Preview-only switches and deployment-enabling config remain outside development. Build failures discovered there must be fixed back on development. Share URL only after Vercel reports READY and page responds successfully.

## End condition

This autonomous workstream continues until the North Star completion definition is met, not merely until the current queue of page migrations is exhausted.
