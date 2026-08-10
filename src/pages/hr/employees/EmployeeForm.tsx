import { useState, useEffect, useCallback } from 'react'
import { UserPlus, UserCog, Link, AlertCircle } from 'lucide-react'
import type {
  HREmployee, HREmployeeInput, HREmployeeWorkScheduleDay,
  HRGender, HRMaritalStatus, HRDayOfWeek, HRAttendancePolicyMode,
} from '@/lib/types/hr'
import {
  useHRDepartments,
  useHRPositions,
  useHRWorkLocations,
  useCreateEmployee,
  useUpdateEmployee,
} from '@/hooks/useQueryHooks'
import {
  getEmployeeWeeklySchedule,
  linkEmployeeToUser,
  setEmployeeWeeklySchedule,
} from '@/lib/services/hr'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import Button from '@/components/ui/Button'
import Input from '@/components/ui/Input'
import Select from '@/components/ui/Select'
import AsyncCombobox from '@/components/ui/AsyncCombobox'
import type { ComboboxOption } from '@/components/ui/AsyncCombobox'

// ─── helpers ────────────────────────────────────────────────

type ToastFn = (msg: string, type?: 'success' | 'warning' | 'error') => void

interface Props {
  open: boolean
  onClose: () => void
  employee?: HREmployee | null   // null = إضافة، HREmployee = تعديل
  onToast: ToastFn
}

// الحالة الأولية للنموذج
const EMPTY_FORM: HREmployeeInput = {
  full_name: '',
  personal_phone: '',
  hire_date: new Date().toISOString().split('T')[0],
  base_salary: 0,
  transport_allowance: 0,
  housing_allowance: 0,
  other_allowances: 0,
  is_field_employee: false,
  status: 'active',
  attendance_checkin_mode: 'assigned_only',
  attendance_checkout_mode: 'assigned_only',
  allowed_checkin_location_ids: [],
  allowed_checkout_location_ids: [],
}

const WEEK_DAYS: { value: HRDayOfWeek; label: string }[] = [
  { value: 'saturday',  label: 'السبت' },
  { value: 'sunday',    label: 'الأحد' },
  { value: 'monday',    label: 'الإثنين' },
  { value: 'tuesday',   label: 'الثلاثاء' },
  { value: 'wednesday', label: 'الأربعاء' },
  { value: 'thursday',  label: 'الخميس' },
  { value: 'friday',    label: 'الجمعة' },
]

function defaultWeeklySchedule(): HREmployeeWorkScheduleDay[] {
  return WEEK_DAYS.map(day => ({
    day_of_week: day.value,
    is_working_day: day.value !== 'friday',
    start_time: day.value === 'friday' ? null : '08:00',
    end_time: day.value === 'friday' ? null : '17:00',
  }))
}

