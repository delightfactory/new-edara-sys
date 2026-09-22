# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-026`.
- Current integrated product merge: `9ac63ca20baaeefa6fe5cb3e87a9734f59847ac5` from PR #74.
- Exact reviewed implementation HEAD: `f3b2386130924ee375f1912190a6ad82befe0065`.
- Current single READY roadmap item: `DS2-REPORT-027 — Next bounded Reports metrics/charts/tables/responsive-composition convergence`.
- Product Design Director must inspect the exact latest Development baseline and bound exactly one smallest dependency-safe presentation-only REPORT027 concern before UI Production begins.
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
- Reports route-level `SubNav`, date-preset `SegmentedControl`, shared native `DateField`, Geography `Select -> Field`, shared `ChartPanel`, shared `MetricGrid`, and `ResponsiveCollection + Card + KeyValueList` convergence across representative analytics surfaces;
- shared `MetricGrid` proofs across Overview, Receivables, Rep Credit Commitment, Sales, Treasury, Customer Health and Product Performance summary clusters while report-domain/business meaning remains caller-owned;
- Product Performance, Customer Health, Churn Risk, Geography, Rep Performance, Target Attainment and Visit Reports detail collections use shared responsive collection grammar while preserving dense semantic Desktop tables;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-REPORT-026 — Product Performance summary metric-grid convergence`

Result:
- PR #74 exact reviewed HEAD `f3b2386130924ee375f1912190a6ad82befe0065` received `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- Product Design independently accepted the same exact HEAD with `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Evidence remains honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview/release PASS is claimed.
- Squash merge commit: `9ac63ca20baaeefa6fe5cb3e87a9734f59847ac5`.
- Product Performance's four-card KPI summary now uses existing shared `MetricGrid columns={4}` instead of page-local `report-grid` composition.
- Desktop remains four columns, Tablet uses the shared two-column composition, and Mobile uses the shared one-column stack.
- Exact card order `إجمالى الإيراد` → `منتجات نشطة` → `أعلى منتج` → `متوسط نسبة المرتجع`, labels, subtitles, values, `fmtCur` / `fmtPct`, `salesTrust` status/freshness/stale wiring, `domain="sales"`, icons and caller-owned `avgReturnRate` remain unchanged.
- `isLoading = summaryLoading || tableLoading` remains unchanged with exactly four `SkeletonCard height={160}` summary placeholders.
- REPORT011 Product Performance `ChartPanel` and REPORT006 responsive detail collection remain unchanged.
- No shared API/CSS/token/breakpoint widening or deployment/workflow change occurred.

## Current single READY roadmap item

`DS2-REPORT-027 — Next bounded Reports metrics/charts/tables/responsive-composition convergence`

Intent:
- Product Design Director inspects representative remaining Reports/Analytics surfaces on the exact latest Development baseline before implementation;
- select exactly one smallest dependency-safe presentation-only concern and name its representative surface/file plus explicit acceptance/exclusion boundary;
- prefer existing shared V2 primitives/patterns, or strengthen a shared contract only when a real consumer demonstrates the need;
- preserve REPORT001-026 contracts and all analytics/query/calculation/trust/permission/RBAC/RLS/routing/export/print/backend/business semantics;
- preserve Settings/Admin, Global convergence, remaining Work and Field debt and shared component-depth work in the roadmap;
- do not turn REPORT027 into broad multi-page report beautification.

Implementation is not authorized until Product Design records the exact bounded concern from the then-current Development HEAD.

## Latest role positions

### Product Design Director
- Accepted PR #74 exact HEAD `f3b2386130924ee375f1912190a6ad82befe0065` with `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Confirmed REPORT026 is a narrow system-convergence move: shared responsive layout grammar only; Product Performance/report/business meaning stays caller-owned.
- Next responsibility is to inspect the exact latest Development baseline and bound one smallest safe REPORT027 concern.

### UI Production Engineer
- REPORT026 implementation is integrated.
- Focused Product Performance tests remain `TESTS_AUTHORED_NOT_EXECUTED`.
- The integrated implementation preserves exact summary/loading plus complete REPORT011 ChartPanel and REPORT006 responsive-detail behavior while consuming `MetricGrid` unchanged.
- Must not begin REPORT027 product code until Product Design records the exact boundary from the latest Development HEAD.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` on `f3b2386130924ee375f1912190a6ad82befe0065` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Found no known source-visible build/type blocker, material review thread, functional-isolation breach or deployment/workflow drift on the merged exact HEAD.
- That approval is consumed by the merge and cannot be reused for REPORT027.

### Development Integrator
- Revalidated PR #74 base/head, exact-head QA and Product Design gates, empty review threads, three-file UI/Test/Governance scope, governance-only Development drift, mergeability and functional isolation.
- Transitioned the Draft PR to Ready without moving its HEAD and squash-merged with expected-head protection as `9ac63ca20baaeefa6fe5cb3e87a9734f59847ac5`.
- Marked REPORT026 DONE and advanced exactly one roadmap item, REPORT027, to READY for Product Design bounding.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Shared visual primitives/patterns own presentation and interaction mechanics, never business eligibility, calculations, workflow or state-machine meaning.
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

- Development evidence through REPORT026 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions/status checks is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- REPORT027 is intentionally a roadmap-level placeholder and must be decomposed by Product Design into one smallest representative presentation concern before implementation.
- Remaining report tables, chart surfaces, dense responsive composition, loading/empty/error states, export/print and broader FilterBar grammar still need later bounded convergence; no business semantics may move into the Design System.
- Further Work detail/feedback/management convergence and Field create/detail convergence remain debt.
- Shared Pagination, FilterBar/search/filter convergence, DataTable keyboard/overflow semantics, SearchInput clear accessibility, error/offline-state convergence and dense-table overflow remain broader shared debt.
- Settings/Admin and global Dark/RTL/accessibility/legacy cleanup remain unstarted roadmap phases.

## Reusable patterns learned

- REPORT026 adds Product Performance to the proven family where a page-local KPI wrapper converges onto shared `MetricGrid` without moving report-domain `MetricCard`, trust/freshness or analytical meaning into the Design System; adjacent REPORT011 ChartPanel and REPORT006 responsive-detail contracts remain fully isolated.
- REPORT025/024/023/022/021/019 establish the same layout-only MetricGrid ownership across distinct metric counts and caller-owned report semantics.
- REPORT020 extends `ResponsiveCollection + Card + KeyValueList` to a ten-fact, two-mode Visit Reports surface while preserving a dense Desktop table and caller-owned loading/error/empty/pagination.
- REPORT018 and REPORT005/008-011/014 establish `ChartPanel` as system-level rather than page-specific without API/CSS/token widening.
- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared patterns should be proven on representative screens, then reused; legacy families should not be globally removed while live consumers remain.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect representative remaining Reports/Analytics surfaces on the exact latest `design-system-v2-development` baseline and record exactly one smallest dependency-safe REPORT027 presentation concern, including representative file/surface and explicit acceptance/exclusion boundary. Preserve REPORT001-026 contracts, all analytics/query/calculation/trust/permission/routing/export/print/backend/business semantics, and keep Settings/Admin, Global, remaining Work/Field and shared-component roadmap intact.

UI Production Engineer should bootstrap only after that boundary is recorded and implement one coherent concern from the exact then-current Development HEAD. Design QA should independently review the future exact stable PR HEAD. Development Integrator should no-op until a future PR receives fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and all normal gates pass.