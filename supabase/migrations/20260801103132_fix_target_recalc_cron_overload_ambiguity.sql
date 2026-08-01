-- ============================================================
-- Fix target recalculation cron overload ambiguity
-- Remote migration history version: 20260801103132
--
-- Root cause:
--   Both overloads existed at the same time:
--     recalculate_all_active_targets()
--     recalculate_all_active_targets(date DEFAULT CURRENT_DATE)
--   Therefore the cron call with no arguments matched both functions and
--   PostgreSQL raised "function ... is not unique" every five minutes.
--
-- The date-aware overload is the canonical superset: explicit-date callers
-- keep historical recalculation support, while no-argument callers keep the
-- same CURRENT_DATE behavior through its default argument.
--
-- Scope: remove only the redundant zero-argument overload. No cron, target,
-- progress, trigger, permission, or calculation logic is changed.
-- ============================================================

DO $$
DECLARE
  v_canonical_oid oid;
  v_default_count integer;
BEGIN
  SELECT p.oid, p.pronargdefaults
  INTO v_canonical_oid, v_default_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'recalculate_all_active_targets'
    AND pg_get_function_identity_arguments(p.oid) = 'p_snapshot_date date';

  IF v_canonical_oid IS NULL THEN
    RAISE EXCEPTION
      '[EDARA] canonical recalculate_all_active_targets(date) is missing; refusing overload cleanup';
  END IF;

  IF v_default_count <> 1 THEN
    RAISE EXCEPTION
      '[EDARA] recalculate_all_active_targets(date) must retain its CURRENT_DATE default; refusing overload cleanup';
  END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.recalculate_all_active_targets();

DO $$
DECLARE
  v_overload_count integer;
BEGIN
  SELECT count(*)
  INTO v_overload_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'recalculate_all_active_targets';

  IF v_overload_count <> 1 THEN
    RAISE EXCEPTION
      '[EDARA] expected exactly one recalculate_all_active_targets overload after cleanup; found %',
      v_overload_count;
  END IF;
END;
$$;
