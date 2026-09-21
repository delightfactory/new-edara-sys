# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-019`.
- Current integrated product merge: `5184c06021d2162e4c1feb5170e92e300bd846d9` from PR #67.
- Exact reviewed implementation HEAD: `a03724562f461c0072c736f6091ff7bcc158bda6`.
- Development coordination HEAD immediately before this Team Memory write: `a38fd14668248bfd54399a17efdc166cede39d96`.
- Current single READY roadmap item: `DS2-REPORT-020 — Next bounded Reports metrics/charts/tables/responsive-composition convergence`.
- Product Design Director must inspect the exact latest Development baseline and bound exactly one smallest dependency-safe presentation-only REPORT020 concern before UI Production begins.
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
- Reports route-level `SubNav`, date-preset `SegmentedControl`, shared native `DateField`, Geography `Select -> Field`, and report Overview shared `MetricGrid` usage for both the four primary KPIs and the two customer-health summary metrics;
- domain-agnostic `ChartPanel` reuse across Sales, Receivables, Churn Risk, Product Performance, Rep Performance and Treasury analytical surfaces;
- Product Performance, Customer Health, Churn Risk, Geography, Rep Performance and Target Attainment detail collections converged onto shared `ResponsiveCollection`, preserving dense semantic Desktop tables and deliberate Tablet/Mobile `Card + KeyValueList` composition from the same caller-owned domain data;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-REPORT-019 — Overview customer-health metric-grid convergence`

Result:
- PR #67 exact reviewed HEAD `a03724562f461c0072c736f6091ff7bcc158bda6` received `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- Product Design independently accepted the same exact HEAD with `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Evidence remains honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview/release PASS is claimed.
- Squash merge commit: `5184c06021d2162e4c1feb5170e92e300bd846d9`.
- Reports Overview `صحة قاعدة العملاء` ready state now consumes the established shared `MetricGrid columns={2}` instead of a page-local `report-grid` wrapper.
- Both existing customer-health `MetricCard`s remain unchanged in order/content/formatting, including active/dormant values, average monetary value, `آخر 90 يوماً`, average-recency secondary fact/fallback and all trust/freshness/stale/domain wiring.
- Existing details link and section hierarchy remain unchanged.
- Existing `custLoading` state remains a single `SkeletonCard height={120}` and does not mount the ready-state customer-health grid while loading.
- Mobile uses the canonical shared one-column stack; Tablet and Desktop preserve the deliberate two-column comparison.
- No shared API/CSS/token widening and no query/cache/calculation/trust/permission/RBAC/RLS/routing/backend/validation/export/print/workflow/business drift occurred.

## Current single READY roadmap item

`DS2-REPORT-020 — Next bounded Reports metrics/charts/tables/responsive-composition convergence`

Intent:
- Product Design Director inspects representative remaining Reports/Analytics surfaces on the exact latest Development baseline before implementation;
- select exactly one smallest dependency-safe presentation-only concern and name its representative surface/file plus explicit acceptance boundary;
- prefer existing shared V2 primitives/patterns, or strengthen a shared contract only when a real consumer demonstrates the need;
- preserve REPORT001-019 contracts and all analytics/query/calculation/trust/permission/RBAC/RLS/routing/export/print/business semantics;
- preserve Settings/Admin, Global convergence, remaining Work and Field debt and shared component-depth work in the roadmap;
- do not turn REPORT020 into broad multi-page report beautification.

Implementation is not authorized until Product Design records the exact bounded concern from the then-current Development HEAD.

## Latest role positions

### Product Design Director
- Accepted PR #67 exact HEAD `a03724562f461c0072c736f6091ff7bcc158bda6` with `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Confirmed the customer-health pair correctly reuses neutral layout-only `MetricGrid` without moving report metric, trust, loading or business truth into the Design System.
- Next responsibility is to inspect the exact latest Development baseline and bound one smallest safe REPORT020 concern.

