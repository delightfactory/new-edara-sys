# AI Operations — Sales & Targets Source Map

**Status:** implementation source map for the next AI Operations domain  
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

The following facts were verified by read-only inspection on 2026-08-17.

### 2.1 Canonical target truth

Existing operational sources:

- `public.targets`
- `public.target_progress`
- `public.target_types`
- `public.target_adjustments`

The deployed target engine is already the canonical deterministic calculator. `public.recalculate_target_progress(...)` defines target achievement and trajectory semantics and writes the official daily `target_progress` snapshot.

AI Operations **must not recalculate or replace that authority**. It consumes an already-calculated progress row for the requested business date.

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

These two types have directly verifiable sales execution evidence and are the highest-value continuation after the Receivables slice.

The following are deliberately deferred to their correct domains rather than mixed into Sales & Targets:

- `reactivation` → Customer Health / Re-engagement
- `category_spread` → Customer Health / Commercial Development
- `visits_count` / `calls_count` → Visits / Field Execution when used as primary cases
- `collection` → Receivables / Credit

### 2.3 Official sales achievement semantics

`recalculate_target_progress` confirms:

#### `sales_value`

- scope members are active `hr_employees` selected by target scope;
- order ownership uses `sales_orders.rep_id` mapped to `hr_employees.user_id`;
- only orders with status `delivered` or `completed` count;
- business date is `sales_orders.delivered_at::date`;
- ordinary value target uses `GREATEST(total_amount - returned_amount, 0)`;
- product/category-filtered value target uses eligible order items and confirmed return items;
- governorate/city/area filters are respected.

#### `product_qty`

- same target-scope membership and order-status/date boundary;
- achievement uses `GREATEST(delivered_quantity - returned_quantity, 0)`;
- product/category filters are respected.

AI contribution evidence must preserve these semantics. It must never use order creation date as the official sales date.

### 2.4 Responsibility evidence

Target scope ownership is evidence, not hard routing.

Verified current relationship model:

- `individual` target scope points to `hr_employees.id`; the employee's `user_id` is the actor candidate;
- `department` scope can use `hr_departments.manager_id` as management-accountability evidence;
- `branch` scope can use `branches.manager_id` as management-accountability evidence;
- `company` has no safe implicit actor in the target row and therefore must not manufacture an owner;
- `targets.assigned_by` is the target assigner/setter and is **context only**, not automatic accountability.

For the current Sales department target, production shows the department manager as Ahmed Abdelkader while the target was assigned by Ahmed Salama. The planner must keep these roles distinct.

### 2.5 Team contribution evidence

Per-employee contribution can be deterministically reproduced with the same target rules. A read-only parity check against the active August sales-value target matched the official `target_progress.achieved_value` exactly.

Contribution is **driver evidence**, not blame and not an automatic owner-selection rule.

### 2.6 Field-execution evidence

Available sources:

- `public.visit_plans`
- `public.visit_plan_items`
- `public.activities`
- `public.activity_types`

The live system contains explicit `visit` and `call` activity categories and operational visit plans.

However, field activity is not uniformly planned for every employee currently contributing to a department sales target. Therefore this slice may expose bounded field-execution evidence, but it **must not deterministically label a department target gap as "low activity" or "poor conversion" unless comparable governed activity expectations are available**.

This preserves acceptance scenarios D1/D2 without inventing a causal conclusion from incomplete activity coverage.

### 2.7 Opportunity / pipeline data

No trusted operational Lead / Opportunity / Pipeline table was found in the live production schema.

Therefore the planned case family "high-value opportunity not being progressed" is **not implemented in this slice**. It remains a valid future case only after a canonical opportunity source exists.

### 2.8 Existing Work collision

`public.work_links.entity_id` is UUID in the current live schema, so a target UUID can be linked safely as:

- `entity_type = 'target'`
- `entity_id = targets.id`

The Sales case kernel must surface an exact active Work collision and the planner must prefer existing Work over creating a duplicate.

---

## 3. Case contract

### 3.1 Domain and case type

```text
domain: sales
case_type: target_trajectory_gap
entity_type: target
entity_id: targets.id
case_key: sales:target_trajectory_gap:<target_uuid>
attention_class: exception
```

### 3.2 Eligibility

