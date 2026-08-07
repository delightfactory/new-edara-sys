# HR Variable Schedules V2 — Batch 0 Baseline & Dependency Map

## Status

Batch 0 is analysis-only. This document records the current production contracts that V2 must preserve.

- Production database inspection: read-only.
- No V2 schema exists in production.
- No production data was changed.
- No existing HR function was changed by Batch 0.
- No build, preview, deployment, PR, or merge is authorized by this document.
- Source baseline: `main` at `5b9bb7bee350e60946a85725cc87523e757d17a1`.

## Primary compatibility invariant

For an employee/date/period with no effective V2 custom schedule, the current production path is authoritative and must remain unchanged.

V2 must not route all employees through a replacement HR engine. Schedule-aware behavior is allowed only where an effective custom employee schedule exists for the relevant date or payroll interval.

## Production timing baseline

Current company settings used by the legacy HR logic:

| Setting | Current value |
| --- | --- |
| `hr.work_start_time` | `1100` (interpreted by PostgreSQL as 11:00) |
| `hr.work_end_time` | `19:00` |
| `hr.work_hours_per_day` | `8` |
| `hr.weekly_off_day` | `friday` |
| `hr.late_grace_minutes` | `15` |
| `hr.auto_checkout_minutes` | `15` |
| `hr.absence_run_delay_minutes` | `120` |
| `hr.open_day_review_delay_minutes` | `120` |
| `hr.overtime_rate` | `1.25` |

All currently active employees inherit the company weekly-off setting because their employee-level `weekly_off_day` is null. This is a baseline observation only; V2 must continue to honor the existing employee `weekly_off_day` field whenever it is populated.

## Frozen public/runtime contracts

The following production definitions were captured during Batch 0. Their signatures and legacy behavior are release-parity baselines.

| Function | Production definition MD5 | V2 treatment |
| --- | --- | --- |
| `record_attendance_gps(...)` | `41f47aaff1eced8e368bce61cbd7a1a4` | Freeze; no V2 dependency unless a real consumer is later proven |
| `record_attendance_gps_v2(...)` | `bd70c45984e188a38cceb45eea00fa00` | Custom-only adapter required |
| `upsert_attendance_and_reprocess(...)` | `a0123e9ec343603dee9adf4ec73739b4` | Custom-only adapter required |
| `is_employee_work_day(uuid,date)` | `3e047334df57ad284bea8e9504724dd0` | Natural custom-schedule compatibility seam |
| `mark_daily_absences(date)` | `21e4cb27c5d1008da928cbf14ad56f1b` | Custom-only adapter required |
| `run_auto_checkout(date)` | `7687df6dc398cd73ed53408c2c53d1a8` | Custom-only adapter required |
| `process_attendance_penalties(uuid)` | `7ea1046753bbcfbbb47bcb35c27f986e` | Custom-only timing/duration input required |
| `reprocess_attendance_day_penalties(uuid)` | `5d1d271f18585e9d2381b9d1c12fa684` | Keep control flow; consumes penalty processor |
| `settle_attendance_day_against_leave(uuid,boolean)` | `c5724ab559a12ca470bcd0bae8ad8206` | Custom-only official-day duration required |
| `calculate_employee_payroll(uuid,uuid)` | `c294bf592059b7e86429960c3e2b3075` | Employee/period-scoped custom adapter required |
| `calculate_payroll_run(uuid)` | `f97661bab79bc9b4fe7c68a19c9e9238` | Freeze orchestration; continues calling employee payroll |
| `approve_payroll_run(uuid,uuid)` | `e32a1fcea2993bfbd1c0e3880b37cbd6` | Freeze approval/accounting; it may recalculate one employee |
| `check_payroll_attendance_clearance(date,date,uuid)` | `3732e7614a8b0a06cdf170f237d426fd` | Freeze unless V2 creates a direct unresolved-day defect |
| `get_monthly_attendance_summary(uuid,int,int)` | `be2cfc9cba5b8e8d8cc1f332b8988804` | Out of core V1; estimated report |
| `get_employee_live_statement(...)` | `ea5916a4771f084ad0a9060d8da7b925` | Out of core V1; consumes estimated summary |
| `sync_approved_leave_to_attendance(uuid)` | `3c3d2222e3d24ac1246fdff05799f9be` | Legacy leave engine; do not rebuild in V2 |
| `cleanup_approved_leave_sync(uuid)` | `2b26c6150df6ef8ae045c7874d66d316` | Legacy leave engine; freeze |
| `handle_leave_submission()` | `5a7810b0020444b79288cb06a2c341f1` | Legacy leave balance flow; freeze |
| `handle_leave_approval()` | `c889ea273497d81136400be80ddb15b0` | Legacy approval state machine; freeze |
| `run_attendance_operational_scan()` | `40baaa14f7df81f78025d14ebb0fc288` | Freeze orchestration |
| `scan_attendance_daily_review_alerts()` | `9997ff7734f0289b85c5d9a3b8330c38` | Custom-only scheduled-end gate may be required |
| `scan_attendance_tracking_alerts()` | `139e2ad118b89ff33d5052e67041e4e6` | Schedule-independent; freeze |

