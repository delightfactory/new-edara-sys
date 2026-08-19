import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const { rpc } = vi.hoisted(() => ({ rpc: vi.fn() }))

vi.mock('@/lib/supabase/client', () => ({
  supabase: { rpc },
}))

import {
  getAiOperationsCaseDetail,
  getAiOperationsConsole,
  AiOperationsContractError,
  AiOperationsUnavailableError,
} from '@/features/ai-operations/service'

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

  it('loads causal case evidence lazily in preview without touching Supabase', async () => {
    const detail = await getAiOperationsCaseDetail('preview-case-001', { mode: 'preview' })

    expect(rpc).not.toHaveBeenCalled()
    expect(detail.decision_review.decision_type).toBe('MONITOR')
    expect(detail.responsibility_evidence.some(item => item.evidence_type === 'explicit_credit_override' && item.strength === 'direct')).toBe(true)
    expect(detail.responsibility_evidence.some(item => item.evidence_type === 'current_customer_assignment' && item.strength === 'supporting')).toBe(true)
    expect(detail.decision_review.why_this_owner).toContain('صاحب قرار الاستثناء الائتماني')
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

  it('keeps the future case-detail RPC explicit and bounded', async () => {
    rpc.mockResolvedValueOnce({
      data: null,
      error: { code: 'PGRST202', message: 'Could not find the function public.ai_ops_get_case_detail' },
    })

    await expect(getAiOperationsCaseDetail('case-123', { mode: 'rpc' })).rejects.toBeInstanceOf(AiOperationsUnavailableError)
    expect(rpc).toHaveBeenCalledWith('ai_ops_get_case_detail', { p_case_id: 'case-123' })
  })

  it('fails closed when a future console RPC violates the approved payload contract', async () => {
    rpc.mockResolvedValueOnce({
      data: { mode: 'rpc', integration_state: 'ready', generated_at: 'badly-incomplete' },
      error: null,
    })

    await expect(getAiOperationsConsole({ mode: 'rpc' })).rejects.toBeInstanceOf(AiOperationsContractError)
  })

  it('fails closed when a future case-detail RPC returns out-of-range confidence', async () => {
    rpc.mockResolvedValueOnce({
      data: {
        case_id: 'case-123',
        case_key: 'receivables:overdue_invoice:case-123',
        business_date: '2026-08-16',
        facts: [],
        responsibility_evidence: [],
        existing_work: [],
        relevant_context_ids: [],
        decision_review: {
          decision_type: 'MONITOR',
          concise_rationale: 'test',
          why_this_owner: null,
          why_now: null,
          confidence: 1.5,
          requires_human_review: false,
        },
      },
      error: null,
    })

    await expect(getAiOperationsCaseDetail('case-123', { mode: 'rpc' })).rejects.toBeInstanceOf(AiOperationsContractError)
  })

  it('requires an explicit preview feature flag and defaults the data adapter to preview', () => {
    expect(features).toContain("VITE_AI_OPERATIONS_PREVIEW === 'true'")
    expect(features).toContain("VITE_AI_OPERATIONS_DATA_MODE === 'rpc' ? 'rpc' : 'preview'")
    expect(envExample).toContain('VITE_AI_OPERATIONS_PREVIEW=false')
    expect(envExample).toContain('VITE_AI_OPERATIONS_DATA_MODE=preview')
  })

  it('surfaces the management console only in explicit preview or live RPC mode', () => {
    expect(managementPage).toContain('AI_OPERATIONS_PREVIEW')
    expect(managementPage).toContain('AI_OPERATIONS_DATA_MODE')
    expect(managementPage).toContain("id: 'ai-operations' as const")
    expect(managementPage).toMatch(/const\s+aiOperationsAvailable\s*=\s*AI_OPERATIONS_PREVIEW\s*\|\|\s*AI_OPERATIONS_DATA_MODE\s*===\s*'rpc'/s)
    expect(managementPage).toMatch(/const\s+definitions\s*=\s*aiOperationsAvailable\s*\?\s*\[\.\.\.TAB_DEFINITIONS,\s*AI_OPERATIONS_TAB\]\s*:\s*TAB_DEFINITIONS/s)
    expect(managementPage).toMatch(/activeTab\s*===\s*'ai-operations'\s*&&\s*aiOperationsAvailable\s*&&\s*<AiOperationsManagementPanel\s*\/>/s)
  })

  it('labels sample data clearly and documents that no database migration is applied', () => {
    expect(consolePanel).toContain('Preview آمن — بدون اتصال بقاعدة AI Operations')
    expect(consolePanel).toContain('بيانات مراجعة ثابتة')
    expect(consolePanel).toContain('لا يتم قراءة أو كتابة أي بيانات تشغيلية.')
    expect(consolePanel).toContain('Preview لا يستدعي Supabase AI RPCs')
    expect(consolePanel).toContain('أدلة المسؤولية — لا يوجد Routing جامد')
  })
})