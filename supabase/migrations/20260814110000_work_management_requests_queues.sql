-- Work Management — Requests / Queues foundation and read model.
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE TYPE public.work_queue_member_role AS ENUM ('member','triager','manager');
CREATE TYPE public.work_request_triage_outcome AS ENUM ('accepted','needs_information','rejected');

CREATE TABLE public.work_queues (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(50) NOT NULL UNIQUE,
  name VARCHAR(160) NOT NULL,
  description TEXT,
  branch_id UUID REFERENCES public.branches(id) ON DELETE RESTRICT,
  department_id UUID REFERENCES public.hr_departments(id) ON DELETE RESTRICT,
  manager_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  default_priority public.work_priority NOT NULL DEFAULT 'normal',
  default_triage_sla_minutes INTEGER NOT NULL DEFAULT 240,
  default_resolution_sla_minutes INTEGER,
  is_active BOOLEAN NOT NULL DEFAULT true,
  settings JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_by_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT work_queues_code_not_blank CHECK (btrim(code) <> ''),
  CONSTRAINT work_queues_name_not_blank CHECK (btrim(name) <> ''),
  CONSTRAINT work_queues_triage_sla_positive CHECK (default_triage_sla_minutes > 0),
  CONSTRAINT work_queues_resolution_sla_positive CHECK (
    default_resolution_sla_minutes IS NULL OR default_resolution_sla_minutes > 0
  ),
  CONSTRAINT work_queues_settings_object CHECK (jsonb_typeof(settings) = 'object')
);

CREATE TRIGGER trg_work_queues_updated_at
  BEFORE UPDATE ON public.work_queues
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE public.work_queue_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  queue_id UUID NOT NULL REFERENCES public.work_queues(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  member_role public.work_queue_member_role NOT NULL DEFAULT 'member',
  can_triage BOOLEAN NOT NULL DEFAULT false,
  can_assign BOOLEAN NOT NULL DEFAULT false,
  active_from TIMESTAMPTZ NOT NULL DEFAULT now(),
  active_until TIMESTAMPTZ,
  added_by_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT work_queue_members_active_window CHECK (
    active_until IS NULL OR active_until > active_from
  )
);

CREATE UNIQUE INDEX work_queue_members_open_membership_uniq
  ON public.work_queue_members(queue_id,user_id)
  WHERE active_until IS NULL;
CREATE INDEX idx_work_queue_members_user_active
  ON public.work_queue_members(user_id,queue_id,active_until);

CREATE TABLE public.work_request_types (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(80) NOT NULL UNIQUE,
  name VARCHAR(180) NOT NULL,
  description TEXT,
  target_queue_id UUID NOT NULL REFERENCES public.work_queues(id) ON DELETE RESTRICT,
  target_department_id UUID REFERENCES public.hr_departments(id) ON DELETE RESTRICT,
  intake_schema JSONB NOT NULL DEFAULT '{"version":1,"fields":[]}'::JSONB,
  expected_outcome_template TEXT NOT NULL,
  default_priority public.work_priority,
  default_visibility public.work_visibility NOT NULL DEFAULT 'standard',
  triage_sla_minutes INTEGER,
  default_resolution_sla_minutes INTEGER,
  allow_requester_cancel BOOLEAN NOT NULL DEFAULT true,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT work_request_types_code_not_blank CHECK (btrim(code) <> ''),
  CONSTRAINT work_request_types_name_not_blank CHECK (btrim(name) <> ''),
  CONSTRAINT work_request_types_outcome_not_blank CHECK (btrim(expected_outcome_template) <> ''),
  CONSTRAINT work_request_types_schema_object CHECK (jsonb_typeof(intake_schema) = 'object'),
  CONSTRAINT work_request_types_schema_version CHECK (
    jsonb_typeof(intake_schema->'version') = 'number'
  ),
  CONSTRAINT work_request_types_schema_fields CHECK (
    jsonb_typeof(intake_schema->'fields') = 'array'
  ),
  CONSTRAINT work_request_types_triage_sla_positive CHECK (
    triage_sla_minutes IS NULL OR triage_sla_minutes > 0
  ),
  CONSTRAINT work_request_types_resolution_sla_positive CHECK (
    default_resolution_sla_minutes IS NULL OR default_resolution_sla_minutes > 0
  )
);

CREATE TRIGGER trg_work_request_types_updated_at
  BEFORE UPDATE ON public.work_request_types
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE public.work_requests (
  work_item_id UUID PRIMARY KEY REFERENCES public.work_items(id) ON DELETE CASCADE,
  request_type_id UUID NOT NULL REFERENCES public.work_request_types(id) ON DELETE RESTRICT,
  queue_id UUID NOT NULL REFERENCES public.work_queues(id) ON DELETE RESTRICT,
  intake_payload JSONB NOT NULL DEFAULT '{}'::JSONB,
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  triage_due_at TIMESTAMPTZ NOT NULL,
  first_responded_at TIMESTAMPTZ,
  triaged_at TIMESTAMPTZ,
  triaged_by_user_id UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  triage_outcome public.work_request_triage_outcome,
  information_request_note TEXT,
  rejection_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT work_requests_payload_object CHECK (jsonb_typeof(intake_payload) = 'object'),
  CONSTRAINT work_requests_triage_after_submit CHECK (triage_due_at >= submitted_at),
  CONSTRAINT work_requests_first_response_after_submit CHECK (
    first_responded_at IS NULL OR first_responded_at >= submitted_at
  ),
  CONSTRAINT work_requests_triaged_after_submit CHECK (
    triaged_at IS NULL OR triaged_at >= submitted_at
  ),
  CONSTRAINT work_requests_triage_pair CHECK (
    (triaged_at IS NULL AND triage_outcome IS NULL)
    OR (triaged_at IS NOT NULL AND triage_outcome IN ('accepted','rejected'))
  )
);

