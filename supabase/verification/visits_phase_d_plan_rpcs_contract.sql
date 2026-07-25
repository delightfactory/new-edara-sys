-- =============================================================================
-- EDARA v2 — visits_phase_d_plan_rpcs_contract.sql
-- سكريبت تحقق ساكن وقارئ فقط (SELECT ONLY) لتدقيق المرحلة د (RPCs الذرية وإدارة منع التكرار)
-- يعيد هذا السكريبت صفوفاً فقط في حال وجود مخالفات للالتزامات الأمنية والهيكلية
--
-- ⚠️ تنبيه إخلاء المسؤولية (Disclaimer):
-- إذا لم تكن هناك قاعدة بيانات محلية نشطة (Local Database Container)، فإن هذا التحقق
-- يُعتبر تحليلاً تناظرياً وساكناً (Analog / Static Verification) فقط لتوجيه المطور أثناء التدقيق.
-- =============================================================================

-- ─── 1. التحقق من وجود RPCs العامة وتواقيعها وصلاحياتها بالترتيب والأنواع ───

WITH expected_public_rpcs AS (
  SELECT * FROM (VALUES
    ('public', 'create_visit_plan_atomic', 'p_operation_id uuid, p_employee_id uuid, p_plan_date date, p_plan_type character varying, p_notes text, p_items jsonb'),
    ('public', 'confirm_visit_plan_atomic', 'p_operation_id uuid, p_plan_id uuid'),
    ('public', 'cancel_visit_plan_atomic', 'p_operation_id uuid, p_plan_id uuid, p_cancellation_reason text'),
    ('public', 'reorder_visit_plan_items_atomic', 'p_operation_id uuid, p_plan_id uuid, p_reorder_data jsonb'),
    ('public', 'close_visit_plan_administratively_atomic', 'p_operation_id uuid, p_plan_id uuid, p_close_reason text')
  ) AS t(fn_schema, fn_name, expected_args)
)
SELECT
    '1.A. PUBLIC_RPC_SIGNATURE_MISMATCH_OR_OVERLOAD' AS audit_rule,
    er.fn_schema,
    er.fn_name,
    p.oid::regprocedure AS actual_signature
FROM expected_public_rpcs er
JOIN pg_catalog.pg_namespace n ON n.nspname = er.fn_schema
LEFT JOIN pg_catalog.pg_proc p ON p.proname = er.fn_name AND p.pronamespace = n.oid
WHERE p.proname IS NULL
   OR pg_catalog.format_type(p.prorettype, NULL) != 'jsonb'
   OR pg_catalog.pg_get_function_arguments(p.oid) IS DISTINCT FROM er.expected_args;


-- ─── 2. التحقق من وجود دوال التنفيذ المميز وتواقيعها وصلاحياتها بالترتيب والأنواع ───

WITH expected_private_rpcs AS (
  SELECT * FROM (VALUES
    ('private', 'create_visit_plan_atomic_impl', 'p_operation_id uuid, p_employee_id uuid, p_plan_date date, p_plan_type character varying, p_notes text, p_items jsonb'),
    ('private', 'confirm_visit_plan_atomic_impl', 'p_operation_id uuid, p_plan_id uuid'),
    ('private', 'cancel_visit_plan_atomic_impl', 'p_operation_id uuid, p_plan_id uuid, p_cancellation_reason text'),
    ('private', 'reorder_visit_plan_items_atomic_impl', 'p_operation_id uuid, p_plan_id uuid, p_reorder_data jsonb'),
    ('private', 'close_visit_plan_administratively_atomic_impl', 'p_operation_id uuid, p_plan_id uuid, p_close_reason text')
  ) AS t(fn_schema, fn_name, expected_args)
)
SELECT
    '2.A. PRIVATE_IMPL_SIGNATURE_MISMATCH_OR_OVERLOAD' AS audit_rule,
    er.fn_schema,
    er.fn_name,
    p.oid::regprocedure AS actual_signature
FROM expected_private_rpcs er
JOIN pg_catalog.pg_namespace n ON n.nspname = er.fn_schema
LEFT JOIN pg_catalog.pg_proc p ON p.proname = er.fn_name AND p.pronamespace = n.oid
WHERE p.proname IS NULL
   OR pg_catalog.format_type(p.prorettype, NULL) != 'jsonb'
   OR pg_catalog.pg_get_function_arguments(p.oid) IS DISTINCT FROM er.expected_args;


