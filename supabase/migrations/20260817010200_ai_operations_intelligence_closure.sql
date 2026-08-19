-- ============================================================================
-- AI Operations — Intelligence Closure
--
-- Additive/fail-closed closure for:
--   * runtime reasoning policy + prompt identity
--   * cross-domain portfolio context + feedback memory
--   * conservative Case reconciliation
--   * staged human decision revision
--   * governed operational-context authoring/revocation
--
-- No business source table is mutated by reasoning/reconciliation/context reads.
-- Reviewed Work/ESCALATE execution remains behind the existing dispatcher.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

-- --------------------------------------------------------------------------
-- 1) Canonical management reasoning policy carried inside every worker context.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ai_ops.reasoning_policy_v1()
RETURNS JSONB
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'policy_id','ops-manager-v1',
    'purpose','choose a small number of high-value operational interventions from frozen trusted evidence',
    'principles',jsonb_build_array(
      'reality_before_activity',
      'deterministic_work_stays_deterministic',
      'cause_and_control_before_org_chart',
      'human_override_is_authoritative',
      'unknown_is_not_false',
      'minimise_interruption_cost',
      'existing_work_first',
      'no_employee_scoring',
      'explainability_without_sensitive_leakage'
    ),
    'responsibility_sequence',jsonb_build_array(
      'define_business_condition',
      'check_expected_or_governed_context',
      'identify_proximate_cause',
      'identify_current_control',
      'identify_business_accountability',
      'identify_execution_capability',
      'check_relationship_continuity',
      'check_authority',
      'check_availability_workload_and_location_fit',
      'check_existing_work_and_recent_activity'
    ),
    'action_quality_gate',jsonb_build_array(
      'fresh_trusted_evidence',
      'case_still_exists',
      'no_conflicting_human_context',
      'no_equivalent_active_work',
      'no_recent_action_already_addressing_condition',
      'active_plausible_accountable_owner',
      'capable_available_executor',
      'operationally_possible_timing',
      'business_value_exceeds_interruption_cost',
      'effort_fits_visible_commitments_without_invented_capacity',
      'no_customer_or_route_collision',
      'reversible_or_human_reviewed',
      'measurable_expected_outcome',
      'employee_safe_reason_only'
    ),
    'decision_preferences',jsonb_build_object(
      'zero_actions_is_valid',true,
      'prefer_monitor_or_investigate_when_uncertain',true,
      'prefer_existing_work_over_duplicate_creation',true,
      'manager_is_last_resort_routing',true,
      'never_invent_capacity_stock_credit_route_or_authority',true
    ),
    'effort_vocabulary',jsonb_build_object(
      'S','short / low interruption',
      'M','meaningful focus block',
      'L','substantial work requiring planning'
    )
  );
$$;
REVOKE ALL ON FUNCTION ai_ops.reasoning_policy_v1()
  FROM PUBLIC,anon,authenticated,service_role;

