# خطة التنفيذ المتكاملة — EDARA Launch Readiness
**التاريخ:** 2026-04-03  
**المرجع:** full-engineering-review-report-2026-04-03.md + edara-final-engineering-audit-2026-04-03.md  
**الحالة:** خطة تنفيذ معتمدة جاهزة للتطوير

---

## أولاً: مبادئ التنفيذ العامة

كل مهمة في هذه الخطة تلتزم بالقواعد التالية:

1. **الحفاظ على العقود الخارجية** — لا يتغير شكل response من hooks أو services إلا بقرار صريح
2. **استبدال الداخل دون كسر الخارج** — الـ implementation internals تتغير، الـ interface للمستهلكين يبقى
3. **لا regression بلا test** — كل إصلاح يرافقه test case صريح يمنع العودة
4. **الأمان أولاً** — Sprint 1 لا يبدأ Sprint 2 إلا بعد merge وتوثيق Sprint 1
5. **الإشارة الصريحة للمخاطر** — كل مهمة تذكر ما يمكن أن يكسر عند التنفيذ وكيف يُتجنب

---

## Sprint 0 — Pre-Sprint Verification (يوم واحد قبل البدء)
**الهدف:** تحقق من النقاط غير المؤكدة بالكامل قبل الشروع في الإصلاحات

### S0-T1 — FAB Audit: هل يغطي desktop-only-btn pages؟
- **الملفات:** `src/components/layout/FAB.tsx`، كل صفحة تستخدم `desktop-only-btn`
- **المطلوب:**
  - قراءة FAB component كاملاً
  - بناء جدول: صفحة → هل FAB موجود → هل يغطي الـ create action
  - تحديد الصفحات التي create button مخفي فيها دون بديل FAB
- **الناتج:** قائمة dead-end pages مؤكدة لإضافتها لـ Sprint 4

### S0-T2 — Realtime Matrix: inventory كامل
- **الملفات:** `src/components/shared/GlobalRealtimeManager.tsx`، كل hooks files
- **المطلوب:**
  - استخراج كل query keys المستخدمة في `useQueryHooks.ts`
  - مقارنتها بـ `TABLE_QUERY_MAP` الحالي
  - توثيق الـ gaps في جدول: جدول → query key المفترض → موجود أم لا
- **الناتج:** قائمة mappings ناقصة جاهزة لـ Sprint 3

### S0-T3 — CORS Full Audit
- **الملفات:** كل edge functions (5 ملفات)
- **المطلوب:** تأكيد `Access-Control-Allow-Origin: *` في كل function + قراءة vercel.json
- **الناتج:** قرار مؤكد بشأن CORS fix scope

### S0-T4 — Payroll Orchestration Exact Path
- **الملفات:** `src/hooks/useQueryHooks.ts`، `src/lib/services/hr.ts`
- **المطلوب:** تحديد الـ hook والـ mutation المسؤولة عن payroll calculation loop
- **الناتج:** تعريف دقيق للمشكلة في Sprint 3

---

## Sprint 1 — الأمان وثبات الجلسة (P0 + P1 Security)
**المدة المقدرة:** 4-5 أيام عمل  
**الأولوية:** قصوى — لا يجوز الإطلاق قبل إغلاق هذا الـ sprint  
**العقد:** لا يتغير أي response shape خارجي في هذا الـ sprint

---

### S1-T1 — إصلاح JWT forgery في dispatch-notification
**المرجع:** EA-SEC-01 / F-SEC-01  
**الأولوية:** P0 — Release Blocker  
**الملف:** `supabase/functions/dispatch-notification/index.ts`

**المشكلة المؤكدة:**
```typescript
// الكود الحالي — خطر
function getJWTRole(token: string): string | null {
  const base64 = token.split('.')[1]?.replace(/-/g, '+').replace(/_/g, '/')
  const payload = JSON.parse(atob(base64))
  return payload.role ?? null  // ← قراءة claim بدون verification للـ signature
}
const isInternalCall = getJWTRole(bearerToken) === 'service_role'
```

**الحل المطلوب:**
استبدال منطق التمييز بين internal/external calls بـ shared secret mechanism:

1. إضافة `INTERNAL_DISPATCH_SECRET` إلى Supabase Vault (project secrets)
2. استبدال `getJWTRole` بـ helper يتحقق من header مخصص:
   ```
   X-Internal-Secret: <value-from-vault>
   ```
3. للـ internal callers (DB triggers): تمرير الـ secret في header
4. للـ browser callers: المسار الخارجي كما هو تماماً

**خطوات التنفيذ:**
1. إضافة `INTERNAL_DISPATCH_SECRET` في Supabase Dashboard → Settings → Secrets
2. تحديث الـ function لقراءة الـ secret من `Deno.env.get('INTERNAL_DISPATCH_SECRET')`
3. استبدال `isInternalCall` check:
   ```typescript
   const internalSecret = Deno.env.get('INTERNAL_DISPATCH_SECRET')
   const providedSecret = req.headers.get('x-internal-secret')
   const isInternalCall = !!internalSecret && providedSecret === internalSecret
   ```
4. تحديث أي DB triggers أو cron jobs تستدعي هذه الـ function لتمرير الـ secret header
5. إزالة `getJWTRole` function بالكامل

**ما يجب عدم تغييره:**
- شكل request body (`event_key`, `user_ids`, `variables`, etc.)
- شكل response `{ dispatched, inApp, push, errors }`
- منطق الـ template rendering وquiet hours

**مخاطر التنفيذ:**
- إذا وُجدت internal callers غير موثقة → تفشل بعد التغيير
- **الحل:** تشغيل function في logging mode أولاً: log كل `isInternalCall=true` request لمدة 24 ساعة قبل التطبيق، للتأكد من معرفة كل الـ callers

