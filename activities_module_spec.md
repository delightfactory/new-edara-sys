# موديول الأنشطة — وثيقة التصور والتخطيط الكاملة
## نظام إدارة الأنشطة الميدانية (Activities Module)

**الإصدار:** 1.0  
**تاريخ الإعداد:** مارس 2026  
**الحالة:** مسودة التخطيط — جاهزة لمراجعة فريق التطوير

---

## فهرس المحتويات

1. [نظرة عامة على الموديول](#1-نظرة-عامة-على-الموديول)
2. [هيكل الوحدات والترابط بينها](#2-هيكل-الوحدات-والترابط-بينها)
3. [الوحدة الأولى — الزيارات](#3-الوحدة-الأولى--الزيارات)
4. [الوحدة الثانية — خطط الزيارات](#4-الوحدة-الثانية--خطط-الزيارات)
5. [الوحدة الثالثة — المكالمات وخططها](#5-الوحدة-الثالثة--المكالمات-وخططها)
6. [الوحدة الرابعة — نظام الأهداف الذكي](#6-الوحدة-الرابعة--نظام-الأهداف-الذكي)
7. [الوحدة الخامسة — لوحات المتابعة والتقارير](#7-الوحدة-الخامسة--لوحات-المتابعة-والتقارير)
8. [نظام الإشعارات الذكية](#8-نظام-الإشعارات-الذكية)
9. [قاعدة البيانات — Schema الكامل](#9-قاعدة-البيانات--schema-الكامل)
10. [الصلاحيات والأمان (RLS)](#10-الصلاحيات-والأمان-rls)
11. [السيناريوهات الحرجة والحالات الاستثنائية](#11-السيناريوهات-الحرجة-والحالات-الاستثنائية)
12. [متطلبات الأداء والتقنية](#12-متطلبات-الأداء-والتقنية)
13. [خريطة الحالات (State Machines)](#13-خريطة-الحالات-state-machines)
14. [خطة التطوير والأولويات](#14-خطة-التطوير-والأولويات)
15. [الفجوات والمتطلبات التكميلية](#15-الفجوات-والمتطلبات-التكميلية)

---

## 1. نظرة عامة على الموديول

### الهدف الاستراتيجي

موديول الأنشطة هو **الأداة التشغيلية المركزية** لإدارة وتوجيه الفريق الميداني. يربط ما بين الجهد الميداني اليومي (زيارات + مكالمات) وبين الأهداف المؤسسية (مبيعات + تحصيل + نمو قاعدة العملاء)، ويوفر للإدارة رؤية لحظية كاملة على مستوى الأداء.

### المبادئ التصميمية الأساسية

| المبدأ | التطبيق |
|--------|---------|
| **Real-time** | كل نشاط يُحدِّث الأهداف فوراً عند الحفظ |
| **Offline-first** | يعمل بدون إنترنت ويتزامن عند الاتصال |
| **Mobile-first** | واجهة المندوب مصممة أولاً للموبايل |
| **الشفافية الكاملة** | كل موظف يرى تقدمه في الوقت الحقيقي |
| **التدخل الاستباقي** | التنبيهات تسبق المشكلة لا تتبعها |
| **المرونة** | الأهداف قابلة للتعديل بدون كود جديد |

### الأدوار المستفيدة

```
CEO / الإدارة العليا
  └─ رؤية استراتيجية: KPI الشركة، مقارنة الفروع، الاتجاهات

مدير المبيعات / المشرف
  └─ رؤية تشغيلية: أداء فريقه، الأهداف الجماعية، التدخل والتوجيه

المندوب الميداني
  └─ رؤية يومية: خطتي اليوم، أهدافي، نشاطاتي، مستحقاتي
```

---

## 2. هيكل الوحدات والترابط بينها

```
┌─────────────────────────────────────────────────────────────────┐
│                     موديول الأنشطة                              │
│                                                                   │
│  ┌─────────────────┐    ┌─────────────────┐                     │
│  │  خطط الزيارات  │───▶│    الزيارات     │──┐                  │
│  │  (Unit 2)       │    │    (Unit 1)      │  │                  │
│  └─────────────────┘    └─────────────────┘  │                  │
│                                               │                  │
│  ┌─────────────────┐    ┌─────────────────┐  ├──▶ ┌──────────┐ │
│  │  خطط المكالمات │───▶│   المكالمات     │  │    │  محرك   │ │
│  │  (Unit 3b)      │    │   (Unit 3a)     │──┤    │ الأهداف │ │
│  └─────────────────┘    └─────────────────┘  │    │ (Unit 4)│ │
│                                               │    └────┬─────┘ │
│  ┌─────────────────────────────────────────┐ │         │        │
│  │         طلبات البيع / التحصيل          │─┘         │        │
│  │         (من موديولات أخرى)             │           │        │
│  └─────────────────────────────────────────┘           │        │
│                                                         ▼        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │           لوحات المتابعة والتقارير (Unit 5)              │   │
│  │    مندوب          مشرف/مدير          إدارة عليا          │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                نظام الإشعارات الذكية                     │   │
│  │         (يخترق كل الوحدات ويربطها بالمستخدم)            │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### قاعدة التكامل المركزية

```
أي نشاط مُكتمل (زيارة / مكالمة)
    │
    ├──▶ يُحدِّث visit_plan_items / call_plan_items (حالة البند)
    ├──▶ يُشغِّل Trigger → يُحدِّث target_progress
    ├──▶ يُصدر إشعاراً للأطراف المعنية
    └──▶ يظهر فوراً في لوحات المتابعة
```

---

## 3. الوحدة الأولى — الزيارات

### 3.1 تعريف الوحدة

تسجيل كل تفاعل ميداني للمندوب مع العميل بشكل موثق ومربوط بالبيانات التشغيلية. الزيارة هي **الوحدة الأساسية للإنتاج الميداني** — كل زيارة تُولِّد بيانات تُغذِّي الأهداف وتُبني منها التقارير.

### 3.2 أنواع الزيارات

| النوع | الوصف | GPS مطلوب؟ | عميل مطلوب؟ |
|-------|--------|-----------|------------|
| `visit_planned` | زيارة مدرجة في خطة اليوم | نعم | نعم |
| `visit_unplanned` | زيارة مفاجئة لعميل موجود | نعم | نعم |
| `visit_exploratory` | زيارة استكشافية لمنطقة جديدة | نعم | لا |
| `visit_prospect` | زيارة عميل محتمل (lead) | نعم | لا — lead_id |
| `visit_complaint` | زيارة لمتابعة شكوى مسجلة | نعم | نعم |
| `visit_collection` | زيارة هدفها تحصيل دين | نعم | نعم |
| `visit_promo` | زيارة ترويج منتج / حملة | نعم | نعم |

### 3.3 رحلة المستخدم — المندوب الميداني

#### المرحلة الأولى: قبل الزيارة

```
[فتح التطبيق صباحاً]
    │
    ▼
[عرض قائمة اليوم]
    ├── العملاء المرتبون حسب التسلسل
    ├── الوقت المقدر لكل زيارة
    ├── ملاحظات خاصة (خامل / مديون / حملة)
    ├── عدادات: منجز / متبقي / نسبة اليوم
    └── تنبيهات: أولويات عالية، callbacks مجدولة

[اختيار عميل من القائمة أو بحث]
    │
    ▼
[صفحة ملف العميل السريع]
    ├── الرصيد الحالي والحد الائتماني
    ├── آخر طلب وتاريخه وقيمته
    ├── آخر زيارة وعدد أيام منذها
    ├── الديون المتأخرة (إن وجدت)
    ├── الأهداف المرتبطة بهذا العميل (تنشيط / ترقية)
    └── ملاحظات المشرف إن وجدت
```

#### المرحلة الثانية: أثناء الزيارة

```
[الضغط على "بدء الزيارة"]
    │
    ▼
[تسجيل GPS تلقائي]
    ├── داخل النطاق (< radius_meters من موقع العميل)
    │       └── [gps_verified = true] → متابعة طبيعية
    └── خارج النطاق (> radius_meters)
            ├── [تنبيه للمندوب]: "أنت على بُعد Xم من الموقع المسجل"
            ├── [خيار]: "تأكيد المتابعة يدوياً"
            └── [يُسجَّل]: distance_meters, gps_verified = false
                          + تنبيه للمشرف فقط (لا يوقف المندوب)

[تسجيل start_time]

[تعبئة نموذج الزيارة]
    ├── موضوع الزيارة (select + text حر)
    ├── ملاحظات (text area)
    ├── مرفقات (صورة / توقيع / ملف)
    └── حقول ديناميكية حسب نوع الزيارة:
            visit_promo   → campaign_id, منتج مستهدف
            visit_complaint → complaint_id
            visit_collection → مبلغ مستهدف
```

#### المرحلة الثالثة: تسجيل النتيجة

```
[اختيار نتيجة الزيارة — outcome_type]
    │
    ├── order_placed      → [ينشئ طلب بيع مباشرة من نفس الشاشة]
    │                         └── order_id يُربط بالزيارة
    │
    ├── collection        → [ينشئ سند قبض]
    │                         └── collection_amount, receipt_id
    │
    ├── followup_scheduled → [يُجدِّل نشاط مستقبلي]
    │                         └── callback_at, followup_type
    │
    ├── refused           → [يُسجَّل سبب الرفض]
    │                         └── refuse_reason (select + text)
    │
    ├── closed            → [محل مغلق / لم يجده]
    │                         └── closed_reason
    │
    ├── complaint         → [ينشئ تذكرة شكوى]
    │                         └── complaint_id يُربط
    │
    └── promotion         → [يُسجَّل منتج + كمية معروضة]
                              └── يُحتسب في هدف الحملة

[تسجيل end_time → حساب duration_minutes تلقائياً]

[حفظ]
    ├── Online  → حفظ مباشر + trigger للأهداف
    └── Offline → يُخزَّن في IndexedDB
                  → يُرفع عند الاتصال
                  → is_offline_sync = true
                  → synced_at يُسجَّل
```

### 3.4 رحلة المستخدم — المشرف

```
[لوحة المشرف — Real-time]
    │
    ├── خريطة حية: مواقع المندوبين + حالة كل منهم
    ├── قائمة نشاطات اليوم: كل زيارة تظهر فور حفظها
    ├── تنبيه فوري عند:
    │       - زيارة عميل A-class تنتهي بـ "رفض"
    │       - مندوب خارج منطقته بشكل غير مبرر
    │       - مندوب لم يسجل نشاطاً > 4 ساعات عمل
    │       - GPS مرفوض بشكل متكرر (> 3 مرات يومياً)
    │
    └── إجراءات المشرف:
            - تعديل خطة اليوم
            - إرسال ملاحظة للمندوب
            - إعادة توزيع زيارة فائتة
            - تصعيد شكوى
```

### 3.5 نموذج البيانات — جدول activities

```sql
activities:
  -- المعرّفات الأساسية
  id                  UUID        PK DEFAULT gen_random_uuid(),
  type_id             UUID        FK → activity_types NOT NULL,
  employee_id         UUID        FK → employees NOT NULL,
  customer_id         UUID        FK → customers,           -- NULL: زيارة استكشافية
  lead_id             UUID        FK → leads,               -- للعملاء المحتملين
  plan_item_id        UUID        FK → visit_plan_items,    -- NULL: غير مخططة

  -- محتوى الزيارة
  subject             VARCHAR(500),
  subject_type        VARCHAR(100),                         -- من قائمة محددة
  outcome_type        VARCHAR(50)  NOT NULL,
  -- ENUM: order_placed, collection, followup_scheduled,
  --       refused, closed, complaint, promotion, exploratory
  outcome_notes       TEXT,
  refuse_reason       VARCHAR(255),                         -- عند الرفض
  closed_reason       VARCHAR(255),                         -- عند الإغلاق

  -- الموقع الجغرافي
  gps_lat             NUMERIC(10,7),
  gps_lng             NUMERIC(10,7),
  gps_verified        BOOLEAN      DEFAULT false,
  distance_meters     INTEGER,                              -- المسافة من موقع العميل

  -- التوقيت
  start_time          TIMESTAMPTZ,
  end_time            TIMESTAMPTZ,
  duration_minutes    INTEGER GENERATED ALWAYS AS
                      (EXTRACT(EPOCH FROM (end_time - start_time)) / 60)::INTEGER STORED,
  activity_date       DATE         NOT NULL,

  -- الروابط مع عمليات أخرى
  order_id            UUID         FK → sales_orders,
  collection_id       UUID         FK → payment_receipts,
  complaint_id        UUID         FK → complaints,
  campaign_id         UUID         FK → promotions,
  followup_activity_id UUID        FK → activities,        -- للزيارة الناتجة

  -- المرفقات والبيانات الإضافية
  attachments         JSONB        DEFAULT '[]',
  -- Format: [{"url":"...","type":"image|pdf|signature","name":"...","size":1234}]
  metadata            JSONB        DEFAULT '{}',
  -- بيانات إضافية خاصة بنوع الزيارة

  -- حالة المزامنة
  is_offline_sync     BOOLEAN      DEFAULT false,
  synced_at           TIMESTAMPTZ,
  device_id           VARCHAR(100),                         -- للتتبع والتحقق

  -- التدقيق
  created_by          UUID         FK → users NOT NULL,
  created_at          TIMESTAMPTZ  DEFAULT now(),
  updated_at          TIMESTAMPTZ  DEFAULT now(),
  deleted_at          TIMESTAMPTZ                           -- Soft delete

-- ===== أنواع الأنشطة =====
activity_types:
  id                  UUID        PK,
  name                VARCHAR(100) NOT NULL,
  code                VARCHAR(50)  UNIQUE NOT NULL,
  -- visit_planned, visit_unplanned, call_outbound, call_inbound, ...
  category            VARCHAR(50), -- visit / call / task
  icon                VARCHAR(50),
  requires_gps        BOOLEAN     DEFAULT true,
  requires_customer   BOOLEAN     DEFAULT true,
  requires_outcome    BOOLEAN     DEFAULT true,
  default_duration_min INTEGER    DEFAULT 30,
  is_active           BOOLEAN     DEFAULT true,
  sort_order          INTEGER     DEFAULT 0
```

### 3.6 الفهارس المطلوبة

```sql
-- الأهم للأداء
CREATE INDEX idx_activities_employee_date
  ON activities(employee_id, activity_date DESC);

CREATE INDEX idx_activities_customer_date
  ON activities(customer_id, activity_date DESC)
  WHERE customer_id IS NOT NULL;

CREATE INDEX idx_activities_outcome_type
  ON activities(outcome_type, activity_date DESC);

CREATE INDEX idx_activities_plan_item
  ON activities(plan_item_id)
  WHERE plan_item_id IS NOT NULL;

CREATE INDEX idx_activities_date_type
  ON activities(activity_date, type_id);

-- للأهداف (الأكثر استخداماً في الحسابات)
CREATE INDEX idx_activities_employee_date_type
  ON activities(employee_id, activity_date, type_id);
```

---

## 4. الوحدة الثانية — خطط الزيارات

### 4.1 تعريف الوحدة

خطة الزيارات هي "الجدول اليومي الذكي" للمندوب. تحدد مسبقاً قائمة العملاء المستهدفين وترتيبهم والوقت المقدر لكل زيارة. الفارق الجوهري: **الزيارة حدث منجز، والخطة تعهد مسبق.**

### 4.2 أنواع الخطط

| النوع | الوصف | التكرار |
|-------|--------|---------|
| `daily` | خطة يوم واحد محدد | يومي |
| `weekly` | خطة أسبوع كامل (5 أيام) | أسبوعي |
| `recurring` | خطة تتكرر تلقائياً (يومية / أسبوعية) | تلقائي |
| `campaign` | خطة مرتبطة بحملة ترويجية محددة | موقوتة |

### 4.3 التدفق التشغيلي الكامل

```
[المشرف] إنشاء الخطة
    │
    ├── تحديد الموظف + التاريخ
    ├── اختيار نوع الخطة
    └── مصدر العملاء:
            أ) اختيار يدوي من قائمة العملاء
            ب) نسخ من خطة سابقة (template)
            ج) توليد تلقائي حسب معايير:
                - عملاء لم تتم زيارتهم > X أيام
                - عملاء خاملون في المنطقة الجغرافية
                - عملاء لديهم ديون متأخرة
                - عملاء مستهدفون بحملة نشطة

    ▼
[ترتيب وتخصيص]
    ├── تحديد تسلسل الزيارات (sequence)
    ├── تحديد الوقت المقدر لكل زيارة (planned_time)
    ├── تحديد المدة المتوقعة (estimated_duration_min)
    ├── تحديد الأولوية (high / normal / low)
    └── إضافة هدف / ملاحظة لكل عميل

    ▼
[اعتماد الخطة — status: confirmed]
    │
    ├── [النظام] إشعار فوري للمندوب (push + in-app)
    ├── [النظام] تحديث visit_plan_items.status → pending
    └── [النظام] جدولة تذكير صباحي (7 AM)

    ▼
[المندوب] تنفيذ الخطة
    │
    ├── استلام الخطة → عرض قائمة مرتبة + خريطة
    ├── تنفيذ الزيارات واحدة تلو الأخرى
    │       ├── كل زيارة مكتملة → plan_item.status = completed
    │       │                     → activity_id يُربط بالبند
    │       └── زيارة فائتة → plan_item.status = skipped
    │                          → skip_reason مطلوب
    └── في نهاية اليوم → plan.status تُحدَّث تلقائياً

    ▼
[النظام] حساب الإنجاز التلقائي
    ├── completion_pct = (completed / total) × 100
    ├── تحديث plan.status:
    │       completed : pct = 100%
    │       partial   : 0 < pct < 100%
    │       missed    : لم تُنفَّذ ولم تتجاوز نهاية اليوم
    └── ترحيل البنود المتبقية للخطة التالية (اختياري)
```

### 4.4 قواعد العمل (Business Rules)

```
BR-VP-01: لا يجوز وجود خطتان لنفس الموظف في نفس التاريخ
          UNIQUE CONSTRAINT: (employee_id, plan_date)

BR-VP-02: لا يمكن للمندوب تعديل الخطة — يرسل طلب تعديل للمشرف

BR-VP-03: الخطة المعتمدة لا يمكن حذفها — تُلغى فقط (status: cancelled)
          مع تسجيل سبب الإلغاء

BR-VP-04: في حال الإلغاء بعد بدء التنفيذ → الزيارات المنجزة تبقى كما هي

BR-VP-05: عميل واحد يمكن أن يظهر مرة واحدة فقط في خطة اليوم نفسه
          UNIQUE CONSTRAINT: (plan_id, customer_id)

BR-VP-06: الترتيب (sequence) يبدأ من 1 ولا يُكرَّر في نفس الخطة

BR-VP-07: إذا لم تُعتمَد الخطة بحلول ساعة 8 صباحاً → تنبيه للمشرف

BR-VP-08: الخطة التي مضت دون تنفيذ أي بند → تُحوَّل تلقائياً إلى status: missed
          ويُرسَل تقرير للمشرف
```

### 4.5 نموذج البيانات

```sql
visit_plans:
  id                  UUID        PK DEFAULT gen_random_uuid(),
  employee_id         UUID        FK → employees NOT NULL,
  plan_date           DATE        NOT NULL,
  plan_type           VARCHAR(20) DEFAULT 'daily',
  -- ENUM: daily, weekly, campaign, recurring
  status              VARCHAR(20) DEFAULT 'draft',
  -- ENUM: draft, confirmed, in_progress, completed, partial, cancelled, missed
  template_id         UUID        FK → visit_plan_templates,
  campaign_id         UUID        FK → promotions,

  -- إحصائيات (تُحسَّب تلقائياً)
  total_customers     INTEGER     DEFAULT 0,
  completed_count     INTEGER     DEFAULT 0,
  skipped_count       INTEGER     DEFAULT 0,
  missed_count        INTEGER     DEFAULT 0,
  completion_pct      NUMERIC(5,2) GENERATED ALWAYS AS (
    CASE WHEN total_customers = 0 THEN 0
         ELSE (completed_count::NUMERIC / total_customers * 100)
    END
  ) STORED,

  notes               TEXT,
  cancellation_reason TEXT,
  confirmed_at        TIMESTAMPTZ,
  confirmed_by        UUID        FK → users,
  created_by          UUID        FK → users NOT NULL,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now(),

  UNIQUE (employee_id, plan_date)


visit_plan_items:
  id                      UUID        PK DEFAULT gen_random_uuid(),
  plan_id                 UUID        FK → visit_plans ON DELETE CASCADE NOT NULL,
  customer_id             UUID        FK → customers NOT NULL,
  sequence                INTEGER     NOT NULL,
  planned_time            TIME,
  estimated_duration_min  INTEGER     DEFAULT 30,
  priority                VARCHAR(10) DEFAULT 'normal',
  -- ENUM: high, normal, low
  purpose                 TEXT,
  purpose_type            VARCHAR(50),
  -- ENUM: sales, collection, activation, promotion, followup, complaint

  status                  VARCHAR(20) DEFAULT 'pending',
  -- ENUM: pending, in_progress, completed, skipped, rescheduled
  actual_arrival_time     TIMESTAMPTZ,
  activity_id             UUID        FK → activities,
  skip_reason             VARCHAR(500),
  reschedule_to           DATE,

  created_at              TIMESTAMPTZ DEFAULT now(),
  updated_at              TIMESTAMPTZ DEFAULT now(),

  UNIQUE (plan_id, customer_id),
  UNIQUE (plan_id, sequence)


visit_plan_templates:
  id            UUID        PK DEFAULT gen_random_uuid(),
  name          VARCHAR(200) NOT NULL,
  employee_id   UUID        FK → employees,
  branch_id     UUID        FK → branches,    -- قالب لفرع كامل
  recurrence    VARCHAR(20),
  -- ENUM: none, daily, weekly, monthly
  day_of_week   INTEGER[],                    -- [1,3,5] = الاثنين والأربعاء والجمعة
  items         JSONB,
  -- [{"customer_id":"...", "sequence":1, "planned_time":"09:00",
  --   "estimated_duration_min":45, "priority":"high", "purpose":"collection"}]
  is_active     BOOLEAN     DEFAULT true,
  created_by    UUID        FK → users NOT NULL,
  created_at    TIMESTAMPTZ DEFAULT now()
```

---

## 5. الوحدة الثالثة — المكالمات وخططها

### 5.1 تعريف الوحدة

المكالمة تعمل بمنطق مشابه للزيارة في 80% من الحالات، مع اختلافات جوهرية في: اتجاه الاتصال (وارد/صادر)، ونتائج خاصة، وعدم اشتراط GPS. خطط المكالمات أداة استهداف قوية لشرائح محددة.

### 5.2 أنواع المكالمات

| النوع | الوصف | الاتجاه |
|-------|--------|---------|
| `call_outbound_sales` | مكالمة مبيعات صادرة | صادر |
| `call_outbound_collection` | مكالمة تحصيل صادرة | صادر |
| `call_outbound_followup` | متابعة طلب / شحنة | صادر |
| `call_outbound_promo` | تعريف بمنتج / عرض | صادر |
| `call_outbound_activation` | تنشيط عميل خامل | صادر |
| `call_inbound_order` | طلب وارد من عميل | وارد |
| `call_inbound_complaint` | شكوى واردة | وارد |
| `call_inbound_inquiry` | استفسار عام | وارد |

### 5.3 التدفق التشغيلي — المكالمة الصادرة

```
[المندوب] بدء المكالمة
    │
    ├── من خطة مكالمات   → يُحمَّل العميل تلقائياً
    └── مكالمة عشوائية   → بحث وتحديد العميل

    ▼
[تسجيل بدء المكالمة]
    ├── اتجاه: outbound
    ├── start_time مُسجَّل
    └── لا GPS مطلوب

    ▼
[أثناء المكالمة]
    ├── تعبئة موضوع المكالمة
    └── تسجيل ملاحظات سريعة

    ▼
[تسجيل النتيجة — call_result]
    │
    ├── answered
    │     └── [النتيجة الفعلية — outcome_type]
    │           ├── agreed_order   → ينشئ طلب بيع
    │           ├── promised_payment → إضافة للتحصيل المتوقع
    │           ├── followup_visit → ينشئ خطة زيارة
    │           ├── complaint      → ينشئ تذكرة
    │           ├── not_interested → يُسجَّل السبب
    │           └── info_only      → مكالمة معلوماتية
    │
    ├── no_answer
    │     ├── attempt_count يُزاد بواحد
    │     ├── إذا attempts >= 3 → ينبّه المشرف
    │     └── يُجدِّل إعادة محاولة تلقائية (بعد X ساعات)
    │
    ├── busy
    │     └── يُجدِّل إعادة محاولة (بعد 30 دقيقة)
    │
    ├── callback_scheduled
    │     └── callback_at يُحدَّد ← تذكير للمندوب
    │
    └── wrong_number
          └── تحديث رقم العميل مطلوب (flag للمشرف)

    ▼
[حفظ + تحديث الأهداف]
```

### 5.4 خطط المكالمات — أنواع الاستهداف

```
┌─────────────────────────────────────────────────────────────┐
│                     خطط المكالمات                            │
├──────────────────┬──────────────────────────────────────────┤
│ النوع            │ شروط التوليد التلقائي                    │
├──────────────────┼──────────────────────────────────────────┤
│ متأخرو الدفع     │ customer.overdue_days > 30               │
│                  │ مرتبون: الأقدم أولاً                      │
│                  │ أولوية: عالية                              │
├──────────────────┼──────────────────────────────────────────┤
│ تنشيط خاملين    │ آخر طلب > dormancy_days (60 افتراضي)     │
│                  │ لديهم سجل شراء سابق                        │
│                  │ مرتبون: القيمة الأعلى أولاً               │
├──────────────────┼──────────────────────────────────────────┤
│ تعريف منتج       │ لم يشتروا product_id محدد من قبل          │
│                  │ مرتبون: إمكانية الشراء                    │
│                  │ مرتبطون بحملة campaign_id                 │
├──────────────────┼──────────────────────────────────────────┤
│ متابعة تسليم     │ طلب تم تسليمه منذ X أيام                 │
│                  │ لم تتم مكالمة متابعة بعده                │
│                  │ هدف: رضا العميل + فرصة بيع               │
├──────────────────┼──────────────────────────────────────────┤
│ ترقية تصنيف      │ عملاء يشترون تصنيف A فقط                 │
│                  │ مؤهلون لتصنيف B أو C                      │
│                  │ هدف: توسيع نطاق المنتجات                  │
├──────────────────┼──────────────────────────────────────────┤
│ مخصص             │ فلاتر يحددها المشرف يدوياً                │
└──────────────────┴──────────────────────────────────────────┘
```

### 5.5 نموذج البيانات — المكالمات

```sql
-- المكالمات تستخدم جدول activities الرئيسي
-- + جدول call_details للبيانات الخاصة بالمكالمات

call_details:
  id                  UUID        PK DEFAULT gen_random_uuid(),
  activity_id         UUID        FK → activities UNIQUE NOT NULL,
  direction           VARCHAR(10) NOT NULL,
  -- ENUM: inbound, outbound
  call_result         VARCHAR(30) NOT NULL,
  -- ENUM: answered, no_answer, busy, callback_scheduled,
  --       wrong_number, rejected
  attempt_count       INTEGER     DEFAULT 1,
  callback_at         TIMESTAMPTZ,
  call_recording_url  TEXT,                              -- رابط تسجيل اختياري
  call_plan_item_id   UUID        FK → call_plan_items,
  created_at          TIMESTAMPTZ DEFAULT now()


call_plans:
  id                  UUID        PK DEFAULT gen_random_uuid(),
  name                VARCHAR(200) NOT NULL,
  target_type         VARCHAR(30) NOT NULL,
  -- ENUM: overdue, dormant, new_product, post_delivery,
  --       upgrade_category, custom
  filter_criteria     JSONB       NOT NULL,
  -- {"min_overdue_days":30, "product_id":"...",
  --  "dormancy_days":60, "governorate_id":"...",
  --  "min_previous_orders":3}
  assigned_to_role    VARCHAR(50),
  -- ENUM: sales_rep, supervisor, any
  period_start        DATE,
  period_end          DATE,
  target_calls_per_rep INTEGER    DEFAULT 0,
  priority            INTEGER     DEFAULT 5,
  status              VARCHAR(20) DEFAULT 'draft',
  -- ENUM: draft, active, paused, completed, cancelled
  auto_reassign       BOOLEAN     DEFAULT false,
  created_by          UUID        FK → users NOT NULL,
  created_at          TIMESTAMPTZ DEFAULT now()


call_plan_items:
  id                  UUID        PK DEFAULT gen_random_uuid(),
  plan_id             UUID        FK → call_plans ON DELETE CASCADE NOT NULL,
  customer_id         UUID        FK → customers NOT NULL,
  assigned_to         UUID        FK → employees NOT NULL,
  priority            INTEGER     DEFAULT 5,
  status              VARCHAR(20) DEFAULT 'pending',
  -- ENUM: pending, in_progress, called, skipped,
  --       callback_pending, failed
  activity_id         UUID        FK → activities,
  attempt_count       INTEGER     DEFAULT 0,
  max_attempts        INTEGER     DEFAULT 3,
  last_attempt_at     TIMESTAMPTZ,
  next_attempt_at     TIMESTAMPTZ,
  notes               TEXT,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
```

---

## 6. الوحدة الرابعة — نظام الأهداف الذكي

### 6.1 الأهمية الاستراتيجية

نظام الأهداف هو **قلب الموديول النابض** وأهم وأعقد وحدة فيه. هو أداة التحكم والتوجيه التي تحوّل الاستراتيجية إلى أرقام يومية قابلة للمتابعة والقياس لكل موظف في كل مستوى.

### 6.2 أنواع الأهداف (9 أنواع)

```
┌──────────────────────────────────────────────────────────────────┐
│                     أنواع الأهداف                                │
├───────────────────┬────────────────────┬─────────────────────────┤
│ الكود             │ الاسم               │ مصدر الحساب             │
├───────────────────┼────────────────────┼─────────────────────────┤
│ sales_value       │ مبيعات مالية       │ SUM(sales_orders.total) │
│                   │                    │ حيث status=delivered     │
├───────────────────┼────────────────────┼─────────────────────────┤
│ collection        │ تحصيلات            │ SUM(payment_receipts.   │
│                   │                    │ amount) في الفترة        │
├───────────────────┼────────────────────┼─────────────────────────┤
│ product_qty       │ كميات منتج محدد   │ SUM(order_items.qty)    │
│                   │                    │ حيث product_id / cat_id  │
├───────────────────┼────────────────────┼─────────────────────────┤
│ visits_count      │ عدد الزيارات       │ COUNT(activities)        │
│                   │                    │ حيث type=visit           │
├───────────────────┼────────────────────┼─────────────────────────┤
│ calls_count       │ عدد المكالمات      │ COUNT(activities)        │
│                   │                    │ حيث type=call            │
├───────────────────┼────────────────────┼─────────────────────────┤
│ new_customers     │ عملاء جدد          │ COUNT(customers)         │
│                   │                    │ created_at في الفترة     │
├───────────────────┼────────────────────┼─────────────────────────┤
│ reactivation      │ تنشيط خاملين       │ COUNT(customers) اشتروا  │
│                   │                    │ بعد صمت > dormancy_days  │
├───────────────────┼────────────────────┼─────────────────────────┤
│ upgrade_value     │ رفع قيمة العملاء   │ AVG(order_value) مقارنةً │
│                   │                    │ بمتوسط الفترة السابقة    │
├───────────────────┼────────────────────┼─────────────────────────┤
│ category_spread   │ توسيع التصنيفات    │ COUNT(DISTINCT cat_id)   │
│                   │                    │ لكل عميل في الفترة       │
└───────────────────┴────────────────────┴─────────────────────────┘
```

### 6.3 المستويات الثلاثة لكل هدف

```
target_value   → الهدف الأساسي (100%)
min_value      → الحد الأدنى (عادةً 80% من target_value) — الإخفاق تحته
stretch_value  → هدف التمدد (عادةً 120% من target_value) — مكافأة إضافية
```

### 6.4 هرمية الأهداف والتوزيع التلقائي

```
هدف الشركة (Company — scope: company)
    │
    ├── فرع القاهرة (Branch — scope: branch)
    │       ├── مندوب 1 (Individual — scope: individual)
    │       ├── مندوب 2
    │       └── مندوب 3
    │
    └── فرع الإسكندرية (Branch — scope: branch)
            ├── مندوب 4
            └── مندوب 5

-- قاعدة التوزيع التلقائي (auto_split = true)
-- إذا أُنشئ هدف شركة بـ auto_split = true:
-- target_value للفرع = (نسبة مبيعاته التاريخية) × target_value الشركة
-- يمكن تعديل النسبة يدوياً بعد التوليد
```

### 6.5 آلية الحساب التلقائي

```sql
-- طريقتان للحساب:

-- 1) Trigger لحظي: عند كل عملية بيع / تحصيل / نشاط
CREATE OR REPLACE FUNCTION update_target_progress_on_activity()
RETURNS TRIGGER AS $$
BEGIN
  -- تحديث جميع الأهداف النشطة المرتبطة بهذا الموظف
  -- التي تغطي التاريخ الحالي
  PERFORM recalculate_targets_for_employee(NEW.employee_id, NEW.activity_date);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2) Cron Job ساعي: لضمان التحديث حتى في حالات الـ offline sync
-- يُنفَّذ كل ساعة عبر Supabase pg_cron
SELECT cron.schedule(
  'recalculate-target-progress',
  '0 * * * *',  -- كل ساعة
  $$
  SELECT recalculate_all_active_targets();
  $$
);

-- دالة الحساب المركزية
CREATE OR REPLACE FUNCTION recalculate_target_progress(
  p_target_id UUID,
  p_snapshot_date DATE DEFAULT CURRENT_DATE
) RETURNS VOID AS $$
DECLARE
  v_target targets%ROWTYPE;
  v_achieved NUMERIC := 0;
  v_trend VARCHAR(20);
  v_days_elapsed NUMERIC;
  v_total_days NUMERIC;
  v_expected_pct NUMERIC;
BEGIN
  SELECT * INTO v_target FROM targets WHERE id = p_target_id AND is_active;

  -- حساب القيمة المحققة حسب نوع الهدف
  CASE v_target.type_code
    WHEN 'sales_value' THEN
      SELECT COALESCE(SUM(so.total_amount), 0) INTO v_achieved
      FROM sales_orders so
      JOIN sales_reps sr ON sr.id = so.sales_rep_id
      WHERE sr.employee_id = v_target.scope_id
        AND so.status IN ('delivered', 'completed')
        AND so.delivered_at::DATE BETWEEN v_target.period_start AND v_snapshot_date
        AND (v_target.product_id IS NULL OR EXISTS (
          SELECT 1 FROM sales_order_items soi
          WHERE soi.order_id = so.id AND soi.product_id = v_target.product_id
        ));

    WHEN 'collection' THEN
      SELECT COALESCE(SUM(pr.amount), 0) INTO v_achieved
      FROM payment_receipts pr
      WHERE pr.collected_by = v_target.scope_id
        AND pr.receipt_date BETWEEN v_target.period_start AND v_snapshot_date;

    WHEN 'visits_count' THEN
      SELECT COUNT(*) INTO v_achieved
      FROM activities a
      JOIN activity_types at ON at.id = a.type_id
      WHERE a.employee_id = v_target.scope_id
        AND at.category = 'visit'
        AND a.activity_date BETWEEN v_target.period_start AND v_snapshot_date
        AND a.deleted_at IS NULL;

    WHEN 'reactivation' THEN
      SELECT COUNT(DISTINCT a.customer_id) INTO v_achieved
      FROM activities a
      WHERE a.employee_id = v_target.scope_id
        AND a.outcome_type = 'order_placed'
        AND a.activity_date BETWEEN v_target.period_start AND v_snapshot_date
        AND NOT EXISTS (
          SELECT 1 FROM sales_orders so
          WHERE so.customer_id = a.customer_id
            AND so.created_at >= v_target.period_start - (v_target.dormancy_days || ' days')::INTERVAL
            AND so.created_at < v_target.period_start
        );
    -- ... باقي الأنواع
  END CASE;

  -- حساب الاتجاه (Trend)
  v_days_elapsed := p_snapshot_date - v_target.period_start + 1;
  v_total_days   := v_target.period_end - v_target.period_start + 1;
  v_expected_pct := (v_days_elapsed / v_total_days) * 100;

  v_trend := CASE
    WHEN v_achieved >= v_target.stretch_value THEN 'exceeded'
    WHEN v_achieved >= v_target.target_value  THEN 'achieved'
    WHEN (v_achieved / v_target.target_value * 100) < (v_expected_pct - 20) THEN 'behind'
    WHEN (v_achieved / v_target.target_value * 100) < (v_expected_pct - 10) THEN 'at_risk'
    ELSE 'on_track'
  END;

  -- حفظ اللقطة
  INSERT INTO target_progress (target_id, snapshot_date, achieved_value, trend, last_calc_at)
  VALUES (p_target_id, p_snapshot_date, v_achieved, v_trend, now())
  ON CONFLICT (target_id, snapshot_date)
  DO UPDATE SET
    achieved_value = EXCLUDED.achieved_value,
    trend = EXCLUDED.trend,
    last_calc_at = EXCLUDED.last_calc_at;

END;
$$ LANGUAGE plpgsql;
```

### 6.6 نموذج البيانات — الأهداف

```sql
target_types:
  id                  UUID        PK DEFAULT gen_random_uuid(),
  name                VARCHAR(100) NOT NULL,
  code                VARCHAR(50)  UNIQUE NOT NULL,
  unit                VARCHAR(20) NOT NULL,
  -- ENUM: currency, count, percent, quantity
  category            VARCHAR(30),
  -- ENUM: financial, activity, customer, product
  auto_source         VARCHAR(50) NOT NULL,
  -- ENUM: sales_orders, payment_receipts, activities,
  --       customers, manual
  auto_calc_enabled   BOOLEAN     DEFAULT true,
  description         TEXT,
  is_active           BOOLEAN     DEFAULT true


targets:
  id                  UUID        PK DEFAULT gen_random_uuid(),
  type_id             UUID        FK → target_types NOT NULL,
  type_code           VARCHAR(50),                          -- denormalized للأداء
  name                VARCHAR(255) NOT NULL,
  description         TEXT,

  -- النطاق
  scope               VARCHAR(20) NOT NULL,
  -- ENUM: company, branch, department, individual
  scope_id            UUID,
  -- branch_id / department_id / employee_id حسب scope

  -- الفترة الزمنية
  period              VARCHAR(20) NOT NULL,
  -- ENUM: monthly, quarterly, yearly, custom
  period_start        DATE        NOT NULL,
  period_end          DATE        NOT NULL,

  -- القيم
  target_value        NUMERIC(15,2) NOT NULL,
  min_value           NUMERIC(15,2),              -- الحد الأدنى
  stretch_value       NUMERIC(15,2),              -- هدف التمدد

  -- الفلاتر التخصصية
  product_id          UUID        FK → products,
  category_id         UUID        FK → product_categories,
  governorate_id      UUID        FK → governorates,
  city_id             UUID        FK → cities,
  customer_tag        VARCHAR(100),
  dormancy_days       INTEGER,                    -- لأهداف التنشيط
  min_order_value     NUMERIC(15,2),              -- لأهداف رفع القيمة
  target_sku_count    INTEGER,                    -- لأهداف توسيع التصنيفات

  -- الهرمية
  parent_target_id    UUID        FK → targets,
  auto_split          BOOLEAN     DEFAULT false,
  split_basis         VARCHAR(20),
  -- ENUM: historical_sales, equal, manual

  -- الإدارة
  assigned_by         UUID        FK → users NOT NULL,
  is_active           BOOLEAN     DEFAULT true,
  notes               TEXT,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()


target_progress:
  id                  UUID        PK DEFAULT gen_random_uuid(),
  target_id           UUID        FK → targets NOT NULL,
  snapshot_date       DATE        NOT NULL,
  achieved_value      NUMERIC(15,2) DEFAULT 0,
  achievement_pct     NUMERIC(6,2) GENERATED ALWAYS AS (
    CASE WHEN target_value = 0 THEN 0
         ELSE (achieved_value / target_value * 100)
    END
  ) STORED,
  trend               VARCHAR(20),
  -- ENUM: on_track, at_risk, behind, achieved, exceeded
  last_calc_at        TIMESTAMPTZ,
  calc_details        JSONB,
  -- {"source_count":45, "source_ids":["..."], "breakdown":{"region1":1200}}

  UNIQUE (target_id, snapshot_date)


-- جدول تسجيل تعديلات الأهداف (Audit)
target_adjustments:
  id                  UUID        PK DEFAULT gen_random_uuid(),
  target_id           UUID        FK → targets NOT NULL,
  field_changed       VARCHAR(50),
  -- ENUM: target_value, min_value, stretch_value, period_end
  old_value           TEXT,
  new_value           TEXT,
  reason              TEXT        NOT NULL,
  adjusted_by         UUID        FK → users NOT NULL,
  adjusted_at         TIMESTAMPTZ DEFAULT now()
```

### 6.7 قواعد العمل — الأهداف

```
BR-TG-01: لا يمكن إنشاء هدف لفترة ماضية بالكامل

BR-TG-02: لا يمكن تعديل target_value بعد مرور 50% من فترة الهدف
          إلا بموافقة مدير أعلى مستوى

BR-TG-03: عند تعديل أي قيمة في الهدف → يُسجَّل في target_adjustments

BR-TG-04: هدف فردي لا يتجاوز حاصل جمع أهداف الأفراد في نفس النطاق
          (تحذير — ليس منعاً كاملاً)

BR-TG-05: الهدف المنتهية فترته يُغلق تلقائياً (is_active = false)
          ويُحسَّب achievement_pct النهائي

BR-TG-06: لا يمكن حذف هدف له progress مسجل — يُلغى فقط

BR-TG-07: هدف scope=company يرتبط تلقائياً بجميع الفروع النشطة
```

---

## 7. الوحدة الخامسة — لوحات المتابعة والتقارير

### 7.1 مبدأ الرؤية الثلاثية

```
┌────────────────────────────────────────────────────────────┐
│ مستوى المندوب — "ماذا أنجزت وما المتبقي؟"                │
│                                                              │
│  - مؤشرات أهدافي الشخصية بالتفصيل                          │
│  - خطة اليوم وحالة كل زيارة                                │
│  - عمولاتي المتوقعة لهذا الشهر                              │
│  - قائمة العملاء المرشحين للتنشيط                          │
│  - callbacks مجدولة لهذا اليوم                              │
└────────────────────────────────────────────────────────────┘
          │
          ▼
┌────────────────────────────────────────────────────────────┐
│ مستوى المشرف — "كيف يؤدي فريقي؟"                         │
│                                                              │
│  - مقارنة أداء جميع المندوبين على نفس الشاشة              │
│  - خريطة حية لمواقع المندوبين                              │
│  - تحديد من يحتاج تدخلاً فورياً                            │
│  - إنجاز خطط الزيارات لكل مندوب                           │
│  - تنبيهات بالعملاء الذين رُفضوا أو فاتتهم الزيارة        │
└────────────────────────────────────────────────────────────┘
          │
          ▼
┌────────────────────────────────────────────────────────────┐
│ مستوى الإدارة — "كيف تسير المؤسسة؟"                      │
│                                                              │
│  - مقارنة أداء الفروع                                       │
│  - مؤشرات KPI الشركة vs الأهداف الكبرى                    │
│  - أعلى وأدنى المندوبين أداءً                              │
│  - توقعات نهاية الشهر (Forecast)                           │
│  - تقارير تفصيلية قابلة للتصدير                            │
└────────────────────────────────────────────────────────────┘
```

### 7.2 مكونات لوحة المندوب

```
الشاشة الرئيسية للمندوب تحتوي على:

1) شريط الأهداف اليومية
   - نسبة إنجاز كل هدف بشريط تقدم ملوّن
   - تنبيه "تحت الحد الأدنى" بالأحمر
   - "تجاوز هدف التمدد" بالأزرق/البنفسجي

2) خطة اليوم
   - قائمة العملاء مرتبة مع حالة كل منهم
   - الوقت المتوقع والفعلي
   - زر "بدء الزيارة" الذي ينقله مباشرة

3) لوحة الإنجاز السريعة
   - زيارات اليوم: X / Y منجز
   - مبيعات اليوم: X,XXX ج.م
   - تحصيلات اليوم: X,XXX ج.م

4) قائمة callbacks اليوم
   - المواعيد المجدولة مرتبة بالوقت

5) عمولتي المتوقعة
   - حساب تلقائي بناء على الإنجاز الحالي
```

### 7.3 مكونات لوحة المشرف

```
1) جدول أداء الفريق
   - صف لكل مندوب
   - أعمدة: مبيعات، تحصيل، زيارات، عملاء جدد، حالة
   - شريط تقدم مصغَّر في كل خلية
   - Badge ملون: ممتاز / جيد / يُتابَع / في خطر

2) خريطة الميدان الحية
   - نقطة ملونة لكل مندوب (أخضر: نشط، رمادي: غير نشط)
   - مسار آخر ساعتين للمندوب
   - عند الضغط: تفاصيل آخر نشاط

3) إنجاز خطط اليوم
   - للمندوب: X/Y زيارة منجزة (%)
   - مندوبون لم يبدؤوا بعد (تنبيه)

4) تنبيهات فورية (بالترتيب)
   - عميل A-class رُفض
   - مندوب بدون نشاط > 4 ساعات
   - هدف تحت الحد الأدنى + قرب نهاية الشهر
   - زيارات فائتة لم تُجدَّل

5) أدوات التدخل
   - إرسال رسالة للمندوب
   - تعديل خطة اليوم
   - إعادة توزيع زيارة فائتة
