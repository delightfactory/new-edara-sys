-- ============================================================
-- Migration 17: HR Core — النواة الأساسية لموديول الموارد البشرية
-- EDARA v2
-- Idempotent: آمن للتشغيل أكثر من مرة
--
-- الجداول:
--   1. إعدادات HR (company_settings — موجودة سابقاً، نضيف إليها)
--   2. hr_departments       — الأقسام
--   3. hr_positions         — المسميات الوظيفية
--   4. hr_employees         — ملفات الموظفين (النواة المركزية)
--   5. hr_contracts         — العقود وتغييراتها
--   6. hr_salary_history    — سجل تاريخ الراتب الفعّال
--   7. hr_work_locations    — مواقع الحضور الجغرافية (GPS)
--   8. hr_delegations       — التفويض الزمني للصلاحيات
--   9. hr_documents         — وثائق الموظف (بطاقة، عقد، ...)
-- صلاحيات + RLS + Indexes + Seeds
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- ENUMs
-- ════════════════════════════════════════════════════════════

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
  CREATE TYPE hr_contract_type AS ENUM ('permanent', 'fixed_term', 'part_time', 'freelance', 'probation');
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;

DO $$ BEGIN
  CREATE TYPE hr_day_of_week AS ENUM ('saturday', 'sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday');
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;