**اختبارات مطلوبة:**
- `[ ]` forged JWT مع `{"role":"service_role"}` في payload → HTTP 401 أو 403
- `[ ]` طلب بدون `x-internal-secret` → external path فقط
- `[ ]` طلب مع `x-internal-secret` صحيح → internal path يعمل
- `[ ]` browser user مصادق عليه بدون secret → external path يعمل

---

### S1-T2 — إضافة Authorization لـ browser callers في dispatch-notification
**المرجع:** EA-SEC-02 / F-SEC-02  
**الأولوية:** P1  
**الملف:** `supabase/functions/dispatch-notification/index.ts`

**المشكلة المؤكدة:**
المسار الخارجي يتحقق من هوية المستخدم فقط، دون التحقق من صلاحيته لإرسال الإشعارات.

**الحل المطلوب:**
إضافة `check_permission` call للـ browser callers مباشرة بعد `auth.getUser()`:

```typescript
// بعد التحقق من هوية المستخدم
const { data: hasPermission } = await adminClient.rpc('check_permission', {
  p_user_id: caller.id,
  p_permission: 'notifications.dispatch',
})
if (!hasPermission) {
  return Response.json({ error: 'لا تملك صلاحية إرسال الإشعارات' }, { status: 403, headers: corsHeaders })
}
```

**ملاحظة مهمة:**
قبل تطبيق هذا الإصلاح، يجب التحقق من:
- هل هناك browser callers حاليون يستخدمون هذه الـ function مباشرة؟
- إذا نعم: منح permission `notifications.dispatch` للأدوار المناسبة أولاً قبل deploy

**خطوات التنفيذ:**
1. التحقق من وجود browser callers في الكود (grep لـ `dispatch-notification`)
2. إضافة `notifications.dispatch` لملف constants.ts إذا لم يكن موجوداً
3. منح هذا الـ permission للأدوار الإدارية المناسبة في DB
4. إضافة الـ check في الـ function

**اختبارات مطلوبة:**
- `[ ]` user مصادق عليه بدون permission → HTTP 403
- `[ ]` user مصادق عليه مع `notifications.dispatch` → يكمل الطلب
- `[ ]` الـ internal path (S1-T1) لا يتأثر بهذا الـ check

---

### S1-T3 — إصلاح Service Worker: إيقاف caching للـ authenticated API
**المرجع:** EA-SEC-03 / F-SEC-03  
**الأولوية:** P1  
**الملف:** `src/sw.ts`

**المشكلة المؤكدة:**
```typescript
// الكود الحالي — خطر على الأجهزة المشتركة
registerRoute(
  ({ url }) => url.hostname.includes('supabase.co'),
  new NetworkFirst({
    cacheName: 'supabase-api-v1',
    maxAgeSeconds: 60 * 60,  // ساعة كاملة
  })
)
```

**الحل المطلوب:**
إزالة هذا الـ route بالكامل من Workbox — الـ Supabase client يتعامل مع الـ network نفسه.

```typescript
// بعد الإصلاح: حذف الـ registerRoute الخاص بـ supabase.co
// الـ static assets caching تبقى كما هي
```

**ما يجب عدم تغييره:**
- Google Fonts caching route
- Static assets caching route
- Navigation/pages caching route
- Push notification handlers

**مخاطر التنفيذ:**
- فقدان offline fallback لبيانات الـ API (وهو السلوك الصحيح لـ ERP)
- بعض المستخدمين قد يلاحظون أن الـ app لا يعمل offline (نعم، هذا صحيح ومقبول)

**خطوات التنفيذ:**
1. حذف `registerRoute` الخاص بـ supabase.co
2. التأكد من حذف `ExpirationPlugin` والـ `CacheableResponsePlugin` المرتبطين به
3. إضافة تعليق توضيحي يشرح لماذا لا يُكاش الـ API
4. اختبار الشاشات الحرجة في حالة offline للتأكد من وجود empty/error states مناسبة

**اختبارات مطلوبة:**
- `[ ]` login → logout → login على نفس الجهاز → لا تظهر بيانات الـ user الأول
- `[ ]` offline → الـ app يعرض error state مناسب بدل بيانات stale
- `[ ]` الـ static assets تعمل offline كما كانت

---

### S1-T4 — إصلاح loadSession: فصل transient errors عن sign-out
**المرجع:** EA-REL-01 / F-SEC-04  
**الأولوية:** P1  
**الملف:** `src/lib/services/auth.ts`

**المشكلة المؤكدة:**
```typescript
// الكود الحالي — يخلط بين حالتين مختلفتين
if (error || !data || data.status !== 'active') {
  await supabase.auth.signOut()  // ← ينفذ حتى عند network timeout
  store.reset()
  return
}
```

**الحل المطلوب:**
فصل الحالات:

```typescript
// الحالة 1: خطأ في transport أو RPC
if (error) {
  // لا sign-out — الجلسة صحيحة، المشكلة transient
  // أبقِ loading=false وأظهر degraded state
  store.setLoading(false)
  store.setInitialized(true)
  // optionally: store.setBootstrapError(true) لعرض retry UI
  return
}

// الحالة 2: لا بيانات — غير متوقع مع user موجود
if (!data) {
  // لا sign-out مباشر — انتظر retry أو اعرض error
  store.setLoading(false)
  store.setInitialized(true)
  return
}

// الحالة 3: الحساب معطل صراحةً
if (data.status !== 'active') {
  await supabase.auth.signOut()  // ← هذه الحالة الوحيدة التي تستوجب sign-out
  store.reset()
  store.setInitialized(true)
  return
}
```

**تغييرات في AuthStore:**
- إضافة `bootstrapError: boolean` لـ store إذا احتاجت الـ UI لعرض retry button
- هذا اختياري في المرحلة الأولى — يمكن الاكتفاء بـ empty state

**ما يجب عدم تغييره:**
- `store.reset()` عند `data.status !== 'active'` — هذا صحيح
- `store.setInitialized(true)` في `finally` — هذا صحيح

