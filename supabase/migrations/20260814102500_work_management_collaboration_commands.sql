-- Work Management — checklist, discussion, participants, attachments and dependencies.
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION public.work_add_checklist_item(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT,
  p_label TEXT,
  p_is_required BOOLEAN DEFAULT false,
  p_sort_order INTEGER DEFAULT 0
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid(); v_prepare JSONB; v_item public.work_items%ROWTYPE;
  v_check public.work_checklist_items%ROWTYPE; v_result JSONB;
BEGIN
  v_prepare := private.work_prepare_operation(p_operation_id, v_actor, 'work_add_checklist_item', jsonb_build_object('work_item_id',p_work_item_id,'expected_version',p_expected_version,'label',p_label,'is_required',p_is_required,'sort_order',p_sort_order), p_work_item_id);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_add_checklist_item','NOT_FOUND','المهمة غير موجودة',p_work_item_id); END IF;
  IF v_item.state_version<>p_expected_version THEN RETURN private.work_command_error(p_operation_id,'work_add_checklist_item','VERSION_CONFLICT','تم تعديل المهمة بواسطة مستخدم آخر',p_work_item_id); END IF;
  IF NOT private.work_actor_can_update_item(v_actor,p_work_item_id) THEN RETURN private.work_command_error(p_operation_id,'work_add_checklist_item','FORBIDDEN','غير مصرح بتعديل قائمة التحقق',p_work_item_id); END IF;
  IF v_item.status IN ('done'::public.work_item_status,'cancelled'::public.work_item_status) THEN RETURN private.work_command_error(p_operation_id,'work_add_checklist_item','INVALID_STATE','المهمة منتهية',p_work_item_id); END IF;
  IF p_label IS NULL OR btrim(p_label)='' THEN RETURN private.work_command_error(p_operation_id,'work_add_checklist_item','VALIDATION_ERROR','بند قائمة التحقق مطلوب',p_work_item_id); END IF;

  INSERT INTO public.work_checklist_items(work_item_id,label,is_required,sort_order,created_by_user_id)
  VALUES(p_work_item_id,p_label,p_is_required,GREATEST(COALESCE(p_sort_order,0),0),v_actor)
  RETURNING * INTO v_check;
  UPDATE public.work_items SET state_version=state_version+1,last_meaningful_activity_at=clock_timestamp() WHERE id=p_work_item_id RETURNING * INTO v_item;
  PERFORM private.work_append_user_event(p_work_item_id,'work.checklist_item_added',v_actor,p_operation_id,v_item.status,v_item.status,jsonb_build_object('checklist_item_id',v_check.id,'label',v_check.label,'is_required',v_check.is_required));
  v_result:=jsonb_build_object('work_item_id',p_work_item_id,'checklist_item_id',v_check.id,'status',v_item.status,'state_version',v_item.state_version);
  RETURN private.work_command_success(p_operation_id,'work_add_checklist_item',p_work_item_id,v_result);
END; $$;

CREATE OR REPLACE FUNCTION public.work_set_checklist_completion(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_checklist_item_id UUID,
  p_expected_version BIGINT,
  p_completed BOOLEAN
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_actor UUID:=auth.uid(); v_prepare JSONB; v_item public.work_items%ROWTYPE;
  v_check public.work_checklist_items%ROWTYPE; v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(p_operation_id,v_actor,'work_set_checklist_completion',jsonb_build_object('work_item_id',p_work_item_id,'checklist_item_id',p_checklist_item_id,'expected_version',p_expected_version,'completed',p_completed),p_work_item_id);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_set_checklist_completion','NOT_FOUND','المهمة غير موجودة',p_work_item_id); END IF;
  IF v_item.state_version<>p_expected_version THEN RETURN private.work_command_error(p_operation_id,'work_set_checklist_completion','VERSION_CONFLICT','تم تعديل المهمة بواسطة مستخدم آخر',p_work_item_id); END IF;
  IF NOT private.work_actor_can_update_item(v_actor,p_work_item_id) THEN RETURN private.work_command_error(p_operation_id,'work_set_checklist_completion','FORBIDDEN','غير مصرح بتعديل قائمة التحقق',p_work_item_id); END IF;
  SELECT * INTO v_check FROM public.work_checklist_items WHERE id=p_checklist_item_id AND work_item_id=p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_set_checklist_completion','CHECKLIST_NOT_FOUND','بند قائمة التحقق غير موجود',p_work_item_id); END IF;

  UPDATE public.work_checklist_items
  SET completed_at=CASE WHEN p_completed THEN COALESCE(completed_at,clock_timestamp()) ELSE NULL END,
      completed_by_user_id=CASE WHEN p_completed THEN v_actor ELSE NULL END
  WHERE id=p_checklist_item_id RETURNING * INTO v_check;
  UPDATE public.work_items SET state_version=state_version+1,last_meaningful_activity_at=clock_timestamp() WHERE id=p_work_item_id RETURNING * INTO v_item;
  PERFORM private.work_append_user_event(p_work_item_id,CASE WHEN p_completed THEN 'work.checklist_item_completed' ELSE 'work.checklist_item_reopened' END,v_actor,p_operation_id,v_item.status,v_item.status,jsonb_build_object('checklist_item_id',p_checklist_item_id));
  v_result:=jsonb_build_object('work_item_id',p_work_item_id,'checklist_item_id',p_checklist_item_id,'completed',p_completed,'status',v_item.status,'state_version',v_item.state_version);
  RETURN private.work_command_success(p_operation_id,'work_set_checklist_completion',p_work_item_id,v_result);
END; $$;

CREATE OR REPLACE FUNCTION public.work_add_comment(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_body TEXT,
  p_comment_kind public.work_comment_kind DEFAULT 'comment',
  p_mentioned_user_ids UUID[] DEFAULT ARRAY[]::UUID[]
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_actor UUID:=auth.uid(); v_prepare JSONB; v_item public.work_items%ROWTYPE;
  v_comment public.work_comments%ROWTYPE; v_mentioned UUID; v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(p_operation_id,v_actor,'work_add_comment',jsonb_build_object('work_item_id',p_work_item_id,'body',p_body,'comment_kind',p_comment_kind,'mentions',COALESCE(p_mentioned_user_ids,ARRAY[]::UUID[])),p_work_item_id);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_add_comment','NOT_FOUND','المهمة غير موجودة',p_work_item_id); END IF;
  IF NOT private.work_actor_can_comment_item(v_actor,p_work_item_id) THEN RETURN private.work_command_error(p_operation_id,'work_add_comment','FORBIDDEN','غير مصرح بالتعليق على المهمة',p_work_item_id); END IF;
  IF p_body IS NULL OR btrim(p_body)='' THEN RETURN private.work_command_error(p_operation_id,'work_add_comment','VALIDATION_ERROR','نص التعليق مطلوب',p_work_item_id); END IF;

  FOREACH v_mentioned IN ARRAY COALESCE(p_mentioned_user_ids,ARRAY[]::UUID[]) LOOP
    IF NOT private.work_actor_is_active(v_mentioned) THEN
      RETURN private.work_command_error(p_operation_id,'work_add_comment','INVALID_MENTION','لا يمكن الإشارة إلى مستخدم غير نشط',p_work_item_id);
    END IF;
    IF NOT private.work_user_can_view_row(v_mentioned,v_item.id,v_item.visibility,v_item.creator_user_id,v_item.requester_user_id,v_item.accountable_owner_user_id,v_item.current_assignee_user_id,v_item.branch_id,v_item.owning_department_id) THEN
      RETURN private.work_command_error(p_operation_id,'work_add_comment','MENTION_VISIBILITY_DENIED','لا يمكن الإشارة إلى مستخدم لا يملك حق رؤية المهمة',p_work_item_id);
    END IF;
  END LOOP;

  INSERT INTO public.work_comments(work_item_id,author_user_id,comment_kind,body)
  VALUES(p_work_item_id,v_actor,p_comment_kind,p_body) RETURNING * INTO v_comment;
  INSERT INTO public.work_mentions(work_item_id,comment_id,mentioned_user_id,created_by_user_id)
  SELECT p_work_item_id,v_comment.id,x,v_actor FROM unnest(COALESCE(p_mentioned_user_ids,ARRAY[]::UUID[])) x
  ON CONFLICT(comment_id,mentioned_user_id) DO NOTHING;

  UPDATE public.work_items SET state_version=state_version+1,last_meaningful_activity_at=clock_timestamp() WHERE id=p_work_item_id RETURNING * INTO v_item;
  PERFORM private.work_append_user_event(p_work_item_id,CASE WHEN p_comment_kind='progress_update'::public.work_comment_kind THEN 'work.progress_updated' ELSE 'work.comment_added' END,v_actor,p_operation_id,v_item.status,v_item.status,jsonb_build_object('comment_id',v_comment.id,'comment_kind',p_comment_kind,'mentioned_user_ids',COALESCE(p_mentioned_user_ids,ARRAY[]::UUID[])));
  v_result:=jsonb_build_object('work_item_id',p_work_item_id,'comment_id',v_comment.id,'status',v_item.status,'state_version',v_item.state_version);
  RETURN private.work_command_success(p_operation_id,'work_add_comment',p_work_item_id,v_result);
END; $$;

CREATE OR REPLACE FUNCTION public.work_set_participant(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT,
  p_user_id UUID,
  p_role public.work_participant_role DEFAULT 'follower',
  p_can_comment BOOLEAN DEFAULT true,
  p_active BOOLEAN DEFAULT true
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_actor UUID:=auth.uid(); v_prepare JSONB; v_item public.work_items%ROWTYPE; v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(p_operation_id,v_actor,'work_set_participant',jsonb_build_object('work_item_id',p_work_item_id,'expected_version',p_expected_version,'user_id',p_user_id,'role',p_role,'can_comment',p_can_comment,'active',p_active),p_work_item_id);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_set_participant','NOT_FOUND','المهمة غير موجودة',p_work_item_id); END IF;
  IF v_item.state_version<>p_expected_version THEN RETURN private.work_command_error(p_operation_id,'work_set_participant','VERSION_CONFLICT','تم تعديل المهمة بواسطة مستخدم آخر',p_work_item_id); END IF;
  IF NOT private.work_actor_can_update_item(v_actor,p_work_item_id) THEN RETURN private.work_command_error(p_operation_id,'work_set_participant','FORBIDDEN','غير مصرح بإدارة المشاركين',p_work_item_id); END IF;
  IF p_active AND NOT private.work_actor_is_active(p_user_id) THEN RETURN private.work_command_error(p_operation_id,'work_set_participant','INVALID_PARTICIPANT','المستخدم غير نشط',p_work_item_id); END IF;

  IF p_active THEN
    UPDATE public.work_participants SET removed_at=clock_timestamp(),removed_by_user_id=v_actor
    WHERE work_item_id=p_work_item_id AND user_id=p_user_id AND removed_at IS NULL;
    INSERT INTO public.work_participants(work_item_id,user_id,participant_role,can_comment,added_by_user_id)
    VALUES(p_work_item_id,p_user_id,p_role,p_can_comment,v_actor);
  ELSE
    UPDATE public.work_participants SET removed_at=clock_timestamp(),removed_by_user_id=v_actor
    WHERE work_item_id=p_work_item_id AND user_id=p_user_id AND removed_at IS NULL;
  END IF;

  UPDATE public.work_items SET state_version=state_version+1,last_meaningful_activity_at=clock_timestamp() WHERE id=p_work_item_id RETURNING * INTO v_item;
  PERFORM private.work_append_user_event(p_work_item_id,CASE WHEN p_active THEN 'work.participant_added' ELSE 'work.participant_removed' END,v_actor,p_operation_id,v_item.status,v_item.status,jsonb_build_object('user_id',p_user_id,'role',p_role,'can_comment',p_can_comment));
  v_result:=jsonb_build_object('work_item_id',p_work_item_id,'status',v_item.status,'state_version',v_item.state_version);
  RETURN private.work_command_success(p_operation_id,'work_set_participant',p_work_item_id,v_result);
END; $$;

CREATE OR REPLACE FUNCTION public.work_add_attachment_metadata(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT,
  p_storage_path TEXT,
  p_original_filename TEXT,
  p_mime_type TEXT,
  p_size_bytes BIGINT,
  p_purpose public.work_attachment_purpose DEFAULT 'reference',
  p_comment_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_actor UUID:=auth.uid(); v_prepare JSONB; v_item public.work_items%ROWTYPE;
  v_attachment public.work_attachments%ROWTYPE; v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(p_operation_id,v_actor,'work_add_attachment_metadata',jsonb_build_object('work_item_id',p_work_item_id,'expected_version',p_expected_version,'storage_path',p_storage_path,'filename',p_original_filename,'mime_type',p_mime_type,'size_bytes',p_size_bytes,'purpose',p_purpose,'comment_id',p_comment_id),p_work_item_id);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_add_attachment_metadata','NOT_FOUND','المهمة غير موجودة',p_work_item_id); END IF;
  IF v_item.state_version<>p_expected_version THEN RETURN private.work_command_error(p_operation_id,'work_add_attachment_metadata','VERSION_CONFLICT','تم تعديل المهمة بواسطة مستخدم آخر',p_work_item_id); END IF;
  IF NOT private.work_actor_can_update_item(v_actor,p_work_item_id) AND NOT private.work_actor_can_comment_item(v_actor,p_work_item_id) THEN RETURN private.work_command_error(p_operation_id,'work_add_attachment_metadata','FORBIDDEN','غير مصرح بإضافة مرفقات',p_work_item_id); END IF;
  IF p_storage_path IS NULL OR p_storage_path NOT LIKE ('work/'||p_work_item_id::TEXT||'/%') THEN RETURN private.work_command_error(p_operation_id,'work_add_attachment_metadata','INVALID_STORAGE_PATH','مسار الملف غير مرتبط بالمهمة',p_work_item_id); END IF;
  IF p_comment_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.work_comments c WHERE c.id=p_comment_id AND c.work_item_id=p_work_item_id) THEN RETURN private.work_command_error(p_operation_id,'work_add_attachment_metadata','COMMENT_NOT_FOUND','التعليق المرتبط بالمرفق غير موجود',p_work_item_id); END IF;

  INSERT INTO public.work_attachments(work_item_id,comment_id,storage_path,original_filename,mime_type,size_bytes,uploaded_by_user_id,purpose)
  VALUES(p_work_item_id,p_comment_id,p_storage_path,p_original_filename,p_mime_type,p_size_bytes,v_actor,p_purpose)
  RETURNING * INTO v_attachment;
  UPDATE public.work_items SET state_version=state_version+1,last_meaningful_activity_at=clock_timestamp() WHERE id=p_work_item_id RETURNING * INTO v_item;
  PERFORM private.work_append_user_event(p_work_item_id,'work.attachment_added',v_actor,p_operation_id,v_item.status,v_item.status,jsonb_build_object('attachment_id',v_attachment.id,'purpose',p_purpose,'filename',p_original_filename));
  v_result:=jsonb_build_object('work_item_id',p_work_item_id,'attachment_id',v_attachment.id,'status',v_item.status,'state_version',v_item.state_version);
  RETURN private.work_command_success(p_operation_id,'work_add_attachment_metadata',p_work_item_id,v_result);
END; $$;

CREATE OR REPLACE FUNCTION public.work_add_dependency(
  p_operation_id UUID,
  p_blocked_work_item_id UUID,
  p_blocker_work_item_id UUID,
  p_expected_blocked_version BIGINT,
  p_strength public.work_dependency_strength DEFAULT 'hard'
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_actor UUID:=auth.uid(); v_prepare JSONB; v_blocked public.work_items%ROWTYPE; v_blocker public.work_items%ROWTYPE;
  v_dep public.work_dependencies%ROWTYPE; v_result JSONB; v_cycle BOOLEAN;
BEGIN
  v_prepare:=private.work_prepare_operation(p_operation_id,v_actor,'work_add_dependency',jsonb_build_object('blocked',p_blocked_work_item_id,'blocker',p_blocker_work_item_id,'expected_version',p_expected_blocked_version,'strength',p_strength),p_blocked_work_item_id);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  IF p_blocked_work_item_id=p_blocker_work_item_id THEN RETURN private.work_command_error(p_operation_id,'work_add_dependency','SELF_DEPENDENCY','لا يمكن ربط المهمة بنفسها',p_blocked_work_item_id); END IF;

  -- Deterministic row locking prevents opposing concurrent dependency writes.
  PERFORM 1 FROM public.work_items WHERE id IN (p_blocked_work_item_id,p_blocker_work_item_id) ORDER BY id FOR UPDATE;
  SELECT * INTO v_blocked FROM public.work_items WHERE id=p_blocked_work_item_id;
  SELECT * INTO v_blocker FROM public.work_items WHERE id=p_blocker_work_item_id;
  IF v_blocked.id IS NULL OR v_blocker.id IS NULL THEN RETURN private.work_command_error(p_operation_id,'work_add_dependency','NOT_FOUND','إحدى المهمتين غير موجودة',p_blocked_work_item_id); END IF;
  IF v_blocked.state_version<>p_expected_blocked_version THEN RETURN private.work_command_error(p_operation_id,'work_add_dependency','VERSION_CONFLICT','تم تعديل المهمة بواسطة مستخدم آخر',p_blocked_work_item_id); END IF;
  IF NOT private.work_actor_can_update_item(v_actor,p_blocked_work_item_id) THEN RETURN private.work_command_error(p_operation_id,'work_add_dependency','FORBIDDEN','غير مصرح بإضافة اعتماد لهذه المهمة',p_blocked_work_item_id); END IF;
  IF NOT private.work_user_can_view_row(v_actor,v_blocker.id,v_blocker.visibility,v_blocker.creator_user_id,v_blocker.requester_user_id,v_blocker.accountable_owner_user_id,v_blocker.current_assignee_user_id,v_blocker.branch_id,v_blocker.owning_department_id) THEN RETURN private.work_command_error(p_operation_id,'work_add_dependency','BLOCKER_VISIBILITY_DENIED','غير مصرح بعرض المهمة المعتمد عليها',p_blocked_work_item_id); END IF;

  WITH RECURSIVE reach(id,path) AS (
    SELECT p_blocked_work_item_id, ARRAY[p_blocked_work_item_id]::UUID[]
    UNION ALL
    SELECT d.blocker_work_item_id, r.path||d.blocker_work_item_id
    FROM reach r JOIN public.work_dependencies d ON d.blocked_work_item_id=r.id AND d.resolved_at IS NULL
    WHERE NOT d.blocker_work_item_id=ANY(r.path)
  ) SELECT EXISTS(SELECT 1 FROM reach WHERE id=p_blocker_work_item_id) INTO v_cycle;
  -- Existing path blocked -> blocker is fine. The forbidden cycle is blocker -> blocked.
  WITH RECURSIVE reach2(id,path) AS (
    SELECT p_blocker_work_item_id, ARRAY[p_blocker_work_item_id]::UUID[]
    UNION ALL
    SELECT d.blocker_work_item_id, r.path||d.blocker_work_item_id
    FROM reach2 r JOIN public.work_dependencies d ON d.blocked_work_item_id=r.id AND d.resolved_at IS NULL
    WHERE NOT d.blocker_work_item_id=ANY(r.path)
  ) SELECT EXISTS(SELECT 1 FROM reach2 WHERE id=p_blocked_work_item_id) INTO v_cycle;
  IF v_cycle THEN RETURN private.work_command_error(p_operation_id,'work_add_dependency','DEPENDENCY_CYCLE','إضافة الاعتماد ستنشئ حلقة مغلقة',p_blocked_work_item_id); END IF;

  INSERT INTO public.work_dependencies(blocked_work_item_id,blocker_work_item_id,dependency_strength,created_by_user_id)
  VALUES(p_blocked_work_item_id,p_blocker_work_item_id,p_strength,v_actor)
  RETURNING * INTO v_dep;
  UPDATE public.work_items SET state_version=state_version+1,last_meaningful_activity_at=clock_timestamp() WHERE id=p_blocked_work_item_id RETURNING * INTO v_blocked;
  PERFORM private.work_append_user_event(p_blocked_work_item_id,'work.dependency_added',v_actor,p_operation_id,v_blocked.status,v_blocked.status,jsonb_build_object('dependency_id',v_dep.id,'blocker_work_item_id',p_blocker_work_item_id,'strength',p_strength));
  v_result:=jsonb_build_object('work_item_id',p_blocked_work_item_id,'dependency_id',v_dep.id,'status',v_blocked.status,'state_version',v_blocked.state_version);
  RETURN private.work_command_success(p_operation_id,'work_add_dependency',p_blocked_work_item_id,v_result);
END; $$;

CREATE OR REPLACE FUNCTION public.work_resolve_dependency(
  p_operation_id UUID,
  p_dependency_id UUID,
  p_expected_blocked_version BIGINT,
  p_reason TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_actor UUID:=auth.uid(); v_prepare JSONB; v_dep public.work_dependencies%ROWTYPE;
  v_item public.work_items%ROWTYPE; v_result JSONB;
BEGIN
  SELECT * INTO v_dep FROM public.work_dependencies WHERE id=p_dependency_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'operation_id',p_operation_id,'operation','work_resolve_dependency','replayed',false,'error',jsonb_build_object('code','NOT_FOUND','message','الاعتماد غير موجود')); END IF;
  v_prepare:=private.work_prepare_operation(p_operation_id,v_actor,'work_resolve_dependency',jsonb_build_object('dependency_id',p_dependency_id,'expected_version',p_expected_blocked_version,'reason',p_reason),v_dep.blocked_work_item_id);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  SELECT * INTO v_item FROM public.work_items WHERE id=v_dep.blocked_work_item_id FOR UPDATE;
  IF v_item.state_version<>p_expected_blocked_version THEN RETURN private.work_command_error(p_operation_id,'work_resolve_dependency','VERSION_CONFLICT','تم تعديل المهمة بواسطة مستخدم آخر',v_dep.blocked_work_item_id); END IF;
  IF NOT private.work_actor_can_update_item(v_actor,v_dep.blocked_work_item_id) THEN RETURN private.work_command_error(p_operation_id,'work_resolve_dependency','FORBIDDEN','غير مصرح بحل الاعتماد',v_dep.blocked_work_item_id); END IF;
  UPDATE public.work_dependencies SET resolved_at=COALESCE(resolved_at,clock_timestamp()),resolved_by_user_id=CASE WHEN resolved_at IS NULL THEN v_actor ELSE resolved_by_user_id END,resolution_reason=COALESCE(resolution_reason,p_reason) WHERE id=p_dependency_id RETURNING * INTO v_dep;
  UPDATE public.work_items SET state_version=state_version+1,last_meaningful_activity_at=clock_timestamp() WHERE id=v_dep.blocked_work_item_id RETURNING * INTO v_item;
  PERFORM private.work_append_user_event(v_item.id,'work.dependency_resolved',v_actor,p_operation_id,v_item.status,v_item.status,jsonb_build_object('dependency_id',p_dependency_id,'reason',p_reason));
  v_result:=jsonb_build_object('work_item_id',v_item.id,'dependency_id',p_dependency_id,'status',v_item.status,'state_version',v_item.state_version);
  RETURN private.work_command_success(p_operation_id,'work_resolve_dependency',v_item.id,v_result);
END; $$;

REVOKE ALL ON FUNCTION public.work_add_checklist_item(UUID,UUID,BIGINT,TEXT,BOOLEAN,INTEGER) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_set_checklist_completion(UUID,UUID,UUID,BIGINT,BOOLEAN) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_add_comment(UUID,UUID,TEXT,public.work_comment_kind,UUID[]) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_set_participant(UUID,UUID,BIGINT,UUID,public.work_participant_role,BOOLEAN,BOOLEAN) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_add_attachment_metadata(UUID,UUID,BIGINT,TEXT,TEXT,TEXT,BIGINT,public.work_attachment_purpose,UUID) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_add_dependency(UUID,UUID,UUID,BIGINT,public.work_dependency_strength) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_resolve_dependency(UUID,UUID,BIGINT,TEXT) FROM PUBLIC,anon;

GRANT EXECUTE ON FUNCTION public.work_add_checklist_item(UUID,UUID,BIGINT,TEXT,BOOLEAN,INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_set_checklist_completion(UUID,UUID,UUID,BIGINT,BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_add_comment(UUID,UUID,TEXT,public.work_comment_kind,UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_set_participant(UUID,UUID,BIGINT,UUID,public.work_participant_role,BOOLEAN,BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_add_attachment_metadata(UUID,UUID,BIGINT,TEXT,TEXT,TEXT,BIGINT,public.work_attachment_purpose,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_add_dependency(UUID,UUID,UUID,BIGINT,public.work_dependency_strength) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_resolve_dependency(UUID,UUID,BIGINT,TEXT) TO authenticated;

RESET lock_timeout;
RESET statement_timeout;
