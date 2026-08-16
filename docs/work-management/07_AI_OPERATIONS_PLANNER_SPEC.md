# Delight AI Operations Planner — Engineering Specification

**Status:** Design specification — not implemented, not released  
**Branch:** `feature/work-management`  
**Scope:** AI-assisted operational planning on top of the existing Reporting/Analytics and Work Management engines  
**Production impact:** None from this document

---

## 1. Purpose

The AI Operations Planner turns trusted operational signals into a small number of high-value, explainable actions without turning EDARA into a task factory.

The planner is not a generic chatbot, a report generator, an employee scoring system, or an autonomous manager. Its job is to:

1. consume compact, pre-aggregated company state;
2. identify material exceptions and opportunities;
3. reason about cause, authority, relationship ownership and actual ability to act;
4. request deeper evidence only when necessary;
5. decide whether the correct outcome is **no action, monitor, investigate, inform, create work, or escalate**;
6. create Work items only through guarded Work Management commands;
7. observe outcomes and human overrides so future recommendations improve without self-modifying business policy.

A successful planner run may legitimately create **zero tasks**.

---

## 2. Non-negotiable design principles

### 2.1 Reality before activity
The planner must never create work merely to complete its own scheduled run or to demonstrate activity. Every created item must have a plausible business benefit, a valid owner/executor model, and a useful expected outcome.

### 2.2 Deterministic work stays deterministic
Anything that can be handled safely by existing rules belongs in SQL, Work policies, recurrence, SLA scanners or notification cooldown logic — not in LLM reasoning.

Examples:
- recurrence generation;
- overdue flags;
- standard follow-up reminders;
- deterministic SLA escalation;
- duplicate/idempotency checks;
- employee/profile availability validation;
- report freshness/trust checks.

The LLM is reserved for ambiguity, prioritisation, causal interpretation, trade-offs and context-sensitive ownership.

### 2.3 Cause and control before org chart
Department or role is evidence, not a routing rule.

For every case the planner must distinguish:
- **decision owner** — who made or controls the underlying business decision;
- **relationship owner** — who owns the ongoing customer/supplier/internal relationship;
- **accountable owner** — who owns the business result;
- **executor** — who can perform the next concrete action;
- **information holder** — who may have context unavailable in the database;
- **manager** — an escalation/fallback authority, not a default dumping ground.

A transaction creator is also only evidence. A clerk creating an invoice is not automatically the credit decision owner.

### 2.4 Human override is authoritative
A valid human action, explicit operational context, approved due-date change or ownership decision must not be silently reversed by the planner.

Human override is feedback, not a negative performance signal.

### 2.5 Unknown is not false
Missing context must lower confidence. The planner may choose `INVESTIGATE`, `INFORM` or `MONITOR` rather than inventing a cause or owner.

### 2.6 Minimise interruption cost
Presence does not equal availability. A person who appears free may be handling high-context work not visible in a simple count.

The planner must prefer:
- fewer, higher-value interventions;
- morning planning over continuous micro-tasking;
- updating/following existing work over creating duplicates;
- protecting focus time and retaining capacity for unplanned operational work.

### 2.7 No punitive employee scoring
Planner data must not become a hidden employee score. Delays, low sales or incomplete work may be caused by dependencies, customer behaviour, authority limits, bad data or management decisions.

Employee-level observations are evidence for planning, not automatic disciplinary conclusions.

### 2.8 Explainability without leaking confidential context
Every recommendation must be able to answer:
- Why this case?
- Why now?
- Why this owner?
- What evidence supports it?
- What outcome is expected?

However, the employee-facing Work item must receive only the minimum rationale necessary to execute it. Management-only or sensitive evidence remains restricted.

---

## 3. Architectural boundary

```text
Operational DB
    |
    v
Existing Analytics / Reporting Engine
    |
    | hourly/current deterministic refresh
    v
AI Snapshot + Case Engine (database)
    |
    v
ChatGPT Planner Worker
    |
    | optional batched drill-down
    v
Decision Gate + Responsibility Resolution
    |
    v
Validated Action Intents
    |
    v
Canonical Work Management command engine
    |
    v
Human execution / outcome / override
    |
    v
Planner feedback + governed operational context
```

