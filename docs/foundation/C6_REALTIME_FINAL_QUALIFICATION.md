# C6 — Realtime containment and final local qualification

The candidate passed the bounded two-user actual-App stock test, current PWA test, 141 files/1076 tests, type and lint. Earlier same-build Realtime failures remain material historical evidence; their runtime cause is unresolved. This is scoped local evidence and a reviewable candidate, not production activation or a guarantee of uninterrupted event delivery. Final independent Claude review2b003fa3-57ae-4405-94af-6718e4071120 passed for the local candidate (completed/readOnlyViolation=false); no blocking finding, no reviewer-executed tests.

## Minimal production change

GlobalRealtimeManager used the nonexistent hr_attendance binding and grouped sales_orders with all other bindings. Read-only production metadata shows the canonical hr_attendance_days and sales_orders are not published, while the other nine bindings are. The pinned Realtime v2.134.10 [subscription implementation](https://github.com/supabase/realtime/blob/v2.134.10/lib/extensions/postgres_cdc_rls/subscriptions.ex) creates all bindings in one transaction and rolls back if any binding matches no publication table. Actual local App instrumentation observed join replies followed by a Postgres system error and zero stock subscriptions. This explains the grouped-channel failure; it does not establish the cause of the later two-client intermittent failure or prove the production network symptom.

The change corrects the attendance table name and isolates sales/attendance in two channels. The other nine tables retain the main channel, existing SDK connection, debounce, identity guards and query keys. Cleanup removes all three data channels. No dependency, financial calculation, RLS policy, publication or production service was changed. Unpublished isolated tables remain unavailable for events until their backend publication is qualified separately; isolation prevents them breaking the main channel.

Two real-SDK wire-boundary tests prove the independent HR/sales channels invalidate their existing queries. Synthetic binding IDs start at1 so callbacks are actually dispatched, including the existing stale-identity notification test. These are SDK/component tests, not substitutes for real database events.

## Exact local dependencies

The owned synthetic fixture lacked six bound tables. Their dependency closure comprises16 empty original tables and7 original enum statements, extracted byte-for-byte from sources02/03/17/18/21. The verification SQL and JSON record all23 source/statement hashes and byte boundaries. Absent objects, transactional rollback and preservation of all prior50 rows/functions/ACLs/policies passed. All66 public tables have RLS enabled; added RLS configuration is explicitly distinguished from original source statements. No triggers, module workflows, business seeds or new table privileges were added. This file is a fixture artifact and must not be replayed on production.

## Live event results and finite diagnosis

The single-user actual App stock screen received a real WAL quantity change and refetched stock_read_safe without navigation.13 actual API requests, no pageerrors/external dependency and66-table cleanup parity passed.

The earlier two-browser run, after correcting fixture products.read, failed: both sessions reported Postgres readiness but quantity remained3 rather than4; no restricted stock frame arrived. This result is retained in JSON, not replaced with a success or attributed to permissions/SDK without proof.

One new SQL-side discriminator called the installed realtime.apply_rls with constructed stock WAL and two real synthetic-user claims inside a rolled-back transaction. Own warehouse fans out to both, foreign warehouse to manager only; financial keys are absent and errors empty. This tests the SQL fanout, not live WAL or sockets. Harness generated-column errors occurred before function execution and were corrected explicitly; no persistent data/sequence change was needed.

One subsequent instrumented actual-App run used a freshly started owned Realtime service, the same frontend build and the same UI assertions/timeouts. Before mutation it recorded two distinct authenticated stock subscriptions and active replication slots. Both browser screens updated3→4, then the restricted screen updated4→5 on its own warehouse while receiving no foreign warehouse row or cost keys. Manager and restricted real frames, positive controls and stock_read_safe refetches are recorded:24 API requests, zero pageerrors/external requests, all66 public rows/temporary overrides restored. No production code, SDK, permission policy or assertion was relaxed to obtain this pass. No claim is made that fresh startup resolves the unexplained earlier failure. Do not repeat unchanged experiments; verify the same two-user flow on the intended preview before production promotion.

The owned experimental Realtime service was retired after label checks. Publication tables, realtime subscriptions and replication slots are all0; the four owned core services remain. No other stack was stopped.

## Current PWA, integration and restore

Current production source hashes match the actual-App build and all final browser reports. The current PWA passed real login, controlling SW, warm reload, offline authenticated shell, reconnect, frontend-only cache and explicit same-assets SW update with exactly one navigation and route retention.20 API requests, no pageerrors/external requests,66-table cleanup parity. Offline business writes/data, changed-build asset compatibility and production timing are outside this proof. Earlier bounded cold/warm measurements remain in C6_APP_PWA_COUNT_QUALIFICATION.md.

Focused SDK/component17 tests and full141 files/1076 tests passed, along with tsc-b and lint. The current actual Vite App build passed. No repeated full suite is required for documentation-only changes; no hosted CI was run.

The current66-table private custom archive restored successfully into a fresh template0 database in the same PG17 cluster. All public row digests, auth.users/auth.identities and public function bodies/owners/ACLs match. Fourteen original literal-array CHECKs deparse differently after reparse: varchar array→text array versus per-element varchar→text casts. Only the exact same column/operator/ordered ASCII literal values/casts are accepted; all other captured schema/table-column ACL/RLS/policies/triggers/constraints/index metadata matches exactly. The initial strict digest mismatch is retained; the qualified result is PASS_WITH_EXPLICIT_CHECK_REPARSE. Clone and temporary container dump retired; private archive retained outside Git. Independent-server/global role bootstrap/Auth runtime and financial replay are not certified.

## Handoff boundary

The verified local development slice is ready for independent review and GitHub backup. C7 must identify the exact saved candidate and list production rollout/rollback requirements. Historical intermittent Realtime failure requires preview verification; do not claim that production compatibility or delivery reliability is proven by one local pass. AI/resale remain deferred. No main/DS2 merge, deployment, hosted migration or production data mutation occurred.
