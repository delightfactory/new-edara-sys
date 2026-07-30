-- Give the field app an actionable, safe reason when a visit cannot be skipped.
-- The previous handler collapsed every business validation error (including
-- plan ownership) into a misleading message about payload length.
DO $migration$
DECLARE
  v_definition text;
  v_updated_definition text;
  v_pattern text :=
    'IF SQLSTATE = ''P0001'' THEN\r?\n\s+v_safe_code := ''DOMAIN_VALIDATION_FAILED'';\r?\n\s+v_safe_message := ''تعذر تخطي الزيارة لعدم استيفاء الشروط أو تجاوز طول البيانات'';\r?\n\s+ELSE';
  v_replacement text := $replacement$IF SQLSTATE = 'P0001' THEN
      CASE
        WHEN SQLERRM LIKE 'سبب تخطي الزيارة%' THEN
          v_safe_code := 'INVALID_SKIP_REASON';
          v_safe_message := left(SQLERRM, 250);
        WHEN SQLERRM = 'لم يتم العثور على سجل موظف نشط مرتبط بالمستخدم الحالي في النظام' THEN
          v_safe_code := 'EMPLOYEE_NOT_FOUND';
          v_safe_message := 'لا يوجد سجل موظف نشط مرتبط بهذا الحساب';
        WHEN SQLERRM IN (
          'ليس لديك صلاحية تحديث بنود الخطة الخاصة بك',
          'لا يمكنك تعديل بند خطة مسندة لموظف آخر',
          'فرع الموظف الحالي لا يطابق الفرع التنظيمي للخطة'
        ) THEN
          v_safe_code := 'NOT_PLAN_OWNER';
          v_safe_message := 'هذه الخطة مسندة لمندوب آخر ولا يمكن تنفيذها من هذا الحساب';
        WHEN SQLERRM = 'البند مرتبط بنشاط فعال ولا يمكن تخطيه' THEN
          v_safe_code := 'ACTIVE_ACTIVITY_EXISTS';
          v_safe_message := 'بدأت الزيارة بالفعل؛ أنهِ الزيارة الجارية بدلاً من تخطيها';
        WHEN SQLERRM = 'لا يمكن تخطي بند إلا في خطة مؤكدة أو جارية' THEN
          v_safe_code := 'PLAN_NOT_EXECUTABLE';
          v_safe_message := 'الخطة ليست في حالة تسمح بالتخطي؛ حدّث الصفحة وراجع حالتها';
        WHEN SQLERRM = 'المنطقة الزمنية للجهاز غير صالحة' THEN
          v_safe_code := 'INVALID_DEVICE_TIMEZONE';
          v_safe_message := 'تعذر قراءة المنطقة الزمنية للجهاز؛ أعد ضبط الوقت تلقائياً ثم حاول مجدداً';
        WHEN SQLERRM = 'بند خطة الزيارة غير موجود' THEN
          v_safe_code := 'VISIT_NOT_FOUND';
          v_safe_message := 'الزيارة غير موجودة أو تم حذفها؛ حدّث الخطة';
        ELSE
          v_safe_code := 'DOMAIN_VALIDATION_FAILED';
          v_safe_message := 'تعذر تخطي الزيارة بسبب حالتها الحالية؛ حدّث الخطة ثم حاول مجدداً';
      END CASE;
    ELSE$replacement$;
BEGIN
  SELECT pg_get_functiondef(
    'private.skip_visit_item_atomic_impl(uuid,uuid,text,timestamptz,character varying)'::regprocedure
  ) INTO v_definition;

  v_updated_definition := regexp_replace(v_definition, v_pattern, v_replacement);
  IF v_updated_definition = v_definition THEN
    RAISE EXCEPTION 'skip_visit_item_atomic_impl validation handler was not found';
  END IF;

  -- Normalize whitespace before persistence as a final server-side guard.
  v_updated_definition := replace(
    v_updated_definition,
    'skip_reason = p_skip_reason,',
    'skip_reason = BTRIM(p_skip_reason),'
  );

  EXECUTE v_updated_definition;
END;
$migration$;
