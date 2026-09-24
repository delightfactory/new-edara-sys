# Product Design Director State

## Reviewed baseline

- Review date/time: `2026-09-24 03:04 Africa/Cairo`.
- Authoritative branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-043`.
- Latest product integration: PR #91, squash merge `c9e28bd2b98bbf65d4d916e114cebb6cdcb86bf4`.
- Exact Development baseline inspected before bounding: `6180f9b346d64a041091d6d5916f980bb49c5e63`.
- Workstream boundary commit: `7538d3b01d8cc58a4b417db0b85e12bc9afc3398`.
- Active slice: `DS2-REPORT-044 — Reports Overview section-header convergence`.
- Current status: `READY — BOUNDED`.
- Active implementation PR targeting Development: `NONE` at bounding time.
- Current contradiction classification: `NONE`.

## Independent Product Design judgment

**REPORT044 is now dependency-safe and implementation-ready.**

I formed the next-slice judgment from the latest integrated Reports source and existing shared contracts before using peer lifecycle states. The smallest useful remaining concern is not another chart/empty-state micro-fix and not a broad Overview beautification pass. It is one repeated hierarchy primitive that is still being recreated locally on the Reports Overview page despite an existing sound shared pattern.

`src/pages/reports/OverviewPage.tsx` currently renders two section-heading compositions locally:
- `المؤشرات الرئيسية` as a page-local styled `h2`;
- `صحة قاعدة العملاء` inside a page-local flex heading/action row with the existing `عرض التفاصيل ←` link.

The shared `SectionHeader` already owns exactly this presentation responsibility: semantic heading level, title/description anatomy, optional independent action, min-width protection, and Mobile wrapping. Its CSS deliberately wraps the shared header at `<=768px` and constrains the action without inventing page-specific device behavior. Therefore REPORT044 should consume that existing grammar rather than extend it.

This is a system-convergence slice, not page-by-page beautification: the goal is to remove one independent section-header implementation and prove the canonical shared hierarchy grammar on a representative management/report surface.

## Bounded implementation contract

### Representative surface

`src/pages/reports/OverviewPage.tsx` only, plus focused `OverviewPage.test.tsx` coverage and UI Production's owned state file.

### Required presentation change

- Replace the local `المؤشرات الرئيسية` heading composition with existing shared `SectionHeader`, preserving semantic `h2`.
- Replace the local `صحة قاعدة العملاء` heading/action layout with existing shared `SectionHeader`, preserving semantic `h2` and passing the existing `Link` action unchanged in meaning and destination.
- Preserve exact action text `عرض التفاصيل ←` and route `/reports/customers`.
- Do not widen or modify shared `SectionHeader` implementation, CSS, tokens or breakpoints.

### Device / RTL / accessibility acceptance

- **Mobile 390:** shared SectionHeader wrapping must prevent clipping/ordinary horizontal overflow; Arabic title remains readable; the customer-details action remains an independent keyboard-focusable link and may wrap through the shared contract rather than page-local responsive CSS.
- **Tablet 900:** preserve deliberate compact management composition; no compressed heading/action collision or hidden action.
- **Desktop 1440:** preserve the existing section hierarchy and efficient horizontal title/action relationship.
- Both section titles remain real `h2` headings; no fake clickable card, nested interactive region, focus trap or live-region behavior is introduced.
- Long Arabic copy and mixed UI content must not be truncated by this slice.

### Focused test expectations

`OverviewPage.test.tsx` should protect:
- exactly the intended two shared `.ds-section-header` instances for these sections;
- exact Arabic titles and `h2` semantics;
- second section action contains the existing link and `/reports/customers` destination;
- existing summary/customer `MetricGrid` composition remains intact;
- existing loading contracts remain intact, including four summary skeletons and the single customer-health `SkeletonCard height={120}` branch.

Evidence remains `TESTS_AUTHORED_NOT_EXECUTED` unless an approved local exact-head runtime genuinely executes tests. Hosted GitHub Actions remain forbidden.

## Explicit exclusions / preserve exactly

Do not change:
- the top page title/subtitle/header and `ReportFilterBar` composition;
- `SystemHealthBar`, trust/freshness/domain wiring or report hooks;
- either `MetricGrid`, any `MetricCard`, KPI values/copy, or loading/state semantics;
- the navigation shortcut grid at the bottom of Overview;
- legacy `edara-card` navigation surfaces, shortcut colors/icons/routes/copy;
- Customer Re-engagement or any other report page;
- shared `SectionHeader` API/CSS/tokens/breakpoints;
- analytics/query/cache/calculation/date/filter/permission/RBAC/RLS/routing/export/print/backend/business/workflow semantics.

If the implementation discovers that this slice cannot be completed without changing shared `SectionHeader` behavior or functional semantics, it must move to `BLOCKED` rather than widening scope.

## Why broader neighboring debt is deferred

The Overview navigation grid is real debt: it still uses whole-card links with legacy `edara-card`, inline presentation and some raw accent hex values. It is deliberately **not** folded into REPORT044. The current shared `Card` contract is explicitly neutral and intentionally carries no click/navigation semantics; a premium whole-card navigation surface therefore deserves a separate interaction/focus/touch contract and a separately bounded slice. Treating the neutral Card as an interactive primitive or smuggling new CSS into this small slice would weaken the system architecture.

Customer Re-engagement is also intentionally deferred because its remaining debt spans filters, status/priority semantics, output/export, drawer behavior and operational actions. That is materially broader and riskier than the clean existing-contract convergence selected here.

## Peer-state synthesis / contradiction handling

After the independent judgment:

- **Development Integrator:** fresh lifecycle state confirms REPORT043 is merged and REPORT044 was intentionally `READY — UNBOUNDED` for Product Design. This run has now completed that required bounding step.
- **UI Production Engineer:** current Development copy remains historical through REPORT043 and contains no competing REPORT044 implementation.
- **Design QA:** current Development copy remains historical through REPORT043 and contains no competing REPORT044 disposition.
- **Team Memory:** integrated truth through REPORT043 is fresh and aligned; its REPORT044-unbounded handoff is now lifecycle-superseded by this bounded Workstream/state, not contradictory.
- **Decision Log / North Star / component/page/device docs:** aligned with shared-system-before-local-invention, Arabic-first hierarchy, adaptive composition and presentation-only ownership.
- **Open PR search targeting Development:** none at the time REPORT044 was bounded.

Current contradiction classification: `NONE`.

## Repository actions / what changed this run

- Completed the mandatory shared-memory bootstrap in the required order.
- Inspected issue #27, exact Development HEAD, open PRs targeting Development, Overview source/tests, shared `SectionHeader`, shared neutral `Card`, V2 surface CSS, and relevant component/page/device decision docs.
- Selected and bounded REPORT044 as the smallest dependency-safe existing-contract concern.
- Updated `31_AGENT_TEAM_WORKSTREAM.md` in commit `7538d3b01d8cc58a4b417db0b85e12bc9afc3398`.
- Did not update `TEAM_MEMORY.md` because overall system direction did not change.
- Did not update `DECISION_LOG.md` because no durable rule changed.
- Did not modify product code or any peer role state, merge a PR, touch `main`, deploy Vercel, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer.
- **What changed:** `DS2-REPORT-044 — Reports Overview section-header convergence` is now `READY — BOUNDED`; only the two local Overview section-heading compositions may converge onto existing shared `SectionHeader`.
- **Preserve:** exact section titles; `h2` semantics; existing `عرض التفاصيل ←` link and `/reports/customers` route; all MetricGrid/MetricCard/loading/SystemHealthBar/trust/query/business contracts; the entire Overview navigation grid; unchanged shared SectionHeader API/CSS/tokens/breakpoints.
- **Need from you:** branch from the exact latest `design-system-v2-development` HEAD after this state write, implement REPORT044 only, add focused Overview tests for shared header anatomy/semantics/action plus regression preservation, and open one Draft PR targeting Development. If shared-contract or functional widening becomes necessary, mark `BLOCKED` instead.
- **Blocker level:** `NONE`.
- **Baseline:** Product Design inspection baseline `6180f9b346d64a041091d6d5916f980bb49c5e63`; Workstream boundary commit `7538d3b01d8cc58a4b417db0b85e12bc9afc3398`; no implementation PR active at handoff.
