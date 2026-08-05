# Employee Work Schedules — Implementation Decisions

> Decision freeze: 2026-08-05
>
> These decisions govern the branch implementation. They do not authorize applying migrations, building, deploying, or activating the feature.

## 1. Scope

V1 provides one effective-dated weekly schedule per employee when needed.

It does not add:

- break tracking;
- a separate part-time/full-time payroll mode;
- rotating, split, or overnight shifts;
- role-based automatic schedule assignment;
- historical schedule editing;
- automatic payroll recalculation after schedule changes.

## 2. Activation date

Normal schedule creation requires:

`effective_from > current Cairo date`

Therefore activation is strictly future-dated in v1.

Reason:

- prevents a same-day race with check-in, absence, auto-checkout, and the 15-minute operational cron;
- prevents a user from changing the expected schedule after part of the day has already occurred;
- keeps the normal workflow separate from historical attendance correction.

Backdated and same-day activation are not supported by the normal RPC or UI.

## 3. Attendance snapshot immutability

A complete schedule snapshot stored on an attendance day is authoritative and immutable in v1.

Manual correction may change actual facts such as punch-in, punch-out, status, or notes, subject to existing payroll guards. It may not refresh the expected schedule window from a newer schedule version.

No “refresh schedule snapshot” button or RPC flag is exposed in v1.

Reason:

- avoids changing lateness, early leave, overtime, or penalties merely because an administrator later edits a schedule;
- preserves auditability;
- reduces the number of dangerous correction paths.

A genuine historical schedule error requires a separate controlled reconciliation procedure outside this feature.

## 4. Legacy attendance rows without a snapshot

No historical backfill is performed.

For a legacy attendance row without a snapshot:

- read-only views do not mutate it;
- a permitted mutation in an open, unapproved payroll period may persist one snapshot using legacy fallback rules for that employee/date;
- approved or paid payroll coverage rejects any mutation before snapshot creation;
- a future custom schedule must never be applied retroactively to that legacy row.

The snapshot helper must distinguish “legacy fallback snapshot” from “employee custom schedule snapshot” through `schedule_source` and audit metadata.

## 5. Company fallback parity

The production configuration inspected on 2026-08-05 has:

- company window: 11:00–19:00;
- configured work hours/day: 8;
- calculated window duration: 8 hours.

A read-only payroll parity sample compared the current overtime hourly divisor with the proposed scheduled-period-minutes divisor over recent payroll periods and active salaried employees.

Result:

- configured hours and time-window hours are equal;
- every sampled hourly-base difference was exactly zero at eight decimal places.

Implementation requirement:

- feature switch off: exact legacy behavior;
- employee without a custom schedule: exact legacy working-day count and monetary output;
- any future mismatch between company time window and `hr.work_hours_per_day` must be reported by preflight diagnostics and must block activation rather than silently choosing one value.

## 6. Custom-schedule payroll divisor

For an employee with a valid custom schedule, the overtime hourly base uses the total scheduled minutes in the entitlement period:

`base_salary / (scheduled_minutes_in_entitlement_period / 60)`

This supports:

- six-hour days;
- nine-hour sales days;
- different daily durations;
- fewer configured weekdays.

The change is limited to schedule-dependent payroll inputs. Salary history, approved adjustments, advances, commissions, taxes, insurance, carryovers, run guards, approval, payment, and accounting flows remain unchanged.

## 7. Schedule mutation permission

Schedule creation and retirement use the existing permission:

`hr.employees.edit`

Reason:

- employee schedules are core employee master data with attendance and payroll consequences;
- the current employee profile already uses this permission for sensitive employee edits;
- `hr_manager` has the permission;
- `super_admin` is covered through wildcard `*`;
- sales, customer service, and supervisors do not receive schedule mutation rights merely because they can view or approve attendance.

The security-definer mutation RPC must call:

`check_permission(auth.uid(), 'hr.employees.edit')`

The new implementation must not copy the existing unrelated RLS mismatch where an employee update policy checks `hr.employees.create`.

## 8. Read access

Schedule reads follow existing employee and attendance visibility:

- authorized HR users with employee/attendance read access may view schedules;
- an employee may view their own effective schedule where self-service policy permits;
- direct table mutation remains blocked; writes go through the reviewed atomic RPC.

Exact RLS expressions are reviewed in the schema migration and verification script.

## 9. GPS compatibility

The current frontend service calls `record_attendance_gps_v2`.

The legacy `record_attendance_gps` RPC has no current frontend caller found in the repository, but external or older installed clients cannot be conclusively excluded.

Decision:

- keep both RPC signatures;
- route both through the same resolver/snapshot rules;
- do not drop or silently weaken the legacy function in v1.

## 10. Feature switch

The global switch is:

`hr.employee_work_schedules_enabled`

Initial value: `false`.

While false:

- custom schedule rows may exist as reviewed data;
- runtime resolution reproduces legacy company/employee-off-day behavior;
- attendance and payroll cannot consume custom schedules;
- the UI does not expose active editing/activation as operational behavior.

The switch is enabled only after database simulation, application review, and explicit production approval.

## 11. Historical protection

The implementation must reject schedule-related attendance changes for dates covered by payroll runs in either state:

- `approved`;
- `paid`.

Schedule saving itself must not update attendance, penalties, payroll lines, payroll runs, journals, advances, notifications, or audit facts outside its own schedule audit record.

## 12. Public holidays and non-working days

Resolution precedence is fixed:

1. public holiday;
2. active custom employee schedule when the feature is enabled;
3. employee single-off-day legacy fallback;
4. company fallback.

A public holiday remains non-working in v1 even when the employee’s weekly pattern would normally work that weekday.

A custom non-working day cannot produce:

- absence;
- lateness;
- early-leave penalty;
- overtime expectation;
- payroll absence deduction.

## 13. Failure mode

Invalid or ambiguous schedule data is fail-closed:

- attendance mutation stops with a diagnosable error;
- absence and auto-checkout jobs skip mutation for that employee/day and surface a diagnostic result;
- payroll calculation stops before creating or replacing a payroll line;
- the system never invents a schedule or treats an invalid schedule as absence.

## 14. Concurrency and overlap

The database must prevent overlapping active schedule ranges for one employee under concurrent saves.

The preferred design is a database exclusion constraint on employee ID plus an inclusive date range. If this requires `btree_gist`, the extension is introduced explicitly in the schema migration and reviewed as part of the migration impact.

The save RPC also takes an employee-scoped transaction/advisory lock for clear failure behavior, but application locking alone is not accepted as the only integrity control.

## 15. First pilot

No employee schedule is seeded by migration.

After production migration and separate feature activation approval, the first schedule is entered through the final RPC/UI for Ahmed Neamatallah with a future effective date:

- Saturday, Monday, Tuesday: 15:00–21:00;
- Sunday, Wednesday, Thursday: 10:00–16:00;
- Friday: non-working.

The pilot is not activated merely by merging code.

## 16. Non-negotiable release checks

- exact fallback payroll parity;
- no global-time reads left in schedule-dependent callers after activation;
- no false absence on a custom off day;
- immutable attendance snapshots;
- no approved/paid payroll mutation;
- no overlapping schedule ranges;
- RLS and grants verified;
- all migration files remain unapplied until explicit authorization;
- no automatic Vercel build/deployment from the feature branch.