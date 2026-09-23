# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-037`.
- Current integrated product HEAD / squash merge: `2af5917c0b370d1bd6aaa785ef248f6084e483d3` from PR #85.
- Exact reviewed implementation HEAD: `a20442ca930ef957bdf79a156145aeec2771f196`.
- Coordination HEAD immediately before this Team Memory write: `f407d73b27f15179d408668e41f26db443c057ad`.
- Current single READY roadmap item: `DS2-REPORT-038 — Next bounded Reports metrics/charts/tables/responsive-composition convergence`.
- REPORT038 is intentionally unbounded: Product Design Director must inspect the exact latest Development baseline and record exactly one smallest dependency-safe presentation-only concern before UI Production begins.
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
- shared V2 Field grammar proven for compact report-scope risk/date controls and Customer Health as-of-date control while filter/date/query truth remains caller-owned;
- shared `MetricGrid` proofs across representative report KPI clusters while report-domain/business meaning remains caller-owned;
- shared `ChartPanel` analytical-surface grammar proven across representative report surfaces while chart data/visualization semantics remain caller-owned;
- shared `StatePanel` empty-state grammar proven across Product Performance, Rep Performance and now Customer Health responsive detail without moving state precedence or data truth into shared components;
- representative report detail collections using shared responsive collection grammar while preserving dense semantic Desktop tables;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-REPORT-037 — Customer Health responsive-detail empty-state convergence`

Result:
- PR #85 exact reviewed HEAD `a20442ca930ef957bdf79a156145aeec2771f196` received `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- Product Design independently closed out the same exact HEAD as `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Evidence remains honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview/release PASS is claimed.
- Squash merge commit: `2af5917c0b370d1bd6aaa785ef248f6084e483d3`.
- Customer Health's bespoke responsive-detail empty block now consumes existing shared passive `StatePanel kind="empty"` with exact copy `لا توجد بيانات snapshot لهذا التاريخ — شغّل watermark sweep أولاً`.
- Exact state precedence remains `isBlocked -> loading -> empty -> ready`; the existing BLOCKED renderer and trust meaning are unchanged.
- Loading remains exactly five `SkeletonCard height={44}` rows before empty evaluation.
- Empty state is one passive renderer across Desktop, Tablet and Mobile; no ready table/card renderer mounts while empty.
- Dense five-column Desktop detail, two-column Tablet cards, one-column Mobile cards, Trust/Freshness and ready-only `>50` footer remain unchanged.
- No shared API/CSS/token/breakpoint widening occurred and no query/snapshot/calculation/permission/RBAC/RLS/routing/export/print/backend/business semantics changed.

## Current single READY roadmap item

`DS2-REPORT-038 — Next bounded Reports metrics/charts/tables/responsive-composition convergence`

Intent:
- Product Design Director inspects representative remaining Reports/Analytics surfaces on the exact latest Development baseline before implementation;
- select exactly one smallest dependency-safe presentation-only concern and name its representative surface/file plus explicit acceptance/exclusion boundary;
- prefer existing shared V2 primitives/patterns, or strengthen a shared contract only when a real consumer demonstrates the need;
- preserve REPORT001-037 contracts and all analytics/query/calculation/trust/permission/RBAC/RLS/routing/export/print/backend/business semantics;
- preserve Settings/Admin, Global convergence, remaining Work and Field debt and shared component-depth work in the roadmap;
- do not turn REPORT038 into broad multi-page report beautification.

Implementation is not authorized until Product Design records the exact bounded concern from the then-current Development HEAD.

## Latest role positions

### Product Design Director
- Independently accepted REPORT037 exact PR HEAD `a20442ca930ef957bdf79a156145aeec2771f196` as `PASS — NO DESIGN-SYSTEM BLOCKER`.
- No current `BLOCKING` contradiction exists.
- Next responsibility is to inspect the exact latest Development baseline and bound one smallest safe REPORT038 concern.

### UI Production Engineer
- REPORT037 implementation is integrated.
- Focused Customer Health state-convergence tests remain `TESTS_AUTHORED_NOT_EXECUTED`.
- The integrated implementation preserves exact blocked/loading/empty/ready precedence and responsive renderer isolation while consuming shared `StatePanel` unchanged.
- Must not begin REPORT038 product code until Product Design records the exact boundary from the latest Development HEAD.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` on `a20442ca930ef957bdf79a156145aeec2771f196` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Found no known source-visible build/type blocker, material review thread, functional-isolation breach or deployment/workflow drift on the merged exact HEAD.
- That approval is consumed by the merge and cannot be reused for REPORT038.

