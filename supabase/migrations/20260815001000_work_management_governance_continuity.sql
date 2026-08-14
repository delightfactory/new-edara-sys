-- Work Management — governance closure: due-date approval enforcement and inactive-user continuity.
SET lock_timeout='5s';
SET statement_timeout='60s';

-- A Work actor/target is available when its profile is active and, when HR records exist,
-- at least one HR employee record is still active. This keeps non-HR system users valid
-- while preventing deactivated employees from remaining executable assignment targets.
CREATE OR REPLACE FUNCTION private.work_user_is_available_for_work(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT p_user_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id=p_user_id
        AND p.status::TEXT='active'
    )
    AND (
      NOT EXISTS (
        SELECT 1 FROM public.hr_employees e WHERE e.user_id=p_user_id
      )
      OR EXISTS (
        SELECT 1
        FROM public.hr_employees e
        WHERE e.user_id=p_user_id
          AND e.status::TEXT='active'
      )
    );
$$;

CREATE OR REPLACE FUNCTION private.work_actor_is_active(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT private.work_user_is_available_for_work(p_user_id);
$$;

CREATE OR REPLACE FUNCTION private.work_user_can_assign_target(
  p_actor_user_id UUID,
  p_target_user_id UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_target_branch_id UUID;
  v_target_department_id UUID;
BEGIN
  IF NOT private.work_actor_is_active(p_actor_user_id)
     OR NOT private.work_user_is_available_for_work(p_target_user_id) THEN
    RETURN false;
  END IF;

  IF p_actor_user_id=p_target_user_id THEN
    RETURN true;
  END IF;

  IF COALESCE(public.check_permission(p_actor_user_id,'work.items.manage'),false) THEN
    RETURN true;
  END IF;

  SELECT e.branch_id,e.department_id
  INTO v_target_branch_id,v_target_department_id
  FROM public.hr_employees e
  WHERE e.user_id=p_target_user_id
    AND e.status::TEXT='active'
  ORDER BY e.id
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF COALESCE(public.check_permission(p_actor_user_id,'work.items.assign_branch'),false)
     AND v_target_branch_id IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM public.branches b
       WHERE b.id=v_target_branch_id
         AND b.manager_id=p_actor_user_id
         AND COALESCE(b.is_active,true)
     ) THEN
    RETURN true;
  END IF;

  IF COALESCE(public.check_permission(p_actor_user_id,'work.items.assign'),false)
     AND COALESCE(public.check_permission(p_actor_user_id,'work.items.manage_team'),false)
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

REVOKE ALL ON FUNCTION private.work_user_is_available_for_work(UUID)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_actor_is_active(UUID)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_user_can_assign_target(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;

-- Direct due-date changes remain available for setting the first due date, shortening it,
-- or clearing it. Extending an existing due date must go through the Approval Engine.
CREATE OR REPLACE FUNCTION public.work_change_due(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT,
  p_new_due_at TIMESTAMPTZ,
  p_reason TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_item public.work_items%ROWTYPE;
  v_old_due TIMESTAMPTZ;
  v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_change_due',
    jsonb_build_object('work_item_id',p_work_item_id,'expected_version',p_expected_version,'new_due_at',p_new_due_at,'reason',p_reason),
    p_work_item_id
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_change_due','NOT_FOUND','المهمة غير موجودة',p_work_item_id); END IF;
  IF v_item.state_version<>p_expected_version THEN RETURN private.work_command_error(p_operation_id,'work_change_due','VERSION_CONFLICT','تم تعديل المهمة بواسطة مستخدم آخر',p_work_item_id); END IF;
  IF NOT private.work_actor_can_update_item(v_actor,p_work_item_id) THEN RETURN private.work_command_error(p_operation_id,'work_change_due','FORBIDDEN','غير مصرح بتعديل موعد المهمة',p_work_item_id); END IF;
  IF v_item.status IN ('done'::public.work_item_status,'cancelled'::public.work_item_status) THEN RETURN private.work_command_error(p_operation_id,'work_change_due','INVALID_STATE','المهمة منتهية',p_work_item_id); END IF;
  IF p_reason IS NULL OR btrim(p_reason)='' THEN RETURN private.work_command_error(p_operation_id,'work_change_due','REASON_REQUIRED','سبب تعديل الموعد مطلوب',p_work_item_id); END IF;

  IF EXISTS (
    SELECT 1
    FROM public.work_approval_requests r
    WHERE r.work_item_id=p_work_item_id
      AND r.context_kind='due_change'::public.work_approval_context_kind
      AND r.status='pending'::public.work_approval_runtime_status
  ) THEN
    RETURN private.work_command_error(
      p_operation_id,'work_change_due','DUE_CHANGE_APPROVAL_PENDING',
      'يوجد طلب تمديد موعد قيد الاعتماد؛ أكمله أو ارفضه قبل تغيير الموعد',p_work_item_id
    );
  END IF;

  IF v_item.due_at IS NOT NULL
     AND p_new_due_at IS NOT NULL
     AND p_new_due_at>v_item.due_at THEN
    RETURN private.work_command_error(
      p_operation_id,'work_change_due','APPROVAL_REQUIRED',
      'تمديد الموعد يتطلب اعتمادًا؛ استخدم طلب تمديد الموعد',p_work_item_id
    );
  END IF;

  v_old_due:=v_item.due_at;
  UPDATE public.work_items
  SET due_at=p_new_due_at,
      first_due_at=COALESCE(first_due_at,p_new_due_at),
      state_version=state_version+1,
      last_meaningful_activity_at=clock_timestamp()
  WHERE id=p_work_item_id
  RETURNING * INTO v_item;

  PERFORM private.work_append_user_event(
    v_item.id,'work.due_changed',v_actor,p_operation_id,v_item.status,v_item.status,
    jsonb_build_object('from_due_at',v_old_due,'to_due_at',p_new_due_at,'reason',p_reason,'approval_required',false)
  );
  v_result:=jsonb_build_object('work_item_id',v_item.id,'status',v_item.status,'state_version',v_item.state_version,'due_at',v_item.due_at);
  RETURN private.work_command_success(p_operation_id,'work_change_due',v_item.id,v_result);
END;
$$;

-- A due-change approval is intentionally extension-only. This prevents the approval
-- path from becoming a second, ambiguous way to perform ordinary due-date edits.
CREATE OR REPLACE FUNCTION public.work_request_due_change(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT,
  p_new_due_at TIMESTAMPTZ,
  p_reason TEXT,
  p_approval_template_id UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_item public.work_items%ROWTYPE;
  v_request_id UUID;
  v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_request_due_change',
    jsonb_build_object('work_item_id',p_work_item_id,'expected_version',p_expected_version,'new_due_at',p_new_due_at,'reason',p_reason,'approval_template_id',p_approval_template_id),
    p_work_item_id
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_request_due_change','NOT_FOUND','المهمة غير موجودة',p_work_item_id); END IF;
  IF v_item.state_version<>p_expected_version THEN RETURN private.work_command_error(p_operation_id,'work_request_due_change','VERSION_CONFLICT','تم تعديل المهمة بواسطة مستخدم آخر',p_work_item_id); END IF;
  IF NOT private.work_actor_can_update_item(v_actor,p_work_item_id) THEN RETURN private.work_command_error(p_operation_id,'work_request_due_change','FORBIDDEN','غير مصرح بطلب تمديد الموعد',p_work_item_id); END IF;
  IF v_item.status IN ('done'::public.work_item_status,'cancelled'::public.work_item_status) THEN RETURN private.work_command_error(p_operation_id,'work_request_due_change','INVALID_STATE','المهمة منتهية',p_work_item_id); END IF;
  IF v_item.due_at IS NULL THEN RETURN private.work_command_error(p_operation_id,'work_request_due_change','NOT_DUE_EXTENSION','لا يوجد موعد حالي لتمديده؛ عيّن الموعد الأول مباشرة',p_work_item_id); END IF;
  IF p_new_due_at IS NULL OR p_new_due_at<=clock_timestamp() THEN RETURN private.work_command_error(p_operation_id,'work_request_due_change','INVALID_DUE_DATE','الموعد الجديد يجب أن يكون في المستقبل',p_work_item_id); END IF;
  IF p_new_due_at<=v_item.due_at THEN RETURN private.work_command_error(p_operation_id,'work_request_due_change','NOT_DUE_EXTENSION','طلب الاعتماد مخصص لتمديد الموعد فقط؛ تقديم الموعد يتم مباشرة مع السبب',p_work_item_id); END IF;
  IF p_reason IS NULL OR btrim(p_reason)='' THEN RETURN private.work_command_error(p_operation_id,'work_request_due_change','REASON_REQUIRED','سبب تمديد الموعد مطلوب',p_work_item_id); END IF;
  IF p_approval_template_id IS NULL THEN RETURN private.work_command_error(p_operation_id,'work_request_due_change','APPROVAL_TEMPLATE_REQUIRED','نموذج اعتماد تمديد الموعد مطلوب',p_work_item_id); END IF;
  IF EXISTS (
    SELECT 1
    FROM public.work_approval_requests r
    WHERE r.work_item_id=p_work_item_id
      AND r.context_kind='due_change'::public.work_approval_context_kind
      AND r.status='pending'::public.work_approval_runtime_status
  ) THEN
    RETURN private.work_command_error(p_operation_id,'work_request_due_change','DUE_CHANGE_APPROVAL_PENDING','يوجد بالفعل طلب تمديد موعد قيد الاعتماد',p_work_item_id);
  END IF;

  BEGIN
    v_request_id:=private.work_start_approval_request(
      p_work_item_id,p_approval_template_id,'due_change',
      jsonb_build_object(
        'old_due_at',v_item.due_at,
        'new_due_at',p_new_due_at,
        'reason',p_reason,
        'requested_work_version',p_expected_version
      ),
      v_actor,p_operation_id
    );

    UPDATE public.work_items
    SET state_version=state_version+1,
        last_meaningful_activity_at=clock_timestamp()
    WHERE id=p_work_item_id
    RETURNING * INTO v_item;

    v_result:=jsonb_build_object(
      'work_item_id',v_item.id,
      'status',v_item.status,
      'state_version',v_item.state_version,
      'approval_request_id',v_request_id,
      'requested_due_at',p_new_due_at
    );
    RETURN private.work_command_success(p_operation_id,'work_request_due_change',v_item.id,v_result);
  EXCEPTION WHEN OTHERS THEN
    RETURN private.work_command_error(p_operation_id,'work_request_due_change','APPROVAL_START_FAILED','تعذر بدء اعتماد تمديد الموعد',p_work_item_id);
  END;
END;
$$;

-- Management-only continuity read model. Historical creator/requester identity is never
-- rewritten; only live owner/assignee responsibilities are considered orphaned.
CREATE OR REPLACE FUNCTION public.work_list_orphaned_assignments()
RETURNS TABLE(
  user_id UUID,
  full_name TEXT,
  profile_status TEXT,
  employee_status TEXT,
  orphan_reason TEXT,
  owner_count BIGINT,
  assignee_count BIGINT,
  work_item_count BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
BEGIN
  IF NOT private.work_actor_is_active(v_actor)
     OR NOT COALESCE(public.check_permission(v_actor,'work.items.manage'),false) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH refs AS (
    SELECT w.id AS work_item_id,w.accountable_owner_user_id AS referenced_user_id,'owner'::TEXT AS responsibility
    FROM public.work_items w
    WHERE w.status NOT IN ('done'::public.work_item_status,'cancelled'::public.work_item_status)
      AND w.accountable_owner_user_id IS NOT NULL
    UNION ALL
    SELECT w.id,w.current_assignee_user_id,'assignee'::TEXT
    FROM public.work_items w
    WHERE w.status NOT IN ('done'::public.work_item_status,'cancelled'::public.work_item_status)
      AND w.current_assignee_user_id IS NOT NULL
  ), aggregated AS (
    SELECT
      r.referenced_user_id,
      count(DISTINCT r.work_item_id) FILTER (WHERE r.responsibility='owner')::BIGINT AS owner_count,
      count(DISTINCT r.work_item_id) FILTER (WHERE r.responsibility='assignee')::BIGINT AS assignee_count,
      count(DISTINCT r.work_item_id)::BIGINT AS work_item_count
    FROM refs r
    GROUP BY r.referenced_user_id
  )
  SELECT
    a.referenced_user_id,
    COALESCE(NULLIF(btrim(p.full_name),''),'مستخدم غير متاح')::TEXT,
    COALESCE(p.status::TEXT,'missing')::TEXT,
    CASE
      WHEN EXISTS (SELECT 1 FROM public.hr_employees e0 WHERE e0.user_id=a.referenced_user_id)
        THEN COALESCE((
          SELECT e1.status::TEXT
          FROM public.hr_employees e1
          WHERE e1.user_id=a.referenced_user_id
          ORDER BY (e1.status::TEXT='active') DESC,e1.id
          LIMIT 1
        ),'unknown')
      ELSE 'no_hr_record'
    END::TEXT,
    CASE
      WHEN p.id IS NULL OR p.status::TEXT<>'active' THEN 'profile_inactive'
      WHEN EXISTS (SELECT 1 FROM public.hr_employees e2 WHERE e2.user_id=a.referenced_user_id)
           AND NOT EXISTS (SELECT 1 FROM public.hr_employees e3 WHERE e3.user_id=a.referenced_user_id AND e3.status::TEXT='active') THEN 'employee_inactive'
      ELSE 'unavailable'
    END::TEXT,
    a.owner_count,
    a.assignee_count,
    a.work_item_count
  FROM aggregated a
  LEFT JOIN public.profiles p ON p.id=a.referenced_user_id
  WHERE NOT private.work_user_is_available_for_work(a.referenced_user_id)
  ORDER BY a.work_item_count DESC,COALESCE(p.full_name,''),a.referenced_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.work_list_continuity_candidates(
  p_search TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 100
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
  v_search TEXT:=NULLIF(btrim(COALESCE(p_search,'')),'');
  v_limit INTEGER:=LEAST(GREATEST(COALESCE(p_limit,100),1),200);
BEGIN
  IF NOT private.work_actor_is_active(v_actor)
     OR NOT COALESCE(public.check_permission(v_actor,'work.items.manage'),false) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.full_name::TEXT,
    employee.branch_id,
    employee.department_id,
    p.id=v_actor
  FROM public.profiles p
  LEFT JOIN LATERAL (
    SELECT e.branch_id,e.department_id
    FROM public.hr_employees e
    WHERE e.user_id=p.id
      AND e.status::TEXT='active'
    ORDER BY e.id
    LIMIT 1
  ) employee ON true
  WHERE private.work_user_is_available_for_work(p.id)
    AND p.full_name IS NOT NULL
    AND btrim(p.full_name)<>''
    AND (v_search IS NULL OR p.full_name ILIKE '%'||v_search||'%')
  ORDER BY (p.id=v_actor) DESC,p.full_name,p.id
  LIMIT v_limit;
END;
$$;

CREATE OR REPLACE FUNCTION public.work_bulk_reassign_orphaned(
  p_operation_id UUID,
  p_inactive_user_id UUID,
  p_replacement_user_id UUID,
  p_reason TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_item public.work_items%ROWTYPE;
  v_updated public.work_items%ROWTYPE;
  v_changed_owner BOOLEAN;
  v_changed_assignee BOOLEAN;
  v_owner_changes INTEGER:=0;
  v_assignee_changes INTEGER:=0;
  v_work_item_ids UUID[]:=ARRAY[]::UUID[];
  v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_bulk_reassign_orphaned',
    jsonb_build_object('inactive_user_id',p_inactive_user_id,'replacement_user_id',p_replacement_user_id,'reason',p_reason),
    NULL
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;

  IF NOT private.work_actor_is_active(v_actor)
     OR NOT COALESCE(public.check_permission(v_actor,'work.items.manage'),false) THEN
    RETURN private.work_command_error(p_operation_id,'work_bulk_reassign_orphaned','FORBIDDEN','لا تملك صلاحية معالجة استمرارية الأعمال');
  END IF;
  IF p_inactive_user_id IS NULL OR p_replacement_user_id IS NULL OR p_inactive_user_id=p_replacement_user_id THEN
    RETURN private.work_command_error(p_operation_id,'work_bulk_reassign_orphaned','INVALID_USERS','حدد المستخدم غير النشط والبديل بشكل صحيح');
  END IF;
  IF p_reason IS NULL OR btrim(p_reason)='' THEN
    RETURN private.work_command_error(p_operation_id,'work_bulk_reassign_orphaned','REASON_REQUIRED','سبب إعادة الإسناد مطلوب');
  END IF;
  IF private.work_user_is_available_for_work(p_inactive_user_id) THEN
    RETURN private.work_command_error(p_operation_id,'work_bulk_reassign_orphaned','SOURCE_STILL_ACTIVE','المستخدم المحدد ما زال متاحًا للعمل ولا يحتاج معالجة استمرارية');
  END IF;
  IF NOT private.work_user_is_available_for_work(p_replacement_user_id)
     OR NOT private.work_user_can_assign_target(v_actor,p_replacement_user_id) THEN
    RETURN private.work_command_error(p_operation_id,'work_bulk_reassign_orphaned','INVALID_REPLACEMENT','المستخدم البديل غير نشط أو غير صالح للإسناد');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.work_items w
    WHERE w.status NOT IN ('done'::public.work_item_status,'cancelled'::public.work_item_status)
      AND (w.accountable_owner_user_id=p_inactive_user_id OR w.current_assignee_user_id=p_inactive_user_id)
  ) THEN
    RETURN private.work_command_error(p_operation_id,'work_bulk_reassign_orphaned','ORPHAN_WORK_NOT_FOUND','لا توجد أعمال نشطة مرتبطة بالمستخدم المحدد');
  END IF;

  FOR v_item IN
    SELECT w.*
    FROM public.work_items w
    WHERE w.status NOT IN ('done'::public.work_item_status,'cancelled'::public.work_item_status)
      AND (w.accountable_owner_user_id=p_inactive_user_id OR w.current_assignee_user_id=p_inactive_user_id)
    ORDER BY w.id
    FOR UPDATE
  LOOP
    v_changed_owner:=v_item.accountable_owner_user_id=p_inactive_user_id;
    v_changed_assignee:=v_item.current_assignee_user_id=p_inactive_user_id;

    UPDATE public.work_items
    SET accountable_owner_user_id=CASE WHEN v_changed_owner THEN p_replacement_user_id ELSE accountable_owner_user_id END,
        current_assignee_user_id=CASE WHEN v_changed_assignee THEN p_replacement_user_id ELSE current_assignee_user_id END,
        assigned_at=CASE WHEN v_changed_assignee THEN clock_timestamp() ELSE assigned_at END,
        first_viewed_at=CASE WHEN v_changed_assignee THEN NULL ELSE first_viewed_at END,
        acknowledged_at=CASE WHEN v_changed_assignee THEN NULL ELSE acknowledged_at END,
        state_version=state_version+1,
        last_meaningful_activity_at=clock_timestamp()
    WHERE id=v_item.id
    RETURNING * INTO v_updated;

    IF v_changed_owner THEN
      v_owner_changes:=v_owner_changes+1;
      PERFORM private.work_append_user_event(
        v_updated.id,'work.ownership_transferred',v_actor,p_operation_id,v_updated.status,v_updated.status,
        jsonb_build_object(
          'from_owner_user_id',p_inactive_user_id,
          'to_owner_user_id',p_replacement_user_id,
          'reason',btrim(p_reason),
          'source','inactive_user_continuity'
        )
      );
    END IF;

    IF v_changed_assignee THEN
      v_assignee_changes:=v_assignee_changes+1;
      PERFORM private.work_append_user_event(
        v_updated.id,'work.delegated',v_actor,p_operation_id,v_updated.status,v_updated.status,
        jsonb_build_object(
          'from_assignee_user_id',p_inactive_user_id,
          'to_assignee_user_id',p_replacement_user_id,
          'reason',btrim(p_reason),
          'source','inactive_user_continuity'
        )
      );
    END IF;

    v_work_item_ids:=array_append(v_work_item_ids,v_updated.id);
  END LOOP;

  v_result:=jsonb_build_object(
    'inactive_user_id',p_inactive_user_id,
    'replacement_user_id',p_replacement_user_id,
    'work_item_count',cardinality(v_work_item_ids),
    'owner_changes',v_owner_changes,
    'assignee_changes',v_assignee_changes,
    'work_item_ids',to_jsonb(v_work_item_ids)
  );
  RETURN private.work_command_success(p_operation_id,'work_bulk_reassign_orphaned',NULL,v_result);
END;
$$;

REVOKE ALL ON FUNCTION public.work_list_orphaned_assignments() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_list_continuity_candidates(TEXT,INTEGER) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_bulk_reassign_orphaned(UUID,UUID,UUID,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.work_list_orphaned_assignments() TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_list_continuity_candidates(TEXT,INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_bulk_reassign_orphaned(UUID,UUID,UUID,TEXT) TO authenticated;

RESET lock_timeout;
RESET statement_timeout;
