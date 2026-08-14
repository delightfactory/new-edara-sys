# Work Management — Local Pre-Merge Validation

> Run this checklist against a **fresh isolated/local Supabase environment** using the exact head of `feature/work-management`. Do not point these scenarios at production.

## 1. Database bootstrap
- [ ] Start from a clean Supabase/PostgreSQL-compatible database.
- [ ] Apply the repository migration chain in order, including `20260815001000_work_management_governance_continuity.sql`.
- [ ] Confirm no migration fails, hangs, or requires hand editing.
- [ ] Confirm Work tables, RPCs, RLS policies, Storage bucket/policies, realtime publication entries, and cron registrations are present as expected.

## 2. Representative users and RBAC/RLS
Prepare representative users for Own / Team / All behavior plus Restricted/Private visibility.

- [ ] Employee can read/update only the Work scope granted by permissions and direct responsibility.
- [ ] Team manager can manage team work but cannot cross unauthorized scope.
- [ ] `work.items.manage` user can operate the management-level controls.
- [ ] Restricted/Private Work does not leak through list, detail, dependency, notification, attachment, or linked-entity paths.
- [ ] An inactive profile fails Work commands.
- [ ] A profile that remains active while its HR employee record is inactive also fails new Work assignment/execution authority as designed.
- [ ] An active non-HR/system profile remains usable where its role permits it.

## 3. Task lifecycle and concurrency
- [ ] Create and activate a Task with expected outcome and next action.
- [ ] Acknowledge/start it, set Waiting with follow-up, then resume it.
- [ ] Delegate executor without changing accountable owner.
- [ ] Transfer ownership and confirm executor is not silently changed unless explicitly requested.
- [ ] Add checklist, comments/progress, participant, dependency, attachment and entity link.
- [ ] Verify a blocking dependency/checklist prevents invalid completion.
- [ ] Complete, cancel and reopen through supported flows.
- [ ] Open the same Work Item in two sessions; mutate from session A then submit stale version from session B and confirm a version conflict rather than lost update.
- [ ] Replay an identical idempotent operation ID and confirm it does not duplicate the effect.

## 4. Due-date governance
- [ ] Set the first due date directly with a reason.
- [ ] Move the due date earlier directly and verify an audit event.
- [ ] Attempt to extend the due date through the ordinary direct command and confirm server error `APPROVAL_REQUIRED`.
- [ ] Use **طلب تمديد الموعد**, select a published approval template and submit a later date.
- [ ] Confirm the Work Item due date is unchanged while the approval is pending.
- [ ] While the approval is pending, attempt an ordinary due-date change and confirm it is blocked.
- [ ] Approve the request and confirm the new due date is applied once, state version advances, and `work.due_change_approved` appears in the timeline.
- [ ] Repeat with Reject and Changes Required and confirm the old due date remains unchanged.

## 5. Inactive employee / business continuity
- [ ] Create open work where an employee is accountable owner and/or current assignee.
- [ ] Leave their profile active but mark the HR employee record inactive.
- [ ] Confirm the employee disappears from valid assignment candidates and cannot receive a new assignment.
- [ ] Open `/work/manage` → **استمرارية الأعمال** and confirm the user appears with correct owner/assignee/open-work counts.
- [ ] Select an active valid replacement and provide a reason.
- [ ] Bulk-reassign and confirm all matching nonterminal Work Items move to the replacement.
- [ ] Confirm historical `creator_user_id` and `requester_user_id` remain unchanged.
- [ ] Confirm assignee receipt timestamps reset when executor changes.
- [ ] Confirm timeline records `work.ownership_transferred` and/or `work.delegated` with `inactive_user_continuity` source metadata.
- [ ] Refresh the Continuity Center and confirm the resolved orphan no longer appears.

## 6. Requests, Queues and SLA
- [ ] Submit an employee Request using a dynamic intake schema.
- [ ] Confirm routing to its target queue and triage SLA.
- [ ] Triage/assign from an authorized queue role and reject an unauthorized attempt.
- [ ] Confirm requester visibility and queue backlog behavior.

## 7. Approvals and Workflows
- [ ] Publish an Approval template and verify published-version immutability.
- [ ] Exercise sequential, parallel-all and parallel-any approval behavior.
- [ ] Exercise Approve / Reject / Changes Required and approval delegation/acting-for audit.
- [ ] Publish a Workflow template and start a run pinned to the exact version.
- [ ] Exercise Task and Approval steps, dependency activation, structured outputs and condition evaluation.
- [ ] Publish a newer Workflow version and confirm the existing run remains pinned to its original version.

## 8. Recurrence and operational automation
- [ ] Exercise daily, weekly and monthly recurrence generation.
- [ ] Verify strict and single-open overlap policies.
- [ ] Verify pause / resume / stop and an end date.
- [ ] Exercise due-soon, overdue, follow-up, stale, blocked and escalation scanners.
- [ ] Confirm notification cooldown/dedup prevents duplicate spam.
- [ ] Confirm manager escalation does not activate until hierarchy readiness is explicitly validated.

## 9. Attachments, links and notifications
- [ ] Upload an allowed attachment and reject an oversized/unsupported file.
- [ ] Confirm download uses a short-lived signed URL and unauthorized users cannot retrieve the object.
- [ ] Delete attachment metadata through the supported logical flow and confirm UI no longer exposes it.
- [ ] Add each applicable allowlisted business-entity link and reject invalid/nonexistent references.
- [ ] Confirm Work visibility does not grant permission to the linked entity itself.
- [ ] Confirm sensitive notification text/recipients do not leak Restricted/Private context.
- [ ] Confirm notification action URLs deep-link back to the intended Work Item.

## 10. Browser and mobile acceptance
Run at least employee, supervisor and manager personas.

- [ ] `/work`, `/work/new`, `/work/:id`, `/work/team`, `/work/manage` load without console/runtime errors.
- [ ] Dialogs/sheets close correctly and internal content scrolls when viewport height is constrained.
- [ ] RTL alignment and reading order are correct.
- [ ] No table/card/form creates horizontal page overflow on a representative phone viewport.
- [ ] Touch targets remain usable and primary actions are not hidden by the mobile safe area.
- [ ] Realtime changes refresh the Work detail without destroying in-progress form input unexpectedly.

## 11. Release gate
Only after all applicable checks above are green:

- [ ] Record defects and fixes, rerun affected scenarios, and obtain a clean result.
- [ ] Complete independent technical/security review of the final branch diff.
- [ ] Complete business/product acceptance.
- [ ] Obtain explicit approval before merging `feature/work-management` to `main`.
- [ ] Obtain explicit approval before applying Work Management migrations or deploying the feature to production.
