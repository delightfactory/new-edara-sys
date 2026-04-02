-- ═══════════════════════════════════════════════════════════════
-- 51_fix_notification_action_urls.sql
--
-- Fix broken action_url_template values that navigate to
-- non-existent routes. All templates corrected to point to
-- actually registered React Router paths.
--
-- Changes:
--   hr.leave.*           → /hr/leaves  (no detail page exists)
--   finance.expense.*    → /finance/expenses
--   finance.budget.alert → /finance/expenses
--   hr.advance.*         → /hr/advances
--   hr.permission.*      → /hr/permissions
--   hr.payroll.processed → /hr/payroll  (payslips route doesn't exist)
--   inventory.stock.*    → /products/{{product_id}}
--   purchase.invoice.*   → /purchases/invoices/{{invoice_id}}
--   sales.invoice.overdue → /sales/orders
-- ═══════════════════════════════════════════════════════════════

-- ── HR Leaves: /hr/leaves/:id doesn't exist → fallback to /hr/leaves ──
UPDATE notification_event_types
SET action_url_template = '/hr/leaves', updated_at = now()
WHERE event_key IN ('hr.leave.requested', 'hr.leave.approved', 'hr.leave.rejected')
  AND action_url_template LIKE '%/hr/leaves/{{%';

-- ── Finance Expenses: /finance/expenses/:id doesn't exist ──
UPDATE notification_event_types
SET action_url_template = '/finance/expenses', updated_at = now()
WHERE event_key IN ('finance.expense.submitted', 'finance.expense.approved', 'finance.expense.rejected')
  AND action_url_template LIKE '%/finance/expenses/{{%';

-- ── Finance Budget Alert: /finance/budgets doesn't exist ──
UPDATE notification_event_types
SET action_url_template = '/finance/expenses', updated_at = now()
WHERE event_key = 'finance.budget.alert';

-- ── HR Advances: /hr/advances/:id doesn't exist ──
UPDATE notification_event_types
SET action_url_template = '/hr/advances', updated_at = now()
WHERE event_key IN ('hr.advance.requested', 'hr.advance.approved', 'hr.advance.rejected')
  AND action_url_template LIKE '%/hr/advances/{{%';

-- ── HR Permissions: /hr/permissions/:id doesn't exist ──
UPDATE notification_event_types
SET action_url_template = '/hr/permissions', updated_at = now()
WHERE event_key IN ('hr.permission.requested', 'hr.permission.approved', 'hr.permission.rejected')
  AND action_url_template LIKE '%/hr/permissions/{{%';

-- ── HR Payroll: /hr/payslips doesn't exist → use /hr/payroll ──
UPDATE notification_event_types
SET action_url_template = '/hr/payroll', updated_at = now()
WHERE event_key = 'hr.payroll.processed';

-- ── Inventory Stock: /inventory/products doesn't exist → /products/:id ──
UPDATE notification_event_types
SET action_url_template = '/products/{{product_id}}', updated_at = now()
WHERE event_key IN ('inventory.stock.low', 'inventory.stock.out')
  AND action_url_template LIKE '%/inventory/products/{{%';

-- ── Purchase invoices: /procurement/invoices → /purchases/invoices ──
UPDATE notification_event_types
SET action_url_template = '/purchases/invoices/{{invoice_id}}', updated_at = now()
WHERE event_key IN ('purchase.invoice.received', 'purchase.invoice.billed')
  AND action_url_template LIKE '%/procurement/invoices/{{%';

-- ── Sales invoice overdue: /sales/invoices doesn't exist ──
UPDATE notification_event_types
SET action_url_template = '/sales/orders', updated_at = now()
WHERE event_key = 'sales.invoice.overdue'
  AND action_url_template LIKE '%/sales/invoices/{{%';

-- ── HR Contract Expiring: /hr/employees/:id exists ✓ ── (no change needed)

-- ── HR Attendance: ?date= parameter routes work ✓ ── (no change needed)

-- ── Sales orders: /sales/orders/:id exists ✓ ── (no change needed)

-- ── Inventory transfers: /inventory/transfers/:id exists ✓ ── (no change needed)

-- ── System: NULL or /settings/security — fine ── (no change needed)

-- ── Verification ──
DO $$
DECLARE
  v_fixed integer;
BEGIN
  SELECT COUNT(*) INTO v_fixed
  FROM notification_event_types
  WHERE action_url_template NOT LIKE '%{{%'
    AND action_url_template IS NOT NULL;

  RAISE NOTICE '[51_fix_notification_action_urls] ✅ Fixed URL templates. % static routes now', v_fixed;
END $$;
