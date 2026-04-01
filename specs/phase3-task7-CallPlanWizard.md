# Spec: Phase 3 — Task 7 — CallPlanWizard
**الأولوية:** متوسط | **الوقت المقدر:** 3-4 ساعات
**آخر تحديث:** 2026-03-31 (مُعاد كتابتها بعد التحقق من CallPlanInput الحقيقي)

---

## الهدف

استبدال `src/pages/activities/CallPlanForm.tsx` (5/100) بـ **Wizard من 3 خطوات** مبني على `CallPlanInput` الفعلي.

---

## عقد البيانات الحقيقي (المرجع الأساسي)

```typescript
// CallPlanInput — الحقول الموجودة فعلاً في activities.ts
interface CallPlanInput {
  employee_id: string
  plan_date: string
  plan_type?: 'daily' | 'weekly' | 'campaign' | 'recurring'
  template_id?: string | null
  notes?: string | null
}

// CallPlanItemInput — الحقول الموجودة فعلاً
interface CallPlanItemInput {
  customer_id?: string | null
  contact_name?: string | null
  phone_number?: string | null   // مطلوب إذا لا يوجد customer_id
  sequence: number               // مطلوب
  planned_time?: string | null
  estimated_duration_min?: number
  priority?: PlanPriority
  purpose?: string | null
  purpose_type?: PlanItemPurposeType | null
}
```

**لا تُضف حقولاً غير موجودة** (`period_start`, `period_end`, `targeting_type`).

---

## التصميم — 3 خطوات

```
خطوة 0: أساسيات الخطة
خطوة 1: اختيار العملاء
خطوة 2: مراجعة القائمة + إنشاء
```

---

## الخطوة 0 — أساسيات الخطة

| الحقل | النوع | مطلوب | ملاحظة |
|-------|-------|--------|--------|
| `employee_id` | Select/Combobox | نعم | يعبأ بالمستخدم الحالي، قابل للتغيير |
| `plan_date` | date | نعم | تاريخ اليوم افتراضياً |
| `plan_type` | select | لا | daily/weekly/campaign/recurring |
| `template_id` | select | لا | من `useCallPlanTemplates()` |
| `notes` | textarea | لا | ملاحظات |

**hooks:**
```typescript
const { data: employee } = useCurrentEmployee()
const { data: employees } = useHREmployees()
const { data: templates } = useCallPlanTemplates()
```

**State:**
```typescript
const [employeeId, setEmployeeId] = useState('')
const [planDate, setPlanDate] = useState(today)
const [planType, setPlanType] = useState<'daily'|'weekly'|'campaign'|'recurring'>('daily')
const [templateId, setTemplateId] = useState('')
const [notes, setNotes] = useState('')
```

**زر التالي:** معطّل حتى يُختار `employee_id` و `plan_date`.

---

## الخطوة 1 — اختيار العملاء

**فلاتر متاحة من `useCustomers()`:**

```typescript
// هذه هي الفلاتر الفعلية التي يدعمها getCustomers()
const { data: customers } = useCustomers({
  search: customerSearch,
  governorateId: filterGovernorate,
  cityId: filterCity,
  type: filterType,     // نوع العميل إذا كان مدعوماً
  isActive: true,
})
```

**UI:**
```tsx
<SearchInput value={customerSearch} onChange={setCustomerSearch} placeholder="ابحث بالاسم أو الكود..." />

<div className="filter-row">
  <select value={filterGovernorate} onChange={e => setFilterGovernorate(e.target.value)}>
    <option value="">كل المناطق</option>
    {governorates?.map(g => <option key={g.id} value={g.id}>{g.name}</option>)}
  </select>
</div>

{/* قائمة بـ checkbox */}
<div className="customer-select-list">
  {customers?.map(c => (
    <label key={c.id} className="customer-select-item">
      <input
        type="checkbox"
        checked={selectedCustomerIds.includes(c.id)}
        onChange={e => {
          if (e.target.checked) setSelectedCustomerIds(prev => [...prev, c.id])
          else setSelectedCustomerIds(prev => prev.filter(id => id !== c.id))
        }}
      />
      <span className="customer-name">{c.name}</span>
      <span className="customer-code">{c.code}</span>
      {c.phone && <span className="customer-phone">{c.phone}</span>}
    </label>
  ))}
</div>

<div className="selection-summary">
  تم اختيار {selectedCustomerIds.length} عميل
</div>
```

**hooks إضافية:**
```typescript
const { data: governorates } = useGovernorates()
```

**State:**
```typescript
const [customerSearch, setCustomerSearch] = useState('')
const [filterGovernorate, setFilterGovernorate] = useState('')
const [filterCity, setFilterCity] = useState('')
const [filterType, setFilterType] = useState('')
const [selectedCustomerIds, setSelectedCustomerIds] = useState<string[]>([])
```

**زر التالي:** معطّل إذا كانت القائمة فارغة.

---

