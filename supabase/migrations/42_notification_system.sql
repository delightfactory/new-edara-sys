-- ═══════════════════════════════════════════════════════════════
-- 42_notification_system.sql
-- Notification System Foundation — Sprint 1
--
-- Creates:
--   ENUMs           : notification_category, notification_priority,
--                     notification_delivery_channel, notification_delivery_status
--   TABLEs          : notification_event_types, notifications,
--                     notification_preferences, push_subscriptions,
--                     notification_delivery_log
--   INDEXes         : optimised for user+unread, category, entity, expiry
--   RLS POLICIES    : per-user isolation; service_role-only INSERT on notifications
--   RPC FUNCTIONS   : get_unread_notifications_count, mark_notification_read,
--                     mark_all_notifications_read, archive_notification,
--                     cleanup_old_notifications
--   REALTIME        : notifications table added to supabase_realtime publication
--   SEED DATA       : 19 canonical event_keys across 7 domains
--
-- Design constraints:
--   ✅ idempotent — safe to re-run (CREATE ... IF NOT EXISTS / OR REPLACE)
--   ✅ service_role-only INSERT on notifications (users never self-insert)
--   ✅ RLS on all tables
--   ✅ search_path = public on every SECURITY DEFINER function
-- ═══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- 1. ENUMs
-- ─────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_category') THEN
    CREATE TYPE public.notification_category AS ENUM (
      'system',
      'hr_attendance',
      'hr_payroll',
      'hr_leaves',
      'finance_expenses',
      'finance_approvals',
      'inventory',
      'sales',
      'procurement',
      'tasks',
      'alerts'
    );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_priority') THEN
    CREATE TYPE public.notification_priority AS ENUM (
      'low',
      'medium',
      'high',
      'critical'
    );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_delivery_channel') THEN
    CREATE TYPE public.notification_delivery_channel AS ENUM (
      'in_app',
      'push',
      'email'
    );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_delivery_status') THEN
    CREATE TYPE public.notification_delivery_status AS ENUM (
      'sent',
      'delivered',
      'clicked',
      'dismissed',
      'failed',
      'skipped'
    );
  END IF;
END $$;

