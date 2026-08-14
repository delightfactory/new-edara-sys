-- Work Management — bind completion_mode=approval to the generic Approval Engine.
SET lock_timeout='5s';
SET statement_timeout='60s';

CREATE OR REPLACE FUNCTION public.work_complete(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT,
  p_completion_summary TEXT,
  p_completion_output JSONB DEFAULT '{}'::JSONB
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_item public.work_items%ROWTYPE;
  v_blockers JSONB;
  v_review public.work_completion_reviews%ROWTYPE;
  v_approval_request_id UUID;
  v_approval_due TIMESTAMPTZ;
  v_from public.work_item_status;
  v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_complete',
    jsonb_build_object(
      'work_item_id',p_work_item_id,'expected_version',p_expected_version,
      'completion_summary',p_completion_summary,'completion_output',COALESCE(p_completion_output,'{}'::JSONB)
    ),p_work_item_id
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_complete','NOT_FOUND','المهمة غير موجودة',p_work_item_id); END IF;
  IF v_item.state_version<>p_expected_version THEN RETURN private.work_command_error(p_operation_id,'work_complete','VERSION_CONFLICT','تم تعديل المهمة بواسطة مستخدم آخر',p_work_item_id); END IF;
  IF NOT private.work_actor_can_update_item(v_actor,p_work_item_id) THEN RETURN private.work_command_error(p_operation_id,'work_complete','FORBIDDEN','غير مصرح بإنهاء المهمة',p_work_item_id); END IF;
  IF v_item.status NOT IN ('open','in_progress','waiting') THEN RETURN private.work_command_error(p_operation_id,'work_complete','INVALID_STATE','لا يمكن إنهاء المهمة من حالتها الحالية',p_work_item_id); END IF;
  IF p_completion_summary IS NULL OR btrim(p_completion_summary)='' THEN RETURN private.work_command_error(p_operation_id,'work_complete','COMPLETION_SUMMARY_REQUIRED','ملخص نتيجة التنفيذ مطلوب',p_work_item_id); END IF;
  IF jsonb_typeof(COALESCE(p_completion_output,'{}'::JSONB))<>'object' THEN RETURN private.work_command_error(p_operation_id,'work_complete','INVALID_OUTPUT','ناتج التنفيذ يجب أن يكون كائن بيانات',p_work_item_id); END IF;

  v_blockers:=private.work_completion_blockers(p_work_item_id);
  IF COALESCE((v_blockers->>'required_checklist_open')::BOOLEAN,false) THEN RETURN private.work_command_error(p_operation_id,'work_complete','CHECKLIST_INCOMPLETE','توجد بنود إلزامية غير مكتملة',p_work_item_id); END IF;
  IF COALESCE((v_blockers->>'required_child_open')::BOOLEAN,false) THEN RETURN private.work_command_error(p_operation_id,'work_complete','CHILD_WORK_OPEN','توجد مهام فرعية مطلوبة لم تُغلق',p_work_item_id); END IF;
  IF COALESCE((v_blockers->>'hard_dependency_open')::BOOLEAN,false) THEN RETURN private.work_command_error(p_operation_id,'work_complete','DEPENDENCY_OPEN','توجد اعتمادات إلزامية لم تكتمل',p_work_item_id); END IF;

  v_from:=v_item.status;

  IF v_item.completion_mode='approval'::public.work_completion_mode THEN
    IF v_item.completion_approval_template_id IS NULL THEN
      RETURN private.work_command_error(p_operation_id,'work_complete','APPROVAL_TEMPLATE_REQUIRED','المهمة تتطلب اعتماد إتمام ولم يتم ربط نموذج اعتماد',p_work_item_id);
    END IF;

    BEGIN
      v_approval_request_id:=private.work_start_approval_request(
        p_work_item_id,v_item.completion_approval_template_id,'completion',
        jsonb_build_object(
          'completion_summary',p_completion_summary,
          'completion_output',COALESCE(p_completion_output,'{}'::JSONB),
          'submitted_by_user_id',v_actor,
          'submitted_work_version',p_expected_version
        ),v_actor,p_operation_id
      );

      SELECT s.due_at INTO v_approval_due
      FROM public.work_approval_stage_instances s
      JOIN public.work_approval_requests r ON r.id=s.approval_request_id
      WHERE r.id=v_approval_request_id AND s.status='pending'
      ORDER BY s.stage_order LIMIT 1;

      UPDATE public.work_items
      SET status='pending_approval',completion_summary=p_completion_summary,
          completion_output=COALESCE(p_completion_output,'{}'::JSONB),completed_by_user_id=v_actor,
          next_action_text='اعتماد نتيجة التنفيذ',next_action_at=v_approval_due,
          waiting_on_type=NULL,waiting_on_user_id=NULL,waiting_on_entity_type=NULL,waiting_on_entity_id=NULL,
          waiting_on_label=NULL,waiting_reason=NULL,waiting_since=NULL,
          state_version=state_version+1,last_meaningful_activity_at=clock_timestamp()
      WHERE id=p_work_item_id RETURNING * INTO v_item;

      PERFORM private.work_append_user_event(
        v_item.id,'work.completion_approval_requested',v_actor,p_operation_id,v_from,'pending_approval',
        jsonb_build_object('approval_request_id',v_approval_request_id,'approval_due_at',v_approval_due)
      );

      v_result:=jsonb_build_object(
        'work_item_id',v_item.id,'status',v_item.status,'state_version',v_item.state_version,
        'approval_request_id',v_approval_request_id
      );
      RETURN private.work_command_success(p_operation_id,'work_complete',v_item.id,v_result);
    EXCEPTION WHEN OTHERS THEN
      RETURN private.work_command_error(p_operation_id,'work_complete','APPROVAL_START_FAILED','تعذر بدء اعتماد نتيجة التنفيذ',p_work_item_id);
    END;
  END IF;

  IF v_item.completion_mode='owner_review'::public.work_completion_mode
     AND v_item.accountable_owner_user_id IS DISTINCT FROM v_actor THEN
    IF v_item.accountable_owner_user_id IS NULL OR NOT private.work_actor_is_active(v_item.accountable_owner_user_id) THEN
      RETURN private.work_command_error(p_operation_id,'work_complete','OWNER_REVIEWER_UNAVAILABLE','لا يوجد مالك مسؤول نشط لمراجعة الإتمام',p_work_item_id);
    END IF;

    INSERT INTO public.work_completion_reviews(
      work_item_id,requested_by_user_id,reviewer_user_id,completion_summary,completion_output
    ) VALUES (
      p_work_item_id,v_actor,v_item.accountable_owner_user_id,p_completion_summary,COALESCE(p_completion_output,'{}'::JSONB)
    ) RETURNING * INTO v_review;

    UPDATE public.work_items
    SET status='pending_approval',completion_summary=p_completion_summary,
        completion_output=COALESCE(p_completion_output,'{}'::JSONB),completed_by_user_id=v_actor,
        next_action_text='مراجعة نتيجة التنفيذ',next_action_at=NULL,
        state_version=state_version+1,last_meaningful_activity_at=clock_timestamp()
    WHERE id=p_work_item_id RETURNING * INTO v_item;

    PERFORM private.work_append_user_event(
      v_item.id,'work.completion_review_requested',v_actor,p_operation_id,v_from,'pending_approval',
      jsonb_build_object('review_id',v_review.id,'reviewer_user_id',v_review.reviewer_user_id)
    );
    v_result:=jsonb_build_object('work_item_id',v_item.id,'status',v_item.status,'state_version',v_item.state_version,'review_id',v_review.id);
    RETURN private.work_command_success(p_operation_id,'work_complete',v_item.id,v_result);
  END IF;

  UPDATE public.work_items
  SET status='done',completion_summary=p_completion_summary,
      completion_output=COALESCE(p_completion_output,'{}'::JSONB),completed_by_user_id=v_actor,
      completed_at=clock_timestamp(),next_action_text=NULL,next_action_at=NULL,
      waiting_on_type=NULL,waiting_on_user_id=NULL,waiting_on_entity_type=NULL,waiting_on_entity_id=NULL,
      waiting_on_label=NULL,waiting_reason=NULL,waiting_since=NULL,
      state_version=state_version+1,last_meaningful_activity_at=clock_timestamp()
  WHERE id=p_work_item_id RETURNING * INTO v_item;

  PERFORM private.work_append_user_event(
    v_item.id,'work.completed',v_actor,p_operation_id,v_from,'done',jsonb_build_object('completion_summary',p_completion_summary)
  );
  v_result:=jsonb_build_object('work_item_id',v_item.id,'status',v_item.status,'state_version',v_item.state_version,'completed_at',v_item.completed_at);
  RETURN private.work_command_success(p_operation_id,'work_complete',v_item.id,v_result);
END;
$$;

RESET lock_timeout;
RESET statement_timeout;
