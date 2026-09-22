# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-22`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD at mandatory bootstrap / independent source inspection: `e26e06b34865aca0e65a1e816779e0c7bb7c416b`.
- Latest integrated product baseline: `DS2-REPORT-022 — Rep Credit Commitment summary metric-grid convergence` / PR #70 / squash merge `5fed58e8ff7c572eecd7427854de83d4c95d759c`.
- Open implementation PRs targeting Development at selection time: `NONE`.
- Current single implementation slice: `DS2-REPORT-023 — Sales summary metric-grid convergence`.
- Current slice state: `READY — BOUNDED`.
- Workstream bounding commit: `d96c745626d6b355baae9d818e92b782ef97722a`; historical-SHA correction/finalized workstream commit: `d63acc081912c32805be9cac1a6c712790d05928`.
- Product Design blocker: `NONE`.

## Independent Product Design judgment

With REPORT022 integrated and no active implementation PR, the placeholder REPORT023 required a concrete dependency-safe boundary. I formed the selection from the current report source and shared-system contracts before comparing peer role states.

The smallest useful next system convergence is the four-card Sales KPI summary in `src/pages/reports/SalesPage.tsx`. That surface still recreates responsive summary layout through the legacy page-level `report-grid`, while the existing `MetricGrid` already owns exactly this presentation responsibility and has a stable layout-only contract. The adjacent Sales analytical surfaces have already converged on shared `ChartPanel`, so isolating the KPI-summary wrapper advances system coherence without mixing chart, filter, query or business concerns.

I considered the analogous Treasury summary as another safe candidate. Sales is the stronger immediate proof because it exercises `MetricGrid columns={4}` with the report-domain `MetricCard` family: Receivables already proves `columns={3}` with `MetricCard`, while REPORT022 proves four-column layout with caller-local KPI shells. This therefore closes a real shared-pattern coverage gap rather than merely repeating a page cosmetic pass.

## REPORT023 bounded contract

### Scope / system intent

Representative surface: `src/pages/reports/SalesPage.tsx` → four-card KPI summary only.

Implementation may:
- import and consume the existing `MetricGrid`;
- replace only the current KPI-summary `<div className="report-grid">` wrapper with `<MetricGrid columns={4}>`;
- extend the focused `SalesPage.test.tsx` source coverage needed to prove the bounded contract.

The shared `MetricGrid` remains unchanged. It owns layout only: Desktop four columns for this caller, Tablet two columns, Mobile one column, with existing `min-width: 0` / `minmax(0, 1fr)` containment.

### Content / truth preservation

Loading must remain exactly four `SkeletonCard height={160}` items under the existing `isLoading = dailyLoading || summaryLoading` gate.

Ready state must preserve these exact four `MetricCard`s and DOM/business order:
1. `صافي الإيراد` — `summary.total_revenue` — `revTrust?.status ?? salesTrust?.status ?? null` — domain `sales` — `TrendingUp`.
2. `إجمالي الضريبة المحصلة` — `summary.total_tax` — `taxTrust?.status ?? salesTrust?.status ?? null` — domain `sales` — `ShoppingBag`.
3. `قيمة المرتجعات` — `summary.total_returns_value` — `revTrust?.status ?? salesTrust?.status ?? null` — domain `sales` — `TrendingDown`.
4. `ذمم عملاء منشأة` — `summary.total_ar_credit` — `arTrust?.status ?? salesTrust?.status ?? null` — domain `ar` — existing no-icon contract.

All current labels, subtitles, `fmtCur` formatting, `lastCompletedAt`, `isStale`, Trust/Freshness semantics and caller-owned report truth remain unchanged.

### Device / RTL / accessibility acceptance

- Desktop: retain dense four-metric comparison in one canonical shared grid.
- Tablet: shared two-column composition.
- Mobile: shared one-column stack with no ordinary KPI-grid horizontal overflow.
- Preserve Arabic-first RTL order, long-label wrapping and large currency-value containment.
- Cards remain informational/non-interactive; no focus target, keyboard path, touch target or action semantics are added or removed.
- No dark-mode/token behavior is changed by this slice; the existing shared grid and cards continue to inherit current semantic surfaces/tokens.

