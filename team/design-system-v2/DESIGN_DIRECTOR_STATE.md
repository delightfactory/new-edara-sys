# Product Design Director State

## Reviewed baseline

- Review date/time: `2026-09-23 08:07 Africa/Cairo`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD rechecked after bounding the Workstream and before this state write: `95f312f9491607f9829d8234dbe615bdc5cad362`.
- Product/source baseline inspected before the governance-only Workstream write: `6ee7ed93a913ed74d0da0e7b2423cbf615dd99f9`.
- Current integrated product baseline remains through `DS2-REPORT-033`, squash merge `464adbfe86f9ff1e53d288babb9715a010346b15` from PR #81.
- Active slice: `DS2-REPORT-034 — Churn Risk KPI summary shared metric convergence`.
- Active implementation PR: none at selection/bounding time; open PRs targeting Development were empty.
- Current slice disposition: `READY — BOUNDED` for UI Production.
- Representative surface: `src/pages/reports/ChurnRiskPage.tsx` → five-card risk-classification KPI summary only.

## Independent Product Design judgment

**REPORT034 should converge the remaining Churn Risk five-card KPI summary onto existing `MetricGrid columns={3}` + `StatCard`, without widening the shared contracts or touching Churn Risk classification/business truth.**

I formed this judgment from the exact Development source and existing shared `MetricGrid` / `StatCard` / semantic-tone contracts before comparing peer states.

Churn Risk is already substantially converged: its filter controls use shared `Select` + `DateField`, its pie visualization uses shared `ChartPanel`, and its customer detail uses shared `ResponsiveCollection + Card + KeyValueList`. The remaining KPI strip is therefore an isolated local mini-system: a page-local responsive grid plus five hand-styled cards with arbitrary per-category border/value colors. This is the smallest safe presentation gap that materially advances system coherence without opening a second report surface or changing analytics semantics.

The existing shared contracts are sufficient. `MetricGrid` owns only responsive metric layout and supports `columns={3}`; `StatCard` owns neutral KPI hierarchy and semantic emphasis only. No five-column shared mode is justified: five metrics should intentionally compose as `3 + 2` on Desktop, `2 + 2 + 1` on Tablet, and one column on Mobile.

## Bounded system contract

### Scope — exactly one summary surface

Replace only the Churn Risk KPI summary presentation:
- current loading `report-grid` wrapper → existing `MetricGrid columns={3}`;
- current ready-state local CSS grid → the same `MetricGrid columns={3}`;
- each local hand-built KPI card → existing `StatCard`.

Preserve exact metric order:
1. `VIP`
2. `مخلص`
3. `متفاعل`
4. `معرض للخطر`
5. `خامد`

Preserve exact caller-owned values:
- `stats.vip`
- `stats.loyal`
- `stats.engaged`
- `stats.at_risk`
- `stats.dormant`

Preserve existing integer formatting through `FMT.format(...)` and the `—` fallback. Do not move the key-to-stat mapping or any RFM classification rule into the Design System.

### Semantic emphasis

Use only shared semantic tones; do not create page-specific StatCard variants or pass arbitrary category colors into the shared primitive:
- `VIP` → `neutral`
- `مخلص` → `success`
- `متفاعل` → `info`
- `معرض للخطر` → `warning`
- `خامد` → `danger`

Rationale: these tones communicate operational meaning through the shared vocabulary while visible labels remain the primary category identity. `VIP` is a segment, not intrinsically a warning/success state, so it remains neutral. The page may continue to use its existing category colors in `RiskBadge` and the pie chart because those are explicitly outside this bounded KPI migration.

### Device acceptance

- **Desktop >=1025px:** five passive metrics render through `MetricGrid columns={3}` as `3 + 2`, preserving order and avoiding a new five-column contract.
- **Tablet 769–1024px:** canonical shared two-column composition `2 + 2 + 1`; touch-first layout remains deliberate.
- **Mobile <=768px:** canonical shared one-column metric stack; no ordinary horizontal overflow.
- Arabic labels and large numeric values must rely on the existing shrink/wrap-safe shared contracts; no page-local width hacks.

### State / accessibility acceptance

- Preserve the exact `statsLoading` gate.
- Loading must render exactly five `SkeletonCard` placeholders at `height={120}` inside the shared MetricGrid; do not substitute a new loading meaning or alter chart/detail state precedence.
- Ready cards remain passive/non-interactive; no new click, focus, hover-only or pseudo-control behavior.
- Category identity remains visible as text, so semantic meaning is not color-only.
- No new heading level, ARIA role or interaction state is introduced by this slice.

## Explicit exclusions / preservation boundary

