-- =============================================================================
-- 21_activities_module_mvp.sql
-- موديول الأنشطة الميدانية + خطط الزيارات + خطط المكالمات + محرك الأهداف
--
-- تم بناء هذا الملف بعد مواءمة كاملة مع البنية الحالية في EDARA v2:
--   - profiles / roles / role_permissions / check_permission() / set_updated_at()
--   - hr_employees / hr_departments / branches
--   - customers / customer_branches / governorates / cities / areas
--   - products / product_categories
--   - sales_orders / sales_order_items
--   - payment_receipts
--
-- مكونات مؤجلة عمداً من هذا الـ MVP لأنها غير موجودة في الـ schema الحالية:
--   - leads
--   - complaints
--   - promotions / campaigns
--
-- ملاحظات تصميمية:
--   1) تم دعم خطط الزيارات والمكالمات مع activities عامة تربط بأي منهما.
--   2) target_progress و target_adjustments غير قابلين للكتابة المباشرة من العميل.
--   3) تم تصحيح مشكلة الجمع المضاعف في view الأداء عبر subqueries مجمعة منفصلة.
--   4) تم دعم scopes: company / branch / department / individual في محرك الأهداف.
--   5) تحديث الأهداف يتم عبر cron job مقترح كل 5 دقائق، وليس trigger لحظي في الـ MVP.
-- =============================================================================

BEGIN;

-- =============================================================================
-- 0) صلاحيات جديدة
-- =============================================================================

INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm
FROM roles r
CROSS JOIN (
  VALUES
    ('activities.update_own'),
    ('visit_plans.read_own'),
    ('call_plans.read_own')
) AS p(perm)
WHERE r.name = 'sales_rep'
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm
FROM roles r
CROSS JOIN (
  VALUES
    ('activities.read_team'),
    ('visit_plans.create'),
    ('visit_plans.read_team'),
    ('visit_plans.confirm'),
    ('visit_plans.cancel'),
    ('call_plans.create'),
    ('call_plans.read_team'),
    ('call_plans.confirm'),
    ('call_plans.cancel'),
    ('targets.read_team'),
    ('reports.activities'),
    ('reports.targets'),
    ('reports.team_performance')
) AS p(perm)
WHERE r.name = 'sales_supervisor'
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm
FROM roles r
CROSS JOIN (
  VALUES
    ('activities.read_team'),
    ('visit_plans.create'),
    ('visit_plans.read_team'),
    ('visit_plans.confirm'),
    ('visit_plans.cancel'),
    ('call_plans.create'),
    ('call_plans.read_team'),
    ('call_plans.confirm'),
    ('call_plans.cancel'),
    ('targets.read_team'),
    ('targets.assign'),
    ('reports.activities'),
    ('reports.targets'),
    ('reports.team_performance'),
    ('reports.export')
) AS p(perm)
WHERE r.name = 'branch_manager'
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm
FROM roles r
CROSS JOIN (
  VALUES
    ('activities.read_all'),
    ('visit_plans.read_all'),
    ('call_plans.read_all'),
    ('targets.assign'),
    ('reports.activities'),
    ('reports.targets'),
    ('reports.team_performance'),
    ('reports.export')
) AS p(perm)
WHERE r.name = 'ceo'
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 1) جداول الأنواع والماستر
-- =============================================================================

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

CREATE TABLE IF NOT EXISTS public.target_types (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name              VARCHAR(100) NOT NULL,
  code              VARCHAR(50) UNIQUE NOT NULL,
  unit              VARCHAR(20) NOT NULL
                    CHECK (unit IN ('currency', 'count', 'percent', 'quantity')),
  category          VARCHAR(30) NOT NULL
                    CHECK (category IN ('financial', 'activity', 'customer', 'product')),
  auto_source       VARCHAR(50) NOT NULL
                    CHECK (auto_source IN ('sales_orders', 'payment_receipts', 'activities', 'customers', 'manual')),
  auto_calc_enabled BOOLEAN NOT NULL DEFAULT true,
  description       TEXT,
  is_active         BOOLEAN NOT NULL DEFAULT true,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- 2) خطط الزيارات
-- =============================================================================

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

DROP TRIGGER IF EXISTS trg_visit_plan_templates_updated_at ON public.visit_plan_templates;
CREATE TRIGGER trg_visit_plan_templates_updated_at
  BEFORE UPDATE ON public.visit_plan_templates
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

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

DROP TRIGGER IF EXISTS trg_visit_plans_updated_at ON public.visit_plans;
CREATE TRIGGER trg_visit_plans_updated_at
  BEFORE UPDATE ON public.visit_plans
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE UNIQUE INDEX IF NOT EXISTS idx_visit_plans_daily_unique
  ON public.visit_plans(employee_id, plan_date)
  WHERE plan_type = 'daily';

CREATE INDEX IF NOT EXISTS idx_visit_plans_emp_date
  ON public.visit_plans(employee_id, plan_date DESC);

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

DROP TRIGGER IF EXISTS trg_visit_plan_items_updated_at ON public.visit_plan_items;
CREATE TRIGGER trg_visit_plan_items_updated_at
  BEFORE UPDATE ON public.visit_plan_items
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_visit_plan_items_plan
  ON public.visit_plan_items(plan_id);

CREATE INDEX IF NOT EXISTS idx_visit_plan_items_status
  ON public.visit_plan_items(plan_id, status);

-- =============================================================================
-- 3) خطط المكالمات
-- =============================================================================

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

DROP TRIGGER IF EXISTS trg_call_plan_templates_updated_at ON public.call_plan_templates;
CREATE TRIGGER trg_call_plan_templates_updated_at
  BEFORE UPDATE ON public.call_plan_templates
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

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

DROP TRIGGER IF EXISTS trg_call_plans_updated_at ON public.call_plans;
CREATE TRIGGER trg_call_plans_updated_at
  BEFORE UPDATE ON public.call_plans
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE UNIQUE INDEX IF NOT EXISTS idx_call_plans_daily_unique
  ON public.call_plans(employee_id, plan_date)
  WHERE plan_type = 'daily';

CREATE INDEX IF NOT EXISTS idx_call_plans_emp_date
  ON public.call_plans(employee_id, plan_date DESC);

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

DROP TRIGGER IF EXISTS trg_call_plan_items_updated_at ON public.call_plan_items;
CREATE TRIGGER trg_call_plan_items_updated_at
  BEFORE UPDATE ON public.call_plan_items
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_call_plan_items_plan
  ON public.call_plan_items(plan_id);

CREATE INDEX IF NOT EXISTS idx_call_plan_items_status
  ON public.call_plan_items(plan_id, status);

-- =============================================================================
-- 4) الأنشطة العامة
-- =============================================================================

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

DROP TRIGGER IF EXISTS trg_activities_updated_at ON public.activities;
CREATE TRIGGER trg_activities_updated_at
  BEFORE UPDATE ON public.activities
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_activities_emp_date
  ON public.activities(employee_id, activity_date DESC);

