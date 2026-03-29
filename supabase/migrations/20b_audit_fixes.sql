-- =============================================================
-- Migration 20b: Audit Fixes â€” Ø¥ØµÙ„Ø§Ø­Ø§Øª Ø§Ù„ØªØ¯Ù‚ÙŠÙ‚ Ø§Ù„Ù†Ù‡Ø§Ø¦ÙŠ
-- EDARA v2
--
-- Ù‡Ø°Ø§ Ø§Ù„Ù…Ù„Ù ÙŠÙØ·Ø¨ÙÙ‘Ù‚ Ø¬Ù…ÙŠØ¹ Ø¥ØµÙ„Ø§Ø­Ø§Øª Ø§Ù„ØªØ¯Ù‚ÙŠÙ‚ ÙÙŠ Ù…ÙƒØ§Ù† ÙˆØ§Ø­Ø¯:
--
-- DDL CHANGES:
--   â€¢ ALTER TABLE hr_payroll_lines ADD updated_at (ÙƒØ§Ù† Ù…ÙÙ‚ÙˆØ¯Ø§Ù‹)
--
-- FUNCTION PATCHES (CREATE OR REPLACE â€” Ø¢Ù…Ù† Ø¹Ù„Ù‰ DB Ù…ÙˆØ¬ÙˆØ¯Ø©):
--   â€¢ FIX-AUDIT-01: record_attendance_gps â€” Ø¥Ø¶Ø§ÙØ© Â±24h timestamp validation
--   â€¢ FIX-AUDIT-02: record_attendance_gps â€” Ø¥Ø¶Ø§ÙØ© hr_permission_requests check
--   â€¢ FIX-AUDIT-04: create_auto_journal_entry â€” Ø¥Ø¶Ø§ÙØ© p_amount > 0 guard
--
-- NEW FUNCTIONS:
--   â€¢ FIX-AUDIT-06: update_payroll_line_adjustments â€” Ø¥Ø¹Ø§Ø¯Ø© Ø­Ø³Ø§Ø¨ net_salary
--   â€¢ FIX-AUDIT-07: upsert_attendance_and_reprocess â€” Ø¥Ø¹Ø§Ø¯Ø© ØªØ´ØºÙŠÙ„ Ø§Ù„Ø¬Ø²Ø§Ø¡Ø§Øª
-- =============================================================


-- â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—
-- â•‘  DDL: Ø¥Ø¶Ø§ÙØ© Ø¹Ù…ÙˆØ¯ updated_at ÙÙŠ hr_payroll_lines          â•‘
-- â•‘  (Ø§Ù„Ø¬Ø¯ÙˆÙ„ ÙƒØ§Ù† ÙŠØ­ØªÙˆÙŠ ÙÙ‚Ø· Ø¹Ù„Ù‰ created_at)                   â•‘
-- â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

ALTER TABLE hr_payroll_lines
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- trigger Ù„ØªØ­Ø¯ÙŠØ« updated_at ØªÙ„Ù‚Ø§Ø¦ÙŠØ§Ù‹
DROP TRIGGER IF EXISTS trg_payroll_lines_updated_at ON hr_payroll_lines;
CREATE TRIGGER trg_payroll_lines_updated_at
  BEFORE UPDATE ON hr_payroll_lines
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—
-- â•‘  FIX-AUDIT-04: create_auto_journal_entry                 â•‘
-- â•‘  Ø¥Ø¶Ø§ÙØ© ÙØ­Øµ p_amount > 0 Ù„Ù…Ù†Ø¹ Ø§Ù„Ù‚ÙŠÙˆØ¯ Ø§Ù„ØµÙØ±ÙŠØ©/Ø§Ù„Ø³Ø§Ù„Ø¨Ø©    â•‘
-- â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

CREATE OR REPLACE FUNCTION create_auto_journal_entry(
  p_source_type   TEXT,
  p_source_id     UUID,
  p_description   TEXT,
  p_debit_account TEXT,     -- ÙƒÙˆØ¯ Ø§Ù„Ø­Ø³Ø§Ø¨ Ø§Ù„Ù…Ø¯ÙŠÙ†
  p_credit_account TEXT,    -- ÙƒÙˆØ¯ Ø§Ù„Ø­Ø³Ø§Ø¨ Ø§Ù„Ø¯Ø§Ø¦Ù†
  p_amount        NUMERIC,
  p_user_id       UUID
) RETURNS UUID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_entry_id    UUID;
  v_debit_acct  UUID;
  v_credit_acct UUID;
BEGIN
  -- FIX-AUDIT-04: Ø±ÙØ¶ Ù…Ø¨Ø§Ù„Øº ØµÙØ±ÙŠØ© Ø£Ùˆ Ø³Ø§Ù„Ø¨Ø©
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'create_auto_journal_entry: Ø§Ù„Ù…Ø¨Ù„Øº ÙŠØ¬Ø¨ Ø£Ù† ÙŠÙƒÙˆÙ† Ø£ÙƒØ¨Ø± Ù…Ù† ØµÙØ± (Ø§Ù„Ù‚ÙŠÙ…Ø©: %)', COALESCE(p_amount, 0);
  END IF;

  -- Ø¬Ù„Ø¨ Ù…Ø¹Ø±Ù‘ÙØ§Øª Ø§Ù„Ø­Ø³Ø§Ø¨Ø§Øª Ù…Ù† Ø§Ù„Ø£ÙƒÙˆØ§Ø¯
  SELECT id INTO v_debit_acct FROM chart_of_accounts WHERE code = p_debit_account;
  IF v_debit_acct IS NULL THEN
    RAISE EXCEPTION 'Ø­Ø³Ø§Ø¨ Ù…Ø¯ÙŠÙ† ØºÙŠØ± Ù…ÙˆØ¬ÙˆØ¯: %', p_debit_account;
  END IF;

  SELECT id INTO v_credit_acct FROM chart_of_accounts WHERE code = p_credit_account;
  IF v_credit_acct IS NULL THEN
    RAISE EXCEPTION 'Ø­Ø³Ø§Ø¨ Ø¯Ø§Ø¦Ù† ØºÙŠØ± Ù…ÙˆØ¬ÙˆØ¯: %', p_credit_account;
  END IF;

  -- Ø¥Ù†Ø´Ø§Ø¡ Ø§Ù„Ù‚ÙŠØ¯ (total_debit = total_credit â†’ ÙŠÙ…Ø± Ù…Ù† CHECK constraint)
  INSERT INTO journal_entries (
    source_type, source_id, description, is_auto,
    total_debit, total_credit, created_by
  ) VALUES (
    p_source_type, p_source_id, p_description, true,
    p_amount, p_amount, p_user_id
  )
  RETURNING id INTO v_entry_id;

  -- Ø¥Ø¯Ø±Ø§Ø¬ Ø§Ù„Ø³Ø·Ø± Ø§Ù„Ù…Ø¯ÙŠÙ†
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
  VALUES (v_entry_id, v_debit_acct, p_amount, 0, p_description);

  -- Ø¥Ø¯Ø±Ø§Ø¬ Ø§Ù„Ø³Ø·Ø± Ø§Ù„Ø¯Ø§Ø¦Ù†
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
  VALUES (v_entry_id, v_credit_acct, 0, p_amount, p_description);

  RETURN v_entry_id;
END; $$;


-- â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—
-- â•‘  FIX-AUDIT-01 + FIX-AUDIT-02: record_attendance_gps      â•‘
-- â•‘  â‘  Ø¥Ø¶Ø§ÙØ© Â±24h timestamp validation                       â•‘
-- â•‘  â‘¡ Ø¥Ø¶Ø§ÙØ© hr_permission_requests ÙÙŠ ÙØ­Øµ Ø§Ù„Ø§Ù†ØµØ±Ø§Ù Ø§Ù„Ù…Ø¨ÙƒØ±   â•‘
-- â•‘                                                           â•‘
-- â•‘  âš  Ù‡Ø°Ù‡ Ù†Ø³Ø®Ø© ÙƒØ§Ù…Ù„Ø© Ù…Ù† Ø§Ù„Ø¯Ø§Ù„Ø© â€” ÙƒÙ„ Ø§Ù„Ø³Ø·Ø± Ø§Ù„Ø£ØµÙ„ÙŠ + Ø§Ù„ØªØ¹Ø¯ÙŠÙ„  â•‘
-- â•‘    Ø§Ù„ØªÙˆÙ‚ÙŠØ¹ Ù…Ø·Ø§Ø¨Ù‚ 100% Ù„Ù„Ø£ØµÙ„ÙŠ                              â•‘
-- â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

