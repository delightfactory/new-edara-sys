-- ═══════════════════════════════════════════════════════════════════════════
-- 52_notification_wave1a_events.sql
-- Wave 1A — Infrastructure + New Event Keys Registration
--
-- SCOPE:
--   1. notification_alert_state table (cron dedupe with cooldown)
--   2. INSERT new event_keys — all idempotent via ON CONFLICT DO NOTHING
--      (keys already seeded in 42/46 are naturally skipped)
--
-- WHAT IS NOT TOUCHED:
--   • No triggers added or modified
--   • No existing event_keys updated (DO NOTHING not DO UPDATE)
--   • No frontend changes (handled in Wave 1A-edge separately)
--
-- SAFETY:
--   ✅ Idempotent — safe to run multiple times
--   ✅ No business logic affected
--   ✅ Additive-only changes
--
-- VERIFIED EXISTING (DO NOTHING will skip silently):
--   hr.attendance.early_leave  → seeded in 42_notification_system.sql L615
--   sales.order.created        → seeded in 42_notification_system.sql L711
--   + all events from 42 and 46
--
-- TRULY NEW (not in any prior migration):
--   hr.payroll.ready_for_review
--   hr.adjustment.created / approved / rejected
--   finance.payment.received / confirmed / rejected
--   finance.custody.loaded
--   sales.order.delivered / cancelled
--   sales.return.created / confirmed
--   purchase.invoice.paid
--   purchase.return.confirmed
--   inventory.transfer.approved
--   inventory.adjustment.pending / approved
-- ═══════════════════════════════════════════════════════════════════════════


-- ────────────────────────────────────────────────────────────────────────────
-- PART 1: notification_alert_state — Cron Dedupe Table
-- Prevents cron jobs from sending spam for the same condition repeatedly.
-- Logic:
--   • alert_key = unique fingerprint per condition+entity
--   • resolved_at NULL  = alert still active
--   • resolved_at SET   = condition cleared (will re-alert if it recurs)
--   • cooldown_hours    = minimum interval between reminders (default 24h)
-- ────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS notification_alert_state (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_key      TEXT        NOT NULL,
  event_key      TEXT        NOT NULL,
  entity_type    TEXT,
  entity_id      UUID,
  last_sent_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at    TIMESTAMPTZ,                    -- NULL = still active
  send_count     INTEGER     NOT NULL DEFAULT 1,
  cooldown_hours INTEGER     NOT NULL DEFAULT 24,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT uq_nas_alert_key UNIQUE (alert_key)
);

CREATE INDEX IF NOT EXISTS idx_nas_event_key  ON notification_alert_state(event_key, resolved_at);
CREATE INDEX IF NOT EXISTS idx_nas_entity_id  ON notification_alert_state(entity_id, resolved_at);
CREATE INDEX IF NOT EXISTS idx_nas_last_sent  ON notification_alert_state(last_sent_at) WHERE resolved_at IS NULL;

COMMENT ON TABLE notification_alert_state IS
  'Deduplication state for cron-based notification alerts. '
  'Prevents repeated notifications for the same ongoing condition. '
  'Each unique condition gets one alert_key; reminders are rate-limited by cooldown_hours.';

