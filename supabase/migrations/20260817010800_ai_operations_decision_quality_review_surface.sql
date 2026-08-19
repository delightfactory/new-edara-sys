-- ============================================================================
-- AI Operations — bounded decision-quality review surface
--
-- Extends only the management read model. No approval, validation or execution
-- behavior changes. Raw management metadata remains private.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '30s';

ALTER FUNCTION public.ai_ops_get_case_decision_review(UUID)
  RENAME TO ai_ops_get_case_decision_review_pre_quality_surface_v1;
REVOKE ALL ON FUNCTION public.ai_ops_get_case_decision_review_pre_quality_surface_v1(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.ai_ops_get_case_decision_review(p_case_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_result JSONB;
  v_decision ai_ops.decisions%ROWTYPE;
BEGIN
  -- The preserved gateway remains the authority for active-actor and
  -- work.policies.manage authorization and for the bounded base response.
  v_result:=public.ai_ops_get_case_decision_review_pre_quality_surface_v1(p_case_id);

  IF v_result->'decision' IS NULL OR v_result->'decision'='null'::JSONB THEN
    RETURN v_result;
  END IF;

  SELECT * INTO v_decision
  FROM ai_ops.decisions d
  WHERE d.case_id=p_case_id
  ORDER BY d.created_at DESC,d.revision DESC,d.id DESC
  LIMIT 1;

  IF NOT FOUND THEN RETURN v_result; END IF;

  RETURN jsonb_set(
    v_result,
    '{decision}',
    (v_result->'decision')||jsonb_build_object(
      'business_impact',v_decision.business_impact,
      'urgency',v_decision.urgency,
      'evidence_completeness',v_decision.evidence_completeness,
      'reversibility',v_decision.reversibility,
      'estimated_effort',v_decision.estimated_effort,
      'success_signal',NULLIF(v_decision.success_signal->>'summary',''),
      'employee_safe_reason',v_decision.employee_safe_reason
    ),
    false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.ai_ops_get_case_decision_review(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ai_ops_get_case_decision_review(UUID) TO authenticated,service_role;

COMMENT ON FUNCTION public.ai_ops_get_case_decision_review(UUID) IS
  'Management-only latest decision review surface including bounded structured quality labels; no raw management metadata and no mutation.';

RESET lock_timeout;
RESET statement_timeout;
