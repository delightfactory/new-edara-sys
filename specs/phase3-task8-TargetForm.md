# Spec: Phase 3 — Task 8 — TargetForm (الفلاتر المتخصصة حسب نوع الهدف)
**الأولوية:** متوسط | **الوقت المقدر:** 2 ساعة

---

## الهدف

إضافة حقول ديناميكية لـ `src/pages/activities/TargetForm.tsx` تظهر حسب نوع الهدف المختار.
الدرجة الحالية: 60/100 — أفضل الشاشات.

---

## الملف المستهدف

`src/pages/activities/TargetForm.tsx` — **تعديل (إضافة حقول ديناميكية)**

اقرأ الملف كاملاً أولاً.

---

## الحقول المطلوب إضافتها

### جدول الحقول حسب النوع

| `target_type.code` | الحقول الإضافية |
|---------------------|----------------|
| `product_qty` | `product_id` (Select المنتجات) أو `category_id` (Select التصنيفات) |
| `reactivation` | `dormancy_days` (number — أيام الخمول، مطلوب) |
| `upgrade_value` | `min_order_value` (number — الحد الأدنى للطلب) |
| `category_spread` | `target_sku_count` (number — عدد التصنيفات المستهدفة) |

---

## التنفيذ

### أ) استخراج نوع الهدف المختار

```typescript
// افترض أن هناك state أو watch لـ target_type_id
// إذا كان react-hook-form:
const { watch } = useForm(...)
// الحقل الصحيح هو type_id (وليس target_type_id)
const selectedTypeId = watch('type_id')   // ✅ type_id

// أوجد الـ type object من القائمة
const { data: targetTypes } = useTargetTypes()
const selectedType = targetTypes?.find(t => t.id === selectedTypeId)
const typeCode = selectedType?.code // 'product_qty' | 'reactivation' | ...
```

### ب) Section ديناميكي

أضفه بعد حقل نوع الهدف مباشرةً:

```tsx
{/* حقول ديناميكية حسب نوع الهدف */}
{typeCode === 'product_qty' && (
  <div className="form-group">
    <label className="form-label">المنتج المستهدف</label>
    <select
      className="form-input"
      value={productId}
      onChange={e => setProductId(e.target.value)}
    >
      <option value="">كل المنتجات</option>
      {products?.map(p => (
        <option key={p.id} value={p.id}>{p.name}</option>
      ))}
    </select>
    <label className="form-label" style={{ marginTop: 'var(--space-3)' }}>أو حسب تصنيف</label>
    <select
      className="form-input"
      value={categoryId}
      onChange={e => setCategoryId(e.target.value)}
    >
      <option value="">كل التصنيفات</option>
      {categories?.map(c => (
        <option key={c.id} value={c.id}>{c.name}</option>
      ))}
    </select>
  </div>
)}

{typeCode === 'reactivation' && (
  <div className="form-group">
    <label className="form-label">
      عدد أيام الخمول <span className="form-required">*</span>
    </label>
    <input
      type="number"
      className="form-input"
      min={1}
      value={dormancyDays}
      onChange={e => setDormancyDays(Number(e.target.value))}
      placeholder="مثال: 60 يوماً بدون طلب"
      required
    />
    <span className="form-hint">العميل الذي لم يطلب منذ X يوم يُعتبر خاملاً</span>
  </div>
)}

{/* upgrade_value و category_spread: لا حقول إضافية في TargetInput حاليًا */}
{(typeCode === 'upgrade_value' || typeCode === 'category_spread') && (
  <div className="form-group">
    <p style={{ color: 'var(--text-muted)', fontSize: 'var(--text-sm)' }}>
      {typeCode === 'upgrade_value'
        ? 'هدف ترقية قيمة الطلب — لا توجد فلاتر إضافية متاحة حالياً'
        : 'هدف انتشار التصنيفات — لا توجد فلاتر إضافية متاحة حالياً'
      }
      {/* TODO: أضف min_order_value / target_sku_count إلى TargetInput عند توسيع الـ schema */}
    </p>
  </div>
)}
```

### ج) State الجديد

```typescript
const [productId, setProductId] = useState('')
const [categoryId, setCategoryId] = useState('')
const [dormancyDays, setDormancyDays] = useState<number>(60)
// min_order_value و target_sku_count غير موجودتين في TargetInput — لا تُضفهما
```

### د) Hooks إضافية

```typescript
import { useProducts, useCategories } from '@/hooks/useQueryHooks'
const { data: products } = useProducts()
const { data: categories } = useCategories()
```

### هـ) في الـ payload

```typescript
// أضف الحقول الديناميكية للـ payload حسب نوع الهدف
const payload: TargetInput = {
  ...baseFields,
  // الحقول الديناميكية
  ...(typeCode === 'product_qty' && { product_id: productId || null, category_id: categoryId || null }),
  ...(typeCode === 'reactivation' && { dormancy_days: dormancyDays }),
  // upgrade_value و category_spread: لا حقول TargetInput إضافية حالياً
  // TODO: أضف min_order_value / target_sku_count هنا عند إضافتهما للـ schema
}
```

**ملاحظة:** إذا كانت هذه الحقول غير موجودة في `TargetInput` type، أضفها كـ `Partial<Record<string, any>>` مع تعليق `// TODO: add to TargetInput type`.

---

## reset عند تغيير نوع الهدف

```typescript
// عند تغيير typeCode، نظّف الحقول الديناميكية
useEffect(() => {
  setProductId('')
  setCategoryId('')
  setDormancyDays(60)
}, [typeCode])
```

---

## Acceptance Criteria

- [ ] عند اختيار نوع `product_qty`، تظهر حقلا المنتج والتصنيف
- [ ] عند اختيار نوع `reactivation`، يظهر حقل أيام الخمول (مطلوب)
- [ ] عند اختيار نوع `upgrade_value` أو `category_spread`، يظهر نص توضيحي (لا حقول — غير مدعومة في TargetInput حالياً)
- [ ] الحقول الديناميكية (`product_id`, `category_id`, `dormancy_days`) تُعاد ضبطها عند تغيير النوع
- [ ] `product_id`, `category_id`, `dormancy_days` تُحفظ مع الهدف في DB
- [ ] الفورم يعمل كما كان للأنواع الأخرى بدون تغيير
- [ ] الحقل المُستخدم هو `type_id` وليس `target_type_id`
