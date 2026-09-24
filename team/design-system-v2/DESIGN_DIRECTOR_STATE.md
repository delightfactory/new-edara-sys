# Product Design Director State

## Reviewed baseline

- Review date/time: `2026-09-24 16:59 Africa/Cairo`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD at the start of Product Design inspection: `0980f86c44564ab35a4453464e5711a1a0e0915c`.
- Exact Development HEAD before this owned-state write: `c41f7b1789862eb21394fa222561627482c707e4`.
- Integrated product baseline: through `DS2-REPORT-049`, squash merge `055aa6587ff2f08e9e89cbf604c15d58b46c86ff` from PR #97.
- Active slice: `DS2-REPORT-050 — Rep Performance shared chart-tooltip adoption`.
- Slice status: `READY — BOUNDED`.
- Active implementation PR: none.
- Current contradiction classification: `NONE`.

## Independent Product Design judgment

I formed the next-slice judgment from the exact latest Development source before using peer states as corroboration.

The smallest dependency-safe Reports concern now is Rep Performance's remaining page-local Recharts `CustomTooltip` in `src/pages/reports/RepPerformancePage.tsx`. The local implementation duplicates the same neutral surface, RTL anatomy, spacing, caller color and LTR monetary-value presentation already proven as shared `ChartTooltip` grammar in Receivables and adopted by Sales, Treasury and Product Performance.

This is therefore a system-convergence slice, not page beautification: remove one duplicate presentation mini-system while keeping chart-library/domain/business truth at the caller boundary. No new shared capability is required by the inspected source. The existing `ChartTooltip` contract is sufficient and must remain unchanged.

## REPORT050 bounded contract

### Representative surface

`src/pages/reports/RepPerformancePage.tsx` — only the local `CustomTooltip` used by the `مقارنة المندوبين — أعلى 15` chart.

### Shared/caller responsibility boundary

Shared `ChartTooltip` owns only:
- neutral tooltip surface and spacing;
- RTL-safe structure and long-content containment;
- passive informational label/row/value presentation.

Rep Performance must continue to own:
- Recharts `active` / payload gating;
- caller heading/label;
- payload row order;
- `p.name` and `p.color`;
- exact `${fmt(p.value)} ج.م` formatting;
- explicit LTR value direction;
- Recharts trigger wiring;
- all analytical, trust and business meaning.

### Device / state / accessibility acceptance

- Mobile 390 / Tablet 900 / Desktop 1440 use the same shared RTL tooltip grammar; no breakpoint or device-specific fork is added.
- Long Arabic heading/series labels remain wrap-safe without ordinary viewport overflow; monetary values remain LTR.
- Tooltip stays passive/informational with no action, focus target, tab stop, `role`, `aria-live` or new keyboard contract.
- Preserve chart state precedence exactly as `tableLoading -> empty -> ready`.
- Preserve the 300px loading skeleton and 300px compact empty-state containment/copy.
- Preserve ready geometry `ResponsiveContainer width="100%" height={Math.max(chartData.length * 40, 200)}`.

### Exact chart truth to preserve

- `rows.slice(0, 15)` and mapping `{ name: rep_name, revenue: net_revenue, returns: returns_value }`.
- Vertical `BarChart` layout and margins `{ top: 4, left: 10, right: 20, bottom: 0 }`.
- Existing Cartesian grid, numeric X-axis formatter, Y-axis `dataKey="name"`, width 120 and current tick/axis behavior.
- Revenue Bar remains first with current Arabic name, `#2563eb`, radius `[0,3,3,0]`, `maxBarSize={20}`.
- Returns Bar remains second with current Arabic name, `#dc2626`, radius `[0,3,3,0]`, `maxBarSize={10}`.
- TrustStateBadge/FreshnessIndicator presence rule and all summary/detail composition remain unchanged.

### Focused test expectations

`src/pages/reports/RepPerformancePage.test.tsx` should add/adjust focused source tests for:
- inactive / empty-payload adapter guards;
- shared tooltip heading, exact row order/labels, exact currency formatting and LTR value direction;
- browser/CSSOM-normalized caller colors: `#2563eb -> rgb(37, 99, 235)` and `#dc2626 -> rgb(220, 38, 38)`;
- representative ready wiring at 390 / 900 / 1440;
- no tooltip leakage into loading/empty branches;
- preserved top-15 mapping, dynamic height, margins/grid/axes and both Bar contracts.

