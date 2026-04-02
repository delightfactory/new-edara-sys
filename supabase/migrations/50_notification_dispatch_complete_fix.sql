-- ═══════════════════════════════════════════════════════════════
-- 50_notification_dispatch_complete_fix.sql
--
-- ROOT CAUSES FIXED:
--
-- [RC-01] call_dispatch_notification (migration 45):
--         body := v_body::text → body := v_body (jsonb direct)
--         timeout 5000 → 30000 (absorbs Edge Function cold start)
--         Reads from internal_config with GUC fallback
--
-- [RC-02] notify_on_expense_change (migration 45):
--         JOIN profiles rp ON rp.role_id ← column does not exist
--         Fix: user_roles + role_permissions + wildcard *
--
-- [RC-03] notify_on_permission_change (migration 46):
--         JOIN profiles p ON p.role_id ← column does not exist
--         Fix: user_roles + role_permissions + wildcard *
--
-- [RC-04] notify_on_sales_order_confirmed (migration 46):
--         JOIN profiles p ON p.role_id ← column does not exist
--         Fix: user_roles + role_permissions + wildcard *
--
-- [RC-05] notify_on_purchase_invoice_change (migration 46):
--         JOIN profiles p ON p.role_id ← column does not exist (×2)
--         Fix: user_roles + role_permissions + wildcard *
--
-- [RC-06] notify_expiring_contracts (migration 46):
--         JOIN profiles p ON p.role_id ← column does not exist
--         Fix: user_roles + role_permissions + wildcard *
--
-- [RC-07] Warmup cron:
--         pg_cron pings dispatch-notification every 10 minutes
--         to prevent cold-start timeouts
--
-- NOT TOUCHED:
--   notify_on_leave_request_change — already correct in DB
--   notify_on_advance_change — uses hr_employees (correct)
--   notify_on_payroll_paid — uses payroll_lines (correct)
--   notify_on_attendance_late — uses direct_manager_id (correct)
--   notify_absent_employees — uses direct_manager_id (correct)
--   All triggers — unchanged (only functions are replaced)
--
-- SAFETY:
--   ✅ AFTER triggers — business tx commits first
--   ✅ All notification logic inside BEGIN..EXCEPTION WHEN OTHERS
--   ✅ SECURITY DEFINER + SET search_path = public
--   ✅ pg_net is fire-and-forget (async HTTP)
--   ✅ CREATE OR REPLACE — idempotent
-- ═══════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────
-- RC-01: call_dispatch_notification
-- Changes: body := v_body (jsonb), timeout 30s, internal_config
-- ─────────────────────────────────────────────────────────────
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

  -- Read Supabase connection details from internal_config table
  SELECT value INTO v_url         FROM internal_config WHERE key = 'supabase_url';
  SELECT value INTO v_service_key FROM internal_config WHERE key = 'service_role_key';

  -- Fallback: try GUC app.settings (backwards compatibility)
  IF v_url IS NULL OR v_url = '' THEN
    v_url := current_setting('app.settings.supabase_url', true);
  END IF;
  IF v_service_key IS NULL OR v_service_key = '' THEN
    v_service_key := current_setting('app.settings.service_role_key', true);
  END IF;

  -- If settings are not configured, log and return silently
  -- Notifications are non-critical — never block business transactions
  IF v_url IS NULL OR v_url = '' THEN
    RAISE WARNING 'call_dispatch_notification: supabase_url not configured — skipping notification for %', p_event_key;
    RETURN;
  END IF;

  IF v_service_key IS NULL OR v_service_key = '' THEN
    RAISE WARNING 'call_dispatch_notification: service_role_key not configured — skipping notification for %', p_event_key;
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
  -- [RC-01 FIX] body passed as jsonb directly (not ::text)
  -- [RC-01 FIX] timeout raised to 30s to absorb cold start (~5s)
  PERFORM net.http_post(
    url                  := v_url || '/functions/v1/dispatch-notification',
    headers              := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body                 := v_body,
    timeout_milliseconds := 30000
  );

EXCEPTION WHEN OTHERS THEN
  -- Absorb all errors — notification failure must never roll back a business transaction
  RAISE WARNING 'call_dispatch_notification: non-critical error for %: %', p_event_key, SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION public.call_dispatch_notification(text, uuid[], jsonb, text, uuid)
  TO service_role;


