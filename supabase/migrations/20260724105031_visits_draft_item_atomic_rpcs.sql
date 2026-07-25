BEGIN;

-- =============================================================================
-- EDARA v2 — 20260724105031_visits_draft_item_atomic_rpcs.sql
-- Migration Phase Draft Items: Atomic RPCs for Adding & Deleting Visit Plan Items
--
-- ⚠️ تنبيه: هذا الملف للإنشاء والتوثيق المرجعي فقط، وممنوع تطبيقه مباشرة على الإنتاج
-- =============================================================================

-- =============================================================================
-- 1. إضافة بند إلى خطة الزيارة ذرياً (Add Visit Plan Item Atomic)
-- =============================================================================

CREATE OR REPLACE FUNCTION private.add_visit_plan_item_atomic_impl(
  p_operation_id           UUID,
  p_plan_id                UUID,
  p_customer_id            UUID,
  p_customer_branch_id     UUID DEFAULT NULL,
  p_purpose                TEXT DEFAULT NULL,
  p_purpose_type           VARCHAR(50) DEFAULT NULL,
  p_priority               VARCHAR(20) DEFAULT 'normal',
  p_planned_time           TIME DEFAULT NULL,
  p_estimated_duration_min INT DEFAULT 30,
  p_client_event_at        TIMESTAMPTZ DEFAULT NULL,
  p_device_timezone        VARCHAR(100) DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  v_actor_id            UUID;
  v_payload             JSONB;
  v_hash                VARCHAR(64);
  v_req_status          VARCHAR(20);
  v_req_result          JSONB;
  v_req_actor           UUID;
  v_req_op              VARCHAR(100);
  v_req_hash            VARCHAR(64);

  v_plan_status         VARCHAR(20);
  v_plan_employee_id    UUID;
  v_plan_branch_id      UUID;
  v_creator_employee_id UUID;
  v_creator_branch_id   UUID;
  v_has_access          BOOLEAN;

  v_cust_lat            NUMERIC(10,7);
  v_cust_lng            NUMERIC(10,7);

  v_cb_cust_id          UUID;
  v_cb_lat              NUMERIC(10,7);
  v_cb_lng              NUMERIC(10,7);

  v_exp_source          VARCHAR(50);
  v_exp_id              UUID;
  v_exp_lat             NUMERIC(10,7);
  v_exp_lng             NUMERIC(10,7);

  v_new_sequence        INT;
  v_new_item_id         UUID;
  v_result_data         JSONB;
BEGIN
  -- 1. Idempotency Check
  IF p_operation_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'add_visit_plan_item_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'INVALID_OPERATION_ID', 'message', 'معرف العملية مطلوب'));
  END IF;

  IF p_plan_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'add_visit_plan_item_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'INVALID_PLAN_ID', 'message', 'معرف الخطة مطلوب'));
  END IF;

  IF p_customer_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'add_visit_plan_item_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'INVALID_CUSTOMER_ID', 'message', 'معرف العميل مطلوب'));
  END IF;

  -- Validation: Priority
  IF p_priority IS NOT NULL AND p_priority NOT IN ('high', 'normal', 'low') THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'add_visit_plan_item_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'INVALID_PRIORITY', 'message', 'درجة الأولوية غير صالحة، يجب أن تكون high أو normal أو low'));
  END IF;

  -- Validation: Purpose Type
  IF p_purpose_type IS NOT NULL AND p_purpose_type NOT IN ('sales', 'collection', 'activation', 'promotion', 'followup', 'service') THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'add_visit_plan_item_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'INVALID_PURPOSE_TYPE', 'message', 'نوع الغرض غير صالح'));
  END IF;

  -- Validation: Duration Bounds
  IF p_estimated_duration_min IS NOT NULL AND (p_estimated_duration_min < 5 OR p_estimated_duration_min > 480) THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'add_visit_plan_item_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'INVALID_DURATION', 'message', 'المدة المتوقعة يجب أن تكون بين 5 و 480 دقيقة'));
  END IF;

  v_actor_id := auth.uid();
  IF v_actor_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'add_visit_plan_item_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'UNAUTHORIZED', 'message', 'المستخدم غير مصرح له'));
  END IF;

  v_payload := jsonb_build_object(
    'operation_name', 'add_visit_plan_item_atomic',
    'plan_id', p_plan_id,
    'customer_id', p_customer_id,
    'customer_branch_id', p_customer_branch_id,
    'purpose', p_purpose,
    'purpose_type', p_purpose_type,
    'priority', COALESCE(p_priority, 'normal'),
    'planned_time', p_planned_time,
    'estimated_duration_min', COALESCE(p_estimated_duration_min, 30),
    'client_event_at', p_client_event_at,
    'device_timezone', p_device_timezone
  );
  v_hash := encode(extensions.digest(v_payload::text, 'sha256'), 'hex');

  INSERT INTO private.visit_operation_requests (operation_id, actor_id, operation_name, request_hash, status, created_at)
  VALUES (p_operation_id, v_actor_id, 'add_visit_plan_item_atomic', v_hash, 'pending', clock_timestamp())
  ON CONFLICT DO NOTHING;

  SELECT status, result_json, actor_id, operation_name, request_hash
  INTO v_req_status, v_req_result, v_req_actor, v_req_op, v_req_hash
  FROM private.visit_operation_requests
  WHERE operation_id = p_operation_id
  FOR UPDATE;

  IF v_req_actor IS DISTINCT FROM v_actor_id OR v_req_op IS DISTINCT FROM 'add_visit_plan_item_atomic' OR v_req_hash IS DISTINCT FROM v_hash THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'add_visit_plan_item_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'IDEMPOTENCY_KEY_CONFLICT', 'message', 'تعارض في معرّف العملية'));
  END IF;

  IF v_req_status = 'completed' THEN RETURN jsonb_build_object('ok', true, 'operation_id', p_operation_id, 'operation', 'add_visit_plan_item_atomic', 'replayed', true, 'data', v_req_result);
  ELSIF v_req_status = 'failed' THEN RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'add_visit_plan_item_atomic', 'replayed', true, 'error', v_req_result->'error');
  ELSIF v_req_status = 'processing' THEN RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'add_visit_plan_item_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'RETRYABLE_ERROR', 'message', 'العملية قيد المعالجة'));
  END IF;

  UPDATE private.visit_operation_requests SET status = 'processing', started_at = clock_timestamp(), updated_at = clock_timestamp() WHERE operation_id = p_operation_id;

  BEGIN
    -- 2. Lock Plan FOR UPDATE
    SELECT status, employee_id, organizational_branch_id
    INTO v_plan_status, v_plan_employee_id, v_plan_branch_id
    FROM public.visit_plans
    WHERE id = p_plan_id
    FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'خطة الزيارة غير موجودة'; END IF;
    IF v_plan_status != 'draft' THEN RAISE EXCEPTION 'لا يمكن إضافة بند إلا لخطة في حالة مسودة (draft)'; END IF;

    -- 3. Authorization Check (Requires visit_plans.create explicitly)
    IF NOT (SELECT public.check_permission(v_actor_id, 'visit_plans.create')) THEN
      RAISE EXCEPTION 'ليس لديك صلاحية إضافة بنود لخطة الزيارة (تتطلب visit_plans.create)';
    END IF;

    SELECT id, branch_id INTO v_creator_employee_id, v_creator_branch_id FROM public.hr_employees WHERE user_id = v_actor_id;

    v_has_access :=
      (v_creator_employee_id IS NOT NULL
       AND v_creator_employee_id = v_plan_employee_id)
      OR public.check_permission(v_actor_id, 'visit_plans.read_all')
      OR (
        public.check_permission(v_actor_id, 'visit_plans.read_team')
        AND v_creator_branch_id IS NOT NULL
        AND v_creator_branch_id = v_plan_branch_id
      );

    IF NOT v_has_access THEN RAISE EXCEPTION 'غير مصرح لك بإضافة بنود لهذه الخطة (تتجاوز نطاق الوصول المسموح)'; END IF;

    -- 4. Check Customer existence
    SELECT latitude, longitude INTO v_cust_lat, v_cust_lng FROM public.customers WHERE id = p_customer_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'العميل غير موجود'; END IF;

    -- 5. Check Customer Branch if provided
    IF p_customer_branch_id IS NOT NULL THEN
      SELECT customer_id, latitude, longitude INTO v_cb_cust_id, v_cb_lat, v_cb_lng FROM public.customer_branches WHERE id = p_customer_branch_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'فرع العميل المحدد غير موجود'; END IF;
      IF v_cb_cust_id != p_customer_id THEN RAISE EXCEPTION 'فرع العميل لا ينتمي للعميل المحدد'; END IF;
    END IF;

    -- 6. Check duplicate customer in plan
    IF EXISTS (SELECT 1 FROM public.visit_plan_items WHERE plan_id = p_plan_id AND customer_id = p_customer_id) THEN
      RAISE EXCEPTION 'العميل موجود بالفعل في هذه الخطة';
    END IF;

    -- 7. Lock items to calculate sequence
    PERFORM 1 FROM public.visit_plan_items WHERE plan_id = p_plan_id ORDER BY sequence FOR UPDATE;

    SELECT COALESCE(MAX(sequence), 0) + 1 INTO v_new_sequence FROM public.visit_plan_items WHERE plan_id = p_plan_id;

    -- 8. Extract location snapshot (customer branch first, then customer, with strict range check)
    IF p_customer_branch_id IS NOT NULL
       AND v_cb_lat IS NOT NULL AND v_cb_lat BETWEEN -90 AND 90
       AND v_cb_lng IS NOT NULL AND v_cb_lng BETWEEN -180 AND 180 THEN
      v_exp_source := 'customer_branch';
      v_exp_id     := p_customer_branch_id;
      v_exp_lat    := v_cb_lat;
      v_exp_lng    := v_cb_lng;
    ELSIF v_cust_lat IS NOT NULL AND v_cust_lat BETWEEN -90 AND 90
       AND v_cust_lng IS NOT NULL AND v_cust_lng BETWEEN -180 AND 180 THEN
      v_exp_source := 'customer';
      v_exp_id     := p_customer_id;
      v_exp_lat    := v_cust_lat;
      v_exp_lng    := v_cust_lng;
    ELSE
      v_exp_source := NULL;
      v_exp_id     := NULL;
      v_exp_lat    := NULL;
      v_exp_lng    := NULL;
    END IF;

    v_new_item_id := pg_catalog.gen_random_uuid();

    -- 9. Insert item
    INSERT INTO public.visit_plan_items (
      id, plan_id, customer_id, customer_branch_id, sequence, planned_time, estimated_duration_min,
      priority, purpose, purpose_type, status, expected_location_source, expected_location_id,
      expected_lat, expected_lng, created_at, updated_at
    ) VALUES (
      v_new_item_id, p_plan_id, p_customer_id, p_customer_branch_id, v_new_sequence, p_planned_time,
      COALESCE(p_estimated_duration_min, 30), COALESCE(p_priority, 'normal'), p_purpose, p_purpose_type,
      'pending', v_exp_source, v_exp_id, v_exp_lat, v_exp_lng, clock_timestamp(), clock_timestamp()
    );

    -- 10. Recalculate plan counts
    PERFORM private.recalculate_visit_plan_counts(p_plan_id);

    v_result_data := jsonb_build_object('item_id', v_new_item_id, 'plan_id', p_plan_id, 'sequence', v_new_sequence);

    UPDATE private.visit_operation_requests
    SET status = 'completed', completed_at = clock_timestamp(), result_json = v_result_data, updated_at = clock_timestamp()
    WHERE operation_id = p_operation_id;

    RETURN jsonb_build_object('ok', true, 'operation_id', p_operation_id, 'operation', 'add_visit_plan_item_atomic', 'replayed', false, 'data', v_result_data);

  EXCEPTION WHEN OTHERS THEN
    DECLARE
      v_safe_code    VARCHAR(50);
      v_safe_message VARCHAR(255);
    BEGIN
      IF SQLSTATE = 'P0001' THEN
        v_safe_code := 'DOMAIN_VALIDATION_FAILED';
        v_safe_message := 'تعذر تنفيذ العملية لعدم استيفاء شروطها';
      ELSE
        v_safe_code := 'INTERNAL_ERROR';
        v_safe_message := 'فشلت معالجة العملية بسبب خطأ داخلي في الخادم';
      END IF;

      UPDATE private.visit_operation_requests
      SET status = 'failed', completed_at = clock_timestamp(), error_code = v_safe_code, result_json = jsonb_build_object('error', jsonb_build_object('code', v_safe_code, 'message', v_safe_message)), updated_at = clock_timestamp()
      WHERE operation_id = p_operation_id;

      RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'add_visit_plan_item_atomic', 'replayed', false, 'error', jsonb_build_object('code', v_safe_code, 'message', v_safe_message));
    END;
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.add_visit_plan_item_atomic(
  p_operation_id           UUID,
  p_plan_id                UUID,
  p_customer_id            UUID,
  p_customer_branch_id     UUID DEFAULT NULL,
  p_purpose                TEXT DEFAULT NULL,
  p_purpose_type           VARCHAR(50) DEFAULT NULL,
  p_priority               VARCHAR(20) DEFAULT 'normal',
  p_planned_time           TIME DEFAULT NULL,
  p_estimated_duration_min INT DEFAULT 30,
  p_client_event_at        TIMESTAMPTZ DEFAULT NULL,
  p_device_timezone        VARCHAR(100) DEFAULT NULL
)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
  SELECT private.add_visit_plan_item_atomic_impl(
    p_operation_id, p_plan_id, p_customer_id, p_customer_branch_id, p_purpose,
    p_purpose_type, p_priority, p_planned_time, p_estimated_duration_min,
    p_client_event_at, p_device_timezone
  );
