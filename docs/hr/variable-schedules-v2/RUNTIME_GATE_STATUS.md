# HR Variable Schedules V2 — Runtime Gate Status

## Decision

Development is intentionally paused before schedule-aware penalty and leave-settlement changes.

The current branch contains static implementations through:

- Batch 1 — additive schedule schema/resolver;
- Batch 2A — fail-closed GPS attendance adapter;
- Batch 2B — fail-closed administrative attendance adapter;
- Batch 3A1 — fail-closed work-day classifier;
- Batch 3A2 — fail-closed same-day absence timing.

The shared runtime activation function remains hard-coded `false`.

## Why the runtime gate is required now

The next dependency boundary is financially sensitive:

- `process_attendance_penalties(uuid)` uses company work-end and company daily hours in early-leave deduction calculations;
- `settle_attendance_day_against_leave(uuid,boolean)` uses company daily hours as the full-day threshold and partial-day denominator;
- GPS checkout and administrative correction both call these helpers.

Changing these functions without executing the accumulated V2 migrations on real PostgreSQL would recreate the migration-accumulation risk that V2 was designed to avoid.

Therefore Batch 3B and payroll are blocked until runtime rehearsal succeeds.

## Isolated rehearsal prepared

The branch contains:

- `.github/workflows/hr-v2-db-rehearsal.yml`;
- `supabase/rehearsal/hr_v2_rehearsal.sh`;
- `supabase/rehearsal/RUN_HR_V2_GATE`.

The workflow is intentionally scoped to the V2 branch and triggers only when the explicit gate marker file changes. Ordinary V2 commits do not run it.

The rehearsal contains no production Supabase URL, password, service-role key, Vercel token, or production data.

Its contract is fail-closed:

1. start an isolated local Supabase/PostgreSQL stack;
2. replay a curated HR baseline from repository SQL only;
3. compare captured production HR function hashes;
4. if any baseline hash differs, stop before V2;
5. only after baseline parity, apply V2 migrations;
6. execute V2 verification SQL.

## First rehearsal attempt

GitHub created workflow run `31180237236`, but no runner or workflow step started.

GitHub's check annotation reported:

`The job was not started because your account is locked due to a billing issue.`

This failure happened before checkout, Node setup, Docker/Supabase startup, SQL replay, or any V2 code execution. It is not a database or migration failure.

No retry should be attempted until the GitHub Actions account lock is resolved.

## Current local execution capability

The current development container has Node.js/npm but does not provide:

- `postgres`;
- `initdb`;
- `pg_ctl`;
- `psql`;
- Docker;
- Podman.

Therefore it cannot substitute for the isolated GitHub runner for PostgreSQL/PLpgSQL execution.

## Production safety

- No V2 migration has been applied to production Supabase.
- Production database access used by V2 remains read-only.
- No production attendance, leave, payroll, employee, or settings row has been written by V2 development.
- V2 runtime remains unreachable because the runtime gate is hard-coded false.
- No release, merge, or production activation is authorized.

## Resume condition

Resume Batch 3B only after a real PostgreSQL rehearsal has at minimum proven:

1. curated baseline reaches the captured production hashes;
2. Batch 1 through Batch 3A2 migrations compile in sequence;
3. all current V2 verification scripts pass;
4. legacy aliases preserve captured function bodies;
5. the runtime gate is still false after all migrations.

If the first executable rehearsal exposes baseline-replay gaps, fix the rehearsal baseline first. Do not change V2 business logic merely to make an incomplete test harness pass.
