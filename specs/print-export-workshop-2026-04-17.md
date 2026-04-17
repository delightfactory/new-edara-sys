# ورشة عمل نظام الطباعة والتصدير الاحترافي

تاريخ الوثيقة: 2026-04-17

## 1) الهدف

نحتاج إنشاء نظام طباعة وتصدير مركزي واحترافي داخل EDARA يمكن استدعاؤه من أي صفحة أو تقرير أو فاتورة أو إيصال أو كشف حساب، مع احترام:

- الهوية المؤسسية وبيانات الشركة من `company_settings`.
- اللغة العربية واتجاه RTL مع دعم الأرقام والحقول اللاتينية.
- الطباعة من الهاتف والديسكتوب والتابلت.
- مقاسات الطباعة المختلفة: A4 / Letter / Legal / thermal receipts / custom sizes.
- المستندات متعددة الصفحات.
- الفصل بين "التصميم الطباعي" و"بيانات الشاشة" و"ملفات التصدير".

هذه الوثيقة تجمع:

- تقييمًا سريعًا للوضع الحالي في المشروع.
- خلاصة أفضل الممارسات الحديثة والمعتمدة.
- تصورًا معماريًا مناسبًا للمشروع الحالي.
- Prompt جاهز لكلود لبدء دراسة أعمق وخطة تنفيذ دقيقة.

---

## 2) الوضع الحالي في المشروع

### ما الموجود اليوم

- يوجد تصدير CSV بسيط فقط في `src/lib/utils/export.ts`.
- توجد بيانات الشركة الأساسية في جدول `company_settings` مثل:
  - `company.name`
  - `company.name_en`
  - `company.logo_url`
  - `company.phone`
  - `company.address`
  - `company.tax_number`
- توجد شاشة إعدادات عامة لعرض وتعديل `company_settings`.
- توجد صفحات كثيرة تصلح لاحقًا كنقاط دمج للطباعة:
  - تفاصيل الطلبات
  - تفاصيل الإيصالات
  - صفحات التقارير
  - الجداول الموحدة

### الفجوات الحالية

- لا يوجد Print Engine مركزي.
- لا يوجد Document Registry أو تعريف موحد للمستندات.
- لا يوجد Print CSS مركزي.
- لا يوجد دعم رسمي لمقاسات الورق أو named page profiles.
- لا يوجد فصل بين:
  - Export tabular data
  - Print-friendly document layout
  - Deterministic PDF generation
- لا يوجد تصور موحد للصفحات متعددة الصفحات أو الترويسات والتذييلات أو الترقيم.

### الاستنتاج

النظام اليوم مهيأ جيدًا للانطلاق لأن:

- لدينا React + Vite + CSS Tokens.
- لدينا إعدادات شركة مركزية.
- لدينا صفحات تفاصيل وتقارير واضحة.

لكن المطلوب ليس "زر طباعة" فقط، بل طبقة منصة كاملة للطباعة والتصدير.

---

## 3) خلاصة البحث: أفضل الممارسات الحديثة

## 3.1 الطباعة على الويب يجب أن تُبنى حول Print CSS وليس حول لقطة شاشة

أفضل الممارسات الحديثة في تطبيقات الأعمال لا تعتمد على screenshot-style printing، بل تعتمد على:

- HTML document structure نظيف.
- `@media print` لإخفاء واجهات التطبيق وإظهار المستند فقط.
- `@page` لضبط المقاسات والهوامش والاتجاه.
- قواعد fragmentation مثل `break-inside` و `break-after` للتحكم في تقسيم الصفحات.

هذا يجعل نفس المستند قابلًا للطباعة، والحفظ كـ PDF من المتصفح، والتحويل لاحقًا إلى PDF احترافي عبر headless browser إذا احتجنا.

## 3.2 نحتاج فصلًا واضحًا بين نوعين من التصدير

يجب التفريق معماريًا بين:

### أ) Document Export

خاص بالفواتير والإيصالات والتقارير وكشوف الحساب.

مخرجاته:

- Print
- PDF

ويعتمد على layout احترافي قابل للقراءة والطباعة.

### ب) Data Export

خاص بالبيانات الجدولية والتحليلية.

