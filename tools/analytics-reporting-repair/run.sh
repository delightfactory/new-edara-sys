#!/usr/bin/env bash
# Only disposable local clusters. Never accepts a database URL or remote host.
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
MIGRATION="$ROOT/supabase/migrations/20261001161712_analytics_reporting_io_repair.sql"
PGBIN="${PGBIN:-$(pg_config --bindir)}"
PGSHARE="${PGSHARE:-$(pg_config --sharedir)}"
SUITE="${1:-all}"
case "$SUITE" in all|release|temporal) ;; *) echo 'Usage: run.sh [all|release|temporal]' >&2; exit 2 ;; esac
[[ "$($PGBIN/postgres --version)" == *' 17.'* ]] || { echo 'PostgreSQL 17 required' >&2; exit 2; }
# Explicitly ignore any developer-shell connection or password defaults.
unset PGHOST PGHOSTADDR PGPORT PGDATABASE PGUSER PGPASSWORD PGSERVICE PGSERVICEFILE PGOPTIONS
python3 - "$MIGRATION" <<'PY'
import hashlib,sys
assert hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest()=='6bfec34676a90646e9af8252715fe52e43b52e7b0713beaca6779aa6da9f9656', 'Release SQL changed: review and update the expected identity deliberately'
PY
run_suite() (
  suite="$1"
  RUN="$(mktemp -d "${TMPDIR:-/tmp}/edara-reporting-${suite}-XXXXXX")"
  DATA="$RUN/data"
  PORT="$(python3 -c "import socket;s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()")"
  started=0
  cleanup() { if [[ "$started" = 1 ]]; then "$PGBIN/pg_ctl" -D "$DATA" -m fast -w stop >> "$RUN/server.log" 2>&1; fi; }
  trap cleanup EXIT
  "$PGBIN/initdb" -D "$DATA" -L "$PGSHARE" -U fixture_runner --locale=C.UTF-8 -A trust > "$RUN/init.log" 2>&1
  "$PGBIN/pg_ctl" -D "$DATA" -l "$RUN/server.log" -o "-h 127.0.0.1 -p $PORT -k '' -c shared_preload_libraries=''" -w start > "$RUN/start.log" 2>&1
  started=1
  PSQL=("$PGBIN/psql" -X -h 127.0.0.1 -p "$PORT" -U fixture_runner -d postgres -v ON_ERROR_STOP=1)
  echo "RESULT_DIR=$RUN"
  "${PSQL[@]}" -f "$HERE/fixture.sql" > "$RUN/fixture.log" 2>&1
  "${PSQL[@]}" -f "$HERE/source-contract-fixture.sql" > "$RUN/source-contract.log" 2>&1
  "${PSQL[@]}" -f "$HERE/installed-contract-fixture.sql" > "$RUN/installed-contract.log" 2>&1
  if [[ "$suite" = release ]]; then
    python3 - "$MIGRATION" "$RUN/forced-late-failure.sql" <<'PY'
import pathlib,sys
sql=pathlib.Path(sys.argv[1]).read_bytes()
anchor=b'END $atomic_reporting_release$;'
assert sql.count(anchor)==1
pathlib.Path(sys.argv[2]).write_bytes(sql.replace(anchor,b"RAISE EXCEPTION 'synthetic forced late release failure';\n"+anchor))
PY
    set +e
    PGOPTIONS='-c role=postgres' "${PSQL[@]}" -f "$RUN/forced-late-failure.sql" > "$RUN/forced-late-failure.log" 2>&1
    forced_exit=$?
    set -e
    [[ "$forced_exit" != 0 ]]
    grep -q 'ERROR:  synthetic forced late release failure' "$RUN/forced-late-failure.log"
    "${PSQL[@]}" -c "SELECT analytics.fixture_assert(to_regclass('analytics.component_checkpoints') IS NULL AND to_regclass('analytics.reporting_invalidation_events') IS NULL,'single-statement late failure rolls back installed objects');" > "$RUN/atomicity.log" 2>&1
  fi
  PGOPTIONS='-c role=postgres' "${PSQL[@]}" -f "$MIGRATION" > "$RUN/migration.log" 2>&1
  if [[ "$suite" = release ]]; then
    "${PSQL[@]}" -f "$HERE/population-regression.sql" > "$RUN/population.log" 2>&1
    "${PSQL[@]}" -f "$HERE/aging-regression.sql" > "$RUN/aging.log" 2>&1
    "${PSQL[@]}" -c 'CREATE TABLE analytics.fixture_release_state AS SELECT jsonb_agg(to_jsonb(c) ORDER BY table_name) AS state FROM analytics.component_checkpoints c;' > "$RUN/reapply.log" 2>&1
    PGOPTIONS='-c role=postgres' "${PSQL[@]}" -f "$MIGRATION" >> "$RUN/reapply.log" 2>&1
    "${PSQL[@]}" -c "SELECT analytics.fixture_assert((SELECT state=(SELECT jsonb_agg(to_jsonb(c) ORDER BY table_name) FROM analytics.component_checkpoints c) FROM analytics.fixture_release_state),'reapplication preserves checkpoints and daily markers'); SELECT analytics.fixture_assert((SELECT count(*)=17 FROM pg_trigger WHERE tgname='trg_reporting_invalidation'),'reapplication keeps exactly seventeen source hooks');" >> "$RUN/reapply.log" 2>&1
    "${PSQL[@]}" -f "$HERE/bounded-history-regression.sql" > "$RUN/bounded-history.log" 2>&1
    grep -h 'PASS:' "$RUN/atomicity.log" "$RUN/population.log" "$RUN/aging.log" "$RUN/reapply.log" "$RUN/bounded-history.log"
  else
    "${PSQL[@]}" -f "$HERE/temporal-snapshot-closure.sql" > "$RUN/temporal.log" 2>&1
    grep 'PASS:' "$RUN/temporal.log"
  fi
  "${PSQL[@]}" -Atc "SELECT jsonb_build_object('suite','$suite','postgres',version(),'assertions',count(*),'migration','20261001161712') FROM analytics.fixture_assertions" > "$RUN/result.json"
  cat "$RUN/result.json"
)
if [[ "$SUITE" = all ]]; then run_suite release; run_suite temporal; else run_suite "$SUITE"; fi
