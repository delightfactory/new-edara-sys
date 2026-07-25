-- =============================================================================
-- EDARA v2 — visits_phase_e_execution_rpcs_contract.sql
-- سكريبت تحقق ساكن وقارئ فقط (SELECT ONLY) لتدقيق المرحلة هـ (التنفيذ الميداني الذري)
-- يعيد هذا السكريبت صفوفاً فقط في حال وجود مخالفات للالتزامات الأمنية والهيكلية والـ ACL
-- =============================================================================

-- ─── 1. التحقق من وجود RPCs العامة وتواقيعها وصلاحياتها بالترتيب والأنواع ───

WITH expected_public_rpcs AS (
  SELECT * FROM (VALUES
    ('public', 'start_visit_item_atomic', 'p_operation_id uuid, p_item_id uuid, p_start_lat numeric, p_start_lng numeric, p_start_accuracy_m numeric, p_client_started_at timestamp with time zone, p_device_timezone character varying'),
    ('public', 'complete_visit_item_atomic', 'p_operation_id uuid, p_item_id uuid, p_end_lat numeric, p_end_lng numeric, p_end_accuracy_m numeric, p_client_completed_at timestamp with time zone, p_device_timezone character varying, p_outcome_type character varying, p_outcome_notes text, p_responses jsonb, p_order_id uuid, p_collection_id uuid, p_gps_exception_reason text'),
    ('public', 'skip_visit_item_atomic', 'p_operation_id uuid, p_item_id uuid, p_skip_reason text, p_client_event_at timestamp with time zone, p_device_timezone character varying'),
    ('public', 'reschedule_visit_item_atomic', 'p_operation_id uuid, p_item_id uuid, p_target_plan_id uuid, p_reschedule_reason text, p_planned_time time without time zone, p_client_event_at timestamp with time zone, p_device_timezone character varying')
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
    ('private', 'start_visit_item_atomic_impl', 'p_operation_id uuid, p_item_id uuid, p_start_lat numeric, p_start_lng numeric, p_start_accuracy_m numeric, p_client_started_at timestamp with time zone, p_device_timezone character varying'),
    ('private', 'complete_visit_item_atomic_impl', 'p_operation_id uuid, p_item_id uuid, p_end_lat numeric, p_end_lng numeric, p_end_accuracy_m numeric, p_client_completed_at timestamp with time zone, p_device_timezone character varying, p_outcome_type character varying, p_outcome_notes text, p_responses jsonb, p_order_id uuid, p_collection_id uuid, p_gps_exception_reason text'),
    ('private', 'skip_visit_item_atomic_impl', 'p_operation_id uuid, p_item_id uuid, p_skip_reason text, p_client_event_at timestamp with time zone, p_device_timezone character varying'),
    ('private', 'reschedule_visit_item_atomic_impl', 'p_operation_id uuid, p_item_id uuid, p_target_plan_id uuid, p_reschedule_reason text, p_planned_time time without time zone, p_client_event_at timestamp with time zone, p_device_timezone character varying')
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


-- ─── 3. التحقق من أمان الخصائص البرمجية والـ search_path للـ RPCs العامة والخاصة ───

WITH expected_properties AS (
  SELECT * FROM (VALUES
    ('public', 'start_visit_item_atomic', false, ARRAY['search_path=pg_catalog']),
    ('public', 'complete_visit_item_atomic', false, ARRAY['search_path=pg_catalog']),
    ('public', 'skip_visit_item_atomic', false, ARRAY['search_path=pg_catalog']),
    ('public', 'reschedule_visit_item_atomic', false, ARRAY['search_path=pg_catalog']),

    ('private', 'start_visit_item_atomic_impl', true, ARRAY['search_path=pg_catalog']),
    ('private', 'complete_visit_item_atomic_impl', true, ARRAY['search_path=pg_catalog']),
    ('private', 'skip_visit_item_atomic_impl', true, ARRAY['search_path=pg_catalog']),
    ('private', 'reschedule_visit_item_atomic_impl', true, ARRAY['search_path=pg_catalog'])
  ) AS t(fn_schema, fn_name, is_definer, expected_config)
)
SELECT
    '3.A. RPC_SECURITY_BREACH_OR_UNSAFE_PATH' AS audit_rule,
    p.oid::regprocedure AS function_signature,
    p.prosecdef AS actual_definer,
    p.proconfig AS actual_config
FROM expected_properties ep
JOIN pg_catalog.pg_namespace n ON n.nspname = ep.fn_schema
LEFT JOIN pg_catalog.pg_proc p ON p.proname = ep.fn_name AND p.pronamespace = n.oid
WHERE p.proname IS NULL
   OR p.prosecdef != ep.is_definer
   OR (ep.expected_config IS NOT NULL AND NOT (p.proconfig @> ep.expected_config));


-- ─── 4. التحقق من الربط الهيكلي الصحيح للـ Wrappers بالـ impl وحظر العمليات المباشرة ───

WITH expected_wrapper_map AS (
  SELECT * FROM (VALUES
    ('public', 'start_visit_item_atomic', 'private', 'start_visit_item_atomic_impl'),
    ('public', 'complete_visit_item_atomic', 'private', 'complete_visit_item_atomic_impl'),
    ('public', 'skip_visit_item_atomic', 'private', 'skip_visit_item_atomic_impl'),
    ('public', 'reschedule_visit_item_atomic', 'private', 'reschedule_visit_item_atomic_impl')
  ) AS t(wrap_schema, wrap_name, impl_schema, impl_name)
)
SELECT
    '4.A. INVALID_PUBLIC_WRAPPER_IMPLEMENTATION' AS audit_rule,
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
   OR p.prosrc ILIKE '%DELETE%'
   OR p.prosrc ILIKE '%visit_plans%'
   OR p.prosrc ILIKE '%visit_plan_items%'
   OR p.prosrc ILIKE '%hr_employees%';


-- ─── 5. التحقق من حظر وجود SQLERRM نهائياً في الدوال ───

SELECT
    '5.A. SQLERRM_USAGE_FOUND' AS audit_rule,
    p.proname AS function_name
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE (n.nspname = 'public' OR n.nspname = 'private')
  AND p.proname IN (
    'start_visit_item_atomic', 'start_visit_item_atomic_impl',
    'complete_visit_item_atomic', 'complete_visit_item_atomic_impl',
    'skip_visit_item_atomic', 'skip_visit_item_atomic_impl',
    'reschedule_visit_item_atomic', 'reschedule_visit_item_atomic_impl'
  )
  AND p.prosrc ILIKE '%SQLERRM%';


-- ─── 6. التحقق من وجود المعاملة الفرعية وقفل الصفوف ───

SELECT
    '6.A. TRANSACTIONAL_STRUCTURE_VIOLATION' AS audit_rule,
    p.proname AS function_name
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'private'
  AND p.proname IN (
    'start_visit_item_atomic_impl',
    'complete_visit_item_atomic_impl',
    'skip_visit_item_atomic_impl',
    'reschedule_visit_item_atomic_impl'
  )
  AND (
    p.prosrc NOT ILIKE '%EXCEPTION WHEN OTHERS%'
    OR p.prosrc NOT ILIKE '%FOR UPDATE%'
  );


-- ─── 7. التحقق من وجود وصحة سياسات RLS بالترتيب والأنواع والأدوار والـ USING / WITH CHECK ───

WITH expected_rls_policies AS (
  SELECT * FROM (VALUES
    ('public', 'visit_plan_items', 'vpi_update', 'w', 'authenticated', true, true, true),
    ('public', 'activities', 'acts_insert', 'a', 'authenticated', true, false, true),
    ('public', 'activities', 'acts_update', 'w', 'authenticated', true, true, true),
    ('public', 'visit_checklist_responses', 'checklist_responses_insert', 'a', 'authenticated', true, false, true),
    ('public', 'visit_checklist_responses', 'checklist_responses_update', 'w', 'authenticated', true, true, true)
  ) AS t(schemaname, tablename, policyname, expected_cmd, expected_role, expected_permissive, expected_using, expected_with_check)
)
SELECT
  '7.A. RLS_POLICY_INTEGRITY_VIOLATION' AS audit_rule,
  ep.tablename,
  ep.policyname
FROM expected_rls_policies ep
JOIN pg_catalog.pg_class c ON c.relname = ep.tablename
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace AND n.nspname = ep.schemaname
LEFT JOIN pg_catalog.pg_policy p ON p.polrelid = c.oid AND p.polname = ep.policyname
WHERE p.polname IS NULL
   OR p.polcmd != ep.expected_cmd
   OR p.polpermissive != ep.expected_permissive
   OR cardinality(p.polroles) != 1
   OR p.polroles[1] != (SELECT r.oid FROM pg_catalog.pg_roles r WHERE r.rolname = ep.expected_role)
   OR (ep.expected_using = true AND p.polqual IS NULL)
   OR (ep.expected_using = false AND p.polqual IS NOT NULL)
   OR (ep.expected_with_check = true AND p.polwithcheck IS NULL)
   OR (ep.expected_with_check = false AND p.polwithcheck IS NOT NULL);


-- ─── 8. تدقيق قيود حقول التنفيذ المذكورة في vpi_update لمنع التعديل المباشر ───

SELECT
  '8.A. VPI_UPDATE_POLICY_FIELDS_UNSAFE' AS audit_rule,
  p.polname
FROM pg_catalog.pg_policy p
JOIN pg_catalog.pg_class c ON c.oid = p.polrelid
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'visit_plan_items'
  AND p.polname = 'vpi_update'
  AND (
    -- USING (polqual) check
    COALESCE(pg_catalog.pg_get_expr(p.polqual, p.polrelid) NOT ILIKE '%status% = ''pending''::text%', true)

    -- WITH CHECK (polwithcheck) check
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%status% = ''pending''::text%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%activity_id IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%gps_lat IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%gps_lng IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%end_gps_lat IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%end_gps_lng IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%start_lat IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%start_lng IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%start_accuracy_m IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%start_distance_m IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%end_lat IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%end_lng IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%end_accuracy_m IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%end_distance_m IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%server_started_at IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%server_completed_at IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%client_started_at IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%client_completed_at IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%gps_validation_status% = ''not_checked''::text%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%gps_review_status% = ''not_required''::text%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%gps_exception_reason IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%gps_exception_requested_by IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%gps_exception_reviewed_by IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%gps_exception_reviewed_at IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%skip_reason IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%reschedule_to IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%reschedule_reason IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%replacement_item_id IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%rescheduled_from_item_id IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%actual_arrival_time IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%actual_start_time IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%actual_end_time IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%device_timezone IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%stale_since IS NULL%', true)
    OR COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) NOT ILIKE '%metadata IS NULL%', true)
  );


