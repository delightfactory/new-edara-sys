# Spec: Phase 2 — Task 4 — ActivitiesDashboard (Role-Based)
**الأولوية:** عالي | **الوقت المقدر:** 5-7 ساعات

---

## الهدف

تحويل `src/pages/activities/ActivitiesDashboard.tsx` من لوحة واحدة (30/100) إلى **3 لوحات حسب الدور**.

---

## الملف المستهدف

`src/pages/activities/ActivitiesDashboard.tsx` — **تعديل جوهري**

اقرأ الملف كاملاً أولاً.

---

## منطق التقسيم

```typescript
// في ActivitiesDashboard.tsx
import { useAuthStore } from '@/stores/auth-store' // ✅ الـ store الحقيقي

export default function ActivitiesDashboard() {
  const can = useAuthStore(s => s.can)

  if (can('VISIT_PLANS_READ_TEAM')) return <SupervisorDashboard />
  if (can('TARGETS_READ_ALL')) return <ManagerDashboard />
  return <RepDashboard />
}
```

**ملاحظة:** تحقق من `src/lib/permissions/constants.ts` لمعرفة أسماء الثوابت الصحيحة.

---

## RepDashboard — لوحة المندوب

### المكونات المطلوبة:

#### 1. بطاقة "الزيارة القادمة"
```tsx
<div className="next-visit-card">
  <div className="next-visit-card__label">الزيارة القادمة</div>
  <div className="next-visit-card__customer">{nextItem?.customer_name ?? 'لا توجد زيارات مجدولة'}</div>
  {nextItem && (
    <>
      <div className="next-visit-card__meta">
        <span>الوقت: {nextItem.scheduled_time ?? 'غير محدد'}</span>
      </div>
      <Button onClick={() => navigate(`/activities/new?customerId=${nextItem.customer_id}&visitPlanItemId=${nextItem.id}`)}>
        ابدأ الزيارة ←
      </Button>
    </>
  )}
</div>
```

**البيانات:** `useVisitPlanItems(todayPlanId)` — ابحث عن أول بند بحالة `pending`

#### 2. شريط تقدم اليوم
```tsx
<div className="day-progress">
  <div className="day-progress__label">تقدم اليوم: {completedCount}/{totalCount} زيارة</div>
  <div className="day-progress__bar">
    <div
      className="day-progress__fill"
      style={{ width: `${(completedCount / totalCount) * 100}%` }}
    />
  </div>
</div>
```

#### 3. أهداف الشهر (من TargetProgressWidget الموجود)
```tsx
<div className="section-title">أهدافي هذا الشهر</div>
{myTargets?.slice(0, 3).map(target => (
  <TargetProgressWidget key={target.id} target={target} />
))}
```

**البيانات:**
```typescript
// useTargetStatus يقبل: { scope?, scopeId?, isActive? } — لا يقبل employee_id مباشرة
// TargetScope = 'company' | 'branch' | 'department' | 'individual'
const { data: targetStatuses } = useTargetStatus({
  scope: 'individual',  // ✅ 'individual' (وليس 'employee')
  scopeId: currentEmployee?.id,
  isActive: true,
})
```

#### 4. Callbacks اليوم
```tsx
<div className="callbacks-list">
  <div className="section-title">مكالمات مجدولة اليوم</div>
  {todayCallbacks?.map(item => (
    <div key={item.id} className="callback-item">
      <span>{item.customer_name}</span>
      <span className="callback-time">{item.scheduled_time}</span>
      <a href={`tel:${item.customer_phone}`}>
        <Button variant="ghost" size="sm">اتصل الآن</Button>
      </a>
    </div>
  ))}
  {(!todayCallbacks || todayCallbacks.length === 0) && (
    <p className="empty-hint">لا توجد مكالمات مجدولة اليوم</p>
  )}
</div>
```

---

## SupervisorDashboard — لوحة المشرف

### المكونات المطلوبة:

#### 1. لوحة التنبيهات الحرجة
```tsx
<div className="alerts-panel">
  <div className="alerts-panel__header">
    <span>تنبيهات حرجة</span>
    <Badge variant="danger">{alerts.length}</Badge>
  </div>
  {alerts.map((alert, i) => (
    <div key={i} className={`alert-item alert-item--${alert.severity}`}>
      <span className="alert-icon">{alert.icon}</span>
      <span>{alert.message}</span>
    </div>
  ))}
</div>
```

