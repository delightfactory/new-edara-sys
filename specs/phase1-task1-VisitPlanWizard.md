# Spec: Phase 1 — Task 1 — VisitPlanWizard
**الأولوية:** حرج | **الوقت المقدر:** 4-6 ساعات

---

## الهدف

استبدال `src/pages/activities/VisitPlanForm.tsx` (فورم بسيط 125 سطر لا يُختار فيه المندوب ولا العملاء) بـ **Wizard متعدد الخطوات** يُغطي كل متطلبات خطة الزيارات.

**الملف الحالي:** `src/pages/activities/VisitPlanForm.tsx`
**الملف المُنتَج:** نفس المسار (استبدال كامل) + ملف مكون جديد اختياري لكل خطوة

---

## السياق — المشكلة الحالية

الفورم الحالي يحتوي فقط على: تاريخ + ملاحظات. ثم يوجّه المشرف لصفحة التفاصيل لإضافة كل عميل بـ modal منفردة.
- خطة 15 عميل = 60 نقرة (غير مقبول تشغيلياً)
- المشرف لا يستطيع إنشاء خطة لمندوب آخر
- لا يوجد bulk selection للعملاء

---

## التصميم المطلوب — 4 خطوات (Stepper)

```
خطوة 0: أساسيات الخطة
خطوة 1: مصدر العملاء
خطوة 2: مراجعة وترتيب العملاء
خطوة 3: مراجعة نهائية + إنشاء
```

---

## المواصفات التفصيلية لكل خطوة

### الخطوة 0 — أساسيات الخطة

**الحقول:**
| الحقل | النوع | مطلوب | ملاحظة |
|-------|-------|--------|--------|
| `employee_id` | Select/Combobox | نعم | dropdown بالموظفين، يبحث بالاسم، يُعبأ تلقائياً بالمستخدم الحالي ويمكن تغييره |
| `plan_date` | date input | نعم | افتراضي: اليوم |
| `plan_type` | select | لا | خيارات: `daily` (يومي), `weekly` (أسبوعي), `campaign` (حملة) — افتراضي: `daily` |
| `notes` | textarea | لا | ملاحظات |

**hooks المستخدمة:**
- `useCurrentEmployee()` → لتعبئة `employee_id` تلقائياً
- `useHREmployees()` → لقائمة الموظفين في الـ dropdown

**زر التالي:** معطّل حتى تُختار التاريخ والموظف

---

### الخطوة 1 — مصدر العملاء

**3 تبويبات (tabs) أو Radio group:**

#### تبويب أ: يدوي
- `SearchInput` للبحث بالاسم أو الكود
- فلاتر: المنطقة (`governorateId`)، المدينة (`cityId`)، نوع العميل (`type`)
- ملاحظة: `getCustomers()` لا يدعم `customer_class` أو `branch_id` — استخدم الفلاتر المتاحة فقط
- قائمة نتائج بـ checkbox متعدد
- زر "أضف المحددين (X)" → ينقل إلى خطوة 2

**hooks:**
- `useCustomers({ search, governorateId, cityId, type })` → للنتائج (هذه هي الفلاتر الفعلية المدعومة)

#### تبويب ب: من قالب
- قائمة القوالب المتاحة
- زر "استخدم هذا القالب" → يُحمّل عملاء القالب وينتقل لخطوة 2

**hooks:**
- `useVisitPlanTemplates()` → لقائمة القوالب

#### تبويب ج: توليد تلقائي
- حقل "خاملون أكثر من X يوم بدون زيارة" (number input)
- checkbox "متأخرو السداد (overdue > 30 يوم)"
- زر "ولّد القائمة" → يُنفّذ استعلام وينتقل لخطوة 2

**ملاحظة التنفيذ:** التوليد التلقائي يستدعي `useCustomers()` مع فلاتر متقدمة. إذا لم يكن الـ hook يدعم هذه الفلاتر بعد، يمكن بناء الاستعلام في الـ step مع تعليق `// TODO: add filter params to service`

---

### الخطوة 2 — مراجعة وترتيب العملاء

**المحتوى:**
- قائمة العملاء المحددين (من خطوة 1)
- لكل عميل:
  - اسم العميل + كود
  - أولوية (رقم قابل للتعديل، أو drag handle)
  - وقت مقدر بالدقائق (number input، اختياري)
  - زر X لحذف العميل من القائمة
- ملخص أسفل القائمة: "X عميل، مجموع الوقت: Y دقيقة"
- **Drag-and-drop:** اختياري في هذه المرحلة — يمكن الاستعاضة عنه بأزرار ↑ ↓ لكل بند