**اختبارات مطلوبة:**
- `[ ]` `get_my_profile` يرجع network error → user لا يُخرج من الجلسة
- `[ ]` `get_my_profile` يرجع RPC error (502) → user لا يُخرج من الجلسة
- `[ ]` `data.status === 'inactive'` → user يُخرج من الجلسة
- `[ ]` `data.status === 'suspended'` → user يُخرج من الجلسة
- `[ ]` جلسة ناجحة كاملة → لا تغيير في السلوك الحالي

---

### S1-T5 — إضافة Security Headers
**المرجع:** NV-SEC-01  
**الأولوية:** P1 (مؤكد من الكود)  
**الملفات:** `vercel.json`، كل edge functions

**خطوات التنفيذ:**

**vercel.json:**
```json
{
  "headers": [
    {
      "source": "/(.*)",
      "headers": [
        { "key": "X-Content-Type-Options", "value": "nosniff" },
        { "key": "X-Frame-Options", "value": "DENY" },
        { "key": "Referrer-Policy", "value": "strict-origin-when-cross-origin" },
        { "key": "Strict-Transport-Security", "value": "max-age=63072000; includeSubDomains" },
        { "key": "Permissions-Policy", "value": "camera=(), microphone=(), geolocation=(self)" },
        { "key": "Content-Security-Policy", "value": "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; img-src 'self' data: https:; connect-src 'self' https://*.supabase.co wss://*.supabase.co; font-src 'self' https://fonts.gstatic.com; frame-ancestors 'none'" }
      ]
    }
  ]
}
```

**ملاحظة:** الـ `unsafe-inline` في script/style مطلوب بسبب inline styles الموجودة — يُحسَّن لاحقاً في Sprint 4

**Edge Functions — CORS:**
تضييق CORS من `*` إلى domain المحدد للـ app (بعد التأكد من domain الـ production):
```typescript
const corsHeaders = {
  'Access-Control-Allow-Origin': 'https://your-production-domain.vercel.app',
  // ...
}
```
**انتبه:** في بيئة التطوير يحتاج هذا لـ environment variable للـ origin

**اختبارات مطلوبة:**
- `[ ]` HTTP response headers تحتوي على CSP وHSTS
- `[ ]` iframe embedding مرفوض
- `[ ]` CORS يرفض طلبات من origins غير معروفة

---

### Sprint 1 — Checklist الإغلاق

قبل الانتقال لـ Sprint 2، يجب التحقق من كل النقاط:

- `[ ]` S1-T1: forged JWT → HTTP 401/403 مؤكد بالاختبار
- `[ ]` S1-T1: internal callers تعمل بعد التغيير
- `[ ]` S1-T2: browser user بدون permission → 403
- `[ ]` S1-T3: authenticated API responses لا تُكاش
- `[ ]` S1-T3: offline state يعرض error مناسب
- `[ ]` S1-T4: transient RPC error لا يخرج المستخدم
- `[ ]` S1-T4: inactive account يخرج المستخدم
- `[ ]` S1-T5: security headers ظاهرة في responses
- `[ ]` smoke test: login → browse → logout → re-login يعمل بدون مشاكل
- `[ ]` smoke test: إرسال إشعار من admin يعمل

---

## Sprint 2 — صحة البيانات وتكامل الحالة (P1/P2 Correctness)
**المدة المقدرة:** 5-6 أيام عمل  
**الأولوية:** عالية جداً  
**العقد:** نفس response shapes للـ hooks والـ services — فقط internals تتغير

---

### S2-T1 — إصلاح getActivities: نقل typeCategory filter إلى DB
**المرجع:** EA-SCL-01 / F-SCALE-01  
**الأولوية:** P1  
**الملف:** `src/lib/services/activities.ts`

**المشكلة المؤكدة:**
```typescript
.range(from, to)           // ← pagination أولاً
// ...
rows = rows.filter(a => (a as any).type?.category === cat)  // ← filter بعدها
return { data: rows, count: count ?? 0, ... }  // ← count خاطئ
```

**الحل المطلوب:**
الـ PostgREST يدعم الفلترة على الـ foreign key table باستخدام `.eq()` على الـ joined relation.
الحل الأمثل: استخدام `!inner` join مع filter قبل `range()`:

```typescript
// قبل .range()
if (params?.typeCategory) {
  // استخدام !inner join لضمان أن الفلترة تؤثر على count
  // في select: 'type:activity_types!inner(id,name,code,category,icon)'
  q = q.eq('type.category', params.typeCategory)
}
// ثم range()
```

**خطوات التنفيذ التفصيلية:**
1. تعديل `getActivities` select string ليستخدم `!inner` بدل join عادي عند وجود typeCategory:
   ```typescript
   const typeSelect = params?.typeCategory
     ? 'type:activity_types!inner(id,name,code,category,icon)'
     : 'type:activity_types(id,name,code,category,icon)'
   ```
2. إضافة filter قبل `.range()`:
   ```typescript
   if (params?.typeCategory) q = q.eq('activity_types.category', params.typeCategory)
   ```
3. حذف الـ client-side filter بعد الجلب بالكامل

**بديل أكثر أماناً (إذا لم يعمل `!inner`):**
إنشاء RPC في DB:
```sql
CREATE OR REPLACE FUNCTION get_activities_paginated(
  p_employee_id uuid,
  p_type_category text,
  p_page int,
  p_page_size int,
  ...
) RETURNS TABLE(...) AS $$
  SELECT a.*, ... 
  FROM activities a
  JOIN activity_types at ON a.type_id = at.id
  WHERE (p_type_category IS NULL OR at.category = p_type_category)
  ...
  LIMIT p_page_size OFFSET (p_page - 1) * p_page_size
$$;
```

**ما يجب عدم تغييره:**
- شكل الـ return value: `{ data, count, page, pageSize, totalPages }`
- نوع `Activity` في data
- كل الـ params الأخرى (employeeId, dateFrom, dateTo, etc.)

