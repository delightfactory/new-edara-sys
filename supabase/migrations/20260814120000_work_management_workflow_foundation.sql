-- Work Management — versioned Workflow Engine foundation.
SET lock_timeout='5s';
SET statement_timeout='60s';

CREATE TYPE public.work_workflow_definition_status AS ENUM ('draft','published');
CREATE TYPE public.work_workflow_step_kind AS ENUM ('task','approval');
CREATE TYPE public.work_workflow_run_status AS ENUM ('running','completed','failed','cancelled');
CREATE TYPE public.work_workflow_step_runtime_status AS ENUM (
  'pending','active','completed','skipped','failed','cancelled'
);

CREATE TABLE public.work_workflow_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(80) NOT NULL UNIQUE,
  name VARCHAR(180) NOT NULL,
  description TEXT,
  current_published_version_id UUID,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT work_workflow_templates_code_not_blank CHECK (btrim(code)<>''),
  CONSTRAINT work_workflow_templates_name_not_blank CHECK (btrim(name)<>'')
);
CREATE TRIGGER trg_work_workflow_templates_updated_at
  BEFORE UPDATE ON public.work_workflow_templates
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE public.work_workflow_template_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id UUID NOT NULL REFERENCES public.work_workflow_templates(id) ON DELETE RESTRICT,
  version_number INTEGER NOT NULL,
  status public.work_workflow_definition_status NOT NULL DEFAULT 'draft',
  metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_by_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  published_by_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  published_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT work_workflow_versions_number_positive CHECK (version_number>0),
  CONSTRAINT work_workflow_versions_metadata_object CHECK (jsonb_typeof(metadata)='object'),
  CONSTRAINT work_workflow_versions_publish_pair CHECK (
    (status='draft' AND published_at IS NULL) OR (status='published' AND published_at IS NOT NULL)
  ),
  CONSTRAINT work_workflow_versions_template_number_uniq UNIQUE(template_id,version_number)
);
ALTER TABLE public.work_workflow_templates
  ADD CONSTRAINT work_workflow_templates_current_version_fk
  FOREIGN KEY (current_published_version_id) REFERENCES public.work_workflow_template_versions(id) ON DELETE RESTRICT;

CREATE TABLE public.work_workflow_step_definitions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_version_id UUID NOT NULL REFERENCES public.work_workflow_template_versions(id) ON DELETE CASCADE,
  step_key VARCHAR(100) NOT NULL,
  name VARCHAR(180) NOT NULL,
  step_kind public.work_workflow_step_kind NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  condition_dsl JSONB NOT NULL DEFAULT '{"op":"always"}'::JSONB,
  task_config JSONB NOT NULL DEFAULT '{}'::JSONB,
  approval_template_id UUID REFERENCES public.work_approval_templates(id) ON DELETE RESTRICT,
  output_schema JSONB NOT NULL DEFAULT '{"version":1,"fields":[]}'::JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT work_workflow_steps_key_not_blank CHECK (btrim(step_key)<>''),
  CONSTRAINT work_workflow_steps_name_not_blank CHECK (btrim(name)<>''),
  CONSTRAINT work_workflow_steps_sort_nonnegative CHECK (sort_order>=0),
  CONSTRAINT work_workflow_steps_condition_object CHECK (jsonb_typeof(condition_dsl)='object'),
  CONSTRAINT work_workflow_steps_task_config_object CHECK (jsonb_typeof(task_config)='object'),
  CONSTRAINT work_workflow_steps_output_schema_object CHECK (jsonb_typeof(output_schema)='object'),
  CONSTRAINT work_workflow_steps_approval_binding CHECK (
    (step_kind='approval' AND approval_template_id IS NOT NULL)
    OR (step_kind='task' AND approval_template_id IS NULL)
  ),
  CONSTRAINT work_workflow_steps_version_key_uniq UNIQUE(template_version_id,step_key)
);

CREATE TABLE public.work_workflow_step_dependencies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_version_id UUID NOT NULL REFERENCES public.work_workflow_template_versions(id) ON DELETE CASCADE,
  predecessor_step_id UUID NOT NULL REFERENCES public.work_workflow_step_definitions(id) ON DELETE CASCADE,
  successor_step_id UUID NOT NULL REFERENCES public.work_workflow_step_definitions(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT work_workflow_dependencies_not_self CHECK (predecessor_step_id<>successor_step_id),
  CONSTRAINT work_workflow_dependencies_pair_uniq UNIQUE(predecessor_step_id,successor_step_id)
);
CREATE INDEX idx_work_workflow_dependencies_successor
  ON public.work_workflow_step_dependencies(successor_step_id,predecessor_step_id);

