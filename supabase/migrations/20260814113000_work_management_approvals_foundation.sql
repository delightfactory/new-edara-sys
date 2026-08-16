-- Work Management — versioned Approval Engine foundation.
SET lock_timeout='5s';
SET statement_timeout='60s';

CREATE TYPE public.work_approval_definition_status AS ENUM ('draft','published');
CREATE TYPE public.work_approval_stage_mode AS ENUM ('all','any');
CREATE TYPE public.work_approval_selector_kind AS ENUM (
  'user','work_owner','assignee','department_manager','branch_manager'
);
CREATE TYPE public.work_approval_context_kind AS ENUM ('completion','due_change','general','workflow_step');
CREATE TYPE public.work_approval_runtime_status AS ENUM (
  'pending','approved','rejected','changes_required','cancelled'
);
CREATE TYPE public.work_approval_assignment_status AS ENUM (
  'pending','approved','rejected','changes_required','skipped'
);

CREATE TABLE public.work_approval_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(80) NOT NULL UNIQUE,
  name VARCHAR(180) NOT NULL,
  description TEXT,
  current_published_version_id UUID,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT work_approval_templates_code_not_blank CHECK (btrim(code)<>''),
  CONSTRAINT work_approval_templates_name_not_blank CHECK (btrim(name)<>'')
);
CREATE TRIGGER trg_work_approval_templates_updated_at
  BEFORE UPDATE ON public.work_approval_templates
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE public.work_approval_template_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id UUID NOT NULL REFERENCES public.work_approval_templates(id) ON DELETE RESTRICT,
  version_number INTEGER NOT NULL,
  status public.work_approval_definition_status NOT NULL DEFAULT 'draft',
  metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_by_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  published_by_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  published_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT work_approval_versions_number_positive CHECK (version_number>0),
  CONSTRAINT work_approval_versions_metadata_object CHECK (jsonb_typeof(metadata)='object'),
  CONSTRAINT work_approval_versions_publish_pair CHECK (
    (status='draft' AND published_at IS NULL)
    OR (status='published' AND published_at IS NOT NULL)
  ),
  CONSTRAINT work_approval_versions_template_number_uniq UNIQUE(template_id,version_number)
);

ALTER TABLE public.work_approval_templates
  ADD CONSTRAINT work_approval_templates_current_version_fk
  FOREIGN KEY (current_published_version_id)
  REFERENCES public.work_approval_template_versions(id) ON DELETE RESTRICT;

CREATE TABLE public.work_approval_stages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_version_id UUID NOT NULL REFERENCES public.work_approval_template_versions(id) ON DELETE CASCADE,
  stage_order INTEGER NOT NULL,
  name VARCHAR(180) NOT NULL,
  decision_mode public.work_approval_stage_mode NOT NULL DEFAULT 'all',
  deadline_minutes INTEGER,
  allow_changes_required BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT work_approval_stages_order_positive CHECK (stage_order>0),
  CONSTRAINT work_approval_stages_name_not_blank CHECK (btrim(name)<>''),
  CONSTRAINT work_approval_stages_deadline_positive CHECK (deadline_minutes IS NULL OR deadline_minutes>0),
  CONSTRAINT work_approval_stages_version_order_uniq UNIQUE(template_version_id,stage_order)
);

CREATE TABLE public.work_approval_stage_approvers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  stage_id UUID NOT NULL REFERENCES public.work_approval_stages(id) ON DELETE CASCADE,
  selector_kind public.work_approval_selector_kind NOT NULL,
  selector_user_id UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT work_approval_stage_approvers_sort_nonnegative CHECK (sort_order>=0),
  CONSTRAINT work_approval_stage_approvers_user_selector_check CHECK (
    (selector_kind='user' AND selector_user_id IS NOT NULL)
    OR (selector_kind<>'user' AND selector_user_id IS NULL)
  )
);
CREATE UNIQUE INDEX work_approval_stage_approvers_selector_uniq
  ON public.work_approval_stage_approvers(stage_id,selector_kind,COALESCE(selector_user_id,'00000000-0000-0000-0000-000000000000'::UUID));

