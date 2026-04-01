# HR Wave 1 Final Consistency Fix Prompt

استخدم هذا التوجيه حرفيًا مع كلود:

```text
المطلوب الآن هو:
HR Wave 1 Final Consistency Fix

هذه ليست مرحلة جديدة.
هذه مرحلة إغلاق نهائي صغيرة جدًا للموجة الأولى فقط.

العمل السابق في Wave 1 كان صحيح الاتجاه وفيه تقدم واضح، لكنه ليس مغلقًا بالكامل بعد.
المطلوب الآن هو إغلاق 3 نقاط محددة فقط، بدون توسيع النطاق، وبدون فتح Wave 2 أو Wave 3.

المراجع المعتمدة:
- specs/hr-module-final-audit-report.md
- specs/hr-module-phase-closure-plan.md
- specs/hr-wave1-execution-prompt.md

المشكلات المؤكدة من مراجعة الكود الفعلي:

1. PermissionsPage — mobile/desktop permission mismatch
في النسخة المكتبية من أدوات الموافقة تم استخدام:
- ['hr.permissions.approve', 'hr.attendance.approve']
لكن في بطاقات الموبايل ما زال PermissionGuard يعتمد فقط على:
- 'hr.attendance.approve'

النتيجة:
مستخدم يملك hr.permissions.approve فقط قد يرى/يستطيع الاعتماد على desktop ولا يراه على mobile.

المطلوب:
- توحيد صلاحية الاعتماد بين desktop وmobile
- لا أريد أي mismatch بين السطحين
- يجب أن تصبح أدوات الاعتماد role-consistent تمامًا

2. MyProfilePage — breadcrumb mismatch after route split
بعد جعل:
- /hr = Admin Workspace
- /hr/my-profile = Self-Service Hub

ما زالت breadcrumbs في MyProfilePage، وحتى في unlinked state، تشير إلى:
- /hr

النتيجة:
الموظف العادي قد يضغط breadcrumb طبيعيًا ثم يصطدم بمسار إداري مغلق.

المطلوب:
- إصلاح breadcrumbs في MyProfilePage بحيث تعكس الفصل الجديد بين admin workspace وself-service
- لا أريد breadcrumb يقود المستخدم الذاتي إلى مساحة إدارية غير مصرح بها
- اختر الصياغة/المسار الأنظف UX-wise ضمن البنية الحالية

3. Sidebar — reconsider placement of delegations
حالياً:
- "التفويضات" موجودة تحت "الخدمات الذاتية"

لكنها وظيفيًا أقرب إلى supervisor/admin approval tooling من كونها self-service.

المطلوب:
- راجع مكانها بعين product clarity
- إذا كان الصحيح نقلها إلى "الشئون الإدارية" فانقلها
- وإذا وجدت مبررًا قويًا لبقائها في self-service، فاذكره بوضوح في التقرير

لكن:
- لا أريد فلسفة عامة
- أريد قرارًا واضحًا clean UX-wise

قيود صارمة جدًا:
- لا تعدل أي شيء خارج:
  - src/pages/hr/permissions/PermissionsPage.tsx
  - src/pages/hr/MyProfilePage.tsx
  - src/components/layout/Sidebar.tsx
  إلا إذا كان هناك داعٍ مباشر جدًا وواضح
- لا تفتح Wave 2
- لا تضف features جديدة
- لا تعيد تصميم الصفحة
- لا تلمس App.tsx إلا إذا ظهر أن إصلاح breadcrumb يحتاجه مباشرة
- لا refactor واسع

التحقق الإلزامي:

A. PermissionsPage
- أدوات الاعتماد متطابقة permission-wise على desktop وmobile

B. MyProfilePage
- breadcrumbs لا تقود employee user إلى /hr الإداري بشكل مضلل

C. Sidebar
- تصنيف "التفويضات" يصبح منطقيًا product-wise

D. npm run build
- يجب أن ينجح

التسليم المطلوب:

1. ما الذي أصلحته بالضبط
2. لماذا كان كل خلل مهمًا
3. هل نقلت "التفويضات" أم أبقيتها، ولماذا
4. نتيجة npm run build

ابدأ الآن بهذه المرحلة فقط:
HR Wave 1 Final Consistency Fix
```
