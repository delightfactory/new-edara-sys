import { useEffect, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { CalendarPlus2, ShieldCheck } from 'lucide-react'
import { toast } from 'sonner'
import Button from '@/components/ui/Button'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import { useAuthStore } from '@/stores/auth-store'
import type { WorkItem } from '@/features/work/types'
import { listDueApprovalTemplates, requestWorkDueExtension } from '@/features/work/due-governance-api'

function toIso(localValue: string) {
  return localValue ? new Date(localValue).toISOString() : null
}

export default function WorkDueGovernance({ item }: { item: WorkItem }) {
  const queryClient = useQueryClient()
  const profile = useAuthStore(state => state.profile)
  const can = useAuthStore(state => state.can)
  const [open, setOpen] = useState(false)
  const [dueAt, setDueAt] = useState('')
  const [reason, setReason] = useState('')
  const [templateId, setTemplateId] = useState('')

  const terminal = item.status === 'done' || item.status === 'cancelled'
  const isDirectActor = !!profile?.id && [
    item.creator_user_id,
    item.requester_user_id,
    item.accountable_owner_user_id,
    item.current_assignee_user_id,
  ].includes(profile.id)
  const canUpdate = !terminal && (
    can('work.items.manage') ||
    can('work.items.manage_team') ||
    (can('work.items.update_own') && isDirectActor)
  )

  const templates = useQuery({
    queryKey: ['work', 'due-approval-templates'],
    queryFn: listDueApprovalTemplates,
    enabled: open,
  })

  useEffect(() => {
    if (open && !templateId && templates.data?.length === 1) setTemplateId(templates.data[0].id)
  }, [open, templateId, templates.data])

  const mutation = useMutation({
    mutationFn: requestWorkDueExtension,
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['work'] })
    },
  })

  if (!canUpdate || !item.due_at) return null

  const close = () => {
    setOpen(false)
    setDueAt('')
    setReason('')
    setTemplateId('')
  }

  const submit = async () => {
    const iso = toIso(dueAt)
    if (!iso) return toast.error('اختر الموعد الجديد')
    if (new Date(iso).getTime() <= new Date(item.due_at!).getTime()) {
      return toast.error('هذا المسار مخصص لتمديد الموعد فقط؛ تقديم الموعد يتم من إجراء تغيير الموعد')
    }
    if (!reason.trim()) return toast.error('سبب التمديد مطلوب')
    if (!templateId) return toast.error('اختر نموذج الاعتماد')

    try {
      await mutation.mutateAsync({
        workItemId: item.id,
        expectedVersion: item.state_version,
        newDueAt: iso,
        reason: reason.trim(),
        approvalTemplateId: templateId,
      })
      toast.success('تم إرسال طلب تمديد الموعد للاعتماد؛ الموعد الحالي لم يتغير بعد')
      close()
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'تعذر إرسال طلب تمديد الموعد')
    }
  }

  return (
    <>
      <section className="work-panel">
        <div className="work-panel-header">
          <div className="work-panel-title"><ShieldCheck size={18} /> حوكمة الموعد النهائي</div>
          <span className="work-section-note">التمديد لا يصبح نافذًا قبل الاعتماد</span>
        </div>
        <div className="work-panel-body">
          <div className="work-comment">
            <strong>الموعد الحالي: {new Date(item.due_at).toLocaleString('en-GB')}</strong>
            <div className="work-comment-meta">تقديم الموعد أو تعديله لوقت أقرب يتم مباشرة مع تسجيل السبب. أي تمديد إلى وقت لاحق يمر عبر Approval Engine.</div>
          </div>
          <div className="work-detail-actions" style={{ marginTop: 'var(--space-3)' }}>
            <Button size="sm" variant="secondary" icon={<CalendarPlus2 size={15} />} onClick={() => setOpen(true)}>طلب تمديد الموعد</Button>
          </div>
        </div>
      </section>

      <ResponsiveModal
        open={open}
        onClose={close}
        title="طلب تمديد الموعد"
        footer={<><Button variant="secondary" onClick={close}>إلغاء</Button><Button loading={mutation.isPending} disabled={!templateId || templates.isLoading} onClick={() => void submit()}>إرسال للاعتماد</Button></>}
      >
        <div className="work-form">
          <div className="work-field-hint">لن يتغير الموعد النهائي الآن. سيطبّق النظام الموعد الجديد تلقائيًا فقط إذا اكتمل نموذج الاعتماد بالموافقة.</div>
          <div className="work-field"><label>الموعد الحالي</label><input value={new Date(item.due_at).toLocaleString('en-GB')} disabled /></div>
          <div className="work-field"><label>الموعد المطلوب *</label><input type="datetime-local" value={dueAt} onChange={event => setDueAt(event.target.value)} /></div>
          <div className="work-field"><label>سبب التمديد *</label><textarea value={reason} onChange={event => setReason(event.target.value)} placeholder="اشرح سبب الحاجة إلى وقت إضافي" /></div>
          <div className="work-field">
            <label>نموذج الاعتماد *</label>
            <select value={templateId} onChange={event => setTemplateId(event.target.value)} disabled={templates.isLoading}>
              <option value="">اختر نموذج الاعتماد</option>
              {templates.data?.map(template => <option key={template.id} value={template.id}>{template.name}</option>)}
            </select>
            {templates.isLoading && <span className="work-field-hint">جارٍ تحميل النماذج المنشورة…</span>}
            {templates.error && <span className="work-field-hint">تعذر تحميل نماذج الاعتماد.</span>}
            {!templates.isLoading && !templates.error && templates.data?.length === 0 && <span className="work-field-hint">لا يوجد نموذج اعتماد منشور. يجب على مدير النظام نشر نموذج اعتماد أولًا.</span>}
          </div>
        </div>
      </ResponsiveModal>
    </>
  )
}