CREATE INDEX IF NOT EXISTS idx_activities_customer_date
  ON public.activities(customer_id, activity_date DESC)
  WHERE customer_id IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_activities_visit_plan
  ON public.activities(visit_plan_item_id)
  WHERE visit_plan_item_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_activities_call_plan
  ON public.activities(call_plan_item_id)
  WHERE call_plan_item_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_activities_outcome
  ON public.activities(outcome_type, activity_date DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_activities_not_deleted
  ON public.activities(employee_id, activity_date)
  WHERE deleted_at IS NULL;

ALTER TABLE public.visit_plan_items
  DROP CONSTRAINT IF EXISTS fk_visit_plan_items_activity;
ALTER TABLE public.visit_plan_items
  ADD CONSTRAINT fk_visit_plan_items_activity
  FOREIGN KEY (activity_id) REFERENCES public.activities(id) ON DELETE SET NULL;

ALTER TABLE public.call_plan_items
  DROP CONSTRAINT IF EXISTS fk_call_plan_items_activity;
ALTER TABLE public.call_plan_items
  ADD CONSTRAINT fk_call_plan_items_activity
  FOREIGN KEY (activity_id) REFERENCES public.activities(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.call_details (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id         UUID UNIQUE NOT NULL REFERENCES public.activities(id) ON DELETE CASCADE,
  direction           VARCHAR(10) NOT NULL CHECK (direction IN ('inbound', 'outbound')),
  call_result         VARCHAR(30) NOT NULL
                      CHECK (call_result IN ('answered', 'no_answer', 'busy', 'callback_scheduled', 'wrong_number', 'rejected')),
  phone_number        VARCHAR(50),
  attempt_count       INTEGER NOT NULL DEFAULT 1 CHECK (attempt_count > 0),
  callback_at         TIMESTAMPTZ,
  call_recording_url  TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_call_details_callback
  ON public.call_details(callback_at)
  WHERE callback_at IS NOT NULL;

-- =============================================================================
-- 5) الأهداف
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.targets (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type_id           UUID NOT NULL REFERENCES public.target_types(id),
  type_code         VARCHAR(50) NOT NULL,
  name              VARCHAR(255) NOT NULL,
  description       TEXT,
  scope             VARCHAR(20) NOT NULL
                    CHECK (scope IN ('company', 'branch', 'department', 'individual')),
  scope_id          UUID,
  period            VARCHAR(20) NOT NULL
                    CHECK (period IN ('monthly', 'quarterly', 'yearly', 'custom')),
  period_start      DATE NOT NULL,
  period_end        DATE NOT NULL,
  target_value      NUMERIC(15,2) NOT NULL CHECK (target_value > 0),
  min_value         NUMERIC(15,2),
  stretch_value     NUMERIC(15,2),
  product_id        UUID REFERENCES products(id),
  category_id       UUID REFERENCES product_categories(id),
  governorate_id    UUID REFERENCES governorates(id),
  city_id           UUID REFERENCES cities(id),
  area_id           UUID REFERENCES areas(id),
  dormancy_days     INTEGER,
  filter_criteria   JSONB NOT NULL DEFAULT '{}'::jsonb,
  parent_target_id  UUID REFERENCES public.targets(id),
  auto_split        BOOLEAN NOT NULL DEFAULT false,
  split_basis       VARCHAR(20)
                    CHECK (split_basis IN ('historical_sales', 'equal', 'manual')),
  is_paused         BOOLEAN NOT NULL DEFAULT false,
  paused_at         TIMESTAMPTZ,
  paused_reason     TEXT,
  assigned_by       UUID NOT NULL REFERENCES profiles(id),
  is_active         BOOLEAN NOT NULL DEFAULT true,
  notes             TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_target_period CHECK (period_end >= period_start),
  CONSTRAINT chk_target_scope_id CHECK (
    (scope = 'company' AND scope_id IS NULL)
    OR (scope <> 'company' AND scope_id IS NOT NULL)
  )
);

DROP TRIGGER IF EXISTS trg_targets_updated_at ON public.targets;
CREATE TRIGGER trg_targets_updated_at
  BEFORE UPDATE ON public.targets
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_targets_scope
  ON public.targets(scope, scope_id);

CREATE INDEX IF NOT EXISTS idx_targets_active_period
  ON public.targets(is_active, is_paused, period_start, period_end);

CREATE INDEX IF NOT EXISTS idx_targets_type
  ON public.targets(type_code);

CREATE INDEX IF NOT EXISTS idx_targets_product
  ON public.targets(product_id)
  WHERE product_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_targets_category
  ON public.targets(category_id)
  WHERE category_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_targets_gov
  ON public.targets(governorate_id)
  WHERE governorate_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_targets_filter_criteria
  ON public.targets USING GIN (filter_criteria);

CREATE TABLE IF NOT EXISTS public.target_progress (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  target_id       UUID NOT NULL REFERENCES public.targets(id) ON DELETE CASCADE,
  snapshot_date   DATE NOT NULL,
  achieved_value  NUMERIC(15,2) NOT NULL DEFAULT 0,
  achievement_pct NUMERIC(6,2) NOT NULL DEFAULT 0,
  trend           VARCHAR(20)
                  CHECK (trend IN ('on_track', 'at_risk', 'behind', 'achieved', 'exceeded')),
  last_calc_at    TIMESTAMPTZ,
  calc_details    JSONB NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (target_id, snapshot_date)
);

CREATE INDEX IF NOT EXISTS idx_target_progress_target_date
  ON public.target_progress(target_id, snapshot_date DESC);

CREATE TABLE IF NOT EXISTS public.target_adjustments (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  target_id     UUID NOT NULL REFERENCES public.targets(id) ON DELETE CASCADE,
  field_changed VARCHAR(50) NOT NULL
                CHECK (field_changed IN (
                  'target_value',
                  'min_value',
                  'stretch_value',
                  'period_end',
                  'is_paused',
                  'is_active',
                  'filter_criteria'
                )),
  old_value     TEXT,
  new_value     TEXT,
  reason        TEXT,
  adjusted_by   UUID REFERENCES profiles(id),
  adjusted_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_target_adjustments_target
  ON public.target_adjustments(target_id, adjusted_at DESC);

-- =============================================================================
-- 6) Functions: Helpers
-- =============================================================================

CREATE OR REPLACE FUNCTION public.target_scope_matches_employee(
  p_scope TEXT,
  p_scope_id UUID,
  p_employee_id UUID
) RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM hr_employees he
    WHERE he.id = p_employee_id
      AND he.status = 'active'
      AND (
        (p_scope = 'individual' AND he.id = p_scope_id)
        OR (p_scope = 'branch' AND he.branch_id = p_scope_id)
        OR (p_scope = 'department' AND he.department_id = p_scope_id)
        OR (p_scope = 'company')
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.sync_target_type_code()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code public.target_types.code%TYPE;
BEGIN
  SELECT code INTO v_code
  FROM public.target_types
  WHERE id = NEW.type_id
    AND is_active = true;

  IF v_code IS NULL THEN
    RAISE EXCEPTION 'نوع الهدف غير موجود أو غير نشط';
  END IF;

  NEW.type_code := v_code;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_target_scope()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.scope = 'individual' AND NOT EXISTS (
    SELECT 1 FROM hr_employees WHERE id = NEW.scope_id
  ) THEN
    RAISE EXCEPTION 'scope_id لا يشير إلى hr_employees';
  END IF;

  IF NEW.scope = 'branch' AND NOT EXISTS (
    SELECT 1 FROM branches WHERE id = NEW.scope_id
  ) THEN
    RAISE EXCEPTION 'scope_id لا يشير إلى branches';
  END IF;

  IF NEW.scope = 'department' AND NOT EXISTS (
    SELECT 1 FROM hr_departments WHERE id = NEW.scope_id
  ) THEN
    RAISE EXCEPTION 'scope_id لا يشير إلى hr_departments';
  END IF;

  IF NEW.scope = 'company' AND NEW.scope_id IS NOT NULL THEN
    RAISE EXCEPTION 'company scope يجب أن يكون scope_id = NULL';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_targets_sync_type_code ON public.targets;
CREATE TRIGGER trg_targets_sync_type_code
  BEFORE INSERT OR UPDATE OF type_id ON public.targets
  FOR EACH ROW EXECUTE FUNCTION public.sync_target_type_code();

DROP TRIGGER IF EXISTS trg_targets_validate_scope ON public.targets;
CREATE TRIGGER trg_targets_validate_scope
  BEFORE INSERT OR UPDATE OF scope, scope_id ON public.targets
  FOR EACH ROW EXECUTE FUNCTION public.validate_target_scope();

CREATE OR REPLACE FUNCTION public.validate_activity_payload()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type public.activity_types%ROWTYPE;
  v_visit_item public.visit_plan_items%ROWTYPE;
  v_visit_plan public.visit_plans%ROWTYPE;
  v_call_item public.call_plan_items%ROWTYPE;
  v_call_plan public.call_plans%ROWTYPE;
BEGIN
  SELECT * INTO v_type
  FROM public.activity_types
  WHERE id = NEW.type_id
    AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'نوع النشاط غير موجود أو غير نشط';
  END IF;

  IF v_type.requires_customer AND NEW.customer_id IS NULL THEN
    RAISE EXCEPTION 'هذا النوع من الأنشطة يتطلب عميلاً';
  END IF;

  IF NEW.visit_plan_item_id IS NOT NULL AND NEW.call_plan_item_id IS NOT NULL THEN
    RAISE EXCEPTION 'لا يمكن ربط النشاط ببند زيارة وبند مكالمة معاً';
  END IF;

  IF NEW.visit_plan_item_id IS NOT NULL THEN
    IF v_type.category <> 'visit' THEN
      RAISE EXCEPTION 'ربط بند زيارة يتطلب activity_type من فئة visit';
    END IF;

    SELECT * INTO v_visit_item
    FROM public.visit_plan_items
    WHERE id = NEW.visit_plan_item_id;

    SELECT * INTO v_visit_plan
    FROM public.visit_plans
    WHERE id = v_visit_item.plan_id;

    IF v_visit_plan.employee_id <> NEW.employee_id THEN
      RAISE EXCEPTION 'employee_id لا يطابق صاحب خطة الزيارة';
    END IF;

    IF NEW.customer_id IS NULL OR NEW.customer_id <> v_visit_item.customer_id THEN
      RAISE EXCEPTION 'customer_id لا يطابق عميل بند الزيارة';
    END IF;
  END IF;

  IF NEW.call_plan_item_id IS NOT NULL THEN
    IF v_type.category <> 'call' THEN
      RAISE EXCEPTION 'ربط بند مكالمة يتطلب activity_type من فئة call';
    END IF;

    SELECT * INTO v_call_item
    FROM public.call_plan_items
    WHERE id = NEW.call_plan_item_id;

    SELECT * INTO v_call_plan
    FROM public.call_plans
    WHERE id = v_call_item.plan_id;

    IF v_call_plan.employee_id <> NEW.employee_id THEN
      RAISE EXCEPTION 'employee_id لا يطابق صاحب خطة المكالمات';
    END IF;

    IF v_call_item.customer_id IS NOT NULL AND NEW.customer_id IS DISTINCT FROM v_call_item.customer_id THEN
      RAISE EXCEPTION 'customer_id لا يطابق عميل بند المكالمة';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_activities_validate_payload ON public.activities;
CREATE TRIGGER trg_activities_validate_payload
  BEFORE INSERT OR UPDATE ON public.activities
  FOR EACH ROW EXECUTE FUNCTION public.validate_activity_payload();

CREATE OR REPLACE FUNCTION public.sync_visit_item_from_activity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.visit_plan_item_id IS NOT NULL
     AND (OLD.visit_plan_item_id IS DISTINCT FROM NEW.visit_plan_item_id OR NEW.deleted_at IS NOT NULL) THEN
    UPDATE public.visit_plan_items
    SET activity_id = NULL,
        status = CASE WHEN status IN ('completed', 'in_progress') THEN 'pending' ELSE status END,
        actual_arrival_time = NULL,
        actual_start_time = NULL,
        actual_end_time = NULL,
        updated_at = now()
    WHERE id = OLD.visit_plan_item_id
      AND activity_id = OLD.id;
  END IF;

  IF NEW.visit_plan_item_id IS NOT NULL AND NEW.deleted_at IS NULL THEN
    UPDATE public.visit_plan_items
    SET activity_id = NEW.id,
        status = CASE
          WHEN NEW.end_time IS NOT NULL THEN 'completed'
          WHEN NEW.start_time IS NOT NULL THEN 'in_progress'
          ELSE status
        END,
        actual_arrival_time = COALESCE(actual_arrival_time, NEW.start_time),
        actual_start_time = COALESCE(NEW.start_time, actual_start_time),
        actual_end_time = COALESCE(NEW.end_time, actual_end_time),
        updated_at = now()
    WHERE id = NEW.visit_plan_item_id;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_call_item_from_activity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.call_plan_item_id IS NOT NULL
     AND (OLD.call_plan_item_id IS DISTINCT FROM NEW.call_plan_item_id OR NEW.deleted_at IS NOT NULL) THEN
    UPDATE public.call_plan_items
    SET activity_id = NULL,
        status = CASE WHEN status IN ('completed', 'in_progress') THEN 'pending' ELSE status END,
        actual_start_time = NULL,
        actual_end_time = NULL,
        updated_at = now()
    WHERE id = OLD.call_plan_item_id
      AND activity_id = OLD.id;
  END IF;

  IF NEW.call_plan_item_id IS NOT NULL AND NEW.deleted_at IS NULL THEN
    UPDATE public.call_plan_items
    SET activity_id = NEW.id,
        status = CASE
          WHEN NEW.end_time IS NOT NULL THEN 'completed'
          WHEN NEW.start_time IS NOT NULL THEN 'in_progress'
          ELSE status
        END,
        actual_start_time = COALESCE(NEW.start_time, actual_start_time),
        actual_end_time = COALESCE(NEW.end_time, actual_end_time),
        updated_at = now()
    WHERE id = NEW.call_plan_item_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_activities_sync_visit_item ON public.activities;
CREATE TRIGGER trg_activities_sync_visit_item
  AFTER INSERT OR UPDATE OF visit_plan_item_id, start_time, end_time, deleted_at ON public.activities
  FOR EACH ROW EXECUTE FUNCTION public.sync_visit_item_from_activity();

DROP TRIGGER IF EXISTS trg_activities_sync_call_item ON public.activities;
CREATE TRIGGER trg_activities_sync_call_item
  AFTER INSERT OR UPDATE OF call_plan_item_id, start_time, end_time, deleted_at ON public.activities
  FOR EACH ROW EXECUTE FUNCTION public.sync_call_item_from_activity();

CREATE OR REPLACE FUNCTION public.recalculate_visit_plan_counts(p_plan_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total      INTEGER := 0;
  v_completed  INTEGER := 0;
  v_skipped    INTEGER := 0;
  v_missed     INTEGER := 0;
  v_plan_date  DATE;
  v_new_status VARCHAR(20);
BEGIN
  SELECT plan_date INTO v_plan_date
  FROM public.visit_plans
  WHERE id = p_plan_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE status = 'completed'),
    COUNT(*) FILTER (WHERE status = 'skipped'),
    COUNT(*) FILTER (WHERE status = 'missed')
  INTO v_total, v_completed, v_skipped, v_missed
  FROM public.visit_plan_items
  WHERE plan_id = p_plan_id;

  v_new_status := CASE
    WHEN v_total = 0 THEN 'draft'
    WHEN v_completed = v_total THEN 'completed'
    WHEN (v_completed + v_skipped + v_missed) = v_total AND v_completed > 0 THEN 'partial'
    WHEN EXISTS (SELECT 1 FROM public.visit_plan_items WHERE plan_id = p_plan_id AND status = 'in_progress') THEN 'in_progress'
    WHEN v_plan_date < CURRENT_DATE AND v_completed = 0 THEN 'missed'
    WHEN v_completed > 0 THEN 'in_progress'
    ELSE 'confirmed'
  END;

  UPDATE public.visit_plans
  SET total_customers = v_total,
      completed_count = v_completed,
      skipped_count = v_skipped,
      missed_count = v_missed,
      status = CASE WHEN status = 'cancelled' THEN status ELSE v_new_status END,
      started_at = CASE
        WHEN started_at IS NULL AND v_completed > 0 THEN now()
        ELSE started_at
      END,
      completed_at = CASE
        WHEN v_new_status IN ('completed', 'partial', 'missed') THEN COALESCE(completed_at, now())
        ELSE NULL
      END,
      updated_at = now()
  WHERE id = p_plan_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.recalculate_call_plan_counts(p_plan_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total      INTEGER := 0;
  v_completed  INTEGER := 0;
  v_skipped    INTEGER := 0;
  v_missed     INTEGER := 0;
  v_plan_date  DATE;
  v_new_status VARCHAR(20);
BEGIN
  SELECT plan_date INTO v_plan_date
  FROM public.call_plans
  WHERE id = p_plan_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE status = 'completed'),
    COUNT(*) FILTER (WHERE status = 'skipped'),
    COUNT(*) FILTER (WHERE status = 'missed')
  INTO v_total, v_completed, v_skipped, v_missed
  FROM public.call_plan_items
  WHERE plan_id = p_plan_id;

  v_new_status := CASE
    WHEN v_total = 0 THEN 'draft'
    WHEN v_completed = v_total THEN 'completed'
    WHEN (v_completed + v_skipped + v_missed) = v_total AND v_completed > 0 THEN 'partial'
    WHEN EXISTS (SELECT 1 FROM public.call_plan_items WHERE plan_id = p_plan_id AND status = 'in_progress') THEN 'in_progress'
    WHEN v_plan_date < CURRENT_DATE AND v_completed = 0 THEN 'missed'
    WHEN v_completed > 0 THEN 'in_progress'
    ELSE 'confirmed'
  END;

  UPDATE public.call_plans
  SET total_calls = v_total,
      completed_count = v_completed,
      skipped_count = v_skipped,
      missed_count = v_missed,
      status = CASE WHEN status = 'cancelled' THEN status ELSE v_new_status END,
      started_at = CASE
        WHEN started_at IS NULL AND v_completed > 0 THEN now()
        ELSE started_at
      END,
      completed_at = CASE
        WHEN v_new_status IN ('completed', 'partial', 'missed') THEN COALESCE(completed_at, now())
        ELSE NULL
      END,
      updated_at = now()
  WHERE id = p_plan_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_recalculate_visit_plan_counts()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.recalculate_visit_plan_counts(OLD.plan_id);
    RETURN OLD;
  END IF;

  PERFORM public.recalculate_visit_plan_counts(NEW.plan_id);

  IF TG_OP = 'UPDATE' AND OLD.plan_id IS DISTINCT FROM NEW.plan_id THEN
    PERFORM public.recalculate_visit_plan_counts(OLD.plan_id);
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_recalculate_call_plan_counts()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.recalculate_call_plan_counts(OLD.plan_id);
    RETURN OLD;
  END IF;

  PERFORM public.recalculate_call_plan_counts(NEW.plan_id);

  IF TG_OP = 'UPDATE' AND OLD.plan_id IS DISTINCT FROM NEW.plan_id THEN
    PERFORM public.recalculate_call_plan_counts(OLD.plan_id);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_visit_plan_items_recalc ON public.visit_plan_items;
CREATE TRIGGER trg_visit_plan_items_recalc
  AFTER INSERT OR UPDATE OR DELETE ON public.visit_plan_items
  FOR EACH ROW EXECUTE FUNCTION public.trg_recalculate_visit_plan_counts();

DROP TRIGGER IF EXISTS trg_call_plan_items_recalc ON public.call_plan_items;
CREATE TRIGGER trg_call_plan_items_recalc
  AFTER INSERT OR UPDATE OR DELETE ON public.call_plan_items
  FOR EACH ROW EXECUTE FUNCTION public.trg_recalculate_call_plan_counts();

CREATE OR REPLACE FUNCTION public.log_target_adjustments()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor UUID := COALESCE(auth.uid(), NEW.assigned_by, OLD.assigned_by);
BEGIN
  IF NEW.target_value IS DISTINCT FROM OLD.target_value THEN
    INSERT INTO public.target_adjustments (target_id, field_changed, old_value, new_value, adjusted_by)
    VALUES (NEW.id, 'target_value', OLD.target_value::TEXT, NEW.target_value::TEXT, v_actor);
  END IF;

  IF NEW.min_value IS DISTINCT FROM OLD.min_value THEN
    INSERT INTO public.target_adjustments (target_id, field_changed, old_value, new_value, adjusted_by)
    VALUES (NEW.id, 'min_value', OLD.min_value::TEXT, NEW.min_value::TEXT, v_actor);
  END IF;

  IF NEW.stretch_value IS DISTINCT FROM OLD.stretch_value THEN
    INSERT INTO public.target_adjustments (target_id, field_changed, old_value, new_value, adjusted_by)
    VALUES (NEW.id, 'stretch_value', OLD.stretch_value::TEXT, NEW.stretch_value::TEXT, v_actor);
  END IF;

  IF NEW.period_end IS DISTINCT FROM OLD.period_end THEN
    INSERT INTO public.target_adjustments (target_id, field_changed, old_value, new_value, adjusted_by)
    VALUES (NEW.id, 'period_end', OLD.period_end::TEXT, NEW.period_end::TEXT, v_actor);
  END IF;

  IF NEW.is_paused IS DISTINCT FROM OLD.is_paused THEN
    INSERT INTO public.target_adjustments (target_id, field_changed, old_value, new_value, adjusted_by)
    VALUES (NEW.id, 'is_paused', OLD.is_paused::TEXT, NEW.is_paused::TEXT, v_actor);
  END IF;

  IF NEW.is_active IS DISTINCT FROM OLD.is_active THEN
    INSERT INTO public.target_adjustments (target_id, field_changed, old_value, new_value, adjusted_by)
    VALUES (NEW.id, 'is_active', OLD.is_active::TEXT, NEW.is_active::TEXT, v_actor);
  END IF;

  IF NEW.filter_criteria IS DISTINCT FROM OLD.filter_criteria THEN
    INSERT INTO public.target_adjustments (target_id, field_changed, old_value, new_value, adjusted_by)
    VALUES (NEW.id, 'filter_criteria', OLD.filter_criteria::TEXT, NEW.filter_criteria::TEXT, v_actor);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_targets_log_adjustments ON public.targets;
CREATE TRIGGER trg_targets_log_adjustments
  AFTER UPDATE ON public.targets
  FOR EACH ROW EXECUTE FUNCTION public.log_target_adjustments();

-- =============================================================================
-- 7) محرك حساب الأهداف
-- =============================================================================

CREATE OR REPLACE FUNCTION public.recalculate_target_progress(
  p_target_id UUID,
  p_snapshot_date DATE DEFAULT CURRENT_DATE
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target       public.targets%ROWTYPE;
  v_achieved     NUMERIC(15,2) := 0;
  v_pct          NUMERIC(6,2) := 0;
  v_days_elapsed NUMERIC := 0;
  v_total_days   NUMERIC := 0;
  v_expected_pct NUMERIC := 0;
  v_trend        VARCHAR(20) := 'on_track';
BEGIN
  SELECT *
  INTO v_target
  FROM public.targets
  WHERE id = p_target_id
    AND is_active = true
    AND is_paused = false;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  CASE v_target.type_code
    WHEN 'sales_value' THEN
      SELECT COALESCE(SUM(so.total_amount), 0)
      INTO v_achieved
      FROM sales_orders so
      JOIN hr_employees he
        ON he.user_id = so.rep_id
      LEFT JOIN customers c
        ON c.id = so.customer_id
      WHERE public.target_scope_matches_employee(v_target.scope, v_target.scope_id, he.id)
        AND so.status IN ('delivered', 'completed')
        AND so.delivered_at::DATE BETWEEN v_target.period_start AND p_snapshot_date
        AND (v_target.product_id IS NULL OR EXISTS (
          SELECT 1
          FROM sales_order_items soi
          WHERE soi.order_id = so.id
            AND soi.product_id = v_target.product_id
        ))
        AND (v_target.category_id IS NULL OR EXISTS (
          SELECT 1
          FROM sales_order_items soi
          JOIN products p ON p.id = soi.product_id
          WHERE soi.order_id = so.id
            AND p.category_id = v_target.category_id
        ))
        AND (v_target.governorate_id IS NULL OR c.governorate_id = v_target.governorate_id)
        AND (v_target.city_id IS NULL OR c.city_id = v_target.city_id)
        AND (v_target.area_id IS NULL OR c.area_id = v_target.area_id);

    WHEN 'collection' THEN
      SELECT COALESCE(SUM(pr.amount), 0)
      INTO v_achieved
      FROM payment_receipts pr
      JOIN hr_employees he
        ON he.user_id = pr.collected_by
      LEFT JOIN customers c
        ON c.id = pr.customer_id
      WHERE public.target_scope_matches_employee(v_target.scope, v_target.scope_id, he.id)
        AND pr.status = 'confirmed'
        AND pr.created_at::DATE BETWEEN v_target.period_start AND p_snapshot_date
        AND (v_target.governorate_id IS NULL OR c.governorate_id = v_target.governorate_id)
        AND (v_target.city_id IS NULL OR c.city_id = v_target.city_id)
        AND (v_target.area_id IS NULL OR c.area_id = v_target.area_id);

    WHEN 'visits_count' THEN
      SELECT COUNT(*)::NUMERIC
      INTO v_achieved
      FROM public.activities a
      JOIN public.activity_types at_ ON at_.id = a.type_id
      WHERE public.target_scope_matches_employee(v_target.scope, v_target.scope_id, a.employee_id)
        AND at_.category = 'visit'
        AND a.deleted_at IS NULL
        AND a.activity_date BETWEEN v_target.period_start AND p_snapshot_date
        AND (v_target.governorate_id IS NULL OR EXISTS (
          SELECT 1 FROM customers c
          WHERE c.id = a.customer_id AND c.governorate_id = v_target.governorate_id
        ))
        AND (v_target.city_id IS NULL OR EXISTS (
          SELECT 1 FROM customers c
          WHERE c.id = a.customer_id AND c.city_id = v_target.city_id
        ))
        AND (v_target.area_id IS NULL OR EXISTS (
          SELECT 1 FROM customers c
          WHERE c.id = a.customer_id AND c.area_id = v_target.area_id
        ));

    WHEN 'calls_count' THEN
      SELECT COUNT(*)::NUMERIC
      INTO v_achieved
      FROM public.activities a
      JOIN public.activity_types at_ ON at_.id = a.type_id
      WHERE public.target_scope_matches_employee(v_target.scope, v_target.scope_id, a.employee_id)
        AND at_.category = 'call'
        AND a.deleted_at IS NULL
        AND a.activity_date BETWEEN v_target.period_start AND p_snapshot_date
        AND (v_target.governorate_id IS NULL OR EXISTS (
          SELECT 1 FROM customers c
          WHERE c.id = a.customer_id AND c.governorate_id = v_target.governorate_id
        ))
        AND (v_target.city_id IS NULL OR EXISTS (
          SELECT 1 FROM customers c
          WHERE c.id = a.customer_id AND c.city_id = v_target.city_id
        ))
        AND (v_target.area_id IS NULL OR EXISTS (
          SELECT 1 FROM customers c
          WHERE c.id = a.customer_id AND c.area_id = v_target.area_id
        ));

    WHEN 'new_customers' THEN
      SELECT COUNT(*)::NUMERIC
      INTO v_achieved
      FROM customers c
      LEFT JOIN hr_employees he
        ON he.user_id = c.assigned_rep_id
      WHERE c.is_active = true
        AND c.created_at::DATE BETWEEN v_target.period_start AND p_snapshot_date
        AND (
          (v_target.scope = 'company')
          OR (he.id IS NOT NULL AND public.target_scope_matches_employee(v_target.scope, v_target.scope_id, he.id))
        )
        AND (v_target.governorate_id IS NULL OR c.governorate_id = v_target.governorate_id)
        AND (v_target.city_id IS NULL OR c.city_id = v_target.city_id)
        AND (v_target.area_id IS NULL OR c.area_id = v_target.area_id);

    WHEN 'reactivation' THEN
      SELECT COUNT(DISTINCT a.customer_id)::NUMERIC
      INTO v_achieved
      FROM public.activities a
      LEFT JOIN customers c
        ON c.id = a.customer_id
      WHERE public.target_scope_matches_employee(v_target.scope, v_target.scope_id, a.employee_id)
        AND a.deleted_at IS NULL
        AND a.outcome_type IN ('order_placed', 'agreed_order')
        AND a.customer_id IS NOT NULL
        AND a.activity_date BETWEEN v_target.period_start AND p_snapshot_date
        AND (v_target.governorate_id IS NULL OR c.governorate_id = v_target.governorate_id)
        AND (v_target.city_id IS NULL OR c.city_id = v_target.city_id)
        AND (v_target.area_id IS NULL OR c.area_id = v_target.area_id)
        AND NOT EXISTS (
          SELECT 1
          FROM sales_orders so_old
          WHERE so_old.customer_id = a.customer_id
            AND so_old.status IN ('delivered', 'completed')
            AND so_old.delivered_at >= (
              v_target.period_start - (COALESCE(v_target.dormancy_days, 60) || ' days')::INTERVAL
            )
            AND so_old.delivered_at < v_target.period_start
        );

    WHEN 'product_qty' THEN
      SELECT COALESCE(SUM(soi.base_quantity), 0)
      INTO v_achieved
      FROM sales_order_items soi
      JOIN sales_orders so
        ON so.id = soi.order_id
      JOIN hr_employees he
        ON he.user_id = so.rep_id
      LEFT JOIN customers c
        ON c.id = so.customer_id
      LEFT JOIN products p
        ON p.id = soi.product_id
      WHERE public.target_scope_matches_employee(v_target.scope, v_target.scope_id, he.id)
        AND so.status IN ('delivered', 'completed')
        AND so.delivered_at::DATE BETWEEN v_target.period_start AND p_snapshot_date
        AND (v_target.product_id IS NULL OR soi.product_id = v_target.product_id)
        AND (v_target.category_id IS NULL OR p.category_id = v_target.category_id)
        AND (v_target.governorate_id IS NULL OR c.governorate_id = v_target.governorate_id)
        AND (v_target.city_id IS NULL OR c.city_id = v_target.city_id)
        AND (v_target.area_id IS NULL OR c.area_id = v_target.area_id);

    ELSE
      v_achieved := 0;
  END CASE;

  v_pct := CASE
    WHEN v_target.target_value = 0 THEN 0
    ELSE ROUND((v_achieved / v_target.target_value) * 100, 2)
  END;

  v_days_elapsed := GREATEST((p_snapshot_date - v_target.period_start + 1), 0);
  v_total_days := GREATEST((v_target.period_end - v_target.period_start + 1), 1);
  v_expected_pct := ROUND((v_days_elapsed / v_total_days) * 100, 2);

  v_trend := CASE
    WHEN v_achieved >= COALESCE(v_target.stretch_value, v_target.target_value * 1.2) THEN 'exceeded'
    WHEN v_achieved >= v_target.target_value THEN 'achieved'
    WHEN v_pct < (v_expected_pct - 20) THEN 'behind'
    WHEN v_pct < (v_expected_pct - 10) THEN 'at_risk'
    ELSE 'on_track'
  END;

  INSERT INTO public.target_progress (
    target_id,
    snapshot_date,
    achieved_value,
    achievement_pct,
    trend,
    last_calc_at,
    calc_details
  )
  VALUES (
    p_target_id,
    p_snapshot_date,
    v_achieved,
    v_pct,
    v_trend,
    now(),
    jsonb_build_object(
      'scope', v_target.scope,
      'type_code', v_target.type_code,
      'expected_pct', v_expected_pct
    )
  )
  ON CONFLICT (target_id, snapshot_date) DO UPDATE SET
    achieved_value = EXCLUDED.achieved_value,
    achievement_pct = EXCLUDED.achievement_pct,
    trend = EXCLUDED.trend,
    last_calc_at = EXCLUDED.last_calc_at,
    calc_details = EXCLUDED.calc_details;
END;
$$;

CREATE OR REPLACE FUNCTION public.recalculate_all_active_targets(
  p_snapshot_date DATE DEFAULT CURRENT_DATE
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target_id UUID;
BEGIN
  FOR v_target_id IN
    SELECT id
    FROM public.targets
    WHERE is_active = true
      AND is_paused = false
      AND period_start <= p_snapshot_date
      AND period_end >= p_snapshot_date
  LOOP
    PERFORM public.recalculate_target_progress(v_target_id, p_snapshot_date);
  END LOOP;
END;
$$;

-- =============================================================================
-- 8) RLS
-- =============================================================================

ALTER TABLE public.activity_types         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.target_types           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visit_plan_templates   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visit_plans            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visit_plan_items       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_plan_templates    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_plans             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_plan_items        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activities             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_details           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.targets                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.target_progress        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.target_adjustments     ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS activity_types_read ON public.activity_types;
CREATE POLICY activity_types_read ON public.activity_types
  FOR SELECT
  USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS target_types_read ON public.target_types;
CREATE POLICY target_types_read ON public.target_types
  FOR SELECT
  USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS vpt_read ON public.visit_plan_templates;
CREATE POLICY vpt_read ON public.visit_plan_templates
  FOR SELECT
  USING (
    created_by = auth.uid()
    OR (employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid()))
    OR (
      check_permission(auth.uid(), 'visit_plans.read_team')
      AND branch_id IN (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
    )
    OR check_permission(auth.uid(), 'visit_plans.read_all')
  );

DROP POLICY IF EXISTS vpt_insert ON public.visit_plan_templates;
CREATE POLICY vpt_insert ON public.visit_plan_templates
  FOR INSERT
  WITH CHECK (
    check_permission(auth.uid(), 'visit_plans.create')
    AND (
      branch_id IS NULL
      OR branch_id IN (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
      OR check_permission(auth.uid(), 'visit_plans.read_all')
    )
  );

DROP POLICY IF EXISTS vpt_update ON public.visit_plan_templates;
CREATE POLICY vpt_update ON public.visit_plan_templates
  FOR UPDATE
  USING (
    (
      check_permission(auth.uid(), 'visit_plans.create')
      AND (
        created_by = auth.uid()
        OR employee_id IN (
          SELECT id
          FROM hr_employees
          WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
        )
        OR branch_id IN (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
      )
    )
    OR check_permission(auth.uid(), 'visit_plans.read_all')
  )
  WITH CHECK (
    (
      check_permission(auth.uid(), 'visit_plans.create')
      AND (
        created_by = auth.uid()
        OR employee_id IN (
          SELECT id
          FROM hr_employees
          WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
        )
        OR branch_id IN (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
      )
    )
    OR check_permission(auth.uid(), 'visit_plans.read_all')
  );

DROP POLICY IF EXISTS vp_read ON public.visit_plans;
CREATE POLICY vp_read ON public.visit_plans
  FOR SELECT
  USING (
    employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR (
      check_permission(auth.uid(), 'visit_plans.read_team')
      AND employee_id IN (
        SELECT id
        FROM hr_employees
        WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
      )
    )
    OR check_permission(auth.uid(), 'visit_plans.read_all')
  );

DROP POLICY IF EXISTS vp_insert ON public.visit_plans;
CREATE POLICY vp_insert ON public.visit_plans
  FOR INSERT
  WITH CHECK (
    check_permission(auth.uid(), 'visit_plans.create')
    AND (
      employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
      OR (
        check_permission(auth.uid(), 'visit_plans.read_team')
        AND employee_id IN (
          SELECT id
          FROM hr_employees
          WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
        )
      )
      OR check_permission(auth.uid(), 'visit_plans.read_all')
    )
  );

DROP POLICY IF EXISTS vp_update ON public.visit_plans;
CREATE POLICY vp_update ON public.visit_plans
  FOR UPDATE
  USING (
    (
      check_permission(auth.uid(), 'visit_plans.create')
      AND employee_id IN (
        SELECT id
        FROM hr_employees
        WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
      )
    )
    OR (
      check_permission(auth.uid(), 'visit_plans.confirm')
      AND employee_id IN (
        SELECT id
        FROM hr_employees
        WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
      )
    )
    OR (
      check_permission(auth.uid(), 'visit_plans.cancel')
      AND employee_id IN (
        SELECT id
        FROM hr_employees
        WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
      )
    )
    OR check_permission(auth.uid(), 'visit_plans.read_all')
  )
  WITH CHECK (
    (
      check_permission(auth.uid(), 'visit_plans.create')
      AND employee_id IN (
        SELECT id
        FROM hr_employees
        WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
      )
    )
    OR (
      check_permission(auth.uid(), 'visit_plans.confirm')
      AND employee_id IN (
        SELECT id
        FROM hr_employees
        WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
      )
    )
    OR (
      check_permission(auth.uid(), 'visit_plans.cancel')
      AND employee_id IN (
        SELECT id
        FROM hr_employees
        WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
      )
    )
    OR check_permission(auth.uid(), 'visit_plans.read_all')
  );

DROP POLICY IF EXISTS vpi_read ON public.visit_plan_items;
CREATE POLICY vpi_read ON public.visit_plan_items
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.visit_plans vp
      WHERE vp.id = plan_id
        AND (
          vp.employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
          OR (
            check_permission(auth.uid(), 'visit_plans.read_team')
            AND vp.employee_id IN (
              SELECT id
              FROM hr_employees
              WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
            )
          )
          OR check_permission(auth.uid(), 'visit_plans.read_all')
        )
    )
  );

DROP POLICY IF EXISTS vpi_insert ON public.visit_plan_items;
CREATE POLICY vpi_insert ON public.visit_plan_items
  FOR INSERT
  WITH CHECK (
    check_permission(auth.uid(), 'visit_plans.create')
    AND EXISTS (
      SELECT 1
      FROM public.visit_plans vp
      WHERE vp.id = plan_id
        AND (
          vp.employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
          OR (
            check_permission(auth.uid(), 'visit_plans.read_team')
            AND vp.employee_id IN (
              SELECT id
              FROM hr_employees
              WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
            )
          )
          OR check_permission(auth.uid(), 'visit_plans.read_all')
        )
    )
  );

DROP POLICY IF EXISTS vpi_update ON public.visit_plan_items;
CREATE POLICY vpi_update ON public.visit_plan_items
  FOR UPDATE
  USING (
    (
      check_permission(auth.uid(), 'visit_plans.create')
      AND EXISTS (
        SELECT 1
        FROM public.visit_plans vp
        WHERE vp.id = plan_id
          AND vp.employee_id IN (
            SELECT id
            FROM hr_employees
            WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
          )
      )
    )
    OR (
      check_permission(auth.uid(), 'visit_plans.confirm')
      AND EXISTS (
        SELECT 1
        FROM public.visit_plans vp
        WHERE vp.id = plan_id
          AND vp.employee_id IN (
            SELECT id
            FROM hr_employees
            WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
          )
      )
    )
    OR (
      check_permission(auth.uid(), 'visit_plans.cancel')
      AND EXISTS (
        SELECT 1
        FROM public.visit_plans vp
        WHERE vp.id = plan_id
          AND vp.employee_id IN (
            SELECT id
            FROM hr_employees
            WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
          )
      )
    )
    OR check_permission(auth.uid(), 'visit_plans.read_all')
  )
  WITH CHECK (
    (
      check_permission(auth.uid(), 'visit_plans.create')
      AND EXISTS (
        SELECT 1
        FROM public.visit_plans vp
        WHERE vp.id = plan_id
          AND vp.employee_id IN (
            SELECT id
            FROM hr_employees
            WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
          )
      )
    )
    OR (
      check_permission(auth.uid(), 'visit_plans.confirm')
      AND EXISTS (
        SELECT 1
        FROM public.visit_plans vp
        WHERE vp.id = plan_id
          AND vp.employee_id IN (
            SELECT id
            FROM hr_employees
            WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
          )
      )
    )
    OR (
      check_permission(auth.uid(), 'visit_plans.cancel')
      AND EXISTS (
        SELECT 1
        FROM public.visit_plans vp
        WHERE vp.id = plan_id
          AND vp.employee_id IN (
            SELECT id
            FROM hr_employees
            WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
          )
      )
    )
    OR check_permission(auth.uid(), 'visit_plans.read_all')
  );

DROP POLICY IF EXISTS cpt_read ON public.call_plan_templates;
CREATE POLICY cpt_read ON public.call_plan_templates
  FOR SELECT
  USING (
    created_by = auth.uid()
    OR (employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid()))
    OR (
      check_permission(auth.uid(), 'call_plans.read_team')
      AND branch_id IN (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
    )
    OR check_permission(auth.uid(), 'call_plans.read_all')
  );

DROP POLICY IF EXISTS cpt_insert ON public.call_plan_templates;
CREATE POLICY cpt_insert ON public.call_plan_templates
  FOR INSERT
  WITH CHECK (
    check_permission(auth.uid(), 'call_plans.create')
    AND (
      branch_id IS NULL
      OR branch_id IN (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
      OR check_permission(auth.uid(), 'call_plans.read_all')
    )
  );

DROP POLICY IF EXISTS cpt_update ON public.call_plan_templates;
CREATE POLICY cpt_update ON public.call_plan_templates
  FOR UPDATE
  USING (
    (
      check_permission(auth.uid(), 'call_plans.create')
      AND (
        created_by = auth.uid()
        OR employee_id IN (
          SELECT id
          FROM hr_employees
          WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
        )
        OR branch_id IN (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
      )
    )
    OR check_permission(auth.uid(), 'call_plans.read_all')
  )
  WITH CHECK (
    (
      check_permission(auth.uid(), 'call_plans.create')
      AND (
        created_by = auth.uid()
        OR employee_id IN (
          SELECT id
          FROM hr_employees
          WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
        )
        OR branch_id IN (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
      )
    )
    OR check_permission(auth.uid(), 'call_plans.read_all')
  );

DROP POLICY IF EXISTS cp_read ON public.call_plans;
CREATE POLICY cp_read ON public.call_plans
  FOR SELECT
  USING (
    employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR (
      check_permission(auth.uid(), 'call_plans.read_team')
      AND employee_id IN (
        SELECT id
        FROM hr_employees
        WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
      )
    )
    OR check_permission(auth.uid(), 'call_plans.read_all')
  );

DROP POLICY IF EXISTS cp_insert ON public.call_plans;
CREATE POLICY cp_insert ON public.call_plans
  FOR INSERT
  WITH CHECK (
    check_permission(auth.uid(), 'call_plans.create')
    AND (
      employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
      OR (
        check_permission(auth.uid(), 'call_plans.read_team')
        AND employee_id IN (
          SELECT id
          FROM hr_employees
          WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
        )
      )
      OR check_permission(auth.uid(), 'call_plans.read_all')
    )
  );

DROP POLICY IF EXISTS cp_update ON public.call_plans;
CREATE POLICY cp_update ON public.call_plans
  FOR UPDATE
  USING (
    (
      check_permission(auth.uid(), 'call_plans.create')
      AND employee_id IN (
        SELECT id
        FROM hr_employees
        WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
      )
    )
    OR (
      check_permission(auth.uid(), 'call_plans.confirm')
      AND employee_id IN (
        SELECT id
        FROM hr_employees
        WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
      )
    )
    OR (
      check_permission(auth.uid(), 'call_plans.cancel')
      AND employee_id IN (
        SELECT id
        FROM hr_employees
        WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
      )
    )
    OR check_permission(auth.uid(), 'call_plans.read_all')
  )
  WITH CHECK (
    (
      check_permission(auth.uid(), 'call_plans.create')
      AND employee_id IN (
        SELECT id
        FROM hr_employees
        WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
      )
    )
    OR (
      check_permission(auth.uid(), 'call_plans.confirm')
      AND employee_id IN (
        SELECT id
        FROM hr_employees
        WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
      )
    )
    OR (
      check_permission(auth.uid(), 'call_plans.cancel')
      AND employee_id IN (
        SELECT id
        FROM hr_employees
        WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
      )
    )
    OR check_permission(auth.uid(), 'call_plans.read_all')
  );

DROP POLICY IF EXISTS cpi_read ON public.call_plan_items;
CREATE POLICY cpi_read ON public.call_plan_items
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.call_plans cp
      WHERE cp.id = plan_id
        AND (
          cp.employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
          OR (
            check_permission(auth.uid(), 'call_plans.read_team')
            AND cp.employee_id IN (
              SELECT id
              FROM hr_employees
              WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
            )
          )
          OR check_permission(auth.uid(), 'call_plans.read_all')
        )
    )
  );

DROP POLICY IF EXISTS cpi_insert ON public.call_plan_items;
CREATE POLICY cpi_insert ON public.call_plan_items
  FOR INSERT
  WITH CHECK (
    check_permission(auth.uid(), 'call_plans.create')
    AND EXISTS (
      SELECT 1
      FROM public.call_plans cp
      WHERE cp.id = plan_id
        AND (
          cp.employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
          OR (
            check_permission(auth.uid(), 'call_plans.read_team')
            AND cp.employee_id IN (
              SELECT id
              FROM hr_employees
              WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
            )
          )
          OR check_permission(auth.uid(), 'call_plans.read_all')
        )
    )
  );

DROP POLICY IF EXISTS cpi_update ON public.call_plan_items;
CREATE POLICY cpi_update ON public.call_plan_items
  FOR UPDATE
  USING (
    (
      check_permission(auth.uid(), 'call_plans.create')
      AND EXISTS (
        SELECT 1
        FROM public.call_plans cp
        WHERE cp.id = plan_id
          AND cp.employee_id IN (
            SELECT id
            FROM hr_employees
            WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
          )
      )
    )
    OR (
      check_permission(auth.uid(), 'call_plans.confirm')
      AND EXISTS (
        SELECT 1
        FROM public.call_plans cp
        WHERE cp.id = plan_id
          AND cp.employee_id IN (
            SELECT id
            FROM hr_employees
            WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
          )
      )
    )
    OR (
      check_permission(auth.uid(), 'call_plans.cancel')
      AND EXISTS (
        SELECT 1
        FROM public.call_plans cp
        WHERE cp.id = plan_id
          AND cp.employee_id IN (
            SELECT id
            FROM hr_employees
            WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
          )
      )
    )
    OR check_permission(auth.uid(), 'call_plans.read_all')
  )
  WITH CHECK (
    (
      check_permission(auth.uid(), 'call_plans.create')
      AND EXISTS (
        SELECT 1
        FROM public.call_plans cp
        WHERE cp.id = plan_id
          AND cp.employee_id IN (
            SELECT id
            FROM hr_employees
            WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
          )
      )
    )
    OR (
      check_permission(auth.uid(), 'call_plans.confirm')
      AND EXISTS (
        SELECT 1
        FROM public.call_plans cp
        WHERE cp.id = plan_id
          AND cp.employee_id IN (
            SELECT id
            FROM hr_employees
            WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
          )
      )
    )
    OR (
      check_permission(auth.uid(), 'call_plans.cancel')
      AND EXISTS (
        SELECT 1
        FROM public.call_plans cp
        WHERE cp.id = plan_id
          AND cp.employee_id IN (
            SELECT id
            FROM hr_employees
            WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
          )
      )
    )
    OR check_permission(auth.uid(), 'call_plans.read_all')
  );

DROP POLICY IF EXISTS acts_read ON public.activities;
CREATE POLICY acts_read ON public.activities
  FOR SELECT
  USING (
    employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    OR (
      check_permission(auth.uid(), 'activities.read_team')
      AND employee_id IN (
        SELECT id
        FROM hr_employees
        WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
      )
    )
    OR check_permission(auth.uid(), 'activities.read_all')
  );

DROP POLICY IF EXISTS acts_insert ON public.activities;
CREATE POLICY acts_insert ON public.activities
  FOR INSERT
  WITH CHECK (
    check_permission(auth.uid(), 'activities.create')
    AND employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    AND created_by = auth.uid()
  );

DROP POLICY IF EXISTS acts_update ON public.activities;
CREATE POLICY acts_update ON public.activities
  FOR UPDATE
  USING (
    (
      employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
      AND check_permission(auth.uid(), 'activities.update_own')
      AND created_at > now() - INTERVAL '24 hours'
    )
    OR check_permission(auth.uid(), 'activities.read_all')
  )
  WITH CHECK (
    (
      employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
      AND check_permission(auth.uid(), 'activities.update_own')
      AND created_by = auth.uid()
    )
    OR check_permission(auth.uid(), 'activities.read_all')
  );

DROP POLICY IF EXISTS cd_read ON public.call_details;
CREATE POLICY cd_read ON public.call_details
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.activities a
      WHERE a.id = activity_id
        AND (
          a.employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
          OR (
            check_permission(auth.uid(), 'activities.read_team')
            AND a.employee_id IN (
              SELECT id
              FROM hr_employees
              WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
            )
          )
          OR check_permission(auth.uid(), 'activities.read_all')
        )
    )
  );

DROP POLICY IF EXISTS cd_insert ON public.call_details;
CREATE POLICY cd_insert ON public.call_details
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.activities a
      WHERE a.id = activity_id
        AND a.employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
        AND check_permission(auth.uid(), 'activities.create')
    )
  );

DROP POLICY IF EXISTS cd_update ON public.call_details;
CREATE POLICY cd_update ON public.call_details
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.activities a
      WHERE a.id = activity_id
        AND (
          (
            a.employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
            AND check_permission(auth.uid(), 'activities.update_own')
          )
          OR check_permission(auth.uid(), 'activities.read_all')
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.activities a
      WHERE a.id = activity_id
        AND (
          (
            a.employee_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
            AND check_permission(auth.uid(), 'activities.update_own')
          )
          OR check_permission(auth.uid(), 'activities.read_all')
        )
    )
  );

