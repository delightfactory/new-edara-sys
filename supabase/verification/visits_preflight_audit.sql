-- =============================================================================
-- EDARA v2 — visits_preflight_audit.sql
-- ملف تدقيق بيانات موديول الزيارات (للقراءة فقط - SELECT ONLY)
-- يهدف هذا السكريبت إلى كشف أي أخطاء أو تعارضات هيكلية أو منطقية قبل تفعيل القيود الجديدة
--
-- ⚠️ تنبيه إخلاء المسؤولية (Disclaimer):
-- إذا لم تكن هناك قاعدة بيانات محلية نشطة (Local Database Container)، فإن هذا التحقق
-- يُعتبر تحليلاً تناظرياً وساكناً (Static & Analog Verification) فقط لتوجيه المطور أثناء التطوير.
-- =============================================================================

-- ─── 1. تدقيق جودة الجغرافيا والـ GPS ───

-- 1.أ. إحداثيات خارج الحدود الجغرافية المعيارية للكرة الأرضية (خط العرض بين -90 و90، وخط الطول بين -180 و180)
SELECT
    '1.A. INVALID_GPS_RANGE' AS audit_rule,
    source_table,
    record_id,
    record_name,
    latitude,
    longitude
FROM (
    SELECT 'customers' AS source_table, id AS record_id, name AS record_name, latitude, longitude FROM public.customers
    UNION ALL
    SELECT 'customer_branches' AS source_table, id AS record_id, name AS record_name, latitude, longitude FROM public.customer_branches
) geo_data
WHERE latitude NOT BETWEEN -90 AND 90
   OR longitude NOT BETWEEN -180 AND 180;

-- 1.ب. إحداثيات مفقودة أو صفرية (تقرير جودة المنشآت والعملاء منفصلاً)
SELECT
    '1.B. MISSING_OR_ZERO_GPS' AS audit_rule,
    source_table,
    record_id,
    record_name,
    latitude,
    longitude
FROM (
    SELECT 'customers' AS source_table, id AS record_id, name AS record_name, latitude, longitude FROM public.customers
    UNION ALL
    SELECT 'customer_branches' AS source_table, id AS record_id, name AS record_name, latitude, longitude FROM public.customer_branches
) geo_data
WHERE latitude IS NULL OR longitude IS NULL
   OR latitude = 0 OR longitude = 0;


-- ─── 2. تدقيق الترتيب والتكرار (Sequences & Duplicates) ───

-- 2.أ. قيم الترتيب (sequence) الصفرية أو السالبة
SELECT
    '2.A. NEGATIVE_OR_ZERO_SEQUENCE' AS audit_rule,
    id AS item_id,
    plan_id,
    sequence
FROM public.visit_plan_items
WHERE sequence <= 0;

-- 2.ب. قيم الترتيب (sequence) المكررة داخل نفس الخطة (موجبة أو سالبة)
SELECT
    '2.B. DUPLICATE_SEQUENCES_IN_PLAN' AS audit_rule,
    plan_id,
    sequence,
    COUNT(*) AS dup_count,
    ARRAY_AGG(id) AS item_ids
FROM public.visit_plan_items
GROUP BY plan_id, sequence
HAVING COUNT(*) > 1;

-- 2.ج. الأنشطة المكررة والنشطة لنفس بند الزيارة (تمنع إنشاء القيد الفريد لاحقاً)
SELECT
    '2.C. DUPLICATE_ACTIVE_ACTIVITIES' AS audit_rule,
    visit_plan_item_id,
    COUNT(*) AS active_activity_count,
    ARRAY_AGG(id) AS activity_ids
FROM public.activities
WHERE deleted_at IS NULL
  AND visit_plan_item_id IS NOT NULL
GROUP BY visit_plan_item_id
HAVING COUNT(*) > 1;


-- ─── 3. تدقيق حالات الموظفين المتزامنة (Concurrency) ───

