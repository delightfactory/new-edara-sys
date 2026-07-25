-- =============================================================================
-- EDARA v2 — visits_phase_b_schema_contract.sql
-- سكريبت تحقق ساكن وقارئ فقط (SELECT ONLY) لتدقيق صحة هيكل بيانات المرحلة ب
-- يعيد هذا السكريبت صفوفاً فقط في حال وجود مخالفات للالتزامات الهيكلية أو الأمنية أو البيانات
--
-- ⚠️ تنبيه إخلاء المسؤولية (Disclaimer):
-- إذا لم تكن هناك قاعدة بيانات محلية نشطة (Local Database Container)، فإن هذا التحقق
-- يُعتبر تحليلاً تناظرياً وساكناً (Analog / Static Verification) فقط لتوجيه المطور أثناء التدقيق.
-- =============================================================================

-- ─── 1. التحقق من وجود المخطط والجداول والأعمدة وخصائصها (نوع البيانات، القيمة الافتراضية، وقبول القيم الفارغة) ───

WITH expected_columns AS (
  SELECT * FROM (VALUES
    -- private.visit_operation_requests
    ('private', 'visit_operation_requests', 'operation_id', 'uuid', 'NO', NULL),
    ('private', 'visit_operation_requests', 'actor_id', 'uuid', 'NO', NULL),
    ('private', 'visit_operation_requests', 'operation_name', 'character varying', 'NO', NULL),
    ('private', 'visit_operation_requests', 'request_hash', 'character varying', 'NO', NULL),
    ('private', 'visit_operation_requests', 'status', 'character varying', 'NO', '''pending''::character varying'),
    ('private', 'visit_operation_requests', 'result_json', 'jsonb', 'YES', NULL),
    ('private', 'visit_operation_requests', 'error_code', 'character varying', 'YES', NULL),
    ('private', 'visit_operation_requests', 'created_at', 'timestamp with time zone', 'NO', 'clock_timestamp()'),
    ('private', 'visit_operation_requests', 'started_at', 'timestamp with time zone', 'YES', NULL),
    ('private', 'visit_operation_requests', 'completed_at', 'timestamp with time zone', 'YES', NULL),
    ('private', 'visit_operation_requests', 'updated_at', 'timestamp with time zone', 'NO', 'clock_timestamp()'),

    -- private.visit_sync_conflicts
    ('private', 'visit_sync_conflicts', 'id', 'uuid', 'NO', 'gen_random_uuid()'),
    ('private', 'visit_sync_conflicts', 'operation_id', 'uuid', 'NO', NULL),
    ('private', 'visit_sync_conflicts', 'visit_plan_item_id', 'uuid', 'NO', NULL),
    ('private', 'visit_sync_conflicts', 'actor_id', 'uuid', 'NO', NULL),
    ('private', 'visit_sync_conflicts', 'operation_name', 'character varying', 'NO', NULL),
    ('private', 'visit_sync_conflicts', 'conflict_reason_code', 'character varying', 'NO', NULL),
    ('private', 'visit_sync_conflicts', 'conflict_payload', 'jsonb', 'NO', NULL),
    ('private', 'visit_sync_conflicts', 'status', 'character varying', 'NO', '''pending''::character varying'),
    ('private', 'visit_sync_conflicts', 'reviewed_by', 'uuid', 'YES', NULL),
    ('private', 'visit_sync_conflicts', 'reviewed_at', 'timestamp with time zone', 'YES', NULL),
    ('private', 'visit_sync_conflicts', 'review_notes', 'text', 'YES', NULL),
    ('private', 'visit_sync_conflicts', 'created_at', 'timestamp with time zone', 'NO', 'clock_timestamp()'),
    ('private', 'visit_sync_conflicts', 'updated_at', 'timestamp with time zone', 'NO', 'clock_timestamp()'),

    -- public.visit_plans
    ('public', 'visit_plans', 'organizational_branch_id', 'uuid', 'YES', NULL),
    ('public', 'visit_plans', 'rescheduled_count', 'integer', 'NO', '0'),
    ('public', 'visit_plans', 'administrative_closed_at', 'timestamp with time zone', 'YES', NULL),
    ('public', 'visit_plans', 'administrative_closed_by', 'uuid', 'YES', NULL),
    ('public', 'visit_plans', 'administrative_close_reason', 'text', 'YES', NULL),
    ('public', 'visit_plans', 'closure_pct', 'numeric', 'YES', NULL),

    -- public.visit_plan_items
    ('public', 'visit_plan_items', 'customer_branch_id', 'uuid', 'YES', NULL),
    ('public', 'visit_plan_items', 'expected_location_source', 'character varying', 'YES', NULL),
    ('public', 'visit_plan_items', 'expected_location_id', 'uuid', 'YES', NULL),
    ('public', 'visit_plan_items', 'expected_lat', 'numeric', 'YES', NULL),
    ('public', 'visit_plan_items', 'expected_lng', 'numeric', 'YES', NULL),
    ('public', 'visit_plan_items', 'start_lat', 'numeric', 'YES', NULL),
    ('public', 'visit_plan_items', 'start_lng', 'numeric', 'YES', NULL),
    ('public', 'visit_plan_items', 'start_accuracy_m', 'numeric', 'YES', NULL),
    ('public', 'visit_plan_items', 'start_distance_m', 'numeric', 'YES', NULL),
    ('public', 'visit_plan_items', 'end_lat', 'numeric', 'YES', NULL),
    ('public', 'visit_plan_items', 'end_lng', 'numeric', 'YES', NULL),
    ('public', 'visit_plan_items', 'end_accuracy_m', 'numeric', 'YES', NULL),
    ('public', 'visit_plan_items', 'end_distance_m', 'numeric', 'YES', NULL),
    ('public', 'visit_plan_items', 'server_started_at', 'timestamp with time zone', 'YES', NULL),
    ('public', 'visit_plan_items', 'server_completed_at', 'timestamp with time zone', 'YES', NULL),
    ('public', 'visit_plan_items', 'client_started_at', 'timestamp with time zone', 'YES', NULL),
    ('public', 'visit_plan_items', 'client_completed_at', 'timestamp with time zone', 'YES', NULL),
    ('public', 'visit_plan_items', 'device_timezone', 'character varying', 'YES', NULL),
    ('public', 'visit_plan_items', 'gps_validation_status', 'character varying', 'NO', '''not_checked''::character varying'),
    ('public', 'visit_plan_items', 'gps_review_status', 'character varying', 'NO', '''not_required''::character varying'),
    ('public', 'visit_plan_items', 'gps_exception_reason', 'text', 'YES', NULL),
    ('public', 'visit_plan_items', 'gps_exception_requested_by', 'uuid', 'YES', NULL),
    ('public', 'visit_plan_items', 'gps_exception_reviewed_by', 'uuid', 'YES', NULL),
    ('public', 'visit_plan_items', 'gps_exception_reviewed_at', 'timestamp with time zone', 'YES', NULL),
    ('public', 'visit_plan_items', 'rescheduled_from_item_id', 'uuid', 'YES', NULL),
    ('public', 'visit_plan_items', 'replacement_item_id', 'uuid', 'YES', NULL),
    ('public', 'visit_plan_items', 'stale_since', 'timestamp with time zone', 'YES', NULL)
  ) AS t(table_schema, table_name, column_name, data_type, is_nullable, column_default)
)
SELECT
    '1.B. SCHEMA_COLUMN_DISCREPANCY' AS audit_rule,
    ec.table_schema,
    ec.table_name,
    ec.column_name,
    c.data_type AS actual_data_type,
    c.is_nullable AS actual_is_nullable,
    c.column_default AS actual_column_default
FROM expected_columns ec
LEFT JOIN information_schema.columns c
  ON c.table_schema = ec.table_schema
  AND c.table_name = ec.table_name
  AND c.column_name = ec.column_name
WHERE c.column_name IS NULL
   OR c.data_type != ec.data_type
   OR c.is_nullable != ec.is_nullable
   OR (ec.column_default IS NOT NULL AND c.column_default IS DISTINCT FROM ec.column_default);


-- ─── 2. التحقق من الأعمدة المولدة لـ closure_pct وصحة معادلتها ───

SELECT
    '2.B. GENERATED_COLUMN_DISCREPANCY' AS audit_rule,
    table_schema,
    table_name,
    column_name,
    is_generated
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'visit_plans'
  AND column_name = 'closure_pct'
  AND is_generated != 'ALWAYS';


-- ─── 3. التحقق من المفاتيح الخارجية وسلوك الحذف (Foreign Keys & Delete Action) ───

WITH expected_fks AS (
  SELECT * FROM (VALUES
    ('private', 'visit_operation_requests', 'actor_id', 'public', 'profiles', 'id', 'r'), -- 'r' = RESTRICT
    ('private', 'visit_sync_conflicts', 'operation_id', 'private', 'visit_operation_requests', 'operation_id', 'r'),
    ('private', 'visit_sync_conflicts', 'visit_plan_item_id', 'public', 'visit_plan_items', 'id', 'r'),
    ('private', 'visit_sync_conflicts', 'actor_id', 'public', 'profiles', 'id', 'r'),
    ('private', 'visit_sync_conflicts', 'reviewed_by', 'public', 'profiles', 'id', 'r'),
    ('public', 'visit_plans', 'organizational_branch_id', 'public', 'branches', 'id', 'r'),
    ('public', 'visit_plans', 'administrative_closed_by', 'public', 'profiles', 'id', 'r'),
    ('public', 'visit_plan_items', 'customer_branch_id', 'public', 'customer_branches', 'id', 'r'),
    ('public', 'visit_plan_items', 'gps_exception_requested_by', 'public', 'profiles', 'id', 'r'),
    ('public', 'visit_plan_items', 'gps_exception_reviewed_by', 'public', 'profiles', 'id', 'r'),
    ('public', 'visit_plan_items', 'rescheduled_from_item_id', 'public', 'visit_plan_items', 'id', 'r'),
    ('public', 'visit_plan_items', 'replacement_item_id', 'public', 'visit_plan_items', 'id', 'r')
  ) AS t(source_schema, source_table, source_column, target_schema, target_table, target_column, delete_rule)
)
SELECT
    '3.B. FK_DISCREPANCY' AS audit_rule,
    ef.source_schema,
    ef.source_table,
    ef.source_column,
    ef.target_schema,
    ef.target_table,
    ef.target_column,
    ef.delete_rule AS expected_rule,
    afk.delete_rule AS actual_rule
FROM expected_fks ef
LEFT JOIN (
  SELECT
    ns.nspname AS source_schema,
    cl.relname AS source_table,
    att.attname AS source_column,
    tns.nspname AS target_schema,
    tcl.relname AS target_table,
    tatt.attname AS target_column,
    c.confdeltype AS delete_rule
  FROM pg_catalog.pg_constraint c
  JOIN pg_catalog.pg_namespace ns ON ns.oid = c.connamespace
  JOIN pg_catalog.pg_class cl ON cl.oid = c.conrelid
  JOIN pg_catalog.pg_class tcl ON tcl.oid = c.confrelid
  JOIN pg_catalog.pg_namespace tns ON tns.oid = tcl.relnamespace
  CROSS JOIN LATERAL unnest(c.conkey) WITH ORDINALITY k(attnum, ord)
  JOIN pg_catalog.pg_attribute att ON att.attrelid = cl.oid AND att.attnum = k.attnum
  JOIN pg_catalog.pg_attribute tatt ON tatt.attrelid = tcl.oid AND tatt.attnum = c.confkey[k.ord]
  WHERE c.contype = 'f'
) afk ON afk.source_schema = ef.source_schema
     AND afk.source_table = ef.source_table
     AND afk.source_column = ef.source_column
     AND afk.target_schema = ef.target_schema
     AND afk.target_table = ef.target_table
     AND afk.target_column = ef.target_column
WHERE afk.source_table IS NULL
   OR afk.delete_rule != ef.delete_rule;


-- ─── 4. التحقق من قيود التحقق (CHECK Constraints Content Audit) ───

WITH expected_checks AS (
  SELECT * FROM (VALUES
    ('private', 'visit_operation_requests', 'chk_hexadecimal', ARRAY['request_hash', '64']),
    ('private', 'visit_operation_requests', 'chk_status', ARRAY['status', 'pending', 'processing', 'completed', 'failed']),
    ('private', 'visit_operation_requests', 'chk_op_lifecycle', ARRAY['status', 'pending', 'processing', 'completed', 'failed', 'started_at', 'completed_at', 'created_at']),
    ('private', 'visit_operation_requests', 'chk_failed_op_error', ARRAY['status', 'failed', 'error_code']),
    ('private', 'visit_sync_conflicts', 'chk_sync_status', ARRAY['status', 'pending', 'resolved_accepted', 'resolved_rejected']),
    ('private', 'visit_sync_conflicts', 'chk_sync_conflict_lifecycle', ARRAY['status', 'pending', 'resolved_accepted', 'resolved_rejected', 'reviewed_by', 'reviewed_at']),
    ('private', 'visit_sync_conflicts', 'chk_conflict_payload_is_object', ARRAY['conflict_payload', 'jsonb_typeof', 'object']),
    ('public', 'visit_plans', 'chk_rescheduled_count', ARRAY['rescheduled_count']),
    ('public', 'visit_plans', 'chk_closure_pct_range', ARRAY['closure_pct', '0', '100']),
    ('public', 'visit_plan_items', 'chk_expected_location_source', ARRAY['expected_location_source', 'customer', 'customer_branch']),
    ('public', 'visit_plan_items', 'chk_gps_validation_status', ARRAY['gps_validation_status', 'not_checked', 'passed', 'failed_distance', 'failed_accuracy', 'no_coordinates']),
    ('public', 'visit_plan_items', 'chk_gps_review_status', ARRAY['gps_review_status', 'not_required', 'pending', 'approved', 'rejected']),
    ('public', 'visit_plan_items', 'chk_expected_coords', ARRAY['expected_lat', 'expected_lng', '-90', '90', '-180', '180']),
    ('public', 'visit_plan_items', 'chk_start_coords', ARRAY['start_lat', 'start_lng', '-90', '90', '-180', '180']),
    ('public', 'visit_plan_items', 'chk_end_coords', ARRAY['end_lat', 'end_lng', '-90', '90', '-180', '180']),
    ('public', 'visit_plan_items', 'chk_expected_pair', ARRAY['expected_lat', 'expected_lng']),
    ('public', 'visit_plan_items', 'chk_start_pair', ARRAY['start_lat', 'start_lng']),
    ('public', 'visit_plan_items', 'chk_end_pair', ARRAY['end_lat', 'end_lng']),
    ('public', 'visit_plan_items', 'chk_start_accuracy_nonneg', ARRAY['start_accuracy_m']),
    ('public', 'visit_plan_items', 'chk_start_distance_nonneg', ARRAY['start_distance_m']),
    ('public', 'visit_plan_items', 'chk_end_accuracy_nonneg', ARRAY['end_accuracy_m']),
    ('public', 'visit_plan_items', 'chk_end_distance_nonneg', ARRAY['end_distance_m']),
    ('public', 'visit_plan_items', 'chk_no_self_reschedule', ARRAY['rescheduled_from_item_id']),
    ('public', 'visit_plan_items', 'chk_no_self_replacement', ARRAY['replacement_item_id']),
    ('public', 'visit_plan_items', 'chk_server_times', ARRAY['server_completed_at', 'server_started_at']),
    ('public', 'visit_plan_items', 'chk_client_times', ARRAY['client_completed_at', 'client_started_at']),
    ('public', 'visit_plan_items', 'chk_gps_review_lifecycle', ARRAY['gps_review_status', 'gps_exception_reason', 'gps_exception_requested_by', 'gps_exception_reviewed_by', 'gps_exception_reviewed_at']),
    ('public', 'visit_plan_items', 'chk_expected_location_snapshot', ARRAY['expected_location_source', 'expected_location_id', 'expected_lat', 'expected_lng'])
  ) AS t(table_schema, table_name, constraint_name, keywords)
)
SELECT
    '4.C. CHECK_CONSTRAINT_DISCREPANCY' AS audit_rule,
    ec.table_schema,
    ec.table_name,
    ec.constraint_name,
    pg_get_constraintdef(con.oid) AS actual_definition
FROM expected_checks ec
JOIN pg_catalog.pg_namespace n ON n.nspname = ec.table_schema
JOIN pg_catalog.pg_class cl ON cl.relname = ec.table_name AND cl.relnamespace = n.oid
LEFT JOIN pg_catalog.pg_constraint con ON con.conrelid = cl.oid AND con.conname = ec.constraint_name AND con.contype = 'c'
WHERE con.oid IS NULL
   OR EXISTS (
     SELECT 1
     FROM unnest(ec.keywords) kw
     WHERE pg_get_constraintdef(con.oid) NOT ILIKE '%' || kw || '%'
   );


-- ─── 5. التحقق من وجود الفهارس وتفردها وترتيب الأعمدة والشرط الجزئي ───

WITH expected_indexes AS (
  SELECT * FROM (VALUES
    ('public', 'visit_plans', 'idx_visit_plans_branch_date', 'organizational_branch_id,plan_date', false, false, ARRAY[]::text[]),
    ('public', 'visit_plan_items', 'idx_visit_plan_items_cust_branch', 'customer_branch_id', false, false, ARRAY[]::text[]),
    ('public', 'visit_plan_items', 'idx_visit_plan_items_gps_pending', 'gps_review_status', false, true, ARRAY['gps_review_status', 'pending']),
    ('public', 'visit_plan_items', 'idx_visit_plan_items_stale', 'stale_since', false, true, ARRAY['stale_since', 'not null']),
    ('public', 'visit_plan_items', 'idx_visit_plan_items_rescheduled_from_unique', 'rescheduled_from_item_id', true, true, ARRAY['rescheduled_from_item_id', 'not null']),
    ('public', 'visit_plan_items', 'idx_visit_plan_items_replacement_unique', 'replacement_item_id', true, true, ARRAY['replacement_item_id', 'not null']),
    ('private', 'visit_operation_requests', 'idx_visit_op_requests_status', 'status', false, false, ARRAY[]::text[]),
    ('private', 'visit_operation_requests', 'idx_visit_op_requests_created_at', 'created_at', false, false, ARRAY[]::text[]),
    ('private', 'visit_operation_requests', 'idx_visit_op_requests_cleanup', 'completed_at', false, true, ARRAY['status', 'completed', 'failed']),
    ('private', 'visit_sync_conflicts', 'idx_visit_sync_conflicts_item', 'visit_plan_item_id', false, false, ARRAY[]::text[]),
    ('private', 'visit_sync_conflicts', 'idx_visit_sync_conflicts_status', 'status', false, false, ARRAY[]::text[])
  ) AS t(table_schema, table_name, index_name, columns, is_unique, is_partial, predicate_fragments)
)
SELECT
    '5.B. INDEX_DISCREPANCY' AS audit_rule,
    ei.table_schema,
    ei.table_name,
    ei.index_name,
    ei.columns AS expected_columns,
    ei.is_unique AS expected_unique,
    ei.is_partial AS expected_partial,
    aidx.columns AS actual_columns,
    aidx.is_unique AS actual_unique,
    aidx.is_partial AS actual_partial,
    aidx.predicate AS actual_predicate
FROM expected_indexes ei
LEFT JOIN (
  SELECT
    ns.nspname AS table_schema,
    cl.relname AS table_name,
    icl.relname AS index_name,
    ins.nspname AS index_schema,
    i.indisunique AS is_unique,
    (i.indpred IS NOT NULL) AS is_partial,
    pg_catalog.pg_get_expr(i.indpred, i.indrelid) AS predicate,
    array_to_string(array_agg(att.attname ORDER BY k.ord), ',') AS columns
  FROM pg_catalog.pg_index i
  JOIN pg_catalog.pg_class cl ON cl.oid = i.indrelid
  JOIN pg_catalog.pg_namespace ns ON ns.oid = cl.relnamespace
  JOIN pg_catalog.pg_class icl ON icl.oid = i.indexrelid
  JOIN pg_catalog.pg_namespace ins ON ins.oid = icl.relnamespace
  CROSS JOIN LATERAL unnest(i.indkey) WITH ORDINALITY k(attnum, ord)
  JOIN pg_catalog.pg_attribute att ON att.attrelid = cl.oid AND att.attnum = k.attnum
  GROUP BY ns.nspname, cl.relname, icl.relname, ins.nspname, i.indisunique, i.indpred, i.indrelid
) aidx ON aidx.table_schema = ei.table_schema
      AND aidx.table_name = ei.table_name
      AND aidx.index_name = ei.index_name
      AND aidx.index_schema = aidx.table_schema
WHERE aidx.index_name IS NULL
   OR aidx.columns != ei.columns
   OR aidx.is_unique != ei.is_unique
   OR aidx.is_partial != ei.is_partial
   OR EXISTS (
     SELECT 1
     FROM unnest(ei.predicate_fragments) f
     WHERE aidx.predicate NOT ILIKE '%' || f || '%'
   );


-- ─── 6. التحقق من أمان المخطط RLS والجداول الخاصة وصلاحيات الأدوار ───

-- 6.أ. التحقق من RLS للجداول الخاصة
SELECT
    '6.A. PRIVATE_TABLE_RLS_VIOLATION' AS audit_rule,
    c.relname AS table_name,
    c.relrowsecurity AS is_rls_enabled
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'private'
  AND c.relname IN ('visit_operation_requests', 'visit_sync_conflicts')
  AND c.relrowsecurity = false;

-- 6.ب. التحقق من عدم وجود أي سياسات (Policies) على جداول المخطط private لمنع التسريب
SELECT
    '6.B. PRIVATE_TABLE_POLICIES_LEAK' AS audit_rule,
    policyname,
    tablename
FROM pg_catalog.pg_policies
WHERE schemaname = 'private'
  AND tablename IN ('visit_operation_requests', 'visit_sync_conflicts');

-- 6.ج. التحقق من حظر صلاحيات Schema USAGE أو CREATE للأدوار العامة والمسجلة
SELECT
    '6.C. SCHEMA_PRIVILEGE_LEAK' AS audit_rule,
    role_name,
    privilege_type
FROM (
  VALUES ('anon', 'USAGE'), ('anon', 'CREATE'),
         ('authenticated', 'CREATE')
) t(role_name, privilege_type)
WHERE has_schema_privilege(role_name, 'private', privilege_type) = true

UNION ALL

SELECT
    '6.C. SCHEMA_PRIVILEGE_LEAK' AS audit_rule,
    'authenticated' AS role_name,
    'USAGE' AS privilege_type
WHERE has_schema_privilege('authenticated', 'private', 'USAGE') = true
  AND (
    SELECT COUNT(DISTINCT p.proname)
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
  ) <> 5

UNION ALL

SELECT
    '6.C. SCHEMA_PRIVILEGE_LEAK' AS audit_rule,
    CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee) END AS role_name,
    x.privilege_type
FROM pg_catalog.pg_namespace n
CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(n.nspacl, pg_catalog.acldefault('n', n.nspowner))) x
WHERE n.nspname = 'private'
  AND (x.grantee = 0 OR pg_get_userbyid(x.grantee) = 'anon');

