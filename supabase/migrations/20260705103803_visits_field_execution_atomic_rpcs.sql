BEGIN;

-- =============================================================================
-- EDARA v2 — 20260705103803_visits_field_execution_atomic_rpcs.sql
-- المرحلة «هـ»: دوال ومسارات وعقود تحقق التنفيذ الميداني الذري وإحباط التكرار والنزاعات
-- =============================================================================

-- ─── 0. التحقق الساكن المسبق من عدم وجود روابط ثنائية غير متطابقة تاريخياً ───
DO $$
DECLARE
  v_mismatch_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_mismatch_count
  FROM (
    SELECT vpi.id
    FROM public.visit_plan_items vpi
    JOIN public.activities a ON a.id = vpi.activity_id
    WHERE a.visit_plan_item_id IS DISTINCT FROM vpi.id

    UNION

    SELECT vpi.id
    FROM public.activities a
    JOIN public.visit_plan_items vpi ON vpi.id = a.visit_plan_item_id
    WHERE vpi.activity_id IS DISTINCT FROM a.id AND a.deleted_at IS NULL

    UNION

    SELECT vpi.id
    FROM public.visit_plan_items vpi
    JOIN public.activities a ON a.id = vpi.activity_id
    WHERE a.deleted_at IS NOT NULL
  ) mismatch;

  IF v_mismatch_count > 0 THEN
    RAISE EXCEPTION 'تم رصد % علاقة ربط ثنائية غير متطابقة أو تشير إلى أنشطة محذوفة تاريخياً. يرجى مراجعة وتعديل البيانات يدوياً من قبل الإدارة.', v_mismatch_count;
  END IF;
END;
$$;

-- ─── 0.ب. التحقق الساكن المسبق لسلامة صفوف draft/pending تاريخياً من بيانات التنفيذ ───
DO $$
DECLARE
  v_invalid_rows_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_invalid_rows_count
  FROM public.visit_plan_items vpi
  JOIN public.visit_plans vp ON vp.id = vpi.plan_id
  WHERE (vp.status = 'draft' AND vpi.status = 'pending')
    AND (
      vpi.activity_id IS NOT NULL
      OR vpi.gps_lat IS NOT NULL
      OR vpi.gps_lng IS NOT NULL
      OR vpi.end_gps_lat IS NOT NULL
      OR vpi.end_gps_lng IS NOT NULL
      OR vpi.start_lat IS NOT NULL
      OR vpi.start_lng IS NOT NULL
      OR vpi.start_accuracy_m IS NOT NULL
      OR vpi.start_distance_m IS NOT NULL
      OR vpi.end_lat IS NOT NULL
      OR vpi.end_lng IS NOT NULL
      OR vpi.end_accuracy_m IS NOT NULL
      OR vpi.end_distance_m IS NOT NULL
      OR vpi.server_started_at IS NOT NULL
      OR vpi.server_completed_at IS NOT NULL
      OR vpi.client_started_at IS NOT NULL
      OR vpi.client_completed_at IS NOT NULL
      OR vpi.gps_validation_status != 'not_checked'
      OR vpi.gps_review_status != 'not_required'
      OR vpi.gps_exception_reason IS NOT NULL
      OR vpi.gps_exception_requested_by IS NOT NULL
      OR vpi.gps_exception_reviewed_by IS NOT NULL
      OR vpi.gps_exception_reviewed_at IS NOT NULL
      OR vpi.skip_reason IS NOT NULL
      OR vpi.reschedule_to IS NOT NULL
      OR vpi.replacement_item_id IS NOT NULL
      OR vpi.rescheduled_from_item_id IS NOT NULL
      OR vpi.actual_arrival_time IS NOT NULL
      OR vpi.actual_start_time IS NOT NULL
      OR vpi.actual_end_time IS NOT NULL
      OR vpi.device_timezone IS NOT NULL
      OR vpi.stale_since IS NOT NULL
      OR (vpi.metadata IS NOT NULL AND vpi.metadata != '{}'::jsonb)
    );

  IF v_invalid_rows_count > 0 THEN
    RAISE EXCEPTION 'تم رصد % بند زيارة تاريخي في حالة مسودة/انتظار يحتوي على بيانات تنفيذ أو GPS غير افتراضية. يرجى تنظيفها أو مراجعتها يدوياً لتفادي حظر التحديثات بعد تطبيق السياسة.', v_invalid_rows_count;
  END IF;
END;
$$;


-- ─── 1. تعديل القيود والصلاحيات وتحديث سياسات RLS وقفل مسارات التجاوز ───

-- 1.أ. تعديل القيد المرجعي لنشاط البند ليصبح ON DELETE RESTRICT
ALTER TABLE public.visit_plan_items
  DROP CONSTRAINT IF EXISTS visit_plan_items_activity_id_fkey;

ALTER TABLE public.visit_plan_items
  DROP CONSTRAINT IF EXISTS fk_visit_plan_items_activity;

ALTER TABLE public.visit_plan_items
  ADD CONSTRAINT fk_visit_plan_items_activity
  FOREIGN KEY (activity_id)
  REFERENCES public.activities(id)
  ON DELETE RESTRICT;

-- 1.ب. إسقاط التريجر التلقائي لمزامنة الأنشطة مع بنود الزيارة لمنع التعديل غير المنسق
DROP TRIGGER IF EXISTS trg_activities_sync_visit_item ON public.activities;
DROP FUNCTION IF EXISTS public.sync_visit_item_from_activity();

-- تهيئة مبكرة لحقل سبب إعادة الجدولة قبل أي ACL أو Policy تشير إليه
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'visit_plan_items'
      AND column_name = 'reschedule_reason'
  ) THEN
    -- تدقيق البيانات التاريخية لمنع تجاوز 500 حرف
    IF EXISTS (
      SELECT 1 FROM public.visit_plan_items
      WHERE char_length(reschedule_reason) > 500
    ) THEN
      RAISE EXCEPTION 'البيانات التاريخية في reschedule_reason تتجاوز 500 حرف؛ يرجى مراجعتها يدوياً';
    END IF;

    -- تطبيع العمود ونوعه وحجمه
    ALTER TABLE public.visit_plan_items ALTER COLUMN reschedule_reason TYPE VARCHAR(500) USING reschedule_reason::VARCHAR(500);
  ELSE
    ALTER TABLE public.visit_plan_items ADD COLUMN reschedule_reason VARCHAR(500);
  END IF;

  -- إضافة القيد المسمى بشكل صريح للتحقق من طول reschedule_reason
  ALTER TABLE public.visit_plan_items DROP CONSTRAINT IF EXISTS chk_visit_plan_items_reschedule_reason_len;
  ALTER TABLE public.visit_plan_items ADD CONSTRAINT chk_visit_plan_items_reschedule_reason_len CHECK (char_length(reschedule_reason) <= 500);
END;
$$;

-- 1.ج. قيد صلاحية التحديث على حقول الجدولة والترتيب فقط ومنع تعديل حقول التنفيذ والـGPS سحباً ومنحاً
REVOKE UPDATE ON TABLE public.visit_plan_items FROM PUBLIC, anon, authenticated;

REVOKE UPDATE (
  id, plan_id, customer_id, customer_branch_id, sequence, planned_time, estimated_duration_min,
  priority, purpose, purpose_type, status, actual_arrival_time, actual_start_time, actual_end_time,
  activity_id, skip_reason, reschedule_to, created_at, updated_at, expected_location_source,
  expected_location_id, expected_lat, expected_lng, start_lat, start_lng, start_accuracy_m,
  start_distance_m, end_lat, end_lng, end_accuracy_m, end_distance_m, server_started_at,
  server_completed_at, client_started_at, client_completed_at, device_timezone, gps_validation_status,
  gps_review_status, gps_exception_reason, gps_exception_requested_by, gps_exception_reviewed_by,
  gps_exception_reviewed_at, rescheduled_from_item_id, replacement_item_id, stale_since,
  gps_lat, gps_lng, end_gps_lat, end_gps_lng, metadata, reschedule_reason
) ON public.visit_plan_items FROM PUBLIC, anon, authenticated;

GRANT UPDATE (
  planned_time,
  estimated_duration_min,
  priority,
  purpose,
  purpose_type
) ON public.visit_plan_items TO authenticated;

-- 1.د. تحديث سياسة vpi_update لتطبيق التحققات الموزعة بين USING و WITH CHECK
DROP POLICY IF EXISTS "vpi_update" ON public.visit_plan_items;

CREATE POLICY "vpi_update" ON public.visit_plan_items
  FOR UPDATE
  TO authenticated
  USING (
    status = 'pending'
    AND EXISTS (
      SELECT 1 FROM public.visit_plans vp
      WHERE vp.id = plan_id
        AND vp.status = 'draft'
        AND (
          (vp.employee_id IN (SELECT id FROM hr_employees WHERE user_id = (SELECT auth.uid())) AND check_permission((SELECT auth.uid()), 'visit_plans.update_own')) OR
          (check_permission((SELECT auth.uid()), 'visit_plans.update') AND (
            check_permission((SELECT auth.uid()), 'visit_plans.read_all') OR
            (check_permission((SELECT auth.uid()), 'visit_plans.read_team') AND vp.organizational_branch_id IN (SELECT branch_id FROM hr_employees WHERE user_id = (SELECT auth.uid())))
          ))
        )
    )
  )
  WITH CHECK (
    status = 'pending'
    AND EXISTS (
      SELECT 1 FROM public.visit_plans vp
      WHERE vp.id = plan_id
        AND vp.status = 'draft'
        AND (
          (vp.employee_id IN (SELECT id FROM hr_employees WHERE user_id = (SELECT auth.uid())) AND check_permission((SELECT auth.uid()), 'visit_plans.update_own')) OR
          (check_permission((SELECT auth.uid()), 'visit_plans.update') AND (
            check_permission((SELECT auth.uid()), 'visit_plans.read_all') OR
            (check_permission((SELECT auth.uid()), 'visit_plans.read_team') AND vp.organizational_branch_id IN (SELECT branch_id FROM hr_employees WHERE user_id = (SELECT auth.uid())))
          ))
        )
    )
    AND activity_id IS NULL
    AND gps_lat IS NULL
    AND gps_lng IS NULL
    AND end_gps_lat IS NULL
    AND end_gps_lng IS NULL
    AND start_lat IS NULL
    AND start_lng IS NULL
    AND start_accuracy_m IS NULL
    AND start_distance_m IS NULL
    AND end_lat IS NULL
    AND end_lng IS NULL
    AND end_accuracy_m IS NULL
    AND end_distance_m IS NULL
    AND server_started_at IS NULL
    AND server_completed_at IS NULL
    AND client_started_at IS NULL
    AND client_completed_at IS NULL
    AND gps_validation_status = 'not_checked'
    AND gps_review_status = 'not_required'
    AND gps_exception_reason IS NULL
    AND gps_exception_requested_by IS NULL
    AND gps_exception_reviewed_by IS NULL
    AND gps_exception_reviewed_at IS NULL
    AND skip_reason IS NULL
    AND reschedule_to IS NULL
    AND reschedule_reason IS NULL
    AND replacement_item_id IS NULL
    AND rescheduled_from_item_id IS NULL
    AND actual_arrival_time IS NULL
    AND actual_start_time IS NULL
    AND actual_end_time IS NULL
    AND device_timezone IS NULL
    AND stale_since IS NULL
    AND (metadata IS NULL OR metadata = '{}'::jsonb)
  );

-- 1.هـ. تعديل سياسات activities لمنع الإدخال أو التعديل المباشر للأنشطة المرتبطة ببند زيارة
DROP POLICY IF EXISTS "acts_insert" ON public.activities;

CREATE POLICY "acts_insert" ON public.activities
  FOR INSERT
  TO authenticated
  WITH CHECK (
    visit_plan_item_id IS NULL
    AND employee_id IN (SELECT id FROM hr_employees WHERE user_id = (SELECT auth.uid()))
    AND created_by = (SELECT auth.uid())
    AND check_permission((SELECT auth.uid()), 'activities.create')
  );

DROP POLICY IF EXISTS "acts_update" ON public.activities;

CREATE POLICY "acts_update" ON public.activities
  FOR UPDATE
  TO authenticated
  USING (
    visit_plan_item_id IS NULL
    AND (
      (employee_id IN (SELECT id FROM hr_employees WHERE user_id = (SELECT auth.uid())) AND check_permission((SELECT auth.uid()), 'activities.update_own'::text) AND created_at > (now() - '24:00:00'::interval))
      OR check_permission((SELECT auth.uid()), 'activities.read_all'::text)
    )
  )
  WITH CHECK (
    visit_plan_item_id IS NULL
    AND (
      (employee_id IN (SELECT id FROM hr_employees WHERE user_id = (SELECT auth.uid())) AND check_permission((SELECT auth.uid()), 'activities.update_own'::text) AND created_at > (now() - '24:00:00'::interval))
      OR check_permission((SELECT auth.uid()), 'activities.read_all'::text)
    )
  );

