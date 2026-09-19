# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-19`.
- Authoritative branch: `design-system-v2-development`.
- Development HEAD immediately before this Director-state write: `7137169dde7c1ee671cf12d9e58134b6a6cbc73a`.
- Latest integrated product slice: `DS2-REPORT-003 — Report custom-date field convergence`, PR #50, squash merge `cec34dcdc2fec5ac7b3cd4821d942f224f9f52f2`.
- Open implementation PRs targeting Development at bootstrap: none.
- Active READY slice: `DS2-REPORT-004 — Reports Overview summary metric-grid convergence`.
- No runtime/build/test/lint/preview/release PASS is claimed in this Director run.

## Independent Product Design judgment

**READY — REPORT004 is now bounded to one smallest dependency-safe presentation concern: the four-metric summary layout on `Reports Overview`.**

I formed this judgment from the current Development source before comparing peer states. The current report summary already has correct domain-aware metric presentation, but its composition still uses a report-local `report-grid report-grid-12` wrapper. Shared V2 `MetricGrid` already exists and has a proven consumer in Supervisor Work, so the smallest architecture-first next step is to converge only the layout primitive.

The report-domain `MetricCard` is deliberately preserved. It is not equivalent to generic `StatCard`: it owns trust/freshness and blocked/running/reconciled presentation semantics. Replacing it in the same slice would cross a semantic boundary and risk converting a layout migration into a report-state redesign.

## Exact REPORT004 boundary

Implementation is limited to the four Overview summary metrics immediately after `ReportFilterBar` in `src/pages/reports/OverviewPage.tsx`:

- replace only the local `report-grid report-grid-12` wrapper with shared `MetricGrid` using its four-column contract;
- preserve the existing four `MetricCard` children in exact order: `صافي الإيراد`, `هامش الربح`, `رصيد الذمم`, `زيارات اليوم`;
- preserve every existing value, formatter, status, freshness, domain, subtitle, icon and trend input;
- preserve all query/cache/service/hook/calculation/chart/table/risk/export/print/permission/routing/`AnalyticsGate` truth;
- preserve REPORT001 `SubNav`, REPORT002 `SegmentedControl`, REPORT003 `DateField` and all date semantics;
- do not touch Sales or any second report page in this slice;
- do not redesign or replace report `MetricCard`, charts, tables, filters or generic report states.

If this wrapper-only migration proves impossible without changing report truth or `MetricCard` semantics, the slice becomes `BLOCKED` rather than expanding.

## Device / state / accessibility acceptance

- Use the existing shared `MetricGrid` responsive contract with no Reports-only breakpoint/width override.
- Desktop preserves useful four-metric comparison density; Tablet/Mobile remain readable and contained without ordinary viewport-level horizontal overflow.
- Long Arabic labels and large numeric values remain readable without wrapper-induced clipping or false truncation.
- Existing trust/freshness/status text, icons and non-color-only meaning remain intact for complete, warning/reconciled, running and blocked/failed paths.
- RTL, dark-mode token behavior and shared accessibility/focus semantics must not regress.

## Peer-state synthesis

After forming the independent judgment:

- **Development Integrator:** current and aligned; REPORT003 is integrated and it explicitly hands the queue to Product Design to bound one smallest REPORT004 concern.
- **Team Memory / Workstream:** aligned on one-READY-slice discipline and on Reports metrics/charts/tables being the next area, with Product Design responsible for narrowing scope before implementation.
- **UI Production Engineer / Design QA:** their specialist states are lifecycle-stale from REPORT003 but contain no competing active slice or contradiction; this is expected after integration and is non-blocking.
- **Decision Log / North Star:** no durable rule changed. This slice applies existing shared-system-first, caller-owned business truth, responsive/Arabic/RTL and one-slice rules.

There is no material cross-role contradiction and no blocker to implementation of the bounded layout-only slice.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the required order.
- Inspected issue #27, current Development HEAD, open PRs targeting Development, representative Reports source and relevant component/migration blueprints.
- Verified there was no active implementation PR, then narrowed the single broad READY roadmap item instead of creating a competing concern.
- Updated `31_AGENT_TEAM_WORKSTREAM.md` to make REPORT004 implementation-ready with exact scope, exclusions, device/state/accessibility acceptance and system-pattern intent.
- Did not implement product code, modify peer specialist states, merge, touch `main`, trigger/rerun GitHub Actions, use hosted CI, deploy Vercel or modify preview branches.
- Did not update Team Memory or Decision Log because overall system direction and durable policy did not change.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA and Product Design after a stable implementation PR HEAD exists.
- **What changed:** `DS2-REPORT-004` is now an exact READY slice limited to replacing the Reports Overview four-metric summary layout wrapper with shared `MetricGrid` while retaining the existing domain `MetricCard` children and semantics.
- **Preserve:** exact four metric order/labels/values/formatters/status/freshness/domain/icons; report-domain `MetricCard` trust semantics; all queries/calculations/charts/tables/risk/filter/date/permission/routing/`AnalyticsGate`/export/print truth; no Sales or second-page migration.
- **Need from you:** open one implementation PR from the latest `design-system-v2-development` HEAD and perform only the wrapper convergence with focused source/test evidence; do not substitute `StatCard` or widen into charts/tables/other report pages.
- **Blocker level:** `NONE`.