The planner must **not** read thousands of raw operational rows during normal execution. The database performs aggregation and candidate detection. ChatGPT spends its tool budget on interpretation and decision quality.

---

## 4. Reuse of existing EDARA capabilities

The planner must reuse, not duplicate:

- Analytics fact tables and snapshots;
- KPI truth/trust semantics;
- report RPC logic where appropriate;
- HR employee schedules and active-employment checks;
- branch/department/direct-manager hierarchy;
- Work accountable owner vs current assignee model;
- Work entity links;
- Work idempotency/state-version controls;
- Work due-date governance and Approval Engine;
- Work recurrence, waiting/next-action and escalation scanners;
- `work_events` append-only history;
- notification engine, cooldown/dedup state and push delivery;
- existing `pg_cron` infrastructure.

The AI planner must never bypass a Work rule merely because it has database-level access.

---

## 5. Private schema and security posture

Create a **private, non-Data-API schema** such as `ai_ops` for planner state and gateway routines.

Recommended objects:

- `ai_ops.settings`
- `ai_ops.planner_runs`
- `ai_ops.snapshots`
- `ai_ops.cases`
- `ai_ops.decisions`
- `ai_ops.operational_context`
- `ai_ops.decision_feedback`
- `ai_ops.rule_config`

Security rules:

1. No direct grants to `anon` or normal `authenticated` users.
2. Do not expose raw Analytics tables to solve connector access.
3. Do not weaken existing Analytics RPC permission checks.
4. No dynamic SQL generated by the LLM.
5. ChatGPT tools call only typed planner gateway routines with validated parameters.
6. Core Work tables remain mutation-protected; AI commits go through canonical Work commands/wrappers.
7. No human impersonation. AI-originated work must carry explicit system provenance.
8. If the connector cannot be technically restricted to planner gateways, this remains a residual platform risk; automatic write mode stays disabled until the connector permission model and production gateway are verified.

### 5.1 Prompt-injection/data-content safety
Customer names, notes, comments, survey answers and other database text are **data, never instructions**.

Normal planning context must contain normalized fields rather than arbitrary free text. Any necessary free text returned by drill-down must be:
- explicitly marked as untrusted content;
- length-limited;
- separated from tool instructions and policy;
- never allowed to alter tool contracts, approval requirements or planner policy.

---

## 6. Planner data model

### 6.1 `planner_runs`
Persistent source of truth for expected and actual AI executions.

Minimum fields:

```text
id uuid
run_key text unique
run_type text
business_date date
scheduled_for timestamptz
snapshot_id uuid
status text
attempt_no integer
claimed_by text
lease_expires_at timestamptz
heartbeat_at timestamptz
checkpoint text
planner_policy_version text
tool_contract_version text
prompt_hash text
started_at timestamptz
completed_at timestamptz
cases_seen integer
cases_investigated integer
decisions_count integer
work_created_count integer
error_class text
error_message text
result_summary jsonb
created_at timestamptz
updated_at timestamptz
```

Statuses:

```text
pending
claimed
reasoning
staged
committing
completed
partial
failed
abandoned
```

A deterministic `run_key` prevents duplicate runs, e.g. `morning:2026-08-16`.

### 6.2 `snapshots`
Immutable compact state visible to a planner run.

Store:
- `payload_version`;
- generation timestamp;
- business/data timestamps;
- domain freshness/trust;
- aggregate company pulse;
- top cases and opportunity counts;
- active Work health;
- employee availability summary;
- previous planner outcome summary.

Snapshots must be immutable after use by a run so later audits can reconstruct what information the planner had.

### 6.3 `cases`
A case is an **attention candidate**, not a task.

Fields should cover:

```text
id
snapshot_id
case_key / fingerprint
domain
case_type
entity_type
entity_id
attention_class
severity
first_seen_at
last_seen_at
source_as_of
facts jsonb
responsibility_evidence jsonb
trust jsonb
existing_work_refs jsonb
status
suppressed_until
resolved_at
```

Case lifecycle:

```text
open -> monitored -> actioned -> resolved
               \-> suppressed
               \-> expired
```

