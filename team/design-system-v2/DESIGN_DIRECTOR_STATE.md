# Product Design Director State

## Reviewed baseline

- Review date/time: `2026-09-23 10:00 Africa/Cairo`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD at selection start: `8b6353d187a490c16b56d209554f9ff51683380f`.
- Exact Development HEAD immediately before this state write: `4cd736fd13568b0129a7330a4407946c0b79c33a` (REPORT035 Workstream bounding only).
- Product UI is integrated through `DS2-REPORT-034` / PR #82 squash `7ba36015798df5d4aa615077adade862687a6f9c`.
- Open implementation PRs targeting Development at selection time: `NONE`.
- Active slice: `DS2-REPORT-035 — Product Performance shared empty-state convergence`.
- Slice status: `READY — BOUNDED`.
- Representative surface: `src/pages/reports/ProductPerformancePage.tsx` only.
- Current blocker classification: `NONE`.

## Independent Product Design judgment

**READY — BOUNDED.** The smallest dependency-safe Reports concern that now gives useful system depth is the remaining page-local empty-state anatomy inside Product Performance, not another metric/card restyle.

I formed this judgment from the exact current Development source before comparing peer states. Product Performance is already substantially converged: the KPI summary uses shared `MetricGrid`, the analytical surface uses shared `ChartPanel`, and the product-detail section uses shared `ResponsiveCollection + Card + KeyValueList` with a deliberate Desktop/Tablet/Mobile composition. The remaining inconsistency is that both the chart empty branch and the responsive detail empty branch still render bespoke inline `لا توجد بيانات` blocks instead of the existing shared `StatePanel` state grammar.

This is a stronger next proof than broad page beautification: it exercises the same shared empty-state component in two analytical contexts on one page — a constrained chart body and a device-orchestrated detail collection — while leaving data truth, loading precedence, visualization semantics and responsive renderers entirely caller-owned.

No shared-contract widening is justified. `StatePanel` already owns empty-state presentation, supports compact density, remains passive by default, exposes `data-state-kind`, and has shrink-safe shared styling. The chart may retain a neutral local geometry wrapper solely to preserve the existing 240px analytical-body footprint; state typography/color/anatomy must come from `StatePanel`, not another local mini-system.

## Exact bounded contract

### In scope

Only two empty renderers in `src/pages/reports/ProductPerformancePage.tsx`:

1. `ChartPanel` titled `أعلى 15 منتجاً بالإيراد` when `chartData.length === 0`.
   - Replace the bespoke centered empty `<div>` with existing shared `StatePanel kind="empty"` using compact density.
   - Preserve the exact visible copy: `لا توجد بيانات`.
   - Preserve the exact 240px chart empty-state footprint.

2. `ResponsiveCollection.emptyState` under `تفاصيل المنتجات — أعلى 50 حسب الإيراد`.
   - Replace the bespoke inline empty block with existing shared `StatePanel kind="empty"`.
   - Preserve the exact visible copy: `لا توجد بيانات`.
   - Keep it as the single empty renderer for Desktop, Tablet and Mobile; no table/card renderer may mount when rows are empty.

### State preservation

Preserve exact precedence:
- chart: `tableLoading -> SkeletonCard height={240} -> empty -> ready BarChart`;
- detail: `tableLoading -> five SkeletonCard height={44} rows -> empty -> ready device renderer`.

Ready-state chart data/order, 240px `ResponsiveContainer`, BarChart geometry, axes, tooltip, grid, revenue series, color and margins are unchanged.

Ready-state detail ordering, Desktop seven-column semantic table, Tablet two-column cards, Mobile one-column cards, all seven facts/fallbacks, return-rate thresholds, Arabic wrapping and LTR numeric presentation are unchanged.

### Device / accessibility acceptance

- Desktop/Tablet/Mobile receive the same shared empty-state anatomy and exact Arabic copy.
- No new ordinary horizontal overflow, fixed-width control or duplicate mounted interaction tree.
- Empty state remains passive: no click handler, focus target, action, alert role or live announcement.
- Existing `StatePanel` semantic section and `data-state-kind="empty"` are sufficient; no shared API/CSS change.
- Chart geometry remains stable at 240px in the empty branch so surrounding analytical rhythm does not jump.

