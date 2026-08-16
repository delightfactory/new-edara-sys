-- Work Management — Approval Engine runtime, delegation and Work bindings.
SET lock_timeout='5s';
SET statement_timeout='60s';

CREATE OR REPLACE FUNCTION private.work_resolve_approval_selector(
  p_selector_kind public.work_approval_selector_kind,
  p_selector_user_id UUID,
  p_work_item_id UUID
) RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_item public.work_items%ROWTYPE;
  v_user UUID;
BEGIN
  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  CASE p_selector_kind
    WHEN 'user' THEN v_user:=p_selector_user_id;
    WHEN 'work_owner' THEN v_user:=v_item.accountable_owner_user_id;
    WHEN 'assignee' THEN v_user:=v_item.current_assignee_user_id;
    WHEN 'department_manager' THEN
      SELECT d.manager_id INTO v_user FROM public.hr_departments d
      WHERE d.id=v_item.owning_department_id AND d.is_active=true;
    WHEN 'branch_manager' THEN
      SELECT b.manager_id INTO v_user FROM public.branches b
      WHERE b.id=v_item.branch_id AND COALESCE(b.is_active,true);
  END CASE;

  IF NOT private.work_actor_is_active(v_user) THEN RETURN NULL; END IF;
  RETURN v_user;
END;
$$;

