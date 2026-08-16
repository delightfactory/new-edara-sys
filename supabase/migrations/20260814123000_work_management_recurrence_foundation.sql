-- Work Management — recurring work definitions and occurrence ledger.
SET lock_timeout='5s';
SET statement_timeout='60s';

CREATE TYPE public.work_recurrence_frequency AS ENUM ('daily','weekly','monthly');
CREATE TYPE public.work_recurrence_overlap_policy AS ENUM ('strict','single_open');
CREATE TYPE public.work_recurrence_target_kind AS ENUM ('task','workflow');
CREATE TYPE public.work_recurrence_status AS ENUM ('active','paused','stopped');
CREATE TYPE public.work_recurrence_monthly_policy AS ENUM ('exact_day','last_day');
CREATE TYPE public.work_recurrence_workflow_version_policy AS ENUM ('pinned','latest_published');
CREATE TYPE public.work_recurrence_occurrence_status AS ENUM ('pending','generated','overlap','failed','cancelled');

CREATE TABLE public.work_recurrence_definitions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(180) NOT NULL,
  description TEXT,
  target_kind public.work_recurrence_target_kind NOT NULL,
  frequency public.work_recurrence_frequency NOT NULL,
  interval_count INTEGER NOT NULL DEFAULT 1,
  weekdays SMALLINT[],
  day_of_month SMALLINT,
  monthly_policy public.work_recurrence_monthly_policy,
  local_time TIME NOT NULL DEFAULT '09:00',
  timezone TEXT NOT NULL DEFAULT 'Africa/Cairo',
  starts_on DATE NOT NULL,
  ends_on DATE,
  overlap_policy public.work_recurrence_overlap_policy NOT NULL DEFAULT 'strict',
  status public.work_recurrence_status NOT NULL DEFAULT 'active',
  next_occurrence_at TIMESTAMPTZ NOT NULL,

  task_config JSONB NOT NULL DEFAULT '{}'::JSONB,
  workflow_template_id UUID REFERENCES public.work_workflow_templates(id) ON DELETE RESTRICT,
  workflow_version_policy public.work_recurrence_workflow_version_policy,
  pinned_workflow_version_id UUID REFERENCES public.work_workflow_template_versions(id) ON DELETE RESTRICT,

  created_by_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  paused_at TIMESTAMPTZ,
  paused_by_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  stopped_at TIMESTAMPTZ,
  stopped_by_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  state_version BIGINT NOT NULL DEFAULT 1,

  CONSTRAINT work_recurrence_name_not_blank CHECK (btrim(name)<>''),
  CONSTRAINT work_recurrence_interval_positive CHECK (interval_count>0),
  CONSTRAINT work_recurrence_timezone_not_blank CHECK (btrim(timezone)<>''),
  CONSTRAINT work_recurrence_date_window CHECK (ends_on IS NULL OR ends_on>=starts_on),
  CONSTRAINT work_recurrence_state_version_positive CHECK (state_version>0),
  CONSTRAINT work_recurrence_task_config_object CHECK (jsonb_typeof(task_config)='object'),
  CONSTRAINT work_recurrence_weekly_config CHECK (
    (frequency='weekly' AND weekdays IS NOT NULL AND cardinality(weekdays)>0)
    OR (frequency<>'weekly' AND weekdays IS NULL)
  ),
  CONSTRAINT work_recurrence_weekdays_range CHECK (
    weekdays IS NULL OR weekdays <@ ARRAY[1,2,3,4,5,6,7]::SMALLINT[]
  ),
  CONSTRAINT work_recurrence_monthly_config CHECK (
    (frequency='monthly' AND monthly_policy IS NOT NULL AND (
      (monthly_policy='last_day' AND day_of_month IS NULL)
      OR (monthly_policy='exact_day' AND day_of_month BETWEEN 1 AND 31)
    ))
    OR (frequency<>'monthly' AND monthly_policy IS NULL AND day_of_month IS NULL)
  ),
  CONSTRAINT work_recurrence_target_config CHECK (
    (target_kind='task' AND workflow_template_id IS NULL AND workflow_version_policy IS NULL AND pinned_workflow_version_id IS NULL)
    OR
    (target_kind='workflow' AND workflow_template_id IS NOT NULL AND workflow_version_policy IS NOT NULL AND (
      (workflow_version_policy='pinned' AND pinned_workflow_version_id IS NOT NULL)
      OR (workflow_version_policy='latest_published' AND pinned_workflow_version_id IS NULL)
    ))
  )
);
CREATE TRIGGER trg_work_recurrence_definitions_updated_at
  BEFORE UPDATE ON public.work_recurrence_definitions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE INDEX idx_work_recurrence_due
  ON public.work_recurrence_definitions(next_occurrence_at,id)
  WHERE status='active';

