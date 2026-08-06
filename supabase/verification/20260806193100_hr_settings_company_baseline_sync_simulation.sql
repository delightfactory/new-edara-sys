-- =============================================================================
-- HR settings/company baseline synchronization — disposable simulation
--
-- DISPOSABLE DATABASE ONLY. Requires:
--   SET SESSION edara.allow_schedule_simulation = 'disposable-only';
-- All writes roll back.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

DO $simulation$
DECLARE
  v_actor UUID;
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_future_date DATE := date_trunc('month', v_today + INTERVAL '12 months')::DATE + 9;
  v_baseline public.hr_company_work_schedules%ROWTYPE;
  v_setting_start TEXT;
  v_rejected BOOLEAN;
BEGIN
  IF current_setting('edara.allow_schedule_simulation', true) IS DISTINCT FROM 'disposable-only' THEN
    RAISE EXCEPTION 'Simulation safety stop: disposable-only session flag is required';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready()
     OR (SELECT count(*) FROM public.hr_company_work_schedules) <> 1
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Baseline-sync simulation requires the clean installed state';
  END IF;

  SELECT candidate.user_id
  INTO v_actor
  FROM (
    SELECT ur.user_id
    FROM public.user_roles ur
    JOIN public.role_permissions rp ON rp.role_id = ur.role_id
    WHERE rp.permission IN ('*', 'settings.update')
    GROUP BY ur.user_id
    HAVING bool_or(rp.permission IN ('*', 'settings.update'))
  ) candidate
  JOIN public.profiles p ON p.id = candidate.user_id
  ORDER BY candidate.user_id
  LIMIT 1;

  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Baseline-sync simulation could not find an authorized actor';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_actor::TEXT, true);

  -- A genuine immediate pre-activation change updates both mutable settings and
  -- the sole technical baseline in one transaction.
  PERFORM public.update_hr_settings_atomic(jsonb_build_array(
    jsonb_build_object('key', 'hr.work_start_time', 'value', '10:00'),
    jsonb_build_object('key', 'hr.work_end_time', 'value', '18:00'),
    jsonb_build_object('key', 'hr.work_hours_per_day', 'value', '8'),
    jsonb_build_object('key', 'hr.weekly_off_day', 'value', 'sunday')
  ));

  SELECT * INTO v_baseline
  FROM public.hr_company_work_schedules
  WHERE is_system_baseline = true;

  IF to_char(v_baseline.start_time, 'HH24:MI') <> '10:00'
     OR to_char(v_baseline.end_time, 'HH24:MI') <> '18:00'
     OR v_baseline.scheduled_minutes <> 480
     OR v_baseline.weekly_off_day <> 'sunday'
     OR NOT public.hr_company_work_schedule_activation_consistent() THEN
    RAISE EXCEPTION 'Baseline-sync simulation failed: atomic semantic change did not synchronize baseline';
  END IF;

  -- A direct table update cannot leave the two representations inconsistent.
  v_rejected := false;
  BEGIN
    UPDATE public.company_settings
    SET value = '09:00'
    WHERE key = 'hr.work_start_time';

    SET CONSTRAINTS trg_company_settings_schedule_consistency_deferred IMMEDIATE;
  EXCEPTION
    WHEN OTHERS THEN
      v_rejected := SQLERRM ILIKE '%تحديث مواعيد الشركة غير مكتمل%';
  END;
  SET CONSTRAINTS trg_company_settings_schedule_consistency_deferred DEFERRED;

  IF NOT v_rejected THEN
    RAISE EXCEPTION 'Baseline-sync simulation failed: inconsistent direct update was accepted';
  END IF;

  SELECT value INTO v_setting_start
  FROM public.company_settings
  WHERE key = 'hr.work_start_time';

  IF v_setting_start <> '10:00'
     OR NOT public.hr_company_work_schedule_activation_consistent() THEN
    RAISE EXCEPTION 'Baseline-sync simulation failed: rejected direct update left data changed';
  END IF;

  -- Once versioned preparation starts, legacy schedule fields become closed to
  -- semantic changes even while the feature switch remains false.
  PERFORM public.save_company_work_schedule_version(
    v_future_date,
    '09:00',
    '17:00',
    'friday',
    'Disposable future version starts staged history'
  );

  v_rejected := false;
  BEGIN
    PERFORM public.update_hr_settings_atomic(jsonb_build_array(
      jsonb_build_object('key', 'hr.work_start_time', 'value', '11:00'),
      jsonb_build_object('key', 'hr.work_end_time', 'value', '19:00'),
      jsonb_build_object('key', 'hr.work_hours_per_day', 'value', '8'),
      jsonb_build_object('key', 'hr.weekly_off_day', 'value', 'friday')
    ));
  EXCEPTION
    WHEN OTHERS THEN
      v_rejected := SQLERRM ILIKE '%بدأ تجهيز الجداول المؤرخة%';
  END;

  IF NOT v_rejected
     OR (SELECT value FROM public.company_settings WHERE key = 'hr.work_start_time') <> '10:00' THEN
    RAISE EXCEPTION 'Baseline-sync simulation failed: legacy settings changed after staged history began';
  END IF;

  RAISE NOTICE 'Baseline-sync simulation passed; all data will roll back';
END;
$simulation$;

ROLLBACK;