-- --------------------------------------------------------------------------
-- 2) Conservative Case lifecycle reconciliation.
-- A Case is resolved only when its domain capture is complete and explicitly
-- not truncated/budget exhausted. Ambiguity always leaves the Case open.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ai_ops.reconcile_cases_from_snapshot(p_snapshot_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_domain TEXT;
  v_capture ai_ops.snapshot_domain_captures%ROWTYPE;
  v_resolved INTEGER := 0;
  v_domain_resolved INTEGER := 0;
  v_eligible_domains INTEGER := 0;
  v_skipped_domains INTEGER := 0;
BEGIN
  SELECT * INTO v_snapshot
  FROM ai_ops.snapshots
  WHERE id=p_snapshot_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations snapshot not found'; END IF;

  FOREACH v_domain IN ARRAY ai_ops.required_operational_domains()
  LOOP
    SELECT * INTO v_capture
    FROM ai_ops.snapshot_domain_captures dc
    WHERE dc.snapshot_id=p_snapshot_id AND dc.domain=v_domain;

    IF NOT FOUND
       OR v_capture.capture_status <> 'completed'
       OR COALESCE((v_capture.metadata->>'has_more')::BOOLEAN,false)
       OR COALESCE((v_capture.metadata->>'global_budget_exhausted')::BOOLEAN,false)
       OR COALESCE((v_capture.metadata->>'budget_exhausted')::BOOLEAN,false)
       OR COALESCE((v_capture.metadata->>'candidate_budget_exhausted')::BOOLEAN,false)
       OR COALESCE((v_capture.metadata->>'source_partial')::BOOLEAN,false)
       OR COALESCE((v_capture.metadata->>'blocked')::BOOLEAN,false)
    THEN
      v_skipped_domains:=v_skipped_domains+1;
      CONTINUE;
    END IF;

    v_eligible_domains:=v_eligible_domains+1;

    UPDATE ai_ops.cases c
    SET
      status='resolved',
      resolved_at=COALESCE(c.resolved_at,v_snapshot.generated_at),
      state_version=c.state_version+1,
      updated_at=clock_timestamp()
    WHERE c.domain=v_domain
      AND c.status IN ('open','monitored','actioned')
      AND c.last_snapshot_id<>p_snapshot_id
      AND NOT EXISTS (
        SELECT 1
        FROM ai_ops.snapshot_cases sc
        WHERE sc.snapshot_id=p_snapshot_id AND sc.case_id=c.id
      );

    GET DIAGNOSTICS v_domain_resolved = ROW_COUNT;
    v_resolved:=v_resolved+v_domain_resolved;
  END LOOP;

  RETURN jsonb_build_object(
    'snapshot_id',p_snapshot_id,
    'resolved_cases',v_resolved,
    'eligible_domains',v_eligible_domains,
    'skipped_domains',v_skipped_domains,
    'fail_closed',true
  );
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.reconcile_cases_from_snapshot(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

-- --------------------------------------------------------------------------
-- 3) Bounded cross-domain portfolio context from frozen evidence + prior audit.
-- No productivity score and no arbitrary capacity threshold.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ai_ops.reasoning_portfolio_context(p_run_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_run ai_ops.planner_runs%ROWTYPE;
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_domains JSONB := '[]'::JSONB;
  v_cross_entity JSONB := '[]'::JSONB;
  v_feedback JSONB := '[]'::JSONB;
  v_previous_runs JSONB := '[]'::JSONB;
  v_open_ai_work JSONB := '{}'::JSONB;
BEGIN
  SELECT * INTO v_run FROM ai_ops.planner_runs WHERE id=p_run_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'planner run not found'; END IF;
  SELECT * INTO v_snapshot FROM ai_ops.snapshots WHERE run_id=p_run_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'planner snapshot not found'; END IF;

  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'domain'),'[]'::JSONB)
  INTO v_domains
  FROM (
    SELECT jsonb_build_object(
      'domain',dc.domain,
      'capture_status',dc.capture_status,
      'case_count',dc.case_count,
      'source_as_of',dc.source_as_of,
      'severity_counts',jsonb_build_object(
        'critical',count(*) FILTER (WHERE sc.severity='critical'),
        'high',count(*) FILTER (WHERE sc.severity='high'),
        'medium',count(*) FILTER (WHERE sc.severity='medium'),
        'low',count(*) FILTER (WHERE sc.severity='low')
      ),
      'existing_work_cases',count(*) FILTER (WHERE jsonb_typeof(sc.facts->'existing_active_work')='object'),
      'distinct_entities',count(DISTINCT sc.entity_id) FILTER (WHERE sc.entity_id IS NOT NULL)
    ) AS x
    FROM ai_ops.snapshot_domain_captures dc
    LEFT JOIN ai_ops.snapshot_cases sc
      ON sc.snapshot_id=dc.snapshot_id AND sc.domain=dc.domain
    WHERE dc.snapshot_id=v_snapshot.id
    GROUP BY dc.domain,dc.capture_status,dc.case_count,dc.source_as_of
  ) q;

  SELECT COALESCE(jsonb_agg(item ORDER BY domain_count DESC, case_count DESC),'[]'::JSONB)
  INTO v_cross_entity
  FROM (
    SELECT
      sc.entity_type,
      sc.entity_id,
      count(*)::INTEGER AS case_count,
      count(DISTINCT sc.domain)::INTEGER AS domain_count,
      jsonb_build_object(
        'entity_type',sc.entity_type,
        'entity_id',sc.entity_id,
        'domains',jsonb_agg(DISTINCT sc.domain),
        'case_count',count(*),
        'max_severity',CASE
          WHEN bool_or(sc.severity='critical') THEN 'critical'
          WHEN bool_or(sc.severity='high') THEN 'high'
          WHEN bool_or(sc.severity='medium') THEN 'medium'
          ELSE 'low'
        END
      ) AS item
    FROM ai_ops.snapshot_cases sc
    WHERE sc.snapshot_id=v_snapshot.id AND sc.entity_id IS NOT NULL
    GROUP BY sc.entity_type,sc.entity_id
    HAVING count(DISTINCT sc.domain)>1
    ORDER BY domain_count DESC,case_count DESC
    LIMIT 15
  ) q;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('reason',feedback_reason,'count',reason_count) ORDER BY reason_count DESC),'[]'::JSONB)
  INTO v_feedback
  FROM (
    SELECT df.feedback_reason,count(*)::INTEGER AS reason_count
    FROM ai_ops.decision_feedback df
    JOIN ai_ops.decisions d ON d.id=df.decision_id
    JOIN ai_ops.planner_runs r ON r.id=d.run_id
    WHERE df.created_at<v_snapshot.generated_at
      AND r.business_date>=v_run.business_date-30
    GROUP BY df.feedback_reason
    ORDER BY reason_count DESC
    LIMIT 12
  ) f;

  SELECT COALESCE(jsonb_agg(item ORDER BY scheduled_for DESC),'[]'::JSONB)
  INTO v_previous_runs
  FROM (
    SELECT r.scheduled_for,
      jsonb_build_object(
        'run_id',r.id,
        'run_type',r.run_type,
        'business_date',r.business_date,
        'status',r.status,
        'cases_seen',r.cases_seen,
        'decisions_count',r.decisions_count,
        'work_created_count',r.work_created_count,
        'result_summary',jsonb_strip_nulls(jsonb_build_object(
          'action_decisions',r.result_summary->'action_decisions',
          'human_rejected_decisions',r.result_summary->'human_rejected_decisions',
          'system_rejected_decisions',r.result_summary->'system_rejected_decisions',
          'blocked_work_commit',r.result_summary->'blocked_work_commit'
        ))
      ) AS item
    FROM ai_ops.planner_runs r
    WHERE r.id<>p_run_id AND r.scheduled_for<v_snapshot.generated_at
    ORDER BY r.scheduled_for DESC
    LIMIT 5
  ) q;

  SELECT jsonb_build_object(
    'active',count(*) FILTER (WHERE wi.status IN ('open','in_progress','waiting')),
    'overdue',count(*) FILTER (WHERE wi.status IN ('open','in_progress','waiting') AND wi.due_at<clock_timestamp()),
    'waiting',count(*) FILTER (WHERE wi.status='waiting')
  )
  INTO v_open_ai_work
  FROM public.work_items wi
  WHERE wi.source_kind='system'::public.work_source_kind
    AND wi.source_key LIKE 'ai_ops:decision:%'
    AND wi.created_at<v_snapshot.generated_at;

  RETURN jsonb_build_object(
    'as_of',v_snapshot.generated_at,
    'business_date',v_run.business_date,
    'domains',v_domains,
    'cross_domain_entities',v_cross_entity,
    'previous_runs',v_previous_runs,
    'human_feedback_30d',v_feedback,
    'previous_ai_work',COALESCE(v_open_ai_work,'{}'::JSONB),
    'interpretation_rules',jsonb_build_array(
      'portfolio context is planning evidence not employee scoring',
      'visible workload does not equal free capacity',
      'cross-domain collisions require integrated reasoning',
      'previous acceptance does not prove current action value',
      'previous rejection or wrong timing should reduce repetition unless new evidence exists'
    )
  );
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.reasoning_portfolio_context(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

-- --------------------------------------------------------------------------
-- 4) Wrap worker context: reconcile conservatively, add policy + portfolio,
-- then recompute the immutable run context identity over the final payload.
-- --------------------------------------------------------------------------
ALTER FUNCTION ai_ops.worker_get_context(UUID,TEXT)
  RENAME TO worker_get_context_pre_intelligence_closure_v1;
