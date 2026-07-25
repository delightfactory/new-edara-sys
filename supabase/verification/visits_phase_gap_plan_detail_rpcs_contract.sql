-- =============================================================================
-- EDARA v2 — visits_phase_gap_plan_detail_rpcs_contract.sql
-- عقد تحقق لفحص الامتثال المعماري والأمني لعمليات إعادة الجدولة وإنهاء اليومية
-- =============================================================================

DO $$
DECLARE
  v_error_count INTEGER := 0;
  v_error_details TEXT := '';

  PROC RECORD;
  PRIV RECORD;
BEGIN
  ------------------------------------------------------------------------------
  -- 1. الفحص العام لوجود الدوال وصلاحياتها وتطابق التوقيع
  ------------------------------------------------------------------------------

  -- أ) دالة إعادة الجدولة: public wrapper
  SELECT * INTO PROC FROM pg_proc JOIN pg_namespace n ON pg_proc.pronamespace = n.oid
  WHERE proname = 'reschedule_visit_item_to_date_atomic' AND n.nspname = 'public';

  IF NOT FOUND THEN
    v_error_count := v_error_count + 1;
    v_error_details := v_error_details || E'\n- غياب دالة public.reschedule_visit_item_to_date_atomic.';
  ELSIF pg_get_function_identity_arguments(PROC.oid) NOT ILIKE '%p_operation_id uuid, p_item_id uuid, p_target_date date, p_reschedule_reason text, p_planned_time time without time zone, p_client_event_at timestamp with time zone, p_device_timezone character varying%' THEN
    v_error_count := v_error_count + 1;
    v_error_details := v_error_details || E'\n- اختلاف توقيع دالة public.reschedule_visit_item_to_date_atomic.';
  END IF;

  -- ب) دالة إعادة الجدولة: private impl
  SELECT * INTO PROC FROM pg_proc JOIN pg_namespace n ON pg_proc.pronamespace = n.oid
  WHERE proname = 'reschedule_visit_item_to_date_atomic_impl' AND n.nspname = 'private';

  IF NOT FOUND THEN
    v_error_count := v_error_count + 1;
    v_error_details := v_error_details || E'\n- غياب دالة private.reschedule_visit_item_to_date_atomic_impl.';
  ELSE
    IF NOT PROC.prosecdef THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- دالة reschedule_visit_item_to_date_atomic_impl تفتقد لـ SECURITY DEFINER.';
    END IF;
    IF PROC.proconfig IS NULL OR NOT ('search_path=pg_catalog' = ANY(PROC.proconfig)) THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- دالة reschedule_visit_item_to_date_atomic_impl تفتقد لـ search_path الآمن.';
    END IF;
  END IF;

  -- ج) دالة إنهاء اليومية: public wrapper
  SELECT * INTO PROC FROM pg_proc JOIN pg_namespace n ON pg_proc.pronamespace = n.oid
  WHERE proname = 'close_visit_day_missed_atomic' AND n.nspname = 'public';

  IF NOT FOUND THEN
    v_error_count := v_error_count + 1;
    v_error_details := v_error_details || E'\n- غياب دالة public.close_visit_day_missed_atomic.';
  ELSIF pg_get_function_identity_arguments(PROC.oid) NOT ILIKE '%p_operation_id uuid, p_plan_id uuid, p_close_reason text, p_client_event_at timestamp with time zone, p_device_timezone character varying%' THEN
    v_error_count := v_error_count + 1;
    v_error_details := v_error_details || E'\n- اختلاف توقيع دالة public.close_visit_day_missed_atomic.';
  END IF;

  -- د) دالة إنهاء اليومية: private impl
  SELECT * INTO PROC FROM pg_proc JOIN pg_namespace n ON pg_proc.pronamespace = n.oid
  WHERE proname = 'close_visit_day_missed_atomic_impl' AND n.nspname = 'private';

  IF NOT FOUND THEN
    v_error_count := v_error_count + 1;
    v_error_details := v_error_details || E'\n- غياب دالة private.close_visit_day_missed_atomic_impl.';
  ELSE
    IF NOT PROC.prosecdef THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- دالة close_visit_day_missed_atomic_impl تفتقد لـ SECURITY DEFINER.';
    END IF;
    IF PROC.proconfig IS NULL OR NOT ('search_path=pg_catalog' = ANY(PROC.proconfig)) THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- دالة close_visit_day_missed_atomic_impl تفتقد لـ search_path الآمن.';
    END IF;
  END IF;

  ------------------------------------------------------------------------------
  -- 2. فحص تسريب الصلاحيات (EXECUTE لـ PUBLIC أو anon)
  ------------------------------------------------------------------------------
  FOR PRIV IN
    SELECT routine_name, grantee
    FROM information_schema.routine_privileges
    WHERE routine_name IN ('reschedule_visit_item_to_date_atomic_impl', 'close_visit_day_missed_atomic_impl', 'reschedule_visit_item_to_date_atomic', 'close_visit_day_missed_atomic')
      AND privilege_type = 'EXECUTE'
      AND grantee IN ('PUBLIC', 'anon')
  LOOP
    v_error_count := v_error_count + 1;
    v_error_details := v_error_details || E'\n- تسريب صلاحية EXECUTE للدالة ' || PRIV.routine_name || ' للمستخدم ' || PRIV.grantee;
  END LOOP;

  -- التأكد من منح EXECUTE لـ authenticated على دوال الواجهة العامة والدوال الخاصة المرتبطة بالغلاف
  FOR PRIV IN
    SELECT unnest(ARRAY['reschedule_visit_item_to_date_atomic', 'close_visit_day_missed_atomic', 'reschedule_visit_item_to_date_atomic_impl', 'close_visit_day_missed_atomic_impl']) AS func_name
    EXCEPT
    SELECT routine_name
    FROM information_schema.routine_privileges
    WHERE privilege_type = 'EXECUTE' AND grantee = 'authenticated'
  LOOP
    v_error_count := v_error_count + 1;
    v_error_details := v_error_details || E'\n- غياب صلاحية EXECUTE لـ authenticated للدالة ' || PRIV.func_name;
  END LOOP;

  ------------------------------------------------------------------------------
  -- 3. الفحص النصي العام (الأنماط الآمنة والمحرمات)
  ------------------------------------------------------------------------------
  FOR PROC IN
    SELECT proname, prosrc
    FROM pg_proc JOIN pg_namespace n ON pg_proc.pronamespace = n.oid
    WHERE proname IN ('reschedule_visit_item_to_date_atomic_impl', 'close_visit_day_missed_atomic_impl')
      AND n.nspname = 'private'
  LOOP
    IF PROC.prosrc NOT ILIKE '%auth.uid()%' AND PROC.prosrc NOT ILIKE '%check_permission%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- غياب فحص المستخدم (auth.uid) أو الصلاحيات في ' || PROC.proname;
    END IF;

    IF PROC.prosrc NOT ILIKE '%private.visit_operation_requests%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- غياب نظام الـ Idempotency في ' || PROC.proname;
    END IF;

    IF PROC.prosrc NOT ILIKE '%FOR UPDATE%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- غياب أقفال SELECT FOR UPDATE في ' || PROC.proname;
    END IF;

    IF PROC.prosrc ILIKE '%SQLERRM%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- تسريب أخطاء داخلية عبر SQLERRM في ' || PROC.proname;
    END IF;

    IF PROC.prosrc NOT ILIKE '%client_event_at%' OR PROC.prosrc NOT ILIKE '%device_timezone%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- عدم دمج client_event_at أو device_timezone في مصفوفة payload في ' || PROC.proname;
    END IF;

    -- الفحص الصارم לגداول المالية والمخزون
    IF PROC.prosrc ILIKE '%sales_orders%' OR PROC.prosrc ILIKE '%payment_receipts%' OR PROC.prosrc ILIKE '%stock%' OR PROC.prosrc ILIKE '%stock_movements%' OR PROC.prosrc ILIKE '%vault_transactions%' OR PROC.prosrc ILIKE '%custody_transactions%' OR PROC.prosrc ILIKE '%journal_entries%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق معماري: المساس بجداول المبيعات أو المالية أو المخزون في ' || PROC.proname;
    END IF;

    -- الفحص الصارم لتأهيل دالة gen_random_uuid
    IF REPLACE(PROC.prosrc, 'pg_catalog.gen_random_uuid', '') ILIKE '%gen_random_uuid%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- استخدام غير مؤهل لـ gen_random_uuid داخل الدالة الخاصة ' || PROC.proname;
    END IF;
  END LOOP;

  ------------------------------------------------------------------------------
  -- 4. فحوصات متخصصة لكل دالة
  ------------------------------------------------------------------------------
  -- أ) تخصيص لـ close_visit_day_missed_atomic_impl
  SELECT prosrc INTO PROC.prosrc FROM pg_proc WHERE proname = 'close_visit_day_missed_atomic_impl';
  IF PROC.prosrc IS NOT NULL THEN
    IF PROC.prosrc ILIKE '%status = ''skipped''%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق: استخدام حالة skipped بدلاً من missed لإنهاء اليومية.';
    END IF;
    IF PROC.prosrc ILIKE '%v_creator_employee_id = v_plan_employee_id%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق: السماح المباشر للمندوب بإغلاق اليومية لمجرد كونه مالك الخطة، يجب إيقافه واقتصاره على الصلاحيات الإدارية.';
    END IF;
  END IF;

  -- ب) تخصيص لـ reschedule_visit_item_to_date_atomic_impl
  SELECT prosrc INTO PROC.prosrc FROM pg_proc WHERE proname = 'reschedule_visit_item_to_date_atomic_impl';
  IF PROC.prosrc IS NOT NULL THEN
    IF (PROC.prosrc ILIKE '%target_plan_id %' OR PROC.prosrc ILIKE '%organizational_branch_id uuid%') AND PROC.prosrc NOT ILIKE '%v_target_plan_id%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق: استقبال target_plan_id أو organizational_branch_id من العميل في إعادة الجدولة.';
    END IF;

    IF PROC.prosrc NOT ILIKE '%p_target_date IS NULL%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق: غياب التحقق الصريح p_target_date IS NULL.';
    END IF;

    IF PROC.prosrc NOT ILIKE '%organizational_branch_id = v_source_branch_id%'
       AND PROC.prosrc NOT ILIKE '%organizational_branch_id IS NOT DISTINCT FROM v_source_branch_id%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق: غياب مطابقة organizational_branch_id عند جلب أو إنشاء خطة الوجهة.';
    END IF;

    IF PROC.prosrc NOT ILIKE '%recalculate_visit_plan_counts(v_target_plan_id)%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق: عدم استدعاء recalculate_visit_plan_counts لخطة الوجهة.';
    END IF;

    -- اختبارات قرارات خطة الوجهة
    IF PROC.prosrc ILIKE '%status IN (''draft'', ''in_progress'')%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق: السماح باستخدام خطة in_progress كوجهة لإعادة الجدولة.';
    END IF;

    IF PROC.prosrc NOT ILIKE '%NOT IN (''draft'', ''confirmed'')%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق: عدم وجود فحص صريح يرفض الخطط التي ليست draft أو confirmed كوجهة.';
    END IF;

    IF PROC.prosrc NOT ILIKE '%v_source_plan_type = ''daily''%'
       OR PROC.prosrc NOT ILIKE '%organizational_branch_id IS NOT DISTINCT FROM v_source_branch_id%'
       OR PROC.prosrc NOT ILIKE '%مرتبطة بفرع تنظيمي مختلف%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق: غياب معالجة القيد اليومي الفريد أو تعارض الفرع التنظيمي.';
    END IF;

    IF PROC.prosrc ILIKE '%v_has_access := false;%'
       OR PROC.prosrc ILIKE '%ELSIF (SELECT public.check_permission(v_actor_id, ''visit_plans.read_team''))%' THEN
      v_error_count := v_error_count + 1;
      v_error_details := v_error_details || E'\n- خرق: منطق الصلاحيات المتسلسل قد يحجب مالك الخطة عند امتلاكه صلاحية فريق.';
    END IF;
  END IF;

  ------------------------------------------------------------------------------
  -- النتيجة
  ------------------------------------------------------------------------------
  IF v_error_count > 0 THEN
    RAISE EXCEPTION 'فشل عقد التحقق الساكن المعماري للفجوات الذرية للزيارات! الأخطاء: %', v_error_details;
  ELSE
    RAISE NOTICE 'اجتازت العمليات الذرية المتبقية عقد التحقق المعماري والأمني بنجاح تام.';
  END IF;
END;
$$;


-- تأهيل pgcrypto حسب المخطط الفعلي
WITH expected(fn_name) AS (
  VALUES
    ('reschedule_visit_item_to_date_atomic_impl'),
    ('close_visit_day_missed_atomic_impl')
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