-- 3.أ. تعدد بنود الزيارات بحالة "قيد التنفيذ" (in_progress) لنفس الموظف عبر جميع تواريخ الخطط
SELECT
    '3.A. MULTIPLE_IN_PROGRESS_ITEMS' AS audit_rule,
    vp.employee_id,
    COUNT(vpi.id) AS in_progress_item_count,
    JSONB_AGG(JSONB_BUILD_OBJECT('item_id', vpi.id, 'plan_date', vp.plan_date)) AS items_detail
FROM public.visit_plan_items vpi
JOIN public.visit_plans vp ON vp.id = vpi.plan_id
WHERE vpi.status = 'in_progress'
GROUP BY vp.employee_id
HAVING COUNT(vpi.id) > 1;

-- 3.ب. أكثر من رأس خطة واحد بحالة "قيد التنفيذ" (in_progress) لنفس الموظف في نفس التاريخ
SELECT
    '3.B. MULTIPLE_IN_PROGRESS_PLANS' AS audit_rule,
    employee_id,
    plan_date,
    COUNT(*) AS plan_count,
    ARRAY_AGG(id) AS plan_ids
FROM public.visit_plans
WHERE status = 'in_progress'
GROUP BY employee_id, plan_date
HAVING COUNT(*) > 1;


-- ─── 4. تدقيق عدم تطابق المعرفات والأنشطة (Activity ID Alignment) ───

-- 4.أ. بند زيارة يشير إلى نشاط، ولكن هذا النشاط لا يشير إليه (أو يشير لبند آخر، أو محذوف)
SELECT
    '4.A. ITEM_REF_MISMATCH' AS audit_rule,
    vpi.id AS item_id,
    vpi.activity_id AS item_activity_ref,
    act.id AS act_id,
    act.visit_plan_item_id AS act_item_ref
FROM public.visit_plan_items vpi
LEFT JOIN public.activities act ON act.id = vpi.activity_id AND act.deleted_at IS NULL
WHERE vpi.activity_id IS NOT NULL
  AND (act.id IS NULL OR act.visit_plan_item_id != vpi.id);

-- 4.ب. نشاط فعال يشير إلى بند زيارة، ولكن البند لا يشير إليه (أو يشير لنشاط آخر)
SELECT
    '4.B. ACTIVITY_REF_MISMATCH' AS audit_rule,
    act.id AS act_id,
    act.visit_plan_item_id AS act_item_ref,
    vpi.id AS item_id,
    vpi.activity_id AS item_activity_ref
FROM public.activities act
LEFT JOIN public.visit_plan_items vpi ON vpi.id = act.visit_plan_item_id
WHERE act.deleted_at IS NULL
  AND act.visit_plan_item_id IS NOT NULL
  AND (vpi.id IS NULL OR vpi.activity_id IS NULL OR vpi.activity_id != act.id);


-- ─── 5. تدقيق الحالات النهائية والطوابع الزمنية (Final Statuses & Timestamps) ───

-- 5.أ. بنود مكتملة بحالات غير متسقة (تفتقد وقت البداية، وقت النهاية، أو المعرف)
SELECT
    '5.A. INCOMPLETE_COMPLETED_ITEMS' AS audit_rule,
    id AS item_id,
    plan_id,
    actual_arrival_time,
    actual_start_time,
    actual_end_time,
    activity_id
FROM public.visit_plan_items
WHERE status = 'completed'
  AND (actual_start_time IS NULL OR actual_end_time IS NULL OR activity_id IS NULL);

-- 5.ب. بنود متخطاة أو معاد جدولتها تفتقد السبب المبرر أو تاريخ الإعادة
SELECT
    '5.B. MISSING_SKIP_OR_RESCHEDULE_REASON' AS audit_rule,
    id AS item_id,
    status,
    skip_reason,
    reschedule_to
FROM public.visit_plan_items
WHERE (status = 'skipped' AND NULLIF(BTRIM(skip_reason), '') IS NULL)
   OR (status = 'rescheduled' AND (reschedule_to IS NULL OR NULLIF(BTRIM(skip_reason), '') IS NULL));

