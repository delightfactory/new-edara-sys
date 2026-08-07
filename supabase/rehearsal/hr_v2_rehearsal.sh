#!/usr/bin/env bash
set -euo pipefail

DB_URL="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
ROOT_DIR="${ROOT_DIR:-$(pwd)}"
MIGRATIONS_DIR="$ROOT_DIR/supabase/migrations"
VERIFY_DIR="$ROOT_DIR/supabase/verification"
SNAPSHOT_DIR="$ROOT_DIR/supabase/rehearsal/production_snapshot"
FUNCTION_SNAPSHOT_DIR="$SNAPSHOT_DIR/functions"
SNAPSHOT_VERIFY="$SNAPSHOT_DIR/verify_current_production_snapshot.sql"

run_sql_file() {
  local file="$1"
  echo "::group::apply $(basename "$file")"
  psql "$DB_URL" -X -v ON_ERROR_STOP=1 -f "$file"
  echo "::endgroup::"
}

prepare_exact_function_sql() {
  local source_sql="$1"
  local restore_sql="$2"
  python3 - "$source_sql" "$restore_sql" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_bytes().decode("utf-8")
marker = "AS $function$"
end_marker = "$function$"
start_marker = source.find(marker)
if start_marker < 0:
    raise SystemExit(f"missing {marker!r} in captured function definition")
body_start = start_marker + len(marker)
body_end = source.rfind(end_marker)
if body_end < body_start:
    raise SystemExit("missing closing $function$ in captured function definition")
body = source[body_start:body_end]

# PostgreSQL's SQL scanner can normalize physical line endings while parsing a
# dollar-quoted function definition. Render the captured body as an E-string so
# CR/LF bytes, leading newlines and trailing spaces are restored intentionally.
escaped = (
    body.replace("\\", "\\\\")
        .replace("'", "''")
        .replace("\r", "\\r")
        .replace("\n", "\\n")
        .replace("\t", "\\t")
)
restored = source[:start_marker] + "AS E'" + escaped + "'" + source[body_end + len(end_marker):]
pathlib.Path(sys.argv[2]).write_bytes(restored.encode("utf-8"))
PY
}

run_b64_sql_file() {
  local b64_file="$1"
  local captured_sql restore_sql
  captured_sql="$(mktemp)"
  restore_sql="$(mktemp)"
  echo "::group::apply snapshot $(basename "$b64_file")"
  base64 --decode "$b64_file" > "$captured_sql"
  prepare_exact_function_sql "$captured_sql" "$restore_sql"
  printf ';\n' >> "$restore_sql"
  if ! psql "$DB_URL" -X -v ON_ERROR_STOP=1 -f "$restore_sql"; then
    rm -f "$captured_sql" "$restore_sql"
    echo "::endgroup::"
    return 1
  fi
  rm -f "$captured_sql" "$restore_sql"
  echo "::endgroup::"
}

run_payroll_snapshot_parts() {
  local captured_sql restore_sql
  captured_sql="$(mktemp)"
  restore_sql="$(mktemp)"
  echo "::group::apply snapshot calculate_employee_payroll"
  cat \
    "$FUNCTION_SNAPSHOT_DIR/calculate_employee_payroll.sql.b64.part1" \
    "$FUNCTION_SNAPSHOT_DIR/calculate_employee_payroll.sql.b64.part2" \
    "$FUNCTION_SNAPSHOT_DIR/calculate_employee_payroll.sql.b64.part3" \
    | base64 --decode > "$captured_sql"
  prepare_exact_function_sql "$captured_sql" "$restore_sql"
  printf ';\n' >> "$restore_sql"
  if ! psql "$DB_URL" -X -v ON_ERROR_STOP=1 -f "$restore_sql"; then
    rm -f "$captured_sql" "$restore_sql"
    echo "::endgroup::"
    return 1
  fi
  rm -f "$captured_sql" "$restore_sql"
  echo "::endgroup::"
}

required_files=(
  "$SNAPSHOT_DIR/00_primitives.sql"
  "$SNAPSHOT_DIR/01_hr_runtime_tables.sql"
  "$SNAPSHOT_DIR/02_permission_location_functions.sql"
  "$SNAPSHOT_DIR/02b_attendance_support_functions.sql"
  "$SNAPSHOT_DIR/04_synthetic_fixtures.sql"
  "$SNAPSHOT_VERIFY"
  "$FUNCTION_SNAPSHOT_DIR/process_attendance_penalties.sql.b64"
  "$FUNCTION_SNAPSHOT_DIR/settle_attendance_day_against_leave.sql.b64"
  "$FUNCTION_SNAPSHOT_DIR/is_employee_work_day.sql.b64"
  "$FUNCTION_SNAPSHOT_DIR/mark_daily_absences.sql.b64"
  "$FUNCTION_SNAPSHOT_DIR/run_auto_checkout.sql.b64"
  "$FUNCTION_SNAPSHOT_DIR/upsert_attendance_and_reprocess.sql.b64"
  "$FUNCTION_SNAPSHOT_DIR/record_attendance_gps_v2.sql.b64"
  "$FUNCTION_SNAPSHOT_DIR/calculate_employee_payroll.sql.b64.part1"
  "$FUNCTION_SNAPSHOT_DIR/calculate_employee_payroll.sql.b64.part2"
  "$FUNCTION_SNAPSHOT_DIR/calculate_employee_payroll.sql.b64.part3"
)

for required in "${required_files[@]}"; do
  if [[ ! -f "$required" ]]; then
    echo "Missing isolated rehearsal input: $required" >&2
    exit 10
  fi
done

echo "::group::prepare isolated restore target"
psql "$DB_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon, authenticated;
SQL
echo "::endgroup::"

# Current production-derived HR runtime surface only. No historical migration
# chronology is replayed and the Action has no production credentials/connection.
run_sql_file "$SNAPSHOT_DIR/00_primitives.sql"
run_sql_file "$SNAPSHOT_DIR/01_hr_runtime_tables.sql"
run_sql_file "$SNAPSHOT_DIR/02_permission_location_functions.sql"

# Exact catalog-captured function definitions. Base64 is transport only; the
# restore step preserves the captured function-body bytes before guards run.
run_b64_sql_file "$FUNCTION_SNAPSHOT_DIR/process_attendance_penalties.sql.b64"
run_sql_file "$SNAPSHOT_DIR/02b_attendance_support_functions.sql"
run_b64_sql_file "$FUNCTION_SNAPSHOT_DIR/settle_attendance_day_against_leave.sql.b64"
run_b64_sql_file "$FUNCTION_SNAPSHOT_DIR/is_employee_work_day.sql.b64"
run_b64_sql_file "$FUNCTION_SNAPSHOT_DIR/mark_daily_absences.sql.b64"
run_b64_sql_file "$FUNCTION_SNAPSHOT_DIR/run_auto_checkout.sql.b64"
run_b64_sql_file "$FUNCTION_SNAPSHOT_DIR/upsert_attendance_and_reprocess.sql.b64"
run_b64_sql_file "$FUNCTION_SNAPSHOT_DIR/record_attendance_gps_v2.sql.b64"
run_payroll_snapshot_parts

run_sql_file "$SNAPSHOT_VERIFY"
run_sql_file "$SNAPSHOT_DIR/04_synthetic_fixtures.sql"

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

echo "HR V2 isolated production-derived rehearsal: PASS"