CREATE OR REPLACE FUNCTION record_attendance_gps(
  p_latitude      NUMERIC,
  p_longitude     NUMERIC,
  p_gps_accuracy  NUMERIC,
  p_log_type      TEXT,         -- 'check_in' | 'check_out'
  p_event_time    TIMESTAMPTZ DEFAULT NULL
) RETURNS JSONB
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  -- â”€â”€â”€ Ù‡ÙˆÙŠØ© Ø§Ù„Ù…ÙˆØ¸Ù â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  v_employee_id     UUID;
  v_is_field        BOOLEAN;

  -- â”€â”€â”€ ÙˆÙ‚Øª ÙˆÙ…ÙƒØ§Ù† â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  v_event_time      TIMESTAMPTZ;
  v_shift_date      DATE;

  -- â”€â”€â”€ Ø¥Ø¹Ø¯Ø§Ø¯Ø§Øª â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  v_gps_required    BOOLEAN;
  v_threshold       INTEGER;
  v_work_start      TIME;
  v_work_end        TIME;

  -- â”€â”€â”€ Ø¯Ù‚Ø© GPS Ø§Ù„Ø¢Ù…Ù†Ø© â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  v_gps_safe        NUMERIC(8,2);

  -- â”€â”€â”€ Ø§Ù„Ù…ÙˆÙ‚Ø¹ â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  v_location_id     UUID;
  v_location_name   TEXT;
  v_loc_row         hr_work_locations%ROWTYPE;
  v_distance        NUMERIC;

  -- â”€â”€â”€ Ø§Ù„ÙŠÙˆÙ… â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  v_existing_day    hr_attendance_days%ROWTYPE;
  v_day_id          UUID;
  v_log_id          UUID;

  -- â”€â”€â”€ Ø­Ø³Ø§Ø¨ Ø§Ù„Ø­Ø¶ÙˆØ± â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  v_att_status      hr_attendance_status;
  v_late_min        INTEGER;
  v_scheduled_start TIMESTAMPTZ;

  -- â”€â”€â”€ FIX-01: ÙØªØ±Ø© Ø§Ù„Ø³Ù…Ø§Ø­ Ø¨Ø§Ù„ØªØ£Ø®ÙŠØ± (Ù…Ù† Ø§Ù„Ø¥Ø¹Ø¯Ø§Ø¯Ø§Øª) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  v_grace_min       INTEGER;

  -- â”€â”€â”€ Ø­Ø³Ø§Ø¨ Ø§Ù„Ø§Ù†ØµØ±Ø§Ù â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  v_check_in_ts     TIMESTAMPTZ;
  v_eff_hours       NUMERIC;
  v_ot_min          INTEGER;
  v_early_min       INTEGER;
  v_sched_end       TIMESTAMPTZ;
  v_co_status       hr_checkout_status;