REVOKE ALL ON FUNCTION ai_ops.worker_get_context_pre_intelligence_closure_v1(UUID,TEXT)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.worker_get_context(p_run_id UUID,p_worker_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_result JSONB;
  v_context JSONB;
  v_snapshot_id UUID;
  v_policy JSONB;
  v_portfolio JSONB;
  v_reconciliation JSONB;
  v_hash TEXT;
  v_bytes INTEGER;
  v_limit INTEGER;
BEGIN
  v_result:=ai_ops.worker_get_context_pre_intelligence_closure_v1(p_run_id,p_worker_id);
  IF COALESCE((v_result->>'blocked')::BOOLEAN,false) THEN RETURN v_result; END IF;

  v_context:=v_result->'context';
  v_snapshot_id:=NULLIF(v_context->'snapshot'->>'snapshot_id','')::UUID;
  IF v_snapshot_id IS NULL THEN RAISE EXCEPTION 'worker context snapshot id missing'; END IF;

  v_reconciliation:=ai_ops.reconcile_cases_from_snapshot(v_snapshot_id);
  v_policy:=ai_ops.reasoning_policy_v1();
  v_portfolio:=ai_ops.reasoning_portfolio_context(p_run_id);

  v_context:=v_context || jsonb_build_object(
    'reasoning_policy',v_policy,
    'portfolio_context',v_portfolio,
    'feedback_memory',jsonb_build_object(
      'source','prior_human_feedback_and_prior_run_outcomes',
      'bounded',true,
      'employee_performance_signal',false
    )
  );

  SELECT max_worker_context_bytes INTO v_limit
  FROM ai_ops.settings WHERE singleton=true;
  v_bytes:=octet_length(convert_to(v_context::TEXT,'UTF8'));

  IF v_bytes>v_limit THEN
    UPDATE ai_ops.planner_runs
    SET status='partial',checkpoint='context_budget_blocked',lease_expires_at=NULL,
        error_class='context_budget_exceeded',
        error_message=format('intelligence closure context %s bytes exceeds limit %s',v_bytes,v_limit),
        result_summary=result_summary||jsonb_build_object(
          'worker_context_bytes',v_bytes,
          'worker_context_limit_bytes',v_limit,
          'intelligence_closure_context',true
        ),
        completed_at=clock_timestamp(),updated_at=clock_timestamp()
    WHERE id=p_run_id;
    RETURN jsonb_build_object(
      'blocked',true,'reason','context_budget_exceeded','run_id',p_run_id,
      'context_bytes',v_bytes,'context_limit_bytes',v_limit
    );
  END IF;

  v_hash:=md5(v_context::TEXT);
  UPDATE ai_ops.planner_runs
  SET result_summary=result_summary||jsonb_build_object(
        'worker_context_hash',v_hash,
        'worker_context_hash_algorithm','md5-jsonb-identity',
        'worker_context_bytes',v_bytes,
        'reasoning_policy_id',v_policy->>'policy_id',
        'portfolio_context',v_portfolio,
        'case_reconciliation',v_reconciliation,
        'intelligence_closure_context',true
      ),
      updated_at=clock_timestamp()
  WHERE id=p_run_id AND claimed_by=p_worker_id AND status='reasoning';

  RETURN jsonb_build_object(
    'blocked',false,
    'context_hash',v_hash,
    'context_hash_algorithm','md5-jsonb-identity',
    'context_bytes',v_bytes,
    'context_limit_bytes',v_limit,
    'context',v_context
  );
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.worker_get_context(UUID,TEXT)
  FROM PUBLIC,anon,authenticated,service_role;

-- --------------------------------------------------------------------------
-- 5) Extended decision-quality fields without rewriting the proven stage core.
-- The wrapper validates extra fields, strips them for the preserved core, then
-- enriches the newly staged decision rows before deterministic validation.
-- --------------------------------------------------------------------------
ALTER FUNCTION ai_ops.worker_stage_decisions(UUID,TEXT,TEXT,JSONB)
  RENAME TO worker_stage_decisions_pre_intelligence_closure_v1;
