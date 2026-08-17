# AI Operations — Multi-Domain Sales Integration

**Status:** branch implementation artifacts only — no production migration applied  
**Branch:** `feature/work-management`  
**Scope:** integrate the existing Sales & Targets case/snapshot slice into the proven AI Operations worker, validation, human-review and reviewed Work path.  
**Acceptance sequence:** governed by `18_AI_OPERATIONS_BUILD_ALL_DOMAINS_ACCEPTANCE_STRATEGY.md`; local DB runtime acceptance is deferred to the final integrated engine sweep and does not block the next domain.

## 1. What this increment changes

Before this increment:

```text
Receivables/Credit
Case -> Snapshot -> Worker -> Decision -> Validation -> Human Review -> Work

Sales/Targets
Case -> Snapshot -> Freshness
```

After this increment, the branch design supports:

```text
One planner run
  -> one immutable snapshot identity
  -> Receivables immutable domain capture
  -> Sales immutable domain capture
  -> one bounded multi-domain worker context
  -> one decision per frozen case
  -> domain-aware current-state validation
  -> unchanged human review
  -> domain-aware reviewed CREATE_WORK commit
```

No autonomous Work creation is enabled. Production remains untouched.

## 2. One snapshot identity, authoritative domain captures

The existing Credit snapshot builder remains the creator of the persisted `ai_ops.snapshots` row. Its original header payload is intentionally not rewritten after creation because snapshots are immutable.

For multi-domain truth, the authoritative coverage record is:

```text
ai_ops.snapshot_domain_captures
```

The worker context now exposes:

- the legacy singular `snapshot.domain_capture` for backward compatibility;
- `snapshot.domain_captures` as the authoritative multi-domain list;
- all immutable `snapshot_cases` across captured domains;
- generic global coverage derived from the domain capture rows.

A Credit-only snapshot may be augmented with Sales only before a worker context hash has been bound. Once reasoning has been bound to a context identity, adding evidence to that run is rejected rather than silently changing what the worker saw.

## 3. Shared global case budget

`max_cases_per_snapshot` remains a hard limit for the whole planner run, not a per-domain allowance.

The two-domain allocator uses a deterministic fair-share policy:

1. start with roughly half the budget for Receivables and half for Sales;
2. if one domain needs fewer slots, spill the unused capacity to the other;
3. never compare Sales severity directly with Receivables severity to decide which domain wins a slot;
4. never exceed the global hard cap.

If Sales has candidates but receives zero remaining slots, an immutable Sales domain capture is still written as `partial` with explicit `global_budget_exhausted` metadata. Zero evidence must never be mistaken for complete zero-case coverage.

## 4. Sales evidence and freshness remain conservative

Sales decisions continue to use the existing target authority:

- `public.targets` defines the target;
- `public.target_progress` is the canonical progress source;
- latest progress at or before the planner business date may keep a case visible;
- stale progress is evidence only and cannot authorize `CREATE_WORK` or `ESCALATE`;
- contribution parity must remain valid for consequential action;
- field activity/visits remain supporting evidence, not deterministic proof of cause;
- AI Operations never calls target recalculation from this path.

This preserves the rule that missing same-day target progress must not hide a material case, while also preventing old evidence from authorizing a current operational action.

## 5. Domain-aware current-state validation

The canonical guard `ai_ops.current_decision_issues(decision_id)` dispatches by the frozen case domain.

### Receivables

The previously audited Credit guard is preserved as a private primitive without changing its business checks.

### Sales

Before a Sales action can validate or commit, the guard rechecks:

- target still exists;
- target remains active, unpaused, in period and supported;
- target definition has not changed since the snapshot;
- latest canonical progress has not changed since the snapshot;
- target remains `behind` or `at_risk`;
- frozen progress is current enough for consequential action;
- contribution parity is valid for consequential action;
- no newer governed context changes the interpretation;
- current branch/employee scope context has not drifted after the snapshot;
- current accountable scope owner still matches the frozen responsibility evidence;
- proposed owner and assignee remain active;
- no equivalent active Work is linked to the target;
- an escalation still points to active Work linked to the same target;
- the Sales domain capture is complete for consequential action.

