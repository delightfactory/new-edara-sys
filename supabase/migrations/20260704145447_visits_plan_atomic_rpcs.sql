-- =============================================================================
-- EDARA v2 — 20260704145447_visits_plan_atomic_rpcs.sql
-- Migration Phase D: Atomic RPCs for Visits Management
--
-- ⚠️ تنبيه: هذا الملف للإنشاء والتوثيق المرجعي فقط، وممنوع تطبيقه مباشرة على الإنتاج
-- =============================================================================

BEGIN;

-- ─── 0. التحقق الساكن المسبق من وجود دالة التشفير digest ───
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'extensions'
      AND p.proname = 'digest'
      AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'text, text'
  ) THEN
    RAISE EXCEPTION 'دالة التشفير extensions.digest(text, text) غير متوفرة في مخطط extensions';
  END IF;
END;
$$;


-- ─── 1. تهيئة صلاحيات المخطط الخاص private ───

REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA private TO authenticated;


-- ─── 2. الدوال الداخلية للتنفيذ المميز (SECURITY DEFINER) ───

-- 2.أ) private.create_visit_plan_atomic_impl
CREATE OR REPLACE FUNCTION private.create_visit_plan_atomic_impl(
  p_operation_id UUID,
  p_employee_id  UUID,
  p_plan_date    DATE,
  p_plan_type    VARCHAR(20),
  p_notes        TEXT,
  p_items        JSONB
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
BEGIN
  -- 1. التحقق من معرف العملية
  IF p_operation_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', NULL::UUID,
      'operation', 'create_visit_plan_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'INVALID_OPERATION_ID',
        'message', 'معرف العملية (operation_id) مطلوب ولا يمكن أن يكون فارغاً'
      )
    );
  END IF;

  -- 2. التحقق من الهوية
  v_actor_id := auth.uid();
  IF v_actor_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'create_visit_plan_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'UNAUTHORIZED',
        'message', 'المستخدم غير مصرح له أو الجلسة منتهية'
      )
    );
  END IF;

  -- 3. بناء الحمولة والتشفير للمنع الذري للتكرار
  v_payload := jsonb_build_object(
    'operation_name', 'create_visit_plan_atomic',
    'employee_id', p_employee_id,
    'plan_date', p_plan_date,
    'plan_type', COALESCE(p_plan_type, 'daily'),
    'notes', p_notes,
    'items', p_items
  );
  v_hash := encode(extensions.digest(v_payload::text, 'sha256'), 'hex');

  -- 4. محرك منع التكرار (Idempotency Engine)
  INSERT INTO private.visit_operation_requests (
    operation_id,
    actor_id,
    operation_name,
    request_hash,
    status,
    created_at
  ) VALUES (
    p_operation_id,
    v_actor_id,
    'create_visit_plan_atomic',
    v_hash,
    'pending',
    clock_timestamp()
  ) ON CONFLICT DO NOTHING;

  SELECT status, result_json, actor_id, operation_name, request_hash
  INTO v_req_status, v_req_result, v_req_actor, v_req_op, v_req_hash
  FROM private.visit_operation_requests
  WHERE operation_id = p_operation_id
  FOR UPDATE;

  -- كشف تعارض مفاتيح العمليات
  IF v_req_actor IS DISTINCT FROM v_actor_id OR
     v_req_op IS DISTINCT FROM 'create_visit_plan_atomic' OR
     v_req_hash IS DISTINCT FROM v_hash THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'create_visit_plan_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'IDEMPOTENCY_KEY_CONFLICT',
        'message', 'تعارض في معرّف العملية (idempotency_key_conflict)'
      )
    );
  END IF;

  -- إرجاع النتائج المخزنة للطلبات المكررة
  IF v_req_status = 'completed' THEN
    RETURN jsonb_build_object(
      'ok', true,
      'operation_id', p_operation_id,
      'operation', 'create_visit_plan_atomic',
      'replayed', true,
      'data', v_req_result
    );
  ELSIF v_req_status = 'failed' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'create_visit_plan_atomic',
      'replayed', true,
      'error', v_req_result->'error'
    );
  ELSIF v_req_status = 'processing' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'create_visit_plan_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'RETRYABLE_ERROR',
        'message', 'العملية قيد المعالجة حالياً (retryable_error)'
      )
    );
  END IF;

  -- تحديث الحالة لبدء المعالجة
  UPDATE private.visit_operation_requests
  SET status = 'processing',
      started_at = clock_timestamp(),
      updated_at = clock_timestamp()
  WHERE operation_id = p_operation_id;

  -- 5. معاملة المنطق الأساسي مع التراجع الجزئي والأمان التام
  BEGIN
    DECLARE
      v_target_branch_id    UUID;
      v_creator_employee_id UUID;
      v_creator_branch_id   UUID;
      v_new_plan_id         UUID;
      v_item_json           JSONB;
      v_item_idx            INTEGER;
      v_sequences           INTEGER[] := ARRAY[]::INTEGER[];
      v_customer_ids        UUID[] := ARRAY[]::UUID[];
      v_cust_id             UUID;
      v_cust_branch_id      UUID;
      v_seq                 INTEGER;
      v_p_time              TIME;
      v_duration            INTEGER;
      v_priority            VARCHAR(10);
      v_purpose             TEXT;
      v_purpose_type        VARCHAR(50);
      v_lat                 NUMERIC(10,7);
      v_lng                 NUMERIC(10,7);
      v_loc_source          VARCHAR(50);
      v_loc_id              UUID;
      v_loc_lat             NUMERIC(10,7);
      v_loc_lng             NUMERIC(10,7);
      v_has_create_access   BOOLEAN;
    BEGIN
      -- التحقق من الصلاحيات والفرع
      IF NOT (SELECT public.check_permission(v_actor_id, 'visit_plans.create')) THEN
        RAISE EXCEPTION 'ليس لديك صلاحية إنشاء خطط الزيارات';
      END IF;

      SELECT branch_id INTO v_target_branch_id
      FROM public.hr_employees
      WHERE id = p_employee_id;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'الموظف المستهدف غير موجود';
      END IF;

      SELECT id, branch_id INTO v_creator_employee_id, v_creator_branch_id
      FROM public.hr_employees
      WHERE user_id = v_actor_id;

      v_has_create_access := false;
      IF (SELECT public.check_permission(v_actor_id, 'visit_plans.read_all')) THEN
        v_has_create_access := true;
      ELSIF (SELECT public.check_permission(v_actor_id, 'visit_plans.read_team')) THEN
        IF v_creator_branch_id = v_target_branch_id THEN
          v_has_create_access := true;
        END IF;
      ELSIF v_creator_employee_id = p_employee_id THEN
        v_has_create_access := true;
      END IF;

      IF NOT v_has_create_access THEN
        RAISE EXCEPTION 'غير مصرح لك بإنشاء خطة زيارة للموظف المستهدف أو خارج نطاق فرعك التنظيمي';
      END IF;

      -- فصل التحقق من نوع مصفوفة JSON عن طولها
      IF p_items IS NULL OR jsonb_typeof(p_items) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'مصفوفة البنود يجب ألا تكون فارغة';
      END IF;
      IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'مصفوفة البنود يجب ألا تكون فارغة';
      END IF;
      IF jsonb_array_length(p_items) > 100 THEN
        RAISE EXCEPTION 'الحد الأقصى للبنود في الخطة الواحدة هو 100 بند';
      END IF;

      IF p_plan_type IS NOT NULL AND p_plan_type NOT IN ('daily', 'weekly', 'campaign', 'recurring') THEN
        RAISE EXCEPTION 'نوع الخطة غير صالح';
      END IF;

      -- التحقق المسبق من الترتيب وصحة البيانات والعملاء والمفاتيح الزائدة
      FOR v_item_idx IN 0 .. jsonb_array_length(p_items) - 1 LOOP
        v_item_json := p_items->v_item_idx;

        IF jsonb_typeof(v_item_json) != 'object' THEN
          RAISE EXCEPTION 'كل عنصر في البنود يجب أن يكون كائناً (object)';
        END IF;

        IF EXISTS (
          SELECT 1 FROM jsonb_object_keys(v_item_json) k
          WHERE k NOT IN (
            'customer_id', 'customer_branch_id', 'sequence', 'planned_time',
            'estimated_duration_min', 'priority', 'purpose', 'purpose_type'
          )
        ) THEN
          RAISE EXCEPTION 'يمنع إرسال مفاتيح إضافية غير معتمدة في بنود الخطة';
        END IF;

        v_cust_id := (v_item_json->>'customer_id')::UUID;
        v_cust_branch_id := (v_item_json->>'customer_branch_id')::UUID;
        v_seq := (v_item_json->>'sequence')::INTEGER;
        v_duration := (v_item_json->>'estimated_duration_min')::INTEGER;
        v_priority := v_item_json->>'priority';
        v_purpose_type := v_item_json->>'purpose_type';

        IF v_cust_id IS NULL THEN
          RAISE EXCEPTION 'رقم العميل (customer_id) مطلوب لكل بند';
        END IF;

        IF NOT EXISTS (SELECT 1 FROM public.customers WHERE id = v_cust_id) THEN
          RAISE EXCEPTION 'العميل المحدد غير موجود';
        END IF;

        IF v_cust_branch_id IS NOT NULL THEN
          IF NOT EXISTS (
            SELECT 1 FROM public.customer_branches
            WHERE id = v_cust_branch_id AND customer_id = v_cust_id
          ) THEN
            RAISE EXCEPTION 'فرع العميل المحدد غير موجود أو لا ينتمي للعميل المستهدف';
          END IF;
        END IF;

        IF v_seq IS NULL OR v_seq < 1 OR v_seq > jsonb_array_length(p_items) THEN
          RAISE EXCEPTION 'الترتيب % غير صالح', v_seq;
        END IF;
        IF v_seq = ANY(v_sequences) THEN
          RAISE EXCEPTION 'الترتيب % مكرر في بنود الخطة', v_seq;
        END IF;
        v_sequences := array_append(v_sequences, v_seq);

        IF v_cust_id = ANY(v_customer_ids) THEN
          RAISE EXCEPTION 'لا يمكن تكرار نفس العميل في الخطة';
        END IF;
        v_customer_ids := array_append(v_customer_ids, v_cust_id);

        IF v_duration IS NOT NULL AND (v_duration < 5 OR v_duration > 480) THEN
          RAISE EXCEPTION 'المدة التقديرية للزيارة يجب أن تكون بين 5 و480 دقيقة';
        END IF;

        IF v_priority IS NOT NULL AND v_priority NOT IN ('high', 'normal', 'low') THEN
          RAISE EXCEPTION 'أولوية الزيارة غير صالحة';
        END IF;

        IF v_purpose_type IS NOT NULL AND v_purpose_type NOT IN ('sales', 'collection', 'activation', 'promotion', 'followup', 'service') THEN
          RAISE EXCEPTION 'غرض الزيارة غير صالح';
        END IF;
      END LOOP;

      -- إنشاء الخطة
      INSERT INTO public.visit_plans (
        employee_id,
        plan_date,
        plan_type,
        status,
        notes,
        created_by,
        organizational_branch_id,
        created_at,
        updated_at
      ) VALUES (
        p_employee_id,
        p_plan_date,
        COALESCE(p_plan_type, 'daily'),
        'draft',
        p_notes,
        v_actor_id,
        v_target_branch_id,
        clock_timestamp(),
        clock_timestamp()
      ) RETURNING id INTO v_new_plan_id;

      -- إدخال البنود وحل الإحداثيات
      FOR v_item_idx IN 0 .. jsonb_array_length(p_items) - 1 LOOP
        v_item_json := p_items->v_item_idx;
        v_cust_id := (v_item_json->>'customer_id')::UUID;
        v_cust_branch_id := (v_item_json->>'customer_branch_id')::UUID;
        v_seq := (v_item_json->>'sequence')::INTEGER;
        v_p_time := (v_item_json->>'planned_time')::TIME;
        v_duration := (v_item_json->>'estimated_duration_min')::INTEGER;
        v_priority := v_item_json->>'priority';
        v_purpose := v_item_json->>'purpose';
        v_purpose_type := v_item_json->>'purpose_type';

        -- حل لقطة الموقع المتوقع
        v_loc_source := NULL;
        v_loc_id := NULL;
        v_lat := NULL;
        v_lng := NULL;

        IF v_cust_branch_id IS NOT NULL THEN
          SELECT latitude, longitude INTO v_lat, v_lng
          FROM public.customer_branches
          WHERE id = v_cust_branch_id;

          IF v_lat IS NOT NULL AND v_lng IS NOT NULL AND v_lat BETWEEN -90 AND 90 AND v_lng BETWEEN -180 AND 180 THEN
            v_loc_source := 'customer_branch';
            v_loc_id := v_cust_branch_id;
            v_loc_lat := v_lat;
            v_loc_lng := v_lng;
          END IF;
        END IF;

        IF v_loc_source IS NULL THEN
          SELECT latitude, longitude INTO v_lat, v_lng
          FROM public.customers
          WHERE id = v_cust_id;

          IF v_lat IS NOT NULL AND v_lng IS NOT NULL AND v_lat BETWEEN -90 AND 90 AND v_lng BETWEEN -180 AND 180 THEN
            v_loc_source := 'customer';
            v_loc_id := v_cust_id;
            v_loc_lat := v_lat;
            v_loc_lng := v_lng;
          ELSE
            v_loc_source := NULL;
            v_loc_id := NULL;
            v_loc_lat := NULL;
            v_loc_lng := NULL;
          END IF;
        END IF;

        INSERT INTO public.visit_plan_items (
          plan_id,
          customer_id,
          customer_branch_id,
          sequence,
          planned_time,
          estimated_duration_min,
          priority,
          purpose,
          purpose_type,
          status,
          expected_location_source,
          expected_location_id,
          expected_lat,
          expected_lng,
          created_at,
          updated_at
        ) VALUES (
          v_new_plan_id,
          v_cust_id,
          v_cust_branch_id,
          v_seq,
          v_p_time,
          COALESCE(v_duration, 30),
          COALESCE(v_priority, 'normal'),
          v_purpose,
          v_purpose_type,
          'pending',
          v_loc_source,
          v_loc_id,
          v_loc_lat,
          v_loc_lng,
          clock_timestamp(),
          clock_timestamp()
        );
      END LOOP;

      PERFORM private.recalculate_visit_plan_counts(v_new_plan_id);

      SELECT jsonb_build_object(
        'plan_id', vp.id,
        'employee_id', vp.employee_id,
        'plan_date', vp.plan_date,
        'status', vp.status,
        'total_customers', vp.total_customers,
        'items', (
          SELECT jsonb_agg(jsonb_build_object(
            'id', vpi.id,
            'customer_id', vpi.customer_id,
            'sequence', vpi.sequence,
            'status', vpi.status
          ) ORDER BY vpi.sequence)
          FROM public.visit_plan_items vpi
          WHERE vpi.plan_id = vp.id
        )
      ) INTO v_result_data
      FROM public.visit_plans vp
      WHERE vp.id = v_new_plan_id;
    END;

    UPDATE private.visit_operation_requests
    SET status = 'completed',
        completed_at = clock_timestamp(),
        result_json = v_result_data,
        updated_at = clock_timestamp()
    WHERE operation_id = p_operation_id;

    RETURN jsonb_build_object(
      'ok', true,
      'operation_id', p_operation_id,
      'operation', 'create_visit_plan_atomic',
      'replayed', false,
      'data', v_result_data
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
      SET status = 'failed',
          completed_at = clock_timestamp(),
          error_code = v_safe_code,
          result_json = jsonb_build_object(
            'error', jsonb_build_object(
              'code', v_safe_code,
              'message', v_safe_message
            )
          ),
          updated_at = clock_timestamp()
      WHERE operation_id = p_operation_id;

      RETURN jsonb_build_object(
        'ok', false,
        'operation_id', p_operation_id,
        'operation', 'create_visit_plan_atomic',
        'replayed', false,
        'error', jsonb_build_object(
          'code', v_safe_code,
          'message', v_safe_message
        )
      );
    END;
  END;
END;
$$;

REVOKE ALL ON FUNCTION private.create_visit_plan_atomic_impl(UUID, UUID, DATE, VARCHAR, TEXT, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.create_visit_plan_atomic_impl(UUID, UUID, DATE, VARCHAR, TEXT, JSONB) TO authenticated;


-- 2.ب) private.confirm_visit_plan_atomic_impl
CREATE OR REPLACE FUNCTION private.confirm_visit_plan_atomic_impl(
  p_operation_id UUID,
  p_plan_id      UUID
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
BEGIN
  -- 1. التحقق من معرف العملية
  IF p_operation_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', NULL::UUID,
      'operation', 'confirm_visit_plan_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'INVALID_OPERATION_ID',
        'message', 'معرف العملية (operation_id) مطلوب ولا يمكن أن يكون فارغاً'
      )
    );
  END IF;

  v_actor_id := auth.uid();
  IF v_actor_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'confirm_visit_plan_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'UNAUTHORIZED',
        'message', 'المستخدم غير مصرح له'
      )
    );
  END IF;

  v_payload := jsonb_build_object(
    'operation_name', 'confirm_visit_plan_atomic',
    'plan_id', p_plan_id
  );
  v_hash := encode(extensions.digest(v_payload::text, 'sha256'), 'hex');

  INSERT INTO private.visit_operation_requests (
    operation_id,
    actor_id,
    operation_name,
    request_hash,
    status,
    created_at
  ) VALUES (
    p_operation_id,
    v_actor_id,
    'confirm_visit_plan_atomic',
    v_hash,
    'pending',
    clock_timestamp()
  ) ON CONFLICT DO NOTHING;

  SELECT status, result_json, actor_id, operation_name, request_hash
  INTO v_req_status, v_req_result, v_req_actor, v_req_op, v_req_hash
  FROM private.visit_operation_requests
  WHERE operation_id = p_operation_id
  FOR UPDATE;

  IF v_req_actor IS DISTINCT FROM v_actor_id OR
     v_req_op IS DISTINCT FROM 'confirm_visit_plan_atomic' OR
     v_req_hash IS DISTINCT FROM v_hash THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'confirm_visit_plan_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'IDEMPOTENCY_KEY_CONFLICT',
        'message', 'تعارض في معرّف العملية (idempotency_key_conflict)'
      )
    );
  END IF;

  IF v_req_status = 'completed' THEN
    RETURN jsonb_build_object('ok', true, 'operation_id', p_operation_id, 'operation', 'confirm_visit_plan_atomic', 'replayed', true, 'data', v_req_result);
  ELSIF v_req_status = 'failed' THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'confirm_visit_plan_atomic', 'replayed', true, 'error', v_req_result->'error');
  ELSIF v_req_status = 'processing' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'confirm_visit_plan_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'RETRYABLE_ERROR',
        'message', 'العملية قيد المعالجة (retryable_error)'
      )
    );
  END IF;

  UPDATE private.visit_operation_requests
  SET status = 'processing', started_at = clock_timestamp(), updated_at = clock_timestamp()
  WHERE operation_id = p_operation_id;

  BEGIN
    DECLARE
      v_plan_status         VARCHAR(20);
      v_target_branch_id    UUID;
      v_creator_employee_id UUID;
      v_creator_branch_id   UUID;
      v_total_items         INT;
      v_pending_items       INT;
      v_has_access          BOOLEAN;
    BEGIN
      SELECT status, organizational_branch_id, employee_id
      INTO v_plan_status, v_target_branch_id, v_creator_employee_id
      FROM public.visit_plans
      WHERE id = p_plan_id
      FOR UPDATE;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'خطة الزيارة غير موجودة';
      END IF;

      IF v_plan_status IS DISTINCT FROM 'draft' THEN
        RAISE EXCEPTION 'لا يمكن تأكيد خطة ليست في حالة مسودة (draft)';
      END IF;

      IF NOT (SELECT public.check_permission(v_actor_id, 'visit_plans.confirm')) THEN
        RAISE EXCEPTION 'ليس لديك صلاحية تأكيد خطط الزيارات';
      END IF;

      SELECT id, branch_id INTO v_creator_employee_id, v_creator_branch_id
      FROM public.hr_employees
      WHERE user_id = v_actor_id;

      v_has_access := false;
      IF (SELECT public.check_permission(v_actor_id, 'visit_plans.read_all')) THEN
        v_has_access := true;
      ELSIF (SELECT public.check_permission(v_actor_id, 'visit_plans.read_team')) THEN
        IF v_creator_branch_id = v_target_branch_id THEN
          v_has_access := true;
        END IF;
      END IF;

      IF NOT v_has_access THEN
        RAISE EXCEPTION 'غير مصرح لك بالوصول أو تنفيذ العمليات على هذه الخطة خارج نطاق فرعك التنظيمي';
      END IF;

      -- قفل بنود الخطة بترتيب ثابت لمنع المآزق
      PERFORM 1
      FROM public.visit_plan_items
      WHERE plan_id = p_plan_id
      ORDER BY id
      FOR UPDATE;

      SELECT COUNT(id), COUNT(id) FILTER (WHERE status = 'pending')
      INTO v_total_items, v_pending_items
      FROM public.visit_plan_items
      WHERE plan_id = p_plan_id;

      IF v_total_items = 0 THEN
        RAISE EXCEPTION 'يمنع تأكيد خطة زيارة لا تحتوي على بنود';
      END IF;
      IF v_pending_items != v_total_items THEN
        RAISE EXCEPTION 'جميع بنود خطة الزيارة المؤكدة يجب أن تكون في حالة معلقة (pending)';
      END IF;

      UPDATE public.visit_plans
      SET status = 'confirmed',
          updated_at = clock_timestamp()
      WHERE id = p_plan_id;

      SELECT jsonb_build_object(
        'plan_id', id,
        'status', status,
        'confirmed_at', confirmed_at,
        'confirmed_by', confirmed_by
      ) INTO v_result_data
      FROM public.visit_plans
      WHERE id = p_plan_id;
    END;

    UPDATE private.visit_operation_requests
    SET status = 'completed', completed_at = clock_timestamp(), result_json = v_result_data, updated_at = clock_timestamp()
    WHERE operation_id = p_operation_id;

    RETURN jsonb_build_object(
      'ok', true,
      'operation_id', p_operation_id,
      'operation', 'confirm_visit_plan_atomic',
      'replayed', false,
      'data', v_result_data
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

      RETURN jsonb_build_object(
        'ok', false,
        'operation_id', p_operation_id,
        'operation', 'confirm_visit_plan_atomic',
        'replayed', false,
        'error', jsonb_build_object('code', v_safe_code, 'message', v_safe_message)
      );
    END;
  END;
END;
$$;

REVOKE ALL ON FUNCTION private.confirm_visit_plan_atomic_impl(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.confirm_visit_plan_atomic_impl(UUID, UUID) TO authenticated;


-- 2.ج) private.cancel_visit_plan_atomic_impl
CREATE OR REPLACE FUNCTION private.cancel_visit_plan_atomic_impl(
  p_operation_id        UUID,
  p_plan_id             UUID,
  p_cancellation_reason TEXT
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
BEGIN
  -- 1. التحقق من معرف العملية
  IF p_operation_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', NULL::UUID,
      'operation', 'cancel_visit_plan_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'INVALID_OPERATION_ID',
        'message', 'معرف العملية (operation_id) مطلوب ولا يمكن أن يكون فارغاً'
      )
    );
  END IF;

  v_actor_id := auth.uid();
  IF v_actor_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'cancel_visit_plan_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'UNAUTHORIZED',
        'message', 'المستخدم غير مصرح له'
      )
    );
  END IF;

  v_payload := jsonb_build_object(
    'operation_name', 'cancel_visit_plan_atomic',
    'plan_id', p_plan_id,
    'cancellation_reason', p_cancellation_reason
  );
  v_hash := encode(extensions.digest(v_payload::text, 'sha256'), 'hex');

  INSERT INTO private.visit_operation_requests (
    operation_id,
    actor_id,
    operation_name,
    request_hash,
    status,
    created_at
  ) VALUES (
    p_operation_id,
    v_actor_id,
    'cancel_visit_plan_atomic',
    v_hash,
    'pending',
    clock_timestamp()
  ) ON CONFLICT DO NOTHING;

  SELECT status, result_json, actor_id, operation_name, request_hash
  INTO v_req_status, v_req_result, v_req_actor, v_req_op, v_req_hash
  FROM private.visit_operation_requests
  WHERE operation_id = p_operation_id
  FOR UPDATE;

  IF v_req_actor IS DISTINCT FROM v_actor_id OR
     v_req_op IS DISTINCT FROM 'cancel_visit_plan_atomic' OR
     v_req_hash IS DISTINCT FROM v_hash THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'cancel_visit_plan_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'IDEMPOTENCY_KEY_CONFLICT',
        'message', 'تعارض في معرّف العملية (idempotency_key_conflict)'
      )
    );
  END IF;

  IF v_req_status = 'completed' THEN
    RETURN jsonb_build_object('ok', true, 'operation_id', p_operation_id, 'operation', 'cancel_visit_plan_atomic', 'replayed', true, 'data', v_req_result);
  ELSIF v_req_status = 'failed' THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'cancel_visit_plan_atomic', 'replayed', true, 'error', v_req_result->'error');
  ELSIF v_req_status = 'processing' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'cancel_visit_plan_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'RETRYABLE_ERROR',
        'message', 'العملية قيد المعالجة (retryable_error)'
      )
    );
  END IF;

  UPDATE private.visit_operation_requests
  SET status = 'processing', started_at = clock_timestamp(), updated_at = clock_timestamp()
  WHERE operation_id = p_operation_id;

  BEGIN
    DECLARE
      v_plan_status         VARCHAR(20);
      v_target_branch_id    UUID;
      v_creator_employee_id UUID;
      v_creator_branch_id   UUID;
      v_total_items         INT;
      v_pending_items       INT;
      v_has_access          BOOLEAN;
    BEGIN
      IF NULLIF(BTRIM(p_cancellation_reason), '') IS NULL THEN
        RAISE EXCEPTION 'إلغاء الخطة يتطلب تسجيل سبب الإلغاء';
      END IF;

      SELECT status, organizational_branch_id, employee_id
      INTO v_plan_status, v_target_branch_id, v_creator_employee_id
      FROM public.visit_plans
      WHERE id = p_plan_id
      FOR UPDATE;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'خطة الزيارة غير موجودة';
      END IF;

      IF v_plan_status NOT IN ('draft', 'confirmed') THEN
        RAISE EXCEPTION 'لا يمكن إلغاء خطة زيارة إلا إذا كانت مسودة أو مؤكدة';
      END IF;

      IF NOT (SELECT public.check_permission(v_actor_id, 'visit_plans.cancel')) THEN
        RAISE EXCEPTION 'ليس لديك صلاحية إلغاء خطط الزيارات';
      END IF;

      SELECT id, branch_id INTO v_creator_employee_id, v_creator_branch_id
      FROM public.hr_employees
      WHERE user_id = v_actor_id;

      v_has_access := false;
      IF (SELECT public.check_permission(v_actor_id, 'visit_plans.read_all')) THEN
        v_has_access := true;
      ELSIF (SELECT public.check_permission(v_actor_id, 'visit_plans.read_team')) THEN
        IF v_creator_branch_id = v_target_branch_id THEN
          v_has_access := true;
        END IF;
      END IF;

      IF NOT v_has_access THEN
        RAISE EXCEPTION 'غير مصرح لك بالوصول أو تنفيذ العمليات على هذه الخطة خارج نطاق فرعك التنظيمي';
      END IF;

      -- قفل البنود للتحقق الصريح
      PERFORM 1
      FROM public.visit_plan_items
      WHERE plan_id = p_plan_id
      ORDER BY id
      FOR UPDATE;

      SELECT COUNT(id), COUNT(id) FILTER (WHERE status = 'pending')
      INTO v_total_items, v_pending_items
      FROM public.visit_plan_items
      WHERE plan_id = p_plan_id;

      IF v_pending_items != v_total_items THEN
        RAISE EXCEPTION 'لا يمكن إلغاء خطة زيارة تم البدء في تنفيذها (يجب أن تكون جميع بنودها pending)';
      END IF;

      UPDATE public.visit_plans
      SET status = 'cancelled',
          cancellation_reason = p_cancellation_reason,
          updated_at = clock_timestamp()
      WHERE id = p_plan_id;

      SELECT jsonb_build_object(
        'plan_id', id,
        'status', status,
        'cancellation_reason', cancellation_reason
      ) INTO v_result_data
      FROM public.visit_plans
      WHERE id = p_plan_id;
    END;

    UPDATE private.visit_operation_requests
    SET status = 'completed', completed_at = clock_timestamp(), result_json = v_result_data, updated_at = clock_timestamp()
    WHERE operation_id = p_operation_id;

    RETURN jsonb_build_object(
      'ok', true,
      'operation_id', p_operation_id,
      'operation', 'cancel_visit_plan_atomic',
      'replayed', false,
      'data', v_result_data
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

      RETURN jsonb_build_object(
        'ok', false,
        'operation_id', p_operation_id,
        'operation', 'cancel_visit_plan_atomic',
        'replayed', false,
        'error', jsonb_build_object('code', v_safe_code, 'message', v_safe_message)
      );
    END;
  END;
END;
$$;

REVOKE ALL ON FUNCTION private.cancel_visit_plan_atomic_impl(UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.cancel_visit_plan_atomic_impl(UUID, UUID, TEXT) TO authenticated;


-- 2.د) private.reorder_visit_plan_items_atomic_impl
CREATE OR REPLACE FUNCTION private.reorder_visit_plan_items_atomic_impl(
  p_operation_id UUID,
  p_plan_id      UUID,
  p_reorder_data JSONB
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
BEGIN
  -- 1. التحقق من معرف العملية
  IF p_operation_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', NULL::UUID,
      'operation', 'reorder_visit_plan_items_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'INVALID_OPERATION_ID',
        'message', 'معرف العملية (operation_id) مطلوب ولا يمكن أن يكون فارغاً'
      )
    );
  END IF;

  v_actor_id := auth.uid();
  IF v_actor_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'reorder_visit_plan_items_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'UNAUTHORIZED',
        'message', 'المستخدم غير مصرح له'
      )
    );
  END IF;

  v_payload := jsonb_build_object(
    'operation_name', 'reorder_visit_plan_items_atomic',
    'plan_id', p_plan_id,
    'reorder_data', p_reorder_data
  );
  v_hash := encode(extensions.digest(v_payload::text, 'sha256'), 'hex');

  INSERT INTO private.visit_operation_requests (
    operation_id,
    actor_id,
    operation_name,
    request_hash,
    status,
    created_at
  ) VALUES (
    p_operation_id,
    v_actor_id,
    'reorder_visit_plan_items_atomic',
    v_hash,
    'pending',
    clock_timestamp()
  ) ON CONFLICT DO NOTHING;

  SELECT status, result_json, actor_id, operation_name, request_hash
  INTO v_req_status, v_req_result, v_req_actor, v_req_op, v_req_hash
  FROM private.visit_operation_requests
  WHERE operation_id = p_operation_id
  FOR UPDATE;

  IF v_req_actor IS DISTINCT FROM v_actor_id OR
     v_req_op IS DISTINCT FROM 'reorder_visit_plan_items_atomic' OR
     v_req_hash IS DISTINCT FROM v_hash THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'reorder_visit_plan_items_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'IDEMPOTENCY_KEY_CONFLICT',
        'message', 'تعارض في معرّف العملية (idempotency_key_conflict)'
      )
    );
  END IF;

  IF v_req_status = 'completed' THEN
    RETURN jsonb_build_object('ok', true, 'operation_id', p_operation_id, 'operation', 'reorder_visit_plan_items_atomic', 'replayed', true, 'data', v_req_result);
  ELSIF v_req_status = 'failed' THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'reorder_visit_plan_items_atomic', 'replayed', true, 'error', v_req_result->'error');
  ELSIF v_req_status = 'processing' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'reorder_visit_plan_items_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'RETRYABLE_ERROR',
        'message', 'العملية قيد المعالجة (retryable_error)'
      )
    );
  END IF;

  UPDATE private.visit_operation_requests
  SET status = 'processing', started_at = clock_timestamp(), updated_at = clock_timestamp()
  WHERE operation_id = p_operation_id;

  BEGIN
    DECLARE
      v_plan_status         VARCHAR(20);
      v_target_branch_id    UUID;
      v_target_employee_id  UUID;
      v_creator_employee_id UUID;
      v_creator_branch_id   UUID;
      v_total_db_items      INT;
      v_total_input_items   INT;
      v_item_json           JSONB;
      v_item_idx            INTEGER;
      v_reorder_item_id     UUID;
      v_reorder_seq         INTEGER;
      v_input_ids           UUID[] := ARRAY[]::UUID[];
      v_input_seqs          INT[] := ARRAY[]::INT[];
      v_db_ids              UUID[] := ARRAY[]::UUID[];
      v_has_reorder_access  BOOLEAN;
    BEGIN
      -- قفل الخطة أولاً
      SELECT status, organizational_branch_id, employee_id
      INTO v_plan_status, v_target_branch_id, v_target_employee_id
      FROM public.visit_plans
      WHERE id = p_plan_id
      FOR UPDATE;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'خطة الزيارة غير موجودة';
      END IF;

      IF v_plan_status IS DISTINCT FROM 'draft' THEN
        RAISE EXCEPTION 'لا يمكن إعادة ترتيب البنود إلا للمسودة (draft) فقط';
      END IF;

      -- قفل البنود في معاملة ذرية بترتيب ثابت لمنع المآزق
      SELECT array_agg(id) INTO v_db_ids
      FROM (
        SELECT id
        FROM public.visit_plan_items
        WHERE plan_id = p_plan_id
        ORDER BY id
        FOR UPDATE
      ) sub;

      v_total_db_items := COALESCE(array_length(v_db_ids, 1), 0);

      -- فحص الصلاحيات والفرع والملكية التفصيلية لمنع ثغرات الـ IDOR
      SELECT id, branch_id INTO v_creator_employee_id, v_creator_branch_id
      FROM public.hr_employees
      WHERE user_id = v_actor_id;

      v_has_reorder_access := false;
      IF (SELECT public.check_permission(v_actor_id, 'visit_plans.read_all')) THEN
        v_has_reorder_access := true;
      ELSIF (SELECT public.check_permission(v_actor_id, 'visit_plans.update'))
            AND (SELECT public.check_permission(v_actor_id, 'visit_plans.read_team')) THEN
        IF v_creator_branch_id = v_target_branch_id THEN
          v_has_reorder_access := true;
        END IF;
      ELSIF (SELECT public.check_permission(v_actor_id, 'visit_plans.update_own')) THEN
        IF v_creator_employee_id = v_target_employee_id THEN
          v_has_reorder_access := true;
        END IF;
      END IF;

      IF NOT v_has_reorder_access THEN
        RAISE EXCEPTION 'غير مصرح لك بإعادة ترتيب بنود خطة زيارة لا تخصك أو تقع خارج فرعك التنظيمي';
      END IF;

      -- فصل التحقق من نوع مصفوفة JSON عن طولها
      IF p_reorder_data IS NULL OR jsonb_typeof(p_reorder_data) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'بيانات إعادة الترتيب يجب أن تكون مصفوفة';
      END IF;
      IF jsonb_array_length(p_reorder_data) = 0 THEN
        RAISE EXCEPTION 'بيانات إعادة الترتيب يجب ألا تكون فارغة';
      END IF;

      v_total_input_items := jsonb_array_length(p_reorder_data);

      IF v_total_input_items != v_total_db_items THEN
        RAISE EXCEPTION 'عدد البنود المرسلة لا يطابق عدد البنود المسجلة بالخطة';
      END IF;

      -- التحقق من المدخلات وسلامة المفاتيح
      FOR v_item_idx IN 0 .. v_total_input_items - 1 LOOP
        v_item_json := p_reorder_data->v_item_idx;

        IF jsonb_typeof(v_item_json) != 'object' THEN
          RAISE EXCEPTION 'كل عنصر في الترتيب يجب أن يكون كائناً (object)';
        END IF;

        IF EXISTS (
          SELECT 1 FROM jsonb_object_keys(v_item_json) k
          WHERE k NOT IN ('item_id', 'sequence')
        ) THEN
          RAISE EXCEPTION 'يمنع إرسال مفاتيح إضافية غير معتمدة في الترتيب';
        END IF;

        v_reorder_item_id := (v_item_json->>'item_id')::UUID;
        v_reorder_seq := (v_item_json->>'sequence')::INTEGER;

        IF v_reorder_item_id IS NULL OR v_reorder_seq IS NULL THEN
          RAISE EXCEPTION 'يجب تحديد معرف البند والترتيب الجديد لكل عنصر';
        END IF;

        IF NOT (v_reorder_item_id = ANY(v_db_ids)) THEN
          RAISE EXCEPTION 'البند % لا ينتمي لهذه الخطة', v_reorder_item_id;
        END IF;

        IF v_reorder_item_id = ANY(v_input_ids) THEN
          RAISE EXCEPTION 'معرف البند % مكرر في طلب إعادة الترتيب', v_reorder_item_id;
        END IF;
        v_input_ids := array_append(v_input_ids, v_reorder_item_id);

        IF v_reorder_seq < 1 OR v_reorder_seq > v_total_db_items THEN
          RAISE EXCEPTION 'قيمة الترتيب % خارج النطاق المسموح (1..%)', v_reorder_seq, v_total_db_items;
        END IF;

        IF v_reorder_seq = ANY(v_input_seqs) THEN
          RAISE EXCEPTION 'الترتيب % مكرر في طلب إعادة الترتيب', v_reorder_seq;
        END IF;
        v_input_seqs := array_append(v_input_seqs, v_reorder_seq);
      END LOOP;

      -- التحقق من عدم وجود قيم إزاحة سابقة
      IF EXISTS (
        SELECT 1 FROM public.visit_plan_items
        WHERE plan_id = p_plan_id AND sequence >= 10000
      ) THEN
        RAISE EXCEPTION 'تجاوز حد الترتيب المسموح به (قيم الترتيب القديمة يجب أن تكون أقل من 10000)';
      END IF;

      -- إزاحة البنود مؤقتاً لتجنب قيود التكرار الفريدة
      UPDATE public.visit_plan_items
      SET sequence = sequence + 10000
      WHERE plan_id = p_plan_id;

      -- تطبيق الترتيب الجديد
      FOR v_item_idx IN 0 .. v_total_input_items - 1 LOOP
        v_item_json := p_reorder_data->v_item_idx;
        v_reorder_item_id := (v_item_json->>'item_id')::UUID;
        v_reorder_seq := (v_item_json->>'sequence')::INTEGER;

        UPDATE public.visit_plan_items
        SET sequence = v_reorder_seq,
            updated_at = clock_timestamp()
        WHERE id = v_reorder_item_id;
      END LOOP;

      SELECT jsonb_build_object(
        'plan_id', p_plan_id,
        'items', (
          SELECT jsonb_agg(jsonb_build_object(
            'id', id,
            'sequence', sequence
          ) ORDER BY sequence)
          FROM public.visit_plan_items
          WHERE plan_id = p_plan_id
        )
      ) INTO v_result_data;
    END;

    UPDATE private.visit_operation_requests
    SET status = 'completed', completed_at = clock_timestamp(), result_json = v_result_data, updated_at = clock_timestamp()
    WHERE operation_id = p_operation_id;

    RETURN jsonb_build_object(
      'ok', true,
      'operation_id', p_operation_id,
      'operation', 'reorder_visit_plan_items_atomic',
      'replayed', false,
      'data', v_result_data
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

      RETURN jsonb_build_object(
        'ok', false,
        'operation_id', p_operation_id,
        'operation', 'reorder_visit_plan_items_atomic',
        'replayed', false,
        'error', jsonb_build_object('code', v_safe_code, 'message', v_safe_message)
      );
    END;
  END;
END;
$$;

REVOKE ALL ON FUNCTION private.reorder_visit_plan_items_atomic_impl(UUID, UUID, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.reorder_visit_plan_items_atomic_impl(UUID, UUID, JSONB) TO authenticated;


-- 2.هـ) private.close_visit_plan_administratively_atomic_impl
CREATE OR REPLACE FUNCTION private.close_visit_plan_administratively_atomic_impl(
  p_operation_id UUID,
  p_plan_id      UUID,
  p_close_reason TEXT
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
BEGIN
  -- 1. التحقق من معرف العملية
  IF p_operation_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', NULL::UUID,
      'operation', 'close_visit_plan_administratively_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'INVALID_OPERATION_ID',
        'message', 'معرف العملية (operation_id) مطلوب ولا يمكن أن يكون فارغاً'
      )
    );
  END IF;

  v_actor_id := auth.uid();
  IF v_actor_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'close_visit_plan_administratively_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'UNAUTHORIZED',
        'message', 'المستخدم غير مصرح له'
      )
    );
  END IF;

  v_payload := jsonb_build_object(
    'operation_name', 'close_visit_plan_administratively_atomic',
    'plan_id', p_plan_id,
    'close_reason', p_close_reason
  );
  v_hash := encode(extensions.digest(v_payload::text, 'sha256'), 'hex');

  INSERT INTO private.visit_operation_requests (
    operation_id,
    actor_id,
    operation_name,
    request_hash,
    status,
    created_at
  ) VALUES (
    p_operation_id,
    v_actor_id,
    'close_visit_plan_administratively_atomic',
    v_hash,
    'pending',
    clock_timestamp()
  ) ON CONFLICT DO NOTHING;

  SELECT status, result_json, actor_id, operation_name, request_hash
  INTO v_req_status, v_req_result, v_req_actor, v_req_op, v_req_hash
  FROM private.visit_operation_requests
  WHERE operation_id = p_operation_id
  FOR UPDATE;

  IF v_req_actor IS DISTINCT FROM v_actor_id OR
     v_req_op IS DISTINCT FROM 'close_visit_plan_administratively_atomic' OR
     v_req_hash IS DISTINCT FROM v_hash THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'close_visit_plan_administratively_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'IDEMPOTENCY_KEY_CONFLICT',
        'message', 'تعارض في معرّف العملية (idempotency_key_conflict)'
      )
    );
  END IF;

  IF v_req_status = 'completed' THEN
    RETURN jsonb_build_object('ok', true, 'operation_id', p_operation_id, 'operation', 'close_visit_plan_administratively_atomic', 'replayed', true, 'data', v_req_result);
  ELSIF v_req_status = 'failed' THEN
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'close_visit_plan_administratively_atomic', 'replayed', true, 'error', v_req_result->'error');
  ELSIF v_req_status = 'processing' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'close_visit_plan_administratively_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'RETRYABLE_ERROR',
        'message', 'العملية قيد المعالجة (retryable_error)'
      )
    );
  END IF;

  UPDATE private.visit_operation_requests
  SET status = 'processing', started_at = clock_timestamp(), updated_at = clock_timestamp()
  WHERE operation_id = p_operation_id;

  BEGIN
    DECLARE
      v_plan_status         VARCHAR(20);
      v_target_branch_id    UUID;
      v_creator_employee_id UUID;
      v_creator_branch_id   UUID;
      v_pending_count       INT;
      v_in_progress_count   INT;
      v_has_access          BOOLEAN;
    BEGIN
      IF NULLIF(BTRIM(p_close_reason), '') IS NULL THEN
        RAISE EXCEPTION 'سبب الإغلاق الإداري يجب ألا يكون فارغاً';
      END IF;

      -- التحقق من طول النص لسبب الإغلاق لتجنب تجاوز قيود الحقول
      IF char_length(p_close_reason) > 500 THEN
        RAISE EXCEPTION 'سبب الإغلاق الإداري يجب ألا يتجاوز 500 حرف';
      END IF;

      -- 1. قفل الخطة أولاً
      SELECT status, organizational_branch_id
      INTO v_plan_status, v_target_branch_id
      FROM public.visit_plans
      WHERE id = p_plan_id
      FOR UPDATE;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'خطة الزيارة غير موجودة';
      END IF;

      IF v_plan_status NOT IN ('confirmed', 'in_progress') THEN
        RAISE EXCEPTION 'الإغلاق الإداري مسموح به فقط للخطط المؤكدة أو الجارية';
      END IF;

      IF NOT (SELECT public.check_permission(v_actor_id, 'visit_plans.close_administrative')) THEN
        RAISE EXCEPTION 'ليس لديك صلاحية الإغلاق الإداري لخطط الزيارات';
      END IF;

      SELECT id, branch_id INTO v_creator_employee_id, v_creator_branch_id
      FROM public.hr_employees
      WHERE user_id = v_actor_id;

      v_has_access := false;
      IF (SELECT public.check_permission(v_actor_id, 'visit_plans.read_all')) THEN
        v_has_access := true;
      ELSIF (SELECT public.check_permission(v_actor_id, 'visit_plans.read_team')) THEN
        IF v_creator_branch_id = v_target_branch_id THEN
          v_has_access := true;
        END IF;
      END IF;

      IF NOT v_has_access THEN
        RAISE EXCEPTION 'غير مصرح لك بالوصول أو تنفيذ العمليات على هذه الخطة خارج نطاق فرعك التنظيمي';
      END IF;

      -- 2. قفل البنود بترتيب ثابت لمنع المآزق
      PERFORM 1
      FROM public.visit_plan_items
      WHERE plan_id = p_plan_id
      ORDER BY id
      FOR UPDATE;

      SELECT
        COUNT(id) FILTER (WHERE status = 'pending'),
        COUNT(id) FILTER (WHERE status = 'in_progress')
      INTO v_pending_count, v_in_progress_count
      FROM public.visit_plan_items
      WHERE plan_id = p_plan_id;

      IF v_in_progress_count > 0 THEN
        RAISE EXCEPTION 'لا يمكن الإغلاق الإداري أثناء وجود زيارة جارية ميدانياً';
      END IF;

      IF v_pending_count = 0 THEN
        RAISE EXCEPTION 'يجب وجود بند معلق (pending) واحد على الأقل لإجراء الإغلاق الإداري';
      END IF;

      -- تحويل البنود المعلقة إلى skipped
      UPDATE public.visit_plan_items
      SET status = 'skipped',
          skip_reason = p_close_reason,
          updated_at = clock_timestamp()
      WHERE plan_id = p_plan_id AND status = 'pending';

      -- تحديث عدادات وحالة الخطة تلقائياً لتصل للحالة النهائية
      PERFORM private.recalculate_visit_plan_counts(p_plan_id);

      -- التحقق من حالة الخطة بعد الاحتساب
      SELECT status INTO v_plan_status
      FROM public.visit_plans
      WHERE id = p_plan_id;

      IF v_plan_status NOT IN ('completed', 'partial', 'missed') THEN
        RAISE EXCEPTION 'لم تصل الخطة إلى حالة إغلاق نهائي بعد احتساب العدادات';
      END IF;

      -- تحديث حقول الإغلاق الإداري
      UPDATE public.visit_plans
      SET administrative_close_reason = p_close_reason,
          updated_at = clock_timestamp()
      WHERE id = p_plan_id;

      SELECT jsonb_build_object(
        'plan_id', id,
        'status', status,
        'skipped_count', skipped_count,
        'administrative_closed_by', administrative_closed_by,
        'administrative_closed_at', administrative_closed_at,
        'administrative_close_reason', administrative_close_reason
      ) INTO v_result_data
      FROM public.visit_plans
      WHERE id = p_plan_id;
    END;

    UPDATE private.visit_operation_requests
    SET status = 'completed', completed_at = clock_timestamp(), result_json = v_result_data, updated_at = clock_timestamp()
    WHERE operation_id = p_operation_id;

    RETURN jsonb_build_object(
      'ok', true,
      'operation_id', p_operation_id,
      'operation', 'close_visit_plan_administratively_atomic',
      'replayed', false,
      'data', v_result_data
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

      RETURN jsonb_build_object(
        'ok', false,
        'operation_id', p_operation_id,
        'operation', 'close_visit_plan_administratively_atomic',
        'replayed', false,
        'error', jsonb_build_object('code', v_safe_code, 'message', v_safe_message)
      );
    END;
  END;
END;
$$;

REVOKE ALL ON FUNCTION private.close_visit_plan_administratively_atomic_impl(UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.close_visit_plan_administratively_atomic_impl(UUID, UUID, TEXT) TO authenticated;


-- ─── 3. الدوال العامة التي تعمل كـ Wrappers (SECURITY INVOKER) ───

-- 3.أ) public.create_visit_plan_atomic
CREATE OR REPLACE FUNCTION public.create_visit_plan_atomic(
  p_operation_id UUID,
  p_employee_id  UUID,
  p_plan_date    DATE,
  p_plan_type    VARCHAR(20),
  p_notes        TEXT,
  p_items        JSONB
)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
  SELECT private.create_visit_plan_atomic_impl(
    p_operation_id,
    p_employee_id,
    p_plan_date,
    p_plan_type,
    p_notes,
    p_items
  );
$$;

REVOKE ALL ON FUNCTION public.create_visit_plan_atomic(UUID, UUID, DATE, VARCHAR, TEXT, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_visit_plan_atomic(UUID, UUID, DATE, VARCHAR, TEXT, JSONB) TO authenticated;


-- 3.ب) public.confirm_visit_plan_atomic
CREATE OR REPLACE FUNCTION public.confirm_visit_plan_atomic(
  p_operation_id UUID,
  p_plan_id      UUID
)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
  SELECT private.confirm_visit_plan_atomic_impl(
    p_operation_id,
    p_plan_id
  );
$$;

REVOKE ALL ON FUNCTION public.confirm_visit_plan_atomic(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_visit_plan_atomic(UUID, UUID) TO authenticated;


-- 3.ج) public.cancel_visit_plan_atomic
CREATE OR REPLACE FUNCTION public.cancel_visit_plan_atomic(
  p_operation_id        UUID,
  p_plan_id             UUID,
  p_cancellation_reason TEXT
)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
  SELECT private.cancel_visit_plan_atomic_impl(
    p_operation_id,
    p_plan_id,
    p_cancellation_reason
  );
$$;

REVOKE ALL ON FUNCTION public.cancel_visit_plan_atomic(UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_visit_plan_atomic(UUID, UUID, TEXT) TO authenticated;


-- 3.د) public.reorder_visit_plan_items_atomic
CREATE OR REPLACE FUNCTION public.reorder_visit_plan_items_atomic(
  p_operation_id UUID,
  p_plan_id      UUID,
  p_reorder_data JSONB
)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
  SELECT private.reorder_visit_plan_items_atomic_impl(
    p_operation_id,
    p_plan_id,
    p_reorder_data
  );
$$;

REVOKE ALL ON FUNCTION public.reorder_visit_plan_items_atomic(UUID, UUID, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reorder_visit_plan_items_atomic(UUID, UUID, JSONB) TO authenticated;


-- 3.هـ) public.close_visit_plan_administratively_atomic
CREATE OR REPLACE FUNCTION public.close_visit_plan_administratively_atomic(
  p_operation_id UUID,
  p_plan_id      UUID,
  p_close_reason TEXT
)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
  SELECT private.close_visit_plan_administratively_atomic_impl(
    p_operation_id,
    p_plan_id,
    p_close_reason
  );
$$;

REVOKE ALL ON FUNCTION public.close_visit_plan_administratively_atomic(UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.close_visit_plan_administratively_atomic(UUID, UUID, TEXT) TO authenticated;

COMMIT;
