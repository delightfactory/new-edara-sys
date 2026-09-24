# Product Design Director State

## Reviewed baseline

- Review date/time: `2026-09-24 21:02 Africa/Cairo`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD immediately before this state write: `69e7c6e654d116b41ff6817c0069221c44b31db3`.
- Product UI integrated through `DS2-REPORT-050`; latest product merge remains `22983eff7ce4d11113c2b10de5468bb33bb86936` from PR #98.
- Current single slice: `DS2-REPORT-051 — Churn Risk shared chart-tooltip adoption`.
- State: `READY — BOUNDED`.
- Workstream boundary commit: `a5fe116aa3bda27b0ddc71cb60c4b1cf458d7122`.
- Active implementation PR targeting Development: none.
- Product Design disposition: `READY — NO DESIGN-SYSTEM BLOCKER`.
- Current contradiction classification: `NONE`.

## Independent Product Design judgment

I reviewed the exact latest Churn Risk source/tests, the integrated shared `ChartTooltip` source/tests/CSS, REPORT046 foundation scope, current Reports convergence and the North Star before comparing peer states.

REPORT051 is the correct smallest next system-level slice. Churn Risk's `توزيع تصنيف العملاء` already uses shared report patterns, but its Pie chart still uses Recharts' default tooltip renderer. That leaves a library-default presentation island inside an otherwise converged analytics surface.

The existing shared `ChartTooltip` can serve this consumer unchanged. It owns only neutral surface, spacing, RTL-safe structure and long-content containment; Churn Risk must retain chart payload interpretation and all domain meaning.

## Locked REPORT051 boundary

Representative surface:
- `src/pages/reports/ChurnRiskPage.tsx` → `توزيع تصنيف العملاء`.

Implement only:
- replace the default Recharts tooltip presentation with existing shared `ChartTooltip`;
- keep a local Churn Risk adapter for `active`/payload gating and payload interpretation;
- keep caller ownership of category heading, exact row label `عملاء`, existing `FMT` count formatting, pie-series color and explicit LTR value direction.

Preserve exactly:
- chart presence rule `!statsLoading && pieData.length > 0`; do not add loading/empty chart UI;
- `ResponsiveContainer width="100%" height={260}`;
- exact Pie data/order, `dataKey="value"`, `nameKey="name"`, center/radii/padding;
- colors `#f59e0b`, `#10b981`, `#3b82f6`, `#f97316`, `#ef4444`;
- current Legend, ChartPanel title and Trust/Freshness action behavior;
- header filters, KPI summary, responsive detail collection/table/cards and all query/trust/business semantics.

Device/accessibility:
- Mobile 390 / Tablet 900 / Desktop 1440 use one shared RTL passive tooltip grammar;
- long Arabic remains contained/wrappable;
- numeric counts remain LTR/bidi-safe;
- no focus target, tab stop, `role`, `aria-live` or action/keyboard contract is added.

Focused tests:
- inactive / empty-payload adapter guards;
- exact category heading + one-row `عملاء` label + existing count formatting + caller color;
- CSSOM-normalized representative color `#f59e0b -> rgb(245, 158, 11)`;
- shared tooltip at 390 / 900 / 1440 and long-Arabic/passive anatomy;
- no chart/tooltip leakage during stats loading or zero pie data;
- unchanged 260px geometry, pie contracts, colors, Legend and Trust/Freshness behavior.

Explicit exclusions:
- any other report tooltip;
- shared `ChartTooltip` implementation/API/tests/CSS/tokens/breakpoints;
- other shared-pattern changes;
- Churn Risk filters/KPIs/detail collection/export/print/navigation;
- any hook/query/cache/RPC/Supabase/calculation/trust/permission/RBAC/RLS/routing/validation/backend/business change.

If exact adoption requires widening the shared tooltip contract or changing functional semantics, REPORT051 is `BLOCKED`.

## Peer-state synthesis

- UI Production state still documents integrated REPORT050; lifecycle-stale but not contradictory.
- Design QA state is consumed REPORT050 evidence; no REPORT051 QA exists yet.
- Integration state correctly hands REPORT051 to Product Design for bounding; that handoff is now satisfied.
- TEAM_MEMORY was stale as REPORT051 unbounded. It is now synchronized with the bounded Workstream in commit `69e7c6e654d116b41ff6817c0069221c44b31db3`.
- Decision Log / North Star / test policy remain aligned; no durable decision changed.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in order.
- Inspected issue #27, current Development state and open PRs; no implementation PR is open.
- Verified Development was exactly `a5fe116aa3bda27b0ddc71cb60c4b1cf458d7122` before Team Memory sync.
- Re-inspected Churn Risk source/tests and the shared tooltip contract/CSS.
- Kept the Workstream unchanged because its REPORT051 boundary is already correct.
- Updated Team Memory only to remove the material stale unbounded direction.
- Did not modify Product code, Decision Log, `main`, Vercel, preview branches, workflows or GitHub Actions.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA after a stable PR HEAD.
- **What changed:** REPORT051 is fully bounded as Churn Risk Pie-chart adoption of the existing presentation-only shared `ChartTooltip`, and shared memory is synchronized.
- **Preserve:** ready-only chart presence, 260px geometry, exact Pie data/order/keys/radii/padding/colors, Legend, Trust/Freshness behavior, caller-owned category/`عملاء`/FMT/color/LTR semantics, all header/KPI/detail composition and all functional contracts; shared `ChartTooltip` remains unchanged.
- **Need from you:** start from the exact latest Development HEAD, implement REPORT051 only, add focused adapter/device/state/chart tests, and open one Draft PR targeting `design-system-v2-development`. Mark `BLOCKED` if shared-contract widening is required.
- **Blocker level:** `NONE`.
- **Baseline:** pre-state-write Development HEAD `69e7c6e654d116b41ff6817c0069221c44b31db3`; Workstream boundary `a5fe116aa3bda27b0ddc71cb60c4b1cf458d7122`.