Evidence remains `TESTS_AUTHORED_NOT_EXECUTED` unless an approved local runtime actually executes the tests.

## Explicit exclusions / stop condition

REPORT050 must not change:
- shared `ChartTooltip` implementation/API/tests/CSS, semantic tokens or breakpoints;
- `ChartPanel`, `MetricGrid`, `StatePanel`, `ResponsiveCollection`, `Card`, `KeyValueList` or other shared patterns;
- page header, `ReportFilterBar`, summary metrics, detail table/cards/responsive orchestration, rank/return-rate styling or trust semantics;
- another report or tooltip consumer;
- hooks/query/cache/RPC/Supabase, calculations, permissions, RBAC/RLS, routing, validation, export/print, backend, workflow or business semantics.

If Rep Performance cannot adopt existing `ChartTooltip` unchanged, or any functional/report semantic change becomes necessary, REPORT050 becomes `BLOCKED` rather than expanding scope.

## Peer-state synthesis

- `TEAM_MEMORY.md` is current through REPORT049 and explicitly hands REPORT050 bounding to Product Design; aligned.
- Prior `DESIGN_DIRECTOR_STATE.md`, `UI_IMPLEMENTATION_STATE.md` and `DESIGN_QA_STATE.md` are lifecycle-stale from REPORT049; their retained responsibility boundaries are compatible but they are not current approval evidence for REPORT050.
- `INTEGRATION_STATE.md` is current through REPORT049 and correctly records REPORT050 as the single unbounded next roadmap item; this run supplies the missing boundary.
- Decision Log and North Star remain aligned: shared system before page-local invention, Arabic-first multi-device behavior and strict UI-only functional isolation.
- No material peer-state contradiction exists. No Team Memory or Decision Log update is warranted because no overall design/system direction or durable rule changed.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the required order.
- Inspected issue #27, current Development HEAD, open PRs targeting Development, relevant component/migration/device guidance, shared `ChartTooltip` contract/tests, Product Performance proof adoption, and current Rep Performance source/tests.
- Rechecked immediately before bounding that no implementation PR targeted `design-system-v2-development`.
- Updated `31_AGENT_TEAM_WORKSTREAM.md` to make REPORT050 exactly one `READY — BOUNDED` implementation slice.
- Updated only this owned specialist state after that material design action.
- Did not modify Team Memory or Decision Log.
- Did not implement Product code, merge, touch `main`, deploy Vercel, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

## What changed since previous state

- REPORT049 is now integrated and the previous Product Design review state is consumed/stale.
- REPORT050 moved from `READY — UNBOUNDED` to `READY — BOUNDED` as Rep Performance shared chart-tooltip adoption.
- The shared `ChartTooltip` responsibility boundary itself did not change.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA after a stable Draft PR exists.
- **What changed:** REPORT050 is now implementation-ready as one bounded Rep Performance tooltip-presentation adoption using the existing shared `ChartTooltip` unchanged.
- **Preserve:** caller-owned `active`/payload guard, heading/order/`p.name`/`p.color`/`${fmt(p.value)} ج.م`/LTR semantics; exact `tableLoading -> empty -> ready`; 300px loading/empty containment; top-15 mapping; dynamic ready height; vertical chart margins/grid/axes; exact revenue/returns Bar order/colors/radii/max sizes; Trust/Freshness; all summary/detail/query/permission/backend/business contracts.
- **Need from you:** branch from the latest `design-system-v2-development`, implement only REPORT050, add focused adapter/device/state/chart regression tests including CSSOM-normalized blue/red color assertions, and open exactly one Draft PR targeting Development. If shared `ChartTooltip` must change, stop and mark `BLOCKED`.
- **Blocker level:** `NONE`.
- **Baseline:** source baseline inspected `0980f86c44564ab35a4453464e5711a1a0e0915c`; Workstream boundary commit / pre-state-write Development HEAD `c41f7b1789862eb21394fa222561627482c707e4`.