-- 6.د. التحقق من عدم وجود أي Table Grants للأدوار العامة والمسجلة على جداول private
SELECT
    '6.D. TABLE_GRANT_LEAK' AS audit_rule,
    grantee,
    table_name,
    privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'private'
  AND table_name IN ('visit_operation_requests', 'visit_sync_conflicts')
  AND grantee IN ('PUBLIC', 'anon', 'authenticated');

-- 6.هـ. التحقق من عدم وجود منح صريح ضمن Default Privileges الخاصة بالمخطط private.
-- لا نستخدم acldefault() هنا لأنه يعيد صلاحية EXECUTE العامة الافتراضية في PostgreSQL
-- حتى عند غياب أي Default ACL صريح خاص بالمخطط، ما ينتج إنذاراً كاذباً.
SELECT
    '6.E. DEFAULT_ACL_DISCREPANCY' AS audit_rule,
    n.nspname AS schema_name,
    a.defaclobjtype AS object_type,
    CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee) END AS grantee,
    x.privilege_type
FROM pg_catalog.pg_default_acl a
JOIN pg_catalog.pg_namespace n ON n.oid = a.defaclnamespace
CROSS JOIN LATERAL pg_catalog.aclexplode(a.defaclacl) x
WHERE n.nspname = 'private'
  AND a.defaclobjtype IN ('r', 'f')
  AND (x.grantee = 0 OR pg_get_userbyid(x.grantee) IN ('anon', 'authenticated'));