**state المطلوبة:**
```typescript
interface SelectedCustomer {
  id: string
  name: string
  code?: string
  sequence?: number
  estimated_duration_min?: number  // الاسم الصحيح في VisitPlanItemInput
}
selectedCustomers: SelectedCustomer[]
```

**زر التالي:** معطّل إذا كانت القائمة فارغة

---

### الخطوة 3 — مراجعة نهائية + إنشاء

**ملخص القراءة فقط:**
- المندوب: اسم الموظف
- التاريخ: بتنسيق `yyyy/MM/dd`
- نوع الخطة
- عدد العملاء
- الملاحظات (إذا وجدت)

**خيار إضافي:**
- checkbox "تأكيد الخطة فوراً بعد الإنشاء؟" (يضع status=confirmed)

**أزرار:**
- "إنشاء الخطة" → يُنفّذ الإنشاء
- "رجوع" → يعود لخطوة 2

---

## منطق الإنشاء (onSubmit)

```typescript
// الخطوة 1: إنشاء الخطة
const plan = await createVisitPlan.mutateAsync({
  employee_id,
  plan_date,
  notes: notes || null,
  // plan_type إذا كان الحقل موجوداً في VisitPlanInput
})

// الخطوة 2: إضافة البنود بالتسلسل أو بـ Promise.all
// useAddVisitPlanItem يقبل: { planId: string, item: VisitPlanItemInput }
await Promise.all(
  selectedCustomers.map((c, index) =>
    addVisitPlanItem.mutateAsync({
      planId: plan.id,           // ✅ planId (وليس plan_id)
      item: {
        customer_id: c.id,
        sequence: index + 1,
        estimated_duration_min: c.estimated_duration_min ?? null,  // ✅ الاسم الصحيح
      },
    })
  )
)

// الخطوة 3: إذا أراد التأكيد الفوري
if (confirmImmediately) {
  // ✅ useUpdateVisitPlan يتطلب { id, input } وليس { id, status } مباشرة
  // الخيار الأفضل: استخدام useConfirmVisitPlan الذي يقبل id فقط
  await confirmVisitPlan.mutateAsync(plan.id)
  // أو:
  // await updateVisitPlan.mutateAsync({ id: plan.id, input: { status: 'confirmed' } })
}

toast.success('تم إنشاء خطة الزيارات')
navigate(`/activities/visit-plans/${plan.id}`)
```

**hooks للإنشاء:**
- `useCreateVisitPlan()`
- `useAddVisitPlanItem()`
- `useConfirmVisitPlan()` — للتأكيد الفوري (يقبل `id: string` مباشرة)
- `useUpdateVisitPlan()` — للتعديل العام (يقبل `{ id, input }`)

---

## هيكل الملف المقترح

```typescript
// src/pages/activities/VisitPlanForm.tsx (استبدال كامل)

// الحالة الرئيسية
const [step, setStep] = useState(0)  // 0..3

// بيانات خطوة 0
const [employeeId, setEmployeeId] = useState('')
const [planDate, setPlanDate] = useState(today)
const [planType, setPlanType] = useState<'daily'|'weekly'|'campaign'>('daily')
const [notes, setNotes] = useState('')

// بيانات خطوة 1-2
const [selectedCustomers, setSelectedCustomers] = useState<SelectedCustomer[]>([])
const [sourceTab, setSourceTab] = useState<'manual'|'template'|'auto'>('manual')

// خطوة 3
const [confirmImmediately, setConfirmImmediately] = useState(false)

// تقسيم الـ JSX لـ renderStep(step: number) switch
```

---

## Acceptance Criteria

- [ ] المشرف يستطيع إنشاء خطة لأي موظف آخر (ليس نفسه فقط)
- [ ] يمكن إضافة 10+ عملاء في خطوة واحدة من تبويب "يدوي"
- [ ] زر "التالي" معطّل إذا لم تكتمل بيانات الخطوة
- [ ] لا يُنشأ أي record في DB حتى الخطوة 3
- [ ] رسالة toast.success عند الإنشاء + redirect لصفحة التفاصيل
- [ ] عند خطأ في الإنشاء: toast.error + يبقى في الخطوة 3

---

## ملاحظات التنفيذ

- لا تنشئ ملفات components منفصلة إلا إذا تجاوز المكون 300 سطر
- `Stepper` جاهز في `@/components/ui/Stepper` — استخدمه مباشرةً
- إذا واجهت غموضاً في types، افتح `src/lib/types/activities.ts` وتحقق
- `VisitPlanInput` موجود في types — تحقق من الحقول المتاحة قبل إضافة حقول جديدة
