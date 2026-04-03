-- 56_fix_notification_templates_and_routes.sql
--
-- Purpose:
--   1. Fix notification_event_types template/body mismatches introduced by
--      newer trigger payloads in Waves 1B/1C/2.
--   2. Fix action_url_template values that point to non-existent routes.
--   3. Repair existing notifications.action_url rows for known broken routes,
--      so already-created notifications stop sending users to 404 pages.
--
-- Root causes observed in production smoke tests:
--   - Some event templates expect variables that triggers never send
--     (for example inventory.transfer.requested expected requester_name/quantity
--      while the trigger sends transfer_number/from_warehouse/to_warehouse).
--   - Some older templates still point to legacy routes:
--       /procurement/...              -> app uses /purchases/...
--       /finance/custody/:id          -> app only has /finance/custody
--       /hr/payroll/adjustments/:id   -> app only has /hr/adjustments
--       /sales/invoices/:id           -> app has /sales/orders/:id
--       /inventory/products/:id       -> current low-stock flow is better sent to /inventory/stock
--
-- Safety:
--   - Pure UPDATE migration
--   - Idempotent
--   - No trigger/function logic changed

-- ---------------------------------------------------------------------------
-- 1) Future notifications: align templates with actual trigger payloads
-- ---------------------------------------------------------------------------

UPDATE public.notification_event_types
SET
  body_template = '{{collector_name}} سجّل تحصيلاً بمبلغ {{amount}} من {{customer_name}}',
  updated_at = now()
WHERE event_key = 'finance.payment.received';

UPDATE public.notification_event_types
SET
  body_template = 'الإيصال بمبلغ {{amount}} من {{customer_name}} تم تأكيده بنجاح',
  updated_at = now()
WHERE event_key = 'finance.payment.confirmed';

UPDATE public.notification_event_types
SET
  body_template = 'الإيصال بمبلغ {{amount}} من {{customer_name}} رُفض. السبب: {{reason}}',
  updated_at = now()
WHERE event_key = 'finance.payment.rejected';

UPDATE public.notification_event_types
SET
  body_template = 'تم إضافة {{amount}} لعهدتك. الرصيد الحالي: {{balance}}',
  action_url_template = '/finance/custody',
  updated_at = now()
WHERE event_key = 'finance.custody.loaded';

UPDATE public.notification_event_types
SET
  body_template = 'طلب جديد من {{customer_name}} بقيمة {{amount}}',
  updated_at = now()
WHERE event_key = 'sales.order.created';

UPDATE public.notification_event_types
SET
  body_template = 'طلب البيع #{{order_number}} لعميل {{customer_name}} بقيمة {{amount}} تم تأكيده',
  updated_at = now()
WHERE event_key = 'sales.order.confirmed';

UPDATE public.notification_event_types
SET
  body_template = 'طلب البيع #{{order_number}} للعميل {{customer_name}} بقيمة {{amount}} تم تسليمه بنجاح',
  updated_at = now()
WHERE event_key = 'sales.order.delivered';

UPDATE public.notification_event_types
SET
  body_template = 'كشف رواتب {{month}} تم حسابه وجاهز للمراجعة والاعتماد. الإجمالي: {{total_net}} لـ {{employee_count}} موظف',
  updated_at = now()
WHERE event_key = 'hr.payroll.ready_for_review';

UPDATE public.notification_event_types
SET
  body_template = '{{requester_name}} أنشأ تعديل {{adjustment_type}} بمبلغ {{amount}} للموظف {{employee_name}}',
  action_url_template = '/hr/adjustments',
  updated_at = now()
WHERE event_key = 'hr.adjustment.created';

UPDATE public.notification_event_types
SET
  body_template = 'تعديل {{adjustment_type}} بمبلغ {{amount}} تمت الموافقة عليه وسيُضاف للمسير القادم',
  action_url_template = '/hr/adjustments',
  updated_at = now()
WHERE event_key = 'hr.adjustment.approved';

UPDATE public.notification_event_types
SET
  body_template = 'تعديل {{adjustment_type}} بمبلغ {{amount}} تم رفضه',
  action_url_template = '/hr/adjustments',
  updated_at = now()
WHERE event_key = 'hr.adjustment.rejected';

UPDATE public.notification_event_types
SET
  body_template = 'فاتورة الشراء #{{invoice_number}} من {{supplier_name}} بقيمة {{amount}} تم استلامها',
  action_url_template = '/purchases/invoices/{{invoice_id}}',
  updated_at = now()
WHERE event_key = 'purchase.invoice.received';

UPDATE public.notification_event_types
SET
  body_template = 'فاتورة الشراء #{{invoice_number}} من {{supplier_name}} بقيمة {{amount}} أصبحت جاهزة للسداد',
  action_url_template = '/purchases/invoices/{{invoice_id}}',
  updated_at = now()
WHERE event_key = 'purchase.invoice.billed';

UPDATE public.notification_event_types
SET
  body_template = 'فاتورة الشراء #{{invoice_number}} من {{supplier_name}} بقيمة {{amount}} تم سدادها بالكامل',
  action_url_template = '/purchases/invoices/{{invoice_id}}',
  updated_at = now()
WHERE event_key = 'purchase.invoice.paid';

UPDATE public.notification_event_types
SET
  body_template = 'مرتجع المشتريات #{{return_number}} للمورد {{supplier_name}} بقيمة {{amount}} تم تأكيده',
  action_url_template = '/purchases/returns/{{return_id}}',
  updated_at = now()
WHERE event_key = 'purchase.return.confirmed';