DO $$ BEGIN
  CREATE TYPE hr_document_type AS ENUM (
    'national_id', 'passport', 'driving_license',
    'employment_contract', 'educational_certificate',
    'social_insurance', 'medical_certificate', 'other'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;


-- ════════════════════════════════════════════════════════════
-- إضافات لإعدادات الشركة (company_settings) — موجود في 01
-- نضيف إعدادات HR المتقدمة التي لم تكن موجودة
-- ════════════════════════════════════════════════════════════

INSERT INTO company_settings (key, value, type, description, category, is_public) VALUES
  -- الامتثال القانوني (مفاتيح تشغيل/إيقاف — موقوفة بالافتراضي)
  ('hr.social_insurance.enabled',      'false', 'boolean', 'تفعيل التأمين الاجتماعي',           'hr', false),
  ('hr.social_insurance.employee_rate','11',    'number',  'نسبة اشتراك الموظف في التأمين %',   'hr', false),
  ('hr.social_insurance.employer_rate','18.75', 'number',  'نسبة اشتراك صاحب العمل %',          'hr', false),
  ('hr.income_tax.enabled',            'false', 'boolean', 'تفعيل ضريبة كسب العمل',             'hr', false),
  ('hr.health_insurance.enabled',      'false', 'boolean', 'تفعيل التأمين الصحي',               'hr', false),
  ('hr.health_insurance.amount',       '0',     'number',  'قيمة خصم التأمين الصحي',            'hr', false),

  -- قواعد وقت العمل (تكمّل ما هو موجود)
  ('hr.weekly_off_day',                'friday','text',    'يوم العطلة الأسبوعية الافتراضي',    'hr', false),
  ('hr.work_hours_per_day',            '8',     'number',  'ساعات العمل الرسمية يومياً',         'hr', false),
  ('hr.overtime_holiday_rate',         '1.75',  'number',  'معامل الإضافي في العطلات',           'hr', false),
  ('hr.max_early_leave_permits',       '2',     'number',  'أقصى إذن انصراف مبكر شهرياً',       'hr', false),
  ('hr.auto_checkout_minutes',         '15',    'number',  'دقائق قبل الانصراف التلقائي',        'hr', false),
  ('hr.gps_accuracy_threshold_meters', '150',   'number',  'أقصى دقة GPS مقبولة (متر)',          'hr', false),

  -- قواعد السلف
  ('hr.advance_max_months_salary',     '1',     'number',  'الحد الأقصى للسلفة (أشهر راتب)',    'hr', false),
  ('hr.advance_max_installments',      '6',     'number',  'أقصى عدد أقساط للسلفة',             'hr', false),
  ('hr.advance_min_installments',      '1',     'number',  'أقل عدد أقساط مسموح',               'hr', false),
  ('hr.advance_max_active',            '1',     'number',  'أقصى عدد سلف نشطة',                 'hr', false),
  ('hr.instant_advance_max_percent',   '50',    'number',  'أقصى نسبة للسلفة الفورية %',        'hr', false)
ON CONFLICT (key) DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- 1. DEPARTMENTS — الأقسام
-- ════════════════════════════════════════════════════════════

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

CREATE INDEX IF NOT EXISTS idx_hr_dept_branch   ON hr_departments(branch_id);
CREATE INDEX IF NOT EXISTS idx_hr_dept_parent   ON hr_departments(parent_id);
CREATE INDEX IF NOT EXISTS idx_hr_dept_active   ON hr_departments(is_active);

-- Seed: الأقسام الأساسية لشركة التوزيع
INSERT INTO hr_departments (name, name_en, code) VALUES
  ('المبيعات',           'Sales',          'SALES'),
  ('المالية والمحاسبة',  'Finance',         'FIN'),
  ('الموارد البشرية',    'Human Resources', 'HR'),
  ('التوزيع والخدمات',   'Distribution',    'DIST'),
  ('المخازن',            'Warehouse',       'WH'),
  ('الإدارة العامة',     'Administration',  'ADMIN')
ON CONFLICT (code) DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- 2. POSITIONS — المسميات الوظيفية
-- ════════════════════════════════════════════════════════════

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

CREATE INDEX IF NOT EXISTS idx_hr_pos_dept   ON hr_positions(department_id);
CREATE INDEX IF NOT EXISTS idx_hr_pos_active ON hr_positions(is_active);

-- Seed: المسميات الوظيفية الأساسية
INSERT INTO hr_positions (name, name_en, is_field) VALUES
  ('مدير عام',            'General Manager',       false),
  ('مدير موارد بشرية',    'HR Manager',            false),
  ('مدير مبيعات',         'Sales Manager',         false),
  ('مشرف مبيعات',         'Sales Supervisor',      false),
  ('مندوب مبيعات',        'Sales Representative',  true),
  ('محاسب',              'Accountant',            false),
  ('أمين مخزن',           'Warehouse Keeper',      false),
  ('سائق توزيع',          'Delivery Driver',       true),
  ('مسؤول موارد بشرية',   'HR Officer',            false),
  ('مدير فرع',            'Branch Manager',        false)
;


-- ════════════════════════════════════════════════════════════
-- 3. HR EMPLOYEES — ملفات الموظفين (النواة المركزية)
-- ════════════════════════════════════════════════════════════

CREATE SEQUENCE IF NOT EXISTS hr_employee_number_seq START WITH 1;

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

CREATE INDEX IF NOT EXISTS idx_hr_emp_user       ON hr_employees(user_id);
CREATE INDEX IF NOT EXISTS idx_hr_emp_dept       ON hr_employees(department_id);
CREATE INDEX IF NOT EXISTS idx_hr_emp_branch     ON hr_employees(branch_id);
CREATE INDEX IF NOT EXISTS idx_hr_emp_manager    ON hr_employees(direct_manager_id);
CREATE INDEX IF NOT EXISTS idx_hr_emp_status     ON hr_employees(status);
CREATE INDEX IF NOT EXISTS idx_hr_emp_number     ON hr_employees(employee_number);
CREATE INDEX IF NOT EXISTS idx_hr_emp_national_id ON hr_employees(national_id) WHERE national_id IS NOT NULL;

-- Trigger: توليد رقم الموظف تلقائياً
CREATE OR REPLACE FUNCTION generate_employee_number()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.employee_number IS NULL OR NEW.employee_number = '' THEN
    NEW.employee_number := 'EMP-' || lpad(nextval('hr_employee_number_seq')::text, 5, '0');
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_employee_auto_number ON hr_employees;
CREATE TRIGGER trg_employee_auto_number
  BEFORE INSERT ON hr_employees
  FOR EACH ROW EXECUTE FUNCTION generate_employee_number();

-- Trigger: عند إنهاء الخدمة — إيقاف حساب المستخدم تلقائياً
CREATE OR REPLACE FUNCTION handle_employee_termination()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- عند تغيير الحالة إلى terminated
  IF NEW.status = 'terminated' AND OLD.status <> 'terminated' THEN
    -- إيقاف الحساب في auth (عبر profiles)
    IF NEW.user_id IS NOT NULL THEN
      UPDATE profiles SET status = 'inactive' WHERE id = NEW.user_id;
    END IF;
    -- تسجيل تاريخ إنهاء الخدمة إذا لم يُحدَّد
    IF NEW.termination_date IS NULL THEN
      NEW.termination_date := CURRENT_DATE;
    END IF;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_employee_termination ON hr_employees;
CREATE TRIGGER trg_employee_termination
  BEFORE UPDATE ON hr_employees
  FOR EACH ROW EXECUTE FUNCTION handle_employee_termination();


-- ════════════════════════════════════════════════════════════
-- 4. HR CONTRACTS — العقود وتغييراتها
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS hr_contracts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id     UUID NOT NULL REFERENCES hr_employees(id) ON DELETE CASCADE,
  contract_type   hr_contract_type NOT NULL DEFAULT 'permanent',
  start_date      DATE NOT NULL,
  end_date        DATE,                                       -- NULL = دائم
  base_salary     NUMERIC(12,2) NOT NULL,
  transport_allowance NUMERIC(12,2) NOT NULL DEFAULT 0,
  housing_allowance   NUMERIC(12,2) NOT NULL DEFAULT 0,
  other_allowances    NUMERIC(12,2) NOT NULL DEFAULT 0,
  notes           TEXT,
  document_url    TEXT,                                       -- رابط نسخة العقد الممسوح
  created_by      UUID REFERENCES profiles(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
  -- لا updated_at — العقد سجل تاريخي ثابت، لا يُعدّل (إنما يُضاف عقد جديد)
);

CREATE INDEX IF NOT EXISTS idx_hr_contracts_emp    ON hr_contracts(employee_id);
CREATE INDEX IF NOT EXISTS idx_hr_contracts_dates  ON hr_contracts(start_date, end_date);

-- Trigger: عند إضافة عقد جديد — تحديث بيانات الراتب في hr_employees
CREATE OR REPLACE FUNCTION sync_employee_salary_from_contract()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE hr_employees
  SET
    base_salary         = NEW.base_salary,
    transport_allowance = NEW.transport_allowance,
    housing_allowance   = NEW.housing_allowance,
    other_allowances    = NEW.other_allowances,
    updated_at          = now()
  WHERE id = NEW.employee_id;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_contract_sync_salary ON hr_contracts;
CREATE TRIGGER trg_contract_sync_salary
  AFTER INSERT ON hr_contracts
  FOR EACH ROW EXECUTE FUNCTION sync_employee_salary_from_contract();


-- ════════════════════════════════════════════════════════════
-- 5. HR SALARY HISTORY — سجل تاريخ الراتب الفعّال
--    يُستخدم لحساب الراتب الصحيح عند الترقيات في منتصف الشهر
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS hr_salary_history (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id         UUID NOT NULL REFERENCES hr_employees(id),
  effective_date      DATE NOT NULL,                          -- تاريخ سريان هذا الراتب
  base_salary         NUMERIC(12,2) NOT NULL,
  transport_allowance NUMERIC(12,2) NOT NULL DEFAULT 0,
  housing_allowance   NUMERIC(12,2) NOT NULL DEFAULT 0,
  other_allowances    NUMERIC(12,2) NOT NULL DEFAULT 0,
  gross_salary        NUMERIC(12,2) GENERATED ALWAYS AS (
    base_salary + transport_allowance + housing_allowance + other_allowances
  ) STORED,
  change_reason       TEXT,                                   -- سبب التغيير (ترقية، تعديل، ...)
  changed_by          UUID REFERENCES profiles(id),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- قيد: لا يمكن أن يكون لنفس الموظف سجلين بنفس تاريخ السريان
  UNIQUE (employee_id, effective_date)
);

CREATE INDEX IF NOT EXISTS idx_hr_salary_hist_emp  ON hr_salary_history(employee_id);
CREATE INDEX IF NOT EXISTS idx_hr_salary_hist_date ON hr_salary_history(employee_id, effective_date DESC);

-- Trigger: عند تغيير الراتب في hr_employees — إضافة سجل في التاريخ تلقائياً
CREATE OR REPLACE FUNCTION log_salary_change()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- تسجيل فقط إذا تغيّر الراتب أو البدلات
  IF (NEW.base_salary <> OLD.base_salary OR
      NEW.transport_allowance <> OLD.transport_allowance OR
      NEW.housing_allowance <> OLD.housing_allowance OR
      NEW.other_allowances <> OLD.other_allowances) THEN
    INSERT INTO hr_salary_history (
      employee_id, effective_date,
      base_salary, transport_allowance, housing_allowance, other_allowances,
      change_reason
    ) VALUES (
      NEW.id, CURRENT_DATE,
      NEW.base_salary, NEW.transport_allowance, NEW.housing_allowance, NEW.other_allowances,
      'تحديث تلقائي عند تغيير بيانات الراتب'
    )
    ON CONFLICT (employee_id, effective_date) DO UPDATE
      SET base_salary         = EXCLUDED.base_salary,
          transport_allowance = EXCLUDED.transport_allowance,
          housing_allowance   = EXCLUDED.housing_allowance,
          other_allowances    = EXCLUDED.other_allowances;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_log_salary_change ON hr_employees;
CREATE TRIGGER trg_log_salary_change
  AFTER UPDATE ON hr_employees
  FOR EACH ROW EXECUTE FUNCTION log_salary_change();


-- ════════════════════════════════════════════════════════════
-- 6. HR WORK LOCATIONS — مواقع الحضور الجغرافية
--    جدول الفروع/المواقع المسموح فيها بتسجيل الحضور
-- ════════════════════════════════════════════════════════════

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

CREATE INDEX IF NOT EXISTS idx_hr_locations_branch  ON hr_work_locations(branch_id);
CREATE INDEX IF NOT EXISTS idx_hr_locations_active  ON hr_work_locations(is_active);

-- إضافة FK بعد وجود الجدول (circular dep مع hr_employees)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_hr_emp_work_location'
  ) THEN
    ALTER TABLE hr_employees
      ADD CONSTRAINT fk_hr_emp_work_location
      FOREIGN KEY (work_location_id) REFERENCES hr_work_locations(id) ON DELETE SET NULL;
  END IF;