```

### 7.4 Views المطلوبة لقاعدة البيانات

```sql
-- أداء المندوبين (يومي / شهري)
CREATE MATERIALIZED VIEW mv_rep_performance AS
SELECT
  e.id              AS employee_id,
  e.name            AS employee_name,
  b.id              AS branch_id,
  b.name            AS branch_name,
  DATE_TRUNC('month', a.activity_date) AS period,
  COUNT(a.id) FILTER (WHERE at.category = 'visit')  AS visits_count,
  COUNT(a.id) FILTER (WHERE at.category = 'call')   AS calls_count,
  COUNT(a.id) FILTER (WHERE a.outcome_type = 'order_placed') AS orders_from_activities,
  COALESCE(SUM(so.total_amount), 0)  AS sales_value,
  COALESCE(SUM(pr.amount), 0)        AS collection_value,
  COUNT(DISTINCT a.customer_id) FILTER (
    WHERE a.outcome_type = 'order_placed'
  )                                  AS active_customers
FROM employees e
JOIN branches b ON b.id = e.branch_id
LEFT JOIN activities a ON a.employee_id = e.id
LEFT JOIN activity_types at ON at.id = a.type_id
LEFT JOIN sales_orders so ON so.id = a.order_id AND so.status = 'delivered'
LEFT JOIN payment_receipts pr ON pr.collected_by = e.id
  AND DATE_TRUNC('month', pr.receipt_date) = DATE_TRUNC('month', a.activity_date)
