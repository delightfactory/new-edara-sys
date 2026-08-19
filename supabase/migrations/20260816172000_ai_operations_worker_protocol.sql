-- ============================================================================
-- AI Operations Planner — Internal Worker Protocol
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply until explicitly reviewed/approved.
--
-- IMPORTANT:
--   These functions are INTERNAL state-machine primitives in the unexposed
--   ai_ops schema. They are NOT a ChatGPT/Supabase connector security boundary.
--   No execution grants are issued to anon/authenticated/service_role.
--
-- Provides:
--   * lease-based run claim/recovery
--   * deterministic frozen worker context + exact payload hash/byte guard
--   * one bounded decision per frozen case (zero decisions when zero cases)
--   * explicit technical failure recording
--
-- Explicitly absent:
--   * no Work creation or escalation execution
--   * no Sales/HR/Inventory mutation
--   * no public worker RPC
--   * no API key/token/authentication mechanism
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.worker_claim_next_run(
  p_worker_id TEXT,
  p_lease_seconds INTEGER DEFAULT 1200
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_settings ai_ops.settings%ROWTYPE;
  v_run ai_ops.planner_runs%ROWTYPE;
  v_now TIMESTAMPTZ := clock_timestamp();
  v_lease_seconds INTEGER;
BEGIN
  IF p_worker_id IS NULL OR btrim(p_worker_id) = '' OR length(p_worker_id) > 120 THEN
    RAISE EXCEPTION 'invalid worker id';
  END IF;

  v_lease_seconds := LEAST(GREATEST(COALESCE(p_lease_seconds, 1200), 300), 1800);

  SELECT * INTO v_settings
  FROM ai_ops.settings
  WHERE singleton = true;

  IF NOT FOUND OR NOT v_settings.planner_enabled THEN
    RETURN jsonb_build_object('claimed', false, 'reason', 'planner_disabled');
  END IF;

  SELECT r.* INTO v_run
  FROM ai_ops.planner_runs r
  WHERE r.scheduled_for <= v_now
    AND (
      r.status = 'pending'
      OR (
        r.status IN ('claimed','reasoning')
        AND r.lease_expires_at IS NOT NULL
        AND r.lease_expires_at <= v_now
      )
    )
  ORDER BY r.scheduled_for ASC, r.created_at ASC, r.id ASC
  FOR UPDATE SKIP LOCKED
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('claimed', false, 'reason', 'no_due_run');
  END IF;

  UPDATE ai_ops.planner_runs
  SET
    status = 'claimed',
    attempt_no = attempt_no + 1,
    claimed_by = p_worker_id,
    claimed_at = v_now,
    lease_expires_at = v_now + make_interval(secs => v_lease_seconds),
    heartbeat_at = v_now,
    checkpoint = 'claimed',
    started_at = COALESCE(started_at, v_now),
    error_class = NULL,
    error_message = NULL,
    updated_at = v_now
  WHERE id = v_run.id
  RETURNING * INTO v_run;

  RETURN jsonb_build_object(
    'claimed', true,
    'run_id', v_run.id,
    'run_key', v_run.run_key,
    'run_type', v_run.run_type,
    'business_date', v_run.business_date,
    'scheduled_for', v_run.scheduled_for,
    'attempt_no', v_run.attempt_no,
    'lease_expires_at', v_run.lease_expires_at,
    'planner_policy_version', v_run.planner_policy_version,
    'tool_contract_version', v_run.tool_contract_version,
    'prompt_version', v_run.prompt_version
  );
END;
$$;

CREATE OR REPLACE FUNCTION ai_ops.worker_get_context(
  p_run_id UUID,
  p_worker_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_settings ai_ops.settings%ROWTYPE;
  v_run ai_ops.planner_runs%ROWTYPE;
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_domain_capture ai_ops.snapshot_domain_captures%ROWTYPE;
  v_build JSONB;
  v_cases JSONB := '[]'::JSONB;
  v_body JSONB;
  v_hash TEXT;
  v_context_bytes INTEGER;
  v_now TIMESTAMPTZ := clock_timestamp();
BEGIN
  IF p_worker_id IS NULL OR btrim(p_worker_id) = '' OR length(p_worker_id) > 120 THEN
    RAISE EXCEPTION 'invalid worker id';
  END IF;

  SELECT * INTO v_run
  FROM ai_ops.planner_runs
  WHERE id = p_run_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'planner run not found';
  END IF;

  IF v_run.claimed_by IS DISTINCT FROM p_worker_id
     OR v_run.status NOT IN ('claimed','reasoning')
     OR v_run.lease_expires_at IS NULL
     OR v_run.lease_expires_at <= v_now THEN
    RAISE EXCEPTION 'worker lease is not valid for run';
  END IF;

  SELECT * INTO v_settings
  FROM ai_ops.settings
  WHERE singleton = true;

  IF NOT FOUND OR NOT v_settings.planner_enabled THEN
    RAISE EXCEPTION 'planner disabled while run is claimed';
  END IF;

  -- Deterministic DB work occurs here, not inside the LLM prompt.
  v_build := ai_ops.build_credit_snapshot(p_run_id, v_settings.max_cases_per_snapshot);

  SELECT * INTO v_snapshot
  FROM ai_ops.snapshots
  WHERE run_id = p_run_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'snapshot missing after build';
  END IF;

  SELECT * INTO v_domain_capture
  FROM ai_ops.snapshot_domain_captures dc
  WHERE dc.snapshot_id = v_snapshot.id
    AND dc.domain = 'receivables';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'receivables capture marker missing after build';
  END IF;

  SELECT COALESCE(jsonb_agg(case_payload ORDER BY snapshot_rank ASC), '[]'::JSONB)
  INTO v_cases
  FROM (
    SELECT
      sc.snapshot_rank,
      jsonb_build_object(
        'case_id', sc.case_id,
        'case_key', sc.case_key,
        'rank', sc.snapshot_rank,
        'domain', sc.domain,
        'case_type', sc.case_type,
        'entity_type', sc.entity_type,
        'entity_id', sc.entity_id,
        'attention_class', sc.attention_class,
        'severity', sc.severity,
        'case_status_at_snapshot', sc.case_status,
        'source_as_of', sc.source_as_of,
        'facts', sc.facts,
        'responsibility_evidence', sc.responsibility_evidence,
        'operational_context', sc.operational_context,
        'trust', sc.trust
      ) AS case_payload
    FROM ai_ops.snapshot_cases sc
    WHERE sc.snapshot_id = v_snapshot.id
      AND sc.domain = 'receivables'
    ORDER BY sc.snapshot_rank ASC
  ) q;

  v_body := jsonb_build_object(
    'contract_version', v_run.tool_contract_version,
    'run', jsonb_build_object(
      'run_id', v_run.id,
      'run_key', v_run.run_key,
      'run_type', v_run.run_type,
      'business_date', v_run.business_date,
      'scheduled_for', v_run.scheduled_for,
      'attempt_no', v_run.attempt_no,
      'planner_policy_version', v_run.planner_policy_version,
      'prompt_version', v_run.prompt_version
    ),
    'snapshot', jsonb_build_object(
      'snapshot_id', v_snapshot.id,
      'payload_version', v_snapshot.payload_version,
      'generated_at', v_snapshot.generated_at,
      'data_as_of', v_snapshot.data_as_of,
      'snapshot_status', v_snapshot.snapshot_status,
      'trust', v_snapshot.trust,
      'company_pulse', v_snapshot.company_pulse,
      'coverage', v_snapshot.coverage,
      'domain_capture', jsonb_build_object(
        'domain', v_domain_capture.domain,
        'capture_status', v_domain_capture.capture_status,
        'case_count', v_domain_capture.case_count,
        'evidence_bytes', v_domain_capture.evidence_bytes,
        'metadata', v_domain_capture.metadata
      )
    ),
    'cases', v_cases,
    'decision_contract', jsonb_build_object(
      'required_decision_for_each_case', true,
      'zero_cases_allows_zero_decisions', true,
      'allowed_decisions', jsonb_build_array('IGNORE','MONITOR','INVESTIGATE','INFORM','CREATE_WORK','ESCALATE'),
      'action_decisions', jsonb_build_array('CREATE_WORK','ESCALATE'),
      'max_actions_per_run', v_settings.max_actions_per_run,
      'monitor_requires_review_after', true,
      'create_work_requires', jsonb_build_array('recommended_owner_user_id','expected_outcome','next_action_text'),
      'rationale_is_concise_not_chain_of_thought', true
    )
  );

  v_context_bytes := octet_length(convert_to(v_body::TEXT, 'UTF8'));

  IF v_context_bytes > v_settings.max_worker_context_bytes THEN
    UPDATE ai_ops.planner_runs
    SET
      status = 'partial',
      checkpoint = 'context_budget_blocked',
      heartbeat_at = v_now,
      lease_expires_at = NULL,
      error_class = 'context_budget_exceeded',
      error_message = format('worker context %s bytes exceeds limit %s', v_context_bytes, v_settings.max_worker_context_bytes),
      result_summary = result_summary || jsonb_build_object(
        'snapshot_id', v_snapshot.id,
        'worker_context_bytes', v_context_bytes,
        'worker_context_limit_bytes', v_settings.max_worker_context_bytes
      ),
      completed_at = v_now,
      updated_at = v_now
    WHERE id = v_run.id;

    RETURN jsonb_build_object(
      'blocked', true,
      'reason', 'context_budget_exceeded',
      'run_id', v_run.id,
      'snapshot_id', v_snapshot.id,
      'context_bytes', v_context_bytes,
      'context_limit_bytes', v_settings.max_worker_context_bytes
    );
  END IF;

  -- MD5 is used only as deterministic payload identity, never authentication.
  v_hash := md5(v_body::TEXT);

  UPDATE ai_ops.planner_runs
  SET
    status = 'reasoning',
    checkpoint = 'context_ready',
    heartbeat_at = v_now,
    lease_expires_at = v_now + interval '20 minutes',
    cases_seen = v_domain_capture.case_count,
    result_summary = result_summary || jsonb_build_object(
      'snapshot_id', v_snapshot.id,
      'worker_context_hash', v_hash,
      'worker_context_hash_algorithm', 'md5-jsonb-identity',
      'worker_context_bytes', v_context_bytes,
      'worker_context_limit_bytes', v_settings.max_worker_context_bytes
    ),
    updated_at = v_now
  WHERE id = v_run.id;

  RETURN jsonb_build_object(
    'blocked', false,
    'context_hash', v_hash,
    'context_hash_algorithm', 'md5-jsonb-identity',
    'context_bytes', v_context_bytes,
    'context_limit_bytes', v_settings.max_worker_context_bytes,
    'context', v_body
  );
END;
$$;

CREATE OR REPLACE FUNCTION ai_ops.worker_heartbeat(
  p_run_id UUID,
  p_worker_id TEXT,
  p_lease_seconds INTEGER DEFAULT 1200
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_now TIMESTAMPTZ := clock_timestamp();
  v_lease_seconds INTEGER := LEAST(GREATEST(COALESCE(p_lease_seconds, 1200), 300), 1800);
  v_new_expiry TIMESTAMPTZ;
BEGIN
  UPDATE ai_ops.planner_runs
  SET
    heartbeat_at = v_now,
    lease_expires_at = v_now + make_interval(secs => v_lease_seconds),
    updated_at = v_now
  WHERE id = p_run_id
    AND claimed_by = p_worker_id
    AND status IN ('claimed','reasoning')
    AND lease_expires_at > v_now
  RETURNING lease_expires_at INTO v_new_expiry;

  IF v_new_expiry IS NULL THEN
    RAISE EXCEPTION 'worker lease is not valid for heartbeat';
  END IF;

  RETURN jsonb_build_object('run_id', p_run_id, 'lease_expires_at', v_new_expiry);
END;
$$;

CREATE OR REPLACE FUNCTION ai_ops.worker_stage_decisions(
  p_run_id UUID,
  p_worker_id TEXT,
  p_context_hash TEXT,
  p_decisions JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_run ai_ops.planner_runs%ROWTYPE;
  v_settings ai_ops.settings%ROWTYPE;
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_domain_capture ai_ops.snapshot_domain_captures%ROWTYPE;
  v_now TIMESTAMPTZ := clock_timestamp();
  v_decision_count INTEGER;
  v_distinct_case_count INTEGER;
  v_action_count INTEGER;
  v_submission_hash TEXT;
  v_existing_count INTEGER;
  v_existing_hashes INTEGER;
  v_item JSONB;
  v_case_id UUID;
  v_decision_type TEXT;
  v_owner UUID;
  v_assignee UUID;
  v_linked_work UUID;
BEGIN
  IF jsonb_typeof(p_decisions) <> 'array' THEN
    RAISE EXCEPTION 'decisions payload must be a JSON array';
  END IF;

  SELECT * INTO v_run
  FROM ai_ops.planner_runs
  WHERE id = p_run_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'planner run not found';
  END IF;

  IF v_run.claimed_by IS DISTINCT FROM p_worker_id
     OR v_run.status <> 'reasoning'
     OR v_run.lease_expires_at IS NULL
     OR v_run.lease_expires_at <= v_now THEN
    RAISE EXCEPTION 'worker lease is not valid for staging';
  END IF;

  IF NULLIF(p_context_hash, '') IS NULL
     OR v_run.result_summary->>'worker_context_hash' IS DISTINCT FROM p_context_hash THEN
    RAISE EXCEPTION 'worker context hash does not match the run context';
  END IF;

  SELECT * INTO v_settings FROM ai_ops.settings WHERE singleton = true;
  SELECT * INTO v_snapshot FROM ai_ops.snapshots WHERE run_id = p_run_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'run snapshot not found';
  END IF;

  SELECT * INTO v_domain_capture
  FROM ai_ops.snapshot_domain_captures dc
  WHERE dc.snapshot_id = v_snapshot.id AND dc.domain = 'receivables';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'run receivables capture marker not found';
  END IF;

  v_decision_count := jsonb_array_length(p_decisions);

  IF v_decision_count <> v_domain_capture.case_count THEN
    RAISE EXCEPTION 'one decision is required for every frozen case: expected %, received %', v_domain_capture.case_count, v_decision_count;
  END IF;

  SELECT count(DISTINCT (item->>'case_id'))::INTEGER
  INTO v_distinct_case_count
  FROM jsonb_array_elements(p_decisions) item;

  IF v_distinct_case_count <> v_decision_count THEN
    RAISE EXCEPTION 'duplicate case decisions are not allowed';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_decisions) item
    WHERE NOT EXISTS (
      SELECT 1 FROM ai_ops.snapshot_cases sc
      WHERE sc.snapshot_id = v_snapshot.id
        AND sc.case_id = (item->>'case_id')::UUID
    )
  ) THEN
    RAISE EXCEPTION 'decision payload references a case outside the frozen run snapshot';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM ai_ops.snapshot_cases sc
    WHERE sc.snapshot_id = v_snapshot.id
      AND sc.domain = 'receivables'
      AND NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_decisions) item
        WHERE (item->>'case_id')::UUID = sc.case_id
      )
  ) THEN
    RAISE EXCEPTION 'decision payload omitted a frozen case';
  END IF;

  -- Reject unknown/trace-like fields. The worker returns decision artifacts,
  -- never chain-of-thought, scratchpads, SQL or free-form tool instructions.
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_decisions) item,
         LATERAL jsonb_object_keys(item) field_name
    WHERE field_name NOT IN (
      'case_id','decision_type','concise_rationale','confidence',
      'recommended_owner_user_id','recommended_assignee_user_id',
      'responsibility_summary','why_this_owner','why_now',
      'expected_outcome','next_action_text','due_at','review_after'
    )
  ) THEN
    RAISE EXCEPTION 'decision payload contains unsupported fields';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_decisions) item
    WHERE item->>'decision_type' NOT IN ('IGNORE','MONITOR','INVESTIGATE','INFORM','CREATE_WORK','ESCALATE')
       OR length(btrim(COALESCE(item->>'concise_rationale',''))) NOT BETWEEN 1 AND 1200
       OR COALESCE((item->>'confidence')::NUMERIC, -1) < 0
       OR COALESCE((item->>'confidence')::NUMERIC, -1) > 1
  ) THEN
    RAISE EXCEPTION 'decision payload failed type/rationale/confidence validation';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_decisions) item
    WHERE length(COALESCE(item->>'responsibility_summary','')) > 800
       OR length(COALESCE(item->>'why_this_owner','')) > 800
       OR length(COALESCE(item->>'why_now','')) > 800
       OR length(COALESCE(item->>'expected_outcome','')) > 1000
       OR length(COALESCE(item->>'next_action_text','')) > 1000
  ) THEN
    RAISE EXCEPTION 'decision payload failed bounded text validation';
  END IF;

  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_decisions) item
    WHERE item->>'decision_type' = 'MONITOR'
      AND NULLIF(item->>'review_after','') IS NULL
  ) THEN
    RAISE EXCEPTION 'MONITOR decisions require review_after';
  END IF;

  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_decisions) item
    WHERE item->>'decision_type' = 'CREATE_WORK'
      AND (
        NULLIF(item->>'recommended_owner_user_id','') IS NULL
        OR NULLIF(btrim(item->>'expected_outcome'),'') IS NULL
        OR NULLIF(btrim(item->>'next_action_text'),'') IS NULL
      )
  ) THEN
    RAISE EXCEPTION 'CREATE_WORK requires owner, expected_outcome and next_action_text';
  END IF;

  SELECT count(*)::INTEGER
  INTO v_action_count
  FROM jsonb_array_elements(p_decisions) item
  WHERE item->>'decision_type' IN ('CREATE_WORK','ESCALATE');

  IF v_action_count > v_settings.max_actions_per_run THEN
    RAISE EXCEPTION 'action decision count % exceeds max %', v_action_count, v_settings.max_actions_per_run;
  END IF;

  -- CREATE_WORK human targets must be valid actors at staging time. Commit will
  -- revalidate again because staging is not authorization to execute.
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_decisions)
  LOOP
    v_case_id := (v_item->>'case_id')::UUID;
    v_decision_type := v_item->>'decision_type';
    v_owner := NULLIF(v_item->>'recommended_owner_user_id','')::UUID;
    v_assignee := NULLIF(v_item->>'recommended_assignee_user_id','')::UUID;

    IF v_decision_type = 'CREATE_WORK' THEN
      IF NOT private.work_actor_is_active(v_owner) THEN
        RAISE EXCEPTION 'recommended owner is not an active Work actor for case %', v_case_id;
      END IF;
      IF v_assignee IS NOT NULL AND NOT private.work_actor_is_active(v_assignee) THEN
        RAISE EXCEPTION 'recommended assignee is not an active Work actor for case %', v_case_id;
      END IF;
    END IF;

    IF v_decision_type = 'ESCALATE' THEN
      SELECT NULLIF(sc.facts->'existing_active_work'->>'work_item_id','')::UUID
      INTO v_linked_work
      FROM ai_ops.snapshot_cases sc
      WHERE sc.snapshot_id = v_snapshot.id AND sc.case_id = v_case_id;

      IF v_linked_work IS NULL THEN
        RAISE EXCEPTION 'ESCALATE requires frozen existing Work evidence for case %', v_case_id;
      END IF;
    ELSE
      v_linked_work := NULL;
    END IF;
  END LOOP;

  v_submission_hash := md5(p_decisions::TEXT);

  SELECT count(*)::INTEGER,
         count(DISTINCT d.management_only_metadata->>'worker_submission_hash')::INTEGER
  INTO v_existing_count, v_existing_hashes
  FROM ai_ops.decisions d
  WHERE d.run_id = p_run_id;

  IF v_existing_count > 0 THEN
    IF v_existing_count = v_decision_count
       AND v_existing_hashes = 1
       AND EXISTS (
         SELECT 1 FROM ai_ops.decisions d
         WHERE d.run_id = p_run_id
           AND d.management_only_metadata->>'worker_submission_hash' = v_submission_hash
       ) THEN
      UPDATE ai_ops.planner_runs
      SET status='staged', checkpoint='decisions_staged', heartbeat_at=v_now,
          lease_expires_at=NULL, decisions_count=v_decision_count,
          result_summary=result_summary || jsonb_build_object('worker_submission_hash',v_submission_hash,'action_decisions',v_action_count),
          updated_at=v_now
      WHERE id=p_run_id;

      RETURN jsonb_build_object('staged', true, 'idempotent_reuse', true, 'decision_count', v_decision_count, 'action_count', v_action_count, 'submission_hash', v_submission_hash);
    END IF;

    RAISE EXCEPTION 'run already contains a different staged decision submission';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_decisions)
  LOOP
    v_case_id := (v_item->>'case_id')::UUID;
    v_decision_type := v_item->>'decision_type';
    v_owner := NULLIF(v_item->>'recommended_owner_user_id','')::UUID;
    v_assignee := NULLIF(v_item->>'recommended_assignee_user_id','')::UUID;

    IF v_decision_type = 'ESCALATE' THEN
      SELECT NULLIF(sc.facts->'existing_active_work'->>'work_item_id','')::UUID
      INTO v_linked_work
      FROM ai_ops.snapshot_cases sc
      WHERE sc.snapshot_id = v_snapshot.id AND sc.case_id = v_case_id;
    ELSE
      v_linked_work := NULL;
    END IF;

    INSERT INTO ai_ops.decisions(
      run_id, case_id, revision, decision_type, recommended_owner_user_id,
      recommended_assignee_user_id, responsibility_basis, concise_rationale,
      confidence, expected_outcome, next_action_text, due_at, review_after,
      linked_work_item_id, validation_state, validation_detail,
      management_only_metadata
    ) VALUES (
      p_run_id,
      v_case_id,
      1,
      v_decision_type,
      v_owner,
      v_assignee,
      jsonb_build_object(
        'summary', COALESCE(v_item->>'responsibility_summary',''),
        'why_this_owner', COALESCE(v_item->>'why_this_owner',''),
        'why_now', COALESCE(v_item->>'why_now','')
      ),
      btrim(v_item->>'concise_rationale'),
      (v_item->>'confidence')::NUMERIC,
      NULLIF(COALESCE(v_item->>'expected_outcome',''), ''),
      NULLIF(COALESCE(v_item->>'next_action_text',''), ''),
      NULLIF(v_item->>'due_at','')::TIMESTAMPTZ,
      NULLIF(v_item->>'review_after','')::TIMESTAMPTZ,
      v_linked_work,
      'pending',
      jsonb_build_object('requires_human_review', true, 'stage_only', true),
      jsonb_build_object(
        'worker_id', p_worker_id,
        'worker_context_hash', p_context_hash,
        'worker_submission_hash', v_submission_hash,
        'chain_of_thought_stored', false
      )
    );
  END LOOP;

  UPDATE ai_ops.planner_runs
  SET
    status = 'staged',
    checkpoint = 'decisions_staged',
    heartbeat_at = v_now,
    lease_expires_at = NULL,
    decisions_count = v_decision_count,
    cases_investigated = v_decision_count,
    result_summary = result_summary || jsonb_build_object(
      'worker_submission_hash', v_submission_hash,
      'action_decisions', v_action_count,
      'zero_action_run', v_action_count = 0
    ),
    updated_at = v_now
  WHERE id = p_run_id;

  RETURN jsonb_build_object(
    'staged', true,
    'idempotent_reuse', false,
    'decision_count', v_decision_count,
    'action_count', v_action_count,
    'zero_action_run', v_action_count = 0,
    'submission_hash', v_submission_hash
  );
