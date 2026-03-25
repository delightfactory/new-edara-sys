-- ========================================================================================
-- 09d_atomic_fixes.sql
-- تحويل العمليات التتابعية (حذف ثم إدراج) إلى عمليات ذرية (Atomic Transactions) لحماية البيانات
-- ========================================================================================

-- -------------------------------------------------------------------------
-- 1. حفظ وحدات المنتج (حذف القديم وإدراج الجديد في خطوة واحدة)
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.save_product_units_atomic(
  p_product_id UUID,
  p_units JSONB, -- Array of objects: [{ unit_id, conversion_factor, selling_price, is_purchase_unit, is_sales_unit }]
  p_user_id UUID DEFAULT auth.uid()
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_unit JSONB;
BEGIN
  -- التحقق من الهوية
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- حذف الوحدات القديمة
  DELETE FROM public.product_units WHERE product_id = p_product_id;

  -- إدراج الوحدات الجديدة
  FOR v_unit IN SELECT * FROM jsonb_array_elements(p_units)
  LOOP
    INSERT INTO public.product_units (product_id, unit_id, conversion_factor, selling_price, is_purchase_unit, is_sales_unit)
    VALUES (
      p_product_id,
      (v_unit->>'unit_id')::UUID,
      (v_unit->>'conversion_factor')::NUMERIC,
      (v_unit->>'selling_price')::NUMERIC,
      COALESCE((v_unit->>'is_purchase_unit')::BOOLEAN, false),
      COALESCE((v_unit->>'is_sales_unit')::BOOLEAN, true)
    );
  END LOOP;
END;
$$;


-- -------------------------------------------------------------------------
-- 2. تحديث باقة المنتجات (تحديث الباقة + حذف وإدراج البنود)
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_bundle_atomic(
  p_bundle_id UUID,
  p_name TEXT,
  p_sku TEXT,
  p_price NUMERIC,
  p_is_active BOOLEAN,
  p_items JSONB, -- Array of objects: [{ product_id, unit_id, quantity }]
  p_user_id UUID DEFAULT auth.uid()
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item JSONB;
BEGIN
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- تحديث بيانات الباقة
  UPDATE public.product_bundles
  SET
    name = COALESCE(p_name, name),
    sku = COALESCE(p_sku, sku),
    price = COALESCE(p_price, price),
    is_active = COALESCE(p_is_active, is_active),
    updated_at = now()
  WHERE id = p_bundle_id;

  -- إذا تم تمرير بنود لتحديثها
  IF p_items IS NOT NULL THEN
    -- حذف البنود القديمة
    DELETE FROM public.product_bundle_items WHERE bundle_id = p_bundle_id;

    -- إدراج البنود الجديدة
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
      INSERT INTO public.product_bundle_items (bundle_id, product_id, unit_id, quantity)
      VALUES (
        p_bundle_id,
        (v_item->>'product_id')::UUID,
        (v_item->>'unit_id')::UUID,
        (v_item->>'quantity')::NUMERIC
      );
    END LOOP;
  END IF;
END;
$$;


-- -------------------------------------------------------------------------
-- 3. تعيين أدوار المستخدم
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_user_roles_atomic(
  p_target_user_id UUID,
  p_role_ids UUID[],
  p_user_id UUID DEFAULT auth.uid()
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

  -- التأكد أن المستخدم المستهدف موجود بالبروفايلات
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_target_user_id) THEN
    RAISE EXCEPTION 'المستخدم غير موجود';
  END IF;

  -- حذف الأدوار القديمة
  DELETE FROM public.user_roles WHERE user_id = p_target_user_id;

  -- إدراج الأدوار الجديدة
  IF p_role_ids IS NOT NULL THEN
    FOREACH v_role_id IN ARRAY p_role_ids
    LOOP
      INSERT INTO public.user_roles (user_id, role_id)
      VALUES (p_target_user_id, v_role_id);
    END LOOP;
  END IF;
END;
$$;


-- -------------------------------------------------------------------------
-- 4. تحديث دور وإصدار صلاحياته
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_role_atomic(
  p_role_id UUID,
  p_name_ar TEXT,
  p_description TEXT,
  p_color TEXT,
  p_permissions TEXT[],
  p_user_id UUID DEFAULT auth.uid()
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_perm TEXT;
BEGIN
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- تحديث بيانات الدور
  UPDATE public.roles
  SET
    name_ar = COALESCE(p_name_ar, name_ar),
    description = COALESCE(p_description, description),
    color = COALESCE(p_color, color),
    updated_at = now()
  WHERE id = p_role_id;

  -- إذا تم توفير قائمة صلاحيات، نقوم بالاستبدال
  IF p_permissions IS NOT NULL THEN
    DELETE FROM public.role_permissions WHERE role_id = p_role_id;

    FOREACH v_perm IN ARRAY p_permissions
    LOOP
      INSERT INTO public.role_permissions (role_id, permission)
      VALUES (p_role_id, v_perm);
    END LOOP;
  END IF;
END;
$$;

-- -------------------------------------------------------------------------
-- 5. إحصائيات مستخدمي الأدوار بشكل مجمع (GROUP BY)
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_roles_user_count()
RETURNS TABLE(role_id UUID, count BIGINT)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role_id, COUNT(*)
  FROM public.user_roles
  WHERE is_active = true
  GROUP BY role_id;
$$;
