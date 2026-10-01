CREATE TABLE public.fixture_ids(label text PRIMARY KEY,id uuid DEFAULT gen_random_uuid());
INSERT INTO public.fixture_ids(label) VALUES('active'),('dormant'),('ledger'),('draft'),('future'),('cairo'),('newhistorical');
CREATE FUNCTION public.fixture_id(text) RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT id FROM public.fixture_ids WHERE label=$1 $$;
INSERT INTO public.customers(id,current_balance,opening_balance) SELECT id,0,0 FROM public.fixture_ids;
CREATE FUNCTION public.fixture_sale(customer uuid,at_time timestamptz,amt numeric,st sales_order_status DEFAULT 'delivered') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE sid uuid:=gen_random_uuid(); BEGIN
 INSERT INTO sales_orders(id,customer_id,status,order_date,delivered_at,total_amount,subtotal,tax_amount,credit_amount)
 VALUES(sid,customer,st,(at_time AT TIME ZONE 'Africa/Cairo')::date,at_time,amt,amt,0,0);
 INSERT INTO sales_order_items(order_id,product_id,quantity,unit_price,discount_percent,discount_amount,tax_rate,tax_amount,line_total,base_quantity,unit_cost_at_sale)
 VALUES(sid,gen_random_uuid(),1,amt,0,0,0,0,amt,1,0); RETURN sid;
END $$;
SELECT fixture_sale(fixture_id('active'),'2019-01-01 08:00Z',120);
SELECT fixture_sale(fixture_id('active'),'2019-02-01 08:00Z',240);
SELECT fixture_sale(fixture_id('dormant'),'2018-01-01 08:00Z',360);
SELECT fixture_sale(fixture_id('draft'),'2018-01-01 08:00Z',10,'draft');
SELECT fixture_sale(fixture_id('future'),'2019-02-15 08:00Z',480);
SELECT fixture_sale(fixture_id('cairo'),'2019-01-01 22:30Z',600);
INSERT INTO customer_ledger(customer_id,created_at,amount,type,source_type) VALUES(fixture_id('ledger'),'2019-01-15 08:00Z',100,'debit','opening_balance');
CALL analytics.internal_refresh_snapshot_customer_health(ARRAY['2019-01-01'::date,'2019-02-01'::date]);
CALL analytics.internal_refresh_snapshot_customer_risk(ARRAY['2019-01-01'::date,'2019-02-01'::date]);
SELECT analytics.fixture_assert((SELECT count(*)=4 FROM analytics.snapshot_customer_health WHERE as_of_date='2019-02-01')
 AND EXISTS(SELECT 1 FROM analytics.snapshot_customer_health WHERE as_of_date='2019-02-01' AND customer_id=fixture_id('dormant') AND is_dormant)
 AND NOT EXISTS(SELECT 1 FROM analytics.snapshot_customer_health WHERE customer_id IN (fixture_id('draft'),fixture_id('future'))),
 'as-of population includes dormant and ledger customers while excluding draft and future activity');
SELECT analytics.fixture_assert(NOT EXISTS(SELECT 1 FROM analytics.snapshot_customer_health WHERE as_of_date='2019-01-01' AND customer_id IN(fixture_id('ledger'),fixture_id('cairo')))
 AND EXISTS(SELECT 1 FROM analytics.snapshot_customer_health WHERE as_of_date='2019-02-01' AND customer_id=fixture_id('cairo') AND recency_days=30),
 'Cairo sale and ledger boundaries prevent future population leakage');
SELECT analytics.fixture_assert(EXISTS(SELECT 1 FROM analytics.snapshot_customer_health WHERE customer_id=fixture_id('ledger') AND recency_days IS NULL AND frequency_l90d=0 AND monetary_l90d=0 AND NOT is_dormant)
 AND EXISTS(SELECT 1 FROM analytics.snapshot_customer_risk WHERE customer_id=fixture_id('ledger') AND risk_label='DORMANT'),
 'ledger-only customers preserve existing zero-sale health and risk formulas');
CREATE FUNCTION analytics.fixture_snapshot_payload() RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('health',(SELECT jsonb_agg(jsonb_build_array(as_of_date,customer_id,recency_days,frequency_l90d,monetary_l90d,is_dormant) ORDER BY as_of_date,customer_id) FROM analytics.snapshot_customer_health),
 'risk',(SELECT jsonb_agg(jsonb_build_array(as_of_date,customer_id,recency_days,frequency_l90d,monetary_l90d,r_score,f_score,m_score,rfm_score,risk_label) ORDER BY as_of_date,customer_id) FROM analytics.snapshot_customer_risk)) $$;
