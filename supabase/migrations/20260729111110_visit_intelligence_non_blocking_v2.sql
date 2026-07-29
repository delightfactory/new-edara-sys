-- EDARA v2 — non-blocking visit intelligence
-- Progressive disclosure keeps the field flow short. A question can block completion
-- only while it is visible and explicitly required by the active template version.

ALTER TABLE public.visit_checklist_questions
  ADD COLUMN IF NOT EXISTS visibility_rule JSONB;

COMMENT ON COLUMN public.visit_checklist_questions.visibility_rule IS
  'Client-evaluated progressive disclosure rule. Supports question_code/operator/value or nested all/any groups. NULL preserves legacy visibility.';

-- Core: one factual answer always starts the flow. Assessment is only relevant after contact.
UPDATE public.visit_checklist_questions AS q
SET visibility_rule = jsonb_build_object(
      'question_code', 'contact.result',
      'operator', 'in',
      'value', jsonb_build_array('تمت مقابلة المسؤول', 'تمت مقابلة موظف')
    )
FROM public.visit_checklist_templates AS t
WHERE t.id = q.template_id
  AND t.template_code = 'visit.core'
  AND q.question_code IN ('contact.person_name', 'customer.current_state');

UPDATE public.visit_checklist_questions AS q
SET is_required = FALSE,
    question_text = 'ملاحظة مختصرة أو خطوة تالية',
    hint_text = 'اختياري — اكتب فقط ما سيفيد المتابعة أو الإدارة'
FROM public.visit_checklist_templates AS t
WHERE t.id = q.template_id
  AND t.template_code = 'visit.core'
  AND q.question_code = 'visit.summary_next_step';

-- Purpose questions are only relevant after an actual contact. Nested rules then reveal
-- the minimum follow-up questions needed for the selected outcome.
UPDATE public.visit_checklist_questions AS q
SET visibility_rule = jsonb_build_object(
      'question_code', 'contact.result',
      'operator', 'in',
      'value', jsonb_build_array('تمت مقابلة المسؤول', 'تمت مقابلة موظف')
    )
FROM public.visit_checklist_templates AS t
WHERE t.id = q.template_id
  AND t.template_code IN (
    'visit.sales', 'visit.collection', 'visit.activation', 'visit.promotion',
    'visit.followup', 'visit.service'
  );

UPDATE public.visit_checklist_questions AS q
SET visibility_rule = jsonb_build_object('all', jsonb_build_array(
      jsonb_build_object(
        'question_code', 'contact.result', 'operator', 'in',
        'value', jsonb_build_array('تمت مقابلة المسؤول', 'تمت مقابلة موظف')
      ),
      jsonb_build_object(
        'question_code', 'sales.order_outcome', 'operator', 'not_equals', 'value', 'تم إنشاء طلب'
      )
    ))
FROM public.visit_checklist_templates AS t
WHERE t.id = q.template_id
  AND t.template_code = 'visit.sales'
  AND q.question_code = 'sales.no_order_reason';

UPDATE public.visit_checklist_questions AS q
SET visibility_rule = jsonb_build_object('all', jsonb_build_array(
      jsonb_build_object(
        'question_code', 'contact.result', 'operator', 'in',
        'value', jsonb_build_array('تمت مقابلة المسؤول', 'تمت مقابلة موظف')
      ),
      jsonb_build_object(
        'question_code', 'sales.order_outcome', 'operator', 'equals', 'value', 'طلب متوقع لاحقاً'
      )
    ))
FROM public.visit_checklist_templates AS t
WHERE t.id = q.template_id
  AND t.template_code = 'visit.sales'
  AND q.question_code = 'sales.opportunity_value';

UPDATE public.visit_checklist_questions AS q
SET visibility_rule = jsonb_build_object('all', jsonb_build_array(
      jsonb_build_object(
        'question_code', 'contact.result', 'operator', 'in',
        'value', jsonb_build_array('تمت مقابلة المسؤول', 'تمت مقابلة موظف')
      ),
      jsonb_build_object(
        'question_code', 'sales.stock_state', 'operator', 'not_equals', 'value', 'لم يتم فحصه'
      )
    ))
FROM public.visit_checklist_templates AS t
WHERE t.id = q.template_id
  AND t.template_code = 'visit.sales'
  AND q.question_code = 'sales.fast_slow_products';

