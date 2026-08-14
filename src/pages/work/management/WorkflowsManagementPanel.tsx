import { useMemo, useState, type FormEvent } from 'react'
import { Check, Loader2, Plus, Send, Trash2 } from 'lucide-react'
import { toast } from 'sonner'
import {
  useApprovalTemplates,
  useCreateWorkflowTemplate,
  useCreateWorkflowTemplateVersion,
  useManagementUsers,
  usePublishWorkflowTemplateVersion,
  useWorkflowTemplates,
  useWorkflowTemplateVersions,
} from '@/features/work/management-hooks'
import type { WorkIntakeField, WorkWorkflowStepDraft } from '@/features/work/management-types'

interface StepEditor extends WorkWorkflowStepDraft {
  conditionMode: 'always' | 'input_eq' | 'step_output_exists' | 'step_output_eq'
  conditionSourceStep?: string
  conditionPath?: string
  conditionValue?: string
}

const emptyStep = (index: number): StepEditor => ({
  key: `step_${index + 1}`,
  name: `خطوة ${index + 1}`,
  kind: 'task',
  depends_on: index > 0 ? [`step_${index}`] : [],
  condition: { op: 'always' },
  output_schema: { version: 1, fields: [] },
  task: { expected_outcome: '', next_action_text: '' },
  conditionMode: 'always',
})

const emptyOutputField = (index: number): WorkIntakeField => ({ key: `output_${index + 1}`, label: '', type: 'string', required: true })

function compileCondition(step: StepEditor): Record<string, unknown> {
  const pathPart = step.conditionPath?.trim()
  if (step.conditionMode === 'input_eq' && pathPart) return { op: 'eq', path: `input.${pathPart}`, value: step.conditionValue ?? '' }
  if (step.conditionMode === 'step_output_exists' && step.conditionSourceStep && pathPart) return { op: 'exists', path: `steps.${step.conditionSourceStep}.output.${pathPart}` }
  if (step.conditionMode === 'step_output_eq' && step.conditionSourceStep && pathPart) return { op: 'eq', path: `steps.${step.conditionSourceStep}.output.${pathPart}`, value: step.conditionValue ?? '' }
  return { op: 'always' }
}

