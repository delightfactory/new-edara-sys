# HR Variable Schedules V2 — Batch 2B Review

## Decision

**Static design gate: PASS.**

**Runtime database gate: deferred.**

**Runtime activation gate: CLOSED.**

Batch 2B adds only the administrative attendance correction compatibility layer. The shared V2 runtime gate remains hard-coded `false`, so the new custom path is not reachable during development.

## Scope completed

- Preserved the existing public `upsert_attendance_and_reprocess(...)` signature.
- Renamed the captured production implementation to a private Legacy alias without changing its body.
- Added a private custom-schedule implementation for administrative correction.
- Added a public compatibility wrapper under the original RPC name.
- Added read-only structural verification for Batch 2B.

No application service, page, hook, absence function, auto-checkout function, penalty rule, leave policy, payroll function, cron, accounting flow, or generic setting was modified.

## Legacy parity contract

The captured production body hash of `upsert_attendance_and_reprocess` is:

`a371dedb6b7b1aad184ea976f7aa2b59`

The later disposable-database verification asserts that exact body after the function is renamed.

While `hr_variable_schedules_v2_runtime_enabled()` returns `false`, the public wrapper immediately calls the Legacy implementation before any schedule or attendance-snapshot lookup.

The public RPC keeps its captured execute contract. The Legacy and custom helper functions are private implementation details and are not directly executable by `anon` or `authenticated`.

## Custom-only timing changes prepared

When runtime is eventually opened for a custom employee/date, the administrative correction path changes only schedule-dependent timing inputs:

- late calculation uses custom scheduled start;
- early/overtime calculation uses custom scheduled end;
- the existing late-grace setting remains unchanged;
- the existing administrative overtime threshold remains 30 minutes;
- the existing administrative early-leave tolerance remains 5 minutes;
- actual effective hours remain punch-out minus punch-in;
- the existing `day_value` mapping remains unchanged;
- the existing authorization check remains unchanged;
- approved/paid payroll lock behavior remains unchanged.

A custom non-working weekday may still receive a manual attendance correction under the existing admin policy, but no company-time late/early/overtime values are invented for that day.

## Snapshot preservation

If an attendance row already contains a V2 custom schedule snapshot, administrative correction uses that snapshot instead of re-resolving the day. This preserves the interpretation that governed the original attendance event.

If no snapshot exists, the custom resolver is required; otherwise the private custom function fails closed.

## Deliberate downstream block

The custom administrative path still invokes the existing:

- `settle_attendance_day_against_leave(..., true)`;
- `reprocess_attendance_day_penalties(...)`.

Those helpers have not yet been made schedule-aware. This is safe during development because the shared runtime gate remains hard-coded false.

Batch 3B must close those schedule-duration dependencies before any real activation can occur.

## Verification prepared

`supabase/verification/20260807153600_hr_variable_schedules_v2_batch2b_verify.sql` checks:

1. runtime gate remains false;
2. Legacy body hash remains exact;
3. fail-closed dispatch occurs before custom lookup;
4. public execute contract remains available;
5. internal implementations are not directly executable by external app roles;
6. custom implementation contains snapshot usage and preserves the 30/5-minute admin thresholds;
7. legacy leave-settlement and penalty calls remain explicit and therefore visible for Batch 3B;
8. no invalid partial custom snapshot exists.

The verification script itself received a static syntax correction before this review was closed.

## Production / deployment status

- No V2 migration has been applied to production Supabase.
- Production database access remains read-only.
- No Vercel deployment has been created by V2 commits since branch deployment suppression was added.
- No application build has been triggered.

## Next boundary

Batch 3 is split deliberately:

- **3A:** work-day classification, absence marking, and auto-checkout timing only.
- **3B:** penalty duration and leave-settlement duration only.

Notification timing, payroll, UI, and release activation remain outside 3A/3B unless separately reviewed.
