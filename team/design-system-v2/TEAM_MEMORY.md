# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-050`.
- Current integrated product HEAD / squash merge: `22983eff7ce4d11113c2b10de5468bb33bb86936` from PR #98.
- Exact reviewed implementation HEAD: `007d1174c09f1808a261fa49b133e4201d25ca68`.
- Current single READY roadmap item: `DS2-REPORT-051 — Churn Risk shared chart-tooltip adoption`.
- REPORT051 is `READY — BOUNDED`: UI Production may implement only the `توزيع تصنيف العملاء` Pie-chart tooltip adoption from the exact latest Development baseline, using the existing shared `ChartTooltip` unchanged; if that requires shared-contract widening or functional semantics to change, the slice becomes `BLOCKED`.
- `main` remains frozen until explicit owner approval.
- Vercel preview remains user-requested only.
- GitHub Actions / hosted CI remain forbidden for normal Design System development.
- Product target remains one deep, premium Arabic-first operational Design System across the entire EDARA interface.
- Mobile is the primary daily operational surface; Tablet is deliberate and touch-first; Desktop preserves management/review/data-entry density and speed.

## Current integrated system

Development now includes:
- semantic foundations and V2 primitives/patterns;
- responsive shell/navigation/form/collection/action composition foundations;
- Dashboard V2 and representative Customers, Sales, Inventory, Procurement, Finance, HR, Field and Work migrations;
- Reports route-level `SubNav`, date-preset `SegmentedControl`, shared native `DateField`, shared `Select -> Field`, shared `ChartPanel`, shared `ChartTooltip`, shared `MetricGrid`, shared `StatePanel`, shared `AlertPanel`, and shared `SectionHeader` convergence across representative analytics surfaces;
- shared V2 Field grammar proven for compact report-scope risk/date controls while filter/date/query truth remains caller-owned;
- shared `MetricGrid` proofs across representative report KPI clusters while report-domain/business meaning remains caller-owned;
- shared `ChartPanel` analytical-surface grammar across representative report charts while chart data/visualization semantics remain caller-owned;
- shared compact passive `StatePanel` empty-state grammar across representative report charts and responsive detail collections;
- shared semantic-feedback `AlertPanel` grammar proven on Treasury's static semantic-contract disclosure without moving disclosure/trust truth into the Design System;
- shared `SectionHeader` hierarchy/action anatomy proven on Reports Overview section headings while report copy/navigation/data truth remain caller-owned;
- representative report detail collections using shared responsive collection grammar while preserving dense semantic Desktop tables;
- Customer Re-engagement using shared `ResponsiveCollection` to mount exactly one ready renderer per device: Mobile cards, explicit touch-first Tablet cards, or dense Desktop table;
- shared domain-agnostic `ChartTooltip` presentation grammar proven on Receivables and adopted by Sales, Treasury, Product Performance and Rep Performance while Recharts/domain/business semantics remain caller-owned;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-REPORT-050 — Rep Performance shared chart-tooltip adoption`

Result:
- PR #98 exact reviewed HEAD `007d1174c09f1808a261fa49b133e4201d25ca68` received `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- Product Design independently closed out the same exact HEAD as `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Evidence remains honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview/release PASS is claimed.
- Squash merge commit: `22983eff7ce4d11113c2b10de5468bb33bb86936`.
- Rep Performance now delegates only the `مقارنة المندوبين — أعلى 15` tooltip presentation/anatomy to existing shared `ChartTooltip`; its local Recharts adapter retains active/payload gating, heading, payload order, labels, caller series colors, exact `${fmt(p.value)} ج.م` formatting and explicit LTR values.
- Exact `tableLoading -> empty -> ready`, 300px loading/empty containment, top-15 mapping, dynamic ready height, vertical layout/margins/grid/axes, revenue/returns series order/colors/radii/max sizes, Trust/Freshness and responsive detail composition remain unchanged.
- Shared `ChartTooltip` API/CSS/tokens/breakpoints remain unchanged; Receivables, Sales, Treasury, Product Performance and Rep Performance are now bounded consumers.
- Development drift from the feature baseline before merge was governance-only in Design QA and Product Design state files; no product/test/shared-component overlap existed.

## Current single READY roadmap item

`DS2-REPORT-051 — Churn Risk shared chart-tooltip adoption`

Intent:
- replace only the default Recharts tooltip inside `src/pages/reports/ChurnRiskPage.tsx` → `توزيع تصنيف العملاء` with the already-proven presentation-only shared `ChartTooltip`;
- keep Churn Risk ownership of chart-library payload interpretation, category heading, one-row `عملاء` label, existing `FMT` count formatting, caller pie-series color, explicit LTR numeric direction and every analytical/trust/business semantic;
- preserve the exact chart presence gate `!statsLoading && pieData.length > 0`, 260px container, pie data/order/keys/radii/padding, five caller colors, Legend and Trust/Freshness behavior;
- preserve header filters, KPI summary and responsive customer-detail collection/table/cards unchanged;
- 390 / 900 / 1440 use the same shared RTL passive tooltip grammar with long-Arabic containment and bidi-safe numeric values;
- no `ChartTooltip` API/CSS/token/breakpoint widening, no other report tooltip migration and no backend/query/calculation/permission/business change;
- focused tests must protect inactive/empty payload guards, exact category/label/count/color/LTR mapping, CSSOM-normalized color evidence, device adoption, chart absence during loading/zero-data and unchanged chart geometry/contracts.

If the existing shared `ChartTooltip` cannot serve this consumer unchanged, or exact behavior preservation requires functional change, REPORT051 is `BLOCKED` rather than broadened.

## Latest role positions

### Product Design Director
- REPORT050 exact-head acceptance is consumed by integration.
- Independently bounded REPORT051 as `Churn Risk shared chart-tooltip adoption` from the current integrated Reports baseline; the workstream boundary is commit `a5fe116aa3bda27b0ddc71cb60c4b1cf458d7122`.
- No current `BLOCKING` contradiction exists; UI Production is the next owner and must keep shared `ChartTooltip` unchanged.

### UI Production Engineer
- REPORT050 implementation is integrated.
- Its PR-carried owned state records REPORT050 implementation/evidence and is consumed by integration; it is not authorization to begin REPORT051.
- Must not begin REPORT051 product code until Product Design records the exact boundary from the latest Development HEAD.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` on `007d1174c09f1808a261fa49b133e4201d25ca68` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Found no known source-visible build/type blocker, material review thread, functional-isolation breach or deployment/workflow drift on the merged exact HEAD.
- That approval is consumed by the merge and cannot be reused for REPORT051.

