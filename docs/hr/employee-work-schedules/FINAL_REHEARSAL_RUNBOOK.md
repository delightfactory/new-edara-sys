# Employee Work Schedules — Final Disposable Rehearsal Runbook

> **Authoritative execution document for the current branch.**
>
> It supersedes earlier rehearsal ordering in `IMPLEMENTATION_GATES.md` and `V1_DURATION_AND_REHEARSAL_ADDENDUM.md` where the order or simulation filename differs.
>
> Nothing in this file authorizes applying migrations to production or enabling the feature.

## Non-negotiable controls

- Target: a disposable Supabase database created from the current production schema.
- Production project remains read-only.
- Vercel automatic deployment for the feature branch remains disabled.
- No Vercel Preview is created during database rehearsal.
- `hr.employee_work_schedules_enabled` remains `false` throughout.
- `hr_employee_work_schedules_activation_ready()` remains `false` throughout.
- No real employee schedule is inserted.
- No historical attendance snapshot is backfilled.
- Every behavioral simulation requires:

```sql
SET SESSION edara.allow_schedule_simulation = 'disposable-only';
```

- Every behavioral simulation ends with `ROLLBACK`.

## A. Capture disposable target baseline

Before M1, capture and compare:

- applied migration history;
- function definitions and hashes listed in `DEPENDENCY_MAP.md`;
- table row counts for HR attendance, penalties, leave, payroll, and settings;
- current company schedule settings;
- function ACLs;
- attendance cron jobs;
- approved/paid payroll counts.

Any drift from the reviewed production baseline stops the rehearsal.

## B. Apply migrations in this exact order

1. `20260805143000_hr_employee_work_schedules_m1_schema.sql`
2. `20260805150000_hr_employee_work_schedules_m2_resolver.sql`
3. `20260805151500_hr_employee_work_schedules_m2_integrity.sql`
4. `20260805152500_hr_employee_work_schedules_m2_snapshot_hardening.sql`
5. `20260805160000_hr_employee_work_schedules_m3a_attendance_callers.sql`
6. `20260805161000_hr_employee_work_schedules_activation_guard.sql`
7. `20260805162000_hr_employee_work_schedules_m3b_legacy_gps_bridge.sql`
8. `20260805170000_hr_employee_work_schedules_m4a_absence_auto_checkout.sql`
9. `20260805173000_hr_employee_work_schedules_m4b_penalties_leave.sql`
10. `20260805180000_hr_employee_work_schedules_m4c_alerts_notifications.sql`
11. `20260805181500_hr_employee_work_schedules_m4d_late_shift_absence_dedupe.sql`
12. `20260805190000_hr_employee_work_schedules_m5_payroll.sql`
13. `20260805193000_hr_employee_work_schedules_future_edit_guard.sql`
14. `20260805193500_hr_employee_work_schedules_consistent_day_duration.sql`
15. `20260805193700_hr_employee_work_schedules_duration_change_month_boundary.sql`
16. `20260805193800_hr_employee_work_schedules_company_duration_boundary.sql`
17. `20260805194000_hr_employee_work_schedules_admin_context.sql`

Do not combine files into one large migration during rehearsal. A failure must identify the exact stage.

## C. Run stage verifications immediately after their migration stage

### C1 — Schema

- `20260805143000_hr_employee_work_schedules_m1_verify.sql`

### C2 — Resolver/integrity/snapshot

- `20260805151500_hr_employee_work_schedules_m2_verify.sql`

### C3 — Attendance callers and activation lock

Before M3B:

- `20260805161000_hr_employee_work_schedules_m3a_verify.sql`
- `20260805161100_hr_employee_work_schedules_activation_guard_simulation.sql`

After M3B:

- `20260805162000_hr_employee_work_schedules_m3b_verify.sql`

### C4 — Attendance automation

Run each before applying the next M4 sub-stage:

- `20260805170000_hr_employee_work_schedules_m4a_verify.sql`
- `20260805173000_hr_employee_work_schedules_m4b_verify.sql`
- `20260805180000_hr_employee_work_schedules_m4c_verify.sql`
- `20260805181500_hr_employee_work_schedules_m4d_verify.sql`

### C5 — Payroll

- `20260805190000_hr_employee_work_schedules_m5_verify.sql`

### C6 — Future edit, duration, company baseline, and admin context

