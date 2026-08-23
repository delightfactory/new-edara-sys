import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const page = readFileSync(resolve(process.cwd(), 'src/pages/work/management/WorkManagementPage.tsx'), 'utf8')

describe('AI Operations management console availability', () => {
  it('surfaces the management tab in either safe preview or live RPC mode', () => {
    expect(page).toContain('AI_OPERATIONS_DATA_MODE, AI_OPERATIONS_PREVIEW')
    expect(page).toContain("AI_OPERATIONS_PREVIEW || AI_OPERATIONS_DATA_MODE === 'rpc'")
    expect(page).toContain('aiOperationsAvailable\n      ? [...TAB_DEFINITIONS, AI_OPERATIONS_TAB]')
  })

  it('uses the same availability gate when rendering the live panel', () => {
    expect(page).toContain("activeTab === 'ai-operations' && aiOperationsAvailable && <AiOperationsManagementPanel />")
    expect(page).not.toContain("activeTab === 'ai-operations' && AI_OPERATIONS_PREVIEW && <AiOperationsManagementPanel />")
  })
})
