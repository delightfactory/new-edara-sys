import { useEffect, useMemo, useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { CalendarClock, CheckCircle2, UserRound, UsersRound } from 'lucide-react'
import { toast } from 'sonner'
import Button from '@/components/ui/Button'
import Field from '@/components/ui/Field'
import PageHeader from '@/components/shared/PageHeader'
import FormSection from '@/components/patterns/FormSection'
import FormGrid from '@/components/patterns/FormGrid'
import FormActions from '@/components/patterns/FormActions'
import { useAssignmentCandidates, useCreateTask } from '@/features/work/runtime-hooks'
import type { WorkCompletionMode, WorkPriority, WorkVisibility } from '@/features/work/types'
import './work.css'

function toIso(value: string) {
  return value ? new Date(value).toISOString() : null
}

export default function CreateTaskPage() {
  const navigate = useNavigate()
  const createTask = useCreateTask()
  const { data: candidates = [], isLoading: candidatesLoading } = useAssignmentCandidates('')

  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [expectedOutcome, setExpectedOutcome] = useState('')
  const [nextActionText, setNextActionText] = useState('')
  const [dueAt, setDueAt] = useState('')
  const [nextActionAt, setNextActionAt] = useState('')
  const [priority, setPriority] = useState<WorkPriority>('normal')
  const [visibility, setVisibility] = useState<WorkVisibility>('standard')
  const [ownerUserId, setOwnerUserId] = useState('')
  const [assigneeUserId, setAssigneeUserId] = useState('')
  const [acknowledgementRequired, setAcknowledgementRequired] = useState(false)
  const [completionMode, setCompletionMode] = useState<WorkCompletionMode>('assignee_closes')
  const [errors, setErrors] = useState<Record<string, string>>({})

  useEffect(() => {
    if (candidates.length === 0) return
    const self = candidates.find(candidate => candidate.is_self) ?? candidates[0]
    setOwnerUserId(current => current || self.user_id)
    setAssigneeUserId(current => current || self.user_id)
  }, [candidates])

  const selectedOwner = useMemo(
    () => candidates.find(candidate => candidate.user_id === ownerUserId),
    [candidates, ownerUserId],
  )
  const selectedAssignee = useMemo(
    () => candidates.find(candidate => candidate.user_id === assigneeUserId),
    [candidates, assigneeUserId],
  )
  const assigneeIsSelf = selectedAssignee?.is_self ?? false

  useEffect(() => {
    if (assigneeIsSelf) setAcknowledgementRequired(false)
  }, [assigneeIsSelf])

  const validate = () => {
    const next: Record<string, string> = {}
    if (!title.trim()) next.title = 'عنوان المهمة مطلوب'
    if (!expectedOutcome.trim()) next.expectedOutcome = 'حدد النتيجة التي تعتبر المهمة مكتملة عند تحقيقها'
    if (!nextActionText.trim()) next.nextActionText = 'حدد أول إجراء عملي بعد إنشاء المهمة'
    if (!ownerUserId) next.ownerUserId = 'حدد المسؤول النهائي عن النتيجة'
    if (!assigneeUserId) next.assigneeUserId = 'حدد الشخص الذي تقع عنده الكرة الآن'
    if (dueAt && nextActionAt && new Date(nextActionAt).getTime() > new Date(dueAt).getTime()) {
      next.nextActionAt = 'موعد الإجراء التالي لا يفضل أن يتجاوز الموعد النهائي للمهمة'
    }
    setErrors(next)
    return Object.keys(next).length === 0
  }

  const handleSubmit = async (event: FormEvent) => {
    event.preventDefault()
    if (!validate()) return

    try {
      const result = await createTask.mutateAsync({
        title: title.trim(),
        description: description.trim() || null,
        expectedOutcome: expectedOutcome.trim(),
        nextActionText: nextActionText.trim(),
        dueAt: toIso(dueAt),
        nextActionAt: toIso(nextActionAt),
        priority,
        visibility,
        ownerUserId,
        assigneeUserId,
        acknowledgementRequired: acknowledgementRequired && !assigneeIsSelf,
        completionMode,
        activate: true,
      })
      toast.success('تم إنشاء المهمة وتفعيلها')
      navigate(`/work/${result.work_item_id}`)
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'تعذر إنشاء المهمة')
    }
  }

  return (
    <div className="work-page">
      <PageHeader
        title="مهمة جديدة"
        subtitle="اكتب المهمة بصيغة تجعل التنفيذ والمسؤولية واضحين من أول لحظة."
        backPath="/work"
      />

      <form className="work-form" onSubmit={handleSubmit} noValidate>
        <FormSection title="ما المطلوب بالضبط؟">
          <Field id="work-title" label="عنوان المهمة" required error={errors.title}>
            {({ controlId, describedBy, invalid }) => (
              <input
                id={controlId}
                className="form-input"
                value={title}
                onChange={event => setTitle(event.target.value)}
                maxLength={250}
                placeholder="مثال: مراجعة مديونية العميل قبل الزيارة"
                autoFocus
                aria-required="true"
                aria-invalid={invalid || undefined}
                aria-describedby={describedBy}
              />
            )}
          </Field>

          <Field id="work-description" label="تفاصيل التنفيذ">
            {({ controlId, describedBy, invalid }) => (
              <textarea
                id={controlId}
                className="form-textarea"
                value={description}
                onChange={event => setDescription(event.target.value)}
                placeholder="أضف السياق أو البيانات التي يحتاجها المنفذ بدون تكرار العنوان."
                aria-invalid={invalid || undefined}
                aria-describedby={describedBy}
              />
            )}
          </Field>

          <Field
            id="work-outcome"
            label="النتيجة المتوقعة"
            hint="هذه ليست خطوة تنفيذ؛ هي تعريف واضح للنتيجة النهائية المقبولة."
            required
            error={errors.expectedOutcome}
          >
            {({ controlId, describedBy, invalid }) => (
              <textarea
                id={controlId}
                className="form-textarea"
                value={expectedOutcome}
                onChange={event => setExpectedOutcome(event.target.value)}
                placeholder="متى نستطيع أن نقول إن المهمة انتهت بنجاح؟"
                aria-required="true"
                aria-invalid={invalid || undefined}
                aria-describedby={describedBy}
              />
            )}
          </Field>
        </FormSection>

        <FormSection title="من المسؤول ومن يمسك الكرة الآن؟">
          <FormGrid columns={2}>
            <Field
              id="work-owner"
              label={<><UsersRound size={15} /> المسؤول النهائي</>}
              hint="يبقى مسؤولًا عن النتيجة حتى لو تم تفويض التنفيذ لشخص آخر."
              required
              error={errors.ownerUserId}
            >
              {({ controlId, describedBy, invalid }) => (
                <select
                  id={controlId}
                  className="form-select"
                  value={ownerUserId}
                  onChange={event => setOwnerUserId(event.target.value)}
                  disabled={candidatesLoading}
                  aria-required="true"
                  aria-invalid={invalid || undefined}
                  aria-describedby={describedBy}
                >
                  <option value="">اختر المسؤول</option>
                  {candidates.map(candidate => (
                    <option key={candidate.user_id} value={candidate.user_id}>
                      {candidate.full_name}{candidate.is_self ? ' — أنا' : ''}
                    </option>
                  ))}
                </select>
              )}
            </Field>

            <Field
              id="work-assignee"
              label={<><UserRound size={15} /> المكلف الحالي</>}
              hint="هو الشخص الذي يجب أن يتحرك الآن فعليًا."
              required
              error={errors.assigneeUserId}
            >
              {({ controlId, describedBy, invalid }) => (
                <select
                  id={controlId}
                  className="form-select"
                  value={assigneeUserId}
                  onChange={event => setAssigneeUserId(event.target.value)}
                  disabled={candidatesLoading}
                  aria-required="true"
                  aria-invalid={invalid || undefined}
                  aria-describedby={describedBy}
                >
                  <option value="">اختر المكلف</option>
                  {candidates.map(candidate => (
                    <option key={candidate.user_id} value={candidate.user_id}>
                      {candidate.full_name}{candidate.is_self ? ' — أنا' : ''}
                    </option>
                  ))}
                </select>
              )}
            </Field>
          </FormGrid>

          {selectedOwner && selectedAssignee && (
            <div className="work-info-grid" style={{ marginTop: 'var(--space-4)' }}>
              <div className="work-info-cell">
                <div className="work-info-label">المساءلة</div>
                <div className="work-info-value">{selectedOwner.full_name}</div>
              </div>
              <div className="work-info-cell">
                <div className="work-info-label">الكرة الآن عند</div>
                <div className="work-info-value">{selectedAssignee.full_name}</div>
              </div>
            </div>
          )}

          <label className="work-inline-check" style={{ marginTop: 'var(--space-4)' }}>
            <input
              type="checkbox"
              checked={acknowledgementRequired}
              disabled={!assigneeUserId || assigneeIsSelf}
              onChange={event => setAcknowledgementRequired(event.target.checked)}
            />
            <span>
              اطلب تأكيد استلام المهمة من المكلف
              <span className="work-field-hint" style={{ display: 'block' }}>مفيد عندما تكون المهمة مسندة لشخص آخر؛ فتح المهمة وحده لا يعتبر تنفيذًا.</span>
            </span>
          </label>
        </FormSection>

        <FormSection title="ما الخطوة التالية ومتى؟">
          <Field id="work-next-action" label="الإجراء التالي" required error={errors.nextActionText}>
            {({ controlId, describedBy, invalid }) => (
              <input
                id={controlId}
                className="form-input"
                value={nextActionText}
                onChange={event => setNextActionText(event.target.value)}
                maxLength={500}
                placeholder="مثال: الاتصال بالعميل لتأكيد الرصيد قبل الساعة 12"
                aria-required="true"
                aria-invalid={invalid || undefined}
                aria-describedby={describedBy}
              />
            )}
          </Field>

          <FormGrid columns={2}>
            <Field
              id="work-next-action-at"
              label={<><CalendarClock size={15} /> موعد الإجراء التالي</>}
              error={errors.nextActionAt}
            >
              {({ controlId, describedBy, invalid }) => (
                <input
                  id={controlId}
                  className="form-input"
                  type="datetime-local"
                  value={nextActionAt}
                  onChange={event => setNextActionAt(event.target.value)}
                  aria-invalid={invalid || undefined}
                  aria-describedby={describedBy}
                />
              )}
            </Field>

            <Field id="work-due-at" label={<><CalendarClock size={15} /> الموعد النهائي</>}>
              {({ controlId, describedBy, invalid }) => (
                <input
                  id={controlId}
                  className="form-input"
                  type="datetime-local"
                  value={dueAt}
                  onChange={event => setDueAt(event.target.value)}
                  aria-invalid={invalid || undefined}
                  aria-describedby={describedBy}
                />
              )}
            </Field>
          </FormGrid>
        </FormSection>

        <FormSection title="أولوية وخصوصية الإجراء">
          <FormGrid columns={2}>
            <Field id="work-priority" label="الأولوية">
              {({ controlId, describedBy, invalid }) => (
                <select
                  id={controlId}
                  className="form-select"
                  value={priority}
                  onChange={event => setPriority(event.target.value as WorkPriority)}
                  aria-invalid={invalid || undefined}
                  aria-describedby={describedBy}
                >
                  <option value="low">منخفضة</option>
                  <option value="normal">عادية</option>
                  <option value="high">مهمة</option>
                  <option value="urgent">عاجلة</option>
                  <option value="critical">حرجة</option>
                </select>
              )}
            </Field>

            <Field id="work-visibility" label="الخصوصية">
              {({ controlId, describedBy, invalid }) => (
                <select
                  id={controlId}
                  className="form-select"
                  value={visibility}
                  onChange={event => setVisibility(event.target.value as WorkVisibility)}
                  aria-invalid={invalid || undefined}
                  aria-describedby={describedBy}
                >
                  <option value="standard">عادية — وفق نطاق الصلاحيات</option>
                  <option value="restricted">مقيدة — تحتاج صلاحية إضافية</option>
                  <option value="private">خاصة — أضيق نطاق رؤية</option>
                </select>
              )}
            </Field>
          </FormGrid>

          <Field
            id="work-completion-mode"
            label="طريقة اعتماد الإتمام"
            hint="الاعتماد متعدد المراحل يُربط بقالب اعتماد مخصص من إعدادات Work وليس من هذا النموذج السريع."
          >
            {({ controlId, describedBy, invalid }) => (
              <select
                id={controlId}
                className="form-select"
                value={completionMode}
                onChange={event => setCompletionMode(event.target.value as WorkCompletionMode)}
                aria-invalid={invalid || undefined}
                aria-describedby={describedBy}
              >
                <option value="assignee_closes">المكلف يغلق المهمة عند اكتمال النتيجة</option>
                <option value="owner_review">المسؤول النهائي يراجع الإتمام</option>
              </select>
            )}
          </Field>
        </FormSection>

        <FormActions>
          <Button type="button" variant="secondary" touchTarget onClick={() => navigate('/work')}>إلغاء</Button>
          <Button type="submit" touchTarget loading={createTask.isPending} icon={<CheckCircle2 size={17} />}>
            إنشاء وتفعيل المهمة
          </Button>
        </FormActions>
      </form>
    </div>
  )
}
