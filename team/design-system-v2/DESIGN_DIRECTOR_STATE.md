# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-22`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD independently inspected before REPORT021 bounding: `bea167f31a36ecde5caf82450e9cc30ed69b5857`.
- Latest integrated product baseline: `DS2-REPORT-020 — Visit Reports responsive detail-collection convergence` / PR #68 / squash merge `92d0091fcd34980a4e91c6626135931a18a199b9`.
- Exact merged implementation HEAD for REPORT020: `9e922249b905bc940534273d658ee817185f3c4a`.
- Open PRs targeting `design-system-v2-development` at selection time: none.
- Workstream boundary commit created this run: `5a870e3eb39f713fdc2aeb2b752f0dfdcb4b1309`.
- Current single implementation-authorized slice: `DS2-REPORT-021 — Receivables summary metric-grid convergence`.
- Disposition: `READY — BOUNDED`.
- Immediate next owner: UI Production Engineer.

## Independent Product Design judgment

REPORT021 should converge exactly one remaining report-summary layout rather than open another broad report page or a new shared abstraction.

The selected concern is `src/pages/reports/ReceivablesPage.tsx` → the three-card AR summary block immediately after `SystemHealthBar` and before the already-migrated AR `ChartPanel`. The current summary still uses the legacy page-local `report-grid` wrapper even though the existing shared `MetricGrid` already provides the correct domain-agnostic responsive metric layout contract.

This is the smallest dependency-safe next step because:
- it removes one remaining local layout implementation using an already-proven shared V2 pattern;
- it does not require a new component, API or shared-style change;
- it preserves report-domain `MetricCard` trust/freshness/status semantics exactly where they are today;
- it deliberately improves Mobile/Tablet/Desktop composition without touching AR data truth or chart semantics;
- broader remaining surfaces such as Customer Reengagement and Rep Credit Commitment combine tables, actions, filters and operational semantics and are therefore not appropriate as the next smallest slice.

## REPORT021 bounded contract

### Representative surface

`src/pages/reports/ReceivablesPage.tsx` → the AR summary metric block only.

### System intent

Replace only the summary's page-local `report-grid` wrapper with existing shared `MetricGrid columns={3}`.

`MetricGrid` remains layout-only. `MetricCard` remains the report-domain component that owns the existing trust/freshness/status presentation. No report meaning may move into the shared grid.

### Exact content to preserve

The ready state keeps exactly three cards in the current order:
1. `صافي التحصيل (Cohort)` — subtitle `منسوب لتاريخ البيع الأصلي` — value `summary?.total_net_cohort` — `BarChart3` icon.
2. `إجمالي الإيصالات` — subtitle `قيمة ما حُصِّل فعلياً` — value `summary?.total_receipt_amount` — `ArrowDownToLine` icon.
3. `إجمالي المردودات النقدية` — subtitle `مسترد من عمليات مرتجع` — value `summary?.total_refunds` — `RotateCcw` icon.

All three retain the current formatter, `arTrust` status, last-completed/freshness/stale wiring and `domain="ar"`.

### Loading/state acceptance

- Summary loading remains exactly three `SkeletonCard height={160}` items.
- Do not invent summary empty/error/blocked semantics that do not exist today.
- Existing page/header/filter/SystemHealthBar behavior remains unchanged.
- Existing AR ChartPanel remains entirely unchanged: title/description, Trust/Freshness action, blocked/loading/empty/ready precedence, exact 260px body contract, chart mapping, margins, axes, tooltip and `receipts / refunds / net` series semantics.

### Device and content acceptance

- Mobile: shared one-column metric stack; no ordinary horizontal overflow.
- Tablet: shared two-column metric composition.
- Desktop: shared three-column comparison.
- Long Arabic labels/subtitles and large currency values must remain wrap-safe and readable.
- Dark/RTL behavior comes from the current shared MetricGrid/MetricCard contracts; no local palette or breakpoint rule is added.

### Focused test intent

Extend the existing Receivables report test artifact to protect:
- shared `MetricGrid` adoption and `data-columns="3"`;
- exact three-card order/content identity;
- exact three loading skeletons at 160px;
- continued isolation of the already-protected AR ChartPanel contract from this metric-layout change.

Execution evidence remains governed by `33_TEST_AND_VALIDATION_POLICY.md`; tests should be authored even if they remain `TESTS_AUTHORED_NOT_EXECUTED`.

### Explicit exclusions

