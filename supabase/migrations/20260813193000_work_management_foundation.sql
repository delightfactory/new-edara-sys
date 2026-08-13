-- ============================================================================
-- Work Management / Work Engine — Migration A: Foundation
--
-- Scope:
--   * canonical Work Item root
--   * participants, timeline events, comments/mentions
--   * checklists, dependencies, entity links and attachment metadata
--   * foundational constraints, indexes and fail-closed RLS posture
--
-- Intentionally NOT included here:
--   * application RLS policies / permissions (Migration B)
--   * atomic state-transition RPCs (Migration C)
--   * requests/queues, approvals, workflows, policies, recurrence or UI
--
-- Safety:
--   * no existing business table is repurposed
--   * no production data is rewritten
--   * browser roles receive no access until Migration B
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

-- Closed value sets use PostgreSQL enums, matching established project practice.
CREATE TYPE public.work_item_kind AS ENUM (
  'task',
  'request',
  'workflow_step'
);

CREATE TYPE public.work_item_status AS ENUM (
  'draft',
  'open',
  'in_progress',
  'waiting_internal',
  'waiting_external',
  'blocked',
  'pending_approval',
  'done',
  'cancelled'
);

CREATE TYPE public.work_priority AS ENUM (
  'low',
  'normal',
  'high',
  'urgent',
  'critical'
);

CREATE TYPE public.work_visibility AS ENUM (
  'standard',
  'restricted',
  'private'
);

CREATE TYPE public.work_completion_mode AS ENUM (
  'assignee_closes',
  'owner_review',
  'approval'
);

CREATE TYPE public.work_actor_kind AS ENUM (
  'user',
  'system'
);

CREATE TYPE public.work_participant_role AS ENUM (
  'follower',
  'collaborator',
  'observer'
);

CREATE TYPE public.work_comment_kind AS ENUM (
  'comment',
  'progress_update'
);

CREATE TYPE public.work_dependency_type AS ENUM (
  'finish_to_start'
);

-- --------------------------------------------------------------------------
-- Canonical Work Item root.
--
-- Future-module references are UUID placeholders in Migration A by design.
-- Their foreign keys are added only after their target tables exist.
-- --------------------------------------------------------------------------
CREATE TABLE public.work_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_number BIGINT GENERATED ALWAYS AS IDENTITY,

  kind public.work_item_kind NOT NULL DEFAULT 'task',
  title VARCHAR(250) NOT NULL,
  description TEXT,
  expected_outcome TEXT,

  completion_summary TEXT,
  completion_output JSONB NOT NULL DEFAULT '{}'::JSONB,
  completed_by_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,

  acknowledgement_required BOOLEAN NOT NULL DEFAULT false,
  assigned_at TIMESTAMPTZ,
  first_viewed_at TIMESTAMPTZ,
  acknowledged_at TIMESTAMPTZ,

  blocks_parent_completion BOOLEAN NOT NULL DEFAULT true,
  completion_approval_template_id UUID,

  status public.work_item_status NOT NULL DEFAULT 'draft',
  priority public.work_priority NOT NULL DEFAULT 'normal',
  visibility public.work_visibility NOT NULL DEFAULT 'standard',

  creator_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  requester_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  accountable_owner_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  current_assignee_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,

  source_department_id UUID REFERENCES public.hr_departments(id) ON DELETE SET NULL,
  owning_department_id UUID REFERENCES public.hr_departments(id) ON DELETE SET NULL,
  branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL,

  queue_id UUID,
  parent_work_item_id UUID REFERENCES public.work_items(id) ON DELETE RESTRICT,

  template_id UUID,
  workflow_run_id UUID,
  policy_id UUID,
  recurrence_definition_id UUID,

  activated_at TIMESTAMPTZ,
  started_at TIMESTAMPTZ,
  due_at TIMESTAMPTZ,
  first_due_at TIMESTAMPTZ,
  next_action_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  archived_at TIMESTAMPTZ,
  reopened_at TIMESTAMPTZ,

  waiting_on_type TEXT,
  waiting_on_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  waiting_on_entity_type TEXT,
  waiting_on_entity_id UUID,
  waiting_reason TEXT,

  next_action_text TEXT,
  blocked_reason TEXT,

  completion_mode public.work_completion_mode NOT NULL DEFAULT 'assignee_closes',
  reassign_on_inactive BOOLEAN NOT NULL DEFAULT true,

  metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
  state_version INTEGER NOT NULL DEFAULT 1,
  last_meaningful_activity_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT work_items_work_number_key UNIQUE (work_number),
  CONSTRAINT work_items_title_not_blank CHECK (btrim(title) <> ''),
  CONSTRAINT work_items_state_version_positive CHECK (state_version > 0),
  CONSTRAINT work_items_not_own_parent CHECK (
    parent_work_item_id IS NULL OR parent_work_item_id <> id
  ),
  CONSTRAINT work_items_metadata_object CHECK (
    jsonb_typeof(metadata) = 'object'
  ),
  CONSTRAINT work_items_completion_output_object CHECK (
    jsonb_typeof(completion_output) = 'object'
  ),
  CONSTRAINT work_items_waiting_on_type_check CHECK (
    waiting_on_type IS NULL
    OR waiting_on_type IN (
      'user',
      'department',
      'queue',
      'external_party',
      'entity',
      'other'
    )
  ),
  CONSTRAINT work_items_waiting_entity_pair_check CHECK (
    (waiting_on_entity_type IS NULL AND waiting_on_entity_id IS NULL)
    OR
    (waiting_on_entity_type IS NOT NULL AND waiting_on_entity_id IS NOT NULL)
  )
);

