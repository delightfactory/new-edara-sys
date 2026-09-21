# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-015`.
- Current integrated product merge: `fae25c2962f01aefc988b3e3ec8e0532e1c491f8` from PR #63.
- Exact reviewed implementation HEAD: `b3667bb27f1cc2a37805f7f2fef4a8276230cf59`.
- Current single READY roadmap item: `DS2-REPORT-016 — Next bounded Reports metrics/charts/tables/responsive-composition convergence`.
- Product Design Director must inspect the exact latest Development baseline and bound exactly one smallest dependency-safe presentation-only REPORT016 concern before UI Production begins.
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
- representative Customers, Sales, Inventory, Procurement, Finance, HR and Field migrations;
- Work Create Task shared form composition, Work Hub shared `SegmentedControl`, and Supervisor Work shared `MetricGrid + StatCard`;
- Reports route-level `SubNav`, date-preset `SegmentedControl`, shared native `DateField`, Overview `MetricGrid`, Geography `Select -> Field`, and domain-agnostic `ChartPanel` reuse across multiple analytical surfaces;
- Product Performance, Customer Health, Churn Risk and Geography detail collections converged onto shared `ResponsiveCollection`, preserving dense semantic Desktop tables and deliberate Tablet/Mobile `Card + KeyValueList` composition from the same caller-owned domain data;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-REPORT-015 — Geography responsive detail-collection convergence`

Result:
- PR #63 exact reviewed HEAD `b3667bb27f1cc2a37805f7f2fef4a8276230cf59` received `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- Product Design independently accepted the same exact HEAD with `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Evidence remains honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview/release PASS is claimed.
- Squash merge commit: `fae25c2962f01aefc988b3e3ec8e0532e1c491f8`.
- Desktop preserves the dense dynamic Geography table, conditional parent column, revenue heatmap/zero-row/hover behavior and comparison density; headers add semantic `scope="col"`.
- Tablet uses two-column and Mobile one-column shared `Card + KeyValueList` composition through `ResponsiveCollection`, with exactly one renderer mounted per device.
- Long Arabic geography/parent names are wrap-safe; numeric money/count/share values retain intentional LTR presentation inside RTL composition.
- `useGeographyTable(filters)`, level/filter meaning, row source/order, conditional parent truth/fallback, Trust/Freshness, five × 44px loading rows, exact empty copy, formatting and all query/calculation/permission/routing/export/print/business semantics remain caller-owned and unchanged.
- No shared API/CSS widening occurred.

## Current single READY roadmap item

`DS2-REPORT-016 — Next bounded Reports metrics/charts/tables/responsive-composition convergence`

Intent:
- Product Design Director inspects representative remaining Reports/Analytics surfaces on the exact latest Development baseline before implementation;
- select exactly one smallest dependency-safe presentation-only concern and name its representative surface/file plus explicit acceptance boundary;
- prefer existing shared V2 primitives/patterns, or strengthen a shared contract only when a real consumer demonstrates the need;
- preserve REPORT001-015 contracts and all analytics/query/calculation/trust/permission/RBAC/RLS/routing/export/print/business semantics;
- preserve Settings/Admin, Global convergence, remaining Work and Field debt and shared component-depth work in the roadmap;
- do not turn REPORT016 into broad multi-page report beautification.

Implementation is not authorized until Product Design records the exact bounded concern from the then-current Development HEAD.

## Latest role positions

### Product Design Director
- Accepted PR #63 exact HEAD `b3667bb27f1cc2a37805f7f2fef4a8276230cf59` with `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Confirmed REPORT015 preserves the bounded Geography data/state/trust/device contract with no shared API/CSS widening.
- Next responsibility is to inspect the exact latest Development baseline and bound one smallest safe REPORT016 concern.

