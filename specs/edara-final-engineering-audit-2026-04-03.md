# التقرير الهندسي النهائي لمراجعة نظام EDARA

التاريخ: 2026-04-03

الجمهور المستهدف: الفريق الهندسي، الـ Tech Leads، ومسؤولو الاعتماد قبل الإطلاق

حالة الوثيقة: تقرير هندسي نهائي قابل للاعتماد والتنفيذ

مصادر التقرير:

- مراجعاتنا المباشرة للكود داخل المستودع
- تقرير المراجعة الموسع المقدم من Claude
- التحقق اليدوي من المسارات عالية الخطورة في الكود

مبدأ هذه الوثيقة:

- العيوب المؤكدة من الكود تُفصل عن البنود التي تحتاج تحقق إضافي
- المخاطر تُشرح بلغة تشغيلية، لا وصفًا كوديًا فقط
- كل نتيجة تتضمن حلًا احترافيًا وطريقة تنفيذ منخفضة المخاطر

---

## 1. الملخص التنفيذي

الحكم العام: النظام **غير جاهز للإنتاج بصورته الحالية**، لكنه يملك أساسًا معماريًا جيدًا ويمكن رفعه إلى مستوى جاهزية إنتاجية مقبول عبر حزمة إصلاحات مركزة ومحددة.

أهم ما يمنع الإطلاق حاليًا:

1. ثغرة أمنية مؤكدة في `dispatch-notification` تسمح بتزوير مسار `service_role`.
2. غياب تفويض حقيقي للـ browser callers عند إرسال الإشعارات.
3. كاش غير آمن لطلبات Supabase الموثقة داخل `service worker`.
4. أخطاء صحة بيانات في pagination بسبب الفلترة بعد `range()`.
5. مسارات تشغيلية معطلة على الموبايل في صفحات خطط الزيارات/المكالمات.

أهم ما يمنع التوسع بثقة:

- استمرار patterns من نوع `post-pagination filtering`
- orchestrations ثقيلة من المتصفح بدل الخادم
- gaps في realtime invalidation
- نقاط drift في counts/stores
- غياب تغطية اختبارية تحمي الإصلاحات المستقبلية

التقدير العام:

- الإصلاحات الحرجة ليست إعادة بناء شاملة، لكنها تتطلب انضباطًا هندسيًا قويًا.
- المسار الأنسب هو الحفاظ على العقود الحالية قدر الإمكان، وتبديل internals غير الآمنة أو غير القابلة للتوسع خلف نفس الواجهات.

---

## 2. منهجية ونطاق المراجعة

### ما تمت مراجعته مباشرة

- `supabase/functions/dispatch-notification/index.ts`
- `supabase/functions/create-user/index.ts`
- `src/sw.ts`
- `src/lib/services/auth.ts`
- `src/lib/services/activities.ts`
- `src/lib/services/users.ts`
- `src/hooks/useNotificationQueries.ts`
- `src/components/shared/GlobalRealtimeManager.tsx`
- `src/hooks/useQueryHooks.ts`
- `src/pages/sales/SalesOrderDetail.tsx`
- ملفات الواجهة المعدلة الخاصة بالإشعارات و`VisitPlanDetail`
- `src/styles/components.css`
- `src/components/layout/AppLayout.tsx`
- `package.json`
- `vite.config.ts`
- `vercel.json`

### ما تم تتبعه على مستوى المسارات

- مسار الإشعارات: trigger -> edge function -> DB -> realtime -> store -> badge/UI
- مسار session bootstrap: `auth.getUser()` -> `get_my_profile()` -> store hydration
- مسار user provisioning: create user -> profile -> roles
- مسارات pagination/filtering في activities وplans وusers
- مسارات mobile action reachability في صفحات الخطط والإشعارات

### ما لم يكن قابلاً للتحقق الكامل

- جميع سياسات RLS داخل جميع migrations
- جميع RPC implementations داخل قاعدة البيانات
- جميع تفاصيل HR/Finance/Sales backend beyond sampled paths
- مدى تغطية الـ FAB لكل الشاشات التي تستخدم `.desktop-only-btn`
- منظومة المراقبة الفعلية في الإنتاج

### مستوى الثقة

- **مرتفع** في النتائج المؤكدة أدناه لأنها مبنية على معاينة مباشرة للكود
- **متوسط** في البنود المفصولة داخل قسم "يحتاج تحقق إضافي" لأنها مهمة هندسيًا لكن لم تُثبت كلها بالمستوى نفسه من التحقق المباشر

---

## 3. مصفوفة التقييم العام حسب المحاور