UPDATE public.visit_checklist_questions AS q
SET visibility_rule = jsonb_build_object('all', jsonb_build_array(
      jsonb_build_object(
        'question_code', 'contact.result', 'operator', 'in',
        'value', jsonb_build_array('تمت مقابلة المسؤول', 'تمت مقابلة موظف')
      ),
      jsonb_build_object(
        'question_code', 'activation.action', 'operator', 'not_contains', 'value', 'لم يتم التنشيط'
      )
    ))
FROM public.visit_checklist_templates AS t
WHERE t.id = q.template_id
  AND t.template_code = 'visit.activation'
  AND q.question_code = 'activation.customer_response';

UPDATE public.visit_checklist_questions AS q
SET visibility_rule = jsonb_build_object('all', jsonb_build_array(
      jsonb_build_object(
        'question_code', 'contact.result', 'operator', 'in',
        'value', jsonb_build_array('تمت مقابلة المسؤول', 'تمت مقابلة موظف')
      ),
      jsonb_build_object(
        'question_code', 'activation.action', 'operator', 'contains', 'value', 'لم يتم التنشيط'
      )
    ))
FROM public.visit_checklist_templates AS t
WHERE t.id = q.template_id
  AND t.template_code = 'visit.activation'
  AND q.question_code = 'activation.support_needed';

UPDATE public.visit_checklist_questions AS q
SET visibility_rule = jsonb_build_object('all', jsonb_build_array(
      jsonb_build_object(
        'question_code', 'contact.result', 'operator', 'in',
        'value', jsonb_build_array('تمت مقابلة المسؤول', 'تمت مقابلة موظف')
      ),
      jsonb_build_object(
        'question_code', 'collection.outcome', 'operator', 'in',
        'value', jsonb_build_array('سداد جزئي', 'لم يتم السداد')
      )
    ))
FROM public.visit_checklist_templates AS t
WHERE t.id = q.template_id
  AND t.template_code = 'visit.collection'
  AND q.question_code = 'collection.failure_reason';

UPDATE public.visit_checklist_questions AS q
SET visibility_rule = jsonb_build_object('all', jsonb_build_array(
      jsonb_build_object(
        'question_code', 'contact.result', 'operator', 'in',
        'value', jsonb_build_array('تمت مقابلة المسؤول', 'تمت مقابلة موظف')
      ),
      jsonb_build_object(
        'question_code', 'collection.failure_reason', 'operator', 'equals', 'value', 'وعد بالدفع لاحقاً'
      )
    ))
FROM public.visit_checklist_templates AS t
WHERE t.id = q.template_id
  AND t.template_code = 'visit.collection'
  AND q.question_code IN ('collection.promise_date', 'collection.promise_confidence');

UPDATE public.visit_checklist_questions AS q
SET visibility_rule = jsonb_build_object('all', jsonb_build_array(
      jsonb_build_object(
        'question_code', 'contact.result', 'operator', 'in',
        'value', jsonb_build_array('تمت مقابلة المسؤول', 'تمت مقابلة موظف')
      ),
      jsonb_build_object(
        'question_code', 'promotion.execution_state', 'operator', 'in',
        'value', jsonb_build_array('مكتمل', 'مكتمل جزئياً')
      )
    ))
FROM public.visit_checklist_templates AS t
WHERE t.id = q.template_id
  AND t.template_code = 'visit.promotion'
  AND q.question_code IN ('promotion.visibility', 'promotion.proof_photo');

UPDATE public.visit_checklist_questions AS q
SET visibility_rule = jsonb_build_object('all', jsonb_build_array(
      jsonb_build_object(
        'question_code', 'contact.result', 'operator', 'in',
        'value', jsonb_build_array('تمت مقابلة المسؤول', 'تمت مقابلة موظف')
      ),
      jsonb_build_object(
        'question_code', 'followup.status', 'operator', 'not_equals', 'value', 'تم حل الموضوع'
      )
    ))
FROM public.visit_checklist_templates AS t
WHERE t.id = q.template_id
  AND t.template_code = 'visit.followup'
  AND q.question_code IN ('followup.stop_reason', 'followup.return_probability');

UPDATE public.visit_checklist_questions AS q
SET is_required = FALSE,
    hint_text = 'اختياري — اكتب رقم الباتش فقط إذا كان متاحًا'
