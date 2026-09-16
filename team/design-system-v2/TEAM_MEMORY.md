# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-INV-001`.
- Latest product integration commit: `805995a5c0d9a118c415d647ed34e63dee326527` from PR #34.
- Workstream synchronization commit: `e16f6bcfb4678a7b7dca67e90e21aba5a6d8fde5`.
- Integration-state synchronization commit: `e0336aaa48a06875f202bd68d0292705ab5237ed`.
- Current single READY slice: `DS2-INV-002 — Transfer/adjustment operational flows`.
- `main` remains frozen until explicit owner approval.
- Vercel preview is user-requested only.
- GitHub Actions / hosted CI remain forbidden for normal Design System development.
- Product target remains one deep, premium Arabic-first operational Design System across the entire EDARA interface.
- Mobile is the primary daily operational surface; Tablet is deliberate; Desktop preserves management/review/data-entry density and speed.
- Repository-native shared memory remains active: every DS2 role reads Team Memory and peer role states before acting.

## Current integrated system

The development branch now includes:
- semantic foundations and V2 primitives/patterns;
- responsive shell/navigation/form/collection/action composition foundations;
- navigation registry and deliberate Tablet shell behavior;
- Sidebar V2 isolated renderer behind feature flag;
- Dashboard V2 migration;
- Customers List V2 migration;
- Customer basic-info V2 composition (`DS2-UI-001`);
- Customer secondary Tabs/Branches/Contacts/Credit V2 composition (`DS2-UI-002`);
- complete shared Tabs semantics reused by the Customer flow;
- Sales Orders list V2 composition (`DS2-UI-003`);
- Sales Order form V2 outer foundation (`DS2-UI-004`);
- backward-compatible shared Stepper guarded interaction contract;
- shared FormSection/FormGrid/FormActions/Button proof on a real stepped Sales form;
- Sales transaction-detail header V2 (`DS2-UI-005`) using shared `TransactionHeader` and canonical `AppAction` device placement;
- Inventory stock list V2 (`DS2-INV-001`) using one `ResponsiveCollection` boundary, thin shared-pattern stock cards and deliberate Desktop/Tablet/Mobile pagination composition;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-INV-001 — Inventory list surfaces`

Result:
- PR #34 exact reviewed head `819832d23cb9aafc895f56dc4b9f5ba2d21530b3` received `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS`.
- Evidence remained honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/runtime PASS is claimed.
- The earlier P2 Tablet pagination blocker on `9f3a2c4...` was closed before final review through shared touch-safe Buttons, complete accessible/current-page semantics and Arabic RTL-native previous/next cues.
- `StockPage` now uses one `ResponsiveCollection<Stock>` boundary instead of CSS-hidden Desktop/Mobile collection trees.
- Desktop keeps dense paged `DataTable` comparison/review behavior and authorized valuation columns.
- Tablet uses deliberate two-column `StockBalanceCard` composition, authorized weighted-cost + total-value parity and numbered direct page jumps.
- Mobile uses one-column operational stock cards with compact previous/next paged-query semantics.
- `StockBalanceCard` remains a thin Inventory-domain composition over shared `Card + KeyValueList + StatusBadge`.
- Tablet pagination uses shared `Button + touchTarget`, explicit accessible names, `aria-current="page"`, semantic 44px minimum numeric hit width and Arabic `السابق` / `التالي` labels.
- Stock health, quantities, valuation, warehouse/product links, `finance.view_costs`, local review math, routes, queries, filters, page size and pagination behavior remain page/domain-owned.
- No hosted CI, Vercel preview, backend/business behavior or `main` change occurred.

## Current single READY slice

`DS2-INV-002 — Transfer/adjustment operational flows`

Intent:
- continue Inventory with the smallest representative dependency-safe transfer or adjustment presentation concern rather than a broad module rewrite;
- Product Design Director should bound one live operational surface before implementation expands;
- preserve stock movement, warehouse, quantity, costing, reservation, approval, permission, validation, route, query/service and transaction semantics exactly;
- reuse existing V2 page/header/form/action/state/dialog grammar and the now-proven Inventory card/status language where it genuinely fits;
- Mobile remains task-oriented and touch-safe; Tablet is deliberate; Desktop preserves efficient review/data entry;
- strengthen only the smallest recurring shared contract proven by the selected live flow;
- do not include backend/query/RBAC/RLS/permission/workflow changes, speculative global Pagination convergence, deployment or preview work.

## Latest role positions

### Product Design Director
- Its latest Development-side BLOCKING state targeted old PR #34 head `9f3a2c4...` and required the same bounded Tablet touch/accessibility/RTL correction later satisfied on `819832d...`.
- Design QA explicitly verified every stated correction condition on the final candidate, so that old blocker is consumed rather than current.
- Full shared numbered Pagination convergence remains a future component-depth WATCH, not a reason to reopen INV001.
- Next role action is to bound the smallest representative transfer/adjustment presentation concern for `DS2-INV-002`.

### UI Production Engineer
- Corrected only the PR #34 Tablet numbered-pagination boundary and preserved the exact page/query/direct-jump algorithm.
- The merged implementation state records shared Button/touch semantics, complete accessible/current-page semantics and RTL-native cues with `TESTS_AUTHORED_NOT_EXECUTED`.
- That implementation state is consumed by the successful merge.
- Next implementation must start only from the latest Development HEAD and take the bounded `DS2-INV-002` concern.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` on `819832d...` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Confirmed no known build/type failure, no current material peer contradiction, no forbidden backend/business/deployment scope and no unresolved review thread.
- Left shared numbered Pagination convergence as a non-blocking future component-depth WATCH.
- Its approval is consumed by the merge and must not be reused for the next slice.

