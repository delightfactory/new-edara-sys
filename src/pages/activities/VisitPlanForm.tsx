/**
 * VisitPlanWizard — إنشاء خطة زيارات بـ 4 خطوات
 * يستبدل VisitPlanForm البسيط بـ Wizard احترافي:
 *
 * الخطوة 0: إعدادات الخطة (تاريخ + نوع + موظف + قالب)
 * الخطوة 1: اختيار العملاء (بحث + فلترة + تحديد جماعي)
 * الخطوة 2: ضبط ترتيب + أولوية + غرض + وقت مخطط
 * الخطوة 3: معاينة + تأكيد
 */
import { useState, useMemo, useCallback, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import {
  useCreateVisitPlan,
  useAddVisitPlanItem,
  useCurrentEmployee,
  useHREmployees,
  useVisitPlanTemplates,
  useVisitPlans,
} from '@/hooks/useQueryHooks'
import { useCustomerSearch } from '@/hooks/useCustomerSearch'
import { useAuthStore } from '@/stores/auth-store'
import { PERMISSIONS } from '@/lib/permissions/constants'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import Stepper from '@/components/ui/Stepper'
import Button from '@/components/ui/Button'
import { CardSkeleton } from '@/components/ui/Skeleton'
import CustomerSearchCard from '@/components/shared/CustomerSearchCard'
import type {
  VisitPlanInput,
  VisitPlanItemInput,
  PlanItemPurposeType,
  PlanPriority,
} from '@/lib/types/activities'
import type { CustomerSearchResult } from '@/hooks/useCustomerSearch'
import { Search, Plus, Trash2, GripVertical, MapPin, Clock, ArrowUp, ArrowDown, Check, ChevronLeft, ChevronRight, Users, ClipboardList, Settings2, Eye, Loader2 } from 'lucide-react'

// ── Step definitions ─────────────────────────────────────────
const WIZARD_STEPS = [
  { label: 'الإعدادات', description: 'تاريخ ونوع الخطة' },
  { label: 'العملاء', description: 'اختيار العملاء' },
  { label: 'التفاصيل', description: 'الترتيب والأولوية' },
  { label: 'المراجعة', description: 'التأكيد والإنشاء' },
]

const PLAN_TYPES = [
  { value: 'daily' as const, label: 'يومية', desc: 'خطة ليوم واحد' },
  { value: 'weekly' as const, label: 'أسبوعية', desc: 'خطة لأسبوع كامل' },
  { value: 'campaign' as const, label: 'حملة', desc: 'حملة إعلانية أو موسمية' },
  { value: 'recurring' as const, label: 'متكررة', desc: 'خطة تتكرر تلقائياً' },
]

const PURPOSE_OPTIONS: { value: PlanItemPurposeType; label: string }[] = [
  { value: 'sales', label: 'مبيعات' },
  { value: 'collection', label: 'تحصيل' },
  { value: 'activation', label: 'تنشيط' },
  { value: 'promotion', label: 'ترويج' },
  { value: 'followup', label: 'متابعة' },
  { value: 'service', label: 'خدمة' },
]

const PRIORITY_OPTIONS: { value: PlanPriority; label: string; color: string }[] = [
  { value: 'high', label: 'عالية', color: 'var(--color-danger)' },
  { value: 'normal', label: 'عادية', color: 'var(--color-primary)' },
  { value: 'low', label: 'منخفضة', color: 'var(--text-muted)' },
]

// ── Selected customer item state ─────────────────────────────
interface SelectedCustomer {
  customerId: string
  customerName: string
  customerCode: string
  phone: string | null
  latitude: number | null
  longitude: number | null
  governorate: string | null
  city: string | null
  currentBalance: number
  creditLimit: number
  sequence: number
  plannedTime: string
  estimatedDuration: number
  priority: PlanPriority
  purposeType: PlanItemPurposeType | ''
  purpose: string
}

export default function VisitPlanWizard() {
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)

  // ── Queries ────────────────────────────────────────────────
  const { data: currentEmployee } = useCurrentEmployee()
  const { data: employeesResult } = useHREmployees({ status: 'active' })
  const allEmployees = employeesResult?.data ?? []
  const { data: templates = [] } = useVisitPlanTemplates()

  // بحث Server-side مع debounce + pagination + RLS
  const customerSearch = useCustomerSearch({ pageSize: 30 })

  // ── Mutations ──────────────────────────────────────────────
  const createPlan = useCreateVisitPlan()
  const addItem = useAddVisitPlanItem()

  // ── Wizard state ───────────────────────────────────────────
  const [step, setStep] = useState(0)
  const [saving, setSaving] = useState(false)

  // ── Step 0: Settings ───────────────────────────────────────
  const canAssignOthers = can(PERMISSIONS.VISIT_PLANS_READ_TEAM) || can(PERMISSIONS.VISIT_PLANS_READ_ALL)
  const [planDate, setPlanDate] = useState(() => new Date().toISOString().slice(0, 10))
  const [planType, setPlanType] = useState<'daily' | 'weekly' | 'campaign' | 'recurring'>('daily')
  const [employeeId, setEmployeeId] = useState('')
  const [templateId, setTemplateId] = useState('')
  const [notes, setNotes] = useState('')

  // Set default employee
  useEffect(() => {
    if (currentEmployee?.id && !employeeId) {
      setEmployeeId(currentEmployee.id)
    }
  }, [currentEmployee, employeeId])

  // ── Check for existing daily plan ──────────────────────────
  const { data: existingPlansResult } = useVisitPlans(
    planType === 'daily' && employeeId ? { employeeId, dateFrom: planDate, dateTo: planDate } : undefined
  )
  const existingPlans = existingPlansResult?.data ?? []
  const hasDailyConflict = planType === 'daily' && existingPlans.length > 0

  // ── Step 1: Customer selection ─────────────────────────────
  const [selectedCustomers, setSelectedCustomers] = useState<SelectedCustomer[]>([])

  const selectedIds = useMemo(() => new Set(selectedCustomers.map(c => c.customerId)), [selectedCustomers])

  const addCustomer = useCallback((cust: CustomerSearchResult) => {
    if (selectedIds.has(cust.id)) return
    setSelectedCustomers(prev => [
      ...prev,
      {
        customerId: cust.id,
        customerName: cust.name,
        customerCode: cust.code || '',
        phone: cust.phone || null,
        latitude: cust.latitude ?? null,
        longitude: cust.longitude ?? null,
        governorate: cust.governorate_name ?? null,
        city: cust.city_name ?? null,
        currentBalance: cust.current_balance ?? 0,
        creditLimit: cust.credit_limit ?? 0,
        sequence: prev.length + 1,
        plannedTime: '',
        estimatedDuration: 30,
        priority: 'normal',
        purposeType: '',
        purpose: '',
      },
    ])
  }, [selectedIds])

  const removeCustomer = useCallback((custId: string) => {
    setSelectedCustomers(prev =>
      prev.filter(c => c.customerId !== custId)
        .map((c, i) => ({ ...c, sequence: i + 1 }))
    )
  }, [])

  // ── Step 2: Reorder + details ──────────────────────────────
  const moveUp = useCallback((index: number) => {
    if (index === 0) return
    setSelectedCustomers(prev => {
      const arr = [...prev]
      ;[arr[index - 1], arr[index]] = [arr[index], arr[index - 1]]
      return arr.map((c, i) => ({ ...c, sequence: i + 1 }))
    })
  }, [])

  const moveDown = useCallback((index: number) => {
    setSelectedCustomers(prev => {
      if (index >= prev.length - 1) return prev
      const arr = [...prev]
      ;[arr[index], arr[index + 1]] = [arr[index + 1], arr[index]]
      return arr.map((c, i) => ({ ...c, sequence: i + 1 }))
    })
  }, [])

  const updateCustomerField = useCallback(<K extends keyof SelectedCustomer>(
    custId: string, field: K, value: SelectedCustomer[K]
  ) => {
    setSelectedCustomers(prev =>
      prev.map(c => c.customerId === custId ? { ...c, [field]: value } : c)
    )
  }, [])

  // ── Step validation ────────────────────────────────────────
  function canProceed(): boolean {
    switch (step) {
      case 0:
        return !!planDate && !!employeeId && !hasDailyConflict
      case 1:
        return selectedCustomers.length > 0
      case 2:
        return selectedCustomers.length > 0
      case 3:
        return true
      default:
        return false
    }
  }

  // ── Submit ─────────────────────────────────────────────────
  const handleCreate = async () => {
    if (!employeeId) { toast.error('يجب تحديد الموظف'); return }
    if (selectedCustomers.length === 0) { toast.error('يجب إضافة عميل واحد على الأقل'); return }
    setSaving(true)

    try {
      // 1. Create the plan
      const planPayload: VisitPlanInput = {
        employee_id: employeeId,
        plan_date: planDate,
        plan_type: planType,
        template_id: templateId || null,
        notes: notes || null,
      }

      const plan = await createPlan.mutateAsync(planPayload)

      // 2. Add items in parallel (Promise.all — أسرع بكثير مع 20+ عميل)
      await Promise.all(
        selectedCustomers.map(cust => {
          const itemPayload: VisitPlanItemInput = {
            customer_id: cust.customerId,
            sequence: cust.sequence,
            planned_time: cust.plannedTime || null,
            estimated_duration_min: cust.estimatedDuration,
            priority: cust.priority,
            purpose: cust.purpose || null,
            purpose_type: (cust.purposeType as PlanItemPurposeType) || null,
          }
          return addItem.mutateAsync({ planId: plan.id, item: itemPayload })
        })
      )

      // 3. حفظ كمسودة (بدون تأكيد تلقائي)
      toast.success('تم إنشاء خطة الزيارات كمسودة بنجاح')

      navigate(`/activities/visit-plans/${plan.id}`)
    } catch (err: any) {
      toast.error(err?.message || 'فشل إنشاء الخطة')
      setSaving(false)
    }
  }

  // ── Template load ──────────────────────────────────────────
  const handleLoadTemplate = (tmplId: string) => {
    setTemplateId(tmplId)
    const tmpl = templates.find(t => t.id === tmplId)
    if (!tmpl?.items || !Array.isArray(tmpl.items)) return

    // القالب يخزّن customer_id + بيانات أساسية
    // نبني البنود مباشرة من بيانات القالب
    const newItems: SelectedCustomer[] = tmpl.items
      .map((item: any, i: number) => {
        if (!item.customer_id) return null
        return {
          customerId: item.customer_id,
          customerName: item.customer_name || `عميل ${i + 1}`,
          customerCode: item.customer_code || '',
          phone: item.phone || null,
          latitude: item.latitude ?? null,
          longitude: item.longitude ?? null,
          governorate: null,
          city: null,
          currentBalance: 0,
          creditLimit: 0,
          sequence: i + 1,
          plannedTime: item.planned_time || '',
          estimatedDuration: item.estimated_duration_min || 30,
          priority: item.priority || 'normal',
          purposeType: item.purpose_type || '',
          purpose: item.purpose || '',
        }
      })
      .filter(Boolean) as SelectedCustomer[]

    if (newItems.length > 0) {
      setSelectedCustomers(newItems)
      toast.success(`تم تحميل ${newItems.length} عميل من القالب`)
    }
  }

  const selectedEmployee = allEmployees.find(e => e.id === employeeId)

  // ═══════════════════════════════════════════════════════════
  // RENDER
  // ═══════════════════════════════════════════════════════════
  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="خطة زيارات جديدة"
        subtitle="إنشاء خطة زيارات ميدانية"
        breadcrumbs={[
          { label: 'خطط الزيارات', path: '/activities/visit-plans' },
          { label: 'جديد' },
        ]}
      />

      <div className="vpw">
        <Stepper steps={WIZARD_STEPS} currentStep={step} />

        <div className="vpw-body">

          {/* ═══════════ STEP 0: Settings ═══════════ */}
          {step === 0 && (
            <div className="vpw-step vpw-step--settings animate-enter">
              <div className="vpw-section-title">
                <Settings2 size={20} />
                <span>إعدادات الخطة</span>
              </div>

              <div className="vpw-settings-grid">
                {/* التاريخ */}
                <div className="form-group">
                  <label className="form-label">تاريخ الخطة <span className="form-required">*</span></label>
                  <input
                    type="date"
                    className="form-input"
                    value={planDate}
                    onChange={e => setPlanDate(e.target.value)}
                    required
                  />
                </div>

                {/* نوع الخطة */}
                <div className="form-group">
                  <label className="form-label">نوع الخطة <span className="form-required">*</span></label>
                  <div className="vpw-type-chips">
                    {PLAN_TYPES.map(pt => (
                      <button
                        key={pt.value}
                        type="button"
                        className={`vpw-type-chip${planType === pt.value ? ' vpw-type-chip--active' : ''}`}
                        onClick={() => setPlanType(pt.value)}
                      >
                        <span className="vpw-type-chip-label">{pt.label}</span>
                        <span className="vpw-type-chip-desc">{pt.desc}</span>
                      </button>
                    ))}
                  </div>
                </div>

                {/* الموظف */}
                <div className="form-group">
                  <label className="form-label">الموظف <span className="form-required">*</span></label>
                  {canAssignOthers ? (
                    <select
                      className="form-select"
                      value={employeeId}
                      onChange={e => setEmployeeId(e.target.value)}
                    >
                      <option value="">-- اختر الموظف --</option>
                      {allEmployees.map(emp => (
                        <option key={emp.id} value={emp.id}>{emp.full_name}</option>
                      ))}
                    </select>
                  ) : (
                    <div className="vpw-employee-badge">
                      <Users size={16} />
                      <span>{currentEmployee?.full_name || 'جاري التحميل...'}</span>
                    </div>
                  )}
                </div>

                {/* القالب */}
                {templates.length > 0 && (
                  <div className="form-group">
                    <label className="form-label">تحميل من قالب</label>
                    <select
                      className="form-select"
                      value={templateId}
                      onChange={e => handleLoadTemplate(e.target.value)}
                    >
                      <option value="">-- بدون قالب --</option>
                      {templates.map(t => (
                        <option key={t.id} value={t.id}>{t.name}</option>
                      ))}
                    </select>
                  </div>
                )}

                {/* ملاحظات */}
                <div className="form-group" style={{ gridColumn: '1 / -1' }}>
                  <label className="form-label">ملاحظات</label>
                  <textarea
                    className="form-textarea"
                    rows={2}
                    value={notes}
                    onChange={e => setNotes(e.target.value)}
                    placeholder="ملاحظات اختيارية على الخطة..."
                  />
                </div>
              </div>

              {/* Daily conflict warning */}
              {hasDailyConflict && (
                <div className="vpw-warning">
                  ⚠ يوجد بالفعل خطة يومية لهذا الموظف في {planDate} — لا يمكن إنشاء خطة يومية أخرى
                </div>
              )}
            </div>
          )}

          {/* ═══════════ STEP 1: Customer Selection ═══════════ */}
          {step === 1 && (
            <div className="vpw-step vpw-step--customers animate-enter">
              <div className="vpw-section-title">
                <Users size={20} />
                <span>اختيار العملاء</span>
                <span className="vpw-badge">{selectedCustomers.length}</span>
              </div>

              {/* Search bar */}
              <div className="vpw-search">
                <Search size={18} className="vpw-search-icon" />
                <input
                  className="vpw-search-input"
                  placeholder="ابحث بالاسم أو الكود أو الهاتف..."
                  value={customerSearch.search}
                  onChange={e => customerSearch.setSearch(e.target.value)}
                  autoFocus
                />
                {customerSearch.search && (
                  <span className="vpw-search-count">
                    {customerSearch.totalCount} نتيجة
                  </span>
                )}
              </div>

              {/* Customer search results */}
              <div className="vpw-customer-list">
                {customerSearch.isLoading && customerSearch.results.length === 0 ? (
                  <div className="page-container animate-enter">
                    <div className="edara-card max-w-[760px] mx-auto p-6">
                      {[1, 2, 3].map(i => <CardSkeleton key={i} />)}
                    </div>
                  </div>
                ) : customerSearch.results.length === 0 && customerSearch.search ? (
                  <div className="vpw-empty">لا توجد نتائج لـ "{customerSearch.search}"</div>
                ) : customerSearch.results.length === 0 ? (
                  <div className="vpw-empty">ابحث عن عميل بالاسم أو الكود أو الهاتف</div>
                ) : (
                  <>
                    {customerSearch.results.map(cust => (
                      <CustomerSearchCard
                        key={cust.id}
                        customer={cust}
                        isSelected={selectedIds.has(cust.id)}
                        onAdd={(c) => addCustomer(c)}
                        compact
                      />
                    ))}
                    {customerSearch.hasMore && (
                      <button
                        type="button"
                        className="vpw-load-more"
                        onClick={customerSearch.loadMore}
                        disabled={customerSearch.isLoading}
                      >
                        {customerSearch.isLoading ? (
                          <><Loader2 size={14} className="vpw-spin" /> جاري التحميل...</>
                        ) : (
                          <>تحميل المزيد ({customerSearch.totalCount - customerSearch.results.length} متبقي)</>
                        )}
                      </button>
                    )}
                  </>
                )}
              </div>

              {/* Selected count */}
              {selectedCustomers.length > 0 && (
                <div className="vpw-selected-summary">
                  <Check size={16} />
                  تم اختيار {selectedCustomers.length} عميل
                </div>
              )}
            </div>
          )}

          {/* ═══════════ STEP 2: Details & Order ═══════════ */}
          {step === 2 && (
            <div className="vpw-step vpw-step--details animate-enter">
              <div className="vpw-section-title">
                <ClipboardList size={20} />
                <span>ترتيب وتفاصيل الزيارات</span>
              </div>

              <div className="vpw-items-list">
                {selectedCustomers.map((cust, idx) => (
                  <div key={cust.customerId} className="vpw-item-card">
                    <div className="vpw-item-header">
                      <div className="vpw-item-order">
                        <button
                          type="button"
                          className="vpw-order-btn"
                          onClick={() => moveUp(idx)}
                          disabled={idx === 0}
                          aria-label="تحريك للأعلى"
                        >
                          <ArrowUp size={14} />
                        </button>
                        <span className="vpw-item-seq">{cust.sequence}</span>
                        <button
                          type="button"
                          className="vpw-order-btn"
                          onClick={() => moveDown(idx)}
                          disabled={idx === selectedCustomers.length - 1}
                          aria-label="تحريك للأسفل"
                        >
                          <ArrowDown size={14} />
                        </button>
                      </div>
                      <div className="vpw-item-name">
                        <strong>{cust.customerName}</strong>
                        <span className="vpw-item-code">{cust.customerCode}</span>
                      </div>
                      <button
                        type="button"
                        className="vpw-item-remove"
                        onClick={() => removeCustomer(cust.customerId)}
                        aria-label="حذف"
                      >
                        <Trash2 size={14} />
                      </button>
                    </div>

                    <div className="vpw-item-fields">
                      {/* الأولوية */}
                      <div className="form-group vpw-field-sm">
                        <label className="form-label">الأولوية</label>
                        <select
                          className="form-select"
                          value={cust.priority}
                          onChange={e => updateCustomerField(cust.customerId, 'priority', e.target.value as PlanPriority)}
                        >
                          {PRIORITY_OPTIONS.map(p => (
                            <option key={p.value} value={p.value}>{p.label}</option>
                          ))}
                        </select>
                      </div>

                      {/* غرض الزيارة */}
                      <div className="form-group vpw-field-sm">
                        <label className="form-label">الغرض</label>
                        <select
                          className="form-select"
                          value={cust.purposeType}
                          onChange={e => updateCustomerField(cust.customerId, 'purposeType', e.target.value as PlanItemPurposeType | '')}
                        >
                          <option value="">— غير محدد —</option>
                          {PURPOSE_OPTIONS.map(p => (
                            <option key={p.value} value={p.value}>{p.label}</option>
                          ))}
                        </select>
                      </div>

                      {/* الوقت المخطط */}
                      <div className="form-group vpw-field-sm">
                        <label className="form-label flex items-center gap-1">
                          <Clock size={12} className="text-muted" />
                          الوقت
                        </label>
                        <input
                          type="time"
                          className="form-input"
                          value={cust.plannedTime}
                          onChange={e => updateCustomerField(cust.customerId, 'plannedTime', e.target.value)}
                        />
                      </div>

                      {/* المدة المقدرة */}
                      <div className="form-group vpw-field-sm">
                        <label className="form-label">المدة (دقيقة)</label>
                        <input
                          type="number"
                          className="form-input"
                          value={cust.estimatedDuration}
                          onChange={e => updateCustomerField(cust.customerId, 'estimatedDuration', Math.max(5, Number(e.target.value)))}
                          min={5}
                          max={480}
                        />
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* ═══════════ STEP 3: Review ═══════════ */}
          {step === 3 && (
            <div className="vpw-step vpw-step--review animate-enter">
              <div className="vpw-section-title">
                <Eye size={20} />
                <span>مراجعة الخطة</span>
              </div>

              <div className="vpw-review-card">
                <div className="vpw-review-row">
                  <span className="vpw-review-label">التاريخ</span>
                  <span className="vpw-review-value">{planDate}</span>
                </div>
                <div className="vpw-review-row">
                  <span className="vpw-review-label">النوع</span>
                  <span className="vpw-review-value">{PLAN_TYPES.find(t => t.value === planType)?.label}</span>
                </div>
                <div className="vpw-review-row">
                  <span className="vpw-review-label">الموظف</span>
                  <span className="vpw-review-value">{selectedEmployee?.full_name || currentEmployee?.full_name}</span>
                </div>
                <div className="vpw-review-row">
                  <span className="vpw-review-label">عدد العملاء</span>
                  <span className="vpw-review-value vpw-review-value--highlight">{selectedCustomers.length}</span>
                </div>
                {notes && (
                  <div className="vpw-review-row">
                    <span className="vpw-review-label">ملاحظات</span>
                    <span className="vpw-review-value">{notes}</span>
                  </div>
                )}
              </div>

              {/* Customer summary list */}
              <div className="vpw-review-items-title">بنود الزيارات</div>
              <div className="vpw-review-items">
                {selectedCustomers.map(cust => (
                  <div key={cust.customerId} className="vpw-review-item">
                    <span className="vpw-review-item-seq">{cust.sequence}</span>
                    <div className="vpw-review-item-info">
                      <span className="vpw-review-item-name">{cust.customerName}</span>
                      <span className="vpw-review-item-meta">
                        {PRIORITY_OPTIONS.find(p => p.value === cust.priority)?.label || 'عادية'}
                        {cust.purposeType && ` · ${PURPOSE_OPTIONS.find(p => p.value === cust.purposeType)?.label}`}
                        {cust.plannedTime && ` · ${cust.plannedTime}`}
                      </span>
                    </div>
                    <span className="vpw-review-item-duration">{cust.estimatedDuration} د</span>
                  </div>
                ))}
              </div>

              {/* Total duration */}
              <div className="vpw-review-total">
                <Clock size={16} />
                إجمالي الوقت المقدر: {selectedCustomers.reduce((s, c) => s + c.estimatedDuration, 0)} دقيقة
              </div>
            </div>
          )}
        </div>

        {/* ═══════════ Navigation buttons ═══════════ */}
        <div className="vpw-nav">
          {step > 0 && (
            <Button
              type="button"
              variant="secondary"
              onClick={() => setStep(s => s - 1)}
              disabled={saving}
            >
              <ChevronRight size={16} />
              السابق
            </Button>
          )}
          {step === 0 && (
            <Button
              type="button"
              variant="secondary"
              onClick={() => navigate('/activities/visit-plans')}
            >
              إلغاء
            </Button>
          )}

          <div style={{ flex: 1 }} />

          {step < 3 ? (
            <Button
              type="button"
              onClick={() => setStep(s => s + 1)}
              disabled={!canProceed()}
            >
              التالي
              <ChevronLeft size={16} />
            </Button>
          ) : (
            <Button
              type="button"
              onClick={handleCreate}
              disabled={saving || selectedCustomers.length === 0}
            >
              {saving ? 'جاري الحفظ...' : '✅ حفظ كمسودة'}
            </Button>
          )}
        </div>
      </div>

      {/* ═══════════ STYLES ═══════════ */}
      <style>{`
        .vpw {
          max-width: 800px;
          margin: 0 auto;
          display: flex;
          flex-direction: column;
          gap: var(--space-4);
        }

        .vpw-body {
          background: var(--bg-surface);
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-xl);
          padding: var(--space-6);
          min-height: 400px;
        }

        /* ── Section title ── */
        .vpw-section-title {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          font-size: var(--text-lg);
          font-weight: 700;
          color: var(--text-primary);
          margin-bottom: var(--space-5);
          padding-bottom: var(--space-3);
          border-bottom: 2px solid var(--color-primary-light);
        }
        .vpw-section-title svg { color: var(--color-primary); }

        .vpw-badge {
          margin-inline-start: auto;
          background: var(--color-primary);
          color: #fff;
          border-radius: var(--radius-full);
          min-width: 24px;
          height: 24px;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: var(--text-xs);
          font-weight: 700;
        }

        /* ── Step 0: Settings grid ── */
        .vpw-settings-grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: var(--space-4);
        }

        .vpw-type-chips {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: var(--space-2);
        }

        .vpw-type-chip {
          display: flex;
          flex-direction: column;
          align-items: flex-start;
          padding: var(--space-3);
          border: 2px solid var(--border-primary);
          border-radius: var(--radius-lg);
          background: var(--bg-surface);
          cursor: pointer;
          transition: all var(--transition-fast);
          text-align: start;
          font-family: inherit;
        }
        .vpw-type-chip:hover { border-color: var(--color-primary); }
        .vpw-type-chip--active {
          border-color: var(--color-primary);
          background: var(--color-primary-light);
        }
        .vpw-type-chip-label {
          font-size: var(--text-sm);
          font-weight: 700;
          color: var(--text-primary);
        }
        .vpw-type-chip--active .vpw-type-chip-label { color: var(--color-primary); }
        .vpw-type-chip-desc {
          font-size: var(--text-xs);
          color: var(--text-muted);
          margin-top: 2px;
        }

        .vpw-employee-badge {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          padding: var(--space-3);
          background: var(--bg-surface-2);
          border-radius: var(--radius-md);
          font-size: var(--text-sm);
          font-weight: 600;
          color: var(--text-primary);
        }

        .vpw-warning {
          margin-top: var(--space-4);
          padding: var(--space-3) var(--space-4);
          background: var(--color-warning-light);
          border: 1px solid var(--color-warning);
          border-radius: var(--radius-md);
          font-size: var(--text-sm);
          color: var(--color-warning);
          font-weight: 600;
        }

        /* ── Step 1: Search ── */
        .vpw-search {
          position: relative;
          margin-bottom: var(--space-4);
        }
        .vpw-search-icon {
          position: absolute;
          top: 50%;
          inset-inline-start: var(--space-3);
          transform: translateY(-50%);
          color: var(--text-muted);
          pointer-events: none;
        }
        .vpw-search-input {
          width: 100%;
          padding: var(--space-3) var(--space-3) var(--space-3) calc(var(--space-3) + 28px);
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-lg);
          font-size: var(--text-sm);
          font-family: inherit;
          background: var(--bg-surface);
          color: var(--text-primary);
          transition: border-color var(--transition-fast);
        }
        .vpw-search-input:focus {
          outline: none;
          border-color: var(--color-primary);
          box-shadow: 0 0 0 3px var(--color-primary-light);
        }

        /* ── Step 1: Customer list ── */
        .vpw-customer-list {
          display: grid;
          grid-template-columns: 1fr;
          gap: var(--space-2);
          max-height: 400px;
          overflow-y: auto;
          padding-inline-end: var(--space-1);
        }

        .vpw-customer-card {
          display: flex;
          align-items: center;
          gap: var(--space-3);
          padding: var(--space-3) var(--space-4);
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-md);
          cursor: pointer;
          transition: all var(--transition-fast);
          background: var(--bg-surface);
        }
        .vpw-customer-card:hover {
          border-color: var(--color-primary);
          transform: translateY(-1px);
          box-shadow: var(--shadow-sm);
        }
        .vpw-customer-card--selected {
          border-color: var(--color-primary);
          background: var(--color-primary-light);
        }

        .vpw-customer-card-check {
          width: 20px;
          height: 20px;
          border-radius: var(--radius-sm);
          border: 2px solid var(--border-primary);
          display: flex;
          align-items: center;
          justify-content: center;
          flex-shrink: 0;
          transition: all var(--transition-fast);
        }
        .vpw-customer-card--selected .vpw-customer-card-check {
          background: var(--color-primary);
          border-color: var(--color-primary);
          color: #fff;
        }

        .vpw-customer-card-info { flex: 1; min-width: 0; }
        .vpw-customer-name {
          display: block;
          font-size: var(--text-sm);
          font-weight: 600;
          color: var(--text-primary);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .vpw-customer-meta {
          display: block;
          font-size: var(--text-xs);
          color: var(--text-muted);
          margin-top: 2px;
        }
        .vpw-customer-gps { color: var(--color-success); flex-shrink: 0; }

        .vpw-selected-summary {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          margin-top: var(--space-4);
          padding: var(--space-3) var(--space-4);
          background: var(--color-success-light);
          border-radius: var(--radius-md);
          font-size: var(--text-sm);
          font-weight: 600;
          color: var(--color-success);
        }

        .vpw-skeleton-list { display: flex; flex-direction: column; gap: var(--space-2); }
        .vpw-skeleton-item { height: 48px; border-radius: var(--radius-md); }
        .vpw-empty {
          text-align: center;
          padding: var(--space-8);
          color: var(--text-muted);
          font-size: var(--text-sm);
        }

        .vpw-load-more {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: var(--space-2);
          width: 100%;
          padding: var(--space-3);
          border: 1px dashed var(--border-primary);
          border-radius: var(--radius-md);
          background: var(--bg-surface-2);
          cursor: pointer;
          font-size: var(--text-xs);
          font-weight: 600;
          color: var(--color-primary);
          font-family: inherit;
          transition: all var(--transition-fast);
        }
        .vpw-load-more:hover { background: var(--color-primary-light); }
        .vpw-load-more:disabled { opacity: 0.6; cursor: wait; }

        .vpw-search-count {
          position: absolute;
          top: 50%;
          inset-inline-end: var(--space-3);
          transform: translateY(-50%);
          font-size: var(--text-xs);
          color: var(--text-muted);
          font-weight: 500;
        }

        .vpw-spin { animation: vpw-spin-anim 1s linear infinite; }
        @keyframes vpw-spin-anim { to { transform: rotate(360deg); } }

        /* ── Step 2: Items ── */
        .vpw-items-list {
          display: flex;
          flex-direction: column;
          gap: var(--space-3);
        }

        .vpw-item-card {
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-lg);
          overflow: hidden;
          background: var(--bg-surface);
          transition: box-shadow var(--transition-fast);
        }
        .vpw-item-card:hover { box-shadow: var(--shadow-sm); }

        .vpw-item-header {
          display: flex;
          align-items: center;
          gap: var(--space-3);
          padding: var(--space-3) var(--space-4);
          background: var(--bg-surface-2);
          border-bottom: 1px solid var(--border-primary);
        }

        .vpw-item-order {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 2px;
        }

        .vpw-order-btn {
          width: 24px;
          height: 20px;
          display: flex;
          align-items: center;
          justify-content: center;
          border: none;
          background: none;
          color: var(--text-muted);
          cursor: pointer;
          border-radius: var(--radius-sm);
          transition: all var(--transition-fast);
          padding: 0;
        }
        .vpw-order-btn:hover:not(:disabled) {
          color: var(--color-primary);
          background: var(--color-primary-light);
        }
        .vpw-order-btn:disabled { opacity: 0.3; cursor: default; }

        .vpw-item-seq {
          font-size: var(--text-xs);
          font-weight: 700;
          color: var(--color-primary);
          min-width: 18px;
          text-align: center;
        }

        .vpw-item-name { flex: 1; min-width: 0; }
        .vpw-item-name strong {
          font-size: var(--text-sm);
          color: var(--text-primary);
        }
        .vpw-item-code {
          font-size: var(--text-xs);
          color: var(--text-muted);
          margin-inline-start: var(--space-2);
        }

        .vpw-item-remove {
          width: 32px;
          height: 32px;
          display: flex;
          align-items: center;
          justify-content: center;
          border: none;
          background: none;
          color: var(--text-muted);
          cursor: pointer;
          border-radius: var(--radius-md);
          transition: all var(--transition-fast);
          padding: 0;
        }
        .vpw-item-remove:hover {
          color: var(--color-danger);
          background: var(--color-danger-light);
        }

        .vpw-item-fields {
          display: grid;
          grid-template-columns: repeat(4, 1fr);
          gap: var(--space-3);
          padding: var(--space-3) var(--space-4);
        }

        .vpw-field-sm .form-label {
          font-size: 0.7rem;
          margin-bottom: var(--space-1);
          display: flex;
          align-items: center;
        }
        .vpw-field-sm .form-select,
        .vpw-field-sm .form-input {
          font-size: var(--text-xs);
          padding: var(--space-2);
        }

        /* ── Step 3: Review ── */
        .vpw-review-card {
          background: var(--bg-surface-2);
          border-radius: var(--radius-lg);
          padding: var(--space-4);
          display: flex;
          flex-direction: column;
          gap: var(--space-2);
          margin-bottom: var(--space-5);
        }
        .vpw-review-row {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: var(--space-2) 0;
        }
        .vpw-review-row:not(:last-child) {
          border-bottom: 1px solid var(--border-primary);
        }
        .vpw-review-label {
          font-size: var(--text-sm);
          color: var(--text-muted);
          font-weight: 500;
        }
        .vpw-review-value {
          font-size: var(--text-sm);
          color: var(--text-primary);
          font-weight: 600;
        }
        .vpw-review-value--highlight {
          background: var(--color-primary);
          color: #fff;
          border-radius: var(--radius-full);
          min-width: 28px;
          height: 28px;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: var(--text-sm);
          font-weight: 700;
        }

        .vpw-review-items-title {
          font-size: var(--text-sm);
          font-weight: 700;
          color: var(--text-primary);
          margin-bottom: var(--space-3);
        }

        .vpw-review-items {
          display: flex;
          flex-direction: column;
          gap: var(--space-2);
        }

        .vpw-review-item {
          display: flex;
          align-items: center;
          gap: var(--space-3);
          padding: var(--space-3);
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-md);
          background: var(--bg-surface);
        }
        .vpw-review-item-seq {
          width: 24px;
          height: 24px;
          border-radius: var(--radius-full);
          background: var(--color-primary-light);
          color: var(--color-primary);
          font-size: var(--text-xs);
          font-weight: 700;
          display: flex;
          align-items: center;
          justify-content: center;
          flex-shrink: 0;
        }
        .vpw-review-item-info { flex: 1; min-width: 0; }
        .vpw-review-item-name {
          display: block;
          font-size: var(--text-sm);
          font-weight: 600;
          color: var(--text-primary);
        }
        .vpw-review-item-meta {
          display: block;
          font-size: var(--text-xs);
          color: var(--text-muted);
          margin-top: 2px;
        }
        .vpw-review-item-duration {
          font-size: var(--text-xs);
          font-weight: 600;
          color: var(--text-muted);
          white-space: nowrap;
        }

        .vpw-review-total {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          margin-top: var(--space-4);
          padding: var(--space-3) var(--space-4);
          background: var(--color-info-light);
          border-radius: var(--radius-md);
          font-size: var(--text-sm);
          font-weight: 600;
          color: var(--color-info);
        }
        .vpw-review-total svg { flex-shrink: 0; }

        /* ── Navigation ── */
        .vpw-nav {
          display: flex;
          align-items: center;
          gap: var(--space-3);
          padding-top: var(--space-3);
          border-top: 1px solid var(--border-primary);
        }

        /* ── Responsive ── */
        @media (max-width: 640px) {
          .vpw-body { padding: var(--space-4); }
          .vpw-settings-grid { grid-template-columns: 1fr; }
          .vpw-type-chips { grid-template-columns: 1fr; }
          .vpw-item-fields { grid-template-columns: 1fr 1fr; }
          .vpw-search-input { padding-inline-start: calc(var(--space-3) + 26px); }
        }

        @media (max-width: 480px) {
          .vpw-item-fields { grid-template-columns: 1fr; }
        }

        /* ── Skeleton animation ── */
        .skeleton {
          background: linear-gradient(
            90deg,
            var(--bg-surface-2) 25%,
            var(--border-primary) 50%,
            var(--bg-surface-2) 75%
          );
          background-size: 200% 100%;
          animation: shimmer 1.5s infinite;
        }
        @keyframes shimmer {
          0% { background-position: 200% 0; }
          100% { background-position: -200% 0; }
        }
      `}</style>
    </div>
  )
}
