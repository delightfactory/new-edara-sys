# Spec: Phase 2 — Task 5 — ActivityDetail (إكمال الحقول المفقودة)
**الأولوية:** عالي | **الوقت المقدر:** 2 ساعة

---

## الهدف

إضافة الحقول المفقودة من `src/pages/activities/ActivityDetail.tsx`.
الدرجة الحالية: 40/100.

---

## الملف المستهدف

`src/pages/activities/ActivityDetail.tsx` — **تعديل (إضافة حقول)**

اقرأ الملف كاملاً أولاً.

---

## الحقول المطلوب إضافتها

### 1. اسم الموظف الذي سجّل النشاط

في قسم "معلومات النشاط"، أضف:
```tsx
<DetailRow label="المسجّل" value={activity.employee?.name ?? activity.employee_id} />
```

### 2. مدة الزيارة

```tsx
{activity.duration_minutes && (
  <DetailRow
    label="مدة الزيارة"
    value={`${activity.duration_minutes} دقيقة`}
  />
)}
```

### 3. المسافة من موقع العميل

```tsx
{activity.distance_meters != null && (
  <DetailRow
    label="المسافة من الموقع"
    value={
      activity.distance_meters < 1000
        ? `${activity.distance_meters} متر`
        : `${(activity.distance_meters / 1000).toFixed(1)} كم`
    }
  />
)}
```

### 4. موضوع الزيارة

```tsx
{activity.subject && (
  <DetailRow label="الموضوع" value={activity.subject} />
)}
{activity.subject_type && (
  <DetailRow label="نوع الموضوع" value={activity.subject_type} />
)}
```

### 5. روابط العمليات المرتبطة

أضف section كامل:
```tsx
{(activity.order_id || activity.collection_id || activity.followup_activity_id) && (
  <div className="linked-operations">
    <div className="section-title">العمليات المرتبطة</div>
    {activity.order_id && (
      <div className="linked-op-item">
        <span>طلب بيع مرتبط</span>
        <Button
          variant="ghost"
          onClick={() => navigate(`/sales/orders/${activity.order_id}`)}
        >
          عرض الطلب ←
        </Button>
      </div>
    )}
    {activity.collection_id && (
      <div className="linked-op-item">
        <span>سند تحصيل مرتبط</span>
        <Button
          variant="ghost"
          onClick={() => navigate(`/finance/payments/${activity.collection_id}`)}
        >
          عرض سند التحصيل ←
        </Button>
      </div>
    )}
    {activity.followup_activity_id && (
      <div className="linked-op-item">
        <span>زيارة متابعة</span>
        <Button
          variant="ghost"
          onClick={() => navigate(`/activities/${activity.followup_activity_id}`)}
        >
          عرض الزيارة التالية ←
        </Button>
      </div>
    )}
  </div>
)}
```

### 6. زر الحذف الناعم

**ملاحظة:** لا توجد صلاحية `ACTIVITIES_DELETE` منفصلة. الحذف الناعم يتم عبر `soft_delete_activity()` RPC التي تتحقق من الصلاحيات حسب الدور:

| الدور | الصلاحية | القيد الزمني |
|-------|----------|---------------|
| المالك (صاحب النشاط) | `ACTIVITIES_UPDATE_OWN` | خلال 24 ساعة من الإنشاء |
| المشرف | `ACTIVITIES_READ_TEAM` | خلال 48 ساعة من الإنشاء |
| الإدارة | `ACTIVITIES_READ_ALL` | بدون قيد |

**الشرط في الواجهة:**
```tsx
// ✅ يعكس سلوك soft_delete_activity() RPC بالضبط
// المالك + المشرف + الإدارة — كل حسب صلاحياته
{(can('ACTIVITIES_UPDATE_OWN') || can('ACTIVITIES_READ_TEAM') || can('ACTIVITIES_READ_ALL')) 
  && !activity.deleted_at && (
  <ConfirmDialog
    trigger={<Button variant="danger">حذف النشاط</Button>}
    title="حذف النشاط"
    description="هل أنت متأكد؟ سيُحذف النشاط بشكل ناعم ولن يظهر في التقارير."
    onConfirm={handleSoftDelete}
  />
)}
```

**ملاحظة:** الـ RPC تتولى التحقق من الملكية والمهلة الزمنية، لذا الواجهة تعرض الزر لأي شخص يملك إحدى الصلاحيات الثلاث.

```typescript
// استخدم useSoftDeleteActivity() المخصص — وليس useUpdateActivity
// useSoftDeleteActivity يقبل activityId: string مباشرةً
import { useSoftDeleteActivity } from '@/hooks/useQueryHooks'

const softDelete = useSoftDeleteActivity()

const handleSoftDelete = () => {
  softDelete.mutate(activity.id, {
    onSuccess: () => { toast.success('تم حذف النشاط'); navigate('/activities') },
    onError: (e: any) => toast.error(e?.message || 'فشل الحذف'),
  })
}
```

---

## CSS الإضافي

```css
.linked-operations {
  padding: var(--space-4);
  background: var(--bg-surface-2);
  border-radius: var(--radius-md);
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
}
.linked-op-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: var(--space-2) 0;
  border-bottom: 1px solid var(--border-primary);
}
.linked-op-item:last-child { border-bottom: none; }
```

---

## Acceptance Criteria

- [ ] اسم الموظف ظاهر في تفاصيل النشاط
- [ ] `duration_minutes` يُعرض بصيغة "X دقيقة" إذا كان موجوداً
- [ ] `distance_meters` يُعرض بمتر أو كيلومتر
- [ ] `subject` و `subject_type` يظهران إذا كانا موجودَين
- [ ] روابط العمليات المرتبطة تظهر فقط إذا كانت موجودة
- [ ] زر الحذف ظاهر لمن يملك `ACTIVITIES_UPDATE_OWN` أو `ACTIVITIES_READ_TEAM` أو `ACTIVITIES_READ_ALL`
