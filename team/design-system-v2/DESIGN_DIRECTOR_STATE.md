# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-22`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development source baseline inspected before Product Design governance writes: `923081b585db5a09ca7a57d240adec14896cc3ad`.
- Exact Development HEAD immediately before this owned-state write: `283c1d7445e943e4b926fb01e5fe6baf8af8db9c`.
- Latest integrated product baseline: `DS2-REPORT-025 — Customer Health summary metric-grid convergence` / PR #73 / squash merge `0e9696f7344da4bff9c2cd75e748472970a63fb2`.
- Active slice: `DS2-REPORT-026 — Product Performance summary metric-grid convergence`.
- Active implementation PR: none; GitHub search found no open PR targeting `design-system-v2-development` before bounding this slice.
- Slice status: `READY — BOUNDED`.
- Workstream bounding commit: `283c1d7445e943e4b926fb01e5fe6baf8af8db9c`.

## Independent Product Design judgment

**REPORT026 is dependency-safe and implementation-ready as one bounded wrapper-only convergence slice.**

I formed the design judgment from the current product/source first, then compared peer states. Among representative remaining Reports debt, Product Performance is the smallest safe next concern: its analytical chart is already on the accepted REPORT011 `ChartPanel`, its details are already on the accepted REPORT006 responsive collection grammar, and only its four-card KPI summary still owns a legacy `report-grid` wrapper. The existing shared `MetricGrid columns={4}` already covers the required layout contract without API/CSS/token widening.

I explicitly did not select the currently visible five-card Customer Reengagement or Churn Risk KPI grids. Both have five-item, caller-colored summary grammars while the shared MetricGrid contract supports only 2/3/4 columns; treating either as a wrapper-only migration would either change deliberate composition without a documented contract or force a broader shared-component decision. REPORT026 therefore stays on Product Performance rather than manufacturing a five-column exception.

## Bounded REPORT026 contract

### Representative surface

`src/pages/reports/ProductPerformancePage.tsx` — the four-card KPI summary immediately after `SystemHealthBar`, and only that summary.

### Intended system change

Replace only the summary's legacy `report-grid` outer wrapper with existing shared `MetricGrid columns={4}`.

The shared primitive remains layout-only. Product metrics, calculation truth, trust/freshness semantics and report/business meaning remain caller-owned.

### Preserve exactly

- Combined summary loading gate: `isLoading = summaryLoading || tableLoading`.
- Exactly four `SkeletonCard height={160}` summary placeholders.
- Ready-card DOM/business order:
  1. `إجمالى الإيراد`
  2. `منتجات نشطة`
  3. `أعلى منتج`
  4. `متوسط نسبة المرتجع`
- Existing labels, subtitles, values, `fmtCur` / `fmtPct`, `salesTrust` status/freshness/stale wiring, `domain="sales"`, and the current TrendingUp / Package / BarChart3 / TrendingDown icon contracts.
- Caller-owned `avgReturnRate` calculation and all summary/table data shaping.
- Existing category selector, `ReportFilterBar`, `SystemHealthBar`, trust-key selection and page hierarchy.
- REPORT011 Product Performance `ChartPanel`: title/description, Trust/Freshness action, 240px loading/empty/chart body, data mapping, chart geometry, grid, axes, tooltip and revenue series.
- REPORT006 Product Performance detail collection: seven-column semantic Desktop table; Tablet/Mobile `ResponsiveCollection + Card + KeyValueList`; exact detail facts, return-rate meaning/threshold styling, loading/empty behavior and one-renderer-per-device isolation.
- All query/cache/service/Supabase RPC/permission/RBAC/RLS/routing/validation/export/print/backend/workflow/business semantics.

### Device / Arabic-first acceptance

- Desktop `>=1025px`: four KPI cards in the existing shared four-column comparison.
- Tablet `769–1024px`: shared two-column composition.
- Mobile `<=768px`: shared one-column stack; no normal summary-grid horizontal scroll.
- Arabic labels/subtitles preserve natural RTL wrapping; existing numeric/currency/percentage treatment remains caller-owned and visually contained.
- The summary is passive information, so no keyboard/focus/touch/action semantic is introduced or removed.

### Explicit exclusions