END;
$$;

CREATE OR REPLACE FUNCTION ai_ops.worker_fail_run(
  p_run_id UUID,
  p_worker_id TEXT,
  p_error_class TEXT,
  p_error_message TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_now TIMESTAMPTZ := clock_timestamp();
BEGIN
  IF NULLIF(btrim(COALESCE(p_error_class,'')), '') IS NULL OR length(p_error_class) > 120 THEN
    RAISE EXCEPTION 'invalid worker error class';
  END IF;

  IF NULLIF(btrim(COALESCE(p_error_message,'')), '') IS NULL OR length(p_error_message) > 1000 THEN
    RAISE EXCEPTION 'invalid worker error message';
  END IF;

  UPDATE ai_ops.planner_runs
  SET
    status = 'failed',
    checkpoint = 'worker_failed',
    heartbeat_at = v_now,
    lease_expires_at = NULL,
    error_class = p_error_class,
    error_message = p_error_message,
    completed_at = v_now,
    updated_at = v_now
  WHERE id = p_run_id
    AND claimed_by = p_worker_id
    AND status IN ('claimed','reasoning')
  RETURNING id INTO p_run_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'worker cannot fail a run it does not currently own';
  END IF;

  RETURN jsonb_build_object('failed', true, 'run_id', p_run_id, 'error_class', p_error_class);
END;
$$;

-- No external execution surface yet. Future access must be added separately
-- through a reviewed bounded gateway/broker; never by broadly exposing ai_ops.
REVOKE ALL ON FUNCTION ai_ops.worker_claim_next_run(TEXT, INTEGER) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION ai_ops.worker_get_context(UUID, TEXT) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION ai_ops.worker_heartbeat(UUID, TEXT, INTEGER) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION ai_ops.worker_stage_decisions(UUID, TEXT, TEXT, JSONB) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION ai_ops.worker_fail_run(UUID, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated, service_role;

RESET lock_timeout;
RESET statement_timeout;
