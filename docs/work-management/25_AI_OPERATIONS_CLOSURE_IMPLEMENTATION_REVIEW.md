# AI Operations — Closure Implementation Review

**Branch:** `feature/work-management`  
**Purpose:** close the four pre-smoke functional/intellectual gaps found in the final architecture audit.  
**Production:** untouched; no merge or production AI Operations migration is authorized by this document.  
**Target state:** development closure / ready for isolated runtime acceptance, followed by realistic mixed-domain smoke testing.

## 1. Closure verdict

The closure pack is intentionally additive. Existing seven-domain detection, immutable snapshot evidence, worker leases, action budget, validation, human review, reviewed Work bridges, escalation, dead-man monitoring, Work idempotency and source-of-truth rules remain authoritative.

The four gaps are now represented in executable contracts rather than documentation only:

1. **Versioned management reasoning policy** — the model consumes a database-owned, immutable, hash-bound policy. Final new-run prompt contract is `v3`.
2. **Cross-domain operational planning frame** — the worker receives a frozen whole-run management frame including domain summaries, actor feasibility evidence, exact shared customer/product links, previous decisions/outcomes and bounded human judgement.
3. **Closed outcome / Case loop** — complete-domain snapshots reconcile disappeared conditions, persistent conditions can reopen after terminal Work, outcomes are immutable, and all learning evidence is snapshot-as-of bounded.
4. **Human governance** — management can create/revoke expiring approved operational context and create an audited decision Revision before review. Approval remains distinct from execution.

No autonomous business mutation was added. `auto_commit_enabled` remains outside the accepted activation path.

## 2. Gap 1 — Decision Policy Runtime

### Implemented

- private `ai_ops.planner_policies` registry;
- exact `policy_version`, `prompt_version` and MD5 payload identity persisted per Run;
- final `v3` prompt contains the full management reasoning method and an explicit final output-contract precedence section;
- Edge worker no longer owns a hidden hard-coded management prompt; it verifies and consumes the database policy;
- prompt content/methodology/hash/version are immutable; only a policy version's activation flag may change;
- prompt-injection boundary remains explicit: business text is data, never instructions.

### Structured action quality

`CREATE_WORK` / `ESCALATE` must explicitly state:

- business impact;
- urgency;
- evidence completeness;
- reversibility;
- effort band `S/M/L`;
- observable success signal;
- employee-safe reason.

These are qualitative planning evidence, not employee scores and not hard-coded confidence thresholds. Deterministic DB validation remains authoritative.

### Human-review binding

The approved/rejected human record is bound to a full immutable fingerprint covering the original execution fields **and** the structured quality envelope. Any post-review drift blocks execution.

A current-state approval block remains a valid non-exceptional fail-closed result and does not fabricate a review row. Quality completeness is required for **approval**, never for rejecting a bad/incomplete AI recommendation.

## 3. Gap 2 — Global Operational Context / Feasibility

The same immutable Snapshot now produces one frozen global planning frame with:

- seven-domain Case/coverage summary;
- commercial vs constraint framing;
- global action budget;
- actor feasibility evidence;
- prior Work/Field pressure evidence;
- exact cross-domain shared-customer/shared-product links;
- prior human feedback, Approve/Reject outcomes and objective Case outcomes;
- explicit semantics that severity is not automatic priority.

### Feasibility rule

Only trusted hard facts are hard blockers. In particular:

- inactive Work actor: hard blocker;
- explicit HR unavailability: hard blocker;
- Work-health counts: pressure evidence only;
- overdue Field plan counts: pressure evidence only;
- no synthetic tasks-per-day capacity threshold;
- no hidden employee productivity score.

This preserves the approved design principle: do not invent capacity precision when the source system has no trusted effort estimate for every active Work item.

## 4. Gap 3 — Outcome / Reconciliation Loop

### Case reconciliation

For a **complete, untruncated** domain capture only:

- a previously active Case absent from the new deterministic source result may resolve;
- a Case still present remains present;
- an `actioned` Case whose AI-linked Work is done/cancelled but whose source condition persists reopens;
- Work completion is never equated automatically with business success.

Partial/truncated/global-budget-exhausted domains never resolve omitted Cases.

### Concurrency and replay

- an older recovery Snapshot cannot resolve/reopen Case state touched by a newer Snapshot;
- first reconciliation output is frozen once per Snapshot;
- global operational context is frozen once per Snapshot;
- the first model-context attempt number is frozen for replay while live retry count remains in `planner_runs` telemetry;
- same frozen evidence therefore has a stable model-input identity under unchanged policy/settings.