BEGIN

  -- â”€â”€â”€ 0. Ø§Ù„ØªØ­Ù‚Ù‚ Ù…Ù† ØµØ­Ø© p_log_type â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  IF p_log_type NOT IN ('check_in', 'check_out') THEN
    RETURN jsonb_build_object(
      'success', false,
      'code',    'INVALID_LOG_TYPE',
      'error',   format('Ù†ÙˆØ¹ Ø§Ù„Ø³Ø¬Ù„ ØºÙŠØ± ØµØ­ÙŠØ­: %s. Ø§Ù„Ù…Ù‚Ø¨ÙˆÙ„: check_in Ø£Ùˆ check_out', p_log_type)
    );
  END IF;

  -- â”€â”€â”€ 0b. ØªØ£Ù…ÙŠÙ† Ø¯Ù‚Ø© GPS Ù…Ù† Overflow â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  v_gps_safe := LEAST(COALESCE(ROUND(p_gps_accuracy::NUMERIC, 2), 0), 999999.99);

  -- â”€â”€â”€ 1. Ø§Ù„ØªØ­Ù‚Ù‚ Ù…Ù† Ù‡ÙˆÙŠØ© Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù… â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  SELECT id, is_field_employee
  INTO   v_employee_id, v_is_field
  FROM   hr_employees
  WHERE  user_id = auth.uid()
    AND  status  = 'active';

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'code',    'NO_EMPLOYEE',
      'error',   'Ø­Ø³Ø§Ø¨Ùƒ ØºÙŠØ± Ù…Ø±ØªØ¨Ø· Ø¨Ù…ÙˆØ¸Ù Ù†Ø´Ø·'
    );
  END IF;

  -- â”€â”€â”€ 2. ÙˆÙ‚Øª Ø§Ù„Ø­Ø¯Ø« ÙˆØ§Ù„ØªØ§Ø±ÙŠØ® â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  v_event_time := COALESCE(p_event_time, now());

  -- FIX-AUDIT-01: Ø±ÙØ¶ Ø£ÙˆÙ‚Ø§Øª Ù…Ø³ØªÙ‚Ø¨Ù„ÙŠØ© Ø£Ùˆ Ø£Ù‚Ø¯Ù… Ù…Ù† 24 Ø³Ø§Ø¹Ø©
  -- ÙŠÙ…Ù†Ø¹ Ø§Ù„ØªÙ„Ø§Ø¹Ø¨ Ø¨Ø§Ù„Ø­Ø¶ÙˆØ± Ø¹Ø¨Ø± Ø¥Ø±Ø³Ø§Ù„ p_event_time Ù…Ø²ÙˆÙ‘Ø±
  IF v_event_time > now() + INTERVAL '5 minutes' THEN
    RETURN jsonb_build_object(
      'success', false,
      'code',    'FUTURE_TIME',
      'error',   'Ù„Ø§ ÙŠÙ…ÙƒÙ† ØªØ³Ø¬ÙŠÙ„ Ø­Ø¶ÙˆØ± ÙÙŠ Ø§Ù„Ù…Ø³ØªÙ‚Ø¨Ù„'
    );
  END IF;
  IF v_event_time < now() - INTERVAL '24 hours' THEN
    RETURN jsonb_build_object(
      'success', false,
      'code',    'TOO_OLD',
      'error',   'Ù„Ø§ ÙŠÙ…ÙƒÙ† ØªØ³Ø¬ÙŠÙ„ Ø­Ø¶ÙˆØ± Ø£Ù‚Ø¯Ù… Ù…Ù† 24 Ø³Ø§Ø¹Ø©'
    );
  END IF;

  v_shift_date := (v_event_time AT TIME ZONE 'Africa/Cairo')::DATE;

  -- â”€â”€â”€ 3. Ù‡Ù„ Ø§Ù„ØªØ­Ù‚Ù‚ Ù…Ù† GPS Ø¥Ù„Ø²Ø§Ù…ÙŠØŸ â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  SELECT COALESCE(
    (SELECT lower(value) = 'true'
     FROM   company_settings
     WHERE  key = 'hr.attendance_gps_required'),
    false
  ) INTO v_gps_required;

  -- â”€â”€â”€ 4. Ø§Ù„ØªØ­Ù‚Ù‚ Ù…Ù† Ø¯Ù‚Ø© GPS (Ø¥Ø°Ø§ ÙƒØ§Ù† Ø¥Ù„Ø²Ø§Ù…ÙŠØ§Ù‹) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  IF v_gps_required THEN
    SELECT COALESCE(
      (SELECT gps_accuracy_threshold
       FROM   hr_work_locations
       WHERE  is_active = true
       ORDER  BY id
       LIMIT  1),
      150
    ) INTO v_threshold;

    IF p_gps_accuracy IS NOT NULL AND p_gps_accuracy > v_threshold THEN
      RETURN jsonb_build_object(
        'success', false,
        'code',    'LOW_GPS_ACCURACY',
        'error',   format('Ø¯Ù‚Ø© GPS Ù…Ù†Ø®ÙØ¶Ø© (%sÙ…). Ø§Ù„Ø­Ø¯ Ø§Ù„Ù…Ø³Ù…ÙˆØ­: %sÙ…',
                          p_gps_accuracy::int, v_threshold)
      );
    END IF;
  END IF;

  -- â”€â”€â”€ 5. Ø§Ù„ØªØ­Ù‚Ù‚ Ù…Ù† Ø§Ù„Ù…ÙˆÙ‚Ø¹ Ø§Ù„Ø¬ØºØ±Ø§ÙÙŠ â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  IF v_is_field THEN
    SELECT id, name
    INTO   v_location_id, v_location_name
    FROM   hr_work_locations
    WHERE  is_active = true
    ORDER  BY (
      6371000 * acos(LEAST(1.0,
        cos(radians(latitude)) * cos(radians(p_latitude))
        * cos(radians(p_longitude) - radians(longitude))
        + sin(radians(latitude)) * sin(radians(p_latitude))
      ))
    ) ASC
    LIMIT 1;

  ELSIF v_gps_required THEN
    SELECT *
    INTO   v_loc_row
    FROM   hr_work_locations
    WHERE  is_active = true
    ORDER  BY (
      6371000 * acos(LEAST(1.0,
        cos(radians(latitude)) * cos(radians(p_latitude))
        * cos(radians(p_longitude) - radians(longitude))
        + sin(radians(latitude)) * sin(radians(p_latitude))
      ))
    ) ASC
    LIMIT 1;

    IF NOT FOUND THEN
      RETURN jsonb_build_object(
        'success', false,
        'code',    'NO_LOCATION_FOUND',
        'error',   'Ù„Ø§ ØªÙˆØ¬Ø¯ Ù…ÙˆØ§Ù‚Ø¹ Ø¹Ù…Ù„ Ù†Ø´Ø·Ø© ÙÙŠ Ø§Ù„Ù†Ø¸Ø§Ù…'
      );
    END IF;

    v_distance := 6371000 * acos(LEAST(1.0,
      cos(radians(v_loc_row.latitude)) * cos(radians(p_latitude))
      * cos(radians(p_longitude) - radians(v_loc_row.longitude))
      + sin(radians(v_loc_row.latitude)) * sin(radians(p_latitude))
    ));

    IF v_distance > v_loc_row.radius_meters THEN
      RETURN jsonb_build_object(
        'success',          false,
        'code',             'OUT_OF_RANGE',
        'error',            format('Ø£Ù†Øª Ø®Ø§Ø±Ø¬ Ø§Ù„Ù†Ø·Ø§Ù‚. Ø§Ù„Ù…Ø³Ø§ÙØ©: %sÙ…ØŒ Ø§Ù„Ø­Ø¯ Ø§Ù„Ù…Ø³Ù…ÙˆØ­: %sÙ…',
                                   round(v_distance), v_loc_row.radius_meters),
        'nearest_location', v_loc_row.name,
        'distance_meters',  round(v_distance)
      );
    END IF;

    v_location_id   := v_loc_row.id;
    v_location_name := v_loc_row.name;

  ELSE
    SELECT id, name
    INTO   v_location_id, v_location_name
    FROM   hr_work_locations
    WHERE  is_active = true
    ORDER  BY (
      6371000 * acos(LEAST(1.0,
        cos(radians(latitude)) * cos(radians(p_latitude))
        * cos(radians(p_longitude) - radians(longitude))
        + sin(radians(latitude)) * sin(radians(p_latitude))
      ))
    ) ASC
    LIMIT 1;
  END IF;

  -- â”€â”€â”€ 6. Ø§Ù„ØªØ­Ù‚Ù‚ Ù…Ù† Ù…Ù†Ø·Ù‚ Ø§Ù„Ø­Ø¶ÙˆØ±/Ø§Ù„Ø§Ù†ØµØ±Ø§Ù â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  SELECT *
  INTO   v_existing_day
  FROM   hr_attendance_days
  WHERE  employee_id = v_employee_id
    AND  shift_date  = v_shift_date;

  IF p_log_type = 'check_in' THEN
    IF FOUND AND v_existing_day.punch_in_time IS NOT NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'code',    'ALREADY_CHECKED_IN',
        'error',   'Ù„Ù‚Ø¯ Ø³Ø¬Ù„Øª Ø­Ø¶ÙˆØ±Ùƒ Ø¨Ø§Ù„ÙØ¹Ù„ Ø§Ù„ÙŠÙˆÙ…'
      );
    END IF;

  ELSE -- check_out
    IF NOT FOUND OR v_existing_day.punch_in_time IS NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'code',    'NOT_CHECKED_IN',
        'error',   'ÙŠØ¬Ø¨ ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø­Ø¶ÙˆØ± Ø£ÙˆÙ„Ø§Ù‹ Ù‚Ø¨Ù„ ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø§Ù†ØµØ±Ø§Ù'
      );
    END IF;
    IF v_existing_day.punch_out_time IS NOT NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'code',    'ALREADY_CHECKED_OUT',
        'error',   'Ù„Ù‚Ø¯ Ø³Ø¬Ù„Øª Ø§Ù†ØµØ±Ø§ÙÙƒ Ø¨Ø§Ù„ÙØ¹Ù„ Ø§Ù„ÙŠÙˆÙ…'
      );
    END IF;
  END IF;

  -- â”€â”€â”€ 7. check_in: Ø­Ø³Ø§Ø¨ Ø§Ù„ØªØ£Ø®ÙŠØ± ÙˆØ§Ù„Ø­Ø§Ù„Ø© â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  v_late_min   := 0;
  v_att_status := 'present';

  IF p_log_type = 'check_in' THEN
    -- FIX-01: Ù‚Ø±Ø§Ø¡Ø© ÙØªØ±Ø© Ø§Ù„Ø³Ù…Ø§Ø­ Ø¨Ø§Ù„ØªØ£Ø®ÙŠØ± Ù…Ù† Ø¥Ø¹Ø¯Ø§Ø¯Ø§Øª HR
    SELECT COALESCE(value::INTEGER, 15)
    INTO   v_grace_min
    FROM   company_settings
    WHERE  key = 'hr.late_grace_minutes';
    IF v_grace_min IS NULL THEN v_grace_min := 15; END IF;

    SELECT value::TIME
    INTO   v_work_start
    FROM   company_settings
    WHERE  key = 'hr.work_start_time';

    IF v_work_start IS NOT NULL THEN
      v_scheduled_start := (v_shift_date + v_work_start) AT TIME ZONE 'Africa/Cairo';

      IF v_event_time > v_scheduled_start + (v_grace_min || ' minutes')::INTERVAL THEN
        v_late_min   := EXTRACT(EPOCH FROM (v_event_time - v_scheduled_start))::INTEGER / 60;
        v_att_status := CASE
          WHEN v_late_min > 120 THEN 'half_day'::hr_attendance_status
          ELSE                       'late'::hr_attendance_status
        END;
      END IF;
    END IF;

    -- â”€â”€â”€ UPSERT hr_attendance_days (check_in) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    INSERT INTO hr_attendance_days (
      employee_id,    shift_date,      work_date,
      punch_in_time,  location_in_id,  gps_accuracy_in,
      status,         late_minutes,    day_value
    ) VALUES (
      v_employee_id,  v_shift_date,    v_shift_date,
      v_event_time,   v_location_id,   v_gps_safe,
      v_att_status,   v_late_min,
      CASE v_att_status
        WHEN 'half_day' THEN 0.5
        WHEN 'present'  THEN 1.0
        WHEN 'late'     THEN 1.0
        ELSE                 1.0
      END
    )
    ON CONFLICT (employee_id, shift_date) DO UPDATE SET
      punch_in_time   = EXCLUDED.punch_in_time,
      location_in_id  = EXCLUDED.location_in_id,
      gps_accuracy_in = EXCLUDED.gps_accuracy_in,
      status          = EXCLUDED.status,
      late_minutes    = EXCLUDED.late_minutes,
      day_value       = EXCLUDED.day_value,
      updated_at      = now()
    RETURNING id INTO v_day_id;

  ELSE
    -- â”€â”€â”€ 8. check_out: Ø­Ø³Ø§Ø¨ Ø³Ø§Ø¹Ø§Øª Ø§Ù„Ø¹Ù…Ù„ ÙˆØ§Ù„Ø£ÙˆÙØ±ØªØ§ÙŠÙ… â”€â”€â”€â”€â”€â”€â”€â”€â”€
    v_check_in_ts := v_existing_day.punch_in_time;
    v_eff_hours   := LEAST(
      ROUND(EXTRACT(EPOCH FROM (v_event_time - v_check_in_ts)) / 3600.0, 2),
      24.00
    );
    v_ot_min      := 0;
    v_early_min   := 0;
    v_co_status   := 'on_time';

    SELECT value::TIME
    INTO   v_work_end
    FROM   company_settings
    WHERE  key = 'hr.work_end_time';

    IF v_work_end IS NOT NULL THEN
      v_sched_end := (v_shift_date + v_work_end) AT TIME ZONE 'Africa/Cairo';

      IF v_event_time > v_sched_end + INTERVAL '30 minutes' THEN
        -- Ø£ÙˆÙØ±ØªØ§ÙŠÙ…
        v_ot_min    := EXTRACT(EPOCH FROM (v_event_time - v_sched_end))::INTEGER / 60;
        v_co_status := 'overtime';
      ELSIF v_event_time < v_sched_end - INTERVAL '5 minutes' THEN
        -- Ø§Ù†ØµØ±Ø§Ù Ù…Ø¨ÙƒØ±
        v_early_min := EXTRACT(EPOCH FROM (v_sched_end - v_event_time))::INTEGER / 60;
        -- FIX-12 + FIX-AUDIT-02: Ø§Ù„ØªØ­Ù‚Ù‚ Ù…Ù† Ø¥Ø¬Ø§Ø²Ø© Ø£Ùˆ Ø¥Ø°Ù† Ø§Ù†ØµØ±Ø§Ù Ù…Ø¨ÙƒØ±
        -- ÙŠØ´Ù…Ù„: Ø¥Ø¬Ø§Ø²Ø© Ù†ØµÙ ÙŠÙˆÙ… (hr_leave_requests) + Ø¥Ø°Ù† Ø±Ø³Ù…ÙŠ (hr_permission_requests)
        IF EXISTS (
          SELECT 1 FROM hr_leave_requests
          WHERE employee_id = v_employee_id
            AND start_date  <= v_shift_date
            AND end_date    >= v_shift_date
            AND status      = 'approved'
        ) OR EXISTS (
          SELECT 1 FROM hr_permission_requests
          WHERE employee_id = v_employee_id
            AND permission_date = v_shift_date
            AND status = 'approved'
        ) THEN
          v_co_status := 'early_authorized';
        ELSE
          v_co_status := 'early_unauthorized';
        END IF;
      END IF;
    END IF;

    -- â”€â”€â”€ UPDATE hr_attendance_days (check_out) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    UPDATE hr_attendance_days SET
      punch_out_time      = v_event_time,
      location_out_id     = v_location_id,
      gps_accuracy_out    = v_gps_safe,
      effective_hours     = v_eff_hours,
      overtime_minutes    = v_ot_min,
      early_leave_minutes = v_early_min,
      checkout_status     = v_co_status,
      day_value           = CASE (SELECT status FROM hr_attendance_days
                                  WHERE employee_id = v_employee_id AND shift_date = v_shift_date)
                              WHEN 'half_day' THEN 0.5
                              ELSE                 1.0
                            END,
      updated_at          = now()
    WHERE  employee_id = v_employee_id
      AND  shift_date  = v_shift_date
    RETURNING id INTO v_day_id;

  END IF;

  -- â”€â”€â”€ 9. Ø¥Ø¯Ø±Ø§Ø¬ Ø³Ø¬Ù„ GPS ÙÙŠ hr_attendance_logs â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  INSERT INTO hr_attendance_logs (
    employee_id,     attendance_day_id,
    log_type,        latitude,         longitude,
    gps_accuracy,    location_id,
    is_offline_sync, event_time
  ) VALUES (
    v_employee_id,   v_day_id,
    p_log_type,      p_latitude,       p_longitude,
    v_gps_safe,      v_location_id,
    false,           v_event_time
  )
  RETURNING id INTO v_log_id;

  -- â”€â”€â”€ 10. Ø¥Ø±Ø¬Ø§Ø¹ Ø§Ù„Ù†ØªÙŠØ¬Ø© â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  RETURN jsonb_build_object(
    'success',           true,
    'action',            p_log_type,
    'attendance_day_id', v_day_id,
    'log_id',            v_log_id,
    'location_name',     v_location_name,
    'location_id',       v_location_id,
    'shift_date',        v_shift_date,
    'event_time',        v_event_time
  );

