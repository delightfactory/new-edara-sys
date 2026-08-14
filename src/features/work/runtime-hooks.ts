import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { workKeys } from './query-keys'
import {
  acknowledgeWork,
  addWorkComment,
  completeWork,
  createTask,
  decideApproval,
  getMyActionInbox,
  getOperationalFlags,
  recordFirstView,
  removeWorkAttachment,
  resumeWork,
  reviewCompletion,
  setChecklistCompletion,
  setWorkWaiting,
  startWork,
  triageRequest,
  updateNextAction,
  uploadWorkAttachment,
} from './runtime-api'

function useInvalidateWork() {
  const queryClient = useQueryClient()
  return () => queryClient.invalidateQueries({ queryKey: workKeys.all })
}

export function useMyActionInbox(limit = 100) {
  return useQuery({
    queryKey: [...workKeys.myActionInbox(), limit],
    queryFn: () => getMyActionInbox(limit),
  })
}

export function useOperationalFlags(workItemIds: string[] = []) {
  const stableIds = [...workItemIds].sort()
  return useQuery({
    queryKey: ['work', 'operational-flags', stableIds],
    queryFn: () => getOperationalFlags(stableIds),
    enabled: stableIds.length > 0,
  })
}

export function useCreateTask() {
  const invalidate = useInvalidateWork()
  return useMutation({ mutationFn: createTask, onSuccess: invalidate })
}

export function useAcknowledgeWork() {
  const invalidate = useInvalidateWork()
  return useMutation({
    mutationFn: ({ workItemId, expectedVersion }: { workItemId: string; expectedVersion: number }) =>
      acknowledgeWork(workItemId, expectedVersion),
    onSuccess: invalidate,
  })
}

export function useStartWork() {
  const invalidate = useInvalidateWork()
  return useMutation({
    mutationFn: ({ workItemId, expectedVersion }: { workItemId: string; expectedVersion: number }) =>
      startWork(workItemId, expectedVersion),
    onSuccess: invalidate,
  })
}

export function useSetWorkWaiting() {
  const invalidate = useInvalidateWork()
  return useMutation({ mutationFn: setWorkWaiting, onSuccess: invalidate })
}

export function useResumeWork() {
  const invalidate = useInvalidateWork()
  return useMutation({
    mutationFn: (input: {
      workItemId: string
      expectedVersion: number
      nextActionText: string
      nextActionAt?: string | null
    }) => resumeWork(input.workItemId, input.expectedVersion, input.nextActionText, input.nextActionAt),
    onSuccess: invalidate,
  })
}

export function useUpdateNextAction() {
  const invalidate = useInvalidateWork()
  return useMutation({
    mutationFn: (input: {
      workItemId: string
      expectedVersion: number
      nextActionText: string
      nextActionAt?: string | null
    }) => updateNextAction(input.workItemId, input.expectedVersion, input.nextActionText, input.nextActionAt),
    onSuccess: invalidate,
  })
}

export function useAddWorkComment() {
  const invalidate = useInvalidateWork()
  return useMutation({ mutationFn: addWorkComment, onSuccess: invalidate })
}

export function useSetChecklistCompletion() {
  const invalidate = useInvalidateWork()
  return useMutation({
    mutationFn: (input: {
      workItemId: string
      checklistItemId: string
      expectedVersion: number
      completed: boolean
    }) => setChecklistCompletion(
      input.workItemId,
      input.checklistItemId,
      input.expectedVersion,
      input.completed,
    ),
    onSuccess: invalidate,
  })
}

export function useCompleteWork() {
  const invalidate = useInvalidateWork()
  return useMutation({
    mutationFn: (input: {
      workItemId: string
      expectedVersion: number
      completionSummary: string
      completionOutput?: Record<string, unknown>
    }) => completeWork(
      input.workItemId,
      input.expectedVersion,
      input.completionSummary,
      input.completionOutput,
    ),
    onSuccess: invalidate,
  })
}

export function useReviewCompletion() {
  const invalidate = useInvalidateWork()
  return useMutation({
    mutationFn: (input: {
      reviewId: string
      expectedVersion: number
      decision: 'approve' | 'changes_required'
      note?: string | null
    }) => reviewCompletion(input.reviewId, input.expectedVersion, input.decision, input.note),
    onSuccess: invalidate,
  })
}

export function useDecideApproval() {
  const invalidate = useInvalidateWork()
  return useMutation({ mutationFn: decideApproval, onSuccess: invalidate })
}

export function useTriageRequest() {
  const invalidate = useInvalidateWork()
  return useMutation({ mutationFn: triageRequest, onSuccess: invalidate })
}

export function useRecordFirstView() {
  const invalidate = useInvalidateWork()
  return useMutation({ mutationFn: recordFirstView, onSuccess: invalidate })
}

export function useUploadWorkAttachment() {
  const invalidate = useInvalidateWork()
  return useMutation({ mutationFn: uploadWorkAttachment, onSuccess: invalidate })
}

export function useRemoveWorkAttachment() {
  const invalidate = useInvalidateWork()
  return useMutation({ mutationFn: removeWorkAttachment, onSuccess: invalidate })
}
