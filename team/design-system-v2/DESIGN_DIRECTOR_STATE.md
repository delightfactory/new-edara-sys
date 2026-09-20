# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-20`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD immediately before this state write: `b5e3c3d873de2d7e6db1f76b9ed287b528059418`.
- Current integrated product HEAD: `5d6ee46bc716f6da39367c87e87608f30929c734` from completed `DS2-REPORT-010` / PR #57.
- Active slice: `DS2-REPORT-011 — Product Performance revenue chart-panel convergence`.
- Product Design inspection baseline before bounding: `80ec9ed679ed8f2bf7f96fb98c84a1df4f2224ee`.
- Workstream boundary commit: `b5e3c3d873de2d7e6db1f76b9ed287b528059418`.
- Active implementation PR: none at selection/recheck time.
- Product Design disposition: `READY — one presentation-only chart concern is dependency-safe for UI Production`.

## What changed since the previous state

REPORT010 is integrated. I inspected the exact current Reports baseline and representative remaining analytical surfaces, formed an independent Product Design judgment, then compared peer states and shared memory.

REPORT011 is now bounded to exactly one remaining page-local analytical shell in `ProductPerformancePage.tsx`: chart section `أعلى 15 منتجاً بالإيراد`. The already-proven shared `ChartPanel -> Card + SectionHeader` contract fits directly; no new shared API, CSS contract or business semantic is required.

## Independent Product Design judgment

**READY — DS2-REPORT-011: Product Performance revenue chart-panel convergence.**

This is the smallest useful next system-convergence step. Product Performance already uses the V2 responsive collection grammar for its detail data, but its revenue chart still rebuilds the analytical card/header shell locally. Converging that single section onto the existing neutral `ChartPanel` removes another page-local mini-system and extends the same analytical hierarchy already proven in Sales, Receivables and Churn Risk.

This is preferable to opening broader Customer Health table, filter-bar or responsive-table work because those concerns carry wider component/state/device implications and deserve separately bounded slices.

## Exact implementation boundary

Representative surface:
- `src/pages/reports/ProductPerformancePage.tsx`
- chart section `أعلى 15 منتجاً بالإيراد` only.

UI Production should:
- replace only the chart's local outer surface/header composition with existing shared `ChartPanel`;
- preserve exact title `أعلى 15 منتجاً بالإيراد`;
- preserve exact description `مرتب تنازلياً حسب صافى الإيراد`;
- preserve the current `salesTrust` presence rule for `TrustStateBadge + FreshnessIndicator` via the panel action area;
- preserve the exact three body states:
  - `tableLoading` -> `SkeletonCard height={240}`;
  - `chartData.length === 0` -> exact `لا توجد بيانات` copy in a centered 240px body;
  - otherwise `ResponsiveContainer width="100%" height={240}`;
- preserve `chartData`, BarChart margins, CartesianGrid, X/Y axes, tick/angle/text-anchor behavior, `CustomTooltip`, and the exact revenue Bar configuration;
- use the shared default semantic `h2` path;
- add/update focused `ProductPerformancePage.test.tsx` coverage for shared-panel adoption plus title/description/action/state/240px/chart-contract preservation.

## Device / Arabic / dark / accessibility acceptance

- **Desktop:** retain the current compact 240px analytical density and all comparative chart information.
- **Tablet:** shared `SectionHeader` must permit deliberate title/description/action wrapping without fixed-width pressure.
- **Mobile:** no new ordinary page-level horizontal overflow, no duplicate renderer, and chart-body containment must remain width-safe.
- **Arabic/RTL:** preserve exact Arabic copy and logical shared layout; long heading/action content must wrap safely.
- **Dark mode:** use the existing semantic V2 panel surface/border/text path; introduce no page-local color/surface contract.
- **Accessibility:** establish page `h1 -> h2` section hierarchy; do not invent new Recharts or trust-control interaction semantics.

No runtime visual/build/test execution evidence is claimed at this direction stage.

## Explicit exclusions / functional isolation

REPORT011 must not change:
- Product Performance page header or category selector;
- `ReportFilterBar` or `SystemHealthBar`;
- KPI `MetricCard`s;
- `ResponsiveCollection` detail section, Desktop table or Tablet/Mobile detail-card composition established by REPORT006;
- category RPC, hooks, query/cache semantics, sorting/top-15 derivation, calculations or trust meaning;
- permissions, routing, export/print, validation, backend or business semantics;
- shared `ChartPanel` API/CSS;
- Recharts abstraction or any second page/report.

If implementation discovers that a material shared-contract change or functional-semantic change is actually required, REPORT011 becomes `BLOCKED` and returns to Product Design instead of expanding the PR.

## Peer-state synthesis / contradiction handling

Independent design judgment was formed from current source and shared contracts before peer-state comparison.

- **Team Memory:** fresh after REPORT010 integration and explicitly delegates REPORT011 bounding to Product Design; aligned.
- **Development Integrator:** fresh and aligned; REPORT010 is merged and REPORT011 is the sole READY roadmap item awaiting this boundary.
- **UI Production Engineer:** Development copy is lifecycle-stale at REPORT010 implementation, as expected after merge; no contradictory durable rule exists.
- **Design QA:** Development copy is lifecycle-stale at REPORT010 exact-head review, as expected; no REPORT011 approval is assumed.
- **Previous Director State:** lifecycle-stale at REPORT010 closeout and is superseded by this owned update.
- **Decision Log / North Star / Component System / Page Patterns / Component Decision Matrix:** aligned; no durable rule changed.

Current contradiction classification: **NONE**.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the required order.
- Inspected issue #27, exact latest Development HEAD, open PRs targeting Development, representative Reports source, `ChartPanel`, `ResponsiveCollection`, Product Performance tests, and relevant component/page/migration guidance.
- Confirmed no active implementation PR targeted `design-system-v2-development` before and immediately after scope selection.
- Bounded REPORT011 in `31_AGENT_TEAM_WORKSTREAM.md` in commit `b5e3c3d873de2d7e6db1f76b9ed287b528059418`.
- Updated only the owned `DESIGN_DIRECTOR_STATE.md` among specialist states.
- Did not update `TEAM_MEMORY.md` or `DECISION_LOG.md` because no overall system direction or durable decision changed.
- Did not implement product code, modify peer states, merge a PR, touch `main`, trigger/rerun GitHub Actions, use hosted CI, deploy Vercel or modify preview branches.

### Cross-role handoff
- **To:** UI Production Engineer; then Design QA on the future exact stable PR HEAD.
- **What changed:** REPORT011 is now concretely bounded to the Product Performance revenue chart's page-local analytical shell, using the existing shared `ChartPanel` only.
- **Preserve:** one-page/one-chart scope; exact Arabic title/description, `salesTrust` action presence rule, loading/empty/data branches, 240px body, `chartData`, complete BarChart/axes/tooltip/Bar semantics, REPORT006 responsive detail-collection contracts, and all query/trust/calculation/permission/routing/export/print/business truth.
- **Need from you:** UI Production should start from the exact latest Development HEAD, open one PR targeting `design-system-v2-development`, implement only this concern plus focused tests, and mark `BLOCKED` instead of widening scope if a shared-contract or functional-semantic change is required. Design QA should review the future exact stable PR HEAD independently.
- **Blocker level:** `NONE`.
- **Baseline:** Development `b5e3c3d873de2d7e6db1f76b9ed287b528059418`; integrated product `5d6ee46bc716f6da39367c87e87608f30929c734`.
