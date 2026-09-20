# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-011`.
- Current integrated product merge: `9433ec1623a812d1b47d93bffad7e1c537caaa91` from PR #58.
- Exact reviewed implementation HEAD: `58927873f328172025f60da7c6b6d3fa3ecbcefa`.
- Current single READY roadmap item: `DS2-REPORT-012 — Next bounded Reports metrics/charts/tables/responsive-composition convergence`.
- Product Design Director must inspect the exact latest Development baseline and bound exactly one smallest dependency-safe presentation-only REPORT012 concern before UI Production begins.
- `main` remains frozen until explicit owner approval.
- Vercel preview remains user-requested only.
- GitHub Actions / hosted CI remain forbidden for normal Design System development.
- Product target remains one deep, premium Arabic-first operational Design System across the entire EDARA interface.
- Mobile is the primary daily operational surface; Tablet is deliberate and touch-first; Desktop preserves management/review/data-entry density and speed.

## Current integrated system

Development now includes:
- semantic foundations and V2 primitives/patterns;
- responsive shell/navigation/form/collection/action composition foundations;
- Dashboard V2;
- Customers, Sales, Inventory, Procurement, Finance, HR and Field representative V2 migrations;
- Work Create Task form convergence using shared form composition;
- Work Hub view-mode convergence using shared `SegmentedControl`;
- Supervisor Work operational summary convergence using shared `MetricGrid + StatCard`;
- Reports route-level secondary navigation convergence using shared `SubNav`;
- Reports date-preset selector convergence using shared `SegmentedControl`;
- shared `SegmentedControl` long-content geometry hardening;
- shared presentation-only V2 `DateField` adopted by report custom-date editors;
- Reports Overview primary KPI-summary layout convergence onto shared `MetricGrid columns={4}` while report-domain `MetricCard` retains trust/freshness semantics;
- shared domain-agnostic V2 `ChartPanel` over `Card + SectionHeader`, semantic `h2` by default, now proven across Sales, Receivables, Churn Risk and Product Performance analytical surfaces;
- Product Performance detail collection convergence onto shared `ResponsiveCollection`, preserving a dense semantic Desktop table and deliberate Tablet/Mobile `Card + KeyValueList` composition;
- Geography analysis-level control convergence from a raw page-local select to shared `Select -> Field`, with report-domain state/filter meaning preserved;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-REPORT-011 — Product Performance revenue chart-panel convergence`

Result:
- PR #58 exact reviewed HEAD `58927873f328172025f60da7c6b6d3fa3ecbcefa` received `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- Product Design independently accepted the same exact HEAD with `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Evidence remains honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview/release PASS is claimed.
- Squash merge commit: `9433ec1623a812d1b47d93bffad7e1c537caaa91`.
- Only Product Performance chart section `أعلى 15 منتجاً بالإيراد` moved from a page-local analytical surface/header shell to the existing shared `ChartPanel`.
- Exact Arabic title/description, `salesTrust` action-presence rule, loading/empty/data 240px states, `chartData`, BarChart margins/grid/axes/tooltip/revenue Bar configuration remain unchanged and caller-owned.
- REPORT006 responsive detail collection, page header, category selector, filters, KPI cards, hooks, category RPC, query/cache, trust calculations, permissions, routing, export/print and business semantics remain unchanged.
- No shared `ChartPanel` API/CSS widening, Recharts abstraction, second report/page, backend/business/query/permission/deployment/workflow change entered the slice.

## Current single READY roadmap item

`DS2-REPORT-012 — Next bounded Reports metrics/charts/tables/responsive-composition convergence`

Intent:
- Product Design Director inspects representative remaining Reports/Analytics surfaces on the exact latest Development baseline before implementation;
- select exactly one smallest dependency-safe presentation-only concern and name its representative surface/file plus explicit acceptance boundary;
- prefer existing shared V2 primitives/patterns, or strengthen a shared contract only when a real consumer demonstrates the need;
- preserve REPORT001-011 contracts and all analytics/query/calculation/trust/permission/routing/export/print/business semantics;
- preserve Settings/Admin, Global convergence, remaining Work and Field debt and shared component-depth work in the roadmap;
- do not turn REPORT012 into broad multi-page report beautification.

Implementation is not authorized until Product Design records the exact bounded concern from the then-current Development HEAD.

## Latest role positions

### Product Design Director
- Accepted PR #58 exact HEAD `58927873f328172025f60da7c6b6d3fa3ecbcefa` with `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Confirmed one-page/one-chart scope, existing shared presentation-only `ChartPanel` fit, semantic `h2` hierarchy and preservation of all report-domain truth.
- Next responsibility is to inspect the exact latest Development baseline and bound one smallest safe REPORT012 concern.

