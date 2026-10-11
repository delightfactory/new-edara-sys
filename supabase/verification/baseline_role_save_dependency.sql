-- Owned synthetic dependency only; original function body, explicit local EXECUTE restriction. Not a production migration.
CREATE OR REPLACE FUNCTION public.update_role_atomic(
  p_role_id     UUID,
  p_name_ar     TEXT        DEFAULT NULL,
  p_description TEXT        DEFAULT NULL,
  p_color       TEXT        DEFAULT NULL,
  p_permissions TEXT[]      DEFAULT NULL,
  p_user_id     UUID        DEFAULT auth.uid()
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_perm TEXT;
BEGIN
  -- [SECURITY GUARD] تطابق الهوية
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- [PERMISSION] فحص صلاحية تحديث الأدوار
  IF NOT check_permission(p_user_id, 'auth.roles.update') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية تحديث الأدوار';
  END IF;

  -- ١. تأكد وجود الدور
  IF NOT EXISTS (SELECT 1 FROM public.roles WHERE id = p_role_id) THEN
    RAISE EXCEPTION 'الدور غير موجود';
  END IF;

  -- ٢. تحديث بيانات الدور
  UPDATE public.roles
  SET
    name_ar     = COALESCE(p_name_ar, name_ar),
    description = COALESCE(p_description, description),
    color       = COALESCE(p_color, color)
  WHERE id = p_role_id;

  -- ٣. استبدال الصلاحيات إذا أُرسلت
  IF p_permissions IS NOT NULL THEN
    DELETE FROM public.role_permissions WHERE role_id = p_role_id;

    FOREACH v_perm IN ARRAY p_permissions
    LOOP
      INSERT INTO public.role_permissions (role_id, permission)
      VALUES (p_role_id, v_perm)
      ON CONFLICT (role_id, permission) DO NOTHING;
    END LOOP;
  END IF;
END;
$$;

-- Owned local configuration: prevent anonymous actor spoofing; keep authenticated permission guard.
REVOKE EXECUTE ON FUNCTION public.update_role_atomic(uuid,text,text,text,text[],uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_role_atomic(uuid,text,text,text,text[],uuid) TO authenticated;
