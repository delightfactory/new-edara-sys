-- Run with ON_ERROR_STOP on an owned local database after the forward migration.
-- Uses the real function and schema; all synthetic records are rolled back.
BEGIN;

DO $$
DECLARE
  actor UUID := gen_random_uuid();
  wildcard_role UUID := gen_random_uuid();
  account_status public.user_status;
BEGIN
  INSERT INTO auth.users (id, email)
  VALUES (actor, actor::TEXT || '@status-gate.invalid');
  INSERT INTO public.profiles (id, full_name, status)
  VALUES (actor, 'Status gate regression', 'active')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.roles (id, name, name_ar)
  VALUES (wildcard_role, 'status-gate-' || actor::TEXT, 'اختبار حالة الحساب');
  INSERT INTO public.role_permissions (role_id, permission)
  VALUES (wildcard_role, '*');
  INSERT INTO public.user_roles (user_id, role_id)
  VALUES (actor, wildcard_role);
  INSERT INTO public.user_permission_overrides
    (user_id, permission, granted, granted_by, expires_at)
  VALUES
    (actor, 'finance.read', false, actor, NULL),
    (actor, 'inventory.read', false, actor, now() - INTERVAL '1 day'),
    (actor, 'reports.read', true, actor, NULL);

  ASSERT public.check_permission(actor, 'customers.read'), 'active wildcard';
  ASSERT NOT public.check_permission(actor, 'finance.read'), 'deny above wildcard';
  ASSERT public.check_permission(actor, 'inventory.read'), 'expired deny falls through';
  ASSERT NOT public.check_permission(NULL, 'customers.read'), 'null actor';
  ASSERT NOT public.check_permission(gen_random_uuid(), 'customers.read'), 'unknown actor';

  FOREACH account_status IN ARRAY ARRAY['inactive', 'suspended']::public.user_status[] LOOP
    UPDATE public.profiles SET status = account_status WHERE id = actor;
    ASSERT NOT public.check_permission(actor, 'customers.read'), 'disabled wildcard';
    ASSERT NOT public.check_permission(actor, 'reports.read'), 'disabled explicit grant';
  END LOOP;
  UPDATE public.profiles SET status = 'active' WHERE id = actor;
  ASSERT public.check_permission(actor, 'customers.read'), 'restored active wildcard';

  UPDATE public.user_roles SET is_active = false WHERE user_id = actor;
  ASSERT NOT public.check_permission(actor, 'customers.read'), 'inactive role';
  ASSERT public.check_permission(actor, 'reports.read'), 'individual grant despite inactive role';
  DELETE FROM public.user_roles WHERE user_id = actor;
  ASSERT public.check_permission(actor, 'reports.read'), 'individual grant without role';
  UPDATE public.user_permission_overrides
  SET expires_at = now() - INTERVAL '1 day'
  WHERE user_id = actor AND permission = 'reports.read';
  ASSERT NOT public.check_permission(actor, 'reports.read'), 'expired individual grant without role';
END;
$$;

ROLLBACK;