-- ─── 9. التحقق من وجود الفهرس الفريد الجزئي للنشاط الفعال للبند ومطابقة شروطه بدقة ───

WITH expected_index AS (
  SELECT
    'public'::name AS index_schema,
    'idx_activities_unique_visit_plan_item'::name AS index_name,
    'public'::name AS table_schema,
    'activities'::name AS table_name
)
SELECT
  '9.A. INDEX_INTEGRITY_VIOLATION' AS audit_rule,
  ei.index_name
FROM expected_index ei
LEFT JOIN pg_catalog.pg_class ic ON ic.relname = ei.index_name
LEFT JOIN pg_catalog.pg_namespace in_ns ON in_ns.oid = ic.relnamespace AND in_ns.nspname = ei.index_schema
LEFT JOIN pg_catalog.pg_index idx ON idx.indexrelid = ic.oid
LEFT JOIN pg_catalog.pg_class tc ON tc.oid = idx.indrelid AND tc.relname = ei.table_name
LEFT JOIN pg_catalog.pg_namespace tn ON tn.oid = tc.relnamespace AND tn.nspname = ei.table_schema
LEFT JOIN pg_catalog.pg_attribute a ON a.attrelid = tc.oid AND a.attnum = idx.indkey[0] AND a.attname = 'visit_plan_item_id'
WHERE ic.relname IS NULL
   OR tc.relname IS NULL
   OR in_ns.oid IS NULL
   OR tn.oid IS NULL
   OR idx.indisunique = false
   OR idx.indisvalid = false
   OR idx.indisready = false
   OR idx.indnkeyatts != 1
   OR idx.indnatts != 1
   OR a.attname IS NULL
   OR pg_catalog.pg_get_expr(idx.indpred, idx.indrelid) NOT ILIKE '%visit_plan_item_id IS NOT NULL%'
   OR pg_catalog.pg_get_expr(idx.indpred, idx.indrelid) NOT ILIKE '%deleted_at IS NULL%';


