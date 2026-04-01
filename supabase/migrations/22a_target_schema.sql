-- ============================================================
-- 22a_target_schema.sql
-- EDARA v2 — محرك الأهداف الموحَّد: Schema والجداول
-- Non-Breaking: كل التعديلات nullable أو DEFAULT آمن
-- Idempotent: آمن للتشغيل أكثر من مرة
-- ============================================================
-- الاعتماديات: 21_activities_module_mvp.sql، 19_hr_payroll_loans.sql، 03_financial_infrastructure.sql
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- SECTION 1: توسيع جدول targets بحقول المكافأة
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.targets
  ADD COLUMN IF NOT EXISTS reward_type
    TEXT CHECK (reward_type IN ('fixed', 'percentage')),       -- NULL = بدون مكافأة
  ADD COLUMN IF NOT EXISTS reward_base_value  NUMERIC(14,2),  -- fixed: المبلغ الكامل | percentage: نسبة %
  ADD COLUMN IF NOT EXISTS reward_pool_basis
    TEXT CHECK (reward_pool_basis IN ('sales_value', 'collection_value')),
  ADD COLUMN IF NOT EXISTS auto_payout        BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS payout_month_offset INTEGER NOT NULL DEFAULT 0;

-- ── CHECK Constraints على targets (تُضاف بأمان) ──────────

-- 1. reward_base_value إلزامية وموجبة إذا كانت reward_type مُحددة
ALTER TABLE public.targets
  DROP CONSTRAINT IF EXISTS chk_reward_base_value_positive;
ALTER TABLE public.targets
  ADD CONSTRAINT chk_reward_base_value_positive CHECK (
    reward_type IS NULL
    OR (reward_base_value IS NOT NULL AND reward_base_value > 0)
  );

-- 2. auto_payout يتطلب مكافأة مُعرَّفة (الشرائح يتحقق منها runtime)
ALTER TABLE public.targets
  DROP CONSTRAINT IF EXISTS chk_auto_payout_requires_reward;
ALTER TABLE public.targets
  ADD CONSTRAINT chk_auto_payout_requires_reward CHECK (
    auto_payout = false
    OR (reward_type IS NOT NULL AND reward_base_value IS NOT NULL AND reward_base_value > 0)
  );

-- 3. pool_basis لا معنى لها مع fixed (يُشترط وجودها مع percentage فقط)
ALTER TABLE public.targets
  DROP CONSTRAINT IF EXISTS chk_pool_basis_requires_percentage;
ALTER TABLE public.targets
  ADD CONSTRAINT chk_pool_basis_requires_percentage CHECK (
    reward_pool_basis IS NULL OR reward_type = 'percentage'
  );

-- ════════════════════════════════════════════════════════════
-- SECTION 2: جدول شرائح المكافأة المتدرجة
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.target_reward_tiers (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  target_id      UUID NOT NULL REFERENCES public.targets(id) ON DELETE CASCADE,
  sequence       INTEGER NOT NULL CHECK (sequence > 0),
  threshold_pct  NUMERIC(6,2) NOT NULL
                 CHECK (threshold_pct > 0 AND threshold_pct <= 200),  -- نسبة الإنجاز المطلوبة
  reward_pct     NUMERIC(6,2) NOT NULL
                 CHECK (reward_pct > 0 AND reward_pct <= 200),        -- نسبة ما يُصرف من المكافأة
  label          TEXT,                                                 -- مثال: 'ممتاز', 'جيد جداً'
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (target_id, sequence),
  UNIQUE (target_id, threshold_pct)
);

DROP TRIGGER IF EXISTS trg_tiers_target_exists ON public.target_reward_tiers;

CREATE INDEX IF NOT EXISTS idx_trt_target
  ON public.target_reward_tiers(target_id, threshold_pct DESC);

-- ════════════════════════════════════════════════════════════
-- SECTION 3: جدول العملاء المستهدفين (للأهداف المتقدمة)
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.target_customers (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  target_id                UUID NOT NULL REFERENCES public.targets(id) ON DELETE CASCADE,
  customer_id              UUID NOT NULL REFERENCES customers(id),
  baseline_value           NUMERIC(14,2),       -- للـ upgrade_value: متوسط مشتريات الفترة المرجعية
  baseline_category_count  INTEGER,              -- للـ category_spread: عدد التصنيفات المرجعي
  baseline_period_start    DATE,
  baseline_period_end      DATE,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (target_id, customer_id)
);

