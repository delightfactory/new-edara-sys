# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-22`.
- Authoritative branch: `design-system-v2-development`.
- Development HEAD used for independent Product Design selection: `949eaac46142a7510d7791ce1d1cdea32fec6850`.
- Latest integrated product baseline: `DS2-REPORT-028 — Profit Dashboard summary metric-grid convergence` / PR #76 / squash merge `337cf967ab1159968866811be194aec359c43f66`.
- Workstream bounding commit created this run: `d34a415a3bd28dcd0c7676a4a76cb13be2975b52`.
- Active slice: `DS2-REPORT-029 — Geography summary metric-grid convergence`.
- Slice state: `READY — BOUNDED`.
- Active implementation PR: `NONE`.
- Product Design disposition: `AUTHORIZED FOR ONE BOUNDED IMPLEMENTATION SLICE`.
- Current blocker classification: `NONE`.

## Independent Product Design judgment

**READY — BOUNDED. REPORT029 should converge only the two-card Geography summary from the page-local `report-grid` wrapper onto the already-proven shared `MetricGrid columns={2}` contract.**

I formed this judgment independently from the exact latest Development source for `GeographyPage.tsx`, its focused tests, the shared `MetricGrid` contract, the current Reports system direction and the North Star before comparing peer role states.

This is the smallest dependency-safe remaining Reports convergence visible on the current baseline: Geography already uses the shared `Select -> Field` control grammar and the accepted `ResponsiveCollection + Card + KeyValueList` detail grammar, but its two summary KPIs remain on the legacy/local `report-grid` layout wrapper. The shared `MetricGrid` already supports exactly two columns and owns only layout, so no shared API, CSS, token, breakpoint or business-semantic decision is required.

## REPORT029 exact design contract

### In scope

Representative product file:
- `src/pages/reports/GeographyPage.tsx`

Focused evidence file:
- `src/pages/reports/GeographyPage.test.tsx`

The implementation may only:
- import existing `MetricGrid`;
- replace the summary KPI `<div className="report-grid">` wrapper with `<MetricGrid columns={2}>`;
- close with `</MetricGrid>`;
- add focused tests proving the bounded layout convergence and preservation contract.

### Content and state truth that must remain exact

Preserve:
- `isLoading = summaryLoading || tableLoading`;
- two summary loading `SkeletonCard`s at `height={160}`;
- KPI order: `إجمالى الإيراد` then `${LEVEL_LABELS[level]} مغطاة`;
- first metric subtitle `من جميع المناطق الجغرافية`, value `fmtCur(summary?.total_revenue)`, `salesTrust` status/completion/stale wiring, `domain="sales"`, `TrendingUp` icon;
- second metric subtitle `بها مبيعات فى الفترة`, value `summary?.covered_areas`, the same trust/domain wiring, `MapPin` icon;
- `LEVEL_LABELS`, controlled geography level and exact option values/order: `governorate`, `city`, `area`;
- `ReportFilterBar`, System Health, all hook inputs and filter propagation.

### Existing Geography detail contract is excluded and must remain untouched

Do not alter:
- semantic Desktop table and column headers;
- conditional parent column/fallback;
- heatmap row treatment, zero-revenue styling or hover behavior;
- detail Trust/Freshness header;
- Tablet/Mobile `ResponsiveCollection + Card + KeyValueList` renderers;
- Tablet two-column key/value/card composition and Mobile one-column composition;
- long Arabic wrapping/LTR numeric handling already protected by tests;
- five-row detail loading state (`5 × 44px` skeletons);
- exact empty copy `لا توجد بيانات — شغّل watermark sweep أولاً`.

### Device / Arabic / accessibility acceptance

- Desktop: exactly two equal summary columns through the existing shared `MetricGrid` contract; dense detail table remains unchanged.
- Tablet: summary remains two columns through the shared contract; existing touch-safe shared Select and two-column detail cards remain unchanged.
- Mobile: summary collapses to one column with no ordinary horizontal overflow; existing one-column detail cards remain unchanged.
- Arabic/RTL labels and long values remain contained through established shared component contracts; numeric/business truth remains caller-owned.
- No new interactive control is introduced. Existing accessible geography Select/Field and report filter semantics must remain unchanged.

### Focused evidence acceptance

Add source-level tests proving:
- exactly one Geography summary shared MetricGrid exists with `data-columns="2"`;
- the summary uses the exact two-card order above;
- loading produces exactly two summary skeletons at `160px` inside the MetricGrid;
- existing filter/detail tests remain intact and continue guarding the already-accepted Geography contracts.

Evidence must remain honestly labeled `TESTS_AUTHORED_NOT_EXECUTED` unless a separately permitted exact-head execution is actually produced.

## Explicit exclusions / stop conditions