-- ─── 10. التحقق من عدم وجود فهرس فريد مكافئ مكرر ومستقل ───

SELECT
  '10.A. DUPLICATE_EQUIVALENT_UNIQUE_INDEX' AS audit_rule,
  ic.relname AS index_name
FROM pg_catalog.pg_index idx
JOIN pg_catalog.pg_class ic ON ic.oid = idx.indexrelid
JOIN pg_catalog.pg_class tc ON tc.oid = idx.indrelid
JOIN pg_catalog.pg_namespace n ON n.oid = tc.relnamespace
WHERE n.nspname = 'public'
  AND tc.relname = 'activities'
  AND idx.indisunique = true
  AND ic.relname IS DISTINCT FROM 'idx_activities_unique_visit_plan_item'
  AND idx.indnkeyatts = 1
  AND idx.indnatts = 1
  AND EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = tc.oid
      AND a.attname = 'visit_plan_item_id'
      AND a.attnum = idx.indkey[0]
  )
  AND pg_catalog.pg_get_expr(idx.indpred, idx.indrelid) ILIKE '%visit_plan_item_id IS NOT NULL%'
  AND pg_catalog.pg_get_expr(idx.indpred, idx.indrelid) ILIKE '%deleted_at IS NULL%';


-- ─── 11. تدقيق قيد الحذف المرجعي للنشاط بالبند وهيكله الموحد ───

WITH expected_fk AS (
  SELECT
    'public'::name AS src_schema,
    'visit_plan_items'::name AS src_table,
    'fk_visit_plan_items_activity'::name AS con_name,
    'public'::name AS tgt_schema,
    'activities'::name AS tgt_table,
    'activity_id'::name AS src_col,
    'id'::name AS tgt_col
)
SELECT
  '11.A. FK_INTEGRITY_VIOLATION' AS audit_rule,
  ef.src_schema,
  ef.src_table,
  ef.con_name