مخرجاته:

- CSV
- XLSX مستقبلًا

ويعتمد على raw/tabular export، لا على تصميم الصفحة الطباعي.

هذا الفصل مهم جدًا حتى لا تتحول صفحة التقرير المرئية نفسها إلى فوضى عند محاولة استخدامها كملف CSV أو فاتورة PDF أو ورقة A4.

## 3.3 المقاسات يجب أن تُدار كـ Paper Profiles مركزية

بدلًا من hardcoding المقاسات داخل كل صفحة، الأفضل اعتماد طبقة مركزية مثل:

- `a4-portrait`
- `a4-landscape`
- `letter-portrait`
- `thermal-58mm`
- `thermal-80mm`
- `custom`

كل profile يحدد:

- width / height أو named size
- orientation
- margins
- density / font scale
- header/footer behavior
- whether page numbers are shown

## 3.4 المستندات متعددة الصفحات تحتاج قواعد fragmentation صريحة

أهم نقطة عملية في التقارير والفواتير الكبيرة هي التحكم في:

- عدم كسر عنوان القسم في آخر الصفحة.
- عدم كسر صف الجدول المهم أو البطاقة الحرجة بشكل سيئ.
- فرض صفحة جديدة عند بداية قسم كبير.
- تكرار header الجدول عند اللزوم.

النهج الصحيح:

- `break-inside: avoid` للعناصر الحساسة.
- `break-after: page` عند بداية/نهاية أقسام معينة.
- تصميم sections و tables من البداية لتتحمل pagination.

## 3.5 لا نعتمد اعتمادًا أعمى على ميزات `@page` المتقدمة

المتصفح الحديث يدعم `@page` و `size` بشكل أفضل الآن، لكن بعض أجزاء paged media المتقدمة ما تزال متفاوتة الدعم بين المتصفحات والطابعات.

لذلك النهج الاحترافي هو:

- استخدام `@page` للمقاس والهوامش والاتجاه.
- استخدام `page` named pages بحذر حيث ينفع.
- عدم رهن نجاح المستند بالكامل بخصائص margin boxes المتقدمة فقط.
- جعل header/footer الأساسي ممكنًا أيضًا داخل بنية المستند نفسها، وليس فقط في هوامش الطباعة.

بمعنى آخر:

- نستفيد من المعيار الحديث.
- لكن نبني fallback قويًا داخل HTML/CSS نفسه.

## 3.6 الطباعة من الهاتف يجب أن تُعتبر Preview + Share + Save PDF، لا مجرد Ctrl+P

على الهاتف، تجربة الطباعة الواقعية غالبًا تكون:

- فتح Preview clean document.
- مشاركة أو حفظ PDF.
- إرسال للطابعة عبر النظام أو الطابعة الحرارية.

لذلك يجب أن نضيف مفهوم:

- `Document Preview Route`
- `Document Actions Sheet`
- أزرار:
  - طباعة
  - حفظ PDF
  - تصدير CSV/XLSX عند اللزوم
  - مشاركة

بدلًا من ربط كل شيء بزر `window.print()` داخل الصفحة الأصلية.

## 3.7 المستند الطباعي لا يجب أن يكرر واجهة التطبيق

لا ينبغي طباعة:

- الـ sidebar
- الـ bottom nav
- الأزرار
- البطاقات الزخرفية الخاصة بالعرض على الشاشة
- الخلفيات المبالغ فيها

بل يجب أن يتحول المستند إلى layout print-first:

- ترويسة مؤسسية
- بيانات رئيسية واضحة
- جداول مرتبة
- summary blocks
- توقيعات أو ملاحظات
- footer مهني

## 3.8 PDF الاحترافي له مساران

### المسار الأول: Browser Print to PDF

الأسرع والأخف في المرحلة الأولى، ويعتمد على Print CSS.

مناسب لـ:

- الفواتير
- الإيصالات
- التقارير الفردية
- المعاينة الفورية للمستخدم

### المسار الثاني: Headless PDF generation

مناسب لاحقًا عندما نحتاج:

- PDF مطابق 100% عبر الأجهزة
- batch export
- background jobs
- إرسال ملفات PDF بالبريد
- أرشفة مستندات رسمية deterministic