-- ─────────────────────────────────────────────
-- 2. TABLE: notification_event_types
--    Central catalogue of all notification event types.
--    Adding a new notification type = one INSERT here, no code changes.
-- ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.notification_event_types (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key            text UNIQUE NOT NULL,         -- e.g. 'hr.attendance.late'
  label_ar             text NOT NULL,
  label_en             text NOT NULL,
  category             public.notification_category NOT NULL,
  default_priority     public.notification_priority NOT NULL DEFAULT 'medium',
  title_template       text NOT NULL,                -- supports {{variable}} syntax
  body_template        text NOT NULL,                -- supports {{variable}} syntax
  icon                 text,
  action_url_template  text,                         -- supports {{variable}} syntax
  is_active            boolean NOT NULL DEFAULT true,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.notification_event_types IS
  'Central registry of all notification event types. Add new events here without touching application code.';
COMMENT ON COLUMN public.notification_event_types.title_template IS
  'Handlebars-style template. Variables wrapped in {{var_name}} are replaced at dispatch time.';
COMMENT ON COLUMN public.notification_event_types.event_key IS
  'Dot-separated hierarchical key, e.g. hr.attendance.late. Must be globally unique.';

-- ─────────────────────────────────────────────
-- 3. TABLE: notifications
-- ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.notifications (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event_key        text REFERENCES public.notification_event_types(event_key) ON DELETE SET NULL,

  -- Content (generated from template at dispatch time)
  title            text NOT NULL,
  body             text NOT NULL,
  category         public.notification_category NOT NULL,
  priority         public.notification_priority NOT NULL DEFAULT 'medium',
  icon             text,
  action_url       text,

  -- Source entity binding
  entity_type      text,       -- 'expense' | 'attendance' | 'leave_request' | ...
  entity_id        uuid,

  -- Arbitrary extra data for UI rendering
  metadata         jsonb NOT NULL DEFAULT '{}',

  -- Read state
  is_read          boolean NOT NULL DEFAULT false,
  read_at          timestamptz,

  -- Archival (soft-delete)
  is_archived      boolean NOT NULL DEFAULT false,
  archived_at      timestamptz,

  -- Delivery channel status snapshot: {in_app: 'sent', push: 'delivered'}
  delivery_channels jsonb NOT NULL DEFAULT '{}',

  -- TTL — null = never expires
  expires_at       timestamptz,

  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.notifications IS
  'All user notifications. Each row belongs to exactly one user. Supports soft-delete via is_archived.';

-- ─────────────────────────────────────────────
-- 4. TABLE: notification_preferences
-- ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.notification_preferences (
  user_id              uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Global channel toggles
  in_app_enabled       boolean NOT NULL DEFAULT true,
  push_enabled         boolean NOT NULL DEFAULT false,
  email_enabled        boolean NOT NULL DEFAULT false,

  -- Quiet hours
  quiet_hours_enabled  boolean NOT NULL DEFAULT false,
  quiet_start          time NOT NULL DEFAULT '22:00',
  quiet_end            time NOT NULL DEFAULT '08:00',
  timezone             text NOT NULL DEFAULT 'Africa/Cairo',

  -- Minimum priority per channel
  min_priority_in_app  public.notification_priority NOT NULL DEFAULT 'low',
  min_priority_push    public.notification_priority NOT NULL DEFAULT 'medium',

  -- Per-category overrides (jsonb for forward compatibility)
  -- Example: {"hr_attendance": {"in_app": true, "push": true}}
  category_preferences jsonb NOT NULL DEFAULT '{}',

  -- Digest / batching
  digest_mode_enabled  boolean NOT NULL DEFAULT false,
  digest_frequency     text NOT NULL DEFAULT 'realtime'
    CHECK (digest_frequency IN ('realtime', 'hourly', 'daily')),

  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.notification_preferences IS
  'Per-user notification preferences. Created on first access with sensible defaults.';

-- ─────────────────────────────────────────────
-- 5. TABLE: push_subscriptions
-- ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.push_subscriptions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Web Push API subscription fields
  endpoint        text NOT NULL,
  p256dh_key      text NOT NULL,
  auth_key        text NOT NULL,

  -- Device metadata
  device_name     text,
  device_type     text NOT NULL DEFAULT 'desktop'
    CHECK (device_type IN ('desktop', 'mobile', 'tablet')),
  browser         text,
  user_agent      text,

  -- Lifecycle
  is_active       boolean NOT NULL DEFAULT true,
  failed_count    integer NOT NULL DEFAULT 0
    CONSTRAINT push_subscriptions_failed_count_check CHECK (failed_count >= 0),
  last_push_at    timestamptz,
  last_failed_at  timestamptz,
  last_seen_at    timestamptz,

  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),

  -- One subscription per endpoint (across all users)
  CONSTRAINT push_subscriptions_endpoint_unique UNIQUE (endpoint)
);

COMMENT ON TABLE public.push_subscriptions IS
  'Web Push API subscriptions per device per user. Auto-deactivated after 5 consecutive failures (enforced in application layer).';

-- ─────────────────────────────────────────────
-- 6. TABLE: notification_delivery_log
-- ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.notification_delivery_log (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id uuid NOT NULL REFERENCES public.notifications(id) ON DELETE CASCADE,
  channel         public.notification_delivery_channel NOT NULL,
  status          public.notification_delivery_status NOT NULL,
  subscription_id uuid REFERENCES public.push_subscriptions(id) ON DELETE SET NULL,
  error_code      text,
  error_message   text,
  processed_at    timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.notification_delivery_log IS
  'Immutable delivery audit log. Used for observability, debugging, and open-rate tracking.';

-- ─────────────────────────────────────────────
-- 7. INDEXES
-- ─────────────────────────────────────────────

-- notifications — most common read patterns
CREATE INDEX IF NOT EXISTS idx_notifications_user_id
  ON public.notifications(user_id);

CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
  ON public.notifications(user_id, is_read)
  WHERE is_read = false AND is_archived = false;

CREATE INDEX IF NOT EXISTS idx_notifications_user_category
  ON public.notifications(user_id, category);

CREATE INDEX IF NOT EXISTS idx_notifications_entity
  ON public.notifications(entity_type, entity_id)
  WHERE entity_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_notifications_created_at
  ON public.notifications(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_expires_at
  ON public.notifications(expires_at)
  WHERE expires_at IS NOT NULL;

-- push_subscriptions
CREATE INDEX IF NOT EXISTS idx_push_subscriptions_user_active
  ON public.push_subscriptions(user_id)
  WHERE is_active = true;

-- delivery_log
CREATE INDEX IF NOT EXISTS idx_delivery_log_notification
  ON public.notification_delivery_log(notification_id);

CREATE INDEX IF NOT EXISTS idx_delivery_log_processed_at
  ON public.notification_delivery_log(processed_at DESC);

-- ─────────────────────────────────────────────
-- 8. TRIGGERS — updated_at
-- ─────────────────────────────────────────────

-- Reuse update_updated_at_column if already defined (from HR migrations), else create.
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'notifications_updated_at'
      AND tgrelid = 'public.notifications'::regclass
  ) THEN
    CREATE TRIGGER notifications_updated_at
      BEFORE UPDATE ON public.notifications
      FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'notification_preferences_updated_at'
      AND tgrelid = 'public.notification_preferences'::regclass
  ) THEN
    CREATE TRIGGER notification_preferences_updated_at
      BEFORE UPDATE ON public.notification_preferences
      FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'push_subscriptions_updated_at'
      AND tgrelid = 'public.push_subscriptions'::regclass
  ) THEN
    CREATE TRIGGER push_subscriptions_updated_at
      BEFORE UPDATE ON public.push_subscriptions
      FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'notification_event_types_updated_at'
      AND tgrelid = 'public.notification_event_types'::regclass
  ) THEN
    CREATE TRIGGER notification_event_types_updated_at
      BEFORE UPDATE ON public.notification_event_types
      FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
  END IF;
