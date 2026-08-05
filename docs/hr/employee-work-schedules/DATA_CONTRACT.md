# Employee Work Schedules — Data Contract

> Design contract only. This file is not a migration and has not been applied to any Supabase project.

## 1. Design objective

Represent one simple weekly work schedule per employee, versioned by effective date, while preserving the current company schedule as the default.

The design deliberately avoids:

- break tracking;
- part-time/full-time calculation modes;
- rotating or split shifts;
- overnight shifts;
- retroactive schedule reinterpretation.

## 2. Schedule model

### 2.1 Header: `hr_employee_work_schedules`

One row represents one complete version of an employee’s weekly schedule.

Proposed columns:

| Column | Type | Rules |
|---|---|---|
| `id` | `uuid` | primary key, generated |
| `employee_id` | `uuid` | required FK to `hr_employees(id)` |
| `effective_from` | `date` | required |
| `effective_to` | `date` | nullable; inclusive end date |
| `status` | `text` | `draft`, `active`, `retired`; checked text rather than a new enum for safer additive rollout |
| `notes` | `text` | nullable |
| `created_by` | `uuid` | nullable FK to `profiles(id)` following current HR audit convention |
| `created_at` | `timestamptz` | required, default `now()` |
| `updated_by` | `uuid` | nullable FK to `profiles(id)` |
| `updated_at` | `timestamptz` | required, default `now()` |

Required constraints:

- `effective_to IS NULL OR effective_to >= effective_from`;
- no overlapping `active` date ranges for the same employee;
- an active schedule must have exactly seven valid day rows;
- an active schedule cannot be changed in place after attendance exists within its effective range; a new version must be created instead.

### 2.2 Days: `hr_employee_work_schedule_days`

Exactly seven rows per schedule version.

Proposed columns:

| Column | Type | Rules |
|---|---|---|
| `id` | `uuid` | primary key, generated |
| `schedule_id` | `uuid` | required FK; cascade delete is acceptable only while the header is `draft` |
| `day_of_week` | existing `hr_day_of_week` | required |
| `is_working_day` | `boolean` | required |
| `start_time` | `time` | required only for working days |
| `end_time` | `time` | required only for working days |
| `scheduled_minutes` | `integer` | generated or validated from start/end; positive for working days, zero for non-working days |

Required constraints:

- unique `(schedule_id, day_of_week)`;
- working day: `start_time IS NOT NULL`, `end_time IS NOT NULL`, `end_time > start_time`;
- non-working day: start/end are null and minutes are zero;
- v1 maximum scheduled duration is less than or equal to 24 hours, with same-day end only;
- no manual minutes that disagree with the time window.

### Why header + seven days?

This keeps a weekly schedule atomic. A schedule version cannot accidentally combine Monday from one effective version with Tuesday from another.

## 3. Attendance snapshot extension

Add nullable columns to `hr_attendance_days`:

| Column | Type | Meaning |
|---|---|---|
| `scheduled_start_at` | `timestamptz` | expected start for that specific attendance date |
| `scheduled_end_at` | `timestamptz` | expected end for that specific attendance date |
| `scheduled_minutes` | `integer` | expected duration for that date |
| `schedule_source` | `text` | `employee` or `company` |
| `work_schedule_id` | `uuid` | nullable FK to the employee schedule header |
| `schedule_snapshot_at` | `timestamptz` | when the expected schedule was fixed on the attendance row |

Snapshot check rules:

- `schedule_source IN ('employee','company')` when present;
- employee source requires `work_schedule_id`;
- company source requires `work_schedule_id IS NULL`;
- work-day snapshots require start/end/minutes together;
- scheduled end must be after scheduled start in v1;
- no default values are applied to historical rows.

### Snapshot authority

For an existing attendance row:

1. If a complete snapshot exists, it is authoritative.
2. If no snapshot exists and the row is being read only, preserve legacy semantics.
3. If no snapshot exists and the row is about to be changed:
   - approved/paid payroll dates: reject;
   - open period: resolve a schedule under an explicit reprocess rule and persist the snapshot in the same transaction.

The system must not silently refresh a complete snapshot because a schedule was edited later.

## 4. Central resolver

Proposed function name:

`resolve_employee_work_schedule(p_employee_id uuid, p_target_date date)`

Proposed return columns:

| Field | Type |
|---|---|
| `day_kind` | `text` |
| `is_working_day` | `boolean` |
| `scheduled_start_at` | `timestamptz` |
| `scheduled_end_at` | `timestamptz` |
| `scheduled_minutes` | `integer` |
| `schedule_source` | `text` |
| `work_schedule_id` | `uuid` |

### Resolution rules

1. Reject unknown or ineligible employee IDs.
2. Public holiday returns `public_holiday`, no working window.
3. Find one active custom schedule covering the target date.
4. Resolve the weekday row from the existing `hr_day_of_week` enum.
5. If custom day is non-working, return `weekly_off`, no window.
6. If custom day is working, construct Cairo timestamps and return the employee window.
7. If no custom schedule exists, reproduce the current legacy rules:
   - employee `weekly_off_day`, if present;
   - otherwise company `hr.weekly_off_day`;
   - company start and end settings;
   - current timezone semantics.

### Fail-safe rule

If an overlapping schedule, missing weekday row, invalid time, or malformed company setting is detected, the resolver raises a clear exception. It must not return an invented default and must not create an absence.

