# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-020`.
- Current integrated product merge: `92d0091fcd34980a4e91c6626135931a18a199b9` from PR #68.
- Exact reviewed implementation HEAD: `9e922249b905bc940534273d658ee817185f3c4a`.
- Development coordination HEAD immediately before this Team Memory write: `db6f0a0a99522bdf1ed70b65b11c1dc98a4344d5`.
- Current single READY roadmap item: `DS2-REPORT-021 — Next bounded Reports metrics/charts/tables/responsive-composition convergence`.
- Product Design Director must inspect the exact latest Development baseline and bound exactly one smallest dependency-safe presentation-only REPORT021 concern before UI Production begins.
- `main` remains frozen until explicit owner approval.
- Vercel preview remains user-requested only.
- GitHub Actions / hosted CI remain forbidden for normal Design System development.
- Product target remains one deep, premium Arabic-first operational Design System across the entire EDARA interface.
- Mobile is the primary daily operational surface; Tablet is deliberate and touch-first; Desktop preserves management/review/data-entry density and speed.

## Current integrated system

Development now includes:
- semantic foundations and V2 primitives/patterns;
- responsive shell/navigation/form/collection/action composition foundations;
- Dashboard V2 and representative Customers, Sales, Inventory, Procurement, Finance, HR and Field migrations;
- Work Create Task shared form composition, Work Hub shared `SegmentedControl`, and Supervisor Work shared `MetricGrid + StatCard`;
- Reports route-level `SubNav`, date-preset `SegmentedControl`, shared native `DateField`, Geography `Select -> Field`, and Overview `MetricGrid` convergence;
- domain-agnostic `ChartPanel` reuse across Sales, Receivables, Churn Risk, Product Performance, Rep Performance and Treasury analytical surfaces;
- Product Performance, Customer Health, Churn Risk, Geography, Rep Performance, Target Attainment and Visit Reports detail collections converged onto shared `ResponsiveCollection`, preserving dense semantic Desktop tables and deliberate Tablet/Mobile `Card + KeyValueList` composition from the same caller-owned domain truth;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-REPORT-020 — Visit Reports responsive detail-collection convergence`

Result:
- PR #68 exact reviewed HEAD `9e922249b905bc940534273d658ee817185f3c4a` received `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- Product Design independently accepted the same exact HEAD with `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Evidence remains honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview/release PASS is claimed.
- Squash merge commit: `92d0091fcd34980a4e91c6626135931a18a199b9`.
- Visit Reports `VisitRowsTable` keeps the dense ten-column semantic table on Desktop and adds `scope="col"` to all headers.
- Tablet uses one two-column passive `Card + KeyValueList` tree; Mobile uses one one-column passive tree with safe Arabic wrapping and deliberate LTR treatment for date/code/duration.
- All ten facts/order remain intact in both modes: normal mode keeps duration + started-at; quality mode keeps exception reasons/order/fallback.
- Existing status/GPS/recording semantics, plan/activity destinations, native-link behavior and caller-owned loading/error/empty/pagination remain unchanged.
- No shared API/CSS/token widening and no query/cache/data-shaping/permission/RBAC/RLS/routing/export/backend/service/validation/workflow/business drift occurred.

## Current single READY roadmap item

`DS2-REPORT-021 — Next bounded Reports metrics/charts/tables/responsive-composition convergence`

Intent:
- Product Design Director inspects representative remaining Reports/Analytics surfaces on the exact latest Development baseline before implementation;
- select exactly one smallest dependency-safe presentation-only concern and name its representative surface/file plus explicit acceptance/exclusion boundary;
- prefer existing shared V2 primitives/patterns, or strengthen a shared contract only when a real consumer demonstrates the need;
- preserve REPORT001-020 contracts and all analytics/query/calculation/trust/permission/RBAC/RLS/routing/export/print/business semantics;
- preserve Settings/Admin, Global convergence, remaining Work and Field debt and shared component-depth work in the roadmap;
- do not turn REPORT021 into broad multi-page report beautification.

Implementation is not authorized until Product Design records the exact bounded concern from the then-current Development HEAD.

## Latest role positions

### Product Design Director
- Accepted PR #68 exact HEAD `9e922249b905bc940534273d658ee817185f3c4a` with `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Confirmed REPORT020 preserves dense Desktop comparison while compact devices reuse the established single-renderer responsive collection grammar without moving business meaning into the Design System.
- Next responsibility is to inspect the exact latest Development baseline and bound one smallest safe REPORT021 concern.