-- 5.ج. بنود متخطاة أو معاد جدولتها ذات تاريخ مستهدف غير منطقي
SELECT
    '5.C. INVALID_RESCHEDULE_DATE' AS audit_rule,
    vpi.id AS item_id,
    vp.plan_date AS original_plan_date,
    vpi.reschedule_to AS target_reschedule_date
FROM public.visit_plan_items vpi
JOIN public.visit_plans vp ON vp.id = vpi.plan_id
WHERE vpi.status = 'rescheduled'
  AND (vpi.reschedule_to IS NULL OR vpi.reschedule_to <= vp.plan_date);

-- 5.د. بنود ذات ترتيب أزمنة غير منطقي (الوصول > البداية > النهاية)
SELECT
    '5.D. CHRONOLOGICAL_ERRORS' AS audit_rule,
    id AS item_id,
    actual_arrival_time,
    actual_start_time,
    actual_end_time
FROM public.visit_plan_items
WHERE (actual_arrival_time > actual_start_time)
   OR (actual_start_time > actual_end_time)
   OR (actual_arrival_time > actual_end_time);

-- 5.هـ. بنود فائتة (missed) ولكن تحتوي على طوابع زمنية للزيارة الميدانية
SELECT
    '5.E. MISSED_ITEM_WITH_TIMESTAMPS' AS audit_rule,
    id AS item_id,
    actual_arrival_time,
    actual_start_time,
    actual_end_time
FROM public.visit_plan_items
WHERE status = 'missed'
  AND (actual_arrival_time IS NOT NULL OR actual_start_time IS NOT NULL OR actual_end_time IS NOT NULL);


-- ─── 6. تدقيق الأيتام والخطط الفارغة (Orphans & Empty Plans) ───

-- 6.أ. بنود زيارة معلقة لا تملك رأس خطة (أيتام البنود)
SELECT
    '6.A. ORPHAN_VISIT_ITEMS' AS audit_rule,
    vpi.id AS item_id,
    vpi.plan_id
FROM public.visit_plan_items vpi
LEFT JOIN public.visit_plans vp ON vp.id = vpi.plan_id
WHERE vp.id IS NULL;

-- 6.ب. أنشطة تشير إلى بنود زيارة غير موجودة
SELECT
    '6.B. ORPHAN_ACTIVITIES' AS audit_rule,
    act.id AS act_id,
    act.visit_plan_item_id
FROM public.activities act
LEFT JOIN public.visit_plan_items vpi ON vpi.id = act.visit_plan_item_id
WHERE act.visit_plan_item_id IS NOT NULL
  AND vpi.id IS NULL;

-- 6.ج. إجابات استبيان تشير إلى أنشطة أو أسئلة أو قوالب مفقودة
SELECT
    '6.C. ORPHAN_CHECKLIST_RESPONSES' AS audit_rule,
    vcr.id AS response_id,
    vcr.activity_id,
    vcr.template_id,
    vcr.question_id
FROM public.visit_checklist_responses vcr
LEFT JOIN public.activities act ON act.id = vcr.activity_id
LEFT JOIN public.visit_checklist_templates vct ON vct.id = vcr.template_id
LEFT JOIN public.visit_checklist_questions vcq ON vcq.id = vcr.question_id
WHERE act.id IS NULL
   OR vct.id IS NULL
   OR vcq.id IS NULL;

-- 6.د. خطط مؤكدة أو جارية فارغة من البنود
SELECT
    '6.D. EMPTY_ACTIVE_PLANS' AS audit_rule,
    vp.id AS plan_id,
    vp.employee_id,
    vp.plan_date,
    vp.status
FROM public.visit_plans vp
LEFT JOIN public.visit_plan_items vpi ON vpi.plan_id = vp.id
WHERE vp.status IN ('confirmed', 'in_progress')
GROUP BY vp.id, vp.employee_id, vp.plan_date, vp.status
HAVING COUNT(vpi.id) = 0;


-- ─── 7. تدقيق العدادات والتقدم المخزن وحالات رأس الخطة ───

