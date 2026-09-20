# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-20`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD after the REPORT010 workstream boundary write and before this state write: `ef90d70dc1ad8957a5672205c986d58e08eeb6f6`.
- Current integrated product HEAD: `5df49a61722daaeedd4c0b3f9434628b07f74c29` from completed `DS2-REPORT-009` / PR #56.
- Open PRs targeting Development at selection time: none.
- Active/READY slice: `DS2-REPORT-010 — Churn Risk pie-chart ChartPanel convergence`.
- Representative surface: `src/pages/reports/ChurnRiskPage.tsx` → Pie Chart section `توزيع تصنيف العملاء` only.
- Product Design disposition: `READY — dependency-safe presentation-only boundary recorded`.
- No implementation PR exists yet; no QA or Product Design implementation acceptance is claimed.

## What changed since the previous state

REPORT009 is now integrated and the generic REPORT010 placeholder has been decomposed into one exact presentation concern. I inspected the remaining Reports direction on the latest Development baseline, including `ChurnRiskPage.tsx`, `CustomerHealthPage.tsx`, the existing shared `ChartPanel`, current report test patterns and the component/page/migration/source-audit decision documents.

The workstream now authorizes only the Churn Risk customer-classification pie-chart shell to converge onto the already-proven `ChartPanel`; implementation has not started.

## Independent Product Design judgment

**READY — DS2-REPORT-010 should migrate the Churn Risk pie-chart analytical shell to the existing shared `ChartPanel`, and nothing else.**

This is the smallest dependency-safe next Reports concern with real system value. The Churn Risk page currently rebuilds the same neutral analytical card/header/action framing already owned by `ChartPanel`, but around a different visualization family (`PieChart`). Reusing the established pattern here strengthens the system grammar beyond Area/Bar charts while leaving customer-risk data, classification, chart semantics and trust state fully caller-owned.

I deliberately did not choose the neighboring customer-health/churn-risk tables or raw filter controls for this slice. Those are larger responsive-collection/filter-grammar concerns with broader state and device contracts. They remain valid future debt, but combining them with REPORT010 would violate the one-concern rule.

## Exact source-backed boundary

### In scope

Only the current Churn Risk Pie Chart section:
- render gate: `!statsLoading && pieData.length > 0`;
- exact title: `توزيع تصنيف العملاء`;
- existing conditional `TrustStateBadge + FreshnessIndicator` cluster;
- `ResponsiveContainer width="100%" height={260}`;
- existing `PieChart`, `Pie`, `Cell`, `Tooltip`, `Legend`, `pieData`, `PIE_COLORS`, `innerRadius={60}`, `outerRadius={100}` and `paddingAngle={2}`.

The local outer report card/header wrapper should be replaced by existing `ChartPanel`, using its default semantic `h2` and `action` slot. No `ChartPanel` API or CSS change is expected.

### Preserve exactly

- chart remains completely absent while stats are loading or `pieData` is empty;
- `riskTrust` continues to decide whether the trust badge/freshness controls render;
- `pieData` continues to derive from the existing customer-risk stats and existing filter of zero-value segments;
- chart body height remains 260px;
- all Pie/Recharts geometry, segment order/colors, tooltip formatter and legend behavior remain caller-owned and unchanged;
- customer-risk classification/business meaning remains in the page/domain layer.

### Explicit exclusions

- page header/subtitle;
- `riskLabel` raw select and `asOfDate` date input;
- KPI grid/cards and `RISK_CONFIG` semantics;
- customer detail table and any ResponsiveCollection/table-card migration;
- `RiskBadge`, `RecencyCell`;
- hooks, query/cache semantics, trust calculations, classification/calculation logic, permissions, routing, export/print, backend/business behavior;
- no MetricGrid/StatCard convergence, FilterBar work, Recharts abstraction, legend/tooltip primitive or second report/page.

## Device / state / accessibility acceptance

