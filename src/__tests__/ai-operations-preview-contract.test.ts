import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const { rpc } = vi.hoisted(() => ({ rpc: vi.fn() }))

vi.mock('@/lib/supabase/client', () => ({
  supabase: { rpc },
}))

import { getAiOperationsConsole, AiOperationsUnavailableError } from '@/features/ai-operations/service'

const features = readFileSync(resolve(process.cwd(), 'src/lib/config/features.ts'), 'utf8')
const envExample = readFileSync(resolve(process.cwd(), '.env.example'), 'utf8')
const managementPage = readFileSync(
  resolve(process.cwd(), 'src/pages/work/management/WorkManagementPage.tsx'),
  'utf8',
)
const consolePanel = readFileSync(
  resolve(process.cwd(), 'src/pages/work/management/AiOperationsManagementPanel.tsx'),
  'utf8',
)

describe('AI Operations preview safety contract', () => {
  beforeEach(() => rpc.mockReset())

  it('returns deterministic preview data without touching Supabase', async () => {
    const snapshot = await getAiOperationsConsole({ mode: 'preview' })

    expect(rpc).not.toHaveBeenCalled()
    expect(snapshot.mode).toBe('preview')
    expect(snapshot.integration_state).toBe('preview_only')
    expect(snapshot.settings.planner_enabled).toBe(false)
    expect(snapshot.settings.shadow_mode).toBe(true)
    expect(snapshot.settings.auto_commit_enabled).toBe(false)
    expect(snapshot.attention.length).toBeGreaterThan(0)
  })

  it('keeps preview fixtures isolated per call', async () => {
    const first = await getAiOperationsConsole({ mode: 'preview' })
    const second = await getAiOperationsConsole({ mode: 'preview' })

    first.settings.planner_enabled = true
    first.attention.splice(0, 1)

    expect(second.settings.planner_enabled).toBe(false)
    expect(second.attention.length).toBeGreaterThan(first.attention.length)
  })

  it('turns a missing future RPC into an explicit not-ready state', async () => {
    rpc.mockResolvedValueOnce({
      data: null,
      error: { code: 'PGRST202', message: 'Could not find the function public.ai_ops_get_console_snapshot' },
    })

    await expect(getAiOperationsConsole({ mode: 'rpc' })).rejects.toBeInstanceOf(AiOperationsUnavailableError)
    expect(rpc).toHaveBeenCalledWith('ai_ops_get_console_snapshot')
  })

  it('requires an explicit preview feature flag and defaults the data adapter to preview', () => {
    expect(features).toContain("VITE_AI_OPERATIONS_PREVIEW === 'true'")
    expect(features).toContain("VITE_AI_OPERATIONS_DATA_MODE === 'rpc' ? 'rpc' : 'preview'")
    expect(envExample).toContain('VITE_AI_OPERATIONS_PREVIEW=false')
    expect(envExample).toContain('VITE_AI_OPERATIONS_DATA_MODE=preview')
  })

  it('does not surface the management tab unless the preview flag is enabled', () => {
    expect(managementPage).toContain('AI_OPERATIONS_PREVIEW')
    expect(managementPage).toContain("id: 'ai-operations' as const")
    expect(managementPage).toContain('AI_OPERATIONS_PREVIEW ?')
    expect(managementPage).toContain("activeTab === 'ai-operations' && AI_OPERATIONS_PREVIEW")
  })

  it('labels sample data clearly and documents that no database migration is applied', () => {
    expect(consolePanel).toContain('Preview آمن — بدون اتصال بقاعدة AI Operations')
    expect(consolePanel).toContain('بيانات مراجعة ثابتة')
    expect(consolePanel).toContain('لا Migration مطبقة على الإنتاج')
    expect(consolePanel).toContain('Preview لا يستدعي Supabase AI RPCs')
  })
})
