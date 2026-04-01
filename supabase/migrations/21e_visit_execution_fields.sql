-- ============================================================================
-- 21e: حقول التنفيذ الميداني لجدول visit_plan_items + call_plan_items
-- يُضيف أعمدة GPS + metadata لدعم وضع التنفيذ الذكي
-- ============================================================================

-- ── 1) أعمدة GPS و metadata لجدول visit_plan_items ──
ALTER TABLE public.visit_plan_items
  ADD COLUMN IF NOT EXISTS gps_lat        DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS gps_lng        DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS end_gps_lat    DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS end_gps_lng    DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS metadata       JSONB DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.visit_plan_items.gps_lat     IS 'إحداثي خط العرض عند بدء الزيارة';
COMMENT ON COLUMN public.visit_plan_items.gps_lng     IS 'إحداثي خط الطول عند بدء الزيارة';
COMMENT ON COLUMN public.visit_plan_items.end_gps_lat IS 'إحداثي خط العرض عند إنهاء الزيارة';
COMMENT ON COLUMN public.visit_plan_items.end_gps_lng IS 'إحداثي خط الطول عند إنهاء الزيارة';
COMMENT ON COLUMN public.visit_plan_items.metadata    IS 'بيانات إضافية (مسافة، حالة الاستبيان، ...)';

-- ── 2) أعمدة GPS و metadata لجدول call_plan_items (للتوسع المستقبلي) ──
ALTER TABLE public.call_plan_items
  ADD COLUMN IF NOT EXISTS metadata       JSONB DEFAULT '{}'::jsonb;

-- ── 3) فهارس على GPS لتسهيل التقارير الجغرافية ──
CREATE INDEX IF NOT EXISTS idx_visit_plan_items_gps
  ON public.visit_plan_items(gps_lat, gps_lng)
  WHERE gps_lat IS NOT NULL;

-- ── 4) تحديث سياسات RLS — لا حاجة لتغيير لأن السياسات الحالية تغطي كل الأعمدة ──
-- RLS policies on visit_plan_items already cover all columns via SELECT/INSERT/UPDATE/DELETE
