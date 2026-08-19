-- ============================================================================
-- AI Operations — final prompt/decision-contract precedence alignment
--
-- v2 added structured quality after the original v1 OUTPUT CONTRACT. v3 keeps
-- the same reasoning policy but explicitly establishes one final output field
-- list so the model cannot interpret the earlier narrower list as authoritative.
-- The worker context decision_contract is enriched to say the same thing.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

WITH precedence(text_value) AS (
  VALUES ($precedence$

FINAL OUTPUT CONTRACT PRECEDENCE — PROMPT v3
This section is the final authoritative output-field contract and supersedes any earlier narrower allowed-field list in this prompt. All earlier reasoning, safety, human-review and no-autonomous-execution rules remain in force.

For every decision, allowed fields are exactly: case_id, decision_type, concise_rationale, confidence, recommended_owner_user_id, recommended_assignee_user_id, responsibility_summary, why_this_owner, why_now, expected_outcome, next_action_text, due_at, review_after, business_impact, urgency, evidence_completeness, reversibility, estimated_effort, success_signal, employee_safe_reason.
For CREATE_WORK and ESCALATE, all structured quality fields business_impact, urgency, evidence_completeness, reversibility, estimated_effort, success_signal and employee_safe_reason are mandatory.
For non-action decisions those structured quality fields may be omitted when they add no value.
Return JSON only and no unsupported fields.
$precedence$)
)
INSERT INTO ai_ops.planner_policies(
  policy_version,prompt_version,enabled,system_prompt,methodology,prompt_hash,created_at,updated_at
)
SELECT
  p.policy_version,'v3',true,p.system_prompt||x.text_value,
  p.methodology||jsonb_build_object(
    'final_output_contract_precedence','v3',
    'supersedes_earlier_narrow_allowed_field_list',true,
    'structured_quality_required_for_actions',true
  ),
  md5(p.system_prompt||x.text_value),clock_timestamp(),clock_timestamp()
FROM ai_ops.planner_policies p
CROSS JOIN precedence x
WHERE p.policy_version='v1' AND p.prompt_version='v2'
ON CONFLICT(policy_version,prompt_version) DO NOTHING;

UPDATE ai_ops.settings
SET prompt_version='v3',updated_at=clock_timestamp()
WHERE singleton=true;

ALTER FUNCTION public.ai_ops_worker_get_context(UUID,TEXT)
  RENAME TO ai_ops_worker_get_context_pre_final_contract_v1;
REVOKE ALL ON FUNCTION public.ai_ops_worker_get_context_pre_final_contract_v1(UUID,TEXT)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.ai_ops_worker_get_context(
  p_run_id UUID,
  p_worker_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_result JSONB;
  v_context JSONB;
  v_contract JSONB;
  v_settings ai_ops.settings%ROWTYPE;
  v_bytes INTEGER;
  v_hash TEXT;
  v_now TIMESTAMPTZ:=clock_timestamp();
BEGIN
  v_result:=public.ai_ops_worker_get_context_pre_final_contract_v1(p_run_id,p_worker_id);
  IF COALESCE((v_result->>'blocked')::BOOLEAN,false) THEN RETURN v_result; END IF;

  SELECT * INTO v_settings FROM ai_ops.settings WHERE singleton=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations settings are not initialized'; END IF;

  v_context:=v_result->'context';
  v_contract:=COALESCE(v_context->'decision_contract','{}'::JSONB)||jsonb_build_object(
    'final_output_contract_version','v3',
    'allowed_fields',jsonb_build_array(
      'case_id','decision_type','concise_rationale','confidence',
      'recommended_owner_user_id','recommended_assignee_user_id',
      'responsibility_summary','why_this_owner','why_now',
      'expected_outcome','next_action_text','due_at','review_after',
      'business_impact','urgency','evidence_completeness','reversibility',
      'estimated_effort','success_signal','employee_safe_reason'
    ),
    'action_quality_requires',jsonb_build_array(
      'business_impact','urgency','evidence_completeness','reversibility',
      'estimated_effort','success_signal','employee_safe_reason'
    ),
    'structured_quality_labels_are_planning_not_employee_scores',true,
    'quality_contract_is_additive_to_deterministic_validation',true
  );
  v_context:=jsonb_set(v_context,'{decision_contract}',v_contract,false);

  v_bytes:=octet_length(convert_to(v_context::TEXT,'UTF8'));
  IF v_bytes>v_settings.max_worker_context_bytes THEN
    UPDATE ai_ops.planner_runs
    SET
      status='partial',checkpoint='context_budget_blocked_after_final_contract',
      lease_expires_at=NULL,completed_at=v_now,error_class='context_budget_exceeded',
      error_message=format('final worker context %s bytes exceeds limit %s',v_bytes,v_settings.max_worker_context_bytes),
      result_summary=result_summary||jsonb_build_object(
        'final_contract_context_bytes',v_bytes,
        'worker_context_limit_bytes',v_settings.max_worker_context_bytes,
        'final_output_contract_version','v3'
      ),updated_at=v_now
    WHERE id=p_run_id;
    RETURN jsonb_build_object(
      'blocked',true,'reason','context_budget_exceeded_after_final_contract',
      'run_id',p_run_id,'context_bytes',v_bytes,'context_limit_bytes',v_settings.max_worker_context_bytes
    );
  END IF;

  v_hash:=md5(v_context::TEXT);
  UPDATE ai_ops.planner_runs
  SET
    result_summary=result_summary||jsonb_build_object(
      'worker_context_hash',v_hash,
      'worker_context_hash_algorithm','md5-jsonb-identity',
      'worker_context_bytes',v_bytes,
      'final_output_contract_version','v3',
      'final_output_contract_aligned',true
    ),updated_at=v_now
  WHERE id=p_run_id;

  RETURN (v_result
    || jsonb_build_object(
      'context_hash',v_hash,
      'context_bytes',v_bytes,
      'context',v_context
    ));
END;
$$;
REVOKE ALL ON FUNCTION public.ai_ops_worker_get_context(UUID,TEXT)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ai_ops_worker_get_context(UUID,TEXT) TO service_role;

COMMENT ON FUNCTION public.ai_ops_worker_get_context(UUID,TEXT) IS
  'Final service-only worker context. Aligns the versioned v3 prompt with one explicit output/quality contract, recomputes byte budget and context identity, and never exposes operational commit.';

RESET lock_timeout;
RESET statement_timeout;
