BEGIN;

-- Completion requests can outlive a checklist-template refresh in the PWA.
-- Accept only the three options deliberately retired by the non-blocking v2
-- rollout, without putting those options back into the current UI.
-- Also turn a missing/weak end-location reading into an auditable GPS review
-- instead of blocking a rep whose start location was already recorded.
DO $repair$
DECLARE
  v_oid             OID;
  v_definition      TEXT;
  v_owner           OID;
  v_acl             ACLITEM[];
  v_is_definer      BOOLEAN;
  v_config          TEXT[];
  v_option_old      TEXT := E'        IF NOT EXISTS (\r\n'
    || E'          SELECT 1 FROM jsonb_array_elements(v_q_options) opt\r\n'
    || E'          WHERE (jsonb_typeof(opt) = \'string\' AND opt #>> \'{}\' = v_resp_value)\r\n'
    || E'             OR (jsonb_typeof(opt) = \'object\' AND (opt ->> \'value\' = v_resp_value OR opt ->> \'label\' = v_resp_value))\r\n'
    || E'        ) THEN\r\n'
    || E'          RAISE EXCEPTION \'قيمة الاختيار غير مطابقة للخيارات المتاحة\';\r\n'
    || E'        END IF;';
  v_option_new      TEXT := E'        -- VISIT_LEGACY_OPTION_COMPATIBILITY\r\n'
    || E'        IF NOT EXISTS (\r\n'
    || E'          SELECT 1 FROM jsonb_array_elements(v_q_options) opt\r\n'
    || E'          WHERE (jsonb_typeof(opt) = \'string\' AND opt #>> \'{}\' = v_resp_value)\r\n'
    || E'             OR (jsonb_typeof(opt) = \'object\' AND (opt ->> \'value\' = v_resp_value OR opt ->> \'label\' = v_resp_value))\r\n'
    || E'        ) AND NOT EXISTS (\r\n'
    || E'          SELECT 1\r\n'
    || E'          FROM public.visit_checklist_questions legacy_question\r\n'
    || E'          WHERE legacy_question.id = v_resp_question_id\r\n'
    || E'            AND (legacy_question.question_code, v_resp_value) IN (\r\n'
    || E'              (\'sales.no_order_reason\', \'تم تنفيذ طلب\'),\r\n'
    || E'              (\'collection.failure_reason\', \'تم السداد بالكامل\'),\r\n'
    || E'              (\'followup.stop_reason\', \'لا يوجد توقف\')\r\n'
    || E'            )\r\n'
    || E'        ) THEN\r\n'
    || E'          RAISE EXCEPTION \'قيمة الاختيار غير مطابقة للخيارات المتاحة\';\r\n'
    || E'        END IF;';
  v_gps_old         TEXT := E'        IF NULLIF(BTRIM(p_gps_exception_reason), \'\') IS NULL THEN\r\n'
    || E'          RAISE EXCEPTION \'يتطلب إكمال الزيارة تسجيل مبرر تجاوز للتحقق الجغرافي (gps_exception_reason)\';\r\n'
    || E'        END IF;\r\n'
    || E'        IF char_length(p_gps_exception_reason) > 1000 THEN\r\n'
    || E'          RAISE EXCEPTION \'مبرر تجاوز التحقق الجغرافي يجب ألا يتجاوز 1000 حرف\';\r\n'
    || E'        END IF;\r\n'
    || E'        v_gps_exc_reason := p_gps_exception_reason;\r\n'
    || E'        v_gps_exc_req_by := v_actor_id;';
  v_gps_new         TEXT := E'        -- VISIT_NON_BLOCKING_END_GPS\r\n'
    || E'        IF NULLIF(BTRIM(p_gps_exception_reason), \'\') IS NULL THEN\r\n'
    || E'          v_gps_exc_reason := CASE v_end_gps_status\r\n'
    || E'            WHEN \'no_coordinates\' THEN \'تعذر الحصول على إحداثيات نهاية الزيارة من الجهاز؛ أحيلت للمراجعة دون تعطيل المندوب\'\r\n'
    || E'            WHEN \'failed_accuracy\' THEN \'دقة موقع نهاية الزيارة أقل من الحد المطلوب؛ أحيلت للمراجعة دون تعطيل المندوب\'\r\n'
    || E'            WHEN \'failed_distance\' THEN \'موقع نهاية الزيارة خارج النطاق المتوقع؛ أحيلت للمراجعة دون تعطيل المندوب\'\r\n'
    || E'            ELSE \'تعذر اعتماد التحقق الجغرافي للزيارة؛ أحيلت للمراجعة دون تعطيل المندوب\'\r\n'
    || E'          END;\r\n'
    || E'        ELSE\r\n'
    || E'          IF char_length(p_gps_exception_reason) > 1000 THEN\r\n'
    || E'            RAISE EXCEPTION \'مبرر تجاوز التحقق الجغرافي يجب ألا يتجاوز 1000 حرف\';\r\n'
    || E'          END IF;\r\n'
    || E'          v_gps_exc_reason := p_gps_exception_reason;\r\n'
    || E'        END IF;\r\n'
    || E'        v_gps_exc_req_by := v_actor_id;';
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

  IF position('VISIT_LEGACY_OPTION_COMPATIBILITY' in v_definition) = 0 THEN
    IF position(v_option_old in v_definition) = 0 THEN
      RAISE EXCEPTION 'legacy option validation patch point was not found';
    END IF;
    v_definition := replace(v_definition, v_option_old, v_option_new);
  END IF;

  IF position('VISIT_NON_BLOCKING_END_GPS' in v_definition) = 0 THEN
    IF position(v_gps_old in v_definition) = 0 THEN
      RAISE EXCEPTION 'end GPS patch point was not found';
    END IF;
    v_definition := replace(v_definition, v_gps_old, v_gps_new);
  END IF;

  EXECUTE v_definition;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    WHERE p.oid = v_oid
      AND position('VISIT_LEGACY_OPTION_COMPATIBILITY' in p.prosrc) > 0
      AND position('VISIT_NON_BLOCKING_END_GPS' in p.prosrc) > 0
      AND p.proowner = v_owner
      AND p.proacl IS NOT DISTINCT FROM v_acl
      AND p.prosecdef = v_is_definer
      AND p.proconfig IS NOT DISTINCT FROM v_config
  ) THEN
    RAISE EXCEPTION 'visit completion compatibility verification failed';
  END IF;
END;
$repair$;

COMMIT;
