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
| `effective_range` | `daterange` | generated from the inclusive dates for overlap protection |
| `status` | `text` | `draft`, `active`, `retired`; checked text rather than a new enum for additive rollout |
| `notes` | `text` | nullable |
| `created_by` | `uuid` | nullable FK to `profiles(id)` following current HR audit convention |
| `created_at` | `timestamptz` | required, default `now()` |
| `updated_by` | `uuid` | nullable FK to `profiles(id)` |
| `updated_at` | `timestamptz` | required, default `now()` |

Required constraints:

- `effective_to IS NULL OR effective_to >= effective_from`;
- no overlapping `active` date ranges for the same employee, including concurrent writes;
- an active schedule must have exactly seven valid day rows;
- an active schedule cannot be changed in place after attendance exists within its effective range; a new version must be created instead.

### 2.2 Days: `hr_employee_work_schedule_days`

Exactly seven rows per schedule version.

Proposed columns:

| Column | Type | Rules |
|---|---|---|
| `id` | `uuid` | primary key, generated |
| `schedule_id` | `uuid` | required FK; draft-only deletion may cascade, historical header deletion remains restricted by attendance references |
| `day_of_week` | existing `hr_day_of_week` | required |
| `is_working_day` | `boolean` | required |
| `start_time` | `time` | required only for working days |
| `end_time` | `time` | required only for working days |
| `scheduled_minutes` | `integer` | generated from start/end; positive for working days and zero for non-working days |

Required constraints:

- unique `(schedule_id, day_of_week)`;
- working day: `start_time IS NOT NULL`, `end_time IS NOT NULL`, `end_time > start_time`;
- non-working day: start/end are null and minutes are zero;
- v1 supports same-day windows only;
- no manual minutes that can disagree with the time window.

### Why header + seven days?

This keeps a weekly schedule atomic. A schedule version cannot accidentally combine Monday from one effective version with Tuesday from another.

## 3. Attendance snapshot extension

Add nullable columns to `hr_attendance_days`:

| Column | Type | Meaning |
|---|---|---|
| `schedule_day_kind` | `text` | `work_day`, `weekly_off`, or `public_holiday` at the time the day was resolved |
| `scheduled_start_at` | `timestamptz` | expected start for that specific attendance date; null for non-working days |
| `scheduled_end_at` | `timestamptz` | expected end for that specific attendance date; null for non-working days |
| `scheduled_minutes` | `integer` | expected duration; positive for work days and zero for non-working days |
| `schedule_source` | `text` | `employee`, `company`, or `public_holiday` |
| `work_schedule_id` | `uuid` | nullable FK to the employee schedule header when source is `employee` |
| `schedule_snapshot_at` | `timestamptz` | when the expected schedule state was fixed on the attendance row |

The day kind is required because an employee can create an attendance record on a weekly off or public holiday. Without it, a historical non-working day could later be misread as an incomplete work-day snapshot.

Snapshot check rules:

- a legacy row may have all snapshot columns null;
- a complete snapshot requires `schedule_day_kind`, `schedule_source`, `scheduled_minutes`, and `schedule_snapshot_at`;
- `schedule_day_kind IN ('work_day','weekly_off','public_holiday')`;
- `schedule_source IN ('employee','company','public_holiday')`;
- employee source requires `work_schedule_id`;
- company and public-holiday sources require `work_schedule_id IS NULL`;
- public-holiday kind and source must appear together;
- work-day snapshot requires start/end, positive minutes, and end after start;
- weekly-off/public-holiday snapshot requires null start/end and zero minutes;
- no defaults or automatic backfill are applied to historical attendance rows.

### Snapshot authority

For an existing attendance row:

1. If a complete snapshot exists, it is authoritative.
2. If no snapshot exists and the row is read only, no database mutation occurs.
3. If no snapshot exists and the row is about to be changed:
   - approved/paid payroll dates: reject;
   - open period: persist one legacy-safe snapshot in the same transaction;
   - a later custom schedule is never used retroactively.

The system must not silently refresh a complete snapshot because a schedule was edited later. V1 exposes no snapshot-refresh action.

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
2. Public holiday returns `public_holiday`, source `public_holiday`, no window, zero minutes.
3. When the feature switch is enabled, find one active custom schedule covering the target date.
4. Resolve the weekday row from the existing `hr_day_of_week` enum.
5. Custom non-working day returns `weekly_off`, source `employee`, schedule ID, no window, zero minutes.
6. Custom working day returns `work_day`, source `employee`, schedule ID, Cairo timestamps, and positive minutes.
7. If the feature is disabled or no custom schedule exists, reproduce the current legacy rules:
   - employee `weekly_off_day`, if present;
   - otherwise company `hr.weekly_off_day`;
   - company start/end settings;
   - current Cairo timezone semantics;
   - source `company`.

### Fail-safe rule

If an overlapping schedule, missing weekday row, invalid time, malformed company setting, or inconsistent company hours is detected, the resolver raises a clear exception. It must not return an invented default and must not create an absence.

## 5. Snapshot helper

Proposed helper:

`ensure_attendance_schedule_snapshot(p_attendance_day_id uuid)`

Responsibilities:

