-- Work Management — acceptance hardening for browser RLS helpers and mentions.
-- This migration intentionally exposes only current-user wrappers to the browser.
SET lock_timeout='5s';
SET statement_timeout='60s';

-- RLS policies are evaluated as the authenticated caller. The caller needs schema
-- USAGE to invoke explicitly-granted safe wrappers, but receives no blanket
-- EXECUTE permission on arbitrary-user authority helpers.
GRANT USAGE ON SCHEMA private TO authenticated;

CREATE OR REPLACE FUNCTION private.work_current_user_is_queue_member(p_queue_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT private.work_user_is_queue_member(auth.uid(),p_queue_id);
$$;

CREATE OR REPLACE FUNCTION private.work_current_user_can_triage_queue(p_queue_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT private.work_user_can_triage_queue(auth.uid(),p_queue_id);
$$;

REVOKE ALL ON FUNCTION private.work_current_user_is_queue_member(UUID)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_current_user_can_triage_queue(UUID)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private.work_current_user_is_queue_member(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION private.work_current_user_can_triage_queue(UUID) TO authenticated;

DROP POLICY IF EXISTS work_queues_select_visible ON public.work_queues;
CREATE POLICY work_queues_select_visible
ON public.work_queues FOR SELECT TO authenticated
USING (
  COALESCE(public.check_permission(auth.uid(),'work.queues.manage'),false)
  OR (
    is_active=true AND (
      COALESCE(public.check_permission(auth.uid(),'work.requests.create'),false)
      OR manager_user_id=auth.uid()
      OR private.work_current_user_is_queue_member(id)
    )
  )
);

DROP POLICY IF EXISTS work_queue_members_select_visible ON public.work_queue_members;
CREATE POLICY work_queue_members_select_visible
ON public.work_queue_members FOR SELECT TO authenticated
USING (
  user_id=auth.uid()
  OR private.work_current_user_can_triage_queue(queue_id)
  OR COALESCE(public.check_permission(auth.uid(),'work.queues.manage'),false)
);

DROP POLICY IF EXISTS work_request_types_select_visible ON public.work_request_types;
CREATE POLICY work_request_types_select_visible
ON public.work_request_types FOR SELECT TO authenticated
USING (
  (is_active=true AND COALESCE(public.check_permission(auth.uid(),'work.requests.create'),false))
  OR private.work_current_user_can_triage_queue(target_queue_id)
  OR COALESCE(public.check_permission(auth.uid(),'work.queues.manage'),false)
);

-- Secure mention directory. It reveals only active users who can already see the
-- same Work Item, and only to a caller who is allowed to comment on that item.
CREATE OR REPLACE FUNCTION public.work_list_mention_candidates(
  p_work_item_id UUID,
  p_search TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 20
) RETURNS TABLE(
  user_id UUID,
  full_name TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_item public.work_items%ROWTYPE;
  v_search TEXT:=NULLIF(btrim(COALESCE(p_search,'')),'');
  v_limit INTEGER:=LEAST(GREATEST(COALESCE(p_limit,20),1),50);
BEGIN
  IF v_actor IS NULL OR NOT private.work_actor_is_active(v_actor) THEN RETURN; END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id;
  IF NOT FOUND OR NOT private.work_actor_can_comment_item(v_actor,p_work_item_id) THEN RETURN; END IF;

  RETURN QUERY
  SELECT p.id,p.full_name
  FROM public.profiles p
  WHERE p.id<>v_actor
    AND p.full_name IS NOT NULL
    AND btrim(p.full_name)<>''
    AND private.work_actor_is_active(p.id)
    AND private.work_user_can_view_row(
      p.id,v_item.id,v_item.visibility,v_item.creator_user_id,v_item.requester_user_id,
      v_item.accountable_owner_user_id,v_item.current_assignee_user_id,
      v_item.branch_id,v_item.owning_department_id
    )
    AND (v_search IS NULL OR p.full_name ILIKE '%'||v_search||'%')
  ORDER BY p.full_name,p.id
  LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.work_list_mention_candidates(UUID,TEXT,INTEGER)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.work_list_mention_candidates(UUID,TEXT,INTEGER)
  TO authenticated;

RESET lock_timeout;
RESET statement_timeout;