| المحور | التقييم الحالي | الخطورة | سبب التقييم | الأثر على الإنتاج |
|---|---|---:|---|---|
| الأمن | ضعيف حاليًا | P0 | ثغرات trust boundary وتفويض في الإشعارات + caching exposure | يمنع الإطلاق |
| صحة البيانات والمنطق | يحتاج إصلاح عاجل | P1 | pagination/count correctness وpartial provisioning | نتائج مضللة ومسارات غير موثوقة |
| الأداء والتوسع | متوسط حاليًا | P1 | post-pagination filtering وbrowser-side batching | سلوك غير صحيح وتدهور واضح مع النمو |
| الاعتمادية والتشغيل | متوسط إلى ضعيف | P1 | forced sign-out وstale data windows | تجربة تشغيل غير مستقرة |
| الواجهة وتجربة المستخدم | غير متجانسة | P1 | mobile dead ends وtouch/mis-tap risks | تعطيل مسارات حقيقية للمستخدم |
| البنية والجودة الهندسية | جيدة أساسًا لكن عليها ديون مهمة | P2 | coupling gaps وinline-style debt وunsafe escape hatches | تباطؤ التطوير وزيادة مخاطرة التغيير |
| الاختبارات والتغطية | منخفضة | P2 | غياب واضح لتغطية تحمي المسارات الحرجة | خطر regression مرتفع |

---

## 4. النتائج المؤكدة

### EA-SEC-01

- **Severity:** `P0`
- **Category:** Security
- **Layer:** Edge Function
- **Affected components:** `dispatch-notification`, notification delivery path

**Problem**  
يتم تحديد ما إذا كان الطلب داخليًا عبر قراءة `role` من payload داخل JWT بدون التحقق من signature. هذا يسمح لأي طرف بصنع token شكليًا يحتوي `{"role":"service_role"}` وتجاوز مسار التحقق الخاص بالمستخدم العادي.

**Why this is confirmed**  
الكود يقرأ الجزء الأوسط من JWT ويفك ترميزه بـ `atob()` ثم يقارن `payload.role` مباشرة دون أي verification cryptographic.

**Failure scenario**  
أي عميل HTTP يرسل bearer token مزورًا ويمر عبر المسار الداخلي، ثم ينشئ إشعارات ويدفع push notifications لمستخدمين اعتباطيين باستخدام admin client.

**Production impact**  
ثغرة release-blocking تسمح بإساءة استخدام منظومة الإشعارات على مستوى النظام.

**Scale impact**  
مع ازدياد عدد المستخدمين تتحول الثغرة إلى vector للـ spam والتشويش التشغيلي واسع النطاق.

**Best professional fix**  
- إزالة الاعتماد على claims غير موثقة
- فصل internal auth عن browser auth
- استخدام shared secret داخلي أو internal-only signed mechanism
- أو verification حقيقي للـ JWT قبل الوثوق بأي claim

**Low-risk rollout strategy**  
- الحفاظ على نفس request shape
- إدخال helper داخلي جديد للتحقق
- تحديث internal callers فقط
- إضافة logging مؤقت للطلبات المرفوضة بعد التغيير

**Required tests**  
- forged token -> `401/403`
- valid internal call -> success
- valid user token without internal auth -> external path only

### EA-SEC-02

- **Severity:** `P1`
- **Category:** Security
- **Layer:** Edge Function / Authorization
- **Affected components:** `dispatch-notification`, browser-triggered notification flow

**Problem**  
المسار الخارجي يتحقق فقط من أن المستخدم authenticated، ثم يقبل `event_key` و`user_ids` كما أرسلها العميل، بدون permission check أو recipient scope enforcement.

**Why this is confirmed**  
الكود يستدعي `auth.getUser()` ثم يكمل التنفيذ بدون check_permission أو equivalent policy.

**Failure scenario**  
أي مستخدم مسجل يمكنه إرسال إشعارات لمستخدمين آخرين، أو انتحال أحداث عمل حساسة من خلال `event_key`.

**Production impact**  
إشعارات كاذبة، spam داخلي، وتآكل الثقة في قنوات التنبيه.

**Scale impact**  
الضرر يتضاعف مع ازدياد المستخدمين لأن fan-out يصبح أكبر وسوء الاستخدام أكثر أثرًا.

**Best professional fix**  
- فرض permission صريح مثل `notifications.dispatch`
- تقييد `event_key` بقائمة allowlist حسب الدور
- اشتقاق recipients على الخادم بدل قبولهم بحرية من المتصفح

**Low-risk rollout strategy**  
- الإبقاء على endpoint الحالي
- إضافة validation server-side أولًا
- ثم نقل callers تدريجيًا إلى domain-specific triggers إن لزم

**Required tests**  
- authenticated user without permission -> `403`
- authenticated user with allowed event and scoped recipients -> success
- arbitrary recipient list from unprivileged user -> reject

### EA-SEC-03

- **Severity:** `P1`
- **Category:** Security / Runtime
- **Layer:** Service Worker
- **Affected components:** `src/sw.ts`, authenticated API traffic

**Problem**  
جميع طلبات `*.supabase.co` تمر عبر cache موحد من نوع `NetworkFirst`، ما يفتح باب replay لردود محمية بين جلسات مختلفة على نفس الجهاز.