CREATE TABLE public.work_workflow_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_version_id UUID NOT NULL REFERENCES public.work_workflow_template_versions(id) ON DELETE RESTRICT,
  parent_work_item_id UUID REFERENCES public.work_items(id) ON DELETE SET NULL,
  recurrence_occurrence_id UUID,
  status public.work_workflow_run_status NOT NULL DEFAULT 'running',
  input_data JSONB NOT NULL DEFAULT '{}'::JSONB,
  output_data JSONB NOT NULL DEFAULT '{}'::JSONB,
  started_by_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  state_version BIGINT NOT NULL DEFAULT 1,
  CONSTRAINT work_workflow_runs_input_object CHECK (jsonb_typeof(input_data)='object'),
  CONSTRAINT work_workflow_runs_output_object CHECK (jsonb_typeof(output_data)='object'),
  CONSTRAINT work_workflow_runs_state_version_positive CHECK (state_version>0)
);
CREATE INDEX idx_work_workflow_runs_status_started
  ON public.work_workflow_runs(status,started_at);

CREATE TABLE public.work_workflow_step_instances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_run_id UUID NOT NULL REFERENCES public.work_workflow_runs(id) ON DELETE CASCADE,
  step_definition_id UUID NOT NULL REFERENCES public.work_workflow_step_definitions(id) ON DELETE RESTRICT,
  step_key VARCHAR(100) NOT NULL,
  status public.work_workflow_step_runtime_status NOT NULL DEFAULT 'pending',
  work_item_id UUID REFERENCES public.work_items(id) ON DELETE SET NULL,
  approval_request_id UUID REFERENCES public.work_approval_requests(id) ON DELETE SET NULL,
  input_data JSONB NOT NULL DEFAULT '{}'::JSONB,
  output_data JSONB NOT NULL DEFAULT '{}'::JSONB,
  activated_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  failure_reason TEXT,
  state_version BIGINT NOT NULL DEFAULT 1,
  CONSTRAINT work_workflow_step_instances_input_object CHECK (jsonb_typeof(input_data)='object'),
  CONSTRAINT work_workflow_step_instances_output_object CHECK (jsonb_typeof(output_data)='object'),
  CONSTRAINT work_workflow_step_instances_state_version_positive CHECK (state_version>0),
  CONSTRAINT work_workflow_step_instances_run_key_uniq UNIQUE(workflow_run_id,step_key)
);
CREATE INDEX idx_work_workflow_step_instances_run_status
  ON public.work_workflow_step_instances(workflow_run_id,status);
CREATE INDEX idx_work_workflow_step_instances_work_item
  ON public.work_workflow_step_instances(work_item_id) WHERE work_item_id IS NOT NULL;

ALTER TABLE public.work_items
  ADD CONSTRAINT work_items_workflow_run_fk
  FOREIGN KEY (workflow_run_id) REFERENCES public.work_workflow_runs(id) ON DELETE RESTRICT;

-- Published workflow definitions are immutable.
CREATE OR REPLACE FUNCTION private.work_block_published_workflow_definition_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
BEGIN
  IF TG_TABLE_NAME='work_workflow_template_versions' THEN
    IF OLD.status='published' THEN RAISE EXCEPTION 'published workflow versions are immutable'; END IF;
  ELSIF TG_TABLE_NAME='work_workflow_step_definitions' THEN
    IF EXISTS (SELECT 1 FROM public.work_workflow_template_versions v WHERE v.id=OLD.template_version_id AND v.status='published') THEN
      RAISE EXCEPTION 'published workflow steps are immutable';
    END IF;
  ELSIF TG_TABLE_NAME='work_workflow_step_dependencies' THEN
    IF EXISTS (SELECT 1 FROM public.work_workflow_template_versions v WHERE v.id=OLD.template_version_id AND v.status='published') THEN
      RAISE EXCEPTION 'published workflow dependencies are immutable';
    END IF;
  END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END;