DROP POLICY IF EXISTS tgt_read ON public.targets;
CREATE POLICY tgt_read ON public.targets
  FOR SELECT
  USING (
    (
      scope = 'individual'
      AND scope_id IN (SELECT id FROM hr_employees WHERE user_id = auth.uid())
    )
    OR (
      check_permission(auth.uid(), 'targets.read_team')
      AND (
        (scope = 'branch' AND scope_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid()))
        OR (
          scope = 'individual'
          AND scope_id IN (
            SELECT id
            FROM hr_employees
            WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
          )
        )
        OR (
          scope = 'department'
          AND scope_id IN (
            SELECT id
            FROM hr_departments
            WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
          )
        )
      )
    )
    OR check_permission(auth.uid(), 'targets.read_all')
  );

DROP POLICY IF EXISTS tgt_insert ON public.targets;
CREATE POLICY tgt_insert ON public.targets
  FOR INSERT
  WITH CHECK (
    check_permission(auth.uid(), 'targets.read_all')
    OR (
      (check_permission(auth.uid(), 'targets.create') OR check_permission(auth.uid(), 'targets.assign'))
      AND (
        (scope = 'individual' AND scope_id IN (
          SELECT id
          FROM hr_employees
          WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
        ))
        OR (scope = 'branch' AND scope_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid()))
        OR (scope = 'department' AND scope_id IN (
          SELECT id
          FROM hr_departments
          WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
        ))
      )
    )
  );

