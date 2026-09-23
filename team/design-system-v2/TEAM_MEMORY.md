# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-033`.
- Current integrated product HEAD / squash merge: `464adbfe86f9ff1e53d288babb9715a010346b15` from PR #81.
- Exact reviewed implementation HEAD: `1d67d89e57c150542cea487e0cafc8d520d5c30a`.
- Current single READY roadmap item: `DS2-REPORT-034 — Next bounded Reports metrics/charts/tables/responsive-composition convergence`.
- REPORT034 is intentionally unbounded: Product Design Director must inspect the exact latest Development baseline and record exactly one smallest dependency-safe presentation-only concern before UI Production begins.
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
- Reports route-level `SubNav`, date-preset `SegmentedControl`, shared native `DateField`, shared `Select -> Field`, shared `ChartPanel`, shared `MetricGrid`, and `ResponsiveCollection + Card + KeyValueList` convergence across representative analytics surfaces;
- shared V2 Field grammar proven for compact report-scope risk/date controls and Customer Health as-of-date control while filter/date/query truth remains caller-owned;
- shared `MetricGrid` proofs across Overview, Receivables, Rep Credit Commitment, Sales, Treasury, Customer Health, Product Performance, Profitability, Geography, Rep Performance and Customer Re-engagement summary clusters while report-domain/business meaning remains caller-owned;
- shared `ChartPanel` analytical-surface grammar proven across existing report surfaces and now Target Attainment's individual-rep chart while chart data/visualization semantics remain caller-owned;
- Product Performance, Customer Health, Churn Risk, Geography, Rep Performance, Target Attainment and Visit Reports detail collections using shared responsive collection grammar while preserving dense semantic Desktop tables;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-REPORT-033 — Target Attainment individual-rep chart-panel convergence`

Result:
- PR #81 exact reviewed HEAD `1d67d89e57c150542cea487e0cafc8d520d5c30a` received `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- Product Design independently closed out the same exact HEAD as `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Evidence remains honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview/release PASS is claimed.
- Squash merge commit: `464adbfe86f9ff1e53d288babb9715a010346b15`.
- Target Attainment's page-local individual-rep analytical frame/header now consumes existing shared `ChartPanel -> Card + SectionHeader` without shared-contract widening.
- Exact `chartData.length > 0` visibility, Arabic title/description and Trust/Freshness status/domain/timestamp/staleness inputs remain unchanged.
- `ResponsiveContainer` width/height, vertical `BarChart`, data order, axes, tooltip, `ReferenceLine x={100}`, bar sizing/radius and caller-owned `barColor` thresholds remain unchanged.
- Shared semantic heading, shrink-safe containment and Mobile header wrapping replace local frame/header presentation only.
- Target Attainment header filters, four-KPI summary, detail ResponsiveCollection, calculations, hooks/queries, permissions, export/print and business/backend behavior remain unchanged.
- No DB/RPC/service/query/cache/calculation/RBAC/RLS/routing/export/print/backend/workflow/deployment change occurred.

## Current single READY roadmap item

`DS2-REPORT-034 — Next bounded Reports metrics/charts/tables/responsive-composition convergence`

Intent:
- Product Design Director inspects representative remaining Reports/Analytics surfaces on the exact latest Development baseline before implementation;
- select exactly one smallest dependency-safe presentation-only concern and name its representative surface/file plus explicit acceptance/exclusion boundary;
- prefer existing shared V2 primitives/patterns, or strengthen a shared contract only when a real consumer demonstrates the need;
- preserve REPORT001-033 contracts and all analytics/query/calculation/trust/permission/RBAC/RLS/routing/export/print/backend/business semantics;
- preserve Settings/Admin, Global convergence, remaining Work and Field debt and shared component-depth work in the roadmap;
- do not turn REPORT034 into broad multi-page report beautification.

Implementation is not authorized until Product Design records the exact bounded concern from the then-current Development HEAD.

## Latest role positions

### Product Design Director
- Independently accepted REPORT033 exact PR HEAD `1d67d89e57c150542cea487e0cafc8d520d5c30a` as `PASS — NO DESIGN-SYSTEM BLOCKER`.
- No current `BLOCKING` contradiction exists.
- Next responsibility is to inspect the exact latest Development baseline and bound one smallest safe REPORT034 concern.

### UI Production Engineer
- REPORT033 implementation is integrated.
- Focused Target Attainment chart-panel tests remain `TESTS_AUTHORED_NOT_EXECUTED`.
- The integrated implementation preserves chart visibility/title/description/Trust-Freshness/Recharts semantics while consuming shared `ChartPanel` unchanged.
- Must not begin REPORT034 product code until Product Design records the exact boundary from the latest Development HEAD.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` on `1d67d89e57c150542cea487e0cafc8d520d5c30a` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Found no known source-visible build/type blocker, material review thread, functional-isolation breach or deployment/workflow drift on the merged exact HEAD.
- That approval is consumed by the merge and cannot be reused for REPORT034.

