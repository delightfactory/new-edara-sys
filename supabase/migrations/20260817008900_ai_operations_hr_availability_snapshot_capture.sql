-- ============================================================================
-- AI Operations Planner — HR / Availability Immutable Snapshot Capture
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.refresh_hr_availability_cases(
  p_snapshot_id UUID,
  p_business_date DATE,
  p_limit INTEGER DEFAULT 50
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_candidate RECORD;
  v_case_id UUID;
  v_case_status TEXT;
  v_case_payload_bytes INTEGER;
  v_context_total INTEGER;
  v_context_captured INTEGER;
  v_context JSONB;
  v_count INTEGER:=0;
  v_evidence_bytes BIGINT:=0;
  v_context_rows INTEGER:=0;
  v_context_truncated_cases INTEGER:=0;
  v_capture_status TEXT:='completed';
  v_has_more BOOLEAN:=false;
  v_rank_offset INTEGER:=0;
  v_effective_limit INTEGER:=LEAST(GREATEST(COALESCE(p_limit,50),1),500);
  v_case_type_counts JSONB:='{}'::JSONB;
BEGIN
  SELECT * INTO v_snapshot FROM ai_ops.snapshots WHERE id=p_snapshot_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ai_ops snapshot not found: %',p_snapshot_id; END IF;

  IF EXISTS (
    SELECT 1 FROM ai_ops.snapshot_domain_captures dc
    WHERE dc.snapshot_id=p_snapshot_id AND dc.domain='hr_availability'
  ) THEN
    RAISE EXCEPTION 'ai_ops hr_availability domain already captured: %',p_snapshot_id;
  END IF;

  IF EXISTS (
    SELECT 1 FROM ai_ops.snapshot_cases sc
    WHERE sc.snapshot_id=p_snapshot_id AND sc.domain='hr_availability'
  ) THEN
    RAISE EXCEPTION 'ai_ops hr_availability evidence exists without capture marker: %',p_snapshot_id;
  END IF;

  SELECT COALESCE(MAX(sc.snapshot_rank),0)
  INTO v_rank_offset
  FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id=p_snapshot_id;

  SELECT COUNT(*)>v_effective_limit
  INTO v_has_more
  FROM ai_ops.hr_availability_candidates(
    p_business_date,v_snapshot.data_as_of,LEAST(v_effective_limit+1,2000)
  );

  IF v_snapshot.snapshot_status='blocked' THEN
    v_capture_status:='blocked';
  ELSIF v_snapshot.snapshot_status='partial' OR v_has_more THEN
    v_capture_status:='partial';
  END IF;

  FOR v_candidate IN
    SELECT * FROM ai_ops.hr_availability_candidates(
      p_business_date,v_snapshot.data_as_of,v_effective_limit
    )
  LOOP
    v_count:=v_count+1;
    v_case_type_counts:=jsonb_set(
      v_case_type_counts,ARRAY[v_candidate.case_type],
      to_jsonb(COALESCE((v_case_type_counts->>v_candidate.case_type)::INTEGER,0)+1),true
    );

    INSERT INTO ai_ops.cases(
      case_key,first_snapshot_id,last_snapshot_id,domain,case_type,
      entity_type,entity_id,attention_class,severity,first_seen_at,last_seen_at,
      source_as_of,facts,responsibility_evidence,trust,status,state_version,updated_at
    ) VALUES (
      v_candidate.case_key,p_snapshot_id,p_snapshot_id,'hr_availability',
      v_candidate.case_type,v_candidate.entity_type,v_candidate.entity_id,
      v_candidate.attention_class,v_candidate.severity,
      v_snapshot.generated_at,v_snapshot.generated_at,v_snapshot.data_as_of,
      v_candidate.facts,v_candidate.responsibility_evidence,v_candidate.trust,
      'open',1,clock_timestamp()
    )
    ON CONFLICT(case_key) DO UPDATE
    SET
      last_snapshot_id=EXCLUDED.last_snapshot_id,
      case_type=EXCLUDED.case_type,
      attention_class=EXCLUDED.attention_class,
      severity=EXCLUDED.severity,
      last_seen_at=EXCLUDED.last_seen_at,
      source_as_of=EXCLUDED.source_as_of,
      facts=EXCLUDED.facts,
      responsibility_evidence=EXCLUDED.responsibility_evidence,
      trust=EXCLUDED.trust,
      status=CASE
        WHEN ai_ops.cases.status IN ('resolved','expired') THEN 'open'
        WHEN ai_ops.cases.status='suppressed'
          AND ai_ops.cases.suppressed_until IS NOT NULL
          AND ai_ops.cases.suppressed_until>clock_timestamp() THEN 'suppressed'
        ELSE ai_ops.cases.status
      END,
      state_version=ai_ops.cases.state_version+1,
      updated_at=clock_timestamp()
    RETURNING id,status INTO v_case_id,v_case_status;

    SELECT COUNT(*)::INTEGER
    INTO v_context_total
    FROM ai_ops.operational_context oc
    WHERE oc.status='active'
      AND oc.valid_from<=v_snapshot.data_as_of
      AND (oc.valid_until IS NULL OR oc.valid_until>v_snapshot.data_as_of)
      AND oc.visibility IN ('management','standard')
      AND (oc.confidence_class<>'ai_inference' OR oc.approved_by_user_id IS NOT NULL)
      AND (
        (oc.subject_type='employee' AND oc.subject_id=v_candidate.affected_employee_id)
        OR (v_candidate.coverage_owner_employee_id IS NOT NULL
          AND oc.subject_type='employee' AND oc.subject_id=v_candidate.coverage_owner_employee_id)
        OR (NULLIF(v_candidate.facts->>'branch_id','') IS NOT NULL
          AND oc.subject_type='branch' AND oc.subject_id=(v_candidate.facts->>'branch_id')::UUID)
        OR (NULLIF(v_candidate.facts->>'owning_department_id','') IS NOT NULL
          AND oc.subject_type='department' AND oc.subject_id=(v_candidate.facts->>'owning_department_id')::UUID)
      );

    SELECT COALESCE(jsonb_agg(context_item ORDER BY priority_rank,updated_at DESC,context_id),'[]'::JSONB)
    INTO v_context
    FROM (
      SELECT
        oc.id AS context_id,oc.updated_at,
        CASE oc.confidence_class
          WHEN 'hard_policy' THEN 1 WHEN 'approved_human' THEN 2
          WHEN 'explicit_human' THEN 3 WHEN 'system_record' THEN 4
          WHEN 'system_inference' THEN 5 ELSE 6
        END AS priority_rank,
        jsonb_build_object(
          'id',oc.id,'subject_type',oc.subject_type,'subject_id',oc.subject_id,
          'context_type',oc.context_type,
          'summary',left(COALESCE(NULLIF(oc.context_payload->>'summary',''),oc.context_type),500),
          'owner_user_id',oc.owner_user_id,'owner_label',owner_profile.full_name,
          'source_type',oc.source_type,'confidence_class',oc.confidence_class,
          'lifecycle_type',oc.lifecycle_type,'valid_from',oc.valid_from,
          'valid_until',oc.valid_until,'review_on',oc.review_on,
          'visibility',oc.visibility,'content_trust','governed_untrusted_text'
        ) AS context_item
      FROM ai_ops.operational_context oc
      LEFT JOIN public.profiles owner_profile ON owner_profile.id=oc.owner_user_id
      WHERE oc.status='active'
        AND oc.valid_from<=v_snapshot.data_as_of
        AND (oc.valid_until IS NULL OR oc.valid_until>v_snapshot.data_as_of)
        AND oc.visibility IN ('management','standard')
        AND (oc.confidence_class<>'ai_inference' OR oc.approved_by_user_id IS NOT NULL)
        AND (
          (oc.subject_type='employee' AND oc.subject_id=v_candidate.affected_employee_id)
          OR (v_candidate.coverage_owner_employee_id IS NOT NULL
            AND oc.subject_type='employee' AND oc.subject_id=v_candidate.coverage_owner_employee_id)
          OR (NULLIF(v_candidate.facts->>'branch_id','') IS NOT NULL
            AND oc.subject_type='branch' AND oc.subject_id=(v_candidate.facts->>'branch_id')::UUID)
          OR (NULLIF(v_candidate.facts->>'owning_department_id','') IS NOT NULL
            AND oc.subject_type='department' AND oc.subject_id=(v_candidate.facts->>'owning_department_id')::UUID)
        )
      ORDER BY priority_rank,oc.updated_at DESC,oc.id
      LIMIT 5
    ) bounded_context;

    v_context_captured:=jsonb_array_length(v_context);
    v_context_rows:=v_context_rows+v_context_captured;
    IF v_context_total>v_context_captured THEN
      v_context_truncated_cases:=v_context_truncated_cases+1;
    END IF;
    v_context:=jsonb_build_object(
      'items',v_context,'total',v_context_total,'captured',v_context_captured,
      'truncated',v_context_total>v_context_captured,'max_per_case',5
    );

    v_case_payload_bytes:=octet_length(convert_to(
      jsonb_build_object(
        'case_key',v_candidate.case_key,'domain','hr_availability',
        'case_type',v_candidate.case_type,'attention_class',v_candidate.attention_class,
        'severity',v_candidate.severity,'facts',v_candidate.facts,
        'responsibility_evidence',v_candidate.responsibility_evidence,
        'operational_context',v_context,'trust',v_candidate.trust
      )::TEXT,'UTF8'
    ));

    INSERT INTO ai_ops.snapshot_cases(
      snapshot_id,case_id,case_key,snapshot_rank,domain,case_type,
      entity_type,entity_id,attention_class,severity,case_status,source_as_of,
      facts,responsibility_evidence,operational_context,trust,payload_bytes
    ) VALUES (
      p_snapshot_id,v_case_id,v_candidate.case_key,v_rank_offset+v_count,
      'hr_availability',v_candidate.case_type,v_candidate.entity_type,v_candidate.entity_id,
      v_candidate.attention_class,v_candidate.severity,v_case_status,
      v_snapshot.data_as_of,v_candidate.facts,v_candidate.responsibility_evidence,
      v_context,v_candidate.trust,v_case_payload_bytes
    );
    v_evidence_bytes:=v_evidence_bytes+v_case_payload_bytes;
  END LOOP;

  INSERT INTO ai_ops.snapshot_domain_captures(
    snapshot_id,domain,capture_version,source_as_of,business_date,
    case_count,evidence_bytes,capture_status,metadata
  ) VALUES (
    p_snapshot_id,'hr_availability','hr-availability-v1',
    v_snapshot.data_as_of,p_business_date,v_count,v_evidence_bytes,v_capture_status,
    jsonb_build_object(
      'case_types',jsonb_build_array(
        'approved_leave_allocation_conflict','employee_status_unavailable',
        'explicit_attendance_unavailable','nonworking_schedule_allocation_conflict'
      ),
      'case_type_counts',v_case_type_counts,
      'case_limit',v_effective_limit,'has_more',v_has_more,
      'planning_horizon_days',14,
      'context_rows_captured',v_context_rows,
      'context_truncated_cases',v_context_truncated_cases,
      'missing_punch_never_infers_absence',true,
      'employee_performance_scoring',false,
      'hr_mutation_performed',false,'source_work_mutation_performed',false
    )
  );

  RETURN jsonb_build_object(
    'snapshot_id',p_snapshot_id,'business_date',p_business_date,
    'domain','hr_availability','capture_status',v_capture_status,
    'candidates_upserted',v_count,'case_type_counts',v_case_type_counts,
    'snapshot_evidence_rows',v_count,'snapshot_evidence_bytes',v_evidence_bytes,
    'context_rows_captured',v_context_rows,
    'context_truncated_cases',v_context_truncated_cases,
    'has_more',v_has_more,'capture_marker_written',true,
    'hr_mutation_performed',false,'source_work_mutation_performed',false
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.refresh_hr_availability_cases(UUID,DATE,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.refresh_hr_availability_cases(UUID,DATE,INTEGER) IS
  'Single-shot immutable HR/Availability capture using exact snapshot data_as_of and bounded governed employee/coverage context; HR and source Work remain read-only.';

RESET lock_timeout;
RESET statement_timeout;
