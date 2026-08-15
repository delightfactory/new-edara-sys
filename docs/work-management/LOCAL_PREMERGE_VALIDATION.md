# Work Management — Local Pre-Merge Validation

> Run this checklist against the established **sanitized local baseline** for NEW-EDARA-SYS, fully isolated from production, using the exact head of `feature/work-management`. Never point these scenarios at production.

## 0. Pinned local toolchain
The acceptance baseline is the same toolchain used by GitHub Actions:

- Node.js **22** (`.nvmrc` is committed at repository root).
- npm 10.x as shipped with the current Node 22 CI image.
- Run `nvm use` (or the equivalent Node-version manager command) before dependency install/tests.
- If a test fails only under a different major Node/npm combination, reproduce it first on Node 22 before classifying it as a Work Management blocker.

The repository currently has pre-existing package-lock normalization drift. Until that repository-wide maintenance item is closed, validate using the same deterministic sequence used by Work Management CI:

```bash
npm install --package-lock-only --ignore-scripts --no-audit --no-fund
npm ci --no-audit --no-fund
npm test
npm run build
```

A raw `npm ci` failure caused solely by the known repository-wide lockfile drift is tracked separately from Work Management functional acceptance; failures that remain after the approved normalization sequence are blockers.

## 1. Database acceptance baseline
Work Management acceptance does **not** require rebuilding the entire legacy NEW-EDARA-SYS migration history from an empty database. The repository contains legacy migrations and seed history with independent bootstrap debt that predates this module.

Use the already established sanitized isolated local database baseline and validate only the Work Management migration chain on top of it.

Validation:
- [ ] Confirm the database is local/isolated and contains no production URL, production key, production network target, active cron delivery, or queued `pg_net` work.
- [ ] Apply every Work Management migration in repository order through the latest Work Management migration, with no manual editing of those Work Management SQL files.
- [ ] Confirm every Work Management migration succeeds on the sanitized baseline.
- [ ] Confirm Work tables, RPCs, RLS policies, Storage bucket/policies, realtime publication entries, and Work cron registrations are present as expected.
- [ ] Record any failure in a Work Management migration as a module blocker.

> Full clean bootstrap of the repository's historical migrations is a separate repository-infrastructure maintenance track and must not be conflated with this module's release acceptance.

## 2. Representative users and RBAC/RLS
Prepare representative users for Own / Team / All behavior plus Restricted/Private visibility.

- [ ] Employee can read/update only the Work scope granted by permissions and direct responsibility.
- [ ] Team manager can manage team work but cannot cross unauthorized scope.
- [ ] `work.items.manage` user can operate the management-level controls.
- [ ] `/work/team` loads through the supervisor overview without PostgreSQL permission or return-type errors.
- [ ] `/work/manage` → Queues loads active/inactive configuration permitted to queue managers without `42501` helper errors.
- [ ] Restricted/Private Work does not leak through list, detail, dependency, notification, attachment, mention, or linked-entity paths.
- [ ] An inactive profile fails Work commands.
- [ ] A profile that remains active while its HR employee record is inactive also fails new Work assignment/execution authority as designed.
- [ ] An active non-HR/system profile remains usable where its role permits it.

## 3. Task lifecycle and concurrency
- [ ] Create and activate a Task with expected outcome and next action.
- [ ] Acknowledge/start it, set Waiting with follow-up, then resume it.
- [ ] Delegate executor without changing accountable owner.
- [ ] Transfer ownership and confirm executor is not silently changed unless explicitly requested.
- [ ] Add checklist, comments/progress, participant, dependency, attachment and entity link.
- [ ] Add a comment/progress update with one or more UI-selected mentions and confirm only users who can already see the Work Item are offered.
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
- [ ] Confirm download requests a **60-second signed URL** and unauthorized users cannot retrieve the object.
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
Only after all applicable Work Management checks above are green:

- [ ] Record defects and fixes, rerun affected scenarios, and obtain a clean result.
- [ ] Complete independent technical/security review of the final branch diff.
- [ ] Complete business/product acceptance.
- [ ] Obtain explicit approval before merging `feature/work-management` to `main`.
- [ ] Obtain explicit approval before applying Work Management migrations or deploying the feature to production.

Repository-wide legacy migration bootstrap repair and package-lock cleanup remain independent maintenance tracks unless they are shown to cause a Work Management runtime, migration, test, type-check, or build failure under the approved acceptance baseline.
