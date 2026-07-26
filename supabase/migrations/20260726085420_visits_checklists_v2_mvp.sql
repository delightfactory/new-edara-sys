-- Visits checklists V2 MVP
-- Scope: harden checklist lookup, preserve historical wording, add real dates,
--        expose lightweight version metadata, and replace the legacy visit
--        templates with short purpose-focused templates.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Lightweight version metadata (no new survey engine or reporting tables)
-- ---------------------------------------------------------------------------

ALTER TABLE public.visit_checklist_templates
  ADD COLUMN IF NOT EXISTS template_code TEXT,
  ADD COLUMN IF NOT EXISTS version INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS estimated_minutes SMALLINT NOT NULL DEFAULT 3;

UPDATE public.visit_checklist_templates
SET template_code = 'legacy.' || id::TEXT
WHERE template_code IS NULL;

ALTER TABLE public.visit_checklist_templates
  ALTER COLUMN template_code SET DEFAULT ('custom.' || gen_random_uuid()::TEXT),
  ALTER COLUMN template_code SET NOT NULL;

ALTER TABLE public.visit_checklist_templates
  DROP CONSTRAINT IF EXISTS visit_checklist_templates_version_check,
  ADD CONSTRAINT visit_checklist_templates_version_check CHECK (version > 0),
  DROP CONSTRAINT IF EXISTS visit_checklist_templates_estimated_minutes_check,
  ADD CONSTRAINT visit_checklist_templates_estimated_minutes_check
    CHECK (estimated_minutes BETWEEN 1 AND 30);

CREATE UNIQUE INDEX IF NOT EXISTS uq_visit_checklist_template_code
  ON public.visit_checklist_templates(template_code);

ALTER TABLE public.visit_checklist_questions
  ADD COLUMN IF NOT EXISTS question_code TEXT;

UPDATE public.visit_checklist_questions
SET question_code = 'legacy.' || id::TEXT
WHERE question_code IS NULL;

ALTER TABLE public.visit_checklist_questions
  ALTER COLUMN question_code SET DEFAULT ('custom.' || gen_random_uuid()::TEXT),
  ALTER COLUMN question_code SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_visit_checklist_question_code_per_template
  ON public.visit_checklist_questions(template_id, question_code);

-- Add a real date type while retaining every existing question type.
ALTER TABLE public.visit_checklist_questions
  DROP CONSTRAINT IF EXISTS visit_checklist_questions_question_type_check;

ALTER TABLE public.visit_checklist_questions
  ADD CONSTRAINT visit_checklist_questions_question_type_check
  CHECK (question_type IN (
    'text', 'number', 'yes_no', 'single_choice',
    'multi_choice', 'rating', 'photo', 'date'
  ));

-- ---------------------------------------------------------------------------
-- 2) Immutable response snapshots for reliable historical reporting
-- ---------------------------------------------------------------------------

ALTER TABLE public.visit_checklist_responses
  ADD COLUMN IF NOT EXISTS template_code_snapshot TEXT,
  ADD COLUMN IF NOT EXISTS template_name_snapshot TEXT,
  ADD COLUMN IF NOT EXISTS template_version_snapshot INTEGER,
  ADD COLUMN IF NOT EXISTS question_code_snapshot TEXT,
  ADD COLUMN IF NOT EXISTS question_text_snapshot TEXT,
  ADD COLUMN IF NOT EXISTS question_type_snapshot VARCHAR(20),
  ADD COLUMN IF NOT EXISTS options_snapshot JSONB;

UPDATE public.visit_checklist_responses r
SET template_code_snapshot = t.template_code,
    template_name_snapshot = t.name,
    template_version_snapshot = t.version,
    question_code_snapshot = q.question_code,
    question_text_snapshot = q.question_text,
    question_type_snapshot = q.question_type,
    options_snapshot = q.options
FROM public.visit_checklist_templates t,
     public.visit_checklist_questions q
WHERE r.template_id = t.id
  AND r.question_id = q.id
  AND q.template_id = t.id
  AND r.template_code_snapshot IS NULL;

CREATE OR REPLACE FUNCTION public.snapshot_and_validate_visit_checklist_response()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
DECLARE
  v_template public.visit_checklist_templates%ROWTYPE;
  v_question public.visit_checklist_questions%ROWTYPE;