### UI Production Engineer
- REPORT019 implementation is integrated.
- Focused Overview tests remain `TESTS_AUTHORED_NOT_EXECUTED`.
- The integrated implementation preserves both existing MetricCards, trust/freshness/domain wiring, section action and loading semantics while consuming `MetricGrid` unchanged.
- Must not begin REPORT020 product code until Product Design records the exact boundary from the latest Development HEAD.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` on `a03724562f461c0072c736f6091ff7bcc158bda6` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Found no known source-visible build/type blocker, material review thread, functional-isolation breach or deployment/workflow drift on the merged exact HEAD.
- That approval is consumed by the merge and cannot be reused for REPORT020.

### Development Integrator
- Revalidated PR #67 base/head, exact-head QA and Product Design gates, empty review threads, three-file UI/Test/Governance scope, governance-only Development drift, mergeability and functional isolation.
- Transitioned the Draft PR to Ready without moving its HEAD and squash-merged with expected-head protection as `5184c06021d2162e4c1feb5170e92e300bd846d9`.
- Marked REPORT019 DONE and advanced exactly one roadmap item, REPORT020, to READY for Product Design bounding.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Customer, Sales, Inventory, Procurement, Finance, HR, Field, Work and Reports business/query/permission/workflow truths remain page/domain/service-owned.
- Shared visual primitives/patterns own presentation and interaction mechanics, never business eligibility, calculations, workflow or state-machine meaning.
- `SubNav` owns route-level secondary-navigation presentation/interaction mechanics only; callers own destination eligibility and route/business meaning.
- `MetricGrid` owns KPI/metric layout and responsive composition only; callers and metric components retain calculation, trust/status and business meaning.
- Report-domain `MetricCard` continues to own report trust/freshness/status presentation semantics unless a separately bounded future decision proves equivalence.
- `SegmentedControl` owns compact single-choice presentation only; callers retain selected value and domain meaning.
- `DateField` owns native date-input presentation/accessibility plumbing only; parsing, normalization, range ordering, timezone and business meaning remain caller-owned.
- `Select -> Field` owns native select presentation/accessibility/geometry only; selected values, state transitions, filter/query meaning and domain semantics remain caller-owned.
- `ChartPanel` owns only neutral analytical surface/frame, semantic section hierarchy and chart-body containment; chart data, visualization semantics, trust/freshness, state decisions and business meaning remain caller-owned.
- `ChartPanel` defaults to semantic `h2`; explicit `2 | 3 | 4` heading override remains for genuinely nested composition.
- REPORT005, REPORT008-011, REPORT014 and REPORT018 prove the same neutral chart-panel grammar across independent analytical surfaces without shared-contract widening.
- REPORT004 and REPORT019 prove `MetricGrid` can own responsive summary layout for distinct Overview metric clusters while leaving report metric/trust/loading semantics outside the layout primitive.
- `ResponsiveCollection` owns device renderer selection/orchestration only; collection data, business ordering, row meaning, actions and state copy remain caller-owned.
- REPORT006, REPORT012, REPORT013, REPORT015, REPORT016 and REPORT017 prove the same responsive-collection grammar across six distinct Reports row shapes while preserving dense Desktop comparison and deliberate Tablet/Mobile cards with exactly one renderer mounted.
- Rank-derived visual emphasis must not leak into unrelated financial/status meaning; REPORT016 specifically proves compact identity/#rank can carry ranking emphasis while revenue stays neutral/default.
- Dense management collections may intentionally remain semantic Desktop tables while Tablet/Mobile use deliberate shared-card composition from the same unchanged domain data.
- Canonical touch targets remain first-class through Tablet; Desktop may intentionally preserve denser pointer-oriented controls.
- Mobile operational actions remain clear and touch-ready; Tablet must be deliberate; Desktop must remain efficient for management/review/data entry.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Durable decisions belong in the Decision Log; routine progress does not.
- No hosted CI, Vercel preview or `main` activity from scheduled agents.

## Known evidence / risks

- Development evidence through REPORT019 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions/status checks is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- REPORT020 is intentionally a roadmap-level placeholder and must be decomposed by Product Design into one smallest representative presentation concern before implementation.
- Remaining report tables, chart surfaces, dense responsive composition, loading/empty/error states, export/print and broader FilterBar grammar still need later bounded convergence; no business semantics may move into the Design System.
- Further Work detail/feedback/management convergence remains debt; remaining Field create/detail surfaces still need later bounded convergence.
- Full shared Pagination, FilterBar/search/filter convergence, DataTable keyboard/overflow semantics, SearchInput clear accessibility, error/offline-state convergence and dense-table overflow remain broader shared debt.
- Settings/Admin and global Dark/RTL/accessibility/legacy cleanup remain unstarted roadmap phases.

## Reusable patterns learned

- REPORT019 proves an additional Overview summary cluster can move from page-local responsive layout to shared `MetricGrid` while preserving existing report `MetricCard` trust/status semantics and a separate loading branch unchanged.
- REPORT018 adds Treasury as another independent proof that `ChartPanel` can absorb only analytical framing/hierarchy while leaving data mapping, chart geometry, trust, state precedence and business meaning in the caller.
- REPORT014 and REPORT008-011, together with REPORT018, establish `ChartPanel` as system-level rather than page-specific without API/CSS/token widening.
- REPORT017 proves `ResponsiveCollection + Card + KeyValueList` generalizes to Target Attainment while preserving eight-fact comparison, achievement thresholds, trend semantics, Trust/Freshness and exact state precedence without shared-contract widening.
- REPORT016 proves the same grammar on Rep Performance while preserving dense Desktop comparison, caller-owned ranking and compact semantic-color separation; REPORT015 proves it on Geography, REPORT013 on RFM Churn Risk, REPORT012 on Customer Health and REPORT006 on Product Performance.
- REPORT007 proved a page-local raw native select can converge onto shared `Select -> Field` without moving controlled state, filter shape or report meaning into the Design System.
- Thin shared composites are preferred when the platform-native interaction model is already correct and the Design System only needs to own presentation/accessibility consistency.
- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared patterns should be proven on representative screens, then reused; legacy families should not be globally removed while live consumers remain.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect representative remaining Reports/Analytics surfaces on the exact latest `design-system-v2-development` baseline and record exactly one smallest dependency-safe REPORT020 presentation concern, including representative file/surface and explicit acceptance/exclusion boundary. Preserve REPORT001-019 contracts, all analytics/query/calculation/trust/permission/routing/export/print/business semantics, and keep Settings/Admin, Global, remaining Work/Field and shared-component roadmap intact.

UI Production Engineer should bootstrap only after that boundary is recorded and implement one coherent concern from the exact then-current Development HEAD. Design QA should independently review the future exact stable PR HEAD. Development Integrator should no-op until a future PR receives fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and all normal gates pass.