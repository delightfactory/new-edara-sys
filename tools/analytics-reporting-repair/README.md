# Reporting repair regression tests

Run `bash tools/analytics-reporting-repair/run.sh` from a checkout with PostgreSQL 17 and Python 3 available. Optional `release` or `temporal` arguments run one suite. If `pg_config` does not describe your installation, set `PGBIN` and `PGSHARE` to its binary and share directories.

The runner creates two disposable, loopback-only local clusters with synthetic authentication and data. It never accepts a connection string or connects to a pre-existing database. Run as an unprivileged OS user; PostgreSQL refuses root. Each cluster is stopped on exit. Temporary fixture directories/logs remain for inspection, and their paths are printed. Trust authentication is limited to these local throwaway clusters; do not use this setup for a deployed database.

## Coverage

- 34 population, Cairo aging and bounded historical rebuild assertions
- Late atomic DDL failure rolls back the entire release
- Reapplication preserves pending work and retains exactly 17 capture hooks
- 5 historical sale-correction tests check later health/risk snapshots, amounts, recency and cleared old buckets

The release suite therefore has 37 assertions and the temporal suite has 5. The migration payload is SHA-256 pinned to the production-reviewed release. The deliberate failure case is generated in the temporary directory, never written into the migration.

The focused fixtures contain generated test identities and synthetic transactions, a partial source schema, selected source constraints/triggers and the analytics procedure definitions required to exercise this migration. They contain no exported customer or transaction records, credentials, live diagnostic responses, remote endpoints or production settings dump. The installed-contract fixture models the reviewed pre-upgrade routine identities; it is not a database bootstrap for a new application deployment.

These tests do not certify the full production schema, source authorization, all financial RPCs, external hooks or notification delivery. Additional pipeline/concurrency and financial-writer coexistence qualification was performed separately. The selected constraints and source hooks in this fixture remain enabled during tests.

After deployment, observe the normal hourly sweep: current Cairo date should progress first, at most 15 date/month buckets per component should rebuild, and deferred dates must remain pending. Reconciliation failures stay visible. A successful migration or passing synthetic test does not establish a production IO reduction.
