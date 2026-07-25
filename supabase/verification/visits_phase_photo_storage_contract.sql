-- ============================================================
-- SQL Verification Contract: Visits Phase Photo Storage Verification
-- Location: supabase/verification/visits_phase_photo_storage_contract.sql
-- ============================================================

DO $$
DECLARE
  v_bucket_id TEXT := 'visit-proofs';
  v_bucket_rec RECORD;
  v_rec RECORD;
  v_policy_count INT;
  v_check_failed BOOLEAN := false;
BEGIN
  RAISE NOTICE '════════════════════════════════════════════════════════════';
  RAISE NOTICE 'بدء التحقق من صحة إعدادات سلة الصور والسياسات الأمنية (RLS)...';
  RAISE NOTICE '════════════════════════════════════════════════════════════';

  -- 1. Check if bucket exists and is configured correctly
  SELECT name, public, file_size_limit, allowed_mime_types
  INTO v_bucket_rec
  FROM storage.buckets
  WHERE id = v_bucket_id;

  IF NOT FOUND THEN
    RAISE WARNING '[فشل العقد] السلة ''visit-proofs'' غير موجودة في قاعدة البيانات!';
    v_check_failed := true;
  ELSE
    IF v_bucket_rec.public IS DISTINCT FROM false THEN
      RAISE WARNING '[فشل العقد] السلة ''visit-proofs'' عامة (public = true)، ويجب أن تكون خاصة (private)!';
      v_check_failed := true;
    END IF;

    IF v_bucket_rec.file_size_limit IS DISTINCT FROM 2097152 THEN
      RAISE WARNING '[فشل العقد] حد الحجم المسموح به غير صحيح: % بايت (المطلوب: 2097152 بايت / 2MB)!', v_bucket_rec.file_size_limit;
      v_check_failed := true;
    END IF;

    IF v_bucket_rec.name IS DISTINCT FROM 'visit-proofs' THEN
      RAISE WARNING '[فشل العقد] اسم السلة غير متطابق!';
      v_check_failed := true;
    END IF;

    IF v_bucket_rec.allowed_mime_types IS NULL THEN
      RAISE WARNING '[فشل العقد] أنواع MIME مفقودة!';
      v_check_failed := true;
    ELSIF NOT (v_bucket_rec.allowed_mime_types @> ARRAY['image/jpeg', 'image/png'] AND v_bucket_rec.allowed_mime_types <@ ARRAY['image/jpeg', 'image/png']) THEN
      RAISE WARNING '[فشل العقد] أنواع الملفات MIME المسموح بها غير متطابقة مع المطلوب (image/jpeg, image/png)!';
      v_check_failed := true;
    END IF;
  END IF;

  -- 2. Verify that visit_proofs_select_policy exists and matches SELECT-specific conditions
  SELECT COUNT(*) INTO v_policy_count
  FROM pg_policies
  WHERE tablename = 'objects'
    AND schemaname = 'storage'
    AND policyname = 'visit_proofs_select_policy'
    AND cmd = 'SELECT'
    AND roles = ARRAY['authenticated']::name[]
    AND with_check IS NULL;

  IF v_policy_count = 0 THEN
    RAISE WARNING '[فشل العقد] سياسة القراءة (SELECT) مفقودة أو لا تطابق الشروط (cmd = SELECT, roles = [authenticated] only, with_check = NULL)!';
    v_check_failed := true;
  END IF;

  -- 3. Verify that visit_proofs_insert_policy exists and matches INSERT-specific conditions
  SELECT COUNT(*) INTO v_policy_count
  FROM pg_policies
  WHERE tablename = 'objects'
    AND schemaname = 'storage'
    AND policyname = 'visit_proofs_insert_policy'
    AND cmd = 'INSERT'
    AND roles = ARRAY['authenticated']::name[]
    AND qual IS NULL;

  IF v_policy_count = 0 THEN
    RAISE WARNING '[فشل العقد] سياسة الإدخال (INSERT) مفقودة أو لا تطابق الشروط (cmd = INSERT, roles = [authenticated] only, qual = NULL)!';
    v_check_failed := true;
  END IF;

  -- 4. Verify presence of plan, item, branch and employee verification within SELECT policy USING clause (qual)
  SELECT COUNT(*) INTO v_policy_count
  FROM pg_policies
  WHERE tablename = 'objects'
    AND schemaname = 'storage'
    AND policyname = 'visit_proofs_select_policy'
    AND COALESCE(qual, '') LIKE '%visit_plan_items%'
    AND COALESCE(qual, '') LIKE '%hr_employees%'
    AND COALESCE(qual, '') LIKE '%plans%'
    AND COALESCE(qual, '') LIKE '%items%';

  IF v_policy_count = 0 THEN
    RAISE WARNING '[فشل العقد] سياسة القراءة (SELECT) تفتقر للتحقق الأمني من ملكية الموظف للخطة، البند، أو هيكلية المسارات!';
    v_check_failed := true;
  END IF;

  -- 5. Verify presence of plan, item, employee ownership and update_own permissions within INSERT policy CHECK clause (with_check)
  SELECT COUNT(*) INTO v_policy_count
  FROM pg_policies
  WHERE tablename = 'objects'
    AND schemaname = 'storage'
    AND policyname = 'visit_proofs_insert_policy'
    AND COALESCE(with_check, '') LIKE '%visit-proofs%'
    AND COALESCE(with_check, '') LIKE '%visit_plan_items%'
    AND COALESCE(with_check, '') LIKE '%hr_employees%'
    AND COALESCE(with_check, '') LIKE '%visit_plans.update_own%'
    AND COALESCE(with_check, '') LIKE '%plans%'
    AND COALESCE(with_check, '') LIKE '%items%';

  IF v_policy_count = 0 THEN
    RAISE WARNING '[فشل العقد] سياسة الإدخال (INSERT) تفتقر للتحقق الأمني من ملكية الموظف، البند، السلة، أو الصلاحيات المطلوبة!';
    v_check_failed := true;
  END IF;

  -- 6. Check for unauthorized policies referencing visit-proofs or access violations
  FOR v_rec IN
    SELECT policyname, cmd, roles, qual, with_check
    FROM pg_policies
    WHERE tablename = 'objects'
      AND schemaname = 'storage'
      AND (COALESCE(qual, '') LIKE '%visit-proofs%' OR COALESCE(with_check, '') LIKE '%visit-proofs%')
  LOOP
    -- Must NOT be UPDATE or DELETE
    IF v_rec.cmd IN ('UPDATE', 'DELETE') THEN
      RAISE WARNING '[فشل العقد] تم العثور على سياسة تعديل أو حذف مخصصة لزيارات: %', v_rec.policyname;
      v_check_failed := true;
    END IF;

    -- Must NOT allow anon or public roles
    IF 'anon' = ANY(v_rec.roles) OR 'public' = ANY(v_rec.roles) THEN
      RAISE WARNING '[فشل العقد] السياسة ''%'' تسمح بالوصول للأدوار غير المصرح بها (anon / public)!', v_rec.policyname;
      v_check_failed := true;
    END IF;

    -- SELECT and INSERT must be authenticated only
    IF v_rec.cmd IN ('SELECT', 'INSERT') AND NOT ('authenticated' = ANY(v_rec.roles)) THEN
      RAISE WARNING '[فشل العقد] السياسة ''%'' غير موجهة لدور authenticated صراحة!', v_rec.policyname;
      v_check_failed := true;
    END IF;
  END LOOP;

  -- 7. Check if the forbidden function storage.is_valid_uuid exists
  SELECT COUNT(*) INTO v_policy_count
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'storage' AND p.proname = 'is_valid_uuid';

  IF v_policy_count > 0 THEN
    RAISE WARNING '[فشل العقد] تم الكشف عن وجود الدالة المحظورة storage.is_valid_uuid!';
    v_check_failed := true;
  END IF;

  IF v_check_failed THEN
    RAISE EXCEPTION 'فشل التحقق! سلة التخزين أو السياسات الأمنية لا تطابق العقد البرمجي المطلوب.';
  ELSE
    RAISE NOTICE '✓ نجح التحقق! كافة إعدادات السلة والسياسات والقيود الأمنية متوافقة بالكامل مع العقد البرمجي.';
  END IF;
END $$;