Unknown future domains fail closed.

## 6. Reviewed Sales Work uses the existing Work Engine

The public management commit surface remains unchanged:

```text
public.ai_ops_commit_reviewed_decision(decision_id)
```

The private bridge dispatches by frozen domain.

For Sales, a new Work item can be created only when all existing safety conditions pass:

- decision type is `CREATE_WORK`;
- planner is enabled;
- Shadow Mode is off;
- no unexplained source-key collision exists;
- human review is approved;
- reviewed decision fingerprint/revision still matches;
- decision is currently validated;
- current-state guard is rerun in the same transaction immediately before Work mutation;
- owner, assignee and future due date are explicit and still active.

The created Work item:

- uses `source_kind='system'`;
- uses deterministic `source_key='ai_ops:decision:<decision_id>'`;
- does not impersonate a human creator/requester;
- uses the existing draft-to-open lifecycle;
- emits the existing `work.created` and `work.activated` events;
- links to the exact target through the already-supported `work_links(entity_type='target')` contract;
- exposes only bounded employee-safe execution context, not management-only rationale.

No target, target progress, sales order, activity or visit record is modified by the bridge.

## 7. Worker contract

The TypeScript worker response supports `snapshot.domain_captures` while retaining the legacy singular Receivables capture field.

Decision requirements remain strict:

- every frozen case needs exactly one disposition;
- zero cases legitimately allow zero decisions;
- `MONITOR` needs a future review time;
- `CREATE_WORK` needs explicit owner, explicit assignee, expected outcome, next action and future due date;
- rationale/action text remains bounded;
- action count remains globally capped;
- staging performs no operational mutation.

## 8. Security boundary remains unchanged

This increment does not create a new autonomous AI API surface.

Internal worker and helper routines remain revoked from normal browser/API roles. Human-approved commit still travels through the existing management RPC and existing Work permission check.

The architectural production rule remains unchanged: the broad personal worker/connector is not an approved unattended mutation boundary.

## 9. Verification status and deferred runtime gates

Branch-level contract and repository tests cover:

- shared multi-domain case budget;
- immutable domain capture behavior;
- deterministic non-colliding snapshot ranks across Receivables and Sales;
- worker context/hash/byte limits;
- one-decision-per-frozen-case cardinality;
- strict CREATE_WORK requirements;
- Sales target/progress/context/Work drift detection;
- Sales scope-accountability drift and branch/employee context drift;
- stale-progress and parity action blocks;
- reviewed Work kill switches, approval fingerprint, idempotency and target linking;
- no target/sales mutation from the worker/guard/bridge.

These checks do **not** replace database runtime acceptance. The following runtime scenarios remain mandatory, but are intentionally deferred to the final integrated local engine acceptance defined in document `18`:

1. apply the complete AI Operations migration chain to an isolated/local Supabase/PostgreSQL environment;
2. prove Sales freshness scenarios with realistic target data;
3. prove the final multi-domain snapshot respects global case budgets, immutable ranks and domain coverage;
4. prove worker context parsing/hashing and zero-case combinations at runtime;
5. stage and validate mixed-domain decisions in one run;
6. prove stale Sales progress blocks action but does not hide the Case;
7. approve and commit a Sales decision to exactly one system-origin Work item linked to its target;
8. retry that commit and prove no duplicate Work;
9. mutate target/progress/context/accountability/Work between review and commit and prove commit-time rejection;
10. run the complete cross-domain feasibility and outcome loop after all intended domains are present.

Until the final integrated runtime acceptance passes, this remains reviewed development-branch implementation, not a production release.

## 10. Expansion rule

Sales local runtime acceptance no longer blocks development of the next domain. Customer Health / Re-engagement may proceed once the current Sales branch increment passes its continuous gates: static architecture/security review, contract tests, and repository CI on the current HEAD.

The next domain must reuse and extend the shared multi-domain worker, validation dispatcher and reviewed Work bridge rather than creating a parallel AI subsystem. Any credible defect discovered during continued development is fixed immediately in the responsible domain/shared layer; only the expensive local database runtime sweep is deferred.