WHERE a.deleted_at IS NULL
GROUP BY e.id, e.name, b.id, b.name, DATE_TRUNC('month', a.activity_date);

CREATE UNIQUE INDEX ON mv_rep_performance(employee_id, period);
-- تحديث كل ساعة
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_rep_performance;


-- ملخص الخطط اليومية
CREATE VIEW v_plan_daily_summary AS
SELECT
  vp.employee_id,
  vp.plan_date,
  vp.status             AS plan_status,
  vp.total_customers,
  vp.completed_count,
  vp.skipped_count,
  vp.completion_pct,
  COUNT(vpi.id) FILTER (WHERE vpi.status = 'pending')     AS pending_count,
  COUNT(vpi.id) FILTER (WHERE vpi.priority = 'high'
                          AND vpi.status = 'pending')      AS high_priority_pending
FROM visit_plans vp
LEFT JOIN visit_plan_items vpi ON vpi.plan_id = vp.id
GROUP BY vp.id;


-- حالة الأهداف مع الاتجاه
CREATE VIEW v_target_status AS
SELECT
  t.*,
  tp.achieved_value,
  tp.achievement_pct,
  tp.trend,
  tp.last_calc_at,
  t.target_value - tp.achieved_value AS remaining_value,
  t.period_end - CURRENT_DATE        AS days_remaining,
  CASE
    WHEN tp.achievement_pct >= COALESCE(t.stretch_value/t.target_value*100, 120)
      THEN 'exceeded'
    WHEN tp.achievement_pct >= 100 THEN 'achieved'
    WHEN tp.achievement_pct >= COALESCE(t.min_value/t.target_value*100, 80)
      THEN 'on_track'
    ELSE 'at_risk'
  END                                AS display_status
