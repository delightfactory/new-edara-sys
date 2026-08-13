# Work Management — Formal Double Review

**Branch:** `feature/work-management`  
**Date:** 2026-08-13  
**Production changes:** None

## Final verdict

**PASS after amendments — READY FOR Migration A on the development branch only.**

The review did not grant a blind first-pass approval. Functional gaps were found and incorporated into specification v1.1 before the technical/security decision.

## Functional amendments now binding

- Next Action is required/derivable for every active Work Item; Waiting always requires explicit follow-up.
- Active work has an expected outcome; completion records the actual completion result/output.
- Required child work is represented and can block parent completion.
- Assignment receipt/first-view/optional acknowledgement are distinct from meaningful work activity.
- Request triage SLA is separate from resolution due and follow-up due.
- Approval runtime steps have due times and explicit completion-template binding.
- Workflow steps have structured outputs; approval-step runtime behavior is explicit.
- Recurring workflows declare pinned vs latest-published version policy.
- Assignment authority is scope-based; broad read does not imply assign; unauthorised cross-department work becomes a Request.
- Reusable task templates and progress-update comments are included.

## Technical/security controls now binding

- Core state mutations are atomic/idempotent RPCs; actor comes from `auth.uid()`.
- Work actor identity is `profiles.id`; organisational hierarchy resolves through HR only when needed.
- RLS helpers must avoid recursion, use locked search paths, and expose only intended EXECUTE privileges.
- State mutations use row locks + expected state version.
- Dependency cycle checks run under deterministic locking.
- Work attachments use a private Work-ID-bound bucket policy modelled on the strict `visit-proofs` pattern.
- Mentions and notifications may not leak restricted/private Work content.
- Cron processing is set-based, private, idempotent and deduplicated through alert state.
- Mandatory indexes cover assignee/owner/queue/status/due, participants, approvals, dependencies, comments, links and search.

## Organisational rollout gate

Automatic direct-manager / department-manager escalation must remain disabled until the real organisational hierarchy is populated and validated. This does not block foundation development.

## Authorised next engineering step

Implement **Migration A — Work Engine Foundation** on `feature/work-management`, then review the migration and contract tests before building the next layer.

This review does **not** authorise applying a migration to production or merging to `main`.