CREATE TABLE public.work_recurrence_occurrences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recurrence_definition_id UUID NOT NULL REFERENCES public.work_recurrence_definitions(id) ON DELETE RESTRICT,
  scheduled_for TIMESTAMPTZ NOT NULL,
  status public.work_recurrence_occurrence_status NOT NULL DEFAULT 'pending',
  work_item_id UUID REFERENCES public.work_items(id) ON DELETE SET NULL,
  workflow_run_id UUID REFERENCES public.work_workflow_runs(id) ON DELETE SET NULL,
  overlap_work_item_id UUID REFERENCES public.work_items(id) ON DELETE SET NULL,
  overlap_workflow_run_id UUID REFERENCES public.work_workflow_runs(id) ON DELETE SET NULL,
  error_code VARCHAR(80),
  error_detail TEXT,
  generated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT work_recurrence_occurrence_definition_schedule_uniq UNIQUE(recurrence_definition_id,scheduled_for),
  CONSTRAINT work_recurrence_occurrence_target_exclusive CHECK (
    NOT (work_item_id IS NOT NULL AND workflow_run_id IS NOT NULL)
  ),
  CONSTRAINT work_recurrence_occurrence_overlap_exclusive CHECK (
    NOT (overlap_work_item_id IS NOT NULL AND overlap_workflow_run_id IS NOT NULL)
  ),
  CONSTRAINT work_recurrence_occurrence_generated_binding CHECK (
    (status='generated' AND generated_at IS NOT NULL AND (work_item_id IS NOT NULL OR workflow_run_id IS NOT NULL))
    OR (status<>'generated')
  ),
  CONSTRAINT work_recurrence_occurrence_overlap_binding CHECK (
    (status='overlap' AND generated_at IS NOT NULL AND (overlap_work_item_id IS NOT NULL OR overlap_workflow_run_id IS NOT NULL))
    OR (status<>'overlap')
  )
);
CREATE INDEX idx_work_recurrence_occurrence_definition
  ON public.work_recurrence_occurrences(recurrence_definition_id,scheduled_for DESC);
CREATE INDEX idx_work_recurrence_occurrence_status
  ON public.work_recurrence_occurrences(status,scheduled_for);

ALTER TABLE public.work_items
  ADD CONSTRAINT work_items_recurrence_definition_fk
  FOREIGN KEY (recurrence_definition_id) REFERENCES public.work_recurrence_definitions(id) ON DELETE RESTRICT,
  ADD CONSTRAINT work_items_recurrence_occurrence_fk
  FOREIGN KEY (recurrence_occurrence_id) REFERENCES public.work_recurrence_occurrences(id) ON DELETE RESTRICT;

ALTER TABLE public.work_workflow_runs
  ADD CONSTRAINT work_workflow_runs_recurrence_occurrence_fk
  FOREIGN KEY (recurrence_occurrence_id) REFERENCES public.work_recurrence_occurrences(id) ON DELETE RESTRICT;

CREATE OR REPLACE FUNCTION private.work_recurrence_local_timestamp(
  p_date DATE,
  p_time TIME,
  p_timezone TEXT
) RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
STABLE
SET search_path=''
AS $$
BEGIN
  -- PostgreSQL validates the IANA timezone name at evaluation time.
  RETURN (p_date+p_time) AT TIME ZONE p_timezone;
EXCEPTION WHEN invalid_parameter_value THEN
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION private.work_recurrence_matches_date(
  p_frequency public.work_recurrence_frequency,
  p_interval_count INTEGER,
  p_starts_on DATE,
  p_candidate DATE,
  p_weekdays SMALLINT[],
  p_day_of_month SMALLINT,
  p_monthly_policy public.work_recurrence_monthly_policy
) RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
SET search_path=''
AS $$
DECLARE
  v_months INTEGER;
  v_last_day INTEGER;
BEGIN
  IF p_candidate<p_starts_on THEN RETURN false; END IF;

  IF p_frequency='daily' THEN
    RETURN ((p_candidate-p_starts_on) % p_interval_count)=0;
  END IF;

  IF p_frequency='weekly' THEN
    RETURN ((p_candidate-p_starts_on)/7) % p_interval_count=0
      AND extract(isodow FROM p_candidate)::SMALLINT=ANY(p_weekdays);
  END IF;

  v_months:=(extract(year FROM p_candidate)::INTEGER-extract(year FROM p_starts_on)::INTEGER)*12
    +(extract(month FROM p_candidate)::INTEGER-extract(month FROM p_starts_on)::INTEGER);
  IF v_months<0 OR (v_months % p_interval_count)<>0 THEN RETURN false; END IF;

  IF p_monthly_policy='last_day' THEN
    v_last_day:=extract(day FROM (date_trunc('month',p_candidate::TIMESTAMP)+interval '1 month - 1 day'))::INTEGER;
    RETURN extract(day FROM p_candidate)::INTEGER=v_last_day;
  END IF;

  -- exact_day intentionally skips months that do not contain that date.
  RETURN extract(day FROM p_candidate)::INTEGER=p_day_of_month;
