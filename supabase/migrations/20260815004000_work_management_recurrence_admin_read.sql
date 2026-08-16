-- Work Management: secure recurrence-management read surface.
-- Keep the backing table closed to browser SELECT and expose only a
-- current-actor, permission-gated management RPC.

CREATE OR REPLACE FUNCTION public.work_list_recurrence_definitions_admin()
RETURNS SETOF public.work_recurrence_definitions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $$
DECLARE
  v_actor UUID := auth.uid();
BEGIN
  IF v_actor IS NULL OR NOT private.work_actor_is_active(v_actor) THEN
    RAISE EXCEPTION 'المستخدم غير متاح لتنفيذ عمليات إدارة العمل'
      USING ERRCODE = '42501';
  END IF;

  IF NOT public.check_permission(v_actor, 'work.recurrence.manage') THEN
    RAISE EXCEPTION 'لا تملك صلاحية إدارة الأعمال الدورية'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT definition.*
  FROM public.work_recurrence_definitions definition
  ORDER BY definition.status ASC,
           definition.next_occurrence_at ASC NULLS LAST,
           definition.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.work_list_recurrence_definitions_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.work_list_recurrence_definitions_admin() FROM anon;
GRANT EXECUTE ON FUNCTION public.work_list_recurrence_definitions_admin() TO authenticated;

COMMENT ON FUNCTION public.work_list_recurrence_definitions_admin() IS
  'Permission-gated recurrence definition listing for the Work Management administration UI.';
