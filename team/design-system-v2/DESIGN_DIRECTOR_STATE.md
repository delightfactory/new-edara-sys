# Product Design Director State

## Reviewed baseline

- Review date/time: `2026-09-23 12:06 Africa/Cairo`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD immediately before this state write: `1ca1a9924e8ca8a27a33d860bc5044c7a9bc1229`.
- Product UI is integrated through `DS2-REPORT-035` / PR #83 squash `8d1aa7e4db89b8dfee7d9ce8c536bb4c160a40fb`.
- Current single READY slice: `DS2-REPORT-036 — Rep Performance shared empty-state convergence`.
- Selection baseline before Product Design Workstream write: `4e266d58f01cd0601534a9c43b52c082e60b3f9b`.
- Workstream bounding commit: `1ca1a9924e8ca8a27a33d860bc5044c7a9bc1229`.
- Representative surface: `src/pages/reports/RepPerformancePage.tsx` → comparison-chart empty branch + responsive detail-collection empty branch only.
- Open implementation PRs targeting Development at selection/recheck: none.
- Current blocker classification: `NONE`.

## Independent Product Design judgment

**REPORT036 is READY — BOUNDED.**

I formed this judgment from the exact latest Development source before comparing peer states. Rep Performance is already structurally aligned with V2 through shared `MetricGrid`, `ChartPanel`, `ResponsiveCollection`, `Card` and `KeyValueList`. The smallest remaining recurring inconsistency is that its chart empty branch and responsive detail empty branch still render page-local empty-state anatomy even though the existing shared `StatePanel` now owns that presentation responsibility and REPORT035 has already proven the pattern safely in the adjacent Product Performance report.

The correct next step is therefore not a page redesign and not a shared-contract expansion. It is a two-renderer presentation convergence onto existing `StatePanel kind="empty"` while preserving all caller-owned state precedence, chart/data truth, responsive ready renderers and business semantics.

## Bounded REPORT036 contract

### Product/system intent

Replace only these two page-local Rep Performance empty renderers:

1. `ChartPanel` body for `مقارنة المندوبين — أعلى 15` when `chartData.length === 0`.
2. `ResponsiveCollection` `emptyState` for `تفصيل الأداء — جميع المندوبين` when `rows` are empty.

Both must consume the existing shared `StatePanel kind="empty"` without modifying the shared component.

Exact visible Arabic copy remains:

`لا توجد بيانات فى النطاق الزمني المحدد`

### Chart acceptance

- Preserve exact precedence: `tableLoading -> SkeletonCard height={300} -> empty -> ready BarChart`.
- Empty presentation uses compact shared `StatePanel` inside a neutral geometry-only wrapper preserving the exact `300px` analytical-body footprint.
- Preserve ready chart top-15 mapping/order and dynamic height `Math.max(chartData.length * 40, 200)`.
- Preserve vertical layout, margins, Cartesian grid, axes, tooltip, revenue and returns series, existing colors/radii/maxBarSize, title/description and Trust/Freshness action behavior.
- No chart calculation, data mapping or visualization semantics move into the Design System.

### Detail acceptance

- Preserve exact precedence: `tableLoading -> five SkeletonCard height={44} rows -> empty -> ready device renderer`.
- Empty presentation becomes one passive shared `StatePanel` inside the existing `ResponsiveCollection` for Desktop, Tablet and Mobile.
- No Desktop table or Tablet/Mobile ready-card renderer mounts while empty.
- Preserve dense seven-column Desktop table and existing Tablet/Mobile `Card + KeyValueList` detail composition, row order, ranking, revenue/returns/customer facts, branch context, return-rate thresholds, Arabic wrapping and LTR numeric treatment.

### Device / accessibility acceptance

- Desktop, Tablet and Mobile share the same passive detail empty anatomy.
- Chart empty/loading footprint remains exactly 300px, avoiding analytical-panel rhythm shift.
- No ordinary horizontal overflow source is introduced.
- Empty states remain non-interactive: no action slot, click handler, focus target, alert role or live announcement.
- Shared `StatePanel` semantics remain unchanged; no new color-only meaning.

### Focused test expectation

Update/extend `src/pages/reports/RepPerformancePage.test.tsx` so it protects:
- one 300px chart loading skeleton before empty evaluation;
- chart empty `.ds-state-panel[data-state-kind="empty"]`, compact density, exact Arabic copy, 300px parent footprint and no action;
- unchanged ready chart contract;
- exactly five 44px detail loading skeletons with neither empty nor ready renderer mounted;
- one passive shared StatePanel on Mobile/Tablet/Desktop when detail data are empty;
- unchanged existing ready renderer/device/data coverage.

