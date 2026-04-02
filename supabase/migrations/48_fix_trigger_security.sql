-- ═══════════════════════════════════════════════════════
-- 48_fix_trigger_security.sql
-- Fix: deactivate_failed_push_subscription lacked
-- SECURITY DEFINER and SET search_path, making it
-- vulnerable to search_path hijacking.
-- Also fixes last_failed_at overwrite on idempotent calls.
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.deactivate_failed_push_subscription()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.failed_count >= 5 THEN
    NEW.is_active      := false;
    -- Preserve original failure time — only set if not already set
    NEW.last_failed_at := COALESCE(NEW.last_failed_at, now());
  END IF;
  RETURN NEW;
END;
$$;
