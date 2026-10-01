-- Separate temporal dependency proof using unchanged live population and RFM formulas.
CREATE TABLE public.fixture_ids(label text PRIMARY KEY,id uuid DEFAULT gen_random_uuid());
INSERT INTO public.fixture_ids(label) VALUES('customer'),('order'),('item');
CREATE FUNCTION public.fixture_id(text) RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT id FROM public.fixture_ids WHERE label=$1 $$;
INSERT INTO customers(id,current_balance,opening_balance) VALUES(fixture_id('customer'),0,0);
INSERT INTO sales_orders(id,customer_id,status,order_date,delivered_at,total_amount,subtotal,tax_amount,credit_amount)
 VALUES(fixture_id('order'),fixture_id('customer'),'delivered','2019-01-01','2019-01-01 08:00Z',120,100,20,0);
INSERT INTO sales_order_items(id,order_id,product_id,quantity,unit_price,discount_percent,discount_amount,tax_rate,tax_amount,line_total,base_quantity,unit_cost_at_sale)
 VALUES(fixture_id('item'),fixture_id('order'),gen_random_uuid(),1,100,0,0,20,20,120,1,30);
CALL analytics.run_analytics_watermark_sweep();
-- Establish a genuine later snapshot through the exact existing procedure's batch contract.
CALL analytics.internal_refresh_snapshot_customer_health(ARRAY['2019-01-01'::date,'2019-02-01'::date]);
CALL analytics.internal_refresh_snapshot_customer_risk(ARRAY['2019-01-01'::date,'2019-02-01'::date]);
SELECT analytics.fixture_assert((SELECT recency_days=31 AND monetary_l90d=120 FROM analytics.snapshot_customer_health WHERE as_of_date='2019-02-01' AND customer_id=fixture_id('customer')),
 'temporal fixture has genuine February snapshot for January sale');
UPDATE sales_orders SET total_amount=24000,subtotal=20000,tax_amount=4000 WHERE id=fixture_id('order');
UPDATE sales_order_items SET unit_price=20000 WHERE id=fixture_id('item');
SELECT analytics.fixture_assert((analytics.reporting_batch_dates(ARRAY(SELECT id FROM analytics.reporting_invalidation_events))->'snapshot_customer_health') @> '["2019-02-01"]'::jsonb
 AND (analytics.reporting_batch_dates(ARRAY(SELECT id FROM analytics.reporting_invalidation_events))->'snapshot_customer_risk') @> '["2019-02-01"]'::jsonb,
 'historical amount correction explicitly expands February health and risk dates');
CALL analytics.run_analytics_watermark_sweep();
SELECT analytics.fixture_assert((SELECT monetary_l90d=24000 AND frequency_l90d=1 AND recency_days=31 FROM analytics.snapshot_customer_health WHERE as_of_date='2019-02-01' AND customer_id=fixture_id('customer'))
 AND (SELECT monetary_l90d=24000 AND rfm_score=480 FROM analytics.snapshot_customer_risk WHERE as_of_date='2019-02-01' AND customer_id=fixture_id('customer')),
 'January amount correction recomputes existing February RFM and risk output');
UPDATE sales_orders SET delivered_at='2019-01-10 08:00Z',order_date='2019-01-10' WHERE id=fixture_id('order');
CALL analytics.run_analytics_watermark_sweep();
SELECT analytics.fixture_assert(NOT EXISTS(SELECT 1 FROM analytics.fact_sales_daily_grain WHERE date='2019-01-01')
 AND EXISTS(SELECT 1 FROM analytics.fact_sales_daily_grain WHERE date='2019-01-10' AND tax_inclusive_amount=24000)
 AND (SELECT recency_days=22 AND monetary_l90d=24000 FROM analytics.snapshot_customer_health WHERE as_of_date='2019-02-01' AND customer_id=fixture_id('customer'))
 AND (SELECT recency_days=22 AND rfm_score=580 AND risk_label='LOYAL' FROM analytics.snapshot_customer_risk WHERE as_of_date='2019-02-01' AND customer_id=fixture_id('customer')),
 'January date correction clears old bucket updates new bucket and changes February recency and risk');
SELECT analytics.fixture_assert(NOT EXISTS(SELECT 1 FROM analytics.reporting_invalidation_events),
 'temporal source events acknowledged only after successful materialization or durable retry');
