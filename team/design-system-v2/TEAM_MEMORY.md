# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-028`.
- Current integrated product merge: `337cf967ab1159968866811be194aec359c43f66` from PR #76.
- Exact reviewed implementation HEAD: `cd7ac87d0839a7e7706858afb4efbdea2025ff8e`.
- Current single READY roadmap item: `DS2-REPORT-029 — Next bounded Reports metrics/charts/tables/responsive-composition convergence`.
- Product Design Director must inspect the exact latest Development baseline and bound exactly one smallest dependency-safe presentation-only REPORT029 concern before UI Production begins.
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
- shared V2 Field grammar proven for compact report-scope risk/date controls in Churn Risk while filter/date/query truth remains caller-owned;
- shared `MetricGrid` proofs across Overview, Receivables, Rep Credit Commitment, Sales, Treasury, Customer Health, Product Performance and Profitability summary clusters while report-domain/business meaning remains caller-owned;
- Product Performance, Customer Health, Churn Risk, Geography, Rep Performance, Target Attainment and Visit Reports detail collections use shared responsive collection grammar while preserving dense semantic Desktop tables;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-REPORT-028 — Profit Dashboard summary metric-grid convergence`

Result:
- PR #76 exact reviewed HEAD `cd7ac87d0839a7e7706858afb4efbdea2025ff8e` received `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- Product Design independently accepted the same exact HEAD with `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Evidence remains honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview/release PASS is claimed.
- Squash merge commit: `337cf967ab1159968866811be194aec359c43f66`.
- ProfitDashboard's four-card KPI summary now consumes existing shared `MetricGrid columns={4}` instead of the page-local `report-grid` wrapper.
- Exact KPI order/content/calculations remain unchanged and caller-owned: net revenue, COGS, gross profit, operating+payroll expenses, plus the existing gross-margin secondary value/copy.
- Existing `isLoading ? '...'` behavior, `overviewTrust` status/completion/stale wiring, `domain="profit_overview"`, icons and local PackageIcon remain unchanged.
- Existing shared composition supplies Desktop 4 / Tablet 2 / Mobile 1 with minmax-safe containment while established `MetricCard` handling preserves Arabic/RTL and large-number containment.
- `ReportFilterBar`, date/query inputs and the separate `report-grid-2` final-net-profit surface remain outside the converged grid and unchanged.
- No shared API/CSS/token/breakpoint widening, backend/functional change or deployment/workflow change occurred.

## Current single READY roadmap item

`DS2-REPORT-029 — Next bounded Reports metrics/charts/tables/responsive-composition convergence`

Intent:
- Product Design Director inspects representative remaining Reports/Analytics surfaces on the exact latest Development baseline before implementation;
- select exactly one smallest dependency-safe presentation-only concern and name its representative surface/file plus explicit acceptance/exclusion boundary;
- prefer existing shared V2 primitives/patterns, or strengthen a shared contract only when a real consumer demonstrates the need;
- preserve REPORT001-028 contracts and all analytics/query/calculation/trust/permission/RBAC/RLS/routing/export/print/backend/business semantics;
- preserve Settings/Admin, Global convergence, remaining Work and Field debt and shared component-depth work in the roadmap;
- do not turn REPORT029 into broad multi-page report beautification.

Implementation is not authorized until Product Design records the exact bounded concern from the then-current Development HEAD.

## Latest role positions

### Product Design Director
- Accepted PR #76 exact HEAD `cd7ac87d0839a7e7706858afb4efbdea2025ff8e` with `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Confirmed REPORT028 is wrapper-only system convergence: shared MetricGrid owns layout while Profitability values, trust, loading, filter/query truth and final-profit presentation remain caller-owned.
- Next responsibility is to inspect the exact latest Development baseline and bound one smallest safe REPORT029 concern.

