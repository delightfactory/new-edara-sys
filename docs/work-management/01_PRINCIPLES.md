# Work Management — Domain Principles

## Scope
The module is an Operational Work Management layer, not a to-do list and not a replacement for `activities`.

Supported constructs over one engine:
- Task
- Request
- Workflow Run
- Approval

## Actor identity
All work actors use `profiles.id` / Auth user UUIDs. Organisational hierarchy is resolved through `hr_employees.user_id` when an employee record exists.

This lets system users participate even if they do not have a complete HR employee record and aligns with notifications plus existing branch/department manager fields.

## Responsibility
Each activated Work Item has:
- creator
- requester when applicable
- accountable owner
- assignee/executor or queue
- approvers when approval is active
- participants/followers

Delegation changes the executor, not the accountable owner.
Ownership transfer changes accountability and must be logged.
Mention does not assign work.
HR authority delegation remains separate from Work delegation.

## Statuses
Primary statuses:
- `draft`
- `open`
- `in_progress`
- `waiting`
- `pending_approval`
- `done`
- `cancelled`

Computed flags, not statuses:
- overdue
- follow-up due
- blocked
- stale
- at risk
- escalated

## Next Action
For `waiting`, the following are mandatory:
- waiting reason
- waiting-on type/label
- next action text
- next action timestamp

Due Date, Follow-up Date and SLA thresholds are separate concepts.

## Follow-up vs Subtask
Ordinary follow-up remains on the same Work Item using `waiting + next_action_at`.
A Subtask is created only when separate responsibility or separately measurable work exists.

## Recurrence
Recurring work consists of one definition and independent occurrence instances.
Default overlap policy is `strict`: each cycle generates its own Work Item even if a previous cycle is overdue.
Optional `single_open` records the new cycle as an overlap without silently moving the original due date.

If every cycle has an independent deliverable, use recurrence. If responsibility is continuous, use one long-lived Work Item with changing Next Actions.

## Security
Core mutations are server-side atomic RPC operations. RLS protects reads. Client users do not receive unrestricted writes to core Work tables.
A link to another domain entity never grants permission to view that entity.

## Audit
`work_events` is append-only and is the operational source of truth. Existing `audit_logs` may receive mirrored security/admin events but is not the workflow history.

## UX rule
The system must always make these understandable:
- who owns the result;
- who currently has the ball;
- what happens next;
- when it is due/followed up;
- why it is blocked or late.
