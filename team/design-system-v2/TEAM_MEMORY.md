# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-UI-003`.
- Latest product integration commit: `e42910fb2bb7c945e67262f610d9e0b630d960a6` from PR #30.
- Last synchronized development baseline before this Team Memory write: `8bde8046822c1900b88ff41b38275fc68349177f`.
- `main` remains frozen until explicit owner approval.
- Vercel preview is user-requested only.
- GitHub Actions / hosted CI remain forbidden for normal Design System development.
- Product target remains one deep, premium Arabic-first operational Design System across the entire EDARA interface.
- Mobile is the primary daily operational surface; Tablet is deliberate; Desktop preserves management density and speed.
- Repository-native shared memory remains active: every scheduled DS2 role reads Team Memory and every peer role state before acting.

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
- Sales Orders list V2 composition (`DS2-UI-003`);
- complete shared Tabs semantics reused by the Customer flow;
- shared ResponsiveCollection proof on a real Sales list with distinct Desktop/Tablet/Mobile data/presentation contracts;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-UI-003 — Sales Orders list V2`

Result:
- PR #30 exact reviewed head `d03dbf4d32e0fb1a3e4888588a5c6d685689f1ff` received `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS`.
- Test evidence remained honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`.
- The Draft lifecycle flag was cleared without moving the reviewed HEAD; GitHub then reported the PR mergeable.
- PR #30 was squash-merged as `e42910fb2bb7c945e67262f610d9e0b630d960a6`.
- `ResponsiveCollection` now owns the one-renderer-at-a-time boundary on Sales Orders.
- Desktop retains the existing paged dense `DataTable`; Tablet uses deliberate cards over the same paged dataset; Mobile keeps accumulated infinite loading.
- Sales KPI/status/card/action/empty-state presentation now composes shared V2 grammar without moving business/query truth out of the page.
- Existing Sales filter/query/pagination/navigation/permission/payment/Smart Transfer/map/call/workflow semantics remain preserved.
- Displayed payment percentage remains page-owned; only progress geometry/ARIA is bounded.
- Legacy Mobile `DataCard` and CSS-hidden duplicate collection trees are removed from this page.
- No hosted CI, Vercel preview, backend/business behavior change, or `main` change occurred.

## Current single READY slice

`DS2-UI-004 — Sales Order form V2 foundation`

Intent:
- continue the Sales golden flow through the real create/edit form;
- select the smallest dependency-safe presentation sub-slice first rather than broad form rewrite;
- reuse shared Field/FormSection/FormGrid/FormActions/Button/Combobox patterns before inventing new primitives;
- preserve all customer/product/pricing/discount/tax/total/validation/submit/query/permission/workflow truth;
- Mobile must retain clear task/action priority without ordinary horizontal overflow;
- Tablet must be deliberate rather than compressed Desktop;
- Desktop must preserve efficient data-entry density;
- any shared Combobox/ProductLine/stepper hardening must be the smallest recurring contract proven by the live form, not speculative abstraction.

## Latest role positions

### Product Design Director
- Its last material state reviewed PR #30 during WIP and set two required boundaries: Tablet presentation must preserve paged data semantics and visual progress normalization must not replace page-projected financial truth.
- Both constraints were resolved on the exact GREEN-DEV/merged head.
- Its PR #30 state is now consumed/stale for new implementation decisions; it should refresh against the Sales Order form before opening any broader shared-form direction.

### UI Production Engineer
- Completed DS2-UI-003 and handed exact head `d03dbf4d...` to QA.
- Its stored role state now describes the merged Sales-list slice and is stale for new implementation work.
- Next material action is to bootstrap from the latest development HEAD and take only DS2-UI-004.

### Design QA
- Issued exact-head `GREEN-DEV` + `SOURCE_REVIEW_PASS` for PR #30 with honest `TESTS_AUTHORED_NOT_EXECUTED` evidence.
- Runtime/preview/release evidence remains unclaimed and separate.
- Its current approval is consumed by the merge and must not be reused for the Sales Order form.

