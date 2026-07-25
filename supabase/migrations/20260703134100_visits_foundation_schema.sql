-- =============================================================================
-- EDARA v2 — visits_foundation_schema.sql
-- Migration Phase B: Foundation Schema for Visits & Field Operations
--
-- يطبق يدوياً فقط بعد اجتياز التدقيق القبلي وبإذن مباشر، داخل معاملة واحدة.
-- =============================================================================

BEGIN;

-- ─── 1. تهيئة مخطط البيانات الخاص (private) ───
CREATE SCHEMA IF NOT EXISTS private;

-- ─── 2. جدول طلبات العمليات لضمان منع التكرار والذرية (private.visit_operation_requests) ───
-- سياسة الاحتفاظ بطلبات العمليات (Retention Policy):
-- 1. العمليات المكتملة أو الفاشلة التي لا ترتبط بتعارض مزامنة: تُعتبر مرشحة للتنظيف الدوري بعد مرور 14 يوماً بناءً على completed_at.
-- 2. العمليات المرتبطة بتعارض مزامنة (في جدول visit_sync_conflicts): يمنع حذفها نهائياً قبل حسم التعارض
--    بقرار إداري صريح وانتهاء فترة الاحتفاظ التدقيقية للنزاع.
-- * ملحوظة: آلية التنظيف التلقائي مؤجلة وسيتم جدولتها وتطبيقها لاحقاً عبر محرك العمليات (Operations Engine) في المراحل القادمة.
CREATE TABLE private.visit_operation_requests (
  operation_id   UUID PRIMARY KEY,
  actor_id       UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  operation_name VARCHAR(100) NOT NULL CONSTRAINT chk_op_name_not_empty CHECK (NULLIF(BTRIM(operation_name), '') IS NOT NULL),
  request_hash   VARCHAR(64) NOT NULL CONSTRAINT chk_hexadecimal CHECK (request_hash ~ '^[0-9a-fA-F]{64}$'),
  status         VARCHAR(20) NOT NULL DEFAULT 'pending' CONSTRAINT chk_status CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  result_json    JSONB,
  error_code     VARCHAR(50),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  started_at     TIMESTAMPTZ,
  completed_at   TIMESTAMPTZ,
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

  -- قيود دورة طلب العملية المعززة والدقيقة
  CONSTRAINT chk_op_lifecycle CHECK (
    (status = 'pending' AND started_at IS NULL AND completed_at IS NULL) OR
    (status = 'processing' AND started_at IS NOT NULL AND completed_at IS NULL AND (created_at <= started_at)) OR
    (status IN ('completed', 'failed') AND started_at IS NOT NULL AND completed_at IS NOT NULL AND (started_at <= completed_at) AND (created_at <= started_at))
  ),
  CONSTRAINT chk_failed_op_error CHECK (
    status != 'failed' OR NULLIF(BTRIM(error_code), '') IS NOT NULL
  )
);

CREATE INDEX idx_visit_op_requests_status ON private.visit_operation_requests(status);
CREATE INDEX idx_visit_op_requests_created_at ON private.visit_operation_requests(created_at);

-- فهرس جزئي محسن لتسريع مهام محرك التنظيف الدوري
CREATE INDEX idx_visit_op_requests_cleanup
  ON private.visit_operation_requests(completed_at)
  WHERE status IN ('completed', 'failed');

DROP TRIGGER IF EXISTS trg_visit_operation_requests_updated_at ON private.visit_operation_requests;
CREATE TRIGGER trg_visit_operation_requests_updated_at
  BEFORE UPDATE ON private.visit_operation_requests
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE private.visit_operation_requests ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE private.visit_operation_requests FROM PUBLIC, anon, authenticated;

