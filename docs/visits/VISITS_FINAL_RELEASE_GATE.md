# VISITS_FINAL_RELEASE_GATE.md
> **بوابة المراجعة النهائية — موديول الزيارات الميدانية**
> التاريخ: 2026-07-24 | الحالة: 🔍 جاهز للمراجعة البشرية قبل التطبيق
> **ممنوع تطبيق أي Migration أو db push أو commit إلا بعد اعتماد هذه الوثيقة صراحةً.**

---

## 0. المتطلبات المسبقة قبل بدء التطبيق (Prerequisites)

يجب التأكد من وجود وكفاءة العوامل والمتطلبات التالية في قاعدة البيانات قبل البدء بتطبيق أي Migration مخصصة للزيارات:
- `01_foundation.sql` (البنية التحتية الأساسية والجداول المرجعية)
- `02_master_data.sql` (بيانات العملاء والفروع والموظفين)
- `17_hr_core.sql` (بيانات الموظفين `hr_employees`)
- `21_activities_module_mvp.sql` (الجداول الأصلية للأنشطة والزيارات `visit_plans` و `visit_plan_items`)
- `sales_orders` (جدول طلبات المبيعات للتحقق القرائي الاختياري عند ربط طلب بالزيارة)
- `payment_receipts` (جدول سندات التحصيل للتحقق القرائي الاختياري عند ربط تحصيل بالزيارة)
- امتداد `pgcrypto` (لتوليد دالة `digest` وتشفير التواقيع الذرية)
- دالة `public.check_permission(user_id, permission_code)` (نظام الصلاحيات RLS/ACL)

---

## 1. فهرس الملفات المعدّلة والجديدة وقواعد التتبع (Git Tracking)

### 1.1 Frontend — واجهات المستخدم
| حالة التتبع في Git | نوع التعديل | المسار | الوصف |
|---|---|---|---|
| Tracked | 🟡 معدّل | `src/pages/activities/VisitPlansPage.tsx` | قائمة خطط الزيارات + مسار atomic لإنشاء خطة |
| Tracked | 🟡 معدّل | `src/pages/activities/VisitPlanForm.tsx` | نموذج إنشاء خطة مع atomic/legacy path |
| Tracked | 🟡 معدّل | `src/pages/activities/VisitPlanDetail.tsx` | تفاصيل الخطة: تأكيد، إلغاء، إعادة جدولة، إنهاء يوم |
| Tracked | 🟡 معدّل | `src/pages/activities/VisitExecutionMode.tsx` | وضع التنفيذ الميداني: بدء، إكمال، تخطي، صور، استبيانات |
| Tracked | 🟡 معدّل | `src/pages/activities/ActivityForm.tsx` | إضافة دعم نوع النشاط visit |
| Untracked | 🟢 جديد | `src/pages/activities/components/VisitPlanItemEditor.tsx` | محرر بنود الخطة (إضافة/تعديل مضمّن) |
| Untracked | 🟢 جديد | `src/pages/activities/components/CancelGuardModal.tsx` | مودال تأكيد الإلغاء مع حماية |
| Untracked | 🟢 جديد | `src/pages/activities/visitPlanFormTypes.ts` | أنواع مدخلات نموذج الخطة |
| Untracked | 🟢 جديد | `src/pages/activities/visitPlanFormValidation.ts` | منطق تحقق نموذج الخطة |

### 1.2 IndexedDB / Offline / Photos — الطبقة اللا-اتصالية
| حالة التتبع في Git | نوع التعديل | المسار | الوصف |
|---|---|---|---|
| Untracked | 🟢 جديد | `src/lib/db/visitsDb.ts` | قاعدة Dexie: pendingVisitOperations, visitSessions, localBlobs |
| Untracked | 🟢 جديد | `src/lib/services/photoSyncService.ts` | خدمة رفع الصور للتخزين مع Retry/Backoff |
| Untracked | 🟢 جديد | `src/lib/config/features.ts` | فلاغ VISITS_ATOMIC_EXECUTION من env |