### Development Integrator
- Revalidated PR #85 base/head, exact-head QA gate, exact-head Product Design closeout, empty review threads, three-file UI/Test/Governance scope, governance-only Development drift, mergeability and functional isolation.
- Transitioned the Draft PR to Ready without moving its HEAD and squash-merged with expected-head protection as `2af5917c0b370d1bd6aaa785ef248f6084e483d3`.
- Marked REPORT037 DONE and advanced exactly one roadmap item, REPORT038, to READY for Product Design bounding.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Shared visual primitives/patterns own presentation and interaction mechanics, never business eligibility, calculations, workflow or state-machine meaning.
- `StatePanel` owns shared state presentation/anatomy only; state precedence, loading decisions, data truth, actions and business meaning remain caller-owned.
- A page-local state wrapper is acceptable only for preserved geometry; state typography/color/anatomy belongs to the shared state family.
- `Field`, `Select`, `Input` and `DateField` own presentation/accessibility/control mechanics only; filter values, date semantics and query inputs remain caller-owned.
- `MetricGrid` owns KPI/metric layout and responsive composition only; callers and metric components retain calculation, trust/status and business meaning.
- `StatCard` owns semantic KPI presentation only; report/domain calculations, category classification and sign/risk truth remain caller-owned.
- Report-domain `MetricCard` continues to own report trust/freshness/status presentation semantics unless a separately bounded future decision proves equivalence.
- `ChartPanel` owns only neutral analytical surface/frame, semantic section hierarchy and chart-body containment; chart data, visualization semantics, trust/freshness, state decisions and business meaning remain caller-owned.
- `ResponsiveCollection` owns device renderer selection/orchestration only; collection data, business ordering, row meaning, actions and state copy remain caller-owned.
- Dense management collections may intentionally remain semantic Desktop tables while Tablet/Mobile use deliberate shared-card composition from the same unchanged domain data.
- Canonical touch targets remain first-class through Tablet; Desktop may intentionally preserve denser pointer-oriented controls.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Durable decisions belong in the Decision Log; routine progress does not.
- No hosted CI, Vercel preview or `main` activity from scheduled agents.

## Known evidence / risks

- Development evidence through REPORT037 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions/status checks is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- REPORT038 is intentionally a roadmap-level placeholder and must be decomposed by Product Design into one smallest representative presentation concern before implementation.
- Remaining report tables, chart surfaces, dense responsive composition, loading/empty/error states, export/print and broader FilterBar grammar still need later bounded convergence; no business semantics may move into the Design System.
- Further Work detail/feedback/management convergence and Field create/detail convergence remain debt.
- Shared Pagination, FilterBar/search/filter convergence, DataTable keyboard/overflow semantics, SearchInput clear accessibility, error/offline-state convergence and dense-table overflow remain broader shared debt.
- Settings/Admin and global Dark/RTL/accessibility/legacy cleanup remain unstarted roadmap phases.

## Reusable patterns learned

- REPORT037 confirms the shared `StatePanel` empty-state grammar also fits a trust-gated responsive detail collection when the caller preserves `isBlocked -> loading -> empty -> ready` and leaves BLOCKED meaning outside the Design System.
- REPORT036 confirms fixed analytical geometry may remain page-owned while shared empty-state anatomy stays system-owned.
- Empty-state convergence must preserve loading precedence and prevent hidden ready renderers from mounting in empty device modes.
- Category-oriented metric summaries can retire arbitrary page-local KPI grid/card styling onto existing `MetricGrid` + `StatCard` without moving category classification or report truth into the Design System.
- Existing report charts can retire local analytical frames onto shared `ChartPanel -> Card + SectionHeader` without changing chart data, responsive sizing, visualization semantics or trust/freshness meaning.
- Compact report-scope controls can converge onto existing `Select` + `DateField` / `Field` grammar without moving filter/date/query meaning into shared components or widening shared APIs.
- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared patterns should be proven on representative screens, then reused; legacy families should not be globally removed while live consumers remain.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect representative remaining Reports/Analytics surfaces on the exact latest `design-system-v2-development` baseline and record exactly one smallest dependency-safe REPORT038 presentation concern, including representative file/surface and explicit acceptance/exclusion boundary. Preserve REPORT001-037 contracts, all analytics/query/calculation/trust/permission/routing/export/print/backend/business semantics, and keep Settings/Admin, Global, remaining Work/Field and shared-component roadmap intact.

UI Production Engineer should bootstrap only after that boundary is recorded and implement one coherent concern from the exact then-current Development HEAD. Design QA should independently review the future exact stable PR HEAD. Development Integrator should no-op until a future PR receives fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and all normal gates pass.