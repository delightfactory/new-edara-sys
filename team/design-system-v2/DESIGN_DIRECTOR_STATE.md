# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-19`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD independently inspected before bounding REPORT005: `42c9a11fab10c1570d283159acac7d172f8e2ea3`.
- Workstream scope commit created this run: `19376d74eb6dc431847cc0fbfee6c6b22fda75e2`.
- Latest integrated product slice: `DS2-REPORT-004 — Reports Overview summary metric-grid convergence`, PR #51, squash merge `38b53912c1b3ff8c933ec0d5cfc9d3dc69488f85`.
- Open implementation PRs targeting Development at final pre-state recheck: none.
- Current single READY slice: `DS2-REPORT-005 — Shared ChartPanel foundation + Sales primary revenue-chart migration`.
- No runtime/build/test/lint/preview/release PASS is claimed in this Director run.

## What changed since the previous state

REPORT004 is integrated and the prior Director acceptance state is stale. The broad roadmap placeholder for REPORT005 has now been decomposed into one dependency-safe implementation slice with one representative consumer and explicit system/device/state/accessibility boundaries.

## Independent Product Design judgment

**READY — implementation is now correctly bounded.**

I formed the architectural judgment from current source before comparing peer states. Reports already prove a recurring chart-frame need: Sales, Receivables and Product Performance independently rebuild a neutral card surface, section title/description and trust/freshness/meta area around visualizations. Meanwhile the V2 blueprint explicitly names `ChartPanel` as a missing shared application pattern and the Reports audit target calls for `ChartPanel`, while shared `Card` and `SectionHeader` already provide the correct lower-level surface and hierarchy contracts.

The right next move is therefore not another page-only cosmetic wrapper, not another MetricGrid repetition, and not a broad charts/tables cleanup. The smallest system-advancing proof is to formalize a thin shared, domain-agnostic `ChartPanel` from existing V2 primitives and migrate exactly one real chart: the first Sales chart titled `تطور الإيراد اليومي`.

## System-pattern intent and exact scope

REPORT005 must:

- introduce one shared `ChartPanel` in the patterns layer, composed from existing shared `Card` + `SectionHeader`;
- keep the pattern presentation-only and intentionally small: title, optional description, optional caller-owned action/meta slot, heading level, children and only ordinary neutral passthrough needed by a reusable surface;
- let `ChartPanel` own neutral card/frame treatment, shared spacing/padding, semantic section hierarchy and a `min-width: 0` body containment boundary;
- migrate only `src/pages/reports/SalesPage.tsx` first visualization surface, `تطور الإيراد اليومي`, onto that shared pattern;
- preserve the exact existing Arabic title, description and caller-owned `TrustStateBadge` + `FreshnessIndicator` content;
- preserve the exact blocked/loading/empty/chart decision tree and the existing 240px responsive chart body;
- preserve every chart data/series/axis/gradient/tooltip/color/dimension and every report-domain hook/calculation/trust decision.

`ChartPanel` must not import or understand Recharts, Reports, trust/freshness status, loading/empty/blocked logic, series/data keys or business vocabulary. The page remains the owner of report truth and state orchestration.

## Why this slice is preferable

REPORT004 already proved `MetricGrid`; immediately repeating only metric-wrapper convergence would add less system depth. In contrast, the source shows the same chart framing grammar repeated across multiple report pages, and the blueprint already identifies `ChartPanel` as a formal V2 gap. One shared pattern plus one proof consumer advances the system without prematurely sweeping multiple pages or inventing a report-specific wrapper.

This is also intentionally **not** a table migration. Product Performance's raw table has additional responsive, semantic and status-presentation questions that deserve their own bounded slice rather than being hidden inside REPORT005.

## Device / hierarchy / accessibility acceptance

- **Desktop:** retain full-width analysis density and the current 240px first-chart visualization height; shared framing must not squeeze/reorder chart content.
- **Tablet:** retain a full-width chart with readable touch-first intermediate header/meta composition rather than a compressed Desktop-only header.
- **Mobile:** panel and header/meta must wrap/contain without ordinary viewport-level horizontal overflow; visualization remains inside its existing `ResponsiveContainer`.
- **Arabic / RTL:** exact Arabic copy is preserved; heading/description/action composition must remain RTL-safe and long-copy tolerant.
- **Hierarchy:** the chart title becomes a semantic `h2` through shared `SectionHeader`, correctly nested beneath the page `h1`.
- **Dark mode:** surface/header treatment must come from existing semantic V2 Card/SectionHeader contracts, not new page-local colors.
- **States:** blocked, loading, empty and data-present branches all remain visible and unchanged in meaning; the existing blocked text remains non-color-only.
- **Focus / touch:** no new interactive control is introduced. Existing caller-owned meta content must retain its current behavior; no visual wrapper may consume or fake interaction semantics.

