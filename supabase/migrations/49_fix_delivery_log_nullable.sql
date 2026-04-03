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




-- 1. جدول إعدادات داخلي (آمن — بدون RLS لأنه يُقرأ فقط من SECURITY DEFINER functions)
CREATE TABLE IF NOT EXISTS internal_config (
  key   text PRIMARY KEY,
  value text NOT NULL
);

-- منع المستخدمين العاديين من القراءة
REVOKE ALL ON internal_config FROM authenticated;
REVOKE ALL ON internal_config FROM anon;
GRANT SELECT ON internal_config TO service_role;

-- 2. أدخل المفاتيح فقط كـ placeholders فارغة إذا لم تكن موجودة مسبقاً.
-- لا تكتب أي URL أو service key خاصين ببيئة محددة داخل الـ repo،
-- ولا تطغِ على قيمة صحيحة تم ضبطها يدوياً في قاعدة البيانات.
INSERT INTO internal_config (key, value) VALUES
  ('supabase_url', '')
ON CONFLICT (key) DO NOTHING;




INSERT INTO internal_config (key, value) VALUES
  ('service_role_key', '')
ON CONFLICT (key) DO NOTHING;

INSERT INTO internal_config (key, value) VALUES
  ('internal_dispatch_secret', '')
ON CONFLICT (key) DO NOTHING;






CREATE OR REPLACE FUNCTION public.call_dispatch_notification(
  p_event_key   text,
  p_user_ids    uuid[],
  p_variables   jsonb  DEFAULT '{}'::jsonb,
  p_entity_type text   DEFAULT NULL,
  p_entity_id   uuid   DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_url         text;
  v_service_key text;
  v_internal_secret text;
  v_headers     jsonb;
  v_body        jsonb;
BEGIN
  IF p_user_ids IS NULL OR array_length(p_user_ids, 1) = 0 THEN
    RETURN;
  END IF;

  -- Read from internal_config table (fallback to GUC for backwards compat)
  SELECT value INTO v_url
  FROM internal_config WHERE key = 'supabase_url';
  IF v_url IS NULL OR v_url = '' THEN
    v_url := current_setting('app.settings.supabase_url', true);
  END IF;

  SELECT value INTO v_service_key
  FROM internal_config WHERE key = 'service_role_key';
  IF v_service_key IS NULL OR v_service_key = '' THEN
    v_service_key := current_setting('app.settings.service_role_key', true);
  END IF;

  SELECT value INTO v_internal_secret
  FROM internal_config WHERE key = 'internal_dispatch_secret';
  IF v_internal_secret IS NULL OR v_internal_secret = '' THEN
    v_internal_secret := current_setting('app.settings.internal_dispatch_secret', true);
  END IF;

  IF v_url IS NULL OR v_url = '' THEN
    RAISE WARNING 'call_dispatch_notification: supabase_url not configured — skipping %', p_event_key;
    RETURN;
  END IF;

  IF (v_internal_secret IS NULL OR v_internal_secret = '')
     AND (v_service_key IS NULL OR v_service_key = '') THEN
    RAISE WARNING 'call_dispatch_notification: service_role_key not configured — skipping %', p_event_key;
    RETURN;
  END IF;

  v_body := jsonb_build_object(
    'event_key',   p_event_key,
    'user_ids',    to_jsonb(p_user_ids),
    'variables',   p_variables,
    'entity_type', p_entity_type,
    'entity_id',   p_entity_id
  );

  v_headers := jsonb_build_object('Content-Type', 'application/json');
  IF v_internal_secret IS NOT NULL AND v_internal_secret <> '' THEN
    v_headers := v_headers || jsonb_build_object('x-internal-secret', v_internal_secret);
  ELSIF v_service_key IS NOT NULL AND v_service_key <> '' THEN
    v_headers := v_headers || jsonb_build_object('Authorization', 'Bearer ' || v_service_key);
  END IF;

  PERFORM net.http_post(
    url     := v_url || '/functions/v1/dispatch-notification',
    headers := v_headers,
    body    := v_body::text
  );

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'call_dispatch_notification: non-critical error for %: %', p_event_key, SQLERRM;
END;
$$;
