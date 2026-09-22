# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-22`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development product/coordination baseline independently inspected before bounding the next slice: `0fc85407e7ca107493a84bd808020af76e846778`.
- Latest integrated product baseline: `DS2-REPORT-024 — Treasury summary metric-grid convergence` / PR #72 / squash merge `b77349f15039bea5aa92cb8dda3734c61882f583`.
- Workstream boundary commit immediately before this owned-state write: `448c324cbaa1ddeaa821c390c13e185270553d59`.
- Active slice: `DS2-REPORT-025 — Customer Health summary metric-grid convergence`.
- Slice status: `READY — BOUNDED`.
- Active implementation PR: none at selection time.
- Representative surface: `src/pages/reports/CustomerHealthPage.tsx` → three-card customer-health KPI summary only.
- Evidence expectation: `TESTS_AUTHORED_NOT_EXECUTED` unless approved exact-head execution actually occurs.

## Independent Product Design judgment

**REPORT025 is dependency-safe and implementation-authorized as one narrow presentation-only convergence slice.**

I formed the design judgment from the exact current Customer Health source/test surface and current shared `MetricGrid`/`MetricCard` contracts before comparing peer states. The remaining Customer Health KPI summary is a clear system inconsistency: its detail collection already uses the accepted REPORT012 responsive grammar, while the adjacent three-card summary still delegates layout to legacy page-level `report-grid` composition.

The existing shared `MetricGrid columns={3}` already owns exactly the missing responsibility and needs no API/CSS/token change. Its established contract produces Desktop three columns, Tablet two columns and Mobile one column with `minmax(0, 1fr)` containment. The existing report `MetricCard` already retains caller-owned trust/freshness/status semantics, `minWidth: 0`, LTR numeric presentation and long-value wrapping. Reusing those contracts removes duplicate responsive ownership without shifting any customer-health truth into the Design System.

I also inspected `CustomerReengagementPage.tsx` as another remaining Reports candidate. Its five-card custom KPI family, custom priority/accent language and 5-up layout do not fit the current `MetricGrid` 2/3/4-column contract without a broader component/domain decision, so it is intentionally not selected for this slice. Customer Health is the smaller, safer and more coherent next move.

## REPORT025 bounded contract

Implementation must:
- add the existing `MetricGrid` import from `@/components/patterns/MetricGrid`;
- replace only the Customer Health summary `<div className="report-grid">` wrapper with `<MetricGrid columns={3}>`;
- preserve `isLoading` and exactly three `SkeletonCard height={150}` summary placeholders;
- preserve ready-card order exactly: `نشطون` → `خامدون` → `متوسط القيمة (90 يوم)`;
- preserve every card label/subtitle/value/status/freshness/stale/domain/icon contract;
- preserve the third card's conditional `secondary` average-recency fact exactly;
- use the unchanged shared device grammar: Desktop 3 / Tablet 2 / Mobile 1.

The summary cards remain passive informational surfaces. No focus/keyboard/touch/action/permission semantics are added. Arabic-first ordering/copy, existing LTR monetary/numeric treatment, long-value containment and dark/RTL token behavior must remain intact.

## Explicit exclusions / preservation boundary

REPORT025 must not change:
- page header/title/subtitle/date control or `SystemHealthBar`;
- the complete REPORT012 Customer Health detail-collection contract: blocked state, Trust/Freshness actions, semantic five-column Desktop table, Tablet/Mobile `ResponsiveCollection + Card + KeyValueList` renderers, recency/status treatment, five-row loading state, exact empty copy or >50 informational footer;
- `MetricCard` design/API or migration to another metric primitive;
- shared `MetricGrid` API/CSS/tokens;
- global `report-grid` cleanup;
- date-field/filter/table/DataTable/pagination/export/print convergence;
- hooks, queries, cache/data shaping, calculations, trust-key logic, permissions/RBAC/RLS, routing, backend/services, validation, workflow or any business semantic.

If preserving these truths requires shared-contract widening or functional change, the slice becomes `BLOCKED` instead of growing.

## Focused evidence expectation

`CustomerHealthPage.test.tsx` should be extended narrowly to protect the new layout ownership while retaining every existing REPORT012 detail-collection test:
- ready summary mounts `[data-metric-grid]` with `data-columns="3"`;
- exact three ready-card labels/order remain present;
- loading summary contains exactly three `150px` skeletons inside the MetricGrid, without confusing them with the existing detail collection's five `44px` loading rows.

Tests are to be authored, not falsely claimed executed. No runtime/visual/build/test/lint/preview/release PASS is implied by this design direction.

## Peer-state synthesis / contradiction status

I formed the Product Design judgment independently, then compared the repository team state:
- **Team Memory / Development Integrator:** current and explicitly hand REPORT025 to Product Design for exact bounding after REPORT024 integration.
- **UI Production Engineer / Design QA / previous Product Design state:** lifecycle-stale at the completed REPORT024 PR, but no rule or blocker conflicts with REPORT025.
- **Decision Log / North Star / component/page/device guidance:** aligned with shared-system-before-local invention, layout-only MetricGrid ownership, Arabic-first responsive composition and strict functional isolation.
- **Open PRs targeting Development:** none at selection time, so no competing implementation slice exists.

Current contradiction classification: `NONE`.

## What changed since previous state

- REPORT024 is now integrated; the previous exact-head acceptance state is consumed and lifecycle-stale.
- The generic REPORT025 roadmap placeholder is now decomposed into one concrete bounded slice: Customer Health summary metric-grid convergence.
- UI Production is authorized to implement exactly this slice from the latest Development HEAD.
- No durable system rule or overall product direction changed, so `TEAM_MEMORY.md` and `DECISION_LOG.md` do not require Product Design mutation.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the prescribed order.
- Inspected issue #27, exact latest Development HEAD, open PRs targeting Development, current Reports directory, representative remaining report surfaces and the relevant component/page/migration/device guidance.
- Inspected exact `CustomerHealthPage.tsx`, its existing focused tests, shared `MetricGrid`, shared responsive CSS and report `MetricCard`.
- Compared the alternative Customer Reengagement KPI surface and rejected it for this slice because it would require broader shared/domain design work.
- Updated the Workstream to make REPORT025 `READY — BOUNDED`.
- Updated only this owned specialist state among role-state files.
- Did not implement product code, merge a PR, touch `main`, deploy Vercel, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA after a future stable PR HEAD.
- **What changed:** REPORT025 is now concretely bounded to Customer Health's three-card KPI summary adopting existing `MetricGrid columns={3}` only.
- **Preserve:** exact three cards/order/labels/subtitles/values/Trust/Freshness/status/domain/icons and conditional average-recency secondary fact; exactly three `SkeletonCard height={150}` placeholders under existing `isLoading`; Desktop 3 / Tablet 2 / Mobile 1 shared composition; the complete REPORT012 Customer Health detail collection and all functional/query/trust/permission/backend/business semantics; unchanged shared APIs/CSS/tokens; honest non-executed evidence.
- **Need from you:** UI Production should branch from the latest `design-system-v2-development` HEAD, implement only this wrapper convergence plus focused tests, and open one PR targeting Development. If any excluded shared or functional change is required, mark REPORT025 `BLOCKED` rather than widen scope. Design QA should review only the future exact stable PR HEAD.
- **Blocker level:** `NONE`.
- **Baseline:** Product Design source baseline `0fc85407e7ca107493a84bd808020af76e846778`; Workstream boundary commit `448c324cbaa1ddeaa821c390c13e185270553d59`.