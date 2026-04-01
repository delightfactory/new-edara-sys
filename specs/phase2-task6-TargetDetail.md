# Spec: Phase 2 — Task 6 — TargetDetail (سجل التعديلات + Forecast)
**الأولوية:** عالي | **الوقت المقدر:** 3 ساعات

---

## الهدف

إضافة قسمَين لـ `src/pages/activities/TargetDetail.tsx`:
1. **سجل التعديلات** — من عدّل الهدف، متى، وما الذي تغير
2. **توقع نهاية الفترة (Forecast)** — بناءً على معدل الإنجاز الحالي

الدرجة الحالية: 45/100.

---

## الملف المستهدف

`src/pages/activities/TargetDetail.tsx` — **تعديل (إضافة أقسام)**

اقرأ الملف كاملاً أولاً.

---

## القسم 1: سجل التعديلات

### مصدر البيانات

`getTarget()` في `src/lib/services/activities.ts` يُعيد **مباشرةً** `adjustments: TargetAdjustment[]` ضمن الـ response — لا حاجة لـ query منفصل.

```typescript
// useTarget(id) يُعيد: Target & { progress_history: TargetProgress[], adjustments: TargetAdjustment[] }
// استخدم target.adjustments مباشرةً من hook الموجود أصلاً في الملف
const { data: target } = useTarget(targetId)
const adjustments = target?.adjustments ?? []
```

**لا تُنشئ query inline جديدة — استخدم بيانات `useTarget` الموجودة بالفعل.**

### UI المطلوب

```tsx
<div className="adjustments-log">
  <div className="section-title">سجل التعديلات</div>

  {(!adjustments || adjustments.length === 0) ? (
    <p className="empty-hint">لا توجد تعديلات مسجلة</p>
  ) : (
    <div className="adjustments-list">
      {adjustments.map((adj, i) => (
        <div key={i} className="adjustment-item">
          <div className="adjustment-item__header">
            <span className="adjustment-item__who">
              {adj.adjusted_by_profile?.full_name ?? 'غير معروف'}
            </span>
            <span className="adjustment-item__when">
              {format(new Date(adj.adjusted_at), 'yyyy/MM/dd HH:mm')}
            </span>
          </div>
          <div className="adjustment-item__change">
            <span className="old-value">من: {adj.old_value?.toLocaleString()}</span>
            <span className="arrow">←</span>
            <span className="new-value">إلى: {adj.new_value?.toLocaleString()}</span>
          </div>
          {adj.reason && (
            <div className="adjustment-item__reason">السبب: {adj.reason}</div>
          )}
        </div>
      ))}
    </div>
  )}
</div>
```

---

## القسم 2: توقع نهاية الفترة (Forecast)

### منطق الحساب

```typescript
import { differenceInDays } from 'date-fns'

const forecastValue = useMemo(() => {
  if (!target?.current_value || !target?.target_value) return null
  if (!target?.period_start || !target?.period_end) return null

  const totalDays = differenceInDays(new Date(target.period_end), new Date(target.period_start))
  const elapsedDays = differenceInDays(new Date(), new Date(target.period_start))

  if (elapsedDays <= 0 || totalDays <= 0) return null

  const dailyRate = target.current_value / elapsedDays
  const forecast = dailyRate * totalDays

  return {
    value: Math.round(forecast),
    percentage: Math.round((forecast / target.target_value) * 100),
    remainingDays: totalDays - elapsedDays,
  }
}, [target])
```

### UI المطلوب

```tsx
{forecastValue && (
  <div className="forecast-card">
    <div className="forecast-card__label">التوقع بنهاية الفترة</div>
    <div className="forecast-card__value">
      {forecastValue.value.toLocaleString('ar-EG')}
      <span className="forecast-pct"> ({forecastValue.percentage}%)</span>
    </div>
    <div className="forecast-card__meta">
      {forecastValue.remainingDays > 0
        ? `${forecastValue.remainingDays} يوم متبقٍ`
        : 'انتهت الفترة'
      }
    </div>
    <div
      className="forecast-bar"
      title={`${forecastValue.percentage}%`}
    >
      <div
        className="forecast-bar__fill"
        style={{
          width: `${Math.min(forecastValue.percentage, 100)}%`,
          background: forecastValue.percentage >= 100
            ? 'var(--color-success)'
            : forecastValue.percentage >= 70
            ? 'var(--color-warning)'
            : 'var(--color-danger)',
        }}
      />
    </div>
  </div>
)}
```

---

## CSS

```css
.adjustments-log {
  margin-top: var(--space-6);
}
.adjustments-list {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
}
.adjustment-item {
  padding: var(--space-3);
  background: var(--bg-surface-2);
  border-radius: var(--radius-md);
  border-right: 3px solid var(--border-primary);
}
.adjustment-item__header {
  display: flex;
  justify-content: space-between;
  margin-bottom: var(--space-1);
}
.adjustment-item__who { font-weight: 600; font-size: var(--text-sm); }
.adjustment-item__when { color: var(--text-muted); font-size: var(--text-xs); }
.adjustment-item__change {
  display: flex;
  gap: var(--space-2);
  align-items: center;
  font-size: var(--text-sm);
}
.old-value { color: var(--color-danger); }
.new-value { color: var(--color-success); }
.adjustment-item__reason {
  margin-top: var(--space-1);
  font-size: var(--text-xs);
  color: var(--text-muted);
}
.forecast-card {
  padding: var(--space-4);
  background: var(--bg-surface-2);
  border-radius: var(--radius-md);
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
}
.forecast-card__label { color: var(--text-muted); font-size: var(--text-sm); }
.forecast-card__value { font-size: var(--text-xl); font-weight: 700; }
.forecast-pct { font-size: var(--text-sm); color: var(--text-muted); }
.forecast-card__meta { font-size: var(--text-sm); color: var(--text-muted); }
.forecast-bar {
  height: 8px;
  background: var(--border-primary);
  border-radius: var(--radius-full);
  overflow: hidden;
}
.forecast-bar__fill {
  height: 100%;
  border-radius: var(--radius-full);
  transition: width var(--transition-slow);
}
.empty-hint {
  color: var(--text-muted);
  font-size: var(--text-sm);
  padding: var(--space-3) 0;
}
```

---

## Acceptance Criteria

- [ ] قسم "سجل التعديلات" يظهر في صفحة التفاصيل
- [ ] إذا لم توجد تعديلات، يظهر "لا توجد تعديلات مسجلة"
- [ ] كل تعديل يُظهر: من عدّل، متى، القيمة القديمة، الجديدة، والسبب
- [ ] بطاقة Forecast تظهر إذا كانت بيانات الفترة والقيم الحالية متاحة
- [ ] شريط Forecast يتلون: أخضر ≥100%، أصفر ≥70%، أحمر <70%
- [ ] لا error إذا كانت البيانات غير متاحة (graceful null handling)
