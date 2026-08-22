-- ============================================================================
-- AI Operations Planner — Worker Context Budget Hardening
--
-- DESIGN-TIME MIGRATION ONLY.
-- Production-clone rehearsal showed the seven-domain worker payload could exceed
-- max_worker_context_bytes before model invocation. This migration fixes the
-- payload producer instead of increasing the configured safety limit:
--   * caps the fresh snapshot case budget from the byte budget while preserving
--     the required-domain fairness floor;
--   * compacts nested evidence deterministically without dropping frozen cases;
--   * keeps responsibility, feasibility, active-work and quantitative facts;
--   * fails closed if the compacted payload still exceeds the hard byte limit.
-- No operational source table is mutated.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.compact_worker_json(
  p_value JSONB,
  p_array_limit INTEGER DEFAULT 3,
  p_string_limit INTEGER DEFAULT 420,
  p_depth INTEGER DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_type TEXT;
  v_result JSONB;
  v_total INTEGER;
BEGIN
  IF p_value IS NULL THEN
    RETURN NULL;
  END IF;

  v_type := jsonb_typeof(p_value);

  IF p_depth >= 8 THEN
    IF v_type = 'array' THEN
      RETURN jsonb_build_array(jsonb_build_object(
        '_truncated_depth', true,
        '_total_items', jsonb_array_length(p_value)
      ));
    ELSIF v_type = 'object' THEN
      RETURN jsonb_build_object('_truncated_depth', true);
    END IF;
    RETURN p_value;
  END IF;

  IF v_type = 'object' THEN
    SELECT COALESCE(
      jsonb_object_agg(e.key, ai_ops.compact_worker_json(
        e.value,
        p_array_limit,
        p_string_limit,
        p_depth + 1
      )),
      '{}'::JSONB
    )
    INTO v_result
    FROM jsonb_each(p_value) e;
    RETURN jsonb_strip_nulls(v_result);
  END IF;

  IF v_type = 'array' THEN
    v_total := jsonb_array_length(p_value);
    SELECT COALESCE(
      jsonb_agg(
        ai_ops.compact_worker_json(
          e.value,
          p_array_limit,
          p_string_limit,
          p_depth + 1
        ) ORDER BY e.ordinality
      ),
      '[]'::JSONB
    )
    INTO v_result
    FROM jsonb_array_elements(p_value) WITH ORDINALITY AS e(value, ordinality)
    WHERE e.ordinality <= GREATEST(p_array_limit, 1);

    IF v_total > GREATEST(p_array_limit, 1) THEN
      v_result := v_result || jsonb_build_array(jsonb_build_object(
        '_truncated', true,
        '_total_items', v_total
      ));
    END IF;
    RETURN v_result;
  END IF;

  IF v_type = 'string' THEN
    RETURN to_jsonb(
      CASE
        WHEN length(p_value #>> '{}') > GREATEST(p_string_limit, 80)
          THEN left(p_value #>> '{}', GREATEST(p_string_limit, 80)) || '…[truncated]'
        ELSE p_value #>> '{}'
      END
    );
  END IF;

  RETURN p_value;
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.compact_worker_json(JSONB,INTEGER,INTEGER,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.compact_worker_json(JSONB,INTEGER,INTEGER,INTEGER) IS
  'Deterministic bounded-evidence compactor for LLM worker context. Preserves object keys and scalar facts, bounds nested arrays/strings, and emits explicit truncation markers.';

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
  v_run ai_ops.planner_runs%ROWTYPE;
  v_settings ai_ops.settings%ROWTYPE;
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_build JSONB;
  v_cases JSONB := '[]'::JSONB;
  v_domain_captures JSONB := '[]'::JSONB;
  v_body JSONB;
  v_hash TEXT;
  v_context_bytes INTEGER;
  v_total_cases INTEGER := 0;
  v_capture_count INTEGER := 0;
  v_any_partial BOOLEAN := false;
  v_any_blocked BOOLEAN := false;
  v_required_domain_count INTEGER;
  v_context_case_limit INTEGER;
  v_array_limit INTEGER := 3;
  v_string_limit INTEGER := 420;
  v_compaction_tier TEXT := 'bounded-v1';
  v_now TIMESTAMPTZ := clock_timestamp();
BEGIN
  IF p_worker_id IS NULL OR btrim(p_worker_id) = '' OR length(p_worker_id) > 120 THEN
    RAISE EXCEPTION 'invalid worker id';
  END IF;

  SELECT * INTO v_run
  FROM ai_ops.planner_runs
  WHERE id = p_run_id;

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

  v_required_domain_count := cardinality(ai_ops.required_operational_domains());
  IF v_required_domain_count IS NULL OR v_required_domain_count <= 0 THEN
    RAISE EXCEPTION 'AI Operations required-domain registry is empty';
  END IF;

  -- Reserve 12 KiB for run/snapshot/contracts and target roughly 1.4 KiB per
  -- selected case before nested evidence compaction. This bounds fresh capture
  -- volume from the same hard byte budget instead of raising that budget.
  v_context_case_limit := LEAST(
    v_settings.max_cases_per_snapshot,
    GREATEST(
      v_required_domain_count,
      floor(
        GREATEST(v_settings.max_worker_context_bytes - 12288, 0)::NUMERIC / 1400
      )::INTEGER
    )
  );

  v_build := ai_ops.build_operational_snapshot(p_run_id, v_context_case_limit);

  SELECT * INTO v_snapshot
  FROM ai_ops.snapshots
  WHERE run_id = p_run_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'run snapshot missing after bounded operational build';
  END IF;

  IF NOT ai_ops.snapshot_has_required_domain_captures(v_snapshot.id) THEN
    RAISE EXCEPTION 'worker context is missing one or more required operational domain captures';
  END IF;

  SELECT
    COALESCE(sum(dc.case_count), 0)::INTEGER,
    count(*)::INTEGER,
    COALESCE(bool_or(dc.capture_status = 'partial'), false),
    COALESCE(bool_or(dc.capture_status = 'blocked'), false),
    COALESCE(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'domain', dc.domain,
      'capture_status', dc.capture_status,
      'case_count', dc.case_count,
      'source_as_of', dc.source_as_of,
      'has_more', dc.metadata->'has_more',
      'global_budget_exhausted', dc.metadata->'global_budget_exhausted'
    )) ORDER BY dc.domain), '[]'::JSONB)
  INTO v_total_cases, v_capture_count, v_any_partial, v_any_blocked, v_domain_captures
  FROM ai_ops.snapshot_domain_captures dc
  WHERE dc.snapshot_id = v_snapshot.id;

  IF v_total_cases > v_context_case_limit THEN
    RAISE EXCEPTION 'frozen case count % exceeds bounded context case limit %',
      v_total_cases, v_context_case_limit;
  END IF;

  -- Keep every frozen case. Only nested evidence is compacted; identifiers,
  -- severity, responsibility and current operational facts remain available.
  SELECT COALESCE(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
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
    'facts', ai_ops.compact_worker_json(sc.facts, v_array_limit, v_string_limit, 0),
    'responsibility_evidence', ai_ops.compact_worker_json(sc.responsibility_evidence, v_array_limit, v_string_limit, 0),
    'operational_context', ai_ops.compact_worker_json(sc.operational_context, v_array_limit, v_string_limit, 0),
    'trust', ai_ops.compact_worker_json(sc.trust, 2, 260, 0)
  )) ORDER BY sc.snapshot_rank), '[]'::JSONB)
  INTO v_cases
  FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id = v_snapshot.id;

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
      'snapshot_status', CASE
        WHEN v_any_blocked THEN 'blocked'
        WHEN v_any_partial OR v_snapshot.snapshot_status <> 'ready' THEN 'partial'
        ELSE 'ready'
      END,
      'trust', ai_ops.compact_worker_json(v_snapshot.trust, 2, 260, 0),
      'company_pulse', ai_ops.compact_worker_json(v_snapshot.company_pulse, 3, 320, 0),
      'coverage', jsonb_build_object(
        'global_case_limit', v_settings.max_cases_per_snapshot,
        'context_case_limit', v_context_case_limit,
        'captured_cases', v_total_cases,
        'domain_capture_count', v_capture_count,
        'all_domain_captures_complete', NOT v_any_partial AND NOT v_any_blocked
      ),
      'domain_captures', v_domain_captures
    ),
    'cases', v_cases,
    'decision_contract', jsonb_build_object(
      'required_decision_for_each_case', true,
      'zero_cases_allows_zero_decisions', true,
      'allowed_decisions', jsonb_build_array('IGNORE','MONITOR','INVESTIGATE','INFORM','CREATE_WORK','ESCALATE'),
      'action_decisions', jsonb_build_array('CREATE_WORK','ESCALATE'),
      'max_actions_per_run', v_settings.max_actions_per_run,
      'monitor_requires_review_after', true,
      'create_work_requires', jsonb_build_array(
        'recommended_owner_user_id','recommended_assignee_user_id',
        'expected_outcome','next_action_text','due_at'
      ),
      'rationale_is_concise_not_chain_of_thought', true
    )
  );

  v_context_bytes := octet_length(convert_to(v_body::TEXT, 'UTF8'));

  -- Emergency compaction tier: preserve every case and all object keys, but
  -- tighten only nested arrays/strings if the first bounded representation is
  -- still too large. Never silently drop a case to make the payload fit.
  IF v_context_bytes > v_settings.max_worker_context_bytes THEN
    v_array_limit := 1;
    v_string_limit := 180;
    v_compaction_tier := 'bounded-v1-tight';

    SELECT COALESCE(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
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
      'facts', ai_ops.compact_worker_json(sc.facts, v_array_limit, v_string_limit, 0),
      'responsibility_evidence', ai_ops.compact_worker_json(sc.responsibility_evidence, v_array_limit, v_string_limit, 0),
      'operational_context', ai_ops.compact_worker_json(sc.operational_context, v_array_limit, v_string_limit, 0),
      'trust', ai_ops.compact_worker_json(sc.trust, 1, 140, 0)
    )) ORDER BY sc.snapshot_rank), '[]'::JSONB)
    INTO v_cases
    FROM ai_ops.snapshot_cases sc
    WHERE sc.snapshot_id = v_snapshot.id;

    v_body := jsonb_set(v_body, '{cases}', v_cases, false);
    v_body := jsonb_set(
      v_body,
      '{snapshot,trust}',
      ai_ops.compact_worker_json(v_snapshot.trust, 1, 140, 0),
      false
    );
    v_body := jsonb_set(
      v_body,
      '{snapshot,company_pulse}',
      ai_ops.compact_worker_json(v_snapshot.company_pulse, 1, 160, 0),
      false
    );
    v_context_bytes := octet_length(convert_to(v_body::TEXT, 'UTF8'));
  END IF;

  IF v_context_bytes > v_settings.max_worker_context_bytes THEN
    UPDATE ai_ops.planner_runs
    SET
      status = 'partial',
      checkpoint = 'context_budget_blocked',
      heartbeat_at = v_now,
      lease_expires_at = NULL,
      error_class = 'context_budget_exceeded',
      error_message = format(
        'compacted worker context %s bytes exceeds limit %s',
        v_context_bytes,
        v_settings.max_worker_context_bytes
      ),
      result_summary = result_summary || jsonb_build_object(
        'snapshot_id', v_snapshot.id,
        'worker_context_bytes', v_context_bytes,
        'worker_context_limit_bytes', v_settings.max_worker_context_bytes,
        'worker_context_case_limit', v_context_case_limit,
        'worker_context_compaction_tier', v_compaction_tier,
        'worker_domain_count', v_capture_count,
        'worker_case_count', v_total_cases
      ),
      completed_at = v_now,
      updated_at = v_now
    WHERE id = p_run_id;

    RETURN jsonb_build_object(
      'blocked', true,
      'reason', 'context_budget_exceeded',
      'run_id', p_run_id,
      'snapshot_id', v_snapshot.id,
      'context_bytes', v_context_bytes,
      'context_limit_bytes', v_settings.max_worker_context_bytes,
      'context_case_limit', v_context_case_limit,
      'compaction_tier', v_compaction_tier
    );
  END IF;

  -- MD5 is deterministic payload identity only, never authentication.
  v_hash := md5(v_body::TEXT);

  UPDATE ai_ops.planner_runs
  SET
    status = 'reasoning',
    checkpoint = 'context_ready',
    heartbeat_at = v_now,
    lease_expires_at = v_now + interval '20 minutes',
    cases_seen = v_total_cases,
    result_summary = result_summary || jsonb_build_object(
      'snapshot_id', v_snapshot.id,
      'worker_context_hash', v_hash,
      'worker_context_hash_algorithm', 'md5-jsonb-identity',
      'worker_context_bytes', v_context_bytes,
      'worker_context_limit_bytes', v_settings.max_worker_context_bytes,
      'worker_context_case_limit', v_context_case_limit,
      'worker_context_compaction_tier', v_compaction_tier,
      'worker_domain_count', v_capture_count,
      'worker_case_count', v_total_cases,
      'multi_domain_context', true
    ),
    updated_at = v_now
  WHERE id = p_run_id;

  RETURN jsonb_build_object(
    'blocked', false,
    'context_hash', v_hash,
    'context_hash_algorithm', 'md5-jsonb-identity',
    'context_bytes', v_context_bytes,
    'context_limit_bytes', v_settings.max_worker_context_bytes,
    'context_case_limit', v_context_case_limit,
    'compaction_tier', v_compaction_tier,
    'context', v_body
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.worker_get_context(UUID,TEXT)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.worker_get_context(UUID,TEXT) IS
  'Canonical seven-domain worker context: byte-budget-aware fresh capture plus deterministic nested evidence compaction; preserves all selected frozen cases and fails closed above max_worker_context_bytes.';

RESET lock_timeout;
RESET statement_timeout;
