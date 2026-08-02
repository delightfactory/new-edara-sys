-- Keep payroll approval balanced when employee deductions exceed earnings.
--
-- calculate_employee_payroll floors a negative net salary at zero and stores
-- the excess in deficit_carryover for deduction in the following month.
-- approve_payroll_run must therefore include that deferred deduction in the
-- current 5310 debit; otherwise credits exceed debits by the exact deficit.

DO $$
DECLARE
  v_old_def             TEXT;
  v_source_def          TEXT;
  v_new_def             TEXT;
  v_previous_def        TEXT;
  v_applied_def         TEXT;
  v_is_security_definer BOOLEAN;
  v_search_path         TEXT[];
BEGIN
  SELECT pg_get_functiondef(p.oid), p.prosecdef, p.proconfig
  INTO v_old_def, v_is_security_definer, v_search_path
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'approve_payroll_run'
    AND pg_get_function_identity_arguments(p.oid) = 'p_run_id uuid, p_user_id uuid';

  IF v_old_def IS NULL THEN
    RAISE EXCEPTION 'approve_payroll_run(uuid, uuid) was not found';
  END IF;

  IF v_old_def LIKE '%v_total_deficit%' THEN
    RAISE NOTICE 'approve_payroll_run already accounts for deficit carryover';
    RETURN;
  END IF;

  -- pg_get_functiondef preserves the original function-body line endings.
  -- Normalize them so the guarded replacements work for both LF and CRLF.
  v_source_def := replace(replace(v_old_def, E'\r\n', E'\n'), E'\r', E'\n');

  v_new_def := replace(
    v_source_def,
    '  v_total_bonus          NUMERIC := 0;' || E'\n' ||
    '  v_total_debit          NUMERIC;',
    '  v_total_bonus          NUMERIC := 0;' || E'\n' ||
    '  v_total_deficit        NUMERIC := 0;' || E'\n' ||
    '  v_total_debit          NUMERIC;'
  );

  IF v_new_def = v_source_def THEN
    RAISE EXCEPTION 'approve_payroll_run declaration did not match the expected definition; no change was applied';
  END IF;

  v_previous_def := v_new_def;
  v_new_def := replace(
    v_new_def,
    '  v_total_debit  := v_total_salary_expense + v_total_overtime + v_total_commission + v_total_bonus;',
    '  SELECT COALESCE(SUM(deficit_carryover), 0)' || E'\n' ||
    '  INTO v_total_deficit' || E'\n' ||
    '  FROM hr_payroll_lines' || E'\n' ||
    '  WHERE payroll_run_id = p_run_id;' || E'\n\n' ||
    '  v_total_salary_expense := v_total_salary_expense + v_total_deficit;' || E'\n\n' ||
    '  v_total_debit  := v_total_salary_expense + v_total_overtime + v_total_commission + v_total_bonus;'
  );

  IF v_new_def = v_previous_def THEN
    RAISE EXCEPTION 'approve_payroll_run debit calculation did not match the expected definition; no change was applied';
  END IF;

  v_previous_def := v_new_def;
  v_new_def := replace(
    v_new_def,
    '        ''dr_5310_salaries'',   v_total_salary_expense,',
    '        ''dr_5310_salaries'',   v_total_salary_expense - v_total_deficit,' || E'\n' ||
    '        ''dr_5310_deficit'',    v_total_deficit,'
  );

  IF v_new_def = v_previous_def THEN
    RAISE EXCEPTION 'approve_payroll_run accounting summary did not match the expected definition; no change was applied';
  END IF;

  IF v_new_def NOT LIKE '%v_total_deficit        NUMERIC := 0;%'
     OR v_new_def NOT LIKE '%SUM(deficit_carryover)%'
     OR v_new_def NOT LIKE '%v_total_salary_expense := v_total_salary_expense + v_total_deficit;%'
     OR v_new_def NOT LIKE '%''dr_5310_deficit'',    v_total_deficit%' THEN
    RAISE EXCEPTION 'approve_payroll_run did not match the expected definition; no change was applied';
  END IF;

  EXECUTE v_new_def;

  SELECT pg_get_functiondef(p.oid), p.prosecdef, p.proconfig
  INTO v_applied_def, v_is_security_definer, v_search_path
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'approve_payroll_run'
    AND pg_get_function_identity_arguments(p.oid) = 'p_run_id uuid, p_user_id uuid';

  IF v_applied_def NOT LIKE '%SUM(deficit_carryover)%'
     OR v_applied_def NOT LIKE '%v_total_salary_expense := v_total_salary_expense + v_total_deficit;%'
     OR NOT v_is_security_definer
     OR NOT ('search_path=public' = ANY(COALESCE(v_search_path, ARRAY[]::TEXT[]))) THEN
    RAISE EXCEPTION 'approve_payroll_run post-install verification failed';
  END IF;
END
$$;

GRANT EXECUTE ON FUNCTION public.approve_payroll_run(UUID, UUID) TO authenticated;
