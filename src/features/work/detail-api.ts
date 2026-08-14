import { supabase } from '@/lib/supabase/client'

export interface WorkActorLabel {
  user_id: string
  full_name: string
}

export interface WorkWaitingLabel {
  type: string | null
  user_id?: string
  label: string
}

export interface WorkResponsibilitySnapshot {
  ok: boolean
  work_item_id?: string
  code?: string
  owner: WorkActorLabel | null
  assignee: WorkActorLabel | null
  waiting_on: WorkWaitingLabel | null
}

export interface WorkAttachment {
  id: string
  work_item_id: string
  comment_id: string | null
  storage_bucket: 'work-attachments'
  storage_path: string
  original_filename: string
  mime_type: string
  size_bytes: number
  uploaded_by_user_id: string | null
  uploaded_at: string
  removed_at: string | null
  removed_by_user_id: string | null
  purpose: 'reference' | 'evidence' | 'output'
}

export async function getWorkResponsibilitySnapshot(workItemId: string): Promise<WorkResponsibilitySnapshot> {
  const { data, error } = await supabase.rpc('work_get_responsibility_snapshot', {
    p_work_item_id: workItemId,
  })
  if (error) throw error
  const snapshot = data as WorkResponsibilitySnapshot
  if (!snapshot?.ok) throw new Error(snapshot?.code === 'FORBIDDEN' ? 'غير مصرح بعرض المهمة' : 'تعذر تحميل المسؤوليات')
  return snapshot
}

export async function getWorkAttachments(workItemId: string): Promise<WorkAttachment[]> {
  const { data, error } = await supabase
    .from('work_attachments')
    .select('*')
    .eq('work_item_id', workItemId)
    .is('removed_at', null)
    .order('uploaded_at', { ascending: false })

  if (error) throw error
  return (data ?? []) as WorkAttachment[]
}

export async function downloadWorkAttachment(attachment: WorkAttachment): Promise<Blob> {
  const { data, error } = await supabase.storage
    .from(attachment.storage_bucket)
    .download(attachment.storage_path)
  if (error) throw error
  return data
}
