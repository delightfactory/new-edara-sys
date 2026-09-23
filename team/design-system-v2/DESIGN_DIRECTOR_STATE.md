# Product Design Director State

## Reviewed baseline

- Review date/time: `2026-09-23 15:00 Africa/Cairo`.
- Authoritative branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-037`.
- Current product integration: PR #85 squash `2af5917c0b370d1bd6aaa785ef248f6084e483d3`.
- Development HEAD at the start of this Product Design run: `3edeb12a543155e79ae81a7775d57e65be1eb6e4`.
- Workstream boundary commit created this run: `d0b2dc8bb5352d5b52720034ea7cbda246ede45b`.
- Open implementation PRs targeting Development at selection time: none.
- Current single READY slice: `DS2-REPORT-038 — Receivables chart empty-state convergence`.
- Status: `READY — BOUNDED`.
- Current contradiction classification: `NONE`.

## Independent Product Design judgment

**REPORT038 should converge only the Receivables AR chart empty renderer onto the existing shared passive `StatePanel` grammar.**

I formed this judgment from the exact latest Development source, the current Receivables focused tests, the shared `StatePanel` contract and adjacent integrated report proofs before comparing peer role states.

The Receivables page is already materially aligned with the V2 report grammar through `MetricGrid`, report-domain `MetricCard`, `ChartPanel`, `ReportFilterBar`, Trust/Freshness and shared loading treatment. The smallest remaining presentation-only inconsistency on that surface is the chart's bespoke 260px centered empty text block. Existing Product Performance proves the correct system split: the page may continue to own fixed analytical geometry while shared `StatePanel` owns empty-state anatomy.

This advances system coherence without changing chart data, trust semantics, business truth or any shared API.

## Bounded REPORT038 contract

Representative surface:
- `src/pages/reports/ReceivablesPage.tsx` → `تحصيلات AR مجمّعة بتاريخ البيع الأصلي` → chart empty branch only.

Required implementation:
- replace only the bespoke empty renderer with existing `StatePanel kind="empty"`;
- preserve exact visible copy `لا توجد بيانات تحصيل في هذه الفترة`;
- preserve the chart-body footprint at exactly 260px through a page-owned geometry wrapper;
- use compact/passive shared state anatomy, with no action, click target, focus target or live announcement;
- preserve exact state precedence `isBlocked -> dailyLoading -> empty -> ready chart`.

Preserve unchanged:
- existing BLOCKED branch, title `بيانات AR محجوبة`, description `يحتاج إلى اكتمال تشغيل محرك AR أولاً`, trust meaning and 260px geometry;
- exactly one `SkeletonCard height={260}` for chart loading;
- `ChartPanel` title/description and TrustStateBadge/FreshnessIndicator action;
- ready chart `ResponsiveContainer` height 260, margins `{ top: 4, left: -10, right: 4, bottom: 0 }`, data mapping `date / receipts / refunds / net`, and all three bar series names/colors/radii/max widths;
- Arabic/RTL composition and LTR numeric presentation;
- summary MetricGrid/MetricCards, ReportFilterBar and SystemHealthBar;
- all hooks, query/cache/calculation/trust/permission/RBAC/RLS/routing/export/print/backend/business/workflow semantics;
- all shared `StatePanel`, `ChartPanel`, CSS, token and breakpoint contracts.

Explicit stop rule:
- if the implementation requires reinterpreting the BLOCKED state, widening a shared contract/CSS rule, changing data/trust semantics or touching any other report surface, mark REPORT038 `BLOCKED` instead of widening the PR.

## Device / state / accessibility acceptance

- **Desktop / Tablet / Mobile:** the same passive empty renderer is used; the 260px analytical body footprint remains stable and the ready chart tree does not mount while empty.
- **Arabic / RTL:** exact Arabic copy remains; no fixed-width text constraint or ordinary horizontal-overflow source may be introduced.
- **Loading:** loading remains higher priority than empty and stays exactly 260px.
- **BLOCKED:** remains higher priority than loading/empty/ready and remains visually/semantically untouched.
- **Empty accessibility:** no action slot, interactive element, alert role or live announcement; `StatePanel` empty semantics remain passive.
- **Ready:** chart mapping, geometry, series and Trust/Freshness remain unchanged.

## Focused test-artifact expectation

Update the existing Receivables focused tests to protect:
- one `.ds-state-panel[data-state-kind="empty"]` with exact copy inside the 260px empty wrapper;
- compact/passive semantics with no action/live announcement/focus target;
- BLOCKED priority and absence of shared empty StatePanel in BLOCKED;
- 260px loading skeleton priority and no empty/ready chart leakage while loading;
- unchanged ready 260px container, margins, data mapping and three series contracts;
- unchanged Trust/Freshness continuity.

Evidence must remain honestly labeled `TESTS_AUTHORED_NOT_EXECUTED` unless an approved exact-head runtime actually executes tests. No hosted CI or Vercel preview is authorized.

## Peer-state synthesis / contradiction handling

After forming the independent judgment, I compared current repository memory and peer states:

- **Team Memory:** current through REPORT037 and explicitly hands REPORT038 to Product Design for one smallest bounded concern; aligned.
- **Development Integrator:** current through REPORT037 integration and hands REPORT038 to Product Design; aligned.
- **UI Production Engineer:** lifecycle-stale through REPORT037 implementation, with no competing active PR or blocker.
- **Design QA:** lifecycle-stale through REPORT037 exact-head review; no REPORT038 approval exists or is expected before implementation.
- **Previous Product Design state:** lifecycle-stale through REPORT037 exact-head acceptance and superseded by this state.
- **Decision Log / North Star / Component Decision Matrix / Device Strategy:** aligned with shared-state consolidation, caller-owned business semantics, Arabic-first multi-device composition and strict functional isolation.

Current contradiction classification: `NONE`.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the prescribed order.
- Inspected issue #27, exact latest Development HEAD and all open PRs targeting Development.
- Confirmed there was no active implementation PR before REPORT038 selection.
- Inspected representative remaining Reports surfaces and chose the smallest safe system-level gap rather than broad report beautification.
- Inspected `ReceivablesPage.tsx`, its focused tests, shared `StatePanel`, adjacent integrated `ProductPerformance` proof and relevant V2 blueprint/migration/device documents.
- Updated the Workstream to bound exactly one READY REPORT038 concern.
- Updated only this owned specialist state file.
- Did not modify product code, peer role states, Team Memory or Decision Log.
- Did not merge, touch `main`, deploy Vercel, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer; then Design QA and Product Design after a stable implementation PR HEAD exists.
- **What changed:** REPORT038 is now bounded to the Receivables AR chart empty branch only, converging its bespoke empty text onto existing passive `StatePanel kind="empty"` while retaining page-owned 260px analytical geometry.
- **Preserve:** exact empty copy; exact `isBlocked -> dailyLoading -> empty -> ready chart` precedence; untouched BLOCKED branch/meaning/copy; 260px loading/empty/ready body contracts; exact ready chart mapping/margins/three series; ChartPanel title/description; Trust/Freshness; summary/filter/system-health surfaces; all query/trust/permission/backend/business semantics; unchanged shared contracts.
- **Need from you:** start from the latest Development HEAD after these governance commits, implement REPORT038 only, update focused Receivables tests, and open exactly one Draft PR targeting `design-system-v2-development`. If any excluded or shared-contract widening becomes necessary, stop and mark the slice `BLOCKED`.
- **Blocker level:** `NONE`.
- **Baseline:** selection baseline `3edeb12a543155e79ae81a7775d57e65be1eb6e4`; Workstream boundary commit `d0b2dc8bb5352d5b52720034ea7cbda246ede45b`.