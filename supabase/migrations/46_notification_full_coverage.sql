-- ═══════════════════════════════════════════════════════════════════════════
-- 46_notification_full_coverage.sql
-- Full Business Event Notification Coverage — Phase 2
--
-- AUDIT CORRECTIONS v2 (applied after schema verification):
--   1. hr_employees.direct_manager_id  (not reporting_manager_id)
--   2. Contract expiry reads from hr_contracts.end_date (not hr_employees)
--   3. Attendance late trigger fires on INSERT with late_minutes > 5
--      (no status filter — status field may be 'present' with late_minutes > 0)
--   4. hr_permission_requests: does NOT have approved_by as profiles.id —
--      it's approved_by UUID REFERENCES hr_employees(id). Re-resolved.
--   5. call_dispatch_notification signature: (text, uuid[], jsonb, text, uuid) ✓
--
-- SAFETY PRINCIPLE (non-negotiable):
--   • AFTER triggers — business transaction always commits first
--   • All notification logic wrapped in BEGIN..EXCEPTION WHEN OTHERS THEN
--     RAISE WARNING — failure NEVER causes a business rollback
--   • pg_net call is fire-and-forget (async HTTP)
--
-- ═══════════════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS pg_net;


-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 1: NEW EVENT KEYS
-- ═══════════════════════════════════════════════════════════════════════════

INSERT INTO public.notification_event_types (
  event_key, label_ar, label_en,
  category, default_priority,
  title_template, body_template,
  icon, action_url_template
) VALUES

  -- ── HR Advances ──────────────────────────────────────────────────────────
  ('hr.advance.requested',
   'طلب سلفة جديد', 'Advance Request',
   'hr_payroll', 'high',
   'طلب سلفة يحتاج موافقتك',
   '{{employee_name}} طلب سلفة بمبلغ {{amount}}',
   'banknote', '/hr/advances/{{advance_id}}'),

  ('hr.advance.approved',
   'تمت الموافقة على السلفة', 'Advance Approved',
   'hr_payroll', 'medium',
   'تمت الموافقة على طلب سلفتك',
   'طلب السلفة بمبلغ {{amount}} تم اعتماده',
   'check-circle', '/hr/advances/{{advance_id}}'),

  ('hr.advance.rejected',
   'رُفض طلب السلفة', 'Advance Rejected',
   'hr_payroll', 'medium',
   'تم رفض طلب سلفتك',
   'طلب السلفة بمبلغ {{amount}} مرفوض. السبب: {{reason}}',
   'x-circle', '/hr/advances/{{advance_id}}'),

  -- ── HR Permission Requests ───────────────────────────────────────────────
  ('hr.permission.requested',
   'طلب إذن انصراف جديد', 'Permission Request',
   'hr_attendance', 'medium',
   'طلب إذن انصراف يحتاج موافقتك',
   '{{employee_name}} طلب إذن انصراف بتاريخ {{permission_date}} | {{reason}}',
   'clock-3', '/hr/permissions/{{permission_id}}'),

  ('hr.permission.approved',
   'تمت الموافقة على إذن الانصراف', 'Permission Approved',
   'hr_attendance', 'low',
   'تمت الموافقة على إذنك',
   'إذن الانصراف بتاريخ {{permission_date}} تم اعتماده',
   'check', '/hr/permissions/{{permission_id}}'),

  ('hr.permission.rejected',
   'رُفض إذن الانصراف', 'Permission Rejected',
   'hr_attendance', 'medium',
   'رُفض طلب إذن انصرافك',
   'طلب الإذن بتاريخ {{permission_date}} مرفوض. السبب: {{reason}}',
   'x-circle', '/hr/permissions/{{permission_id}}'),

  -- ── HR Payroll ───────────────────────────────────────────────────────────
  ('hr.payroll.processed',
   'راتبك جاهز', 'Payroll Ready',
   'hr_payroll', 'medium',
   'كشف راتبك جاهز لـ {{month}}',
   'راتب {{month}} تم صرفه بصافي {{net_salary}}',
   'banknote', '/hr/payslips/{{payroll_run_id}}'),

  -- ── HR Contract Expiry ────────────────────────────────────────────────────
  ('hr.contract.expiring',
   'عقد موظف ينتهي قريباً', 'Contract Expiring Soon',
   'hr_attendance', 'high',
   'تحذير: عقد موظف على وشك الانتهاء',
   'عقد {{employee_name}} ينتهي في {{expiry_date}} (خلال {{days_remaining}} يوم)',
   'file-warning', '/hr/employees/{{employee_id}}'),

  -- ── HR Attendance Late ─────────────────────────────────────────────────
  ('hr.attendance.late',
   'تأخر في الحضور', 'Late Arrival',
   'hr_attendance', 'medium',
   'تأخر في الحضور — {{employee_name}}',
   'وصل متأخراً {{minutes_late}} دقيقة في {{date}}',
   'clock', '/hr/attendance?date={{date}}&employee={{employee_id}}'),

  -- ── HR Attendance Absent (cron) ─────────────────────────────────────────
  ('hr.attendance.absent',
   'غياب بدون إذن', 'Unexcused Absence',
   'hr_attendance', 'high',
   'غياب بدون إذن — {{employee_name}}',
   '{{employee_name}} لم يسجل حضوراً في {{date}}',
   'user-x', '/hr/attendance?date={{date}}&employee={{employee_id}}'),

  -- ── Sales ────────────────────────────────────────────────────────────────
  ('sales.order.confirmed',
   'طلب بيع مؤكد', 'Sales Order Confirmed',
   'sales', 'medium',
   'تم تأكيد طلب البيع #{{order_number}}',
   'طلب البيع #{{order_number}} لعميل {{customer_name}} بقيمة {{amount}} تم تأكيده',
   'shopping-cart', '/sales/orders/{{order_id}}'),

  -- ── Procurement ──────────────────────────────────────────────────────────
  ('purchase.invoice.received',
   'استلام بضاعة — فاتورة شراء', 'Purchase Invoice Received',
   'procurement', 'medium',
   'استلمت البضاعة — فاتورة {{invoice_number}}',
   'تم استلام بضاعة فاتورة {{invoice_number}} من {{supplier_name}} | مطلوب الاعتماد المالي',
   'package-check', '/procurement/invoices/{{invoice_id}}'),

  ('purchase.invoice.billed',
   'اعتماد مالي — فاتورة شراء', 'Purchase Invoice Billed',
   'procurement', 'medium',
   'اعتماد مالي لفاتورة {{invoice_number}}',
   'فاتورة {{invoice_number}} من {{supplier_name}} بقيمة {{amount}} اعتُمدت مالياً',
   'receipt', '/procurement/invoices/{{invoice_id}}')

