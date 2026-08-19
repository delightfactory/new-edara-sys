# AI Operations — Intelligence Closure Plan

**Status:** implementation plan and acceptance contract  
**Branch:** `feature/work-management`  
**Production:** untouched / disabled by default

## Goal

Close the four gaps found in the pre-smoke architecture review without bypassing or weakening any existing Work Management, AI Operations, RBAC, snapshot, review, or execution contract.

The closure is additive and fail-closed. Existing domain detection and reviewed execution remain authoritative.

## Gap 1 — Runtime decision policy

### Problem
The engineering specification contains the management reasoning method, but the live worker prompt only carries the transport/safety contract.

### Closure
- Add an explicit `ops-manager-v1` reasoning policy to the worker context.
- Require cause/control before org-chart routing.
- Require value-vs-interruption reasoning and existing-work-first behavior.
- Require cross-domain feasibility reasoning before `CREATE_WORK`/`ESCALATE`.
- Extend staged decision payloads with business impact, urgency, evidence completeness, reversibility, effort band, measurable success signal, and employee-safe reason.
- Bind every claimed run to a concrete prompt version + SHA-256 prompt hash through a service-role-only gateway.
- Persist prompt identity in `planner_runs` so audit can establish the exact worker instruction version used.

## Gap 2 — Company-wide portfolio context

### Problem
Seven domain Cases reach the worker, but the management pulse is not a synthesized cross-domain portfolio view.

### Closure
- Build a deterministic portfolio summary only from frozen snapshot evidence plus bounded prior-run/outcome aggregates.
- Include per-domain demand/severity/trust, cross-domain entity collisions, existing Work evidence, responsibility candidates, previous planner outcomes, human feedback distribution, and unresolved AI-created Work counts.
- Do not invent numeric employee capacity thresholds.
- Keep hard validation authoritative for availability/current-state checks; portfolio workload is planning evidence, not employee scoring.
- Store the generated portfolio summary in the run audit metadata and include it in the context hash.

## Gap 3 — Outcome and Case reconciliation loop

### Problem
Cases can become `actioned`, but absence from a later trustworthy capture does not reliably close the Case and previous outcomes/feedback are not part of later reasoning.

### Closure
- Reconcile a Case to `resolved` only when its domain capture is complete and explicitly not truncated/budget-exhausted/blocked.
- Never resolve from partial evidence.
- Reopen a previously resolved Case through the existing deterministic capture path if the underlying condition reappears.
- Add bounded previous-run outcome and feedback memory to subsequent planner context.
- Keep Work completion distinct from business success; unresolved AI-created Work is exposed as portfolio evidence rather than assumed success.

## Gap 4 — Human correction and governed context

### Problem
Managers can approve/reject/snooze/dismiss but cannot safely correct a nearly-right recommendation, and `operational_context` lacks a management authoring gateway.

### Closure
- Add management-only operational-context create/revoke RPCs with bounded text, explicit lifecycle, subject validation, and no direct table grants.
- Add a management-only staged-decision revision RPC.
- Revision is allowed only before any human review/commit, updates the existing staged decision in place, increments `revision`, stores the previous editable state in bounded revision history, and immediately re-runs current-state validation.
- Human approval still remains a separate action. Revision never executes Work.
- No approved/rejected review record is mutated or replaced.

## Compatibility / non-regression rules

1. No source business table is mutated by snapshot, reasoning, reconciliation, or feedback functions.
2. Work creation and escalation remain behind the existing reviewed execution dispatcher.
3. Browser roles never gain worker execution access.
4. `service_role` worker gateways remain narrowly scoped.
5. Existing seven-domain capture functions and domain current-state guards remain unchanged.
6. Case reconciliation is conservative: uncertainty leaves the Case open.
7. No productivity score or arbitrary tasks-per-day capacity rule is introduced.
8. AI-originated recommendations cannot approve themselves.
9. Preview mode remains read-only.
10. New functionality remains disabled operationally until the final runtime acceptance sweep passes.

## Required acceptance after implementation

- Contract tests for policy identity, extended decision payload, portfolio context, feedback memory, conservative reconciliation, revision immutability boundaries, context authoring security, and prompt binding.
- Full repository CI on current HEAD.
- Isolated full migration-chain rehearsal.
- Realistic mixed-domain local E2E: snapshot -> model decision -> validation -> human correction/review -> execution -> Work outcome -> next run reconciliation.
- Mutation-between-review-and-commit failure scenario.
- Retry/idempotency and dead-man recovery scenarios.
- Shadow-mode comparison against human management decisions before enabling human-approval mode.
