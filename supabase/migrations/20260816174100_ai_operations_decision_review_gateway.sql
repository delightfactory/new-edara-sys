-- ============================================================================
-- AI Operations Planner — Bounded Management Decision Review Gateway
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply until explicitly reviewed/approved.
-- Depends on:
--   * 20260816174000_ai_operations_run_finalization.sql
--
-- Purpose:
--   Give the management UI the exact reviewed decision contract needed for a
--   safe approve/reject/explicit-commit flow without exposing ai_ops tables or
--   management-only metadata wholesale.
--
-- Read-only. No operational mutation occurs here.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '30s';

CREATE OR REPLACE FUNCTION public.ai_ops_get_case_decision_review(p_case_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_case ai_ops.cases%ROWTYPE;
  v_decision ai_ops.decisions%ROWTYPE;
  v_review ai_ops.decision_reviews%ROWTYPE;
  v_run ai_ops.planner_runs%ROWTYPE;
  v_owner_label TEXT;
  v_assignee_label TEXT;
  v_reviewer_label TEXT;
  v_committed_work_number BIGINT;
  v_validation_codes JSONB := '[]'::JSONB;
BEGIN
  IF v_actor IS NULL OR NOT private.work_actor_is_active(v_actor) THEN
    RAISE EXCEPTION 'المستخدم غير متاح لعرض مراجعة قرار AI Operations'
      USING ERRCODE = '42501';
  END IF;

  IF NOT COALESCE(public.check_permission(v_actor, 'work.policies.manage'), false) THEN
    RAISE EXCEPTION 'لا تملك صلاحية مراجعة قرارات التشغيل الذكي'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_case
  FROM ai_ops.cases
  WHERE id = p_case_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AI Operations case not found';
  END IF;

  SELECT * INTO v_decision
  FROM ai_ops.decisions d
  WHERE d.case_id = p_case_id
  ORDER BY d.created_at DESC, d.revision DESC, d.id DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'case_id', p_case_id,
      'decision', NULL
    );
  END IF;

  SELECT * INTO v_run
  FROM ai_ops.planner_runs
  WHERE id = v_decision.run_id;

  SELECT * INTO v_review
  FROM ai_ops.decision_reviews
  WHERE decision_id = v_decision.id;

  SELECT p.full_name INTO v_owner_label
  FROM public.profiles p
  WHERE p.id = v_decision.recommended_owner_user_id;

  SELECT p.full_name INTO v_assignee_label
  FROM public.profiles p
  WHERE p.id = v_decision.recommended_assignee_user_id;

  IF v_review.id IS NOT NULL THEN
    SELECT p.full_name INTO v_reviewer_label
    FROM public.profiles p
    WHERE p.id = v_review.reviewed_by_user_id;
  END IF;

  IF v_decision.committed_work_item_id IS NOT NULL THEN
    SELECT wi.work_number INTO v_committed_work_number
    FROM public.work_items wi
    WHERE wi.id = v_decision.committed_work_item_id;
  END IF;

  IF jsonb_typeof(v_decision.validation_detail->'validation_codes') = 'array' THEN
    v_validation_codes := v_validation_codes || (v_decision.validation_detail->'validation_codes');
  END IF;
  IF jsonb_typeof(v_decision.validation_detail->'approval_revalidation_codes') = 'array' THEN
    v_validation_codes := v_validation_codes || (v_decision.validation_detail->'approval_revalidation_codes');
  END IF;
  IF jsonb_typeof(v_decision.validation_detail->'commit_revalidation_codes') = 'array' THEN
    v_validation_codes := v_validation_codes || (v_decision.validation_detail->'commit_revalidation_codes');
  END IF;

  RETURN jsonb_build_object(
    'case_id', p_case_id,
    'decision', jsonb_build_object(
      'decision_id', v_decision.id,
      'run_id', v_decision.run_id,
      'run_status', v_run.status,
      'run_checkpoint', v_run.checkpoint,
      'revision', v_decision.revision,
      'decision_type', v_decision.decision_type,
      'concise_rationale', v_decision.concise_rationale,
      'why_this_owner', v_decision.responsibility_basis->>'why_this_owner',
      'why_now', COALESCE(
        v_decision.responsibility_basis->>'why_now',
        v_decision.management_only_metadata->>'why_now'
      ),
      'confidence', v_decision.confidence,
      'recommended_owner_user_id', v_decision.recommended_owner_user_id,
      'recommended_owner_label', v_owner_label,
      'recommended_assignee_user_id', v_decision.recommended_assignee_user_id,
      'recommended_assignee_label', v_assignee_label,
      'expected_outcome', v_decision.expected_outcome,
      'next_action_text', v_decision.next_action_text,
      'due_at', v_decision.due_at,
      'review_after', v_decision.review_after,
      'validation_state', v_decision.validation_state,
      'validation_codes', v_validation_codes,
      'requires_human_review', CASE
        WHEN jsonb_typeof(v_decision.validation_detail->'requires_human_review') = 'boolean'
          THEN (v_decision.validation_detail->>'requires_human_review')::BOOLEAN
        ELSE true
      END,
      'review_state', v_review.review_state,
      'reviewed_by_user_id', v_review.reviewed_by_user_id,
      'reviewed_by_label', v_reviewer_label,
      'reviewed_at', v_review.reviewed_at,
      'review_note', v_review.review_note,
      'commit_status', v_decision.commit_status,
      'committed_work_item_id', v_decision.committed_work_item_id,
      'committed_work_number', v_committed_work_number,
      'committed_at', v_decision.committed_at,
      'updated_at', v_decision.updated_at
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.ai_ops_get_case_decision_review(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ai_ops_get_case_decision_review(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.ai_ops_get_case_decision_review(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ai_ops_get_case_decision_review(UUID) TO service_role;

COMMENT ON FUNCTION public.ai_ops_get_case_decision_review(UUID) IS
  'Permission-gated management read model for the latest AI decision, human review and explicit Work commit state. Does not expose raw ai_ops tables or unrestricted metadata.';

RESET lock_timeout;
RESET statement_timeout;
