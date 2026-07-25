BEGIN;

-- =============================================================================
-- EDARA v2 — visits_plan_detail_gap_rpcs.sql
-- سد الفجوات المتبقية في التنفيذ الذري: إعادة الجدولة بتاريخ، وإنهاء اليومية (Missed)
-- =============================================================================

-- =============================================================================
-- 1. إعادة الجدولة بتاريخ (Reschedule to Date)
-- =============================================================================

CREATE OR REPLACE FUNCTION private.reschedule_visit_item_to_date_atomic_impl(
  p_operation_id UUID,
  p_item_id UUID,
  p_target_date DATE,
  p_reschedule_reason TEXT,
  p_planned_time TIME,
  p_client_event_at TIMESTAMPTZ,
  p_device_timezone VARCHAR(100)
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

  v_source_plan_id      UUID;
  v_source_plan_status  VARCHAR(20);
  v_source_plan_type    VARCHAR(50);
  v_source_employee_id  UUID;
  v_source_branch_id    UUID;
  v_item_status         VARCHAR(20);
  v_target_plan_id      UUID;
  v_target_plan_status  VARCHAR(20);
  v_new_sequence        INT;
  v_new_item_id         UUID;

  v_customer_id         UUID;
  v_customer_branch_id  UUID;
  v_purpose             TEXT;
  v_purpose_type        VARCHAR(50);
  v_priority            VARCHAR(20);
  v_estimated_duration  INT;

  v_creator_employee_id UUID;
  v_creator_branch_id   UUID;
  v_has_access          BOOLEAN;
BEGIN
  -- 1. Idempotency Check
  IF p_operation_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'reschedule_visit_item_to_date_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'INVALID_OPERATION_ID', 'message', 'معرف العملية مطلوب'));
  END IF;

  IF p_item_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'reschedule_visit_item_to_date_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'INVALID_ITEM_ID', 'message', 'معرف البند مطلوب'));
  END IF;

  IF p_target_date IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'reschedule_visit_item_to_date_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'INVALID_TARGET_DATE', 'message', 'تاريخ الوجهة مطلوب'));
  END IF;

  v_actor_id := auth.uid();
  IF v_actor_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'reschedule_visit_item_to_date_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'UNAUTHORIZED', 'message', 'المستخدم غير مصرح له'));
  END IF;

  IF NULLIF(BTRIM(p_reschedule_reason), '') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'reschedule_visit_item_to_date_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'INVALID_REASON', 'message', 'سبب إعادة الجدولة مطلوب'));
  END IF;

  v_payload := jsonb_build_object(
    'operation_name', 'reschedule_visit_item_to_date_atomic',
    'item_id', p_item_id,
    'target_date', p_target_date,
    'reschedule_reason', p_reschedule_reason,
    'planned_time', p_planned_time,
    'client_event_at', p_client_event_at,
    'device_timezone', p_device_timezone
  );
  v_hash := encode(extensions.digest(v_payload::text, 'sha256'), 'hex');

  INSERT INTO private.visit_operation_requests (operation_id, actor_id, operation_name, request_hash, status, created_at)
  VALUES (p_operation_id, v_actor_id, 'reschedule_visit_item_to_date_atomic', v_hash, 'pending', clock_timestamp())
  ON CONFLICT DO NOTHING;

  SELECT status, result_json, actor_id, operation_name, request_hash
  INTO v_req_status, v_req_result, v_req_actor, v_req_op, v_req_hash
  FROM private.visit_operation_requests
  WHERE operation_id = p_operation_id
  FOR UPDATE;

  IF v_req_actor IS DISTINCT FROM v_actor_id OR v_req_op IS DISTINCT FROM 'reschedule_visit_item_to_date_atomic' OR v_req_hash IS DISTINCT FROM v_hash THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'reschedule_visit_item_to_date_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'IDEMPOTENCY_KEY_CONFLICT', 'message', 'تعارض في معرّف العملية (idempotency_key_conflict)'));
  END IF;

  IF v_req_status = 'completed' THEN RETURN jsonb_build_object('ok', true, 'operation_id', p_operation_id, 'operation', 'reschedule_visit_item_to_date_atomic', 'replayed', true, 'data', v_req_result);
  ELSIF v_req_status = 'failed' THEN RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'reschedule_visit_item_to_date_atomic', 'replayed', true, 'error', v_req_result->'error');
  ELSIF v_req_status = 'processing' THEN RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'reschedule_visit_item_to_date_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'RETRYABLE_ERROR', 'message', 'العملية قيد المعالجة'));
  END IF;

  UPDATE private.visit_operation_requests SET status = 'processing', started_at = clock_timestamp(), updated_at = clock_timestamp() WHERE operation_id = p_operation_id;

  BEGIN
    -- 2. Lock Source Item and Plan
    SELECT plan_id, status, customer_id, customer_branch_id, purpose, purpose_type, priority, estimated_duration_min
    INTO v_source_plan_id, v_item_status, v_customer_id, v_customer_branch_id, v_purpose, v_purpose_type, v_priority, v_estimated_duration
    FROM public.visit_plan_items
    WHERE id = p_item_id
    FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'بند الزيارة غير موجود'; END IF;
    IF v_item_status != 'pending' THEN RAISE EXCEPTION 'لا يمكن إعادة جدولة بند إلا إذا كان في حالة pending'; END IF;

    SELECT status, plan_type, employee_id, organizational_branch_id
    INTO v_source_plan_status, v_source_plan_type, v_source_employee_id, v_source_branch_id
    FROM public.visit_plans
    WHERE id = v_source_plan_id
    FOR UPDATE;

    IF v_source_plan_status NOT IN ('confirmed', 'in_progress') THEN
      RAISE EXCEPTION 'لا يمكن إعادة جدولة بنود لخطة غير مؤكدة أو غير جارية';
    END IF;

    -- 3. Authorization Check
    IF NOT (SELECT public.check_permission(v_actor_id, 'visit_plans.update_own')) AND NOT (SELECT public.check_permission(v_actor_id, 'visit_plans.update')) THEN
      RAISE EXCEPTION 'ليس لديك صلاحية لتعديل خطط الزيارات';
    END IF;

    SELECT id, branch_id INTO v_creator_employee_id, v_creator_branch_id FROM public.hr_employees WHERE user_id = v_actor_id;

    v_has_access :=
      (v_creator_employee_id IS NOT NULL AND v_creator_employee_id = v_source_employee_id)
      OR public.check_permission(v_actor_id, 'visit_plans.read_all')
      OR (
        public.check_permission(v_actor_id, 'visit_plans.read_team')
        AND v_creator_branch_id IS NOT NULL
        AND v_creator_branch_id = v_source_branch_id
      );

    IF NOT v_has_access THEN RAISE EXCEPTION 'غير مصرح لك بتعديل هذه الخطة'; END IF;

    -- 4. Find or Create Target Plan
    -- يتم البحث عن خطة موجودة لنفس اليوم. وبسبب قيد (idx_visit_plans_daily_unique) لا يمكننا إنشاء مسودة موازية لخطة مؤكدة.
    -- مسموح بالإضافة إلى خطط draft و confirmed فقط.
    -- تم استبعاد in_progress لمنع إرباك المندوب أثناء تنفيذه الميداني ولضمان استقرار ترتيب الزيارات.
    IF v_source_plan_type = 'daily' THEN
      -- القيد الفريد التاريخي لليوميات يعتمد على الموظف والتاريخ فقط؛ لذلك يجب
      -- قفل أي خطة يومية موجودة أولاً ثم فحص الفرع بدلاً من محاولة إنشاء صف متعارض.
      SELECT id, status INTO v_target_plan_id, v_target_plan_status
      FROM public.visit_plans
      WHERE employee_id = v_source_employee_id
        AND plan_date = p_target_date
        AND plan_type = 'daily'
      ORDER BY created_at DESC
      LIMIT 1
      FOR UPDATE;
    ELSE
      SELECT id, status INTO v_target_plan_id, v_target_plan_status
      FROM public.visit_plans
      WHERE employee_id = v_source_employee_id
        AND plan_date = p_target_date
        AND plan_type = v_source_plan_type
        AND organizational_branch_id IS NOT DISTINCT FROM v_source_branch_id
      ORDER BY created_at DESC
      LIMIT 1
      FOR UPDATE;
    END IF;

    IF FOUND THEN
      IF (SELECT organizational_branch_id FROM public.visit_plans WHERE id = v_target_plan_id)
         IS DISTINCT FROM v_source_branch_id THEN
        RAISE EXCEPTION 'خطة يوم الوجهة مرتبطة بفرع تنظيمي مختلف وتحتاج معالجة إدارية قبل إعادة الجدولة';
      END IF;
      IF v_target_plan_status NOT IN ('draft', 'confirmed') THEN
        RAISE EXCEPTION 'يوجد خطة زيارة في يوم الوجهة ولكنها غير قابلة للإضافة (حالتها %)', v_target_plan_status;
      END IF;
    ELSE
      v_target_plan_id := pg_catalog.gen_random_uuid();
      INSERT INTO public.visit_plans (
        id, employee_id, organizational_branch_id, plan_date, plan_type, status,
        created_by, created_at, updated_at
      ) VALUES (
        v_target_plan_id, v_source_employee_id, v_source_branch_id, p_target_date, v_source_plan_type, 'draft',
        v_actor_id, clock_timestamp(), clock_timestamp()
      );
    END IF;

    -- Lock target plan items to safely calculate sequence
    PERFORM 1 FROM public.visit_plan_items WHERE plan_id = v_target_plan_id FOR UPDATE;

    SELECT COALESCE(MAX(sequence), 0) + 1 INTO v_new_sequence
    FROM public.visit_plan_items
    WHERE plan_id = v_target_plan_id;

    v_new_item_id := pg_catalog.gen_random_uuid();

    -- 5. Create new item
    INSERT INTO public.visit_plan_items (
      id, plan_id, customer_id, customer_branch_id, sequence, planned_time, estimated_duration_min,
      priority, purpose, purpose_type, status, rescheduled_from_item_id, created_at, updated_at
    ) VALUES (
      v_new_item_id, v_target_plan_id, v_customer_id, v_customer_branch_id, v_new_sequence, p_planned_time, v_estimated_duration,
      v_priority, v_purpose, v_purpose_type, 'pending', p_item_id, clock_timestamp(), clock_timestamp()
    );

    -- 6. Update old item
    UPDATE public.visit_plan_items
    SET status = 'rescheduled',
        reschedule_reason = p_reschedule_reason,
        reschedule_to = p_target_date,
        replacement_item_id = v_new_item_id,
        updated_at = clock_timestamp()
    WHERE id = p_item_id;

    -- Recalculate source plan and target plan
    PERFORM private.recalculate_visit_plan_counts(v_source_plan_id);
    PERFORM private.recalculate_visit_plan_counts(v_target_plan_id);

    UPDATE private.visit_operation_requests
    SET status = 'completed', completed_at = clock_timestamp(), result_json = jsonb_build_object('target_plan_id', v_target_plan_id, 'new_item_id', v_new_item_id), updated_at = clock_timestamp()
    WHERE operation_id = p_operation_id;

    RETURN jsonb_build_object(
      'ok', true,
      'operation_id', p_operation_id,
      'operation', 'reschedule_visit_item_to_date_atomic',
      'replayed', false,
      'data', jsonb_build_object('target_plan_id', v_target_plan_id, 'new_item_id', v_new_item_id)
    );

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

      RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'reschedule_visit_item_to_date_atomic', 'replayed', false, 'error', jsonb_build_object('code', v_safe_code, 'message', v_safe_message));
    END;
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.reschedule_visit_item_to_date_atomic(
  p_operation_id UUID,
  p_item_id UUID,
  p_target_date DATE,
  p_reschedule_reason TEXT,
  p_planned_time TIME DEFAULT NULL,
  p_client_event_at TIMESTAMPTZ DEFAULT NULL,
  p_device_timezone VARCHAR(100) DEFAULT NULL
)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
  SELECT private.reschedule_visit_item_to_date_atomic_impl(p_operation_id, p_item_id, p_target_date, p_reschedule_reason, p_planned_time, p_client_event_at, p_device_timezone);
