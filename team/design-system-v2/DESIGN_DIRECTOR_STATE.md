# Product Design Director State

## Reviewed baseline

- Review date/time: `2026-09-24 07:02 Africa/Cairo`.
- Authoritative branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-045`.
- Latest product integration: PR #93, squash merge `573753d8d6c50e44d56cbb5c253604e9755118a5`.
- Exact Development HEAD at the start of this Product Design run: `2d4c5e6df3184fc8fdf011568a81aa54065138a1`.
- Workstream boundary commit created this run: `04a47998f7f31f25e72150d2604d49090afe527f`.
- Open implementation PRs targeting Development at slice selection: none.
- Active slice: `DS2-REPORT-046 — Shared chart-tooltip presentation foundation (Receivables proof)`.
- Current state: `READY — BOUNDED`.
- Active implementation PR: none yet.
- Current Product Design disposition: `IMPLEMENTATION AUTHORIZED WITHIN BOUNDED SCOPE`.
- Current contradiction classification: `NONE`.

## Independent Product Design judgment

REPORT046 should establish a shared chart-tooltip presentation grammar and prove it on one representative report chart only: Receivables.

This is a system gap rather than page beautification. The current Development source independently recreates substantially the same `CustomTooltip` surface/anatomy in Receivables, Sales, Treasury, Product Performance and Rep Performance: local background/border/radius/shadow/padding/RTL label-row-value styling wrapped around Recharts payload data. The repeated visual concern belongs in the shared V2 presentation layer, while Recharts payload interpretation, series/domain labels, value formatting, chart data and business truth must remain caller-owned.

The smallest dependency-safe move is therefore one domain-agnostic shared tooltip presentation pattern plus one Receivables adoption. Migrating every duplicate in one PR would over-broaden the slice and reduce our ability to review the shared contract before reuse.

## Bounded architecture

### Shared layer responsibility

The new shared pattern under `src/components/patterns/` may own only:
- tooltip surface and semantic V2 surface/border/elevation usage;
- spacing and row layout;
- RTL-safe label/value anatomy;
- typography and long-content wrapping/containment;
- optional caller-provided series-color presentation.

Preferred API direction is a presentation contract such as a tooltip label plus caller-mapped rows/items. It must remain domain-agnostic and contain no Supabase/query knowledge, report calculations, currency assumptions, trust meaning or Recharts payload interpretation.

Minimum shared styling may be added to `src/styles/design-system-v2-surfaces.css` using existing semantic aliases. No new token or breakpoint should be added unless a source-proven need makes the current slice impossible; that case must be returned as `BLOCKED`, not silently widened.

### Representative consumer

Only `src/pages/reports/ReceivablesPage.tsx` is migrated in REPORT046.

Its existing Recharts adapter/payload interpretation stays caller-owned. The shared pattern should receive already-mapped presentational content while preserving:
- tooltip label behavior;
- series order as provided by Recharts;
- current currency formatting (`fmt(value) + ' ج.م'`);
- explicit LTR numeric/currency value treatment;
- caller-provided series colors.

Sales, Treasury, Product Performance, Rep Performance and all other duplicated tooltips remain unchanged until later explicitly bounded adoption slices.

## Device / state / accessibility acceptance

### Mobile 390
- Tooltip remains legible, RTL-native and width-safe within the viewport.
- Long Arabic labels may wrap rather than truncate or force ordinary horizontal overflow.
- Numeric/currency values preserve caller-owned mixed-direction treatment.

### Tablet 900
- Same shared tooltip grammar remains touch-context safe and readable without introducing a Tablet-specific mini-system.
- No new breakpoint-specific tooltip logic is expected.

### Desktop 1440
- Preserve dense analytical readability and existing chart interaction behavior.
- Shared tooltip styling must not inflate the analytical surface unnecessarily.

### State / interaction
- Tooltip remains informational only: no action, focus target, click target, live region or keyboard-only capability is introduced.
- Receivables keeps exact chart precedence `isBlocked -> dailyLoading -> empty -> ready`.
- Preserve exact 260px loading/empty/ready analytical geometry.
- Preserve the current blocked and empty Arabic copy.
- Preserve chart data mapping/order, margins, axes, tooltip trigger behavior, receipts/refunds/net series, colors, radii and `maxBarSize`.
- Preserve Trust/Freshness and all report/page state semantics.

## Test / evidence requirements

Focused tests should protect the material new contract:
- shared tooltip semantic/anatomy structure and RTL-safe presentation contract;
- long Arabic label/content tolerance where source-level testable;
- Receivables adapter preserves caller-owned label/value/order behavior and currency-direction semantics where practical;
- existing Receivables chart loading/empty/blocked/ready regression coverage remains intact.

Evidence must remain honest under the current quota policy: `TESTS_AUTHORED_NOT_EXECUTED` unless an approved exact-head local environment actually executes them. No hosted CI, runtime visual, preview or release PASS may be inferred from source review.

## Explicit exclusions / stop conditions

REPORT046 must not change:
- Sales, Treasury, Product Performance, Rep Performance or any other chart tooltip consumer;
- chart series/palette/gradients/legend/axis/data/geometry;
- `ChartPanel` API or responsibilities;
- FilterBar, KPI/MetricGrid, tables, ResponsiveCollection or Reports Overview navigation cards;
- query/cache/calculation/date/filter/trust/permission/RBAC/RLS/routing/export/print/backend/business/workflow semantics.

If implementation demonstrates that `ChartPanel` itself must own tooltip data/presentation or that any business/chart semantics need to move into the shared component, mark REPORT046 `BLOCKED` and return to Product Design. Do not widen the slice.

## Peer-state synthesis / contradiction handling

This judgment was formed from the current report source, shared `ChartPanel`, semantic-foundation/surface CSS and the North Star before comparing peer states.

- **Team Memory:** fresh and aligned on integrated truth through REPORT045 and explicitly delegates REPORT046 bounding to Product Design.
- **Development Integrator:** fresh and aligned; REPORT045 is merged and REPORT046 was intentionally `READY — UNBOUNDED` awaiting this action.
- **UI Production Engineer:** Development state is lifecycle-historical for REPORT045; no active REPORT046 implementation or contradictory direction exists.
- **Design QA:** Development state is lifecycle-historical for REPORT045; no active REPORT046 review or contradiction exists.
- **Decision Log / North Star / Device Strategy / Component Decision Matrix:** aligned with shared-system-before-local-invention, UI-only isolation and deliberate multi-device/RTL quality.
- **Open PR check:** no PR currently targets `design-system-v2-development`, so no competing implementation slice exists.

Current contradiction classification: `NONE`.

## Repository actions / what changed this run

- Completed the mandatory shared-memory bootstrap in the required order.
- Inspected issue #27, exact Development HEAD, open PRs targeting Development, relevant Reports source, shared analytical/surface contracts and blueprint/device/component guidance.
- Bounded REPORT046 in `31_AGENT_TEAM_WORKSTREAM.md` as the shared chart-tooltip presentation foundation with Receivables as the sole representative consumer.
- Did not update `TEAM_MEMORY.md`; the overall product/system direction did not change, only the next implementation concern became concrete.
- Did not update `DECISION_LOG.md`; no durable rule changed.
- Did not modify product code or peer role states, merge a PR, touch `main`, deploy Vercel, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer.
- **What changed:** REPORT046 is now `READY — BOUNDED` as a shared domain-agnostic chart-tooltip presentation foundation proved only on the Receivables AR chart.
- **Preserve:** caller-owned Recharts payload interpretation, series/domain labels, value formatting/order/colors and mixed-direction values; Receivables `isBlocked -> dailyLoading -> empty -> ready`; exact 260px chart-state geometry; Trust/Freshness and Arabic state copy; all REPORT001-045 contracts; no other tooltip consumer or business/backend semantics touched.
- **Need from you:** start from the exact latest Development HEAD after this state write; add the smallest shared presentation contract + focused tests, migrate Receivables only, and open one Draft PR targeting Development. If implementation requires `ChartPanel` API widening, new business/chart semantics, new tokens/breakpoints without a source-proven necessity, or another consumer migration, stop and mark `BLOCKED` for Product Design reconsideration.
- **Blocker level:** `NONE`.
- **Baseline:** Development immediately before this owned-state write `04a47998f7f31f25e72150d2604d49090afe527f`; no implementation PR exists yet.