## الخطوة 2 — مراجعة القائمة + إنشاء

**قائمة العملاء المحددين مع إمكانية التعديل:**
```tsx
{selectedCustomers.map((c, index) => (
  <div key={c.id} className="review-item">
    <div className="review-item__info">
      <span>{index + 1}. {c.name}</span>
    </div>
    <div className="review-item__options">
      {/* وقت مخطط (اختياري) */}
      <input
        type="time"
        value={itemOptions[c.id]?.planned_time ?? ''}
        onChange={e => updateItemOption(c.id, 'planned_time', e.target.value)}
        placeholder="الوقت"
        style={{ width: 100 }}
      />
      {/* غرض المكالمة (اختياري) */}
      <input
        type="text"
        value={itemOptions[c.id]?.purpose ?? ''}
        onChange={e => updateItemOption(c.id, 'purpose', e.target.value)}
        placeholder="غرض المكالمة..."
        className="form-input"
        style={{ flex: 1 }}
      />
      <button onClick={() => removeCustomer(c.id)}>✕</button>
    </div>
  </div>
))}
```

**State للخيارات المتقدمة:**
```typescript
interface ItemOption {
  planned_time?: string
  purpose?: string
  estimated_duration_min?: number
}
const [itemOptions, setItemOptions] = useState<Record<string, ItemOption>>({})

const updateItemOption = (customerId: string, key: keyof ItemOption, value: any) =>
  setItemOptions(prev => ({ ...prev, [customerId]: { ...prev[customerId], [key]: value } }))

const removeCustomer = (id: string) =>
  setSelectedCustomerIds(prev => prev.filter(cid => cid !== id))
```

**ملخص + زر الإنشاء:**
```tsx
<div className="summary-card">
  <div>المندوب: {selectedEmployee?.name}</div>
  <div>تاريخ الخطة: {planDate}</div>
  <div>نوع الخطة: {planType}</div>
  <div>عدد العملاء: {selectedCustomerIds.length}</div>
</div>

<div className="wizard-actions">
  <Button variant="secondary" onClick={() => setStep(1)}>رجوع</Button>
  <Button disabled={selectedCustomerIds.length === 0 || saving} onClick={handleCreate}>
    {saving ? 'جاري الإنشاء...' : 'إنشاء خطة المكالمات'}
  </Button>
</div>
```

---

## منطق الإنشاء

```typescript
const createPlan = useCreateCallPlan()
const addItem = useAddCallPlanItem()
const [saving, setSaving] = useState(false)

const handleCreate = async () => {
  if (selectedCustomerIds.length === 0 || !employeeId || !planDate) return
  setSaving(true)
  try {
    // الخطوة 1: إنشاء الخطة
    const plan = await createPlan.mutateAsync({
      employee_id: employeeId,
      plan_date: planDate,
      plan_type: planType,
      template_id: templateId || null,
      notes: notes || null,
    })

    // الخطوة 2: إضافة البنود
    // useAddCallPlanItem يقبل: { planId: string, item: CallPlanItemInput }
    // (تحقق من signature الفعلي في useQueryHooks.ts)
    await Promise.all(
      selectedCustomerIds.map((customerId, index) =>
        addItem.mutateAsync({
          planId: plan.id,
          item: {
            customer_id: customerId,
            sequence: index + 1,
            planned_time: itemOptions[customerId]?.planned_time || null,
            purpose: itemOptions[customerId]?.purpose || null,
            estimated_duration_min: itemOptions[customerId]?.estimated_duration_min,
          },
        })
      )
    )

    toast.success('تم إنشاء خطة المكالمات')
    navigate(`/activities/call-plans/${plan.id}`)
  } catch (e: any) {
    toast.error(e?.message || 'فشل الإنشاء')
  } finally {
    setSaving(false)
  }
}
```

**hooks للإنشاء:**
```typescript
import {
  useCreateCallPlan,
  useAddCallPlanItem,
  useCurrentEmployee,
  useHREmployees,
  useCallPlanTemplates,
  useCustomers,
  useGovernorates,
} from '@/hooks/useQueryHooks'
```

**ملاحظة:** تحقق من signature الفعلي لـ `useAddCallPlanItem` في `useQueryHooks.ts` سطر 1094 — تأكد أنه يقبل `{ planId, item }` (مشابه لـ `useAddVisitPlanItem`).

---

## Acceptance Criteria

- [ ] المشرف يختار المندوب في خطوة 0 (ليس فقط نفسه)
- [ ] قائمة العملاء قابلة للبحث والفلترة بالمنطقة
- [ ] يمكن إضافة 10+ عملاء في نقرة واحدة
- [ ] يمكن تخصيص وقت مخطط وغرض لكل مكالمة في خطوة 2
- [ ] يمكن حذف عملاء من القائمة قبل الإنشاء
- [ ] الإنشاء يُنشئ الخطة + البنود في DB
- [ ] redirect لصفحة تفاصيل الخطة بعد الإنشاء