**اختبارات مطلوبة:**
- `[ ]` `getActivities({ typeCategory: 'visit' })` → كل عناصر data من نوع visit
- `[ ]` `getActivities({ typeCategory: 'visit' })` → count يعكس عدد visits فقط
- `[ ]` `getActivities({ typeCategory: 'call', page: 2 })` → صفحة 2 من calls فقط (لا visits)
- `[ ]` `getActivities()` بدون filter → لا تغيير في السلوك

---

### S2-T2 — إصلاح getVisitPlans: نقل branchId filter إلى DB
**المرجع:** EA-SCL-02 / F-SCALE-02  
**الأولوية:** P1  
**الملف:** `src/lib/services/activities.ts`

**المشكلة المؤكدة:**
```typescript
const { data, error, count } = await q  // ← جلب بدون branch filter
let rows = (data ?? []) as VisitPlan[]
if (params?.branchId) {
  rows = rows.filter(p => (p as any).employee?.branch_id === params.branchId)  // ← بعد range
}
```

**الحل المطلوب:**
الخيار المفضل هو RPC لأن الـ join على `hr_employees` أكثر تعقيداً:

**خيار 1 — DB View:**
```sql
CREATE OR REPLACE VIEW visit_plans_with_branch AS
SELECT vp.*, e.branch_id as employee_branch_id
FROM visit_plans vp
LEFT JOIN hr_employees e ON vp.employee_id = e.id;
```
ثم query على الـ view مع `.eq('employee_branch_id', branchId)` قبل `range()`

**خيار 2 — مباشرة في PostgREST (يحتاج اختبار):**
```typescript
// في select: 'employee:hr_employees!inner(id, full_name, branch_id)'
// ثم قبل range():
if (params?.branchId) q = q.eq('hr_employees.branch_id', params.branchId)
```

**خطوات التنفيذ:**
1. اختبار خيار 2 في Supabase Studio أولاً
2. إذا نجح → تطبيقه مباشرة
3. إذا لم ينجح → إنشاء view أو RPC

**ما يجب عدم تغييره:**
- شكل `{ data, count, page, pageSize, totalPages }`
- نوع `VisitPlan` في data (بما فيه `employee.branch_id` للـ UI المرتبطة)

**اختبارات مطلوبة:**
- `[ ]` `getVisitPlans({ branchId: 'X' })` → كل plans لموظفي فرع X فقط
- `[ ]` count يعكس plans فرع X فقط
- `[ ]` `getVisitPlans()` بدون filter → لا تغيير

---

### S2-T3 — إصلاح getCallPlans: نقل branchId filter إلى DB
**المرجع:** EA-SCL-03 / F-SCALE-03  
**الأولوية:** P1  
**الملف:** `src/lib/services/activities.ts` (line ~503)

**الحل:** نفس النهج تماماً الذي اتُبع في S2-T2 — توحيد الحل وإعادة استخدامه.

**خطوات التنفيذ:**
1. تطبيق نفس حل S2-T2 على `getCallPlans()`
2. التأكد من أن الـ select string يستخدم نفس join pattern

**اختبارات مطلوبة:**
- `[ ]` نفس اختبارات S2-T2 مطبقة على call plans

---

### S2-T4 — إصلاح getUsers: نقل role filter إلى DB
**المرجع:** EA-SCL-04 / F-SCALE-04  
**الأولوية:** P2  
**الملف:** `src/lib/services/users.ts`

**المشكلة المؤكدة:**
```typescript
const { data: profiles, error, count } = await query.range(from, to)
// ...
if (params?.role) {
  users = users.filter(u =>
    u.user_roles?.some(ur => ur.role?.name === params.role)
  )
}
return { data: users, count: count || 0, ... }  // ← count خاطئ
```

**الحل المطلوب:**
إنشاء RPC في DB:
```sql
CREATE OR REPLACE FUNCTION get_users_paginated(
  p_search text,
  p_status text,
  p_role_name text,
  p_page int,
  p_page_size int
) RETURNS TABLE(
  profile jsonb,
  total_count bigint
) AS $$
  ...
$$;
```

أو تعديل query لاستخدام subquery:
```typescript
// إذا كان role filter مطلوباً:
// SELECT profiles.* FROM profiles
// WHERE id IN (
//   SELECT user_id FROM user_roles ur
//   JOIN roles r ON ur.role_id = r.id
//   WHERE r.name = p_role AND ur.is_active = true
// )
// هذا يدمج filter في DB قبل pagination
```

**اختبارات مطلوبة:**
- `[ ]` `getUsers({ role: 'admin' })` → كل النتائج admins
- `[ ]` count يعكس admin users فقط
- `[ ]` pagination على role-filtered results صحيحة

---

### S2-T5 — إصلاح create-user: atomicity عند فشل role assignment
**المرجع:** EA-DAT-01 / F-DATA-01  
**الأولوية:** P2  
**الملف:** `supabase/functions/create-user/index.ts`

**المشكلة المؤكدة:**
```typescript
const { error: rolesErr } = await adminClient.from('user_roles').insert(...)
if (rolesErr) {
  console.error('Role assignment error:', rolesErr)
  // ← لا يوقف التنفيذ — يكمل ويرجع 201
}
return Response.json({ user_id: newUserId }, { status: 201 })
```

**الحل المطلوب:**
عند فشل role assignment → delete المستخدم وأرجع error:

```typescript
const { error: rolesErr } = await adminClient.from('user_roles').insert(...)
if (rolesErr) {
  console.error('Role assignment error:', rolesErr)
  // Compensate: delete the created user
  await adminClient.auth.admin.deleteUser(newUserId).catch(e => {
    console.error('Failed to cleanup user after role assignment error:', e)
  })
  return Response.json(
    { error: 'فشل تعيين الأدوار — لم يتم إنشاء المستخدم', code: 'ROLE_ASSIGNMENT_FAILED' },
    { status: 500, headers: corsHeaders }
  )
}
```

**ملاحظة:** نفس pattern الـ grade-check compensation (lines 113-119) موجود وصحيح — نعيد استخدامه.