COMMENT ON TABLE public.work_items IS
  'Canonical actionable-work root for Tasks, Requests and active Workflow Steps.';
COMMENT ON COLUMN public.work_items.work_number IS
  'Stable human-facing sequence component. Display code may format this with the created year.';
COMMENT ON COLUMN public.work_items.queue_id IS
  'Migration A placeholder; FK is added when work_queues exists.';
COMMENT ON COLUMN public.work_items.template_id IS
  'Migration A placeholder; FK is added when task/work templates exist.';
COMMENT ON COLUMN public.work_items.workflow_run_id IS
  'Migration A placeholder; FK is added when workflow runtime tables exist.';
COMMENT ON COLUMN public.work_items.policy_id IS
  'Migration A placeholder; FK is added when work policies exist.';
COMMENT ON COLUMN public.work_items.recurrence_definition_id IS
  'Migration A placeholder; FK is added when recurrence definitions exist.';
COMMENT ON COLUMN public.work_items.completion_approval_template_id IS
  'Migration A placeholder; FK is added when approval templates exist.';
COMMENT ON COLUMN public.work_items.blocks_parent_completion IS
  'When true, a non-terminal child blocks completion of its parent.';
COMMENT ON COLUMN public.work_items.last_meaningful_activity_at IS
  'Operational activity clock; merely viewing the item must not advance it.';

CREATE TRIGGER trg_work_items_updated_at
  BEFORE UPDATE ON public.work_items
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- --------------------------------------------------------------------------
-- Participants: persistent visibility/collaboration roles, separate from
-- assignment and mentions.
-- --------------------------------------------------------------------------
CREATE TABLE public.work_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_item_id UUID NOT NULL
    REFERENCES public.work_items(id) ON DELETE CASCADE,
  user_id UUID NOT NULL
    REFERENCES public.profiles(id) ON DELETE RESTRICT,
  participant_role public.work_participant_role NOT NULL,
  added_by_user_id UUID
    REFERENCES public.profiles(id) ON DELETE SET NULL,
  added_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  removed_at TIMESTAMPTZ,
  removed_by_user_id UUID
    REFERENCES public.profiles(id) ON DELETE SET NULL,
  CONSTRAINT work_participants_removed_order_check CHECK (
    removed_at IS NULL OR removed_at >= added_at
  )
);

