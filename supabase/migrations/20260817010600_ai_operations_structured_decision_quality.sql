-- ============================================================================
-- AI Operations — structured decision quality runtime
--
-- Completes the designed decision-quality fields without weakening the existing
-- canonical staging/idempotency lifecycle. The preserved staging implementation
-- continues to own cardinality, action budget, frozen Case membership, active
-- actor checks and exact core-submission retries. This outer layer adds a second
-- immutable quality hash and persists bounded planning-quality attributes.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

-- --------------------------------------------------------------------------
-- Future runs explicitly freeze the prompt version selected by settings.
-- Existing historical runs keep their original prompt_version for replay.
-- --------------------------------------------------------------------------
ALTER TABLE ai_ops.settings
  ADD COLUMN prompt_version TEXT NOT NULL DEFAULT 'v1';
ALTER TABLE ai_ops.settings
  ADD CONSTRAINT ai_ops_settings_prompt_version_not_blank CHECK (btrim(prompt_version) <> '');

-- v2 extends the already approved v1 policy; it does not rewrite historical v1.
WITH extension(text_value) AS (
  VALUES ($quality$

STRUCTURED DECISION QUALITY
For CREATE_WORK and ESCALATE, also return these bounded fields:
- business_impact: one of low, medium, high, critical. This is a qualitative planning label, not an employee score.
- urgency: one of low, normal, high, immediate. Severity alone does not determine urgency.
- evidence_completeness: a number from 0 to 1 reflecting how complete the supplied evidence is; do not fabricate precision.
- reversibility: one of reversible, review_required, sensitive.
- estimated_effort: S, M or L only. S=short/low interruption, M=meaningful focus block, L=substantial planned work. Do not invent minutes.
- success_signal: a short observable business result that would show whether the intervention worked.
- employee_safe_reason: the minimum non-sensitive reason the employee needs to execute the Work.

These fields explain and constrain a proposed action; they never override deterministic validation, permissions, human approval or current-state checks.
The complete allowed output fields are: case_id, decision_type, concise_rationale, confidence, recommended_owner_user_id, recommended_assignee_user_id, responsibility_summary, why_this_owner, why_now, expected_outcome, next_action_text, due_at, review_after, business_impact, urgency, evidence_completeness, reversibility, estimated_effort, success_signal, employee_safe_reason.
$quality$)
)
INSERT INTO ai_ops.planner_policies(
  policy_version,prompt_version,enabled,system_prompt,methodology,prompt_hash,created_at,updated_at
)
SELECT
  p.policy_version,'v2',true,p.system_prompt||e.text_value,
  p.methodology || jsonb_build_object(
    'structured_decision_quality',true,
    'effort_vocabulary',jsonb_build_array('S','M','L'),
    'quality_fields_are_planning_labels_not_scores',true,
    'action_quality_fields_required',jsonb_build_array(
      'business_impact','urgency','evidence_completeness','reversibility',
      'estimated_effort','success_signal','employee_safe_reason'
    )
  ),
  md5(p.system_prompt||e.text_value),clock_timestamp(),clock_timestamp()
FROM ai_ops.planner_policies p
CROSS JOIN extension e
WHERE p.policy_version='v1' AND p.prompt_version='v1'
ON CONFLICT (policy_version,prompt_version) DO NOTHING;

UPDATE ai_ops.settings
SET prompt_version='v2',updated_at=clock_timestamp()
WHERE singleton=true;

-- Policy content is append-only after v2 is seeded. Version changes create a new
-- row; operational emergency control remains planner_enabled/shadow_mode.
CREATE OR REPLACE FUNCTION ai_ops.reject_planner_policy_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'AI planner policy versions are immutable; create a new prompt version';
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.reject_planner_policy_mutation() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER trg_ai_ops_planner_policies_immutable
  BEFORE UPDATE OR DELETE ON ai_ops.planner_policies
  FOR EACH ROW EXECUTE FUNCTION ai_ops.reject_planner_policy_mutation();

-- Materialize future expected runs with the exact configured prompt version.
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

  IF NOT EXISTS (
    SELECT 1 FROM ai_ops.planner_policies p
    WHERE p.policy_version=v_settings.planner_policy_version
      AND p.prompt_version=v_settings.prompt_version
      AND p.enabled=true
  ) THEN
    RAISE EXCEPTION 'configured AI planner policy/prompt version is not registered';
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
            planner_policy_version,tool_contract_version,prompt_version
          ) VALUES (
            v_schedule.code||':'||v_local_day::TEXT,v_schedule.id,v_schedule.run_type,
            v_local_day,v_scheduled_for,'pending','created',
            v_settings.planner_policy_version,v_settings.tool_contract_version,v_settings.prompt_version
          ) ON CONFLICT(run_key) DO NOTHING;
          IF FOUND THEN v_inserted:=v_inserted+1; END IF;
        END IF;
      END IF;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object(
    'materialized',v_inserted,'planner_enabled',true,'checked_at',p_now,
    'planner_policy_version',v_settings.planner_policy_version,
    'prompt_version',v_settings.prompt_version
  );
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.materialize_due_runs(TIMESTAMPTZ)
  FROM PUBLIC,anon,authenticated,service_role;