### UI Production Engineer
- REPORT020 implementation is integrated.
- Focused Visit Reports tests remain `TESTS_AUTHORED_NOT_EXECUTED`.
- The integrated implementation preserves exact facts/modes/links/state contracts while consuming `ResponsiveCollection + Card + KeyValueList` unchanged.
- Must not begin REPORT021 product code until Product Design records the exact boundary from the latest Development HEAD.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` on `9e922249b905bc940534273d658ee817185f3c4a` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Found no known source-visible build/type blocker, material review thread, functional-isolation breach or deployment/workflow drift on the merged exact HEAD.
- That approval is consumed by the merge and cannot be reused for REPORT021.

### Development Integrator
- Revalidated PR #68 base/head, exact-head QA and Product Design gates, empty review threads, three-file UI/Test/Governance scope, governance-only Development drift, mergeability and functional isolation.
- Transitioned the Draft PR to Ready without moving its HEAD and squash-merged with expected-head protection as `92d0091fcd34980a4e91c6626135931a18a199b9`.
- Marked REPORT020 DONE and advanced exactly one roadmap item, REPORT021, to READY for Product Design bounding.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Customer, Sales, Inventory, Procurement, Finance, HR, Field, Work and Reports business/query/permission/workflow truths remain page/domain/service-owned.
- Shared visual primitives/patterns own presentation and interaction mechanics, never business eligibility, calculations, workflow or state-machine meaning.
- `SubNav` owns secondary-navigation presentation/interaction mechanics only; callers own destination eligibility and route/business meaning.
- `MetricGrid` owns KPI/metric layout and responsive composition only; callers and metric components retain calculation, trust/status and business meaning.
- Report-domain `MetricCard` continues to own report trust/freshness/status presentation semantics unless a separately bounded future decision proves equivalence.
- `SegmentedControl` owns compact single-choice presentation only; callers retain selected value and domain meaning.
- `DateField` owns native date-input presentation/accessibility plumbing only; parsing, normalization, range ordering, timezone and business meaning remain caller-owned.
- `Select -> Field` owns native select presentation/accessibility/geometry only; selected values, state transitions, filter/query meaning and domain semantics remain caller-owned.
- `ChartPanel` owns only neutral analytical surface/frame, semantic section hierarchy and chart-body containment; chart data, visualization semantics, trust/freshness, state decisions and business meaning remain caller-owned.
- `ResponsiveCollection` owns device renderer selection/orchestration only; collection data, business ordering, row meaning, actions and state copy remain caller-owned.
- REPORT006, REPORT012, REPORT013, REPORT015, REPORT016, REPORT017 and REPORT020 now prove the same responsive-collection grammar across seven distinct Reports row shapes while preserving dense Desktop comparison and deliberate Tablet/Mobile cards with exactly one renderer mounted.
- REPORT020 additionally proves that a mode-dependent fact slot can remain caller-owned while Desktop and compact renderers share the exact same domain truth and link/state semantics.
- Rank-derived visual emphasis must not leak into unrelated financial/status meaning; REPORT016 preserves ranking emphasis while revenue stays neutral/default.
- Dense management collections may intentionally remain semantic Desktop tables while Tablet/Mobile use deliberate shared-card composition from the same unchanged domain data.
- Canonical touch targets remain first-class through Tablet; Desktop may intentionally preserve denser pointer-oriented controls.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Durable decisions belong in the Decision Log; routine progress does not.
- No hosted CI, Vercel preview or `main` activity from scheduled agents.

## Known evidence / risks

- Development evidence through REPORT020 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions/status checks is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- REPORT021 is intentionally a roadmap-level placeholder and must be decomposed by Product Design into one smallest representative presentation concern before implementation.
- Remaining report tables, chart surfaces, dense responsive composition, loading/empty/error states, export/print and broader FilterBar grammar still need later bounded convergence; no business semantics may move into the Design System.
- Further Work detail/feedback/management convergence and Field create/detail convergence remain debt.
- Shared Pagination, FilterBar/search/filter convergence, DataTable keyboard/overflow semantics, SearchInput clear accessibility, error/offline-state convergence and dense-table overflow remain broader shared debt.
- Settings/Admin and global Dark/RTL/accessibility/legacy cleanup remain unstarted roadmap phases.

## Reusable patterns learned

- REPORT020 extends `ResponsiveCollection + Card + KeyValueList` to a ten-fact, two-mode Visit Reports surface while preserving a dense Desktop table, exact native drill-down links and caller-owned loading/error/empty/pagination.
- Mode-specific content does not require a new shared API when the caller can supply the same fact slot to each renderer while retaining business semantics locally.
- REPORT019 proves an additional Overview summary cluster can move to shared `MetricGrid` while preserving report `MetricCard` trust/status semantics and a separate loading branch unchanged.
- REPORT018 and REPORT005/008-011/014 establish `ChartPanel` as system-level rather than page-specific without API/CSS/token widening.
- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared patterns should be proven on representative screens, then reused; legacy families should not be globally removed while live consumers remain.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect representative remaining Reports/Analytics surfaces on the exact latest `design-system-v2-development` baseline and record exactly one smallest dependency-safe REPORT021 presentation concern, including representative file/surface and explicit acceptance/exclusion boundary. Preserve REPORT001-020 contracts, all analytics/query/calculation/trust/permission/routing/export/print/business semantics, and keep Settings/Admin, Global, remaining Work/Field and shared-component roadmap intact.

UI Production Engineer should bootstrap only after that boundary is recorded and implement one coherent concern from the exact then-current Development HEAD. Design QA should independently review the future exact stable PR HEAD. Development Integrator should no-op until a future PR receives fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and all normal gates pass.