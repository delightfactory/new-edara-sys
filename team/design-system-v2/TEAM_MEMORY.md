# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-004`.
- Current integrated product HEAD: `38b53912c1b3ff8c933ec0d5cfc9d3dc69488f85` from PR #51.
- Development coordination HEAD immediately before this memory write: `b6e0985a1198fff897795acb23f1312f65117739`.
- Current single READY roadmap item: `DS2-REPORT-005 — Next bounded report chart/table/responsive-composition convergence`.
- Product Design Director must first inspect the exact latest Development baseline and bound one smallest dependency-safe presentation-only REPORT005 concern before UI Production implementation begins.
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
- shared `SegmentedControl` long-content geometry hardened so default/non-block items retain intrinsic width while block mode and Mobile horizontal containment remain intact;
- shared presentation-only V2 `DateField` composed from `Input -> Field` and adopted by the two report custom-date editors;
- Reports Overview primary KPI-summary layout convergence onto shared `MetricGrid columns={4}` while report-domain `MetricCard` continues to own trust/freshness and running/blocked semantics;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-REPORT-004 — Reports Overview summary metric-grid convergence`

Result:
- PR #51 exact reviewed HEAD `0dad8a5eb73e1a4fac73475dda5a247182db2e51` received `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- Product Design independently accepted the same exact HEAD with `PASS — NO DESIGN-SYSTEM BLOCKER` and resolved the prior stale illustrative wrapper/metric-label wording in favor of exact baseline source truth.
- Evidence remains honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/lint/runtime/preview PASS is claimed.
- Squash merge commit: `38b53912c1b3ff8c933ec0d5cfc9d3dc69488f85`.
- Only the primary Reports Overview KPI-summary wrapper migrated from local `report-grid` to shared `MetricGrid columns={4}`.
- Exact existing metric children remain in source order: `صافي الإيراد`, `إجمالي المبيعات`, `صافي التحصيل الخزيني`, `تحصيل AR المنسوب`.
- Every existing metric prop/value/formatter/status/freshness/domain/subtitle/icon/secondary value and the four-skeleton loading branch remain unchanged.
- Report-domain `MetricCard` remains intentionally domain-owned because its trust/freshness and COMPLETE/warning/RUNNING/BLOCKED semantics are richer than generic `StatCard` presentation.
- Customer Health, navigation cards, charts, tables, filters and every second report page remain untouched.
- All report queries, cache/service/hook contracts, calculations, metric/chart/table data, permissions, routing, `AnalyticsGate`, export/print and business truth remain caller/domain-owned and unchanged.

## Current single READY roadmap item

`DS2-REPORT-005 — Next bounded report chart/table/responsive-composition convergence`

Intent:
- Product Design Director inspects representative report chart/table/metric/responsive-composition consumers on the exact latest Development baseline before implementation;
- select exactly one smallest dependency-safe presentation-only concern and name its representative surface/file and acceptance boundary;
- prefer an existing shared V2 primitive/pattern, or strengthen a proven shared contract only when a real consumer demonstrates the need;
- preserve all report queries, cache/service/hook contracts, calculations, metric values, chart data/series/legend meaning, table row/value meaning, permissions, routing, `AnalyticsGate`, export/print and business truth;
- preserve REPORT001 `SubNav`, REPORT002 `SegmentedControl`, REPORT003 `DateField`, REPORT004 `MetricGrid` adoption and report-domain `MetricCard` trust/freshness semantics;
- preserve Settings/Admin, Global convergence, remaining Work and Field debt and shared component-depth work in the roadmap;
- do not turn REPORT005 into a broad multi-page report beautification pass.

## Latest role positions

### Product Design Director
- Accepted PR #51 exact HEAD `0dad8a5eb73e1a4fac73475dda5a247182db2e51` with `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Explicitly corrected its earlier illustrative REPORT004 class/metric list to the exact source truth and closed the QA/UI `WATCH`.
- Next responsibility is to inspect the exact latest Development baseline and bound one smallest safe REPORT005 presentation concern.