function tomorrowDateInput(): string {
  const parts = new Intl.DateTimeFormat('en', {
    timeZone: 'Africa/Cairo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date())
  const getPart = (type: Intl.DateTimeFormatPartTypes) => (
    Number(parts.find(part => part.type === type)?.value)
  )
  const cairoTomorrow = new Date(Date.UTC(
    getPart('year'),
    getPart('month') - 1,
    getPart('day') + 1,
  ))
  return cairoTomorrow.toISOString().slice(0, 10)
}

function normalizeScheduleTime(value: string | null): string | null {
  return value ? value.slice(0, 5) : null
}

// تحويل موظف موجود إلى HREmployeeInput (بدون الحقول المحسوبة!)
function employeeToInput(emp: HREmployee): HREmployeeInput {
  return {
    full_name:          emp.full_name,
    full_name_en:       emp.full_name_en ?? undefined,
    national_id:        emp.national_id ?? undefined,
    birth_date:         emp.birth_date ?? undefined,
    gender:             emp.gender ?? undefined,
    marital_status:     emp.marital_status ?? undefined,
    address:            emp.address ?? undefined,
    personal_phone:     emp.personal_phone,
    emergency_phone:    emp.emergency_phone ?? undefined,
    emergency_contact:  emp.emergency_contact ?? undefined,
    department_id:      emp.department_id ?? undefined,
    position_id:        emp.position_id ?? undefined,
    branch_id:          emp.branch_id ?? undefined,
    direct_manager_id:  emp.direct_manager_id ?? undefined,
    status:             emp.status,
    hire_date:          emp.hire_date,
    probation_end_date: emp.probation_end_date ?? undefined,
    termination_date:   emp.termination_date ?? undefined,
    termination_reason: emp.termination_reason ?? undefined,
    weekly_off_day:     emp.weekly_off_day ?? undefined,
    is_field_employee:  emp.is_field_employee,
    work_location_id:   emp.work_location_id ?? undefined,
    attendance_checkin_mode: emp.attendance_checkin_mode,
    attendance_checkout_mode: emp.attendance_checkout_mode,
    allowed_checkin_location_ids: emp.allowed_checkin_location_ids ?? [],
    allowed_checkout_location_ids: emp.allowed_checkout_location_ids ?? [],
    base_salary:        emp.base_salary,
    transport_allowance: emp.transport_allowance,
    housing_allowance:  emp.housing_allowance,
    other_allowances:   emp.other_allowances,
    notes:              emp.notes ?? undefined,
  }
}

// ─── Component ────────────────────────────────────────────────

export default function EmployeeForm({ open, onClose, employee, onToast }: Props) {
  const isEdit = !!employee

  const [form, setForm] = useState<HREmployeeInput>(EMPTY_FORM)
  const [authEmail, setAuthEmail] = useState('')   // حقل الربط الاختياري
  const [useCustomSchedule, setUseCustomSchedule] = useState(false)
  const [weeklySchedule, setWeeklySchedule] = useState<HREmployeeWorkScheduleDay[]>(defaultWeeklySchedule)
  const [scheduleEffectiveFrom, setScheduleEffectiveFrom] = useState(tomorrowDateInput)
  const [loadedScheduleEffectiveFrom, setLoadedScheduleEffectiveFrom] = useState<string | null>(null)
  const [scheduleDirty, setScheduleDirty] = useState(false)
  const [scheduleLoading, setScheduleLoading] = useState(false)
  const [scheduleLoadError, setScheduleLoadError] = useState('')
  const [scheduleError, setScheduleError] = useState('')
  const [savingSchedule, setSavingSchedule] = useState(false)
  const [activeStepIndex, setActiveStepIndex] = useState(0)
  const steps = [
    { id: 'basic',  label: 'البيانات الشخصية' },
    { id: 'job',    label: 'بيانات التوظيف' },
    { id: 'salary', label: 'الراتب والبدلات' },
    { id: 'schedule', label: 'جدول العمل' },
  ] as const
  const activeTab = steps[activeStepIndex].id
  const [errors, setErrors] = useState<Partial<Record<keyof HREmployeeInput, string>>>({})

  const createMut = useCreateEmployee()
  const updateMut = useUpdateEmployee()
  const loading = createMut.isPending || updateMut.isPending || savingSchedule || scheduleLoading

  // ── جلب بيانات الرجوع ──────────────────
  const { data: departments = [] } = useHRDepartments()
  const { data: positions = [] }   = useHRPositions(form.department_id ?? undefined)
  const { data: workLocations = [] } = useHRWorkLocations()

  // ── مزامنة النموذج عند الفتح ──────────
  useEffect(() => {
    if (open) {
      setForm(isEdit ? employeeToInput(employee!) : EMPTY_FORM)
      setAuthEmail('')
      setUseCustomSchedule(false)
      setWeeklySchedule(defaultWeeklySchedule())
      setScheduleEffectiveFrom(tomorrowDateInput())
      setLoadedScheduleEffectiveFrom(null)
      setScheduleDirty(false)
      setScheduleLoadError('')
      setScheduleError('')
      setActiveStepIndex(0)
      setErrors({})
      setTabErrors({})
    }
  }, [open, isEdit, employee])

  useEffect(() => {
    if (!open) return

    let cancelled = false
    setScheduleLoading(true)
    setScheduleLoadError('')

    getEmployeeWeeklySchedule(employee?.id)
      .then(result => {
        if (cancelled) return
        setUseCustomSchedule(result.has_custom_schedule)
        setLoadedScheduleEffectiveFrom(result.effective_from)
        setScheduleEffectiveFrom(
          result.effective_from && result.effective_from >= tomorrowDateInput()
            ? result.effective_from
            : tomorrowDateInput()
        )
        setWeeklySchedule(result.schedule.map(day => ({
          ...day,
          start_time: normalizeScheduleTime(day.start_time),
          end_time: normalizeScheduleTime(day.end_time),
        })))
        setScheduleDirty(false)
      })
      .catch(() => {
        if (!cancelled) {
          setScheduleLoadError('تعذّر تحميل جدول العمل الحالي. أغلق النموذج وأعد فتحه قبل الحفظ.')
        }
      })
      .finally(() => {
        if (!cancelled) setScheduleLoading(false)
      })

    return () => { cancelled = true }
  }, [open, employee])

  const set = <K extends keyof HREmployeeInput>(key: K) =>
    (val: HREmployeeInput[K] | null) =>
      setForm(prev => ({ ...prev, [key]: val === null ? undefined : val }))

  const toggleLocation = (key: 'allowed_checkin_location_ids' | 'allowed_checkout_location_ids', locationId: string) => {
    setForm(prev => {
      const current = prev[key] ?? []
      const next = current.includes(locationId)
        ? current.filter(id => id !== locationId)
        : [...current, locationId]
      return { ...prev, [key]: next }
    })
  }

  const updateScheduleDay = (
    day: HRDayOfWeek,
    patch: Partial<HREmployeeWorkScheduleDay>
  ) => {
    setWeeklySchedule(current => current.map(item => {
      if (item.day_of_week !== day) return item
      const next = { ...item, ...patch }
      if (patch.is_working_day === false) {
        next.start_time = null
        next.end_time = null
      } else if (patch.is_working_day === true) {
        const reference = current.find(candidate => (
          candidate.is_working_day && candidate.start_time && candidate.end_time
        ))
        next.start_time = next.start_time ?? reference?.start_time ?? '08:00'
        next.end_time = next.end_time ?? reference?.end_time ?? '17:00'
      }
      return next
    }))
    setScheduleDirty(true)
    setScheduleError('')
  }

  function validateSchedule(): boolean {
    if (scheduleEffectiveFrom < tomorrowDateInput()) {
      setScheduleError('تاريخ بدء الجدول يجب أن يكون غداً أو بعده')
      return false
    }

    if (!useCustomSchedule) {
      setScheduleError('')
      return true
    }

    const workingDays = weeklySchedule.filter(day => day.is_working_day)
    if (workingDays.length === 0) {
      setScheduleError('يجب تحديد يوم عمل واحد على الأقل')
      return false
    }

    const invalid = workingDays.find(day => (
      !day.start_time || !day.end_time || day.end_time <= day.start_time
    ))
    if (invalid) {
      const label = WEEK_DAYS.find(day => day.value === invalid.day_of_week)?.label ?? invalid.day_of_week
      setScheduleError(`راجع وقت البداية والنهاية ليوم ${label}`)
      return false
    }

    setScheduleError('')
    return true
  }

  const attendanceModeOptions: { value: HRAttendancePolicyMode; label: string }[] = [
    { value: 'assigned_only', label: 'من المواقع المحددة فقط' },
    { value: 'field_allowed', label: 'يسمح بالميدان' },
  ]

  // ── loadOptions للمدير المباشر (Combobox) ──
  const loadManagers = useCallback(async (search: string): Promise<ComboboxOption[]> => {
    const { data } = await import('@/lib/services/hr').then(m =>
      m.getEmployees({ page: 1, pageSize: 30 })
    )
    return (data ?? [])
      .filter(e => !employee || e.id !== employee.id) // لا يفوّض لنفسه
      .filter(e =>
        !search ||
        e.full_name.includes(search) ||
        e.employee_number.includes(search)
      )
      .map(e => ({
        value: e.id,
        label: e.full_name,
        sublabel: e.employee_number,
      }))
  }, [employee])

  // ── Validation ──────────────────────────
  // UX-01: تتبع أي tabs فيها أخطاء
  const [tabErrors, setTabErrors] = useState<Record<string, boolean>>({})

  function validate(): boolean {
    const e: typeof errors = {}
    if (!form.full_name.trim())    e.full_name = 'الاسم مطلوب'
    if (!form.personal_phone.trim()) e.personal_phone = 'رقم الهاتف مطلوب'
    if (!form.hire_date)           e.hire_date = 'تاريخ التعيين مطلوب'
    if (form.base_salary <= 0)     e.base_salary = 'الراتب الأساسي يجب أن يكون أكبر من صفر'
    const scheduleValid = validateSchedule()
    setErrors(e)

    // UX-01: تحديد أي تاب فيه خطأ
    const tabWithErrors: Record<string, boolean> = {}
    if (e.full_name || e.personal_phone) tabWithErrors['basic'] = true
    if (e.hire_date)                     tabWithErrors['job']   = true
    if (e.base_salary)                   tabWithErrors['salary'] = true
    if (!scheduleValid || scheduleLoadError) tabWithErrors['schedule'] = true
    setTabErrors(tabWithErrors)

    // إذا التاب الحالي ليس فيه خطأ لكن تاب آخر فيه — انتقل له
    // إذا التاب الحالي ليس فيه خطأ لكن تاب آخر فيه — انتقل له (مؤقتًا لمعالجة الخطأ)
    if (Object.keys(tabWithErrors).length > 0 && !tabWithErrors[activeTab]) {
      const firstErrorStepId = Object.keys(tabWithErrors)[0]
      const idx = steps.findIndex(s => s.id === firstErrorStepId)
      if (idx !== -1) setActiveStepIndex(idx)
    }
    return Object.keys(e).length === 0 && scheduleValid && !scheduleLoadError
  }

  // ── Step Navigation ────────────────────────
  function validateCurrentStep(): boolean {
    const e: typeof errors = { ...errors }
    let isValid = true

    if (activeTab === 'basic') {
      if (!form.full_name.trim())      { e.full_name      = 'الاسم مطلوب'; isValid = false } else { delete e.full_name }
      if (!form.personal_phone.trim()) { e.personal_phone = 'رقم الهاتف مطلوب'; isValid = false } else { delete e.personal_phone }
    } else if (activeTab === 'job') {
      if (!form.hire_date) { e.hire_date = 'تاريخ التعيين مطلوب'; isValid = false } else { delete e.hire_date }
    } else if (activeTab === 'salary') {
      if (form.base_salary <= 0) { e.base_salary = 'الراتب الأساسي يجب أن يكون أكبر من صفر'; isValid = false } else { delete e.base_salary }
    } else if (activeTab === 'schedule') {
      isValid = validateSchedule() && !scheduleLoadError
    }
    setErrors(e)
    if (!isValid) onToast('يرجى معالجة الأخطاء قبل الانتقال', 'warning')
    return isValid
  }

  const handleNext = () => {
    if (validateCurrentStep()) {
      setActiveStepIndex(p => Math.min(steps.length - 1, p + 1))
    }
  }

  const handlePrev = () => {
    setActiveStepIndex(p => Math.max(0, p - 1))
  }

  // ── Submit ───────────────────────────────
  async function handleSubmit() {
    if (!validate()) return

    let employeeSaved = false
    try {
      let employeeId: string
      setSavingSchedule(true)

      if (isEdit) {
        const updated = await updateMut.mutateAsync({ id: employee!.id, input: form })
        employeeId = updated.id
      } else {
        const created = await createMut.mutateAsync(form)
        employeeId = created.id
      }
      employeeSaved = true

      const shouldSaveSchedule = isEdit ? scheduleDirty : useCustomSchedule
      if (shouldSaveSchedule) {
        await setEmployeeWeeklySchedule(
          employeeId,
          useCustomSchedule ? weeklySchedule : null,
          scheduleEffectiveFrom,
        )
      }

      onToast(isEdit ? 'تم تحديث بيانات الموظف وجدول عمله بنجاح' : 'تم إضافة الموظف وجدول عمله بنجاح', 'success')

      // ── ربط الحساب بالبريد الإلكتروني (اختياري — لا يُلغي العملية إذا فشل) ──
      if (!isEdit && authEmail.trim()) {
        try {
          const linkResult = await linkEmployeeToUser(employeeId, authEmail.trim())
          if (linkResult.success) {
            onToast('تم ربط حساب المستخدم بنجاح ✓', 'success')
          } else {
            // فشل الربط — تحذير فقط، الموظف أُنشئ بنجاح
            const msg = linkResult.code === 'USER_NOT_FOUND'
              ? `البريد "${authEmail}" غير موجود في النظام — يمكن الربط لاحقاً`
              : `الحساب مرتبط بموظف آخر بالفعل`
            onToast(msg, 'warning')
          }
        } catch {
          onToast('تعذّر ربط الحساب — تم إنشاء الموظف دون ربط', 'warning')
        }
      }

      onClose()
    } catch (err: unknown) {
      // عرض رسالة Supabase/PostgreSQL كما هي (عربية)
      const msg = err instanceof Error ? err.message : 'حدث خطأ غير متوقع'
      if (employeeSaved) {
        onToast(
          `تم حفظ بيانات الموظف، لكن تعذّر حفظ تغيير جدول العمل: ${msg}. افتح الموظف وحاول حفظ الجدول مرة أخرى.`,
          'warning',
        )
        onClose()
      } else {
        onToast(msg, 'error')
      }
    } finally {
      setSavingSchedule(false)
    }
  }

  const weeklyScheduledMinutes = weeklySchedule.reduce((total, day) => {
    if (!day.is_working_day || !day.start_time || !day.end_time) return total
    const [startHour, startMinute] = day.start_time.split(':').map(Number)
    const [endHour, endMinute] = day.end_time.split(':').map(Number)
    return total + ((endHour * 60 + endMinute) - (startHour * 60 + startMinute))
  }, 0)
  const hasPendingSchedule = !!loadedScheduleEffectiveFrom
    && loadedScheduleEffectiveFrom >= tomorrowDateInput()

  return (
    <ResponsiveModal
      open={open}
      onClose={onClose}
      title={isEdit ? 'تعديل بيانات الموظف' : 'إضافة موظف جديد'}
      size="lg"
      disableOverlayClose={loading}
      footer={
        <div style={{ display: 'flex', justifyContent: 'space-between', width: '100%', alignItems: 'center' }}>
          <div>
            {activeStepIndex > 0 && (
              <Button variant="ghost" onClick={handlePrev} disabled={loading}>
                السابق
              </Button>
            )}
          </div>
          <div style={{ display: 'flex', gap: 'var(--space-2)' }}>
            <Button variant="secondary" onClick={onClose} disabled={loading}>
              إلغاء
            </Button>
            {activeStepIndex < steps.length - 1 ? (
              <Button onClick={handleNext}>
                التالي
              </Button>
            ) : (
              <Button
                icon={isEdit ? <UserCog size={16} /> : <UserPlus size={16} />}
                onClick={handleSubmit}
                loading={loading}
              >
                {isEdit ? 'حفظ البيانات' : 'إضافة الموظف'}
              </Button>
            )}
          </div>
        </div>
      }
    >
      {/* ── Stepper Header ── */}
      <div className="emp-stepper">
        <div className="emp-stepper-line" />
        {steps.map((s, idx) => {
          const isActive = idx === activeStepIndex
          const isDone = idx < activeStepIndex
          const hasError = tabErrors[s.id]
          
          let circleColor = 'var(--text-muted)'
          let bgColor = 'var(--bg-surface)'
          let borderColor = 'var(--border-color)'
          
          if (isActive) {
            circleColor = 'var(--color-primary)'
            borderColor = 'var(--color-primary)'
          }
          if (isDone) {
            circleColor = '#fff'
            bgColor = 'var(--color-primary)'
            borderColor = 'var(--color-primary)'
          }
          if (hasError && !isActive && !isDone) {
            borderColor = 'var(--color-danger)'
            circleColor = 'var(--color-danger)'
          }

          return (
            <div 
              key={s.id} 
              className={`emp-step ${isActive ? 'emp-step--active' : ''} ${isDone ? 'emp-step--done' : ''}`} 
              onClick={() => { if (isEdit || idx < activeStepIndex) setActiveStepIndex(idx) }}
              style={{ cursor: (isEdit || idx < activeStepIndex) ? 'pointer' : 'default' }}
            >
              <div 
                className="emp-step-circle" 
                style={{ color: circleColor, background: bgColor, borderColor: borderColor }}
              >
                {isDone ? '✓' : idx + 1}
              </div>
              <span className="emp-step-label" style={{ color: isActive || isDone ? 'var(--text-primary)' : 'var(--text-muted)', fontWeight: isActive ? 700 : 500 }}>
                {s.label}
              </span>
            </div>
          )
        })}
      </div>

      {/* ══ TAB 1: البيانات الشخصية ══ */}
      {activeTab === 'basic' && (
        <div className="emp-form-section">
          <div className="emp-form-grid">
            <Input
              label="الاسم الكامل"
              required
              value={form.full_name}
              onChange={e => set('full_name')(e.target.value)}
              error={errors.full_name}
              placeholder="محمد أحمد محمد"
            />
            <Input
              label="الاسم بالإنجليزية"
              value={form.full_name_en ?? ''}
              onChange={e => set('full_name_en')(e.target.value || null)}
              placeholder="Mohamed Ahmed"
            />
          </div>

          <div className="emp-form-grid">
            <Input
              label="الرقم القومي"
              value={form.national_id ?? ''}
              onChange={e => set('national_id')(e.target.value || null)}
              placeholder="30xxxxxxxxxxxxxxx"
              maxLength={14}
            />
            <Input
              label="تاريخ الميلاد"
              type="date"
              value={form.birth_date ?? ''}
              onChange={e => set('birth_date')(e.target.value || null)}
            />
          </div>

          <div className="emp-form-grid">
            <Select
              label="الجنس"
              value={form.gender ?? ''}
              onChange={e => set('gender')((e.target.value as HRGender) || null)}
              options={[
                { value: 'male', label: 'ذكر' },
                { value: 'female', label: 'أنثى' },
              ]}
              placeholder="اختر الجنس"
            />
            <Select
              label="الحالة الاجتماعية"
              value={form.marital_status ?? ''}
              onChange={e => set('marital_status')((e.target.value as HRMaritalStatus) || null)}
              options={[
                { value: 'single',   label: 'أعزب / عزباء' },
                { value: 'married',  label: 'متزوج / متزوجة' },
                { value: 'divorced', label: 'مطلق / مطلقة' },
                { value: 'widowed',  label: 'أرمل / أرملة' },
              ]}
              placeholder="اختر الحالة"
            />
          </div>

          <div className="emp-form-grid">
            <Input
              label="هاتف شخصي"
              required
              type="tel"
              value={form.personal_phone}
              onChange={e => set('personal_phone')(e.target.value)}
              error={errors.personal_phone}
              placeholder="010xxxxxxxx"
              dir="ltr"
            />
            <Input
              label="هاتف طوارئ"
              type="tel"
              value={form.emergency_phone ?? ''}
              onChange={e => set('emergency_phone')(e.target.value || null)}
              placeholder="010xxxxxxxx"
              dir="ltr"
            />
          </div>

          <Input
            label="اسم جهة الاتصال الطارئ"
            value={form.emergency_contact ?? ''}
            onChange={e => set('emergency_contact')(e.target.value || null)}
            placeholder="اسم الشخص — صلة القرابة"
          />

          <Input
            label="العنوان"
            value={form.address ?? ''}
            onChange={e => set('address')(e.target.value || null)}
            placeholder="المحافظة — المدينة — الحي"
          />

          {/* ── ربط حساب auth (إضافة جديدة فقط) ── */}
          {!isEdit && (
            <div className="emp-link-section">
              <div className="emp-link-header">
                <Link size={14} />
                <span>ربط بحساب مستخدم (اختياري)</span>
              </div>
              <Input
                label="البريد الإلكتروني للحساب"
                type="email"
                value={authEmail}
                onChange={e => setAuthEmail(e.target.value)}
                placeholder="employee@company.com"
                hint="إذا كان الموظف يملك حساباً في النظام — يمكن الربط لاحقاً أيضاً"
                dir="ltr"
              />
              {authEmail && (
                <div className="emp-link-notice">
                  <AlertCircle size={13} />
                  <span>إذا لم يُعثر على الحساب لن يُلغى إنشاء الموظف</span>
                </div>
              )}
            </div>
          )}
        </div>
      )}

      {/* ══ TAB 2: بيانات التوظيف ══ */}
      {activeTab === 'job' && (
        <div className="emp-form-section">
          <div className="emp-form-grid">
            <Input
              label="تاريخ التعيين"
              type="date"
              required
              value={form.hire_date}
              onChange={e => set('hire_date')(e.target.value)}
              error={errors.hire_date}
            />
            <Input
              label="نهاية فترة التجربة"
              type="date"
              value={form.probation_end_date ?? ''}
              onChange={e => set('probation_end_date')(e.target.value || null)}
            />
          </div>

          <div className="emp-form-grid">
            <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
              <Select
                label="حالة الموظف"
                value={form.status ?? 'active'}
                onChange={e => set('status')(e.target.value as HREmployeeInput['status'])}
                disabled={form.status === 'terminated'}
                options={[
                  { value: 'active',     label: 'نشط' },
                  { value: 'on_leave',   label: 'في إجازة' },
                  { value: 'suspended',  label: 'موقوف' },
                  ...(form.status === 'terminated' ? [{ value: 'terminated', label: 'منتهي الخدمة (مُقفلة)' }] : []),
                ]}
              />
              {isEdit && form.status !== 'terminated' && (
                <div style={{ display: 'flex', gap: '4px', alignItems: 'center', color: 'var(--color-primary)', fontSize: '11px', background: 'var(--bg-primary-light)', padding: '4px 8px', borderRadius: '4px' }}>
                  <AlertCircle size={12} />
                  <span>إنهاء الخدمة يتم فقط عبر زر "إنهاء الخدمة" في لوحة تحكم الموظف بالخارج.</span>
                </div>
              )}
            </div>
          </div>

          <div className="emp-form-grid">
            <Select
              label="القسم"
              value={form.department_id ?? ''}
              onChange={e => {
                set('department_id')(e.target.value || null)
                set('position_id')(null) // reset position when dept changes
              }}
              placeholder="اختر القسم"
              options={departments.map(d => ({ value: d.id, label: d.name }))}
            />
            <Select
              label="المسمى الوظيفي"
              value={form.position_id ?? ''}
              onChange={e => set('position_id')(e.target.value || null)}
              placeholder={form.department_id ? 'اختر المسمى' : 'اختر القسم أولاً'}
              disabled={!form.department_id}
              options={positions.map(p => ({ value: p.id, label: p.name }))}
            />
          </div>

          <AsyncCombobox
            label="المدير المباشر"
            placeholder="ابحث باسم الموظف..."
            value={form.direct_manager_id ?? null}
            onChange={val => set('direct_manager_id')(val)}
            loadOptions={loadManagers}
          />

          <Select
            label="موقع الحضور الافتراضي (GPS)"
            value={form.work_location_id ?? ''}
            onChange={e => {
              const nextId = e.target.value || null
              setForm(prev => ({
                ...prev,
                work_location_id: nextId ?? undefined,
                allowed_checkin_location_ids: nextId && (prev.allowed_checkin_location_ids?.length ?? 0) === 0
                  ? [nextId]
                  : (prev.allowed_checkin_location_ids ?? []),
                allowed_checkout_location_ids: nextId && (prev.allowed_checkout_location_ids?.length ?? 0) === 0
                  ? [nextId]
                  : (prev.allowed_checkout_location_ids ?? []),
              }))
            }}
            placeholder="اختر الموقع"
            options={workLocations.map(l => ({ value: l.id, label: l.name }))}
          />

          <div className="emp-form-grid">
            <Select
              label="سياسة تسجيل الحضور"
              value={form.attendance_checkin_mode ?? 'assigned_only'}
              onChange={e => set('attendance_checkin_mode')((e.target.value as HRAttendancePolicyMode) || 'assigned_only')}
              options={attendanceModeOptions}
              hint="حدد هل يبدأ اليوم من مواقع محددة فقط أم يسمح بالبداية من الميدان"
            />
            <Select
              label="سياسة تسجيل الانصراف"
              value={form.attendance_checkout_mode ?? 'assigned_only'}
              onChange={e => set('attendance_checkout_mode')((e.target.value as HRAttendancePolicyMode) || 'assigned_only')}
              options={attendanceModeOptions}
              hint="يمكن إلزام الحضور من المقر والسماح بالانصراف من الميدان"
            />
          </div>

          <div className="emp-form-grid">
            <div className="form-group">
              <label className="form-label">المواقع المسموح بها للحضور</label>
              <div className="emp-location-checklist">
                {workLocations.map(location => {
                  const checked = (form.allowed_checkin_location_ids ?? []).includes(location.id)
                  return (
                    <label key={`checkin-${location.id}`} className="emp-location-option">
                      <input
                        type="checkbox"
                        checked={checked}
                        onChange={() => toggleLocation('allowed_checkin_location_ids', location.id)}
                      />
                      <span>{location.name}</span>
                    </label>
                  )
                })}
              </div>
              <span className="form-hint">إذا تركت القائمة فارغة فسيُستخدم الموقع الافتراضي فقط عند التحقق.</span>
            </div>

            <div className="form-group">
              <label className="form-label">المواقع المسموح بها للانصراف</label>
              <div className="emp-location-checklist">
                {workLocations.map(location => {
                  const checked = (form.allowed_checkout_location_ids ?? []).includes(location.id)
                  return (
                    <label key={`checkout-${location.id}`} className="emp-location-option">
                      <input
                        type="checkbox"
                        checked={checked}
                        onChange={() => toggleLocation('allowed_checkout_location_ids', location.id)}
                      />
                      <span>{location.name}</span>
                    </label>
                  )
                })}
              </div>
              <span className="form-hint">استخدمها للسماح بإنهاء اليوم من فرع آخر أو من الميدان حسب السياسة المحددة.</span>
            </div>
          </div>

          <div className="emp-form-grid">
            <Select
              label="يوم الإجازة الأسبوعية"
              value={form.weekly_off_day ?? ''}
              onChange={e => set('weekly_off_day')((e.target.value as HRDayOfWeek) || null)}
              placeholder="يتبع إعداد الشركة"
              options={[
                { value: 'friday',    label: 'الجمعة' },
                { value: 'saturday',  label: 'السبت' },
                { value: 'sunday',    label: 'الأحد' },
                { value: 'monday',    label: 'الإثنين' },
                { value: 'tuesday',   label: 'الثلاثاء' },
                { value: 'wednesday', label: 'الأربعاء' },
                { value: 'thursday',  label: 'الخميس' },
              ]}
              hint="يُستخدم فقط عند عدم تفعيل جدول عمل خاص"
            />
            <div className="form-group">
              <label className="form-label">موظف ميداني؟</label>
              <label className="emp-toggle">
                <input
                  type="checkbox"
                  checked={form.is_field_employee ?? false}
                  onChange={e => set('is_field_employee')(e.target.checked)}
                />
                <span className="emp-toggle-track" />
                <span className="emp-toggle-label">
                  {form.is_field_employee ? 'نعم (مندوب / سائق)' : 'لا (مكتبي)'}
                </span>
              </label>
            </div>
          </div>

          {form.status === 'terminated' && (
            <Input
              label="سبب إنهاء الخدمة"
              value={form.termination_reason ?? ''}
              onChange={e => set('termination_reason')(e.target.value || null)}
              placeholder="استقالة / إنهاء عقد / ..."
            />
          )}

          <Input
            label="ملاحظات"
            value={form.notes ?? ''}
            onChange={e => set('notes')(e.target.value || null)}
            placeholder="أي ملاحظات إضافية"
          />
        </div>
      )}

      {/* ══ TAB 3: الراتب والبدلات ══ */}
      {activeTab === 'salary' && (
        <div className="emp-form-section">
          {isEdit ? (
            <div className="emp-salary-notice" style={{ background: 'var(--bg-warning-light)', color: 'var(--color-warning)' }}>
              <AlertCircle size={16} />
              <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
                <strong style={{ fontSize: 'var(--text-sm)' }}>تعديل الراتب متوقف من هذا النموذج</strong>
                <span style={{ fontSize: 'var(--text-xs)', opacity: 0.9 }}>
                  للحفاظ على السجلات والتاريخ المالي للموظف، يُرجى استخدام قائمة "تعديل الراتب" أو الدخول على تبويب "العقود" من ملف الموظف مباشرة.
                </span>
              </div>
            </div>
          ) : (
            <div className="emp-salary-notice">
              <AlertCircle size={14} />
              <span>
                الراتب الإجمالي يُحسب تلقائياً = الأساسي + البدلات
              </span>
            </div>
          )}

          <div className="emp-form-grid" style={{ opacity: isEdit ? 0.7 : 1 }}>
            <Input
              label="الراتب الأساسي"
              required={!isEdit}
              type="number"
              min={0}
              step={100}
              value={String(form.base_salary)}
              onChange={e => set('base_salary')(Number(e.target.value))}
              error={!isEdit ? errors.base_salary : undefined}
              placeholder="0"
              hint={isEdit ? 'لا يمكن التعديل المباشر' : 'ج.م / شهر'}
              disabled={isEdit}
            />
            <Input
              label="بدل المواصلات"
              type="number"
              min={0}
              step={50}
              value={String(form.transport_allowance ?? 0)}
              onChange={e => set('transport_allowance')(Number(e.target.value))}
              placeholder="0"
              hint={isEdit ? '' : 'ج.م / شهر'}
              disabled={isEdit}
            />
          </div>

          <div className="emp-form-grid" style={{ opacity: isEdit ? 0.7 : 1 }}>
            <Input
              label="بدل السكن"
              type="number"
              min={0}
              step={50}
              value={String(form.housing_allowance ?? 0)}
              onChange={e => set('housing_allowance')(Number(e.target.value))}
              placeholder="0"
              hint={isEdit ? '' : 'ج.م / شهر'}
              disabled={isEdit}
            />
            <Input
              label="بدلات أخرى"
              type="number"
              min={0}
              step={50}
              value={String(form.other_allowances ?? 0)}
              onChange={e => set('other_allowances')(Number(e.target.value))}
              placeholder="0"
              hint={isEdit ? '' : 'ج.م / شهر'}
              disabled={isEdit}
            />
          </div>

          {/* عرض الإجمالي محلياً فقط (للمراجعة البصرية — لا يُرسل) */}
          <div className="emp-salary-total">
            <span>الإجمالي التقديري</span>
            <strong>
              {(
                (form.base_salary || 0) +
                (form.transport_allowance || 0) +
                (form.housing_allowance || 0) +
                (form.other_allowances || 0)
              ).toLocaleString('en-US')} ج.م
            </strong>
          </div>
        </div>
      )}

      {/* ══ TAB 4: جدول العمل الأسبوعي ══ */}
      {activeTab === 'schedule' && (
        <div className="emp-form-section">
          <div className="emp-schedule-intro">
            <div>
              <strong>جدول عمل خاص بالموظف</strong>
              <p>
                عند إيقافه يتبع الموظف مواعيد الشركة ويوم الراحة المحدد في بيانات التوظيف.
                عند تفعيله تصبح المواعيد أدناه هي المرجع للحضور والتأخير والانصراف والأوفرتايم والراتب.
              </p>
            </div>
            <label className="emp-toggle">
              <input
                type="checkbox"
                checked={useCustomSchedule}
                onChange={event => {
                  setUseCustomSchedule(event.target.checked)
                  setScheduleDirty(true)
                  setScheduleError('')
                }}
                disabled={scheduleLoading || !!scheduleLoadError}
              />
              <span className="emp-toggle-track" />
              <span className="emp-toggle-label">{useCustomSchedule ? 'مفعّل' : 'يتبع الشركة'}</span>
            </label>
          </div>

          {!scheduleLoading && !scheduleLoadError && (
            <div className="emp-schedule-effective">
              <label htmlFor="employee-schedule-effective-from">يبدأ تطبيق التغيير من</label>
              <input
                id="employee-schedule-effective-from"
                className="form-input"
                type="date"
                dir="ltr"
                min={tomorrowDateInput()}
                value={scheduleEffectiveFrom}
                disabled={hasPendingSchedule}
                onChange={event => {
                  setScheduleEffectiveFrom(event.target.value)
                  setScheduleDirty(true)
                  setScheduleError('')
                }}
              />
              <p>
                {hasPendingSchedule
                  ? `يوجد تغيير محفوظ سيبدأ في ${loadedScheduleEffectiveFrom}. يمكنك تعديل محتواه بنفس التاريخ.`
                  : loadedScheduleEffectiveFrom
                    ? `الجدول الحالي محفوظ منذ ${loadedScheduleEffectiveFrom}. أي تعديل جديد يبدأ من التاريخ المحدد دون تغيير الأيام السابقة.`
                    : 'أي تغيير يبدأ من التاريخ المحدد دون تعديل أيام الحضور السابقة أو اليوم المفتوح.'}
              </p>
            </div>
          )}

          {scheduleLoading && (
            <div className="emp-schedule-message">جارٍ تحميل جدول العمل…</div>
          )}

          {scheduleLoadError && (
            <div className="emp-schedule-message emp-schedule-message--error">
              <AlertCircle size={16} />
              {scheduleLoadError}
            </div>
          )}

          {useCustomSchedule && !scheduleLoading && !scheduleLoadError && (
            <>
              <div className="emp-schedule-table">
                <div className="emp-schedule-row emp-schedule-row--header">
                  <span>اليوم</span>
                  <span>يوم عمل</span>
                  <span>الحضور</span>
                  <span>الانصراف</span>
                  <span>الساعات</span>
                </div>

                {WEEK_DAYS.map(dayOption => {
                  const day = weeklySchedule.find(item => item.day_of_week === dayOption.value)
                    ?? defaultWeeklySchedule().find(item => item.day_of_week === dayOption.value)!
                  const minutes = day.is_working_day && day.start_time && day.end_time
                    ? Math.max(0,
                      (Number(day.end_time.slice(0, 2)) * 60 + Number(day.end_time.slice(3, 5)))
                      - (Number(day.start_time.slice(0, 2)) * 60 + Number(day.start_time.slice(3, 5)))
                    )
                    : 0

                  return (
                    <div key={dayOption.value} className={`emp-schedule-row ${day.is_working_day ? '' : 'emp-schedule-row--off'}`}>
                      <strong>{dayOption.label}</strong>
                      <label className="emp-schedule-working">
                        <input
                          type="checkbox"
                          checked={day.is_working_day}
                          onChange={event => updateScheduleDay(day.day_of_week, { is_working_day: event.target.checked })}
                        />
                        <span>{day.is_working_day ? 'عمل' : 'راحة'}</span>
                      </label>
                      <input
                        className="form-input emp-schedule-time"
                        type="time"
                        dir="ltr"
                        value={day.start_time ?? ''}
                        disabled={!day.is_working_day}
                        aria-label={`موعد حضور ${dayOption.label}`}
                        onChange={event => updateScheduleDay(day.day_of_week, { start_time: event.target.value || null })}
                      />
                      <input
                        className="form-input emp-schedule-time"
                        type="time"
                        dir="ltr"
                        value={day.end_time ?? ''}
                        disabled={!day.is_working_day}
                        aria-label={`موعد انصراف ${dayOption.label}`}
                        onChange={event => updateScheduleDay(day.day_of_week, { end_time: event.target.value || null })}
                      />
                      <span className="emp-schedule-hours">
                        {day.is_working_day ? `${(minutes / 60).toFixed(minutes % 60 ? 1 : 0)} ساعة` : '—'}
                      </span>
                    </div>
                  )
                })}
              </div>

              <div className="emp-schedule-summary">
                <span>{weeklySchedule.filter(day => day.is_working_day).length} أيام عمل أسبوعياً</span>
                <strong>{(weeklyScheduledMinutes / 60).toFixed(weeklyScheduledMinutes % 60 ? 1 : 0)} ساعة أسبوعياً</strong>
              </div>

            </>
          )}

          {scheduleError && !scheduleLoading && !scheduleLoadError && (
            <div className="emp-schedule-message emp-schedule-message--error">
              <AlertCircle size={16} />
              {scheduleError}
            </div>
          )}
        </div>
      )}

      <style>{`
        .emp-stepper {
          display: flex; justify-content: space-between; align-items: flex-start;
          margin-bottom: var(--space-6); position: relative; padding: 0 var(--space-4);
        }
        .emp-stepper-line {
          position: absolute; top: 15px; left: calc(var(--space-4) + 15px); right: calc(var(--space-4) + 15px);
          height: 2px; background: var(--border-color); z-index: 0;
        }
        .emp-step {
          display: flex; flex-direction: column; align-items: center; gap: 6px;
          position: relative; z-index: 1; min-width: 80px; text-align: center;
        }
        .emp-step-circle {
          width: 32px; height: 32px; border-radius: 50%;
          border: 2px solid;
          display: flex; align-items: center; justify-content: center;
          font-size: 14px; font-weight: 700;
          transition: all 0.2s ease;
        }
        .emp-step-label { font-size: var(--text-xs); transition: color 0.2s ease; }
        
        .emp-form-section {
          display: flex;
          flex-direction: column;
          gap: var(--space-4);
          animation: animate-enter 0.2s ease;
        }
        .emp-form-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
          gap: var(--space-4);
        }
        .emp-location-checklist {
          display: flex;
          flex-direction: column;
          gap: var(--space-2);
          max-height: 180px;
          overflow-y: auto;
          padding: var(--space-3);
          border: 1px solid var(--border-color);
          border-radius: var(--radius-md);
          background: var(--bg-surface);
        }
        .emp-location-option {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          font-size: var(--text-sm);
          color: var(--text-secondary);
          cursor: pointer;
        }

        .emp-schedule-intro {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--space-4);
          padding: var(--space-4);
          border: 1px solid var(--border-color);
          border-radius: var(--radius-md);
          background: var(--bg-surface-2);
        }
        .emp-schedule-intro p {
          margin: 6px 0 0;
          color: var(--text-muted);
          font-size: var(--text-xs);
          line-height: 1.7;
        }
        .emp-schedule-effective {
          display: grid;
          grid-template-columns: minmax(150px, auto) minmax(180px, 240px) 1fr;
          align-items: center;
          gap: var(--space-3);
          padding: var(--space-3);
          margin-block: var(--space-4);
          border: 1px solid var(--border-color);
          border-radius: var(--radius-md);
          background: var(--bg-surface-2);
        }
        .emp-schedule-effective label {
          font-weight: 600;
          color: var(--text-primary);
        }
        .emp-schedule-effective p {
          margin: 0;
          color: var(--text-secondary);
          line-height: 1.7;
          text-align: start;
        }
        .emp-schedule-table {
          border: 1px solid var(--border-color);
          border-radius: var(--radius-md);
          overflow: hidden;
        }
        .emp-schedule-row {
          display: grid;
          grid-template-columns: minmax(90px, 1fr) minmax(80px, .8fr) minmax(105px, 1fr) minmax(105px, 1fr) minmax(75px, .8fr);
          gap: var(--space-3);
          align-items: center;
          padding: var(--space-3) var(--space-4);
          border-bottom: 1px solid var(--border-color);
        }
        .emp-schedule-row:last-child { border-bottom: 0; }
        .emp-schedule-row--header {
          color: var(--text-muted);
          background: var(--bg-surface-2);
          font-size: var(--text-xs);
          font-weight: 700;
        }
        .emp-schedule-row--off {
          color: var(--text-muted);
          background: var(--bg-surface-2);
        }
        .emp-schedule-working {
          display: flex;
          align-items: center;
          gap: 6px;
          font-size: var(--text-sm);
          cursor: pointer;
        }
        .emp-schedule-time { min-width: 0; text-align: center; }
        .emp-schedule-hours { font-size: var(--text-sm); color: var(--text-secondary); }
        .emp-schedule-summary {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--space-3);
          padding: var(--space-3) var(--space-4);
          border-radius: var(--radius-md);
          background: var(--bg-primary-light);
          color: var(--color-primary);
          font-size: var(--text-sm);
        }
        .emp-schedule-message {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          padding: var(--space-3);
          border-radius: var(--radius-md);
          background: var(--bg-surface-2);
          color: var(--text-muted);
          font-size: var(--text-sm);
        }
        .emp-schedule-message--error {
          color: var(--color-danger);
          background: var(--bg-danger-light);
        }

        @media (max-width: 720px) {
          .emp-schedule-intro { align-items: flex-start; flex-direction: column; }
          .emp-schedule-effective { grid-template-columns: 1fr; }
          .emp-schedule-row {
            grid-template-columns: 1fr 1fr;
          }
          .emp-schedule-row--header { display: none; }
          .emp-schedule-hours { grid-column: 1 / -1; }
        }

        /* Auth link section */
        .emp-link-section {
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-md);
          padding: var(--space-4);
          background: var(--bg-surface-2);
          display: flex;
          flex-direction: column;
          gap: var(--space-3);
        }
        .emp-link-header {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          font-size: var(--text-sm);
          font-weight: 600;
          color: var(--text-secondary);
        }
        .emp-link-notice {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          font-size: var(--text-xs);
          color: var(--color-warning);
          background: color-mix(in srgb, var(--color-warning) 8%, transparent);
          padding: var(--space-2) var(--space-3);
          border-radius: var(--radius-sm);
        }

        /* Toggle */
        .emp-toggle {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          cursor: pointer;
          user-select: none;
          padding-top: var(--space-1);
        }
        .emp-toggle input { display: none; }
        .emp-toggle-track {
          width: 38px; height: 20px;
          border-radius: var(--radius-full);
          background: var(--border-primary);
          flex-shrink: 0;
          position: relative;
          transition: background var(--transition-fast);
        }
        .emp-toggle-track::after {
          content: '';
          position: absolute;
          top: 2px; inset-inline-start: 2px;
          width: 16px; height: 16px;
          border-radius: 50%;
          background: white;
          transition: inset-inline-start var(--transition-fast);
        }
        .emp-toggle input:checked + .emp-toggle-track {
          background: var(--color-primary);
        }
        .emp-toggle input:checked + .emp-toggle-track::after {
          inset-inline-start: calc(100% - 18px);
        }
        .emp-toggle-label { font-size: var(--text-sm); color: var(--text-secondary); }

        /* Salary tab */
        .emp-salary-notice {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          font-size: var(--text-xs);
          color: var(--text-muted);
          background: var(--bg-surface-2);
          padding: var(--space-2) var(--space-3);
          border-radius: var(--radius-sm);
          border: 1px solid var(--border-primary);
        }
        .emp-salary-total {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: var(--space-3) var(--space-4);
          background: color-mix(in srgb, var(--color-primary) 6%, transparent);
          border-radius: var(--radius-md);
          border: 1px solid color-mix(in srgb, var(--color-primary) 20%, transparent);
          font-size: var(--text-sm);
          color: var(--text-secondary);
        }
        .emp-salary-total strong {
          font-size: var(--text-lg);
          font-weight: 700;
          color: var(--color-primary);
          font-variant-numeric: tabular-nums;
        }
      `}</style>
    </ResponsiveModal>
  )
}
