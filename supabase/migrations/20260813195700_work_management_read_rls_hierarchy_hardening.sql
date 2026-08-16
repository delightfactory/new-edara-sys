-- ============================================================================
-- Work Management — Migration B3: hierarchy hardening for team visibility.
-- Keeps historical/inactive assignees visible to their current active managers,
-- but never treats an inactive employee record as an active manager.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION private.work_user_manages_scope(
  p_user_id UUID,
  p_branch_id UUID,
  p_owning_department_id UUID,
  p_accountable_owner_user_id UUID,
  p_current_assignee_user_id UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RETURN false;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = p_user_id
      AND p.status::TEXT = 'active'
  ) THEN
    RETURN false;
  END IF;

  IF p_branch_id IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.branches b
    WHERE b.id = p_branch_id
      AND b.manager_id = p_user_id
      AND COALESCE(b.is_active, true)
  ) THEN
    RETURN true;
  END IF;

  IF p_owning_department_id IS NOT NULL AND EXISTS (
    WITH RECURSIVE department_chain AS (
      SELECT
        d.id,
        d.parent_id,
        d.manager_id,
        ARRAY[d.id]::UUID[] AS path
      FROM public.hr_departments d
      WHERE d.id = p_owning_department_id
        AND d.is_active = true

      UNION ALL

      SELECT
        parent.id,
        parent.parent_id,
        parent.manager_id,
        dc.path || parent.id
      FROM public.hr_departments parent
      JOIN department_chain dc ON parent.id = dc.parent_id
      WHERE parent.is_active = true
        AND NOT parent.id = ANY(dc.path)
    )
    SELECT 1
    FROM department_chain dc
    JOIN public.profiles manager_profile ON manager_profile.id = dc.manager_id
    WHERE dc.manager_id = p_user_id
      AND manager_profile.status::TEXT = 'active'
  ) THEN
    RETURN true;
  END IF;

  IF EXISTS (
    WITH RECURSIVE manager_chain AS (
      -- The target employee may be inactive; historical/orphaned work must stay
      -- visible to the valid managers above that employee.
      SELECT
        e.id,
        e.user_id,
        e.direct_manager_id,
        0 AS depth,
        ARRAY[e.id]::UUID[] AS path
      FROM public.hr_employees e
      WHERE e.user_id IN (
        p_accountable_owner_user_id,
        p_current_assignee_user_id
      )

      UNION ALL

      SELECT
        manager.id,
        manager.user_id,
        manager.direct_manager_id,
        mc.depth + 1,
        mc.path || manager.id
      FROM public.hr_employees manager
      JOIN manager_chain mc ON manager.id = mc.direct_manager_id
      WHERE manager.status::TEXT = 'active'
        AND NOT manager.id = ANY(mc.path)
    )
    SELECT 1
    FROM manager_chain mc
    JOIN public.profiles manager_profile ON manager_profile.id = mc.user_id
    WHERE mc.depth > 0
      AND mc.user_id = p_user_id
      AND manager_profile.status::TEXT = 'active'
  ) THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

REVOKE ALL ON FUNCTION private.work_user_manages_scope(
  UUID, UUID, UUID, UUID, UUID
) FROM PUBLIC, anon, authenticated, service_role;

RESET lock_timeout;
RESET statement_timeout;
