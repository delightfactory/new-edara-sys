-- ============================================================================
-- AI Operations Planner — HR / Availability Human-Approved Coverage Work Bridge
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION private.work_create_ai_reviewed_hr_availability_task(
  p_decision_id UUID,p_approved_execution_by UUID
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_settings ai_ops.settings%ROWTYPE; v_decision ai_ops.decisions%ROWTYPE;
  v_review ai_ops.decision_reviews%ROWTYPE; v_snapshot ai_ops.snapshots%ROWTYPE;
  v_sc ai_ops.snapshot_cases%ROWTYPE; v_existing public.work_items%ROWTYPE; v_source public.work_items%ROWTYPE; v_work public.work_items%ROWTYPE;
  v_issues JSONB; v_now TIMESTAMPTZ:=clock_timestamp(); v_source_key TEXT; v_priority public.work_priority;
  v_title TEXT; v_description TEXT; v_fingerprint TEXT; v_source_work_id UUID; v_employee_id UUID; v_coverage_owner UUID;
BEGIN
  IF p_approved_execution_by IS NULL OR NOT private.work_actor_is_active(p_approved_execution_by) THEN
    RAISE EXCEPTION 'approved execution actor is not an active Work actor';
  END IF;
  SELECT * INTO v_decision FROM ai_ops.decisions WHERE id=p_decision_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations decision not found'; END IF;
  IF v_decision.decision_type<>'CREATE_WORK' THEN
    RETURN jsonb_build_object('committed',false,'blocked',true,'reason','bridge_supports_create_work_only','decision_type',v_decision.decision_type);
  END IF;
  IF v_decision.committed_work_item_id IS NOT NULL THEN
    SELECT * INTO v_existing FROM public.work_items WHERE id=v_decision.committed_work_item_id;
    IF FOUND THEN RETURN jsonb_build_object('committed',true,'idempotent_reuse',true,'decision_id',p_decision_id,'work_item_id',v_existing.id,'work_number',v_existing.work_number); END IF;
    RAISE EXCEPTION 'decision references missing committed Work item';
  END IF;
  SELECT * INTO v_settings FROM ai_ops.settings WHERE singleton=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations settings are not initialized'; END IF;
  IF NOT v_settings.planner_enabled THEN RETURN jsonb_build_object('committed',false,'blocked',true,'reason','planner_disabled_kill_switch'); END IF;
  IF v_settings.shadow_mode THEN RETURN jsonb_build_object('committed',false,'blocked',true,'reason','shadow_mode_blocks_operational_commit'); END IF;

  SELECT * INTO v_review FROM ai_ops.decision_reviews WHERE decision_id=p_decision_id;
  IF NOT FOUND OR v_review.review_state<>'approved' THEN RETURN jsonb_build_object('committed',false,'blocked',true,'reason','human_approval_required'); END IF;
  IF v_decision.validation_state<>'validated' THEN RETURN jsonb_build_object('committed',false,'blocked',true,'reason','decision_not_validated'); END IF;
  v_fingerprint:=md5(jsonb_build_object('id',v_decision.id,'run_id',v_decision.run_id,'case_id',v_decision.case_id,
    'revision',v_decision.revision,'decision_type',v_decision.decision_type,'recommended_owner_user_id',v_decision.recommended_owner_user_id,
    'recommended_assignee_user_id',v_decision.recommended_assignee_user_id,'responsibility_basis',v_decision.responsibility_basis,
    'concise_rationale',v_decision.concise_rationale,'confidence',v_decision.confidence,'expected_outcome',v_decision.expected_outcome,
    'next_action_text',v_decision.next_action_text,'due_at',v_decision.due_at,'review_after',v_decision.review_after,'linked_work_item_id',v_decision.linked_work_item_id)::TEXT);
  IF v_review.decision_fingerprint IS DISTINCT FROM v_fingerprint OR v_review.decision_revision<>v_decision.revision THEN
    RETURN jsonb_build_object('committed',false,'blocked',true,'reason','review_fingerprint_mismatch');
  END IF;

  SELECT * INTO v_snapshot FROM ai_ops.snapshots WHERE run_id=v_decision.run_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'decision snapshot missing'; END IF;
  SELECT * INTO v_sc FROM ai_ops.snapshot_cases sc WHERE sc.snapshot_id=v_snapshot.id AND sc.case_id=v_decision.case_id;
  IF NOT FOUND OR v_sc.domain<>'hr_availability' THEN RAISE EXCEPTION 'HR Availability bridge received unsupported frozen case'; END IF;
  v_source_work_id:=NULLIF(v_sc.facts->>'source_work_item_id','')::UUID;
  v_employee_id:=COALESCE(v_sc.entity_id,NULLIF(v_sc.facts->>'affected_employee_id','')::UUID);
  v_coverage_owner:=NULLIF(v_sc.responsibility_evidence->>'coverage_owner_user_id','')::UUID;
  IF v_source_work_id IS NULL OR v_employee_id IS NULL OR v_coverage_owner IS NULL THEN RAISE EXCEPTION 'HR Availability frozen routing identity incomplete'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('ai_ops:hr-availability-source:'||v_source_work_id::TEXT,0));
  v_source_key:='ai_ops:decision:'||p_decision_id::TEXT;
  SELECT * INTO v_existing FROM public.work_items wi WHERE wi.source_kind='system'::public.work_source_kind AND wi.source_key=v_source_key ORDER BY wi.created_at,wi.id LIMIT 1;
  IF FOUND THEN RETURN jsonb_build_object('committed',false,'blocked',true,'reason','unexpected_source_key_collision','work_item_id',v_existing.id); END IF;

  v_issues:=ai_ops.current_decision_issues(p_decision_id);
  IF jsonb_array_length(v_issues)>0 THEN
    UPDATE ai_ops.decisions SET validation_state='rejected',commit_status='rejected',
      validation_detail=validation_detail||jsonb_build_object('commit_revalidation_failed',true,'commit_revalidation_codes',v_issues,'commit_revalidation_at',v_now,'stage_only',true),
      validated_at=v_now,validated_by_user_id=NULL,updated_at=v_now WHERE id=p_decision_id;
    RETURN jsonb_build_object('committed',false,'blocked',true,'reason','current_state_changed','validation_codes',v_issues);
  END IF;
  IF v_decision.recommended_owner_user_id IS DISTINCT FROM v_coverage_owner OR v_decision.recommended_assignee_user_id IS DISTINCT FROM v_coverage_owner THEN
    RETURN jsonb_build_object('committed',false,'blocked',true,'reason','coverage_routing_changed');
  END IF;
  IF v_decision.due_at IS NULL OR v_decision.due_at<=v_now THEN RETURN jsonb_build_object('committed',false,'blocked',true,'reason','future_due_at_required'); END IF;
  IF NOT private.work_actor_is_active(v_coverage_owner) THEN RETURN jsonb_build_object('committed',false,'blocked',true,'reason','coverage_owner_became_unavailable'); END IF;
  SELECT * INTO v_source FROM public.work_items wi WHERE wi.id=v_source_work_id;
  IF NOT FOUND OR v_source.status::TEXT IN ('draft','done','cancelled') THEN RETURN jsonb_build_object('committed',false,'blocked',true,'reason','source_work_no_longer_active'); END IF;
  IF NOT private.work_link_entity_exists('employee',v_employee_id) OR NOT private.work_link_entity_exists('work_item',v_source_work_id) THEN
    RETURN jsonb_build_object('committed',false,'blocked',true,'reason','work_link_identity_no_longer_valid');
  END IF;

  v_priority:=CASE v_sc.severity WHEN 'critical' THEN 'urgent'::public.work_priority WHEN 'high' THEN 'high'::public.work_priority WHEN 'medium' THEN 'normal'::public.work_priority ELSE 'low'::public.work_priority END;
  v_title:=left('تنسيق تغطية العمل #'||COALESCE(v_source.work_number::TEXT,'—')||' أثناء فترة عدم التوفر',240);
  v_description:=left(concat_ws(E'\n',
    'توجد فترة عدم توفر مسجلة تؤثر على تنفيذ أو متابعة عمل قائم.',
    'راجع العمل الأصلي وحدد تغطية تنفيذية مناسبة أو عدّل التوزيع من خلال مسارات Work المعتمدة.',
    'لا يتم تغيير بيانات الحضور أو الإجازة أو العمل الأصلي تلقائيًا، ولا يتضمن هذا التكليف أي تقييم لأداء الموظف.'),2000);

  INSERT INTO public.work_items(kind,source_kind,source_key,title,description,expected_outcome,status,priority,visibility,
    creator_user_id,requester_user_id,accountable_owner_user_id,current_assignee_user_id,owning_department_id,branch_id,
    due_at,first_due_at,next_action_text,acknowledgement_required,completion_mode,last_meaningful_activity_at,state_version,metadata)
  VALUES ('task'::public.work_item_kind,'system'::public.work_source_kind,v_source_key,v_title,v_description,v_decision.expected_outcome,
    'draft'::public.work_item_status,v_priority,'standard'::public.work_visibility,NULL,NULL,v_coverage_owner,v_coverage_owner,
    v_source.owning_department_id,v_source.branch_id,v_decision.due_at,v_decision.due_at,v_decision.next_action_text,false,
    'assignee_closes'::public.work_completion_mode,v_now,1,jsonb_build_object('origin','ai_ops','ai_domain','hr_availability',
      'ai_case_type',v_sc.case_type,'ai_decision_id',v_decision.id,'ai_case_id',v_decision.case_id,'ai_run_id',v_decision.run_id,
      'ai_snapshot_id',v_snapshot.id,'human_review_id',v_review.id,'approved_execution_by',p_approved_execution_by,
      'source_work_item_id',v_source_work_id,'affected_employee_id',v_employee_id,'coverage_planning_task',true,
      'employee_safe_reason',v_decision.employee_safe_reason,'management_rationale_exposed',false,
      'hr_mutation_performed',false,'source_work_mutation_performed',false)) RETURNING * INTO v_work;

  PERFORM private.ai_ops_append_work_system_event(v_work.id,'work.created',NULL,'draft'::public.work_item_status,
    jsonb_build_object('source_kind','system','source_key',v_source_key,'origin','ai_ops','domain','hr_availability','case_type',v_sc.case_type,
      'decision_id',v_decision.id,'review_id',v_review.id,'source_work_item_id',v_source_work_id,'affected_employee_id',v_employee_id,
      'owner_user_id',v_coverage_owner,'assignee_user_id',v_coverage_owner,'due_at',v_work.due_at));
  UPDATE public.work_items SET status='open'::public.work_item_status,activated_at=v_now,assigned_at=v_now,
    state_version=state_version+1,last_meaningful_activity_at=v_now,updated_at=v_now WHERE id=v_work.id RETURNING * INTO v_work;
  INSERT INTO public.work_links(work_item_id,entity_type,entity_id,relation_type,label,created_by_user_id)
    VALUES (v_work.id,'work_item',v_source_work_id,'coverage_for',left('العمل الأصلي #'||COALESCE(v_source.work_number::TEXT,'—'),240),NULL)
    ON CONFLICT(work_item_id,entity_type,entity_id,relation_type) DO NOTHING;
  INSERT INTO public.work_links(work_item_id,entity_type,entity_id,relation_type,label,created_by_user_id)
    VALUES (v_work.id,'employee',v_employee_id,'availability_for','تغطية استمرارية تشغيلية',NULL)
    ON CONFLICT(work_item_id,entity_type,entity_id,relation_type) DO NOTHING;
  PERFORM private.ai_ops_append_work_system_event(v_work.id,'work.activated','draft'::public.work_item_status,'open'::public.work_item_status,
    jsonb_build_object('source','ai_ops_human_approved','domain','hr_availability','case_type',v_sc.case_type,'decision_id',v_decision.id,
      'approved_by_user_id',p_approved_execution_by,'source_work_item_id',v_source_work_id,'affected_employee_id',v_employee_id));

  UPDATE ai_ops.decisions SET committed_work_item_id=v_work.id,committed_at=v_now,commit_status='committed',
    validation_detail=validation_detail||jsonb_build_object('commit_revalidated_against_current_state',true,'commit_revalidated_at',v_now,
      'human_review_id',v_review.id,'approved_execution_by',p_approved_execution_by,'domain','hr_availability','stage_only',false,
      'source_work_item_id',v_source_work_id,'affected_employee_id',v_employee_id,'hr_mutation_performed',false,'source_work_mutation_performed',false),updated_at=v_now
    WHERE id=p_decision_id;
  UPDATE ai_ops.cases SET status='actioned',updated_at=v_now,state_version=state_version+1 WHERE id=v_decision.case_id;
  UPDATE ai_ops.planner_runs SET checkpoint='reviewed_work_committed',work_created_count=work_created_count+1,
    result_summary=result_summary||jsonb_build_object('last_committed_decision_id',v_decision.id,'last_committed_work_item_id',v_work.id,
      'last_commit_at',v_now,'last_commit_domain','hr_availability'),updated_at=v_now WHERE id=v_decision.run_id;
  RETURN jsonb_build_object('committed',true,'idempotent_reuse',false,'decision_id',p_decision_id,'work_item_id',v_work.id,
    'work_number',v_work.work_number,'source_key',v_source_key,'source_work_item_id',v_source_work_id,'affected_employee_id',v_employee_id,
    'domain','hr_availability','operational_mutation','coverage_work_create_only','hr_mutation_performed',false,'source_work_mutation_performed',false);