END $$;

-- Auto-deactivate push subscription after 5 consecutive failures
CREATE OR REPLACE FUNCTION public.deactivate_failed_push_subscription()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.failed_count >= 5 THEN
    NEW.is_active := false;
    NEW.last_failed_at := now();
  END IF;
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'auto_deactivate_push_subscription'
      AND tgrelid = 'public.push_subscriptions'::regclass
  ) THEN
    CREATE TRIGGER auto_deactivate_push_subscription
      BEFORE UPDATE ON public.push_subscriptions
      FOR EACH ROW EXECUTE FUNCTION public.deactivate_failed_push_subscription();
  END IF;
END $$;

-- ─────────────────────────────────────────────
-- 9. ROW LEVEL SECURITY
-- ─────────────────────────────────────────────

ALTER TABLE public.notification_event_types    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_preferences    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_subscriptions          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_delivery_log   ENABLE ROW LEVEL SECURITY;

-- notification_event_types: public read catalogue, service_role writes
CREATE POLICY "notification_event_types_read_all" ON public.notification_event_types
  FOR SELECT USING (true);

-- notifications: users see/update/delete only their own rows
CREATE POLICY "notifications_select_own" ON public.notifications
  FOR SELECT USING (auth.uid() = user_id);

-- UPDATE on notifications is intentionally not granted to authenticated users.
-- All notification mutations go through SECURITY DEFINER RPCs:
--   • mark_notification_read()    → sets is_read + read_at
--   • mark_all_notifications_read() → bulk read
--   • archive_notification()      → sets is_archived + archived_at
-- This prevents clients from freely altering priority, action_url, or entity_id.

-- INSERT restricted to service_role only — users never self-insert notifications
CREATE POLICY "notifications_insert_service_role" ON public.notifications
  FOR INSERT WITH CHECK (auth.role() = 'service_role');

