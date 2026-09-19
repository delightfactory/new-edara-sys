# Design QA State

## Reviewed baseline

- Review date: `2026-09-19`.
- Development branch: `design-system-v2-development`.
- Exact Development HEAD independently inspected before this state write: `efa2e959ab994da3b81a9c28d937cf7acc570da7`.
- Active slice: `DS2-REPORT-005 — Shared ChartPanel foundation + Sales primary revenue-chart migration`.
- Representative surface: `src/pages/reports/SalesPage.tsx`, first chart `تطور الإيراد اليومي`.
- Active implementation PR: `#52 — DS2-REPORT-005: converge Sales revenue chart panel`.
- Feature-branch base: `efa2e959ab994da3b81a9c28d937cf7acc570da7` on `design-system-v2-development`.
- Exact PR HEAD independently reviewed: `7d63904e50197e76167205c6d6f52af4d2884257`.
- PR state at review: `OPEN / DRAFT / mergeable=true`.
- Changed-file scope: 6 files — shared `ChartPanel`, focused `ChartPanel` test, Sales page, focused Sales test, shared surfaces CSS, and UI Production Engineer owned state.
- Current disposition: `AGENT-REVIEW: BLOCKED`.
- Severity: `P2 / BLOCKING`.
- Evidence: `TESTS_AUTHORED_NOT_EXECUTED`; `SOURCE_REVIEW_PASS` withheld.
- Exact-head build/test/lint/runtime/preview PASS: not claimed.

## Independent QA disposition

**BLOCKED on exact PR HEAD `7d63904e50197e76167205c6d6f52af4d2884257`.**

The implementation is otherwise well bounded and functionally isolated, but it violates the explicit semantic hierarchy acceptance contract for REPORT005. The new shared `ChartPanel` defaults to `headingLevel = 3`, the Sales consumer does not override it, and both focused tests intentionally lock the chart title as `h3`. Product Design explicitly requires the chart title to be semantic `h2` beneath the existing page `h1`.

Because this is a new shared pattern, accepting the wrong default would turn a local hierarchy mistake into reusable Design System grammar. That is a material system-fit/accessibility issue, not a cosmetic preference.

## Exact-head findings

### Scope / functional isolation — PASS

The exact PR diff contains only:
- `src/components/patterns/ChartPanel.tsx`
- `src/components/patterns/ChartPanel.test.tsx`
- `src/pages/reports/SalesPage.tsx`
- `src/pages/reports/SalesPage.test.tsx`
- `src/styles/design-system-v2-surfaces.css`
- `team/design-system-v2/UI_IMPLEMENTATION_STATE.md`

The product change migrates only the first Sales revenue-chart shell onto a shared V2 composition. `useSystemTrustState`, `useTrustForComponent`, `useSalesDailyTotals`, `useSalesSummary`, date/filter semantics, `chartData`, blocked predicate, currency formatting, Recharts data/series/axes/gradients/tooltip/dimensions and trust/freshness props remain unchanged. The second bar chart remains untouched.

No DB/migration/RPC/service/query-cache/RBAC/RLS/permission/route-guard/business-calculation/validation/workflow/export/print/deployment contract changed.

### Shared-system fit — BLOCKED on heading hierarchy

`ChartPanel` correctly composes approved shared `Card + SectionHeader`, keeps chart data/state/business meaning caller-owned, and adds only neutral body spacing/containment. This is the right architectural direction and avoids a Reports-local mini design system.

However:
- `src/components/patterns/ChartPanel.tsx` sets `headingLevel = 3` by default;
- `src/pages/reports/SalesPage.tsx` does not pass an override;
- the page already has `h1` (`إيرادات المبيعات`), so the migrated chart title renders as `h3` with no intervening `h2` in this section path;
- `SectionHeader` itself defaults to `h2`, while the new shared wrapper unnecessarily overrides that established semantic default;
- Product Design's REPORT005 acceptance explicitly requires `تطور الإيراد اليومي` to become semantic `h2` beneath the page `h1`.

Minimum fix: make this Sales chart resolve to `h2` on the next HEAD. Preferred shared fix is to default `ChartPanel` to `headingLevel = 2`, retaining the explicit prop for genuinely nested chart panels. Update focused tests to assert `h2`. Do not widen the slice or alter chart/business semantics.

