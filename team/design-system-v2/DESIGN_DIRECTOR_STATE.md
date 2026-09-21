# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-21`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD independently inspected before the REPORT015 workstream boundary write: `be80864789784177cb29feb95c1398d2d518dedc`.
- REPORT015 workstream boundary commit: `c1eb05419dc89d3b2fde065b06dd924142b86f41`.
- Current integrated product baseline: `DS2-REPORT-014` / PR #62, squash merge `a7096cdc86fb9fa55205556a10c8a5c13a6235d4`.
- Current single READY slice: `DS2-REPORT-015 — Geography responsive detail-collection convergence`.
- Representative surface: `src/pages/reports/GeographyPage.tsx` → `التوزيع حسب {LEVEL_LABELS[level]}` collection only.
- Active implementation PR: none at boundary selection; open PR query targeting `design-system-v2-development` returned none.
- Product Design disposition: `READY — IMPLEMENTATION AUTHORIZED WITH BOUNDED PRESENTATION-ONLY SCOPE`.

## Independent Product Design judgment

REPORT015 should advance the responsive report grammar rather than add another low-value chart-shell repetition. The Geography detail surface is a clear remaining system gap: Desktop currently has a useful dense comparative heatmap table, but Tablet/Mobile inherit the same horizontally-scrollable table with no deliberate operational composition.

The existing `ResponsiveCollection + Card + KeyValueList` contract is already proven across Product Performance, Customer Health and Churn Risk. Geography is a strong fourth proof because its row shape is different and includes level-dependent parent context plus heatmap-style Desktop emphasis, yet all required business truth already exists in caller-owned `GeographyRow[]` data. No new shared primitive, API or business rule is required.

The correct system direction is therefore:
- keep Desktop dense and comparative, including the current heatmap/zero-row treatment;
- use deliberate touch-first cards on Tablet/Mobile from the same rows;
- represent all current geography facts without horizontal scrolling;
- keep the existing level selector/filter, Trust/Freshness, loading/empty copy and data semantics unchanged;
- add only the semantic Desktop header improvement `scope="col"` within the selected collection.

This is a bounded presentation migration, not a Geography redesign.

## REPORT015 acceptance boundary

### System-pattern intent

Use the existing shared `ResponsiveCollection` orchestration so exactly one device renderer mounts at a time. Tablet/Mobile cards should use existing neutral `Card` plus compact `KeyValueList`; no shared API/CSS widening is authorized.

### Preserve exactly

- `useGeographyTable(filters)` and existing caller-owned row order.
- `geo_id`, `geo_name`, `parent_name`, `net_revenue`, `customer_count`, `transaction_count`, `revenue_share_pct` truth.
- Existing `governorate | city | area` controlled state and filter shape from REPORT007.
- Existing table outer shell/header, dynamic `التوزيع حسب {LEVEL_LABELS[level]}` heading, Trust/Freshness presence/props.
- `tableLoading` precedence, exact five `SkeletonCard height={44}` loading composition and exact empty copy `لا توجد بيانات — شغّل watermark sweep أولاً`.
- Desktop conditional parent column only when `level !== 'governorate'` with `parent_name ?? '—'` fallback.
- Desktop heatmap calculation based on current `maxRev`, `isZero`, opacity and row background behavior.
- Existing money/count/share formatting, numeric direction, ordering and zero values.

### Device composition

- **Desktop:** retain the current dense table/heatmap and current column order; add `scope="col"` to semantic column headers only.
- **Tablet:** use touch-first Geography cards with `geo_name` as identity and compact two-column `KeyValueList` for conditional parent, net revenue, customers, transactions and revenue share.
- **Mobile:** use the same card anatomy with one-column compact `KeyValueList`; long Arabic geography/parent names must wrap without ordinary horizontal overflow.
- **All devices:** one renderer mounted only; no CSS-hidden duplicate interaction/data tree.

### Accessibility / RTL / dark-mode intent

- Desktop headers are semantic column headers.
- Cards remain non-interactive; no fabricated click/navigation semantics.
- Arabic names/supporting labels wrap naturally; current numeric LTR treatment remains where applicable.
- Reuse semantic shared Card/KeyValueList surfaces; no new page-local palette or LTR-first assumptions.
- Do not create a new hover/touch/keyboard dependency.

### Explicit exclusions

