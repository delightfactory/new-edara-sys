-- Production-derived helper functions used by HR V2 rehearsal.
-- Captured read-only from NEW-EDARA-SYS on 2026-08-07. No data included.

CREATE OR REPLACE FUNCTION public.check_permission(p_user_id uuid, p_permission text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (
      SELECT granted
      FROM user_permission_overrides
      WHERE user_id = p_user_id
        AND permission = p_permission
        AND (expires_at IS NULL OR expires_at > now())
      LIMIT 1
    ),
    EXISTS (
      SELECT 1
      FROM user_roles ur
      JOIN role_permissions rp ON rp.role_id = ur.role_id
      WHERE ur.user_id = p_user_id
        AND ur.is_active = true
        AND (rp.permission = p_permission OR rp.permission = '*')
    )
  )
$function$;

CREATE OR REPLACE FUNCTION public.resolve_employee_attendance_location_context(p_employee_id uuid, p_latitude numeric, p_longitude numeric, p_action text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_employee hr_employees%ROWTYPE;
  v_mode TEXT;
  v_allowed_ids UUID[];
  v_location hr_work_locations%ROWTYPE;
  v_distance NUMERIC;
  v_allowed_count INTEGER := 0;
  v_max_field_distance NUMERIC := 50000;
BEGIN
  SELECT * INTO v_employee FROM hr_employees WHERE id = p_employee_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', false, 'code', 'NO_EMPLOYEE', 'error', 'تعذر تحديد الموظف');
  END IF;

  SELECT COALESCE(value::NUMERIC, 50000)
  INTO v_max_field_distance
  FROM company_settings
  WHERE key = 'hr.field_attendance_max_distance_meters';

  IF p_action = 'check_out' THEN
    v_mode := COALESCE(v_employee.attendance_checkout_mode, 'assigned_only');
    v_allowed_ids := COALESCE(v_employee.allowed_checkout_location_ids, '{}');
  ELSIF p_action = 'track' THEN
    IF v_employee.is_field_employee THEN
      v_mode := 'field_allowed';
    ELSE
      v_mode := COALESCE(v_employee.attendance_checkin_mode, 'assigned_only');
    END IF;
    v_allowed_ids := (
      SELECT ARRAY(
        SELECT DISTINCT x
        FROM unnest(
          COALESCE(v_employee.allowed_checkin_location_ids, '{}')
          || COALESCE(v_employee.allowed_checkout_location_ids, '{}')
          || CASE
               WHEN v_employee.work_location_id IS NOT NULL THEN ARRAY[v_employee.work_location_id]
               ELSE ARRAY[]::UUID[]
             END
        ) AS x
      )
    );
  ELSE
    v_mode := COALESCE(v_employee.attendance_checkin_mode, 'assigned_only');
    v_allowed_ids := COALESCE(v_employee.allowed_checkin_location_ids, '{}');
  END IF;

  IF cardinality(v_allowed_ids) = 0 AND v_employee.work_location_id IS NOT NULL THEN
    v_allowed_ids := ARRAY[v_employee.work_location_id];
  END IF;
  v_allowed_count := COALESCE(cardinality(v_allowed_ids), 0);

  IF v_mode = 'field_allowed' THEN
    IF v_allowed_count > 0 THEN
      SELECT * INTO v_location
      FROM hr_work_locations
      WHERE is_active = true AND id = ANY(v_allowed_ids)
      ORDER BY (6371000 * acos(LEAST(1.0,
        cos(radians(latitude)) * cos(radians(p_latitude))
        * cos(radians(p_longitude) - radians(longitude))
        + sin(radians(latitude)) * sin(radians(p_latitude)))))
      LIMIT 1;
    ELSE
      SELECT * INTO v_location
      FROM hr_work_locations
      WHERE is_active = true
      ORDER BY (6371000 * acos(LEAST(1.0,
        cos(radians(latitude)) * cos(radians(p_latitude))
        * cos(radians(p_longitude) - radians(longitude))
        + sin(radians(latitude)) * sin(radians(p_latitude)))))
      LIMIT 1;
    END IF;

    IF FOUND THEN
      v_distance := 6371000 * acos(LEAST(1.0,
        cos(radians(v_location.latitude)) * cos(radians(p_latitude))
        * cos(radians(p_longitude) - radians(v_location.longitude))
        + sin(radians(v_location.latitude)) * sin(radians(p_latitude))));
    END IF;

    IF NOT FOUND OR v_distance > v_max_field_distance THEN
      RETURN jsonb_build_object(
        'valid', false,
        'code', 'OUT_OF_RANGE',
        'error', format(
          'أنت خارج نطاق الحضور الميداني المسموح. المسافة الحالية %s كم والحد الأقصى %s كم',
          round(COALESCE(v_distance, 0) / 1000),
          round(v_max_field_distance / 1000)
        ),
        'location_id', v_location.id,
        'location_name', v_location.name,
        'distance_meters', round(COALESCE(v_distance, 0)),
        'max_distance_meters', round(v_max_field_distance),
        'is_field_employee', v_employee.is_field_employee,
        'policy_mode', v_mode,
        'inside_allowed_zone', false
      );
    END IF;

    RETURN jsonb_build_object(
      'valid', true,
      'location_id', v_location.id,
      'location_name', v_location.name,
      'distance_meters', round(v_distance),
      'max_distance_meters', round(v_max_field_distance),
      'is_field_employee', v_employee.is_field_employee,
      'policy_mode', v_mode,
      'inside_allowed_zone', true
    );
  END IF;

  IF v_allowed_count = 0 THEN
    RETURN jsonb_build_object(
      'valid', false,
      'code', 'NO_ALLOWED_LOCATIONS',
      'error', 'لا توجد مواقع حضور مسموح بها لهذا الموظف',
      'is_field_employee', v_employee.is_field_employee,
      'policy_mode', v_mode
    );
  END IF;

  SELECT * INTO v_location
  FROM hr_work_locations
  WHERE is_active = true AND id = ANY(v_allowed_ids)
  ORDER BY (6371000 * acos(LEAST(1.0,
    cos(radians(latitude)) * cos(radians(p_latitude))
    * cos(radians(p_longitude) - radians(longitude))
    + sin(radians(latitude)) * sin(radians(p_latitude)))))
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'valid', false,
      'code', 'NO_ALLOWED_LOCATIONS',
      'error', 'المواقع المسموح بها غير مفعلة أو غير موجودة',
      'is_field_employee', v_employee.is_field_employee,
      'policy_mode', v_mode
    );
  END IF;

  v_distance := 6371000 * acos(LEAST(1.0,
    cos(radians(v_location.latitude)) * cos(radians(p_latitude))
    * cos(radians(p_longitude) - radians(v_location.longitude))
    + sin(radians(v_location.latitude)) * sin(radians(p_latitude))));

  IF v_distance > v_location.radius_meters THEN
    RETURN jsonb_build_object(
      'valid', false,
      'code', 'OUT_OF_RANGE',
      'error', format('أنت خارج النطاق المسموح. المسافة الحالية %s متر', round(v_distance)),
      'location_id', v_location.id,
      'location_name', v_location.name,
      'distance_meters', round(v_distance),
      'is_field_employee', v_employee.is_field_employee,
      'policy_mode', v_mode,
      'inside_allowed_zone', false
    );
  END IF;

  RETURN jsonb_build_object(
    'valid', true,
    'location_id', v_location.id,
    'location_name', v_location.name,
    'distance_meters', round(v_distance),
    'is_field_employee', v_employee.is_field_employee,
    'policy_mode', v_mode,
    'inside_allowed_zone', true
  );
END;
$function$;
