#!/usr/bin/env bash
set -euo pipefail

DB_URL="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
ROOT_DIR="${ROOT_DIR:-$(pwd)}"
MIGRATIONS_DIR="$ROOT_DIR/supabase/migrations"
VERIFY_DIR="$ROOT_DIR/supabase/verification"
SNAPSHOT_FILE="${PRODUCTION_SNAPSHOT_FILE:-}"
SNAPSHOT_VERIFY="$ROOT_DIR/supabase/rehearsal/production_snapshot/verify_current_production_snapshot.sql"

run_sql_file() {
  local file="$1"
  echo "::group::apply $(basename "$file")"
  psql "$DB_URL" -X -v ON_ERROR_STOP=1 -f "$file"
  echo "::endgroup::"
}

if [[ -z "$SNAPSHOT_FILE" || ! -s "$SNAPSHOT_FILE" ]]; then
  echo "A current production schema snapshot is required; historical migration reconstruction is disabled." >&2
  exit 10
fi

if [[ ! -f "$SNAPSHOT_VERIFY" ]]; then
  echo "Missing production snapshot verification: $SNAPSHOT_VERIFY" >&2
  exit 11
fi

# Supabase documents that a fresh target can inherit broad default privileges.
# Revoke those defaults locally before restore so explicit dump grants remain authoritative.
echo "::group::prepare isolated restore target"
psql "$DB_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon, authenticated;
SQL
echo "::endgroup::"

echo "::group::restore current production application schema"
psql "$DB_URL" -X -v ON_ERROR_STOP=1 -f "$SNAPSHOT_FILE"
echo "::endgroup::"

run_sql_file "$SNAPSHOT_VERIFY"

# Four early V2 adapters deliberately guard pg_get_functiondef(), whose hash can
# differ solely because a dump/restore normalizes line endings. If and only if
# each normalized function body is the captured production body, reproduce the
# captured production CRLF representation locally. No production object is touched.
echo "::group::materialize exact production guard representation"
psql "$DB_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
DO $representation$
DECLARE
  r record;
  v_definition text;
  v_raw_hash text;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('record_attendance_gps_v2',
       'p_latitude numeric, p_longitude numeric, p_gps_accuracy numeric, p_log_type text, p_event_time timestamp with time zone',
       '12e9b106ce2992fd3268cadfde21558b',
       'bd70c45984e188a38cceb45eea00fa00'),
      ('upsert_attendance_and_reprocess',
       'p_employee_id uuid, p_shift_date date, p_punch_in_time timestamp with time zone, p_punch_out_time timestamp with time zone, p_status hr_attendance_status, p_notes text, p_user_id uuid',
       'e00a7617452d6b2796366b9e9be12e90',
       'a0123e9ec343603dee9adf4ec73739b4'),
      ('is_employee_work_day',
       'p_employee_id uuid, p_date date',
       '561f564a44537961e799f5826cbf865b',
       '3e047334df57ad284bea8e9504724dd0'),
      ('mark_daily_absences',
       'p_target_date date',
       '45983089033bddad79c682d5b58f122e',
       '21e4cb27c5d1008da928cbf14ad56f1b')
    ) AS x(proname, identity_args, normalized_hash, raw_hash)
  LOOP
    SELECT pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
      INTO v_definition, v_raw_hash
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname=r.proname
      AND pg_get_function_identity_arguments(p.oid)=r.identity_args;

    IF v_definition IS NULL THEN
      RAISE EXCEPTION 'Missing production function % during representation materialization', r.proname;
    END IF;

    IF md5(replace((SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                    WHERE n.nspname='public' AND p.proname=r.proname
                      AND pg_get_function_identity_arguments(p.oid)=r.identity_args), E'\r\n', E'\n'))
       IS DISTINCT FROM r.normalized_hash THEN
      RAISE EXCEPTION 'Refusing representation change: normalized production body drifted for %', r.proname;
    END IF;

    IF v_raw_hash IS DISTINCT FROM r.raw_hash THEN
      v_definition := replace(replace(v_definition, E'\r\n', E'\n'), E'\n', E'\r\n');
      EXECUTE v_definition;

      SELECT md5(pg_get_functiondef(p.oid)) INTO v_raw_hash
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname=r.proname
        AND pg_get_function_identity_arguments(p.oid)=r.identity_args;

      IF v_raw_hash IS DISTINCT FROM r.raw_hash THEN
        RAISE EXCEPTION 'Could not reproduce captured production representation for % (actual=%)', r.proname, v_raw_hash;
      END IF;
    END IF;
  END LOOP;