FROM targets t
LEFT JOIN target_progress tp ON tp.target_id = t.id
  AND tp.snapshot_date = CURRENT_DATE
WHERE t.is_active = true;
```

---

## 8. نظام الإشعارات الذكية

### 8.1 مبدأ التصميم

الإشعار الصحيح، للشخص الصحيح، في الوقت الصحيح. لا إشعارات مزعجة أو زائدة.

### 8.2 قائمة الإشعارات الكاملة

```
┌──────────────────────────────────────────────────────────────────┐
│                     إشعارات المندوب                              │
├─────────────────────────────────┬────────────────────────────────┤
│ الحدث                           │ التوقيت / الشرط               │
├─────────────────────────────────┼────────────────────────────────┤
│ خطة اليوم جاهزة                 │ 7:00 ص من يوم الخطة           │
│ تذكير callback مجدول            │ 15 دقيقة قبل callback_at      │
│ هدف في خطر                     │ pct < 60% + 70% من الفترة      │
│ هدف تحت الحد الأدنى             │ فوري عند الكشف                 │
│ تجاوزت هدف التمدد               │ فوري عند الإنجاز               │
│ عميل قريب من موقعك              │ GPS trigger: < 200م من عميل   │
│                                 │ مخطط في القائمة               │
│ عميل خامل يحتاج تنشيطاً         │ يومي الساعة 9 ص               │
│ callback لم يُتابَع              │ بعد callback_at بساعة         │
└─────────────────────────────────┴────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│                     إشعارات المشرف                               │
├─────────────────────────────────┬────────────────────────────────┤
│ الحدث                           │ التوقيت / الشرط               │
├─────────────────────────────────┼────────────────────────────────┤
│ خطة غير معتمدة قرب موعد بدء     │ 8:00 ص إذا لم تُعتمَد         │
│ مندوب بدون نشاط                 │ بعد 4 ساعات عمل بدون نشاط     │
│ عميل A-class رُفض               │ فوري عند تسجيل رفض             │
│ GPS متكرر خارج النطاق           │ > 3 مرات في يوم واحد           │
│ مندوب تحت الحد الأدنى للهدف     │ عند الكشف + أسبوعياً          │
│ زيارة فائتة لعميل مهم           │ نهاية اليوم                    │
│ هدف الفريق في خطر               │ أسبوعياً إذا pct < 70%         │
│ مندوب تجاوز هدف التمدد          │ فوري — فرصة للتحفيز            │
└─────────────────────────────────┴────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│                   إشعارات الإدارة العليا                         │
├─────────────────────────────────┬────────────────────────────────┤
│ الحدث                           │ التوقيت / الشرط               │
├─────────────────────────────────┼────────────────────────────────┤
│ فرع كامل تحت 70% من الهدف       │ أسبوعياً                      │
│ أداء الشركة لهذا الشهر          │ أسبوعي تلقائي كل إثنين        │
│ مندوب تجاوز هدف تمدد الشركة     │ فوري                           │
└─────────────────────────────────┴────────────────────────────────┘
```

### 8.3 نموذج بيانات الإشعارات

```sql
notifications:
  id                  UUID        PK DEFAULT gen_random_uuid(),
  recipient_id        UUID        FK → users NOT NULL,
  type                VARCHAR(50) NOT NULL,
  -- ENUM: plan_ready, goal_at_risk, goal_achieved, customer_nearby,
  --       rep_inactive, visit_refused_vip, callback_due, ...
  title               VARCHAR(255) NOT NULL,
  body                TEXT,
  category            VARCHAR(30),
  -- ENUM: plan, goal, activity, alert, info
  priority            VARCHAR(10) DEFAULT 'medium',
  -- ENUM: low, medium, high, critical
  action_url          TEXT,                    -- رابط التوجيه عند الضغط
  action_type         VARCHAR(30),             -- open_plan, view_goal, ...
  metadata            JSONB DEFAULT '{}',      -- بيانات إضافية للسياق
  is_read             BOOLEAN     DEFAULT false,
  read_at             TIMESTAMPTZ,
  expires_at          TIMESTAMPTZ,             -- بعضها ينتهي بانتهاء اليوم
  created_at          TIMESTAMPTZ DEFAULT now()