### 1.3 Types / Services / Hooks
| حالة التتبع في Git | نوع التعديل | المسار | الوصف |
|---|---|---|---|
| Tracked | 🟡 معدّل | `src/lib/types/activities.ts` | إضافة أنواع RPC الذرية، VisitRpcResult، VisitOperationName |
| Tracked | 🟡 معدّل | `src/lib/services/activities.ts` | إضافة 12 دالة atomic RPC + callVisitRpc + add/delete atomic |
| Untracked | 🟢 جديد | `src/hooks/useVisitExecutionSession.ts` | ربط IndexedDB بالمزامنة والصور والـ GPS |
| Untracked | 🟢 جديد | `src/hooks/useCustomerBranches.ts` | تحميل فروع العميل لنموذج الخطة |
| Tracked | 🟡 معدّل | `src/hooks/useQueryHooks.ts` | إضافة useMutation hooks لجميع RPCs الذرية |
| Tracked | 🟡 معدّل | `src/lib/permissions/constants.ts` | إضافة ثوابت صلاحيات visit_plans.* |
| Tracked | 🟡 معدّل | `src/components/shared/ActivityStatusBadge.tsx` | دعم حالات بنود الزيارات |
| Tracked | 🟡 معدّل | `src/components/shared/ChecklistForm.tsx` | دعم الاستبيانات الميدانية مع الصور |

### 1.4 Migrations — بالترتيب الزمني
| حالة التتبع في Git | نوع التعديل | الملف | المحتوى |
|---|---|---|---|
| Untracked | 🟢 جديد | `20260703134100_visits_foundation_schema.sql` | تعديل وتوسيع جداول `visit_plans`/`items` الأصلية من موديول 21 + إنشاء جداول الـ Idempotency والنزاعات في مخطط private |
| Untracked | 🟢 جديد | `20260704103808_visits_rls_state_machine.sql` | سياسات RLS + Triggers آلة الحالة + recalculate_visit_plan_counts |
| Untracked | 🟢 جديد | `20260704145447_visits_plan_atomic_rpcs.sql` | RPCs: إنشاء، تأكيد، إلغاء، إعادة ترتيب، إغلاق إداري |
| Untracked | 🟢 جديد | `20260705103803_visits_field_execution_atomic_rpcs.sql` | RPCs: بدء، إكمال، تخطي، إعادة جدولة + سياسات execute |
| Untracked | 🟢 جديد | `20260708114440_visits_plan_detail_gap_rpcs.sql` | RPCs: reschedule_to_date + close_visit_day_missed |
| Untracked | 🟢 جديد | `20260713134745_visit_proofs_storage.sql` | Storage bucket visit-proofs + سياسات الوصول |
| Untracked | 🟢 جديد | `20260724105031_visits_draft_item_atomic_rpcs.sql` | RPCs: add_visit_plan_item_atomic + delete_visit_plan_item_atomic |

### 1.5 Verification Contracts
| حالة التتبع | الملف | يفحص |
|---|---|---|
| Untracked | `supabase/verification/visits_preflight_audit.sql` | Schema consistency، RLS enabled، extensions |
| Untracked | `supabase/verification/visits_phase_b_schema_contract.sql` | هيكل الجداول، أعمدة، قيود NOT NULL |
| Untracked | `supabase/verification/visits_phase_c_rls_state_contract.sql` | وجود 4 سياسات vp_*/vpi_*، صحة triggers |
| Untracked | `supabase/verification/visits_phase_d_plan_rpcs_contract.sql` | وجود 5 RPCs خطة + توقيعاتها + SECURITY |
| Untracked | `supabase/verification/visits_phase_e_execution_rpcs_contract.sql` | وجود 4 RPCs تنفيذ + توقيعاتها + Statement-scoped DML/FOR UPDATE Regex Audit |
| Untracked | `supabase/verification/visits_phase_gap_plan_detail_rpcs_contract.sql` | وجود reschedule_to_date + close_day_missed |
| Untracked | `supabase/verification/visits_phase_photo_storage_contract.sql` | وجود bucket + سياسات storage |
| Untracked | `supabase/verification/visits_draft_item_atomic_rpcs_contract.sql` | وجود add/delete + لا ELSIF + لا medium + full signatures |

---

## 2. التسلسل اليدوي لتطبيق Migrations وعقود التحقق

> ⚠️ **يجب التوقف فوراً وعدم مواصلة الخطوات إذا أعادت أي خطوة صف مخالفة واحد أو Exception.**

