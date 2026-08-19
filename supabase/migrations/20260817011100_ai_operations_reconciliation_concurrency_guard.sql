-- ============================================================================
-- AI Operations — stale-snapshot guard for outcome reconciliation
--
-- Recovery may process an older due run after a newer snapshot has already
-- touched the same Case. An older snapshot must never resolve/reopen newer Case
-- reality. Reconciliation therefore acts only when no later snapshot update is
-- visible for the Case; source operational tables remain untouched.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.reconcile_cases_from_snapshot(p_snapshot_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_domain RECORD;
  v_row RECORD;
  v_decision RECORD;
  v_resolved INTEGER := 0;
  v_reopened INTEGER := 0;
  v_skipped_domains INTEGER := 0;
  v_stale_case_skips INTEGER := 0;
  v_domain_stale_case_skips INTEGER := 0;
  v_complete_domains INTEGER := 0;
  v_now TIMESTAMPTZ := clock_timestamp();
  v_outcome_type TEXT;
  v_key TEXT;
BEGIN
  SELECT * INTO v_snapshot FROM ai_ops.snapshots WHERE id=p_snapshot_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations snapshot not found'; END IF;

  FOR v_domain IN
    SELECT dc.*
    FROM ai_ops.snapshot_domain_captures dc
    WHERE dc.snapshot_id=p_snapshot_id
    ORDER BY dc.domain
  LOOP
    IF v_domain.capture_status<>'completed'
       OR COALESCE((v_domain.metadata->>'has_more')::BOOLEAN,false)
       OR COALESCE((v_domain.metadata->>'global_budget_exhausted')::BOOLEAN,false)
       OR COALESCE((v_domain.metadata->>'truncated')::BOOLEAN,false) THEN
      v_skipped_domains:=v_skipped_domains+1;
      CONTINUE;
    END IF;

    v_complete_domains:=v_complete_domains+1;

    -- Resolve only older/current Case state. If another newer snapshot has
    -- refreshed a Case after this snapshot was generated, this run is stale for
    -- that Case and has no authority to change its lifecycle.
    FOR v_row IN
      UPDATE ai_ops.cases c
      SET
        status='resolved',
        resolved_at=v_now,
        state_version=c.state_version+1,
        updated_at=v_now
      WHERE c.domain=v_domain.domain
        AND c.status IN ('open','monitored','actioned','suppressed')
        AND c.last_seen_at<=v_snapshot.generated_at
        AND NOT EXISTS (
          SELECT 1
          FROM ai_ops.snapshot_cases sc
          WHERE sc.snapshot_id=p_snapshot_id AND sc.case_id=c.id
        )
      RETURNING c.id
    LOOP
      v_key:='snapshot:'||p_snapshot_id::TEXT||':case:'||v_row.id::TEXT||':source_resolved';
      INSERT INTO ai_ops.case_outcomes(
        idempotency_key,case_id,snapshot_id,outcome_type,observed_at,metadata
      ) VALUES (
        v_key,v_row.id,p_snapshot_id,'source_resolved',v_now,
        jsonb_build_object(
          'domain',v_domain.domain,
          'capture_status',v_domain.capture_status,
          'snapshot_generated_at',v_snapshot.generated_at,
          'stale_snapshot_guard',true,
          'employee_performance_signal',false
        )
      ) ON CONFLICT(idempotency_key) DO NOTHING;
      v_resolved:=v_resolved+1;
    END LOOP;

    SELECT count(*)::INTEGER INTO v_domain_stale_case_skips
    FROM ai_ops.cases c
    WHERE c.domain=v_domain.domain
      AND c.status IN ('open','monitored','actioned','suppressed')
      AND c.last_seen_at>v_snapshot.generated_at
      AND NOT EXISTS (
        SELECT 1 FROM ai_ops.snapshot_cases sc
        WHERE sc.snapshot_id=p_snapshot_id AND sc.case_id=c.id
      );
    v_stale_case_skips:=v_stale_case_skips+COALESCE(v_domain_stale_case_skips,0);

    -- A persistent Case may be reopened after its latest AI-linked Work is done
    -- or cancelled only if THIS snapshot is still the Case's latest captured
    -- state. A newer snapshot wins and this older run becomes observation-only.
    FOR v_row IN
      SELECT c.id AS case_id
      FROM ai_ops.cases c
      JOIN ai_ops.snapshot_cases sc
        ON sc.snapshot_id=p_snapshot_id AND sc.case_id=c.id
      WHERE c.domain=v_domain.domain
        AND c.status='actioned'
        AND c.last_snapshot_id=p_snapshot_id
        AND c.last_seen_at<=v_snapshot.generated_at
    LOOP
      SELECT d.id AS decision_id,d.committed_work_item_id,wi.status::TEXT AS work_status
      INTO v_decision
      FROM ai_ops.decisions d
      JOIN public.work_items wi ON wi.id=d.committed_work_item_id
      WHERE d.case_id=v_row.case_id
        AND d.commit_status='committed'
        AND d.committed_work_item_id IS NOT NULL
      ORDER BY d.committed_at DESC NULLS LAST,d.created_at DESC,d.id DESC
      LIMIT 1;

      IF FOUND AND v_decision.work_status IN ('done','cancelled') THEN
        UPDATE ai_ops.cases
        SET
          status='open',
          resolved_at=NULL,
          state_version=state_version+1,
          updated_at=v_now
        WHERE id=v_row.case_id
          AND status='actioned'
          AND last_snapshot_id=p_snapshot_id;

        IF FOUND THEN
          v_outcome_type:=CASE
            WHEN v_decision.work_status='done' THEN 'work_completed_condition_persists'
            ELSE 'work_cancelled_condition_persists'
          END;
          v_key:='snapshot:'||p_snapshot_id::TEXT||':case:'||v_row.case_id::TEXT||':'||v_outcome_type;
          INSERT INTO ai_ops.case_outcomes(
            idempotency_key,case_id,snapshot_id,decision_id,work_item_id,
            outcome_type,observed_at,metadata
          ) VALUES (
            v_key,v_row.case_id,p_snapshot_id,v_decision.decision_id,
            v_decision.committed_work_item_id,v_outcome_type,v_now,
            jsonb_build_object(
              'work_status',v_decision.work_status,
              'condition_present_in_snapshot',true,
              'completion_is_not_success',true,
              'stale_snapshot_guard',true,
              'employee_performance_signal',false
            )
          ) ON CONFLICT(idempotency_key) DO NOTHING;
          v_reopened:=v_reopened+1;
        END IF;
      END IF;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object(
    'snapshot_id',p_snapshot_id,
    'complete_domains_reconciled',v_complete_domains,
    'domains_skipped_as_partial',v_skipped_domains,
    'stale_case_updates_skipped',v_stale_case_skips,
    'cases_resolved',v_resolved,
    'cases_reopened_after_terminal_work',v_reopened,
    'stale_snapshot_guard',true,
    'source_mutation_performed',false
  );
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.reconcile_cases_from_snapshot(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.reconcile_cases_from_snapshot(UUID) IS
  'Complete-domain Case reconciliation with stale-snapshot protection. Older recovery runs cannot resolve/reopen Case state touched by newer snapshots; Work completion remains distinct from business success.';

RESET lock_timeout;
RESET statement_timeout;
