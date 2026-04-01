# HR Inferential Dead-End Audit

## Executive Verdict
موديول HR أصبح أقوى بكثير بعد Waves السابقة، لكن هذه الجولة الاستدلالية تؤكد أنه **ليس مغلقًا بالكامل على مستوى المرجعيات والسياق**.  
الحكم الحالي:

- البنية والرحلات الأساسية: قوية
- self-service والإدارة اليومية: جيدة
- طبقة `unsupported references / contextual filtering`: ما زالت تحتوي فجوات حقيقية
- الدرجة العامة في هذه العدسة: **B+**

أكبر مشكلة لم تعد “نقص feature كبيرة”، بل **أن بعض الحقول والاختيارات تعتمد على مرجعيات أو أهلية سياقية لا تمثلها الواجهة أو لا تديرها أصلًا**.

## Findings

### P1. أنواع الإجازات تُستهلك في self-service بلا أي surface إدارة فعلية
- النوع: `unsupported reference`
- [LeaveRequestForm.tsx](C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\pages\hr\leaves\LeaveRequestForm.tsx) يبني رحلة الطلب كاملة فوق `useHRLeaveTypes()` ويعرض خصائص مرجعية مثل:
  - `is_paid`
  - `has_balance`
  - `requires_document`
  - `max_days_per_year`
- لكن في [HRSettingsPage.tsx](C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\pages\hr\settings\HRSettingsPage.tsx) لا يوجد أي tab لإدارة `leave types` أصلًا؛ التبويبات تنتهي عند:
  - settings
  - departments
  - positions
  - locations
  - holidays
  - penalties
- وفي [hr.ts](C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\lib\services\hr.ts) يوجد فقط `getLeaveTypes()` دون create/update/delete مقابلة.
- الأثر: أي تغيير في أنواع الإجازات أو خصائصها التشغيلية ما زال يحتاج تدخلًا خارج surface الإدارة، رغم أنها تظهر مباشرة للموظف في self-service.

### P1. أهلية أنواع الإجازات لا تُصفّى سياقيًا بحسب جنس الموظف أو وضعه
- النوع: `context mismatch`
- [LeaveRequestForm.tsx](C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\pages\hr\leaves\LeaveRequestForm.tsx) تعرض جميع `leaveTypes.map(...)` بدون أي contextual filtering.
- [hr.ts](C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\lib\services\hr.ts) تُرجع الأنواع active-only فقط، لكنها لا تأخذ employee context.
- [hr.ts](C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\lib\types\hr.ts) تعرف `HRGender` وتعرف `HRLeaveType`، لكن `HRLeaveType` لا تحمل أي eligibility fields مرتبطة بالجنس أو الحالة.
- الأثر: الواجهة لا تملك حتى vocabulary كافية لتمنع ظهور إجازة أمومة/وضع لموظف مسجل كذكر. هذا ليس bug عرض فقط، بل gap في تمثيل قواعد الأهلية نفسها.

### P2. دورة حياة المسميات الوظيفية ما زالت ناقصة رغم وجود surface إدارة
- النوع: `reference lifecycle gap`
- [EmployeeForm.tsx](C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\pages\hr\employees\EmployeeForm.tsx) تعتمد على `position_id` وتستهلك قائمة المسميات في create/edit.
- [HRSettingsPage.tsx](C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\pages\hr\settings\HRSettingsPage.tsx) تعرض تبويب `positions`، لكن query نفسها تستخدم `getPositions()` فقط.
- [hr.ts](C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\lib\services\hr.ts) تجعل `getPositions()` active-only بشكل صريح عبر `.eq('is_active', true)`.
- النتيجة:
  - surface الإدارة لا ترى المسميات المعطلة
  - لا يوجد path لإعادة تفعيلها
  - الجدول يعرض badge “موقوف” نظريًا، لكن مصدر البيانات نفسه لا يجلب الموقوف أصلًا
- الأثر: lifecycle المرجعية للمسمى ليست مكتملة، رغم أن الحقل مركزي داخل employee lifecycle.

