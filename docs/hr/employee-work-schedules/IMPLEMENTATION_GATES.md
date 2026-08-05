# Employee Work Schedules — Implementation Gates

> This is the authoritative execution order for disposable rehearsal and later production rollout.
>
> Creating files on the Git branch does **not** authorize applying them to any Supabase database.

## Global rules

1. Production remains read-only until a separate explicit approval.
2. Migrations are applied first to a disposable database created from the current production schema.
3. No employee schedule is seeded during schema/runtime installation.
4. `hr.employee_work_schedules_enabled` remains `false` throughout every gate below.
5. `hr_employee_work_schedules_activation_ready()` remains `false` until a separately reviewed final release gate.
6. No migration changes an existing cron schedule.
7. No migration backfills historical attendance snapshots.
8. A failure at any gate stops the sequence. Later files are not applied to compensate for an earlier failure.

## Gate 0 — Baseline capture

Before applying M1, capture from the target database:

- migration history;
- all schedule-sensitive function definitions and MD5 hashes;
- attendance/payroll table counts;
- payroll run states;
- attendance cron jobs;
- relevant function ACLs;
- current company schedule settings;
- count of approved/paid payroll periods.

Compare them with the hashes documented in `DEPENDENCY_MAP.md` and the guarded migrations. Any drift blocks rehearsal until the branch is rebased and reviewed.

## Gate 1 — Additive schema

Apply:

1. `20260805143000_hr_employee_work_schedules_m1_schema.sql`

Immediately run:

- `20260805143000_hr_employee_work_schedules_m1_verify.sql`

Expected:

- two empty schedule tables;
- seven nullable attendance snapshot columns;
- feature switch exists and is false;
- no attendance/payroll runtime function changed;
- no employee or attendance row changed.

## Gate 2 — Resolver, integrity, and snapshot rules

Apply in order:

1. `20260805150000_hr_employee_work_schedules_m2_resolver.sql`
2. `20260805151500_hr_employee_work_schedules_m2_integrity.sql`
3. `20260805152500_hr_employee_work_schedules_m2_snapshot_hardening.sql`

Immediately run:

- `20260805151500_hr_employee_work_schedules_m2_verify.sql`

Do **not** run the M2 transactional simulation yet. Its current version intentionally exercises the later future-edit RPC and is part of the integrated disposable rehearsal after Gate 7.

Expected:

- central resolver installed;
- public resolver still returns company fallback while the switch is false;
- no schedule rows;
- no attendance snapshots;
- all current runtime functions remain byte-identical.

## Gate 3 — Attendance callers and activation lock

Apply in order:

1. `20260805160000_hr_employee_work_schedules_m3a_attendance_callers.sql`
2. `20260805161000_hr_employee_work_schedules_activation_guard.sql`
3. `20260805162000_hr_employee_work_schedules_m3b_legacy_gps_bridge.sql`

Run after M3A + activation guard, before M3B:

- `20260805161000_hr_employee_work_schedules_m3a_verify.sql`
- `20260805161100_hr_employee_work_schedules_activation_guard_simulation.sql`

Then apply M3B and run:

- `20260805162000_hr_employee_work_schedules_m3b_verify.sql`

Expected:

- disabled public callers delegate to exact cloned production implementations;
- enabled paths consume resolver/snapshot data;
- old GPS signature remains available;
- activation attempt is rejected by the database trigger;
- no attendance row changes.

## Gate 4 — Attendance automation and financial effects

Apply and verify each sub-gate before the next one.

### Gate 4A — Absence and auto-checkout

Apply:

- `20260805170000_hr_employee_work_schedules_m4a_absence_auto_checkout.sql`

Run:

- `20260805170000_hr_employee_work_schedules_m4a_verify.sql`

### Gate 4B — Penalties and leave settlement

Apply:

- `20260805173000_hr_employee_work_schedules_m4b_penalties_leave.sql`

Run:

- `20260805173000_hr_employee_work_schedules_m4b_verify.sql`

### Gate 4C — Alerts and notifications

Apply:

- `20260805180000_hr_employee_work_schedules_m4c_alerts_notifications.sql`

Run **before M4D**:

- `20260805180000_hr_employee_work_schedules_m4c_verify.sql`

### Gate 4D — Late shifts and notification deduplication

Apply:

- `20260805181500_hr_employee_work_schedules_m4d_late_shift_absence_dedupe.sql`

Run:

- `20260805181500_hr_employee_work_schedules_m4d_verify.sql`

Expected:

- company-wide end time is absent from enabled automation/penalty/review paths;
- non-working attendance creates no automatic penalty or overtime;
- missing custom snapshots fail closed;
- late-starting shifts are covered by the existing 15-minute operational scan;
- one atomic absence-alert claim exists per employee/date;
- no cron schedule is created or changed.

## Gate 5 — Payroll

Apply:

1. `20260805190000_hr_employee_work_schedules_m5_payroll.sql`

Run:

- `20260805190000_hr_employee_work_schedules_m5_verify.sql`

Expected:

- disabled payroll is the exact production implementation;
- default schedule day/minute parity passes across the sampled periods;
- enabled payroll replaces only workday/minute inputs and overtime denominator;
- advances, commissions, adjustments, taxes, insurance, deficit carryovers, attendance clearance, run calculation, and approval functions remain intact;
- no payroll run or line is recalculated by migration.

## Gate 6 — Controlled future correction and admin read context

Apply in order:

1. `20260805193000_hr_employee_work_schedules_future_edit_guard.sql`
2. `20260805194000_hr_employee_work_schedules_admin_context.sql`

Run:

- `20260805193000_hr_employee_work_schedules_future_edit_verify.sql`
- `20260805194000_hr_employee_work_schedules_admin_context_verify.sql`

Expected:

- only an active, unstarted, unreferenced schedule may be corrected;
- effective date cannot be changed by the correction RPC;
- all-off schedules are rejected;
- company settings RLS is not broadened;
- UI receives only the four schedule defaults and feature state.

## Gate 7 — Integrated rollback-only simulation

Set the disposable-only guard in the same database session:

```sql
SET SESSION edara.allow_schedule_simulation = 'disposable-only';
```

Run:

- `20260805151500_hr_employee_work_schedules_m2_simulation.sql`

The file itself starts a transaction and ends with `ROLLBACK`.

It verifies:

- mixed six-hour schedule for Ahmed Neamatallah's pattern;
- company fallback while the rollout flag is false;
- internal custom resolver output;
- Friday off;
- controlled future correction;
- rejection of an all-off schedule;
- later nine-hour sales replacement;
- correct retirement/end-date lifecycle;
- immutable legacy company snapshot;
- feature switch remains false.

After execution, assert that schedule and test attendance row counts are unchanged from Gate 0.

## Gate 8 — Final installed-but-disabled preflight

Run:

- `20260805200000_hr_employee_work_schedules_final_disabled_preflight.sql`

This verification is designed for the final state after all migrations above. It does not replace the stage-specific checks.

Required result:

- all required functions and triggers exist;
- feature flag false;
- activation readiness false;
- activation trigger installed;
- no internal helpers exposed;
- exact legacy clones preserved;
- no schedule/snapshot seed data;
- unchanged cron jobs;
- frontend/database RPC contract present.

## Gate 9 — Application checks without deployment

Before creating any Vercel preview:

1. Type-check locally.
2. Run unit tests, including `hrWorkSchedules.test.ts`.
3. Run lint.
4. Run a local production build only after explicit agreement that local build is allowed.
5. Review the branch diff against `main`.
6. Confirm `EmployeeProfileLegacy.tsx` has the same blob as the original `main` employee profile.
7. Confirm no unexpected file outside the feature scope changed.

These checks must not create a Vercel deployment.

## Gate 10 — One explicit preview decision

Only after Gates 0–9 pass:

- decide explicitly whether to create one aggregated Vercel Preview;
- do not re-enable automatic branch deployment;
- do not connect the preview to production writes;
- test desktop/mobile RTL, employee profile navigation, schedule editor validation, permission boundaries, and disabled-state copy.

## Gate 11 — Production rollout decision

Production remains out of scope until a separate reviewed plan covers:

- fresh production drift capture;
- exact migration transaction order;
- lock/runtime estimates;
- operational window;
- backup/rollback evidence;
- pilot employee and future effective date;
- final activation-readiness migration;
- explicit setting enablement;
- live monitoring and stop conditions.

The migrations in this branch do not, by themselves, authorize or perform production activation.
