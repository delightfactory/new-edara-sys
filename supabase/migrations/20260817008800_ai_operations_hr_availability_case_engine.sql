-- ============================================================================
-- AI Operations Planner — HR / Availability Case Engine
--
-- DESIGN-TIME MIGRATION ONLY. HR remains authoritative for employment,
-- schedules, approved leave and explicit attendance state. This domain detects
-- allocation conflicts only; it does not infer absence from missing punches,
-- score employees, mutate HR, or reassign source Work automatically.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.hr_availability_candidates(
  p_business_date DATE,
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
  affected_employee_id UUID,
  affected_user_id UUID,
  coverage_owner_user_id UUID,
  coverage_owner_employee_id UUID,
  coverage_owner_name TEXT,
  coverage_owner_active BOOLEAN,
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
WITH active_work AS (
  SELECT
    w.*,
    (w.due_at AT TIME ZONE 'Africa/Cairo')::DATE AS due_date_local,
    (w.next_action_at AT TIME ZONE 'Africa/Cairo')::DATE AS next_action_date_local
  FROM public.work_items w
  WHERE w.status IN ('open','in_progress','waiting','pending_approval')
    AND w.visibility='standard'
    AND w.current_assignee_user_id IS NOT NULL
    AND COALESCE(w.metadata->>'ai_domain','')<>'hr_availability'
), employee_work AS (
  SELECT
    w.*,
    e.id AS employee_id,
    e.user_id AS employee_user_id,
    e.full_name AS employee_name,
    e.status::TEXT AS employee_status,
    e.branch_id AS employee_branch_id,
    e.department_id AS employee_department_id,
    e.direct_manager_id,
    CASE
      WHEN w.due_date_local IS NOT NULL AND w.due_date_local<=p_business_date THEN p_business_date
      WHEN w.next_action_date_local IS NOT NULL AND w.next_action_date_local<=p_business_date THEN p_business_date
      ELSE LEAST(
        CASE WHEN w.due_date_local BETWEEN p_business_date AND p_business_date+14 THEN w.due_date_local END,
        CASE WHEN w.next_action_date_local BETWEEN p_business_date AND p_business_date+14 THEN w.next_action_date_local END
      )
    END AS availability_date
  FROM active_work w
  JOIN LATERAL (
    SELECT emp.*
    FROM public.hr_employees emp
    WHERE emp.user_id=w.current_assignee_user_id
      AND emp.status::TEXT IN ('active','on_leave')
    ORDER BY emp.updated_at DESC NULLS LAST,emp.id
    LIMIT 1
  ) e ON true
), relevant AS (
  SELECT * FROM employee_work WHERE availability_date IS NOT NULL
), availability AS (
  SELECT
    r.*,
    sched.is_working_day,
    sched.scheduled_start_at,
    sched.scheduled_end_at,
    sched.scheduled_minutes,
    sched.schedule_source,
    leave_row.id AS leave_request_id,
    leave_row.start_date AS leave_start_date,
    leave_row.end_date AS leave_end_date,
    attendance.id AS attendance_day_id,
    attendance.status::TEXT AS attendance_status,
    attendance.review_status::TEXT AS attendance_review_status,
    manager.id AS manager_employee_id,
    manager.user_id AS manager_user_id,
    manager.full_name AS manager_name,
    CASE WHEN r.accountable_owner_user_id IS NULL THEN false
         ELSE private.work_actor_is_active(r.accountable_owner_user_id) END AS source_owner_active,
    CASE WHEN manager.user_id IS NULL THEN false
         ELSE private.work_actor_is_active(manager.user_id) END AS manager_active
  FROM relevant r
  LEFT JOIN LATERAL public.get_employee_work_schedule(r.employee_id,r.availability_date) sched ON true
  LEFT JOIN LATERAL (
    SELECT lr.id,lr.start_date,lr.end_date
    FROM public.hr_leave_requests lr
    WHERE lr.employee_id=r.employee_id
      AND lr.status::TEXT='approved'
      AND r.availability_date BETWEEN lr.start_date AND lr.end_date
    ORDER BY lr.start_date,lr.id
    LIMIT 1
  ) leave_row ON true
  LEFT JOIN LATERAL (
    SELECT ad.id,ad.status,ad.review_status
    FROM public.hr_attendance_days ad
    WHERE ad.employee_id=r.employee_id
      AND ad.work_date=r.availability_date
    ORDER BY ad.updated_at DESC NULLS LAST,ad.id
    LIMIT 1
  ) attendance ON true
  LEFT JOIN public.hr_employees manager ON manager.id=r.direct_manager_id
), flagged AS (
  SELECT
    a.*,
    CASE
      WHEN a.leave_request_id IS NOT NULL THEN 'approved_leave_allocation_conflict'
      WHEN a.employee_status='on_leave' THEN 'employee_status_unavailable'
      WHEN a.availability_date=p_business_date
       AND a.attendance_status IN ('on_leave','absent_authorized','absent_unauthorized','weekly_off','public_holiday')
        THEN 'explicit_attendance_unavailable'
      WHEN COALESCE(a.is_working_day,false)=false THEN 'nonworking_schedule_allocation_conflict'
      ELSE NULL
    END AS selected_case_type,
    CASE
      WHEN a.accountable_owner_user_id IS NOT NULL
       AND a.accountable_owner_user_id<>a.employee_user_id
       AND a.source_owner_active
        THEN a.accountable_owner_user_id
      WHEN a.manager_user_id IS NOT NULL AND a.manager_user_id<>a.employee_user_id AND a.manager_active
        THEN a.manager_user_id
      ELSE NULL
    END AS routed_owner_user_id,
    CASE
      WHEN a.accountable_owner_user_id IS NOT NULL
       AND a.accountable_owner_user_id<>a.employee_user_id
       AND a.source_owner_active
        THEN (
          SELECT he.id FROM public.hr_employees he
          WHERE he.user_id=a.accountable_owner_user_id AND he.status::TEXT='active'
          ORDER BY he.updated_at DESC NULLS LAST,he.id LIMIT 1
        )
      WHEN a.manager_user_id IS NOT NULL AND a.manager_user_id<>a.employee_user_id AND a.manager_active
        THEN a.manager_employee_id
      ELSE NULL
    END AS routed_owner_employee_id,
    CASE
      WHEN a.accountable_owner_user_id IS NOT NULL
       AND a.accountable_owner_user_id<>a.employee_user_id
       AND a.source_owner_active
        THEN (SELECT p.full_name::TEXT FROM public.profiles p WHERE p.id=a.accountable_owner_user_id)
      WHEN a.manager_user_id IS NOT NULL AND a.manager_user_id<>a.employee_user_id AND a.manager_active THEN a.manager_name::TEXT
      ELSE NULL
    END AS routed_owner_name
  FROM availability a
), selected AS (
  SELECT * FROM flagged WHERE selected_case_type IS NOT NULL
)
SELECT
  'hr_availability:'||s.id::TEXT||':'||s.employee_id::TEXT||':'||s.availability_date::TEXT AS case_key,
  s.selected_case_type AS case_type,
  'continuity'::TEXT AS attention_class,
  CASE
    WHEN s.availability_date<=p_business_date+1
      OR (s.due_at IS NOT NULL AND s.due_at<p_as_of)
      OR (s.next_action_at IS NOT NULL AND s.next_action_at<=p_as_of)
      THEN 'high'
    ELSE 'medium'
  END::TEXT AS severity,
  'employee'::TEXT AS entity_type,
  s.employee_id AS entity_id,
  s.id AS source_work_item_id,
  s.employee_id AS affected_employee_id,
  s.employee_user_id AS affected_user_id,
  s.routed_owner_user_id AS coverage_owner_user_id,
  s.routed_owner_employee_id AS coverage_owner_employee_id,
  s.routed_owner_name AS coverage_owner_name,
  CASE WHEN s.routed_owner_user_id IS NULL THEN false
       ELSE private.work_actor_is_active(s.routed_owner_user_id) END AS coverage_owner_active,
  (
    s.routed_owner_user_id IS NOT NULL
    AND private.work_actor_is_active(s.routed_owner_user_id)
  ) AS responsibility_unambiguous,
  jsonb_build_object(
    'source_work_item_id',s.id,
    'work_number',s.work_number,
    'work_title',left(COALESCE(s.title,''),240),
    'work_status',s.status::TEXT,
    'work_priority',s.priority::TEXT,
    'work_state_version',s.state_version,
    'work_due_at',s.due_at,
    'work_next_action_at',s.next_action_at,
    'work_next_action_text',left(COALESCE(s.next_action_text,''),500),
    'branch_id',COALESCE(s.branch_id,s.employee_branch_id),
    'owning_department_id',COALESCE(s.owning_department_id,s.employee_department_id),
    'affected_employee_id',s.employee_id,
    'affected_user_id',s.employee_user_id,
    'affected_employee_name',s.employee_name,
    'employee_status',s.employee_status,
    'availability_date',s.availability_date,
    'availability_reason',s.selected_case_type,
    'schedule_is_working_day',s.is_working_day,
    'schedule_source',s.schedule_source,
    'scheduled_start_at',s.scheduled_start_at,
    'scheduled_end_at',s.scheduled_end_at,
    'scheduled_minutes',s.scheduled_minutes,
    'leave_request_id',s.leave_request_id,
    'leave_start_date',s.leave_start_date,
    'leave_end_date',s.leave_end_date,
    'attendance_day_id',s.attendance_day_id,
    'attendance_status',s.attendance_status,
    'attendance_review_status',s.attendance_review_status,
    'direct_manager_employee_id',s.manager_employee_id,
    'direct_manager_user_id',s.manager_user_id,
    'source_accountable_owner_user_id',s.accountable_owner_user_id,
    'source_current_assignee_user_id',s.current_assignee_user_id,
    'missing_attendance_row_treated_as_absence',false
  ) AS facts,
  jsonb_build_object(
    'routing_rule','active_source_owner_else_direct_manager_controls_short_term_coverage',
    'affected_employee_id',s.employee_id,
    'affected_user_id',s.employee_user_id,
    'source_accountable_owner_user_id',s.accountable_owner_user_id,
    'direct_manager_employee_id',s.manager_employee_id,
    'direct_manager_user_id',s.manager_user_id,
    'coverage_owner_user_id',s.routed_owner_user_id,
    'coverage_owner_employee_id',s.routed_owner_employee_id,
    'coverage_owner_name',s.routed_owner_name,
    'coverage_owner_active',
      CASE WHEN s.routed_owner_user_id IS NULL THEN false
           ELSE private.work_actor_is_active(s.routed_owner_user_id) END,
    'responsibility_unambiguous',
      (s.routed_owner_user_id IS NOT NULL AND private.work_actor_is_active(s.routed_owner_user_id)),
    'create_work_owner_user_id',s.routed_owner_user_id,
    'create_work_assignee_user_id',s.routed_owner_user_id
  ) AS responsibility_evidence,
  jsonb_build_object(
    'source_contract','hr-availability-v1',
    'deterministic',true,
    'business_date',p_business_date,
    'source_as_of',p_as_of,
    'schedule_authority','public.get_employee_work_schedule',
    'approved_leave_only',true,
    'explicit_attendance_unavailability_only',true,
    'missing_punch_never_infers_absence',true,
    'employee_performance_scoring',false,
    'contact_or_identity_pii_included',false,
    'hr_mutation_performed',false,
    'source_work_mutation_performed',false
  ) AS trust
FROM selected s
ORDER BY
  CASE WHEN s.availability_date<=p_business_date THEN 0
       WHEN s.availability_date=p_business_date+1 THEN 1 ELSE 2 END,
  CASE s.selected_case_type
    WHEN 'approved_leave_allocation_conflict' THEN 0
    WHEN 'employee_status_unavailable' THEN 1
    WHEN 'explicit_attendance_unavailable' THEN 2
    ELSE 3
  END,
  COALESCE(s.due_at,s.next_action_at),s.work_number,s.id
LIMIT LEAST(GREATEST(COALESCE(p_limit,50),1),2000);
$$;

REVOKE ALL ON FUNCTION ai_ops.hr_availability_candidates(DATE,TIMESTAMPTZ,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.hr_availability_candidates(DATE,TIMESTAMPTZ,INTEGER) IS
  'Read-only HR/Availability allocation-conflict candidates using official schedules, approved leave and explicit attendance states; missing punches never imply absence and no HR/Work mutation occurs.';

RESET lock_timeout;
RESET statement_timeout;
