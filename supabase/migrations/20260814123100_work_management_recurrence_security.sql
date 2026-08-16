-- Work Management — recurrence visibility hardening and explicit permission.
SET lock_timeout='5s';
SET statement_timeout='60s';

WITH permission_matrix(role_name,permission) AS (
  VALUES
    ('sales_supervisor','work.recurrence.manage'),
    ('hr_manager','work.recurrence.manage'),
    ('branch_manager','work.recurrence.manage'),
    ('ceo','work.recurrence.manage')
)
INSERT INTO public.role_permissions(role_id,permission)
SELECT r.id,p.permission
FROM permission_matrix p
JOIN public.roles r ON r.name=p.role_name
ON CONFLICT (role_id,permission) DO NOTHING;

CREATE OR REPLACE FUNCTION private.work_user_can_view_recurrence_definition(
  p_user_id UUID,
  p_definition_id UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_definition public.work_recurrence_definitions%ROWTYPE;
BEGIN
  IF NOT private.work_actor_is_active(p_user_id) THEN RETURN false; END IF;
  IF COALESCE(public.check_permission(p_user_id,'work.policies.manage'),false)
     OR COALESCE(public.check_permission(p_user_id,'work.recurrence.manage'),false) THEN
    RETURN true;
  END IF;

  SELECT * INTO v_definition
  FROM public.work_recurrence_definitions
  WHERE id=p_definition_id;
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_definition.created_by_user_id=p_user_id THEN RETURN true; END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.work_recurrence_occurrences o
    LEFT JOIN public.work_items w ON w.id=COALESCE(o.work_item_id,o.overlap_work_item_id)
    WHERE o.recurrence_definition_id=p_definition_id
      AND w.id IS NOT NULL
      AND private.work_user_can_view_row(
        p_user_id,w.id,w.visibility,w.creator_user_id,w.requester_user_id,
        w.accountable_owner_user_id,w.current_assignee_user_id,w.branch_id,w.owning_department_id
      )
  ) OR EXISTS (
    SELECT 1
    FROM public.work_recurrence_occurrences o
    WHERE o.recurrence_definition_id=p_definition_id
      AND COALESCE(o.workflow_run_id,o.overlap_workflow_run_id) IS NOT NULL
      AND private.work_user_can_view_workflow_run(
        p_user_id,COALESCE(o.workflow_run_id,o.overlap_workflow_run_id)
      )
  );
END;
$$;

DROP POLICY IF EXISTS work_recurrence_definitions_select ON public.work_recurrence_definitions;
DROP POLICY IF EXISTS work_recurrence_occurrences_select ON public.work_recurrence_occurrences;

CREATE POLICY work_recurrence_definitions_select
ON public.work_recurrence_definitions FOR SELECT TO authenticated
USING (private.work_user_can_view_recurrence_definition(auth.uid(),id));

CREATE POLICY work_recurrence_occurrences_select
ON public.work_recurrence_occurrences FOR SELECT TO authenticated
USING (private.work_user_can_view_recurrence_definition(auth.uid(),recurrence_definition_id));

REVOKE ALL ON FUNCTION private.work_user_can_view_recurrence_definition(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;

RESET lock_timeout;
RESET statement_timeout;
