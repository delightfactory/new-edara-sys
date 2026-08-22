import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const readText = (path: string) =>
  readFileSync(resolve(process.cwd(), path), 'utf8').replace(/\r\n/g, '\n')

const fieldMigration = readText(
  'supabase/migrations/20260817007500_ai_operations_field_execution_case_engine.sql',
)
const contextMigration = readText(
  'supabase/migrations/20260817010300_ai_operations_worker_context_budget_hardening.sql',
)
const worker = readText('supabase/functions/ai-operations-worker/index.ts')
const config = readText('supabase/config.toml')
const scheduler = readText('supabase/maintenance/ai_ops_operator_schedule.sql')
const killSwitch = readText('supabase/maintenance/ai_ops_operator_unschedule.sql')
const deployment = readText('.github/workflows/deploy-ai-operations-worker.yml')
const runbook = readText('supabase/maintenance/AI_OPS_RELEASE_RUNBOOK.md')

describe('AI Operations release hardening contract', () => {
  it('compiles the early Field Execution migration against the production activity schema', () => {
    expect(fieldMigration).toContain('LEFT JOIN public.activity_types at ON at.id=a.type_id')
    expect(fieldMigration).toContain("COALESCE(at.code::TEXT,'activity')")
    expect(fieldMigration).not.toContain('a.type::TEXT')
  })

  it('bounds worker context without raising the configured hard byte limit or dropping selected cases', () => {
    expect(contextMigration).toContain('CREATE OR REPLACE FUNCTION ai_ops.compact_worker_json')
    expect(contextMigration).toContain('v_context_case_limit')
    expect(contextMigration).toContain('v_settings.max_worker_context_bytes - 12288')
    expect(contextMigration).toContain("v_compaction_tier TEXT := 'bounded-v1'")
    expect(contextMigration).toContain("v_compaction_tier := 'bounded-v1-tight'")
    expect(contextMigration).toContain("'case_id', sc.case_id")
    expect(contextMigration).toContain("'responsibility_evidence', ai_ops.compact_worker_json")
    expect(contextMigration).toContain("'operational_context', ai_ops.compact_worker_json")
    expect(contextMigration).toContain("checkpoint = 'context_budget_blocked'")
    expect(contextMigration).not.toMatch(/SET\s+max_worker_context_bytes\s*=/i)
  })

  it('puts a bounded model wait behind an AbortSignal and refreshes the lease while reasoning', () => {
    expect(worker).toContain('AI_OPS_MODEL_TIMEOUT_MS')
    expect(worker).toContain('new AbortController()')
    expect(worker).toContain('signal: abortController.signal')
    expect(worker).toContain('setInterval(() =>')
    expect(worker).toContain("rpc('ai_ops_worker_heartbeat'")
    expect(worker).toContain("return 'model_timeout'")
    expect(worker).toContain("return 'model_http_retryable'")
    expect(worker).toContain("return 'model_http_non_retryable'")
  })

  it('pins service-to-service Edge authentication explicitly', () => {
    expect(config).toContain('[functions.ai-operations-worker]')
    expect(config).toMatch(/\[functions\.ai-operations-worker\]\nverify_jwt = false(?:\n|$)/)
  })

  it('schedules through pg_cron and pg_net using a dedicated Vault secret, never the service-role key', () => {
    expect(scheduler).toContain("cron.schedule(")
    expect(scheduler).toContain("'ai-operations-worker-poller'")
    expect(scheduler).toContain('net.http_post(')
    expect(scheduler).toContain('vault.decrypted_secrets')
    expect(scheduler).toContain("name = 'ai_ops_edge_function_url'")
    expect(scheduler).toContain("name = 'ai_ops_worker_secret'")
    expect(scheduler).toContain("'x-ai-ops-worker-secret'")
    expect(scheduler).not.toContain('SUPABASE_SERVICE_ROLE_KEY')
    expect(killSwitch).toContain("cron.unschedule(v_job.jobid)")
  })

  it('keeps production deployment manual and separated from activation', () => {
    expect(deployment).toContain('workflow_dispatch:')
    expect(deployment).toContain('DEPLOY_AI_OPS_WORKER')
    expect(deployment).toContain('functions deploy ai-operations-worker')
    expect(deployment).not.toContain('db push')
    expect(deployment).not.toContain('cron.schedule')
    expect(deployment).not.toContain('planner_enabled=true')
  })

  it('makes a final production-clone lifecycle rehearsal a GO requirement', () => {
    expect(runbook).toContain('Mandatory isolated production-clone rehearsal')
    expect(runbook).toContain('require `blocked=false`')
    expect(runbook).toContain('all seven required domain capture markers')
    expect(runbook).toContain('actual Edge Worker path')
    expect(runbook).toContain('Release remains **NO-GO** until all are true')
  })
})
