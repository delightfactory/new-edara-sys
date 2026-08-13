-- Work Management — Migration C2b: atomic Create Task private implementation.
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION private.create_work_task_atomic_impl(
  p_operation_id UUID,
  p_title TEXT,
  p_description TEXT,
  p_expected_outcome TEXT,
  p_priority public.work_priority DEFAULT 'normal',
  p_visibility public.work_visibility DEFAULT 'standard',
  p_owner_user_id UUID DEFAULT NULL,
  p_assignee_user_id UUID DEFAULT NULL,
  p_due_at TIMESTAMPTZ DEFAULT NULL,
  p_next_action_text VARCHAR(500) DEFAULT NULL,
  p_next_action_at TIMESTAMPTZ DEFAULT NULL,
  p_acknowledgement_required BOOLEAN DEFAULT false,
  p_completion_mode public.work_completion_mode DEFAULT 'assignee_closes'
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_owner UUID;
  v_assignee UUID;
  v_payload JSONB;
  v_prepare JSONB;
  v_result JSONB;
  v_safe_code TEXT;
  v_safe_message TEXT;
BEGIN
  v_owner := COALESCE(p_owner_user_id, v_actor);
  v_assignee := COALESCE(p_assignee_user_id, v_owner);

  v_payload := jsonb_build_object(
    'title', p_title,
    'description', p_description,
    'expected_outcome', p_expected_outcome,
    'priority', p_priority,
    'visibility', p_visibility,
    'owner_user_id', v_owner,
    'assignee_user_id', v_assignee,
    'due_at', p_due_at,
    'next_action_text', p_next_action_text,
    'next_action_at', p_next_action_at,
    'acknowledgement_required', COALESCE(p_acknowledgement_required, false),
    'completion_mode', p_completion_mode
  );

  v_prepare := private.work_prepare_operation(
    p_operation_id,
    v_actor,
    'create_work_task_atomic',
    v_payload,
    NULL
  );

  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN, false) THEN
    RETURN v_prepare->'response';
  END IF;

  BEGIN
    IF NOT COALESCE(public.check_permission(v_actor, 'work.items.create'), false) THEN
      RAISE EXCEPTION 'permission denied';
    END IF;

    IF p_title IS NULL OR btrim(p_title) = '' OR char_length(btrim(p_title)) > 250 THEN
      RAISE EXCEPTION 'invalid title';
    END IF;

    IF p_due_at IS NOT NULL AND p_due_at <= clock_timestamp() THEN
      RAISE EXCEPTION 'due date must be in the future';
    END IF;

    IF p_next_action_at IS NOT NULL AND p_next_action_at <= clock_timestamp() THEN
      RAISE EXCEPTION 'next action date must be in the future';
    END IF;

    IF NOT private.work_user_can_assign_target(v_actor, v_owner)
       OR NOT private.work_user_can_assign_target(v_actor, v_assignee) THEN
      RAISE EXCEPTION 'assignment outside authorised scope';
    END IF;

    v_result := private.work_insert_task_draft(
      p_operation_id,
      v_actor,
      btrim(p_title),
      NULLIF(btrim(COALESCE(p_description, '')), ''),
      NULLIF(btrim(COALESCE(p_expected_outcome, '')), ''),
      COALESCE(p_priority, 'normal'::public.work_priority),
      COALESCE(p_visibility, 'standard'::public.work_visibility),
      v_owner,
      v_assignee,
      p_due_at,
      COALESCE(NULLIF(btrim(COALESCE(p_next_action_text, '')), ''), left(btrim(p_title), 500)),
      COALESCE(p_next_action_at, p_due_at),
      COALESCE(p_acknowledgement_required, false),
      COALESCE(p_completion_mode, 'assignee_closes'::public.work_completion_mode)
    );

    PERFORM private.work_complete_operation(
      p_operation_id,
      (v_result->>'work_item_id')::UUID,
      v_result
    );

    RETURN jsonb_build_object(
      'ok', true,
      'operation_id', p_operation_id,
      'operation', 'create_work_task_atomic',
      'replayed', false,
      'data', v_result
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'P0001' THEN
      v_safe_code := 'DOMAIN_VALIDATION_FAILED';
      v_safe_message := 'تعذر إنشاء المهمة لعدم استيفاء شروطها أو الصلاحيات المطلوبة';
    ELSE
      v_safe_code := 'INTERNAL_ERROR';
      v_safe_message := 'فشل إنشاء المهمة بسبب خطأ داخلي';
    END IF;

    PERFORM private.work_fail_operation(
      p_operation_id,
      v_safe_code,
      v_safe_message,
      'create_task',
      SQLERRM
    );

    RETURN jsonb_build_object(
      'ok', false,
      'operation_id', p_operation_id,
      'operation', 'create_work_task_atomic',
      'replayed', false,
      'error', jsonb_build_object(
        'code', v_safe_code,
        'message', v_safe_message
      )
    );
  END;
END;
$$;

REVOKE ALL ON FUNCTION private.create_work_task_atomic_impl(
  UUID, TEXT, TEXT, TEXT, public.work_priority, public.work_visibility,
  UUID, UUID, TIMESTAMPTZ, VARCHAR, TIMESTAMPTZ, BOOLEAN, public.work_completion_mode
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION private.create_work_task_atomic_impl(
  UUID, TEXT, TEXT, TEXT, public.work_priority, public.work_visibility,
  UUID, UUID, TIMESTAMPTZ, VARCHAR, TIMESTAMPTZ, BOOLEAN, public.work_completion_mode
) TO authenticated, service_role;

RESET lock_timeout;
RESET statement_timeout;
