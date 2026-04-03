-- ═══════════════════════════════════════════════════════════════════════════
-- 53_notification_wave1b_new_triggers.sql
-- Wave 1B — New Notification Triggers (Tables Without Existing Notification Triggers)
--
-- SCOPE — 5 tables, all new (no prior notification triggers):
--   1. payment_receipts   → finance.payment.received / .confirmed / .rejected
--   2. custody_transactions → finance.custody.loaded
--   3. sales_returns      → sales.return.created / .confirmed
--   4. purchase_returns   → purchase.return.confirmed
--   5. hr_payroll_adjustments → hr.adjustment.created / .approved / .rejected
--
-- EXISTING TRIGGERS NOT TOUCHED (confirmed from migrations 22e, 03):
--   trg_pr_insert_recalc_targets  (payment_receipts AFTER INSERT)  — migration 22e
--   trg_pr_update_recalc_targets  (payment_receipts AFTER UPDATE)  — migration 22e
--   trg_sr_recalc_targets         (sales_returns AFTER UPDATE)     — migration 22e
--   trg_receipts_updated_at       (payment_receipts BEFORE UPDATE) — migration 03
--   trg_receipt_auto_number       (payment_receipts BEFORE INSERT) — migration 03
--   trg_sales_returns_updated_at  (sales_returns BEFORE UPDATE)    — migration 04
--   trg_purchase_return_number    (purchase_returns BEFORE INSERT) — migration 16
--   trg_purchase_returns_updated_at (purchase_returns BEFORE UPDATE) — migration 16
--   trg_adj_updated_at            (hr_payroll_adjustments BEFORE UPDATE) — migration 20c
--
-- DUPLICATE PREVENTION:
--   • Each function is an independent AFTER trigger — no shared function names
--   • AFTER fires after BEFORE (updated_at, auto-number) — no conflict
--   • Target recalc triggers are different functions on different events:
--       trg_pr_insert_recalc (AFTER INSERT) fires independently from
--       trg_notify_payment_receipt_change (AFTER INSERT) — both execute,
--       PostgreSQL fires multiple AFTER triggers alphabetically or by creation
--       order, each independently committed.
--   • All notification functions are fire-and-forget via call_dispatch_notification
--     (pg_net async HTTP) — they do not modify the triggering row
--
-- SAFETY:
--   ✅ All triggers: AFTER (business tx commits first)
--   ✅ All functions: BEGIN..EXCEPTION WHEN OTHERS (never block business logic)
--   ✅ SECURITY DEFINER + SET search_path = public
--   ✅ CREATE OR REPLACE — idempotent
--   ✅ DROP TRIGGER IF EXISTS before CREATE — idempotent
--   ✅ call_dispatch_notification returns void, never raises
--
-- RECIPIENT MAPPING (verified from schema):
--   payment_receipts:
--     .received   → check_permission 'finance.payments.confirm' (03_financial_infrastructure.sql L554)
--     .confirmed  → NEW.created_by (profile_id who created the receipt)
--     .rejected   → NEW.created_by
--   custody_transactions:
--     .loaded     → custody_accounts.employee_id (= profiles.id directly — 03_financial.sql L204)
--   sales_returns:
--     .created    → check_permission 'sales.returns.confirm'
--     .confirmed  → NEW.created_by
--   purchase_returns:
--     .confirmed  → NEW.created_by
--   hr_payroll_adjustments:
--     .created    → check_permission 'hr.adjustments.approve' (20c_hr_adjustments.sql L88)
--     .approved   → hr_employees WHERE id = NEW.employee_id → user_id
--     .rejected   → same
-- ═══════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════
-- 1. payment_receipts
-- ═══════════════════════════════════════════════════════════════════════════
-- Schema verified (03_financial_infrastructure.sql L244, 08_payment_receipts_refactor.sql):
--   id, customer_id, amount, payment_method, status (pending/confirmed/rejected)
--   collected_by, created_by (both → profiles.id)
--   sales_order_id (added in migration 08 via confirm_payment_receipt usage)
--   custody_id → custody_accounts.id
-- Existing non-notification triggers: trg_receipt_auto_number (BEFORE INSERT),
--   trg_receipts_updated_at (BEFORE UPDATE),
--   trg_pr_insert_recalc_targets (AFTER INSERT), trg_pr_update_recalc_targets (AFTER UPDATE)

