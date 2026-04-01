-- =============================================================================
-- 21d_visit_checklists.sql
-- نظام استبيانات الزيارات والمكالمات + صلاحيات جديدة لتعديل الخطط
--
-- يعتمد على:
--   - 21_activities_module_mvp.sql (activities, visit_plan_items, call_plan_items)
--   - 21b_activities_rls_engine.sql (check_permission, RLS engine)
--   - 01_auth_core.sql (profiles, roles, role_permissions)
--
-- المكونات:
--   1) صلاحيات جديدة (visit_plans.update, call_plans.update, checklists.manage)
--   2) جداول الاستبيانات (templates, questions, responses)
--   3) RLS policies
--   4) Triggers & Indexes
--   5) Seed data — استبيانات نموذجية
-- =============================================================================

BEGIN;

-- =============================================================================
-- 1) صلاحيات جديدة
-- =============================================================================

-- صلاحية تعديل خطة الزيارات (للمشرف والمدير)
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm
FROM roles r
CROSS JOIN (
  VALUES
    ('visit_plans.update'),
    ('call_plans.update'),
    ('checklists.manage')
) AS p(perm)
WHERE r.name IN ('sales_supervisor', 'branch_manager')
ON CONFLICT DO NOTHING;

-- CEO يحصل على نفس الصلاحيات
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm
FROM roles r
CROSS JOIN (
  VALUES
    ('visit_plans.update'),
    ('call_plans.update'),
    ('checklists.manage')
) AS p(perm)
WHERE r.name = 'ceo'
ON CONFLICT DO NOTHING;

-- المندوب: تعديل مسودة خطته فقط
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm
FROM roles r
CROSS JOIN (
  VALUES
    ('visit_plans.update_own'),
    ('call_plans.update_own')
) AS p(perm)
WHERE r.name = 'sales_rep'
ON CONFLICT DO NOTHING;

-- المشرف والمدير يحصلون أيضاً على update_own للتوافق
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, p.perm
FROM roles r
CROSS JOIN (
  VALUES
    ('visit_plans.update_own'),
    ('call_plans.update_own')
) AS p(perm)
WHERE r.name IN ('sales_supervisor', 'branch_manager', 'ceo')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 2) جداول الاستبيانات
-- =============================================================================