-- ─── 3. جدول تعارضات المزامنة التاريخية (private.visit_sync_conflicts) ───
CREATE TABLE private.visit_sync_conflicts (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- ON DELETE RESTRICT لمنع التنظيف التلقائي من إسقاط سجلات تعارضات معلقة في الميدان
  operation_id         UUID NOT NULL UNIQUE REFERENCES private.visit_operation_requests(operation_id) ON DELETE RESTRICT,
  visit_plan_item_id   UUID NOT NULL REFERENCES public.visit_plan_items(id) ON DELETE RESTRICT,
  actor_id             UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  operation_name       VARCHAR(100) NOT NULL CONSTRAINT chk_sync_op_name_not_empty CHECK (NULLIF(BTRIM(operation_name), '') IS NOT NULL),
  conflict_reason_code VARCHAR(50) NOT NULL CONSTRAINT chk_reason_code_not_empty CHECK (NULLIF(BTRIM(conflict_reason_code), '') IS NOT NULL),
  conflict_payload     JSONB NOT NULL CONSTRAINT chk_conflict_payload_is_object CHECK (jsonb_typeof(conflict_payload) = 'object'),
  status               VARCHAR(20) NOT NULL DEFAULT 'pending' CONSTRAINT chk_sync_status CHECK (status IN ('pending', 'resolved_accepted', 'resolved_rejected')),
  reviewed_by          UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  reviewed_at          TIMESTAMPTZ,
  review_notes         TEXT,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

  -- قيد دورة المراجعة للتعارضات الميدانية
  CONSTRAINT chk_sync_conflict_lifecycle CHECK (
    (status = 'pending' AND reviewed_by IS NULL AND reviewed_at IS NULL) OR
    (status IN ('resolved_accepted', 'resolved_rejected') AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)
  )
);

CREATE INDEX idx_visit_sync_conflicts_item ON private.visit_sync_conflicts(visit_plan_item_id);
CREATE INDEX idx_visit_sync_conflicts_status ON private.visit_sync_conflicts(status);

DROP TRIGGER IF EXISTS trg_visit_sync_conflicts_updated_at ON private.visit_sync_conflicts;
CREATE TRIGGER trg_visit_sync_conflicts_updated_at
  BEFORE UPDATE ON private.visit_sync_conflicts
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE private.visit_sync_conflicts ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE private.visit_sync_conflicts FROM PUBLIC, anon, authenticated;

-- سحب الصلاحيات التلقائية للجداول والدوال المستقبلية داخل المخطط الخاص لضمان العزل الكامل
ALTER DEFAULT PRIVILEGES IN SCHEMA private REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA private REVOKE ALL ON FUNCTIONS FROM PUBLIC, anon, authenticated;


-- ─── 4. تعديل حقول رأس خطة الزيارة (public.visit_plans) ───
-- تم استبعاد IF NOT EXISTS لضمان الفشل المبكر عند وجود هياكل سابقة معارِضة
ALTER TABLE public.visit_plans
  ADD COLUMN organizational_branch_id UUID REFERENCES public.branches(id) ON DELETE RESTRICT,
  ADD COLUMN rescheduled_count INTEGER DEFAULT 0 NOT NULL CONSTRAINT chk_rescheduled_count CHECK (rescheduled_count >= 0),
  ADD COLUMN administrative_closed_at TIMESTAMPTZ,
  ADD COLUMN administrative_closed_by UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  ADD COLUMN administrative_close_reason TEXT;

-- Backfill آمن ومستقل لإدراج الفرع التنظيمي للخطط التاريخية بناءً على فرع الموظف
UPDATE public.visit_plans vp
SET organizational_branch_id = emp.branch_id
FROM public.hr_employees emp
WHERE emp.id = vp.employee_id
  AND vp.organizational_branch_id IS NULL;

-- Backfill ذري كامل لجميع عدادات الخطة من بنود الخطة الفعلية المربوطة
UPDATE public.visit_plans vp
SET
  total_customers = COALESCE(counts.total_count, 0),
  completed_count = COALESCE(counts.completed_count, 0),
  skipped_count = COALESCE(counts.skipped_count, 0),
  missed_count = COALESCE(counts.missed_count, 0),
  rescheduled_count = COALESCE(counts.rescheduled_count, 0)
FROM (
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
) AS counts
WHERE vp.id = counts.plan_id;

-- إضافة حقل التقدم closure_pct وقيد نطاقه بعد تعديل وتصحيح العدادات تلافياً لمخالفة القيود
ALTER TABLE public.visit_plans
  ADD COLUMN closure_pct NUMERIC(5,2) GENERATED ALWAYS AS (
    CASE
      WHEN total_customers = 0 THEN 0
      ELSE ROUND(((completed_count + skipped_count + rescheduled_count + missed_count)::NUMERIC / total_customers::NUMERIC) * 100, 2)
    END
  ) STORED CONSTRAINT chk_closure_pct_range CHECK (closure_pct BETWEEN 0 AND 100);