FROM expected_fk ef
LEFT JOIN pg_catalog.pg_class c_src ON c_src.relname = ef.src_table
LEFT JOIN pg_catalog.pg_namespace n_src ON n_src.oid = c_src.relnamespace AND n_src.nspname = ef.src_schema
LEFT JOIN pg_catalog.pg_constraint con
  ON con.conrelid = c_src.oid
  AND con.conname = ef.con_name
  AND con.contype = 'f'
  AND con.confdeltype = 'r' -- RESTRICT
  AND con.convalidated = true
  AND cardinality(con.conkey) = 1
  AND cardinality(con.confkey) = 1
LEFT JOIN pg_catalog.pg_class c_tgt ON c_tgt.oid = con.confrelid AND c_tgt.relname = ef.tgt_table
LEFT JOIN pg_catalog.pg_namespace n_tgt ON n_tgt.oid = c_tgt.relnamespace AND n_tgt.nspname = ef.tgt_schema
LEFT JOIN pg_catalog.pg_attribute a_src ON a_src.attrelid = c_src.oid AND a_src.attnum = con.conkey[1] AND a_src.attname = ef.src_col
LEFT JOIN pg_catalog.pg_attribute a_tgt ON a_tgt.attrelid = c_tgt.oid AND a_tgt.attnum = con.confkey[1] AND a_tgt.attname = ef.tgt_col
WHERE con.conname IS NULL
   OR c_tgt.oid IS NULL
   OR n_src.oid IS NULL
   OR n_tgt.oid IS NULL
   OR a_src.attname IS NULL
   OR a_tgt.attname IS NULL;


-- ─── 12. التحقق من عدم وجود أي قيود أجنبية أخرى تسرب الحذف بالعمود وعدّها ───

SELECT
    '12.A. UNSAFE_SECONDARY_FK_ON_ACTIVITY_ID' AS audit_rule,
    c.relname AS table_name,
    con.conname AS constraint_name
FROM pg_catalog.pg_constraint con
JOIN pg_catalog.pg_class c ON c.oid = con.conrelid
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'visit_plan_items'
  AND con.contype = 'f'
  AND con.conname IS DISTINCT FROM 'fk_visit_plan_items_activity'
  AND EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = c.oid
      AND a.attname = 'activity_id'
      AND a.attnum = ANY(con.conkey)
  );

SELECT
  '12.B. MULTIPLE_FKS_ON_ACTIVITY_ID' AS audit_rule,
  COUNT(*) AS fk_count
FROM pg_catalog.pg_constraint con
JOIN pg_catalog.pg_class c ON c.oid = con.conrelid
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'visit_plan_items'
  AND con.contype = 'f'
  AND EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = c.oid
      AND a.attname = 'activity_id'
      AND a.attnum = ANY(con.conkey)
  )
HAVING COUNT(*) != 1;


-- ─── 13. تدقيق أمان دالة مسافة Haversine وتوقيعها والـ configuration ───

WITH expected_haversine AS (
  SELECT * FROM (VALUES
    ('private', 'calculate_haversine_distance', 'lat1 numeric, lng1 numeric, lat2 numeric, lng2 numeric')
  ) AS t(fn_schema, fn_name, fn_args)
)
SELECT
    '13.A. HAVERSINE_SECURITY_VIOLATION' AS audit_rule,
    p.oid::regprocedure AS actual_signature
FROM expected_haversine eh
JOIN pg_catalog.pg_namespace n ON n.nspname = eh.fn_schema
LEFT JOIN pg_catalog.pg_proc p ON p.proname = eh.fn_name AND p.pronamespace = n.oid
WHERE p.proname IS NULL
   OR p.prosecdef = true -- must be invoker (prosecdef = false)
   OR (SELECT l.lanname FROM pg_catalog.pg_language l WHERE l.oid = p.prolang) != 'plpgsql'
   OR NOT (p.proconfig @> ARRAY['search_path=pg_catalog']);


-- ─── 14. تدقيق وجود وثبات نوع وقيد VARCHAR(500) لسبب إعادة الجدولة بـ LEFT JOIN المرتبط بـ OID ───

WITH expected_col AS (
  SELECT
    'public'::name AS table_schema,
    'visit_plan_items'::name AS table_name,
    'reschedule_reason'::name AS column_name
)
SELECT
  '14.A. RESCHEDULE_REASON_COLUMN_INVALID' AS audit_rule,
  ec.column_name
FROM expected_col ec
LEFT JOIN information_schema.columns c
  ON c.table_schema = ec.table_schema
  AND c.table_name = ec.table_name
  AND c.column_name = ec.column_name
