# HR Variable Schedules V2 — Batch 1 Review

## Decision

**Static design gate: PASS.**

**Runtime database gate: NOT YET EXECUTED.**

Batch 2 must not begin until the Batch 1 migration is applied and verified on an isolated disposable database copy. Production is not an acceptable test target.

## Batch 1 artifacts

- `supabase/migrations/20260807114500_hr_variable_schedules_v2_batch1_schema.sql`
- `supabase/verification/20260807114600_hr_variable_schedules_v2_batch1_verify.sql`

No existing HR runtime source file, migration, table definition, attendance function, payroll function, leave function, settings code, or UI file was modified by Batch 1.

## Added data model

### `hr_employee_work_schedules`

Employee-specific version header only:

- employee;
- future `effective_from`;
- optional inclusive `effective_to`;
- notes and audit metadata.

No company schedule history was added.

### `hr_employee_work_schedule_days`

One row per weekday:

- `day_of_week` uses PostgreSQL DOW convention: Sunday `0` through Saturday `6`;
- working day requires start/end times;
- non-working day requires both times to be null;
- end must be later than start;
- overnight shifts remain unsupported;
- official minutes are derived from start/end rather than stored twice.

## Resolver contract

`resolve_employee_custom_schedule(employee_id, date)` is deliberately custom-only.

It returns a row only when all of these are true:

1. a schedule version is effective for that employee/date;
2. the version has exactly seven unique weekday rows;
3. at least one weekday is a working day;
4. the row for the requested weekday exists.

It does **not** synthesize company work times, company weekly off, or the legacy employee `weekly_off_day` field.

Therefore `NOT FOUND` remains an unambiguous instruction for future adapters: execute the untouched legacy path.

## Lifecycle rules

- New versions cannot start today or in the past.
- Future versions can be edited or deleted before they start.
- Once a version starts, weekday timing rows become immutable.
- An active version may only have its future end boundary planned/changed; historical timing cannot be rewritten.
- An ended version is immutable.
- Date ranges for the same employee cannot overlap.
- Deleting a permitted future header safely cascades to its weekday rows.

The migration intentionally does not auto-close a predecessor when a successor is created. A later UI/save operation must perform predecessor closure and successor creation atomically; Batch 1 does not add that write workflow yet.

## RLS boundary

New schedule tables use schedule-specific RLS only.

- Employee self-read is supported.
- Existing `hr.employees.read` permission can read schedules.
- Existing employee-management write permission controls schedule writes.
- `anon` receives no access to the new tables or resolver.
- No existing HR RLS policy or function grant was changed.

## Legacy parity evidence

`main...feature/hr-variable-schedules-v2` currently contains only:

- the V2 scope/baseline/review documents;
- the new Batch 1 migration;
- the new Batch 1 verification script;
- the branch-specific Vercel ignore rule.

No existing runtime file was edited.

The Batch 1 migration itself creates objects under new names and attaches triggers only to the two new schedule tables. It does not `ALTER` attendance, leave, payroll, employee, or settings runtime tables.

This gives strong static evidence that merely installing the Batch 1 schema cannot alter a current HR result. Runtime execution is still required to prove SQL compilation and trigger behavior on an isolated PostgreSQL/Supabase copy.

## Deliberate non-features

Batch 1 does not add:

- attendance snapshot columns;
- attendance routing;
- payroll routing;
- absence routing;
- auto-checkout routing;
- penalty changes;
- leave changes;
- company settings changes;
- feature activation;
- seed data;
- historical backfill;
- pilot employee data;
- UI.

## Verification status

Completed:

- production object-name collision check: read-only;
- production dependency baseline review: read-only;
- Git diff review against `main`;
- static lifecycle/integrity review;
- Vercel deployment check.

Not completed:

- executing the migration on an isolated database;
- executing the Batch 1 verification SQL;
- transactional lifecycle simulation (future create/edit/delete, overlap rejection, active immutability, resolver completeness);
- database advisor scan after applying the new schema.

## Deployment safety

No Batch 1 migration has been applied to the production Supabase project.

No Batch 1 commit has generated a Vercel deployment. The branch-specific automatic-deployment suppression remains effective.

## Gate before Batch 2

Before attendance integration begins, the isolated database rehearsal must prove:

1. migration compiles cleanly;
2. both new tables have RLS enabled;
3. migration seeds zero schedule rows;
4. incomplete schedules resolve to zero rows;
5. a valid seven-day future schedule resolves the correct weekday and minutes;
6. overlapping versions are rejected;
7. past/today starts are rejected;
8. started schedule day rows cannot be edited;
9. a future schedule can be deleted cleanly with its children;
10. existing HR runtime remains unchanged.

Until these pass, Batch 1 is **not** considered runtime-approved and Batch 2 is blocked.