CREATE UNIQUE INDEX work_participants_active_role_uniq
  ON public.work_participants(work_item_id, user_id, participant_role)
  WHERE removed_at IS NULL;

-- --------------------------------------------------------------------------
-- Comments and formal progress updates.
-- --------------------------------------------------------------------------
CREATE TABLE public.work_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_item_id UUID NOT NULL
    REFERENCES public.work_items(id) ON DELETE CASCADE,
  author_user_id UUID
    REFERENCES public.profiles(id) ON DELETE RESTRICT,
  comment_kind public.work_comment_kind NOT NULL DEFAULT 'comment',
  body TEXT NOT NULL,
  edited_at TIMESTAMPTZ,
  redacted_at TIMESTAMPTZ,
  redacted_by_user_id UUID
    REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT work_comments_body_not_blank CHECK (btrim(body) <> ''),
  CONSTRAINT work_comments_id_work_item_key UNIQUE (id, work_item_id)
);

COMMENT ON TABLE public.work_comments IS
  'Human discussion and explicit progress updates. Rows are retained; later policies redact instead of deleting.';

CREATE TABLE public.work_mentions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_item_id UUID NOT NULL
    REFERENCES public.work_items(id) ON DELETE CASCADE,
  comment_id UUID NOT NULL,
  mentioned_user_id UUID NOT NULL
    REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_by_user_id UUID
    REFERENCES public.profiles(id) ON DELETE SET NULL,
  notified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT work_mentions_comment_same_item_fk
    FOREIGN KEY (comment_id, work_item_id)
    REFERENCES public.work_comments(id, work_item_id)
    ON DELETE CASCADE,
  CONSTRAINT work_mentions_comment_user_key
    UNIQUE (comment_id, mentioned_user_id)
);

COMMENT ON TABLE public.work_mentions IS
  'Persistent parsed mentions. A mention never grants Work Item visibility.';

-- --------------------------------------------------------------------------
-- Immutable business timeline source. event_type remains TEXT intentionally:
-- later modules add event families without altering a database enum.
-- --------------------------------------------------------------------------
CREATE TABLE public.work_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_item_id UUID NOT NULL
    REFERENCES public.work_items(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  actor_user_id UUID
    REFERENCES public.profiles(id) ON DELETE RESTRICT,
  actor_kind public.work_actor_kind NOT NULL DEFAULT 'user',
  from_status public.work_item_status,
  to_status public.work_item_status,
  payload JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT work_events_type_not_blank CHECK (btrim(event_type) <> ''),
  CONSTRAINT work_events_payload_object CHECK (jsonb_typeof(payload) = 'object'),
  CONSTRAINT work_events_user_actor_check CHECK (
    actor_kind <> 'user' OR actor_user_id IS NOT NULL
  )
);

COMMENT ON TABLE public.work_events IS
  'Canonical append-only operational timeline. Mutation permissions are defined in Migration B/C.';

-- --------------------------------------------------------------------------
-- Checklist / Definition-of-Done support.
-- --------------------------------------------------------------------------
CREATE TABLE public.work_checklist_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_item_id UUID NOT NULL
    REFERENCES public.work_items(id) ON DELETE CASCADE,
  label TEXT NOT NULL,
  is_required BOOLEAN NOT NULL DEFAULT false,
  sort_order INTEGER NOT NULL DEFAULT 0,
  completed_at TIMESTAMPTZ,
  completed_by_user_id UUID
    REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_by_user_id UUID
    REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT work_checklist_items_label_not_blank CHECK (btrim(label) <> ''),
  CONSTRAINT work_checklist_items_sort_order_nonnegative CHECK (sort_order >= 0)
);

