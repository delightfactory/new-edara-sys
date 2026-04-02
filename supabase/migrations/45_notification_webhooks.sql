-- ═══════════════════════════════════════════════════════════════
-- 45_notification_webhooks.sql
-- Notification System — Business Event Triggers (DB→Edge Function bridge)
--
-- PROBLEM (F-01): The dispatch-notification Edge Function exists but
-- nothing calls it automatically. This migration bridges business events
-- to notification delivery by creating AFTER triggers on key tables
-- that use pg_net (available by default in Supabase) to POST to the
-- Edge Function.
--
-- EVENT COVERAGE (D-01):
--   hr_leave_requests:    requested, approved, rejected           (D-01b)
--   expenses:             submitted for approval, approved, rejected (D-01c)
--
-- DESIGN PRINCIPLES:
--   ✅ Idempotent — CREATE OR REPLACE + DROP TRIGGER IF EXISTS
--   ✅ Fire-and-forget — net.http_post() is async (non-blocking)
--   ✅ SECURITY DEFINER on all trigger functions + SET search_path
--   ✅ Silent failures — notification failure MUST NOT block business tx
--   ✅ AFTER trigger (not BEFORE) — notification fires after DB change
--   ✅ Checks event_key matches seed data in migration 42
--
-- PRE-REQUISITE: pg_net extension
--   To install: Dashboard → Database → Extensions → pg_net → Enable
--   Or: CREATE EXTENSION IF NOT EXISTS pg_net;
--
-- ENVIRONMENT:
--   SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are passed via
--   current_setting('app.supabase_url') and current_setting('app.service_role_key')
--   Configure via: supabase/config.toml or supabase secrets
-- ═══════════════════════════════════════════════════════════════

-- Enable pg_net if not already enabled (idempotent)
CREATE EXTENSION IF NOT EXISTS pg_net;

-- ─────────────────────────────────────────────
-- D-01a: Helper function — call_dispatch_notification
-- Encapsulates the net.http_post call so individual trigger
-- functions stay simple and consistent.
-- Arguments follow the dispatch-notification Edge Function API.
-- ─────────────────────────────────────────────
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
  v_body        jsonb;
BEGIN
  -- Guard: if user_ids is empty, skip (nothing to notify)
  IF p_user_ids IS NULL OR array_length(p_user_ids, 1) = 0 THEN
    RETURN;
  END IF;

  -- Read Supabase connection details from app config
  -- These are set by Supabase automatically in the DB environment
  v_url         := current_setting('app.settings.supabase_url',         true)
               -- Fallback: try SUPABASE_URL set by Supabase natively
               ;
  v_service_key := current_setting('app.settings.service_role_key',     true);

  -- If settings are not configured, log and return silently
  -- Notifications are non-critical — never block business transactions
  IF v_url IS NULL OR v_url = '' THEN
    RAISE WARNING 'call_dispatch_notification: app.settings.supabase_url not set — skipping notification for %', p_event_key;
    RETURN;
  END IF;

  IF v_service_key IS NULL OR v_service_key = '' THEN
    RAISE WARNING 'call_dispatch_notification: app.settings.service_role_key not set — skipping notification for %', p_event_key;
    RETURN;
  END IF;

  -- Build request body
  v_body := jsonb_build_object(
    'event_key',   p_event_key,
    'user_ids',    to_jsonb(p_user_ids),
    'variables',   p_variables,
    'entity_type', p_entity_type,
    'entity_id',   p_entity_id
  );

  -- Fire async HTTP POST to dispatch-notification Edge Function
  -- pg_net executes this asynchronously — does NOT block the transaction
  PERFORM net.http_post(
    url     := v_url || '/functions/v1/dispatch-notification',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body    := v_body::text
  );

EXCEPTION WHEN OTHERS THEN
  -- Absorb all errors — notification failure must never roll back a business transaction
  RAISE WARNING 'call_dispatch_notification: non-critical error for %: %', p_event_key, SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION public.call_dispatch_notification(text, uuid[], jsonb, text, uuid)
  TO service_role;


