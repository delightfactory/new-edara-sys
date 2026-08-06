# Employee Work Schedules — Current Migration Manifest

> **المرجع الوحيد لترتيب التطبيق والمراجعة على الفرع الحالي.**
>
> لا يجيز هذا الملف تطبيق أي شيء على الإنتاج أو تفعيل الخاصية.

## ضوابط ثابتة

- قاعدة الإنتاج قراءة فقط.
- لا يتم تشغيل `hr.employee_work_schedules_enabled`.
- لا يتم إنشاء جداول لموظفين حقيقيين.
- لا يتم عمل Backfill للحضور أو الإجازات القديمة.
- لا يتم إعادة حساب أي مسير راتب قائم.
- لا يتم إنشاء Vercel Build أو Deployment تلقائي من الفرع.
- كل المحاكاة على قاعدة Disposable محلية وتنتهي بـ`ROLLBACK`.
- كل دفعة إصلاح مستقلة، ولا تبدأ الدفعة التالية قبل مراجعة ملفات الدفعة الحالية.

## حالة الدفعات

| الدفعة | النطاق | الحالة النظرية | التطبيق/التشغيل |
|---|---|---|---|
| الأساس | الجداول والحضور والجزاءات والراتب | موجود على الفرع | غير مطبق |
| 1 | تكامل الإجازات | منفذ على الفرع للمراجعة | غير مطبق وغير مشغّل على PostgreSQL |
| 2 | إعدادات الشركة المؤرخة والذرية | لم تبدأ | — |
| 3 | التقارير وكشوف الحضور | لم تبدأ | — |
| 4 | دورة حياة الموظف والجداول المستقبلية | لم تبدأ | — |
| 5 | تنبيهات الغياب والتصاريح | لم تبدأ | — |
| 6 | بوابة التفعيل النهائية | لم تبدأ | — |

## ترتيب الميجريشنات المعتمد حاليًا

1. `20260805143000_hr_employee_work_schedules_m1_schema.sql`
2. `20260805150000_hr_employee_work_schedules_m2_resolver.sql`
3. `20260805151500_hr_employee_work_schedules_m2_integrity.sql`
4. `20260805152500_hr_employee_work_schedules_m2_snapshot_hardening.sql`
5. `20260805160000_hr_employee_work_schedules_m3a_attendance_callers.sql`
6. `20260805161000_hr_employee_work_schedules_activation_guard.sql`
7. `20260805162000_hr_employee_work_schedules_m3b_legacy_gps_bridge.sql`
8. `20260805170000_hr_employee_work_schedules_m4a_absence_auto_checkout.sql`
9. `20260805173000_hr_employee_work_schedules_m4b_penalties_leave.sql`
10. `20260805180000_hr_employee_work_schedules_m4c_alerts_notifications.sql`
11. `20260805181500_hr_employee_work_schedules_m4d_late_shift_absence_dedupe.sql`
12. `20260805181600_hr_employee_work_schedules_absence_notification_grace.sql`
13. `20260805190000_hr_employee_work_schedules_m5_payroll.sql`
14. `20260805193000_hr_employee_work_schedules_future_edit_guard.sql`
15. `20260805193500_hr_employee_work_schedules_consistent_day_duration.sql`
16. `20260805193700_hr_employee_work_schedules_duration_change_month_boundary.sql`
17. `20260805193800_hr_employee_work_schedules_company_duration_boundary.sql`
18. `20260805194000_hr_employee_work_schedules_admin_context.sql`
19. `20260805210000_hr_employee_work_schedules_critical_review_fixes.sql`
20. `20260805210500_hr_employee_work_schedules_service_role_actor_guard.sql`
21. `20260805212000_hr_employee_work_schedules_attendance_metric_normalization.sql`
22. `20260805212100_hr_employee_work_schedules_permission_minute_alias_fix.sql`
23. `20260805213000_hr_employee_work_schedules_absence_notification_delivery_guard.sql`
24. `20260805215000_hr_employee_work_schedules_release_safety_fixes.sql`
25. `20260806180000_hr_employee_work_schedules_leave_integration.sql`
26. `20260806181000_hr_employee_work_schedules_leave_balance_settlement.sql`
27. `20260806181500_hr_employee_work_schedules_leave_cross_year_compatibility.sql`
28. `20260806181700_hr_employee_work_schedules_partial_unpaid_leave.sql`

يجب إيقاف التطبيق فور فشل أي ملف. لا يتم دمج الملفات في Migration واحدة كبيرة أثناء البروفة، ولا يتم تخطي Migration فاشلة بتعديل يدوي على قاعدة الاختبار.

## اختبارات المراحل

تشغل اختبارات كل مرحلة فور اكتمالها:

- `20260805143000_hr_employee_work_schedules_m1_verify.sql`
- `20260805151500_hr_employee_work_schedules_m2_verify.sql`
- `20260805161000_hr_employee_work_schedules_m3a_verify.sql`
- `20260805161100_hr_employee_work_schedules_activation_guard_simulation.sql`
- `20260805162000_hr_employee_work_schedules_m3b_verify.sql`
- `20260805170000_hr_employee_work_schedules_m4a_verify.sql`
- `20260805173000_hr_employee_work_schedules_m4b_verify.sql`
- `20260805180000_hr_employee_work_schedules_m4c_verify.sql`
- `20260805181500_hr_employee_work_schedules_m4d_verify.sql`
- `20260805181600_hr_employee_work_schedules_absence_notification_grace_verify.sql`
- `20260805190000_hr_employee_work_schedules_m5_verify.sql`
- `20260805193000_hr_employee_work_schedules_future_edit_verify.sql`
- `20260805193500_hr_employee_work_schedules_consistent_duration_verify.sql`
- `20260805193800_hr_employee_work_schedules_company_duration_verify.sql`
- `20260805194000_hr_employee_work_schedules_admin_context_verify.sql`
- `20260805211000_hr_employee_work_schedules_critical_review_fixes.sql`
- `20260805214000_hr_employee_work_schedules_attendance_normalization.sql`
- `20260805215100_hr_employee_work_schedules_release_safety_verify.sql`
- `20260806182000_hr_employee_work_schedules_leave_integration_verify.sql`