### P2. صفحة إدارة الإجازات تفترض أن مرجعيات الأنواع صحيحة مسبقًا بدل أن تكشف mismatch eligibility
- النوع: `dead-end journey`
- [LeavesPage.tsx](C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\pages\hr\leaves\LeavesPage.tsx) تغلق رحلة التقديم والمراجعة جيدًا، لكنها لا تكشف أي warning إذا كان نوع الإجازة الظاهر للموظف غير مناسب لسياقه.
- [LeaveRequestForm.tsx](C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\pages\hr\leaves\LeaveRequestForm.tsx) تعطي للمستخدم impression أن كل ما في القائمة صالح له.
- الأثر: لو كان backend يرفض لاحقًا، فسيبدو الرفض arbitrary للمستخدم. ولو لم يرفض، فنحن أمام inconsistency منطقية صريحة.

### P3. مرجعيات HR ليست متساوية في النضج الإداري
- النوع: `cross-surface inconsistency`
- داخل [HRSettingsPage.tsx](C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\pages\hr\settings\HRSettingsPage.tsx):
  - departments: include inactive
  - positions: active-only
  - locations: لها create/update/delete
  - holidays: create/delete
  - leave types: غائبة
- الأثر: خبرة المدير داخل إعدادات HR ليست متسقة؛ بعض المرجعيات قابلة للإدارة lifecycle-wise، وبعضها نصف مغلق، وبعضها غير موجود أصلًا.

## Unsupported References
- `hr_leave_types`
  - تُستهلك في self-service requests
  - لا يوجد لها surface إدارة داخل HR settings
  - لا توجد services CRUD مقابلة في الواجهة الحالية
- `hr_positions`
  - لها surface إدارة، لكن lifecycle ناقصة بسبب active-only listing
- قواعد eligibility لأنواع الإجازات
  - غير ممثلة في types/services/forms
  - وبالتالي غير قابلة للإدارة أو التصفية

## Context-Mismatch Findings
- `LeaveRequestForm` تعرض أنواع الإجازات بدون employee-context filtering.
- `HRLeaveType` لا تحمل حقول أهلية تسمح أصلًا بتصفية النوع بحسب gender/status.
- تجربة الموظف تفترض أن “ما أراه = ما يحق لي طلبه”، وهذا غير مضمون منطقيًا حاليًا.

## Dead-End Journeys
- رحلة “تغيير/ضبط نوع إجازة” تنتهي خارج المنتج؛ لا يوجد surface إدارة.
- رحلة “إعادة تفعيل مسمى وظيفي موقوف” غير موجودة فعليًا من surface الإدارة الحالية.
- رحلة “معرفة لماذا يظهر لي هذا النوع من الإجازة أصلًا” غير موجودة للمستخدم ولا للإداري.

## Cross-Surface Inconsistencies
- employee create/edit تستهلك `positions` كمرجعية أساسية، بينما settings لا تدير lifecycle الخاصة بها بالكامل.
- self-service leave request تعتمد على `leave types`, لكن admin settings لا تحتوي مرجعيتها أصلًا.
- بعض المرجعيات في HR settings lifecycle-complete، وبعضها لا يزال half-managed.

## Prioritized Closure Pack

### Wave X1 — Leave Type Governance
- إضافة surface إدارة فعلية لـ `leave types` داخل HR settings
- دعم CRUD + active/inactive lifecycle
- عرض الخصائص التشغيلية الحالية بوضوح:
  - paid/unpaid
  - balance-backed
  - requires document
  - affects salary

### Wave X2 — Leave Eligibility Filtering
- تمثيل eligibility rules لأنواع الإجازات بشكل صريح في model/service layer
- تصفية الأنواع في `LeaveRequestForm` بحسب employee context
- إضافة guard explanatory إذا كان النوع غير صالح لسياق الموظف

### Wave X3 — Position Lifecycle Completion
- تعديل `getPositions()` أو إضافة admin mode/includeInactive
- جعل `PositionsTab` ترى active + inactive
- إضافة path واضح لإعادة التفعيل بدل الاكتفاء بالـ soft delete