-- --------------------------------------------------------------------------
-- Blocking dependencies. Cycle prevention belongs to the atomic RPC layer,
-- where deterministic locks can make the recursive check concurrency-safe.
-- --------------------------------------------------------------------------
CREATE TABLE public.work_dependencies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  blocked_work_item_id UUID NOT NULL
    REFERENCES public.work_items(id) ON DELETE CASCADE,
  blocker_work_item_id UUID NOT NULL
    REFERENCES public.work_items(id) ON DELETE CASCADE,
  dependency_type public.work_dependency_type NOT NULL DEFAULT 'finish_to_start',
  created_by_user_id UUID
    REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ,
  resolved_by_user_id UUID
    REFERENCES public.profiles(id) ON DELETE SET NULL,
  CONSTRAINT work_dependencies_not_self CHECK (
    blocked_work_item_id <> blocker_work_item_id
  )
);

CREATE UNIQUE INDEX work_dependencies_active_pair_uniq
  ON public.work_dependencies(blocked_work_item_id, blocker_work_item_id)
  WHERE resolved_at IS NULL;

-- --------------------------------------------------------------------------
-- Generic entity links. Valid entity types, existence and caller visibility
-- are enforced by controlled RPCs in later migrations.
-- --------------------------------------------------------------------------
CREATE TABLE public.work_links (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_item_id UUID NOT NULL
    REFERENCES public.work_items(id) ON DELETE CASCADE,
  entity_type TEXT NOT NULL,
  entity_id UUID NOT NULL,
  relation_type TEXT NOT NULL DEFAULT 'relates_to',
  label TEXT,
  created_by_user_id UUID
    REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT work_links_entity_type_not_blank CHECK (btrim(entity_type) <> ''),
  CONSTRAINT work_links_relation_type_not_blank CHECK (btrim(relation_type) <> ''),
  CONSTRAINT work_links_item_entity_relation_key
    UNIQUE (work_item_id, entity_type, entity_id, relation_type)
);

-- --------------------------------------------------------------------------
-- Attachment metadata only. Storage bucket creation/policies are a later
-- migration, but the metadata path is already bound to its Work Item.
-- --------------------------------------------------------------------------
CREATE TABLE public.work_attachments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_item_id UUID NOT NULL
    REFERENCES public.work_items(id) ON DELETE CASCADE,
  comment_id UUID,
  storage_bucket TEXT NOT NULL DEFAULT 'work-attachments',
  storage_path TEXT NOT NULL,
  original_filename TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  size_bytes BIGINT NOT NULL,
  uploaded_by_user_id UUID
    REFERENCES public.profiles(id) ON DELETE SET NULL,
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  removed_at TIMESTAMPTZ,
  removed_by_user_id UUID
    REFERENCES public.profiles(id) ON DELETE SET NULL,
  CONSTRAINT work_attachments_comment_same_item_fk
    FOREIGN KEY (comment_id, work_item_id)
    REFERENCES public.work_comments(id, work_item_id)
    ON DELETE CASCADE,
  CONSTRAINT work_attachments_bucket_check CHECK (
    storage_bucket = 'work-attachments'
  ),
  CONSTRAINT work_attachments_path_not_blank CHECK (btrim(storage_path) <> ''),
  CONSTRAINT work_attachments_path_bound_to_item_check CHECK (
    storage_path LIKE ('work/' || work_item_id::TEXT || '/%')
  ),
  CONSTRAINT work_attachments_filename_not_blank CHECK (
    btrim(original_filename) <> ''
  ),
  CONSTRAINT work_attachments_mime_not_blank CHECK (btrim(mime_type) <> ''),
  CONSTRAINT work_attachments_size_nonnegative CHECK (size_bytes >= 0),
  CONSTRAINT work_attachments_storage_object_key
    UNIQUE (storage_bucket, storage_path)
);

-- --------------------------------------------------------------------------
-- Operational/RLS read-path indexes.
-- --------------------------------------------------------------------------
CREATE INDEX idx_work_items_assignee_status
  ON public.work_items(current_assignee_user_id, status)
  WHERE current_assignee_user_id IS NOT NULL;

CREATE INDEX idx_work_items_owner_status
  ON public.work_items(accountable_owner_user_id, status)
  WHERE accountable_owner_user_id IS NOT NULL;

CREATE INDEX idx_work_items_queue_status
  ON public.work_items(queue_id, status)
  WHERE queue_id IS NOT NULL;

