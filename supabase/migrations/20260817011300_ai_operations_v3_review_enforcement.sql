-- ============================================================================
-- AI Operations — v3 full-review enforcement
--
-- Prompt v3 is a contract-clarity successor to v2 and retains all structured
-- decision-quality requirements. Keep review/commit fail-closed even if an
-- earlier wrapper had an explicit v2 version check.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

ALTER FUNCTION public.ai_ops_review_decision(UUID,TEXT,TEXT)
  RENAME TO ai_ops_review_decision_pre_v3_enforcement_v1;
REVOKE ALL ON FUNCTION public.ai_ops_review_decision_pre_v3_enforcement_v1(UUID,TEXT,TEXT)
  FROM PUBLIC,anon,authenticated,service_role;

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

  IF v_run.prompt_version='v3'
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
    RAISE EXCEPTION 'structured decision quality is incomplete; v3 decision cannot be reviewed';
  END IF;

  RETURN public.ai_ops_review_decision_pre_v3_enforcement_v1(
    p_decision_id,p_review_state,p_review_note
  );
END;
$$;
REVOKE ALL ON FUNCTION public.ai_ops_review_decision(UUID,TEXT,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ai_ops_review_decision(UUID,TEXT,TEXT) TO authenticated,service_role;

ALTER FUNCTION public.ai_ops_commit_reviewed_decision(UUID)
  RENAME TO ai_ops_commit_reviewed_decision_pre_v3_enforcement_v1;
REVOKE ALL ON FUNCTION public.ai_ops_commit_reviewed_decision_pre_v3_enforcement_v1(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.ai_ops_commit_reviewed_decision(p_decision_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_decision ai_ops.decisions%ROWTYPE;
  v_run ai_ops.planner_runs%ROWTYPE;
  v_review ai_ops.decision_reviews%ROWTYPE;
  v_binding ai_ops.decision_review_bindings%ROWTYPE;
  v_full TEXT;
BEGIN
  IF v_actor IS NULL OR NOT private.work_actor_is_active(v_actor) THEN
    RAISE EXCEPTION 'المستخدم غير متاح لتنفيذ قرار AI Operations' USING ERRCODE='42501';
  END IF;
  IF NOT COALESCE(public.check_permission(v_actor,'work.policies.manage'),false) THEN
    RAISE EXCEPTION 'لا تملك صلاحية تنفيذ قرارات التشغيل الذكي' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_decision FROM ai_ops.decisions WHERE id=p_decision_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations decision not found'; END IF;
  SELECT * INTO v_run FROM ai_ops.planner_runs WHERE id=v_decision.run_id;
  SELECT * INTO v_review FROM ai_ops.decision_reviews WHERE decision_id=p_decision_id;

  IF v_run.prompt_version='v3'
     AND v_review.id IS NOT NULL
     AND v_review.review_state='approved'
     AND v_decision.decision_type IN ('CREATE_WORK','ESCALATE') THEN
    SELECT * INTO v_binding
    FROM ai_ops.decision_review_bindings b
    WHERE b.review_id=v_review.id AND b.decision_id=p_decision_id;

    IF NOT FOUND THEN
      RETURN jsonb_build_object(
        'committed',false,'blocked',true,'decision_id',p_decision_id,
        'reason','full_review_fingerprint_missing'
      );
    END IF;

    v_full:=ai_ops.decision_full_fingerprint(p_decision_id);
    IF v_binding.decision_revision<>v_decision.revision
       OR v_binding.full_fingerprint IS DISTINCT FROM v_full THEN
      RETURN jsonb_build_object(
        'committed',false,'blocked',true,'decision_id',p_decision_id,
        'reason','full_review_fingerprint_mismatch'
      );
    END IF;
  END IF;

  RETURN public.ai_ops_commit_reviewed_decision_pre_v3_enforcement_v1(p_decision_id);
END;
$$;
REVOKE ALL ON FUNCTION public.ai_ops_commit_reviewed_decision(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ai_ops_commit_reviewed_decision(UUID) TO authenticated,service_role;

RESET lock_timeout;
RESET statement_timeout;