```
[خطوة 0] تشغيل preflight audit قبل أي Migration:
    └─ supabase/verification/visits_preflight_audit.sql

[خطوة 1] تطبيق Foundation Migration ثم عقد التحقق B:
    ├─ 20260703134100_visits_foundation_schema.sql
    │  (تعديل وتوسيع جداول visit_plans/items الأصلية من Migration 21 + إنشاء جداول private)
    └─ supabase/verification/visits_phase_b_schema_contract.sql

[خطوة 2] تطبيق RLS & State Machine Migration ثم عقد التحقق C:
    ├─ 20260704103808_visits_rls_state_machine.sql
    └─ supabase/verification/visits_phase_c_rls_state_contract.sql

[خطوة 3] تطبيق Plan Atomic RPCs Migration ثم عقد التحقق D:
    ├─ 20260704145447_visits_plan_atomic_rpcs.sql
    └─ supabase/verification/visits_phase_d_plan_rpcs_contract.sql

[خطوة 4] تطبيق Field Execution RPCs Migration ثم عقد التحقق E:
    ├─ 20260705103803_visits_field_execution_atomic_rpcs.sql
    │  (يتضمن قراءة تحقق لحظية snapshot validation فقط من sales_orders و payment_receipts دون FOR UPDATE)
    └─ supabase/verification/visits_phase_e_execution_rpcs_contract.sql

[خطوة 5] تطبيق Gap RPCs Migration ثم عقد التحقق Gap:
    ├─ 20260708114440_visits_plan_detail_gap_rpcs.sql
    └─ supabase/verification/visits_phase_gap_plan_detail_rpcs_contract.sql

[خطوة 6] تطبيق Photo Storage Migration ثم عقد التحقق Photo:
    ├─ 20260713134745_visit_proofs_storage.sql
    └─ supabase/verification/visits_phase_photo_storage_contract.sql

[خطوة 7] تطبيق Draft Item RPCs Migration ثم عقد التحقق Draft Item:
    ├─ 20260724105031_visits_draft_item_atomic_rpcs.sql
    └─ supabase/verification/visits_draft_item_atomic_rpcs_contract.sql
```

---

## 3. نتائج التحقق الساكن المعماري والأمني

### 3.1 ✅ عزل Legacy عند VISITS_ATOMIC_EXECUTION=true
- **VisitPlanDetail.tsx**: كل `if (VISITS_ATOMIC_EXECUTION)` يستدعي مسار atomic، والـ `else` مخصص لـ legacy تحت شرط `!atomic` فقط.
- **VisitExecutionMode.tsx**: جميع فروع `!VISITS_ATOMIC_EXECUTION` تُنفذ حماية وقائية وتعرض شاشة حظر تمنع الدخول الهجين.
- **الحكم:** ✅ لا تسرب Legacy نشط عند تشغيل الفلاج الذري.

### 3.2 ✅ مطابقة RPCs والتوافق الكامل
- 13/13 RPC مستدعاة من `activities.ts` لها `CREATE OR REPLACE FUNCTION` مطابقة بالتوقيع والاسم والمخطط في ملفات المايجريشن 3، 4، 5، 7.
- لا توجد أي RPCs يتيمة مستدعاة في الواجهة بدون مايجريشن مسبقة.

### 3.3 ✅ الحدود والتبعيات مع موديولات النظام الأخرى
**لا توجد كتابة خارج موديول الزيارات؛ توجد قراءة تحقق اختيارية من طلبات البيع وسندات التحصيل دون قفل صفوفها.**
- تم إلغاء `FOR UPDATE` تماماً من استعلامات `sales_orders` و `payment_receipts` في `complete_visit_item_atomic_impl` لمنع أي تعطيل لقفل الصفوف على التدفقات التشغيلية للمبيعات والتحصيلات.
- تم تعزيز عقد التحقق `visits_phase_e_execution_rpcs_contract.sql` باختبارات ساكنة دقيقة تعتمد تعابير نمطية محددة العبارة `~*` لكشف أي كتابة DML أو استعلام `FOR UPDATE` على هذين الجدولين دون بلاغات كاذبة.

### 3.4 🔴 استبعاد صريح لموديول الرواتب و PayrollRunDetail
- **الواجهة:** تم تعديل `src/pages/hr/payroll/PayrollRunDetail.tsx` لخيار صلاحيات آخر في المستودع. **هذا الملف ليس جزءاً من موديول الزيارات ويجب استبعاده تماماً من حزمة commit / release الخاطفة للزيارات.**
- **المايجريشنز:** المايجريشنز التالية غير متتبعة وتخص الرواتب ويجب عدم إدراجها:
  - `20260613103203_fix_payroll_subcent_deficit_carryover.sql`
  - `20260613121500_fix_payroll_deficit_journal_balance.sql`

---

## 4. مصفوفة Smoke Test الإلزامية قبل اعتماد الإنتاج (في Staging)

> تُنفذ يدوياً في بيئة اختبار Staging تحتوي على التعديلات وقاعدة بيانات مُطبق عليها الخطوات من 0 إلى 7 مع تفعيل `VITE_VISITS_ATOMIC_EXECUTION=true` لغرض الاختبار.