WHERE c.column_name IS NULL
   OR c.data_type IS DISTINCT FROM 'character varying'
   OR c.character_maximum_length IS DISTINCT FROM 500;

WITH expected_con AS (
  SELECT
    'chk_visit_plan_items_reschedule_reason_len'::name AS con_name
)
SELECT
  '14.B. RESCHEDULE_REASON_CONSTRAINT_INVALID' AS audit_rule,
  econ.con_name
FROM expected_con econ
LEFT JOIN pg_catalog.pg_constraint con
  ON con.conrelid = 'public.visit_plan_items'::regclass::oid
  AND con.conname = econ.con_name
WHERE con.conname IS NULL
   OR con.contype != 'c'
   OR con.convalidated = false
   OR pg_catalog.pg_get_constraintdef(con.oid) NOT ILIKE '%char_length%'
   OR pg_catalog.pg_get_constraintdef(con.oid) NOT ILIKE '%reschedule_reason%'
   OR pg_catalog.pg_get_constraintdef(con.oid) NOT ILIKE '%500%';


-- ─── 15. تدقيق ومطابقة الـ ACL وصلاحيات authenticated / anon / PUBLIC على مستوى المخططات والدوال ───

-- 15.أ. التحقق من صلاحيات USAGE و CREATE للمخطط private بـ aclexplode المباشر
WITH schema_acl AS (
  SELECT
    n.nspname,
    (aclexplode(COALESCE(n.nspacl, acldefault('n', n.nspowner)))).*
  FROM pg_catalog.pg_namespace n
  WHERE n.nspname = 'private'
)
SELECT
  '15.A. SCHEMA_ACL_VIOLATION' AS audit_rule,
  nspname,
  privilege_type,
  grantee
FROM schema_acl
WHERE (
  -- authenticated must not have CREATE
  (grantee = (SELECT oid FROM pg_roles WHERE rolname = 'authenticated') AND privilege_type = 'CREATE')
  -- PUBLIC (grantee = 0) and anon must not have USAGE or CREATE
  OR (grantee = 0 AND privilege_type IN ('USAGE', 'CREATE'))
  OR (grantee = (SELECT oid FROM pg_roles WHERE rolname = 'anon') AND privilege_type IN ('USAGE', 'CREATE'))
);

-- 15.ب. التحقق من منح صلاحية USAGE لـ authenticated على private بـ LEFT JOIN
WITH expected_schema_usage AS (
  SELECT
    'private'::name AS schema_name,
    'authenticated'::name AS role_name,
    'USAGE'::text AS expected_priv
)
SELECT
  '15.B. SCHEMA_USAGE_MISSING' AS audit_rule,
  esu.schema_name
FROM expected_schema_usage esu
LEFT JOIN (
  SELECT n.nspname, (aclexplode(COALESCE(n.nspacl, acldefault('n', n.nspowner)))).*
  FROM pg_catalog.pg_namespace n
) x ON x.nspname = esu.schema_name
    AND x.grantee = (SELECT oid FROM pg_roles WHERE rolname = esu.role_name)
    AND x.privilege_type = esu.expected_priv
WHERE x.nspname IS NULL;

-- 15.ج. التحقق من حظر EXECUTE للدوال الثمانية عن anon أو PUBLIC (بـ grantee = 0) بـ aclexplode
WITH expected_rpcs AS (
  SELECT * FROM (VALUES
    ('public', 'start_visit_item_atomic'),
    ('public', 'complete_visit_item_atomic'),
    ('public', 'skip_visit_item_atomic'),
    ('public', 'reschedule_visit_item_atomic'),

    ('private', 'start_visit_item_atomic_impl'),
    ('private', 'complete_visit_item_atomic_impl'),
    ('private', 'skip_visit_item_atomic_impl'),
    ('private', 'reschedule_visit_item_atomic_impl')
  ) AS t(fn_schema, fn_name)
),
rpc_acls AS (
  SELECT
    n.nspname AS fn_schema,
    p.proname AS fn_name,
    p.oid AS fn_oid,
    (aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner)))).*
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname IN ('public', 'private')
    AND p.proname IN (
      'start_visit_item_atomic', 'start_visit_item_atomic_impl',
      'complete_visit_item_atomic', 'complete_visit_item_atomic_impl',
      'skip_visit_item_atomic', 'skip_visit_item_atomic_impl',
      'reschedule_visit_item_atomic', 'reschedule_visit_item_atomic_impl'
    )
)
SELECT
  '15.C. RPC_DIRECT_ACL_VIOLATION' AS audit_rule,
  er.fn_schema,
  er.fn_name,
  acl.privilege_type,
  acl.grantee