-- 7.أ. اختلاف العدادات المخزنة بالخطة عن العد الفعلي المباشر لبنودها
SELECT
    '7.A. PLAN_COUNTERS_MISMATCH' AS audit_rule,
    vp.id AS plan_id,
    vp.total_customers AS stored_total,
    COUNT(vpi.id) AS actual_total,
    vp.completed_count AS stored_completed,
    COUNT(vpi.id) FILTER (WHERE vpi.status = 'completed') AS actual_completed,
    vp.skipped_count AS stored_skipped,
    COUNT(vpi.id) FILTER (WHERE vpi.status = 'skipped') AS actual_skipped,
    vp.missed_count AS stored_missed,
    COUNT(vpi.id) FILTER (WHERE vpi.status = 'missed') AS actual_missed
FROM public.visit_plans vp
LEFT JOIN public.visit_plan_items vpi ON vpi.plan_id = vp.id
GROUP BY vp.id, vp.total_customers, vp.completed_count, vp.skipped_count, vp.missed_count
HAVING vp.total_customers != COUNT(vpi.id)
    OR vp.completed_count != COUNT(vpi.id) FILTER (WHERE vpi.status = 'completed')
    OR vp.skipped_count != COUNT(vpi.id) FILTER (WHERE vpi.status = 'skipped')
    OR vp.missed_count != COUNT(vpi.id) FILTER (WHERE vpi.status = 'missed');

-- 7.ب. تدقيق حالة رأس الخطة مقابل التوزيع الفعلي لحالات بنودها (يشمل تعارضات الحالات المغلقة)
SELECT
    '7.B. PLAN_STATUS_VS_ITEMS_MISMATCH' AS audit_rule,
    vp.id AS plan_id,
    vp.status AS plan_status,
    COUNT(vpi.id) AS total_items,
    COUNT(vpi.id) FILTER (WHERE vpi.status = 'completed') AS completed_items,
    COUNT(vpi.id) FILTER (WHERE vpi.status = 'skipped') AS skipped_items,
    COUNT(vpi.id) FILTER (WHERE vpi.status = 'rescheduled') AS rescheduled_items,
    COUNT(vpi.id) FILTER (WHERE vpi.status = 'missed') AS missed_items
FROM public.visit_plans vp
JOIN public.visit_plan_items vpi ON vpi.plan_id = vp.id
GROUP BY vp.id, vp.status
HAVING
    -- خطة مكتملة ولكن تحتوي على بنود غير مكتملة
    (vp.status = 'completed' AND COUNT(vpi.id) != COUNT(vpi.id) FILTER (WHERE vpi.status = 'completed'))
    -- خطة فائتة ولكن تحتوي على بنود مكتملة أو متخطاة
    OR (vp.status = 'missed' AND COUNT(vpi.id) != COUNT(vpi.id) FILTER (WHERE vpi.status = 'missed'))
    -- خطة جزئية ولكن تحتوي على بنود معلقة
    OR (vp.status = 'partial' AND EXISTS (SELECT 1 FROM public.visit_plan_items WHERE plan_id = vp.id AND status IN ('pending', 'in_progress')))
    -- خطة ملغاة ولكن تحتوي على بنود مكتملة أو جارية
    OR (vp.status = 'cancelled' AND EXISTS (SELECT 1 FROM public.visit_plan_items WHERE plan_id = vp.id AND status IN ('completed', 'in_progress')))
    -- خطة معلنة/جارية ولكن كافة بنودها وصلت لحالة نهائية
    OR (vp.status IN ('confirmed', 'in_progress') AND NOT EXISTS (SELECT 1 FROM public.visit_plan_items WHERE plan_id = vp.id AND status IN ('pending', 'in_progress')))
    -- أي خطة نهائية مغلقة تحتوي على بنود معلقة
    OR (vp.status IN ('completed', 'partial', 'cancelled', 'missed') AND EXISTS (SELECT 1 FROM public.visit_plan_items WHERE plan_id = vp.id AND status IN ('pending', 'in_progress')));


