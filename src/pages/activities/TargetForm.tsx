/**
 * TargetForm — Wizard من 7 خطوات لإنشاء الهدف
 * المسار الوحيد: createTargetWithRewards()
 * الحقول المؤجلة (مُقصودًا): parent_target_id, auto_split, split_basis
 */
import { useState, useMemo, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import {
  useCreateTargetWithRewards,
  useTargetTypes,
  useBranches,
  useHRDepartments,
  useHREmployees,
  useProducts,
  useCategories,
  useGovernorates,
  useCustomers,
} from '@/hooks/useQueryHooks'
import { supabase } from '@/lib/supabase/client'
import type { TargetScope, TargetPeriod, TargetType } from '@/lib/types/activities'
import type { TierInput, TargetCustomerInput } from '@/lib/types/activities'
import PageHeader from '@/components/shared/PageHeader'
import Button from '@/components/ui/Button'
import TierLadderDisplay from '@/components/targets/TierLadderDisplay'
import { ChevronRight, ChevronLeft, Check, Gift, Plus, Trash2, Info, Users, AlertCircle } from 'lucide-react'
import { allowsPercentageReward } from '@/lib/utils/rewardRules'

// ── Constants ──────────────────────────────────────────────────

const SCOPE_OPTIONS: { value: TargetScope; label: string; icon: string; needsId: boolean }[] = [
  { value: 'company',    label: 'الشركة كلها',  icon: '🏢', needsId: false },
  { value: 'branch',     label: 'فرع',           icon: '🏬', needsId: true  },
  { value: 'department', label: 'قسم',           icon: '🏛️', needsId: true  },
  { value: 'individual', label: 'موظف بعينه',    icon: '👤', needsId: true  },
]

const PERIOD_OPTIONS: { value: TargetPeriod; label: string }[] = [
  { value: 'monthly',   label: 'شهري' },
  { value: 'quarterly', label: 'ربع سنوي' },
  { value: 'yearly',    label: 'سنوي' },
  { value: 'custom',    label: 'مخصص' },
]

const UNIT_AR: Record<string, string> = { currency: 'ج.م', count: 'عدد', percent: '%', quantity: 'كمية' }

// أنواع تستوجب عملاء مستهدفين
const TYPES_NEED_CUSTOMERS = ['upgrade_value', 'category_spread']

// فلاتر ديناميكية حسب code النوع
const TYPE_EXTRA: Record<string, string[]> = {
  sales_value:     ['product_id', 'category_id', 'governorate_id'],
  collection:      ['governorate_id'],
  product_qty:     ['product_id', 'category_id'],
  new_customers:   ['governorate_id'],
  reactivation:    ['dormancy_days'],
  category_spread: ['category_id'],
}

const STEP_LABELS = ['النوع', 'النطاق', 'القيم', 'المكافأة', 'الشرائح', 'العملاء', 'مراجعة']

function toDateStr(y: number, m: number, d: number) {
  // بناء yyyy-mm-dd مباشرة بدون تحويل UTC لتجنب مشكلة timezone offset
  return `${y}-${String(m + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`
}

function defaultDates(period: TargetPeriod) {
  const now = new Date()
  const y = now.getFullYear()
  const m = now.getMonth() // 0-indexed

  if (period === 'monthly') {
    // آخر يوم في الشهر: اليوم 0 من الشهر التالي
    const lastDay = new Date(y, m + 1, 0).getDate()
    return { start: toDateStr(y, m, 1), end: toDateStr(y, m, lastDay) }
  }
  if (period === 'quarterly') {
    const q = Math.floor(m / 3)
    const qStartMonth = q * 3           // 0-indexed
    const qEndMonth   = q * 3 + 2       // 0-indexed
    const lastDay = new Date(y, qEndMonth + 1, 0).getDate()
    return { start: toDateStr(y, qStartMonth, 1), end: toDateStr(y, qEndMonth, lastDay) }
  }
  if (period === 'yearly') return { start: `${y}-01-01`, end: `${y}-12-31` }
  // custom: اليوم الحالي
  const today = toDateStr(y, m, now.getDate())
  return { start: today, end: today }
}


function fmtN(n: number) { return n.toLocaleString('ar-EG', { maximumFractionDigits: 2 }) }

// ── Component ─────────────────────────────────────────────────

export default function TargetForm() {
  const navigate = useNavigate()
  const createTarget = useCreateTargetWithRewards()

  // ── Reference data
  const { data: targetTypes = [] }  = useTargetTypes()
  const { data: branches = [] }     = useBranches()
  const { data: departments = [] }  = useHRDepartments()
  const { data: empRes }            = useHREmployees({ pageSize: 200 })
  const employees = useMemo(() => empRes?.data ?? [], [empRes])
  const { data: productsRes }       = useProducts()
  const products = useMemo(() => (productsRes as any)?.data ?? productsRes ?? [], [productsRes])
  const { data: categories = [] }   = useCategories()
  const { data: governorates = [] } = useGovernorates()

  // ── Step
  const [step, setStep] = useState(1)

  // ── Step 1: نوع + اسم + فلاتر
  const [typeId,        setTypeId]        = useState('')
  const [name,          setName]          = useState('')
  const [description,   setDescription]   = useState('')
  const [productId,     setProductId]     = useState('')
  const [categoryId,    setCategoryId]    = useState('')
  const [governorateId, setGovernorateId] = useState('')
  const [dormancyDays,  setDormancyDays]  = useState('')
  const [growthPct,     setGrowthPct]     = useState('')   // upgrade_value فقط

  // ── Step 2: نطاق
  const [scope,   setScope]   = useState<TargetScope>('company')
  const [scopeId, setScopeId] = useState('')

  // ── Step 3: فترة + قيم + ملاحظات
  const [period,       setPeriod]       = useState<TargetPeriod>('monthly')
  const [periodStart,  setPeriodStart]  = useState(() => defaultDates('monthly').start)
  const [periodEnd,    setPeriodEnd]    = useState(() => defaultDates('monthly').end)
  const [targetValue,  setTargetValue]  = useState('')
  const [minValue,     setMinValue]     = useState('')
  const [stretchValue, setStretchValue] = useState('')
  const [notes,        setNotes]        = useState('')

  // ── Step 4: مكافأة
  const [rewardType,       setRewardType]       = useState<'fixed' | 'percentage' | ''>('')
  const [rewardBaseValue,  setRewardBaseValue]  = useState('')
  const [rewardPoolBasis,  setRewardPoolBasis]  = useState<'sales_value' | 'collection_value' | ''>('')
  const [autoPayout,       setAutoPayout]       = useState(false)
  const [payoutMonthOffset, setPayoutMonthOffset] = useState('0')

  // ── Step 5: شرائح
  const [tiers, setTiers] = useState<TierInput[]>([
    { sequence: 1, threshold_pct: 80, reward_pct: 80, label: 'جيد' },
    { sequence: 2, threshold_pct: 100, reward_pct: 100, label: 'ممتاز' },
  ])

  // ── Step 6: عملاء (للـ upgrade_value & category_spread)
  const [customers, setCustomers] = useState<(TargetCustomerInput & { _key: number; _name?: string })[]>([])
  const [customerSearch, setCustomerSearch]       = useState('')
  const [customerBaseline, setCustomerBaseline]   = useState('')
  const [customerCatCount, setCustomerCatCount]   = useState('')
  const [customerPickId,   setCustomerPickId]     = useState('')  // selected customer id from search
  const [customerActiveIdx, setCustomerActiveIdx] = useState(-1)  // keyboard navigation index

  // ── S6: Customer search query (lazy — يبدأ عند كتابة 2 أحرف+)
  const { data: customersRes } = useCustomers(
    customerSearch.trim().length >= 2 ? { search: customerSearch.trim(), pageSize: 20, isActive: true } : undefined
  )
  const customerResults = useMemo(() => customersRes?.data ?? [], [customersRes])
  const showDropdown = customerSearch.trim().length >= 2 && customerResults.length > 0 && !customerPickId

  // ── Loading
  const [saving, setSaving] = useState(false)

  // ── Derived
  const selectedType: TargetType | undefined = useMemo(() => targetTypes.find(t => t.id === typeId), [targetTypes, typeId])
  const unit          = selectedType?.unit ?? 'currency'
  const unitLabel     = UNIT_AR[unit] ?? ''
  const typeCode      = selectedType?.code ?? ''
  const typeCategory  = selectedType?.category ?? ''
  const extraFields   = TYPE_EXTRA[typeCode] ?? []
  const needsCustomers = TYPES_NEED_CUSTOMERS.includes(typeCode)
  const hasReward      = !!rewardType
  const scopeOption    = SCOPE_OPTIONS.find(o => o.value === scope)!
  const needsScopeId   = scopeOption.needsId

  const suggestedMin     = targetValue ? Math.round(Number(targetValue) * 0.8) : 0
  const suggestedStretch = targetValue ? Math.round(Number(targetValue) * 1.2) : 0

  // ── Effective steps (skip step 5 if no reward; skip step 6 if not needed)
  const activeSteps = useMemo(() => {
    const s = [1, 2, 3, 4]
    if (hasReward) s.push(5)
    if (needsCustomers) s.push(6)
    s.push(7)
    return s
  }, [hasReward, needsCustomers])

  const totalSteps   = activeSteps.length
  const currentIndex = activeSteps.indexOf(step)
  const logicalStep  = currentIndex + 1 // 1-based display

  const goPrev = () => {
    const idx = activeSteps.indexOf(step)
    if (idx > 0) setStep(activeSteps[idx - 1])
  }
  const goNext = () => {
    const idx = activeSteps.indexOf(step)
    if (idx < activeSteps.length - 1) setStep(activeSteps[idx + 1])
  }

  // ── Per-step validation (determines if Next is enabled)
  const stepValid = useCallback((s: number): boolean => {
    switch (s) {
      case 1: {
        if (!typeId || !name.trim()) return false
        if (typeCode === 'upgrade_value' && !growthPct) return false
        if (typeCode === 'reactivation' && !dormancyDays) return false
        return true
      }
      case 2: return !needsScopeId || !!scopeId
      case 3: return !!targetValue && Number(targetValue) > 0 && !!periodStart && !!periodEnd
      case 4: {
        if (!rewardType) return true // مكافأة اختيارية
        if (!rewardBaseValue || Number(rewardBaseValue) <= 0) return false
        if (rewardType === 'percentage' && !rewardPoolBasis) return false
        return true
      }
      case 5: {
        if (!hasReward) return true
        if (tiers.length === 0) return false
        return tiers.every(t => t.threshold_pct > 0 && t.reward_pct > 0)
      }
      case 6: {
        // إلزامي: يجب وجود عميل واحد على الأقل لـ upgrade_value و category_spread
        if (!needsCustomers) return true
        if (customers.length === 0) return false
        // upgrade_value: كل عميل يجب أن يمتلك baseline_value صالح
        if (typeCode === 'upgrade_value') {
          return customers.every(c => c.baseline_value != null && c.baseline_value > 0)
        }
        return true
      }
      default: return true
    }
  }, [typeId, name, typeCode, growthPct, dormancyDays, needsScopeId, scopeId, targetValue, periodStart, periodEnd, rewardType, rewardBaseValue, rewardPoolBasis, hasReward, tiers, needsCustomers, customers])

  // ── Tier helpers
  const addTier = () => setTiers(prev => [...prev, { sequence: prev.length + 1, threshold_pct: 0, reward_pct: 0, label: '' }])
  const removeTier = (i: number) => setTiers(prev => prev.filter((_, idx) => idx !== i).map((t, idx) => ({ ...t, sequence: idx + 1 })))
  const updateTier = (i: number, field: keyof TierInput, val: any) => setTiers(prev => prev.map((t, idx) => idx === i ? { ...t, [field]: val } : t))

  // ── Customer helpers
  const addCustomer = () => {
    if (!customerPickId) return
    // منع التكرار
    if (customers.some(c => c.customer_id === customerPickId)) {
      toast.warning('هذا العميل موجود بالفعل في القائمة')
      return
    }
    const picked = customerResults.find(c => c.id === customerPickId)
    setCustomers(prev => [...prev, {
      _key: Date.now(),
      _name: picked?.name ?? customerPickId,
      customer_id: customerPickId,
      baseline_value: customerBaseline ? Number(customerBaseline) : undefined,
      baseline_category_count: customerCatCount ? Number(customerCatCount) : undefined,
    }])
    setCustomerSearch(''); setCustomerPickId(''); setCustomerBaseline(''); setCustomerCatCount('')
  }
  const removeCustomer = (key: number) => setCustomers(prev => prev.filter(c => c._key !== key))

  // ── Period handler
  const handlePeriodChange = (p: TargetPeriod) => {
    setPeriod(p)
    if (p !== 'custom') { const { start, end } = defaultDates(p); setPeriodStart(start); setPeriodEnd(end) }
  }

  // ── Submit
  const handleSubmit = async () => {
    if (saving) return
    setSaving(true)
    try {
      const { data: u } = await supabase.auth.getUser()
      const userId = u.user?.id ?? ''

      const filterCriteria: Record<string, any> = {}
      if (typeCode === 'upgrade_value' && growthPct) filterCriteria.growth_pct = Number(growthPct)

      await createTarget.mutateAsync({
        type_id:          typeId,
        name:             name.trim(),
        description:      description || null,
        scope,
        scope_id:         needsScopeId ? scopeId : null,
        period,
        period_start:     periodStart,
        period_end:       periodEnd,
        target_value:     Number(targetValue),
        min_value:        minValue ? Number(minValue) : null,
        stretch_value:    stretchValue ? Number(stretchValue) : null,
        product_id:       productId || null,
        category_id:      categoryId || null,
        governorate_id:   governorateId || null,
        dormancy_days:    dormancyDays ? Number(dormancyDays) : null,
        filter_criteria:  Object.keys(filterCriteria).length ? filterCriteria : undefined,
        notes:            notes || null,
        reward_type:      rewardType || null,
        reward_base_value: rewardBaseValue ? Number(rewardBaseValue) : null,
        reward_pool_basis: (rewardType === 'percentage' && rewardPoolBasis) ? rewardPoolBasis : null,
        auto_payout:      autoPayout,
        payout_month_offset: Number(payoutMonthOffset),
        tiers:            hasReward && tiers.length > 0 ? tiers : undefined,
        customers:        customers.length > 0 ? customers.map(({ _key, _name, ...c }) => c) : undefined,
        p_user_id:        userId,
      }, {
        onSuccess: (newId: string) => {
          toast.success('تم إنشاء الهدف بنجاح 🎯')
          navigate(`/activities/targets/${newId}`)
        },
        onError: (e: any) => toast.error(e?.message || 'فشل في الإنشاء'),
      })
    } catch (e: any) {
      toast.error(e?.message || 'حدث خطأ')
    } finally {
      setSaving(false)
    }
  }

  // ── Render helpers ─────────────────────────────────────────────

  const renderScopeIdSelector = () => {
    if (!needsScopeId) return null
    const opts = scope === 'branch'     ? (branches as any[]).map(b => ({ id: b.id, label: b.name }))
               : scope === 'department' ? (departments as any[]).map(d => ({ id: d.id, label: d.name }))
               : employees.map(e => ({ id: e.id, label: `${e.full_name}${e.employee_number ? ` (${e.employee_number})` : ''}` }))
    const lbl = scope === 'branch' ? 'الفرع' : scope === 'department' ? 'القسم' : 'الموظف'
    return (
      <div className="form-group">
        <label className="form-label">{lbl} <span className="form-required">*</span></label>
        <select className="form-select" value={scopeId} onChange={e => setScopeId(e.target.value)}>
          <option value="">-- اختر {lbl} --</option>
          {opts.map(o => <option key={o.id} value={o.id}>{o.label}</option>)}
        </select>
      </div>
    )
  }

  // ── STEP RENDERERS ───────────────────────────────────────────
  // تنبيه: هذه دوال عادية لا مكونات React
  // يجب استدعاؤها كـ {renderStep1()} وليس <S1 />
  // استخدام <S1 /> داخل الـ component body يُنشئ نوع مكوّن جديد في كل render
  // مما يُسبب remount وفقدان التركيز عند كل ضغطة مفتاح

  function renderStep1() { return (
    <>
      <div className="tf-section">
        <div className="tf-section-title">🎯 نوع الهدف <span className="form-required">*</span></div>
        <div className="tf-type-grid">
          {targetTypes.map(t => (
            <button key={t.id} type="button"
              className={`tf-type-card${typeId === t.id ? ' tf-type-card--active' : ''}`}
              onClick={() => setTypeId(t.id)}>
              <div className="tf-type-name">{t.name}</div>
              <div className="tf-type-meta">
                <span className="tf-unit-badge">{UNIT_AR[t.unit] ?? t.unit}</span>
                <span className="tf-type-cat">{t.category}</span>
              </div>
              {t.description && <div className="tf-type-desc">{t.description}</div>}
            </button>
          ))}
        </div>
      </div>

      <div className="tf-section">
        <div className="tf-section-title">اسم الهدف</div>
        <div className="form-group">
          <label className="form-label">عنوان واضح يصف الهدف <span className="form-required">*</span></label>
          <input className="form-input" value={name} onChange={e => setName(e.target.value)}
            placeholder={`مثال: هدف ${selectedType?.name ?? 'مبيعات'} - ${PERIOD_OPTIONS.find(p => p.value === period)?.label ?? 'شهري'} 2026`} />
        </div>
        <div className="form-group">
          <label className="form-label">وصف <span style={{ color: 'var(--text-muted)', fontWeight: 400 }}>(اختياري)</span></label>
          <textarea className="form-textarea" rows={2} value={description} onChange={e => setDescription(e.target.value)} placeholder="وصف مختصر..." />
        </div>
      </div>

      {/* growth_pct — إلزامي لـ upgrade_value */}
      {typeCode === 'upgrade_value' && (
        <div className="tf-section">
          <div className="tf-section-title">📈 نسبة النمو المستهدفة</div>
          <div className="form-group">
            <label className="form-label">growth_pct — نسبة زيادة قيمة العميل <span className="form-required">*</span></label>
            <input type="number" className="form-input" value={growthPct} onChange={e => setGrowthPct(e.target.value)}
              placeholder="مثال: 20 (يعني 20%)" min="1" step="0.1" />
          </div>
        </div>
      )}

      {extraFields.length > 0 && (
        <div className="tf-section">
          <div className="tf-section-title"><Info size={14} className="inline align-middle ml-1" /> فلاتر تخصصية — {selectedType?.name}</div>
          {extraFields.includes('product_id') && (
            <div className="form-group">
              <label className="form-label">منتج <span style={{ color: 'var(--text-muted)', fontWeight: 400 }}>(اختياري)</span></label>
              <select className="form-select" value={productId} onChange={e => setProductId(e.target.value)}>
                <option value="">كل المنتجات</option>
                {(products as any[]).map((p: any) => <option key={p.id} value={p.id}>{p.name}</option>)}
              </select>
            </div>
          )}
          {extraFields.includes('category_id') && (
            <div className="form-group">
              <label className="form-label">تصنيف <span style={{ color: 'var(--text-muted)', fontWeight: 400 }}>(اختياري)</span></label>
              <select className="form-select" value={categoryId} onChange={e => setCategoryId(e.target.value)}>
                <option value="">كل التصنيفات</option>
                {(categories as any[]).map((c: any) => <option key={c.id} value={c.id}>{c.name}</option>)}
              </select>
            </div>
          )}
          {extraFields.includes('governorate_id') && (
            <div className="form-group">
              <label className="form-label">محافظة <span style={{ color: 'var(--text-muted)', fontWeight: 400 }}>(اختياري)</span></label>
              <select className="form-select" value={governorateId} onChange={e => setGovernorateId(e.target.value)}>
                <option value="">كل المحافظات</option>
                {(governorates as any[]).map((g: any) => <option key={g.id} value={g.id}>{g.name}</option>)}
              </select>
            </div>
          )}
          {extraFields.includes('dormancy_days') && (
            <div className="form-group">
              <label className="form-label">أيام الخمول <span className="form-required">*</span></label>
              <input type="number" className="form-input" value={dormancyDays}
                onChange={e => setDormancyDays(e.target.value)} placeholder="مثال: 90" min="1" step="1" />
              <small style={{ color: 'var(--text-muted)', fontSize: 11 }}>عدد الأيام التي بدونها يُعتبر العميل خاملاً</small>
            </div>
          )}
        </div>
      )}
    </>
  ) } // end renderStep1

  function renderStep2() { return (
    <div className="tf-section">
      <div className="tf-section-title">📌 نطاق الهدف</div>
      <div className="tf-scope-grid">
        {SCOPE_OPTIONS.map(o => (
          <button key={o.value} type="button"
            className={`tf-scope-btn${scope === o.value ? ' tf-scope-btn--active' : ''}`}
            onClick={() => { setScope(o.value); setScopeId('') }}>
            <span style={{ fontSize: 24 }}>{o.icon}</span>
            <span>{o.label}</span>
          </button>
        ))}
      </div>
      {renderScopeIdSelector()}
    </div>
  ) } // end renderStep2

  function renderStep3() { return (
    <>
      <div className="tf-section">
        <div className="tf-section-title">📅 الفترة الزمنية</div>
        <div className="form-group">
          <label className="form-label">نوع الفترة</label>
          <select className="form-select" value={period} onChange={e => handlePeriodChange(e.target.value as TargetPeriod)}>
            {PERIOD_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
          </select>
        </div>
        <div className="tf-dates">
          <div className="form-group">
            <label className="form-label">من <span className="form-required">*</span></label>
            <input type="date" className="form-input" value={periodStart} onChange={e => setPeriodStart(e.target.value)} />
          </div>
          <div className="form-group">
            <label className="form-label">إلى <span className="form-required">*</span></label>
            <input type="date" className="form-input" value={periodEnd} onChange={e => setPeriodEnd(e.target.value)} />
          </div>
        </div>
      </div>

      <div className="tf-section">
        <div className="tf-section-title">💰 القيم المستهدفة</div>
        {targetValue && Number(targetValue) > 0 && (
          <div className="tf-value-visual">
            <div className="tf-zone tf-zone--danger" style={{ width: `${minValue ? Math.min(Number(minValue) / Number(targetValue) * 100, 80) : 75}%` }}>أحمر</div>
            <div className="tf-zone tf-zone--success" style={{ flex: 1 }}>🎯 الهدف</div>
            <div className="tf-zone tf-zone--stretch" style={{ width: '20%' }}>تمدد</div>
          </div>
        )}
        <div className="tf-values-grid">
          <div className="form-group">
            <label className="form-label">القيمة المستهدفة {unitLabel && <span className="tf-unit-badge">{unitLabel}</span>} <span className="form-required">*</span></label>
            <input type="number" className="form-input" style={{ borderColor: 'var(--color-primary)', fontWeight: 700, fontSize: 'var(--text-base)' }}
              value={targetValue} onChange={e => setTargetValue(e.target.value)} placeholder="0" min="0" step="any" />
          </div>
          <div className="form-group">
            <label className="form-label">الحد الأدنى {unitLabel && <span className="tf-unit-badge">{unitLabel}</span>}<span style={{ color: 'var(--text-muted)', fontWeight: 400 }}> (اختياري)</span></label>
            <input type="number" className="form-input" value={minValue}
              onChange={e => setMinValue(e.target.value)}
              placeholder={suggestedMin ? `اقتراح: ${suggestedMin.toLocaleString('ar-EG')}` : '—'} min="0" step="any" />
            {suggestedMin > 0 && !minValue && (
              <button type="button" className="tf-suggest-btn" onClick={() => setMinValue(String(suggestedMin))}>
                استخدام 80% ← {suggestedMin.toLocaleString('ar-EG')}
              </button>
            )}
          </div>
          <div className="form-group">
            <label className="form-label">هدف التمدد {unitLabel && <span className="tf-unit-badge">{unitLabel}</span>}<span style={{ color: 'var(--text-muted)', fontWeight: 400 }}> (اختياري)</span></label>
            <input type="number" className="form-input" value={stretchValue}
              onChange={e => setStretchValue(e.target.value)}
              placeholder={suggestedStretch ? `اقتراح: ${suggestedStretch.toLocaleString('ar-EG')}` : '—'} min="0" step="any" />
            {suggestedStretch > 0 && !stretchValue && (
              <button type="button" className="tf-suggest-btn" onClick={() => setStretchValue(String(suggestedStretch))}>
                استخدام 120% ← {suggestedStretch.toLocaleString('ar-EG')}
              </button>
            )}
          </div>
        </div>
        <div className="form-group">
          <label className="form-label">ملاحظات <span style={{ color: 'var(--text-muted)', fontWeight: 400 }}>(اختيارية)</span></label>
          <textarea className="form-textarea" rows={2} value={notes} onChange={e => setNotes(e.target.value)} placeholder="ملاحظات إضافية..." />
        </div>
      </div>
    </>
  ) } // end renderStep3

  function renderStep4() {
    const isPercentage  = rewardType === 'percentage'
    const canPercentage = allowsPercentageReward(typeCategory, typeCode)

    // وعاء الحساب المُثبَّت تلقائياً للنوع (null = مقيَّد بـ sales_value دائماً بحكم DB)
    // كل الأنواع المالية غير collection تقبل sales_value فقط
    const lockedBasis = isPercentage
      ? (typeCode === 'collection' ? 'collection_value' : 'sales_value')
      : null

    return (
      <div className="tf-section">
        <div className="tf-section-title"><Gift size={16} className="inline align-middle ml-1" /> إعداد المكافأة <span style={{ color: 'var(--text-muted)', fontWeight: 400 }}>(اختياري)</span></div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '8px', marginBottom: '16px' }}>
          {[{ v: '' as const, label: 'بدون مكافأة', desc: 'لا يوجد حافز مادي' },
            { v: 'fixed' as const, label: 'مقطوعة', desc: 'مبلغ ثابت عند التحقيق' },
            { v: 'percentage' as const, label: 'نسبة', desc: 'نسبة من وعاء الحساب' }]
            .filter(o => o.v !== 'percentage' || canPercentage)
            .map(o => (
            <button key={o.v} type="button"
              className={`tf-type-card${rewardType === o.v ? ' tf-type-card--active' : ''}`}
              style={{ padding: '12px 8px' }}
              onClick={() => {
                setRewardType(o.v)
                // تنظيف pool_basis تلقائياً عند تغيير نوع المكافأة
                if (!o.v || o.v === 'fixed') {
                  setRewardPoolBasis('')
                } else if (o.v === 'percentage') {
                  // تعيين pool_basis تلقائياً حسب النوع
                  const auto = typeCode === 'collection' ? 'collection_value' : 'sales_value'
                  setRewardPoolBasis(auto)
                }
              }}>
              <div className="tf-type-name" style={{ fontSize: '13px' }}>{o.label}</div>
              <div className="tf-type-desc">{o.desc}</div>
            </button>
          ))}
        </div>

        {!canPercentage && (
          <div style={{ display: 'flex', alignItems: 'center', gap: '6px', padding: '8px 12px',
            background: 'var(--bg-surface-2)', borderRadius: '6px', fontSize: '12px', color: 'var(--text-muted)',
            marginBottom: '12px' }}>
            <Info size={13} /> هذا النوع من الأهداف يدعم المكافأة المقطوعة فقط
          </div>
        )}

        {rewardType && (
          <>
            <div className="tf-dates">
              <div className="form-group">
                <label className="form-label">
                  {rewardType === 'fixed' ? 'المبلغ الثابت (ج.م)' : 'النسبة المئوية (%)'}
                  <span className="form-required"> *</span>
                </label>
                <input type="number" className="form-input" value={rewardBaseValue}
                  onChange={e => setRewardBaseValue(e.target.value)}
                  placeholder={rewardType === 'fixed' ? 'مثال: 5000' : 'مثال: 2.5'} min="0.01" step="any" />
              </div>

              {/* وعاء الحساب — يظهر فقط مع percentage */}
              {isPercentage && (
                <div className="form-group">
                  <label className="form-label">وعاء الحساب</label>
                  {/* مُثبَّت دائماً — لا خيار للمستخدم لأن DB تفرض قيماً محددة */}
                  <div style={{
                    padding: '8px 12px', background: 'var(--bg-surface-2)',
                    border: '1px solid var(--border-primary)', borderRadius: '6px',
                    fontSize: '13px', display: 'flex', alignItems: 'center', gap: '6px'
                  }}>
                    <span style={{ fontSize: 16 }}>🔒</span>
                    <span style={{ fontWeight: 600, color: 'var(--text-primary)' }}>
                      {lockedBasis === 'collection_value' ? 'إجمالي التحصيلات' : 'إجمالي المبيعات'}
                    </span>
                    <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>محدد تلقائياً حسب نوع الهدف</span>
                  </div>
                </div>
              )}
            </div>

            <div style={{ borderTop: '1px solid var(--border-primary)', marginTop: '8px', paddingTop: '16px' }}>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                <div className="form-group">
                  <label className="form-label" style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer' }}>
                    <input type="checkbox" checked={autoPayout} onChange={e => setAutoPayout(e.target.checked)}
                      style={{ width: 16, height: 16 }} />
                    تفعيل الصرف التلقائي بالرواتب
                  </label>
                  <small style={{ color: 'var(--text-muted)', fontSize: 11 }}>يتطلب شريحة مكافأة واحدة على الأقل</small>
                </div>
                <div className="form-group">
                  <label className="form-label">تأخير الصرف</label>
                  <select className="form-select" value={payoutMonthOffset} onChange={e => setPayoutMonthOffset(e.target.value)}>
                    <option value="0">نفس الشهر</option>
                    <option value="1">الشهر التالي</option>
                    <option value="2">بعد شهرين</option>
                  </select>
                </div>
              </div>
            </div>
          </>
        )}

        {!rewardType && (
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', color: 'var(--text-muted)', fontSize: '13px', padding: '8px 0' }}>
            <Info size={14} /> يمكن إضافة مكافأة لاحقاً عبر صفحة تفاصيل الهدف.
          </div>
        )}
      </div>
    )
  } // end renderStep4

  function renderStep5() { return (
    <div className="tf-section">
      <div className="tf-section-title" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', border: 'none', paddingBottom: 0, marginBottom: '12px' }}>
        <span>🏆 شرائح المكافأة</span>
        <Button type="button" variant="secondary" icon={<Plus size={14} />} onClick={addTier} size="sm">إضافة شريحة</Button>
      </div>

      {tiers.length === 0 ? (
        <div className="empty-state" style={{ padding: '24px 0' }}>
          <p className="empty-state-title">لا توجد شرائح بعد</p>
          <p className="empty-state-text">أضف شريحة واحدة على الأقل لتحديد متى وكم تُصرف المكافأة</p>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
          {tiers.map((tier, i) => (
            <div key={i} style={{
              display: 'grid', gridTemplateColumns: '36px 1fr 1fr 1fr auto',
              gap: '8px', alignItems: 'center',
              padding: '12px', background: 'var(--bg-surface-2)',
              border: '1px solid var(--border-primary)', borderRadius: '8px'
            }}>
              <div style={{ textAlign: 'center', fontWeight: 800, color: 'var(--color-primary)', fontSize: '18px' }}>{i + 1}</div>
              <div className="form-group" style={{ margin: 0 }}>
                <label className="form-label">نسبة الإنجاز %</label>
                <input type="number" className="form-input" value={tier.threshold_pct}
                  onChange={e => updateTier(i, 'threshold_pct', Number(e.target.value))}
                  placeholder="مثال: 80" min="1" max="200" />
              </div>
              <div className="form-group" style={{ margin: 0 }}>
                <label className="form-label">% المكافأة المصروفة</label>
                <input type="number" className="form-input" value={tier.reward_pct}
                  onChange={e => updateTier(i, 'reward_pct', Number(e.target.value))}
                  placeholder="مثال: 80" min="1" max="200" />
              </div>
              <div className="form-group" style={{ margin: 0 }}>
                <label className="form-label">تسمية الشريحة</label>
                <input type="text" className="form-input" value={tier.label ?? ''}
                  onChange={e => updateTier(i, 'label', e.target.value)}
                  placeholder="مثال: ممتاز" />
              </div>
              <button type="button" onClick={() => removeTier(i)}
                style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--color-danger)', padding: '8px', marginTop: '20px' }}>
                <Trash2 size={16} />
              </button>
            </div>
          ))}
        </div>
      )}

      <div style={{ marginTop: '12px', padding: '12px', background: 'var(--color-primary-light)', borderRadius: '8px', fontSize: '12px', color: 'var(--text-secondary)' }}>
        <strong>مثال: </strong>شريحة 80% → تصرف 80% من المكافأة | شريحة 100% → تصرف 100% من المكافأة
      </div>
    </div>
  ) } // end renderStep5

  function renderStep6() { return (
    <div className="tf-section">
      <div className="tf-section-title"><Users size={16} className="inline align-middle ml-1" /> العملاء المستهدفون</div>
      <p style={{ fontSize: '13px', color: 'var(--text-secondary)', marginBottom: '12px' }}>
        {typeCode === 'upgrade_value'
          ? 'اختر العملاء الذين تريد قياس نمو مشترياتهم مقارنة بقيمة مرجعية.'
          : 'اختر العملاء الذين تريد قياس انتشار التصنيفات لديهم.'}
      </p>

      {/* ── اختيار بالبحث ── */}
      <div style={{ padding: '14px', background: 'var(--bg-surface-2)', border: '1px solid var(--border-primary)', borderRadius: '10px', marginBottom: '10px' }}>
        <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap', alignItems: 'flex-end' }}>
          {/* searchable input with keyboard navigation */}
          <div className="form-group" style={{ margin: 0, flex: '2 1 220px', position: 'relative' }}>
            <label className="form-label">بحث عن عميل <span className="form-required">*</span></label>
            <input
              className="form-input"
              value={customerSearch}
              autoComplete="off"
              aria-autocomplete="list"
              aria-expanded={showDropdown}
              onChange={e => {
                setCustomerSearch(e.target.value)
                setCustomerPickId('')
                setCustomerActiveIdx(-1)
              }}
              onKeyDown={e => {
                if (!showDropdown) return
                if (e.key === 'ArrowDown') {
                  e.preventDefault()
                  setCustomerActiveIdx(i => Math.min(i + 1, customerResults.length - 1))
                } else if (e.key === 'ArrowUp') {
                  e.preventDefault()
                  setCustomerActiveIdx(i => Math.max(i - 1, 0))
                } else if (e.key === 'Enter') {
                  e.preventDefault()
                  const c = customerActiveIdx >= 0 ? customerResults[customerActiveIdx] : null
                  if (c) { setCustomerPickId((c as any).id); setCustomerSearch((c as any).name); setCustomerActiveIdx(-1) }
                } else if (e.key === 'Escape') {
                  setCustomerActiveIdx(-1)
                  setCustomerPickId('')
                  setCustomerSearch('')
                }
              }}
              onBlur={() =>
                // تأخير بسيط للسماح للنقر على عنصر القائمة قبل الإغلاق
                setTimeout(() => { if (!customerPickId) setCustomerActiveIdx(-1) }, 200)
              }
              placeholder="اكتب اسم العميل أو الكود..."
            />
            {showDropdown && (
              <div role="listbox" style={{
                position: 'absolute', top: '100%', right: 0, left: 0, zIndex: 50,
                background: 'var(--bg-surface)', border: '1px solid var(--border-primary)',
                borderRadius: '8px', boxShadow: 'var(--shadow-lg)', maxHeight: 220, overflowY: 'auto',
                marginTop: '2px',
              }}>
                {(customerResults as any[]).map((c: any, idx: number) => (
                  <button
                    key={c.id} type="button" role="option"
                    aria-selected={customerActiveIdx === idx}
                    style={{
                      display: 'block', width: '100%', textAlign: 'right', padding: '9px 14px',
                      background: customerActiveIdx === idx ? 'var(--color-primary-light)' : 'none',
                      border: 'none', borderBottom: '1px solid var(--border-secondary)',
                      cursor: 'pointer', fontSize: '13px', color: 'var(--text-primary)',
                    }}
                    onMouseEnter={() => setCustomerActiveIdx(idx)}
                    onMouseLeave={() => setCustomerActiveIdx(-1)}
                    onClick={() => { setCustomerPickId(c.id); setCustomerSearch(c.name); setCustomerActiveIdx(-1) }}
                  >
                    <span style={{ fontWeight: 600 }}>{c.name}</span>
                    <span style={{ fontSize: '11px', color: 'var(--text-muted)', marginRight: '6px' }}>{c.code}</span>
                  </button>
                ))}
              </div>
            )}
            {customerSearch.trim().length >= 2 && customerResults.length === 0 && (
              <div style={{ position: 'absolute', top: '100%', right: 0, left: 0, zIndex: 50, background: 'var(--bg-surface)', border: '1px solid var(--border-primary)', borderRadius: '8px', padding: '10px 14px', fontSize: '13px', color: 'var(--text-muted)', marginTop: '2px' }}>
                لا يوجد عميل بهذا الاسم
              </div>
            )}
          </div>

          {typeCode === 'upgrade_value' && (
            <div className="form-group" style={{ margin: 0, flex: '1 1 130px' }}>
              <label className="form-label">القيمة المرجعية (ج.م)</label>
              <input type="number" className="form-input" value={customerBaseline} onChange={e => setCustomerBaseline(e.target.value)} placeholder="0" min="0" />
            </div>
          )}
          {typeCode === 'category_spread' && (
            <div className="form-group" style={{ margin: 0, flex: '1 1 130px' }}>
              <label className="form-label">عدد التصنيفات المرجعي</label>
              <input type="number" className="form-input" value={customerCatCount} onChange={e => setCustomerCatCount(e.target.value)} placeholder="0" min="0" />
            </div>
          )}
          <Button type="button" variant="secondary" icon={<Plus size={14} />}
            onClick={addCustomer} disabled={!customerPickId}
            style={{ alignSelf: 'flex-end' }}
          >
            إضافة
          </Button>
        </div>
      </div>

      {/* ── قائمة المختارين ── */}
      {customers.length === 0 ? (
        <div style={{ textAlign: 'center', padding: '16px', color: 'var(--text-muted)', fontSize: '13px', background: 'var(--bg-surface-2)', borderRadius: '8px' }}>
          ابحث عن عميل وأضفه للقائمة
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
          {customers.map((c, i) => (
            <div key={c._key} style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '10px 14px',
              background: 'var(--bg-surface-2)', border: '1px solid var(--border-primary)', borderRadius: '8px' }}>
              <span style={{ fontWeight: 700, color: 'var(--color-primary)', minWidth: 24, fontSize: '13px' }}>{i + 1}</span>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: '13px', fontWeight: 600, color: 'var(--text-primary)' }}>{c._name ?? c.customer_id}</div>
                {c._name && <div style={{ fontSize: '10px', fontFamily: 'monospace', color: 'var(--text-muted)' }}>{c.customer_id}</div>}
              </div>
              {c.baseline_value != null && <span className="tf-unit-badge">{fmtN(c.baseline_value)} ج.م</span>}
              {c.baseline_category_count != null && <span className="tf-unit-badge">{c.baseline_category_count} تصنيف</span>}
              <button type="button" onClick={() => removeCustomer(c._key)}
                style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--color-danger)', padding: '4px' }}>
                <Trash2 size={14} />
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  ) } // end renderStep6

  function renderStep7() {
    const scopeLabel = SCOPE_OPTIONS.find(o => o.value === scope)?.label
    const periodLabel = PERIOD_OPTIONS.find(o => o.value === period)?.label
    const scopeIdLabel = !needsScopeId ? '' : (
      scope === 'branch'     ? (branches as any[]).find(b => b.id === scopeId)?.name :
      scope === 'department' ? (departments as any[]).find(d => d.id === scopeId)?.name :
      employees.find(e => e.id === scopeId)?.full_name
    ) ?? scopeId

    return (
      <div className="tf-section">
        <div className="tf-section-title">✅ مراجعة شاملة قبل الإنشاء</div>

        <div className="tf-review-card">
          <div style={{ fontSize: 28 }}>🎯</div>
          <div>
            <div style={{ fontSize: 'var(--text-base)', fontWeight: 800, color: 'var(--color-primary)' }}>{name || '—'}</div>
            <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>{selectedType?.name ?? '—'}</div>
          </div>
        </div>

        <div className="tf-review-grid">
          {/* Tiers visual — TierLadderDisplay (عرضبصري في صفحة المراجعة */}
          {hasReward && tiers.length > 0 && (
            <div style={{ marginTop: '12px' }}>
              <TierLadderDisplay
                tiers={tiers.map((t, i) => ({
                  id: `preview-${i}`, sequence: i + 1,
                  target_id: '', threshold_pct: t.threshold_pct,
                  reward_pct: t.reward_pct, label: t.label ?? null,
                  created_at: '',
                }))}
                currentAchievementPct={0}
                rewardType={rewardType as 'fixed' | 'percentage' | null}
                rewardBaseValue={rewardBaseValue ? Number(rewardBaseValue) : null}
              />
            </div>
          )}
          <div className="tf-review-item tf-review-item--highlight">
            <span className="tf-review-label">القيمة المستهدفة</span>
            <span className="tf-review-value">{fmtN(Number(targetValue || 0))} {unitLabel}</span>
          </div>
          {minValue && <div className="tf-review-item"><span className="tf-review-label">الحد الأدنى</span><span className="tf-review-value">{fmtN(Number(minValue))} {unitLabel}</span></div>}
          {stretchValue && <div className="tf-review-item"><span className="tf-review-label">هدف التمدد</span><span className="tf-review-value">{fmtN(Number(stretchValue))} {unitLabel}</span></div>}
          <div className="tf-review-item">
            <span className="tf-review-label">الفترة</span>
            <span className="tf-review-value">{periodLabel}: {periodStart} — {periodEnd}</span>
          </div>

          {/* Reward */}
          {hasReward && (
            <>
              <div className="tf-review-item" style={{ background: 'rgba(139,92,246,0.06)' }}>
                <span className="tf-review-label">نوع المكافأة</span>
                <span className="tf-review-value">{rewardType === 'fixed' ? 'مقطوعة' : 'نسبية'}</span>
              </div>
              <div className="tf-review-item" style={{ background: 'rgba(139,92,246,0.06)' }}>
                <span className="tf-review-label">{rewardType === 'fixed' ? 'المبلغ الثابت' : 'النسبة %'}</span>
                <span className="tf-review-value">{rewardBaseValue} {rewardType === 'fixed' ? 'ج.م' : '%'}</span>
              </div>
              {rewardPoolBasis && (
                <div className="tf-review-item" style={{ background: 'rgba(139,92,246,0.06)' }}>
                  <span className="tf-review-label">وعاء الحساب</span>
                  <span className="tf-review-value">{rewardPoolBasis === 'sales_value' ? 'إجمالي المبيعات' : 'إجمالي التحصيلات'}</span>
                </div>
              )}
              {tiers.length > 0 && (
                <div className="tf-review-item" style={{ background: 'rgba(139,92,246,0.06)' }}>
                  <span className="tf-review-label">الشرائح</span>
                  <span className="tf-review-value" style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
                    {tiers.map((t, i) => (
                      <span key={i} className="tf-tag">عند {t.threshold_pct}% → {t.reward_pct}% {t.label ? `(${t.label})` : ''}</span>
                    ))}
                  </span>
                </div>
              )}
              <div className="tf-review-item" style={{ background: 'rgba(139,92,246,0.06)' }}>
                <span className="tf-review-label">الصرف التلقائي</span>
                <span className="tf-review-value">{autoPayout ? `✓ مفعّل (offset +${payoutMonthOffset} شهر)` : '—'}</span>
              </div>
            </>
          )}

          {/* Customers */}
          {customers.length > 0 && (
            <div className="tf-review-item">
              <span className="tf-review-label">العملاء المستهدفون</span>
              <span className="tf-review-value" style={{ display: 'flex', flexDirection: 'column', gap: '3px' }}>
                {customers.map((c, i) => (
                  <span key={c._key} style={{ fontSize: '12px' }}>
                    <strong style={{ color: 'var(--color-primary)' }}>{i + 1}.</strong>{' '}
                    {c._name || c.customer_id}
                    {c.baseline_value != null && <span className="tf-unit-badge" style={{ marginRight: 6 }}>{fmtN(c.baseline_value)} ج.م</span>}
                    {c.baseline_category_count != null && <span className="tf-unit-badge" style={{ marginRight: 6 }}>{c.baseline_category_count} تصنيف</span>}
                  </span>
                ))}
              </span>
            </div>
          )}

          {/* Filters */}
          {(productId || categoryId || governorateId || dormancyDays) && (
            <div className="tf-review-item">
              <span className="tf-review-label">فلاتر</span>
              <span className="tf-review-value" style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
                {productId && <span className="tf-tag">منتج</span>}
                {categoryId && <span className="tf-tag">تصنيف</span>}
                {governorateId && <span className="tf-tag">محافظة</span>}
                {dormancyDays && <span className="tf-tag">خمول {dormancyDays} يوم</span>}
              </span>
            </div>
          )}
        </div>

        <div style={{ display: 'flex', alignItems: 'flex-start', gap: '8px', padding: '12px 16px',
          background: 'var(--color-warning-light)', border: '1px solid var(--color-warning)',
          borderRadius: '8px', marginTop: '12px', fontSize: '13px' }}>
          <AlertCircle size={16} style={{ color: 'var(--color-warning)', flexShrink: 0, marginTop: 2 }} />
          <span style={{ color: 'var(--text-secondary)' }}>
            بعد الإنشاء، يمكن تعديل القيم والمكافأة عبر صفحة التفاصيل. لا يمكن تغيير النوع أو النطاق.
          </span>
        </div>
      </div>
    )
  } // end renderStep7

  // ── Main Render ─────────────────────────────────────────────

  const isLastStep = activeSteps.indexOf(step) === activeSteps.length - 1
  const isFirstStep = activeSteps.indexOf(step) === 0
  const nextValid = stepValid(step)

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="هدف جديد"
        subtitle={`الخطوة ${logicalStep} من ${totalSteps} — ${STEP_LABELS[step - 1] ?? ''}`}
        breadcrumbs={[
          { label: 'الأهداف', path: '/activities/targets' },
          { label: 'هدف جديد' },
        ]}
      />

      {/* Step Indicator */}
      <div className="tf-steps">
        {activeSteps.map((s, i) => {
          const done = activeSteps.indexOf(step) > i
          const active = s === step
          return (
            <div key={s} className={`tf-step${active ? ' tf-step--active' : done ? ' tf-step--done' : ''}`}>
              <div className="tf-step-circle">{done ? <Check size={11} /> : i + 1}</div>
              <span className="tf-step-label">{STEP_LABELS[s - 1]}</span>
            </div>
          )
        })}
      </div>

      <form className="edara-card tf-form" onSubmit={e => { e.preventDefault(); if (isLastStep) handleSubmit() }}>
        {step === 1 && renderStep1()}
        {step === 2 && renderStep2()}
        {step === 3 && renderStep3()}
        {step === 4 && renderStep4()}
        {step === 5 && renderStep5()}
        {step === 6 && renderStep6()}
        {step === 7 && renderStep7()}

        <div className="tf-actions">
          {!isFirstStep && (
            <Button type="button" variant="secondary" icon={<ChevronRight size={14} />} onClick={goPrev}>
              السابق
            </Button>
          )}
          <div style={{ flex: 1 }} />
          {!isLastStep ? (
            <Button type="button" disabled={!nextValid} onClick={goNext} icon={<ChevronLeft size={14} />}>
              التالي
            </Button>
          ) : (
            <Button type="submit" disabled={saving || !stepValid(3)}>
              {saving ? 'جاري الحفظ...' : 'إنشاء الهدف 🎯'}
            </Button>
          )}
        </div>
      </form>

      <style>{`
        .tf-form { max-width: 720px; margin: 0 auto; padding: var(--space-4); display: flex; flex-direction: column; gap: var(--space-3); }
        .tf-steps { display: flex; justify-content: center; gap: 0; max-width: 720px; margin: 0 auto var(--space-4); padding: 0 var(--space-4); }
        .tf-step { display: flex; align-items: center; gap: var(--space-1); flex: 1; padding: var(--space-2) 0; font-size: var(--text-xs); color: var(--text-muted); position: relative; }
        .tf-step + .tf-step::before { content: ''; position: absolute; right: 100%; top: 12px; width: 8px; height: 2px; background: var(--border-primary); }
        .tf-step--done + .tf-step::before, .tf-step--active + .tf-step::before { background: var(--color-primary); }
        .tf-step-circle { width: 24px; height: 24px; border-radius: 50%; border: 2px solid var(--border-primary); display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: 700; flex-shrink: 0; background: var(--bg-surface); color: var(--text-muted); }
        .tf-step--active .tf-step-circle { border-color: var(--color-primary); background: var(--color-primary); color: #fff; }
        .tf-step--done .tf-step-circle { border-color: var(--color-success); background: var(--color-success); color: #fff; }
        .tf-step--active { color: var(--color-primary); font-weight: 700; }
        .tf-step--done { color: var(--color-success); }
        .tf-step-label { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .tf-section { border: 1px solid var(--border-primary); border-radius: var(--radius-lg); padding: var(--space-4); display: flex; flex-direction: column; gap: var(--space-3); }
        .tf-section-title { font-size: var(--text-sm); font-weight: 700; color: var(--text-secondary); padding-bottom: var(--space-2); border-bottom: 1px solid var(--border-primary); }
        .tf-type-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: var(--space-2); }
        .tf-type-card { padding: var(--space-3); border: 2px solid var(--border-primary); border-radius: var(--radius-md); background: var(--bg-surface); cursor: pointer; text-align: right; transition: all var(--transition-fast); font-family: inherit; }
        .tf-type-card:hover { border-color: var(--color-primary); }
        .tf-type-card--active { border-color: var(--color-primary); background: var(--color-primary-light); }
        .tf-type-name { font-weight: 700; font-size: var(--text-sm); color: var(--text-primary); margin-bottom: 4px; }
        .tf-type-meta { display: flex; gap: var(--space-2); font-size: 11px; }
        .tf-type-cat { color: var(--text-muted); }
        .tf-type-desc { font-size: 11px; color: var(--text-muted); margin-top: 4px; line-height: 1.4; }
        .tf-scope-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: var(--space-2); }
        .tf-scope-btn { padding: var(--space-3) var(--space-2); border: 2px solid var(--border-primary); border-radius: var(--radius-md); background: var(--bg-surface); color: var(--text-secondary); font-size: var(--text-sm); cursor: pointer; transition: all var(--transition-fast); font-family: inherit; font-weight: 500; display: flex; flex-direction: column; align-items: center; gap: 4px; }
        .tf-scope-btn:hover { border-color: var(--color-primary); color: var(--color-primary); }
        .tf-scope-btn--active { border-color: var(--color-primary); background: var(--color-primary); color: #fff !important; font-weight: 700; }
        .tf-dates, .tf-values-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: var(--space-3); }
        .tf-unit-badge { display: inline-block; padding: 1px 6px; border-radius: 4px; background: var(--color-primary-light); color: var(--color-primary); font-size: 11px; font-weight: 700; margin-right: var(--space-1); }
        .tf-suggest-btn { display: block; margin-top: 4px; padding: 2px 8px; border: none; background: var(--bg-surface-2); color: var(--color-primary); font-size: 11px; font-weight: 600; cursor: pointer; border-radius: var(--radius-sm); font-family: inherit; transition: background var(--transition-fast); }
        .tf-suggest-btn:hover { background: var(--color-primary-light); }
        .tf-value-visual { display: flex; height: 26px; border-radius: var(--radius-md); overflow: hidden; margin-bottom: var(--space-2); }
        .tf-zone { display: flex; align-items: center; justify-content: center; font-size: 10px; font-weight: 700; color: rgba(255,255,255,0.9); }
        .tf-zone--danger  { background: linear-gradient(135deg, #f87171, #ef4444); }
        .tf-zone--success { background: linear-gradient(135deg, #34d399, #10b981); }
        .tf-zone--stretch { background: linear-gradient(135deg, #a78bfa, #7c3aed); }
        .tf-review-card { display: flex; align-items: center; gap: var(--space-3); padding: var(--space-4); background: var(--color-primary-light); border: 1px solid var(--color-primary); border-radius: var(--radius-md); margin-bottom: var(--space-3); }
        .tf-review-grid { display: flex; flex-direction: column; gap: var(--space-2); }
        .tf-review-item { display: flex; justify-content: space-between; align-items: center; padding: var(--space-2) var(--space-3); border-radius: var(--radius-sm); background: var(--bg-surface-2); }
        .tf-review-item--highlight { background: var(--color-success-light); }
        .tf-review-label { font-size: var(--text-xs); color: var(--text-muted); font-weight: 600; }
        .tf-review-value { font-size: var(--text-sm); color: var(--text-primary); font-weight: 600; }
        .tf-tag { font-size: 10px; padding: 1px 6px; border-radius: 99px; background: var(--bg-surface); border: 1px solid var(--border-primary); color: var(--text-secondary); }
        .tf-actions { display: flex; gap: var(--space-3); align-items: center; padding-top: var(--space-3); border-top: 1px solid var(--border-primary); }
        @media (max-width: 600px) {
          .tf-form { padding: var(--space-3); }
          .tf-scope-grid { grid-template-columns: repeat(2, 1fr); }
          .tf-type-grid { grid-template-columns: 1fr; }
          .tf-dates, .tf-values-grid { grid-template-columns: 1fr; }
          .tf-step-label { display: none; }
        }
      `}</style>
    </div>
  )
}