CREATE INDEX IF NOT EXISTS idx_tc_target
  ON public.target_customers(target_id);

CREATE INDEX IF NOT EXISTS idx_tc_customer
  ON public.target_customers(customer_id);

-- ════════════════════════════════════════════════════════════
-- SECTION 4: جدول استحقاقات المكافأة (الجسر الفاصل)
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.target_reward_payouts (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  target_id        UUID NOT NULL REFERENCES public.targets(id),
  employee_id      UUID NOT NULL REFERENCES hr_employees(id),
  period_id        UUID NOT NULL REFERENCES hr_payroll_periods(id),

  -- حالة الإنجاز عند التثبيت
  achievement_pct  NUMERIC(6,2) NOT NULL CHECK (achievement_pct >= 0),
  tier_reached     INTEGER,                           -- رقم الشريحة المُحققة
  reward_pct       NUMERIC(6,2),                      -- نسبة المكافأة المُصرَّفة
  base_amount      NUMERIC(14,2),                     -- قيمة الـ pool المحسوبة

  -- المبلغ النهائي
  payout_amount    NUMERIC(14,2) NOT NULL CHECK (payout_amount >= 0),

  -- الحالة
  status           TEXT NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending', 'committed', 'cancelled')),

  -- الربط مع تعديلات الراتب
  adjustment_id    UUID REFERENCES hr_payroll_adjustments(id),

  -- التوثيق
  computed_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  committed_at     TIMESTAMPTZ,
  notes            TEXT,

  -- Idempotency: هدف واحد × موظف واحد × فترة واحدة
  UNIQUE (target_id, employee_id, period_id)
);

CREATE INDEX IF NOT EXISTS idx_trp_period
  ON public.target_reward_payouts(period_id, status);

CREATE INDEX IF NOT EXISTS idx_trp_employee
  ON public.target_reward_payouts(employee_id, period_id);

CREATE INDEX IF NOT EXISTS idx_trp_target
  ON public.target_reward_payouts(target_id, status);

-- ════════════════════════════════════════════════════════════
-- SECTION 5: حساب محاسبي جديد (5335 — مكافآت أهداف الموظفين)
-- ════════════════════════════════════════════════════════════

INSERT INTO public.chart_of_accounts (code, name, name_en, type, sort_order)
VALUES (
  '5335',
  'مكافآت أهداف الموظفين',
  'Employee Target Bonuses',
  'expense',
  46
)
ON CONFLICT (code) DO NOTHING;

-- ربط بالحساب الأب (5000 مصروفات)
UPDATE public.chart_of_accounts
SET parent_id = (SELECT id FROM public.chart_of_accounts WHERE code = '5000' LIMIT 1)
WHERE code = '5335' AND parent_id IS NULL;

-- ════════════════════════════════════════════════════════════
-- SECTION 6: دالة التحقق من اتساق المكافأة ونوع الهدف
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.is_valid_reward_config(
  p_type_category TEXT,
  p_type_code     TEXT,
  p_reward_type   TEXT,
  p_pool_basis    TEXT
) RETURNS BOOLEAN
  LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
  -- بدون مكافأة = صحيح دائماً
  IF p_reward_type IS NULL THEN
    RETURN (p_pool_basis IS NULL);  -- pool_basis لا معنى لها بدون reward_type
  END IF;

  -- percentage: مسموح فقط للأهداف المالية وupgrade_value
  IF p_reward_type = 'percentage' THEN
    IF p_type_category NOT IN ('financial') AND p_type_code != 'upgrade_value' THEN
      RETURN FALSE;  -- العددية/النشاطية/توسيع التصنيفات: fixed فقط
    END IF;

    -- pool_basis إلزامي مع percentage
    IF p_pool_basis IS NULL THEN
      RETURN FALSE;
    END IF;

    -- ★ upgrade_value + percentage: sales_value فقط (قرار نهائي)
    IF p_type_code = 'upgrade_value' AND p_pool_basis != 'sales_value' THEN
      RETURN FALSE;  -- يمنع: upgrade_value + percentage + collection_value
    END IF;

    -- collection type: collection_value فقط
    IF p_type_code = 'collection' AND p_pool_basis != 'collection_value' THEN
      RETURN FALSE;
    END IF;

    -- collection_value: مسموح فقط مع collection type
    IF p_pool_basis = 'collection_value' AND p_type_code != 'collection' THEN
      RETURN FALSE;
    END IF;
  END IF;

  -- pool_basis بدون percentage = خطأ (يجب أن يكون NULL مع fixed)
  IF p_reward_type = 'fixed' AND p_pool_basis IS NOT NULL THEN
    RETURN FALSE;
  END IF;

  RETURN TRUE;