**Why this is confirmed**  
الـ route يطابق hostname بالكامل ولا يميز بين public/static/authenticated requests، ولا تختلف cache key حسب session identity.

**Failure scenario**  
User A يحمّل بيانات حساسة، ثم logout، ثم User B يدخل على نفس الجهاز أثناء ضعف الشبكة أو offline fallback فيحصل على cached response لا تخصه.

**Production impact**  
تعريض بيانات محمية بين الجلسات، خصوصًا على الأجهزة المشتركة.

**Scale impact**  
يزداد خطر الحوادث التشغيلية والدعم الفني مع انتشار الأجهزة المشتركة واستخدام PWA.

**Best professional fix**  
- إزالة كاش authenticated Supabase traffic بالكامل
- الإبقاء على caching فقط للـ static assets والـ public resources

**Low-risk rollout strategy**  
- تعطيل Supabase API caching أولًا بدون المساس ببقية Workbox rules
- اختبار offline behavior للشاشات الحرجة بعد التعديل

**Required tests**  
- login/logout/login on same device with offline fallback
- ensure protected responses are never served cross-session

### EA-REL-01

- **Severity:** `P1`
- **Category:** Reliability/Operations
- **Layer:** Auth Service
- **Affected components:** `src/lib/services/auth.ts`, session bootstrap

**Problem**  
أي error صادر من `get_my_profile()` يؤدي إلى sign-out، حتى لو كان الخطأ transient network/db failure وليس account deactivation.

**Why this is confirmed**  
الشرط الحالي يجمع `error || !data || data.status !== 'active'` في نفس مسار `signOut()`.

**Failure scenario**  
انقطاع مؤقت أو timeout أثناء boot يؤدي إلى إخراج مستخدمين صحيحين من الجلسة وإعادة توجيههم إلى login.

**Production impact**  
جلسات غير مستقرة وتجربة تشغيل سيئة أثناء اضطرابات backend المؤقتة.

**Scale impact**  
كلما زاد الحمل أو تواتر hiccups، زادت احتمالية forced logout الجماعي.

**Best professional fix**  
- فصل auth state عن profile-loading state
- sign out فقط عند account status صريح أو auth failure مؤكد
- إظهار degraded state/retry path عند transport failure

**Low-risk rollout strategy**  
- الحفاظ على store API الحالي
- إضافة error state خاصة بالbootstrap بدل reset الكامل

**Required tests**  
- transient RPC failure does not sign out
- inactive account still signs out

### EA-SCL-01

- **Severity:** `P1`
- **Category:** Performance/Scale + Correctness
- **Layer:** Service / Data Access
- **Affected components:** `getActivities`, activities listing UI

**Problem**  
فلترة `typeCategory` تطبق بعد `range()`، أي بعد pagination على dataset غير مفلتر.

**Why this is confirmed**  
الخدمة تجلب الصفحة أولًا ثم تنفذ `rows.filter(...)` محليًا.

**Failure scenario**  
المستخدم يختار category معينة، فيرى صفحات ناقصة أو فارغة بينما `count` و`totalPages` يعكسان dataset أوسع من الفلتر.

**Production impact**  
نتائج غير موثوقة وصعوبة في تصفح السجلات.

**Scale impact**  
يزداد الخطأ مع تضخم السجلات ويؤدي إلى wastage في network/client work.

**Best professional fix**  
- نقل الفلترة إلى DB layer قبل pagination عبر view أو RPC أو join filter مناسب

**Low-risk rollout strategy**  
- الحفاظ على response contract الحالي
- تبديل implementation فقط

**Required tests**  
- filtered count correctness
- filtered page membership correctness

### EA-SCL-02

- **Severity:** `P1`
- **Category:** Performance/Scale + Correctness
- **Layer:** Service / Data Access
- **Affected components:** `getVisitPlans`, branch-scoped plan views

**Problem**  
فلترة `branchId` لخطط الزيارات تتم بعد pagination.

**Why this is confirmed**  
الخدمة تفلتر `rows` محليًا باستخدام `employee.branch_id` بعد جلب الصفحة.

**Failure scenario**  
مشرف فرع يرى صفحات قليلة العناصر أو فارغة رغم وجود نتائج حقيقية داخل الفرع.

**Production impact**  
انهيار موثوقية شاشات الإشراف والتخطيط.

**Scale impact**  
كلما اتسعت البيانات عبر الفروع، زادت صفحات false-empty وزاد التضليل في counts.

**Best professional fix**  
- استعلام DB-side يجمع employee branch filter قبل `range()`

**Low-risk rollout strategy**  
- الإبقاء على نفس hook/service contract
- تبديل query backend only

**Required tests**  
- branch-filtered pages and totals

### EA-SCL-03

- **Severity:** `P1`
- **Category:** Performance/Scale + Correctness
- **Layer:** Service / Data Access
- **Affected components:** `getCallPlans`, branch-scoped call-plan views