**ما يجب عدم تغييره:**
- الـ response shape للـ happy path: `{ user_id: newUserId }` مع 201
- كل خطوات الـ validation الحالية

**اختبارات مطلوبة:**
- `[ ]` role assignment فاشل → HTTP 500 مع `ROLE_ASSIGNMENT_FAILED`
- `[ ]` role assignment فاشل → `auth.users` لا يحتوي على المستخدم الجديد
- `[ ]` role assignment ناجح → HTTP 201 مع user_id

---

### S2-T6 — إصلاح Archive Mutation: unread count decrement مرة واحدة فقط
**المرجع:** EA-DAT-02 / F-DATA-02  
**الأولوية:** P2  
**الملف:** `src/hooks/useNotificationQueries.ts`

**المشكلة المؤكدة:**
في `useArchiveMutation.onMutate`:
```typescript
queryClient.setQueriesData<...>(
  { queryKey: notificationKeys.lists() },
  old => {
    if (!old) return old
    const removed = old.data.find(n => n.id === id)
    if (removed && !removed.isRead) {
      useNotificationStore.getState().decrementUnread()  // ← يُنفَّذ لكل cache entry تحتوي الـ notification
    }
    return { ... }
  },
)
```

**الحل المطلوب:**
نقل الـ decrement خارج الـ `setQueriesData` callback — تنفيذه مرة واحدة قبل الـ loop:

```typescript
onMutate: async (id: string) => {
  await queryClient.cancelQueries({ queryKey: notificationKeys.all })

  const previousLists = queryClient.getQueriesData<{ data: Notification[] }>({
    queryKey: notificationKeys.lists(),
  })

  // تحقق ONE TIME: هل الـ notification كانت unread في أي cache؟
  const wasUnread = previousLists.some(([, old]) =>
    old?.data.some(n => n.id === id && !n.isRead)
  )

  // نقل الـ decrement خارج الـ callback
  if (wasUnread) {
    useNotificationStore.getState().decrementUnread()
  }

  // تحديث كل الـ caches (بدون decrementUnread داخلها)
  queryClient.setQueriesData<{ data: Notification[]; count: number; ... }>(
    { queryKey: notificationKeys.lists() },
    old => {
      if (!old) return old
      return {
        ...old,
        data: old.data.filter(n => n.id !== id),
        count: Math.max(0, old.count - 1),
      }
    },
  )
  // ...
}
```

**ما يجب عدم تغييره:**
- الـ optimistic removal من cache (filter)
- الـ count decrement في cache object
- الـ rollback logic في onError

**اختبارات مطلوبة:**
- `[ ]` archive notification موجودة في 2 caches مختلفة → `decrementUnread` يُستدعى مرة واحدة فقط
- `[ ]` archive notification مقروءة → لا `decrementUnread`
- `[ ]` الـ badge count صحيح بعد archive

---

### S2-T7 — إصلاح SalesOrderDetail: توحيد permission identifier
**المرجع:** EA-DOM-01 / F-DOMAIN-01  
**الأولوية:** P2  
**الملفات:** `src/pages/sales/SalesOrderDetail.tsx`، `src/lib/permissions/constants.ts`

**المشكلة المؤكدة:**
- `SalesOrderDetail.tsx:383` يستخدم: `can('sales.orders.update')`
- `constants.ts` لا يحتوي على `SALES_ORDERS_UPDATE`
- النتيجة: كل المستخدمين يرون الزر مخفياً بغض النظر عن أدوارهم

**الحل المطلوب:**
خيار A (المفضل): إضافة `SALES_ORDERS_UPDATE` لـ constants وإضافته للأدوار المناسبة في DB:
```typescript
// في constants.ts
SALES_ORDERS_UPDATE: 'sales.orders.update',
```
ثم إضافة migration لمنح هذا الـ permission للأدوار الصحيحة.

خيار B (سريع مؤقت): استخدام أقرب permission موجود:
```typescript
// في SalesOrderDetail.tsx — مؤقت حتى يُضاف permission صحيح
can(PERMISSIONS.SALES_ORDERS_EDIT_CONFIRMED) || can(PERMISSIONS.SALES_ORDERS_CREATE)
```

**الحل المقترح:** خيار A لأنه الصحيح هندسياً.

**خطوات التنفيذ:**
1. إضافة `SALES_ORDERS_UPDATE: 'sales.orders.update'` لـ constants.ts
2. إنشاء migration لإضافة هذا الـ permission لـ role المبيعات
3. استخدام `PERMISSIONS.SALES_ORDERS_UPDATE` في SalesOrderDetail بدل الـ string literal

**اختبارات مطلوبة:**
- `[ ]` user مع role المبيعات يرى زر التعديل على draft orders
- `[ ]` user بدون permission لا يرى الزر
- `[ ]` permission string متسق بين constants/DB/UI

---

### Sprint 2 — Checklist الإغلاق

- `[ ]` S2-T1: activities مفلترة بـ typeCategory → count وpages صحيحة
- `[ ]` S2-T2: visit plans مفلترة بـ branchId → count وpages صحيحة
- `[ ]` S2-T3: call plans مفلترة بـ branchId → count وpages صحيحة
- `[ ]` S2-T4: users مفلترة بـ role → count وpages صحيحة
- `[ ]` S2-T5: create-user فاشل في roles → يرجع error ولا يُنشئ user
- `[ ]` S2-T6: archive notification → unread count لا ينخفض أكثر من مرة
- `[ ]` S2-T7: SalesOrderDetail → edit button مرئي للأدوار الصحيحة
- `[ ]` لا regression في أي list page كانت تعمل صح

---

## Sprint 3 — Scale Readiness والأداء (P1/P2 Scale)
**المدة المقدرة:** 4-5 أيام عمل  
**الأولوية:** عالية — مطلوب قبل فتح الـ app لعدد كبير من المستخدمين

---