`case_key` must remain stable while the underlying business condition remains the same. This prevents rediscovering the same issue as a new problem every run.

### 6.4 `decisions`
One record per planner disposition, including no-action decisions.

Minimum content:

```text
case_id
run_id
decision_type
business_impact
urgency
confidence
evidence_completeness
reversibility
estimated_effort
recommended_owner_id
recommended_assignee_id
responsibility_basis
concise_rationale
expected_outcome
success_signal
review_after
validation_status
commit_status
work_item_id
idempotency_key
management_only_metadata
employee_safe_reason
created_at
```

Do not store hidden chain-of-thought. Store concise decision rationale and supporting evidence only.

### 6.5 `operational_context`
Structured, governed business context for facts the transactional system cannot know.

Examples:
- temporary customer credit arrangement;
- customer relationship personally managed by a specific owner;
- planned stock depletion for a campaign;
- temporary staffing responsibility;
- exceptional supplier agreement.

Required semantics:

```text
subject_type
subject_id
context_type
context_payload
owner_id
source_type
confidence_class
valid_from
valid_until
review_on
status
visibility
created_by
approved_by (when required)
```

Context confidence precedence:

1. hard system/policy constraint;
2. explicit approved human context;
3. explicit current business record/event;
4. system-derived inference;
5. AI inference.

AI inference alone must never override explicit human context or hard policy.

Every non-permanent context needs expiry/review semantics. Expired context cannot silently influence decisions.

### 6.6 `decision_feedback`
Structured feedback, never an employee penalty record.

Suggested reasons:

```text
accepted
already_handled
wrong_owner
wrong_timing
missing_context
not_actionable
lower_value_than_other_work
superseded_by_human_decision
data_incorrect
other
```

A free-text note may be optional and management-scoped.

---

## 7. Snapshot contract

### 7.1 Goal
One compact read should answer: **Where should attention go today?**

### 7.2 Payload shape

```text
run_context
  run_id
  run_type
  business_date
  snapshot_id
  generated_at
  data_as_of
  snapshot_status
  policy_version

trust
  domain_status[]
  stale_domains[]
  blocked_domains[]

company_pulse
  sales
  targets
  receivables
  treasury
  customers
  visits
  inventory
  people
  work

cases[]
  case_id
  domain
  case_type
  attention_class
  severity
  compact_facts
  responsibility_candidates
  existing_work_summary
  source_as_of
  trust

coverage
  total_cases
  returned_cases
  has_more_by_domain
  suppressed_cases_count

previous_run
  actions_created
  still_open
  outcomes_observed
  human_overrides
```

### 7.3 Payload budget
Normal context must be intentionally bounded.

Initial design target:
- aggregate pulse for all domains;
- top few material cases per domain;
- approximately 20–30 cases total maximum in the first payload;
- counts for omitted lower-ranked cases;
- no raw transaction history;
- no full customer list;
- no full product list.

The exact limit is a configuration, not a business rule. If many cases suddenly appear, that is itself a possible data/system anomaly and should trigger a circuit breaker rather than mass task creation.

---

## 8. Case/exception engine

The database determines **what changed or is unusual**. It does not determine the business action or owner.

Initial case families may include:

### Sales/targets
- material target trajectory gap;
- significant rep/customer/product deterioration;
- high-value opportunity not being progressed;
- unusual return rate;
- planned visit activity without expected downstream result.

### Customer health/re-engagement
- newly at-risk high-value customer;
- dormant high-value customer with credible reactivation potential;
- material fall in frequency/value;
- conflicting signals such as high potential plus unresolved credit exposure.

### Receivables/credit
- new overdue exposure;
- material ageing step change;
- broken collection commitment where such commitment exists;
- credit utilisation risk;
- debt growth outpacing confirmed collections.

### Inventory
- stockout/critical coverage with active demand;
- dead/slow stock with commercial relevance;
- abnormal movement;
- surplus that may justify a sales initiative.

### Visits
- missed planned visit;
- repeated low-conversion pattern;
- routing/coverage gap;
- important customer without expected contact.

### Work
- high-value work blocked or stale;
- work lacking an actionable next step;
- repeated missed outcome;
- business-critical item at risk even before its due date.