### Device / RTL / density / containment — PASS at source level

- Shared `Card` provides `min-width: 0`, semantic surfaces and standard padding.
- `.ds-chart-panel__body` adds logical `margin-block-start` plus `min-width: 0`.
- Existing 240px `ResponsiveContainer` is unchanged.
- Mobile shared `SectionHeader` wrapping remains available at `<=768px`; action content keeps caller ownership and can wrap internally.
- Arabic title/description are unchanged and no physical LTR-only positioning is introduced.
- Desktop analytical density remains full-width; no Reports-local breakpoint or overflow workaround was added.

No `RUNTIME_VISUAL_PASS` is claimed.

### Relevant states — PASS for preserved semantics

The first chart's existing blocked, loading, empty and data-present decision tree remains caller-owned and structurally unchanged inside `ChartPanel`. The blocked copy remains non-color-only. Existing trust/freshness content remains separate from the heading. No new interactive control or focus behavior was introduced.

### Test Artifact Gate / evidence honesty — PASS for presence, BLOCKED for asserted hierarchy

Focused tests exist and evidence is honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`.

Coverage currently verifies shared Card/SectionHeader composition, title/description/action/body slots, first-chart-only adoption, preserved trust/freshness and empty/blocked states. However, both `ChartPanel.test.tsx` and `SalesPage.test.tsx` explicitly assert heading level `3`, so the tests currently protect the wrong hierarchy contract and must be updated with the implementation fix.

Design QA did not execute tests, build, lint, runtime inspection or preview. GitHub Actions/hosted CI and Vercel were not used. No execution PASS is claimed.

## Peer-state comparison / contradiction handling

This judgment was formed from the exact PR diff, exact Development baseline, shared `Card`/`SectionHeader`/surface contracts, Sales source and focused tests before comparing peer conclusions.

- **Product Design Director:** target, scope and shared-pattern direction align with the implementation, but its acceptance requires semantic `h2` beneath the page `h1`.
- **UI Production Engineer:** records `h3` as the intended accessibility outcome and authored tests to lock `h3`. This directly contradicts Product Design's explicit hierarchy acceptance. Classification: **`BLOCKING`**.
- **Development Integrator / Team Memory:** lifecycle-stale from completed REPORT004 for this new PR; no competing REPORT005 approval exists. Integration remains `NO_MERGE` while this blocker is current.
- **Source-shape note:** the baseline really did use a raw inline shell/header, so converging that raw source into shared `Card + SectionHeader` is valid and not itself a QA blocker.

## System-fit judgment

REPORT005 is directionally strong: it establishes a reusable, presentation-only chart frame without importing report/recharts/business semantics and proves it on one representative consumer. The current heading default is the only material blocker found, but it must be corrected before GREEN-DEV because it would otherwise institutionalize an incorrect semantic hierarchy in a new shared pattern.

### Cross-role handoff
- **To:** UI Production Engineer for repair; Product Design Director and Design QA after a stable repaired HEAD; Development Integrator remains `NO_MERGE`.
- **What changed:** Design QA independently reviewed PR #52 exact HEAD `7d63904e50197e76167205c6d6f52af4d2884257` and blocked it on the shared `ChartPanel`/Sales `h3` hierarchy mismatch.
- **Preserve:** one-chart-only scope; shared `Card + SectionHeader` composition; exact Arabic title/description; caller-owned trust/freshness; blocked/loading/empty/data tree; existing 240px chart body; all Recharts series/data/axes/gradient/tooltip semantics; second chart and every other Reports surface out of scope; all query/filter/calculation/permission/routing/business truth unchanged.
- **Need from you:** make the migrated chart semantic `h2` (preferably by restoring the shared `ChartPanel` default to `2`), update focused tests to assert `h2`, keep all other scope unchanged, then request fresh exact-head QA/Product Design review.
- **Blocker level:** `BLOCKING`.
- **Baseline:** Development `efa2e959ab994da3b81a9c28d937cf7acc570da7`; reviewed PR #52 HEAD `7d63904e50197e76167205c6d6f52af4d2884257`.
- **Evidence:** `TESTS_AUTHORED_NOT_EXECUTED`; `SOURCE_REVIEW_PASS` withheld; no executed build/test/lint/runtime/preview/release PASS claimed.