-- 2.1) قوالب الاستبيانات
-- كل قالب ينتمي لفئة (visit/call/task) وقد يرتبط بنوع غرض محدد
CREATE TABLE IF NOT EXISTS public.visit_checklist_templates (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          VARCHAR(200) NOT NULL,
  description   TEXT,
  category      VARCHAR(20) NOT NULL DEFAULT 'visit'
                CHECK (category IN ('visit', 'call', 'task')),
  -- ربط بنوع الغرض: إذا NULL يُطبق على كل الأغراض
  purpose_type  VARCHAR(50)
                CHECK (purpose_type IS NULL OR purpose_type IN (
                  'sales', 'collection', 'activation',
                  'promotion', 'followup', 'service'
                )),
  is_mandatory  BOOLEAN NOT NULL DEFAULT false,
  is_active     BOOLEAN NOT NULL DEFAULT true,
  sort_order    INTEGER NOT NULL DEFAULT 0,
  created_by    UUID NOT NULL REFERENCES profiles(id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_checklist_templates_updated_at ON public.visit_checklist_templates;
CREATE TRIGGER trg_checklist_templates_updated_at
  BEFORE UPDATE ON public.visit_checklist_templates
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_checklist_templates_category
  ON public.visit_checklist_templates(category, is_active);

CREATE INDEX IF NOT EXISTS idx_checklist_templates_purpose
  ON public.visit_checklist_templates(category, purpose_type)
  WHERE is_active = true;

-- 2.2) أسئلة الاستبيان
-- 7 أنواع أسئلة: text, number, yes_no, single_choice, multi_choice, rating, photo
CREATE TABLE IF NOT EXISTS public.visit_checklist_questions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id   UUID NOT NULL REFERENCES public.visit_checklist_templates(id) ON DELETE CASCADE,
  question_text TEXT NOT NULL,
  question_type VARCHAR(20) NOT NULL
                CHECK (question_type IN (
                  'text',           -- حقل نص حر
                  'number',         -- رقم (كمية، سعر، إلخ)
                  'yes_no',         -- نعم أو لا (toggle)
                  'single_choice',  -- اختيار واحد من قائمة
                  'multi_choice',   -- اختيار متعدد من قائمة
                  'rating',         -- تقييم (1-5 نجوم)
                  'photo'           -- التقاط صورة
                )),
  -- خيارات الاختيار (تُستخدم فقط مع single_choice و multi_choice)
  -- مثال: ["ممتاز", "جيد", "ضعيف"] أو [{"label": "نعم", "value": "yes"}]
  options       JSONB NOT NULL DEFAULT '[]'::jsonb,
  -- قيمة افتراضية (اختياري)
  default_value TEXT,
  -- نص المساعدة/التلميح (اختياري)
  hint_text     TEXT,
  -- الحد الأدنى والأقصى للأرقام (فقط مع question_type = 'number')
  min_value     NUMERIC,
  max_value     NUMERIC,
  is_required   BOOLEAN NOT NULL DEFAULT false,
  sort_order    INTEGER NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_checklist_questions_template
  ON public.visit_checklist_questions(template_id, sort_order);

-- 2.3) إجابات المندوب (مرتبطة بالنشاط)
-- كل إجابة ترتبط بنشاط + سؤال (UNIQUE)
CREATE TABLE IF NOT EXISTS public.visit_checklist_responses (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id   UUID NOT NULL REFERENCES public.activities(id) ON DELETE CASCADE,
  template_id   UUID NOT NULL REFERENCES public.visit_checklist_templates(id),
  question_id   UUID NOT NULL REFERENCES public.visit_checklist_questions(id),
  -- الإجابة النصية (text, number, yes_no, single_choice, rating)
  answer_value  TEXT,
  -- الإجابة المعقدة (multi_choice, photo URLs, بيانات إضافية)
  answer_json   JSONB,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (activity_id, question_id)
);

CREATE INDEX IF NOT EXISTS idx_checklist_responses_activity
  ON public.visit_checklist_responses(activity_id);

CREATE INDEX IF NOT EXISTS idx_checklist_responses_template
  ON public.visit_checklist_responses(template_id);

-- =============================================================================
-- 3) RLS Policies
-- =============================================================================

ALTER TABLE public.visit_checklist_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visit_checklist_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visit_checklist_responses ENABLE ROW LEVEL SECURITY;

-- 3.1) القوالب: قراءة لكل مصادق، كتابة لمن لديه checklists.manage
DROP POLICY IF EXISTS "checklist_templates_read" ON public.visit_checklist_templates;
CREATE POLICY "checklist_templates_read" ON public.visit_checklist_templates FOR SELECT
  USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "checklist_templates_write" ON public.visit_checklist_templates;
CREATE POLICY "checklist_templates_write" ON public.visit_checklist_templates FOR ALL
  USING (check_permission(auth.uid(), 'checklists.manage'));

-- 3.2) الأسئلة: قراءة لكل مصادق، كتابة لمن لديه checklists.manage
DROP POLICY IF EXISTS "checklist_questions_read" ON public.visit_checklist_questions;
CREATE POLICY "checklist_questions_read" ON public.visit_checklist_questions FOR SELECT
  USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "checklist_questions_write" ON public.visit_checklist_questions;
CREATE POLICY "checklist_questions_write" ON public.visit_checklist_questions FOR ALL
  USING (check_permission(auth.uid(), 'checklists.manage'));

