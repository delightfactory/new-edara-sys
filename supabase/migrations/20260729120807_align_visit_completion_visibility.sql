BEGIN;

-- Keep server-side completion validation aligned with the progressive-disclosure
-- rules used by ChecklistForm. Hidden required questions must never block a rep.
CREATE OR REPLACE FUNCTION private.visit_checklist_visibility_matches(
  p_rule JSONB,
  p_answers JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = pg_catalog
AS $function$
DECLARE
  v_child    JSONB;
  v_actual   JSONB;
  v_expected JSONB;
  v_operator TEXT;
  v_code     TEXT;
  v_has      BOOLEAN;
  v_matches  BOOLEAN;
BEGIN
  IF p_rule IS NULL OR p_rule = 'null'::JSONB THEN
    RETURN TRUE;
  END IF;

  IF p_rule ? 'all' THEN
    IF jsonb_typeof(p_rule -> 'all') IS DISTINCT FROM 'array' THEN
      RETURN FALSE;
    END IF;
    FOR v_child IN SELECT value FROM jsonb_array_elements(p_rule -> 'all')
    LOOP
      IF NOT private.visit_checklist_visibility_matches(v_child, p_answers) THEN
        RETURN FALSE;
      END IF;
    END LOOP;
    RETURN TRUE;
  END IF;

  IF p_rule ? 'any' THEN
    IF jsonb_typeof(p_rule -> 'any') IS DISTINCT FROM 'array' THEN
      RETURN FALSE;
    END IF;
    FOR v_child IN SELECT value FROM jsonb_array_elements(p_rule -> 'any')
    LOOP
      IF private.visit_checklist_visibility_matches(v_child, p_answers) THEN
        RETURN TRUE;
      END IF;
    END LOOP;
    RETURN FALSE;
  END IF;

  v_code := p_rule ->> 'question_code';
  v_operator := p_rule ->> 'operator';
  v_expected := p_rule -> 'value';
  v_actual := CASE WHEN v_code IS NULL THEN NULL ELSE p_answers -> v_code END;
  v_has := v_actual IS NOT NULL
    AND v_actual <> 'null'::JSONB
    AND NOT (jsonb_typeof(v_actual) = 'string' AND NULLIF(BTRIM(v_actual #>> '{}'), '') IS NULL)
    AND NOT (jsonb_typeof(v_actual) = 'array' AND jsonb_array_length(v_actual) = 0);

  IF v_operator = 'answered' THEN
    RETURN CASE WHEN v_expected = 'false'::JSONB THEN NOT v_has ELSE v_has END;
  END IF;

  -- Match the client rule: a comparison never reveals a dependent question
  -- before its controlling answer exists.
  IF NOT v_has THEN
    RETURN FALSE;
  END IF;

  IF jsonb_typeof(v_expected) = 'array' THEN
    SELECT EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_expected) AS expected(value)
      WHERE expected.value = v_actual
    ) INTO v_matches;
  ELSE
    v_matches := v_actual = v_expected;
  END IF;

  IF v_operator = 'equals' THEN RETURN v_actual = v_expected; END IF;
  IF v_operator = 'not_equals' THEN RETURN v_actual <> v_expected; END IF;
  IF v_operator = 'in' THEN RETURN v_matches; END IF;
  IF v_operator = 'not_in' THEN RETURN NOT v_matches; END IF;

  IF v_operator IN ('contains', 'not_contains') THEN
    IF jsonb_typeof(v_actual) = 'array' AND jsonb_typeof(v_expected) = 'array' THEN
      SELECT EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_actual) AS actual(value)
        JOIN jsonb_array_elements(v_expected) AS expected(value)
          ON expected.value = actual.value
      ) INTO v_matches;
    ELSIF jsonb_typeof(v_actual) = 'array' THEN
      SELECT EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_actual) AS actual(value)
        WHERE actual.value = v_expected
      ) INTO v_matches;
    ELSIF jsonb_typeof(v_expected) = 'array' THEN
      SELECT EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_expected) AS expected(value)
        WHERE expected.value = v_actual
      ) INTO v_matches;
    ELSE
      v_matches := v_actual = v_expected;
    END IF;
    RETURN CASE WHEN v_operator = 'not_contains' THEN NOT v_matches ELSE v_matches END;
  END IF;

  -- Preserve the client's forward-compatible behavior for unknown operators.
  RETURN TRUE;
