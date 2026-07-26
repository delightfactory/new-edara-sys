-- Zero rows = pass.
WITH private_fn AS (
  SELECT p.oid, p.prosecdef, p.prosrc, p.proconfig
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'private'
    AND p.proname = 'reschedule_visit_item_to_date_atomic_impl'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) =
      'p_operation_id uuid, p_item_id uuid, p_target_date date, p_reschedule_reason text, p_planned_time time without time zone, p_client_event_at timestamp with time zone, p_device_timezone character varying'
),
public_fn AS (
  SELECT p.oid, p.prosecdef, p.prosrc, p.proconfig
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'reschedule_visit_item_to_date_atomic'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) =
      'p_operation_id uuid, p_item_id uuid, p_target_date date, p_reschedule_reason text, p_planned_time time without time zone, p_client_event_at timestamp with time zone, p_device_timezone character varying'
),
violations AS (
  SELECT 'PRIVATE_FUNCTION_MISSING' AS violation
  WHERE NOT EXISTS (SELECT 1 FROM private_fn)

  UNION ALL
  SELECT 'PRIVATE_FUNCTION_NOT_SECURITY_DEFINER'
  WHERE EXISTS (SELECT 1 FROM private_fn WHERE NOT prosecdef)

  UNION ALL
  SELECT 'PRIVATE_FUNCTION_UNSAFE_SEARCH_PATH'
  WHERE EXISTS (
    SELECT 1 FROM private_fn
    WHERE NOT (proconfig @> ARRAY['search_path=pg_catalog']::TEXT[])
  )

  UNION ALL
  SELECT 'SERVER_FUTURE_DATE_GUARD_MISSING'
  WHERE EXISTS (
    SELECT 1 FROM private_fn
    WHERE prosrc NOT ILIKE '%p_target_date <= v_today%'
       OR prosrc NOT ILIKE '%Africa/Cairo%'
  )

  UNION ALL
  SELECT 'REASON_LENGTH_GUARD_MISSING'
  WHERE EXISTS (
    SELECT 1 FROM private_fn
    WHERE prosrc NOT ILIKE '%char_length(BTRIM(p_reschedule_reason)) > 500%'
  )

  UNION ALL
  SELECT 'PLANNED_TIME_PRESERVATION_MISSING'
  WHERE EXISTS (
    SELECT 1 FROM private_fn
    WHERE prosrc NOT ILIKE '%COALESCE(p_planned_time, v_original_planned_time)%'
  )

  UNION ALL
  SELECT 'TARGET_DUPLICATE_GUARD_MISSING'
  WHERE EXISTS (
    SELECT 1 FROM private_fn
    WHERE prosrc NOT ILIKE '%TARGET_CUSTOMER_DUPLICATE%'
  )

  UNION ALL
  SELECT 'TARGET_PLAN_RESULT_METADATA_MISSING'
  WHERE EXISTS (
    SELECT 1 FROM private_fn
    WHERE prosrc NOT ILIKE '%target_plan_created%'
       OR prosrc NOT ILIKE '%target_plan_status%'
       OR prosrc NOT ILIKE '%planned_time%'
  )

  UNION ALL
  SELECT 'PUBLIC_FUNCTION_MISSING'
  WHERE NOT EXISTS (SELECT 1 FROM public_fn)

  UNION ALL
  SELECT 'PUBLIC_FUNCTION_NOT_SECURITY_INVOKER'
  WHERE EXISTS (SELECT 1 FROM public_fn WHERE prosecdef)

  UNION ALL
  SELECT 'ANON_CAN_EXECUTE_PRIVATE_FUNCTION'
  WHERE pg_catalog.has_function_privilege(
    'anon',
    'private.reschedule_visit_item_to_date_atomic_impl(uuid,uuid,date,text,time,timestamptz,varchar)',
    'EXECUTE'
  )

  UNION ALL
  SELECT 'ANON_CAN_EXECUTE_PUBLIC_FUNCTION'
  WHERE pg_catalog.has_function_privilege(
    'anon',
    'public.reschedule_visit_item_to_date_atomic(uuid,uuid,date,text,time,timestamptz,varchar)',
    'EXECUTE'
  )

  UNION ALL
  SELECT 'AUTHENTICATED_CANNOT_EXECUTE_PUBLIC_FUNCTION'
  WHERE NOT pg_catalog.has_function_privilege(
    'authenticated',
    'public.reschedule_visit_item_to_date_atomic(uuid,uuid,date,text,time,timestamptz,varchar)',
    'EXECUTE'
  )
)
SELECT violation
FROM violations
ORDER BY violation;
