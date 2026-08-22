#!/usr/bin/env bash
set -euo pipefail

CONFIRM="${AI_OPS_REHEARSAL_CONFIRM:-}"
EDGE_URL="${AI_OPS_EDGE_REHEARSAL_URL:-}"
WORKER_SECRET="${AI_OPS_EDGE_REHEARSAL_SECRET:-}"
EXPECT_CLAIM="${AI_OPS_EDGE_EXPECT_CLAIM:-true}"

if [[ "$CONFIRM" != "ISOLATED_PRODUCTION_CLONE" ]]; then
  echo "Refusing to run: set AI_OPS_REHEARSAL_CONFIRM=ISOLATED_PRODUCTION_CLONE only for an isolated clone." >&2
  exit 2
fi

if [[ -z "$EDGE_URL" || -z "$WORKER_SECRET" ]]; then
  echo "AI_OPS_EDGE_REHEARSAL_URL and AI_OPS_EDGE_REHEARSAL_SECRET are required" >&2
  exit 2
fi

case "$EDGE_URL" in
  http://127.0.0.1:*|http://localhost:*|https://*.supabase.co/functions/v1/ai-operations-worker)
    ;;
  *)
    echo "Refusing unexpected Edge URL: $EDGE_URL" >&2
    exit 2
    ;;
esac

response_file="$(mktemp)"
trap 'rm -f "$response_file"' EXIT

http_code="$(curl \
  --silent \
  --show-error \
  --output "$response_file" \
  --write-out '%{http_code}' \
  --max-time 150 \
  --request POST \
  --header 'Content-Type: application/json' \
  --header "x-ai-ops-worker-secret: $WORKER_SECRET" \
  --data '{}' \
  "$EDGE_URL")"

if [[ "$http_code" != "200" ]]; then
  echo "Edge rehearsal returned HTTP $http_code" >&2
  cat "$response_file" >&2
  exit 3
fi

node - "$response_file" "$EXPECT_CLAIM" <<'NODE'
import { readFileSync } from 'node:fs'

const [path, expectClaimRaw] = process.argv.slice(2)
const body = JSON.parse(readFileSync(path, 'utf8'))
const expectClaim = expectClaimRaw === 'true'

if (body?.ok !== true) {
  console.error('Edge worker returned a non-success body:', JSON.stringify(body))
  process.exit(4)
}

if (body?.blocked === true) {
  console.error('Edge worker reached a context/model blocker:', JSON.stringify(body))
  process.exit(4)
}

if (expectClaim && body?.claimed !== true) {
  console.error('Expected the rehearsal Edge worker to claim a prepared due run:', JSON.stringify(body))
  process.exit(4)
}

if (expectClaim && typeof body?.run_id !== 'string') {
  console.error('Claimed rehearsal run did not return run_id:', JSON.stringify(body))
  process.exit(4)
}

if (expectClaim && (!body?.staged || !body?.validated)) {
  console.error('Claimed rehearsal run did not complete stage/validation lifecycle:', JSON.stringify(body))
  process.exit(4)
}

console.log('AI Operations isolated-clone Edge/model lifecycle PASS')
console.log(JSON.stringify({
  claimed: body?.claimed,
  run_id: body?.run_id ?? null,
  staged: Boolean(body?.staged),
  validated: Boolean(body?.validated),
}))
NODE