FROM public.visit_checklist_templates AS t
WHERE t.id = q.template_id
  AND t.template_code = 'visit.service'
  AND q.question_code = 'service.product_batch';

-- Remove artificial escape answers that previously existed only because irrelevant
-- questions were always displayed.
UPDATE public.visit_checklist_questions AS q
SET options = COALESCE((
  SELECT jsonb_agg(value)
  FROM jsonb_array_elements(q.options) AS option_value(value)
  WHERE value <> to_jsonb('تم تنفيذ طلب'::TEXT)
), '[]'::jsonb)
FROM public.visit_checklist_templates AS t
WHERE t.id = q.template_id
  AND t.template_code = 'visit.sales'
  AND q.question_code = 'sales.no_order_reason';

UPDATE public.visit_checklist_questions AS q
SET options = COALESCE((
  SELECT jsonb_agg(value)
  FROM jsonb_array_elements(q.options) AS option_value(value)
  WHERE value <> to_jsonb('تم السداد بالكامل'::TEXT)
), '[]'::jsonb)
FROM public.visit_checklist_templates AS t
WHERE t.id = q.template_id
  AND t.template_code = 'visit.collection'
  AND q.question_code = 'collection.failure_reason';

UPDATE public.visit_checklist_questions AS q
SET options = COALESCE((
  SELECT jsonb_agg(value)
  FROM jsonb_array_elements(q.options) AS option_value(value)
  WHERE value <> to_jsonb('لا يوجد توقف'::TEXT)
), '[]'::jsonb)
FROM public.visit_checklist_templates AS t
WHERE t.id = q.template_id
  AND t.template_code = 'visit.followup'
  AND q.question_code = 'followup.stop_reason';

-- Optional commitments enrich decisions without blocking the rep if the customer has not
-- committed to a date or action yet.
INSERT INTO public.visit_checklist_questions
  (template_id, question_code, question_text, question_type, options, hint_text, is_required, sort_order, visibility_rule)
SELECT t.id, 'sales.expected_order_date', 'الموعد المتوقع للطلب', 'date', '[]'::jsonb,
       'اختياري — اتركه فارغًا إذا لم يحدد العميل موعدًا', FALSE, 60,
       jsonb_build_object('all', jsonb_build_array(
         jsonb_build_object(
           'question_code', 'contact.result', 'operator', 'in',
           'value', jsonb_build_array('تمت مقابلة المسؤول', 'تمت مقابلة موظف')
         ),
         jsonb_build_object(
           'question_code', 'sales.order_outcome', 'operator', 'equals', 'value', 'طلب متوقع لاحقاً'
         )
       ))
FROM public.visit_checklist_templates AS t
WHERE t.template_code = 'visit.sales'
  AND NOT EXISTS (
    SELECT 1 FROM public.visit_checklist_questions existing
    WHERE existing.template_id = t.id AND existing.question_code = 'sales.expected_order_date'
  );

INSERT INTO public.visit_checklist_questions
  (template_id, question_code, question_text, question_type, options, hint_text, is_required, sort_order, visibility_rule)
SELECT t.id, 'sales.no_order_details', 'توضيح مختصر للسبب', 'text', '[]'::jsonb,
       'اختياري — يساعد الإدارة على فهم الأسباب غير الموجودة بالقائمة', FALSE, 45,
       jsonb_build_object('all', jsonb_build_array(
         jsonb_build_object(
           'question_code', 'contact.result', 'operator', 'in',
           'value', jsonb_build_array('تمت مقابلة المسؤول', 'تمت مقابلة موظف')
         ),
         jsonb_build_object(
           'question_code', 'sales.no_order_reason', 'operator', 'equals', 'value', 'أخرى'
         )
       ))
FROM public.visit_checklist_templates AS t
WHERE t.template_code = 'visit.sales'
  AND NOT EXISTS (
    SELECT 1 FROM public.visit_checklist_questions existing
    WHERE existing.template_id = t.id AND existing.question_code = 'sales.no_order_details'
  );

INSERT INTO public.visit_checklist_questions
  (template_id, question_code, question_text, question_type, options, hint_text, is_required, sort_order, visibility_rule)