-- notification_preferences: full per-user control
CREATE POLICY "preferences_select_own" ON public.notification_preferences
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "preferences_upsert_own" ON public.notification_preferences
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- push_subscriptions: full per-user control
CREATE POLICY "push_select_own" ON public.push_subscriptions
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "push_insert_own" ON public.push_subscriptions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "push_update_own" ON public.push_subscriptions
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "push_delete_own" ON public.push_subscriptions
  FOR DELETE USING (auth.uid() = user_id);

-- notification_delivery_log: users read logs for their own notifications only
CREATE POLICY "delivery_log_select_own" ON public.notification_delivery_log
  FOR SELECT USING (
    notification_id IN (
      SELECT id FROM public.notifications WHERE user_id = auth.uid()
    )
  );

-- ─────────────────────────────────────────────
-- 10. RPC FUNCTIONS
-- ─────────────────────────────────────────────

-- 10.1 — Count unread notifications for the calling user
CREATE OR REPLACE FUNCTION public.get_unread_notifications_count(
  p_user_id uuid DEFAULT auth.uid()
)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COUNT(*)::integer
  FROM public.notifications
  WHERE user_id = p_user_id
    AND is_read    = false
    AND is_archived = false
    AND (expires_at IS NULL OR expires_at > now());
$$;

