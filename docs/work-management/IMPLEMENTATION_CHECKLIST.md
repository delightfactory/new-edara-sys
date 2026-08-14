# Work Management — Implementation Closure Checklist

> **Code status:** functionally complete on `feature/work-management` through `bd5c706e` (2026-08-15).
>
> This document separates **implemented code** from **release acceptance**. A checked implementation item means the capability exists in the branch and is covered by code review/contract tests where applicable. It does **not** authorize merge, production migration, or deployment.

## 1 — Domain foundation
- [x] Canonical `work_items` bounded context, separate from field `activities`
- [x] Canonical lifecycle: `draft / open / in_progress / waiting / pending_approval / done / cancelled`
- [x] Accountable owner separated from current assignee
- [x] Definition of Done, expected outcome, next action, due/follow-up and waiting context
- [x] Parent/subtask model with blocking completion semantics
- [x] Participants, comments/progress updates and validated mentions
- [x] Append-only `work_events` timeline with DB mutation protection
- [x] Checklists, dependencies and cycle prevention
- [x] Generic allowlisted entity links without inheriting linked-entity permissions
- [x] Private attachment metadata/storage contract and signed downloads
- [x] Operational indexes, state versioning and private idempotency operation ledger

## 2 — Security, authority and visibility
- [x] Existing RBAC/check_permission model reused
- [x] Own / Team / All authority scopes
- [x] Standard / Restricted / Private visibility behavior
- [x] Dependency access requires visibility of both work items
- [x] Inactive users fail closed
- [x] HR-deactivated employees fail closed even if their profile remains active
- [x] Non-HR system users remain supported when their profile is active
- [x] Active hierarchy/manager checks and hierarchy readiness gate
- [x] Official frontend permission registry and Role Editor integration
- [x] Server-filtered assignment/participant directories
- [x] Private/restricted notification recipient filtering
- [x] Private Work attachment storage policies

## 3 — Atomic Task command engine
- [x] Create Task and Subtask
- [x] Activate / first-view receipt / acknowledgement / start
- [x] Waiting / resume / next action
- [x] Delegate execution / transfer accountability
- [x] Direct due-date change with mandatory reason
- [x] Server-enforced due-date extension approval barrier
- [x] Checklist, comment/update, participant and mention commands
- [x] Attachment metadata commands and logical-delete handling
- [x] Entity-link commands with allowlist/existence validation
- [x] Dependency add/resolve with cycle prevention and deterministic locking
- [x] Completion, owner-review completion and approval-bound completion
- [x] Cancel and reopen
- [x] Inactive-user orphan detection and management-only bulk reassignment
- [x] Optimistic concurrency / `state_version` on state-changing commands
- [x] Idempotent operation IDs on sensitive commands

## 4 — Requests and Queues
- [x] Queues, memberships and queue managers
- [x] Versioned/configurable Request Types and intake schemas
- [x] Employee request submission UX
- [x] Independent triage / first-response SLA
- [x] Atomic triage and assignment
- [x] Cross-department request routing model
- [x] Queue backlog and management views

## 5 — Approval Engine
- [x] Versioned approval templates and immutable published versions
- [x] Runtime approval requests
- [x] Sequential stages
- [x] Parallel `all` and `any`
- [x] Approve / Reject / Changes Required
- [x] Stage deadlines and operational escalation support
- [x] Specific delegator → delegate resolution
- [x] Acting-for audit trail
- [x] Completion approval binding
- [x] Due-date extension approval binding
- [x] Dedicated due-extension UX; due date changes only after final approval

## 6 — Workflow Engine
- [x] Versioned templates and immutable published versions
- [x] Step definitions and runtime runs/instances
- [x] Task and Approval steps
- [x] Step dependencies
- [x] Structured outputs
- [x] Safe condition DSL
- [x] Cycle validation
- [x] Active runs pinned to exact template versions
- [x] Workflow template/run management UX