REVOKE ALL ON FUNCTION ai_ops.worker_stage_decisions_pre_intelligence_closure_v1(UUID,TEXT,TEXT,JSONB)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.worker_stage_decisions(
  p_run_id UUID,p_worker_id TEXT,p_context_hash TEXT,p_decisions JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_item JSONB;
  v_base JSONB := '[]'::JSONB;
  v_result JSONB;
  v_case_id UUID;
  v_type TEXT;
  v_impact TEXT;
  v_urgency TEXT;
  v_reversibility TEXT;
  v_effort TEXT;
  v_evidence NUMERIC;
  v_signal TEXT;
  v_safe_reason TEXT;
BEGIN
  IF jsonb_typeof(p_decisions)<>'array' THEN RAISE EXCEPTION 'decisions payload must be a JSON array'; END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_decisions)
  LOOP
    v_type:=v_item->>'decision_type';
    v_impact:=NULLIF(v_item->>'business_impact','');
    v_urgency:=NULLIF(v_item->>'urgency','');
    v_reversibility:=NULLIF(v_item->>'reversibility','');
    v_effort:=NULLIF(v_item->>'estimated_effort','');
    v_evidence:=NULLIF(v_item->>'evidence_completeness','')::NUMERIC;
    v_signal:=NULLIF(btrim(COALESCE(v_item->>'success_signal','')),'');
    v_safe_reason:=NULLIF(btrim(COALESCE(v_item->>'employee_safe_reason','')),'');

    IF v_impact IS NOT NULL AND v_impact NOT IN ('low','medium','high','critical') THEN RAISE EXCEPTION 'invalid business_impact'; END IF;
    IF v_urgency IS NOT NULL AND v_urgency NOT IN ('low','normal','high','immediate') THEN RAISE EXCEPTION 'invalid urgency'; END IF;
    IF v_reversibility IS NOT NULL AND v_reversibility NOT IN ('reversible','review_required','sensitive') THEN RAISE EXCEPTION 'invalid reversibility'; END IF;
    IF v_effort IS NOT NULL AND v_effort NOT IN ('S','M','L') THEN RAISE EXCEPTION 'invalid estimated_effort'; END IF;
    IF v_evidence IS NOT NULL AND (v_evidence<0 OR v_evidence>1) THEN RAISE EXCEPTION 'invalid evidence_completeness'; END IF;
    IF length(COALESCE(v_signal,''))>800 OR length(COALESCE(v_safe_reason,''))>800 THEN RAISE EXCEPTION 'extended decision text exceeds limit'; END IF;

    IF v_type IN ('CREATE_WORK','ESCALATE') AND (
      v_impact IS NULL OR v_urgency IS NULL OR v_reversibility IS NULL OR
      v_effort IS NULL OR v_evidence IS NULL OR v_signal IS NULL OR v_safe_reason IS NULL
    ) THEN
      RAISE EXCEPTION 'action decisions require impact, urgency, reversibility, effort, evidence completeness, success signal and employee-safe reason';
    END IF;

    v_base:=v_base||jsonb_build_array(
      v_item - 'business_impact' - 'urgency' - 'evidence_completeness'
             - 'reversibility' - 'estimated_effort' - 'success_signal'
             - 'employee_safe_reason'
    );
  END LOOP;

  v_result:=ai_ops.worker_stage_decisions_pre_intelligence_closure_v1(
    p_run_id,p_worker_id,p_context_hash,v_base
  );

  IF COALESCE((v_result->>'staged')::BOOLEAN,false) THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_decisions)
    LOOP
      v_case_id:=(v_item->>'case_id')::UUID;
      UPDATE ai_ops.decisions d
      SET
        business_impact=NULLIF(v_item->>'business_impact',''),
        urgency=NULLIF(v_item->>'urgency',''),
        evidence_completeness=NULLIF(v_item->>'evidence_completeness','')::NUMERIC,
        reversibility=NULLIF(v_item->>'reversibility',''),
        estimated_effort=NULLIF(v_item->>'estimated_effort',''),
        success_signal=CASE
          WHEN NULLIF(btrim(COALESCE(v_item->>'success_signal','')),'') IS NULL THEN '{}'::JSONB
          ELSE jsonb_build_object('signal',btrim(v_item->>'success_signal'))
        END,
        employee_safe_reason=NULLIF(btrim(COALESCE(v_item->>'employee_safe_reason','')),''),
        management_only_metadata=d.management_only_metadata||jsonb_build_object(
          'decision_quality_contract','ops-manager-v1'
        ),
        updated_at=clock_timestamp()
      WHERE d.run_id=p_run_id AND d.case_id=v_case_id;
    END LOOP;
  END IF;

  RETURN v_result||jsonb_build_object('decision_quality_contract','ops-manager-v1');
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.worker_stage_decisions(UUID,TEXT,TEXT,JSONB)
  FROM PUBLIC,anon,authenticated,service_role;