CREATE INDEX idx_work_requests_queue_backlog
  ON public.work_requests(queue_id,triage_due_at,submitted_at)
  WHERE triaged_at IS NULL;
CREATE INDEX idx_work_requests_request_type
  ON public.work_requests(request_type_id,submitted_at DESC);

ALTER TABLE public.work_items
  ADD CONSTRAINT work_items_queue_fk
  FOREIGN KEY (queue_id) REFERENCES public.work_queues(id) ON DELETE RESTRICT,
  ADD CONSTRAINT work_items_request_type_fk
  FOREIGN KEY (request_type_id) REFERENCES public.work_request_types(id) ON DELETE RESTRICT;

CREATE OR REPLACE FUNCTION private.work_user_is_queue_member(
  p_user_id UUID,
  p_queue_id UUID
) RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT p_user_id IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.work_queue_members m
    JOIN public.work_queues q ON q.id=m.queue_id
    WHERE m.queue_id=p_queue_id
      AND m.user_id=p_user_id
      AND q.is_active=true
      AND m.active_from <= clock_timestamp()
      AND (m.active_until IS NULL OR m.active_until > clock_timestamp())
  );
$$;

CREATE OR REPLACE FUNCTION private.work_user_can_triage_queue(
  p_user_id UUID,
  p_queue_id UUID
) RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT private.work_actor_is_active(p_user_id)
    AND COALESCE(public.check_permission(p_user_id,'work.requests.triage'),false)
    AND (
      COALESCE(public.check_permission(p_user_id,'work.queues.manage'),false)
      OR EXISTS (
        SELECT 1 FROM public.work_queues q
        WHERE q.id=p_queue_id AND q.is_active=true AND q.manager_user_id=p_user_id
      )
      OR EXISTS (
        SELECT 1 FROM public.work_queue_members m
        WHERE m.queue_id=p_queue_id AND m.user_id=p_user_id
          AND m.active_from <= clock_timestamp()
          AND (m.active_until IS NULL OR m.active_until > clock_timestamp())
          AND (m.can_triage=true OR m.member_role IN ('triager','manager'))
      )
    );
$$;

CREATE OR REPLACE FUNCTION private.work_user_can_assign_queue(
  p_user_id UUID,
  p_queue_id UUID
) RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT private.work_actor_is_active(p_user_id)
    AND (
      COALESCE(public.check_permission(p_user_id,'work.queues.manage'),false)
      OR EXISTS (
        SELECT 1 FROM public.work_queues q
        WHERE q.id=p_queue_id AND q.is_active=true AND q.manager_user_id=p_user_id
      )
      OR EXISTS (
        SELECT 1 FROM public.work_queue_members m
        WHERE m.queue_id=p_queue_id AND m.user_id=p_user_id
          AND m.active_from <= clock_timestamp()
          AND (m.active_until IS NULL OR m.active_until > clock_timestamp())
          AND (m.can_assign=true OR m.member_role='manager')
      )
    );
$$;

CREATE OR REPLACE FUNCTION private.work_queue_assignment_target_allowed(
  p_queue_id UUID,
  p_target_user_id UUID
) RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT private.work_actor_is_active(p_target_user_id)
    AND (
      EXISTS (
        SELECT 1 FROM public.work_queues q
        WHERE q.id=p_queue_id AND q.is_active=true AND q.manager_user_id=p_target_user_id
      )
      OR private.work_user_is_queue_member(p_target_user_id,p_queue_id)
    );
$$;

CREATE OR REPLACE FUNCTION private.work_user_has_queue_access(
  p_user_id UUID,
  p_work_item_id UUID
) RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT COALESCE(public.check_permission(p_user_id,'work.items.read_own'),false)
    AND EXISTS (
      SELECT 1
      FROM public.work_items w
      WHERE w.id=p_work_item_id
        AND w.queue_id IS NOT NULL
        AND private.work_user_is_queue_member(p_user_id,w.queue_id)
    );
$$;

