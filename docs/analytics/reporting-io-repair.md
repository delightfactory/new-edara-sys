# Analytics reporting replay repair

This migration replaces repeated full fact rebuilding for unchanged blocked comparisons with durable per-component processing and reconciliation retries. It keeps financial comparison errors visible. Processing a source change is not a certification that accounting reconciliation succeeded.

Seventeen source tables emit private transactional reporting invalidations containing old/new identity/date metadata. The worker consumes explicit committed IDs, never a maximum sequence watermark. Date expansion handles historical corrections, deleted/moved records, geography and monthly allocation/headcount changes. A source operation fails atomically if its reporting event cannot be recorded; silently dropping events is intentionally prohibited.

Customer health/risk now use a deterministic per-date population: customers with delivered/completed sales or recorded customer-ledger activity on or before the Cairo as-of date. Dormant customers remain visible. Draft/cancelled-only and future activity do not establish membership. Existing RFM measures, date window thresholds and risk scoring are retained.

Daily aging is requested once per Cairo day even without source transactions. Separate current-day and contiguous-history markers prioritize today's snapshot after outages without repeatedly rewriting it during historical catch-up. Historical population initialization and later corrections rebuild at most 15 date/month buckets per component per sweep; all deferred dates remain durable. The seed-version marker records scheduling, not successful completion. Reports stay explicitly stale while their rebuild/review backlog remains.

The deployment is a single atomic SQL statement. Preconditions verify the reviewed routine bodies, ownership, required source types/RLS and analytics coordination lock. A late installation failure rolls back all changes. Reapplication preserves checkpoint/event state. It adds two private RLS tables, internal helpers and 17 hooks, and changes the analytics sweep, health procedure and guarded trust reader. It does not change source policies, financial procedures, cron cadence or public RPC signatures.

## Deployment and verification

Apply only this release migration, not the preparation components used during review. Do not blindly replay historical repository migrations into an existing database. Confirm the connected project, inspect the live migration ledger, save current definitions/ACL and capture baseline counters first. When a migration API assigns the version, retain its actual returned history identity in the repository audit without changing SQL contents.

Prefer observing the next normal hourly sweep to running extra manual refreshes. Check installed hashes, 17 enabled hooks, private ACL/RLS, current-day coverage, durable backlog progress and no repeated unchanged-bucket writes. Compare WAL/table-write/runtime counters using the same statistics-reset window; correlate with physical IO telemetry. No production improvement percentage is implied by synthetic benchmarks.

A full application/notification/authentication certification is outside the bounded analytics tests. Critical financial-writer coexistence, locking and rollback were checked differentially without rewriting those routines. An existing positive-clawback formatting defect was reproduced unchanged and is a separate financial issue.

## Rollback

Coordinate an emergency reversal under the same analytics lock. Retain events and checkpoint arrays. If capture hooks must be suspended, record the outage, restore the exact saved legacy procedures and keep reports stale until an explicit rebuild covers the gap. Reverting restores the old replay/population defects; it is not a healthy steady state. Never delete pending work, suppress comparison failures or advance a watermark blindly.

## Release identity

- Base source revision: `52154ce8a0fe6ce431bf07c72b73cee8befe0cf5`
- Applied database migration: `20261001161712_analytics_reporting_io_repair` (2026-10-01 16:17 UTC)
- SQL SHA-256: `6bfec34676a90646e9af8252715fe52e43b52e7b0713beaca6779aa6da9f9656`
- The connector-assigned migration version above replaces the preparation filename only; SQL bytes are unchanged
- Installation checks confirmed the expected routine bodies, 17 enabled hooks and private table privileges/RLS. Runtime improvement must be established from normal scheduled sweeps and counter windows

Focused regression assets are under `tools/analytics-reporting-repair`. Their runner always creates disposable local PostgreSQL clusters. It accepts no production connection string. The fixtures contain synthetic records and a partial schema plus selected implementation definitions; they are not a complete application replica.
