# AI Operations — Sales & Targets Source Map

**Status:** implementation source map for the Sales & Targets AI Operations domain  
**Branch:** `feature/work-management`  
**Production posture:** production inspection is read-only; this document authorizes no production migration or mutation  
**Parent specs:** `07_AI_OPERATIONS_PLANNER_SPEC.md`, `08_AI_OPERATIONS_PLANNER_ACCEPTANCE_SCENARIOS.md`

---

## 1. Domain objective

The Sales & Targets domain must answer a useful operating question:

> Which currently governed sales targets are materially off trajectory, what factual drivers are visible, who has plausible business accountability or execution context, and is a new intervention actually justified?

A target gap is an **attention case**, not automatically a task and not automatically an employee-performance judgement.

The domain must avoid low-value output such as "increase sales" or assigning a target gap to the transaction creator. It must preserve the distinction between target accountability, sales contribution, field execution, authority and actual next action.

---

## 2. Reality-study findings from the live production schema

### 2.1 Canonical target truth

Existing operational sources:

- `public.targets`
- `public.target_progress`
- `public.target_types`
- `public.target_adjustments`

The deployed target engine is already the canonical deterministic calculator. `public.recalculate_target_progress(...)` defines target achievement and trajectory semantics and writes the official `target_progress` snapshots.

AI Operations **must not recalculate or replace that authority**. The planner consumes the latest official `target_progress` row at or before the requested planner business date.

If that row belongs to an earlier date, the case remains visible, but every deterministic metric must remain aligned to that same snapshot date. The planner records `metrics_as_of`, snapshot age and freshness explicitly and must not present an older metric as current-state evidence.

Relevant trend semantics in the deployed target engine:

- `exceeded`
- `achieved`
- `on_track`
- `at_risk`
- `behind`

The engine computes expected progress from elapsed calendar days inside the target period and stores `days_elapsed`, `total_days` and `expected_pct` in `target_progress.calc_details`.

### 2.2 Initial target types in this slice

This slice intentionally supports only:

- `sales_value`
- `product_qty`

The following remain in their proper domains rather than being mixed into this slice:

- `reactivation` → Customer Health / Re-engagement
- `category_spread` → Customer Health / Commercial Development
- `visits_count` / `calls_count` → Visits / Field Execution when used as primary cases
- `collection` → Receivables / Credit

### 2.3 Official sales achievement semantics

`recalculate_target_progress` confirms:

#### `sales_value`

- scope members are active `hr_employees` selected by target scope;
- order ownership uses `sales_orders.rep_id` mapped to `hr_employees.user_id`;
- only `delivered` or `completed` orders count;
- official sales date is `sales_orders.delivered_at::date`;
- ordinary value targets use `GREATEST(total_amount - returned_amount, 0)`;
- product/category-filtered targets use eligible order items less confirmed return items;
- governorate/city/area filters are respected.

#### `product_qty`

- the same scope membership and delivery-date boundary apply;
- achievement uses `GREATEST(delivered_quantity - returned_quantity, 0)`;
- product/category filters are respected.

AI contribution evidence must preserve these semantics. It must never use order creation date as the official sales date.

When the latest official progress is older than the requested planner date, contribution evidence is recomputed only through `metrics_as_of` so its total can still be reconciled to the stored official achievement.

### 2.4 Responsibility evidence

Target scope ownership is evidence, not hard routing.

- `individual` scope points to `hr_employees.id`; the employee `user_id` is an actor candidate;
- `department` scope may use `hr_departments.manager_id` as management-accountability evidence;
- `branch` scope may use `branches.manager_id` as management-accountability evidence;
- `company` has no safe implicit actor in the target row and must not manufacture one;
- `targets.assigned_by` identifies who assigned/set the target and is **context only**, not automatic accountability.

For the current Sales department target, production shows the department manager as Ahmed Abdelkader while the target was assigned by Ahmed Salama. The planner must keep those roles distinct.

### 2.5 Team contribution evidence

Per-employee contribution can be deterministically reproduced with the same target rules and checked against official `target_progress.achieved_value`.

Contribution is **driver evidence**, not blame and not an automatic owner-selection rule.

A parity mismatch is a trust failure that must remain visible; it must not be hidden by the reasoning layer.

### 2.6 Field-execution evidence

Available sources include:

- `public.visit_plans`
- `public.visit_plan_items`
- `public.activities`
- `public.activity_types`

Field activity is not uniformly planned for every employee contributing to a department target. Therefore this slice may expose bounded field-execution evidence, but it **must not deterministically label a department target gap as "low activity" or "poor conversion" unless comparable governed expectations are available**.

Field-execution evidence is also bounded by `metrics_as_of`; it is never allowed to mix later visits/calls with an older official target snapshot.

### 2.7 Opportunity / pipeline data

No trusted operational Lead / Opportunity / Pipeline table was found in the live production schema.

Therefore the planned case family "high-value opportunity not being progressed" is **not implemented in this slice**. It remains future scope only after a canonical opportunity source exists.

### 2.8 Existing Work collision

`public.work_links.entity_id` is UUID, so a target can be linked as:

- `entity_type = 'target'`
- `entity_id = targets.id`

The case kernel surfaces exact active Work linked to the target so downstream reasoning can prefer continuity over duplicate work creation.

