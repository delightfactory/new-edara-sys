# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-042`.
- Current integrated product HEAD / squash merge: `f7479859fe5c3233c3082bad2e97c0a004213f4c` from PR #90.
- Exact reviewed implementation HEAD: `dbabddc56743f2d448bbefbab4998b6f0b98e9bb`.
- Coordination HEAD immediately before this Team Memory write: `7d808b057300e20b7787bde97181cd8dc27c844e`.
- Current single READY roadmap item: `DS2-REPORT-043 — Next bounded Reports metrics/charts/tables/responsive-composition convergence`.
- REPORT043 is intentionally unbounded: Product Design Director must inspect the exact latest Development baseline and record exactly one smallest dependency-safe presentation-only concern before UI Production begins.
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
- Reports route-level `SubNav`, date-preset `SegmentedControl`, shared native `DateField`, shared `Select -> Field`, shared `ChartPanel`, shared `MetricGrid`, shared `StatePanel`, and `ResponsiveCollection + Card + KeyValueList` convergence across representative analytics surfaces;
- shared V2 Field grammar proven for compact report-scope risk/date controls while filter/date/query truth remains caller-owned;
- shared `MetricGrid` proofs across representative report KPI clusters while report-domain/business meaning remains caller-owned;
- shared `ChartPanel` analytical-surface grammar across representative report charts while chart data/visualization semantics remain caller-owned;
- shared compact passive `StatePanel` empty-state grammar across Product Performance, Rep Performance, Customer Health responsive detail, Receivables AR chart, Geography responsive detail, Churn Risk responsive detail, and both Sales analytical charts;
- representative report detail collections using shared responsive collection grammar while preserving dense semantic Desktop tables;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-REPORT-042 — Sales revenue/tax bar-chart empty-state convergence`

Result:
- PR #90 exact reviewed HEAD `dbabddc56743f2d448bbefbab4998b6f0b98e9bb` received `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- Product Design independently closed out the same exact HEAD as `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Evidence remains honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview/release PASS is claimed.
- Squash merge commit: `f7479859fe5c3233c3082bad2e97c0a004213f4c`.
- The second Sales analytical panel (`توزيع الإيرادات اليومي (إيراد + ضريبة)`) now consumes the existing shared compact passive `StatePanel kind="empty"` instead of treating an empty Recharts canvas as an implicit no-data state.
- Exact empty copy remains `لا توجد بيانات في النطاق الزمني المحدد`.
- Caller-owned analytical geometry remains 200px across loading/empty/ready.
- Exact state precedence is `dailyLoading -> empty -> ready`; no `isBlocked`, BLOCKED/FAILED or trust semantics were added to this chart.
- `SkeletonCard height={200}` and the ready BarChart data/margin/axes/grid/tooltip/revenue+tax series/fills/radii/`maxBarSize` remain unchanged.
- The first Sales chart remains completely unchanged, including its 240px geometry, BLOCKED/trust semantics, Trust/Freshness and AreaChart contract.
- No shared API/CSS/token/breakpoint widening occurred and no query/cache/aggregation/calculation/trust/permission/RBAC/RLS/routing/export/print/backend/business/workflow semantics changed.

## Current single READY roadmap item

`DS2-REPORT-043 — Next bounded Reports metrics/charts/tables/responsive-composition convergence`

Intent:
- Product Design Director inspects representative remaining Reports/Analytics surfaces on the exact latest Development baseline before implementation;
- select exactly one smallest dependency-safe presentation-only concern and name its representative surface/file plus explicit acceptance/exclusion boundary;
- prefer existing shared V2 primitives/patterns, or strengthen a shared contract only when a real consumer demonstrates the need;
- preserve REPORT001-042 contracts and all analytics/query/calculation/trust/permission/RBAC/RLS/routing/export/print/backend/business semantics;
- preserve Settings/Admin, Global convergence, remaining Work and Field debt and shared component-depth work in the roadmap;
- do not turn REPORT043 into broad multi-page report beautification.

Implementation is not authorized until Product Design records the exact bounded concern from the then-current Development HEAD.

## Latest role positions

### Product Design Director
- Independently accepted REPORT042 exact PR HEAD `dbabddc56743f2d448bbefbab4998b6f0b98e9bb` as `PASS — NO DESIGN-SYSTEM BLOCKER`.
- No current `BLOCKING` contradiction exists.
- That acceptance is consumed by REPORT042 integration; next responsibility is to inspect the exact latest Development baseline and bound one smallest safe REPORT043 concern.

### UI Production Engineer
- REPORT042 implementation is integrated.
- The PR-carried owned state records REPORT042 scope/evidence and is consumed by integration; the Development copy now arrives through the merged PR and remains historical for the completed slice until the next implementation run.
- Must not begin REPORT043 product code until Product Design records the exact boundary from the latest Development HEAD.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` on `dbabddc56743f2d448bbefbab4998b6f0b98e9bb` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Found no known source-visible build/type blocker, material review thread, functional-isolation breach or deployment/workflow drift on the merged exact HEAD.
- That approval is consumed by the merge and cannot be reused for REPORT043.

