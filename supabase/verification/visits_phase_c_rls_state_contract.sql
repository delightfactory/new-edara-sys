-- =============================================================================
-- EDARA v2 — visits_phase_c_rls_state_contract.sql
-- سكريبت تحقق ساكن وقارئ فقط (SELECT ONLY) لتدقيق المرحلة ج (RLS وآلة الحالات والـ Gates)
-- يعيد هذا السكريبت صفوفاً فقط في حال وجود مخالفات للالتزامات الأمنية والهيكلية
--
-- ⚠️ تنبيه إخلاء المسؤولية (Disclaimer):
-- إذا لم تكن هناك قاعدة بيانات محلية نشطة (Local Database Container)، فإن هذا التحقق
-- يُعتبر تحليلاً تناظرياً وساكناً (Analog / Static Verification) فقط لتوجيه المطور أثناء التدقيق.
-- =============================================================================

-- ─── 1. التحقق من تفعيل RLS وغياب السياسات العامة FOR ALL والسياسات القديمة ───

SELECT
    '1.A. RLS_NOT_ENABLED_OR_ALL_POLICY_LEAK' AS audit_rule,
    c.relname AS table_name,
    p.polname AS policy_name
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_catalog.pg_policy p ON p.polrelid = c.oid
WHERE n.nspname = 'public'
  AND c.relname IN ('visit_plans', 'visit_plan_items')
  AND (
    c.relrowsecurity = false -- RLS غير مفعل
    OR p.polname = 'vp_write' -- السياسة القديمة مسربة
    OR p.polname = 'vpi_write'
    OR p.polcmd = '*' -- وجود سياسة FOR ALL
  );


-- ─── 2. التحقق من هيكل وتواجد سياسات RLS الجديدة بالتفصيل ───

WITH expected_policies AS (
  SELECT * FROM (VALUES
    ('public', 'visit_plans', 'vp_read', 'SELECT', ARRAY['authenticated'::name]),
    ('public', 'visit_plans', 'vp_insert', 'INSERT', ARRAY['authenticated'::name]),
    ('public', 'visit_plans', 'vp_update', 'UPDATE', ARRAY['authenticated'::name]),
    ('public', 'visit_plan_items', 'vpi_read', 'SELECT', ARRAY['authenticated'::name]),
    ('public', 'visit_plan_items', 'vpi_insert', 'INSERT', ARRAY['authenticated'::name]),
    ('public', 'visit_plan_items', 'vpi_update', 'UPDATE', ARRAY['authenticated'::name]),
    ('public', 'visit_plan_items', 'vpi_delete', 'DELETE', ARRAY['authenticated'::name])
  ) AS t(table_schema, table_name, policy_name, cmd_type, roles)
)
SELECT
    '2.A. POLICY_MISSING_OR_MISCONFIGURED' AS audit_rule,
    ep.table_schema,
    ep.table_name,
    ep.policy_name,
    p.cmd AS actual_cmd,
    p.roles AS actual_roles
FROM expected_policies ep
LEFT JOIN pg_catalog.pg_policies p
  ON p.schemaname = ep.table_schema
  AND p.tablename = ep.table_name
  AND p.policyname = ep.policy_name
WHERE p.policyname IS NULL
   OR p.cmd != ep.cmd_type
   OR NOT (p.roles @> ep.roles AND p.roles <@ ep.roles);


-- ─── 3. التحقق من شروط الـ UPDATE ووجود USING و WITH CHECK معاً ───

SELECT
    '3.A. UPDATE_POLICY_CHECK_MISSING' AS audit_rule,
    c.relname AS table_name,
    p.polname AS policy_name
FROM pg_policy p
JOIN pg_class c ON c.oid = p.polrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('visit_plans', 'visit_plan_items')
  AND p.polcmd = 'w' -- UPDATE
  AND (p.polqual IS NULL OR p.polwithcheck IS NULL);


-- ─── 4. التحقق من نصوص السياسات الجوهرية (فحص فريق الفرع وقيد draft للبنود) ───

