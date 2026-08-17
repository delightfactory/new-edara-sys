-- ============================================================================
-- AI Operations Planner — Six-Domain Global Budget + Work Health Actionability
--
-- DESIGN-TIME MIGRATION ONLY. Adds Work Health to the one hard Case budget,
-- extends the explicit bounded-partial actionability contract to work-health-v1,
-- and updates the shared required-domain registry used by worker context/staging.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

ALTER FUNCTION ai_ops.build_operational_snapshot(UUID,INTEGER)
  RENAME TO build_operational_snapshot_five_domain_v1;
REVOKE ALL ON FUNCTION ai_ops.build_operational_snapshot_five_domain_v1(UUID,INTEGER)
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
  v_credit_capture ai_ops.snapshot_domain_captures%ROWTYPE;
  v_sales_capture ai_ops.snapshot_domain_captures%ROWTYPE;
  v_customer_capture ai_ops.snapshot_domain_captures%ROWTYPE;
  v_inventory_capture ai_ops.snapshot_domain_captures%ROWTYPE;
  v_field_capture ai_ops.snapshot_domain_captures%ROWTYPE;
  v_work_capture ai_ops.snapshot_domain_captures%ROWTYPE;
  v_limit INTEGER;
  v_credit_demand INTEGER:=0;
  v_sales_demand INTEGER:=0;
  v_customer_demand INTEGER:=0;
  v_inventory_demand INTEGER:=0;
  v_field_demand INTEGER:=0;
  v_work_demand INTEGER:=0;
  v_allocations JSONB:='{}'::JSONB;
  v_credit_alloc INTEGER:=0;
  v_sales_alloc INTEGER:=0;
  v_customer_alloc INTEGER:=0;
  v_inventory_alloc INTEGER:=0;
  v_field_alloc INTEGER:=0;
  v_work_alloc INTEGER:=0;
  v_existing_domain_budget INTEGER:=0;
  v_existing_cases INTEGER:=0;
  v_remaining INTEGER:=0;
  v_context_bound BOOLEAN:=false;
  v_work_has_candidate BOOLEAN:=false;
  v_five_domain_build JSONB;
  v_work_build JSONB;
  v_total_cases INTEGER:=0;
  v_domain_captures JSONB:='[]'::JSONB;
  v_work_as_of TIMESTAMPTZ:=clock_timestamp();
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('ai_ops:operational_snapshot:'||p_run_id::TEXT,0));

  SELECT * INTO v_run FROM ai_ops.planner_runs WHERE id=p_run_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ai_ops planner run not found: %',p_run_id; END IF;

  SELECT * INTO v_settings FROM ai_ops.settings WHERE singleton=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations settings are not initialized'; END IF;

  v_limit:=LEAST(
    GREATEST(COALESCE(p_case_limit,v_settings.max_cases_per_snapshot),1),
    v_settings.max_cases_per_snapshot
  );

  SELECT * INTO v_snapshot FROM ai_ops.snapshots WHERE run_id=p_run_id;

  IF FOUND THEN
    SELECT * INTO v_credit_capture FROM ai_ops.snapshot_domain_captures dc
      WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='receivables';
    SELECT * INTO v_sales_capture FROM ai_ops.snapshot_domain_captures dc
      WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='sales';
    SELECT * INTO v_customer_capture FROM ai_ops.snapshot_domain_captures dc
      WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='customer_health';
    SELECT * INTO v_inventory_capture FROM ai_ops.snapshot_domain_captures dc
      WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='inventory';
    SELECT * INTO v_field_capture FROM ai_ops.snapshot_domain_captures dc
      WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='field_execution';
    SELECT * INTO v_work_capture FROM ai_ops.snapshot_domain_captures dc
      WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='work_health';

    IF v_credit_capture.snapshot_id IS NULL OR v_sales_capture.snapshot_id IS NULL
       OR v_customer_capture.snapshot_id IS NULL OR v_inventory_capture.snapshot_id IS NULL
       OR v_field_capture.snapshot_id IS NULL THEN
      RAISE EXCEPTION 'existing operational snapshot is missing a required pre-Work-Health domain capture marker';
    END IF;

    IF v_work_capture.snapshot_id IS NOT NULL THEN
      v_total_cases:=v_credit_capture.case_count+v_sales_capture.case_count+
        v_customer_capture.case_count+v_inventory_capture.case_count+
        v_field_capture.case_count+v_work_capture.case_count;
      IF v_total_cases>v_limit THEN
        RAISE EXCEPTION 'existing snapshot case count % exceeds global limit %',v_total_cases,v_limit;
      END IF;

      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'domain',dc.domain,'capture_status',dc.capture_status,'case_count',dc.case_count,
        'evidence_bytes',dc.evidence_bytes,'capture_version',dc.capture_version,'metadata',dc.metadata
      ) ORDER BY CASE dc.domain WHEN 'receivables' THEN 0 WHEN 'sales' THEN 1
        WHEN 'customer_health' THEN 2 WHEN 'inventory' THEN 3
        WHEN 'field_execution' THEN 4 WHEN 'work_health' THEN 5 ELSE 6 END,dc.domain),'[]'::JSONB)
      INTO v_domain_captures
      FROM ai_ops.snapshot_domain_captures dc WHERE dc.snapshot_id=v_snapshot.id;

      RETURN jsonb_build_object(
        'snapshot_id',v_snapshot.id,'run_id',p_run_id,'business_date',v_run.business_date,
        'global_case_limit',v_limit,'captured_cases',v_total_cases,
        'idempotent_reuse',true,'domain_captures',v_domain_captures
      );
    END IF;

    v_context_bound:=NULLIF(v_run.result_summary->>'worker_context_hash','') IS NOT NULL;
    IF v_context_bound THEN
      RAISE EXCEPTION 'existing snapshot is already bound to a worker context and cannot add Work Health';
    END IF;

    v_existing_cases:=v_credit_capture.case_count+v_sales_capture.case_count+
      v_customer_capture.case_count+v_inventory_capture.case_count+v_field_capture.case_count;
    IF v_existing_cases>v_limit THEN
      RAISE EXCEPTION 'existing snapshot case count % exceeds global limit %',v_existing_cases,v_limit;
    END IF;

    SELECT COUNT(*)::INTEGER INTO v_work_demand
    FROM ai_ops.work_health_candidates(v_snapshot.data_as_of,2000);
    v_remaining:=GREATEST(v_limit-v_existing_cases,0);
    v_work_alloc:=LEAST(v_work_demand,v_remaining);
  ELSE
    IF v_run.status NOT IN ('pending','claimed','reasoning') THEN
      RAISE EXCEPTION 'planner run status does not allow snapshot build: %',v_run.status;
    END IF;

    SELECT LEAST(COUNT(*)::INTEGER,v_limit)
    INTO v_credit_demand
    FROM public.sales_orders so
    WHERE so.status IN ('delivered'::public.sales_order_status,'partially_delivered'::public.sales_order_status)
      AND so.payment_terms IN ('credit','mixed')
      AND so.delivered_at IS NOT NULL AND so.due_date IS NOT NULL
      AND so.due_date<v_run.business_date
      AND GREATEST(0::NUMERIC,
        COALESCE(so.total_amount,0)-COALESCE(so.paid_amount,0)-COALESCE(so.returned_amount,0)
      )>0;

    SELECT COUNT(*)::INTEGER INTO v_sales_demand
    FROM ai_ops.sales_target_candidates(v_run.business_date,v_limit);
    SELECT COUNT(*)::INTEGER INTO v_customer_demand
    FROM ai_ops.customer_health_candidates(v_run.business_date,2000);
    SELECT COUNT(*)::INTEGER INTO v_inventory_demand
    FROM ai_ops.inventory_candidates(v_run.business_date,2000);
    SELECT COUNT(*)::INTEGER INTO v_field_demand
    FROM ai_ops.field_execution_candidates(v_run.business_date,2000);
    SELECT COUNT(*)::INTEGER INTO v_work_demand
    FROM ai_ops.work_health_candidates(v_work_as_of,2000);

    v_allocations:=ai_ops.allocate_domain_case_budget(
      v_limit,
      jsonb_build_object(
        'receivables',v_credit_demand,'sales',v_sales_demand,
        'customer_health',v_customer_demand,'inventory',v_inventory_demand,
        'field_execution',v_field_demand,'work_health',v_work_demand
      ),
      ARRAY['receivables','sales','customer_health','inventory','field_execution','work_health']::TEXT[]
    );

    v_credit_alloc:=COALESCE((v_allocations->>'receivables')::INTEGER,0);
    v_sales_alloc:=COALESCE((v_allocations->>'sales')::INTEGER,0);
    v_customer_alloc:=COALESCE((v_allocations->>'customer_health')::INTEGER,0);
    v_inventory_alloc:=COALESCE((v_allocations->>'inventory')::INTEGER,0);
    v_field_alloc:=COALESCE((v_allocations->>'field_execution')::INTEGER,0);
    v_work_alloc:=COALESCE((v_allocations->>'work_health')::INTEGER,0);
    v_existing_domain_budget:=v_credit_alloc+v_sales_alloc+v_customer_alloc+
      v_inventory_alloc+v_field_alloc;

    v_five_domain_build:=ai_ops.build_operational_snapshot_five_domain_v1(
      p_run_id,GREATEST(v_existing_domain_budget,1)
    );

    SELECT * INTO v_snapshot FROM ai_ops.snapshots WHERE run_id=p_run_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'snapshot missing after preserved five-domain base build'; END IF;

    SELECT * INTO v_credit_capture FROM ai_ops.snapshot_domain_captures dc
      WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='receivables';
    SELECT * INTO v_sales_capture FROM ai_ops.snapshot_domain_captures dc
      WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='sales';
    SELECT * INTO v_customer_capture FROM ai_ops.snapshot_domain_captures dc
      WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='customer_health';
    SELECT * INTO v_inventory_capture FROM ai_ops.snapshot_domain_captures dc
      WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='inventory';
    SELECT * INTO v_field_capture FROM ai_ops.snapshot_domain_captures dc
      WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='field_execution';

    IF v_credit_capture.snapshot_id IS NULL OR v_sales_capture.snapshot_id IS NULL
       OR v_customer_capture.snapshot_id IS NULL OR v_inventory_capture.snapshot_id IS NULL
       OR v_field_capture.snapshot_id IS NULL THEN
      RAISE EXCEPTION 'preserved five-domain builder did not produce required capture markers';
    END IF;

    v_existing_cases:=v_credit_capture.case_count+v_sales_capture.case_count+
      v_customer_capture.case_count+v_inventory_capture.case_count+v_field_capture.case_count;
    v_remaining:=GREATEST(v_limit-v_existing_cases,0);
    v_work_alloc:=LEAST(v_work_demand,v_remaining);
  END IF;

  IF v_work_alloc>0 THEN
    v_work_build:=ai_ops.refresh_work_health_cases(
      v_snapshot.id,v_run.business_date,v_work_alloc
    );
  ELSE
    v_work_has_candidate:=v_work_demand>0;
    INSERT INTO ai_ops.snapshot_domain_captures(
      snapshot_id,domain,capture_version,source_as_of,business_date,
      case_count,evidence_bytes,capture_status,metadata
    ) VALUES (
      v_snapshot.id,'work_health','work-health-v1',
      v_snapshot.data_as_of,v_run.business_date,0,0,
      CASE WHEN v_work_has_candidate THEN 'partial' ELSE 'completed' END,
      jsonb_build_object(
        'capture_marker_written',true,
        'case_types',jsonb_build_array(
          'overdue_work','blocked_work','waiting_follow_up_due','stale_work','missing_next_action'
        ),
        'global_budget_exhausted',v_work_has_candidate,
        'global_case_limit',v_limit,'allocated_case_limit',0,'case_limit',0,
        'has_more',v_work_has_candidate,
        'source_work_mutation_performed',false
      )
    );
  END IF;

  SELECT * INTO v_credit_capture FROM ai_ops.snapshot_domain_captures dc
    WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='receivables';
  SELECT * INTO v_sales_capture FROM ai_ops.snapshot_domain_captures dc
    WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='sales';
  SELECT * INTO v_customer_capture FROM ai_ops.snapshot_domain_captures dc
    WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='customer_health';
  SELECT * INTO v_inventory_capture FROM ai_ops.snapshot_domain_captures dc
    WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='inventory';
  SELECT * INTO v_field_capture FROM ai_ops.snapshot_domain_captures dc
    WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='field_execution';
  SELECT * INTO v_work_capture FROM ai_ops.snapshot_domain_captures dc
    WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='work_health';

  IF v_credit_capture.snapshot_id IS NULL OR v_sales_capture.snapshot_id IS NULL
     OR v_customer_capture.snapshot_id IS NULL OR v_inventory_capture.snapshot_id IS NULL
     OR v_field_capture.snapshot_id IS NULL OR v_work_capture.snapshot_id IS NULL THEN
    RAISE EXCEPTION 'operational snapshot did not produce all six immutable domain capture markers';
  END IF;

  v_total_cases:=v_credit_capture.case_count+v_sales_capture.case_count+
    v_customer_capture.case_count+v_inventory_capture.case_count+
    v_field_capture.case_count+v_work_capture.case_count;
  IF v_total_cases>v_limit THEN
    RAISE EXCEPTION 'multi-domain snapshot case count % exceeds global limit %',v_total_cases,v_limit;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'domain',dc.domain,'capture_status',dc.capture_status,'case_count',dc.case_count,
    'evidence_bytes',dc.evidence_bytes,'capture_version',dc.capture_version,'metadata',dc.metadata
  ) ORDER BY CASE dc.domain WHEN 'receivables' THEN 0 WHEN 'sales' THEN 1
    WHEN 'customer_health' THEN 2 WHEN 'inventory' THEN 3
    WHEN 'field_execution' THEN 4 WHEN 'work_health' THEN 5 ELSE 6 END,dc.domain),'[]'::JSONB)
  INTO v_domain_captures
  FROM ai_ops.snapshot_domain_captures dc WHERE dc.snapshot_id=v_snapshot.id;

  RETURN jsonb_build_object(
    'snapshot_id',v_snapshot.id,'run_id',p_run_id,'business_date',v_run.business_date,
    'global_case_limit',v_limit,
    'credit_demand',v_credit_demand,'sales_demand',v_sales_demand,
    'customer_health_demand',v_customer_demand,'inventory_demand',v_inventory_demand,
    'field_execution_demand',v_field_demand,'work_health_demand',v_work_demand,
    'credit_allocated_limit',v_credit_alloc,'sales_allocated_limit',v_sales_alloc,
    'customer_health_allocated_limit',v_customer_alloc,'inventory_allocated_limit',v_inventory_alloc,
    'field_execution_allocated_limit',v_field_alloc,'work_health_allocated_limit',v_work_alloc,
    'captured_cases',v_total_cases,'idempotent_reuse',false,
    'domain_captures',v_domain_captures,'operational_mutation_performed',false
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.build_operational_snapshot(UUID,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;

-- The required-domain registry is the single worker/staging coverage authority.
CREATE OR REPLACE FUNCTION ai_ops.required_operational_domains()
RETURNS TEXT[]
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT ARRAY[
    'receivables','sales','customer_health','inventory','field_execution','work_health'
  ]::TEXT[];
$$;
REVOKE ALL ON FUNCTION ai_ops.required_operational_domains()
  FROM PUBLIC,anon,authenticated,service_role;

ALTER FUNCTION ai_ops.selected_case_capture_allows_action(UUID)
  RENAME TO selected_case_capture_allows_action_five_domain_v1;
REVOKE ALL ON FUNCTION ai_ops.selected_case_capture_allows_action_five_domain_v1(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.selected_case_capture_allows_action(p_decision_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_decision_type TEXT;
  v_run_business_date DATE;
  v_snapshot_id UUID;
  v_snapshot_status TEXT;
  v_snapshot_data_as_of TIMESTAMPTZ;
  v_domain TEXT;
  v_case_source_as_of TIMESTAMPTZ;
  v_case_payload_bytes INTEGER;
  v_capture_version TEXT;
  v_capture_status TEXT;
  v_capture_source_as_of TIMESTAMPTZ;
  v_capture_business_date DATE;
  v_capture_case_count INTEGER;
  v_capture_evidence_bytes BIGINT;
  v_metadata JSONB;
  v_frozen_domain_case_count INTEGER;
  v_frozen_domain_evidence_bytes BIGINT;
BEGIN
  SELECT sc.domain INTO v_domain
  FROM ai_ops.decisions d
  JOIN ai_ops.snapshots s ON s.run_id=d.run_id
  JOIN ai_ops.snapshot_cases sc ON sc.snapshot_id=s.id AND sc.case_id=d.case_id
  WHERE d.id=p_decision_id;

  IF NOT FOUND THEN RETURN false; END IF;
  IF v_domain<>'work_health' THEN
    RETURN ai_ops.selected_case_capture_allows_action_five_domain_v1(p_decision_id);
  END IF;

  SELECT
    d.decision_type::TEXT,r.business_date,s.id,s.snapshot_status,s.data_as_of,
    sc.domain,sc.source_as_of,sc.payload_bytes,
    dc.capture_version,dc.capture_status,dc.source_as_of,dc.business_date,
    dc.case_count,dc.evidence_bytes,dc.metadata
  INTO
    v_decision_type,v_run_business_date,v_snapshot_id,v_snapshot_status,v_snapshot_data_as_of,
    v_domain,v_case_source_as_of,v_case_payload_bytes,
    v_capture_version,v_capture_status,v_capture_source_as_of,v_capture_business_date,
    v_capture_case_count,v_capture_evidence_bytes,v_metadata
  FROM ai_ops.decisions d
  JOIN ai_ops.planner_runs r ON r.id=d.run_id
  JOIN ai_ops.snapshots s ON s.run_id=d.run_id
  JOIN ai_ops.snapshot_cases sc ON sc.snapshot_id=s.id AND sc.case_id=d.case_id
  JOIN ai_ops.snapshot_domain_captures dc ON dc.snapshot_id=s.id AND dc.domain=sc.domain
  WHERE d.id=p_decision_id;

  IF NOT FOUND OR v_decision_type NOT IN ('CREATE_WORK','ESCALATE') THEN RETURN false; END IF;
  IF v_domain<>'work_health' OR v_capture_version<>'work-health-v1' THEN RETURN false; END IF;
  IF v_snapshot_status<>'ready' THEN RETURN false; END IF;
  IF v_capture_status NOT IN ('completed','partial') THEN RETURN false; END IF;
  IF v_capture_source_as_of IS DISTINCT FROM v_snapshot_data_as_of
     OR v_case_source_as_of IS DISTINCT FROM v_snapshot_data_as_of
     OR v_capture_business_date IS DISTINCT FROM v_run_business_date THEN RETURN false; END IF;
  IF COALESCE(v_case_payload_bytes,0)<=0
     OR COALESCE(v_capture_case_count,0)<=0
     OR COALESCE(v_capture_evidence_bytes,0)<=0 THEN RETURN false; END IF;

  SELECT COUNT(*)::INTEGER,COALESCE(SUM(sc.payload_bytes),0)::BIGINT
  INTO v_frozen_domain_case_count,v_frozen_domain_evidence_bytes
  FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id=v_snapshot_id AND sc.domain='work_health';

  IF v_frozen_domain_case_count IS DISTINCT FROM v_capture_case_count
     OR v_frozen_domain_evidence_bytes IS DISTINCT FROM v_capture_evidence_bytes THEN
    RETURN false;
  END IF;

  IF COALESCE((v_metadata->>'global_budget_exhausted')::BOOLEAN,false) THEN RETURN false; END IF;

  IF v_capture_status='completed' THEN
    IF COALESCE((v_metadata->>'has_more')::BOOLEAN,false) THEN RETURN false; END IF;
    RETURN true;
  END IF;

  -- A partial selected Case is actionable only for trusted bounded selection.
  IF NOT COALESCE((v_metadata->>'has_more')::BOOLEAN,false) THEN RETURN false; END IF;
  IF NULLIF(v_metadata->>'case_limit','') IS NULL THEN RETURN false; END IF;
  IF (v_metadata->>'case_limit')::INTEGER<=0 THEN RETURN false; END IF;
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.selected_case_capture_allows_action(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.build_operational_snapshot(UUID,INTEGER) IS
  'Canonical six-domain operational snapshot builder using one hard global Case budget across Receivables, Sales, Customer Health, Inventory, Field Execution and Work Health.';
COMMENT ON FUNCTION ai_ops.required_operational_domains() IS
  'Canonical required AI Operations domain registry consumed by worker context/staging coverage gates.';
COMMENT ON FUNCTION ai_ops.selected_case_capture_allows_action(UUID) IS
  'Shared selected-case actionability gate extended fail-closed to the explicit work-health-v1 capture contract.';

RESET lock_timeout;
RESET statement_timeout;