## Explicit exclusions / blocker boundary

REPORT005 must not:

- migrate the second Sales bar chart;
- migrate Receivables, Product Performance or any other report page;
- touch Sales summary MetricCards/`report-grid`, `ReportFilterBar`, `SystemHealthBar` or `CustomTooltip`;
- change Recharts library usage, chart series, data keys, legends, axes, gradients, colors, values, calculations or dimensions;
- create a parallel report-domain `ReportChartCard` abstraction;
- alter queries/cache/services/RPC/DB, permissions/RBAC/RLS, routing, `AnalyticsGate`, export/print or business rules;
- use hosted CI, deploy/preview, touch `main` or modify preview branches.

If implementation discovers that the shared frame cannot be introduced without changing chart truth, trust logic or multiple unrelated report concerns, the slice becomes `BLOCKING` and returns to Product Design rather than expanding scope.

## Expected implementation / evidence

- UI Production Engineer creates one feature branch from the then-current Development HEAD and one PR targeting `design-system-v2-development`.
- Focused tests should cover the shared `ChartPanel` hierarchy/slots/neutral contract and Sales adoption/preservation of the first chart's title/state boundary.
- Tests may be authored without execution under the current policy; evidence must be honestly labeled.
- Design QA independently reviews a stable exact PR HEAD and records `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` only if the source and scope pass.
- Product Design then reviews the same exact stable PR HEAD before integration.

## Peer-state synthesis

After the independent judgment:

- **Integration State / Team Memory:** aligned with REPORT004 being integrated and Product Design needing to bound exactly one REPORT005 concern. This run completes that handoff.
- **UI Production State:** still describes the completed REPORT004 implementation and is stale for the newly bounded slice; no contradiction exists because no REPORT005 implementation PR is open.
- **Design QA State:** still describes REPORT004 exact-head QA and is likewise stale for REPORT005; no contradiction exists yet.
- **Workstream:** now contains the exact executable REPORT005 boundary and is the current slice-level source of truth.
- **Decision Log / North Star:** no durable decision changed. This slice applies existing shared-system-first, caller-owned business truth, Arabic/RTL, device and one-slice rules.

No material cross-role contradiction is currently blocking implementation.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the required order.
- Inspected issue #27, exact Development HEAD and confirmed no open PR targeting Development before and after scope bounding.
- Inspected representative current report surfaces in Overview, Sales, Receivables and Product Performance plus shared `Card`, `SectionHeader`, `MetricGrid`, surface CSS and relevant component/page/module/migration blueprints.
- Updated `31_AGENT_TEAM_WORKSTREAM.md` to replace the broad REPORT005 placeholder with one executable shared-ChartPanel + Sales-first-chart slice.
- Did not implement product code, modify peer specialist states, merge, touch `main`, trigger/rerun GitHub Actions, use hosted CI, deploy Vercel or modify preview branches.
- Did not update Team Memory or Decision Log because overall design direction and durable policy did not change; this is normal slice decomposition/progress.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA and Product Design after a stable PR exists.
- **What changed:** REPORT005 is now `READY` and bounded to a shared domain-agnostic `ChartPanel` foundation plus migration of only SalesPage's first `تطور الإيراد اليومي` chart surface.
- **Preserve:** exact first-chart Arabic title/description; trust/freshness caller ownership; blocked/loading/empty/data branches; 240px responsive chart body; all chart data/series/axis/gradient/tooltip/color semantics; REPORT001–004 contracts; all query/calculation/permission/routing/`AnalyticsGate`/export/print/business truth; no second chart or report page.
- **Need from you:** start one feature branch from the latest Development HEAD, implement only the bounded `ChartPanel` + first Sales chart adoption, author focused shared-pattern/Sales tests, open one PR to `design-system-v2-development`, and stop for exact-head QA/Product Design review.
- **Blocker level:** `NONE`.
- **Baseline:** Development pre-state-write `19376d74eb6dc431847cc0fbfee6c6b22fda75e2`; Product Design source-inspection baseline `42c9a11fab10c1570d283159acac7d172f8e2ea3`.
