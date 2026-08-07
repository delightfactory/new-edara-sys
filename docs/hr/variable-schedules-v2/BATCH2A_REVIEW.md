# HR Variable Schedules V2 — Batch 2A Review

## Decision

**Static design gate: PASS.**

**Runtime database gate: deferred.**

**Runtime activation gate: CLOSED by construction.**

Batch 2A adds the GPS attendance compatibility layer only. It is intentionally unreachable while `hr_variable_schedules_v2_runtime_enabled()` returns `false`.

## Scope completed

- Preserved the existing public `record_attendance_gps_v2(...)` signature.
- Renamed the captured production implementation to `record_attendance_gps_v2_legacy(...)` without changing its body.
- Added a private custom-schedule implementation for GPS check-in/check-out.
- Added a public compatibility wrapper under the original RPC name.
- Added nullable custom-schedule snapshot fields to `hr_attendance_days`.
- Added a fail-closed runtime gate that returns `false` throughout development.
- Added a read-only Batch 2A verification script.

No application service, page, hook, GPS/location policy, tracking function, company setting, leave function, penalty function, payroll function, cron job, or existing RLS policy was modified.

## Legacy parity contract

With the development runtime gate `false`, the public wrapper immediately calls `record_attendance_gps_v2_legacy(...)` before performing any V2 employee or schedule lookup.

The captured production body hash of the Legacy implementation is:

`8d8e6f188962e81933949e6472ba4541`

The Batch 2A verification script asserts this body hash after the function is renamed, so a rename cannot hide accidental body drift.

The original external EXECUTE contract on `record_attendance_gps_v2(...)` is restored on the wrapper. The new Legacy alias and custom implementation are private and are not externally executable by `anon` or `authenticated`.

## Custom timing behavior prepared

When the runtime gate is eventually opened and an effective complete custom schedule exists:

- a custom working day uses the custom start time for late calculation;
- a custom working day uses the custom end time for early/overtime calculation;
- the existing late-grace setting remains unchanged;
- GPS validation, location selection, tracking, attendance logs, lock checks, and response shape remain the captured Legacy behavior;
- a configured custom non-working weekday generates no company-time late or early classification;
- effective worked hours are still recorded from actual punch timestamps.

No off-day compensation/pay policy is invented in Batch 2A. That remains a payroll-policy concern.

## Attendance snapshot

The following nullable fields are added to `hr_attendance_days`:

- `custom_schedule_id`;
- `custom_scheduled_start`;
- `custom_scheduled_end`;
- `custom_scheduled_minutes`.

Existing attendance rows remain all-NULL in these columns. There is no backfill and no default.

For a custom working day, the schedule id/start/end/minutes are snapshotted at check-in. For a custom non-working weekday, the schedule id and zero minutes are stored while start/end remain null.

Checkout prefers an existing attendance snapshot over re-resolving timing, preserving the interpretation actually used at check-in.

## Deliberate downstream block

The captured GPS checkout path calls:

- `settle_attendance_day_against_leave(...)`;
- `reprocess_attendance_day_penalties(...)`.

Those helpers are still Legacy after Batch 2A and include schedule-duration assumptions that must be reviewed before custom attendance is reachable.

This is why the runtime gate is hard-coded `false`. Batch 2A must **not** be activated independently.

Batch 3 must close the schedule-dependent leave-settlement/penalty timing gap before the release gate can ever change runtime activation.

## Static safety observations

- Batch 2A asserts the production `record_attendance_gps_v2` definition hash before renaming it.
- Internal function names were checked for production collision before implementation.
- Snapshot column names were checked for production collision before implementation.
- The migration is transactional.
- Historical rows satisfy the new snapshot constraint because all added columns are nullable and added without defaults.
- V2 runtime is fail-closed even if custom schedule rows are later inserted manually during development.

## Verification prepared

`supabase/verification/20260807122100_hr_variable_schedules_v2_batch2a_verify.sql` checks:

1. runtime gate is false;
2. Legacy function body remains the captured production body;
3. public wrapper exists;
4. custom function exists;
5. public RPC execution grants remain available;
6. internal implementations are not direct external RPCs;
7. all four snapshot columns exist and are nullable;
8. existing attendance rows were not backfilled.

These assertions are prepared but have not yet been executed on PostgreSQL.

## Production / deployment status

- No Batch 1 or Batch 2A migration has been applied to production Supabase.
- Production database access during development remained read-only.
- No Vercel deployment was created by Batch 2A commits.
- No application build was triggered.

## Next step

Batch 2B may add the same employee/date-scoped compatibility pattern to administrative attendance correction (`upsert_attendance_and_reprocess`) while keeping the runtime gate false.

Batch 2B must remain isolated from absence, auto-checkout, penalty policy, leave policy, payroll and UI.