REPORT034 must not modify:
- page title/description/header layout;
- risk-classification `Select`, as-of `DateField`, or filter/date semantics;
- `SystemHealthBar`;
- `RISK_CONFIG` category identity, `RiskBadge`, `RecencyCell`, or RFM classification rules;
- pie `ChartPanel`, chart visibility/data/order/colors/geometry/tooltip/legend, or Trust/Freshness action wiring;
- customer-detail `ResponsiveCollection`, Desktop table, Tablet/Mobile cards, ordering, loading/blocked/empty copy or renderer semantics;
- hooks, queries, snapshots, calculations, cache semantics, permissions, RBAC/RLS, routing, export/print, backend or business behavior;
- shared `MetricGrid`, `StatCard`, Card/Status APIs, CSS, tokens or breakpoints;
- any other report/page.

If implementation discovers that any excluded shared or functional change is required, REPORT034 becomes `BLOCKED` instead of expanding the PR.

## Focused evidence expectation

UI Production should author focused source-level tests that guard the actual migration risks:
- both loading and ready summary states are under `.ds-metric-grid[data-columns="3"]`;
- five shared `StatCard` surfaces appear in the exact risk order;
- semantic `data-tone` mapping is exactly `neutral / success / info / warning / danger` in that order;
- rendered values preserve the existing source/format/fallback contract;
- loading renders exactly five 120px skeletons and no ready StatCards.

Existing Churn Risk tests already protect shared filter wiring, pie-chart composition and responsive detail behavior; do not broaden this slice into rewriting those test families. Evidence remains `TESTS_AUTHORED_NOT_EXECUTED` unless an approved runtime actually executes the exact future PR HEAD.

## Peer-state synthesis / contradiction handling

After forming the independent design judgment:

- **Development Integrator:** fresh and aligned. REPORT033 is merged and Integrator explicitly handed REPORT034 to Product Design for one smallest dependency-safe presentation concern.
- **Team Memory:** fresh through REPORT033 and aligned; it names REPORT034 as the sole unbounded READY roadmap item and preserves remaining Reports, shared-component depth, Work/Field, Settings/Admin and Global debt.
- **UI Production Engineer:** lifecycle-stale from the now-integrated REPORT033 branch state; no conflicting rule/blocker. It must bootstrap again from the new Development HEAD before REPORT034 implementation.
- **Design QA:** lifecycle-stale from REPORT033 exact-head review; no conflicting rule/blocker. Fresh exact-head QA is required for the future REPORT034 PR.
- **Decision Log / North Star / component matrix / device strategy:** aligned with shared-system-before-local-invention, semantic variants rather than arbitrary page colors, Arabic-first multi-device composition and strict UI-only functional isolation.

Current contradiction classification: `NONE`.

## Why adjacent candidates were not selected

- Customer Re-engagement still contains a large local export drawer/overlay, but that slice would mix overlay, export and interaction concerns and carries a larger regression surface than this KPI-only convergence.
- Overview retains a local report-navigation card grid with arbitrary accent colors, but it needs a clearer shared navigation-card/action contract rather than forcing an existing metric primitive onto a different responsibility.
- Sales and several other representative report surfaces are already using shared `MetricGrid` / `ChartPanel` grammar correctly.

Therefore Churn Risk KPI summary is the smallest dependency-safe next move that reduces a real duplicate visual implementation with an already-proven shared pattern.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the prescribed order.
- Inspected issue #27, the exact current Development branch, open PRs targeting Development, and representative remaining Reports surfaces.
- Verified no implementation PR was open when selecting REPORT034.
- Inspected `ChurnRiskPage.tsx`, its focused page tests, existing `MetricGrid`, `StatCard`, semantic tone contract and relevant component/page/device/migration blueprints.
- Bounded REPORT034 in `31_AGENT_TEAM_WORKSTREAM.md` at commit `95f312f9491607f9829d8234dbe615bdc5cad362`.
- Did not modify product code, peer state files, Team Memory or Decision Log.
- Did not merge, deploy, touch `main`, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer; then Design QA and Product Design for future exact-head review.
- **What changed:** REPORT034 is now `READY — BOUNDED` as Churn Risk's five-card KPI summary convergence onto existing `MetricGrid columns={3}` + `StatCard` only.
- **Preserve:** exact metric order/labels/stat sources/FMT/fallback, exact `statsLoading` gate and 5×120px skeletons, all filter/RFM/chart/detail/trust/query/permission/export/backend semantics, and unchanged shared component/API/CSS/token/breakpoint contracts.
- **Need from you:** start from the latest Development HEAD, implement only this bounded summary migration, author the focused metric-grid/StatCard/order/tone/loading tests, and open exactly one PR targeting `design-system-v2-development`. Mark `BLOCKED` rather than widen scope if shared or functional changes become necessary.
- **Blocker level:** `NONE`.
- **Baseline:** exact Development pre-state-write HEAD `95f312f9491607f9829d8234dbe615bdc5cad362`; product/source selection baseline `6ee7ed93a913ed74d0da0e7b2423cbf615dd99f9`.