BEGIN
  SELECT * INTO v_template
  FROM public.visit_checklist_templates
  WHERE id = NEW.template_id;

  SELECT * INTO v_question
  FROM public.visit_checklist_questions
  WHERE id = NEW.question_id
    AND template_id = NEW.template_id;

  IF v_template.id IS NULL OR v_question.id IS NULL THEN
    RAISE EXCEPTION 'السؤال أو القالب غير موجود أو غير متطابق';
  END IF;

  IF v_question.question_type = 'date' THEN
    IF NEW.answer_json IS NOT NULL
       OR NEW.answer_value IS NULL
       OR NEW.answer_value !~ '^\\d{4}-\\d{2}-\\d{2}$' THEN
      RAISE EXCEPTION 'إجابة التاريخ يجب أن تكون بصيغة YYYY-MM-DD';
    END IF;

    BEGIN
      IF (NEW.answer_value::DATE)::TEXT IS DISTINCT FROM NEW.answer_value THEN
        RAISE EXCEPTION 'إجابة التاريخ غير صالحة';
      END IF;
    EXCEPTION WHEN datetime_field_overflow OR invalid_datetime_format THEN
      RAISE EXCEPTION 'إجابة التاريخ غير صالحة';
    END;
  END IF;

  -- Always derive snapshots server-side; never trust client-provided history.
  NEW.template_code_snapshot := v_template.template_code;
  NEW.template_name_snapshot := v_template.name;
  NEW.template_version_snapshot := v_template.version;
  NEW.question_code_snapshot := v_question.question_code;
  NEW.question_text_snapshot := v_question.question_text;
  NEW.question_type_snapshot := v_question.question_type;
  NEW.options_snapshot := v_question.options;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_snapshot_validate_visit_checklist_response
  ON public.visit_checklist_responses;
CREATE TRIGGER trg_snapshot_validate_visit_checklist_response
  BEFORE INSERT OR UPDATE ON public.visit_checklist_responses
  FOR EACH ROW
  EXECUTE FUNCTION public.snapshot_and_validate_visit_checklist_response();

REVOKE ALL ON FUNCTION public.snapshot_and_validate_visit_checklist_response()
  FROM PUBLIC, anon, authenticated;

-- Track meaningful template/question edits without building a full publishing engine.
CREATE OR REPLACE FUNCTION public.bump_visit_checklist_template_version()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
BEGIN
  IF ROW(NEW.name, NEW.description, NEW.category, NEW.purpose_type, NEW.is_mandatory)
     IS DISTINCT FROM
     ROW(OLD.name, OLD.description, OLD.category, OLD.purpose_type, OLD.is_mandatory) THEN
    NEW.version := OLD.version + 1;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_bump_visit_checklist_template_version
  ON public.visit_checklist_templates;
CREATE TRIGGER trg_bump_visit_checklist_template_version
  BEFORE UPDATE ON public.visit_checklist_templates
  FOR EACH ROW
  EXECUTE FUNCTION public.bump_visit_checklist_template_version();

CREATE OR REPLACE FUNCTION public.touch_visit_checklist_template_version_from_question()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
DECLARE
  v_template_id UUID := COALESCE(NEW.template_id, OLD.template_id);
BEGIN
  UPDATE public.visit_checklist_templates
  SET version = version + 1,
      updated_at = clock_timestamp()
  WHERE id = v_template_id;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_touch_template_version_from_question
  ON public.visit_checklist_questions;
CREATE TRIGGER trg_touch_template_version_from_question
  AFTER INSERT OR UPDATE OR DELETE ON public.visit_checklist_questions
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_visit_checklist_template_version_from_question();

REVOKE ALL ON FUNCTION public.bump_visit_checklist_template_version()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.touch_visit_checklist_template_version_from_question()
  FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3) Harden checklist discovery: authenticated invoker + existing RLS
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_applicable_checklists(
  p_category VARCHAR(20),
  p_purpose_type VARCHAR(50) DEFAULT NULL
) RETURNS SETOF public.visit_checklist_templates
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
  SELECT t.*
  FROM public.visit_checklist_templates t
  WHERE t.is_active = true
    AND t.category = p_category
    AND (t.purpose_type IS NULL OR t.purpose_type = p_purpose_type)
  ORDER BY t.sort_order, t.name;
$$;