END; $$;


-- ════════════════════════════════════════════════════════════
-- 7. HR DELEGATIONS — التفويض الزمني للصلاحيات
--    عند غياب مدير يفوّض صلاحياته لشخص آخر لفترة محددة
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS hr_delegations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delegator_id    UUID NOT NULL REFERENCES hr_employees(id),  -- من يفوّض (المدير الغائب)
  delegate_id     UUID NOT NULL REFERENCES hr_employees(id),  -- من يتلقى التفويض
  -- الصلاحيات المفوَّضة (قائمة نصية مثل: 'hr.leaves.approve', 'hr.advances.approve')
  permissions     TEXT[] NOT NULL DEFAULT '{}',
  scope_type      TEXT CHECK (scope_type IN ('team', 'branch', 'all')) DEFAULT 'team',
  scope_id        UUID,                                       -- فرع أو فريق محدد (NULL = كل)
  valid_from      TIMESTAMPTZ NOT NULL DEFAULT now(),
  valid_until     TIMESTAMPTZ NOT NULL,
  reason          TEXT,
  is_active       BOOLEAN NOT NULL DEFAULT true,
  created_by      UUID REFERENCES profiles(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_delegation_self CHECK (delegator_id <> delegate_id),
  CONSTRAINT chk_delegation_dates CHECK (valid_until > valid_from)
);