-- ─── 3. التحقق من عدم وجود overloads إضافية مقيدة بالمخطط ───

SELECT
    '3.A. RPC_DUPLICATE_OVERLOAD_DETECTED' AS audit_rule,
    n.nspname AS schema_name,
    p.proname AS function_name
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname IN ('public', 'private')
  AND p.proname IN (
    'create_visit_plan_atomic', 'create_visit_plan_atomic_impl',
    'confirm_visit_plan_atomic', 'confirm_visit_plan_atomic_impl',
    'cancel_visit_plan_atomic', 'cancel_visit_plan_atomic_impl',
    'reorder_visit_plan_items_atomic', 'reorder_visit_plan_items_atomic_impl',
    'close_visit_plan_administratively_atomic', 'close_visit_plan_administratively_atomic_impl'
  )
GROUP BY n.nspname, p.proname
HAVING pg_catalog.count(p.oid) > 1;


-- ─── 4. التحقق من أمان الخصائص البرمجية والـ search_path للـ RPCs العامة والخاصة ───

WITH expected_properties AS (
  SELECT * FROM (VALUES
    ('public', 'create_visit_plan_atomic', false, ARRAY['search_path=pg_catalog']),
    ('public', 'confirm_visit_plan_atomic', false, ARRAY['search_path=pg_catalog']),
    ('public', 'cancel_visit_plan_atomic', false, ARRAY['search_path=pg_catalog']),
    ('public', 'reorder_visit_plan_items_atomic', false, ARRAY['search_path=pg_catalog']),
    ('public', 'close_visit_plan_administratively_atomic', false, ARRAY['search_path=pg_catalog']),

    ('private', 'create_visit_plan_atomic_impl', true, ARRAY['search_path=pg_catalog']),
    ('private', 'confirm_visit_plan_atomic_impl', true, ARRAY['search_path=pg_catalog']),
    ('private', 'cancel_visit_plan_atomic_impl', true, ARRAY['search_path=pg_catalog']),
    ('private', 'reorder_visit_plan_items_atomic_impl', true, ARRAY['search_path=pg_catalog']),
    ('private', 'close_visit_plan_administratively_atomic_impl', true, ARRAY['search_path=pg_catalog'])
  ) AS t(fn_schema, fn_name, is_definer, expected_config)
)
SELECT
    '4.A. RPC_SECURITY_BREACH_OR_UNSAFE_PATH' AS audit_rule,
    p.oid::regprocedure AS function_signature,
    p.prosecdef AS actual_definer,
    p.proconfig AS actual_config
FROM expected_properties ep
JOIN pg_catalog.pg_namespace n ON n.nspname = ep.fn_schema
LEFT JOIN pg_catalog.pg_proc p ON p.proname = ep.fn_name AND p.pronamespace = n.oid
WHERE p.proname IS NULL
   OR p.prosecdef != ep.is_definer
   OR (ep.expected_config IS NOT NULL AND NOT (p.proconfig @> ep.expected_config));


-- ─── 5. التحقق من الربط الهيكلي الصحيح والكامل للـ Wrappers بالـ impl المقابل وحظر التعديلات ───

WITH expected_wrapper_map AS (
  SELECT * FROM (VALUES
    ('public', 'create_visit_plan_atomic', 'private', 'create_visit_plan_atomic_impl'),
    ('public', 'confirm_visit_plan_atomic', 'private', 'confirm_visit_plan_atomic_impl'),
    ('public', 'cancel_visit_plan_atomic', 'private', 'cancel_visit_plan_atomic_impl'),
    ('public', 'reorder_visit_plan_items_atomic', 'private', 'reorder_visit_plan_items_atomic_impl'),
    ('public', 'close_visit_plan_administratively_atomic', 'private', 'close_visit_plan_administratively_atomic_impl')
  ) AS t(wrap_schema, wrap_name, impl_schema, impl_name)
)
SELECT
    '5.A. INVALID_PUBLIC_WRAPPER_IMPLEMENTATION' AS audit_rule,
    w.wrap_schema || '.' || w.wrap_name AS wrapper_name,
    p.oid::regprocedure AS actual_wrapper_signature