CREATE OR REPLACE FUNCTION public.notify_on_payment_receipt_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_approvers       uuid[];
  v_customer_name   text;
  v_amount_text     text;
  v_receipt_num     text;
BEGIN
  BEGIN
    -- Resolve display values (best-effort — all inside exception wrapper)
    SELECT name INTO v_customer_name
    FROM customers WHERE id = NEW.customer_id LIMIT 1;

    v_amount_text := to_char(NEW.amount, 'FM999,999,999.00') || ' ج.م';
    v_receipt_num := COALESCE(NEW.number, NEW.id::text);

    -- ─────────────────────────────────────────────────────────────
    -- INSERT: New receipt created
    -- ─────────────────────────────────────────────────────────────
    IF TG_OP = 'INSERT' THEN

      IF NEW.status = 'pending' THEN
        -- Cash receipt pending confirmation → notify finance.payments.confirm holders
        -- [RC pattern from migration 50]: include wildcard '*' for admin roles
        SELECT ARRAY(
          SELECT DISTINCT ur.user_id
          FROM user_roles ur
          JOIN role_permissions rp ON rp.role_id = ur.role_id
          WHERE rp.permission IN ('finance.payments.confirm', '*')
            AND ur.is_active = true
          LIMIT 20
        ) INTO v_approvers;

        IF array_length(v_approvers, 1) > 0 THEN
          PERFORM public.call_dispatch_notification(
            'finance.payment.received',
            v_approvers,
            jsonb_build_object(
              'collector_name',  COALESCE((SELECT full_name FROM profiles WHERE id = NEW.collected_by), 'مندوب'),
              'amount',          v_amount_text,
              'customer_name',   COALESCE(v_customer_name, 'عميل'),
              'order_number',    COALESCE(NEW.sales_order_id::text, ''),
              'receipt_id',      NEW.id::text
            ),
            'payment_receipt',
            NEW.id
          );
        END IF;

      ELSIF NEW.status = 'confirmed' THEN
        -- Direct confirmed INSERT (cash/field path via deliver_sales_order)
        -- Notify the creator immediately
        IF NEW.created_by IS NOT NULL THEN
          PERFORM public.call_dispatch_notification(
            'finance.payment.confirmed',
            ARRAY[NEW.created_by],
            jsonb_build_object(
              'amount',        v_amount_text,
              'customer_name', COALESCE(v_customer_name, 'عميل'),
              'receipt_id',    NEW.id::text
            ),
            'payment_receipt',
            NEW.id
          );
        END IF;
      END IF;

    -- ─────────────────────────────────────────────────────────────
    -- UPDATE: Status transition
    -- ─────────────────────────────────────────────────────────────
    ELSIF TG_OP = 'UPDATE' THEN

      IF NEW.status = 'confirmed' AND OLD.status IS DISTINCT FROM 'confirmed' THEN
        IF NEW.created_by IS NOT NULL THEN
          PERFORM public.call_dispatch_notification(
            'finance.payment.confirmed',
            ARRAY[NEW.created_by],
            jsonb_build_object(
              'amount',        v_amount_text,
              'customer_name', COALESCE(v_customer_name, 'عميل'),
              'receipt_id',    NEW.id::text
            ),
            'payment_receipt',
            NEW.id
          );
        END IF;

      ELSIF NEW.status = 'rejected' AND OLD.status IS DISTINCT FROM 'rejected' THEN
        IF NEW.created_by IS NOT NULL THEN
          PERFORM public.call_dispatch_notification(
            'finance.payment.rejected',
            ARRAY[NEW.created_by],
            jsonb_build_object(
              'amount',        v_amount_text,
              'customer_name', COALESCE(v_customer_name, 'عميل'),
              'reason',        COALESCE(NEW.rejection_reason, 'لم يُحدد سبب'),
              'receipt_id',    NEW.id::text
            ),
            'payment_receipt',
            NEW.id
          );
        END IF;
      END IF;

    END IF;

  EXCEPTION WHEN OTHERS THEN
    -- Non-blocking: notification failure never blocks the business transaction
    RAISE WARNING '[notify_on_payment_receipt_change] non-critical error: %', SQLERRM;
  END;

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Drop then create (idempotent)
DROP TRIGGER IF EXISTS trg_notify_payment_receipt_change ON public.payment_receipts;
CREATE TRIGGER trg_notify_payment_receipt_change
  AFTER INSERT OR UPDATE OF status ON public.payment_receipts
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_payment_receipt_change();

