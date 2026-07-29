-- EDARA v2 — Visit reporting center
-- One secure reporting grain per planned visit, plus a normalized survey fact.

CREATE INDEX IF NOT EXISTS idx_visit_checklist_responses_snapshot_answer
  ON public.visit_checklist_responses (question_code_snapshot, answer_value, activity_id)
  WHERE question_code_snapshot IS NOT NULL;

DROP VIEW IF EXISTS public.v_visit_survey_report_answers;
DROP VIEW IF EXISTS public.v_visit_report_rows;

CREATE VIEW public.v_visit_report_rows
WITH (security_invoker = true)
AS
SELECT
  item.id AS visit_item_id,
  plan.id AS plan_id,
  plan.plan_date,
  plan.status AS plan_status,
  plan.plan_type,
  plan.organizational_branch_id AS branch_id,
  branch.name AS branch_name,
  plan.employee_id,
  employee.full_name AS employee_name,
  item.sequence,
  item.customer_id,
  customer.code AS customer_code,
  customer.name AS customer_name,
  item.customer_branch_id,
  item.purpose_type,
  item.purpose,
  item.priority,
  item.status AS visit_status,
  item.planned_time,
  item.estimated_duration_min,
  item.activity_id,
  activity.outcome_type,
  activity.outcome_notes,
  activity.order_id,
  activity.collection_id,
  COALESCE(activity.start_time, item.server_started_at, item.actual_start_time) AS started_at,
  COALESCE(activity.end_time, item.server_completed_at, item.actual_end_time) AS completed_at,
  COALESCE(
    activity.duration_minutes,
    CASE
      WHEN item.server_started_at IS NOT NULL AND item.server_completed_at IS NOT NULL
        THEN GREATEST(0, ROUND(EXTRACT(EPOCH FROM (item.server_completed_at - item.server_started_at)) / 60.0)::INTEGER)
      ELSE NULL
    END
  ) AS duration_minutes,
  item.start_distance_m,
  item.end_distance_m,
  item.gps_validation_status,
  item.gps_review_status,
  item.gps_exception_reason,
  item.skip_reason,
  item.reschedule_to,
  item.reschedule_reason,
  COALESCE((item.metadata ->> 'administrative_completion')::BOOLEAN, FALSE) AS is_administrative_completion,
  CASE
    WHEN COALESCE((item.metadata ->> 'administrative_completion')::BOOLEAN, FALSE) THEN 'administrative'
    WHEN item.status = 'completed' AND item.activity_id IS NULL THEN 'missing_activity'
    WHEN item.activity_id IS NOT NULL THEN 'recorded'
    WHEN item.status IN ('pending', 'in_progress') THEN 'open'
    ELSE item.status
  END AS recording_quality,
  survey.response_count,
  survey.contact_result,
  survey.contact_person_name,
  survey.customer_state,
  survey.visit_summary,
  survey.sales_order_outcome,
  survey.sales_no_order_reason,
  survey.sales_opportunity_value,
  survey.activation_response,
  survey.followup_status,
  COALESCE(survey.has_core_survey, FALSE) AS has_core_survey,
  COALESCE(
    survey.sales_order_outcome,
    survey.followup_status,
    survey.activation_response,
    survey.contact_result,
    activity.outcome_type
  ) AS business_outcome,
  COALESCE(survey.contact_result IN ('تمت مقابلة المسؤول', 'تمت مقابلة موظف'), FALSE) AS is_effective_contact,
  (item.gps_review_status = 'pending') AS needs_gps_review,
  (
    item.status = 'completed'
    AND (
      item.activity_id IS NULL
      OR NOT COALESCE(survey.has_core_survey, FALSE)
      OR item.gps_review_status = 'pending'
      OR COALESCE((item.metadata ->> 'administrative_completion')::BOOLEAN, FALSE)
    )
  ) AS has_quality_exception