-- ─── 8. تدقيق بنود الخطط المعلقة في الماضي (Stale Pending Items) ───

-- 8.أ. بنود بقيت معلقة (pending/in_progress) على الرغم من فوات تاريخ خطتها (بتوقيت القاهرة)
SELECT
    '8.A. STALE_PENDING_IN_PAST' AS audit_rule,
    vpi.id AS item_id,
    vpi.status,
    vp.plan_date,
    vp.id AS plan_id,
    vp.employee_id
FROM public.visit_plan_items vpi
JOIN public.visit_plans vp ON vp.id = vpi.plan_id
WHERE vp.plan_date < (CURRENT_TIMESTAMP AT TIME ZONE 'Africa/Cairo')::DATE
  AND vpi.status IN ('pending', 'in_progress');


-- ─── 9. تدقيق أمان الصور وBase64 في الاستبيانات ───

-- 9.أ. كشف الصور المشفرة بصيغة Base64 في answer_value و answer_json (تفتيش نصي شامل لـ Data URI)
SELECT
    '9.A. BASE64_IMAGE_DATA_DETECTED' AS audit_rule,
    id AS response_id,
    activity_id,
    template_id,
    question_id,
    OCTET_LENGTH(answer_value) AS value_size_bytes,
    OCTET_LENGTH(answer_json::text) AS json_size_bytes
FROM public.visit_checklist_responses
WHERE answer_value ILIKE '%data:image/%;base64,%'
   OR answer_json::text ILIKE '%data:image/%;base64,%';

-- 9.ب. عدم تطابق السؤال (question_id) مع معرف القالب (template_id) في الإجابات المرفوعة
SELECT
    '9.B. QUESTION_TEMPLATE_ID_MISMATCH' AS audit_rule,
    vcr.id AS response_id,
    vcr.activity_id,
    vcr.template_id AS response_template_id,
    vcq.template_id AS question_template_id,
    vcr.question_id
FROM public.visit_checklist_responses vcr
JOIN public.visit_checklist_questions vcq ON vcq.id = vcr.question_id
WHERE vcr.template_id != vcq.template_id;


-- ─── 10. تدقيق تعارض العميل والفرع بين المستويات المختلفة ───

-- 10.أ. اختلاف العميل بين بند الزيارة والنشاط الفعلي المرتبط به
SELECT
    '10.A. CUSTOMER_MISMATCH_ITEM_VS_ACTIVITY' AS audit_rule,
    vpi.id AS item_id,
    vpi.customer_id AS item_customer_id,
    act.id AS act_id,
    act.customer_id AS act_customer_id
FROM public.visit_plan_items vpi
JOIN public.activities act ON act.id = vpi.activity_id
WHERE act.deleted_at IS NULL
  AND vpi.customer_id != act.customer_id;

-- 10.ب. اختلاف العميل بين النشاط والطلب المالي المرتبط به
SELECT
    '10.B. CUSTOMER_MISMATCH_ACTIVITY_VS_ORDER' AS audit_rule,
    act.id AS act_id,
    act.customer_id AS act_customer_id,
    so.id AS order_id,
    so.customer_id AS order_customer_id
FROM public.activities act
JOIN public.sales_orders so ON so.id = act.order_id
WHERE act.deleted_at IS NULL
  AND act.customer_id != so.customer_id;

-- 10.ج. اختلاف العميل بين النشاط والتحصيل المالي المرتبط به
SELECT
    '10.C. CUSTOMER_MISMATCH_ACTIVITY_VS_COLLECTION' AS audit_rule,
    act.id AS act_id,
    act.customer_id AS act_customer_id,
    pr.id AS collection_id,
    pr.customer_id AS collection_customer_id
FROM public.activities act
JOIN public.payment_receipts pr ON pr.id = act.collection_id
WHERE act.deleted_at IS NULL
  AND act.customer_id != pr.customer_id;

