#!/usr/bin/env bash
set -euo pipefail

DB_URL="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
ROOT_DIR="${ROOT_DIR:-$(pwd)}"
MIGRATIONS_DIR="$ROOT_DIR/supabase/migrations"
VERIFY_DIR="$ROOT_DIR/supabase/verification"

run_sql_file() {
  local file="$1"
  echo "::group::apply $(basename "$file")"
  psql "$DB_URL" -X -v ON_ERROR_STOP=1 -f "$file"
  echo "::endgroup::"
}

# Curated HR baseline only. This intentionally excludes production data seeds and
# unrelated sales/analytics/inventory history. In particular, sales-only audit
# migrations are not part of the HR reconstruction.
#
# The baseline gate is fail-closed. It first compares normalized PL/pgSQL bodies
# so Windows CRLF vs Linux LF cannot create a false mismatch. Only after semantic
# parity is proven do we re-serialize the four functions guarded by V2 using the
# CRLF representation captured in production. This lets the original V2 migration
# guards and verification files run UNCHANGED.
BASELINE_FILES=(
  "01_foundation.sql"
  "02_master_data.sql"
  "02b_fixes.sql"
  "03_financial_infrastructure.sql"
  "03b_approval_fixes.sql"
  "03e_rls_hardening.sql"
  "03j_auth_guard.sql"
  "17_hr_core.sql"
  "18_hr_attendance_leaves.sql"
  "19_hr_payroll_loans.sql"
  "19b_hr_core_hotfixes.sql"
  "19c_advances_finance_sync.sql"
  "19d_hr_permissions_fix.sql"
  "20a_attendance_gps_rpc.sql"
  "20b_audit_fixes.sql"
  "20c_hr_adjustments.sql"
  "20g_live_statement_rpc.sql"
  "34_hr_attendance_operational_governance.sql"
  "35_hr_attendance_operational_fixes.sql"
  "36_hr_attendance_daily_review_closure.sql"
  "37_hr_attendance_payroll_coupling.sql"
  "38_hr_payroll_attendance_guard.sql"
  "39_hr_attendance_location_governance.sql"
  "39b_hr_attendance_final_completion.sql"
  "39c_hr_attendance_consistency_fixes.sql"
  "47_hr_attendance_numeric_precision_fix.sql"
  "107_hr_attendance_migration1_foundation.sql"
  "108_hr_attendance_migration2_leave_sync.sql"
  "109_hr_attendance_migration3_daily_absence.sql"
  "110_hr_attendance_migration4_auto_checkout.sql"
  "111_hr_attendance_migration5_leave_settlement.sql"
  "112_hr_attendance_migration6_penalties.sql"
)

for name in "${BASELINE_FILES[@]}"; do
  file="$MIGRATIONS_DIR/$name"
  if [[ ! -f "$file" ]]; then
    echo "Missing baseline migration: $name" >&2
    exit 1
  fi
  run_sql_file "$file"
done

echo "::group::verify normalized production HR baseline"
psql "$DB_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
DO $baseline$
DECLARE
  v_hash text;
BEGIN
  SELECT md5(replace(p.prosrc, E'\r\n', E'\n')) INTO v_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='record_attendance_gps_v2'
    AND pg_get_function_identity_arguments(p.oid)=
      'p_latitude numeric, p_longitude numeric, p_gps_accuracy numeric, p_log_type text, p_event_time timestamp with time zone';
  IF v_hash IS DISTINCT FROM '12e9b106ce2992fd3268cadfde21558b' THEN
    RAISE EXCEPTION 'Normalized baseline mismatch: record_attendance_gps_v2 = %', v_hash;
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n')) INTO v_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='upsert_attendance_and_reprocess'
    AND pg_get_function_identity_arguments(p.oid)=
      'p_employee_id uuid, p_shift_date date, p_punch_in_time timestamp with time zone, p_punch_out_time timestamp with time zone, p_status hr_attendance_status, p_notes text, p_user_id uuid';
  IF v_hash IS DISTINCT FROM 'e00a7617452d6b2796366b9e9be12e90' THEN
    RAISE EXCEPTION 'Normalized baseline mismatch: upsert_attendance_and_reprocess = %', v_hash;
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n')) INTO v_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='is_employee_work_day'
    AND pg_get_function_identity_arguments(p.oid)='p_employee_id uuid, p_date date';
  IF v_hash IS DISTINCT FROM '561f564a44537961e799f5826cbf865b' THEN
    RAISE EXCEPTION 'Normalized baseline mismatch: is_employee_work_day = %', v_hash;
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n')) INTO v_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='mark_daily_absences'
    AND pg_get_function_identity_arguments(p.oid)='p_target_date date';
  IF v_hash IS DISTINCT FROM '45983089033bddad79c682d5b58f122e' THEN
    RAISE EXCEPTION 'Normalized baseline mismatch: mark_daily_absences = %', v_hash;
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n')) INTO v_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='run_auto_checkout'
    AND pg_get_function_identity_arguments(p.oid)='p_target_date date';
  IF v_hash IS DISTINCT FROM 'd13869f50592c2dc31c63e9212183c81' THEN
    RAISE EXCEPTION 'Normalized baseline mismatch: run_auto_checkout = %', v_hash;
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n')) INTO v_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='process_attendance_penalties'
    AND pg_get_function_identity_arguments(p.oid)='p_attendance_day_id uuid';
  IF v_hash IS DISTINCT FROM 'c05f834d11387ab8312965c16a065a0a' THEN
    RAISE EXCEPTION 'Normalized baseline mismatch: process_attendance_penalties = %', v_hash;
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n')) INTO v_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='settle_attendance_day_against_leave'
    AND pg_get_function_identity_arguments(p.oid)='p_attendance_day_id uuid, p_force boolean';
  IF v_hash IS DISTINCT FROM 'f0cd9bc5b6787e76aa970de6a9ce9370' THEN
    RAISE EXCEPTION 'Normalized baseline mismatch: settle_attendance_day_against_leave = %', v_hash;
  END IF;
