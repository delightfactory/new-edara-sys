import { useMemo, useState, type FormEvent } from 'react'
import { Loader2, Plus, Power, Trash2, UserPlus } from 'lucide-react'
import { toast } from 'sonner'
import {
  useCreateQueue,
  useCreateRequestType,
  useManagementUsers,
  useSetQueueMember,
  useUpdateQueue,
  useWorkQueueMembers,
  useWorkQueues,
  useWorkRequestTypes,
} from '@/features/work/management-hooks'
import type { WorkIntakeField } from '@/features/work/management-types'
import type { WorkPriority } from '@/features/work/types'

const PRIORITIES: Array<{ value: WorkPriority; label: string }> = [
  { value: 'low', label: 'منخفضة' },
  { value: 'normal', label: 'عادية' },
  { value: 'high', label: 'مرتفعة' },
  { value: 'urgent', label: 'عاجلة' },
  { value: 'critical', label: 'حرجة' },
]

const FIELD_TYPES: Array<{ value: WorkIntakeField['type']; label: string }> = [
  { value: 'string', label: 'نص' },
  { value: 'number', label: 'رقم' },
  { value: 'boolean', label: 'نعم / لا' },
  { value: 'array', label: 'قائمة' },
  { value: 'object', label: 'بيانات مركبة' },
]

const emptyField = (index: number): WorkIntakeField => ({ key: `field_${index + 1}`, label: '', type: 'string', required: false })

