# Spec: Phase 1 — Task 2 — VisitPlanDetail (Skip + Improvements)
**الأولوية:** حرج | **الوقت المقدر:** 2-3 ساعات

---

## الهدف

إضافة 3 تحسينات لـ `src/pages/activities/VisitPlanDetail.tsx`:
1. **تفعيل زر Skip** — `onSkip` موجودة في `PlanItemCard` لكن لم تُمرَّر
2. **زر "إضافة متعددة"** — bulk add من قائمة مفلترة بدلاً من modal واحدة
3. **إعادة الترتيب** — أزرار ↑ ↓ لتغيير sequence البنود

---

## الملف المستهدف

`src/pages/activities/VisitPlanDetail.tsx` — **تعديل (لا استبدال)**

اقرأ الملف كاملاً أولاً قبل البدء.

---

## التغيير 1: تفعيل Skip modal

### الوضع الحالي
```tsx
// في VisitPlanDetail.tsx — PlanItemCard مُستخدمة لكن onSkip غير مُمررة
<PlanItemCard
  item={item}
  onComplete={...}
  // onSkip مفقودة هنا
/>
```

### المطلوب

**أ) إضافة state:**
```typescript
const [skipItem, setSkipItem] = useState<VisitPlanItem | null>(null)
const [skipReason, setSkipReason] = useState('')
```

**ب) تمرير onSkip:**
```tsx
<PlanItemCard
  item={item}
  onComplete={...}
  onSkip={(item) => {
    setSkipItem(item)
    setSkipReason('')
  }}
/>
```

**ج) Modal جديد لإدخال السبب:**
```tsx
<ResponsiveModal
  open={!!skipItem}
  onClose={() => setSkipItem(null)}
  title="تخطي هذا البند"
>
  <div>
    <label className="form-label">سبب التخطي <span className="form-required">*</span></label>
    <textarea
      className="form-textarea"
      rows={3}
      value={skipReason}
      onChange={e => setSkipReason(e.target.value)}
      placeholder="اذكر سبب تخطي هذا العميل..."
    />
    <div style={{ display: 'flex', gap: 'var(--space-3)', justifyContent: 'flex-end', marginTop: 'var(--space-4)' }}>
      <Button variant="secondary" onClick={() => setSkipItem(null)}>إلغاء</Button>
      <Button
        variant="danger"
        disabled={!skipReason.trim()}
        onClick={handleSkipConfirm}
      >
        تأكيد التخطي
      </Button>
    </div>
  </div>
</ResponsiveModal>
```

**د) دالة handleSkipConfirm:**
```typescript
const updateItem = useUpdateVisitPlanItem()

const handleSkipConfirm = () => {
  if (!skipItem || !skipReason.trim() || !plan) return
  // useUpdateVisitPlanItem يقبل: { itemId, input, planId }
  updateItem.mutate(
    {
      itemId: skipItem.id,
      planId: plan.id,
      input: { status: 'skipped', skip_reason: skipReason.trim() },
    },
    {
      onSuccess: () => {
        toast.success('تم تخطي البند')
        setSkipItem(null)
        setSkipReason('')
      },
      onError: (e: any) => toast.error(e?.message || 'فشل التحديث'),
    }
  )
}
```

**ملاحظة:** تحقق من أن `VisitPlanItemInput` تحتوي على `skip_reason` و `status`. إذا لم تكن موجودة، أضفها كـ `Partial<{status: string, skip_reason: string}>` مع تعليق.

---

## التغيير 2: زر "إضافة متعددة"

### الوضع الحالي
يوجد زر "إضافة عميل" يفتح modal لإضافة عميل واحد فقط.

### المطلوب

**أ) إضافة state:**
```typescript
const [bulkAddOpen, setBulkAddOpen] = useState(false)
const [bulkSearch, setBulkSearch] = useState('')
const [bulkSelected, setBulkSelected] = useState<string[]>([]) // customer IDs
```

**ب) استبدال زر "إضافة عميل" بـ "إضافة عميل/عملاء"** (أو إضافة زر ثانٍ):
```tsx
<Button onClick={() => setBulkAddOpen(true)}>
  إضافة عملاء
</Button>
```