notification_preferences:
  user_id             UUID        FK → users,
  notification_type   VARCHAR(50),
  in_app              BOOLEAN     DEFAULT true,
  push                BOOLEAN     DEFAULT true,
  email               BOOLEAN     DEFAULT false,
  PRIMARY KEY (user_id, notification_type)
```

---

## 9. قاعدة البيانات — Schema الكامل

### 9.1 مخطط العلاقات المبسط

```
employees ──────────────────────────────────────────┐
    │                                                │
    ├──(1:N)── visit_plans ──(1:N)── visit_plan_items ──┐
    │                                                   │
    ├──(1:N)── activities ──────────────────────────────┘
    │               │
    │               ├──(N:1)── activity_types
    │               ├──(N:1)── customers
    │               ├──(N:1)── sales_orders
    │               ├──(N:1)── payment_receipts
    │               ├──(N:1)── complaints
    │               └──(1:1)── call_details
    │
    ├──(N:N)── targets (via scope_id)
    │               └──(1:N)── target_progress
    │
    └──(1:N)── call_plan_items ──(N:1)── call_plans
```

### 9.2 قائمة الجداول الكاملة

```
جداول موديول الأنشطة:
├── activity_types          (أنواع الأنشطة — master data)
├── activities              (السجل الموحد لكل الأنشطة)
├── call_details            (تفاصيل المكالمات — extension لـ activities)
├── visit_plans             (خطط الزيارات الرئيسية)
├── visit_plan_items        (بنود خطط الزيارات)
├── visit_plan_templates    (قوالب خطط متكررة)
├── call_plans              (خطط المكالمات)
├── call_plan_items         (بنود خطط المكالمات)
├── target_types            (أنواع الأهداف — master data)
├── targets                 (الأهداف المحددة)
├── target_progress         (لقطات التقدم اليومية)
├── target_adjustments      (سجل تعديلات الأهداف)
└── notifications           (الإشعارات)

