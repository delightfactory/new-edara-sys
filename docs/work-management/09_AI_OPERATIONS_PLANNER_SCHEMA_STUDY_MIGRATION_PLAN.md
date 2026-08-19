# Delight AI Operations Planner — Live Schema Study & Migration Plan

**Status:** Engineering plan — no AI migration implemented  
**Branch:** `feature/work-management`  
**Study target:** current `NEW-EDARA-SYS` production schema, read-only inspection  
**Primary goal:** add AI-assisted operational planning without altering current operational semantics, adding unnecessary load, or weakening security boundaries.

---

## 1. Executive engineering decision

The AI Operations Planner can be added with a **small, additive and isolated migration series**. The current schema already contains most of the hard infrastructure needed:

- a mature Analytics/reporting layer;
- `pg_cron` scheduling;
- Work Management system actors, system source kinds and idempotent source keys;
- append-only Work events;
- existing Work notification dispatch;
- HR hierarchy/schedule data;
- indexed operational sources for overdue sales, stock movement, customers, targets and Work;
- existing `private` server-side command patterns.

The safest implementation therefore does **not** modify core Sales, Customer, Inventory, HR, Visit or Analytics transaction paths.

The first AI migrations must follow:

> **Additive → Isolated → Disabled by default → Reversible → Measurable → No source-table triggers.**

Applying the AI foundation migration must change **zero existing user-facing behaviour**.

---

## 2. Live-schema findings that materially change the design

### 2.1 Current operational scale

At study time the database contained approximately:

| Source | Current rows / size signal |
|---|---:|
| `sales_orders` | 8,078 / ~12 MB |
| `sales_order_items` | 18,110 / ~5.2 MB |
| `customers` | 1,885 / ~3.4 MB |
| `stock_movements` | ~2,157 / ~1.1 MB |
| `stock` | ~232 |
| `activities` | ~162 |
| `hr_attendance_days` | ~222 |
| `hr_employees` | 9 |
| `work_items` | 1 |

This is modest for PostgreSQL, but large enough that repeated full scans every few minutes would be poor engineering. Snapshot/case generation should run at low frequency and use indexed/current sources.

### 2.2 Analytics already performs the heavy historical work

Largest current Analytics relations include approximately:

- `analytics.snapshot_customer_health` ~27 MB;
- `analytics.snapshot_customer_risk` ~26 MB;
- `analytics.fact_sales_daily_grain` ~15 MB.

The hourly Analytics sweep is healthy and inexpensive relative to the rest of the application: recent executions were generally around one second.

The AI layer should consume this work rather than reread transaction history during every ChatGPT run.

### 2.3 Critical semantics: customer Health/Risk snapshots are DELTA-oriented, not full current-state snapshots

The existing refresh procedure for `snapshot_customer_health` identifies only customers affected by Sales/Ledger activity on target dates, deletes those target-date snapshots, and rebuilds rows for that affected set. `snapshot_customer_risk` then consumes those rows.

Therefore:

> **`snapshot_customer_health/risk WHERE as_of_date = today` must NOT be interpreted as the complete current customer population.**

These relations are useful for historical/change evidence, but the AI customer-current-state layer needs a separate bounded current-state calculation or a validated current-state source.

This finding prevents a serious false-completeness failure in the planner.

### 2.4 Existing customer re-engagement report is a better current-state semantic reference

`customer_reengagement_list/summary` already calculates the current active customer universe from `customers + delivered/completed sales_orders`, including:

- historical revenue;
- last 90-day revenue;
- previous 90-day revenue;
- recency;
- assigned rep;
- outstanding balance;
- value tier;
- `CHAMPION_LOST / DECLINING_HIGH / MID_LOST / MID_AT_RISK` prioritisation.

It currently enforces human `auth.uid()` report permissions and cannot be used directly by a system worker. Initial AI implementation should preserve its semantics without modifying the public report RPC first.

### 2.5 Causal credit responsibility is supported by real schema evidence

Relevant evidence already exists:

- `sales_orders.created_by_id`;
- `sales_orders.rep_id`;
- `customers.assigned_rep_id`;
- `sales_orders.credit_override_by`;
- `customer_credit_history.changed_by + reason`;
- `sales_order_due_date_history.changed_by + reason`.

This allows the Responsibility Resolver to reason about the transaction creator, relationship owner, salesperson, actual credit override authority and last due-date decision separately.

The planner must treat each as evidence, not as a hard routing rule.