UPDATE public.notification_event_types
SET
  body_template = 'طلب تحويل {{transfer_number}} من {{from_warehouse}} إلى {{to_warehouse}} ينتظر موافقتك',
  updated_at = now()
WHERE event_key = 'inventory.transfer.requested';

UPDATE public.notification_event_types
SET
  body_template = 'تمت الموافقة على التحويل {{transfer_number}} من {{from_warehouse}} إلى {{to_warehouse}} وجارٍ تجهيزه',
  updated_at = now()
WHERE event_key = 'inventory.transfer.approved';

UPDATE public.notification_event_types
SET
  title_template = 'تم استلام التحويل {{transfer_number}} بالكامل',
  body_template = 'تحويل المخزون {{transfer_number}} تم استلامه في {{to_warehouse}} بنجاح',
  updated_at = now()
WHERE event_key = 'inventory.transfer.completed';

UPDATE public.notification_event_types
SET
  body_template = '{{product_name}} في {{warehouse_name}} وصل إلى {{available_qty}} (الحد الأدنى {{min_stock_level}})',
  action_url_template = '/inventory/stock',
  updated_at = now()
WHERE event_key = 'inventory.stock.low';

UPDATE public.notification_event_types
SET
  body_template = 'نفد مخزون {{product_name}} في {{warehouse_name}} تمامًا',
  action_url_template = '/inventory/stock',
  updated_at = now()
WHERE event_key = 'inventory.stock.out';

UPDATE public.notification_event_types
SET
  body_template = 'طلب البيع #{{order_number}} للعميل {{customer_name}} متأخر السداد. الرصيد المتبقي {{outstanding}} وتاريخ الاستحقاق {{due_date}}',
  action_url_template = '/sales/orders/{{order_id}}',
  updated_at = now()
WHERE event_key = 'sales.invoice.overdue';

-- Optional/rare events whose old links point to routes that do not exist.
UPDATE public.notification_event_types
SET
  action_url_template = NULL,
  updated_at = now()
WHERE event_key = 'finance.budget.alert';

UPDATE public.notification_event_types
SET
  action_url_template = NULL,
  updated_at = now()
WHERE event_key = 'system.login.new_device';


-- ---------------------------------------------------------------------------
-- 2) Existing notifications: repair broken deep links already stored in rows
-- ---------------------------------------------------------------------------

UPDATE public.notifications
SET action_url = REPLACE(action_url, '/procurement/invoices/', '/purchases/invoices/')
WHERE action_url LIKE '/procurement/invoices/%';

UPDATE public.notifications
SET action_url = REPLACE(action_url, '/procurement/returns/', '/purchases/returns/')
WHERE action_url LIKE '/procurement/returns/%';

UPDATE public.notifications
SET action_url = '/finance/custody'
WHERE event_key = 'finance.custody.loaded'
  AND action_url LIKE '/finance/custody/%';

UPDATE public.notifications
SET action_url = '/hr/adjustments'
WHERE event_key IN ('hr.adjustment.created', 'hr.adjustment.approved', 'hr.adjustment.rejected')
  AND action_url LIKE '/hr/payroll/adjustments/%';

UPDATE public.notifications
SET action_url = '/inventory/stock'
WHERE event_key IN ('inventory.stock.low', 'inventory.stock.out')
  AND (
    action_url LIKE '/inventory/products/%'
    OR action_url LIKE '/products/%{{%'
    OR action_url LIKE '%{{%'
  );

UPDATE public.notifications
SET action_url = CASE
  WHEN entity_id IS NOT NULL THEN '/sales/orders/' || entity_id::text
  ELSE '/sales/orders'
END
WHERE event_key = 'sales.invoice.overdue'
  AND (
    action_url = '/sales/orders'
    OR action_url LIKE '/sales/invoices/%'
    OR action_url LIKE '%{{%'
  );

UPDATE public.notifications
SET action_url = '/hr/payroll'
WHERE event_key = 'hr.payroll.processed'
  AND action_url LIKE '/hr/payslips/%';

UPDATE public.notifications
SET action_url = NULL
WHERE event_key = 'finance.budget.alert'
  AND action_url LIKE '/finance/budgets/%';

UPDATE public.notifications
SET action_url = NULL
WHERE event_key = 'system.login.new_device'
  AND action_url = '/settings/security';


-- ---------------------------------------------------------------------------
-- 3) Verification
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_templates integer;
  v_links     integer;
BEGIN
  SELECT count(*)
  INTO v_templates
  FROM public.notification_event_types
  WHERE event_key IN (
    'finance.payment.received',
    'finance.payment.confirmed',
    'finance.payment.rejected',
    'finance.custody.loaded',
    'sales.order.created',
    'sales.order.confirmed',
    'sales.order.delivered',
    'sales.invoice.overdue',
    'purchase.invoice.received',
    'purchase.invoice.billed',
    'purchase.invoice.paid',
    'purchase.return.confirmed',
    'hr.adjustment.created',
    'hr.adjustment.approved',
    'hr.adjustment.rejected',
    'hr.payroll.ready_for_review',
    'inventory.transfer.requested',
    'inventory.transfer.approved',
    'inventory.transfer.completed',
    'inventory.stock.low',
    'inventory.stock.out',
    'finance.budget.alert',
    'system.login.new_device'
  );

  SELECT count(*)
  INTO v_links
  FROM public.notifications
  WHERE action_url LIKE '/purchases/%'
     OR action_url = '/finance/custody'
     OR action_url = '/hr/adjustments'
     OR action_url = '/inventory/stock'
     OR action_url LIKE '/sales/orders/%';

  RAISE NOTICE '[56_fix_notification_templates_and_routes] updated template rows: %, repaired notification links observed: %',
    v_templates, v_links;
END $$;