EXCEPTION

  WHEN numeric_value_out_of_range THEN
    RETURN jsonb_build_object(
      'success',      false,
      'code',         'NUMERIC_OVERFLOW',
      'error',        SQLERRM,
      '_debug', jsonb_build_object(
        'gps_raw',        COALESCE(p_gps_accuracy::TEXT, 'null'),
        'gps_safe',       COALESCE(v_gps_safe::TEXT,     'null'),
        'latitude',       COALESCE(p_latitude::TEXT,     'null'),
        'longitude',      COALESCE(p_longitude::TEXT,    'null'),
        'late_min',       COALESCE(v_late_min::TEXT,     'null'),
        'day_created',    CASE WHEN v_day_id IS NOT NULL THEN 'YES' ELSE 'NO - failed in days INSERT' END,
        'log_created',    CASE WHEN v_log_id IS NOT NULL THEN 'YES' ELSE 'NO - failed in logs INSERT' END,
        'eff_hours_raw',  COALESCE(v_eff_hours::TEXT,    'null')
      )
    );

  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'code',    'INTERNAL_ERROR',
      'error',   SQLERRM
    );

END; $$;


-- â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—
-- â•‘  FIX-AUDIT-06: update_payroll_line_adjustments           â•‘
-- â•‘                                                           â•‘
-- â•‘  Ø§Ù„Ù…Ø´ÙƒÙ„Ø©: updatePayrollLine ÙÙŠ Ø§Ù„Ù€ Frontend ÙŠÙØ­Ø¯Ù‘Ø«        â•‘
-- â•‘  bonus_amount / other_deductions / override_net ÙÙ‚Ø·       â•‘
-- â•‘  Ø¨Ø¯ÙˆÙ† Ø¥Ø¹Ø§Ø¯Ø© Ø­Ø³Ø§Ø¨ net_salary.                              â•‘
-- â•‘  â†’ approve_payroll_run ÙŠÙ‚Ø±Ø£ net_salary Ø§Ù„Ù‚Ø¯ÙŠÙ…             â•‘
-- â•‘  â†’ Ø§Ù„Ù‚ÙŠØ¯ Ø§Ù„Ù…Ø­Ø§Ø³Ø¨ÙŠ Ù„Ø§ ÙŠØ¹ÙƒØ³ Ø§Ù„Ù…ÙƒØ§ÙØ¢Øª/Ø§Ù„Ø®ØµÙˆÙ…Ø§Øª Ø§Ù„Ø¥Ø¶Ø§ÙÙŠØ©    â•‘
-- â•‘                                                           â•‘
-- â•‘  Ø§Ù„Ø¥ØµÙ„Ø§Ø­: RPC Ø°Ø±ÙŠ ÙŠÙØ¹ÙŠØ¯ Ø­Ø³Ø§Ø¨ net_salary ØªÙ„Ù‚Ø§Ø¦ÙŠØ§Ù‹        â•‘
-- â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

CREATE OR REPLACE FUNCTION update_payroll_line_adjustments(
  p_line_id          UUID,
  p_bonus_amount     NUMERIC DEFAULT NULL,   -- NULL = Ù„Ø§ ØªØºÙŠÙŠØ±
  p_other_deductions NUMERIC DEFAULT NULL,   -- NULL = Ù„Ø§ ØªØºÙŠÙŠØ±
  p_override_net     NUMERIC DEFAULT NULL,   -- NULL = Ù„Ø§ ØªØºÙŠÙŠØ± (Ø§Ø³ØªØ®Ø¯Ù… 0 Ù„Ø¥Ø²Ø§Ù„Ø© override)
  p_override_reason  TEXT    DEFAULT NULL,
  p_notes            TEXT    DEFAULT NULL,
  p_user_id          UUID    DEFAULT NULL
) RETURNS JSONB
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_line         hr_payroll_lines%ROWTYPE;
  v_run_status   TEXT;
  v_new_bonus    NUMERIC;
  v_new_deduct   NUMERIC;
  v_new_override NUMERIC;
  v_new_net      NUMERIC;
  v_new_total_d  NUMERIC;