FROM expected_wrapper_map w
JOIN pg_catalog.pg_namespace n ON n.nspname = w.wrap_schema
LEFT JOIN pg_catalog.pg_proc p ON p.proname = w.wrap_name AND p.pronamespace = n.oid
WHERE p.proname IS NULL
   OR (SELECT l.lanname FROM pg_catalog.pg_language l WHERE l.oid = p.prolang) != 'sql'
   OR p.prosecdef = true
   OR pg_catalog.format_type(p.prorettype, NULL) != 'jsonb'
   OR p.prosrc NOT ILIKE '%' || w.impl_schema || '.' || w.impl_name || '%'
   OR EXISTS (
     SELECT 1 FROM expected_wrapper_map other
     WHERE other.impl_name != w.impl_name
       AND p.prosrc ILIKE '%' || other.impl_schema || '.' || other.impl_name || '%'
   )
   OR p.prosrc ILIKE '%INSERT%'
   OR p.prosrc ILIKE '%UPDATE%'
   OR p.prosrc ILIKE '%DELETE%';


-- ─── 6. التحقق من سحب صلاحية EXECUTE للدوال وتأمينها للأدوار غير المخولة (PUBLIC / anon) ───

SELECT
    '6.A. RPC_EXECUTE_PRIVILEGE_LEAK' AS audit_rule,
    n.nspname AS schema_name,
    p.proname AS function_name,
    CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee) END AS grantee,
    x.privilege_type
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) x
WHERE (n.nspname = 'public' OR n.nspname = 'private')
  AND p.proname IN (
    'create_visit_plan_atomic', 'create_visit_plan_atomic_impl',
    'confirm_visit_plan_atomic', 'confirm_visit_plan_atomic_impl',
    'cancel_visit_plan_atomic', 'cancel_visit_plan_atomic_impl',
    'reorder_visit_plan_items_atomic', 'reorder_visit_plan_items_atomic_impl',
    'close_visit_plan_administratively_atomic', 'close_visit_plan_administratively_atomic_impl'
  )
  AND (x.grantee = 0 OR pg_get_userbyid(x.grantee) IN ('anon'));


-- ─── 7. التحقق من منح EXECUTE المباشر للدور authenticated على العامة والخاصة ───

WITH expected_rpcs AS (
  SELECT * FROM (VALUES
    ('public', 'create_visit_plan_atomic'),
    ('public', 'confirm_visit_plan_atomic'),
    ('public', 'cancel_visit_plan_atomic'),
    ('public', 'reorder_visit_plan_items_atomic'),
    ('public', 'close_visit_plan_administratively_atomic'),

    ('private', 'create_visit_plan_atomic_impl'),
    ('private', 'confirm_visit_plan_atomic_impl'),
    ('private', 'cancel_visit_plan_atomic_impl'),
    ('private', 'reorder_visit_plan_items_atomic_impl'),
    ('private', 'close_visit_plan_administratively_atomic_impl')
  ) AS t(fn_schema, fn_name)
)
SELECT
    '7.A. RPC_MISSING_AUTHENTICATED_GRANT' AS audit_rule,
    er.fn_schema,
    er.fn_name
FROM expected_rpcs er
JOIN pg_catalog.pg_namespace n ON n.nspname = er.fn_schema
LEFT JOIN pg_catalog.pg_proc p ON p.proname = er.fn_name AND p.pronamespace = n.oid
WHERE p.proname IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) x
    WHERE pg_catalog.pg_get_userbyid(x.grantee) = 'authenticated'
      AND x.privilege_type = 'EXECUTE'
  );


-- ─── 8. التحقق من حظر وجود SQLERRM نهائياً في الدوال ───

SELECT
    '8.A. SQLERRM_USAGE_FOUND' AS audit_rule,
    p.proname AS function_name
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE (n.nspname = 'public' OR n.nspname = 'private')
  AND p.proname IN (
    'create_visit_plan_atomic', 'create_visit_plan_atomic_impl',
    'confirm_visit_plan_atomic', 'confirm_visit_plan_atomic_impl',
    'cancel_visit_plan_atomic', 'cancel_visit_plan_atomic_impl',
    'reorder_visit_plan_items_atomic', 'reorder_visit_plan_items_atomic_impl',
    'close_visit_plan_administratively_atomic', 'close_visit_plan_administratively_atomic_impl'
  )
  AND p.prosrc ILIKE '%SQLERRM%';


-- ─── 9. التحقق من وجود المعاملة الفرعية (nested exception block) للتراجع في impl ───

SELECT
    '9.A. NESTED_EXCEPTION_BLOCK_MISSING' AS audit_rule,
    p.proname AS function_name
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'private'
  AND p.proname IN (
    'create_visit_plan_atomic_impl',
    'confirm_visit_plan_atomic_impl',
    'cancel_visit_plan_atomic_impl',
    'reorder_visit_plan_items_atomic_impl',
    'close_visit_plan_administratively_atomic_impl'
  )
  AND p.prosrc NOT ILIKE '%EXCEPTION WHEN OTHERS%';


