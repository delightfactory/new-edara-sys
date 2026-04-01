-- 17_hr_core.sql bug fixes: Salary History and Contracts Source of Truth

-- 1. Modify the raw salary log trigger to respect a local bypass setting
CREATE OR REPLACE FUNCTION log_salary_change()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Skip automatic logging if bypass is active
  BEGIN
    IF current_setting('hr.bypass_salary_log', true) = 'true' THEN
      RETURN NEW;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Fallback just in case
  END;

  IF (NEW.base_salary <> OLD.base_salary OR
      NEW.transport_allowance <> OLD.transport_allowance OR
      NEW.housing_allowance <> OLD.housing_allowance OR
      NEW.other_allowances <> OLD.other_allowances) THEN
    
    INSERT INTO hr_salary_history (
      employee_id, effective_date,
      base_salary, transport_allowance, housing_allowance, other_allowances,
      change_reason
    ) VALUES (
      NEW.id, CURRENT_DATE,
      NEW.base_salary, NEW.transport_allowance, NEW.housing_allowance, NEW.other_allowances,
      'تحديث تلقائي للملف المالي (تعديل مباشر)'
    )
    ON CONFLICT (employee_id, effective_date) DO UPDATE
      SET base_salary = EXCLUDED.base_salary,
          transport_allowance = EXCLUDED.transport_allowance,
          housing_allowance = EXCLUDED.housing_allowance,
          other_allowances = EXCLUDED.other_allowances,
          change_reason = EXCLUDED.change_reason;
  END IF;
  RETURN NEW;
END; $$;


-- 2. Modify Contract Sync to bypass the raw logger and assert start_date history
CREATE OR REPLACE FUNCTION sync_employee_salary_from_contract()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Disable automatic log for this transaction
  PERFORM set_config('hr.bypass_salary_log', 'true', true);

  -- Update employee
  UPDATE hr_employees
  SET
    base_salary         = NEW.base_salary,
    transport_allowance = COALESCE(NEW.transport_allowance, 0),
    housing_allowance   = COALESCE(NEW.housing_allowance, 0),
    other_allowances    = COALESCE(NEW.other_allowances, 0),
    updated_at          = now()
  WHERE id = NEW.employee_id;

  -- Insert correct historical record based on contract metadata
  INSERT INTO hr_salary_history (
    employee_id, effective_date,
    base_salary, transport_allowance, housing_allowance, other_allowances,
    change_reason
  ) VALUES (
    NEW.employee_id, NEW.start_date,
    NEW.base_salary, COALESCE(NEW.transport_allowance, 0), COALESCE(NEW.housing_allowance, 0), COALESCE(NEW.other_allowances, 0),
    'تسجيل عقد جديد (' || NEW.contract_type || ')'
  )
  ON CONFLICT (employee_id, effective_date) DO UPDATE
    SET base_salary         = EXCLUDED.base_salary,
        transport_allowance = EXCLUDED.transport_allowance,
        housing_allowance   = EXCLUDED.housing_allowance,
        other_allowances    = EXCLUDED.other_allowances,
        change_reason       = EXCLUDED.change_reason;

  PERFORM set_config('hr.bypass_salary_log', 'false', true);
  
  RETURN NEW;
END; $$;


-- 3. Create a clean RPC for Direct Salary Updates with explicit Date and Reason
CREATE OR REPLACE FUNCTION update_employee_salary(
  p_employee_id UUID,
  p_base_salary NUMERIC,
  p_transport_allowance NUMERIC,
  p_housing_allowance NUMERIC,
  p_other_allowances NUMERIC,
  p_reason TEXT,
  p_effective_date DATE,
  p_changed_by UUID DEFAULT auth.uid()
)
RETURNS hr_salary_history LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_history hr_salary_history;
BEGIN
  -- 0. Security Guard
  IF NOT check_permission(auth.uid(), 'hr.employees.edit') THEN
    RAISE EXCEPTION 'Access Denied: missing hr.employees.edit permission';
  END IF;

  -- Disable automatic log for this transaction to avoid duplicates/wrong default reasons
  PERFORM set_config('hr.bypass_salary_log', 'true', true);

  -- 1. Update Employee Base
  UPDATE hr_employees
  SET
    base_salary         = p_base_salary,
    transport_allowance = COALESCE(p_transport_allowance, 0),
    housing_allowance   = COALESCE(p_housing_allowance, 0),
    other_allowances    = COALESCE(p_other_allowances, 0),
    updated_at          = now()
  WHERE id = p_employee_id;

  -- 2. Create Explicit History Record
  INSERT INTO hr_salary_history (
    employee_id, effective_date,
    base_salary, transport_allowance, housing_allowance, other_allowances,
    change_reason, changed_by
  ) VALUES (
    p_employee_id, COALESCE(p_effective_date, CURRENT_DATE),
    p_base_salary, COALESCE(p_transport_allowance, 0), COALESCE(p_housing_allowance, 0), COALESCE(p_other_allowances, 0),
    p_reason, p_changed_by
  )
  ON CONFLICT (employee_id, effective_date) DO UPDATE
    SET base_salary         = EXCLUDED.base_salary,
        transport_allowance = EXCLUDED.transport_allowance,
        housing_allowance   = EXCLUDED.housing_allowance,
        other_allowances    = EXCLUDED.other_allowances,
        change_reason       = EXCLUDED.change_reason,
        changed_by          = EXCLUDED.changed_by
  RETURNING * INTO v_history;

  PERFORM set_config('hr.bypass_salary_log', 'false', true);
  
  RETURN v_history;
END; $$;

REVOKE ALL ON FUNCTION update_employee_salary FROM PUBLIC;
GRANT EXECUTE ON FUNCTION update_employee_salary TO authenticated;
