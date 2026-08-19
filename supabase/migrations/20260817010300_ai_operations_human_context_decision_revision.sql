-- ============================================================================
-- AI Operations — governed human context + audited decision revision
--
-- Management browser access remains through narrow SECURITY DEFINER RPCs only.
-- No direct ai_ops grants are introduced. Existing validation/review/commit
-- gates remain authoritative.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

-- --------------------------------------------------------------------------
-- Append-only audit trail for management context lifecycle changes.
-- --------------------------------------------------------------------------
CREATE TABLE ai_ops.operational_context_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  context_id UUID NOT NULL REFERENCES ai_ops.operational_context(id) ON DELETE RESTRICT,
  event_type TEXT NOT NULL,
  actor_user_id UUID NOT NULL,
  event_note TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ai_ops_context_events_type_check CHECK (event_type IN ('created','revoked')),
  CONSTRAINT ai_ops_context_events_note_length CHECK (event_note IS NULL OR length(event_note) <= 1000),
  CONSTRAINT ai_ops_context_events_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);
CREATE INDEX idx_ai_ops_context_events_context_time
  ON ai_ops.operational_context_events(context_id, created_at DESC);
ALTER TABLE ai_ops.operational_context_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE ai_ops.operational_context_events FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION ai_ops.reject_context_event_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'AI operational context event history is immutable';
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.reject_context_event_mutation() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER trg_ai_ops_context_events_immutable
  BEFORE UPDATE OR DELETE ON ai_ops.operational_context_events
  FOR EACH ROW EXECUTE FUNCTION ai_ops.reject_context_event_mutation();

-- --------------------------------------------------------------------------
-- Create approved human operational context. We require expiry for v1 so a
-- temporary management fact cannot silently become permanent policy.
-- Subject ids stay soft-typed, but must already appear in planner Case evidence.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_ops_create_operational_context(
  p_subject_type TEXT,
  p_subject_id UUID,
  p_context_type TEXT,
  p_summary TEXT,
  p_owner_user_id UUID DEFAULT NULL,
  p_valid_until TIMESTAMPTZ DEFAULT NULL,
  p_visibility TEXT DEFAULT 'management'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_now TIMESTAMPTZ := clock_timestamp();
  v_summary TEXT := NULLIF(btrim(COALESCE(p_summary,'')), '');
  v_context ai_ops.operational_context%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT private.work_actor_is_active(v_actor) THEN
    RAISE EXCEPTION 'المستخدم غير متاح لإضافة سياق AI Operations' USING ERRCODE='42501';
  END IF;
  IF NOT COALESCE(public.check_permission(v_actor,'work.policies.manage'),false) THEN
    RAISE EXCEPTION 'لا تملك صلاحية إدارة سياق التشغيل الذكي' USING ERRCODE='42501';
  END IF;

  IF p_subject_id IS NULL
     OR p_subject_type IS NULL
     OR p_subject_type !~ '^[a-z][a-z0-9_]{0,78}$'
     OR p_context_type IS NULL
     OR p_context_type !~ '^[a-z][a-z0-9_]{0,98}$' THEN
    RAISE EXCEPTION 'subject/context type is invalid';
  END IF;
  IF v_summary IS NULL OR length(v_summary) > 500 THEN
    RAISE EXCEPTION 'context summary is required and must not exceed 500 characters';
  END IF;
  IF p_visibility NOT IN ('management','standard') THEN
    RAISE EXCEPTION 'context visibility must be management or standard';
  END IF;
  IF p_valid_until IS NULL
     OR p_valid_until <= v_now
     OR p_valid_until > v_now + interval '180 days' THEN
    RAISE EXCEPTION 'approved human context requires an expiry within 180 days';
  END IF;
  IF p_owner_user_id IS NOT NULL AND NOT private.work_actor_is_active(p_owner_user_id) THEN
    RAISE EXCEPTION 'context owner must be an active Work actor';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM ai_ops.cases c
    WHERE c.entity_type = p_subject_type AND c.entity_id = p_subject_id
  ) THEN
    RAISE EXCEPTION 'context subject is not known to AI Operations Case evidence';
  END IF;

  INSERT INTO ai_ops.operational_context(
    subject_type, subject_id, context_type, context_payload, owner_user_id,
    source_type, confidence_class, lifecycle_type, valid_from, valid_until,
    status, visibility, created_by_user_id, approved_by_user_id, created_at, updated_at
  ) VALUES (
    p_subject_type, p_subject_id, p_context_type,
    jsonb_build_object(
      'summary', v_summary,
      'content_trust', 'governed_untrusted_text',
      'execution_authority', false
    ),
    p_owner_user_id, 'human', 'approved_human', 'valid_until', v_now, p_valid_until,
    'active', p_visibility, v_actor, v_actor, v_now, v_now
  ) RETURNING * INTO v_context;

  INSERT INTO ai_ops.operational_context_events(
    context_id,event_type,actor_user_id,event_note,metadata
  ) VALUES (
    v_context.id,'created',v_actor,NULL,
    jsonb_build_object(
      'subject_type',p_subject_type,
      'subject_id',p_subject_id,
      'context_type',p_context_type,
      'valid_until',p_valid_until,
      'visibility',p_visibility,
      'approved_human',true,
      'execution_authority',false
    )
  );

  RETURN jsonb_build_object(
    'created',true,
    'context_id',v_context.id,
    'subject_type',v_context.subject_type,
    'subject_id',v_context.subject_id,
    'context_type',v_context.context_type,
    'valid_until',v_context.valid_until,
    'status',v_context.status
  );