| # | السيناريو | المسار | النتيجة المتوقعة |
|---|---|---|---|
| **SM-01** | إنشاء خطة | خطة جديدة (atomic) | إنشاء خطة بحالة `draft` وتوليد `operation_id` |
| **SM-02** | إضافة بند | إضافة عميل -> حفظ | إضافة بند بـ `sequence=1` وحالة `pending` |
| **SM-03** | حذف بند | حذف البند -> تأكيد | حذف البند وتحديث العدادات ذرية |
| **SM-04** | إعادة ترتيب | سحب وإفلات البنود -> حفظ | إعادة احتساب التسلسل بالترتيب الجديد |
| **SM-05** | تأكيد الخطة | تأكيد الخطة | تحول حالة الخطة إلى `confirmed` |
| **SM-06** | بدء زيارة | VisitExecutionMode -> بدء | تحول البند إلى `in_progress` وتسجيل الإحداثيات |
| **SM-07** | GPS fallback | تعطيل GPS -> بدء | المطالبة بمبرر استثناء موقع جغرافي |
| **SM-08** | رفع صورة | رفع صورة في استبيان | حفظ الصورة في `visit-proofs` وتسجيل المسار |
| **SM-09** | استبيان | إكمال بدون إجابة الاستبيان | الرفض ومنع الإكمال حتى استيفاء الأسئلة |
| **SM-10** | إكمال زيارة | إكمال الزيارة بنجاح | تحول البند إلى `completed` وتسجيل وقت الخادم |
| **SM-11** | تخطي زيارة | تخطي الزيارة مع مبرر | تحول البند إلى `skipped` وتسجيل المبرر |
| **SM-12** | إعادة جدولة | إعادة جدولة لتاريخ آخر | تحول البند الحالي وإنشاء بند جديد `pending` |
| **SM-13** | إنهاء اليوم (مكتمل) | إنهاء اليوم وبنوده مكتملة | تحول حالة الخطة إلى `completed` |
| **SM-14** | إنهاء اليوم (مستويات الحالات) | إنهاء اليوم عند وجود بنود غير مكتملة (missed) | **تحول بنود الخطة المتبقية إلى `missed`؛ وحالة الخطة تُحسب بدقة:**<br>• جميع البنود missed => حالة الخطة `missed`<br>• بنود completed + missed => حالة الخطة `partial`<br>• جميع البنود completed => حالة الخطة `completed` |
| **SM-15** | إلغاء الخطة | إلغاء خطة مسودة | تحول الخطة إلى `cancelled` وتسجيل السبب |
| **SM-16** | Double-click | ضغط متكرر على زر التأكيد | منع الاستدعاءات المزدوجة بفضل Lock و Idempotency |
| **SM-17** | Offline -> Sync | تنفيذ عمليات بدون شبكة ثم الاتصال | تخزين العمليات في IndexedDB ثم المزامنة التلقائية |
| **SM-18** | Idempotency | إعادة استخدام نفس operation_id | إرجاع النتيجة السابقة بـ `replayed: true` |
| **SM-19** | فحص الصلاحيات | محاولة تنفيذ RPC بدون صلاحية | الرفض الفوري بـ EXCEPTION صريح |
| **SM-20** | فحص النطاق | محاولة تعديل خطة مندوب فرع آخر | الرفض بحظر الوصول للنطاق غير المصرح |

---

## 5. قائمة تحقق الإصدار النهائية (Release Checklist)

- [ ] نجاح build نهائي واحد للكود المحدد للإصدار (`npm run build`).
- [ ] التأكد من وجود المتطلبات المسبقة 01, 02, 17, 21 و check_permission.
- [ ] تنفيذ التسلسل اليدوي للمايجريشنز وعقود التحقق من 0 إلى 7 في Staging.
- [ ] تنفيذ SM-01 إلى SM-20 في Staging وتسجيل النتائج بنجاح.
- [ ] إبقاء `VITE_VISITS_ATOMIC_EXECUTION=false` في بيئة الإنتاج حتى اكتمال المايجريشنز والعقود واختبارات Smoke واعتماد المستخدم الصريح.
- [ ] تفعيل الفلاج `VITE_VISITS_ATOMIC_EXECUTION=true` في الإنتاج يحتاج إذنًا منفصلًا وصريحًا بعد النشر.
- [ ] استبعاد `src/pages/hr/payroll/PayrollRunDetail.tsx` تماماً من commit الزيارات.
- [ ] استبعاد مايجريشنز الرواتب `20260613*` من commit الزيارات.
- [ ] Storage bucket `visit-proofs` موجود أو تم إنشاؤه عبر مايجريشن [6].

---

> 📌 **الحالة:** جاهز للتنفيذ اليدوي والمراجعة البشرية. ممنوع التطبيق التلقائي أو الـ Commit بدون موافقة صريحة.