Views:
├── mv_rep_performance      (materialized — أداء المندوبين الشهري)
├── v_plan_daily_summary    (ملخص الخطط اليومية)
└── v_target_status         (حالة الأهداف مع الاتجاه)
```

---

## 10. الصلاحيات والأمان (RLS)

### 10.1 مصفوفة الصلاحيات

```
┌────────────────────┬──────┬──────┬──────┬──────┬──────────┐
│ الجدول             │ CEO  │ مدير │ مشرف │ مندوب│ مخزن     │
├────────────────────┼──────┼──────┼──────┼──────┼──────────┤
│ activities         │  R   │  R   │ R/W* │ R/W**│    -     │
│ visit_plans        │  R   │ R/W  │ R/W  │  R   │    -     │
│ visit_plan_items   │  R   │ R/W  │ R/W  │  R   │    -     │
│ call_plans         │  R   │ R/W  │ R/W  │  R   │    -     │
│ call_plan_items    │  R   │  R   │ R/W  │  R   │    -     │
│ targets            │ R/W  │ R/W  │  R   │  R***│    -     │
│ target_progress    │  R   │  R   │  R   │  R***│    -     │
│ notifications      │  R   │  R   │  R   │  R   │    -     │
└────────────────────┴──────┴──────┴──────┴──────┴──────────┘