### HR/availability
- absence or schedule change that invalidates today's allocation;
- unavailable owner/assignee (existing Work continuity engine remains authoritative);
- capacity warning, used only as a planning constraint, not performance judgement.

---

## 9. Responsibility reasoning model

For each actionable case, the planner follows this sequence:

1. **Define the business condition** — what actually changed?
2. **Check whether it is expected** — is there approved context explaining it?
3. **Identify the proximate cause** — what most directly caused or sustains the condition?
4. **Identify current control** — who can change the next relevant state?
5. **Identify business accountability** — who owns the consequence?
6. **Identify execution capability** — who can perform the next concrete action?
7. **Check relationship continuity** — would assigning somebody else damage context/customer continuity?
8. **Check authority** — does the action require approval or a higher authority?
9. **Check capacity/availability/location fit**.
10. **Check existing work or recent activity**.
11. Only then select owner/assignee or choose no action/investigation.

Responsibility evidence may include:
- explicit operational-context owner;
- current Work owner;
- entity/account relationship owner;
- transaction or decision creator where meaningful;
- assigned representative;
- direct manager;
- department manager;
- branch manager;
- configured queue;
- recent relevant activity owner.

**Manager fallback must be last-resort routing, not the default.**

### 9.1 Owner and executor may differ
If a management-owned customer needs a routine call, a valid decision may be:
- accountable owner: manager/customer owner;
- executor: rep;

But the planner must not make this split automatically when high-context knowledge is likely required. It may instead ask the accountable owner to decide/delegate.

---

## 10. Decision types

Allowed planner dispositions:

### `IGNORE`
Noise or expected variation with no useful action.

### `MONITOR`
Material enough to watch, but intervention now would add little value.

Must include `review_after` or a deterministic re-evaluation condition.

### `INVESTIGATE`
Current evidence is insufficient. The planner requests batched drill-down or, if the missing information is human-only, creates/raises a focused information request.

### `INFORM`
A person should know, but no separate Work item is justified.

### `CREATE_WORK`
A concrete, valuable, executable action exists with clear responsibility and outcome.

### `ESCALATE`
Used only where contextual escalation adds value. Routine due/SLA escalation remains with the deterministic Work Engine.

---

## 11. Decision Quality Gate

Before `CREATE_WORK` or contextual `ESCALATE`, every intent must pass:

1. data freshness/trust acceptable for this decision;
2. case still exists at validation time;
3. no conflicting approved human context;
4. no equivalent active Work item;
5. no recent action already addressing the condition;
6. proposed owner is active/available under Work rules;
7. owner has plausible authority/accountability;
8. proposed executor has plausible capability and access;
9. action is operationally possible within the time window;
10. expected business value exceeds interruption cost;
11. effort fits available planning capacity;
12. customer/relationship contact collision is absent;
13. action is reversible or within approved automation tier;
14. expected outcome is measurable enough to review;
15. employee-facing reason contains no restricted information.

Failure does **not** force reassignment. It may convert the decision to `MONITOR`, `INFORM` or `INVESTIGATE`.

---

## 12. Human capacity and interruption model

### 12.1 Presence is not free capacity
Schedule/attendance is the maximum theoretical window, not assignable time.

Capacity reasoning should consider:
- scheduled working window;
- absence/leave/shift changes;
- active Work and next actions;
- estimated effort of already committed AI work;
- field travel/location constraints;
- role/skill fit;
- high-context obligations;
- reserve for unexpected work.

### 12.2 Minimal effort vocabulary
Until a mature capacity layer exists, AI-created work uses a lightweight estimate:

```text
S = short / low interruption
M = meaningful focus block
L = substantial work requiring planning
```

An optional minutes estimate may supplement the band, but it must not pretend to be precise time tracking.

### 12.3 Anti-overload guardrails
- Prefer a small number of high-value tasks.
- Midday runs should normally reuse/update existing work rather than add new items.
- Do not load reliable/high-performing employees merely because they clear work quickly.
- Do not fill every visible free hour.
- Keep a configurable reserve for routine/unplanned work.
- Sudden high-volume recommendations trip a circuit breaker and require review.

---

## 13. Tool contract and tool-call budget