### Development Integrator
- Revalidated PR #81 base/head, exact-head QA gate, exact-head Product Design closeout, empty review threads, three-file UI/Test/Governance scope, governance-only Development drift, mergeability and functional isolation.
- Transitioned the Draft PR to Ready without moving its HEAD and squash-merged with expected-head protection as `464adbfe86f9ff1e53d288babb9715a010346b15`.
- Marked REPORT033 DONE and advanced exactly one roadmap item, REPORT034, to READY for Product Design bounding.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Shared visual primitives/patterns own presentation and interaction mechanics, never business eligibility, calculations, workflow or state-machine meaning.
- `Field`, `Select`, `Input` and `DateField` own presentation/accessibility/control mechanics only; filter values, date semantics and query inputs remain caller-owned.
- `MetricGrid` owns KPI/metric layout and responsive composition only; callers and metric components retain calculation, trust/status and business meaning.
- `StatCard` owns semantic KPI presentation only; report/domain calculations, priority classes and balance-sign truth remain caller-owned.
- Report-domain `MetricCard` continues to own report trust/freshness/status presentation semantics unless a separately bounded future decision proves equivalence.
- `ChartPanel` owns only neutral analytical surface/frame, semantic section hierarchy and chart-body containment; chart data, visualization semantics, trust/freshness, state decisions and business meaning remain caller-owned.
- `ResponsiveCollection` owns device renderer selection/orchestration only; collection data, business ordering, row meaning, actions and state copy remain caller-owned.
- `SubNav`, `SegmentedControl`, `DateField` and `Select -> Field` remain presentation/accessibility contracts only; route/filter/domain truth remains caller-owned.
- Dense management collections may intentionally remain semantic Desktop tables while Tablet/Mobile use deliberate shared-card composition from the same unchanged domain data.
- Canonical touch targets remain first-class through Tablet; Desktop may intentionally preserve denser pointer-oriented controls.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Durable decisions belong in the Decision Log; routine progress does not.
- No hosted CI, Vercel preview or `main` activity from scheduled agents.

## Known evidence / risks

- Development evidence through REPORT033 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions/status checks is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- REPORT034 is intentionally a roadmap-level placeholder and must be decomposed by Product Design into one smallest representative presentation concern before implementation.
- Remaining report tables, chart surfaces, dense responsive composition, loading/empty/error states, export/print and broader FilterBar grammar still need later bounded convergence; no business semantics may move into the Design System.
- Further Work detail/feedback/management convergence and Field create/detail convergence remain debt.
- Shared Pagination, FilterBar/search/filter convergence, DataTable keyboard/overflow semantics, SearchInput clear accessibility, error/offline-state convergence and dense-table overflow remain broader shared debt.
- Settings/Admin and global Dark/RTL/accessibility/legacy cleanup remain unstarted roadmap phases.

## Reusable patterns learned

- REPORT033 proves an existing report chart can retire a local analytical frame/header onto shared `ChartPanel -> Card + SectionHeader` without changing chart data, responsive sizing, visualization semantics or trust/freshness meaning.
- The shared ChartPanel contract can carry Arabic title/description plus a passive Trust/Freshness action cluster while preserving Mobile wrapping and shrink-safe containment.
- REPORT032 proves a five-metric report summary can retire a local KPI mini-system onto existing `MetricGrid columns={3}` + `StatCard` without adding a five-column shared mode or moving domain calculations into the Design System.
- Semantic tone mapping should express existing business meaning through the shared vocabulary while the caller retains classification and sign logic.
- Value-level loading can preserve metric identity/context instead of blanking the whole summary surface.
- REPORT031 proves a remaining report-header native date control can converge onto shared `DateField -> Input -> Field` without moving current-day/date-state/query semantics into the Design System or widening the shared contract.
- REPORT030/029/028/026/025/024/023/022/021/019 reinforce layout-only `MetricGrid` ownership across distinct metric counts and caller-owned report semantics.
- REPORT027 proves compact report-scope controls can converge from page-local native styling onto existing shared `Select` + `DateField` / `Field` grammar without moving filter/date/query meaning into shared components or widening shared APIs.
- REPORT020 and REPORT018/005/008-011/014 reinforce shared responsive collection and `ChartPanel` grammar without broad API/CSS widening.
- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared patterns should be proven on representative screens, then reused; legacy families should not be globally removed while live consumers remain.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect representative remaining Reports/Analytics surfaces on the exact latest `design-system-v2-development` baseline and record exactly one smallest dependency-safe REPORT034 presentation concern, including representative file/surface and explicit acceptance/exclusion boundary. Preserve REPORT001-033 contracts, all analytics/query/calculation/trust/permission/routing/export/print/backend/business semantics, and keep Settings/Admin, Global, remaining Work/Field and shared-component roadmap intact.

UI Production Engineer should bootstrap only after that boundary is recorded and implement one coherent concern from the exact then-current Development HEAD. Design QA should independently review the future exact stable PR HEAD. Development Integrator should no-op until a future PR receives fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and all normal gates pass.