**Problem**  
نفس pattern السابق موجود في `getCallPlans()`.

**Why this is confirmed**  
الفلترة تتم محليًا على `rows` بعد الجلب.

**Failure scenario**  
صفحات call plans بحسب الفرع تصبح ناقصة أو misleading.

**Production impact**  
تجربة إشراف غير موثوقة في call-center workflows.

**Scale impact**  
الخلل يزداد مع نمو البيانات وتعدد الفروع.

**Best professional fix**  
- نفس fix pattern الخاص بـ visit plans

**Low-risk rollout strategy**  
- توحيد الحل على مستوى service layer

**Required tests**  
- same as visit plans

### EA-DAT-01

- **Severity:** `P2`
- **Category:** Data/Correctness
- **Layer:** Edge Function / Provisioning
- **Affected components:** `create-user`, user onboarding/admin provisioning

**Problem**  
إذا فشل insert داخل `user_roles` يتم log فقط وإرجاع `201 Created` رغم أن provisioning غير مكتمل.

**Why this is confirmed**  
الـ function لا توقف التنفيذ عند `rolesErr`.

**Failure scenario**  
ينشأ user/profile بنجاح جزئي، لكن بدون roles، بينما لوحة الإدارة تعتبر العملية ناجحة.

**Production impact**  
حسابات شبحية أو ناقصة الصلاحيات، وصعوبة دعم وتشخيص.

**Scale impact**  
مع زيادة provisioning flows تزداد احتمالات partial-account incidents.

**Best professional fix**  
- جعل provisioning atomic بالكامل
- أو تنفيذ compensation rollback عند failure

**Low-risk rollout strategy**  
- الحفاظ على success payload في happy path
- إضافة structured error عند الفشل

**Required tests**  
- role assignment failure triggers rollback or explicit failure

### EA-DAT-02

- **Severity:** `P2`
- **Category:** Data/Correctness
- **Layer:** State / Cache
- **Affected components:** `useArchiveMutation`, notification unread store

**Problem**  
أرشفة notification غير مقروءة قد تُنقص unread count أكثر من مرة إذا كانت موجودة في أكثر من cached list.

**Why this is confirmed**  
الـ store decrement يحدث داخل callback تعمل لكل matching cache entry.

**Failure scenario**  
الـ badge يظهر قيمة أقل من الحقيقة مؤقتًا حتى refetch لاحق.

**Production impact**  
إضعاف الثقة في دقة حالة الإشعارات.

**Scale impact**  
يزداد الأثر مع تعدد filters/pages/caches المفتوحة.

**Best professional fix**  
- تنفيذ decrement مرة واحدة لكل mutation وليس لكل cache entry

**Low-risk rollout strategy**  
- الحفاظ على optimistic removal
- نقل side effect خارج per-cache loop

**Required tests**  
- same notification present in multiple caches

### EA-OPS-01

- **Severity:** `P2`
- **Category:** Reliability/Operations
- **Layer:** Realtime / Cache Invalidation
- **Affected components:** `GlobalRealtimeManager`, sales views

**Problem**  
`TABLE_QUERY_MAP` لا يغطي `sales_orders` و`sales_returns` ومفاتيح query المرتبطة بها مثل `sales-stats`.

**Why this is confirmed**  
الخريطة الحالية لا تشمل هذه الجداول، بينما hooks الخاصة بالمبيعات تعتمد على query keys منفصلة واضحة.

**Failure scenario**  
تغييرات المبيعات من تبويب أو مستخدم آخر لا تنعكس إلا بعد manual refresh أو stale-time expiry.

**Production impact**  
بيانات stale في لوحات وتقارير ومتابعة الطلبات.

**Scale impact**  
كلما زاد عدد المستخدمين المتزامنين، زادت تكلفة stale coordination.

**Best professional fix**  
- توسيع invalidation map على أساس domain query matrix وليس بشكل جزئي

**Low-risk rollout strategy**  
- إضافة mappings missing فقط دون تغيير query keys الحالية

**Required tests**  
- cross-session sales update invalidates expected queries

### EA-PERF-01

- **Severity:** `P2`
- **Category:** Performance/Scale
- **Layer:** Frontend orchestration / HR workflow
- **Affected components:** payroll run calculation path

**Problem**  
يتم جلب جميع الموظفين النشطين ثم استدعاء calculation RPC لكل موظف بالتتابع من المتصفح.

**Why this is confirmed**  
الكود يقرأ قائمة الموظفين ثم ينفذ loop sequential من داخل mutation.

**Failure scenario**  
run شهرية للرواتب تستغرق وقتًا طويلًا، أو تنقطع عند إغلاق التبويب، أو تفشل جزئيًا بسبب network jitter.

**Production impact**  
تشغيل حساس معتمد على browser lifetime بدل server-side orchestration.

