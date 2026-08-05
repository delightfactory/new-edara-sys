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
  addMinutesToTime,
  calculateScheduledMinutes,
  getCairoDateISO,
  getNextCairoDateISO,
  getUniformWorkingDayMinutes,
  isFirstDayOfMonthISO,
  normalizeScheduleTime,
  validateEmployeeWorkSchedule,
} from '@/lib/validations/hrWorkSchedules'
import './EmployeeWorkScheduleTab.css'

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
  employeeOffDay: HRDayOfWeek | null | undefined
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

function scheduleDuration(schedule: HREmployeeWorkSchedule | undefined): number | null {
  if (!schedule) return null
  return schedule.days.find(day => day.is_working_day)?.scheduled_minutes ?? null
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
  if (schedule.effective_from > cairoToday) return 'مخطط'
  if (!schedule.effective_to || schedule.effective_to >= cairoToday) return 'ساري'
  return 'سابق'
}

function scheduleVariant(
  schedule: HREmployeeWorkSchedule,
  cairoToday: string
): 'success' | 'warning' | 'info' {
  const label = scheduleLabel(schedule, cairoToday)
  if (label === 'مخطط') return 'warning'
  if (label === 'ساري') return 'success'
  return 'info'
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
  const featureEnabled = featureQuery.data?.enabled === true

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

    const candidates = [tomorrow, addDaysToISODate(activeSchedule.effective_from, 1)].sort()
    return candidates[candidates.length - 1] ?? tomorrow
  }, [activeSchedule, tomorrow])

  const getBaselineMinutes = (dateISO: string, excludedScheduleId?: string | null): number => {
    const predecessor = schedules
      .filter(schedule => schedule.id !== excludedScheduleId && schedule.effective_from < dateISO)
      .sort((a, b) => b.effective_from.localeCompare(a.effective_from))[0]

    return scheduleDuration(predecessor)
      ?? Math.round((defaultsQuery.data?.work_hours_per_day ?? 0) * 60)
  }

  const resetEditor = () => {
    setEditorOpen(false)
    setEditingScheduleId(null)
    setEffectiveFrom(tomorrow)
    setDays([])
    setNotes('')
    setErrors({})
  }

  const startNewSchedule = () => {
    const defaults = defaultsQuery.data
    if (!defaults) {
      toast.error('تعذر تحميل مواعيد الشركة الافتراضية')
      return
    }

    const template = activeSchedule?.days.length === 7
      ? activeSchedule.days.map(toDayInput)
      : buildCompanyDays(defaults, employee.weekly_off_day)

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
      const nextErrors = { ...validation.errors }
      const proposedMinutes = getUniformWorkingDayMinutes(days)
      const baselineMinutes = getBaselineMinutes(effectiveFrom, editingScheduleId)

      if (
        proposedMinutes !== null
        && baselineMinutes > 0
        && proposedMinutes !== baselineMinutes
        && !isFirstDayOfMonthISO(effectiveFrom)
      ) {
        nextErrors.effective_from = 'تغيير عدد ساعات يوم العمل يجب أن يبدأ من أول يوم في الشهر'
      }

      if (Object.keys(nextErrors).length > 0) {
        setErrors(nextErrors)
        throw new Error('راجع بيانات جدول العمل قبل الحفظ')
      }

      return editingScheduleId
        ? updateFutureEmployeeWorkSchedule(editingScheduleId, days, notes)
        : saveEmployeeWorkSchedule(input)
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
    setDays(current => current.map(day =>
      day.day_of_week === dayName ? { ...day, ...patch } : day
    ))

    setErrors(current => {
      const next = { ...current }
      delete next[`days.${dayName}`]
      delete next.days
      return next
    })
  }

  const toggleDay = (dayName: HRDayOfWeek, checked: boolean) => {
    const defaults = defaultsQuery.data
    const referenceMinutes = getUniformWorkingDayMinutes(days)
      ?? getBaselineMinutes(effectiveFrom, editingScheduleId)
    const startTime = defaults?.start_time ?? null
    const endTime = startTime && referenceMinutes > 0
      ? addMinutesToTime(startTime, referenceMinutes)
      : null

    updateDay(dayName, {
      is_working_day: checked,
      start_time: checked ? startTime : null,
      end_time: checked ? endTime ?? defaults?.end_time ?? null : null,
    })
  }

  if (featureQuery.isLoading) {
    return <div className="employee-work-schedule-loading"><Spinner /></div>
  }

  if (featureQuery.error) {
    return (
      <div className="employee-work-schedule-state employee-work-schedule-state--danger">
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
      <div className="employee-work-schedule-state">
        <ShieldCheck size={22} />
        <div>
          <strong>ميزة جداول العمل الفردية غير مركبة على قاعدة البيانات</strong>
          <p>ستظل مواعيد الشركة الحالية هي المرجع، ولن تتم أي محاولة كتابة.</p>
        </div>
      </div>
    )
  }

  if (defaultsQuery.isLoading || schedulesQuery.isLoading) {
    return <div className="employee-work-schedule-loading"><Spinner /></div>
  }

  if (defaultsQuery.error || schedulesQuery.error) {
    return (
      <div className="employee-work-schedule-state employee-work-schedule-state--danger">
        <AlertCircle size={20} />
        <div>
          <strong>تعذر تحميل جدول العمل</strong>
          <p>لم يتم تغيير أي بيانات. راجع الصلاحيات أو اكتمال ملفات الميجريشن.</p>
        </div>
      </div>
    )
  }

  return (
    <section className="employee-work-schedule-tab">
      <div className={`employee-work-schedule-state ${featureEnabled ? 'employee-work-schedule-state--success' : 'employee-work-schedule-state--warning'}`}>
        <ShieldCheck size={22} />
        <div>
          <strong>
            {featureEnabled
              ? 'جداول الموظفين مفعلة في الحضور والرواتب'
              : 'مرحلة إعداد ومراجعة فقط — التأثير التشغيلي معطل'}
          </strong>
          <p>
            {featureEnabled
              ? 'سيتم الحساب وفق الموعد المثبت لكل موظف ولكل يوم.'
              : 'يمكن تجهيز جدول مستقبلي، لكنه لن يغيّر الحضور أو الجزاءات أو الرواتب قبل قرار التفعيل النهائي.'}
          </p>
        </div>
      </div>

      <div className="employee-work-schedule-header employee-work-schedule-card edara-card">
        <div>
          <h3>مواعيد العمل الأسبوعية</h3>
          <p>موعد مستقل لكل يوم، دون تتبع للراحة أو محرك منفصل للدوام الجزئي.</p>
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
          className="employee-work-schedule-editor employee-work-schedule-card edara-card"
          onSubmit={event => {
            event.preventDefault()
            mutation.mutate()
          }}
        >
          <div className="employee-work-schedule-editor-header">
            <div>
              <h3>{editingScheduleId ? 'تصحيح الجدول المستقبلي' : 'إضافة جدول مستقبلي'}</h3>
              <p>
                {editingScheduleId
                  ? 'يمكن تعديل الأيام والساعات فقط لأن الجدول لم يبدأ ولم يرتبط بحضور.'
                  : 'يبدأ التطبيق في تاريخ مستقبلي ولا يعاد حساب أي يوم سابق.'}
              </p>
            </div>
            <Badge variant="warning">غير مطبق بأثر رجعي</Badge>
          </div>

          <div className="employee-work-schedule-form-grid">
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
              <label className="form-label" htmlFor="employee-work-schedule-notes">
                ملاحظات
              </label>
              <textarea
                id="employee-work-schedule-notes"
                className={`form-input employee-work-schedule-notes ${errors.notes ? 'error' : ''}`}
                value={notes}
                maxLength={500}
                rows={2}
                onChange={event => setNotes(event.target.value)}
                placeholder="سبب تغيير المواعيد أو أي توضيح إداري"
              />
              {errors.notes && <span className="form-error">{errors.notes}</span>}
            </div>
          </div>

          <div className="employee-work-schedule-table-wrap">
            <table className="employee-work-schedule-table">
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
                    <tr
                      key={day.day_of_week}
                      className={rowError ? 'employee-work-schedule-row--error' : ''}
                    >
                      <td data-label="اليوم">
                        <strong>{HR_WORK_WEEK_DAY_LABELS[day.day_of_week]}</strong>
                      </td>
                      <td data-label="يوم عمل">
                        <label className="employee-work-schedule-check">
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
                          className="form-input employee-work-schedule-time"
                          type="time"
                          step={60}
                          value={day.start_time ?? ''}
                          disabled={!day.is_working_day}
                          onChange={event => updateDay(day.day_of_week, { start_time: event.target.value })}
                        />
                      </td>
                      <td data-label="إلى">
                        <input
                          className="form-input employee-work-schedule-time"
                          type="time"
                          step={60}
                          value={day.end_time ?? ''}
                          disabled={!day.is_working_day}
                          onChange={event => updateDay(day.day_of_week, { end_time: event.target.value })}
                        />
                      </td>
                      <td data-label="المدة">
                        {day.is_working_day && duration > 0 ? formatHours(duration) : '—'}
                        {rowError && (
                          <span className="employee-work-schedule-row-error">{rowError}</span>
                        )}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>

          {errors.days && (
            <div className="employee-work-schedule-form-error">{errors.days}</div>
          )}

          <div className="employee-work-schedule-summary">
            <span>
              <Clock3 size={15} /> إجمالي الأسبوع: <strong>{formatHours(weeklyMinutes)}</strong>
            </span>
            <span>
              أيام العمل: <strong>{days.filter(day => day.is_working_day).length}</strong>
            </span>
          </div>

          <div className="employee-work-schedule-actions">
            <Button type="submit" loading={mutation.isPending}>حفظ الجدول</Button>
            <Button
              type="button"
              variant="secondary"
              onClick={resetEditor}
              disabled={mutation.isPending}
            >
              إلغاء
            </Button>
          </div>
        </form>
      )}

      <div className="employee-work-schedule-history">
        {schedules.length === 0 ? (
          <div className="employee-work-schedule-empty edara-card">
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
            <article
              key={schedule.id}
              className="employee-work-schedule-history-card employee-work-schedule-card edara-card"
            >
              <div className="employee-work-schedule-history-header">
                <div>
                  <div className="employee-work-schedule-history-title">
                    <CalendarClock size={17} />
                    من {formatDate(schedule.effective_from)} إلى {formatDate(schedule.effective_to)}
                  </div>
                  <div className="employee-work-schedule-history-meta">
                    {schedule.days.filter(day => day.is_working_day).length} أيام عمل · {formatHours(totalMinutes)} أسبوعيًا
                  </div>
                </div>

                <div className="employee-work-schedule-history-actions">
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

              <div className="employee-work-schedule-days">
                {schedule.days.map(day => (
                  <div
                    key={day.day_of_week}
                    className={`employee-work-schedule-day ${day.is_working_day ? '' : 'employee-work-schedule-day--off'}`}
                  >
                    <span>{HR_WORK_WEEK_DAY_LABELS[day.day_of_week]}</span>
                    <strong>
                      {day.is_working_day
                        ? `${normalizeScheduleTime(day.start_time)} – ${normalizeScheduleTime(day.end_time)}`
                        : 'إجازة'}
                    </strong>
                  </div>
                ))}
              </div>

              {schedule.notes && (
                <p className="employee-work-schedule-history-notes">{schedule.notes}</p>
              )}
            </article>
          )
        })}
      </div>

      {futureSchedule && !featureEnabled && (
        <div className="employee-work-schedule-state employee-work-schedule-state--warning">
          <AlertCircle size={20} />
          <div>
            <strong>يوجد جدول مستقبلي محفوظ لكنه غير فعال تشغيليًا</strong>
            <p>لن يبدأ تأثيره قبل اجتياز المحاكاة وفتح قفل التفعيل بقرار مستقل.</p>
          </div>
        </div>
      )}
    </section>
  )
}
