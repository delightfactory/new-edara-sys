-- ═══════════════════════════════════════════════════════════════
-- 40_hr_attendance_final_completion.sql
-- HR Attendance — Full Functional Closure 100%
--
-- Additive & non-destructive. Safe to re-run (idempotent).
--
-- Changes:
--   1. hr.gps_accuracy_threshold_meters → marked deprecated in company_settings
--   2. validate_attendance_location → rebuilt to delegate to
--      resolve_employee_attendance_location_context (consistent semantics)
--      documented as "precheck only" — not the source of truth for acceptance
-- ═══════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────
-- 1) mark hr.gps_accuracy_threshold_meters as deprecated
--
-- الإعداد الفعلي الآن هو:
--   hr.default_gps_accuracy_threshold_meters (على مستوى الشركة)
--   hr_work_locations.gps_accuracy_threshold  (على مستوى الموقع)
--
-- نعلّق الإعداد القديم deprecated في description حتى:
--   - لا يختفي من البيانات القديمة (backward safe)
--   - لكن يتضح أنه غير مستخدم فعليًا
-- ─────────────────────────────────────────────────────────────

UPDATE company_settings
SET description = '[DEPRECATED — لم تعد هذه الإعداد تدخل في القرار الفعلي. '
               || 'استخدم hr.default_gps_accuracy_threshold_meters بدلًا منها، '
               || 'أو gps_accuracy_threshold على مستوى الموقع في hr_work_locations.]'
WHERE key = 'hr.gps_accuracy_threshold_meters';

-- ملاحظة: لا نحذف السجل لأن البيانات القديمة قد تشير إليه.
-- الإعداد ببساطة لم يعد يظهر في HRSettingsPage (تم حذفه من الـ UI).


-- ─────────────────────────────────────────────────────────────
-- 2) validate_attendance_location
--
-- رُبطت الآن بـ resolve_employee_attendance_location_context
-- لتكون متسقة الـ semantics مع المنطق النهائي.
--
-- مهم: هذه الدالة هي PRECHECK ONLY.
--   - لا تستبدل record_attendance_gps_v2 كمصدر القبول النهائي
--   - لا تطبق GPS accuracy threshold (لأنها لا تتلقى accuracy من كل مسارات الاستدعاء)
--   - نتيجتها valid=true تعني "الموقع مقبول من حيث النطاق الجغرافي"
--   - لكن القبول الفعلي للتسجيل يبقى داخل record_attendance_gps_v2
--
-- ما تغيّر:
--   - قبلها: تستدعي resolve_employee_attendance_location_context مباشرة
--   - الآن:  تفعل نفس الشيء لكن بتوثيق واضح ومخرجات متسقة
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION validate_attendance_location(
  p_employee_id UUID,
  p_latitude NUMERIC,
  p_longitude NUMERIC,
  p_gps_accuracy NUMERIC DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ctx JSONB;
BEGIN
  -- ★ تفويض كامل إلى resolve_employee_attendance_location_context
  -- هذا يضمن أن الأكواد / الدلالات / حد الميدان / allowed_ids
  -- كلها متسقة مع منطق التسجيل الفعلي في record_attendance_gps_v2
  v_ctx := resolve_employee_attendance_location_context(
    p_employee_id,
    p_latitude,
    p_longitude,
    'check_in' -- نستخدم check_in كـ default للـ precheck
  );

  -- ملاحظة مهمة:
  -- validate_attendance_location هي PRECHECK ONLY.
  -- أي نتيجة valid=true هنا تعني "الموقع مقبول جغرافيًا"
  -- لكن القبول الفعلي للتسجيل يعتمد أيضًا على:
  --   (أ) دقة GPS (p_gps_accuracy) التي تُفحص داخل record_attendance_gps_v2
  --   (ب) حالة اليوم (punch_in_time / punch_out_time)
  --   (ج) أي checks إضافية داخل record_attendance_gps_v2
  --
  -- p_gps_accuracy لا تُستخدم هنا عمدًا —
  -- لأن هذا الـ precheck مخصص للتحقق الجغرافي فقط.
  -- إذا احتجت فحص accuracy قبل الوصول للـ RPC، نفذ ذلك على مستوى الـ client.

  RETURN v_ctx;
END;
$$;

GRANT EXECUTE ON FUNCTION validate_attendance_location(UUID, NUMERIC, NUMERIC, NUMERIC) TO authenticated;


-- ═══════════════════════════════════════════════════════════════
-- END OF MIGRATION 40
-- ═══════════════════════════════════════════════════════════════
