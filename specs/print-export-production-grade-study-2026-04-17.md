# الدراسة الإنتاجية الكاملة لنظام الطباعة والتصدير

تاريخ الوثيقة: 2026-04-17

هذه الوثيقة تُلغي أي افتراض سابق يتعلق بـ `MVP` أو `Prototype` أو "مرحلة أولية مبسطة".

الافتراض الرسمي هنا هو:

- نحن نبني **منصة طباعة وتصدير Production-grade** من أول إصدار.
- المنصة يجب أن تكون قابلة للاعتماد الكامل في التشغيل الحقيقي.
- يجب أن تدعم التوسع المستقبلي دون إعادة بناء جذرية.
- يجب ألا تُضعف أداء التطبيق أو تستهلك الموارد بشكل غير محسوب.

---

## 1) التفويض النهائي

المطلوب ليس زر طباعة، ولا شاشة تصدير، ولا قوالب معزولة لكل صفحة.

المطلوب هو **نظام إخراج مستندي مركزي** يخدم:

- الفواتير
- أوامر البيع والشراء
- إيصالات القبض والدفع
- كشوف الحساب
- التقارير التحليلية والتشغيلية
- المستندات متعددة الصفحات
- الطباعة الحرارية
- الطباعة المكتبية
- ملفات PDF
- ملفات CSV
- ملفات XLSX

مع احترام:

- RTL والعربية بشكل أصيل
- الهوية المؤسسية وبيانات الشركة
- الطباعة من الهاتف والتابلت والديسكتوب
- المقاسات الرسمية والمعتمدة
- الأداء العالي
- الاستقرار والاعتمادية
- الاختبارات وسهولة الصيانة

---

## 2) تقييم الواقع الحالي داخل المشروع

## 2.1 الموجود حاليًا

- يوجد تصدير CSV بسيط فقط في `src/lib/utils/export.ts`.
- توجد بيانات الشركة الأساسية في `company_settings`.
- توجد صفحات تفاصيل تصلح لاحقًا كنقاط استدعاء للمستندات مثل:
  - `PaymentReceiptDetail`
  - `SalesOrderDetail`
  - صفحات التقارير
  - الجداول المشتركة
- يوجد نظام تصميم أساسي عبر CSS tokens.

## 2.2 الفجوة الجوهرية

المشروع اليوم لا يحتوي على:

- Document registry
- Render engine للمستندات
- Print CSS مركزي
- PDF pipeline
- Export orchestration
- Paper profiles
- Preview workflow
- Performance policy خاصة بالإخراج

النتيجة:

أي محاولة لبناء الطباعة مباشرة داخل الصفحات الحالية ستنتج نظامًا:

- هشًا
- متكررًا
- صعب الصيانة
- غير موحد بصريًا
- خطرًا على الأداء

---

## 3) المبدأ المعماري الحاسم

**لا نطبع صفحات الـ UI التفاعلية نفسها.**

بل نبني 4 طبقات منفصلة:

1. **طبقة تعريف المستند**
2. **طبقة إعداد البيانات**
3. **طبقة الرندر والإخراج**
4. **طبقة التشغيل والجدولة والأداء**

هذا هو الفارق بين نظام احترافي قابل للإنتاج، وبين حلول طباعة مجزأة.

---

## 4) الخلاصة البحثية الحديثة والمعتمدة

## 4.1 ما الذي يمكن الاعتماد عليه على الويب اليوم؟

بحسب MDN:

- `@page` أصبح Baseline حديثًا منذ ديسمبر 2024.
- `@page size` أصبح Baseline حديثًا منذ ديسمبر 2024.
- `page` property متاح على نطاق واسع منذ فبراير 2023.
- `break-inside` متاح على نطاق واسع منذ يناير 2019.
- `print-color-adjust` أصبح Baseline منذ مايو 2025.
- `window.print()` متاح على نطاق واسع، لكنه **blocking** أثناء فتح نافذة الطباعة.
- `beforeprint` و `afterprint` مدعومان على نطاق واسع.

هذا يعني:

- يمكن الاعتماد على Print CSS الحديثة كجزء أساسي من النظام.
- لكن لا ينبغي أن نعتمد على ميزات paged media الأكثر تباينًا في الدعم اعتمادًا كاملًا دون fallback.

## 4.2 ما الذي لا يجب فعله في نظام إنتاجي؟

- لا نطبع DOM الصفحة الحالية كما هو.
- لا نضع مكتبات تصدير كبيرة داخل كل شاشة.
- لا ننشئ PDF ثقيل بالكامل داخل الـ main UI thread.
- لا نشغّل Chromium/headless browser داخل العميل.
- لا نستخدم Edge Functions محدودة الموارد كخيار افتراضي لتوليد PDF الثقيل.

## 4.3 ما الذي نستنتجه مهنيًا؟

أفضل نظام إنتاجي هنا يجب أن يكون **هجينًا ومنضبطًا**:

### داخل المتصفح

- Preview
- Print
- Lightweight PDF handoff
- CSV صغير/متوسط
- XLSX بسيط/متوسط عند الحاجة

### خارج المتصفح

- Deterministic PDF generation
- Large XLSX generation
- Batch exports
- Archived official documents
- Heavy multi-page rendering

---

## 5) قرار الأداء والموارد

## 5.1 لماذا لا نضع كل شيء داخل العميل؟

لأن هذا يسبب:

- تضخم حجم الـ bundle
- استهلاك ذاكرة أعلى على الهاتف
- بطء في التفاعل
- re-renders مكلفة
- crashes محتملة مع التقارير الكبيرة
- تجربة ضعيفة مع الطابعات الحرارية والملفات الضخمة