### 2.6 Work already supports a clean system-origin path

No Work schema extension is required for AI provenance:

- `work_source_kind` already includes `system`;
- `work_actor_kind` already includes `system`;
- `work_items.creator_user_id` is nullable;
- `work_items.source_key` exists;
- `work_items.metadata` exists;
- unique `(source_kind, source_key)` already provides a strong idempotency guard;
- `private.work_append_system_event()` already writes system events with no fake human actor.

Therefore the AI implementation must **not**:

- create a fake “AI employee” profile;
- add an `ai_creator_id` column;
- extend Work source enums;
- ALTER Work tables merely for provenance.

### 2.7 Human Work command cannot be reused as an AI identity

`public.work_create_task()` derives actor identity from `auth.uid()` and applies human assignment permissions. A scheduled/system AI worker must not invoke it while pretending to be a human.

The correct integration is a **small system-only Work bridge** that consumes an already validated AI decision and follows existing system Work patterns.

### 2.8 Existing Work notifications can be reused

The current Work event trigger dispatches assignment notifications when `work.activated` is inserted. An AI-created Work item can therefore:

1. be inserted as `source_kind='system'`;
2. receive an AI provenance system event;
3. receive a standard system `work.activated` event;
4. reuse the existing Work notification path.

No new operational notification trigger is required.

---

## 3. Source-table change policy

### 3.1 Forbidden in the initial AI migration series

Do **not** add AI triggers to:

- `sales_orders` / `sales_order_items`;
- `customers`;
- `stock` / `stock_movements`;
- `products`;
- `activities` / visit-plan tables;
- HR attendance/employee tables;
- core Work tables.

Do **not** weaken existing Analytics/RPC permission checks so a connector can call them without a user session.

Do **not** add an index to an operational table merely because the AI layer may use it.

Do **not** modify existing report semantics as part of the AI foundation.

### 3.2 Why

These tables already carry business triggers, validations, notifications or lifecycle logic. AI triggers would introduce avoidable coupling and make operational latency harder to reason about.

Current indexes already cover the primary planned AI access paths, including:

- overdue invoices;
- sales effective date/customer/rep;
- customer assignment/status/search;
- stock movement product/type/date;
- attendance employee/date;
- Analytics date/customer/rep/trend;
- Work source-key idempotency and status/action scans.

If an isolated `EXPLAIN (ANALYZE, BUFFERS)` later proves a missing source index, that index must be proposed in a **separate migration with a separate regression review**.

---

## 4. Isolation boundary

Create a dedicated schema:

```text
ai_ops
```

Do not place new AI tables inside the existing `private` schema. `private` already contains Work and Visit operational internals and currently has broader schema usage than a dedicated AI boundary should have.

### 4.1 `ai_ops` security defaults

At creation:

- revoke all privileges from `PUBLIC`;
- no direct grants to `anon`;
- no direct grants to normal `authenticated` users;
- enable RLS on all planner-state tables even though direct access is revoked;
- add no end-user RLS policies in foundation;
- explicitly verify `ai_ops` is not exposed through the Data API/PostgREST schema list;
- system gateways use fixed `search_path=''` and fully-qualified object names;
- no dynamic SQL accepted from a planner response.

### 4.2 Cross-domain references

Prefer soft typed references for business entities in `ai_ops`:

```text
entity_type
entity_id
```

Validate existence in gateway/case builders. Avoid foreign keys from planner history to operational business rows unless a later requirement clearly justifies the coupling.

Internal `ai_ops -> ai_ops` foreign keys are appropriate.

This avoids delete/update coupling and keeps planner-history retention independent from transaction lifecycle.

---

## 5. Migration series

The AI work should be delivered as small reviewable cubes. Each migration is independently safe and has a feature/activation boundary.

# Migration A — prerequisite reliability/security corrections

**Not an AI migration. Must be separate. Not executed by this plan.**

Before autonomous AI write mode is accepted, resolve current baseline issues documented in Section 11.

Recommended separate migrations:

- fix attendance absence-notification enum drift;
- harden exposed opening-balance audit tables;
- review remaining RLS-disabled advisor findings.

These corrections must not be hidden inside AI migration files.

---

# Migration 1 — `ai_operations_planner_foundation`

### Purpose
Create the isolated state model with **zero scheduled behaviour** and **zero Work writes**.

### Objects

Recommended tables:

#### `ai_ops.settings`
Single active configuration record or versioned configuration.

Minimum controls:

```text
planner_enabled              false
shadow_mode                  true
auto_commit_enabled          false
timezone                     Africa/Cairo
max_context_cases            25
max_drilldown_cases          bounded
max_snapshot_bytes           bounded
case_explosion_limit         bounded
lease_minutes                bounded
policy_version
tool_contract_version
```

#### `ai_ops.run_schedules`
Business schedules only; seed disabled.

```text
run_type
local_time
weekdays / cadence
enabled = false
primary_worker_window
recovery_window
```

#### `ai_ops.planner_runs`
Persistent orchestration source of truth.

Use deterministic unique `run_key` such as:

```text
morning:2026-08-16
midday:2026-08-16
```

Include status, lease, checkpoint, attempt count, policy/tool versions, timestamps, metrics and bounded error information.

#### `ai_ops.snapshots`
Immutable planner input record:

- compact JSON payload;
- generation/data timestamps;
- domain trust/freshness;
- payload version;
- hash/size metadata.

#### `ai_ops.cases`
Stable attention candidates with `case_key`/fingerprint and lifecycle.

#### `ai_ops.decisions`
Planner disposition and concise rationale/evidence, including decisions that create no Work.

#### `ai_ops.operational_context`
Governed human knowledge unavailable from raw transactions, with validity/expiry/review.

#### `ai_ops.decision_feedback`
Human outcome/override feedback; not an employee-scoring table.

### Index policy
Add only indexes on these new tables, e.g.:

- unique run key;
- due run lookup `(status, scheduled_for)`;
- lease expiry;
- snapshot/run linkage;
- case key/status/domain;
- decision run/case/commit status;
- active operational context by `(subject_type, subject_id, status, valid_until)`.

### Lock/resource risk
Very low: new schema/tables/indexes only. No source-table rewrite or backfill.

### Behaviour after apply
None. Everything disabled.

### Rollback
Drop `ai_ops` only while no released planner history exists. After release, use forward migrations rather than destructive rollback.

---

# Migration 2 — `ai_operations_planner_snapshot_engine`

### Purpose
Generate compact, deterministic planning snapshots and cases without ChatGPT reading raw history.

### Execution policy
- set-based SQL;
- bounded results;
- no trigger-based generation;
- no per-customer N+1 query loops;
- no LLM involvement;
- transaction timeout/statement timeout appropriate to the environment;
- partial-domain failure is recorded, not disguised as complete coverage.

### Domain source strategy

#### Sales
Use `analytics.fact_sales_daily_grain` for period aggregates and trajectory/context where its semantics fit.

#### Targets
Use current target-progress/snapshot sources with explicit `as_of_date`; verify daily coverage in tests.

#### Customers
Do not use current-date `snapshot_customer_health/risk` as a full population.

Initial current-state customer candidates should use a bounded aggregation equivalent to the current re-engagement semantics. Because the current dataset is approximately 8k orders / 1.9k customers, one morning set-based calculation is acceptable; repeated high-frequency calculation is not.

Contract-test the AI current-state output against the established re-engagement report for representative fixtures before release.

#### Receivables/credit
Use the existing indexed overdue model and enrich responsibility evidence from:

```text
customer.assigned_rep_id
sales_order.rep_id
sales_order.created_by_id
sales_order.credit_override_by
latest customer_credit_history.changed_by/reason
latest sales_order_due_date_history.changed_by/reason
existing Work
active operational context
```

Do not infer decision ownership from `created_by_id` alone.

#### Inventory
Generate only compact exceptions: critical/low cover, stockout with demand, dead/surplus relevance, unusual movement. The current source is small; run once at planning-window refresh, not every ChatGPT tool call.

#### Visits
Use current visit plans/activities and existing report grain; distinguish low activity from low conversion.

#### HR/availability
Use current employee schedule/attendance as constraints. Presence must not be converted to “free capacity.”

#### Work
Use Work statuses/flags/next actions and existing links; waiting with a future next action suppresses duplicate follow-up.

### Snapshot budget
Initial target:

- 20–30 top material cases in normal context;
- aggregate counts for omitted cases;
- typical payload target ~20–40 KB;
- hard serialized payload cap, initially no more than ~128 KB;
- no unbounded free text;
- no raw transaction history.

Limits are configuration, not business semantics.

### Circuit breaker
If a normally small case population suddenly becomes anomalously large:

- mark snapshot degraded/anomalous;
- suppress mass auto-actions;
- require data/system review;
- permit only separately verified critical cases under later policy.