### Development Integrator
- Revalidated PR #98 base/head, exact-head QA gate, exact-head Product Design closeout, empty review threads, exact three-file UI/Test/Governance scope, governance-only Development drift, mergeability and functional isolation.
- Transitioned the Draft PR to Ready without moving its HEAD and squash-merged with expected-head protection as `22983eff7ce4d11113c2b10de5468bb33bb86936`.
- Marked REPORT050 DONE and advanced exactly one roadmap item, REPORT051, to READY for Product Design bounding.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Shared visual primitives/patterns own presentation and interaction mechanics, never business eligibility, calculations, workflow or state-machine meaning.
- `ChartTooltip` owns tooltip presentation/anatomy only; callers retain chart-library payload interpretation, domain labels/order, value formatting/direction, series colors, data, trust and business meaning.
- `ChartPanel` owns only neutral analytical surface/frame, semantic section hierarchy and chart-body containment; chart data, visualization semantics, trust/freshness, state decisions and business meaning remain caller-owned.
- `ResponsiveCollection` owns device renderer selection/orchestration plus generic loading/empty collection containment only; collection data, business ordering, row meaning, domain copy, permissions and actions remain caller-owned.
- Ready responsive collection composition should mount one renderer per canonical device mode rather than keep duplicate hidden interaction trees when the shared orchestrator already fits the capability.
- Dense management collections may intentionally remain semantic Desktop tables while Tablet/Mobile use deliberate shared-card composition from the same unchanged domain data.
- Tablet must be a deliberate touch-first composition rather than an accidental Desktop fallback.
- `SectionHeader` owns semantic section hierarchy plus neutral title/description/action anatomy and responsive layout only; callers retain section copy, route/navigation meaning, data/business truth and action semantics.
- `AlertPanel` owns semantic feedback/message presentation and accessibility anatomy only; callers retain domain copy, business/trust truth, announcement necessity and actions.
- `StatePanel` owns shared state presentation/anatomy only; state precedence, loading decisions, data truth, actions and business meaning remain caller-owned.
- A page-local state wrapper is acceptable for preserved analytical geometry; state typography/color/anatomy belongs to the shared state family.
- `Field`, `Select`, `Input` and `DateField` own presentation/accessibility/control mechanics only; filter values, date semantics and query inputs remain caller-owned.
- `MetricGrid` owns KPI/metric layout and responsive composition only; callers and metric components retain calculation, trust/status and business meaning.
- `StatCard` owns semantic KPI presentation only; report/domain calculations, category classification and sign/risk truth remain caller-owned.
- Report-domain `MetricCard` continues to own report trust/freshness/status presentation semantics unless a separately bounded future decision proves equivalence.
- Canonical touch targets remain first-class through Tablet; Desktop may intentionally preserve denser pointer-oriented controls.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Durable decisions belong in the Decision Log; routine progress does not.
- No hosted CI, Vercel preview or `main` activity from scheduled agents.

