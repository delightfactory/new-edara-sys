-- ============================================================
-- 05_auth_fixes.sql
-- إصلاح: إعادة إنشاء update_role_atomic مع check_permission guard
-- السبب: خطأ 400 Bad Request عند استدعاء update_role_atomic
-- ============================================================

-- ─── إعادة إنشاء update_role_atomic ───────────────────────────────────────
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

-- منح تشغيل للمصادقين
GRANT EXECUTE ON FUNCTION public.update_role_atomic TO authenticated;


-- ─── إعادة إنشاء set_user_roles_atomic (احتياطي) ──────────────────────────
CREATE OR REPLACE FUNCTION public.set_user_roles_atomic(
  p_target_user_id UUID,
  p_role_ids        UUID[],
  p_user_id         UUID DEFAULT auth.uid()
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_role_id UUID;
BEGIN
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  IF NOT check_permission(p_user_id, 'auth.users.update') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية تحديث المستخدمين';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_target_user_id) THEN
    RAISE EXCEPTION 'المستخدم غير موجود';
  END IF;

  DELETE FROM public.user_roles WHERE user_id = p_target_user_id;

  IF p_role_ids IS NOT NULL THEN
    FOREACH v_role_id IN ARRAY p_role_ids
    LOOP
      INSERT INTO public.user_roles (user_id, role_id)
      VALUES (p_target_user_id, v_role_id)
      ON CONFLICT (user_id, role_id) DO NOTHING;
    END LOOP;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_user_roles_atomic TO authenticated;


-- ─── التأكد من وجود UNIQUE constraint على role_permissions ──────────────
DO $$
BEGIN
  -- إضافة UNIQUE constraint إذا لم يكن موجوداً لمنع التكرار
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'role_permissions_role_id_permission_key'
      AND conrelid = 'public.role_permissions'::regclass
  ) THEN
    ALTER TABLE public.role_permissions
      ADD CONSTRAINT role_permissions_role_id_permission_key
      UNIQUE (role_id, permission);
  END IF;
END;
$$;
