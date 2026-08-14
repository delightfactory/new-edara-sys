import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  createApprovalTemplate,
  createApprovalTemplateVersion,
  createQueue,
  createRecurrence,
  createRequestType,
  createWorkflowTemplate,
  createWorkflowTemplateVersion,
  getOperationalSettings,
  listApprovalTemplates,
  listApprovalTemplateVersions,
  listRecurrenceDefinitions,
  listWorkQueueMembers,
  listWorkQueues,
  listWorkRequestTypes,
  listWorkflowTemplates,
  listWorkflowTemplateVersions,
  publishApprovalTemplateVersion,
  publishWorkflowTemplateVersion,
  setQueueMember,
  setRecurrenceState,
  updateOperationalSettings,
  updateQueue,
} from './management-api'

const managementKeys = {
  all: ['work', 'management'] as const,
  queues: ['work', 'management', 'queues'] as const,
  queueMembers: ['work', 'management', 'queue-members'] as const,
  requestTypes: ['work', 'management', 'request-types'] as const,
  approvalTemplates: ['work', 'management', 'approval-templates'] as const,
  approvalVersions: ['work', 'management', 'approval-versions'] as const,
  workflowTemplates: ['work', 'management', 'workflow-templates'] as const,
  workflowVersions: ['work', 'management', 'workflow-versions'] as const,
  recurrence: ['work', 'management', 'recurrence'] as const,
  policies: ['work', 'management', 'policies'] as const,
}

function useInvalidateManagement() {
  const client = useQueryClient()
  return () => client.invalidateQueries({ queryKey: managementKeys.all })
}

export function useWorkQueues(enabled = true) {
  return useQuery({ queryKey: managementKeys.queues, queryFn: listWorkQueues, enabled })
}

export function useWorkQueueMembers(enabled = true) {
  return useQuery({ queryKey: managementKeys.queueMembers, queryFn: listWorkQueueMembers, enabled })
}

export function useWorkRequestTypes(enabled = true) {
  return useQuery({ queryKey: managementKeys.requestTypes, queryFn: listWorkRequestTypes, enabled })
}

export function useApprovalTemplates(enabled = true) {
  return useQuery({ queryKey: managementKeys.approvalTemplates, queryFn: listApprovalTemplates, enabled })
}

export function useApprovalTemplateVersions(enabled = true) {
  return useQuery({ queryKey: managementKeys.approvalVersions, queryFn: listApprovalTemplateVersions, enabled })
}

export function useWorkflowTemplates(enabled = true) {
  return useQuery({ queryKey: managementKeys.workflowTemplates, queryFn: listWorkflowTemplates, enabled })
}

export function useWorkflowTemplateVersions(enabled = true) {
  return useQuery({ queryKey: managementKeys.workflowVersions, queryFn: listWorkflowTemplateVersions, enabled })
}

export function useRecurrenceDefinitions(enabled = true) {
  return useQuery({ queryKey: managementKeys.recurrence, queryFn: listRecurrenceDefinitions, enabled })
}

export function useOperationalSettings(enabled = true) {
  return useQuery({ queryKey: managementKeys.policies, queryFn: getOperationalSettings, enabled })
}

function managementMutation<TVariables>(mutationFn: (variables: TVariables) => Promise<unknown>) {
  return function useManagementMutation() {
    const invalidate = useInvalidateManagement()
    return useMutation({ mutationFn, onSuccess: invalidate })
  }
}

export const useCreateQueue = managementMutation(createQueue)
export const useUpdateQueue = managementMutation(updateQueue)
export const useSetQueueMember = managementMutation(setQueueMember)
export const useCreateRequestType = managementMutation(createRequestType)
export const useCreateApprovalTemplate = managementMutation(createApprovalTemplate)
export const useCreateApprovalTemplateVersion = managementMutation(
  (input: { templateId: string; definition: Parameters<typeof createApprovalTemplateVersion>[1]; publish?: boolean }) =>
    createApprovalTemplateVersion(input.templateId, input.definition, input.publish),
)
export const usePublishApprovalTemplateVersion = managementMutation(
  (versionId: string) => publishApprovalTemplateVersion(versionId),
)
export const useCreateWorkflowTemplate = managementMutation(createWorkflowTemplate)
export const useCreateWorkflowTemplateVersion = managementMutation(
  (input: { templateId: string; definition: Parameters<typeof createWorkflowTemplateVersion>[1]; publish?: boolean }) =>
    createWorkflowTemplateVersion(input.templateId, input.definition, input.publish),
)
export const usePublishWorkflowTemplateVersion = managementMutation(
  (versionId: string) => publishWorkflowTemplateVersion(versionId),
)
export const useCreateRecurrence = managementMutation(createRecurrence)
export const useSetRecurrenceState = managementMutation(
  (input: { definitionId: string; expectedVersion: number; action: 'pause' | 'resume' | 'stop' }) =>
    setRecurrenceState(input.definitionId, input.expectedVersion, input.action),
)
export const useUpdateOperationalSettings = managementMutation(updateOperationalSettings)
