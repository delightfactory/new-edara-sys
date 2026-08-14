#!/usr/bin/env node

import { createHash } from 'node:crypto'
import { mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { basename, resolve, sep } from 'node:path'

const root = process.cwd()
const sourceDir = resolve(root, 'supabase/migrations')
const outputDir = resolve(root, process.argv[2] ?? '.local-supabase/migrations')

if (outputDir === sourceDir || outputDir.startsWith(`${sourceDir}${sep}`)) {
  throw new Error('Refusing to stage local migrations inside supabase/migrations')
}

function parseOrder(filename) {
  const match = filename.match(/^(\d+)([a-z]*)(?:[_-]|$)/i)
  if (!match) return { number: null, suffix: '', filename }
  return {
    number: BigInt(match[1]),
    suffix: match[2].toLowerCase(),
    filename,
  }
}

function compareMigrations(leftName, rightName) {
  const left = parseOrder(leftName)
  const right = parseOrder(rightName)

  if (left.number === null && right.number !== null) return 1
  if (left.number !== null && right.number === null) return -1
  if (left.number !== null && right.number !== null) {
    if (left.number < right.number) return -1
    if (left.number > right.number) return 1
  }

  const suffixCompare = left.suffix.localeCompare(right.suffix, 'en')
  if (suffixCompare !== 0) return suffixCompare
  return left.filename.localeCompare(right.filename, 'en', { numeric: true })
}

function versionAt(index) {
  const date = new Date(Date.UTC(2000, 0, 1, 0, 0, index))
  const pad = value => String(value).padStart(2, '0')
  return [
    date.getUTCFullYear(),
    pad(date.getUTCMonth() + 1),
    pad(date.getUTCDate()),
    pad(date.getUTCHours()),
    pad(date.getUTCMinutes()),
    pad(date.getUTCSeconds()),
  ].join('')
}

function safeStem(filename) {
  return basename(filename, '.sql')
    .replace(/[^A-Za-z0-9_-]+/g, '_')
    .replace(/^_+|_+$/g, '') || 'migration'
}

const sourceFiles = readdirSync(sourceDir)
  .filter(name => name.toLowerCase().endsWith('.sql'))
  .sort(compareMigrations)

if (sourceFiles.length === 0) throw new Error('No SQL migrations found')

rmSync(outputDir, { recursive: true, force: true })
mkdirSync(outputDir, { recursive: true })

const manifest = sourceFiles.map((sourceName, index) => {
  const sourcePath = resolve(sourceDir, sourceName)
  const content = readFileSync(sourcePath)
  const version = versionAt(index)
  const generatedName = `${version}_${String(index + 1).padStart(4, '0')}_${safeStem(sourceName)}.sql`
  const generatedPath = resolve(outputDir, generatedName)
  writeFileSync(generatedPath, content)

  return {
    sequence: index + 1,
    version,
    source: `supabase/migrations/${sourceName}`,
    generated: generatedName,
    bytes: content.byteLength,
    sha256: createHash('sha256').update(content).digest('hex'),
  }
})

writeFileSync(
  resolve(outputDir, 'manifest.json'),
  `${JSON.stringify({ generated_at: new Date().toISOString(), source: 'supabase/migrations', migrations: manifest }, null, 2)}\n`,
  'utf8',
)

console.log(`Prepared ${manifest.length} immutable SQL copies in ${outputDir}`)
console.log(`Manifest: ${resolve(outputDir, 'manifest.json')}`)
console.log('Local acceptance only: never use this staging directory for production migration push.')
