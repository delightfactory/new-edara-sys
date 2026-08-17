-- ============================================================================
-- AI Operations Planner — Seven-Domain Global Budget + HR Availability Actionability
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

ALTER FUNCTION ai_ops.build_operational_snapshot(UUID,INTEGER)
  RENAME TO build_operational_snapshot_six_domain_v1;
REVOKE ALL ON FUNCTION ai_ops.build_operational_snapshot_six_domain_v1(UUID,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.build_operational_snapshot(
  p_run_id UUID,
  p_case_limit INTEGER DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_run ai_ops.planner_runs%ROWTYPE;
  v_settings ai_ops.settings%ROWTYPE;
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_limit INTEGER;
  v_credit_demand INTEGER:=0; v_sales_demand INTEGER:=0; v_customer_demand INTEGER:=0;
  v_inventory_demand INTEGER:=0; v_field_demand INTEGER:=0; v_work_demand INTEGER:=0; v_hr_demand INTEGER:=0;
  v_alloc JSONB:='{}'::JSONB;
  v_six_budget INTEGER:=0; v_hr_alloc INTEGER:=0; v_existing_cases INTEGER:=0; v_remaining INTEGER:=0;
  v_context_bound BOOLEAN:=false; v_hr_has_candidate BOOLEAN:=false;
  v_base JSONB; v_hr_build JSONB; v_total INTEGER:=0; v_domain_captures JSONB:='[]'::JSONB;
  v_probe_as_of TIMESTAMPTZ:=clock_timestamp();
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('ai_ops:operational_snapshot:'||p_run_id::TEXT,0));
  SELECT * INTO v_run FROM ai_ops.planner_runs WHERE id=p_run_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ai_ops planner run not found: %',p_run_id; END IF;
  SELECT * INTO v_settings FROM ai_ops.settings WHERE singleton=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations settings are not initialized'; END IF;
  v_limit:=LEAST(GREATEST(COALESCE(p_case_limit,v_settings.max_cases_per_snapshot),1),v_settings.max_cases_per_snapshot);

  SELECT * INTO v_snapshot FROM ai_ops.snapshots WHERE run_id=p_run_id;
  IF FOUND THEN
    IF EXISTS (SELECT 1 FROM ai_ops.snapshot_domain_captures dc WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='hr_availability') THEN
      IF NOT (SELECT COUNT(*)=7 FROM ai_ops.snapshot_domain_captures dc
        WHERE dc.snapshot_id=v_snapshot.id
          AND dc.domain=ANY(ARRAY['receivables','sales','customer_health','inventory','field_execution','work_health','hr_availability']::TEXT[])) THEN
        RAISE EXCEPTION 'existing seven-domain snapshot is missing a required immutable domain capture marker';
      END IF;
      SELECT COUNT(*)::INTEGER INTO v_total FROM ai_ops.snapshot_cases sc WHERE sc.snapshot_id=v_snapshot.id;
      IF v_total>v_limit THEN RAISE EXCEPTION 'existing snapshot case count % exceeds global limit %',v_total,v_limit; END IF;
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'domain',dc.domain,'capture_status',dc.capture_status,'case_count',dc.case_count,
        'evidence_bytes',dc.evidence_bytes,'capture_version',dc.capture_version,
        'business_date',dc.business_date,'source_as_of',dc.source_as_of,'metadata',dc.metadata
      ) ORDER BY array_position(ai_ops.required_operational_domains(),dc.domain),dc.domain),'[]'::JSONB)
      INTO v_domain_captures FROM ai_ops.snapshot_domain_captures dc WHERE dc.snapshot_id=v_snapshot.id;
      RETURN jsonb_build_object('snapshot_id',v_snapshot.id,'run_id',p_run_id,'business_date',v_run.business_date,
        'global_case_limit',v_limit,'captured_cases',v_total,'idempotent_reuse',true,'domain_captures',v_domain_captures);
    END IF;

    IF NOT (SELECT COUNT(*)=6 FROM ai_ops.snapshot_domain_captures dc
      WHERE dc.snapshot_id=v_snapshot.id AND dc.domain=ANY(ARRAY['receivables','sales','customer_health','inventory','field_execution','work_health']::TEXT[])) THEN
      RAISE EXCEPTION 'existing operational snapshot is missing a required pre-HR domain capture marker';
    END IF;
    v_context_bound:=NULLIF(v_run.result_summary->>'worker_context_hash','') IS NOT NULL;
    IF v_context_bound THEN RAISE EXCEPTION 'existing snapshot is already bound to a worker context and cannot add HR Availability'; END IF;
    SELECT COUNT(*)::INTEGER INTO v_existing_cases FROM ai_ops.snapshot_cases sc WHERE sc.snapshot_id=v_snapshot.id;
    v_remaining:=GREATEST(v_limit-v_existing_cases,0);
    SELECT COUNT(*)::INTEGER INTO v_hr_demand
    FROM ai_ops.hr_availability_candidates(v_run.business_date,v_snapshot.data_as_of,2000);
    v_hr_alloc:=LEAST(v_hr_demand,v_remaining);
  ELSE
    IF v_run.status NOT IN ('pending','claimed','reasoning') THEN
      RAISE EXCEPTION 'planner run status does not allow snapshot build: %',v_run.status;
    END IF;
    SELECT LEAST(COUNT(*)::INTEGER,v_limit) INTO v_credit_demand
    FROM public.sales_orders so
    WHERE so.status IN ('delivered'::public.sales_order_status,'partially_delivered'::public.sales_order_status)
      AND so.payment_terms IN ('credit','mixed') AND so.delivered_at IS NOT NULL AND so.due_date IS NOT NULL
      AND so.due_date<v_run.business_date
      AND GREATEST(0::NUMERIC,COALESCE(so.total_amount,0)-COALESCE(so.paid_amount,0)-COALESCE(so.returned_amount,0))>0;
    SELECT COUNT(*)::INTEGER INTO v_sales_demand FROM ai_ops.sales_target_candidates(v_run.business_date,v_limit);
    SELECT COUNT(*)::INTEGER INTO v_customer_demand FROM ai_ops.customer_health_candidates(v_run.business_date,2000);
    SELECT COUNT(*)::INTEGER INTO v_inventory_demand FROM ai_ops.inventory_candidates(v_run.business_date,2000);
    SELECT COUNT(*)::INTEGER INTO v_field_demand FROM ai_ops.field_execution_candidates(v_run.business_date,2000);
    SELECT COUNT(*)::INTEGER INTO v_work_demand FROM ai_ops.work_health_candidates(v_probe_as_of,2000);
    SELECT COUNT(*)::INTEGER INTO v_hr_demand FROM ai_ops.hr_availability_candidates(v_run.business_date,v_probe_as_of,2000);

    v_alloc:=ai_ops.allocate_domain_case_budget(v_limit,jsonb_build_object(
      'receivables',v_credit_demand,'sales',v_sales_demand,'customer_health',v_customer_demand,
      'inventory',v_inventory_demand,'field_execution',v_field_demand,'work_health',v_work_demand,
      'hr_availability',v_hr_demand),
      ARRAY['receivables','sales','customer_health','inventory','field_execution','work_health','hr_availability']::TEXT[]);
    v_six_budget:=COALESCE((v_alloc->>'receivables')::INTEGER,0)+COALESCE((v_alloc->>'sales')::INTEGER,0)+
      COALESCE((v_alloc->>'customer_health')::INTEGER,0)+COALESCE((v_alloc->>'inventory')::INTEGER,0)+
      COALESCE((v_alloc->>'field_execution')::INTEGER,0)+COALESCE((v_alloc->>'work_health')::INTEGER,0);
    v_hr_alloc:=COALESCE((v_alloc->>'hr_availability')::INTEGER,0);

    v_base:=ai_ops.build_operational_snapshot_six_domain_v1(p_run_id,GREATEST(v_six_budget,1));
    SELECT * INTO v_snapshot FROM ai_ops.snapshots WHERE run_id=p_run_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'snapshot missing after preserved six-domain base build'; END IF;
    IF NOT (SELECT COUNT(*)=6 FROM ai_ops.snapshot_domain_captures dc
      WHERE dc.snapshot_id=v_snapshot.id AND dc.domain=ANY(ARRAY['receivables','sales','customer_health','inventory','field_execution','work_health']::TEXT[])) THEN
      RAISE EXCEPTION 'preserved six-domain builder did not produce all required capture markers';
    END IF;
    SELECT COUNT(*)::INTEGER INTO v_existing_cases FROM ai_ops.snapshot_cases sc WHERE sc.snapshot_id=v_snapshot.id;
    v_remaining:=GREATEST(v_limit-v_existing_cases,0);
    -- Re-read HR demand against the exact immutable snapshot data_as_of.
    SELECT COUNT(*)::INTEGER INTO v_hr_demand
    FROM ai_ops.hr_availability_candidates(v_run.business_date,v_snapshot.data_as_of,2000);
    -- Rebind the final HR allocation to the exact frozen snapshot timestamp and
    -- consume only genuinely remaining capacity. If the preserved six-domain
    -- build under-used its quota, HR may safely consume that residual budget.
    v_hr_alloc:=LEAST(v_hr_demand,v_remaining);
  END IF;

  IF v_hr_alloc>0 THEN
    v_hr_build:=ai_ops.refresh_hr_availability_cases(v_snapshot.id,v_run.business_date,v_hr_alloc);
  ELSE
    v_hr_has_candidate:=v_hr_demand>0;
    INSERT INTO ai_ops.snapshot_domain_captures(
      snapshot_id,domain,capture_version,source_as_of,business_date,case_count,evidence_bytes,capture_status,metadata
    ) VALUES (
      v_snapshot.id,'hr_availability','hr-availability-v1',v_snapshot.data_as_of,v_run.business_date,0,0,
      CASE WHEN v_hr_has_candidate THEN 'partial' ELSE 'completed' END,
      jsonb_build_object('capture_marker_written',true,'global_budget_exhausted',v_hr_has_candidate,
        'global_case_limit',v_limit,'allocated_case_limit',0,'case_limit',0,'has_more',v_hr_has_candidate,
        'planning_horizon_days',14,'missing_punch_never_infers_absence',true,
        'employee_performance_scoring',false,'hr_mutation_performed',false,'source_work_mutation_performed',false)
    );
  END IF;

  SELECT COUNT(*)::INTEGER INTO v_total FROM ai_ops.snapshot_cases sc WHERE sc.snapshot_id=v_snapshot.id;
  IF v_total>v_limit THEN RAISE EXCEPTION 'seven-domain snapshot case count % exceeds global limit %',v_total,v_limit; END IF;
  IF NOT (SELECT COUNT(*)=7 FROM ai_ops.snapshot_domain_captures dc WHERE dc.snapshot_id=v_snapshot.id
    AND dc.domain=ANY(ARRAY['receivables','sales','customer_health','inventory','field_execution','work_health','hr_availability']::TEXT[])) THEN
    RAISE EXCEPTION 'operational snapshot did not produce all seven immutable domain capture markers';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'domain',dc.domain,'capture_status',dc.capture_status,'case_count',dc.case_count,
    'evidence_bytes',dc.evidence_bytes,'capture_version',dc.capture_version,
    'business_date',dc.business_date,'source_as_of',dc.source_as_of,'metadata',dc.metadata
  ) ORDER BY CASE dc.domain WHEN 'receivables' THEN 0 WHEN 'sales' THEN 1 WHEN 'customer_health' THEN 2
    WHEN 'inventory' THEN 3 WHEN 'field_execution' THEN 4 WHEN 'work_health' THEN 5 WHEN 'hr_availability' THEN 6 ELSE 7 END,dc.domain),'[]'::JSONB)
  INTO v_domain_captures FROM ai_ops.snapshot_domain_captures dc WHERE dc.snapshot_id=v_snapshot.id;

  RETURN jsonb_build_object('snapshot_id',v_snapshot.id,'run_id',p_run_id,'business_date',v_run.business_date,
    'global_case_limit',v_limit,'hr_availability_demand',v_hr_demand,'hr_availability_allocated_limit',v_hr_alloc,
    'captured_cases',v_total,'idempotent_reuse',false,'domain_captures',v_domain_captures,
    'operational_mutation_performed',false);
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.build_operational_snapshot(UUID,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.required_operational_domains()
RETURNS TEXT[] LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT ARRAY['receivables','sales','customer_health','inventory','field_execution','work_health','hr_availability']::TEXT[];
$$;
REVOKE ALL ON FUNCTION ai_ops.required_operational_domains() FROM PUBLIC,anon,authenticated,service_role;

ALTER FUNCTION ai_ops.selected_case_capture_allows_action(UUID)
  RENAME TO selected_case_capture_allows_action_six_domain_v1;
REVOKE ALL ON FUNCTION ai_ops.selected_case_capture_allows_action_six_domain_v1(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.selected_case_capture_allows_action(p_decision_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_domain TEXT; v_decision_type TEXT; v_run_date DATE;
  v_snapshot_id UUID; v_snapshot_status TEXT; v_snapshot_as_of TIMESTAMPTZ;
  v_sc_source TIMESTAMPTZ; v_payload INTEGER;
  v_version TEXT; v_status TEXT; v_capture_source TIMESTAMPTZ; v_capture_date DATE;
  v_case_count INTEGER; v_evidence BIGINT; v_meta JSONB;
  v_frozen_count INTEGER; v_frozen_bytes BIGINT;
BEGIN
  SELECT sc.domain,d.decision_type,r.business_date,s.id,s.snapshot_status,s.data_as_of,sc.source_as_of,sc.payload_bytes
  INTO v_domain,v_decision_type,v_run_date,v_snapshot_id,v_snapshot_status,v_snapshot_as_of,v_sc_source,v_payload
  FROM ai_ops.decisions d JOIN ai_ops.planner_runs r ON r.id=d.run_id
  JOIN ai_ops.snapshots s ON s.run_id=d.run_id
  JOIN ai_ops.snapshot_cases sc ON sc.snapshot_id=s.id AND sc.case_id=d.case_id
  WHERE d.id=p_decision_id;
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_domain<>'hr_availability' THEN
    RETURN ai_ops.selected_case_capture_allows_action_six_domain_v1(p_decision_id);
  END IF;
  IF v_decision_type NOT IN ('CREATE_WORK','ESCALATE') OR v_snapshot_status<>'ready'
     OR COALESCE(v_payload,0)<=0 OR v_sc_source IS DISTINCT FROM v_snapshot_as_of THEN RETURN false; END IF;

  SELECT dc.capture_version,dc.capture_status,dc.source_as_of,dc.business_date,dc.case_count,dc.evidence_bytes,dc.metadata
  INTO v_version,v_status,v_capture_source,v_capture_date,v_case_count,v_evidence,v_meta
  FROM ai_ops.snapshot_domain_captures dc WHERE dc.snapshot_id=v_snapshot_id AND dc.domain='hr_availability';
  IF NOT FOUND OR v_version<>'hr-availability-v1' OR v_status NOT IN ('completed','partial')
     OR v_capture_source IS DISTINCT FROM v_snapshot_as_of OR v_capture_date IS DISTINCT FROM v_run_date
     OR COALESCE(v_case_count,0)<=0 OR COALESCE(v_evidence,0)<=0 THEN RETURN false; END IF;

  SELECT COUNT(*)::INTEGER,COALESCE(SUM(sc.payload_bytes),0)::BIGINT
  INTO v_frozen_count,v_frozen_bytes FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id=v_snapshot_id AND sc.domain='hr_availability';
  IF v_frozen_count IS DISTINCT FROM v_case_count OR v_frozen_bytes IS DISTINCT FROM v_evidence THEN RETURN false; END IF;
  IF COALESCE((v_meta->>'global_budget_exhausted')::BOOLEAN,false) THEN RETURN false; END IF;
  IF v_status='completed' AND COALESCE((v_meta->>'has_more')::BOOLEAN,false) THEN RETURN false; END IF;
  IF v_status='partial' AND (
    NOT COALESCE((v_meta->>'has_more')::BOOLEAN,false)
    OR NULLIF(v_meta->>'case_limit','') IS NULL
    OR (v_meta->>'case_limit')::INTEGER<=0
  ) THEN RETURN false; END IF;
  RETURN true;
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
  RETURN false;
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.selected_case_capture_allows_action(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.build_operational_snapshot(UUID,INTEGER) IS
  'Canonical seven-domain snapshot builder with one hard deterministic budget and exact immutable HR Availability capture.';
COMMENT ON FUNCTION ai_ops.required_operational_domains() IS
  'Canonical worker/staging coverage registry for seven AI Operations domains including HR Availability.';
COMMENT ON FUNCTION ai_ops.selected_case_capture_allows_action(UUID) IS
  'Shared selected-case actionability gate extended explicitly to trusted hr-availability-v1 bounded capture semantics.';

RESET lock_timeout;
RESET statement_timeout;
