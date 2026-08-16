# Work Management — Runtime Summary

## Status

The Work Management bounded context is **Code Complete** on `feature/work-management` through commit `bd5c706e` (2026-08-15). GitHub Actions passed the full test suite, TypeScript type-check, and production frontend build on that commit.

This status does **not** mean the feature has been merged or released. No Work Management production migration or deployment has been performed from this closure work.

## Runtime model

Work state changes use server-side atomic RPCs rather than direct client state mutation. Sensitive operations carry an `operation_id` for idempotency and an expected `state_version` for optimistic concurrency. The canonical operational audit trail is append-only `work_events`.

Delegation changes the current executor only. Ownership transfer changes final accountability. Historical creator/requester identity is not rewritten by responsibility changes. Waiting requires an explicit next action and follow-up context. Completion validates Definition-of-Done requirements, blocking checklist/dependency rules, and any configured approval path.

## Due-date governance

A direct due-date command remains available for setting the first due date, clearing it, or moving an existing due date earlier, with a mandatory reason. **Extending an existing due date is rejected by the server unless it goes through the Approval Engine.**

The dedicated due-extension flow creates a `due_change` approval request against a published approval template. The current due date remains unchanged while approval is pending. Final approval applies the requested date atomically and records `work.due_change_approved`; rejection or Changes Required leaves the current due date unchanged and records the corresponding event.

A pending due-extension approval also blocks an ordinary direct due-date change, preventing stale approvals from later applying over a conflicting date.

## Employee availability and business continuity

Work availability now considers both authentication/profile status and HR employment status:

- an inactive profile fails closed;
- a user with HR records must have at least one active HR employee record;
- an active non-HR/system user remains supported when no HR employee record exists.

New assignments therefore cannot be directed to an employee who has left service merely because their profile was not deactivated at the same time.

The management center includes an **استمرارية الأعمال** view that detects open work whose accountable owner or current assignee is no longer available. A manager with `work.items.manage` can bulk-reassign those live responsibilities to a valid replacement. The operation is idempotent, locks the affected work, bumps state versions, preserves creator/requester history, and records existing ownership/delegation events with continuity metadata.

## Functional scope closed in the branch

The branch contains the Work Item lifecycle and collaboration model, Requests and Queues, versioned Approvals, versioned Workflow Engine, Recurrence, operational flags and scanners, Action Inbox, notifications, private attachments, related business-entity links, employee/team/management UX, realtime detail refresh, and the final due-governance/business-continuity controls.

See `IMPLEMENTATION_CHECKLIST.md` for the implementation-vs-release boundary and `LOCAL_PREMERGE_VALIDATION.md` for the required isolated-environment acceptance run.