SELECT
    '4.A. POLICY_QUAL_MISSING_KEYWORDS' AS audit_rule,
    schemaname,
    tablename,
    policyname,
    qual,
    with_check
FROM pg_catalog.pg_policies
WHERE (
  -- vp_read و vpi_read يجب أن تحتوي على فحص فريق الفرع التنظيمي
  (policyname IN ('vp_read', 'vpi_read') AND qual NOT ILIKE '%read_team%')
  -- vpi_insert و vpi_delete يجب أن تقتصر على حالة draft فقط
  OR (policyname IN ('vpi_insert', 'vpi_delete') AND COALESCE(qual, with_check) NOT ILIKE '%draft%')
  -- vp_insert يجب أن تشترط تطابق الفرع والـ created_by
  OR (policyname = 'vp_insert' AND (with_check NOT ILIKE '%created_by%' OR with_check NOT ILIKE '%branch_id%'))
);


-- ─── 5. التحقق من غياب شرط الفرع الحالي من تحديث الخطط التاريخية لتمكين النقل ───

SELECT
    '5.A. VP_UPDATE_POLICY_HISTORICAL_BRANCH_VIOLATION' AS audit_rule,
    policyname,
    qual,
    with_check
FROM pg_catalog.pg_policies
WHERE (schemaname = 'public' AND tablename = 'visit_plans' AND policyname = 'vp_update')
  AND (
    (qual ILIKE '%branch_id = employee_id%' OR with_check ILIKE '%branch_id = employee_id%')
    OR (qual ILIKE '%branch_id = (SELECT branch_id FROM hr_employees WHERE id = employee_id)%'
        OR with_check ILIKE '%branch_id = (SELECT branch_id FROM hr_employees WHERE id = employee_id)%')
  )
  -- يسمح فقط بشرط الفرع التاريخي داخل المسودة ولا يفرضه بشكل عام للتحديثات التاريخية
  AND NOT (COALESCE(qual, with_check) ILIKE '%draft%' AND COALESCE(qual, with_check) ILIKE '%update_own%');


-- ─── 6. التحقق من حظر استخدام متغيرات الجلسة GUC تماماً ───

SELECT
    '6.A. PROHIBITED_SESSION_GUC_USAGE' AS audit_rule,
    n.nspname AS schema_name,
    p.proname AS function_name,
    p.prosrc AS code_definition
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname IN ('public', 'private')
  AND p.proname ILIKE '%visit%'
  AND (
    p.prosrc ILIKE '%recalculating_visit_plan%'
    OR p.prosrc ILIKE '%set_config%'
    OR p.prosrc ILIKE '%current_setting%'
  );


-- ─── 7. التحقق من غياب الدوال العامة الحساسة والـ SECURITY DEFINER بالخطأ ───

SELECT
    '7.A. SENSITIVE_PUBLIC_FUNCTION_LEAK' AS audit_rule,
    n.nspname AS schema_name,
    p.proname AS function_name,
    p.prosecdef AS is_definer
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE (
  -- غياب الدوال العامة القديمة تماماً
  (n.nspname = 'public' AND p.proname IN ('recalculate_visit_plan_counts', 'trg_recalculate_visit_plan_counts'))
  -- التحقق من عدم وجود أي SECURITY DEFINER متعلق بالزيارات داخل المخطط العام public
  OR (
    n.nspname = 'public'
    AND p.prosecdef = true
    AND p.proname ILIKE '%visit%'
    -- Legacy bridge removed atomically by phase E; it remains expected at phase C.
    AND p.proname <> 'sync_visit_item_from_activity'
  )
);


-- ─── 8. التحقق من تواجد تريجرات آلة الحالات والـ Recalc وتوافق شروطها وربطها ───

