import { mkdtempSync, readFileSync, readdirSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { spawnSync } from 'node:child_process'
import { describe, expect, it } from 'vitest'

describe('local migration staging', () => {
  it('creates a Supabase-compatible uniquely versioned local copy without changing SQL bytes', () => {
    const tempRoot = mkdtempSync(join(tmpdir(), 'wm-local-migrations-'))
    const output = join(tempRoot, 'migrations')

    try {
      const result = spawnSync(
        process.execPath,
        [resolve(process.cwd(), 'scripts/prepare-local-migrations.mjs'), output],
        { cwd: process.cwd(), encoding: 'utf8' },
      )

      expect(result.status, result.stderr || result.stdout).toBe(0)

      const sourceFiles = readdirSync(resolve(process.cwd(), 'supabase/migrations'))
        .filter(name => name.endsWith('.sql'))
      const generatedFiles = readdirSync(output).filter(name => name.endsWith('.sql'))
      const manifest = JSON.parse(readFileSync(join(output, 'manifest.json'), 'utf8')) as {
        migrations: Array<{ version: string; source: string; generated: string; bytes: number; sha256: string }>
      }

      expect(manifest.migrations).toHaveLength(sourceFiles.length)
      expect(generatedFiles).toHaveLength(sourceFiles.length)
      expect(sourceFiles).toContain('02_master_data.sql')
      expect(sourceFiles).toContain('02_seed_egypt_geography.sql')
      expect(sourceFiles).toContain('02b_fixes.sql')

      const versions = manifest.migrations.map(entry => entry.version)
      expect(new Set(versions).size).toBe(versions.length)
      for (const entry of manifest.migrations) {
        expect(entry.version).toMatch(/^\d{14}$/)
        expect(entry.generated).toMatch(/^\d{14}_.+\.sql$/)
        expect(entry.sha256).toMatch(/^[a-f0-9]{64}$/)
        const original = readFileSync(resolve(process.cwd(), entry.source))
        const staged = readFileSync(join(output, entry.generated))
        expect(Buffer.compare(original, staged)).toBe(0)
        expect(entry.bytes).toBe(original.byteLength)
      }
    } finally {
      rmSync(tempRoot, { recursive: true, force: true })
    }
  })
})