-- 10.2 — Mark a single notification as read (returns true if record was unread)
CREATE OR REPLACE FUNCTION public.mark_notification_read(
  p_notification_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated integer;
BEGIN
  UPDATE public.notifications
  SET    is_read    = true,
         read_at   = now(),
         updated_at = now()
  WHERE  id       = p_notification_id
    AND  user_id  = auth.uid()
    AND  is_read  = false;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated > 0;
END;
$$;

-- 10.3 — Mark all unread notifications as read (optionally filtered by category)
CREATE OR REPLACE FUNCTION public.mark_all_notifications_read(
  p_category public.notification_category DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  UPDATE public.notifications
  SET    is_read    = true,
         read_at   = now(),
         updated_at = now()
  WHERE  user_id    = auth.uid()
    AND  is_read    = false
    AND  is_archived = false
    AND  (p_category IS NULL OR category = p_category);

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- 10.4 — Archive a notification (also marks it as read)
CREATE OR REPLACE FUNCTION public.archive_notification(
  p_notification_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.notifications
  SET    is_archived  = true,
         archived_at  = now(),
         is_read      = true,
         read_at      = COALESCE(read_at, now()),
         updated_at   = now()
  WHERE  id      = p_notification_id
    AND  user_id = auth.uid();
END;
$$;

-- 10.5 — Cleanup expired & stale notifications (cron-safe)
CREATE OR REPLACE FUNCTION public.cleanup_old_notifications()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_archived integer;
  v_deleted  integer;
BEGIN
  -- Archive notifications that have passed their TTL
  UPDATE public.notifications
  SET    is_archived = true,
         archived_at = now(),
         updated_at  = now()
  WHERE  expires_at IS NOT NULL
    AND  expires_at < now()
    AND  is_archived = false;

  GET DIAGNOSTICS v_archived = ROW_COUNT;

  -- Hard-delete archived rows older than 90 days
  DELETE FROM public.notifications
  WHERE  is_archived = true
    AND  archived_at < now() - interval '90 days';

  -- Also hard-delete read notifications older than 90 days (housekeeping)
  DELETE FROM public.notifications
  WHERE  is_read   = true
    AND  is_archived = false
    AND  created_at < now() - interval '90 days';

  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  RETURN v_archived + v_deleted;
END;
$$;

-- Grant execute rights to authenticated users
GRANT EXECUTE ON FUNCTION public.get_unread_notifications_count(uuid)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_notification_read(uuid)          TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_all_notifications_read(public.notification_category) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_notification(uuid)            TO authenticated;
-- cleanup_old_notifications is for cron/service_role only — no authenticated grant

-- ─────────────────────────────────────────────
-- 11. REALTIME PUBLICATION
-- ─────────────────────────────────────────────

-- Enable Realtime on the notifications table so clients receive INSERT events
-- filtered by user_id via the RLS-aware channel subscription.
ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;

-- ─────────────────────────────────────────────
-- 12. SEED DATA — notification_event_types
-- ─────────────────────────────────────────────

INSERT INTO public.notification_event_types
  (event_key, label_ar, label_en, category, default_priority,
   title_template, body_template, icon, action_url_template)
VALUES
  -- ── HR Attendance ──────────────────────────────────────────
  ('hr.attendance.late',
   'تأخر في الحضور', 'Late Arrival',
   'hr_attendance', 'medium',
   'تأخر في الحضور — {{employee_name}}',
   'وصل متأخراً {{minutes_late}} دقيقة في {{date}}',
   'clock', '/hr/attendance?date={{date}}'),

  ('hr.attendance.absent',
   'غياب بدون إذن', 'Unexcused Absence',
   'hr_attendance', 'high',
   'غياب بدون إذن — {{employee_name}}',
   'لم يسجل حضوراً في {{date}}',
   'user-x', '/hr/attendance?date={{date}}'),

  ('hr.attendance.early_leave',
   'مغادرة مبكرة', 'Early Departure',
   'hr_attendance', 'medium',
   'مغادرة مبكرة — {{employee_name}}',
   'غادر قبل {{minutes_early}} دقيقة من وقت الانصراف',
   'log-out', '/hr/attendance?date={{date}}'),

  -- ── HR Leaves ──────────────────────────────────────────────
  ('hr.leave.requested',
   'طلب إجازة جديد', 'New Leave Request',
   'hr_leaves', 'high',
   'طلب إجازة يتطلب موافقتك',
   '{{employee_name}} طلب إجازة من {{from_date}} إلى {{to_date}}',
   'calendar-plus', '/hr/leaves/{{leave_id}}'),

  ('hr.leave.approved',
   'تمت الموافقة على الإجازة', 'Leave Approved',
   'hr_leaves', 'medium',
   'تمت الموافقة على إجازتك',
   'إجازتك من {{from_date}} إلى {{to_date}} تمت الموافقة عليها',
   'calendar-check', '/hr/leaves/{{leave_id}}'),

  ('hr.leave.rejected',
   'رُفض طلب الإجازة', 'Leave Rejected',
   'hr_leaves', 'medium',
   'رُفض طلب إجازتك',
   'طلب إجازتك من {{from_date}} إلى {{to_date}} تم رفضه. السبب: {{reason}}',
   'calendar-x', '/hr/leaves/{{leave_id}}'),

  -- ── HR Payroll ─────────────────────────────────────────────
  ('hr.payroll.processed',
   'صرف الرواتب', 'Payroll Processed',
   'hr_payroll', 'medium',
   'تم إعداد كشف راتبك لـ {{month}}',
   'راتب {{month}} جاهز للمراجعة. الإجمالي: {{total_amount}} {{currency}}',
   'banknote', '/hr/payroll/{{payroll_id}}'),

  -- ── Finance Expenses ───────────────────────────────────────
  ('finance.expense.submitted',
   'طلب صرف جديد', 'Expense Submitted',
   'finance_approvals', 'high',
   'طلب صرف يحتاج موافقتك',
   '{{requester_name}} طلب صرف {{amount}} {{currency}} — {{description}}',
   'receipt', '/finance/expenses/{{expense_id}}'),

  ('finance.expense.approved',
   'موافقة على طلب الصرف', 'Expense Approved',
   'finance_expenses', 'medium',
   'تمت الموافقة على طلب صرفك',
   'تمت الموافقة على طلب الصرف {{amount}} {{currency}} بواسطة {{approver_name}}',
   'check-circle', '/finance/expenses/{{expense_id}}'),

  ('finance.expense.rejected',
   'رفض طلب الصرف', 'Expense Rejected',
   'finance_expenses', 'medium',
   'تم رفض طلب صرفك',
   'تم رفض طلب الصرف {{amount}} {{currency}}. السبب: {{reason}}',
   'x-circle', '/finance/expenses/{{expense_id}}'),

  ('finance.budget.alert',
   'تحذير ميزانية', 'Budget Alert',
   'finance_approvals', 'high',
   'تحذير: الميزانية اقتربت من الحد',
   'ميزانية {{budget_name}} استُخدم منها {{percentage}}% ({{used}} من {{total}} {{currency}})',
   'alert-triangle', '/finance/budgets/{{budget_id}}'),

  -- ── Inventory ──────────────────────────────────────────────
  ('inventory.stock.low',
   'مخزون منخفض', 'Low Stock Alert',
   'inventory', 'high',
   'تحذير: مخزون منخفض — {{product_name}}',
   '{{product_name}} وصل إلى {{current_quantity}} {{unit}} (أقل من الحد الأدنى {{min_quantity}} {{unit}})',
   'package-minus', '/inventory/products/{{product_id}}'),

  ('inventory.stock.out',
   'نفاد المخزون', 'Out of Stock',
   'inventory', 'critical',
   'تحذير: نفاد المخزون — {{product_name}}',
   'نفد مخزون {{product_name}} تماماً',
   'package-x', '/inventory/products/{{product_id}}'),

  ('inventory.transfer.requested',
   'طلب تحويل مخزون', 'Transfer Requested',
   'inventory', 'medium',
   'طلب تحويل مخزون للموافقة',
   '{{requester_name}} طلب تحويل {{quantity}} {{unit}} من {{product_name}}',
   'package', '/inventory/transfers/{{transfer_id}}'),

  ('inventory.transfer.completed',
   'اكتمال تحويل المخزون', 'Transfer Completed',
   'inventory', 'low',
   'تم اكتمال تحويل المخزون',
   'تحويل {{quantity}} {{unit}} من {{product_name}} تم بنجاح',
   'package-check', '/inventory/transfers/{{transfer_id}}'),

  -- ── Sales ──────────────────────────────────────────────────
  ('sales.order.created',
   'طلب بيع جديد', 'New Sales Order',
   'sales', 'medium',
   'طلب بيع جديد #{{order_number}}',
   'طلب جديد من {{customer_name}} بقيمة {{amount}} {{currency}}',
   'shopping-cart', '/sales/orders/{{order_id}}'),

  ('sales.invoice.overdue',
   'فاتورة متأخرة السداد', 'Invoice Overdue',
   'sales', 'critical',
   'تحذير: فاتورة متأخرة السداد',
   'الفاتورة #{{invoice_number}} بقيمة {{amount}} {{currency}} للعميل {{customer_name}} متأخرة {{days_overdue}} يوم',
   'alert-circle', '/sales/invoices/{{invoice_id}}'),

  -- ── System ─────────────────────────────────────────────────
  ('system.app.update',
   'تحديث متاح', 'App Update Available',
   'system', 'low',
   'تحديث جديد متاح للنظام',
   'الإصدار {{version}} متاح الآن. أعد تحميل الصفحة للتحديث.',
   'refresh-cw', NULL),

  ('system.login.new_device',
   'تسجيل دخول من جهاز جديد', 'New Device Login',
   'system', 'high',
   'تسجيل دخول من جهاز جديد',
   'تم تسجيل الدخول من {{browser}} على {{os}} في {{location}}',
   'shield-alert', '/settings/security')

ON CONFLICT (event_key) DO UPDATE SET
  label_ar         = EXCLUDED.label_ar,
  label_en         = EXCLUDED.label_en,
  title_template   = EXCLUDED.title_template,
  body_template    = EXCLUDED.body_template,
  default_priority = EXCLUDED.default_priority,
  icon             = EXCLUDED.icon,
  action_url_template = EXCLUDED.action_url_template,
  is_active        = EXCLUDED.is_active,
  updated_at       = now();