## 5.2 لماذا لا نعتمد على Supabase Edge Functions لتوليد PDF الثقيل كخيار افتراضي؟

بحسب Supabase Docs:

- ذاكرة Edge Functions القصوى: `256MB`
- حجم الوظيفة بعد bundling: `20MB`
- CPU time لكل request محدود
- وهناك قيود تشغيلية إضافية على بيئة Edge

لذلك:

- Edge Functions ممتازة للتنسيق والـ orchestration والروابط والتوقيع والتفويض.
- لكنها ليست الخيار الافتراضي المثالي لتشغيل محرك Chromium ثقيل لإنتاج PDFs مؤسسية كبيرة بشكل مستمر.

**الاستنتاج**:

إذا أردنا PDF إنتاجيًا حقيقيًا من أول إصدار، فيجب عزله في **Render Worker / PDF Service** مستقل أو بيئة server runtime تدعم Chromium بشكل مناسب.

هذا استنتاج معماري مبني على حدود المنصة الحالية، وليس مجرد تفضيل.

---

## 6) القرار المعماري النهائي المقترح

## 6.1 النظام المقترح

نبني **Output Platform** مركزية تتكون من:

### 1) Document Registry

يسجل كل نوع مستند في النظام:

- `sales-order`
- `sales-invoice`
- `payment-receipt`
- `account-statement`
- `sales-report`
- `inventory-report`
- `attendance-report`
- `payslip`
- وغيرها

### 2) Document Definition

كل مستند يعرّف:

- هويته
- المخرجات المدعومة
- paper profiles المدعومة
- استراتيجية الحصول على البيانات
- renderer المناسب
- هل التنفيذ sync أو async
- هل الوثيقة أرشيفية أو لحظية

### 3) Data Preparation Layer

تحوّل البيانات من الشكل التشغيلي إلى **Canonical Document Model**.

هذه النقطة أساسية جدًا.

بدل أن يتعامل renderer مع raw DB rows أو UI state، نتعامل مع نموذج موحد مثل:

- company
- parties
- document meta
- sections
- tables
- totals
- approvals
- footer notes

### 4) Render Layer

تحتوي على renderers منفصلة:

- HTML preview renderer
- Print renderer
- PDF HTML renderer
- Thermal renderer
- Table export schema renderer

### 5) Output Adapters

تنفذ فعليًا:

- browser print
- pdf job
- csv export
- xlsx export

### 6) Execution Orchestrator

تقرر:

- هل العملية synchronous أم asynchronous؟
- هل تُنفذ داخل المتصفح أم عبر worker/service؟
- هل تحفظ artifact أم مجرد download فوري؟
- هل تحتاج caching أو snapshot؟

### 7) Artifact / Archive Layer

للمستندات الرسمية:

- حفظ نسخة PDF
- metadata
- hash/version
- created_by
- generated_at
- source filters / parameters

---

## 7) لماذا نحتاج Canonical Document Model؟

لأنه بدون هذا النموذج سنقع في 3 أخطاء:

1. ربط الطباعة مباشرة بصفحات الواجهة
2. تكرار logic التنسيق في أكثر من موضع
3. صعوبة دعم PDF وPrint وPreview وArchive بطريقة موحدة

## 7.1 مثال مبسط

```ts
type OutputKind =
  | 'print'
  | 'pdf-browser'
  | 'pdf-download'
  | 'pdf-archive'
  | 'csv'
  | 'xlsx'

type DocumentKind =
  | 'payment-receipt'
  | 'sales-order'
  | 'sales-invoice'
  | 'account-statement'
  | 'report'

type PaperProfileId =
  | 'a4-portrait'
  | 'a4-landscape'
  | 'letter-portrait'
  | 'legal-portrait'
  | 'thermal-58mm'
  | 'thermal-80mm'
  | 'custom'

interface CompanyBranding {
  name: string
  nameEn?: string | null
  logoUrl?: string | null
  phone?: string | null
  address?: string | null
  taxNumber?: string | null
  email?: string | null
  website?: string | null
  footerNote?: string | null
  currencyCode: string
  currencySymbol: string
}

interface CanonicalDocument {
  kind: DocumentKind
  title: string
  number?: string | null
  status?: string | null
  issuedAt?: string | null
  direction: 'rtl' | 'ltr'
  locale: string
  company: CompanyBranding
  parties: Array<{
    role: string
    name: string
    code?: string | null
    phone?: string | null
    address?: string | null
    taxNumber?: string | null
  }>
  meta: Array<{ label: string; value: string; dir?: 'rtl' | 'ltr' }>
  sections: DocumentSection[]
  totals?: DocumentTotals | null
  notes?: string[] | null
  approvals?: Array<{ label: string; value: string }>
}

type DocumentSection =
  | { type: 'kv'; title?: string; rows: Array<{ label: string; value: string; dir?: 'rtl' | 'ltr' }> }
  | { type: 'table'; title?: string; columns: DocumentColumn[]; rows: DocumentRow[] }
  | { type: 'plain-text'; title?: string; content: string; dir?: 'rtl' | 'ltr' }
  | { type: 'summary'; title?: string; items: Array<{ label: string; value: string }> }

interface DocumentColumn {
  key: string
  label: string
  align?: 'start' | 'center' | 'end'
  width?: string
  dir?: 'rtl' | 'ltr'
}

type DocumentRow = Record<string, string | number | null>

interface DocumentTotals {
  subtotal?: string
  discount?: string
  tax?: string
  total?: string
  paid?: string
  remaining?: string
}
```