-- ─── 7. التحقق من صحة وسلامة البيانات والـ Backfill والـ Constraints بعد التطبيق ───

-- 7.أ. التحقق من أن الخطط التاريخية التي كانت موجودة وقت الـBackfill وحصلت على الموظف لم تترك فارغة الفرع بلا سبب
SELECT
    '7.A. PLAN_BACKFILL_MISSING' AS audit_rule,
    vp.id AS plan_id,
    vp.employee_id,
    emp.branch_id AS employee_branch_id
FROM public.visit_plans vp
JOIN public.hr_employees emp ON emp.id = vp.employee_id
WHERE vp.organizational_branch_id IS NULL
  AND emp.branch_id IS NOT NULL;

-- 7.ب. التحقق من مطابقة جميع عدادات الخطط المباشرة مع البنود الفعلية
SELECT
    '7.B. PLAN_COUNTERS_MISMATCH' AS audit_rule,
    vp.id AS plan_id,
    vp.total_customers AS stored_total,
    counts.total_count AS actual_total,
    vp.completed_count AS stored_completed,
    counts.completed_count AS actual_completed,
    vp.skipped_count AS stored_skipped,
    counts.skipped_count AS actual_skipped,
    vp.missed_count AS stored_missed,
    counts.missed_count AS actual_missed,
    vp.rescheduled_count AS stored_rescheduled,
    counts.rescheduled_count AS actual_rescheduled