DROP POLICY IF EXISTS tgt_update ON public.targets;
CREATE POLICY tgt_update ON public.targets
  FOR UPDATE
  USING (
    check_permission(auth.uid(), 'targets.read_all')
    OR (
      (check_permission(auth.uid(), 'targets.update') OR check_permission(auth.uid(), 'targets.assign'))
      AND (
        (scope = 'individual' AND scope_id IN (
          SELECT id
          FROM hr_employees
          WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
        ))
        OR (scope = 'branch' AND scope_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid()))
        OR (scope = 'department' AND scope_id IN (
          SELECT id
          FROM hr_departments
          WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
        ))
      )
    )
  )
  WITH CHECK (
    check_permission(auth.uid(), 'targets.read_all')
    OR (
      (check_permission(auth.uid(), 'targets.update') OR check_permission(auth.uid(), 'targets.assign'))
      AND (
        (scope = 'individual' AND scope_id IN (
          SELECT id
          FROM hr_employees
          WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
        ))
        OR (scope = 'branch' AND scope_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid()))
        OR (scope = 'department' AND scope_id IN (
          SELECT id
          FROM hr_departments
          WHERE branch_id = (SELECT branch_id FROM hr_employees WHERE user_id = auth.uid())
        ))
      )
    )
  );

DROP POLICY IF EXISTS tp_read ON public.target_progress;
CREATE POLICY tp_read ON public.target_progress
  FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.targets t WHERE t.id = target_id)
  );

