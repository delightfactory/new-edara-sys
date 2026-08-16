import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260816163504_ai_operations_foundation.sql',
), 'utf8')

const entityMap = readFileSync(resolve(
  process.cwd(),
  'docs/work-management/11_AI_OPERATIONS_EXISTING_ENTITY_MAP.md',
), 'utf8')

const workExtensionsApi = readFileSync(resolve(
  process.cwd(),
  'src/features/work/extensions-api.ts',
), 'utf8')

describe('AI Operations foundation migration contract', () => {
  it('creates an isolated planner schema and keeps it closed to browser roles', () => {
    expect(migration).toContain('CREATE SCHEMA ai_ops;')
    expect(migration).toContain('REVOKE ALL ON SCHEMA ai_ops FROM PUBLIC;')
    expect(migration).toContain('REVOKE ALL ON SCHEMA ai_ops FROM anon;')
    expect(migration).toContain('REVOKE ALL ON SCHEMA ai_ops FROM authenticated;')
    expect(migration).not.toMatch(/GRANT\s+(?:USAGE|ALL|SELECT|INSERT|UPDATE|DELETE|EXECUTE)[\s\S]*?TO\s+(?:anon|authenticated)\b/i)
  })

  it('ships disabled, shadow-only and without autonomous commit enabled', () => {
    expect(migration).toMatch(/planner_enabled\s+BOOLEAN\s+NOT NULL DEFAULT false/i)
    expect(migration).toMatch(/shadow_mode\s+BOOLEAN\s+NOT NULL DEFAULT true/i)
    expect(migration).toMatch(/auto_commit_enabled\s+BOOLEAN\s+NOT NULL DEFAULT false/i)
    expect(migration).toContain('ai_ops_settings_auto_commit_safe_state')
  })

  it('creates only planner-local runtime/governance tables', () => {
    for (const table of [
      'settings',
      'run_schedules',
      'planner_runs',
      'snapshots',
      'cases',
      'decisions',
      'operational_context',
      'decision_feedback',
    ]) {
      expect(migration).toContain(`CREATE TABLE ai_ops.${table}`)
      expect(migration).toContain(`ALTER TABLE ai_ops.${table} ENABLE ROW LEVEL SECURITY;`)
    }
  })

  it('does not alter current operational schemas or add source-table triggers/indexes', () => {
    expect(migration).not.toMatch(/ALTER\s+TABLE\s+(?:public|analytics|private)\./i)
    expect(migration).not.toMatch(/CREATE\s+(?:UNIQUE\s+)?INDEX[\s\S]*?ON\s+(?:public|analytics|private)\./i)
    expect(migration).not.toMatch(/CREATE\s+TRIGGER[\s\S]*?ON\s+(?:public|analytics|private)\./i)
    expect(migration).not.toMatch(/\b(?:sales_orders|customers|stock_movements|hr_employees|activities)\b/i)
  })

  it('does not install scheduler or external network integration in foundation', () => {
    expect(migration).not.toMatch(/\bcron\.schedule\s*\(/i)
    expect(migration).not.toMatch(/\bcron\.unschedule\s*\(/i)
    expect(migration).not.toMatch(/\bnet\.http_(?:get|post)\s*\(/i)
    expect(migration).not.toMatch(/\bhttp_(?:get|post)\s*\(/i)
    expect(migration).not.toMatch(/CREATE\s+EXTENSION\s+(?:IF\s+NOT\s+EXISTS\s+)?["']?pg_cron["']?/i)
  })

  it('keeps business-entity and human references soft across the isolation boundary', () => {
    expect(migration).not.toMatch(/REFERENCES\s+public\./i)
    expect(migration).toContain('entity_type VARCHAR(80)')
    expect(migration).toContain('entity_id UUID')
    expect(migration).toContain('recommended_owner_user_id UUID')
    expect(migration).toContain('recommended_assignee_user_id UUID')
    expect(migration).toContain('work_item_id UUID')
  })

  it('persists durable runs, stable cases and concise decision rationale', () => {
    expect(migration).toContain('run_key TEXT NOT NULL UNIQUE')
    expect(migration).toContain('lease_expires_at TIMESTAMPTZ')
    expect(migration).toContain('checkpoint TEXT NOT NULL')
    expect(migration).toContain('case_key TEXT NOT NULL UNIQUE')
    expect(migration).toContain("decision_type IN ('IGNORE','MONITOR','INVESTIGATE','INFORM','CREATE_WORK','ESCALATE')")
    expect(migration).toContain('concise_rationale TEXT NOT NULL')
  })

  it('makes the evidence snapshot immutable without touching source tables', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION ai_ops.reject_snapshot_mutation()')
    expect(migration).toContain('CREATE TRIGGER trg_ai_ops_snapshots_immutable')
    expect(migration).toContain('BEFORE UPDATE OR DELETE ON ai_ops.snapshots')
  })

  it('uses the verified existing Work entity-link capability instead of duplicating it', () => {
    expect(entityMap).toContain('public.work_links')
    expect(entityMap).toContain('public.work_add_link(...)')
    expect(workExtensionsApi).toContain(".from('work_links')")
    expect(workExtensionsApi).toContain("'work_add_link'")
    expect(migration).not.toMatch(/CREATE TABLE\s+(?:public\.)?work_(?:entity_)?links/i)
  })
})