CREATE TABLE public.work_approval_delegations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delegator_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  delegate_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  template_id UUID REFERENCES public.work_approval_templates(id) ON DELETE CASCADE,
  context_kind public.work_approval_context_kind,
  starts_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ends_at TIMESTAMPTZ,
  reason TEXT,
  created_by_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  revoked_at TIMESTAMPTZ,
  revoked_by_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT work_approval_delegations_not_self CHECK (delegator_user_id<>delegate_user_id),
  CONSTRAINT work_approval_delegations_window CHECK (ends_at IS NULL OR ends_at>starts_at),
  CONSTRAINT work_approval_delegations_revoke_after_start CHECK (revoked_at IS NULL OR revoked_at>=starts_at)
);
CREATE INDEX idx_work_approval_delegations_resolver
  ON public.work_approval_delegations(delegator_user_id,starts_at,ends_at,revoked_at);

CREATE TABLE public.work_approval_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_item_id UUID NOT NULL REFERENCES public.work_items(id) ON DELETE CASCADE,
  template_version_id UUID NOT NULL REFERENCES public.work_approval_template_versions(id) ON DELETE RESTRICT,
  context_kind public.work_approval_context_kind NOT NULL,
  context_payload JSONB NOT NULL DEFAULT '{}'::JSONB,
  status public.work_approval_runtime_status NOT NULL DEFAULT 'pending',
  current_stage_order INTEGER,
  requested_by_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  state_version BIGINT NOT NULL DEFAULT 1,
  CONSTRAINT work_approval_requests_payload_object CHECK (jsonb_typeof(context_payload)='object'),
  CONSTRAINT work_approval_requests_state_version_positive CHECK (state_version>0)
);
CREATE UNIQUE INDEX work_approval_requests_one_pending_context
  ON public.work_approval_requests(work_item_id,context_kind)
  WHERE status='pending';
CREATE INDEX idx_work_approval_requests_item_status
  ON public.work_approval_requests(work_item_id,status,requested_at DESC);

CREATE TABLE public.work_approval_stage_instances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  approval_request_id UUID NOT NULL REFERENCES public.work_approval_requests(id) ON DELETE CASCADE,
  stage_definition_id UUID NOT NULL REFERENCES public.work_approval_stages(id) ON DELETE RESTRICT,
  stage_order INTEGER NOT NULL,
  decision_mode public.work_approval_stage_mode NOT NULL,
  status public.work_approval_runtime_status NOT NULL DEFAULT 'pending',
  activated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  due_at TIMESTAMPTZ,
  decided_at TIMESTAMPTZ,
  CONSTRAINT work_approval_stage_instances_order_positive CHECK (stage_order>0),
  CONSTRAINT work_approval_stage_instances_request_order_uniq UNIQUE(approval_request_id,stage_order)
);
CREATE INDEX idx_work_approval_stage_instances_pending_due
  ON public.work_approval_stage_instances(due_at)
  WHERE status='pending' AND due_at IS NOT NULL;

CREATE TABLE public.work_approval_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  stage_instance_id UUID NOT NULL REFERENCES public.work_approval_stage_instances(id) ON DELETE CASCADE,
  original_approver_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  effective_approver_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  status public.work_approval_assignment_status NOT NULL DEFAULT 'pending',
  decision_note TEXT,
  decided_at TIMESTAMPTZ,
  decided_by_user_id UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  acting_for_user_id UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT work_approval_assignments_stage_original_uniq UNIQUE(stage_instance_id,original_approver_user_id),
  CONSTRAINT work_approval_assignments_acting_for_check CHECK (
    acting_for_user_id IS NULL OR acting_for_user_id=original_approver_user_id
  )
);
CREATE INDEX idx_work_approval_assignments_inbox
  ON public.work_approval_assignments(effective_approver_user_id,status,created_at)
  WHERE status='pending';

ALTER TABLE public.work_items
  ADD CONSTRAINT work_items_completion_approval_template_fk
  FOREIGN KEY (completion_approval_template_id)
  REFERENCES public.work_approval_templates(id) ON DELETE RESTRICT;

