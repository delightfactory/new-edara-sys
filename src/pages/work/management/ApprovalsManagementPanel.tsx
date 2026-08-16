import { useMemo, useState, type FormEvent } from 'react'
import { Check, Loader2, Plus, Send, Trash2 } from 'lucide-react'
import { toast } from 'sonner'
import {
  useApprovalTemplates,
  useApprovalTemplateVersions,
  useCreateApprovalTemplate,
  useCreateApprovalTemplateVersion,
  useManagementUsers,
  usePublishApprovalTemplateVersion,
} from '@/features/work/management-hooks'
import type { WorkApprovalApproverDraft, WorkApprovalStageDraft } from '@/features/work/management-types'

const emptyApprover = (): WorkApprovalApproverDraft => ({ selector_kind: 'work_owner' })
const emptyStage = (index: number): WorkApprovalStageDraft => ({
  name: `مرحلة ${index + 1}`,
  mode: 'all',
  deadline_minutes: null,
  allow_changes_required: true,
  approvers: [emptyApprover()],
})

const SELECTORS: Array<{ value: WorkApprovalApproverDraft['selector_kind']; label: string }> = [
  { value: 'work_owner', label: 'المسؤول النهائي عن العمل' },
  { value: 'assignee', label: 'المكلف الحالي' },
  { value: 'department_manager', label: 'مدير الإدارة المالكة' },
  { value: 'branch_manager', label: 'مدير الفرع' },
  { value: 'user', label: 'مستخدم محدد' },
]

