# Employee Work Schedules — Dependency Map

> Baseline date: 2026-08-05
>
> Source of truth: read-only inspection of the current production schema and function definitions, matched against the feature branch structure.
>
> No SQL in this document has been applied to any database.

## 1. Current behavior contract

The production system currently has one company-wide time window and a limited per-employee weekly-off override.

### Company settings currently used

| Setting | Current value | Current consumers |
|---|---:|---|
| `hr.work_start_time` | `1100` | GPS attendance, manual attendance |
| `hr.work_end_time` | `19:00` | GPS attendance, manual attendance, absence marking, auto-checkout, early-leave penalty coverage |
| `hr.work_hours_per_day` | `8` | payroll overtime hourly divisor, penalty day conversion |
| `hr.weekly_off_day` | `friday` | work-day resolution and payroll working-day count |
| `hr.late_grace_minutes` | `15` | attendance lateness |
| `hr.auto_checkout_minutes` | `15` | automatic checkout timing |
| `hr.absence_run_delay_minutes` | `120` | daily absence run timing |

### Existing employee-level override

`hr_employees.weekly_off_day` can override only the single company weekly-off day. It cannot represent:

- different start/end times by weekday;
- more than one non-working day;
- a six-hour or nine-hour day;
- different schedules across effective date ranges.

### Existing attendance record

`hr_attendance_days` stores actual punches and calculated results, including:

- `punch_in_time`, `punch_out_time`;
- `late_minutes`, `early_leave_minutes`, `overtime_minutes`;
- `effective_hours`, `day_value`;
- status, review, tracking, leave, and lock fields.

It does **not** currently store the expected start/end window used to calculate those results. This is the principal historical-stability gap that the feature must close.

## 2. Database function dependency surface

### A. Direct schedule calculators — blocking

These functions directly read global start/end/hours settings or independently count workdays. They must be changed to consume one central resolver and, where applicable, an attendance-day snapshot.

| Function | Current schedule assumption | Required v1 change | Regression risk |
|---|---|---|---|
| `record_attendance_gps_v2(...)` | Reads global start/end; calculates late, early leave, overtime | Resolve and persist the employee/date schedule when the day is created; reuse the stored snapshot at checkout | Critical: live attendance path |
| `record_attendance_gps(...)` | Legacy GPS path also reads global start/end | Keep behavior equivalent to v2 or formally prove it is unused before removal; no silent divergence | Critical: legacy callers may remain |
| `upsert_attendance_and_reprocess(...)` | Manual correction reads global start/end and fixed thresholds | Resolve/snapshot the applicable schedule; preserve approved-payroll guard | Critical: HR corrections and payroll linkage |
| `process_attendance_penalties(...)` | Uses global hours/day and global end time for early-leave coverage | Use snapshot minutes/end time; maintain existing penalty rules and overrides | Critical: monetary deductions |
| `is_employee_work_day(...)` | Holiday, employee single off-day, then company single off-day | Delegate to central resolver while preserving current text result contract | High: broad downstream usage |
| `mark_daily_absences(date)` | Uses global work end for run timing and `is_employee_work_day` | Determine run eligibility per employee schedule; insert the same schedule snapshot into absence rows | Critical: false absences |
| `run_auto_checkout(date)` | Uses one global scheduled end for all open days | Use the attendance-day snapshot; never reinterpret an existing open day from a newly edited schedule | Critical: automatic mutation |
| `calculate_employee_payroll(uuid,uuid)` | Counts one weekly-off pattern; uses global 8 hours in OT divisor | Count employee scheduled workdays; use employee scheduled minutes for the overtime divisor without changing unrelated salary/adjustment logic | Critical: payroll |

### B. Operational and notification paths — blocking review

These functions may not calculate the whole schedule themselves, but their behavior depends on work-day or attendance timing assumptions.

| Function | Dependency | Required review |
|---|---|---|
| `run_attendance_operational_scan()` | Orchestrates attendance scans on the existing cron | Confirm downstream calls use the central resolver/snapshots and do not emit false alerts |
| `scan_daily_attendance_review(date)` | Reviews daily anomalies | Verify any expected-time comparisons use snapshots rather than global settings |
| `notify_absent_employee_on_work_day(uuid,date)` | Decides whether absence notification is valid | Must use the same work-day result as absence marking |
| `settle_leave_request_on_payroll(uuid)` | Connects attendance/leave effects to payroll | Verify workday and day-value assumptions remain correct under custom schedules |

### C. Adjacent functions — mandatory search before migration freeze

Before the migration is considered complete, run a production-schema search for every function whose definition contains any of:

- `hr.work_start_time`
- `hr.work_end_time`
- `hr.work_hours_per_day`
- `hr.weekly_off_day`
- `is_employee_work_day`
- writes to `hr_attendance_days`
- reads of `late_minutes`, `early_leave_minutes`, or `overtime_minutes`

The result must be compared with this file. A new or previously missed function blocks release until classified.

## 3. Payroll dependency details

The current payroll function performs several independent calculations that must not be conflated.

### Current working-day logic

- Selects one off-day name from `hr_employees.weekly_off_day`, falling back to `hr.weekly_off_day`.
- Counts all other calendar days in the period.
- Removes public holidays.
- Uses the resulting count as `v_working_days`.
- Sets `v_daily_rate = gross_salary / v_working_days`.

### Current overtime logic