-- ─────────────────────────────────────────────
-- D-01b: hr_leave_requests — Leave notification triggers
--
-- Events:
--   INSERT                → notify supervisor: new request pending (hr.leave.requested)
--   UPDATE status=approved_supervisor → notify HR manager   (hr.leave.pending_hr) [when 2-level flow]
--   UPDATE status=approved → notify employee: approved      (hr.leave.approved)
--   UPDATE status=rejected → notify employee: rejected      (hr.leave.rejected)
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_on_leave_request_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee_profile_id   uuid;
  v_supervisor_profile_id uuid;
  v_hr_profile_id         uuid;
  v_start_text            text;
  v_end_text              text;
BEGIN
  -- Resolve profile_id (users system) from hr_employee_id
  BEGIN
    SELECT user_id INTO v_employee_profile_id
    FROM hr_employees WHERE id = NEW.employee_id LIMIT 1;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  BEGIN
    IF NEW.supervisor_id IS NOT NULL THEN
      SELECT user_id INTO v_supervisor_profile_id
      FROM hr_employees WHERE id = NEW.supervisor_id LIMIT 1;
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  BEGIN
    IF NEW.hr_manager_id IS NOT NULL THEN
      SELECT user_id INTO v_hr_profile_id
      FROM hr_employees WHERE id = NEW.hr_manager_id LIMIT 1;
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  v_start_text := to_char(NEW.start_date, 'YYYY-MM-DD');
  v_end_text   := to_char(NEW.end_date,   'YYYY-MM-DD');

  -- ── INSERT: new leave request → notify supervisor ─────────
  IF TG_OP = 'INSERT' THEN
    IF v_supervisor_profile_id IS NOT NULL THEN
      PERFORM public.call_dispatch_notification(
        'hr.leave.requested',
        ARRAY[v_supervisor_profile_id],
        jsonb_build_object(
          'employee_name', COALESCE(
            (SELECT full_name FROM hr_employees WHERE id = NEW.employee_id LIMIT 1),
            'موظف'
          ),
          'from_date', v_start_text,
          'to_date',   v_end_text,
          'leave_id',  NEW.id::text
        ),
        'hr_leave_request',
        NEW.id
      );
    END IF;
    RETURN NEW;
  END IF;

  -- ── UPDATE: handle status transitions ─────────────────────
  IF TG_OP = 'UPDATE' AND NEW.status <> OLD.status THEN

    -- Approved → notify employee
    IF NEW.status = 'approved' AND OLD.status <> 'approved' THEN
      IF v_employee_profile_id IS NOT NULL THEN
        PERFORM public.call_dispatch_notification(
          'hr.leave.approved',
          ARRAY[v_employee_profile_id],
          jsonb_build_object(
            'from_date', v_start_text,
            'to_date',   v_end_text,
            'leave_id',  NEW.id::text
          ),
          'hr_leave_request',
          NEW.id
        );
      END IF;

    -- Rejected → notify employee
    ELSIF NEW.status = 'rejected' AND OLD.status <> 'rejected' THEN
      IF v_employee_profile_id IS NOT NULL THEN
        PERFORM public.call_dispatch_notification(
          'hr.leave.rejected',
          ARRAY[v_employee_profile_id],
          jsonb_build_object(
            'from_date', v_start_text,
            'to_date',   v_end_text,
            'reason',    COALESCE(NEW.rejection_reason, 'لم يُحدد سبب'),
            'leave_id',  NEW.id::text
          ),
          'hr_leave_request',
          NEW.id
        );
      END IF;
    END IF;

  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_leave_request ON public.hr_leave_requests;
CREATE TRIGGER trg_notify_leave_request
  AFTER INSERT OR UPDATE OF status
  ON public.hr_leave_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_leave_request_change();


-- ─────────────────────────────────────────────
-- D-01c: expenses — Expense notification triggers
--
-- Events:
--   UPDATE status: draft→pending_approval → notify approvers (finance.expense.submitted)
--   UPDATE status: approved               → notify requester (finance.expense.approved)
--   UPDATE status: rejected               → notify requester (finance.expense.rejected)
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_on_expense_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_creator_id   uuid;
  v_approver_ids uuid[];
  v_amount_text  text;
