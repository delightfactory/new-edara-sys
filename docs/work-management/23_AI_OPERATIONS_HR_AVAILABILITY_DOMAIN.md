# AI Operations — HR / Availability Domain

**Status:** Design-time implementation on `feature/work-management`  
**Capture contract:** `hr-availability-v1`  
**Production mutation:** none

## Purpose

This domain protects operational continuity when a real HR availability state conflicts with already allocated Work. It is **not** an employee scoring or attendance-discipline engine. HR remains authoritative for employment, schedules, approved leave and attendance records; Work remains authoritative for task ownership, assignment and execution state.

The domain follows the shared AI Operations chain:

`deterministic candidate -> immutable snapshot -> shared worker -> one decision -> current-state validation -> human review -> reviewed Coverage Work`

No HR row and no source Work item is changed automatically.

## Authoritative sources

The implementation reuses existing production contracts:

- `public.hr_employees` for employee/user/branch/department/direct-manager placement and employment state.
- `public.get_employee_work_schedule(employee_id,date)` as the authoritative schedule resolver, including employee schedule overrides, company defaults, weekly off days and public holidays with Cairo semantics.
- `public.hr_leave_requests` with **`status = approved` only** for leave availability.
- `public.hr_attendance_days` only when it contains an explicit unavailable status.
- `public.work_items` for active allocated Work.
- `private.work_actor_is_active` for Work actor validity.
- `ai_ops.operational_context` for bounded governed employee/manager/branch/department context.

Missing attendance rows or missing punches are **never** interpreted as absence.

## Deterministic Case families

One dominant Case is emitted for a source Work / affected employee / relevant execution date:

1. `approved_leave_allocation_conflict` — an approved leave covers the Work due/follow-up date.
2. `employee_status_unavailable` — the employee has an explicit `on_leave` employment state affecting the allocation.
3. `explicit_attendance_unavailable` — the current relevant day has an explicit unavailable attendance status (`on_leave`, authorized/unauthorized absence, weekly off, or public holiday).
4. `nonworking_schedule_allocation_conflict` — the authoritative schedule marks the relevant due/follow-up day as non-working.

The planning horizon is 14 days. Already overdue or follow-up-due Work is evaluated against the current Cairo business date.

## Capacity semantics

The planner specification allows capacity as a planning constraint, never as a performance judgement. The current data model does not contain a trusted effort estimate per Work item, so this domain does **not** invent a tasks-per-day capacity threshold. It freezes official `scheduled_minutes` and availability windows as context for feasibility/routing while avoiding a false numerical workload score.

## Responsibility

Short-term coverage control is deterministic:

- if the source Work has a different active accountable owner, that owner controls coverage;
- otherwise the affected employee's active direct manager controls coverage;
- the affected unavailable employee is never automatically selected as coverage owner;
- if neither route is available, responsibility is ambiguous and consequential action fails closed.

This implements cause/control-before-org-chart while still using the direct manager where the manager genuinely controls short-term allocation.

## Snapshot and global budget

`ai_ops.refresh_hr_availability_cases` freezes:

- exact `snapshot.data_as_of` evidence;
- `hr-availability-v1` capture marker;
- source Work state/version/due/next-action data;
- schedule/approved-leave/explicit-attendance evidence;
- responsibility evidence;
- at most five governed context rows per Case.

The canonical builder becomes seven-domain and continues to use the shared deterministic round-robin allocator across:

`receivables, sales, customer_health, inventory, field_execution, work_health, hr_availability`

A zero-capacity HR marker with real demand is `partial` and carries `global_budget_exhausted=true`; it is never actionable.

Bounded partial actionability is explicitly extended only to trusted `hr-availability-v1` captures where the exact selected frozen Case and domain row/byte accounting are intact, the parent snapshot is `ready`, source/business-date bindings match and the truncation metadata is coherent.

## Current-state validation

Immediately before consequential action the guard re-reads:

- source Work existence, state version, status, due and next-action timing;
- affected employee existence;
- current schedule result;
- approved leave state;
- explicit attendance unavailable state;
- current coverage owner route and actor availability;
- newer governed context;
- active equivalent HR Availability recovery Work;
- active Work Health recovery Work linked to the same source Work.

Any meaningful drift blocks commit. This also prevents HR Availability and Work Health from creating duplicate recovery tasks for the same source Work.

## Human-reviewed Work bridge

Only an approved, validated `CREATE_WORK` decision may create Coverage Work. The bridge:

- serializes commits by source Work using a source-level advisory lock;
- revalidates current state in the same transaction immediately before the Work write;
- uses deterministic source key `ai_ops:decision:<decision_id>`;
- creates a separate standard Work item for the coverage owner;
- links the new Work to both the source Work and affected employee;
- exposes only employee-safe execution text;
- does not copy leave reasons, personal contact data or management-only rationale;
- does not mutate attendance, leave, employee, source Work ownership/due/next-action, or any other HR record.

The coverage owner must use normal Work/HR workflows for any actual reassignment, due-date governance, leave action or operational update.

## Deferred acceptance

Per the approved build-all strategy, this domain receives static/security/contract gates and repository CI now. Full clean-PostgreSQL migration/runtime E2E remains intentionally deferred until all planned domains and cross-domain orchestration are present. No production migration is applied before that acceptance and explicit approval.