END;
$representation$;
SQL
echo "::endgroup::"

run_sql_file "$MIGRATIONS_DIR/20260807114500_hr_variable_schedules_v2_batch1_schema.sql"
run_sql_file "$VERIFY_DIR/20260807114600_hr_variable_schedules_v2_batch1_verify.sql"

run_sql_file "$MIGRATIONS_DIR/20260807122000_hr_variable_schedules_v2_batch2a_gps_adapter.sql"
run_sql_file "$VERIFY_DIR/20260807122100_hr_variable_schedules_v2_batch2a_verify.sql"

run_sql_file "$MIGRATIONS_DIR/20260807153500_hr_variable_schedules_v2_batch2b_admin_attendance_adapter.sql"
run_sql_file "$VERIFY_DIR/20260807153600_hr_variable_schedules_v2_batch2b_verify.sql"

run_sql_file "$MIGRATIONS_DIR/20260807155500_hr_variable_schedules_v2_batch3a1_workday_classifier.sql"
run_sql_file "$VERIFY_DIR/20260807155600_hr_variable_schedules_v2_batch3a1_verify.sql"

run_sql_file "$MIGRATIONS_DIR/20260807161000_hr_variable_schedules_v2_batch3a2_same_day_absence.sql"
run_sql_file "$VERIFY_DIR/20260807161100_hr_variable_schedules_v2_batch3a2_verify.sql"

run_sql_file "$MIGRATIONS_DIR/20260807164500_hr_variable_schedules_v2_batch3b1_auto_checkout.sql"
run_sql_file "$VERIFY_DIR/20260807164600_hr_variable_schedules_v2_batch3b1_verify.sql"

run_sql_file "$MIGRATIONS_DIR/20260807170500_hr_variable_schedules_v2_batch3b2_early_leave_penalty.sql"
run_sql_file "$VERIFY_DIR/20260807170600_hr_variable_schedules_v2_batch3b2_verify.sql"

run_sql_file "$MIGRATIONS_DIR/20260807172500_hr_variable_schedules_v2_batch3b3_leave_settlement.sql"
run_sql_file "$VERIFY_DIR/20260807172600_hr_variable_schedules_v2_batch3b3_verify.sql"

run_sql_file "$MIGRATIONS_DIR/20260807181500_hr_variable_schedules_v2_batch3c_public_holiday_precedence.sql"
run_sql_file "$VERIFY_DIR/20260807181600_hr_variable_schedules_v2_batch3c_verify.sql"
run_sql_file "$VERIFY_DIR/20260807181700_hr_variable_schedules_v2_batch3c_holiday_simulation.sql"

run_sql_file "$VERIFY_DIR/20260807174000_hr_variable_schedules_v2_batch3_integration_simulation.sql"

run_sql_file "$MIGRATIONS_DIR/20260807184500_hr_variable_schedules_v2_batch4a_payroll_schedule_metrics.sql"
run_sql_file "$VERIFY_DIR/20260807184600_hr_variable_schedules_v2_batch4a_verify.sql"
run_sql_file "$VERIFY_DIR/20260807184700_hr_variable_schedules_v2_batch4a_metrics_simulation.sql"

echo "HR V2 isolated production-snapshot rehearsal: PASS"