$$;

REVOKE ALL ON FUNCTION private.add_visit_plan_item_atomic_impl(UUID, UUID, UUID, UUID, TEXT, VARCHAR, VARCHAR, TIME, INT, TIMESTAMPTZ, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.add_visit_plan_item_atomic_impl(UUID, UUID, UUID, UUID, TEXT, VARCHAR, VARCHAR, TIME, INT, TIMESTAMPTZ, VARCHAR) TO authenticated;

REVOKE ALL ON FUNCTION public.add_visit_plan_item_atomic(UUID, UUID, UUID, UUID, TEXT, VARCHAR, VARCHAR, TIME, INT, TIMESTAMPTZ, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_visit_plan_item_atomic(UUID, UUID, UUID, UUID, TEXT, VARCHAR, VARCHAR, TIME, INT, TIMESTAMPTZ, VARCHAR) TO authenticated;


-- =============================================================================
-- 2. حذف بند من خطة الزيارة ذرياً (Delete Visit Plan Item Atomic)
-- =============================================================================

CREATE OR REPLACE FUNCTION private.delete_visit_plan_item_atomic_impl(
  p_operation_id    UUID,
  p_item_id         UUID,
  p_client_event_at TIMESTAMPTZ DEFAULT NULL,
  p_device_timezone VARCHAR(100) DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  v_actor_id            UUID;
  v_payload             JSONB;
  v_hash                VARCHAR(64);
  v_req_status          VARCHAR(20);
  v_req_result          JSONB;
  v_req_actor           UUID;
  v_req_op              VARCHAR(100);
  v_req_hash            VARCHAR(64);

  v_plan_id             UUID;
  v_item_status         VARCHAR(20);
  v_start_lat           NUMERIC(10,7);
  v_server_started_at   TIMESTAMPTZ;
  v_client_started_at   TIMESTAMPTZ;

  v_plan_status         VARCHAR(20);
  v_plan_employee_id    UUID;
  v_plan_branch_id      UUID;
  v_creator_employee_id UUID;
  v_creator_branch_id   UUID;
  v_has_access          BOOLEAN;
  v_result_data         JSONB;
BEGIN
  -- 1. Idempotency Check
  IF p_operation_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'delete_visit_plan_item_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'INVALID_OPERATION_ID', 'message', 'معرف العملية مطلوب'));
  END IF;

  IF p_item_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'delete_visit_plan_item_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'INVALID_ITEM_ID', 'message', 'معرف البند مطلوب'));
  END IF;

  v_actor_id := auth.uid();
  IF v_actor_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'delete_visit_plan_item_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'UNAUTHORIZED', 'message', 'المستخدم غير مصرح له'));
  END IF;

  v_payload := jsonb_build_object(
    'operation_name', 'delete_visit_plan_item_atomic',
    'item_id', p_item_id,
    'client_event_at', p_client_event_at,
    'device_timezone', p_device_timezone
  );
  v_hash := encode(extensions.digest(v_payload::text, 'sha256'), 'hex');

  INSERT INTO private.visit_operation_requests (operation_id, actor_id, operation_name, request_hash, status, created_at)
  VALUES (p_operation_id, v_actor_id, 'delete_visit_plan_item_atomic', v_hash, 'pending', clock_timestamp())
  ON CONFLICT DO NOTHING;

  SELECT status, result_json, actor_id, operation_name, request_hash
  INTO v_req_status, v_req_result, v_req_actor, v_req_op, v_req_hash
  FROM private.visit_operation_requests
  WHERE operation_id = p_operation_id
  FOR UPDATE;

  IF v_req_actor IS DISTINCT FROM v_actor_id OR v_req_op IS DISTINCT FROM 'delete_visit_plan_item_atomic' OR v_req_hash IS DISTINCT FROM v_hash THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'delete_visit_plan_item_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'IDEMPOTENCY_KEY_CONFLICT', 'message', 'تعارض في معرّف العملية'));
  END IF;

  IF v_req_status = 'completed' THEN RETURN jsonb_build_object('ok', true, 'operation_id', p_operation_id, 'operation', 'delete_visit_plan_item_atomic', 'replayed', true, 'data', v_req_result);
  ELSIF v_req_status = 'failed' THEN RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'delete_visit_plan_item_atomic', 'replayed', true, 'error', v_req_result->'error');
  ELSIF v_req_status = 'processing' THEN RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'delete_visit_plan_item_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'RETRYABLE_ERROR', 'message', 'العملية قيد المعالجة'));
  END IF;

  UPDATE private.visit_operation_requests SET status = 'processing', started_at = clock_timestamp(), updated_at = clock_timestamp() WHERE operation_id = p_operation_id;

  BEGIN
    -- 2. Lock Item FOR UPDATE
    SELECT plan_id, status, start_lat, server_started_at, client_started_at
    INTO v_plan_id, v_item_status, v_start_lat, v_server_started_at, v_client_started_at
    FROM public.visit_plan_items
    WHERE id = p_item_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'بند الزيارة غير موجود';
    END IF;

    IF v_item_status != 'pending' THEN RAISE EXCEPTION 'لا يمكن حذف بند إلا إذا كان في حالة pending'; END IF;

    IF v_start_lat IS NOT NULL OR v_server_started_at IS NOT NULL OR v_client_started_at IS NOT NULL THEN
      RAISE EXCEPTION 'لا يمكن حذف بند زيارة تم بدء تنفيذه ميدانياً';
    END IF;

    -- Lock Plan FOR UPDATE
    SELECT status, employee_id, organizational_branch_id
    INTO v_plan_status, v_plan_employee_id, v_plan_branch_id
    FROM public.visit_plans
    WHERE id = v_plan_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'خطة الزيارة المرتبطة بالبند غير موجودة';
    END IF;

    IF v_plan_status != 'draft' THEN RAISE EXCEPTION 'لا يمكن حذف بند إلا من خطة في حالة مسودة (draft)'; END IF;

    -- 3. Authorization Check (Requires visit_plans.create explicitly)
    IF NOT (SELECT public.check_permission(v_actor_id, 'visit_plans.create')) THEN
      RAISE EXCEPTION 'ليس لديك صلاحية حذف بنود من خطة الزيارة (تتطلب visit_plans.create)';
    END IF;

    SELECT id, branch_id INTO v_creator_employee_id, v_creator_branch_id FROM public.hr_employees WHERE user_id = v_actor_id;

    v_has_access :=
      (v_creator_employee_id IS NOT NULL
       AND v_creator_employee_id = v_plan_employee_id)
      OR public.check_permission(v_actor_id, 'visit_plans.read_all')
      OR (
        public.check_permission(v_actor_id, 'visit_plans.read_team')
        AND v_creator_branch_id IS NOT NULL
        AND v_creator_branch_id = v_plan_branch_id
      );

    IF NOT v_has_access THEN RAISE EXCEPTION 'غير مصرح لك بحذف بنود من هذه الخطة (تتجاوز نطاق الوصول المسموح)'; END IF;

    -- 4. Check for linked activity
    IF EXISTS (SELECT 1 FROM public.activities WHERE visit_plan_item_id = p_item_id AND deleted_at IS NULL) THEN
      RAISE EXCEPTION 'لا يمكن حذف بند زيارة مرتبطة بنشاط ميداني مُسجّل';
    END IF;

    -- 5. Delete Item
    DELETE FROM public.visit_plan_items WHERE id = p_item_id;

    -- 6. Recalculate plan counts
    PERFORM private.recalculate_visit_plan_counts(v_plan_id);

    v_result_data := jsonb_build_object('item_id', p_item_id, 'plan_id', v_plan_id);

    UPDATE private.visit_operation_requests
    SET status = 'completed', completed_at = clock_timestamp(), result_json = v_result_data, updated_at = clock_timestamp()
    WHERE operation_id = p_operation_id;

    RETURN jsonb_build_object('ok', true, 'operation_id', p_operation_id, 'operation', 'delete_visit_plan_item_atomic', 'replayed', false, 'data', v_result_data);

  EXCEPTION WHEN OTHERS THEN
    DECLARE
      v_safe_code    VARCHAR(50);
      v_safe_message VARCHAR(255);
    BEGIN
      IF SQLSTATE = 'P0001' THEN
        v_safe_code := 'DOMAIN_VALIDATION_FAILED';
        v_safe_message := 'تعذر تنفيذ العملية لعدم استيفاء شروطها';
      ELSE
        v_safe_code := 'INTERNAL_ERROR';
        v_safe_message := 'فشلت معالجة العملية بسبب خطأ داخلي في الخادم';
      END IF;

      UPDATE private.visit_operation_requests
      SET status = 'failed', completed_at = clock_timestamp(), error_code = v_safe_code, result_json = jsonb_build_object('error', jsonb_build_object('code', v_safe_code, 'message', v_safe_message)), updated_at = clock_timestamp()
      WHERE operation_id = p_operation_id;

      RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'delete_visit_plan_item_atomic', 'replayed', false, 'error', jsonb_build_object('code', v_safe_code, 'message', v_safe_message));
    END;
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_visit_plan_item_atomic(
  p_operation_id    UUID,
  p_item_id         UUID,
  p_client_event_at TIMESTAMPTZ DEFAULT NULL,
  p_device_timezone VARCHAR(100) DEFAULT NULL
)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
  SELECT private.delete_visit_plan_item_atomic_impl(
    p_operation_id, p_item_id, p_client_event_at, p_device_timezone
  );
$$;

REVOKE ALL ON FUNCTION private.delete_visit_plan_item_atomic_impl(UUID, UUID, TIMESTAMPTZ, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.delete_visit_plan_item_atomic_impl(UUID, UUID, TIMESTAMPTZ, VARCHAR) TO authenticated;

REVOKE ALL ON FUNCTION public.delete_visit_plan_item_atomic(UUID, UUID, TIMESTAMPTZ, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_visit_plan_item_atomic(UUID, UUID, TIMESTAMPTZ, VARCHAR) TO authenticated;

COMMIT;
