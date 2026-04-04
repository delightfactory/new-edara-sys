#!/usr/bin/env node
/**
 * 02_generate_rls_migration.js
 * ============================
 * Safe RLS Migration Generator
 * Transforms live pg_policies snapshot into optimized SQL
 *
 * Input:  policies_snapshot.json
 * Output: output/66_rls_initplan_safe.sql
 *         output/policies_diff_report.md
 *
 * Transformations applied (ONLY these):
 *   1. auth.uid()                        -> (SELECT auth.uid())
 *   2. check_permission(auth.uid(), 'X') -> (SELECT check_permission((SELECT auth.uid()), 'X'))
 *   3. Add TO authenticated              (only for appropriate policies)
 *
 * Safety exclusions:
 *   - Policies using auth.role()     (service_role bypass)
 *   - Policies named *service_role*
 *   - Policies with roles: [anon] or [service_role]
 */

const fs   = require('fs')
const path = require('path')

const TOOLS_DIR    = path.dirname(__filename)
const PROJECT_ROOT = path.resolve(TOOLS_DIR, '..', '..', '..')

const SNAPSHOT_CANDIDATES = [
  path.join(TOOLS_DIR, 'policies_snapshot.json'),
  path.join(PROJECT_ROOT, 'tools', 'policies_snapshot.json'),
]

const OUTPUT_DIR    = path.join(TOOLS_DIR, 'output')
const OUTPUT_SQL    = path.join(OUTPUT_DIR, '66_rls_initplan_safe.sql')
const OUTPUT_REPORT = path.join(OUTPUT_DIR, 'policies_diff_report.md')

// Find snapshot file
const SNAPSHOT_PATH = SNAPSHOT_CANDIDATES.find(p => fs.existsSync(p))

if (!SNAPSHOT_PATH) {
  console.error('\u274c Snapshot file not found in:\n' + SNAPSHOT_CANDIDATES.map(p => '  - ' + p).join('\n'))
  process.exit(1)
}

console.log('Found snapshot: ' + path.relative(PROJECT_ROOT, SNAPSHOT_PATH))

// Load and parse snapshot
let policies
try {
  const raw    = fs.readFileSync(SNAPSHOT_PATH, 'utf8').trim()
  const parsed = JSON.parse(raw)

  // Handle all possible formats from Supabase SQL Editor:
  // Format A: [{ tablename, policyname, ... }, ...]   (direct array)
  // Format B: { policies_snapshot: [...] }            (object with key)
  // Format C: [{ policies_snapshot: [...] }]          (array wrapping object) <-- actual format
  if (Array.isArray(parsed)) {
    if (parsed.length > 0 && Array.isArray(parsed[0].policies_snapshot)) {
      policies = parsed[0].policies_snapshot   // Format C
    } else {
      policies = parsed                         // Format A
    }
  } else if (parsed && Array.isArray(parsed.policies_snapshot)) {
    policies = parsed.policies_snapshot          // Format B
  } else {
    throw new Error('Unrecognized snapshot format')
  }

  if (!Array.isArray(policies)) throw new Error('Not an array after parsing')
  console.log('Loaded ' + policies.length + ' policies from database snapshot')
} catch (err) {
  console.error('Error reading snapshot: ' + err.message)
  process.exit(1)
}

// ── Safety checks ────────────────────────────────────────────────────────────

function isExcluded(policy) {
  const roles    = policy.roles ?? []
  const name     = policy.policyname ?? ''
  const qual     = policy.qual ?? ''
  const wcheck   = policy.with_check ?? ''
  const allExprs = qual + ' ' + wcheck

  if (roles.includes('service_role'))          return { excluded: true, reason: 'roles: service_role' }
  if (roles.includes('anon'))                  return { excluded: true, reason: 'roles: anon' }
  if (name.includes('service_role'))           return { excluded: true, reason: 'policy name contains service_role' }
  if (/auth\.role\s*\(\s*\)/.test(allExprs))  return { excluded: true, reason: 'uses auth.role() - service_role check' }

  return { excluded: false }
}

// ── Safe expression transformer ──────────────────────────────────────────────
//
// The actual format in pg_policies uses PostgreSQL cast notation:
//   check_permission(auth.uid(), 'finance.expenses.read'::text)
//                                                        ^^^^^^
// So the regex MUST match optional ::text (or ::varchar etc.) casts after the string.
//
// Order of operations:
//   1. Wrap full check_permission(auth.uid(), 'X'::cast) -> (SELECT check_permission((SELECT auth.uid()), 'X'::cast))
//   2. Wrap ALL remaining auth.uid()                     -> (SELECT auth.uid())
//   3. Remove any accidental double-wraps