### Lock/resource risk
Low. Reads existing indexed data and writes only `ai_ops` tables. No source ALTER/trigger.

### Rollback
Disable snapshot settings/jobs; keep history. Functions/tables remain harmless when planner is disabled.

---

# Migration 3 — `ai_operations_planner_worker_gateway`

### Purpose
Expose a small typed worker contract around persisted state.

### Candidate private gateway functions

```text
ai_ops.claim_due_run(worker_id, supported_contract_version)
ai_ops.heartbeat_run(run_id, worker_id)
ai_ops.get_planning_context(run_id, worker_id)
ai_ops.get_case_details(run_id, case_ids[])
ai_ops.stage_decisions(run_id, decisions_json)
ai_ops.validate_staged_decisions(run_id)
ai_ops.complete_run(run_id, result_summary)
ai_ops.fail_run(run_id, error_class, bounded_error)
```

Actual external exposure must be through the smallest available safe app/action surface; raw administrative SQL is not an acceptable security boundary for autonomous write mode.

### Lease/checkpoint rules
- claim atomically;
- one active lease per run;
- expiry permits recovery;
- heartbeat may extend lease only for current claimant;
- checkpoint is persisted after context load and decision staging;
- retry after crash must be idempotent.

### Decision staging rules
- allowed decision enum only;
- bounded strings/arrays;
- no SQL, executable expressions or unbounded arbitrary payloads;
- no hidden chain-of-thought stored;
- concise rationale + evidence references only;
- consequential actions remain `staged`, not committed.

### Behaviour after apply
Still Shadow Mode. Planner may persist analysis/decisions but cannot create Work unless later explicit activation gate is opened.

---

# Migration 4 — `ai_operations_planner_work_bridge`

### Purpose
Convert a **validated decision record** into canonical Work without human impersonation.

### Critical contract
The system Work function should accept a **decision ID**, not arbitrary Work fields supplied directly by the LLM.

Candidate internal command:

```text
private.work_create_ai_system_task(p_decision_id uuid)
```

The command must re-read trusted staged fields and revalidate current state at commit time.

### Revalidation before commit

- decision is in an allowed validated state;
- run/contract/policy versions are acceptable;
- source case still exists and remains material;
- data trust/freshness is acceptable;
- no conflicting active human operational context;
- no equivalent open Work/current action;
- owner and assignee are valid/active/available for Work;
- responsibility reason exists;
- expected outcome and next action are nonblank;
- due date/effort are plausible;
- action family is in the low-risk allowlist;
- no prohibited source-domain mutation is implied.

### Work write shape

```text
kind                   task
source_kind            system
source_key             ai_ops:decision:<decision_uuid>
creator_user_id        NULL
requester_user_id      NULL
accountable_owner      resolved real human
current_assignee       resolved real human
metadata               minimal provenance only
```

Existing `(source_kind, source_key)` unique index becomes the final duplicate guard.

Append:

1. an AI provenance system event, e.g. `work.ai_planner.created`;
2. a standard system `work.activated` event.

The second event intentionally reuses the existing Work assignment notification path.

### Explicitly prohibited autonomous source actions
This bridge never:

- changes customer credit limit;
- changes sales-order due date/terms;
- posts financial entries;
- changes inventory balances;
- approves expenses;
- changes salary/payroll;
- terminates/penalizes employees;
- changes roles/access/security;
- approves an approval requested by the AI itself.

It creates Work only.

### Activation
`auto_commit_enabled` remains `false` until isolated acceptance + security-channel acceptance + explicit business approval.

---

# Migration 5 — `ai_operations_planner_scheduler_reliability`

### Purpose
Make expected AI runs observable/recoverable independently of ChatGPT’s own scheduler.

### Database scheduler model
Use **one cheap planner scheduler tick**, not many domain jobs.

Recommended cadence shape:

```text
7,22,37,52 * * * *
```

or an equivalent offset selected after final production timing review.

Why offset:
- Analytics runs at minute 0;
- Work recurrence/workflow jobs run every 5 minutes;
- attendance/other jobs cluster on 15-minute boundaries;
- an offset avoids unnecessary concurrency.

Most ticks should perform an indexed no-op.

When a run is due:
- create deterministic run record if absent;
- build/finalize the snapshot once;
- expire abandoned leases safely;
- mark stale overdue runs;
- invoke EDARA-side dead-man notification if the expected planner window is missed.

