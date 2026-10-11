BEGIN;

-- A previously issued session must lose permission-gated capabilities when
-- its profile is disabled. Keep individual override precedence unchanged.
CREATE OR REPLACE FUNCTION public.check_permission(
  p_user_id UUID, p_permission TEXT
) RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = p_user_id AND p.status = 'active'
  ) AND COALESCE(
    (
      SELECT upo.granted
      FROM public.user_permission_overrides upo
      WHERE upo.user_id = p_user_id
        AND upo.permission = p_permission
        AND (upo.expires_at IS NULL OR upo.expires_at > now())
      LIMIT 1
    ),
    EXISTS (
      SELECT 1
      FROM public.user_roles ur
      JOIN public.role_permissions rp ON rp.role_id = ur.role_id
      WHERE ur.user_id = p_user_id
        AND ur.is_active = true
        AND (rp.permission = p_permission OR rp.permission = '*')
    )
  )
$$;

COMMIT;
