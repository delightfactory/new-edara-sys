# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-051`.
- Latest product integration: PR #100, reviewed HEAD `8af587a2b6ecf03fde3903290d8bbfab3cf8b0a5`, squash merge `27d37f6d4c3a2ab184f9c7f47f86e637af6835f6`.
- Current single READY implementation slice: `DS2-REPORT-052 — Target Attainment shared chart-tooltip adoption` (`READY — BOUNDED`).
- REPORT052 may start from the exact latest Development baseline. It is limited to the default Recharts tooltip inside `src/pages/reports/TargetAttainmentPage.tsx` → `نسبة الإنجاز — المندوبون الفرديون`, using existing shared `ChartTooltip` unchanged.
- PR #101 (`ci: validate explicit final candidates on DS2 development`) is a separate governance/CI Draft, not a product implementation slice. It is `WATCH` for governance/base-drift purposes and does not block starting REPORT052. Its own integration remains separately gated by governance review.
- `main` remains frozen until explicit owner approval.
- Vercel preview remains user-requested only.
- Hosted GitHub Actions remain forbidden for normal Design System development under the currently integrated policy.
- Product target remains one complete, premium, Arabic-first operational Design System across Mobile, Tablet and Desktop.

## Current integrated system

Development includes:
- semantic foundations and V2 primitives/patterns;
- responsive shell/navigation/form/collection/action composition foundations;
- Dashboard V2 and representative Customers, Sales, Inventory, Procurement, Finance, HR, Field and Work migrations;
- Reports route/date/filter convergence;
- shared `ChartPanel`, `ChartTooltip`, `MetricGrid`, `StatePanel`, `AlertPanel`, `SectionHeader`, Field controls and responsive collection grammar;
- shared domain-agnostic `ChartTooltip` adoption in Receivables, Sales, Treasury, Product Performance, Rep Performance and Churn Risk while each caller retains chart-library/domain/business semantics.

## Latest completed slice

`DS2-REPORT-051 — Churn Risk shared chart-tooltip adoption`

Result:
- exact reviewed PR #100 HEAD `8af587a2b6ecf03fde3903290d8bbfab3cf8b0a5`;
- `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`;
- Product Design `PASS — NO DESIGN-SYSTEM BLOCKER`;
- evidence `TESTS_AUTHORED_NOT_EXECUTED`;
- squash merge `27d37f6d4c3a2ab184f9c7f47f86e637af6835f6`;
- Churn Risk now delegates only Pie-tooltip presentation/anatomy to shared `ChartTooltip`;
- caller-owned active/payload gating, category heading, `عملاء`, `FMT`, caller Pie color, LTR numeric direction, ready-only chart presence, 260px geometry, Pie data/order/keys/radii/padding/colors, Legend, Trust/Freshness, filters/KPIs/detail/query/business semantics remain unchanged;
- shared `ChartTooltip` API/CSS/tokens/breakpoints were not widened.

## Current single READY slice

`DS2-REPORT-052 — Target Attainment shared chart-tooltip adoption`

Representative surface:
- `src/pages/reports/TargetAttainmentPage.tsx` → default Recharts tooltip in `نسبة الإنجاز — المندوبون الفرديون`.

Implement only:
- replace default tooltip presentation with existing shared `ChartTooltip`;
- keep a local caller adapter for `active` / payload interpretation;
- keep representative-name heading, exact row label `الإنجاز`, percentage formatting, caller achievement color and explicit LTR value direction caller-owned.

Preserve exactly:
- chart presence `chartData.length > 0`;
- `individualRows = rows.filter(r => r.scope === 'individual' && r.rep_name)`;
- chart mapping `{ name: r.rep_name!, pct: Math.round(r.achievement_pct ?? 0) }`;
- `ResponsiveContainer width="100%" height={Math.max(chartData.length * 40, 200)}`;
- vertical BarChart layout and margins `{ top: 4, left: 10, right: 40, bottom: 0 }`;
- grid, X/Y axes, percentage tick/domain behavior and `ReferenceLine x={100}`;
- `Bar dataKey="pct" name="الإنجاز%" radius={[0, 3, 3, 0]} maxBarSize={20}`;
- caller `barColor` thresholds/colors `>=100 -> #10b981`, `>=80 -> #f59e0b`, otherwise `#ef4444`;
- ChartPanel title/description, Trust/Freshness, report filters, KPI summary, responsive target detail composition, state precedence and all query/trust/business semantics.

