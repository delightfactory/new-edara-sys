-- Work Management — public atomic Task lifecycle RPCs.
SET lock_timeout = '5s';
SET statement_timeout = '60s';

-- --------------------------------------------------------------------------
-- Create Task: creates a draft and, by default, activates it atomically.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.work_create_task(
  p_operation_id UUID,
  p_title TEXT,
  p_description TEXT DEFAULT NULL,
  p_expected_outcome TEXT DEFAULT NULL,
  p_priority public.work_priority DEFAULT 'normal',
  p_visibility public.work_visibility DEFAULT 'standard',
  p_owner_user_id UUID DEFAULT NULL,
  p_assignee_user_id UUID DEFAULT NULL,
  p_due_at TIMESTAMPTZ DEFAULT NULL,
  p_next_action_text VARCHAR(500) DEFAULT NULL,
  p_next_action_at TIMESTAMPTZ DEFAULT NULL,
  p_acknowledgement_required BOOLEAN DEFAULT false,
  p_completion_mode public.work_completion_mode DEFAULT 'assignee_closes',
  p_activate BOOLEAN DEFAULT true
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_owner UUID := COALESCE(p_owner_user_id, auth.uid());
  v_assignee UUID := COALESCE(p_assignee_user_id, auth.uid());
  v_prepare JSONB;
  v_result JSONB;
  v_item public.work_items%ROWTYPE;
BEGIN
  v_prepare := private.work_prepare_operation(
    p_operation_id, v_actor, 'work_create_task',
    jsonb_build_object(
      'title', p_title, 'description', p_description,
      'expected_outcome', p_expected_outcome, 'priority', p_priority,
      'visibility', p_visibility, 'owner', v_owner, 'assignee', v_assignee,
      'due_at', p_due_at, 'next_action_text', p_next_action_text,
      'next_action_at', p_next_action_at,
      'acknowledgement_required', p_acknowledgement_required,
      'completion_mode', p_completion_mode, 'activate', p_activate
    ), NULL
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN, false) THEN
    RETURN v_prepare->'response';
  END IF;

  IF NOT COALESCE(public.check_permission(v_actor, 'work.items.create'), false) THEN
    RETURN private.work_command_error(p_operation_id, 'work_create_task', 'FORBIDDEN', 'لا تملك صلاحية إنشاء مهمة');
  END IF;
  IF p_title IS NULL OR btrim(p_title) = '' THEN
    RETURN private.work_command_error(p_operation_id, 'work_create_task', 'VALIDATION_ERROR', 'عنوان المهمة مطلوب');
  END IF;
  IF NOT private.work_user_can_assign_target(v_actor, v_owner)
     OR NOT private.work_user_can_assign_target(v_actor, v_assignee) THEN
    RETURN private.work_command_error(p_operation_id, 'work_create_task', 'ASSIGNMENT_SCOPE_DENIED', 'لا يمكن إسناد المهمة للمستخدم المحدد ضمن نطاقك الحالي');
  END IF;
  IF p_activate AND (p_expected_outcome IS NULL OR btrim(p_expected_outcome) = '') THEN
    RETURN private.work_command_error(p_operation_id, 'work_create_task', 'EXPECTED_OUTCOME_REQUIRED', 'النتيجة المتوقعة مطلوبة قبل تفعيل المهمة');
  END IF;
  IF p_activate AND (p_next_action_text IS NULL OR btrim(p_next_action_text) = '') THEN
    RETURN private.work_command_error(p_operation_id, 'work_create_task', 'NEXT_ACTION_REQUIRED', 'الإجراء التالي مطلوب قبل تفعيل المهمة');
  END IF;

  BEGIN
    v_result := private.work_insert_task_draft(
      p_operation_id, v_actor, p_title, p_description, p_expected_outcome,
      p_priority, p_visibility, v_owner, v_assignee, p_due_at,
      p_next_action_text, p_next_action_at, p_acknowledgement_required,
      p_completion_mode
    );

    SELECT * INTO v_item FROM public.work_items
    WHERE id = (v_result->>'work_item_id')::UUID
    FOR UPDATE;

    IF p_activate THEN
      UPDATE public.work_items
      SET status = 'open'::public.work_item_status,
          activated_at = clock_timestamp(),
          assigned_at = clock_timestamp(),
          state_version = state_version + 1,
          last_meaningful_activity_at = clock_timestamp()
      WHERE id = v_item.id
      RETURNING * INTO v_item;

      PERFORM private.work_append_user_event(
        v_item.id, 'work.activated', v_actor, p_operation_id,
        'draft'::public.work_item_status, 'open'::public.work_item_status,
        jsonb_build_object('assignee_user_id', v_assignee, 'owner_user_id', v_owner)
      );
    END IF;

    v_result := jsonb_build_object(
      'work_item_id', v_item.id,
      'work_number', v_item.work_number,
      'status', v_item.status,
      'state_version', v_item.state_version
    );
    RETURN private.work_command_success(p_operation_id, 'work_create_task', v_item.id, v_result);
  EXCEPTION WHEN OTHERS THEN
    RETURN private.work_command_error(p_operation_id, 'work_create_task', 'INTERNAL_ERROR', 'تعذر إنشاء المهمة');
  END;
END;
$$;

-- --------------------------------------------------------------------------
-- Subtask creation. Parent ownership/assignment are inherited unless supplied.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.work_create_subtask(
  p_operation_id UUID,
  p_parent_work_item_id UUID,
  p_expected_parent_version BIGINT,
  p_title TEXT,
  p_description TEXT DEFAULT NULL,
  p_expected_outcome TEXT DEFAULT NULL,
  p_priority public.work_priority DEFAULT 'normal',
  p_owner_user_id UUID DEFAULT NULL,
  p_assignee_user_id UUID DEFAULT NULL,
  p_due_at TIMESTAMPTZ DEFAULT NULL,
  p_next_action_text VARCHAR(500) DEFAULT NULL,
  p_next_action_at TIMESTAMPTZ DEFAULT NULL,
  p_blocks_parent_completion BOOLEAN DEFAULT true,
  p_activate BOOLEAN DEFAULT true
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_prepare JSONB;
  v_parent public.work_items%ROWTYPE;
  v_child public.work_items%ROWTYPE;
  v_owner UUID;
  v_assignee UUID;
  v_result JSONB;
BEGIN
  v_prepare := private.work_prepare_operation(
    p_operation_id, v_actor, 'work_create_subtask',
    jsonb_build_object(
      'parent', p_parent_work_item_id, 'parent_version', p_expected_parent_version,
      'title', p_title, 'description', p_description, 'expected_outcome', p_expected_outcome,
      'priority', p_priority, 'owner', p_owner_user_id, 'assignee', p_assignee_user_id,
      'due_at', p_due_at, 'next_action_text', p_next_action_text,
      'next_action_at', p_next_action_at, 'blocks_parent', p_blocks_parent_completion,
      'activate', p_activate
    ), p_parent_work_item_id
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN, false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_parent FROM public.work_items
  WHERE id = p_parent_work_item_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN private.work_command_error(p_operation_id, 'work_create_subtask', 'NOT_FOUND', 'المهمة الرئيسية غير موجودة', p_parent_work_item_id);
  END IF;
  IF v_parent.state_version <> p_expected_parent_version THEN
    RETURN private.work_command_error(p_operation_id, 'work_create_subtask', 'VERSION_CONFLICT', 'تم تعديل المهمة الرئيسية بواسطة مستخدم آخر', p_parent_work_item_id);
  END IF;
  IF v_parent.status IN ('done'::public.work_item_status, 'cancelled'::public.work_item_status) THEN
    RETURN private.work_command_error(p_operation_id, 'work_create_subtask', 'INVALID_STATE', 'لا يمكن إضافة مهمة فرعية إلى مهمة منتهية', p_parent_work_item_id);
  END IF;
  IF NOT private.work_actor_can_update_item(v_actor, p_parent_work_item_id) THEN
    RETURN private.work_command_error(p_operation_id, 'work_create_subtask', 'FORBIDDEN', 'لا تملك صلاحية تعديل المهمة الرئيسية', p_parent_work_item_id);
  END IF;

  v_owner := COALESCE(p_owner_user_id, v_parent.accountable_owner_user_id, v_actor);
  v_assignee := COALESCE(p_assignee_user_id, v_parent.current_assignee_user_id, v_owner);
  IF NOT private.work_user_can_assign_target(v_actor, v_owner)
     OR NOT private.work_user_can_assign_target(v_actor, v_assignee) THEN
    RETURN private.work_command_error(p_operation_id, 'work_create_subtask', 'ASSIGNMENT_SCOPE_DENIED', 'لا يمكن إسناد المهمة الفرعية للمستخدم المحدد', p_parent_work_item_id);
  END IF;
  IF p_title IS NULL OR btrim(p_title) = '' THEN
    RETURN private.work_command_error(p_operation_id, 'work_create_subtask', 'VALIDATION_ERROR', 'عنوان المهمة الفرعية مطلوب', p_parent_work_item_id);
  END IF;
  IF p_activate AND (p_expected_outcome IS NULL OR btrim(p_expected_outcome) = '') THEN
    RETURN private.work_command_error(p_operation_id, 'work_create_subtask', 'EXPECTED_OUTCOME_REQUIRED', 'النتيجة المتوقعة مطلوبة', p_parent_work_item_id);
  END IF;
  IF p_activate AND (p_next_action_text IS NULL OR btrim(p_next_action_text) = '') THEN
    RETURN private.work_command_error(p_operation_id, 'work_create_subtask', 'NEXT_ACTION_REQUIRED', 'الإجراء التالي مطلوب', p_parent_work_item_id);
  END IF;

  BEGIN
    v_result := private.work_insert_task_draft(
      p_operation_id, v_actor, p_title, p_description, p_expected_outcome,
      p_priority, v_parent.visibility, v_owner, v_assignee, p_due_at,
      p_next_action_text, p_next_action_at, false, v_parent.completion_mode
    );

    UPDATE public.work_items
    SET parent_work_item_id = p_parent_work_item_id,
        blocks_parent_completion = p_blocks_parent_completion,
        status = CASE WHEN p_activate THEN 'open'::public.work_item_status ELSE 'draft'::public.work_item_status END,
        activated_at = CASE WHEN p_activate THEN clock_timestamp() ELSE NULL END,
        assigned_at = CASE WHEN p_activate THEN clock_timestamp() ELSE NULL END,
        state_version = CASE WHEN p_activate THEN state_version + 1 ELSE state_version END,
        last_meaningful_activity_at = clock_timestamp()
    WHERE id = (v_result->>'work_item_id')::UUID
    RETURNING * INTO v_child;

    PERFORM private.work_append_user_event(
      v_child.id, 'work.parent_linked', v_actor, p_operation_id,
      NULL, v_child.status,
      jsonb_build_object('parent_work_item_id', p_parent_work_item_id, 'blocks_parent_completion', p_blocks_parent_completion)
    );

    UPDATE public.work_items
    SET state_version = state_version + 1,
        last_meaningful_activity_at = clock_timestamp()
    WHERE id = p_parent_work_item_id;

    v_result := jsonb_build_object(
      'work_item_id', v_child.id, 'work_number', v_child.work_number,
      'status', v_child.status, 'state_version', v_child.state_version,
      'parent_work_item_id', p_parent_work_item_id
    );
    RETURN private.work_command_success(p_operation_id, 'work_create_subtask', v_child.id, v_result);
  EXCEPTION WHEN OTHERS THEN
    RETURN private.work_command_error(p_operation_id, 'work_create_subtask', 'INTERNAL_ERROR', 'تعذر إنشاء المهمة الفرعية', p_parent_work_item_id);
  END;
END;
$$;

-- --------------------------------------------------------------------------
-- First view is intentionally not meaningful activity and does not bump state.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.work_record_first_view(p_work_item_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_item public.work_items%ROWTYPE;
BEGIN
  SELECT * INTO v_item FROM public.work_items WHERE id = p_work_item_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object('code', 'NOT_FOUND', 'message', 'المهمة غير موجودة')); END IF;

  IF NOT private.work_user_can_view_row(
    v_actor, v_item.id, v_item.visibility, v_item.creator_user_id, v_item.requester_user_id,
    v_item.accountable_owner_user_id, v_item.current_assignee_user_id,
    v_item.branch_id, v_item.owning_department_id
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object('code', 'FORBIDDEN', 'message', 'غير مصرح بعرض المهمة'));
  END IF;

  IF v_item.current_assignee_user_id = v_actor AND v_item.first_viewed_at IS NULL THEN
    UPDATE public.work_items SET first_viewed_at = clock_timestamp() WHERE id = p_work_item_id AND first_viewed_at IS NULL;
  END IF;

  RETURN jsonb_build_object('ok', true, 'work_item_id', p_work_item_id);
END;
$$;

-- --------------------------------------------------------------------------
-- Acknowledge assignment.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.work_acknowledge(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_prepare JSONB;
  v_item public.work_items%ROWTYPE;
  v_result JSONB;
BEGIN
  v_prepare := private.work_prepare_operation(p_operation_id, v_actor, 'work_acknowledge', jsonb_build_object('work_item_id', p_work_item_id, 'expected_version', p_expected_version), p_work_item_id);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN, false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id = p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id, 'work_acknowledge', 'NOT_FOUND', 'المهمة غير موجودة', p_work_item_id); END IF;
  IF v_item.state_version <> p_expected_version THEN RETURN private.work_command_error(p_operation_id, 'work_acknowledge', 'VERSION_CONFLICT', 'تم تعديل المهمة بواسطة مستخدم آخر', p_work_item_id); END IF;
  IF v_item.current_assignee_user_id <> v_actor THEN RETURN private.work_command_error(p_operation_id, 'work_acknowledge', 'FORBIDDEN', 'التأكيد متاح للمكلف الحالي فقط', p_work_item_id); END IF;
  IF v_item.status IN ('done'::public.work_item_status, 'cancelled'::public.work_item_status) THEN RETURN private.work_command_error(p_operation_id, 'work_acknowledge', 'INVALID_STATE', 'المهمة منتهية', p_work_item_id); END IF;

  UPDATE public.work_items
  SET acknowledged_at = COALESCE(acknowledged_at, clock_timestamp()),
      state_version = state_version + 1
  WHERE id = p_work_item_id
  RETURNING * INTO v_item;

  PERFORM private.work_append_user_event(v_item.id, 'work.acknowledged', v_actor, p_operation_id, v_item.status, v_item.status, '{}'::JSONB);
  v_result := jsonb_build_object('work_item_id', v_item.id, 'status', v_item.status, 'state_version', v_item.state_version);
  RETURN private.work_command_success(p_operation_id, 'work_acknowledge', v_item.id, v_result);
END;
$$;

-- --------------------------------------------------------------------------
-- Start execution.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.work_start(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_prepare JSONB;
  v_item public.work_items%ROWTYPE;
  v_result JSONB;
BEGIN
  v_prepare := private.work_prepare_operation(p_operation_id, v_actor, 'work_start', jsonb_build_object('work_item_id', p_work_item_id, 'expected_version', p_expected_version), p_work_item_id);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN, false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id = p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id, 'work_start', 'NOT_FOUND', 'المهمة غير موجودة', p_work_item_id); END IF;
  IF v_item.state_version <> p_expected_version THEN RETURN private.work_command_error(p_operation_id, 'work_start', 'VERSION_CONFLICT', 'تم تعديل المهمة بواسطة مستخدم آخر', p_work_item_id); END IF;
  IF v_item.current_assignee_user_id <> v_actor AND NOT private.work_user_can_manage_item(v_actor, p_work_item_id) THEN RETURN private.work_command_error(p_operation_id, 'work_start', 'FORBIDDEN', 'غير مصرح ببدء المهمة', p_work_item_id); END IF;
  IF v_item.status <> 'open'::public.work_item_status THEN RETURN private.work_command_error(p_operation_id, 'work_start', 'INVALID_STATE', 'يمكن بدء المهمة من حالة مفتوحة فقط', p_work_item_id); END IF;
  IF v_item.start_not_before IS NOT NULL AND v_item.start_not_before > clock_timestamp() THEN RETURN private.work_command_error(p_operation_id, 'work_start', 'START_NOT_ALLOWED_YET', 'لم يحن موعد بدء المهمة بعد', p_work_item_id); END IF;
  IF v_item.acknowledgement_required AND v_item.acknowledged_at IS NULL THEN RETURN private.work_command_error(p_operation_id, 'work_start', 'ACKNOWLEDGEMENT_REQUIRED', 'يجب تأكيد استلام المهمة أولًا', p_work_item_id); END IF;
  IF EXISTS (
    SELECT 1 FROM public.work_dependencies d
    JOIN public.work_items blocker ON blocker.id = d.blocker_work_item_id
    WHERE d.blocked_work_item_id = p_work_item_id AND d.resolved_at IS NULL
      AND d.dependency_strength = 'hard'::public.work_dependency_strength
      AND blocker.status <> 'done'::public.work_item_status
  ) THEN RETURN private.work_command_error(p_operation_id, 'work_start', 'BLOCKED_BY_DEPENDENCY', 'المهمة مرتبطة باعتماد سابق لم يكتمل', p_work_item_id); END IF;

  UPDATE public.work_items
  SET status = 'in_progress'::public.work_item_status,
      started_at = COALESCE(started_at, clock_timestamp()),
      state_version = state_version + 1,
      last_meaningful_activity_at = clock_timestamp()
  WHERE id = p_work_item_id RETURNING * INTO v_item;

  PERFORM private.work_append_user_event(v_item.id, 'work.started', v_actor, p_operation_id, 'open'::public.work_item_status, 'in_progress'::public.work_item_status, '{}'::JSONB);
  v_result := jsonb_build_object('work_item_id', v_item.id, 'status', v_item.status, 'state_version', v_item.state_version);
  RETURN private.work_command_success(p_operation_id, 'work_start', v_item.id, v_result);
END;
$$;

-- --------------------------------------------------------------------------
-- Waiting requires an explicit reason, next action and follow-up timestamp.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.work_set_waiting(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT,
  p_waiting_on_type public.work_waiting_on_type,
  p_waiting_reason TEXT,
  p_next_action_text VARCHAR(500),
  p_follow_up_at TIMESTAMPTZ,
  p_waiting_on_user_id UUID DEFAULT NULL,
  p_waiting_on_entity_type TEXT DEFAULT NULL,
  p_waiting_on_entity_id UUID DEFAULT NULL,
  p_waiting_on_label VARCHAR(250) DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_prepare JSONB;
  v_item public.work_items%ROWTYPE;
  v_from public.work_item_status;
  v_result JSONB;
BEGIN
  v_prepare := private.work_prepare_operation(
    p_operation_id, v_actor, 'work_set_waiting',
    jsonb_build_object('work_item_id', p_work_item_id, 'expected_version', p_expected_version, 'waiting_on_type', p_waiting_on_type, 'waiting_reason', p_waiting_reason, 'next_action_text', p_next_action_text, 'follow_up_at', p_follow_up_at, 'waiting_on_user_id', p_waiting_on_user_id, 'waiting_on_entity_type', p_waiting_on_entity_type, 'waiting_on_entity_id', p_waiting_on_entity_id, 'waiting_on_label', p_waiting_on_label),
    p_work_item_id
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN, false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id = p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id, 'work_set_waiting', 'NOT_FOUND', 'المهمة غير موجودة', p_work_item_id); END IF;
  IF v_item.state_version <> p_expected_version THEN RETURN private.work_command_error(p_operation_id, 'work_set_waiting', 'VERSION_CONFLICT', 'تم تعديل المهمة بواسطة مستخدم آخر', p_work_item_id); END IF;
  IF NOT private.work_actor_can_update_item(v_actor, p_work_item_id) THEN RETURN private.work_command_error(p_operation_id, 'work_set_waiting', 'FORBIDDEN', 'غير مصرح بتحديث المهمة', p_work_item_id); END IF;
  IF v_item.status NOT IN ('open'::public.work_item_status, 'in_progress'::public.work_item_status) THEN RETURN private.work_command_error(p_operation_id, 'work_set_waiting', 'INVALID_STATE', 'لا يمكن تحويل المهمة إلى انتظار من حالتها الحالية', p_work_item_id); END IF;
  IF p_waiting_reason IS NULL OR btrim(p_waiting_reason) = '' OR p_next_action_text IS NULL OR btrim(p_next_action_text) = '' OR p_follow_up_at IS NULL THEN RETURN private.work_command_error(p_operation_id, 'work_set_waiting', 'WAITING_DETAILS_REQUIRED', 'سبب الانتظار والإجراء التالي وموعد المتابعة مطلوبة', p_work_item_id); END IF;
  IF p_waiting_on_type = 'user'::public.work_waiting_on_type AND p_waiting_on_user_id IS NULL THEN RETURN private.work_command_error(p_operation_id, 'work_set_waiting', 'WAITING_USER_REQUIRED', 'حدد الشخص المنتظر منه الإجراء', p_work_item_id); END IF;
  IF p_waiting_on_type = 'entity'::public.work_waiting_on_type AND (p_waiting_on_entity_type IS NULL OR p_waiting_on_entity_id IS NULL) THEN RETURN private.work_command_error(p_operation_id, 'work_set_waiting', 'WAITING_ENTITY_REQUIRED', 'بيانات الجهة أو السجل المنتظر مطلوبة', p_work_item_id); END IF;

  v_from := v_item.status;
  UPDATE public.work_items
  SET status = 'waiting'::public.work_item_status,
      waiting_on_type = p_waiting_on_type::TEXT,
      waiting_on_user_id = p_waiting_on_user_id,
      waiting_on_entity_type = p_waiting_on_entity_type,
      waiting_on_entity_id = p_waiting_on_entity_id,
      waiting_on_label = p_waiting_on_label,
      waiting_reason = p_waiting_reason,
      waiting_since = clock_timestamp(),
      next_action_text = p_next_action_text,
      next_action_at = p_follow_up_at,
      state_version = state_version + 1,
      last_meaningful_activity_at = clock_timestamp()
  WHERE id = p_work_item_id RETURNING * INTO v_item;

  PERFORM private.work_append_user_event(v_item.id, 'work.waiting', v_actor, p_operation_id, v_from, 'waiting'::public.work_item_status, jsonb_build_object('waiting_on_type', p_waiting_on_type, 'waiting_reason', p_waiting_reason, 'follow_up_at', p_follow_up_at));
  v_result := jsonb_build_object('work_item_id', v_item.id, 'status', v_item.status, 'state_version', v_item.state_version);
  RETURN private.work_command_success(p_operation_id, 'work_set_waiting', v_item.id, v_result);
END;
$$;

-- --------------------------------------------------------------------------
-- Resume from waiting.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.work_resume(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT,
  p_next_action_text VARCHAR(500),
  p_next_action_at TIMESTAMPTZ DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_prepare JSONB;
  v_item public.work_items%ROWTYPE;
  v_result JSONB;
BEGIN
  v_prepare := private.work_prepare_operation(p_operation_id, v_actor, 'work_resume', jsonb_build_object('work_item_id', p_work_item_id, 'expected_version', p_expected_version, 'next_action_text', p_next_action_text, 'next_action_at', p_next_action_at), p_work_item_id);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN, false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id = p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id, 'work_resume', 'NOT_FOUND', 'المهمة غير موجودة', p_work_item_id); END IF;
  IF v_item.state_version <> p_expected_version THEN RETURN private.work_command_error(p_operation_id, 'work_resume', 'VERSION_CONFLICT', 'تم تعديل المهمة بواسطة مستخدم آخر', p_work_item_id); END IF;
  IF NOT private.work_actor_can_update_item(v_actor, p_work_item_id) THEN RETURN private.work_command_error(p_operation_id, 'work_resume', 'FORBIDDEN', 'غير مصرح بتحديث المهمة', p_work_item_id); END IF;
  IF v_item.status <> 'waiting'::public.work_item_status THEN RETURN private.work_command_error(p_operation_id, 'work_resume', 'INVALID_STATE', 'المهمة ليست في حالة انتظار', p_work_item_id); END IF;
  IF p_next_action_text IS NULL OR btrim(p_next_action_text) = '' THEN RETURN private.work_command_error(p_operation_id, 'work_resume', 'NEXT_ACTION_REQUIRED', 'الإجراء التالي مطلوب', p_work_item_id); END IF;

  UPDATE public.work_items
  SET status = 'in_progress'::public.work_item_status,
      waiting_on_type = NULL, waiting_on_user_id = NULL,
      waiting_on_entity_type = NULL, waiting_on_entity_id = NULL,
      waiting_on_label = NULL, waiting_reason = NULL, waiting_since = NULL,
      next_action_text = p_next_action_text, next_action_at = p_next_action_at,
      state_version = state_version + 1,
      last_meaningful_activity_at = clock_timestamp()
  WHERE id = p_work_item_id RETURNING * INTO v_item;

  PERFORM private.work_append_user_event(v_item.id, 'work.resumed', v_actor, p_operation_id, 'waiting'::public.work_item_status, 'in_progress'::public.work_item_status, jsonb_build_object('next_action_text', p_next_action_text, 'next_action_at', p_next_action_at));
  v_result := jsonb_build_object('work_item_id', v_item.id, 'status', v_item.status, 'state_version', v_item.state_version);
  RETURN private.work_command_success(p_operation_id, 'work_resume', v_item.id, v_result);
END;
$$;

-- --------------------------------------------------------------------------
-- Update next action without changing lifecycle state.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.work_update_next_action(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT,
  p_next_action_text VARCHAR(500),
  p_next_action_at TIMESTAMPTZ DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_prepare JSONB;
  v_item public.work_items%ROWTYPE;
  v_result JSONB;
BEGIN
  v_prepare := private.work_prepare_operation(p_operation_id, v_actor, 'work_update_next_action', jsonb_build_object('work_item_id', p_work_item_id, 'expected_version', p_expected_version, 'next_action_text', p_next_action_text, 'next_action_at', p_next_action_at), p_work_item_id);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN, false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id = p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id, 'work_update_next_action', 'NOT_FOUND', 'المهمة غير موجودة', p_work_item_id); END IF;
  IF v_item.state_version <> p_expected_version THEN RETURN private.work_command_error(p_operation_id, 'work_update_next_action', 'VERSION_CONFLICT', 'تم تعديل المهمة بواسطة مستخدم آخر', p_work_item_id); END IF;
  IF NOT private.work_actor_can_update_item(v_actor, p_work_item_id) THEN RETURN private.work_command_error(p_operation_id, 'work_update_next_action', 'FORBIDDEN', 'غير مصرح بتحديث المهمة', p_work_item_id); END IF;
  IF v_item.status IN ('done'::public.work_item_status, 'cancelled'::public.work_item_status) THEN RETURN private.work_command_error(p_operation_id, 'work_update_next_action', 'INVALID_STATE', 'المهمة منتهية', p_work_item_id); END IF;
  IF p_next_action_text IS NULL OR btrim(p_next_action_text) = '' THEN RETURN private.work_command_error(p_operation_id, 'work_update_next_action', 'NEXT_ACTION_REQUIRED', 'الإجراء التالي مطلوب', p_work_item_id); END IF;
  IF v_item.status = 'waiting'::public.work_item_status AND p_next_action_at IS NULL THEN RETURN private.work_command_error(p_operation_id, 'work_update_next_action', 'FOLLOW_UP_REQUIRED', 'موعد المتابعة مطلوب أثناء الانتظار', p_work_item_id); END IF;

  UPDATE public.work_items
  SET next_action_text = p_next_action_text, next_action_at = p_next_action_at,
      state_version = state_version + 1, last_meaningful_activity_at = clock_timestamp()
  WHERE id = p_work_item_id RETURNING * INTO v_item;

  PERFORM private.work_append_user_event(v_item.id, 'work.next_action_updated', v_actor, p_operation_id, v_item.status, v_item.status, jsonb_build_object('next_action_text', p_next_action_text, 'next_action_at', p_next_action_at));
  v_result := jsonb_build_object('work_item_id', v_item.id, 'status', v_item.status, 'state_version', v_item.state_version);
  RETURN private.work_command_success(p_operation_id, 'work_update_next_action', v_item.id, v_result);
END;
$$;

-- --------------------------------------------------------------------------
-- Delegation changes executor only; accountability remains with the owner.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.work_delegate(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT,
  p_new_assignee_user_id UUID,
  p_reason TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_prepare JSONB;
  v_item public.work_items%ROWTYPE;
  v_old_assignee UUID;
  v_result JSONB;
BEGIN
  v_prepare := private.work_prepare_operation(p_operation_id, v_actor, 'work_delegate', jsonb_build_object('work_item_id', p_work_item_id, 'expected_version', p_expected_version, 'new_assignee', p_new_assignee_user_id, 'reason', p_reason), p_work_item_id);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN, false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id = p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id, 'work_delegate', 'NOT_FOUND', 'المهمة غير موجودة', p_work_item_id); END IF;
  IF v_item.state_version <> p_expected_version THEN RETURN private.work_command_error(p_operation_id, 'work_delegate', 'VERSION_CONFLICT', 'تم تعديل المهمة بواسطة مستخدم آخر', p_work_item_id); END IF;
  IF v_item.status IN ('done'::public.work_item_status, 'cancelled'::public.work_item_status) THEN RETURN private.work_command_error(p_operation_id, 'work_delegate', 'INVALID_STATE', 'المهمة منتهية', p_work_item_id); END IF;
  IF NOT COALESCE(public.check_permission(v_actor, 'work.items.delegate'), false) THEN RETURN private.work_command_error(p_operation_id, 'work_delegate', 'FORBIDDEN', 'لا تملك صلاحية التفويض', p_work_item_id); END IF;
  IF NOT private.work_actor_can_update_item(v_actor, p_work_item_id) THEN RETURN private.work_command_error(p_operation_id, 'work_delegate', 'FORBIDDEN', 'غير مصرح بإدارة هذه المهمة', p_work_item_id); END IF;
  IF NOT private.work_user_can_assign_target(v_actor, p_new_assignee_user_id) THEN RETURN private.work_command_error(p_operation_id, 'work_delegate', 'ASSIGNMENT_SCOPE_DENIED', 'المستخدم الجديد خارج نطاق الإسناد المسموح', p_work_item_id); END IF;

  v_old_assignee := v_item.current_assignee_user_id;
  UPDATE public.work_items
  SET current_assignee_user_id = p_new_assignee_user_id,
      assigned_at = clock_timestamp(), first_viewed_at = NULL, acknowledged_at = NULL,
      state_version = state_version + 1, last_meaningful_activity_at = clock_timestamp()
  WHERE id = p_work_item_id RETURNING * INTO v_item;

  PERFORM private.work_append_user_event(v_item.id, 'work.delegated', v_actor, p_operation_id, v_item.status, v_item.status, jsonb_build_object('from_assignee_user_id', v_old_assignee, 'to_assignee_user_id', p_new_assignee_user_id, 'reason', p_reason));
  v_result := jsonb_build_object('work_item_id', v_item.id, 'status', v_item.status, 'state_version', v_item.state_version, 'current_assignee_user_id', p_new_assignee_user_id);
  RETURN private.work_command_success(p_operation_id, 'work_delegate', v_item.id, v_result);
END;
$$;

-- --------------------------------------------------------------------------
-- Ownership transfer changes accountability and is intentionally distinct.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.work_transfer_ownership(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT,
  p_new_owner_user_id UUID,
  p_reason TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_prepare JSONB;
  v_item public.work_items%ROWTYPE;
  v_old_owner UUID;
  v_result JSONB;
BEGIN
  v_prepare := private.work_prepare_operation(p_operation_id, v_actor, 'work_transfer_ownership', jsonb_build_object('work_item_id', p_work_item_id, 'expected_version', p_expected_version, 'new_owner', p_new_owner_user_id, 'reason', p_reason), p_work_item_id);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN, false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id = p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id, 'work_transfer_ownership', 'NOT_FOUND', 'المهمة غير موجودة', p_work_item_id); END IF;
  IF v_item.state_version <> p_expected_version THEN RETURN private.work_command_error(p_operation_id, 'work_transfer_ownership', 'VERSION_CONFLICT', 'تم تعديل المهمة بواسطة مستخدم آخر', p_work_item_id); END IF;
  IF NOT COALESCE(public.check_permission(v_actor, 'work.items.transfer_ownership'), false) OR NOT private.work_actor_can_update_item(v_actor, p_work_item_id) THEN RETURN private.work_command_error(p_operation_id, 'work_transfer_ownership', 'FORBIDDEN', 'غير مصرح بنقل مسؤولية المهمة', p_work_item_id); END IF;
  IF NOT private.work_user_can_assign_target(v_actor, p_new_owner_user_id) THEN RETURN private.work_command_error(p_operation_id, 'work_transfer_ownership', 'ASSIGNMENT_SCOPE_DENIED', 'المالك الجديد خارج نطاق الإسناد المسموح', p_work_item_id); END IF;

  v_old_owner := v_item.accountable_owner_user_id;
  UPDATE public.work_items
  SET accountable_owner_user_id = p_new_owner_user_id,
      state_version = state_version + 1, last_meaningful_activity_at = clock_timestamp()
  WHERE id = p_work_item_id RETURNING * INTO v_item;

  PERFORM private.work_append_user_event(v_item.id, 'work.ownership_transferred', v_actor, p_operation_id, v_item.status, v_item.status, jsonb_build_object('from_owner_user_id', v_old_owner, 'to_owner_user_id', p_new_owner_user_id, 'reason', p_reason));
  v_result := jsonb_build_object('work_item_id', v_item.id, 'status', v_item.status, 'state_version', v_item.state_version, 'accountable_owner_user_id', p_new_owner_user_id);
  RETURN private.work_command_success(p_operation_id, 'work_transfer_ownership', v_item.id, v_result);
END;
$$;

-- --------------------------------------------------------------------------
-- Direct due-date change. Approval-bound policies are added by the Approval layer.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.work_change_due(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT,
  p_new_due_at TIMESTAMPTZ,
  p_reason TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_prepare JSONB;
  v_item public.work_items%ROWTYPE;
  v_old_due TIMESTAMPTZ;
  v_result JSONB;
BEGIN
  v_prepare := private.work_prepare_operation(p_operation_id, v_actor, 'work_change_due', jsonb_build_object('work_item_id', p_work_item_id, 'expected_version', p_expected_version, 'new_due_at', p_new_due_at, 'reason', p_reason), p_work_item_id);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN, false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id = p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id, 'work_change_due', 'NOT_FOUND', 'المهمة غير موجودة', p_work_item_id); END IF;
  IF v_item.state_version <> p_expected_version THEN RETURN private.work_command_error(p_operation_id, 'work_change_due', 'VERSION_CONFLICT', 'تم تعديل المهمة بواسطة مستخدم آخر', p_work_item_id); END IF;
  IF NOT private.work_actor_can_update_item(v_actor, p_work_item_id) THEN RETURN private.work_command_error(p_operation_id, 'work_change_due', 'FORBIDDEN', 'غير مصرح بتعديل موعد المهمة', p_work_item_id); END IF;
  IF v_item.status IN ('done'::public.work_item_status, 'cancelled'::public.work_item_status) THEN RETURN private.work_command_error(p_operation_id, 'work_change_due', 'INVALID_STATE', 'المهمة منتهية', p_work_item_id); END IF;
  IF p_reason IS NULL OR btrim(p_reason) = '' THEN RETURN private.work_command_error(p_operation_id, 'work_change_due', 'REASON_REQUIRED', 'سبب تعديل الموعد مطلوب', p_work_item_id); END IF;

  v_old_due := v_item.due_at;
  UPDATE public.work_items
  SET due_at = p_new_due_at,
      first_due_at = COALESCE(first_due_at, p_new_due_at),
      state_version = state_version + 1,
      last_meaningful_activity_at = clock_timestamp()
  WHERE id = p_work_item_id RETURNING * INTO v_item;

  PERFORM private.work_append_user_event(v_item.id, 'work.due_changed', v_actor, p_operation_id, v_item.status, v_item.status, jsonb_build_object('from_due_at', v_old_due, 'to_due_at', p_new_due_at, 'reason', p_reason));
  v_result := jsonb_build_object('work_item_id', v_item.id, 'status', v_item.status, 'state_version', v_item.state_version, 'due_at', v_item.due_at);
  RETURN private.work_command_success(p_operation_id, 'work_change_due', v_item.id, v_result);
END;
$$;

REVOKE ALL ON FUNCTION public.work_create_task(UUID, TEXT, TEXT, TEXT, public.work_priority, public.work_visibility, UUID, UUID, TIMESTAMPTZ, VARCHAR, TIMESTAMPTZ, BOOLEAN, public.work_completion_mode, BOOLEAN) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.work_create_subtask(UUID, UUID, BIGINT, TEXT, TEXT, TEXT, public.work_priority, UUID, UUID, TIMESTAMPTZ, VARCHAR, TIMESTAMPTZ, BOOLEAN, BOOLEAN) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.work_record_first_view(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.work_acknowledge(UUID, UUID, BIGINT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.work_start(UUID, UUID, BIGINT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.work_set_waiting(UUID, UUID, BIGINT, public.work_waiting_on_type, TEXT, VARCHAR, TIMESTAMPTZ, UUID, TEXT, UUID, VARCHAR) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.work_resume(UUID, UUID, BIGINT, VARCHAR, TIMESTAMPTZ) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.work_update_next_action(UUID, UUID, BIGINT, VARCHAR, TIMESTAMPTZ) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.work_delegate(UUID, UUID, BIGINT, UUID, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.work_transfer_ownership(UUID, UUID, BIGINT, UUID, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.work_change_due(UUID, UUID, BIGINT, TIMESTAMPTZ, TEXT) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.work_create_task(UUID, TEXT, TEXT, TEXT, public.work_priority, public.work_visibility, UUID, UUID, TIMESTAMPTZ, VARCHAR, TIMESTAMPTZ, BOOLEAN, public.work_completion_mode, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_create_subtask(UUID, UUID, BIGINT, TEXT, TEXT, TEXT, public.work_priority, UUID, UUID, TIMESTAMPTZ, VARCHAR, TIMESTAMPTZ, BOOLEAN, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_record_first_view(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_acknowledge(UUID, UUID, BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_start(UUID, UUID, BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_set_waiting(UUID, UUID, BIGINT, public.work_waiting_on_type, TEXT, VARCHAR, TIMESTAMPTZ, UUID, TEXT, UUID, VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_resume(UUID, UUID, BIGINT, VARCHAR, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_update_next_action(UUID, UUID, BIGINT, VARCHAR, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_delegate(UUID, UUID, BIGINT, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_transfer_ownership(UUID, UUID, BIGINT, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_change_due(UUID, UUID, BIGINT, TIMESTAMPTZ, TEXT) TO authenticated;

RESET lock_timeout;
RESET statement_timeout;
