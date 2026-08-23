import { readdir, readFile, stat } from 'node:fs/promises'
import { extname, join, relative } from 'node:path'
import process from 'node:process'

const roots = [
  'src',
  'supabase/functions',
  'supabase/migrations',
  'supabase/maintenance',
  '.github/workflows',
]

const checkedExtensions = new Set([
  '.ts', '.tsx', '.js', '.jsx', '.cjs', '.mjs',
  '.sql', '.yml', '.yaml', '.toml',
])

const failures = []

async function walk(path) {
  let info
  try {
    info = await stat(path)
  } catch (error) {
    if (error?.code === 'ENOENT') return
    throw error
  }

  if (info.isDirectory()) {
    for (const entry of await readdir(path)) {
      if (entry === 'node_modules' || entry === 'dist' || entry === 'coverage') continue
      await walk(join(path, entry))
    }
    return
  }

  if (!checkedExtensions.has(extname(path))) return

  const bytes = await readFile(path)
  const text = bytes.toString('utf8')
  const displayPath = relative(process.cwd(), path).replaceAll('\\', '/')

  if (bytes.includes(0)) failures.push(`${displayPath}: contains a NUL byte`)
  if (text.includes('\r\n')) failures.push(`${displayPath}: contains CRLF; repository source is LF-normalized`)

  const lines = text.split('\n')
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index]
    if (
      line.startsWith('<<<<<<< ') ||
      line === '=======' ||
      line.startsWith('>>>>>>> ')
    ) {
      failures.push(`${displayPath}:${index + 1}: unresolved merge-conflict marker`)
    }
  }
}

for (const root of roots) await walk(root)

if (failures.length > 0) {
  console.error('Source hygiene check failed:')
  for (const failure of failures) console.error(`- ${failure}`)
  process.exit(1)
}

console.log('Source hygiene check passed.')
