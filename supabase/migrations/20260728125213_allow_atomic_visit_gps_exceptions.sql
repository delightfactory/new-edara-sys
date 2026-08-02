BEGIN;

-- Planned visits may be started without device coordinates. The atomic
-- completion RPC records that case as an explicit GPS exception, but the
-- legacy activity trigger used to reject the activity before the RPC could
-- persist that exception. Keep GPS mandatory for every other write path and
-- allow only the narrowly-defined in-progress atomic visit case.
CREATE OR REPLACE FUNCTION public.validate_activity_payload()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  v_type       public.activity_types%ROWTYPE;
  v_visit_item public.visit_plan_items%ROWTYPE;
  v_visit_plan public.visit_plans%ROWTYPE;
  v_call_item  public.call_plan_items%ROWTYPE;
  v_call_plan  public.call_plans%ROWTYPE;
  v_is_atomic_visit_gps_exception BOOLEAN := false;
BEGIN
  SELECT * INTO v_type
  FROM public.activity_types
  WHERE id = NEW.type_id AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'نوع النشاط غير موجود أو غير نشط';
  END IF;

  IF NEW.visit_plan_item_id IS NOT NULL THEN
    SELECT * INTO v_visit_item
    FROM public.visit_plan_items
    WHERE id = NEW.visit_plan_item_id;

    v_is_atomic_visit_gps_exception :=
      FOUND
      AND v_type.category = 'visit'
      AND v_visit_item.status = 'in_progress'
      AND v_visit_item.server_started_at IS NOT NULL
      AND NEW.start_time IS NOT DISTINCT FROM v_visit_item.server_started_at
      AND NEW.end_time IS NOT NULL
      AND NEW.gps_verified IS false
      AND v_visit_item.gps_validation_status IN (
        'no_coordinates',
        'failed_accuracy',
        'failed_distance'
      );
  END IF;

  IF v_type.requires_gps
     AND (NEW.gps_lat IS NULL OR NEW.gps_lng IS NULL)
     AND NOT v_is_atomic_visit_gps_exception THEN
    RAISE EXCEPTION 'هذا النوع من الأنشطة يتطلب إحداثيات GPS (gps_lat و gps_lng)';
  END IF;

  IF v_type.requires_customer AND NEW.customer_id IS NULL THEN
    RAISE EXCEPTION 'هذا النوع من الأنشطة يتطلب عميلاً';
  END IF;

  IF NEW.visit_plan_item_id IS NOT NULL AND NEW.call_plan_item_id IS NOT NULL THEN
    RAISE EXCEPTION 'لا يمكن ربط النشاط ببند زيارة وبند مكالمة معاً';
  END IF;

  IF NEW.visit_plan_item_id IS NOT NULL THEN
    IF v_type.category <> 'visit' THEN
      RAISE EXCEPTION 'ربط بند زيارة يتطلب activity_type من فئة visit';
    END IF;

    IF v_visit_item.id IS NULL THEN
      RAISE EXCEPTION 'بند الزيارة المحدد غير موجود';
    END IF;

    SELECT * INTO v_visit_plan
    FROM public.visit_plans
    WHERE id = v_visit_item.plan_id;

    IF v_visit_plan.employee_id <> NEW.employee_id THEN
      RAISE EXCEPTION 'employee_id لا يطابق صاحب خطة الزيارة';
    END IF;
    IF NEW.customer_id IS NULL OR NEW.customer_id <> v_visit_item.customer_id THEN
      RAISE EXCEPTION 'customer_id لا يطابق عميل بند الزيارة';
    END IF;
  END IF;

  IF NEW.call_plan_item_id IS NOT NULL THEN
    IF v_type.category <> 'call' THEN
      RAISE EXCEPTION 'ربط بند مكالمة يتطلب activity_type من فئة call';
    END IF;

    SELECT * INTO v_call_item
    FROM public.call_plan_items
    WHERE id = NEW.call_plan_item_id;

    SELECT * INTO v_call_plan
    FROM public.call_plans
    WHERE id = v_call_item.plan_id;

    IF v_call_plan.employee_id <> NEW.employee_id THEN
      RAISE EXCEPTION 'employee_id لا يطابق صاحب خطة المكالمات';
    END IF;
    IF v_call_item.customer_id IS NOT NULL
       AND NEW.customer_id IS DISTINCT FROM v_call_item.customer_id THEN
      RAISE EXCEPTION 'customer_id لا يطابق عميل بند المكالمة';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.validate_activity_payload() FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.validate_activity_payload() IS
  'Validates activity payloads and permits missing GPS only for an in-progress planned visit whose atomic completion records an explicit GPS exception.';

COMMIT;