DROP POLICY IF EXISTS ta_read ON public.target_adjustments;
CREATE POLICY ta_read ON public.target_adjustments
  FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.targets t WHERE t.id = target_id)
  );

-- =============================================================================
-- 9) Views آمنة
-- =============================================================================

DROP VIEW IF EXISTS public.v_plan_daily_summary;
CREATE VIEW public.v_plan_daily_summary
WITH (security_invoker = true)
AS
SELECT
  'visit'::TEXT AS plan_module,
  vp.id,
  vp.employee_id,
  vp.plan_date,
  vp.status AS plan_status,
  vp.total_customers AS total_items,
  vp.completed_count,
  vp.skipped_count,
  vp.missed_count,
  vp.completion_pct,
  COUNT(vpi.id) FILTER (WHERE vpi.status = 'pending') AS pending_count,
  COUNT(vpi.id) FILTER (WHERE vpi.priority = 'high' AND vpi.status = 'pending') AS high_priority_pending
FROM public.visit_plans vp
LEFT JOIN public.visit_plan_items vpi
  ON vpi.plan_id = vp.id
GROUP BY vp.id

UNION ALL

SELECT
  'call'::TEXT AS plan_module,
  cp.id,
  cp.employee_id,
  cp.plan_date,
  cp.status AS plan_status,
  cp.total_calls AS total_items,
  cp.completed_count,
  cp.skipped_count,
  cp.missed_count,
  cp.completion_pct,
  COUNT(cpi.id) FILTER (WHERE cpi.status = 'pending') AS pending_count,
  COUNT(cpi.id) FILTER (WHERE cpi.priority = 'high' AND cpi.status = 'pending') AS high_priority_pending
