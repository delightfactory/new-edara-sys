# HR Wave 1 Execution Prompt

استخدم هذا التوجيه حرفيًا مع كلود:

```text
المطلوب الآن هو:
HR Module Wave 1 Closure

هذه المرحلة ليست مراجعة جديدة، وليست refactor عام، وليست redesign شامل.
هذه مرحلة تنفيذ جراحية للموجة الأولى فقط من خطة إغلاق موديول HR.

الهدف:
إغلاق فجوات:
- route / permission precision
- role surface separation
- self-service journey clarity
- request/approve flow cleanliness

بدون فتح موجات لاحقة الآن، وبدون كسر أي تدفق قائم في الحضور أو الإجازات أو الأذونات أو الرواتب.

المراجع المعتمدة لهذه المرحلة:
- specs/hr-module-final-audit-report.md
- specs/hr-module-phase-closure-plan.md

التزم بهما باعتبارهما المرجع الوظيفي والمنتجي لهذه المرحلة.

قرارات المرحلة المعتمدة:

1. `/hr` يجب أن يصبح Admin Workspace فقط
2. `/hr/my-profile` يجب أن يصبح Self-Service Hub فقط
3. لا نضيف صلاحيات جديدة إلا إذا كانت ضرورية جدًا
4. نستخدم الموجود فعليًا في المشروع أولًا
5. لا نفتح Wave 2 أو Wave 3 الآن

نطاق التنفيذ الإلزامي:

1. Route / Sidebar Cleanup
راجع وعدّل فقط ما يلزم في:
- src/App.tsx
- src/components/layout/Sidebar.tsx

المطلوب:
- ضبط route `/hr` بحيث لا يكون مجرد ProtectedRoute عام، بل route إداري واضح
- مراجعة route `/hr/attendance` بحيث لا تعتمد على `hr.employees.read`
- استخدام الصلاحية الموجودة فعليًا `hr.attendance.read` إن كانت مناسبة
- التأكد أن `/hr/my-profile` يبقى متاحًا كمسار ذاتي للمستخدمين المسجلين
- إعادة تنظيم Sidebar في HR بحيث يصبح الفصل واضحًا بين:
  - Admin Tools
  - My Space / Self-Service

المهم:
- لا أريد كسر الوصول الحالي للمستخدمين الإداريين
- ولا أريد أن نفقد employee self-service
- ولا أريد broad permissions غير دقيقة

2. Permissions Page Cleanup
راجع وعدّل:
- src/pages/hr/permissions/PermissionsPage.tsx

المطلوب:
- فصل surface طلب الإذن عن surface المراجعة/الاعتماد
- لا يشترط فصل route جديد إذا كان tab/segmented surface داخل الصفحة أوضح وأنظف
- يجب أن تصبح الصفحة role-aware:
  - employee يرى request flow بوضوح
  - approver يرى review/approve flow بوضوح
- لا أريد مزجًا مربكًا بين request/approve/checkin في تجربة واحدة مسطحة

3. MyProfilePage Upgrade — Wave 1 Scope Only
راجع وعدّل:
- src/pages/hr/MyProfilePage.tsx

لكن انتبه:
هذه ليست مرحلة payslips ولا payroll history الكاملة.
هذه Wave 2.

المطلوب في Wave 1 فقط:
- تحويل الصفحة من “روابط سريعة فقط” إلى self-service hub أوضح
- تحسين empty/unlinked state ليصبح:
  - إرشاديًا
  - واضح الخطوة التالية
  - غير dead-end
- تحسين hierarchy وعرض المسارات الذاتية
- لو احتجت إضافة cards أو sectioning أفضل فافعل
لكن:
- لا تدخل في features جديدة كبيرة خارج النطاق

4. Permission Consistency Audit During Implementation
أثناء التنفيذ راجع consistency بين:
- route permissions
- sidebar permissions
- page-level PermissionGuards

المطلوب:
- لا تترك mismatch واضحًا بين من يرى الرابط ومن يستطيع فتح الصفحة
- لا تترك صفحة self-service تحتاج صلاحية إدارية ضمنية للوصول الطبيعي
- لا توسع النطاق إلى كل المشروع، فقط HR Wave 1 surfaces

5. قيود صارمة جدًا
- لا تفتح Wave 2
- لا تبني stepper للموظف الآن
- لا تبني Contract Management الآن
- لا تبني Offboarding الآن
- لا تبني Payslip Viewer الآن
- لا تفكك EmployeeProfile.tsx أو HRSettingsPage.tsx الآن
- لا تضف صلاحيات جديدة إذا كان الموجود يكفي
- وإذا اضطررت لإضافة صلاحية جديدة فعلًا، توقف واذكر السبب بوضوح في التقرير
- لا تعمل refactor واسع خارج الملفات المتأثرة مباشرة

6. أسئلة يجب أن تحسمها من الكود لا بالافتراض
قبل التعديل:
- هل `hr.attendance.read` مستخدمة فعلًا في constants/routes أم فقط معرفة؟
- هل `/hr` يجب أن تُربط بـ `hr.employees.read` أم هناك صلاحية أدق موجودة فعلًا؟
- هل `PermissionsPage` تخدم employee request + approver review في نفس الصفحة حاليًا؟ وكيف أنظفها بأقل تغيير ممكن؟

7. جودة التنفيذ المطلوبة
- لا أريد patch شكليًا
- لا أريد إعادة ترتيب sidebar فقط دون معالجة route precision
- لا أريد حلًا يضيق الوصول ويكسر self-service
- لا أريد حلًا يوسع الوصول بدافع الراحة
- المطلوب أقل تغيير يحقق أعلى clarity وأعلى safety

8. التحقق الإلزامي بعد التنفيذ
اختبر واذكر النتيجة على الأقل لهذه الحالات:

A. مستخدم HR/Admin
- يرى `/hr`
- يرى أدوات الإدارة في Sidebar
- يستطيع فتح attendance / payroll / permissions review

B. مستخدم Employee عادي
- يستطيع الوصول إلى `/hr/my-profile`
- لا يحصل على Admin Workspace إذا لم يملك صلاحياته
- يستطيع الوصول الطبيعي إلى self-service surfaces الخاصة به

C. Attendance route
- لا تبقى معتمدة على `hr.employees.read` إذا كان هذا mismatch

D. Permissions page
- request flow واضح
- approval flow واضح
- لا يوجد خلط مربك في نفس surface

E. Sidebar consistency
- ما يظهر في القائمة يتسق مع ما تسمح به routes

9. التسليم المطلوب
بعد التنفيذ سلّم:

أ. السبب الجذري المختصر الذي كانت تعالجه Wave 1
ب. ما الذي عدلته في:
   - App.tsx
   - Sidebar.tsx
   - PermissionsPage.tsx
   - MyProfilePage.tsx
   - وأي ملفات داعمة إن لزم
ج. كيف أصبح الفصل بين Admin Workspace وSelf-Service
د. كيف ضمنت consistency بين route / sidebar / page permissions
هـ. ما الذي تعمدت تأجيله لـ Wave 2 وWave 3
و. نتيجة npm run build

ابدأ الآن بهذه المرحلة فقط:
HR Module Wave 1 Closure
```
