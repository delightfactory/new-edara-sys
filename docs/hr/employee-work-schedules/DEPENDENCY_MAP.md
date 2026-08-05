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
| `hr.work_end_time` | `19:00` | GPS attendance, manual attendance, absence marking, auto-checkout, daily open-day alerts, early-leave penalty coverage |
| `hr.work_hours_per_day` | `8` | payroll overtime hourly divisor, penalty/leave day conversion |
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

## 2. Exact production dependency census

A production-schema search was run for all functions containing any of:

- `hr.work_start_time`;
- `hr.work_end_time`;
- `hr.work_hours_per_day`;
- `hr.weekly_off_day`;
- `is_employee_work_day(...)`.

The exact current result is the following eleven functions. This list replaces earlier approximate names.

### A. Direct schedule calculators — blocking

| Function | Current schedule assumption | Required v1 change | Regression risk |
|---|---|---|---|
| `record_attendance_gps_v2(...)` | Reads global start/end; calculates late, early leave, overtime | Resolve and persist the employee/date schedule when the day is created; reuse the stored snapshot at checkout | Critical: confirmed live frontend path |
| `record_attendance_gps(...)` | Legacy GPS path also reads global start/end | Preserve compatibility until external callers are ruled out; no silent divergence | Critical: legacy RPC remains callable |
| `upsert_attendance_and_reprocess(...)` | Manual correction reads global start/end and fixed thresholds | Resolve/snapshot the applicable schedule; preserve approved-payroll guard | Critical: HR corrections and payroll linkage |
| `process_attendance_penalties(...)` | Uses global hours/day and global end time for early-leave coverage | Use snapshot minutes/end time; maintain existing penalty rules and overrides | Critical: monetary deductions |
| `is_employee_work_day(...)` | Holiday, employee single off-day, then company single off-day | Delegate to central resolver while preserving current text result contract | High: broad downstream usage |
| `mark_daily_absences(date)` | Uses global work end for run timing and `is_employee_work_day` | Determine eligibility and due time per employee schedule; insert the same schedule snapshot into absence rows | Critical: false absences |
| `run_auto_checkout(date)` | Uses one global scheduled end for all open days | Use attendance-day snapshot; never reinterpret an existing open day from a newly edited schedule | Critical: automatic mutation |
| `calculate_employee_payroll(uuid,uuid)` | Counts one weekly-off pattern; uses global 8 hours in OT divisor | Count employee scheduled workdays; use employee scheduled period minutes without changing unrelated salary/adjustment logic | Critical: payroll |

### B. Operational, notification, and leave paths — blocking review

| Function | Verified dependency | Required v1 treatment |
|---|---|---|
| `scan_attendance_daily_review_alerts()` | Reads global work end to decide when an open day becomes overdue | Use each open attendance row’s stored scheduled end; legacy row fallback must remain safe |
| `notify_absent_employees()` | Calls `is_employee_work_day` | Inherits central resolver result; verify no notification on a custom off day |
| `settle_attendance_day_against_leave(uuid,boolean)` | Reads global work hours/day | Use scheduled minutes from the attendance snapshot when judging full-day attendance/leave restoration |

### C. Orchestration and schedule-independent monitoring

| Function | Verified behavior | Treatment |
|---|---|---|
| `run_attendance_operational_scan()` | Calls `scan_attendance_tracking_alerts()` and `scan_attendance_daily_review_alerts()` | No independent schedule calculation, but end-to-end cron regression is mandatory |
| `scan_attendance_tracking_alerts()` | Tracks stale/outside-zone pings and permission return gaps | No schedule source change expected; must remain behaviorally unchanged |

The active cron job is:

- job: `scan-attendance-alerts`;
- schedule: every 15 minutes;
- command: `select public.run_attendance_operational_scan();`.

### D. Mandatory repeat search before migration freeze

The exact production search must be rerun immediately before freezing migration files. A new or previously changed function blocks release until classified.

The search must also include functions that:

- write to `hr_attendance_days`;
- read `late_minutes`, `early_leave_minutes`, or `overtime_minutes`;
- call the resolver or snapshot helper;
- calculate leave day value or payroll attendance clearance.

## 3. Confirmed application call paths

### Frontend

`src/lib/services/hr.ts` is the current HR service layer.

The current check-in/check-out service calls:

`record_attendance_gps_v2`

The current repository search and service inspection found no frontend caller for the legacy `record_attendance_gps` RPC. This is evidence that v2 is the current application path, but it is not proof that no external or old client calls the legacy RPC. Therefore v1 retains compatible legacy behavior instead of dropping the function.

### Edge Functions

The repository’s current Supabase Edge Functions are limited to account and notification utilities. No attendance Edge Function caller was found. This must be rechecked at migration freeze.

