import { useQuery } from '@tanstack/react-query'
import { getWorkAttachments, getWorkResponsibilitySnapshot } from './detail-api'

export function useWorkResponsibility(workItemId: string | undefined) {
  return useQuery({
    queryKey: workItemId ? ['work', 'item', workItemId, 'responsibility'] : ['work', 'item', 'missing', 'responsibility'],
    queryFn: () => getWorkResponsibilitySnapshot(workItemId!),
    enabled: Boolean(workItemId),
  })
}

export function useWorkAttachments(workItemId: string | undefined) {
  return useQuery({
    queryKey: workItemId ? ['work', 'item', workItemId, 'attachments'] : ['work', 'item', 'missing', 'attachments'],
    queryFn: () => getWorkAttachments(workItemId!),
    enabled: Boolean(workItemId),
  })
}
