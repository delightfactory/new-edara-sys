# Product Design Director State

## Reviewed baseline

- Review date/time: `2026-09-23 23:03 Africa/Cairo`.
- Authoritative branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-041`.
- Latest product integration: PR #89, squash merge `b334b07e93b7551839772d6a5cbbdb53089df06b`.
- Exact Development HEAD before Product Design bounding: `fbe23d0511cafd61ccb453347c04a554f512fb9f`.
- Workstream boundary commit: `3320c81d1ae07b05378f8c630cfbf64e218b4d73`.
- Current slice: `DS2-REPORT-042 — Sales revenue/tax bar-chart empty-state convergence`.
- Current slice state: `READY — BOUNDED`.
- Active implementation PR: none.
- Current contradiction classification: `NONE`.

## Independent Product Design judgment

**REPORT042 should be the second Sales analytical chart's no-data branch only.**

I formed this judgment from the exact current `SalesPage.tsx`, focused Sales test artifact, shared `StatePanel` and `ChartPanel` contracts, the component decision matrix, migration matrix and device strategy before relying on peer lifecycle conclusions.

The second `ChartPanel` (`توزيع الإيرادات اليومي (إيراد + ضريبة)`) currently has only `dailyLoading -> ready BarChart`. When the date-scoped `chartData` is empty it still mounts an empty Recharts canvas, while the immediately adjacent first Sales chart now uses the established shared compact passive empty-state grammar. That is a real system-coherence gap and the smallest dependency-safe remaining concern: no new primitive, no cross-page redesign, no data/business change and no shared-contract widening are required.

The correct convergence is therefore presentation-only: retain caller-owned 200px analytical geometry and state truth, add an explicit no-data branch using the existing compact passive `StatePanel kind="empty"`, and leave the BarChart contract untouched when data exists.

## REPORT042 bounded design direction

### Representative surface

`src/pages/reports/SalesPage.tsx` → second `ChartPanel` titled `توزيع الإيرادات اليومي (إيراد + ضريبة)` → no-data branch only.

### System-pattern intent

- `ChartPanel` continues to own only analytical surface hierarchy.
- `StatePanel` continues to own only shared passive state presentation/anatomy.
- `SalesPage` continues to own data truth, loading precedence, fixed body geometry and BarChart semantics.
- The slice removes an implicit blank-chart no-data state instead of inventing a page-local mini-system.
- Shared APIs/CSS/tokens/breakpoints remain unchanged.

### Required implementation behavior

- Preserve second-chart precedence as `dailyLoading -> empty -> ready`.
- Do **not** add `isBlocked`, `BLOCKED`, `FAILED`, trust gating or Trust/Freshness UI to the second chart.
- When `dailyLoading` is false and `chartData.length === 0`, render the existing shared compact passive `StatePanel kind="empty"` inside a caller-owned 200px wrapper.
- Exact empty copy: `لا توجد بيانات في النطاق الزمني المحدد`.
- Preserve `SkeletonCard height={200}` exactly.
- Preserve ready `ResponsiveContainer width="100%" height={200}` and the existing BarChart data, margin, axes/grid/tooltip, revenue/tax bars, fills, radii and `maxBarSize` exactly.
- Preserve the first Sales chart completely, including its `isBlocked -> dailyLoading -> empty -> ready` precedence, BLOCKED copy/meaning, 240px geometry, Trust/Freshness and AreaChart contract.
- Preserve Sales summary metrics, filter/date behavior, SystemHealthBar, formatting and hooks.

### Device / RTL / accessibility acceptance

- At representative Mobile 390, Tablet 900 and Desktop 1440 widths, empty state remains one compact shared panel inside the preserved 200px analytical body.
- No fixed-width or new ordinary horizontal-overflow source; Arabic empty copy must wrap naturally.
- Empty state is passive: no action slot, click handler, button/link, explicit focus target or live announcement.
- Loading mounts only the 200px skeleton; empty and ready renderers do not mount.
- Empty mounts no ready BarChart; ready mounts no shared empty panel.
- Focused tests should protect 200px empty geometry, shared passive anatomy, representative device widths and the unchanged ready BarChart contract.
- Evidence must remain `TESTS_AUTHORED_NOT_EXECUTED` unless an approved exact-head execution environment actually runs the tests/build.

### Explicit exclusions

- no change to the first Sales chart;
- no new trust/BLOCKED semantics for the second chart;
- no chart-title/description/action redesign;
- no chart data mapping, tax/revenue meaning, color/series/axis/tooltip change;
- no `StatePanel` / `ChartPanel` implementation, CSS, token or breakpoint change;
- no query/cache/aggregation/calculation/trust/permission/RBAC/RLS/routing/export/print/backend/business/workflow change;
- no neighboring report-page cleanup in this PR.

If implementation reveals that satisfying the second chart requires new trust/business semantics or a shared-contract change, REPORT042 becomes `BLOCKED` rather than widening scope.

## Selection rationale against broader debt

- REPORT041 explicitly left the second Sales chart's no-data behavior untouched, so REPORT042 closes the adjacent proven pattern gap with minimal regression surface.
- Broader remaining report debt such as FilterBar/search decomposition, dense-table overflow, export/print grammar and other page-level convergence is materially wider and should remain separately bounded.
- The slice advances the North Star's state-completeness and semantic-consistency requirements without page-by-page decorative redesign.

## Peer-state synthesis / contradiction handling

After the independent judgment:

- **Development Integrator:** fresh through REPORT041 and explicitly delegated REPORT042 bounding to Product Design; aligned.
- **Team Memory:** integrated truth through REPORT041 is current, but its `REPORT042 READY — UNBOUNDED` placeholder is now lifecycle-stale because the Workstream contains the bounded concern; all durable invariants remain aligned. No overall system direction changed, so Team Memory is not rewritten by Product Design this run.
- **UI Production:** Development copy still reflects the completed REPORT041 implementation lifecycle; no competing active PR or REPORT042 code exists.
- **Design QA:** Development copy reflects REPORT041 exact-head review; consumed by integration and not reusable for REPORT042.
- **Decision Log / North Star / component/migration/device docs:** aligned; no durable decision changed.
- **Open PRs targeting Development:** none at selection time, so there is no overlapping implementation slice.

Current contradiction classification: `NONE`.

## What changed since the previous state

- REPORT041 is now integrated; prior Product Design acceptance was consumed by that merge.
- Inspected the exact latest Development baseline and remaining Sales analytical composition.
- Bounded exactly one next implementation slice: `DS2-REPORT-042 — Sales revenue/tax bar-chart empty-state convergence`.
- Updated the Workstream only for the new scope/acceptance/exclusion boundary.
- Did not modify product code, peer role states, Team Memory or Decision Log.
- Did not merge, touch `main`, deploy Vercel, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer; then Design QA after a stable Draft PR exists.
- **What changed:** REPORT042 is now `READY — BOUNDED` to the second Sales revenue/tax BarChart no-data branch only, using the existing compact passive shared `StatePanel` inside preserved 200px caller-owned geometry.
- **Preserve:** second-chart `dailyLoading -> empty -> ready` only; no new trust/BLOCKED semantics; exact empty copy `لا توجد بيانات في النطاق الزمني المحدد`; 200px loading/empty/ready geometry; unchanged ready BarChart data/margins/axes/tooltip/revenue+tax series; first Sales chart entirely unchanged; all excluded query/calculation/permission/export/backend/business/shared contracts.
- **Need from you:** start from the exact latest `design-system-v2-development` HEAD, implement REPORT042 only, author focused tests for Mobile/Tablet/Desktop empty/loading/ready contracts, and open one Draft PR targeting Development. Mark BLOCKED instead of widening scope if new business/trust semantics or shared-contract changes are required.
- **Blocker level:** `NONE`.
- **Baseline:** Product Design selection baseline `fbe23d0511cafd61ccb453347c04a554f512fb9f`; Workstream boundary commit `3320c81d1ae07b05378f8c630cfbf64e218b4d73`.
