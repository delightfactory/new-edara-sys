# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-21`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD independently inspected before REPORT018 bounding: `9b06a32dedd92527c79f8c74408b79c6f2b4211e`.
- REPORT018 Workstream bounding commit: `97741761ac37161103a3e944d40bc84de405bc42`.
- Latest integrated product baseline: `DS2-REPORT-017` / PR #65, squash merge `3474748541068600e1deae061bf68fca23b346ef`.
- Current single READY slice: `DS2-REPORT-018 — Treasury daily cashflow chart-panel convergence`.
- Representative surface: `src/pages/reports/TreasuryPage.tsx` → `التدفق النقدي اليومي` chart section only.
- Open implementation PRs targeting Development at final pre-state check: none.
- Current Product Design disposition: `READY — BOUNDED / NO DESIGN-SYSTEM BLOCKER`.
- No build/test/lint/runtime/preview/release PASS is claimed.

## Independent Product Design judgment

**READY — REPORT018 is dependency-safe and bounded to one presentation-only Treasury chart shell.**

I independently inspected the exact latest integrated Reports baseline, remaining Reports surfaces, the current Treasury composition, the shared `ChartPanel` contract and an already integrated `ChartPanel` consumer before comparing peer states. The smallest useful next concern is the page-local analytical surface around `التدفق النقدي اليومي`: it duplicates the neutral Card/header hierarchy already owned by `ChartPanel`, while all Treasury data, trust, state and chart behavior can remain unchanged.

This advances system coherence without creating another page-specific responsive pattern, without broad multi-page beautification, and without requiring backend/business changes.

## REPORT018 design contract

### Scope / system intent

- Replace only the local surface/header wrapper around Treasury `التدفق النقدي اليومي` with shared `ChartPanel`.
- Preserve exact section title `التدفق النقدي اليومي` and description `net_cashflow — مجمّع يومياً في قاعدة البيانات`.
- Preserve the existing `TrustStateBadge + FreshnessIndicator` cluster as the `ChartPanel` action content, with safe compact-width wrapping.
- Use the shared default semantic section heading so page hierarchy becomes `h1` page → `h2` chart section.
- Do not widen `ChartPanel`, shared CSS or tokens; the current shared contract is already sufficient.

### Data / visualization truth to preserve

Preserve exactly:
- `chartData` mapping: `date <- treasury_date`, `inflow <- gross_inflow`, `outflow <- gross_outflow`, `net <- net_cashflow`;
- caller-owned ordering;
- `ResponsiveContainer width="100%" height={280}`;
- `AreaChart` data and current margins;
- all three gradient ids, colors and opacities;
- Cartesian grid, X/Y axes, tick formatters and styling;
- current `CustomTooltip` usage and behavior;
- zero `ReferenceLine`;
- Area series names `داخل / مستردّ / صافي`, data keys, colors, stroke widths, fills and dot behavior.

No data meaning or chart semantics move into the Design System.

### State / trust truth to preserve

Preserve state precedence and exact presentation:
- blocked/failed first: 280px blocked panel with current two-line copy;
- then `dailyLoading`: `SkeletonCard height={280}`;
- then empty: 280px surface with exact copy `لا توجد تدفقات خزينية في هذه الفترة`;
- then ready chart.

Trust resolution, `SystemHealthBar`, freshness meaning and all hook/query/cache behavior remain caller-owned and unchanged.

### Device / RTL / accessibility acceptance

- **Mobile:** shared ChartPanel must contain the chart at 100% width with no new page-level horizontal overflow; title/description/action cluster remains legible under Arabic wrapping.
- **Tablet:** deliberate contained analytical surface; action cluster may wrap without crowding the heading; no touch interaction is invented for informational trust/freshness badges.
- **Desktop:** retain the same management-facing chart density and 280px chart height.
- **RTL / Arabic:** preserve RTL composition and long Arabic wrapping through shared semantic surfaces; do not alter chart-series color meaning.
- **Dark mode:** rely on current semantic Card/SectionHeader/ChartPanel surfaces and tokens; no local palette expansion.
- **Accessibility:** semantic section heading improves hierarchy; no click/focus/keyboard affordance is added because the section remains informational.

### Explicit exclusions