COMMENT ON COLUMN notification_alert_state.alert_key IS
  'Unique fingerprint for a condition, e.g.: '
  '''inventory.stock.low::<product_id>::<warehouse_id>'' or '
  '''sales.invoice.overdue::<order_id>''';

COMMENT ON COLUMN notification_alert_state.resolved_at IS
  'Set when the condition clears (e.g., stock replenished, invoice paid). '
  'If the condition recurs, this is reset to NULL and a new alert fires.';

-- RLS: no direct user access needed — only accessed by SECURITY DEFINER functions
ALTER TABLE notification_alert_state ENABLE ROW LEVEL SECURITY;


-- ────────────────────────────────────────────────────────────────────────────
-- PART 2: Register new event_keys
-- All inserts use ON CONFLICT (event_key) DO NOTHING for full idempotency.
-- Events already seeded in migrations 42 and 46 are silently skipped.
-- ────────────────────────────────────────────────────────────────────────────

INSERT INTO public.notification_event_types (
  event_key, label_ar, label_en,
  category, default_priority,
  title_template, body_template,
  icon, action_url_template
) VALUES

  -- ── HR Payroll — Ready for Review ────────────────────────────────────────
  ('hr.payroll.ready_for_review',
   'كشف الرواتب جاهز للمراجعة', 'Payroll Ready for Review',
   'hr_payroll', 'high',
   'كشف الرواتب جاهز للمراجعة — {{month}}',
   'كشف رواتب {{month}} تم حسابه وجاهز للمراجعة والاعتماد. الإجمالي: {{total_net}} ج.م لـ {{employee_count}} موظف',
   'calculator', '/hr/payroll/{{payroll_run_id}}'),

  -- ── HR Payroll Adjustments ───────────────────────────────────────────────
  ('hr.adjustment.created',
   'تعديل راتب جديد', 'Payroll Adjustment Created',
   'hr_payroll', 'medium',
   'تعديل راتب يحتاج موافقتك',
   '{{requester_name}} أنشأ تعديل {{adjustment_type}} بمبلغ {{amount}} ج.م للموظف {{employee_name}}',
   'file-plus', '/hr/payroll/adjustments/{{adjustment_id}}'),

  ('hr.adjustment.approved',
   'تمت الموافقة على تعديل الراتب', 'Payroll Adjustment Approved',
   'hr_payroll', 'medium',
   'تمت الموافقة على تعديل راتبك',
   'تعديل {{adjustment_type}} بمبلغ {{amount}} ج.م تمت الموافقة عليه وسيُضاف للمسير القادم',
   'check-circle', '/hr/payroll/adjustments/{{adjustment_id}}'),

  ('hr.adjustment.rejected',
   'رُفض تعديل الراتب', 'Payroll Adjustment Rejected',
   'hr_payroll', 'medium',
   'رُفض تعديل راتبك',
   'تعديل {{adjustment_type}} بمبلغ {{amount}} ج.م تم رفضه',
   'x-circle', '/hr/payroll/adjustments/{{adjustment_id}}'),

  -- ── Finance — Payment Receipts ───────────────────────────────────────────
  ('finance.payment.received',
   'إيصال تحصيل جديد — يحتاج تأكيد', 'Payment Receipt — Pending Confirmation',
   'finance_approvals', 'high',
   'إيصال تحصيل يحتاج تأكيدك',
   '{{collector_name}} سجّل تحصيلاً بمبلغ {{amount}} ج.م من {{customer_name}} — طلب بيع #{{order_number}}',
   'banknote', '/finance/payments/{{receipt_id}}'),

  ('finance.payment.confirmed',
   'تم تأكيد إيصال التحصيل', 'Payment Receipt Confirmed',
   'finance_expenses', 'medium',
   'تم تأكيد إيصال تحصيلك',
   'الإيصال بمبلغ {{amount}} ج.م من {{customer_name}} تم تأكيده بنجاح',
   'check-circle', '/finance/payments/{{receipt_id}}'),

  ('finance.payment.rejected',
   'رُفض إيصال التحصيل', 'Payment Receipt Rejected',
   'finance_expenses', 'high',
   'رُفض إيصال التحصيل',
   'الإيصال بمبلغ {{amount}} ج.م من {{customer_name}} رُفض. السبب: {{reason}}',
   'x-circle', '/finance/payments/{{receipt_id}}'),

  -- ── Finance — Custody ────────────────────────────────────────────────────
  ('finance.custody.loaded',
   'تم تحميل العهدة', 'Custody Loaded',
   'finance_expenses', 'medium',
   'تم تحميل عهدتك',
   'تم إضافة {{amount}} ج.م لعهدتك. الرصيد الحالي: {{balance}} ج.م',
   'wallet', '/finance/custody/{{custody_id}}'),

  -- ── Sales — Order Lifecycle ──────────────────────────────────────────────
  ('sales.order.delivered',
   'تم تسليم طلب البيع', 'Sales Order Delivered',
   'sales', 'medium',
   'تم تسليم الطلب #{{order_number}}',
   'طلب البيع #{{order_number}} للعميل {{customer_name}} بقيمة {{amount}} ج.م تم تسليمه بنجاح',
   'package-check', '/sales/orders/{{order_id}}'),

  ('sales.order.cancelled',
   'تم إلغاء طلب البيع', 'Sales Order Cancelled',
   'sales', 'high',
   'تم إلغاء الطلب #{{order_number}}',
   'طلب البيع #{{order_number}} للعميل {{customer_name}} تم إلغاؤه',
   'shopping-cart', '/sales/orders/{{order_id}}'),

  -- ── Sales — Returns ──────────────────────────────────────────────────────
  ('sales.return.created',
   'مرتجع مبيعات جديد', 'Sales Return Created',
   'sales', 'high',
   'مرتجع مبيعات يحتاج تأكيدك',
   'مرتجع جديد #{{return_number}} بقيمة {{amount}} ج.م من العميل {{customer_name}}',
   'package', '/sales/returns/{{return_id}}'),

  ('sales.return.confirmed',
   'تم تأكيد مرتجع المبيعات', 'Sales Return Confirmed',
   'sales', 'medium',
   'تم تأكيد المرتجع #{{return_number}}',
   'مرتجع المبيعات #{{return_number}} بقيمة {{amount}} ج.م تم تأكيده وقُيّد في المخزن',
   'package-check', '/sales/returns/{{return_id}}'),

  -- ── Procurement — Invoice Paid ───────────────────────────────────────────
  ('purchase.invoice.paid',
   'تم سداد فاتورة الشراء', 'Purchase Invoice Paid',
   'procurement', 'medium',
   'تم سداد الفاتورة #{{invoice_number}}',
   'فاتورة الشراء #{{invoice_number}} من {{supplier_name}} بقيمة {{amount}} ج.م تم سدادها بالكامل',
   'receipt', '/procurement/invoices/{{invoice_id}}'),

  -- ── Procurement — Return Confirmed ───────────────────────────────────────
  ('purchase.return.confirmed',
   'تم تأكيد مرتجع المشتريات', 'Purchase Return Confirmed',
   'procurement', 'medium',
   'تم تأكيد مرتجع المشتريات #{{return_number}}',
   'مرتجع المشتريات #{{return_number}} للمورد {{supplier_name}} بقيمة {{amount}} ج.م تم تأكيده',
   'package', '/procurement/returns/{{return_id}}'),

  -- ── Inventory — Transfer Approved ────────────────────────────────────────
  ('inventory.transfer.approved',
   'تمت الموافقة على التحويل', 'Transfer Approved',
   'inventory', 'medium',
   'تمت الموافقة على طلب التحويل',
   'طلب تحويل {{quantity}} {{unit}} من {{product_name}} تمت الموافقة عليه وجاري الشحن',
   'package', '/inventory/transfers/{{transfer_id}}'),

  -- ── Inventory — Adjustments ──────────────────────────────────────────────
  ('inventory.adjustment.pending',
   'تسوية مخزون تنتظر اعتمادك', 'Stock Adjustment Pending Approval',
   'inventory', 'high',
   'تسوية مخزون تحتاج اعتمادك',
   'تسوية مخزون جديدة #{{adjustment_number}} في مخزن {{warehouse_name}} تنتظر اعتمادك',
   'clipboard-list', '/inventory/adjustments/{{adjustment_id}}'),

  ('inventory.adjustment.approved',
   'تمت الموافقة على تسوية المخزون', 'Stock Adjustment Approved',
   'inventory', 'low',
   'تمت الموافقة على تسوية المخزون',
   'تسوية المخزون #{{adjustment_number}} تمت الموافقة عليها وطُبِّقت على الأرصدة',
   'clipboard-check', '/inventory/adjustments/{{adjustment_id}}')

ON CONFLICT (event_key) DO NOTHING;
-- ↑ DO NOTHING: if the event_key already exists (from any prior migration), skip silently.
-- This makes the migration fully idempotent regardless of execution order.


-- ────────────────────────────────────────────────────────────────────────────
-- VERIFICATION
-- ────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_new_events_count  INTEGER;
  v_alert_table_exists BOOLEAN;
BEGIN
  -- Check alert state table
  SELECT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'notification_alert_state'
  ) INTO v_alert_table_exists;

  -- Count our new keys (subset — truly new ones)
  SELECT COUNT(*) INTO v_new_events_count
  FROM public.notification_event_types
  WHERE event_key IN (
    'hr.payroll.ready_for_review',
    'hr.adjustment.created', 'hr.adjustment.approved', 'hr.adjustment.rejected',
    'finance.payment.received', 'finance.payment.confirmed', 'finance.payment.rejected',
    'finance.custody.loaded',
    'sales.order.delivered', 'sales.order.cancelled',
    'sales.return.created', 'sales.return.confirmed',
    'purchase.invoice.paid', 'purchase.return.confirmed',
    'inventory.transfer.approved',
    'inventory.adjustment.pending', 'inventory.adjustment.approved'
  );

  RAISE NOTICE '══════════════════════════════════════════════════════';
  RAISE NOTICE '[52_wave1a_events] VERIFICATION:';
  RAISE NOTICE '  notification_alert_state table: %', CASE WHEN v_alert_table_exists THEN '✅ exists' ELSE '❌ missing' END;
  RAISE NOTICE '  New event_keys registered: % / 17', v_new_events_count;

  IF NOT v_alert_table_exists THEN
    RAISE WARNING '[52_wave1a_events] ⚠️  alert state table missing';
  END IF;

  IF v_new_events_count < 17 THEN
    RAISE WARNING '[52_wave1a_events] ⚠️  Expected 17 new events, found %', v_new_events_count;
  ELSE
    RAISE NOTICE '  ✅ Wave 1A-sql complete — no triggers touched';
  END IF;

  RAISE NOTICE '══════════════════════════════════════════════════════';
END $$;