---

## 8) قرار الإخراج الرسمي

## 8.1 الطباعة

الطباعة تتم عبر:

- Preview route أو dedicated print surface
- HTML document renderer
- Print CSS مركزية
- `window.print()` عند الطلب

لكن:

- لا تتم من الشاشة الأصلية
- لا تتم من modal مزدحم
- لا تتم من DOM تفاعلي يحتوي على أزرار وملاحة وبطاقات تطبيق

تحذير مهم:

- `@page { size; margin }` نعتمد عليه رسميًا.
- أما `@page margin boxes` مثل `@top-center` و`@bottom-right` فلا نعتمد عليها كآلية رئيسية للـ headers/footers بسبب تفاوت الدعم بين المتصفحات.
- القرار الرسمي: نستخدم `position: fixed` داخل `@media print` لكل headers/footers في كل documents.

## 8.2 PDF

### القرار النهائي

في نظام إنتاجي كامل، يجب دعم PDF على مستويين:

#### A) PDF Interactive

للمستخدم النهائي داخل التطبيق:

- preview
- download
- share

#### B) PDF Deterministic

للاستخدامات الرسمية:

- أرشفة
- إرسال
- batch jobs
- توليد تقارير كبيرة
- مطابقة ثابتة عبر الأجهزة

### التنفيذ المقترح

#### Tier 1 — Browser PDF

- المعاينة في المتصفح: HTML renderer
- الطباعة أو الحفظ PDF عبر `window.print()`
- هذا هو المسار الافتراضي الرسمي من أول يوم

#### Tier 2 — Client-side PDF

- المكتبة المعتمدة: `@react-pdf/renderer`
- التحميل: lazy-loaded فقط
- الحجم المتوقع: حوالي `350KB gzip`
- الحالات المناسبة:
  - `Download PDF` مباشرة بدون print dialog
  - mobile users
  - simple/medium documents مثل الفواتير والإيصالات وكشوف الحساب المتوسطة
- الشرط الإلزامي:
  - Arabic font مضمّن صريح مثل `Noto Naskh Arabic` أو ما يعادله
- القيد:
  - لا يُستخدم للتقارير الثقيلة متعددة الصفحات أو الجداول الكبيرة جدًا

#### Tier 3 — Deterministic PDF Service

- التوليد الإنتاجي الرسمي عند الحاجة التشغيلية المثبتة: **Playwright/Chromium PDF service**
- يستخدم فقط عند الحاجة إلى:
  - archival compliance
  - batch jobs
  - deterministic cross-device PDFs
  - heavy multi-page reports

بحسب Playwright docs:

- `page.pdf()` يولد PDF اعتمادًا على `print` CSS media
- يدعم المقاسات والهوامش بوحدات قياس واضحة
- يدعم `preferCSSPageSize`
- يدعم `printBackground`
- لكن هناك قيود على `headerTemplate/footerTemplate`

إذًا القرار الأفضل:

- نبني HTML/CSS document render قويًا أصلًا
- نعتمد Tier 1 وTier 2 من أول يوم
- ونفعل Tier 3 فقط عندما يظهر business case تشغيلي واضح
- ولا نبني PDF layout منفصل منطقيًا عن document HTML إلا إذا ظهر سبب قاهر

## 8.3 CSV

CSV يظل مسارًا منفصلًا مخصصًا للتصدير الجدولي.

مطلوب فيه:

- UTF-8 BOM
- schema-based headers
- raw + formatted mapping
- escape صحيح
- download naming
- auditability عند الحاجة

## 8.4 XLSX

XLSX يجب أن يكون مخرجًا رسميًا، لكن ليس عبر HTML-to-XLSX hacks.

المكتبة المعتمدة: `exceljs` (`Apache 2.0`).

السبب:

- `SheetJS CE` غيّر ترخيصه عام 2023 بما يقيّد الاستخدام التجاري في SaaS.
- `exceljs` أوضح قانونيًا وأنسب كخيار افتراضي للإنتاج.
- يجب أن تُحمّل `exceljs` lazy في كل الحالات بدون استثناء.

النهج الصحيح:

- workbook builder
- explicit sheet schema
- column widths
- header naming
- number/date typing
- optional multi-sheet workbooks
- type-safe cell formatting
- Web Worker compatibility
- streaming/chunk-aware generation when needed

الاستنتاج:

- XLSX يجب أن يُدار عبر exporter schema مستقل
- المستندات الضخمة تُنقل إلى background/export worker

---

## 9) تقسيم التنفيذ بين المتصفح والخدمة الخلفية

## 9.1 داخل المتصفح فقط

ينفذ داخل المتصفح:

- preview rendering
- browser print
- CSV صغير/متوسط
- XLSX صغير/متوسط
- download UX
- mobile share / open

## 9.2 داخل خدمة إخراج مستقلة

ينفذ خارج المتصفح:

- deterministic PDF
- التقارير الثقيلة
- ملفات XLSX الكبيرة
- exports المجدولة
- multi-document bundle
- archive generation

## 9.3 متى تتحول العملية من sync إلى async؟

نقترح policy واضحة:

- مستند فردي عادي: sync
- تقرير كبير أو صفحات كثيرة: async job
- XLSX كبير: async
- batch export: async
- أي عملية يُتوقع أن تتجاوز budget الواجهة: async

## 9.4 سياسة أمان الإخراج

لأن النظام ERP ويحتوي بيانات حساسة، فالإخراج يجب أن يخضع لنفس صرامة الأذونات المطبقة على البيانات الأصلية.

السياسة المعتمدة:

1. `Preview route` محمية بنفس auth guard وصلاحيات التطبيق، ولا يوجد أي استثناء للمستندات.
2. أي `artifact` محفوظ في `Supabase Storage` يُحمّل فقط عبر `signed URL` مؤقتة، بمدة صلاحية افتراضية لا تتجاوز ساعة واحدة.
3. الوصول إلى سجلات الـ artifacts يخضع لـ `RLS` أو طبقة أذونات مكافئة، بحيث لا يرى المستخدم إلا ما يملك حق الوصول إليه.
4. لا يُصدَّر أي حقل في `CSV/XLSX/PDF` إذا لم يكن المستخدم يملك صلاحية رؤيته أصلًا.
5. روابط تحميل PDF أو artifacts لا تُخزَّن في client state طويل الأجل، وتُعتبر مؤقتة دائمًا.
6. أي snapshot أرشيفي يُسجل معه:
   - `generated_by`
   - `generated_at`
   - `source filters`
   - `document version`
7. بيانات branding داخل الـ artifact تعتبر snapshot وقت التوليد، وليس مرجعًا حيًا يتغير بعد الحفظ.

---

## 10) ضوابط الأداء واستهلاك الموارد

هذه النقطة إلزامية، وليست تحسينًا لاحقًا.

## 10.1 budgets صريحة

يجب اعتماد budgets تشغيلية مثل:

| المكتبة/العملية | الحد الأقصى |
|---|---|
| `output core module` | `25KB gzip` |
| `exceljs` lazy chunk | `250KB gzip` |
| `@react-pdf/renderer` lazy chunk | `380KB gzip` |
| Arabic print font lazy asset | `350KB` |
| `CSV` export أقل من `10K rows` | `sync < 500ms` |
| `XLSX` export أقل من `5K rows` | `sync < 2000ms` |
| `PDF` generation عبر Tier 2 | `< 4000ms` |
| Print preview render | `< 1500ms` |
| Max in-memory rows for UI | `500 rows` |

هذه budgets تترجم إلى قواعد تنفيذية:

- عدم تحميل مكتبات PDF/XLSX الثقيلة داخل `main route bundle`
- lazy-load لكل exporters
- عدم تحميل الخطوط والصور الطباعية إلا عند preview/export
- عدم تنفيذ re-renders كبيرة عند تغيير إعدادات الطباعة
- عدم تحميل datasets عملاقة مباشرة إلى الواجهة عندما يكون المقصود export ثقيل

## 10.2 قاعدة فصل الأحمال الثقيلة

الأحمال التالية يجب فصلها عن main thread:

- توليد PDF رسمي
- XLSX كبير
- تقارير متعددة الصفحات بآلاف الصفوف
- دمج عدة مستندات

## 10.3 استهلاك الذاكرة

أهم سياسات الذاكرة:

- no giant in-memory UI arrays لمجرد التصدير
- استخدام pagination أو chunking في data preparation
- استخدام streaming where applicable
- تنظيف blobs وobject URLs بعد التحميل
- عدم الاحتفاظ بـ preview snapshots غير المستخدمة

## 10.4 الخطوط والصور

الأداء الطباعي يتأثر كثيرًا بالخطوط والصور.

سياسات مقترحة:

- اعتماد مجموعة خطوط محدودة جدًا
- preload فقط عند preview/print routes
- logo variants للطباعة:
  - full
  - monochrome
  - thermal-safe
- ضغط الصور مسبقًا
- منع الصور الضخمة غير الضرورية داخل المستند

## 10.5 الجداول الكبيرة

الجداول الكبيرة لا تُعالج كـ screen tables.

يجب:

- بناء report-specific table renderer
- تكرار header بشكل مضبوط
- break strategy
- row height predictability
- نقل الأحجام الكبيرة إلى async export path

## 10.6 cache strategy

نحتاج cache محسوبًا وليس عشوائيًا:

- cache لبيانات branding
- cache لمواصفات paper profiles
- cache للـ generated artifacts عند الحاجة
- cache keyed by:
  - document kind
  - entity id
  - filters
  - generation version

لكن يجب تفادي:

- cache غير مضبوط على المستندات الحساسة أو المتغيرة بسرعة دون versioning

## 10.7 observability

أي نظام إنتاجي هنا يجب أن يسجل:

- generation start / finish
- duration
- output type
- document kind
- page count
- artifact size
- failures / retries

بدون observability، لن نستطيع ضبط الأداء أو اكتشاف الاختناقات.

---

## 11) تجربة الاستخدام الإنتاجية

## 11.1 نقطة الدخول الموحدة

كل صفحة تحتاج إخراجًا يجب أن تستدعي `DocumentActions` موحدًا:

- Preview
- Print
- Download PDF
- Export CSV
- Export XLSX

مع إظهار الخيارات المدعومة فقط لكل مستند.

## 11.2 Preview route

نحتاج route أو surface مستقلة مثل:

- `/documents/:kind/:id/preview`
- أو preview overlay منفصل

لكن الأفضل للتشغيل والأداء هو route مستقلة في أغلب الحالات.

## 11.3 الموبايل

على الهاتف، التجربة يجب أن تكون:

- فتح document preview clean
- action sheet أو top actions
- print / pdf / share

وليس:

- طباعة الشاشة الأصلية
- أو تحميل DOM مزدحم بالمكونات التفاعلية

---

## 12) Paper Profiles الرسمية

من أول إصدار يجب أن توجد paper profiles مركزية:

- `a4-portrait`
- `a4-landscape`
- `letter-portrait`
- `legal-portrait`
- `thermal-58mm`
- `thermal-80mm`
- `custom`

