# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-22`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD independently inspected before Product Design bounding: `9a9830e5255630e6acf82cfa1012e008e6bcf069`.
- Latest integrated product baseline: `DS2-REPORT-021 — Receivables summary metric-grid convergence` / PR #69 / squash merge `e93463e9d59d5979eea44edec3afb0e2ffd8bb56`.
- Open PRs targeting Development at decision time: none.
- Current single implementation slice: `DS2-REPORT-022 — Rep Credit Commitment summary metric-grid convergence`.
- Slice state: `READY — BOUNDED`.
- Immediate next owner: UI Production Engineer.
- Workstream bounding commit: `bb15acd1d7a0d276338946776112a3a7ee40bec1`.

## Independent Product Design judgment

The smallest dependency-safe Reports concern on the current baseline is the four-card filtered KPI summary in `src/pages/reports/RepCreditCommitmentPage.tsx`.

The page currently recreates responsive summary layout locally with `css.kpiGrid` (`repeat(auto-fit, minmax(180px, 1fr))`) in both loading and ready states. The existing shared `MetricGrid` already owns the exact layout responsibility without owning metric meaning: Desktop supports four columns, Tablet canonicalizes four-column summaries to two columns, and Mobile canonicalizes to one column. The local metric cards can remain caller-owned for this slice, so no shared API, card semantic, status-tone or business change is required.

This is preferable to opening the larger Customer Reengagement or Rep Credit table/drawer work now. Those surfaces combine filters, interactive row actions, permissions, output/drawer semantics and responsive collection orchestration; widening REPORT022 into those concerns would violate the smallest-slice rule.

## REPORT022 bounded contract

### System-pattern intent

- Replace the page-local KPI grid layout with existing `MetricGrid columns={4}` in the loading and ready summary branches only.
- Use the established shared device grammar: Desktop 4 columns, Tablet 2, Mobile 1.
- Preserve all four KPI cards as caller-owned content/presentation in REPORT022; no `StatCard`/`MetricCard` migration is authorized in this slice.

### Preserve exactly

Ready card order and meaning:
1. `مسؤولو المحافظ` — `summary.totalReps` — `لديهم عملاء بأرصدة فعلية`.
2. `إجمالي محافظ المتابعة` — `fmt(summary.totalPortfolio)` — `يشمل الأرصدة الافتتاحية`.
3. `إجمالي المديونية المنشأة` — `fmt(summary.totalCreatedDebt)` — `فواتير مسلَّمة صافيها > 0`.
4. `إجمالي التحصيلات المؤكدة` — `fmt(summary.totalConfirmedCollections)` — `إيصالات confirmed فقط`.

Also preserve:
- current local card shell/accent styling and exact card order;
- loading as exactly four caller-owned shimmer cards, each `6rem` high with the current surface/shimmer behavior;
- ready summary absence when `rows.length === 0`;
- the separate `summary.hasUnassigned` warning immediately after the summary, unchanged;
- current error/empty/filter indicators and all surrounding page behavior.

### Device / RTL / accessibility acceptance

- Desktop `>=1025px`: four-card comparison row through shared `MetricGrid columns={4}`.
- Tablet `769–1024px`: two-column shared composition.
- Mobile `<=768px`: one-column stack, no ordinary horizontal overflow, safe Arabic wrapping.
- DOM/business order remains the same in RTL.
- No interaction is added or removed, so current keyboard/touch semantics remain unchanged.

### Explicit exclusions

No change to:
- `deriveFilteredSummary`, `applyPageFilters`, query/service/cache/data/calculation semantics;
- page header, paper selector, `DocumentActions`, print params, filters, advanced ranges, sorting/reset;
- table/mobile-card renderer, `useIsMobile`, row click/hover behavior;
- drawers, drawer filters, customer/order/receipt sections or credit-state logic;
- `StatCard`, `MetricCard`, FilterBar, ResponsiveCollection, DataTable or warning-banner redesign;
- shared `MetricGrid` API/CSS/tokens;
- backend/services, RBAC/RLS/permissions, routing, validation, export/print semantics, workflow or deployment.

If implementation requires any shared-contract widening or functional semantic change, REPORT022 becomes `BLOCKED` rather than expanding.

### Focused evidence contract

Author focused source tests that prove:
- loading and ready summary branches consume the shared grid with `data-columns="4"`;
- loading still exposes exactly four summary placeholders without altering table/page loading semantics;
- ready state preserves the exact four labels/order;
- the unassigned warning remains outside the grid and unchanged.

Hosted CI remains forbidden. Use `TESTS_AUTHORED_NOT_EXECUTED` unless tests are actually executed in an allowed local environment.

## Peer-state synthesis / contradiction status

This judgment was formed from the current source, shared `MetricGrid`/responsive CSS contract and North Star before comparing peer states.

- **Integration State / Team Memory:** current through REPORT021 and both hand Product Design the unbounded REPORT022 placeholder; aligned.
- **UI Production State / Design QA State:** lifecycle-stale at REPORT021 but contain no active competing implementation or contradictory system rule.
- **Decision Log / North Star / component and migration guidance:** aligned with reusing an established layout-only pattern and preserving business semantics.
- Open PR inspection found no implementation PR targeting Development, so no competing slice exists.

Current contradiction classification: `NONE`.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the required order.
- Inspected issue #27, latest Development HEAD, open PRs targeting Development, Reports inventory and relevant component/page/device/migration guidance.
- Compared remaining report debt and selected the smallest dependency-safe concern.
- Bounded REPORT022 in `31_AGENT_TEAM_WORKSTREAM.md` at commit `bb15acd1d7a0d276338946776112a3a7ee40bec1`.
- Updated only this owned specialist state after the material lifecycle change.
- Did not modify Team Memory or Decision Log because no overall system direction or durable rule changed.
- Did not modify product code, merge any PR, touch `main`, deploy Vercel, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer.
- **What changed:** `DS2-REPORT-022 — Rep Credit Commitment summary metric-grid convergence` is now `READY — BOUNDED`; implementation is authorized only for the four-card summary layout in `src/pages/reports/RepCreditCommitmentPage.tsx`.
- **Preserve:** exact four loading placeholders and four ready KPI cards/order/values/subtitles/local accent styling; `deriveFilteredSummary`; empty/error/filter behavior; separate unassigned warning; header/output/filter/table/mobile-card/drawer/credit semantics; all shared APIs/CSS/tokens and functional truth.
- **Need from you:** start from current Development HEAD, replace only the loading/ready `css.kpiGrid` wrappers with existing `MetricGrid columns={4}`, remove the local grid style only if unused, author focused tests, and open exactly one PR targeting `design-system-v2-development`. Mark `BLOCKED` rather than widening shared or functional scope.
- **Blocker level:** `NONE`.
- **Baseline:** Product Design source baseline `9a9830e5255630e6acf82cfa1012e008e6bcf069`; bounded Workstream commit `bb15acd1d7a0d276338946776112a3a7ee40bec1`; latest integrated product merge `e93463e9d59d5979eea44edec3afb0e2ffd8bb56`.