FROM public.visit_plan_items AS item
JOIN public.visit_plans AS plan ON plan.id = item.plan_id
JOIN public.hr_employees AS employee ON employee.id = plan.employee_id
LEFT JOIN public.branches AS branch ON branch.id = plan.organizational_branch_id
JOIN public.customers AS customer ON customer.id = item.customer_id
LEFT JOIN public.activities AS activity
  ON activity.id = item.activity_id
 AND activity.deleted_at IS NULL
LEFT JOIN LATERAL (
  SELECT
    COUNT(*)::INTEGER AS response_count,
    BOOL_OR(COALESCE(response.template_code_snapshot, template.template_code) = 'visit.core') AS has_core_survey,
    MAX(response.answer_value) FILTER (
      WHERE COALESCE(response.question_code_snapshot, question.question_code) = 'contact.result'
    ) AS contact_result,
    MAX(response.answer_value) FILTER (
      WHERE COALESCE(response.question_code_snapshot, question.question_code) = 'contact.person_name'
    ) AS contact_person_name,
    MAX(response.answer_value) FILTER (
      WHERE COALESCE(response.question_code_snapshot, question.question_code) = 'customer.current_state'
    ) AS customer_state,
    MAX(response.answer_value) FILTER (
      WHERE COALESCE(response.question_code_snapshot, question.question_code) = 'visit.summary_next_step'
    ) AS visit_summary,
    MAX(response.answer_value) FILTER (
      WHERE COALESCE(response.question_code_snapshot, question.question_code) = 'sales.order_outcome'
    ) AS sales_order_outcome,
    MAX(response.answer_value) FILTER (
      WHERE COALESCE(response.question_code_snapshot, question.question_code) = 'sales.no_order_reason'
    ) AS sales_no_order_reason,
    MAX(NULLIF(response.answer_value, '')::NUMERIC) FILTER (
      WHERE COALESCE(response.question_code_snapshot, question.question_code) = 'sales.opportunity_value'
        AND response.answer_value ~ '^[0-9]+([.][0-9]+)?$'
    ) AS sales_opportunity_value,
    MAX(response.answer_value) FILTER (
      WHERE COALESCE(response.question_code_snapshot, question.question_code) = 'activation.customer_response'
    ) AS activation_response,
    MAX(response.answer_value) FILTER (
      WHERE COALESCE(response.question_code_snapshot, question.question_code) = 'followup.status'
    ) AS followup_status
  FROM public.visit_checklist_responses AS response
  LEFT JOIN public.visit_checklist_questions AS question ON question.id = response.question_id
  LEFT JOIN public.visit_checklist_templates AS template ON template.id = response.template_id
  WHERE response.activity_id = activity.id
) AS survey ON TRUE
WHERE
  (SELECT public.check_permission((SELECT auth.uid()), 'reports.activities'))
  OR (SELECT public.check_permission((SELECT auth.uid()), 'reports.view_all'));

CREATE VIEW public.v_visit_survey_report_answers
WITH (security_invoker = true)
AS
SELECT
  plan.plan_date,
  plan.organizational_branch_id AS branch_id,
  branch.name AS branch_name,
  plan.employee_id,
  employee.full_name AS employee_name,
  item.id AS visit_item_id,
  item.plan_id,
  item.customer_id,
  customer.code AS customer_code,
  customer.name AS customer_name,
  item.purpose_type,
  activity.id AS activity_id,
  response.id AS response_id,
  COALESCE(response.template_code_snapshot, template.template_code) AS template_code,
  COALESCE(response.template_name_snapshot, template.name) AS template_name,
  COALESCE(response.template_version_snapshot, template.version) AS template_version,
  COALESCE(response.question_code_snapshot, question.question_code) AS question_code,
  COALESCE(response.question_text_snapshot, question.question_text) AS question_text,
  COALESCE(response.question_type_snapshot, question.question_type) AS question_type,
  response.answer_value,
  response.answer_json,
  response.created_at
FROM public.visit_checklist_responses AS response
JOIN public.activities AS activity
  ON activity.id = response.activity_id
 AND activity.deleted_at IS NULL