كل profile يحدد:

- size أو width/height
- orientation
- margins
- font scale
- density
- page numbering policy
- header/footer policy
- thermal constraints

قيد معروف يجب توثيقه صراحة:

- `thermal-58mm` و`thermal-80mm` عبر browser print مدعومان بشكل موثوق عندما تكون الطابعة حرارية USB أو network أو معرّفة عبر نظام التشغيل.
- أما Bluetooth thermal printing على الموبايل فليست مضمونة عبر web-only architecture، وقد تحتاج bridge أو companion app أو مسار تقني متخصص.

---

## 13) أنواع المستندات ونوع الإخراج المناسب

## 13.1 مستندات تشغيلية فردية

مثل:

- إيصال قبض
- سند دفع
- أمر بيع
- فاتورة

المناسب:

- preview
- print
- pdf

## 13.2 تقارير تحليلية

مثل:

- تقرير المبيعات
- تقرير المخزون
- كشف الحساب

المناسب:

- print
- pdf
- csv
- xlsx

## 13.3 بيانات bulk

مثل:

- تفاصيل آلاف السطور
- استخراجات مالية كاملة

المناسب:

- csv
- xlsx
- pdf فقط إذا كان هناك use case رسمي واضح

---

## 14) المجلدات والملفات المقترحة

```text
src/
  features/
    output/
      core/
        document-types.ts
        document-registry.ts
        output-types.ts
        paper-profiles.ts
        output-policies.ts
      branding/
        company-branding.ts
      models/
        canonical-document.ts
      renderers/
        html/
          render-document.tsx
          render-thermal.tsx
          render-report.tsx
        exports/
          csv-exporter.ts
          xlsx-exporter.ts
      workers/
        csv-worker.ts
        xlsx-worker.ts
      components/
        DocumentActions.tsx
        DocumentPreviewLayout.tsx
        PrintSurface.tsx
      hooks/
        useDocumentOutput.ts
        usePaperProfile.ts
      styles/
        print.css
        thermal.css
        pdf.css
      definitions/
        payment-receipt.definition.ts
        sales-order.definition.ts
        sales-invoice.definition.ts
        account-statement.definition.ts
        report.definition.ts
      services/
        preview-service.ts
        browser-print-service.ts
        export-service.ts
        artifact-service.ts
```

وبالنسبة للخلفية:

```text
supabase/
  functions/
    output-jobs/
    output-artifacts/
```

لكن:

- وظيفة orchestration ممكنة داخل Supabase Functions
- أما PDF render الثقيل فالأفضل له **service/worker runtime مناسب** منفصل

---

## 15) كيف نطبّق هذا على EDARA الحالية؟

## 15.1 PaymentReceiptDetail

لا تُطبع الصفحة نفسها.

يتم إنشاء:

- `payment-receipt.definition.ts`
- canonical model builder
- `ThermalReceiptLayout`
- `A4ReceiptLayout`

والصفحة الحالية تستدعي فقط `DocumentActions`.

## 15.2 SalesOrderDetail

يتم فصل:

- interactive workflow
- document output

ويُبنى:

- `sales-order.definition.ts`
- `sales-invoice.definition.ts` إذا لزم الفصل
- A4 invoice renderer
- export schema لبيانات السطور

## 15.3 Reports pages

صفحات التقارير الحالية تبقى كشاشات تحليلية.

لكن الإخراج يتم عبر:

- report document definition
- report snapshot filters
- dedicated report renderer
- async path للتقارير الثقيلة

## 15.4 DataTable

`DataTable` لا ينبغي أن يتحمل مسؤولية الطباعة الرسمية.

لكنه يمكن أن يشارك في:

- export schema helpers
- selected columns mapping

فقط.

---

## 16) معايير القبول الإنتاجية

لن نعتبر النظام جاهزًا إلا إذا تحقق ما يلي:

1. كل مستند رسمي له preview نظيف ومخصص.
2. كل مستند رسمي له طباعة صحيحة على المقاس المناسب.
3. دعم `A4` و`thermal 58/80` من أول إصدار.
4. PDF الرسمي deterministic وليس معتمدًا فقط على حفظ المتصفح.
5. CSV وXLSX يعملان من schema موحد وليس من DOM scraping.
6. المستندات الكبيرة لا تسبب تجمد الواجهة.
7. المكتبات الثقيلة lazy-loaded.
8. يوجد logging وقياس مدة وأخطاء generation.
9. يوجد fallback واضح بين browser print وserver PDF.
10. الهوية المؤسسية وبيانات الشركة تُدار مركزيًا.
11. RTL/LTR مضبوط لكل الحقول.
12. يوجد test coverage للطبقة المنطقية الأساسية.

---

## 17) الاختبارات المطلوبة

## 17.1 Unit tests

- canonical model builders
- paper profile selection
- output policy decisions
- csv/xlsx mapping

## 17.2 Integration tests

- preview route loads correct document
- correct options shown per document type
- generation path selection sync/async

## 17.3 Visual / PDF regression

- golden files أو snapshot PDFs
- A4 invoice
- thermal receipt
- multi-page report

## 17.4 Performance tests

- generation time
- memory envelope
- large report export
- simultaneous export contention

---

## 18) الإعدادات التي أوصي بإضافتها

داخل `company_settings` أو `print_settings` منطقيًا:

- `company.email`
- `company.website`
- `company.commercial_register`
- `company.footer_note`
- `print.default_locale`
- `print.default_direction`
- `print.default_a4_profile`
- `print.default_thermal_profile`
- `print.show_logo`
- `print.show_tax_number`
- `print.show_page_numbers`
- `print.thermal_density`
- `print.archive_pdf_enabled`
- `print.max_sync_rows`
- `print.max_sync_pages`
- `print.preview_image_quality`

---

## 19) القرار النهائي الموصى به

### أوصي رسميًا بما يلي:

1. بناء **منصة إخراج مستندي مركزية** من أول إصدار.
2. اعتماد **Canonical Document Model** كقلب النظام.
3. اعتماد **HTML/CSS document rendering** كأصل موحد للمعاينة والطباعة.
4. اعتماد استراتيجية PDF ثلاثية المستويات:
   - Tier 1 من اليوم الأول: `browser print` / `Save as PDF`
   - Tier 2 من اليوم الأول أو قريبًا: `@react-pdf/renderer`
   - Tier 3 عند وجود حاجة تشغيلية مثبتة: `Chromium service`
   انظر `Section 8.2` و`Section 22.2` للتفاصيل.
5. فصل **exports الثقيلة** إلى background jobs أو worker service.
6. عدم الاعتماد على `Supabase Edge Functions` وحدها لتوليد PDFs ثقيلة بشكل افتراضي بسبب حدود الموارد التشغيلية.
7. اعتماد **schema-based CSV/XLSX** بدل أي تحويل من DOM.
8. تطبيق **performance budgets** وlazy loading والتقسيم بين sync/async من أول يوم.

هذا هو المسار الأكثر احترافية، والأكثر أمانًا تشغيليًا، والأفضل على المدى الطويل.

---

## 20) Prompt محدث لكلود

```text
نحن لا نبني MVP ولا prototype. نحن نبني من أول إصدار منصة طباعة وتصدير Production-grade داخل نظام ERP/PWA اسمه EDARA، مبني حاليًا بـ React + TypeScript + Vite + Supabase.

أريد منك أن تقوم بدراسة تقنية ومعمارية عميقة جدًا من منظور Production readiness الكامل، وليس من منظور التدرج المرحلي البسيط.

السياق:
- يوجد حاليًا CSV export بسيط فقط.
- توجد بيانات الشركة الأساسية في company_settings مثل:
  - company.name
  - company.name_en
  - company.logo_url
  - company.phone
  - company.address
  - company.tax_number
- النظام عربي RTL أساسًا.
- نحتاج دعم كامل لـ:
  - invoices
  - receipts
  - statements
  - reports
  - multi-page documents
  - A4 / Letter / Legal / thermal printing
  - mobile / tablet / desktop flows
  - print / pdf / csv / xlsx

مهم جدًا:
- لا تفترض أي MVP.
- لا تقدّم approach مؤقت أو مبسط على أنه خطوة أولى.
- اعتبر أن أول إصدار يجب أن يكون Production-grade ويمكن الاعتماد عليه فعليًا.
- يجب أن تضع الأداء واستهلاك الموارد في صلب الدراسة، وليس كتحسين لاحق.

أريد منك دراسة كاملة عبر المحاور التالية:

1) Production Architecture
- اقترح architecture كاملة لمنصة إخراج مستندي مركزية.
- يجب أن تشمل:
  - document registry
  - document definitions
  - canonical document model
  - data preparation layer
  - html/print renderer
  - pdf renderer/pipeline
  - csv/xlsx exporters
  - preview workflow
  - output orchestration
  - artifact/archive strategy

2) Performance and Resource Governance
- ضع تصورًا صريحًا لكيفية منع:
  - bundle bloat
  - UI thread blocking
  - excessive memory usage
  - large report freezes
  - mobile degradation
- اقترح:
  - lazy loading strategy
  - sync vs async export policy
  - chunking/streaming policies
  - caching rules
  - observability metrics
  - performance budgets

3) PDF Strategy
- أريد رأيًا حاسمًا، لا قائمة خيارات.
- ما هو الأنسب Production-grade:
  - browser-native save as PDF
  - headless Chromium / Playwright / Puppeteer
  - hybrid strategy
- اربط قرارك بواقع مشروع React/Vite/Supabase.
- إذا كان هناك runtime معين غير مناسب لتوليد PDF الثقيل، فاذكر ذلك صراحة مع السبب.

4) Print Strategy
- كيف نبني print system احترافي يدعم:
  - named paper profiles
  - A4 and thermal
  - multi-page documents
  - page breaks
  - headers/footers
  - rtl/ltr mixed fields
  - mobile preview

5) Export Strategy
- كيف نفصل معماريًا بين:
  - document export
  - tabular data export
- كيف نبني schema-based CSV/XLSX layer احترافية؟

6) Mapping to our current codebase
- وضّح كيف يطبق هذا على:
  - PaymentReceiptDetail
  - SalesOrderDetail
  - Reports pages
  - DataTable
- ما الذي يجب فصله عن UI الحالي؟
- ما الذي يمكن إعادة استخدامه؟

7) Required Deliverables
- Executive summary
- Final architecture recommendation
- Performance and resource policy
- Risks and tradeoffs
- Acceptance criteria for production launch
- Suggested folder structure
- Suggested TypeScript interfaces
- Suggested settings keys
- Decision matrix: print vs pdf vs csv vs xlsx

تعليمات صارمة:
- استخدم مصادر رسمية أو موثوقة جدًا فقط.
- إذا كانت ميزة CSS أو PDF pipeline ليست موثوقة إنتاجيًا، فاذكر ذلك بوضوح.
- لا تعطِ اقتراحات عامة فقط؛ أريد recommendation نهائية مرجحة ومبررة.
- لا تفترض أن طباعة الشاشة الحالية تكفي.
- لا تفترض أن الأداء يمكن علاجه لاحقًا.
```

