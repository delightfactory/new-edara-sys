# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-19`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD independently inspected before REPORT006 governance write: `19eed8c9f1c8794cf309ed67c40084c085345004`.
- REPORT005 is integrated: PR `#52`, reviewed HEAD `eec9f05772babd40be61803b39d90bd9b859b28d`, squash merge `3776e7defc83a1376a571dd38256c6a7bbf87e17`.
- Open PRs targeting Development at final pre-state recheck: none.
- Current single READY slice: `DS2-REPORT-006 — Product Performance responsive detail-collection convergence`.
- Representative surface: `src/pages/reports/ProductPerformancePage.tsx`, section `تفاصيل المنتجات — أعلى 50 حسب الإيراد` only.
- Workstream boundary commit created this run: `2ca3a41fd02067f4230924145e1773d9c7a650e1`.
- Current Product Design disposition: `READY — IMPLEMENTATION AUTHORIZED WITHIN BOUNDED PRESENTATION-ONLY SCOPE`.

## What changed since the previous state

REPORT005 completed its lifecycle and is now integrated. Integration explicitly handed REPORT006 back to Product Design for exact-source bounding before any implementation.

This run inspected the current report surfaces and the existing shared responsive grammar. `ProductPerformancePage` contains a real dense seven-column product-detail table that is currently the same table composition at every device width, with horizontal overflow as the only narrow-screen adaptation. The repository already has a shared `ResponsiveCollection` contract designed to mount exactly one deliberate Desktop/Tablet/Mobile renderer at a time, plus current V2 `Card` and `KeyValueList` building blocks for labeled detail composition.

That makes the Product Performance detail section the smallest useful REPORT006 proof: one collection, one page, no query or business change, and a direct system-level improvement to responsive dense-data presentation rather than another page-local beautification pass.

## Independent Product Design judgment

**READY — IMPLEMENTATION AUTHORIZED only for the bounded REPORT006 concern recorded below.**

I formed the boundary from exact current source and shared-component contracts before comparing peer states. No implementation PR exists, so there is no competing active slice.

The design decision is deliberately not to create a generic DataTable V2 in this slice and not to adopt the legacy `DataCard`. REPORT006 should prove the already-existing shared responsive-composition contract first, using current V2 primitives, before the broader DataTable/MobileDataCard component-depth backlog is opened.

## REPORT006 implementation boundary

### System intent

Use shared `ResponsiveCollection<ProductPerformanceRow>` for the existing `تفاصيل المنتجات — أعلى 50 حسب الإيراد` collection so one data capability receives deliberate device composition:

- **Desktop renderer:** preserve the current semantic seven-column table and its dense information hierarchy.
- **Tablet renderer:** use the same detail-card composition as Mobile rather than compressing seven table columns or relying on page-level horizontal scrolling.
- **Mobile renderer:** stacked detail cards composed from existing V2 `Card` + `KeyValueList` building blocks.
- Only one renderer may be mounted at a time; no CSS-hidden duplicate Desktop/Mobile DOM.

No new generic table/card abstraction is authorized by this slice.

### Content / business-truth preservation

Preserve exactly:
- section title `تفاصيل المنتجات — أعلى 50 حسب الإيراد`;
- row source, row order and current top-50 result contract;
- the seven existing data fields and Desktop order: `المنتج`, `التصنيف`, `الإيراد`, `الكمية`, `نسبة المرتجع`, `عملاء`, `الحصة%`;
- `ProductPerformanceRow` values and current `fmt` / `fmtCur` / `fmtPct` formatting meaning;
- currency/unit copy;
- return-rate semantic thresholds/colors: `>10` danger, `>5` warning, otherwise success;
- current five-row skeleton loading presentation;
- exact empty copy `لا توجد بيانات`;
- all existing trust/freshness ownership and every upstream report calculation/query/filter/date/category contract.

For Tablet/Mobile the information hierarchy should be:
- product name = primary identity;
- category = secondary context;
- revenue, quantity, return rate, customers and share = explicitly labeled `KeyValueList` details.

All seven source fields therefore remain represented; the narrow-screen composition changes hierarchy, not meaning.

### Device / RTL / long Arabic acceptance

- **Desktop:** native table remains the dense high-information surface. Preserve contained overflow behavior and add `scope="col"` to touched column headers so table semantics stay explicit.
- **Tablet:** deliberate detail-card layout, no page horizontal overflow, readable multi-column metadata where space permits.
- **Mobile:** one-column stacked cards, no table-width dependency or horizontal page overflow, product identity immediately readable before numeric detail.
- Arabic product/category text must remain legible under long-content stress; do not introduce essential-text clipping merely to preserve a one-line card.
- Numeric values may retain LTR numeric direction while Arabic labels/content remain RTL-first.
- Dark mode must inherit semantic V2 Card/KeyValue/status tokens; no report-local light-only surface/color patch is allowed.