**ج) Modal الإضافة الجماعية:**
```tsx
<ResponsiveModal
  open={bulkAddOpen}
  onClose={() => { setBulkAddOpen(false); setBulkSelected([]) }}
  title="إضافة عملاء للخطة"
>
  <SearchInput
    value={bulkSearch}
    onChange={setBulkSearch}
    placeholder="ابحث بالاسم أو الكود..."
  />
  {/* قائمة نتائج بـ checkbox */}
  <div style={{ maxHeight: 300, overflowY: 'auto', marginTop: 'var(--space-3)' }}>
    {customers?.map(c => (
      <label key={c.id} style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', padding: 'var(--space-2) 0', cursor: 'pointer' }}>
        <input
          type="checkbox"
          checked={bulkSelected.includes(c.id)}
          onChange={e => {
            if (e.target.checked) setBulkSelected(prev => [...prev, c.id])
            else setBulkSelected(prev => prev.filter(id => id !== c.id))
          }}
        />
        <span>{c.name}</span>
        <span style={{ color: 'var(--text-muted)', fontSize: 'var(--text-xs)' }}>{c.code}</span>
      </label>
    ))}
  </div>
  <div style={{ display: 'flex', gap: 'var(--space-3)', justifyContent: 'flex-end', marginTop: 'var(--space-4)' }}>
    <Button variant="secondary" onClick={() => { setBulkAddOpen(false); setBulkSelected([]) }}>إلغاء</Button>
    <Button disabled={bulkSelected.length === 0 || addingBulk} onClick={handleBulkAdd}>
      {addingBulk ? 'جاري الإضافة...' : `إضافة (${bulkSelected.length})`}
    </Button>
  </div>
</ResponsiveModal>
```

**د) دالة handleBulkAdd:**
```typescript
const addItem = useAddVisitPlanItem()
const [addingBulk, setAddingBulk] = useState(false)

const handleBulkAdd = async () => {
  if (!plan || bulkSelected.length === 0) return
  setAddingBulk(true)
  const currentMax = planItems?.length ?? 0
  try {
    // ✅ useAddVisitPlanItem يقبل { planId, item } وليس plan_id مباشرة
    await Promise.all(
      bulkSelected.map((customerId, i) =>
        addItem.mutateAsync({
          planId: plan.id,           // ✅ planId (وليس plan_id)
          item: {                    // ✅ item object
            customer_id: customerId,
            sequence: currentMax + i + 1,
          },
        })
      )
    )
    toast.success(`تمت إضافة ${bulkSelected.length} عميل`)
    setBulkAddOpen(false)
    setBulkSelected([])
  } catch (e: any) {
    toast.error(e?.message || 'فشل إضافة بعض العملاء')
  } finally {
    setAddingBulk(false)
  }
}
```

**hooks مطلوبة:**
- `useCustomers({ search: bulkSearch })` → لقائمة العملاء في modal

---

## التغيير 3: إعادة الترتيب بأزرار ↑ ↓

### المطلوب

لكل بند في القائمة، أضف زرَّين صغيرَين:

```tsx
<div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
  <button
    disabled={index === 0 || reordering}
    onClick={() => handleMoveItem(item, 'up')}
    style={{ border: 'none', background: 'transparent', cursor: 'pointer', padding: 2 }}
    title="نقل لأعلى"
  >
    ↑
  </button>
  <button
    disabled={index === items.length - 1 || reordering}
    onClick={() => handleMoveItem(item, 'down')}
    style={{ border: 'none', background: 'transparent', cursor: 'pointer', padding: 2 }}
    title="نقل لأسفل"
  >
    ↓
  </button>
</div>
```

**دالة handleMoveItem:**
```typescript
const [reordering, setReordering] = useState(false)

const handleMoveItem = async (item: VisitPlanItem, direction: 'up' | 'down') => {
  if (!planItems || !plan) return
  const sorted = [...planItems].sort((a, b) => (a.sequence ?? 0) - (b.sequence ?? 0))
  const idx = sorted.findIndex(i => i.id === item.id)
  const swapIdx = direction === 'up' ? idx - 1 : idx + 1
  if (swapIdx < 0 || swapIdx >= sorted.length) return

  const current = sorted[idx]
  const swap = sorted[swapIdx]
  setReordering(true)
  try {
    // useUpdateVisitPlanItem يقبل: { itemId, input, planId }
    await Promise.all([
      updateItem.mutateAsync({ itemId: current.id, planId: plan.id, input: { sequence: swap.sequence } }),
      updateItem.mutateAsync({ itemId: swap.id,    planId: plan.id, input: { sequence: current.sequence } }),
    ])
  } catch (e: any) {
    toast.error('فشل تغيير الترتيب')
  } finally {
    setReordering(false)
  }
}
```

---

## Acceptance Criteria

- [ ] زر Skip ظاهر على كل بند في الخطة غير المكتملة
- [ ] الضغط على Skip يفتح modal يطلب سبباً
- [ ] لا يمكن تأكيد التخطي بدون سبب (زر معطّل)
- [ ] بعد التخطي: البند يُحدَّث وtوast.success يظهر
- [ ] زر "إضافة عملاء" يفتح modal بـ checkbox
- [ ] يمكن إضافة أكثر من عميل في نقرة واحدة
- [ ] أزرار ↑ ↓ تُغيّر sequence في DB
- [ ] الزر ↑ معطّل للبند الأول، ↓ معطّل للأخير