### UI Production Engineer
- REPORT011 implementation is integrated.
- Focused Product Performance chart structural/state/chart-contract tests remain `TESTS_AUTHORED_NOT_EXECUTED`.
- The Development-branch UI state is lifecycle history after merge; UI Production must bootstrap from current shared memory/workstream before future implementation.
- Must not begin REPORT012 product code until Product Design records the exact boundary from the latest Development HEAD.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` on `58927873f328172025f60da7c6b6d3fa3ecbcefa` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Found no known source-visible build/type blocker, material review thread, functional-isolation breach or deployment/workflow drift on the merged implementation.
- That approval is consumed by the merge and cannot be reused for REPORT012.

### Development Integrator
- Revalidated PR #58 base/head, same-head QA and Product Design gates, empty review threads, three-file UI/Test/Governance scope, governance-only Development drift and functional isolation.
- Transitioned the Draft PR to Ready without moving its HEAD and squash-merged with expected-head protection as `9433ec1623a812d1b47d93bffad7e1c537caaa91`.
- Marked REPORT011 DONE and advanced exactly one roadmap item, REPORT012, to READY for Product Design bounding.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Customer, Sales, Inventory, Procurement, Finance, HR, Field, Work and Reports business/query/permission/workflow truths remain page/domain/service-owned.
- Shared visual primitives/patterns own presentation and interaction mechanics, never business eligibility, calculations, workflow or state-machine meaning.
- `SubNav` owns route-level secondary-navigation presentation/interaction mechanics only; callers own destination eligibility and route/business meaning.
- `MetricGrid` owns KPI layout/responsive composition only; callers retain calculation and business meaning.
- Report-domain `MetricCard` continues to own report trust/freshness/status presentation semantics unless a separately bounded future decision proves equivalence.
- `SegmentedControl` owns compact single-choice presentation only; callers retain selected value and domain meaning.
- `DateField` owns native date-input presentation/accessibility plumbing only; parsing, normalization, range ordering, timezone and business meaning remain caller-owned.
- `Select -> Field` owns native select presentation/accessibility/geometry only; selected values, state transitions, filter/query meaning and domain semantics remain caller-owned.
- `ChartPanel` owns only neutral analytical surface/frame, semantic section hierarchy and chart-body containment; chart data, visualization semantics, trust/freshness, state decisions and business meaning remain caller-owned.
- `ChartPanel` defaults to semantic `h2`; explicit `2 | 3 | 4` heading override remains for genuinely nested composition.
- REPORT008-011 prove cross-page, same-page and cross-visualization reuse of `ChartPanel` without shared API/CSS widening when caller-owned analytical semantics already fit the contract.
- `ResponsiveCollection` owns device renderer selection/orchestration only; collection data, business ordering, row meaning, actions and state copy remain caller-owned.
- Dense management collections may intentionally remain semantic Desktop tables while Tablet/Mobile use deliberate shared-card composition from the same unchanged domain data.
- Canonical touch targets remain first-class through Tablet; Desktop may intentionally preserve denser pointer-oriented controls.
- Mobile operational actions remain clear and touch-ready; Tablet must be deliberate; Desktop must remain efficient for management/review/data entry.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Durable decisions belong in the Decision Log; routine progress does not.
- No hosted CI, Vercel preview or `main` activity from scheduled agents.

## Known evidence / risks

- Development evidence through REPORT011 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions/status checks is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- REPORT012 is intentionally a roadmap-level placeholder and must be decomposed by Product Design into one smallest representative presentation concern before implementation.
- Report tables, later chart surfaces, dense responsive composition, loading/empty/error states, export/print and broader FilterBar grammar still need later bounded convergence; no business semantics may move into the Design System.
- Further Work detail/feedback/management convergence remains debt; remaining Field create/detail surfaces still need later bounded convergence.
- Full shared Pagination, FilterBar/search/filter convergence, DataTable keyboard/overflow semantics, SearchInput clear accessibility, error/offline-state convergence and dense-table overflow remain broader shared debt.
- Settings/Admin and global Dark/RTL/accessibility/legacy cleanup remain unstarted roadmap phases.

## Reusable patterns learned

- REPORT011 proves a fourth report surface can adopt the neutral `ChartPanel` directly while preserving page-owned loading/empty/data branching, trust-presence rules and complete BarChart semantics without shared API/CSS widening.
- REPORT010 proves the same neutral `ChartPanel` grammar can frame a Pie visualization while preserving caller-owned risk classification, trust presence, omission semantics and complete Pie/Recharts configuration.
- REPORT009 proves multiple analytical sections on the same report can share `ChartPanel` while preserving different caller-owned state/trust/chart semantics and body heights.
- REPORT008 proves a second report can adopt `ChartPanel` directly, preserving trust/freshness placement, explicit blocked/loading/empty/data states and complete Recharts semantics.
- REPORT007 proves a page-local raw native select can converge onto shared `Select -> Field` without moving controlled state, filter shape or report meaning into the Design System.
- REPORT006 proves a dense report collection can preserve its semantic Desktop table while Tablet/Mobile deliberately switch to shared `Card + KeyValueList` through `ResponsiveCollection`, without changing domain data or mounting duplicate renderers.
- Thin shared composites are preferred when the platform-native interaction model is already correct and the Design System only needs to own presentation/accessibility consistency.
- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared patterns should be proven on representative screens, then reused; legacy families should not be globally removed while live consumers remain.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect representative remaining Reports/Analytics surfaces on the exact latest `design-system-v2-development` baseline and record exactly one smallest dependency-safe REPORT012 presentation concern, including representative file/surface and explicit acceptance boundary. Preserve REPORT001-011 contracts, all analytics/query/calculation/business semantics, and keep Admin, Global, remaining Work and Field roadmap intact.

UI Production Engineer should bootstrap only after that boundary is recorded and implement one coherent concern from the exact then-current Development HEAD. Design QA should independently review the future exact stable PR HEAD. Development Integrator should no-op until a future PR receives fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and all normal gates pass.