-- فهارس الفروع والتواريخ لتسريع عمليات البحث للمشرفين
CREATE INDEX idx_visit_plans_branch_date ON public.visit_plans(organizational_branch_id, plan_date);


-- ─── 5. تعديل حقول بنود خطة الزيارة وتثبيت أجهزة القياس الجغرافية والزمنية (public.visit_plan_items) ───
ALTER TABLE public.visit_plan_items
  ADD COLUMN customer_branch_id UUID REFERENCES public.customer_branches(id) ON DELETE RESTRICT,
  ADD COLUMN expected_location_source VARCHAR(50) CONSTRAINT chk_expected_location_source CHECK (expected_location_source IN ('customer', 'customer_branch')),
  ADD COLUMN expected_location_id UUID,
  ADD COLUMN expected_lat NUMERIC(10,7),
  ADD COLUMN expected_lng NUMERIC(10,7),
  ADD COLUMN start_lat NUMERIC(10,7),
  ADD COLUMN start_lng NUMERIC(10,7),
  ADD COLUMN start_accuracy_m NUMERIC(8,2),
  ADD COLUMN start_distance_m NUMERIC(8,2),
  ADD COLUMN end_lat NUMERIC(10,7),
  ADD COLUMN end_lng NUMERIC(10,7),
  ADD COLUMN end_accuracy_m NUMERIC(8,2),
  ADD COLUMN end_distance_m NUMERIC(8,2),
  ADD COLUMN server_started_at TIMESTAMPTZ,
  ADD COLUMN server_completed_at TIMESTAMPTZ,
  ADD COLUMN client_started_at TIMESTAMPTZ,
  ADD COLUMN client_completed_at TIMESTAMPTZ,
  ADD COLUMN device_timezone VARCHAR(100),
  ADD COLUMN gps_validation_status VARCHAR(50) DEFAULT 'not_checked' NOT NULL CONSTRAINT chk_gps_validation_status CHECK (gps_validation_status IN ('not_checked', 'passed', 'failed_distance', 'failed_accuracy', 'no_coordinates')),
  ADD COLUMN gps_review_status VARCHAR(50) DEFAULT 'not_required' NOT NULL CONSTRAINT chk_gps_review_status CHECK (gps_review_status IN ('not_required', 'pending', 'approved', 'rejected')),
  ADD COLUMN gps_exception_reason TEXT,
  ADD COLUMN gps_exception_requested_by UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  ADD COLUMN gps_exception_reviewed_by UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  ADD COLUMN gps_exception_reviewed_at TIMESTAMPTZ,
  ADD COLUMN rescheduled_from_item_id UUID REFERENCES public.visit_plan_items(id) ON DELETE RESTRICT,
  ADD COLUMN replacement_item_id UUID REFERENCES public.visit_plan_items(id) ON DELETE RESTRICT,
  ADD COLUMN stale_since TIMESTAMPTZ;

