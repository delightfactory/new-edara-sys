-- Local empty subscription dependencies only: exact source DDL, then owned RLS configuration.
-- No module workflow, trigger, seed, function, or client table grants applied. Not a production migration.
DO $$ BEGIN
  CREATE TYPE hr_gender AS ENUM ('male', 'female');
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;

DO $$ BEGIN
  CREATE TYPE hr_marital_status AS ENUM ('single', 'married', 'divorced', 'widowed');
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;

DO $$ BEGIN
  CREATE TYPE hr_employee_status AS ENUM ('active', 'on_leave', 'suspended', 'terminated');
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;

DO $$ BEGIN
  CREATE TYPE hr_day_of_week AS ENUM ('saturday', 'sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday');
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;

DO $$ BEGIN
  CREATE TYPE hr_attendance_status AS ENUM (
    'present', 'late', 'half_day',
    'absent_unauthorized', 'absent_authorized',
    'on_leave', 'weekly_off', 'public_holiday'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;

DO $$ BEGIN
  CREATE TYPE hr_checkout_status AS ENUM (
    'on_time', 'early_authorized', 'early_unauthorized',
    'overtime', 'auto'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;

DO $$ BEGIN
  CREATE TYPE hr_review_status AS ENUM ('ok', 'needs_review', 'reviewed');
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;

CREATE TABLE IF NOT EXISTS stock_transfers (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  number            TEXT UNIQUE,    -- Trigger يملأه تلقائياً
  from_warehouse_id UUID NOT NULL REFERENCES warehouses(id),
  to_warehouse_id   UUID NOT NULL REFERENCES warehouses(id),
  status            TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'approved', 'in_transit', 'received', 'cancelled')),
  requested_by      UUID NOT NULL REFERENCES profiles(id),
  approved_by       UUID REFERENCES profiles(id),
  received_by       UUID REFERENCES profiles(id),
  notes             TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT chk_transfer_diff_warehouse CHECK (from_warehouse_id != to_warehouse_id)
);

