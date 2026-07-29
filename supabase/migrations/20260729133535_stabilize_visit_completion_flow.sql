BEGIN;

-- Keep enough private context to diagnose a failed field operation without
-- exposing request payloads or internal database errors through the Data API.
ALTER TABLE private.visit_operation_requests
  ADD COLUMN IF NOT EXISTS subject_id UUID,
  ADD COLUMN IF NOT EXISTS failure_stage VARCHAR(50),
  ADD COLUMN IF NOT EXISTS error_detail TEXT;

CREATE INDEX IF NOT EXISTS idx_visit_op_requests_subject
  ON private.visit_operation_requests(subject_id, created_at DESC)
  WHERE subject_id IS NOT NULL;

COMMENT ON COLUMN private.visit_operation_requests.subject_id IS
  'Primary business record affected by the operation (visit item for field execution operations).';
COMMENT ON COLUMN private.visit_operation_requests.failure_stage IS
  'Safe operational stage used for support diagnostics.';
COMMENT ON COLUMN private.visit_operation_requests.error_detail IS
  'Private server-side diagnostic detail. Never returned for internal errors.';

-- Preserve the existing deny-by-default model for the private operation table.
REVOKE ALL ON TABLE private.visit_operation_requests FROM PUBLIC, anon, authenticated;

-- Replace the generic completion error with a stable category while returning
-- the already-curated domain validation message to the rep. Internal errors
-- remain generic to the client and retain their detail only in the private log.
DO $repair$
DECLARE
  v_oid        OID;
  v_definition TEXT;
  v_owner      OID;
  v_acl        ACLITEM[];
  v_is_definer BOOLEAN;
  v_config     TEXT[];
  v_old_error_block TEXT := E'    IF SQLSTATE = ''P0001'' THEN\r\n'
    || E'      v_safe_code := ''DOMAIN_VALIDATION_FAILED'';\r\n'
    || E'      v_safe_message := ''تعذر إكمال الزيارة لعدم استيفاء الشروط أو فشل استيفاء الاستبيانات الإلزامية'';\r\n'
    || E'    ELSE\r\n'
    || E'      v_safe_code := ''INTERNAL_ERROR'';\r\n'
    || E'      v_safe_message := ''فشلت معالجة العملية بسبب خطأ داخلي في الخادم'';\r\n'
    || E'    END IF;';
  v_new_error_block TEXT := E'    -- VISIT_STRUCTURED_FAILURE_DIAGNOSTICS\r\n'
    || E'    IF SQLSTATE = ''P0001'' THEN\r\n'
    || E'      v_safe_code := CASE\r\n'
    || E'        WHEN SQLERRM ~ ''(استبيان|السؤال|القالب|الإجابة|الاختيار|التقييم|الصورة|Base64|Data URL)'' THEN ''SURVEY_VALIDATION_FAILED''\r\n'
    || E'        WHEN SQLERRM ~ ''(الموقع|الجغرافي|الإحداثيات|دقة)'' THEN ''GPS_VALIDATION_FAILED''\r\n'
    || E'        WHEN SQLERRM ~ ''(طلب المبيعات|سند التحصيل)'' THEN ''LINKED_DOCUMENT_VALIDATION_FAILED''\r\n'
    || E'        ELSE ''VISIT_STATE_INVALID''\r\n'
    || E'      END;\r\n'
    || E'      v_safe_message := LEFT(SQLERRM, 500);\r\n'
    || E'    ELSE\r\n'
    || E'      v_safe_code := ''INTERNAL_ERROR'';\r\n'
    || E'      v_safe_message := ''فشلت معالجة العملية بسبب خطأ داخلي في الخادم'';\r\n'
    || E'    END IF;';
  v_old_update TEXT := E'    UPDATE private.visit_operation_requests\r\n'
    || E'    SET status = ''failed'',\r\n'
    || E'        completed_at = clock_timestamp(),\r\n'
    || E'        error_code = v_safe_code,\r\n'
    || E'        result_json = jsonb_build_object(';
  v_new_update TEXT := E'    UPDATE private.visit_operation_requests\r\n'
    || E'    SET status = ''failed'',\r\n'
    || E'        completed_at = clock_timestamp(),\r\n'
    || E'        subject_id = p_item_id,\r\n'
    || E'        failure_stage = CASE\r\n'
    || E'          WHEN v_safe_code = ''SURVEY_VALIDATION_FAILED'' THEN ''survey_validation''\r\n'
    || E'          WHEN v_safe_code = ''GPS_VALIDATION_FAILED'' THEN ''gps_validation''\r\n'
    || E'          WHEN v_safe_code = ''LINKED_DOCUMENT_VALIDATION_FAILED'' THEN ''linked_document_validation''\r\n'
    || E'          WHEN v_safe_code = ''VISIT_STATE_INVALID'' THEN ''visit_state''\r\n'
    || E'          ELSE ''internal''\r\n'
    || E'        END,\r\n'
    || E'        error_detail = LEFT(format(''sqlstate=%s; message=%s'', SQLSTATE, SQLERRM), 2000),\r\n'
    || E'        error_code = v_safe_code,\r\n'
    || E'        result_json = jsonb_build_object(';
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

  IF position('VISIT_STRUCTURED_FAILURE_DIAGNOSTICS' in v_definition) = 0 THEN
    IF position(v_old_error_block in v_definition) = 0 THEN
      RAISE EXCEPTION 'completion error classification patch point was not found';
    END IF;
    IF position(v_old_update in v_definition) = 0 THEN
      RAISE EXCEPTION 'completion failure update patch point was not found';
    END IF;
    v_definition := replace(v_definition, v_old_error_block, v_new_error_block);
    v_definition := replace(v_definition, v_old_update, v_new_update);
    EXECUTE v_definition;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid = v_oid
      AND position('VISIT_STRUCTURED_FAILURE_DIAGNOSTICS' in p.prosrc) > 0
      AND p.proowner = v_owner
      AND p.proacl IS NOT DISTINCT FROM v_acl
      AND p.prosecdef = v_is_definer
      AND p.proconfig IS NOT DISTINCT FROM v_config
  ) THEN
    RAISE EXCEPTION 'completion diagnostics verification failed';
  END IF;
END;
$repair$;

-- Postgres Changes only emits tables included in the publication. Add the
-- three low-volume operational visit tables without rebuilding the existing
-- publication or affecting other modules.
DO $realtime$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'visit_plans'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.visit_plans;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'visit_plan_items'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.visit_plan_items;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'activities'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.activities;
    END IF;
  END IF;
END;
$realtime$;

COMMIT;
