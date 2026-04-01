# Spec: Phase 1 — Task 3 — ActivityForm (إصلاح وإكمال)
**الأولوية:** حرج | **الوقت المقدر:** 3-4 ساعات
**آخر تحديث:** 2026-03-31 (مُصحَّح بعد التحقق من الكود الفعلي)

---

## الهدف

إصلاح وإكمال `src/pages/activities/ActivityForm.tsx` بإضافة 4 تحسينات:
1. **اختيار العميل** — عند فتح الفورم بدون رابط خطة
2. **حقلا Subject** — `subject` و `subject_type` مفقودان
3. **إصلاح GPS** — يبقى blocking **لأنواع تتطلب GPS فقط**، يصبح اختياري للباقي
4. **الإجراءات المرتبطة بالنتيجة** — أزرار تظهر حسب `outcome_type`

---

## الملف المستهدف

`src/pages/activities/ActivityForm.tsx` — **تعديل (لا استبدال)**

اقرأ الملف كاملاً أولاً. الدرجة الحالية: 35/100.

---

## التغيير 1: اختيار العميل

### الوضع الحالي
الفورم يأخذ `customerId` من URL params فقط. إذا لم يكن في الـ URL، لا يوجد طريقة لاختيار عميل.

### المطلوب

**أ) تحقق من URL params:**
```typescript
const [searchParams] = useSearchParams()
// ✅ أسماء الـ params مطابقة للكود الفعلي في ActivityForm.tsx
const customerIdFromUrl = searchParams.get('customerId')
const visitPlanItemIdFromUrl = searchParams.get('visitPlanItemId')
const callPlanItemIdFromUrl = searchParams.get('callPlanItemId')
```

**ب) إضافة state:**
```typescript
const [selectedCustomerId, setSelectedCustomerId] = useState(customerIdFromUrl ?? '')
```

**ج) إظهار dropdown فقط إذا لم يأتِ من URL:**
```tsx
{!customerIdFromUrl && (
  <div className="form-group">
    <label className="form-label">العميل</label>
    <select
      className="form-input"
      value={selectedCustomerId}
      onChange={e => setSelectedCustomerId(e.target.value)}
    >
      <option value="">اختر العميل... (اختياري)</option>
      {customers?.map(c => (
        <option key={c.id} value={c.id}>{c.name} ({c.code})</option>
      ))}
    </select>
  </div>
)}
```

**hooks:**
- `useCustomers()` → لقائمة العملاء (تحقق من أن `requires_customer` في ActivityType يُحدد إجبارية الاختيار)

**في الـ payload:**
```typescript
customer_id: (selectedCustomerId || customerIdFromUrl) || null,
visit_plan_item_id: visitPlanItemIdFromUrl || null,
call_plan_item_id: callPlanItemIdFromUrl || null,
```

---

## التغيير 2: حقلا Subject

### المطلوب

أضف حقلَين بعد حقل نوع النشاط:

```tsx
{/* نوع الموضوع */}
<div className="form-group">
  <label className="form-label">نوع الموضوع</label>
  <select
    className="form-input"
    value={subjectType}
    onChange={e => setSubjectType(e.target.value)}
  >
    <option value="">بدون موضوع محدد</option>
    <option value="product">منتج</option>
    <option value="offer">عرض</option>
    <option value="complaint">شكوى</option>
    <option value="collection">تحصيل</option>
    <option value="general">عام</option>
  </select>
</div>

{/* الموضوع */}
<div className="form-group">
  <label className="form-label">الموضوع</label>
  <input
    type="text"
    className="form-input"
    value={subject}
    onChange={e => setSubject(e.target.value)}
    placeholder="وصف مختصر لهدف الزيارة..."
  />
</div>
```

**State:**
```typescript
const [subject, setSubject] = useState('')
const [subjectType, setSubjectType] = useState('')
```

**في الـ payload (`ActivityInput`):**
```typescript
subject: subject || null,
subject_type: subjectType || null,
```

---

## التغيير 3: إصلاح GPS (Conditional Logic)

### السياق المهم
`ActivityType` interface يحتوي على حقل `requires_gps: boolean`.
- إذا `selectedActivityType.requires_gps === true` → GPS **إجباري** (يبقى blocking)
- إذا `selectedActivityType.requires_gps === false` → GPS **اختياري** (لا يُوقف الحفظ)

### الوضع الحالي (خطأ)
```typescript
// يوقف الحفظ دائماً بدون GPS
if (!gpsCoords) { toast.error('يجب تفعيل GPS'); return }
```

### المطلوب

**أ) احصل على ActivityType المختار:**
```typescript
const { data: activityTypes } = useActivityTypes()
const selectedActivityType = activityTypes?.find(t => t.id === typeId)
const gpsRequired = selectedActivityType?.requires_gps ?? false
```