WITH expected_triggers AS (
  -- tgtype: 1 = ROW, 2 = BEFORE, 4 = INSERT, 8 = DELETE, 16 = UPDATE
  -- BEFORE ROW UPDATE: 1 + 2 + 16 = 19
  -- AFTER ROW INSERT/DELETE/UPDATE: 1 + 4 + 8 + 16 = 29
  SELECT * FROM (VALUES
    ('public', 'visit_plans', 'trg_visit_plans_state_machine', 'private', 'trg_visit_plans_state_machine', 19::int2, NULL::text),
    ('public', 'visit_plan_items', 'trg_visit_plan_items_state_machine', 'private', 'trg_visit_plan_items_state_machine', 19::int2, NULL::text),
    ('public', 'visit_plan_items', 'trg_visit_plan_items_recalc', 'private', 'trg_recalculate_visit_plan_counts', 29::int2, 'plan_id,status')
  ) AS t(table_schema, table_name, trigger_name, fn_schema, fn_name, expected_tgtype, expected_columns)
)
SELECT
    '8.A. TRIGGER_MISCONFIGURED' AS audit_rule,
    et.table_schema,
    et.table_name,
    et.trigger_name,
    tg.oid IS NULL AS is_missing,
    tg.tgenabled <> 'O' AS is_disabled,
    tg.tgisinternal AS is_internal,
    pron.nspname AS fn_schema,
    p.proname AS fn_name,
    tg.tgtype AS actual_tgtype,
    (
      SELECT pg_catalog.array_to_string(pg_catalog.array_agg(att.attname ORDER BY att.attname), ',')
      FROM pg_catalog.pg_attribute att
      WHERE att.attrelid = tg.tgrelid
        AND att.attnum = ANY(tg.tgattr::int2[])
    ) AS actual_columns
FROM expected_triggers et
LEFT JOIN pg_catalog.pg_namespace n ON n.nspname = et.table_schema
LEFT JOIN pg_catalog.pg_class c ON c.relname = et.table_name AND c.relnamespace = n.oid
LEFT JOIN pg_catalog.pg_trigger tg ON tg.tgrelid = c.oid AND tg.tgname = et.trigger_name
LEFT JOIN pg_catalog.pg_proc p ON p.oid = tg.tgfoid
LEFT JOIN pg_catalog.pg_namespace pron ON pron.oid = p.pronamespace
WHERE tg.oid IS NULL
   OR tg.tgenabled <> 'O'
   OR tg.tgisinternal = true
   OR pron.nspname != et.fn_schema
   OR p.proname != et.fn_name
   OR tg.tgtype IS DISTINCT FROM et.expected_tgtype
   OR (
     et.expected_columns IS NOT NULL AND
     COALESCE((
       SELECT pg_catalog.array_to_string(pg_catalog.array_agg(att.attname ORDER BY att.attname), ',')
       FROM pg_catalog.pg_attribute att
       WHERE att.attrelid = tg.tgrelid
         AND att.attnum = ANY(tg.tgattr::int2[])
     ), '') != et.expected_columns
   );


-- ─── 9. التحقق من أمان الخصائص البرمجية والـ search_path للدوال الجديدة ───

WITH expected_fns AS (
  SELECT * FROM (VALUES
    ('private', 'recalculate_visit_plan_counts', true, ARRAY['search_path=pg_catalog']),
    ('private', 'trg_recalculate_visit_plan_counts', true, ARRAY['search_path=pg_catalog']),
    ('private', 'trg_visit_plans_state_machine', false, NULL::text[]),
    ('private', 'trg_visit_plan_items_state_machine', false, NULL::text[])
  ) AS t(fn_schema, fn_name, is_definer, expected_config)
)
SELECT
    '9.A. FUNCTION_SECURITY_BREACH' AS audit_rule,
    p.oid::regprocedure AS function_signature,
    p.prosecdef AS actual_definer,
    p.proconfig AS actual_config
FROM expected_fns ef
JOIN pg_catalog.pg_namespace n ON n.nspname = ef.fn_schema
LEFT JOIN pg_catalog.pg_proc p ON p.proname = ef.fn_name AND p.pronamespace = n.oid
WHERE p.proname IS NULL -- كشف غياب الدالة بالـ LEFT JOIN
   OR p.prosecdef != ef.is_definer
   OR (ef.expected_config IS NOT NULL AND NOT (p.proconfig @> ef.expected_config));


-- ─── 10. التحقق من سحب صلاحية EXECUTE للدوال وتأمينها للأدوار غير المخولة ───

