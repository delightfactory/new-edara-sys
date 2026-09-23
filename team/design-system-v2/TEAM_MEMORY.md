# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-034`.
- Current integrated product HEAD / squash merge: `7ba36015798df5d4aa615077adade862687a6f9c` from PR #82.
- Exact reviewed implementation HEAD: `8bec856b57aff490092c68b948fdac52078c2bf2`.
- Current single READY roadmap item: `DS2-REPORT-035 — Next bounded Reports metrics/charts/tables/responsive-composition convergence`.
- REPORT035 is intentionally unbounded: Product Design Director must inspect the exact latest Development baseline and record exactly one smallest dependency-safe presentation-only concern before UI Production begins.
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
- shared `MetricGrid` proofs across Overview, Receivables, Rep Credit Commitment, Sales, Treasury, Customer Health, Product Performance, Profitability, Geography, Rep Performance, Customer Re-engagement and now Churn Risk summary clusters while report-domain/business meaning remains caller-owned;
- shared `ChartPanel` analytical-surface grammar proven across representative report surfaces while chart data/visualization semantics remain caller-owned;
- representative report detail collections using shared responsive collection grammar while preserving dense semantic Desktop tables;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-REPORT-034 — Churn Risk KPI summary shared metric convergence`

Result:
- PR #82 exact reviewed HEAD `8bec856b57aff490092c68b948fdac52078c2bf2` received `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- Product Design independently closed out the same exact HEAD as `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Evidence remains honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview/release PASS is claimed.
- Squash merge commit: `7ba36015798df5d4aa615077adade862687a6f9c`.
- Churn Risk's five-card page-local KPI mini-system now consumes existing `MetricGrid columns={3}` + passive `StatCard` without shared-contract widening.
- Exact metric order remains `VIP → مخلص → متفاعل → معرض للخطر → خامد`.
- Exact caller-owned sources `stats.vip / stats.loyal / stats.engaged / stats.at_risk / stats.dormant`, `FMT.format(...)`, `—` fallback and `statsLoading` gate remain unchanged.
- Semantic tones use the shared vocabulary `neutral / success / info / warning / danger`; category identity remains text-visible rather than color-only.
- Loading remains exactly five `SkeletonCard height={120}` placeholders.
- Shared composition yields Desktop `3+2`, Tablet `2+2+1`, Mobile one column with existing shrink-safe containment.
- Header/filter/date controls, System Health, RFM/category identity, RiskBadge/RecencyCell, pie ChartPanel/Trust-Freshness, responsive detail, queries/calculations/permissions/export/print/backend/business behavior and shared APIs/CSS/tokens/breakpoints remain unchanged.

## Current single READY roadmap item

`DS2-REPORT-035 — Next bounded Reports metrics/charts/tables/responsive-composition convergence`

Intent:
- Product Design Director inspects representative remaining Reports/Analytics surfaces on the exact latest Development baseline before implementation;
- select exactly one smallest dependency-safe presentation-only concern and name its representative surface/file plus explicit acceptance/exclusion boundary;
- prefer existing shared V2 primitives/patterns, or strengthen a shared contract only when a real consumer demonstrates the need;
- preserve REPORT001-034 contracts and all analytics/query/calculation/trust/permission/RBAC/RLS/routing/export/print/backend/business semantics;
- preserve Settings/Admin, Global convergence, remaining Work and Field debt and shared component-depth work in the roadmap;
- do not turn REPORT035 into broad multi-page report beautification.

Implementation is not authorized until Product Design records the exact bounded concern from the then-current Development HEAD.

## Latest role positions

### Product Design Director
- Independently accepted REPORT034 exact PR HEAD `8bec856b57aff490092c68b948fdac52078c2bf2` as `PASS — NO DESIGN-SYSTEM BLOCKER`.
- No current `BLOCKING` contradiction exists.
- Next responsibility is to inspect the exact latest Development baseline and bound one smallest safe REPORT035 concern.

### UI Production Engineer
- REPORT034 implementation is integrated.
- Focused Churn Risk metric-summary tests remain `TESTS_AUTHORED_NOT_EXECUTED`.
- The integrated implementation preserves risk order/value/loading/domain semantics while consuming shared `MetricGrid` + `StatCard` unchanged.
- Must not begin REPORT035 product code until Product Design records the exact boundary from the latest Development HEAD.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` on `8bec856b57aff490092c68b948fdac52078c2bf2` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Found no known source-visible build/type blocker, material review thread, functional-isolation breach or deployment/workflow drift on the merged exact HEAD.
- That approval is consumed by the merge and cannot be reused for REPORT035.

