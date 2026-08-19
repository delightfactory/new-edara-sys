import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { AI_OPERATIONS_DATA_MODE } from '@/lib/config/features'
import {
  commitAiOperationsDecision,
  createAiOperationsOperationalContext,
  getAiOperationsCaseDetail,
  getAiOperationsConsole,
  getAiOperationsDecisionReview,
  revokeAiOperationsOperationalContext,
  reviseAiOperationsDecision,
  reviewAiOperationsDecision,
  setAiOperationsCaseDisposition,
  type CreateAiOperationsContextInput,
  type ReviseAiOperationsDecisionInput,
} from './service'
import type { AiOpsHumanReviewState } from './types'

export const aiOperationsKeys = {
  all: ['ai-operations'] as const,
  console: (mode: 'preview' | 'rpc') => ['ai-operations', 'console', mode] as const,
  caseDetail: (mode: 'preview' | 'rpc', caseId: string) => ['ai-operations', 'case-detail', mode, caseId] as const,
  decisionReview: (mode: 'preview' | 'rpc', caseId: string) => ['ai-operations', 'decision-review', mode, caseId] as const,
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

export function useAiOperationsDecisionReview(caseId: string | null, enabled = true) {
  const mode = AI_OPERATIONS_DATA_MODE
  const resolvedCaseId = caseId ?? ''
  return useQuery({
    queryKey: aiOperationsKeys.decisionReview(mode, resolvedCaseId),
    queryFn: () => getAiOperationsDecisionReview(resolvedCaseId, { mode }),
    enabled: enabled && Boolean(caseId),
    staleTime: mode === 'preview' ? Infinity : 15_000,
    retry: mode === 'preview' ? false : 1,
  })
}

function invalidateAiOperations(queryClient: ReturnType<typeof useQueryClient>) {
  return queryClient.invalidateQueries({ queryKey: aiOperationsKeys.all })
}

export function useReviewAiOperationsDecision() {
  const queryClient = useQueryClient()
  const mode = AI_OPERATIONS_DATA_MODE
  return useMutation({
    mutationFn: ({
      decisionId,
      reviewState,
      reviewNote,
    }: {
      decisionId: string
      reviewState: AiOpsHumanReviewState
      reviewNote?: string | null
    }) => reviewAiOperationsDecision(decisionId, reviewState, reviewNote, { mode }),
    onSuccess: () => invalidateAiOperations(queryClient),
  })
}

export function useCommitAiOperationsDecision() {
  const queryClient = useQueryClient()
  const mode = AI_OPERATIONS_DATA_MODE
  return useMutation({
    mutationFn: ({ decisionId }: { decisionId: string }) => commitAiOperationsDecision(decisionId, { mode }),
    onSuccess: () => invalidateAiOperations(queryClient),
  })
}

export function useReviseAiOperationsDecision() {
  const queryClient = useQueryClient()
  const mode = AI_OPERATIONS_DATA_MODE
  return useMutation({
    mutationFn: (input: ReviseAiOperationsDecisionInput) => reviseAiOperationsDecision(input, { mode }),
    onSuccess: () => invalidateAiOperations(queryClient),
  })
}

export function useCreateAiOperationsContext() {
  const queryClient = useQueryClient()
  const mode = AI_OPERATIONS_DATA_MODE
  return useMutation({
    mutationFn: (input: CreateAiOperationsContextInput) => createAiOperationsOperationalContext(input, { mode }),
    onSuccess: () => invalidateAiOperations(queryClient),
  })
}

export function useRevokeAiOperationsContext() {
  const queryClient = useQueryClient()
  const mode = AI_OPERATIONS_DATA_MODE
  return useMutation({
    mutationFn: ({ contextId, note }: { contextId: string; note?: string | null }) =>
      revokeAiOperationsOperationalContext(contextId, note, { mode }),
    onSuccess: () => invalidateAiOperations(queryClient),
  })
}

export function useSetAiOperationsCaseDisposition() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({
      caseId,
      action,
      until,
      note,
    }: {
      caseId: string
      action: 'snooze' | 'dismiss'
      until: string | null
      note?: string | null
    }) => setAiOperationsCaseDisposition(caseId, action, until, note),
    onSuccess: () => invalidateAiOperations(queryClient),
  })
}
