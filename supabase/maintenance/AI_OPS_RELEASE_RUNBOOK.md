# AI Operations Operator — Release Runbook

This runbook is the release gate for the AI Operations Operator. It is not an instruction to deploy automatically. Production remains untouched until every qualification step below has passed and release approval is explicit.

## 1. Safety invariants

- Treat operational source tables as read-only inputs to AI Operations.
- Keep `planner_enabled=false` during database and Edge deployment.
- Keep `shadow_mode=true` and `auto_commit_enabled=false` for initial live qualification.
- Never replay the full historical migration directory against production.
- Apply only the explicitly approved AI Operations release migration set, one file at a time, stopping on the first failure.
- Do not store the Supabase service-role key in pg_cron. The scheduler uses a dedicated worker secret stored in Vault.
- Never replace, disable, or unschedule unrelated production cron jobs; AI Operations owns only the named `ai-operations-worker-poller` job.
- A migration failure is handled with a forward fix unless a tested rollback exists for that exact migration. Do not improvise destructive rollback SQL.

## 2. Production facts verified read-only on 2026-08-22

Before this hardening branch is released, production was inspected read-only and showed:

- `ai_ops` schema is not present.
- Work Management is present through `20260815004000`.
- `public.activities` has `type_id`; it does not have an `activities.type` column.
- `public.activity_types.id` is the lookup target and `activity_types.code` is the stable activity code.
- `pg_cron`, `pg_net`, and `supabase_vault` are installed.
- `cron.job` currently contains 12 active existing jobs; none is named `ai-operations-worker-poller`.

Re-run the read-only preflight immediately before release; do not rely solely on this historical observation.

## 3. Required release artifacts

The release candidate must contain all AI Operations migrations from the approved start through the current terminal migration, including:

- `20260816163504_ai_operations_foundation.sql`
- all subsequent approved `*_ai_operations_*.sql` migrations in timestamp order
- `20260817010300_ai_operations_worker_context_budget_hardening.sql`

It must also contain:

- `supabase/functions/ai-operations-worker/index.ts`
- `supabase/config.toml`
- `supabase/maintenance/ai_ops_operator_schedule.sql`
- `supabase/maintenance/ai_ops_operator_unschedule.sql`
- `supabase/rehearsal/run_ai_ops_clone_rehearsal.sh`
- `supabase/rehearsal/verify_ai_ops_clone_context.sql`
- `supabase/rehearsal/run_ai_ops_edge_rehearsal.sh`
- the manual deployment workflow
- AI Operations contract tests

Record the exact release commit SHA and never substitute a later unreviewed branch head during rollout.

## 4. Read-only production preflight

Run read-only checks and preserve the output with the release evidence:

```sql
select exists(
  select 1 from information_schema.schemata where schema_name='ai_ops'
) as ai_ops_exists;

select column_name, data_type, udt_name
from information_schema.columns
where table_schema='public' and table_name='activities'
order by ordinal_position;

select extname, extversion
from pg_extension
where extname in ('pg_cron','pg_net','supabase_vault');

select jobid, jobname, schedule, active
from cron.job
order by jobid;

select version
from supabase_migrations.schema_migrations
order by version desc
limit 30;
```

Any material difference from the expected production contract stops the release for review.

## 5. Backup and restore readiness

Before any production migration:

1. Confirm the current Supabase backup/PITR capability and recovery point applicable to the project.
2. Record the recovery reference/time and the release start time.
3. Confirm database access needed for a forward fix is available.
4. Capture the current schema/migration state.

Do not proceed merely because migrations are additive; a partially applied release still requires a controlled recovery path.

## 6. Mandatory isolated production-clone rehearsal

Use the curated isolated database derived from the final production state. Do not modify production for this rehearsal.

The guarded runner is:

```bash
AI_OPS_REHEARSAL_CONFIRM=ISOLATED_PRODUCTION_CLONE \
AI_OPS_REHEARSAL_DB_URL='<isolated clone connection string>' \
bash supabase/rehearsal/run_ai_ops_clone_rehearsal.sh
```

The runner refuses to proceed without the explicit clone confirmation, refuses a baseline where `ai_ops` already exists, applies the approved AI Operations migration files one by one with `ON_ERROR_STOP=1`, and then executes the realistic seven-domain context gate.

The context gate must prove:

- expected schemas/tables/functions exist;
- all seven required domain captures are present;
- `blocked=false`;
- `context_bytes <= context_limit_bytes`;
- `context_limit_bytes` remains exactly 65,536 rather than being raised to make the test pass;
- all seven required capture markers remain present, while selected cases cover exactly every demand-bearing capture (`case_count > 0`, `has_more=true`, or `global_budget_exhausted=true`) and no zero-demand or unknown domain;
- every selected frozen case retains meaningful, non-empty responsibility, operational/feasibility, trust and facts values after compaction; key-only or compaction-marker-only evidence fails the gate;
- the context hash is produced;
- the probe itself is rolled back after verification.