## 5. Snapshot helper

Proposed helper:

`ensure_attendance_schedule_snapshot(p_attendance_day_id uuid, p_allow_refresh boolean default false)`

Responsibilities:

- lock the attendance row;
- return the existing complete snapshot unchanged;
- reject refresh for approved/paid payroll periods;
- resolve and save a missing snapshot atomically;
- allow refresh only through an explicitly authorized manual reprocess path;
- never create or modify punch times.

Live attendance, manual attendance, auto-checkout, penalties, and leave settlement should not each implement separate snapshot rules.

## 6. Workday compatibility function

Keep the existing signature:

`is_employee_work_day(uuid,date) returns text`

Its implementation may delegate to the central resolver and map the result to the current values:

- `work_day`
- `weekly_off`
- `public_holiday`

Keeping the signature avoids unnecessary caller breakage.

## 7. Schedule mutation API

Direct client writes to both tables should be avoided. A transaction-safe RPC is preferred.

Proposed RPC:

`save_employee_work_schedule(p_employee_id, p_effective_from, p_days_json, p_notes)`

It should:

1. verify the caller’s explicit schedule-management permission;
2. validate all seven days;
3. verify no overlapping active range;
4. verify the activation date does not rewrite protected history;
5. retire/close the previous future schedule only when safe;
6. create the header and seven day rows in one transaction;
7. write an audit log;
8. return the saved schedule and validation summary.

A separate RPC should disable future custom scheduling without deleting history.

## 8. Activation-date safety

V1 default policy:

- the UI proposes a future effective date;
- same-day activation is allowed only when no attendance record exists for that employee/date and no automated absence/checkout mutation has run;
- backdated activation is rejected by the normal save RPC;
- historical correction remains a separate privileged workflow and is not part of this feature.

This policy prevents a schedule save from changing already-observed attendance facts.

## 9. Payroll schedule inputs

Proposed helper:

`get_employee_scheduled_period(p_employee_id uuid, p_start_date date, p_end_date date)`

Return one row per date or an aggregate containing:

- scheduled workday count;
- scheduled minutes total;
- holiday count already excluded;
- source mix for diagnostic purposes.

Payroll uses this helper only for schedule-dependent inputs.

### Compatibility requirement

For employees without custom schedules:

- working-day count must match the current single-off-day loop;
- scheduled minutes must equal `working_days × current company hours/day` under the existing default contract;
- daily salary rate, absence deduction, and overtime amount must remain equal within established database rounding.

If the current start/end window and `hr.work_hours_per_day` disagree, migration must not silently select one as authoritative. The discrepancy must be surfaced before activation.

## 10. RLS and permissions

### Read

Proposed access follows the existing HR pattern:

- employee may read their own effective schedule;
- users with HR employee or attendance read permission may read schedules needed for administration.

### Write

Schedule mutation requires a dedicated management permission or a verified existing HR management permission. It must not use broad client-side table access.

### Service-role functions

Security-definer functions must:

- set a safe `search_path`;
- perform explicit permission checks for client-invoked mutations;
- expose only the minimum execution grants;
- never trust employee IDs supplied by a normal employee for another user.

Permission names remain unresolved until the role catalog is inspected and documented.

## 11. Feature switch

A non-public company setting is proposed:

`hr.employee_work_schedules_enabled = false`

Behavior while false:

- resolver returns legacy company/employee-off-day results;
- schedule UI may be hidden or display draft-only state;
- no attendance path consumes custom schedules;
- schema and draft schedules may exist safely.

The switch is a rollout control, not a substitute for rollback. Production activation requires a separate reviewed change.

## 12. Migration split

Draft migrations should be separated to make review and rollback clearer:

1. **Schema only**
   - schedule tables;
   - attendance snapshot columns;
   - indexes, constraints, RLS;
   - feature switch default false.
2. **Resolver and snapshot helpers**
   - no caller rewrites yet.
3. **Attendance callers**
   - GPS variants;
   - manual upsert;
   - work-day compatibility.
4. **Automations and penalties**
   - absence marking;
   - auto-checkout;
   - penalty processing;
   - operational scans/notifications.
5. **Payroll integration**
   - scheduled period helper;
   - minimal `calculate_employee_payroll` changes.
6. **Verification functions**
   - parity diagnostics and preflight checks.

No migration is applied merely because its file exists on the branch.

## 13. Index plan

Minimum proposed indexes:

- schedule header: `(employee_id, effective_from DESC)`;
- active schedule lookup: partial index on employee/date-relevant columns where status is active;
- schedule days: unique `(schedule_id, day_of_week)`;
- attendance snapshot FK index on `work_schedule_id` only if query plans justify it.

No redundant index should be added without an `EXPLAIN`-based reason.

## 14. Deletion and retention

- active or historically referenced schedules are never deleted;
- draft schedules with no references may be deleted by an authorized user;
- retiring a schedule closes its range; it does not remove day rows;
- attendance FK should use `ON DELETE RESTRICT` or equivalent historical protection.

## 15. Acceptance checks for this contract

The data contract is accepted only when:

- seven-day validation is unambiguous;
- no overlap is possible under concurrent saves;
- default fallback exactly matches production behavior;
- snapshot refresh rules are explicit;
- RLS and grants are reviewed;
- payroll default parity is proven;
- feature-disabled mode is operationally identical to the current system.