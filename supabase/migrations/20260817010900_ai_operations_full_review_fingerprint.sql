-- ============================================================================
-- AI Operations — bind the complete decision quality envelope to human review
--
-- The original review/commit fingerprint predates structured decision-quality
-- fields. Keep that existing guard, and add an immutable full fingerprint that
-- covers both the original execution contract and the new quality attributes.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.decision_full_fingerprint(p_decision_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  d ai_ops.decisions%ROWTYPE;
BEGIN
  SELECT * INTO d FROM ai_ops.decisions WHERE id=p_decision_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations decision not found'; END IF;

  RETURN md5(jsonb_build_object(
    'id',d.id,
    'run_id',d.run_id,
    'case_id',d.case_id,
    'revision',d.revision,
    'decision_type',d.decision_type,
    'recommended_owner_user_id',d.recommended_owner_user_id,
    'recommended_assignee_user_id',d.recommended_assignee_user_id,
    'responsibility_basis',d.responsibility_basis,
    'concise_rationale',d.concise_rationale,
    'confidence',d.confidence,
    'expected_outcome',d.expected_outcome,
    'next_action_text',d.next_action_text,
    'due_at',d.due_at,
    'review_after',d.review_after,
    'linked_work_item_id',d.linked_work_item_id,
    'business_impact',d.business_impact,
    'urgency',d.urgency,
    'evidence_completeness',d.evidence_completeness,
    'reversibility',d.reversibility,
    'estimated_effort',d.estimated_effort,
    'success_signal',d.success_signal,
    'employee_safe_reason',d.employee_safe_reason
  )::TEXT);
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.decision_full_fingerprint(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE ai_ops.decision_review_bindings (
  review_id UUID PRIMARY KEY REFERENCES ai_ops.decision_reviews(id) ON DELETE RESTRICT,
  decision_id UUID NOT NULL UNIQUE REFERENCES ai_ops.decisions(id) ON DELETE RESTRICT,
  decision_revision INTEGER NOT NULL,
  full_fingerprint TEXT NOT NULL,
  bound_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ai_ops_review_bindings_revision_positive CHECK (decision_revision>0),
  CONSTRAINT ai_ops_review_bindings_fingerprint_format CHECK (full_fingerprint~'^[a-f0-9]{32}$')
);
ALTER TABLE ai_ops.decision_review_bindings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE ai_ops.decision_review_bindings FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.reject_decision_review_binding_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'AI decision full review fingerprint is immutable';
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.reject_decision_review_binding_mutation()
  FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER trg_ai_ops_decision_review_bindings_immutable
  BEFORE UPDATE OR DELETE ON ai_ops.decision_review_bindings
  FOR EACH ROW EXECUTE FUNCTION ai_ops.reject_decision_review_binding_mutation();

-- --------------------------------------------------------------------------
-- Human review wrapper: require complete quality for v2 consequential actions,
-- then bind the exact full fingerprint after the preserved review succeeds.
-- --------------------------------------------------------------------------
ALTER FUNCTION public.ai_ops_review_decision(UUID,TEXT,TEXT)
  RENAME TO ai_ops_review_decision_pre_full_fingerprint_v1;
REVOKE ALL ON FUNCTION public.ai_ops_review_decision_pre_full_fingerprint_v1(UUID,TEXT,TEXT)
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
  v_result JSONB;
  v_review ai_ops.decision_reviews%ROWTYPE;
  v_existing ai_ops.decision_review_bindings%ROWTYPE;
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

  IF v_run.prompt_version='v2'
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
    RAISE EXCEPTION 'structured decision quality is incomplete; decision cannot be reviewed';
  END IF;

  v_result:=public.ai_ops_review_decision_pre_full_fingerprint_v1(
    p_decision_id,p_review_state,p_review_note
  );

  SELECT * INTO v_review FROM ai_ops.decision_reviews WHERE decision_id=p_decision_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'decision review was not persisted'; END IF;

  v_full:=ai_ops.decision_full_fingerprint(p_decision_id);
  SELECT * INTO v_existing
  FROM ai_ops.decision_review_bindings b
  WHERE b.review_id=v_review.id;

  IF FOUND THEN
    IF v_existing.decision_id IS DISTINCT FROM p_decision_id
       OR v_existing.decision_revision<>v_decision.revision
       OR v_existing.full_fingerprint IS DISTINCT FROM v_full THEN
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

-- --------------------------------------------------------------------------
-- Explicit commit wrapper: the complete reviewed envelope must still match.
-- This is an additional guard; the preserved bridge still rechecks its original
-- fingerprint, source state, owner availability, idempotency and Work rules.
-- --------------------------------------------------------------------------
ALTER FUNCTION public.ai_ops_commit_reviewed_decision(UUID)
  RENAME TO ai_ops_commit_reviewed_decision_pre_full_fingerprint_v1;
REVOKE ALL ON FUNCTION public.ai_ops_commit_reviewed_decision_pre_full_fingerprint_v1(UUID)
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

  IF v_review.id IS NOT NULL AND v_review.review_state='approved'
     AND v_decision.decision_type IN ('CREATE_WORK','ESCALATE') THEN
    SELECT * INTO v_binding
    FROM ai_ops.decision_review_bindings b
    WHERE b.review_id=v_review.id AND b.decision_id=p_decision_id;

    IF NOT FOUND THEN
      IF v_run.prompt_version='v2' THEN
        RETURN jsonb_build_object(
          'committed',false,'blocked',true,'decision_id',p_decision_id,
          'reason','full_review_fingerprint_missing'
        );
      END IF;
    ELSE
      v_full:=ai_ops.decision_full_fingerprint(p_decision_id);
      IF v_binding.decision_revision<>v_decision.revision
         OR v_binding.full_fingerprint IS DISTINCT FROM v_full THEN
        RETURN jsonb_build_object(
          'committed',false,'blocked',true,'decision_id',p_decision_id,
          'reason','full_review_fingerprint_mismatch'
        );
      END IF;
    END IF;
  END IF;

  RETURN public.ai_ops_commit_reviewed_decision_pre_full_fingerprint_v1(p_decision_id);
END;
$$;
REVOKE ALL ON FUNCTION public.ai_ops_commit_reviewed_decision(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ai_ops_commit_reviewed_decision(UUID) TO authenticated,service_role;

-- --------------------------------------------------------------------------
-- Revision v2: success signal and employee-safe reason must follow the edited
-- execution text. The preserved 7-argument revision still owns revision history,
-- current-state validation and revision-aware lifecycle; it is no longer public.
-- --------------------------------------------------------------------------
ALTER FUNCTION public.ai_ops_revise_decision(UUID,UUID,UUID,TEXT,TEXT,TIMESTAMPTZ,TEXT)
  RENAME TO ai_ops_revise_decision_pre_quality_alignment_v1;
REVOKE ALL ON FUNCTION public.ai_ops_revise_decision_pre_quality_alignment_v1(UUID,UUID,UUID,TEXT,TEXT,TIMESTAMPTZ,TEXT)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.ai_ops_revise_decision(
  p_decision_id UUID,
  p_owner_user_id UUID,
  p_assignee_user_id UUID,
  p_expected_outcome TEXT,
  p_next_action_text TEXT,
  p_due_at TIMESTAMPTZ,
  p_success_signal TEXT,
  p_employee_safe_reason TEXT,
  p_revision_note TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_success TEXT:=NULLIF(btrim(COALESCE(p_success_signal,'')),'');
  v_employee_reason TEXT:=NULLIF(btrim(COALESCE(p_employee_safe_reason,'')),'');
  v_result JSONB;
  v_new_id UUID;
BEGIN
  IF v_actor IS NULL OR NOT private.work_actor_is_active(v_actor) THEN
    RAISE EXCEPTION 'المستخدم غير متاح لتعديل قرار AI Operations' USING ERRCODE='42501';
  END IF;
  IF NOT COALESCE(public.check_permission(v_actor,'work.policies.manage'),false) THEN
    RAISE EXCEPTION 'لا تملك صلاحية تعديل قرارات التشغيل الذكي' USING ERRCODE='42501';
  END IF;
  IF v_success IS NULL OR length(v_success)>500 THEN
    RAISE EXCEPTION 'success signal is required and must not exceed 500 characters';
  END IF;
  IF v_employee_reason IS NULL OR length(v_employee_reason)>500 THEN
    RAISE EXCEPTION 'employee-safe reason is required and must not exceed 500 characters';
  END IF;

  v_result:=public.ai_ops_revise_decision_pre_quality_alignment_v1(
    p_decision_id,p_owner_user_id,p_assignee_user_id,p_expected_outcome,
    p_next_action_text,p_due_at,p_revision_note
  );

  IF COALESCE((v_result->>'revised')::BOOLEAN,false) IS NOT TRUE THEN
    RETURN v_result;
  END IF;
  v_new_id:=(v_result->>'decision_id')::UUID;

  UPDATE ai_ops.decisions
  SET
    success_signal=jsonb_build_object('summary',v_success),
    employee_safe_reason=v_employee_reason,
    management_only_metadata=COALESCE(management_only_metadata,'{}'::JSONB)||jsonb_build_object(
      'human_revision_quality_aligned',true,
      'quality_aligned_by_user_id',v_actor,
      'quality_aligned_at',clock_timestamp()
    ),
    updated_at=clock_timestamp()
  WHERE id=v_new_id;

  RETURN v_result||jsonb_build_object(
    'success_signal_updated',true,
    'employee_safe_reason_updated',true,
    'execution_performed',false
  );
END;
$$;
REVOKE ALL ON FUNCTION public.ai_ops_revise_decision(UUID,UUID,UUID,TEXT,TEXT,TIMESTAMPTZ,TEXT,TEXT,TEXT)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ai_ops_revise_decision(UUID,UUID,UUID,TEXT,TEXT,TIMESTAMPTZ,TEXT,TEXT,TEXT)
  TO authenticated,service_role;

RESET lock_timeout;
RESET statement_timeout;
