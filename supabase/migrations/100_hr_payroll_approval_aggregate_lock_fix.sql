-- Fix approve_payroll_run(): PostgreSQL does not allow FOR UPDATE on aggregate queries.
-- Lock the pending advance installment rows first, then aggregate the locked rowset.

DO $$
DECLARE
  v_old_def TEXT;
  v_new_def TEXT;
BEGIN
  SELECT pg_get_functiondef('public.approve_payroll_run(uuid, uuid)'::regprocedure)
  INTO v_old_def;

  v_new_def := regexp_replace(
    v_old_def,
    'SELECT\s+COALESCE\s*\(\s*SUM\s*\(\s*ai\.amount\s*\)\s*,\s*0\s*\)\s+INTO\s+v_actual_advance\s+FROM\s+hr_advance_installments\s+ai\s+JOIN\s+hr_advances\s+adv\s+ON\s+adv\.id\s*=\s*ai\.advance_id\s+WHERE\s+adv\.employee_id\s*=\s*v_line\.employee_id\s+AND\s+ai\.due_year\s*=\s*v_period\.year\s+AND\s+ai\.due_month\s*=\s*v_period\.month\s+AND\s+ai\.status\s*=\s*''pending''\s+FOR\s+UPDATE\s*;',
    $sql$
      WITH locked_advance_installments AS (
        SELECT ai.amount
        FROM hr_advance_installments ai
        JOIN hr_advances adv ON adv.id = ai.advance_id
        WHERE adv.employee_id = v_line.employee_id
          AND ai.due_year = v_period.year AND ai.due_month = v_period.month
          AND ai.status = 'pending'
        FOR UPDATE OF ai
      )
      SELECT COALESCE(SUM(amount), 0) INTO v_actual_advance
      FROM locked_advance_installments;
    $sql$,
    'i'
  );

  IF v_new_def = v_old_def THEN
    RAISE EXCEPTION 'approve_payroll_run aggregate FOR UPDATE block was not found';
  END IF;

  EXECUTE v_new_def;
END;
$$;

GRANT EXECUTE ON FUNCTION approve_payroll_run(UUID, UUID) TO authenticated;