CREATE INDEX idx_work_items_status_due
  ON public.work_items(status, due_at)
  WHERE due_at IS NOT NULL;

CREATE INDEX idx_work_items_status_next_action
  ON public.work_items(status, next_action_at)
  WHERE next_action_at IS NOT NULL;

CREATE INDEX idx_work_items_branch_department
  ON public.work_items(branch_id, owning_department_id);

CREATE INDEX idx_work_items_last_meaningful_activity
  ON public.work_items(last_meaningful_activity_at)
  WHERE last_meaningful_activity_at IS NOT NULL;

CREATE INDEX idx_work_items_workflow_run
  ON public.work_items(workflow_run_id)
  WHERE workflow_run_id IS NOT NULL;

CREATE INDEX idx_work_items_policy
  ON public.work_items(policy_id)
  WHERE policy_id IS NOT NULL;

CREATE INDEX idx_work_items_title_trgm
  ON public.work_items USING GIN (title public.gin_trgm_ops);

CREATE INDEX idx_work_participants_active_user_item
  ON public.work_participants(user_id, work_item_id)
  WHERE removed_at IS NULL;

CREATE INDEX idx_work_participants_item
  ON public.work_participants(work_item_id);

CREATE INDEX idx_work_comments_item_cursor
  ON public.work_comments(work_item_id, created_at, id);

CREATE INDEX idx_work_mentions_item
  ON public.work_mentions(work_item_id);

CREATE INDEX idx_work_mentions_user_unnotified
  ON public.work_mentions(mentioned_user_id, notified_at);

CREATE INDEX idx_work_events_item_cursor
  ON public.work_events(work_item_id, created_at, id);

CREATE INDEX idx_work_checklist_required_open
  ON public.work_checklist_items(work_item_id, is_required, completed_at);

CREATE INDEX idx_work_dependencies_blocked_open
  ON public.work_dependencies(blocked_work_item_id, resolved_at);

CREATE INDEX idx_work_dependencies_blocker_open
  ON public.work_dependencies(blocker_work_item_id, resolved_at);

CREATE INDEX idx_work_links_item
  ON public.work_links(work_item_id);

CREATE INDEX idx_work_links_entity
  ON public.work_links(entity_type, entity_id);

CREATE INDEX idx_work_attachments_item
  ON public.work_attachments(work_item_id, uploaded_at);

CREATE INDEX idx_work_attachments_comment
  ON public.work_attachments(comment_id)
  WHERE comment_id IS NOT NULL;

CREATE INDEX idx_work_items_parent
  ON public.work_items(parent_work_item_id)
  WHERE parent_work_item_id IS NOT NULL;

-- --------------------------------------------------------------------------
-- Fail closed until Migration B installs the permission-aware SELECT policies.
-- State-changing browser operations remain RPC-only in Migration C.
-- --------------------------------------------------------------------------
ALTER TABLE public.work_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_mentions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_checklist_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_dependencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_attachments ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.work_items FROM anon, authenticated;
REVOKE ALL ON TABLE public.work_participants FROM anon, authenticated;
REVOKE ALL ON TABLE public.work_comments FROM anon, authenticated;
REVOKE ALL ON TABLE public.work_mentions FROM anon, authenticated;
REVOKE ALL ON TABLE public.work_events FROM anon, authenticated;
REVOKE ALL ON TABLE public.work_checklist_items FROM anon, authenticated;
REVOKE ALL ON TABLE public.work_dependencies FROM anon, authenticated;
REVOKE ALL ON TABLE public.work_links FROM anon, authenticated;
REVOKE ALL ON TABLE public.work_attachments FROM anon, authenticated;

-- Internal/service operations remain possible while browser access is closed.
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.work_items TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.work_participants TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.work_comments TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.work_mentions TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.work_events TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.work_checklist_items TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.work_dependencies TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.work_links TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.work_attachments TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.work_items_work_number_seq TO service_role;

RESET lock_timeout;
RESET statement_timeout;
