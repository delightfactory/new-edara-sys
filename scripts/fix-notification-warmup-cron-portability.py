from pathlib import Path

root = Path(__file__).resolve().parents[1]
path = root / 'supabase/migrations/50_notification_dispatch_complete_fix.sql'
text = path.read_text(encoding='utf-8')

old = '''DO $$
BEGIN
  -- Unschedule if exists (idempotent)
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'keep-dispatch-notification-warm') THEN
    PERFORM cron.unschedule('keep-dispatch-notification-warm');
  END IF;
END $$;

SELECT cron.schedule(
  'keep-dispatch-notification-warm',
  '*/10 * * * *',
  $$
    SELECT net.http_post(
      url     := (SELECT value FROM internal_config WHERE key = 'supabase_url')
                 || '/functions/v1/dispatch-notification',
       headers := (
         WITH cfg AS (
           SELECT
             max(case when key = 'service_role_key' then value end) as service_role_key,
             max(case when key = 'internal_dispatch_secret' then value end) as internal_dispatch_secret
           FROM internal_config
           WHERE key in ('service_role_key', 'internal_dispatch_secret')
         )
         SELECT jsonb_build_object('Content-Type', 'application/json')
           || CASE
                WHEN coalesce(nullif(cfg.internal_dispatch_secret, ''), '') <> '' THEN
                  jsonb_build_object('x-internal-secret', cfg.internal_dispatch_secret)
                ELSE
                  jsonb_build_object('Authorization', 'Bearer ' || cfg.service_role_key)
              END
         FROM cfg
       ),
       body    := '{"event_key":"__ping__","user_ids":[]}'::jsonb,
       timeout_milliseconds := 10000
     );
  $$
);
'''

new = '''DO $$
DECLARE
  v_command TEXT;
BEGIN
  -- Fresh/local databases may not have pg_cron and/or pg_net enabled. The
  -- notification dispatch fixes are still valid without the optional warmup.
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron')
     AND to_regclass('cron.job') IS NOT NULL
     AND to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') IS NOT NULL THEN
    BEGIN
      PERFORM cron.unschedule('keep-dispatch-notification-warm');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;

    v_command := $warmup$
      SELECT net.http_post(
        url     := (SELECT value FROM internal_config WHERE key = 'supabase_url')
                   || '/functions/v1/dispatch-notification',
        headers := (
          WITH cfg AS (
            SELECT
              max(case when key = 'service_role_key' then value end) as service_role_key,
              max(case when key = 'internal_dispatch_secret' then value end) as internal_dispatch_secret
            FROM internal_config
            WHERE key in ('service_role_key', 'internal_dispatch_secret')
          )
          SELECT jsonb_build_object('Content-Type', 'application/json')
            || CASE
                 WHEN coalesce(nullif(cfg.internal_dispatch_secret, ''), '') <> '' THEN
                   jsonb_build_object('x-internal-secret', cfg.internal_dispatch_secret)
                 ELSE
                   jsonb_build_object('Authorization', 'Bearer ' || cfg.service_role_key)
               END
          FROM cfg
        ),
        body    := '{"event_key":"__ping__","user_ids":[]}'::jsonb,
        timeout_milliseconds := 10000
      );
    $warmup$;

    PERFORM cron.schedule(
      'keep-dispatch-notification-warm',
      '*/10 * * * *',
      v_command
    );
    RAISE NOTICE '[50_notification_dispatch_complete_fix] notification warmup scheduled';
  ELSE
    RAISE NOTICE '[50_notification_dispatch_complete_fix] pg_cron/pg_net unavailable — warmup not scheduled';
  END IF;
END $$;
'''

if old not in text:
    raise RuntimeError('expected warmup cron block missing')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
Path(__file__).unlink(missing_ok=True)
(root / '.github/workflows/fix-notification-warmup-cron-portability.yml').unlink(missing_ok=True)