### Development Integrator
- Revalidated PR #34 base/head/review marker/review threads/diff scope and Development drift.
- Confirmed the exact current HEAD retained `GREEN-DEV + SOURCE_REVIEW_PASS`, the stale BLOCKING states targeted the superseded candidate, and the final six-file diff contained no forbidden functional or deployment changes.
- Marked PR #34 Ready without moving HEAD and squash-merged it with expected-head protection as `805995a5c0d9a118c415d647ed34e63dee326527`.
- Integration state is `MERGED_GREEN_DEV` for DS2-INV-001.
- Workstream marks DS2-INV-001 DONE and exactly one next slice, DS2-INV-002, READY.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Customer create/update/GPS/lookup/credit/default branch/default contact/Branch-Contact semantics must not drift.
- Sales list query/filter/Desktop+Tablet pagination/Mobile infinite-loading/navigation/permission/status/payment/Smart Transfer/map/call/workflow semantics must not drift.
- Sales Order form customer/product/pricing/discount/tax/total/validation/submit semantics remain page/domain-owned.
- Sales transaction-detail permission/status/workflow/callback/query/service/calculation truth remains page/domain-owned.
- Inventory stock/query/filter/page/valuation/permission/review/link truth remains page/domain-owned.
- Inventory transfer/adjustment movement, costing, reservation, approval, validation and transaction truth must remain page/domain/service-owned.
- Shared `TransactionHeader` owns presentation/device placement, not business eligibility or workflow truth.
- Shared Stepper owns visual/interaction mechanics only; page/domain code owns workflow reachability and validation truth.
- Complete shared Tabs keyboard/focus/ARIA/RTL semantics remain system-owned; do not reintroduce partial page-local ARIA.
- Neutral metadata counts use neutral Badge semantics; semantic state uses StatusBadge.
- Shared Button/action hierarchy should own migrated actions.
- Mobile operational actions remain clear and touch-ready.
- Tablet must not collapse into oversized Mobile or cramped Desktop.
- Desktop must remain efficient for dense management/review/data-entry work.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Hidden duplicate device interaction trees should be avoided where device-aware composition exists.
- Each agent writes only its own specialist state; all agents read every specialist state.
- Durable decisions belong in the Decision Log; routine progress does not.
- No hosted CI, Vercel preview or `main` activity from scheduled agents.

## Known evidence / risks

- Development evidence through DS2-INV-001 remains source-level: no exact-head executed test suite, local build, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- `DocumentActions` remains a legacy shared feature surface; capability parity is preserved, but Mobile sticky-header density/touch polish should be observed during future runtime review.
- Permission-limited empty states should later converge toward neutral explanatory microcopy.
- Shared numbered Pagination still lacks a converged reusable pattern; INV001 locally hardened the Tablet boundary without opening a global rewrite.
- Dense-table overflow semantics remain a future hardening area.
- Combobox/ProductLine interaction debt remains real but intentionally deferred until a live screen proves a reusable need.
- Transfer/adjustment flows are higher-risk operational surfaces; the next slice must remain presentation-only and avoid accidental movement/costing/validation/workflow changes.

## Reusable patterns learned

- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared navigation/action declarations should own placement decisions rather than pages inventing coordinates.
- Canonical `AppAction + resolveActionSet` can drive shared transaction headers while domain pages retain eligibility/callback truth.
- Shared `TransactionHeader` can expose Mobile/Tablet/Desktop action hierarchy without creating a new action taxonomy.
- Form composition can be standardized independently from business field semantics.
- Shared `PageHeader` + `FormSection` + `FormGrid` + `FormActions` has real Customer and Sales form proof points.
- Shared Stepper can support optional guarded interaction without absorbing workflow truth or breaking read-only consumers.
- Complete shared Tabs semantics can be reused through thin domain wrappers.
- Shared `ResponsiveCollection` can preserve distinct device compositions while owning one presentation boundary.
- Thin domain cards can compose shared `Card + KeyValueList + StatusBadge` without creating a new primitive family.
- Shared `Button + touchTarget` can safely harden a bounded Tablet pagination boundary while global Pagination convergence remains deferred.
- Domain adapters should stay thin: shared patterns own presentation, domain/page code owns business truth.
- `Badge` metadata and `StatusBadge` semantic state remain distinct.
- Accessibility semantics should be introduced only at a complete reusable interaction boundary.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect the live Inventory transfer/adjustment surfaces and bound the smallest representative presentation-only concern for `DS2-INV-002`, explicitly preserving stock movement/costing/reservation/permission/validation/workflow truth and avoiding speculative framework expansion.

UI Production Engineer should bootstrap from the exact latest `design-system-v2-development` HEAD and take only that bounded `DS2-INV-002` concern. Design QA should independently review the next stable exact PR HEAD. Development Integrator should no-op until that exact head receives `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` and all normal gates pass.