-- 1.و. تعديل سياسات visit_checklist_responses لمنع الإدخال المباشر للإجابات المرتبطة بالزيارات
DROP POLICY IF EXISTS "checklist_responses_insert" ON public.visit_checklist_responses;

CREATE POLICY "checklist_responses_insert" ON public.visit_checklist_responses
  FOR INSERT
  TO authenticated
  WITH CHECK (
    NOT EXISTS (
      SELECT 1 FROM public.activities a
      WHERE a.id = activity_id AND a.visit_plan_item_id IS NOT NULL
    )
    AND (
      check_permission((SELECT auth.uid()), 'activities.update_own'::text)
      OR check_permission((SELECT auth.uid()), 'activities.read_team'::text)
      OR check_permission((SELECT auth.uid()), 'activities.read_all'::text)
    )
  );

DROP POLICY IF EXISTS "checklist_responses_update" ON public.visit_checklist_responses;

CREATE POLICY "checklist_responses_update" ON public.visit_checklist_responses
  FOR UPDATE
  TO authenticated
  USING (
    NOT EXISTS (
      SELECT 1 FROM public.activities a
      WHERE a.id = activity_id AND a.visit_plan_item_id IS NOT NULL
    )
    AND EXISTS (
      SELECT 1 FROM public.activities a
      WHERE a.id = activity_id
        AND a.created_by = (SELECT auth.uid())
    )
    AND check_permission((SELECT auth.uid()), 'activities.update_own'::text)
  )
  WITH CHECK (
    NOT EXISTS (
      SELECT 1 FROM public.activities a
      WHERE a.id = activity_id AND a.visit_plan_item_id IS NOT NULL
    )
    AND EXISTS (
      SELECT 1 FROM public.activities a
      WHERE a.id = activity_id
        AND a.created_by = (SELECT auth.uid())
    )
    AND check_permission((SELECT auth.uid()), 'activities.update_own'::text)
  );

-- 1.ز. التحقق من التكرارات التاريخية وإدخال فهرس فريد جزئي لمنع تعدد الأنشطة الفعالة للبند الواحد
DO $$
DECLARE
  v_dup_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_dup_count
  FROM (
    SELECT visit_plan_item_id
    FROM public.activities
    WHERE visit_plan_item_id IS NOT NULL AND deleted_at IS NULL
    GROUP BY visit_plan_item_id
    HAVING COUNT(*) > 1
  ) dup;

  IF v_dup_count > 0 THEN
    RAISE EXCEPTION 'يوجد % بند زيارة مرتبط بأكثر من نشاط فعال تاريخياً. تعذر إنشاء الفهرس الفريد؛ يرجى مراجعة وتصفية البيانات يدوياً من قبل الإدارة.', v_dup_count;
  END IF;
END;
$$;

CREATE UNIQUE INDEX idx_activities_unique_visit_plan_item
  ON public.activities(visit_plan_item_id)
  WHERE visit_plan_item_id IS NOT NULL AND deleted_at IS NULL;

-- 1.ح. إدراج وتأكيد القيم الافتراضية للنظام والتحقق
INSERT INTO public.company_settings (key, value, type, description, category, is_public) VALUES
  ('activities.visit_gps_radius_meters', '250', 'number', 'نطاق مطابقة الموقع الجغرافي بالمتر لبنود خطة الزيارة', 'activities', false),
  ('activities.visit_gps_accuracy_threshold_meters', '100', 'number', 'حد الدقة المسموح به لجهاز تحديد المواقع بالمتر لتسجيل الزيارات', 'activities', false),
  ('company.timezone', 'Africa/Cairo', 'text', 'المنطقة الزمنية الرسمية للشركة لتسجيل ومعالجة العمليات الميدانية والمالية', 'general', false)
ON CONFLICT (key) DO NOTHING;

-- ─── 2. دوال التحقق الجغرافي والمسافات (Haversine) ───

CREATE OR REPLACE FUNCTION private.calculate_haversine_distance(
  lat1 NUMERIC,
  lng1 NUMERIC,
  lat2 NUMERIC,
  lng2 NUMERIC
)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
STRICT
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
DECLARE
  r       DOUBLE PRECISION := 6371000.0; -- Earth's radius in meters
  phi1    DOUBLE PRECISION;
  phi2    DOUBLE PRECISION;
  dphi    DOUBLE PRECISION;
  dlambda DOUBLE PRECISION;
  a       DOUBLE PRECISION;
  c       DOUBLE PRECISION;
BEGIN
  phi1 := radians(lat1::double precision);
  phi2 := radians(lat2::double precision);
  dphi := radians((lat2 - lat1)::double precision);
  dlambda := radians((lng2 - lng1)::double precision);

  a := sin(dphi / 2.0) * sin(dphi / 2.0) +
       cos(phi1) * cos(phi2) *
       sin(dlambda / 2.0) * sin(dlambda / 2.0);

  IF a > 1.0 THEN
    a := 1.0;
  ELSIF a < 0.0 THEN
    a := 0.0;
  END IF;

  c := 2.0 * atan2(sqrt(a), sqrt(1.0 - a));

  RETURN (r * c)::numeric;
END;
$$;

REVOKE ALL ON FUNCTION private.calculate_haversine_distance(NUMERIC, NUMERIC, NUMERIC, NUMERIC) FROM PUBLIC, anon, authenticated;


-- ─── 3. دالة بدء الزيارة الذرية (start_visit_item_atomic) ───

CREATE OR REPLACE FUNCTION private.start_visit_item_atomic_impl(
  p_operation_id UUID,
  p_item_id UUID,
  p_start_lat NUMERIC,
  p_start_lng NUMERIC,
  p_start_accuracy_m NUMERIC,
  p_client_started_at TIMESTAMPTZ,
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

  v_server_time         TIMESTAMPTZ;
  v_plan_id             UUID;
  v_plan_status         VARCHAR(20);
  v_target_employee_id  UUID;
  v_target_branch_id    UUID;
  v_item_status         VARCHAR(20);
  v_creator_employee_id UUID;
  v_creator_branch_id   UUID;
  v_radius_threshold    NUMERIC;
  v_accuracy_threshold  NUMERIC;
  v_exp_lat             NUMERIC;
  v_exp_lng             NUMERIC;
  v_start_distance      NUMERIC;
  v_start_accuracy      NUMERIC;
  v_start_gps_status    VARCHAR(20);
  v_result_data         JSONB;
  v_safe_message        VARCHAR(250);
  v_safe_code           VARCHAR(50);
BEGIN
  -- 1. التحقق من معرف العملية
  IF p_operation_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', NULL::UUID,
      'operation', 'start_visit_item_atomic',
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
      'operation', 'start_visit_item_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'UNAUTHORIZED',
        'message', 'المستخدم غير مصرح له أو الجلسة منتهية'
      )
    );
  END IF;

  -- 3. بناء الحمولة الموحدة وتشفيرها
  v_payload := jsonb_build_object(
    'operation_name', 'start_visit_item_atomic',
    'item_id', p_item_id,
    'start_lat', p_start_lat,
    'start_lng', p_start_lng,
    'start_accuracy_m', p_start_accuracy_m,
    'client_started_at', p_client_started_at,
    'device_timezone', p_device_timezone
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
    'start_visit_item_atomic',
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
     v_req_op IS DISTINCT FROM 'start_visit_item_atomic' OR
     v_req_hash IS DISTINCT FROM v_hash THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'start_visit_item_atomic',
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
      'operation', 'start_visit_item_atomic',
      'replayed', true,
      'data', v_req_result
    );
  END IF;

  IF v_req_status = 'failed' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'start_visit_item_atomic',
      'replayed', true,
      'error', v_req_result -> 'error'
    );
  END IF;

  IF v_req_status = 'processing' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'start_visit_item_atomic',
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
      started_at = clock_timestamp()
  WHERE operation_id = p_operation_id;

  -- 5. تنفيذ منطق معالجة عملية البدء (كل التحقق داخل الـ block المعزول)
  BEGIN
    v_server_time := clock_timestamp();

    -- قفل الخطة والبند بالترتيب الهرمي
    SELECT vp.status, vp.employee_id, vp.organizational_branch_id, vp.id, vpi.status, vpi.expected_lat, vpi.expected_lng
    INTO v_plan_status, v_target_employee_id, v_target_branch_id, v_plan_id, v_item_status, v_exp_lat, v_exp_lng
    FROM public.visit_plans vp
    JOIN public.visit_plan_items vpi ON vpi.plan_id = vp.id
    WHERE vpi.id = p_item_id
    FOR UPDATE;

    IF v_plan_id IS NULL THEN
      RAISE EXCEPTION 'بند خطة الزيارة غير موجود';
    END IF;

    -- التحقق من صلاحيات المندوب والمطابقة المباشرة للملكية والفرع
    IF NOT (SELECT public.check_permission(v_actor_id, 'visit_plans.update_own'::text)) OR
       NOT (SELECT public.check_permission(v_actor_id, 'activities.create'::text)) THEN
      RAISE EXCEPTION 'ليس لديك الصلاحيات الكافية لبدء زيارة ميدانية';
    END IF;

    -- جلب الموظف النشط فقط
    SELECT id, branch_id INTO v_creator_employee_id, v_creator_branch_id
    FROM public.hr_employees
    WHERE user_id = v_actor_id AND status = 'active';

    IF v_creator_employee_id IS NULL THEN
      RAISE EXCEPTION 'لم يتم العثور على سجل موظف نشط مرتبط بالمستخدم الحالي في النظام';
    END IF;

    IF v_creator_employee_id IS DISTINCT FROM v_target_employee_id THEN
      RAISE EXCEPTION 'لا يمكنك بدء زيارة مسندة لموظف آخر';
    END IF;

    IF v_creator_branch_id IS DISTINCT FROM v_target_branch_id THEN
      RAISE EXCEPTION 'فرع الموظف الحالي لا يطابق الفرع التنظيمي للخطة';
    END IF;

    -- التحقق من صحة المنطقة الزمنية
    IF p_device_timezone IS NOT NULL THEN
      IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = p_device_timezone) THEN
        RAISE EXCEPTION 'المنطقة الزمنية للجهاز غير صالحة';
      END IF;
    END IF;

    -- تعارضات المزامنة اللوجستية
    IF v_item_status IS DISTINCT FROM 'pending' THEN
      INSERT INTO private.visit_sync_conflicts (
        operation_id,
        visit_plan_item_id,
        actor_id,
        operation_name,
        conflict_reason_code,
        conflict_payload,
        status
      ) VALUES (
        p_operation_id,
        p_item_id,
        v_actor_id,
        'start_visit_item_atomic',
        'STATUS_CONFLICT',
        jsonb_build_object(
          'expected_status', 'pending',
          'actual_status', v_item_status,
          'plan_id', v_plan_id,
          'plan_status', v_plan_status
        ),
        'pending'
      ) ON CONFLICT (operation_id) DO NOTHING;

      UPDATE private.visit_operation_requests
      SET status = 'failed',
          completed_at = clock_timestamp(),
          error_code = 'SYNC_CONFLICT',
          result_json = jsonb_build_object(
            'error', jsonb_build_object(
              'code', 'SYNC_CONFLICT',
              'message', 'تعذر إكمال العملية لوجود تعارض في مزامنة البيانات؛ يرجى تحديث الصفحة والمحاولة مجدداً.'
            )
          ),
          updated_at = clock_timestamp()
      WHERE operation_id = p_operation_id;

      RETURN jsonb_build_object(
        'ok', false,
        'operation_id', p_operation_id,
        'operation', 'start_visit_item_atomic',
        'replayed', false,
        'error', jsonb_build_object(
          'code', 'SYNC_CONFLICT',
          'message', 'تعذر إكمال العملية لوجود تعارض في مزامنة البيانات؛ يرجى تحديث الصفحة والمحاولة مجدداً.'
        )
      );
    END IF;

    -- التحقق من حالة الخطة المعتمدة
    IF v_plan_status NOT IN ('confirmed', 'in_progress') THEN
      RAISE EXCEPTION 'لا يمكن بدء زيارة إلا إذا كانت خطتها مؤكدة أو جارية';
    END IF;

    -- استخدام hashtextextended لتقليل تصادم advisory locks وإرجاع RETRYABLE_ERROR
    IF NOT pg_try_advisory_xact_lock(hashtextextended(v_target_employee_id::text, 0)) THEN
      UPDATE private.visit_operation_requests
      SET status = 'pending',
          started_at = NULL,
          updated_at = clock_timestamp()
      WHERE operation_id = p_operation_id;

      RETURN jsonb_build_object(
        'ok', false,
        'operation_id', p_operation_id,
        'operation', 'start_visit_item_atomic',
        'replayed', false,
        'error', jsonb_build_object(
          'code', 'RETRYABLE_ERROR',
          'message', 'العملية قيد التنفيذ حالياً لموظف آخر أو مكررة (advisory lock conflict)'
        )
      );
    END IF;

    -- منع بدء زيارتين متزامنتين لنفس المندوب
    IF EXISTS (
      SELECT 1 FROM public.visit_plan_items vpi
      JOIN public.visit_plans vp ON vp.id = vpi.plan_id
      WHERE vp.employee_id = v_target_employee_id
        AND vpi.status = 'in_progress'
    ) THEN
      RAISE EXCEPTION 'الموظف لديه زيارة أخرى جارية حالياً ميدانياً؛ يرجى إنهاء الزيارة الحالية أولاً';
    END IF;

    -- التحقق من اتساق الإحداثيات والدقة
    IF p_start_lat IS NULL AND p_start_accuracy_m IS NOT NULL THEN
      RAISE EXCEPTION 'لا يمكن تحديد دقة الموقع عند غياب الإحداثيات الجغرافية';
    END IF;

    IF (p_start_lat IS NOT NULL AND p_start_lng IS NULL) OR (p_start_lat IS NULL AND p_start_lng IS NOT NULL) THEN
      RAISE EXCEPTION 'يجب توفير إحداثيات خطوط الطول والعرض معاً أو تركهما فارغين معاً';
    END IF;

    IF p_start_lat IS NOT NULL THEN
      IF p_start_lat NOT BETWEEN -90 AND 90 OR p_start_lng NOT BETWEEN -180 AND 180 THEN
        RAISE EXCEPTION 'إحداثيات بدء الزيارة غير صالحة';
      END IF;
      IF p_start_accuracy_m <= 0 THEN
        RAISE EXCEPTION 'دقة موقع البدء يجب أن تكون أكبر من الصفر';
      END IF;
    END IF;

    -- جلب إعدادات الجغرافيا بـ Fallback آمن متكامل
    BEGIN
      SELECT COALESCE(value::numeric, 250) INTO v_radius_threshold
      FROM public.company_settings WHERE key = 'activities.visit_gps_radius_meters';
    EXCEPTION WHEN OTHERS THEN
      v_radius_threshold := 250;
    END;
    IF v_radius_threshold IS NULL OR v_radius_threshold <= 0 THEN
      v_radius_threshold := 250;
    END IF;

    BEGIN
      SELECT COALESCE(value::numeric, 100) INTO v_accuracy_threshold
      FROM public.company_settings WHERE key = 'activities.visit_gps_accuracy_threshold_meters';
    EXCEPTION WHEN OTHERS THEN
      v_accuracy_threshold := 100;
    END;
    IF v_accuracy_threshold IS NULL OR v_accuracy_threshold <= 0 THEN
      v_accuracy_threshold := 100;
    END IF;

    -- حساب مسافة البدء خادمياً بالـ Haversine
    v_start_distance := NULL;
    IF p_start_lat IS NOT NULL AND v_exp_lat IS NOT NULL AND v_exp_lng IS NOT NULL THEN
      v_start_distance := private.calculate_haversine_distance(v_exp_lat, v_exp_lng, p_start_lat, p_start_lng);
    END IF;

    v_start_accuracy := CASE WHEN p_start_lat IS NULL THEN NULL ELSE p_start_accuracy_m END;

    -- تحديد نتيجة التحقق الجغرافي المبدئي
    IF p_start_lat IS NULL OR v_exp_lat IS NULL OR v_exp_lng IS NULL THEN
      v_start_gps_status := 'no_coordinates';
    ELSIF v_start_accuracy IS NULL OR v_start_accuracy > v_accuracy_threshold THEN
      v_start_gps_status := 'failed_accuracy';
    ELSIF v_start_distance IS NULL OR v_start_distance > v_radius_threshold THEN
      v_start_gps_status := 'failed_distance';
    ELSE
      v_start_gps_status := 'passed';
    END IF;

    -- التحديث الفعلي للبند في المعاملة
    UPDATE public.visit_plan_items
    SET status = 'in_progress',
        server_started_at = v_server_time,
        client_started_at = p_client_started_at,
        device_timezone = p_device_timezone,
        actual_start_time = v_server_time,
        start_lat = p_start_lat,
        start_lng = p_start_lng,
        start_accuracy_m = v_start_accuracy,
        start_distance_m = v_start_distance,
        gps_validation_status = v_start_gps_status,
        gps_lat = p_start_lat,
        gps_lng = p_start_lng,
        updated_at = v_server_time
    WHERE id = p_item_id;

    -- بناء مخرجات النتيجة
    SELECT jsonb_build_object(
      'item_id', vpi.id,
      'status', vpi.status,
      'server_started_at', vpi.server_started_at,
      'start_distance_m', vpi.start_distance_m,
      'gps_validation_status', vpi.gps_validation_status,
      'plan_id', vp.id,
      'plan_status', vp.status
    ) INTO v_result_data
    FROM public.visit_plan_items vpi
    JOIN public.visit_plans vp ON vp.id = vpi.plan_id
    WHERE vpi.id = p_item_id;

    -- تحديث حالة الطلب بالاكتمال
    UPDATE private.visit_operation_requests
    SET status = 'completed',
        result_json = v_result_data,
        completed_at = clock_timestamp()
    WHERE operation_id = p_operation_id;

    RETURN jsonb_build_object(
      'ok', true,
      'operation_id', p_operation_id,
      'operation', 'start_visit_item_atomic',
      'replayed', false,
      'data', v_result_data
    );

  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'P0001' THEN
      v_safe_code := 'DOMAIN_VALIDATION_FAILED';
      v_safe_message := 'تعذر تنفيذ العملية لعدم استيفاء شروطها اللوجستية أو الجغرافية';
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
      'operation', 'start_visit_item_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', v_safe_code,
        'message', v_safe_message
      )
    );
  END;