---

## 21) المراجع

- MDN `@page`
  - https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/@page
- MDN `@page size`
  - https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/@page/size
- MDN `page`
  - https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/page
- MDN `break-inside`
  - https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/break-inside
- MDN `print-color-adjust`
  - https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/print-color-adjust
- MDN `window.print()`
  - https://developer.mozilla.org/en-US/docs/Web/API/Window/print
- MDN `beforeprint`
  - https://developer.mozilla.org/en-US/docs/Web/API/Window/beforeprint_event
- MDN `afterprint`
  - https://developer.mozilla.org/en-US/docs/Web/API/Window/afterprint_event
- W3C CSS Paged Media Level 3
  - https://www.w3.org/TR/css-page-3/
- Playwright `page.pdf()`
  - https://playwright.dev/docs/api/class-page
- Puppeteer `Page.pdf()`
  - https://pptr.dev/next/api/puppeteer.page.pdf
- Puppeteer PDF generation guide
  - https://pptr.dev/guides/pdf-generation
- Supabase Edge Functions overview
  - https://supabase.com/docs/guides/functions
- Supabase Edge Functions limits
  - https://supabase.com/docs/guides/functions/limits
- React PDF
  - https://react-pdf.org/
- React PDF components
  - https://react-pdf.org/components
- React PDF styling
  - https://react-pdf.org/styling
- ExcelJS
  - https://github.com/exceljs/exceljs

---

## 22) ملحق المراجعة النقدية المركبة

هذه الفقرة تلخص ما خرجنا به بعد مراجعة نقدية إضافية مستقلة، مع اعتماد ما ثبت أنه أقوى تشغيليًا وإنتاجيًا.

## 22.1 ما نعتمده رسميًا بدون تحفظ

### أ) الفصل الكامل بين الـ UI التفاعلي ومنصة الإخراج

هذا أصبح قرارًا نهائيًا:

- لا نطبع الشاشات التفاعلية الحالية.
- لا نربط الطباعة بـ `PaymentReceiptDetail` أو `SalesOrderDetail` مباشرة.
- هذه الصفحات تستدعي فقط `DocumentActions`.
- كل ما يخص الطباعة/المعاينة/PDF/CSV/XLSX يخرج إلى `output platform`.

### ب) Canonical Document Model

هذا يظل القرار المركزي الأهم، ولا تغيير عليه.

### ج) عدم الاعتماد على Supabase Edge Functions لتوليد PDF ثقيل

هذا أيضًا قرار نهائي ولا تغيير عليه.

### د) Preview route مستقلة

اعتماد route مستقلة للمستندات هو القرار الأفضل:

- أفضل أداء
- أسهل للطباعة
- أقل تلوثًا بمنطق الشاشة الأصلية

---

## 22.2 القرارات التي عدلناها بعد المراجعة

## القرار الأول: استراتيجية PDF

### القرار السابق

الوثيقة في نسختها الأساسية رجحت `Chromium/Playwright PDF service` كطبقة PDF الرسمية من البداية.

### القرار المحدث

نعتمد الآن **استراتيجية PDF متعددة المستويات**:

#### Tier 1 — من أول يوم

- `HTML/CSS renderer`
- `window.print()`
- استخدام `Save as PDF` من نافذة الطباعة

هذا هو المسار الافتراضي الرسمي للطباعة والحفظ PDF من المتصفح.

#### Tier 2 — من أول يوم أو قريبًا جدًا

- `@react-pdf/renderer` كخيار `Download PDF` مباشر للمستندات البسيطة والمتوسطة
- يستخدم خصوصًا في:
  - الفواتير
  - الإيصالات
  - المستندات الفردية
  - الموبايل عندما نريد PDF مباشر بدون print dialog

#### Tier 3 — عند وجود حاجة تشغيلية مثبتة

- `Chromium service` عبر `Gotenberg` أو `Playwright`
- يستخدم فقط عند الحاجة إلى:
  - batch generation
  - archival compliance
  - deterministic cross-device PDFs
  - تقارير ضخمة متعددة الصفحات

### القرار النهائي

لا نبدأ بـ Chromium service كخط أول.

بل نبدأ بـ:

- Tier 1 للطباعة وحفظ PDF من نافذة المتصفح
- Tier 2 للتحميل المباشر PDF
- ونؤجل Tier 3 حتى تظهر حاجة تشغيلية حقيقية

هذا ليس تراجعًا في الجودة، بل ضبط احترافي للتكلفة والتعقيد.

---

## القرار الثاني: مكتبة XLSX

### القرار السابق

الوثيقة استشهدت بمراجع `SheetJS` دون حسم قاطع للمكتبة.

### القرار المحدث

نعتمد رسميًا:

- `exceljs`

ولا نعتمد `SheetJS CE` كخيار افتراضي للمشروع بسبب حساسية الترخيص في الاستخدام التجاري.

### السبب

- وضوح ترخيص أفضل
- API ناضجة
- formatting جيد
- دعم عملي للإنتاج
- قابلية تشغيل جيدة مع `Web Worker`

---

## القرار الثالث: headers / footers الطباعية

### القرار السابق

كان هناك انفتاح على استخدام خصائص paged media المتقدمة مثل margin boxes.

### القرار المحدث

لأقصى توافق بين المتصفحات:

- نعتمد أساسًا على `position: fixed` داخل `@media print`
- مع `@page { size; margin }`
- ومع `break-inside`, `break-before`, `break-after`