Do not touch:
- page header;
- analysis-level `Select`;
- `ReportFilterBar`;
- KPI `report-grid` / `MetricCard`;
- `SystemHealthBar`;
- outer collection shell/header or Trust/Freshness behavior;
- any second report page;
- `ResponsiveCollection`, `Card` or `KeyValueList` shared APIs/CSS unless Product Design explicitly re-bounds after a demonstrated blocker;
- hooks, queries, cache behavior, geography aggregation/calculations, ranking/order, permissions/RBAC/RLS, routes, export/print, backend, deployment or business semantics.

If implementation requires functional/data-semantic change or shared-contract widening, REPORT015 becomes `BLOCKED` rather than expanding the PR.

## Focused test-artifact expectation

Tests should protect the actual migration risk:
- Desktop exact dynamic columns/labels/order, `scope="col"`, row facts and absence of card renderer;
- Mobile only one-column card renderer with all current source fields and conditional parent behavior;
- Tablet only two-column card renderer with the same row truth;
- loading and exact empty-copy precedence suppress ready renderers;
- existing REPORT007 level-control/filter semantics remain intact and only the already-defined parent-field presence changes with level.

Evidence remains subject to `33_TEST_AND_VALIDATION_POLICY.md`; authored tests are not execution evidence.

## Peer-state synthesis / contradiction status

Independent judgment above was formed from the exact latest Geography source, current responsive shared components, prior migrated report consumers and blueprint/device guidance before peer-state comparison.

- **Team Memory:** current on REPORT014 integration and explicitly delegates REPORT015 bounding to Product Design; aligned.
- **Development Integrator:** current and aligned; REPORT014 is merged and exactly one roadmap placeholder REPORT015 was handed to Product Design.
- **UI Production:** lifecycle-stale at the pre-merge REPORT014 implementation state; not contradictory. It must bootstrap fresh from the post-boundary Development HEAD before REPORT015 product code.
- **Design QA:** lifecycle-stale at REPORT014 exact-head review; not contradictory. Fresh REPORT015 exact-head review will be required after implementation.
- **Previous Product Design state:** lifecycle-stale at REPORT014 acceptance and superseded by this state.
- **Decision Log / North Star:** aligned with UI-only isolation, shared-system-before-page-local invention, Arabic-first responsive composition and one-renderer-per-device direction.

Current contradiction classification: **NONE**.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in prescribed order.
- Inspected issue #27, current Development HEAD, open PRs targeting Development, relevant report source/tests, shared `ResponsiveCollection`, `Card`, `KeyValueList`, and component/page/device blueprint guidance.
- Confirmed no active implementation PR targeted `design-system-v2-development` before selecting REPORT015.
- Bounded exactly one dependency-safe slice: Geography responsive detail-collection convergence.
- Updated `31_AGENT_TEAM_WORKSTREAM.md` in commit `c1eb05419dc89d3b2fde065b06dd924142b86f41`.
- Did not modify product code, peer-owned specialist states, Team Memory or Decision Log.
- Did not merge, touch `main`, trigger/rerun GitHub Actions, use hosted CI, deploy Vercel or modify preview branches.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA after implementation.
- **What changed:** REPORT015 is now source-accurately bounded and implementation-authorized as Geography responsive detail-collection convergence on `src/pages/reports/GeographyPage.tsx` only.
- **Preserve:** existing level/filter truth; `GeographyRow[]` fields/order; outer shell/header/Trust/Freshness; `tableLoading` and exact five-row skeletons; exact empty copy; Desktop heatmap/zero-row/conditional-parent/numeric semantics; no shared API/CSS widening; no query/calculation/permission/routing/export/print/business changes.
- **Need from you:** UI Production should start from the latest Development HEAD after this state write, open exactly one REPORT015 PR, implement Desktop table + Tablet/Mobile shared-card composition with one renderer per device, and author focused tests for device/state/field parity. If a shared-contract or semantic blocker appears, stop and mark `BLOCKED` rather than broadening scope. Design QA then independently reviews the exact stable PR HEAD.
- **Blocker level:** `NONE`.
- **Baseline:** REPORT015 boundary commit `c1eb05419dc89d3b2fde065b06dd924142b86f41`; this state write advances Development once more and its resulting commit is the authoritative feature baseline unless superseded by later non-overlapping governance drift.