-- 10.د. فحص الفجوات الهيكلية في ربط الفروع بالمعاملات المالية (لعدم احتواء جداول المالية الحالية على customer_branch_id)
SELECT
    '10.D. FINANCE_BRANCH_LINKAGE_GAP' AS audit_rule,
    c.table_name,
    c.column_name
FROM (
    VALUES
      ('sales_orders', 'customer_branch_id'),
      ('payment_receipts', 'customer_branch_id')
) c(table_name, column_name)
LEFT JOIN information_schema.columns col
  ON col.table_schema = 'public'
  AND col.table_name = c.table_name
  AND col.column_name = c.column_name
WHERE col.column_name IS NULL;


-- ─── 11. تدقيق أمان الـ RLS والصلاحيات (RLS & Table Privileges Audit) ───

-- 11.أ. تدقيق تفعيل RLS وفرضه الجبري على جداول موديول الزيارات والأنشطة
SELECT
    '11.A. TABLE_RLS_STATUS' AS audit_rule,
    c.relname AS table_name,
    c.relrowsecurity AS is_rls_enabled,
    c.relforcerowsecurity AS is_rls_forced
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('visit_plans', 'visit_plan_items', 'activities', 'visit_checklist_responses', 'visit_checklist_templates', 'visit_checklist_questions');

-- 11.ب. تدقيق سياسات الـ RLS الفعلية الحالية من pg_policies (لإبراز vp_write وسقوط read_team)
SELECT
    '11.B. CURRENT_RLS_POLICIES' AS audit_rule,
    policyname,
    tablename,
    roles,
    cmd,
    qual,
    with_check
FROM pg_catalog.pg_policies
WHERE tablename IN ('visit_plans', 'visit_plan_items', 'activities', 'visit_checklist_responses');

-- 11.ج. تدقيق صلاحيات الجداول (Table Privileges) الممنوحة للأدوار الحساسة (باستخدام information_schema.table_privileges لدقة PUBLIC)
SELECT
    '11.C. TABLE_PRIVILEGES' AS audit_rule,
    grantee,
    table_name,
    privilege_type,
    is_grantable
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name IN ('visit_plans', 'visit_plan_items', 'activities', 'visit_checklist_responses')
  AND grantee IN ('PUBLIC', 'anon', 'authenticated');


-- ─── 12. تدقيق أمان وصلاحيات الدوال وتواقيعها (Function Security Audit) ───

-- 12.أ. تدقيق خصائص الدوال الحساسة (SECURITY DEFINER ومسار البحث search_path والصلاحيات)
SELECT
    '12.A. FUNCTION_GOVERNANCE' AS audit_rule,
    p.oid::regprocedure AS function_signature,
    p.prosecdef AS is_security_definer,
    p.proconfig AS search_path_config,
    p.proacl AS access_control_list,
    pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE') AS has_auth_execute,
    pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE') AS has_anon_execute,
    -- تدقيق PUBLIC عبر aclexplode لتجاوز الحدود التقليدية لـ has_function_privilege
    EXISTS (
        SELECT 1
        FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) x
        WHERE x.grantee = 0
          AND x.privilege_type = 'EXECUTE'
    ) AS has_public_execute
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND (
     p.proname LIKE '%visit%'
     OR p.proname LIKE '%activity%'
     OR p.proname LIKE '%checklist%'
  );


-- ─── 13. تدقيق الصلاحيات الممنوحة للأدوار بنظام EDARA v2 (Role Permissions Audit) ───

SELECT
    '13.A. ROLE_PERMISSIONS_AUDIT' AS audit_rule,
    rp.permission,
    r.name AS role_name
FROM public.role_permissions rp
JOIN public.roles r ON r.id = rp.role_id
WHERE rp.permission IN (
    'activities.create', 'activities.update_own', 'activities.read_team', 'activities.read_all',
    'visit_plans.create', 'visit_plans.update', 'visit_plans.confirm', 'visit_plans.cancel', 'visit_plans.read_team', 'visit_plans.read_all',
    'visit_plans.read_own', 'visit_plans.update_own'
);


