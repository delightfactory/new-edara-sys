# Product Design Director State

## Reviewed baseline

- Review date/time: `2026-09-24 15:03 Africa/Cairo`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD at the start of architectural inspection: `f95c072df7b945e37de833910b36ee8a64572e72`.
- Exact Development HEAD after Workstream bounding and before this owned-state write: `3d7d1f7ec2f4114292f6cc98f0d766bee06c664e`.
- Integrated product baseline: through `DS2-REPORT-048`, squash merge `9eb5489a00631f1cc7b9377893e7b0a1ebb560d6`.
- Active slice: `DS2-REPORT-049 — Product Performance shared chart-tooltip adoption`.
- Slice status: `READY — BOUNDED`.
- Representative surface: `src/pages/reports/ProductPerformancePage.tsx` → local Recharts `CustomTooltip` for “أعلى 15 منتجاً بالإيراد”.
- Active implementation PR: none at decision time.
- Current Product Design disposition: `READY — BOUNDED / IMPLEMENTATION AUTHORIZED WITHIN THE DECLARED PRESENTATION-ONLY BOUNDARY`.
- Current contradiction classification: `NONE`.

## Independent Product Design judgment

REPORT049 should continue the proven shared chart-tooltip grammar on Product Performance, not begin a new report redesign. The exact current Product Performance source still recreates a page-local tooltip surface/anatomy that is structurally equivalent to the shared `ChartTooltip` already proven by Receivables and adopted by Sales and Treasury.

I formed this judgment from the current Development source before using peer states as corroboration. Product Performance has one local Recharts `CustomTooltip` with:
- `!active || !payload?.length` gating;
- caller-owned Recharts payload iteration/order;
- `p.name` labels;
- `p.color` series identity;
- exact `${fmt(p.value)} ج.م` values;
- explicit LTR numeric/currency direction;
- a page-local neutral surface, spacing, typography, shadow and RTL anatomy now duplicated by the shared presentation primitive.

The smallest dependency-safe next step is therefore to remove only that duplicated presentation layer and retain a Product Performance-local Recharts adapter. This advances system coherence without widening the Design System contract or touching analytical/business semantics.

## REPORT049 bounded contract

### System intent

Use existing `src/components/patterns/ChartTooltip.tsx` unchanged. The shared pattern continues to own only tooltip presentation/anatomy. Product Performance continues to own chart-library interpretation, labels/order, series color, formatting/direction, chart data/configuration, trust and business meaning.

### Must preserve

- existing adapter guard: `!active || !payload?.length`;
- exact tooltip heading `label`;
- payload row order and `p.name` labels;
- caller series color from `p.color`;
- exact `${fmt(p.value)} ج.م` formatting and explicit LTR value direction;
- existing Recharts `<Tooltip content={...} />` wiring;
- exact chart state order `tableLoading -> empty -> ready`;
- loading/empty branches must not mount ready chart/tooltip content;
- exact 240px analytical height and `ResponsiveContainer width="100%"` containment;
- `rows.slice(0, 15)` data selection;
- existing 20-character product-name visual truncation in chart data;
- chart margins, Cartesian grid, X/Y axes, tick formatting/rotation/alignment;
- one revenue Bar with data key `revenue`, name `الإيراد`, fill `#2563eb`, radius `[3, 3, 0, 0]`, `maxBarSize={32}`;
- current ChartPanel title/description, TrustStateBadge/FreshnessIndicator presence rule and all report copy;
- all current summary metrics and responsive product-detail collection behavior.

### Device / Arabic / accessibility acceptance

- Mobile `390px`, Tablet `900px`, Desktop `1440px`: same shared RTL tooltip grammar with no device-specific fork or breakpoint change.
- Long Arabic tooltip labels must wrap/contain without ordinary viewport overflow.
- Monetary values remain bidi-safe and explicitly LTR.
- Tooltip remains informational only: no action, focus target, tab stop, role or live-region semantics.

### Required test artifacts

Product Performance focused tests should cover:
- inactive and empty-payload adapter guards;
- exact heading, row label/order, color, `ج.م` formatting and `dir="ltr"` value contract;
- CSSOM-normalized series-color expectation for `#2563eb` as `rgb(37, 99, 235)`, avoiding the stale raw-HEX assertion class already caught in REPORT047;
- shared-tooltip ready wiring at 390 / 900 / 1440;
- no tooltip leakage into loading/empty chart states;
- unchanged 240px geometry, data mapping, margins, grid/axes and revenue Bar contract.

Evidence must remain honestly labeled under the test policy; authored tests are not execution evidence.

### Explicit exclusions