END;
$$;
REVOKE ALL ON FUNCTION public.ai_ops_create_operational_context(TEXT,UUID,TEXT,TEXT,UUID,TIMESTAMPTZ,TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ai_ops_create_operational_context(TEXT,UUID,TEXT,TEXT,UUID,TIMESTAMPTZ,TEXT)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ai_ops_revoke_operational_context(
  p_context_id UUID,
  p_note TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_context ai_ops.operational_context%ROWTYPE;
  v_note TEXT := NULLIF(btrim(COALESCE(p_note,'')), '');
  v_now TIMESTAMPTZ := clock_timestamp();
BEGIN
  IF v_actor IS NULL OR NOT private.work_actor_is_active(v_actor) THEN
    RAISE EXCEPTION 'المستخدم غير متاح لإلغاء سياق AI Operations' USING ERRCODE='42501';
  END IF;
  IF NOT COALESCE(public.check_permission(v_actor,'work.policies.manage'),false) THEN
    RAISE EXCEPTION 'لا تملك صلاحية إدارة سياق التشغيل الذكي' USING ERRCODE='42501';
  END IF;
  IF v_note IS NOT NULL AND length(v_note) > 1000 THEN
    RAISE EXCEPTION 'revoke note exceeds 1000 characters';
  END IF;

  SELECT * INTO v_context
  FROM ai_ops.operational_context
  WHERE id=p_context_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations context not found'; END IF;

  IF v_context.status='revoked' THEN
    RETURN jsonb_build_object('revoked',true,'idempotent_reuse',true,'context_id',v_context.id,'status',v_context.status);
  END IF;
  IF v_context.status <> 'active' THEN
    RETURN jsonb_build_object('revoked',false,'blocked',true,'reason','context_not_active','context_id',v_context.id,'status',v_context.status);
  END IF;

  UPDATE ai_ops.operational_context
  SET status='revoked', updated_at=v_now
  WHERE id=p_context_id
  RETURNING * INTO v_context;

  INSERT INTO ai_ops.operational_context_events(
    context_id,event_type,actor_user_id,event_note,metadata
  ) VALUES (
    v_context.id,'revoked',v_actor,v_note,
    jsonb_build_object('previous_status','active','execution_authority',false)
  );

  RETURN jsonb_build_object('revoked',true,'idempotent_reuse',false,'context_id',v_context.id,'status',v_context.status);
END;
$$;
REVOKE ALL ON FUNCTION public.ai_ops_revoke_operational_context(UUID,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ai_ops_revoke_operational_context(UUID,TEXT) TO authenticated, service_role;

-- --------------------------------------------------------------------------
-- Audited human revision of an unreviewed staged CREATE_WORK recommendation.
-- Revision never changes Case/source/decision type and never executes Work.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_ops_revise_decision(
  p_decision_id UUID,
  p_owner_user_id UUID,
  p_assignee_user_id UUID,
  p_expected_outcome TEXT,
  p_next_action_text TEXT,
  p_due_at TIMESTAMPTZ,
  p_revision_note TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_old ai_ops.decisions%ROWTYPE;
  v_run ai_ops.planner_runs%ROWTYPE;
  v_new ai_ops.decisions%ROWTYPE;
  v_new_id UUID := gen_random_uuid();
  v_now TIMESTAMPTZ := clock_timestamp();
  v_issues JSONB := '[]'::JSONB;
  v_note TEXT := NULLIF(btrim(COALESCE(p_revision_note,'')), '');
  v_outcome TEXT := NULLIF(btrim(COALESCE(p_expected_outcome,'')), '');
  v_next TEXT := NULLIF(btrim(COALESCE(p_next_action_text,'')), '');
BEGIN
  IF v_actor IS NULL OR NOT private.work_actor_is_active(v_actor) THEN
    RAISE EXCEPTION 'المستخدم غير متاح لتعديل قرار AI Operations' USING ERRCODE='42501';
  END IF;
  IF NOT COALESCE(public.check_permission(v_actor,'work.policies.manage'),false) THEN
    RAISE EXCEPTION 'لا تملك صلاحية تعديل قرارات التشغيل الذكي' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_old FROM ai_ops.decisions WHERE id=p_decision_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations decision not found'; END IF;
  IF v_old.decision_type <> 'CREATE_WORK' THEN
    RAISE EXCEPTION 'human revision v1 supports CREATE_WORK recommendations only';
  END IF;

  SELECT * INTO v_run FROM ai_ops.planner_runs WHERE id=v_old.run_id FOR UPDATE;
  IF NOT FOUND OR v_run.status <> 'staged' THEN
    RAISE EXCEPTION 'decision is not in a staged reviewable run';
  END IF;
  IF EXISTS (SELECT 1 FROM ai_ops.decision_reviews dr WHERE dr.decision_id=v_old.id) THEN
    RAISE EXCEPTION 'reviewed decisions cannot be revised';
  END IF;
  IF v_old.commit_status='committed' OR v_old.committed_work_item_id IS NOT NULL THEN
    RAISE EXCEPTION 'committed decisions cannot be revised';
  END IF;
  IF EXISTS (
    SELECT 1 FROM ai_ops.decisions d
    WHERE d.run_id=v_old.run_id AND d.case_id=v_old.case_id AND d.revision>v_old.revision
  ) THEN
    RAISE EXCEPTION 'a newer decision revision already exists';
  END IF;

  IF p_owner_user_id IS NULL OR NOT private.work_actor_is_active(p_owner_user_id) THEN
    RAISE EXCEPTION 'revised accountable owner must be an active Work actor';
  END IF;
  IF p_assignee_user_id IS NULL OR NOT private.work_actor_is_active(p_assignee_user_id) THEN
    RAISE EXCEPTION 'revised assignee must be an active Work actor';
  END IF;
  IF v_outcome IS NULL OR length(v_outcome)>1000 THEN
    RAISE EXCEPTION 'revised expected outcome is required and must not exceed 1000 characters';
  END IF;
  IF v_next IS NULL OR length(v_next)>500 THEN
    RAISE EXCEPTION 'revised next action is required and must not exceed 500 characters';
  END IF;
  IF p_due_at IS NULL OR p_due_at<=v_now THEN
    RAISE EXCEPTION 'revised due date must be in the future';
  END IF;
  IF v_note IS NOT NULL AND length(v_note)>1000 THEN
    RAISE EXCEPTION 'revision note exceeds 1000 characters';
  END IF;

  UPDATE ai_ops.decisions
  SET
    validation_state='rejected',
    commit_status='skipped',
    validation_detail=COALESCE(validation_detail,'{}'::JSONB) || jsonb_build_object(
      'superseded_by_human_revision',true,
      'superseded_at',v_now,
      'superseded_by_user_id',v_actor,
      'superseding_decision_id',v_new_id,
      'stage_only',true
    ),
    updated_at=v_now
  WHERE id=v_old.id;

  INSERT INTO ai_ops.decisions(
    id,run_id,case_id,revision,decision_type,business_impact,urgency,confidence,
    evidence_completeness,reversibility,estimated_effort,
    recommended_owner_user_id,recommended_assignee_user_id,responsibility_basis,
    concise_rationale,expected_outcome,success_signal,review_after,
    validation_state,validation_detail,commit_status,committed_work_item_id,
    idempotency_key,management_only_metadata,employee_safe_reason,
    next_action_text,due_at,linked_work_item_id,validated_at,validated_by_user_id,
    committed_at,created_at,updated_at
  ) VALUES (
    v_new_id,v_old.run_id,v_old.case_id,v_old.revision+1,v_old.decision_type,
    v_old.business_impact,v_old.urgency,v_old.confidence,v_old.evidence_completeness,
    v_old.reversibility,v_old.estimated_effort,p_owner_user_id,p_assignee_user_id,
    COALESCE(v_old.responsibility_basis,'{}'::JSONB) || jsonb_build_object(
      'human_revision',true,
      'revised_by_user_id',v_actor,
      'previous_owner_user_id',v_old.recommended_owner_user_id,
      'previous_assignee_user_id',v_old.recommended_assignee_user_id
    ),
    v_old.concise_rationale,v_outcome,COALESCE(v_old.success_signal,'{}'::JSONB),
    v_old.review_after,'pending',jsonb_build_object(
      'human_revision',true,
      'revision_note',v_note,
      'source_decision_id',v_old.id,
      'stage_only',true
    ),
    'staged',NULL,'human-revision:'||v_new_id::TEXT,
    COALESCE(v_old.management_only_metadata,'{}'::JSONB) || jsonb_build_object(
      'human_revision',true,
      'revised_by_user_id',v_actor,
      'revision_note',v_note
    ),
    v_old.employee_safe_reason,v_next,p_due_at,v_old.linked_work_item_id,
    NULL,NULL,NULL,v_now,v_now
  ) RETURNING * INTO v_new;

  -- Reuse the canonical current-state/feasibility guard. The human edit does
  -- not gain execution authority merely because a manager entered it.
  v_issues := ai_ops.current_decision_issues(v_new.id);
  IF jsonb_array_length(v_issues)=0 THEN
    UPDATE ai_ops.decisions
    SET
      validation_state='validated',
      validation_detail=validation_detail || jsonb_build_object(
        'human_revision_revalidated',true,
        'human_revision_revalidated_at',v_now,
        'stage_only',true
      ),
      validated_at=v_now,
      validated_by_user_id=NULL,
      updated_at=v_now
    WHERE id=v_new.id
    RETURNING * INTO v_new;
  ELSE
    UPDATE ai_ops.decisions
    SET
      validation_state='rejected',
      validation_detail=validation_detail || jsonb_build_object(
        'human_revision_revalidation_failed',true,
        'human_revision_validation_codes',v_issues,
        'human_revision_revalidated_at',v_now,
        'stage_only',true
      ),
      validated_at=v_now,
      validated_by_user_id=NULL,
      updated_at=v_now
    WHERE id=v_new.id
    RETURNING * INTO v_new;
  END IF;

  PERFORM ai_ops.refresh_run_terminal_state(v_new.run_id);

  RETURN jsonb_build_object(
    'revised',true,
    'old_decision_id',v_old.id,
    'decision_id',v_new.id,
    'revision',v_new.revision,
    'validation_state',v_new.validation_state,
    'validation_codes',v_issues,
    'execution_performed',false
  );
END;
$$;
REVOKE ALL ON FUNCTION public.ai_ops_revise_decision(UUID,UUID,UUID,TEXT,TEXT,TIMESTAMPTZ,TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ai_ops_revise_decision(UUID,UUID,UUID,TEXT,TEXT,TIMESTAMPTZ,TEXT)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.ai_ops_revise_decision(UUID,UUID,UUID,TEXT,TEXT,TIMESTAMPTZ,TEXT) IS
  'Management-only audited CREATE_WORK revision. Creates a new revision, supersedes the old unreviewed decision, and immediately reuses current-state validation. Never executes Work.';

RESET lock_timeout;
RESET statement_timeout;