### No automatic first-run flood
Seed schedules disabled. Enabling a schedule must not backfill prior days unless explicitly requested.

### Heavy work frequency
Default design expectation: approximately 1–3 substantive snapshots per business day, not continuous recomputation.

---

## 6. ChatGPT automation topology

Database scheduling and ChatGPT scheduling serve different purposes.

### Database owns
- whether a run should exist;
- run identity;
- snapshot/case state;
- lease/recovery state;
- idempotency;
- missed-run detection;
- dead-man alert.

### ChatGPT owns
- ambiguity resolution;
- causal reasoning;
- prioritisation;
- responsibility choice;
- contextual trade-offs;
- decision disposition.

### Suggested workers

#### Primary planner worker
Runs after the intended database snapshot window and claims the due run.

#### Recovery worker
Runs later, claims only expired/pending incomplete runs, and exits immediately when none exists.

#### Optional midday delta worker
Only if business testing proves enough value. It consumes changes since morning, not a second full-company report.

Do not create separate ChatGPT automations for Sales, Inventory, AR, HR, etc. The snapshot is the multiplexing layer.

---

## 7. Tool-call budget

Normal successful planner run target:

1. claim + compact planning context;
2. optional one batched drill-down call;
3. stage/validate decision batch;
4. complete run or, in an approved later tier, commit validated low-risk Work batch.

Target: **2–4 meaningful tool calls** for most runs.

The database does not return thousands of rows to the LLM. The LLM does not reconstruct KPIs already available in SQL.

---

## 8. Resource budget and performance gates

### Initial targets

- planner scheduler no-op: low-millisecond/indexed target;
- snapshot generation: preferably a few seconds maximum under current production scale, measured before release;
- normal snapshot payload: ~20–40 KB target;
- hard snapshot payload cap: bounded/configurable;
- no source-table lock stronger than ordinary read locks during snapshot generation;
- no migration table rewrite on operational relations;
- no new source index in baseline migrations;
- no high-frequency full-company aggregation.

### Required pre-release performance evidence
In an isolated/runtime-like DB:

- `EXPLAIN (ANALYZE, BUFFERS)` for each case-builder query;
- query count per snapshot;
- rows scanned vs returned;
- snapshot runtime P50/P95 across representative fixture/data copy;
- scheduler no-op runtime;
- Work commit runtime;
- concurrent run claim test;
- Analytics + AI snapshot overlap test;
- Work cron + AI tick overlap test.

If any current application query regresses materially, the AI migration fails acceptance.

---

## 9. Retention / growth controls

Planner state will be small relative to transactional history if bounded correctly.

Recommended initial retention semantics:

- keep run/decision audit history long enough for operational learning and incident review;
- keep compact immutable snapshots for a bounded period, then retain summary/hash if needed;
- cases can remain as lifecycle records but avoid duplicating raw business history;
- free-text evidence should be minimal and bounded;
- do not copy customer/sales ledgers into `ai_ops`.

Retention cleanup can be a later set-based routine. No second cron job is required initially; the main scheduler may perform low-frequency bounded cleanup.

---

## 10. Rollout gates

### Tier 0 — schema only
- migrations 1–2 deployed in isolated environment;
- planner disabled;
- no scheduled ChatGPT worker;
- verify no operational regression.

### Tier 1 — shadow analysis
- planner enabled for snapshots/runs;
- no Work writes;
- compare AI recommendations with management judgement for a trial window;
- measure false positives, wrong-owner rate, duplicate detection, missing-context rate.

### Tier 2 — human-approved Work creation
- staged decisions visible for review;
- human approval commits Work through the system bridge;
- collect feedback.

### Tier 3 — narrowly allowlisted low-risk auto-create
Only after explicit acceptance of:

- decision quality;
- Work ownership quality;
- connector/action boundary;
- security baseline;
- missed-run recovery;
- idempotency;
- no-regression evidence.

Sensitive business mutations remain human-owned regardless of tier.

---

## 11. Pre-existing findings that must be addressed before autonomous activation

These issues were discovered during read-only study. They were **not caused by AI work and were not modified**.

### 11.1 Attendance absence notification cron is currently broken

`notify-absent-employees` has been failing repeatedly because its SQL still checks an obsolete enum value:

```text
approved_hr
```

Current `hr_leave_request_status` values include:

```text
draft
pending_supervisor
approved_supervisor
pending_hr
approved
rejected
cancelled
```

`approved_hr` does not exist.

A recent 24-hour sample showed all scheduled executions failing.

