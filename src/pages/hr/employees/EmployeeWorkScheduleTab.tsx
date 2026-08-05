import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { AlertCircle, CalendarClock, Clock3, Pencil, Plus, ShieldCheck } from 'lucide-react'
import { toast } from 'sonner'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import Input from '@/components/ui/Input'
import Spinner from '@/components/ui/Spinner'
import { useAuthStore } from '@/stores/auth-store'
import type { HREmployee, HRDayOfWeek } from '@/lib/types/hr'
import {
  HR_WORK_WEEK_DAYS,
  HR_WORK_WEEK_DAY_LABELS,
  type HRCompanyWorkScheduleDefaults,
  type HREmployeeWorkSchedule,
  type HREmployeeWorkScheduleDayInput,
} from '@/lib/types/hrWorkSchedules'
import {
  getCompanyWorkScheduleDefaults,
  getEmployeeWorkSchedules,
  getWorkScheduleFeatureState,
  saveEmployeeWorkSchedule,
  updateFutureEmployeeWorkSchedule,
} from '@/lib/services/hrWorkSchedules'
import {
  addDaysToISODate,
  calculateScheduledMinutes,
  getCairoDateISO,
  getNextCairoDateISO,
  normalizeScheduleTime,
  validateEmployeeWorkSchedule,
} from '@/lib/validations/hrWorkSchedules'

interface EmployeeWorkScheduleTabProps {
  employee: Pick<
    HREmployee,
    'id' | 'full_name' | 'status' | 'hire_date' | 'termination_date' | 'weekly_off_day'
  >
}

const queryKeys = {
  feature: ['hr', 'employee-work-schedules', 'feature'] as const,
  defaults: ['hr', 'employee-work-schedules', 'company-defaults'] as const,
  employee: (employeeId: string) => ['hr', 'employee-work-schedules', employeeId] as const,
}

function toDayInput(
  day: HREmployeeWorkSchedule['days'][number]
): HREmployeeWorkScheduleDayInput {
  return {
    day_of_week: day.day_of_week,
    is_working_day: day.is_working_day,
    start_time: normalizeScheduleTime(day.start_time),
    end_time: normalizeScheduleTime(day.end_time),
  }
}

function buildCompanyDays(
  defaults: HRCompanyWorkScheduleDefaults,
  employeeOffDay: HRDayOfWeek | null
): HREmployeeWorkScheduleDayInput[] {
  const weeklyOff = employeeOffDay ?? defaults.weekly_off_day

  return HR_WORK_WEEK_DAYS.map(day => {
    const isWorkingDay = day !== weeklyOff
    return {
      day_of_week: day,
      is_working_day: isWorkingDay,
      start_time: isWorkingDay ? defaults.start_time : null,
      end_time: isWorkingDay ? defaults.end_time : null,
    }
  })
}

function formatDate(value: string | null): string {
  if (!value) return 'مستمر'
  return new Date(`${value}T12:00:00Z`).toLocaleDateString('ar-EG-u-nu-latn', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  })
}

function formatHours(minutes: number): string {
  const hours = minutes / 60
  return Number.isInteger(hours) ? `${hours} ساعة` : `${hours.toFixed(1)} ساعة`
}

function scheduleLabel(schedule: HREmployeeWorkSchedule, cairoToday: string): string {
  if (schedule.status === 'retired') return 'سابق'
  if (schedule.effective_from > cairoToday) return 'مخطط'
  return 'ساري'
}

function scheduleVariant(
  schedule: HREmployeeWorkSchedule,
  cairoToday: string
): 'success' | 'warning' | 'info' {
  if (schedule.status === 'retired') return 'info'
  if (schedule.effective_from > cairoToday) return 'warning'
  return 'success'
}