END; $$;

-- ════════════════════════════════════════════════════════════
-- SECTION 7: Trigger — التحقق من اتساق المكافأة عند الإنشاء/التعديل
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trg_validate_target_reward_fn()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_category TEXT;
  v_code     TEXT;
BEGIN
  -- لا مكافأة = لا تحقق
  IF NEW.reward_type IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT tt.category, tt.code INTO v_category, v_code
  FROM public.target_types tt WHERE tt.id = NEW.type_id;

  IF NOT public.is_valid_reward_config(v_category, v_code, NEW.reward_type, NEW.reward_pool_basis) THEN
    RAISE EXCEPTION
      '[EDARA] تركيبة المكافأة غير صالحة للهدف من نوع [%]: reward_type=%, pool_basis=%',
      v_code, NEW.reward_type, COALESCE(NEW.reward_pool_basis, 'NULL');
  END IF;

  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_validate_target_reward ON public.targets;
CREATE TRIGGER trg_validate_target_reward
  BEFORE INSERT OR UPDATE OF reward_type, reward_pool_basis, reward_base_value
  ON public.targets
  FOR EACH ROW EXECUTE FUNCTION public.trg_validate_target_reward_fn();

-- ════════════════════════════════════════════════════════════
-- SECTION 8: ★ Trigger — منع auto_payout=true في INSERT المباشر
-- (الحماية المزدوجة — يُغلق الثغرة التي أشار إليها كوديكس)
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trg_block_auto_payout_on_insert_fn()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.auto_payout = true THEN
    RAISE EXCEPTION
      '[EDARA] auto_payout=true غير مسموح عند الإنشاء المباشر. '
      'استخدم create_target_with_rewards() RPC لإنشاء الهدف مع شرائح المكافأة والصرف التلقائي.';
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_block_auto_payout_on_insert ON public.targets;
CREATE TRIGGER trg_block_auto_payout_on_insert
  BEFORE INSERT ON public.targets
  FOR EACH ROW EXECUTE FUNCTION public.trg_block_auto_payout_on_insert_fn();

-- ════════════════════════════════════════════════════════════
-- SECTION 9: Trigger — منع حذف آخر شريحة عند تفعيل auto_payout
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trg_prevent_last_tier_delete_fn()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_auto_payout BOOLEAN;
  v_remaining   INTEGER;
BEGIN
  SELECT auto_payout INTO v_auto_payout
  FROM public.targets WHERE id = OLD.target_id;

  IF v_auto_payout = true THEN
    SELECT COUNT(*) INTO v_remaining
    FROM public.target_reward_tiers
    WHERE target_id = OLD.target_id AND id != OLD.id;

    IF v_remaining = 0 THEN
      RAISE EXCEPTION
        '[EDARA] لا يمكن حذف آخر شريحة مكافأة — الهدف مُفعَّل للصرف التلقائي. '
        'أوقف auto_payout أولاً عبر adjust_target().';
    END IF;
  END IF;
  RETURN OLD;
END; $$;

DROP TRIGGER IF EXISTS trg_prevent_last_tier_delete ON public.target_reward_tiers;
CREATE TRIGGER trg_prevent_last_tier_delete
  BEFORE DELETE ON public.target_reward_tiers
  FOR EACH ROW EXECUTE FUNCTION public.trg_prevent_last_tier_delete_fn();

-- ════════════════════════════════════════════════════════════
-- SECTION 10: RLS — تأمين الجداول الثلاثة الجديدة
-- ════════════════════════════════════════════════════════════

-- تفعيل RLS
ALTER TABLE public.target_reward_tiers  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.target_customers     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.target_reward_payouts ENABLE ROW LEVEL SECURITY;

