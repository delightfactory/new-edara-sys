# توجيه التنفيذ الرسمي لأداة التطوير

تاريخ الوثيقة: 2026-04-17

## الغرض

هذه الوثيقة هي **التوجيه التنفيذي الرسمي** لأداة التطوير لتنفيذ منصة الطباعة والتصدير داخل مشروع EDARA وفق القرار المعماري المعتمد، وبدون إعادة فتح النقاش المعماري أو الرجوع إلى افتراضات `MVP` أو `prototype`.

المرجع المعتمد الذي يجب الالتزام به بالكامل:

- `c:\Users\HP\OneDrive\Desktop\new-edara-sys\specs\print-export-production-grade-study-2026-04-17.md`

هذه الوثيقة ليست طلب مراجعة، وليست دراسة، وليست brainstorming.

إنها أمر تنفيذ مباشر.

---

## الأمر التنفيذي

أنت الآن مسؤول عن **تنفيذ منصة الإخراج المستندي الكاملة** داخل مشروع EDARA، وفق الوثيقة المعتمدة المشار إليها أعلاه.

مهم جدًا:

- لا تعيد تقييم المعمارية من الصفر.
- لا تطرح بدائل جديدة إلا إذا ظهر blocker تنفيذي حقيقي يمنع التنفيذ.
- لا تختصر التنفيذ إلى نسخة أولية أو مؤقتة.
- لا تنفذ حلولًا محلية داخل الصفحات الحالية.
- لا تربط الطباعة أو التصدير مباشرة بصفحات UI التفاعلية.
- لا تكسر الأداء، ولا تضخم الحزمة الأساسية، ولا تضف imports ثقيلة إلى main bundle.
- يجب أن يكون التنفيذ **Production-grade** منذ البداية.

---

## الهدف النهائي المطلوب

تنفيذ **Output Platform** مركزية داخل المشروع، تدعم:

- Preview
- Print
- PDF عبر 3 tiers
- CSV
- XLSX
- Paper profiles
- Canonical Document Model
- Document registry
- Branding resolver
- Output orchestration
- Security policy
- Performance budgets
- Web Workers

بحيث تصبح قابلة للاستدعاء من:

- `PaymentReceiptDetail`
- `SalesOrderDetail`
- `Reports pages`
- أي مستندات مستقبلية

---

## المطلوب من أداة التطوير

نفّذ العمل على شكل **مراحل تنفيذ فعلية متسلسلة** داخل الكود، مع الحفاظ على الاستقرار وإمكانية التحقق بعد كل مرحلة.

يجب أن يكون الترتيب تنفيذيًا صارمًا كما يلي:

### المرحلة 1 — Scaffold المنصة الأساسية

أنشئ feature جديدة داخل:

```text
src/features/output/
```

ويجب أن تتضمن على الأقل:

```text
src/features/output/
  core/
  models/
  branding/
  paper-profiles/
  definitions/
  renderers/
  orchestrator/
  services/
  components/
  hooks/
  styles/
  workers/
```

في هذه المرحلة يجب تثبيت:

- `DocumentKind`
- `OutputKind`
- `PaperProfileId`
- `OutputTier`
- `CanonicalDocument`
- أنواع sections, columns, totals, approvals
- `DocumentDefinition`
- `PaperProfile`
- `OutputRequest`
- `OutputResult`

مهم:

- `OutputKind` يجب أن يعكس tiers المعتمدة:
  - `print`
  - `pdf-browser`
  - `pdf-download`
  - `pdf-archive`
  - `csv`
  - `xlsx`

### المرحلة 2 — Branding وPaper Profiles

نفّذ:

- `branding-resolver`
- تحميل بيانات الشركة من `company_settings`
- تطبيعها إلى `CompanyBranding`
- cache محسوب للبيانات

ونفّذ:

- paper profiles الرسمية:
  - `a4-portrait`
  - `a4-landscape`
  - `letter-portrait`
  - `legal-portrait`
  - `thermal-58mm`
  - `thermal-80mm`

يجب أن تشمل profiles:

- size
- orientation
- margins
- fontScale
- pageNumbering
- header/footer policy
- thermal constraints

### المرحلة 3 — HTML/Print Renderer الأساسي

نفّذ renderer موحدًا للمستندات يعتمد على `CanonicalDocument`.

المطلوب:

- Standard document layout
- Thermal layout
- Report layout
- print styles منفصلة
- آلية `position: fixed` للـ headers/footers
- عدم الاعتماد على `@page margin boxes` كآلية رئيسية
- دعم `RTL/LTR`
- دعم mixed-direction fields

أنشئ على الأقل:

- `DocumentRenderer`
- `StandardLayout`
- `ThermalLayout`
- `ReportLayout`
- `print-base.css`
- `print-a4.css`
- `print-thermal.css`
- `print-report.css`

### المرحلة 4 — Preview وPrint Services

نفّذ:

- `DocumentPreview` / preview route architecture
- `PrintSurface`
- `browser-print-service`
- wrapper آمن لـ `window.print()`
- hooks أو services لـ:
  - beforeprint
  - afterprint
  - loading states
  - cleanup states

يجب أن تكون المعاينة:

- منفصلة عن الصفحة الأصلية
- نظيفة
- قابلة للطباعة
- مناسبة للهاتف والديسكتوب

### المرحلة 5 — Document Registry وDefinitions

ثبّت registry مركزية للمستندات.

يجب أن تحتوي كل definition على:

- kind
- default paper
- supported outputs
- supported papers
- isArchivable
- maxSyncPages
- fetchAndBuild
- exportSchema عند الحاجة

ابدأ بأول definitions فعلية:

- `payment-receipt`
- `sales-order`
- `sales-invoice` إذا لزم الفصل
- `report`

مهم:

- لا تنقل UI logic من الصفحات إلى definitions
- definitions مسؤولة فقط عن fetch/build/output preparation

### المرحلة 6 — دمج فعلي مع الشاشات الحالية

ابدأ الربط مع:

- `PaymentReceiptDetail`
- `SalesOrderDetail`
- صفحة تقارير واحدة على الأقل

المبدأ:

- الصفحة الأصلية تبقى تشغيلية وتفاعلية
- تضاف لها `DocumentActions`
- لا يُكتب print/export logic محلي داخل الصفحة

أعد استخدام ما يصلح من utilities الحالية مثل:

- formatting helpers
- date helpers
- currency formatting

لكن لا تعيد استخدام DOM الصفحة الحالية كمستند.

### المرحلة 7 — CSV Exporter

نفّذ CSV exporter رسميًا عبر schema-based mapping.

المطلوب:

- BOM
- escaping صحيح
- raw/formatted values
- headers واضحة
- filename conventions
- احترام العربية
- احترام الأذونات

إذا تجاوز الحجم الحدود المحددة، استخدم:

- `csv-worker.ts`

### المرحلة 8 — XLSX Exporter

نفّذ XLSX عبر:

- `exceljs`

شروط صارمة:

- lazy-loaded فقط
- لا import داخل main bundle
- Web Worker للأحمال الثقيلة
- column typing
- sheet naming
- widths
- formatting
- multi-sheet support عند اللزوم

أنشئ:

- `xlsx-exporter.ts`
- `xlsx-worker.ts`

### المرحلة 9 — PDF Tiers

نفّذ tiers كما يلي:

#### Tier 1

- Browser print / save as PDF
- مدعوم من أول يوم

#### Tier 2

- `@react-pdf/renderer`
- lazy-loaded فقط
- للمستندات الفردية والبسيطة/المتوسطة
- مع تضمين Arabic font صريح

#### Tier 3

- لا تنفذ service كاملة الآن إذا لم تكن ضمن النطاق الفعلي المباشر
- لكن نفّذ:
  - contract
  - client integration placeholder
  - request/response shape
  - trigger conditions

بحيث يصبح تفعيل Tier 3 لاحقًا مباشرًا.

### المرحلة 10 — Output Orchestrator

نفّذ Orchestrator مركزيًا يقرر:

- أي output path يُستخدم
- هل التنفيذ sync أو async
- هل يستخدم worker
- هل يستخدم browser
- هل يستخدم Tier 2
- هل يكتفي placeholder لـ Tier 3

مهم:

- القرار يجب أن يعتمد على:
  - document kind
  - output kind
  - page count
  - row count
  - budgets

### المرحلة 11 — Security and Permissions

نفّذ سياسة الأمان بالكامل كما تم اعتمادها:

- Preview route محمية
- artifacts عبر signed URLs فقط
- عدم تخزين download URLs طويلًا في client state
- احترام RLS/permission scope
- لا يُصدّر أي حقل لا يملك المستخدم صلاحية رؤيته

مهم:

- هذه ليست طبقة لاحقة
- يجب تنفيذها أثناء بناء المنصة وليس بعد اكتمالها