$$;
CREATE TRIGGER trg_work_workflow_version_immutable
  BEFORE UPDATE OR DELETE ON public.work_workflow_template_versions
  FOR EACH ROW EXECUTE FUNCTION private.work_block_published_workflow_definition_mutation();
CREATE TRIGGER trg_work_workflow_step_immutable
  BEFORE UPDATE OR DELETE ON public.work_workflow_step_definitions
  FOR EACH ROW EXECUTE FUNCTION private.work_block_published_workflow_definition_mutation();
CREATE TRIGGER trg_work_workflow_dependency_immutable
  BEFORE UPDATE OR DELETE ON public.work_workflow_step_dependencies
  FOR EACH ROW EXECUTE FUNCTION private.work_block_published_workflow_definition_mutation();

ALTER TABLE public.work_workflow_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_workflow_template_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_workflow_step_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_workflow_step_dependencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_workflow_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_workflow_step_instances ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.work_workflow_templates FROM anon,authenticated;
REVOKE ALL ON TABLE public.work_workflow_template_versions FROM anon,authenticated;
REVOKE ALL ON TABLE public.work_workflow_step_definitions FROM anon,authenticated;
REVOKE ALL ON TABLE public.work_workflow_step_dependencies FROM anon,authenticated;
REVOKE ALL ON TABLE public.work_workflow_runs FROM anon,authenticated;
REVOKE ALL ON TABLE public.work_workflow_step_instances FROM anon,authenticated;
GRANT SELECT ON TABLE public.work_workflow_templates TO authenticated;
GRANT SELECT ON TABLE public.work_workflow_template_versions TO authenticated;
GRANT SELECT ON TABLE public.work_workflow_step_definitions TO authenticated;
GRANT SELECT ON TABLE public.work_workflow_step_dependencies TO authenticated;
GRANT SELECT ON TABLE public.work_workflow_runs TO authenticated;
GRANT SELECT ON TABLE public.work_workflow_step_instances TO authenticated;

CREATE POLICY work_workflow_templates_select
ON public.work_workflow_templates FOR SELECT TO authenticated
USING (is_active=true OR COALESCE(public.check_permission(auth.uid(),'work.workflows.manage'),false));
CREATE POLICY work_workflow_versions_select
ON public.work_workflow_template_versions FOR SELECT TO authenticated
USING (status='published' OR COALESCE(public.check_permission(auth.uid(),'work.workflows.manage'),false));
CREATE POLICY work_workflow_steps_select
ON public.work_workflow_step_definitions FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.work_workflow_template_versions v
  WHERE v.id=template_version_id AND (v.status='published' OR COALESCE(public.check_permission(auth.uid(),'work.workflows.manage'),false))
));
CREATE POLICY work_workflow_dependencies_select
ON public.work_workflow_step_dependencies FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.work_workflow_template_versions v
  WHERE v.id=template_version_id AND (v.status='published' OR COALESCE(public.check_permission(auth.uid(),'work.workflows.manage'),false))
));
CREATE POLICY work_workflow_runs_select
ON public.work_workflow_runs FOR SELECT TO authenticated
USING (
  started_by_user_id=auth.uid()
  OR (parent_work_item_id IS NOT NULL AND private.work_current_user_can_view_item(parent_work_item_id))
  OR EXISTS (
    SELECT 1 FROM public.work_workflow_step_instances si
    WHERE si.workflow_run_id=id AND si.work_item_id IS NOT NULL AND private.work_current_user_can_view_item(si.work_item_id)
  )
  OR COALESCE(public.check_permission(auth.uid(),'work.workflows.manage'),false)
);
CREATE POLICY work_workflow_step_instances_select
ON public.work_workflow_step_instances FOR SELECT TO authenticated
USING (
  (work_item_id IS NOT NULL AND private.work_current_user_can_view_item(work_item_id))
  OR EXISTS (
    SELECT 1 FROM public.work_workflow_runs r
    WHERE r.id=workflow_run_id AND r.started_by_user_id=auth.uid()
  )
  OR COALESCE(public.check_permission(auth.uid(),'work.workflows.manage'),false)
);

REVOKE ALL ON FUNCTION private.work_block_published_workflow_definition_mutation() FROM PUBLIC,anon,authenticated,service_role;

RESET lock_timeout;
RESET statement_timeout;
