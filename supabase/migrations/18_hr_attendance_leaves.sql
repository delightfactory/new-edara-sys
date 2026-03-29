-- ============================================================
-- Migration 18: HR Attendance, Leaves, Permissions & Penalties
-- EDARA v2 — Idempotent: آمن للتشغيل أكثر من مرة
--
-- الجداول:
--   1. hr_public_holidays       — العطل الرسمية
--   2. hr_attendance_days       — سجل الحضور اليومي
--   3. hr_attendance_logs       — نقاط GPS (Append-only)
--   4. hr_leave_types           — أنواع الإجازات
--   5. hr_leave_balances        — أرصدة الإجازات
--   6. hr_leave_requests        — طلبات الإجازة (multi-level approval)
--   7. hr_permission_requests   — أذونات الانصراف المبكر
--   8. hr_penalty_rules         — قواعد الجزاءات
--   9. hr_penalty_instances     — تطبيقات الجزاء الفعلية
-- الدوال: validate_work_day, process_attendance_penalties,
--         get_monthly_attendance_summary, initialize_leave_balances
-- ============================================================


-- ════════════════════════════════════════════════════════════
-- ENUMs
-- ════════════════════════════════════════════════════════════

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

DO $$ BEGIN
  CREATE TYPE hr_leave_request_status AS ENUM (
    'draft',
    'pending_supervisor',
    'approved_supervisor',
    'pending_hr',
    'approved',
    'rejected',
    'cancelled'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;

DO $$ BEGIN
  CREATE TYPE hr_penalty_type AS ENUM (
    'late', 'absent_unauthorized', 'early_leave_unauthorized', 'out_of_range'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;

DO $$ BEGIN
  CREATE TYPE hr_deduction_type AS ENUM (
    'none', 'warning', 'quarter_day', 'half_day', 'full_day', 'custom_minutes'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;


-- ════════════════════════════════════════════════════════════
-- 1. PUBLIC HOLIDAYS — العطل الرسمية
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS hr_public_holidays (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT NOT NULL,
  holiday_date DATE NOT NULL,
  year         INTEGER NOT NULL GENERATED ALWAYS AS (EXTRACT(YEAR FROM holiday_date)::INTEGER) STORED,
  is_recurring BOOLEAN NOT NULL DEFAULT false,  -- عطلة متكررة سنوياً (مثل عيد الفطر تحتاج تحديداً)
  notes        TEXT,
  created_by   UUID REFERENCES profiles(id),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (holiday_date)
);

CREATE INDEX IF NOT EXISTS idx_hr_holidays_date ON hr_public_holidays(holiday_date);
CREATE INDEX IF NOT EXISTS idx_hr_holidays_year ON hr_public_holidays(year);

-- Seed: عطل مصر الثابتة 2026
INSERT INTO hr_public_holidays (name, holiday_date, is_recurring) VALUES
  ('رأس السنة الميلادية',   '2026-01-01', true),
  ('عيد الشرطة',            '2026-01-25', true),
  ('ثورة 25 يناير',         '2026-01-25', true),
  ('شم النسيم',             '2026-04-13', false),
  ('عيد العمال',            '2026-05-01', true),
  ('ثورة 30 يونيو',         '2026-06-30', true),
  ('ثورة 23 يوليو',         '2026-07-23', true),
  ('عيد القوات المسلحة',    '2026-10-06', true)
ON CONFLICT (holiday_date) DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- 2. ATTENDANCE DAYS — سجل الحضور اليومي (ملخص يومي)
-- ════════════════════════════════════════════════════════════

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

CREATE INDEX IF NOT EXISTS idx_hr_att_emp_date   ON hr_attendance_days(employee_id, shift_date DESC);
CREATE INDEX IF NOT EXISTS idx_hr_att_status     ON hr_attendance_days(status);
CREATE INDEX IF NOT EXISTS idx_hr_att_review     ON hr_attendance_days(review_status) WHERE review_status = 'needs_review';
CREATE INDEX IF NOT EXISTS idx_hr_att_month      ON hr_attendance_days(employee_id, shift_date DESC);
-- NOTE: EXTRACT(YEAR/MONTH FROM shift_date) removed — not IMMUTABLE in PostgreSQL.
-- Queries filter by date range: WHERE shift_date BETWEEN start AND end (uses idx_hr_att_emp_date)


-- ════════════════════════════════════════════════════════════
-- 3. ATTENDANCE LOGS — سجلات GPS (Append-only)
--    يُخزَّن هنا كل نقطة GPS منفصلة عن ملخص اليوم
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS hr_attendance_logs (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id       UUID NOT NULL REFERENCES hr_employees(id),
  attendance_day_id UUID REFERENCES hr_attendance_days(id),  -- NULL إذا لم يُنشأ اليوم بعد
  log_type          TEXT NOT NULL CHECK (log_type IN ('check_in', 'check_out', 'location_ping', 'auto_checkout')),
  latitude          NUMERIC(10,7) NOT NULL,
  longitude         NUMERIC(10,7) NOT NULL,
  gps_accuracy      NUMERIC(8,2),                            -- الدقة بالأمتار (PWA)
  location_id       UUID REFERENCES hr_work_locations(id),   -- أقرب موقع عمل مُعتمَد

  -- ─── دعم الوضع بدون اتصال (Offline Mode) ───
  is_offline_sync   BOOLEAN NOT NULL DEFAULT false,          -- هل سُجِّل أثناء انقطاع الإنترنت؟
  event_time        TIMESTAMPTZ NOT NULL DEFAULT now(),      -- الوقت الفعلي للحدث (قد يختلف عن created_at)
  synced_at         TIMESTAMPTZ,                             -- متى وصل للسيرفر (NULL = فوري)
  -- requires_review: إذا كانت الدقة سيئة أو offline sync
  requires_review   BOOLEAN NOT NULL DEFAULT false,

  device_info       TEXT,                                    -- معلومات الجهاز/المتصفح
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
  -- لا updated_at — Append-only
);

CREATE INDEX IF NOT EXISTS idx_hr_att_logs_emp    ON hr_attendance_logs(employee_id, event_time DESC);
CREATE INDEX IF NOT EXISTS idx_hr_att_logs_day    ON hr_attendance_logs(attendance_day_id);
CREATE INDEX IF NOT EXISTS idx_hr_att_logs_review ON hr_attendance_logs(requires_review) WHERE requires_review = true;
CREATE INDEX IF NOT EXISTS idx_hr_att_logs_offline ON hr_attendance_logs(is_offline_sync) WHERE is_offline_sync = true;


-- ════════════════════════════════════════════════════════════
-- 4. LEAVE TYPES — أنواع الإجازات
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS hr_leave_types (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name                TEXT NOT NULL,
  name_en             TEXT,
  code                TEXT UNIQUE NOT NULL,
  max_days_per_year   INTEGER,                    -- NULL = بلا حد (بدون أجر)
  max_days_per_request INTEGER,                   -- أقصى أيام في طلب واحد
  is_paid             BOOLEAN NOT NULL DEFAULT true,
  has_balance         BOOLEAN NOT NULL DEFAULT true,  -- هل يُتتبع رصيدها؟
  deducts_from_balance BOOLEAN NOT NULL DEFAULT true,
  requires_approval   BOOLEAN NOT NULL DEFAULT true,
  approval_levels     INTEGER NOT NULL DEFAULT 2  -- 1 = مشرف فقط، 2 = مشرف + HR
                      CHECK (approval_levels IN (1, 2)),
  requires_document   BOOLEAN NOT NULL DEFAULT false,  -- يشترط وثيقة (مثل تقرير طبي)
  can_carry_forward   BOOLEAN NOT NULL DEFAULT false,
  affects_salary      BOOLEAN NOT NULL DEFAULT false,  -- يؤثر على الراتب (بدون أجر)
  is_system           BOOLEAN NOT NULL DEFAULT false,  -- لا يمكن حذفه
  is_active           BOOLEAN NOT NULL DEFAULT true,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed: أنواع الإجازات الأساسية
INSERT INTO hr_leave_types (name, name_en, code, max_days_per_year, max_days_per_request, is_paid, has_balance, deducts_from_balance, requires_approval, approval_levels, requires_document, can_carry_forward, affects_salary, is_system) VALUES
  ('سنوية',       'Annual Leave',     'ANNUAL',    21,   14,  true,  true,  true,  true, 2, false, true,  false, true),
  ('عارضة',       'Casual Leave',     'CASUAL',    6,    3,   true,  true,  true,  true, 1, false, false, false, true),
  ('مرضية',       'Sick Leave',       'SICK',      15,   15,  true,  true,  true,  true, 1, true,  false, false, true),
  ('أمومة',       'Maternity Leave',  'MATERNITY', 90,   90,  true,  true,  true,  true, 2, false, false, false, true),
  ('مناسبات',     'Occasion Leave',   'OCCASION',  3,    3,   true,  false, false, true, 1, false, false, false, true),
  ('بدون أجر',   'Unpaid Leave',     'UNPAID',    NULL, 30,  false, false, false, true, 2, false, false, true,  true)
ON CONFLICT (code) DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- 5. LEAVE BALANCES — أرصدة الإجازات
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS hr_leave_balances (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id       UUID NOT NULL REFERENCES hr_employees(id),
  leave_type_id     UUID NOT NULL REFERENCES hr_leave_types(id),
  year              INTEGER NOT NULL,
  total_days        NUMERIC(5,1) NOT NULL DEFAULT 0,    -- المستحق للسنة
  used_days         NUMERIC(5,1) NOT NULL DEFAULT 0,    -- المستهلك (معتمد)
  pending_days      NUMERIC(5,1) NOT NULL DEFAULT 0,    -- في انتظار الاعتماد
  carried_forward   NUMERIC(5,1) NOT NULL DEFAULT 0,    -- مرحَّل من السنة السابقة
  remaining_days    NUMERIC(5,1) GENERATED ALWAYS AS (
    total_days + carried_forward - used_days
  ) STORED,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (employee_id, leave_type_id, year)
);

CREATE INDEX IF NOT EXISTS idx_hr_bal_emp  ON hr_leave_balances(employee_id, year);
CREATE INDEX IF NOT EXISTS idx_hr_bal_type ON hr_leave_balances(leave_type_id);


-- ════════════════════════════════════════════════════════════
-- 6. LEAVE REQUESTS — طلبات الإجازة
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS hr_leave_requests (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id         UUID NOT NULL REFERENCES hr_employees(id),
  leave_type_id       UUID NOT NULL REFERENCES hr_leave_types(id),
  start_date          DATE NOT NULL,
  end_date            DATE NOT NULL,
  days_count          NUMERIC(5,1) NOT NULL CHECK (days_count > 0),
  reason              TEXT,
  document_url        TEXT,                         -- وثيقة داعمة (تقرير طبي، ...)

  -- ─── دورة الاعتماد (Multi-level) ───
  status              hr_leave_request_status NOT NULL DEFAULT 'pending_supervisor',

  -- المستوى الأول: المشرف المباشر
  supervisor_id       UUID REFERENCES hr_employees(id),
  supervisor_action_at TIMESTAMPTZ,
  supervisor_notes    TEXT,

  -- المستوى الثاني: مدير HR (إذا approval_levels = 2)
  hr_manager_id       UUID REFERENCES hr_employees(id),
  hr_action_at        TIMESTAMPTZ,
  hr_notes            TEXT,

  -- الرفض
  rejection_reason    TEXT,
  rejected_by         UUID REFERENCES hr_employees(id),
  rejected_at         TIMESTAMPTZ,

  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_leave_dates CHECK (end_date >= start_date)
);

CREATE INDEX IF NOT EXISTS idx_hr_leave_emp     ON hr_leave_requests(employee_id, start_date DESC);
CREATE INDEX IF NOT EXISTS idx_hr_leave_status  ON hr_leave_requests(status);
CREATE INDEX IF NOT EXISTS idx_hr_leave_pending ON hr_leave_requests(supervisor_id, status)
  WHERE status IN ('pending_supervisor');
CREATE INDEX IF NOT EXISTS idx_hr_leave_hr      ON hr_leave_requests(hr_manager_id, status)
  WHERE status = 'pending_hr';

-- Trigger: عند اعتماد الطلب نهائياً → خصم من الرصيد
CREATE OR REPLACE FUNCTION handle_leave_approval()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_approval_levels INTEGER;
BEGIN
  -- جلب عدد مستويات الاعتماد لهذا النوع
  SELECT approval_levels INTO v_approval_levels
  FROM hr_leave_types WHERE id = NEW.leave_type_id;

  -- المشرف وافق + النوع يحتاج مستوى واحد فقط → اعتماد نهائي
  IF NEW.status = 'approved_supervisor' AND v_approval_levels = 1 THEN
    NEW.status := 'approved';
  END IF;

  -- المشرف وافق + النوع يحتاج مستويين → ينتقل لـ HR
  IF NEW.status = 'approved_supervisor' AND v_approval_levels = 2 THEN
    NEW.status := 'pending_hr';
  END IF;

  -- عند الاعتماد النهائي → خصم من الرصيد
  IF NEW.status = 'approved' AND OLD.status <> 'approved' THEN
    -- خصم المعلق وإضافة للمستهلك
    UPDATE hr_leave_balances
    SET
      used_days    = used_days + NEW.days_count,
      pending_days = GREATEST(0, pending_days - NEW.days_count),
      updated_at   = now()
    WHERE employee_id  = NEW.employee_id
      AND leave_type_id = NEW.leave_type_id
      AND year          = EXTRACT(YEAR FROM NEW.start_date)::INTEGER;
  END IF;

  -- عند الإلغاء أو الرفض → إعادة الأيام المعلقة
  IF NEW.status IN ('rejected', 'cancelled') AND OLD.status = 'pending_supervisor' THEN
    UPDATE hr_leave_balances
    SET
      pending_days = GREATEST(0, pending_days - NEW.days_count),
      updated_at   = now()
    WHERE employee_id  = NEW.employee_id
      AND leave_type_id = NEW.leave_type_id
      AND year          = EXTRACT(YEAR FROM NEW.start_date)::INTEGER;
  END IF;

  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_leave_approval ON hr_leave_requests;
CREATE TRIGGER trg_leave_approval
  BEFORE UPDATE ON hr_leave_requests
  FOR EACH ROW EXECUTE FUNCTION handle_leave_approval();

-- Trigger: عند إرسال طلب جديد → حجز الأيام في pending
CREATE OR REPLACE FUNCTION handle_leave_submission()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_has_balance BOOLEAN;
  v_remaining   NUMERIC;
BEGIN
  -- جلب إعداد الرصيد لهذا النوع
  SELECT has_balance INTO v_has_balance
  FROM hr_leave_types WHERE id = NEW.leave_type_id;

  IF v_has_balance THEN
    -- التحقق من كفاية الرصيد
    SELECT remaining_days INTO v_remaining
    FROM hr_leave_balances
    WHERE employee_id  = NEW.employee_id
      AND leave_type_id = NEW.leave_type_id
      AND year          = EXTRACT(YEAR FROM NEW.start_date)::INTEGER;

    IF v_remaining IS NULL OR (v_remaining - NEW.days_count) < 0 THEN
      RAISE EXCEPTION 'رصيد الإجازة غير كافٍ. المتبقي: %', COALESCE(v_remaining, 0);
    END IF;

    -- حجز الأيام كـ pending
    UPDATE hr_leave_balances
    SET
      pending_days = pending_days + NEW.days_count,
      updated_at   = now()
    WHERE employee_id  = NEW.employee_id
      AND leave_type_id = NEW.leave_type_id
      AND year          = EXTRACT(YEAR FROM NEW.start_date)::INTEGER;
  END IF;

  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_leave_submission ON hr_leave_requests;
CREATE TRIGGER trg_leave_submission
  BEFORE INSERT ON hr_leave_requests
  FOR EACH ROW EXECUTE FUNCTION handle_leave_submission();


-- ════════════════════════════════════════════════════════════
-- 7. PERMISSION REQUESTS — أذونات الانصراف المبكر
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS hr_permission_requests (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id       UUID NOT NULL REFERENCES hr_employees(id),
  permission_date   DATE NOT NULL,
  leave_time        TIME NOT NULL,                    -- وقت المغادرة المطلوب
  expected_return   TIME,                             -- وقت العودة المتوقع (اختياري)
  actual_return     TIME,                             -- وقت العودة الفعلي
  duration_minutes  INTEGER,                          -- مدة الغياب بالدقائق
  reason            TEXT NOT NULL,
  status            TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'approved', 'rejected')),
  approved_by       UUID REFERENCES hr_employees(id),
  action_at         TIMESTAMPTZ,
  rejection_reason  TEXT,
  -- عداد أذونات الشهر (تُحسب بالـ View)
  month_permit_count INTEGER,                         -- cached — كم مرة حصل على إذن هذا الشهر
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_hr_perm_emp    ON hr_permission_requests(employee_id, permission_date DESC);
CREATE INDEX IF NOT EXISTS idx_hr_perm_status ON hr_permission_requests(status) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_hr_perm_month  ON hr_permission_requests(employee_id, permission_date DESC);
-- NOTE: EXTRACT(YEAR/MONTH) removed — not IMMUTABLE. Queries use date range scan on permission_date.


-- ════════════════════════════════════════════════════════════
-- 8. PENALTY RULES — محرك قواعد الجزاءات
--    يدعم التدرج (Escalation) عبر occurrence_from / occurrence_to
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS hr_penalty_rules (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name                      TEXT NOT NULL,
  penalty_type              hr_penalty_type NOT NULL,

  -- ─── نطاق الوقت (للتأخير والانصراف المبكر) ───
  min_minutes               INTEGER NOT NULL DEFAULT 0,   -- من كم دقيقة
  max_minutes               INTEGER,                      -- حتى كم دقيقة (NULL = بلا حد)

  -- ─── نطاق التكرار في الشهر (التصعيد) ───
  -- المرة 1: إنذار، المرة 3: خصم ربع يوم، ...
  occurrence_from           INTEGER NOT NULL DEFAULT 1,   -- من التكرار رقم
  occurrence_to             INTEGER,                      -- حتى التكرار رقم (NULL = كل المرات)

  -- ─── نوع الجزاء ───
  deduction_type            hr_deduction_type NOT NULL DEFAULT 'none',
  deduction_custom_minutes  INTEGER DEFAULT 0,           -- دقائق محددة (إذا كان custom_minutes)

  -- ─── تصعيد تلقائي ───
  escalate_to_disciplinary  BOOLEAN NOT NULL DEFAULT false,  -- فتح قضية تأديبية
  notify_manager            BOOLEAN NOT NULL DEFAULT true,
  notify_hr                 BOOLEAN NOT NULL DEFAULT false,
  notify_ceo                BOOLEAN NOT NULL DEFAULT false,

  is_active                 BOOLEAN NOT NULL DEFAULT true,
  sort_order                INTEGER NOT NULL DEFAULT 0,      -- ترتيب التطبيق
  created_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_hr_pen_rules_type ON hr_penalty_rules(penalty_type, is_active);

-- Seed: قواعد الجزاءات الافتراضية — مبنية على وثيقة التصميم
INSERT INTO hr_penalty_rules (name, penalty_type, min_minutes, max_minutes, occurrence_from, occurrence_to, deduction_type, notify_manager, notify_hr, notify_ceo, sort_order) VALUES

  -- ── تأخير: فترة السماح (1-15 دقيقة، حتى 3 مرات) ──
  ('تأخير — فترة السماح (1-3 مرات)', 'late', 1, 15, 1, 3, 'none', false, false, false, 10),
  -- من المرة الرابعة: إنذار
  ('تأخير — فترة السماح (4+ مرات)', 'late', 1, 15, 4, NULL, 'warning', true, false, false, 11),

  -- ── تأخير بسيط (15-30 دقيقة) ──
  ('تأخير بسيط (15-30 د)', 'late', 15, 30, 1, NULL, 'warning', true, false, false, 20),

  -- ── تأخير متوسط (30-60 دقيقة) ──
  ('تأخير متوسط (30-60 د)', 'late', 30, 60, 1, NULL, 'quarter_day', true, false, false, 30),

  -- ── تأخير كبير (60-120 دقيقة) ──
  ('تأخير كبير (60-120 د)', 'late', 60, 120, 1, NULL, 'half_day', true, true, false, 40),

  -- ── غياب جزئي (أكثر من 120 دقيقة تأخير) ──
  ('غياب جزئي (أكثر من 120 د)', 'late', 120, NULL, 1, NULL, 'full_day', true, true, false, 50),

  -- ── غياب بدون إذن: اليوم الأول ──
  ('غياب بدون إذن — اليوم الأول', 'absent_unauthorized', 0, NULL, 1, 2, 'full_day', true, false, false, 60),

  -- ── غياب بدون إذن: 3 أيام+ (فتح قضية) ──
  ('غياب بدون إذن — 3 أيام أو أكثر', 'absent_unauthorized', 0, NULL, 3, 4, 'full_day', true, true, false, 70),

  -- ── غياب بدون إذن: 5 أيام+ (تنبيه طارئ للمدير العام) ──
  ('غياب بدون إذن — 5 أيام (طارئ)', 'absent_unauthorized', 0, NULL, 5, NULL, 'full_day', true, true, true, 80),

  -- ── انصراف مبكر بدون إذن ──
  ('انصراف مبكر بلا إذن', 'early_leave_unauthorized', 0, NULL, 1, NULL, 'half_day', true, false, false, 90),

  -- ── خروج من النطاق الجغرافي ──
  ('خروج من النطاق الجغرافي', 'out_of_range', 0, NULL, 1, NULL, 'warning', true, false, false, 100)
;


-- ════════════════════════════════════════════════════════════
-- 9. PENALTY INSTANCES — تطبيقات الجزاء الفعلية
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS hr_penalty_instances (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id         UUID NOT NULL REFERENCES hr_employees(id),
  attendance_day_id   UUID REFERENCES hr_attendance_days(id),
  penalty_rule_id     UUID REFERENCES hr_penalty_rules(id),
  penalty_type        hr_penalty_type NOT NULL,
  occurrence_in_month INTEGER NOT NULL DEFAULT 1,   -- رقمها في الشهر لهذا النوع
  deduction_type      hr_deduction_type NOT NULL DEFAULT 'none',
  deduction_days      NUMERIC(4,4) NOT NULL DEFAULT 0,
  -- 0.25 = ربع يوم، 0.5 = نصف يوم، 1.0 = يوم كامل
  notes               TEXT,

  -- ─── التجاوز الإداري ───
  is_overridden       BOOLEAN NOT NULL DEFAULT false,
  overridden_by       UUID REFERENCES profiles(id),
  override_reason     TEXT,
  overridden_at       TIMESTAMPTZ,

  -- ربط بمسير الراتب (يُستخدم في Migration 19)
  payroll_run_id      UUID,                          -- FK يُضاف في ملف الرواتب

  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_hr_pen_inst_emp   ON hr_penalty_instances(employee_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_hr_pen_inst_day   ON hr_penalty_instances(attendance_day_id);
CREATE INDEX IF NOT EXISTS idx_hr_pen_inst_month ON hr_penalty_instances(employee_id, created_at DESC);
-- NOTE: EXTRACT(YEAR/MONTH FROM TIMESTAMPTZ) removed — TIMESTAMPTZ is timezone-dependent, not IMMUTABLE.
-- Queries use: WHERE created_at BETWEEN month_start AND month_end + INTERVAL '1 day'


-- ════════════════════════════════════════════════════════════
-- 10. updated_at Triggers
-- ════════════════════════════════════════════════════════════

DO $$
DECLARE tbl TEXT;
BEGIN
  FOR tbl IN SELECT unnest(ARRAY[
    'hr_attendance_days', 'hr_leave_balances',
    'hr_leave_requests', 'hr_permission_requests'
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
-- 11. RLS — تأمين الجداول
-- ════════════════════════════════════════════════════════════

ALTER TABLE hr_public_holidays      ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_attendance_days      ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_attendance_logs      ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_leave_types          ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_leave_balances       ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_leave_requests       ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_permission_requests  ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_penalty_rules        ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_penalty_instances    ENABLE ROW LEVEL SECURITY;

-- عطل رسمية: الكل يقرأ — مدير HR يكتب
DROP POLICY IF EXISTS "hr_holidays_read"  ON hr_public_holidays;
CREATE POLICY "hr_holidays_read"  ON hr_public_holidays FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "hr_holidays_write" ON hr_public_holidays;
CREATE POLICY "hr_holidays_write" ON hr_public_holidays FOR ALL
  USING (check_permission(auth.uid(), 'hr.settings.update'));

-- سجلات الحضور: الموظف يرى نفسه + أصحاب hr.attendance.read
DROP POLICY IF EXISTS "hr_att_read"   ON hr_attendance_days;
CREATE POLICY "hr_att_read" ON hr_attendance_days FOR SELECT
  USING (
    employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR check_permission(auth.uid(), 'hr.attendance.read')
  );
DROP POLICY IF EXISTS "hr_att_write"  ON hr_attendance_days;
CREATE POLICY "hr_att_write" ON hr_attendance_days FOR ALL
  USING (check_permission(auth.uid(), 'hr.attendance.create'));

-- سجلات GPS: الموظف نفسه + أصحاب hr.attendance.read (INSERT مفتوح للمتصل)
DROP POLICY IF EXISTS "hr_logs_read"  ON hr_attendance_logs;
CREATE POLICY "hr_logs_read" ON hr_attendance_logs FOR SELECT
  USING (
    employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR check_permission(auth.uid(), 'hr.attendance.read')
  );
DROP POLICY IF EXISTS "hr_logs_insert" ON hr_attendance_logs;
CREATE POLICY "hr_logs_insert" ON hr_attendance_logs FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- أنواع الإجازات: الكل يقرأ
DROP POLICY IF EXISTS "hr_lt_read"  ON hr_leave_types;
CREATE POLICY "hr_lt_read"  ON hr_leave_types FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "hr_lt_write" ON hr_leave_types;
CREATE POLICY "hr_lt_write" ON hr_leave_types FOR ALL
  USING (check_permission(auth.uid(), 'hr.settings.update'));

-- أرصدة الإجازات: الموظف نفسه + hr.leaves.read
DROP POLICY IF EXISTS "hr_lb_read"  ON hr_leave_balances;
CREATE POLICY "hr_lb_read" ON hr_leave_balances FOR SELECT
  USING (
    employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR check_permission(auth.uid(), 'hr.leaves.read')
  );
DROP POLICY IF EXISTS "hr_lb_write" ON hr_leave_balances;
CREATE POLICY "hr_lb_write" ON hr_leave_balances FOR ALL
  USING (check_permission(auth.uid(), 'hr.payroll.calculate'));

-- طلبات الإجازة: الموظف + المشرف + hr.leaves.read
DROP POLICY IF EXISTS "hr_lr_read"   ON hr_leave_requests;
CREATE POLICY "hr_lr_read" ON hr_leave_requests FOR SELECT
  USING (
    employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR supervisor_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR check_permission(auth.uid(), 'hr.leaves.read')
  );
DROP POLICY IF EXISTS "hr_lr_insert" ON hr_leave_requests;
CREATE POLICY "hr_lr_insert" ON hr_leave_requests FOR INSERT
  WITH CHECK (
    employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR check_permission(auth.uid(), 'hr.leaves.create')
  );
DROP POLICY IF EXISTS "hr_lr_update" ON hr_leave_requests;
CREATE POLICY "hr_lr_update" ON hr_leave_requests FOR UPDATE
  USING (
    -- الموظف يستطيع الإلغاء فقط
    (employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid()) AND status = 'pending_supervisor')
    OR check_permission(auth.uid(), 'hr.leaves.approve')
  );

-- أذونات الانصراف: الموظف + المشرف + hr.attendance.read
DROP POLICY IF EXISTS "hr_perm_read" ON hr_permission_requests;
CREATE POLICY "hr_perm_read" ON hr_permission_requests FOR SELECT
  USING (
    employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR check_permission(auth.uid(), 'hr.attendance.read')
  );
DROP POLICY IF EXISTS "hr_perm_insert" ON hr_permission_requests;
CREATE POLICY "hr_perm_insert" ON hr_permission_requests FOR INSERT
  WITH CHECK (
    employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR check_permission(auth.uid(), 'hr.attendance.create')
  );
DROP POLICY IF EXISTS "hr_perm_update" ON hr_permission_requests;
CREATE POLICY "hr_perm_update" ON hr_permission_requests FOR UPDATE
  USING (check_permission(auth.uid(), 'hr.attendance.approve'));

-- قواعد الجزاءات: الكل يقرأ — مدير HR يعدّل
DROP POLICY IF EXISTS "hr_pen_rules_read" ON hr_penalty_rules;
CREATE POLICY "hr_pen_rules_read" ON hr_penalty_rules FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "hr_pen_rules_write" ON hr_penalty_rules;
CREATE POLICY "hr_pen_rules_write" ON hr_penalty_rules FOR ALL
  USING (check_permission(auth.uid(), 'hr.settings.update'));

-- تطبيقات الجزاء: الموظف + hr.attendance.read
DROP POLICY IF EXISTS "hr_pen_inst_read" ON hr_penalty_instances;
CREATE POLICY "hr_pen_inst_read" ON hr_penalty_instances FOR SELECT
  USING (
    employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR check_permission(auth.uid(), 'hr.attendance.read')
  );
DROP POLICY IF EXISTS "hr_pen_inst_write" ON hr_penalty_instances;
CREATE POLICY "hr_pen_inst_write" ON hr_penalty_instances FOR ALL
  USING (check_permission(auth.uid(), 'hr.attendance.approve'));


-- ════════════════════════════════════════════════════════════
-- 12. FUNCTIONS — الدوال المساعدة
-- ════════════════════════════════════════════════════════════

-- ─── دالة 1: هل هذا اليوم يوم عمل للموظف؟ ───
CREATE OR REPLACE FUNCTION is_employee_work_day(
  p_employee_id UUID,
  p_date        DATE
) RETURNS TEXT   -- 'work_day', 'weekly_off', 'public_holiday'
  LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_off_day      hr_day_of_week;
  v_company_off  TEXT;
  v_day_name     TEXT;
BEGIN
  -- 1. هل عطلة رسمية؟
  IF EXISTS (SELECT 1 FROM hr_public_holidays WHERE holiday_date = p_date) THEN
    RETURN 'public_holiday';
  END IF;

  -- 2. تحديد يوم العطلة الأسبوعية للموظف
  SELECT weekly_off_day INTO v_off_day FROM hr_employees WHERE id = p_employee_id;

  IF v_off_day IS NOT NULL THEN
    v_day_name := lower(to_char(p_date, 'day'));
    v_day_name := trim(v_day_name);
    IF v_off_day::text = v_day_name THEN
      RETURN 'weekly_off';
    END IF;
  ELSE
    -- تتبع إعداد الشركة
    SELECT value INTO v_company_off
    FROM company_settings WHERE key = 'hr.weekly_off_day';
    v_day_name := trim(lower(to_char(p_date, 'day')));
    IF lower(COALESCE(v_company_off, 'friday')) = v_day_name THEN
      RETURN 'weekly_off';
    END IF;
  END IF;

  RETURN 'work_day';
END; $$;


-- ─── دالة 2: تهيئة أرصدة الإجازات لموظف جديد ───
CREATE OR REPLACE FUNCTION initialize_employee_leave_balances(
  p_employee_id UUID,
  p_year        INTEGER DEFAULT NULL
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_year       INTEGER;
  v_leave_type hr_leave_types%ROWTYPE;
BEGIN
  v_year := COALESCE(p_year, EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER);

  FOR v_leave_type IN
    SELECT * FROM hr_leave_types
    WHERE has_balance = true AND is_active = true
  LOOP
    INSERT INTO hr_leave_balances (
      employee_id, leave_type_id, year, total_days
    ) VALUES (
      p_employee_id,
      v_leave_type.id,
      v_year,
      COALESCE(v_leave_type.max_days_per_year, 0)
    )
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;
  END LOOP;
END; $$;

-- Trigger: تهيئة أرصدة الإجازات عند إنشاء موظف جديد
CREATE OR REPLACE FUNCTION handle_new_employee_balances()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM initialize_employee_leave_balances(NEW.id);
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_init_leave_balances ON hr_employees;
CREATE TRIGGER trg_init_leave_balances
  AFTER INSERT ON hr_employees
  FOR EACH ROW EXECUTE FUNCTION handle_new_employee_balances();


-- ─── دالة 3: تطبيق الجزاءات على يوم حضور ───
CREATE OR REPLACE FUNCTION process_attendance_penalties(
  p_attendance_day_id UUID
) RETURNS INTEGER   -- عدد الجزاءات المطبقة
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_day          hr_attendance_days%ROWTYPE;
  v_rule         hr_penalty_rules%ROWTYPE;
  v_penalty_type hr_penalty_type;
  v_minutes      INTEGER;
  v_occurrence   INTEGER;
  v_deduct_days  NUMERIC;
  v_count        INTEGER := 0;
  v_month_start  DATE;
  v_month_end    DATE;
BEGIN
  SELECT * INTO v_day FROM hr_attendance_days WHERE id = p_attendance_day_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  v_month_start := date_trunc('month', v_day.shift_date)::DATE;
  v_month_end   := (date_trunc('month', v_day.shift_date) + INTERVAL '1 month - 1 day')::DATE;

  -- ─── معالجة التأخير ───
  IF v_day.late_minutes > 0 AND v_day.status IN ('present', 'late', 'half_day') THEN
    v_penalty_type := 'late';
    v_minutes      := v_day.late_minutes;

    -- عدد مرات التأخير في هذا الشهر (بما فيها الحالية)
    SELECT COUNT(*) + 1 INTO v_occurrence
    FROM hr_penalty_instances
    WHERE employee_id  = v_day.employee_id
      AND penalty_type = v_penalty_type
      AND created_at   BETWEEN v_month_start AND v_month_end + INTERVAL '1 day'
      AND attendance_day_id <> p_attendance_day_id;

    -- إيجاد القاعدة المناسبة
    SELECT * INTO v_rule
    FROM hr_penalty_rules
    WHERE penalty_type  = v_penalty_type
      AND is_active     = true
      AND v_minutes     >= min_minutes
      AND (max_minutes IS NULL OR v_minutes < max_minutes)
      AND v_occurrence  >= occurrence_from
      AND (occurrence_to IS NULL OR v_occurrence <= occurrence_to)
    ORDER BY sort_order DESC
    LIMIT 1;

    IF FOUND THEN
      -- تحويل نوع الخصم إلى أيام
      v_deduct_days := CASE v_rule.deduction_type
        WHEN 'quarter_day' THEN 0.25
        WHEN 'half_day'    THEN 0.5
        WHEN 'full_day'    THEN 1.0
        ELSE 0
      END;

      INSERT INTO hr_penalty_instances (
        employee_id, attendance_day_id, penalty_rule_id,
        penalty_type, occurrence_in_month, deduction_type, deduction_days
      ) VALUES (
        v_day.employee_id, p_attendance_day_id, v_rule.id,
        v_penalty_type, v_occurrence, v_rule.deduction_type, v_deduct_days
      );
      v_count := v_count + 1;
    END IF;
  END IF;

  -- ─── معالجة الغياب بدون إذن ───
  IF v_day.status = 'absent_unauthorized' THEN
    v_penalty_type := 'absent_unauthorized';

    SELECT COUNT(*) + 1 INTO v_occurrence
    FROM hr_penalty_instances
    WHERE employee_id  = v_day.employee_id
      AND penalty_type = v_penalty_type
      AND created_at   BETWEEN v_month_start AND v_month_end + INTERVAL '1 day'
      AND attendance_day_id <> p_attendance_day_id;

    SELECT * INTO v_rule
    FROM hr_penalty_rules
    WHERE penalty_type  = v_penalty_type
      AND is_active     = true
      AND v_occurrence  >= occurrence_from
      AND (occurrence_to IS NULL OR v_occurrence <= occurrence_to)
    ORDER BY sort_order DESC
    LIMIT 1;

    IF FOUND THEN
      v_deduct_days := CASE v_rule.deduction_type
        WHEN 'quarter_day' THEN 0.25
        WHEN 'half_day'    THEN 0.5
        WHEN 'full_day'    THEN 1.0
        ELSE 0
      END;

      INSERT INTO hr_penalty_instances (
        employee_id, attendance_day_id, penalty_rule_id,
        penalty_type, occurrence_in_month, deduction_type, deduction_days
      ) VALUES (
        v_day.employee_id, p_attendance_day_id, v_rule.id,
        v_penalty_type, v_occurrence, v_rule.deduction_type, v_deduct_days
      );
      v_count := v_count + 1;
    END IF;
  END IF;

  -- ─── معالجة الانصراف المبكر بدون إذن ───
  IF v_day.checkout_status = 'early_unauthorized' AND v_day.early_leave_minutes > 0 THEN
    v_penalty_type := 'early_leave_unauthorized';

    SELECT COUNT(*) + 1 INTO v_occurrence
    FROM hr_penalty_instances
    WHERE employee_id  = v_day.employee_id
      AND penalty_type = v_penalty_type
      AND created_at   BETWEEN v_month_start AND v_month_end + INTERVAL '1 day'
      AND attendance_day_id <> p_attendance_day_id;

    SELECT * INTO v_rule
    FROM hr_penalty_rules
    WHERE penalty_type  = v_penalty_type
      AND is_active     = true
      AND v_occurrence  >= occurrence_from
      AND (occurrence_to IS NULL OR v_occurrence <= occurrence_to)
    ORDER BY sort_order DESC
    LIMIT 1;

    IF FOUND THEN
      v_deduct_days := CASE v_rule.deduction_type
        WHEN 'quarter_day' THEN 0.25
        WHEN 'half_day'    THEN 0.5
        WHEN 'full_day'    THEN 1.0
        ELSE 0
      END;

      INSERT INTO hr_penalty_instances (
        employee_id, attendance_day_id, penalty_rule_id,
        penalty_type, occurrence_in_month, deduction_type, deduction_days
      ) VALUES (
        v_day.employee_id, p_attendance_day_id, v_rule.id,
        v_penalty_type, v_occurrence, v_rule.deduction_type, v_deduct_days
      );
      v_count := v_count + 1;
    END IF;
  END IF;

  RETURN v_count;
END; $$;


-- ─── دالة 4: ملخص الحضور الشهري (قلب كشف الحساب اللحظي) ───
CREATE OR REPLACE FUNCTION get_monthly_attendance_summary(
  p_employee_id UUID,
  p_year        INTEGER,
  p_month       INTEGER
) RETURNS JSONB
  LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_result          JSONB;
  v_month_start     DATE;
  v_month_end       DATE;
  v_working_days    INTEGER;
  v_present         INTEGER;
  v_absent_unauth   INTEGER;
  v_absent_auth     INTEGER;
  v_on_leave        INTEGER;
  v_weekly_off      INTEGER;
  v_holiday         INTEGER;
  v_total_late_min  INTEGER;
  v_total_ot_min    INTEGER;
  v_total_ded_days  NUMERIC;
  v_leave_balances  JSONB;
BEGIN
  v_month_start := make_date(p_year, p_month, 1);
  v_month_end   := (v_month_start + INTERVAL '1 month - 1 day')::DATE;

  SELECT
    COUNT(*) FILTER (WHERE status NOT IN ('weekly_off', 'public_holiday')),
    COUNT(*) FILTER (WHERE status = 'present'),
    COUNT(*) FILTER (WHERE status = 'absent_unauthorized'),
    COUNT(*) FILTER (WHERE status = 'absent_authorized'),
    COUNT(*) FILTER (WHERE status = 'on_leave'),
    COUNT(*) FILTER (WHERE status = 'weekly_off'),
    COUNT(*) FILTER (WHERE status = 'public_holiday'),
    COALESCE(SUM(late_minutes), 0)::INTEGER,
    COALESCE(SUM(overtime_minutes), 0)::INTEGER
  INTO
    v_working_days, v_present, v_absent_unauth, v_absent_auth,
    v_on_leave, v_weekly_off, v_holiday, v_total_late_min, v_total_ot_min
  FROM hr_attendance_days
  WHERE employee_id = p_employee_id
    AND shift_date  BETWEEN v_month_start AND v_month_end;

  -- إجمالي خصومات الجزاءات بالأيام
  SELECT COALESCE(SUM(deduction_days), 0)
  INTO v_total_ded_days
  FROM hr_penalty_instances
  WHERE employee_id   = p_employee_id
    AND NOT is_overridden
    AND created_at    BETWEEN v_month_start AND v_month_end + INTERVAL '1 day';

  -- أرصدة الإجازات
  SELECT jsonb_agg(jsonb_build_object(
    'type',      lt.name,
    'total',     lb.total_days,
    'used',      lb.used_days,
    'pending',   lb.pending_days,
    'remaining', lb.remaining_days
  ))
  INTO v_leave_balances
  FROM hr_leave_balances lb
  JOIN hr_leave_types lt ON lt.id = lb.leave_type_id
  WHERE lb.employee_id = p_employee_id AND lb.year = p_year;

  v_result := jsonb_build_object(
    'employee_id',        p_employee_id,
    'year',               p_year,
    'month',              p_month,
    'working_days',       COALESCE(v_working_days, 0),
    'present_days',       COALESCE(v_present, 0),
    'absent_unauthorized',COALESCE(v_absent_unauth, 0),
    'absent_authorized',  COALESCE(v_absent_auth, 0),
    'on_leave_days',      COALESCE(v_on_leave, 0),
    'weekly_off_days',    COALESCE(v_weekly_off, 0),
    'public_holidays',    COALESCE(v_holiday, 0),
    'total_late_minutes', COALESCE(v_total_late_min, 0),
    'total_overtime_minutes', COALESCE(v_total_ot_min, 0),
    'penalty_deduction_days', COALESCE(v_total_ded_days, 0),
    'leave_balances',     COALESCE(v_leave_balances, '[]'::jsonb)
  );

  RETURN v_result;
END; $$;


-- ═══════════════════════════════════════════════════════════
-- 13. VIEW — ملخص الإذن الشهري (عداد أذونات الموظف)
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW v_monthly_permission_count AS
SELECT
  employee_id,
  EXTRACT(YEAR  FROM permission_date)::INTEGER AS year,
  EXTRACT(MONTH FROM permission_date)::INTEGER AS month,
  COUNT(*) FILTER (WHERE status = 'approved') AS approved_count,
  COUNT(*) FILTER (WHERE status = 'pending')  AS pending_count
FROM hr_permission_requests
GROUP BY employee_id, year, month;


-- ════════════════════════════════════════════════════════════
-- ملاحظات التطوير المستقبلي
-- ════════════════════════════════════════════════════════════
-- TODO (V2): validate_attendance_location — تعديل الاستعلام من
--   ORDER BY distance LIMIT 1  إلى  WHERE distance <= radius
--   لتفادي حالة الفروع المتداخلة (اقتراح جيمني المعتمد)
--
-- TODO: إعداد pg_cron لتشغيل process_attendance_penalties يومياً
--       لكل الموظفين وتوليد سجلات الغياب التلقائي
--
-- الملف التالي: 19_hr_payroll_loans.sql
--   hr_payroll_periods, hr_payroll_runs, hr_payroll_lines
--   hr_advances (السلف الفورية والمجدولة), hr_advance_installments
--   RPC: calculate_payroll, approve_payroll (مع Journal Entry)
-- ════════════════════════════════════════════════════════════