### المرحلة 12 — Performance Enforcement

يجب فرض budgets المعتمدة داخل التنفيذ:

- لا مكتبات ثقيلة في main bundle
- lazy loading للمكتبات الثقيلة
- Web Workers عند الحاجة
- cleanup للـ Blob URLs
- عدم تخزين canonical docs الضخمة في global state
- عدم تحميل صفوف ضخمة للواجهة فقط بغرض التصدير

راقب خصوصًا:

- output core module size
- preview render time
- PDF Tier 2 generation time
- CSV/XLSX thresholds

### المرحلة 13 — Observability

أضف metrics واضحة لمنصة الإخراج:

- output started
- output completed
- output failed
- duration
- file size
- page count
- row count
- selected tier

استخدم ما هو متاح حاليًا في المشروع مثل:

- Sentry أو ما يعادله إن كان موجودًا

### المرحلة 14 — Testing

نفّذ اختبارات فعلية تغطي على الأقل:

#### Unit tests

- canonical builders
- registry
- paper profiles
- output policy decisions
- csv exporter
- xlsx export mapping

#### Integration tests

- preview route
- DocumentActions
- screen integration
- permission checks

#### Print / visual validation

- A4 sample
- thermal sample
- report sample

#### Performance validation

- CSV thresholds
- XLSX thresholds
- Tier 2 PDF generation

### المرحلة 15 — Rollout Readiness

قبل اعتبار التنفيذ مكتملاً، تأكد من:

- وجود أول مستند رسمي جاهز بالكامل
- وجود أول thermal document جاهز بالكامل
- وجود أول report export path جاهز
- وجود CSV working path
- وجود XLSX working path
- وجود Tier 1 وTier 2 working paths
- وجود عقود Tier 3

---

## قواعد تنفيذ صارمة

يجب الالتزام بهذه القواعد أثناء التنفيذ:

1. لا تضع imports ثقيلة داخل الـ main app bundle.
2. لا تستخدم الصفحة التفاعلية الحالية كمستند مطبوع.
3. لا تنشئ PDF path واحدًا غامضًا يخفي الفروق بين tiers.
4. لا تستخدم `SheetJS CE`.
5. لا تعتمد على `@page margin boxes` للـ headers/footers.
6. لا تهمل thermal constraints.
7. لا تؤجل security layer إلى النهاية.
8. لا تؤجل tests إلى ما بعد اكتمال كل شيء.
9. لا تكسر المسارات الحالية أو الشاشات الحالية أثناء الدمج.
10. عند وجود تعارض بين التنفيذ والوثيقة المعتمدة، الوثيقة المعتمدة هي الأصل، ما لم يظهر blocker تنفيذي حقيقي.

---

## ما يجب أن تسلمه أداة التطوير

المخرجات المطلوبة ليست شرحًا، بل تنفيذًا فعليًا داخل الكود، مع:

- الملفات الجديدة
- الملفات المعدلة
- الاختبارات
- أي إعدادات أو مفاتيح جديدة لازمة
- توضيح ما تم إنجازه وما بقي مؤجلًا عمدًا

وعند نهاية كل دفعة تنفيذية يجب أن تذكر:

- ما الذي تم
- ما الذي تم التحقق منه
- ما الذي يعتمد عليه ما بعده
- هل يوجد blocker حقيقي أم لا

---

## تعريف النجاح

يعتبر التنفيذ ناجحًا فقط إذا أصبحت المنصة:

- قابلة للاستخدام من صفحات فعلية
- تطبع مستندًا فعليًا بشكل احترافي
- تصدر CSV فعليًا
- تصدر XLSX فعليًا
- توفر PDF عمليًا عبر Tier 1 وTier 2
- تحافظ على الأداء
- تحترم الأمان والصلاحيات
- تفتح الطريق لتفعيل Tier 3 لاحقًا بدون إعادة بناء جذرية

---

## الصيغة العملية للأمر

ابدأ الآن بتنفيذ الخطة الكاملة كما تم اعتمادها في الوثيقة المرجعية، ونفّذها على مراحل مترابطة داخل الكود الفعلي للمشروع، مع الحفاظ على الاستقرار، والأداء، والأمان، والاختبارات، وعدم ترك أي منطقة رمادية أو قرار تنفيذي غير محسوم إذا كان ضمن النطاق المعتمد.

لا تتوقف عند التحليل.

ابدأ التنفيذ الفعلي.