-- ─── 10. التحقق من وجود قفل صفوف البنود صراحة في impl ───

SELECT
    '10.A. VISIT_ITEM_LOCKING_MISSING' AS audit_rule,
    p.proname AS function_name
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'private'
  AND p.proname IN (
    'confirm_visit_plan_atomic_impl',
    'cancel_visit_plan_atomic_impl',
    'reorder_visit_plan_items_atomic_impl',
    'close_visit_plan_administratively_atomic_impl'
  )
  AND p.prosrc NOT ILIKE '%FOR UPDATE%';


-- ─── 11. التحقق من عدم وجود أي منح صلاحيات مباشر على جداول المخطط private للأدوار العامة ───

SELECT
    '11.A. DIRECT_PRIVILEGE_LEAK_ON_PRIVATE_SCHEMA' AS audit_rule,
    r.relname AS table_name,
    CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee) END AS grantee,
    x.privilege_type
FROM pg_catalog.pg_class r
JOIN pg_catalog.pg_namespace n ON n.oid = r.relnamespace
CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(r.relacl, pg_catalog.acldefault('r', r.relowner))) x
WHERE n.nspname = 'private'
  AND (
    x.grantee = 0
    OR pg_catalog.pg_get_userbyid(x.grantee) IN ('anon', 'authenticated')
  );


-- ─── 12. التحقق من صلاحيات المخطط private (USAGE فقط لـ authenticated وحظر البقية) ───

SELECT
    '12.A. SCHEMA_USAGE_OR_CREATE_LEAK_ON_PRIVATE' AS audit_rule,
    n.nspname AS schema_name,
    CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee) END AS grantee,
    x.privilege_type
FROM pg_catalog.pg_namespace n
CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(n.nspacl, pg_catalog.acldefault('n', n.nspowner))) x
WHERE n.nspname = 'private'
  AND x.privilege_type IN ('USAGE', 'CREATE')
  AND (
    x.grantee = 0
    OR pg_catalog.pg_get_userbyid(x.grantee) = 'anon'
    OR (
      pg_catalog.pg_get_userbyid(x.grantee) = 'authenticated'
      AND x.privilege_type = 'CREATE'
    )
  );

-- ─── 13. التحقق من وجود USAGE لـ authenticated على المخطط private ───

SELECT
    '13.A. SCHEMA_USAGE_MISSING_FOR_AUTHENTICATED' AS audit_rule,
    'private' AS schema_name
FROM pg_catalog.pg_namespace n
WHERE n.nspname = 'private'
  AND NOT EXISTS (
    SELECT 1
    FROM pg_catalog.aclexplode(COALESCE(n.nspacl, pg_catalog.acldefault('n', n.nspowner))) x
    WHERE pg_catalog.pg_get_userbyid(x.grantee) = 'authenticated'
      AND x.privilege_type = 'USAGE'
  );


-- ─── 14. تطابق نطاق مدة الزيارة مع الواجهة وRPC إضافة البند ───
SELECT
    '14.A. CREATE_DURATION_RANGE_MISSING' AS audit_rule,
    p.proname
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'private'
  AND p.proname = 'create_visit_plan_atomic_impl'
  AND (
    p.prosrc NOT ILIKE '%v_duration < 5%'
    OR p.prosrc NOT ILIKE '%v_duration > 480%'
  );


-- 15. تأهيل pgcrypto حسب المخطط الفعلي
WITH expected(fn_name) AS (
  VALUES
    ('create_visit_plan_atomic_impl'),
    ('confirm_visit_plan_atomic_impl'),
    ('cancel_visit_plan_atomic_impl'),
    ('reorder_visit_plan_items_atomic_impl'),
    ('close_visit_plan_administratively_atomic_impl')
)
SELECT
  '15.A. DIGEST_SCHEMA_INVALID' AS audit_rule,
  e.fn_name
FROM expected e
LEFT JOIN pg_catalog.pg_namespace n ON n.nspname = 'private'
LEFT JOIN pg_catalog.pg_proc p ON p.pronamespace = n.oid AND p.proname = e.fn_name
WHERE p.oid IS NULL
   OR p.prosrc NOT ILIKE '%extensions.digest%'
   OR p.prosrc ILIKE '%public.digest%';