### Development Integrator
- Revalidated PR #82 base/head, exact-head QA gate, exact-head Product Design closeout, empty review threads, three-file UI/Test/Governance scope, governance-only Development drift, mergeability and functional isolation.
- Transitioned the Draft PR to Ready without moving its HEAD and squash-merged with expected-head protection as `7ba36015798df5d4aa615077adade862687a6f9c`.
- Marked REPORT034 DONE and advanced exactly one roadmap item, REPORT035, to READY for Product Design bounding.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Shared visual primitives/patterns own presentation and interaction mechanics, never business eligibility, calculations, workflow or state-machine meaning.
- `Field`, `Select`, `Input` and `DateField` own presentation/accessibility/control mechanics only; filter values, date semantics and query inputs remain caller-owned.
- `MetricGrid` owns KPI/metric layout and responsive composition only; callers and metric components retain calculation, trust/status and business meaning.
- `StatCard` owns semantic KPI presentation only; report/domain calculations, category classification and sign/risk truth remain caller-owned.
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

- Development evidence through REPORT034 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions/status checks is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- REPORT035 is intentionally a roadmap-level placeholder and must be decomposed by Product Design into one smallest representative presentation concern before implementation.
- Remaining report tables, chart surfaces, dense responsive composition, loading/empty/error states, export/print and broader FilterBar grammar still need later bounded convergence; no business semantics may move into the Design System.
- Further Work detail/feedback/management convergence and Field create/detail convergence remain debt.
- Shared Pagination, FilterBar/search/filter convergence, DataTable keyboard/overflow semantics, SearchInput clear accessibility, error/offline-state convergence and dense-table overflow remain broader shared debt.
- Settings/Admin and global Dark/RTL/accessibility/legacy cleanup remain unstarted roadmap phases.

## Reusable patterns learned

- REPORT034 proves a category-oriented five-metric report summary can retire arbitrary page-local KPI grid/card styling onto existing `MetricGrid columns={3}` + `StatCard` without moving category classification or report-domain truth into the Design System.
- Shared semantic tones can support business categories while explicit text labels retain primary meaning and color remains secondary.
- Five passive metrics do not require a bespoke five-column shared mode; the established Desktop `3+2`, Tablet `2+2+1`, Mobile `1` composition remains sufficient and more coherent.
- Loading-state identity should stay structurally aligned with the shared metric grid rather than use a different page-local layout.
- REPORT033 proves an existing report chart can retire a local analytical frame/header onto shared `ChartPanel -> Card + SectionHeader` without changing chart data, responsive sizing, visualization semantics or trust/freshness meaning.
- REPORT032 proves a five-metric report summary can retire a local KPI mini-system onto existing `MetricGrid columns={3}` + `StatCard` without adding a five-column shared mode or moving domain calculations into the Design System.
- REPORT031 proves a remaining report-header native date control can converge onto shared `DateField -> Input -> Field` without moving current-day/date-state/query semantics into the Design System or widening the shared contract.
- REPORT030/029/028/026/025/024/023/022/021/019 reinforce layout-only `MetricGrid` ownership across distinct metric counts and caller-owned report semantics.
- REPORT027 proves compact report-scope controls can converge from page-local native styling onto existing shared `Select` + `DateField` / `Field` grammar without moving filter/date/query meaning into shared components or widening shared APIs.
- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared patterns should be proven on representative screens, then reused; legacy families should not be globally removed while live consumers remain.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect representative remaining Reports/Analytics surfaces on the exact latest `design-system-v2-development` baseline and record exactly one smallest dependency-safe REPORT035 presentation concern, including representative file/surface and explicit acceptance/exclusion boundary. Preserve REPORT001-034 contracts, all analytics/query/calculation/trust/permission/routing/export/print/backend/business semantics, and keep Settings/Admin, Global, remaining Work/Field and shared-component roadmap intact.

UI Production Engineer should bootstrap only after that boundary is recorded and implement one coherent concern from the exact then-current Development HEAD. Design QA should independently review the future exact stable PR HEAD. Development Integrator should no-op until a future PR receives fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and all normal gates pass.