-- Published approval definitions are immutable. A new version is required.
CREATE OR REPLACE FUNCTION private.work_block_published_approval_version_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
BEGIN
  IF TG_TABLE_NAME='work_approval_template_versions' THEN
    IF OLD.status='published'::public.work_approval_definition_status THEN
      RAISE EXCEPTION 'published approval versions are immutable';
    END IF;
  ELSIF TG_TABLE_NAME='work_approval_stages' THEN
    IF EXISTS (
      SELECT 1 FROM public.work_approval_template_versions v
      WHERE v.id=OLD.template_version_id AND v.status='published'
    ) THEN RAISE EXCEPTION 'published approval stages are immutable'; END IF;
  ELSIF TG_TABLE_NAME='work_approval_stage_approvers' THEN
    IF EXISTS (
      SELECT 1 FROM public.work_approval_stages s
      JOIN public.work_approval_template_versions v ON v.id=s.template_version_id
      WHERE s.id=OLD.stage_id AND v.status='published'
    ) THEN RAISE EXCEPTION 'published approval approvers are immutable'; END IF;
  END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END;
$$;

CREATE TRIGGER trg_work_approval_version_immutable
  BEFORE UPDATE OR DELETE ON public.work_approval_template_versions
  FOR EACH ROW EXECUTE FUNCTION private.work_block_published_approval_version_mutation();
CREATE TRIGGER trg_work_approval_stage_immutable
  BEFORE UPDATE OR DELETE ON public.work_approval_stages
  FOR EACH ROW EXECUTE FUNCTION private.work_block_published_approval_version_mutation();
CREATE TRIGGER trg_work_approval_approver_immutable
  BEFORE UPDATE OR DELETE ON public.work_approval_stage_approvers
  FOR EACH ROW EXECUTE FUNCTION private.work_block_published_approval_version_mutation();

CREATE OR REPLACE FUNCTION private.work_resolve_approval_delegate(
  p_original_approver_user_id UUID,
  p_template_id UUID,
  p_context_kind public.work_approval_context_kind,
  p_at TIMESTAMPTZ DEFAULT now()
) RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT COALESCE((
    SELECT d.delegate_user_id
    FROM public.work_approval_delegations d
    WHERE d.delegator_user_id=p_original_approver_user_id
      AND d.revoked_at IS NULL
      AND d.starts_at<=p_at
      AND (d.ends_at IS NULL OR d.ends_at>p_at)
      AND (d.template_id IS NULL OR d.template_id=p_template_id)
      AND (d.context_kind IS NULL OR d.context_kind=p_context_kind)
      AND private.work_actor_is_active(d.delegate_user_id)
    ORDER BY
      (d.template_id IS NOT NULL)::INTEGER DESC,
      (d.context_kind IS NOT NULL)::INTEGER DESC,
      d.starts_at DESC,
      d.id
    LIMIT 1
  ),p_original_approver_user_id);
$$;

CREATE OR REPLACE FUNCTION private.work_user_has_approval_access(
  p_user_id UUID,
  p_work_item_id UUID
) RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT p_user_id IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.work_approval_requests r
    JOIN public.work_approval_stage_instances s ON s.approval_request_id=r.id
    JOIN public.work_approval_assignments a ON a.stage_instance_id=s.id
    WHERE r.work_item_id=p_work_item_id
      AND p_user_id IN (a.original_approver_user_id,a.effective_approver_user_id)
  );
$$;

CREATE OR REPLACE FUNCTION private.work_user_has_direct_access(
  p_user_id UUID,
  p_work_item_id UUID,
  p_creator_user_id UUID,
  p_requester_user_id UUID,
  p_accountable_owner_user_id UUID,
  p_current_assignee_user_id UUID
) RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT p_user_id IS NOT NULL AND (
    p_user_id=p_creator_user_id
    OR p_user_id=p_requester_user_id
    OR p_user_id=p_accountable_owner_user_id
    OR p_user_id=p_current_assignee_user_id
    OR EXISTS (
      SELECT 1 FROM public.work_participants wp
      WHERE wp.work_item_id=p_work_item_id AND wp.user_id=p_user_id AND wp.removed_at IS NULL
    )
    OR private.work_user_has_approval_access(p_user_id,p_work_item_id)
  );