REVOKE EXECUTE ON FUNCTION public.notify_on_payment_receipt_change() FROM authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- 2. custody_transactions
-- ═══════════════════════════════════════════════════════════════════════════
-- Schema verified (03_financial_infrastructure.sql L217):
--   custody_id → custody_accounts.id
--   custody_accounts.employee_id → profiles.id (UNIQUE NOT NULL — direct profile ref, NOT hr_employees)
--   type IN ('load', 'collection', 'expense', 'settlement', 'return')
--   amount, balance_after, description, created_by
-- No existing notification triggers on this table.

CREATE OR REPLACE FUNCTION public.notify_on_custody_loaded()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_profile_id  uuid;
  v_amount_text       text;
  v_balance_text      text;
BEGIN
  BEGIN
    -- Only fire for 'load' type (custody top-up)
    IF NEW.type <> 'load' THEN
      RETURN NEW;
    END IF;

    -- custody_accounts.employee_id IS profiles.id (direct — not hr_employees)
    SELECT ca.employee_id INTO v_owner_profile_id
    FROM custody_accounts ca
    WHERE ca.id = NEW.custody_id
    LIMIT 1;

    IF v_owner_profile_id IS NULL THEN
      RETURN NEW;
    END IF;

    v_amount_text  := to_char(NEW.amount, 'FM999,999,999.00') || ' ج.م';
    v_balance_text := to_char(NEW.balance_after, 'FM999,999,999.00') || ' ج.م';

    PERFORM public.call_dispatch_notification(
      'finance.custody.loaded',
      ARRAY[v_owner_profile_id],
      jsonb_build_object(
        'amount',     v_amount_text,
        'balance',    v_balance_text,
        'custody_id', NEW.custody_id::text
      ),
      'custody_transaction',
      NEW.id
    );

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[notify_on_custody_loaded] non-critical error: %', SQLERRM;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_custody_loaded ON public.custody_transactions;
CREATE TRIGGER trg_notify_custody_loaded
  AFTER INSERT ON public.custody_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_custody_loaded();

REVOKE EXECUTE ON FUNCTION public.notify_on_custody_loaded() FROM authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- 3. sales_returns
-- ═══════════════════════════════════════════════════════════════════════════
-- Schema verified (04_sales_system.sql L288):
--   id, return_number, order_id, customer_id, warehouse_id
--   status (sales_return_status ENUM) DEFAULT 'draft'
--   total_amount, reason
--   confirmed_by, confirmed_at, cancelled_by, cancelled_at
--   created_by (profiles.id NOT NULL)
-- Existing non-notification triggers:
--   trg_sales_returns_updated_at (BEFORE UPDATE) — migration 04
--   trg_sr_recalc_targets (AFTER UPDATE) — migration 22e (targets recalc)
-- No conflict: trg_sr_recalc_targets fires on UPDATE status→'confirmed',
--   our trigger fires on INSERT + UPDATE status→'confirmed'. Both are
--   independent AFTER triggers; PostgreSQL fires all applicable triggers.

CREATE OR REPLACE FUNCTION public.notify_on_sales_return_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_approvers       uuid[];
  v_customer_name   text;
  v_amount_text     text;
  v_return_num      text;