الاختيار الاحترافي للمشروع الحالي:

- Phase 1: browser-native print pipeline.
- Phase 2: headless Chromium/Puppeteer route عند الحاجة التشغيلية الفعلية.

## 3.9 بيانات الشركة يجب أن تُحل مركزيًا لا داخل كل مستند

بدل أن يجلب كل مستند `company_settings` بنفسه بطريقة عشوائية، الأفضل وجود resolver موحد مثل:

- `getDocumentBranding()`
- `getCompanyPrintProfile()`

ويعيد:

- الاسم العربي والإنجليزي
- الشعار
- الهاتف
- العنوان
- الرقم الضريبي
- العملة
- أي footnotes قانونية

## 3.10 لا نربط المستند بصفحة UI الأصلية 1:1

بعض الصفحات الحالية مثل `PaymentReceiptDetail` و`SalesOrderDetail` مصممة للاستخدام التفاعلي اليومي، وليست جاهزة لأن تكون مستندات طباعة مباشرة كما هي.

لذلك الأفضل أن يكون لكل مستند:

- View model خاص بالطباعة
- Layout خاص بالطباعة
- Renderer خاص بالتصدير

وليس مجرد "اطبع الصفحة الحالية كما هي".

---

## 4) الاستنتاج المهني المقترح للمشروع

## 4.1 القرار المعماري الرئيسي

نبني **منصة مستندات مركزية** داخل النظام، وليس وظائف متفرقة.

اسم مقترح:

- `Document Output System`
- أو
- `Print & Export Platform`

## 4.2 الطبقات المقترحة

### 1) Document Definition Layer

تعرف ماهية المستند منطقيًا:

- `sales-order`
- `payment-receipt`
- `account-statement`
- `sales-report`
- `inventory-report`

وتحدد:

- title
- document type
- supported outputs
- default paper profile
- whether multi-page is expected

### 2) Data Preparation Layer

تحول البيانات الخام إلى view model موحد للطباعة:

- company
- customer / supplier / employee
- metadata
- line items
- totals
- notes
- approval trail

### 3) Render Layer

ينشئ المستند نفسه:

- `A4DocumentLayout`
- `ThermalReceiptLayout`
- `ReportLayout`
- `StatementLayout`

### 4) Output Layer

تتعامل مع طرق الإخراج:

- `print`
- `pdf`
- `csv`
- `xlsx` مستقبلًا

### 5) Policy / Settings Layer

تحدد:

- بيانات الشركة
- paper profiles
- defaults
- branding rules
- optional legal footer
- decimal formatting / currency / locale

---

## 5) تصور هيكلي مناسب لـ EDARA

## 5.1 مكونات أساسية مقترحة

### مجلدات منطقية

```text
src/
  features/
    documents/
      definitions/
      renderers/
      layouts/
      hooks/
      services/
      styles/
      presets/
      utils/
```

### ملفات أساسية مقترحة

```text
src/features/documents/definitions/document-types.ts
src/features/documents/definitions/document-registry.ts
src/features/documents/presets/paper-profiles.ts
src/features/documents/services/document-branding.ts
src/features/documents/services/document-export-service.ts
src/features/documents/services/document-print-service.ts
src/features/documents/layouts/A4DocumentLayout.tsx
src/features/documents/layouts/ThermalReceiptLayout.tsx
src/features/documents/layouts/ReportDocumentLayout.tsx
src/features/documents/components/DocumentPreview.tsx
src/features/documents/components/DocumentActions.tsx
src/features/documents/styles/print.css
```

## 5.2 نماذج واجهات TypeScript مقترحة

```ts
type OutputKind = 'print' | 'pdf' | 'csv' | 'xlsx'

type PaperProfileId =
  | 'a4-portrait'
  | 'a4-landscape'
  | 'letter-portrait'
  | 'thermal-58mm'
  | 'thermal-80mm'
  | 'custom'

interface DocumentDefinition<TInput, TModel> {
  type: string
  title: string
  supportedOutputs: OutputKind[]
  defaultPaperProfile: PaperProfileId
  prepare: (input: TInput) => Promise<TModel> | TModel
  render: (model: TModel, ctx: DocumentRenderContext) => React.ReactNode
}

interface DocumentRenderContext {
  paper: PaperProfile
  company: CompanyBranding
  locale: string
  direction: 'rtl' | 'ltr'
  output: OutputKind
}
```

