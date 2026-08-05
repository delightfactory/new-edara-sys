# Employee Work Schedules — Release and Rollback Plan

> This plan governs future deployment. It does not authorize a build, preview deployment, database migration, feature activation, or production release.

## 1. Release principle

The feature is introduced in a disabled, additive state and activated progressively.

Operational recovery must be possible by disabling custom schedule resolution without deleting schedule data, attendance snapshots, or historical audit records.

## 2. Environments

### GitHub feature branch

`feature/hr-employee-work-schedules`

- all design, migration, service, UI, and test work remains on this branch;
- Vercel automatic deployment is disabled for this branch;
- no merge to `main` until every gate is accepted.

### Disposable database environment

Required before production:

- Supabase branch or other isolated database created from the current schema;
- no production business data required beyond sanitized/controlled fixtures;
- migrations applied and rollback rehearsed there first.

### Production

No production DDL/DML is permitted during branch development. Production remains a read-only source for schema/function inspection until a separate explicit approval.

## 3. Feature controls

### Runtime switch

Proposed setting:

`hr.employee_work_schedules_enabled`

Initial production value: `false`.

When false:

- resolver ignores custom schedules and reproduces legacy behavior;
- no new attendance mutation uses custom schedule data;
- existing stored snapshots remain intact and readable;
- UI editing is hidden or marked unavailable for activation.

### Employee-level activation

A custom schedule affects only an employee with:

- a complete valid schedule;
- active status;
- an effective date covering the target date;
- the global runtime switch enabled.

No role-, department-, or job-title-based automatic activation in v1.

## 4. Migration phases

### Phase M1 — additive schema

- create schedule header and day tables;
- add nullable attendance snapshot columns;
- add indexes, constraints, audit metadata, and RLS;
- add disabled feature setting;
- do not change current function behavior.

Verification:

- existing tables and row counts unchanged;
- existing functions’ hashes unchanged;
- current attendance and payroll smoke queries unchanged;
- no default/backfill update on historical attendance.

Rollback:

- because runtime behavior is unchanged, operational rollback is not needed;
- schema removal is deferred until confirmed unreferenced and is not performed under incident pressure.

### Phase M2 — resolver and diagnostics

- create central resolver;
- create schedule validation and snapshot helper functions;
- create parity/preflight diagnostic functions;
- feature switch remains false;
- existing callers remain unchanged.

Verification:

- resolver fallback output compared with legacy work-day/time logic;
- permission grants reviewed;
- invalid schedule states fail clearly.

Rollback:

- revoke client execution if necessary;
- restore prior function set only in disposable rehearsal;
- production behavior remains unchanged because no caller consumes the resolver.

### Phase M3 — attendance integration

- update GPS v2 and any confirmed live legacy GPS path;
- update manual attendance correction;
- update work-day compatibility function;
- update absence marking and auto-checkout;
- update penalties and operational scans.

Feature switch remains false after deployment.

Verification:

- fallback parity for employees without schedules;
- no cron false positives;
- no historical attendance changes;
- no approved/paid payroll mutation.

Operational rollback:

1. set feature switch false;
2. verify all new resolutions return legacy source;
3. if a function defect affects fallback itself, restore the frozen pre-release function definitions through a reviewed emergency migration;
4. do not delete snapshots or schedules during the incident.

### Phase M4 — payroll integration

- update only schedule-dependent inputs in payroll;
- leave adjustments, advances, commissions, taxes, insurance, status guards, and accounting flow unchanged.

Feature switch remains false after deployment.

Verification:

- exact fallback parity matrix;
- custom schedule simulations;
- accounting balance;
- no automatic payroll recalculation triggered by schedule writes.

Operational rollback:

- disable feature switch;
- use frozen prior payroll function definition if fallback parity is compromised;
- never recalculate approved/paid runs as part of rollback.

### Phase M5 — UI and service layer

- add typed schedule service and validation;
- add employee profile schedule editor;
- editing requires reviewed permission;
- activation date warnings and history protection are visible.

This phase can be merged only after API/database contracts are stable.

## 5. Pre-production gates

### Gate A — branch integrity

- branch starts from reviewed `main` baseline;
- diff contains only schedule-related changes plus branch deploy protection;
- no credentials, generated artifacts, or production data;
- Vercel branch auto-deploy remains disabled.

### Gate B — static quality

- TypeScript build succeeds locally or in an explicitly triggered non-deploying environment;
- ESLint succeeds;
- Vitest succeeds;
- SQL parser/lint review succeeds;
- every replaced function preserves signature, owner/security mode, grants, and safe `search_path` unless a reviewed change is intended.

### Gate C — database safety

