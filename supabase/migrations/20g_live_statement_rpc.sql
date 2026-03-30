-- ════════════════════════════════════════════════════════════
-- Migration 20g v3: get_employee_live_statement RPC
-- ROOT CAUSE FIX:
--   1. get_employee_salary_at_date هي SETOF TABLE وليست row واحدة
--      الحل: متغيرات منفصلة بدلاً من RECORD
--   2. تجنب (record_var).field داخل jsonb_build_object — مصدر أخطاء خفية
--   3. استخدام COALESCE مباشرة على المتغيرات الصريحة
-- ════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS get_employee_live_statement(UUID);
DROP FUNCTION IF EXISTS get_employee_live_statement(UUID, INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION get_employee_live_statement(
  p_employee_id UUID,
  p_year        INTEGER DEFAULT NULL,
  p_month       INTEGER DEFAULT NULL
) RETURNS JSONB
  LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_emp                 hr_employees%ROWTYPE;
  v_summary             JSONB;
  v_year                INTEGER;
  v_month               INTEGER;
  v_advances            JSONB;
  v_commission          NUMERIC := 0;

  -- متغيرات الراتب — صريحة بدلاً من RECORD لتجنب مشاكل SETOF
  v_base_salary         NUMERIC := 0;
  v_transport_allowance NUMERIC := 0;
  v_housing_allowance   NUMERIC := 0;
  v_other_allowances    NUMERIC := 0;
  v_gross_salary        NUMERIC := 0;
BEGIN
  -- ─── التحقق من وجود الموظف ───
  SELECT * INTO v_emp FROM hr_employees WHERE id = p_employee_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الموظف غير موجود: %', p_employee_id;
  END IF;

  v_year  := COALESCE(p_year,  EXTRACT(YEAR  FROM CURRENT_DATE)::INTEGER);
  v_month := COALESCE(p_month, EXTRACT(MONTH FROM CURRENT_DATE)::INTEGER);

  -- ─── الراتب من سجل التاريخ (SETOF → نقرأ عمود بعمود) ───
  -- الدالة تُعيد أحدث سجل راتب سارٍ قبل أو في التاريخ المحدد
  SELECT
    sh.base_salary,
    sh.transport_allowance,
    sh.housing_allowance,
    sh.other_allowances,
    sh.gross_salary
  INTO
    v_base_salary,
    v_transport_allowance,
    v_housing_allowance,
    v_other_allowances,
    v_gross_salary
  FROM hr_salary_history sh
  WHERE sh.employee_id = p_employee_id
    AND sh.effective_date <= CURRENT_DATE
  ORDER BY sh.effective_date DESC
  LIMIT 1;

  -- إذا لم يوجد سجل تاريخ راتب → استخدم بيانات الموظف الحالية المخزنة
  IF NOT FOUND THEN
    v_base_salary         := v_emp.base_salary;
    v_transport_allowance := v_emp.transport_allowance;
    v_housing_allowance   := v_emp.housing_allowance;
    v_other_allowances    := v_emp.other_allowances;
    v_gross_salary        := v_emp.gross_salary;
  END IF;

  -- ─── ملخص الحضور الشهري (تقديري) ───
  BEGIN
    v_summary := get_monthly_attendance_summary(p_employee_id, v_year, v_month);
  EXCEPTION WHEN OTHERS THEN
    -- لا توجد بيانات حضور بعد هذا الشهر → قيم صفرية آمنة
    v_summary := jsonb_build_object(
      'working_days',           26,
      'present_days',           0,
      'absent_unauthorized',    0,
      'absent_authorized',      0,
      'on_leave_days',          0,
      'weekly_off_days',        0,
      'public_holidays',        0,
      'total_late_minutes',     0,
      'total_overtime_minutes', 0,
      'penalty_deduction_days', 0
    );
  END;

  -- ─── العمولات المؤهلة غير المُدرجة في مسير هذا الشهر ───
  SELECT COALESCE(SUM(commission_amount), 0) INTO v_commission
  FROM hr_commission_records
  WHERE employee_id                         = p_employee_id
    AND is_eligible                         = true
    AND included_in_run                     IS NULL
    AND EXTRACT(YEAR  FROM created_at)::INTEGER = v_year
    AND EXTRACT(MONTH FROM created_at)::INTEGER = v_month;

  -- ─── السلف النشطة وأقساطها القادمة ───
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id',                  adv.id,
    'number',              adv.number,
    'advance_type',        adv.advance_type,
    'amount',              adv.amount,
    'paid_amount',         adv.paid_amount,
    'remaining_amount',    adv.remaining_amount,
    'monthly_installment', adv.monthly_installment,
    'reason',              adv.reason,
    'status',              adv.status,
    'next_installment', (
      SELECT jsonb_build_object(
        'month',  ai.due_month,
        'year',   ai.due_year,
        'amount', ai.amount
      )
      FROM hr_advance_installments ai
      WHERE ai.advance_id = adv.id
        AND ai.status     = 'pending'
      ORDER BY ai.due_year, ai.due_month
      LIMIT 1
    )
  )), '[]'::jsonb)
  INTO v_advances
  FROM hr_advances adv
  WHERE adv.employee_id = p_employee_id
    AND adv.status NOT IN ('fully_repaid', 'rejected', 'cancelled');

  -- ─── تجميع الكشف الكامل ───
  RETURN jsonb_build_object(
    'employee', jsonb_build_object(
      'id',              v_emp.id,
      'name',            v_emp.full_name,
      'number',          v_emp.employee_number,
      'position_name',   NULL,
      'department_name', NULL
    ),
    'period', jsonb_build_object(
      'year',       v_year,
      'month',      v_month,
      'label',      to_char(make_date(v_year, v_month, 1), 'FMMonth YYYY'),
      'month_name', to_char(make_date(v_year, v_month, 1), 'FMMonth YYYY')
    ),
    'earnings', jsonb_build_object(
      'base_salary',         v_base_salary,
      'transport_allowance', v_transport_allowance,
      'housing_allowance',   v_housing_allowance,
      'other_allowances',    v_other_allowances,
      'gross_salary',        v_gross_salary,
      'commission_amount',   v_commission
    ),
    'attendance', jsonb_build_object(
      'working_days',           COALESCE((v_summary->>'working_days')::INTEGER,           26),
      'present_days',           COALESCE((v_summary->>'present_days')::INTEGER,           0),
      'absent_unauthorized',    COALESCE((v_summary->>'absent_unauthorized')::INTEGER,    0),
      'total_late_minutes',     COALESCE((v_summary->>'total_late_minutes')::INTEGER,     0),
      'penalty_deduction_days', COALESCE((v_summary->>'penalty_deduction_days')::NUMERIC, 0),
      'total_overtime_minutes', COALESCE((v_summary->>'total_overtime_minutes')::INTEGER, 0)
    ),
    'advances',         COALESCE(v_advances, '[]'::jsonb),
    'is_partial_month', (v_emp.hire_date >= make_date(v_year, v_month, 1)),
    'note',             'هذا الكشف تقديري وليس نهائياً — يُعتد بالمسير الرسمي عند الاعتماد'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_employee_live_statement(UUID, INTEGER, INTEGER) TO authenticated;