END;
$$;

CREATE OR REPLACE FUNCTION private.work_recurrence_next_occurrence_at(
  p_frequency public.work_recurrence_frequency,
  p_interval_count INTEGER,
  p_starts_on DATE,
  p_ends_on DATE,
  p_weekdays SMALLINT[],
  p_day_of_month SMALLINT,
  p_monthly_policy public.work_recurrence_monthly_policy,
  p_local_time TIME,
  p_timezone TEXT,
  p_after TIMESTAMPTZ
) RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
STABLE
SET search_path=''
AS $$
DECLARE
  v_after_local_date DATE;
  v_start_date DATE;
  v_date DATE;
  v_candidate TIMESTAMPTZ;
  v_limit DATE;
BEGIN
  BEGIN
    v_after_local_date:=(p_after AT TIME ZONE p_timezone)::DATE;
  EXCEPTION WHEN invalid_parameter_value THEN
    RETURN NULL;
  END;

  v_start_date:=greatest(p_starts_on,v_after_local_date-1);
  v_limit:=COALESCE(p_ends_on,v_start_date+interval '6 years')::DATE;

  FOR v_date IN SELECT d::DATE FROM generate_series(v_start_date,v_limit,interval '1 day') AS d LOOP
    IF private.work_recurrence_matches_date(
      p_frequency,p_interval_count,p_starts_on,v_date,p_weekdays,p_day_of_month,p_monthly_policy
    ) THEN
      v_candidate:=private.work_recurrence_local_timestamp(v_date,p_local_time,p_timezone);
      IF v_candidate IS NOT NULL AND v_candidate>p_after THEN RETURN v_candidate; END IF;
    END IF;
  END LOOP;
  RETURN NULL;
END;
$$;

ALTER TABLE public.work_recurrence_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_recurrence_occurrences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.work_recurrence_definitions FROM anon,authenticated;
REVOKE ALL ON TABLE public.work_recurrence_occurrences FROM anon,authenticated;
GRANT SELECT ON TABLE public.work_recurrence_definitions TO authenticated;
GRANT SELECT ON TABLE public.work_recurrence_occurrences TO authenticated;

CREATE POLICY work_recurrence_definitions_select
ON public.work_recurrence_definitions FOR SELECT TO authenticated
USING (
  created_by_user_id=auth.uid()
  OR COALESCE(public.check_permission(auth.uid(),'work.policies.manage'),false)
  OR EXISTS (
    SELECT 1 FROM public.work_recurrence_occurrences o
    WHERE o.recurrence_definition_id=id AND (
      (o.work_item_id IS NOT NULL AND private.work_current_user_can_view_item(o.work_item_id))
      OR (o.overlap_work_item_id IS NOT NULL AND private.work_current_user_can_view_item(o.overlap_work_item_id))
      OR (o.workflow_run_id IS NOT NULL AND private.work_user_can_view_workflow_run(auth.uid(),o.workflow_run_id))
      OR (o.overlap_workflow_run_id IS NOT NULL AND private.work_user_can_view_workflow_run(auth.uid(),o.overlap_workflow_run_id))
    )
  )
);

CREATE POLICY work_recurrence_occurrences_select
ON public.work_recurrence_occurrences FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.work_recurrence_definitions d
    WHERE d.id=recurrence_definition_id AND (
      d.created_by_user_id=auth.uid()
      OR COALESCE(public.check_permission(auth.uid(),'work.policies.manage'),false)
    )
  )
  OR (work_item_id IS NOT NULL AND private.work_current_user_can_view_item(work_item_id))
  OR (overlap_work_item_id IS NOT NULL AND private.work_current_user_can_view_item(overlap_work_item_id))
  OR (workflow_run_id IS NOT NULL AND private.work_user_can_view_workflow_run(auth.uid(),workflow_run_id))
  OR (overlap_workflow_run_id IS NOT NULL AND private.work_user_can_view_workflow_run(auth.uid(),overlap_workflow_run_id))
);

REVOKE ALL ON FUNCTION private.work_recurrence_local_timestamp(DATE,TIME,TEXT) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_recurrence_matches_date(public.work_recurrence_frequency,INTEGER,DATE,DATE,SMALLINT[],SMALLINT,public.work_recurrence_monthly_policy) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_recurrence_next_occurrence_at(public.work_recurrence_frequency,INTEGER,DATE,DATE,SMALLINT[],SMALLINT,public.work_recurrence_monthly_policy,TIME,TEXT,TIMESTAMPTZ) FROM PUBLIC,anon,authenticated,service_role;

RESET lock_timeout;
RESET statement_timeout;