CREATE INDEX IF NOT EXISTS idx_hr_deleg_delegator  ON hr_delegations(delegator_id);
CREATE INDEX IF NOT EXISTS idx_hr_deleg_delegate   ON hr_delegations(delegate_id);
CREATE INDEX IF NOT EXISTS idx_hr_deleg_active     ON hr_delegations(is_active, valid_from, valid_until);


-- ════════════════════════════════════════════════════════════
-- 8. HR DOCUMENTS — وثائق الموظف
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS hr_employee_documents (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id     UUID NOT NULL REFERENCES hr_employees(id) ON DELETE CASCADE,
  document_type   hr_document_type NOT NULL,
  document_number TEXT,
  issue_date      DATE,
  expiry_date     DATE,                                       -- تاريخ الانتهاء (NULL = لا ينتهي)
  file_url        TEXT,                                       -- رابط الملف في Storage
  notes           TEXT,
  uploaded_by     UUID REFERENCES profiles(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_hr_docs_emp     ON hr_employee_documents(employee_id);
CREATE INDEX IF NOT EXISTS idx_hr_docs_expiry  ON hr_employee_documents(expiry_date) WHERE expiry_date IS NOT NULL;
-- الفهرس أعلاه يُستخدم في استعلام "الوثائق التي تنتهي خلال 30 يوماً"


-- ════════════════════════════════════════════════════════════
-- 9. updated_at Triggers
-- ════════════════════════════════════════════════════════════

DO $$
DECLARE tbl TEXT;
BEGIN
  FOR tbl IN SELECT unnest(ARRAY[
    'hr_departments', 'hr_positions', 'hr_employees',
    'hr_work_locations'
  ]) LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS trg_%I_updated_at ON %I;
       CREATE TRIGGER trg_%I_updated_at
       BEFORE UPDATE ON %I
       FOR EACH ROW EXECUTE FUNCTION set_updated_at()',
      tbl, tbl, tbl, tbl
    );
  END LOOP;
END; $$;


-- ════════════════════════════════════════════════════════════
-- 10. COA ADDITIONS — إضافة حسابات الرواتب لشجرة الحسابات
-- ════════════════════════════════════════════════════════════

INSERT INTO chart_of_accounts (code, name, name_en, type, sort_order) VALUES
  ('2300', 'التزامات الموظفين',       'Employee Liabilities',   'liability', 15),
  ('2310', 'رواتب مستحقة الدفع',      'Accrued Salaries',       'liability', 16),
  ('2320', 'سلف الموظفين',            'Employee Advances',      'liability', 17),
  ('2330', 'تأمينات اجتماعية',        'Social Insurance',       'liability', 18),
  ('5300', 'مصروفات رواتب وأجور',     'Salary Expenses',        'expense',   46),
  ('5310', 'رواتب أساسية',            'Basic Salaries',         'expense',   47),
  ('5320', 'بدلات وإضافات',           'Allowances & Extras',    'expense',   48),
  ('5330', 'عمولات موظفين',           'Staff Commissions',      'expense',   49)
ON CONFLICT (code) DO NOTHING;

-- ربط الأبناء بالآباء
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '2000')
WHERE code = '2300' AND parent_id IS NULL;

UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '2300')
WHERE code IN ('2310','2320','2330') AND parent_id IS NULL;

UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '5000')
WHERE code = '5300' AND parent_id IS NULL;

UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '5300')
WHERE code IN ('5310','5320','5330') AND parent_id IS NULL;


-- ════════════════════════════════════════════════════════════
-- 11. STORAGE BUCKET — وثائق الموظفين
-- ════════════════════════════════════════════════════════════

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'hr-documents',
  'hr-documents',
  false,                                         -- خاص — يتطلب صلاحية
  10485760,                                      -- 10MB
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
) ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "hr_docs_select" ON storage.objects;
CREATE POLICY "hr_docs_select" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'hr-documents'
    AND check_permission(auth.uid(), 'hr.employees.read')
  );

DROP POLICY IF EXISTS "hr_docs_insert" ON storage.objects;
CREATE POLICY "hr_docs_insert" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'hr-documents'
    AND check_permission(auth.uid(), 'hr.employees.create')
  );

DROP POLICY IF EXISTS "hr_docs_delete" ON storage.objects;
CREATE POLICY "hr_docs_delete" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'hr-documents'
    AND check_permission(auth.uid(), 'hr.employees.delete')
  );


-- ════════════════════════════════════════════════════════════
-- 12. RLS — تأمين كل الجداول
-- ════════════════════════════════════════════════════════════

ALTER TABLE hr_departments        ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_positions          ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_employees          ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_contracts          ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_salary_history     ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_work_locations     ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_delegations        ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_employee_documents ENABLE ROW LEVEL SECURITY;

-- Departments & Positions: الكل يقرأ — مدير HR يعدّل
DROP POLICY IF EXISTS "hr_depts_read" ON hr_departments;
CREATE POLICY "hr_depts_read" ON hr_departments FOR SELECT
  USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "hr_depts_write" ON hr_departments;
CREATE POLICY "hr_depts_write" ON hr_departments FOR ALL
  USING (check_permission(auth.uid(), 'hr.employees.create'));

DROP POLICY IF EXISTS "hr_pos_read" ON hr_positions;
CREATE POLICY "hr_pos_read" ON hr_positions FOR SELECT
  USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "hr_pos_write" ON hr_positions;
CREATE POLICY "hr_pos_write" ON hr_positions FOR ALL
  USING (check_permission(auth.uid(), 'hr.employees.create'));

-- Employees: عرض نفسك + أصحاب hr.employees.read
DROP POLICY IF EXISTS "hr_emp_read" ON hr_employees;
CREATE POLICY "hr_emp_read" ON hr_employees FOR SELECT
  USING (
    user_id = auth.uid()
    OR check_permission(auth.uid(), 'hr.employees.read')
  );
DROP POLICY IF EXISTS "hr_emp_insert" ON hr_employees;
CREATE POLICY "hr_emp_insert" ON hr_employees FOR INSERT
  WITH CHECK (check_permission(auth.uid(), 'hr.employees.create'));
DROP POLICY IF EXISTS "hr_emp_update" ON hr_employees;
CREATE POLICY "hr_emp_update" ON hr_employees FOR UPDATE
  USING (check_permission(auth.uid(), 'hr.employees.create'));

