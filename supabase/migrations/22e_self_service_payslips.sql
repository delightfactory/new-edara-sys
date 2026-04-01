-- ============================================================
-- Migration 22e: HR Self-Service Payslips
-- Provides a secure RPC for employees to fetch their own payslips
-- without exposing all payroll runs or lines via broad RLS policies.
-- ============================================================

CREATE OR REPLACE FUNCTION get_my_payslips()
RETURNS TABLE (
    line_id             UUID,
    period_year         INTEGER,
    period_month        INTEGER,
    period_name         TEXT,
    run_status          TEXT,
    base_salary         NUMERIC(12,2),
    total_allowances    NUMERIC(12,2),
    total_deductions    NUMERIC(12,2),
    net_salary          NUMERIC(12,2),
    -- detailed breakdowns for the viewer
    transport_allowance NUMERIC(12,2),
    housing_allowance   NUMERIC(12,2),
    other_allowances    NUMERIC(12,2),
    overtime_amount     NUMERIC(12,2),
    commission_amount   NUMERIC(12,2),
    bonus_amount        NUMERIC(12,2),
    absence_deduction   NUMERIC(12,2),
    penalty_deduction   NUMERIC(12,2),
    advance_deduction   NUMERIC(12,2),
    social_insurance    NUMERIC(12,2),
    health_insurance    NUMERIC(12,2),
    other_deductions    NUMERIC(12,2)
)
LANGUAGE plpgsql
SECURITY DEFINER   -- Exectutes with DB owner privileges to bypass hr_payroll_runs RLS securely
SET search_path = public
AS $$
DECLARE
  v_employee_id UUID;
BEGIN
  -- 1. Get the employee record linked to the current user
  SELECT id INTO v_employee_id 
  FROM hr_employees 
  WHERE user_id = auth.uid() 
  LIMIT 1;

  -- If no linked employee, return nothing
  IF v_employee_id IS NULL THEN
    RETURN;
  END IF;

  -- 2. Return ONLY the lines belong to this employee from 'approved' or 'paid' runs
  RETURN QUERY
  SELECT 
    pl.id,
    pp.year,
    pp.month,
    pp.name,
    pr.status::text,
    pl.base_salary,
    (pl.transport_allowance + pl.housing_allowance + pl.other_allowances + pl.overtime_amount + pl.commission_amount + pl.bonus_amount) AS total_allowances,
    pl.total_deductions,
    pl.net_salary,
    pl.transport_allowance,
    pl.housing_allowance,
    pl.other_allowances,
    pl.overtime_amount,
    pl.commission_amount,
    pl.bonus_amount,
    pl.absence_deduction,
    pl.penalty_deduction,
    pl.advance_deduction,
    pl.social_insurance,
    pl.health_insurance,
    pl.other_deductions
  FROM hr_payroll_lines pl
  INNER JOIN hr_payroll_runs pr ON pl.payroll_run_id = pr.id
  INNER JOIN hr_payroll_periods pp ON pr.period_id = pp.id
  WHERE pl.employee_id = v_employee_id
    AND pr.status IN ('approved', 'paid')
  ORDER BY pp.year DESC, pp.month DESC;
END;
$$;

-- Revoke execute from public to be safe
REVOKE EXECUTE ON FUNCTION get_my_payslips() FROM PUBLIC;
-- Grant ONLY to authenticated users
GRANT EXECUTE ON FUNCTION get_my_payslips() TO authenticated;
