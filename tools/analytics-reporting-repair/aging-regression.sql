-- Simulate calendar advancement by restoring only durable scheduled-through state;
-- no clock override or special production test hook is introduced.
INSERT INTO public.fixture_ids(label) VALUES('aging');
INSERT INTO public.customers(id,current_balance,opening_balance) VALUES(fixture_id('aging'),0,0);
SELECT fixture_sale(fixture_id('aging'),(((now() AT TIME ZONE 'Africa/Cairo')::date-91)::timestamp AT TIME ZONE 'Africa/Cairo'),100);
CALL analytics.internal_refresh_snapshot_customer_health(ARRAY[(now() AT TIME ZONE 'Africa/Cairo')::date-1]);
CALL analytics.internal_refresh_snapshot_customer_risk(ARRAY[(now() AT TIME ZONE 'Africa/Cairo')::date-1]);
SELECT analytics.fixture_assert(EXISTS(SELECT 1 FROM analytics.snapshot_customer_health WHERE as_of_date=(now() AT TIME ZONE 'Africa/Cairo')::date-1 AND customer_id=fixture_id('aging') AND recency_days=90 AND NOT is_dormant),
 'daily aging setup reaches the exact 90-day dormancy boundary yesterday');
DELETE FROM analytics.reporting_invalidation_events;
UPDATE analytics.component_checkpoints SET scanned_through=clock_timestamp();
UPDATE analytics.component_checkpoints SET daily_enqueued_through=(now() AT TIME ZONE 'Africa/Cairo')::date-1,current_day_enqueued=(now() AT TIME ZONE 'Africa/Cairo')::date-1
 WHERE table_name IN('snapshot_customer_health','snapshot_customer_risk');
SELECT analytics.fixture_assert((SELECT count(*)=2 FROM analytics.get_system_trust_state() WHERE component_name IN('snapshot_customer_health','snapshot_customer_risk') AND is_stale),
 'new Cairo day is stale until health and risk daily work has completed');
SET TIME ZONE 'Pacific/Kiritimati';
CALL analytics.run_analytics_watermark_sweep();
RESET TIME ZONE;
SELECT analytics.fixture_assert(EXISTS(SELECT 1 FROM analytics.snapshot_customer_health WHERE as_of_date=(now() AT TIME ZONE 'Africa/Cairo')::date AND customer_id=fixture_id('aging') AND recency_days=91 AND is_dormant AND frequency_l90d=0)
 AND EXISTS(SELECT 1 FROM analytics.snapshot_customer_risk WHERE as_of_date=(now() AT TIME ZONE 'Africa/Cairo')::date AND customer_id=fixture_id('aging') AND risk_label='DORMANT'),
 'idle new-day sweep ages recency and dormancy with no source transactions');
SELECT analytics.fixture_assert((SELECT count(*)=2 FROM analytics.component_checkpoints WHERE table_name IN('snapshot_customer_health','snapshot_customer_risk') AND daily_enqueued_through=(now() AT TIME ZONE 'Africa/Cairo')::date)
 AND (SELECT count(*)=2 FROM analytics.get_system_trust_state() WHERE component_name IN('snapshot_customer_health','snapshot_customer_risk') AND NOT is_stale),
 'daily marker and freshness use Cairo date independently of the session timezone');
CREATE FUNCTION analytics.fixture_health_versions() RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('health',(SELECT jsonb_agg(jsonb_build_array(id,ctid::text,xmin::text) ORDER BY id) FROM analytics.snapshot_customer_health),
 'risk',(SELECT jsonb_agg(jsonb_build_array(id,ctid::text,xmin::text) ORDER BY id) FROM analytics.snapshot_customer_risk)) $$;
CREATE TEMP TABLE same_day_versions AS SELECT analytics.fixture_health_versions() AS versions;
CALL analytics.run_analytics_watermark_sweep();
SELECT analytics.fixture_assert((SELECT analytics.fixture_health_versions()=versions FROM same_day_versions),'repeat same-day idle sweep rewrites no health or risk tuples');
-- Catch-up requests at most fifteen additional calendar dates each sweep.
UPDATE analytics.component_checkpoints SET daily_enqueued_through=(now() AT TIME ZONE 'Africa/Cairo')::date-31
 WHERE table_name IN('snapshot_customer_health','snapshot_customer_risk');
CALL analytics.run_analytics_watermark_sweep();
SELECT analytics.fixture_assert((SELECT count(*)=2 FROM analytics.component_checkpoints WHERE table_name IN('snapshot_customer_health','snapshot_customer_risk') AND daily_enqueued_through=(now() AT TIME ZONE 'Africa/Cairo')::date-16)
 AND (SELECT count(*)=2 FROM analytics.get_system_trust_state() WHERE component_name IN('snapshot_customer_health','snapshot_customer_risk') AND is_stale),
 'calendar catch-up schedules only fifteen days and remains stale while days remain');
CALL analytics.run_analytics_watermark_sweep(); CALL analytics.run_analytics_watermark_sweep();
SELECT analytics.fixture_assert((SELECT count(*)=2 FROM analytics.component_checkpoints WHERE table_name IN('snapshot_customer_health','snapshot_customer_risk') AND daily_enqueued_through=(now() AT TIME ZONE 'Africa/Cairo')::date),
 'bounded catch-up eventually reaches current Cairo day without skipping days');
-- Fault injection only in this disposable cluster; retain failed date for retry.
ALTER PROCEDURE analytics.internal_refresh_snapshot_customer_health(date[]) RENAME TO fixture_real_health;
CREATE PROCEDURE analytics.internal_refresh_snapshot_customer_health(date[]) LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'fixture daily refresh failure'; END $$;
UPDATE analytics.component_checkpoints SET daily_enqueued_through=(now() AT TIME ZONE 'Africa/Cairo')::date-1,current_day_enqueued=(now() AT TIME ZONE 'Africa/Cairo')::date-1
 WHERE table_name IN('snapshot_customer_health','snapshot_customer_risk');