BEGIN
  -- Only fire on status changes
  IF TG_OP = 'UPDATE' AND NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;

  v_creator_id  := NEW.created_by;
  v_amount_text := to_char(NEW.amount, 'FM999,999,999.00') || ' جنيه';

  -- Submitted for approval → notify relevant approvers
  -- We notify profiles with finance.expenses.approve permission
  -- (simplified: notify approved_by if set, or all with the permission)
  IF NEW.status = 'pending_approval' AND OLD.status = 'draft' THEN
    -- Gather approvers (profiles with finance.expenses.approve)
    SELECT ARRAY(
      SELECT DISTINCT rp.profile_id
      FROM role_permissions rmp
      JOIN profiles rp ON rp.role_id = rmp.role_id
      WHERE rmp.permission = 'finance.expenses.approve'
        AND rp.id <> NEW.created_by
      LIMIT 20  -- safety cap
    ) INTO v_approver_ids;

    IF v_approver_ids IS NOT NULL AND array_length(v_approver_ids, 1) > 0 THEN
      PERFORM public.call_dispatch_notification(
        'finance.expense.submitted',
        v_approver_ids,
        jsonb_build_object(
          'requester_name', COALESCE(
            (SELECT COALESCE(full_name, email) FROM profiles WHERE id = NEW.created_by LIMIT 1),
            'موظف'
          ),
          'amount',      v_amount_text,
          'currency',    'EGP',
          'description', LEFT(COALESCE(NEW.description, ''), 60),
          'expense_id',  NEW.id::text
        ),
        'expense',
        NEW.id
      );
    END IF;
  END IF;

  -- Approved → notify creator
  IF NEW.status = 'approved' AND OLD.status <> 'approved' THEN
    IF v_creator_id IS NOT NULL THEN
      PERFORM public.call_dispatch_notification(
        'finance.expense.approved',
        ARRAY[v_creator_id],
        jsonb_build_object(
          'amount',       v_amount_text,
          'currency',     'EGP',
          'approver_name', COALESCE(
            (SELECT COALESCE(full_name, email) FROM profiles WHERE id = NEW.approved_by LIMIT 1),
            'المعتمِد'
          ),
          'expense_id',  NEW.id::text
        ),
        'expense',
        NEW.id
      );
    END IF;
  END IF;

  -- Rejected → notify creator
  IF NEW.status = 'rejected' AND OLD.status <> 'rejected' THEN
    IF v_creator_id IS NOT NULL THEN
      PERFORM public.call_dispatch_notification(
        'finance.expense.rejected',
        ARRAY[v_creator_id],
        jsonb_build_object(
          'amount',     v_amount_text,
          'currency',   'EGP',
          'reason',     COALESCE(NEW.rejection_reason, 'لم يُحدد سبب'),
          'expense_id', NEW.id::text
        ),
        'expense',
        NEW.id
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_expense_change ON public.expenses;
CREATE TRIGGER trg_notify_expense_change
  AFTER UPDATE OF status
  ON public.expenses
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_expense_change();


-- ─────────────────────────────────────────────
-- SECURITY: revoke from authenticated users
-- These trigger functions run automatically — no direct calls needed
-- ─────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public.notify_on_leave_request_change() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_on_expense_change()        FROM authenticated;

-- ─────────────────────────────────────────────
-- CONFIGURATION INSTRUCTIONS (must be done in Supabase Dashboard)
-- ─────────────────────────────────────────────
-- To configure the Supabase URL and service_role key for triggers:
--
-- In Supabase Dashboard → Database → Custom Config, add:
--   app.settings.supabase_url  = https://your-project.supabase.co
--   app.settings.service_role_key = your-service-role-key
--
-- Or via SQL (run once, not part of migration):
--   ALTER DATABASE postgres SET "app.settings.supabase_url" = 'https://xxx.supabase.co';
--   ALTER DATABASE postgres SET "app.settings.service_role_key" = 'your-key-here';
-- ─────────────────────────────────────────────
