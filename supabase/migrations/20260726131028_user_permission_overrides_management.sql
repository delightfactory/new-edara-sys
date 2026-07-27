-- ==========================================================================
-- Individual user permission management
--
-- Keeps roles as the baseline and stores only explicit per-user grants/denies.
-- Writes are intentionally exposed through one audited, atomic RPC.
-- ==========================================================================

-- A dedicated permission separates profile/role editing from the much more
-- sensitive ability to grant and revoke arbitrary application permissions.
INSERT INTO public.role_permissions (role_id, permission)
SELECT id, 'auth.user_permissions.manage'
FROM public.roles
WHERE name = 'super_admin'
ON CONFLICT (role_id, permission) DO NOTHING;

-- Preserve the established positive-permission result contract used by
-- get_my_profile and any trusted backend callers.
CREATE OR REPLACE FUNCTION public.get_user_permissions(p_user_id UUID)
RETURNS TABLE(permission TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Missing user identity';
  END IF;

  -- Preserve trusted service-role compatibility while preventing anonymous
  -- callers from using this SECURITY DEFINER function to inspect other users.
  IF auth.uid() IS NULL THEN
    IF COALESCE(auth.jwt()->>'role', '') <> 'service_role' THEN
      RAISE EXCEPTION 'Unauthorized: Missing user identity';
    END IF;
  ELSIF p_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  RETURN QUERY
    SELECT upo.permission
    FROM public.user_permission_overrides upo
    WHERE upo.user_id = p_user_id
      AND upo.granted = true
      AND (upo.expires_at IS NULL OR upo.expires_at > now());

  RETURN QUERY
    SELECT DISTINCT rp.permission
    FROM public.role_permissions rp
    JOIN public.user_roles ur ON ur.role_id = rp.role_id
    WHERE ur.user_id = p_user_id
      AND ur.is_active = true
      AND NOT EXISTS (
        SELECT 1
        FROM public.user_permission_overrides upo
        WHERE upo.user_id = p_user_id
          AND upo.permission = rp.permission
          AND upo.granted = false
          AND (upo.expires_at IS NULL OR upo.expires_at > now())
      );

END;
$$;

REVOKE ALL ON FUNCTION public.get_user_permissions(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_user_permissions(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_user_permissions(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_permissions(UUID) TO service_role;


-- A separate self-only RPC extends the new frontend without changing the
-- established get_user_permissions/get_my_profile response contract.
CREATE OR REPLACE FUNCTION public.get_my_permission_denials()
RETURNS TABLE(permission TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Missing user identity';
  END IF;

  RETURN QUERY
    SELECT '!' || upo.permission
    FROM public.user_permission_overrides upo
    WHERE upo.user_id = v_actor
      AND upo.granted = false
      AND (upo.expires_at IS NULL OR upo.expires_at > now());
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_permission_denials() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_permission_denials() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_permission_denials() TO authenticated;


CREATE OR REPLACE FUNCTION public.get_user_permission_context(p_target_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_inherited JSONB;
  v_overrides JSONB;
  v_role_permissions JSONB;
  v_has_wildcard BOOLEAN;
  v_actor_grade INTEGER;
  v_target_grade INTEGER;
BEGIN
  IF v_actor IS NULL
     OR NOT public.check_permission(v_actor, 'auth.user_permissions.manage') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية إدارة صلاحيات المستخدمين';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_target_user_id) THEN
    RAISE EXCEPTION 'المستخدم غير موجود';
  END IF;

  SELECT COALESCE(MAX(r.grade), 0)
  INTO v_actor_grade
  FROM public.user_roles ur
  JOIN public.roles r ON r.id = ur.role_id
  WHERE ur.user_id = v_actor AND ur.is_active = true;

  SELECT COALESCE(MAX(r.grade), 0)
  INTO v_target_grade
  FROM public.user_roles ur
  JOIN public.roles r ON r.id = ur.role_id
  WHERE ur.user_id = p_target_user_id AND ur.is_active = true;

  IF p_target_user_id = v_actor OR v_target_grade >= v_actor_grade THEN
    RAISE EXCEPTION 'لا يمكنك إدارة مستخدم بمستوى مساوٍ أو أعلى من مستواك';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles ur
    JOIN public.role_permissions rp ON rp.role_id = ur.role_id
    WHERE ur.user_id = p_target_user_id
      AND ur.is_active = true
      AND rp.permission = '*'
  ) INTO v_has_wildcard;

  SELECT COALESCE(jsonb_agg(permission ORDER BY permission), '[]'::jsonb)
  INTO v_inherited
  FROM (
    SELECT DISTINCT rp.permission
    FROM public.user_roles ur
    JOIN public.role_permissions rp ON rp.role_id = ur.role_id
    WHERE ur.user_id = p_target_user_id
      AND ur.is_active = true
      AND rp.permission <> '*'
  ) inherited;

  SELECT COALESCE(jsonb_agg(to_jsonb(active_override) ORDER BY active_override.permission), '[]'::jsonb)
  INTO v_overrides
  FROM (
    SELECT
      upo.id,
      upo.user_id,
      upo.permission,
      upo.granted,
      upo.granted_by,
      upo.reason,
      upo.expires_at,
      upo.created_at
    FROM public.user_permission_overrides upo
    WHERE upo.user_id = p_target_user_id
      AND (upo.expires_at IS NULL OR upo.expires_at > now())
  ) active_override;

  SELECT COALESCE(jsonb_object_agg(role_permission.role_id, role_permission.permissions), '{}'::jsonb)
  INTO v_role_permissions
  FROM (
    SELECT
      rp.role_id::TEXT AS role_id,
      jsonb_agg(rp.permission ORDER BY rp.permission) AS permissions
    FROM public.role_permissions rp
    GROUP BY rp.role_id
  ) role_permission;

  RETURN jsonb_build_object(
    'has_wildcard', v_has_wildcard,
    'inherited_permissions', v_inherited,
    'role_permissions_by_role', v_role_permissions,
    'overrides', v_overrides
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_user_permission_context(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_user_permission_context(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_user_permission_context(UUID) TO authenticated;


CREATE OR REPLACE FUNCTION public.set_user_permission_overrides(
  p_target_user_id UUID,
  p_overrides JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_item JSONB;
  v_permission TEXT;
  v_reason TEXT;
  v_expires_at TIMESTAMPTZ;
  v_seen TEXT[] := ARRAY[]::TEXT[];
  v_old JSONB;
  v_new JSONB;
  v_actor_grade INTEGER;
  v_target_grade INTEGER;
  v_known_permissions CONSTANT TEXT[] := ARRAY[
    'activities.create', 'activities.read_all', 'activities.read_own',
    'activities.read_team', 'activities.update_own', 'auth.roles.create',
    'auth.roles.delete', 'auth.roles.read', 'auth.roles.update',
    'auth.user_permissions.manage', 'auth.users.create',
    'auth.users.deactivate', 'auth.users.read', 'auth.users.reset_password',
    'auth.users.update', 'branches.create', 'branches.read', 'branches.update',
    'call_plans.cancel', 'call_plans.confirm', 'call_plans.create',
    'call_plans.read_all', 'call_plans.read_own', 'call_plans.read_team',
    'call_plans.update', 'call_plans.update_own', 'categories.create',
    'checklists.manage', 'customers.create', 'customers.credit.update',
    'customers.delete', 'customers.read', 'customers.read_all',
    'customers.update', 'customers.update_location', 'finance.custody.create',
    'finance.custody.read', 'finance.custody.read_all',
    'finance.custody.transact', 'finance.credit.manage',
    'finance.expenses.approve',
    'finance.expenses.create', 'finance.expenses.read',
    'finance.expenses.read_all', 'finance.journal.create',
    'finance.journal.read', 'finance.journals.create',
    'finance.ledger.adjust', 'finance.ledger.read',
    'finance.payments.confirm', 'finance.payments.create',
    'finance.payments.read', 'finance.payments.read_all',
    'finance.vaults.create', 'finance.vaults.read', 'finance.vaults.read_all',
    'finance.vaults.transact', 'finance.vaults.update', 'finance.view_costs',
    'finance.read', 'hr.adjustments.approve', 'hr.adjustments.create',
    'hr.adjustments.read', 'hr.advances.approve', 'hr.advances.create',
    'hr.advances.read', 'hr.attendance.approve', 'hr.attendance.checkin',
    'hr.attendance.create', 'hr.attendance.edit', 'hr.attendance.read',
    'hr.attendance.update',
    'hr.commissions.create', 'hr.employees.create', 'hr.employees.delete',
    'hr.employees.edit', 'hr.employees.read', 'hr.employees.update',
    'hr.leaves.approve',
    'hr.leaves.create', 'hr.leaves.read', 'hr.leaves.request',
    'hr.payroll.approve', 'hr.payroll.calculate', 'hr.payroll.disburse',
    'hr.payroll.read', 'hr.permissions.approve', 'hr.reports.view',
    'hr.settings.update',
    'inventory.adjustments.create', 'inventory.adjustments.read',
    'inventory.create', 'inventory.read', 'inventory.read_all',
    'inventory.transfers.approve', 'inventory.transfers.create',
    'inventory.transfers.read', 'inventory.update', 'notifications.dispatch',
    'price_lists.read', 'price_lists.update', 'procurement.invoices.bill',
    'procurement.invoices.cancel', 'procurement.invoices.create',
    'procurement.invoices.pay', 'procurement.invoices.read',
    'procurement.invoices.receive', 'procurement.returns.confirm',
    'procurement.returns.create', 'procurement.returns.read', 'products.create',
    'products.delete', 'products.read', 'products.update',
    'purchases.orders.confirm', 'purchases.orders.create',
    'purchases.orders.read', 'purchases.orders.read_all',
    'purchases.receipts.confirm', 'reports.activities', 'reports.export',
    'reports.financial', 'reports.sales', 'reports.targets',
    'reports.team_performance', 'reports.view_all',
    'sales.discounts.override', 'sales.orders.cancel', 'sales.orders.confirm',
    'sales.orders.create', 'sales.orders.deliver',
    'sales.orders.edit_confirmed', 'sales.orders.edit_price',
    'sales.orders.override_credit', 'sales.orders.read', 'sales.orders.delete',
    'sales.orders.read_all', 'sales.orders.update', 'sales.returns.confirm',
    'sales.returns.cancel', 'sales.returns.create', 'sales.returns.read',
    'sales.shipping.manage', 'sales.read',
    'settings.audit.read', 'settings.read', 'settings.update',
    'suppliers.create', 'suppliers.delete', 'suppliers.read',
    'suppliers.update', 'targets.assign', 'targets.create', 'targets.read',
    'targets.read_all', 'targets.read_own', 'targets.read_team',
    'targets.rewards.configure', 'targets.rewards.view', 'targets.update',
    'targets.view', 'visit_plans.cancel', 'visit_plans.close_day',
    'visit_plans.close_administrative', 'visit_plans.confirm',
    'visit_plans.create', 'visit_plans.read_all', 'visit_plans.read_own',
    'visit_plans.read_team', 'visit_plans.review_gps', 'visit_plans.update',
    'visit_plans.update_own'
  ];
BEGIN
  IF v_actor IS NULL
     OR NOT public.check_permission(v_actor, 'auth.user_permissions.manage') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية إدارة صلاحيات المستخدمين';
  END IF;

  -- Prevent delegated administrators from escalating their own account.
  IF p_target_user_id = v_actor THEN
    RAISE EXCEPTION 'لا يمكن تعديل صلاحيات حسابك الحالي';
  END IF;

  IF p_overrides IS NULL OR jsonb_typeof(p_overrides) <> 'array' THEN
    RAISE EXCEPTION 'صيغة استثناءات الصلاحيات غير صحيحة';
  END IF;

  IF jsonb_array_length(p_overrides) > cardinality(v_known_permissions) THEN
    RAISE EXCEPTION 'عدد استثناءات الصلاحيات غير صحيح';
  END IF;

  -- Lock the target profile so concurrent access edits cannot interleave.
  PERFORM 1
  FROM public.profiles
  WHERE id = p_target_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'المستخدم غير موجود';
  END IF;

  SELECT COALESCE(MAX(r.grade), 0)
  INTO v_actor_grade
  FROM public.user_roles ur
  JOIN public.roles r ON r.id = ur.role_id
  WHERE ur.user_id = v_actor AND ur.is_active = true;

  SELECT COALESCE(MAX(r.grade), 0)
  INTO v_target_grade
  FROM public.user_roles ur
  JOIN public.roles r ON r.id = ur.role_id
  WHERE ur.user_id = p_target_user_id AND ur.is_active = true;

  IF v_target_grade >= v_actor_grade THEN
    RAISE EXCEPTION 'لا يمكنك إدارة مستخدم بمستوى مساوٍ أو أعلى من مستواك';
  END IF;

  -- Validate the complete payload before changing any row.
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_overrides)
  LOOP
    IF jsonb_typeof(v_item) <> 'object' THEN
      RAISE EXCEPTION 'صيغة استثناء صلاحية غير صحيحة';
    END IF;

    v_permission := NULLIF(btrim(v_item->>'permission'), '');
    IF v_permission IS NULL OR NOT (v_permission = ANY(v_known_permissions)) THEN
      RAISE EXCEPTION 'صلاحية غير معروفة: %', COALESCE(v_permission, '(فارغة)');
    END IF;

    IF v_permission = ANY(v_seen) THEN
      RAISE EXCEPTION 'لا يمكن تكرار الصلاحية: %', v_permission;
    END IF;
    v_seen := array_append(v_seen, v_permission);

    IF jsonb_typeof(v_item->'granted') IS DISTINCT FROM 'boolean' THEN
      RAISE EXCEPTION 'حالة الصلاحية غير صحيحة: %', v_permission;
    END IF;

    v_reason := NULLIF(btrim(v_item->>'reason'), '');
    IF char_length(v_reason) > 500 THEN
      RAISE EXCEPTION 'سبب الاستثناء أطول من الحد المسموح';
    END IF;

    BEGIN
      v_expires_at := NULLIF(v_item->>'expires_at', '')::TIMESTAMPTZ;
    EXCEPTION WHEN invalid_datetime_format THEN
      RAISE EXCEPTION 'تاريخ انتهاء غير صحيح للصلاحية: %', v_permission;
    END;

    IF v_expires_at IS NOT NULL AND v_expires_at <= now() THEN
      RAISE EXCEPTION 'تاريخ انتهاء الصلاحية يجب أن يكون في المستقبل: %', v_permission;
    END IF;
  END LOOP;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'permission', upo.permission,
        'granted', upo.granted,
        'reason', upo.reason,
        'expires_at', upo.expires_at
      ) ORDER BY upo.permission
    ),
    '[]'::jsonb
  )
  INTO v_old
  FROM public.user_permission_overrides upo
  WHERE upo.user_id = p_target_user_id;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'permission', item.permission,
        'granted', item.granted,
        'reason', NULLIF(btrim(item.reason), ''),
        'expires_at', item.expires_at
      ) ORDER BY item.permission
    ),
    '[]'::jsonb
  )
  INTO v_new
  FROM jsonb_to_recordset(p_overrides) AS item(
    permission TEXT,
    granted BOOLEAN,
    reason TEXT,
    expires_at TIMESTAMPTZ
  );

  IF v_old = v_new THEN
    RETURN jsonb_build_object('saved_count', jsonb_array_length(v_new), 'changed', false);
  END IF;

  DELETE FROM public.user_permission_overrides
  WHERE user_id = p_target_user_id;

  INSERT INTO public.user_permission_overrides (
    user_id, permission, granted, granted_by, reason, expires_at
  )
  SELECT
    p_target_user_id,
    item.permission,
    item.granted,
    v_actor,
    NULLIF(btrim(item.reason), ''),
    item.expires_at
  FROM jsonb_to_recordset(p_overrides) AS item(
    permission TEXT,
    granted BOOLEAN,
    reason TEXT,
    expires_at TIMESTAMPTZ
  );

  INSERT INTO public.audit_logs (
    user_id, action, entity_type, entity_id, old_data, new_data
  ) VALUES (
    v_actor,
    'user_permissions.updated',
    'user_permission_overrides',
    p_target_user_id,
    jsonb_build_object('overrides', v_old),
    jsonb_build_object('overrides', v_new)
  );

  RETURN jsonb_build_object('saved_count', jsonb_array_length(v_new), 'changed', true);
END;
$$;

REVOKE ALL ON FUNCTION public.set_user_permission_overrides(UUID, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_user_permission_overrides(UUID, JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_user_permission_overrides(UUID, JSONB) TO authenticated;

-- Harden the existing role assignment RPC against self-escalation while
-- preserving its signature for existing callers (including create-user).
CREATE OR REPLACE FUNCTION public.set_user_roles_atomic(
  p_target_user_id UUID,
  p_role_ids UUID[],
  p_user_id UUID DEFAULT auth.uid()
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_role_id UUID;
  v_actor_grade INTEGER;
  v_current_target_grade INTEGER;
  v_requested_grade INTEGER;
  v_old_roles JSONB;
  v_new_roles JSONB;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Missing user identity';
  END IF;

  IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  IF NOT public.check_permission(p_user_id, 'auth.users.update') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية تحديث المستخدمين';
  END IF;

  IF p_target_user_id = p_user_id THEN
    RAISE EXCEPTION 'لا يمكن تعديل أدوار حسابك الحالي';
  END IF;

  PERFORM 1
  FROM public.profiles
  WHERE id = p_target_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'المستخدم غير موجود';
  END IF;

  SELECT COALESCE(MAX(r.grade), 0)
  INTO v_actor_grade
  FROM public.user_roles ur
  JOIN public.roles r ON r.id = ur.role_id
  WHERE ur.user_id = p_user_id AND ur.is_active = true;

  SELECT COALESCE(MAX(r.grade), 0)
  INTO v_current_target_grade
  FROM public.user_roles ur
  JOIN public.roles r ON r.id = ur.role_id
  WHERE ur.user_id = p_target_user_id AND ur.is_active = true;

  SELECT COALESCE(MAX(r.grade), 0)
  INTO v_requested_grade
  FROM public.roles r
  WHERE r.id = ANY(COALESCE(p_role_ids, ARRAY[]::UUID[]));

  IF v_current_target_grade >= v_actor_grade OR v_requested_grade >= v_actor_grade THEN
    RAISE EXCEPTION 'لا يمكنك إدارة أو تعيين دور بمستوى مساوٍ أو أعلى من مستواك';
  END IF;

  FOREACH v_role_id IN ARRAY COALESCE(p_role_ids, ARRAY[]::UUID[])
  LOOP
    IF NOT EXISTS (SELECT 1 FROM public.roles WHERE id = v_role_id) THEN
      RAISE EXCEPTION 'الدور غير موجود: %', v_role_id;
    END IF;
  END LOOP;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'role_id', ur.role_id,
        'branch_id', ur.branch_id,
        'is_active', ur.is_active,
        'assigned_by', ur.assigned_by
      ) ORDER BY ur.role_id
    ),
    '[]'::jsonb
  )
  INTO v_old_roles
  FROM public.user_roles ur
  WHERE ur.user_id = p_target_user_id;

  -- Apply only the role delta. Existing assignments retain branch scope,
  -- assigner and original assignment timestamp.
  DELETE FROM public.user_roles ur
  WHERE ur.user_id = p_target_user_id
    AND NOT (ur.role_id = ANY(COALESCE(p_role_ids, ARRAY[]::UUID[])));

  UPDATE public.user_roles ur
  SET is_active = true
  WHERE ur.user_id = p_target_user_id
    AND ur.role_id = ANY(COALESCE(p_role_ids, ARRAY[]::UUID[]))
    AND ur.is_active = false;

  INSERT INTO public.user_roles (user_id, role_id, assigned_by)
  SELECT p_target_user_id, requested.role_id, p_user_id
  FROM (
    SELECT DISTINCT requested_role.role_id
    FROM unnest(COALESCE(p_role_ids, ARRAY[]::UUID[])) AS requested_role(role_id)
  ) requested
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.user_roles existing
    WHERE existing.user_id = p_target_user_id
      AND existing.role_id = requested.role_id
  );

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'role_id', ur.role_id,
        'branch_id', ur.branch_id,
        'is_active', ur.is_active,
        'assigned_by', ur.assigned_by
      ) ORDER BY ur.role_id
    ),
    '[]'::jsonb
  )
  INTO v_new_roles
  FROM public.user_roles ur
  WHERE ur.user_id = p_target_user_id;

  IF v_old_roles IS DISTINCT FROM v_new_roles THEN
    INSERT INTO public.audit_logs (
      user_id, action, entity_type, entity_id, old_data, new_data
    ) VALUES (
      p_user_id,
      'user_roles.updated',
      'user_roles',
      p_target_user_id,
      jsonb_build_object('roles', v_old_roles),
      jsonb_build_object('roles', v_new_roles)
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.set_user_roles_atomic(UUID, UUID[], UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_user_roles_atomic(UUID, UUID[], UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_user_roles_atomic(UUID, UUID[], UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_user_roles_atomic(UUID, UUID[], UUID) TO service_role;


CREATE OR REPLACE FUNCTION public.set_user_access_atomic(
  p_target_user_id UUID,
  p_role_ids UUID[],
  p_overrides JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_override_result JSONB;
BEGIN
  IF v_actor IS NULL
     OR NOT public.check_permission(v_actor, 'auth.users.update')
     OR NOT public.check_permission(v_actor, 'auth.user_permissions.manage') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية إدارة وصول المستخدمين';
  END IF;

  IF p_target_user_id = v_actor THEN
    RAISE EXCEPTION 'لا يمكن تعديل وصول حسابك الحالي';
  END IF;

  PERFORM 1
  FROM public.profiles
  WHERE id = p_target_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'المستخدم غير موجود';
  END IF;

  -- Both calls participate in this RPC transaction. Any validation or write
  -- failure rolls back role and override changes together.
  PERFORM public.set_user_roles_atomic(p_target_user_id, p_role_ids, v_actor);
  SELECT public.set_user_permission_overrides(p_target_user_id, p_overrides)
  INTO v_override_result;

  RETURN v_override_result;
END;
$$;

REVOKE ALL ON FUNCTION public.set_user_access_atomic(UUID, UUID[], JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_user_access_atomic(UUID, UUID[], JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_user_access_atomic(UUID, UUID[], JSONB) TO authenticated;


-- Preserve the existing profile and access APIs while giving the user edit
-- screen one all-or-nothing operation. A NULL overrides payload means the
-- caller is editing profile/roles only and existing overrides stay untouched.
CREATE OR REPLACE FUNCTION public.update_user_with_access_atomic(
  p_target_user_id UUID,
  p_full_name TEXT,
  p_phone TEXT,
  p_role_ids UUID[],
  p_overrides JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_result JSONB := jsonb_build_object('saved_count', 0, 'changed', false);
BEGIN
  IF v_actor IS NULL OR NOT public.check_permission(v_actor, 'auth.users.update') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية تحديث المستخدمين';
  END IF;

  IF p_target_user_id = v_actor THEN
    RAISE EXCEPTION 'استخدم مسار الملف الشخصي لتعديل حسابك الحالي';
  END IF;

  IF NULLIF(btrim(p_full_name), '') IS NULL THEN
    RAISE EXCEPTION 'اسم المستخدم مطلوب';
  END IF;

  IF p_overrides IS NOT NULL
     AND NOT public.check_permission(v_actor, 'auth.user_permissions.manage') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية إدارة صلاحيات المستخدمين';
  END IF;

  -- Lock and update the same profile row used to serialize access edits.
  PERFORM 1
  FROM public.profiles
  WHERE id = p_target_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'المستخدم غير موجود';
  END IF;

  UPDATE public.profiles
  SET
    full_name = btrim(p_full_name),
    phone = NULLIF(btrim(p_phone), ''),
    updated_at = now()
  WHERE id = p_target_user_id;

  IF p_overrides IS NULL THEN
    -- Preserve the existing profile-edit path: when the requested active role
    -- set is unchanged, do not invoke role mutation or its hierarchy checks.
    IF EXISTS (
      SELECT 1
      FROM (
        (SELECT ur.role_id
         FROM public.user_roles ur
         WHERE ur.user_id = p_target_user_id AND ur.is_active = true
         EXCEPT
         SELECT DISTINCT requested.role_id
         FROM unnest(COALESCE(p_role_ids, ARRAY[]::UUID[])) AS requested(role_id))
        UNION ALL
        (SELECT DISTINCT requested.role_id
         FROM unnest(COALESCE(p_role_ids, ARRAY[]::UUID[])) AS requested(role_id)
         EXCEPT
         SELECT ur.role_id
         FROM public.user_roles ur
         WHERE ur.user_id = p_target_user_id AND ur.is_active = true)
      ) role_delta
    ) THEN
      PERFORM public.set_user_roles_atomic(p_target_user_id, p_role_ids, v_actor);
    END IF;
  ELSE
    SELECT public.set_user_access_atomic(p_target_user_id, p_role_ids, p_overrides)
    INTO v_result;
  END IF;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.update_user_with_access_atomic(UUID, TEXT, TEXT, UUID[], JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_user_with_access_atomic(UUID, TEXT, TEXT, UUID[], JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_user_with_access_atomic(UUID, TEXT, TEXT, UUID[], JSONB) TO authenticated;

-- The browser must not bypass validation/auditing with direct table writes.
REVOKE ALL ON TABLE public.user_permission_overrides FROM anon, authenticated;
-- Preserve the existing authenticated read contract; overrides_select still
-- limits rows through RLS while all direct write and TRUNCATE privileges stay revoked.
GRANT SELECT ON TABLE public.user_permission_overrides TO authenticated;
DROP POLICY IF EXISTS "overrides_write" ON public.user_permission_overrides;