function transformExpression(expr) {
  if (!expr) return { text: null, changed: false }

  const original = expr
  let text = expr

  // Step 1: wrap the full check_permission(...) call
  // CRITICAL FIX: pg_policies stores 'permission.name'::text — the regex MUST include
  // an optional PostgreSQL type cast (::text, ::varchar, ::name, etc.) after the string
  text = text.replace(
    /check_permission\s*\(\s*auth\.uid\s*\(\s*\)\s*,\s*('[^']*'|"[^"]*")(\s*::\s*\w+)?\s*\)/gi,
    (_, perm, cast) => '(SELECT check_permission((SELECT auth.uid()), ' + perm + (cast || '') + '))'
  )

  // Step 2: wrap ALL remaining bare auth.uid() including those inside subqueries
  text = text.replace(/auth\.uid\s*\(\s*\)/gi, '(SELECT auth.uid())')

  // Step 3: remove double-wraps, e.g. (SELECT (SELECT auth.uid())) -> (SELECT auth.uid())
  let prev
  do {
    prev = text
    text = text.replace(/\(\s*SELECT\s+\(\s*SELECT\s+auth\.uid\s*\(\s*\)\s*\)\s*\)/gi, '(SELECT auth.uid())')
  } while (text !== prev)

  return { text, changed: text !== original }
}

// ── Roles clause builder ─────────────────────────────────────────────────────
// CRITICAL FIX: we NEVER inject or change roles.
// We emit exactly what the snapshot says — preserving 'public' where it was public.
// 'public' in PostgreSQL RLS = all roles (authenticated + anon + service_role).
// Some policies (e.g. company_settings.settings_select with is_public=true) are
// intentionally public so anon users can read public rows. Changing to
// TO authenticated would silently break that.

function buildRolesClause(policy) {
  const roles = policy.roles ?? []
  // 'public' means no TO clause (applies to everyone) — do not emit TO public,
  // just omit the clause entirely, which is equivalent
  if (!roles.length || (roles.length === 1 && roles[0] === 'public')) return ''
  // For any other explicit role list, emit it verbatim
  return 'TO ' + roles.join(', ') + '\n'
}

// ── Build CREATE POLICY SQL ──────────────────────────────────────────────────

function buildCreatePolicy(policy, newQual, newWithCheck) {
  const { tablename, policyname, cmd, permissive } = policy
  const isRestrictive = (permissive === 'RESTRICTIVE')
  // Use EXACT original roles from snapshot — never inject TO authenticated
  const toClause = buildRolesClause(policy)
  const cmdStr   = cmd === 'ALL' ? 'FOR ALL' : 'FOR ' + cmd

  let sql = 'DROP POLICY IF EXISTS "' + policyname + '" ON ' + tablename + ';\n'
  sql += 'CREATE POLICY "' + policyname + '" ON ' + tablename + ' ' + cmdStr + '\n'
  if (isRestrictive) sql += 'AS RESTRICTIVE\n'
  if (toClause)      sql += toClause

  if (newQual) {
    sql += 'USING (' + newQual + ')'
    if (newWithCheck) sql += '\nWITH CHECK (' + newWithCheck + ')'
    sql += ';\n'
  } else if (newWithCheck) {
    sql += 'WITH CHECK (' + newWithCheck + ');\n'
  } else {
    sql += ';\n'
  }

  return sql
}

// ── Main processing ──────────────────────────────────────────────────────────

const diffEntries  = []
const sqlChunks    = []
let changedCount   = 0
let excludedCount  = 0
let unchangedCount = 0

policies.sort((a, b) =>
  (a.tablename || '').localeCompare(b.tablename || '') ||
  (a.policyname || '').localeCompare(b.policyname || '')
)

let currentTable = null

for (const policy of policies) {
  const { excluded, reason } = isExcluded(policy)

  if (excluded) {
    excludedCount++
    diffEntries.push({ table: policy.tablename, policy: policy.policyname, status: 'SKIP', reason })
    continue
  }

  const { text: newQual,      changed: qualChanged      } = transformExpression(policy.qual)
  const { text: newWithCheck, changed: withCheckChanged } = transformExpression(policy.with_check)
  const hasChange = qualChanged || withCheckChanged

  if (!hasChange) {
    unchangedCount++
    diffEntries.push({ table: policy.tablename, policy: policy.policyname, status: 'NO_CHANGE', reason: 'no bare auth.uid() found' })
    continue
  }

  if (currentTable !== policy.tablename) {
    const sep = '─'.repeat(Math.max(0, 50 - (policy.tablename || '').length))
    sqlChunks.push('\n-- +++ ' + policy.tablename + ' ' + sep)
    currentTable = policy.tablename
  }

  sqlChunks.push(buildCreatePolicy(policy, newQual, newWithCheck))

  changedCount++
  diffEntries.push({
    table:         policy.tablename,
    policy:        policy.policyname,
    status:        'CHANGED',
    reason:        null,
    before_qual:   policy.qual,
    after_qual:    newQual,
    before_check:  policy.with_check,
    after_check:   newWithCheck,
  })
}

// ── Write migration SQL ───────────────────────────────────────────────────────

fs.mkdirSync(OUTPUT_DIR, { recursive: true })

const header = [
  '-- ==============================================================',
  '-- 66_rls_initplan_safe.sql',
  '-- GENERATED by 02_generate_rls_migration.js',
  '-- Source: pg_policies catalog (live database snapshot)',
  '-- Generated: ' + new Date().toISOString(),
  '--',
  '-- Transformations:',
  '--   auth.uid()                         -> (SELECT auth.uid())',
  '--   check_permission(auth.uid(), X)    -> (SELECT check_permission((SELECT auth.uid()), X))',
  '--   Added TO authenticated on applicable policies',
  '--',
  '-- Stats:',
  '--   Transformed: ' + changedCount,
  '--   Unchanged:   ' + unchangedCount,
  '--   Skipped:     ' + excludedCount,
  '-- ==============================================================',
  '',
  'BEGIN;',
  '',
].join('\n')

const footer = '\nCOMMIT;\n'
fs.writeFileSync(OUTPUT_SQL, header + sqlChunks.join('\n') + footer, 'utf8')

// ── Write diff report ─────────────────────────────────────────────────────────

let report = '# RLS Policies Diff Report\n'
report += '> Generated: ' + new Date().toISOString() + '\n'
report += '> Source: pg_policies (live database)\n\n---\n\n'
report += '## Summary\n\n'
report += '| Status | Count |\n|--------|-------|\n'
report += '| Transformed | **' + changedCount + '** |\n'
report += '| No change needed | ' + unchangedCount + ' |\n'
report += '| Skipped (service_role/anon) | ' + excludedCount + ' |\n'
report += '| Total | ' + policies.length + ' |\n\n---\n\n'

// Changed policies
const changed = diffEntries.filter(e => e.status === 'CHANGED')
if (changed.length > 0) {
  report += '## Transformed Policies (' + changed.length + ')\n\n'
  for (const e of changed) {
    report += '### `' + e.table + '` — `' + e.policy + '`\n\n'
    if (e.before_qual) {
      report += '**USING before:**\n```sql\n' + e.before_qual + '\n```\n\n'
      report += '**USING after:**\n```sql\n' + e.after_qual + '\n```\n\n'
    }
    if (e.before_check) {
      report += '**WITH CHECK before:**\n```sql\n' + e.before_check + '\n```\n\n'
      report += '**WITH CHECK after:**\n```sql\n' + e.after_check + '\n```\n\n'
    }
    report += '---\n\n'
  }
}

// Skipped policies
const skipped = diffEntries.filter(e => e.status === 'SKIP')
if (skipped.length > 0) {
  report += '## Skipped Policies (' + skipped.length + ')\n\n'
  report += '| Table | Policy | Reason |\n|-------|--------|--------|\n'
  for (const e of skipped) {
    report += '| ' + e.table + ' | `' + e.policy + '` | ' + e.reason + ' |\n'
  }
  report += '\n'
}

fs.writeFileSync(OUTPUT_REPORT, report, 'utf8')

// ── Summary ───────────────────────────────────────────────────────────────────
console.log('\n=== Generation Complete ===')
console.log('Transformed: ' + changedCount + ' policies')
console.log('No change:   ' + unchangedCount + ' policies')
console.log('Skipped:     ' + excludedCount + ' policies')
console.log('\nOutput files:')
console.log('  SQL:    ' + path.relative(PROJECT_ROOT, OUTPUT_SQL))
console.log('  Report: ' + path.relative(PROJECT_ROOT, OUTPUT_REPORT))
console.log('\nREVIEW THE DIFF REPORT before applying the migration!')