The actual Edge/model lifecycle is a separate mandatory gate. Prepare a due run on the isolated clone, deploy/configure the rehearsal Edge Function against that clone, then run:

```bash
AI_OPS_REHEARSAL_CONFIRM=ISOLATED_PRODUCTION_CLONE \
AI_OPS_EDGE_REHEARSAL_URL='<isolated Edge function URL>' \
AI_OPS_EDGE_REHEARSAL_SECRET='<dedicated rehearsal worker secret>' \
bash supabase/rehearsal/run_ai_ops_edge_rehearsal.sh
```

That gate requires a successful claim and completes the actual Edge → model → stage → validate lifecycle. It fails on blocked context, unsuccessful model/worker response, missing claim, or incomplete stage/validation response.

The production-clone rehearsal is the authoritative database/runtime qualification. A source-code contract test alone is not a substitute.

## 7. Production database rollout

Only after the clone rehearsal passes:

1. set/confirm `planner_enabled=false`;
2. apply the exact approved AI Operations migration files one by one;
3. after each file, record success and run its checkpoint verification;
4. stop immediately on any error;
5. do not continue to later migrations hoping a later migration will repair an earlier failure;
6. after the terminal migration, verify RLS/revokes/service gateways/settings again.

The field execution migration must compile against the real production activity schema before continuing beyond it.

## 8. Edge Function secrets

Configure the Edge Function environment with secret values supplied through the deployment platform, never committed to Git:

- `INTERNAL_AI_OPS_WORKER_SECRET`
- `AI_OPS_MODEL_BASE_URL`
- `AI_OPS_MODEL_API_KEY`
- `AI_OPS_MODEL`
- optional `AI_OPS_MODEL_TIMEOUT_MS` (default is 90000 ms)

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are platform-provided runtime values. The service-role key is used only inside the Edge Function to execute the private RPC surface. It is not an accepted inbound HTTP credential and must not be copied into the cron scheduler.

For the database scheduler, create Vault secrets:

- `ai_ops_edge_function_url` — full `.../functions/v1/ai-operations-worker` URL
- `ai_ops_worker_secret` — exactly the same dedicated secret as `INTERNAL_AI_OPS_WORKER_SECRET`

The function is configured with `verify_jwt=false` because invocation is service-to-service. Every POST must present the dedicated `x-ai-ops-worker-secret`; the handler rejects requests if the dedicated secret is missing or mismatched.

## 9. Edge deployment

Use the manual `deploy-ai-operations-worker.yml` workflow against the exact approved release commit. It must pass its source/config/tests gate before deployment.

Deployment of the Edge Function does not enable the planner and does not create the cron job.

After deployment, perform one authenticated manual invocation while the planner is still disabled and confirm the expected safe behavior before scheduling it.

## 10. Scheduler activation

Only after the database and Edge Function are qualified and the Vault secrets exist, run:

`supabase/maintenance/ai_ops_operator_schedule.sql`

The script:

- validates `pg_cron` and `pg_net`;
- validates both required Vault secrets;
- replaces only the named `ai-operations-worker-poller` job;
- leaves every unrelated existing cron job untouched;
- calls the Edge Function through `pg_net` once per minute;
- sends the dedicated worker secret, not the service-role key.

Verify the resulting row in `cron.job` and re-check that unrelated production jobs remain unchanged.

## 11. First live activation

Activate live behavior in stages:

1. configure only the explicitly approved AI Operations run schedules;
2. keep `shadow_mode=true`;
3. keep `auto_commit_enabled=false`;
4. enable `planner_enabled=true`;
5. observe completed runs, context sizes, domain coverage, model failures, decision validation and review queues;
6. manually inspect representative decisions across all domains;
7. only after an explicit later approval may any broader automation policy be considered.

A successful Edge invocation with `claimed=false` is normal when no due run exists.

## 12. Kill switch

For any unsafe or unexplained behavior:

1. set `planner_enabled=false`;
2. run `supabase/maintenance/ai_ops_operator_unschedule.sql` to stop new Edge invocations;
3. leave `auto_commit_enabled=false`;
4. preserve run/decision evidence for diagnosis;
5. use a reviewed forward fix for database changes rather than deleting historical migrations.

Disabling the planner is the primary logical kill switch; unscheduling the poller is the transport-level kill switch. Neither action may alter unrelated cron jobs.

## 13. Final GO criteria

Release remains **NO-GO** until all are true:

- sequential migration rehearsal passes on the final production clone;
- realistic seven-domain context remains within the hard byte budget while retaining decision-critical evidence;
- actual Edge/model lifecycle passes with timeout/heartbeat behavior;
- scheduler/auth/secrets path is proven without exposing the service-role key or altering unrelated cron jobs;
- full automated test/build/lint gates are green and Windows/Linux line endings are stable;
- the final integration branch is conflict-free;
- the final PR targets `main`, is no longer Draft, and represents the exact qualified release SHA;
- a short independent final review issues GO.
