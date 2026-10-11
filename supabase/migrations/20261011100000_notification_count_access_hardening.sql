-- Count only the caller's notifications; trusted server callers retain their scope.
BEGIN;

CREATE OR REPLACE FUNCTION public.get_unread_notifications_count(
  p_user_id uuid DEFAULT auth.uid()
)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COUNT(*)::integer
  FROM public.notifications
  WHERE user_id = p_user_id
    AND is_read = false
    AND is_archived = false
    AND (expires_at IS NULL OR expires_at > now())
    AND (
      auth.role() = 'service_role'
      OR (auth.uid() IS NOT NULL AND p_user_id = auth.uid())
    );
$$;

REVOKE EXECUTE ON FUNCTION public.get_unread_notifications_count(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_unread_notifications_count(uuid) TO authenticated, service_role;

COMMIT;
