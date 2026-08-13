-- Work Management — Migration C6a: internal Waiting writer.
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION private.work_apply_waiting(
  p_operation_id UUID,
  p_actor_user_id UUID,
  p_work_item_id UUID,
  p_waiting_on_type TEXT,
  p_waiting_on_user_id UUID,
  p_waiting_on_label VARCHAR(250),
  p_waiting_on_entity_type TEXT,
  p_waiting_on_entity_id UUID,
  p_waiting_reason TEXT,
  p_next_action_text VARCHAR(500),
  p_next_action_at TIMESTAMPTZ
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_from_status public.work_item_status;
  v_item public.work_items%ROWTYPE;
BEGIN
  SELECT status INTO v_from_status FROM public.work_items WHERE id = p_work_item_id;

  UPDATE public.work_items
  SET status = 'waiting'::public.work_item_status,
      waiting_on_type = p_waiting_on_type,
      waiting_on_user_id = p_waiting_on_user_id,
      waiting_on_label = p_waiting_on_label,
      waiting_on_entity_type = p_waiting_on_entity_type,
      waiting_on_entity_id = p_waiting_on_entity_id,
      waiting_reason = p_waiting_reason,
      waiting_since = clock_timestamp(),
      next_action_text = p_next_action_text,
      next_action_at = p_next_action_at,
      last_meaningful_activity_at = clock_timestamp(),
      state_version = state_version + 1
  WHERE id = p_work_item_id
  RETURNING * INTO v_item;

  INSERT INTO public.work_events(work_item_id, event_type, actor_user_id, actor_kind, from_status, to_status, operation_id, payload, created_at)
  VALUES(v_item.id, 'work.waiting_set', p_actor_user_id, 'user'::public.work_actor_kind, v_from_status, 'waiting'::public.work_item_status,
    p_operation_id, jsonb_build_object('waiting_on_type', p_waiting_on_type, 'waiting_on_user_id', p_waiting_on_user_id,
      'waiting_on_label', p_waiting_on_label, 'waiting_reason', p_waiting_reason, 'next_action_at', p_next_action_at), clock_timestamp());

  RETURN jsonb_build_object('work_item_id', v_item.id, 'status', v_item.status, 'state_version', v_item.state_version,
    'waiting_since', v_item.waiting_since, 'next_action_at', v_item.next_action_at, 'due_at', v_item.due_at);
END;
$$;

REVOKE ALL ON FUNCTION private.work_apply_waiting(UUID, UUID, UUID, TEXT, UUID, VARCHAR, TEXT, UUID, TEXT, VARCHAR, TIMESTAMPTZ)
  FROM PUBLIC, anon, authenticated, service_role;
RESET lock_timeout;
RESET statement_timeout;