**Scale impact**  
الزمن الكلي ينمو خطيًا مع عدد الموظفين وlatency الشبكة.

**Best professional fix**  
- نقل orchestration إلى batch RPC أو background job server-side

**Low-risk rollout strategy**  
- إبقاء الزر والـ UI contract
- استبدال internals بخادم يطلق job مع polling/progress

**Required tests**  
- batch start
- job progress
- completion/failure handling

### EA-DOM-01

- **Severity:** `P2`
- **Category:** Data/Correctness / Domain
- **Layer:** Frontend permission gating
- **Affected components:** `SalesOrderDetail`

**Problem**  
زر تعديل أمر البيع gated بواسطة permission identifier لا يظهر أنه معرف أو ممنوح فعليًا في frontend permission model.

**Why this is confirmed**  
الصفحة تستخدم `sales.orders.update` بينما هذا identifier غير متسق مع ما راجعناه سابقًا في constants والمسارات ذات الصلة.

**Failure scenario**  
المستخدم يملك المسار الوظيفي أو route منطقيًا لكن الواجهة تخفي إجراء التعديل.

**Production impact**  
UX وظيفي غير متسق وصعوبة في دعم المستخدمين.

**Scale impact**  
يظهر أكثر مع تعقيد permission matrices وتعدد الأدوار.

**Best professional fix**  
- توحيد permission identifiers في constants/backend/UI

**Low-risk rollout strategy**  
- reconcile aliases أولًا بدل تغيير واسع في المنظومة دفعة واحدة

**Required tests**  
- permission contract tests
- UI visibility tests

### EA-UX-01

- **Severity:** `P1`
- **Category:** UX/Frontend
- **Layer:** Mobile operational flows
- **Affected components:** `VisitPlanDetail`, `CallPlanDetail`, `components.css`

**Problem**  
أزرار تشغيلية مهمة مثل `Bulk Close`, `Clone Plan`, و`Save as Template` مخفية على الموبايل بواسطة `.desktop-only-btn` دون أي بديل mobile.

**Why this is confirmed**  
القاعدة العامة في CSS تخفي `.desktop-only-btn` على `max-width: 768px`، والصفحات المذكورة تستخدم هذا class لهذه الإجراءات تحديدًا.

**Failure scenario**  
المشرف الميداني على الهاتف لا يستطيع إنهاء اليومية، استنساخ المسار، أو حفظه كقالب.

**Production impact**  
dead-end فعلي لمسارات تشغيل رئيسية في جهاز الاستخدام الأقرب لطبيعة هذا النوع من الأنظمة.

**Scale impact**  
يزداد العبء التشغيلي مع نمو فرق العمل الميدانية لأن الاعتماد على الموبايل أعلى.

**Best professional fix**  
- إضافة mobile overflow menu أو bottom sheet لهذه الإجراءات
- عدم إزالة desktop buttons

**Low-risk rollout strategy**  
- reuse existing handlers/modals
- تغيير surface فقط على mobile

**Required tests**  
- mobile viewport action reachability
- same flows succeed from alternative mobile trigger

### EA-UX-02

- **Severity:** `P2`
- **Category:** UX/Frontend
- **Layer:** Notifications page navigation
- **Affected components:** `NotificationsPage`

**Problem**  
تمت إزالة fallback الأفقي لتبويبات الإشعارات على الموبايل، بينما التبويبات ما زالت تعتمد على icon + label + no-wrap layout.

**Why this is confirmed**  
الـ mobile CSS يزيل `overflow-x: auto` ويجعل التبويبات تعتمد على `flex: 1` فقط.

**Failure scenario**  
على الشاشات الأضيق أو مع تكبير الخط قد تصبح بعض التبويبات clipped أو غير مريحة الوصول.

**Production impact**  
تجربة تنقل هشّة في شاشة مركزية داخل منظومة الإشعارات.

**Scale impact**  
الأثر ليس مرتبطًا بحجم البيانات بقدر ارتباطه بتنوع الأجهزة وإعدادات accessibility.

**Best professional fix**  
- إعادة fallback scroll أو تبني mobile tab pattern أكثر صلابة

**Low-risk rollout strategy**  
- restore overflow-x behavior أولًا
- إعادة التصميم لاحقًا إن لزم

**Required tests**  
- 320px/360px widths
- enlarged text settings

### EA-UX-03

- **Severity:** `P2`
- **Category:** UX/Frontend
- **Layer:** Touch interaction safety
- **Affected components:** `NotificationItem`

**Problem**  
أزرار archive/delete على الموبايل صُغّرت إلى `26x26` مع بقاء الصف كاملًا clickable، ما يزيد احتمال mis-tap والتنقل غير المقصود.

**Why this is confirmed**  
الـ mobile override يحدد هذه الأحجام صراحة، والصف يحتفظ بـ row-click behavior.

