import { useQuery } from '@tanstack/react-query'
import { AI_OPERATIONS_DATA_MODE } from '@/lib/config/features'
import { getAiOperationsCaseDetail, getAiOperationsConsole } from './service'

export const aiOperationsKeys = {
  all: ['ai-operations'] as const,
  console: (mode: 'preview' | 'rpc') => ['ai-operations', 'console', mode] as const,
  caseDetail: (mode: 'preview' | 'rpc', caseId: string) => ['ai-operations', 'case-detail', mode, caseId] as const,
}

export function useAiOperationsConsole(enabled = true) {
  const mode = AI_OPERATIONS_DATA_MODE
  return useQuery({
    queryKey: aiOperationsKeys.console(mode),
    queryFn: () => getAiOperationsConsole({ mode }),
    enabled,
    staleTime: mode === 'preview' ? Infinity : 60_000,
    retry: mode === 'preview' ? false : 1,
  })
}

export function useAiOperationsCaseDetail(caseId: string | null, enabled = true) {
  const mode = AI_OPERATIONS_DATA_MODE
  const resolvedCaseId = caseId ?? ''
  return useQuery({
    queryKey: aiOperationsKeys.caseDetail(mode, resolvedCaseId),
    queryFn: () => getAiOperationsCaseDetail(resolvedCaseId, { mode }),
    enabled: enabled && Boolean(caseId),
    staleTime: mode === 'preview' ? Infinity : 60_000,
    retry: mode === 'preview' ? false : 1,
  })
}
