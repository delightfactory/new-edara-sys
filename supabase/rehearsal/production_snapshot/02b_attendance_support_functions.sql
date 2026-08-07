-- Production-derived attendance support helper used by V2 wrappers.
-- Captured read-only from production on 2026-08-07.

CREATE OR REPLACE FUNCTION public.reprocess_attendance_day_penalties(p_attendance_day_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_deleted INTEGER;
  v_reapplied INTEGER;
BEGIN
  DELETE FROM hr_penalty_instances
  WHERE attendance_day_id = p_attendance_day_id
    AND payroll_run_id IS NULL
    AND is_overridden = false;

  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  SELECT process_attendance_penalties(p_attendance_day_id)
  INTO v_reapplied;

  RETURN COALESCE(v_reapplied, 0);
END;
$function$;
