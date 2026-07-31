-- Zero rows = contract passed.

-- 1) Checklist discovery must no longer bypass RLS or allow anonymous execution.
SELECT 'CHECKLIST_LOOKUP_SECURITY_REGRESSION' AS audit_rule
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'get_applicable_checklists'
  AND (
    p.prosecdef = true
    OR pg_catalog.has_function_privilege(
      'anon', p.oid, 'EXECUTE'
    )
  );

-- 2) Real dates, stable codes, versions, and response snapshots must exist.
WITH required_columns(table_name, column_name) AS (
  VALUES
    ('visit_checklist_templates', 'template_code'),
    ('visit_checklist_templates', 'version'),
    ('visit_checklist_templates', 'estimated_minutes'),
    ('visit_checklist_questions', 'question_code'),
    ('visit_checklist_responses', 'template_code_snapshot'),
    ('visit_checklist_responses', 'template_version_snapshot'),
    ('visit_checklist_responses', 'question_code_snapshot'),
    ('visit_checklist_responses', 'question_text_snapshot'),
    ('visit_checklist_responses', 'question_type_snapshot'),
    ('visit_checklist_responses', 'options_snapshot')
)
SELECT 'MISSING_V2_COLUMN' AS audit_rule, r.table_name, r.column_name
FROM required_columns r
LEFT JOIN information_schema.columns c
  ON c.table_schema = 'public'
 AND c.table_name = r.table_name
 AND c.column_name = r.column_name
WHERE c.column_name IS NULL;

SELECT 'DATE_QUESTION_TYPE_MISSING' AS audit_rule
WHERE NOT EXISTS (
  SELECT 1
  FROM pg_catalog.pg_constraint c
  WHERE c.conrelid = 'public.visit_checklist_questions'::regclass
    AND c.conname = 'visit_checklist_questions_question_type_check'
    AND pg_catalog.pg_get_constraintdef(c.oid) ILIKE '%date%'
);

-- 3) All seven concise visit templates must exist and be the active set.
WITH expected(template_code) AS (
  VALUES
    ('visit.core'),
    ('visit.sales'),
    ('visit.collection'),
    ('visit.activation'),
    ('visit.promotion'),
    ('visit.followup'),
    ('visit.service')
)
SELECT 'MISSING_ACTIVE_MVP_TEMPLATE' AS audit_rule, e.template_code
FROM expected e
LEFT JOIN public.visit_checklist_templates t
  ON t.template_code = e.template_code AND t.is_active = true
WHERE t.id IS NULL;

SELECT 'UNEXPECTED_ACTIVE_VISIT_TEMPLATE' AS audit_rule, t.template_code
FROM public.visit_checklist_templates t
WHERE t.category = 'visit'
  AND t.is_active = true
  AND t.template_code NOT IN (
    'visit.core', 'visit.sales', 'visit.collection', 'visit.activation',
    'visit.promotion', 'visit.followup', 'visit.service'
  );

-- 4) Snapshot/validation trigger must be enabled.
SELECT 'SNAPSHOT_TRIGGER_MISSING_OR_DISABLED' AS audit_rule
WHERE NOT EXISTS (
  SELECT 1
  FROM pg_catalog.pg_trigger tg
  WHERE tg.tgrelid = 'public.visit_checklist_responses'::regclass
    AND tg.tgname = 'trg_snapshot_validate_visit_checklist_response'
    AND tg.tgenabled = 'O'
    AND NOT tg.tgisinternal
);

-- 5) A native date input emits YYYY-MM-DD. The trigger regex must accept
-- ASCII digits without relying on a double-escaped \d sequence.
SELECT 'DATE_VALIDATION_REGEX_REGRESSION' AS audit_rule
WHERE NOT EXISTS (
  SELECT 1
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'snapshot_and_validate_visit_checklist_response'
    AND p.prosrc LIKE '%^[0-9]{4}-[0-9]{2}-[0-9]{2}$%'
);

-- 6) Atomic completion passes JSON literal null for scalar answer_json fields.
-- The trigger must normalize it to SQL NULL before validating or persisting.
SELECT 'SCALAR_JSON_NULL_NORMALIZATION_REGRESSION' AS audit_rule
WHERE NOT EXISTS (
  SELECT 1
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'snapshot_and_validate_visit_checklist_response'
    AND p.prosrc LIKE '%NEW.answer_json := NULLIF(NEW.answer_json, ''null''::JSONB)%'
);