## Known evidence / risks

- Development evidence through REPORT050 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions/status checks is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- REPORT051 is intentionally a roadmap-level placeholder and must be decomposed by Product Design into one smallest representative presentation concern before implementation.
- Shared `ChartTooltip` now has bounded consumers in Receivables, Sales, Treasury, Product Performance and Rep Performance; duplicated page-local tooltips remain adoption debt and must be migrated only through future bounded slices.
- Reports Overview navigation cards retain legacy interactive-surface/touch/action debt; neutral shared `Card` does not currently own whole-card navigation semantics, so this needs a separately bounded concern if selected later.
- Remaining report tables, chart surfaces, dense responsive composition, loading/empty/error states, export/print and broader FilterBar grammar still need later bounded convergence; no business semantics may move into the Design System.
- Further Work detail/feedback/management convergence and Field create/detail convergence remain debt.
- Shared Pagination, FilterBar/search/filter convergence, DataTable keyboard/overflow semantics, SearchInput clear accessibility, error/offline-state convergence and dense-table overflow remain broader shared debt.
- Settings/Admin and global Dark/RTL/accessibility/legacy cleanup remain unstarted roadmap phases.

## Reusable patterns learned

- REPORT050 reinforces that repeated page-local chart-tooltip anatomy should converge through bounded adoption of the proven shared `ChartTooltip` while caller chart/domain truth remains local.
- REPORT049 established the same bounded-adoption pattern on Product Performance after Receivables, Sales and Treasury.
- REPORT047 confirmed focused tests must use browser/CSSOM representation contracts when asserting inline colors; deterministic test mismatches are real GREEN-DEV blockers even when runtime product code appears source-clean.
- REPORT046 established repeated chart-tooltip visual anatomy as a shared domain-agnostic presentation contract while chart-library adapters and report/business truth stay in callers.
- A representative proof consumer is preferable to mass migration: prove the shared contract first, then adopt on adjacent surfaces through separately bounded slices.
- Caller-provided chart colors can remain series identity without being reclassified as Design System semantic status colors.
- Mixed-direction analytical values should remain caller-directed while the shared tooltip provides RTL-safe containment and bidi isolation.
- Shared `ResponsiveCollection` should replace page-local CSS device switching when the same collection capability has distinct Mobile/Tablet/Desktop renderers and the shared contract already covers orchestration.
- One mounted ready renderer per device removes hidden duplicate interactive descendants and makes device behavior explicit without changing data/business truth.
- Shared state presentation must never homogenize caller-owned state truth merely for visual consistency.
- Shared patterns should be proven on representative screens, then reused; legacy families should not be globally removed while live consumers remain.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect representative remaining Reports/Analytics surfaces on the exact latest `design-system-v2-development` baseline and record exactly one smallest dependency-safe REPORT051 presentation concern, including representative file/surface and explicit acceptance/exclusion boundary. Preserve REPORT001-050 contracts, all analytics/query/calculation/trust/permission/routing/export/print/backend/business semantics, and keep Settings/Admin, Global, remaining Work/Field and shared-component roadmap intact.

UI Production Engineer should bootstrap only after that boundary is recorded and implement one coherent concern from the exact then-current Development HEAD. Design QA should independently review the future exact stable PR HEAD. Development Integrator should no-op until a future PR receives fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and all normal gates pass.
