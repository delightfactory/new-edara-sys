-- ============================================================================
-- AI Operations — quality completeness blocks approval, never human rejection
--
-- A malformed/incomplete AI action must not become executable, but management
-- must always be able to reject it and record that judgement. This final review
-- definition keeps v3 quality completeness as an APPROVAL prerequisite only.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION public.ai_ops_review_decision(
  p_decision_id UUID,
  p_review_state TEXT,
  p_review_note TEXT DEFAULT NULL
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
  v_result JSONB;
  v_review ai_ops.decision_reviews%ROWTYPE;
  v_binding ai_ops.decision_review_bindings%ROWTYPE;
  v_full TEXT;
BEGIN
  IF v_actor IS NULL OR NOT private.work_actor_is_active(v_actor) THEN
    RAISE EXCEPTION 'المستخدم غير متاح لمراجعة قرار AI Operations' USING ERRCODE='42501';
  END IF;
  IF NOT COALESCE(public.check_permission(v_actor,'work.policies.manage'),false) THEN
    RAISE EXCEPTION 'لا تملك صلاحية مراجعة قرارات التشغيل الذكي' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_decision FROM ai_ops.decisions WHERE id=p_decision_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations decision not found'; END IF;
  SELECT * INTO v_run FROM ai_ops.planner_runs WHERE id=v_decision.run_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations run not found'; END IF;

  IF p_review_state='approved'
     AND v_run.prompt_version='v3'
     AND v_decision.decision_type IN ('CREATE_WORK','ESCALATE')
     AND (
       v_decision.business_impact IS NULL
       OR v_decision.urgency IS NULL
       OR v_decision.evidence_completeness IS NULL
       OR v_decision.reversibility IS NULL
       OR v_decision.estimated_effort IS NULL
       OR NULLIF(v_decision.success_signal->>'summary','') IS NULL
       OR NULLIF(btrim(COALESCE(v_decision.employee_safe_reason,'')),'') IS NULL
     ) THEN
    RAISE EXCEPTION 'structured decision quality is incomplete; v3 decision cannot be approved';
  END IF;

  v_result:=public.ai_ops_review_decision_pre_full_fingerprint_v1(
    p_decision_id,p_review_state,p_review_note
  );

  IF COALESCE((v_result->>'approval_blocked')::BOOLEAN,false)
     OR COALESCE((v_result->>'reviewed')::BOOLEAN,false) IS NOT TRUE THEN
    RETURN v_result||jsonb_build_object(
      'full_review_fingerprint_bound',false,
      'execution_performed',false
    );
  END IF;

  SELECT * INTO v_review
  FROM ai_ops.decision_reviews
  WHERE decision_id=p_decision_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'successful human review did not persist its immutable review row';
  END IF;

  v_full:=ai_ops.decision_full_fingerprint(p_decision_id);
  SELECT * INTO v_binding
  FROM ai_ops.decision_review_bindings b
  WHERE b.review_id=v_review.id;

  IF FOUND THEN
    IF v_binding.decision_id IS DISTINCT FROM p_decision_id
       OR v_binding.decision_revision<>v_decision.revision
       OR v_binding.full_fingerprint IS DISTINCT FROM v_full THEN
      RAISE EXCEPTION 'existing review full fingerprint does not match current decision';
    END IF;
  ELSE
    INSERT INTO ai_ops.decision_review_bindings(
      review_id,decision_id,decision_revision,full_fingerprint
    ) VALUES (
      v_review.id,p_decision_id,v_decision.revision,v_full
    );
  END IF;

  RETURN v_result||jsonb_build_object(
    'full_review_fingerprint_bound',true,
    'full_review_fingerprint',v_full
  );
END;
$$;
REVOKE ALL ON FUNCTION public.ai_ops_review_decision(UUID,TEXT,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ai_ops_review_decision(UUID,TEXT,TEXT) TO authenticated,service_role;

COMMENT ON FUNCTION public.ai_ops_review_decision(UUID,TEXT,TEXT) IS
  'Final human-review gateway. v3 structured quality is mandatory for approval only; rejection remains available for incomplete AI recommendations. Current-state approval blocks remain fail-closed non-exceptional outcomes.';

RESET lock_timeout;
RESET statement_timeout;
