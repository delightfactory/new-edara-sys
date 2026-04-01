/**
 * CallPlanWizard — إنشاء خطة مكالمات بـ 4 خطوات
 *
 * الخطوة 0: إعدادات الخطة (تاريخ + نوع + موظف + قالب)
 * الخطوة 1: اختيار جهات الاتصال (عملاء مسجلون أو أرقام خارجية)
 * الخطوة 2: ضبط ترتيب + أولوية + غرض + وقت مخطط
 * الخطوة 3: معاينة + تأكيد
 */
import { useState, useMemo, useCallback, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import {
  useCreateCallPlan,
  useAddCallPlanItem,
  useCurrentEmployee,
  useHREmployees,
  useCallPlanTemplates,
  useCallPlans,
} from '@/hooks/useQueryHooks'
import { useCustomerSearch } from '@/hooks/useCustomerSearch'
import { useAuthStore } from '@/stores/auth-store'
import { PERMISSIONS } from '@/lib/permissions/constants'
import PageHeader from '@/components/shared/PageHeader'
import Stepper from '@/components/ui/Stepper'
import Button from '@/components/ui/Button'
import { CardSkeleton } from '@/components/ui/Skeleton'
import CustomerSearchCard from '@/components/shared/CustomerSearchCard'
import type {
  CallPlanInput,
  CallPlanItemInput,
  PlanItemPurposeType,
  PlanPriority,
} from '@/lib/types/activities'
import type { CustomerSearchResult } from '@/hooks/useCustomerSearch'
import {
  Search, Plus, Trash2, Clock, ArrowUp, ArrowDown,
  Check, ChevronLeft, ChevronRight, Users, ClipboardList,
  Settings2, Eye, Phone, UserCheck, Loader2,
} from 'lucide-react'

// ── Step definitions ─────────────────────────────────────────
const WIZARD_STEPS = [
  { label: 'الإعدادات', description: 'تاريخ ونوع الخطة' },
  { label: 'جهات الاتصال', description: 'اختيار من تتصل بهم' },
  { label: 'التفاصيل', description: 'الترتيب والأولوية' },
  { label: 'المراجعة', description: 'التأكيد والإنشاء' },
]

const PLAN_TYPES = [
  { value: 'daily' as const, label: 'يومية', desc: 'خطة ليوم واحد' },
  { value: 'weekly' as const, label: 'أسبوعية', desc: 'خطة لأسبوع كامل' },
  { value: 'campaign' as const, label: 'حملة', desc: 'حملة ترويجية أو موسمية' },
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

// ── Contact item — يمثّل إما عميل مسجل أو جهة خارجية ──────────
interface SelectedContact {
  // يُملأ أحد الاثنين فقط
  customerId: string | null
  customerName: string          // اسم العميل أو اسم جهة الاتصال الخارجية
  customerCode: string
  // للجهات الخارجية
  contactName: string
  phoneNumber: string
  // مشترك
  sequence: number
  plannedTime: string
  estimatedDuration: number
  priority: PlanPriority
  purposeType: PlanItemPurposeType | ''
  purpose: string
  isExternal: boolean
}

type ContactMode = 'customers' | 'external'

export default function CallPlanWizard() {
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)

  // ── Queries ────────────────────────────────────────────────
  const { data: currentEmployee } = useCurrentEmployee()
  const { data: employeesResult } = useHREmployees({ status: 'active' })
  const allEmployees = employeesResult?.data ?? []
  const { data: templates = [] } = useCallPlanTemplates()

  // بحث Server-side مع debounce
  const customerSearch = useCustomerSearch({ pageSize: 30 })

  // ── Mutations ──────────────────────────────────────────────
  const createPlan   = useCreateCallPlan()
  const addItem      = useAddCallPlanItem()

  // ── Wizard state ───────────────────────────────────────────
  const [step, setStep]   = useState(0)
  const [saving, setSaving] = useState(false)

  // ── Step 0: Settings ───────────────────────────────────────
  const canAssignOthers = can(PERMISSIONS.CALL_PLANS_READ_TEAM) || can(PERMISSIONS.CALL_PLANS_READ_ALL)
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

  // ── Check for existing daily call plan conflict ────────────
  const { data: existingPlansResult } = useCallPlans(
    planType === 'daily' && employeeId
      ? { employeeId, dateFrom: planDate, dateTo: planDate }
      : undefined
  )
  const existingPlans = existingPlansResult?.data ?? []
  const hasDailyConflict = planType === 'daily' && existingPlans.length > 0

  // ── Step 1: Contact selection ──────────────────────────────
  const [contactMode, setContactMode] = useState<ContactMode>('customers')
  const [searchTerm, setSearchTerm] = useState('')
  const [selectedContacts, setSelectedContacts] = useState<SelectedContact[]>([])

  // External contact form fields
  const [extPhone, setExtPhone] = useState('')
  const [extName, setExtName]   = useState('')

  const selectedCustomerIds = useMemo(
    () => new Set(selectedContacts.filter(c => c.customerId).map(c => c.customerId!)),
    [selectedContacts]
  )

  const addCustomer = useCallback((cust: CustomerSearchResult) => {
    if (selectedCustomerIds.has(cust.id)) return
    setSelectedContacts(prev => [
      ...prev,
      {
        customerId: cust.id,
        customerName: cust.name,
        customerCode: cust.code || '',
        contactName: '',
        phoneNumber: cust.phone || '',
        sequence: prev.length + 1,
        plannedTime: '',
        estimatedDuration: 10,
        priority: 'normal',
        purposeType: '',
        purpose: '',
        isExternal: false,
      },
    ])
  }, [selectedCustomerIds])

  const addExternalContact = useCallback(() => {
    if (!extPhone.trim()) {
      toast.error('أدخل رقم الهاتف')
      return
    }
    setSelectedContacts(prev => [
      ...prev,
      {
        customerId: null,
        customerName: extName.trim() || extPhone.trim(),
        customerCode: '',
        contactName: extName.trim(),
        phoneNumber: extPhone.trim(),
        sequence: prev.length + 1,
        plannedTime: '',
        estimatedDuration: 10,
        priority: 'normal',
        purposeType: '',
        purpose: '',
        isExternal: true,
      },
    ])
    setExtPhone('')
    setExtName('')
  }, [extPhone, extName])

  const removeContact = useCallback((idx: number) => {
    setSelectedContacts(prev =>
      prev.filter((_, i) => i !== idx)
        .map((c, i) => ({ ...c, sequence: i + 1 }))
    )
  }, [])

  // ── Step 2: Reorder + details ──────────────────────────────
  const moveUp = useCallback((index: number) => {
    if (index === 0) return
    setSelectedContacts(prev => {
      const arr = [...prev]
      ;[arr[index - 1], arr[index]] = [arr[index], arr[index - 1]]
      return arr.map((c, i) => ({ ...c, sequence: i + 1 }))
    })
  }, [])

  const moveDown = useCallback((index: number) => {
    setSelectedContacts(prev => {
      if (index >= prev.length - 1) return prev
      const arr = [...prev]
      ;[arr[index], arr[index + 1]] = [arr[index + 1], arr[index]]
      return arr.map((c, i) => ({ ...c, sequence: i + 1 }))
    })
  }, [])

  const updateContactField = useCallback(<K extends keyof SelectedContact>(
    idx: number, field: K, value: SelectedContact[K]
  ) => {
    setSelectedContacts(prev =>
      prev.map((c, i) => i === idx ? { ...c, [field]: value } : c)
    )
  }, [])

  // ── Step validation ────────────────────────────────────────
  function canProceed(): boolean {
    switch (step) {
      case 0: return !!planDate && !!employeeId && !hasDailyConflict
      case 1: return selectedContacts.length > 0
      case 2: return selectedContacts.length > 0
      case 3: return true
      default: return false
    }
  }

  // ── Submit ─────────────────────────────────────────────────
  const handleCreate = async () => {
    if (!employeeId) { toast.error('يجب تحديد الموظف'); return }
    if (selectedContacts.length === 0) { toast.error('يجب إضافة جهة اتصال واحدة على الأقل'); return }
    setSaving(true)

    try {
      const planPayload: CallPlanInput = {
        employee_id: employeeId,
        plan_date: planDate,
        plan_type: planType,
        template_id: templateId || null,
        notes: notes || null,
      }

      const plan = await createPlan.mutateAsync(planPayload)

      await Promise.all(
        selectedContacts.map(contact => {
          const itemPayload: CallPlanItemInput = {
            customer_id: contact.customerId || null,
            contact_name: contact.contactName || null,
            phone_number: contact.isExternal ? contact.phoneNumber : null,
            sequence: contact.sequence,
            planned_time: contact.plannedTime || null,
            estimated_duration_min: contact.estimatedDuration,
            priority: contact.priority,
            purpose: contact.purpose || null,
            purpose_type: (contact.purposeType as PlanItemPurposeType) || null,
          }
          return addItem.mutateAsync({ planId: plan.id, item: itemPayload })
        })
      )

      // 3. حفظ كمسودة (بدون تأكيد تلقائي)
      toast.success('تم إنشاء خطة المكالمات كمسودة بنجاح')

      navigate(`/activities/call-plans/${plan.id}`)
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

    const newContacts: SelectedContact[] = tmpl.items
      .map((item: any, i: number) => {
        if (item.customer_id) {
          return {
            customerId: item.customer_id,
            customerName: item.customer_name || `عميل ${i + 1}`,
            customerCode: item.customer_code || '',
            contactName: '',
            phoneNumber: item.phone || '',
            sequence: i + 1,
            plannedTime: item.planned_time || '',
            estimatedDuration: item.estimated_duration_min || 10,
            priority: item.priority || 'normal',
            purposeType: item.purpose_type || '',
            purpose: item.purpose || '',
            isExternal: false,
          }
        } else if (item.phone_number) {
          return {
            customerId: null,
            customerName: item.contact_name || item.phone_number,
            customerCode: '',
            contactName: item.contact_name || '',
            phoneNumber: item.phone_number,
            sequence: i + 1,
            plannedTime: item.planned_time || '',
            estimatedDuration: item.estimated_duration_min || 10,
            priority: item.priority || 'normal',
            purposeType: item.purpose_type || '',
            purpose: item.purpose || '',
            isExternal: true,
          }
        }
        return null
      })
      .filter(Boolean) as SelectedContact[]

    if (newContacts.length > 0) {
      setSelectedContacts(newContacts)
      toast.success(`تم تحميل ${newContacts.length} جهة اتصال من القالب`)
    }
  }

  const selectedEmployee = allEmployees.find(e => e.id === employeeId)

  // ═══════════════════════════════════════════════════════════
  // RENDER
  // ═══════════════════════════════════════════════════════════
  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="خطة مكالمات جديدة"
        subtitle="إنشاء خطة مكالمات ميدانية"
        breadcrumbs={[
          { label: 'خطط المكالمات', path: '/activities/call-plans' },
          { label: 'جديد' },
        ]}
      />

      <div className="cpw">
        <Stepper steps={WIZARD_STEPS} currentStep={step} />

        <div className="cpw-body">

          {/* ═══════════ STEP 0: Settings ═══════════ */}
          {step === 0 && (
            <div className="cpw-step cpw-step--settings animate-enter">
              <div className="cpw-section-title">
                <Settings2 size={20} />
                <span>إعدادات الخطة</span>
              </div>

              <div className="cpw-settings-grid">
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
                  <div className="cpw-type-chips">
                    {PLAN_TYPES.map(pt => (
                      <button
                        key={pt.value}
                        type="button"
                        className={`cpw-type-chip${planType === pt.value ? ' cpw-type-chip--active' : ''}`}
                        onClick={() => setPlanType(pt.value)}
                      >
                        <span className="cpw-type-chip-label">{pt.label}</span>
                        <span className="cpw-type-chip-desc">{pt.desc}</span>
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
                    <div className="cpw-employee-badge">
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
                <div className="form-group col-span-full">
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

              {hasDailyConflict && (
                <div className="cpw-warning">
                  ⚠ يوجد بالفعل خطة مكالمات يومية لهذا الموظف في {planDate} — لا يمكن إنشاء خطة يومية أخرى
                </div>
              )}
            </div>
          )}

          {/* ═══════════ STEP 1: Contact Selection ═══════════ */}
          {step === 1 && (
            <div className="cpw-step cpw-step--contacts animate-enter">
              <div className="cpw-section-title">
                <Phone size={20} />
                <span>اختيار جهات الاتصال</span>
                <span className="cpw-badge">{selectedContacts.length}</span>
              </div>

              {/* Toggle: عملاء مسجلون / خارجيون */}
              <div className="cpw-mode-toggle">
                <button
                  type="button"
                  className={`cpw-mode-btn${contactMode === 'customers' ? ' cpw-mode-btn--active' : ''}`}
                  onClick={() => setContactMode('customers')}
                >
                  <UserCheck size={16} />
                  <span>عملاء مسجلون</span>
                </button>
                <button
                  type="button"
                  className={`cpw-mode-btn${contactMode === 'external' ? ' cpw-mode-btn--active' : ''}`}
                  onClick={() => setContactMode('external')}
                >
                  <Phone size={16} />
                  <span>أرقام خارجية</span>
                </button>
              </div>

              {contactMode === 'customers' ? (
                <>
                  {/* Search bar */}
                  <div className="cpw-search">
                    <Search size={18} className="cpw-search-icon" />
                    <input
                      className="cpw-search-input"
                      placeholder="ابحث بالاسم أو الكود أو الهاتف..."
                      value={customerSearch.search}
                      onChange={e => customerSearch.setSearch(e.target.value)}
                      autoFocus
                    />
                    {customerSearch.search && (
                      <span className="cpw-search-count">{customerSearch.totalCount} نتيجة</span>
                    )}
                  </div>

                  {/* Customer list */}
                  <div className="cpw-contact-list">
                    {customerSearch.isLoading && customerSearch.results.length === 0 ? (
                      <div className="page-container animate-enter">
                        <div className="edara-card max-w-[760px] mx-auto p-6">
                          {[1, 2, 3].map(i => <CardSkeleton key={i} />)}
                        </div>
                      </div>
                    ) : customerSearch.results.length === 0 && customerSearch.search ? (
                      <div className="cpw-empty">لا توجد نتائج لـ "{customerSearch.search}"</div>
                    ) : customerSearch.results.length === 0 ? (
                      <div className="cpw-empty">ابحث عن عميل بالاسم أو الكود أو الهاتف</div>
                    ) : (
                      <>
                        {customerSearch.results.map(cust => (
                          <CustomerSearchCard
                            key={cust.id}
                            customer={cust}
                            isSelected={selectedCustomerIds.has(cust.id)}
                            onAdd={(c) => addCustomer(c)}
                            compact
                          />
                        ))}
                        {customerSearch.hasMore && (
                          <button
                            type="button"
                            className="cpw-load-more"
                            onClick={customerSearch.loadMore}
                            disabled={customerSearch.isLoading}
                          >
                            {customerSearch.isLoading ? (
                              <><Loader2 size={14} className="cpw-spin" /> جاري التحميل...</>
                            ) : (
                              <>تحميل المزيد ({customerSearch.totalCount - customerSearch.results.length} متبقي)</>
                            )}
                          </button>
                        )}
                      </>
                    )}
                  </div>
                </>
              ) : (
                /* External contact form */
                <div className="cpw-external-form">
                  <div className="cpw-external-fields">
                    <div className="form-group">
                      <label className="form-label">رقم الهاتف <span className="form-required">*</span></label>
                      <input
                        className="form-input"
                        type="tel"
                        dir="ltr"
                        value={extPhone}
                        onChange={e => setExtPhone(e.target.value)}
                        placeholder="+20..."
                        onKeyDown={e => e.key === 'Enter' && addExternalContact()}
                      />
                    </div>
                    <div className="form-group">
                      <label className="form-label">اسم جهة الاتصال (اختياري)</label>
                      <input
                        className="form-input"
                        value={extName}
                        onChange={e => setExtName(e.target.value)}
                        placeholder="اذكر الاسم..."
                        onKeyDown={e => e.key === 'Enter' && addExternalContact()}
                      />
                    </div>
                    <Button
                      type="button"
                      icon={<Plus size={16} />}
                      onClick={addExternalContact}
                      className="self-end"
                    >
                      إضافة
                    </Button>
                  </div>
                </div>
              )}

              {/* Selected summary */}
              {selectedContacts.length > 0 && (
                <div className="cpw-selected-summary">
                  <Check size={16} />
                  تم اختيار {selectedContacts.length} جهة اتصال
                  {selectedContacts.filter(c => c.isExternal).length > 0 && (
                    <span className="cpw-ext-badge">
                      {selectedContacts.filter(c => c.isExternal).length} خارجية
                    </span>
                  )}
                </div>
              )}

              {/* Mini list of selected */}
              {selectedContacts.length > 0 && (
                <div className="cpw-selected-mini-list">
                  {selectedContacts.map((c, idx) => (
                    <div key={idx} className="cpw-selected-mini-item">
                      {c.isExternal ? <Phone size={12} /> : <UserCheck size={12} />}
                      <span className="cpw-selected-mini-name">{c.customerName}</span>
                      {c.phoneNumber && (
                        <span className="cpw-selected-mini-phone" dir="ltr">{c.phoneNumber}</span>
                      )}
                      <button
                        className="cpw-selected-mini-remove"
                        onClick={() => removeContact(idx)}
                        aria-label="حذف"
                      >
                        ×
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* ═══════════ STEP 2: Details & Order ═══════════ */}
          {step === 2 && (
            <div className="cpw-step cpw-step--details animate-enter">
              <div className="cpw-section-title">
                <ClipboardList size={20} />
                <span>ترتيب وتفاصيل المكالمات</span>
              </div>

              <div className="cpw-items-list">
                {selectedContacts.map((contact, idx) => (
                  <div key={idx} className="cpw-item-card">
                    <div className="cpw-item-header">
                      <div className="cpw-item-order">
                        <button
                          type="button"
                          className="cpw-order-btn"
                          onClick={() => moveUp(idx)}
                          disabled={idx === 0}
                          aria-label="تحريك للأعلى"
                        >
                          <ArrowUp size={14} />
                        </button>
                        <span className="cpw-item-seq">{contact.sequence}</span>
                        <button
                          type="button"
                          className="cpw-order-btn"
                          onClick={() => moveDown(idx)}
                          disabled={idx === selectedContacts.length - 1}
                          aria-label="تحريك للأسفل"
                        >
                          <ArrowDown size={14} />
                        </button>
                      </div>
                      <div className="cpw-item-name">
                        <strong>{contact.customerName}</strong>
                        {contact.isExternal && (
                          <span className="cpw-item-ext-badge">خارجي</span>
                        )}
                        {contact.phoneNumber && (
                          <span className="cpw-item-phone" dir="ltr">{contact.phoneNumber}</span>
                        )}
                      </div>
                      <button
                        type="button"
                        className="cpw-item-remove"
                        onClick={() => removeContact(idx)}
                        aria-label="حذف"
                      >
                        <Trash2 size={14} />
                      </button>
                    </div>

                    <div className="cpw-item-fields">
                      {/* الأولوية */}
                      <div className="form-group cpw-field-sm">
                        <label className="form-label">الأولوية</label>
                        <select
                          className="form-select"
                          value={contact.priority}
                          onChange={e => updateContactField(idx, 'priority', e.target.value as PlanPriority)}
                        >
                          {PRIORITY_OPTIONS.map(p => (
                            <option key={p.value} value={p.value}>{p.label}</option>
                          ))}
                        </select>
                      </div>

                      {/* غرض المكالمة */}
                      <div className="form-group cpw-field-sm">
                        <label className="form-label">الغرض</label>
                        <select
                          className="form-select"
                          value={contact.purposeType}
                          onChange={e => updateContactField(idx, 'purposeType', e.target.value as PlanItemPurposeType | '')}
                        >
                          <option value="">— غير محدد —</option>
                          {PURPOSE_OPTIONS.map(p => (
                            <option key={p.value} value={p.value}>{p.label}</option>
                          ))}
                        </select>
                      </div>

                      {/* الوقت المخطط */}
                      <div className="form-group cpw-field-sm">
                        <label className="form-label flex items-center gap-1">
                          <Clock size={12} className="text-muted" />
                          الوقت
                        </label>
                        <input
                          type="time"
                          className="form-input"
                          value={contact.plannedTime}
                          onChange={e => updateContactField(idx, 'plannedTime', e.target.value)}
                        />
                      </div>

                      {/* المدة المقدرة */}
                      <div className="form-group cpw-field-sm">
                        <label className="form-label">المدة (دقيقة)</label>
                        <input
                          type="number"
                          className="form-input"
                          value={contact.estimatedDuration}
                          onChange={e => updateContactField(idx, 'estimatedDuration', Math.max(1, Number(e.target.value)))}
                          min={1}
                          max={120}
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
            <div className="cpw-step cpw-step--review animate-enter">
              <div className="cpw-section-title">
                <Eye size={20} />
                <span>مراجعة الخطة</span>
              </div>

              <div className="cpw-review-card">
                <div className="cpw-review-row">
                  <span className="cpw-review-label">التاريخ</span>
                  <span className="cpw-review-value">{planDate}</span>
                </div>
                <div className="cpw-review-row">
                  <span className="cpw-review-label">النوع</span>
                  <span className="cpw-review-value">{PLAN_TYPES.find(t => t.value === planType)?.label}</span>
                </div>
                <div className="cpw-review-row">
                  <span className="cpw-review-label">الموظف</span>
                  <span className="cpw-review-value">{selectedEmployee?.full_name || currentEmployee?.full_name}</span>
                </div>
                <div className="cpw-review-row">
                  <span className="cpw-review-label">جهات الاتصال</span>
                  <span className="cpw-review-value cpw-review-value--highlight">{selectedContacts.length}</span>
                </div>
                <div className="cpw-review-row">
                  <span className="cpw-review-label">منهم خارجيون</span>
                  <span className="cpw-review-value">{selectedContacts.filter(c => c.isExternal).length}</span>
                </div>
                {notes && (
                  <div className="cpw-review-row">
                    <span className="cpw-review-label">ملاحظات</span>
                    <span className="cpw-review-value">{notes}</span>
                  </div>
                )}
              </div>

              {/* Contact summary list */}
              <div className="cpw-review-items-title">بنود المكالمات</div>
              <div className="cpw-review-items">
                {selectedContacts.map(contact => (
                  <div key={contact.sequence} className="cpw-review-item">
                    <span className="cpw-review-item-seq">{contact.sequence}</span>
                    <div className="cpw-review-item-info">
                      <span className="cpw-review-item-name">{contact.customerName}</span>
                      <span className="cpw-review-item-meta">
                        {PRIORITY_OPTIONS.find(p => p.value === contact.priority)?.label || 'عادية'}
                        {contact.purposeType && ` · ${PURPOSE_OPTIONS.find(p => p.value === contact.purposeType)?.label}`}
                        {contact.plannedTime && ` · ${contact.plannedTime}`}
                        {contact.isExternal && ' · خارجي'}
                      </span>
                    </div>
                    <span className="cpw-review-item-duration">{contact.estimatedDuration} د</span>
                  </div>
                ))}
              </div>

              {/* Total duration */}
              <div className="cpw-review-total">
                <Clock size={16} />
                إجمالي الوقت المقدر: {selectedContacts.reduce((s, c) => s + c.estimatedDuration, 0)} دقيقة
              </div>
            </div>
          )}
        </div>

        {/* ═══════════ Navigation buttons ═══════════ */}
        <div className="cpw-nav">
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
              onClick={() => navigate('/activities/call-plans')}
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
              disabled={saving || selectedContacts.length === 0}
            >
              {saving ? 'جاري الإنشاء...' : '✓ إنشاء الخطة'}
            </Button>
          )}
        </div>
      </div>

      {/* ═══════════ STYLES ═══════════ */}
      <style>{`
        .cpw {
          max-width: 800px;
          margin: 0 auto;
          display: flex;
          flex-direction: column;
          gap: var(--space-4);
        }

        .cpw-body {
          background: var(--bg-surface);
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-xl);
          padding: var(--space-6);
          min-height: 400px;
        }

        /* ── Section title ── */
        .cpw-section-title {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          font-size: var(--text-lg);
          font-weight: 700;
          color: var(--text-primary);
          margin-bottom: var(--space-5);
          padding-bottom: var(--space-3);
          border-bottom: 2px solid var(--color-success-light);
        }
        .cpw-section-title svg { color: var(--color-success); }

        .cpw-badge {
          margin-inline-start: auto;
          background: var(--color-success);
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
        .cpw-settings-grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: var(--space-4);
        }

        .cpw-type-chips {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: var(--space-2);
        }

        .cpw-type-chip {
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
        .cpw-type-chip:hover { border-color: var(--color-success); }
        .cpw-type-chip--active {
          border-color: var(--color-success);
          background: var(--color-success-light);
        }
        .cpw-type-chip-label {
          font-size: var(--text-sm);
          font-weight: 700;
          color: var(--text-primary);
        }
        .cpw-type-chip--active .cpw-type-chip-label { color: var(--color-success); }
        .cpw-type-chip-desc {
          font-size: var(--text-xs);
          color: var(--text-muted);
          margin-top: 2px;
        }

        .cpw-employee-badge {
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

        .cpw-warning {
          margin-top: var(--space-4);
          padding: var(--space-3) var(--space-4);
          background: var(--color-warning-light);
          border: 1px solid var(--color-warning);
          border-radius: var(--radius-md);
          font-size: var(--text-sm);
          color: var(--color-warning);
          font-weight: 600;
        }

        /* ── Step 1: Mode Toggle ── */
        .cpw-mode-toggle {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: var(--space-2);
          margin-bottom: var(--space-4);
        }
        .cpw-mode-btn {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: var(--space-2);
          padding: var(--space-3);
          border: 2px solid var(--border-primary);
          border-radius: var(--radius-lg);
          background: var(--bg-surface);
          cursor: pointer;
          font-family: inherit;
          font-size: var(--text-sm);
          font-weight: 600;
          color: var(--text-secondary);
          transition: all var(--transition-fast);
        }
        .cpw-mode-btn:hover { border-color: var(--color-success); }
        .cpw-mode-btn--active {
          border-color: var(--color-success);
          background: var(--color-success-light);
          color: var(--color-success);
        }

        /* ── Step 1: Search ── */
        .cpw-search {
          position: relative;
          margin-bottom: var(--space-4);
        }
        .cpw-search-icon {
          position: absolute;
          top: 50%;
          inset-inline-start: var(--space-3);
          transform: translateY(-50%);
          color: var(--text-muted);
          pointer-events: none;
        }
        .cpw-search-input {
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
        .cpw-search-input:focus {
          outline: none;
          border-color: var(--color-success);
          box-shadow: 0 0 0 3px var(--color-success-light);
        }

        /* ── Contact list ── */
        .cpw-contact-list {
          display: flex;
          flex-direction: column;
          gap: var(--space-2);
          max-height: 300px;
          overflow-y: auto;
          padding-inline-end: var(--space-1);
          margin-bottom: var(--space-4);
        }
        .cpw-contact-card {
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
        .cpw-contact-card:hover {
          border-color: var(--color-success);
          transform: translateY(-1px);
          box-shadow: var(--shadow-sm);
        }
        .cpw-contact-card--selected {
          border-color: var(--color-success);
          background: var(--color-success-light);
        }
        .cpw-contact-card-check {
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
        .cpw-contact-card--selected .cpw-contact-card-check {
          background: var(--color-success);
          border-color: var(--color-success);
          color: #fff;
        }
        .cpw-contact-card-info { flex: 1; min-width: 0; }
        .cpw-contact-name {
          display: block;
          font-size: var(--text-sm);
          font-weight: 600;
          color: var(--text-primary);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .cpw-contact-meta {
          display: block;
          font-size: var(--text-xs);
          color: var(--text-muted);
          margin-top: 2px;
        }

        /* External contact form */
        .cpw-external-form {
          margin-bottom: var(--space-4);
        }
        .cpw-external-fields {
          display: grid;
          grid-template-columns: 1fr 1fr auto;
          gap: var(--space-3);
          align-items: flex-end;
          padding: var(--space-4);
          background: var(--bg-surface-2);
          border-radius: var(--radius-lg);
          border: 1px solid var(--border-primary);
        }

        .cpw-selected-summary {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          margin-top: var(--space-3);
          padding: var(--space-3) var(--space-4);
          background: var(--color-success-light);
          border-radius: var(--radius-md);
          font-size: var(--text-sm);
          font-weight: 600;
          color: var(--color-success);
        }
        .cpw-ext-badge {
          margin-inline-start: var(--space-2);
          padding: 2px 8px;
          background: var(--color-warning-light);
          color: var(--color-warning);
          border-radius: var(--radius-full);
          font-size: var(--text-xs);
          font-weight: 700;
        }

        /* Mini list */
        .cpw-selected-mini-list {
          margin-top: var(--space-3);
          display: flex;
          flex-direction: column;
          gap: var(--space-2);
          max-height: 180px;
          overflow-y: auto;
        }
        .cpw-selected-mini-item {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          padding: var(--space-2) var(--space-3);
          background: var(--bg-surface-2);
          border-radius: var(--radius-md);
          font-size: var(--text-xs);
          color: var(--text-secondary);
        }
        .cpw-selected-mini-name { flex: 1; font-weight: 600; color: var(--text-primary); }
        .cpw-selected-mini-phone { color: var(--text-muted); font-size: 11px; }
        .cpw-selected-mini-remove {
          border: none;
          background: none;
          cursor: pointer;
          color: var(--text-muted);
          font-size: var(--text-sm);
          line-height: 1;
          padding: 0 var(--space-1);
          border-radius: var(--radius-sm);
          transition: color var(--transition-fast);
          font-weight: 700;
        }
        .cpw-selected-mini-remove:hover { color: var(--color-danger); }

        .cpw-skeleton-list { display: flex; flex-direction: column; gap: var(--space-2); }
        .cpw-skeleton-item { height: 48px; border-radius: var(--radius-md); }
        .cpw-empty {
          text-align: center;
          padding: var(--space-8);
          color: var(--text-muted);
          font-size: var(--text-sm);
        }

        /* ── Step 2: Items ── */
        .cpw-items-list {
          display: flex;
          flex-direction: column;
          gap: var(--space-3);
        }
        .cpw-item-card {
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-lg);
          overflow: hidden;
          background: var(--bg-surface);
          transition: box-shadow var(--transition-fast);
        }
        .cpw-item-card:hover { box-shadow: var(--shadow-sm); }
        .cpw-item-header {
          display: flex;
          align-items: center;
          gap: var(--space-3);
          padding: var(--space-3) var(--space-4);
          background: var(--bg-surface-2);
          border-bottom: 1px solid var(--border-primary);
        }
        .cpw-item-order {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 2px;
        }
        .cpw-order-btn {
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
        .cpw-order-btn:hover:not(:disabled) {
          color: var(--color-success);
          background: var(--color-success-light);
        }
        .cpw-order-btn:disabled { opacity: 0.3; cursor: default; }
        .cpw-item-seq {
          font-size: var(--text-xs);
          font-weight: 700;
          color: var(--color-success);
          min-width: 18px;
          text-align: center;
        }
        .cpw-item-name { flex: 1; min-width: 0; }
        .cpw-item-name strong {
          font-size: var(--text-sm);
          color: var(--text-primary);
        }
        .cpw-item-ext-badge {
          margin-inline-start: var(--space-2);
          padding: 1px 6px;
          background: var(--color-warning-light);
          color: var(--color-warning);
          border-radius: var(--radius-full);
          font-size: 10px;
          font-weight: 700;
        }
        .cpw-item-phone {
          display: block;
          font-size: var(--text-xs);
          color: var(--text-muted);
          margin-top: 2px;
        }
        .cpw-item-remove {
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
        .cpw-item-remove:hover {
          color: var(--color-danger);
          background: var(--color-danger-light);
        }
        .cpw-item-fields {
          display: grid;
          grid-template-columns: repeat(4, 1fr);
          gap: var(--space-3);
          padding: var(--space-3) var(--space-4);
        }
        .cpw-field-sm .form-label {
          font-size: 0.7rem;
          margin-bottom: var(--space-1);
          display: flex;
          align-items: center;
        }
        .cpw-field-sm .form-select,
        .cpw-field-sm .form-input {
          font-size: var(--text-xs);
          padding: var(--space-2);
        }

        /* ── Step 3: Review ── */
        .cpw-review-card {
          background: var(--bg-surface-2);
          border-radius: var(--radius-lg);
          padding: var(--space-4);
          display: flex;
          flex-direction: column;
          gap: var(--space-2);
          margin-bottom: var(--space-5);
        }
        .cpw-review-row {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: var(--space-2) 0;
        }
        .cpw-review-row:not(:last-child) {
          border-bottom: 1px solid var(--border-primary);
        }
        .cpw-review-label {
          font-size: var(--text-sm);
          color: var(--text-muted);
          font-weight: 500;
        }
        .cpw-review-value {
          font-size: var(--text-sm);
          color: var(--text-primary);
          font-weight: 600;
        }
        .cpw-review-value--highlight {
          background: var(--color-success);
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
        .cpw-review-items-title {
          font-size: var(--text-sm);
          font-weight: 700;
          color: var(--text-primary);
          margin-bottom: var(--space-3);
        }
        .cpw-review-items {
          display: flex;
          flex-direction: column;
          gap: var(--space-2);
        }
        .cpw-review-item {
          display: flex;
          align-items: center;
          gap: var(--space-3);
          padding: var(--space-3);
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-md);
          background: var(--bg-surface);
        }
        .cpw-review-item-seq {
          width: 24px;
          height: 24px;
          border-radius: var(--radius-full);
          background: var(--color-success-light);
          color: var(--color-success);
          font-size: var(--text-xs);
          font-weight: 700;
          display: flex;
          align-items: center;
          justify-content: center;
          flex-shrink: 0;
        }
        .cpw-review-item-info { flex: 1; min-width: 0; }
        .cpw-review-item-name {
          display: block;
          font-size: var(--text-sm);
          font-weight: 600;
          color: var(--text-primary);
        }
        .cpw-review-item-meta {
          display: block;
          font-size: var(--text-xs);
          color: var(--text-muted);
          margin-top: 2px;
        }
        .cpw-review-item-duration {
          font-size: var(--text-xs);
          font-weight: 600;
          color: var(--text-muted);
          white-space: nowrap;
        }
        .cpw-review-total {
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
        .cpw-review-total svg { flex-shrink: 0; }

        /* ── Navigation ── */
        .cpw-nav {
          display: flex;
          align-items: center;
          gap: var(--space-3);
          padding-top: var(--space-3);
          border-top: 1px solid var(--border-primary);
        }

        /* ── Responsive ── */
        @media (max-width: 640px) {
          .cpw-body { padding: var(--space-4); }
          .cpw-settings-grid { grid-template-columns: 1fr; }
          .cpw-type-chips { grid-template-columns: 1fr; }
          .cpw-item-fields { grid-template-columns: 1fr 1fr; }
          .cpw-external-fields { grid-template-columns: 1fr; }
          .cpw-search-input { padding-inline-start: calc(var(--space-3) + 26px); }
        }
        @media (max-width: 480px) {
          .cpw-item-fields { grid-template-columns: 1fr; }
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