CREATE TEMP TABLE whole_batch AS SELECT analytics.fixture_snapshot_payload() AS payload;
DELETE FROM analytics.snapshot_customer_health; DELETE FROM analytics.snapshot_customer_risk;
CALL analytics.internal_refresh_snapshot_customer_health(ARRAY['2019-02-01'::date]); CALL analytics.internal_refresh_snapshot_customer_risk(ARRAY['2019-02-01'::date]);
CALL analytics.internal_refresh_snapshot_customer_health(ARRAY['2019-01-01'::date]); CALL analytics.internal_refresh_snapshot_customer_risk(ARRAY['2019-01-01'::date]);
SELECT analytics.fixture_assert((SELECT analytics.fixture_snapshot_payload()=payload FROM whole_batch),'single-date reverse order equals multi-date health and risk population');
CALL analytics.internal_refresh_snapshot_customer_health(ARRAY['2019-02-01'::date,NULL,'2019-01-01'::date,'2019-02-01'::date]);
CALL analytics.internal_refresh_snapshot_customer_risk(ARRAY['2019-01-01'::date,'2019-02-01'::date]);
SELECT analytics.fixture_assert((SELECT analytics.fixture_snapshot_payload()=payload FROM whole_batch),'duplicate unsorted dates and NULL entries do not change per-date output');
CALL analytics.internal_refresh_snapshot_customer_health(NULL); CALL analytics.internal_refresh_snapshot_customer_health('{}');
SELECT analytics.fixture_assert((SELECT analytics.fixture_snapshot_payload()=payload FROM whole_batch),'empty or NULL date arrays leave existing snapshots unchanged');
-- Initial upgrade must repair existing snapshot dates and materialize the current Cairo day.
CALL analytics.run_analytics_watermark_sweep();
SELECT analytics.fixture_assert((SELECT count(*)=2 FROM analytics.component_checkpoints WHERE table_name IN('snapshot_customer_health','snapshot_customer_risk') AND asof_seed_version=1 AND daily_enqueued_through=(now() AT TIME ZONE 'Africa/Cairo')::date AND cardinality(refresh_dates)=0),
 'upgrade durably seeds existing populations and the current Cairo snapshot day');
DELETE FROM analytics.reporting_invalidation_events;
-- A new historical identity has NO prior snapshot row. Existing later dates still need it.
SELECT fixture_sale(fixture_id('newhistorical'),'2019-01-10 08:00Z',1000);
CALL analytics.run_analytics_watermark_sweep();
SELECT analytics.fixture_assert(EXISTS(SELECT 1 FROM analytics.snapshot_customer_health WHERE as_of_date='2019-02-01' AND customer_id=fixture_id('newhistorical') AND recency_days=22 AND monetary_l90d=1000)
 AND EXISTS(SELECT 1 FROM analytics.snapshot_customer_risk WHERE as_of_date='2019-02-01' AND customer_id=fixture_id('newhistorical')),
 'new backdated customer activity populates later dates without requiring prior customer snapshot rows');
DELETE FROM sales_orders WHERE customer_id=fixture_id('newhistorical');
CALL analytics.run_analytics_watermark_sweep();
SELECT analytics.fixture_assert(NOT EXISTS(SELECT 1 FROM analytics.snapshot_customer_health WHERE customer_id=fixture_id('newhistorical'))
 AND NOT EXISTS(SELECT 1 FROM analytics.snapshot_customer_risk WHERE customer_id=fixture_id('newhistorical')),
 'deleting last qualifying activity removes stale population from later health and risk dates');
DELETE FROM customer_ledger WHERE customer_id=fixture_id('ledger');
CALL analytics.run_analytics_watermark_sweep();
SELECT analytics.fixture_assert(NOT EXISTS(SELECT 1 FROM analytics.snapshot_customer_health WHERE customer_id=fixture_id('ledger')),
 'deleting sole ledger activity removes ledger-only customer across later as-of snapshots');
INSERT INTO customer_ledger(customer_id,created_at,amount,type,source_type) VALUES(fixture_id('ledger'),'2019-01-15 08:00Z',100,'debit','adjustment');
CALL analytics.run_analytics_watermark_sweep();
SELECT analytics.fixture_assert(EXISTS(SELECT 1 FROM analytics.snapshot_customer_health WHERE as_of_date='2019-02-01' AND customer_id=fixture_id('ledger')),
 'backdated ledger-only insertion adds customer to existing later dates');
UPDATE customer_ledger SET created_at='2019-03-01 08:00Z' WHERE customer_id=fixture_id('ledger');
CALL analytics.run_analytics_watermark_sweep();
SELECT analytics.fixture_assert(NOT EXISTS(SELECT 1 FROM analytics.snapshot_customer_health WHERE as_of_date='2019-02-01' AND customer_id=fixture_id('ledger'))
 AND EXISTS(SELECT 1 FROM analytics.snapshot_customer_health WHERE as_of_date='2019-03-01' AND customer_id=fixture_id('ledger')),
 'moving qualifying ledger date clears old as-of membership and adds new date');
-- Existing status change to cancelled must remove customer with no other valid activity.
UPDATE sales_orders SET status='cancelled' WHERE customer_id=fixture_id('dormant');
CALL analytics.run_analytics_watermark_sweep();
SELECT analytics.fixture_assert(NOT EXISTS(SELECT 1 FROM analytics.snapshot_customer_health WHERE customer_id=fixture_id('dormant')),
 'cancelled-only activity does not retain an as-of population member');
