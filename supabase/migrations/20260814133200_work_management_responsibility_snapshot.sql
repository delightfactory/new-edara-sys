-- Work Management — responsibility snapshot for a single visible Work Item.
-- Exposes only the actors already bound to a Work Item the caller can view.
SET lock_timeout='5s';
SET statement_timeout='60s';

CREATE OR REPLACE FUNCTION public.work_get_responsibility_snapshot(
  p_work_item_id UUID
) RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_item public.work_items%ROWTYPE;
  v_owner_name TEXT;
  v_assignee_name TEXT;
  v_waiting_name TEXT;
BEGIN
  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'code','NOT_FOUND');
  END IF;

  IF NOT private.work_user_can_view_row(
    v_actor,v_item.id,v_item.visibility,v_item.creator_user_id,v_item.requester_user_id,
    v_item.accountable_owner_user_id,v_item.current_assignee_user_id,v_item.branch_id,v_item.owning_department_id
  ) THEN
    RETURN jsonb_build_object('ok',false,'code','FORBIDDEN');
  END IF;

  SELECT p.full_name INTO v_owner_name
  FROM public.profiles p WHERE p.id=v_item.accountable_owner_user_id;

  SELECT p.full_name INTO v_assignee_name
  FROM public.profiles p WHERE p.id=v_item.current_assignee_user_id;

  IF v_item.waiting_on_user_id IS NOT NULL THEN
    SELECT p.full_name INTO v_waiting_name
    FROM public.profiles p WHERE p.id=v_item.waiting_on_user_id;
  END IF;

  RETURN jsonb_build_object(
    'ok',true,
    'work_item_id',v_item.id,
    'owner',CASE WHEN v_item.accountable_owner_user_id IS NULL THEN NULL ELSE jsonb_build_object(
      'user_id',v_item.accountable_owner_user_id,'full_name',COALESCE(v_owner_name,'مستخدم')
    ) END,
    'assignee',CASE WHEN v_item.current_assignee_user_id IS NULL THEN NULL ELSE jsonb_build_object(
      'user_id',v_item.current_assignee_user_id,'full_name',COALESCE(v_assignee_name,'مستخدم')
    ) END,
    'waiting_on',CASE
      WHEN v_item.status<>'waiting' THEN NULL
      WHEN v_item.waiting_on_user_id IS NOT NULL THEN jsonb_build_object(
        'type','user','user_id',v_item.waiting_on_user_id,'label',COALESCE(v_waiting_name,v_item.waiting_on_label,'مستخدم')
      )
      ELSE jsonb_build_object(
        'type',v_item.waiting_on_type,'label',COALESCE(v_item.waiting_on_label,v_item.waiting_reason,'جهة انتظار')
      )
    END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.work_get_responsibility_snapshot(UUID)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.work_get_responsibility_snapshot(UUID)
  TO authenticated;

RESET lock_timeout;
RESET statement_timeout;