- lock the attendance row;
- return an existing complete snapshot unchanged;
- reject mutation for approved/paid payroll periods;
- save a missing legacy-safe snapshot atomically for an open period;
- never refresh a complete snapshot in v1;
- never create or modify punch times.

Live attendance, manual attendance, auto-checkout, penalties, leave settlement, and open-day review should not implement separate snapshot rules.

## 6. Workday compatibility function

Keep the existing signature:

`is_employee_work_day(uuid,date) returns text`

Its implementation delegates to the central resolver and returns the existing values:

- `work_day`
- `weekly_off`
- `public_holiday`

Keeping the signature avoids caller breakage.

## 7. Schedule mutation API

Direct client writes to both tables are blocked. A transaction-safe RPC is used.

Proposed RPC:

`save_employee_work_schedule(p_employee_id, p_effective_from, p_days_json, p_notes)`

It must:

1. require `check_permission(auth.uid(), 'hr.employees.edit')`;
2. require `p_effective_from` to be later than the current Cairo date;
3. validate exactly seven distinct weekdays;
4. validate every working/non-working window;
5. take an employee-scoped lock;
6. verify no overlapping active range;
7. create the header and seven day rows atomically;
8. preserve prior versions rather than rewriting history;
9. write an audit log;
10. return the saved schedule and validation summary.

A separate RPC may retire a future schedule without deleting history.

## 8. Activation-date safety

V1 policy is fixed:

- normal activation is strictly future-dated;
- same-day activation is rejected;
- backdated activation is rejected;
- historical correction is a separate controlled workflow and not part of this feature.

This avoids races with attendance, absence, auto-checkout, and the operational cron.

## 9. Payroll schedule inputs

Proposed helper:

`get_employee_scheduled_period(p_employee_id uuid, p_start_date date, p_end_date date)`

It returns or aggregates:

- scheduled workday count;
- scheduled minutes total;
- holidays already excluded;
- source mix for diagnostics.

Payroll uses this helper only for schedule-dependent inputs.

### Compatibility requirement

For employees without custom schedules:

- working-day count must match the current single-off-day loop;
- scheduled minutes must equal `working_days × current company hours/day` under the current configuration;
- daily salary rate, absence deduction, and overtime amount must remain exactly equal under current numeric rounding.

A read-only production sample on 2026-08-05 confirmed that the 11:00–19:00 window equals the configured eight hours and that sampled old/new hourly bases differed by zero at eight decimal places.

If the company window and `hr.work_hours_per_day` diverge later, preflight must block feature activation rather than silently choosing one value.

For custom schedules, overtime hourly base uses:

`base_salary / (scheduled_minutes_in_entitlement_period / 60)`

## 10. RLS and permissions

### Read

- employee may read their own schedule where self-service is allowed;
- users with `hr.employees.read` or `hr.attendance.read` may read schedules needed for administration.

### Write

- direct client insert/update/delete is not granted;
- mutation goes through the atomic security-definer RPC;
- mutation permission is the existing `hr.employees.edit`.

### Security-definer functions

They must:

- set `search_path = public` or another explicitly reviewed safe path;
- perform explicit permission checks;
- expose only minimum execution grants;
- never trust a supplied employee ID without permission and scope validation.

## 11. Feature switch

A non-public setting is introduced:

`hr.employee_work_schedules_enabled = false`

Behavior while false:

- resolver returns legacy behavior;
- custom schedules cannot affect attendance or payroll;
- schedule data may exist for review;
- operational UI activation remains unavailable.

The switch is a rollout control, not a substitute for rollback.

## 12. Migration split

1. **Schema only**
   - `btree_gist` extension if required for the overlap constraint;
   - schedule tables;
   - attendance snapshot columns;
   - indexes, constraints, RLS;
   - feature switch false.
2. **Resolver and snapshot helpers**
   - no caller rewrites yet.
3. **Attendance callers**
   - both GPS variants;
   - manual upsert;
   - work-day compatibility.
4. **Automations, notifications, penalties, and leave settlement**
   - absence marking;
   - absence notifications;
   - auto-checkout;
   - daily open-day review;
   - penalty processing;
   - leave settlement.
5. **Payroll integration**
   - scheduled-period helper;
   - minimal `calculate_employee_payroll` changes.
6. **Verification functions/scripts**
   - parity diagnostics and preflight checks.

No migration is applied merely because its file exists on the branch.

## 13. Index plan

Minimum indexes:

- schedule header `(employee_id, effective_from DESC)`;
- exclusion constraint for active date-range overlap;
- unique schedule day `(schedule_id, day_of_week)`;
- attendance `work_schedule_id` index only because the FK/history lookup requires it.

No redundant index is added without a query-plan reason.

## 14. Deletion and retention

- active, retired, or attendance-referenced schedules are never deleted;
- an unreferenced draft may be deleted only through an authorized future RPC;
- retiring a schedule closes its lifecycle; it does not remove day rows;
- attendance FK uses `ON DELETE RESTRICT`.

## 15. Acceptance checks

The contract is accepted only when:

- seven-day validation is atomic;
- overlap is impossible under concurrent saves;
- fallback matches production behavior;
- non-working-day snapshots are unambiguous;
- snapshots cannot silently refresh;
- RLS and grants are verified;
- payroll parity is proven;
- feature-disabled mode is operationally identical to the current system.