BEGIN
  BEGIN
    SELECT c.name INTO v_customer_name
    FROM sales_returns sr
    JOIN customers c ON c.id = sr.customer_id
    WHERE sr.id = NEW.id
    LIMIT 1;

    v_amount_text := to_char(NEW.total_amount, 'FM999,999,999.00') || ' ج.م';
    v_return_num  := COALESCE(NEW.return_number, NEW.id::text);

    -- ─────────────────────────────────────────────────────────────
    -- INSERT → sales.return.created
    -- Notify: holders of 'sales.returns.confirm' permission
    -- ─────────────────────────────────────────────────────────────
    IF TG_OP = 'INSERT' THEN
      -- [RC pattern from migration 50]: include wildcard '*' for admin roles
      SELECT ARRAY(
        SELECT DISTINCT ur.user_id
        FROM user_roles ur
        JOIN role_permissions rp ON rp.role_id = ur.role_id
        WHERE rp.permission IN ('sales.returns.confirm', '*')
          AND ur.is_active = true
        LIMIT 20
      ) INTO v_approvers;

      IF array_length(v_approvers, 1) > 0 THEN
        PERFORM public.call_dispatch_notification(
          'sales.return.created',
          v_approvers,
          jsonb_build_object(
            'return_number',  v_return_num,
            'amount',         v_amount_text,
            'customer_name',  COALESCE(v_customer_name, 'عميل'),
            'return_id',      NEW.id::text
          ),
          'sales_return',
          NEW.id
        );
      END IF;

    -- ─────────────────────────────────────────────────────────────
    -- UPDATE status → 'confirmed' → sales.return.confirmed
    -- Notify: created_by (the sales rep or clerk who created the return)
    -- ─────────────────────────────────────────────────────────────
    ELSIF TG_OP = 'UPDATE' THEN
      IF NEW.status = 'confirmed' AND OLD.status IS DISTINCT FROM 'confirmed' THEN
        IF NEW.created_by IS NOT NULL THEN
          PERFORM public.call_dispatch_notification(
            'sales.return.confirmed',
            ARRAY[NEW.created_by],
            jsonb_build_object(
              'return_number',  v_return_num,
              'amount',         v_amount_text,
              'customer_name',  COALESCE(v_customer_name, 'عميل'),
              'return_id',      NEW.id::text
            ),
            'sales_return',
            NEW.id
          );
        END IF;
      END IF;
    END IF;

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[notify_on_sales_return_change] non-critical error: %', SQLERRM;
  END;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_sales_return_change ON public.sales_returns;
CREATE TRIGGER trg_notify_sales_return_change
  AFTER INSERT OR UPDATE OF status ON public.sales_returns
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_sales_return_change();

REVOKE EXECUTE ON FUNCTION public.notify_on_sales_return_change() FROM authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- 4. purchase_returns
-- ═══════════════════════════════════════════════════════════════════════════
-- Schema verified (16_procurement_returns_and_cancellations.sql L143):
--   id, number, supplier_id, warehouse_id, original_invoice_id
--   status TEXT CHECK IN ('draft', 'confirmed') DEFAULT 'draft'
--   return_date, notes, subtotal, discount_amount, tax_amount, total_amount
--   confirmed_by, confirmed_at, created_by (profiles.id)
-- Existing non-notification triggers:
--   trg_purchase_return_number (BEFORE INSERT) — migration 16
--   trg_purchase_returns_updated_at (BEFORE UPDATE) — migration 16
-- No existing notification triggers.

CREATE OR REPLACE FUNCTION public.notify_on_purchase_return_confirmed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_supplier_name  text;
  v_amount_text    text;
  v_return_num     text;
BEGIN
  BEGIN
    -- Only fire on status transition: draft → confirmed
    IF NOT (NEW.status = 'confirmed' AND OLD.status IS DISTINCT FROM 'confirmed') THEN
      RETURN NEW;
    END IF;

    IF NEW.created_by IS NULL THEN
      RETURN NEW;
    END IF;

    SELECT s.name INTO v_supplier_name
    FROM suppliers s WHERE s.id = NEW.supplier_id LIMIT 1;

    v_amount_text := to_char(NEW.total_amount, 'FM999,999,999.00') || ' ج.م';
    v_return_num  := COALESCE(NEW.number, NEW.id::text);

    PERFORM public.call_dispatch_notification(
      'purchase.return.confirmed',
      ARRAY[NEW.created_by],
      jsonb_build_object(
        'return_number',  v_return_num,
        'amount',         v_amount_text,
        'supplier_name',  COALESCE(v_supplier_name, 'مورد'),
        'return_id',      NEW.id::text
      ),
      'purchase_return',
      NEW.id
    );

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[notify_on_purchase_return_confirmed] non-critical error: %', SQLERRM;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_purchase_return_confirmed ON public.purchase_returns;
CREATE TRIGGER trg_notify_purchase_return_confirmed
  AFTER UPDATE OF status ON public.purchase_returns
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_purchase_return_confirmed();

