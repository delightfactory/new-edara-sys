-- AI Operations — service worker gateway and deterministic due-run materializer.
SET lock_timeout = '5s';
SET statement_timeout = '30s';

CREATE OR REPLACE FUNCTION ai_ops.materialize_due_runs(p_now TIMESTAMPTZ DEFAULT clock_timestamp())
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_settings ai_ops.settings%ROWTYPE;
  v_schedule ai_ops.run_schedules%ROWTYPE;
  v_local_now TIMESTAMP;
  v_local_day DATE;
  v_scheduled_for TIMESTAMPTZ;
  v_offset INTEGER;
  v_max_days INTEGER;
  v_inserted INTEGER:=0;
BEGIN
  SELECT * INTO v_settings FROM ai_ops.settings WHERE singleton=true;
  IF NOT FOUND OR NOT v_settings.planner_enabled THEN
    RETURN jsonb_build_object('materialized',0,'planner_enabled',false);
  END IF;

  FOR v_schedule IN SELECT * FROM ai_ops.run_schedules WHERE enabled ORDER BY code LOOP
    v_local_now:=p_now AT TIME ZONE v_schedule.timezone;
    v_max_days:=LEAST(7,CEIL(v_schedule.recovery_window_minutes/1440.0)::INTEGER);
    FOR v_offset IN 0..v_max_days LOOP
      v_local_day:=v_local_now::DATE-v_offset;
      IF EXTRACT(DOW FROM v_local_day)::SMALLINT=ANY(v_schedule.weekdays) THEN
        v_scheduled_for:=(v_local_day+v_schedule.local_time) AT TIME ZONE v_schedule.timezone;
        IF v_scheduled_for<=p_now
           AND v_scheduled_for>=p_now-(v_schedule.recovery_window_minutes*interval '1 minute') THEN
          INSERT INTO ai_ops.planner_runs(
            run_key,schedule_id,run_type,business_date,scheduled_for,status,checkpoint,
            planner_policy_version,tool_contract_version
          ) VALUES (
            v_schedule.code||':'||v_local_day::TEXT,v_schedule.id,v_schedule.run_type,
            v_local_day,v_scheduled_for,'pending','created',
            v_settings.planner_policy_version,v_settings.tool_contract_version
          ) ON CONFLICT(run_key) DO NOTHING;
          IF FOUND THEN v_inserted:=v_inserted+1; END IF;
        END IF;
      END IF;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object('materialized',v_inserted,'planner_enabled',true,'checked_at',p_now);
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.materialize_due_runs(TIMESTAMPTZ)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.ai_ops_worker_materialize_due_runs()
RETURNS JSONB LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
  SELECT ai_ops.materialize_due_runs(clock_timestamp());
$$;
CREATE OR REPLACE FUNCTION public.ai_ops_worker_claim_next_run(p_worker_id TEXT,p_lease_seconds INTEGER DEFAULT 1200)
RETURNS JSONB LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
  SELECT ai_ops.worker_claim_next_run(p_worker_id,p_lease_seconds);
$$;
CREATE OR REPLACE FUNCTION public.ai_ops_worker_heartbeat(p_run_id UUID,p_worker_id TEXT,p_lease_seconds INTEGER DEFAULT 1200)
RETURNS JSONB LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
  SELECT ai_ops.worker_heartbeat(p_run_id,p_worker_id,p_lease_seconds);
$$;
CREATE OR REPLACE FUNCTION public.ai_ops_worker_get_context(p_run_id UUID,p_worker_id TEXT)
RETURNS JSONB LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
  SELECT ai_ops.worker_get_context(p_run_id,p_worker_id);
$$;
CREATE OR REPLACE FUNCTION public.ai_ops_worker_stage_decisions(p_run_id UUID,p_worker_id TEXT,p_context_hash TEXT,p_decisions JSONB)
RETURNS JSONB LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
  SELECT ai_ops.worker_stage_decisions(p_run_id,p_worker_id,p_context_hash,p_decisions);
$$;
CREATE OR REPLACE FUNCTION public.ai_ops_worker_validate_staged_run(p_run_id UUID)
RETURNS JSONB LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
  SELECT ai_ops.validate_staged_run(p_run_id);
$$;
CREATE OR REPLACE FUNCTION public.ai_ops_worker_fail_run(p_run_id UUID,p_worker_id TEXT,p_error_class TEXT,p_error_message TEXT)
RETURNS JSONB LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
  SELECT ai_ops.worker_fail_run(p_run_id,p_worker_id,p_error_class,p_error_message);
$$;

REVOKE ALL ON FUNCTION public.ai_ops_worker_materialize_due_runs() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ai_ops_worker_claim_next_run(TEXT,INTEGER) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ai_ops_worker_heartbeat(UUID,TEXT,INTEGER) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ai_ops_worker_get_context(UUID,TEXT) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ai_ops_worker_stage_decisions(UUID,TEXT,TEXT,JSONB) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ai_ops_worker_validate_staged_run(UUID) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ai_ops_worker_fail_run(UUID,TEXT,TEXT,TEXT) FROM PUBLIC,anon,authenticated;

GRANT EXECUTE ON FUNCTION public.ai_ops_worker_materialize_due_runs() TO service_role;
GRANT EXECUTE ON FUNCTION public.ai_ops_worker_claim_next_run(TEXT,INTEGER) TO service_role;
GRANT EXECUTE ON FUNCTION public.ai_ops_worker_heartbeat(UUID,TEXT,INTEGER) TO service_role;
GRANT EXECUTE ON FUNCTION public.ai_ops_worker_get_context(UUID,TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.ai_ops_worker_stage_decisions(UUID,TEXT,TEXT,JSONB) TO service_role;
GRANT EXECUTE ON FUNCTION public.ai_ops_worker_validate_staged_run(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.ai_ops_worker_fail_run(UUID,TEXT,TEXT,TEXT) TO service_role;

COMMENT ON FUNCTION public.ai_ops_worker_get_context(UUID,TEXT) IS
  'Service-role-only bounded worker context gateway. Browser roles have no execution grant.';
COMMENT ON FUNCTION public.ai_ops_worker_stage_decisions(UUID,TEXT,TEXT,JSONB) IS
  'Service-role-only staging gateway. Staging never commits Work.';

RESET lock_timeout;
RESET statement_timeout;