FROM expected_rpcs er
JOIN pg_catalog.pg_namespace n ON n.nspname = er.fn_schema
JOIN pg_catalog.pg_proc p ON p.proname = er.fn_name AND p.pronamespace = n.oid
LEFT JOIN rpc_acls acl ON acl.fn_oid = p.oid
WHERE (
  -- PUBLIC (0) or anon (role OID) must not have EXECUTE
  (acl.grantee = 0 AND acl.privilege_type = 'EXECUTE')
  OR (acl.grantee = (SELECT oid FROM pg_roles WHERE rolname = 'anon') AND acl.privilege_type = 'EXECUTE')
);

-- 15.د. التحقق من منح EXECUTE لـ authenticated على الدوال الثمانية بشكل مباشر
WITH expected_rpcs AS (
  SELECT * FROM (VALUES
    ('public', 'start_visit_item_atomic'),
    ('public', 'complete_visit_item_atomic'),
    ('public', 'skip_visit_item_atomic'),
    ('public', 'reschedule_visit_item_atomic'),

    ('private', 'start_visit_item_atomic_impl'),
    ('private', 'complete_visit_item_atomic_impl'),
    ('private', 'skip_visit_item_atomic_impl'),
    ('private', 'reschedule_visit_item_atomic_impl')
  ) AS t(fn_schema, fn_name)
)
SELECT
  '15.D. RPC_MISSING_DIRECT_AUTHENTICATED_EXECUTE' AS audit_rule,
  er.fn_schema,
  er.fn_name
FROM expected_rpcs er
JOIN pg_catalog.pg_namespace n ON n.nspname = er.fn_schema
JOIN pg_catalog.pg_proc p ON p.proname = er.fn_name AND p.pronamespace = n.oid
LEFT JOIN (
  SELECT
    p.oid AS fn_oid,
    (aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner)))).*
  FROM pg_catalog.pg_proc p
) acl ON acl.fn_oid = p.oid
      AND acl.grantee = (SELECT oid FROM pg_roles WHERE rolname = 'authenticated')
      AND acl.privilege_type = 'EXECUTE'
WHERE acl.grantee IS NULL;

-- 15.هـ. التحقق من حظر استدعاء دالة Haversine عن authenticated / anon / PUBLIC بـ aclexplode
SELECT
  '15.E. HAVERSINE_DIRECT_ACL_LEAK' AS audit_rule,
  acl.privilege_type,
  acl.grantee
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) acl
WHERE n.nspname = 'private'
  AND p.proname = 'calculate_haversine_distance'
  AND acl.privilege_type = 'EXECUTE'
  AND (
    acl.grantee = 0
    OR acl.grantee = (SELECT oid FROM pg_roles WHERE rolname = 'anon')
    OR acl.grantee = (SELECT oid FROM pg_roles WHERE rolname = 'authenticated')
  );

-- 15.و. التحقق من حظر الوصول المباشر لجداول المخطط private بـ aclexplode
SELECT
  '15.F. PRIVATE_TABLE_DIRECT_ACL_LEAK' AS audit_rule,
  c.relname AS table_name,
  acl.privilege_type,
  acl.grantee
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) acl
WHERE n.nspname = 'private'
  AND c.relkind = 'r'
  AND acl.privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
  AND (
    acl.grantee = 0
    OR acl.grantee = (SELECT oid FROM pg_roles WHERE rolname = 'anon')
    OR acl.grantee = (SELECT oid FROM pg_roles WHERE rolname = 'authenticated')
  );

-- 15.ز. تدقيق صلاحية UPDATE للأعمدة لـ authenticated وحظرها على الجدول بالكامل (الخمسة الآمنة فقط)
SELECT
  '15.G. COLUMN_PRIVILEGE_VIOLATION' AS audit_rule,
  col.column_name,
  col_priv.privilege_type
FROM information_schema.columns col
LEFT JOIN (
  SELECT column_name, privilege_type
  FROM information_schema.column_privileges
  WHERE table_schema = 'public'
    AND table_name = 'visit_plan_items'
    AND grantee = 'authenticated'
    AND privilege_type = 'UPDATE'
) col_priv ON col_priv.column_name = col.column_name
WHERE col.table_schema = 'public'
  AND col.table_name = 'visit_plan_items'
  AND (
    (col.column_name IN ('planned_time', 'estimated_duration_min', 'priority', 'purpose', 'purpose_type') AND col_priv.privilege_type IS NULL)
    OR (col.column_name NOT IN ('planned_time', 'estimated_duration_min', 'priority', 'purpose', 'purpose_type') AND col_priv.privilege_type IS NOT NULL)
  );

SELECT
  '15.H. TABLE_PRIVILEGE_VIOLATION' AS audit_rule,
  t.table_name
FROM information_schema.tables t
WHERE t.table_schema = 'public'
  AND t.table_name = 'visit_plan_items'
  AND EXISTS (
    SELECT 1 FROM information_schema.table_privileges tp
    WHERE tp.table_schema = 'public'
      AND tp.table_name = 'visit_plan_items'
      AND tp.grantee = 'authenticated'
      AND tp.privilege_type = 'UPDATE'
  );