SELECT
    '10.A. FUNCTION_EXECUTE_PRIVILEGE_LEAK' AS audit_rule,
    n.nspname AS schema_name,
    p.proname AS function_name,
    CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee) END AS grantee,
    x.privilege_type
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) x
WHERE n.nspname IN ('public', 'private')
  AND p.proname IN ('recalculate_visit_plan_counts', 'trg_recalculate_visit_plan_counts', 'trg_visit_plans_state_machine', 'trg_visit_plan_items_state_machine')
  AND (x.grantee = 0 OR pg_get_userbyid(x.grantee) IN ('anon', 'authenticated'));


-- ─── 11. التحقق من حماية metadata والبيانات التعريفية الأساسية ───

SELECT
    '11.A. METADATA_PROTECTION_MISSING' AS audit_rule,
    p.proname AS function_name,
    p.prosrc AS code_definition
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'private'
  AND (
    (p.proname = 'trg_visit_plans_state_machine' AND (p.prosrc NOT ILIKE '%created_by%' OR p.prosrc NOT ILIKE '%created_at%' OR p.prosrc NOT ILIKE '%id%'))
    OR
    (p.proname = 'trg_visit_plan_items_state_machine' AND (p.prosrc NOT ILIKE '%plan_id%' OR p.prosrc NOT ILIKE '%created_at%' OR p.prosrc NOT ILIKE '%id%'))
  );


-- ─── 12. التحقق من قفل الخطط النهائية واستثناء الإغلاق الإداري بالـ JSONB ───

SELECT
    '12.A. PLAN_FINAL_LOCK_JSONB_MISSING' AS audit_rule,
    p.proname AS function_name,
    p.prosrc AS code_definition
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'private'
  AND p.proname = 'trg_visit_plans_state_machine'
  AND (
    p.prosrc NOT ILIKE '%to_jsonb(NEW) - ARRAY%'
    OR p.prosrc NOT ILIKE '%administrative_closed_by%'
    OR p.prosrc NOT ILIKE '%administrative_closed_at%'
    OR p.prosrc NOT ILIKE '%administrative_close_reason%'
  );


-- ─── 13. التحقق من حماية بنود الزيارات والـ GPS (بما في ذلك مصفوفة انتقالات الحالات والقرار الحصري) ───

SELECT
    '13.A. ITEM_AND_GPS_SECURITY_MISSING' AS audit_rule,
    p.proname AS function_name,
    p.prosrc AS code_definition
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'private'
  AND p.proname = 'trg_visit_plan_items_state_machine'
  AND (
    p.prosrc NOT ILIKE '%to_jsonb(NEW) - ARRAY%'
    OR p.prosrc NOT ILIKE '%customer_id%'
    OR p.prosrc NOT ILIKE '%expected_location_source%'
    OR p.prosrc NOT ILIKE '%approved%'
    OR p.prosrc NOT ILIKE '%rejected%'
    OR p.prosrc NOT ILIKE '%not_required%'
    OR p.prosrc NOT ILIKE '%pending%'
    -- التحقق من الانتقالات الحصرية الحتمية وتجميد القرار وقيد الصلاحية والتوقيت بالسيرفر
    OR p.prosrc NOT ILIKE '%OLD.gps_review_status = ''not_required'' AND NEW.gps_review_status != ''pending''%'
    OR p.prosrc NOT ILIKE '%OLD.gps_review_status = ''pending'' AND NEW.gps_review_status NOT IN (''approved'', ''rejected'')%'
    OR p.prosrc NOT ILIKE '%OLD.gps_review_status IN (''approved'', ''rejected'')%'
    OR p.prosrc NOT ILIKE '%(SELECT auth.uid())%'
    OR p.prosrc NOT ILIKE '%clock_timestamp()%'
    OR p.prosrc NOT ILIKE '%review_gps%'
  );


-- ─── 14. التحقق من قيود الإغلاق الإداري وتأكيد الخطة ───

