# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-22`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD at mandatory bootstrap / independent source review: `4a7ee557c3df4630f86710ebaccaeae3014c18ec`.
- Latest integrated product baseline: `DS2-REPORT-023 — Sales summary metric-grid convergence` / PR #71 / squash merge `407996fd63fe49e26ef9747618426d725d408c81`.
- Open implementation PRs targeting Development at selection time: none.
- Current single implementation-authorized slice: `DS2-REPORT-024 — Treasury summary metric-grid convergence`.
- Current disposition: `READY — BOUNDED`.
- Representative surface: `src/pages/reports/TreasuryPage.tsx` → three-card treasury KPI summary only.
- Workstream bounding commit: `5f459faf949d059e2359f28c48f98015d96d1169`.
- Evidence at this stage: Product Design source inspection only; no implementation/test/build/runtime/visual PASS is claimed for REPORT024.

## Independent Product Design judgment

REPORT024 should converge the remaining Treasury KPI-summary layout onto the already-proven shared `MetricGrid` contract and do nothing else.

On exact Development baseline `4a7ee557c3df4630f86710ebaccaeae3014c18ec`, Treasury already has the correct report-domain `MetricCard`s and an accepted shared `ChartPanel` from REPORT018, but the three-card summary still uses the legacy page-level `report-grid`. This is a clean duplicated-layout ownership gap: the shared `MetricGrid columns={3}` already owns exactly the required responsive presentation responsibility while Treasury calculations, trust/freshness and business meaning remain caller-owned.

The smallest safe change is therefore wrapper-only. Replace the KPI-summary `report-grid` with existing `MetricGrid columns={3}` in the current loading/ready branch. Preserve `summaryLoading`, exactly three `SkeletonCard height={160}` placeholders, and the exact ready-card order/contracts: `صافي التدفق الخزيني`, `إجمالي التحصيل الداخل`, `إجمالي المسترد`; current subtitles, `fmtCur` values, `trsTrust` status/freshness/stale wiring, `domain="treasury"`, and the `Wallet`, `ArrowDownToLine`, `ArrowUpFromLine` icons.

This gives the canonical device composition without any new local breakpoint or shared widening: Desktop three-column comparison, Tablet two columns, Mobile one column. The shared CSS already uses `minmax(0, 1fr)` / `min-width: 0`, while the existing `MetricCard` continues to own report-specific content containment and numeric presentation. The cards remain passive informational surfaces, so no interaction/focus/touch semantics need to change.

The Treasury `ChartPanel` is explicitly outside scope. REPORT018 already established its neutral analytical shell and exact blocked/loading/empty/ready, 280px, data mapping, gradient, axis, tooltip, reference-line and series contracts. Mixing chart work into REPORT024 would create unnecessary regression risk and violate one-concern slicing.

Larger remaining surfaces such as Customer Reengagement, broader report FilterBar/search grammar, dense table cleanup and export/print convergence are materially more complex because they combine actions, state, responsive orchestration or business-facing semantics. They should remain separately bounded backlog work rather than being pulled into this slice.

## Acceptance boundary

### Required

- consume existing `MetricGrid columns={3}` unchanged;
- replace only the Treasury KPI-summary outer `report-grid` wrapper and add the required import;
- preserve exactly three `160px` summary skeletons under the existing `summaryLoading` gate;
- preserve exact three ready cards, DOM/business order, labels, subtitles, values, trust/freshness/status/stale/domain/icon wiring;
- Mobile `<=768px`: one-column stack, no ordinary KPI-grid horizontal overflow;
- Tablet `769–1024px`: deliberate shared two-column composition;
- Desktop `>=1025px`: three-column management comparison;
- preserve Arabic/RTL order/wrapping and current numeric/LTR treatment inside the existing report cards;
- keep cards informational/non-interactive;
- extend focused Treasury tests for `[data-metric-grid]`, `data-columns="3"`, exact three-card order/contracts and exactly three `160px` summary loading placeholders while retaining REPORT018 chart tests.

### Explicitly excluded