**Decision:** fix as a separate reliability migration before considering the automation baseline healthy.

### 11.2 Opening-balance audit tables have material direct exposure

Supabase security advisor flags several RLS-disabled relations. Direct privilege review found the highest-priority exposure on:

- `public.customer_opening_balance_audit`;
- `public.supplier_opening_balance_audit`.

Both currently have broad direct privileges for `anon` and `authenticated` while RLS is disabled.

**Decision:** review actual application dependency, then harden via dedicated security migration. Do not bundle this correction with AI schema work.

Other advisor findings (`internal_config`, Analytics ETL state, private Work operation ledger) require hardening review as well, but their current direct grants are narrower and must be assessed independently rather than treated as the same exposure class.

### 11.3 Current Supabase ChatGPT app permission is too broad for autonomous write trust

At study time the connected Supabase app was configured as:

```text
Allow all actions
```

The connected tool surface includes privileged database operations. A prompt instruction such as “only call the AI gateway” is **not a security boundary**.

Therefore:

> **Automatic Work creation must stay disabled while the scheduled worker has an unrestricted administrative database action surface.**

Acceptable later solutions include a bounded app/action/tool surface that exposes only planner gateways, or another verified control that prevents arbitrary database mutation at the capability level.

Changing ChatGPT’s “ask before write” behaviour is not equivalent to reducing the underlying app’s actual database access; capability restriction remains the preferred production boundary.

---

## 12. Migration lock-safety rules

Every migration in this series must be reviewed for:

- table rewrite risk;
- AccessExclusive lock duration;
- index build behaviour;
- function replacement dependency;
- RLS/grant effects;
- PostgREST exposure;
- pg_cron duplicate-name/idempotency;
- rollback/forward-fix path.

Migration transaction requirements:

1. use explicit guards/idempotent existence checks where appropriate;
2. fail fast on unexpected schema prerequisites;
3. never silently drop/recreate an existing operational object;
4. no `CASCADE` against current production business objects;
5. seed disabled states only;
6. do not backfill AI historical data in the deployment transaction;
7. historical testing/backfill, if ever needed, is a separate controlled operation.

---

## 13. Validation matrix before any production AI migration

### Schema
- fresh local/isolated database migration chain;
- migration apply twice where safe/idempotency applies;
- no name collision with existing functions/types/tables;
- grants/RLS inspection.

### Operational regression
- login/profile;
- sales order create/deliver/return;
- customer credit/due-date paths;
- inventory movement;
- attendance;
- visits;
- existing reports;
- Work task lifecycle;
- Work recurrence/workflow/notification cron.

### AI-specific
- snapshot completeness flags;
- stale-domain handling;
- case explosion breaker;
- duplicate case/work prevention;
- management-owned overdue invoice scenario;
- wrong-owner ambiguity -> investigate;
- human context expiry;
- prompt-injection text treated as data;
- worker crash after context load;
- worker crash after Work commit;
- two concurrent workers;
- dead-man missed-run alert;
- connector/tool-contract mismatch.

---

## 14. Implementation order

Recommended next coding sequence after plan approval:

1. resolve/approve prerequisite baseline fixes separately;
2. implement Migration 1 foundation + contract tests;
3. implement current-state snapshot/case SQL for **one domain first** (Receivables/Credit is the strongest causal test case);
4. add Sales/Targets, Customer opportunities, Inventory, Visits, HR/availability, Work health incrementally;
5. validate payload size/runtime and current report equivalence;
6. implement worker lease/gateway in Shadow Mode;
7. run recorded management-review trial;
8. implement Work system bridge only after decision quality is acceptable;
9. implement scheduler/dead-man reliability;
10. verify a bounded ChatGPT action surface before enabling autonomous Work creation;
11. seed actual business schedules only after explicit acceptance.

This order deliberately proves value and decision quality before granting write autonomy.

---

## 15. Final design conclusion

The live schema confirms that the planner does **not** require invasive database work.

The safest target architecture is:

```text
Operational modules (unchanged)
        |
        | indexed reads / existing analytics
        v
      ai_ops
 snapshots -> cases -> runs -> staged decisions -> context/feedback
        |
        | validated decision ID only
        v
private Work system bridge
        |
        v
existing Work engine/events/notifications
```

The migration program should therefore be judged successful not by how much schema it adds, but by how little of the existing operational system it needs to touch.

**No AI migration, cron, connector permission change, Work auto-create or production behaviour change is authorised by this document.**
