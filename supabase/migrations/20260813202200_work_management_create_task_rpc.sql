-- Work Management — Migration C2c: public Create Task RPC wrapper.
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION public.create_work_task_atomic(
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
  p_completion_mode public.work_completion_mode DEFAULT 'assignee_closes'
) RETURNS JSONB
LANGUAGE sql
SET search_path = 'pg_catalog'
AS $$
  SELECT private.create_work_task_atomic_impl(
    p_operation_id,
    p_title,
    p_description,
    p_expected_outcome,
    p_priority,
    p_visibility,
    p_owner_user_id,
    p_assignee_user_id,
    p_due_at,
    p_next_action_text,
    p_next_action_at,
    p_acknowledgement_required,
    p_completion_mode
  );
$$;

REVOKE ALL ON FUNCTION public.create_work_task_atomic(
  UUID, TEXT, TEXT, TEXT, public.work_priority, public.work_visibility,
  UUID, UUID, TIMESTAMPTZ, VARCHAR, TIMESTAMPTZ, BOOLEAN, public.work_completion_mode
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_work_task_atomic(
  UUID, TEXT, TEXT, TEXT, public.work_priority, public.work_visibility,
  UUID, UUID, TIMESTAMPTZ, VARCHAR, TIMESTAMPTZ, BOOLEAN, public.work_completion_mode
) TO authenticated, service_role;

RESET lock_timeout;
RESET statement_timeout;