### UI Production Engineer
- REPORT015 implementation is integrated.
- Focused Geography tests remain `TESTS_AUTHORED_NOT_EXECUTED`.
- The integrated implementation preserves caller-owned Geography truth and existing shared responsive contracts.
- Must not begin REPORT016 product code until Product Design records the exact boundary from the latest Development HEAD.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` on `b3667bb27f1cc2a37805f7f2fef4a8276230cf59` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Found no known source-visible build/type blocker, material review thread, functional-isolation breach or deployment/workflow drift.
- That approval is consumed by the merge and cannot be reused for REPORT016.

### Development Integrator
- Revalidated PR #63 base/head, same-head QA and Product Design gates, empty review threads, three-file UI/Test/Governance scope, governance-only Development drift, mergeability and functional isolation.
- Transitioned the Draft PR to Ready without moving its HEAD and squash-merged with expected-head protection as `fae25c2962f01aefc988b3e3ec8e0532e1c491f8`.
- Marked REPORT015 DONE and advanced exactly one roadmap item, REPORT016, to READY for Product Design bounding.

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
- `ResponsiveCollection` owns device renderer selection/orchestration only; collection data, business ordering, row meaning, actions and state copy remain caller-owned.
- REPORT006, REPORT012, REPORT013 and REPORT015 prove the same responsive-collection grammar across four distinct Reports row shapes while preserving dense Desktop comparison and deliberate Tablet/Mobile cards with exactly one renderer mounted.
- Dense management collections may intentionally remain semantic Desktop tables while Tablet/Mobile use deliberate shared-card composition from the same unchanged domain data.
- Canonical touch targets remain first-class through Tablet; Desktop may intentionally preserve denser pointer-oriented controls.
- Mobile operational actions remain clear and touch-ready; Tablet must be deliberate; Desktop must remain efficient for management/review/data entry.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Durable decisions belong in the Decision Log; routine progress does not.
- No hosted CI, Vercel preview or `main` activity from scheduled agents.

## Known evidence / risks

- Development evidence through REPORT015 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions/status checks is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- REPORT016 is intentionally a roadmap-level placeholder and must be decomposed by Product Design into one smallest representative presentation concern before implementation.
- Report tables, later chart surfaces, dense responsive composition, loading/empty/error states, export/print and broader FilterBar grammar still need later bounded convergence; no business semantics may move into the Design System.
- Further Work detail/feedback/management convergence remains debt; remaining Field create/detail surfaces still need later bounded convergence.
- Full shared Pagination, FilterBar/search/filter convergence, DataTable keyboard/overflow semantics, SearchInput clear accessibility, error/offline-state convergence and dense-table overflow remain broader shared debt.
- Settings/Admin and global Dark/RTL/accessibility/legacy cleanup remain unstarted roadmap phases.

## Reusable patterns learned

- REPORT015 proves `ResponsiveCollection + Card + KeyValueList` generalizes to Geography's dynamic-level table while preserving caller-owned conditional-parent truth, heatmap-only Desktop affordances, loading/empty precedence and full numeric data without shared-contract widening.
- REPORT013 proved the same grammar on RFM Churn Risk; REPORT012 on Customer Health; REPORT006 on Product Performance. Together these show the responsive collection pattern is system-level rather than page-specific.
- REPORT014 and REPORT008-011 prove multiple independent report charts can adopt the neutral `ChartPanel` while preserving caller-owned loading/empty/data/trust/chart semantics without shared API/CSS widening.
- REPORT007 proved a page-local raw native select can converge onto shared `Select -> Field` without moving controlled state, filter shape or report meaning into the Design System.
- Thin shared composites are preferred when the platform-native interaction model is already correct and the Design System only needs to own presentation/accessibility consistency.
- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared patterns should be proven on representative screens, then reused; legacy families should not be globally removed while live consumers remain.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect representative remaining Reports/Analytics surfaces on the exact latest `design-system-v2-development` baseline and record exactly one smallest dependency-safe REPORT016 presentation concern, including representative file/surface and explicit acceptance boundary. Preserve REPORT001-015 contracts, all analytics/query/calculation/trust/permission/routing/export/print/business semantics, and keep Settings/Admin, Global, remaining Work/Field and shared-component roadmap intact.

UI Production Engineer should bootstrap only after that boundary is recorded and implement one coherent concern from the exact then-current Development HEAD. Design QA should independently review the future exact stable PR HEAD. Development Integrator should no-op until a future PR receives fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and all normal gates pass.