REVOKE EXECUTE ON FUNCTION public.notify_on_purchase_return_confirmed() FROM authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- 5. hr_payroll_adjustments
-- ═══════════════════════════════════════════════════════════════════════════
-- Schema verified (20c_hr_adjustments.sql L13):
--   id, employee_id (→ hr_employees.id), type IN ('bonus','deduction','penalty')
--   amount, reason, effective_date
--   status IN ('pending','approved','rejected') DEFAULT 'pending'
--   created_by (→ profiles.id), approved_by (→ profiles.id)
--   payroll_line_id, created_at, updated_at
-- Existing non-notification triggers:
--   trg_adj_updated_at (BEFORE UPDATE) — migration 20c
-- Permission 'hr.adjustments.approve' exists in RLS (20c_hr_adjustments.sql L84-88)
-- Note: Permission NOT in constants.ts frontend — notification routing uses
--   DB-side role_permissions join only (safe, consistent with RLS)

CREATE OR REPLACE FUNCTION public.notify_on_hr_adjustment_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_approvers       uuid[];
  v_employee_name   text;
  v_employee_user   uuid;
  v_amount_text     text;
  v_requester_name  text;
  v_type_label      text;
BEGIN
  BEGIN
    -- Resolve employee display info
    SELECT he.user_id,
           COALESCE(he.full_name, 'موظف')
    INTO   v_employee_user,
           v_employee_name
    FROM   hr_employees he
    WHERE  he.id = NEW.employee_id
    LIMIT  1;

    v_amount_text := to_char(NEW.amount, 'FM999,999,999.00') || ' ج.م';

    -- Resolve requester name (created_by)
    IF NEW.created_by IS NOT NULL THEN
      SELECT COALESCE(full_name, 'مستخدم') INTO v_requester_name
      FROM profiles WHERE id = NEW.created_by LIMIT 1;
    END IF;
    v_requester_name := COALESCE(v_requester_name, 'مستخدم');

    -- Human-readable type label
    v_type_label := CASE NEW.type
      WHEN 'bonus'     THEN 'مكافأة'
      WHEN 'deduction' THEN 'خصم'
      WHEN 'penalty'   THEN 'جزاء'
      ELSE NEW.type
    END;

    -- ─────────────────────────────────────────────────────────────
    -- INSERT → hr.adjustment.created
    -- Notify: holders of 'hr.adjustments.approve' permission
    -- (This is the standard approval workflow per 20c_hr_adjustments.sql)
    -- ─────────────────────────────────────────────────────────────
    IF TG_OP = 'INSERT' THEN
      -- [RC pattern from migration 50]: include wildcard '*' for admin roles
      SELECT ARRAY(
        SELECT DISTINCT ur.user_id
        FROM user_roles ur
        JOIN role_permissions rp ON rp.role_id = ur.role_id
        WHERE rp.permission IN ('hr.adjustments.approve', '*')
          AND ur.is_active = true
        LIMIT 20
      ) INTO v_approvers;

      IF array_length(v_approvers, 1) > 0 THEN
        PERFORM public.call_dispatch_notification(
          'hr.adjustment.created',
          v_approvers,
          jsonb_build_object(
            'requester_name',  v_requester_name,
            'adjustment_type', v_type_label,
            'amount',          v_amount_text,
            'employee_name',   v_employee_name,
            'adjustment_id',   NEW.id::text
          ),
          'hr_payroll_adjustment',
          NEW.id
        );
      END IF;

    -- ─────────────────────────────────────────────────────────────
    -- UPDATE status → approved / rejected
    -- Notify: the affected employee (via hr_employees.user_id)
    -- ─────────────────────────────────────────────────────────────
    ELSIF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN

      IF NEW.status = 'approved' AND v_employee_user IS NOT NULL THEN
        PERFORM public.call_dispatch_notification(
          'hr.adjustment.approved',
          ARRAY[v_employee_user],
          jsonb_build_object(
            'adjustment_type', v_type_label,
            'amount',          v_amount_text,
            'adjustment_id',   NEW.id::text
          ),
          'hr_payroll_adjustment',
          NEW.id
        );

      ELSIF NEW.status = 'rejected' AND v_employee_user IS NOT NULL THEN
        PERFORM public.call_dispatch_notification(
          'hr.adjustment.rejected',
          ARRAY[v_employee_user],
          jsonb_build_object(
            'adjustment_type', v_type_label,
            'amount',          v_amount_text,
            'adjustment_id',   NEW.id::text
          ),
          'hr_payroll_adjustment',
          NEW.id
        );
      END IF;

    END IF;

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[notify_on_hr_adjustment_change] non-critical error: %', SQLERRM;
  END;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_hr_adjustment_change ON public.hr_payroll_adjustments;