ON CONFLICT (event_key) DO UPDATE SET
  label_ar            = EXCLUDED.label_ar,
  label_en            = EXCLUDED.label_en,
  title_template      = EXCLUDED.title_template,
  body_template       = EXCLUDED.body_template,
  default_priority    = EXCLUDED.default_priority,
  icon                = EXCLUDED.icon,
  action_url_template = EXCLUDED.action_url_template,
  updated_at          = now();


-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 2: TRIGGER FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- 2.1  hr_advances  →  requested / approved / rejected
--      SCHEMA-VERIFIED:
--        hr_advances.employee_id → hr_employees.id
--        hr_advances.supervisor_id → hr_employees.id  ✓
--        hr_advances.rejection_reason TEXT             ✓
--        hr_advances.amount NUMERIC                    ✓
--        hr_employees.user_id UUID                     ✓
--        hr_employees.direct_manager_id UUID           ✓
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_on_advance_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee_profile   uuid;
  v_supervisor_profile uuid;
  v_amount_text        text;
  v_emp_name           text;
BEGIN
  BEGIN
    -- Resolve employee profile
    SELECT he.user_id, he.full_name
    INTO   v_employee_profile, v_emp_name
    FROM   hr_employees he
    WHERE  he.id = NEW.employee_id
    LIMIT  1;

    -- Resolve supervisor: try explicit supervisor_id first,
    -- fall back to direct_manager_id
    IF NEW.supervisor_id IS NOT NULL THEN
      SELECT he.user_id INTO v_supervisor_profile
      FROM   hr_employees he
      WHERE  he.id = NEW.supervisor_id
      LIMIT  1;
    ELSE
      SELECT mgr.user_id INTO v_supervisor_profile
      FROM   hr_employees emp
      JOIN   hr_employees mgr ON mgr.id = emp.direct_manager_id
      WHERE  emp.id = NEW.employee_id
      LIMIT  1;
    END IF;

    v_amount_text := to_char(NEW.amount, 'FM999,999,999.00') || ' ج.م';

    -- ── INSERT: new advance → notify supervisor ──────────────────────────
    IF TG_OP = 'INSERT' AND v_supervisor_profile IS NOT NULL THEN
      PERFORM public.call_dispatch_notification(
        'hr.advance.requested',
        ARRAY[v_supervisor_profile],
        jsonb_build_object(
          'employee_name', COALESCE(v_emp_name, 'موظف'),
          'amount',        v_amount_text,
          'advance_id',    NEW.id::text
        ),
        'hr_advance',
        NEW.id
      );
    END IF;

    -- ── UPDATE: status change → notify employee ──────────────────────────
    IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN

      IF NEW.status = 'approved' AND v_employee_profile IS NOT NULL THEN
        PERFORM public.call_dispatch_notification(
          'hr.advance.approved',
          ARRAY[v_employee_profile],
          jsonb_build_object(
            'amount',     v_amount_text,
            'advance_id', NEW.id::text
          ),
          'hr_advance',
          NEW.id
        );

      ELSIF NEW.status = 'rejected' AND v_employee_profile IS NOT NULL THEN
        PERFORM public.call_dispatch_notification(
          'hr.advance.rejected',
          ARRAY[v_employee_profile],
          jsonb_build_object(
            'amount',     v_amount_text,
            'reason',     COALESCE(NEW.rejection_reason, 'لم يُحدد سبب'),
            'advance_id', NEW.id::text
          ),
          'hr_advance',
          NEW.id
        );
      END IF;

    END IF;

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[notify_on_advance_change] non-critical: %', SQLERRM;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_advance_change ON public.hr_advances;
CREATE TRIGGER trg_notify_advance_change
  AFTER INSERT OR UPDATE OF status
  ON public.hr_advances
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_advance_change();


