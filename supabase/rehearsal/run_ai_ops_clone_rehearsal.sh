#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MIGRATIONS_DIR="$ROOT_DIR/supabase/migrations"
VERIFY_SQL="$ROOT_DIR/supabase/rehearsal/verify_ai_ops_clone_context.sql"
DB_URL="${AI_OPS_REHEARSAL_DB_URL:-}"
CONFIRM="${AI_OPS_REHEARSAL_CONFIRM:-}"

if [[ -z "$DB_URL" ]]; then
  echo "AI_OPS_REHEARSAL_DB_URL is required" >&2
  exit 2
fi

if [[ "$CONFIRM" != "ISOLATED_PRODUCTION_CLONE" ]]; then
  echo "Refusing to run: set AI_OPS_REHEARSAL_CONFIRM=ISOLATED_PRODUCTION_CLONE only for an isolated clone." >&2
  exit 2
fi

command -v psql >/dev/null 2>&1 || {
  echo "psql is required" >&2
  exit 2
}

existing_ai_ops="$(psql "$DB_URL" -X -Atq -v ON_ERROR_STOP=1 -c "select exists(select 1 from information_schema.schemata where schema_name='ai_ops');")"
if [[ "$existing_ai_ops" != "f" ]]; then
  echo "Refusing to run: expected a production-derived baseline without ai_ops, but ai_ops already exists." >&2
  exit 3
fi

mapfile -t migrations < <(
  find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '*ai_operations*.sql' -printf '%f\n' | LC_ALL=C sort
)

if [[ ${#migrations[@]} -eq 0 ]]; then
  echo "No AI Operations migrations found" >&2
  exit 4
fi

if [[ "${migrations[0]}" != "20260816163504_ai_operations_foundation.sql" ]]; then
  echo "Unexpected first AI Operations migration: ${migrations[0]}" >&2
  exit 4
fi

if [[ "${migrations[-1]}" != "20260817010300_ai_operations_worker_context_budget_hardening.sql" ]]; then
  echo "Unexpected terminal AI Operations migration: ${migrations[-1]}" >&2
  exit 4
fi

echo "Applying ${#migrations[@]} AI Operations migrations to the confirmed isolated clone..."
for migration in "${migrations[@]}"; do
  echo "==> $migration"
  psql "$DB_URL" -X -v ON_ERROR_STOP=1 -f "$MIGRATIONS_DIR/$migration"
done

echo "==> running realistic seven-domain context gate"
psql "$DB_URL" -X -v ON_ERROR_STOP=1 -f "$VERIFY_SQL"

echo "AI Operations isolated-clone migration + context rehearsal PASS"