## 5.3 Paper Profiles مركزية

```ts
interface PaperProfile {
  id: PaperProfileId
  label: string
  width?: string
  height?: string
  size?: 'A4' | 'letter' | 'legal'
  orientation?: 'portrait' | 'landscape'
  margin: string
  contentWidth?: string
  fontScale?: number
  showPageNumbers?: boolean
}
```

أمثلة:

- `thermal-58mm`: width 58mm, tight margin, dense typography.
- `thermal-80mm`: width 80mm, larger totals, optional QR/logo.
- `a4-portrait`: classic invoice/report.
- `a4-landscape`: wide reports and analysis tables.

---

## 6) سياسة أنواع الإخراج

## 6.1 Print / PDF

يستخدمان نفس document renderer قدر الإمكان.

الفرق:

- `print`: يفتح preview ويستدعي `window.print()`.
- `pdf`:
  - في المرحلة الأولى: print-to-pdf من المتصفح.
  - في المرحلة الثانية: headless PDF service.

## 6.2 CSV / XLSX

لا يجب أن يستخدما نفس template الطباعي.

الأفضل:

- `table export schema`
- headers مترجمة
- raw values + formatted values حيث يلزم
- UTF-8 BOM للعربية
- لاحقًا دعم `xlsx` مع sheet names وcolumn widths وtype-safe formatting

---

## 7) معايير تصميم المستندات

## 7.1 مبادئ ثابتة

- Header مؤسسي موحد.
- منطقة meta واضحة في أعلى المستند.
- hierarchy بصري قوي بين:
  - العنوان
  - رقم المستند
  - الحالة
  - التاريخ
- body منظم إلى sections.
- summary block واضح في النهاية.
- footer احترافي ومختصر.

## 7.2 مبادئ عربية / RTL

- المستند RTL افتراضيًا عند العربية.
- الحقول اللاتينية مثل:
  - phone
  - tax number
  - email
  - codes
  تكون `dir="ltr"` عند العرض.
- استخدام tabular numerals للمبالغ والأرقام المهمة.
- محاذاة المبالغ والإجماليات بشكل ثابت.

## 7.3 مبادئ الجداول

- table headers ثابتة وواضحة.
- عدم كسر الصف الحرج داخل الصفحة إن أمكن.
- الصفوف الطويلة تُعالج بالتفاف منضبط.
- عمود المبلغ والإجمالي يجب أن يكون محاذاته موحدة.

## 7.4 مبادئ الإيصالات الحرارية

- عرض ضيق وواضح.
- تقليل العناصر الزخرفية.
- تباين عالٍ.
- line-height محسوب للطابعات الحرارية.
- عدم الاعتماد على ألوان خفيفة.
- إجمالي نهائي واضح جدًا.
- دعم طباعة بدون شعار أو مع شعار صغير حسب الإعدادات.

---

## 8) السياسة التشغيلية المقترحة

## 8.1 من داخل أي صفحة

أي شاشة تحتاج مستندًا يجب أن تستدعي:

- document definition
- data prepare function
- preview route أو modal
- output action

وليس أن تعيد اختراع الطباعة بنفسها.

## 8.2 Preview أولًا

أفضل UX:

- زر `طباعة / تصدير`
- يفتح `Document Preview`
- من هناك:
  - Print
  - Save PDF
  - CSV/XLSX إذا كان المستند تحليليًا

## 8.3 عدم الطباعة من DOM الصفحة الأصلية

كقاعدة عامة:

- لا نطبع `DashboardPage` نفسها.
- لا نطبع `DetailPage` التفاعلية نفسها.

بل ننشئ نسخة document-friendly render.

---

## 9) إعدادات إضافية يُستحسن التفكير فيها

الإعدادات الحالية جيدة كبداية، لكن على الأرجح سنحتاج لاحقًا إلى مفاتيح إضافية مثل:

- `company.email`
- `company.website`
- `company.commercial_register`
- `company.footer_note`
- `print.default_paper_profile`
- `print.show_logo`
- `print.show_tax_number`
- `print.thermal_show_qr`
- `print.default_copies`
- `print.default_density`
- `print.a4_margin_mm`

مهم:

لا نضيف هذه الإعدادات دفعة واحدة قبل حسم المعمارية؛ نضيف ما يلزم فقط بعد اعتماد التصميم النهائي.

---

## 10) خطة تنفيذ مبدئية مقترحة

## المرحلة 1: الأساس المركزي

- إنشاء `documents` feature.
- بناء `paper profiles`.
- بناء `company branding resolver`.
- بناء `print.css` مركزي.
- بناء `DocumentPreview`.
- دعم أول مستندين:
  - إيصال تحصيل
  - طلب بيع / فاتورة

## المرحلة 2: التقارير متعددة الصفحات

- A4 report layout.
- sectioned reports.
- page-aware tables.
- pagination rules.
- export actions unified.

## المرحلة 3: data export

- تحسين CSV الحالي.
- إضافة XLSX احترافي.
- schema-based column definitions.

## المرحلة 4: deterministic PDF

- دراسة إضافة Puppeteer أو خدمة headless Chrome.
- background PDF jobs.
- archive-ready PDFs.

---

## 11) قرارات مبدئية أوصي بها الآن

1. نعتمد `browser-native print CSS` كخط الأساس في المرحلة الأولى.
2. نفصل معماريًا بين `Document Export` و`Data Export`.
3. ننشئ `Paper Profiles` مركزية بدل hardcoding.
4. نبني `Document Preview` مستقل بدل طباعة الصفحة الأصلية.
5. نستفيد من `company_settings` الحالية كمرجع branding مركزي.
6. لا نعتمد بالكامل على features متقدمة متفاوتة الدعم داخل `@page`; نبني fallback داخل layout نفسه.
7. نبدأ بمستندين فعليين فقط، ثم نعمم المنصة بعد إثبات النمط.

---

## 12) Prompt جاهز لكلود

انسخ prompt التالي إلى كلود لبدء ورشة البحث والتحليل:

```text
نحن نعمل على نظام ERP/PWA باسم EDARA مبني حاليًا بـ React + TypeScript + Vite + Supabase، وهدفنا الآن هو تصميم نظام طباعة وتصدير احترافي ومركزي وقابل لإعادة الاستخدام من أي موضع في النظام.

أريد منك إجراء دراسة تحليلية عميقة وعملية، وليس مجرد اقتراحات عامة.

السياق المهم:
- لدينا بيانات الشركة الأساسية داخل company_settings مثل:
  - company.name
  - company.name_en
  - company.logo_url
  - company.phone
  - company.address
  - company.tax_number
- يوجد حاليًا تصدير CSV بسيط فقط، ولا يوجد نظام طباعة/تصدير مركزي فعلي.
- النظام يستخدم العربية وRTL بشكل أساسي.
- نحتاج دعم:
  - فواتير
  - إيصالات
  - تقارير
  - كشوف حساب
  - مستندات متعددة الصفحات
  - طباعة من الهاتف والديسكتوب والتابلت
  - طابعات حرارية بمقاسات مختلفة
  - ورق A4 وباقي المقاسات المهنية المعتمدة

أريد منك تنفيذ المهمة على 6 محاور:

1) تقييم معماري للوضع الحالي
- ما الفروق بين:
  - page printing
  - document rendering
  - PDF export
  - tabular data export
- ما المخاطر إذا قمنا فقط بطباعة صفحات UI الحالية كما هي؟

2) بحث وتحليل لأفضل الممارسات الحديثة والمعتمدة
- ابحث عن أفضل الممارسات الحالية والمعتمدة في:
  - CSS print
  - @media print
  - @page
  - named pages
  - multi-page documents
  - thermal receipts
  - PDF generation pipelines
  - responsive print/export UX
- اعتمد على مصادر رسمية أو موثوقة جدًا، واذكر بوضوح أين توجد قيود دعم بين المتصفحات.

3) تصور معماري احترافي للنظام
- اقترح architecture كاملة لنظام مركزي reusable داخل المشروع.
- يجب أن يتضمن التصور:
  - document registry
  - document definitions
  - data preparation/view models
  - renderers/layouts
  - paper profiles
  - branding resolver
  - output adapters (print/pdf/csv/xlsx)
  - preview flow

4) توصية تنفيذية خاصة بمشروعنا الحالي
- ما أفضل approach لنا الآن عمليًا؟
- هل نبدأ browser-native print CSS أولًا؟
- متى نحتاج headless PDF generation مثل Puppeteer؟
- ما الحدود بين phase 1 وphase 2؟

5) mapping على الشاشات الحالية
- اقترح كيف يمكن تطبيق هذا النظام تدريجيًا على:
  - PaymentReceiptDetail
  - SalesOrderDetail
  - Reports pages
  - Data tables
- وضّح ما الذي يجب إعادة استخدامه، وما الذي يجب فصله عن UI الحالي.

6) مخرجات نهائية مطلوبة منك
- أريد منك أن تخرج في النهاية بـ:
  - Executive summary
  - Architecture recommendation
  - Risks and tradeoffs
  - Phased implementation plan
  - Suggested folder/file structure
  - Suggested TypeScript interfaces
  - Suggested company_settings additions
  - Decision matrix: print vs pdf vs csv vs xlsx

تعليمات مهمة:
- لا تكتفِ بالنظري؛ اربط اقتراحك بما يناسب React/Vite/Supabase وPWA.
- إذا وجدت أن بعض مميزات CSS paged media غير مضمونة عمليًا، فاذكر ذلك صراحة وقدّم fallback محترف.
- فرّق بوضوح بين:
  - printable document layout
  - interactive UI page
  - export data schema
- أريد رأيك الصريح والمرجح، لا مجرد قائمة خيارات متساوية.
- إذا احتجت المفاضلة بين بدائل، فاكتب recommendation نهائية واضحة مع الأسباب.
```

