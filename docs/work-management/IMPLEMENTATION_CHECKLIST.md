# Work Management — Implementation Completeness Checklist

> هذا الملف Gate ملزم. لا تُعتبر وحدة المهام والمتابعات مكتملة ولا جاهزة للدمج قبل إغلاق كل بند مطلوب أدناه باختبار أو مراجعة صريحة. وجود عائق في أداة أو بيئة لا يحول البند إلى Optional.

## A — Foundation
- [x] Canonical `work_items`
- [x] Owner vs current assignee separation
- [x] Source lineage / source key
- [x] Next Action / due / waiting fields
- [x] Definition-of-Done fields
- [x] Assignment receipt timestamps
- [x] Parent/subtask foundation + `blocks_parent_completion`
- [x] Participants
- [x] Comments + progress updates
- [x] Mentions
- [x] Append-only event table foundation
- [x] Checklists
- [x] Dependencies foundation
- [x] Generic entity links foundation
- [x] Attachment metadata + private-path contract
- [x] Operational indexes
- [x] Private idempotency operation ledger

## B — Security / visibility
- [x] Existing RBAC model reused
- [x] Own / Team / All read model
- [x] Restricted / Private visibility model
- [x] Dependency visibility requires visibility of both ends
- [x] Inactive users fail closed
- [x] Active hierarchy managers only
- [x] Explicit `manage_team` permission in DB seed
- [ ] Frontend official permission registry updated
- [ ] Assignment-scope RPC tests
- [ ] Private/restricted notification leak tests
- [ ] Private attachment storage policies

## C — Atomic command engine
- [x] Operation ledger
- [x] Authority helper layer
- [x] Idempotency helper layer
- [x] Internal validated Task draft writer
- [ ] Public atomic Create Task RPC
- [ ] Create Subtask / parent inheritance
- [ ] Activate RPC
- [ ] First-view receipt RPC/controlled read hook
- [ ] Acknowledge RPC
- [ ] Start RPC
- [ ] Set Waiting RPC
- [ ] Resume RPC
- [ ] Update Next Action RPC
- [ ] Delegate execution RPC
- [ ] Transfer ownership RPC
- [ ] Due-date direct change RPC
- [ ] Due-date change request flow
- [ ] Checklist mutation RPC
- [ ] Comment / Progress Update RPC
- [ ] Participant/follower RPC
- [ ] Mention validation
- [ ] Attachment metadata RPC
- [ ] Entity-link RPC + allowlist/existence/permission validation
- [ ] Add dependency RPC + cycle prevention + deterministic locking
- [ ] Resolve dependency RPC
- [ ] Complete RPC
- [ ] Owner-review completion flow
- [ ] Cancel RPC
- [ ] Reopen RPC
- [ ] Inactive-user orphan/bulk reassignment flow
- [ ] `state_version` concurrency conflict coverage for every mutation

## D — Requests / queues
- [ ] Work queues
- [ ] Queue membership/manager model
- [ ] Request types
- [ ] Intake form schema contract
- [ ] Request submission
- [ ] Independent triage / first-response SLA
- [ ] Queue triage / assignment
- [ ] Cross-department assignment routed through Request where required
- [ ] Queue backlog views

## E — Approvals
- [ ] Versioned approval templates
- [ ] Runtime approval requests
- [ ] Sequential stages
- [ ] Parallel `all`
- [ ] Parallel `any`
- [ ] Approve
- [ ] Reject
- [ ] Changes Required
- [ ] Approval deadlines + escalation
- [ ] Specific delegator → delegate authority resolver
- [ ] Acting-for audit trail
- [ ] Completion approval binding
- [ ] Due-change approval binding

## F — Workflow engine
- [ ] Workflow templates
- [ ] Immutable published versions
- [ ] Step definitions
- [ ] Runtime runs
- [ ] Runtime step instances
- [ ] Task steps
- [ ] Approval steps
- [ ] Step dependencies
- [ ] Structured step outputs
- [ ] Safe condition DSL
- [ ] Cycle validation
- [ ] Active run pinned to exact version

## G — Recurring work
- [ ] Recurrence definitions
- [ ] Occurrence ledger
- [ ] Daily / weekly / monthly
- [ ] No-end-date continuous recurrence
- [ ] End date
- [ ] Pause / resume / stop
- [ ] Strict recurrence — prior overdue stays open while next cycle is created
- [ ] Single-open overlap policy
- [ ] Monthly edge cases / last-day policy
- [ ] Recurring Task instances
- [ ] Recurring Workflow instances
- [ ] Pinned vs latest-published workflow-version policy
- [ ] Recurrence compliance reporting

## H — Operational state / automation
- [ ] Overdue computed flag
- [ ] Follow-up Due computed flag
- [ ] Blocked computed flag
- [ ] Stale computed flag
- [ ] At Risk deterministic rule
- [ ] Escalated overlay
- [ ] Due-warning scanner
- [ ] Follow-up scanner
- [ ] Stale scanner
- [ ] Escalation scanner
- [ ] Notification cooldown/dedup via existing alert state
- [ ] Recurrence generator cron
- [ ] Workflow activator cron
- [ ] Hierarchy readiness gate before automatic manager escalation

## I — Notifications / Action Inbox
- [ ] Work event catalogue seeded
- [ ] Existing `tasks` notification category reused
- [ ] Assignment notifications
- [ ] Delegation / ownership notifications
- [ ] Mentions
- [ ] Follow-up due
- [ ] Due soon / overdue
- [ ] Blocked / unblocked
- [ ] Approval requested / decided
- [ ] Escalations
- [ ] Recurrence generated / overlap
- [ ] Actionable quick actions call secure RPCs
- [ ] `مطلوب مني الآن` Action Inbox

## J — UX
- [ ] `/work` module shell
- [ ] My Action Inbox
- [ ] Work Item details
- [ ] Responsibility / current-ball-holder card
- [ ] Next Action card
- [ ] Checklist UI
- [ ] Discussion / progress UI
- [ ] Attachments/evidence UI
- [ ] Related entities UI
- [ ] Immutable timeline UI
- [ ] Create Task UX
- [ ] Request intake UX
- [ ] Approval UX
- [ ] Recurrence editor
- [ ] Workflow template/run UX
- [ ] Team supervisor views
- [ ] Operations Control Center
- [ ] RTL
- [ ] Mobile-first / internal scroll / no horizontal overflow
- [ ] Realtime invalidation integration
- [ ] Push deep links

## K — Integration
- [ ] Activities remain separate and linkable
- [ ] Customer links
- [ ] Sales order links
- [ ] Payment/collection links
- [ ] Supplier links
- [ ] Purchase/invoice links
- [ ] Product links
- [ ] Warehouse links
- [ ] Employee links
- [ ] Visit/activity links
- [ ] Target links
- [ ] Entity visibility never inherited from Work visibility

## L — Final verification gates
- [ ] SQL executes on isolated PostgreSQL 17 / Supabase-compatible environment
- [ ] Migration contract tests
- [ ] State-machine tests
- [ ] RLS matrix tests
- [ ] Idempotency tests
- [ ] Concurrency tests
- [ ] Dependency-cycle tests
- [ ] Approval edge-case tests
- [ ] Workflow-version tests
- [ ] Recurrence edge-case tests
- [ ] Notification leak/dedup tests
- [ ] TypeScript passes
- [ ] Production frontend build passes
- [ ] Existing regression suite reviewed
- [ ] Mobile smoke tests
- [ ] Functional completeness review
- [ ] Technical/security review
- [ ] No production migration before explicit release gate
- [ ] No merge to `main` before double review