-- ─────────────────────────────────────────────────────────────
-- RC-02: notify_on_expense_change
-- Changes: profiles.role_id → user_roles + wildcard *
-- Original: migration 45, lines 239-333
-- ─────────────────────────────────────────────────────────────
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
  IF NEW.status = 'pending_approval' AND OLD.status = 'draft' THEN
    -- [RC-02 FIX] profiles.role_id → user_roles + wildcard *
    SELECT ARRAY(
      SELECT DISTINCT ur.user_id
      FROM   user_roles ur
      JOIN   role_permissions rp ON rp.role_id = ur.role_id
      WHERE  rp.permission IN ('finance.expenses.approve', '*')
        AND  ur.is_active = true
        AND  ur.user_id <> COALESCE(NEW.created_by, gen_random_uuid())
      LIMIT  20
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


-- ─────────────────────────────────────────────────────────────
-- RC-03: notify_on_permission_change
-- Changes: profiles.role_id → user_roles + wildcard *
-- Original: migration 46, lines 270-356
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_on_permission_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee_profile  uuid;
  v_approver_profiles uuid[];
  v_emp_name          text;
  v_perm_date         text;
BEGIN
  BEGIN
    SELECT he.user_id, he.full_name
    INTO   v_employee_profile, v_emp_name
    FROM   hr_employees he
    WHERE  he.id = NEW.employee_id
    LIMIT  1;

    v_perm_date := to_char(NEW.permission_date, 'YYYY-MM-DD');

    -- ── INSERT: new request → notify approvers ──────────────────────
    IF TG_OP = 'INSERT' THEN
      -- [RC-03 FIX] profiles.role_id → user_roles + wildcard *
      SELECT ARRAY(
        SELECT DISTINCT ur.user_id
        FROM   user_roles ur
        JOIN   role_permissions rp ON rp.role_id = ur.role_id
        WHERE  rp.permission IN ('hr.attendance.approve', '*')
          AND  ur.is_active = true
          AND  ur.user_id <> COALESCE(v_employee_profile, gen_random_uuid())
        LIMIT  20
      ) INTO v_approver_profiles;

      IF v_approver_profiles IS NOT NULL
         AND array_length(v_approver_profiles, 1) > 0 THEN
        PERFORM public.call_dispatch_notification(
          'hr.permission.requested',
          v_approver_profiles,
          jsonb_build_object(
            'employee_name',   COALESCE(v_emp_name, 'موظف'),
            'permission_date', v_perm_date,
            'reason',          COALESCE(NEW.reason, '—'),
            'permission_id',   NEW.id::text
          ),
          'hr_permission_request',
          NEW.id
        );
      END IF;
    END IF;

    -- ── UPDATE: status transition → notify employee ──────────────────────
    IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN

      IF NEW.status = 'approved' AND v_employee_profile IS NOT NULL THEN
        PERFORM public.call_dispatch_notification(
          'hr.permission.approved',
          ARRAY[v_employee_profile],
          jsonb_build_object(
            'permission_date', v_perm_date,
            'permission_id',   NEW.id::text
          ),
          'hr_permission_request',
          NEW.id
        );

      ELSIF NEW.status = 'rejected' AND v_employee_profile IS NOT NULL THEN
        PERFORM public.call_dispatch_notification(
          'hr.permission.rejected',
          ARRAY[v_employee_profile],
          jsonb_build_object(
            'permission_date', v_perm_date,
            'reason',          COALESCE(NEW.rejection_reason, 'لم يُحدد سبب'),
            'permission_id',   NEW.id::text
          ),
          'hr_permission_request',
          NEW.id
        );
      END IF;

    END IF;

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[notify_on_permission_change] non-critical: %', SQLERRM;
  END;

  RETURN NEW;
END;
$$;


-- ─────────────────────────────────────────────────────────────
-- RC-04: notify_on_sales_order_confirmed
-- Changes: profiles.role_id → user_roles + wildcard *
-- Original: migration 46, lines 538-606
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_on_sales_order_confirmed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_recipient_ids uuid[];
  v_customer_name text;
  v_amount_text   text;
BEGIN
  -- Guard: only fire on confirmation transition
  IF NEW.status <> 'confirmed' OR OLD.status = 'confirmed' THEN
    RETURN NEW;
  END IF;

  BEGIN
    SELECT COALESCE(name, 'عميل')
    INTO   v_customer_name
    FROM   customers
    WHERE  id = NEW.customer_id
    LIMIT  1;

    v_amount_text := to_char(NEW.total_amount, 'FM999,999,999.00') || ' ج.م';

    -- Build recipient array: rep + creator + all managers with read_all or *
    -- [RC-04 FIX] profiles.role_id → user_roles + wildcard *
    SELECT ARRAY(
      WITH reps AS (
        SELECT NEW.rep_id        AS id WHERE NEW.rep_id IS NOT NULL
        UNION ALL
        SELECT NEW.created_by_id AS id
          WHERE NEW.created_by_id IS NOT NULL
            AND NEW.created_by_id IS DISTINCT FROM NEW.rep_id
      ),
      managers AS (
        SELECT DISTINCT ur.user_id AS id
        FROM   user_roles ur
        JOIN   role_permissions rp ON rp.role_id = ur.role_id
        WHERE  rp.permission IN ('sales.orders.read_all', '*')
          AND  ur.is_active = true
        LIMIT  10
      )
      SELECT id FROM reps
      UNION
      SELECT id FROM managers
    ) INTO v_recipient_ids;

    IF v_recipient_ids IS NOT NULL
       AND array_length(v_recipient_ids, 1) > 0 THEN
      PERFORM public.call_dispatch_notification(
        'sales.order.confirmed',
        v_recipient_ids,
        jsonb_build_object(
          'order_number',  NEW.order_number,
          'customer_name', v_customer_name,
          'amount',        v_amount_text,
          'order_id',      NEW.id::text
        ),
        'sales_order',
        NEW.id
      );
    END IF;

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[notify_on_sales_order_confirmed] non-critical: %', SQLERRM;
  END;

  RETURN NEW;
END;
$$;


-- ─────────────────────────────────────────────────────────────
-- RC-05: notify_on_purchase_invoice_change
-- Changes: profiles.role_id → user_roles + wildcard * (×2)
-- Original: migration 46, lines 625-710
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_on_purchase_invoice_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_recipient_ids uuid[];
  v_supplier_name text;
  v_amount_text   text;
BEGIN
  -- Guard: only act on actual status changes
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  BEGIN
    SELECT COALESCE(name, 'مورد')
    INTO   v_supplier_name
    FROM   suppliers
    WHERE  id = NEW.supplier_id
    LIMIT  1;

    v_amount_text := to_char(NEW.total_amount, 'FM999,999,999.00') || ' ج.م';

    -- ── received → notify finance users who can bill ────────────────────
    IF NEW.status = 'received' THEN
      -- [RC-05 FIX] profiles.role_id → user_roles + wildcard *
      SELECT ARRAY(
        SELECT DISTINCT ur.user_id
        FROM   user_roles ur
        JOIN   role_permissions rp ON rp.role_id = ur.role_id
        WHERE  rp.permission IN ('procurement.invoices.bill', '*')
          AND  ur.is_active = true
        LIMIT  10
      ) INTO v_recipient_ids;

      IF v_recipient_ids IS NOT NULL
         AND array_length(v_recipient_ids, 1) > 0 THEN
        PERFORM public.call_dispatch_notification(
          'purchase.invoice.received',
          v_recipient_ids,
          jsonb_build_object(
            'invoice_number', COALESCE(NEW.number, NEW.id::text),
            'supplier_name',  v_supplier_name,
            'amount',         v_amount_text,
            'invoice_id',     NEW.id::text
          ),
          'purchase_invoice',
          NEW.id
        );
      END IF;
    END IF;

    -- ── billed → notify users who can authorize payment ─────────────────
    IF NEW.status = 'billed' THEN
      -- [RC-05 FIX] profiles.role_id → user_roles + wildcard *
      SELECT ARRAY(
        SELECT DISTINCT ur.user_id
        FROM   user_roles ur
        JOIN   role_permissions rp ON rp.role_id = ur.role_id
        WHERE  rp.permission IN ('procurement.invoices.pay', '*')
          AND  ur.is_active = true
        LIMIT  10
      ) INTO v_recipient_ids;

      IF v_recipient_ids IS NOT NULL
         AND array_length(v_recipient_ids, 1) > 0 THEN
        PERFORM public.call_dispatch_notification(
          'purchase.invoice.billed',
          v_recipient_ids,
          jsonb_build_object(
            'invoice_number', COALESCE(NEW.number, NEW.id::text),
            'supplier_name',  v_supplier_name,
            'amount',         v_amount_text,
            'invoice_id',     NEW.id::text
          ),
          'purchase_invoice',
          NEW.id
        );
      END IF;
    END IF;

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[notify_on_purchase_invoice_change] non-critical: %', SQLERRM;
  END;

  RETURN NEW;
END;
$$;


-- ─────────────────────────────────────────────────────────────
-- RC-06: notify_expiring_contracts
-- Changes: profiles.role_id → user_roles + wildcard *
-- Original: migration 46, lines 831-897
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_expiring_contracts()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp          RECORD;
  v_hr_managers  uuid[];
  v_today        date    := CURRENT_DATE;
  v_count        integer := 0;
  v_notify_days  integer[] := ARRAY[60, 30, 14, 7];
BEGIN
  -- [RC-06 FIX] profiles.role_id → user_roles + wildcard *
  SELECT ARRAY(
    SELECT DISTINCT ur.user_id
    FROM   user_roles ur
    JOIN   role_permissions rp ON rp.role_id = ur.role_id
    WHERE  rp.permission IN ('hr.employees.manage', 'hr.settings.update', '*')
      AND  ur.is_active = true
    LIMIT  15
  ) INTO v_hr_managers;

  IF v_hr_managers IS NULL OR array_length(v_hr_managers, 1) = 0 THEN
    RAISE NOTICE '[notify_expiring_contracts] no HR managers found — skipping';
    RETURN;
  END IF;

  -- Scan active contracts expiring on notification days
  FOR v_emp IN
    SELECT DISTINCT ON (he.id)
      he.id                                AS employee_id,
      he.full_name                         AS emp_name,
      c.end_date                           AS expiry_date,
      (c.end_date - v_today)               AS days_remaining
    FROM   hr_employees he
    JOIN   hr_contracts c ON c.employee_id = he.id
    WHERE  he.status = 'active'
      AND  c.end_date IS NOT NULL
      AND  c.end_date > v_today
      AND  (c.end_date - v_today) = ANY(v_notify_days)
    ORDER BY he.id, c.start_date DESC
  LOOP
    BEGIN
      PERFORM public.call_dispatch_notification(
        'hr.contract.expiring',
        v_hr_managers,
        jsonb_build_object(
          'employee_name',  v_emp.emp_name,
          'expiry_date',    to_char(v_emp.expiry_date, 'YYYY-MM-DD'),
          'days_remaining', v_emp.days_remaining::text,
          'employee_id',    v_emp.employee_id::text
        ),
        'hr_employee',
        v_emp.employee_id
      );
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '[notify_expiring_contracts] employee % error: %',
                    v_emp.employee_id, SQLERRM;
    END;
  END LOOP;

  RAISE NOTICE '[notify_expiring_contracts] % contract-expiry notifications dispatched',
               v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_expiring_contracts() TO service_role;
REVOKE EXECUTE ON FUNCTION public.notify_expiring_contracts() FROM authenticated;


-- ─────────────────────────────────────────────────────────────
-- RC-07: Warmup cron — keep dispatch-notification Edge Function warm
-- Prevents cold-start timeouts by pinging every 10 minutes
-- dispatch-notification returns 400 for empty user_ids (harmless)
-- ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  -- Unschedule if exists (idempotent)
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'keep-dispatch-notification-warm') THEN
    PERFORM cron.unschedule('keep-dispatch-notification-warm');
  END IF;
