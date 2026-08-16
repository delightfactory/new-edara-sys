-- ============================================================================
-- Work Management — Migration B2: Read RLS
-- Read-only browser visibility; all Work mutations remain closed until RPCs.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE SCHEMA IF NOT EXISTS private;

-- --------------------------------------------------------------------------
-- Internal visibility helpers.
--
-- The p_user_id variants are private implementation details and are not
-- executable by browser roles. Public RLS paths use current-user wrappers that
-- derive identity exclusively from auth.uid().
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.work_user_has_direct_access(
  p_user_id UUID,
  p_work_item_id UUID,
  p_creator_user_id UUID,
  p_requester_user_id UUID,
  p_accountable_owner_user_id UUID,
  p_current_assignee_user_id UUID
) RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    p_user_id IS NOT NULL
    AND (
      p_user_id = p_creator_user_id
      OR p_user_id = p_requester_user_id
      OR p_user_id = p_accountable_owner_user_id
      OR p_user_id = p_current_assignee_user_id
      OR EXISTS (
        SELECT 1
        FROM public.work_participants wp
        WHERE wp.work_item_id = p_work_item_id
          AND wp.user_id = p_user_id
          AND wp.removed_at IS NULL
      )
    );
$$;

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
    WHERE dc.manager_id = p_user_id
  ) THEN
    RETURN true;
  END IF;

  IF EXISTS (
    WITH RECURSIVE manager_chain AS (
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
      WHERE NOT manager.id = ANY(mc.path)
    )
    SELECT 1
    FROM manager_chain mc
    WHERE mc.depth > 0
      AND mc.user_id = p_user_id
  ) THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION private.work_user_can_view_row(
  p_user_id UUID,
  p_work_item_id UUID,
  p_visibility public.work_visibility,
  p_creator_user_id UUID,
  p_requester_user_id UUID,
  p_accountable_owner_user_id UUID,
  p_current_assignee_user_id UUID,
  p_branch_id UUID,
  p_owning_department_id UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_direct BOOLEAN;
  v_team BOOLEAN := false;
  v_read_own BOOLEAN;
  v_read_team BOOLEAN;
  v_read_all BOOLEAN;
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

  v_direct := private.work_user_has_direct_access(
    p_user_id,
    p_work_item_id,
    p_creator_user_id,
    p_requester_user_id,
    p_accountable_owner_user_id,
    p_current_assignee_user_id
  );

  v_read_own := COALESCE(
    public.check_permission(p_user_id, 'work.items.read_own'),
    false
  );

  IF v_direct AND v_read_own THEN
    RETURN true;
  END IF;

  v_read_all := COALESCE(
    public.check_permission(p_user_id, 'work.items.read_all'),
    false
  );

  IF p_visibility = 'private'::public.work_visibility THEN
    RETURN v_read_all
      AND COALESCE(
        public.check_permission(p_user_id, 'work.items.read_private'),
        false
      );
  END IF;

  v_read_team := COALESCE(
    public.check_permission(p_user_id, 'work.items.read_team'),
    false
  );

  IF v_read_team THEN
    v_team := private.work_user_manages_scope(
      p_user_id,
      p_branch_id,
      p_owning_department_id,
      p_accountable_owner_user_id,
      p_current_assignee_user_id
    );
  END IF;

  IF p_visibility = 'restricted'::public.work_visibility THEN
    IF NOT COALESCE(
      public.check_permission(p_user_id, 'work.items.read_restricted'),
      false
    ) THEN
      RETURN false;
    END IF;

    RETURN v_read_all OR v_team;
  END IF;

  RETURN v_read_all OR v_team;
END;
$$;

CREATE OR REPLACE FUNCTION private.work_current_user_can_view_row(
  p_work_item_id UUID,
  p_visibility public.work_visibility,
  p_creator_user_id UUID,
  p_requester_user_id UUID,
  p_accountable_owner_user_id UUID,
  p_current_assignee_user_id UUID,
  p_branch_id UUID,
  p_owning_department_id UUID
) RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.work_user_can_view_row(
    auth.uid(),
    p_work_item_id,
    p_visibility,
    p_creator_user_id,
    p_requester_user_id,
    p_accountable_owner_user_id,
    p_current_assignee_user_id,
    p_branch_id,
    p_owning_department_id
  );
$$;

CREATE OR REPLACE FUNCTION private.work_current_user_can_view_item(
  p_work_item_id UUID
) RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE((
    SELECT private.work_user_can_view_row(
      auth.uid(),
      w.id,
      w.visibility,
      w.creator_user_id,
      w.requester_user_id,
      w.accountable_owner_user_id,
      w.current_assignee_user_id,
      w.branch_id,
      w.owning_department_id
    )
    FROM public.work_items w
    WHERE w.id = p_work_item_id
  ), false);
$$;

REVOKE ALL ON FUNCTION private.work_user_has_direct_access(
  UUID, UUID, UUID, UUID, UUID, UUID
) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION private.work_user_manages_scope(
  UUID, UUID, UUID, UUID, UUID
) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION private.work_user_can_view_row(
  UUID, UUID, public.work_visibility, UUID, UUID, UUID, UUID, UUID, UUID
) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION private.work_current_user_can_view_row(
  UUID, public.work_visibility, UUID, UUID, UUID, UUID, UUID, UUID
) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION private.work_current_user_can_view_item(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION private.work_current_user_can_view_row(
  UUID, public.work_visibility, UUID, UUID, UUID, UUID, UUID, UUID
) TO authenticated;

GRANT EXECUTE ON FUNCTION private.work_current_user_can_view_item(UUID)
  TO authenticated;

GRANT SELECT ON TABLE public.work_items TO authenticated;
GRANT SELECT ON TABLE public.work_participants TO authenticated;
GRANT SELECT ON TABLE public.work_comments TO authenticated;
GRANT SELECT ON TABLE public.work_mentions TO authenticated;
GRANT SELECT ON TABLE public.work_events TO authenticated;
GRANT SELECT ON TABLE public.work_checklist_items TO authenticated;
GRANT SELECT ON TABLE public.work_dependencies TO authenticated;
GRANT SELECT ON TABLE public.work_links TO authenticated;
GRANT SELECT ON TABLE public.work_attachments TO authenticated;

CREATE POLICY work_items_select_visible
  ON public.work_items
  FOR SELECT
  TO authenticated
  USING (
    private.work_current_user_can_view_row(
      id,
      visibility,
      creator_user_id,
      requester_user_id,
      accountable_owner_user_id,
      current_assignee_user_id,
      branch_id,
      owning_department_id
    )
  );

CREATE POLICY work_participants_select_visible
  ON public.work_participants
  FOR SELECT
  TO authenticated
  USING (private.work_current_user_can_view_item(work_item_id));

CREATE POLICY work_comments_select_visible
  ON public.work_comments
  FOR SELECT
  TO authenticated
  USING (private.work_current_user_can_view_item(work_item_id));

CREATE POLICY work_mentions_select_visible
  ON public.work_mentions
  FOR SELECT
  TO authenticated
  USING (private.work_current_user_can_view_item(work_item_id));

CREATE POLICY work_events_select_visible
  ON public.work_events
  FOR SELECT
  TO authenticated
  USING (private.work_current_user_can_view_item(work_item_id));

CREATE POLICY work_checklist_items_select_visible
  ON public.work_checklist_items
  FOR SELECT
  TO authenticated
  USING (private.work_current_user_can_view_item(work_item_id));

CREATE POLICY work_dependencies_select_visible
  ON public.work_dependencies
  FOR SELECT
  TO authenticated
  USING (
    private.work_current_user_can_view_item(blocked_work_item_id)
    AND private.work_current_user_can_view_item(blocker_work_item_id)
  );

CREATE POLICY work_links_select_visible
  ON public.work_links
  FOR SELECT
  TO authenticated
  USING (private.work_current_user_can_view_item(work_item_id));

CREATE POLICY work_attachments_select_visible
  ON public.work_attachments
  FOR SELECT
  TO authenticated
  USING (private.work_current_user_can_view_item(work_item_id));

RESET lock_timeout;
RESET statement_timeout;
