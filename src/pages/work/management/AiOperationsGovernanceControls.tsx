import { useState } from 'react'
import { PencilLine, PlusCircle, ShieldAlert, XCircle } from 'lucide-react'
import { useManagementUsers } from '@/features/work/management-hooks'
import {
  useCreateAiOperationsContext,
  useReviseAiOperationsDecision,
  useRevokeAiOperationsContext,
} from '@/features/ai-operations/hooks'
import type {
  AiOpsCase,
  AiOpsDecisionReviewDetail,
  AiOpsOperationalContextItem,
} from '@/features/ai-operations/types'

function toDateTimeLocal(value: string | null) {
  if (!value) return ''
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ''
  const pad = (part: number) => String(part).padStart(2, '0')
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`
}

export function AiOperationsDecisionRevisionEditor({
  decision,
  disabled,
}: {
  decision: AiOpsDecisionReviewDetail
  disabled: boolean
}) {
  const [open, setOpen] = useState(false)
  const [ownerId, setOwnerId] = useState('')
  const [assigneeId, setAssigneeId] = useState('')
  const [expectedOutcome, setExpectedOutcome] = useState('')
  const [nextActionText, setNextActionText] = useState('')
  const [successSignal, setSuccessSignal] = useState('')
  const [employeeSafeReason, setEmployeeSafeReason] = useState('')
  const [dueAt, setDueAt] = useState('')
  const [revisionNote, setRevisionNote] = useState('')
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState(false)
  const users = useManagementUsers('', open)
  const revision = useReviseAiOperationsDecision()

  if (decision.decision_type !== 'CREATE_WORK' || decision.review_state !== null) return null

  const startEditing = () => {
    setOwnerId(decision.recommended_owner_user_id ?? '')
    setAssigneeId(decision.recommended_assignee_user_id ?? '')
    setExpectedOutcome(decision.expected_outcome ?? '')
    setNextActionText(decision.next_action_text ?? '')
    setSuccessSignal(decision.success_signal ?? '')
    setEmployeeSafeReason(decision.employee_safe_reason ?? '')
    setDueAt(toDateTimeLocal(decision.due_at))
    setRevisionNote('')
    setMessage(null)
    setError(false)
    setOpen(true)
  }

  const save = async () => {
    setMessage(null)
    setError(false)
    try {
      if (
        !ownerId || !assigneeId || !expectedOutcome.trim() || !nextActionText.trim()
        || !successSignal.trim() || !employeeSafeReason.trim() || !dueAt
      ) {
        throw new Error('حدد المالك والمنفذ والنتيجة والإجراء وإشارة النجاح والسبب الآمن للموظف والموعد قبل حفظ التعديل.')
      }
      const parsedDue = new Date(dueAt)
      if (Number.isNaN(parsedDue.getTime())) throw new Error('الموعد المعدل غير صالح.')

      const result = await revision.mutateAsync({
        decisionId: decision.decision_id,
        ownerUserId: ownerId,
        assigneeUserId: assigneeId,
        expectedOutcome,
        nextActionText,
        dueAt: parsedDue.toISOString(),
        successSignal,
        employeeSafeReason,
        revisionNote,
      })
      setOpen(false)
      if (result.validation_state === 'validated') {
        setMessage(`تم إنشاء Revision ${result.revision} وإعادة التحقق منها. راجعها ثم اعتمدها بشكل مستقل.`)
      } else {
        setError(true)
        setMessage(`تم حفظ Revision ${result.revision} للسجل لكنها فشلت في التحقق الحالي: ${result.validation_codes.join('، ') || 'تغير الواقع التشغيلي'}.`)
      }
    } catch (caught) {
      setError(true)
      setMessage(caught instanceof Error ? caught.message : 'تعذر تعديل القرار.')
    }
  }

  return (
    <div className="aiops-governance-control">
      {!open && (
        <button type="button" className="btn btn-secondary" disabled={disabled} onClick={startEditing}>
          <PencilLine size={16} /> تعديل القرار قبل الاعتماد
        </button>
      )}

      {open && (
        <div className="aiops-governance-editor">
          <div className="aiops-governance-warning">
            <ShieldAlert size={15} /> التعديل ينشئ Revision جديدة؛ القرار الأصلي يظل محفوظًا ولا يحدث أي تنفيذ. إشارة النجاح والسبب الذي يصل للموظف يتحركان مع النسخة الجديدة حتى لا نعتمد هدفًا قديمًا لمهمة معدلة.
          </div>
          <div className="aiops-governance-grid">
            <label>
              <span>Accountable Owner</span>
              <select value={ownerId} onChange={event => setOwnerId(event.target.value)} disabled={users.isLoading || revision.isPending}>
                <option value="">اختر المالك</option>
                {(users.data ?? []).map(user => <option key={user.user_id} value={user.user_id}>{user.full_name}</option>)}
              </select>
            </label>
            <label>
              <span>Assignee / المنفذ</span>
              <select value={assigneeId} onChange={event => setAssigneeId(event.target.value)} disabled={users.isLoading || revision.isPending}>
                <option value="">اختر المنفذ</option>
                {(users.data ?? []).map(user => <option key={user.user_id} value={user.user_id}>{user.full_name}</option>)}
              </select>
            </label>
            <label className="aiops-governance-wide">
              <span>الموعد الجديد</span>
              <input type="datetime-local" value={dueAt} onChange={event => setDueAt(event.target.value)} disabled={revision.isPending} />
            </label>
            <label className="aiops-governance-wide">
              <span>الإجراء التالي</span>
              <textarea maxLength={500} value={nextActionText} onChange={event => setNextActionText(event.target.value)} disabled={revision.isPending} />
            </label>
            <label className="aiops-governance-wide">
              <span>النتيجة المتوقعة</span>
              <textarea maxLength={1000} value={expectedOutcome} onChange={event => setExpectedOutcome(event.target.value)} disabled={revision.isPending} />
            </label>
            <label className="aiops-governance-wide">
              <span>إشارة النجاح التي سنراجعها</span>
              <textarea maxLength={500} value={successSignal} onChange={event => setSuccessSignal(event.target.value)} disabled={revision.isPending} />
            </label>
            <label className="aiops-governance-wide">
              <span>السبب الآمن الذي يصل للموظف</span>
              <textarea maxLength={500} value={employeeSafeReason} onChange={event => setEmployeeSafeReason(event.target.value)} disabled={revision.isPending} />
            </label>
            <label className="aiops-governance-wide">
              <span>سبب التعديل — اختياري</span>
              <textarea maxLength={1000} value={revisionNote} onChange={event => setRevisionNote(event.target.value)} disabled={revision.isPending} />
            </label>
          </div>
          <div className="aiops-review-actions">
            <button type="button" className="btn btn-primary" disabled={revision.isPending} onClick={save}>حفظ Revision وإعادة التحقق</button>
            <button type="button" className="btn btn-secondary" disabled={revision.isPending} onClick={() => setOpen(false)}>إلغاء</button>
          </div>
        </div>
      )}

      {message && <div className={`aiops-review-message${error ? ' aiops-review-message--danger' : ''}`}>{message}</div>}
    </div>
  )
}

const contextTypes = [
  ['temporary_arrangement', 'اتفاق أو ترتيب مؤقت'],
  ['relationship_context', 'سياق علاقة عميل/جهة'],
  ['planned_exception', 'استثناء مخطط ومقبول'],
  ['execution_constraint', 'قيد يمنع أو يغير التنفيذ'],
  ['ownership_context', 'توضيح مسؤولية أو ملكية علاقة'],
] as const

export function AiOperationsCaseContextEditor({
  item,
  disabled,
}: {
  item: AiOpsCase
  disabled: boolean
}) {
  const [open, setOpen] = useState(false)
  const [contextType, setContextType] = useState<(typeof contextTypes)[number][0]>('temporary_arrangement')
  const [summary, setSummary] = useState('')
  const [validUntil, setValidUntil] = useState('')
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState(false)
  const mutation = useCreateAiOperationsContext()

  if (!item.entity_type || !item.entity_id) return null

  const save = async () => {
    setMessage(null)
    setError(false)
    try {
      if (!summary.trim() || !validUntil) throw new Error('اكتب السياق وحدد تاريخ انتهاء واضح.')
      const expiry = new Date(validUntil)
      if (Number.isNaN(expiry.getTime())) throw new Error('تاريخ انتهاء السياق غير صالح.')
      await mutation.mutateAsync({
        subjectType: item.entity_type!,
        subjectId: item.entity_id!,
        contextType,
        summary,
        validUntil: expiry.toISOString(),
        visibility: 'management',
      })
      setSummary('')
      setValidUntil('')
      setOpen(false)
      setMessage('تم حفظ السياق كحقيقة إدارية معتمدة ومؤقتة. سيؤثر فقط على Snapshots الجديدة بعد إضافته.')
    } catch (caught) {
      setError(true)
      setMessage(caught instanceof Error ? caught.message : 'تعذر حفظ السياق التشغيلي.')
    }
  }

  return (
    <div className="aiops-governance-control">
      {!open && (
        <button type="button" className="btn btn-secondary" disabled={disabled} onClick={() => setOpen(true)}>
          <PlusCircle size={16} /> إضافة سياق إداري للحالة
        </button>
      )}
      {open && (
        <div className="aiops-governance-editor">
          <div className="aiops-governance-warning">
            <ShieldAlert size={15} /> السياق بيانات إدارية غير تنفيذية، ومطلوب له تاريخ انتهاء حتى لا يتحول لاستثناء دائم.
          </div>
          <div className="aiops-governance-grid">
            <label>
              <span>نوع السياق</span>
              <select value={contextType} onChange={event => setContextType(event.target.value as typeof contextType)} disabled={mutation.isPending}>
                {contextTypes.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
              </select>
            </label>
            <label>
              <span>صالح حتى</span>
              <input type="datetime-local" value={validUntil} onChange={event => setValidUntil(event.target.value)} disabled={mutation.isPending} />
            </label>
            <label className="aiops-governance-wide">
              <span>المعلومة الإدارية</span>
              <textarea maxLength={500} value={summary} onChange={event => setSummary(event.target.value)} disabled={mutation.isPending} placeholder="مثال: يوجد اتفاق مع العميل على التحصيل يوم الخميس؛ لا تصعّد قبل الموعد." />
            </label>
          </div>
          <div className="aiops-review-actions">
            <button type="button" className="btn btn-primary" disabled={mutation.isPending} onClick={save}>حفظ السياق</button>
            <button type="button" className="btn btn-secondary" disabled={mutation.isPending} onClick={() => setOpen(false)}>إلغاء</button>
          </div>
        </div>
      )}
      {message && <div className={`aiops-review-message${error ? ' aiops-review-message--danger' : ''}`}>{message}</div>}
    </div>
  )
}

export function AiOperationsContextRevokeButton({
  item,
  disabled,
}: {
  item: AiOpsOperationalContextItem
  disabled: boolean
}) {
  const mutation = useRevokeAiOperationsContext()
  const [message, setMessage] = useState<string | null>(null)

  if (item.status !== 'active') return null

  const revoke = async () => {
    setMessage(null)
    try {
      await mutation.mutateAsync({ contextId: item.id, note: 'Revoked from AI Operations management console' })
      setMessage('تم إلغاء السياق ولن يدخل في Snapshots جديدة.')
    } catch (caught) {
      setMessage(caught instanceof Error ? caught.message : 'تعذر إلغاء السياق.')
    }
  }

  return (
    <div className="aiops-context-revoke">
      <button type="button" className="aiops-context-revoke-button" disabled={disabled || mutation.isPending} onClick={revoke}>
        <XCircle size={13} /> إلغاء السياق
      </button>
      {message && <span>{message}</span>}
    </div>
  )
}
