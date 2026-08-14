-- Work Management — completion, owner review, cancellation and reopening.
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE TYPE public.work_completion_review_status AS ENUM ('pending','approved','changes_required','cancelled');

CREATE TABLE public.work_completion_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_item_id UUID NOT NULL REFERENCES public.work_items(id) ON DELETE CASCADE,
  requested_by_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  reviewer_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  status public.work_completion_review_status NOT NULL DEFAULT 'pending',
  completion_summary TEXT NOT NULL,
  completion_output JSONB NOT NULL DEFAULT '{}'::JSONB,
  reviewer_note TEXT,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_at TIMESTAMPTZ,
  decided_by_user_id UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  CONSTRAINT work_completion_reviews_output_object CHECK (jsonb_typeof(completion_output)='object')
);
CREATE UNIQUE INDEX work_completion_reviews_one_pending
  ON public.work_completion_reviews(work_item_id) WHERE status='pending';
CREATE INDEX idx_work_completion_reviews_reviewer_status
  ON public.work_completion_reviews(reviewer_user_id,status,requested_at);
ALTER TABLE public.work_completion_reviews ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.work_completion_reviews FROM anon,authenticated;
GRANT SELECT ON TABLE public.work_completion_reviews TO service_role;

CREATE POLICY work_completion_reviews_read
ON public.work_completion_reviews FOR SELECT TO authenticated
USING (private.work_current_user_can_view_item(work_item_id));
GRANT SELECT ON TABLE public.work_completion_reviews TO authenticated;

