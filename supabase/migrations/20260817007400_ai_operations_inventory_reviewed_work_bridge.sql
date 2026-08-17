-- ============================================================================
-- AI Operations Planner — Inventory Human-Approved Work Bridge
--
-- DESIGN-TIME MIGRATION ONLY.
-- Adds reviewed CREATE_WORK execution for Inventory. Operational mutation is
-- limited to Work + AI provenance/state after human approval. No stock balance,
-- stock movement, transfer, product, warehouse, batch or purchasing record is
-- changed by this bridge.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

-- Reuse the generic Work link contract and add the real transfer entity rather
-- than hiding transfer identity only inside metadata.
CREATE OR REPLACE FUNCTION private.work_link_entity_table(p_entity_type TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE lower(trim(p_entity_type))
    WHEN 'customer' THEN 'public.customers'
    WHEN 'sales_order' THEN 'public.sales_orders'
    WHEN 'payment_receipt' THEN 'public.payment_receipts'
    WHEN 'supplier' THEN 'public.suppliers'
    WHEN 'purchase_invoice' THEN 'public.purchase_invoices'
    WHEN 'product' THEN 'public.products'
    WHEN 'warehouse' THEN 'public.warehouses'
    WHEN 'stock_transfer' THEN 'public.stock_transfers'
    WHEN 'employee' THEN 'public.hr_employees'
    WHEN 'activity' THEN 'public.activities'
    WHEN 'target' THEN 'public.targets'
    ELSE NULL
  END;
$$;

REVOKE ALL ON FUNCTION private.work_link_entity_table(TEXT)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.work_create_ai_reviewed_inventory_task(
  p_decision_id UUID,
  p_approved_execution_by UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_settings ai_ops.settings%ROWTYPE;
  v_decision ai_ops.decisions%ROWTYPE;
  v_review ai_ops.decision_reviews%ROWTYPE;
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_sc ai_ops.snapshot_cases%ROWTYPE;
  v_existing_work public.work_items%ROWTYPE;
  v_work public.work_items%ROWTYPE;
  v_issues JSONB;
  v_now TIMESTAMPTZ:=clock_timestamp();
  v_source_key TEXT;
  v_priority public.work_priority;
  v_title TEXT;
  v_description TEXT;
  v_fingerprint TEXT;
  v_product_id UUID;
  v_warehouse_id UUID;
  v_from_warehouse_id UUID;
  v_transfer_id UUID;
  v_department_id UUID;
  v_branch_id UUID;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('ai_ops:commit:'||p_decision_id::TEXT,0));

  IF p_approved_execution_by IS NULL
     OR NOT private.work_actor_is_active(p_approved_execution_by) THEN
    RAISE EXCEPTION 'approved execution actor is not an active Work actor';
  END IF;

  SELECT * INTO v_decision
  FROM ai_ops.decisions
  WHERE id=p_decision_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations decision not found'; END IF;

  IF v_decision.decision_type<>'CREATE_WORK' THEN
    RETURN jsonb_build_object(
      'committed',false,'blocked',true,'reason','bridge_supports_create_work_only',
      'decision_type',v_decision.decision_type
    );
  END IF;

  IF v_decision.committed_work_item_id IS NOT NULL THEN
    SELECT * INTO v_existing_work FROM public.work_items WHERE id=v_decision.committed_work_item_id;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'committed',true,'idempotent_reuse',true,'decision_id',p_decision_id,
        'work_item_id',v_existing_work.id,'work_number',v_existing_work.work_number
      );
    END IF;
    RAISE EXCEPTION 'decision references missing committed Work item';
  END IF;

  SELECT * INTO v_settings FROM ai_ops.settings WHERE singleton=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations settings are not initialized'; END IF;
  IF NOT v_settings.planner_enabled THEN
    RETURN jsonb_build_object('committed',false,'blocked',true,'reason','planner_disabled_kill_switch');
  END IF;
  IF v_settings.shadow_mode THEN
    RETURN jsonb_build_object('committed',false,'blocked',true,'reason','shadow_mode_blocks_operational_commit');
  END IF;

  v_source_key:='ai_ops:decision:'||p_decision_id::TEXT;
  SELECT * INTO v_existing_work
  FROM public.work_items wi
  WHERE wi.source_kind='system'::public.work_source_kind AND wi.source_key=v_source_key
  ORDER BY wi.created_at,wi.id LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'committed',false,'blocked',true,'reason','unexpected_source_key_collision',
      'work_item_id',v_existing_work.id,'work_number',v_existing_work.work_number
    );
  END IF;

  SELECT * INTO v_review FROM ai_ops.decision_reviews WHERE decision_id=p_decision_id;
  IF NOT FOUND OR v_review.review_state<>'approved' THEN
    RETURN jsonb_build_object('committed',false,'blocked',true,'reason','human_approval_required');
  END IF;
  IF v_decision.validation_state<>'validated' THEN
    RETURN jsonb_build_object('committed',false,'blocked',true,'reason','decision_not_validated');
  END IF;

  v_fingerprint:=md5(jsonb_build_object(
    'id',v_decision.id,'run_id',v_decision.run_id,'case_id',v_decision.case_id,
    'revision',v_decision.revision,'decision_type',v_decision.decision_type,
    'recommended_owner_user_id',v_decision.recommended_owner_user_id,
    'recommended_assignee_user_id',v_decision.recommended_assignee_user_id,
    'responsibility_basis',v_decision.responsibility_basis,
    'concise_rationale',v_decision.concise_rationale,'confidence',v_decision.confidence,
    'expected_outcome',v_decision.expected_outcome,'next_action_text',v_decision.next_action_text,
    'due_at',v_decision.due_at,'review_after',v_decision.review_after,
    'linked_work_item_id',v_decision.linked_work_item_id
  )::TEXT);

  IF v_review.decision_fingerprint IS DISTINCT FROM v_fingerprint
     OR v_review.decision_revision<>v_decision.revision THEN
    RETURN jsonb_build_object('committed',false,'blocked',true,'reason','review_fingerprint_mismatch');
  END IF;

  -- Same-transaction current-state revalidation immediately before mutation.
  v_issues:=ai_ops.current_decision_issues(p_decision_id);
  IF jsonb_array_length(v_issues)>0 THEN
    UPDATE ai_ops.decisions
    SET validation_state='rejected',commit_status='rejected',
        validation_detail=validation_detail||jsonb_build_object(
          'commit_revalidation_failed',true,'commit_revalidation_codes',v_issues,
          'commit_revalidation_at',v_now,'stage_only',true
        ),
        validated_at=v_now,validated_by_user_id=NULL,updated_at=v_now
    WHERE id=p_decision_id;
    RETURN jsonb_build_object(
      'committed',false,'blocked',true,'reason','current_state_changed','validation_codes',v_issues
    );
  END IF;

  IF v_decision.recommended_owner_user_id IS NULL
     OR v_decision.recommended_assignee_user_id IS NULL
     OR v_decision.due_at IS NULL THEN
    RETURN jsonb_build_object(
      'committed',false,'blocked',true,'reason','explicit_owner_assignee_and_due_required'
    );
  END IF;
  IF v_decision.due_at<=v_now THEN
    RETURN jsonb_build_object('committed',false,'blocked',true,'reason','proposed_due_at_not_future');
  END IF;
  IF NOT private.work_actor_is_active(v_decision.recommended_owner_user_id)
     OR NOT private.work_actor_is_active(v_decision.recommended_assignee_user_id) THEN
    RETURN jsonb_build_object('committed',false,'blocked',true,'reason','work_actor_became_unavailable');
  END IF;

  SELECT * INTO v_snapshot FROM ai_ops.snapshots WHERE run_id=v_decision.run_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'decision snapshot missing'; END IF;
  SELECT * INTO v_sc FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id=v_snapshot.id AND sc.case_id=v_decision.case_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'decision-time frozen evidence missing'; END IF;

  IF v_sc.domain<>'inventory' OR v_sc.case_type NOT IN ('local_shortage','stalled_transfer') THEN
    RAISE EXCEPTION 'Inventory Work bridge received unsupported frozen case';
  END IF;

  v_warehouse_id:=NULLIF(v_sc.facts->>'warehouse_id','')::UUID;
  v_product_id:=NULLIF(v_sc.facts->>'product_id','')::UUID;
  v_transfer_id:=NULLIF(v_sc.facts->>'transfer_id','')::UUID;
  v_from_warehouse_id:=NULLIF(v_sc.facts->>'from_warehouse_id','')::UUID;

  IF v_warehouse_id IS NULL OR NOT private.work_link_entity_exists('warehouse',v_warehouse_id) THEN
    RAISE EXCEPTION 'warehouse entity no longer exists or is unsupported by Work link contract';
  END IF;
  IF v_sc.case_type='local_shortage' THEN
    IF v_product_id IS NULL OR NOT private.work_link_entity_exists('product',v_product_id) THEN
      RAISE EXCEPTION 'product entity no longer exists or is unsupported by Work link contract';
    END IF;
  ELSE
    IF v_transfer_id IS NULL OR NOT private.work_link_entity_exists('stock_transfer',v_transfer_id) THEN
      RAISE EXCEPTION 'stock transfer no longer exists or is unsupported by Work link contract';
    END IF;
  END IF;

  SELECT e.department_id,e.branch_id
  INTO v_department_id,v_branch_id
  FROM public.hr_employees e
  WHERE e.user_id=v_decision.recommended_assignee_user_id AND e.status::TEXT='active'
  ORDER BY e.updated_at DESC NULLS LAST,e.id LIMIT 1;

  IF v_branch_id IS NULL THEN
    v_branch_id:=NULLIF(v_sc.facts->>'branch_id','')::UUID;
  END IF;

  v_priority:=CASE v_sc.severity
    WHEN 'critical' THEN 'urgent'::public.work_priority
    WHEN 'high' THEN 'high'::public.work_priority
    WHEN 'medium' THEN 'normal'::public.work_priority
    ELSE 'low'::public.work_priority
  END;

  IF v_sc.case_type='local_shortage' THEN
    v_title:=left(
      'معالجة نقص مخزون — '||COALESCE(NULLIF(v_sc.facts->>'product_name',''),'منتج')||
      ' — '||COALESCE(NULLIF(v_sc.facts->>'warehouse_name',''),'مخزن'),240
    );
    v_description:=left(concat_ws(E'\n',
      'إجراء تشغيلي ناتج عن مراجعة معتمدة لحالة تغطية المخزون الفعلية.',
      'راجع الرصيد المتاح والطلب الفعلي والتحويلات أو المخزون المتاح في المخازن الأخرى قبل التنفيذ.',
      'سجّل الإجراء والنتيجة والخطوة التالية داخل Work. لا يعدّل هذا التكليف المخزون أو التحويلات تلقائيًا.'
    ),2000);
  ELSE
    v_title:=left(
      'متابعة تحويل مخزني متأخر — '||COALESCE(NULLIF(v_sc.facts->>'transfer_number',''),'تحويل'),240
    );
    v_description:=left(concat_ws(E'\n',
      'إجراء تشغيلي ناتج عن مراجعة معتمدة لتحويل مخزني ما زال في حالة نقل بعد المدة المتوقعة.',
      'تحقق من حالة التحويل والاستلام الفعلي مع المخازن المعنية قبل أي إجراء على السجل التشغيلي.',
      'سجّل النتيجة والخطوة التالية داخل Work. النظام لا يستلم أو يلغي التحويل تلقائيًا.'
    ),2000);
  END IF;

  INSERT INTO public.work_items(
    kind,source_kind,source_key,title,description,expected_outcome,
    status,priority,visibility,creator_user_id,requester_user_id,
    accountable_owner_user_id,current_assignee_user_id,
    owning_department_id,branch_id,due_at,first_due_at,next_action_text,
    next_action_at,acknowledgement_required,completion_mode,
    last_meaningful_activity_at,state_version,metadata
  ) VALUES (
    'task'::public.work_item_kind,'system'::public.work_source_kind,v_source_key,
    v_title,v_description,v_decision.expected_outcome,'draft'::public.work_item_status,
    v_priority,'standard'::public.work_visibility,NULL,NULL,
    v_decision.recommended_owner_user_id,v_decision.recommended_assignee_user_id,
    v_department_id,v_branch_id,v_decision.due_at,v_decision.due_at,
    v_decision.next_action_text,NULL,false,'assignee_closes'::public.work_completion_mode,
    v_now,1,jsonb_build_object(
      'origin','ai_ops','ai_domain','inventory','ai_case_type',v_sc.case_type,
      'ai_decision_id',v_decision.id,'ai_case_id',v_decision.case_id,
      'ai_run_id',v_decision.run_id,'ai_snapshot_id',v_snapshot.id,
      'human_review_id',v_review.id,'approved_execution_by',p_approved_execution_by,
      'employee_safe_reason',v_decision.employee_safe_reason,
      'management_rationale_exposed',false,'inventory_mutation_performed',false
    )
  ) RETURNING * INTO v_work;

  PERFORM private.ai_ops_append_work_system_event(
    v_work.id,'work.created',NULL,'draft'::public.work_item_status,
    jsonb_build_object(
      'source_kind','system','source_key',v_source_key,'origin','ai_ops','domain','inventory',
      'case_type',v_sc.case_type,'decision_id',v_decision.id,'review_id',v_review.id,
      'owner_user_id',v_work.accountable_owner_user_id,'assignee_user_id',v_work.current_assignee_user_id,
      'due_at',v_work.due_at
    )
  );

  UPDATE public.work_items
  SET status='open'::public.work_item_status,activated_at=v_now,assigned_at=v_now,
      state_version=state_version+1,last_meaningful_activity_at=v_now,updated_at=v_now
  WHERE id=v_work.id RETURNING * INTO v_work;

  IF v_sc.case_type='local_shortage' THEN
    INSERT INTO public.work_links(work_item_id,entity_type,entity_id,relation_type,label,created_by_user_id)
    VALUES(v_work.id,'product',v_product_id,'primary',left(COALESCE(v_sc.facts->>'product_name','منتج'),240),NULL)
    ON CONFLICT(work_item_id,entity_type,entity_id,relation_type) DO NOTHING;
    INSERT INTO public.work_links(work_item_id,entity_type,entity_id,relation_type,label,created_by_user_id)
    VALUES(v_work.id,'warehouse',v_warehouse_id,'affected_at',left(COALESCE(v_sc.facts->>'warehouse_name','مخزن'),240),NULL)
    ON CONFLICT(work_item_id,entity_type,entity_id,relation_type) DO NOTHING;
  ELSE
    INSERT INTO public.work_links(work_item_id,entity_type,entity_id,relation_type,label,created_by_user_id)
    VALUES(v_work.id,'stock_transfer',v_transfer_id,'primary',left(COALESCE(v_sc.facts->>'transfer_number','تحويل مخزني'),240),NULL)
    ON CONFLICT(work_item_id,entity_type,entity_id,relation_type) DO NOTHING;
    INSERT INTO public.work_links(work_item_id,entity_type,entity_id,relation_type,label,created_by_user_id)
    VALUES(v_work.id,'warehouse',v_warehouse_id,'destination',left(COALESCE(v_sc.facts->>'warehouse_name','مخزن مستلم'),240),NULL)
    ON CONFLICT(work_item_id,entity_type,entity_id,relation_type) DO NOTHING;
    IF v_from_warehouse_id IS NOT NULL AND private.work_link_entity_exists('warehouse',v_from_warehouse_id) THEN
      INSERT INTO public.work_links(work_item_id,entity_type,entity_id,relation_type,label,created_by_user_id)
      VALUES(v_work.id,'warehouse',v_from_warehouse_id,'source',left(COALESCE(v_sc.facts->>'from_warehouse_name','مخزن مرسل'),240),NULL)
      ON CONFLICT(work_item_id,entity_type,entity_id,relation_type) DO NOTHING;
    END IF;
  END IF;

  PERFORM private.ai_ops_append_work_system_event(
    v_work.id,'work.activated','draft'::public.work_item_status,'open'::public.work_item_status,
    jsonb_build_object(
      'source','ai_ops_human_approved','domain','inventory','case_type',v_sc.case_type,
      'decision_id',v_decision.id,'approved_by_user_id',p_approved_execution_by,
      'assignee_user_id',v_work.current_assignee_user_id,'owner_user_id',v_work.accountable_owner_user_id
    )
  );

  UPDATE ai_ops.decisions
  SET committed_work_item_id=v_work.id,committed_at=v_now,commit_status='committed',
      validation_detail=validation_detail||jsonb_build_object(
        'commit_revalidated_against_current_state',true,'commit_revalidated_at',v_now,
        'human_review_id',v_review.id,'approved_execution_by',p_approved_execution_by,
        'domain','inventory','stage_only',false,'inventory_mutation_performed',false
      ),updated_at=v_now
  WHERE id=p_decision_id;

  UPDATE ai_ops.cases
  SET status='actioned',updated_at=v_now,state_version=state_version+1
  WHERE id=v_decision.case_id;

  UPDATE ai_ops.planner_runs
  SET checkpoint='reviewed_work_committed',work_created_count=work_created_count+1,
      result_summary=result_summary||jsonb_build_object(
        'last_committed_decision_id',v_decision.id,'last_committed_work_item_id',v_work.id,
        'last_commit_at',v_now,'last_commit_domain','inventory'
      ),updated_at=v_now
  WHERE id=v_decision.run_id;

  RETURN jsonb_build_object(
    'committed',true,'idempotent_reuse',false,'decision_id',p_decision_id,
    'work_item_id',v_work.id,'work_number',v_work.work_number,'source_key',v_source_key,
    'domain','inventory','case_type',v_sc.case_type,
    'operational_mutation','work_create_only','inventory_mutation_performed',false
  );