FROM public.visit_plans vp
JOIN (
  SELECT
    p.id AS plan_id,
    COUNT(i.id) AS total_count,
    COUNT(i.id) FILTER (WHERE i.status = 'completed') AS completed_count,
    COUNT(i.id) FILTER (WHERE i.status = 'skipped') AS skipped_count,
    COUNT(i.id) FILTER (WHERE i.status = 'missed') AS missed_count,
    COUNT(i.id) FILTER (WHERE i.status = 'rescheduled') AS rescheduled_count
  FROM public.visit_plans p
  LEFT JOIN public.visit_plan_items i ON i.plan_id = p.id
  GROUP BY p.id
) counts ON counts.plan_id = vp.id
WHERE vp.total_customers != counts.total_count
   OR vp.completed_count != counts.completed_count
   OR vp.skipped_count != counts.skipped_count
   OR vp.missed_count != counts.missed_count
   OR vp.rescheduled_count != counts.rescheduled_count;

-- 7.ج. التحقق من سلامة وصحة العمود المحسوب closure_pct بالمعادلة الفعلية (وتغطيته عند total_customers = 0)
SELECT
    '7.C. PLAN_CLOSURE_PCT_MISMATCH' AS audit_rule,
    vp.id AS plan_id,
    vp.closure_pct