CALL analytics.run_analytics_watermark_sweep();
SELECT analytics.fixture_assert((SELECT count(*)=2 FROM analytics.component_checkpoints WHERE table_name IN('snapshot_customer_health','snapshot_customer_risk') AND refresh_dates @> ARRAY[(now() AT TIME ZONE 'Africa/Cairo')::date])
 AND (SELECT count(*)=2 FROM analytics.get_system_trust_state() WHERE component_name IN('snapshot_customer_health','snapshot_customer_risk') AND is_stale),
 'failed daily health refresh retains durable health and dependent risk retry dates');
DROP PROCEDURE analytics.internal_refresh_snapshot_customer_health(date[]);
ALTER PROCEDURE analytics.fixture_real_health(date[]) RENAME TO internal_refresh_snapshot_customer_health;
CALL analytics.run_analytics_watermark_sweep();
SELECT analytics.fixture_assert((SELECT count(*)=2 FROM analytics.component_checkpoints WHERE table_name IN('snapshot_customer_health','snapshot_customer_risk') AND cardinality(refresh_dates)=0)
 AND (SELECT count(*)=2 FROM analytics.get_system_trust_state() WHERE component_name IN('snapshot_customer_health','snapshot_customer_risk') AND NOT is_stale),
 'restored daily refresh retries pending day without hiding the earlier failure');
UPDATE analytics.component_checkpoints SET daily_enqueued_through=(now() AT TIME ZONE 'Africa/Cairo')::date-1,current_day_enqueued=(now() AT TIME ZONE 'Africa/Cairo')::date-1
 WHERE table_name IN('snapshot_customer_health','snapshot_customer_risk');
TRUNCATE same_day_versions; INSERT INTO same_day_versions SELECT analytics.fixture_health_versions();
BEGIN; CALL analytics.run_analytics_watermark_sweep(); ROLLBACK;
SELECT analytics.fixture_assert((SELECT count(*)=2 FROM analytics.component_checkpoints WHERE table_name IN('snapshot_customer_health','snapshot_customer_risk') AND daily_enqueued_through=(now() AT TIME ZONE 'Africa/Cairo')::date-1)
 AND (SELECT analytics.fixture_health_versions()=versions FROM same_day_versions),
 'caller rollback restores daily marker and derived rows together');
CALL analytics.run_analytics_watermark_sweep();
-- All dates, including more than one orchestrator chunk, must have deterministic population.
SELECT analytics.fixture_assert((SELECT count(DISTINCT as_of_date)=15 FROM analytics.snapshot_customer_health WHERE customer_id=fixture_id('aging') AND as_of_date BETWEEN (now() AT TIME ZONE 'Africa/Cairo')::date-15 AND (now() AT TIME ZONE 'Africa/Cairo')::date-1),
 'dormant customer remains present across multi-chunk daily history');
SELECT analytics.fixture_assert(analytics.txn_date('2026-04-23 22:30Z')='2026-04-24'::date
 AND analytics.txn_date('2026-10-29 22:30Z')='2026-10-30'::date,
 'date helpers retain Cairo daylight-saving boundary mapping');
UPDATE analytics.component_checkpoints SET daily_enqueued_through=(now() AT TIME ZONE 'Africa/Cairo')::date-31,current_day_enqueued=(now() AT TIME ZONE 'Africa/Cairo')::date-31
 WHERE table_name IN('snapshot_customer_health','snapshot_customer_risk');
DELETE FROM analytics.snapshot_customer_health WHERE as_of_date=(now() AT TIME ZONE 'Africa/Cairo')::date;
DELETE FROM analytics.snapshot_customer_risk WHERE as_of_date=(now() AT TIME ZONE 'Africa/Cairo')::date;
CALL analytics.run_analytics_watermark_sweep();
SELECT analytics.fixture_assert(EXISTS(SELECT 1 FROM analytics.snapshot_customer_health WHERE as_of_date=(now() AT TIME ZONE 'Africa/Cairo')::date)
 AND EXISTS(SELECT 1 FROM analytics.snapshot_customer_risk WHERE as_of_date=(now() AT TIME ZONE 'Africa/Cairo')::date)
 AND (SELECT count(*)=2 FROM analytics.component_checkpoints WHERE table_name IN('snapshot_customer_health','snapshot_customer_risk') AND current_day_enqueued=(now() AT TIME ZONE 'Africa/Cairo')::date AND daily_enqueued_through=(now() AT TIME ZONE 'Africa/Cairo')::date-16),
 'after a true month-long outage today is refreshed before historical catch-up finishes');
CREATE TEMP TABLE today_outage_versions AS SELECT id FROM analytics.snapshot_customer_health WHERE as_of_date=(now() AT TIME ZONE 'Africa/Cairo')::date;
CALL analytics.run_analytics_watermark_sweep(); CALL analytics.run_analytics_watermark_sweep();
SELECT analytics.fixture_assert(NOT EXISTS(SELECT 1 FROM today_outage_versions p WHERE NOT EXISTS(SELECT 1 FROM analytics.snapshot_customer_health h WHERE h.id=p.id))
 AND (SELECT count(*)=2 FROM analytics.component_checkpoints WHERE table_name IN('snapshot_customer_health','snapshot_customer_risk') AND daily_enqueued_through=(now() AT TIME ZONE 'Africa/Cairo')::date AND cardinality(refresh_dates)=0),
 'historical catch-up does not replay already processed current-day rows');