Normal planner execution should require **2–4 connector calls**, not dozens.

### 13.1 `ai_claim_and_get_context(run_type)`
Atomically:
- finds/claims the due run;
- obtains/refreshes lease;
- returns compact immutable snapshot and cases;
- returns previous checkpoint on recovery.

No due run -> explicit no-op result.

### 13.2 `ai_get_case_details(case_ids[], depth)`
Batched drill-down for only selected cases.

`depth` should be bounded (`standard`, `deep`) and the gateway decides which approved report/read models are used. The LLM must not compose arbitrary source-table queries.

### 13.3 `ai_stage_and_validate_decisions(run_id, decisions[])`
Persists concise decision records and validates:
- current case state;
- collision with Work;
- owner/assignee availability;
- context conflict;
- action tier;
- payload schema;
- idempotency key;
- current Work state/version where relevant.

Returns per-decision status and any reason for rejection/needs-review.

### 13.4 `ai_commit_validated_decisions(run_id, decision_ids[])`
Commits only validated intents through Work commands and finalizes run state.

Every decision has its own idempotency key. Independent decisions may be isolated with database subtransactions so one failure does not lose all safe actions. Interdependent actions use an explicit `decision_group_id` and atomic-group semantics.

### 13.5 No-action completion
A run with only `IGNORE/MONITOR/INFORM` decisions still calls a finalization gateway so the run is visibly complete and not mistaken for a failed execution.

Every gateway call implicitly refreshes the run heartbeat/lease.

---

## 14. ChatGPT worker topology

The database owns **run expectation and run state**. ChatGPT scheduled tasks are workers that claim due runs; they are not the durable scheduler of truth.

Recommended worker roles:

### 14.1 Morning Planner
Main daily reasoning pass. Uses the latest trusted snapshot plus deltas from the previous business day.

Goal: choose today's highest-value interventions before work fragments the day.

### 14.2 Midday Delta Planner
Reads only material changes since morning plus status of morning actions.

Goal: correct course when reality changed. It must not recreate a full morning plan or generate work just because it ran.

### 14.3 End-of-Day Outcome Reviewer
Primarily evaluates:
- whether expected outcomes occurred;
- human overrides;
- unresolved cases;
- context candidates.

It should not normally create new non-urgent work late in the day.

### 14.4 Recovery Watchdog
A separate lightweight scheduled worker, ideally hourly during relevant operating windows.

It claims:
- overdue `pending` runs;
- runs whose lease expired;
- `partial` runs with retryable decisions.

It does not independently create a competing plan. Lease/idempotency rules make retries safe.

### 14.5 Platform-wide failure
If all ChatGPT workers fail, the database cannot manufacture LLM reasoning. Therefore a deterministic dead-man check must alert configured management/system administrators when a required run remains incomplete beyond its grace window.

This prevents **silent failure**, even when automatic recovery is temporarily impossible.

---

## 15. Run reliability model

### 15.1 Lease
A worker claims a run for a configurable lease period. Each gateway call refreshes the lease.

Expired lease means recoverable execution, not automatic failure.

### 15.2 Checkpoints
Recommended checkpoints:

```text
context_loaded
investigation_complete
decisions_staged
commit_started
commit_complete
```

Recovery resumes from durable state rather than repeating the whole analysis blindly.

### 15.3 Idempotency
Idempotency exists at multiple levels:
- deterministic run key;
- stable case fingerprint;
- decision idempotency key;
- canonical Work operation id;
- existing notification dedup/cooldown.

### 15.4 Partial degradation
If one domain is stale/unavailable:
- mark snapshot/run `partial`;
- exclude that domain from decisions;
- continue with trustworthy independent domains when safe;
- never represent the result as full-company coverage.

If Work validation/commit capability is unavailable, planner may analyse but cannot claim work was created.

---

## 16. Trust and source-of-truth rules

Every metric/case carries source timestamp and trust metadata.

Source precedence follows existing EDARA truth definitions, e.g. ledger/approved transaction truth over operational caches.

Planner policy must distinguish:
- official/verified financial metrics;
- operationally verified metrics;
- approximate managerial estimates;
- stale/unknown signals.