Device/accessibility:
- same shared RTL passive tooltip grammar at 390 / 900 / 1440;
- long Arabic representative names remain wrappable;
- percentage values remain LTR/bidi-safe;
- no focus target, tab stop, role, aria-live or keyboard/action semantics added.

Focused tests:
- inactive / empty-payload guards;
- exact representative heading / `الإنجاز` / percentage / caller-color / LTR mapping;
- CSSOM-normalized caller-color evidence;
- 390 / 900 / 1440 adoption and long-Arabic/passive anatomy;
- no chart/tooltip leakage when `chartData.length === 0`;
- unchanged individual filtering, rounded mapping, dynamic height, layout/margins/grid/axes/reference-line/bar/color and Trust/Freshness contracts.

Explicit exclusions:
- any other report tooltip/chart;
- shared `ChartTooltip` implementation/API/tests/CSS/tokens/breakpoints;
- other shared-pattern changes;
- Target Attainment filter-control convergence, KPI cards, detail collection/table/cards, export/print/navigation;
- any hook/query/cache/RPC/Supabase/calculation/trust/permission/RBAC/RLS/routing/validation/backend/business change.

If existing `ChartTooltip` cannot serve unchanged, or preserving current chart semantics requires functional change, REPORT052 becomes `BLOCKED` rather than broadened.

## Latest role positions

### Product Design Director
- REPORT052 is the correct smallest next system-level slice.
- Product Design disposition: `READY — NO DESIGN-SYSTEM BLOCKER`.
- PR #101 is a governance/CI WATCH, not an implementation-start blocker.
- No current material Design-System contradiction exists.

### UI Production Engineer
- Development-branch role state is lifecycle-stale from REPORT051.
- Next action is to start REPORT052 from the exact latest Development HEAD, implement only the bounded tooltip adoption and open one Draft implementation PR targeting Development.

### Design QA
- Latest state is consumed REPORT051 approval.
- Fresh exact-head review is required for the future REPORT052 implementation PR.

### Development Integrator
- Correctly records REPORT051 integrated and REPORT052 READY.
- Its blocker on PR #101 applies to integration of that governance PR itself.
- Product Design does not extend that blocker to starting REPORT052 because the authoritative operating contract limits concurrent implementation slices, not unrelated governance PRs.
- Future REPORT052 integration must reconcile any Development drift and receive fresh exact-head gates.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Shared visual primitives/patterns own presentation and interaction mechanics, never business eligibility, calculations, workflow or state-machine meaning.
- `ChartTooltip` owns presentation/anatomy only; callers retain chart-library payload interpretation, domain labels/order, value formatting/direction, series colors, data, trust and business meaning.
- `ChartPanel` owns neutral analytical surface/frame and section hierarchy only.
- `ResponsiveCollection` owns device renderer selection/orchestration and generic collection states only.
- Mobile is primary operational; Tablet is deliberate touch-first; Desktop preserves dense management/review workflows.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Durable decisions belong in the Decision Log; routine progress belongs in role states / Team Memory / issue #27.
- No normal hosted CI, Vercel preview or `main` activity from scheduled agents.

## Known evidence / risks

- Evidence through REPORT051 remains source-level; no exact-head executed build/test/lint/runtime/preview/release PASS is claimed.
- Runtime visual acceptance remains milestone-based and owner-requested.
- PR #101 proposes a governance/CI policy change and overlaps governance files including Workstream/Test Policy/Decision Log. It must be reconciled separately and may create future base drift.
- Remaining Reports/Analytics convergence still includes report filter/search grammar, dense tables, state/error/offline convergence, export/print, and other bounded shared-pattern adoption.
- Settings/Admin and global Dark/RTL/accessibility/legacy cleanup remain future roadmap phases.

## Reusable patterns learned

- Repeated page-local chart-tooltip anatomy should converge through bounded adoption of the proven shared `ChartTooltip` while caller chart/domain truth stays local.
- A representative proof consumer is preferable to mass migration.
- Caller-provided chart colors can remain series identity without becoming Design System semantic-status colors.
- Mixed-direction analytical values remain caller-directed while shared tooltip anatomy provides RTL containment and bidi isolation.
- Shared state presentation must not homogenize caller-owned state truth.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

UI Production Engineer should start REPORT052 from the exact latest `design-system-v2-development` HEAD, implement only the bounded Target Attainment tooltip adoption, author focused tests and open one Draft implementation PR targeting Development. PR #101 remains separate governance work and must not be merged or used to trigger hosted CI by Product Design. Design QA should review only the future exact stable REPORT052 PR HEAD; Development Integrator should revalidate all gates and any base drift before merge.
