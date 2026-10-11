# Visits workflow qualification — 2026-10-11

Bounded extension of `codex/baseline-ui-polish`, following the existing baseline
`fd232077b664bb7a4ee5fac500b7d913e7a382c1`. No production deployment, hosted migration,
DS2 merge, or AI-operations integration is included.

## Functional repairs

- Start consent: the original execution page set `showGeoDialog` but did not mount
  `GeoPermissionDialog`. Commit `775cc61` connects the existing allow/dismiss handlers.
  Prompt, allow, deny, unavailable, timeout, dismissal/reopening, and repeated clicks
  are covered without changing location policy, ownership, or queue semantics.
- Rescheduling already has an atomic destination-plan/replacement-item RPC. The legacy
  feature-disabled path only updates the original item's status/date. The local preview
  was feature-disabled; its external launcher now enables `VITE_VISITS_ATOMIC_EXECUTION`.
  The served module was checked; the fresh execution page passes the feature gate and
  correctly refuses execution by an account other than the assigned representative.
- Rescheduling the last item exposed a database defect: the plan closes, then a repeated
  counter update encounters `completion_pct`/`closure_pct` generated fields before
  PostgreSQL recomputes them in a BEFORE trigger. Migration
  `20261011190839_fix_visit_closed_plan_generated_column_guard.sql` excludes only those
  generated fields from the two closed-plan row comparisons. All other comparisons,
  status transitions, permission checks, and mutation guards are preserved.
- Local migration definition was mechanically compared with the actual previous
  function. A private full-database backup and original-function rollback artifact were
  saved before applying it to the owned local test database. No migration history was
  manually invented and no production database was changed.

## Evidence and limits

| Check | Result |
|---|---|
| Full application suite before the final wizard guard | 142 files / 1087 tests PASS |
| Final wizard/execution delta | 2 files / 84 tests PASS, including the new guard regression |
| Lint and production build | PASS; final logs retained outside Git |
| Start database rollback scenario | PASS: start persisted, absent-location policy unchanged, replay idempotent, second active visit refused |
| Reschedule database rollback scenario | PASS: daily/weekly type, date/employee/time, source/replacement links, target draft and existing confirmed plan, duplicate/replay guards, last-item closure, closed notes refused |
| Actual unchanged service through Auth/PostgREST | PASS: 9 HTTP requests; target-day list retrieves persisted draft/replacement; replay creates no duplicate |
| Service fixture cleanup | All 158 public-table count/content snapshots restored |
| Responsive browser smoke | Actual local list, wizard settings, and plan details checked at 390, 900, 1440px; no document horizontal overflow |

The first unrestricted full-suite run overlapped builds/database work and hit timing
failures in two unchanged files. Those 57 tests passed with two workers; one bounded
full run with two workers then passed all 1087 tests. Assertions/timeouts were not
weakened. The subsequent small wizard guard was verified by its focused regression.

The SQL scripts use a privileged local database connection with synthetic claims;
they exercise real domain RPCs, not a general RLS proof. Start temporarily links an
existing fixture employee inside a transaction, then rolls everything back.
The HTTP reschedule test uses the synthetic admin account, so it does not certify
every representative/team permission combination. Real device permission prompts,
camera/location accuracy, and offline field use still require representative UAT.
Browser smoke is not exhaustive certification of every wizard step/dialog/state.

Owned environments: `edara-qualification-20261011` (HTTP/RPC fixtures),
`edara-baseline-full-20261011` (user preview at `http://127.0.0.1:5180`). Private
credentials, database dumps, raw customer screenshots, and service harness remain
outside Git. The user preview uses live Vite HMR. No historical plan was reassigned
or bypassed to make execution work.

## UX delivery

Existing primitives and scoped semantic-token CSS improve wizard steps/fields,
touch controls, summary density and plan cards. Execution always follows the current
visit in route order; row actions now explicitly say “فتح تنفيذ الخطة”. Customer
identity stays visible across tabs; GPS justification is available on both tabs;
disabled completion explains mandatory-checklist/photo-sync requirements. Checklist
forms stay mounted so tab switches retain draft answers. Reschedule confirmation
explains draft approval and offers “فتح خطة اليوم الجديد” after success.

A misleading daily-conflict message before choosing an employee was suppressed;
the existing selected-employee conflict policy remains unchanged.

Claude Code helped implement the bounded UX pass and independently reviewed the
database fix (PASS). Final Claude UI review confirmed the actual execution page,
consent dialog and scoped CSS (PASS). It disclosed that other pages were initially
read from an old mirror; their review was therefore not counted. Codex reviewed the
actual complete diff, tests, reschedule action/draft wording and browser layouts.

## Review boundary

This slice is qualified for continued local user testing. It does not declare the
entire application/resale edition certified or authorize production release.
Any production promotion must carry the migration and feature configuration together
and undergo the already required final release review.
