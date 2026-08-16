-- Work Management — supervisor overview return-type compatibility fix.
-- Keeps the existing authorization/read model unchanged and makes the SELECT
-- row types exactly match RETURNS TABLE across PostgreSQL environments.
SET lock_timeout='5s';
SET statement_timeout='60s';

CREATE OR REPLACE FUNCTION public.work_get_supervisor_overview(
  p_assignee_user_id UUID DEFAULT NULL,
  p_attention_only BOOLEAN DEFAULT false,
  p_limit INTEGER DEFAULT 300
) RETURNS TABLE(
  work_item_id UUID,
  work_number BIGINT,
  title TEXT,
  status TEXT,
  priority TEXT,
  visibility TEXT,
  accountable_owner_user_id UUID,
  owner_name TEXT,
  current_assignee_user_id UUID,
  assignee_name TEXT,
  branch_id UUID,
  owning_department_id UUID,
  due_at TIMESTAMPTZ,
  next_action_text TEXT,
  next_action_at TIMESTAMPTZ,
  waiting_reason TEXT,
  state_version BIGINT,
  is_blocked BOOLEAN,
  is_overdue BOOLEAN,
  is_stale BOOLEAN,
  is_at_risk BOOLEAN,
  is_escalated BOOLEAN,
  is_due_soon BOOLEAN,
  is_follow_up_due BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_limit INTEGER:=LEAST(GREATEST(COALESCE(p_limit,300),1),500);
BEGIN
  IF NOT private.work_actor_is_active(v_actor) THEN RETURN; END IF;
  IF NOT (
    COALESCE(public.check_permission(v_actor,'work.items.read_team'),false)
    OR COALESCE(public.check_permission(v_actor,'work.items.read_all'),false)
    OR COALESCE(public.check_permission(v_actor,'work.items.manage_team'),false)
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    w.id,
    w.work_number,
    w.title::TEXT,
    w.status::TEXT,
    w.priority::TEXT,
    w.visibility::TEXT,
    w.accountable_owner_user_id,
    owner.full_name::TEXT,
    w.current_assignee_user_id,
    assignee.full_name::TEXT,
    w.branch_id,
    w.owning_department_id,
    w.due_at,
    w.next_action_text::TEXT,
    w.next_action_at,
    w.waiting_reason::TEXT,
    w.state_version,
    COALESCE(f.is_blocked,false),
    COALESCE(f.is_overdue,false),
    COALESCE(f.is_stale,false),
    COALESCE(f.is_at_risk,false),
    COALESCE(f.is_escalated,false),
    COALESCE(f.is_due_soon,false),
    COALESCE(f.is_follow_up_due,false)
  FROM public.work_items w
  LEFT JOIN public.work_operational_flags f ON f.work_item_id=w.id
  LEFT JOIN public.profiles owner ON owner.id=w.accountable_owner_user_id
  LEFT JOIN public.profiles assignee ON assignee.id=w.current_assignee_user_id
  WHERE w.status IN ('open','in_progress','waiting','pending_approval')
    AND (p_assignee_user_id IS NULL OR w.current_assignee_user_id=p_assignee_user_id)
    AND private.work_user_can_view_row(
      v_actor,w.id,w.visibility,w.creator_user_id,w.requester_user_id,
      w.accountable_owner_user_id,w.current_assignee_user_id,w.branch_id,w.owning_department_id
    )
    AND (
      NOT COALESCE(p_attention_only,false)
      OR COALESCE(f.is_blocked,false)
      OR COALESCE(f.is_overdue,false)
      OR COALESCE(f.is_stale,false)
      OR COALESCE(f.is_at_risk,false)
      OR COALESCE(f.is_escalated,false)
      OR COALESCE(f.is_follow_up_due,false)
    )
  ORDER BY
    COALESCE(f.is_overdue,false) DESC,
    COALESCE(f.is_blocked,false) DESC,
    COALESCE(f.is_at_risk,false) DESC,
    COALESCE(f.is_follow_up_due,false) DESC,
    w.due_at ASC NULLS LAST,
    w.priority DESC,
    w.work_number DESC
  LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.work_get_supervisor_overview(UUID,BOOLEAN,INTEGER)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.work_get_supervisor_overview(UUID,BOOLEAN,INTEGER)
  TO authenticated;

RESET lock_timeout;
RESET statement_timeout;