SELECT
  '15.I. TABLE_OR_COLUMN_ACCESS_LEAK_TO_ANON_OR_PUBLIC' AS audit_rule,
  tp.grantee,
  tp.privilege_type
FROM information_schema.table_privileges tp
WHERE tp.table_schema = 'public'
  AND tp.table_name = 'visit_plan_items'
  AND tp.grantee IN ('PUBLIC', 'anon')
  AND tp.privilege_type = 'UPDATE'

UNION ALL

SELECT
  '15.J. COLUMN_ACCESS_LEAK_TO_ANON_OR_PUBLIC' AS audit_rule,
  cp.grantee,
  cp.column_name
FROM information_schema.column_privileges cp
WHERE cp.table_schema = 'public'
  AND cp.table_name = 'visit_plan_items'
  AND cp.grantee IN ('PUBLIC', 'anon')
  AND cp.privilege_type = 'UPDATE';


-- ─── 16. تدقيق متطلبات أمان وموثوقية الهيكل البرمجي لـ impl بالكامل وفحوص v_actor_id والمطابقة ───

WITH expected_impl_logic AS (
  SELECT * FROM (VALUES
    ('private', 'start_visit_item_atomic_impl'),
    ('private', 'complete_visit_item_atomic_impl'),
    ('private', 'skip_visit_item_atomic_impl'),
    ('private', 'reschedule_visit_item_atomic_impl')
  ) AS t(fn_schema, fn_name)
)
SELECT
  '16.A. RPC_IMPL_LOGIC_VIOLATION' AS audit_rule,
  el.fn_name
FROM expected_impl_logic el
JOIN pg_catalog.pg_namespace n ON n.nspname = el.fn_schema
LEFT JOIN pg_catalog.pg_proc p
  ON p.proname = el.fn_name
  AND p.pronamespace = n.oid
  AND p.prosrc ILIKE '%auth.uid()%'
  AND p.prosrc ILIKE '%check_permission%'
  AND p.prosrc ILIKE '%extensions.digest%'
  AND p.prosrc ILIKE '%sha256%'
  AND p.prosrc ILIKE '%INSERT INTO private.visit_operation_requests%'
  AND p.prosrc ILIKE '%ON CONFLICT DO NOTHING%'
  AND p.prosrc ILIKE '%FOR UPDATE%'
  AND p.prosrc ILIKE '%IDEMPOTENCY_KEY_CONFLICT%'
  AND p.prosrc ILIKE '%RETRYABLE_ERROR%'
  AND p.prosrc ILIKE '%status = ''processing''%'
  AND p.prosrc ILIKE '%EXCEPTION WHEN OTHERS%'
  AND p.prosrc ILIKE '%status = ''failed''%'
  AND p.prosrc ILIKE '%jsonb_build_object%'
  AND p.prosrc ILIKE '%''ok'',%'
  AND p.prosrc ILIKE '%''operation_id'',%'
  AND p.prosrc ILIKE '%''replayed'',%'
  -- Added checks:
  AND p.prosrc ILIKE '%v_actor_id IS NULL%'
  AND p.prosrc ILIKE '%actor_id%'
  AND p.prosrc ILIKE '%operation_name%'
  AND p.prosrc ILIKE '%request_hash%'
WHERE p.proname IS NULL;


-- ─── 17. تدقيق أمان مسار الصور ووجود الفحوص التفصيلية والرمزية في دالة الإكمال باستخدام strpos ───

SELECT
  '17.A. COMPLETE_MISSING_SECURE_PATH_VALIDATION_DETAILS' AS audit_rule,
  p.proname
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'private'
  AND p.proname = 'complete_visit_item_atomic_impl'
  AND (
    strpos(p.prosrc, 'position(chr(92) in v_photo_path) > 0') = 0
    OR strpos(p.prosrc, 'position(''%'' in v_photo_path) > 0') = 0
    OR strpos(p.prosrc, 'position(''?'' in v_photo_path) > 0') = 0
    OR strpos(p.prosrc, 'position(''//'' in v_photo_path) > 0') = 0
    OR strpos(p.prosrc, 'v_photo_path LIKE ''/%''') = 0
    OR strpos(p.prosrc, 'v_photo_path LIKE ''.%''') = 0
    OR strpos(p.prosrc, 'v_photo_path ~ ''(^|/)\.\.?(/|$)''') = 0
  );


-- ─── 18. تدقيق حظر أي INSERT/UPDATE/DELETE أو FOR UPDATE على المبيعات والتحصيلات ───

SELECT
    '18.A. TRANSACTIONAL_WRITE_VIOLATION_IN_COMPLETE' AS audit_rule,
    p.proname
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'private'
  AND p.proname = 'complete_visit_item_atomic_impl'
  AND p.prosrc ~* '(INSERT[[:space:]]+INTO|UPDATE|DELETE[[:space:]]+FROM)[[:space:]]+public[.](sales_orders|payment_receipts)';