-- Salary History: مدير HR والمالي فقط
DROP POLICY IF EXISTS "hr_sal_hist_read" ON hr_salary_history;
CREATE POLICY "hr_sal_hist_read" ON hr_salary_history FOR SELECT
  USING (
    employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR check_permission(auth.uid(), 'hr.payroll.read')
  );
DROP POLICY IF EXISTS "hr_sal_hist_write" ON hr_salary_history;
CREATE POLICY "hr_sal_hist_write" ON hr_salary_history FOR ALL
  USING (check_permission(auth.uid(), 'hr.payroll.calculate'));

-- Contracts: مدير HR يكتب، أصحاب hr.employees.read يقرأون
DROP POLICY IF EXISTS "hr_contracts_read" ON hr_contracts;
CREATE POLICY "hr_contracts_read" ON hr_contracts FOR SELECT
  USING (
    employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR check_permission(auth.uid(), 'hr.employees.read')
  );
DROP POLICY IF EXISTS "hr_contracts_write" ON hr_contracts;
CREATE POLICY "hr_contracts_write" ON hr_contracts FOR ALL
  USING (check_permission(auth.uid(), 'hr.employees.create'));

-- Work Locations: القراءة مفتوحة للمسجلين (لكشف الحضور)
DROP POLICY IF EXISTS "hr_locations_read" ON hr_work_locations;
CREATE POLICY "hr_locations_read" ON hr_work_locations FOR SELECT
  USING (auth.uid() IS NOT NULL AND is_active = true);
DROP POLICY IF EXISTS "hr_locations_write" ON hr_work_locations;
CREATE POLICY "hr_locations_write" ON hr_work_locations FOR ALL
  USING (check_permission(auth.uid(), 'hr.employees.create'));

-- Delegations: الشخص المفوِّض والمفوَّض إليه + مدير HR
DROP POLICY IF EXISTS "hr_deleg_read" ON hr_delegations;
CREATE POLICY "hr_deleg_read" ON hr_delegations FOR SELECT
  USING (
    delegator_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR delegate_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR check_permission(auth.uid(), 'hr.employees.read')
  );
DROP POLICY IF EXISTS "hr_deleg_write" ON hr_delegations;
CREATE POLICY "hr_deleg_write" ON hr_delegations FOR ALL
  USING (check_permission(auth.uid(), 'hr.employees.create'));

-- Documents: الموظف نفسه + مدير HR
DROP POLICY IF EXISTS "hr_docs_rls_read" ON hr_employee_documents;
CREATE POLICY "hr_docs_rls_read" ON hr_employee_documents FOR SELECT
  USING (
    employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR check_permission(auth.uid(), 'hr.employees.read')
  );
DROP POLICY IF EXISTS "hr_docs_rls_write" ON hr_employee_documents;
CREATE POLICY "hr_docs_rls_write" ON hr_employee_documents FOR ALL
  USING (check_permission(auth.uid(), 'hr.employees.create'));


-- ════════════════════════════════════════════════════════════
-- 13. FUNCTIONS — الدوال المساعدة
-- ════════════════════════════════════════════════════════════

-- ─── الدالة 1: ربط مستخدم بموظف بالإيميل ───
-- تُستخدم عند إنشاء ملف موظف جديد أو يدوياً من واجهة HR
CREATE OR REPLACE FUNCTION link_employee_to_user(
  p_employee_id UUID,
  p_email       TEXT
) RETURNS JSONB
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_result  JSONB;
BEGIN
  -- البحث عن مستخدم بنفس الإيميل في auth.users
  SELECT id INTO v_user_id
  FROM auth.users
  WHERE email = lower(trim(p_email))
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'USER_NOT_FOUND',
      'message', 'لا يوجد مستخدم بهذا البريد الإلكتروني'
    );
  END IF;

  -- التحقق أن هذا المستخدم غير مرتبط بموظف آخر
  IF EXISTS (
    SELECT 1 FROM hr_employees
    WHERE user_id = v_user_id AND id <> p_employee_id
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'USER_ALREADY_LINKED',
      'message', 'هذا المستخدم مرتبط بموظف آخر بالفعل'
    );
  END IF;

  -- الربط
  UPDATE hr_employees
  SET user_id = v_user_id, updated_at = now()
  WHERE id = p_employee_id;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', v_user_id,
    'message', 'تم الربط بنجاح'
  );
END; $$;