FROM public.call_plans cp
LEFT JOIN public.call_plan_items cpi
  ON cpi.plan_id = cp.id
GROUP BY cp.id;

DROP VIEW IF EXISTS public.v_target_status;
CREATE VIEW public.v_target_status
WITH (security_invoker = true)
AS
SELECT
  t.id,
  t.name,
  t.type_code,
  t.scope,
  t.scope_id,
  t.period_start,
  t.period_end,
  t.target_value,
  t.min_value,
  t.stretch_value,
  t.is_active,
  t.is_paused,
  tp.achieved_value,
  tp.achievement_pct,
  tp.trend,
  tp.last_calc_at,
  (t.target_value - COALESCE(tp.achieved_value, 0)) AS remaining_value,
  (t.period_end - CURRENT_DATE) AS days_remaining
FROM public.targets t
LEFT JOIN LATERAL (
  SELECT *
  FROM public.target_progress tp
  WHERE tp.target_id = t.id
  ORDER BY tp.snapshot_date DESC
  LIMIT 1
) tp ON true
WHERE t.is_active = true;

DROP VIEW IF EXISTS public.v_rep_performance;
CREATE VIEW public.v_rep_performance
WITH (security_invoker = true)
AS
WITH activity_monthly AS (
  SELECT
    he.id AS employee_id,
    DATE_TRUNC('month', a.activity_date)::DATE AS period_month,
    COUNT(a.id) FILTER (WHERE at_.category = 'visit') AS visits_count,
    COUNT(a.id) FILTER (WHERE at_.category = 'call') AS calls_count,
    COUNT(a.id) FILTER (WHERE a.outcome_type IN ('order_placed', 'agreed_order')) AS orders_from_activities,
    COUNT(DISTINCT a.customer_id) FILTER (WHERE a.outcome_type IN ('order_placed', 'agreed_order')) AS active_customers
  FROM hr_employees he
  LEFT JOIN public.activities a
    ON a.employee_id = he.id
   AND a.deleted_at IS NULL
  LEFT JOIN public.activity_types at_
    ON at_.id = a.type_id
  WHERE he.status = 'active'
  GROUP BY he.id, DATE_TRUNC('month', a.activity_date)::DATE
),
sales_monthly AS (
  SELECT
    he.id AS employee_id,
    DATE_TRUNC('month', so.delivered_at)::DATE AS period_month,
    SUM(so.total_amount) AS sales_value
  FROM hr_employees he
  JOIN sales_orders so
    ON so.rep_id = he.user_id
   AND so.status IN ('delivered', 'completed')
   AND so.delivered_at IS NOT NULL
  WHERE he.status = 'active'
  GROUP BY he.id, DATE_TRUNC('month', so.delivered_at)::DATE
),
collections_monthly AS (
  SELECT
    he.id AS employee_id,
    DATE_TRUNC('month', pr.created_at)::DATE AS period_month,
    SUM(pr.amount) FILTER (WHERE pr.status = 'confirmed') AS collection_value
  FROM hr_employees he
  JOIN payment_receipts pr
    ON pr.collected_by = he.user_id
  WHERE he.status = 'active'
  GROUP BY he.id, DATE_TRUNC('month', pr.created_at)::DATE
),
periods AS (
  SELECT employee_id, period_month FROM activity_monthly WHERE period_month IS NOT NULL
  UNION
  SELECT employee_id, period_month FROM sales_monthly WHERE period_month IS NOT NULL
  UNION
  SELECT employee_id, period_month FROM collections_monthly WHERE period_month IS NOT NULL
)
SELECT
  he.id AS employee_id,
  he.full_name AS employee_name,
  b.id AS branch_id,
  b.name AS branch_name,
  p.period_month AS period,
  COALESCE(am.visits_count, 0) AS visits_count,
  COALESCE(am.calls_count, 0) AS calls_count,
  COALESCE(am.orders_from_activities, 0) AS orders_from_activities,
  COALESCE(sm.sales_value, 0) AS sales_value,
  COALESCE(cm.collection_value, 0) AS collection_value,
  COALESCE(am.active_customers, 0) AS active_customers
