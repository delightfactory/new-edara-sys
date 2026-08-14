-- Work Management — request triage atomicity hardening.
-- Validation must complete before first-response or Work state is mutated.
SET lock_timeout='5s';
SET statement_timeout='60s';

CREATE OR REPLACE FUNCTION public.work_triage_request(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT,
  p_decision TEXT,
  p_assignee_user_id UUID DEFAULT NULL,
  p_owner_user_id UUID DEFAULT NULL,
  p_due_at TIMESTAMPTZ DEFAULT NULL,
  p_next_action_text VARCHAR(500) DEFAULT NULL,
  p_follow_up_at TIMESTAMPTZ DEFAULT NULL,
  p_note TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_item public.work_items%ROWTYPE;
  v_request public.work_requests%ROWTYPE;
  v_queue public.work_queues%ROWTYPE;
  v_owner UUID;
  v_now TIMESTAMPTZ:=clock_timestamp();
  v_from public.work_item_status;
  v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_triage_request',
    jsonb_build_object(
      'work_item_id',p_work_item_id,'expected_version',p_expected_version,'decision',p_decision,
      'assignee_user_id',p_assignee_user_id,'owner_user_id',p_owner_user_id,'due_at',p_due_at,
      'next_action_text',p_next_action_text,'follow_up_at',p_follow_up_at,'note',p_note
    ),p_work_item_id
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id FOR UPDATE;
  IF NOT FOUND OR v_item.kind<>'request'::public.work_item_kind THEN
    RETURN private.work_command_error(p_operation_id,'work_triage_request','NOT_FOUND','الطلب غير موجود',p_work_item_id);
  END IF;
  SELECT * INTO v_request FROM public.work_requests WHERE work_item_id=p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN private.work_command_error(p_operation_id,'work_triage_request','REQUEST_RUNTIME_MISSING','بيانات تشغيل الطلب غير موجودة',p_work_item_id);
  END IF;
  SELECT * INTO v_queue FROM public.work_queues WHERE id=v_request.queue_id;
  IF NOT FOUND OR NOT v_queue.is_active THEN
    RETURN private.work_command_error(p_operation_id,'work_triage_request','QUEUE_UNAVAILABLE','جهة استقبال الطلب غير متاحة',p_work_item_id);
  END IF;

  IF v_item.state_version<>p_expected_version THEN
    RETURN private.work_command_error(p_operation_id,'work_triage_request','VERSION_CONFLICT','تم تعديل الطلب بواسطة مستخدم آخر',p_work_item_id);
  END IF;
  IF NOT private.work_user_can_triage_queue(v_actor,v_request.queue_id) THEN
    RETURN private.work_command_error(p_operation_id,'work_triage_request','FORBIDDEN','غير مصرح لك بفرز هذا الطلب',p_work_item_id);
  END IF;
  IF v_request.triaged_at IS NOT NULL THEN
    RETURN private.work_command_error(p_operation_id,'work_triage_request','ALREADY_TRIAGED','تم فرز هذا الطلب بالفعل',p_work_item_id);
  END IF;
  IF p_decision NOT IN ('accept','needs_information','reject') THEN
    RETURN private.work_command_error(p_operation_id,'work_triage_request','INVALID_DECISION','قرار الفرز غير صحيح',p_work_item_id);
  END IF;

  -- Validate the complete requested transition before writing anything.
  IF p_decision='needs_information' THEN
    IF p_note IS NULL OR btrim(p_note)='' OR p_follow_up_at IS NULL THEN
      RETURN private.work_command_error(p_operation_id,'work_triage_request','FOLLOW_UP_REQUIRED','وضح المعلومات المطلوبة وحدد موعد المتابعة',p_work_item_id);
    END IF;
    IF p_follow_up_at <= v_now THEN
      RETURN private.work_command_error(p_operation_id,'work_triage_request','INVALID_FOLLOW_UP','موعد المتابعة يجب أن يكون في المستقبل',p_work_item_id);
    END IF;
    IF NOT private.work_actor_is_active(v_item.requester_user_id) THEN
      RETURN private.work_command_error(p_operation_id,'work_triage_request','REQUESTER_UNAVAILABLE','مقدم الطلب غير نشط',p_work_item_id);
    END IF;
  ELSIF p_decision='reject' THEN
    IF p_note IS NULL OR btrim(p_note)='' THEN
      RETURN private.work_command_error(p_operation_id,'work_triage_request','REJECTION_REASON_REQUIRED','سبب رفض الطلب مطلوب',p_work_item_id);
    END IF;
  ELSE
    IF p_assignee_user_id IS NULL OR p_next_action_text IS NULL OR btrim(p_next_action_text)='' THEN
      RETURN private.work_command_error(p_operation_id,'work_triage_request','ASSIGNMENT_REQUIRED','حدد المسؤول والإجراء التالي لقبول الطلب',p_work_item_id);
    END IF;
    IF NOT private.work_user_can_assign_queue(v_actor,v_request.queue_id) THEN
      RETURN private.work_command_error(p_operation_id,'work_triage_request','QUEUE_ASSIGN_DENIED','لا تملك صلاحية الإسناد داخل جهة الاستقبال',p_work_item_id);
    END IF;
    IF NOT private.work_queue_assignment_target_allowed(v_request.queue_id,p_assignee_user_id) THEN
      RETURN private.work_command_error(p_operation_id,'work_triage_request','INVALID_QUEUE_ASSIGNEE','المستخدم المحدد ليس مسؤولاً نشطًا داخل جهة الاستقبال',p_work_item_id);
    END IF;
    v_owner:=COALESCE(p_owner_user_id,v_queue.manager_user_id);
    IF NOT private.work_actor_is_active(v_owner) THEN
      RETURN private.work_command_error(p_operation_id,'work_triage_request','OWNER_UNAVAILABLE','المالك المسؤول غير نشط',p_work_item_id);
    END IF;
    IF v_owner<>v_queue.manager_user_id AND NOT private.work_queue_assignment_target_allowed(v_request.queue_id,v_owner) THEN
      RETURN private.work_command_error(p_operation_id,'work_triage_request','INVALID_QUEUE_OWNER','المالك المحدد خارج جهة الاستقبال',p_work_item_id);
    END IF;
    IF p_due_at IS NOT NULL AND p_due_at <= v_now THEN
      RETURN private.work_command_error(p_operation_id,'work_triage_request','INVALID_DUE_DATE','موعد الاستحقاق يجب أن يكون في المستقبل',p_work_item_id);
    END IF;
    IF p_follow_up_at IS NOT NULL AND p_follow_up_at <= v_now THEN
      RETURN private.work_command_error(p_operation_id,'work_triage_request','INVALID_FOLLOW_UP','موعد المتابعة يجب أن يكون في المستقبل',p_work_item_id);
    END IF;
  END IF;

  v_from:=v_item.status;
  UPDATE public.work_requests
  SET first_responded_at=COALESCE(first_responded_at,v_now)
  WHERE work_item_id=p_work_item_id
  RETURNING * INTO v_request;

  IF p_decision='needs_information' THEN
    UPDATE public.work_requests
    SET information_request_note=p_note
    WHERE work_item_id=p_work_item_id;

    UPDATE public.work_items
    SET status='waiting',waiting_on_type='user',waiting_on_user_id=requester_user_id,
        waiting_on_label='مقدم الطلب',waiting_reason=p_note,waiting_since=v_now,
        next_action_text=left('استكمال المعلومات المطلوبة: '||p_note,500),next_action_at=p_follow_up_at,
        state_version=state_version+1,last_meaningful_activity_at=v_now
    WHERE id=p_work_item_id RETURNING * INTO v_item;

    PERFORM private.work_append_user_event(
      v_item.id,'work.request.information_required',v_actor,p_operation_id,v_from,'waiting'::public.work_item_status,
      jsonb_build_object('note',p_note,'follow_up_at',p_follow_up_at)
    );

  ELSIF p_decision='reject' THEN
    UPDATE public.work_requests
    SET triaged_at=v_now,triaged_by_user_id=v_actor,triage_outcome='rejected',rejection_reason=p_note
    WHERE work_item_id=p_work_item_id;

    UPDATE public.work_items
    SET status='cancelled',cancelled_at=v_now,next_action_text=NULL,next_action_at=NULL,
        waiting_on_type=NULL,waiting_on_user_id=NULL,waiting_on_entity_type=NULL,waiting_on_entity_id=NULL,
        waiting_on_label=NULL,waiting_reason=NULL,waiting_since=NULL,
        state_version=state_version+1,last_meaningful_activity_at=v_now
    WHERE id=p_work_item_id RETURNING * INTO v_item;

    PERFORM private.work_append_user_event(
      v_item.id,'work.request.rejected',v_actor,p_operation_id,v_from,'cancelled'::public.work_item_status,
      jsonb_build_object('reason',p_note)
    );

  ELSE
    UPDATE public.work_requests
    SET triaged_at=v_now,triaged_by_user_id=v_actor,triage_outcome='accepted',information_request_note=NULL
    WHERE work_item_id=p_work_item_id;

    UPDATE public.work_items
    SET status='open',accountable_owner_user_id=v_owner,current_assignee_user_id=p_assignee_user_id,
        assigned_at=v_now,due_at=COALESCE(p_due_at,due_at),first_due_at=COALESCE(first_due_at,p_due_at,due_at),
        next_action_text=p_next_action_text,next_action_at=p_follow_up_at,
        waiting_on_type=NULL,waiting_on_user_id=NULL,waiting_on_entity_type=NULL,waiting_on_entity_id=NULL,
        waiting_on_label=NULL,waiting_reason=NULL,waiting_since=NULL,
        state_version=state_version+1,last_meaningful_activity_at=v_now
    WHERE id=p_work_item_id RETURNING * INTO v_item;

    PERFORM private.work_append_user_event(
      v_item.id,'work.request.accepted',v_actor,p_operation_id,v_from,'open'::public.work_item_status,
      jsonb_build_object('assignee_user_id',p_assignee_user_id,'owner_user_id',v_owner,'due_at',v_item.due_at)
    );
  END IF;

  v_result:=jsonb_build_object(
    'work_item_id',v_item.id,'status',v_item.status,'state_version',v_item.state_version,
    'decision',p_decision,'first_responded_at',v_request.first_responded_at,
    'triaged_at',(SELECT triaged_at FROM public.work_requests WHERE work_item_id=p_work_item_id)
  );
  RETURN private.work_command_success(p_operation_id,'work_triage_request',v_item.id,v_result);
END;
$$;

RESET lock_timeout;
RESET statement_timeout;