- page header/title/description, `ReportFilterBar`, semantic-contract notice and `SystemHealthBar`;
- Treasury `ChartPanel`, Trust/Freshness chart action and every chart state/body/data/visualization contract;
- hooks, query/cache/data mapping, calculations, trust-key/fallback logic, permissions/RBAC/RLS, routing, backend/services, validation, export/print/workflow/business semantics;
- report-domain `MetricCard` redesign;
- shared `MetricGrid` API/CSS/tokens or any global `report-grid` cleanup;
- every other Reports/Analytics surface.

If implementation reveals that any excluded shared or functional change is necessary, REPORT024 becomes `BLOCKED` rather than expanding the PR.

## Peer-state synthesis / contradiction status

I formed the REPORT024 direction from the exact current Treasury source, existing `MetricGrid` implementation/responsive CSS, Treasury focused tests and the current North Star/component/page/device guidance before comparing peer lifecycle states.

- **Team Memory / Development Integrator:** current and aligned that REPORT023 is merged and exactly one placeholder REPORT024 awaited Product Design bounding.
- **UI Production Engineer:** lifecycle-stale at the now-merged REPORT023 implementation; no conflicting REPORT024 implementation exists.
- **Design QA:** lifecycle-stale at REPORT023 exact-head review; no REPORT024 approval or blocker exists yet.
- **Previous Product Design state:** lifecycle-stale at REPORT023 acceptance and superseded by this bounded next-slice direction.
- **Decision Log / North Star / shared component contracts:** aligned with layout-only shared ownership, Arabic-first responsive composition, canonical device boundaries and strict functional isolation.
- **Open PR search:** no implementation PR targeting `design-system-v2-development` at selection time, so no competing slice exists.

Current contradiction classification: `NONE`.

## What changed since previous state

- REPORT023 is now integrated and its prior exact-head Product Design acceptance is consumed.
- Product Design inspected the exact latest Development baseline and decomposed the REPORT024 roadmap placeholder into one concrete smallest safe concern: Treasury three-card summary metric-grid convergence.
- REPORT024 is now `READY — BOUNDED` for UI Production; implementation was not performed by Product Design.
- No durable rule or overall system direction changed, so `TEAM_MEMORY.md` and `DECISION_LOG.md` do not require Product Design mutation in this run.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the required order.
- Inspected issue #27, exact Development HEAD, open PRs targeting Development, Treasury source/tests, shared `MetricGrid` implementation/responsive CSS, and relevant component/page/migration/device guidance.
- Updated the Workstream to replace the generic REPORT024 placeholder with the exact bounded Treasury contract.
- Updated only this owned specialist state among role-state files.
- Did not implement product code, merge any PR, touch `main`, deploy Vercel, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA after implementation PR opens.
- **What changed:** `DS2-REPORT-024 — Treasury summary metric-grid convergence` is now `READY — BOUNDED`; only the three-card Treasury KPI-summary wrapper may converge from local `report-grid` to existing `MetricGrid columns={3}`.
- **Preserve:** `summaryLoading`; exactly three `SkeletonCard height={160}` placeholders; exact three cards/order/labels/subtitles/`fmtCur` values/`trsTrust` status-freshness-stale/domain/icon contracts; Mobile 1 / Tablet 2 / Desktop 3 shared composition; the entire accepted REPORT018 Treasury ChartPanel/state/data/series contract; all query/calculation/trust/permission/backend/business behavior; no shared API/CSS/token widening.
- **Need from you:** start from the latest Development HEAD after this governance write, implement REPORT024 only, add focused summary-grid tests while retaining existing chart tests, label evidence honestly as `TESTS_AUTHORED_NOT_EXECUTED` unless approved exact-head local execution actually occurs, and open one PR targeting `design-system-v2-development`. If excluded work becomes necessary, mark the slice `BLOCKED` instead of widening it.
- **Blocker level:** `NONE`.
- **Baseline:** Product Design source baseline `4a7ee557c3df4630f86710ebaccaeae3014c18ec`; Workstream bounding commit `5f459faf949d059e2359f28c48f98015d96d1169`; latest integrated product merge `407996fd63fe49e26ef9747618426d725d408c81`.
