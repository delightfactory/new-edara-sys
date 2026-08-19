-- ============================================================================
-- AI Operations Planner — Inventory Case Engine
--
-- DESIGN-TIME MIGRATION ONLY. Production inventory tables remain read-only.
-- Production-backed v1 cases:
--   * local_shortage: positive recent outbound demand with no stock or <7 days
--     of available cover at the exact warehouse.
--   * stalled_transfer: in_transit more than 7 days after sent_at/created_at.
-- min_stock_level is not authority because it is not operationally configured.
-- Batch expiry is intentionally not emitted until positive batch usage exists.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.inventory_candidates(
  p_business_date DATE,
  p_limit INTEGER DEFAULT 50
)
RETURNS TABLE(
  case_key TEXT,
  case_type TEXT,
  attention_class TEXT,
  severity TEXT,
  entity_type TEXT,
  entity_id UUID,
  warehouse_id UUID,
  warehouse_name TEXT,
  product_id UUID,
  product_name TEXT,
  transfer_id UUID,
  responsible_user_id UUID,
  responsible_user_name TEXT,
  responsible_user_active BOOLEAN,
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
WITH
manager_rollup AS (
  SELECT
    w.id AS warehouse_id,
    w.manager_id AS declared_manager_id,
    COUNT(DISTINCT wm.profile_id) FILTER (WHERE wm.is_primary)::INTEGER AS primary_count,
    MIN(wm.profile_id::TEXT) FILTER (WHERE wm.is_primary)::UUID AS sole_primary_user_id
  FROM public.warehouses w
  LEFT JOIN public.warehouse_managers wm ON wm.warehouse_id=w.id
  WHERE w.is_active=true
  GROUP BY w.id,w.manager_id
),
warehouse_responsibility AS (
  SELECT
    mr.warehouse_id,
    CASE
      WHEN mr.primary_count=1
       AND (mr.declared_manager_id IS NULL OR mr.declared_manager_id=mr.sole_primary_user_id)
        THEN mr.sole_primary_user_id
      ELSE NULL
    END AS responsible_user_id,
    (
      mr.primary_count=1
      AND (mr.declared_manager_id IS NULL OR mr.declared_manager_id=mr.sole_primary_user_id)
    ) AS responsibility_unambiguous,
    mr.declared_manager_id,mr.primary_count,mr.sole_primary_user_id
  FROM manager_rollup mr
),
outbound_30d AS (
  SELECT
    sm.warehouse_id,sm.product_id,
    SUM(sm.quantity)::NUMERIC AS outbound_qty_30d,
    COUNT(*)::INTEGER AS outbound_movement_count_30d,
    MAX(sm.created_at) AS latest_outbound_at
  FROM public.stock_movements sm
  WHERE sm.type='out'
    AND (sm.created_at AT TIME ZONE 'Africa/Cairo')::DATE
        BETWEEN p_business_date-29 AND p_business_date
  GROUP BY sm.warehouse_id,sm.product_id
),
shortage_base AS (
  SELECT
    o.warehouse_id,w.name::TEXT AS warehouse_name,w.branch_id,
    o.product_id,p.name::TEXT AS product_name,p.sku::TEXT AS product_sku,
    COALESCE(s.quantity,0)::NUMERIC AS quantity,
    COALESCE(s.reserved_quantity,0)::NUMERIC AS reserved_quantity,
    COALESCE(s.available_quantity,0)::NUMERIC AS available_quantity,
    COALESCE(s.wac,0)::NUMERIC AS wac,
    o.outbound_qty_30d,o.outbound_movement_count_30d,o.latest_outbound_at,
    (o.outbound_qty_30d/30.0)::NUMERIC AS average_daily_outbound,
    CASE WHEN COALESCE(s.available_quantity,0)<=0 THEN 0::NUMERIC
         ELSE (COALESCE(s.available_quantity,0)/(o.outbound_qty_30d/30.0))::NUMERIC END AS coverage_days,
    wr.responsible_user_id,wr.responsibility_unambiguous,
    wr.declared_manager_id,wr.primary_count,wr.sole_primary_user_id
  FROM outbound_30d o
  JOIN public.warehouses w ON w.id=o.warehouse_id AND w.is_active=true
  JOIN public.products p ON p.id=o.product_id AND p.is_active=true
  LEFT JOIN public.stock s ON s.warehouse_id=o.warehouse_id AND s.product_id=o.product_id
  LEFT JOIN warehouse_responsibility wr ON wr.warehouse_id=o.warehouse_id
  WHERE o.outbound_qty_30d>0
    AND (
      COALESCE(s.available_quantity,0)<=0
      OR COALESCE(s.available_quantity,0)/(o.outbound_qty_30d/30.0)<7
    )
),
shortage_enriched AS (
  SELECT
    sb.*,
    alt.total_alternate_available,alt.alternate_warehouses,
    COALESCE(inbound.in_transit_count,0)::INTEGER AS in_transit_count,
    COALESCE(inbound.in_transit_remaining_qty,0)::NUMERIC AS in_transit_remaining_qty,
    inbound.oldest_in_transit_sent_at,
    rp.full_name::TEXT AS responsible_user_name,
    CASE WHEN sb.responsible_user_id IS NULL THEN false
         ELSE private.work_actor_is_active(sb.responsible_user_id) END AS responsible_user_active
  FROM shortage_base sb
  LEFT JOIN public.profiles rp ON rp.id=sb.responsible_user_id
  LEFT JOIN LATERAL (
    SELECT
      COALESCE(SUM(x.available_quantity),0)::NUMERIC AS total_alternate_available,
      COALESCE(jsonb_agg(jsonb_build_object(
        'warehouse_id',x.warehouse_id,'warehouse_name',x.warehouse_name,
        'available_quantity',x.available_quantity
      ) ORDER BY x.available_quantity DESC,x.warehouse_id),'[]'::JSONB) AS alternate_warehouses
    FROM (
      SELECT s2.warehouse_id,w2.name::TEXT AS warehouse_name,
             COALESCE(s2.available_quantity,0)::NUMERIC AS available_quantity
      FROM public.stock s2
      JOIN public.warehouses w2 ON w2.id=s2.warehouse_id AND w2.is_active=true
      WHERE s2.product_id=sb.product_id AND s2.warehouse_id<>sb.warehouse_id
        AND COALESCE(s2.available_quantity,0)>0
      ORDER BY s2.available_quantity DESC,s2.warehouse_id
      LIMIT 5
    ) x
  ) alt ON true
  LEFT JOIN LATERAL (
    SELECT
      COUNT(DISTINCT st.id)::INTEGER AS in_transit_count,
      COALESCE(SUM(GREATEST(sti.quantity-COALESCE(sti.received_quantity,0),0)),0)::NUMERIC
        AS in_transit_remaining_qty,
      MIN(COALESCE(st.sent_at,st.created_at)) AS oldest_in_transit_sent_at
    FROM public.stock_transfers st
    JOIN public.stock_transfer_items sti ON sti.transfer_id=st.id
    WHERE st.to_warehouse_id=sb.warehouse_id AND st.status='in_transit'
      AND sti.product_id=sb.product_id
  ) inbound ON true
),
transfer_base AS (
  SELECT
    st.id AS transfer_id,st.number::TEXT AS transfer_number,
    st.from_warehouse_id,fw.name::TEXT AS from_warehouse_name,
    st.to_warehouse_id,tw.name::TEXT AS to_warehouse_name,tw.branch_id AS to_branch_id,
    st.status::TEXT AS transfer_status,st.requested_by,st.approved_by,st.sent_by,
    COALESCE(st.sent_at,st.created_at) AS sent_reference_at,
    GREATEST(p_business_date-(COALESCE(st.sent_at,st.created_at) AT TIME ZONE 'Africa/Cairo')::DATE,0)::INTEGER
      AS transit_age_days,
    COUNT(sti.id)::INTEGER AS item_count,
    COALESCE(SUM(sti.quantity),0)::NUMERIC AS transfer_quantity,
    COALESCE(SUM(sti.received_quantity),0)::NUMERIC AS received_quantity,
    wr.responsible_user_id,wr.responsibility_unambiguous,
    wr.declared_manager_id,wr.primary_count,wr.sole_primary_user_id
  FROM public.stock_transfers st
  JOIN public.warehouses fw ON fw.id=st.from_warehouse_id
  JOIN public.warehouses tw ON tw.id=st.to_warehouse_id AND tw.is_active=true
  LEFT JOIN public.stock_transfer_items sti ON sti.transfer_id=st.id
  LEFT JOIN warehouse_responsibility wr ON wr.warehouse_id=st.to_warehouse_id
  WHERE st.status='in_transit' AND COALESCE(st.sent_at,st.created_at) IS NOT NULL
    AND (COALESCE(st.sent_at,st.created_at) AT TIME ZONE 'Africa/Cairo')::DATE<=p_business_date-8
  GROUP BY
    st.id,st.number,st.from_warehouse_id,fw.name,st.to_warehouse_id,tw.name,tw.branch_id,
    st.status,st.requested_by,st.approved_by,st.sent_by,st.sent_at,st.created_at,
    wr.responsible_user_id,wr.responsibility_unambiguous,
    wr.declared_manager_id,wr.primary_count,wr.sole_primary_user_id
),
transfer_enriched AS (
  SELECT tb.*,rp.full_name::TEXT AS responsible_user_name,
    CASE WHEN tb.responsible_user_id IS NULL THEN false
         ELSE private.work_actor_is_active(tb.responsible_user_id) END AS responsible_user_active
  FROM transfer_base tb
  LEFT JOIN public.profiles rp ON rp.id=tb.responsible_user_id
),
combined AS (
  SELECT
    'inventory:local_shortage:'||se.warehouse_id::TEXT||':'||se.product_id::TEXT AS case_key,
    'local_shortage'::TEXT AS case_type,'exception'::TEXT AS attention_class,
    CASE WHEN se.available_quantity<=0 THEN 'critical'
         WHEN se.coverage_days<3 THEN 'high' ELSE 'medium' END::TEXT AS severity,
    'product'::TEXT AS entity_type,se.product_id AS entity_id,
    se.warehouse_id,se.warehouse_name,se.product_id,se.product_name,NULL::UUID AS transfer_id,
    se.responsible_user_id,se.responsible_user_name,se.responsible_user_active,se.responsibility_unambiguous,
    jsonb_build_object(
      'warehouse_id',se.warehouse_id,'warehouse_name',se.warehouse_name,'branch_id',se.branch_id,
      'product_id',se.product_id,'product_name',se.product_name,'product_sku',se.product_sku,
      'quantity',se.quantity,'reserved_quantity',se.reserved_quantity,'available_quantity',se.available_quantity,
      'wac',se.wac,'demand_window_days',30,'outbound_qty_30d',se.outbound_qty_30d,
      'outbound_movement_count_30d',se.outbound_movement_count_30d,
      'average_daily_outbound',round(se.average_daily_outbound,4),
      'coverage_days',round(se.coverage_days,2),'coverage_threshold_days',7,
      'latest_outbound_at',se.latest_outbound_at,
      'alternate_available_quantity',se.total_alternate_available,
      'alternate_warehouses',se.alternate_warehouses,
      'incoming_transfer_count',se.in_transit_count,
      'incoming_transfer_remaining_qty',se.in_transit_remaining_qty,
      'oldest_incoming_transfer_sent_at',se.oldest_in_transit_sent_at,
      'min_stock_level_authoritative',false,'demand_authority','stock_movements.type=out'
    ) AS facts,
    jsonb_build_object(
      'routing_rule','warehouse_primary_manager_must_be_unique',
      'responsible_user_id',se.responsible_user_id,'responsible_user_name',se.responsible_user_name,
      'responsible_user_active',se.responsible_user_active,'responsibility_unambiguous',se.responsibility_unambiguous,
      'warehouse_declared_manager_id',se.declared_manager_id,
      'warehouse_primary_manager_count',se.primary_count,
      'warehouse_sole_primary_user_id',se.sole_primary_user_id
    ) AS responsibility_evidence,
    jsonb_build_object(
      'source_contract','inventory-v1','deterministic',true,'business_date',p_business_date,
      'stock_balance_current',true,'recent_demand_window_days',30,'coverage_threshold_days',7,
      'min_stock_level_ignored_as_unconfigured',true,'batch_expiry_case_enabled',false,
      'operational_mutation_performed',false
    ) AS trust
  FROM shortage_enriched se

  UNION ALL

  SELECT
    'inventory:stalled_transfer:'||te.transfer_id::TEXT,
    'stalled_transfer'::TEXT,'exception'::TEXT,
    CASE WHEN te.transit_age_days>=30 THEN 'critical'
         WHEN te.transit_age_days>=14 THEN 'high' ELSE 'medium' END::TEXT,
    'stock_transfer'::TEXT,te.transfer_id,
    te.to_warehouse_id,te.to_warehouse_name,NULL::UUID,NULL::TEXT,te.transfer_id,
    te.responsible_user_id,te.responsible_user_name,te.responsible_user_active,te.responsibility_unambiguous,
    jsonb_build_object(
      'transfer_id',te.transfer_id,'transfer_number',te.transfer_number,'status',te.transfer_status,
      'from_warehouse_id',te.from_warehouse_id,'from_warehouse_name',te.from_warehouse_name,
      'to_warehouse_id',te.to_warehouse_id,'to_warehouse_name',te.to_warehouse_name,
      'warehouse_id',te.to_warehouse_id,'warehouse_name',te.to_warehouse_name,
      'branch_id',te.to_branch_id,'requested_by',te.requested_by,'approved_by',te.approved_by,
      'sent_by',te.sent_by,'sent_reference_at',te.sent_reference_at,
      'transit_age_days',te.transit_age_days,'stalled_after_days',7,
      'item_count',te.item_count,'transfer_quantity',te.transfer_quantity,'received_quantity',te.received_quantity
    ),
    jsonb_build_object(
      'routing_rule','destination_warehouse_primary_manager_must_be_unique',
      'responsible_user_id',te.responsible_user_id,'responsible_user_name',te.responsible_user_name,
      'responsible_user_active',te.responsible_user_active,'responsibility_unambiguous',te.responsibility_unambiguous,
      'warehouse_declared_manager_id',te.declared_manager_id,
      'warehouse_primary_manager_count',te.primary_count,
      'warehouse_sole_primary_user_id',te.sole_primary_user_id
    ),
    jsonb_build_object(
      'source_contract','inventory-v1','deterministic',true,'business_date',p_business_date,
      'stalled_transfer_threshold_days',7,
      'threshold_source','inventory_v1_conservative_fallback_no_deployed_transfer_sla',
      'operational_mutation_performed',false
    )
  FROM transfer_enriched te
)
SELECT * FROM combined c
ORDER BY
  CASE c.severity WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END,
  CASE c.case_type WHEN 'local_shortage' THEN 0 ELSE 1 END,c.case_key
LIMIT LEAST(GREATEST(COALESCE(p_limit,50),1),2000);
$$;

REVOKE ALL ON FUNCTION ai_ops.inventory_candidates(DATE,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON FUNCTION ai_ops.inventory_candidates(DATE,INTEGER) IS
  'Read-only deterministic Inventory candidates from actual outbound demand/current availability and stalled in-transit transfers; no min-stock or batch assumptions are invented.';

RESET lock_timeout;
RESET statement_timeout;
