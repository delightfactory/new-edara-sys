# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-18`.
- Authoritative branch: `design-system-v2-development`.
- Latest integrated product slice: `DS2-WORK-003`, squash-merged as `95a84a8109f45cf9ac32c92d5d950f64d38dbaa0`.
- Exact Development product/source baseline independently inspected for this decision: `53e10ef8692d330250603f8a10d985003f3ac456`.
- Development HEAD after recording the bounded Workstream direction, immediately before this Director state write: `b97a67b07ac0fc9282920ae5b002c1a24d5a67e9`; that intervening commit is governance-only and does not alter the inspected report/shared-component source.
- Open implementation PRs targeting Development at review: none.
- Current single READY slice: `DS2-REPORT-001 — Report route sub-navigation convergence`.
- Representative surface: `src/pages/reports/ReportsLayout.tsx`.
- Product Design disposition: `READY — DEPENDENCY-SAFE / NO BLOCKER`.
- Runtime/build/lint/preview/release PASS: not claimed.

## Independent Product Design judgment

The smallest correct first Reports/Analytics slice is **route-level secondary-navigation convergence in `ReportsLayout` only**.

The current report shell recreates a full local route-navigation mini-system through `reports-tabs`, inline `NavLink` presentation and report-local navigation CSS even though V2 already has a mature shared `SubNav` explicitly designed for route-level secondary navigation. The shared contract already provides real-link semantics, active-route styling, focus-visible treatment, decorative-icon handling, horizontal containment/overflow, canonical 44px touch geometry and reduced-motion behavior.

This is a stronger first report slice than filter convergence. Representative report pages such as Overview and Sales use the local `ReportFilterBar`, whose preset/date controls carry query-sensitive date-range behavior and whose current presentation still includes report-local 32px preset-button treatment. The broader V2 roadmap already identifies FilterBar decomposition/mobile-filter behavior as component-depth debt. Pulling that debt into the first report PR would create a wider interaction and query-parity surface than necessary.

Therefore REPORT001 should prove the shared report shell/navigation grammar first, while explicitly preserving filter convergence as separate backlog debt rather than accepting the existing `ReportFilterBar` as canonical.

## Evidence inspected

### Report shell / route model

`ReportsLayout.tsx` currently:
- declares 14 report destinations with Arabic labels, Lucide icons and permission arrays;
- filters them through `tab.permissions.some(permission => can(permission))`;
- renders them through a local sticky horizontally scrolling `reports-tabs` + inline `NavLink` implementation;
- keeps `/reports/reengagement` and `/reports/visits` outside `AnalyticsGate` while all other child report outlets remain gated;
- also owns broad report-content/filter/grid CSS that is unrelated to the navigation renderer and must not be swept into this slice.

### Existing shared navigation contract

Shared `SubNav` is already the canonical route-level secondary navigation pattern:
- semantic named `<nav>`;
- real `NavLink` destinations and active-route class;
- caller-owned item model, so report permission eligibility remains outside the visual primitive;
- icons are decorative through `aria-hidden`;
- horizontal scroll containment, logical layout, focus-visible styling and at least `var(--ds-control-height-touch)` item height;
- existing focused tests already prove report-like route-link/active behavior.

### Representative filter/report pages

- `OverviewPage` and `SalesPage` both keep date-range state and pass it into report hooks through the existing `ReportFilterBar` contract.
- `ReportFilterBar` owns presets plus normalized custom date inputs and invokes the caller `onChange`; those semantics are not presentation-only trivia and must remain untouched here.
- Current report-shell CSS gives preset buttons only `32px` minimum height, reinforcing that report filter/touch convergence is real later debt, not a pattern to copy as the V2 answer.

## Bounded implementation direction

Implement exactly one concern in one PR:

1. Replace the local `reports-tabs` / inline `NavLink` route renderer in `ReportsLayout` with shared `SubNav`.
2. Preserve the already permission-filtered report destination model as caller-owned data; do not move permission resolution into `SubNav`.
3. Preserve all 14 current report routes, their order, Arabic labels, icons and permission arrays exactly.
4. Give the shared navigation a clear Arabic accessible name such as `أقسام التقارير`.
5. Remove only navigation-specific `reports-tabs` markup/style rules proven dead after adoption; leave unrelated report shell/content/filter/grid CSS untouched.
6. Add focused authored protection for shared `SubNav` adoption, exact permitted route order/labels, real-link/active-route semantics and the unchanged operational-page `AnalyticsGate` bypass.

No shared `SubNav` redesign is expected or authorized by default. If exact implementation evidence shows the existing shared contract cannot preserve parity without changing route/permission semantics, mark the slice `BLOCKED` instead of widening it.