-- ─── الدالة 2: الحصول على الراتب الفعّال في تاريخ محدد ───
-- تُستخدم في حساب الرواتب للتعامل مع الترقيات في منتصف الشهر
CREATE OR REPLACE FUNCTION get_employee_salary_at_date(
  p_employee_id UUID,
  p_date        DATE DEFAULT CURRENT_DATE
) RETURNS TABLE (
  base_salary         NUMERIC,
  transport_allowance NUMERIC,
  housing_allowance   NUMERIC,
  other_allowances    NUMERIC,
  gross_salary        NUMERIC,
  effective_date      DATE
)
  LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    sh.base_salary,
    sh.transport_allowance,
    sh.housing_allowance,
    sh.other_allowances,
    sh.gross_salary,
    sh.effective_date
  FROM hr_salary_history sh
  WHERE sh.employee_id = p_employee_id
    AND sh.effective_date <= p_date
  ORDER BY sh.effective_date DESC
  LIMIT 1;

  -- إذا لم يوجد سجل في التاريخ — ارجع بيانات الموظف الحالية
  IF NOT FOUND THEN
    RETURN QUERY
    SELECT
      e.base_salary,
      e.transport_allowance,
      e.housing_allowance,
      e.other_allowances,
      e.gross_salary,
      e.hire_date
    FROM hr_employees e
    WHERE e.id = p_employee_id;
  END IF;
END; $$;


-- ─── الدالة 3: التحقق من صحة تسجيل الحضور GPS ───
-- تتحقق من أن الإحداثيات داخل نطاق أحد مواقع العمل
-- وأن دقة GPS ضمن الحد المسموح (بديل is_mock_location في PWA)
CREATE OR REPLACE FUNCTION validate_attendance_location(
  p_employee_id   UUID,
  p_latitude      NUMERIC,
  p_longitude     NUMERIC,
  p_gps_accuracy  NUMERIC DEFAULT NULL   -- الدقة بالأمتار (NULL = غير معروفة)
) RETURNS JSONB
  LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_location       hr_work_locations%ROWTYPE;
  v_distance_m     NUMERIC;
  v_threshold      INTEGER;
  v_is_field       BOOLEAN;
BEGIN
  -- هل الموظف ميداني؟ (مسموح له بالتسجيل من أي موقع نشط)
  SELECT is_field_employee INTO v_is_field
  FROM hr_employees WHERE id = p_employee_id;

  -- ─── فحص دقة GPS ───
  -- نقرأ الحد من إعدادات الموظف أو الشركة
  SELECT COALESCE(
    (SELECT gps_accuracy_threshold FROM hr_work_locations WHERE is_active = true LIMIT 1),
    150  -- الافتراضي: 150 متر
  ) INTO v_threshold;

  IF p_gps_accuracy IS NOT NULL AND p_gps_accuracy > v_threshold THEN
    RETURN jsonb_build_object(
      'valid', false,
      'code', 'LOW_GPS_ACCURACY',
      'message', format('دقة GPS منخفضة جداً (%s متر). الحد المسموح: %s متر', p_gps_accuracy::int, v_threshold),
      'requires_review', true
    );
  END IF;

  -- ─── البحث عن أقرب موقع عمل ضمن النطاق ───
  -- نستخدم Haversine تقريبياً عبر درجات العرض/الطول
  SELECT *
  INTO v_location
  FROM hr_work_locations
  WHERE is_active = true
  ORDER BY (
    -- حساب المسافة التقريبية (Haversine simplified)
    6371000 * acos(LEAST(1.0,
      cos(radians(latitude)) * cos(radians(p_latitude))
      * cos(radians(p_longitude) - radians(longitude))
      + sin(radians(latitude)) * sin(radians(p_latitude))
    ))
  ) ASC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'valid', false,
      'code', 'NO_LOCATION_FOUND',
      'message', 'لا توجد مواقع عمل نشطة مسجلة في النظام'
    );
  END IF;

  -- حساب المسافة الفعلية بالأمتار
  v_distance_m := 6371000 * acos(LEAST(1.0,
    cos(radians(v_location.latitude)) * cos(radians(p_latitude))
    * cos(radians(p_longitude) - radians(v_location.longitude))
    + sin(radians(v_location.latitude)) * sin(radians(p_latitude))
  ));

  IF v_is_field OR v_distance_m <= v_location.radius_meters THEN
    RETURN jsonb_build_object(
      'valid', true,
      'location_id', v_location.id,
      'location_name', v_location.name,
      'distance_meters', round(v_distance_m),
      'require_selfie', v_location.require_selfie,
      'is_field_employee', v_is_field
    );
  ELSE
    RETURN jsonb_build_object(
      'valid', false,
      'code', 'OUT_OF_RANGE',
      'message', format('أنت خارج نطاق الحضور. المسافة: %s م، الحد المسموح: %s م',
                        round(v_distance_m), v_location.radius_meters),
      'nearest_location', v_location.name,
      'distance_meters', round(v_distance_m)
    );
  END IF;