**منطق التنبيهات (يُحسب client-side من بيانات متاحة):**
```typescript
// مثال على بناء التنبيهات من بيانات الفريق
const alerts = useMemo(() => {
  const result: Alert[] = []
  teamMembers?.forEach(member => {
    if (!member.last_activity_at) return
    const hoursSince = differenceInHours(new Date(), new Date(member.last_activity_at))
    if (hoursSince > 4) {
      result.push({
        severity: 'warning',
        icon: '⚠',
        message: `${member.name} لم يُسجل نشاطاً منذ ${hoursSince} ساعات`,
      })
    }
  })
  return result
}, [teamMembers])
```

#### 2. جدول أداء الفريق
```tsx
<div className="team-table-wrapper">
  <div className="section-title">أداء الفريق اليوم</div>
  <table className="team-table">
    <thead>
      <tr>
        <th>المندوب</th>
        <th>الزيارات</th>
        <th>إنجاز الخطة</th>
        <th>الحالة</th>
      </tr>
    </thead>
    <tbody>
      {teamMembers?.map(member => (
        <tr key={member.id}>
          <td>{member.name}</td>
          <td>{member.today_visits_count ?? 0}</td>
          <td>{member.plan_completed}/{member.plan_total}</td>
          <td>
            <Badge variant={member.status === 'ok' ? 'success' : member.status === 'warning' ? 'warning' : 'danger'}>
              {member.status === 'ok' ? 'جيد' : member.status === 'warning' ? 'يُتابع' : 'خطر'}
            </Badge>
          </td>
        </tr>
      ))}
    </tbody>
  </table>
</div>
```

**البيانات:**
```typescript
// useRepPerformance() موجود بالفعل في useQueryHooks.ts — استخدمه
const { data: repPerformance } = useRepPerformance()
// يُعيد بيانات أداء الفريق — تحقق من شكل البيانات في useQueryHooks.ts سطر 921
```
ادمج بيانات `repPerformance` مع `useHREmployees()` إذا احتجت اسم الموظف.
أضف تعليق `// TODO: confirm repPerformance shape with getRepPerformance service`.

---

## ManagerDashboard — لوحة الإدارة (مبسطة)

هذه اللوحة بسيطة في هذه المرحلة:
```tsx
function ManagerDashboard() {
  return (
    <div className="page-container animate-enter">
      <PageHeader title="لوحة الأنشطة" subtitle="نظرة عامة على الشركة" />
      {/* إعادة استخدام StatCards الموجودة */}
      <div className="stats-grid">
        {/* نفس الـ 4 بطاقات الحالية */}
      </div>
      {/* TODO: Phase 4 — إضافة مقارنة الفروع و KPI */}
    </div>
  )
}
```

---

## هيكل الملف النهائي

```typescript
// src/pages/activities/ActivitiesDashboard.tsx

// 3 دوال فرعية في نفس الملف (ليس ملفات منفصلة إلا إذا تجاوزت 200 سطر)
function RepDashboard() { ... }
function SupervisorDashboard() { ... }
function ManagerDashboard() { ... }

// المكون الرئيسي — router
export default function ActivitiesDashboard() {
  const can = useAuthStore(s => s.can)
  if (can('VISIT_PLANS_READ_TEAM')) return <SupervisorDashboard />
  if (can('TARGETS_READ_ALL')) return <ManagerDashboard />
  return <RepDashboard />
}
```

---

## Acceptance Criteria

- [ ] المندوب يرى بطاقة الزيارة القادمة مع زر "ابدأ الزيارة"
- [ ] المندوب يرى شريط تقدم اليوم
- [ ] المشرف يرى جدول الفريق بدلاً من لوحة المندوب
- [ ] المشرف يرى لوحة التنبيهات (ولو فارغة)
- [ ] لا يوجد error عند عدم وجود بيانات (graceful empty states)
- [ ] الـ routing الحالي `/activities` لا يتغير