END;
$baseline$;
SQL
echo "::endgroup::"

# Production currently stores the captured legacy PL/pgSQL bodies with CRLF line
# endings. Git checkout on the Linux runner materializes the same SQL as LF. The
# V2 migration guards intentionally use the raw production definition hashes, so
# normalize ONLY this disposable database representation back to CRLF after the
# semantic normalized-body gate above has already proven parity.
echo "::group::materialize captured production function representation"
psql "$DB_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
DO $representation$
DECLARE
  v_oid oid;
  v_definition text;
BEGIN
  FOR v_oid IN
    SELECT p.oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'record_attendance_gps_v2',
        'upsert_attendance_and_reprocess',
        'is_employee_work_day',
        'mark_daily_absences'
      )
  LOOP
    v_definition := pg_get_functiondef(v_oid);
    EXECUTE replace(v_definition, E'\n', E'\r\n');
  END LOOP;
END;
$representation$;

DO $raw_gate$
DECLARE
  v_hash text;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)) INTO v_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='record_attendance_gps_v2'
    AND pg_get_function_identity_arguments(p.oid)=
      'p_latitude numeric, p_longitude numeric, p_gps_accuracy numeric, p_log_type text, p_event_time timestamp with time zone';
  IF v_hash IS DISTINCT FROM 'bd70c45984e188a38cceb45eea00fa00' THEN
    RAISE EXCEPTION 'Raw production representation mismatch: record_attendance_gps_v2 = %', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef(p.oid)) INTO v_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='upsert_attendance_and_reprocess'
    AND pg_get_function_identity_arguments(p.oid)=
      'p_employee_id uuid, p_shift_date date, p_punch_in_time timestamp with time zone, p_punch_out_time timestamp with time zone, p_status hr_attendance_status, p_notes text, p_user_id uuid';
  IF v_hash IS DISTINCT FROM 'a0123e9ec343603dee9adf4ec73739b4' THEN
    RAISE EXCEPTION 'Raw production representation mismatch: upsert_attendance_and_reprocess = %', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef(p.oid)) INTO v_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='is_employee_work_day'
    AND pg_get_function_identity_arguments(p.oid)='p_employee_id uuid, p_date date';
  IF v_hash IS DISTINCT FROM '3e047334df57ad284bea8e9504724dd0' THEN
    RAISE EXCEPTION 'Raw production representation mismatch: is_employee_work_day = %', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef(p.oid)) INTO v_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='mark_daily_absences'
    AND pg_get_function_identity_arguments(p.oid)='p_target_date date';
  IF v_hash IS DISTINCT FROM '21e4cb27c5d1008da928cbf14ad56f1b' THEN
    RAISE EXCEPTION 'Raw production representation mismatch: mark_daily_absences = %', v_hash;
  END IF;
END;
$raw_gate$;
SQL
echo "::endgroup::"

# Each batch is verified immediately after its migration and before the next batch
# is allowed to mutate any contract that the previous batch intentionally froze.
# This preserves the meaning of batch-local assertions (for example Batch 3A1
# proves mark_daily_absences is untouched before Batch 3A2 deliberately wraps it).
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

echo "HR V2 isolated database rehearsal: PASS"
