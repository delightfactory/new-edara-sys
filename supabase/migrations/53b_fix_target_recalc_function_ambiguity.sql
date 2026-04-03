-- ============================================================
-- 53b_fix_target_recalc_function_ambiguity.sql
-- Cleanup: remove legacy 3-arg overload of recalculate_targets_for_employee
--
-- Root cause discovered during Wave 1B smoke test:
--   payment_receipts UPDATE -> confirmed was failing because PostgreSQL found
--   two overloads of public.recalculate_targets_for_employee(...):
--     1) (uuid, text[], date)
--     2) (uuid, text[], date, date DEFAULT NULL)
--
-- Calls that pass 3 arguments become ambiguous once the 4-arg version exists
-- with defaults. The 4-arg version fully supersedes the 3-arg version.
--
-- Safety:
--   - We verified there were no recorded DB dependencies on the 3-arg overload
--   - The 4-arg overload remains and covers all existing 3-arg call sites
--   - DROP FUNCTION IF EXISTS makes this migration idempotent
-- ============================================================

DROP FUNCTION IF EXISTS public.recalculate_targets_for_employee(
  uuid,
  text[],
  date
);

DO $$
DECLARE
  v_remaining_count integer;
  v_four_arg_exists boolean;
BEGIN
  SELECT COUNT(*)
  INTO v_remaining_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'recalculate_targets_for_employee';

  SELECT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'recalculate_targets_for_employee'
      AND pg_get_function_identity_arguments(p.oid) =
        'p_employee_id uuid, p_type_codes text[], p_snapshot_date date, p_effective_date date'
  )
  INTO v_four_arg_exists;

  RAISE NOTICE '[53b_cleanup] recalculate_targets_for_employee overloads remaining: %', v_remaining_count;
  RAISE NOTICE '[53b_cleanup] 4-arg canonical overload present: %',
    CASE WHEN v_four_arg_exists THEN 'yes' ELSE 'no' END;

  IF NOT v_four_arg_exists THEN
    RAISE WARNING '[53b_cleanup] canonical 4-arg overload missing unexpectedly';
  END IF;
END $$;