-- --------------------------------------------------------------------------
-- Preserve the complete canonical staging/retry/lifecycle function.
-- --------------------------------------------------------------------------
ALTER FUNCTION ai_ops.worker_stage_decisions(UUID,TEXT,TEXT,JSONB)
  RENAME TO worker_stage_decisions_pre_structured_quality_v1;
REVOKE ALL ON FUNCTION ai_ops.worker_stage_decisions_pre_structured_quality_v1(UUID,TEXT,TEXT,JSONB)
  FROM PUBLIC,anon,authenticated,service_role;

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
  v_core JSONB:='[]'::JSONB;
  v_item JSONB;
  v_core_item JSONB;
  v_quality_hash TEXT;
  v_existing_quality_hash TEXT;
  v_result JSONB;
  v_decision_id UUID;
  v_case_id UUID;
  v_decision_type TEXT;
  v_impact TEXT;
  v_urgency TEXT;
  v_evidence NUMERIC;
  v_reversibility TEXT;
  v_effort TEXT;
  v_success TEXT;
  v_employee_reason TEXT;
  v_now TIMESTAMPTZ:=clock_timestamp();
BEGIN
  IF jsonb_typeof(p_decisions)<>'array' THEN
    RAISE EXCEPTION 'decisions payload must be a JSON array';
  END IF;

  SELECT * INTO v_run FROM ai_ops.planner_runs WHERE id=p_run_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'planner run not found'; END IF;

  -- Reject every field not explicitly covered by the combined core+quality contract.
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_decisions) item,
         LATERAL jsonb_object_keys(item) field_name
    WHERE field_name NOT IN (
      'case_id','decision_type','concise_rationale','confidence',
      'recommended_owner_user_id','recommended_assignee_user_id',
      'responsibility_summary','why_this_owner','why_now',
      'expected_outcome','next_action_text','due_at','review_after',
      'business_impact','urgency','evidence_completeness','reversibility',
      'estimated_effort','success_signal','employee_safe_reason'
    )
  ) THEN
    RAISE EXCEPTION 'decision payload contains unsupported quality fields';
  END IF;

  -- Validate qualitative labels without turning them into automatic business rules.
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_decisions) item
    WHERE (item ? 'business_impact' AND item->>'business_impact' NOT IN ('low','medium','high','critical'))
       OR (item ? 'urgency' AND item->>'urgency' NOT IN ('low','normal','high','immediate'))
       OR (item ? 'reversibility' AND item->>'reversibility' NOT IN ('reversible','review_required','sensitive'))
       OR (item ? 'estimated_effort' AND item->>'estimated_effort' NOT IN ('S','M','L'))
       OR (item ? 'evidence_completeness' AND (
            COALESCE((item->>'evidence_completeness')::NUMERIC,-1)<0
            OR COALESCE((item->>'evidence_completeness')::NUMERIC,-1)>1
          ))
       OR length(COALESCE(item->>'success_signal',''))>500
       OR length(COALESCE(item->>'employee_safe_reason',''))>500
  ) THEN
    RAISE EXCEPTION 'decision structured quality payload is invalid';
  END IF;

  -- Consequential actions must make their quality assumptions explicit. There is
  -- deliberately no confidence/evidence threshold here; absence is unsafe, but a
  -- fake numerical cutoff would encode policy that the business has not approved.
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_decisions) item
    WHERE item->>'decision_type' IN ('CREATE_WORK','ESCALATE')
      AND (
        NULLIF(item->>'business_impact','') IS NULL
        OR NULLIF(item->>'urgency','') IS NULL
        OR NULLIF(item->>'evidence_completeness','') IS NULL
        OR NULLIF(item->>'reversibility','') IS NULL
        OR NULLIF(item->>'estimated_effort','') IS NULL
        OR NULLIF(btrim(COALESCE(item->>'success_signal','')),'') IS NULL
        OR NULLIF(btrim(COALESCE(item->>'employee_safe_reason','')),'') IS NULL
      )
  ) THEN
    RAISE EXCEPTION 'action decisions require complete structured quality fields';
  END IF;

  -- Strip quality attributes before delegating to the existing canonical staging
  -- function so its historical core hash/idempotency semantics remain unchanged.
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_decisions)
  LOOP
    v_core_item:=v_item
      - 'business_impact' - 'urgency' - 'evidence_completeness'
      - 'reversibility' - 'estimated_effort' - 'success_signal'
      - 'employee_safe_reason';
    v_core:=v_core||jsonb_build_array(v_core_item);
  END LOOP;

  v_quality_hash:=md5(p_decisions::TEXT);
  v_existing_quality_hash:=NULLIF(v_run.result_summary->>'worker_quality_submission_hash','');

  -- A durable retry must replay both the existing core submission and the exact
  -- quality envelope. Legacy rows without a quality hash may only replay a payload
  -- with no quality keys; branch acceptance starts new runs on v2.
  IF v_run.status IN ('staged','completed','partial') AND v_existing_quality_hash IS NOT NULL
     AND v_existing_quality_hash IS DISTINCT FROM v_quality_hash THEN
    RAISE EXCEPTION 'staged retry quality payload does not match the persisted submission';
  END IF;

  IF v_run.status IN ('staged','completed','partial') AND v_existing_quality_hash IS NULL
     AND EXISTS (
       SELECT 1 FROM jsonb_array_elements(p_decisions) item
       WHERE item ?| ARRAY[
         'business_impact','urgency','evidence_completeness','reversibility',
         'estimated_effort','success_signal','employee_safe_reason'
       ]
     ) THEN
    RAISE EXCEPTION 'legacy staged run cannot acquire new quality fields during retry';
  END IF;

  v_result:=ai_ops.worker_stage_decisions_pre_structured_quality_v1(
    p_run_id,p_worker_id,p_context_hash,v_core
  );

  -- First submission: enrich each newly staged decision from the exact Case entry.
  IF v_existing_quality_hash IS NULL AND jsonb_array_length(p_decisions)>0 THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_decisions)
    LOOP
      v_case_id:=(v_item->>'case_id')::UUID;
      v_decision_type:=v_item->>'decision_type';
      v_impact:=NULLIF(v_item->>'business_impact','');
      v_urgency:=NULLIF(v_item->>'urgency','');
      v_evidence:=NULLIF(v_item->>'evidence_completeness','')::NUMERIC;
      v_reversibility:=NULLIF(v_item->>'reversibility','');
      v_effort:=NULLIF(v_item->>'estimated_effort','');
      v_success:=NULLIF(btrim(COALESCE(v_item->>'success_signal','')),'');
      v_employee_reason:=NULLIF(btrim(COALESCE(v_item->>'employee_safe_reason','')),'');

      SELECT d.id INTO v_decision_id
      FROM ai_ops.decisions d
      WHERE d.run_id=p_run_id AND d.case_id=v_case_id AND d.revision=1
      ORDER BY d.created_at DESC,d.id DESC
      LIMIT 1;
      IF v_decision_id IS NULL THEN
        RAISE EXCEPTION 'staged decision row missing for structured quality enrichment';
      END IF;

      UPDATE ai_ops.decisions
      SET
        business_impact=v_impact,
        urgency=v_urgency,
        evidence_completeness=v_evidence,
        reversibility=v_reversibility,
        estimated_effort=v_effort,
        success_signal=CASE WHEN v_success IS NULL THEN '{}'::JSONB ELSE jsonb_build_object('summary',v_success) END,
        employee_safe_reason=v_employee_reason,
        management_only_metadata=COALESCE(management_only_metadata,'{}'::JSONB)||jsonb_build_object(
          'worker_quality_submission_hash',v_quality_hash,
          'structured_decision_quality',true,
          'quality_labels_are_planning_not_employee_scores',true
        ),
        updated_at=v_now
      WHERE id=v_decision_id;
    END LOOP;
  END IF;

  UPDATE ai_ops.planner_runs
  SET
    result_summary=result_summary||jsonb_build_object(
      'worker_quality_submission_hash',COALESCE(v_existing_quality_hash,v_quality_hash),
      'structured_decision_quality',true,
      'quality_prompt_version','v2'
    ),
    updated_at=v_now
  WHERE id=p_run_id;

  RETURN v_result||jsonb_build_object(
    'quality_submission_hash',COALESCE(v_existing_quality_hash,v_quality_hash),
    'structured_decision_quality',true
  );
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.worker_stage_decisions(UUID,TEXT,TEXT,JSONB)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.worker_stage_decisions(UUID,TEXT,TEXT,JSONB) IS
  'Canonical staging entrypoint plus bounded structured decision-quality envelope. Preserves historical core staging/retry/lifecycle semantics and adds an exact quality submission hash.';

RESET lock_timeout;
RESET statement_timeout;
