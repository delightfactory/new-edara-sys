# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-22`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD independently inspected before REPORT028 bounding: `844a20128ff1c2b11b85a93f3416ac1957e76daa`.
- Development HEAD immediately before this owned-state write: `9bb61b5e9a8f09362a36d1e27674e01f4cd260c3`.
- Latest integrated product baseline: `DS2-REPORT-027 — Churn Risk filter-control field convergence` / PR #75 / squash merge `d9a1fb373142cac8c9f7f1b7545d340f99298f8a`.
- Active slice: `DS2-REPORT-028 — Profit Dashboard summary metric-grid convergence`.
- Active implementation PR: none at selection/bounding time.
- Product Design disposition: `READY — BOUNDED`.
- Current blocker classification: `NONE`.

## Independent Product Design judgment

**READY — REPORT028 should converge only the four-card profitability summary grid onto the existing shared `MetricGrid columns={4}` contract.**

I formed this judgment from the exact latest Development source for the remaining Reports/Analytics surfaces, the existing `MetricGrid` implementation and responsive CSS, the Reports page grammar and device strategy, before comparing peer role states.

`src/pages/reports/profitability/ProfitDashboard.tsx` contains a small, isolated system-coherence gap: four existing report-domain `MetricCard`s are still arranged by the legacy/local `report-grid` wrapper even though the shared V2 `MetricGrid` already owns exactly that layout responsibility and is proven across several report summaries. This is a cleaner next move than widening five-card Churn/Reengagement layouts, touching Customer Reengagement's large export/mobile-card surface, or entering Rep Credit Commitment's broad drawer/filter/table composition.

The slice is therefore intentionally wrapper-only. Profitability calculations, trust/freshness, loading copy, date/filter/query truth and the separate final-net-profit highlight remain caller-owned.

## Bounded system contract

Representative surface:
- `src/pages/reports/profitability/ProfitDashboard.tsx` → only the four KPI `MetricCard` summary cluster currently inside `report-grid`.

Required implementation intent:
- replace only the summary wrapper with existing `MetricGrid columns={4}`;
- do not change `MetricGrid`, `MetricCard`, shared CSS, tokens or breakpoints;
- preserve exact KPI order: `صافي الإيراد بعد المرتجعات` → `المبيعات (تكلفة البضاعة)` → `إجمالي الربح (التشغيلي)` → `المصروفات التشغيلية والرواتب`;
- preserve all existing values and calculations: `net_revenue`, `cogs`, `gross_profit`, operating+payroll expense sum and gross-margin secondary value;
- preserve `overviewTrust` status / completion / stale wiring, `domain="profit_overview"`, all icons and `PackageIcon`;
- preserve current loading presentation exactly as `isLoading ? '...'`; no new skeleton or state behavior in this slice.

Device / content acceptance:
- Desktop: four equal minmax-safe columns;
- Tablet: two columns;
- Mobile: one column with no normal horizontal overflow;
- Arabic/RTL labels must wrap safely, mixed Arabic/Latin values must remain legible and large numbers must remain contained;
- no interaction or focus semantics are added by the grid; existing component accessibility remains authoritative.

Focused evidence expected:
- assert the shared metric grid is present with `data-columns="4"`;
- protect exact KPI order/content plus the existing loading/trust/secondary-value wiring;
- evidence is `TESTS_AUTHORED_NOT_EXECUTED` unless an approved execution environment actually runs the tests.

## Explicit exclusions / stop rule

REPORT028 must not modify:
- the separate `report-grid-2` / `صافي الربح النهائي` highlight card or its net-profit-margin presentation;
- title/header composition, `ReportFilterBar`, date state, `branchId`, query inputs/hooks, trust hooks or calculations;
- any second profitability/report page, chart, table, drawer, export/print surface or five-card KPI layout;
- shared APIs/CSS/tokens/breakpoints;
- DB/RPC/services/query/cache/RBAC/RLS/permissions/routing/validation/workflow/backend/business semantics;
- deployment, preview branches, hosted CI or `main`.

If the wrapper-only convergence cannot be implemented without any excluded shared or functional change, REPORT028 becomes `BLOCKED` rather than expanding scope.

## Peer-state synthesis / contradictions

I formed the Product Design judgment above independently, then compared current repository state:

- **Development Integrator / Team Memory:** lifecycle-current through merged REPORT027 and explicitly hand REPORT028 to Product Design for one smallest bounded concern; aligned.
- **UI Production Engineer:** lifecycle-stale at the completed REPORT027 implementation stage; no competing implementation or contradictory requirement exists.
- **Design QA:** lifecycle-stale at REPORT027 exact-head approval; no REPORT028 approval/blocker exists yet, as expected.
- **Decision Log / North Star / component/device guidance:** aligned with shared-system-before-local-invention, caller-owned business truth, Arabic-first multi-device composition and strict functional isolation.
- **Open Development PRs at selection time:** none.

Current contradiction classification: `NONE`.

## What changed this run

- Completed the mandatory shared-memory bootstrap in the required order.
- Inspected issue #27, exact Development HEAD, open PRs targeting Development, remaining Reports/Analytics surfaces, profitability surfaces, shared `MetricGrid` implementation/responsive CSS and relevant component/page/device/migration guidance.
- Concretely bounded the generic REPORT028 roadmap placeholder as `DS2-REPORT-028 — Profit Dashboard summary metric-grid convergence`.
- Updated `31_AGENT_TEAM_WORKSTREAM.md` with exact scope, exclusions, device/state/accessibility acceptance, focused evidence expectation and stop rule.
- Did not update `TEAM_MEMORY.md` because the overall system direction did not change.
- Did not update `DECISION_LOG.md` because no durable rule changed.
- Did not implement product code, merge, touch `main`, deploy Vercel, modify preview branches, or trigger/rerun GitHub Actions/hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA after the implementation PR is stable.
- **What changed:** REPORT028 is now concretely `READY — BOUNDED` as the four-card Profit Dashboard summary wrapper migration from local `report-grid` to existing `MetricGrid columns={4}` only.
- **Preserve:** exact four KPI order/content/calculations/loading/trust/icons/secondary margin wiring; the separate final-net-profit highlight; all date/filter/query/trust/business truth; unchanged shared `MetricGrid`/`MetricCard` APIs/CSS/tokens/breakpoints; every REPORT001-027 contract.
- **Need from you:** UI Production should start from the exact latest Development HEAD, implement only the bounded wrapper convergence, author focused metric-grid/order/state tests and open one Development-targeting PR. If any excluded shared or functional change is required, stop and mark the slice `BLOCKED`. Design QA should independently review the future exact stable PR HEAD.
- **Blocker level:** `NONE`.
- **Baseline:** source inspected at `844a20128ff1c2b11b85a93f3416ac1957e76daa`; REPORT028 workstream-bound baseline before this state write `9bb61b5e9a8f09362a36d1e27674e01f4cd260c3`.