BEGIN;

-- A standard-conforming SQL string must not double-escape the regex digit
-- class. Use an explicit ASCII digit range so the validation behaves the same
-- across PostgreSQL settings and accepts the value emitted by input[type=date].
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
       OR NEW.answer_value !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
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

  -- Historical response metadata remains derived from the database and cannot
  -- be forged by the client.
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

REVOKE ALL ON FUNCTION public.snapshot_and_validate_visit_checklist_response()
  FROM PUBLIC, anon, authenticated;

COMMIT;