SELECT t.id, 'visit.next_action', 'هل يوجد إجراء تالٍ؟', 'single_choice',
       '["لا يوجد إجراء","متابعة اتصال","زيارة أخرى","إعداد عرض سعر","إنشاء طلب لاحقاً","دعم فني","تحصيل"]'::jsonb,
       'اختياري — اختر فقط إذا اتفقت على خطوة أو ترى حاجة واضحة', FALSE, 50,
       jsonb_build_object(
         'question_code', 'contact.result', 'operator', 'in',
         'value', jsonb_build_array('تمت مقابلة المسؤول', 'تمت مقابلة موظف')
       )
FROM public.visit_checklist_templates AS t
WHERE t.template_code = 'visit.core'
  AND NOT EXISTS (
    SELECT 1 FROM public.visit_checklist_questions existing
    WHERE existing.template_id = t.id AND existing.question_code = 'visit.next_action'
  );

INSERT INTO public.visit_checklist_questions
  (template_id, question_code, question_text, question_type, options, hint_text, is_required, sort_order, visibility_rule)
SELECT t.id, 'visit.next_action_date', 'موعد الإجراء التالي', 'date', '[]'::jsonb,
       'اختياري — لا يمنع إنهاء الزيارة إذا لم يتحدد الموعد', FALSE, 60,
       jsonb_build_object('all', jsonb_build_array(
         jsonb_build_object(
           'question_code', 'contact.result', 'operator', 'in',
           'value', jsonb_build_array('تمت مقابلة المسؤول', 'تمت مقابلة موظف')
         ),
         jsonb_build_object(
           'question_code', 'visit.next_action', 'operator', 'not_equals', 'value', 'لا يوجد إجراء'
         )
       ))
FROM public.visit_checklist_templates AS t
WHERE t.template_code = 'visit.core'
  AND NOT EXISTS (
    SELECT 1 FROM public.visit_checklist_questions existing
    WHERE existing.template_id = t.id AND existing.question_code = 'visit.next_action_date'
  );

UPDATE public.visit_checklist_templates
SET version = GREATEST(version, 2),
    updated_at = NOW()
WHERE template_code LIKE 'visit.%' AND is_active;