-- --------------------------------------------------------------------------
-- 6) Service-role-only prompt identity binding for exact runtime audit.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_ops_worker_bind_prompt(
  p_run_id UUID,p_worker_id TEXT,p_prompt_version TEXT,p_prompt_hash TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_run ai_ops.planner_runs%ROWTYPE;
BEGIN
  IF current_user NOT IN ('postgres','service_role') THEN
    RAISE EXCEPTION 'service role required' USING ERRCODE='42501';
  END IF;
  IF NULLIF(btrim(COALESCE(p_prompt_version,'')),'') IS NULL
     OR p_prompt_hash !~ '^[a-f0-9]{64}$' THEN
    RAISE EXCEPTION 'invalid prompt identity';
  END IF;

  SELECT * INTO v_run FROM ai_ops.planner_runs WHERE id=p_run_id FOR UPDATE;
  IF NOT FOUND OR v_run.claimed_by IS DISTINCT FROM p_worker_id
     OR v_run.status NOT IN ('claimed','reasoning')
     OR v_run.lease_expires_at IS NULL OR v_run.lease_expires_at<=clock_timestamp() THEN
    RAISE EXCEPTION 'worker lease is not valid for prompt binding';
  END IF;

  IF v_run.prompt_hash IS NOT NULL AND (
    v_run.prompt_hash IS DISTINCT FROM p_prompt_hash OR
    v_run.prompt_version IS DISTINCT FROM p_prompt_version
  ) THEN
    RAISE EXCEPTION 'run prompt identity is already bound to a different contract';
  END IF;

  UPDATE ai_ops.planner_runs
  SET prompt_version=p_prompt_version,prompt_hash=p_prompt_hash,
      result_summary=result_summary||jsonb_build_object(
        'prompt_version',p_prompt_version,'prompt_hash',p_prompt_hash,'prompt_hash_algorithm','sha256'
      ),updated_at=clock_timestamp()
  WHERE id=p_run_id;

  RETURN jsonb_build_object('bound',true,'run_id',p_run_id,'prompt_version',p_prompt_version,'prompt_hash',p_prompt_hash);
END;
$$;
REVOKE ALL ON FUNCTION public.ai_ops_worker_bind_prompt(UUID,TEXT,TEXT,TEXT)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ai_ops_worker_bind_prompt(UUID,TEXT,TEXT,TEXT)
  TO service_role;

-- --------------------------------------------------------------------------
-- 7) Management-only pre-review decision correction.
-- Revision is in-place to preserve one-decision-per-case run cardinality.
-- Previous editable state is stored in bounded management-only history.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_ops_revise_staged_decision(
  p_decision_id UUID,p_patch JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_decision ai_ops.decisions%ROWTYPE;
  v_run ai_ops.planner_runs%ROWTYPE;
  v_history JSONB;
  v_history_item JSONB;
  v_issues JSONB;
  v_owner UUID;
  v_assignee UUID;
  v_due TIMESTAMPTZ;
  v_next TEXT;
  v_outcome TEXT;
  v_safe TEXT;
BEGIN
  IF v_actor IS NULL OR NOT private.work_actor_is_active(v_actor)
     OR NOT COALESCE(public.check_permission(v_actor,'work.policies.manage'),false) THEN
    RAISE EXCEPTION 'not authorised to revise AI Operations decisions' USING ERRCODE='42501';
  END IF;
  IF jsonb_typeof(p_patch)<>'object' THEN RAISE EXCEPTION 'revision patch must be an object'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_patch) k WHERE k NOT IN (
    'recommended_owner_user_id','recommended_assignee_user_id','due_at',
    'next_action_text','expected_outcome','employee_safe_reason'
  )) THEN RAISE EXCEPTION 'revision patch contains unsupported fields'; END IF;

  SELECT * INTO v_decision FROM ai_ops.decisions WHERE id=p_decision_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations decision not found'; END IF;
  SELECT * INTO v_run FROM ai_ops.planner_runs WHERE id=v_decision.run_id FOR UPDATE;
  IF NOT FOUND OR v_run.status<>'staged' THEN RAISE EXCEPTION 'decision run is not reviewable'; END IF;
  IF EXISTS (SELECT 1 FROM ai_ops.decision_reviews WHERE decision_id=p_decision_id) THEN
    RAISE EXCEPTION 'reviewed decision is immutable; wait for a new planner decision';
  END IF;
  IF v_decision.commit_status='committed' THEN RAISE EXCEPTION 'committed decision cannot be revised'; END IF;
  IF v_decision.decision_type NOT IN ('CREATE_WORK','ESCALATE') THEN
    RAISE EXCEPTION 'only actionable staged decisions can be revised';
  END IF;

  v_owner:=CASE WHEN p_patch ? 'recommended_owner_user_id' THEN NULLIF(p_patch->>'recommended_owner_user_id','')::UUID ELSE v_decision.recommended_owner_user_id END;
  v_assignee:=CASE WHEN p_patch ? 'recommended_assignee_user_id' THEN NULLIF(p_patch->>'recommended_assignee_user_id','')::UUID ELSE v_decision.recommended_assignee_user_id END;
  v_due:=CASE WHEN p_patch ? 'due_at' THEN NULLIF(p_patch->>'due_at','')::TIMESTAMPTZ ELSE v_decision.due_at END;
  v_next:=CASE WHEN p_patch ? 'next_action_text' THEN NULLIF(btrim(p_patch->>'next_action_text'),'') ELSE v_decision.next_action_text END;
  v_outcome:=CASE WHEN p_patch ? 'expected_outcome' THEN NULLIF(btrim(p_patch->>'expected_outcome'),'') ELSE v_decision.expected_outcome END;
  v_safe:=CASE WHEN p_patch ? 'employee_safe_reason' THEN NULLIF(btrim(p_patch->>'employee_safe_reason'),'') ELSE v_decision.employee_safe_reason END;

  IF v_decision.decision_type='CREATE_WORK' AND (
    v_owner IS NULL OR v_assignee IS NULL OR v_due IS NULL OR v_due<=clock_timestamp()
    OR v_next IS NULL OR v_outcome IS NULL
  ) THEN RAISE EXCEPTION 'revised CREATE_WORK must remain executable'; END IF;
  IF v_owner IS NOT NULL AND NOT private.work_actor_is_active(v_owner) THEN RAISE EXCEPTION 'revised owner is unavailable'; END IF;
  IF v_assignee IS NOT NULL AND NOT private.work_actor_is_active(v_assignee) THEN RAISE EXCEPTION 'revised assignee is unavailable'; END IF;
  IF length(COALESCE(v_next,''))>500 OR length(COALESCE(v_outcome,''))>1000 OR length(COALESCE(v_safe,''))>800 THEN
    RAISE EXCEPTION 'revised text exceeds contract limit';
  END IF;

  v_history:=COALESCE(v_decision.management_only_metadata->'revision_history','[]'::JSONB);
  IF jsonb_typeof(v_history)<>'array' THEN v_history:='[]'::JSONB; END IF;
  v_history_item:=jsonb_build_object(
    'revision',v_decision.revision,
    'revised_at',clock_timestamp(),
    'revised_by_user_id',v_actor,
    'recommended_owner_user_id',v_decision.recommended_owner_user_id,
    'recommended_assignee_user_id',v_decision.recommended_assignee_user_id,
    'due_at',v_decision.due_at,
    'next_action_text',v_decision.next_action_text,
    'expected_outcome',v_decision.expected_outcome,
    'employee_safe_reason',v_decision.employee_safe_reason
  );
  v_history:=CASE WHEN jsonb_array_length(v_history)>=10 THEN (SELECT jsonb_agg(value) FROM jsonb_array_elements(v_history) WITH ORDINALITY e(value,n) WHERE n>jsonb_array_length(v_history)-9) ELSE v_history END;
  v_history:=COALESCE(v_history,'[]'::JSONB)||jsonb_build_array(v_history_item);

  UPDATE ai_ops.decisions
  SET revision=revision+1,
      recommended_owner_user_id=v_owner,
      recommended_assignee_user_id=v_assignee,
      due_at=v_due,
      next_action_text=v_next,
      expected_outcome=v_outcome,
      employee_safe_reason=v_safe,
      validation_state='pending',validated_at=NULL,validated_by_user_id=NULL,
      commit_status='staged',
      validation_detail=jsonb_build_object('requires_human_review',true,'stage_only',true,'human_revision',true),
      management_only_metadata=management_only_metadata||jsonb_build_object(
        'revision_history',v_history,
        'last_revised_by_user_id',v_actor,
        'last_revised_at',clock_timestamp()
      ),updated_at=clock_timestamp()
  WHERE id=p_decision_id
  RETURNING * INTO v_decision;

  v_issues:=ai_ops.current_decision_issues(p_decision_id);
  UPDATE ai_ops.decisions
  SET validation_state=CASE WHEN jsonb_array_length(v_issues)=0 THEN 'validated' ELSE 'rejected' END,
      validation_detail=validation_detail||jsonb_build_object(
        'revision_validation_codes',v_issues,
        'revision_revalidated_at',clock_timestamp()
      ),validated_at=clock_timestamp(),updated_at=clock_timestamp()
  WHERE id=p_decision_id;

  RETURN jsonb_build_object(
    'revised',true,'old_decision_id',p_decision_id,'decision_id',p_decision_id,
    'revision',v_decision.revision,
    'validation_state',CASE WHEN jsonb_array_length(v_issues)=0 THEN 'validated' ELSE 'rejected' END,
    'validation_codes',v_issues,'execution_performed',false
  );
