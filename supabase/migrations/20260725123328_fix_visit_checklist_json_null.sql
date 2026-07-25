BEGIN;

-- Forward-only repair: Postgres JSONB `null` is a JSON value, not SQL NULL.
-- Normalize it before validating scalar checklist responses.
DO $repair$
DECLARE
  v_oid          OID;
  v_definition   TEXT;
  v_owner        OID;
  v_acl          ACLITEM[];
  v_is_definer   BOOLEAN;
  v_config       TEXT[];
  v_old_count    INTEGER;
BEGIN
  SELECT p.oid, p.proowner, p.proacl, p.prosecdef, p.proconfig
  INTO v_oid, v_owner, v_acl, v_is_definer, v_config
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'private'
    AND p.proname = 'complete_visit_item_atomic_impl'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) =
      'p_operation_id uuid, p_item_id uuid, p_end_lat numeric, p_end_lng numeric, p_end_accuracy_m numeric, p_client_completed_at timestamp with time zone, p_device_timezone character varying, p_outcome_type character varying, p_outcome_notes text, p_responses jsonb, p_order_id uuid, p_collection_id uuid, p_gps_exception_reason text';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'private.complete_visit_item_atomic_impl(...) was not found';
  END IF;

  IF NOT v_is_definer OR v_config IS NULL OR NOT ('search_path=pg_catalog' = ANY(v_config)) THEN
    RAISE EXCEPTION 'private.complete_visit_item_atomic_impl(...) has unexpected security properties';
  END IF;

  SELECT (
    pg_catalog.length(p.prosrc)
    - pg_catalog.length(pg_catalog.replace(
        p.prosrc,
        'v_resp_json := v_resp_item -> ''answer_json'';',
        ''
      ))
  ) / pg_catalog.length('v_resp_json := v_resp_item -> ''answer_json'';')
  INTO v_old_count
  FROM pg_catalog.pg_proc p
  WHERE p.oid = v_oid;

  IF v_old_count = 0 THEN
    IF EXISTS (
      SELECT 1
      FROM pg_catalog.pg_proc p
      WHERE p.oid = v_oid
        AND p.prosrc LIKE '%v_resp_json := NULLIF(v_resp_item -> ''answer_json'', ''null''::JSONB);%'
    ) THEN
      RETURN;
    END IF;
    RAISE EXCEPTION 'expected checklist JSON-null defect was not found and the corrected expression is absent';
  END IF;

  IF v_old_count <> 1 THEN
    RAISE EXCEPTION 'unexpected checklist JSON-null occurrence count: %', v_old_count;
  END IF;

  SELECT pg_catalog.pg_get_functiondef(v_oid) INTO v_definition;
  v_definition := pg_catalog.replace(
    v_definition,
    'v_resp_json := v_resp_item -> ''answer_json'';',
    'v_resp_json := NULLIF(v_resp_item -> ''answer_json'', ''null''::JSONB);'
  );
  EXECUTE v_definition;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc p
    WHERE p.oid = v_oid
      AND (
        p.prosrc LIKE '%v_resp_json := v_resp_item -> ''answer_json'';%'
        OR p.prosrc NOT LIKE '%v_resp_json := NULLIF(v_resp_item -> ''answer_json'', ''null''::JSONB);%'
        OR p.proowner IS DISTINCT FROM v_owner
        OR p.proacl IS DISTINCT FROM v_acl
        OR p.prosecdef IS DISTINCT FROM v_is_definer
        OR p.proconfig IS DISTINCT FROM v_config
      )
  ) THEN
    RAISE EXCEPTION 'complete_visit_item_atomic_impl JSON-null repair verification failed';
  END IF;
END;
$repair$;

COMMIT;