BEGIN
  -- [SECURITY GUARD] ØªØ­Ù‚Ù‚ Ù…Ù† Ø§Ù„Ù‡ÙˆÙŠØ©
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- 1. Ù‚ÙÙ„ Ø§Ù„ØµÙ Ù„Ù…Ù†Ø¹ Ø§Ù„ØªØ²Ø§Ù…Ù†
  SELECT * INTO v_line
  FROM hr_payroll_lines
  WHERE id = p_line_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ø³Ø·Ø± Ø§Ù„Ø±Ø§ØªØ¨ ØºÙŠØ± Ù…ÙˆØ¬ÙˆØ¯';
  END IF;

  -- 2. Ø§Ù„ØªØ­Ù‚Ù‚ Ù…Ù† Ø£Ù† Ø§Ù„Ù…Ø³ÙŠØ± ÙÙŠ Ø­Ø§Ù„Ø© Ø§Ù„Ù…Ø±Ø§Ø¬Ø¹Ø© (Ù„Ø§ ØªØ¹Ø¯ÙŠÙ„ Ø¨Ø¹Ø¯ Ø§Ù„Ø§Ø¹ØªÙ…Ø§Ø¯)
  SELECT status INTO v_run_status
  FROM hr_payroll_runs
  WHERE id = v_line.payroll_run_id;

  IF v_run_status NOT IN ('review', 'calculating') THEN
    RAISE EXCEPTION 'Ù„Ø§ ÙŠÙ…ÙƒÙ† Ø§Ù„ØªØ¹Ø¯ÙŠÙ„ â€” Ø§Ù„Ù…Ø³ÙŠØ± ÙÙŠ Ø­Ø§Ù„Ø©: %', v_run_status;
  END IF;

  -- 3. Ø­Ø³Ø§Ø¨ Ø§Ù„Ù‚ÙŠÙ… Ø§Ù„Ø¬Ø¯ÙŠØ¯Ø© (COALESCE ÙŠØ­Ø§ÙØ¸ Ø¹Ù„Ù‰ Ø§Ù„Ù‚ÙŠÙ…Ø© Ø§Ù„Ø­Ø§Ù„ÙŠØ© Ø¥Ø°Ø§ Ù„Ù… ØªÙÙ…Ø±Ø±)
  v_new_bonus    := COALESCE(p_bonus_amount,     v_line.bonus_amount,     0);
  v_new_deduct   := COALESCE(p_other_deductions, v_line.other_deductions, 0);
  -- override_net: Ù†Ø³ØªØ®Ø¯Ù… p_override_net Ø¥Ø°Ø§ Ù…ÙØ±Ø±ØŒ ÙˆØ¥Ù„Ø§ Ù†Ø­Ø§ÙØ¸ Ø¹Ù„Ù‰ Ø§Ù„Ø­Ø§Ù„ÙŠ
  v_new_override := CASE
    WHEN p_override_net IS NOT NULL THEN p_override_net
    ELSE v_line.override_net
  END;
  -- Ø¥Ø°Ø§ ÙƒØ§Ù† override_net = 0 Ù†Ø¹ØªØ¨Ø±Ù‡ Ø¥Ù„ØºØ§Ø¡
  IF v_new_override = 0 THEN v_new_override := NULL; END IF;

  -- 4. â˜… Ø¥Ø¹Ø§Ø¯Ø© Ø­Ø³Ø§Ø¨ net_salary â˜…
  -- Ø§Ù„Ù…Ø¹Ø§Ø¯Ù„Ø© Ø§Ù„Ø£ØµÙ„ÙŠØ© Ù…Ù† calculate_employee_payroll (19b_hr_core_hotfixes.sql L309-311):
  --   net = gross_earned + overtime + commission
  --       - absence - penalty - advance - si - tax - health
  -- Ø§Ù„Ø¢Ù† Ù†ÙØ¶ÙŠÙ bonus ÙˆÙ†Ø·Ø±Ø­ other_deductions:
  --   net = gross_earned + overtime + commission + bonus
  --       - absence - penalty - advance - si - tax - health - other_deductions
  IF v_new_override IS NOT NULL THEN
    -- override_net ÙŠØªØ¬Ø§ÙˆØ² ÙƒÙ„ Ø§Ù„Ø­Ø³Ø§Ø¨Ø§Øª â€” ÙŠÙØ³ØªØ®Ø¯Ù… ÙƒØµØ§ÙÙ Ù†Ù‡Ø§Ø¦ÙŠ
    v_new_net := v_new_override;
  ELSE
    v_new_net := COALESCE(v_line.gross_earned, 0)
               + COALESCE(v_line.overtime_amount, 0)
               + COALESCE(v_line.commission_amount, 0)
               + v_new_bonus
               - COALESCE(v_line.absence_deduction, 0)
               - COALESCE(v_line.penalty_deduction, 0)
               - COALESCE(v_line.advance_deduction, 0)
               - COALESCE(v_line.social_insurance, 0)
               - COALESCE(v_line.income_tax, 0)
               - COALESCE(v_line.health_insurance, 0)
               - v_new_deduct;
    v_new_net := GREATEST(0, v_new_net);
  END IF;

  -- 5. Ø­Ø³Ø§Ø¨ total_deductions Ø§Ù„Ø¬Ø¯ÙŠØ¯
  v_new_total_d := COALESCE(v_line.absence_deduction, 0)
                 + COALESCE(v_line.penalty_deduction, 0)
                 + COALESCE(v_line.advance_deduction, 0)
                 + COALESCE(v_line.social_insurance, 0)
                 + COALESCE(v_line.income_tax, 0)
                 + COALESCE(v_line.health_insurance, 0)
                 + v_new_deduct;

  -- 6. ØªØ­Ø¯ÙŠØ« Ø§Ù„ØµÙ
  UPDATE hr_payroll_lines SET
    bonus_amount     = v_new_bonus,
    other_deductions = v_new_deduct,
    override_net     = v_new_override,
    override_reason  = COALESCE(p_override_reason, override_reason),
    notes            = COALESCE(p_notes, notes),
    net_salary       = v_new_net,
    total_deductions = v_new_total_d,
    updated_at       = now()
  WHERE id = p_line_id;

  -- 7. ØªØ­Ø¯ÙŠØ« Ù…Ø¬Ø§Ù…ÙŠØ¹ Ø§Ù„Ù…Ø³ÙŠØ±
  UPDATE hr_payroll_runs SET
    total_gross      = (SELECT COALESCE(SUM(gross_earned), 0) FROM hr_payroll_lines WHERE payroll_run_id = v_line.payroll_run_id),
    total_deductions = (SELECT COALESCE(SUM(total_deductions), 0) FROM hr_payroll_lines WHERE payroll_run_id = v_line.payroll_run_id),
    total_net        = (SELECT COALESCE(SUM(net_salary), 0) FROM hr_payroll_lines WHERE payroll_run_id = v_line.payroll_run_id),
    updated_at       = now()
  WHERE id = v_line.payroll_run_id;

  RETURN jsonb_build_object(
    'success',        true,
    'line_id',        p_line_id,
    'bonus_amount',   v_new_bonus,
    'other_deductions', v_new_deduct,
    'override_net',   v_new_override,
    'net_salary',     v_new_net,
    'total_deductions', v_new_total_d,
    'message',        'ØªÙ… ØªØ­Ø¯ÙŠØ« Ø³Ø·Ø± Ø§Ù„Ø±Ø§ØªØ¨ ÙˆØ¥Ø¹Ø§Ø¯Ø© Ø­Ø³Ø§Ø¨ Ø§Ù„ØµØ§ÙÙŠ'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION update_payroll_line_adjustments(UUID, NUMERIC, NUMERIC, NUMERIC, TEXT, TEXT, UUID) TO authenticated;


-- â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—
-- â•‘  FIX-AUDIT-07: upsert_attendance_and_reprocess           â•‘
-- â•‘                                                           â•‘
-- â•‘  Ø§Ù„Ù…Ø´ÙƒÙ„Ø©: Ø§Ù„ØªØ¹Ø¯ÙŠÙ„ Ø§Ù„ÙŠØ¯ÙˆÙŠ Ù„Ù„Ø­Ø¶ÙˆØ± (upsertAttendanceDay)   â•‘
-- â•‘  ÙŠÙØ­Ø¯Ù‘Ø« Ø£ÙˆÙ‚Ø§Øª Ø§Ù„Ø¯Ø®ÙˆÙ„/Ø§Ù„Ø®Ø±ÙˆØ¬ Ù„ÙƒÙ†:                        â•‘
-- â•‘    â‘  Ù„Ø§ ÙŠØ­Ø°Ù Ø§Ù„Ø¬Ø²Ø§Ø¡Ø§Øª Ø§Ù„Ù‚Ø¯ÙŠÙ…Ø© Ø§Ù„Ù…Ø±ØªØ¨Ø·Ø© Ø¨Ø§Ù„Ù‚ÙŠÙ… Ø§Ù„Ø³Ø§Ø¨Ù‚Ø©   â•‘
-- â•‘    â‘¡ Ù„Ø§ ÙŠÙØ¹ÙŠØ¯ ØªØ´ØºÙŠÙ„ process_attendance_penalties         â•‘
-- â•‘  â†’ Ø§Ù„Ù…ÙˆØ¸Ù ÙŠÙØ®ØµÙ… Ø¸Ù„Ù…Ø§Ù‹ Ù…Ù† Ø±Ø§ØªØ¨Ù‡ Ø±ØºÙ… Ø§Ù„ØªØµØ­ÙŠØ­              â•‘
-- â•‘                                                           â•‘
-- â•‘  Ø§Ù„Ø¥ØµÙ„Ø§Ø­: RPC Ø°Ø±ÙŠ ÙŠÙØ¹Ø¯Ù‘Ù„ Ø§Ù„Ø­Ø¶ÙˆØ± Ø«Ù… ÙŠÙØ¹ÙŠØ¯ Ø§Ù„Ø¬Ø²Ø§Ø¡Ø§Øª      â•‘
-- â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

CREATE OR REPLACE FUNCTION upsert_attendance_and_reprocess(
  p_employee_id       UUID,
  p_shift_date        DATE,
  p_punch_in_time     TIMESTAMPTZ  DEFAULT NULL,
  p_punch_out_time    TIMESTAMPTZ  DEFAULT NULL,
  p_status            hr_attendance_status DEFAULT NULL,
  p_notes             TEXT         DEFAULT NULL,
  p_user_id           UUID         DEFAULT NULL
) RETURNS JSONB
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_day_id          UUID;
  v_existing        hr_attendance_days%ROWTYPE;
  v_new_eff_hours   NUMERIC;
  v_new_late_min    INTEGER := 0;
  v_new_early_min   INTEGER := 0;
  v_new_ot_min      INTEGER := 0;
  v_new_status      hr_attendance_status;
  v_new_co_status   hr_checkout_status;
  v_work_start      TIME;
  v_work_end        TIME;
  v_grace_min       INTEGER;
  v_sched_start     TIMESTAMPTZ;
  v_sched_end       TIMESTAMPTZ;
  v_penalties_count INTEGER;
BEGIN
  -- [SECURITY] ØµÙ„Ø§Ø­ÙŠØ© Ø§Ù„ØªØ¹Ø¯ÙŠÙ„
  IF NOT check_permission(COALESCE(p_user_id, auth.uid()), 'hr.attendance.create') THEN
    RAISE EXCEPTION 'Ù„Ø§ ØªÙ…Ù„Ùƒ ØµÙ„Ø§Ø­ÙŠØ© ØªØ¹Ø¯ÙŠÙ„ Ø§Ù„Ø­Ø¶ÙˆØ±';
  END IF;

  -- 1. Ø¬Ù„Ø¨ Ø¥Ø¹Ø¯Ø§Ø¯Ø§Øª Ø³Ø§Ø¹Ø§Øª Ø§Ù„Ø¹Ù…Ù„
  SELECT value::TIME INTO v_work_start
  FROM company_settings WHERE key = 'hr.work_start_time';
  SELECT value::TIME INTO v_work_end
  FROM company_settings WHERE key = 'hr.work_end_time';
  SELECT COALESCE(value::INTEGER, 15) INTO v_grace_min
  FROM company_settings WHERE key = 'hr.late_grace_minutes';

  v_work_start := COALESCE(v_work_start, '09:00'::TIME);
  v_work_end   := COALESCE(v_work_end,   '17:00'::TIME);

  -- 2. Ø­Ø³Ø§Ø¨ Ø§Ù„Ù‚ÙŠÙ… Ø§Ù„Ù…Ø´ØªÙ‚Ø©
  v_new_status    := COALESCE(p_status, 'present');
  v_new_co_status := NULL;

  IF p_punch_in_time IS NOT NULL AND p_punch_out_time IS NOT NULL THEN
    -- Ø³Ø§Ø¹Ø§Øª ÙØ¹Ù„ÙŠØ©
    v_new_eff_hours := LEAST(
      ROUND(EXTRACT(EPOCH FROM (p_punch_out_time - p_punch_in_time)) / 3600.0, 2),
      24.00
    );

    -- ØªØ£Ø®ÙŠØ±
    v_sched_start := (p_shift_date + v_work_start) AT TIME ZONE 'Africa/Cairo';
    IF p_punch_in_time > v_sched_start + (v_grace_min || ' minutes')::INTERVAL THEN
      v_new_late_min := EXTRACT(EPOCH FROM (p_punch_in_time - v_sched_start))::INTEGER / 60;
      IF v_new_late_min > 0 THEN
        v_new_status := 'late';
      END IF;
    END IF;

    -- Ø§Ù†ØµØ±Ø§Ù Ù…Ø¨ÙƒØ± / Ø£ÙˆÙØ±ØªØ§ÙŠÙ…
    v_sched_end := (p_shift_date + v_work_end) AT TIME ZONE 'Africa/Cairo';
    IF p_punch_out_time > v_sched_end + INTERVAL '30 minutes' THEN
      v_new_ot_min := EXTRACT(EPOCH FROM (p_punch_out_time - v_sched_end))::INTEGER / 60;
      v_new_co_status := 'overtime';
    ELSIF p_punch_out_time < v_sched_end - INTERVAL '5 minutes' THEN
      v_new_early_min := EXTRACT(EPOCH FROM (v_sched_end - p_punch_out_time))::INTEGER / 60;
      -- ÙØ­Øµ Ø¥Ø¬Ø§Ø²Ø© Ø£Ùˆ Ø¥Ø°Ù† Ø§Ù†ØµØ±Ø§Ù Ù…Ø¨ÙƒØ±
      IF EXISTS (
        SELECT 1 FROM hr_leave_requests
        WHERE employee_id = p_employee_id
          AND start_date <= p_shift_date AND end_date >= p_shift_date
          AND status = 'approved'
      ) OR EXISTS (
        SELECT 1 FROM hr_permission_requests
        WHERE employee_id = p_employee_id
          AND permission_date = p_shift_date
          AND status = 'approved'
      ) THEN
        v_new_co_status := 'early_authorized';
      ELSE
        v_new_co_status := 'early_unauthorized';
      END IF;
    ELSE
      v_new_co_status := 'on_time';
    END IF;
  ELSIF p_punch_in_time IS NOT NULL THEN
    -- Ø¯Ø®ÙˆÙ„ ÙÙ‚Ø· Ø¨Ø¯ÙˆÙ† Ø®Ø±ÙˆØ¬
    v_sched_start := (p_shift_date + v_work_start) AT TIME ZONE 'Africa/Cairo';
    IF p_punch_in_time > v_sched_start + (v_grace_min || ' minutes')::INTERVAL THEN
      v_new_late_min := EXTRACT(EPOCH FROM (p_punch_in_time - v_sched_start))::INTEGER / 60;
      v_new_status := 'late';
    END IF;
  END IF;

  -- 3. UPSERT Ø³Ø¬Ù„ Ø§Ù„Ø­Ø¶ÙˆØ±
  INSERT INTO hr_attendance_days (
    employee_id, shift_date, work_date,
    punch_in_time, punch_out_time,
    status, checkout_status,
    late_minutes, early_leave_minutes, overtime_minutes,
    effective_hours, day_value,
    notes, review_status
  ) VALUES (
    p_employee_id, p_shift_date, p_shift_date,
    p_punch_in_time, p_punch_out_time,
    v_new_status, v_new_co_status,
    v_new_late_min, v_new_early_min, v_new_ot_min,
    v_new_eff_hours,
    CASE v_new_status
      WHEN 'half_day' THEN 0.5
      WHEN 'absent_unauthorized' THEN 0
      WHEN 'absent_authorized' THEN 0
      ELSE 1.0
    END,
    p_notes, 'reviewed'
  )
  ON CONFLICT (employee_id, shift_date)
  DO UPDATE SET
    punch_in_time       = EXCLUDED.punch_in_time,
    punch_out_time      = EXCLUDED.punch_out_time,
    status              = EXCLUDED.status,
    checkout_status     = EXCLUDED.checkout_status,
    late_minutes        = EXCLUDED.late_minutes,
    early_leave_minutes = EXCLUDED.early_leave_minutes,
    overtime_minutes    = EXCLUDED.overtime_minutes,
    effective_hours     = EXCLUDED.effective_hours,
    day_value           = EXCLUDED.day_value,
    notes               = EXCLUDED.notes,
    review_status       = 'reviewed',
    reviewed_by         = COALESCE(p_user_id, auth.uid()),
    reviewed_at         = now(),
    updated_at          = now()
  RETURNING id INTO v_day_id;

  -- 4. â˜… Ø­Ø°Ù Ø§Ù„Ø¬Ø²Ø§Ø¡Ø§Øª Ø§Ù„Ù‚Ø¯ÙŠÙ…Ø© ØºÙŠØ± Ø§Ù„Ù…ØªØ¬Ø§ÙˆØ²Ø© Ù„Ù‡Ø°Ø§ Ø§Ù„ÙŠÙˆÙ… â˜…
  DELETE FROM hr_penalty_instances
  WHERE attendance_day_id = v_day_id
    AND is_overridden = false
    AND payroll_run_id IS NULL;  -- Ù„Ù… ØªÙØ¯Ø±Ø¬ ÙÙŠ Ù…Ø³ÙŠØ± Ø¨Ø¹Ø¯

  -- 5. â˜… Ø¥Ø¹Ø§Ø¯Ø© ØªØ´ØºÙŠÙ„ Ù…Ø­Ø±Ùƒ Ø§Ù„Ø¬Ø²Ø§Ø¡Ø§Øª â˜…
  SELECT process_attendance_penalties(v_day_id) INTO v_penalties_count;

  RETURN jsonb_build_object(
    'success',           true,
    'attendance_day_id', v_day_id,
    'status',            v_new_status,
    'checkout_status',   v_new_co_status,
    'late_minutes',      v_new_late_min,
    'early_leave_minutes', v_new_early_min,
    'overtime_minutes',  v_new_ot_min,
    'effective_hours',   v_new_eff_hours,
    'penalties_applied', v_penalties_count,
    'message',           format('ØªÙ… ØªØ­Ø¯ÙŠØ« Ø§Ù„Ø­Ø¶ÙˆØ± â€” %s Ø¬Ø²Ø§Ø¡/Ø§Øª Ø£ÙØ¹ÙŠØ¯ Ø­Ø³Ø§Ø¨Ù‡Ø§', v_penalties_count)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION upsert_attendance_and_reprocess(UUID, DATE, TIMESTAMPTZ, TIMESTAMPTZ, hr_attendance_status, TEXT, UUID) TO authenticated;


-- â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—
-- â•‘  FIX-AUDIT-08: calculate_employee_payroll                â•‘
-- â•‘                                                          â•‘
-- â•‘  BUGS FIXED:                                             â•‘
-- â•‘  (A) working_days ÙƒØ§Ù† ÙŠÙØ­Ø³Ø¨ Ù…Ù† Ø¹Ø¯Ø¯ Ø³Ø¬Ù„Ø§Øª Ø§Ù„Ø­Ø¶ÙˆØ±          â•‘
-- â•‘      â†’ daily_rate Ù…Ø¶Ø®Ù… Ø¥Ø°Ø§ Ø§Ù„Ø³Ø¬Ù„Ø§Øª Ù‚Ù„ÙŠÙ„Ø©                 â•‘
-- â•‘  (B) partial month ÙƒØ§Ù† ÙŠØ¶Ø±Ø¨ daily_rate Ã— Ø£ÙŠØ§Ù… ØªÙ‚ÙˆÙŠÙ…ÙŠØ©    â•‘
-- â•‘      â†’ ÙŠØ´Ù…Ù„ Ø§Ù„Ø¬Ù…Ø¹Ø§Øª â†’ ØªØ¶Ø®Ù… Ø§Ù„Ø±Ø§ØªØ¨                       â•‘
-- â•‘  (C) Ø§Ù„Ø£ÙŠØ§Ù… Ø¨Ø¯ÙˆÙ† Ø³Ø¬Ù„ Ø­Ø¶ÙˆØ± Ù„Ù… ØªÙØ­Ø³Ø¨ ÙƒØºÙŠØ§Ø¨               â•‘
-- â•‘      â†’ Ù…ÙˆØ¸Ù Ø¨Ø³Ø¬Ù„ Ø­Ø¶ÙˆØ± ÙˆØ§Ø­Ø¯ ÙŠØ£Ø®Ø° Ø§Ù„Ø±Ø§ØªØ¨ ÙƒØ§Ù…Ù„              â•‘
-- â•‘                                                          â•‘
-- â•‘  SOLUTION:                                               â•‘
-- â•‘  1. Ø­Ø³Ø§Ø¨ Ø£ÙŠØ§Ù… Ø§Ù„Ø¹Ù…Ù„ Ù…Ù† Ø§Ù„ØªÙ‚ÙˆÙŠÙ… (Ø¨Ø­Ø°Ù Ø§Ù„Ø¹Ø·Ù„Ø§Øª/Ø§Ù„Ø£Ø¹ÙŠØ§Ø¯)   â•‘
-- â•‘  2. partial month ÙŠØ­Ø³Ø¨ Ø£ÙŠØ§Ù… Ø¹Ù…Ù„ ÙØ¹Ù„ÙŠØ© (Ø¨Ø¯ÙˆÙ† Ø¬Ù…Ø¹Ø§Øª)       â•‘
-- â•‘  3. Ø§Ù„ØºÙŠØ§Ø¨ = Ø£ÙŠØ§Ù… Ø§Ù„Ø¹Ù…Ù„ Ø§Ù„Ù…Ø³ØªØ­Ù‚Ø© - Ø£ÙŠØ§Ù… Ø§Ù„Ø­Ø¶ÙˆØ± Ø§Ù„ÙØ¹Ù„ÙŠØ©  â•‘
-- â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

CREATE OR REPLACE FUNCTION calculate_employee_payroll(
  p_employee_id  UUID,
  p_run_id       UUID
) RETURNS UUID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_run              hr_payroll_runs%ROWTYPE;
  v_period           hr_payroll_periods%ROWTYPE;
  v_emp              hr_employees%ROWTYPE;
  v_summary          JSONB;
  v_salary           RECORD;
  v_line_id          UUID;

  v_daily_rate       NUMERIC;
  v_gross_earned     NUMERIC;
  v_overtime_amount  NUMERIC;
  v_commission       NUMERIC;

  v_absence_deduct   NUMERIC;
  v_penalty_deduct   NUMERIC;
  v_advance_deduct   NUMERIC;
  v_si_deduct        NUMERIC;
  v_tax_deduct       NUMERIC;
  v_health_deduct    NUMERIC;

  v_si_enabled       BOOLEAN;
  v_si_rate          NUMERIC;
  v_tax_enabled      BOOLEAN;
  v_health_enabled   BOOLEAN;
  v_health_amount    NUMERIC;
  v_overtime_rate    NUMERIC;
  v_working_days     INTEGER;  -- Ø£ÙŠØ§Ù… Ø§Ù„Ø¹Ù…Ù„ Ø§Ù„Ø¥Ø¬Ù…Ø§Ù„ÙŠØ© ÙÙŠ Ø§Ù„ÙØªØ±Ø©

  v_work_hours_per_day NUMERIC;

  -- FIX-AUDIT-08 vars
  v_off_day_name     TEXT;
  v_off_dow          INTEGER;
  v_public_holidays  INTEGER;
  v_d                DATE;
  v_calendar_days    INTEGER;

  -- FIX-AUDIT-08(B): partial month â€” Ø£ÙŠØ§Ù… Ø§Ù„Ø¹Ù…Ù„ Ù…Ù† ØªØ§Ø±ÙŠØ® Ø§Ù„ØªÙˆØ¸ÙŠÙ/Ø§Ù„Ø¥Ù†Ù‡Ø§Ø¡
  v_partial_start    DATE;
  v_partial_end      DATE;
  v_partial_working  INTEGER;
  v_is_partial       BOOLEAN := false;

  -- FIX-AUDIT-08(C): Ø­Ø³Ø§Ø¨ Ø§Ù„ØºÙŠØ§Ø¨ Ø§Ù„ØªÙ„Ù‚Ø§Ø¦ÙŠ
  v_attended_days    NUMERIC;  -- Ø£ÙŠØ§Ù… Ø§Ù„Ø­Ø¶ÙˆØ± Ø§Ù„ÙØ¹Ù„ÙŠØ© (Ù…Ù† day_value)
  v_entitled_days    INTEGER;  -- Ø£ÙŠØ§Ù… Ø§Ù„Ø¹Ù…Ù„ Ø§Ù„Ù…Ø³ØªØ­Ù‚Ø© Ù„Ù„Ù…ÙˆØ¸Ù
  v_auto_absent      NUMERIC;  -- ØºÙŠØ§Ø¨ Ù…Ø­Ø³ÙˆØ¨ ØªÙ„Ù‚Ø§Ø¦ÙŠØ§Ù‹

  v_net              NUMERIC;
BEGIN
  SELECT * INTO v_run    FROM hr_payroll_runs    WHERE id = p_run_id;
  SELECT * INTO v_period FROM hr_payroll_periods WHERE id = v_run.period_id;
  SELECT * INTO v_emp    FROM hr_employees        WHERE id = p_employee_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ø¨ÙŠØ§Ù†Ø§Øª ØºÙŠØ± Ù…ÙƒØªÙ…Ù„Ø©'; END IF;

  SELECT * INTO v_salary
  FROM get_employee_salary_at_date(p_employee_id, v_period.start_date);

  v_summary := get_monthly_attendance_summary(p_employee_id, v_period.year, v_period.month);

  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- STEP 1: ØªØ­Ø¯ÙŠØ¯ ÙŠÙˆÙ… Ø§Ù„Ø¹Ø·Ù„Ø© Ø§Ù„Ø£Ø³Ø¨ÙˆØ¹ÙŠØ©
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  v_off_day_name := COALESCE(v_emp.weekly_off_day::TEXT, NULL);
  IF v_off_day_name IS NULL THEN
    SELECT value INTO v_off_day_name
    FROM company_settings WHERE key = 'hr.weekly_off_day';
  END IF;
  v_off_day_name := COALESCE(v_off_day_name, 'friday');

  v_off_dow := CASE lower(v_off_day_name)
    WHEN 'sunday'    THEN 0
    WHEN 'monday'    THEN 1
    WHEN 'tuesday'   THEN 2
    WHEN 'wednesday' THEN 3
    WHEN 'thursday'  THEN 4
    WHEN 'friday'    THEN 5
    WHEN 'saturday'  THEN 6
    ELSE 5
  END;

  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- STEP 2: Ø­Ø³Ø§Ø¨ Ø£ÙŠØ§Ù… Ø§Ù„Ø¹Ù…Ù„ Ø§Ù„ØªÙ‚ÙˆÙŠÙ…ÙŠØ© ÙÙŠ Ø§Ù„ÙØªØ±Ø© Ø§Ù„ÙƒØ§Ù…Ù„Ø©
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  v_calendar_days := 0;
  v_d := v_period.start_date;
  WHILE v_d <= v_period.end_date LOOP
    IF EXTRACT(DOW FROM v_d)::INTEGER <> v_off_dow THEN
      v_calendar_days := v_calendar_days + 1;
    END IF;
    v_d := v_d + 1;
  END LOOP;

  -- Ø­Ø°Ù Ø§Ù„Ø¥Ø¬Ø§Ø²Ø§Øª Ø§Ù„Ø±Ø³Ù…ÙŠØ© ÙÙŠ Ø£ÙŠØ§Ù… Ø¹Ù…Ù„
  SELECT COUNT(*) INTO v_public_holidays
  FROM hr_public_holidays
  WHERE holiday_date BETWEEN v_period.start_date AND v_period.end_date
    AND EXTRACT(DOW FROM holiday_date)::INTEGER <> v_off_dow;

  v_calendar_days := v_calendar_days - COALESCE(v_public_holidays, 0);
  IF v_calendar_days <= 0 THEN v_calendar_days := 26; END IF;

  v_working_days := v_calendar_days;
  v_daily_rate := COALESCE(v_salary.gross_salary, 0) / v_working_days;

  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- STEP 3: Ø³Ø§Ø¹Ø§Øª Ø§Ù„Ø¹Ù…Ù„ Ù…Ù† Ø§Ù„Ø¥Ø¹Ø¯Ø§Ø¯Ø§Øª
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  SELECT COALESCE(value::NUMERIC, 8) INTO v_work_hours_per_day
  FROM company_settings WHERE key = 'hr.work_hours_per_day';

  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- STEP 4: Ø§Ù„Ù…Ø³ØªØ­Ù‚ Ø§Ù„Ø¥Ø¬Ù…Ø§Ù„ÙŠ (gross_earned) + Partial Month
  -- FIX-AUDIT-08(B): Ø­Ø³Ø§Ø¨ Ø£ÙŠØ§Ù… Ø§Ù„Ø¹Ù…Ù„ Ø§Ù„ÙØ¹Ù„ÙŠØ© ÙÙŠ Ø§Ù„ÙØªØ±Ø© Ø§Ù„Ø¬Ø²Ø¦ÙŠØ©
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  v_gross_earned := COALESCE(v_salary.gross_salary, 0);
  v_entitled_days := v_working_days;  -- default: Ø§Ù„ÙØªØ±Ø© Ø§Ù„ÙƒØ§Ù…Ù„Ø©

  -- Ù‡Ù„ Ø§Ù„Ù…ÙˆØ¸Ù Ø§Ù†Ø¶Ù… ÙÙŠ Ù…Ù†ØªØµÙ Ø§Ù„ÙØªØ±Ø©ØŸ
  IF v_emp.hire_date > v_period.start_date AND v_emp.hire_date <= v_period.end_date THEN
    v_is_partial := true;
    v_partial_start := v_emp.hire_date;
    v_partial_end   := v_period.end_date;

    -- Ø­Ø³Ø§Ø¨ Ø£ÙŠØ§Ù… Ø§Ù„Ø¹Ù…Ù„ Ù…Ù† ØªØ§Ø±ÙŠØ® Ø§Ù„ØªÙˆØ¸ÙŠÙ (Ø¨Ø¯ÙˆÙ† Ø¹Ø·Ù„Ø§Øª)
    v_partial_working := 0;
    v_d := v_partial_start;
    WHILE v_d <= v_partial_end LOOP
      IF EXTRACT(DOW FROM v_d)::INTEGER <> v_off_dow THEN
        -- Ù„ÙŠØ³ Ø¥Ø¬Ø§Ø²Ø© Ø±Ø³Ù…ÙŠØ©ØŸ
        IF NOT EXISTS (
          SELECT 1 FROM hr_public_holidays
          WHERE holiday_date = v_d
        ) THEN
          v_partial_working := v_partial_working + 1;
        END IF;
      END IF;
      v_d := v_d + 1;
    END LOOP;

    IF v_partial_working <= 0 THEN v_partial_working := 1; END IF;

    v_gross_earned := v_daily_rate * v_partial_working;
    v_entitled_days := v_partial_working;
  END IF;

  -- Ù‡Ù„ Ø§Ù„Ù…ÙˆØ¸Ù ØºØ§Ø¯Ø± ÙÙŠ Ù…Ù†ØªØµÙ Ø§Ù„ÙØªØ±Ø©ØŸ
  IF v_emp.termination_date IS NOT NULL
    AND v_emp.termination_date >= v_period.start_date
    AND v_emp.termination_date <= v_period.end_date THEN
    v_is_partial := true;
    v_partial_start := GREATEST(v_period.start_date, v_emp.hire_date);
    v_partial_end   := v_emp.termination_date;

    v_partial_working := 0;
    v_d := v_partial_start;
    WHILE v_d <= v_partial_end LOOP
      IF EXTRACT(DOW FROM v_d)::INTEGER <> v_off_dow THEN
        IF NOT EXISTS (
          SELECT 1 FROM hr_public_holidays
          WHERE holiday_date = v_d
        ) THEN
          v_partial_working := v_partial_working + 1;
        END IF;
      END IF;
      v_d := v_d + 1;
    END LOOP;

    IF v_partial_working <= 0 THEN v_partial_working := 1; END IF;

    v_gross_earned := v_daily_rate * v_partial_working;
    v_entitled_days := v_partial_working;
  END IF;

  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- STEP 5: Ø­Ø³Ø§Ø¨ Ø§Ù„ØºÙŠØ§Ø¨ Ø§Ù„ØªÙ„Ù‚Ø§Ø¦ÙŠ
  -- FIX-AUDIT-08(C): Ø£ÙŠØ§Ù… Ø§Ù„Ø¹Ù…Ù„ Ø¨Ø¯ÙˆÙ† Ø³Ø¬Ù„ Ø­Ø¶ÙˆØ± = ØºÙŠØ§Ø¨
  -- Ø§Ù„Ø­Ø¶ÙˆØ± Ø§Ù„ÙØ¹Ù„ÙŠ = SUM(day_value) Ù…Ù† attendance_days
  -- Ø§Ù„ØºÙŠØ§Ø¨ = Ø£ÙŠØ§Ù… Ø§Ù„Ø¹Ù…Ù„ Ø§Ù„Ù…Ø³ØªØ­Ù‚Ø© - Ø§Ù„Ø­Ø¶ÙˆØ± Ø§Ù„ÙØ¹Ù„ÙŠ - Ø§Ù„Ø¥Ø¬Ø§Ø²Ø§Øª Ø§Ù„Ù…Ø¹ØªÙ…Ø¯Ø©
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  -- Ø£ÙŠØ§Ù… Ø§Ù„Ø­Ø¶ÙˆØ± Ø§Ù„ÙØ¹Ù„ÙŠØ© (day_value: 1=ÙƒØ§Ù…Ù„, 0.5=Ù†ØµÙ, 0=ØºÙŠØ§Ø¨)
  SELECT COALESCE(SUM(day_value), 0) INTO v_attended_days
  FROM hr_attendance_days
  WHERE employee_id = p_employee_id
    AND shift_date BETWEEN v_period.start_date AND v_period.end_date
    AND status NOT IN ('weekly_off', 'public_holiday');

  -- Ø£ÙŠØ§Ù… Ø§Ù„Ø¥Ø¬Ø§Ø²Ø§Øª Ø§Ù„Ù…Ø¹ØªÙ…Ø¯Ø© (on_leave, absent_authorized)
  v_attended_days := v_attended_days
    + COALESCE((v_summary->>'on_leave_days')::NUMERIC, 0)
    + COALESCE((v_summary->>'absent_authorized')::NUMERIC, 0);

  -- Ø§Ù„ØºÙŠØ§Ø¨ Ø§Ù„ØªÙ„Ù‚Ø§Ø¦ÙŠ = Ø§Ù„Ø£ÙŠØ§Ù… Ø§Ù„Ù…Ø³ØªØ­Ù‚Ø© - Ø§Ù„Ø­Ø¶ÙˆØ± - Ø§Ù„Ø¥Ø¬Ø§Ø²Ø§Øª
  v_auto_absent := GREATEST(0, v_entitled_days - v_attended_days);

  -- Ø®ØµÙ… Ø§Ù„ØºÙŠØ§Ø¨ = (Ø§Ù„ØºÙŠØ§Ø¨ Ù…Ù† Ø³Ø¬Ù„Ø§Øª attendance + Ø§Ù„ØºÙŠØ§Ø¨ Ø§Ù„ØªÙ„Ù‚Ø§Ø¦ÙŠ) Ã— Ø§Ù„Ù…Ø¹Ø¯Ù„ Ø§Ù„ÙŠÙˆÙ…ÙŠ
  v_absence_deduct := v_auto_absent * v_daily_rate;

  -- Ø®ØµÙ… Ø§Ù„Ø¬Ø²Ø§Ø¡Ø§Øª (Ù…Ù† penalty_instances)
  v_penalty_deduct := COALESCE((v_summary->>'penalty_deduction_days')::NUMERIC, 0) * v_daily_rate;

  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- STEP 6: Ø§Ù„Ø£ÙˆÙØ±ØªØ§ÙŠÙ…
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  SELECT COALESCE(value::NUMERIC, 1.5) INTO v_overtime_rate
  FROM company_settings WHERE key = 'hr.overtime_rate';

  v_overtime_amount :=
    COALESCE((v_summary->>'total_overtime_minutes')::NUMERIC, 0) / 60.0
    * (COALESCE(v_salary.base_salary, 0) / (v_working_days * v_work_hours_per_day))
    * v_overtime_rate;

  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- STEP 7: Ø§Ù„Ø¹Ù…ÙˆÙ„Ø§Øª ÙˆØ§Ù„Ø³Ù„Ù
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  SELECT COALESCE(SUM(commission_amount), 0) INTO v_commission
  FROM hr_commission_records
  WHERE employee_id = p_employee_id AND period_id = v_run.period_id
    AND is_eligible = true AND included_in_run IS NULL;

  SELECT COALESCE(SUM(ai.amount), 0) INTO v_advance_deduct
  FROM hr_advance_installments ai
  JOIN hr_advances adv ON adv.id = ai.advance_id
  WHERE adv.employee_id = p_employee_id
    AND ai.due_year = v_period.year AND ai.due_month = v_period.month
    AND ai.status = 'pending';

  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- STEP 8: Ø§Ù„ØªØ£Ù…ÙŠÙ†Ø§Øª ÙˆØ§Ù„Ø¶Ø±Ø§Ø¦Ø¨
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  SELECT COALESCE(value::BOOLEAN, false) INTO v_si_enabled
  FROM company_settings WHERE key = 'hr.social_insurance.enabled';
  SELECT COALESCE(value::NUMERIC, 11) INTO v_si_rate
  FROM company_settings WHERE key = 'hr.social_insurance.employee_rate';
  SELECT COALESCE(value::BOOLEAN, false) INTO v_tax_enabled
  FROM company_settings WHERE key = 'hr.income_tax.enabled';
  SELECT COALESCE(value::BOOLEAN, false) INTO v_health_enabled
  FROM company_settings WHERE key = 'hr.health_insurance.enabled';
  SELECT COALESCE(value::NUMERIC, 0) INTO v_health_amount
  FROM company_settings WHERE key = 'hr.health_insurance.amount';

  v_si_deduct     := CASE WHEN v_si_enabled    THEN v_gross_earned * (v_si_rate / 100) ELSE 0 END;
  v_tax_deduct    := 0;
  v_health_deduct := CASE WHEN v_health_enabled THEN v_health_amount ELSE 0 END;

  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- STEP 9: Ø§Ù„ØµØ§ÙÙŠ
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  v_net := v_gross_earned + v_overtime_amount + v_commission
         - v_absence_deduct - v_penalty_deduct - v_advance_deduct
         - v_si_deduct - v_tax_deduct - v_health_deduct;
  v_net := GREATEST(0, v_net);

  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- STEP 10: Ø­ÙØ¸ Ø§Ù„Ù†ØªØ§Ø¦Ø¬
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  INSERT INTO hr_payroll_lines (
    payroll_run_id, employee_id, period_id,
    total_working_days, actual_work_days,
    absent_days, deducted_days, overtime_hours,
    base_salary, transport_allowance, housing_allowance, other_allowances,
    overtime_amount, commission_amount, gross_earned,
    absence_deduction, penalty_deduction, advance_deduction,
    social_insurance, income_tax, health_insurance,
    total_deductions, net_salary, is_partial_month
  ) VALUES (
    p_run_id, p_employee_id, v_run.period_id,
    v_working_days,
    v_attended_days,
    v_auto_absent,
    COALESCE((v_summary->>'penalty_deduction_days')::NUMERIC, 0),
    COALESCE((v_summary->>'total_overtime_minutes')::NUMERIC, 0) / 60.0,
    COALESCE(v_salary.base_salary, 0),
    COALESCE(v_salary.transport_allowance, 0),
    COALESCE(v_salary.housing_allowance, 0),
    COALESCE(v_salary.other_allowances, 0),
    v_overtime_amount, v_commission, v_gross_earned,
    v_absence_deduct, v_penalty_deduct, v_advance_deduct,
    v_si_deduct, v_tax_deduct, v_health_deduct,
    v_absence_deduct + v_penalty_deduct + v_advance_deduct
      + v_si_deduct + v_tax_deduct + v_health_deduct,
    v_net,
    v_is_partial
  )
  ON CONFLICT (payroll_run_id, employee_id)
  DO UPDATE SET
    total_working_days = EXCLUDED.total_working_days,
    actual_work_days   = EXCLUDED.actual_work_days,
    absent_days        = EXCLUDED.absent_days,
    deducted_days      = EXCLUDED.deducted_days,
    overtime_hours     = EXCLUDED.overtime_hours,
    base_salary        = EXCLUDED.base_salary,
    transport_allowance= EXCLUDED.transport_allowance,
    housing_allowance  = EXCLUDED.housing_allowance,
    other_allowances   = EXCLUDED.other_allowances,
    gross_earned       = EXCLUDED.gross_earned,
    total_deductions   = EXCLUDED.total_deductions,
    net_salary         = EXCLUDED.net_salary,
    absence_deduction  = EXCLUDED.absence_deduction,
    penalty_deduction  = EXCLUDED.penalty_deduction,
    advance_deduction  = EXCLUDED.advance_deduction,
    commission_amount  = EXCLUDED.commission_amount,
    overtime_amount    = EXCLUDED.overtime_amount,
    social_insurance   = EXCLUDED.social_insurance,
    income_tax         = EXCLUDED.income_tax,
    health_insurance   = EXCLUDED.health_insurance,
    is_partial_month   = EXCLUDED.is_partial_month
  RETURNING id INTO v_line_id;

  UPDATE hr_payroll_runs
  SET
    total_gross      = (SELECT COALESCE(SUM(gross_earned),     0) FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
    total_deductions = (SELECT COALESCE(SUM(total_deductions), 0) FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
    total_net        = (SELECT COALESCE(SUM(net_salary),       0) FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
    total_employees  = (SELECT COUNT(*)                            FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
    calculated_by    = auth.uid(),
    calculated_at    = now(),
    status           = 'review',
    updated_at       = now()
  WHERE id = p_run_id;

  RETURN v_line_id;
END; $$;

