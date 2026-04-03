-- ═══════════════════════════════════════════════════════════════════════════
-- 54_notification_wave1c_extend_existing.sql
-- Wave 1C — Replace/Extend Existing Notification Triggers
--
-- SCOPE:
--   1. sales_orders:
--        REPLACE trg_notify_sales_order_confirmed (confirmed-only)
--        WITH    trg_notify_sales_order_lifecycle (INSERT + all status transitions)
--        → new function: notify_on_sales_order_lifecycle()
--        → dropped: trg_notify_sales_order_confirmed (old trigger name)
--
--   2. purchase_invoices:
--        EXTEND notify_on_purchase_invoice_change() (CREATE OR REPLACE)
--        → adds `→ paid` transition to existing received/billed logic
--        → trigger name trg_notify_purchase_invoice UNCHANGED
--
--   3. hr_payroll_runs:
--        EXTEND notify_on_payroll_paid() (CREATE OR REPLACE)
--        → adds `→ review` transition to existing paid logic
--        → trigger name RENAMED to trg_notify_payroll_lifecycle for clarity
--        → old trigger trg_notify_payroll_paid DROPPED to avoid duplicate fires
--
--   4. hr_attendance_days:
--        NEW independent trigger: trg_notify_attendance_early_leave (AFTER UPDATE)
--        → different event from trg_notify_attendance_late (AFTER INSERT)
--        → NO conflict guaranteed
--
-- NON-NOTIFICATION TRIGGERS PRESERVED (verified from migrations 22e, 04, 19):
--   trg_so_recalc_targets          sales_orders    AFTER UPDATE OF status  (22e_target_auto_recalc.sql L331)
--   trg_sales_orders_updated_at    sales_orders    BEFORE UPDATE           (04_sales_system.sql L200)
--   trg_payroll_run_number         hr_payroll_runs BEFORE INSERT           (19_hr_payroll_loans.sql L131)
--   trg_payroll_run_updated_at     hr_payroll_runs BEFORE UPDATE           (19_hr_payroll_loans.sql L136)
--   trg_notify_attendance_late     hr_attendance_days AFTER INSERT         (46_notification_full_coverage.sql L519)
--
-- DUPLICATE NOTIFICATION PREVENTION:
--   sales_orders INSERT → only sales.order.created fires (new branch)
--   sales_orders UPDATE confirmed → only new function fires (old trigger DROPPED)
--   sales_orders UPDATE delivered/completed → only new function fires (partially_delivered excluded)
--   sales_orders UPDATE cancelled → only new function fires
--   purchase_invoices: received/billed logic unchanged; `→paid` is a new ELSIF branch
--   hr_payroll_runs: review is an additional branch before the paid guard
--   hr_attendance_days: late fires on INSERT; early_leave fires on UPDATE → zero overlap
--
-- SAFETY:
--   ✅ All triggers: AFTER (business tx commits first)
--   ✅ All functions: BEGIN..EXCEPTION WHEN OTHERS (never block business)
--   ✅ SECURITY DEFINER + SET search_path = public
--   ✅ CREATE OR REPLACE — idempotent
--   ✅ DROP TRIGGER IF EXISTS — idempotent
--   ✅ call_dispatch_notification is pg_net async — fire-and-forget
--   ✅ No recalculate_targets_for_employee calls (respects 53b baseline)
--
-- SCHEMAS VERIFIED:
--   sales_orders: order_number TEXT, rep_id profiles(id), created_by_id profiles(id)
--     status ENUM: draft/confirmed/partially_delivered/delivered/completed/cancelled
--   hr_payroll_runs: status ENUM: draft/calculating/review/approved/paid/cancelled
--     period_id → hr_payroll_periods (year, month)
--     total_net NUMERIC, total_employees INTEGER
--   hr_attendance_days: early_leave_minutes INTEGER DEFAULT 0 (verified 46_L452)
--     employee_id → hr_employees.direct_manager_id → hr_employees.user_id
-- ═══════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════
-- 1. sales_orders — REPLACE with full lifecycle function
-- ═══════════════════════════════════════════════════════════════════════════
--
-- DROPPED: trg_notify_sales_order_confirmed (fired only on UPDATE→confirmed)
-- CREATED: trg_notify_sales_order_lifecycle (INSERT + UPDATE, all transitions)
--
-- LOGIC PRESERVATION for sales.order.confirmed (from migration 50 L377-411):
--   Recipients = rep_id UNION created_by_id UNION managers with sales.orders.read_all / *
--   This exact CTE logic is copied verbatim — no changes.
--
-- NEW TRANSITIONS:
--   INSERT        → sales.order.created  → managers with sales.orders.read_all / *
--   UPDATE →delivered/completed → sales.order.delivered → rep + created_by + finance.ledger.read
--   UPDATE →cancelled            → sales.order.cancelled  → rep + created_by

