-- Work Management — secure user directory for configuration builders.
-- Configuration managers need human-readable selectors without direct profile-directory access.
SET lock_timeout='5s';
SET statement_timeout='60s';

CREATE OR REPLACE FUNCTION public.work_list_management_users(
  p_search TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 100
) RETURNS TABLE(
  user_id UUID,
  full_name TEXT,
  branch_id UUID,
  department_id UUID,
  is_self BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_limit INTEGER:=LEAST(GREATEST(COALESCE(p_limit,100),1),200);
  v_search TEXT:=NULLIF(btrim(COALESCE(p_search,'')),'');
  v_allowed BOOLEAN;
BEGIN
  v_allowed:=private.work_actor_is_active(v_actor) AND (
    COALESCE(public.check_permission(v_actor,'work.queues.manage'),false)
    OR COALESCE(public.check_permission(v_actor,'work.templates.manage'),false)
    OR COALESCE(public.check_permission(v_actor,'work.workflows.manage'),false)
    OR COALESCE(public.check_permission(v_actor,'work.recurrence.manage'),false)
  );
  IF NOT v_allowed THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.full_name,
    e.branch_id,
    e.department_id,
    p.id=v_actor
  FROM public.profiles p
  LEFT JOIN public.hr_employees e
    ON e.user_id=p.id AND e.status::TEXT='active'
  WHERE p.status::TEXT='active'
    AND p.full_name IS NOT NULL
    AND btrim(p.full_name)<>''
    AND (v_search IS NULL OR p.full_name ILIKE '%'||v_search||'%')
  ORDER BY (p.id=v_actor) DESC,p.full_name,p.id
  LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.work_list_management_users(TEXT,INTEGER)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.work_list_management_users(TEXT,INTEGER)
  TO authenticated;

RESET lock_timeout;
RESET statement_timeout;