### S3-T1 — توسيع GlobalRealtimeManager: Domain Invalidation Matrix
**المرجع:** EA-OPS-01 / F-DATA-03  
**الأولوية:** P2  
**الملف:** `src/components/shared/GlobalRealtimeManager.tsx`

**المشكلة المؤكدة:**
`TABLE_QUERY_MAP` يفتقد جداول أساسية. من Sprint 0 يجب أن تكون لدينا قائمة كاملة بالـ gaps.

**المنهجية الصحيحة:**
بناء matrix رسمي بدل إضافة جزئية:

**إضافات مؤكدة مطلوبة (من فحص الكود):**
```typescript
const TABLE_QUERY_MAP: Record<string, string[]> = {
  // موجود حالياً (يبقى كما هو)
  expenses: ['expenses'],
  // ...

  // ← جديد: المبيعات
  sales_orders:       ['sales-orders'],
  sales_order_items:  ['sales-orders'],
  sale_returns:       ['sales-returns'],
  
  // ← جديد: الأنشطة
  visit_plans:        ['visit-plans'],
  visit_plan_items:   ['visit-plans'],
  call_plans:         ['call-plans'],
  call_plan_items:    ['call-plans'],
  activities:         ['activities'],
  
  // ← جديد: HR
  hr_employees:       ['employees'],
  hr_attendance:      ['attendance'],
  // (باقي الـ HR tables تُحدد من نتائج S0-T2)
}
```

**ما يجب عدم تغييره:**
- الـ existing mappings
- الـ DEBOUNCE_MS (500ms)
- الـ channel subscription logic

**اختبارات مطلوبة:**
- `[ ]` إنشاء sales_order من tab آخر → قائمة الطلبات في الـ tab الأول تتحدث
- `[ ]` تحديث visit_plan → قائمة خطط الزيارات تتحدث
- `[ ]` الـ debounce يمنع flooding عند bulk updates

---

### S3-T2 — تحويل Payroll Calculation إلى Server-Side
**المرجع:** EA-PERF-01 / F-PERF-01  
**الأولوية:** P2  
**الملفات:** `src/hooks/useQueryHooks.ts`، `src/lib/services/hr.ts`، migration جديدة

**تفاصيل المشكلة (تُحدد بعد S0-T4):**
الكود يلف على الموظفين النشطين ويستدعي RPC لكل موظف بالتتابع من المتصفح.

**الحل المطلوب:**
إنشاء RPC واحد على الـ DB يعالج كل الموظفين:

```sql
CREATE OR REPLACE FUNCTION run_monthly_payroll(
  p_year int,
  p_month int
) RETURNS TABLE(
  processed_count int,
  failed_count int,
  total_net bigint
) AS $$
BEGIN
  -- Process all employees in one transaction
  -- ...
END;
$$;
```

**تغيير في useQueryHooks.ts:**
استبدال الـ loop بـ mutation واحدة:
```typescript
const runPayrollMutation = useMutation({
  mutationFn: ({ year, month }) => supabase.rpc('run_monthly_payroll', { p_year: year, p_month: month }),
  onSuccess: () => {
    queryClient.invalidateQueries({ queryKey: ['payroll-runs'] })
    queryClient.invalidateQueries({ queryKey: ['employees'] })
  }
})
```

**ما يجب عدم تغييره:**
- الـ UI للزر والـ progress display
- شكل النتيجة المعروضة للمستخدم

**اختبارات مطلوبة:**
- `[ ]` payroll run يكتمل في request واحد بدل N requests
- `[ ]` إغلاق الـ tab أثناء التشغيل لا يوقف العملية
- `[ ]` النتائج صحيحة مقارنة بالـ implementation القديم

---

### S3-T3 — إصلاح getUsers: roles caching
**المرجع:** SCALE-06  
**الأولوية:** P2  
**الملف:** `src/lib/services/users.ts`

**المشكلة:**
`supabase.from('roles').select('*')` يُنفَّذ في كل `getUsers()` و`getUser()` call.

**الحل:**
إنشاء `getRolesMap()` helper مع caching بسيط:
```typescript
let rolesCache: Map<string, Role> | null = null
let rolesCacheTime = 0
const ROLES_CACHE_TTL = 5 * 60 * 1000 // 5 minutes

async function getRolesMap(): Promise<Map<string, Role>> {
  if (rolesCache && Date.now() - rolesCacheTime < ROLES_CACHE_TTL) {
    return rolesCache
  }
  const { data } = await supabase.from('roles').select('*')
  rolesCache = new Map((data || []).map(r => [r.id, r]))
  rolesCacheTime = Date.now()
  return rolesCache
}
```

**اختبارات مطلوبة:**
- `[ ]` متعدد `getUsers()` calls في نفس الجلسة → roles fetched مرة واحدة فقط
- `[ ]` نتائج `getUsers` لا تزال صحيحة

---

### Sprint 3 — Checklist الإغلاق

- `[ ]` S3-T1: sales_orders تغيير → يظهر في list فوراً بدون manual refresh
- `[ ]` S3-T1: visit_plans تغيير → يظهر في list فوراً
- `[ ]` S3-T2: payroll run لا يعتمد على browser loop
- `[ ]` S3-T3: roles table لا تُجلب في كل user request
- `[ ]` لا regression في أي module كان يعمل

---

## Sprint 4 — Mobile UX وإغلاق Dead-Ends (P1/P2 UX)
**المدة المقدرة:** 4-5 أيام عمل  
**الأولوية:** عالية — مطلوب قبل الإطلاق لأن المستخدمين الميدانيين على موبايل

---

### S4-T1 — VisitPlanDetail: Mobile Overflow Menu للإجراءات المخفية
**المرجع:** EA-UX-01 / F-UX-01  
**الأولوية:** P1 — Dead-end معطل  
**الملفات:** `src/pages/activities/VisitPlanDetail.tsx`