---

## 13) رأيي المهني النهائي في هذه المرحلة

أوصي أن يكون القرار الرسمي المبدئي كالتالي:

- نبني **منصة مستندات مركزية** وليست حلول طباعة محلية داخل كل صفحة.
- نجعل **Print CSS + Preview-first** هو الأساس.
- نستخدم **A4/thermal paper profiles** مركزيًا.
- نبدأ بـ **إيصال التحصيل + طلب البيع/الفاتورة** كأول حالتي تطبيق.
- نؤجل **Headless PDF** إلى حين وجود حاجة تشغيلية واضحة مثل الأرشفة أو الإرسال الآلي أو التقارير الدورية.

هذا المسار هو الأكثر احترافية والأقل مخاطرة والأفضل ملاءمة لبنية المشروع الحالية.

---

## 14) مراجع البحث

### مراجع رسمية أساسية

- MDN - `@page`
  - https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/@page
- MDN - `@page size`
  - https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/@page/size
- MDN - Printing with CSS / `beforeprint` / `afterprint`
  - https://developer.mozilla.org/en-US/docs/Web/CSS/Guides/Media_queries/Printing
- MDN - CSS paged media
  - https://developer.mozilla.org/en-US/docs/Web/CSS/Guides/Paged_media
- MDN - `break-inside`
  - https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/break-inside
- MDN - `print-color-adjust`
  - https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/print-color-adjust
- MDN - `page` property
  - https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/page
- W3C - CSS Paged Media Module Level 3
  - https://www.w3.org/TR/css-page-3/
- Puppeteer - `Page.pdf()`
  - https://pptr.dev/next/api/puppeteer.page.pdf
- Puppeteer - PDF generation guide
  - https://pptr.dev/guides/pdf-generation

### ملاحظات استنتاجية من المراجع

- دعم `@page` و`size` أصبح أفضل بكثير على المتصفحات الحديثة، لكن ليس كل أجزاء paged media المتقدمة متساوية الدعم.
- `break-inside` خيار مهم وعملي جدًا للمستندات متعددة الصفحات.
- `print-color-adjust` و `-webkit-print-color-adjust` مهمان عندما نحتاج fidelity لونية أعلى.
- headless PDF عبر Chromium مناسب كمرحلة لاحقة عندما نحتاج reproducible server-grade PDFs.

