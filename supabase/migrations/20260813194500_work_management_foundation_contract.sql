-- ============================================================================
-- Work Management — Migration A2: foundation contract completion
--
-- Adds lineage, receipt/audit fields and contract details identified during the
-- schema-to-spec review before any Work migration is applied to production.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE TYPE public.work_source_kind AS ENUM (
  'manual',
  'request_intake',
  'workflow',
  'recurrence',
  'system'
);

CREATE TYPE public.work_dependency_strength AS ENUM (
  'hard',
  'soft'
);

CREATE TYPE public.work_attachment_purpose AS ENUM (
  'reference',
  'evidence',
  'output'
);

ALTER TABLE public.work_items
  ADD COLUMN source_kind public.work_source_kind NOT NULL DEFAULT 'manual',
  ADD COLUMN source_key TEXT,
  ADD COLUMN request_type_id UUID,
  ADD COLUMN workflow_step_key TEXT,
  ADD COLUMN recurrence_occurrence_id UUID,
  ADD COLUMN start_not_before TIMESTAMPTZ,
  ADD COLUMN waiting_on_label VARCHAR(250),
  ADD COLUMN waiting_since TIMESTAMPTZ;

ALTER TABLE public.work_items
  ALTER COLUMN state_version TYPE BIGINT
  USING state_version::BIGINT;

ALTER TABLE public.work_items
  ALTER COLUMN next_action_text TYPE VARCHAR(500)
  USING left(next_action_text, 500);

COMMENT ON COLUMN public.work_items.source_kind IS
  'Origin family: manual, request intake, workflow, recurrence or system.';
COMMENT ON COLUMN public.work_items.source_key IS
  'Optional idempotent source key supplied by a trusted source integration.';
COMMENT ON COLUMN public.work_items.request_type_id IS
  'Placeholder FK added when Work Request types are created.';
COMMENT ON COLUMN public.work_items.recurrence_occurrence_id IS
  'Placeholder FK added when recurrence occurrence records are created.';

CREATE UNIQUE INDEX work_items_source_key_uniq
  ON public.work_items(source_kind, source_key)
  WHERE source_key IS NOT NULL;

CREATE UNIQUE INDEX work_items_recurrence_occurrence_uniq
  ON public.work_items(recurrence_occurrence_id)
  WHERE recurrence_occurrence_id IS NOT NULL;

CREATE INDEX idx_work_items_source_kind_created
  ON public.work_items(source_kind, created_at DESC);

ALTER TABLE public.work_participants
  ADD COLUMN can_comment BOOLEAN NOT NULL DEFAULT true;

DROP INDEX public.work_participants_active_role_uniq;

CREATE UNIQUE INDEX work_participants_active_user_uniq
  ON public.work_participants(work_item_id, user_id)
  WHERE removed_at IS NULL;

ALTER TABLE public.work_events
  ADD COLUMN acting_for_user_id UUID
    REFERENCES public.profiles(id) ON DELETE RESTRICT,
  ADD COLUMN operation_id UUID,
  ADD COLUMN client_event_at TIMESTAMPTZ;

CREATE INDEX idx_work_events_operation
  ON public.work_events(operation_id)
  WHERE operation_id IS NOT NULL;

CREATE INDEX idx_work_events_type_created
  ON public.work_events(event_type, created_at);

ALTER TABLE public.work_dependencies
  ADD COLUMN dependency_strength public.work_dependency_strength NOT NULL DEFAULT 'hard',
  ADD COLUMN resolution_reason TEXT;

COMMENT ON COLUMN public.work_dependencies.dependency_type IS
  'Dependency timing relationship. Migration A currently supports finish-to-start.';
COMMENT ON COLUMN public.work_dependencies.dependency_strength IS
  'Hard dependencies block completion/start rules; soft dependencies are advisory.';

ALTER TABLE public.work_attachments
  ADD COLUMN purpose public.work_attachment_purpose NOT NULL DEFAULT 'reference';

RESET lock_timeout;
RESET statement_timeout;
