# AI Operations — Decision Pipeline Implementation Delta

**Status:** branch implementation artifacts only — no database migration applied  
**Branch:** `feature/work-management`  
**Scope:** Receivables/Credit first vertical slice only.

## 1. Closed branch-side reasoning pipeline

The first slice now has a concrete internal pipeline:

```text
planner run
  → atomic Credit snapshot
  → immutable ranked case evidence
  → frozen governed operational context
  → bounded worker reasoning context
  → one structured decision per frozen case
  → staged decisions only
  → current-state validation
  → explicit human review
  → [Work bridge NOT YET IMPLEMENTED]
```

No file in this pipeline is deployed to production and no `ai_ops` schema exists in production at the time of this document.

## 2. Worker protocol is intentionally not an external connector

`20260816172000_ai_operations_worker_protocol.sql` defines internal state-machine primitives only:

- claim/recover a due run with a lease;
- build/read immutable context;
- enforce serialized context budget;
- heartbeat;
- stage a bounded decision batch;
- record technical failure.

All worker functions are explicitly revoked from:

```text
PUBLIC
anon
authenticated
service_role
```

There is no API key, token, public RPC or ChatGPT-specific access surface in the current branch artifacts.

This is deliberate. The existing broad Supabase ChatGPT connector is not accepted as an unattended production-write security boundary.

## 3. Context budget is hard, measured and fail-closed

Planner settings add:

```text
max_worker_context_bytes = 65,536 bytes by default
```

The worker serializes the actual frozen context before reasoning.

If the payload is over budget:

- the run becomes partial;
- checkpoint becomes `context_budget_blocked`;
- the worker receives no silently truncated reasoning context;
- no decision is staged.

The budget covers the real worker payload, while snapshot/header and per-case evidence byte counts remain separately auditable.

## 4. Zero cases and zero actions are first-class successful outcomes

A domain capture marker is written even when Receivables contains zero cases.

Therefore the system can distinguish:

```text
0 cases because nothing required attention
```

from:

```text
domain capture never completed
```

When cases exist, the worker must return exactly one structured decision for every frozen case. The decision can be `IGNORE` or `MONITOR`; it does not need to be an action.

A run with zero action decisions is explicitly recorded as `zero_action_run=true` and is not treated as failure.

## 5. No chain-of-thought persistence

Worker output is a strict JSON decision artifact. Unknown fields are rejected.

Allowed content is limited to fields such as:

- case ID;
- decision type;
- concise rationale;
- confidence;
- proposed owner/assignee;
- concise responsibility summary;
- why this owner / why now;
- expected outcome / next action;
- due or review date.

Scratchpads, SQL, tool instructions, hidden reasoning and arbitrary fields are not part of the contract.

The persisted decision metadata explicitly records:

```text
chain_of_thought_stored = false
```

## 6. Staging is network-retry safe

The worker context has a deterministic payload identity hash.
The submitted decision batch also has an identity hash.

If the first staging call commits but its HTTP/tool response is lost, resending the exact same:

```text
worker + context hash + decision batch hash
```

returns idempotent success.

A different batch after staging is rejected instead of replacing the audited decision set.

## 7. Frozen operational context is part of decision evidence

Operational context that can influence reasoning is frozen into each immutable snapshot case.

For the Credit slice it is restricted to:

- the sales order itself;
- its customer;
- active context valid at snapshot time;
- management/standard visibility only;
- approved AI inference only; unapproved AI inference is excluded.

Context priority is deterministic:

1. hard policy;
2. approved human;
3. explicit human;
4. system record;
5. system inference;
6. approved AI inference.

Maximum normal context is **5 records per case**. Each summary is capped at 500 characters and marked as governed but untrusted text.

Coverage stores total/captured/truncated so omission is visible rather than silent.

## 8. Management replay is aligned to decision time

A critical audit correction was added:

When management opens a case that already has a decision, the UI read gateway loads evidence from the snapshot belonging to **that same decision run**.

It does not combine:

```text
old AI decision + newer case facts
```

or:

```text
old decision + currently edited operational context
```

The review payload instead includes:

- decision-time facts;
- decision-time responsibility evidence;
- decision-time Work collision evidence;
- decision-time frozen operational context;
- context coverage/truncation;
- concise decision rationale.

The current console summary is separately corrected to attach a decision only if it belongs to the same run as the displayed latest snapshot.

## 9. Current-state validation is separate from AI reasoning

A staged AI decision is not considered safe merely because it was reasonable against its snapshot.

`ai_ops.current_decision_issues(decision_id)` is the single source of current-state drift checks for the first Credit slice.

It checks, among other things:

- invoice still exists and is still an overdue credit candidate;
- due date unchanged;
- remaining balance unchanged;
- current customer assignment unchanged;
- order rep unchanged;
- credit override unchanged;
- no new due-date history after snapshot;
- no new customer credit-policy history after snapshot;
- no newer governed operational context;
- proposed Work owner/assignee still active;
- no newly appeared active Work collision for `CREATE_WORK`;
- linked Work still active for `ESCALATE`;
- action decisions are not based on partial/blocked snapshot capture.

The check uses the **current Cairo business date**, because validation is about current operational reality, not historical replay.

This function is intended to be reused by both validation and the future Work commit bridge so the safety criteria cannot drift between layers.

## 10. Validation and human approval have different meanings

The pipeline now explicitly separates:

```text
validation_state
  = current system facts still support the recommendation

human review
  = an authorised manager agrees with the recommendation
```

`ai_ops.decision_reviews` is an immutable human-review ledger.

The management review RPC:

```text
public.ai_ops_review_decision(...)
```

requires:

- authenticated active Work actor;
- `work.policies.manage` permission.

Approval performs **fresh current-state revalidation again**, rather than trusting an earlier validation timestamp.

If reality changed:

- the decision is persisted as rejected/stale;
- the review call returns an explicit blocked result;
- no human approval row is created;
- no operational action occurs.

The blocked result is returned instead of raising after the update, because a Postgres exception would roll back the safety-state update itself.

## 11. Human review is immutable and fingerprinted

A review stores:

- decision ID/revision;
- approve/reject state;
- reviewing user;
- timestamp;
- bounded note;
- decision fingerprint;
- validation state/time at review.

Exact same-review retry is idempotent only when reviewer, decision fingerprint, review state and note all match.

A different second review cannot silently replace the first audited review.

## 12. Work bridge remains intentionally open

The Work bridge is **not implemented yet** in this document/state.

Before it is written, implementation must reuse the actual deployed Work system-generation pattern discovered from:

- `work_items` constraints/defaults;
- existing system-origin recurrence generation;
- `private.work_append_system_event(...)` or the actual generic event helper available at that time;
- current notification trigger semantics;
- `work_links` for exact business-entity links;
- Work idempotency/source-key conventions.

The bridge must not:

- call human-auth Work commands by impersonating a profile;
- write arbitrary user-supplied task fields directly;
- bypass Work events/notifications;
- mutate Sales/Customer/Credit data;
- accept an unvalidated AI payload directly.

The intended input is a **reviewed + validated `decision_id` only**.

Commit-time implementation must call the shared current-state guard again inside the same transaction before any Work mutation.

Until that bridge is designed and tested, the Credit slice is intentionally a **reasoning/review system with no operational auto-write path**.