- forward migration rehearsal succeeds from a production-schema clone;
- migration is idempotent only where explicitly designed; accidental rerun fails safely otherwise;
- RLS policies and function grants verified;
- no table scan/backfill on production-sized history without plan and timing evidence;
- lock-impact analysis completed.

### Gate D — functional simulation

All blocking scenarios in `REGRESSION_MATRIX.md` pass.

### Gate E — fallback rehearsal

- disabling feature switch restores legacy runtime results;
- rollback function definitions are frozen and tested;
- open attendance days and draft payroll runs have a documented handling plan;
- no destructive rollback is required to stabilize operations.

## 6. Production deployment sequence

A future approved production window follows this order:

1. Confirm no payroll approval/payment operation is running.
2. Confirm no attendance correction batch is running.
3. Capture schema/function hashes and targeted row counts.
4. Apply M1 only.
5. Run M1 verification; stop on any mismatch.
6. Apply M2; keep switch false.
7. Run resolver parity diagnostics.
8. Apply M3/M4 only after their separate approval and preflight.
9. Keep switch false for an observation period.
10. Deploy UI/service code only when database APIs are present and disabled-safe.
11. Run end-to-end fallback smoke test.
12. Select one pilot employee and future effective date.
13. Enable global switch only during an attended monitoring window.
14. Verify pilot attendance and operational scan results.
15. Expand employee by employee after explicit review.

No bulk creation of schedules by department or role in the first rollout.

## 7. Pilot employee

Recommended first pilot: Ahmed Neamatallah, because his schedule exercises two distinct daily windows while remaining six hours per scheduled day.

Pilot data must be entered through the final UI/RPC after approval, not inserted as hard-coded migration data.

Required pilot checkpoints:

- schedule display and effective date;
- first check-in snapshot;
- first checkout calculations;
- one operational scan;
- one non-working day;
- one manual review screen;
- payroll preview in a non-approved run.

## 8. Monitoring after activation

Monitor at minimum:

- resolver errors;
- attendance rows missing complete snapshots after feature activation;
- false absences on custom off days;
- unexpected late/early/overtime distributions;
- open attendance rows after expected auto-checkout;
- operational alert volume;
- payroll parity diagnostics;
- database function errors and execution latency.

Suggested diagnostic counts:

- custom-schedule employees by effective date;
- attendance rows by `schedule_source`;
- work-day rows with null scheduled window;
- non-working rows with monetary penalties;
- snapshots referencing inactive/retired schedule versions;
- approved payroll periods containing post-approval attendance changes — expected zero.

## 9. Incident levels

### Level 1 — UI-only issue

Examples: schedule editor layout or validation display.

Action:

- disable/hide editor;
- keep database runtime unchanged;
- no schedule deletion.

### Level 2 — one employee schedule issue

Examples: incorrect weekday or effective date before attendance mutation.

Action:

- retire/correct through versioned schedule workflow;
- preserve audit trail;
- review any open attendance rows explicitly.

### Level 3 — schedule calculation issue

Examples: incorrect late/overtime/absence for pilot.

Action:

- immediately set feature switch false;
- stop schedule edits;
- preserve affected rows and logs;
- compare snapshots and resolver results;
- correct only open/unapproved periods through reviewed transactions.

### Level 4 — payroll or broad attendance regression

Action:

- disable feature switch;
- stop payroll calculations/approvals and attendance correction batches;
- restore frozen prior function definitions if fallback is affected;
- do not mutate approved/paid payroll;
- perform incident-specific reconciliation before reactivation.

## 10. Rollback artifacts required before production

- pre-feature definitions of every replaced function;
- checksums for those definitions;
- reverse/fallback migration scripts;
- feature-disable verification query;
- snapshot-integrity query;
- schedule-overlap query;
- payroll parity report query;
- list of new grants/policies and their reversal;
- deployment and operator checklist.

Artifacts are committed to the branch but are not executed automatically.

## 11. No destructive emergency rollback

During an incident, do not:

- drop schedule tables;
- drop attendance snapshot columns;
- delete schedule versions;
- null existing snapshots;
- recalculate historical attendance in bulk;
- recalculate approved/paid payroll;
- disable unrelated RLS policies;
- roll back the entire application for a schedule-only UI defect.

Operational fallback is the feature switch plus restoration of precisely scoped function definitions when necessary.

## 12. Final release approval record

Before any production action, the review must record:

- exact Git commit SHA;
- exact migration files and hashes;
- exact database project/environment;
- backup/preflight evidence;
- simulation results;
- identified pilot employee and effective date;
- feature switch initial state;
- rollback operator and decision threshold;
- explicit approval to apply migrations;
- separate explicit approval to enable the feature;
- separate explicit approval to expand beyond the pilot.