Evidence must remain `TESTS_AUTHORED_NOT_EXECUTED` unless an approved runtime actually executes it.

## Explicit exclusions / stop rule

Do not modify:
- page header, `ReportFilterBar`, System Health or summary `MetricGrid` / report `MetricCard` contract;
- chart data/calculations/order/geometry/series/Trust/Freshness beyond replacing the empty renderer;
- detail ready table/card semantics, facts, thresholds or interactions;
- hooks, queries/cache, calculations, permissions/RBAC/RLS, routing, export/print, backend/business/workflow semantics;
- any other report page;
- `StatePanel`, `ResponsiveCollection`, `ChartPanel`, shared CSS, tokens, breakpoints or other shared APIs.

If implementation requires any excluded shared-contract or functional/business change, REPORT036 becomes `BLOCKED` rather than widening the PR.

## System-coherence rationale

This slice advances the North Star because it removes another local state mini-system while reusing a shared pattern already proven in a materially equivalent analytics context. `StatePanel` owns only shared state presentation/anatomy; loading decisions, empty-state precedence, chart truth, collection truth and business meaning remain caller-owned.

The adjacent Product Performance implementation is the correct structural precedent: compact shared state inside a geometry-only fixed-height analytical wrapper, and a single shared passive detail empty renderer inside `ResponsiveCollection`. Rep Performance differs only in its preserved 300px chart loading footprint and exact Arabic copy, both of which remain page-owned.

No reason exists to create a new state component, add a report-specific variant or widen shared CSS/API contracts.

## Peer-state synthesis / contradiction handling

After forming the independent Product Design judgment:

- **Team Memory:** current through REPORT035 and explicitly hands REPORT036 to Product Design for one smallest bounded presentation concern. Its generic REPORT036 placeholder is now lifecycle-stale only because this run has bounded it; durable invariants remain aligned.
- **UI Production Engineer:** lifecycle-current through REPORT035 only; no competing implementation or blocker exists. It must start REPORT036 only from the latest Development HEAD after this Design Director state write.
- **Design QA:** lifecycle-current through REPORT035 only; no REPORT036 disposition exists and fresh exact-head review will be required after implementation.
- **Development Integrator:** current through REPORT035 and explicitly handed REPORT036 to Product Design for bounding; aligned.
- **Decision Log / North Star / Component Decision Matrix / Device Strategy:** aligned with shared state-family consolidation, shared-system-before-local-invention, Arabic-first responsive composition and strict presentation-only ownership.
- **Open PRs targeting Development:** none at selection/recheck, so no competing slice exists.

Current contradiction classification: `NONE`.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the prescribed order.
- Inspected issue #27, exact latest Development HEAD and all open PRs targeting Development.
- Inspected current Rep Performance source and focused tests, existing Product Performance REPORT035 implementation, shared `StatePanel`, `Card`, `SectionHeader`, component decision matrix and device strategy.
- Independently selected Rep Performance's two local empty renderers as the smallest dependency-safe REPORT036 concern.
- Updated `31_AGENT_TEAM_WORKSTREAM.md` to `DS2-REPORT-036 — Rep Performance shared empty-state convergence`, `READY — BOUNDED`, with scope, exclusions, device/state/accessibility acceptance, focused-test expectations and stop rule.
- Did not modify product code, peer role states, Team Memory or Decision Log.
- Did not merge, deploy, touch `main`, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA after a stable implementation PR exists.
- **What changed:** REPORT036 is now bounded to Rep Performance's comparison-chart empty branch plus responsive detail empty branch, both converging onto existing shared `StatePanel kind="empty"` only.
- **Preserve:** exact Arabic copy `لا توجد بيانات فى النطاق الزمني المحدد`; 300px chart loading/empty footprint; exact chart `loading -> empty -> ready` precedence and ready visualization contract; five 44px detail loading rows; one passive detail empty renderer across devices; unchanged Desktop/Tablet/Mobile ready composition; all query/calculation/trust/permission/export/print/backend/business semantics; unchanged shared APIs/CSS/tokens/breakpoints.
- **Need from you:** UI Production should start from the latest Development HEAD, implement REPORT036 only, add/update focused tests, and open exactly one PR targeting `design-system-v2-development`. Any required excluded/shared/functional widening must be reported as `BLOCKED`, not absorbed. Design QA must independently review the future exact stable PR HEAD.
- **Blocker level:** `NONE`.
- **Baseline:** Product Design selection baseline `4e266d58f01cd0601534a9c43b52c082e60b3f9b`; Workstream-bounded Development HEAD before this state write `1ca1a9924e8ca8a27a33d860bc5044c7a9bc1229`.