A target is eligible only when all are true:

1. target is active and not paused;
2. business date lies inside target period;
3. type is `sales_value` or `product_qty`;
4. a canonical `target_progress` row exists for the exact business date;
5. progress trend is `behind` or `at_risk`.

The AI kernel does **not** invoke `recalculate_target_progress`, because the planner's source capture must not mutate operational target tables.

Missing/stale official progress is a trust/integrity concern, not permission for AI to manufacture fresh numbers.

### 3.3 Materiality and severity

Initial severity policy intentionally avoids alarm inflation:

- `at_risk` → `medium`
- `behind` → `high`
- `critical` only when at least 75% of the target period has elapsed **and** the target remains behind with a materially poor projected/minimum position based on deterministic pace evidence.

The first implementation keeps the case's factual trajectory gap visible so AI can prioritise among multiple `high` cases without turning every mid-month miss into `critical`.

### 3.4 Core facts

Each case should expose:

- target identity/name/type/unit;
- target scope and period;
- target/minimum/stretch values;
- official achieved value and achievement percentage;
- expected progress percentage;
- trajectory gap in percentage points;
- remaining amount/quantity;
- elapsed and remaining days;
- required average daily pace from now;
- actual average daily pace to date;
- pace multiplier required to reach target;
- product/category/geographic filters when present;
- last canonical progress calculation timestamp;
- top deterministic employee contributions;
- bounded field execution summary where applicable;
- exact active linked Work if one exists.

### 3.5 Responsibility evidence

Evidence may contain:

- `scope_accountability`: individual actor or department/branch manager when explicitly present;
- `target_assigner`: contextual evidence only;
- `top_contributors`: execution/result evidence only;
- `existing_active_work`: continuity evidence.

No actor is selected merely because they are the top or bottom contributor.

---

## 4. Decision-quality expectations

This slice supports the parent acceptance scenarios D1 and D2 while remaining honest about evidence quality.

### D1 — trajectory gap with low governed activity

If a later/current target has a valid planned/target activity baseline and actual execution is materially low, the reasoning layer may identify execution coverage as a plausible driver and recommend a bounded action owned according to real sales responsibility.

### D2 — trajectory gap despite healthy activity

If activity expectations are met but outcome remains weak, the planner must not simply add more visits. It should investigate customer/product mix, conversion quality or offer execution and may place the review with the accountable sales owner rather than dumping additional activity on a rep.

### Current evidence limitation

Where activity coverage is partial, the case records that limitation. The model may investigate but cannot state a causal conclusion as fact.

---

## 5. Safety boundary

The Sales & Targets source/case functions are allowed to:

- `SELECT` from operational Sales, Target, HR, Product, Geography, Visit/Activity and Work tables;
- write only planner-local case/snapshot state inside `ai_ops` when a capture is explicitly invoked.

They are not allowed to:

- call `recalculate_target_progress`;
- update targets or target progress;
- alter sales orders/items;
- alter visits/activities;
- alter HR ownership;
- create Work during case capture;
- modify any source-table schema/index/trigger;
- infer employee performance scores.

Work creation remains downstream of AI decision validation + human review + explicit Work commit.

---

## 6. Multi-domain integration decision

The existing Credit snapshot builder and worker context are deliberately Credit-specific (`receivables`, `credit_recovery`).

Do **not** clone those orchestration functions per domain.

Implementation order:

1. implement and validate the Sales target candidate/case capture independently;
2. prove business-quality output on isolated/local data;
3. generalise the existing snapshot builder/worker context **once** into a bounded multi-domain contract;
4. attach future Customer, Inventory, Visits, Work and HR domains to that shared contract.

This avoids duplicated orchestration and keeps each domain responsible only for its source truth, case detection and evidence contract.

---

## 7. Current live-data sanity check

On 2026-08-16 the live target engine had current `sales_value` / `product_qty` targets materially behind expected calendar trajectory, while canonical progress rows were fresh and available.

The production reality study also verified:

- the Sales department has a real configured manager;
- target assigner and department manager are different actors and therefore must remain distinct evidence;
- team contribution can be reconciled to official target achievement;
- field-plan/activity data exists but does not provide uniform activity expectations for every contributor;
- no canonical opportunity pipeline exists.

These findings define the implementation boundary above.
