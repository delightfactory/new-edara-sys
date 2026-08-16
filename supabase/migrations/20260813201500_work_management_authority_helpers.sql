-- Work Management — Migration C1b: private authority helpers.
SET lock_timeout = '5s';
SET statement_timeout = '60s';
CREATE SCHEMA IF NOT EXISTS private;

CREATE OR REPLACE FUNCTION private.work_actor_is_active(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT p_user_id IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = p_user_id
      AND p.status::TEXT = 'active'
  );
$$;

CREATE OR REPLACE FUNCTION private.work_user_can_assign_target(
  p_actor_user_id UUID,
  p_target_user_id UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_target_branch_id UUID;
  v_target_department_id UUID;
BEGIN
  IF NOT private.work_actor_is_active(p_actor_user_id)
     OR NOT private.work_actor_is_active(p_target_user_id) THEN
    RETURN false;
  END IF;

  IF p_actor_user_id = p_target_user_id THEN
    RETURN true;
  END IF;

  IF COALESCE(public.check_permission(p_actor_user_id, 'work.items.manage'), false) THEN
    RETURN true;
  END IF;

  SELECT e.branch_id, e.department_id
  INTO v_target_branch_id, v_target_department_id
  FROM public.hr_employees e
  WHERE e.user_id = p_target_user_id
    AND e.status::TEXT = 'active';

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF COALESCE(public.check_permission(p_actor_user_id, 'work.items.assign_branch'), false)
     AND v_target_branch_id IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM public.branches b
       WHERE b.id = v_target_branch_id
         AND b.manager_id = p_actor_user_id
         AND COALESCE(b.is_active, true)
     ) THEN
    RETURN true;
  END IF;

  IF COALESCE(public.check_permission(p_actor_user_id, 'work.items.assign'), false)
     AND COALESCE(public.check_permission(p_actor_user_id, 'work.items.manage_team'), false)
     AND private.work_user_manages_scope(
       p_actor_user_id,
       v_target_branch_id,
       v_target_department_id,
       p_target_user_id,
       p_target_user_id
     ) THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION private.work_user_can_manage_item(
  p_actor_user_id UUID,
  p_work_item_id UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_item public.work_items%ROWTYPE;
BEGIN
  IF NOT private.work_actor_is_active(p_actor_user_id) THEN
    RETURN false;
  END IF;

  SELECT * INTO v_item
  FROM public.work_items w
  WHERE w.id = p_work_item_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF COALESCE(public.check_permission(p_actor_user_id, 'work.items.manage'), false) THEN
    RETURN true;
  END IF;

  RETURN COALESCE(public.check_permission(p_actor_user_id, 'work.items.manage_team'), false)
    AND private.work_user_manages_scope(
      p_actor_user_id,
      v_item.branch_id,
      v_item.owning_department_id,
      v_item.accountable_owner_user_id,
      v_item.current_assignee_user_id
    );
END;
$$;

REVOKE ALL ON FUNCTION private.work_actor_is_active(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.work_user_can_assign_target(UUID, UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.work_user_can_manage_item(UUID, UUID)
  FROM PUBLIC, anon, authenticated, service_role;

RESET lock_timeout;
RESET statement_timeout;
