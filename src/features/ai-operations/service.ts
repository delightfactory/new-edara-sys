import { AI_OPERATIONS_DATA_MODE } from '@/lib/config/features'
import { supabase } from '@/lib/supabase/client'
import { AI_OPERATIONS_PREVIEW_DATA } from './preview-data'
import type { AiOpsConsoleSnapshot, AiOpsDataMode } from './types'

export class AiOperationsUnavailableError extends Error {
  readonly code = 'AI_OPERATIONS_NOT_READY'

  constructor(message = 'طبقة AI Operations غير مفعلة بعد على قاعدة البيانات.') {
    super(message)
    this.name = 'AiOperationsUnavailableError'
  }
}

export interface AiOperationsServiceOptions {
  mode?: AiOpsDataMode
}

function clonePreview(): AiOpsConsoleSnapshot {
  return structuredClone(AI_OPERATIONS_PREVIEW_DATA)
}

async function loadConsoleFromRpc(): Promise<AiOpsConsoleSnapshot> {
  // This RPC intentionally does not exist in production yet. It will be added only
  // after the reviewed ai_ops migrations are explicitly approved and applied.
  const { data, error } = await supabase.rpc('ai_ops_get_console_snapshot')

  if (error) {
    if (error.code === 'PGRST202' || /Could not find the function/i.test(error.message ?? '')) {
      throw new AiOperationsUnavailableError()
    }
    throw error
  }

  if (!data || typeof data !== 'object') {
    throw new AiOperationsUnavailableError('لم تُرجع طبقة AI Operations Snapshot صالحة.')
  }

  return data as unknown as AiOpsConsoleSnapshot
}

export async function getAiOperationsConsole(
  options: AiOperationsServiceOptions = {},
): Promise<AiOpsConsoleSnapshot> {
  const mode = options.mode ?? AI_OPERATIONS_DATA_MODE

  if (mode === 'preview') {
    return clonePreview()
  }

  return loadConsoleFromRpc()
}