END;
$$;

REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_inventory_task(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;

ALTER FUNCTION private.work_create_ai_reviewed_task(UUID,UUID)
  RENAME TO work_create_ai_reviewed_task_three_domain_v1;
REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_task_three_domain_v1(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.work_create_ai_reviewed_task(
  p_decision_id UUID,
  p_approved_execution_by UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_domain TEXT;
BEGIN
  SELECT sc.domain INTO v_domain
  FROM ai_ops.decisions d
  JOIN ai_ops.snapshots s ON s.run_id=d.run_id
  JOIN ai_ops.snapshot_cases sc ON sc.snapshot_id=s.id AND sc.case_id=d.case_id
  WHERE d.id=p_decision_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'decision-time frozen evidence missing'; END IF;

  IF v_domain='inventory' THEN
    RETURN private.work_create_ai_reviewed_inventory_task(p_decision_id,p_approved_execution_by);
  END IF;
  RETURN private.work_create_ai_reviewed_task_three_domain_v1(p_decision_id,p_approved_execution_by);
END;
$$;

REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_task(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION private.work_create_ai_reviewed_inventory_task(UUID,UUID) IS
  'Human-approved Inventory CREATE_WORK bridge with kill switches, immutable review fingerprint, commit-time revalidation and exact product/warehouse/stock-transfer Work links; inventory records remain read-only.';
COMMENT ON FUNCTION private.work_create_ai_reviewed_task(UUID,UUID) IS
  'Canonical reviewed Work bridge dispatcher for Receivables, Sales, Customer Health and Inventory.';

RESET lock_timeout;
RESET statement_timeout;