CREATE OR REPLACE FUNCTION private.work_activate_approval_stage(
  p_approval_request_id UUID,
  p_stage_order INTEGER
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_request public.work_approval_requests%ROWTYPE;
  v_stage public.work_approval_stages%ROWTYPE;
  v_template_id UUID;
  v_instance public.work_approval_stage_instances%ROWTYPE;
  v_def public.work_approval_stage_approvers%ROWTYPE;
  v_original UUID;
  v_effective UUID;
  v_count INTEGER:=0;
BEGIN
  SELECT * INTO v_request FROM public.work_approval_requests WHERE id=p_approval_request_id FOR UPDATE;
  IF NOT FOUND OR v_request.status<>'pending' THEN RAISE EXCEPTION 'approval request is not pending'; END IF;

  SELECT s.* INTO v_stage
  FROM public.work_approval_stages s
  WHERE s.template_version_id=v_request.template_version_id AND s.stage_order=p_stage_order;
  IF NOT FOUND THEN RAISE EXCEPTION 'approval stage does not exist'; END IF;

  SELECT v.template_id INTO v_template_id
  FROM public.work_approval_template_versions v
  WHERE v.id=v_request.template_version_id;

  INSERT INTO public.work_approval_stage_instances(
    approval_request_id,stage_definition_id,stage_order,decision_mode,status,activated_at,due_at
  ) VALUES (
    v_request.id,v_stage.id,v_stage.stage_order,v_stage.decision_mode,'pending',clock_timestamp(),
    CASE WHEN v_stage.deadline_minutes IS NULL THEN NULL
         ELSE clock_timestamp()+make_interval(mins=>v_stage.deadline_minutes) END
  ) RETURNING * INTO v_instance;

  FOR v_def IN
    SELECT * FROM public.work_approval_stage_approvers
    WHERE stage_id=v_stage.id ORDER BY sort_order,id
  LOOP
    v_original:=private.work_resolve_approval_selector(
      v_def.selector_kind,v_def.selector_user_id,v_request.work_item_id
    );
    IF v_original IS NULL THEN
      RAISE EXCEPTION 'approval selector resolved to no active approver';
    END IF;
    v_effective:=private.work_resolve_approval_delegate(
      v_original,v_template_id,v_request.context_kind,clock_timestamp()
    );
    IF NOT private.work_actor_is_active(v_effective) THEN
      RAISE EXCEPTION 'effective approver is inactive';
    END IF;

    INSERT INTO public.work_approval_assignments(
      stage_instance_id,original_approver_user_id,effective_approver_user_id
    ) VALUES (v_instance.id,v_original,v_effective)
    ON CONFLICT (stage_instance_id,original_approver_user_id) DO NOTHING;
    v_count:=v_count+1;
  END LOOP;

  IF v_count=0 THEN RAISE EXCEPTION 'approval stage has no approvers'; END IF;

  UPDATE public.work_approval_requests
  SET current_stage_order=v_stage.stage_order
  WHERE id=v_request.id;

  RETURN v_instance.id;
END;
$$;

CREATE OR REPLACE FUNCTION private.work_start_approval_request(
  p_work_item_id UUID,
  p_template_id UUID,
  p_context_kind public.work_approval_context_kind,
  p_context_payload JSONB,
  p_requested_by_user_id UUID,
  p_operation_id UUID
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_template public.work_approval_templates%ROWTYPE;
  v_version public.work_approval_template_versions%ROWTYPE;
  v_request public.work_approval_requests%ROWTYPE;
  v_first_order INTEGER;
BEGIN
  SELECT * INTO v_template FROM public.work_approval_templates WHERE id=p_template_id;
  IF NOT FOUND OR NOT v_template.is_active OR v_template.current_published_version_id IS NULL THEN
    RAISE EXCEPTION 'approval template is not published';
  END IF;
  SELECT * INTO v_version FROM public.work_approval_template_versions
  WHERE id=v_template.current_published_version_id AND template_id=v_template.id AND status='published';
  IF NOT FOUND THEN RAISE EXCEPTION 'published approval version missing'; END IF;

  SELECT min(stage_order) INTO v_first_order
  FROM public.work_approval_stages WHERE template_version_id=v_version.id;
  IF v_first_order IS NULL THEN RAISE EXCEPTION 'approval template has no stages'; END IF;

  INSERT INTO public.work_approval_requests(
    work_item_id,template_version_id,context_kind,context_payload,status,requested_by_user_id,requested_at,state_version
  ) VALUES (
    p_work_item_id,v_version.id,p_context_kind,COALESCE(p_context_payload,'{}'::JSONB),
    'pending',p_requested_by_user_id,clock_timestamp(),1
  ) RETURNING * INTO v_request;

  PERFORM private.work_activate_approval_stage(v_request.id,v_first_order);
  PERFORM private.work_append_user_event(
    p_work_item_id,'work.approval.requested',p_requested_by_user_id,p_operation_id,NULL,NULL,
    jsonb_build_object(
      'approval_request_id',v_request.id,'template_id',v_template.id,
      'template_version_id',v_version.id,'context_kind',p_context_kind,'stage_order',v_first_order
    )
  );
  RETURN v_request.id;
END;
$$;

CREATE OR REPLACE FUNCTION private.work_finalize_approval_request(
  p_approval_request_id UUID,
  p_status public.work_approval_runtime_status,
  p_actor_user_id UUID,
  p_operation_id UUID,
  p_note TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_request public.work_approval_requests%ROWTYPE;
  v_item public.work_items%ROWTYPE;
  v_old_due TIMESTAMPTZ;
  v_new_due TIMESTAMPTZ;
BEGIN
  SELECT * INTO v_request FROM public.work_approval_requests WHERE id=p_approval_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'approval request not found'; END IF;
  SELECT * INTO v_item FROM public.work_items WHERE id=v_request.work_item_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'work item not found'; END IF;

  UPDATE public.work_approval_requests
  SET status=p_status,completed_at=clock_timestamp(),state_version=state_version+1
  WHERE id=v_request.id;

  IF v_request.context_kind='completion' THEN
    IF p_status='approved' THEN
      IF v_item.status<>'pending_approval' THEN RAISE EXCEPTION 'completion approval work state mismatch'; END IF;
      UPDATE public.work_items
      SET status='done',completed_at=clock_timestamp(),next_action_text=NULL,next_action_at=NULL,
          state_version=state_version+1,last_meaningful_activity_at=clock_timestamp()
      WHERE id=v_item.id;
      PERFORM private.work_append_user_event(
        v_item.id,'work.completion_approved',p_actor_user_id,p_operation_id,
        'pending_approval','done',jsonb_build_object('approval_request_id',v_request.id,'note',p_note)
      );
    ELSIF p_status IN ('rejected','changes_required') THEN
      UPDATE public.work_items
      SET status='in_progress',completion_summary=NULL,completion_output='{}'::JSONB,completed_by_user_id=NULL,
          next_action_text=left(CASE WHEN p_status='changes_required' THEN 'تنفيذ التعديلات المطلوبة: ' ELSE 'مراجعة سبب رفض الاعتماد: ' END||COALESCE(p_note,''),500),
          next_action_at=NULL,state_version=state_version+1,last_meaningful_activity_at=clock_timestamp()
      WHERE id=v_item.id;
      PERFORM private.work_append_user_event(
        v_item.id,CASE WHEN p_status='changes_required' THEN 'work.completion_changes_required' ELSE 'work.completion_rejected' END,
        p_actor_user_id,p_operation_id,'pending_approval','in_progress',
        jsonb_build_object('approval_request_id',v_request.id,'note',p_note)
      );
    END IF;

  ELSIF v_request.context_kind='due_change' THEN
    IF p_status='approved' THEN
      v_old_due:=v_item.due_at;
      BEGIN
        v_new_due:=(v_request.context_payload->>'new_due_at')::TIMESTAMPTZ;
      EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'invalid due change approval payload';
      END;
      UPDATE public.work_items
      SET due_at=v_new_due,first_due_at=COALESCE(first_due_at,v_old_due,v_new_due),
          state_version=state_version+1,last_meaningful_activity_at=clock_timestamp()
      WHERE id=v_item.id;
      PERFORM private.work_append_user_event(
        v_item.id,'work.due_change_approved',p_actor_user_id,p_operation_id,v_item.status,v_item.status,
        jsonb_build_object('approval_request_id',v_request.id,'from_due_at',v_old_due,'to_due_at',v_new_due,'note',p_note)
      );
    ELSE
      PERFORM private.work_append_user_event(
        v_item.id,CASE WHEN p_status='changes_required' THEN 'work.due_change_changes_required' ELSE 'work.due_change_rejected' END,
        p_actor_user_id,p_operation_id,v_item.status,v_item.status,
        jsonb_build_object('approval_request_id',v_request.id,'requested_due_at',v_request.context_payload->>'new_due_at','note',p_note)
      );
    END IF;
  ELSE
    PERFORM private.work_append_user_event(
      v_item.id,'work.approval.finished',p_actor_user_id,p_operation_id,v_item.status,v_item.status,
      jsonb_build_object('approval_request_id',v_request.id,'status',p_status,'context_kind',v_request.context_kind,'note',p_note)
    );
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.work_decide_approval(
  p_operation_id UUID,
  p_assignment_id UUID,
  p_expected_approval_version BIGINT,
  p_decision TEXT,
  p_note TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_assignment public.work_approval_assignments%ROWTYPE;
  v_stage public.work_approval_stage_instances%ROWTYPE;
  v_stage_def public.work_approval_stages%ROWTYPE;
  v_request public.work_approval_requests%ROWTYPE;
  v_work_item_id UUID;
  v_next_order INTEGER;
  v_stage_approved BOOLEAN:=false;
  v_final_status public.work_approval_runtime_status;
  v_acting_for UUID;
  v_result JSONB;
BEGIN
  SELECT r.work_item_id INTO v_work_item_id
  FROM public.work_approval_assignments a
  JOIN public.work_approval_stage_instances s ON s.id=a.stage_instance_id
  JOIN public.work_approval_requests r ON r.id=s.approval_request_id
  WHERE a.id=p_assignment_id;
  IF v_work_item_id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'operation_id',p_operation_id,'operation','work_decide_approval','replayed',false,'error',jsonb_build_object('code','NOT_FOUND','message','طلب الاعتماد غير موجود'));
  END IF;

  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_decide_approval',
    jsonb_build_object('assignment_id',p_assignment_id,'expected_approval_version',p_expected_approval_version,'decision',p_decision,'note',p_note),
    v_work_item_id
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_assignment FROM public.work_approval_assignments WHERE id=p_assignment_id FOR UPDATE;
  SELECT * INTO v_stage FROM public.work_approval_stage_instances WHERE id=v_assignment.stage_instance_id FOR UPDATE;
  SELECT * INTO v_request FROM public.work_approval_requests WHERE id=v_stage.approval_request_id FOR UPDATE;
  SELECT * INTO v_stage_def FROM public.work_approval_stages WHERE id=v_stage.stage_definition_id;

  IF v_request.state_version<>p_expected_approval_version THEN
    RETURN private.work_command_error(p_operation_id,'work_decide_approval','VERSION_CONFLICT','تم تحديث طلب الاعتماد بواسطة مستخدم آخر',v_work_item_id);
  END IF;
  IF v_request.status<>'pending' OR v_stage.status<>'pending' OR v_assignment.status<>'pending' THEN
    RETURN private.work_command_error(p_operation_id,'work_decide_approval','ALREADY_DECIDED','مرحلة الاعتماد أو القرار لم تعد معلقة',v_work_item_id);
  END IF;
  IF v_assignment.effective_approver_user_id<>v_actor THEN
    IF NOT (COALESCE(public.check_permission(v_actor,'work.approvals.decide'),false) AND private.work_user_can_manage_item(v_actor,v_work_item_id)) THEN
      RETURN private.work_command_error(p_operation_id,'work_decide_approval','FORBIDDEN','هذا الاعتماد ليس مسندًا إليك',v_work_item_id);
    END IF;
  END IF;
  IF p_decision NOT IN ('approve','reject','changes_required') THEN
    RETURN private.work_command_error(p_operation_id,'work_decide_approval','INVALID_DECISION','قرار الاعتماد غير صحيح',v_work_item_id);
  END IF;
  IF p_decision='changes_required' AND NOT v_stage_def.allow_changes_required THEN
    RETURN private.work_command_error(p_operation_id,'work_decide_approval','CHANGES_NOT_ALLOWED','هذه المرحلة لا تسمح بطلب تعديلات',v_work_item_id);
  END IF;
  IF p_decision IN ('reject','changes_required') AND (p_note IS NULL OR btrim(p_note)='') THEN
    RETURN private.work_command_error(p_operation_id,'work_decide_approval','NOTE_REQUIRED','سبب القرار مطلوب',v_work_item_id);
  END IF;

  v_acting_for:=CASE WHEN v_actor<>v_assignment.original_approver_user_id THEN v_assignment.original_approver_user_id ELSE NULL END;
  UPDATE public.work_approval_assignments
  SET status=CASE p_decision
        WHEN 'approve' THEN 'approved'::public.work_approval_assignment_status
        WHEN 'reject' THEN 'rejected'::public.work_approval_assignment_status
        ELSE 'changes_required'::public.work_approval_assignment_status END,
      decision_note=p_note,decided_at=clock_timestamp(),decided_by_user_id=v_actor,acting_for_user_id=v_acting_for
  WHERE id=v_assignment.id;

  PERFORM private.work_append_user_event(
    v_work_item_id,'work.approval.decision',v_actor,p_operation_id,NULL,NULL,
    jsonb_build_object('approval_request_id',v_request.id,'stage_order',v_stage.stage_order,'assignment_id',v_assignment.id,'decision',p_decision,'note',p_note),
    v_acting_for
  );

  IF p_decision='reject' THEN
    UPDATE public.work_approval_stage_instances SET status='rejected',decided_at=clock_timestamp() WHERE id=v_stage.id;
    UPDATE public.work_approval_assignments SET status='skipped'
      WHERE stage_instance_id=v_stage.id AND status='pending';
    v_final_status:='rejected';
  ELSIF p_decision='changes_required' THEN
    UPDATE public.work_approval_stage_instances SET status='changes_required',decided_at=clock_timestamp() WHERE id=v_stage.id;
    UPDATE public.work_approval_assignments SET status='skipped'
      WHERE stage_instance_id=v_stage.id AND status='pending';
    v_final_status:='changes_required';
  ELSE
    IF v_stage.decision_mode='any' THEN
      v_stage_approved:=true;
      UPDATE public.work_approval_assignments SET status='skipped'
      WHERE stage_instance_id=v_stage.id AND status='pending';
    ELSE
      v_stage_approved:=NOT EXISTS (
        SELECT 1 FROM public.work_approval_assignments a
        WHERE a.stage_instance_id=v_stage.id AND a.status<>'approved'
      );
    END IF;

    IF v_stage_approved THEN
      UPDATE public.work_approval_stage_instances SET status='approved',decided_at=clock_timestamp() WHERE id=v_stage.id;
      SELECT min(stage_order) INTO v_next_order
      FROM public.work_approval_stages
      WHERE template_version_id=v_request.template_version_id AND stage_order>v_stage.stage_order;
      IF v_next_order IS NULL THEN
        v_final_status:='approved';
      ELSE
        PERFORM private.work_activate_approval_stage(v_request.id,v_next_order);
      END IF;
    END IF;
  END IF;

  UPDATE public.work_approval_requests
  SET state_version=state_version+1
  WHERE id=v_request.id
  RETURNING * INTO v_request;

  IF v_final_status IS NOT NULL THEN
    PERFORM private.work_finalize_approval_request(v_request.id,v_final_status,v_actor,p_operation_id,p_note);
    SELECT * INTO v_request FROM public.work_approval_requests WHERE id=v_request.id;
  END IF;

  v_result:=jsonb_build_object(
    'approval_request_id',v_request.id,'work_item_id',v_request.work_item_id,'status',v_request.status,
    'current_stage_order',v_request.current_stage_order,'state_version',v_request.state_version,
    'decision',p_decision,'acting_for_user_id',v_acting_for
  );
  RETURN private.work_command_success(p_operation_id,'work_decide_approval',v_work_item_id,v_result);
END;
$$;

CREATE OR REPLACE FUNCTION public.work_request_due_change(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT,
  p_new_due_at TIMESTAMPTZ,
  p_reason TEXT,
  p_approval_template_id UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_item public.work_items%ROWTYPE;
  v_request_id UUID;
  v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_request_due_change',
    jsonb_build_object('work_item_id',p_work_item_id,'expected_version',p_expected_version,'new_due_at',p_new_due_at,'reason',p_reason,'approval_template_id',p_approval_template_id),
    p_work_item_id
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_request_due_change','NOT_FOUND','المهمة غير موجودة',p_work_item_id); END IF;
  IF v_item.state_version<>p_expected_version THEN RETURN private.work_command_error(p_operation_id,'work_request_due_change','VERSION_CONFLICT','تم تعديل المهمة بواسطة مستخدم آخر',p_work_item_id); END IF;
  IF NOT private.work_actor_can_update_item(v_actor,p_work_item_id) THEN RETURN private.work_command_error(p_operation_id,'work_request_due_change','FORBIDDEN','غير مصرح بطلب تعديل الموعد',p_work_item_id); END IF;
  IF v_item.status IN ('done','cancelled') THEN RETURN private.work_command_error(p_operation_id,'work_request_due_change','INVALID_STATE','المهمة منتهية',p_work_item_id); END IF;
  IF p_new_due_at IS NULL OR p_new_due_at<=clock_timestamp() THEN RETURN private.work_command_error(p_operation_id,'work_request_due_change','INVALID_DUE_DATE','الموعد الجديد يجب أن يكون في المستقبل',p_work_item_id); END IF;
  IF p_reason IS NULL OR btrim(p_reason)='' THEN RETURN private.work_command_error(p_operation_id,'work_request_due_change','REASON_REQUIRED','سبب تعديل الموعد مطلوب',p_work_item_id); END IF;
  IF p_approval_template_id IS NULL THEN RETURN private.work_command_error(p_operation_id,'work_request_due_change','APPROVAL_TEMPLATE_REQUIRED','نموذج اعتماد تعديل الموعد مطلوب',p_work_item_id); END IF;

  BEGIN
    v_request_id:=private.work_start_approval_request(
      p_work_item_id,p_approval_template_id,'due_change',
      jsonb_build_object('old_due_at',v_item.due_at,'new_due_at',p_new_due_at,'reason',p_reason,'requested_work_version',p_expected_version),
      v_actor,p_operation_id
    );
    UPDATE public.work_items
    SET state_version=state_version+1,last_meaningful_activity_at=clock_timestamp()
    WHERE id=p_work_item_id RETURNING * INTO v_item;

    v_result:=jsonb_build_object(
      'work_item_id',v_item.id,'status',v_item.status,'state_version',v_item.state_version,
      'approval_request_id',v_request_id,'requested_due_at',p_new_due_at
    );
    RETURN private.work_command_success(p_operation_id,'work_request_due_change',v_item.id,v_result);
  EXCEPTION WHEN OTHERS THEN
    RETURN private.work_command_error(p_operation_id,'work_request_due_change','APPROVAL_START_FAILED','تعذر بدء اعتماد تعديل الموعد',p_work_item_id);
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.work_create_approval_delegation(
  p_operation_id UUID,
  p_delegate_user_id UUID,
  p_starts_at TIMESTAMPTZ DEFAULT now(),
  p_ends_at TIMESTAMPTZ DEFAULT NULL,
  p_template_id UUID DEFAULT NULL,
  p_context_kind public.work_approval_context_kind DEFAULT NULL,
  p_reason TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_delegation public.work_approval_delegations%ROWTYPE;
  v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_create_approval_delegation',
    jsonb_build_object('delegate_user_id',p_delegate_user_id,'starts_at',p_starts_at,'ends_at',p_ends_at,'template_id',p_template_id,'context_kind',p_context_kind,'reason',p_reason),NULL
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;

  IF NOT private.work_actor_is_active(p_delegate_user_id) OR p_delegate_user_id=v_actor THEN
    RETURN private.work_command_error(p_operation_id,'work_create_approval_delegation','INVALID_DELEGATE','المفوض إليه يجب أن يكون مستخدمًا نشطًا مختلفًا');
  END IF;
  IF p_ends_at IS NOT NULL AND p_ends_at<=p_starts_at THEN
    RETURN private.work_command_error(p_operation_id,'work_create_approval_delegation','INVALID_WINDOW','فترة التفويض غير صحيحة');
  END IF;

  INSERT INTO public.work_approval_delegations(
    delegator_user_id,delegate_user_id,template_id,context_kind,starts_at,ends_at,reason,created_by_user_id
  ) VALUES (
    v_actor,p_delegate_user_id,p_template_id,p_context_kind,COALESCE(p_starts_at,clock_timestamp()),p_ends_at,p_reason,v_actor
  ) RETURNING * INTO v_delegation;

  v_result:=jsonb_build_object('delegation_id',v_delegation.id,'delegator_user_id',v_actor,'delegate_user_id',p_delegate_user_id,'starts_at',v_delegation.starts_at,'ends_at',v_delegation.ends_at);
  RETURN private.work_command_success(p_operation_id,'work_create_approval_delegation',NULL,v_result);
END;
$$;

REVOKE ALL ON FUNCTION private.work_resolve_approval_selector(public.work_approval_selector_kind,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_activate_approval_stage(UUID,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_start_approval_request(UUID,UUID,public.work_approval_context_kind,JSONB,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_finalize_approval_request(UUID,public.work_approval_runtime_status,UUID,UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.work_decide_approval(UUID,UUID,BIGINT,TEXT,TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_request_due_change(UUID,UUID,BIGINT,TIMESTAMPTZ,TEXT,UUID) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_create_approval_delegation(UUID,UUID,TIMESTAMPTZ,TIMESTAMPTZ,UUID,public.work_approval_context_kind,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.work_decide_approval(UUID,UUID,BIGINT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_request_due_change(UUID,UUID,BIGINT,TIMESTAMPTZ,TEXT,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_create_approval_delegation(UUID,UUID,TIMESTAMPTZ,TIMESTAMPTZ,UUID,public.work_approval_context_kind,TEXT) TO authenticated;

RESET lock_timeout;
RESET statement_timeout;