أما margin boxes المتقدمة:

- تعتبر optional enhancement
- لا يعتمد عليها نجاح المستند إنتاجيًا

---

## القرار الرابع: Thermal printing

### القرار السابق

الوثيقة كانت تتعامل مع thermal printing على أنها paper profile + CSS فقط.

### القرار المحدث

نعتمد رسميًا التفريق بين حالتين:

#### Thermal via browser print

مدعوم عندما تكون الطابعة:

- USB
- network
- أو معرفة عبر نظام التشغيل والطباعة تتم من print dialog

#### Thermal via Bluetooth mobile

هذه ليست مضمونة عبر web standards وحدها.

لذلك:

- لا نعد بها كميزة مضمونة في النسخة الويب فقط
- وإذا أصبحت requirement فعلية، تحتاج bridge أو companion app أو مسار تقني متخصص

هذا التوضيح مهم جدًا حتى لا نبني توقعًا غير واقعي.

---

## القرار الخامس: rich-text داخل CanonicalDocument

تم رصد مخاطرة XSS إذا كان المحتوى يأتي من المستخدم ويُحقن كـ HTML.

### القرار المحدث

إما:

- استبدال `rich-text` بـ `plain-text` و`markdown`

أو:

- فرض sanitization إجباري ومركزي قبل أي render

والأكثر أمانًا مبدئيًا:

- استخدام `plain-text` + line breaks
- وإضافة `markdown` لاحقًا إذا لزم

---

## 22.3 ضوابط الأداء المحدثة بأرقام صريحة

المبدأ الصحيح هو أن budgets يجب أن تكون قابلة للقياس.

### Budgets معتمدة مبدئيًا

```ts
const PERFORMANCE_BUDGETS = {
  preview_tti_ms: 1500,
  simple_pdf_ms: 3000,
  complex_pdf_ms: 8000,
  csv_sync_rows: 10000,
  xlsx_sync_rows: 5000,
  max_sync_pages: 15,
  max_in_memory_ui_rows: 500,
  blob_cleanup_delay_ms: 5000,
}
```

### Bundle policy

```ts
const ALWAYS_LAZY = [
  'exceljs',
  '@react-pdf/renderer',
]
```

### قاعدة إلزامية

- لا يوجد أي import متعلق بالإخراج داخل `main bundle`.
- كل ما يتعلق بـ PDF/XLSX يجب أن يكون lazy-loaded.

---

## 22.4 Web Workers كقرار رسمي

تمت مراجعة نقطة مهمة كانت بحاجة لتوضيح:

- التصدير الثقيل ليس كله server-side.

### القرار المحدث

نستخدم:

- `Web Worker` لـ CSV/XLSX المتوسط والكبير داخل المتصفح
- async server/service path فقط عند تجاوز budgets أو عند الحاجة للأرشفة أو batch

### متى نستخدم Web Worker؟

- CSV حتى أحجام كبيرة نسبيًا
- XLSX متوسط أو كبير
- عمليات client-side transformation التي قد تحجز الـ main thread

---

## 22.5 استراتيجية الخطوط

هذه نقطة أصبحت صريحة الآن.

### للمستندات العادية

نوصي بخط عربي موحد مثل:

- `Noto Naskh Arabic`
- أو `IBM Plex Arabic`
- أو `Cairo` إذا ثبتت جودته الطباعية الكافية

### للمستندات الحرارية

الأولوية هي:

- سرعة الفتح والطباعة
- وضوح النص

لذلك:

- لا نعتمد على web fonts الثقيلة في thermal route
- نفضل system-safe fallback
- ونوفر variant branding مناسب للطباعة الحرارية

---

## 22.6 الهيكل النهائي المرجح بعد الدمج

بعد دمج الدراستين، هذه هي التوصية الأوضح:

### قلب النظام

- `Canonical Document Model`
- `Document Registry`
- `Branding Resolver`
- `Paper Profiles`
- `Output Orchestrator`

### طبقة الإخراج

- `HTML/CSS renderer` للطباعة والمعاينة
- `@react-pdf/renderer` للتحميل PDF المباشر
- `exceljs` لـ XLSX
- `CSV exporter` محسن
- `Web Workers` للمعالجات الثقيلة داخل المتصفح

### طبقة مؤجلة عند الحاجة

- `Chromium/Gotenberg/Playwright service`

---

## 22.7 القرار التنفيذي النهائي المعتمد

بناءً على الدراسة الأساسية والمراجعة النقدية الإضافية، نعتمد الآن رسميًا ما يلي:

1. نبني منصة إخراج مستندي مركزية مستقلة عن الـ UI.
2. نعتمد `Canonical Document Model` كطبقة البيانات الموحدة.
3. الطباعة والمعاينة تعتمدان على `HTML/CSS print renderer`.
4. PDF يتبع استراتيجية 3 tiers:
   - Tier 1: browser print/save as PDF
   - Tier 2: `@react-pdf/renderer`
   - Tier 3: Chromium service عند الحاجة التشغيلية المثبتة
5. XLSX يعتمد على `exceljs`.
6. CSV/XLSX الثقيلة داخل العميل تستخدم `Web Workers`.
7. thermal printing عبر browser print مدعوم فقط في حدود USB/network/system printer workflows.
8. Bluetooth thermal على الموبايل لا يُعلن كميزة مضمونة في web-only architecture.
9. headers/footers الطباعية تعتمد أساسًا على `position: fixed` وليس margin boxes.
10. budgets والأرقام أعلاه تصبح جزءًا من معايير القبول قبل الإطلاق.