### Explicit exclusions

Do not modify:
- page header, category native `<select>`, `ReportFilterBar`, System Health;
- KPI `MetricGrid` / MetricCards;
- TrustStateBadge / FreshnessIndicator;
- chart data mapping, BarChart/axes/grid/tooltip/series/colors/margins or ready-state geometry;
- product-detail table/card facts, row order, return-rate thresholds or responsive breakpoints;
- category Supabase RPC, hooks, query/cache/calculation semantics, permissions/RBAC/RLS, routing, export/print, backend or business behavior;
- shared `StatePanel`, `ResponsiveCollection`, `ChartPanel`, Card/KeyValueList implementations/APIs, global CSS, tokens or breakpoints;
- every other report page.

### Test artifact expectations

Focused source tests must prove:
- chart empty branch consumes `.ds-state-panel[data-state-kind="empty"]`, preserves exact `لا توجد بيانات`, compact density and the 240px analytical-body footprint;
- detail `ResponsiveCollection` empty branch consumes `.ds-state-panel[data-state-kind="empty"]`, preserves the same copy, and mounts neither table nor responsive cards on Mobile/Tablet/Desktop;
- chart loading still renders exactly one 240px SkeletonCard before empty-state evaluation;
- detail loading still renders exactly five 44px SkeletonCards and no empty/ready renderer;
- ready chart and device-specific detail renderers remain unchanged.

Evidence must remain honestly labeled `TESTS_AUTHORED_NOT_EXECUTED` unless an approved exact-head runtime is actually executed. Hosted CI remains forbidden.

## Peer-state synthesis / contradiction handling

After forming the independent Product Design judgment:

- **Development Integrator:** current through REPORT034, explicitly hands REPORT035 to Product Design for one smallest bounded concern; aligned.
- **Team Memory:** current through REPORT034 and still describes REPORT035 as an unbounded placeholder; lifecycle-stale after this Product Design bounding, but its durable direction/invariants are fully aligned. No need for a Team Memory write because overall system direction did not change.
- **UI Production Engineer:** lifecycle-stale from REPORT034; no active competing PR or REPORT035 implementation exists.
- **Design QA:** lifecycle-stale from REPORT034; no REPORT035 approval is expected before implementation.
- **Decision Log / North Star / component matrix / device strategy:** aligned with shared-system-before-local-invention, state-family consolidation, Arabic-first multi-device composition and strict presentation-only ownership.

Current contradiction classification: `NONE`.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the prescribed order.
- Inspected issue #27, exact Development HEAD, open PRs targeting Development, relevant component/device/page-pattern/migration documents and representative remaining report source.
- Confirmed no implementation PR was active before selection.
- Independently inspected Product Performance source/tests plus existing shared `StatePanel` contract and CSS.
- Bounded REPORT035 in `31_AGENT_TEAM_WORKSTREAM.md` at commit `4cd736fd13568b0129a7330a4407946c0b79c33a`.
- Did not modify product code, peer role states, Team Memory or Decision Log.
- Did not merge, deploy, touch `main`, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer.
- **What changed:** REPORT035 is now `READY — BOUNDED` as Product Performance shared empty-state convergence only: the chart empty branch and responsive-detail empty branch must consume existing `StatePanel kind="empty"` while preserving copy, state precedence and all ready/loading behavior.
- **Preserve:** exact `لا توجد بيانات` copy; chart 240px empty/loading geometry; five 44px detail loading skeletons; current BarChart/data/trust semantics; Desktop/Tablet/Mobile detail renderer isolation and all seven product facts; all shared APIs/CSS/tokens and all query/calculation/permission/backend/business semantics.
- **Need from you:** start from the latest `design-system-v2-development` HEAD, implement only this two-context empty-state concern with focused tests, update only your owned state, and open exactly one Draft PR targeting Development. If any shared-contract or functional widening proves necessary, mark REPORT035 `BLOCKED` instead.
- **Blocker level:** `NONE`.
- **Baseline:** selection baseline `8b6353d187a490c16b56d209554f9ff51683380f`; Workstream-bounded Development HEAD immediately before this state write `4cd736fd13568b0129a7330a4407946c0b79c33a`.