Do not change:
- Sales, Treasury, Overview or any second report;
- `MetricCard`, `MetricGrid`, `ChartPanel`, `ReportFilterBar`, shared CSS or tokens;
- AR chart presentation/data/state semantics;
- page-header/filter grammar;
- global `report-grid` cleanup;
- query/cache/calculation/trust/permission/RBAC/RLS/routing/export/print/backend/service/validation/workflow/business semantics.

If the existing `MetricGrid columns={3}` contract cannot serve this consumer unchanged, or if functional/report semantics would need to change, REPORT021 becomes `BLOCKED` for Product Design re-bounding rather than widening the PR.

## Evidence behind the decision

- `MetricGrid` explicitly accepts `columns={2|3|4}` and owns only responsive KPI/summary layout; business meaning remains caller-owned.
- Its current CSS gives three columns on Desktop, two on Tablet (`769–1024px`) and one on Mobile (`<=768px`), matching the established device strategy without shared changes.
- Receivables currently has exactly one legacy `report-grid` around its three summary cards while its analytical chart is already on shared `ChartPanel`.
- The existing Receivables focused tests already protect the chart contract, making it possible to add a narrow metric-grid regression guard without opening a second concern.

## Peer-state synthesis / contradiction status

This Product Design judgment was formed from the current Development source and shared contracts before peer-state comparison.

- **Development Integrator:** current and aligned; REPORT020 is merged and REPORT021 was explicitly handed to Product Design for one bounded concern.
- **Design QA:** lifecycle-stale at the consumed REPORT020 exact-head approval; no REPORT021 decision or blocker exists yet.
- **UI Production Engineer:** lifecycle-stale at REPORT020 implementation; no competing REPORT021 branch/PR existed when this boundary was selected.
- **Team Memory:** current through REPORT020 but still contains the pre-bound REPORT021 placeholder. That is lifecycle-stale after this material Product Design boundary, not contradictory; overall system direction did not change, so Product Design did not rewrite Team Memory.
- **Decision Log / North Star / device/component guidance:** aligned; no durable decision changed.

Current contradiction classification: `NONE`.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the required order.
- Inspected issue #27, exact latest Development HEAD and confirmed no open PR targeting Development.
- Inspected representative remaining report surfaces and relevant blueprint/component/device guidance.
- Inspected `MetricGrid` API/CSS and the exact Receivables page/test contracts.
- Bounded REPORT021 as `Receivables summary metric-grid convergence` and updated the Workstream in commit `5a870e3eb39f713fdc2aeb2b752f0dfdcb4b1309`.
- Updated only this owned specialist state among role-state files.
- Did not modify Team Memory or Decision Log because no overall system direction or durable rule changed.
- Did not modify product code, merge a PR, touch `main`, trigger/rerun GitHub Actions, use hosted CI, deploy Vercel or modify preview branches.

## What changed since previous state

- REPORT020 moved from accepted implementation awaiting integration to integrated product baseline.
- The placeholder REPORT021 has now been decomposed into exactly one implementation-authorized concern: Receivables AR summary `report-grid` → shared `MetricGrid columns={3}`.
- No design-system blocker, functional change or durable architecture decision was introduced.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA waits for a stable exact PR HEAD.
- **What changed:** `DS2-REPORT-021 — Receivables summary metric-grid convergence` is now `READY — BOUNDED`; only the three-card AR summary wrapper may migrate from legacy `report-grid` to existing `MetricGrid columns={3}`.
- **Preserve:** exact three cards/order/content/icons/formatters/trust/freshness/domain wiring; three 160px loading skeletons; unchanged header/filter/SystemHealthBar and complete AR ChartPanel/state/data/series contract; Mobile 1-column, Tablet 2-column, Desktop 3-column shared metric composition; REPORT001-020 contracts and every query/calculation/permission/export/backend/business truth; no shared API/CSS/token widening and no second report.
- **Need from you:** branch from the latest `design-system-v2-development`, implement REPORT021 only, add focused metric-grid/loading regression coverage alongside the existing chart tests, open exactly one Development-targeting Draft PR, and label execution evidence honestly. If current `MetricGrid` cannot serve unchanged, stop and mark `BLOCKED` rather than widening scope.
- **Blocker level:** `NONE`.
- **Baseline:** exact inspected Development HEAD `bea167f31a36ecde5caf82450e9cc30ed69b5857`; Workstream boundary commit / pre-state-write Development HEAD `5a870e3eb39f713fdc2aeb2b752f0dfdcb4b1309`.