CREATE OR REPLACE FUNCTION public.notify_on_sales_order_lifecycle()
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
  BEGIN
    -- Resolve display fields (best-effort, inside exception)
    SELECT COALESCE(name, 'عميل')
    INTO v_customer_name
    FROM customers
    WHERE id = NEW.customer_id
    LIMIT 1;

    v_amount_text := to_char(NEW.total_amount, 'FM999,999,999.00') || ' ج.م';

    -- ─────────────────────────────────────────────────────────────
    -- INSERT → sales.order.created
    -- Notify: managers with sales.orders.read_all / * (awareness)
    -- ─────────────────────────────────────────────────────────────
    IF TG_OP = 'INSERT' THEN
      SELECT ARRAY(
        SELECT DISTINCT ur.user_id
        FROM user_roles ur
        JOIN role_permissions rp ON rp.role_id = ur.role_id
        WHERE rp.permission IN ('sales.orders.read_all', '*')
          AND ur.is_active = true
        LIMIT 15
      ) INTO v_recipient_ids;

      IF v_recipient_ids IS NOT NULL
         AND array_length(v_recipient_ids, 1) > 0 THEN
        PERFORM public.call_dispatch_notification(
          'sales.order.created',
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

    -- ─────────────────────────────────────────────────────────────
    -- UPDATE transitions
    -- ─────────────────────────────────────────────────────────────
    ELSIF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN

      -- ── confirmed (logic preserved VERBATIM from migration 50 L377-411) ──
      IF NEW.status = 'confirmed' AND OLD.status <> 'confirmed' THEN
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
            FROM user_roles ur
            JOIN role_permissions rp ON rp.role_id = ur.role_id
            WHERE rp.permission IN ('sales.orders.read_all', '*')
              AND ur.is_active = true
            LIMIT 10
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

      -- ── delivered or completed → sales.order.delivered ──────────────────
      -- Only fully terminal states: 'delivered' and 'completed'.
      -- 'partially_delivered' is explicitly excluded — the order is not yet
      -- fully delivered and sending a "delivery confirmed" notification would
      -- be misleading and premature.
      ELSIF NEW.status IN ('delivered', 'completed')
        AND OLD.status NOT IN ('delivered', 'completed') THEN

        -- Recipients: rep + created_by (direct actors) +
        --             finance.ledger.read holders (revenue awareness)
        SELECT ARRAY(
          WITH direct_actors AS (
            SELECT NEW.rep_id        AS id WHERE NEW.rep_id IS NOT NULL
            UNION ALL
            SELECT NEW.created_by_id AS id
              WHERE NEW.created_by_id IS NOT NULL
                AND NEW.created_by_id IS DISTINCT FROM NEW.rep_id
          ),
          finance_users AS (
            SELECT DISTINCT ur.user_id AS id
            FROM user_roles ur
            JOIN role_permissions rp ON rp.role_id = ur.role_id
            WHERE rp.permission IN ('finance.ledger.read', '*')
              AND ur.is_active = true
            LIMIT 10
          )
          SELECT id FROM direct_actors
          UNION
          SELECT id FROM finance_users
        ) INTO v_recipient_ids;

        IF v_recipient_ids IS NOT NULL
           AND array_length(v_recipient_ids, 1) > 0 THEN
          PERFORM public.call_dispatch_notification(
            'sales.order.delivered',
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

      -- ── cancelled ────────────────────────────────────────────────────────
      ELSIF NEW.status = 'cancelled' AND OLD.status <> 'cancelled' THEN
        -- Recipients: rep + created_by (notify them their order was cancelled)
        SELECT ARRAY(
          SELECT NEW.rep_id WHERE NEW.rep_id IS NOT NULL
          UNION
          SELECT NEW.created_by_id
            WHERE NEW.created_by_id IS NOT NULL
              AND NEW.created_by_id IS DISTINCT FROM NEW.rep_id
        ) INTO v_recipient_ids;

        IF v_recipient_ids IS NOT NULL
           AND array_length(v_recipient_ids, 1) > 0 THEN
          PERFORM public.call_dispatch_notification(
            'sales.order.cancelled',
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

      END IF; -- status transitions
    END IF; -- TG_OP

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[notify_on_sales_order_lifecycle] non-critical: %', SQLERRM;
  END;

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Drop old confirmed-only trigger first (avoid duplicate fire on UPDATE confirmed)
DROP TRIGGER IF EXISTS trg_notify_sales_order_confirmed ON public.sales_orders;

-- Drop new lifecycle trigger if re-running (idempotency)
DROP TRIGGER IF EXISTS trg_notify_sales_order_lifecycle ON public.sales_orders;

CREATE TRIGGER trg_notify_sales_order_lifecycle
  AFTER INSERT OR UPDATE OF status ON public.sales_orders
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_sales_order_lifecycle();

REVOKE EXECUTE ON FUNCTION public.notify_on_sales_order_lifecycle() FROM authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- 2. purchase_invoices — EXTEND: add '→ paid' transition
-- ═══════════════════════════════════════════════════════════════════════════
--
-- WHAT CHANGES: CREATE OR REPLACE same function name (notify_on_purchase_invoice_change)
--   Adds ELSIF branch for status = 'paid'
--   received and billed branches: copied VERBATIM from migration 50 L454-509
-- TRIGGER: No change to trigger name (trg_notify_purchase_invoice)
--   DROP + CREATE to ensure column filter is correct

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
    INTO v_supplier_name
    FROM suppliers
    WHERE id = NEW.supplier_id
    LIMIT 1;

    v_amount_text := to_char(NEW.total_amount, 'FM999,999,999.00') || ' ج.م';

    -- ── received → notify finance users who can bill ─────────────────────
    -- [VERBATIM from migration 50 L454-479]
    IF NEW.status = 'received' THEN
      SELECT ARRAY(
        SELECT DISTINCT ur.user_id
        FROM user_roles ur
        JOIN role_permissions rp ON rp.role_id = ur.role_id
        WHERE rp.permission IN ('procurement.invoices.bill', '*')
          AND ur.is_active = true
        LIMIT 10
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

    -- ── billed → notify users who can authorize payment ──────────────────
    -- [VERBATIM from migration 50 L482-509]
    ELSIF NEW.status = 'billed' THEN
      SELECT ARRAY(
        SELECT DISTINCT ur.user_id
        FROM user_roles ur
        JOIN role_permissions rp ON rp.role_id = ur.role_id
        WHERE rp.permission IN ('procurement.invoices.pay', '*')
          AND ur.is_active = true
        LIMIT 10
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

    -- ── paid → notify created_by (the creator / initiator) ───────────────
    -- [NEW in Wave 1C]
    -- Recipient: NEW.created_by — the procurement staff who created the invoice
    ELSIF NEW.status = 'paid' AND NEW.created_by IS NOT NULL THEN
      PERFORM public.call_dispatch_notification(
        'purchase.invoice.paid',
        ARRAY[NEW.created_by],
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

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[notify_on_purchase_invoice_change] non-critical: %', SQLERRM;
  END;

  RETURN NEW;
END;
$$;

-- Re-create trigger (same name — idempotent)
DROP TRIGGER IF EXISTS trg_notify_purchase_invoice ON public.purchase_invoices;
CREATE TRIGGER trg_notify_purchase_invoice
  AFTER UPDATE OF status ON public.purchase_invoices
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_purchase_invoice_change();

REVOKE EXECUTE ON FUNCTION public.notify_on_purchase_invoice_change() FROM authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- 3. hr_payroll_runs — EXTEND: add '→ review' transition
-- ═══════════════════════════════════════════════════════════════════════════
--
-- WHAT CHANGES: CREATE OR REPLACE same function name (notify_on_payroll_paid)
--   Adds review branch BEFORE the paid guard — no conflict with paid logic
--   review branch fires ONLY when status changes TO 'review' from non-review
--   paid branch fires ONLY when status changes TO 'paid' (guard unchanged)
--
-- TRIGGER: Renamed from trg_notify_payroll_paid → trg_notify_payroll_lifecycle
--   Old trigger DROPPED. New trigger CREATED.
--   This is safe: DROP + CREATE = same net effect as the old trigger
--   on a broader rename for clarity.
--
-- RECIPIENT for review:
--   hr.payroll.calculate permission holders — those who can calculate payroll
--   are the ones who need to review it before approval.
--   Permission verified in: 19_hr_payroll_loans.sql L464 + 01_foundation.sql L484
--   Wildcard * included per pattern from migration 50.

CREATE OR REPLACE FUNCTION public.notify_on_payroll_paid()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_line             RECORD;
  v_month_name       text;
  v_recipient_ids    uuid[];
  v_total_net_text   text;
BEGIN
  -- ── Branch 1: status → 'review' ─────────────────────────────────────────
  -- Notify payroll managers that the run is ready for their review
  -- [NEW in Wave 1C]
  IF NEW.status = 'review' AND OLD.status IS DISTINCT FROM 'review' THEN
    BEGIN
      SELECT to_char(make_date(pp.year, pp.month, 1), 'Month YYYY')
      INTO v_month_name
      FROM hr_payroll_periods pp
      WHERE pp.id = NEW.period_id
      LIMIT 1;

      v_month_name     := COALESCE(trim(v_month_name), 'هذا الشهر');
      v_total_net_text := to_char(NEW.total_net, 'FM999,999,999.00') || ' ج.م';

      SELECT ARRAY(
        SELECT DISTINCT ur.user_id
        FROM user_roles ur
        JOIN role_permissions rp ON rp.role_id = ur.role_id
        WHERE rp.permission IN ('hr.payroll.calculate', '*')
          AND ur.is_active = true
        LIMIT 15
      ) INTO v_recipient_ids;

      IF v_recipient_ids IS NOT NULL
         AND array_length(v_recipient_ids, 1) > 0 THEN
        PERFORM public.call_dispatch_notification(
          'hr.payroll.ready_for_review',
          v_recipient_ids,
          jsonb_build_object(
            'month',          v_month_name,
            'total_net',      v_total_net_text,
            'employee_count', NEW.total_employees::text,
            'payroll_run_id', NEW.id::text
          ),
          'hr_payroll_run',
          NEW.id
        );
      END IF;

    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '[notify_on_payroll_paid] review branch non-critical: %', SQLERRM;
    END;

    -- Do NOT return here — if somehow status jumps to review then paid in one
    -- operation (impossible in practice), allow the paid branch to also fire.
    -- In normal flow: RETURN NEW here to avoid redundant paid-branch check.
    RETURN NEW;
  END IF;

  -- ── Branch 2: status → 'paid' ────────────────────────────────────────────
  -- [PRESERVED VERBATIM from migration 46 L388-436]
  -- Guard: only fire on confirmation transition
  IF NEW.status <> 'paid' OR OLD.status = 'paid' THEN
    RETURN NEW;
  END IF;

  BEGIN
    SELECT to_char(make_date(pp.year, pp.month, 1), 'Month YYYY')
    INTO   v_month_name
    FROM   hr_payroll_periods pp
    WHERE  pp.id = NEW.period_id
    LIMIT  1;

    v_month_name := COALESCE(trim(v_month_name), 'هذا الشهر');

    -- Iterate payroll lines and notify each employee individually
    FOR v_line IN
      SELECT
        pl.net_salary,
        he.user_id AS employee_profile
      FROM   hr_payroll_lines pl
      JOIN   hr_employees he ON he.id = pl.employee_id
      WHERE  pl.payroll_run_id = NEW.id
        AND  he.user_id IS NOT NULL
    LOOP
      BEGIN
        PERFORM public.call_dispatch_notification(
          'hr.payroll.processed',
          ARRAY[v_line.employee_profile],
          jsonb_build_object(
            'month',          v_month_name,
            'net_salary',     to_char(v_line.net_salary, 'FM999,999,999.00') || ' ج.م',
            'total_amount',   to_char(v_line.net_salary, 'FM999,999,999.00') || ' ج.م',
            'payroll_run_id', NEW.id::text
          ),
          'hr_payroll_run',
          NEW.id
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[notify_on_payroll_paid] per-employee error: %', SQLERRM;
      END;
    END LOOP;

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[notify_on_payroll_paid] non-critical: %', SQLERRM;
  END;

  RETURN NEW;
END;
$$;

-- Drop old trigger (confirmed→paid only, AFTER UPDATE OF status)
DROP TRIGGER IF EXISTS trg_notify_payroll_paid ON public.hr_payroll_runs;

-- Create renamed trigger (same scope — AFTER UPDATE OF status, same table)
DROP TRIGGER IF EXISTS trg_notify_payroll_lifecycle ON public.hr_payroll_runs;
CREATE TRIGGER trg_notify_payroll_lifecycle
  AFTER UPDATE OF status ON public.hr_payroll_runs
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_payroll_paid();

REVOKE EXECUTE ON FUNCTION public.notify_on_payroll_paid() FROM authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- 4. hr_attendance_days — NEW independent early_leave trigger
-- ═══════════════════════════════════════════════════════════════════════════
--
-- EXISTING: trg_notify_attendance_late AFTER INSERT (migration 46 L519)
--   → fires on new row with late_minutes > 5
-- NEW:      trg_notify_attendance_early_leave AFTER UPDATE
--   → fires when early_leave_minutes transitions from 0/null → > 0
--   → completely different TG_OP (INSERT vs UPDATE) — ZERO overlap guaranteed
--
-- Schema verified (migration 46 L452):
--   hr_attendance_days.early_leave_minutes INTEGER DEFAULT 0
--   hr_attendance_days.shift_date DATE
--   hr_attendance_days.employee_id → hr_employees.id
--   hr_employees.direct_manager_id → hr_employees.id (not reporting_manager_id — verified 46 L455)
--   hr_employees.user_id UUID
--
-- Recipient: direct_manager_id → manager's user_id (mirrors late trigger pattern)

CREATE OR REPLACE FUNCTION public.notify_on_attendance_early_leave()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_manager_profile uuid;
  v_emp_name        text;
  v_date_text       text;
BEGIN
  -- Guard: only fire when early_leave_minutes first becomes > 0
  -- (transition from 0/null to a positive value)
  IF COALESCE(NEW.early_leave_minutes, 0) <= 0 THEN
    RETURN NEW;
  END IF;
  IF COALESCE(OLD.early_leave_minutes, 0) > 0 THEN
    -- Already had early_leave previously — avoid re-notifying on minor updates
    RETURN NEW;
  END IF;

  BEGIN
    -- Resolve employee name + direct manager's profile_id
    -- direct_manager_id verified from 46_notification_full_coverage.sql L455
    SELECT
      emp.full_name,
      mgr.user_id
    INTO
      v_emp_name,
      v_manager_profile
    FROM   hr_employees emp
    LEFT JOIN hr_employees mgr ON mgr.id = emp.direct_manager_id
    WHERE  emp.id = NEW.employee_id
    LIMIT  1;

    v_date_text := to_char(NEW.shift_date, 'YYYY-MM-DD');

    IF v_manager_profile IS NOT NULL THEN
      PERFORM public.call_dispatch_notification(
        'hr.attendance.early_leave',
        ARRAY[v_manager_profile],
        jsonb_build_object(
          'employee_name',  COALESCE(v_emp_name, 'موظف'),
          'minutes_early',  NEW.early_leave_minutes::text,
          'date',           v_date_text,
          'employee_id',    NEW.employee_id::text
        ),
        'hr_attendance_day',
        NEW.id
      );
    END IF;

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[notify_on_attendance_early_leave] non-critical: %', SQLERRM;
  END;

  RETURN NEW;
END;
$$;

-- Independent AFTER UPDATE trigger — different from trg_notify_attendance_late (AFTER INSERT)
DROP TRIGGER IF EXISTS trg_notify_attendance_early_leave ON public.hr_attendance_days;
CREATE TRIGGER trg_notify_attendance_early_leave
  AFTER UPDATE OF early_leave_minutes ON public.hr_attendance_days
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_attendance_early_leave();

REVOKE EXECUTE ON FUNCTION public.notify_on_attendance_early_leave() FROM authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_fn_count  INTEGER;
  v_trg_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_fn_count
  FROM pg_proc
  WHERE proname IN (
    'notify_on_sales_order_lifecycle',
    'notify_on_purchase_invoice_change',
    'notify_on_payroll_paid',
    'notify_on_attendance_early_leave'
  );

  SELECT COUNT(*) INTO v_trg_count
  FROM information_schema.triggers
  WHERE trigger_name IN (
    'trg_notify_sales_order_lifecycle',
    'trg_notify_purchase_invoice',
    'trg_notify_payroll_lifecycle',
    'trg_notify_attendance_early_leave'
  );

  -- Verify old confirmed trigger is gone (no duplicate)
  IF EXISTS (SELECT 1 FROM information_schema.triggers
             WHERE trigger_name = 'trg_notify_sales_order_confirmed') THEN
    RAISE WARNING '[54_wave1c] ⚠️  trg_notify_sales_order_confirmed STILL EXISTS — duplicate risk!';
  END IF;

  -- Verify old payroll trigger is gone
  IF EXISTS (SELECT 1 FROM information_schema.triggers
             WHERE trigger_name = 'trg_notify_payroll_paid') THEN
    RAISE WARNING '[54_wave1c] ⚠️  trg_notify_payroll_paid STILL EXISTS — duplicate risk!';
  END IF;

  -- Verify target recalc triggers are intact
  RAISE NOTICE '══════════════════════════════════════════════════════════';
  RAISE NOTICE '[54_notification_wave1c] VERIFICATION RESULT:';
  RAISE NOTICE '  Functions present: % / 4', v_fn_count;
  RAISE NOTICE '  Triggers present:  % / 4', v_trg_count;

  RAISE NOTICE '  trg_so_recalc_targets: %',
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.triggers WHERE trigger_name = 'trg_so_recalc_targets')
    THEN '✅ intact' ELSE '❌ MISSING' END;

  RAISE NOTICE '  trg_notify_sales_order_confirmed  (must be GONE): %',
    CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.triggers WHERE trigger_name = 'trg_notify_sales_order_confirmed')
    THEN '✅ dropped' ELSE '❌ STILL EXISTS — duplicate risk' END;

  RAISE NOTICE '  trg_notify_payroll_paid  (must be GONE): %',
    CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.triggers WHERE trigger_name = 'trg_notify_payroll_paid')
    THEN '✅ dropped' ELSE '❌ STILL EXISTS — duplicate risk' END;

  RAISE NOTICE '  trg_notify_attendance_late  (must remain): %',
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.triggers WHERE trigger_name = 'trg_notify_attendance_late')
    THEN '✅ intact' ELSE '❌ MISSING' END;

  IF v_fn_count = 4 AND v_trg_count = 4 THEN
    RAISE NOTICE '  ✅ Wave 1C complete';
  ELSE
    RAISE WARNING '[54_wave1c] ⚠️  Expected 4/4 — check output above';
  END IF;
  RAISE NOTICE '══════════════════════════════════════════════════════════';
END $$;
