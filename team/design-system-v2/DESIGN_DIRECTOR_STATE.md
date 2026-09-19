# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-19`.
- Authoritative branch: `design-system-v2-development`.
- Exact product/coordination HEAD independently inspected before bounding: `4cb9a7b1132606498de6c9170735f681556a93a2`.
- Workstream boundary commit created this run: `371ab7c50e194bc0a03930c827cead023e9de043`.
- Product UI is integrated through `DS2-REPORT-007` / PR #54 / squash merge `9ab20b3ca467b1d42eae0fb9fd6936d156e11662`.
- Open implementation PRs targeting Development at selection time: none.
- Current single implementation-authorized slice: `DS2-REPORT-008 — Receivables AR chart-panel convergence`.
- Representative surface: `src/pages/reports/ReceivablesPage.tsx` → chart section `تحصيلات AR مجمّعة بتاريخ البيع الأصلي` only.
- Current Product Design disposition: `READY — BOUNDED / NO DESIGN-SYSTEM BLOCKER TO IMPLEMENTATION`.
- Runtime/build/test/lint/preview/release PASS: not claimed.

## What changed since the previous state

REPORT007 is now integrated and the pipeline had no active implementation PR. I independently inspected the exact latest Development baseline, remaining Reports surfaces, the proven shared `ChartPanel` contract and current role/team memory. The generic REPORT008 placeholder is now decomposed into one dependency-safe concern: migrate only the Receivables AR chart shell from a page-local card/header composition onto the existing shared `ChartPanel`.

This is deliberately a cross-page reuse step rather than another new abstraction. REPORT005 already proved `ChartPanel` on Sales; Receivables presents the same recurring analytical framing need with title, description, trust/freshness action cluster and caller-owned blocked/loading/empty/data branches. Reusing the existing pattern here strengthens system coherence without absorbing AR or chart semantics into the Design System.

## Independent Product Design judgment

**READY — implementation may proceed for REPORT008 exactly as bounded.**

The current Receivables chart shell duplicates surface, border, radius, padding, shadow and section-header composition locally. Existing shared `ChartPanel` already owns exactly that neutral analytical presentation through `Card + SectionHeader`, defaults to semantic `h2`, and intentionally leaves chart data/state/business meaning with the caller.

No new primitive, chart abstraction or shared API expansion is justified. The smallest useful move is to replace only this one local shell and preserve all report truth literally.

## REPORT008 acceptance boundary

### System fit / visual grammar

- Use existing `ChartPanel` for the section currently titled `تحصيلات AR مجمّعة بتاريخ البيع الأصلي`.
- Feed the exact existing title and description into `ChartPanel`.
- Feed the existing `TrustStateBadge + FreshnessIndicator` cluster into the `action` slot.
- Keep the default `headingLevel={2}` so the page hierarchy becomes structurally `h1 -> h2` without inventing nested heading levels.
- No `ChartPanel` API/CSS redesign is expected or authorized.

### Functional isolation

Preserve exactly:
- `range`, `filters`, `useARDailyTotals`, `useARSummary` and `useSystemTrustState` wiring;
- `arTrust`, `isBlocked` and every trust/freshness source;
- `chartData` mapping of `sale_date`, `receipt_amount`, `refund_amount`, `net_cohort`;
- blocked/loading/empty/data branch conditions and exact user-facing copy;
- `ResponsiveContainer` height `260`;
- `BarChart` margin, grid, axes, tooltip, formatters and all three series names/colors/radii/maxBarSize;
- all metrics, calculations, hooks, query/cache/service/RPC/DB truth, permissions, routing, `AnalyticsGate`, export/print and business semantics.

### Device / Arabic / accessibility acceptance

- **Desktop:** preserve the current dense analytical rhythm; shared Card/SectionHeader spacing must not inflate the chart into a decorative oversized surface.
- **Tablet:** title/description and trust/freshness action cluster must remain wrap-capable and touch-readable; no compressed accidental header row.
- **Mobile:** no ordinary page-level horizontal overflow may be introduced; chart containment and section header/action composition must remain readable under the shared pattern.
- **Arabic / RTL:** exact Arabic copy remains unchanged; long Arabic title/description wrapping must stay coherent and action metadata must not collide with text.
- **Dark mode:** surface/border/text presentation should come from existing shared semantic tokens through `ChartPanel` rather than local card styling.
- **Accessibility:** the shared `SectionHeader` semantic `h2` path is required; existing trust/freshness content semantics remain unchanged.