CREATE TABLE IF NOT EXISTS expense_categories (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL UNIQUE,                      -- F1: فريد لمنع التكرار
  parent_id   UUID REFERENCES expense_categories(id),    -- هرمي
  is_active   BOOLEAN DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS expenses (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  number            TEXT UNIQUE,  -- Trigger يملأه تلقائياً
  category_id       UUID REFERENCES expense_categories(id),
  amount            NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  description       TEXT NOT NULL,
  expense_date      DATE DEFAULT CURRENT_DATE,
  status            TEXT NOT NULL CHECK (status IN (
    'draft', 'pending_approval', 'approved', 'rejected'
  )) DEFAULT 'draft',
  payment_source    TEXT CHECK (payment_source IN ('vault', 'custody')),
  vault_id          UUID REFERENCES vaults(id),
  custody_id        UUID REFERENCES custody_accounts(id),
  receipt_url       TEXT,                                     -- صورة الفاتورة/الإيصال
  branch_id         UUID REFERENCES branches(id),
  approved_by       UUID REFERENCES profiles(id),
  approved_at       TIMESTAMPTZ,
  rejection_reason  TEXT,
  created_by        UUID REFERENCES profiles(id),
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS hr_departments (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  name_en     TEXT,
  code        TEXT UNIQUE,                                    -- كود القسم للقيود المحاسبية
  parent_id   UUID REFERENCES hr_departments(id),            -- هرمي (أقسام فرعية)
  manager_id  UUID REFERENCES profiles(id),                  -- مدير القسم (يُحدَّث بعد إنشاء الموظفين)
  branch_id   UUID REFERENCES branches(id),                  -- القسم تابع لأي فرع
  is_active   BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_dept_no_self_ref CHECK (parent_id IS DISTINCT FROM id)
);

CREATE TABLE IF NOT EXISTS hr_positions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT NOT NULL,
  name_en         TEXT,
  department_id   UUID REFERENCES hr_departments(id),
  grade           INTEGER,                                    -- درجة وظيفية (1 = الأدنى)
  min_salary      NUMERIC(12,2),
  max_salary      NUMERIC(12,2),
  is_field        BOOLEAN NOT NULL DEFAULT false,             -- وظيفة ميدانية (مندوب، سائق)
  is_active       BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS hr_employees (
  -- ─── معرّفات ───
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_number   TEXT UNIQUE NOT NULL,                     -- رقم موظف ثابت لا يتغير أبداً

  -- ─── ربط المستخدم (شبه تلقائي بالإيميل) ───
  user_id           UUID UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL,
  -- NULL = موظف بحساب منفصل أو بدون حساب (عامل يدوي)

  -- ─── البيانات الشخصية ───
  full_name         TEXT NOT NULL,
  full_name_en      TEXT,
  national_id       TEXT UNIQUE,                              -- الرقم القومي
  birth_date        DATE,
  gender            hr_gender,
  marital_status    hr_marital_status,
  address           TEXT,
  personal_phone    TEXT NOT NULL,
  emergency_phone   TEXT,
  emergency_contact TEXT,                                     -- اسم جهة الاتصال الطارئ

  -- ─── بيانات التوظيف ───
  department_id     UUID REFERENCES hr_departments(id),
  position_id       UUID REFERENCES hr_positions(id),
  branch_id         UUID REFERENCES branches(id),
  direct_manager_id UUID REFERENCES hr_employees(id),         -- المدير المباشر (موظف آخر)
  status            hr_employee_status NOT NULL DEFAULT 'active',
  hire_date         DATE NOT NULL,
  probation_end_date DATE,                                    -- نهاية فترة التجربة
  termination_date  DATE,                                     -- تاريخ إنهاء الخدمة
  termination_reason TEXT,

  -- ─── العطلة الأسبوعية (NULL = يتبع إعداد الشركة) ───
  weekly_off_day    hr_day_of_week,
  -- إذا NULL: النظام يقرأ hr.weekly_off_day من company_settings

  -- ─── نمط العمل ───
  is_field_employee BOOLEAN NOT NULL DEFAULT false,           -- مندوب / سائق = يتنقل
  work_location_id  UUID,                                     -- موقع الحضور الافتراضي (FK مضافة لاحقاً)

  -- ─── الراتب الحالي (cached من hr_salary_history) ───
  base_salary       NUMERIC(12,2) NOT NULL DEFAULT 0,
  transport_allowance NUMERIC(12,2) NOT NULL DEFAULT 0,
  housing_allowance   NUMERIC(12,2) NOT NULL DEFAULT 0,
  other_allowances    NUMERIC(12,2) NOT NULL DEFAULT 0,
  -- إجمالي السطح: base_salary + allowances (computed)
  gross_salary      NUMERIC(12,2) GENERATED ALWAYS AS (
    base_salary + transport_allowance + housing_allowance + other_allowances
  ) STORED,

  -- ─── ملاحظات ───
  notes             TEXT,
  created_by        UUID REFERENCES profiles(id),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.visit_plan_templates (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        VARCHAR(200) NOT NULL,
  employee_id UUID REFERENCES hr_employees(id),
  branch_id   UUID REFERENCES branches(id),
  recurrence  VARCHAR(20) NOT NULL DEFAULT 'none'
              CHECK (recurrence IN ('none', 'daily', 'weekly', 'monthly')),
  day_of_week INTEGER[],
  items       JSONB NOT NULL DEFAULT '[]'::jsonb,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  created_by  UUID NOT NULL REFERENCES profiles(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.visit_plans (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id         UUID NOT NULL REFERENCES hr_employees(id),
  plan_date           DATE NOT NULL,
  plan_type           VARCHAR(20) NOT NULL DEFAULT 'daily'
                      CHECK (plan_type IN ('daily', 'weekly', 'campaign', 'recurring')),
  status              VARCHAR(20) NOT NULL DEFAULT 'draft'
                      CHECK (status IN ('draft', 'confirmed', 'in_progress', 'completed', 'partial', 'cancelled', 'missed')),
  template_id         UUID REFERENCES public.visit_plan_templates(id),
  total_customers     INTEGER NOT NULL DEFAULT 0 CHECK (total_customers >= 0),
  completed_count     INTEGER NOT NULL DEFAULT 0 CHECK (completed_count >= 0),
  skipped_count       INTEGER NOT NULL DEFAULT 0 CHECK (skipped_count >= 0),
  missed_count        INTEGER NOT NULL DEFAULT 0 CHECK (missed_count >= 0),
  completion_pct      NUMERIC(5,2) GENERATED ALWAYS AS (
                        CASE
                          WHEN total_customers = 0 THEN 0
                          ELSE ROUND((completed_count::NUMERIC / total_customers::NUMERIC) * 100, 2)
                        END
                      ) STORED,
  notes               TEXT,
  cancellation_reason TEXT,
  confirmed_at        TIMESTAMPTZ,
  confirmed_by        UUID REFERENCES profiles(id),
  started_at          TIMESTAMPTZ,
  completed_at        TIMESTAMPTZ,
  created_by          UUID NOT NULL REFERENCES profiles(id),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.visit_plan_items (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id                UUID NOT NULL REFERENCES public.visit_plans(id) ON DELETE CASCADE,
  customer_id            UUID NOT NULL REFERENCES customers(id),
  sequence               INTEGER NOT NULL CHECK (sequence > 0),
  planned_time           TIME,
  estimated_duration_min INTEGER NOT NULL DEFAULT 30 CHECK (estimated_duration_min > 0),
  priority               VARCHAR(10) NOT NULL DEFAULT 'normal'
                         CHECK (priority IN ('high', 'normal', 'low')),
  purpose                TEXT,
  purpose_type           VARCHAR(50)
                         CHECK (purpose_type IN ('sales', 'collection', 'activation', 'promotion', 'followup', 'service')),
  status                 VARCHAR(20) NOT NULL DEFAULT 'pending'
                         CHECK (status IN ('pending', 'in_progress', 'completed', 'skipped', 'missed', 'rescheduled')),
  actual_arrival_time    TIMESTAMPTZ,
  actual_start_time      TIMESTAMPTZ,
  actual_end_time        TIMESTAMPTZ,
  activity_id            UUID UNIQUE,
  skip_reason            VARCHAR(500),
  reschedule_to          DATE,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (plan_id, customer_id),
  UNIQUE (plan_id, sequence)
);

CREATE TABLE IF NOT EXISTS public.activity_types (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name                 VARCHAR(100) NOT NULL,
  code                 VARCHAR(50) UNIQUE NOT NULL,
  category             VARCHAR(20) NOT NULL
                       CHECK (category IN ('visit', 'call', 'task')),
  icon                 VARCHAR(50),
  requires_gps         BOOLEAN NOT NULL DEFAULT true,
  requires_customer    BOOLEAN NOT NULL DEFAULT true,
  requires_outcome     BOOLEAN NOT NULL DEFAULT true,
  default_duration_min INTEGER NOT NULL DEFAULT 30,
  is_active            BOOLEAN NOT NULL DEFAULT true,
  sort_order           INTEGER NOT NULL DEFAULT 0,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.call_plan_templates (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        VARCHAR(200) NOT NULL,
  employee_id UUID REFERENCES hr_employees(id),
  branch_id   UUID REFERENCES branches(id),
  recurrence  VARCHAR(20) NOT NULL DEFAULT 'none'
              CHECK (recurrence IN ('none', 'daily', 'weekly', 'monthly')),
  day_of_week INTEGER[],
  items       JSONB NOT NULL DEFAULT '[]'::jsonb,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  created_by  UUID NOT NULL REFERENCES profiles(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.call_plans (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id         UUID NOT NULL REFERENCES hr_employees(id),
  plan_date           DATE NOT NULL,
  plan_type           VARCHAR(20) NOT NULL DEFAULT 'daily'
                      CHECK (plan_type IN ('daily', 'weekly', 'campaign', 'recurring')),
  status              VARCHAR(20) NOT NULL DEFAULT 'draft'
                      CHECK (status IN ('draft', 'confirmed', 'in_progress', 'completed', 'partial', 'cancelled', 'missed')),
  template_id         UUID REFERENCES public.call_plan_templates(id),
  total_calls         INTEGER NOT NULL DEFAULT 0 CHECK (total_calls >= 0),
  completed_count     INTEGER NOT NULL DEFAULT 0 CHECK (completed_count >= 0),
  skipped_count       INTEGER NOT NULL DEFAULT 0 CHECK (skipped_count >= 0),
  missed_count        INTEGER NOT NULL DEFAULT 0 CHECK (missed_count >= 0),
  completion_pct      NUMERIC(5,2) GENERATED ALWAYS AS (
                        CASE
                          WHEN total_calls = 0 THEN 0
                          ELSE ROUND((completed_count::NUMERIC / total_calls::NUMERIC) * 100, 2)
                        END
                      ) STORED,
  notes               TEXT,
  cancellation_reason TEXT,
  confirmed_at        TIMESTAMPTZ,
  confirmed_by        UUID REFERENCES profiles(id),
  started_at          TIMESTAMPTZ,
  completed_at        TIMESTAMPTZ,
  created_by          UUID NOT NULL REFERENCES profiles(id),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.call_plan_items (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id                UUID NOT NULL REFERENCES public.call_plans(id) ON DELETE CASCADE,
  customer_id            UUID REFERENCES customers(id),
  contact_name           VARCHAR(200),
  phone_number           VARCHAR(50),
  sequence               INTEGER NOT NULL CHECK (sequence > 0),
  planned_time           TIME,
  estimated_duration_min INTEGER NOT NULL DEFAULT 10 CHECK (estimated_duration_min > 0),
  priority               VARCHAR(10) NOT NULL DEFAULT 'normal'
                         CHECK (priority IN ('high', 'normal', 'low')),
  purpose                TEXT,
  purpose_type           VARCHAR(50)
                         CHECK (purpose_type IN ('sales', 'collection', 'activation', 'promotion', 'followup', 'service')),
  status                 VARCHAR(20) NOT NULL DEFAULT 'pending'
                         CHECK (status IN ('pending', 'in_progress', 'completed', 'skipped', 'missed', 'rescheduled')),
  callback_at            TIMESTAMPTZ,
  actual_start_time      TIMESTAMPTZ,
  actual_end_time        TIMESTAMPTZ,
  activity_id            UUID UNIQUE,
  skip_reason            VARCHAR(500),
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (plan_id, sequence),
  CONSTRAINT chk_call_plan_customer_or_phone
    CHECK (customer_id IS NOT NULL OR phone_number IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS public.activities (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type_id              UUID NOT NULL REFERENCES public.activity_types(id),
  employee_id          UUID NOT NULL REFERENCES hr_employees(id),
  customer_id          UUID REFERENCES customers(id),
  visit_plan_item_id   UUID REFERENCES public.visit_plan_items(id),
  call_plan_item_id    UUID REFERENCES public.call_plan_items(id),
  subject              VARCHAR(500),
  subject_type         VARCHAR(100),
  outcome_type         VARCHAR(50) NOT NULL
                       CHECK (outcome_type IN (
                         'order_placed',
                         'collection',
                         'followup_scheduled',
                         'refused',
                         'closed',
                         'promotion',
                         'exploratory',
                         'info_only',
                         'agreed_order',
                         'promised_payment',
                         'followup_visit',
                         'not_interested',
                         'no_answer',
                         'busy',
                         'callback_scheduled'
                       )),
  outcome_notes        TEXT,
  refuse_reason        VARCHAR(255),
  closed_reason        VARCHAR(255),
  gps_lat              NUMERIC(10,7),
  gps_lng              NUMERIC(10,7),
  gps_verified         BOOLEAN NOT NULL DEFAULT false,
  distance_meters      INTEGER,
  start_time           TIMESTAMPTZ,
  end_time             TIMESTAMPTZ,
  duration_minutes     INTEGER GENERATED ALWAYS AS (
                        CASE
                          WHEN start_time IS NULL OR end_time IS NULL THEN NULL
                          ELSE (EXTRACT(EPOCH FROM (end_time - start_time)) / 60)::INTEGER
                        END
                      ) STORED,
  activity_date        DATE NOT NULL DEFAULT CURRENT_DATE,
  order_id             UUID REFERENCES sales_orders(id),
  collection_id        UUID REFERENCES payment_receipts(id),
  followup_activity_id UUID REFERENCES public.activities(id),
  attachments          JSONB NOT NULL DEFAULT '[]'::jsonb,
  metadata             JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_offline_sync      BOOLEAN NOT NULL DEFAULT false,
  synced_at            TIMESTAMPTZ,
  device_id            VARCHAR(100),
  created_by           UUID NOT NULL REFERENCES profiles(id),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at           TIMESTAMPTZ,
  CONSTRAINT chk_activity_time
    CHECK (end_time IS NULL OR start_time IS NULL OR end_time >= start_time),
  CONSTRAINT chk_activity_single_plan_link
    CHECK (NOT (visit_plan_item_id IS NOT NULL AND call_plan_item_id IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS hr_work_locations (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name              TEXT NOT NULL,
  branch_id         UUID REFERENCES branches(id),            -- الفرع المرتبط بهذا الموقع
  latitude          NUMERIC(10,7) NOT NULL,                   -- خط العرض
  longitude         NUMERIC(10,7) NOT NULL,                   -- خط الطول
  radius_meters     INTEGER NOT NULL DEFAULT 200,             -- دائرة السماحية بالأمتار
  require_selfie    BOOLEAN NOT NULL DEFAULT false,           -- هل يشترط صورة سيلفي؟
  gps_accuracy_threshold INTEGER NOT NULL DEFAULT 150,        -- أقصى قيمة دقة GPS مقبولة (متر) — PWA Safe
  -- ملاحظة: is_mock_location غير متاح في PWA، نعتمد على accuracy threshold
  is_active         BOOLEAN NOT NULL DEFAULT true,
  notes             TEXT,
  created_by        UUID REFERENCES profiles(id),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS hr_attendance_days (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id         UUID NOT NULL REFERENCES hr_employees(id),

  -- ─── حقلان منفصلان للتعامل مع الورديات الليلية ───
  shift_date          DATE NOT NULL,                    -- تاريخ الوردية (للتجميع والتقارير)
  work_date           DATE NOT NULL,                    -- تاريخ الدخول الفعلي (قد يختلف في الليلي)
  -- عادةً shift_date = work_date، لكن لو بدأ الموظف 10 مساءً:
  --   shift_date = تاريخ الوردية، work_date = تاريخ الدخول

  -- ─── أوقات الدخول والخروج ───
  punch_in_time       TIMESTAMPTZ,                      -- وقت الدخول الفعلي
  punch_out_time      TIMESTAMPTZ,                      -- وقت الخروج الفعلي

  -- ─── موقع التسجيل ───
  location_in_id      UUID REFERENCES hr_work_locations(id),
  location_out_id     UUID REFERENCES hr_work_locations(id),
  gps_accuracy_in     NUMERIC(8,2),                     -- دقة GPS عند الدخول (متر)
  gps_accuracy_out    NUMERIC(8,2),                     -- دقة GPS عند الخروج

  -- ─── الحالات المحسوبة ───
  status              hr_attendance_status NOT NULL DEFAULT 'absent_unauthorized',
  checkout_status     hr_checkout_status,               -- NULL إذا لم يخرج بعد
  late_minutes        INTEGER NOT NULL DEFAULT 0,       -- دقائق التأخير
  early_leave_minutes INTEGER NOT NULL DEFAULT 0,       -- دقائق الانصراف المبكر
  overtime_minutes    INTEGER NOT NULL DEFAULT 0,       -- دقائق الأوفرتايم
  effective_hours     NUMERIC(4,2),                     -- الساعات الفعلية
  day_value           NUMERIC(4,4) NOT NULL DEFAULT 1,  -- قيمة اليوم (1=كامل، 0.5=نصف، 0=غياب)

  -- ─── الانصراف التلقائي ───
  is_auto_checkout    BOOLEAN NOT NULL DEFAULT false,   -- انصراف تلقائي (نسي التسجيل)

  -- ─── المراجعة ───
  review_status       hr_review_status NOT NULL DEFAULT 'ok',
  reviewed_by         UUID REFERENCES profiles(id),
  reviewed_at         TIMESTAMPTZ,
  notes               TEXT,

  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- موظف لا يمكن أن يكون له أكثر من سجل لنفس الوردية
  UNIQUE (employee_id, shift_date)
);

-- Owned local configuration: isolate empty subscription-dependency tables.
ALTER TABLE public.stock_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_positions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visit_plan_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visit_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visit_plan_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_plan_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_plan_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_work_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_attendance_days ENABLE ROW LEVEL SECURITY;