END; $$;


-- ─── الدالة 4: التحقق من صلاحية بضمن التفويض الزمني ───
-- تُستخدم في check_permission كطبقة إضافية له
CREATE OR REPLACE FUNCTION check_delegated_permission(
  p_user_id   UUID,
  p_permission TEXT
) RETURNS BOOLEAN
  LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_employee_id UUID;
BEGIN
  -- إيجاد معرّف الموظف من المستخدم
  SELECT id INTO v_employee_id
  FROM hr_employees
  WHERE user_id = p_user_id AND status = 'active';

  IF NOT FOUND THEN RETURN false; END IF;

  -- هل هناك تفويض نشط يمنح هذه الصلاحية؟
  RETURN EXISTS (
    SELECT 1 FROM hr_delegations
    WHERE delegate_id = v_employee_id
      AND p_permission = ANY(permissions)
      AND is_active = true
      AND now() BETWEEN valid_from AND valid_until
  );
END; $$;


-- ════════════════════════════════════════════════════════════
-- 14. PERMISSIONS SEED — صلاحيات HR الكاملة
-- ════════════════════════════════════════════════════════════

-- صلاحيات مدير HR الكاملة
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('hr.employees.read'),
  ('hr.employees.create'),
  ('hr.employees.update'),
  ('hr.employees.delete'),
  ('hr.attendance.read'),
  ('hr.attendance.create'),
  ('hr.attendance.update'),
  ('hr.attendance.approve'),
  ('hr.leaves.read'),
  ('hr.leaves.create'),
  ('hr.leaves.approve'),
  ('hr.advances.read'),
  ('hr.advances.create'),
  ('hr.advances.approve'),
  ('hr.payroll.read'),
  ('hr.payroll.calculate'),
  ('hr.payroll.approve'),
  ('hr.reports.view'),
  ('hr.settings.update')
) AS p(perm)
WHERE r.name = 'hr_manager'
ON CONFLICT DO NOTHING;

-- صلاحيات CEO / المدير العام
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('hr.employees.read'),
  ('hr.attendance.read'),
  ('hr.leaves.read'),
  ('hr.leaves.approve'),
  ('hr.advances.read'),
  ('hr.payroll.read'),
  ('hr.payroll.approve'),
  ('hr.reports.view')
) AS p(perm)
WHERE r.name = 'ceo'
ON CONFLICT DO NOTHING;

-- صلاحيات مدير الفرع
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('hr.employees.read'),
  ('hr.attendance.read'),
  ('hr.attendance.approve'),
  ('hr.leaves.read'),
  ('hr.leaves.approve'),
  ('hr.advances.read')
) AS p(perm)
WHERE r.name = 'branch_manager'
ON CONFLICT DO NOTHING;

-- صلاحيات مشرف المبيعات (اعتماد حضور فريقه)
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('hr.attendance.read'),
  ('hr.attendance.approve'),
  ('hr.leaves.read'),
  ('hr.leaves.approve')
) AS p(perm)
WHERE r.name = 'sales_supervisor'
ON CONFLICT DO NOTHING;

-- الموظف العادي: يرى بياناته فقط (الـ RLS تتحكم — لا صلاحيات إضافية مطلوبة)
-- hr_employees RLS: user_id = auth.uid() ← يتيح للموظف رؤية ملفه الخاص


-- ════════════════════════════════════════════════════════════
-- ملاحظات التطوير المستقبلي
-- ════════════════════════════════════════════════════════════
-- الملف التالي: 18_hr_attendance_leaves.sql
--   ثلاث جداول: hr_attendance_days, hr_attendance_logs (GPS), hr_public_holidays
--   جداول الإجازات: hr_leave_types, hr_leave_balances, hr_leave_requests
--   جداول الأذونات: hr_permission_requests (إذن انصراف مبكر)
--   محرك الجزاءات: hr_penalty_rules, hr_penalty_instances
-- ════════════════════════════════════════════════════════════