### Accessibility / state acceptance

- Desktop remains a true `<table>` with `<thead>`, `<tbody>` and column headers.
- Tablet/Mobile use explicit labels for every quantitative value through `KeyValueList`.
- Return-rate state is never color-only because the percentage text remains visible with the semantic color.
- Do not invent clickable-card semantics or row navigation: the current rows have no row action.
- Preserve one caller-owned loading state and one caller-owned empty state by passing explicit `loadingState` / `emptyState` to `ResponsiveCollection`; do not silently change skeleton count or empty copy to the pattern defaults.
- Focus/touch behavior must not regress, but this slice introduces no new action control.

### Explicit exclusions

Do not:
- create or broaden a generic DataTable V2;
- create a new MobileDataCard abstraction;
- adopt legacy `DataCard` for this proof;
- migrate the Product Performance chart, metric cards/grid, category selector, page header or `ReportFilterBar`;
- touch any second report/table;
- change sorting/order, pagination/result count, filters, hooks, Supabase/RPC/service/query-cache contracts, calculations, trust/freshness semantics, permissions, routing, `AnalyticsGate`, export/print or business truth;
- perform generic report CSS cleanup.

If implementation discovers that the desired result requires functional semantics to change or a broader generic-table contract, stop and mark REPORT006 `BLOCKED` for Product Design re-bounding rather than expanding the PR.

### Evidence expected from UI Production

Author focused tests that demonstrate:
- Desktop renders the preserved table field contract;
- Mobile mounts only the detail-card renderer;
- Tablet deliberately follows the detail-card composition;
- preserved custom loading and empty branches remain single and unchanged;
- no hidden duplicate renderer DOM exists.

Hosted CI remains forbidden; evidence labels must remain honest per `33_TEST_AND_VALIDATION_POLICY.md`.

## Peer-state synthesis / contradiction handling

- **Development Integrator:** current and aligned. REPORT005 is recorded `MERGED_GREEN_DEV_REPORT005`, and its handoff explicitly asks Product Design to bound REPORT006 before implementation. That request is now satisfied.
- **UI Production Engineer / Design QA:** no active REPORT006 PR exists at the final recheck, so any REPORT005 lifecycle wording in specialist states is stale context rather than a material contradiction.
- **Workstream:** updated this run so REPORT006 is no longer a placeholder owned by Product Design; it now records the exact Product Performance surface, acceptance boundary and UI Production as next owner.
- **North Star / Decision Log:** aligned. This slice applies existing durable rules: shared-system-first, deliberate device composition, Arabic/RTL quality, semantic accessibility and caller-owned business truth. No new durable rule was created.

There is **no current BLOCKING cross-role contradiction** and exactly one implementation slice is READY.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the required order.
- Inspected issue #27, exact current Development HEAD, open PRs targeting Development and relevant component/page/migration guidance.
- Inspected representative report consumers and exact `ProductPerformancePage` table source.
- Inspected shared `ResponsiveCollection`, its focused tests, current V2 `Card` and `KeyValueList`; also checked legacy `DataCard` and intentionally excluded it from this proof.
- Updated `31_AGENT_TEAM_WORKSTREAM.md` in commit `2ca3a41fd02067f4230924145e1773d9c7a650e1` with the exact REPORT006 scope and implementation authorization.
- Did not update Team Memory or Decision Log because overall system direction and durable rules did not change.
- Did not implement product code, modify peer specialist states, merge any PR, touch `main`, trigger/rerun GitHub Actions, use hosted CI, deploy Vercel or modify preview branches.

### Cross-role handoff
- **To:** UI Production Engineer.
- **What changed:** REPORT006 is now fully bounded and implementation-authorized on the Product Performance detail collection only; Workstream commit `2ca3a41fd02067f4230924145e1773d9c7a650e1` replaces the prior placeholder boundary.
- **Preserve:** exact `تفاصيل المنتجات — أعلى 50 حسب الإيراد` title; seven fields and Desktop order; row source/order/count; all formatters/units; return-rate thresholds/colors; five-row loading skeleton; exact `لا توجد بيانات`; every query/filter/date/category/calculation/trust/permission/routing/`AnalyticsGate`/export/print/business contract; no second report surface.
- **Need from you:** branch from the latest `design-system-v2-development`, open one REPORT006 implementation PR, migrate only this collection to shared `ResponsiveCollection` with Desktop semantic table plus Tablet/Mobile V2 `Card + KeyValueList` detail composition, author focused contract tests, and stop rather than broadening scope if functional semantics or a generic DataTable abstraction becomes necessary.
- **Blocker level:** `NONE`.
- **Baseline:** exact independently inspected pre-governance Development HEAD `19eed8c9f1c8794cf309ed67c40084c085345004`; REPORT006 boundary commit `2ca3a41fd02067f4230924145e1773d9c7a650e1`.