$$;

REVOKE ALL ON FUNCTION private.reschedule_visit_item_to_date_atomic_impl(UUID, UUID, DATE, TEXT, TIME, TIMESTAMPTZ, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.reschedule_visit_item_to_date_atomic_impl(UUID, UUID, DATE, TEXT, TIME, TIMESTAMPTZ, VARCHAR) TO authenticated;

REVOKE ALL ON FUNCTION public.reschedule_visit_item_to_date_atomic(UUID, UUID, DATE, TEXT, TIME, TIMESTAMPTZ, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reschedule_visit_item_to_date_atomic(UUID, UUID, DATE, TEXT, TIME, TIMESTAMPTZ, VARCHAR) TO authenticated;


-- =============================================================================
-- 2. إنهاء اليومية (Bulk Close - Missed)
-- =============================================================================

CREATE OR REPLACE FUNCTION private.close_visit_day_missed_atomic_impl(
  p_operation_id UUID,
  p_plan_id      UUID,
  p_close_reason TEXT,
  p_client_event_at TIMESTAMPTZ,
  p_device_timezone VARCHAR(100)
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
  v_result_data         JSONB;

  v_plan_status         VARCHAR(20);
  v_target_branch_id    UUID;
  v_creator_employee_id UUID;
  v_creator_branch_id   UUID;
  v_plan_employee_id    UUID;
  v_pending_count       INT;
  v_in_progress_count   INT;
  v_has_access          BOOLEAN;
BEGIN
  IF p_operation_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'close_visit_day_missed_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'INVALID_OPERATION_ID', 'message', 'معرف العملية مطلوب'));
  END IF;

  IF p_plan_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'close_visit_day_missed_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'INVALID_PLAN_ID', 'message', 'معرف الخطة مطلوب'));
  END IF;

  v_actor_id := auth.uid();
  IF v_actor_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'close_visit_day_missed_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'UNAUTHORIZED', 'message', 'المستخدم غير مصرح له'));
  END IF;

  IF NULLIF(BTRIM(p_close_reason), '') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'close_visit_day_missed_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'INVALID_REASON', 'message', 'سبب الإغلاق مطلوب'));
  END IF;

  v_payload := jsonb_build_object(
    'operation_name', 'close_visit_day_missed_atomic',
    'plan_id', p_plan_id,
    'close_reason', p_close_reason,
    'client_event_at', p_client_event_at,
    'device_timezone', p_device_timezone
  );
  v_hash := encode(extensions.digest(v_payload::text, 'sha256'), 'hex');

  INSERT INTO private.visit_operation_requests (operation_id, actor_id, operation_name, request_hash, status, created_at)
  VALUES (p_operation_id, v_actor_id, 'close_visit_day_missed_atomic', v_hash, 'pending', clock_timestamp())
  ON CONFLICT DO NOTHING;

  SELECT status, result_json, actor_id, operation_name, request_hash
  INTO v_req_status, v_req_result, v_req_actor, v_req_op, v_req_hash
  FROM private.visit_operation_requests
  WHERE operation_id = p_operation_id
  FOR UPDATE;

  IF v_req_actor IS DISTINCT FROM v_actor_id OR v_req_op IS DISTINCT FROM 'close_visit_day_missed_atomic' OR v_req_hash IS DISTINCT FROM v_hash THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'close_visit_day_missed_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'IDEMPOTENCY_KEY_CONFLICT', 'message', 'تعارض في معرّف العملية'));
  END IF;

  IF v_req_status = 'completed' THEN RETURN jsonb_build_object('ok', true, 'operation_id', p_operation_id, 'operation', 'close_visit_day_missed_atomic', 'replayed', true, 'data', v_req_result);
  ELSIF v_req_status = 'failed' THEN RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'close_visit_day_missed_atomic', 'replayed', true, 'error', v_req_result->'error');
  ELSIF v_req_status = 'processing' THEN RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'close_visit_day_missed_atomic', 'replayed', false, 'error', jsonb_build_object('code', 'RETRYABLE_ERROR', 'message', 'العملية قيد المعالجة'));
  END IF;

  UPDATE private.visit_operation_requests SET status = 'processing', started_at = clock_timestamp(), updated_at = clock_timestamp() WHERE operation_id = p_operation_id;

  BEGIN
    SELECT status, organizational_branch_id, employee_id
    INTO v_plan_status, v_target_branch_id, v_plan_employee_id
    FROM public.visit_plans
    WHERE id = p_plan_id
    FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'خطة الزيارة غير موجودة'; END IF;
    IF v_plan_status NOT IN ('confirmed', 'in_progress') THEN RAISE EXCEPTION 'لا يمكن إنهاء يومية لخطة غير مؤكدة أو غير جارية'; END IF;

    -- Authorization Check: Only supervisors/managers can close day
    IF NOT (SELECT public.check_permission(v_actor_id, 'visit_plans.close_administrative'))
       AND NOT (SELECT public.check_permission(v_actor_id, 'visit_plans.close_day')) THEN
      RAISE EXCEPTION 'ليس لديك صلاحية لإغلاق اليومية. هذه العملية تتطلب تصريحاً إدارياً.';
    END IF;

    -- NOTE: Owner of the plan is explicitly not granted permission directly here without the specific admin/close permission.

    PERFORM 1 FROM public.visit_plan_items WHERE plan_id = p_plan_id ORDER BY id FOR UPDATE;

    SELECT COUNT(id) FILTER (WHERE status = 'pending'), COUNT(id) FILTER (WHERE status = 'in_progress')
    INTO v_pending_count, v_in_progress_count
    FROM public.visit_plan_items
    WHERE plan_id = p_plan_id;

    IF v_in_progress_count > 0 THEN RAISE EXCEPTION 'لا يمكن إنهاء اليومية أثناء وجود زيارة جارية ميدانياً'; END IF;
    IF v_pending_count = 0 THEN RAISE EXCEPTION 'يجب وجود بند معلق (pending) واحد على الأقل لإنهاء اليومية'; END IF;

    -- يتم توظيف حقل skip_reason لتسجيل مبرر الإغلاق والتحويل لحالة missed لأن الجدول لا يحوي حقل missed_reason منفصل حالياً.
    UPDATE public.visit_plan_items
    SET status = 'missed',
        skip_reason = p_close_reason,
        updated_at = clock_timestamp()
    WHERE plan_id = p_plan_id AND status = 'pending';

    -- العدادات ستقوم تلقائياً بتقييم ما إن كانت الخطة مغلقة وإعطائها الحالة النهائية المناسبة (completed, partial, missed)
    PERFORM private.recalculate_visit_plan_counts(p_plan_id);

    SELECT jsonb_build_object('plan_id', id, 'status', status) INTO v_result_data FROM public.visit_plans WHERE id = p_plan_id;

    UPDATE private.visit_operation_requests
    SET status = 'completed', completed_at = clock_timestamp(), result_json = v_result_data, updated_at = clock_timestamp()
    WHERE operation_id = p_operation_id;

    RETURN jsonb_build_object('ok', true, 'operation_id', p_operation_id, 'operation', 'close_visit_day_missed_atomic', 'replayed', false, 'data', v_result_data);

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

      RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'close_visit_day_missed_atomic', 'replayed', false, 'error', jsonb_build_object('code', v_safe_code, 'message', v_safe_message));
    END;
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.close_visit_day_missed_atomic(
  p_operation_id UUID,
  p_plan_id UUID,
  p_close_reason TEXT,
  p_client_event_at TIMESTAMPTZ DEFAULT NULL,
  p_device_timezone VARCHAR(100) DEFAULT NULL
)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
  SELECT private.close_visit_day_missed_atomic_impl(p_operation_id, p_plan_id, p_close_reason, p_client_event_at, p_device_timezone);
$$;

REVOKE ALL ON FUNCTION private.close_visit_day_missed_atomic_impl(UUID, UUID, TEXT, TIMESTAMPTZ, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.close_visit_day_missed_atomic_impl(UUID, UUID, TEXT, TIMESTAMPTZ, VARCHAR) TO authenticated;

REVOKE ALL ON FUNCTION public.close_visit_day_missed_atomic(UUID, UUID, TEXT, TIMESTAMPTZ, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.close_visit_day_missed_atomic(UUID, UUID, TEXT, TIMESTAMPTZ, VARCHAR) TO authenticated;

COMMIT;
