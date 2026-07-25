-- =============================================================================
-- EDARA v2 — visits_draft_item_atomic_rpcs_contract.sql
-- عقد تحقق لفحص الامتثال المعماري والأمني لعمليات إضافة وحذف بنود الخطة ذرياً
-- =============================================================================

DO $$
DECLARE
  v_error_count INTEGER := 0;
  v_error_details TEXT := '';

  PROC RECORD;
  PRIV RECORD;
  v_args TEXT;
  v_overload_count INTEGER;
BEGIN
  ------------------------------------------------------------------------------
  -- 1. الفحص العام لوجود الدوال وصلاحياتها وتطابق التوقيع الكامل ومحاربة الـ overload
  ------------------------------------------------------------------------------

  -- أ) دالة إضافة بند: public wrapper
  SELECT count(*) INTO v_overload_count
  FROM pg_proc JOIN pg_namespace n ON pg_proc.pronamespace = n.oid
  WHERE proname = 'add_visit_plan_item_atomic' AND n.nspname = 'public';

  IF v_overload_count > 1 THEN
    v_error_count := v_error_count + 1;
    v_error_details := v_error_details || E'\n- وجود overload زائد لـ public.add_visit_plan_item_atomic.';
  END IF;

  SELECT pg_proc.* INTO PROC
  FROM pg_proc JOIN pg_namespace n ON pg_proc.pronamespace = n.oid
  WHERE proname = 'add_visit_plan_item_atomic' AND n.nspname = 'public';

  IF NOT FOUND THEN
    v_error_count := v_error_count + 1;
    v_error_details := v_error_details || E'\n- غياب دالة public.add_visit_plan_item_atomic.';
  ELSE
    v_args := pg_get_function_identity_arguments(PROC.oid);
    IF v_args NOT ILIKE '%p_operation_id uuid, p_plan_id uuid, p_customer_id uuid, p_customer_branch_id uuid, p_purpose text, p_purpose_type character varying, p_priority character varying, p_planned_time time without time zone, p_estimated_duration_min integer, p_client_event_at timestamp with time zone, p_device_timezone character varying%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- عدم تطابق التوقيع الكامل لدالة public.add_visit_plan_item_atomic.';
    END IF;
    IF PROC.prosecdef THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- دالة public.add_visit_plan_item_atomic يجب أن تكون SECURITY INVOKER.';
    END IF;
  END IF;

  -- ب) دالة إضافة بند: private impl
  SELECT count(*) INTO v_overload_count
  FROM pg_proc JOIN pg_namespace n ON pg_proc.pronamespace = n.oid
  WHERE proname = 'add_visit_plan_item_atomic_impl' AND n.nspname = 'private';

  IF v_overload_count > 1 THEN
    v_error_count := v_error_count + 1;
    v_error_details := v_error_details || E'\n- وجود overload زائد لـ private.add_visit_plan_item_atomic_impl.';
  END IF;

  SELECT pg_proc.* INTO PROC
  FROM pg_proc JOIN pg_namespace n ON pg_proc.pronamespace = n.oid
  WHERE proname = 'add_visit_plan_item_atomic_impl' AND n.nspname = 'private';

  IF NOT FOUND THEN
    v_error_count := v_error_count + 1;
    v_error_details := v_error_details || E'\n- غياب دالة private.add_visit_plan_item_atomic_impl.';
  ELSE
    v_args := pg_get_function_identity_arguments(PROC.oid);
    IF v_args NOT ILIKE '%p_operation_id uuid, p_plan_id uuid, p_customer_id uuid, p_customer_branch_id uuid, p_purpose text, p_purpose_type character varying, p_priority character varying, p_planned_time time without time zone, p_estimated_duration_min integer, p_client_event_at timestamp with time zone, p_device_timezone character varying%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- عدم تطابق التوقيع الكامل لدالة private.add_visit_plan_item_atomic_impl.';
    END IF;
    IF NOT PROC.prosecdef THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- دالة add_visit_plan_item_atomic_impl تفتقد لـ SECURITY DEFINER.';
    END IF;
    IF PROC.proconfig IS NULL OR NOT ('search_path=pg_catalog' = ANY(PROC.proconfig)) THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- دالة add_visit_plan_item_atomic_impl تفتقد لـ search_path الآمن.';
    END IF;
  END IF;

  -- ج) دالة حذف بند: public wrapper
  SELECT count(*) INTO v_overload_count
  FROM pg_proc JOIN pg_namespace n ON pg_proc.pronamespace = n.oid
  WHERE proname = 'delete_visit_plan_item_atomic' AND n.nspname = 'public';

  IF v_overload_count > 1 THEN
    v_error_count := v_error_count + 1;
    v_error_details := v_error_details || E'\n- وجود overload زائد لـ public.delete_visit_plan_item_atomic.';
  END IF;

  SELECT pg_proc.* INTO PROC
  FROM pg_proc JOIN pg_namespace n ON pg_proc.pronamespace = n.oid
  WHERE proname = 'delete_visit_plan_item_atomic' AND n.nspname = 'public';

  IF NOT FOUND THEN
    v_error_count := v_error_count + 1;
    v_error_details := v_error_details || E'\n- غياب دالة public.delete_visit_plan_item_atomic.';
  ELSE
    v_args := pg_get_function_identity_arguments(PROC.oid);
    IF v_args NOT ILIKE '%p_operation_id uuid, p_item_id uuid, p_client_event_at timestamp with time zone, p_device_timezone character varying%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- عدم تطابق التوقيع الكامل لدالة public.delete_visit_plan_item_atomic.';
    END IF;
    IF PROC.prosecdef THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- دالة public.delete_visit_plan_item_atomic يجب أن تكون SECURITY INVOKER.';
    END IF;
  END IF;

  -- د) دالة حذف بند: private impl
  SELECT count(*) INTO v_overload_count
  FROM pg_proc JOIN pg_namespace n ON pg_proc.pronamespace = n.oid
  WHERE proname = 'delete_visit_plan_item_atomic_impl' AND n.nspname = 'private';

  IF v_overload_count > 1 THEN
    v_error_count := v_error_count + 1;
    v_error_details := v_error_details || E'\n- وجود overload زائد لـ private.delete_visit_plan_item_atomic_impl.';
  END IF;

  SELECT pg_proc.* INTO PROC
  FROM pg_proc JOIN pg_namespace n ON pg_proc.pronamespace = n.oid
  WHERE proname = 'delete_visit_plan_item_atomic_impl' AND n.nspname = 'private';

  IF NOT FOUND THEN
    v_error_count := v_error_count + 1;
    v_error_details := v_error_details || E'\n- غياب دالة private.delete_visit_plan_item_atomic_impl.';
  ELSE
    v_args := pg_get_function_identity_arguments(PROC.oid);
    IF v_args NOT ILIKE '%p_operation_id uuid, p_item_id uuid, p_client_event_at timestamp with time zone, p_device_timezone character varying%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- عدم تطابق التوقيع الكامل لدالة private.delete_visit_plan_item_atomic_impl.';
    END IF;
    IF NOT PROC.prosecdef THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- دالة delete_visit_plan_item_atomic_impl تفتقد لـ SECURITY DEFINER.';
    END IF;
    IF PROC.proconfig IS NULL OR NOT ('search_path=pg_catalog' = ANY(PROC.proconfig)) THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- دالة delete_visit_plan_item_atomic_impl تفتقد لـ search_path الآمن.';
    END IF;
  END IF;

  ------------------------------------------------------------------------------
  -- 2. فحص تسريب الصلاحيات (EXECUTE لـ PUBLIC أو anon)
  ------------------------------------------------------------------------------
  FOR PRIV IN
    SELECT routine_name, grantee
    FROM information_schema.routine_privileges
    WHERE routine_name IN ('add_visit_plan_item_atomic_impl', 'delete_visit_plan_item_atomic_impl', 'add_visit_plan_item_atomic', 'delete_visit_plan_item_atomic')
      AND privilege_type = 'EXECUTE'
      AND grantee IN ('PUBLIC', 'anon')
  LOOP
    v_error_count := v_error_count + 1;
    v_error_details := v_error_details || E'\n- تسريب صلاحية EXECUTE للدالة ' || PRIV.routine_name || ' للمستخدم ' || PRIV.grantee;
  END LOOP;

  -- التأكد من منح EXECUTE لـ authenticated
  FOR PRIV IN
    SELECT unnest(ARRAY['add_visit_plan_item_atomic', 'delete_visit_plan_item_atomic', 'add_visit_plan_item_atomic_impl', 'delete_visit_plan_item_atomic_impl']) AS func_name
    EXCEPT
    SELECT routine_name
    FROM information_schema.routine_privileges
    WHERE privilege_type = 'EXECUTE' AND grantee = 'authenticated'
  LOOP
    v_error_count := v_error_count + 1;
    v_error_details := v_error_details || E'\n- غياب صلاحية EXECUTE لـ authenticated للدالة ' || PRIV.func_name;
  END LOOP;

  ------------------------------------------------------------------------------
  -- 3. الفحص النصي المعماري الدقيق لـ add_visit_plan_item_atomic_impl
  ------------------------------------------------------------------------------
  SELECT pg_proc.* INTO PROC
  FROM pg_proc JOIN pg_namespace n ON pg_proc.pronamespace = n.oid
  WHERE proname = 'add_visit_plan_item_atomic_impl' AND n.nspname = 'private';

  IF PROC.prosrc IS NOT NULL THEN
    -- أ) كشف عودة صيغة ELSIF في نطاق الصلاحيات
    IF PROC.prosrc ILIKE '%ELSIF (SELECT public.check_permission(v_actor_id, ''visit_plans.read_team''))%'
       OR PROC.prosrc ILIKE '%ELSIF v_creator_employee_id = v_plan_employee_id%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق: عودة صيغة ELSIF التسلسلية المحظورة في نطاق الصلاحيات في add_visit_plan_item_atomic_impl.';
    END IF;

    -- ب) كشف ظهور medium
    IF PROC.prosrc ILIKE '%medium%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق: ظهور قيمة الأولوية medium المحظورة في add_visit_plan_item_atomic_impl.';
    END IF;

    -- ج) كشف غياب قائمة priority وقائمة purpose_type وحدود المدة
    IF PROC.prosrc NOT ILIKE '%high%' OR PROC.prosrc NOT ILIKE '%normal%' OR PROC.prosrc NOT ILIKE '%low%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق: غياب الفحص الصريح لقائمة قيم priority المسموحة (high, normal, low).';
    END IF;

    IF PROC.prosrc NOT ILIKE '%sales%' OR PROC.prosrc NOT ILIKE '%collection%' OR PROC.prosrc NOT ILIKE '%activation%' OR PROC.prosrc NOT ILIKE '%promotion%' OR PROC.prosrc NOT ILIKE '%followup%' OR PROC.prosrc NOT ILIKE '%service%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق: غياب الفحص الصريح لقائمة قيم purpose_type المسموحة.';
    END IF;

    IF PROC.prosrc NOT ILIKE '%480%' OR (PROC.prosrc NOT ILIKE '%< 5%' AND PROC.prosrc NOT ILIKE '%BETWEEN 5 AND 480%') THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق: غياب فحص حدود مدة البند (بين 5 و 480 دقيقة).';
    END IF;

    -- د) كشف غياب visit_plans.create صراحة
    IF PROC.prosrc NOT ILIKE '%visit_plans.create%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق: غياب الاشتراك الصريح لصلاحية visit_plans.create في الإضافة.';
    END IF;

    -- هـ) كشف قبول update أو update_own كبديل غير مصرح به
    IF PROC.prosrc ILIKE '%visit_plans.update_own%' OR PROC.prosrc ILIKE '%visit_plans.update''%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق: قبول غير مصرح به لصلاحية update أو update_own كبديل لصلاحية create في الإضافة.';
    END IF;

    -- و) كشف غياب تحقق نطاق الإحداثيات الجغرافية
    IF PROC.prosrc NOT ILIKE '%BETWEEN -90 AND 90%' OR PROC.prosrc NOT ILIKE '%BETWEEN -180 AND 180%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق: غياب فحص نطاق الإحداثيات الجغرافية الجائزة (-90..90 و -180..180).';
    END IF;
  END IF;

  ------------------------------------------------------------------------------
  -- 4. الفحص النصي المعماري الدقيق لـ delete_visit_plan_item_atomic_impl
  ------------------------------------------------------------------------------
  SELECT pg_proc.* INTO PROC
  FROM pg_proc JOIN pg_namespace n ON pg_proc.pronamespace = n.oid
  WHERE proname = 'delete_visit_plan_item_atomic_impl' AND n.nspname = 'private';

  IF PROC.prosrc IS NOT NULL THEN
    -- أ) كشف عودة صيغة ELSIF في نطاق الصلاحيات
    IF PROC.prosrc ILIKE '%ELSIF (SELECT public.check_permission(v_actor_id, ''visit_plans.read_team''))%'
       OR PROC.prosrc ILIKE '%ELSIF v_creator_employee_id = v_plan_employee_id%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق: عودة صيغة ELSIF التسلسلية المحظورة في نطاق الصلاحيات في delete_visit_plan_item_atomic_impl.';
    END IF;

    -- ب) كشف غياب NOT FOUND في الحذف
    IF PROC.prosrc NOT ILIKE '%NOT FOUND%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق: غياب فحص NOT FOUND عند البحث عن بند الزيارات المراد حذفه.';
    END IF;

    -- ج) كشف غياب visit_plans.create صراحة
    IF PROC.prosrc NOT ILIKE '%visit_plans.create%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق: غياب الاشتراط الصريح لصلاحية visit_plans.create في الحذف.';
    END IF;

    -- د) كشف قبول update أو update_own كبديل غير مصرح به
    IF PROC.prosrc ILIKE '%visit_plans.update_own%' OR PROC.prosrc ILIKE '%visit_plans.update''%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق: قبول غير مصرح به لصلاحية update أو update_own كبديل لصلاحية create في الحذف.';
    END IF;
  END IF;

  ------------------------------------------------------------------------------
  -- النتيجة
  ------------------------------------------------------------------------------
  IF v_error_count > 0 THEN
    RAISE EXCEPTION 'فشل عقد التحقق الساكن لإضافة وحذف بنود الخطة ذرياً! الأخطاء: %', v_error_details;
  ELSE
    RAISE NOTICE 'اجتازت دوال إضافة وحذف بنود الخطة الذرية عقد التحقق المعماري والأمني بنجاح تام.';
  END IF;
END;
$$;


-- تأهيل pgcrypto حسب المخطط الفعلي
WITH expected(fn_name) AS (
  VALUES
    ('add_visit_plan_item_atomic_impl'),
    ('delete_visit_plan_item_atomic_impl')
)
SELECT
  'DIGEST_SCHEMA_INVALID' AS audit_rule,
  e.fn_name
FROM expected e
LEFT JOIN pg_catalog.pg_namespace n ON n.nspname = 'private'
LEFT JOIN pg_catalog.pg_proc p ON p.pronamespace = n.oid AND p.proname = e.fn_name
WHERE p.oid IS NULL
   OR p.prosrc NOT ILIKE '%extensions.digest%'
   OR p.prosrc ILIKE '%public.digest%';