export default function ApprovalsManagementPanel() {
  const templates = useApprovalTemplates()
  const versions = useApprovalTemplateVersions()
  const users = useManagementUsers('')
  const createTemplate = useCreateApprovalTemplate()
  const createVersion = useCreateApprovalTemplateVersion()
  const publishVersion = usePublishApprovalTemplateVersion()

  const [showBuilder, setShowBuilder] = useState(false)
  const [templateId, setTemplateId] = useState('')
  const [code, setCode] = useState('')
  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [publish, setPublish] = useState(false)
  const [stages, setStages] = useState<WorkApprovalStageDraft[]>([emptyStage(0)])

  const versionsByTemplate = useMemo(() => {
    const map = new Map<string, typeof versions.data>()
    for (const version of versions.data ?? []) {
      const current = map.get(version.template_id) ?? []
      map.set(version.template_id, [...current, version])
    }
    return map
  }, [versions.data])

  const reset = () => {
    setTemplateId('')
    setCode('')
    setName('')
    setDescription('')
    setPublish(false)
    setStages([emptyStage(0)])
    setShowBuilder(false)
  }

  const patchStage = (index: number, patch: Partial<WorkApprovalStageDraft>) => {
    setStages(previous => previous.map((stage, current) => current === index ? { ...stage, ...patch } : stage))
  }

  const patchApprover = (stageIndex: number, approverIndex: number, patch: Partial<WorkApprovalApproverDraft>) => {
    setStages(previous => previous.map((stage, currentStage) => {
      if (currentStage !== stageIndex) return stage
      return {
        ...stage,
        approvers: stage.approvers.map((approver, currentApprover) => currentApprover === approverIndex ? { ...approver, ...patch } : approver),
      }
    }))
  }

  const addApprover = (stageIndex: number) => {
    setStages(previous => previous.map((stage, current) => current === stageIndex ? { ...stage, approvers: [...stage.approvers, emptyApprover()] } : stage))
  }

  const removeApprover = (stageIndex: number, approverIndex: number) => {
    setStages(previous => previous.map((stage, current) => current === stageIndex ? { ...stage, approvers: stage.approvers.filter((_, index) => index !== approverIndex) } : stage))
  }

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    if (!templateId && (!code.trim() || !name.trim())) {
      toast.error('الكود والاسم مطلوبان للنموذج الجديد')
      return
    }
    if (stages.length === 0 || stages.some(stage => !stage.name.trim() || stage.approvers.length === 0)) {
      toast.error('كل مرحلة تحتاج اسمًا ومعتمدًا واحدًا على الأقل')
      return
    }
    const invalidUser = stages.some(stage => stage.approvers.some(approver => approver.selector_kind === 'user' && !approver.user_id))
    if (invalidUser) {
      toast.error('اختر المستخدم في المعتمدات المحددة بالاسم')
      return
    }

    const definition = {
      metadata: { authored_from: 'work_management_ui' },
      stages: stages.map((stage, stageIndex) => ({
        ...stage,
        deadline_minutes: stage.deadline_minutes || undefined,
        approvers: stage.approvers.map((approver, approverIndex) => ({
          ...approver,
          user_id: approver.selector_kind === 'user' ? approver.user_id : undefined,
          sort_order: approverIndex,
        })),
        sort_order: stageIndex,
      })),
    }

    try {
      if (templateId) {
        await createVersion.mutateAsync({ templateId, definition, publish })
        toast.success(publish ? 'تم إنشاء ونشر نسخة اعتماد جديدة' : 'تم إنشاء نسخة اعتماد مسودة')
      } else {
        await createTemplate.mutateAsync({ code, name, description: description || null, definition, publish })
        toast.success(publish ? 'تم إنشاء ونشر نموذج الاعتماد' : 'تم إنشاء نموذج الاعتماد كمسودة')
      }
      reset()
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'تعذر حفظ نموذج الاعتماد')
    }
  }

  const publishDraft = async (versionId: string) => {
    try {
      await publishVersion.mutateAsync(versionId)
      toast.success('تم نشر نسخة الاعتماد')
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'تعذر نشر النسخة')
    }
  }

  if (templates.isLoading || versions.isLoading) {
    return <div className="work-management-loading"><Loader2 className="animate-spin" /> جاري تحميل قوالب الاعتماد…</div>
  }
  if (templates.error || versions.error) {
    return <div className="work-management-error"><p>تعذر تحميل قوالب الاعتماد.</p></div>
  }

  return (
    <section className="work-management-panel" aria-labelledby="approval-management-title">
      <div className="work-management-panel-header">
        <div>
          <h2 id="approval-management-title">قوالب الاعتماد</h2>
          <p className="page-subtitle">صمّم مسار القرار كمراحل واضحة، وانشر نسخة ثابتة لا تتغير بعد استخدامها.</p>
        </div>
        <button type="button" className="btn btn-primary" onClick={() => setShowBuilder(value => !value)}><Plus size={16} /> نموذج أو نسخة جديدة</button>
      </div>

      {showBuilder && (
        <div className="work-management-section">
          <div className="work-management-section-heading"><div><h3>Approval Stage Builder</h3><span className="form-hint">اختر نموذجًا قائمًا لإنشاء Version جديدة، أو اتركه فارغًا لنموذج جديد.</span></div></div>
          <form className="work-management-form" onSubmit={submit}>
            <div className="form-group is-wide">
              <label className="form-label" htmlFor="approval-existing">نموذج قائم</label>
              <select id="approval-existing" className="form-input" value={templateId} onChange={event => setTemplateId(event.target.value)}>
                <option value="">نموذج جديد</option>
                {(templates.data ?? []).map(template => <option key={template.id} value={template.id}>{template.name} — {template.code}</option>)}
              </select>
            </div>
            {!templateId && <>
              <div className="form-group"><label className="form-label required" htmlFor="approval-code">الكود</label><input id="approval-code" dir="ltr" className="form-input" value={code} onChange={event => setCode(event.target.value)} /></div>
              <div className="form-group"><label className="form-label required" htmlFor="approval-name">الاسم</label><input id="approval-name" className="form-input" value={name} onChange={event => setName(event.target.value)} /></div>
              <div className="form-group is-wide"><label className="form-label" htmlFor="approval-description">الوصف</label><textarea id="approval-description" className="form-input" rows={2} value={description} onChange={event => setDescription(event.target.value)} /></div>
            </>}

            <div className="form-group is-wide">
              <div className="work-management-section-heading"><div><label className="form-label">مراحل الاعتماد</label><span className="form-hint">المراحل تُنفذ بالترتيب. داخل المرحلة يمكن طلب موافقة الجميع أو أي معتمد.</span></div><button type="button" className="btn btn-ghost btn-sm" onClick={() => setStages(previous => [...previous, emptyStage(previous.length)])}><Plus size={15} /> مرحلة</button></div>
              <div className="work-management-builder-list">
                {stages.map((stage, stageIndex) => (
                  <article className="work-management-builder-item" key={stageIndex}>
                    <div className="work-management-builder-item-head"><div className="flex items-center gap-2"><span className="work-management-builder-index">{stageIndex + 1}</span><strong>{stage.name || 'مرحلة بدون اسم'}</strong></div><button type="button" className="work-management-icon-button" aria-label={`حذف المرحلة ${stageIndex + 1}`} disabled={stages.length === 1} onClick={() => setStages(previous => previous.filter((_, index) => index !== stageIndex))}><Trash2 size={16} /></button></div>
                    <div className="work-management-inline-fields">
                      <input className="form-input is-wide" aria-label={`اسم المرحلة ${stageIndex + 1}`} value={stage.name} onChange={event => patchStage(stageIndex, { name: event.target.value })} />
                      <select className="form-input" aria-label={`طريقة قرار المرحلة ${stageIndex + 1}`} value={stage.mode} onChange={event => patchStage(stageIndex, { mode: event.target.value as 'all' | 'any' })}><option value="all">موافقة الجميع</option><option value="any">موافقة أي معتمد</option></select>
                      <input className="form-input" type="number" min={1} aria-label={`مهلة المرحلة ${stageIndex + 1}`} value={stage.deadline_minutes ?? ''} onChange={event => patchStage(stageIndex, { deadline_minutes: event.target.value ? Number(event.target.value) : null })} placeholder="مهلة بالدقائق" />
                      <label className="perm-checkbox-label is-wide"><input type="checkbox" checked={stage.allow_changes_required} onChange={event => patchStage(stageIndex, { allow_changes_required: event.target.checked })} /> يسمح بطلب تعديلات</label>
                    </div>

                    <div style={{ marginTop: 'var(--space-3)' }}>
                      <div className="work-management-section-heading"><strong style={{ fontSize: 13 }}>المعتمدون</strong><button type="button" className="btn btn-ghost btn-sm" onClick={() => addApprover(stageIndex)}><Plus size={14} /> معتمد</button></div>
                      <div className="work-management-builder-list">
                        {stage.approvers.map((approver, approverIndex) => (
                          <div className="work-management-inline-fields" key={approverIndex}>
                            <select className="form-input is-wide" aria-label={`مصدر المعتمد ${approverIndex + 1}`} value={approver.selector_kind} onChange={event => patchApprover(stageIndex, approverIndex, { selector_kind: event.target.value as WorkApprovalApproverDraft['selector_kind'], user_id: undefined })}>{SELECTORS.map(selector => <option key={selector.value} value={selector.value}>{selector.label}</option>)}</select>
                            {approver.selector_kind === 'user' && <select className="form-input is-wide" aria-label={`المستخدم المعتمد ${approverIndex + 1}`} value={approver.user_id ?? ''} onChange={event => patchApprover(stageIndex, approverIndex, { user_id: event.target.value })}><option value="">اختر المستخدم</option>{(users.data ?? []).map(user => <option key={user.user_id} value={user.user_id}>{user.full_name}</option>)}</select>}
                            <button type="button" className="work-management-icon-button" aria-label="حذف المعتمد" disabled={stage.approvers.length === 1} onClick={() => removeApprover(stageIndex, approverIndex)}><Trash2 size={15} /></button>
                          </div>
                        ))}
                      </div>
                    </div>
                  </article>
                ))}
              </div>
            </div>

            <div className="form-group is-wide"><label className="perm-checkbox-label"><input type="checkbox" checked={publish} onChange={event => setPublish(event.target.checked)} /> نشر النسخة فور الحفظ</label><span className="form-hint">النسخة المنشورة تصبح immutable؛ أي تعديل لاحق ينشئ Version جديدة.</span></div>
            <div className="work-management-form-actions"><button type="button" className="btn btn-secondary" onClick={reset}>إلغاء</button><button type="submit" className="btn btn-primary" disabled={createTemplate.isPending || createVersion.isPending}>{(createTemplate.isPending || createVersion.isPending) ? <Loader2 size={16} className="animate-spin" /> : <Check size={16} />} حفظ</button></div>
          </form>
        </div>
      )}

      <div className="work-management-section">
        <div className="work-management-section-heading"><div><h3>النماذج الحالية</h3><span className="form-hint">{templates.data?.length ?? 0} نموذج</span></div></div>
        {(templates.data?.length ?? 0) === 0 ? <div className="work-management-empty"><h3>لا توجد قوالب اعتماد</h3><p>ابدأ بقالب واضح للحالات التي تحتاج قرارًا رسميًا.</p></div> : <div className="work-management-grid">{templates.data?.map(template => {
          const templateVersions = versionsByTemplate.get(template.id) ?? []
          const latest = [...templateVersions].sort((a, b) => b.version_number - a.version_number)[0]
          return <article className="work-management-card" key={template.id}><div className="work-management-card-head"><div><div className="work-management-card-title">{template.name}</div><div className="work-management-card-subtitle" dir="ltr">{template.code}</div></div><span className={`work-management-pill ${template.current_published_version_id ? 'is-good' : 'is-warning'}`}>{template.current_published_version_id ? 'منشور' : 'غير منشور'}</span></div><div className="work-management-meta"><span className="work-management-pill">{templateVersions.length} نسخة</span>{latest && <span className="work-management-pill">v{latest.version_number} — {latest.status}</span>}</div>{latest?.status === 'draft' && <div className="work-management-actions"><button type="button" className="btn btn-ghost btn-sm" disabled={publishVersion.isPending} onClick={() => publishDraft(latest.id)}><Send size={14} /> نشر v{latest.version_number}</button></div>}</article>
        })}</div>}
      </div>
    </section>
  )
}