CREATE OR REPLACE FUNCTION public.work_complete(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT,
  p_completion_summary TEXT,
  p_completion_output JSONB DEFAULT '{}'::JSONB
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid(); v_prepare JSONB; v_item public.work_items%ROWTYPE;
  v_blockers JSONB; v_review public.work_completion_reviews%ROWTYPE; v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(p_operation_id,v_actor,'work_complete',jsonb_build_object('work_item_id',p_work_item_id,'expected_version',p_expected_version,'completion_summary',p_completion_summary,'completion_output',COALESCE(p_completion_output,'{}'::JSONB)),p_work_item_id);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_complete','NOT_FOUND','المهمة غير موجودة',p_work_item_id); END IF;
  IF v_item.state_version<>p_expected_version THEN RETURN private.work_command_error(p_operation_id,'work_complete','VERSION_CONFLICT','تم تعديل المهمة بواسطة مستخدم آخر',p_work_item_id); END IF;
  IF NOT private.work_actor_can_update_item(v_actor,p_work_item_id) THEN RETURN private.work_command_error(p_operation_id,'work_complete','FORBIDDEN','غير مصرح بإنهاء المهمة',p_work_item_id); END IF;
  IF v_item.status NOT IN ('open'::public.work_item_status,'in_progress'::public.work_item_status,'waiting'::public.work_item_status) THEN RETURN private.work_command_error(p_operation_id,'work_complete','INVALID_STATE','لا يمكن إنهاء المهمة من حالتها الحالية',p_work_item_id); END IF;
  IF p_completion_summary IS NULL OR btrim(p_completion_summary)='' THEN RETURN private.work_command_error(p_operation_id,'work_complete','COMPLETION_SUMMARY_REQUIRED','ملخص نتيجة التنفيذ مطلوب',p_work_item_id); END IF;
  IF jsonb_typeof(COALESCE(p_completion_output,'{}'::JSONB))<>'object' THEN RETURN private.work_command_error(p_operation_id,'work_complete','INVALID_OUTPUT','ناتج التنفيذ يجب أن يكون كائن بيانات',p_work_item_id); END IF;

  v_blockers:=private.work_completion_blockers(p_work_item_id);
  IF COALESCE((v_blockers->>'required_checklist_open')::BOOLEAN,false) THEN RETURN private.work_command_error(p_operation_id,'work_complete','CHECKLIST_INCOMPLETE','توجد بنود إلزامية غير مكتملة',p_work_item_id); END IF;
  IF COALESCE((v_blockers->>'required_child_open')::BOOLEAN,false) THEN RETURN private.work_command_error(p_operation_id,'work_complete','CHILD_WORK_OPEN','توجد مهام فرعية مطلوبة لم تُغلق',p_work_item_id); END IF;
  IF COALESCE((v_blockers->>'hard_dependency_open')::BOOLEAN,false) THEN RETURN private.work_command_error(p_operation_id,'work_complete','DEPENDENCY_OPEN','توجد اعتمادات إلزامية لم تكتمل',p_work_item_id); END IF;

  IF v_item.completion_mode='approval'::public.work_completion_mode THEN
    IF v_item.completion_approval_template_id IS NULL THEN
      RETURN private.work_command_error(p_operation_id,'work_complete','APPROVAL_TEMPLATE_REQUIRED','المهمة تتطلب اعتماد إتمام ولم يتم ربط نموذج اعتماد',p_work_item_id);
    END IF;
    -- Approval runtime migration replaces this guard with an approval request creation path.
    RETURN private.work_command_error(p_operation_id,'work_complete','APPROVAL_RUNTIME_NOT_READY','مسار اعتماد الإتمام غير متاح قبل تطبيق طبقة الاعتمادات',p_work_item_id);
  END IF;

  IF v_item.completion_mode='owner_review'::public.work_completion_mode
     AND v_item.accountable_owner_user_id IS DISTINCT FROM v_actor THEN
    IF v_item.accountable_owner_user_id IS NULL OR NOT private.work_actor_is_active(v_item.accountable_owner_user_id) THEN
      RETURN private.work_command_error(p_operation_id,'work_complete','OWNER_REVIEWER_UNAVAILABLE','لا يوجد مالك مسؤول نشط لمراجعة الإتمام',p_work_item_id);
    END IF;

    INSERT INTO public.work_completion_reviews(work_item_id,requested_by_user_id,reviewer_user_id,completion_summary,completion_output)
    VALUES(p_work_item_id,v_actor,v_item.accountable_owner_user_id,p_completion_summary,COALESCE(p_completion_output,'{}'::JSONB))
    RETURNING * INTO v_review;

    UPDATE public.work_items
    SET status='pending_approval'::public.work_item_status,
        completion_summary=p_completion_summary,
        completion_output=COALESCE(p_completion_output,'{}'::JSONB),
        completed_by_user_id=v_actor,
        next_action_text='مراجعة نتيجة التنفيذ',
        next_action_at=NULL,
        state_version=state_version+1,
        last_meaningful_activity_at=clock_timestamp()
    WHERE id=p_work_item_id RETURNING * INTO v_item;

    PERFORM private.work_append_user_event(v_item.id,'work.completion_review_requested',v_actor,p_operation_id,NULL,'pending_approval'::public.work_item_status,jsonb_build_object('review_id',v_review.id,'reviewer_user_id',v_review.reviewer_user_id));
    v_result:=jsonb_build_object('work_item_id',v_item.id,'status',v_item.status,'state_version',v_item.state_version,'review_id',v_review.id);
    RETURN private.work_command_success(p_operation_id,'work_complete',v_item.id,v_result);
  END IF;

  UPDATE public.work_items
  SET status='done'::public.work_item_status,
      completion_summary=p_completion_summary,
      completion_output=COALESCE(p_completion_output,'{}'::JSONB),
      completed_by_user_id=v_actor,
      completed_at=clock_timestamp(),
      next_action_text=NULL,next_action_at=NULL,
      waiting_on_type=NULL,waiting_on_user_id=NULL,waiting_on_entity_type=NULL,
      waiting_on_entity_id=NULL,waiting_on_label=NULL,waiting_reason=NULL,waiting_since=NULL,
      state_version=state_version+1,last_meaningful_activity_at=clock_timestamp()
  WHERE id=p_work_item_id RETURNING * INTO v_item;

  PERFORM private.work_append_user_event(v_item.id,'work.completed',v_actor,p_operation_id,NULL,'done'::public.work_item_status,jsonb_build_object('completion_summary',p_completion_summary));
  v_result:=jsonb_build_object('work_item_id',v_item.id,'status',v_item.status,'state_version',v_item.state_version,'completed_at',v_item.completed_at);
  RETURN private.work_command_success(p_operation_id,'work_complete',v_item.id,v_result);
END; $$;

CREATE OR REPLACE FUNCTION public.work_review_completion(
  p_operation_id UUID,
  p_review_id UUID,
  p_expected_version BIGINT,
  p_decision TEXT,
  p_note TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid(); v_review public.work_completion_reviews%ROWTYPE;
  v_item public.work_items%ROWTYPE; v_prepare JSONB; v_result JSONB;
BEGIN
  SELECT * INTO v_review FROM public.work_completion_reviews WHERE id=p_review_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'operation_id',p_operation_id,'operation','work_review_completion','replayed',false,'error',jsonb_build_object('code','NOT_FOUND','message','طلب المراجعة غير موجود')); END IF;
  v_prepare:=private.work_prepare_operation(p_operation_id,v_actor,'work_review_completion',jsonb_build_object('review_id',p_review_id,'expected_version',p_expected_version,'decision',p_decision,'note',p_note),v_review.work_item_id);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id=v_review.work_item_id FOR UPDATE;
  SELECT * INTO v_review FROM public.work_completion_reviews WHERE id=p_review_id FOR UPDATE;
  IF v_item.state_version<>p_expected_version THEN RETURN private.work_command_error(p_operation_id,'work_review_completion','VERSION_CONFLICT','تم تعديل المهمة بواسطة مستخدم آخر',v_item.id); END IF;
  IF v_review.status<>'pending'::public.work_completion_review_status THEN RETURN private.work_command_error(p_operation_id,'work_review_completion','ALREADY_DECIDED','تم اتخاذ قرار في هذه المراجعة بالفعل',v_item.id); END IF;
  IF v_review.reviewer_user_id<>v_actor AND NOT private.work_user_can_manage_item(v_actor,v_item.id) THEN RETURN private.work_command_error(p_operation_id,'work_review_completion','FORBIDDEN','غير مصرح باتخاذ قرار المراجعة',v_item.id); END IF;
  IF p_decision NOT IN ('approve','changes_required') THEN RETURN private.work_command_error(p_operation_id,'work_review_completion','INVALID_DECISION','قرار المراجعة غير صحيح',v_item.id); END IF;

  IF p_decision='approve' THEN
    UPDATE public.work_completion_reviews SET status='approved',reviewer_note=p_note,decided_at=clock_timestamp(),decided_by_user_id=v_actor WHERE id=p_review_id;
    UPDATE public.work_items
    SET status='done',completed_at=clock_timestamp(),next_action_text=NULL,next_action_at=NULL,
        state_version=state_version+1,last_meaningful_activity_at=clock_timestamp()
    WHERE id=v_item.id RETURNING * INTO v_item;
    PERFORM private.work_append_user_event(v_item.id,'work.completion_approved',v_actor,p_operation_id,'pending_approval'::public.work_item_status,'done'::public.work_item_status,jsonb_build_object('review_id',p_review_id,'note',p_note));
  ELSE
    IF p_note IS NULL OR btrim(p_note)='' THEN RETURN private.work_command_error(p_operation_id,'work_review_completion','NOTE_REQUIRED','وضح التعديلات المطلوبة',v_item.id); END IF;
    UPDATE public.work_completion_reviews SET status='changes_required',reviewer_note=p_note,decided_at=clock_timestamp(),decided_by_user_id=v_actor WHERE id=p_review_id;
    UPDATE public.work_items
    SET status='in_progress',completion_summary=NULL,completion_output='{}'::JSONB,completed_by_user_id=NULL,
        next_action_text=left('تنفيذ تعديلات المراجعة: '||p_note,500),next_action_at=NULL,
        state_version=state_version+1,last_meaningful_activity_at=clock_timestamp()
    WHERE id=v_item.id RETURNING * INTO v_item;
    PERFORM private.work_append_user_event(v_item.id,'work.completion_changes_required',v_actor,p_operation_id,'pending_approval'::public.work_item_status,'in_progress'::public.work_item_status,jsonb_build_object('review_id',p_review_id,'note',p_note));
  END IF;

  v_result:=jsonb_build_object('work_item_id',v_item.id,'status',v_item.status,'state_version',v_item.state_version,'review_id',p_review_id,'decision',p_decision);
  RETURN private.work_command_success(p_operation_id,'work_review_completion',v_item.id,v_result);
END; $$;

CREATE OR REPLACE FUNCTION public.work_cancel(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT,
  p_reason TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid(); v_prepare JSONB; v_item public.work_items%ROWTYPE; v_from public.work_item_status; v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(p_operation_id,v_actor,'work_cancel',jsonb_build_object('work_item_id',p_work_item_id,'expected_version',p_expected_version,'reason',p_reason),p_work_item_id);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_cancel','NOT_FOUND','المهمة غير موجودة',p_work_item_id); END IF;
  IF v_item.state_version<>p_expected_version THEN RETURN private.work_command_error(p_operation_id,'work_cancel','VERSION_CONFLICT','تم تعديل المهمة بواسطة مستخدم آخر',p_work_item_id); END IF;
  IF NOT private.work_user_can_manage_item(v_actor,p_work_item_id) AND v_item.accountable_owner_user_id<>v_actor THEN RETURN private.work_command_error(p_operation_id,'work_cancel','FORBIDDEN','غير مصرح بإلغاء المهمة',p_work_item_id); END IF;
  IF v_item.status IN ('done'::public.work_item_status,'cancelled'::public.work_item_status) THEN RETURN private.work_command_error(p_operation_id,'work_cancel','INVALID_STATE','المهمة منتهية بالفعل',p_work_item_id); END IF;
  IF p_reason IS NULL OR btrim(p_reason)='' THEN RETURN private.work_command_error(p_operation_id,'work_cancel','REASON_REQUIRED','سبب الإلغاء مطلوب',p_work_item_id); END IF;
  v_from:=v_item.status;
  UPDATE public.work_items
  SET status='cancelled',cancelled_at=clock_timestamp(),next_action_text=NULL,next_action_at=NULL,
      state_version=state_version+1,last_meaningful_activity_at=clock_timestamp()
  WHERE id=p_work_item_id RETURNING * INTO v_item;
  UPDATE public.work_completion_reviews SET status='cancelled',decided_at=clock_timestamp(),decided_by_user_id=v_actor,reviewer_note=COALESCE(reviewer_note,p_reason) WHERE work_item_id=p_work_item_id AND status='pending';
  PERFORM private.work_append_user_event(v_item.id,'work.cancelled',v_actor,p_operation_id,v_from,'cancelled'::public.work_item_status,jsonb_build_object('reason',p_reason));
  v_result:=jsonb_build_object('work_item_id',v_item.id,'status',v_item.status,'state_version',v_item.state_version);
  RETURN private.work_command_success(p_operation_id,'work_cancel',v_item.id,v_result);
END; $$;

CREATE OR REPLACE FUNCTION public.work_reopen(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT,
  p_reason TEXT,
  p_next_action_text VARCHAR(500),
  p_next_action_at TIMESTAMPTZ DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid(); v_prepare JSONB; v_item public.work_items%ROWTYPE; v_from public.work_item_status; v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(p_operation_id,v_actor,'work_reopen',jsonb_build_object('work_item_id',p_work_item_id,'expected_version',p_expected_version,'reason',p_reason,'next_action_text',p_next_action_text,'next_action_at',p_next_action_at),p_work_item_id);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_reopen','NOT_FOUND','المهمة غير موجودة',p_work_item_id); END IF;
  IF v_item.state_version<>p_expected_version THEN RETURN private.work_command_error(p_operation_id,'work_reopen','VERSION_CONFLICT','تم تعديل المهمة بواسطة مستخدم آخر',p_work_item_id); END IF;
  IF NOT private.work_user_can_manage_item(v_actor,p_work_item_id) AND v_item.accountable_owner_user_id<>v_actor THEN RETURN private.work_command_error(p_operation_id,'work_reopen','FORBIDDEN','غير مصرح بإعادة فتح المهمة',p_work_item_id); END IF;
  IF v_item.status NOT IN ('done'::public.work_item_status,'cancelled'::public.work_item_status) THEN RETURN private.work_command_error(p_operation_id,'work_reopen','INVALID_STATE','إعادة الفتح متاحة للمهمات المنتهية فقط',p_work_item_id); END IF;
  IF p_reason IS NULL OR btrim(p_reason)='' OR p_next_action_text IS NULL OR btrim(p_next_action_text)='' THEN RETURN private.work_command_error(p_operation_id,'work_reopen','DETAILS_REQUIRED','سبب إعادة الفتح والإجراء التالي مطلوبان',p_work_item_id); END IF;
  v_from:=v_item.status;
  UPDATE public.work_items
  SET status='open',completed_at=NULL,cancelled_at=NULL,reopened_at=clock_timestamp(),
      completion_summary=NULL,completion_output='{}'::JSONB,completed_by_user_id=NULL,
      next_action_text=p_next_action_text,next_action_at=p_next_action_at,
      state_version=state_version+1,last_meaningful_activity_at=clock_timestamp()
  WHERE id=p_work_item_id RETURNING * INTO v_item;
  PERFORM private.work_append_user_event(v_item.id,'work.reopened',v_actor,p_operation_id,v_from,'open'::public.work_item_status,jsonb_build_object('reason',p_reason,'next_action_text',p_next_action_text,'next_action_at',p_next_action_at));
  v_result:=jsonb_build_object('work_item_id',v_item.id,'status',v_item.status,'state_version',v_item.state_version);
  RETURN private.work_command_success(p_operation_id,'work_reopen',v_item.id,v_result);
END; $$;

REVOKE ALL ON FUNCTION public.work_complete(UUID,UUID,BIGINT,TEXT,JSONB) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_review_completion(UUID,UUID,BIGINT,TEXT,TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_cancel(UUID,UUID,BIGINT,TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_reopen(UUID,UUID,BIGINT,TEXT,VARCHAR,TIMESTAMPTZ) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.work_complete(UUID,UUID,BIGINT,TEXT,JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_review_completion(UUID,UUID,BIGINT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_cancel(UUID,UUID,BIGINT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_reopen(UUID,UUID,BIGINT,TEXT,VARCHAR,TIMESTAMPTZ) TO authenticated;

RESET lock_timeout;
RESET statement_timeout;