**المشكلة المؤكدة:**
3 إجراءات مهمة مخفية تماماً على الموبايل:
- `إنهاء اليومية المتبقية` (Bulk Close)
- `استنساخ المسار` (Clone Plan)
- `حفظ كقالب` (Save as Template)

**الحل المطلوب:**
إضافة "More Actions" button/sheet على الموبايل يعيد نفس الإجراءات.

**النهج:**
```typescript
// state جديد
const [moreActionsOpen, setMoreActionsOpen] = useState(false)

// في الـ header actions:
{/* Desktop buttons يبقون كما هم */}
<Button className="desktop-only-btn" onClick={() => setBulkCloseOpen(true)}>
  إنهاء اليومية
</Button>

{/* Mobile more button — جديد */}
<Button 
  className="mobile-only-btn"  // ← visible فقط على mobile
  variant="secondary" 
  icon={<MoreVertical size={16} />}
  onClick={() => setMoreActionsOpen(true)}
>
  المزيد
</Button>

{/* Mobile actions bottom sheet */}
<ResponsiveModal 
  open={moreActionsOpen} 
  onClose={() => setMoreActionsOpen(false)}
  title="إجراءات إضافية"
>
  {/* نفس الـ handlers الموجودة — فقط trigger جديد */}
  {canConfirm && pendingItems.length > 0 && (
    <button onClick={() => { setMoreActionsOpen(false); setBulkCloseOpen(true) }}>
      إنهاء اليومية المتبقية
    </button>
  )}
  {canCreate && (
    <button onClick={() => { setMoreActionsOpen(false); setCloneOpen(true) }}>
      استنساخ المسار
    </button>
  )}
  {canSaveTmpl && items.length > 0 && (
    <button onClick={() => { setMoreActionsOpen(false); setSaveTmplOpen(true) }}>
      حفظ كقالب
    </button>
  )}
</ResponsiveModal>
```

**الإضافة المطلوبة في components.css:**
```css
@media (max-width: 768px) {
  .mobile-only-btn { display: inline-flex !important; }
}
@media (min-width: 769px) {
  .mobile-only-btn { display: none !important; }
}
```

**ما يجب عدم تغييره:**
- الـ desktop buttons تبقى بنفس `className="desktop-only-btn"`
- كل الـ modal handlers والـ mutation flows لا تتغير
- فقط الـ trigger surface يتغير للموبايل

**اختبارات مطلوبة:**
- `[ ]` mobile viewport: زر "المزيد" ظاهر
- `[ ]` mobile viewport: tap "المزيد" → يفتح sheet يحتوي الإجراءات
- `[ ]` mobile: تنفيذ "إنهاء اليومية" من الـ sheet يعمل
- `[ ]` mobile: تنفيذ "استنساخ المسار" من الـ sheet يعمل
- `[ ]` desktop: Desktop buttons ظاهرة، mobile sheet مخفي

---

### S4-T2 — CallPlanDetail: نفس Mobile Overflow Menu
**المرجع:** EA-UX-01 (CallPlanDetail)  
**الأولوية:** P1  
**الملف:** `src/pages/activities/CallPlanDetail.tsx`

نفس النهج الذي طُبق في S4-T1. إعادة استخدام نفس pattern.

---

### S4-T3 — FAB Audit Fix: معالجة الـ pages بدون mobile create path
**المرجع:** NV-UX-01  
**الأولوية:** P2 (تُحدد بعد S0-T1)  
**الملفات:** صفحات محددة بعد S0-T1

**بعد نتائج S0-T1:**
لكل صفحة يُثبت أن FAB لا يغطيها:
- إضافة FAB context أو تحديث FAB للـ routing المناسب لتلك الصفحة
- أو إضافة mobile-specific create button

---

### S4-T4 — NotificationsPage: إصلاح tab overflow على الموبايل
**المرجع:** EA-UX-02 / F-UX-02  
**الأولوية:** P2  
**الملف:** `src/pages/notifications/NotificationsPage.tsx`

**المشكلة المؤكدة:**
```css
@media (max-width: 768px) {
  .npage-tabs {
    overflow-x: visible;  /* ← لا fallback عند overflow */
  }
}
```

**الحل:**
```css
@media (max-width: 768px) {
  .npage-tabs {
    overflow-x: auto;  /* ← restore scroll fallback */
    -webkit-overflow-scrolling: touch;
    scrollbar-width: none;
  }
  .npage-tabs::-webkit-scrollbar { display: none; }
}
```

**اختبارات مطلوبة:**
- `[ ]` 320px viewport → كل الـ 3 tabs مرئية أو scrollable
- `[ ]` large text settings → tabs لا تُقطع

---

### S4-T5 — NotificationItem: تكبير touch targets على الموبايل
**المرجع:** EA-UX-03 / F-UX-03  
**الأولوية:** P2  
**الملف:** `src/components/notifications/NotificationItem.tsx`

**المشكلة المؤكدة:**
```css
@media (max-width: 768px) {
  .ni-action-btn {
    width: 26px;   /* ← دون الحد الأدنى */
    height: 26px;
  }
}
```

**الحل:**
```css
@media (max-width: 768px) {
  .ni-action-btn {
    width: 36px;   /* ← أكبر من 44 مستحسن، 36 حد أدنى عملي */
    height: 36px;
    border-radius: var(--radius-md);
    /* زيادة مساحة الـ tap zone */
    padding: 6px;
  }
  .ni-actions {
    gap: 6px;      /* ← زيادة المسافة بين الأزرار */
  }
}
```

**اختبارات مطلوبة:**
- `[ ]` tap archive button → لا يُفتح الإشعار
- `[ ]` tap row → لا يُؤرشف الإشعار
- `[ ]` visual regression للـ layout

---

### Sprint 4 — Checklist الإغلاق

