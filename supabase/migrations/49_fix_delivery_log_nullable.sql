-- ═══════════════════════════════════════════════════════
-- 47_fix_delivery_log_nullable.sql
-- Fix: notification_delivery_log.notification_id must be
-- nullable to support push-only delivery (no in-app record)
-- and failed delivery logging when insert was skipped.
-- ═══════════════════════════════════════════════════════
ALTER TABLE public.notification_delivery_log
  ALTER COLUMN notification_id DROP NOT NULL;

COMMENT ON COLUMN public.notification_delivery_log.notification_id IS
  'NULL when the notification was push-only (in_app_enabled=false) or when the in-app insert failed.';
