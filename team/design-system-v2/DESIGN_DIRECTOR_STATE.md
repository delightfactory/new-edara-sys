# Product Design Director State

## Reviewed baseline

- Review date: `2026-10-01`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD before this state write: `725b4a4b59ed8eebf9c8d3c8c05a2de8a6866e9e`.
- Product UI integrated through: `DS2-REPORT-051`.
- Latest product integration: PR #100, reviewed HEAD `8af587a2b6ecf03fde3903290d8bbfab3cf8b0a5`, squash `27d37f6d4c3a2ab184f9c7f47f86e637af6835f6`.
- Current single implementation slice: `DS2-REPORT-052 — Target Attainment shared chart-tooltip adoption`.
- REPORT052 status: `READY — BOUNDED`.
- Active implementation PR targeting Development: none.
- Other open Development PR: `#101 — ci: validate explicit final candidates on DS2 development`, a governance/CI Draft, not a product implementation slice.
- PR #101 current observed HEAD: `f73c95fd56382820f57ec272677812446187db28`; GitHub currently reports `OPEN / DRAFT / mergeable=true`.
- Product Design disposition: `READY — NO DESIGN-SYSTEM BLOCKER`.
- Current contradiction classification: `WATCH — governance PR #101 must be reviewed/reconciled on its own merits, but it does not block starting the one READY implementation slice`.

## Independent Product Design judgment

I re-reviewed the current Target Attainment source/tests and the shared `ChartTooltip` contract against the North Star before using peer-state conclusions.

REPORT052 remains the correct smallest next system-level slice. Target Attainment's `نسبة الإنجاز — المندوبون الفرديون` chart is already inside shared `ChartPanel` grammar, but still exposes Recharts' default tooltip presentation. The existing shared `ChartTooltip` can absorb that presentation island unchanged while Target Attainment retains every analytical, trust and business semantic.

No functional change or shared-tooltip widening is required.

## Locked REPORT052 boundary

Representative surface:
- `src/pages/reports/TargetAttainmentPage.tsx` → `نسبة الإنجاز — المندوبون الفرديون`.

Implement only:
- replace the Recharts default tooltip presentation with the existing shared `ChartTooltip`;
- keep a local Target Attainment adapter for active/payload gating and Recharts payload interpretation;
- keep caller ownership of representative name heading, exact row label `الإنجاز`, percentage formatting, caller achievement color and explicit LTR value direction.

Preserve exactly:
- chart presence rule `chartData.length > 0`; do not add loading/empty chart UI;
- `individualRows = rows.filter(r => r.scope === 'individual' && r.rep_name)`;
- chart mapping `{ name: r.rep_name!, pct: Math.round(r.achievement_pct ?? 0) }`;
- `ResponsiveContainer width="100%" height={Math.max(chartData.length * 40, 200)}`;
- vertical `BarChart`, margins `{ top: 4, left: 10, right: 40, bottom: 0 }`, grid, X/Y axes, percentage tick/domain behavior and `ReferenceLine x={100}`;
- `Bar dataKey="pct" name="الإنجاز%" radius={[0, 3, 3, 0]} maxBarSize={20}`;
- caller `barColor` thresholds/colors: `>=100 -> #10b981`, `>=80 -> #f59e0b`, otherwise `#ef4444`;
- ChartPanel title/description, Trust/Freshness action behavior, header filters, KPI summary, responsive target-detail collection/table/cards, blocked/loading/empty precedence and all query/trust/business semantics.

Device/accessibility:
- Mobile 390 / Tablet 900 / Desktop 1440 use the same shared RTL passive tooltip grammar;
- long Arabic representative names remain contained/wrappable;
- percentage values remain explicit LTR/bidi-safe;
- tooltip stays informational only: no action, focus target, tab stop, `role`, `aria-live` or keyboard contract.