export default function QueuesManagementPanel() {
  const queues = useWorkQueues()
  const members = useWorkQueueMembers()
  const requestTypes = useWorkRequestTypes()
  const users = useManagementUsers('')
  const createQueue = useCreateQueue()
  const updateQueue = useUpdateQueue()
  const setMember = useSetQueueMember()
  const createRequestType = useCreateRequestType()

  const [showQueueForm, setShowQueueForm] = useState(false)
  const [showRequestTypeForm, setShowRequestTypeForm] = useState(false)
  const [queueCode, setQueueCode] = useState('')
  const [queueName, setQueueName] = useState('')
  const [queueDescription, setQueueDescription] = useState('')
  const [queueManager, setQueueManager] = useState('')
  const [queuePriority, setQueuePriority] = useState<WorkPriority>('normal')
  const [queueTriageSla, setQueueTriageSla] = useState(240)
  const [queueResolutionSla, setQueueResolutionSla] = useState<number | ''>('')

  const [memberQueueId, setMemberQueueId] = useState('')
  const [memberUserId, setMemberUserId] = useState('')
  const [memberRole, setMemberRole] = useState<'member' | 'triager' | 'manager'>('member')
  const [memberCanTriage, setMemberCanTriage] = useState(false)
  const [memberCanAssign, setMemberCanAssign] = useState(false)

  const [typeCode, setTypeCode] = useState('')
  const [typeName, setTypeName] = useState('')
  const [typeDescription, setTypeDescription] = useState('')
  const [typeQueueId, setTypeQueueId] = useState('')
  const [typeOutcome, setTypeOutcome] = useState('')
  const [typeTriageSla, setTypeTriageSla] = useState<number | ''>('')
  const [typeResolutionSla, setTypeResolutionSla] = useState<number | ''>('')
  const [typeFields, setTypeFields] = useState<WorkIntakeField[]>([emptyField(0)])

  const activeQueues = useMemo(() => (queues.data ?? []).filter(queue => queue.is_active), [queues.data])
  const userNames = useMemo(() => new Map((users.data ?? []).map(user => [user.user_id, user.full_name])), [users.data])
  const memberCountByQueue = useMemo(() => {
    const counts = new Map<string, number>()
    for (const member of members.data ?? []) counts.set(member.queue_id, (counts.get(member.queue_id) ?? 0) + 1)
    return counts
  }, [members.data])

  const resetQueueForm = () => {
    setQueueCode('')
    setQueueName('')
    setQueueDescription('')
    setQueueManager('')
    setQueuePriority('normal')
    setQueueTriageSla(240)
    setQueueResolutionSla('')
    setShowQueueForm(false)
  }

  const submitQueue = async (event: FormEvent) => {
    event.preventDefault()
    if (!queueCode.trim() || !queueName.trim() || !queueManager) {
      toast.error('الكود والاسم ومسؤول الطابور مطلوبون')
      return
    }
    try {
      await createQueue.mutateAsync({
        code: queueCode,
        name: queueName,
        description: queueDescription || null,
        managerUserId: queueManager,
        defaultPriority: queuePriority,
        defaultTriageSlaMinutes: queueTriageSla,
        defaultResolutionSlaMinutes: queueResolutionSla === '' ? null : queueResolutionSla,
      })
      toast.success('تم إنشاء طابور العمل')
      resetQueueForm()
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'تعذر إنشاء الطابور')
    }
  }

  const toggleQueue = async (queueId: string) => {
    const queue = queues.data?.find(item => item.id === queueId)
    if (!queue) return
    try {
      await updateQueue.mutateAsync({
        queueId: queue.id,
        expectedVersion: queue.state_version,
        name: queue.name,
        description: queue.description,
        managerUserId: queue.manager_user_id,
        branchId: queue.branch_id,
        departmentId: queue.department_id,
        defaultPriority: queue.default_priority,
        defaultTriageSlaMinutes: queue.default_triage_sla_minutes,
        defaultResolutionSlaMinutes: queue.default_resolution_sla_minutes,
        isActive: !queue.is_active,
      })
      toast.success(queue.is_active ? 'تم إيقاف الطابور' : 'تم تفعيل الطابور')
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'تعذر تحديث الطابور')
    }
  }

  const submitMember = async (event: FormEvent) => {
    event.preventDefault()
    if (!memberQueueId || !memberUserId) {
      toast.error('اختر الطابور والمستخدم')
      return
    }
    try {
      await setMember.mutateAsync({
        queueId: memberQueueId,
        userId: memberUserId,
        memberRole,
        canTriage: memberCanTriage || memberRole === 'triager' || memberRole === 'manager',
        canAssign: memberCanAssign || memberRole === 'manager',
        isActive: true,
      })
      toast.success('تم تحديث عضوية الطابور')
      setMemberUserId('')
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'تعذر تحديث العضوية')
    }
  }

  const updateField = (index: number, patch: Partial<WorkIntakeField>) => {
    setTypeFields(previous => previous.map((field, current) => current === index ? { ...field, ...patch } : field))
  }

  const submitRequestType = async (event: FormEvent) => {
    event.preventDefault()
    const usableFields = typeFields.filter(field => field.key.trim() && field.label.trim())
    if (!typeCode.trim() || !typeName.trim() || !typeQueueId || !typeOutcome.trim()) {
      toast.error('الكود والاسم والطابور والنتيجة المتوقعة مطلوبة')
      return
    }
    if (new Set(usableFields.map(field => field.key.trim())).size !== usableFields.length) {
      toast.error('مفاتيح حقول نموذج الطلب يجب أن تكون فريدة')
      return
    }
    try {
      await createRequestType.mutateAsync({
        code: typeCode,
        name: typeName,
        description: typeDescription || null,
        targetQueueId: typeQueueId,
        expectedOutcomeTemplate: typeOutcome,
        intakeSchema: { version: 1, fields: usableFields },
        triageSlaMinutes: typeTriageSla === '' ? null : typeTriageSla,
        defaultResolutionSlaMinutes: typeResolutionSla === '' ? null : typeResolutionSla,
        allowRequesterCancel: true,
      })
      toast.success('تم إنشاء نوع الطلب')
      setTypeCode('')
      setTypeName('')
      setTypeDescription('')
      setTypeOutcome('')
      setTypeTriageSla('')
      setTypeResolutionSla('')
      setTypeFields([emptyField(0)])
      setShowRequestTypeForm(false)
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'تعذر إنشاء نوع الطلب')
    }
  }

  if (queues.isLoading || requestTypes.isLoading || members.isLoading) {
    return <div className="work-management-loading"><Loader2 className="animate-spin" /> جاري تحميل إعدادات الطوابير…</div>
  }
  if (queues.error || requestTypes.error || members.error) {
    return <div className="work-management-error"><p>تعذر تحميل إعدادات الطوابير والطلبات. أعد المحاولة من الصفحة.</p></div>
  }

  return (
    <section className="work-management-panel" aria-labelledby="queues-management-title">
      <div className="work-management-panel-header">
        <div>
          <h2 id="queues-management-title">الطوابير واستقبال الطلبات</h2>
          <p className="page-subtitle">افصل قناة استقبال الطلب عن تنفيذ المهمة، وحدد من يفرز ومن يوزع العمل.</p>
        </div>
        <div className="work-management-actions" style={{ marginTop: 0 }}>
          <button type="button" className="btn btn-secondary" onClick={() => setShowRequestTypeForm(value => !value)}>
            <Plus size={16} /> نوع طلب
          </button>
          <button type="button" className="btn btn-primary" onClick={() => setShowQueueForm(value => !value)}>
            <Plus size={16} /> طابور جديد
          </button>
        </div>
      </div>

      {showQueueForm && (
        <div className="work-management-section">
          <div className="work-management-section-heading"><h3>إنشاء طابور تشغيل</h3></div>
          <form className="work-management-form" onSubmit={submitQueue}>
            <div className="form-group">
              <label className="form-label required" htmlFor="queue-code">الكود</label>
              <input id="queue-code" className="form-input" dir="ltr" value={queueCode} onChange={event => setQueueCode(event.target.value)} placeholder="customer_service" />
            </div>
            <div className="form-group">
              <label className="form-label required" htmlFor="queue-name">الاسم</label>
              <input id="queue-name" className="form-input" value={queueName} onChange={event => setQueueName(event.target.value)} placeholder="خدمة العملاء" />
            </div>
            <div className="form-group is-wide">
              <label className="form-label" htmlFor="queue-description">الوصف</label>
              <textarea id="queue-description" className="form-input" rows={2} value={queueDescription} onChange={event => setQueueDescription(event.target.value)} />
            </div>
            <div className="form-group">
              <label className="form-label required" htmlFor="queue-manager">مسؤول الطابور</label>
              <select id="queue-manager" className="form-input" value={queueManager} onChange={event => setQueueManager(event.target.value)}>
                <option value="">اختر المستخدم</option>
                {(users.data ?? []).map(user => <option key={user.user_id} value={user.user_id}>{user.full_name}</option>)}
              </select>
            </div>
            <div className="form-group">
              <label className="form-label" htmlFor="queue-priority">الأولوية الافتراضية</label>
              <select id="queue-priority" className="form-input" value={queuePriority} onChange={event => setQueuePriority(event.target.value as WorkPriority)}>
                {PRIORITIES.map(priority => <option key={priority.value} value={priority.value}>{priority.label}</option>)}
              </select>
            </div>
            <div className="form-group">
              <label className="form-label required" htmlFor="queue-triage-sla">SLA الفرز بالدقائق</label>
              <input id="queue-triage-sla" type="number" min={1} className="form-input" dir="ltr" value={queueTriageSla} onChange={event => setQueueTriageSla(Number(event.target.value))} />
            </div>
            <div className="form-group">
              <label className="form-label" htmlFor="queue-resolution-sla">SLA التنفيذ بالدقائق</label>
              <input id="queue-resolution-sla" type="number" min={1} className="form-input" dir="ltr" value={queueResolutionSla} onChange={event => setQueueResolutionSla(event.target.value ? Number(event.target.value) : '')} placeholder="اختياري" />
            </div>
            <div className="work-management-form-actions">
              <button type="button" className="btn btn-secondary" onClick={resetQueueForm}>إلغاء</button>
              <button type="submit" className="btn btn-primary" disabled={createQueue.isPending}>
                {createQueue.isPending ? <Loader2 size={16} className="animate-spin" /> : <Plus size={16} />} إنشاء الطابور
              </button>
            </div>
          </form>
        </div>
      )}

      <div className="work-management-section">
        <div className="work-management-section-heading">
          <div><h3>الطوابير الحالية</h3><span className="form-hint">{queues.data?.length ?? 0} طابور</span></div>
        </div>
        {(queues.data?.length ?? 0) === 0 ? (
          <div className="work-management-empty"><h3>لا توجد طوابير بعد</h3><p>أنشئ أول قناة استقبال للطلبات التشغيلية.</p></div>
        ) : (
          <div className="work-management-grid">
            {queues.data?.map(queue => (
              <article key={queue.id} className="work-management-card">
                <div className="work-management-card-head">
                  <div>
                    <div className="work-management-card-title">{queue.name}</div>
                    <div className="work-management-card-subtitle" dir="ltr">{queue.code}</div>
                  </div>
                  <span className={`work-management-pill ${queue.is_active ? 'is-good' : 'is-muted'}`}>{queue.is_active ? 'نشط' : 'متوقف'}</span>
                </div>
                <div className="work-management-meta">
                  <span className="work-management-pill">فرز {queue.default_triage_sla_minutes} د</span>
                  <span className="work-management-pill">{memberCountByQueue.get(queue.id) ?? 0} عضو</span>
                  <span className="work-management-pill">مسؤول: {userNames.get(queue.manager_user_id) ?? 'مستخدم نشط'}</span>
                </div>
                <div className="work-management-actions">
                  <button type="button" className="btn btn-ghost btn-sm" onClick={() => { setMemberQueueId(queue.id); setMemberUserId('') }}>
                    <UserPlus size={15} /> عضو
                  </button>
                  <button type="button" className="btn btn-ghost btn-sm" disabled={updateQueue.isPending} onClick={() => toggleQueue(queue.id)}>
                    <Power size={15} /> {queue.is_active ? 'إيقاف' : 'تفعيل'}
                  </button>
                </div>
              </article>
            ))}
          </div>
        )}
      </div>

      {memberQueueId && (
        <div className="work-management-section">
          <div className="work-management-section-heading"><h3>إضافة / تحديث عضو الطابور</h3></div>
          <form className="work-management-form" onSubmit={submitMember}>
            <div className="form-group">
              <label className="form-label required" htmlFor="member-user">المستخدم</label>
              <select id="member-user" className="form-input" value={memberUserId} onChange={event => setMemberUserId(event.target.value)}>
                <option value="">اختر المستخدم</option>
                {(users.data ?? []).map(user => <option key={user.user_id} value={user.user_id}>{user.full_name}</option>)}
              </select>
            </div>
            <div className="form-group">
              <label className="form-label" htmlFor="member-role">الدور داخل الطابور</label>
              <select id="member-role" className="form-input" value={memberRole} onChange={event => setMemberRole(event.target.value as typeof memberRole)}>
                <option value="member">عضو</option>
                <option value="triager">مسؤول فرز</option>
                <option value="manager">مدير الطابور</option>
              </select>
            </div>
            <label className="perm-checkbox-label"><input type="checkbox" checked={memberCanTriage} onChange={event => setMemberCanTriage(event.target.checked)} /> يفرز الطلبات</label>
            <label className="perm-checkbox-label"><input type="checkbox" checked={memberCanAssign} onChange={event => setMemberCanAssign(event.target.checked)} /> يوزع الطلبات</label>
            <div className="work-management-form-actions">
              <button type="button" className="btn btn-secondary" onClick={() => setMemberQueueId('')}>إلغاء</button>
              <button type="submit" className="btn btn-primary" disabled={setMember.isPending}>حفظ العضوية</button>
            </div>
          </form>
        </div>
      )}

      {showRequestTypeForm && (
        <div className="work-management-section">
          <div className="work-management-section-heading"><h3>تعريف نوع طلب</h3></div>
          <form className="work-management-form" onSubmit={submitRequestType}>
            <div className="form-group"><label className="form-label required" htmlFor="type-code">الكود</label><input id="type-code" className="form-input" dir="ltr" value={typeCode} onChange={event => setTypeCode(event.target.value)} /></div>
            <div className="form-group"><label className="form-label required" htmlFor="type-name">الاسم</label><input id="type-name" className="form-input" value={typeName} onChange={event => setTypeName(event.target.value)} /></div>
            <div className="form-group is-wide"><label className="form-label" htmlFor="type-description">الوصف</label><textarea id="type-description" className="form-input" rows={2} value={typeDescription} onChange={event => setTypeDescription(event.target.value)} /></div>
            <div className="form-group"><label className="form-label required" htmlFor="type-queue">طابور الاستقبال</label><select id="type-queue" className="form-input" value={typeQueueId} onChange={event => setTypeQueueId(event.target.value)}><option value="">اختر الطابور</option>{activeQueues.map(queue => <option key={queue.id} value={queue.id}>{queue.name}</option>)}</select></div>
            <div className="form-group"><label className="form-label required" htmlFor="type-outcome">النتيجة المتوقعة</label><input id="type-outcome" className="form-input" value={typeOutcome} onChange={event => setTypeOutcome(event.target.value)} placeholder="ما الذي يجب أن يخرج من معالجة هذا الطلب؟" /></div>
            <div className="form-group"><label className="form-label" htmlFor="type-triage-sla">SLA فرز خاص</label><input id="type-triage-sla" type="number" min={1} className="form-input" dir="ltr" value={typeTriageSla} onChange={event => setTypeTriageSla(event.target.value ? Number(event.target.value) : '')} placeholder="يرث من الطابور" /></div>
            <div className="form-group"><label className="form-label" htmlFor="type-resolution-sla">SLA تنفيذ خاص</label><input id="type-resolution-sla" type="number" min={1} className="form-input" dir="ltr" value={typeResolutionSla} onChange={event => setTypeResolutionSla(event.target.value ? Number(event.target.value) : '')} placeholder="يرث من الطابور" /></div>

            <div className="form-group is-wide">
              <div className="work-management-section-heading"><div><label className="form-label">حقول نموذج الطلب</label><span className="form-hint">المستخدم يرى Labels واضحة؛ المفتاح البرمجي ثابت داخل البيانات.</span></div><button type="button" className="btn btn-ghost btn-sm" onClick={() => setTypeFields(previous => [...previous, emptyField(previous.length)])}><Plus size={15} /> حقل</button></div>
              <div className="work-management-builder-list">
                {typeFields.map((field, index) => (
                  <div className="work-management-builder-item" key={`${index}-${field.key}`}>
                    <div className="work-management-builder-item-head"><span className="work-management-builder-index">{index + 1}</span><button type="button" className="work-management-icon-button" aria-label="حذف الحقل" onClick={() => setTypeFields(previous => previous.filter((_, current) => current !== index))}><Trash2 size={16} /></button></div>
                    <div className="work-management-inline-fields">
                      <input className="form-input" dir="ltr" aria-label={`مفتاح الحقل ${index + 1}`} value={field.key} onChange={event => updateField(index, { key: event.target.value.replace(/[^A-Za-z0-9_]/g, '_') })} />
                      <input className="form-input is-wide" aria-label={`اسم الحقل ${index + 1}`} value={field.label} onChange={event => updateField(index, { label: event.target.value })} placeholder="الاسم الظاهر للمستخدم" />
                      <select className="form-input" aria-label={`نوع الحقل ${index + 1}`} value={field.type} onChange={event => updateField(index, { type: event.target.value as WorkIntakeField['type'] })}>{FIELD_TYPES.map(type => <option key={type.value} value={type.value}>{type.label}</option>)}</select>
                      <label className="perm-checkbox-label"><input type="checkbox" checked={Boolean(field.required)} onChange={event => updateField(index, { required: event.target.checked })} /> مطلوب</label>
                    </div>
                  </div>
                ))}
              </div>
            </div>
            <div className="work-management-form-actions"><button type="button" className="btn btn-secondary" onClick={() => setShowRequestTypeForm(false)}>إلغاء</button><button type="submit" className="btn btn-primary" disabled={createRequestType.isPending}>{createRequestType.isPending && <Loader2 size={16} className="animate-spin" />} حفظ نوع الطلب</button></div>
          </form>
        </div>
      )}

      <div className="work-management-section">
        <div className="work-management-section-heading"><div><h3>أنواع الطلبات</h3><span className="form-hint">{requestTypes.data?.length ?? 0} نوع</span></div></div>
        {(requestTypes.data?.length ?? 0) === 0 ? <div className="work-management-empty"><h3>لا توجد أنواع طلبات</h3><p>اربط كل نوع بطابور واضح وSLA فرز مستقل.</p></div> : <div className="work-management-grid">{requestTypes.data?.map(type => <article key={type.id} className="work-management-card"><div className="work-management-card-head"><div><div className="work-management-card-title">{type.name}</div><div className="work-management-card-subtitle" dir="ltr">{type.code}</div></div><span className={`work-management-pill ${type.is_active ? 'is-good' : 'is-muted'}`}>{type.is_active ? 'نشط' : 'متوقف'}</span></div><div className="work-management-meta"><span className="work-management-pill">{type.intake_schema?.fields?.length ?? 0} حقل</span><span className="work-management-pill">{queues.data?.find(queue => queue.id === type.target_queue_id)?.name ?? 'طابور'}</span><span className="work-management-pill">{type.triage_sla_minutes ? `فرز ${type.triage_sla_minutes} د` : 'يرث SLA الفرز'}</span></div></article>)}</div>}
      </div>
    </section>
  )
}