CREATE OR REPLACE FUNCTION public.get_visit_report_summary(
  p_date_from DATE DEFAULT (CURRENT_DATE - 29),
  p_date_to DATE DEFAULT CURRENT_DATE,
  p_employee_id UUID DEFAULT NULL,
  p_branch_id UUID DEFAULT NULL,
  p_purpose_type TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE SQL
STABLE
SECURITY INVOKER
SET search_path = pg_catalog
AS $function$
  WITH filtered AS MATERIALIZED (
    SELECT *
    FROM public.v_visit_report_rows AS report
    WHERE report.plan_date BETWEEN LEAST(p_date_from, p_date_to) AND GREATEST(p_date_from, p_date_to)
      AND (p_employee_id IS NULL OR report.employee_id = p_employee_id)
      AND (p_branch_id IS NULL OR report.branch_id = p_branch_id)
      AND (p_purpose_type IS NULL OR report.purpose_type = p_purpose_type)
  )
  SELECT jsonb_build_object(
    'metrics', jsonb_build_object(
      'planned', COUNT(*),
      'completed', COUNT(*) FILTER (WHERE visit_status = 'completed'),
      'field_recorded', COUNT(*) FILTER (WHERE activity_id IS NOT NULL),
      'administrative', COUNT(*) FILTER (WHERE is_administrative_completion),
      'effective_contacts', COUNT(*) FILTER (WHERE is_effective_contact),
      'survey_completed', COUNT(*) FILTER (WHERE has_core_survey),
      'gps_passed', COUNT(*) FILTER (WHERE gps_validation_status = 'passed'),
      'gps_pending_review', COUNT(*) FILTER (WHERE needs_gps_review),
      'quality_exceptions', COUNT(*) FILTER (WHERE has_quality_exception),
      'open_visits', COUNT(*) FILTER (WHERE visit_status IN ('pending', 'in_progress')),
      'average_duration_minutes', ROUND(AVG(duration_minutes) FILTER (WHERE duration_minutes IS NOT NULL), 1),
      'opportunity_value', COALESCE(SUM(sales_opportunity_value), 0),
      'sales_created', COUNT(*) FILTER (WHERE sales_order_outcome = 'تم إنشاء طلب'),
      'sales_expected', COUNT(*) FILTER (WHERE sales_order_outcome = 'طلب متوقع لاحقاً'),
      'sales_lost', COUNT(*) FILTER (WHERE sales_order_outcome = 'فقدت الفرصة'),
      'activation_followup', COUNT(*) FILTER (WHERE activation_response = 'مهتم ويحتاج متابعة'),
      'at_risk_visits', COUNT(*) FILTER (WHERE customer_state IN ('تراجع', 'معرض للفقد', 'متوقف')),
      'very_short_visits', COUNT(*) FILTER (WHERE duration_minutes IS NOT NULL AND duration_minutes < 3),
      'unlinked_order_claims', COUNT(*) FILTER (WHERE sales_order_outcome = 'تم إنشاء طلب' AND order_id IS NULL),
      'actionable_visits', COUNT(*) FILTER (
        WHERE sales_order_outcome = 'طلب متوقع لاحقاً'
           OR activation_response = 'مهتم ويحتاج متابعة'
           OR customer_state IN ('تراجع', 'معرض للفقد', 'متوقف')
           OR has_quality_exception
      )
    ),
    'contact_results', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('label', contact_result, 'count', total) ORDER BY total DESC, contact_result)
      FROM (SELECT contact_result, COUNT(*) total FROM filtered WHERE contact_result IS NOT NULL GROUP BY contact_result) grouped
    ), '[]'::jsonb),
    'customer_states', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('label', customer_state, 'count', total) ORDER BY total DESC, customer_state)
      FROM (SELECT customer_state, COUNT(*) total FROM filtered WHERE customer_state IS NOT NULL GROUP BY customer_state) grouped
    ), '[]'::jsonb),
    'sales_outcomes', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('label', sales_order_outcome, 'count', total) ORDER BY total DESC, sales_order_outcome)
      FROM (SELECT sales_order_outcome, COUNT(*) total FROM filtered WHERE sales_order_outcome IS NOT NULL GROUP BY sales_order_outcome) grouped
    ), '[]'::jsonb),
    'activation_outcomes', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('label', activation_response, 'count', total) ORDER BY total DESC, activation_response)
      FROM (SELECT activation_response, COUNT(*) total FROM filtered WHERE activation_response IS NOT NULL GROUP BY activation_response) grouped
    ), '[]'::jsonb),
    'daily_results', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'date', plan_date, 'planned', planned, 'completed', completed, 'effective_contacts', effective_contacts
      ) ORDER BY plan_date)
      FROM (
        SELECT plan_date, COUNT(*) planned,
               COUNT(*) FILTER (WHERE visit_status = 'completed') completed,
               COUNT(*) FILTER (WHERE is_effective_contact) effective_contacts
        FROM filtered GROUP BY plan_date
      ) grouped
    ), '[]'::jsonb),
    'purpose_results', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'purpose_type', purpose_type, 'planned', planned, 'completed', completed,
        'effective_contacts', effective_contacts
      ) ORDER BY planned DESC, purpose_type)
      FROM (
        SELECT COALESCE(purpose_type, 'unspecified') purpose_type, COUNT(*) planned,
               COUNT(*) FILTER (WHERE visit_status = 'completed') completed,
               COUNT(*) FILTER (WHERE is_effective_contact) effective_contacts
        FROM filtered GROUP BY COALESCE(purpose_type, 'unspecified')
      ) grouped
    ), '[]'::jsonb),
    'employee_results', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'employee_id', employee_id, 'employee_name', employee_name, 'planned', planned,
        'completed', completed, 'field_recorded', field_recorded,
        'effective_contacts', effective_contacts, 'quality_exceptions', quality_exceptions
      ) ORDER BY completed DESC, employee_name)
      FROM (
        SELECT employee_id, employee_name, COUNT(*) planned,
               COUNT(*) FILTER (WHERE visit_status = 'completed') completed,
               COUNT(*) FILTER (WHERE activity_id IS NOT NULL) field_recorded,
               COUNT(*) FILTER (WHERE is_effective_contact) effective_contacts,
               COUNT(*) FILTER (WHERE has_quality_exception) quality_exceptions
        FROM filtered GROUP BY employee_id, employee_name
      ) grouped
    ), '[]'::jsonb)
  )
  FROM filtered;
$function$;

REVOKE ALL ON FUNCTION public.get_visit_report_summary(DATE, DATE, UUID, UUID, TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_visit_report_summary(DATE, DATE, UUID, UUID, TEXT)
  TO authenticated;