**Failure scenario**  
المستخدم يحاول الأرشفة أو الحذف لكن يضغط قليلًا خارج الهدف الصغير، فيُفتح الإشعار أو يتم تعليمه كمقروء بدل تنفيذ الإجراء المقصود.

**Production impact**  
إحباط متكرر في أحد أكثر flows تكرارًا للمستخدمين.

**Scale impact**  
ليس scale-sensitive تقنيًا، لكنه high-frequency UX tax.

**Best professional fix**  
- تكبير touch targets
- زيادة separation بين row action وbutton actions

**Low-risk rollout strategy**  
- CSS-only fix أولًا
- إعادة تقييم component interaction model لاحقًا إذا لزم

**Required tests**  
- manual mobile tap reliability QA
- visual regression for button layout

---

## 5. العناصر التي تحتاج تحقق إضافي

### NV-SEC-01 — CORS وsecurity headers

**Why it looks concerning**  
تقرير كلود أشار إلى `Access-Control-Allow-Origin: *` في edge functions وإلى غياب headers مثل CSP/HSTS.

**Why it is not classified as confirmed here**  
لم نعد نثبت كل edge functions وكل headers end-to-end داخل هذه الدورة بالمستوى نفسه من التحقق المباشر.

**What is needed to verify**  
- قراءة جميع edge functions الخاصة بالـ CORS
- مراجعة `vercel.json` وheaders الفعلية في بيئة التشغيل

**Release impact if confirmed**  
مرتفع، لكنه أقل من ثغرات auth/authorization الحالية.

### NV-OPS-01 — مدى اتساع gaps في realtime invalidation خارج المبيعات

**Why it looks concerning**  
هناك مؤشرات على أن موديولات أخرى مثل HR/activities قد تكون أيضًا غير مغطاة بالكامل.

**Why it is not classified as confirmed here**  
المراجعة المباشرة ثبتت gap في المبيعات تحديدًا، لكن لم نكمل matrix كامل لكل الجداول/المفاتيح.

**What is needed to verify**  
- inventory كامل للـ query keys
- mapping matrix مقابل الجداول ذات التغييرات الحية

**Release impact if confirmed**  
متوسط إلى مرتفع حسب الموديول.

### NV-UX-01 — هل الـ FAB يغطي كل أزرار الإنشاء المخفية على الموبايل؟

**Why it looks concerning**  
استخدام `.desktop-only-btn` واسع جدًا في صفحات القوائم.

**Why it is not classified as confirmed here**  
ليس مثبتًا لدينا حاليًا أن كل create flows تصبح dead-end، لأن بعض الصفحات قد تكون مغطاة عبر FAB.

**What is needed to verify**  
- مراجعة `FAB` وربطها بكل الصفحات التي تخفي create buttons
- اختبار mobile journey لكل صفحة رئيسية

**Release impact if confirmed**  
متوسط، وقد يصبح مرتفعًا إذا شمل flows أساسية غير مغطاة.

### NV-QUAL-01 — مدى اتساع debt الخاصة بـ inline styles و`@ts-nocheck`

**Why it looks concerning**  
التقرير الثانوي أشار إلى debt أوسع مما تحققنا منه مباشرة.

**Why it is not classified as confirmed here**  
ثبت لدينا وجود debt من هذا النوع، لكن ليس inventory الكامل لمدى اتساعه العددي.

**What is needed to verify**  
- grep inventory نهائي
- تصنيف حسب criticality وليس العدد فقط

**Release impact if confirmed**  
ليس blocker مباشر، لكنه مهم للسرعة والجودة طويلة الأمد.

---

## 6. مراجعة الواجهة وتجربة المستخدم

### 6.1 كسر وظيفي مؤكد

- الموبايل لا يملك بديلًا لإجراءات مهمة في `VisitPlanDetail` و`CallPlanDetail`
- بعض إجراءات الإشعارات على الموبايل صغيرة أكثر من اللازم وتتصادم مع row click behavior

### 6.2 تدهور UX مؤكد

- تبويبات الإشعارات على الموبايل فقدت fallback أكثر أمانًا
- واجهة الإشعارات تظل عرضة لـ accidental navigation بسبب قرب targets من row click

### 6.3 نقاط راجعناها صراحة

- mobile reachability
- dead-end flows
- hidden actions
- touch targets
- overflow/clipping
- tab usability
- destructive interactions
- permission-driven visibility
- user-intent alignment

### 6.4 الحكم العام على الواجهة

الواجهة ليست ضعيفة من حيث الأساس البصري أو البنية العامة، لكن التعديلات الحالية أظهرت pattern خطير: إصلاحات responsive قد تُغلق مسارات تشغيلية كاملة إذا لم تُربط دائمًا ببديل mobile. هذه ليست مشكلة تجميل، بل governance issue في طريقة اتخاذ قرارات الـ UI.

### 6.5 التوصية الاحترافية

