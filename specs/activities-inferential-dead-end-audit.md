# Activities Inferential Dead-End Audit

## Executive Verdict
موديول Activities أصبح قويًا جدًا وظيفيًا بعد Wave A وWave B، لكن الجولة الاستدلالية تكشف أن **طبقة المرجعيات وسلامة الاستهلاك ليست مغلقة بالكامل**.  
الحكم الحالي:

- الرحلات التشغيلية الأساسية: قوية
- surface الإدارة للـ checklists/templates: جيدة
- المرجعيات الأساسية (activity types / target types): ما زالت backend-only عمليًا
- بعض surfaces الإدارية تنتج خيارات لا تملك execution journey كاملة
- الدرجة العامة في هذه العدسة: **B+**

## Findings

### P1. `activity_types` مرجعية أساسية للنشاط بلا surface إدارة مقابلة
- النوع: `unsupported reference`
- [ActivityForm.tsx](C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\pages\activities\ActivityForm.tsx) تعتمد مباشرة على `useActivityTypes()` لاختيار نوع النشاط.
- [activities.ts](C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\lib\services\activities.ts) تحتوي `getActivityTypes()` فقط، active-only.
- لا يوجد في [App.tsx](C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\App.tsx) أو [Sidebar.tsx](C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\components\layout\Sidebar.tsx) أي route أو surface لإدارة activity types.
- الأثر: نوع النشاط مرجعية core تؤثر على create flow، لكن lifecycle الإدارية لها خارج المنتج.

### P1. `target_types` مرجعية أساسية للأهداف بلا surface إدارة مقابلة
- النوع: `unsupported reference`
- [TargetForm.tsx](C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\pages\activities\TargetForm.tsx) تعتمد على `useTargetTypes()` منذ بداية create flow.
- [activities.ts](C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\lib\services\activities.ts) تحتوي `getTargetTypes()` فقط، active-only.
- لا يوجد أي surface إدارة مقابلة في routes أو sidebar.
- الأثر: المدير ينشئ target بناءً على reference data لا يمكنه إدارتها من نفس المنتج، وهذا dead-end إداري واضح.

### P1. شاشة إدارة checklists تسمح بإنشاء قوالب لفئات لا نرى لها رحلة تنفيذ فعلية
- النوع: `context mismatch`
- [ChecklistTemplatesPage.tsx](C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\pages\activities\ChecklistTemplatesPage.tsx) تسمح بإنشاء قوالب لفئات:
  - `visit`
  - `call`
  - `task`
- لكن استهلاك `useChecklistTemplates()` داخل صفحات الأنشطة يظهر فعليًا في:
  - [VisitExecutionMode.tsx](C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\pages\activities\VisitExecutionMode.tsx)
  - [ActivityDetail.tsx](C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\pages\activities\ActivityDetail.tsx) للعرض
- لا توجد surface تنفيذ موازية واضحة للمكالمات أو المهام تستعمل checklists مثلما تفعل الزيارات.
- الأثر: الإدارة الحالية قد تُنتج templates لـ `call/task` دون execution journey مكتملة، فتتحول الميزة إلى مرجعية orphaned جزئيًا.

### P2. `ActivityForm` تربط outcomes بالـ category بشكل hardcoded لا بالمرجعية نفسها
- النوع: `logic mismatch`
- [ActivityForm.tsx](C:\Users\HP\OneDrive\Desktop\new-edara-sys\src\pages\activities\ActivityForm.tsx) تعرف قوائم outcomes ثابتة محليًا:
  - `OUTCOME_VISIT_OPTIONS`
  - `OUTCOME_CALL_OPTIONS`
  - `OUTCOME_TASK_OPTIONS`
- بينما نوع النشاط نفسه يأتي من `activity_types` كمرجعية backend.
- الأثر: حتى لو أصبحت `activity_types` قابلة للإدارة لاحقًا، فإن allowed outcomes ما زالت مشفرة محليًا في الواجهة. هذا يخلق coupling خفيًا بين reference data ومنطق form.

### P2. الإدارة في Activities ناضجة لبعض المرجعيات ومغلقة تمامًا لمرجعيات أخرى
- النوع: `cross-surface inconsistency`
- لدينا الآن surface إدارة لـ:
  - checklists
  - plan templates
- لكن لا توجد إدارة لـ:
  - activity types
  - target types
- الأثر: خبرة المدير داخل Activities غير متجانسة؛ بعض المرجعيات أصبحت fully managed، وبعض المرجعيات الأكثر مركزية ما زالت read-only ضمنيًا.

## Unsupported References
- `activity_types`
  - تُستهلك مباشرة في ActivityForm وVisitExecutionMode
  - لا يوجد لها admin surface
- `target_types`
  - تُستهلك مباشرة في TargetForm وTargets flows
  - لا يوجد لها admin surface
- allowed outcomes by category
  - ممثلة في form logic لا في reference management

## Context-Mismatch Findings
- `ChecklistTemplatesPage` تسمح بإدارة `call/task` checklists رغم أن execution journey الواضحة حاليًا هي visit-first.
- `ActivityForm` تعرض outcomes بحسب category hardcoded، لا بحسب type-specific policy قابلة للإدارة.

## Dead-End Journeys
- رحلة “إضافة نوع نشاط جديد أو تعديل نشاط قائم مرجعيًا” غير موجودة.
- رحلة “إضافة نوع هدف جديد أو تعديل خصائصه المرجعية” غير موجودة.
- رحلة “إنشاء checklist للمكالمات/المهام ثم استهلاكها عمليًا” غير مثبتة مثل رحلة الزيارات، ما يجعلها dead-end محتملة.

## Cross-Surface Inconsistencies
- checklists/templates في Activities أصبحت managed، بينما activity/target types بقيت unmanaged.
- forms تعتمد على reference data backend، لكن الإدارة لا تملك نفس المستوى من التحكم في جميع المرجعيات.
- category-driven outcomes في ActivityForm لا تتبع model مركزيًا، ما يجعل سلوك form أقل شفافية من المرجعيات التي تبنيها.

## Prioritized Closure Pack

### Wave Y1 — Reference Governance
- إنشاء surface إدارية خفيفة لـ:
  - activity types
  - target types
- يكفي في البداية lifecycle أساسية:
  - create/update/activate/deactivate
  - ترتيب/ظهور

### Wave Y2 — Checklist Scope Honesty
- إما تقييد checklist categories في الإدارة إلى ما يملك execution journey فعلية الآن
- أو بناء/توضيح execution surfaces للمكالمات والمهام إن كانت مدعومة فعلًا
- الهدف: لا نسمح للإدارة بإنشاء reference data بلا استهلاك حقيقي

### Wave Y3 — Outcome Policy Normalization
- تقليل hardcoded outcome logic في `ActivityForm`
- ربط allowed outcomes بسياسة مرجعية أو type-aware mapping أكثر وضوحًا
- حتى لا تبقى form معتمدة على knowledge محلي لا يمكن للإدارة التحكم فيه