### Development Integrator
- Revalidated PR #90 base/head, exact-head QA gate, exact-head Product Design closeout, empty review threads, three-file UI/Test/Governance scope, governance-only Development drift, mergeability and functional isolation.
- Transitioned the Draft PR to Ready without moving its HEAD and squash-merged with expected-head protection as `f7479859fe5c3233c3082bad2e97c0a004213f4c`.
- Marked REPORT042 DONE and advanced exactly one roadmap item, REPORT043, to READY for Product Design bounding.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Shared visual primitives/patterns own presentation and interaction mechanics, never business eligibility, calculations, workflow or state-machine meaning.
- `StatePanel` owns shared state presentation/anatomy only; state precedence, loading decisions, data truth, actions and business meaning remain caller-owned.
- A page-local state wrapper is acceptable for preserved analytical geometry; state typography/color/anatomy belongs to the shared state family.
- `ResponsiveCollection` owns device renderer selection/orchestration plus generic loading/empty collection presentation only; collection data, business ordering, row meaning, domain copy and actions remain caller-owned.
- `Field`, `Select`, `Input` and `DateField` own presentation/accessibility/control mechanics only; filter values, date semantics and query inputs remain caller-owned.
- `MetricGrid` owns KPI/metric layout and responsive composition only; callers and metric components retain calculation, trust/status and business meaning.
- `StatCard` owns semantic KPI presentation only; report/domain calculations, category classification and sign/risk truth remain caller-owned.
- Report-domain `MetricCard` continues to own report trust/freshness/status presentation semantics unless a separately bounded future decision proves equivalence.
- `ChartPanel` owns only neutral analytical surface/frame, semantic section hierarchy and chart-body containment; chart data, visualization semantics, trust/freshness, state decisions and business meaning remain caller-owned.
- Dense management collections may intentionally remain semantic Desktop tables while Tablet/Mobile use deliberate shared-card composition from the same unchanged domain data.
- Canonical touch targets remain first-class through Tablet; Desktop may intentionally preserve denser pointer-oriented controls.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Durable decisions belong in the Decision Log; routine progress does not.
- No hosted CI, Vercel preview or `main` activity from scheduled agents.

## Known evidence / risks

- Development evidence through REPORT042 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions/status checks is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- REPORT043 is intentionally a roadmap-level placeholder and must be decomposed by Product Design into one smallest representative presentation concern before implementation.
- Remaining report tables, chart surfaces, dense responsive composition, loading/empty/error states, export/print and broader FilterBar grammar still need later bounded convergence; no business semantics may move into the Design System.
- Further Work detail/feedback/management convergence and Field create/detail convergence remain debt.
- Shared Pagination, FilterBar/search/filter convergence, DataTable keyboard/overflow semantics, SearchInput clear accessibility, error/offline-state convergence and dense-table overflow remain broader shared debt.
- Settings/Admin and global Dark/RTL/accessibility/legacy cleanup remain unstarted roadmap phases.

## Reusable patterns learned

- REPORT042 confirms adjacent analytical panels may share the same passive empty-state anatomy while retaining different caller-owned geometry and state machines: the second Sales chart remains 200px and has no trust/BLOCKED semantics, while the first remains 240px with its own BLOCKED/trust contract.
- Shared state presentation must never homogenize caller-owned state truth merely for visual consistency.
- REPORT041 confirmed fixed analytical geometry can remain page-owned while shared compact passive `StatePanel` owns empty-state anatomy inside an existing `ChartPanel`; chart data, state precedence, Trust/Freshness and visualization semantics remain caller-owned.
- `ResponsiveCollection.emptyTitle -> compact passive StatePanel` is preferred over bespoke local empty blocks when no domain-specific action/geometry is required.
- Empty-state convergence must preserve caller-owned loading/blocking precedence and prevent hidden ready renderers from mounting in non-ready states.
- Category-oriented metric summaries can retire arbitrary page-local KPI grid/card styling onto existing `MetricGrid` + `StatCard` without moving category classification or report truth into the Design System.
- Existing report charts can retire local analytical frames onto shared `ChartPanel -> Card + SectionHeader` without changing chart data, responsive sizing, visualization semantics or trust/freshness meaning.
- Compact report-scope controls can converge onto existing `Select` + `DateField` / `Field` grammar without moving filter/date/query meaning into shared components or widening shared APIs.
- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared patterns should be proven on representative screens, then reused; legacy families should not be globally removed while live consumers remain.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect representative remaining Reports/Analytics surfaces on the exact latest `design-system-v2-development` baseline and record exactly one smallest dependency-safe REPORT043 presentation concern, including representative file/surface and explicit acceptance/exclusion boundary. Preserve REPORT001-042 contracts, all analytics/query/calculation/trust/permission/routing/export/print/backend/business semantics, and keep Settings/Admin, Global, remaining Work/Field and shared-component roadmap intact.

UI Production Engineer should bootstrap only after that boundary is recorded and implement one coherent concern from the exact then-current Development HEAD. Design QA should independently review the future exact stable PR HEAD. Development Integrator should no-op until a future PR receives fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and all normal gates pass.