Do not change:
- Treasury page header or `ReportFilterBar`;
- semantic-contract notice;
- `SystemHealthBar`;
- the three KPI `MetricCard`s or summary loading behavior;
- `CustomTooltip` content/behavior;
- hooks, queries, cache/data semantics, calculations or trust resolution;
- permissions/RBAC/RLS, routing, backend/service contracts, validation, export/print, workflow or business semantics;
- `ChartPanel` API, shared CSS/tokens or any other report surface.

If any excluded shared-system widening or functional/data-semantic change is required, REPORT018 becomes `BLOCKED` rather than expanding scope.

### Test artifact expectation

UI Production should add focused Treasury coverage protecting:
- shared `ChartPanel` adoption and `h1 -> h2` hierarchy;
- exact title/description and trust/freshness presence;
- blocked/loading/empty/ready precedence and exact copy/heights;
- unchanged `chartData` mapping and caller ordering;
- unchanged core chart configuration/series semantics.

Normal evidence remains `TESTS_AUTHORED_NOT_EXECUTED` unless an approved runtime actually executes the tests.

## Peer-state synthesis / contradiction status

This judgment was formed independently first, then compared with repository memory and peer states.

- **Development Integrator:** current and aligned; REPORT017 is merged and Integrator explicitly handed REPORT018 to Product Design for one smallest safe boundary.
- **Team Memory:** aligned; REPORT017 is integrated and the generic REPORT018 placeholder required exactly this decomposition before implementation.
- **UI Production:** Development copy remains lifecycle-stale from REPORT017, not contradictory; it contains no active competing implementation.
- **Design QA:** Development copy remains lifecycle-stale from REPORT017, not contradictory; fresh REPORT018 exact-head review will be required after implementation.
- **Decision Log / North Star:** aligned with UI-only functional isolation, shared-system reuse, Arabic-first deliberate device behavior and no hosted CI/deployment activity.

Current contradiction classification: **NONE**.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the prescribed order.
- Inspected issue #27, exact Development HEAD and open PRs targeting Development.
- Inspected relevant component/page/device/migration guidance, representative remaining Reports surfaces, exact Treasury source, shared `ChartPanel`, and an integrated `ChartPanel` precedent.
- Bound REPORT018 in `31_AGENT_TEAM_WORKSTREAM.md` as one Treasury chart-shell concern; Workstream commit `97741761ac37161103a3e944d40bc84de405bc42`.
- Updated only this owned specialist state among role-state files.
- Did not update Team Memory or Decision Log because no overall system direction or durable rule changed.
- Did not modify product code, merge a PR, touch `main`, trigger/rerun GitHub Actions, use hosted CI, deploy Vercel or modify preview branches.

## What changed since previous state

- REPORT017 is now integrated and its prior active-PR state is superseded.
- The generic REPORT018 roadmap placeholder is now decomposed into one exact Treasury chart-panel migration with device/state/accessibility acceptance and explicit exclusions.
- UI Production is now authorized to implement REPORT018 from the exact latest Development baseline; no competing implementation PR existed at selection/final pre-state check.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA after a stable implementation PR exists.
- **What changed:** REPORT018 is now bounded as `Treasury daily cashflow chart-panel convergence`, limited to the `التدفق النقدي اليومي` local surface/header shell and reuse of existing shared `ChartPanel`.
- **Preserve:** exact Treasury chart data mapping/order/configuration/series colors and labels; Trust/Freshness; blocked/loading/empty/ready precedence and exact copy/heights; 280px chart density; Arabic/RTL/dark-mode semantics; page header/filter/notice/SystemHealth/KPIs/CustomTooltip and all functional/business contracts; unchanged shared APIs/CSS/tokens.
- **Need from you:** UI Production should start from the latest Development HEAD, implement only this slice and author focused contract tests in one Draft PR targeting `design-system-v2-development`. If shared-contract widening or any functional/data-semantic change is required, mark `BLOCKED`. Design QA should independently inspect the future exact stable PR HEAD.
- **Blocker level:** `NONE`.
- **Baseline:** REPORT018 bounded on Development Workstream commit `97741761ac37161103a3e944d40bc84de405bc42`; latest integrated product merge `3474748541068600e1deae061bf68fca23b346ef`.
