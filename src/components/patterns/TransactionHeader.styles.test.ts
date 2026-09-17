import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const stylesPath = fileURLToPath(new URL('../../styles/design-system-v2-transaction.css', import.meta.url))
const styles = readFileSync(stylesPath, 'utf8')

describe('TransactionHeader overflow presentation contract', () => {
  it('keeps overflow actions hidden until the native details control is opened', () => {
    expect(styles).toMatch(/\.ds-transaction-header__overflow-actions\s*\{[^}]*display:\s*none;/s)
    expect(styles).toMatch(/\.ds-transaction-header__overflow\[open\]\s*>\s*\.ds-transaction-header__overflow-actions\s*\{[^}]*display:\s*grid;/s)
  })
})
