# Product Design Director State

## Reviewed baseline

- Review date/time: `2026-09-23 21:04 Africa/Cairo`.
- Authoritative branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-040`.
- Latest product integration: PR #88, squash merge `23707a5465549613dfbde0a6637acee5fbc847e2`.
- Exact Development HEAD before the REPORT041 Workstream boundary write: `7387e5ce050abd6cdb1d8ca68ee032fb50da3ab4`.
- Workstream boundary commit created this run: `fcb74efd439a3e8d489cbd93d4acb6d99329b5ca`.
- Active/READY slice: `DS2-REPORT-041 — Sales revenue-chart empty-state convergence`.
- Active implementation PR: none; open PRs targeting `design-system-v2-development`: `0` at review time.
- Current contradiction classification: `NONE`.

## Independent Product Design judgment

**REPORT041 is `READY — BOUNDED` as one presentation-only Sales analytics concern.**

I formed this judgment from the exact current Development source and shared component contracts before comparing peer role states. The smallest dependency-safe remaining Reports concern is the page-local empty renderer inside the Sales `ChartPanel` titled `تطور الإيراد اليومي`.

That panel already has the correct caller-owned state machine and analytical contract: `isBlocked -> dailyLoading -> empty -> ready`, a fixed 240px chart body, Trust/Freshness context, and an established ready `AreaChart`. Only the empty branch still recreates state presentation locally instead of consuming the shared `StatePanel` grammar. The current shared `StatePanel` already supports a passive compact empty state without carrying business logic, and Receivables proves the same fixed-height chart-body composition safely on Development.

This is preferable to broader debt inspected during this run. Reports Overview still contains a larger local interactive navigation-card mini-system and literal accent colors; Customer Re-engagement contains a much broader legacy FilterBar/export-drawer/status mini-system intertwined with permissions/output behavior. Those are real future system debts, but widening REPORT041 into either would violate the one-smallest-concern rule and raise interaction/functional risk.

## REPORT041 bounded design contract

Representative surface:
- `src/pages/reports/SalesPage.tsx`
- first `ChartPanel`: `تطور الإيراد اليومي`
- empty branch only.

Required convergence:
- replace only the page-local 240px empty block with existing shared `StatePanel kind="empty"` using `compact` presentation;
- preserve exact visible copy: `لا توجد بيانات في النطاق الزمني المحدد`;
- preserve a 240px chart-body footprint around the shared state;
- preserve passive semantics: no action slot, click handler, button/link, explicit focus target or live announcement.

Preserve exactly:
- precedence `isBlocked -> dailyLoading -> empty -> ready`;
- current BLOCKED renderer, copy and trust meaning;
- `SkeletonCard height={240}` loading state;
- `ChartPanel` title, description, TrustStateBadge and FreshnessIndicator placement;
- ready `ResponsiveContainer + AreaChart` data mapping, margin, axes/grid/tooltip, revenue/returns series, gradients, colors and geometry;
- report filter/range behavior, KPI MetricGrid/MetricCard composition, SystemHealthBar and formatting;
- all query/cache/aggregation/calculation/trust/permission/RBAC/RLS/routing/export/print/backend/business semantics.

Explicitly excluded:
- the second chart `توزيع الإيرادات اليومي (إيراد + ضريبة)`, including its current no-data behavior;
- chart tooltip/color/token refactors;
- any shared `StatePanel` / `ChartPanel` API, CSS, token or breakpoint widening;
- Overview navigation-card debt, Customer Re-engagement debt, Settings/Admin and Global cleanup.

## Device / RTL / accessibility acceptance

The shared empty state must preserve the same 240px analytical footprint at representative Mobile/Tablet/Desktop widths (390/900/1440px), remain visually centered and compact, allow Arabic copy to wrap naturally, introduce no normal horizontal overflow, and preserve the same business meaning across devices.

Because the state is passive, there must be no new touch target, keyboard target or focus order. `kind="empty"` must retain the shared contract's non-live behavior. The change must remain readable in RTL and not rely on color to communicate the empty condition.

## Focused test intent

Update focused `SalesPage.test.tsx` coverage to prove:
- empty data mounts one shared `.ds-state-panel[data-state-kind="empty"]` with compact anatomy and exact Arabic copy inside a 240px body;
- empty does not mount the ready AreaChart renderer;
- loading retains higher priority than empty and stays exactly 240px;
- BLOCKED retains higher priority and exact current copy/meaning;
- ready chart behavior remains unchanged when data exists;
- representative 390/900/1440px source-level acceptance has no semantic/device divergence or new overflow/focus target.

Evidence must remain honest: focused tests are to be authored, but `TESTS_AUTHORED_NOT_EXECUTED` remains the correct label unless local execution evidence is actually produced. Hosted GitHub Actions remain forbidden.

## Peer-state synthesis / contradiction handling

After the independent judgment:

- **Integration state:** current through REPORT040 and explicitly delegates REPORT041 bounding to Product Design; aligned, not contradictory.
- **Team Memory:** current through REPORT040 and marks REPORT041 as intentionally unbounded pending Product Design; now superseded only for routine current-slice scope by this bounded Workstream state. No overall North-Star direction changed, so Team Memory is not rewritten this run.
- **UI Production state:** lifecycle-stale after REPORT040 merge and contains no competing REPORT041 implementation; no contradiction.
- **Design QA state:** lifecycle-stale after REPORT040 merge and contains no REPORT041 judgment; no contradiction.
- **Decision Log / North Star / Component System / Migration Matrix / QA Guardrails / Device Strategy / Component Decision Matrix:** aligned with consolidating state presentation through the existing shared component while keeping state truth/business semantics caller-owned.
- **Open implementation PRs:** none targeting Development at the final pre-write check, so no competing slice exists.

Current contradiction classification: `NONE`.

## What changed since the previous state

- REPORT040 is now integrated; the prior exact-head PR acceptance state is no longer the active lifecycle state.
- Inspected the exact post-REPORT040 Development baseline, issue #27, open PRs, relevant Reports source/tests and shared contracts.
- Independently selected and bounded REPORT041 to the Sales first-chart empty branch only.
- Updated `31_AGENT_TEAM_WORKSTREAM.md` at commit `fcb74efd439a3e8d489cbd93d4acb6d99329b5ca`.
- Did not change product code, peer role states, Team Memory or Decision Log.
- Did not merge, touch `main`, deploy Vercel, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer.
- **What changed:** `DS2-REPORT-041 — Sales revenue-chart empty-state convergence` is now the single `READY — BOUNDED` slice; only the first Sales chart empty renderer is authorized.
- **Preserve:** exact copy `لا توجد بيانات في النطاق الزمني المحدد`; `isBlocked -> dailyLoading -> empty -> ready`; unchanged BLOCKED and 240px loading contracts; unchanged first-chart ready data/geometry/Trust/Freshness; second chart entirely untouched; passive compact shared empty semantics; all data/query/permission/export/backend/business behavior.
- **Need from you:** start from the latest Development HEAD, implement REPORT041 only, author focused Sales tests for blocked/loading/empty/ready plus representative device acceptance, and open one Draft PR targeting `design-system-v2-development`. If any shared-contract or functional widening is required, stop and mark the slice `BLOCKED`.
- **Blocker level:** `NONE`.
- **Baseline:** pre-boundary Development `7387e5ce050abd6cdb1d8ca68ee032fb50da3ab4`; Workstream boundary commit `fcb74efd439a3e8d489cbd93d4acb6d99329b5ca`.