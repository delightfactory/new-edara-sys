# Product Design Director State

## Reviewed baseline

- Review date/time: `2026-09-24 13:02 Africa/Cairo`.
- Authoritative branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-047`.
- Latest product integration: PR #95, squash merge `c7af0b151b51d904f658f8d7df3edbc6aaace8e1`.
- Exact Development HEAD before this Product Design state write: `ed34a9cbb8a14acb2598daf71fb152f06f55d750`.
- Open PRs targeting Development at the selection recheck: none.
- Current single READY slice: `DS2-REPORT-048 — Treasury shared chart-tooltip adoption`.
- Status: `READY — BOUNDED`.
- Representative surface: `src/pages/reports/TreasuryPage.tsx` → the page-local Recharts `CustomTooltip` used by the single daily cashflow chart.
- Current contradiction classification: `NONE`.
- No implementation/review evidence is claimed yet for REPORT048; implementation has not started.

## Independent Product Design judgment

The smallest dependency-safe next system move is to migrate Treasury's remaining page-local chart-tooltip presentation onto the already-proven shared `ChartTooltip` without changing the shared contract.

This is a system-convergence slice, not page beautification. Treasury currently duplicates the same tooltip surface/anatomy that was already extracted and proven on Receivables and adopted by Sales: neutral surface, border/elevation, RTL label/value layout and caller-provided series colors. The shared component already has the correct responsibility boundary: presentation only. Treasury can therefore consume it without moving Recharts payload interpretation, labels/order, formatting, series identity, chart state or business/trust truth into the Design System.

I inspected adjacent remaining report tooltip debt in Product Performance and Rep Performance as well. They remain valid future adoption candidates, but moving Treasury first is safer and smaller: one chart, one local tooltip, a mature existing Treasury test suite, and no need to widen the shared API. Broad multi-page tooltip migration would violate the one-slice rule.

## REPORT048 acceptance boundary

### System-pattern intent
- Reuse existing shared `ChartTooltip` unchanged.
- Treasury continues to own `active` / `payload?.length` gating, payload row order, `p.name`, `p.color`, exact `${fmt(p.value)} ج.م` formatting, explicit LTR value direction, Recharts trigger wiring and all analytical/business/trust semantics.
- Remove only the duplicated local presentation surface/anatomy.

### Device / RTL / accessibility acceptance
- Mobile `390px`, Tablet `900px`, Desktop `1440px`: same shared RTL-native tooltip grammar; no device-specific fork.
- Long Arabic labels remain contained and wrappable without ordinary viewport overflow.
- Currency values remain caller-formatted and explicitly LTR/bidi-isolated.
- Tooltip remains passive/informational: no action, focus target, tab stop, role or live region.

### State / analytical integrity to preserve
- Exact precedence: `isBlocked -> dailyLoading -> empty -> ready`.
- Exact 280px chart geometry.
- Exact blocked title/copy and empty Arabic copy.
- Existing TrustStateBadge/FreshnessIndicator context and `ChartPanel` hierarchy.
- Existing chart mapping: `treasury_date -> date`, `gross_inflow -> inflow`, `gross_outflow -> outflow`, `net_cashflow -> net`.
- Existing `ResponsiveContainer` width, chart margins, grid, axes, zero `ReferenceLine`, gradients and all three Area series names/colors/strokes/fills remain unchanged.
- Existing semantic-contract `AlertPanel`, summary `MetricGrid`, header/filter and SystemHealthBar remain unchanged.

### Focused test expectation
Extend the existing Treasury page coverage so it protects:
- tooltip inactive/empty-payload guard;
- exact heading label, payload row order, caller series colors, `ج.م` formatting and LTR value direction;
- ready tooltip adoption at representative 390 / 900 / 1440 widths;
- existing blocked/loading/empty/ready isolation;
- existing 280px geometry, data mapping, margins, axes/reference-line and series/gradient contracts.

Inline color assertions must use browser/CSSOM-normalized values, consistent with the shared `ChartTooltip.test.tsx` contract and the REPORT047 repair lesson.

### Explicit exclusions
- No change to shared `ChartTooltip` API, CSS, tokens or breakpoints.
- No `ChartPanel`, `StatePanel`, `AlertPanel`, `MetricGrid`, filter/header or broader report-foundation change.
- No Product Performance or Rep Performance tooltip migration in REPORT048.
- No chart palette/legend/axis/data mapping redesign.
- No query/cache/calculation/trust/permission/RBAC/RLS/routing/export/print/validation/backend/business semantic change.

If implementation proves that Treasury requires a shared-contract widening or functional semantic change, REPORT048 becomes `BLOCKED` rather than expanding scope silently.

## Peer-state synthesis / contradiction handling

This direction was formed from the North Star, exact Development source, shared `ChartTooltip` contract/tests, Treasury source/tests, device/component decision guidance and remaining Reports debt before peer-state conclusions were used as corroboration.

- **Team Memory / Development Integrator:** aligned that REPORT047 is merged and REPORT048 is the single next roadmap item awaiting Product Design bounding.
- **UI Production Engineer:** its owned state is lifecycle-stale from REPORT047 and must not be reused as authorization; no REPORT048 implementation PR exists.
- **Design QA:** its owned state is lifecycle-stale from REPORT047; no current contradiction applies to REPORT048.
- **Integration State:** current and confirms REPORT047 DONE with REPORT048 delegated to Product Design for one bounded concern.
- **Open PR check:** no PR currently targets `design-system-v2-development`, so creating exactly one REPORT048 implementation slice will not compete with active work.
- **Decision Log / component guidance / device strategy:** aligned with shared-system-before-page-local invention, presentation-only primitives, Arabic-first multi-device behavior and strict functional isolation.

Current contradiction classification: `NONE`.

## Repository actions / what changed this run

- Completed the mandatory shared-memory bootstrap in the prescribed order.
- Inspected issue #27 including the latest REPORT047 integration event, exact Development HEAD, all open PRs targeting Development, current Workstream, component/device/migration guidance and representative remaining Reports surfaces.
- Inspected exact current Treasury tooltip/chart source and its focused regression tests, plus the integrated shared `ChartTooltip` implementation/test contract and adjacent Product/Rep tooltip debt.
- Bounded REPORT048 to one presentation-only Treasury chart-tooltip adoption concern and updated `31_AGENT_TEAM_WORKSTREAM.md` accordingly.
- Updated only this owned Product Design state among specialist states.
- Did not update `TEAM_MEMORY.md` or `DECISION_LOG.md` because no overall Design System direction or durable rule changed.
- Did not modify product code or peer role states, merge a PR, touch `main`, deploy Vercel, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer.
- **What changed:** REPORT048 is now `READY — BOUNDED` as `Treasury shared chart-tooltip adoption`, limited to replacing Treasury's local tooltip presentation with the existing shared `ChartTooltip` while preserving all caller-owned chart/domain semantics.
- **Preserve:** shared `ChartTooltip` API/CSS/tokens unchanged; Treasury payload guard/order/labels/colors/`${fmt(value)} ج.م`/LTR direction; exact `isBlocked -> dailyLoading -> empty -> ready`; 280px geometry; blocked/empty Arabic copy; Trust/Freshness; chart mapping/margins/axes/reference-line/gradients/series; AlertPanel/MetricGrid/filter/header/SystemHealthBar; all query/permission/backend/business contracts.
- **Need from you:** start from the exact latest Development HEAD after this governance update, implement REPORT048 only, extend focused Treasury tests including CSSOM-normalized color expectations, and open one Draft PR targeting `design-system-v2-development`. If shared-contract widening or functional changes appear necessary, stop and mark `BLOCKED`.
- **Blocker level:** `NONE`.
- **Baseline:** exact Development pre-state-write HEAD `ed34a9cbb8a14acb2598daf71fb152f06f55d750`; no active PR.