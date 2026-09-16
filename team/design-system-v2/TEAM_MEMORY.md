# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-UI-005`.
- Latest product integration commit: `58b0f3f8f54f04636d3a35dd7d658edb7bcf5068` from PR #32.
- Workstream synchronization commit: `e1554f35677c2bf343cdbac9438f98b0c8c9eee9`.
- Integration-state synchronization commit: `aa86aaf186a2a7e6e3cb41ce4425a28c87e694d4`.
- Current single READY slice: `DS2-INV-001 — Inventory list surfaces`.
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
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-UI-005 — Sales transaction detail V2`

Result:
- PR #32 exact reviewed head `de7c99cb099ac4ccff941e1eb5f2dafacebd7ca6` received `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS`.
- Evidence remained honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/runtime PASS is claimed.
- The earlier incomplete-wiring and stale-baseline TypeScript blockers were both closed before final review.
- Shared `TransactionHeader` consumes canonical `AppAction[] + useDeviceMode + resolveActionSet`; no parallel Sales/header action taxonomy remains.
- Device placement is one visible workflow action on Mobile, up to two on Tablet, up to four on Desktop, with remaining eligible actions in overflow.
- Live Sales edit / confirm / deliver / due-date / return / copy / cancel permission/status predicates and callbacks remain page-owned.
- Confirm warehouse fallback, modal initialization, stock check and four `actionLoading` guards remain preserved.
- `DocumentActions` capability remains preserved through the tools slot.
- Shared Sales status semantics replace the local header status map; local sticky hero/horizontal action strip/`ActionBtn` presentation is removed only from the migrated region.
- Financial summary, receipts, items, notes, modals, queries, services, calculations and workflow semantics were not moved or changed.
- No hosted CI, Vercel preview, backend/business behavior or `main` change occurred.

## Current single READY slice

`DS2-INV-001 — Inventory list surfaces`

Intent:
- begin the Inventory module after completing the Customer/Sales golden-flow tranche;
- select the smallest representative dependency-safe Inventory list concern, not a broad module rewrite;
- reuse `ResponsiveCollection`, shared status/badge/action/filter/state grammar and proven device-aware composition before inventing new patterns;
- preserve inventory quantities, valuation, warehouse/product semantics, permissions, routes, queries, pagination/filter behavior and operational actions exactly;
- Mobile remains task-oriented and touch-safe; Tablet is deliberate; Desktop preserves dense comparison/review efficiency;
- strengthen only the smallest shared V2 gap proven by a real Inventory screen;
- do not include transfer/adjustment business-flow redesign, backend/query changes, deployment or preview work.

## Latest role positions

### Product Design Director
- Its prior BLOCKING state targeted stale PR #32 head `3f370e02...` and required synchronization of the already-integrated TypeScript hotfix.
- That requirement was satisfied on final reviewed head `de7c99c...`; Design QA explicitly treated the old blocker as consumed.
- The transaction/action architecture itself was already judged sound.
- Next role action is to bound the smallest representative Inventory list concern without pre-designing a broad Inventory framework.

### UI Production Engineer
- Synchronized PR #32 with Development without force-rewriting the slice, inherited the existing TypeScript hotfix, preserved the bounded Sales header implementation, and handed off exact head `de7c99c...`.
- That implementation state is consumed by the successful merge.
- Next implementation must start only from the latest Development HEAD and take `DS2-INV-001`.

### Design QA
- Issued exact-head `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` on `de7c99c...` with `TESTS_AUTHORED_NOT_EXECUTED`.
- Confirmed no known build/type failure, no current material peer contradiction, no forbidden backend/business/deployment scope and no unresolved review thread.
- Left only a non-blocking runtime `WATCH` for `DocumentActions` Mobile sticky-header density/polish.
- Its approval is consumed by the merge and must not be reused for the Inventory slice.

### Development Integrator
- Revalidated current PR/base/head/review markers/threads/diff scope and Development drift.
- Confirmed Development drift after the synchronized base was only Design QA state, so exact-head product review remained fresh.
- Marked PR #32 Ready without moving HEAD and squash-merged it using expected-head protection as `58b0f3f8f54f04636d3a35dd7d658edb7bcf5068`.
- Integration state is `MERGED_GREEN_DEV` for DS2-UI-005.
- Workstream marks DS2-UI-005 DONE and exactly one next slice, DS2-INV-001, READY.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Customer create/update/GPS/lookup/credit/default branch/default contact/Branch-Contact semantics must not drift.
- Sales list query/filter/Desktop+Tablet pagination/Mobile infinite-loading/navigation/permission/status/payment/Smart Transfer/map/call/workflow semantics must not drift.
- Sales Order form customer/product/pricing/discount/tax/total/validation/submit semantics remain page/domain-owned.
- Sales transaction-detail permission/status/workflow/callback/query/service/calculation truth remains page/domain-owned.
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

- Development evidence through DS2-UI-005 remains source-level for the merged slice: no exact-head executed test suite, local build, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- `DocumentActions` remains a legacy shared feature surface; capability parity is preserved, but Mobile sticky-header density/touch polish should be observed during future runtime review.
- Permission-limited empty states should later converge toward neutral explanatory microcopy.
- Dense-table overflow semantics and shared numbered Pagination remain future hardening areas.
- Combobox/ProductLine interaction debt remains real but intentionally deferred until a live screen proves a reusable need.
- Inventory migration may expose genuine InventorySummary/filter/table/card/action gaps; strengthen only the smallest recurring contract proven by the selected live list surface.

## Reusable patterns learned

- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared navigation/action declarations should own placement decisions rather than pages inventing coordinates.
- Canonical `AppAction + resolveActionSet` can drive shared transaction headers while domain pages retain eligibility/callback truth.
- Shared `TransactionHeader` can expose Mobile/Tablet/Desktop action hierarchy without creating a new action taxonomy.
- Form composition can be standardized independently from business field semantics.
- Shared `PageHeader` + `FormSection` + `FormGrid` + `FormActions` has real Customer and Sales form proof points.
- Shared Stepper can support optional guarded interaction without absorbing workflow truth or breaking read-only consumers.
- Complete shared Tabs semantics can be reused through thin domain wrappers.
- Shared `ResponsiveCollection` can preserve distinct page-owned device datasets while owning one presentation boundary.
- Domain adapters should stay thin: shared patterns own presentation, domain/page code owns business truth.
- `Badge` metadata and `StatusBadge` semantic state remain distinct.
- Accessibility semantics should be introduced only at a complete reusable interaction boundary.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Product Design Director should inspect the live Inventory list surfaces and bound the smallest representative presentation-only concern for `DS2-INV-001`, reusing the current V2 list/action/state grammar and avoiding speculative framework expansion.

UI Production Engineer should bootstrap from the exact latest `design-system-v2-development` HEAD and take only `DS2-INV-001`. Design QA should independently review the next stable exact PR HEAD. Development Integrator should no-op until that exact head receives `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` and all normal gates pass.
