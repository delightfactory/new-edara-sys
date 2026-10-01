-- Pre-existing as-of dates are upgraded gradually; no calendar/source event is lost.
DO $$ DECLARE dates date[]; BEGIN
 SELECT array_agg(d::date ORDER BY d) INTO dates FROM generate_series('2020-01-01'::date,'2020-02-29'::date,'1 day') d;
 CALL analytics.internal_refresh_snapshot_customer_health(dates);
 CALL analytics.internal_refresh_snapshot_customer_risk(dates);
END $$;
DELETE FROM analytics.reporting_invalidation_events;
UPDATE analytics.component_checkpoints SET scanned_through=clock_timestamp();
UPDATE analytics.component_checkpoints SET asof_seed_version=0,daily_enqueued_through=(now() AT TIME ZONE 'Africa/Cairo')::date-1
 WHERE table_name IN('snapshot_customer_health','snapshot_customer_risk');
CREATE TEMP TABLE history_versions AS SELECT as_of_date,jsonb_agg(id ORDER BY id) AS ids FROM analytics.snapshot_customer_health GROUP BY as_of_date;
CALL analytics.run_analytics_watermark_sweep();
CREATE TEMP TABLE first_processed AS
SELECT h.as_of_date,jsonb_agg(h.id ORDER BY h.id) AS ids FROM analytics.snapshot_customer_health h JOIN history_versions b USING(as_of_date)
GROUP BY h.as_of_date,b.ids HAVING jsonb_agg(h.id ORDER BY h.id)<>b.ids;
SELECT analytics.fixture_assert((SELECT count(*)=15 FROM first_processed)
 AND EXISTS(SELECT 1 FROM first_processed WHERE as_of_date=(now() AT TIME ZONE 'Africa/Cairo')::date),
 'historical bootstrap rebuilds at most fifteen health dates and prioritizes current Cairo day');
SELECT analytics.fixture_assert((SELECT count(*)=2 FROM analytics.component_checkpoints WHERE table_name IN('snapshot_customer_health','snapshot_customer_risk') AND asof_seed_version=1 AND cardinality(refresh_dates)>0)
 AND (SELECT count(*)=2 FROM analytics.get_system_trust_state() WHERE component_name IN('snapshot_customer_health','snapshot_customer_risk') AND is_stale),
 'seed version means durable scheduling only and historical backlog remains explicitly stale');
SELECT analytics.fixture_assert(NOT EXISTS(SELECT 1 FROM analytics.component_checkpoints WHERE table_name NOT IN('snapshot_customer_health','snapshot_customer_risk') AND cardinality(refresh_dates)>0),
 'health-only bootstrap does not manufacture refresh work for unrelated financial components');
CREATE TEMP TABLE remaining_before AS SELECT table_name,cardinality(refresh_dates) AS n FROM analytics.component_checkpoints WHERE table_name IN('snapshot_customer_health','snapshot_customer_risk');
CALL analytics.run_analytics_watermark_sweep();
SELECT analytics.fixture_assert(NOT EXISTS(SELECT 1 FROM first_processed p WHERE p.ids<>(SELECT jsonb_agg(h.id ORDER BY h.id) FROM analytics.snapshot_customer_health h WHERE h.as_of_date=p.as_of_date)),
 'next bounded sweep advances historical backlog without replaying processed dates');
SELECT analytics.fixture_assert((SELECT count(*)=2 FROM analytics.component_checkpoints cp JOIN remaining_before b USING(table_name) WHERE cardinality(cp.refresh_dates)=b.n-15),
 'both health and dependent risk retain every deferred date and consume matching batches');
DO $$ DECLARE attempts integer:=0; BEGIN
 WHILE EXISTS(SELECT 1 FROM analytics.component_checkpoints WHERE table_name IN('snapshot_customer_health','snapshot_customer_risk') AND cardinality(refresh_dates)>0) LOOP
  CALL analytics.run_analytics_watermark_sweep(); attempts:=attempts+1;
  IF attempts>20 THEN RAISE EXCEPTION 'bounded bootstrap failed to converge'; END IF;
 END LOOP;
END $$;
SELECT analytics.fixture_assert((SELECT count(*)=2 FROM analytics.get_system_trust_state() WHERE component_name IN('snapshot_customer_health','snapshot_customer_risk') AND NOT is_stale)
 AND (SELECT count(DISTINCT as_of_date)=60 FROM analytics.snapshot_customer_health WHERE as_of_date BETWEEN '2020-01-01' AND '2020-02-29'),
 'complete bounded bootstrap preserves all historical dates and restores genuine freshness');
-- A later source correction can expand to the same large history and must obey the same cap.
UPDATE public.sales_orders SET total_amount=total_amount+1 WHERE customer_id=fixture_id('active') AND order_date='2019-01-01';
CALL analytics.run_analytics_watermark_sweep();
SELECT analytics.fixture_assert((SELECT cardinality(refresh_dates)>0 FROM analytics.component_checkpoints WHERE table_name='snapshot_customer_health')
 AND (SELECT (log_output->>'affected_dates_count')::int<=15 FROM analytics.etl_runs WHERE table_name='snapshot_customer_health' ORDER BY started_at DESC LIMIT 1),
 'recurring historical invalidation expansion obeys the same fifteen-date rebuild cap');
