# Employee Work Schedules — V1 Duration and Rehearsal Addendum

> Effective for the current feature branch review.
>
> This addendum narrows and clarifies the V1 contract. Where an earlier planning or gate document conflicts with this file, this file governs until the consolidated documents are revised after disposable-database rehearsal.

## 1. Frozen V1 payroll-safe rule

A schedule version may use different start and end times on different weekdays, but every working day inside that version must have the same duration.

Valid examples:

- Ahmed Neamatallah: 15:00–21:00 on some days and 10:00–16:00 on other days; every workday is six hours.
- Sales: 09:00–18:00 on every workday; every workday is nine hours.
- Customer service: each employee may have a separate four-, six-, eight-, or nine-hour schedule, provided that employee's working-day duration is internally consistent for the effective version.

Not supported in V1:

- four hours on Saturday and eight hours on Sunday for the same employee/version;
- split shifts;
- overnight windows;
- break deductions;
- hourly-wage or part-time payroll modes.

### Why this rule exists

The current payroll model prices a full absence as one salary day, while lateness and early leave are proportional parts of that scheduled day. A fixed daily duration per employee/version keeps:

- a full absence equal to one daily salary rate;
- a 30-minute violation proportional to that employee's six-, eight-, or nine-hour day;
- the overtime hourly denominator consistent with the period's scheduled minutes;
- the existing salary-per-day model intact.

Supporting mixed daily durations in one version would require a separate hourly-entitlement payroll model. That is deliberately outside V1.

## 2. Daily-duration change boundary

Changing only start/end times while preserving the same daily minutes may begin on any future date.

Changing daily minutes, such as:

- six hours to nine hours;
- eight hours to six hours;
- part-day to full-day;

must begin on the first day of a calendar month.

This prevents one payroll period from containing two incompatible daily salary denominators under the current salary-per-day model.

The rule is enforced in two places:

1. immediate activation guard when a new schedule version becomes active;
2. deferred final-state constraint after controlled future edits.

## 3. Authoritative final rehearsal simulations

The following rollback-only simulations are authoritative after all current migrations are installed:

1. `20260805200500_hr_employee_work_schedules_lifecycle_simulation.sql`
   - future schedule creation;
   - same-duration time correction;
   - same-duration replacement and lifecycle closure;
   - resolver behavior while the public feature switch remains false;
   - immutable legacy company snapshot.

2. `20260805193700_hr_employee_work_schedules_duration_boundary_simulation.sql`
   - rejects a six-to-nine-hour change midmonth;
   - proves the rejected transaction leaves the previous schedule intact;
   - accepts the same duration change on day one of the next month.

3. `20260805201000_hr_employee_work_schedules_runtime_payroll_simulation.sql`
   - six-hour attendance and payroll;
   - nine-hour sales attendance and payroll;
   - minute-proportional early-leave deduction;
   - overtime after the employee's own scheduled end;
   - no automatic financial effect on a weekly off day.

All require the same disposable-database session guard:

```sql
SET SESSION edara.allow_schedule_simulation = 'disposable-only';
```

Every file starts a transaction and ends with `ROLLBACK`.

## 4. Superseded rehearsal file

`20260805151500_hr_employee_work_schedules_m2_simulation.sql` was written before the month-boundary rule was frozen. It remains useful as design history, but it is **not part of the executable rehearsal sequence** and must not be run after the duration-boundary migration.

No release checklist may cite that older simulation as evidence.

## 5. Correct integrated gate order

After M1–M5 and their stage-specific checks:

1. Apply `20260805193000_hr_employee_work_schedules_future_edit_guard.sql`.
2. Apply `20260805193500_hr_employee_work_schedules_consistent_day_duration.sql`.
3. Apply `20260805193700_hr_employee_work_schedules_duration_change_month_boundary.sql`.
4. Apply `20260805194000_hr_employee_work_schedules_admin_context.sql`.
5. Run the structural verifies for future edit, duration consistency, and admin context.
6. Run the three authoritative rollback-only simulations listed above.
7. Run `20260805200000_hr_employee_work_schedules_final_disabled_preflight.sql`.
8. Run `20260805200100_hr_employee_work_schedules_final_duration_preflight.sql`.
9. Confirm table counts and hashes still match the pre-rehearsal baseline.
10. Only then proceed to local TypeScript checks; no Vercel Preview is created automatically.

## 6. Activation remains blocked

Passing these simulations does not enable the feature.

The following remain mandatory:

- `hr.employee_work_schedules_enabled = false`;
- `hr_employee_work_schedules_activation_ready() = false`;
- activation trigger installed;
- no production migration application;
- no production schedule seed;
- no production attendance snapshot backfill;
- no automatic Vercel build or deployment.

A separate final readiness migration and an explicit production decision are still required.
