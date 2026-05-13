-- ============================================================
-- Migration 115: HR Advance Installments Integrity (Phase 3)
-- ============================================================

-- SAFETY CHECK: Prevent migration if deferred rows exist.
DO $$
DECLARE
  v_deferred_count INT;
BEGIN
  SELECT COUNT(*) INTO v_deferred_count FROM hr_advance_installments WHERE status = 'deferred';
  IF v_deferred_count > 0 THEN
    RAISE EXCEPTION 'SAFETY BLOCK: Found % deferred installments. Please manually migrate their dates and set them to pending before running this migration.', v_deferred_count;
  END IF;
END;
$$;

-- 1. Fix handle_advance_approval (Rounding & Precision)
CREATE OR REPLACE FUNCTION handle_advance_approval()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_period_id    UUID;
  v_period_year  INTEGER;
  v_period_month INTEGER;
  i              INTEGER;
  v_start_offset INTEGER;
  v_base_inst    NUMERIC;
  v_current_inst NUMERIC;
BEGIN
  IF NEW.status = 'approved' AND OLD.status <> 'approved' THEN
    v_period_year  := EXTRACT(YEAR  FROM CURRENT_DATE)::INTEGER;
    v_period_month := EXTRACT(MONTH FROM CURRENT_DATE)::INTEGER;

    v_start_offset := CASE WHEN NEW.advance_type = 'instant' THEN 0 ELSE 1 END;
    
    -- Calculate base installment, and we will let the last installment absorb remainder
    v_base_inst := ROUND(NEW.amount / NEW.installments_count, 2);

    FOR i IN 1 .. NEW.installments_count LOOP
      DECLARE
        v_inst_year  INTEGER;
        v_inst_month INTEGER;
        v_offset     INTEGER := (i - 1) + v_start_offset;
      BEGIN
        v_inst_month := ((v_period_month - 1 + v_offset) % 12) + 1;
        v_inst_year  := v_period_year + ((v_period_month - 1 + v_offset) / 12);

        INSERT INTO hr_payroll_periods (year, month, name, start_date, end_date)
        VALUES (
          v_inst_year, v_inst_month,
          to_char(make_date(v_inst_year, v_inst_month, 1), 'Month YYYY'),
          make_date(v_inst_year, v_inst_month, 1),
          (make_date(v_inst_year, v_inst_month, 1) + INTERVAL '1 month - 1 day')::DATE
        ) ON CONFLICT (year, month) DO NOTHING;

        SELECT id INTO v_period_id
        FROM hr_payroll_periods WHERE year = v_inst_year AND month = v_inst_month;

        -- Last installment absorbs the difference
        IF i = NEW.installments_count THEN
           v_current_inst := NEW.amount - (v_base_inst * (NEW.installments_count - 1));
        ELSE
           v_current_inst := v_base_inst;
        END IF;

        -- Force v_current_inst directly, ignoring NEW.monthly_installment to ensure exact sum matching
        INSERT INTO hr_advance_installments (
          advance_id, installment_number, period_id,
          due_year, due_month, amount, status
        ) VALUES (
          NEW.id, i, v_period_id,
          v_inst_year, v_inst_month,
          v_current_inst,
          'pending'
        );
      END;
    END LOOP;
  END IF;

  RETURN NEW;
END; $$;

-- 2. Fix handle_installment_deducted (Double deduction + COALESCE)
CREATE OR REPLACE FUNCTION handle_installment_deducted()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'deducted' AND OLD.status <> 'deducted' THEN
    UPDATE hr_advances
    SET paid_amount = LEAST(amount, COALESCE(paid_amount, 0) + NEW.amount),
        status = CASE 
          WHEN LEAST(amount, COALESCE(paid_amount, 0) + NEW.amount) >= amount - 0.005 THEN 'fully_repaid' 
          ELSE status 
        END,
        updated_at = now()
    WHERE id = NEW.advance_id;
  END IF;
  RETURN NEW;
END; $$;

-- 3. New RPC: defer_advance_installment
CREATE OR REPLACE FUNCTION defer_advance_installment(
  p_installment_id UUID,
  p_new_due_year INTEGER,
  p_new_due_month INTEGER,
  p_reason TEXT
) RETURNS JSONB
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_inst RECORD;
  v_period_id UUID;
BEGIN
  -- Strict Auth Check
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  -- Security check: Require approve permission only.
  IF NOT check_permission(auth.uid(), 'hr.advances.approve') THEN
    RAISE EXCEPTION 'Access denied. Requires hr.advances.approve permission.';
  END IF;

  IF p_new_due_month < 1 OR p_new_due_month > 12 THEN
    RAISE EXCEPTION 'Invalid month. Must be between 1 and 12.';
  END IF;

  -- Atomic locking for the installment
  SELECT * INTO v_inst FROM hr_advance_installments WHERE id = p_installment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Installment not found'; END IF;
  
  IF v_inst.status <> 'pending' THEN
    RAISE EXCEPTION 'Can only defer pending installments';
  END IF;

  -- Ensure target period exists
  INSERT INTO hr_payroll_periods (year, month, name, start_date, end_date)
  VALUES (
    p_new_due_year, p_new_due_month,
    to_char(make_date(p_new_due_year, p_new_due_month, 1), 'Month YYYY'),
    make_date(p_new_due_year, p_new_due_month, 1),
    (make_date(p_new_due_year, p_new_due_month, 1) + INTERVAL '1 month - 1 day')::DATE
  ) ON CONFLICT (year, month) DO NOTHING;

  SELECT id INTO v_period_id
  FROM hr_payroll_periods WHERE year = p_new_due_year AND month = p_new_due_month;

  UPDATE hr_advance_installments
  SET due_year = p_new_due_year,
      due_month = p_new_due_month,
      period_id = v_period_id,
      deferred_reason = p_reason,
      deferred_to_month = p_new_due_month,
      deferred_to_year = p_new_due_year,
      status = 'pending' -- keep it pending
  WHERE id = p_installment_id;

  RETURN jsonb_build_object('success', true, 'message', 'تم تأجيل القسط بنجاح');