END;
$$;
REVOKE ALL ON FUNCTION public.ai_ops_revise_staged_decision(UUID,JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ai_ops_revise_staged_decision(UUID,JSONB) TO authenticated,service_role;

-- --------------------------------------------------------------------------
-- 8) Governed operational-context authoring and revocation.
-- Narrow subject types avoid arbitrary entity references or dynamic SQL.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_ops_create_operational_context(
  p_subject_type TEXT,p_subject_id UUID,p_context_type TEXT,p_summary TEXT,
  p_owner_user_id UUID DEFAULT NULL,p_lifecycle_type TEXT DEFAULT 'valid_until',
  p_valid_until TIMESTAMPTZ DEFAULT NULL,p_review_on DATE DEFAULT NULL,
  p_visibility TEXT DEFAULT 'management'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_context ai_ops.operational_context%ROWTYPE;
  v_summary TEXT:=NULLIF(btrim(COALESCE(p_summary,'')),'');
  v_exists BOOLEAN:=false;
BEGIN
  IF v_actor IS NULL OR NOT private.work_actor_is_active(v_actor)
     OR NOT COALESCE(public.check_permission(v_actor,'work.policies.manage'),false) THEN
    RAISE EXCEPTION 'not authorised to create AI Operations context' USING ERRCODE='42501';
  END IF;
  IF p_subject_type NOT IN ('customer','employee','sales_order','work_item','product') THEN RAISE EXCEPTION 'unsupported context subject type'; END IF;
  IF p_subject_id IS NULL OR p_context_type !~ '^[a-z][a-z0-9_]{0,98}$' OR v_summary IS NULL OR length(v_summary)>500 THEN
    RAISE EXCEPTION 'invalid operational context payload';
  END IF;
  IF p_lifecycle_type NOT IN ('permanent','valid_until','review_on','one_time') THEN RAISE EXCEPTION 'invalid context lifecycle'; END IF;
  IF p_visibility NOT IN ('management','standard') THEN RAISE EXCEPTION 'restricted context authoring requires a separate sensitive-data workflow'; END IF;
  IF p_lifecycle_type='valid_until' AND (p_valid_until IS NULL OR p_valid_until<=clock_timestamp()) THEN RAISE EXCEPTION 'valid_until context requires a future end'; END IF;
  IF p_lifecycle_type='review_on' AND (p_review_on IS NULL OR p_review_on<(clock_timestamp() AT TIME ZONE 'Africa/Cairo')::DATE) THEN RAISE EXCEPTION 'review_on context requires a current/future review date'; END IF;
  IF p_owner_user_id IS NOT NULL AND NOT private.work_actor_is_active(p_owner_user_id) THEN RAISE EXCEPTION 'context owner is unavailable'; END IF;

  IF p_subject_type='customer' THEN SELECT EXISTS(SELECT 1 FROM public.customers WHERE id=p_subject_id) INTO v_exists;
  ELSIF p_subject_type='employee' THEN SELECT EXISTS(SELECT 1 FROM public.profiles WHERE id=p_subject_id) INTO v_exists;
  ELSIF p_subject_type='sales_order' THEN SELECT EXISTS(SELECT 1 FROM public.sales_orders WHERE id=p_subject_id) INTO v_exists;
  ELSIF p_subject_type='work_item' THEN SELECT EXISTS(SELECT 1 FROM public.work_items WHERE id=p_subject_id) INTO v_exists;
  ELSIF p_subject_type='product' THEN SELECT EXISTS(SELECT 1 FROM public.products WHERE id=p_subject_id) INTO v_exists;
  END IF;
  IF NOT v_exists THEN RAISE EXCEPTION 'context subject does not exist'; END IF;

  INSERT INTO ai_ops.operational_context(
    subject_type,subject_id,context_type,context_payload,owner_user_id,
    source_type,confidence_class,lifecycle_type,valid_from,valid_until,review_on,
    status,visibility,created_by_user_id,approved_by_user_id
  ) VALUES (
    p_subject_type,p_subject_id,p_context_type,jsonb_build_object('summary',v_summary),p_owner_user_id,
    'human','approved_human',p_lifecycle_type,clock_timestamp(),
    CASE WHEN p_lifecycle_type='valid_until' THEN p_valid_until ELSE NULL END,
    CASE WHEN p_lifecycle_type='review_on' THEN p_review_on ELSE NULL END,
    'active',p_visibility,v_actor,v_actor
  ) RETURNING * INTO v_context;

  RETURN jsonb_build_object(
    'created',true,'context_id',v_context.id,'subject_type',v_context.subject_type,
    'subject_id',v_context.subject_id,'context_type',v_context.context_type,
    'valid_until',v_context.valid_until,'status',v_context.status
  );
END;
$$;
REVOKE ALL ON FUNCTION public.ai_ops_create_operational_context(TEXT,UUID,TEXT,TEXT,UUID,TEXT,TIMESTAMPTZ,DATE,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ai_ops_create_operational_context(TEXT,UUID,TEXT,TEXT,UUID,TEXT,TIMESTAMPTZ,DATE,TEXT) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.ai_ops_revoke_operational_context(p_context_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_context ai_ops.operational_context%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT private.work_actor_is_active(v_actor)
     OR NOT COALESCE(public.check_permission(v_actor,'work.policies.manage'),false) THEN
    RAISE EXCEPTION 'not authorised to revoke AI Operations context' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_context FROM ai_ops.operational_context WHERE id=p_context_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'operational context not found'; END IF;
  IF v_context.status='revoked' THEN RETURN jsonb_build_object('revoked',true,'idempotent_reuse',true,'context_id',v_context.id,'status','revoked'); END IF;
  IF v_context.status<>'active' THEN RETURN jsonb_build_object('revoked',false,'blocked',true,'reason','context_not_active','context_id',v_context.id,'status',v_context.status); END IF;

  UPDATE ai_ops.operational_context
  SET status='revoked',updated_at=clock_timestamp()
  WHERE id=p_context_id RETURNING * INTO v_context;

  RETURN jsonb_build_object('revoked',true,'idempotent_reuse',false,'context_id',v_context.id,'status',v_context.status);
END;
$$;
REVOKE ALL ON FUNCTION public.ai_ops_revoke_operational_context(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ai_ops_revoke_operational_context(UUID) TO authenticated,service_role;

COMMENT ON FUNCTION ai_ops.reasoning_policy_v1() IS
  'Canonical bounded management reasoning policy carried in every worker context.';
COMMENT ON FUNCTION ai_ops.reconcile_cases_from_snapshot(UUID) IS
  'Conservative case closure. Resolves only from complete non-truncated domain captures; uncertainty fails open.';
COMMENT ON FUNCTION ai_ops.reasoning_portfolio_context(UUID) IS
  'Cross-domain management portfolio built from frozen evidence and bounded prior outcomes/feedback; never an employee score.';
COMMENT ON FUNCTION public.ai_ops_revise_staged_decision(UUID,JSONB) IS
  'Management-only pre-review correction of a staged actionable decision. Increments revision, preserves bounded prior state, revalidates, never executes.';
COMMENT ON FUNCTION public.ai_ops_create_operational_context(TEXT,UUID,TEXT,TEXT,UUID,TEXT,TIMESTAMPTZ,DATE,TEXT) IS
  'Management-only governed business context authoring for supported operational subjects.';

RESET lock_timeout;
RESET statement_timeout;