### UI Production Engineer
- REPORT004 implementation is integrated.
- Focused Overview tests remain `TESTS_AUTHORED_NOT_EXECUTED`.
- Must not begin REPORT005 product code until Product Design records the exact boundary from the latest Development HEAD.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` on `0dad8a5eb73e1a4fac73475dda5a247182db2e51` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Found no known source-visible build/type blocker, material review thread, functional-isolation breach or deployment/workflow drift on the merged implementation.
- That approval is consumed by the merge and cannot be reused for REPORT005.

### Development Integrator
- Revalidated PR #51 base/head, same-head QA and Product Design gates, review threads, three-file scope, governance-only Development drift and functional isolation.
- Transitioned the draft PR to ready without moving its HEAD and squash-merged with expected-head protection as `38b53912c1b3ff8c933ec0d5cfc9d3dc69488f85`.
- Marked REPORT004 DONE and advanced exactly one roadmap item, REPORT005, to READY for Product Design bounding.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Customer, Sales, Inventory, Procurement, Finance, HR, Field, Work and Reports business/query/permission/workflow truths remain page/domain/service-owned.
- Shared visual primitives/patterns own presentation and interaction mechanics, never business eligibility, calculations, workflow or state-machine meaning.
- `SubNav` owns route-level secondary-navigation presentation/interaction mechanics only; callers own destination eligibility and route/business meaning.
- `MetricGrid` owns KPI layout/responsive composition only; callers retain calculation and business meaning.
- Report-domain `MetricCard` continues to own report trust/freshness/status presentation semantics and must not be flattened into generic KPI semantics unless a separately bounded future design decision proves equivalence.
- `SegmentedControl` owns compact single-choice presentation only; callers retain selected value and domain meaning.
- Default/non-block `SegmentedControl` items retain intrinsic non-shrinking geometry; `--block` retains equal-width stretching; Mobile horizontal containment remains in the shared component.
- `DateField` owns native date-input presentation/accessibility plumbing only; parsing, normalization, range ordering, timezone and business meaning remain caller-owned.
- Native form-control geometry introduced through V2 form convergence remains scoped by explicit V2 boundaries such as `.ds-field`; generic legacy consumers must not be redefined incidentally.
- Canonical touch targets remain first-class through Tablet; Desktop may intentionally preserve denser pointer-oriented controls.
- Mobile operational actions remain clear and touch-ready; Tablet must be deliberate; Desktop must remain efficient for management/review/data entry.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Initial-empty and filtered-empty remain distinct when filtering/search exists; search/filter copy must match actual service/query truth.
- Hidden duplicate device interaction trees should be avoided where device-aware composition exists.
- Each agent writes only its own specialist state; all agents read every specialist state.
- Exact source truth supersedes stale illustrative governance wording when the governing invariant is unambiguous; any material contradiction still requires explicit specialist synthesis before merge.
- Durable decisions belong in the Decision Log; routine progress does not.
- No hosted CI, Vercel preview or `main` activity from scheduled agents.

## Known evidence / risks

- Development evidence through REPORT004 remains source-level: no exact-head executed test suite, local build/lint, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- REPORT005 is intentionally broad at roadmap level and must be decomposed by Product Design into one smallest representative presentation concern before implementation.
- Report charts/tables, dense responsive composition, loading/empty/error states, export/print and broader FilterBar grammar still need later bounded convergence; no business semantics may move into the Design System.
- Further Work detail/feedback/management convergence remains debt; remaining Field create/detail surfaces still need later bounded convergence.
- Full shared Pagination, FilterBar/search/filter convergence, DataTable keyboard/overflow semantics, SearchInput clear accessibility, error/offline-state convergence and dense-table overflow remain broader shared debt.
- Settings/Admin and global Dark/RTL/accessibility/legacy cleanup remain unstarted roadmap phases.

## Reusable patterns learned

- A real migrated consumer may expose a shared primitive gap; repair the shared contract once rather than introduce a page-local workaround when functional isolation permits it.
- Shared layout can converge independently of richer domain cards: REPORT004 proves `MetricGrid` can own responsive KPI composition while a domain-specific `MetricCard` retains trust/freshness and state semantics.
- Exact source truth should be revalidated before integration when earlier design notes contain illustrative examples; source correction is governance clarification, not permission to widen scope.
- Shared presentation can evolve while domain semantics remain caller-owned; REPORT003 established a native `DateField` without absorbing range/date/query meaning.
- Thin shared composites are preferred when the platform-native interaction model is already correct and the Design System only needs to own presentation/accessibility consistency.
- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared form composition can standardize presentation while validation/payload/workflow truth stays page-owned.
- Shared CSS hardening should attach to explicit adopted V2 boundaries to avoid incidental legacy blast radius.
- `ResponsiveCollection` has cross-module proof for dense Desktop vs operational Tablet/Mobile collections.
- `SegmentedControl` is the canonical compact single-choice presentation where the page/domain owns the value and meaning.
- `MetricGrid` now has cross-module proof for responsive KPI layout in both Work and Reports while calculations/domain-state meaning remain caller-owned.
- `SubNav` is proven as the canonical route-level secondary-navigation grammar: caller owns eligibility/meaning, while `SubNav` owns real-link semantics, active/focus state, horizontal reachability, RTL-safe layout and touch geometry.
- Shared patterns should be proven on representative screens, then reused; legacy families should not be globally removed while live consumers remain.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect representative report chart/table/metric and responsive-composition surfaces on the exact latest `design-system-v2-development` baseline and record exactly one smallest dependency-safe REPORT005 presentation concern. Preserve all analytics/query/calculation/business semantics and keep Admin, Global, remaining Work and Field roadmap intact.

UI Production Engineer should bootstrap only after that boundary is recorded and implement one coherent concern from the exact then-current Development HEAD. Design QA should independently review the future exact stable PR HEAD. Development Integrator should no-op until a future PR receives fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and all normal gates pass.