R   = قراءة فقط
R/W = قراءة وكتابة
*   = المشرف يكتب للمندوبين في فرعه فقط
**  = المندوب يكتب لنفسه فقط (employee_id = auth.uid())
*** = المندوب يقرأ أهدافه الشخصية فقط
```

### 10.2 سياسات RLS المقترحة

```sql
-- Activities: المندوب يرى فقط نشاطاته الخاصة
CREATE POLICY "activities_rep_own" ON activities
  FOR ALL
  USING (
    employee_id = (SELECT id FROM employees WHERE user_id = auth.uid())
    OR check_permission(auth.uid(), 'activities.read_all')
  );

-- Activities: الإنشاء فقط لنفسه
CREATE POLICY "activities_create_own" ON activities
  FOR INSERT
  WITH CHECK (
    employee_id = (SELECT id FROM employees WHERE user_id = auth.uid())
    AND check_permission(auth.uid(), 'activities.create')
  );

-- Visit Plans: المشرف يرى فقط فرعه
CREATE POLICY "visit_plans_branch" ON visit_plans
  FOR ALL
  USING (
    employee_id IN (
      SELECT e.id FROM employees e
      WHERE e.branch_id = (
        SELECT branch_id FROM employees WHERE user_id = auth.uid()
      )
    )
    OR check_permission(auth.uid(), 'visit_plans.read_all')
  );

-- Targets: المندوب يرى أهدافه فقط
CREATE POLICY "targets_own" ON targets
  FOR SELECT
  USING (
    (scope = 'individual' AND scope_id = (
      SELECT id FROM employees WHERE user_id = auth.uid()
    ))
    OR check_permission(auth.uid(), 'targets.read_all')
  );
```

---

## 11. السيناريوهات الحرجة والحالات الاستثنائية

### 11.1 سيناريوهات الزيارات

```
السيناريو 1: مندوب بدون إنترنت
─────────────────────────────────
الزيارة تُخزَّن في IndexedDB على الجهاز
عند عودة الاتصال: ترفع تلقائياً (background sync)
is_offline_sync = true, synced_at = وقت الرفع
في حال تعارض (نفس plan_item_id رُفع مرتين): يُؤخَذ الأحدث

السيناريو 2: GPS مرفوض أو فاشل
─────────────────────────────────
المندوب لا يُوقَف — يكمل الزيارة يدوياً
gps_verified = false, distance_meters = null
تنبيه يصل للمشرف فقط (لا للمندوب)
تجاوز GPS بشكل متكرر (> 3 في يوم): تقرير يومي للمشرف

السيناريو 3: عميل غير موجود في النظام
──────────────────────────────────────
خيار "عميل محتمل" → ينشئ lead بدلاً من customer
lead_id يُربط بالزيارة بدلاً من customer_id
بعد تحويل الـ lead إلى عميل → الزيارة تنتقل تلقائياً

السيناريو 4: رفض متكرر من نفس العميل
──────────────────────────────────────
بعد 3 رفوضات لنفس العميل خلال شهر:
تنبيه للمشرف مع ملخص السبب
المشرف يقرر: تصعيد / إعادة تسعير / شطب

السيناريو 5: مندوب ينسى إغلاق الزيارة
─────────────────────────────────────────
end_time يُحدَّث تلقائياً عند:
  - بدء زيارة جديدة
  - بعد مرور max_duration (180 دقيقة افتراضياً)
  - نهاية وقت الدوام (6 مساءً مثلاً)
duration_minutes يُحسَّب وفقاً لـ end_time التلقائي

السيناريو 6: زيارة مكررة لعميل في نفس اليوم
─────────────────────────────────────────────
مسموح به (لا قيود تقنية)
رسالة تأكيد: "لديك زيارة سابقة لهذا العميل اليوم"
المندوب يؤكد المتابعة
```

### 11.2 سيناريوهات الأهداف

```
السيناريو 1: تعديل الهدف في منتصف الشهر
──────────────────────────────────────────
يُسجَّل في target_adjustments مع السبب
يُرسَل إشعار للمندوب بالتغيير
يُعاد حساب target_progress تلقائياً من تاريخ التعديل
الحسابات التاريخية قبل التعديل تبقى كما هي

السيناريو 2: هدف منتهي الصلاحية بدون إنجاز
──────────────────────────────────────────────
is_active يُضبط false تلقائياً
last_progress يُحسَّب كـ final_achievement
يُدرَج في تقرير نهاية الشهر

السيناريو 3: مندوب مُعار لفرع آخر
─────────────────────────────────────
الأنشطة تُسجَّل بـ employee_id الأصلي
الأهداف تُحسَّب للمندوب الأصلي
المشرف المعير يرى نشاطاته عبر صلاحية مؤقتة

السيناريو 4: إجازة المندوب في منتصف فترة الهدف
──────────────────────────────────────────────────
الخياران:
  أ) تجميد الهدف (target_paused = true) للفترة
  ب) تمديد فترة الهدف بعدد أيام الإجازة
يُقرَّر المشرف عبر واجهة إدارة الأهداف
```

---

## 12. متطلبات الأداء والتقنية

### 12.1 متطلبات الأداء

```
┌─────────────────────────────────────────────────────────┐
│ استجابة API                                              │
├──────────────────────────────────┬──────────────────────┤
│ قائمة زيارات اليوم (ص)          │ < 500ms              │
│ حفظ زيارة جديدة                  │ < 1s                 │
│ تحديث target_progress            │ < 2s (trigger)       │
│ تحميل لوحة المشرف               │ < 2s                 │
│ بحث العملاء (real-time)          │ < 300ms              │
└──────────────────────────────────┴──────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ العمل بدون إنترنت (Offline)                              │
├─────────────────────────────────────────────────────────┤
│ - تسجيل الزيارة كاملاً                                  │
│ - عرض قائمة اليوم (مخزنة من آخر تزامن)                 │
│ - بيانات العميل الأساسية (آخر 24 ساعة)                 │
│ - Queue للمزامنة عند عودة الاتصال                       │
└─────────────────────────────────────────────────────────┘
```

### 12.2 التقنيات المطلوبة

```
Frontend:
  - React / React Native (Expo) للموبايل
  - Zustand لإدارة الحالة
  - IndexedDB (Dexie.js) للتخزين المحلي
  - Background Sync API للمزامنة التلقائية
  - React Query للـ caching وإدارة الطلبات
  - GPS: navigator.geolocation (Web) / expo-location (Mobile)

Backend (Supabase):
  - PostgreSQL لقاعدة البيانات
  - Row Level Security لكل الجداول
  - Realtime Subscriptions للوحة الحية
  - pg_cron للحسابات المجدولة
  - Edge Functions للمنطق المعقد
  - Storage للمرفقات (صور / ملفات)

Notifications:
  - Supabase Realtime للـ in-app
  - Web Push API / Expo Notifications للـ push
  - SMTP/Resend للبريد الإلكتروني
```

---

## 13. خريطة الحالات (State Machines)

### 13.1 حالات الزيارة

```
[PENDING → من خطة مخطط] 
    → IN_PROGRESS (عند بدء الزيارة)
        → COMPLETED (حفظ ناجح)
        → SKIPPED (المندوب يتخطاها)
    → SKIPPED (المشرف يتخطاها)
```

### 13.2 حالات خطة الزيارات

```
DRAFT → CONFIRMED → IN_PROGRESS → COMPLETED
                              └→ PARTIAL
DRAFT → CANCELLED
CONFIRMED → CANCELLED (قبل البدء)
```

### 13.3 حالات الأهداف

```
ACTIVE (جارٍ الحساب)
    ↓ (نهاية الفترة)
COMPLETED (أُغلق وحُسب)
    
ACTIVE → PAUSED (إجازة / ظرف طارئ)
PAUSED → ACTIVE (استئناف)
ACTIVE → CANCELLED (إلغاء استثنائي)
```

### 13.4 اتجاه الهدف (Trend)

```
on_track  → الإنجاز يسير بالسرعة الصحيحة
at_risk   → الإنجاز يتأخر 10-20% عن المتوقع
behind    → الإنجاز يتأخر > 20% عن المتوقع
achieved  → وصل 100% قبل نهاية الفترة
exceeded  → تجاوز هدف التمدد
```

---

## 14. خطة التطوير والأولويات

### 14.1 المراحل المقترحة

```
المرحلة الأولى — الأساس (أسبوع 1-2)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
□ Migration: activity_types, activities
□ API: CRUD الزيارات
□ UI: شاشة تسجيل الزيارة (موبايل)
□ UI: قائمة نشاطاتي اليومية
□ GPS Integration
□ Offline: IndexedDB + Background Sync

المرحلة الثانية — خطط الزيارات (أسبوع 3)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
□ Migration: visit_plans, visit_plan_items, visit_plan_templates
□ API: إنشاء وإدارة الخطط
□ UI: واجهة إنشاء الخطة (ويب — للمشرف)
□ UI: عرض الخطة (موبايل — للمندوب)
□ Notifications: إشعار الخطة + تذكير صباحي
□ Auto-status: تحديث حالة بنود الخطة

