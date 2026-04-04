-- ============================================================
-- 01_extract_policies.sql
-- استخراج السياسات الحالية من pg_catalog مباشرةً
--
-- طريقة التشغيل:
--   1. افتح Supabase Dashboard → SQL Editor
--   2. انسخ هذا الاستعلام وشغّله
--   3. في النتيجة اضغط "Download CSV" أو انسخ JSON
--   4. احفظ الملف باسم: tools/policies_snapshot.json
--
-- ملاحظة أمنية:
--   هذا استعلام قراءة فقط (SELECT) — لا يُغيّر أي شيء
-- ============================================================

SELECT
  json_agg(
    json_build_object(
      'tablename',    p.tablename,
      'policyname',   p.policyname,
      'permissive',   p.permissive,
      'roles',        p.roles,
      'cmd',          p.cmd,
      'qual',         p.qual,
      'with_check',   p.with_check
    )
    ORDER BY p.tablename, p.policyname
  ) AS policies_snapshot
FROM pg_policies p
WHERE p.schemaname = 'public';