-- ─── 14. تدقيق بيئة التشغيل وخصائص قاعدة البيانات (Database Environment) ───

-- 14.أ. إصدار PostgreSQL، والمنطقة الزمنية الافتراضية، والإضافات المتاحة وحالة pg_cron
SELECT
    '14.A. POSTGRES_VERSION_AND_TZ' AS audit_rule,
    version() AS pg_version,
    current_setting('timezone') AS db_timezone;

SELECT
    '14.B. EXTENSION_STATUS' AS audit_rule,
    name,
    default_version,
    installed_version
FROM pg_available_extensions
WHERE name IN ('pg_cron', 'uuid-ossp', 'pgcrypto');


-- 14.ج. دالة SHA-256 المطلوبة لمحرك idempotency في مخطط pgcrypto الفعلي
SELECT
    '14.C. MISSING_EXTENSIONS_DIGEST' AS audit_rule,
    'extensions.digest(text, text)' AS required_function
WHERE NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'extensions'
      AND p.proname = 'digest'
      AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'text, text'
);

-- ─── 15. تقرير معلوماتي للهياكل التي ستضيفها مراحل Migrations الزيارات ───
-- هذه النتائج متوقعة قبل تطبيق المراحل المعنية ولا تُعامل وحدها كمخالفات بيانات أو موانع نشر.

-- 15.أ. التحقق من وجود الحقول الجديدة المحددة بالخطط والبنود والجداول الجديدة
SELECT
    '15.A. INFO_PLANNED_MISSING_COLUMNS' AS audit_rule,
    t.table_name,
    c.column_name
FROM (
    VALUES
      ('visit_plan_items', 'customer_branch_id'),
      ('visit_plan_items', 'start_accuracy_m'),
      ('visit_plan_items', 'end_accuracy_m'),
      ('visit_plan_items', 'start_distance_m'),
      ('visit_plan_items', 'end_distance_m'),
      ('visit_plan_items', 'expected_lat'),
      ('visit_plan_items', 'expected_lng'),
      ('visit_plan_items', 'expected_location_source'),
      ('visit_plan_items', 'expected_location_id'),
      ('visit_plan_items', 'gps_validation_status'),
      ('visit_plan_items', 'gps_review_status'),
      ('visit_plan_items', 'gps_exception_reason'),
      ('visit_plan_items', 'gps_exception_requested_by'),
      ('visit_plan_items', 'gps_exception_reviewed_by'),
      ('visit_plan_items', 'gps_exception_reviewed_at'),
      ('visit_plan_items', 'rescheduled_from_item_id'),
      ('visit_plan_items', 'replacement_item_id'),
      ('visit_plan_items', 'stale_since'),
      ('visit_plan_items', 'server_started_at'),
      ('visit_plan_items', 'server_completed_at'),
      ('visit_plan_items', 'client_started_at'),
      ('visit_plan_items', 'client_completed_at'),
      ('visit_plan_items', 'device_timezone'),
      ('visit_plan_items', 'start_lat'),
      ('visit_plan_items', 'start_lng'),
      ('visit_plan_items', 'end_lat'),
      ('visit_plan_items', 'end_lng'),
      ('visit_plan_items', 'reschedule_reason')
) t(table_name, column_name)
LEFT JOIN information_schema.columns c
  ON c.table_schema = 'public'
  AND c.table_name = t.table_name
  AND c.column_name = t.column_name
WHERE c.column_name IS NULL;

-- 15.ب. الجداول الجديدة التي ستنشئها Foundation (معلوماتي قبل التطبيق)
SELECT
    '15.B. INFO_PLANNED_MISSING_TABLES' AS audit_rule,
    t.table_schema,
    t.table_name
FROM (
    VALUES
      ('private', 'visit_operation_requests'),
      ('private', 'visit_sync_conflicts')
) t(table_schema, table_name)
LEFT JOIN information_schema.tables tab
  ON tab.table_schema = t.table_schema
  AND tab.table_name = t.table_name
WHERE tab.table_name IS NULL;