END;
$$;

REVOKE ALL ON FUNCTION private.start_visit_item_atomic_impl(UUID, UUID, NUMERIC, NUMERIC, NUMERIC, TIMESTAMPTZ, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.start_visit_item_atomic_impl(UUID, UUID, NUMERIC, NUMERIC, NUMERIC, TIMESTAMPTZ, VARCHAR) TO authenticated;

-- Wrapper العامة لـ start_visit_item_atomic
CREATE OR REPLACE FUNCTION public.start_visit_item_atomic(
  p_operation_id UUID,
  p_item_id UUID,
  p_start_lat NUMERIC,
  p_start_lng NUMERIC,
  p_start_accuracy_m NUMERIC,
  p_client_started_at TIMESTAMPTZ,
  p_device_timezone VARCHAR(100)
)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
  SELECT private.start_visit_item_atomic_impl(
    p_operation_id,
    p_item_id,
    p_start_lat,
    p_start_lng,
    p_start_accuracy_m,
    p_client_started_at,
    p_device_timezone
  );
$$;

REVOKE ALL ON FUNCTION public.start_visit_item_atomic(UUID, UUID, NUMERIC, NUMERIC, NUMERIC, TIMESTAMPTZ, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_visit_item_atomic(UUID, UUID, NUMERIC, NUMERIC, NUMERIC, TIMESTAMPTZ, VARCHAR) TO authenticated;


-- ─── 4. دالة إكمال الزيارة الذرية (complete_visit_item_atomic) ───

CREATE OR REPLACE FUNCTION private.complete_visit_item_atomic_impl(
  p_operation_id UUID,
  p_item_id UUID,
  p_end_lat NUMERIC,
  p_end_lng NUMERIC,
  p_end_accuracy_m NUMERIC,
  p_client_completed_at TIMESTAMPTZ,
  p_device_timezone VARCHAR(100),
  p_outcome_type VARCHAR(50),
  p_outcome_notes TEXT,
  p_responses JSONB,
  p_order_id UUID,
  p_collection_id UUID,
  p_gps_exception_reason TEXT
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

  v_server_time         TIMESTAMPTZ;
  v_plan_id             UUID;
  v_plan_status         VARCHAR(20);
  v_target_employee_id  UUID;
  v_target_branch_id    UUID;
  v_item_status         VARCHAR(20);
  v_server_started_at   TIMESTAMPTZ;
  v_item_activity_id    UUID;
  v_item_customer_id    UUID;
  v_item_purpose_type   VARCHAR(50);
  v_item_priority       VARCHAR(10);
  v_item_duration       INTEGER;
  v_item_purpose        TEXT;
  v_creator_employee_id UUID;
  v_creator_branch_id   UUID;
  v_radius_threshold    NUMERIC;
  v_accuracy_threshold  NUMERIC;
  v_exp_lat             NUMERIC;
  v_exp_lng             NUMERIC;

  v_start_lat           NUMERIC;
  v_start_lng           NUMERIC;
  v_start_accuracy_m    NUMERIC;
  v_start_distance      NUMERIC;
  v_start_gps_status_recalc VARCHAR(20);

  v_end_distance        NUMERIC;
  v_end_accuracy        NUMERIC;
  v_end_gps_status      VARCHAR(20);
  v_gps_status          VARCHAR(20);
  v_gps_review_status   VARCHAR(20);
  v_gps_exc_reason      VARCHAR(1000);
  v_gps_exc_req_by      UUID;
  v_act_type_id         UUID;
  v_company_tz          VARCHAR(100);
  v_activity_id         UUID;
  v_outcome_type        VARCHAR(50);

  v_ord_customer_id     UUID;
  v_ord_rep_id          UUID;
  v_ord_status          TEXT;
  v_coll_customer_id    UUID;
  v_coll_status         TEXT;
  v_coll_collected_by   UUID;
  v_coll_created_by     UUID;

  v_resp_item           JSONB;
  v_resp_template_id    UUID;
  v_resp_question_id    UUID;
  v_resp_value          TEXT;
  v_resp_json           JSONB;
  v_q_type              VARCHAR(20);
  v_q_min               NUMERIC;
  v_q_max               NUMERIC;
  v_q_required          BOOLEAN;
  v_q_template_id       UUID;
  v_q_options           JSONB;
  v_t_active            BOOLEAN;
  v_t_category          VARCHAR(20);
  v_t_purpose           VARCHAR(50);
  v_t_mandatory         BOOLEAN;
  v_answered_q_ids      UUID[] := ARRAY[]::UUID[];
  v_temp_num            NUMERIC;
  v_photo_path          TEXT;
  v_photo_path_parts    TEXT[];
  v_missing_q_text      TEXT;

  v_result_data         JSONB;
  v_safe_message        VARCHAR(250);
  v_safe_code           VARCHAR(50);
BEGIN
  -- 1. التحقق من معرف العملية
  IF p_operation_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', NULL::UUID,
      'operation', 'complete_visit_item_atomic',
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
      'operation', 'complete_visit_item_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'UNAUTHORIZED',
        'message', 'المستخدم غير مصرح له أو الجلسة منتهية'
      )
    );
  END IF;

  -- 3. بناء الحمولة الموحدة وتشفيرها
  v_payload := jsonb_build_object(
    'operation_name', 'complete_visit_item_atomic',
    'item_id', p_item_id,
    'end_lat', p_end_lat,
    'end_lng', p_end_lng,
    'end_accuracy_m', p_end_accuracy_m,
    'client_completed_at', p_client_completed_at,
    'device_timezone', p_device_timezone,
    'outcome_type', p_outcome_type,
    'outcome_notes', p_outcome_notes,
    'responses', p_responses,
    'order_id', p_order_id,
    'collection_id', p_collection_id,
    'gps_exception_reason', p_gps_exception_reason
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
    'complete_visit_item_atomic',
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
     v_req_op IS DISTINCT FROM 'complete_visit_item_atomic' OR
     v_req_hash IS DISTINCT FROM v_hash THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'complete_visit_item_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'IDEMPOTENCY_KEY_CONFLICT',
        'message', 'تعارض في معرّف العملية (idempotency_key_conflict)'
      )
    );
  END IF;

  IF v_req_status = 'completed' THEN
    RETURN jsonb_build_object(
      'ok', true,
      'operation_id', p_operation_id,
      'operation', 'complete_visit_item_atomic',
      'replayed', true,
      'data', v_req_result
    );
  END IF;

  IF v_req_status = 'failed' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'complete_visit_item_atomic',
      'replayed', true,
      'error', v_req_result -> 'error'
    );
  END IF;

  IF v_req_status = 'processing' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'complete_visit_item_atomic',
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
      started_at = clock_timestamp()
  WHERE operation_id = p_operation_id;

  -- 5. تنفيذ منطق إكمال البند (جميع الفحوصات الجنائية واللوجستية بالداخل)
  BEGIN
    v_server_time := clock_timestamp();

    -- منع تشفيرات Base64 أو Data URLs في المدخلات بالكامل
    IF p_responses::text ILIKE '%data:%' OR p_responses::text ILIKE '%;base64,%' THEN
      RAISE EXCEPTION 'غير مسموح بإرسال نصوص مشفرة بـ Base64 أو Data URLs في الإجابات';
    END IF;

    -- إذا كان p_order_id وp_collection_id غير فارغين معاً، ارفض الطلب صراحةً
    IF p_order_id IS NOT NULL AND p_collection_id IS NOT NULL THEN
      RAISE EXCEPTION 'لا يمكن ربط طلب مبيعات وسند تحصيل معاً في زيارة واحدة؛ يجب تحديد أحدهما فقط أو تركهما فارغين';
    END IF;

    -- قفل الخطة والبند بالترتيب الهرمي
    SELECT vp.status, vp.employee_id, vp.organizational_branch_id, vp.id,
           vpi.status, vpi.server_started_at, vpi.activity_id, vpi.expected_lat, vpi.expected_lng,
           vpi.start_lat, vpi.start_lng, vpi.start_accuracy_m, vpi.customer_id,
           vpi.purpose_type, vpi.priority, vpi.estimated_duration_min, vpi.purpose
    INTO v_plan_status, v_target_employee_id, v_target_branch_id, v_plan_id,
         v_item_status, v_server_started_at, v_item_activity_id, v_exp_lat, v_exp_lng,
         v_start_lat, v_start_lng, v_start_accuracy_m, v_item_customer_id,
         v_item_purpose_type, v_item_priority, v_item_duration, v_item_purpose
    FROM public.visit_plans vp
    JOIN public.visit_plan_items vpi ON vpi.plan_id = vp.id
    WHERE vpi.id = p_item_id
    FOR UPDATE;

    IF v_plan_id IS NULL THEN
      RAISE EXCEPTION 'بند خطة الزيارة غير موجود';
    END IF;

    -- التحقق من الصلاحيات والملكية المباشرة والفرع الموظف
    IF NOT (SELECT public.check_permission(v_actor_id, 'visit_plans.update_own'::text)) OR
       NOT (SELECT public.check_permission(v_actor_id, 'activities.create'::text)) THEN
      RAISE EXCEPTION 'ليس لديك الصلاحيات الكافية لإكمال زيارة ميدانية';
    END IF;

    -- جلب الموظف النشط فقط
    SELECT id, branch_id INTO v_creator_employee_id, v_creator_branch_id
    FROM public.hr_employees
    WHERE user_id = v_actor_id AND status = 'active';

    IF v_creator_employee_id IS NULL THEN
      RAISE EXCEPTION 'لم يتم العثور على سجل موظف نشط مرتبط بالمستخدم الحالي في النظام';
    END IF;

    IF v_creator_employee_id IS DISTINCT FROM v_target_employee_id THEN
      RAISE EXCEPTION 'لا يمكنك تعديل زيارة مسندة لموظف آخر';
    END IF;

    IF v_creator_branch_id IS DISTINCT FROM v_target_branch_id THEN
      RAISE EXCEPTION 'فرع الموظف الحالي لا يطابق الفرع التنظيمي للخطة';
    END IF;

    -- التحقق من المنطقة الزمنية
    IF p_device_timezone IS NOT NULL THEN
      IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = p_device_timezone) THEN
        RAISE EXCEPTION 'المنطقة الزمنية للجهاز غير صالحة';
      END IF;
    END IF;

    -- تعارضات المزامنة اللوجستية
    IF v_item_status IS DISTINCT FROM 'in_progress' THEN
      INSERT INTO private.visit_sync_conflicts (
        operation_id,
        visit_plan_item_id,
        actor_id,
        operation_name,
        conflict_reason_code,
        conflict_payload,
        status
      ) VALUES (
        p_operation_id,
        p_item_id,
        v_actor_id,
        'complete_visit_item_atomic',
        'STATUS_CONFLICT',
        jsonb_build_object(
          'expected_status', 'in_progress',
          'actual_status', v_item_status,
          'plan_id', v_plan_id,
          'plan_status', v_plan_status
        ),
        'pending'
      ) ON CONFLICT (operation_id) DO NOTHING;

      UPDATE private.visit_operation_requests
      SET status = 'failed',
          completed_at = clock_timestamp(),
          error_code = 'SYNC_CONFLICT',
          result_json = jsonb_build_object(
            'error', jsonb_build_object(
              'code', 'SYNC_CONFLICT',
              'message', 'تعذر إكمال العملية لوجود تعارض في مزامنة البيانات؛ يرجى تحديث الصفحة والمحاولة مجدداً.'
            )
          ),
          updated_at = clock_timestamp()
      WHERE operation_id = p_operation_id;

      RETURN jsonb_build_object(
        'ok', false,
        'operation_id', p_operation_id,
        'operation', 'complete_visit_item_atomic',
        'replayed', false,
        'error', jsonb_build_object(
          'code', 'SYNC_CONFLICT',
          'message', 'تعذر إكمال العملية لوجود تعارض في مزامنة البيانات؛ يرجى تحديث الصفحة والمحاولة مجدداً.'
        )
      );
    END IF;

    -- التحقق من تاريخ البدء والنشاط الفعال
    IF v_server_started_at IS NULL THEN
      RAISE EXCEPTION 'تاريخ بدء الخادم (server_started_at) مفقود';
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.activities
      WHERE visit_plan_item_id = p_item_id AND deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION 'البند مرتبط بنشاط فعال مسبقاً في الجداول';
    END IF;

    -- التحقق من حالة الخطة المعتمدة
    IF v_plan_status NOT IN ('confirmed', 'in_progress') THEN
      RAISE EXCEPTION 'لا يمكن إكمال زيارة إلا إذا كانت خطتها مؤكدة أو جارية';
    END IF;

    -- التحقق من اتساق الإحداثيات والدقة النهائية
    IF p_end_lat IS NULL AND p_end_accuracy_m IS NOT NULL THEN
      RAISE EXCEPTION 'لا يمكن تحديد دقة الموقع عند غياب الإحداثيات الجغرافية';
    END IF;

    IF (p_end_lat IS NOT NULL AND p_end_lng IS NULL) OR (p_end_lat IS NULL AND p_end_lng IS NOT NULL) THEN
      RAISE EXCEPTION 'يجب توفير إحداثيات خطوط الطول والعرض معاً أو تركهما فارغين معاً';
    END IF;

    IF p_end_lat IS NOT NULL THEN
      IF p_end_lat NOT BETWEEN -90 AND 90 OR p_end_lng NOT BETWEEN -180 AND 180 THEN
        RAISE EXCEPTION 'إحداثيات نهاية الزيارة غير صالحة';
      END IF;
      IF p_end_accuracy_m <= 0 THEN
        RAISE EXCEPTION 'دقة موقع النهاية يجب أن تكون أكبر من الصفر';
      END IF;
    END IF;

    -- جلب إعدادات الجغرافيا بـ Fallback آمن
    BEGIN
      SELECT COALESCE(value::numeric, 250) INTO v_radius_threshold
      FROM public.company_settings WHERE key = 'activities.visit_gps_radius_meters';
    EXCEPTION WHEN OTHERS THEN
      v_radius_threshold := 250;
    END;
    IF v_radius_threshold IS NULL OR v_radius_threshold <= 0 THEN
      v_radius_threshold := 250;
    END IF;

    BEGIN
      SELECT COALESCE(value::numeric, 100) INTO v_accuracy_threshold
      FROM public.company_settings WHERE key = 'activities.visit_gps_accuracy_threshold_meters';
    EXCEPTION WHEN OTHERS THEN
      v_accuracy_threshold := 100;
    END;
    IF v_accuracy_threshold IS NULL OR v_accuracy_threshold <= 0 THEN
      v_accuracy_threshold := 100;
    END IF;

    -- إعادة حساب مسافة البداية خادمياً بالـ Haversine
    v_start_distance := NULL;
    IF v_start_lat IS NOT NULL AND v_exp_lat IS NOT NULL AND v_exp_lng IS NOT NULL THEN
      v_start_distance := private.calculate_haversine_distance(v_exp_lat, v_exp_lng, v_start_lat, v_start_lng);
    END IF;

    -- إعادة حساب دقة وتحديد نتيجة الطرف المبدئي وفق الحدود الحالية
    IF v_start_lat IS NULL OR v_exp_lat IS NULL OR v_exp_lng IS NULL THEN
      v_start_gps_status_recalc := 'no_coordinates';
    ELSIF v_start_accuracy_m IS NULL OR v_start_accuracy_m > v_accuracy_threshold THEN
      v_start_gps_status_recalc := 'failed_accuracy';
    ELSIF v_start_distance IS NULL OR v_start_distance > v_radius_threshold THEN
      v_start_gps_status_recalc := 'failed_distance';
    ELSE
      v_start_gps_status_recalc := 'passed';
    END IF;

    -- حساب مسافة النهاية خادمياً
    v_end_distance := NULL;
    IF p_end_lat IS NOT NULL AND v_exp_lat IS NOT NULL AND v_exp_lng IS NOT NULL THEN
      v_end_distance := private.calculate_haversine_distance(v_exp_lat, v_exp_lng, p_end_lat, p_end_lng);
    END IF;

    v_end_accuracy := CASE WHEN p_end_lat IS NULL THEN NULL ELSE p_end_accuracy_m END;

    -- تحديد نتيجة التحقق الجغرافي للطرف النهائي
    IF p_end_lat IS NULL OR v_exp_lat IS NULL OR v_exp_lng IS NULL THEN
      v_end_gps_status := 'no_coordinates';
    ELSIF v_end_accuracy IS NULL OR v_end_accuracy > v_accuracy_threshold THEN
      v_end_gps_status := 'failed_accuracy';
    ELSIF v_end_distance IS NULL OR v_end_distance > v_radius_threshold THEN
      v_end_gps_status := 'failed_distance';
    ELSE
      v_end_gps_status := 'passed';
    END IF;

    -- دمج التقييم النهائي بين البداية الحقيقية المعاد حسابها والنهاية
    IF v_start_gps_status_recalc = 'no_coordinates' OR v_end_gps_status = 'no_coordinates' THEN
      v_gps_status := 'no_coordinates';
    ELSIF v_start_gps_status_recalc = 'failed_accuracy' OR v_end_gps_status = 'failed_accuracy' THEN
      v_gps_status := 'failed_accuracy';
    ELSIF v_start_gps_status_recalc = 'failed_distance' OR v_end_gps_status = 'failed_distance' THEN
      v_gps_status := 'failed_distance';
    ELSE
      v_gps_status := 'passed';
    END IF;

    -- تحديد حالة المراجعة للمطابقة الجغرافية
    v_gps_exc_reason := NULL;
    v_gps_exc_req_by := NULL;

    IF v_gps_status = 'passed' THEN
      v_gps_review_status := 'not_required';
    ELSE
      v_gps_review_status := 'pending';

      IF v_gps_status = 'no_coordinates' AND (v_exp_lat IS NULL OR v_exp_lng IS NULL) THEN
        v_gps_exc_reason := 'إحداثيات العميل المعتمدة غير متوفرة في النظام';
        v_gps_exc_req_by := v_actor_id;
      ELSE
        IF NULLIF(BTRIM(p_gps_exception_reason), '') IS NULL THEN
          RAISE EXCEPTION 'يتطلب إكمال الزيارة تسجيل مبرر تجاوز للتحقق الجغرافي (gps_exception_reason)';
        END IF;
        IF char_length(p_gps_exception_reason) > 1000 THEN
          RAISE EXCEPTION 'مبرر تجاوز التحقق الجغرافي يجب ألا يتجاوز 1000 حرف';
        END IF;
        v_gps_exc_reason := p_gps_exception_reason;
        v_gps_exc_req_by := v_actor_id;
      END IF;
    END IF;

    -- الربط المالي والتدقيق وصياغة النتيجة خادمياً
    -- قراءة تحقق لحظية فقط (Snapshot validation) دون قفل صفوف (FOR UPDATE) لمنع تعطيل التدفقات التشغيلية للمبيعات والتحصيلات
    IF p_order_id IS NOT NULL THEN
      SELECT customer_id, rep_id, status INTO v_ord_customer_id, v_ord_rep_id, v_ord_status
      FROM public.sales_orders
      WHERE id = p_order_id;

      IF v_ord_customer_id IS NULL THEN
        RAISE EXCEPTION 'طلب المبيعات المحدد غير موجود';
      END IF;
      IF v_ord_customer_id IS DISTINCT FROM v_item_customer_id THEN
        RAISE EXCEPTION 'طلب المبيعات لا يخص نفس عميل بند الزيارة';
      END IF;
      IF v_ord_rep_id IS DISTINCT FROM v_actor_id THEN
        RAISE EXCEPTION 'لا يمكنك ربط طلب مبيعات لمندوب آخر بالزيارة';
      END IF;
      IF v_ord_status IN ('draft', 'cancelled') THEN
        RAISE EXCEPTION 'لا يمكن ربط زيارة بطلب مبيعات مسودة أو ملغى';
      END IF;
      v_outcome_type := 'order_placed';
    ELSIF p_collection_id IS NOT NULL THEN
      SELECT customer_id, status, collected_by, created_by INTO v_coll_customer_id, v_coll_status, v_coll_collected_by, v_coll_created_by
      FROM public.payment_receipts
      WHERE id = p_collection_id;

      IF v_coll_customer_id IS NULL THEN
        RAISE EXCEPTION 'سند التحصيل المحدد غير موجود';
      END IF;
      IF v_coll_customer_id IS DISTINCT FROM v_item_customer_id THEN
        RAISE EXCEPTION 'سند التحصيل لا يخص نفس عميل بند الزيارة';
      END IF;
      IF v_coll_status IS DISTINCT FROM 'confirmed' THEN
        RAISE EXCEPTION 'لا يمكنك ربط زيارة بسند تحصيل غير مؤكد';
      END IF;
      IF v_coll_collected_by IS DISTINCT FROM v_actor_id AND v_coll_created_by IS DISTINCT FROM v_actor_id THEN
        RAISE EXCEPTION 'لا يمكنك ربط سند تحصيل لم يتم تحصيله أو إنشائه بواسطتك';
      END IF;
      v_outcome_type := 'collection';
    ELSE
      v_outcome_type := p_outcome_type;
      IF v_outcome_type IS NULL THEN
        v_outcome_type := 'visited';
      END IF;
    END IF;

    -- التحقق من نوع النتيجة ضمن القائمة المسموحة الموسعة
    IF v_outcome_type NOT IN (
      'visited', 'order_placed', 'collection', 'refused', 'closed', 'promotion',
      'exploratory', 'followup_scheduled', 'info_only', 'agreed_order',
      'promised_payment', 'followup_visit', 'not_interested'
    ) THEN
      RAISE EXCEPTION 'نوع النتيجة (outcome_type) المحددة غير صالحة للزيارات الميدانية';
    END IF;

    -- تدقيق مصفوفة الاستبيانات
    IF p_responses IS NULL OR jsonb_typeof(p_responses) IS DISTINCT FROM 'array' THEN
      RAISE EXCEPTION 'مصفوفة إجابات الاستبيان مطلوبة';
    END IF;
    IF jsonb_array_length(p_responses) > 300 THEN
      RAISE EXCEPTION 'لا يمكن إرسال أكثر من 300 إجابة في الزيارة الواحدة';
    END IF;

    FOR i IN 0 .. jsonb_array_length(p_responses) - 1 LOOP
      v_resp_item := p_responses -> i;
      IF jsonb_typeof(v_resp_item) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION 'كل إجابة في مصفوفة الاستبيانات يجب أن تكون كائناً';
      END IF;

      -- التحقق من عدم وجود حقول إضافية
      IF EXISTS (
        SELECT 1 FROM jsonb_object_keys(v_resp_item) k
        WHERE k NOT IN ('template_id', 'question_id', 'answer_value', 'answer_json')
      ) THEN
        RAISE EXCEPTION 'إجابة الاستبيان تحتوي على حقول إضافية غير مسموحة';
      END IF;

      BEGIN
        v_resp_template_id := (v_resp_item ->> 'template_id')::UUID;
        v_resp_question_id := (v_resp_item ->> 'question_id')::UUID;
      EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'معرف القالب أو معرف السؤال ليس UUID صالحاً';
      END;

      v_resp_value := v_resp_item ->> 'answer_value';
      v_resp_json := v_resp_item -> 'answer_json';

      IF v_resp_template_id IS NULL OR v_resp_question_id IS NULL THEN
        RAISE EXCEPTION 'معرف القالب ومعرف السؤال مطلوبان لكل إجابة استبيان';
      END IF;

      IF v_resp_question_id = ANY(v_answered_q_ids) THEN
        RAISE EXCEPTION 'لا يمكن تكرار إجابة السؤال في الاستبيان المرسل';
      END IF;
      v_answered_q_ids := array_append(v_answered_q_ids, v_resp_question_id);

      SELECT q.question_type, q.min_value, q.max_value, q.is_required, q.template_id, q.options,
             t.is_active, t.category, t.purpose_type, t.is_mandatory
      INTO v_q_type, v_q_min, v_q_max, v_q_required, v_q_template_id, v_q_options,
           v_t_active, v_t_category, v_t_purpose, v_t_mandatory
      FROM public.visit_checklist_questions q
      JOIN public.visit_checklist_templates t ON t.id = q.template_id
      WHERE q.id = v_resp_question_id AND q.template_id = v_resp_template_id;

      IF v_q_type IS NULL THEN
        RAISE EXCEPTION 'السؤال أو القالب غير موجود أو غير متطابق';
      END IF;

      IF NOT v_t_active OR v_t_category IS DISTINCT FROM 'visit' THEN
        RAISE EXCEPTION 'قالب الاستبيان غير نشط أو غير مخصص للزيارات الميدانية';
      END IF;
      IF v_t_purpose IS NOT NULL AND v_t_purpose IS DISTINCT FROM v_item_purpose_type THEN
        RAISE EXCEPTION 'قالب الاستبيان غير مخصص لغرض البند الحالي';
      END IF;

      -- التحقق من استهلاك الحقول حسب نوع السؤال
      IF v_q_type IN ('text', 'number', 'yes_no', 'single_choice', 'rating') THEN
        IF v_resp_value IS NULL THEN
          RAISE EXCEPTION 'حقل answer_value مطلوب لنوع السؤال';
        END IF;
        IF v_resp_json IS NOT NULL THEN
          RAISE EXCEPTION 'حقل answer_json يجب أن يكون فارغاً لنوع السؤال';
        END IF;
      ELSIF v_q_type IN ('multi_choice', 'photo') THEN
        IF v_resp_json IS NULL THEN
          RAISE EXCEPTION 'حقل answer_json مطلوب لنوع السؤال';
        END IF;
        IF v_resp_value IS NOT NULL THEN
          RAISE EXCEPTION 'حقل answer_value يجب أن يكون فارغاً لنوع السؤال';
        END IF;
      END IF;

      -- التدقيق الفني للأنواع
      IF v_q_type = 'text' THEN
        IF NULLIF(BTRIM(v_resp_value), '') IS NULL THEN
          RAISE EXCEPTION 'قيمة الإجابة النصية للسؤال لا يمكن أن تكون فارغة';
        END IF;
      ELSIF v_q_type = 'number' THEN
        BEGIN
          v_temp_num := v_resp_value::NUMERIC;
        EXCEPTION WHEN OTHERS THEN
          RAISE EXCEPTION 'قيمة السؤال يجب أن تكون رقماً صالحاً';
        END;
        IF v_q_min IS NOT NULL AND v_temp_num < v_q_min THEN
          RAISE EXCEPTION 'قيمة السؤال يجب ألا تقل عن الحد الأدنى';
        END IF;
        IF v_q_max IS NOT NULL AND v_temp_num > v_q_max THEN
          RAISE EXCEPTION 'قيمة السؤال يجب ألا تزيد عن الحد الأقصى';
        END IF;
      ELSIF v_q_type = 'yes_no' THEN
        IF v_resp_value NOT IN ('yes', 'no') THEN
          RAISE EXCEPTION 'قيمة السؤال يجب أن تكون نعم أو لا (yes / no)';
        END IF;
      ELSIF v_q_type = 'single_choice' THEN
        IF NOT EXISTS (
          SELECT 1 FROM jsonb_array_elements(v_q_options) opt
          WHERE (jsonb_typeof(opt) = 'string' AND opt #>> '{}' = v_resp_value)
             OR (jsonb_typeof(opt) = 'object' AND (opt ->> 'value' = v_resp_value OR opt ->> 'label' = v_resp_value))
        ) THEN
          RAISE EXCEPTION 'قيمة الاختيار غير مطابقة للخيارات المتاحة';
        END IF;
      ELSIF v_q_type = 'multi_choice' THEN
        IF jsonb_typeof(v_resp_json) IS DISTINCT FROM 'array' THEN
          RAISE EXCEPTION 'إجابة الاختيار المتعدد يجب أن تكون مصفوفة JSON';
        END IF;
        IF v_q_required AND jsonb_array_length(v_resp_json) = 0 THEN
          RAISE EXCEPTION 'يجب اختيار قيمة واحدة على الأقل للسؤال الإجباري';
        END IF;
        -- التحقق من عدم التكرار الداخلي
        IF EXISTS (
          SELECT val FROM jsonb_array_elements_text(v_resp_json) val
          GROUP BY val HAVING COUNT(*) > 1
        ) THEN
          RAISE EXCEPTION 'لا يمكن تكرار قيم الاختيار في السؤال';
        END IF;
        -- multi_choice يجب أن يرفض أي عنصر ليس JSON string
        IF EXISTS (
          SELECT 1 FROM jsonb_array_elements(v_resp_json) val
          WHERE jsonb_typeof(val) IS DISTINCT FROM 'string'
        ) THEN
          RAISE EXCEPTION 'مصفوفة الاختيار المتعدد يجب أن تحتوي على نصوص فقط';
        END IF;
        -- التحقق من مطابقة الخيارات
        IF EXISTS (
          SELECT 1 FROM jsonb_array_elements_text(v_resp_json) val
          WHERE NOT EXISTS (
            SELECT 1 FROM jsonb_array_elements(v_q_options) opt
            WHERE (jsonb_typeof(opt) = 'string' AND opt #>> '{}' = val)
               OR (jsonb_typeof(opt) = 'object' AND (opt ->> 'value' = val OR opt ->> 'label' = val))
          )
        ) THEN
          RAISE EXCEPTION 'إحدى قيم الاختيار المتعدد غير متوفرة في الخيارات المتاحة';
        END IF;
      ELSIF v_q_type = 'rating' THEN
        BEGIN
          v_temp_num := v_resp_value::NUMERIC;
        EXCEPTION WHEN OTHERS THEN
          RAISE EXCEPTION 'قيمة التقييم يجب أن تكون رقماً صحيحاً';
        END;
        IF v_temp_num IS NULL OR v_temp_num NOT IN (1, 2, 3, 4, 5) THEN
          RAISE EXCEPTION 'قيمة التقييم يجب أن تكون بين 1 و 5 نجوم';
        END IF;
      ELSIF v_q_type = 'photo' THEN
        IF jsonb_typeof(v_resp_json) IS DISTINCT FROM 'object' THEN
          RAISE EXCEPTION 'إجابة الصورة يجب أن تكون كائناً يحتوي مسار التخزين';
        END IF;
        v_photo_path := v_resp_json ->> 'storage_path';
        IF v_photo_path IS NULL OR NULLIF(BTRIM(v_photo_path), '') IS NULL THEN
          RAISE EXCEPTION 'مسار تخزين الصورة (storage_path) مطلوب';
        END IF;
        -- تدقيق وحظر المسارات غير الآمنة والقصيرة والطويلة
        IF char_length(v_photo_path) > 2048 THEN
          RAISE EXCEPTION 'مسار تخزين الصورة طويل جداً';
        END IF;
        -- صيغة Allowlist واضحة ومنع traversal ومقاطع . و ..
        IF position(chr(92) in v_photo_path) > 0 OR
           position('%' in v_photo_path) > 0 OR
           position('?' in v_photo_path) > 0 OR
           position('//' in v_photo_path) > 0 OR
           v_photo_path LIKE '/%' OR
           v_photo_path LIKE '.%' OR
           v_photo_path ~ '(^|/)\.\.?(/|$)' OR
           v_photo_path !~ '^[a-zA-Z0-9_\-\./]+$' THEN
          RAISE EXCEPTION 'مسار تخزين الصورة غير صالح أو غير آمن';
        END IF;

        -- ربط الدليل حصراً بالخطة والبند الجاريين ومنع اعتماد مسار لزيارة أخرى.
        v_photo_path_parts := pg_catalog.string_to_array(v_photo_path, '/');
        IF pg_catalog.array_length(v_photo_path_parts, 1) IS DISTINCT FROM 5
           OR v_photo_path_parts[1] IS DISTINCT FROM 'plans'
           OR v_photo_path_parts[2] IS DISTINCT FROM v_plan_id::TEXT
           OR v_photo_path_parts[3] IS DISTINCT FROM 'items'
           OR v_photo_path_parts[4] IS DISTINCT FROM p_item_id::TEXT
           OR v_photo_path_parts[5] !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|png)$' THEN
          RAISE EXCEPTION 'مسار إثبات الصورة لا يخص خطة وبند الزيارة الحاليين';
        END IF;

        -- لا تُعتمد إجابة الصورة قبل التأكد من رفع الملف فعلياً إلى السلة الخاصة.
        IF NOT EXISTS (
          SELECT 1
          FROM storage.objects so
          WHERE so.bucket_id = 'visit-proofs'
            AND so.name = v_photo_path
        ) THEN
          RAISE EXCEPTION 'ملف إثبات الصورة غير موجود في التخزين';
        END IF;
      END IF;
    END LOOP;

    -- التحقق من الأسئلة الإجبارية والقوالب المطبقة
    SELECT q.question_text INTO v_missing_q_text
    FROM public.visit_checklist_questions q
    JOIN public.visit_checklist_templates t ON t.id = q.template_id
    WHERE t.is_active = true
      AND t.category = 'visit'
      AND (t.purpose_type IS NULL OR t.purpose_type = v_item_purpose_type)
      AND q.is_required = true
      AND (
        t.is_mandatory = true
        OR t.id IN (
          SELECT (r->>'template_id')::UUID FROM jsonb_array_elements(p_responses) r
        )
      )
      AND q.id NOT IN (
        SELECT (r->>'question_id')::UUID FROM jsonb_array_elements(p_responses) r
      )
    LIMIT 1;

    IF v_missing_q_text IS NOT NULL THEN
      RAISE EXCEPTION 'السؤال الإجباري "%" لم يتم الإجابة عليه في الاستبيانات المطبقة', v_missing_q_text;
    END IF;

    -- 6. إنشاء النشاط الميداني الفعلي
    SELECT id INTO v_act_type_id
    FROM public.activity_types
    WHERE code = 'visit_planned' AND is_active = true;

    IF v_act_type_id IS NULL THEN
      RAISE EXCEPTION 'نوع النشاط المجدول (visit_planned) غير معرف أو غير نشط في النظام';
    END IF;

    -- جلب المنطقة الزمنية مع Fallback حقيقي معزز
    v_company_tz := NULL;
    SELECT value INTO v_company_tz FROM public.company_settings WHERE key = 'company.timezone';
    IF v_company_tz IS NULL OR NULLIF(BTRIM(v_company_tz), '') IS NULL THEN
      v_company_tz := 'Africa/Cairo';
    ELSE
      IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = v_company_tz) THEN
        v_company_tz := 'Africa/Cairo';
      END IF;
    END IF;

    -- إدخال النشاط
    INSERT INTO public.activities (
      type_id,
      employee_id,
      customer_id,
      visit_plan_item_id,
      outcome_type,
      outcome_notes,
      gps_lat,
      gps_lng,
      gps_verified,
      distance_meters,
      order_id,
      collection_id,
      start_time,
      end_time,
      activity_date,
      created_by
    ) VALUES (
      v_act_type_id,
      v_target_employee_id,
      v_item_customer_id,
      p_item_id,
      v_outcome_type,
      p_outcome_notes,
      v_start_lat,
      v_start_lng,
      (v_gps_status = 'passed'),
      v_end_distance::integer,
      p_order_id,
      p_collection_id,
      v_server_started_at,
      v_server_time,
      (v_server_time AT TIME ZONE v_company_tz)::date,
      v_actor_id
    )
    RETURNING id INTO v_activity_id;

    -- إدخال إجابات الاستبيان
    FOR i IN 0 .. jsonb_array_length(p_responses) - 1 LOOP
      v_resp_item := p_responses -> i;
      INSERT INTO public.visit_checklist_responses (
        activity_id,
        template_id,
        question_id,
        answer_value,
        answer_json
      ) VALUES (
        v_activity_id,
        (v_resp_item ->> 'template_id')::UUID,
        (v_resp_item ->> 'question_id')::UUID,
        v_resp_item ->> 'answer_value',
        v_resp_item -> 'answer_json'
      );
    END LOOP;

    -- تحديث حالة البند للربط الثنائي الصارم
    UPDATE public.visit_plan_items
    SET status = 'completed',
        server_completed_at = v_server_time,
        client_completed_at = p_client_completed_at,
        device_timezone = p_device_timezone,
        actual_end_time = v_server_time,
        end_lat = p_end_lat,
        end_lng = p_end_lng,
        end_accuracy_m = v_end_accuracy,
        end_distance_m = v_end_distance,
        end_gps_lat = p_end_lat,
        end_gps_lng = p_end_lng,
        gps_validation_status = v_gps_status,
        gps_review_status = v_gps_review_status,
        gps_exception_reason = v_gps_exc_reason,
        gps_exception_requested_by = v_gps_exc_req_by,
        activity_id = v_activity_id,
        start_distance_m = v_start_distance,
        updated_at = v_server_time
    WHERE id = p_item_id;

    -- بناء مخرجات النتيجة
    SELECT jsonb_build_object(
      'item_id', vpi.id,
      'status', vpi.status,
      'activity_id', vpi.activity_id,
      'gps_validation_status', vpi.gps_validation_status,
      'gps_review_status', vpi.gps_review_status,
      'plan_id', vp.id,
      'plan_status', vp.status
    ) INTO v_result_data
    FROM public.visit_plan_items vpi
    JOIN public.visit_plans vp ON vp.id = vpi.plan_id
    WHERE vpi.id = p_item_id;

    -- تحديث حالة الطلب
    UPDATE private.visit_operation_requests
    SET status = 'completed',
        result_json = v_result_data,
        completed_at = clock_timestamp()
    WHERE operation_id = p_operation_id;

    RETURN jsonb_build_object(
      'ok', true,
      'operation_id', p_operation_id,
      'operation', 'complete_visit_item_atomic',
      'replayed', false,
      'data', v_result_data
    );

  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'P0001' THEN
      v_safe_code := 'DOMAIN_VALIDATION_FAILED';
      v_safe_message := 'تعذر إكمال الزيارة لعدم استيفاء الشروط أو فشل استيفاء الاستبيانات الإلزامية';
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
      'operation', 'complete_visit_item_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', v_safe_code,
        'message', v_safe_message
      )
    );
  END;