## Device / RTL / accessibility acceptance

- **Mobile (`<=768px`)**: all permitted destinations remain reachable through the contained horizontal track; touch height remains at least 44px; no new ordinary-page horizontal overflow; long Arabic labels remain readable as discrete items.
- **Tablet (`769–1024px`)**: navigation remains deliberately touch-first, horizontally reachable and not compressed below the shared touch contract.
- **Desktop (`>=1025px`)**: preserve efficient report-family scanning and route access; horizontal overflow remains available when the permitted route set exceeds width.
- **RTL/Arabic**: preserve the existing destination order and Arabic copy; use the shared logical-layout contract rather than physical left/right positioning.
- **Accessibility**: named route navigation, real links, visible keyboard focus and active-route state; icons remain decorative; do not introduce ARIA tab semantics for route navigation.

## Explicit exclusions / preserved truth

Do not change in REPORT001:
- `ReportFilterBar`, preset/date normalization, date-range state or any filter/query semantics;
- report page headers/content composition except the common route-nav renderer itself;
- analytics hooks, query/cache behavior, aggregation/calculation/trust logic or business meaning;
- metrics, `MetricCard`, charts, legends, tables, drill-down, loading/empty/error states, export/print actions or child-report redesign;
- `ReportsRedirect`, route definitions, permissions, `AnalyticsGate` behavior or operational-page classification;
- broad `ReportsLayout` CSS/inline-style cleanup;
- backend/RPC/DB/RBAC/RLS/workflow/deployment/preview/`main`.

Report filter convergence remains an explicit later concern. REPORT001 must not make the current report-local filter implementation the canonical system answer.

## Peer-state synthesis

The judgment above was formed from current report/shared-component source and the North Star/component/page-pattern documents before comparing role conclusions.

- **Team Memory:** aligned; it advances REPORT001 and explicitly asks Product Design to bound the smallest report shell/navigation/filter concern.
- **Development Integrator:** aligned and current for lifecycle; WORK003 is merged and the next action is a bounded REPORT001 direction.
- **UI Production Engineer:** lifecycle-stale on completed WORK003; no contradictory design judgment exists. It should now bootstrap only from the latest Development HEAD and implement this single report-nav concern.
- **Design QA:** lifecycle-stale on completed WORK003; no contradictory report judgment exists. Fresh exact-head review is required only after the future REPORT001 PR stabilizes.
- **Previous Director state:** lifecycle-stale after WORK003 integration and superseded by this report direction.
- **Decision Log:** no durable rule changed; existing shared-system-first, functional-isolation and device rules already govern this decision, so no update is warranted.
- **Team Memory:** no overall product/system direction changed; Integrator-owned synchronized memory remains sufficient until the next merge, so no Director mutation is warranted.

No current cross-role `BLOCKING` contradiction exists.

## What changed since previous Director state

- WORK003 is now integrated; the former exact-head PR acceptance state is no longer the active lifecycle position.
- Product Design inspected the current Reports shell, representative report/filter surfaces and the existing shared navigation contract.
- REPORT001 is now concretely bounded from a broad shell/navigation/filter placeholder to one dependency-safe concern: `ReportsLayout` route sub-navigation -> shared `SubNav`.
- Report filter/touch convergence is explicitly preserved as later debt rather than being silently declared solved.
- Workstream direction was updated in governance commit `b97a67b07ac0fc9282920ae5b002c1a24d5a67e9`.
- No product code, peer specialist state, Team Memory, Decision Log, GitHub Actions, Vercel, preview branch, `main`, deployment or merge action was performed.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA and Development Integrator observe until a stable implementation PR exists.
- **What changed:** `DS2-REPORT-001` is concretely READY as `ReportsLayout` route sub-navigation convergence using the existing shared `SubNav` only.
- **Preserve:** exact 14 report destinations/order/Arabic labels/icons; existing permission arrays and caller-owned `can(...)` filtering; route behavior; `/reports/reengagement` + `/reports/visits` operational `AnalyticsGate` bypass; all report date/filter/query/aggregation/calculation/trust/export/print/business truth; unrelated report shell CSS; full report filter/REPORT002/Admin/Global backlog.
- **Need from you:** UI Production Engineer should open exactly one PR from the latest Development HEAD and implement only this bounded navigation concern with focused authored tests. QA should independently review the exact stable PR HEAD afterward; Integrator remains no-op until fresh gates exist.
- **Blocker level:** `NONE`.
- **Baseline:** source inspected at Development `53e10ef8692d330250603f8a10d985003f3ac456`; governance-only Workstream boundary recorded at `b97a67b07ac0fc9282920ae5b002c1a24d5a67e9` immediately before this state write.