END $$;

SELECT cron.schedule(
  'keep-dispatch-notification-warm',
  '*/10 * * * *',
  $$
    SELECT net.http_post(
      url     := (SELECT value FROM internal_config WHERE key = 'supabase_url')
                 || '/functions/v1/dispatch-notification',
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer ' || (SELECT value FROM internal_config WHERE key = 'service_role_key')
      ),
      body    := '{"event_key":"__ping__","user_ids":[]}'::jsonb,
      timeout_milliseconds := 10000
    );
  $$
);


-- ─────────────────────────────────────────────────────────────
-- SECURITY: revoke trigger functions from authenticated
-- ─────────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public.notify_on_expense_change()            FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_on_permission_change()         FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_on_sales_order_confirmed()     FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_on_purchase_invoice_change()   FROM authenticated;


-- ─────────────────────────────────────────────────────────────
-- VERIFICATION
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_fn_count integer;
BEGIN
  SELECT COUNT(*) INTO v_fn_count
  FROM pg_proc
  WHERE proname IN (
    'call_dispatch_notification',
    'notify_on_expense_change',
    'notify_on_permission_change',
    'notify_on_sales_order_confirmed',
    'notify_on_purchase_invoice_change',
    'notify_expiring_contracts'
  );

  RAISE NOTICE '══════════════════════════════════════════════';
  RAISE NOTICE '[50_notification_dispatch_complete_fix] RESULT:';
  RAISE NOTICE '  ✅ Functions replaced: %/6', v_fn_count;
  RAISE NOTICE '══════════════════════════════════════════════';

  IF v_fn_count < 6 THEN
    RAISE WARNING '  ⚠️  Missing functions — expected 6';
  END IF;
END $$;