END;
$$;

REVOKE ALL ON FUNCTION private.complete_visit_item_atomic_impl(UUID, UUID, NUMERIC, NUMERIC, NUMERIC, TIMESTAMPTZ, VARCHAR, VARCHAR, TEXT, JSONB, UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.complete_visit_item_atomic_impl(UUID, UUID, NUMERIC, NUMERIC, NUMERIC, TIMESTAMPTZ, VARCHAR, VARCHAR, TEXT, JSONB, UUID, UUID, TEXT) TO authenticated;

-- Wrapper العامة لـ complete_visit_item_atomic
CREATE OR REPLACE FUNCTION public.complete_visit_item_atomic(
  p_operation_id UUID,
  p_item_id UUID,
  p_end_lat NUMERIC,
  p_end_lng NUMERIC,
  p_end_accuracy_m NUMERIC,
  p_client_completed_at TIMESTAMPTZ,
  p_device_timezone VARCHAR(100),
  p_outcome_type VARCHAR(50),
  p_outcome_notes TEXT,
  p_responses JSONB,
  p_order_id UUID,
  p_collection_id UUID,
  p_gps_exception_reason TEXT
)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
  SELECT private.complete_visit_item_atomic_impl(
    p_operation_id,
    p_item_id,
    p_end_lat,
    p_end_lng,
    p_end_accuracy_m,
    p_client_completed_at,
    p_device_timezone,
    p_outcome_type,
    p_outcome_notes,
    p_responses,
    p_order_id,
    p_collection_id,
    p_gps_exception_reason
  );
$$;

REVOKE ALL ON FUNCTION public.complete_visit_item_atomic(UUID, UUID, NUMERIC, NUMERIC, NUMERIC, TIMESTAMPTZ, VARCHAR, VARCHAR, TEXT, JSONB, UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_visit_item_atomic(UUID, UUID, NUMERIC, NUMERIC, NUMERIC, TIMESTAMPTZ, VARCHAR, VARCHAR, TEXT, JSONB, UUID, UUID, TEXT) TO authenticated;


-- ─── 5. دالة تخطي الزيارة الذرية (skip_visit_item_atomic) ───

CREATE OR REPLACE FUNCTION private.skip_visit_item_atomic_impl(
  p_operation_id UUID,
  p_item_id UUID,
  p_skip_reason TEXT,
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

  v_server_time         TIMESTAMPTZ;
  v_plan_id             UUID;
  v_plan_status         VARCHAR(20);
  v_target_employee_id  UUID;
  v_target_branch_id    UUID;
  v_item_status         VARCHAR(20);
  v_creator_employee_id UUID;
  v_creator_branch_id   UUID;
  v_result_data         JSONB;
  v_safe_message        VARCHAR(250);
  v_safe_code           VARCHAR(50);
BEGIN
  -- 1. التحقق من معرف العملية
  IF p_operation_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', NULL::UUID,
      'operation', 'skip_visit_item_atomic',
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
      'operation', 'skip_visit_item_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'UNAUTHORIZED',
        'message', 'المستخدم غير مصرح له أو الجلسة منتهية'
      )
    );
  END IF;

  -- 3. بناء الحمولة الموحدة وتشفيرها
  v_payload := jsonb_build_object(
    'operation_name', 'skip_visit_item_atomic',
    'item_id', p_item_id,
    'skip_reason', p_skip_reason,
    'client_event_at', p_client_event_at,
    'device_timezone', p_device_timezone
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
    'skip_visit_item_atomic',
    v_hash,
    'pending',
    clock_timestamp()
  ) ON CONFLICT DO NOTHING;

  SELECT status, result_json, actor_id, operation_name, request_hash
  INTO v_req_status, v_req_result, v_req_actor, v_req_op, v_req_hash
  FROM private.visit_operation_requests
  WHERE operation_id = p_operation_id
  FOR UPDATE;

  -- تعارضات idempotency
  IF v_req_actor IS DISTINCT FROM v_actor_id OR
     v_req_op IS DISTINCT FROM 'skip_visit_item_atomic' OR
     v_req_hash IS DISTINCT FROM v_hash THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'skip_visit_item_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'IDEMPOTENCY_KEY_CONFLICT',
        'message', 'تعارض في معرّف العملية (idempotency_key_conflict)'
      )
    );
  END IF;

  IF v_req_status = 'completed' THEN
    RETURN jsonb_build_object(
      'ok', true,
      'operation_id', p_operation_id,
      'operation', 'skip_visit_item_atomic',
      'replayed', true,
      'data', v_req_result
    );
  END IF;

  IF v_req_status = 'failed' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'skip_visit_item_atomic',
      'replayed', true,
      'error', v_req_result -> 'error'
    );
  END IF;

  IF v_req_status = 'processing' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'skip_visit_item_atomic',
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
      started_at = clock_timestamp()
  WHERE operation_id = p_operation_id;

  -- 5. تنفيذ منطق التخطي (التحقق بالداخل)
  BEGIN
    v_server_time := clock_timestamp();

    -- سبب التخطي إلزامي
    IF NULLIF(BTRIM(p_skip_reason), '') IS NULL THEN
      RAISE EXCEPTION 'سبب تخطي الزيارة (skip_reason) مطلوب';
    END IF;
    IF char_length(p_skip_reason) > 500 THEN
      RAISE EXCEPTION 'سبب تخطي الزيارة يجب ألا يتجاوز 500 حرف';
    END IF;

    -- قفل الخطة والبند
    SELECT vp.status, vp.employee_id, vp.organizational_branch_id, vp.id, vpi.status
    INTO v_plan_status, v_target_employee_id, v_target_branch_id, v_plan_id, v_item_status
    FROM public.visit_plans vp
    JOIN public.visit_plan_items vpi ON vpi.plan_id = vp.id
    WHERE vpi.id = p_item_id
    FOR UPDATE;

    IF v_plan_id IS NULL THEN
      RAISE EXCEPTION 'بند خطة الزيارة غير موجود';
    END IF;

    -- التحقق من الصلاحيات والملكية المباشرة والفرع
    IF NOT (SELECT public.check_permission(v_actor_id, 'visit_plans.update_own'::text)) THEN
      RAISE EXCEPTION 'ليس لديك صلاحية تحديث بنود الخطة الخاصة بك';
    END IF;

    -- جلب الموظف النشط
    SELECT id, branch_id INTO v_creator_employee_id, v_creator_branch_id
    FROM public.hr_employees
    WHERE user_id = v_actor_id AND status = 'active';

    IF v_creator_employee_id IS NULL THEN
      RAISE EXCEPTION 'لم يتم العثور على سجل موظف نشط مرتبط بالمستخدم الحالي في النظام';
    END IF;

    IF v_creator_employee_id IS DISTINCT FROM v_target_employee_id THEN
      RAISE EXCEPTION 'لا يمكنك تعديل بند خطة مسندة لموظف آخر';
    END IF;

    IF v_creator_branch_id IS DISTINCT FROM v_target_branch_id THEN
      RAISE EXCEPTION 'فرع الموظف الحالي لا يطابق الفرع التنظيمي للخطة';
    END IF;

    -- التحقق من المنطقة الزمنية للجهاز
    IF p_device_timezone IS NOT NULL THEN
      IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = p_device_timezone) THEN
        RAISE EXCEPTION 'المنطقة الزمنية للجهاز غير صالحة';
      END IF;
    END IF;

    -- تعارضات المزامنة اللوجستية
    IF v_item_status NOT IN ('pending', 'in_progress') THEN
      INSERT INTO private.visit_sync_conflicts (
        operation_id,
        visit_plan_item_id,
        actor_id,
        operation_name,
        conflict_reason_code,
        conflict_payload,
        status
      ) VALUES (
        p_operation_id,
        p_item_id,
        v_actor_id,
        'skip_visit_item_atomic',
        'STATUS_CONFLICT',
        jsonb_build_object(
          'expected_status', 'pending_or_in_progress',
          'actual_status', v_item_status,
          'plan_id', v_plan_id,
          'plan_status', v_plan_status
        ),
        'pending'
      ) ON CONFLICT (operation_id) DO NOTHING;

      UPDATE private.visit_operation_requests
      SET status = 'failed',
          completed_at = clock_timestamp(),
          error_code = 'SYNC_CONFLICT',
          result_json = jsonb_build_object(
            'error', jsonb_build_object(
              'code', 'SYNC_CONFLICT',
              'message', 'تعذر إكمال العملية لوجود تعارض في مزامنة البيانات؛ يرجى تحديث الصفحة والمحاولة مجدداً.'
            )
          ),
          updated_at = clock_timestamp()
      WHERE operation_id = p_operation_id;

      RETURN jsonb_build_object(
        'ok', false,
        'operation_id', p_operation_id,
        'operation', 'skip_visit_item_atomic',
        'replayed', false,
        'error', jsonb_build_object(
          'code', 'SYNC_CONFLICT',
          'message', 'تعذر إكمال العملية لوجود تعارض في مزامنة البيانات؛ يرجى تحديث الصفحة والمحاولة مجدداً.'
        )
      );
    END IF;

    -- التأكد من خلو البند من الأنشطة الفعالة
    IF EXISTS (
      SELECT 1 FROM public.activities
      WHERE visit_plan_item_id = p_item_id AND deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION 'البند مرتبط بنشاط فعال ولا يمكن تخطيه';
    END IF;

    -- التحقق من حالة الخطة
    IF v_plan_status NOT IN ('confirmed', 'in_progress') THEN
      RAISE EXCEPTION 'لا يمكن تخطي بند إلا في خطة مؤكدة أو جارية';
    END IF;

    -- تحديث البند مع الاحتفاظ ببيانات البداية وتثبيت تواريخ النهاية إن كان جاريًا
    UPDATE public.visit_plan_items
    SET status = 'skipped',
        skip_reason = p_skip_reason,
        server_completed_at = CASE WHEN v_item_status = 'in_progress' THEN v_server_time ELSE NULL END,
        client_completed_at = CASE WHEN v_item_status = 'in_progress' THEN p_client_event_at ELSE NULL END,
        device_timezone = CASE WHEN v_item_status = 'in_progress' THEN p_device_timezone ELSE device_timezone END,
        actual_end_time = CASE WHEN v_item_status = 'in_progress' THEN v_server_time ELSE NULL END,
        updated_at = v_server_time
    WHERE id = p_item_id;

    -- بناء مخرجات النتيجة
    SELECT jsonb_build_object(
      'item_id', vpi.id,
      'status', vpi.status,
      'skip_reason', vpi.skip_reason,
      'plan_id', vp.id,
      'plan_status', vp.status
    ) INTO v_result_data
    FROM public.visit_plan_items vpi
    JOIN public.visit_plans vp ON vp.id = vpi.plan_id
    WHERE vpi.id = p_item_id;

    -- تحديث الطلب بالاكتمال
    UPDATE private.visit_operation_requests
    SET status = 'completed',
        result_json = v_result_data,
        completed_at = clock_timestamp()
    WHERE operation_id = p_operation_id;

    RETURN jsonb_build_object(
      'ok', true,
      'operation_id', p_operation_id,
      'operation', 'skip_visit_item_atomic',
      'replayed', false,
      'data', v_result_data
    );

  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'P0001' THEN
      v_safe_code := 'DOMAIN_VALIDATION_FAILED';
      v_safe_message := 'تعذر تخطي الزيارة لعدم استيفاء الشروط أو تجاوز طول البيانات';
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
      'operation', 'skip_visit_item_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', v_safe_code,
        'message', v_safe_message
      )
    );
  END;