$$;

REVOKE ALL ON FUNCTION private.work_block_published_approval_version_mutation() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_resolve_approval_delegate(UUID,UUID,public.work_approval_context_kind,TIMESTAMPTZ) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_user_has_approval_access(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

ALTER TABLE public.work_approval_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_approval_template_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_approval_stages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_approval_stage_approvers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_approval_delegations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_approval_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_approval_stage_instances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_approval_assignments ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.work_approval_templates FROM anon,authenticated;
REVOKE ALL ON TABLE public.work_approval_template_versions FROM anon,authenticated;
REVOKE ALL ON TABLE public.work_approval_stages FROM anon,authenticated;
REVOKE ALL ON TABLE public.work_approval_stage_approvers FROM anon,authenticated;
REVOKE ALL ON TABLE public.work_approval_delegations FROM anon,authenticated;
REVOKE ALL ON TABLE public.work_approval_requests FROM anon,authenticated;
REVOKE ALL ON TABLE public.work_approval_stage_instances FROM anon,authenticated;
REVOKE ALL ON TABLE public.work_approval_assignments FROM anon,authenticated;

GRANT SELECT ON TABLE public.work_approval_templates TO authenticated;
GRANT SELECT ON TABLE public.work_approval_template_versions TO authenticated;
GRANT SELECT ON TABLE public.work_approval_stages TO authenticated;
GRANT SELECT ON TABLE public.work_approval_stage_approvers TO authenticated;
GRANT SELECT ON TABLE public.work_approval_delegations TO authenticated;
GRANT SELECT ON TABLE public.work_approval_requests TO authenticated;
GRANT SELECT ON TABLE public.work_approval_stage_instances TO authenticated;
GRANT SELECT ON TABLE public.work_approval_assignments TO authenticated;

CREATE POLICY work_approval_templates_select
ON public.work_approval_templates FOR SELECT TO authenticated
USING (is_active=true OR COALESCE(public.check_permission(auth.uid(),'work.templates.manage'),false));
CREATE POLICY work_approval_versions_select
ON public.work_approval_template_versions FOR SELECT TO authenticated
USING (status='published' OR COALESCE(public.check_permission(auth.uid(),'work.templates.manage'),false));
CREATE POLICY work_approval_stages_select
ON public.work_approval_stages FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.work_approval_template_versions v
  WHERE v.id=template_version_id AND (v.status='published' OR COALESCE(public.check_permission(auth.uid(),'work.templates.manage'),false))
));
CREATE POLICY work_approval_stage_approvers_select
ON public.work_approval_stage_approvers FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.work_approval_stages s
  JOIN public.work_approval_template_versions v ON v.id=s.template_version_id
  WHERE s.id=stage_id AND (v.status='published' OR COALESCE(public.check_permission(auth.uid(),'work.templates.manage'),false))
));
CREATE POLICY work_approval_delegations_select
ON public.work_approval_delegations FOR SELECT TO authenticated
USING (
  delegator_user_id=auth.uid() OR delegate_user_id=auth.uid()
  OR COALESCE(public.check_permission(auth.uid(),'work.templates.manage'),false)
);
CREATE POLICY work_approval_requests_select
ON public.work_approval_requests FOR SELECT TO authenticated
USING (private.work_current_user_can_view_item(work_item_id));
CREATE POLICY work_approval_stage_instances_select
ON public.work_approval_stage_instances FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.work_approval_requests r
  WHERE r.id=approval_request_id AND private.work_current_user_can_view_item(r.work_item_id)
));
CREATE POLICY work_approval_assignments_select
ON public.work_approval_assignments FOR SELECT TO authenticated
USING (
  effective_approver_user_id=auth.uid() OR original_approver_user_id=auth.uid()
  OR EXISTS (
    SELECT 1 FROM public.work_approval_stage_instances s
    JOIN public.work_approval_requests r ON r.id=s.approval_request_id
    WHERE s.id=stage_instance_id AND private.work_current_user_can_view_item(r.work_item_id)
  )
);

RESET lock_timeout;
RESET statement_timeout;