## المحاكاة السلوكية المعتمدة حاليًا

في جلسة Disposable فقط:

```sql
SET SESSION edara.allow_schedule_simulation = 'disposable-only';
```

ثم تشغل الملفات التالية، وكل ملف ينتهي بـ`ROLLBACK`:

1. `20260805200700_hr_employee_work_schedules_final_lifecycle_simulation.sql`
2. `20260805200600_hr_employee_work_schedules_company_and_transition_duration_simulation.sql`
3. `20260805201000_hr_employee_work_schedules_runtime_payroll_simulation.sql`
4. `20260805214500_hr_employee_work_schedules_offday_payroll_simulation.sql`
5. `20260805215200_hr_employee_work_schedules_permission_snapshot_simulation.sql`
6. `20260805215300_hr_employee_work_schedules_zero_day_partial_payroll_simulation.sql`
7. `20260806183000_hr_employee_work_schedules_leave_lifecycle_simulation.sql`
8. `20260806184000_hr_employee_work_schedules_unpaid_leave_payroll_simulation.sql`
9. `20260806185000_hr_employee_work_schedules_partial_unpaid_leave_simulation.sql`

## وضع الفحص النهائي

`20260805222000_hr_employee_work_schedules_final_release_preflight.sql` لم يعد فحص الإصدار النهائي المعتمد؛ لأنه أُنشئ قبل دفعة تكامل الإجازات والدفعات اللاحقة المخططة.

لا يوجد حاليًا Final Release Preflight صالح للتفعيل. يتم إنشاء فحص نهائي جديد فقط في الدفعة السادسة، بعد إغلاق:

- إعدادات الشركة المؤرخة والذرية.
- التقارير وكشوف الحضور.
- دورة حياة الموظف.
- التنبيهات والتصاريح.
- نتائج جولة المراجعة المستقلة التالية.

الملفات القديمة التالية ليست دليل إصدار نهائي ولا تُشغل ضمن مسار الإثبات النهائي:

- `20260805200000_hr_employee_work_schedules_final_disabled_preflight.sql`
- `20260805200100_hr_employee_work_schedules_final_duration_preflight.sql`
- `20260805200200_hr_employee_work_schedules_final_company_duration_preflight.sql`
- `20260805222000_hr_employee_work_schedules_final_release_preflight.sql`
- `20260805151500_hr_employee_work_schedules_m2_simulation.sql`
- `20260805193700_hr_employee_work_schedules_duration_boundary_simulation.sql`
- `20260805200500_hr_employee_work_schedules_lifecycle_simulation.sql`

## قواعد V1 المجمدة

- سبعة أيام فريدة، ويوم عمل واحد على الأقل.
- لا ورديات ليلية أو فترتين في اليوم أو تتبع راحة.
- مواعيد الأيام قد تختلف، لكن مدة يوم العمل ثابتة داخل نسخة الجدول.
- تغيير مدة اليوم يبدأ من أول الشهر.
- الموظف بلا جدول خاص يستخدم إعداد الشركة.
- العطلة الرسمية يوم غير مقرر ولا ينتج أثرًا ماليًا تلقائيًا.
- الحضور في يوم غير مقرر لا يعوض غياب يوم عمل.
- Auto Checkout لا يمنح إضافيًا ماليًا تلقائيًا.
- التصاريح المتداخلة تُحسب كاتحاد زمني واحد.
- Snapshot يوم الحضور غير قابلة للتغيير بعد تثبيتها.
- فترة لا تحتوي يوم عمل مقرر لا تُمنح يوم استحقاق وهميًا.
- أيام الإجازة تُحتسب خادميًا من أيام العمل المقررة فقط عند التفعيل.
- اعتماد الإجازة النهائي يزامن الحضور بعد حفظ الحالة، وبـSnapshot كاملة.
- الإجازة المدفوعة تدخل كاستحقاق مدفوع.
- الإجازة بدون أجر لا تدخل كحضور مدفوع ولا تنشئ جزاءً تلقائيًا.
- العمل الجزئي أثناء إجازة بدون أجر يُدفع بنسبة العمل الفعلية، والباقي إجازة معتمدة بلا جزاء.
- العمل الجزئي أثناء إجازة مدفوعة يظل يوم إجازة مدفوعًا وفق سياسة V1.
- طلب الإجازة العابر لنهاية السنة يظل متوافقًا مع سياسة النظام الحالية ويُحاسب على رصيد سنة البداية.
- التشغيل يظل مطابقًا للنظام القديم والمفتاح مغلق.

## فحوص التطبيق بعد قاعدة البيانات

دون Deploy:

1. TypeScript type-check.
2. اختبارات `hrWorkSchedules.test.ts`.
3. اختبارات شاشة الإجازات والـRPC preview.
4. الاختبارات الكاملة.
5. lint.
6. مراجعة فرق الفرع كاملًا.
7. التأكد أن `EmployeeProfileLegacy.tsx` مطابق لـ`main`.
8. التأكد من عدم إنشاء Vercel Deployment.

أي Preview أو تطبيق إنتاجي أو فتح Feature Flag يحتاج قرارًا مستقلًا بعد نجاح جميع الدفعات والفحوص.