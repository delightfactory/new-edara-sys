import { useState, useEffect, useCallback } from 'react'
import { UserPlus, UserCog, Link, AlertCircle } from 'lucide-react'
import type { HREmployee, HREmployeeInput, HRGender, HRMaritalStatus, HRDayOfWeek } from '@/lib/types/hr'
import {
  useHRDepartments,
  useHRPositions,
  useHRWorkLocations,
  useCreateEmployee,
  useUpdateEmployee,
} from '@/hooks/useQueryHooks'
import { linkEmployeeToUser } from '@/lib/services/hr'
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
  const [activeTab, setActiveTab] = useState<'basic' | 'job' | 'salary'>('basic')
  const [errors, setErrors] = useState<Partial<Record<keyof HREmployeeInput, string>>>({})

  const createMut = useCreateEmployee()
  const updateMut = useUpdateEmployee()
  const loading = createMut.isPending || updateMut.isPending

  // ── جلب بيانات الرجوع ──────────────────
  const { data: departments = [] } = useHRDepartments()
  const { data: positions = [] }   = useHRPositions(form.department_id ?? undefined)
  const { data: workLocations = [] } = useHRWorkLocations()

  // ── مزامنة النموذج عند الفتح ──────────
  useEffect(() => {
    if (open) {
      setForm(isEdit ? employeeToInput(employee!) : EMPTY_FORM)
      setAuthEmail('')
      setActiveTab('basic')
      setErrors({})
      setTabErrors({})
    }
  }, [open, isEdit, employee])

  const set = <K extends keyof HREmployeeInput>(key: K) =>
    (val: HREmployeeInput[K] | null) =>
      setForm(prev => ({ ...prev, [key]: val === null ? undefined : val }))

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
    setErrors(e)

    // UX-01: تحديد أي تاب فيه خطأ
    const tabWithErrors: Record<string, boolean> = {}
    if (e.full_name || e.personal_phone) tabWithErrors['basic'] = true
    if (e.hire_date)                     tabWithErrors['job']   = true
    if (e.base_salary)                   tabWithErrors['salary'] = true
    setTabErrors(tabWithErrors)

    // إذا التاب الحالي ليس فيه خطأ لكن تاب آخر فيه — انتقل له
    if (Object.keys(tabWithErrors).length > 0 && !tabWithErrors[activeTab]) {
      setActiveTab(Object.keys(tabWithErrors)[0] as typeof activeTab)
    }
    return Object.keys(e).length === 0
  }

  // ── Submit ───────────────────────────────
  async function handleSubmit() {
    if (!validate()) return

    try {
      let employeeId: string

      if (isEdit) {
        const updated = await updateMut.mutateAsync({ id: employee!.id, input: form })
        employeeId = updated.id
        onToast('تم تحديث بيانات الموظف بنجاح', 'success')
      } else {
        const created = await createMut.mutateAsync(form)
        employeeId = created.id
        onToast('تم إضافة الموظف بنجاح', 'success')
      }

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
      onToast(msg, 'error')
    }
  }

  // ── Tab nav ──────────────────────────────
  const tabs = [
    { id: 'basic',  label: 'البيانات الشخصية' },
    { id: 'job',    label: 'بيانات التوظيف' },
    { id: 'salary', label: 'الراتب والبدلات' },
  ] as const

  return (
    <ResponsiveModal
      open={open}
      onClose={onClose}
      title={isEdit ? 'تعديل بيانات الموظف' : 'إضافة موظف جديد'}
      size="lg"
      disableOverlayClose={loading}
      footer={
        <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
          <Button variant="secondary" onClick={onClose} disabled={loading} style={{ flex: 1 }}>
            إلغاء
          </Button>
          <Button
            icon={isEdit ? <UserCog size={16} /> : <UserPlus size={16} />}
            onClick={handleSubmit}
            loading={loading}
            style={{ flex: 2 }}
          >
            {isEdit ? 'حفظ التعديلات' : 'إضافة الموظف'}
          </Button>
        </div>
      }
    >
      {/* ── Tab switcher ── */}
      <div className="emp-form-tabs">
        {tabs.map(t => (
          <button
            key={t.id}
            type="button"
            className={`emp-form-tab ${activeTab === t.id ? 'emp-form-tab--active' : ''} ${tabErrors[t.id] ? 'emp-form-tab--error' : ''}`}
            onClick={() => setActiveTab(t.id)}
            style={{ position: 'relative' }}
          >
            {t.label}
            {tabErrors[t.id] && (
              <span style={{
                display: 'inline-block', width: 6, height: 6,
                borderRadius: '50%', background: 'var(--color-danger)',
                position: 'absolute', top: 6, left: 6,
              }} />
            )}
          </button>
        ))}
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
            {/* نوع التوظيف يُحفظ في جدول العقود (hr_contracts) وليس في hr_employees مباشرة */}
            {/* يُضاف في شاشة العقود لاحقاً */}
            <Select
              label="حالة الموظف"
              value={form.status ?? 'active'}
              onChange={e => set('status')(e.target.value as HREmployeeInput['status'])}
              options={[
                { value: 'active',     label: 'نشط' },
                { value: 'on_leave',   label: 'في إجازة' },
                { value: 'suspended',  label: 'موقوف' },
                { value: 'terminated', label: 'منتهي الخدمة' },
              ]}
            />
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
            onChange={e => set('work_location_id')(e.target.value || null)}
            placeholder="اختر الموقع"
            options={workLocations.map(l => ({ value: l.id, label: l.name }))}
          />

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
                { value: 'thursday',  label: 'الخميس' },
                { value: 'monday',    label: 'الإثنين' },
              ]}
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
          {/* تنبيه: الحقول المحسوبة لا تظهر هنا (gross_salary = GENERATED ALWAYS AS) */}
          <div className="emp-salary-notice">
            <AlertCircle size={14} />
            <span>
              الراتب الإجمالي يُحسب تلقائياً = الأساسي + البدلات
            </span>
          </div>

          <div className="emp-form-grid">
            <Input
              label="الراتب الأساسي"
              required
              type="number"
              min={0}
              step={100}
              value={String(form.base_salary)}
              onChange={e => set('base_salary')(Number(e.target.value))}
              error={errors.base_salary}
              placeholder="0"
              hint="ج.م / شهر"
            />
            <Input
              label="بدل المواصلات"
              type="number"
              min={0}
              step={50}
              value={String(form.transport_allowance ?? 0)}
              onChange={e => set('transport_allowance')(Number(e.target.value))}
              placeholder="0"
              hint="ج.م / شهر"
            />
          </div>

          <div className="emp-form-grid">
            <Input
              label="بدل السكن"
              type="number"
              min={0}
              step={50}
              value={String(form.housing_allowance ?? 0)}
              onChange={e => set('housing_allowance')(Number(e.target.value))}
              placeholder="0"
              hint="ج.م / شهر"
            />
            <Input
              label="بدلات أخرى"
              type="number"
              min={0}
              step={50}
              value={String(form.other_allowances ?? 0)}
              onChange={e => set('other_allowances')(Number(e.target.value))}
              placeholder="0"
              hint="ج.م / شهر"
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
              ).toLocaleString('ar-EG')} ج.م
            </strong>
          </div>
        </div>
      )}

      <style>{`
        .emp-form-tabs {
          display: flex;
          border-bottom: 1.5px solid var(--border-primary);
          margin-bottom: var(--space-5);
          gap: var(--space-1);
          overflow-x: auto;
          scrollbar-width: none;
        }
        .emp-form-tabs::-webkit-scrollbar { display: none; }
        .emp-form-tab {
          padding: var(--space-2) var(--space-4);
          font-size: var(--text-sm);
          font-weight: 500;
          color: var(--text-secondary);
          border: none;
          background: transparent;
          cursor: pointer;
          border-bottom: 2px solid transparent;
          margin-bottom: -1.5px;
          white-space: nowrap;
          transition: color var(--transition-fast), border-color var(--transition-fast);
          font-family: var(--font-sans);
        }
        .emp-form-tab:hover { color: var(--text-primary); }
        .emp-form-tab--active {
          color: var(--color-primary);
          border-bottom-color: var(--color-primary);
        }

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
