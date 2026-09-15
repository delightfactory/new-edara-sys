# 31 — Design System V2 Agent Team Workstream

## Purpose

Provide one shared operating board for the scheduled Design System V2 agent team.

Authoritative branch: `design-system-v2-development`

`main` is frozen for this workstream until explicit user approval of the completed Design System V2 rollout.

## Team

| Role | Responsibility | May write product code? | May merge? | May deploy? |
|---|---|---:|---:|---:|
| Design Architect | Choose/define the next small slice and acceptance criteria | No | No | No |
| UI Implementer | Implement one READY slice on a feature branch | Yes, UI-only | No | No |
| Quality Reviewer | Review exact PR HEAD against gates and report blockers/GREEN | No | No | No |
| Integrator | Merge GREEN PR into development and update queue | No feature work | Development only | No |

## State machine

`BACKLOG -> READY -> IN_PROGRESS -> REVIEW -> GREEN -> DONE`

Exceptional state: `BLOCKED`

Rules:
- only one implementation slice may be `IN_PROGRESS` or `REVIEW` at a time
- a slice cannot become DONE without exact-head review
- the next slice must not start while the current slice has a blocker
- preview deployment is outside this state machine and only happens on explicit user request

## Current baseline

Already present before the scheduled team starts:

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
- Sidebar V2 feature flag (off by default)
- Dashboard V2 migration
- Customers List V2 migration
- TypeScript fix for Sidebar visible-entry projection on development branch

## Active queue

### DS2-UI-001 — Customer Form: basic-info composition
Status: `READY`
Owner role: UI Implementer

Scope:
- migrate only the `info` tab composition to existing V2 patterns
- use shared PageHeader / Tabs where safe
- use FormSection / FormGrid / FormActions
- preserve every existing field and handler
- preserve customer create/update behavior
- preserve default branch/default contact creation behavior
- preserve GPS behavior
- preserve finance credit permission guard
- preserve lookup loading for governorates/cities/areas/price lists/reps
- preserve edit-mode branches/contacts/credit tabs outside the slice

Explicit exclusions:
- no service changes
- no query changes
- no validation-semantic changes
- no branch/contact CRUD redesign
- no credit-history redesign
- no modal redesign in this slice

Acceptance:
- create and edit modes retain the same fields and submit behavior
- Mobile/Tablet/Desktop form composition is deliberate
- no hidden action becomes unavailable
- focused tests protect submit wiring and credit permission boundary where practical

### DS2-UI-002 — Sales Orders list V2
Status: `BACKLOG`

Goal:
- migrate list presentation and page grammar only
- preserve filtering, pagination/infinite behavior, status mapping, permissions and navigation

### DS2-UI-003 — Sales Order form composition V2
Status: `BACKLOG`

Goal:
- migrate presentation in small sub-slices
- preserve pricing, customer selection, product lines, validation and submit behavior

### DS2-UI-004 — Inventory list/transaction presentation baseline
Status: `BACKLOG`

### DS2-UI-005 — Procurement presentation baseline
Status: `BACKLOG`

### DS2-UI-006 — Finance presentation baseline
Status: `BACKLOG`

### DS2-UI-007 — HR operational/mobile task presentation baseline
Status: `BACKLOG`

## Reviewer checklist

For every implementation PR:

- [ ] PR targets `design-system-v2-development`
- [ ] branch was based on the then-current development HEAD
- [ ] changed files match the declared slice
- [ ] no DB/migration/RPC/service contract changes
- [ ] no permission/RBAC/RLS/route-guard changes
- [ ] no accounting/inventory/credit/HR/sales calculation changes
- [ ] no query/cache semantics changed without explicit authorization
- [ ] responsive behavior is explicit for Mobile/Tablet/Desktop
- [ ] loading/empty/error/disabled/permission states are preserved where relevant
- [ ] RTL/focus/touch concerns are addressed
- [ ] focused tests exist for composition/behavior at risk
- [ ] build/test evidence, when available, applies to the exact HEAD
- [ ] no Vercel auto-deploy enabling change
- [ ] no preview deployment was created by the agent

## Integrator checklist

Before merge:

- [ ] reviewer explicitly reports GREEN
- [ ] no unresolved blocker/review thread
- [ ] exact HEAD matches reviewed HEAD
- [ ] base remains `design-system-v2-development`
- [ ] no unexpected main-branch targeting

After merge:

- [ ] update this workstream status
- [ ] move exactly one next backlog item to READY
- [ ] do not create a preview deployment
- [ ] do not merge development into main

## Preview rule

When the user explicitly asks to see the current version, use a dedicated preview branch from the current development HEAD. Preview-only switches must remain outside the development branch. Share a URL only after Vercel reports READY and the page responds successfully.
