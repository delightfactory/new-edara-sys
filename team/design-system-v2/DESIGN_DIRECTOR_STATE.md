# Product Design Director State

## Reviewed baseline

- Review date/time: `2026-09-24 09:01 Africa/Cairo`.
- Authoritative branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-046`.
- Latest product integration: PR #94, squash merge `d937088e7ee1e7f6dc6fcb1dccb5bc5e617c86d0`.
- Exact Development HEAD at the start of Product Design decision-making: `21404d94ebc0e42363801f5342d940ad53baf1f6`.
- Workstream boundary commit created this run: `6269879d0a67895ec1005030c8526ddc7fd509ba`.
- Open implementation PRs targeting Development at decision time: none.
- Active single READY slice: `DS2-REPORT-047 — Sales shared chart-tooltip adoption`.
- Status: `READY — BOUNDED`.
- Current contradiction classification: `NONE`.

## Independent Product Design judgment

**REPORT047 should be the Sales adoption of the already-proven shared `ChartTooltip`, with no shared-contract widening.**

The exact current Sales source still carries one page-local `CustomTooltip` presentation implementation that is reused by both Sales analytical charts. Its responsibility is visually equivalent to the new shared `ChartTooltip` proven by REPORT046: neutral tooltip surface, RTL label/value anatomy, series-color rows, compact typography/spacing and mixed-direction values. Keeping the Sales copy now would preserve an unnecessary local mini-system immediately beside a proven shared pattern.

This is the smallest dependency-safe next concern because it validates shared-pattern reuse on a second live report without mixing in a new state contract, chart redesign, table migration or functional semantic change. It also gives stronger system value than another isolated beautification pass: the shared tooltip grammar moves from a single proof consumer toward actual cross-report adoption while all report truth stays caller-owned.

I explicitly did **not** select Treasury empty-state cleanup, Reports Overview interactive navigation-card debt, broader table hardening, or multi-page tooltip migration. Those are valid later concerns, but each introduces a different system responsibility or broader interaction/state surface and should remain separately bounded.

## REPORT047 bounded direction

Representative surface:
- `src/pages/reports/SalesPage.tsx`
- existing page-local `CustomTooltip`
- both ready chart consumers: `تطور الإيراد اليومي` and `توزيع الإيرادات اليومي (إيراد + ضريبة)`

Required system intent:
- retain the existing Sales Recharts adapter and delegate only presentation/anatomy to shared `ChartTooltip`;
- keep `active` / `payload?.length` guard behavior unchanged;
- preserve payload row order and the current caller-owned mapping of `p.name`, `p.color`, `fmt(p.value) + ' ج.م'` and explicit `ltr` value direction;
- preserve existing Recharts `Tooltip content={<CustomTooltip />}` integration shape unless a purely local equivalent refactor is needed for testability;
- do not modify the shared `ChartTooltip` API, CSS, tokens or breakpoints. If the existing shared contract cannot express Sales without widening it, REPORT047 becomes `BLOCKED` rather than broadening scope.

## Device / state / accessibility acceptance

### Mobile 390 / Tablet 900 / Desktop 1440
- same shared RTL tooltip grammar across all canonical device modes;
- viewport containment and long-Arabic wrapping remain inherited from the shared pattern;
- caller-formatted currency values remain explicit LTR/bidi-isolated;
- series identity colors and payload order remain unchanged;
- no device-specific tooltip mini-system or breakpoint is added.

### First Sales chart
Preserve exactly:
- `isBlocked -> dailyLoading -> empty -> ready`;
- 240px caller-owned analytical geometry;
- exact blocked and empty Arabic copy;
- Trust/Freshness action content;
- AreaChart data mapping, margins, grid/axes, gradients, series names/colors/strokes/fills and trigger behavior.

### Second Sales chart
Preserve exactly:
- `dailyLoading -> empty -> ready`;
- 200px caller-owned analytical geometry;
- exact empty Arabic copy;
- BarChart data mapping, margins, grid/axes, revenue/tax series names/colors/radii/`maxBarSize` and trigger behavior;
- no new BLOCKED/trust semantics.

### Accessibility / interaction
- tooltip remains informational and passive;
- no action, click target, focus target, role, tab stop, live region or new keyboard-only interaction is introduced;
- loading/empty/blocked branches must not mount ready chart/tooltip content.

## Explicit exclusions / functional isolation

Out of scope:
- Treasury, Product Performance, Rep Performance or any other tooltip migration;
- shared `ChartTooltip`, `ChartPanel`, `StatePanel`, `MetricGrid`, tokens, CSS or breakpoint changes;
- chart palette, legend, axes, metric, filter, navigation, export or print redesign;
- query/cache/date semantics, calculations, trust logic, permissions, RBAC/RLS, routing, validation, backend/service contracts or business behavior.

## Test-artifact expectation

UI Production should extend the focused Sales tests so the tooltip adapter can be inspected and must protect:
- exact chart label passed through;
- exact payload row order;
- exact series colors;
- exact `fmt(value) + ' ج.م'` output;
- explicit LTR value direction;
- both ready chart consumers at representative 390 / 900 / 1440 widths;
- existing first/second chart state precedence, 240px/200px geometry and ready chart data/series contracts.

Evidence remains subject to `33_TEST_AND_VALIDATION_POLICY.md`; authored-but-unexecuted tests must be labeled `TESTS_AUTHORED_NOT_EXECUTED` and no build/runtime/visual PASS may be inferred without actual approved execution.

## Peer-state synthesis / contradiction handling

The design decision above was formed from the current North Star, component/migration/device guidance, shared `ChartTooltip` contract, exact Sales source/tests and adjacent remaining Reports debt. Peer states were then used to detect contradiction.

- **Team Memory:** current through REPORT046 and explicitly calls out remaining duplicated page-local chart tooltips as bounded adoption debt. Aligned; its REPORT047 placeholder is now superseded by this fresher bounded direction.
- **UI Production Engineer:** lifecycle-historical through REPORT046; no competing REPORT047 implementation exists.
- **Design QA:** lifecycle-historical through REPORT046; no current REPORT047 blocker exists.
- **Development Integrator:** confirms REPORT046 integrated and handed REPORT047 to Product Design for exact bounding. Aligned.
- **Decision Log / North Star / component guidance:** aligned with shared-system-before-page-local invention, Arabic-first responsive quality and strict caller-owned business semantics.

Current contradiction classification: `NONE`.

## Repository actions / what changed this run

- Completed the mandatory shared-memory bootstrap in the prescribed order.
- Inspected issue #27 and its latest coordination event, exact current Development HEAD, open PRs targeting Development, relevant component/page/migration/device guidance, shared `ChartTooltip`, Sales source/tests and representative adjacent Reports tooltip/state debt.
- Confirmed there was no active implementation PR, so no competing slice exists.
- Bounded REPORT047 in `31_AGENT_TEAM_WORKSTREAM.md` as `Sales shared chart-tooltip adoption` in commit `6269879d0a67895ec1005030c8526ddc7fd509ba`.
- Did not update `TEAM_MEMORY.md`; the overall Design System direction and durable system responsibilities did not change.
- Did not update `DECISION_LOG.md`; no long-lived rule changed.
- Did not modify product code or peer role states, merge a PR, touch `main`, deploy Vercel, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer; then Design QA and Product Design for exact-head review after implementation.
- **What changed:** REPORT047 is now `READY — BOUNDED` as Sales adoption of the existing shared `ChartTooltip` for both current Sales charts, with no shared-contract widening.
- **Preserve:** caller-owned Recharts payload interpretation/order/labels/colors/`fmt(value) + ' ج.م'`/LTR value direction; first chart `isBlocked -> dailyLoading -> empty -> ready` and 240px geometry; second chart `dailyLoading -> empty -> ready` and 200px geometry; all existing chart data/axes/margins/series/Trust/Freshness/query/business semantics; all non-Sales tooltip consumers unchanged.
- **Need from you:** start from the exact latest Development HEAD after this state write, implement REPORT047 only, add focused Sales tooltip-adapter/device tests, and open one Draft PR targeting `design-system-v2-development`. If adoption requires changing shared `ChartTooltip` API/CSS/tokens or any functional semantics, mark `BLOCKED` instead of widening scope.
- **Blocker level:** `NONE`.
- **Baseline:** product baseline `21404d94ebc0e42363801f5342d940ad53baf1f6`; workstream boundary `6269879d0a67895ec1005030c8526ddc7fd509ba`.