-- ─────────────────────────────────────────────────────────────────────────
-- 2.2  hr_permission_requests  →  requested / approved / rejected
--      SCHEMA-VERIFIED:
--        hr_permission_requests.employee_id → hr_employees.id ✓
--        hr_permission_requests.permission_date DATE            ✓
--        hr_permission_requests.reason TEXT NOT NULL            ✓
--        hr_permission_requests.rejection_reason TEXT           ✓
--        hr_permission_requests.status IN('pending','approved','rejected') ✓
--        No approved_by → profiles;  approved_by → hr_employees (ignored here)
-- ─────────────────────────────────────────────────────────────────────────
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

    -- ── INSERT: new request → notify all users with hr.attendance.approve ─
    IF TG_OP = 'INSERT' THEN
      SELECT ARRAY(
        SELECT DISTINCT p.id
        FROM   role_permissions rp
        JOIN   profiles p ON p.role_id = rp.role_id
        WHERE  rp.permission = 'hr.attendance.approve'
          AND  p.id <> COALESCE(v_employee_profile, gen_random_uuid())
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

DROP TRIGGER IF EXISTS trg_notify_permission_change ON public.hr_permission_requests;
CREATE TRIGGER trg_notify_permission_change
  AFTER INSERT OR UPDATE OF status
  ON public.hr_permission_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_permission_change();


-- ─────────────────────────────────────────────────────────────────────────
-- 2.3  hr_payroll_runs  →  status='paid'  — notify each employee
--      SCHEMA-VERIFIED:
--        hr_payroll_run_status ENUM: 'draft','calculating','review',
--                                   'approved','paid','cancelled'  ✓
--        hr_payroll_runs.period_id → hr_payroll_periods.id          ✓
--        hr_payroll_periods.year INTEGER, hr_payroll_periods.month INTEGER ✓
--        hr_payroll_lines.payroll_run_id → hr_payroll_runs.id        ✓
--        hr_payroll_lines.employee_id → hr_employees.id              ✓
--        hr_payroll_lines.net_salary NUMERIC                         ✓
--        hr_employees.user_id UUID                                   ✓
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_on_payroll_paid()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_line       RECORD;
  v_month_name text;
BEGIN
  -- Only trigger when moving to 'paid' (idempotent guard)
  IF NEW.status <> 'paid' OR OLD.status = 'paid' THEN
    RETURN NEW;
  END IF;

  BEGIN
    -- Build human-readable month name
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
        AND  he.user_id IS NOT NULL  -- skip employees without user accounts
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

DROP TRIGGER IF EXISTS trg_notify_payroll_paid ON public.hr_payroll_runs;
CREATE TRIGGER trg_notify_payroll_paid
  AFTER UPDATE OF status
  ON public.hr_payroll_runs
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_payroll_paid();


-- ─────────────────────────────────────────────────────────────────────────
-- 2.4  hr_attendance_days  →  INSERT with late_minutes > 5
--      Notifies the employee's direct manager.
--
--      SCHEMA-VERIFIED:
--        hr_attendance_days.late_minutes INTEGER DEFAULT 0     ✓
--        hr_attendance_days.shift_date DATE                    ✓
--        hr_attendance_days.employee_id → hr_employees.id      ✓
--        hr_employees.direct_manager_id → hr_employees.id      ✓ (not reporting_manager_id)
--        hr_employees.full_name TEXT                           ✓
--        hr_employees.user_id UUID                             ✓
--
--      NOTE: We do NOT filter on status='late' because:
--        - Status is computed by process_attendance_penalties (separate trigger)
--        - A record with late_minutes > 0 may have status='present' at INSERT time
--        - We rely solely on late_minutes > 5 for notification threshold
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_on_attendance_late()
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
  -- Guard: only fire for meaningful lateness
  IF COALESCE(NEW.late_minutes, 0) < 5 THEN
    RETURN NEW;
  END IF;

  BEGIN
    -- Resolve employee name + manager's profile
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
        'hr.attendance.late',
        ARRAY[v_manager_profile],
        jsonb_build_object(
          'employee_name', COALESCE(v_emp_name, 'موظف'),
          'minutes_late',  NEW.late_minutes::text,
          'date',          v_date_text,
          'employee_id',   NEW.employee_id::text
        ),
        'hr_attendance_day',
        NEW.id
      );
    END IF;

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[notify_on_attendance_late] non-critical: %', SQLERRM;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_attendance_late ON public.hr_attendance_days;
CREATE TRIGGER trg_notify_attendance_late
  AFTER INSERT
  ON public.hr_attendance_days
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_attendance_late();