Approximate profitability may support prioritisation but must not silently drive an irreversible financial decision.

A significant data-quality/drift failure can itself become a **system integrity case**; it should not cause mass business tasks based on suspect numbers.

---

## 17. Work Management integration

### 17.1 AI provenance
Every AI-created Work item records:
- originating run;
- decision id;
- case id;
- planner policy version;
- system/AI source marker;
- concise employee-safe assignment reason.

Do not impersonate a human creator.

If the current Work command contract requires a human auth identity, implementation must add an explicit supported system-origin path rather than falsifying `creator_id`.

### 17.2 Reuse canonical Work semantics
AI must respect:
- accountable owner vs assignee;
- waiting + next action for ordinary follow-up;
- dependencies/checklists;
- approval-bound completion;
- availability checks;
- optimistic concurrency;
- idempotent operation IDs;
- append-only events.

### 17.3 Due dates
AI must never bypass due-date extension governance.

It may:
- propose a due change;
- create a review task;
- invoke the existing due-extension request path if policy explicitly allows.

It may **not** directly extend an existing due date.

### 17.4 Existing work first
If a live Work item already covers the business condition, prefer:
- monitor it;
- add an appropriate next-action recommendation through an allowed human-reviewed path;
- contextual escalation when warranted;

rather than creating another task.

---

## 18. Automation action tiers

### Tier 0 — Shadow
Read/analyse only. Decisions recorded for review; no Work creation.

### Tier 1 — Human approval
Planner stages recommended actions. A manager approves/edits/rejects before Work creation.

### Tier 2 — Low-risk auto-create
Only high-confidence, reversible operational Work creation after all validation gates pass.

Examples may eventually include a focused customer follow-up or review task where responsibility and context are unambiguous.

### Permanently human-sensitive boundary unless separately approved
The planner must not autonomously perform underlying business mutations such as:
- changing credit limits or payment terms;
- extending invoice/work due dates outside existing approvals;
- posting/refunding/approving money movements;
- inventory adjustments;
- payroll/salary changes;
- discipline, termination or legal action;
- permission/security changes;
- approval decisions on behalf of humans;
- destructive deletion;
- cancelling or transferring accountability of human Work without an explicitly designed policy.

Creating a **review task** about a sensitive case is different from executing the sensitive decision.

AI must never approve its own generated request/action.

---

## 19. Notification ergonomics

AI-generated work can create notification fatigue if each low-value item generates a separate interruption.

Integration should support:
- immediate notification for genuinely urgent/high-impact new work;
- digest/batched notification for ordinary AI-created items from the same run where feasible;
- no notification for `IGNORE/MONITOR` unless a configured review point is reached;
- management health alert for failed/missed planner runs;
- no repeated reminders when Work/notification cooldown already covers the case.

The Work item remains the source of execution truth; notification is only the delivery mechanism.

---

## 20. Outcome model and learning boundary

Completion is not the same as success.

AI-created Work must define:
- expected outcome;
- success signal;
- review time/condition.

Examples:
- not “call customer” but “obtain a confirmed next payment/contact commitment or document why one is not currently possible”;
- not “review stock” but “confirm whether replenishment/production action is required and record the decision”.

Outcome categories can include:

```text
achieved
partially_achieved
not_achieved
superseded
not_actionable
wrong_owner
external_dependency
context_changed
unknown
```

### 20.1 No uncontrolled self-learning
The LLM may propose:
- a context candidate;
- a rule/config review;
- a recurring false-positive pattern.

It may not silently change thresholds, permissions, routing rules, prompts or automation tiers.

Policy/config changes require explicit versioned human approval.

---

## 21. Management UX requirement

Before Tier 2 auto-create is enabled, provide a minimal management surface (inside Work Management, not a duplicate analytics dashboard) showing:

- last expected/successful planner run;
- current run health/failures/recovery;
- shadow/review recommendations;
- decision rationale/evidence/trust;
- approve/edit/reject in Tier 1;
- human feedback reason;
- operational-context records and expiry;
- planner-generated Work and actual outcomes;
- tool-call/run metrics.

Employees should see only their normal Work experience plus an employee-safe “why this was assigned” explanation where useful.