### UI Production Engineer
- REPORT028 implementation is integrated.
- Focused ProfitDashboard tests remain `TESTS_AUTHORED_NOT_EXECUTED`.
- The integrated implementation preserves exact KPI order/value/calculation/loading/trust/domain/icon/secondary-margin behavior while consuming shared `MetricGrid columns={4}` unchanged.
- Must not begin REPORT029 product code until Product Design records the exact boundary from the latest Development HEAD.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` on `cd7ac87d0839a7e7706858afb4efbdea2025ff8e` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Found no known source-visible build/type blocker, material review thread, functional-isolation breach or deployment/workflow drift on the merged exact HEAD.
- That approval is consumed by the merge and cannot be reused for REPORT029.

### Development Integrator
- Revalidated PR #76 base/head, exact-head QA and Product Design gates, empty review threads, three-file UI/Test/Governance scope, governance-only Development drift, mergeability and functional isolation.
- Transitioned the Draft PR to Ready without moving its HEAD and squash-merged with expected-head protection as `337cf967ab1159968866811be194aec359c43f66`.
- Marked REPORT028 DONE and advanced exactly one roadmap item, REPORT029, to READY for Product Design bounding.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Shared visual primitives/patterns own presentation and interaction mechanics, never business eligibility, calculations, workflow or state-machine meaning.
- `Field`, `Select`, `Input` and `DateField` own presentation/accessibility/control mechanics only; filter values, date semantics and query inputs remain caller-owned.
- `MetricGrid` owns KPI/metric layout and responsive composition only; callers and metric components retain calculation, trust/status and business meaning.
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

- Development evidence through REPORT028 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions/status checks is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- REPORT029 is intentionally a roadmap-level placeholder and must be decomposed by Product Design into one smallest representative presentation concern before implementation.
- Remaining report tables, chart surfaces, dense responsive composition, loading/empty/error states, export/print and broader FilterBar grammar still need later bounded convergence; no business semantics may move into the Design System.
- Further Work detail/feedback/management convergence and Field create/detail convergence remain debt.
- Shared Pagination, FilterBar/search/filter convergence, DataTable keyboard/overflow semantics, SearchInput clear accessibility, error/offline-state convergence and dense-table overflow remain broader shared debt.
- Settings/Admin and global Dark/RTL/accessibility/legacy cleanup remain unstarted roadmap phases.

## Reusable patterns learned

- REPORT028 reinforces layout-only `MetricGrid` ownership on a profitability surface while preserving card-level loading/trust semantics and a distinct downstream highlight outside the shared grid.
- REPORT027 proves compact report-scope controls can converge from page-local native styling onto existing shared `Select` + `DateField` / `Field` grammar without moving filter/date/query meaning into shared components or widening shared APIs.
- REPORT026/025/024/023/022/021/019 establish layout-only `MetricGrid` ownership across distinct metric counts and caller-owned report semantics.
- REPORT020 extends `ResponsiveCollection + Card + KeyValueList` to a ten-fact, two-mode Visit Reports surface while preserving a dense Desktop table and caller-owned loading/error/empty/pagination.
- REPORT018 and REPORT005/008-011/014 establish `ChartPanel` as system-level rather than page-specific without API/CSS/token widening.
- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared patterns should be proven on representative screens, then reused; legacy families should not be globally removed while live consumers remain.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect representative remaining Reports/Analytics surfaces on the exact latest `design-system-v2-development` baseline and record exactly one smallest dependency-safe REPORT029 presentation concern, including representative file/surface and explicit acceptance/exclusion boundary. Preserve REPORT001-028 contracts, all analytics/query/calculation/trust/permission/routing/export/print/backend/business semantics, and keep Settings/Admin, Global, remaining Work/Field and shared-component roadmap intact.

UI Production Engineer should bootstrap only after that boundary is recorded and implement one coherent concern from the exact then-current Development HEAD. Design QA should independently review the future exact stable PR HEAD. Development Integrator should no-op until a future PR receives fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and all normal gates pass.