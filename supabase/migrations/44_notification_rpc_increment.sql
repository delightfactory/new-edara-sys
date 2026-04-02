-- ═══════════════════════════════════════════════════════════════
-- 44_notification_rpc_increment.sql
-- Notification System — Missing RPC Functions
--
-- Problem: send-push-notification Edge Function calls
--   increment_push_failed_count() which was never defined.
--   Without this, failed push tracking relies on a fragile
--   read-then-write pattern that is NOT atomic and misses
--   last_failed_at, meaning auto-deactivation trigger cannot
--   fire properly even though it exists.
--
-- Fix: Add the missing RPC + a helper RPC for resetting
--   failed_count on a successful push delivery.
--
-- Design constraints:
--   ✅ idempotent — CREATE OR REPLACE
--   ✅ SECURITY DEFINER + search_path = public
--   ✅ GRANT EXECUTE to service_role ONLY (Edge Functions use it)
--   ✅ NOT granted to authenticated (users should never call these)
-- ═══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- 1. increment_push_failed_count
--    Atomically increments failed_count + sets last_failed_at.
--    The BEFORE UPDATE trigger auto_deactivate_push_subscription
--    fires after this update, deactivating the subscription if
--    failed_count >= 5.
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.increment_push_failed_count(
  p_subscription_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.push_subscriptions
  SET  failed_count   = failed_count + 1,
       last_failed_at = now(),
       updated_at     = now()
  WHERE id = p_subscription_id;
  -- NOTE: the BEFORE UPDATE trigger deactivate_failed_push_subscription
  -- fires here and sets is_active=false when failed_count reaches 5.
END;
$$;

-- ─────────────────────────────────────────────
-- 2. reset_push_failed_count
--    Called on a successful push delivery to reset the failure
--    counter and update last_push_at.
--    Keeps subscriptions alive when a device recovers after
--    a transient failure.
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.reset_push_failed_count(
  p_subscription_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.push_subscriptions
  SET  failed_count = 0,
       last_push_at = now(),
       last_seen_at = now(),
       updated_at   = now()
  WHERE id = p_subscription_id;
END;
$$;

-- ─────────────────────────────────────────────
-- 3. Grant execute to service_role ONLY
--    Edge Functions authenticate as service_role.
--    Authenticated (browser) users must never call these.
-- ─────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.increment_push_failed_count(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.reset_push_failed_count(uuid)      TO service_role;

-- Explicitly revoke from authenticated as a safety net
REVOKE EXECUTE ON FUNCTION public.increment_push_failed_count(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.reset_push_failed_count(uuid)      FROM authenticated;
