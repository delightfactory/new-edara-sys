-- Work Management — blocked flag hardening.
-- A user may be allowed to see a Work Item but not the blocker details. The UI must
-- still know that completion is blocked, without exposing the hidden blocker identity.
SET lock_timeout='5s';
SET statement_timeout='60s';

CREATE OR REPLACE FUNCTION private.work_item_has_open_blocker(p_work_item_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT
    EXISTS(
      SELECT 1
      FROM public.work_dependencies d
      JOIN public.work_items blocker ON blocker.id=d.blocker_work_item_id
      WHERE d.blocked_work_item_id=p_work_item_id
        AND d.resolved_at IS NULL
        AND d.dependency_strength='hard'
        AND blocker.status<>'done'
    )
    OR EXISTS(
      SELECT 1
      FROM public.work_items child
      WHERE child.parent_work_item_id=p_work_item_id
        AND child.blocks_parent_completion=true
        AND child.status NOT IN ('done','cancelled')
    );
$$;
REVOKE ALL ON FUNCTION private.work_item_has_open_blocker(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.work_operational_item_is_blocked(p_work_item_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT CASE
    -- pg_cron / trusted internal processors have no auth JWT and may evaluate all rows.
    WHEN auth.uid() IS NULL THEN private.work_item_has_open_blocker(p_work_item_id)
    -- Browser callers receive only the boolean for Work they are already allowed to see.
    WHEN private.work_current_user_can_view_item(p_work_item_id)
      THEN private.work_item_has_open_blocker(p_work_item_id)
    ELSE false
  END;
$$;
REVOKE ALL ON FUNCTION private.work_operational_item_is_blocked(UUID)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private.work_operational_item_is_blocked(UUID) TO authenticated;

CREATE OR REPLACE VIEW public.work_operational_flags
WITH (security_invoker=true)
AS
WITH settings AS (
  SELECT * FROM public.work_operational_settings WHERE singleton=true
), base AS (
  SELECT
    w.*,
    s.due_soon_hours,
    s.stale_after_hours,
    (w.status IN ('open','in_progress','waiting','pending_approval')) AS is_active,
    private.work_operational_item_is_blocked(w.id) AS is_blocked,
    EXISTS(
      SELECT 1 FROM public.work_escalations e
      WHERE e.work_item_id=w.id AND e.resolved_at IS NULL
    ) AS is_escalated
  FROM public.work_items w
  CROSS JOIN settings s
)
SELECT
  b.id AS work_item_id,
  b.work_number,
  b.status,
  b.priority,
  b.visibility,
  b.current_assignee_user_id,
  b.accountable_owner_user_id,
  b.due_at,
  b.next_action_at,
  b.last_meaningful_activity_at,
  b.is_blocked,
  (b.is_active AND b.due_at IS NOT NULL AND b.due_at<clock_timestamp()) AS is_overdue,
  (
    b.status IN ('open','in_progress','pending_approval')
    AND COALESCE(b.last_meaningful_activity_at,b.activated_at,b.created_at)
        < clock_timestamp()-make_interval(hours=>b.stale_after_hours)
  ) AS is_stale,
  b.is_escalated,
  (
    b.is_active AND b.due_at IS NOT NULL
    AND b.due_at>=clock_timestamp()
    AND b.due_at<=clock_timestamp()+make_interval(hours=>b.due_soon_hours)
  ) AS is_due_soon,
  (
    b.status='waiting' AND b.next_action_at IS NOT NULL AND b.next_action_at<=clock_timestamp()
  ) AS is_follow_up_due,
  (
    b.is_active
    AND NOT (b.due_at IS NOT NULL AND b.due_at<clock_timestamp())
    AND (
      (b.due_at IS NOT NULL
       AND b.due_at<=clock_timestamp()+make_interval(hours=>b.due_soon_hours)
       AND (b.is_blocked OR (
         b.status IN ('open','in_progress','pending_approval')
         AND COALESCE(b.last_meaningful_activity_at,b.activated_at,b.created_at)
             < clock_timestamp()-make_interval(hours=>b.stale_after_hours)
       )))
      OR (b.status='waiting' AND b.next_action_at IS NOT NULL AND b.next_action_at<=clock_timestamp())
    )
  ) AS is_at_risk
FROM base b;

GRANT SELECT ON public.work_operational_flags TO authenticated;

RESET lock_timeout;
RESET statement_timeout;