-- 3.3) الإجابات: قراءة لمن لديه أنشطة، كتابة للمندوب (update_own) أو الفريق
DROP POLICY IF EXISTS "checklist_responses_read" ON public.visit_checklist_responses;
CREATE POLICY "checklist_responses_read" ON public.visit_checklist_responses FOR SELECT
  USING (
    check_permission(auth.uid(), 'activities.read_all')
    OR check_permission(auth.uid(), 'activities.read_team')
    OR (
      check_permission(auth.uid(), 'activities.update_own')
      AND activity_id IN (
        SELECT id FROM public.activities WHERE created_by = auth.uid()
      )
    )
  );

DROP POLICY IF EXISTS "checklist_responses_insert" ON public.visit_checklist_responses;
CREATE POLICY "checklist_responses_insert" ON public.visit_checklist_responses FOR INSERT
  WITH CHECK (
    check_permission(auth.uid(), 'activities.update_own')
    OR check_permission(auth.uid(), 'activities.read_team')
    OR check_permission(auth.uid(), 'activities.read_all')
  );

DROP POLICY IF EXISTS "checklist_responses_update" ON public.visit_checklist_responses;
CREATE POLICY "checklist_responses_update" ON public.visit_checklist_responses FOR UPDATE
  USING (
    check_permission(auth.uid(), 'activities.update_own')
    AND activity_id IN (
      SELECT id FROM public.activities WHERE created_by = auth.uid()
    )
  );

-- =============================================================================
-- 4) دالة مساعدة: جلب الاستبيانات المناسبة لغرض زيارة/مكالمة
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_applicable_checklists(
  p_category VARCHAR(20),
  p_purpose_type VARCHAR(50) DEFAULT NULL
) RETURNS SETOF public.visit_checklist_templates
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT t.*
  FROM public.visit_checklist_templates t
  WHERE t.is_active = true
    AND t.category = p_category
    AND (
      t.purpose_type IS NULL                   -- قالب عام لكل الأغراض
      OR t.purpose_type = p_purpose_type       -- قالب مخصص لهذا الغرض
    )
  ORDER BY t.sort_order, t.name;
$$;

-- =============================================================================
-- 5) Seed Data — استبيانات نموذجية
-- =============================================================================

DO $$
DECLARE
  v_admin_id UUID;
  v_template_sales UUID;
  v_template_collection UUID;
  v_template_general UUID;
  v_template_call UUID;