### State / test acceptance

- Preserve blocked copy `بيانات AR محجوبة` + `يحتاج إلى اكتمال تشغيل محرك AR أولاً`.
- Preserve empty copy `لا توجد بيانات تحصيل في هذه الفترة`.
- Preserve loading `SkeletonCard height={260}` and successful chart body height `260`.
- Author focused tests for shared `ChartPanel` adoption, exact title/description/action presence, preserved state copy and unchanged 260px chart contract. Tests may remain `TESTS_AUTHORED_NOT_EXECUTED` under current policy; do not claim execution that did not occur.

## Explicit exclusions

REPORT008 must not change:
- the three Receivables `MetricCard`s or their `report-grid` wrapper;
- page header, `ReportFilterBar`, `SystemHealthBar` or `CustomTooltip`;
- a second Receivables surface, Sales second chart, Rep Performance, Product Performance or any other report;
- chart legend/series design, Recharts abstraction, new responsive chart behavior or new visual semantics;
- shared `ChartPanel` API/CSS unless a real incompatibility blocks the exact consumer;
- backend/query/cache/service/RPC/DB/calculation/trust-status/permission/routing/export/print/business behavior.

If the existing `ChartPanel` contract proves materially insufficient, or implementation requires any functional semantic change, REPORT008 becomes `BLOCKED` and returns to Product Design instead of widening the PR.

## Peer-state synthesis

This judgment was formed from current source and shared contracts first, then compared with peer states.

- **Team Memory:** current and aligned at program level; it explicitly hands REPORT008 to Product Design for one bounded concern. Its placeholder wording is now superseded only by this newly recorded boundary.
- **UI Production Engineer:** lifecycle-stale at REPORT007 implementation; no active conflicting PR or scope exists.
- **Design QA:** lifecycle-stale at REPORT007 approval; no current REPORT008 judgment exists yet, as expected before implementation.
- **Development Integrator:** current and aligned; REPORT007 is merged and it explicitly requires Product Design to bound REPORT008 before implementation.
- **Decision Log / North Star / Component Decision Matrix:** aligned. The selected slice applies the existing shared-system-first, UI-only isolation and analytical presentation ownership rules; it creates no new durable decision.

Current contradiction classification: **NONE**.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the required order.
- Inspected issue #27, exact Development HEAD, open PRs targeting Development, representative remaining Reports surfaces, `ChartPanel`, Sales' proven consumer and relevant Component System / Page Pattern / Migration Matrix / Source Audit / Component Decision Matrix documents.
- Updated `31_AGENT_TEAM_WORKSTREAM.md` to make REPORT008 implementation-ready with a precise representative surface, exclusions and device/state/accessibility acceptance.
- Did not update `TEAM_MEMORY.md` or `DECISION_LOG.md` because no overall system direction or durable rule changed.
- Did not implement product code, modify peer specialist states, merge a PR, touch `main`, trigger/rerun GitHub Actions, use hosted CI, deploy Vercel or modify preview branches.

### Cross-role handoff
- **To:** UI Production Engineer, then Design QA after an exact stable PR HEAD exists.
- **What changed:** REPORT008 is now fully bounded as the one-chart Receivables AR `ChartPanel` convergence in `src/pages/reports/ReceivablesPage.tsx`; implementation is authorized.
- **Preserve:** exact title/description; trust/freshness action cluster and value sources; blocked/loading/empty/data branches and copy; 260px body; chartData/Recharts/tooltip/series/axes/colors/formatters; all metric/filter/query/calculation/trust/permission/routing/export/print/business truth; existing `ChartPanel` presentation-only ownership boundary; no Actions/Vercel/preview/`main` activity.
- **Need from you:** UI Production Engineer should branch from the exact latest `design-system-v2-development` HEAD and open exactly one REPORT008 PR for this chart shell with focused tests. If `ChartPanel` requires material API/CSS widening or business semantics would move, stop and mark BLOCKED. Design QA should independently review only the future exact stable PR HEAD.
- **Blocker level:** `NONE`.
- **Baseline:** product/source baseline `4cb9a7b1132606498de6c9170735f681556a93a2`; workstream boundary commit `371ab7c50e194bc0a03930c827cead023e9de043`.
