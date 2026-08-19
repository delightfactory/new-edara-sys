-- AI Operations Planner — Work Health Snapshot As-Of Integrity Hardening
-- DESIGN-TIME MIGRATION ONLY. A new build may sample Work Health demand immediately
-- before the shared snapshot is created. If a time-based Work Health condition
-- crosses its boundary in that interval, a zero completed capture must fail closed.
SET lock_timeout = '5s';
SET statement_timeout = '60s';

ALTER FUNCTION ai_ops.build_operational_snapshot(UUID,INTEGER)
  RENAME TO build_operational_snapshot_pre_work_health_asof_integrity_v1;
REVOKE ALL ON FUNCTION ai_ops.build_operational_snapshot_pre_work_health_asof_integrity_v1(UUID,INTEGER)
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
DECLARE
  v_result JSONB;
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_capture ai_ops.snapshot_domain_captures%ROWTYPE;
  v_exact_candidate_exists BOOLEAN:=false;
BEGIN
  v_result:=ai_ops.build_operational_snapshot_pre_work_health_asof_integrity_v1(
    p_run_id,p_case_limit
  );

  -- Do not reinterpret an already-frozen snapshot using later mutable Work state.
  IF NOT COALESCE((v_result->>'idempotent_reuse')::BOOLEAN,false) THEN
    SELECT * INTO v_snapshot
    FROM ai_ops.snapshots s
    WHERE s.run_id=p_run_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'new operational snapshot missing after build: %',p_run_id;
    END IF;

    SELECT * INTO v_capture
    FROM ai_ops.snapshot_domain_captures dc
    WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='work_health';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'new operational snapshot is missing Work Health capture: %',v_snapshot.id;
    END IF;

    IF v_capture.capture_version<>'work-health-v1' THEN
      RAISE EXCEPTION 'unexpected Work Health capture version during as-of integrity check: %',v_capture.capture_version;
    END IF;

    -- Positive allocations already capture at snapshot.data_as_of. The integrity
    -- edge is a zero completed marker produced from an earlier zero-demand sample.
    IF v_capture.case_count=0 AND v_capture.capture_status='completed' THEN
      SELECT EXISTS(
        SELECT 1
        FROM ai_ops.work_health_candidates(v_snapshot.data_as_of,1)
      ) INTO v_exact_candidate_exists;

      IF v_exact_candidate_exists THEN
        RAISE EXCEPTION
          'Work Health zero-completed capture disagrees with snapshot data_as_of; build fails closed';
      END IF;
    END IF;
  END IF;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.build_operational_snapshot(UUID,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.build_operational_snapshot(UUID,INTEGER) IS
  'Canonical six-domain snapshot build with Work Health settings, global-budget and zero-completed snapshot-as-of integrity fail-closed guards.';

RESET lock_timeout;
RESET statement_timeout;