## 4. Payroll dependency details

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

For employees whose daily scheduled duration varies, the general overtime divisor must be the **sum of scheduled minutes for the payroll entitlement period**, not `working_days × one global daily constant`.

Proposed v1 equivalent:

`overtime_hourly_base = base_salary / (scheduled_minutes_in_period / 60)`

Compatibility rule:

For an employee using the company default schedule, this must resolve to the same value as the existing formula within the current numeric rounding behavior.

The formula remains a design proposal until the parity simulation passes exactly.

## 5. Data dependencies and invariants

### `hr_attendance_days`

Existing uniqueness: one row per `(employee_id, shift_date)`.

New snapshot columns must be additive and nullable during rollout. No existing row is backfilled automatically.

Required invariant after activation for a new/modified day:

- work day: expected start, expected end, and positive scheduled minutes are present;
- non-working day: no late, early-leave, overtime, absence, or monetary penalty is generated from a working window;
- existing snapshot is reused unless an authorized manual reprocess explicitly refreshes it;
- approved/paid payroll dates cannot be refreshed.

### `hr_employees`

The existing `weekly_off_day` remains in place for legacy fallback. It is not dropped, renamed, or silently migrated.

### Holidays and leave

Public holidays remain higher-priority non-working dates. Approved leave and permission settlement continue to operate after schedule resolution. Custom schedules must not convert a public holiday into a normal work day in v1.

## 6. Frontend and service dependency surface

### Existing integration points

- `src/pages/hr/employees/EmployeeProfile.tsx`
  - hosts employee-specific tabs;
  - preferred location for a dedicated “Work schedule” tab;
  - current edit controls use `hr.employees.edit`.
- `src/pages/hr/employees/EmployeeForm.tsx`
  - should not be overloaded with a seven-day versioned schedule editor.
- `src/lib/services/hr.ts`
  - existing HR data-access layer;
  - schedule methods should be isolated in a clearly named section or a small HR schedule module.
- `src/lib/types/hr.ts`
  - current HR type source; schedule DTOs should follow it.
- `src/lib/validations`
  - appropriate home for Zod validation.
- `src/__tests__` and colocated `*.test.ts(x)` files
  - repository uses Vitest; pure validation/calculation tests can run without a live database.

### Permission decision

Schedule mutation will use the existing permission:

`hr.employees.edit`

Verified role coverage:

- `hr_manager` has `hr.employees.edit`;
- `super_admin` has wildcard `*`;
- branch manager, sales supervisor, sales representative, and customer service do not have it.

This matches the business sensitivity of changing attendance and payroll expectations without introducing another permission in v1.

Schedule read access may follow `hr.employees.read` / `hr.attendance.read` as appropriate.

Important existing inconsistency: the current `hr_employees` update RLS policy checks `hr.employees.create`, while the UI uses `hr.employees.edit`. New schedule tables/RPCs must not copy that mismatch; the RPC must explicitly call `check_permission(auth.uid(), 'hr.employees.edit')`.

## 7. Central resolver contract

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

## 8. Historical behavior rules

- New custom schedules are effective-dated.
- No automatic retroactive activation.
- Existing attendance rows are not mass-updated.
- A stored attendance snapshot is authoritative for that row.
- A legacy row without a snapshot is evaluated with legacy-safe rules unless an explicit authorized reprocess is requested.
- Closed/approved/paid payroll periods are immutable.
- A schedule edit must never trigger payroll recalculation by itself.

## 9. Rollout dependency order

1. Add schema objects behind a disabled feature switch.
2. Add central resolver and snapshot helpers.
3. Update both GPS RPCs and manual attendance path.
4. Update work-day, absence, notifications, daily review, and auto-checkout.
5. Update penalties and leave settlement.
6. Update payroll schedule inputs.
7. Add service methods and UI.
8. Run fallback-parity simulations.
9. Activate for one pilot employee from an approved effective date.

No later step may be activated while an earlier schedule-dependent mutation path still reads global times directly.

## 10. Remaining blocking decisions before SQL implementation

Resolved:

- live frontend GPS path: v2;
- current cron chain and frequency;
- repository Edge Function scope;
- schedule mutation permission: `hr.employees.edit`;
- exact direct function dependency census.

Still unresolved and must not be guessed:

- exact numeric rounding proof required to preserve default-schedule payroll parity;
- whether first production activation must be strictly future-day or may be same-day before any attendance row exists;
- whether manual reprocessing retains the original snapshot by default or exposes a separate explicit snapshot-refresh action;
- whether legacy GPS RPC remains callable by an external installed client; until proven otherwise it must remain compatible.

Each unresolved item remains a release blocker until recorded as resolved in the implementation review.