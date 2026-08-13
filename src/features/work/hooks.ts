import { useQuery } from '@tanstack/react-query'
import {
  getWorkChecklist,
  getWorkComments,
  getWorkItem,
  getWorkTimeline,
  listVisibleWorkItems,
  type WorkListFilters,
} from './api'
import { workKeys } from './query-keys'

export function useWorkItem(id: string | undefined) {
  return useQuery({
    queryKey: id ? workKeys.item(id) : ['work', 'item', 'missing'],
    queryFn: () => getWorkItem(id!),
    enabled: Boolean(id),
  })
}

export function useVisibleWorkItems(filters: WorkListFilters = {}) {
  return useQuery({
    queryKey: workKeys.list(filters as Record<string, unknown>),
    queryFn: () => listVisibleWorkItems(filters),
  })
}

export function useWorkTimeline(workItemId: string | undefined) {
  return useQuery({
    queryKey: workItemId ? workKeys.timeline(workItemId) : ['work', 'timeline', 'missing'],
    queryFn: () => getWorkTimeline(workItemId!),
    enabled: Boolean(workItemId),
  })
}

export function useWorkComments(workItemId: string | undefined) {
  return useQuery({
    queryKey: workItemId ? workKeys.comments(workItemId) : ['work', 'comments', 'missing'],
    queryFn: () => getWorkComments(workItemId!),
    enabled: Boolean(workItemId),
  })
}

export function useWorkChecklist(workItemId: string | undefined) {
  return useQuery({
    queryKey: workItemId ? workKeys.checklist(workItemId) : ['work', 'checklist', 'missing'],
    queryFn: () => getWorkChecklist(workItemId!),
    enabled: Boolean(workItemId),
  })
}