FROM public.visit_plans vp
WHERE (vp.total_customers = 0 AND vp.closure_pct != 0)
   OR (vp.total_customers > 0 AND vp.closure_pct != ROUND(((vp.completed_count + vp.skipped_count + vp.rescheduled_count + vp.missed_count)::NUMERIC / vp.total_customers::NUMERIC) * 100, 2));

-- 7.د. رصد وجود قيم فارغة NULL في الحقول الإلزامية الجديدة بنظام الزيارات
SELECT
    '7.D. REQUIRED_FIELDS_NULL_VIOLATION' AS audit_rule,
    id AS item_id,
    status
FROM public.visit_plan_items
WHERE gps_validation_status IS NULL
   OR gps_review_status IS NULL;


-- ─── 8. تفتيش/تنبيه مرشحي التنظيف الدوري لطلبات العمليات (Operations Cleanup Candidates Audit) ───

-- 8.أ. تنبيه/مرشح تنظيف: رصد أي طلب عملية تجاوز 14 يوماً بناءً على completed_at وغير مرتبط بنزاع أو تعارض معلق،
-- ليتسنى لمهام التنظيف الدورية (عند تطبيقها في محرك العمليات لاحقاً) purge البيانات بنجاح.
SELECT
    '8.A. OPERATIONS_CLEANUP_CANDIDATES' AS audit_rule,
    vor.operation_id,
    vor.completed_at,
    vor.status
FROM private.visit_operation_requests vor
LEFT JOIN private.visit_sync_conflicts vsc ON vsc.operation_id = vor.operation_id
WHERE vor.completed_at < (CURRENT_TIMESTAMP - INTERVAL '14 days')
  AND vor.status IN ('completed', 'failed')
  AND vsc.id IS NULL;