- No redesign or conversion of report-domain `MetricCard`.
- No five-column MetricGrid variant and no shared API/CSS/token/breakpoint widening.
- No chart, details, filters, header, category-RPC, trust, query or calculation change.
- No backend, DB/RPC contract, cache, permissions, RBAC/RLS, routing, validation, export/print, workflow or business change.
- No opportunistic cleanup elsewhere in Reports.

If any excluded change becomes necessary, REPORT026 becomes `BLOCKED`; implementation must not widen the PR.

## Evidence contract

`ProductPerformancePage.test.tsx` already protects the accepted REPORT006/011 chart and responsive-detail contracts. REPORT026 should add only focused summary evidence:
- shared `[data-metric-grid]` / `data-columns="4"` adoption;
- exact four ready-card labels/order;
- exactly four 160px summary skeletons inside MetricGrid when either side of the existing combined loading gate is active;
- no legacy `.report-grid` ownership for this bounded summary;
- existing chart/detail tests remain unchanged and continue to guard against drift.

Hosted GitHub Actions remain forbidden. Evidence must remain `TESTS_AUTHORED_NOT_EXECUTED` unless an approved exact-head local run actually occurs; no build/runtime/visual PASS may be inferred from source review.

## Peer-state synthesis / contradiction status

I formed the judgment above first, then compared repository memory:
- **Integration State / Team Memory:** current through merged REPORT025 and explicitly hand REPORT026 to Product Design for bounding; aligned.
- **UI Production State / Design QA State:** lifecycle-stale at the completed REPORT025 cycle, but they contain no rule or implementation claim that conflicts with this newly bounded slice.
- **Previous Product Design state:** lifecycle-stale at REPORT025 exact-head acceptance and is superseded by this owned-state update.
- **Decision Log / North Star / component and device guidance:** aligned with shared-pattern reuse, Mobile/Tablet/Desktop adaptation, Arabic-first containment, strict functional isolation and shared-system-before-page-local-invention.
- **Open PRs targeting Development:** none at the time of selection, so there is no competing implementation slice.

Current contradiction classification: `NONE`.

## What changed this run

- REPORT025 is now integrated; the previous Product Design acceptance state was stale.
- The generic REPORT026 placeholder has been converted into one exact implementation contract: Product Performance four-card summary MetricGrid convergence.
- `31_AGENT_TEAM_WORKSTREAM.md` now records REPORT026 as `READY — BOUNDED` with scope, exclusions, device/state/accessibility acceptance and focused evidence.
- No overall Design System direction changed, so `TEAM_MEMORY.md` and `DECISION_LOG.md` were intentionally not mutated.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the prescribed order.
- Inspected issue #27, current Development HEAD, open PRs targeting Development, representative remaining Reports surfaces, Product Performance source/tests, shared `MetricGrid` source/CSS and relevant component/page/migration/device blueprints.
- Updated `31_AGENT_TEAM_WORKSTREAM.md` only to bind the next implementation slice.
- Updated only this owned specialist state among role-state files.
- Did not implement product code, merge a PR, touch `main`, deploy Vercel, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer.
- **What changed:** `DS2-REPORT-026 — Product Performance summary metric-grid convergence` is now `READY — BOUNDED`; the only authorized product change is replacing the four-card Product Performance summary `report-grid` wrapper with existing `MetricGrid columns={4}`.
- **Preserve:** existing `isLoading = summaryLoading || tableLoading`; exactly four 160px skeletons; exact four MetricCards/order/copy/values/formatters/Trust/Freshness/domain/icons; `avgReturnRate`; category/filter/system-health behavior; REPORT011 ChartPanel; REPORT006 responsive details; all shared APIs/CSS/tokens and all query/calculation/permission/backend/business semantics.
- **Need from you:** start from the latest `design-system-v2-development`, implement REPORT026 only, add focused summary tests for shared `data-columns="4"`, exact card order and 4×160px loading, retain existing chart/detail tests, and open exactly one Draft PR targeting Development. If any shared-contract or functional widening is needed, mark the slice `BLOCKED` instead.
- **Blocker level:** `NONE`.
- **Baseline:** Product source inspected at `923081b585db5a09ca7a57d240adec14896cc3ad`; bounded Workstream commit / Development pre-state-write `283c1d7445e943e4b926fb01e5fe6baf8af8db9c`.