JOIN public.visit_plan_items AS item ON item.id = activity.visit_plan_item_id
JOIN public.visit_plans AS plan ON plan.id = item.plan_id
JOIN public.hr_employees AS employee ON employee.id = plan.employee_id
LEFT JOIN public.branches AS branch ON branch.id = plan.organizational_branch_id
JOIN public.customers AS customer ON customer.id = item.customer_id
LEFT JOIN public.visit_checklist_questions AS question ON question.id = response.question_id
LEFT JOIN public.visit_checklist_templates AS template ON template.id = response.template_id
WHERE
  (SELECT public.check_permission((SELECT auth.uid()), 'reports.activities'))
  OR (SELECT public.check_permission((SELECT auth.uid()), 'reports.view_all'));

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
      'opportunity_value', COALESCE(SUM(sales_opportunity_value), 0)
    ),
    'contact_results', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('label', contact_result, 'count', total) ORDER BY total DESC, contact_result)
      FROM (
        SELECT contact_result, COUNT(*) AS total
        FROM filtered
        WHERE contact_result IS NOT NULL
        GROUP BY contact_result
      ) AS grouped
    ), '[]'::jsonb),
    'customer_states', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('label', customer_state, 'count', total) ORDER BY total DESC, customer_state)
      FROM (
        SELECT customer_state, COUNT(*) AS total
        FROM filtered
        WHERE customer_state IS NOT NULL
        GROUP BY customer_state
      ) AS grouped
    ), '[]'::jsonb),
    'purpose_results', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'purpose_type', purpose_type,
        'planned', planned,
        'completed', completed,
        'effective_contacts', effective_contacts
      ) ORDER BY planned DESC, purpose_type)
      FROM (
        SELECT
          COALESCE(purpose_type, 'unspecified') AS purpose_type,
          COUNT(*) AS planned,
          COUNT(*) FILTER (WHERE visit_status = 'completed') AS completed,
          COUNT(*) FILTER (WHERE is_effective_contact) AS effective_contacts
        FROM filtered
        GROUP BY COALESCE(purpose_type, 'unspecified')
      ) AS grouped
    ), '[]'::jsonb),
    'employee_results', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'employee_id', employee_id,
        'employee_name', employee_name,
        'planned', planned,
        'completed', completed,
        'field_recorded', field_recorded,
        'effective_contacts', effective_contacts,
        'quality_exceptions', quality_exceptions
      ) ORDER BY completed DESC, employee_name)
      FROM (
        SELECT
          employee_id,
          employee_name,
          COUNT(*) AS planned,
          COUNT(*) FILTER (WHERE visit_status = 'completed') AS completed,
          COUNT(*) FILTER (WHERE activity_id IS NOT NULL) AS field_recorded,
          COUNT(*) FILTER (WHERE is_effective_contact) AS effective_contacts,
          COUNT(*) FILTER (WHERE has_quality_exception) AS quality_exceptions
        FROM filtered
        GROUP BY employee_id, employee_name
      ) AS grouped
    ), '[]'::jsonb)
  )
  FROM filtered;
$function$;

REVOKE ALL ON public.v_visit_report_rows FROM PUBLIC, anon;
REVOKE ALL ON public.v_visit_survey_report_answers FROM PUBLIC, anon;
GRANT SELECT ON public.v_visit_report_rows TO authenticated;
GRANT SELECT ON public.v_visit_survey_report_answers TO authenticated;

REVOKE ALL ON FUNCTION public.get_visit_report_summary(DATE, DATE, UUID, UUID, TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_visit_report_summary(DATE, DATE, UUID, UUID, TEXT)
  TO authenticated;

COMMENT ON VIEW public.v_visit_report_rows IS
  'Secure one-row-per-planned-visit reporting grain. Underlying RLS and reports.activities permission are enforced.';
COMMENT ON VIEW public.v_visit_survey_report_answers IS
  'Secure normalized survey-answer reporting fact using immutable template/question snapshots.';
