# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-007`.
- Current integrated product HEAD: `9ab20b3ca467b1d42eae0fb9fd6936d156e11662` from PR #54.
- Development coordination HEAD immediately before this memory write: `e1b72da6bf2e5ab09e50d2bf6ceada867b2916c6`.
- Current single READY roadmap item: `DS2-REPORT-008 — Next bounded Reports metrics/charts/tables/responsive-composition convergence`.
- Product Design Director must inspect the exact latest Development baseline and bound one smallest dependency-safe presentation-only REPORT008 concern before UI Production implementation begins.
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
- shared presentation-only V2 `DateField` adopted by the two report custom-date editors;
- Reports Overview primary KPI-summary layout convergence onto shared `MetricGrid columns={4}` while report-domain `MetricCard` retains trust/freshness semantics;
- shared domain-agnostic V2 `ChartPanel` over `Card + SectionHeader`, with semantic `h2` default, proven on the primary Sales revenue chart;
- Product Performance detail collection convergence onto shared `ResponsiveCollection`, preserving a dense semantic Desktop table and deliberate Tablet/Mobile `Card + KeyValueList` composition;
- Geography analysis-level control convergence from a raw page-local select to shared `Select -> Field`, with report-domain state/filter meaning preserved;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-REPORT-007 — Geography analysis-level selector convergence`

Result:
- PR #54 exact reviewed HEAD `00d830adb59a27588722331b80762df524def907` received `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- Product Design independently accepted the same exact HEAD with `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Evidence remains honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview/release PASS is claimed.
- Squash merge commit: `9ab20b3ca467b1d42eae0fb9fd6936d156e11662`.
- Only Geography's `GeoLevel` header selector migrated from raw local `<select>` styling to shared V2 `Select -> Field`.
- Exact option values/order/Arabic labels remain `governorate / محافظة`, `city / مدينة`, `area / منطقة`.
- `level`, `setLevel(...)` and `filters = { dateFrom, dateTo, level }` remain page-owned.
- `ReportFilterBar`, date behavior, Geography hooks/queries/cache/services/RPC/DB/calculations, trust/metrics/table/heatmap, permissions, routing, `AnalyticsGate`, export/print and business truth remain unchanged.
- Explicit Arabic accessible naming is present; shared V2 form grammar owns presentation, focus, dark/disabled, RTL and Tablet/Mobile touch geometry only.

## Current single READY roadmap item

`DS2-REPORT-008 — Next bounded Reports metrics/charts/tables/responsive-composition convergence`

Intent:
- Product Design Director inspects representative remaining Reports/Analytics surfaces on the exact latest Development baseline before implementation;
- select exactly one smallest dependency-safe presentation-only concern and name its representative surface/file plus explicit acceptance boundary;
- prefer existing shared V2 primitives/patterns, or strengthen a shared contract only when a real consumer demonstrates the need;
- preserve REPORT001-007 contracts and all analytics/query/calculation/trust/permission/routing/export/print/business semantics;
- preserve Settings/Admin, Global convergence, remaining Work and Field debt and shared component-depth work in the roadmap;
- do not turn REPORT008 into broad multi-page report beautification.

Implementation is not authorized until Product Design records the exact bounded concern from the then-current Development HEAD.

## Latest role positions

### Product Design Director
- Accepted PR #54 exact HEAD `00d830adb59a27588722331b80762df524def907` with `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Confirmed the one-selector Geography boundary, shared `Select -> Field` fit, explicit Arabic accessible naming and preservation of all report-domain truth.
- Next responsibility is to inspect the exact latest Development baseline and bound one smallest safe REPORT008 concern.

