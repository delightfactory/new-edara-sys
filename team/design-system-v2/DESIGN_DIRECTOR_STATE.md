# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-22`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD inspected before Product Design bounding: `02fc7acdec0f8ebff0b660fe8317f3ac7f8e3961`.
- Workstream bounding commit: `6b151157d918da24d7fe5a49cfabe48ed7162eec`.
- Latest integrated product baseline: `DS2-REPORT-029 — Geography summary metric-grid convergence` / PR #77 / squash merge `523f547a4259043d33ee77afc5139ffe42c1354e`.
- Open implementation PRs targeting Development at selection time: `none`.
- Active slice: `DS2-REPORT-030 — Rep Performance summary metric-grid convergence`.
- Representative surface: `src/pages/reports/RepPerformancePage.tsx` → four-card KPI summary only.
- Slice state: `READY — BOUNDED`.
- Current blocker classification: `NONE`.

## Independent Product Design judgment

**REPORT030 should converge Rep Performance's remaining local four-KPI summary layout onto the existing shared `MetricGrid columns={4}` contract, and nothing else.**

I formed this judgment from the exact latest Development source and existing shared component/device contracts before comparing peer states. `RepPerformancePage.tsx` already uses the V2 grammar for its comparison chart (`ChartPanel`) and detail collection (`ResponsiveCollection + Card + KeyValueList`), but its summary still uses the legacy page-local `report-grid` wrapper around four `MetricCard`s. The existing `MetricGrid` already supports four columns and owns exactly the responsive layout responsibility needed here, so this is the smallest dependency-safe system convergence available without widening a shared contract or touching business semantics.

I explicitly did **not** choose Customer Re-engagement's five-card KPI strip for this slice: the current shared MetricGrid intentionally supports 2/3/4 columns, while that surface carries five priority/business-accent cards and broader local layout debt. Forcing it into REPORT030 would require a separate shared-contract/design decision rather than a bounded wrapper migration.

## REPORT030 design contract

### In scope

`src/pages/reports/RepPerformancePage.tsx` — replace only the four-KPI summary `<div className="report-grid">` wrapper with the existing shared `<MetricGrid columns={4}>` pattern.

Focused tests should be added to `src/pages/reports/RepPerformancePage.test.tsx` for the bounded summary contract.

### Preserve exactly

- `isLoading = summaryLoading || tableLoading`.
- Exactly four summary `SkeletonCard`s at `height={160}` during the combined loading state.
- Exact KPI order and copy:
  1. `إجمالى الإيراد الصافى`
  2. `مندوبون نشطون`
  3. `متوسط إيراد المندوب`
  4. `إجمالى المرتجعات`
- Exact value/formatter expressions from `summary`.
- Existing `salesTrust` status, `last_completed_at`, stale-state wiring and `domain="sales"` on every metric.
- Existing `TrendingUp`, `Users2`, `Award`, `TrendingDown` icon mapping.
- Arabic/RTL source order and current caller-owned metric semantics.

### Device / state / accessibility acceptance

The existing shared MetricGrid contract supplies the required layout without local breakpoints:
- Desktop `>=1025px`: four equal `minmax(0, 1fr)` columns.
- Tablet `769–1024px`: two columns.
- Mobile `<=768px`: one column.
- Grid maintains `min-width: 0`, avoiding ordinary grid-origin horizontal overflow.
- No interaction is introduced, so there is no new focus/keyboard/touch behavior to invent; existing MetricCard semantics remain authoritative.
- Loading stays within the same shared grid and retains four 160px skeletons.
- No empty/error/permission branch is added or changed by this wrapper-only slice.

### Explicit exclusions

Do not change:
- the already-converged Rep Performance `ChartPanel`, top-15 chart ordering/mapping, axes, tooltip, series, trust/freshness chart actions or chart loading/empty behavior;
- the already-converged `ResponsiveCollection + Card + KeyValueList` detail section, seven-column Desktop table, ranking/return tones, Tablet/Mobile cards, detail loading/empty states or detail data semantics;
- `ReportFilterBar`, date range, `SystemHealthBar`, hooks, query/cache behavior, calculations, formatters, trust resolution, permission/RBAC/RLS, routes, export/print, RPC/DB/backend/workflow/business semantics;
- `MetricGrid`, `MetricCard`, shared CSS, tokens, device breakpoints or any other report/page.

If any excluded shared-contract or functional/business change becomes necessary, REPORT030 is `BLOCKED`; implementation must not widen the slice.

## System coherence rationale

This slice advances a shared grammar rather than beautifying one page. Metric layout is presentation infrastructure and belongs to the already-proven `MetricGrid`; Rep Performance keeps domain values, trust semantics and calculations caller-owned. The same shared pattern is already proven across multiple report domains, so convergence here reduces independent layout implementations without creating a new component variant.

The wider remaining Reports debt remains deliberately outside this slice: Customer Re-engagement's five-card KPI grammar, export drawer, responsive collection debt, broader FilterBar convergence, table hardening and other report/state refinements require their own bounded decisions.

## Peer-state synthesis / contradictions

After forming the independent judgment:

- **Team Memory / Integration State:** aligned that REPORT029 is integrated and REPORT030 is the single next roadmap item requiring Product Design bounding.
- **UI Production / Design QA / prior Product Design states:** lifecycle-stale at REPORT029, as expected after integration; none contains a conflicting REPORT030 rule.
- **Decision Log / North Star / component/device guidance:** aligned with shared-system reuse, caller-owned business semantics, canonical device boundaries and no local mini design systems.
- **Open PR check:** no implementation PR targets `design-system-v2-development`, so creating exactly one bounded READY slice does not compete with active work.

Current contradiction classification: `NONE`.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the prescribed order.
- Inspected issue #27, latest Development HEAD, open PRs targeting Development, relevant Reports source/tests and shared component/device/migration guidance.
- Inspected representative remaining Reports debt and selected the smallest safe REPORT030 concern.
- Updated `docs/design-system-v2/31_AGENT_TEAM_WORKSTREAM.md` to make REPORT030 `READY — BOUNDED` with scope, exclusions and device/state/accessibility acceptance.
- Did not modify `TEAM_MEMORY.md` because the overall system direction did not change; this is normal slice decomposition.
- Did not modify `DECISION_LOG.md` because no durable rule changed.
- Did not implement product code, merge, touch `main`, deploy Vercel, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer, then Design QA / Product Design for exact-head review.
- **What changed:** `DS2-REPORT-030 — Rep Performance summary metric-grid convergence` is now `READY — BOUNDED`; only the Rep Performance four-KPI summary wrapper should move from local `report-grid` to existing `MetricGrid columns={4}`.
- **Preserve:** exact combined loading gate and 4 × 160px skeletons; exact four KPI order/copy/values/formatters/trust/domain/icons; existing ChartPanel and responsive detail contracts; all date/filter/query/calculation/permission/backend/business semantics; unchanged shared MetricGrid/MetricCard API/CSS/tokens/breakpoints.
- **Need from you:** start from the latest Development HEAD, implement REPORT030 only, add focused `data-columns="4"` / KPI-order / loading / trust-domain regression coverage, and open exactly one Draft PR targeting `design-system-v2-development`. If shared-contract or functional widening appears necessary, mark the slice `BLOCKED` instead.
- **Blocker level:** `NONE`.
- **Baseline:** selection baseline `02fc7acdec0f8ebff0b660fe8317f3ac7f8e3961`; workstream bounding commit `6b151157d918da24d7fe5a49cfabe48ed7162eec`.