- اعتماد قاعدة هندسية واضحة: أي إجراء `desktop-only` يجب أن يكون له mobile fallback معرف وصريح
- إضافة checklist UX قبل الدمج لأي تغييرات responsive تشمل:
  - هل ما زال الإجراء reachable؟
  - هل يمكن تنفيذه بإبهام واحد؟
  - هل هناك accidental destructive path؟
  - هل النية الأساسية للمستخدم ما زالت قابلة للإنجاز؟

---

## 7. مراجعة الأداء والقابلية للتوسع

### ما سينكسر أولًا

1. شاشات القوائم المفلترة التي تعتمد على post-pagination filtering
2. العمليات التسلسلية الطويلة من المتصفح مثل payroll batching
3. نوافذ stale data الناتجة عن invalidation gaps
4. counts/badges غير المتطابقة مع الحالة الحقيقية

### المواضع المؤكدة

- `getActivities`
- `getVisitPlans`
- `getCallPlans`
- `getUsers` عند الفلترة بالدور
- payroll browser-side orchestration
- missing sales realtime invalidation

### الحكم الهندسي

المشكلة الأكبر ليست "البطء" المجرد، بل أن بعض المسارات ستبدأ بإرجاع **نتائج خاطئة** قبل أن يشعر الفريق بوضوح بالبطء. وهذا أخطر من performance regression تقليدي، لأن المستخدم سيثق في بيانات غير صحيحة.

### التوصيات الاحترافية

- نقل كل relational filters المؤثرة على membership/count إلى DB layer
- تحويل browser-orchestrated batch work إلى server-side orchestration
- بناء invalidation matrix رسمية بدل map جزئية متنامية عشوائيًا
- إضافة اختبارات count/page correctness قبل أي توسع فعلي

---

## 8. مراجعة الأمن وحدود الثقة

### Release blockers

- ثغرة JWT forgery في `dispatch-notification`
- غياب authorization الحقيقي للـ browser callers
- caching غير آمن لطلبات Supabase الموثقة

### Hardening items

- فصل internal vs external trust paths
- منع أي privileged decision مبني على claims غير موثقة
- مراجعة CORS/security headers والـ service worker boundaries

### Lower-priority security debt

- توسيع contract tests الخاصة بالـ permissions
- مراجعة أشمل لمسارات internal caller identity

### الحكم العام

المشكلة الأمنية الحالية ليست "انتشار ثغرات صغيرة"، بل **تمركز شديد للمخاطر في نقاط محددة وحساسة**. وهذا جيد من جهة أن العلاج مركّز، لكنه خطير من جهة أن بقاء هذه النقاط دون إصلاح يمنع أي ثقة تشغيلية حقيقية.

---

## 9. مراجعة الاعتمادية والتشغيل

### العيوب المؤكدة

- forced sign-out عند transient profile lookup failure
- partial provisioning عند فشل role assignment
- stale views بسبب invalidation gaps
- unread badge drift بسبب optimistic side effects متعددة

### الأثر التشغيلي

- صعوبة دعم المستخدمين لأن بعض failures تظهر كسلوك business غامض لا كخطأ واضح
- احتمال تآكل الثقة في النظام عندما يرى المستخدم counts خاطئة أو جلسات تُغلق بلا داع
- زيادة تكلفة الدعم والتشخيص في بيئة تشغيل حية

### التوصية الاحترافية

- نمذجة failure modes بوضوح: auth failure != profile RPC failure
- جعل workflows الإدارية إما atomic أو compensating
- بناء observability checklist لاحقًا لمسارات auth/provisioning/notifications/realtime

---

## 10. مراجعة البنية والجودة الهندسية

### نقاط الضعف المؤكدة أو المرجحة بقوة

- permission identifiers غير موحدة بالكامل بين بعض الشاشات والمنظومة
- بعض المسارات الحرجة تعتمد على escape hatches خطرة مثل unverified claims أو client-side orchestration
- هناك دين واضح في responsive/UI governance بسبب `.desktop-only-btn`

### ديون هندسية يجب تتبعها

- inline styling debt على مستوى واسع
- `@ts-nocheck` أو equivalent unsafe bypasses في ملفات حرجة إن ثبتت بالكامل
- gaps بين query keys وrealtime invalidation map

### الحكم العام

البنية الأساسية جيدة بما يكفي للإنقاذ السريع نسبيًا، لكن استمرار هذه الديون دون systematization سيجعل كل تعديل مستقبلي أعلى مخاطرة وأبطأ تنفيذًا.

---

## 11. فجوات الاختبارات

### أعلى أولويات الاختبار

1. **Security regression**
- forged JWT rejection
- permission enforcement on dispatch
- authenticated API caching isolation behavior

2. **Correctness**
- pagination/filter/count tests لـ activities/plans/users
- create-user atomicity tests
- unread count consistency tests

3. **Auth stability**
- transient backend failure during bootstrap
- inactive vs active account paths

4. **Frontend UX regression**
- mobile action reachability on plan detail pages
- notification tabs under narrow widths
- notification action touch reliability

