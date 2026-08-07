#!/usr/bin/env bash
set -euo pipefail

# Read-only production schema capture for the HR V2 isolated rehearsal.
# This script never runs migrations, db push, db reset, or any SQL against production.
# supabase db dump is schema-only by default; application data is intentionally excluded.

SUPABASE_CLI_VERSION="${SUPABASE_CLI_VERSION:-2.110.0}"
SUPABASE_PROJECT_REF="${SUPABASE_PROJECT_REF:-ozthzccqudrudicnneuu}"
OUTPUT_FILE="${1:-${PRODUCTION_SNAPSHOT_FILE:-}}"

if [[ -z "$OUTPUT_FILE" ]]; then
  echo "Production snapshot output path is required." >&2
  exit 2
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"
OUTPUT_FILE="$(cd "$(dirname "$OUTPUT_FILE")" && pwd)/$(basename "$OUTPUT_FILE")"
rm -f "$OUTPUT_FILE"

capture_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$capture_dir"
}
trap cleanup EXIT

capture_with_db_url() {
  echo "Capturing production application schema through a read-only dump command..."
  npx --yes "supabase@${SUPABASE_CLI_VERSION}" db dump \
    --db-url "$PRODUCTION_READONLY_DB_URL" \
    --schema public,analytics,private \
    --keep-comments \
    --file "$OUTPUT_FILE"
}

capture_with_linked_project() {
  echo "Capturing production application schema through the linked project (dump only)..."
  mkdir -p "$capture_dir/project"
  pushd "$capture_dir/project" >/dev/null
  SUPABASE_TELEMETRY_DISABLED=1 npx --yes "supabase@${SUPABASE_CLI_VERSION}" init >/dev/null
  SUPABASE_TELEMETRY_DISABLED=1 \
    SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" \
    SUPABASE_DB_PASSWORD="$SUPABASE_DB_PASSWORD" \
    npx --yes "supabase@${SUPABASE_CLI_VERSION}" link --project-ref "$SUPABASE_PROJECT_REF" >/dev/null
  SUPABASE_TELEMETRY_DISABLED=1 \
    SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" \
    SUPABASE_DB_PASSWORD="$SUPABASE_DB_PASSWORD" \
    npx --yes "supabase@${SUPABASE_CLI_VERSION}" db dump \
      --linked \
      --schema public,analytics,private \
      --keep-comments \
      --file "$OUTPUT_FILE"
  popd >/dev/null
}

if [[ -n "${PRODUCTION_READONLY_DB_URL:-}" ]]; then
  capture_with_db_url
elif [[ -n "${SUPABASE_ACCESS_TOKEN:-}" && -n "${SUPABASE_DB_PASSWORD:-}" ]]; then
  # Compatibility fallback for an already-configured CI connection. The only
  # remote database operation performed is `db dump`.
  capture_with_linked_project
else
  cat >&2 <<'EOF'
No production schema read credential is available to this workflow.
Configure HR_V2_PROD_READONLY_DB_URL (preferred), or the existing
SUPABASE_ACCESS_TOKEN + SUPABASE_DB_PASSWORD pair. No credential is ever
written to the repository or printed by this script.
EOF
  exit 3
fi

if [[ ! -s "$OUTPUT_FILE" ]]; then
  echo "Production schema dump is empty or missing." >&2
  exit 4
fi

# Hard fail if data unexpectedly appears in the dump. Schema-only is the contract.
if grep -Eq '^[[:space:]]*(INSERT[[:space:]]+INTO|COPY[[:space:]].*[[:space:]]FROM[[:space:]]+stdin;)' "$OUTPUT_FILE"; then
  echo "Refusing snapshot: data statements were detected in the production dump." >&2
  rm -f "$OUTPUT_FILE"
  exit 5
fi

# Minimal structural sentinels: these must exist in the current production app schema.
for sentinel in \
  'hr_payroll_runs' \
  'hr_payroll_lines' \
  'hr_attendance_days' \
  'calculate_employee_payroll' \
  'record_attendance_gps_v2'; do
  if ! grep -Fq "$sentinel" "$OUTPUT_FILE"; then
    echo "Refusing snapshot: expected production object '$sentinel' is missing." >&2
    rm -f "$OUTPUT_FILE"
    exit 6
  fi
done

chmod 600 "$OUTPUT_FILE"
echo "Production schema snapshot captured (schema only; no table data)."