**ب) منطق GPS الجديد في handleSubmit:**
```typescript
// GPS إجباري فقط لأنواع تتطلبه
if (gpsRequired && !gpsCoords) {
  toast.error('هذا النوع من النشاط يتطلب تحديد الموقع الجغرافي')
  return  // blocking — يبقى كما هو
}

// GPS اختياري للباقي — فقط نسجل gps_verified=false
const payload: ActivityInput = {
  ...otherFields,
  gps_lat: gpsCoords?.lat ?? null,
  gps_lng: gpsCoords?.lng ?? null,
  gps_verified: !!gpsCoords,
}
```

**ج) لا تُظهر toast.warning في هذه الحالة** — السلوك الاختياري هو الافتراضي، لا حاجة لتحذير.

---

## التغيير 4: الإجراءات المرتبطة بالنتيجة

### الحقول المتاحة في `ActivityInput`

```typescript
// الحقول الفعلية لربط العمليات:
order_id?: string | null
collection_id?: string | null
followup_activity_id?: string | null
```

**لا يوجد حقل `followup_date`** في `ActivityInput` — لا تُضفه.

### المطلوب

بعد اختيار `outcome_type`، تظهر section توجيهية:

```tsx
{outcomeType && (
  <div className="form-group outcome-actions">
    <label className="form-label">الإجراء المرتبط بالنتيجة</label>

    {outcomeType === 'order_placed' && (
      <div className="outcome-action-hint">
        <p className="outcome-hint-text">
          يمكنك إنشاء طلب بيع بعد حفظ هذا النشاط مباشرةً
        </p>
        <Button
          type="button"
          variant="secondary"
          onClick={() => {
            // حفظ النشاط أولاً ثم التوجيه لطلب البيع
            // أو: فتح في tab جديد
            const customerId = selectedCustomerId || customerIdFromUrl
            navigate(`/sales/orders/new${customerId ? `?customerId=${customerId}` : ''}`)
          }}
        >
          إنشاء طلب بيع ←
        </Button>
      </div>
    )}

    {outcomeType === 'collection' && (
      <div className="outcome-action-hint">
        <p className="outcome-hint-text">يمكنك إنشاء سند تحصيل بعد الحفظ</p>
        <Button
          type="button"
          variant="secondary"
          onClick={() => {
            const customerId = selectedCustomerId || customerIdFromUrl
            // ✅ Route الصحيح: /finance/payments (وليس /finance/receipts)
            navigate(`/finance/payments${customerId ? `?customerId=${customerId}` : ''}`)
          }}
        >
          إنشاء سند تحصيل ←
        </Button>
      </div>
    )}

    {outcomeType === 'followup_visit' && (
      <div className="outcome-action-hint">
        <p className="outcome-hint-text">
          بعد الحفظ: اذهب لصفحة النشاط وستجد زر "جدّل زيارة متابعة"
        </p>
        {/* لا يوجد حقل followup_date في ActivityInput */}
        {/* followup_activity_id يُربط لاحقاً بعد إنشاء النشاط التالي */}
      </div>
    )}

    {outcomeType === 'complaint' && (
      <p className="outcome-hint-text">
        يمكنك فتح تذكرة شكوى من قائمة الشكاوى بعد حفظ النشاط
      </p>
    )}
  </div>
)}
```

**ملاحظة:** أزرار "إنشاء طلب بيع" و "إنشاء سند تحصيل" تنقل المستخدم لصفحة الإنشاء المعنية — لا يتم ربط `order_id` أو `collection_id` تلقائياً في هذه المرحلة. هذا يحتاج flow أكثر تعقيداً يُعالَج في مرحلة لاحقة.

---

## CSS الإضافي

```css
.outcome-actions {
  padding: var(--space-3);
  background: var(--bg-surface-2);
  border-radius: var(--radius-md);
  border-right: 3px solid var(--color-warning);
}
.outcome-action-hint {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
}
.outcome-hint-text {
  margin: 0;
  font-size: var(--text-sm);
  color: var(--text-muted);
}
```

---

## Acceptance Criteria

- [ ] عند فتح `/activities/new` بدون `?customerId=`، يظهر dropdown لاختيار العميل
- [ ] عند فتح `/activities/new?customerId=XXX`، لا يظهر الـ dropdown
- [ ] حقلا `subject` و `subject_type` ظاهران ويُحفظان في DB
- [ ] **GPS blocking** يبقى فقط لأنواع `requires_gps === true`
- [ ] **GPS optional** بدون أي blocking أو warning لأنواع `requires_gps === false`
- [ ] عند اختيار `outcome_type=order_placed`، يظهر زر "إنشاء طلب بيع"
- [ ] عند اختيار `outcome_type=collection`، يظهر زر "إنشاء سند تحصيل"
- [ ] عند اختيار `outcome_type=followup_visit`، يظهر نص توجيهي (لا حقل تاريخ)
- [ ] لا يوجد حقل `followup_date` في payload

---

## ملاحظة هامة للمنفّذ

`ActivityInput.type_id` (وليس `activity_type_id`) — تأكد من الاسم الصحيح عند بناء الـ payload.