export default function WorkflowsManagementPanel() {
  const templates = useWorkflowTemplates()
  const versions = useWorkflowTemplateVersions()
  const approvalTemplates = useApprovalTemplates()
  const users = useManagementUsers('')
  const createTemplate = useCreateWorkflowTemplate()
  const createVersion = useCreateWorkflowTemplateVersion()
  const publishVersion = usePublishWorkflowTemplateVersion()

  const [showBuilder, setShowBuilder] = useState(false)
  const [templateId, setTemplateId] = useState('')
  const [code, setCode] = useState('')
  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [publish, setPublish] = useState(false)
  const [steps, setSteps] = useState<StepEditor[]>([emptyStep(0)])

  const publishedApprovals = useMemo(() => (approvalTemplates.data ?? []).filter(template => template.is_active && template.current_published_version_id), [approvalTemplates.data])
  const versionsByTemplate = useMemo(() => {
    const map = new Map<string, NonNullable<typeof versions.data>>()
    for (const version of versions.data ?? []) map.set(version.template_id, [...(map.get(version.template_id) ?? []), version])
    return map
  }, [versions.data])

  const reset = () => {
    setShowBuilder(false)
    setTemplateId('')
    setCode('')
    setName('')
    setDescription('')
    setPublish(false)
    setSteps([emptyStep(0)])
  }

  const patchStep = (index: number, patch: Partial<StepEditor>) => setSteps(previous => previous.map((step, current) => current === index ? { ...step, ...patch } : step))

  const setDependency = (stepIndex: number, predecessorKey: string, checked: boolean) => {
    setSteps(previous => previous.map((step, current) => current !== stepIndex ? step : {
      ...step,
      depends_on: checked ? Array.from(new Set([...step.depends_on, predecessorKey])) : step.depends_on.filter(key => key !== predecessorKey),
    }))
  }

  const updateOutputField = (stepIndex: number, fieldIndex: number, patch: Partial<WorkIntakeField>) => {
    setSteps(previous => previous.map((step, current) => current !== stepIndex ? step : {
      ...step,
      output_schema: { ...step.output_schema, fields: step.output_schema.fields.map((field, index) => index === fieldIndex ? { ...field, ...patch } : field) },
    }))
  }

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    if (!templateId && (!code.trim() || !name.trim())) { toast.error('الكود والاسم مطلوبان لمسار العمل الجديد'); return }
    if (steps.length === 0 || steps.some(step => !step.key.trim() || !step.name.trim())) { toast.error('كل خطوة تحتاج مفتاحًا واسمًا'); return }
    if (new Set(steps.map(step => step.key)).size !== steps.length) { toast.error('مفاتيح الخطوات يجب أن تكون فريدة'); return }
    if (steps.some(step => step.kind === 'task' && !step.task?.expected_outcome.trim())) { toast.error('كل خطوة مهمة تحتاج نتيجة متوقعة'); return }
    if (steps.some(step => step.kind === 'approval' && !step.approval_template_id)) { toast.error('اختر نموذج اعتماد لكل خطوة اعتماد'); return }
    if (steps.some(step => step.conditionMode !== 'always' && !step.conditionPath?.trim())) { toast.error('أكمل مسار بيانات شرط التشغيل'); return }

    const definition = {
      metadata: { authored_from: 'work_management_ui' },
      steps: steps.map(step => ({
        key: step.key,
        name: step.name,
        kind: step.kind,
        depends_on: step.depends_on,
        condition: compileCondition(step),
        output_schema: step.output_schema,
        task: step.kind === 'task' ? step.task : undefined,
        approval_template_id: step.kind === 'approval' ? step.approval_template_id : undefined,
      })),
    }

    try {
      if (templateId) {
        await createVersion.mutateAsync({ templateId, definition, publish })
        toast.success(publish ? 'تم إنشاء ونشر نسخة المسار' : 'تم إنشاء نسخة مسار مسودة')
      } else {
        await createTemplate.mutateAsync({ code, name, description: description || null, definition, publish })
        toast.success(publish ? 'تم إنشاء ونشر مسار العمل' : 'تم إنشاء مسار العمل كمسودة')
      }
      reset()
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'تعذر حفظ مسار العمل')
    }
  }

  const publishDraft = async (versionId: string) => {
    try { await publishVersion.mutateAsync(versionId); toast.success('تم نشر نسخة مسار العمل') }
    catch (error) { toast.error(error instanceof Error ? error.message : 'تعذر نشر النسخة') }
  }

  if (templates.isLoading || versions.isLoading || approvalTemplates.isLoading) return <div className="work-management-loading"><Loader2 className="animate-spin" /> جاري تحميل مسارات العمل…</div>
  if (templates.error || versions.error || approvalTemplates.error) return <div className="work-management-error"><p>تعذر تحميل مسارات العمل.</p></div>

  return (
    <section className="work-management-panel" aria-labelledby="workflow-management-title">
      <div className="work-management-panel-header">
        <div><h2 id="workflow-management-title">مسارات العمل</h2><p className="page-subtitle">حوّل الإجراءات المتكررة متعددة الخطوات إلى مسار Versioned قابل للتدقيق.</p></div>
        <button type="button" className="btn btn-primary" onClick={() => setShowBuilder(value => !value)}><Plus size={16} /> مسار أو نسخة جديدة</button>
      </div>

      {showBuilder && <div className="work-management-section">
        <div className="work-management-section-heading"><div><h3>Workflow Builder</h3><span className="form-hint">الواجهة تسمح بالاعتماد فقط على خطوات سابقة؛ الـbackend يعيد فحص الدورات والـDSL عند الحفظ والنشر.</span></div></div>
        <form className="work-management-form" onSubmit={submit}>
          <div className="form-group is-wide"><label className="form-label" htmlFor="workflow-existing">مسار قائم</label><select id="workflow-existing" className="form-input" value={templateId} onChange={event => setTemplateId(event.target.value)}><option value="">مسار جديد</option>{(templates.data ?? []).map(template => <option key={template.id} value={template.id}>{template.name} — {template.code}</option>)}</select></div>
          {!templateId && <><div className="form-group"><label className="form-label required" htmlFor="workflow-code">الكود</label><input id="workflow-code" dir="ltr" className="form-input" value={code} onChange={event => setCode(event.target.value.replace(/[^A-Za-z0-9._-]/g, '_'))} /></div><div className="form-group"><label className="form-label required" htmlFor="workflow-name">الاسم</label><input id="workflow-name" className="form-input" value={name} onChange={event => setName(event.target.value)} /></div><div className="form-group is-wide"><label className="form-label" htmlFor="workflow-description">الوصف</label><textarea id="workflow-description" className="form-input" rows={2} value={description} onChange={event => setDescription(event.target.value)} /></div></>}

          <div className="form-group is-wide">
            <div className="work-management-section-heading"><div><label className="form-label">الخطوات</label><span className="form-hint">المهمة تنتج عملاً، والاعتماد ينتج قرارًا. المخرجات المهيكلة متاحة للشروط والخطوات التالية.</span></div><button type="button" className="btn btn-ghost btn-sm" onClick={() => setSteps(previous => [...previous, emptyStep(previous.length)])}><Plus size={15} /> خطوة</button></div>
            <div className="work-management-builder-list">
              {steps.map((step, stepIndex) => {
                const previousSteps = steps.slice(0, stepIndex)
                return <article key={stepIndex} className="work-management-builder-item">
                  <div className="work-management-builder-item-head"><div className="flex items-center gap-2"><span className="work-management-builder-index">{stepIndex + 1}</span><strong>{step.name || 'خطوة بدون اسم'}</strong></div><button type="button" className="work-management-icon-button" aria-label={`حذف الخطوة ${stepIndex + 1}`} disabled={steps.length === 1} onClick={() => setSteps(previous => previous.filter((_, index) => index !== stepIndex))}><Trash2 size={16} /></button></div>
                  <div className="work-management-inline-fields">
                    <input className="form-input" dir="ltr" aria-label={`مفتاح الخطوة ${stepIndex + 1}`} value={step.key} onChange={event => patchStep(stepIndex, { key: event.target.value.replace(/[^A-Za-z0-9_-]/g, '_') })} />
                    <input className="form-input is-wide" aria-label={`اسم الخطوة ${stepIndex + 1}`} value={step.name} onChange={event => patchStep(stepIndex, { name: event.target.value })} />
                    <select className="form-input" aria-label={`نوع الخطوة ${stepIndex + 1}`} value={step.kind} onChange={event => patchStep(stepIndex, { kind: event.target.value as 'task' | 'approval' })}><option value="task">مهمة</option><option value="approval">اعتماد</option></select>
                  </div>

                  {previousSteps.length > 0 && <div style={{ marginTop: 'var(--space-3)' }}><label className="form-label">تعتمد على</label><div className="work-management-meta">{previousSteps.map(previousStep => <label key={previousStep.key} className="perm-checkbox-label"><input type="checkbox" checked={step.depends_on.includes(previousStep.key)} onChange={event => setDependency(stepIndex, previousStep.key, event.target.checked)} /> {previousStep.name}</label>)}</div></div>}

                  <div style={{ marginTop: 'var(--space-3)' }}><label className="form-label">شرط التشغيل</label><div className="work-management-inline-fields">
                    <select className="form-input is-wide" value={step.conditionMode} aria-label={`شرط تشغيل الخطوة ${stepIndex + 1}`} onChange={event => patchStep(stepIndex, { conditionMode: event.target.value as StepEditor['conditionMode'], conditionSourceStep: undefined, conditionPath: '', conditionValue: '' })}><option value="always">دائمًا</option><option value="input_eq">قيمة Input تساوي</option><option value="step_output_exists">مخرج خطوة موجود</option><option value="step_output_eq">مخرج خطوة يساوي</option></select>
                    {(step.conditionMode === 'step_output_exists' || step.conditionMode === 'step_output_eq') && <select className="form-input" value={step.conditionSourceStep ?? ''} onChange={event => patchStep(stepIndex, { conditionSourceStep: event.target.value })}><option value="">اختر خطوة سابقة</option>{previousSteps.map(previousStep => <option key={previousStep.key} value={previousStep.key}>{previousStep.name}</option>)}</select>}
                    {step.conditionMode !== 'always' && <input className="form-input" dir="ltr" value={step.conditionPath ?? ''} onChange={event => patchStep(stepIndex, { conditionPath: event.target.value })} placeholder={step.conditionMode === 'input_eq' ? 'customer_type' : 'approved'} />}
                    {(step.conditionMode === 'input_eq' || step.conditionMode === 'step_output_eq') && <input className="form-input" value={step.conditionValue ?? ''} onChange={event => patchStep(stepIndex, { conditionValue: event.target.value })} placeholder="القيمة" />}
                  </div></div>

                  {step.kind === 'task' ? <div style={{ marginTop: 'var(--space-3)' }}><label className="form-label">إعداد المهمة</label><div className="work-management-inline-fields"><input className="form-input is-wide" value={step.task?.expected_outcome ?? ''} onChange={event => patchStep(stepIndex, { task: { ...(step.task ?? { expected_outcome: '' }), expected_outcome: event.target.value } })} placeholder="النتيجة المتوقعة *" /><input className="form-input is-wide" value={step.task?.next_action_text ?? ''} onChange={event => patchStep(stepIndex, { task: { ...(step.task ?? { expected_outcome: '' }), next_action_text: event.target.value } })} placeholder="الإجراء التالي" /><select className="form-input is-wide" value={step.task?.assignee_user_id ?? ''} onChange={event => patchStep(stepIndex, { task: { ...(step.task ?? { expected_outcome: '' }), assignee_user_id: event.target.value || undefined } })}><option value="">يحدده runtime / صاحب المسار</option>{(users.data ?? []).map(user => <option key={user.user_id} value={user.user_id}>{user.full_name}</option>)}</select></div></div> : <div style={{ marginTop: 'var(--space-3)' }}><label className="form-label">نموذج الاعتماد</label><select className="form-input" value={step.approval_template_id ?? ''} onChange={event => patchStep(stepIndex, { approval_template_id: event.target.value })}><option value="">اختر نموذج اعتماد منشور</option>{publishedApprovals.map(template => <option key={template.id} value={template.id}>{template.name}</option>)}</select></div>}

                  <div style={{ marginTop: 'var(--space-3)' }}><div className="work-management-section-heading"><div><label className="form-label">المخرجات المهيكلة</label><span className="form-hint">حقول يمكن للخطوات التالية الاعتماد عليها.</span></div><button type="button" className="btn btn-ghost btn-sm" onClick={() => patchStep(stepIndex, { output_schema: { ...step.output_schema, fields: [...step.output_schema.fields, emptyOutputField(step.output_schema.fields.length)] } })}><Plus size={14} /> مخرج</button></div>{step.output_schema.fields.length > 0 && <div className="work-management-builder-list">{step.output_schema.fields.map((field, fieldIndex) => <div className="work-management-inline-fields" key={fieldIndex}><input className="form-input" dir="ltr" value={field.key} aria-label={`مفتاح مخرج ${fieldIndex + 1}`} onChange={event => updateOutputField(stepIndex, fieldIndex, { key: event.target.value.replace(/[^A-Za-z0-9_]/g, '_') })} /><input className="form-input is-wide" value={field.label} aria-label={`اسم مخرج ${fieldIndex + 1}`} onChange={event => updateOutputField(stepIndex, fieldIndex, { label: event.target.value })} /><select className="form-input" value={field.type} onChange={event => updateOutputField(stepIndex, fieldIndex, { type: event.target.value as WorkIntakeField['type'] })}><option value="string">نص</option><option value="number">رقم</option><option value="boolean">نعم/لا</option><option value="array">قائمة</option><option value="object">بيانات</option></select><button type="button" className="work-management-icon-button" aria-label="حذف المخرج" onClick={() => patchStep(stepIndex, { output_schema: { ...step.output_schema, fields: step.output_schema.fields.filter((_, index) => index !== fieldIndex) } })}><Trash2 size={14} /></button></div>)}</div>}</div>
                </article>
              })}
            </div>
          </div>
          <div className="form-group is-wide"><label className="perm-checkbox-label"><input type="checkbox" checked={publish} onChange={event => setPublish(event.target.checked)} /> نشر النسخة فور الحفظ</label></div>
          <div className="work-management-form-actions"><button type="button" className="btn btn-secondary" onClick={reset}>إلغاء</button><button type="submit" className="btn btn-primary" disabled={createTemplate.isPending || createVersion.isPending}>{(createTemplate.isPending || createVersion.isPending) ? <Loader2 size={16} className="animate-spin" /> : <Check size={16} />} حفظ المسار</button></div>
        </form>
      </div>}

      <div className="work-management-section"><div className="work-management-section-heading"><div><h3>المسارات الحالية</h3><span className="form-hint">{templates.data?.length ?? 0} مسار</span></div></div>{(templates.data?.length ?? 0) === 0 ? <div className="work-management-empty"><h3>لا توجد مسارات عمل</h3><p>أنشئ مسارًا عندما تكون العملية أكبر من مهمة واحدة وتحتاج خطوات مترابطة.</p></div> : <div className="work-management-grid">{templates.data?.map(template => { const templateVersions = versionsByTemplate.get(template.id) ?? []; const latest = [...templateVersions].sort((a, b) => b.version_number - a.version_number)[0]; return <article className="work-management-card" key={template.id}><div className="work-management-card-head"><div><div className="work-management-card-title">{template.name}</div><div className="work-management-card-subtitle" dir="ltr">{template.code}</div></div><span className={`work-management-pill ${template.current_published_version_id ? 'is-good' : 'is-warning'}`}>{template.current_published_version_id ? 'منشور' : 'مسودة فقط'}</span></div><div className="work-management-meta"><span className="work-management-pill">{templateVersions.length} نسخة</span>{latest && <span className="work-management-pill">v{latest.version_number} — {latest.status}</span>}</div>{latest?.status === 'draft' && <div className="work-management-actions"><button type="button" className="btn btn-ghost btn-sm" disabled={publishVersion.isPending} onClick={() => publishDraft(latest.id)}><Send size={14} /> نشر v{latest.version_number}</button></div>}</article> })}</div>}</div>
    </section>
  )
}
