# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-21`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD immediately before this state write: `822c0cf344e0a8b5a816f3b4d575ef7f1cf3cdfa`.
- Current integrated product baseline: `DS2-REPORT-013` / PR #61, squash merge `a9c787f447780f72b7ac0a99b9b9ce0d1f636932`.
- Current single READY slice: `DS2-REPORT-014 — Rep Performance comparison chart-panel convergence`.
- Representative surface: `src/pages/reports/RepPerformancePage.tsx` → chart `مقارنة المندوبين — أعلى 15` only.
- Active implementation PR: none at final pre-write recheck.
- Product Design disposition: `READY — IMPLEMENTATION AUTHORIZED WITH EXACT BOUNDARY / NO DESIGN-SYSTEM BLOCKER`.
- Evidence level: source/design inspection only. Build/test/lint/runtime/preview/release PASS is not claimed.

## Independent Product Design judgment

**READY — NO DESIGN-SYSTEM BLOCKER.**

After REPORT013 integration, I re-audited representative remaining Reports surfaces against the North Star before using peer-state conclusions. The smallest dependency-safe concern is the Rep Performance comparison chart shell: it still rebuilds the same analytical Card/header/trust composition locally even though the shared presentation-only `ChartPanel` contract is already proven across Sales, Receivables, Churn Risk and Product Performance.

REPORT014 should therefore move only that one chart shell to `ChartPanel`. This strengthens shared hierarchy/spacing/RTL/dark/containment grammar without moving chart data, states, calculations or trust meaning into the Design System. Broader high-value debt remains visible — especially Rep Performance and Geography desktop-only wide tables — but mixing those into the same PR would violate one-concern slice discipline.

## Exact REPORT014 boundary

### In scope

Only the Rep Performance analytical chart titled `مقارنة المندوبين — أعلى 15` may change from its page-local Card/header shell to the existing shared `ChartPanel` composition.

Preserve exactly:
- title `مقارنة المندوبين — أعلى 15`;
- description `صافى الإيراد مقابل المرتجعات`;
- current Trust/Freshness action cluster and `salesTrust` conditions/props;
- `tableLoading` -> `SkeletonCard height={300}`;
- empty-state condition `chartData.length === 0`, exact copy and 300px state height;
- `chartData = rows.slice(0, 15)` order/mapping using current `rep_name`, `net_revenue`, `returns_value` truth;
- `ResponsiveContainer` dynamic height `Math.max(chartData.length * 40, 200)`;
- every current BarChart/grid/axis/tooltip/revenue-bar/returns-bar prop, label, value, series color and geometry.

### System/device/accessibility acceptance

- `ChartPanel` remains presentation-only and unchanged; no shared API/CSS widening.
- Page `h1` -> chart `h2` hierarchy is provided by the existing default `ChartPanel` heading level.
- Shared Card/SectionHeader grammar must keep title/description/action content safely contained and wrapping across Mobile/Tablet/Desktop without page-level horizontal escape.
- Arabic-first RTL composition and semantic dark-mode surfaces remain inherited from shared tokens; numeric/currency treatment stays unchanged.
- No duplicate analytical surface or hidden interaction tree is introduced.
- Focused tests must protect title/description/action composition, loading/empty/ready branches, chart-data order/mapping and current series/configuration contract; execution evidence must remain honestly labeled.

### Explicitly out of scope

Do not change:
- `تفصيل الأداء — جميع المندوبين` table or its ranking/row styling;
- KPIs, page header, filters/date controls, `SystemHealthBar`, `CustomTooltip`, or another Reports page;
- `ChartPanel`, `Card`, `SectionHeader`, shared CSS or shared component APIs;
- hooks, data sources, queries/caches, calculations, ranking/order, trust/freshness semantics, permissions/RBAC/RLS, routing, export/print, backend/schema/RPC, business rules, deployments or workflows.

If implementation requires any excluded functional/shared-contract change, REPORT014 becomes `BLOCKED` and returns to Product Design instead of expanding.

## Why this slice precedes other visible Reports debt

- `RepPerformancePage` also has a seven-column Desktop table that is a valid future `ResponsiveCollection` candidate, but that is a materially larger device-composition concern and should remain a separate slice.
- `GeographyPage` has a similar wide-table/mobile-composition gap and remains a strong later candidate.
- `TargetAttainmentPage` also contains a local analytical chart shell, but changing a second chart in REPORT014 would turn a bounded proof into multi-page beautification.
- The selected one-chart migration has the smallest semantic surface area and consumes an already-integrated shared pattern without API invention.

## Peer-state synthesis / contradiction status

Independent source/design judgment above was formed first, then peer states were compared.

- **Development Integrator:** current and aligned. REPORT013 is merged and it explicitly handed REPORT014 selection/bounding to Product Design.
- **UI Production:** Development-branch state is lifecycle-stale at REPORT013 implementation. It creates no current blocker because REPORT013 is already integrated and no REPORT014 implementation has started.
- **Design QA:** Development-branch state is lifecycle-stale at REPORT013 exact-head review. Fresh REPORT014 review will be required after an implementation PR exists.
- **Team Memory / Decision Log / North Star:** no durable design direction changed; no update is required.
- **Open PRs:** none targeting `design-system-v2-development` at the final pre-write recheck, so REPORT014 is the only authorized implementation slice.

Current contradiction classification: **NONE**.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the prescribed order.
- Inspected issue #27, current Development HEAD, open PRs targeting Development, relevant component/page/device/migration guidance and representative remaining Reports source surfaces.
- Independently inspected `RepPerformancePage`, `GeographyPage`, `OverviewPage`, `TargetAttainmentPage`, the shared `ChartPanel` contract and an already-integrated consumer before selecting REPORT014.
- Bounded REPORT014 in `31_AGENT_TEAM_WORKSTREAM.md` at commit `822c0cf344e0a8b5a816f3b4d575ef7f1cf3cdfa`.
- Did not modify product code, peer-owned specialist states, Team Memory or Decision Log.
- Did not merge, touch `main`, trigger/rerun GitHub Actions, use hosted CI, deploy Vercel or modify preview branches.

### Cross-role handoff
- **To:** UI Production Engineer.
- **What changed:** REPORT014 is now source-accurately bounded and implementation-authorized as a one-chart migration: only `RepPerformancePage.tsx` section `مقارنة المندوبين — أعلى 15` moves from the local Card/header shell to the existing shared `ChartPanel` composition.
- **Preserve:** exact chart title/description; Trust/Freshness action cluster; loading/empty/ready precedence and copy/heights; `rows.slice(0, 15)` mapping/order; current ResponsiveContainer dynamic height and complete BarChart/grid/axis/tooltip/two-series configuration; Arabic/RTL, LTR numeric treatment, dark-mode semantics and device containment; unchanged table/KPIs/filters/SystemHealth/CustomTooltip/shared APIs/CSS and all data/query/calculation/ranking/trust/permission/routing/export/print/business semantics.
- **Need from you:** start from the latest `design-system-v2-development` HEAD, create exactly one REPORT014 feature branch/PR, implement only this ChartPanel convergence, author focused tests for the declared contract, and record honest evidence. If any shared API/CSS widening or functional-semantic change is required, stop and mark the slice `BLOCKED` instead of expanding scope.
- **Blocker level:** `NONE`.
- **Baseline:** integrated product merge `a9c787f447780f72b7ac0a99b9b9ce0d1f636932`; exact pre-state-write Development HEAD `822c0cf344e0a8b5a816f3b4d575ef7f1cf3cdfa`; no active implementation PR at final pre-write recheck.