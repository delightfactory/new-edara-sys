-- Work Management — expose only a current-user active check to RLS.
SET lock_timeout='5s';
SET statement_timeout='60s';

CREATE OR REPLACE FUNCTION private.work_current_user_is_active()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT private.work_actor_is_active(auth.uid());
$$;
REVOKE ALL ON FUNCTION private.work_current_user_is_active()
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private.work_current_user_is_active() TO authenticated;

DROP POLICY IF EXISTS work_operational_settings_select ON public.work_operational_settings;
CREATE POLICY work_operational_settings_select
ON public.work_operational_settings FOR SELECT TO authenticated
USING (private.work_current_user_is_active());

RESET lock_timeout;
RESET statement_timeout;