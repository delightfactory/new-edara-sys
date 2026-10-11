-- Local synthetic qualification only. Ten exact source42 statements; no production replay.
-- Original arbitrary-user SECURITY DEFINER semantics retained; wider notification security NOT accepted.
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

ALTER TABLE public.notification_event_types    ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.notifications               ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notification_event_types_read_all" ON public.notification_event_types
  FOR SELECT USING (true);

CREATE POLICY "notifications_select_own" ON public.notifications
  FOR SELECT USING (auth.uid() = user_id);

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

GRANT EXECUTE ON FUNCTION public.get_unread_notifications_count(uuid)  TO authenticated;
