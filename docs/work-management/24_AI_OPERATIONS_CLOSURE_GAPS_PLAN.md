# AI Operations — Final Closure Plan Before Runtime Acceptance

**Branch:** `feature/work-management`  
**Scope:** close the four remaining operational-intelligence gaps without bypassing or weakening the existing seven-domain Case -> Snapshot -> Decision -> Validation -> Human Review -> Work lifecycle.

## Release posture

This closure is additive and fail-closed. Existing Work Management commands, human approval, current-state guards, immutable snapshot evidence, service-role worker gateways, action budgets, idempotency, and Shadow/Planner kill switches remain authoritative.

No production deployment or merge is authorized by this document.

## Gap 1 — Versioned Decision Policy Runtime

### Problem
The repository specification contains a richer management reasoning method than the Edge worker's embedded prompt. `planner_policy_version`, `prompt_version`, and `prompt_hash` exist in run state but do not yet prove which exact decision method the model received.

### Closure
1. Add a private `ai_ops.planner_policies` registry containing the approved system prompt, methodology contract, prompt version and deterministic prompt hash.
2. Require every worker run to resolve an enabled policy matching both the frozen run `planner_policy_version` and `prompt_version`; missing/mismatched policy fails closed.
3. Inject the exact policy into the bounded worker context and persist its hash on `planner_runs.prompt_hash`.
4. Make the Edge worker consume only the versioned prompt delivered by the database. It must not maintain an independent management-reasoning prompt.
5. Keep output schema enforcement and all deterministic safety gates in SQL.

### Acceptance
A historical run can be reconstructed using: run versions + prompt hash + immutable snapshot + staged decision payload.

## Gap 2 — Global Operational Context

### Problem
All seven domains reach the worker, but cross-domain prioritisation is mostly a list of Cases rather than a compact company-wide planning frame.

### Closure
1. Build a deterministic global summary strictly from the same frozen snapshot/domain captures; never re-query mutable operational truth to decorate model input.
2. Include domain coverage/trust, severity distribution, top material Cases, commercial-vs-constraint pressure, global action budget, prior run result and recent structured feedback/outcome observations.
3. Preserve the raw bounded frozen Cases alongside the global summary; the summary is orientation, not a substitute for evidence.
4. Include explicit reasoning rules: value vs interruption cost, feasibility before assignment, existing Work first, cause/control before hierarchy, uncertainty may produce INVESTIGATE/MONITOR/IGNORE.

### Acceptance
The model receives one bounded representation answering both "what is happening across the company?" and "which exact frozen Cases support that view?".

## Gap 3 — Outcome / Case Reconciliation Loop

### Problem
Cases can become `actioned`, and feedback is stored, but source resolution and Work outcomes do not yet form a reliable closed loop into later runs.

### Closure
1. Add immutable `ai_ops.case_outcomes` observations; these are planner-quality/outcome records, never employee performance scores.
2. Reconcile only domains whose frozen capture is demonstrably complete. Missing Cases in a partial/truncated/budget-exhausted capture must never be auto-resolved.
3. When a Case disappears from a complete later snapshot, resolve it and record `source_resolved`.
4. When AI-created/referenced Work completes or is cancelled while the underlying condition still appears in a later snapshot, reopen the Case for reconsideration and record a persistence outcome instead of silently declaring success.
5. Feed recent outcome observations and structured human feedback into later global worker context.
6. Never mutate source Sales/Inventory/HR/Customer records as part of reconciliation.

### Acceptance
A later run can distinguish: condition resolved, Work completed but condition persists, Work cancelled while condition persists, human rejected/wrong timing/missing context, and still-active execution.

## Gap 4 — Human Context + Audited Decision Revision

### Problem
Management can Approve/Reject/Snooze/Dismiss but cannot safely add governed operational facts or correct a mostly-right recommendation before approval.

### Closure
1. Add management-only RPCs to create approved human operational context and revoke it. Context is bounded, treated as untrusted data content, versioned by lifecycle dates, and never becomes executable policy.
2. Add management-only decision revision for staged, uncommitted decisions before approval.
3. Revision creates a new decision row; the previous row is retained and marked superseded/rejected for lifecycle accounting. No in-place replacement of reviewed history.
4. Allow only operational edits needed for execution: owner, assignee, due date, next action and expected outcome. Decision type/case/source evidence cannot be switched by the UI revision path.
5. Every revision immediately runs the existing current-state guard. A stale or infeasible edit is stored for audit but rejected and cannot be approved/committed.
6. Add UI/service controls for revision and governed context without exposing internal `ai_ops` tables.

### Acceptance
A manager can correct routing/timing/action text with a complete audit trail and still cannot bypass validation, review or commit guards.

## Compatibility / non-regression rules

- No direct `anon`/`authenticated` access to `ai_ops` tables or internal worker routines.
- Browser mutations remain narrow `public.*` SECURITY DEFINER gateways with active-actor + `work.policies.manage` checks.
- Existing human approval and explicit execution remain two separate operations.
- Existing `CREATE_WORK`/`ESCALATE` bridges remain the only operational AI write paths.
- No new source-table triggers or AI-generated SQL.
- Snapshot Cases and evidence remain immutable.
- New context/outcome enrichment is included in the final worker-context byte budget and may fail closed when oversized.
- Auto-commit remains disabled/untrusted for this acceptance cycle.

## Final acceptance sequence after implementation

1. Full repository tests, type-check and production build.
2. Clean full migration chain from zero.
3. Seven-domain non-empty realistic snapshot.
4. Verify policy version/hash and replayability.
5. Verify global prioritisation context and byte bounds.
6. Exercise model decisions with mixed opportunities/constraints.
7. Approve/reject/snooze/dismiss and revise a recommendation.
8. Add/revoke human operational context and prove next snapshot honors it.
9. Commit reviewed Work/ESCALATE and prove idempotency.
10. Change source reality between review and commit and prove fail-closed behavior.
11. Complete/cancel Work, rerun, and prove Case resolution/reopen outcomes.
12. Verify prior feedback/outcomes enter the next planner context.
13. Run final architecture/security review before any merge or production migration.
