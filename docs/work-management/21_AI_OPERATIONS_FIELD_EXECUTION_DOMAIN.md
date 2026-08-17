# AI Operations — Visits / Field Execution Domain

**Status:** branch implementation artifacts only — no production AI Operations migration applied  
**Branch:** `feature/work-management`  
**Domain:** `field_execution`  
**Acceptance sequence:** governed by `18_AI_OPERATIONS_BUILD_ALL_DOMAINS_ACCEPTANCE_STRATEGY.md`.

## 1. Production reality used by this domain

This increment was designed from a read-only inspection of the production Visit Plans implementation and its atomic RPCs, not from a synthetic field-sales model.

The deployed system already has a mature field execution state machine around:

- `public.visit_plans`;
- `public.visit_plan_items`;
- `public.activities` linked back to visit items;
- atomic start/complete/skip/reschedule/day-close operations;
- HR employee/direct-manager structure;
- generic Work links and Work events.

The current atomic operations establish `confirmed` and `in_progress` as operational plan states. The administrative end-of-day operation converts remaining `pending` items to `missed`; the date-reschedule operation creates a replacement item and marks the source item `rescheduled`.

Production inspection on 17 August 2026 showed two old `in_progress` visit days with 18 pending commitments between them. This observation validates that an operational backlog exists, but these counts are runtime data and are not hard-coded into the domain.

Historical state labels from older Visit Plan implementations are not treated as current operational authority.

## 2. Why the Case is plan-level

The deterministic v1 Case is:

### `overdue_visit_day`

A Case is raised when:

- `plan_date < business_date`;
- the plan is currently `confirmed` or `in_progress`;
- at least one visit item remains `pending`.

The Case entity is the exact `visit_plan`, not each pending customer.

This is deliberate. The native domain resolves and closes the daily plan atomically. Creating one AI Case and potentially one Work item for every pending customer would duplicate the same operational failure, overload the employee, and make closure harder rather than easier.

The bounded evidence can still show up to ten pending items so the reviewer understands the scope of the day.

## 3. What the Case does not claim

The engine does not infer why a visit was not executed.

A pending item may reflect several operational realities, and the correct resolution belongs to the native Visit Plan workflow. Therefore:

- no missed reason is invented;
- no item is automatically marked `missed`, `skipped`, `completed` or `rescheduled`;
- no customer-health conclusion is inferred from the visit state alone;
- exact GPS coordinates are not sent to the AI worker;
- GPS is not used as an employee-surveillance scoring mechanism.

Severity age bands are deterministic triage only, not an invented field-service SLA.

## 4. Evidence frozen per Case

The snapshot freezes:

- exact visit-plan identity and date;
- plan type/state and organizational branch;
- total/pending/completed/skipped/missed/rescheduled counts;
- overdue age and pending percentage;
- up to ten pending item identifiers with customer identity/code, sequence, planned time, priority and purpose type;
- latest non-deleted activity linked to the plan, if any;
- an existing active visit-plan-linked Work item, if any;
- execution representative identity;
- direct-manager accountability;
- active-actor checks;
- bounded governed context for the employee and branch.

Direct customer contact PII and exact location coordinates are excluded from worker facts.

## 5. Responsibility contract

Field execution responsibility is explicit rather than inferred by the model:

- **current assignee:** the employee/user who owns the Visit Plan;
- **accountable owner:** that employee's current active direct manager.

A consequential Work action is fail-closed when this chain is missing, ambiguous, inactive or changed after the snapshot.

The current-state guard also rejects a proposed Work action if the AI recommends another assignee or owner instead of the real current execution chain.

## 6. Shared global snapshot budget

Field Execution is the fifth Case domain in the canonical operational snapshot:

1. Receivables;
2. Sales;
3. Customer Health;
4. Inventory;
5. Field Execution.

All five share the same hard global Case limit through the domain-neutral round-robin allocator. Domain severity scales are never compared against each other.

The reviewed four-domain builder is preserved as a private primitive. Field Execution is appended only before any worker context hash binds to the snapshot.

If Field Execution has demand but receives zero global capacity, an immutable zero-row `partial` capture marker records `global_budget_exhausted=true`; this marker can never authorize action.

`field-execution-v1` is explicitly added to the shared bounded-partial actionability contract. A selected frozen Case may remain actionable when the only missing coverage is intentional case-limit truncation. Blocked, structurally inconsistent, source-incomplete or zero-budget evidence remains fail closed.

## 7. Current-state validation

Immediately before consequential execution, the guard re-runs the exact deterministic candidate kernel.

It rejects execution when material state changed, including:

- the plan disappeared or is no longer an overdue candidate;
- plan or employee identity changed;
- representative/direct manager changed or became unavailable;
- pending/completed/skipped/missed/rescheduled counts changed;
- the bounded pending-item set changed;
- a newer linked activity appeared;
- a new active Work item now collides with the plan;
- an escalation no longer points to active Work linked to the plan;
- newer governed employee/branch context appeared;
- snapshot evidence fails the shared actionability gate.

The native visit records remain read-only throughout validation.

## 8. Human-reviewed Work execution

The domain never autonomously changes Visit Plan state.

A reviewed `CREATE_WORK` requires:

- planner enabled;
- Shadow Mode off;
- approved human review;
- exact reviewed decision fingerprint and revision still current;
- validated decision;
- same-transaction current-state revalidation;
- real active direct manager as accountable owner;
- real active plan representative as assignee;
- explicit future due date;
- deterministic source key `ai_ops:decision:<decision_id>`.

The resulting Work is system-origin and employee-safe. It instructs the assignee to review the overdue day and use the existing Visit Plan workflow to execute, reschedule or administratively resolve each pending commitment according to its actual state and permissions.

The Work links to:

- the exact `visit_plan` as the primary operational entity;
- the exact HR `employee` as the assigned field representative.

The bridge mutates Work and AI provenance only. It does not update `visit_plans`, `visit_plan_items`, `activities`, calls or customers.

## 9. Acceptance for this increment

Before proceeding to Work Health, the current branch must pass:

- deterministic Field Execution candidate contract tests;
- immutable snapshot contract tests;
- five-domain global budget/actionability tests;
- current-state drift and responsibility tests;
- human-reviewed Work bridge tests;
- no-field-mutation and no-exact-GPS worker-fact assertions;
- repository tests, type-check, production build and Windows clean-install CI.

The expensive local database runtime acceptance remains deferred to the final integrated all-domain sweep. No production migration, merge or deployment is authorized by this document.
