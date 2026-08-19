-- ============================================================================
-- AI Operations Planner — Work Health Fail-Closed / Concurrency Hardening
--
-- DESIGN-TIME MIGRATION ONLY.
-- 1) Missing native Work operational settings must never look like zero demand.
-- 2) Recovery commits for the same unhealthy source Work serialize on a
--    source-level advisory lock before the normal decision-level commit path.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

ALTER FUNCTION ai_ops.refresh_work_health_cases(UUID,DATE,INTEGER)
  RENAME TO refresh_work_health_cases_pre_settings_guard_v1;
REVOKE ALL ON FUNCTION ai_ops.refresh_work_health_cases_pre_settings_guard_v1(UUID,DATE,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.refresh_work_health_cases(
  p_snapshot_id UUID,
  p_business_date DATE,
  p_limit INTEGER DEFAULT 50
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS(
    SELECT 1 FROM public.work_operational_settings s WHERE s.singleton=true
  ) THEN
    RAISE EXCEPTION 'Work operational settings are missing; Work Health capture fails closed';
  END IF;

  RETURN ai_ops.refresh_work_health_cases_pre_settings_guard_v1(
    p_snapshot_id,p_business_date,p_limit
  );
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.refresh_work_health_cases(UUID,DATE,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;

ALTER FUNCTION ai_ops.build_operational_snapshot(UUID,INTEGER)
  RENAME TO build_operational_snapshot_pre_work_health_settings_guard_v1;
REVOKE ALL ON FUNCTION ai_ops.build_operational_snapshot_pre_work_health_settings_guard_v1(UUID,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.build_operational_snapshot(
  p_run_id UUID,
  p_case_limit INTEGER DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS(
    SELECT 1 FROM public.work_operational_settings s WHERE s.singleton=true
  ) THEN
    RAISE EXCEPTION 'Work operational settings are missing; operational snapshot fails closed';
  END IF;

  RETURN ai_ops.build_operational_snapshot_pre_work_health_settings_guard_v1(
    p_run_id,p_case_limit
  );
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.build_operational_snapshot(UUID,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;

ALTER FUNCTION private.work_create_ai_reviewed_work_health_task(UUID,UUID)
  RENAME TO work_create_ai_reviewed_work_health_task_pre_source_lock_v1;
REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_work_health_task_pre_source_lock_v1(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.work_create_ai_reviewed_work_health_task(
  p_decision_id UUID,
  p_approved_execution_by UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_source_work_id UUID;
BEGIN
  SELECT COALESCE(sc.entity_id,NULLIF(sc.facts->>'work_item_id','')::UUID)
  INTO v_source_work_id
  FROM ai_ops.decisions d
  JOIN ai_ops.snapshots s ON s.run_id=d.run_id
  JOIN ai_ops.snapshot_cases sc ON sc.snapshot_id=s.id AND sc.case_id=d.case_id
  WHERE d.id=p_decision_id AND sc.domain='work_health';

  IF v_source_work_id IS NULL THEN
    RAISE EXCEPTION 'Work Health decision-time source Work identity is missing';
  END IF;

  -- Different runs/decisions about the same source Work must not race through
  -- collision detection and create duplicate recovery tasks.
  PERFORM pg_advisory_xact_lock(
    hashtextextended('ai_ops:work-health-source:'||v_source_work_id::TEXT,0)
  );

  RETURN private.work_create_ai_reviewed_work_health_task_pre_source_lock_v1(
    p_decision_id,p_approved_execution_by
  );
END;
$$;
REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_work_health_task(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.refresh_work_health_cases(UUID,DATE,INTEGER) IS
  'Fail-closed Work Health capture wrapper requiring the native Work operational settings singleton.';
COMMENT ON FUNCTION ai_ops.build_operational_snapshot(UUID,INTEGER) IS
  'Canonical operational snapshot wrapper that fails closed when native Work Health settings are unavailable.';
COMMENT ON FUNCTION private.work_create_ai_reviewed_work_health_task(UUID,UUID) IS
  'Source-serialized Work Health reviewed recovery bridge preventing concurrent duplicate recovery Work across runs.';

RESET lock_timeout;
RESET statement_timeout;