-- Extend Work visibility with queue-scoped access without turning membership into
-- team/branch authority. Private Work still requires direct access or read_private.
CREATE OR REPLACE FUNCTION private.work_user_can_view_row(
  p_user_id UUID,
  p_work_item_id UUID,
  p_visibility public.work_visibility,
  p_creator_user_id UUID,
  p_requester_user_id UUID,
  p_accountable_owner_user_id UUID,
  p_current_assignee_user_id UUID,
  p_branch_id UUID,
  p_owning_department_id UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_direct BOOLEAN;
  v_team BOOLEAN:=false;
  v_queue BOOLEAN:=false;
  v_read_own BOOLEAN;
  v_read_team BOOLEAN;
  v_read_all BOOLEAN;
BEGIN
  IF p_user_id IS NULL OR NOT private.work_actor_is_active(p_user_id) THEN RETURN false; END IF;

  v_direct:=private.work_user_has_direct_access(
    p_user_id,p_work_item_id,p_creator_user_id,p_requester_user_id,
    p_accountable_owner_user_id,p_current_assignee_user_id
  );
  v_read_own:=COALESCE(public.check_permission(p_user_id,'work.items.read_own'),false);
  IF v_direct AND v_read_own THEN RETURN true; END IF;

  v_read_all:=COALESCE(public.check_permission(p_user_id,'work.items.read_all'),false);
  IF p_visibility='private'::public.work_visibility THEN
    RETURN v_read_all AND COALESCE(public.check_permission(p_user_id,'work.items.read_private'),false);
  END IF;

  v_queue:=private.work_user_has_queue_access(p_user_id,p_work_item_id);
  v_read_team:=COALESCE(public.check_permission(p_user_id,'work.items.read_team'),false);
  IF v_read_team THEN
    v_team:=private.work_user_manages_scope(
      p_user_id,p_branch_id,p_owning_department_id,
      p_accountable_owner_user_id,p_current_assignee_user_id
    );
  END IF;

  IF p_visibility='restricted'::public.work_visibility THEN
    IF NOT COALESCE(public.check_permission(p_user_id,'work.items.read_restricted'),false) THEN RETURN false; END IF;
    RETURN v_read_all OR v_team OR v_queue;
  END IF;

  RETURN v_read_all OR v_team OR v_queue;
END;
$$;

REVOKE ALL ON FUNCTION private.work_user_is_queue_member(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_user_can_triage_queue(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_user_can_assign_queue(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_queue_assignment_target_allowed(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_user_has_queue_access(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

ALTER TABLE public.work_queues ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_queue_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_request_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_requests ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.work_queues FROM anon,authenticated;
REVOKE ALL ON TABLE public.work_queue_members FROM anon,authenticated;
REVOKE ALL ON TABLE public.work_request_types FROM anon,authenticated;
REVOKE ALL ON TABLE public.work_requests FROM anon,authenticated;
GRANT SELECT ON TABLE public.work_queues TO authenticated;
GRANT SELECT ON TABLE public.work_queue_members TO authenticated;
GRANT SELECT ON TABLE public.work_request_types TO authenticated;
GRANT SELECT ON TABLE public.work_requests TO authenticated;

CREATE POLICY work_queues_select_visible
ON public.work_queues FOR SELECT TO authenticated
USING (
  is_active=true AND (
    COALESCE(public.check_permission(auth.uid(),'work.requests.create'),false)
    OR manager_user_id=auth.uid()
    OR private.work_user_is_queue_member(auth.uid(),id)
    OR COALESCE(public.check_permission(auth.uid(),'work.queues.manage'),false)
  )
);

CREATE POLICY work_queue_members_select_visible
ON public.work_queue_members FOR SELECT TO authenticated
USING (
  user_id=auth.uid()
  OR private.work_user_can_triage_queue(auth.uid(),queue_id)
  OR COALESCE(public.check_permission(auth.uid(),'work.queues.manage'),false)
);

CREATE POLICY work_request_types_select_visible
ON public.work_request_types FOR SELECT TO authenticated
USING (
  (is_active=true AND COALESCE(public.check_permission(auth.uid(),'work.requests.create'),false))
  OR private.work_user_can_triage_queue(auth.uid(),target_queue_id)
  OR COALESCE(public.check_permission(auth.uid(),'work.queues.manage'),false)
);

CREATE POLICY work_requests_select_visible
ON public.work_requests FOR SELECT TO authenticated
USING (private.work_current_user_can_view_item(work_item_id));

CREATE OR REPLACE VIEW public.work_queue_backlog
WITH (security_invoker=true)
AS
SELECT
  r.queue_id,
  r.request_type_id,
  r.work_item_id,
  w.work_number,
  w.title,
  w.priority,
  w.visibility,
  w.requester_user_id,
  w.accountable_owner_user_id,
  w.current_assignee_user_id,
  w.status,
  r.submitted_at,
  r.triage_due_at,
  r.first_responded_at,
  CASE
    WHEN r.first_responded_at IS NOT NULL THEN 'responded'
    WHEN r.triage_due_at < clock_timestamp() THEN 'breached'
    ELSE 'within_sla'
  END AS triage_sla_state,
  w.due_at,
  w.next_action_text,
  w.next_action_at,
  w.state_version
FROM public.work_requests r
JOIN public.work_items w ON w.id=r.work_item_id
WHERE r.triaged_at IS NULL
  AND w.status NOT IN ('done'::public.work_item_status,'cancelled'::public.work_item_status);

GRANT SELECT ON public.work_queue_backlog TO authenticated;

RESET lock_timeout;
RESET statement_timeout;
