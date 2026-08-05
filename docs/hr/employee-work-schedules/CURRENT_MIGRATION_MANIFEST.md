# Employee Work Schedules — Current Migration Manifest

> **المرجع الوحيد لترتيب التطبيق والمراجعة على الفرع الحالي.**
>
> لا يجيز هذا الملف تطبيق أي شيء على الإنتاج أو تفعيل الخاصية.

## ضوابط ثابتة

- قاعدة الإنتاج قراءة فقط.
- لا يتم تشغيل `hr.employee_work_schedules_enabled`.
- لا يتم إنشاء جداول لموظفين حقيقيين.
- لا يتم عمل Backfill للحضور القديم.
- لا يتم إنشاء Vercel Build أو Deployment تلقائي من الفرع.
- كل المحاكاة على قاعدة Disposable محلية وتنتهي بـ`ROLLBACK`.

## ترتيب الميجريشنات المعتمد

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

يجب إيقاف التطبيق فور فشل أي ملف، ولا يتم دمج الملفات في Migration واحدة كبيرة أثناء البروفة.

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

## المحاكاة السلوكية المعتمدة

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

## الفحص النهائي الوحيد

بعد رجوع كل المحاكاة وتشابه عدادات البيانات مع الـBaseline، يشغل فقط:

- `20260805222000_hr_employee_work_schedules_final_release_preflight.sql`

الملفات القديمة التالية ليست دليل إصدار نهائي ولا تُشغل ضمن المسار المعتمد:

- `20260805200000_hr_employee_work_schedules_final_disabled_preflight.sql`
- `20260805200100_hr_employee_work_schedules_final_duration_preflight.sql`
- `20260805200200_hr_employee_work_schedules_final_company_duration_preflight.sql`
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
- التشغيل يظل مطابقًا للنظام القديم والمفتاح مغلق.

## فحوص التطبيق بعد قاعدة البيانات

دون Deploy:

1. TypeScript type-check.
2. اختبارات `hrWorkSchedules.test.ts`.
3. الاختبارات الكاملة.
4. lint.
5. مراجعة فرق الفرع كاملًا.
6. التأكد أن `EmployeeProfileLegacy.tsx` مطابق لـ`main`.
7. التأكد من عدم إنشاء Vercel Deployment.

أي Preview أو تطبيق إنتاجي يحتاج قرارًا مستقلًا بعد نجاح جميع البنود السابقة.
