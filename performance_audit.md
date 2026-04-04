# تقرير تدقيق الأداء — EDARA v2
> **مبني على التحقيق الكامل للكود + وثائق Supabase الرسمية**

---

## الأسباب الجذرية — مُثبتة بالدليل

### 🔴 السبب الأول: `auth.uid()` مُستدعاة بدون `SELECT` wrapper في كل سياسات RLS

#### الدليل من وثائق Supabase الرسمية:
> *"Wrapping the function causes an **initPlan** to be run by the Postgres optimizer, which allows it to **'cache' the results per-statement**, rather than calling the function on **each row**."*
> — [Supabase RLS Performance Guide](https://supabase.com/docs/guides/database/postgres/row-level-security#call-functions-with-select)

#### الكود الحالي في نظامنا (❌ مخالف للمعيار):
```sql
-- ❌ السطور الفعلية في سياساتنا:
check_permission(auth.uid(), 'inventory.read')  -- 03e_rls_hardening.sql, سطор متعددة
created_by = auth.uid()                          -- 03e_rls_hardening.sql
employee_id = auth.uid()                         -- 03e_rls_hardening.sql
```

#### ما يحدث فعلياً:
| النهج | تقييم `auth.uid()` | عند قراءة 100 صف |
|--------|---------------------|------------------|
| `auth.uid()` (الحالي) | **مرة لكل صف** | 100 استدعاء لـ JWT parsing |
| `(select auth.uid())` (الصحيح) | **مرة واحدة للاستعلام كله** | 1 استدعاء لـ JWT parsing |

#### حجم المشكلة:
```
21_activities_module_mvp.sql    → 177 سطر بـ auth.uid() غير محمي
02_master_data.sql              → 67 سطر
21b_activities_rls_engine.sql   → 55 سطر
03_financial_infrastructure.sql → 44 سطر
03e_rls_hardening.sql           → 41 سطر
03h_extreme_performance.sql     → 40 سطر
... إجمالي > 800 استدعاء مكشوف
```

**التأثير:**
- كل ضغطة زر تُطلق RPC → تُشغّل SELECT على جداول → كل صف يُقيّم `auth.uid()` مستقلاً
- عند تسجيل الدخول: `get_my_profile()` تجلب بيانات من جداول متعددة بـ RLS → مئات استدعاءات JWT

---

### 🔴 السبب الثاني: `check_permission()` تُستدعى مباشرة في RLS بدون `SELECT` wrapper

#### الدليل من وثائق Supabase:
> *"This method works well for JWT functions like `auth.uid()` and `auth.jwt()` **as well as security definer Functions**."*

#### الكود الحالي (❌ مخالف):
```sql
-- ❌ check_permission تُستدعى مباشرة
USING ( check_permission(auth.uid(), 'inventory.read') )

-- ✅ الصحيح حسب الوثائق
USING ( (SELECT check_permission((SELECT auth.uid()), 'inventory.read')) )
```

**التأثير:** `check_permission()` تُجري **2 subqueries** (user_permission_overrides + role_permissions JOIN user_roles) لكل صف في كل استعلام محمي بـ RLS.

---

### 🔴 السبب الثالث: الـ `loadSession` تُجري طلبين متسلسلين عند كل تسجيل دخول

#### الكود الفعلي في `auth.ts`:
```typescript
// طلب 1: التحقق من وجود مستخدم
const { data: { user } } = await supabase.auth.getUser()

// طلب 2 (متسلسل — ينتظر انتهاء الأول):
const { data } = await supabase.rpc('get_my_profile').single()

// طلب 3 (fire and forget — لكن يُضيف load):
supabase.from('profiles').update({ last_login_at: ... })
```

**المشكلة:** الطلبان الأول والثاني **تسلسليان** — كل واحد ينتظر انتهاء السابق.
الصحيح: `supabase.auth.getUser()` غير ضروري إذا كانت الجلسة موجودة — `get_my_profile()` تفشل إذا لم يكن المستخدم مسجلاً دخوله لأنها تستخدم `auth.uid()`.

---

### 🟡 السبب الرابع: `get_my_profile()` تستدعي `get_user_permissions()` التي تجري subquery مزدوجة

من `03j_auth_guard.sql` سطر 20-34:
```sql
-- ❌ Two separate queries for the same user
RETURN QUERY SELECT permission FROM user_permission_overrides WHERE user_id = p_user_id...
RETURN QUERY SELECT DISTINCT rp.permission FROM role_permissions rp
  JOIN user_roles ur ON ur.role_id = ur.role_id
  WHERE ur.user_id = p_user_id
    AND rp.permission NOT IN (
      SELECT upo2.permission FROM user_permission_overrides upo2  -- ← subquery مُكررة
      WHERE upo2.user_id = p_user_id ...
    )
```

يمكن دمجهما في استعلام واحد بـ CTE.

---

### 🟡 السبب الخامس: سياسات RLS بدون `TO authenticated`

#### الدليل من وثائق Supabase:
> *"Always use the Role inside your policies, specified by the TO operator... This prevents the policy from running for any anon users, since the execution stops at the `to authenticated` step."*

#### الكود الحالي (❌):
```sql
-- ❌ تُشغَّل لكل المستخدمين بما فيهم الـ anon
CREATE POLICY "expenses_read" ON expenses FOR SELECT
USING ( created_by = auth.uid() OR check_permission(auth.uid(), 'finance.expenses.read_all') );

-- ✅ الصحيح
CREATE POLICY "expenses_read" ON expenses FOR SELECT
TO authenticated
USING ( (SELECT auth.uid()) = created_by OR (SELECT check_permission((SELECT auth.uid()), 'finance.expenses.read_all')) );
```

---

## الإصلاح الخطة — بالأولوية

| الأولوية | الإصلاح | التأثير المتوقع | التعقيد |
|----------|---------|-----------------|---------|
| 🔴 1 | `(select auth.uid())` في كل سياسات RLS | **تخفيض 80%+ وقت الاستعلام** | migration |
| 🔴 2 | `(select check_permission(...))` في كل سياسات | **تخفيض 60%+ initPlan cost** | migration |
| 🔴 3 | إضافة `TO authenticated` لكل السياسات | **توقف تقييم anon requests** | migration |
| 🟡 4 | دمج طلبي `loadSession` في طلب واحد | تسجيل دخول أسرع | frontend |
| 🟡 5 | تحسين `get_user_permissions()` بـ CTE | جلب بروفايل أسرع | migration |

---

## ما هو ممكن التطبيق الآن؟

> [!IMPORTANT]
> الإصلاح الجذري الحقيقي هو **Migration يُعيد كتابة سياسات RLS** لتشمل:
> 1. `(select auth.uid())` بدلاً من `auth.uid()`
> 2. `(select check_permission(...))` بدلاً من `check_permission(...)`
> 3. `TO authenticated` على كل السياسات
>
> هذا **يمس 94 ملف migration** ويتطلب migration شامل جديد.

> [!WARNING]
> تطبيق هذا الإصلاح يتطلب:
> - مراجعة كل سياسة حالية
> - اختبار عدم كسر أي منطق RLS موجود
> - تطبيق Migration في بيئة staging أولاً

---

## الإصلاحات المطبقة فعلاً (الجلسة الحالية)

| الإصلاح | الملف | التأثير |
|---------|-------|---------|
| ✅ تقليل Realtime subscriptions من 37 → 8 جداول | `GlobalRealtimeManager.tsx` | تقليل WebSocket traffic |
| ✅ رفع `staleTime` من 30s → 120s مع `gcTime` | `App.tsx` | تقليل refetch غير ضروري |
| ✅ `refetchOnReconnect: false` | `App.tsx` | منع cascade refetch |
| ✅ `ANALYZE` شامل لكل الجداول الجديدة | `64_performance_analyze_refresh.sql` | تحسين query planner |
| ⏳ `(select auth.uid())` في RLS | **يحتاج Migration 65** | الإصلاح الجذري الأكبر |