- `[ ]` S4-T1: VisitPlanDetail mobile → 3 actions متاحة من overflow menu
- `[ ]` S4-T2: CallPlanDetail mobile → نفس الوضع
- `[ ]` S4-T3: FAB coverage مؤكدة لكل list pages
- `[ ]` S4-T4: notification tabs مرئية على 320px
- `[ ]` S4-T5: archive/delete tap موثوق على الموبايل
- `[ ]` manual QA على mobile viewport لكل الصفحات المعدلة

---

## Sprint 5 — Observability والجودة الهندسية (Technical Debt)
**المدة المقدرة:** 3-4 أيام  
**الأولوية:** متوسطة — مهم للتشغيل على المدى البعيد لكن لا يمنع الإطلاق

---

### S5-T1 — Error Tracking: إضافة Sentry أو مكافئ
**الأولوية:** P2  
- تثبيت Sentry (أو LogRocket)
- إضافة error boundary logging في React
- إضافة edge function error reporting
- إضافة auth failure tracking

### S5-T2 — @ts-nocheck: إزالة من Edge Functions
**الأولوية:** P2  
**الملفات:** `dispatch-notification/index.ts`، `create-user/index.ts`
- إزالة `@ts-nocheck`
- إصلاح TypeScript errors الناتجة (غالباً Deno-specific imports)

### S5-T3 — Inline Styles: بدء migration تدريجي
**الأولوية:** P3 (debt طويل الأمد)
- لا يُوحد دفعة واحدة — مخاطر عالية
- استراتيجية: عند تعديل أي component، extract styles إلى CSS module أو global stylesheet
- توثيق convention واضح: لا `<style>` جديدة في JSX

### S5-T4 — Test Infrastructure: إعداد Vitest
- إضافة `vitest` لـ devDependencies
- إضافة `@testing-library/react` و`@testing-library/user-event`
- إعداد `vitest.config.ts` أساسي
- كتابة 5 tests أساسية كـ proof-of-concept:
  - getActivities filter correctness
  - useMarkAsReadMutation decrement logic
  - loadSession error handling
  - Permission guard rendering
  - Notification count display

---

## جدول ملخص الـ Sprints

| Sprint | الاسم | المدة | العناصر | Priority |
|--------|-------|-------|---------|---------|
| S0 | Pre-Sprint Verification | 1 يوم | 4 tasks تحقق | قبل الكل |
| S1 | Security & Auth Stability | 4-5 أيام | 5 tasks | P0/P1 |
| S2 | Data Correctness & State | 5-6 أيام | 7 tasks | P1/P2 |
| S3 | Scale Readiness | 4-5 أيام | 3 tasks | P2 |
| S4 | Mobile UX Dead-ends | 4-5 أيام | 5 tasks | P1/P2 |
| S5 | Observability & Quality | 3-4 أيام | 4 tasks | P2/P3 |
| **Total** | | **~22-26 يوم** | **28 tasks** | |

---

## Verification Checklist النهائي قبل الإطلاق

يجب تحقيق كل النقاط التالية قبل Soft Launch:

### الأمان
- `[ ]` JWT مزور مع `{"role":"service_role"}` يُرفض من dispatch-notification
- `[ ]` مستخدم عادي لا يستطيع إرسال إشعارات لمستخدمين آخرين
- `[ ]` logout → login على نفس الجهاز → لا بيانات من الجلسة السابقة
- `[ ]` HTTP responses تحتوي على CSP وHSTS وX-Frame-Options

### الاستقرار
- `[ ]` انقطاع مؤقت في الـ backend لا يُخرج المستخدم من الجلسة
- `[ ]` حساب معطل يُخرج المستخدمين الصحيحين

### صحة البيانات
- `[ ]` تصفية activities بـ typeCategory → صفحات وcounts صحيحة
- `[ ]` تصفية visit/call plans بـ branchId → صفحات وcounts صحيحة
- `[ ]` إنشاء مستخدم جديد يفشل بشكل كامل إذا فشل role assignment
- `[ ]` أرشفة إشعار واحد → unread badge ينقص بمقدار 1 فقط

### الموبايل
- `[ ]` VisitPlanDetail: bulk close متاح على الموبايل
- `[ ]` VisitPlanDetail: clone plan متاح على الموبايل
- `[ ]` VisitPlanDetail: save as template متاح على الموبايل
- `[ ]` NotificationsPage: كل الـ 3 tabs مرئية على 320px

### الوظائف الأساسية (لا regression)
- `[ ]` Login / Logout يعمل
- `[ ]` إنشاء sales order يعمل
- `[ ]` تأكيد visit plan يعمل
- `[ ]` إشعارات realtime تصل
- `[ ]` PWA install يعمل

---

## ملاحظات تنفيذية مهمة

### 1. ترتيب التنفيذ صارم
Sprint 1 يجب أن يُكمل ويُدمج قبل بدء Sprint 2. لا يوجد ما يمنع تشغيل S2 و S4 بالتوازي بعد إغلاق S1، لكن يُفضل التسلسل لتقليل مخاطر الـ merge conflicts.

### 2. Feature flags مؤقتة
لإصلاحات SCALE-01/02/03، يُنصح بإضافة feature flag مؤقتة:
```typescript
const USE_SERVER_FILTERED_PAGINATION = true  // toggle for rollback
```
هذا يسمح بالتراجع السريع إذا ظهرت مشكلة في production.

### 3. DB Migrations
أي إضافة لـ RPC أو View تتطلب migration file جديد في `supabase/migrations/` باسم تسلسلي واضح.

### 4. Internal Callers Audit قبل S1-T1
قبل deploy S1-T1، نفّذ:
```bash
grep -r "dispatch-notification" . --include="*.ts" --include="*.sql"
```
وتأكد من تحديث كل caller ليمرر `x-internal-secret`.

### 5. مراجعة إضافية مطلوبة بعد S0
بناءً على نتائج S0:
- قد تُضاف tasks جديدة لـ Sprint 3 أو 4 إذا وُجدت FAB gaps أو realtime gaps إضافية
- هذا متوقع وطبيعي — الخطة قابلة للتعديل بناءً على S0 findings