---

## 3. Case contract

### 3.1 Identity

```text
domain: sales
case_type: target_trajectory_gap
entity_type: target
entity_id: targets.id
case_key: sales:target_trajectory_gap:<target_uuid>
attention_class: exception
```

### 3.2 Eligibility

A target is eligible when all are true:

1. it is active and not paused;
2. requested business date lies inside the target period;
3. type is `sales_value` or `product_qty`;
4. at least one canonical `target_progress` row exists at or before the requested business date;
5. the latest such progress row is `behind` or `at_risk`.

The AI kernel does **not** invoke `recalculate_target_progress`; planner source capture remains read-only against operational target tables.

If the latest progress row predates the requested business date:

- the case is **not hidden**;
- `progress_snapshot_date` / `metrics_as_of` identify the true measurement date;
- `progress_snapshot_age_days` records the gap;
- `requires_progress_refresh_for_current_action = true`;
- the evidence remains reviewable, but it is not treated as current-state action evidence until the official progress is refreshed.

Missing official progress entirely is a source-integrity condition; AI must never manufacture the missing KPI.

### 3.3 Materiality and severity

Initial severity policy avoids alarm inflation:

- `at_risk` → `medium`
- `behind` → `high`
- `critical` only when at least 75% of the **official metrics-as-of target period** has elapsed and the target remains behind with a materially poor projected/minimum position.

Severity, projection and pace all use the same canonical `metrics_as_of`. The requested planner date does not silently advance those calculations when the official snapshot is older.

### 3.4 Core facts

Each case exposes, where available:

- target identity/name/type/unit;
- target scope and period;
- requested planner business date;
- `progress_snapshot_date` and `metrics_as_of`;
- snapshot age and exact-business-date flag;
- target/minimum/stretch values;
- official achieved value and achievement percentage;
- expected progress percentage from the official snapshot;
- trajectory gap;
- remaining amount/quantity as of the official snapshot;
- elapsed/remaining days as of `metrics_as_of`;
- actual and required daily pace as of `metrics_as_of`;
- projected value from the same official window;
- product/category/geographic filters;
- last canonical progress calculation timestamp;
- deterministic team contributions reconciled to the same snapshot;
- bounded field execution through the same snapshot date;
- exact active linked Work when one exists.

### 3.5 Responsibility evidence

Evidence may contain:

- `scope_accountability`: individual actor or department/branch manager when explicitly present;
- `target_assigner`: context only;
- `top_contributors`: execution/result evidence only;
- `existing_active_work`: continuity evidence.

No actor is selected merely because they are the top or bottom contributor.

---

## 4. Decision-quality expectations

### D1 — trajectory gap with low governed activity

If a valid governed activity baseline exists and execution is materially low, the reasoning layer may identify execution coverage as a plausible driver and recommend a bounded action owned according to real sales responsibility.

### D2 — trajectory gap despite healthy activity

If activity expectations are met but outcome remains weak, the planner must not simply add more visits. It should investigate customer/product mix, conversion quality or offer execution.

### Current evidence limitation

Where activity coverage is partial, the case records that limitation. The model may investigate but cannot state a causal conclusion as fact.

If the official progress snapshot is older than the requested business date, the model may explain the historical evidence but must not form a current-state operational action from that stale measurement until official progress is refreshed.

---

## 5. Safety boundary

Sales & Targets source/case functions may:

- `SELECT` from operational Sales, Target, HR, Product, Geography, Visit/Activity and Work tables;
- write only planner-local case/snapshot state inside `ai_ops` during explicit capture.

They may not:

- call `recalculate_target_progress`;
- update targets or target progress;
- alter sales orders/items;
- alter visits/activities;
- alter HR ownership;
- create Work during case capture;
- modify source-table schema/indexes/triggers;
- infer employee performance scores.

Work creation remains downstream of AI decision validation, human review and explicit Work commit.

---

## 6. Multi-domain integration decision

The existing Credit snapshot builder and worker context are deliberately Credit-specific (`receivables`, `credit_recovery`).

Do **not** clone those orchestration functions per domain.

Implementation order:

1. implement and validate Sales target candidate/case capture independently;
2. prove business-quality output on isolated/local data;
3. generalise the existing snapshot builder/worker context **once** into a bounded multi-domain contract;
4. attach Customer, Inventory, Visits, Work and HR domains to that shared contract.

---

## 7. Runtime findings and correction

Production read-only inspection confirmed the target recalculation job is active and runs every five minutes, while `snapshot_date` and `last_calc_at` are separate concepts.

Local acceptance testing exposed a real edge case: the copied local database contained active delayed targets but its latest official `target_progress.snapshot_date` was `2026-08-10`. The first Sales kernel required an exact progress row for the requested planner date, so valid target-gap cases disappeared as `0 rows`.

The follow-up freshness contract corrects this without touching operational data:

- select the latest official progress at or before the requested business date;
- keep the case visible;
- align contribution, activity, pace, projection and severity to that same `metrics_as_of`;
- surface snapshot age/freshness explicitly;
- require official progress refresh before treating an older snapshot as current-state action evidence.

This preserves the Target Engine as the single KPI authority while preventing "no case" from being confused with "no exact snapshot for today".