-- إضافة قيود التحقق الجغرافية والزمنية والنسبية لجدول البنود
ALTER TABLE public.visit_plan_items
  -- 1. قيود نطاق خطوط العرض والطول الجغرافية
  ADD CONSTRAINT chk_expected_coords CHECK (
    (expected_lat IS NULL AND expected_lng IS NULL) OR
    (expected_lat BETWEEN -90 AND 90 AND expected_lng BETWEEN -180 AND 180)
  ),
  ADD CONSTRAINT chk_start_coords CHECK (
    (start_lat IS NULL AND start_lng IS NULL) OR
    (start_lat BETWEEN -90 AND 90 AND start_lng BETWEEN -180 AND 180)
  ),
  ADD CONSTRAINT chk_end_coords CHECK (
    (end_lat IS NULL AND end_lng IS NULL) OR
    (end_lat BETWEEN -90 AND 90 AND end_lng BETWEEN -180 AND 180)
  ),

  -- 2. التحقق من الزوج الكامل للإحداثيات (خط العرض والطول معاً أو لا شيء)
  ADD CONSTRAINT chk_expected_pair CHECK ((expected_lat IS NULL) = (expected_lng IS NULL)),
  ADD CONSTRAINT chk_start_pair CHECK ((start_lat IS NULL) = (start_lng IS NULL)),
  ADD CONSTRAINT chk_end_pair CHECK ((end_lat IS NULL) = (end_lng IS NULL)),

  -- 3. دقة الـ GPS والمسافات يجب أن تكون قيمًا غير سالبة
  ADD CONSTRAINT chk_start_accuracy_nonneg CHECK (start_accuracy_m >= 0),
  ADD CONSTRAINT chk_start_distance_nonneg CHECK (start_distance_m >= 0),
  ADD CONSTRAINT chk_end_accuracy_nonneg CHECK (end_accuracy_m >= 0),
  ADD CONSTRAINT chk_end_distance_nonneg CHECK (end_distance_m >= 0),

  -- 4. منع ارتباط البند بنفسه كبند بديل أو بند معاد جدولته
  ADD CONSTRAINT chk_no_self_reschedule CHECK (id != rescheduled_from_item_id),
  ADD CONSTRAINT chk_no_self_replacement CHECK (id != replacement_item_id),

  -- 5. ترتيب أزمنة الخادم وأزمنة العميل الميدانية
  ADD CONSTRAINT chk_server_times CHECK (
    server_completed_at IS NULL OR server_started_at IS NULL OR server_completed_at >= server_started_at
  ),
  ADD CONSTRAINT chk_client_times CHECK (
    client_completed_at IS NULL OR client_started_at IS NULL OR client_completed_at >= client_started_at
  ),

  -- 6. قيد دورة المراجعة الجغرافية المدمج للـ GPS
  ADD CONSTRAINT chk_gps_review_lifecycle CHECK (
    (gps_review_status = 'not_required' AND
     gps_exception_reason IS NULL AND gps_exception_requested_by IS NULL AND
     gps_exception_reviewed_by IS NULL AND gps_exception_reviewed_at IS NULL) OR
    (gps_review_status = 'pending' AND
     NULLIF(BTRIM(gps_exception_reason), '') IS NOT NULL AND gps_exception_requested_by IS NOT NULL AND
     gps_exception_reviewed_by IS NULL AND gps_exception_reviewed_at IS NULL) OR
    (gps_review_status IN ('approved', 'rejected') AND
     NULLIF(BTRIM(gps_exception_reason), '') IS NOT NULL AND gps_exception_requested_by IS NOT NULL AND
     gps_exception_reviewed_by IS NOT NULL AND gps_exception_reviewed_at IS NOT NULL)
  ),

  -- 7. قيد اكتمال لقطة الموقع المتوقع (expected location snapshot completeness check)
  ADD CONSTRAINT chk_expected_location_snapshot CHECK (
    (expected_location_source IS NULL AND expected_location_id IS NULL AND expected_lat IS NULL AND expected_lng IS NULL) OR
    (expected_location_source IS NOT NULL AND expected_location_id IS NOT NULL AND expected_lat IS NOT NULL AND expected_lng IS NOT NULL)
  );

-- فهارس الفروع وبنود البحث الجغرافي والتعليق والمراجعة
CREATE INDEX idx_visit_plan_items_cust_branch ON public.visit_plan_items(customer_branch_id);

CREATE INDEX idx_visit_plan_items_gps_pending
  ON public.visit_plan_items(gps_review_status)
  WHERE gps_review_status = 'pending';

CREATE INDEX idx_visit_plan_items_stale
  ON public.visit_plan_items(stale_since)
  WHERE stale_since IS NOT NULL;

-- فهارس فريدة جزئية لمنع تكرار البدائل أو إعادة الجدولة المتعددة لنفس البند
CREATE UNIQUE INDEX idx_visit_plan_items_rescheduled_from_unique
  ON public.visit_plan_items(rescheduled_from_item_id)
  WHERE rescheduled_from_item_id IS NOT NULL;

CREATE UNIQUE INDEX idx_visit_plan_items_replacement_unique
  ON public.visit_plan_items(replacement_item_id)
  WHERE replacement_item_id IS NOT NULL;

COMMIT;