REVOKE ALL ON FUNCTION public.get_applicable_checklists(VARCHAR, VARCHAR)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_applicable_checklists(VARCHAR, VARCHAR)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 4) Replace only visit templates. Call templates remain unchanged.
--    Abort safely if a visit is currently in progress so requirements cannot
--    change underneath a field user.
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  v_created_by UUID;
  v_template_id UUID;
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.visit_plan_items WHERE status = 'in_progress'
  ) THEN
    RAISE EXCEPTION 'لا يمكن نشر قوالب الزيارات الجديدة أثناء وجود زيارة قيد التنفيذ';
  END IF;

  SELECT created_by INTO v_created_by
  FROM public.visit_checklist_templates
  ORDER BY created_at
  LIMIT 1;

  IF v_created_by IS NULL THEN
    RAISE EXCEPTION 'تعذر تحديد منشئ صالح لقوالب الزيارات الجديدة';
  END IF;

  UPDATE public.visit_checklist_templates
  SET is_active = false, updated_at = clock_timestamp()
  WHERE category = 'visit' AND is_active = true;

  INSERT INTO public.visit_checklist_templates
    (template_code, version, name, description, category, purpose_type,
     is_mandatory, is_active, sort_order, estimated_minutes, created_by)
  VALUES
    ('visit.core', 1, 'نتيجة الزيارة الأساسية',
     'ملخص قصير لا يكرر بيانات الطلب أو التحصيل.',
     'visit', NULL, true, true, 10, 2, v_created_by)
  RETURNING id INTO v_template_id;

  INSERT INTO public.visit_checklist_questions
    (template_id, question_code, question_text, question_type, options,
     hint_text, is_required, sort_order)
  VALUES
    (v_template_id, 'contact.result', 'ما نتيجة التواصل أثناء الزيارة؟', 'single_choice',
     '["تمت مقابلة المسؤول","تمت مقابلة موظف","المسؤول غير موجود","المكان مغلق","تعذر الوصول","رفض المقابلة"]',
     NULL, true, 10),
    (v_template_id, 'contact.person_name', 'اسم الشخص الذي تمت مقابلته', 'text',
     '[]', 'اختياري عند عدم إتمام المقابلة', false, 20),
    (v_template_id, 'customer.current_state', 'ما تقييمك الحالي لحالة العميل؟', 'single_choice',
     '["نمو","مستقر","تراجع","معرض للفقد","متوقف","لا يمكن التقييم"]',
     NULL, true, 30),
    (v_template_id, 'visit.summary_next_step', 'ملخص النتيجة أو الإجراء التالي', 'text',
     '[]', 'اكتب النتيجة باختصار، وإذا لا يوجد إجراء تالٍ اذكر ذلك', true, 40);

  UPDATE public.visit_checklist_templates SET version = 1 WHERE id = v_template_id;

  INSERT INTO public.visit_checklist_templates
    (template_code, version, name, description, category, purpose_type,
     is_mandatory, is_active, sort_order, estimated_minutes, created_by)
  VALUES
    ('visit.sales', 1, 'زيارة البيع وإعادة الطلب',
     'حركة المنتجات وفرصة الطلب وأسباب عدم الشراء.',
     'visit', 'sales', true, true, 20, 3, v_created_by)
  RETURNING id INTO v_template_id;

  INSERT INTO public.visit_checklist_questions
    (template_id, question_code, question_text, question_type, options,
     hint_text, min_value, is_required, sort_order)
  VALUES
    (v_template_id, 'sales.stock_state', 'ما حالة مخزون منتجات ديلايت؟', 'single_choice',
     '["كافٍ","منخفض","توجد نواقص","نفد","لم يتم فحصه"]', NULL, NULL, true, 10),
    (v_template_id, 'sales.fast_slow_products', 'أهم المنتجات السريعة أو البطيئة والنواقص', 'text',
     '[]', 'اكتب أسماء المنتجات أو الفئات المهمة فقط', NULL, false, 20),
    (v_template_id, 'sales.order_outcome', 'ما نتيجة فرصة الطلب؟', 'single_choice',
     '["تم إنشاء طلب","طلب متوقع لاحقاً","لا توجد حاجة حالياً","فقدت الفرصة"]', NULL, NULL, true, 30),
    (v_template_id, 'sales.no_order_reason', 'السبب الأهم لعدم تنفيذ طلب الآن', 'single_choice',
     '["تم تنفيذ طلب","مخزون كافٍ","ضعف الحركة","السعر","منافس","سيولة أو ائتمان","نقص منتج لدينا","مشكلة سابقة","أخرى"]',
     NULL, NULL, true, 40),
    (v_template_id, 'sales.opportunity_value', 'قيمة فرصة الطلب المتوقعة', 'number',
     '[]', 'اتركها فارغة إذا لا توجد فرصة قابلة للتقدير', 0, false, 50);

  UPDATE public.visit_checklist_templates SET version = 1 WHERE id = v_template_id;

  INSERT INTO public.visit_checklist_templates
    (template_code, version, name, description, category, purpose_type,
     is_mandatory, is_active, sort_order, estimated_minutes, created_by)
  VALUES
    ('visit.collection', 1, 'زيارة التحصيل والمخاطر',
     'يسجل نتيجة التحصيل والمخاطر فقط؛ المبلغ والطريقة من سند التحصيل.',
     'visit', 'collection', true, true, 30, 3, v_created_by)
  RETURNING id INTO v_template_id;

  INSERT INTO public.visit_checklist_questions
    (template_id, question_code, question_text, question_type, options,
     hint_text, is_required, sort_order)
  VALUES
    (v_template_id, 'collection.outcome', 'ما نتيجة التحصيل؟', 'single_choice',
     '["سداد كامل","سداد جزئي","لم يتم السداد","لا ينطبق"]', NULL, true, 10),
    (v_template_id, 'collection.failure_reason', 'سبب عدم السداد أو النقص', 'single_choice',
     '["تم السداد بالكامل","المسؤول غير موجود","مشكلة سيولة","اعتراض على فاتورة","وعد بالدفع لاحقاً","أخرى"]', NULL, true, 20),
    (v_template_id, 'collection.promise_date', 'تاريخ وعد الدفع', 'date',
     '[]', 'يُملأ فقط عند وجود وعد محدد', false, 30),
    (v_template_id, 'collection.promise_confidence', 'درجة الثقة في وعد الدفع', 'rating',
     '[]', '1 ضعيفة — 5 مرتفعة', false, 40),
    (v_template_id, 'collection.recommendation', 'توصية المندوب', 'single_choice',
     '["استمرار التعامل","متابعة قريبة","مراجعة الحد الائتماني","وقف البيع الآجل","تصعيد للإدارة","لا توجد توصية"]', NULL, true, 50);

  UPDATE public.visit_checklist_templates SET version = 1 WHERE id = v_template_id;

  INSERT INTO public.visit_checklist_templates
    (template_code, version, name, description, category, purpose_type,
     is_mandatory, is_active, sort_order, estimated_minutes, created_by)
  VALUES
    ('visit.activation', 1, 'تنشيط العميل أو المنتج',
     'نتيجة التنشيط والدعم المطلوب دون تفاصيل زائدة.',
     'visit', 'activation', true, true, 40, 2, v_created_by)
  RETURNING id INTO v_template_id;

  INSERT INTO public.visit_checklist_questions
    (template_id, question_code, question_text, question_type, options,
     hint_text, is_required, sort_order)
  VALUES
    (v_template_id, 'activation.action', 'ما الذي تم تنفيذه؟', 'multi_choice',
     '["شرح منتج","تجربة منتج","تدريب","تسليم عينة","مراجعة استخدام","لم يتم التنشيط"]', NULL, true, 10),
    (v_template_id, 'activation.customer_response', 'استجابة العميل', 'single_choice',
     '["متحمس","مهتم ويحتاج متابعة","غير مقتنع","تعذر التقييم"]', NULL, true, 20),
    (v_template_id, 'activation.support_needed', 'الدعم المطلوب', 'multi_choice',
     '["عينة","عرض سعر","تدريب","مواد دعائية","دعم فني","لا يوجد"]', NULL, false, 30);

  UPDATE public.visit_checklist_templates SET version = 1 WHERE id = v_template_id;

  INSERT INTO public.visit_checklist_templates
    (template_code, version, name, description, category, purpose_type,
     is_mandatory, is_active, sort_order, estimated_minutes, created_by)
  VALUES
    ('visit.promotion', 1, 'الترويج وعرض المنتجات',
     'توثيق تنفيذ العرض ووضوح المنتجات داخل نقطة البيع.',
     'visit', 'promotion', true, true, 50, 2, v_created_by)
  RETURNING id INTO v_template_id;

  INSERT INTO public.visit_checklist_questions
    (template_id, question_code, question_text, question_type, options,
     hint_text, is_required, sort_order)
  VALUES
    (v_template_id, 'promotion.execution_state', 'حالة تنفيذ العرض أو الترويج', 'single_choice',
     '["مكتمل","مكتمل جزئياً","لم ينفذ","لا ينطبق"]', NULL, true, 10),
    (v_template_id, 'promotion.visibility', 'تقييم ظهور منتجات ديلايت', 'rating',
     '[]', '1 ضعيف — 5 ممتاز', true, 20),
    (v_template_id, 'promotion.competitor_change', 'هل ظهر عرض أو منافس مهم جديد؟', 'yes_no',
     '[]', NULL, true, 30),
    (v_template_id, 'promotion.proof_photo', 'صورة العرض أو الظهور', 'photo',
     '[]', 'صورة واحدة واضحة عند الحاجة', false, 40);

  UPDATE public.visit_checklist_templates SET version = 1 WHERE id = v_template_id;

  INSERT INTO public.visit_checklist_templates
    (template_code, version, name, description, category, purpose_type,
     is_mandatory, is_active, sort_order, estimated_minutes, created_by)
  VALUES
    ('visit.followup', 1, 'المتابعة وإعادة التنشيط',
     'حالة المتابعة وسبب التعطل واحتمالية العودة.',
     'visit', 'followup', true, true, 60, 3, v_created_by)
  RETURNING id INTO v_template_id;

  INSERT INTO public.visit_checklist_questions
    (template_id, question_code, question_text, question_type, options,
     hint_text, is_required, sort_order)
  VALUES
    (v_template_id, 'followup.status', 'ما نتيجة المتابعة؟', 'single_choice',
     '["تم حل الموضوع","تقدم جزئي","يحتاج متابعة أخرى","رفض العميل","تعذر التواصل"]', NULL, true, 10),
    (v_template_id, 'followup.stop_reason', 'السبب الأساسي للتوقف أو التعطل', 'single_choice',
     '["لا يوجد توقف","السعر","الائتمان","نقص المنتجات","مشكلة جودة","تأخير توريد","انتقل لمنافس","تغير أو إغلاق النشاط","ضعف المتابعة","أخرى"]', NULL, true, 20),
    (v_template_id, 'followup.return_probability', 'احتمالية العودة أو إتمام الاتفاق', 'single_choice',
     '["مرتفعة","متوسطة","ضعيفة","غير منطبق"]', NULL, true, 30),
    (v_template_id, 'followup.next_date', 'تاريخ المتابعة التالي', 'date',
     '[]', 'اتركه فارغاً إذا لا توجد متابعة', false, 40);

  UPDATE public.visit_checklist_templates SET version = 1 WHERE id = v_template_id;

  INSERT INTO public.visit_checklist_templates
    (template_code, version, name, description, category, purpose_type,
     is_mandatory, is_active, sort_order, estimated_minutes, created_by)
  VALUES
    ('visit.service', 1, 'الخدمة أو الشكوى الفنية',
     'توثيق المشكلة والإجراء الفني والدرجة العاجلة.',
     'visit', 'service', true, true, 70, 3, v_created_by)
  RETURNING id INTO v_template_id;

  INSERT INTO public.visit_checklist_questions
    (template_id, question_code, question_text, question_type, options,
     hint_text, is_required, sort_order)
  VALUES
    (v_template_id, 'service.issue_type', 'نوع المشكلة أو الطلب', 'single_choice',
     '["جودة المنتج","طريقة الاستخدام","تعبئة أو تسريب","رائحة أو نتيجة غير مرضية","تدريب","طلب خدمة آخر"]', NULL, true, 10),
    (v_template_id, 'service.product_batch', 'المنتج والحجم ورقم الباتش إن وجد', 'text',
     '[]', NULL, true, 20),
    (v_template_id, 'service.urgency', 'درجة الاستعجال', 'single_choice',
     '["عادية","مهمة","عاجلة"]', NULL, true, 30),
    (v_template_id, 'service.action_taken', 'الإجراء الذي تم أو المطلوب', 'text',
     '[]', NULL, true, 40),
    (v_template_id, 'service.proof_photo', 'صورة المشكلة أو المنتج', 'photo',
     '[]', 'صورة واحدة واضحة عند الحاجة', false, 50);

  UPDATE public.visit_checklist_templates SET version = 1 WHERE id = v_template_id;
END;
$$;

COMMIT;
