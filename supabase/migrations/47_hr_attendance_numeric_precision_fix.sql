-- ═══════════════════════════════════════════════════════════════
-- 47_hr_attendance_numeric_precision_fix.sql
-- HR Attendance: fix numeric overflow for full-day values
--
-- السبب:
--   NUMERIC(4,4) لا يستوعب 1.0 لأن الجزء الصحيح المسموح به = 0 فقط.
--   هذا كان يسبب overflow عند:
--     1) day_value = 1.0
--     2) deduction_days = 1.0 بعد إعادة تشغيل process_attendance_penalties
--        أثناء تسجيل الانصراف.
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE hr_attendance_days
  ALTER COLUMN day_value TYPE NUMERIC(5,4)
  USING day_value::NUMERIC(5,4);

ALTER TABLE hr_attendance_days
  ALTER COLUMN day_value SET DEFAULT 1.0;

ALTER TABLE hr_penalty_instances
  ALTER COLUMN deduction_days TYPE NUMERIC(5,4)
  USING deduction_days::NUMERIC(5,4);

ALTER TABLE hr_penalty_instances
  ALTER COLUMN deduction_days SET DEFAULT 0.0;

COMMENT ON COLUMN hr_attendance_days.day_value IS
'قيمة اليوم: 1.0 = يوم كامل، 0.5 = نصف يوم، 0 = غياب. النوع NUMERIC(5,4) لتفادي overflow عند 1.0.';

COMMENT ON COLUMN hr_penalty_instances.deduction_days IS
'خصم بالأيام من الجزاءات: 0.25 / 0.5 / 1.0. النوع NUMERIC(5,4) لتفادي overflow عند full_day.';
