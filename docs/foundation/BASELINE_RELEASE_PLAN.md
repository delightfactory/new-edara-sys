# Baseline release package and rollback — 2026-10-12

Status: published after explicit owner approval; see BASELINE_PRODUCTION_RELEASE.md for the executed record. The sequences below describe the controlled release procedure.
Application source is frozen at `d7fdc527f3dc087f5f0c30b464df31ee481c8483` on
`codex/baseline-ui-polish`. Later documentation commits do not change that application.
This release does not merge DS2 governance work, deferred AI operations or resale changes.

## Exact targets

- Production: `edara.delight-world.com`, Vercel project
  `prj_lxOEu9ZLCgeKdlJbIj2Rt4YMWBEF`, team `team_AYQTvxuQJ1EepKxDVhzjX1ew`.
- Pre-release production deployment retained for rollback: `dpl_Aa1KTwZFaBj9fj766JtTHMgLr6Ld`,
  source `main` / `d0d5f35429463219e575d4e306464ea24ebed776`.
- Production Supabase: `ozthzccqudrudicnneuu`.
- Qualification: owned `edara-qualification-20261011`, API `127.0.0.1:60451`,
  immutable static build on ports 5182–5184. User preview 5180 and its database stay separate.
- Qualification is local deployment rehearsal. No hosted Vercel Preview/cloud-database
  qualification is claimed; the loopback build must never be uploaded as a production artifact.

## Finite work and acceptance

1. Freeze source, lockfile and ten migration hashes; archive the source and build against
   the owned qualification API with env-file loading disabled.
2. Read production function/view/table contracts and ACLs only. Compare grant-only
   function bodies and owners with candidate; investigate unexpected drift before release.
3. Run exact-source full suite, lint/types/build; actual Auth/PostgREST and scoped Realtime;
   browser automatic stock refresh/reconnect; actual old-to-new PWA update.
4. Restore qualification database from its pre-test dump, compare all public-table row
   fingerprints and relevant definitions, retire test fixtures. Preserve user UAT.
5. Independent bounded Claude review of this package. Save sanitized evidence in Git.
6. Stop at reviewable release candidate; await user UAT outcome and production approval.
   No additional redesign/refactor or repeated green-test loops belong to this release.

## Promotion sequence — executed record linked above

1. Recheck exact project/domain/deployment/database identities and hashes. Refresh the
   captured production catalog; invalidate this package if contracts changed.
2. Capture fresh production definitions, owners, view options and affected function/table/column ACLs. For this metadata-only release, the owner approved the targeted snapshot plus tested rollback as the recovery gate; this was executed and qualified. A full business-data backup was not taken or claimed. Any future data/schema migration must establish its own appropriate recovery gate.
3. Prepare a manual protected deployment from the frozen source, with production-specific
   build variables. Verify `VITE_SUPABASE_URL` names the production project and its matching
   public anon key, `VITE_VISITS_ATOMIC_EXECUTION=true`, and
   `VITE_DESIGN_SYSTEM_V2_SIDEBAR=true`. Review approved Sentry/VAPID settings without
   displaying secrets. Keep `git.deploymentEnabled=false`.
4. Apply only the ten named hash-verified SQL files in manifest order using the approved
   migration mechanism. Record actual outcomes; never invent migration history or apply
   the entire historical migration directory. No synthetic fixture SQL or local credentials.
5. Verify deployed function signatures/owners/ACLs, cost-safe reads, active-profile gates,
   and publication configuration. Notify PostgREST schema cache through the approved
   provider mechanism if needed. Do not grant broad access to make a failing check pass.
6. Promote the reviewed deployment only after database checks pass. Verify live HTTP,
   SPA deep links/assets, `sw.js` cache headers, actual source/build identity and API target.
   READY alone is insufficient. Check admin and representative workflows with authorized
   accounts, Realtime and PWA update; avoid artificial financial production postings.

## Rollback sequence — prepared, not executed

Trigger: reproducible release regression in login/permissions, normal business workflows,
visits, cost visibility or asset/PWA delivery. Pause affected writes and preserve incident
logs and the current database state; do not repeat promotion blindly.

1. Frontend: restore the previous recorded Vercel production deployment above, after
   confirming it is still the actual pre-release target and compatible with the migrated
   database. Verify domain/source/API and headers after rollback.
2. Database: prefer retaining compatible security hardening and additive RPCs. Returning
   the old UI does not by itself require reverting database security. Assess the concrete
   failure before any database undo.
3. If database reversal is required, restore the captured pre-change function/view
   definitions, owners, table/column ACLs and function ACLs for affected objects in reverse
   dependency order within controlled transactions. Review every restored grant: it can
   reopen a known security weakness. Keep business writes paused while resolving that risk.
   Revoke/remove additive surfaces only after confirming no caller depends on them.
4. Never restore a whole database over post-release business transactions as a routine
   rollback. Use the fresh backup/PITR in a separate restore target for recovery assessment,
   then reconcile affected records before any destructive cutover.
5. PWA: existing clients can retain old cached bundles until they explicitly accept an
   update. Retain prior assets and check both client generations. Verify rollback update
   prompt/manual acceptance and session recovery; do not clear users' drafts or offline
   queues to conceal an update problem.

Private source archive/build, full local dump, production definitions/ACL catalogs and
raw logs are outside Git. Production backup creation/restore and provider promotion are
separate gates and are not certified by the local rehearsal.