5. **Integration/E2E**
- notification end-to-end flow
- visit/call plan lifecycle
- provisioning + permissions visibility

### الحكم العام

أخطر ما في الوضع الحالي ليس فقط وجود bugs، بل أن جزءًا مهمًا منها يمكن أن يعود بسهولة بعد الإصلاح بسبب ضعف الحواجز الاختبارية.

---

## 12. خطة المعالجة المرحلية

### Phase 1 — الأمن و Release Blockers

**الهدف**  
إزالة أي ثغرة تمنع الإطلاق أو تكسر trust boundary مباشرة.

**البنود**

- EA-SEC-01
- EA-SEC-02
- EA-SEC-03
- EA-REL-01

**الأولوية**  
قصوى

**ناتج الإنجاز**

- notification dispatch مؤمن
- session bootstrap أكثر استقرارًا
- no cross-session replay عبر service worker

**مخاطر التنفيذ**

- احتمال كسر internal callers إذا لم تُحدّث آلية التوثيق بعناية

**التحقق بعد الإغلاق**

- integration tests
- smoke tests على auth + notifications

### Phase 2 — Correctness / State Integrity

**الهدف**  
إيقاف النتائج المضللة والـ partial-success workflows.

**البنود**

- EA-SCL-01
- EA-SCL-02
- EA-SCL-03
- EA-DAT-01
- EA-DAT-02
- EA-DOM-01

**الأولوية**  
عالية جدًا

**ناتج الإنجاز**

- counts/pages صحيحة
- provisioning موثوق
- notification state أدق
- permission visibility أكثر اتساقًا

**مخاطر التنفيذ**

- أي تعديل على query internals قد يغير ordering أو counts إذا لم يختبر جيدًا

**التحقق بعد الإغلاق**

- pagination correctness suite
- provisioning failure suite
- UI visibility tests

### Phase 3 — Scale / Performance

**الهدف**  
إزالة patterns التي ستنهار مع زيادة الحجم أو التزامن.

**البنود**

- EA-OPS-01
- EA-PERF-01
- مراجعة أوسع لـ invalidation matrix
- مراجعة أوسع للـ server-side batching opportunities

**الأولوية**  
عالية

**ناتج الإنجاز**

- stale windows أقل
- batch workflows أكثر تحملًا
- readiness أفضل للتوسع

**مخاطر التنفيذ**

- يتطلب تنسيقًا أفضل بين frontend والخدمات الخلفية/الـ RPCs

**التحقق بعد الإغلاق**

- cross-session update tests
- long-running workflow tests

### Phase 4 — UX / Maintainability Hardening

**الهدف**  
إغلاق dead ends وتحسين governance الخاصة بالواجهة وتقليل debt المؤسسي.

**البنود**

- EA-UX-01
- EA-UX-02
- EA-UX-03
- inventory أوسع لـ `.desktop-only-btn`
- debt reduction plan for styling/contracts

**الأولوية**  
متوسطة إلى عالية

**ناتج الإنجاز**

- mobile journeys مكتملة
- interaction reliability أفضل
- pattern governance أوضح

**مخاطر التنفيذ**

- منخفضة نسبيًا إذا حُفظت handlers الحالية وتم تعديل trigger surfaces فقط

**التحقق بعد الإغلاق**

- manual UX QA
- viewport regression pass

---

## 13. الحكم النهائي

### هل المشروع `production-ready`؟

لا، ليس بعد.

### ما المطلوب قبل `release`؟

- إصلاح ثغرات `dispatch-notification`
- تعطيل caching غير الآمن لطلبات Supabase الموثقة
- فصل transient auth/bootstrap failures عن sign-out path
- إصلاح post-pagination filtering في الخدمات الحرجة
- إعادة فتح المسارات التشغيلية الأساسية على الموبايل

### ما المطلوب قبل `scale-up`؟

- نقل batch orchestration الثقيلة إلى الخادم
- توسيع وإضفاء الطابع النظامي على realtime invalidation
- تثبيت correctness حول counts/pages/state drift
- تعزيز test coverage للمسارات الحرجة

### ما الذي يمكن تأجيله نسبيًا؟

- بعض ديون maintainability مثل inventory الكامل للـ inline styling debt
- التحسينات الأقل تأثيرًا التي لا تكسر مسارًا وظيفيًا أو أمنيًا مباشرًا

### الخلاصة

المشروع يملك أساسًا فنيًا يسمح بالوصول إلى حالة إنتاجية جيدة، لكن لا ينبغي التعامل مع الوضع الحالي على أنه "بحاجة لبعض التحسينات فقط". هناك defects مركزة وواضحة تمنع الثقة التشغيلية، لكنها قابلة للإصلاح دون إعادة بناء شاملة إذا نُفذت المعالجة بترتيب صحيح، مع الحفاظ على العقود الحالية واختبار المسارات الحرجة بصرامة.

