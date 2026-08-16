-- Work Management — request-specific assignment candidates.
-- Queue assignment authority is intentionally distinct from general task/team assignment.
SET lock_timeout='5s';
SET statement_timeout='60s';

CREATE OR REPLACE FUNCTION public.work_list_request_assignment_candidates(
  p_work_item_id UUID,
  p_search TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 50
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
  v_request public.work_requests%ROWTYPE;
  v_limit INTEGER:=LEAST(GREATEST(COALESCE(p_limit,50),1),100);
  v_search TEXT:=NULLIF(btrim(COALESCE(p_search,'')),'');
BEGIN
  IF NOT private.work_actor_is_active(v_actor) THEN RETURN; END IF;

  SELECT r.* INTO v_request
  FROM public.work_requests r
  WHERE r.work_item_id=p_work_item_id;
  IF NOT FOUND THEN RETURN; END IF;

  IF NOT private.work_user_can_triage_queue(v_actor,v_request.queue_id)
     OR NOT private.work_user_can_assign_queue(v_actor,v_request.queue_id) THEN
    RETURN;
  END IF;

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
    AND private.work_queue_assignment_target_allowed(v_request.queue_id,p.id)
  ORDER BY (p.id=v_actor) DESC,p.full_name,p.id
  LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.work_list_request_assignment_candidates(UUID,TEXT,INTEGER)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.work_list_request_assignment_candidates(UUID,TEXT,INTEGER)
  TO authenticated;

RESET lock_timeout;
RESET statement_timeout;