- Sums `overtime_minutes` from attendance records.
- Calculates the hourly base using:

  `base_salary / (v_working_days * hr.work_hours_per_day)`

- Applies the existing overtime rate setting.

### Required change boundary

The feature must replace only the schedule-dependent inputs:

- period working-day count;
- partial-period working-day count;
- employee scheduled minutes/hours used for the overtime base.

It must not rewrite or broaden:

- salary-history selection;
- approved-adjustment linkage;
- advances;
- commissions;
- tax or insurance switches;
- payroll run status guards;
- attendance-clearance guards;
- deficit carryovers;
- approved/paid payroll immutability.

### Formula decision to freeze before implementation

For employees whose daily scheduled duration varies, the safest general overtime divisor is the **sum of scheduled minutes for the payroll entitlement period**, not `working_days × one daily constant`.

Proposed v1 equivalent:

`overtime_hourly_base = base_salary / (scheduled_minutes_in_period / 60)`

Compatibility rule:

For an employee using the company default schedule, this must resolve to the same value as the existing formula within the current numeric rounding behavior.

This formula remains a design proposal until simulation proves exact fallback parity.

## 4. Data dependencies and invariants

### `hr_attendance_days`

Existing uniqueness: one row per `(employee_id, shift_date)`.

New snapshot columns must be additive and nullable during rollout. No existing row is backfilled automatically.

Required invariant after activation for a new/modified day:

- work day: expected start, expected end, and positive scheduled minutes are present;
- non-working day: no late, early-leave, or overtime calculation is generated from a working window;
- existing snapshot is reused unless an authorized manual reprocess explicitly refreshes it;
- approved/paid payroll dates cannot be refreshed.

### `hr_employees`

The existing `weekly_off_day` remains in place for legacy fallback. It is not dropped, renamed, or silently migrated.

### Holidays and leave

Public holidays remain higher-priority non-working dates. Approved leave and permission settlement continue to operate after schedule resolution. Custom schedules must not convert a public holiday into a normal work day in v1.

## 5. Frontend and service dependency surface

### Existing integration points

- `src/pages/hr/employees/EmployeeProfile.tsx`
  - already hosts employee-specific tabs, including attendance;
  - preferred location for a dedicated “Work schedule” tab or section.
- `src/pages/hr/employees/EmployeeForm.tsx`
  - should not be overloaded with a seven-day versioned schedule editor unless review proves it remains clear and safe.
- `src/lib/services/hr.ts`
  - existing HR data-access layer;
  - schedule read/write methods should be isolated in a clearly named section or a new small HR schedule module, consistent with repository conventions.
- `src/lib/types`
  - typed schedule DTOs and resolver result types belong here if existing HR types are centralized there.
- `src/lib/validations`
  - Zod validation for complete weekly schedules and effective dates.
- `src/__tests__` and colocated `*.test.ts(x)` files
  - repository already uses Vitest; pure validation/calculation tests should be added without requiring a live database.

### UI permission boundary

Schedule visibility may follow employee/attendance read permissions, but schedule mutation must use an explicit HR management permission. No new RLS policy will reuse a broad payroll permission merely because payroll consumes the data.

The exact permission key is not frozen until the existing permission catalog and role assignments are reviewed.

## 6. Central resolver contract

All database paths must call one resolver with:

- employee ID;
- target date.

It must return at least:

- `day_kind`: `work_day`, `weekly_off`, or `public_holiday`;
- `scheduled_start_at`;
- `scheduled_end_at`;
- `scheduled_minutes`;
- `schedule_source`: `employee` or `company`;
- `work_schedule_id`, nullable for company fallback.

Resolution precedence:

1. Public holiday.
2. Effective and valid custom employee schedule.
3. Current employee `weekly_off_day` plus company times.
4. Current company weekly-off day plus company times.

A resolver error or incomplete custom schedule must not silently treat the employee as absent. The mutation path must stop with a diagnosable error, while read-only previews may expose a validation warning.

## 7. Historical behavior rules

- New custom schedules are effective-dated.
- No automatic retroactive activation.
- Existing attendance rows are not mass-updated.
- A stored attendance snapshot is authoritative for that row.
- A legacy row without a snapshot is evaluated with the legacy rules that applied before activation, unless an explicit and authorized reprocess is requested.
- Closed/approved/paid payroll periods are immutable.
- A schedule edit must never trigger payroll recalculation by itself.

## 8. Rollout dependency order

1. Add schema objects and resolver behind a disabled feature switch.
2. Add snapshot-aware helper functions.
3. Update attendance write paths.
4. Update absence and auto-checkout jobs.
5. Update penalties.
6. Update payroll calculations.
7. Add service methods and UI.
8. Run fallback-parity simulations.
9. Activate for one pilot employee from a future effective date.

No later step may be activated while an earlier schedule-dependent mutation path still reads global times directly.

## 9. Blocking unknowns before SQL implementation

The following must be resolved from code/schema inspection, not guessed:

- exact permission key and role coverage for schedule mutation;
- whether both GPS RPC variants still have live callers;
- exact cron call chain under `run_attendance_operational_scan()`;
- whether any Edge Function calls legacy RPC signatures;
- rounding precision required to preserve default-schedule payroll parity;
- whether the first production activation date must be strictly future-day or may be same-day before any attendance row exists;
- whether manual reprocessing should retain the original snapshot by default or require an explicit “use current schedule” action.

Each item remains a release blocker until recorded as resolved in the implementation review.