### Explicit exclusions / stop rule

Out of scope:
- both existing Sales `ChartPanel`s, including titles/descriptions/actions, blocked/loading/empty/ready behavior, body heights, chart data mapping, margins, axes, tooltip, gradients and series;
- page header, `ReportFilterBar`, `SystemHealthBar`, Trust/Freshness components and date-range behavior;
- formatting helpers, hooks, query/cache behavior, calculations, data mapping, trust lookup, permissions/RBAC/RLS, routing, backend/services, validation, export/print, workflow or business semantics;
- any shared `MetricGrid` API/CSS/token change;
- global `report-grid` cleanup, `MetricCard` redesign/conversion, or another report page.

If any excluded shared or functional change becomes necessary, REPORT023 becomes `BLOCKED`; the implementation PR must not widen.

### Focused evidence contract

Focused tests should prove:
- the Sales summary adopts `[data-metric-grid]` with `data-columns="4"`;
- exact four-card order/content remains intact;
- loading remains exactly four `160px` placeholders;
- existing Sales chart-panel tests remain intact and continue to guard both analytical sections against drift.

Evidence remains `TESTS_AUTHORED_NOT_EXECUTED` unless an approved exact-head local execution actually occurs. Hosted GitHub Actions/CI remain forbidden.

## Peer-state synthesis / contradiction status

After the independent selection:
- **Integration State / Team Memory:** aligned on REPORT022 being integrated and REPORT023 being the sole placeholder requiring Product Design bounding.
- **UI Production Engineer:** its specialist state is lifecycle-stale at REPORT022 REVIEW; it contains no current REPORT023 implementation and no contradictory system rule.
- **Design QA:** its specialist state is lifecycle-stale at REPORT022 exact-head review; it contains no contradiction with the new boundary.
- **North Star / Decision Log / component and device guidance:** aligned with shared-pattern reuse, Arabic-first responsive composition, Desktop density, Mobile containment and strict functional isolation.
- **Issue #27:** latest lifecycle event confirms REPORT022 DONE and delegates REPORT023 bounding to Product Design.

Current contradiction classification: `NONE`.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the required order.
- Inspected issue #27, current Development HEAD, open PRs targeting Development, current Sales and Treasury report source, Sales focused tests, `MetricGrid`, its responsive CSS, and relevant component/page/device guidance.
- Independently selected and bounded REPORT023 as the Sales summary metric-grid convergence slice.
- Updated `31_AGENT_TEAM_WORKSTREAM.md` to authorize exactly this one bounded implementation slice.
- Updated only this owned specialist state among role-state files.
- Did not modify Team Memory or Decision Log because no overall design direction or durable rule changed.
- Did not implement product code, merge any PR, touch `main`, deploy Vercel, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer.
- **What changed:** `DS2-REPORT-023 — Sales summary metric-grid convergence` is now the single `READY — BOUNDED` implementation slice from the inspected Development baseline `e26e06b34865aca0e65a1e816779e0c7bb7c416b`; the finalized workstream boundary is on Development commit `d63acc081912c32805be9cac1a6c712790d05928`.
- **Preserve:** exact four Sales KPI cards/order/labels/subtitles/values/status fallback/Trust/Freshness/domain/icon contracts; exactly four `160px` loading placeholders and the existing combined loading gate; Mobile 1 / Tablet 2 / Desktop 4 shared MetricGrid composition; both Sales ChartPanels and all filter/header/system-health/query/calculation/permission/backend/business behavior unchanged.
- **Need from you:** start from the latest Development HEAD, implement only the KPI-summary wrapper adoption with existing `MetricGrid columns={4}`, add focused tests for grid adoption/card order/loading preservation, keep existing chart tests intact, and open exactly one REPORT023 implementation PR. If any excluded shared or functional change is required, mark the slice `BLOCKED` instead of widening it.
- **Blocker level:** `NONE`.
- **Baseline:** source-selection baseline `e26e06b34865aca0e65a1e816779e0c7bb7c416b`; finalized workstream HEAD before this state write `d63acc081912c32805be9cac1a6c712790d05928`; latest integrated product merge `5fed58e8ff7c572eecd7427854de83d4c95d759c`.