## 7 — Recurring Work
- [x] Recurrence definitions and occurrence ledger
- [x] Daily / weekly / monthly schedules
- [x] Open-ended and end-dated recurrence
- [x] Pause / resume / stop
- [x] Strict and single-open overlap policies
- [x] Monthly edge/last-day handling
- [x] Recurring Task and Workflow instances
- [x] Pinned vs latest-published workflow-version policy
- [x] Recurrence compliance reporting and management editor

## 8 — Operational intelligence, automation and notifications
- [x] Overdue / Follow-up Due / Blocked / Stale / At Risk computed flags
- [x] Escalated operational overlay
- [x] Due / follow-up / stale / escalation scanners
- [x] Existing `notification_alert_state` cooldown/dedup integration
- [x] Recurrence generator and Workflow activation scheduling
- [x] Existing `tasks` notification category reused
- [x] Assignment, delegation, ownership, mention, due, blocked, approval, escalation and recurrence notifications
- [x] Action URLs / deep links to Work Item
- [x] `مطلوب مني الآن` Action Inbox

## 9 — UX and operational administration
- [x] `/work` employee shell and Action Inbox
- [x] `/work/new` Create Task UX
- [x] Request intake UX
- [x] `/work/:id` detail, responsibility, next action and immutable timeline
- [x] Checklist, discussion/progress, attachments and related entities
- [x] Cancel/reopen, delegation, ownership, due, subtask, participants and escalation controls
- [x] Approval decisions and due-extension request UX
- [x] Team supervisor view `/work/team`
- [x] Management center `/work/manage`
- [x] Queue/Request/Approval/Workflow/Recurrence/Policy management
- [x] Business continuity center for inactive employee responsibilities
- [x] RTL/responsive implementation and Work-detail realtime invalidation

## 10 — Integration model
- [x] `activities` remain independent and linkable
- [x] Allowlisted links cover customers, sales orders, payment/collection, suppliers, purchases/invoices, products, warehouse, employees, visits/activities and targets as supported by the schema
- [x] Work visibility never grants visibility to a linked business entity

## 11 — Automated verification completed on branch
- [x] Work Management foundation/migration contract tests
- [x] State-model and runtime-hardening contract tests
- [x] Permission/RLS contract tests
- [x] Request/Queue contract tests
- [x] Approval and workflow-version/pinning contract tests
- [x] Recurrence contract tests
- [x] Notification/storage contract tests
- [x] Operational Action Inbox contract tests
- [x] UI/supervisor/functional-closure contract tests
- [x] Due-governance and inactive-user continuity contract tests
- [x] Full repository test suite passed in GitHub Actions on `bd5c706e`
- [x] TypeScript type-check passed on `bd5c706e`
- [x] Production frontend build passed on `bd5c706e`

## 12 — Release acceptance gates — intentionally still open
These are not coding gaps. They require an isolated/local Supabase runtime and/or human acceptance before merge/release.

- [ ] Apply the complete migration chain on a fresh isolated Supabase/PostgreSQL environment
- [ ] Run role/RLS runtime matrix with representative Own / Team / All users
- [ ] Run multi-session optimistic-concurrency/idempotency scenarios against the real database
- [ ] Run end-to-end Approval / Workflow / Recurrence scheduler scenarios against the isolated database
- [ ] Run attachment upload/download/delete against isolated Supabase Storage
- [ ] Run inactive-HR employee continuity scenario end-to-end
- [ ] Run browser smoke tests for employee, supervisor and manager personas
- [ ] Run mobile visual/interaction smoke tests with no horizontal overflow
- [ ] Business/product acceptance of terminology and flows
- [ ] Final independent technical/security review of the complete branch diff
- [ ] Explicit approval to merge to `main`
- [ ] Explicit approval before any production database migration or deployment

## Closure rule

The Work Management cube is **Code Complete** on this feature branch when Sections 1–11 are green. It is **not Production Released** until every applicable item in Section 12 has been performed and explicitly accepted. No unchecked release gate may be silently converted into an assumption.