- **Desktop:** preserve the compact 260px analytical body and reporting density.
- **Tablet:** shared SectionHeader/action composition must wrap safely without fixed-width pressure and retain touch-safe spacing.
- **Mobile:** Arabic title and trust/freshness action may wrap; chart body remains width-contained with no new ordinary page-level horizontal overflow or duplicate renderer.
- **RTL / dark mode:** use the existing semantic `ChartPanel -> Card + SectionHeader` path; no local surface/color override.
- **States:** do not invent loading/empty/blocked/error semantics for this chart; preserve current omission behavior exactly.
- **Accessibility:** improve structural hierarchy from page `h1` to chart-section `h2`; introduce no new interactive/focus behavior and do not reinterpret Recharts semantics.
- **Test artifact:** focused tests should protect shared-panel adoption, exact title/action presence rules, loading/no-data omission, 260px container and unchanged Pie configuration. Evidence must be labeled honestly per `33_TEST_AND_VALIDATION_POLICY.md`.

## Stop / block rule

If implementation requires material shared `ChartPanel` API/CSS widening, changes the render/state meaning of the pie chart, or reveals a functional/query/business dependency, REPORT010 becomes `BLOCKED` and returns to Product Design rather than expanding scope.

## Peer-state synthesis / contradiction handling

Independent direction was formed from current source and system contracts, then checked against repository memory and peer states.

- **Team Memory:** fresh at REPORT009 integration and explicitly hands REPORT010 bounding to Product Design; aligned.
- **Development Integrator:** fresh, confirms REPORT009 merged and exactly one REPORT010 placeholder is ready for bounding; aligned.
- **UI Production Engineer:** lifecycle-stale at REPORT009 implementation, as expected after merge; no contradiction and no current implementation authority until this new boundary.
- **Design QA:** lifecycle-stale at REPORT009 exact-head review, as expected; no contradiction and no approval is reused.
- **Decision Log / North Star / Component System / Page Patterns / Migration Matrix / Source Audit / Component Decision Matrix:** aligned; no durable rule changes.

Current contradiction classification: **NONE**.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the required order.
- Inspected issue #27, exact current Development HEAD, all open PRs targeting Development, representative remaining Reports source and relevant system/blueprint documents.
- Replaced the generic REPORT010 placeholder with the exact Churn Risk pie-chart `ChartPanel` convergence boundary in `31_AGENT_TEAM_WORKSTREAM.md`.
- Updated only the owned `DESIGN_DIRECTOR_STATE.md` among specialist states.
- Did not update `TEAM_MEMORY.md` or `DECISION_LOG.md` because overall system direction and durable rules did not change.
- Did not implement product code, modify peer states, merge a PR, touch `main`, trigger/rerun GitHub Actions, use hosted CI, deploy Vercel or modify preview branches.

### Cross-role handoff
- **To:** UI Production Engineer; then Design QA + Product Design Director on the future stable implementation HEAD.
- **What changed:** REPORT010 is now concretely READY as a one-chart Churn Risk pie-chart migration onto the existing shared `ChartPanel`.
- **Preserve:** exact render gate, Arabic title, trust/freshness presence rules, 260px body, `pieData`/`PIE_COLORS`/Pie/Tooltip/Legend semantics, all KPI/filter/table/query/trust/calculation/permission/routing/export/print/business truth, existing `ChartPanel` API/CSS, and the one-page/one-chart boundary.
- **Need from you:** UI Production should branch from the exact latest Development HEAD after this state write, implement only the bounded chart-shell migration plus focused tests, and open one PR to `design-system-v2-development`. Design QA/Product Design should review only the exact stable PR HEAD afterward.
- **Blocker level:** `NONE`.
- **Baseline:** Product Design selection baseline `3365b4223d5f37d56f3d3af9bb698340935bb95d`; workstream-boundary baseline `ef90d70dc1ad8957a5672205c986d58e08eeb6f6`.