END;
$$;
REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_hr_availability_task(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;

ALTER FUNCTION private.work_create_ai_reviewed_task(UUID,UUID)
  RENAME TO work_create_ai_reviewed_task_six_domain_v1;
REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_task_six_domain_v1(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.work_create_ai_reviewed_task(p_decision_id UUID,p_approved_execution_by UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_domain TEXT;
BEGIN
  SELECT sc.domain INTO v_domain FROM ai_ops.decisions d JOIN ai_ops.snapshots s ON s.run_id=d.run_id
  JOIN ai_ops.snapshot_cases sc ON sc.snapshot_id=s.id AND sc.case_id=d.case_id WHERE d.id=p_decision_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'decision-time frozen evidence missing'; END IF;
  IF v_domain='hr_availability' THEN
    RETURN private.work_create_ai_reviewed_hr_availability_task(p_decision_id,p_approved_execution_by);
  END IF;
  RETURN private.work_create_ai_reviewed_task_six_domain_v1(p_decision_id,p_approved_execution_by);
END;
$$;
REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_task(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION private.work_create_ai_reviewed_hr_availability_task(UUID,UUID) IS
  'Human-approved HR/Availability coverage bridge; creates employee-safe manager coverage Work only after same-transaction revalidation and never mutates HR or source Work.';

RESET lock_timeout;
RESET statement_timeout;