The existing grants/ACLs are also part of the compatibility baseline. V2 is not a security-cleanup project and must not opportunistically tighten existing function grants.

## Existing application consumers that must keep their contracts

- `src/lib/services/hr.ts` calls `record_attendance_gps_v2` through `recordAttendanceGPS`.
- `src/pages/hr/attendance/AttendanceCheckin.tsx` uses `recordAttendanceGPS`, `recordAttendanceLocationPing`, and current attendance-day queries.
- Administrative attendance correction calls `upsert_attendance_and_reprocess` through `upsertAttendanceDay`.
- Manual absence marking calls `mark_daily_absences`.
- Manual auto-checkout calls `run_auto_checkout`.
- Payroll hooks call the existing `calculate_payroll_run`; that function iterates employees and calls `calculate_employee_payroll`.
- Payroll approval may call `calculate_employee_payroll` again for employees with approved payroll adjustments before journal creation.
- `LeaveRequestForm.tsx` currently calculates `days_count` as inclusive calendar days and inserts the request through the existing leave flow.
- The employee form already supports one optional `weekly_off_day` override. V2 must not remove or silently reinterpret that existing field for legacy employees.

Public RPC signatures used by these consumers should remain unchanged in V2 unless a later batch has explicit evidence that a new endpoint is safer than modifying a current contract.

## Dependency matrix