FROM periods p
JOIN hr_employees he
  ON he.id = p.employee_id
LEFT JOIN branches b
  ON b.id = he.branch_id
LEFT JOIN activity_monthly am
  ON am.employee_id = p.employee_id
 AND am.period_month = p.period_month
LEFT JOIN sales_monthly sm
  ON sm.employee_id = p.employee_id
 AND sm.period_month = p.period_month
LEFT JOIN collections_monthly cm
  ON cm.employee_id = p.employee_id
 AND cm.period_month = p.period_month
WHERE he.status = 'active';

-- =============================================================================
-- 10) Seed Data
-- =============================================================================

INSERT INTO public.activity_types (
  name,
  code,
  category,
  requires_gps,
  requires_customer,
  requires_outcome,
  default_duration_min,
  sort_order
) VALUES
  ('زيارة مخططة',           'visit_planned',        'visit', true,  true,  true, 45, 10),
  ('زيارة مفاجئة',           'visit_unplanned',      'visit', true,  true,  true, 30, 20),
  ('زيارة استكشافية',        'visit_exploratory',    'visit', true,  false, true, 60, 30),
  ('زيارة تحصيل',           'visit_collection',     'visit', true,  true,  true, 20, 40),
  ('زيارة ترويج',            'visit_promo',          'visit', true,  true,  true, 30, 50),
  ('مكالمة مبيعات صادرة',   'call_out_sales',       'call',  false, true,  true, 10, 60),
  ('مكالمة تحصيل صادرة',    'call_out_collect',     'call',  false, true,  true, 10, 70),
  ('مكالمة متابعة صادرة',   'call_out_followup',    'call',  false, true,  true, 5,  80),
  ('مكالمة واردة',           'call_inbound',         'call',  false, true,  true, 15, 90),
  ('مكالمة تنشيط صادرة',    'call_out_activation',  'call',  false, true,  true, 10, 100),
  ('مهمة متابعة',           'task_followup',        'task',  false, false, true, 15, 110)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  category = EXCLUDED.category,
  requires_gps = EXCLUDED.requires_gps,
  requires_customer = EXCLUDED.requires_customer,
  requires_outcome = EXCLUDED.requires_outcome,
  default_duration_min = EXCLUDED.default_duration_min,
  sort_order = EXCLUDED.sort_order,
  is_active = true;

