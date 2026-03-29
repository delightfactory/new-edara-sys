-- ============================================================
-- Migration 20e: إصلاح توليد أقساط السلفة الفورية
-- المشكلة: السلفة الفورية (instant) تُولّد قسطاً واحداً في الشهر القادم
-- بدلاً من الشهر الحالي، مما يمنع خصمها من المسير الجاري.
-- الحل: بدء الأقساط من الشهر الحالي (i=0) للسلف الفورية.
-- ============================================================

CREATE OR REPLACE FUNCTION handle_advance_approval()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_period_id    UUID;
  v_period_year  INTEGER;
  v_period_month INTEGER;
  i              INTEGER;
  v_start_offset INTEGER;  -- ★ 0 للفورية (الشهر الحالي)، 1 للمجدولة (الشهر القادم)
BEGIN
  -- عند الانتقال إلى approved (من pending_finance)
  IF NEW.status = 'approved' AND OLD.status <> 'approved' THEN
    v_period_year  := EXTRACT(YEAR  FROM CURRENT_DATE)::INTEGER;
    v_period_month := EXTRACT(MONTH FROM CURRENT_DATE)::INTEGER;

    -- ★ السلفة الفورية: القسط يبدأ من الشهر الحالي
    -- السلفة المجدولة: الأقساط تبدأ من الشهر القادم
    v_start_offset := CASE WHEN NEW.advance_type = 'instant' THEN 0 ELSE 1 END;

    FOR i IN 1 .. NEW.installments_count LOOP
      DECLARE
        v_inst_year  INTEGER;
        v_inst_month INTEGER;
        v_offset     INTEGER := (i - 1) + v_start_offset;  -- ★ instant: 0,1,2.. / scheduled: 1,2,3..
      BEGIN
        v_inst_month := ((v_period_month - 1 + v_offset) % 12) + 1;
        v_inst_year  := v_period_year + ((v_period_month - 1 + v_offset) / 12);

        -- جلب أو إنشاء الفترة
        INSERT INTO hr_payroll_periods (year, month, name, start_date, end_date)
        VALUES (
          v_inst_year, v_inst_month,
          to_char(make_date(v_inst_year, v_inst_month, 1), 'Month YYYY'),
          make_date(v_inst_year, v_inst_month, 1),
          (make_date(v_inst_year, v_inst_month, 1) + INTERVAL '1 month - 1 day')::DATE
        ) ON CONFLICT (year, month) DO NOTHING;

        SELECT id INTO v_period_id
        FROM hr_payroll_periods WHERE year = v_inst_year AND month = v_inst_month;

        INSERT INTO hr_advance_installments (
          advance_id, installment_number, period_id,
          due_year, due_month, amount, status
        ) VALUES (
          NEW.id, i, v_period_id,
          v_inst_year, v_inst_month,
          COALESCE(NEW.monthly_installment, ROUND(NEW.amount / NEW.installments_count, 2)),
          'pending'
        );
      END;
    END LOOP;
  END IF;

  RETURN NEW;
END; $$;

-- ★ إصلاح السلف الفورية الموجودة: نقل أقساطها للشهر الحالي
-- (إذا كانت مُنشأة هذا الشهر وقسطها الوحيد في الشهر القادم)
UPDATE hr_advance_installments ai
SET
  due_month = EXTRACT(MONTH FROM CURRENT_DATE)::INTEGER,
  due_year  = EXTRACT(YEAR  FROM CURRENT_DATE)::INTEGER,
  period_id = (
    SELECT p.id FROM hr_payroll_periods p
    WHERE p.year = EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER
      AND p.month = EXTRACT(MONTH FROM CURRENT_DATE)::INTEGER
    LIMIT 1
  )
FROM hr_advances adv
WHERE adv.id = ai.advance_id
  AND adv.advance_type = 'instant'
  AND adv.status IN ('approved', 'paid')
  AND ai.installment_number = 1
  AND ai.status = 'pending'
  -- فقط الأقساط التي تقع في الشهر القادم عن طريق الخطأ
  AND (
    (ai.due_year = EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER AND ai.due_month = EXTRACT(MONTH FROM CURRENT_DATE)::INTEGER + 1)
    OR (EXTRACT(MONTH FROM CURRENT_DATE)::INTEGER = 12 AND ai.due_year = EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER + 1 AND ai.due_month = 1)
  );