SELECT
    '14.A. ADMINISTRATIVE_CLOSE_OR_CONFIRM_CHECK_MISSING' AS audit_rule,
    p.proname AS function_name,
    p.prosrc AS code_definition
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'private'
  AND p.proname = 'trg_visit_plans_state_machine'
  AND (
    p.prosrc NOT ILIKE '%OLD.status NOT IN (''completed'', ''partial'', ''missed'')%'
    OR p.prosrc NOT ILIKE '%close_administrative%'
    OR p.prosrc NOT ILIKE '%skipped_count%'
    OR p.prosrc NOT ILIKE '%visit_plans.confirm%'
  );


-- ─── 15. التحقق من حيازة الأدوار للصلاحيات ───

WITH expected_perms AS (
  SELECT * FROM (VALUES
    ('sales_supervisor', 'visit_plans.close_administrative'),
    ('sales_supervisor', 'visit_plans.review_gps'),
    ('branch_manager', 'visit_plans.close_administrative'),
    ('branch_manager', 'visit_plans.review_gps'),
    ('ceo', 'visit_plans.close_administrative'),
    ('ceo', 'visit_plans.review_gps'),
    ('ceo', 'visit_plans.create'),
    ('ceo', 'visit_plans.update'),
    ('ceo', 'visit_plans.confirm'),
    ('ceo', 'visit_plans.cancel'),
    ('sales_rep', 'visit_plans.update_own')
  ) AS t(role_name, perm_name)
)
SELECT
    '15.A. ROLE_PERMISSION_MISSING' AS audit_rule,
    ep.role_name,
    ep.perm_name
FROM expected_perms ep
LEFT JOIN public.role_permissions rp
  ON rp.permission = ep.perm_name
  AND rp.role_id = (SELECT id FROM public.roles WHERE name = ep.role_name)
WHERE rp.permission IS NULL;


-- ─── 16. منع رجوع متغيرات العدادات التنفيذية غير المعلنة ───
SELECT
    '16.A. STATE_MACHINE_COUNTER_DECLARATION_MISSING' AS audit_rule,
    p.proname
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'private'
  AND p.proname = 'trg_visit_plans_state_machine'
  AND (
    p.prosrc !~* 'v_pending[[:space:]]+INTEGER'
    OR p.prosrc !~* 'v_in_progress[[:space:]]+INTEGER'
  );


-- ─── 17. منع تأهيل COALESCE باسم schema داخل دالة إعادة حساب الخطة ───
SELECT
    '17.A. PLAN_COUNTER_RECALC_COALESCE_INVALID' AS audit_rule,
    'private.recalculate_visit_plan_counts(uuid)' AS function_name
WHERE NOT EXISTS (
  SELECT 1
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'private'
    AND p.proname = 'recalculate_visit_plan_counts'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_plan_id uuid'
    AND p.prosrc NOT LIKE '%pg_catalog.coalesce(%'
    AND p.prosrc LIKE '%COALESCE(completed_at, pg_catalog.clock_timestamp())%'
    AND p.prosecdef = true
    AND p.proconfig IS NOT NULL
    AND 'search_path=pg_catalog' = ANY(p.proconfig)
);


-- ─── 18. ضمان تأهيل check_permission داخل تريجرات آلة الحالات ───
WITH expected(function_name, expected_count) AS (
  VALUES
    ('trg_visit_plans_state_machine'::TEXT, 3),
    ('trg_visit_plan_items_state_machine'::TEXT, 1)
)
SELECT
  '18.A. STATE_TRIGGER_PERMISSION_RESOLUTION_INVALID' AS audit_rule,
  expected.function_name
FROM expected
LEFT JOIN LATERAL (
  SELECT p.prosrc
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'private'
    AND p.proname = expected.function_name
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) = ''
) actual ON true
WHERE actual.prosrc IS NULL
   OR actual.prosrc LIKE '%(SELECT check_permission(%'
   OR (
     (
       pg_catalog.length(actual.prosrc)
       - pg_catalog.length(pg_catalog.replace(actual.prosrc, '(SELECT public.check_permission(', ''))
     ) / pg_catalog.length('(SELECT public.check_permission(')
   ) <> expected.expected_count;