-- ── target_reward_tiers ──────────────────────────────────
-- القراءة: كل من يرى الهدف يرى شرائحه
DROP POLICY IF EXISTS "trt_read" ON public.target_reward_tiers;
CREATE POLICY "trt_read" ON public.target_reward_tiers FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.targets t
      WHERE t.id = target_id
        AND (
          t.assigned_by = auth.uid()
          OR (t.scope = 'individual' AND t.scope_id IN (
              SELECT id FROM hr_employees WHERE user_id = auth.uid()
            ))
          OR check_permission(auth.uid(), 'targets.read_all')
        )
    )
  );

-- الكتابة: من يملك targets.create
DROP POLICY IF EXISTS "trt_write" ON public.target_reward_tiers;
CREATE POLICY "trt_write" ON public.target_reward_tiers FOR ALL
  USING (
    check_permission(auth.uid(), 'targets.create')
    OR check_permission(auth.uid(), 'targets.read_all')
  );

-- ── target_customers ──────────────────────────────────────
DROP POLICY IF EXISTS "tc_read" ON public.target_customers;
CREATE POLICY "tc_read" ON public.target_customers FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.targets t
      WHERE t.id = target_id
        AND (
          t.assigned_by = auth.uid()
          OR (t.scope = 'individual' AND t.scope_id IN (
              SELECT id FROM hr_employees WHERE user_id = auth.uid()
            ))
          OR check_permission(auth.uid(), 'targets.read_all')
        )
    )
  );

DROP POLICY IF EXISTS "tc_write" ON public.target_customers;
CREATE POLICY "tc_write" ON public.target_customers FOR ALL
  USING (
    check_permission(auth.uid(), 'targets.create')
    OR check_permission(auth.uid(), 'targets.read_all')
  );

-- ── target_reward_payouts ────────────────────────────────
-- القراءة: الموظف يرى مكافآته / الإدارة ترى الكل
DROP POLICY IF EXISTS "trp_read" ON public.target_reward_payouts;
CREATE POLICY "trp_read" ON public.target_reward_payouts FOR SELECT
  USING (
    employee_id IN (
      SELECT id FROM hr_employees WHERE user_id = auth.uid()
    )
    OR check_permission(auth.uid(), 'targets.read_all')
    OR check_permission(auth.uid(), 'hr.payroll.read')
  );

-- الكتابة: SECURITY DEFINER فقط (RPC) — يُمنع الكتابة المباشرة
DROP POLICY IF EXISTS "trp_write" ON public.target_reward_payouts;
CREATE POLICY "trp_write" ON public.target_reward_payouts FOR ALL
  USING (false);  -- DENY ALL — الكتابة عبر prepare_target_reward_payouts() فقط

-- ════════════════════════════════════════════════════════════
-- SECTION 11: صلاحيات جديدة للأدوار
-- ════════════════════════════════════════════════════════════

-- targets.rewards.view: عرض مكافآت الأهداف
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm FROM roles r
CROSS JOIN (VALUES
  ('targets.rewards.view'),
  ('targets.rewards.configure')
) AS p(perm)
WHERE r.name IN ('super_admin', 'ceo', 'branch_manager')
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission)
SELECT r.id, 'targets.rewards.view' FROM roles r
WHERE r.name = 'sales_rep'
ON CONFLICT DO NOTHING;

-- ════════════════════════════════════════════════════════════
-- SECTION 12: تحديث target_adjustments للقبول بالحقول الجديدة
-- (يُعدَّل CHECK constraint لإضافة حقول المكافأة)
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.target_adjustments
  DROP CONSTRAINT IF EXISTS target_adjustments_field_changed_check;

ALTER TABLE public.target_adjustments
  ADD CONSTRAINT target_adjustments_field_changed_check
  CHECK (field_changed IN (
    -- الحقول الأصلية
    'target_value',
    'min_value',
    'stretch_value',
    'period_end',
    'is_paused',
    'is_active',
    'filter_criteria',
    -- الحقول الجديدة (طبقة أ — قابلة للتعديل دائماً قبل committed)
    'reward_base_value',
    'auto_payout',
    'payout_month_offset',
    -- الحقول الجديدة (طبقة ب — مقيَّدة بعد committed)
    'reward_type',
    'reward_pool_basis'
  ));

-- ════════════════════════════════════════════════════════════
-- نهاية 22a_target_schema.sql
-- الخطوة التالية: 22b_target_calc.sql
-- ════════════════════════════════════════════════════════════