| Flow | Legacy employee/date | Custom employee/date | Exact V2 responsibility | Explicit non-responsibility |
| --- | --- | --- | --- | --- |
| Work-day classification | Exact current `is_employee_work_day` behavior | Use custom weekday work/off state; public holiday remains authoritative | Resolve custom work/off only when schedule exists | Do not change company/employee weekly-off behavior for legacy |
| GPS check-in | Exact current `record_attendance_gps_v2` behavior | Replace only scheduled start/day context | Correct late calculation from custom start | Do not redesign GPS/location/tracking/auth |
| GPS check-out | Exact current behavior | Replace only scheduled end/day context | Correct early/overtime calculation from custom end | Do not redesign permissions or leave policy |
| Manual attendance correction | Exact current behavior | Use custom start/end when deriving timing fields | Correct schedule-dependent metrics only | Do not change payroll locks or authorization model |
| Absence marking | Exact current behavior | Treat custom off-days as non-workdays and custom workdays as workdays | Prevent false custom absence; respect custom end before same-day run | Do not rewrite absence policy |
| Auto-checkout | Exact current behavior | Use custom scheduled end for that attendance day | Prevent early/late closure caused by company end | Do not redesign tracking or alert policy |
| Late penalty | Exact current rule engine | Consume late minutes produced from custom start | No rule-policy change | Do not alter occurrence/escalation rules |
| Early-leave penalty | Exact current legacy logic | Use custom scheduled end and official custom-day duration | Correct custom denominator/window only | Do not globally fix inherited permission-overlap behavior |
| Leave settlement after actual work | Exact current behavior | Compare worked hours to custom official-day duration | Avoid treating 6h/9h custom day as company 8h | Do not rebuild leave balance/approval engine |
| Leave request creation/balance | Exact current flow | Initially remain exact current flow | No change in Batch 1–3 unless payroll correctness proves a minimal adapter mandatory | Do not change legacy `days_count` policy |
| Employee payroll | Exact current `calculate_employee_payroll` path when no custom schedule affects calculation interval | Use custom expected workdays/minutes and custom-day attendance interpretation only | Schedule-dependent inputs only | Do not alter advances, commissions, insurance, tax, adjustments, deficit carryover |
| Payroll run orchestration | Exact current `calculate_payroll_run` | Same orchestration | Employee-level payroll dispatch only | Do not create a second run engine |
| Payroll approval/accounting | Exact current | Exact current | Ensure any recalculation during approval dispatches correctly for that employee | Do not alter journal accounts, balancing, payment flow |
| Tracking-gap scan | Exact current | Exact current | None | Schedule-independent |
| Daily open-day review scan | Exact current | Custom scheduled-end cutoff only | Prevent pre-end false review alert | Do not redesign alert subsystem |
| Absent-manager notification | Exact current | A minimal custom start-time gate may be required | Prevent false notification before a later custom shift starts | Do not redesign recipients, delivery, or permission policy |
| Monthly attendance summary/live statement | Exact current | Legacy/estimated until separately reviewed | No core V1 change | Do not let reporting expand core schedule work |

## Key production-flow observations

### Attendance

`record_attendance_gps_v2` derives late/early/overtime from company start/end settings. It also owns GPS validation, tracking state, attendance logs, leave settlement, and penalty reprocessing. V2 must not duplicate or redesign those unrelated responsibilities.

A custom adapter therefore needs only a reliable custom schedule context for the employee and shift date. If no custom context exists, execution must take the legacy path.

### Existing work-day override

Production already supports `hr_employees.weekly_off_day`. `is_employee_work_day` first checks public holidays, then employee weekly off, then the company weekly off. This hierarchy remains the legacy source of truth when V2 has no effective custom schedule.

### Absence and auto-checkout

Both same-day guards currently use the company end time. For custom shifts this creates a direct correctness risk:

- a later custom shift could be processed too early;
- an earlier custom shift could be processed using an irrelevant company cutoff.

The adapter must solve that only for custom-schedule employees/days. It must not change the cutoff behavior of legacy employees.

### Payroll

Official payroll currently derives expected workdays from one weekly off day plus public holidays and uses company hours for the overtime denominator. It also contains many unrelated financial behaviors: interim/final calculations, salary history, adjustments, advances, commissions, insurance, deficit carryover, approval guards, and accounting.

V2 must not fork those financial policies. The safe boundary is schedule-dependent inputs only.

`calculate_payroll_run` and `approve_payroll_run` both depend on `calculate_employee_payroll`, so employee-scoped dispatch must remain correct both during normal calculation and during approval-time recalculation.

### Leave

The current leave form and triggers use inclusive calendar `days_count`. The current leave approval, balance, sync, and settlement flow is a pre-existing subsystem with known inherited behavior. V2 does not redefine this policy for legacy employees.

For a custom-schedule employee, the first implementation preference is to keep leave approval/balance untouched and make attendance/payroll interpretation safe for custom work/off dates. If this cannot be done without creating a financial mismatch, implementation must stop and request a separately reviewed leave-policy decision instead of silently expanding V2.

## Existing inherited issues — explicitly not V2 scope

The following were observed during prior and current analysis. They must not be opportunistically repaired for the whole company inside V2:

1. Leave approval/sync has an inherited timing/state interaction because approval is a `BEFORE UPDATE` trigger while the sync helper re-reads an approved row from storage.
2. Early-leave permission overlap logic can double-count overlapping permission windows.
3. Some frontend date defaults use browser/UTC-style ISO dates rather than an explicit Cairo date.
4. Current function EXECUTE grants are broad.
5. `get_monthly_attendance_summary` is row-based and is an estimated reporting function, not the official payroll source.
6. Existing payroll partial-period logic includes its current fallback behavior when calculated working days are zero.

These are documented so that V2 does not accidentally depend on them being fixed. A direct custom-schedule correctness blocker must be isolated and reviewed before any exception to this rule.

## Trigger baseline that V2 must account for

### `hr_attendance_days`

- `trg_hr_attendance_days_updated_at` — BEFORE UPDATE.
- `trg_notify_attendance_early_leave` — AFTER UPDATE OF `early_leave_minutes`.
- `trg_notify_attendance_late` — AFTER INSERT.

Schedule-aware attendance writes must therefore avoid transient incorrect timing values that could fire legacy notification triggers before final correction.

### `hr_leave_requests`

- `trg_leave_submission` — BEFORE INSERT.
- `trg_leave_approval` — BEFORE UPDATE.
- `trg_notify_leave_request` — AFTER INSERT / status update.

V2 will not restructure these triggers in core V1.

### `hr_payroll_runs`

Payroll lifecycle notification, number generation, and updated-at triggers remain unchanged.

## Cron / scheduled-operation baseline

Current production cron jobs relevant to HR attendance:

| Schedule | Command | V2 rule |
| --- | --- | --- |
| `*/15 * * * *` | `select public.run_attendance_operational_scan();` | Keep cron unchanged; custom-only adaptation must be inside the directly schedule-dependent scan |
| `0 14 * * *` | `select public.notify_absent_employees();` | Keep cron unchanged; if needed add only a custom-shift timing guard |

`mark_daily_absences` and `run_auto_checkout` are currently exposed as manual administrative operations rather than these two cron jobs. V2 must preserve that operational model.

## RLS baseline

Existing HR RLS concepts to preserve when Batch 1 adds schedule tables:

- employee data: self-read or appropriate HR permission;
- attendance: self-read or attendance-read permission;
- leave: employee/supervisor/HR-based access;
- payroll lines: self-read or payroll-read permission.

Batch 1 should add schedule-specific RLS only. It must not rewrite existing HR RLS policies.

## Proposed V2 compatibility seams for later batches

These are design targets, not implemented code:

1. `has_effective_custom_schedule(employee_id, date)` or equivalent resolver check.
2. A custom schedule resolver that returns work/off status plus start/end/minutes only when a custom version is effective.
3. Minimal attendance snapshot fields written only when a custom schedule actually governed the attendance day.
4. Employee/date dispatch at current public attendance/work-day entry points.
5. Employee/period dispatch at payroll calculation.

No company schedule history, generic settings rewrite, historical backfill, or company-wide replacement engine is justified by Batch 0 evidence.

## Batch 1 design gate

Batch 1 may begin only if it remains additive and satisfies all of the following:

- creates only employee custom-schedule storage, lifecycle validation, RLS, resolver, and optional custom-only snapshot columns;
- does not alter current attendance/payroll/leave callers;
- does not seed or backfill any employee schedule;
- does not modify existing attendance rows;
- does not modify existing payroll rows;
- does not change generic company settings;
- does not change any current production function result;
- provides a deterministic way to prove `no custom schedule => no runtime behavior change` before Batch 2.

If Batch 1 requires more than this, implementation stops for architecture review.

## Batch 0 conclusion

The production dependency map does **not** justify rebuilding HR.

The required custom-schedule integration surface is limited to schedule-dependent decisions in attendance, work-day classification, absence/auto-checkout, penalty/leave-day duration, and employee payroll. Tracking, generic settings, leave policy, payroll orchestration, accounting, advances, commissions, insurance, tax, and historical HR data can remain existing behavior.

Batch 0 therefore supports proceeding to a small additive Batch 1, but it does not authorize Batch 1 implementation, production migration, feature activation, or deployment.