- `RepPerformancePage` or any other report tooltip consumer.
- Any shared `ChartTooltip` API/CSS/token/breakpoint change.
- `ChartPanel`, `StatePanel`, `ResponsiveCollection`, `MetricGrid`, `Card`, `KeyValueList` or other shared-pattern changes.
- Product Performance raw category `<select>` / Field convergence, `ReportFilterBar`, page header, summary metrics, detail table/cards, return-rate semantics, export/print or navigation.
- Any hook/query/cache/RPC/Supabase, calculation, trust, permission, RBAC/RLS, route, validation, backend or business-semantic change.

If the existing shared tooltip cannot satisfy Product Performance within these exclusions, REPORT049 becomes `BLOCKED`; implementation must not silently widen the slice.

## System-coherence rationale

This is not page-by-page beautification. It is the next bounded adoption of an already-proven domain-agnostic presentation primitive. Product Performance is a strong proof target because its local tooltip duplicates the shared anatomy almost exactly while its chart domain semantics remain simple and fully caller-owned. Migrating it now reduces visual implementation divergence with very low functional risk, while leaving the more complex two-series Rep Performance tooltip as a separately bounded future adoption.

The page also contains other design debt—most visibly the locally styled category `<select>` and remaining report header/filter/detail-table composition—but combining those concerns would violate one-slice discipline and blur evidence. They remain future bounded work.

## Peer-state synthesis / contradiction handling

After forming the independent judgment, I compared current peer states and repository memory:

- **Development Integrator:** current and aligned. REPORT048 is merged and it explicitly handed REPORT049 to Product Design for exact-current-baseline bounding.
- **Team Memory:** aligned on roadmap intent and invariants, but lifecycle-stale after this decision because it still labels REPORT049 `READY — UNBOUNDED`. This is not a design contradiction. I did not rewrite Team Memory because the overall Design System direction did not materially change; the Workstream and this owned state now carry the bounded current-slice truth.
- **UI Production Engineer:** lifecycle-stale from merged REPORT048. Its tooltip responsibility boundary remains compatible with REPORT049, but it provides no authorization/evidence for this new slice.
- **Design QA:** lifecycle-stale from merged REPORT048. Its REPORT048 approval is consumed and cannot be reused for REPORT049.
- **Decision Log / North Star / component and device guidance:** aligned with shared-system-before-page-local invention, Arabic-first responsive behavior, caller-owned business truth and strict UI-only functional isolation.
- **Issue #27:** latest event confirms REPORT048 integration and REPORT049 awaiting Product Design bounding; this run advances that event stream.

Current contradiction classification: `NONE`.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the required order.
- Inspected issue #27, exact current Development HEAD, open PRs targeting Development, current Product Performance and Rep Performance implementations, Product Performance tests, shared `ChartTooltip` implementation/tests, and relevant component/page/migration/device/decision guidance.
- Confirmed there was no active implementation PR targeting `design-system-v2-development` before bounding REPORT049.
- Updated `31_AGENT_TEAM_WORKSTREAM.md` only to replace REPORT049's unbounded placeholder with this exact bounded concern, acceptance criteria and explicit exclusions.
- Updated only this owned specialist state after the Workstream decision.
- Did not modify product code, peer role-state files, Team Memory or Decision Log.
- Did not merge, touch `main`, deploy Vercel, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

## What changed since previous state

- REPORT048 lifecycle is now integrated and consumed.
- REPORT049 moved from `READY — UNBOUNDED` to `READY — BOUNDED` as Product Performance shared chart-tooltip adoption.
- No durable Design System rule changed; this is adoption of the existing presentation-only tooltip contract.

### Cross-role handoff
- **To:** UI Production Engineer; then Design QA and Product Design Director for fresh exact-head review after implementation.
- **What changed:** REPORT049 is now exactly bounded to Product Performance's one local chart-tooltip presentation migration onto the existing shared `ChartTooltip`; implementation is authorized within this presentation-only boundary.
- **Preserve:** shared `ChartTooltip` unchanged; Product Performance `active`/payload guard, label/order/`p.name`/`p.color`/`${fmt(value)} ج.م`/LTR semantics; `tableLoading -> empty -> ready`; 240px chart; current chart data/truncation/margins/grid/axes/revenue Bar; Trust/Freshness; current summary/detail responsive composition; all query/permission/backend/business contracts.
- **Need from you:** UI Production should bootstrap from the exact latest Development HEAD after this state write, implement REPORT049 only, add focused adapter/device/state/chart tests using CSSOM-normalized RGB expectations, and open one Draft PR targeting Development. Any need to widen the shared tooltip contract or alter functional semantics must be reported as `BLOCKED`.
- **Blocker level:** `NONE`.
- **Baseline:** Development pre-state-write `3d7d1f7ec2f4114292f6cc98f0d766bee06c664e`; no implementation PR exists yet.
