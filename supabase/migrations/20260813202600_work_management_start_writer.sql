-- Work Management — Migration C5a: internal Start writer.
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION private.work_apply_start(
  p_operation_id UUID,
  p_actor_user_id UUID,
  p_work_item_id UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_item public.work_items%ROWTYPE;
BEGIN
  UPDATE public.work_items
  SET status = 'in_progress'::public.work_item_status,
      started_at = COALESCE(started_at, clock_timestamp()),
      first_viewed_at = CASE WHEN p_actor_user_id = current_assignee_user_id THEN COALESCE(first_viewed_at, clock_timestamp()) ELSE first_viewed_at END,
      acknowledged_at = CASE WHEN p_actor_user_id = current_assignee_user_id THEN COALESCE(acknowledged_at, clock_timestamp()) ELSE acknowledged_at END,
      last_meaningful_activity_at = clock_timestamp(),
      state_version = state_version + 1
  WHERE id = p_work_item_id
  RETURNING * INTO v_item;

  INSERT INTO public.work_events(work_item_id, event_type, actor_user_id, actor_kind, from_status, to_status, operation_id, payload, created_at)
  VALUES(v_item.id, 'work.started', p_actor_user_id, 'user'::public.work_actor_kind,
    'open'::public.work_item_status, 'in_progress'::public.work_item_status,
    p_operation_id, jsonb_build_object('current_assignee_user_id', v_item.current_assignee_user_id), clock_timestamp());

  RETURN jsonb_build_object('work_item_id', v_item.id, 'status', v_item.status, 'state_version', v_item.state_version,
    'started_at', v_item.started_at, 'acknowledged_at', v_item.acknowledged_at);
END;
$$;

REVOKE ALL ON FUNCTION private.work_apply_start(UUID, UUID, UUID) FROM PUBLIC, anon, authenticated, service_role;
RESET lock_timeout;
RESET statement_timeout;
