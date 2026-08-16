-- Work Management — item people directory and participant snapshot for complete detail UX.
SET lock_timeout='5s';
SET statement_timeout='60s';

CREATE OR REPLACE FUNCTION public.work_list_item_people_candidates(
  p_work_item_id UUID,
  p_purpose TEXT DEFAULT 'participant',
  p_search TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 50
) RETURNS TABLE(user_id UUID,full_name TEXT,branch_id UUID,department_id UUID,is_self BOOLEAN)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_item public.work_items%ROWTYPE;
  v_purpose TEXT:=lower(trim(COALESCE(p_purpose,'participant')));
  v_search TEXT:=NULLIF(trim(COALESCE(p_search,'')),'');
  v_limit INTEGER:=LEAST(GREATEST(COALESCE(p_limit,50),1),100);
BEGIN
  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id;
  IF NOT FOUND OR NOT private.work_actor_is_active(v_actor) OR NOT private.work_actor_can_update_item(v_actor,p_work_item_id) THEN RETURN; END IF;
  IF v_purpose='delegate' AND NOT COALESCE(public.check_permission(v_actor,'work.items.delegate'),false) THEN RETURN; END IF;
  IF v_purpose='transfer_owner' AND NOT COALESCE(public.check_permission(v_actor,'work.items.transfer_ownership'),false) THEN RETURN; END IF;
  IF v_purpose NOT IN ('participant','delegate','transfer_owner') THEN RETURN; END IF;

  RETURN QUERY
  SELECT p.id,p.full_name,e.branch_id,e.department_id,p.id=v_actor
  FROM public.profiles p
  LEFT JOIN public.hr_employees e ON e.user_id=p.id AND e.status::TEXT='active'
  WHERE p.status::TEXT='active'
    AND p.full_name IS NOT NULL AND trim(p.full_name)<>''
    AND (v_search IS NULL OR p.full_name ILIKE '%'||v_search||'%')
    AND private.work_user_can_assign_target(v_actor,p.id)
  ORDER BY (p.id=v_actor) DESC,p.full_name,p.id
  LIMIT v_limit;
END;
$$;

CREATE OR REPLACE FUNCTION public.work_list_participants(p_work_item_id UUID)
RETURNS TABLE(user_id UUID,full_name TEXT,participant_role public.work_participant_role,can_comment BOOLEAN,added_at TIMESTAMPTZ)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_item public.work_items%ROWTYPE;
BEGIN
  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id;
  IF NOT FOUND OR NOT private.work_user_can_view_row(
    v_actor,v_item.id,v_item.visibility,v_item.creator_user_id,v_item.requester_user_id,
    v_item.accountable_owner_user_id,v_item.current_assignee_user_id,v_item.branch_id,v_item.owning_department_id
  ) THEN RETURN; END IF;

  RETURN QUERY
  SELECT wp.user_id,COALESCE(p.full_name,'مستخدم'),wp.participant_role,wp.can_comment,wp.added_at
  FROM public.work_participants wp
  LEFT JOIN public.profiles p ON p.id=wp.user_id
  WHERE wp.work_item_id=p_work_item_id AND wp.removed_at IS NULL
  ORDER BY wp.added_at,wp.user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.work_list_item_people_candidates(UUID,TEXT,TEXT,INTEGER) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_list_participants(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.work_list_item_people_candidates(UUID,TEXT,TEXT,INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_list_participants(UUID) TO authenticated;

RESET lock_timeout;
RESET statement_timeout;
