import { useQuery } from '@tanstack/react-query'
import { AI_OPERATIONS_DATA_MODE } from '@/lib/config/features'
import { getAiOperationsConsole } from './service'

export const aiOperationsKeys = {
  all: ['ai-operations'] as const,
  console: (mode: 'preview' | 'rpc') => ['ai-operations', 'console', mode] as const,
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
