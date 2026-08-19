# AI Operations — Work Health Domain

**Status:** branch implementation artifacts only — no production AI Operations migration applied  
**Branch:** `feature/work-management`  
**Domain:** `work_health`  
**Acceptance sequence:** governed by `18_AI_OPERATIONS_BUILD_ALL_DOMAINS_ACCEPTANCE_STRATEGY.md`.

## 1. Production authority

Work Health does not invent a second task-health model. The deployed Work Engine already exposes authoritative operational semantics through:

- `public.work_items` and immutable `public.work_events`;
- `public.work_operational_settings`;
- `public.work_operational_flags`;
- dependency-based blocker evaluation;
- `public.work_escalations`;
- `private.work_scan_operational_alerts`, scheduled every 15 minutes;
- native Work RPCs for due date, Next Action, waiting, dependency resolution, escalation and completion.

At discovery time the configured health thresholds were `due_soon_hours=24` and `stale_after_hours=72`. These are runtime configuration values, not constants in AI Operations.

The AI domain reuses those semantics and adds only one structural invariant: an active execution Work item in `open`, `in_progress` or `waiting` should not lack `next_action_text`.

## 2. Deterministic v1 Cases

One dominant Case is emitted per unhealthy source Work item, using a stable Case key `work_health:<work_item_id>` and precedence that avoids duplicate AI Cases for overlapping signals:

1. `overdue_work`;
2. `blocked_work`;
3. `waiting_follow_up_due`;
4. `stale_work`;
5. `missing_next_action`.

`due_soon` alone is deliberately not an AI Case because the native operational scanner already provides the appropriate reminder. An at-risk combination is evidence, not a second Case.

Private Work is excluded from v1 AI facts. Comments, attachments and proofs are not captured. Work Health recovery tasks (`metadata.ai_domain=work_health`) are excluded so the domain cannot recursively create health Cases about its own recovery tasks.

## 3. Evidence and responsibility

Frozen facts include:

- source Work identity/number/status/priority and standard-visibility title;
- source and organizational identifiers;
- `state_version`;
- due date, Next Action, waiting state and last meaningful activity;
- authoritative overdue/stale/blocked/follow-up/due-soon/at-risk booleans;
- calculated overdue/stale age for reviewer context;
- operational settings version and configured health thresholds;
- the source Work itself as normalized `existing_active_work` evidence for `ESCALATE`;
- bounded governed context for active owner/assignee employees, branch and department.

The source accountable owner owns recovery responsibility. For `CREATE_WORK`, both recommended accountable owner and assignee must be that current active source owner. This deliberately avoids creating another execution task for the original assignee.

If the owner is missing/inactive, monitoring remains possible but consequential creation fails closed.

## 4. Six-domain global budget

Work Health is the sixth domain under the same hard Case budget:

1. Receivables;
2. Sales;
3. Customer Health;
4. Inventory;
5. Field Execution;
6. Work Health.

The existing domain-neutral round-robin allocator remains the only allocator. Cross-domain severity is never compared.

The canonical required-domain registry is updated to include `work_health`; the shared worker-context and decision-staging wrappers therefore fail closed if a Work Health capture marker is absent.

The trusted capture version is `work-health-v1`. A selected Work Health Case may be actionable under bounded partial coverage only when the same shared row-count/evidence-byte/source-date integrity rules hold. Zero-budget markers and malformed/blocked/source-partial evidence remain non-actionable.

## 5. Current-state guard

Immediately before review/commit, the guard re-runs Work Health against current time and rejects consequential action when material state changed, including:

- source Work missing or no longer unhealthy;
- dominant health Case type changed;
- `state_version` changed;
- status/priority/due/Next Action/waiting/last activity changed;
- health signals changed;
- operational settings version changed;
- owner/assignee responsibility changed;
- proposed recovery routing differs from the source accountable owner;
- another active AI Work Health recovery task now exists for the source Work;
- an `ESCALATE` decision no longer links to the exact active source Work;
- newer governed context appeared;
- frozen capture evidence fails the shared actionability gate.

## 6. Human-reviewed recovery Work

A reviewed `CREATE_WORK` can create a separate recovery task only after:

- planner enabled;
- Shadow Mode off;
- approved human review;
- exact decision fingerprint and revision still match;
- decision remains validated;
- same-transaction current-state revalidation passes;
- source accountable owner is still active;
- explicit future due date exists;
- no active recovery collision exists.

The task is system-origin with deterministic source key `ai_ops:decision:<decision_id>`. It links to the exact unhealthy source `work_item`, and optionally to the source owner employee.

The recovery instruction is employee-safe: review the original Work and use the native Work workflow to update the real status, Next Action, due date, waiting/blocker resolution or completion as appropriate.

**The bridge never changes the unhealthy source Work automatically.** It creates only the approved recovery Work plus AI provenance/events.

## 7. Runtime discovery signal

Read-only production discovery on 17 August 2026 showed one active Work item. The authoritative operational logic classified it as `overdue_work`; it was urgent and overdue, while not stale, blocked or follow-up-due. This validates the v1 kernel against a real current state without hard-coding production values.

## 8. Acceptance for this increment

Before moving to HR / Availability, this domain must pass:

- Work Health deterministic-case contract tests;
- immutable snapshot/capture tests;
- six-domain global-budget and required-domain coverage tests;
- bounded-partial actionability tests;
- current-state state-version/signal/settings/routing drift tests;
- recovery collision and recursion-prevention tests;
- reviewed recovery Work bridge tests;
- source-Work read-only assertions;
- read-only production-schema compatibility check;
- repository tests, type-check, production build and Windows clean-install CI.

The expensive isolated full migration-chain/runtime E2E remains deferred to the final all-domain acceptance sweep. No production migration, merge or deployment is authorized by this document.
