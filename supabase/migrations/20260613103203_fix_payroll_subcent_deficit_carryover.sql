-- Prevent sub-cent floating results from creating a 0.00 carryover adjustment.
-- Payroll amounts are stored at two-decimal currency precision, so normalize
-- net salary before deciding whether a real deficit exists.
DO $$
DECLARE
  v_old_def TEXT;
  v_new_def TEXT;
  v_applied_def TEXT;
  v_is_security_definer BOOLEAN;
  v_search_path TEXT[];
BEGIN
  SELECT pg_get_functiondef(
    'public.calculate_employee_payroll(uuid, uuid)'::regprocedure
  )
  INTO v_old_def;

  v_new_def := regexp_replace(
    v_old_def,
    'v_net\s*:=\s*v_gross_earned\s*\+\s*v_overtime_amount\s*\+\s*v_commission\s*\+\s*v_adj_bonus\s*-\s*v_absence_deduct\s*-\s*v_penalty_deduct\s*-\s*v_advance_deduct\s*-\s*v_si_deduct\s*-\s*v_tax_deduct\s*-\s*v_health_deduct\s*-\s*v_adj_deduction\s*;',
    'v_net := ROUND(
      v_gross_earned + v_overtime_amount + v_commission + v_adj_bonus
      - v_absence_deduct - v_penalty_deduct - v_advance_deduct
      - v_si_deduct - v_tax_deduct - v_health_deduct - v_adj_deduction,
      2
    );',
    'i'
  );

  IF v_new_def = v_old_def THEN
    RAISE EXCEPTION
      'calculate_employee_payroll net salary expression was not found';
  END IF;

  EXECUTE v_new_def;

  SELECT
    pg_get_functiondef(p.oid),
    p.prosecdef,
    p.proconfig
  INTO
    v_applied_def,
    v_is_security_definer,
    v_search_path
  FROM pg_proc p
  WHERE p.oid = 'public.calculate_employee_payroll(uuid, uuid)'::regprocedure;

  IF v_applied_def !~* 'v_net\s*:=\s*ROUND\s*\(' THEN
    RAISE EXCEPTION
      'calculate_employee_payroll net salary rounding was not applied';
  END IF;

  IF NOT v_is_security_definer
     OR NOT ('search_path=public' = ANY(COALESCE(v_search_path, ARRAY[]::TEXT[]))) THEN
    RAISE EXCEPTION
      'calculate_employee_payroll security settings changed unexpectedly';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.calculate_employee_payroll(UUID, UUID)
TO authenticated;
