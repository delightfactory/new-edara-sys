-- ============================================================
-- Migration 19: HR Payroll & Loans
-- EDARA v2 — Idempotent: آمن للتشغيل أكثر من مرة
--
-- الجداول:
--   1. hr_payroll_periods       — فترات الرواتب (شهر/سنة)
--   2. hr_payroll_runs          — تشغيلات مسير الرواتب
--   3. hr_payroll_lines         — تفاصيل راتب كل موظف في المسير
--   4. hr_advances              — السلف (فورية ومجدولة)
--   5. hr_advance_installments  — جدول أقساط السلف المجدولة
--   6. hr_commission_targets    — لوائح الأهداف والعمولات
--   7. hr_commission_records    — سجلات العمولات المحققة
--
-- الدوال: calculate_employee_payroll, approve_payroll_run,
--         request_advance, get_employee_live_statement
-- ============================================================


-- ════════════════════════════════════════════════════════════
-- ENUMs
-- ════════════════════════════════════════════════════════════

DO $$ BEGIN
  CREATE TYPE hr_payroll_run_status AS ENUM (
    'draft', 'calculating', 'review', 'approved', 'paid', 'cancelled'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;

DO $$ BEGIN
  CREATE TYPE hr_advance_type AS ENUM ('instant', 'scheduled');
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;

DO $$ BEGIN
  CREATE TYPE hr_advance_status AS ENUM (
    'pending_supervisor', 'pending_hr', 'pending_finance',
    'approved', 'rejected', 'paid', 'fully_repaid', 'cancelled'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;

DO $$ BEGIN
  CREATE TYPE hr_installment_status AS ENUM (
    'pending', 'deducted', 'deferred', 'skipped'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END; $$;


-- ════════════════════════════════════════════════════════════
-- 1. PAYROLL PERIODS — فترات الرواتب
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS hr_payroll_periods (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  year          INTEGER NOT NULL,
  month         INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
  name          TEXT NOT NULL,                          -- مثل: "مارس 2026"
  start_date    DATE NOT NULL,
  end_date      DATE NOT NULL,
  is_closed     BOOLEAN NOT NULL DEFAULT false,         -- فترة مغلقة: لا تعديل
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (year, month)
);

CREATE INDEX IF NOT EXISTS idx_hr_pp_year_month ON hr_payroll_periods(year, month);

-- Seed: الفترة الحالية فورياً
INSERT INTO hr_payroll_periods (year, month, name, start_date, end_date)
VALUES (
  EXTRACT(YEAR  FROM CURRENT_DATE)::INTEGER,
  EXTRACT(MONTH FROM CURRENT_DATE)::INTEGER,
  to_char(CURRENT_DATE, 'Month YYYY'),
  date_trunc('month', CURRENT_DATE)::DATE,
  (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::DATE
) ON CONFLICT (year, month) DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- 2. PAYROLL RUNS — تشغيلات مسير الرواتب
-- ════════════════════════════════════════════════════════════

CREATE SEQUENCE IF NOT EXISTS hr_payroll_run_seq START WITH 1;

CREATE TABLE IF NOT EXISTS hr_payroll_runs (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  number            TEXT UNIQUE,                        -- PAY-2026-03-001 (Trigger)
  period_id         UUID NOT NULL REFERENCES hr_payroll_periods(id),
  branch_id         UUID REFERENCES branches(id),       -- NULL = كل الفروع
  status            hr_payroll_run_status NOT NULL DEFAULT 'draft',

  -- ─── الإجماليات (تُحسب عند calculate) ───
  total_gross       NUMERIC(16,2) NOT NULL DEFAULT 0,
  total_deductions  NUMERIC(16,2) NOT NULL DEFAULT 0,
  total_net         NUMERIC(16,2) NOT NULL DEFAULT 0,
  total_employees   INTEGER NOT NULL DEFAULT 0,

  -- ─── الاعتماد ───
  calculated_by     UUID REFERENCES profiles(id),
  calculated_at     TIMESTAMPTZ,
  approved_by       UUID REFERENCES profiles(id),       -- المدير المالي
  approved_at       TIMESTAMPTZ,
  paid_by           UUID REFERENCES profiles(id),
  paid_at           TIMESTAMPTZ,

  -- ─── الربط المحاسبي ───
  journal_entry_id  UUID,                               -- FK لـ journal_entries (يُعبَّأ عند approve)

  notes             TEXT,
  created_by        UUID REFERENCES profiles(id),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_hr_pr_period  ON hr_payroll_runs(period_id);
CREATE INDEX IF NOT EXISTS idx_hr_pr_status  ON hr_payroll_runs(status);
CREATE INDEX IF NOT EXISTS idx_hr_pr_branch  ON hr_payroll_runs(branch_id);

CREATE OR REPLACE FUNCTION generate_payroll_run_number()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public AS $$
DECLARE v_period hr_payroll_periods%ROWTYPE;
BEGIN
  IF NEW.number IS NULL OR NEW.number = '' THEN
    SELECT * INTO v_period FROM hr_payroll_periods WHERE id = NEW.period_id;
    NEW.number := 'PAY-' || v_period.year || '-'
      || lpad(v_period.month::text, 2, '0') || '-'
      || lpad(nextval('hr_payroll_run_seq')::text, 3, '0');
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_payroll_run_number ON hr_payroll_runs;
CREATE TRIGGER trg_payroll_run_number
  BEFORE INSERT ON hr_payroll_runs
  FOR EACH ROW EXECUTE FUNCTION generate_payroll_run_number();

DROP TRIGGER IF EXISTS trg_payroll_run_updated_at ON hr_payroll_runs;
CREATE TRIGGER trg_payroll_run_updated_at
  BEFORE UPDATE ON hr_payroll_runs
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ════════════════════════════════════════════════════════════
-- 3. PAYROLL LINES — تفاصيل راتب كل موظف في المسير
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS hr_payroll_lines (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payroll_run_id        UUID NOT NULL REFERENCES hr_payroll_runs(id) ON DELETE CASCADE,
  employee_id           UUID NOT NULL REFERENCES hr_employees(id),
  period_id             UUID NOT NULL REFERENCES hr_payroll_periods(id),

  -- ─── أيام العمل ───
  total_working_days    INTEGER NOT NULL DEFAULT 0,     -- أيام العمل الإجمالية في الشهر
  actual_work_days      NUMERIC(5,2) NOT NULL DEFAULT 0,-- الأيام الصافية (بعد الغياب والخصم)
  absent_days           NUMERIC(5,2) NOT NULL DEFAULT 0,
  deducted_days         NUMERIC(5,2) NOT NULL DEFAULT 0,-- من الجزاءات (0.25، 0.5، ...)
  overtime_hours        NUMERIC(5,2) NOT NULL DEFAULT 0,

  -- ─── المستحقات ───
  base_salary           NUMERIC(12,2) NOT NULL DEFAULT 0,
  transport_allowance   NUMERIC(12,2) NOT NULL DEFAULT 0,
  housing_allowance     NUMERIC(12,2) NOT NULL DEFAULT 0,
  other_allowances      NUMERIC(12,2) NOT NULL DEFAULT 0,
  overtime_amount       NUMERIC(12,2) NOT NULL DEFAULT 0,
  commission_amount     NUMERIC(12,2) NOT NULL DEFAULT 0,
  bonus_amount          NUMERIC(12,2) NOT NULL DEFAULT 0,
  gross_earned          NUMERIC(12,2) NOT NULL DEFAULT 0,-- المستحق الفعلي (pro-rata)

  -- ─── الخصومات ───
  absence_deduction     NUMERIC(12,2) NOT NULL DEFAULT 0,
  penalty_deduction     NUMERIC(12,2) NOT NULL DEFAULT 0,
  advance_deduction     NUMERIC(12,2) NOT NULL DEFAULT 0,-- خصم السلفة/الأقساط
  social_insurance      NUMERIC(12,2) NOT NULL DEFAULT 0,-- التأمين (إذا مُفعَّل)
  income_tax            NUMERIC(12,2) NOT NULL DEFAULT 0,-- الضريبة (إذا مُفعَّلة)
  health_insurance      NUMERIC(12,2) NOT NULL DEFAULT 0,
  other_deductions      NUMERIC(12,2) NOT NULL DEFAULT 0,
  total_deductions      NUMERIC(12,2) NOT NULL DEFAULT 0,

  -- ─── الصافي ───
  net_salary            NUMERIC(12,2) NOT NULL DEFAULT 0,

  -- ─── حالة الموظف في هذا الشهر ───
  is_partial_month      BOOLEAN NOT NULL DEFAULT false,  -- انضم أو غادر في منتصف الشهر
  hire_date_in_period   DATE,                            -- تاريخ بداية الاستحقاق
  term_date_in_period   DATE,                            -- تاريخ نهاية الاستحقاق

  -- ─── ملاحظات / Overrides ───
  override_net          NUMERIC(12,2),                   -- تعديل يدوي للصافي (يحتاج مبرر)
  override_reason       TEXT,
  notes                 TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (payroll_run_id, employee_id)
);

CREATE INDEX IF NOT EXISTS idx_hr_pl_run      ON hr_payroll_lines(payroll_run_id);
CREATE INDEX IF NOT EXISTS idx_hr_pl_employee ON hr_payroll_lines(employee_id);
CREATE INDEX IF NOT EXISTS idx_hr_pl_period   ON hr_payroll_lines(period_id);

-- ربط penalty_instances بمسير الرواتب
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_penalty_payroll_run'
  ) THEN
    ALTER TABLE hr_penalty_instances
      ADD CONSTRAINT fk_penalty_payroll_run
      FOREIGN KEY (payroll_run_id) REFERENCES hr_payroll_runs(id) ON DELETE SET NULL;
  END IF;
END; $$;


-- ════════════════════════════════════════════════════════════
-- 4. ADVANCES — السلف (فورية ومجدولة)
-- ════════════════════════════════════════════════════════════

CREATE SEQUENCE IF NOT EXISTS hr_advance_seq START WITH 1;

CREATE TABLE IF NOT EXISTS hr_advances (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  number                TEXT UNIQUE,                    -- ADV-00001 (Trigger)
  employee_id           UUID NOT NULL REFERENCES hr_employees(id),
  advance_type          hr_advance_type NOT NULL,
  amount                NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  installments_count    INTEGER NOT NULL DEFAULT 1,     -- 1 = فورية
  monthly_installment   NUMERIC(12,2),                  -- القسط الشهري
  reason                TEXT NOT NULL,
  status                hr_advance_status NOT NULL DEFAULT 'pending_supervisor',

  -- ─── دورة الاعتماد ───
  supervisor_id         UUID REFERENCES hr_employees(id),
  supervisor_action_at  TIMESTAMPTZ,
  supervisor_notes      TEXT,

  hr_manager_id         UUID REFERENCES hr_employees(id),
  hr_action_at          TIMESTAMPTZ,
  hr_notes              TEXT,

  finance_user_id       UUID REFERENCES profiles(id),   -- المالية تصرف
  finance_action_at     TIMESTAMPTZ,
  finance_notes         TEXT,
  vault_id              UUID REFERENCES vaults(id),     -- الخزنة التي صُرفت منها

  rejection_reason      TEXT,
  rejected_by           UUID REFERENCES hr_employees(id),

  -- ─── متبقي السلفة (cached) ───
  paid_amount           NUMERIC(12,2) NOT NULL DEFAULT 0,
  remaining_amount      NUMERIC(12,2) GENERATED ALWAYS AS (amount - paid_amount) STORED,

  created_by            UUID REFERENCES profiles(id),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_hr_adv_emp    ON hr_advances(employee_id);
CREATE INDEX IF NOT EXISTS idx_hr_adv_status ON hr_advances(status);

CREATE OR REPLACE FUNCTION generate_advance_number()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public AS $$
BEGIN
  IF NEW.number IS NULL OR NEW.number = '' THEN
    NEW.number := 'ADV-' || lpad(nextval('hr_advance_seq')::text, 5, '0');
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_advance_number ON hr_advances;
CREATE TRIGGER trg_advance_number
  BEFORE INSERT ON hr_advances
  FOR EACH ROW EXECUTE FUNCTION generate_advance_number();

DROP TRIGGER IF EXISTS trg_advance_updated_at ON hr_advances;
CREATE TRIGGER trg_advance_updated_at
  BEFORE UPDATE ON hr_advances
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Trigger: عند اعتماد السلفة — توليد جدول الأقساط آلياً
CREATE OR REPLACE FUNCTION handle_advance_approval()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_period_id    UUID;
  v_period_year  INTEGER;
  v_period_month INTEGER;
  i              INTEGER;
BEGIN
  -- عند الانتقال إلى approved (من pending_finance)
  IF NEW.status = 'approved' AND OLD.status <> 'approved' THEN
    -- توليد جدول الأقساط
    v_period_year  := EXTRACT(YEAR  FROM CURRENT_DATE)::INTEGER;
    v_period_month := EXTRACT(MONTH FROM CURRENT_DATE)::INTEGER;

    FOR i IN 1 .. NEW.installments_count LOOP
      -- احسب الشهر الصحيح للقسط
      DECLARE
        v_inst_year  INTEGER;
        v_inst_month INTEGER;
      BEGIN
        v_inst_month := ((v_period_month - 1 + i) % 12) + 1;
        v_inst_year  := v_period_year + ((v_period_month - 1 + i) / 12);

        -- جلب أو إنشاء الفترة
        INSERT INTO hr_payroll_periods (year, month, name, start_date, end_date)
        VALUES (
          v_inst_year, v_inst_month,
          to_char(make_date(v_inst_year, v_inst_month, 1), 'Month YYYY'),
          make_date(v_inst_year, v_inst_month, 1),
          (make_date(v_inst_year, v_inst_month, 1) + INTERVAL '1 month - 1 day')::DATE
        ) ON CONFLICT (year, month) DO NOTHING;

        SELECT id INTO v_period_id
        FROM hr_payroll_periods WHERE year = v_inst_year AND month = v_inst_month;

        INSERT INTO hr_advance_installments (
          advance_id, installment_number, period_id,
          due_year, due_month, amount, status
        ) VALUES (
          NEW.id, i, v_period_id,
          v_inst_year, v_inst_month,
          COALESCE(NEW.monthly_installment, ROUND(NEW.amount / NEW.installments_count, 2)),
          'pending'
        );
      END;
    END LOOP;
  END IF;

  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_advance_approval ON hr_advances;
CREATE TRIGGER trg_advance_approval
  AFTER UPDATE ON hr_advances
  FOR EACH ROW EXECUTE FUNCTION handle_advance_approval();


-- ════════════════════════════════════════════════════════════
-- 5. ADVANCE INSTALLMENTS — جدول أقساط السلف
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS hr_advance_installments (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  advance_id          UUID NOT NULL REFERENCES hr_advances(id) ON DELETE CASCADE,
  installment_number  INTEGER NOT NULL,
  period_id           UUID REFERENCES hr_payroll_periods(id),
  due_year            INTEGER NOT NULL,
  due_month           INTEGER NOT NULL CHECK (due_month BETWEEN 1 AND 12),
  amount              NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  status              hr_installment_status NOT NULL DEFAULT 'pending',
  -- deferred = مؤجل (إجازة بدون راتب أو قرار إداري)
  deducted_in_run_id  UUID REFERENCES hr_payroll_runs(id),
  deferred_reason     TEXT,                             -- سبب التأجيل
  deferred_to_month   INTEGER,                          -- شهر إعادة الجدولة
  deferred_to_year    INTEGER,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (advance_id, installment_number)
);

CREATE INDEX IF NOT EXISTS idx_hr_inst_advance ON hr_advance_installments(advance_id);
CREATE INDEX IF NOT EXISTS idx_hr_inst_period  ON hr_advance_installments(period_id);
CREATE INDEX IF NOT EXISTS idx_hr_inst_status  ON hr_advance_installments(status, due_year, due_month);

-- Trigger: عند خصم القسط — تحديث المبلغ المسدَّد في السلفة
CREATE OR REPLACE FUNCTION handle_installment_deducted()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'deducted' AND OLD.status <> 'deducted' THEN
    UPDATE hr_advances
    SET paid_amount = paid_amount + NEW.amount,
        updated_at  = now()
    WHERE id = NEW.advance_id;

    -- إذا تم سداد الكل → تحديث حالة السلفة
    UPDATE hr_advances
    SET status = 'fully_repaid', updated_at = now()
    WHERE id = NEW.advance_id
      AND (amount - paid_amount - NEW.amount) <= 0;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_installment_deducted ON hr_advance_installments;
CREATE TRIGGER trg_installment_deducted
  AFTER UPDATE ON hr_advance_installments
  FOR EACH ROW EXECUTE FUNCTION handle_installment_deducted();


-- ════════════════════════════════════════════════════════════
-- 6. COMMISSION TARGETS — لوائح الأهداف والعمولات
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS hr_commission_targets (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id       UUID NOT NULL REFERENCES hr_employees(id),
  period_id         UUID NOT NULL REFERENCES hr_payroll_periods(id),
  target_amount     NUMERIC(14,2) NOT NULL,             -- الهدف البيعي بالجنيه
  commission_rate   NUMERIC(5,2) NOT NULL DEFAULT 0,    -- نسبة العمولة % عند تحقيق الهدف
  -- شرائح العمولة المتدرجة
  tier_50_rate      NUMERIC(5,2) DEFAULT 0,             -- نسبة عند 50% من الهدف
  tier_75_rate      NUMERIC(5,2) DEFAULT 0,             -- نسبة عند 75% من الهدف
  tier_100_rate     NUMERIC(5,2) DEFAULT 0,             -- نسبة عند 100% من الهدف
  tier_120_rate     NUMERIC(5,2) DEFAULT 0,             -- نسبة عند تجاوز 120%
  notes             TEXT,
  created_by        UUID REFERENCES profiles(id),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (employee_id, period_id)
);

CREATE INDEX IF NOT EXISTS idx_hr_ct_emp    ON hr_commission_targets(employee_id);
CREATE INDEX IF NOT EXISTS idx_hr_ct_period ON hr_commission_targets(period_id);


-- ════════════════════════════════════════════════════════════
-- 7. COMMISSION RECORDS — سجلات العمولات المحققة
--    تُغذَّى تلقائياً من موديول المبيعات والتحصيلات
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS hr_commission_records (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id       UUID NOT NULL REFERENCES hr_employees(id),
  period_id         UUID NOT NULL REFERENCES hr_payroll_periods(id),

  -- ─── مصدر البيانات (من موديول المبيعات/التحصيلات) ───
  source_type       TEXT NOT NULL CHECK (source_type IN ('sales', 'collection', 'delivery')),
  source_id         UUID NOT NULL,                      -- معرّف الفاتورة أو الإيصال
  gross_amount      NUMERIC(14,2) NOT NULL DEFAULT 0,   -- قيمة البيع
  collected_amount  NUMERIC(14,2) NOT NULL DEFAULT 0,   -- المحصَّل فعلاً (القاعدة)

  -- ─── العمولة المحسوبة ───
  -- القاعدة: العمولة تُستحق فقط على المحصَّل
  commission_rate   NUMERIC(5,2) NOT NULL DEFAULT 0,
  commission_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  is_eligible       BOOLEAN NOT NULL DEFAULT false,     -- هل المبلغ محصَّل فعلاً؟
  included_in_run   UUID REFERENCES hr_payroll_runs(id),

  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_hr_cr_emp    ON hr_commission_records(employee_id, period_id);
CREATE INDEX IF NOT EXISTS idx_hr_cr_source ON hr_commission_records(source_type, source_id);
CREATE INDEX IF NOT EXISTS idx_hr_cr_run    ON hr_commission_records(included_in_run);


-- ════════════════════════════════════════════════════════════
-- 8. RLS
-- ════════════════════════════════════════════════════════════

ALTER TABLE hr_payroll_periods       ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_payroll_runs          ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_payroll_lines         ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_advances              ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_advance_installments  ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_commission_targets    ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_commission_records    ENABLE ROW LEVEL SECURITY;

-- فترات الرواتب: الكل يقرأ
DROP POLICY IF EXISTS "hr_pp_read"  ON hr_payroll_periods;
CREATE POLICY "hr_pp_read"  ON hr_payroll_periods FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "hr_pp_write" ON hr_payroll_periods;
CREATE POLICY "hr_pp_write" ON hr_payroll_periods FOR ALL
  USING (check_permission(auth.uid(), 'hr.payroll.calculate'));

-- مسير الرواتب (run): hr.payroll.read يقرأ — hr.payroll.calculate يكتب
DROP POLICY IF EXISTS "hr_pr_read"  ON hr_payroll_runs;
CREATE POLICY "hr_pr_read" ON hr_payroll_runs FOR SELECT
  USING (check_permission(auth.uid(), 'hr.payroll.read'));
DROP POLICY IF EXISTS "hr_pr_write" ON hr_payroll_runs;
CREATE POLICY "hr_pr_write" ON hr_payroll_runs FOR ALL
  USING (check_permission(auth.uid(), 'hr.payroll.calculate'));

-- تفاصيل الراتب: الموظف نفسه + hr.payroll.read
DROP POLICY IF EXISTS "hr_pl_read"  ON hr_payroll_lines;
CREATE POLICY "hr_pl_read" ON hr_payroll_lines FOR SELECT
  USING (
    employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR check_permission(auth.uid(), 'hr.payroll.read')
  );
DROP POLICY IF EXISTS "hr_pl_write" ON hr_payroll_lines;
CREATE POLICY "hr_pl_write" ON hr_payroll_lines FOR ALL
  USING (check_permission(auth.uid(), 'hr.payroll.calculate'));

-- السلف: الموظف + المشرف + مدير HR + المالية
DROP POLICY IF EXISTS "hr_adv_read"   ON hr_advances;
CREATE POLICY "hr_adv_read" ON hr_advances FOR SELECT
  USING (
    employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR check_permission(auth.uid(), 'hr.advances.read')
  );
DROP POLICY IF EXISTS "hr_adv_insert" ON hr_advances;
CREATE POLICY "hr_adv_insert" ON hr_advances FOR INSERT
  WITH CHECK (
    employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR check_permission(auth.uid(), 'hr.advances.create')
  );
DROP POLICY IF EXISTS "hr_adv_update" ON hr_advances;
CREATE POLICY "hr_adv_update" ON hr_advances FOR UPDATE
  USING (check_permission(auth.uid(), 'hr.advances.approve'));

-- أقساط السلف: مثل السلف
DROP POLICY IF EXISTS "hr_inst_read"  ON hr_advance_installments;
CREATE POLICY "hr_inst_read" ON hr_advance_installments FOR SELECT
  USING (
    advance_id IN (
      SELECT id FROM hr_advances
      WHERE employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    )
    OR check_permission(auth.uid(), 'hr.advances.read')
  );
DROP POLICY IF EXISTS "hr_inst_write" ON hr_advance_installments;
CREATE POLICY "hr_inst_write" ON hr_advance_installments FOR ALL
  USING (check_permission(auth.uid(), 'hr.payroll.calculate'));

-- أهداف العمولات
DROP POLICY IF EXISTS "hr_ct_read"  ON hr_commission_targets;
CREATE POLICY "hr_ct_read" ON hr_commission_targets FOR SELECT
  USING (
    employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR check_permission(auth.uid(), 'hr.payroll.read')
  );
DROP POLICY IF EXISTS "hr_ct_write" ON hr_commission_targets;
CREATE POLICY "hr_ct_write" ON hr_commission_targets FOR ALL
  USING (check_permission(auth.uid(), 'hr.payroll.calculate'));

-- سجلات العمولات
DROP POLICY IF EXISTS "hr_cr_read"  ON hr_commission_records;
CREATE POLICY "hr_cr_read" ON hr_commission_records FOR SELECT
  USING (
    employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR check_permission(auth.uid(), 'hr.payroll.read')
  );
DROP POLICY IF EXISTS "hr_cr_write" ON hr_commission_records;
CREATE POLICY "hr_cr_write" ON hr_commission_records FOR ALL
  USING (check_permission(auth.uid(), 'hr.payroll.calculate'));


-- ════════════════════════════════════════════════════════════
-- 9. FUNCTIONS
-- ════════════════════════════════════════════════════════════

-- ─── دالة 1: حساب راتب موظف واحد في مسير معين ───
CREATE OR REPLACE FUNCTION calculate_employee_payroll(
  p_employee_id  UUID,
  p_run_id       UUID
) RETURNS UUID   -- معرّف الـ payroll_line المُنشأة أو المُحدَّثة
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_run          hr_payroll_runs%ROWTYPE;
  v_period       hr_payroll_periods%ROWTYPE;
  v_emp          hr_employees%ROWTYPE;
  v_summary      JSONB;
  v_salary       RECORD;
  v_line_id      UUID;

  -- مستحقات
  v_daily_rate       NUMERIC;
  v_gross_earned     NUMERIC;
  v_overtime_amount  NUMERIC;
  v_commission       NUMERIC;

  -- خصومات
  v_absence_deduct   NUMERIC;
  v_penalty_deduct   NUMERIC;
  v_advance_deduct   NUMERIC;
  v_si_deduct        NUMERIC;   -- تأمين اجتماعي
  v_tax_deduct       NUMERIC;   -- ضريبة
  v_health_deduct    NUMERIC;

  -- إعدادات
  v_si_enabled       BOOLEAN;
  v_si_rate          NUMERIC;
  v_tax_enabled      BOOLEAN;
  v_health_enabled   BOOLEAN;
  v_health_amount    NUMERIC;
  v_working_days     INTEGER;
  v_net              NUMERIC;
BEGIN
  SELECT * INTO v_run    FROM hr_payroll_runs    WHERE id = p_run_id;
  SELECT * INTO v_period FROM hr_payroll_periods WHERE id = v_run.period_id;
  SELECT * INTO v_emp    FROM hr_employees        WHERE id = p_employee_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'بيانات غير مكتملة'; END IF;

  -- ─── جلب الراتب الفعّال في بداية الشهر ───
  SELECT * INTO v_salary
  FROM get_employee_salary_at_date(p_employee_id, v_period.start_date);

  -- ─── ملخص الحضور من migration 18 ───
  v_summary := get_monthly_attendance_summary(
    p_employee_id, v_period.year, v_period.month
  );

  -- ─── أيام العمل وحساب الراتب اليومي ───
  v_working_days  := (v_summary->>'working_days')::INTEGER;
  IF v_working_days = 0 THEN v_working_days := 26; END IF; -- افتراضي

  v_daily_rate    := COALESCE(v_salary.gross_salary, 0) / v_working_days;

  -- ─── الأيام المستحقة (بعد حساب الغياب والجزاءات) ───
  v_absence_deduct := COALESCE((v_summary->>'absent_unauthorized')::NUMERIC, 0)
                    * v_daily_rate;

  v_penalty_deduct := COALESCE((v_summary->>'penalty_deduction_days')::NUMERIC, 0)
                    * v_daily_rate;

  -- ─── الراتب المكتسب (قد يكون partial إذا انضم في منتصف الشهر) ───
  v_gross_earned := COALESCE(v_salary.gross_salary, 0);

  -- Pro-rata إذا كان الموظف انضم في هذا الشهر
  IF v_emp.hire_date > v_period.start_date AND v_emp.hire_date <= v_period.end_date THEN
    v_gross_earned := v_daily_rate
      * (v_period.end_date - v_emp.hire_date + 1);
  END IF;

  -- Pro-rata إذا كان أنهى خدمته هذا الشهر
  IF v_emp.termination_date IS NOT NULL
    AND v_emp.termination_date >= v_period.start_date
    AND v_emp.termination_date <= v_period.end_date THEN
    v_gross_earned := v_daily_rate
      * (v_emp.termination_date - v_period.start_date + 1);
  END IF;

  -- ─── الأوفرتايم ───
  DECLARE
    v_overtime_rate NUMERIC;
  BEGIN
    SELECT COALESCE(value::NUMERIC, 1.5) INTO v_overtime_rate
    FROM company_settings WHERE key = 'hr.overtime_rate';

    v_overtime_amount := COALESCE((v_summary->>'total_overtime_minutes')::NUMERIC, 0)
      / 60.0
      * (COALESCE(v_salary.base_salary, 0) / (v_working_days * 8.0))
      * v_overtime_rate;
  END;

  -- ─── العمولات المؤهلة (محصَّلة فعلاً فقط) ───
  SELECT COALESCE(SUM(commission_amount), 0) INTO v_commission
  FROM hr_commission_records
  WHERE employee_id = p_employee_id
    AND period_id   = v_run.period_id
    AND is_eligible = true
    AND included_in_run IS NULL;

  -- ─── السلف: القسط المستحق هذا الشهر ───
  SELECT COALESCE(SUM(amount), 0) INTO v_advance_deduct
  FROM hr_advance_installments ai
  JOIN hr_advances adv ON adv.id = ai.advance_id
  WHERE adv.employee_id = p_employee_id
    AND ai.due_year     = v_period.year
    AND ai.due_month    = v_period.month
    AND ai.status       = 'pending';

  -- ─── الامتثال القانوني (مفاتيح تشغيل/إيقاف) ───
  SELECT COALESCE(value::BOOLEAN, false) INTO v_si_enabled
  FROM company_settings WHERE key = 'hr.social_insurance.enabled';

  SELECT COALESCE(value::NUMERIC, 11) INTO v_si_rate
  FROM company_settings WHERE key = 'hr.social_insurance.employee_rate';

  SELECT COALESCE(value::BOOLEAN, false) INTO v_tax_enabled
  FROM company_settings WHERE key = 'hr.income_tax.enabled';

  SELECT COALESCE(value::BOOLEAN, false) INTO v_health_enabled
  FROM company_settings WHERE key = 'hr.health_insurance.enabled';

  SELECT COALESCE(value::NUMERIC, 0) INTO v_health_amount
  FROM company_settings WHERE key = 'hr.health_insurance.amount';

  v_si_deduct     := CASE WHEN v_si_enabled     THEN v_gross_earned * (v_si_rate / 100) ELSE 0 END;
  v_tax_deduct    := 0; -- يُحسب بشرائح تصاعدية — للتطوير لاحقاً
  v_health_deduct := CASE WHEN v_health_enabled  THEN v_health_amount ELSE 0 END;

  -- ─── الصافي ───
  v_net := v_gross_earned + v_overtime_amount + v_commission
         - v_absence_deduct - v_penalty_deduct - v_advance_deduct
         - v_si_deduct - v_tax_deduct - v_health_deduct;

  v_net := GREATEST(0, v_net); -- الصافي لا يقل عن صفر

  -- ─── إدراج أو تحديث سطر المسير ───
  INSERT INTO hr_payroll_lines (
    payroll_run_id, employee_id, period_id,
    total_working_days, actual_work_days,
    absent_days, deducted_days, overtime_hours,
    base_salary, transport_allowance, housing_allowance, other_allowances,
    overtime_amount, commission_amount,
    gross_earned,
    absence_deduction, penalty_deduction, advance_deduction,
    social_insurance, income_tax, health_insurance,
    total_deductions, net_salary,
    is_partial_month
  ) VALUES (
    p_run_id, p_employee_id, v_run.period_id,
    v_working_days,
    v_working_days - COALESCE((v_summary->>'absent_unauthorized')::NUMERIC, 0),
    COALESCE((v_summary->>'absent_unauthorized')::NUMERIC, 0),
    COALESCE((v_summary->>'penalty_deduction_days')::NUMERIC, 0),
    COALESCE((v_summary->>'total_overtime_minutes')::NUMERIC, 0) / 60.0,
    COALESCE(v_salary.base_salary, 0),
    COALESCE(v_salary.transport_allowance, 0),
    COALESCE(v_salary.housing_allowance, 0),
    COALESCE(v_salary.other_allowances, 0),
    v_overtime_amount,
    v_commission,
    v_gross_earned,
    v_absence_deduct, v_penalty_deduct, v_advance_deduct,
    v_si_deduct, v_tax_deduct, v_health_deduct,
    v_absence_deduct + v_penalty_deduct + v_advance_deduct
      + v_si_deduct + v_tax_deduct + v_health_deduct,
    v_net,
    (v_emp.hire_date > v_period.start_date
      OR (v_emp.termination_date IS NOT NULL AND v_emp.termination_date < v_period.end_date))
  )
  ON CONFLICT (payroll_run_id, employee_id)
  DO UPDATE SET
    gross_earned        = EXCLUDED.gross_earned,
    total_deductions    = EXCLUDED.total_deductions,
    net_salary          = EXCLUDED.net_salary,
    absence_deduction   = EXCLUDED.absence_deduction,
    penalty_deduction   = EXCLUDED.penalty_deduction,
    advance_deduction   = EXCLUDED.advance_deduction,
    commission_amount   = EXCLUDED.commission_amount,
    overtime_amount     = EXCLUDED.overtime_amount
  RETURNING id INTO v_line_id;

  -- ─── تحديث إجماليات المسير ───
  UPDATE hr_payroll_runs
  SET
    total_gross      = (SELECT COALESCE(SUM(gross_earned), 0) FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
    total_deductions = (SELECT COALESCE(SUM(total_deductions), 0) FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
    total_net        = (SELECT COALESCE(SUM(net_salary), 0) FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
    total_employees  = (SELECT COUNT(*)                         FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
    calculated_by    = auth.uid(),
    calculated_at    = now(),
    status           = 'review',
    updated_at       = now()
  WHERE id = p_run_id;

  RETURN v_line_id;
END; $$;


-- ─── دالة 2: اعتماد مسير الرواتب + توليد القيد المحاسبي ───
CREATE OR REPLACE FUNCTION approve_payroll_run(
  p_run_id  UUID,
  p_user_id UUID
) RETURNS JSONB
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_run          hr_payroll_runs%ROWTYPE;
  v_period       hr_payroll_periods%ROWTYPE;
  v_je_id        UUID;
  v_coa_salaries UUID;
  v_coa_advances UUID;
  v_coa_payable  UUID;
BEGIN
  SELECT * INTO v_run FROM hr_payroll_runs WHERE id = p_run_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'مسير الرواتب غير موجود'; END IF;
  IF v_run.status NOT IN ('review', 'calculating') THEN
    RAISE EXCEPTION 'المسير يجب أن يكون في مرحلة المراجعة';
  END IF;

  SELECT * INTO v_period FROM hr_payroll_periods WHERE id = v_run.period_id;

  -- ─── جلب معرّفات الحسابات المحاسبية ───
  SELECT id INTO v_coa_salaries FROM chart_of_accounts WHERE code = '5310';
  SELECT id INTO v_coa_advances FROM chart_of_accounts WHERE code = '2320';
  SELECT id INTO v_coa_payable  FROM chart_of_accounts WHERE code = '2310';

  -- ─── إنشاء قيد يومية مسير الرواتب ───
  INSERT INTO journal_entries (
    source_type, source_id,
    description, entry_date, is_auto, status,
    total_debit, total_credit, created_by
  ) VALUES (
    'manual', p_run_id,
    'مسير رواتب ' || v_period.name,
    v_period.end_date,
    true, 'posted',
    v_run.total_gross,
    v_run.total_gross,
    p_user_id
  ) RETURNING id INTO v_je_id;

  -- مدين: مصروف الرواتب (5310)
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit)
  VALUES (v_je_id, v_coa_salaries, v_run.total_net, 0);

  -- مدين: سلف الموظفين المُستقطعة (2320) إذا وجدت
  IF v_run.total_deductions > 0 THEN
    INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit)
    VALUES (v_je_id, v_coa_advances, v_run.total_deductions, 0);
  END IF;

  -- دائن: رواتب مستحقة الدفع (2310)
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit)
  VALUES (v_je_id, v_coa_payable, 0, v_run.total_gross);

  -- ─── تحديث حالة المسير ───
  UPDATE hr_payroll_runs
  SET
    status           = 'approved',
    approved_by      = p_user_id,
    approved_at      = now(),
    journal_entry_id = v_je_id,
    updated_at       = now()
  WHERE id = p_run_id;

  -- ─── تحديث حالة أقساط السلف المستقطعة ───
  UPDATE hr_advance_installments ai
  SET status             = 'deducted',
      deducted_in_run_id = p_run_id
  FROM hr_payroll_lines pl
  WHERE pl.payroll_run_id = p_run_id
    AND ai.advance_id IN (
      SELECT id FROM hr_advances WHERE employee_id = pl.employee_id
    )
    AND ai.due_year  = v_period.year
    AND ai.due_month = v_period.month
    AND ai.status    = 'pending';

  -- ─── تحديث سجلات العمولات ───
  UPDATE hr_commission_records
  SET included_in_run = p_run_id
  WHERE period_id   = v_run.period_id
    AND is_eligible = true
    AND included_in_run IS NULL;

  RETURN jsonb_build_object(
    'success',          true,
    'run_id',           p_run_id,
    'journal_entry_id', v_je_id,
    'total_net',        v_run.total_net,
    'employees',        v_run.total_employees
  );
END; $$;


-- ─── دالة 3: طلب سلفة مع التحقق من القواعد ───
CREATE OR REPLACE FUNCTION request_advance(
  p_employee_id       UUID,
  p_advance_type      hr_advance_type,
  p_amount            NUMERIC,
  p_installments      INTEGER,
  p_reason            TEXT,
  p_requested_by_uid  UUID
) RETURNS JSONB
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_emp              hr_employees%ROWTYPE;
  v_max_months       NUMERIC;
  v_max_active       INTEGER;
  v_instant_max_pct  NUMERIC;
  v_max_inst         INTEGER;
  v_min_inst         INTEGER;
  v_active_count     INTEGER;
  v_advance_id       UUID;
BEGIN
  SELECT * INTO v_emp FROM hr_employees WHERE id = p_employee_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'الموظف غير موجود'; END IF;

  -- ─── قراءة الإعدادات ───
  SELECT COALESCE(value::NUMERIC, 1)  INTO v_max_months   FROM company_settings WHERE key = 'hr.advance_max_months_salary';
  SELECT COALESCE(value::INTEGER, 1)  INTO v_max_active    FROM company_settings WHERE key = 'hr.advance_max_active';
  SELECT COALESCE(value::NUMERIC, 50) INTO v_instant_max_pct FROM company_settings WHERE key = 'hr.instant_advance_max_percent';
  SELECT COALESCE(value::INTEGER, 6)  INTO v_max_inst      FROM company_settings WHERE key = 'hr.advance_max_installments';
  SELECT COALESCE(value::INTEGER, 1)  INTO v_min_inst      FROM company_settings WHERE key = 'hr.advance_min_installments';

  -- ─── التحقق: سلفة نشطة؟ ───
  SELECT COUNT(*) INTO v_active_count
  FROM hr_advances
  WHERE employee_id = p_employee_id
    AND status NOT IN ('fully_repaid', 'rejected', 'cancelled');

  IF v_active_count >= v_max_active THEN
    RETURN jsonb_build_object(
      'success', false,
      'code',    'ACTIVE_ADVANCE_EXISTS',
      'message', 'لديك سلفة نشطة بالفعل. يجب إتمام سدادها أولاً'
    );
  END IF;

  -- ─── التحقق: الحد الأقصى ───
  IF p_advance_type = 'instant' THEN
    IF p_amount > (v_emp.gross_salary * v_instant_max_pct / 100) THEN
      RETURN jsonb_build_object(
        'success', false,
        'code',    'EXCEEDS_INSTANT_LIMIT',
        'message', format('السلفة الفورية لا تتجاوز %s%% من الراتب', v_instant_max_pct)
      );
    END IF;
  ELSE
    IF p_amount > (v_emp.gross_salary * v_max_months) THEN
      RETURN jsonb_build_object(
        'success', false,
        'code',    'EXCEEDS_SCHEDULED_LIMIT',
        'message', format('السلفة المجدولة لا تتجاوز %s شهر راتب', v_max_months)
      );
    END IF;
    IF p_installments < v_min_inst OR p_installments > v_max_inst THEN
      RETURN jsonb_build_object(
        'success', false,
        'code',    'INVALID_INSTALLMENTS',
        'message', format('عدد الأقساط يجب أن يكون بين %s و%s', v_min_inst, v_max_inst)
      );
    END IF;
  END IF;

  -- ─── إنشاء السلفة ───
  INSERT INTO hr_advances (
    employee_id, advance_type, amount,
    installments_count,
    monthly_installment,
    reason, status, created_by
  ) VALUES (
    p_employee_id, p_advance_type, p_amount,
    CASE p_advance_type WHEN 'instant' THEN 1 ELSE p_installments END,
    CASE p_advance_type WHEN 'instant' THEN p_amount
                         ELSE ROUND(p_amount / p_installments, 2) END,
    p_reason, 'pending_supervisor', p_requested_by_uid
  ) RETURNING id INTO v_advance_id;

  RETURN jsonb_build_object(
    'success',     true,
    'advance_id',  v_advance_id,
    'message',     'تم تقديم طلب السلفة بنجاح، في انتظار موافقة المشرف'
  );
END; $$;


-- ─── دالة 4: كشف الحساب اللحظي للموظف (Live Statement) ───
CREATE OR REPLACE FUNCTION get_employee_live_statement(
  p_employee_id UUID
) RETURNS JSONB
  LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_emp      hr_employees%ROWTYPE;
  v_summary  JSONB;
  v_year     INTEGER;
  v_month    INTEGER;
  v_salary   RECORD;
  v_advances JSONB;
  v_result   JSONB;
BEGIN
  SELECT * INTO v_emp FROM hr_employees WHERE id = p_employee_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'الموظف غير موجود'; END IF;

  v_year  := EXTRACT(YEAR  FROM CURRENT_DATE)::INTEGER;
  v_month := EXTRACT(MONTH FROM CURRENT_DATE)::INTEGER;

  -- ملخص الحضور الشهري
  v_summary := get_monthly_attendance_summary(p_employee_id, v_year, v_month);

  -- الراتب الفعّال اليوم
  SELECT * INTO v_salary FROM get_employee_salary_at_date(p_employee_id, CURRENT_DATE);

  -- السلف النشطة
  SELECT jsonb_agg(jsonb_build_object(
    'number',     number,
    'type',       advance_type,
    'amount',     amount,
    'paid',       paid_amount,
    'remaining',  remaining_amount,
    'next_installment', (
      SELECT jsonb_build_object('month', due_month, 'year', due_year, 'amount', ai.amount)
      FROM hr_advance_installments ai
      WHERE ai.advance_id = adv.id AND ai.status = 'pending'
      ORDER BY due_year, due_month LIMIT 1
    )
  ))
  INTO v_advances
  FROM hr_advances adv
  WHERE employee_id = p_employee_id
    AND status NOT IN ('fully_repaid', 'rejected', 'cancelled');

  -- ─── تجميع الكشف الكامل ───
  v_result := jsonb_build_object(
    'employee',   jsonb_build_object(
      'id',              v_emp.id,
      'name',            v_emp.full_name,
      'number',          v_emp.employee_number
    ),
    'period', jsonb_build_object(
      'year',  v_year,
      'month', v_month,
      'label', to_char(CURRENT_DATE, 'Month YYYY')
    ),
    'earnings', jsonb_build_object(
      'base_salary',          COALESCE(v_salary.base_salary, 0),
      'transport_allowance',  COALESCE(v_salary.transport_allowance, 0),
      'housing_allowance',    COALESCE(v_salary.housing_allowance, 0),
      'other_allowances',     COALESCE(v_salary.other_allowances, 0),
      'gross_salary',         COALESCE(v_salary.gross_salary, 0)
    ),
    'attendance',    v_summary,
    'advances',      COALESCE(v_advances, '[]'::jsonb),
    'note', 'هذا الكشف تقديري وليس نهائياً — يُعتد بالمسير الرسمي عند الاعتماد'
  );

  RETURN v_result;
END; $$;


-- ════════════════════════════════════════════════════════════
-- 10. صلاحيات إضافية
-- ════════════════════════════════════════════════════════════

-- السماح للمندوب بتقديم طلب سلفة
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('hr.advances.read'),
  ('hr.advances.create')
) AS p(perm)
WHERE r.name IN ('sales_rep', 'warehouse_keeper', 'sales_supervisor')
ON CONFLICT DO NOTHING;

-- مدير المالية: اعتماد مسير الرواتب والسلف
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('hr.advances.read'),
  ('hr.advances.approve'),
  ('hr.payroll.read'),
  ('hr.payroll.approve')
) AS p(perm)
WHERE r.name = 'accountant'
ON CONFLICT DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- ملاحظات التطوير المستقبلي
-- ════════════════════════════════════════════════════════════
-- Migration 20 (إذا لزم):
--   - hr_disciplinary_cases — القضايا التأديبية
--   - hr_targets_performance — نظام الأهداف المتقدم
--   - تطوير income_tax بالشرائح التصاعدية المصرية
-- pg_cron tasks (تُضبط في Supabase Dashboard):
--   - يومياً 00:01: process_attendance_penalties لكل الموظفين
--   - أول كل شهر: initialize_employee_leave_balances للسنة الجديدة
--   - آخر الشهر: تذكير مسير الرواتب لمدير HR
-- ============================================================
