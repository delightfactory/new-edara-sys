# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-UI-004`.
- Latest product integration commit: `d00faf8e36d40c9dde9df0b2de6dc89737419c5d` from PR #31.
- Workstream synchronization commit: `028059587debbb19223e406784e5b3ff7aa54eb8`.
- Integration-state synchronization commit: `c2e0112d6452b5bc0dd3cb2c794d5fd209774a66`.
- `main` remains frozen until explicit owner approval.
- Vercel preview is user-requested only.
- GitHub Actions / hosted CI remain forbidden for normal Design System development.
- Product target remains one deep, premium Arabic-first operational Design System across the entire EDARA interface.
- Mobile is the primary daily operational surface; Tablet is deliberate; Desktop preserves management/data-entry density and speed.
- Repository-native shared memory remains active: every scheduled DS2 role reads Team Memory and peer role states before acting.

## Current integrated system

The development branch includes:
- semantic foundations and V2 primitives/patterns;
- responsive collection/action/form composition foundations;
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
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-UI-004 — Sales Order form V2 foundation`

Result:
- PR #31 exact reviewed head `198f146a3abde9efa6bfb3c98c20469f3815d3ff` received `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS`.
- Test evidence remained honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`.
- The prior P2 Desktop-density blocker was closed at the presentation boundary: Step 0 now uses shared `columns={3}` => 3 Desktop / 2 Tablet / 1 Mobile, with full-width customer/credit rows preserved.
- Shared `Stepper` was evolved backward-compatibly: read-only remains default; optional page-owned guarded interaction and wrapped Mobile layout are available when a real workflow requires them.
- Sales workflow reachability and validation remain page-owned rather than moving into the visual primitive.
- Shared `FormSection`, `FormGrid`, `FormActions` and `Button` now own the outer presentation grammar for the migrated form slice.
- RTL previous/next cues are native and consistent.
- Create/edit/copyFrom, customer/branch/rep, product/unit/stock, pricing/discount/tax/shipping/totals/minimum-order, permissions, validation/toasts, save sequence, routes and Mobile add-product modal behavior remain preserved.
- Customer/product Combobox and ProductLine redesign remain deliberately deferred until a later live screen proves the recurring need.
- No hosted CI, Vercel preview, backend/business behavior change or `main` change occurred.

## Current single READY slice

`DS2-UI-005 — Sales transaction detail V2`

Intent:
- continue the Sales golden flow through the real transaction-detail surface;
- first select the smallest dependency-safe presentation-only sub-slice rather than broad detail-page rewrite;
- reuse shared detail/header/status/financial/key-value/action/timeline/state grammar where already available;
- strengthen only the smallest reusable detail contract proven necessary by the live screen;
- preserve every displayed value, workflow action, permission, route, query and business transition;
- Mobile must retain clear primary/secondary/destructive action priority;
- Tablet must be deliberate rather than compressed Desktop;
- Desktop must preserve dense review/management efficiency;
- Arabic/RTL, long values, loading/error/permission states and destructive confirmations remain first-class.

## Latest role positions

### Product Design Director
- Last material state targeted prior blocked PR #31 head `6841ceb...` and agreed the only remaining blocker was Step 0 Desktop density.
- That exact blocker was corrected and independently closed by Design QA on later head `198f146a...`.
- Its prior BLOCKING state is therefore stale/consumed and must not be applied to DS2-UI-005.
- Next material action is to inspect the live Sales transaction-detail surface and bound the smallest shared detail/header/summary/action direction without speculative framework expansion.

### UI Production Engineer
- Corrected the bounded PR #31 P2 and handed exact head `198f146a...` for re-review.
- That state is now consumed by the successful merge.
- Next action is to bootstrap from the exact latest development HEAD and take only DS2-UI-005.

### Design QA
- Issued exact-head `GREEN-DEV` + `SOURCE_REVIEW_PASS` for PR #31 with honest `TESTS_AUTHORED_NOT_EXECUTED` evidence.
- Confirmed the prior P2 density blocker closed and no still-current BLOCKING contradiction remained.
- Runtime/preview/release evidence remains unclaimed and separate.
- Its approval is consumed by the merge and must not be reused for DS2-UI-005.

### Development Integrator
- Revalidated exact head/base/scope/peer-state freshness and development drift.
- Cleared Draft without moving the reviewed HEAD and squash-merged PR #31 as `d00faf8e36d40c9dde9df0b2de6dc89737419c5d`.
- Integration state is `MERGED_GREEN_DEV` for DS2-UI-004.
- Workstream now marks DS2-UI-004 DONE and DS2-UI-005 READY.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Customer create/update/GPS/lookup/credit/default branch/default contact/Branch-Contact semantics must not drift.
- Sales list query/filter/Desktop+Tablet pagination/Mobile infinite-loading/navigation/permission/status/payment/Smart Transfer/map/call/workflow semantics must not drift.
- Sales Order form customer/product/pricing/discount/tax/total/validation/submit semantics remain page/domain-owned.
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

- Development evidence through DS2-UI-004 remains source-level only: no executed test suite, preview build, runtime visual pass or release approval is claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- Permission-limited empty states should later converge toward neutral explanatory microcopy.
- Dense-table overflow semantics and shared numbered Pagination remain future hardening areas.
- Progress/accessibility hardening should later consider `aria-valuetext` for projected values above 100 while visual geometry stays bounded.
- Combobox/ProductLine interaction debt remains real but intentionally deferred; open only when the next live slice proves a concrete reusable need.
- DS2-UI-005 may expose a genuine TransactionHeader/FinancialSummary/action/timeline gap; strengthen only the smallest recurring contract proven by the live detail screen.

## Reusable patterns learned

- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared navigation/action declarations should own placement decisions rather than pages inventing coordinates.
- Form composition can be standardized independently from business field semantics.
- Shared `PageHeader` + `FormSection` + `FormGrid` + `FormActions` has real Customer and Sales form proof points.
- Shared Stepper can support optional guarded interaction without absorbing workflow truth or breaking read-only consumers.
- Complete shared Tabs semantics can be reused through thin domain wrappers.
- Shared `ResponsiveCollection` can preserve distinct page-owned device datasets while owning one presentation boundary.
- Domain cards should compose shared primitives rather than becoming new cross-system primitives by default.
- `Badge` metadata and `StatusBadge` semantic state remain distinct.
- Feature flags remain appropriate for high-risk visual shell replacement before broad rollout.
- Accessibility semantics should be introduced only at a complete reusable interaction boundary.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

UI Production Engineer should bootstrap from the exact latest `design-system-v2-development` HEAD and take only `DS2-UI-005 — Sales transaction detail V2`, first identifying the smallest presentation-only detail sub-slice that can be completed and independently reviewed without touching Sales business truth.

Product Design Director should bound reusable transaction-header/financial-summary/action/timeline direction from the live screen rather than pre-design a broad detail framework. Design QA should independently review the next stable exact PR HEAD. Development Integrator should no-op until that exact head receives `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` and all normal gates pass.