### Learning boundary

Future planner context contains bounded prior:

- structured decision feedback;
- management Approve/Reject outcomes;
- objective Case outcomes.

All three are restricted to `<= snapshot.data_as_of`; later facts cannot leak backwards into a recovered historical Run. Feedback never self-modifies business policy and never becomes an employee-performance record.

## 5. Gap 4 — Human Context + Decision Revision

### Governed operational context

Management-only RPCs allow an authorized active actor to:

- add bounded operational context to an existing AI Case entity;
- require an explicit future expiry (maximum 180 days for the current human-context path);
- revoke the context;
- preserve immutable context events.

Human context is planning evidence only and carries no execution authority.

### Context-drift safety

Before consequential approval/commit, the final current-state guard also invalidates an old recommendation when:

- frozen context was revoked;
- frozen context expired;
- frozen context fields changed;
- relevant new approved context appeared after the Snapshot.

The decision must then be regenerated/revalidated against current reality.

### Decision Revision

Before human review, management may revise a `CREATE_WORK` recommendation by creating a **new immutable decision revision**. The old revision remains audit history.

Editable execution fields include:

- accountable owner;
- assignee;
- due date;
- next action;
- expected outcome;
- success signal;
- employee-safe reason;
- optional revision note.

The new revision is immediately rechecked against current-state guards. Run lifecycle counts only the latest revision per Case, so superseded rejected rows cannot falsely force the Run to `partial`.

## 6. Backward compatibility

New Runs materialize with prompt `v3`.

A recoverable local-development Run frozen under legacy prompt `v1` retains its original core staging contract rather than being forced to invent fields that did not exist when its context was created. v2/v3 use structured-quality staging and exact quality submission hashes.

This compatibility path is for migration/recovery correctness; it does not change the final new-run policy.

## 7. Safety invariants preserved

The closure pack does **not** weaken any of these boundaries:

- `ai_ops` private tables are not browser data APIs;
- worker execution gateways remain service-role-only;
- browser management writes use narrow authenticated RPCs plus `work.policies.manage` checks;
- model output cannot execute SQL/tool calls;
- staging never creates Work;
- human approval never creates Work;
- `CREATE_WORK` / `ESCALATE` still require an explicit separate execution command;
- commit reruns current-state validation in the execution transaction;
- native Work idempotency/concurrency/event semantics remain authoritative;
- operational source tables are not changed by Case detection, snapshot, reasoning, reconciliation or feedback;
- Shadow Mode and Planner Off remain kill switches;
- no payroll, finance, credit-limit, stock-adjustment, HR discipline or other sensitive source mutation was added.

## 8. Acceptance evidence added

The repository now includes contract tests covering:

- versioned policy runtime and prompt hash;
- final `v3` output contract;
- structured decision quality;
- cross-domain planning evidence;
- frozen global context and outcomes;
- feedback snapshot-as-of causality;
- reconciliation concurrency;
- exact replay freeze;
- human context/revision governance;
- context mutation drift;
- full review fingerprint;
- blocked-review semantics;
- revision-aware Run lifecycle;
- legacy prompt staging compatibility;
- Edge worker separation from commit;
- final TypeScript worker/context schemas.

A dedicated GitHub Actions closure workflow also performs repository tests/build plus full isolated migration-chain/runtime checks without production credentials.

## 9. What still belongs to the smoke / acceptance phase

Development closure does not substitute for real operational acceptance. Before any merge/production migration, the authoritative strategy in `18_AI_OPERATIONS_BUILD_ALL_DOMAINS_ACCEPTANCE_STRATEGY.md` still requires realistic mixed-domain runtime scenarios, including:

1. non-zero Cases from multiple domains in one Snapshot;
2. actual model output against the final `v3` prompt;
3. correct prioritisation across commercial opportunities and operational constraints;
4. Approve / Reject / Revision / Snooze / Dismiss;
5. context added/revoked between Snapshot and review;
6. source state changed between review and commit;
7. CREATE_WORK and ESCALATE through native Work paths;
8. response-loss/idempotent retries;
9. Work completed while source condition persists;
10. source condition genuinely resolves and Case closes;
11. subsequent planner Run consumes prior outcome/human judgement correctly;
12. worker/model outage, lease recovery and dead-man alerting;
13. final security review and repository CI on the exact release HEAD.

Until those pass, the correct operational mode is **Shadow**, then **Human Approval**. Auto-commit is not approved by this closure review.
