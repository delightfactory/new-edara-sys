import { useMemo, useState, type FormEvent } from 'react'
import { Loader2, Pause, Play, Plus, Square } from 'lucide-react'
import { toast } from 'sonner'
import {
  useCreateRecurrence,
  useManagementUsers,
  useRecurrenceDefinitions,
  useSetRecurrenceState,
  useWorkflowTemplates,
} from '@/features/work/management-hooks'

const WEEKDAYS = [
  { value: 6, label: 'السبت' },
  { value: 7, label: 'الأحد' },
  { value: 1, label: 'الاثنين' },
  { value: 2, label: 'الثلاثاء' },
  { value: 3, label: 'الأربعاء' },
  { value: 4, label: 'الخميس' },
  { value: 5, label: 'الجمعة' },
]

const frequencyLabel = (value: string) => value === 'daily' ? 'يومي' : value === 'weekly' ? 'أسبوعي' : 'شهري'

export default function RecurrenceManagementPanel() {
  const recurrence = useRecurrenceDefinitions()
  const workflows = useWorkflowTemplates()
  const users = useManagementUsers('')
  const createRecurrence = useCreateRecurrence()
  const setState = useSetRecurrenceState()

  const [showForm, setShowForm] = useState(false)
  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [targetKind, setTargetKind] = useState<'task' | 'workflow'>('task')
  const [frequency, setFrequency] = useState<'daily' | 'weekly' | 'monthly'>('daily')
  const [intervalCount, setIntervalCount] = useState(1)
  const [localTime, setLocalTime] = useState('09:00')
  const [timezone, setTimezone] = useState('Africa/Cairo')
  const [startsOn, setStartsOn] = useState(() => new Date().toISOString().slice(0, 10))
  const [endsOn, setEndsOn] = useState('')
  const [weekdays, setWeekdays] = useState<number[]>([6])
  const [monthlyPolicy, setMonthlyPolicy] = useState<'exact_day' | 'last_day'>('exact_day')
  const [dayOfMonth, setDayOfMonth] = useState(1)
  const [overlapPolicy, setOverlapPolicy] = useState<'strict' | 'single_open'>('strict')
  const [taskTitle, setTaskTitle] = useState('')
  const [taskOutcome, setTaskOutcome] = useState('')
  const [taskNextAction, setTaskNextAction] = useState('')
  const [taskOwner, setTaskOwner] = useState('')
  const [taskAssignee, setTaskAssignee] = useState('')
  const [taskDueMinutes, setTaskDueMinutes] = useState<number | ''>('')
  const [workflowTemplateId, setWorkflowTemplateId] = useState('')
  const [workflowVersionPolicy, setWorkflowVersionPolicy] = useState<'pinned' | 'latest_published'>('pinned')
  const [workflowStarterUserId, setWorkflowStarterUserId] = useState('')

  const publishedWorkflows = useMemo(() => (workflows.data ?? []).filter(template => template.is_active && template.current_published_version_id), [workflows.data])

  const reset = () => {
    setShowForm(false)
    setName('')
    setDescription('')
    setTargetKind('task')
    setFrequency('daily')
    setIntervalCount(1)
    setLocalTime('09:00')
    setTimezone('Africa/Cairo')
    setEndsOn('')
    setWeekdays([6])
    setMonthlyPolicy('exact_day')
    setDayOfMonth(1)
    setOverlapPolicy('strict')
    setTaskTitle('')
    setTaskOutcome('')
    setTaskNextAction('')
    setTaskOwner('')
    setTaskAssignee('')
    setTaskDueMinutes('')
    setWorkflowTemplateId('')
    setWorkflowVersionPolicy('pinned')
    setWorkflowStarterUserId('')
  }

  const toggleWeekday = (day: number) => setWeekdays(previous => previous.includes(day) ? previous.filter(value => value !== day) : [...previous, day])

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    if (!name.trim()) { toast.error('اسم الجدول الدوري مطلوب'); return }
    if (frequency === 'weekly' && weekdays.length === 0) { toast.error('اختر يومًا أسبوعيًا واحدًا على الأقل'); return }
    if (targetKind === 'task' && (!taskTitle.trim() || !taskOutcome.trim() || !taskNextAction.trim())) { toast.error('عنوان المهمة والنتيجة المتوقعة والإجراء التالي مطلوبة'); return }
    if (targetKind === 'workflow' && !workflowTemplateId) { toast.error('اختر مسار عمل منشور'); return }

    try {
      await createRecurrence.mutateAsync({
        name,
        description: description || null,
        targetKind,
        frequency,
        intervalCount,
        localTime,
        timezone,
        startsOn,
        endsOn: endsOn || null,
        weekdays: frequency === 'weekly' ? weekdays : null,
        monthlyPolicy: frequency === 'monthly' ? monthlyPolicy : null,
        dayOfMonth: frequency === 'monthly' && monthlyPolicy === 'exact_day' ? dayOfMonth : null,
        overlapPolicy,
        taskConfig: targetKind === 'task' ? {
          title: taskTitle,
          expected_outcome: taskOutcome,
          next_action_text: taskNextAction,
          owner_user_id: taskOwner || undefined,
          assignee_user_id: taskAssignee || undefined,
          due_after_minutes: taskDueMinutes === '' ? undefined : taskDueMinutes,
          priority: 'normal',
          visibility: 'standard',
          completion_mode: 'assignee_closes',
        } : {},
        workflowTemplateId: targetKind === 'workflow' ? workflowTemplateId : null,
        workflowVersionPolicy: targetKind === 'workflow' ? workflowVersionPolicy : null,
        workflowInput: {},
        workflowStarterUserId: targetKind === 'workflow' ? (workflowStarterUserId || null) : null,
      })
      toast.success('تم إنشاء الجدول الدوري')
      reset()
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'تعذر إنشاء الجدول الدوري')
    }
  }

  const changeState = async (id: string, version: number, action: 'pause' | 'resume' | 'stop') => {
    try {
      await setState.mutateAsync({ definitionId: id, expectedVersion: version, action })
      toast.success(action === 'pause' ? 'تم إيقاف الجدول مؤقتًا' : action === 'resume' ? 'تم استئناف الجدول' : 'تم إنهاء الجدول الدوري')
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'تعذر تحديث الجدول الدوري')
    }
  }

  if (recurrence.isLoading || workflows.isLoading) return <div className="work-management-loading"><Loader2 className="animate-spin" /> جاري تحميل الأعمال الدورية…</div>
  if (recurrence.error || workflows.error) return <div className="work-management-error"><p>تعذر تحميل الأعمال الدورية.</p></div>

  return (
    <section className="work-management-panel" aria-labelledby="recurrence-management-title">
      <div className="work-management-panel-header">
        <div><h2 id="recurrence-management-title">الأعمال الدورية</h2><p className="page-subtitle">أنشئ دورة مستقلة لكل موعد؛ single-open يسجل التداخل ولا يغيّر موعد مهمة قديمة.</p></div>
        <button type="button" className="btn btn-primary" onClick={() => setShowForm(value => !value)}><Plus size={16} /> جدول دوري</button>
      </div>

      {showForm && <div className="work-management-section">
        <div className="work-management-section-heading"><div><h3>إنشاء جدول دوري</h3><span className="form-hint">كل موعد ينتج Occurrence في الـledger حتى لو تعذر التوليد أو حدث overlap.</span></div></div>
        <form className="work-management-form" onSubmit={submit}>
          <div className="form-group"><label className="form-label required" htmlFor="recurrence-name">الاسم</label><input id="recurrence-name" className="form-input" value={name} onChange={event => setName(event.target.value)} /></div>
          <div className="form-group"><label className="form-label" htmlFor="recurrence-kind">ما الذي يتكرر؟</label><select id="recurrence-kind" className="form-input" value={targetKind} onChange={event => setTargetKind(event.target.value as 'task' | 'workflow')}><option value="task">مهمة</option><option value="workflow">مسار عمل</option></select></div>
          <div className="form-group is-wide"><label className="form-label" htmlFor="recurrence-description">الوصف</label><textarea id="recurrence-description" className="form-input" rows={2} value={description} onChange={event => setDescription(event.target.value)} /></div>

          <div className="form-group"><label className="form-label" htmlFor="recurrence-frequency">التكرار</label><select id="recurrence-frequency" className="form-input" value={frequency} onChange={event => setFrequency(event.target.value as typeof frequency)}><option value="daily">يومي</option><option value="weekly">أسبوعي</option><option value="monthly">شهري</option></select></div>
          <div className="form-group"><label className="form-label" htmlFor="recurrence-interval">كل</label><input id="recurrence-interval" type="number" min={1} className="form-input" dir="ltr" value={intervalCount} onChange={event => setIntervalCount(Number(event.target.value))} /></div>
          <div className="form-group"><label className="form-label" htmlFor="recurrence-time">الساعة المحلية</label><input id="recurrence-time" type="time" className="form-input" dir="ltr" value={localTime} onChange={event => setLocalTime(event.target.value)} /></div>
          <div className="form-group"><label className="form-label" htmlFor="recurrence-timezone">المنطقة الزمنية</label><input id="recurrence-timezone" className="form-input" dir="ltr" value={timezone} onChange={event => setTimezone(event.target.value)} /></div>
          <div className="form-group"><label className="form-label" htmlFor="recurrence-start">يبدأ</label><input id="recurrence-start" type="date" className="form-input" dir="ltr" value={startsOn} onChange={event => setStartsOn(event.target.value)} /></div>
          <div className="form-group"><label className="form-label" htmlFor="recurrence-end">ينتهي</label><input id="recurrence-end" type="date" className="form-input" dir="ltr" value={endsOn} onChange={event => setEndsOn(event.target.value)} /></div>

          {frequency === 'weekly' && <div className="form-group is-wide"><label className="form-label">أيام الأسبوع</label><div className="work-management-meta">{WEEKDAYS.map(day => <label className="perm-checkbox-label" key={day.value}><input type="checkbox" checked={weekdays.includes(day.value)} onChange={() => toggleWeekday(day.value)} /> {day.label}</label>)}</div></div>}
          {frequency === 'monthly' && <><div className="form-group"><label className="form-label" htmlFor="monthly-policy">قاعدة الشهر</label><select id="monthly-policy" className="form-input" value={monthlyPolicy} onChange={event => setMonthlyPolicy(event.target.value as typeof monthlyPolicy)}><option value="exact_day">يوم محدد</option><option value="last_day">آخر يوم في الشهر</option></select></div>{monthlyPolicy === 'exact_day' && <div className="form-group"><label className="form-label" htmlFor="monthly-day">اليوم</label><input id="monthly-day" type="number" min={1} max={31} className="form-input" dir="ltr" value={dayOfMonth} onChange={event => setDayOfMonth(Number(event.target.value))} /></div>}</>}

          <div className="form-group is-wide"><label className="form-label">سياسة التداخل</label><div className="work-management-grid"><label className="work-management-card"><input type="radio" name="overlap" value="strict" checked={overlapPolicy === 'strict'} onChange={() => setOverlapPolicy('strict')} /> <strong>Strict</strong><div className="work-management-card-subtitle">كل موعد يولد عملًا مستقلًا حتى لو ظل السابق مفتوحًا.</div></label><label className="work-management-card"><input type="radio" name="overlap" value="single_open" checked={overlapPolicy === 'single_open'} onChange={() => setOverlapPolicy('single_open')} /> <strong>Single Open</strong><div className="work-management-card-subtitle">إذا ظل عمل سابق مفتوحًا تسجل الدورة الجديدة Overlap بدون تغيير القديم.</div></label></div></div>

          {targetKind === 'task' ? <div className="form-group is-wide"><div className="work-management-section-heading"><h3>قالب المهمة</h3></div><div className="work-management-form"><div className="form-group"><label className="form-label required" htmlFor="rec-task-title">العنوان</label><input id="rec-task-title" className="form-input" value={taskTitle} onChange={event => setTaskTitle(event.target.value)} /></div><div className="form-group"><label className="form-label" htmlFor="rec-task-due">مهلة الإنجاز بالدقائق</label><input id="rec-task-due" type="number" min={1} className="form-input" dir="ltr" value={taskDueMinutes} onChange={event => setTaskDueMinutes(event.target.value ? Number(event.target.value) : '')} /></div><div className="form-group is-wide"><label className="form-label required" htmlFor="rec-task-outcome">النتيجة المتوقعة</label><input id="rec-task-outcome" className="form-input" value={taskOutcome} onChange={event => setTaskOutcome(event.target.value)} /></div><div className="form-group is-wide"><label className="form-label required" htmlFor="rec-task-next">الإجراء التالي</label><input id="rec-task-next" className="form-input" value={taskNextAction} onChange={event => setTaskNextAction(event.target.value)} /></div><div className="form-group"><label className="form-label" htmlFor="rec-task-owner">المسؤول النهائي</label><select id="rec-task-owner" className="form-input" value={taskOwner} onChange={event => setTaskOwner(event.target.value)}><option value="">منشئ الجدول</option>{(users.data ?? []).map(user => <option key={user.user_id} value={user.user_id}>{user.full_name}</option>)}</select></div><div className="form-group"><label className="form-label" htmlFor="rec-task-assignee">المكلف الحالي</label><select id="rec-task-assignee" className="form-input" value={taskAssignee} onChange={event => setTaskAssignee(event.target.value)}><option value="">المسؤول النهائي</option>{(users.data ?? []).map(user => <option key={user.user_id} value={user.user_id}>{user.full_name}</option>)}</select></div></div></div> : <div className="form-group is-wide"><div className="work-management-section-heading"><h3>مصدر مسار العمل</h3></div><div className="work-management-form"><div className="form-group"><label className="form-label required" htmlFor="rec-workflow">المسار المنشور</label><select id="rec-workflow" className="form-input" value={workflowTemplateId} onChange={event => setWorkflowTemplateId(event.target.value)}><option value="">اختر المسار</option>{publishedWorkflows.map(template => <option key={template.id} value={template.id}>{template.name}</option>)}</select></div><div className="form-group"><label className="form-label" htmlFor="rec-version-policy">سياسة النسخة</label><select id="rec-version-policy" className="form-input" value={workflowVersionPolicy} onChange={event => setWorkflowVersionPolicy(event.target.value as typeof workflowVersionPolicy)}><option value="pinned">ثبّت النسخة الحالية</option><option value="latest_published">استخدم أحدث نسخة منشورة وقت الدورة</option></select></div><div className="form-group"><label className="form-label" htmlFor="rec-starter">هوية بدء الـRun</label><select id="rec-starter" className="form-input" value={workflowStarterUserId} onChange={event => setWorkflowStarterUserId(event.target.value)}><option value="">منشئ الجدول</option>{(users.data ?? []).map(user => <option key={user.user_id} value={user.user_id}>{user.full_name}</option>)}</select></div></div></div>}

          <div className="work-management-form-actions"><button type="button" className="btn btn-secondary" onClick={reset}>إلغاء</button><button type="submit" className="btn btn-primary" disabled={createRecurrence.isPending}>{createRecurrence.isPending ? <Loader2 size={16} className="animate-spin" /> : <Plus size={16} />} إنشاء الجدول</button></div>
        </form>
      </div>}

      <div className="work-management-section"><div className="work-management-section-heading"><div><h3>الجداول الحالية</h3><span className="form-hint">{recurrence.data?.length ?? 0} جدول</span></div></div>{(recurrence.data?.length ?? 0) === 0 ? <div className="work-management-empty"><h3>لا توجد أعمال دورية</h3><p>استخدم التكرار للأعمال التي يجب ألا تعتمد على ذاكرة الأفراد.</p></div> : <div className="work-management-grid">{recurrence.data?.map(rule => <article key={rule.id} className="work-management-card"><div className="work-management-card-head"><div><div className="work-management-card-title">{rule.name}</div><div className="work-management-card-subtitle">{rule.target_kind === 'task' ? 'مهمة دورية' : 'Workflow دوري'}</div></div><span className={`work-management-pill ${rule.status === 'active' ? 'is-good' : rule.status === 'paused' ? 'is-warning' : 'is-muted'}`}>{rule.status === 'active' ? 'نشط' : rule.status === 'paused' ? 'متوقف مؤقتًا' : 'منتهي'}</span></div><div className="work-management-meta"><span className="work-management-pill">{frequencyLabel(rule.frequency)} × {rule.interval_count}</span><span className="work-management-pill">{rule.overlap_policy === 'strict' ? 'Strict' : 'Single Open'}</span>{rule.next_occurrence_at && <span className="work-management-pill">التالي {new Date(rule.next_occurrence_at).toLocaleString('en-GB', { dateStyle: 'short', timeStyle: 'short' })}</span>}</div>{rule.status !== 'stopped' && <div className="work-management-actions">{rule.status === 'active' ? <button type="button" className="btn btn-ghost btn-sm" onClick={() => changeState(rule.id, rule.state_version, 'pause')} disabled={setState.isPending}><Pause size={14} /> إيقاف مؤقت</button> : <button type="button" className="btn btn-ghost btn-sm" onClick={() => changeState(rule.id, rule.state_version, 'resume')} disabled={setState.isPending}><Play size={14} /> استئناف</button>}<button type="button" className="btn btn-ghost btn-sm" onClick={() => changeState(rule.id, rule.state_version, 'stop')} disabled={setState.isPending}><Square size={14} /> إنهاء</button></div>}</article>)}</div>}</div>
    </section>
  )
}