export default function EmployeeWorkScheduleTab({ employee }: EmployeeWorkScheduleTabProps) {
  const can = useAuthStore(state => state.can)
  const queryClient = useQueryClient()
  const cairoToday = getCairoDateISO()
  const tomorrow = getNextCairoDateISO()
  const canEdit = can('hr.employees.edit') && employee.status !== 'terminated'

  const [editorOpen, setEditorOpen] = useState(false)
  const [editingScheduleId, setEditingScheduleId] = useState<string | null>(null)
  const [effectiveFrom, setEffectiveFrom] = useState(tomorrow)
  const [days, setDays] = useState<HREmployeeWorkScheduleDayInput[]>([])
  const [notes, setNotes] = useState('')
  const [errors, setErrors] = useState<Record<string, string>>({})

  const featureQuery = useQuery({
    queryKey: queryKeys.feature,
    queryFn: getWorkScheduleFeatureState,
    staleTime: 60_000,
  })

  const installed = featureQuery.data?.installed === true

  const defaultsQuery = useQuery({
    queryKey: queryKeys.defaults,
    queryFn: getCompanyWorkScheduleDefaults,
    enabled: installed,
    staleTime: 5 * 60_000,
  })

  const schedulesQuery = useQuery({
    queryKey: queryKeys.employee(employee.id),
    queryFn: () => getEmployeeWorkSchedules(employee.id),
    enabled: installed,
  })

  const schedules = schedulesQuery.data ?? []
  const activeSchedule = schedules.find(schedule => schedule.status === 'active')
  const futureSchedule = schedules.find(
    schedule => schedule.status === 'active' && schedule.effective_from > cairoToday
  )

  const weeklyMinutes = useMemo(
    () => days.reduce((total, day) => total + calculateScheduledMinutes(day), 0),
    [days]
  )

  const minimumNewDate = useMemo(() => {
    if (!activeSchedule) return tomorrow
    return [tomorrow, addDaysToISODate(activeSchedule.effective_from, 1)].sort().at(-1) ?? tomorrow
  }, [activeSchedule, tomorrow])

  const resetEditor = () => {
    setEditorOpen(false)
    setEditingScheduleId(null)
    setEffectiveFrom(tomorrow)
    setDays([])
    setNotes('')
    setErrors({})
  }

  const startNewSchedule = () => {
    if (!defaultsQuery.data) {
      toast.error('تعذر تحميل مواعيد الشركة الافتراضية')
      return
    }

    const template = activeSchedule?.days.length === 7
      ? activeSchedule.days.map(toDayInput)
      : buildCompanyDays(defaultsQuery.data, employee.weekly_off_day)

    setEditingScheduleId(null)
    setEffectiveFrom(minimumNewDate)
    setDays(template)
    setNotes('')
    setErrors({})
    setEditorOpen(true)
  }

  const startFutureEdit = (schedule: HREmployeeWorkSchedule) => {
    setEditingScheduleId(schedule.id)
    setEffectiveFrom(schedule.effective_from)
    setDays(schedule.days.map(toDayInput))
    setNotes(schedule.notes ?? '')
    setErrors({})
    setEditorOpen(true)
  }

  const mutation = useMutation({
    mutationFn: async () => {
      const input = {
        employee_id: employee.id,
        effective_from: effectiveFrom,
        days,
        notes: notes.trim() || null,
      }

      const validation = validateEmployeeWorkSchedule(input, cairoToday)
      if (!validation.valid) {
        setErrors(validation.errors)
        throw new Error('راجع بيانات جدول العمل قبل الحفظ')
      }

      if (editingScheduleId) {
        return updateFutureEmployeeWorkSchedule(editingScheduleId, days, notes)
      }

      return saveEmployeeWorkSchedule(input)
    },
    onSuccess: async result => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.employee(employee.id) })
      toast.success(
        result.feature_enabled
          ? 'تم حفظ جدول العمل وسيُطبق في التاريخ المحدد'
          : 'تم حفظ جدول العمل للمراجعة، ولن يؤثر على الحضور قبل التفعيل النهائي'
      )
      resetEditor()
    },
    onError: error => {
      if (error instanceof Error && error.message !== 'راجع بيانات جدول العمل قبل الحفظ') {
        toast.error(error.message)
      }
    },
  })

  const updateDay = (
    dayName: HRDayOfWeek,
    patch: Partial<HREmployeeWorkScheduleDayInput>
  ) => {
    setDays(current => current.map(day => {
      if (day.day_of_week !== dayName) return day
      return { ...day, ...patch }
    }))
    setErrors(current => {
      const next = { ...current }
      delete next[`days.${dayName}`]
      delete next.days
      return next
    })
  }

  const toggleDay = (dayName: HRDayOfWeek, checked: boolean) => {
    const defaults = defaultsQuery.data
    updateDay(dayName, {
      is_working_day: checked,
      start_time: checked ? defaults?.start_time ?? null : null,
      end_time: checked ? defaults?.end_time ?? null : null,
    })
  }

  if (featureQuery.isLoading) {
    return (
      <div className="ews-loading"><Spinner /></div>
    )
  }

  if (featureQuery.error) {
    return (
      <div className="ews-state ews-state--danger">
        <AlertCircle size={20} />
        <div>
          <strong>تعذر التحقق من إعدادات جداول العمل</strong>
          <p>لم يتم تنفيذ أي تغيير. أعد المحاولة بعد مراجعة الاتصال.</p>
        </div>
      </div>
    )
  }

  if (!installed) {
    return (
      <div className="ews-state">
        <ShieldCheck size={22} />
        <div>
          <strong>ميزة جداول العمل الفردية غير مركبة على قاعدة البيانات</strong>
          <p>لا توجد أي محاولة كتابة أو افتراض بديل. ستظل مواعيد الشركة الحالية هي المرجع.</p>
        </div>
      </div>
    )
  }

  if (defaultsQuery.isLoading || schedulesQuery.isLoading) {
    return <div className="ews-loading"><Spinner /></div>
  }

  if (defaultsQuery.error || schedulesQuery.error) {
    return (
      <div className="ews-state ews-state--danger">
        <AlertCircle size={20} />
        <div>
          <strong>تعذر تحميل جدول العمل</strong>
          <p>لم يتم تغيير أي بيانات. راجع الصلاحيات أو اكتمال ملفات الميجريشن.</p>
        </div>
      </div>
    )
  }

  return (
    <section className="ews-root">
      <div className={`ews-state ${featureQuery.data.enabled ? 'ews-state--success' : 'ews-state--warning'}`}>
        <ShieldCheck size={22} />
        <div>
          <strong>
            {featureQuery.data.enabled
              ? 'جداول الموظفين مفعلة في الحضور والرواتب'
              : 'مرحلة إعداد ومراجعة فقط — التأثير التشغيلي معطل'}
          </strong>
          <p>
            {featureQuery.data.enabled
              ? 'سيتم الحساب وفق مواعيد كل موظف المثبتة لكل يوم.'
              : 'يمكن تجهيز جدول مستقبلي، لكنه لن يغيّر الحضور أو الجزاءات أو الرواتب قبل قرار التفعيل النهائي.'}
          </p>
        </div>
      </div>

      <div className="ews-header edara-card">
        <div>
          <h3>مواعيد العمل الأسبوعية</h3>
          <p>موعد مستقل لكل يوم، دون تتبع للراحة أو تصنيف منفصل للدوام الجزئي.</p>
        </div>
        {canEdit && (
          <Button
            size="sm"
            icon={<Plus size={15} />}
            onClick={startNewSchedule}
            disabled={!defaultsQuery.data || mutation.isPending}
          >
            جدول مستقبلي جديد
          </Button>
        )}
      </div>

      {editorOpen && (
        <form
          className="ews-editor edara-card"
          onSubmit={event => {
            event.preventDefault()
            mutation.mutate()
          }}
        >
          <div className="ews-editor-head">
            <div>
              <h3>{editingScheduleId ? 'تصحيح الجدول المستقبلي' : 'إضافة جدول مستقبلي'}</h3>
              <p>
                {editingScheduleId
                  ? 'يمكن تعديل الأيام والساعات فقط لأن الجدول لم يبدأ ولم يرتبط بحضور.'
                  : 'يبدأ التطبيق في تاريخ مستقبلي، ولا يعاد حساب أي يوم سابق.'}
              </p>
            </div>
            <Badge variant="warning">غير مطبق بأثر رجعي</Badge>
          </div>

          <div className="ews-form-grid">
            <Input
              type="date"
              label="تاريخ بدء التطبيق"
              value={effectiveFrom}
              min={editingScheduleId ? effectiveFrom : minimumNewDate}
              disabled={Boolean(editingScheduleId)}
              error={errors.effective_from}
              required
              onChange={event => {
                setEffectiveFrom(event.target.value)
                setErrors(current => {
                  const next = { ...current }
                  delete next.effective_from
                  return next
                })
              }}
            />
            <div className="form-group">
              <label className="form-label" htmlFor="employee-work-schedule-notes">ملاحظات</label>
              <textarea
                id="employee-work-schedule-notes"
                className={`form-input ews-notes ${errors.notes ? 'error' : ''}`}
                value={notes}
                maxLength={500}
                rows={2}
                onChange={event => setNotes(event.target.value)}
                placeholder="سبب تغيير المواعيد أو أي توضيح إداري"
              />
              {errors.notes && <span className="form-error">{errors.notes}</span>}
            </div>
          </div>

          <div className="ews-table-wrap">
            <table className="ews-table">
              <thead>
                <tr>
                  <th>اليوم</th>
                  <th>يوم عمل</th>
                  <th>من</th>
                  <th>إلى</th>
                  <th>المدة</th>
                </tr>
              </thead>
              <tbody>
                {days.map(day => {
                  const rowError = errors[`days.${day.day_of_week}`]
                  const duration = calculateScheduledMinutes(day)
                  return (
                    <tr key={day.day_of_week} className={rowError ? 'ews-row--error' : ''}>
                      <td data-label="اليوم"><strong>{HR_WORK_WEEK_DAY_LABELS[day.day_of_week]}</strong></td>
                      <td data-label="يوم عمل">
                        <label className="ews-check">
                          <input
                            type="checkbox"
                            checked={day.is_working_day}
                            onChange={event => toggleDay(day.day_of_week, event.target.checked)}
                          />
                          <span>{day.is_working_day ? 'عمل' : 'إجازة'}</span>
                        </label>
                      </td>
                      <td data-label="من">
                        <input
                          className="form-input ews-time"
                          type="time"
                          step={60}
                          value={day.start_time ?? ''}
                          disabled={!day.is_working_day}
                          onChange={event => updateDay(day.day_of_week, { start_time: event.target.value })}
                        />
                      </td>
                      <td data-label="إلى">
                        <input
                          className="form-input ews-time"
                          type="time"
                          step={60}
                          value={day.end_time ?? ''}
                          disabled={!day.is_working_day}
                          onChange={event => updateDay(day.day_of_week, { end_time: event.target.value })}
                        />
                      </td>
                      <td data-label="المدة">
                        {day.is_working_day && duration > 0 ? formatHours(duration) : '—'}
                        {rowError && <span className="ews-row-error">{rowError}</span>}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>

          {errors.days && <div className="ews-form-error">{errors.days}</div>}

          <div className="ews-summary">
            <span><Clock3 size={15} /> إجمالي الأسبوع: <strong>{formatHours(weeklyMinutes)}</strong></span>
            <span>أيام العمل: <strong>{days.filter(day => day.is_working_day).length}</strong></span>
          </div>

          <div className="ews-actions">
            <Button type="submit" loading={mutation.isPending}>حفظ الجدول</Button>
            <Button type="button" variant="secondary" onClick={resetEditor} disabled={mutation.isPending}>
              إلغاء
            </Button>
          </div>
        </form>
      )}

      <div className="ews-list">
        {schedules.length === 0 ? (
          <div className="ews-empty edara-card">
            <CalendarClock size={32} />
            <h3>لا يوجد جدول فردي محفوظ</h3>
            <p>يستمر الموظف حاليًا على مواعيد الشركة ويوم الإجازة المحدد في ملفه.</p>
          </div>
        ) : schedules.map(schedule => {
          const totalMinutes = schedule.days.reduce(
            (total, day) => total + day.scheduled_minutes,
            0
          )
          const editable = canEdit
            && schedule.status === 'active'
            && schedule.effective_from > cairoToday

          return (
            <article key={schedule.id} className="ews-card edara-card">
              <div className="ews-card-head">
                <div>
                  <div className="ews-card-title">
                    <CalendarClock size={17} />
                    من {formatDate(schedule.effective_from)} إلى {formatDate(schedule.effective_to)}
                  </div>
                  <div className="ews-card-meta">
                    {schedule.days.filter(day => day.is_working_day).length} أيام عمل · {formatHours(totalMinutes)} أسبوعيًا
                  </div>
                </div>
                <div className="ews-card-actions">
                  <Badge variant={scheduleVariant(schedule, cairoToday)}>
                    {scheduleLabel(schedule, cairoToday)}
                  </Badge>
                  {editable && (
                    <Button
                      variant="secondary"
                      size="sm"
                      icon={<Pencil size={14} />}
                      onClick={() => startFutureEdit(schedule)}
                    >
                      تصحيح
                    </Button>
                  )}
                </div>
              </div>

              <div className="ews-days-preview">
                {schedule.days.map(day => (
                  <div key={day.day_of_week} className={`ews-day ${day.is_working_day ? '' : 'ews-day--off'}`}>
                    <span>{HR_WORK_WEEK_DAY_LABELS[day.day_of_week]}</span>
                    <strong>
                      {day.is_working_day
                        ? `${normalizeScheduleTime(day.start_time)} – ${normalizeScheduleTime(day.end_time)}`
                        : 'إجازة'}
                    </strong>
                  </div>
                ))}
              </div>

              {schedule.notes && <p className="ews-card-notes">{schedule.notes}</p>}
            </article>
          )
        })}
      </div>

      {futureSchedule && !featureQuery.data.enabled && (
        <div className="ews-state ews-state--warning">
          <AlertCircle size={20} />
          <div>
            <strong>يوجد جدول مستقبلي محفوظ لكنه غير فعال تشغيليًا</strong>
            <p>لن يبدأ تأثيره قبل تطبيق جميع الميجريشنات واجتياز المحاكاة وفتح قفل التفعيل بقرار مستقل.</p>
          </div>
        </div>
      )}

      <style>{`
        .ews-root { display: flex; flex-direction: column; gap: var(--space-4); }
        .ews-loading { display: flex; justify-content: center; padding: var(--space-10); }
        .ews-state {
          display: flex; gap: var(--space-3); align-items: flex-start;
          padding: var(--space-4); border: 1px solid var(--border-primary);
          border-radius: var(--radius-lg); background: var(--bg-surface);
        }
        .ews-state svg { flex-shrink: 0; color: var(--color-primary); margin-top: 2px; }
        .ews-state strong { display: block; color: var(--text-primary); margin-bottom: 4px; }
        .ews-state p { margin: 0; color: var(--text-secondary); font-size: var(--text-sm); }
        .ews-state--warning { border-color: color-mix(in srgb, var(--color-warning) 45%, var(--border-primary)); background: color-mix(in srgb, var(--color-warning) 7%, var(--bg-surface)); }
        .ews-state--warning svg { color: var(--color-warning); }
        .ews-state--success { border-color: color-mix(in srgb, var(--color-success) 45%, var(--border-primary)); background: color-mix(in srgb, var(--color-success) 7%, var(--bg-surface)); }
        .ews-state--success svg { color: var(--color-success); }
        .ews-state--danger { border-color: color-mix(in srgb, var(--color-danger) 45%, var(--border-primary)); }
        .ews-state--danger svg { color: var(--color-danger); }
        .ews-header, .ews-editor, .ews-card, .ews-empty { padding: var(--space-5); }
        .ews-header { display: flex; justify-content: space-between; gap: var(--space-3); align-items: center; }
        .ews-header h3, .ews-editor h3, .ews-empty h3 { margin: 0 0 4px; color: var(--text-primary); }
        .ews-header p, .ews-editor p, .ews-empty p { margin: 0; color: var(--text-secondary); font-size: var(--text-sm); }
        .ews-editor { display: flex; flex-direction: column; gap: var(--space-4); }
        .ews-editor-head { display: flex; justify-content: space-between; gap: var(--space-3); align-items: flex-start; }
        .ews-form-grid { display: grid; grid-template-columns: minmax(220px, 320px) minmax(280px, 1fr); gap: var(--space-4); }
        .ews-notes { min-height: 74px; resize: vertical; font-family: var(--font-sans); }
        .ews-table-wrap { overflow-x: auto; border: 1px solid var(--border-primary); border-radius: var(--radius-lg); }
        .ews-table { width: 100%; border-collapse: collapse; min-width: 680px; }
        .ews-table th, .ews-table td { padding: var(--space-3); text-align: start; border-bottom: 1px solid var(--border-primary); }
        .ews-table th { background: var(--bg-surface-2); font-size: var(--text-xs); color: var(--text-muted); }
        .ews-table tr:last-child td { border-bottom: 0; }
        .ews-row--error { background: color-mix(in srgb, var(--color-danger) 5%, transparent); }
        .ews-time { min-width: 120px; direction: ltr; }
        .ews-check { display: inline-flex; align-items: center; gap: 8px; cursor: pointer; white-space: nowrap; }
        .ews-check input { width: 18px; height: 18px; accent-color: var(--color-primary); }
        .ews-row-error { display: block; margin-top: 4px; color: var(--color-danger); font-size: var(--text-xs); max-width: 240px; }
        .ews-form-error { color: var(--color-danger); font-size: var(--text-sm); }
        .ews-summary { display: flex; flex-wrap: wrap; gap: var(--space-4); color: var(--text-secondary); font-size: var(--text-sm); }
        .ews-summary span { display: inline-flex; gap: 6px; align-items: center; }
        .ews-actions { display: flex; gap: var(--space-2); justify-content: flex-end; }
        .ews-list { display: flex; flex-direction: column; gap: var(--space-3); }
        .ews-card { display: flex; flex-direction: column; gap: var(--space-4); }
        .ews-card-head { display: flex; justify-content: space-between; gap: var(--space-3); align-items: flex-start; }
        .ews-card-title { display: flex; align-items: center; gap: 7px; font-weight: 700; color: var(--text-primary); }
        .ews-card-meta { margin-top: 5px; color: var(--text-muted); font-size: var(--text-xs); }
        .ews-card-actions { display: flex; gap: var(--space-2); align-items: center; flex-wrap: wrap; }
        .ews-days-preview { display: grid; grid-template-columns: repeat(7, minmax(105px, 1fr)); gap: var(--space-2); overflow-x: auto; }
        .ews-day { min-width: 105px; padding: var(--space-3); border-radius: var(--radius-md); background: var(--bg-surface-2); border: 1px solid var(--border-primary); }
        .ews-day span { display: block; font-size: var(--text-xs); color: var(--text-muted); margin-bottom: 5px; }
        .ews-day strong { direction: ltr; display: block; font-size: var(--text-xs); color: var(--text-primary); white-space: nowrap; }
        .ews-day--off { opacity: 0.65; }
        .ews-card-notes { margin: 0; padding-top: var(--space-3); border-top: 1px solid var(--border-primary); color: var(--text-secondary); font-size: var(--text-sm); }
        .ews-empty { text-align: center; color: var(--text-muted); }
        .ews-empty svg { margin-bottom: var(--space-2); }
        @media (max-width: 700px) {
          .ews-header, .ews-editor-head, .ews-card-head { flex-direction: column; align-items: stretch; }
          .ews-form-grid { grid-template-columns: 1fr; }
          .ews-actions { justify-content: stretch; }
          .ews-actions button { flex: 1; }
          .ews-table-wrap { overflow: visible; border: 0; }
          .ews-table { min-width: 0; }
          .ews-table thead { display: none; }
          .ews-table, .ews-table tbody, .ews-table tr, .ews-table td { display: block; width: 100%; }
          .ews-table tr { border: 1px solid var(--border-primary); border-radius: var(--radius-lg); margin-bottom: var(--space-3); padding: var(--space-2); }
          .ews-table td { display: grid; grid-template-columns: 92px 1fr; gap: var(--space-2); align-items: center; border: 0; padding: var(--space-2); }
          .ews-table td::before { content: attr(data-label); color: var(--text-muted); font-size: var(--text-xs); font-weight: 600; }
          .ews-time { min-width: 0; width: 100%; }
          .ews-days-preview { grid-template-columns: repeat(7, 110px); }
        }
      `}</style>
    </section>
  )
}