INSERT INTO public.target_types (
  name,
  code,
  unit,
  category,
  auto_source,
  auto_calc_enabled,
  description
) VALUES
  ('مبيعات مالية',    'sales_value',     'currency', 'financial', 'sales_orders',     true,  'إجمالي المبيعات المسلّمة أو المكتملة'),
  ('تحصيلات',        'collection',      'currency', 'financial', 'payment_receipts', true,  'إجمالي سندات القبض المؤكدة'),
  ('كميات منتج',     'product_qty',     'quantity', 'product',   'sales_orders',     true,  'إجمالي الكمية الأساسية لمنتج/فئة'),
  ('عدد زيارات',     'visits_count',    'count',    'activity',  'activities',       true,  'عدد الأنشطة المصنفة زيارات'),
  ('عدد مكالمات',    'calls_count',     'count',    'activity',  'activities',       true,  'عدد الأنشطة المصنفة مكالمات'),
  ('عملاء جدد',      'new_customers',   'count',    'customer',  'customers',        true,  'العملاء المضافون خلال الفترة'),
  ('تنشيط خاملين',   'reactivation',    'count',    'customer',  'activities',       true,  'عملاء عادوا للنشاط بعد فترة خمول'),
  ('رفع قيمة عميل',  'upgrade_value',   'currency', 'customer',  'manual',           false, 'يُفعّل في مرحلة لاحقة أو عبر manual calc'),
  ('توسيع تصنيفات',  'category_spread', 'count',    'product',   'manual',           false, 'يُفعّل في مرحلة لاحقة أو عبر manual calc')
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  unit = EXCLUDED.unit,
  category = EXCLUDED.category,
  auto_source = EXCLUDED.auto_source,
  auto_calc_enabled = EXCLUDED.auto_calc_enabled,
  description = EXCLUDED.description,
  is_active = true;

-- =============================================================================
-- 11) ملاحظات تشغيلية
-- =============================================================================
-- لتفعيل إعادة حساب الأهداف في Supabase Dashboard:
--   SELECT cron.schedule(
--     'recalc-targets-every-5m',
--     '*/5 * * * *',
--     'SELECT public.recalculate_all_active_targets(CURRENT_DATE);'
--   );
--
-- ملاحظة: لا يتم تفعيل pg_cron من الـ migration تلقائياً لأن المشروع الحالي
-- يتبع نمط إعداد الجدولة من Dashboard كما هو مستخدم في موديولات HR.

COMMIT;