END; $$;

-- 4. Secure request_advance
CREATE OR REPLACE FUNCTION request_advance(
  p_employee_id       UUID,
  p_advance_type      hr_advance_type,
  p_amount            NUMERIC,
  p_installments      INTEGER,
  p_reason            TEXT,
  p_requested_by_uid  UUID
) RETURNS JSONB
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_emp              hr_employees%ROWTYPE;
  v_max_months       NUMERIC;
  v_max_active       INTEGER;
  v_instant_max_pct  NUMERIC;
  v_max_inst         INTEGER;
  v_min_inst         INTEGER;
  v_active_count     INTEGER;
  v_advance_id       UUID;
BEGIN
  -- Strict Auth Check
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT * INTO v_emp FROM hr_employees WHERE id = p_employee_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'الموظف غير موجود'; END IF;

  -- SECURE: Ensure caller has approve permission OR (is the employee themselves AND has create permission)
  IF NOT check_permission(auth.uid(), 'hr.advances.approve') THEN
    IF NOT check_permission(auth.uid(), 'hr.advances.create') THEN
       RAISE EXCEPTION 'Access denied. Missing hr.advances.create permission.';
    END IF;
    IF v_emp.user_id IS DISTINCT FROM auth.uid() THEN
       RAISE EXCEPTION 'Access denied. You cannot request an advance for another employee.';
    END IF;
  END IF;

  -- ─── قراءة الإعدادات ───
  SELECT COALESCE(value::NUMERIC, 1)  INTO v_max_months   FROM company_settings WHERE key = 'hr.advance_max_months_salary';
  SELECT COALESCE(value::INTEGER, 1)  INTO v_max_active    FROM company_settings WHERE key = 'hr.advance_max_active';
  SELECT COALESCE(value::NUMERIC, 50) INTO v_instant_max_pct FROM company_settings WHERE key = 'hr.instant_advance_max_percent';
  SELECT COALESCE(value::INTEGER, 6)  INTO v_max_inst      FROM company_settings WHERE key = 'hr.advance_max_installments';
  SELECT COALESCE(value::INTEGER, 1)  INTO v_min_inst      FROM company_settings WHERE key = 'hr.advance_min_installments';

  -- ─── التحقق: سلفة نشطة؟ ───
  SELECT COUNT(*) INTO v_active_count
  FROM hr_advances
  WHERE employee_id = p_employee_id
    AND status NOT IN ('fully_repaid', 'rejected', 'cancelled');

  IF v_active_count >= v_max_active THEN
    RETURN jsonb_build_object(
      'success', false,
      'code',    'ACTIVE_ADVANCE_EXISTS',
      'message', 'لديك سلفة نشطة بالفعل. يجب إتمام سدادها أولاً'
    );
  END IF;

  -- ─── التحقق: الحد الأقصى ───
  IF p_advance_type = 'instant' THEN
    IF p_amount > (v_emp.gross_salary * v_instant_max_pct / 100) THEN
      RETURN jsonb_build_object(
        'success', false,
        'code',    'EXCEEDS_INSTANT_LIMIT',
        'message', format('السلفة الفورية لا تتجاوز %s%% من الراتب', v_instant_max_pct)
      );
    END IF;
  ELSE
    IF p_amount > (v_emp.gross_salary * v_max_months) THEN
      RETURN jsonb_build_object(
        'success', false,
        'code',    'EXCEEDS_SCHEDULED_LIMIT',
        'message', format('السلفة المجدولة لا تتجاوز %s شهر راتب', v_max_months)
      );
    END IF;
    IF p_installments < v_min_inst OR p_installments > v_max_inst THEN
      RETURN jsonb_build_object(
        'success', false,
        'code',    'INVALID_INSTALLMENTS',
        'message', format('عدد الأقساط يجب أن يكون بين %s و%s', v_min_inst, v_max_inst)
      );
    END IF;
  END IF;

  -- ─── إنشاء السلفة ───
  INSERT INTO hr_advances (
    employee_id, advance_type, amount,
    installments_count,
    monthly_installment,
    reason, status, created_by
  ) VALUES (
    p_employee_id, p_advance_type, p_amount,
    CASE p_advance_type WHEN 'instant' THEN 1 ELSE p_installments END,
    CASE p_advance_type WHEN 'instant' THEN p_amount
                         ELSE ROUND(p_amount / p_installments, 2) END,
    p_reason, 'pending_supervisor', auth.uid()
  ) RETURNING id INTO v_advance_id;

  RETURN jsonb_build_object(
    'success',     true,
    'advance_id',  v_advance_id,
    'message',     'تم تقديم طلب السلفة بنجاح، في انتظار موافقة المشرف'
  );
END; $$;
