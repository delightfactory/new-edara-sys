# Employee Work Schedules — Current Migration Manifest

> **Single source of truth for the current branch review.**
>
> This manifest supersedes migration/simulation lists in earlier planning documents. Only files listed here participate in the final disposable rehearsal.

## Production prohibition

- Do not apply any listed migration to production.
- Do not enable `hr.employee_work_schedules_enabled`.
- Do not create real employee schedules.
- Do not run any simulation outside a disposable database.
- Do not create a Vercel Build or Deployment from this branch automatically.

## Migration order

Apply to a disposable database in this exact order:

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
12. `20260805181600_hr_employee_work_schedules_absence_notification_grace.sql`
13. `20260805190000_hr_employee_work_schedules_m5_payroll.sql`
14. `20260805193000_hr_employee_work_schedules_future_edit_guard.sql`
15. `20260805193500_hr_employee_work_schedules_consistent_day_duration.sql`
16. `20260805193700_hr_employee_work_schedules_duration_change_month_boundary.sql`
17. `20260805193800_hr_employee_work_schedules_company_duration_boundary.sql`
18. `20260805194000_hr_employee_work_schedules_admin_context.sql`

## Stage verification order

Run the matching verification immediately after each stage and before moving forward:

- `20260805143000_hr_employee_work_schedules_m1_verify.sql`
- `20260805151500_hr_employee_work_schedules_m2_verify.sql`
- `20260805161000_hr_employee_work_schedules_m3a_verify.sql`
- `20260805161100_hr_employee_work_schedules_activation_guard_simulation.sql`
- `20260805162000_hr_employee_work_schedules_m3b_verify.sql`
- `20260805170000_hr_employee_work_schedules_m4a_verify.sql`
- `20260805173000_hr_employee_work_schedules_m4b_verify.sql`
- `20260805180000_hr_employee_work_schedules_m4c_verify.sql`
- `20260805181500_hr_employee_work_schedules_m4d_verify.sql`
- `20260805181600_hr_employee_work_schedules_absence_notification_grace_verify.sql`
- `20260805190000_hr_employee_work_schedules_m5_verify.sql`
- `20260805193000_hr_employee_work_schedules_future_edit_verify.sql`
- `20260805193500_hr_employee_work_schedules_consistent_duration_verify.sql`
- `20260805193800_hr_employee_work_schedules_company_duration_verify.sql`
- `20260805194000_hr_employee_work_schedules_admin_context_verify.sql`

`20260805161100_hr_employee_work_schedules_activation_guard_simulation.sql` is rollback-only and does not require the general simulation session flag unless the file itself states otherwise.

## Authoritative behavioral simulations

Open one disposable-database session and set:

```sql
SET SESSION edara.allow_schedule_simulation = 'disposable-only';
```

Run only:

1. `20260805200700_hr_employee_work_schedules_final_lifecycle_simulation.sql`
2. `20260805200600_hr_employee_work_schedules_company_and_transition_duration_simulation.sql`
3. `20260805201000_hr_employee_work_schedules_runtime_payroll_simulation.sql`

Each file starts a transaction and ends with `ROLLBACK`.

## Final preflights

After all simulations roll back, run:

1. `20260805200000_hr_employee_work_schedules_final_disabled_preflight.sql`
2. `20260805200100_hr_employee_work_schedules_final_duration_preflight.sql`
3. `20260805200200_hr_employee_work_schedules_final_company_duration_preflight.sql`

Then compare all business-data row counts and protected function hashes with the pre-rehearsal baseline.

## Explicitly excluded files

The following were design-stage simulations and are excluded from final evidence:

- `20260805151500_hr_employee_work_schedules_m2_simulation.sql`
- `20260805193700_hr_employee_work_schedules_duration_boundary_simulation.sql`
- `20260805200500_hr_employee_work_schedules_lifecycle_simulation.sql`

Do not run, cite, rename, or merge them into the authoritative sequence.

## Frozen V1 schedule rules

- Seven unique weekdays.
- At least one working day.
- Same-day windows only; no overnight schedule.
- No split shifts or break tracking.
- Every working day inside one schedule version has the same duration.
- Start/end times may differ while duration remains equal.
- First custom duration is compared with the company baseline.
- Any change in daily duration starts on day one of a month.
- Attendance/penalty/payroll runtime remains exact legacy behavior while the flag is false.
- Absence notification waits for the employee start plus the existing late-grace setting.
- Late-shift notifications reuse the existing 15-minute operational scan.
- One atomic alert-state key prevents duplicate absence notifications per employee/date.

## Application checks after database rehearsal

No deployment is required for these checks:

1. Confirm `EmployeeProfileLegacy.tsx` is byte-identical to the original `main` profile.
2. Run TypeScript type-check locally.
3. Run focused schedule validation tests.
4. Run the full test suite.
5. Run lint.
6. Review the complete branch diff.
7. Confirm no Vercel Deployment was created.

A Vercel Preview and any production action require separate explicit decisions.