- `20260805193000_hr_employee_work_schedules_future_edit_verify.sql`
- `20260805193500_hr_employee_work_schedules_consistent_duration_verify.sql`
- `20260805193800_hr_employee_work_schedules_company_duration_verify.sql`
- `20260805194000_hr_employee_work_schedules_admin_context_verify.sql`

The older `20260805193700_hr_employee_work_schedules_duration_boundary_simulation.sql` is not authoritative after the company-baseline guard and must not be used as release evidence.

## D. Run only these authoritative rollback simulations

Set the disposable-only session flag, then run these files one at a time. Re-set the flag if the SQL client opens a new session.

### D1 — Final lifecycle and snapshot stability

- `20260805200700_hr_employee_work_schedules_final_lifecycle_simulation.sql`

Proves:

- initial six-hour custom schedule begins on a month boundary;
- public runtime still uses company fallback while disabled;
- internal resolver reads prepared custom times;
- same-duration future correction works;
- all-off correction is rejected;
- same-duration replacement closes the previous version correctly;
- a legacy company snapshot is immutable.

### D2 — Company baseline and duration transition boundaries

- `20260805200600_hr_employee_work_schedules_company_and_transition_duration_simulation.sql`

Proves:

- company eight-hour fallback → first six-hour schedule is rejected midmonth;
- the same first six-hour schedule is accepted on day one;
- six-hour → nine-hour transition is rejected midmonth;
- six-hour → nine-hour transition is accepted on day one of the next month;
- rejected writes leave no partial lifecycle state.

### D3 — Attendance, penalties, and payroll

- `20260805201000_hr_employee_work_schedules_runtime_payroll_simulation.sql`

Proves with temporary employees:

- Ahmed-style six-hour schedule;
- nine-hour sales schedule;
- 30-minute early leave uses 360 scheduled minutes for the six-hour employee;
- overtime begins after the employee's own end time;
- weekly-off attendance creates no automatic penalty or overtime;
- six-hour payroll uses six-hour scheduled period minutes;
- nine-hour payroll uses nine-hour scheduled period minutes;
- no real employee, payroll period, or payroll run is touched after rollback.

## E. Run final installed-but-disabled preflights

Run in this order:

1. `20260805200000_hr_employee_work_schedules_final_disabled_preflight.sql`
2. `20260805200100_hr_employee_work_schedules_final_duration_preflight.sql`
3. `20260805200200_hr_employee_work_schedules_final_company_duration_preflight.sql`

All must report:

- feature false;
- readiness false;
- zero schedule rows;
- zero attendance snapshot rows;
- exact legacy clones;
- gated public dispatchers;
- no internal helper exposure;
- unchanged attendance cron jobs;
- duration consistency enforced;
- company baseline checked;
- duration changes restricted to month boundaries;
- production activation not authorized.

## F. Compare post-rehearsal state with the baseline

Because every simulation rolls back, the following must match section A exactly except for installed schema/functions/migration records:

- employee count;
- attendance row count;
- attendance-log count;
- penalty count;
- leave balances and requests;
- salary history count;
- payroll periods, runs, lines, adjustments, advances, and installments;
- notification rows and alert-state rows;
- company setting values;
- cron jobs;
- approved/paid payroll state.

Any unexpected business-data difference is a hard failure.

## G. Application checks — still no deployment

After database rehearsal passes:

1. Check that `EmployeeProfileLegacy.tsx` uses the exact original `main` profile blob.
2. Type-check the branch locally.
3. Run the focused schedule validation tests.
4. Run the full unit-test suite.
5. Run lint.
6. Review the complete diff against `main`.
7. Confirm branch commits created no Vercel Deployment.
8. Decide separately whether one aggregated local production build is necessary.

No Vercel Preview is created until a separate explicit decision.

## H. Files excluded from release evidence

The following were earlier design-stage simulations and are not authoritative in the final sequence:

- `20260805151500_hr_employee_work_schedules_m2_simulation.sql`
- `20260805193700_hr_employee_work_schedules_duration_boundary_simulation.sql`
- `20260805200500_hr_employee_work_schedules_lifecycle_simulation.sql`

They must not be run or cited as final evidence.

## I. Production remains a separate decision

Even a completely successful disposable rehearsal does not authorize:

- applying migrations to production;
- creating production employee schedules;
- enabling `hr.employee_work_schedules_enabled`;
- changing attendance cron jobs;
- recalculating attendance or payroll;
- creating a Vercel Preview or Production Deployment.

Production requires a fresh drift review, explicit maintenance window, backup/rollback evidence, one pilot employee with a future effective date, a separate readiness migration, and direct approval.