### UI Production Engineer
- REPORT007 implementation is integrated.
- Focused Geography selector/filter-propagation tests remain `TESTS_AUTHORED_NOT_EXECUTED`.
- Must not begin REPORT008 product code until Product Design records the exact boundary from the latest Development HEAD.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` on `00d830adb59a27588722331b80762df524def907` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Found no known source-visible build/type blocker, material review thread, functional-isolation breach or deployment/workflow drift on the merged implementation.
- That approval is consumed by the merge and cannot be reused for REPORT008.

### Development Integrator
- Revalidated PR #54 base/head, same-head QA and Product Design gates, empty inline review threads, three-file UI/Test/Governance scope, governance-only Development drift and functional isolation.
- Transitioned the draft PR to ready without moving its HEAD and squash-merged with expected-head protection as `9ab20b3ca467b1d42eae0fb9fd6936d156e11662`.
- Marked REPORT007 DONE and advanced exactly one roadmap item, REPORT008, to READY for Product Design bounding.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Customer, Sales, Inventory, Procurement, Finance, HR, Field, Work and Reports business/query/permission/workflow truths remain page/domain/service-owned.
- Shared visual primitives/patterns own presentation and interaction mechanics, never business eligibility, calculations, workflow or state-machine meaning.
- `SubNav` owns route-level secondary-navigation presentation/interaction mechanics only; callers own destination eligibility and route/business meaning.
- `MetricGrid` owns KPI layout/responsive composition only; callers retain calculation and business meaning.
- Report-domain `MetricCard` continues to own report trust/freshness/status presentation semantics unless a separately bounded future decision proves equivalence.
- `SegmentedControl` owns compact single-choice presentation only; callers retain selected value and domain meaning.
- Default/non-block `SegmentedControl` items retain intrinsic non-shrinking geometry; `--block` retains equal-width stretching; Mobile horizontal containment remains in the shared component.
- `DateField` owns native date-input presentation/accessibility plumbing only; parsing, normalization, range ordering, timezone and business meaning remain caller-owned.
- `Select -> Field` owns native select presentation/accessibility/geometry only; selected values, state transitions, filter/query meaning and domain semantics remain caller-owned.
- `ChartPanel` owns only neutral analytical surface/frame, semantic section hierarchy and chart-body containment; chart data, visualization semantics, trust/freshness, state decisions and business meaning remain caller-owned.
- `ChartPanel` defaults to semantic `h2`; its explicit `2 | 3 | 4` heading override is for genuinely nested composition.
- `ResponsiveCollection` owns device renderer selection/orchestration only; collection data, business ordering, row meaning, actions and state copy remain caller-owned.
- Dense management collections may intentionally remain semantic Desktop tables while Tablet/Mobile use deliberate shared-card composition from the same unchanged domain data.
- Native form-control geometry introduced through V2 form convergence remains scoped by explicit V2 boundaries such as `.ds-field`; generic legacy consumers must not be redefined incidentally.
- Canonical touch targets remain first-class through Tablet; Desktop may intentionally preserve denser pointer-oriented controls.
- Mobile operational actions remain clear and touch-ready; Tablet must be deliberate; Desktop must remain efficient for management/review/data entry.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Initial-empty and filtered-empty remain distinct when filtering/search exists; search/filter copy must match actual service/query truth.
- Hidden duplicate device interaction trees should be avoided where device-aware composition exists.
- Each agent writes only its own specialist state; all agents read every specialist state.
- Exact source truth supersedes stale illustrative governance wording when the governing invariant is unambiguous; material contradictions still require explicit specialist synthesis before merge.
- Durable decisions belong in the Decision Log; routine progress does not.
- No hosted CI, Vercel preview or `main` activity from scheduled agents.

## Known evidence / risks

- Development evidence through REPORT007 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- REPORT008 is intentionally a roadmap-level placeholder and must be decomposed by Product Design into one smallest representative presentation concern before implementation.
- Report tables, later chart surfaces, dense responsive composition, loading/empty/error states, export/print and broader FilterBar grammar still need later bounded convergence; no business semantics may move into the Design System.
- Further Work detail/feedback/management convergence remains debt; remaining Field create/detail surfaces still need later bounded convergence.
- Full shared Pagination, FilterBar/search/filter convergence, DataTable keyboard/overflow semantics, SearchInput clear accessibility, error/offline-state convergence and dense-table overflow remain broader shared debt.
- Settings/Admin and global Dark/RTL/accessibility/legacy cleanup remain unstarted roadmap phases.

## Reusable patterns learned

- REPORT007 proves a page-local raw native select can converge onto shared `Select -> Field` without moving controlled state, filter shape or report meaning into the Design System.
- REPORT006 proves a dense report collection can preserve its semantic Desktop table while Tablet/Mobile deliberately switch to shared `Card + KeyValueList` through `ResponsiveCollection`, without changing domain data or mounting duplicate renderers.
- A real migrated consumer may expose a shared primitive gap; repair the shared contract once rather than introduce a page-local workaround when functional isolation permits it.
- REPORT005 proves a thin `ChartPanel` over `Card + SectionHeader` can retire one report-local inline chart shell without absorbing Recharts, trust/freshness, state branching or analytics meaning into the Design System.
- Shared layout can converge independently of richer domain cards: REPORT004 proves `MetricGrid` can own responsive KPI composition while a domain-specific `MetricCard` retains trust/freshness and state semantics.
- Shared presentation can evolve while domain semantics remain caller-owned; REPORT003 established a native `DateField` without absorbing range/date/query meaning.
- Thin shared composites are preferred when the platform-native interaction model is already correct and the Design System only needs to own presentation/accessibility consistency.
- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared form composition can standardize presentation while validation/payload/workflow truth stays page-owned.
- Shared CSS hardening should attach to explicit adopted V2 boundaries to avoid incidental legacy blast radius.
- `ResponsiveCollection` now has cross-module and Reports proof for dense Desktop vs operational Tablet/Mobile collections.
- `SegmentedControl` is the canonical compact single-choice presentation where the page/domain owns the value and meaning.
- `MetricGrid` has cross-module proof for responsive KPI layout while calculations/domain-state meaning remain caller-owned.
- `SubNav` is proven as the canonical route-level secondary-navigation grammar while caller owns eligibility/meaning.
- Shared patterns should be proven on representative screens, then reused; legacy families should not be globally removed while live consumers remain.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect representative remaining Reports/Analytics surfaces on the exact latest `design-system-v2-development` baseline and record exactly one smallest dependency-safe REPORT008 presentation concern, including representative file/surface and explicit acceptance boundary. Preserve REPORT001-007 contracts, all analytics/query/calculation/business semantics, and keep Admin, Global, remaining Work and Field roadmap intact.

UI Production Engineer should bootstrap only after that boundary is recorded and implement one coherent concern from the exact then-current Development HEAD. Design QA should independently review the future exact stable PR HEAD. Development Integrator should no-op until a future PR receives fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and all normal gates pass.
