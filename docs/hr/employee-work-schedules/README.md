# Employee Work Schedules — Safety Baseline

> Status: design and branch-only implementation.
>
> Production database changes are explicitly out of scope until the implementation, review, simulations, and rollback rehearsal are complete.

## Purpose

Add simple, employee-specific weekly work schedules without introducing a new shift engine or changing the behavior of employees who continue to use the company schedule.

The feature must support:

- Different working days and start/end times per employee.
- A 9-hour official work window for sales employees when configured.
- Individually configured customer-service schedules.
- Simple shorter schedules such as Ahmed Neamatallah's 6-hour windows.
- Existing attendance, absence, penalties, overtime, leave, holiday, auto-checkout, and payroll flows.

## Non-goals for v1

The first version will **not** add:

- A separate part-time payroll engine or employee classification.
- Break tracking or break deductions.
- Split shifts in the same day.
- Overnight shifts crossing midnight.
- Automatic rotating shifts.
- Retroactive schedule changes.
- Reinterpretation of historical attendance or closed payroll periods.

## Mandatory safety invariants

1. **No custom schedule means no behavior change.**
   An employee without an effective custom schedule must continue to use the current company settings and produce the same attendance and payroll results.

2. **Historical attendance is immutable in meaning.**
   Each attendance day must retain a snapshot of the schedule used for that day. A later schedule change must not alter old late, early-leave, overtime, absence, or payroll calculations.

3. **One central resolver.**
   All affected database functions must resolve the expected schedule through one shared function. No function may independently implement different fallback rules.

4. **Additive database design.**
   Draft migrations must add new tables, columns, functions, indexes, and policies without dropping or renaming existing production objects.

5. **Closed payroll periods remain untouched.**
   The feature must not recalculate or mutate closed payroll periods.

6. **No production execution during branch development.**
   SQL migration files may be authored and reviewed on this branch, but they must not be applied to the production Supabase project.

7. **Explicit effective dates.**
   A custom schedule becomes active only from an explicit date. Existing attendance rows are not backfilled automatically.

8. **Safe fallback.**
   If no valid custom schedule is found, the system must fall back to the existing company schedule. Invalid or incomplete custom data must fail safely rather than silently creating payroll differences.

## Proposed v1 data model — design draft

The final names and constraints remain subject to schema and RLS review.

### `hr_employee_work_schedules`

Versioned schedule header:

- `id`
- `employee_id`
- `effective_from`
- `effective_to` nullable
- `is_active`
- audit fields

A versioned header allows a complete weekly schedule to change atomically from a specific date.

### `hr_employee_work_schedule_days`

Seven weekday rows linked to one schedule version:

- `schedule_id`
- `weekday`
- `is_working_day`
- `start_time` nullable for non-working days
- `end_time` nullable for non-working days
- `scheduled_minutes`

Required constraints:

- One row per weekday per schedule.
- Working days require valid start and end times.
- End time must be later than start time in v1.
- `scheduled_minutes` must match the configured window or be generated centrally.

### Attendance-day snapshot fields

Additive fields proposed for `hr_attendance_days`:

- `scheduled_start_at`
- `scheduled_end_at`
- `scheduled_minutes`
- `schedule_source` (`employee` or `company`)
- `work_schedule_id` nullable

These fields are populated when an attendance day is first created or deliberately reprocessed under an authorized rule. They prevent later schedule changes from rewriting history.

## Central schedule resolution contract

A database resolver will accept:

- `employee_id`
- `target_date`

It will return:

- whether the date is a working day
- expected start timestamp
- expected end timestamp
- scheduled minutes
- source (`employee` or `company`)
- effective schedule id when applicable

Resolution order:

1. Effective, valid employee schedule for the date.
2. Existing company schedule behavior.

The resolver must preserve existing timezone and company-setting semantics. No new timezone behavior will be introduced without a separate review.

## Known dependency surface

The following production functions currently participate in schedule-dependent behavior and must be reviewed before any migration is approved:

- `record_attendance_gps_v2`
- `upsert_attendance_and_reprocess`
- `process_attendance_penalties`
- `is_employee_work_day`
- `mark_daily_absences`
- `run_auto_checkout`
- `calculate_employee_payroll`

Operational monitoring also runs through `run_attendance_operational_scan()` on an existing 15-minute cron schedule. Its downstream functions must be checked for assumptions about company-wide times.

Frontend integration is expected in the employee profile, backed by the existing HR service layer. Exact files and call paths are tracked in `DEPENDENCY_MAP.md`.

## Delivery gates

### Gate 0 — baseline documentation

- Dependency map completed.
- Regression matrix completed.
- Release and rollback plan completed.
- No runtime code or database change required.

### Gate 1 — branch-only draft implementation

- Additive SQL migration files authored but not applied.
- Typed service interfaces and validation authored.
- Employee schedule UI authored behind an implementation boundary.
- Unit-level pure calculation tests added where possible.

### Gate 2 — static and code review

- SQL reviewed object by object.
- Function dependency review completed.
- RLS and permission review completed.
- TypeScript build, lint, and tests pass.
- Branch diff reviewed for unrelated changes.

### Gate 3 — isolated simulation

- Apply only to a disposable or Supabase preview branch, never production.
- Seed controlled scenarios.
- Compare old and new results for employees without custom schedules.
- Exercise all scenarios in `REGRESSION_MATRIX.md`.
- Rehearse rollback/fallback.

### Gate 4 — controlled production proposal

A production migration is considered only after:

- Every blocking test passes.
- The production migration and verification queries are frozen and reviewed.
- Backup and rollback procedures are ready.
- A limited pilot employee and effective date are approved.

## Acceptance criteria

The feature is not ready for production unless all of the following are true:

- Employees without custom schedules produce identical results to the baseline.
- New schedule dates affect only dates on or after `effective_from`.
- Old attendance records remain stable after schedule edits.
- GPS and manual attendance produce equivalent schedule snapshots.
- Absence, late arrival, early leave, and overtime use the same resolved schedule.
- Leave and holiday behavior remains intact.
- Payroll uses the intended scheduled hours and does not alter closed periods.
- The operational attendance scan continues without new false alerts.
- A tested fallback path can disable custom-schedule usage without destructive rollback.
