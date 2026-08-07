-- Synthetic rehearsal-only reference data.
-- Deliberately contains no production/company rows or identifiers.

INSERT INTO public.company_settings (key, value, type, category, is_public)
VALUES
  ('hr.work_hours_per_day', '8', 'number', 'hr', false),
  ('hr.work_start_time', '09:00', 'text', 'hr', false),
  ('hr.work_end_time', '17:00', 'text', 'hr', false),
  ('hr.late_grace_minutes', '15', 'number', 'hr', false),
  ('hr.auto_checkout_minutes', '15', 'number', 'hr', false),
  ('hr.absence_run_delay_minutes', '120', 'number', 'hr', false),
  ('hr.weekly_off_day', 'friday', 'text', 'hr', false),
  ('hr.default_gps_accuracy_threshold_meters', '100', 'number', 'hr', false),
  ('hr.field_attendance_max_distance_meters', '50000', 'number', 'hr', false)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

INSERT INTO public.hr_leave_types (
  id, name, name_en, code,
  max_days_per_year, max_days_per_request,
  is_paid, has_balance, deducts_from_balance,
  requires_approval, approval_levels,
  requires_document, can_carry_forward, affects_salary,
  is_system, is_active, eligible_gender
) VALUES (
  '00000000-0000-4000-8000-000000000101'::uuid,
  'إجازة اختبار معزولة',
  'Isolated rehearsal leave',
  'V2_TEST_LEAVE',
  30, 30,
  true, true, true,
  true, 2,
  false, false, false,
  false, true, 'all'
)
ON CONFLICT (code) DO NOTHING;