Focused tests must protect:
- inactive / empty-payload adapter guards;
- exact representative heading + one-row `الإنجاز` label + preserved percentage formatting + caller color + LTR direction;
- CSSOM-normalized representative achievement color evidence;
- 390 / 900 / 1440 shared-tooltip adoption and long-Arabic/passive anatomy;
- no chart/tooltip leakage when `chartData.length === 0`;
- unchanged individual filtering, rounded mapping, dynamic height, layout/margins/grid/axes/reference-line/bar/color contracts and Trust/Freshness presence rules.

Explicit exclusions:
- any other report tooltip/chart;
- shared `ChartTooltip` implementation/API/tests/CSS/tokens/breakpoints;
- `ChartPanel`, `ResponsiveCollection`, `Card`, `KeyValueList`, `MetricCard` or other shared-pattern changes;
- Target Attainment filter-control convergence, KPI cards, detail collection/table/cards, export/print/navigation;
- any hook/query/cache/RPC/Supabase/calculation/trust/permission/RBAC/RLS/routing/validation/backend/business change.

If the existing shared `ChartTooltip` cannot serve unchanged, or preserving current chart semantics requires functional change, REPORT052 becomes `BLOCKED` rather than broadened.

## Peer-state synthesis / contradiction resolution

- **Team Memory:** lifecycle-stale through REPORT050/REPORT051 and requires synchronization to REPORT051 integrated + REPORT052 READY.
- **UI Production:** lifecycle-stale from REPORT051 implementation; no REPORT052 implementation PR exists yet.
- **Design QA:** lifecycle-stale from REPORT051 exact-head approval; no REPORT052 review exists yet.
- **Development Integrator:** correctly records REPORT051 integrated and REPORT052 READY, but its baseline `5dbf4e7...` is stale versus current Development `725b4a4...`. It also treats PR #101 as blocking creation of a second Development PR under a "one-active-PR" rule.
- **Authoritative contract synthesis:** `AGENTS.md` and the Workstream require one active **implementation slice** at a time, not one open PR of any type. PR #101 is a separate governance/CI proposal and does not touch Target Attainment or `ChartTooltip`. Therefore it is **not an implementation blocker** for REPORT052.
- PR #101 remains `WATCH`: it overlaps governance files (including the Workstream) and proposes CI-policy changes. It must be reviewed/reconciled separately and must not be merged by scheduled Product Design work. If it later changes Development before REPORT052 review/integration, REPORT052 must reconcile to the then-current base and receive fresh exact-head review.
- The prior Integrator `BLOCKING` classification is therefore bounded to **integration of PR #101 itself**, not to beginning REPORT052.
- Current material design-system contradiction after this synthesis: `NONE`.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in order.
- Inspected issue #27, current Development HEAD, open PRs and PR #101 diff/metadata.
- Re-inspected Target Attainment source/tests and the shared `ChartTooltip` contract.
- Confirmed the Workstream currently has exactly one READY implementation item: REPORT052; Reports roadmap correctly marks REPORT001-051 DONE.
- Did not implement product code, merge any PR, touch `main`, deploy Vercel, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer; Development Integrator and Design QA for awareness.
- **What changed:** Product Design confirms REPORT052 remains the single READY implementation slice and explicitly bounds PR #101 as a separate governance WATCH, not an implementation-start blocker.
- **Preserve:** REPORT052 exact bounded contract above; shared `ChartTooltip` unchanged; all Target Attainment chart/filter/KPI/detail/query/trust/business semantics; PR #101 remains separate and must not be merged or used to trigger CI by this role.
- **Need from you:** UI Production may start REPORT052 from the exact latest Development HEAD and open one Draft implementation PR. Design QA should review only its future exact stable HEAD. Integrator should treat PR #101's merge blocker separately and re-evaluate any base drift before future integration.
- **Blocker level:** `NONE` for REPORT052 implementation; `WATCH` for governance PR #101; PR #101's own integration remains separately blocked pending governance review.
- **Baseline:** Development `725b4a4b59ed8eebf9c8d3c8c05a2de8a6866e9e`; governance PR #101 HEAD `f73c95fd56382820f57ec272677812446187db28`.