---

## 22. Observability and dead-man monitoring

Track at minimum:

```text
expected_runs
completed_runs
partial_runs
failed_runs
recovered_runs
missed_run_alerts
normal_tool_calls_per_run
drilldown_calls_per_run
cases_seen
cases_actioned
cases_monitored
zero_action_runs
work_created
duplicate_actions_prevented
validation_rejections
human_overrides
wrong_owner_feedback
work_outcomes
context_candidates_accepted
```

Do **not** optimise for `work_created`. High work volume is not a success KPI.

Important health metrics:
- run completion reliability;
- silent-failure count (target zero);
- duplicate creation count (target zero);
- owner/routing quality;
- useful-action acceptance;
- outcome quality;
- data freshness/trust;
- connector/tool efficiency.

---

## 23. Circuit breakers

Automatically stop auto-create for the affected run/domain when any of these occur:

- snapshot stale beyond configured tolerance;
- trust status below decision requirement;
- case volume changes abnormally;
- identity/hierarchy mapping is incomplete for a required action;
- Work command validation repeatedly fails;
- connector returns an unexpected contract version;
- proposed auto-actions exceed configured safe volume;
- a sensitive-action type appears;
- required operational context is conflicted/expired;
- planner attempts to act outside its allowlisted decision schema.

Degraded mode is `analyse/inform`, not “try harder with broader database access”.

---

## 24. Seed/config model

Initial migration should seed **configuration**, not hard-coded people UUIDs.

Use stable business codes and resolver functions where identities are necessary.

Seed categories:
- run types and planner windows;
- case-rule definitions and thresholds;
- attention limits per domain;
- trust requirements;
- action-tier allowlist;
- sensitive-action denylist;
- recovery/lease/grace settings;
- notification policy;
- policy/tool contract version;
- system planner owner/administrators by stable employee/role resolver where needed.

No initial auto-create enablement. Deploy in Shadow mode by default.

---

## 25. Rollout gates

### Phase A — Data contract verification
- snapshot reconciles with existing reports;
- trust/freshness semantics verified;
- no unnecessary PII/free text;
- context payload within tool budget.

### Phase B — Shadow mode
- planner runs automatically;
- creates no Work;
- management compares recommendations to real decisions;
- owner/reasoning mistakes and false positives are classified.

### Phase C — Human-approved recommendations
- Tier 1 management queue enabled;
- recommendation -> human decision -> Work flow validated;
- feedback and outcome capture proven.

### Phase D — Low-risk auto-create
Enable only allowlisted case/action combinations that have demonstrated stable routing and business value.

### Phase E — Expand carefully
Expand case coverage based on measured usefulness, not feature count.

No phase transition is automatic.

---

## 26. Acceptance invariants

The design is not ready for implementation/release unless all of the following are testable:

1. A missed ChatGPT worker execution remains visible in the database.
2. A second worker can safely recover an expired run.
3. Retry cannot create duplicate Work.
4. A run can complete successfully with zero actions.
5. Stale analytics cannot generate an affected-domain auto action.
6. Human approved context can suppress/redirect an otherwise obvious task.
7. Org role alone cannot determine responsibility when stronger causal evidence exists.
8. An inactive employee cannot receive new Work.
9. Existing related Work prevents duplicate creation.
10. Human due-date decisions/approvals cannot be overwritten by AI.
11. Sensitive actions cannot be auto-executed.
12. Employee-facing rationale does not leak management-only context.
13. Planner failure produces a deterministic health alert after the grace window.
14. Tool output containing arbitrary user text cannot alter planner policy/tool instructions.
15. High-volume data anomalies trip a circuit breaker instead of creating mass tasks.
16. Outcome review distinguishes “task done” from “business result achieved”.
17. Human rejection/override is captured as feedback without becoming an employee penalty.
18. Planner policy and tool-contract versions are recorded per run.

---

## 27. Implementation boundary

This specification intentionally defines **what must be built and how it must behave**. It does not authorize implementation, database migration, ChatGPT automation creation, production writes, merge or deployment.

Implementation should begin only after the acceptance-scenario companion document has been reviewed against real Delight cases and this specification is accepted as the design baseline.
