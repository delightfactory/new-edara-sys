-- ============================================================================
-- AI Operations Planner — Work Health Case Engine
--
-- DESIGN-TIME MIGRATION ONLY. The native Work Engine remains authoritative.
-- Cases are derived from the same operational semantics used by the deployed
-- Work health view/scanner plus one structural invariant: active execution Work
-- should have an explicit Next Action. No Work record is mutated here.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.work_health_candidates(
  p_as_of TIMESTAMPTZ,
  p_limit INTEGER DEFAULT 50
)
RETURNS TABLE(
  case_key TEXT,
  case_type TEXT,
  attention_class TEXT,
  severity TEXT,
  entity_type TEXT,
  entity_id UUID,
  source_work_item_id UUID,
  owner_user_id UUID,
  owner_employee_id UUID,
  assignee_user_id UUID,
  assignee_employee_id UUID,
  owner_name TEXT,
  assignee_name TEXT,
  owner_active BOOLEAN,
  assignee_active BOOLEAN,
  responsibility_unambiguous BOOLEAN,
  facts JSONB,
  responsibility_evidence JSONB,
  trust JSONB
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
WITH settings AS (
  SELECT *
  FROM public.work_operational_settings
  WHERE singleton=true
), base AS (
  SELECT
    w.*,
    s.due_soon_hours,
    s.stale_after_hours,
    s.state_version AS settings_state_version,
    s.updated_at AS settings_updated_at,
    (w.status IN ('open','in_progress','waiting','pending_approval')) AS is_native_active,
    private.work_operational_item_is_blocked(w.id) AS is_blocked,
    EXISTS(
      SELECT 1
      FROM public.work_escalations e
      WHERE e.work_item_id=w.id AND e.resolved_at IS NULL
    ) AS is_escalated
  FROM public.work_items w
  CROSS JOIN settings s
  WHERE w.status NOT IN ('draft','done','cancelled')
    AND w.visibility='standard'
    -- Prevent Work Health recovery tasks from recursively generating Work Health.
    AND COALESCE(w.metadata->>'ai_domain','')<>'work_health'
), flags AS (
  SELECT
    b.*,
    (b.is_native_active AND b.due_at IS NOT NULL AND b.due_at<p_as_of) AS is_overdue,
    (
      b.status IN ('open','in_progress','pending_approval')
      AND COALESCE(b.last_meaningful_activity_at,b.activated_at,b.created_at)
          < p_as_of-make_interval(hours=>b.stale_after_hours)
    ) AS is_stale,
    (
      b.is_native_active AND b.due_at IS NOT NULL
      AND b.due_at>=p_as_of
      AND b.due_at<=p_as_of+make_interval(hours=>b.due_soon_hours)
    ) AS is_due_soon,
    (
      b.status='waiting'
      AND b.next_action_at IS NOT NULL
      AND b.next_action_at<=p_as_of
    ) AS is_follow_up_due,
    (
      b.status IN ('open','in_progress','waiting')
      AND NULLIF(btrim(COALESCE(b.next_action_text,'')),'') IS NULL
    ) AS is_missing_next_action
  FROM base b
), enriched AS (
  SELECT
    f.*,
    op.full_name::TEXT AS owner_name,
    ap.full_name::TEXT AS assignee_name,
    oe.id AS owner_employee_id,
    ae.id AS assignee_employee_id,
    CASE WHEN f.accountable_owner_user_id IS NULL THEN false
         ELSE private.work_actor_is_active(f.accountable_owner_user_id) END AS owner_active,
    CASE WHEN f.current_assignee_user_id IS NULL THEN false
         ELSE private.work_actor_is_active(f.current_assignee_user_id) END AS assignee_active,
    (
      f.is_native_active
      AND NOT (f.due_at IS NOT NULL AND f.due_at<p_as_of)
      AND (
        (
          f.due_at IS NOT NULL
          AND f.due_at<=p_as_of+make_interval(hours=>f.due_soon_hours)
          AND (f.is_blocked OR f.is_stale)
        )
        OR f.is_follow_up_due
      )
    ) AS is_at_risk
  FROM flags f
  LEFT JOIN public.profiles op ON op.id=f.accountable_owner_user_id
  LEFT JOIN public.profiles ap ON ap.id=f.current_assignee_user_id
  LEFT JOIN LATERAL (
    SELECT e.id
    FROM public.hr_employees e
    WHERE e.user_id=f.accountable_owner_user_id AND e.status::TEXT='active'
    ORDER BY e.updated_at DESC NULLS LAST,e.id
    LIMIT 1
  ) oe ON true
  LEFT JOIN LATERAL (
    SELECT e.id
    FROM public.hr_employees e
    WHERE e.user_id=f.current_assignee_user_id AND e.status::TEXT='active'
    ORDER BY e.updated_at DESC NULLS LAST,e.id
    LIMIT 1
  ) ae ON true
), selected AS (
  SELECT
    e.*,
    CASE
      WHEN e.is_overdue THEN 'overdue_work'
      WHEN e.is_blocked THEN 'blocked_work'
      WHEN e.is_follow_up_due THEN 'waiting_follow_up_due'
      WHEN e.is_stale THEN 'stale_work'
      ELSE 'missing_next_action'
    END::TEXT AS selected_case_type
  FROM enriched e
  WHERE e.is_overdue OR e.is_blocked OR e.is_follow_up_due
     OR e.is_stale OR e.is_missing_next_action
)
SELECT
  'work_health:'||s.id::TEXT AS case_key,
  s.selected_case_type AS case_type,
  'exception'::TEXT AS attention_class,
  CASE
    WHEN s.is_overdue AND s.priority='urgent' THEN 'critical'
    WHEN s.is_overdue OR s.is_blocked THEN 'high'
    ELSE 'medium'
  END::TEXT AS severity,
  'work_item'::TEXT AS entity_type,
  s.id AS entity_id,
  s.id AS source_work_item_id,
  s.accountable_owner_user_id AS owner_user_id,
  s.owner_employee_id,
  s.current_assignee_user_id AS assignee_user_id,
  s.assignee_employee_id,
  s.owner_name,
  s.assignee_name,
  s.owner_active,
  s.assignee_active,
  (s.accountable_owner_user_id IS NOT NULL AND s.owner_active) AS responsibility_unambiguous,
  jsonb_build_object(
    'work_item_id',s.id,
    'work_number',s.work_number,
    'title',left(COALESCE(s.title,''),240),
    'status',s.status::TEXT,
    'priority',s.priority::TEXT,
    'source_kind',s.source_kind::TEXT,
    'source_key',s.source_key,
    'branch_id',s.branch_id,
    'owning_department_id',s.owning_department_id,
    'state_version',s.state_version,
    'activated_at',s.activated_at,
    'assigned_at',s.assigned_at,
    'due_at',s.due_at,
    'first_due_at',s.first_due_at,
    'next_action_text',left(COALESCE(s.next_action_text,''),500),
    'next_action_at',s.next_action_at,
    'waiting_since',s.waiting_since,
    'waiting_reason',left(COALESCE(s.waiting_reason,''),500),
    'blocked_reason',left(COALESCE(s.blocked_reason,''),500),
    'last_meaningful_activity_at',s.last_meaningful_activity_at,
    'is_overdue',s.is_overdue,
    'is_blocked',s.is_blocked,
    'is_stale',s.is_stale,
    'is_escalated',s.is_escalated,
    'is_due_soon',s.is_due_soon,
    'is_follow_up_due',s.is_follow_up_due,
    'is_at_risk',s.is_at_risk,
    'is_missing_next_action',s.is_missing_next_action,
    'overdue_hours',CASE WHEN s.is_overdue
      THEN round((extract(epoch FROM (p_as_of-s.due_at))/3600.0)::NUMERIC,2)
      ELSE NULL END,
    'stale_hours',round((extract(epoch FROM (
      p_as_of-COALESCE(s.last_meaningful_activity_at,s.activated_at,s.created_at)
    ))/3600.0)::NUMERIC,2),
    'due_soon_hours',s.due_soon_hours,
    'stale_after_hours',s.stale_after_hours,
    'settings_state_version',s.settings_state_version,
    'settings_updated_at',s.settings_updated_at,
    -- The source Work itself is the active Work contract for ESCALATE.
    'existing_active_work',jsonb_build_object(
      'work_item_id',s.id,'work_number',s.work_number,'status',s.status::TEXT
    )
  ) AS facts,
  jsonb_build_object(
    'routing_rule','source_work_accountable_owner_owns_recovery',
    'owner_user_id',s.accountable_owner_user_id,
    'owner_employee_id',s.owner_employee_id,
    'owner_name',s.owner_name,
    'owner_active',s.owner_active,
    'assignee_user_id',s.current_assignee_user_id,
    'assignee_employee_id',s.assignee_employee_id,
    'assignee_name',s.assignee_name,
    'assignee_active',s.assignee_active,
    'responsibility_unambiguous',
      (s.accountable_owner_user_id IS NOT NULL AND s.owner_active),
    'create_work_owner_user_id',s.accountable_owner_user_id,
    'create_work_assignee_user_id',s.accountable_owner_user_id
  ) AS responsibility_evidence,
  jsonb_build_object(
    'source_contract','work-health-v1',
    'deterministic',true,
    'source_as_of',p_as_of,
    'native_operational_flags_semantics',true,
    'due_soon_hours',s.due_soon_hours,
    'stale_after_hours',s.stale_after_hours,
    'missing_next_action_is_structural_invariant',true,
    'private_visibility_excluded',true,
    'work_health_recovery_recursion_excluded',true,
    'source_work_mutation_performed',false
  ) AS trust
FROM selected s
ORDER BY
  CASE
    WHEN s.is_overdue AND s.priority='urgent' THEN 0
    WHEN s.is_overdue THEN 1
    WHEN s.is_blocked THEN 2
    WHEN s.is_follow_up_due THEN 3
    WHEN s.is_stale THEN 4
    ELSE 5
  END,
  COALESCE(s.due_at,s.next_action_at,s.last_meaningful_activity_at,s.created_at),
  s.work_number,s.id
LIMIT LEAST(GREATEST(COALESCE(p_limit,50),1),2000);
$$;

REVOKE ALL ON FUNCTION ai_ops.work_health_candidates(TIMESTAMPTZ,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.work_health_candidates(TIMESTAMPTZ,INTEGER) IS
  'Read-only Work Health candidates using deployed overdue/stale/blocked/follow-up semantics plus an explicit Next Action invariant; one dominant Case per source Work item, standard visibility only.';

RESET lock_timeout;
RESET statement_timeout;