END;
$$;

REVOKE ALL ON FUNCTION private.skip_visit_item_atomic_impl(UUID, UUID, TEXT, TIMESTAMPTZ, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.skip_visit_item_atomic_impl(UUID, UUID, TEXT, TIMESTAMPTZ, VARCHAR) TO authenticated;

-- Wrapper العامة لـ skip_visit_item_atomic
CREATE OR REPLACE FUNCTION public.skip_visit_item_atomic(
  p_operation_id UUID,
  p_item_id UUID,
  p_skip_reason TEXT,
  p_client_event_at TIMESTAMPTZ,
  p_device_timezone VARCHAR(100)
)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
  SELECT private.skip_visit_item_atomic_impl(
    p_operation_id,
    p_item_id,
    p_skip_reason,
    p_client_event_at,
    p_device_timezone
  );
$$;

REVOKE ALL ON FUNCTION public.skip_visit_item_atomic(UUID, UUID, TEXT, TIMESTAMPTZ, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.skip_visit_item_atomic(UUID, UUID, TEXT, TIMESTAMPTZ, VARCHAR) TO authenticated;


-- ─── 6. دالة إعادة جدولة الزيارة الذرية (reschedule_visit_item_atomic) ───

CREATE OR REPLACE FUNCTION private.reschedule_visit_item_atomic_impl(
  p_operation_id UUID,
  p_item_id UUID,
  p_target_plan_id UUID,
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

  v_server_time         TIMESTAMPTZ;
  v_source_plan_id      UUID;
  v_item_status         VARCHAR(20);
  v_item_customer_id    UUID;
  v_item_priority       VARCHAR(10);
  v_item_duration       INTEGER;
  v_item_purpose        TEXT;
  v_item_purpose_type   VARCHAR(50);
  v_rescheduled_from_item_id UUID;

  v_src_plan_status     VARCHAR(20);
  v_src_emp_id          UUID;
  v_src_branch_id       UUID;
  v_src_date            DATE;

  v_tgt_plan_status     VARCHAR(20);
  v_tgt_emp_id          UUID;
  v_tgt_branch_id       UUID;
  v_tgt_date            DATE;

  v_creator_employee_id UUID;
  v_creator_branch_id   UUID;
  v_chain_depth         INTEGER;
  v_new_seq             INTEGER;
  v_customer_branch_id  UUID;
  v_tgt_lat             NUMERIC;
  v_tgt_lng             NUMERIC;
  v_exp_loc_id          UUID;
  v_loc_source          VARCHAR(20);
  v_new_item_id         UUID;

  v_result_data         JSONB;
  v_safe_message        VARCHAR(250);
  v_safe_code           VARCHAR(50);
BEGIN
  -- 1. التحقق من معرف العملية
  IF p_operation_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', NULL::UUID,
      'operation', 'reschedule_visit_item_atomic',
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
      'operation', 'reschedule_visit_item_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'UNAUTHORIZED',
        'message', 'المستخدم غير مصرح له أو الجلسة منتهية'
      )
    );
  END IF;

  -- 3. بناء الحمولة وتشفيرها
  v_payload := jsonb_build_object(
    'operation_name', 'reschedule_visit_item_atomic',
    'item_id', p_item_id,
    'target_plan_id', p_target_plan_id,
    'reschedule_reason', p_reschedule_reason,
    'planned_time', p_planned_time,
    'client_event_at', p_client_event_at,
    'device_timezone', p_device_timezone
  );
  v_hash := encode(extensions.digest(v_payload::text, 'sha256'), 'hex');

  -- 4. محرك منع التكرار
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
    'reschedule_visit_item_atomic',
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
     v_req_op IS DISTINCT FROM 'reschedule_visit_item_atomic' OR
     v_req_hash IS DISTINCT FROM v_hash THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'reschedule_visit_item_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', 'IDEMPOTENCY_KEY_CONFLICT',
        'message', 'تعارض في معرّف العملية (idempotency_key_conflict)'
      )
    );
  END IF;

  IF v_req_status = 'completed' THEN
    RETURN jsonb_build_object(
      'ok', true,
      'operation_id', p_operation_id,
      'operation', 'reschedule_visit_item_atomic',
      'replayed', true,
      'data', v_req_result
    );
  END IF;

  IF v_req_status = 'failed' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'reschedule_visit_item_atomic',
      'replayed', true,
      'error', v_req_result -> 'error'
    );
  END IF;

  IF v_req_status = 'processing' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'reschedule_visit_item_atomic',
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
      started_at = clock_timestamp()
  WHERE operation_id = p_operation_id;

  -- 5. تنفيذ منطق إعادة الجدولة (جميع الفحوصات الجنائية واللوجستية بالداخل)
  BEGIN
    v_server_time := clock_timestamp();

    -- سبب إعادة الجدولة إلزامي وطوله
    IF NULLIF(BTRIM(p_reschedule_reason), '') IS NULL THEN
      RAISE EXCEPTION 'سبب إعادة الجدولة مطلوب';
    END IF;
    IF char_length(p_reschedule_reason) > 500 THEN
      RAISE EXCEPTION 'سبب إعادة الجدولة يجب ألا يتجاوز 500 حرف';
    END IF;

    -- جلب معرف الخطة المصدر للبدء بالقفل بترتيب UUID
    SELECT plan_id INTO v_source_plan_id
    FROM public.visit_plan_items
    WHERE id = p_item_id;

    IF v_source_plan_id IS NULL THEN
      RAISE EXCEPTION 'بند خطة الزيارة المصدر غير موجود';
    END IF;

    IF v_source_plan_id = p_target_plan_id THEN
      RAISE EXCEPTION 'لا يمكن إعادة جدولة البند لنفس خطته الحالية';
    END IF;

    -- قفل الخطتين بترتيب UUID ثابت لتفادي deadlock
    IF v_source_plan_id < p_target_plan_id THEN
      SELECT status, employee_id, organizational_branch_id, plan_date
      INTO v_src_plan_status, v_src_emp_id, v_src_branch_id, v_src_date
      FROM public.visit_plans WHERE id = v_source_plan_id FOR UPDATE;

      SELECT status, employee_id, organizational_branch_id, plan_date
      INTO v_tgt_plan_status, v_tgt_emp_id, v_tgt_branch_id, v_tgt_date
      FROM public.visit_plans WHERE id = p_target_plan_id FOR UPDATE;
    ELSE
      SELECT status, employee_id, organizational_branch_id, plan_date
      INTO v_tgt_plan_status, v_tgt_emp_id, v_tgt_branch_id, v_tgt_date
      FROM public.visit_plans WHERE id = p_target_plan_id FOR UPDATE;

      SELECT status, employee_id, organizational_branch_id, plan_date
      INTO v_src_plan_status, v_src_emp_id, v_src_branch_id, v_src_date
      FROM public.visit_plans WHERE id = v_source_plan_id FOR UPDATE;
    END IF;

    -- تحقق صريح من وجود الخطة الهدف
    IF v_tgt_plan_status IS NULL THEN
      RAISE EXCEPTION 'الخطة الهدف غير موجودة';
    END IF;

    -- قفل وقراءة البند المصدر صراحة FOR UPDATE
    SELECT status, customer_id, priority, estimated_duration_min, purpose, purpose_type, rescheduled_from_item_id, customer_branch_id
    INTO v_item_status, v_item_customer_id, v_item_priority, v_item_duration, v_item_purpose, v_item_purpose_type, v_rescheduled_from_item_id, v_customer_branch_id
    FROM public.visit_plan_items
    WHERE id = p_item_id
    FOR UPDATE;

    -- التحقق من الصلاحيات والملكية المباشرة والفرع
    IF NOT (SELECT public.check_permission(v_actor_id, 'visit_plans.update_own'::text)) THEN
      RAISE EXCEPTION 'ليس لديك صلاحية تحديث بنود الخطة الخاصة بك';
    END IF;

    -- جلب الموظف النشط فقط
    SELECT id, branch_id INTO v_creator_employee_id, v_creator_branch_id
    FROM public.hr_employees
    WHERE user_id = v_actor_id AND status = 'active';

    IF v_creator_employee_id IS NULL THEN
      RAISE EXCEPTION 'لم يتم العثور على سجل موظف نشط مرتبط بالمستخدم الحالي في النظام';
    END IF;

    IF v_creator_employee_id IS DISTINCT FROM v_src_emp_id THEN
      RAISE EXCEPTION 'لا يمكنك تعديل بند خطة مسندة لموظف آخر';
    END IF;

    IF v_creator_branch_id IS DISTINCT FROM v_src_branch_id OR v_creator_branch_id IS DISTINCT FROM v_tgt_branch_id THEN
      RAISE EXCEPTION 'فرع الموظف الحالي لا يطابق الفرع التنظيمي لأحد الخطط';
    END IF;

    -- التحقق من المنطقة الزمنية
    IF p_device_timezone IS NOT NULL THEN
      IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = p_device_timezone) THEN
        RAISE EXCEPTION 'المنطقة الزمنية للجهاز غير صالحة';
      END IF;
    END IF;

    -- تعارضات المزامنة اللوجستية
    IF v_item_status NOT IN ('pending', 'in_progress') THEN
      INSERT INTO private.visit_sync_conflicts (
        operation_id,
        visit_plan_item_id,
        actor_id,
        operation_name,
        conflict_reason_code,
        conflict_payload,
        status
      ) VALUES (
        p_operation_id,
        p_item_id,
        v_actor_id,
        'reschedule_visit_item_atomic',
        'STATUS_CONFLICT',
        jsonb_build_object(
          'expected_status', 'pending_or_in_progress',
          'actual_status', v_item_status,
          'plan_id', v_source_plan_id
        ),
        'pending'
      ) ON CONFLICT (operation_id) DO NOTHING;

      UPDATE private.visit_operation_requests
      SET status = 'failed',
          completed_at = clock_timestamp(),
          error_code = 'SYNC_CONFLICT',
          result_json = jsonb_build_object(
            'error', jsonb_build_object(
              'code', 'SYNC_CONFLICT',
              'message', 'تعذر إكمال العملية لوجود تعارض في مزامنة البيانات؛ يرجى تحديث الصفحة والمحاولة مجدداً.'
            )
          ),
          updated_at = clock_timestamp()
      WHERE operation_id = p_operation_id;

      RETURN jsonb_build_object(
        'ok', false,
        'operation_id', p_operation_id,
        'operation', 'reschedule_visit_item_atomic',
        'replayed', false,
        'error', jsonb_build_object(
          'code', 'SYNC_CONFLICT',
          'message', 'تعذر إكمال العملية لوجود تعارض في مزامنة البيانات؛ يرجى تحديث الصفحة والمحاولة مجدداً.'
        )
      );
    END IF;

    -- التحقق من عدم وجود نشاط فعال للبند
    IF EXISTS (
      SELECT 1 FROM public.activities
      WHERE visit_plan_item_id = p_item_id AND deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION 'لا يمكن إعادة جدولة بند مرتبط بنشاط فعال';
    END IF;

    -- فحص قيود المخطط والهدف والموظف والتاريخ
    IF v_src_plan_status NOT IN ('confirmed', 'in_progress') THEN
      RAISE EXCEPTION 'لا يمكن إعادة جدولة البند إلا من خطة مؤكدة أو جارية';
    END IF;
    IF v_tgt_emp_id IS DISTINCT FROM v_src_emp_id OR v_tgt_branch_id IS DISTINCT FROM v_src_branch_id THEN
      RAISE EXCEPTION 'يجب أن تكون الخطة المستهدفة لنفس الموظف ونفس الفرع التنظيمي';
    END IF;
    IF v_tgt_date <= v_src_date THEN
      RAISE EXCEPTION 'تاريخ الخطة الهدف يجب أن يكون أكبر من تاريخ الخطة المصدر لإعادة الجدولة';
    END IF;
    IF v_tgt_plan_status NOT IN ('draft', 'confirmed') THEN
      RAISE EXCEPTION 'يجب أن تكون الخطة الهدف في حالة مسودة أو مؤكدة فقط';
    END IF;

    -- التحقق من الفرع المخصص للعميل
    IF v_customer_branch_id IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.customer_branches
        WHERE id = v_customer_branch_id AND customer_id = v_item_customer_id
      ) THEN
        RAISE EXCEPTION 'فرع العميل المحدد لا ينتمي لنفس عميل بند الزيارة';
      END IF;
    END IF;

    -- فحص وتفادي تكرار إدخال نفس العميل في نفس الخطة الهدف
    IF EXISTS (
      SELECT 1 FROM public.visit_plan_items
      WHERE plan_id = p_target_plan_id AND customer_id = v_item_customer_id
    ) THEN
      v_safe_code := 'TARGET_DUPLICATE_CUSTOMER';
      v_safe_message := 'العميل مضاف مسبقاً في الخطة المستهدفة';

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
        'operation', 'reschedule_visit_item_atomic',
        'replayed', false,
        'error', jsonb_build_object(
          'code', 'TARGET_DUPLICATE_CUSTOMER',
          'message', 'العميل مضاف مسبقاً في الخطة المستهدفة'
        )
      );
    END IF;

    -- التحقق من عمق سلسلة إعادة الجدولة لمنع الدورات (حد أقصى 10)
    WITH RECURSIVE reschedule_chain AS (
      SELECT rescheduled_from_item_id, 1 AS depth
      FROM public.visit_plan_items
      WHERE id = p_item_id

      UNION ALL

      SELECT vpi.rescheduled_from_item_id, rc.depth + 1
      FROM public.visit_plan_items vpi
      JOIN reschedule_chain rc ON rc.rescheduled_from_item_id = vpi.id
      WHERE vpi.rescheduled_from_item_id IS NOT NULL
        AND rc.depth < 12
    )
    SELECT MAX(depth) INTO v_chain_depth
    FROM reschedule_chain;

    IF COALESCE(v_chain_depth, 0) >= 10 THEN
      RAISE EXCEPTION 'تجاوزت سلسلة إعادة الجدولة الحد الأقصى المسموح به (10 مرات)';
    END IF;

    -- قفل بنود الخطة الهدف قبل حساب MAX(sequence) لتفادي التداخل في الترتيب
    PERFORM 1 FROM public.visit_plan_items
    WHERE plan_id = p_target_plan_id
    FOR UPDATE;

    SELECT COALESCE(MAX(sequence), 0) + 1 INTO v_new_seq
    FROM public.visit_plan_items
    WHERE plan_id = p_target_plan_id;

    -- أخذ لقطة إحداثيات العميل خادمياً بالكامل
    v_tgt_lat := NULL;
    v_tgt_lng := NULL;
    v_exp_loc_id := NULL;
    v_loc_source := NULL;

    -- 1. المحاولة من فرع العميل المحدد بالبند
    IF v_customer_branch_id IS NOT NULL THEN
      SELECT latitude, longitude, id INTO v_tgt_lat, v_tgt_lng, v_exp_loc_id
      FROM public.customer_branches
      WHERE id = v_customer_branch_id;

      IF v_tgt_lat IS NOT NULL AND v_tgt_lng IS NOT NULL THEN
        v_loc_source := 'customer_branch';
      END IF;
    END IF;

    -- 2. المحاولة من الفرع الرئيسي للعميل (is_primary = true)
    IF v_tgt_lat IS NULL OR v_tgt_lng IS NULL THEN
      SELECT latitude, longitude, id INTO v_tgt_lat, v_tgt_lng, v_exp_loc_id
      FROM public.customer_branches
      WHERE customer_id = v_item_customer_id
        AND is_primary = true
      LIMIT 1;

      IF v_tgt_lat IS NOT NULL AND v_tgt_lng IS NOT NULL THEN
        v_loc_source := 'customer_branch';
        v_customer_branch_id := v_exp_loc_id;
      ELSE
        v_tgt_lat := NULL;
        v_tgt_lng := NULL;
      END IF;
    END IF;

    -- 3. المحاولة من إحداثيات العميل العامة
    IF v_tgt_lat IS NULL OR v_tgt_lng IS NULL THEN
      SELECT latitude, longitude INTO v_tgt_lat, v_tgt_lng
      FROM public.customers
      WHERE id = v_item_customer_id;

      IF v_tgt_lat IS NOT NULL AND v_tgt_lng IS NOT NULL THEN
        v_loc_source := 'customer';
        v_exp_loc_id := v_item_customer_id;
        v_customer_branch_id := NULL;
      ELSE
        v_tgt_lat := NULL;
        v_tgt_lng := NULL;
        v_exp_loc_id := NULL;
        v_loc_source := NULL;
        v_customer_branch_id := NULL;
      END IF;
    END IF;

    -- إنشاء البند البديل في الخطة الهدف
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
      rescheduled_from_item_id,
      expected_location_source,
      expected_location_id,
      expected_lat,
      expected_lng
    ) VALUES (
      p_target_plan_id,
      v_item_customer_id,
      v_customer_branch_id,
      v_new_seq,
      p_planned_time,
      v_item_duration,
      v_item_priority,
      v_item_purpose,
      v_item_purpose_type,
      'pending',
      p_item_id,
      v_loc_source,
      v_exp_loc_id,
      v_tgt_lat,
      v_tgt_lng
    )
    RETURNING id INTO v_new_item_id;

    -- تحديث البند المصدر مع تدوين أوقات الإغلاق وجهاز المندوب
    UPDATE public.visit_plan_items
    SET status = 'rescheduled',
        replacement_item_id = v_new_item_id,
        reschedule_to = v_tgt_date,
        reschedule_reason = p_reschedule_reason,
        server_completed_at = v_server_time,
        client_completed_at = p_client_event_at,
        device_timezone = p_device_timezone,
        actual_end_time = v_server_time,
        updated_at = v_server_time
    WHERE id = p_item_id;

    -- بناء مخرجات النتيجة
    SELECT jsonb_build_object(
      'source_item_id', p_item_id,
      'source_status', 'rescheduled',
      'new_item_id', v_new_item_id,
      'new_status', 'pending',
      'source_plan_id', v_source_plan_id,
      'target_plan_id', p_target_plan_id
    ) INTO v_result_data;

    -- تحديث الطلب
    UPDATE private.visit_operation_requests
    SET status = 'completed',
        result_json = v_result_data,
        completed_at = clock_timestamp()
    WHERE operation_id = p_operation_id;

    RETURN jsonb_build_object(
      'ok', true,
      'operation_id', p_operation_id,
      'operation', 'reschedule_visit_item_atomic',
      'replayed', false,
      'data', v_result_data
    );

  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'P0001' THEN
      v_safe_code := 'DOMAIN_VALIDATION_FAILED';
      v_safe_message := 'تعذر إعادة جدولة الزيارة لعدم استيفاء شروطها اللوجستية أو الجغرافية';
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
      'operation', 'reschedule_visit_item_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', v_safe_code,
        'message', v_safe_message
      )
    );
  END;