REPORT029 must not:
- modify `MetricGrid`, `MetricCard`, `Select`, `Field`, `ReportFilterBar`, `ResponsiveCollection`, `Card`, `KeyValueList`, shared tokens, CSS or breakpoints;
- redesign/refactor Geography detail surfaces;
- introduce a chart or alter export/print/routing/navigation;
- change analytics hooks, query/cache semantics, calculations, date/filter truth, trust rules, permissions, RBAC/RLS, backend or business behavior;
- touch a second report page;
- expand into the unresolved five-card KPI-grid question on Churn Risk or Customer Reengagement.

If the exact wrapper-only change cannot be completed without any excluded shared/functional change, mark REPORT029 `BLOCKED` and return to Product Design rather than widening the slice.

## System-level rationale

The North Star requires fewer independent implementations of repeated UI concepts, not page-by-page beautification. Geography is a clean representative proof because:
- its metric count already maps to a supported shared `MetricGrid` shape (`2`);
- its filter/control and responsive detail grammar are already on accepted V2 patterns;
- the remaining debt is isolated to layout ownership, not data or domain semantics;
- the change advances the same report metric grammar already proven on Overview, Receivables, Rep Credit Commitment, Sales, Treasury, Customer Health, Product Performance and Profitability;
- it avoids inventing a five-column shared metric contract without evidence and avoids pulling broader Customer Reengagement debt into a small slice.

## Peer-state synthesis / contradictions

After forming the Product Design judgment independently, I compared repository memory and peer states:

- **Team Memory / Workstream:** current through merged REPORT028 and explicitly delegated REPORT029 bounding to Product Design. This run resolves that placeholder into one exact authorized Geography concern.
- **Development Integrator:** lifecycle-current through REPORT028 integration; no active implementation PR and no competing slice exists.
- **UI Production Engineer:** latest REPORT028 implementation position is consumed/stale for the new lifecycle stage, but contains no conflicting design rule. It must bootstrap from the new REPORT029 baseline before implementation.
- **Design QA:** REPORT028 GREEN evidence is consumed by merge and cannot be reused for REPORT029; no conflicting rule or blocker is present.
- **Decision Log / North Star / component and module guidance:** aligned with layout-only shared pattern ownership, caller-owned business truth, deliberate Desktop/Tablet/Mobile composition, Arabic/RTL containment and strict functional isolation.
- **Current open PR search:** no PR targets `design-system-v2-development`, so authorizing REPORT029 does not create a competing implementation slice.

Current contradiction classification: `NONE`.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the prescribed order.
- Inspected issue #27, latest Development HEAD, open PRs targeting Development, current report source/tests and relevant component/module/migration guidance.
- Confirmed REPORT028 is integrated and the prior Product Design state was lifecycle-stale, not contradictory.
- Independently selected and bounded REPORT029 as Geography summary metric-grid convergence.
- Updated `docs/design-system-v2/31_AGENT_TEAM_WORKSTREAM.md` in commit `d34a415a3bd28dcd0c7676a4a76cb13be2975b52` with exact scope, exclusions and device/state/accessibility acceptance.
- Did not modify `TEAM_MEMORY.md` because the overall system direction and durable design rules did not change; this is routine next-slice bounding.
- Did not modify `DECISION_LOG.md` because no long-lived rule changed.
- Did not implement product code, create a competing implementation, merge, touch `main`, deploy Vercel, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer.
- **What changed:** `DS2-REPORT-029 — Geography summary metric-grid convergence` is now `READY — BOUNDED` and authorized as the only implementation slice: replace only the two-KPI Geography summary `report-grid` wrapper with existing `MetricGrid columns={2}` and add focused preservation tests.
- **Preserve:** exact summary loading (`summaryLoading || tableLoading`, 2 × 160px skeletons), KPI order/content/values/trust/domain/icons, geography Select/filter propagation, System Health, and the complete existing Desktop/Tablet/Mobile Geography detail contract including heatmap/table/card/loading/empty behavior; no shared API/CSS/token/breakpoint or backend/business/query/permission change.
- **Need from you:** bootstrap from Development at/after workstream commit `d34a415a3bd28dcd0c7676a4a76cb13be2975b52`, implement only this bounded wrapper convergence plus focused tests, open one PR targeting `design-system-v2-development`, record the exact PR HEAD and `TESTS_AUTHORED_NOT_EXECUTED`, and stop as `BLOCKED` if any excluded shared or functional widening becomes necessary.
- **Blocker level:** `NONE`.
- **Baseline:** Product Design selection formed on Development `949eaac46142a7510d7791ce1d1cdea32fec6850`; bounded workstream commit `d34a415a3bd28dcd0c7676a4a76cb13be2975b52`.