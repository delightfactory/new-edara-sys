-- Work Management — unified "مطلوب مني الآن" Action Inbox.
-- This is an RLS-aware read model, not a second notification queue.
SET lock_timeout='5s';
SET statement_timeout='60s';

CREATE OR REPLACE VIEW public.work_action_inbox
WITH (security_invoker=true)
AS
-- 1) Current assignee: acknowledge, execute, or perform a due waiting follow-up.
SELECT
  'work:'||w.id::TEXT AS inbox_key,
  CASE
    WHEN w.acknowledgement_required=true AND w.acknowledged_at IS NULL THEN 'acknowledge'
    WHEN w.status='waiting' THEN 'follow_up'
    ELSE 'execute_next_action'
  END::TEXT AS action_kind,
  w.id AS work_item_id,
  w.id AS subject_id,
  w.work_number,
  w.title,
  w.priority,
  w.visibility,
  w.status,
  CASE
    WHEN w.acknowledgement_required=true AND w.acknowledged_at IS NULL THEN w.assigned_at
    WHEN w.status='waiting' THEN w.next_action_at
    ELSE COALESCE(w.next_action_at,w.due_at)
  END AS action_due_at,
  w.state_version AS work_state_version,
  NULL::BIGINT AS approval_state_version,
  '/work/'||w.id::TEXT AS deep_link,
  jsonb_build_object(
    'work_item_id',w.id,
    'expected_version',w.state_version,
    'next_action_text',w.next_action_text
  ) AS action_payload
FROM public.work_items w
WHERE w.current_assignee_user_id=(select auth.uid())
  AND (
    (w.status IN ('open','in_progress'))
    OR (w.status='waiting' AND w.next_action_at IS NOT NULL AND w.next_action_at<=clock_timestamp())
  )

UNION ALL

-- 2) Owner completion review.
SELECT
  'completion_review:'||r.id::TEXT,
  'completion_review'::TEXT,
  w.id,
  r.id,
  w.work_number,
  w.title,
  w.priority,
  w.visibility,
  w.status,
  r.requested_at,
  w.state_version,
  NULL::BIGINT,
  '/work/'||w.id::TEXT,
  jsonb_build_object(
    'work_item_id',w.id,
    'review_id',r.id,
    'expected_version',w.state_version
  )
FROM public.work_completion_reviews r
JOIN public.work_items w ON w.id=r.work_item_id
WHERE r.status='pending'
  AND r.reviewer_user_id=(select auth.uid())

UNION ALL

-- 3) Generic Approval Engine assignment awaiting this effective approver.
SELECT
  'approval:'||a.id::TEXT,
  'approval_decision'::TEXT,
  w.id,
  a.id,
  w.work_number,
  w.title,
  w.priority,
  w.visibility,
  w.status,
  si.due_at,
  w.state_version,
  ar.state_version,
  '/work/'||w.id::TEXT,
  jsonb_build_object(
    'work_item_id',w.id,
    'assignment_id',a.id,
    'approval_request_id',ar.id,
    'expected_approval_version',ar.state_version,
    'acting_for_user_id',CASE
      WHEN a.original_approver_user_id<>a.effective_approver_user_id THEN a.original_approver_user_id
      ELSE NULL
    END
  )
FROM public.work_approval_assignments a
JOIN public.work_approval_stage_instances si ON si.id=a.stage_instance_id
JOIN public.work_approval_requests ar ON ar.id=si.approval_request_id
JOIN public.work_items w ON w.id=ar.work_item_id
WHERE a.status='pending'
  AND si.status='pending'
  AND ar.status='pending'
  AND a.effective_approver_user_id=(select auth.uid())

UNION ALL

-- 4) Request Queue triage. Queue membership alone is insufficient: the explicit
-- triage permission and a manager/triager relationship are both required.
SELECT
  'request_triage:'||r.work_item_id::TEXT,
  'triage_request'::TEXT,
  w.id,
  r.work_item_id,
  w.work_number,
  w.title,
  w.priority,
  w.visibility,
  w.status,
  r.triage_due_at,
  w.state_version,
  NULL::BIGINT,
  '/work/'||w.id::TEXT,
  jsonb_build_object(
    'work_item_id',w.id,
    'queue_id',r.queue_id,
    'request_type_id',r.request_type_id,
    'expected_version',w.state_version
  )
FROM public.work_requests r
JOIN public.work_items w ON w.id=r.work_item_id
JOIN public.work_queues q ON q.id=r.queue_id AND q.is_active=true
LEFT JOIN public.work_queue_members m
  ON m.queue_id=r.queue_id
 AND m.user_id=(select auth.uid())
 AND m.active_from<=clock_timestamp()
 AND (m.active_until IS NULL OR m.active_until>clock_timestamp())
WHERE r.triaged_at IS NULL
  AND w.status NOT IN ('done','cancelled')
  AND COALESCE(public.check_permission((select auth.uid()),'work.requests.triage'),false)
  AND (
    COALESCE(public.check_permission((select auth.uid()),'work.queues.manage'),false)
    OR q.manager_user_id=(select auth.uid())
    OR m.can_triage=true
    OR m.member_role IN ('triager','manager')
  );

GRANT SELECT ON public.work_action_inbox TO authenticated;

CREATE OR REPLACE FUNCTION public.work_get_action_inbox(p_limit INTEGER DEFAULT 100)
RETURNS SETOF public.work_action_inbox
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path=''
AS $$
  SELECT *
  FROM public.work_action_inbox
  ORDER BY
    (action_due_at IS NULL),
    action_due_at ASC NULLS LAST,
    CASE priority
      WHEN 'critical'::public.work_priority THEN 1
      WHEN 'urgent'::public.work_priority THEN 2
      WHEN 'high'::public.work_priority THEN 3
      WHEN 'normal'::public.work_priority THEN 4
      ELSE 5
    END,
    work_number DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit,100),1),200);
$$;

REVOKE ALL ON FUNCTION public.work_get_action_inbox(INTEGER) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.work_get_action_inbox(INTEGER) TO authenticated;

RESET lock_timeout;
RESET statement_timeout;