-- ─────────────────────────────────────────────────────────────────────────
-- 2.5  sales_orders  →  status = 'confirmed'
--      Notifies: the sales rep + all users with sales.orders.read_all
--
--      SCHEMA-VERIFIED:
--        sales_orders.rep_id UUID → profiles.id                 ✓
--        sales_orders.created_by_id UUID → profiles.id          ✓
--        sales_orders.order_number TEXT                         ✓
--        sales_orders.total_amount NUMERIC                      ✓
--        sales_order_status ENUM includes 'confirmed'           ✓
--        customers.name TEXT                                    ✓
-- ─────────────────────────────────────────────────────────────────────────
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

    -- Build recipient array: rep + creator + all managers with read_all
    SELECT ARRAY(
      WITH reps AS (
        SELECT NEW.rep_id        AS id WHERE NEW.rep_id IS NOT NULL
        UNION ALL
        SELECT NEW.created_by_id AS id
          WHERE NEW.created_by_id IS NOT NULL
            AND NEW.created_by_id IS DISTINCT FROM NEW.rep_id
      ),
      managers AS (
        SELECT DISTINCT p.id
        FROM   role_permissions rp
        JOIN   profiles p ON p.role_id = rp.role_id
        WHERE  rp.permission = 'sales.orders.read_all'
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

DROP TRIGGER IF EXISTS trg_notify_sales_order_confirmed ON public.sales_orders;
CREATE TRIGGER trg_notify_sales_order_confirmed
  AFTER UPDATE OF status
  ON public.sales_orders
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_sales_order_confirmed();


-- ─────────────────────────────────────────────────────────────────────────
-- 2.6  purchase_invoices  →  received / billed
--      SCHEMA-VERIFIED:
--        purchase_invoices.status IN('draft','received','billed','paid','cancelled') ✓
--        purchase_invoices.number TEXT                         ✓
--        purchase_invoices.total_amount NUMERIC                ✓
--        purchase_invoices.supplier_id → suppliers.id         ✓
--        suppliers.name TEXT (in master data)                  ✓
-- ─────────────────────────────────────────────────────────────────────────
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
      SELECT ARRAY(
        SELECT DISTINCT p.id
        FROM   role_permissions rp
        JOIN   profiles p ON p.role_id = rp.role_id
        WHERE  rp.permission = 'procurement.invoices.bill'
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
      SELECT ARRAY(
        SELECT DISTINCT p.id
        FROM   role_permissions rp
        JOIN   profiles p ON p.role_id = rp.role_id
        WHERE  rp.permission = 'procurement.invoices.pay'
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

DROP TRIGGER IF EXISTS trg_notify_purchase_invoice ON public.purchase_invoices;
CREATE TRIGGER trg_notify_purchase_invoice
  AFTER UPDATE OF status
  ON public.purchase_invoices
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_purchase_invoice_change();


-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 3: CRON FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- 3.1  notify_absent_employees()
--      Scheduled daily at 14:00 UTC (≈ 16:00 Cairo)
--      Finds active employees with no hr_attendance_days for today,
--      not on approved leave, not on approved permission.
--
--      SCHEMA-VERIFIED:
--        hr_employees.status hr_employee_status ✓ ('active' ∈ enum)
--        hr_employees.direct_manager_id → hr_employees.id ✓
--        hr_leave_requests.start_date / end_date DATE ✓
--        hr_leave_requests.status ENUM includes 'approved' ✓
--        hr_permission_requests.permission_date DATE ✓
--        hr_attendance_days UNIQUE(employee_id, shift_date) ✓
--        is_employee_work_day() exists in migration 18 ✓
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_absent_employees()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp    RECORD;
  v_today  date    := CURRENT_DATE;
  v_count  integer := 0;
BEGIN
  FOR v_emp IN
    SELECT
      he.id         AS employee_id,
      he.full_name  AS emp_name,
      mgr.user_id   AS manager_profile
    FROM   hr_employees he
    LEFT JOIN hr_employees mgr ON mgr.id = he.direct_manager_id
    WHERE  he.status = 'active'

      -- Not on approved leave today
      AND NOT EXISTS (
        SELECT 1
        FROM   hr_leave_requests lr
        WHERE  lr.employee_id = he.id
          AND  lr.status IN ('approved_supervisor', 'approved_hr', 'approved')
          AND  v_today BETWEEN lr.start_date AND lr.end_date
      )

      -- Not on approved permission today
      AND NOT EXISTS (
        SELECT 1
        FROM   hr_permission_requests pr
        WHERE  pr.employee_id = he.id
          AND  pr.permission_date = v_today
          AND  pr.status = 'approved'
      )

      -- No attendance record at all for today
      AND NOT EXISTS (
        SELECT 1
        FROM   hr_attendance_days ad
        WHERE  ad.employee_id = he.id
          AND  ad.shift_date  = v_today
      )

      -- Only on actual workdays (not weekends / public holidays)
      AND public.is_employee_work_day(he.id, v_today) = 'work_day'
  LOOP
    BEGIN
      IF v_emp.manager_profile IS NOT NULL THEN
        PERFORM public.call_dispatch_notification(
          'hr.attendance.absent',
          ARRAY[v_emp.manager_profile],
          jsonb_build_object(
            'employee_name', v_emp.emp_name,
            'date',          to_char(v_today, 'YYYY-MM-DD'),
            'employee_id',   v_emp.employee_id::text
          ),
          'hr_attendance_day',
          NULL
        );
        v_count := v_count + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '[notify_absent_employees] employee % error: %',
                    v_emp.employee_id, SQLERRM;
    END;
  END LOOP;

  RAISE NOTICE '[notify_absent_employees] % notifications dispatched for %',
               v_count, v_today;
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_absent_employees() TO service_role;
REVOKE EXECUTE ON FUNCTION public.notify_absent_employees() FROM authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 3.2  notify_expiring_contracts()
--      Scheduled daily at 08:00 UTC (≈ 10:00 Cairo)
--      Reads hr_contracts.end_date (NOT hr_employees.contract_end_date
--      which does not exist). Notifies on days: 60, 30, 14, 7.
--
--      SCHEMA-VERIFIED:
--        hr_contracts.employee_id → hr_employees.id ✓
--        hr_contracts.end_date DATE (NULL = permanent) ✓
--        hr_employees.direct_manager_id ✓ (manager of employee)
--        NOTIFY HR managers via permission 'hr.employees.manage' ✓
-- ─────────────────────────────────────────────────────────────────────────
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
  -- Resolve HR manager profile IDs once
  SELECT ARRAY(
    SELECT DISTINCT p.id
    FROM   role_permissions rp
    JOIN   profiles p ON p.role_id = rp.role_id
    WHERE  rp.permission IN ('hr.employees.manage', 'hr.settings.update')
    LIMIT  15
  ) INTO v_hr_managers;

  IF v_hr_managers IS NULL OR array_length(v_hr_managers, 1) = 0 THEN
    RAISE NOTICE '[notify_expiring_contracts] no HR managers found — skipping';
    RETURN;
  END IF;

  -- Scan active contracts expiring on notification days
  -- Uses DISTINCT ON employee to get the latest contract
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
    ORDER BY he.id, c.start_date DESC  -- latest contract per employee
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


-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 4: CRON JOBS (pg_cron — already enabled)
-- ═══════════════════════════════════════════════════════════════════════════

-- Idempotent: unschedule before re-scheduling
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'notify-absent-employees') THEN
    PERFORM cron.unschedule('notify-absent-employees');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'notify-expiring-contracts') THEN
    PERFORM cron.unschedule('notify-expiring-contracts');
  END IF;
END $$;

-- Daily at 14:00 UTC (≈ 16:00 Cairo Standard Time — end of workday)
SELECT cron.schedule(
  'notify-absent-employees',
  '0 14 * * *',
  $$ SELECT public.notify_absent_employees(); $$
);

-- Daily at 08:00 UTC (≈ 10:00 Cairo — morning check)
SELECT cron.schedule(
  'notify-expiring-contracts',
  '0 8 * * *',
  $$ SELECT public.notify_expiring_contracts(); $$
);


-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 5: SECURITY — revoke execution from authenticated users
-- Trigger functions run automatically; no user should invoke them directly
-- ═══════════════════════════════════════════════════════════════════════════

REVOKE EXECUTE ON FUNCTION public.notify_on_advance_change()                FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_on_permission_change()             FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_on_payroll_paid()                  FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_on_attendance_late()               FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_on_sales_order_confirmed()         FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_on_purchase_invoice_change()       FROM authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 6: VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_event_count   integer;
  v_trigger_count integer;
  v_cron_count    integer;
BEGIN
  SELECT COUNT(*) INTO v_event_count
  FROM   public.notification_event_types
  WHERE  event_key IN (
    'hr.advance.requested', 'hr.advance.approved', 'hr.advance.rejected',
    'hr.permission.requested', 'hr.permission.approved', 'hr.permission.rejected',
    'hr.payroll.processed', 'hr.contract.expiring',
    'hr.attendance.late', 'hr.attendance.absent',
    'sales.order.confirmed',
    'purchase.invoice.received', 'purchase.invoice.billed'
  );

  SELECT COUNT(*) INTO v_trigger_count
  FROM   information_schema.triggers
  WHERE  trigger_name IN (
    'trg_notify_advance_change',
    'trg_notify_permission_change',
    'trg_notify_payroll_paid',
    'trg_notify_attendance_late',
    'trg_notify_sales_order_confirmed',
    'trg_notify_purchase_invoice'
  )
    AND  trigger_schema = 'public';

  SELECT COUNT(*) INTO v_cron_count
  FROM   cron.job
  WHERE  jobname IN ('notify-absent-employees', 'notify-expiring-contracts');

  RAISE NOTICE '══════════════════════════════════════════════';
  RAISE NOTICE '[46_notification_full_coverage] RESULT:';
  RAISE NOTICE '  ✅ Event keys  : %/13', v_event_count;
  RAISE NOTICE '  ✅ Triggers    : %/6',  v_trigger_count;
  RAISE NOTICE '  ✅ Cron jobs   : %/2',  v_cron_count;
  RAISE NOTICE '══════════════════════════════════════════════';

  IF v_event_count  < 13 THEN RAISE WARNING '  ⚠️  Missing event keys'; END IF;
  IF v_trigger_count < 6  THEN RAISE WARNING '  ⚠️  Missing triggers';   END IF;
  IF v_cron_count   < 2   THEN RAISE WARNING '  ⚠️  Missing cron jobs';  END IF;
END $$;
