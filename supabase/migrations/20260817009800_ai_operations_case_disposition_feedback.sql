-- AI Operations — governed management case disposition + structured feedback.
SET lock_timeout = '5s';
SET statement_timeout = '30s';

CREATE OR REPLACE FUNCTION public.ai_ops_set_case_disposition(
  p_case_id UUID,
  p_action TEXT,
  p_until TIMESTAMPTZ DEFAULT NULL,
  p_note TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_case ai_ops.cases%ROWTYPE;
  v_decision ai_ops.decisions%ROWTYPE;
  v_now TIMESTAMPTZ := clock_timestamp();
  v_until TIMESTAMPTZ;
  v_reason TEXT;
  v_note TEXT := NULLIF(btrim(COALESCE(p_note,'')), '');
  v_feedback_recorded BOOLEAN := false;
BEGIN
  IF v_actor IS NULL OR NOT private.work_actor_is_active(v_actor) THEN
    RAISE EXCEPTION 'المستخدم غير متاح لتحديث حالة AI Operations' USING ERRCODE='42501';
  END IF;
  IF NOT COALESCE(public.check_permission(v_actor,'work.policies.manage'),false) THEN
    RAISE EXCEPTION 'لا تملك صلاحية إدارة حالات التشغيل الذكي' USING ERRCODE='42501';
  END IF;
  IF p_action NOT IN ('snooze','dismiss') THEN
    RAISE EXCEPTION 'AI Operations case disposition is not supported';
  END IF;
  IF v_note IS NOT NULL AND length(v_note)>1000 THEN
    RAISE EXCEPTION 'ملاحظة الحالة تتجاوز الحد المسموح';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('ai_ops:case-disposition:'||p_case_id::TEXT,0));
  SELECT * INTO v_case FROM ai_ops.cases WHERE id=p_case_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations case not found'; END IF;

  v_until := COALESCE(
    p_until,
    CASE WHEN p_action='snooze' THEN v_now+interval '24 hours' ELSE v_now+interval '7 days' END
  );
  IF v_until<=v_now OR v_until>v_now+interval '90 days' THEN
    RAISE EXCEPTION 'case suppression must be in the future and no more than 90 days';
  END IF;
  v_reason := CASE WHEN p_action='snooze' THEN 'wrong_timing' ELSE 'not_actionable' END;

  IF v_case.status='suppressed'
     AND v_case.suppressed_until IS NOT DISTINCT FROM v_until THEN
    RETURN jsonb_build_object(
      'updated',true,'idempotent_reuse',true,'case_id',v_case.id,
      'case_status',v_case.status,'suppressed_until',v_case.suppressed_until,
      'feedback_recorded',false
    );
  END IF;

  UPDATE ai_ops.cases
  SET status='suppressed', suppressed_until=v_until, resolved_at=NULL,
      state_version=state_version+1, updated_at=v_now
  WHERE id=p_case_id
  RETURNING * INTO v_case;

  SELECT * INTO v_decision
  FROM ai_ops.decisions d
  WHERE d.case_id=p_case_id
  ORDER BY d.created_at DESC,d.revision DESC,d.id DESC
  LIMIT 1;

  IF FOUND THEN
    INSERT INTO ai_ops.decision_feedback(
      decision_id,feedback_reason,feedback_note,actor_user_id,metadata
    ) VALUES (
      v_decision.id,v_reason,v_note,v_actor,
      jsonb_build_object(
        'case_disposition',p_action,
        'suppressed_until',v_until,
        'employee_performance_signal',false
      )
    );
    v_feedback_recorded:=true;
  END IF;

  RETURN jsonb_build_object(
    'updated',true,'idempotent_reuse',false,'case_id',v_case.id,
    'case_status',v_case.status,'suppressed_until',v_case.suppressed_until,
    'feedback_recorded',v_feedback_recorded
  );
END;
$$;

REVOKE ALL ON FUNCTION public.ai_ops_set_case_disposition(UUID,TEXT,TIMESTAMPTZ,TEXT)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ai_ops_set_case_disposition(UUID,TEXT,TIMESTAMPTZ,TEXT)
  TO authenticated,service_role;

COMMENT ON FUNCTION public.ai_ops_set_case_disposition(UUID,TEXT,TIMESTAMPTZ,TEXT) IS
  'Management-only temporary Snooze/Dismiss gateway. Records planner-quality feedback, never employee performance scoring.';

RESET lock_timeout;
RESET statement_timeout;