### Development Integrator
- Revalidated exact head/base/scope/role states, cleared Draft without head movement, confirmed mergeability, and squash-merged PR #30.
- Integration state is `MERGED_GREEN_DEV` for DS2-UI-003.
- Workstream now marks DS2-UI-003 DONE and DS2-UI-004 READY.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Customer create/update/GPS/lookup/credit/default branch/default contact/Branch-Contact mutation semantics must not drift during later work.
- Sales list query/filter/Desktop+Tablet pagination/Mobile infinite-loading/navigation/permission/status/payment/Smart Transfer/map/call/workflow semantics must not drift during later work.
- Sales Order form customer/product/pricing/discount/tax/total/validation/submit semantics remain page/domain-owned during DS2-UI-004.
- Complete shared Tabs keyboard/focus/ARIA/RTL semantics are system-owned; do not reintroduce partial page-local ARIA.
- Neutral metadata counts use neutral Badge semantics; semantic state uses StatusBadge.
- Shared Button/action hierarchy should own touch/action behavior for newly migrated actions.
- Mobile operational actions remain clear and touch-ready.
- Tablet must not collapse into oversized Mobile or cramped Desktop.
- Desktop must remain efficient for dense management/review/data-entry work.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Semantic actions/statuses are system-owned, not page-color inventions.
- Hidden duplicate device interaction trees should be avoided where device-aware composition exists.
- Each agent writes only its own specialist state; all agents read every specialist state.
- Durable decisions belong in the Decision Log; routine progress does not.
- No hosted CI, Vercel preview, or `main` activity from scheduled agents.

## Known evidence / risks

- Development evidence for DS2-UI-003 is source-level only: no executed test suite, preview build, runtime visual pass or release approval was claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- Permission-limited empty states should converge toward neutral explanatory microcopy in the future shared StatePanel/microcopy program.
- Focusable horizontal overflow semantics for dense tables should be standardized in later DataTable/accessibility hardening rather than solved ad hoc per page.
- Desktop/Tablet numbered pagination should later converge into one shared accessible Pagination/DataTable contract when that real shared-depth program opens.
- Progress/accessibility hardening should consider `aria-valuetext` for projected values above 100 while visual geometry remains bounded.
- DS2-UI-004 may expose real Combobox/ProductLine/long-form composition gaps; strengthen only the smallest shared contract proven by the selected form sub-slice.

## Reusable patterns learned so far

- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared navigation/action declarations should own placement decisions rather than each page inventing coordinates.
- Form composition can be standardized independently from business field semantics.
- Shared `PageHeader` + `FormSection` + `FormGrid` + `FormActions` has a real Customer-form proof point.
- Complete shared Tabs semantics can be reused through a thin domain wrapper for labels/counts/visibility without duplicating interaction logic.
- Shared `ResponsiveCollection` can preserve distinct page-owned device datasets while owning a single presentation boundary.
- Domain cards should compose shared primitives rather than becoming new cross-system primitives by default.
- Page-projected business values may remain distinct from bounded visual geometry/ARIA constraints.
- `Badge` metadata and `StatusBadge` semantic state should remain distinct.
- Feature flags remain appropriate for high-risk visual shell replacement before broad rollout.
- Accessibility semantics should be introduced only at a complete reusable interaction boundary.
- Agent communication remains role-state based: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

UI Production Engineer should bootstrap from the exact latest `design-system-v2-development` HEAD and take only `DS2-UI-004 — Sales Order form V2 foundation`, first identifying the smallest presentation-only form sub-slice that can be completed and independently reviewed without touching Sales business truth.

Product Design Director should bound shared form/combobox/product-line direction from the live form rather than pre-design a broad form framework. Design QA should independently review the next stable exact PR HEAD. Development Integrator should no-op until that exact head receives `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` and all normal gates pass.