CREATE TRIGGER trg_notify_hr_adjustment_change
  AFTER INSERT OR UPDATE OF status ON public.hr_payroll_adjustments
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_hr_adjustment_change();

REVOKE EXECUTE ON FUNCTION public.notify_on_hr_adjustment_change() FROM authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- SEED: hr.adjustments.approve into role_permissions
-- ═══════════════════════════════════════════════════════════════════════════
-- [P1 FIX]: hr.adjustments.approve is referenced in RLS/RPC (20c_hr_adjustments.sql)
-- but was never seeded into role_permissions. Without this seed, notify_on_hr_adjustment_change
-- returns zero recipients on clean deployments and the notification is silently dropped.
--
-- Granted to: hr_manager, super_admin
-- (hr_manager is the natural owner of payroll adjustment approval workflow)
-- ON CONFLICT DO NOTHING — safe if already granted manually via UI
-- ───────────────────────────────────────────────────────────────────────────
INSERT INTO role_permissions (role_id, permission)
SELECT r.id, 'hr.adjustments.approve'
FROM roles r
WHERE r.name IN ('hr_manager', 'super_admin')
ON CONFLICT DO NOTHING;

-- NOTE: No separate `permissions` table exists in this system.
-- Permissions are stored as TEXT directly in role_permissions.permission.
-- The INSERT above into role_permissions is sufficient.


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
    'notify_on_payment_receipt_change',
    'notify_on_custody_loaded',
    'notify_on_sales_return_change',
    'notify_on_purchase_return_confirmed',
    'notify_on_hr_adjustment_change'
  );

  SELECT COUNT(*) INTO v_trg_count
  FROM information_schema.triggers
  WHERE trigger_name IN (
    'trg_notify_payment_receipt_change',
    'trg_notify_custody_loaded',
    'trg_notify_sales_return_change',
    'trg_notify_purchase_return_confirmed',
    'trg_notify_hr_adjustment_change'
  );

  -- Verify existing non-notification triggers are intact
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE trigger_name = 'trg_pr_insert_recalc_targets'
  ) THEN
    RAISE WARNING '[53_wave1b] ⚠️  trg_pr_insert_recalc_targets MISSING — unexpected!';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE trigger_name = 'trg_pr_update_recalc_targets'
  ) THEN
    RAISE WARNING '[53_wave1b] ⚠️  trg_pr_update_recalc_targets MISSING — unexpected!';
  END IF;

  RAISE NOTICE '══════════════════════════════════════════════════════════';
  RAISE NOTICE '[53_notification_wave1b] VERIFICATION RESULT:';
  RAISE NOTICE '  Functions registered: % / 5', v_fn_count;
  RAISE NOTICE '  Triggers registered:  % / 5', v_trg_count;
  RAISE NOTICE '  trg_pr_insert_recalc_targets: %',
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.triggers WHERE trigger_name = 'trg_pr_insert_recalc_targets')
    THEN '✅ intact' ELSE '❌ MISSING' END;
  RAISE NOTICE '  trg_pr_update_recalc_targets: %',
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.triggers WHERE trigger_name = 'trg_pr_update_recalc_targets')
    THEN '✅ intact' ELSE '❌ MISSING' END;
  RAISE NOTICE '  trg_sr_recalc_targets: %',
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.triggers WHERE trigger_name = 'trg_sr_recalc_targets')
    THEN '✅ intact' ELSE '❌ MISSING' END;

  IF v_fn_count = 5 AND v_trg_count = 5 THEN
    RAISE NOTICE '  ✅ Wave 1B complete — 5 functions + 5 triggers';
  ELSE
    RAISE WARNING '[53_wave1b] ⚠️  Expected 5/5 — check above';
  END IF;
  RAISE NOTICE '══════════════════════════════════════════════════════════';
END $$;