BEGIN
  -- جلب أول admin/CEO كمنشئ
  SELECT p.id INTO v_admin_id
  FROM profiles p
  JOIN user_roles ur ON ur.user_id = p.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.name IN ('super_admin', 'ceo')
  LIMIT 1;

  -- fallback: أول مستخدم
  IF v_admin_id IS NULL THEN
    SELECT id INTO v_admin_id FROM profiles LIMIT 1;
  END IF;

  -- لا نكمل إذا لا يوجد مستخدمين
  IF v_admin_id IS NULL THEN
    RETURN;
  END IF;

  -- ═══ استبيان المبيعات ═══
  INSERT INTO public.visit_checklist_templates (id, name, description, category, purpose_type, is_mandatory, sort_order, created_by)
  VALUES (gen_random_uuid(), 'أسئلة زيارة المبيعات', 'أسئلة أساسية عند زيارة العميل بغرض المبيعات', 'visit', 'sales', true, 1, v_admin_id)
  RETURNING id INTO v_template_sales;

  INSERT INTO public.visit_checklist_questions (template_id, question_text, question_type, options, is_required, sort_order) VALUES
    (v_template_sales, 'هل المنتجات متوفرة على الرفوف؟', 'yes_no', '[]', true, 1),
    (v_template_sales, 'مستوى المخزون لدى العميل', 'single_choice', '["مرتفع", "متوسط", "منخفض", "نفد"]'::jsonb, true, 2),
    (v_template_sales, 'هل يوجد طلب جديد؟', 'yes_no', '[]', true, 3),
    (v_template_sales, 'المنتجات المطلوبة أو الملاحظات', 'text', '[]', false, 4),
    (v_template_sales, 'تقييم عام لحالة العميل', 'rating', '[]', false, 5);

  -- ═══ استبيان التحصيل ═══
  INSERT INTO public.visit_checklist_templates (id, name, description, category, purpose_type, is_mandatory, sort_order, created_by)
  VALUES (gen_random_uuid(), 'أسئلة زيارة التحصيل', 'أسئلة عند زيارة العميل بغرض تحصيل المستحقات', 'visit', 'collection', true, 2, v_admin_id)
  RETURNING id INTO v_template_collection;

  INSERT INTO public.visit_checklist_questions (template_id, question_text, question_type, options, is_required, sort_order, hint_text) VALUES
    (v_template_collection, 'هل تم التحصيل؟', 'yes_no', '[]', true, 1, NULL),
    (v_template_collection, 'المبلغ المحصّل (ج.م)', 'number', '[]', false, 2, 'أدخل المبلغ الفعلي المحصل'),
    (v_template_collection, 'طريقة الدفع', 'single_choice', '["نقدي", "تحويل بنكي", "شيك", "إنستاباي", "محفظة إلكترونية"]'::jsonb, false, 3, NULL),
    (v_template_collection, 'سبب عدم التحصيل', 'single_choice', '["العميل غير متواجد", "ليس لديه سيولة حالياً", "نزاع على الفاتورة", "وعد بالدفع لاحقاً", "أخرى"]'::jsonb, false, 4, 'يُملأ فقط في حالة عدم التحصيل'),
    (v_template_collection, 'تاريخ وعد الدفع المتوقع', 'text', '[]', false, 5, 'مثال: خلال أسبوع / يوم 15 من الشهر القادم'),
    (v_template_collection, 'ملاحظات إضافية', 'text', '[]', false, 6, NULL);

  -- ═══ استبيان عام للزيارات ═══
  INSERT INTO public.visit_checklist_templates (id, name, description, category, purpose_type, is_mandatory, sort_order, created_by)
  VALUES (gen_random_uuid(), 'تقرير زيارة عام', 'أسئلة عامة تُطبق على كل أنواع الزيارات', 'visit', NULL, false, 10, v_admin_id)
  RETURNING id INTO v_template_general;

  INSERT INTO public.visit_checklist_questions (template_id, question_text, question_type, options, is_required, sort_order) VALUES
    (v_template_general, 'الحالة العامة للمحل/الشركة', 'single_choice', '["ممتاز", "جيد", "متوسط", "ضعيف", "مغلق"]'::jsonb, false, 1),
    (v_template_general, 'هل يوجد منتجات منافسة بارزة؟', 'yes_no', '[]', false, 2),
    (v_template_general, 'ملاحظات المندوب', 'text', '[]', false, 3);

  -- ═══ استبيان المكالمات ═══
  INSERT INTO public.visit_checklist_templates (id, name, description, category, purpose_type, is_mandatory, sort_order, created_by)
  VALUES (gen_random_uuid(), 'أسئلة المكالمة', 'أسئلة أساسية عند إجراء مكالمة مع العميل', 'call', NULL, false, 1, v_admin_id)
  RETURNING id INTO v_template_call;

  INSERT INTO public.visit_checklist_questions (template_id, question_text, question_type, options, is_required, sort_order) VALUES
    (v_template_call, 'نتيجة المكالمة', 'single_choice', '["رد وتم الاتفاق", "رد ويحتاج متابعة", "لم يرد", "الرقم مشغول", "رقم خاطئ"]'::jsonb, true, 1),
    (v_template_call, 'هل يحتاج زيارة ميدانية؟', 'yes_no', '[]', false, 2),
    (v_template_call, 'ملخص المكالمة', 'text', '[]', false, 3);

END;
$$;

COMMIT;