END;
$$;

REVOKE ALL ON FUNCTION private.reschedule_visit_item_atomic_impl(UUID, UUID, UUID, TEXT, TIME, TIMESTAMPTZ, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.reschedule_visit_item_atomic_impl(UUID, UUID, UUID, TEXT, TIME, TIMESTAMPTZ, VARCHAR) TO authenticated;

-- Wrapper العامة لـ reschedule_visit_item_atomic
CREATE OR REPLACE FUNCTION public.reschedule_visit_item_atomic(
  p_operation_id UUID,
  p_item_id UUID,
  p_target_plan_id UUID,
  p_reschedule_reason TEXT,
  p_planned_time TIME,
  p_client_event_at TIMESTAMPTZ,
  p_device_timezone VARCHAR(100)
)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
  SELECT private.reschedule_visit_item_atomic_impl(
    p_operation_id,
    p_item_id,
    p_target_plan_id,
    p_reschedule_reason,
    p_planned_time,
    p_client_event_at,
    p_device_timezone
  );
$$;

REVOKE ALL ON FUNCTION public.reschedule_visit_item_atomic(UUID, UUID, UUID, TEXT, TIME, TIMESTAMPTZ, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reschedule_visit_item_atomic(UUID, UUID, UUID, TEXT, TIME, TIMESTAMPTZ, VARCHAR) TO authenticated;

COMMIT;