SELECT
    '18.B. FORBIDDEN_FOR_UPDATE_ON_SALES_OR_COLLECTIONS' AS audit_rule,
    p.proname
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'private'
  AND p.proname = 'complete_visit_item_atomic_impl'
  AND p.prosrc ~* 'FROM[[:space:]]+public[.](sales_orders|payment_receipts)[^;]*FOR[[:space:]]+UPDATE';


-- ─── 19. تدقيق حظر وجود أعمدة أو أنماط ممنوعة أو مضللّة ───

SELECT
    '19.A. FORBIDDEN_COLUMN_OR_PATTERN_DETECTED' AS audit_rule,
    p.proname
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'private'
  AND p.proname IN (
    'start_visit_item_atomic_impl',
    'complete_visit_item_atomic_impl',
    'skip_visit_item_atomic_impl',
    'reschedule_visit_item_atomic_impl'
  )
  AND p.prosrc ~* '(^|[^[:alnum:]_])(activity_type_id|gps_accuracy|is_default)([^[:alnum:]_]|$)';


-- ─── 20. تدقيق غياب رفض ربط الطلب والتحصيل معاً في complete ───

SELECT
    '20.A. COMPLETE_MISSING_DUAL_TRANSACTION_REJECTION' AS audit_rule,
    p.proname
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'private'
  AND p.proname = 'complete_visit_item_atomic_impl'
  AND p.prosrc NOT ILIKE '%p_order_id IS NOT NULL AND p_collection_id IS NOT NULL%';


-- ─── 21. الحفاظ على صلاحيات الأنشطة والاستبيانات غير المرتبطة بالزيارات ───
WITH policy_defs AS (
  SELECT
    c.relname AS table_name,
    p.polname AS policy_name,
    COALESCE(pg_catalog.pg_get_expr(p.polqual, p.polrelid), '') AS using_expr,
    COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid), '') AS check_expr
  FROM pg_catalog.pg_policy p
  JOIN pg_catalog.pg_class c ON c.oid = p.polrelid
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND p.polname IN ('acts_update', 'checklist_responses_insert', 'checklist_responses_update')
)
SELECT
  '21.A. SHARED_ACTIVITY_POLICY_REGRESSION' AS audit_rule,
  table_name,
  policy_name
FROM policy_defs
WHERE
  (policy_name = 'acts_update' AND (
    using_expr NOT ILIKE '%visit_plan_item_id IS NULL%'
    OR using_expr NOT ILIKE '%activities.read_all%'
    OR check_expr NOT ILIKE '%visit_plan_item_id IS NULL%'
    OR check_expr NOT ILIKE '%activities.read_all%'
  ))
  OR (policy_name = 'checklist_responses_insert' AND (
    check_expr NOT ILIKE '%visit_plan_item_id IS NOT NULL%'
    OR check_expr NOT ILIKE '%activities.update_own%'
    OR check_expr NOT ILIKE '%activities.read_team%'
    OR check_expr NOT ILIKE '%activities.read_all%'
  ))
  OR (policy_name = 'checklist_responses_update' AND (
    using_expr NOT ILIKE '%visit_plan_item_id IS NOT NULL%'
    OR using_expr NOT ILIKE '%activities.update_own%'
    OR check_expr NOT ILIKE '%visit_plan_item_id IS NOT NULL%'
    OR check_expr NOT ILIKE '%activities.update_own%'
  ));

-- ─── 22. ربط دليل الصورة بالخطة والبند والتحقق من وجوده في Storage ───
SELECT
  '22.A. PHOTO_PROOF_BINDING_OR_EXISTENCE_MISSING' AS audit_rule,
  p.proname
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'private'
  AND p.proname = 'complete_visit_item_atomic_impl'
  AND (
    p.prosrc NOT ILIKE '%FROM storage.objects%'
    OR p.prosrc NOT ILIKE '%visit-proofs%'
    OR p.prosrc NOT ILIKE '%v_plan_id::TEXT%'
    OR p.prosrc NOT ILIKE '%p_item_id::TEXT%'
  );

-- ─── 23. تطبيع JSON null لإجابات الحقول القياسية قبل التحقق ───
SELECT
  '23.A. CHECKLIST_JSON_NULL_NORMALIZATION_MISSING' AS audit_rule,
  'private.complete_visit_item_atomic_impl(...)' AS function_name
WHERE NOT EXISTS (
  SELECT 1
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'private'
    AND p.proname = 'complete_visit_item_atomic_impl'
    AND p.prosrc LIKE '%v_resp_json := NULLIF(v_resp_item -> ''answer_json'', ''null''::JSONB);%'
    AND p.prosecdef = true
    AND p.proconfig IS NOT NULL
    AND 'search_path=pg_catalog' = ANY(p.proconfig)
);