المرحلة الثالثة — المكالمات (أسبوع 4)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
□ Migration: call_details, call_plans, call_plan_items
□ UI: شاشة تسجيل المكالمة
□ Logic: callback scheduling
□ Logic: auto-retry للـ no_answer
□ UI: إنشاء خطة مكالمات مع فلاتر

المرحلة الرابعة — الأهداف (أسبوع 5-6)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
□ Migration: target_types, targets, target_progress, target_adjustments
□ SQL Functions: recalculate_target_progress لكل نوع
□ Triggers: تحديث لحظي عند الأنشطة
□ pg_cron: حساب ساعي
□ UI: واجهة إنشاء الأهداف (ويب)
□ UI: لوحة الأهداف (موبايل — للمندوب)
□ Notifications: تنبيهات الأهداف

المرحلة الخامسة — اللوحات والتقارير (أسبوع 7-8)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
□ Materialized Views: mv_rep_performance
□ Views: v_plan_daily_summary, v_target_status
□ UI: لوحة المشرف (ويب)
□ UI: لوحة الإدارة (ويب)
□ Realtime: خريطة المندوبين الحية
□ Export: PDF / Excel للتقارير
```

### 14.2 معايير الإنجاز (Definition of Done)

```
لكل وحدة يجب أن يتحقق:
□ Migration مُختبَرة على بيانات حقيقية
□ RLS Policies مُختبَرة لكل دور
□ Unit Tests لكل SQL Function
□ API Tests لكل endpoint
□ Offline mode مُختبَر
□ Performance: الاستجابة ضمن الحدود المحددة
□ Notifications مُختبَرة لكل سيناريو
□ UI مُختبَرة على: iOS، Android، Chrome، Safari
□ RTL Layout صحيح على كل الشاشات
```

---

## 15. الفجوات والمتطلبات التكميلية

### 15.1 متطلبات لم تُذكَر سابقاً — ضرورية للاكتمال

```
1) إدارة العملاء المحتملين (Leads)
   ─────────────────────────────────
   جدول leads منفصل عن customers
   leads تنشأ من: زيارة استكشافية / مكالمة / إضافة يدوية
   pipeline: lead → contacted → interested → converted → customer
   الزيارة يمكن أن ترتبط بـ lead_id بدلاً من customer_id

2) نظام الاعتراضات والشكاوى (Objections / Complaints)
   ─────────────────────────────────────────────────────
   عند رفض العميل → سبب محدد من قائمة (سعر / منافس / مخزون)
   هذه الأسباب تُحلَّل في تقارير "أسباب الرفض"
   تُستخدم لتحسين الخطط المستقبلية

3) تسجيل الحضور مرتبطاً بالأنشطة
   ─────────────────────────────────
   تسجيل الحضور الصباحي يُفعِّل الزيارات
   مغادرة بدون زيارات مسجلة = تنبيه
   ربط ساعات العمل بعدد الأنشطة

4) التحقق من صحة البيانات (Data Validation)
   ──────────────────────────────────────────
   زيارة مدتها < 5 دقائق = تحقق من الصحة (تحذير)
   GPS يُسجَّل مكانين مختلفين جداً خلال دقيقتين = مستحيل
   outcome_type = order_placed بدون order_id = خطأ منطقي

5) ربط الأهداف بالعمولات
   ──────────────────────────
   الهدف المحقق ≥ 100% → يُفعِّل مخطط عمولة معين
   هدف التمدد → يُفعِّل مخطط عمولة أعلى
   هذا الربط يحتاج جدول target_commission_links

6) تقارير التنبؤ (Forecasting)
   ────────────────────────────
   بناءً على الأداء الحالي + معدل الإنجاز اليومي
   → توقع نهاية الشهر لكل هدف
   → Forecast = (achieved + daily_avg × remaining_days)

7) إدارة النزاعات (Conflict Resolution)
   ─────────────────────────────────────
   مندوبان يزوران نفس العميل في نفس اليوم: تحذير
   مندوبان لهما نفس العميل في خطتيهما: تعارض يحتاج قرار مشرف

8) نظام التقييم والمراجعة (Review System)
   ──────────────────────────────────────────
   المشرف يُقيِّم جودة الزيارات لا مجرد عددها
   visit_quality_score (1-5) يُضيفه المشرف
   يؤثر على تقييم المندوب الشامل

9) تكامل التقويم (Calendar Integration)
   ─────────────────────────────────────
   خطط الزيارات تظهر في تقويم Google / Outlook
   المواعيد تُزامَن ثنائياً

10) واجهة "رحلة المندوب" الجغرافية
    ─────────────────────────────────
    خريطة تعرض: مسار اليوم + زيارات منجزة + فائتة
    تُستخدم للمراجعة الأسبوعية ولاكتشاف أنماط التغطية
```

### 15.2 قرارات تصميم مفتوحة (للنقاش مع الفريق)

```
Q1: هل الزيارة تحتاج موافقة للحذف؟
    مقترح: لا حذف حقيقي — soft delete فقط بإذن مشرف

Q2: هل تُسجَّل زيارات الأيام الماضية؟
    مقترح: مسموح خلال 24 ساعة فقط — ما بعدها يحتاج إذن مشرف

Q3: ما الحد الأقصى لمرفقات الزيارة؟
    مقترح: 5 مرفقات × 10MB كحد أقصى لكل مرفق

Q4: هل يمكن نقل زيارة من مندوب لآخر؟
    مقترح: لا نقل — المشرف يُنشئ زيارة جديدة للمندوب الآخر

Q5: ما هو dormancy_days الافتراضي للعملاء الخاملين؟
    مقترح: 60 يوماً — قابل للتخصيص per-target

Q6: هل الأهداف تُعاد تلقائياً للشهر التالي؟
    مقترح: قوالب أهداف تُولِّد تلقائياً — ليست نسخ آلية

Q7: هل يرى المندوب أهداف زملائه؟
    مقترح: لا — لكن يرى ترتيبه في الفريق (leaderboard اختياري)
```

---

## ملحق أ — قائمة الصلاحيات الكاملة للموديول

```
activities.create               — إنشاء نشاط جديد
activities.read_own             — قراءة نشاطاته الخاصة
activities.read_team            — قراءة نشاطات الفريق
activities.read_all             — قراءة كل الأنشطة
activities.update_own           — تعديل نشاطه الخاص (< 24h)
activities.delete               — حذف (مشرف فأعلى)

visit_plans.create              — إنشاء خطة زيارات
visit_plans.read_own            — قراءة خطط فريقه
visit_plans.read_all            — قراءة كل الخطط
visit_plans.confirm             — اعتماد خطة
visit_plans.cancel              — إلغاء خطة

call_plans.create               — إنشاء خطة مكالمات
call_plans.manage               — إدارة خطط المكالمات

targets.read_own                — قراءة أهدافه الشخصية
targets.read_team               — قراءة أهداف الفريق
targets.read_all                — قراءة كل الأهداف
targets.create                  — إنشاء هدف جديد
targets.update                  — تعديل هدف قائم
targets.assign                  — تعيين هدف لموظف

reports.activities              — تقارير الأنشطة
reports.targets                 — تقارير الأهداف
reports.team_performance        — تقارير أداء الفريق
reports.export                  — تصدير التقارير
```

---

## ملحق ب — مثال على بيانات الإنشاء (Seed Data)

```sql
-- أنواع الأنشطة الأساسية
INSERT INTO activity_types (name, code, category, requires_gps, requires_customer, default_duration_min) VALUES
  ('زيارة مخططة',         'visit_planned',    'visit', true,  true,  45),
  ('زيارة مفاجئة',         'visit_unplanned',  'visit', true,  true,  30),
  ('زيارة استكشافية',      'visit_exploratory','visit', true,  false, 60),
  ('زيارة تحصيل',         'visit_collection', 'visit', true,  true,  20),
  ('زيارة ترويج',          'visit_promo',      'visit', true,  true,  30),
  ('مكالمة صادرة مبيعات', 'call_out_sales',   'call',  false, true,  10),
  ('مكالمة صادرة تحصيل',  'call_out_collect', 'call',  false, true,  10),
  ('مكالمة صادرة متابعة', 'call_out_followup','call',  false, true,  5),
  ('مكالمة واردة',         'call_inbound',     'call',  false, true,  15);

-- أنواع الأهداف
INSERT INTO target_types (name, code, unit, auto_source, auto_calc_enabled) VALUES
  ('مبيعات مالية',     'sales_value',    'currency', 'sales_orders',     true),
  ('تحصيلات',         'collection',     'currency', 'payment_receipts', true),
  ('كميات منتج',      'product_qty',    'quantity', 'sales_orders',     true),
  ('عدد زيارات',      'visits_count',   'count',    'activities',       true),
  ('عدد مكالمات',     'calls_count',    'count',    'activities',       true),
  ('عملاء جدد',       'new_customers',  'count',    'customers',        true),
  ('تنشيط خاملين',   'reactivation',   'count',    'activities',       true),
  ('رفع قيمة عميل',   'upgrade_value',  'currency', 'sales_orders',     true),
  ('توسيع تصنيفات',   'category_spread','count',    'sales_orders',     true);
```

---

*هذه الوثيقة تمثل التصور الكامل لموديول الأنشطة كما نوقش وصُوِّر في جلسة التخطيط.*  
*يجب مراجعتها مع فريق التطوير قبل البدء في كتابة أي سطر كود.*  
*أي تغيير في المتطلبات بعد بدء التطوير يُسجَّل في نسخة محدَّثة من هذه الوثيقة.*