END;
$function$;

REVOKE ALL ON FUNCTION private.visit_checklist_visibility_matches(JSONB, JSONB)
  FROM PUBLIC, anon, authenticated;

DO $repair$
DECLARE
  v_oid          OID;
  v_definition   TEXT;
  v_owner        OID;
  v_acl          ACLITEM[];
  v_is_definer   BOOLEAN;
  v_config       TEXT[];
  v_old_fragment TEXT := '      AND q.is_required = true';
  v_new_fragment TEXT := E'      AND q.is_required = true\r\n'
    || E'      AND private.visit_checklist_visibility_matches(\r\n'
    || E'        q.visibility_rule,\r\n'
    || E'        COALESCE((\r\n'
    || E'          SELECT jsonb_object_agg(\r\n'
    || E'            answer_question.question_code,\r\n'
    || E'            COALESCE(\r\n'
    || E'              NULLIF(response.value -> \'answer_json\', \'null\'::JSONB),\r\n'
    || E'              to_jsonb(response.value ->> \'answer_value\')\r\n'
    || E'            )\r\n'
    || E'          )\r\n'
    || E'          FROM jsonb_array_elements(p_responses) AS response(value)\r\n'
    || E'          JOIN public.visit_checklist_questions AS answer_question\r\n'
    || E'            ON answer_question.id = (response.value ->> \'question_id\')::UUID\r\n'
    || E'        ), \'{}\'::JSONB)\r\n'
    || E'      )';
  v_occurrences  INTEGER;
BEGIN
  SELECT p.oid, p.proowner, p.proacl, p.prosecdef, p.proconfig,
         pg_get_functiondef(p.oid)
  INTO v_oid, v_owner, v_acl, v_is_definer, v_config, v_definition
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'private'
    AND p.proname = 'complete_visit_item_atomic_impl'
    AND pg_get_function_identity_arguments(p.oid) =
      'p_operation_id uuid, p_item_id uuid, p_end_lat numeric, p_end_lng numeric, p_end_accuracy_m numeric, p_client_completed_at timestamp with time zone, p_device_timezone character varying, p_outcome_type character varying, p_outcome_notes text, p_responses jsonb, p_order_id uuid, p_collection_id uuid, p_gps_exception_reason text';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'private.complete_visit_item_atomic_impl(...) was not found';
  END IF;
  IF NOT v_is_definer OR v_config IS NULL OR NOT ('search_path=pg_catalog' = ANY(v_config)) THEN
    RAISE EXCEPTION 'complete_visit_item_atomic_impl has unexpected security properties';
  END IF;

  -- The replacement intentionally keeps the original required predicate, so
  -- detect an already-patched function before counting that predicate.
  IF position('private.visit_checklist_visibility_matches(' in v_definition) > 0 THEN
    RETURN;
  END IF;

  v_occurrences := (
    length(v_definition) - length(replace(v_definition, v_old_fragment, ''))
  ) / length(v_old_fragment);

  IF v_occurrences <> 1 THEN
    RAISE EXCEPTION 'unexpected completion visibility patch occurrence count: %', v_occurrences;
  END IF;

  v_definition := replace(v_definition, v_old_fragment, v_new_fragment);
  EXECUTE v_definition;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid = v_oid
      AND position('private.visit_checklist_visibility_matches(' in p.prosrc) > 0
      AND p.proowner = v_owner
      AND p.proacl IS NOT DISTINCT FROM v_acl
      AND p.prosecdef = v_is_definer
      AND p.proconfig IS NOT DISTINCT FROM v_config
  ) THEN
    RAISE EXCEPTION 'completion visibility repair verification failed';
  END IF;
END;
$repair$;

COMMIT;
