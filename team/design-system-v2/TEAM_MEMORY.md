# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-UI-002`.
- Latest product integration commit: `773085994502401a7368eded20926b1308b62e3f` from PR #29.
- Last synchronized development baseline before this Team Memory write: `3cab291fbec18adbbb83720e93b78186d20d91e7`.
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
- complete shared Tabs semantics reused by the Customer flow;
- Design System North Star, test policy, role-state handoff protocol, Team Memory and durable Decision Log.

## Latest completed slice

`DS2-UI-002 — Customer detail secondary tabs/patterns`

Result:
- PR #29 exact reviewed head `1cb3853bf3cf94b2a25edd637d0083006e5d2191` received `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS`.
- Test evidence remained honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`.
- The Draft lifecycle flag was cleared without moving the reviewed HEAD; GitHub then reported the PR mergeable.
- PR #29 was squash-merged as `773085994502401a7368eded20926b1308b62e3f`.
- Customer edit sections now use the existing complete shared `Tabs` contract instead of legacy/local section switching.
- Branch/Contact presentation uses shared `Card`, `SectionHeader`, `KeyValueList`, `StatePanel`, `Button`, neutral `Badge`, and semantic `StatusBadge`.
- Duplicate legacy Customer secondary render trees were removed.
- Existing Customer create/update/GPS/lookup/credit/count/permission behavior remains preserved.
- Existing ResponsiveModal/delete flows and the dense credit-history table remain intentionally deferred from broader shared overlay/DataTable redesign.
- No hosted CI, Vercel preview, backend/business behavior change, or `main` change occurred.

## Current single READY slice

`DS2-UI-003 — Sales Orders list V2`

Intent:
- move the next golden-flow collection screen into shared V2 grammar;
- preserve existing data/query/navigation/permission/status/business behavior;
- prove or minimally strengthen reusable responsive collection, filter/search, status, action and state patterns using the real Sales Orders list;
- Mobile must prioritize record/action clarity without ordinary horizontal overflow;
- Tablet must be deliberate rather than compressed Desktop;
- Desktop must retain useful comparison density;
- no Sales-only mini design system and no speculative global DataTable/FilterBar program unless the real slice proves the smallest reusable shared contract required now.

## Latest role positions

### Product Design Director
- Independently revalidated the exact PR #29 GREEN-DEV head before integration.
- Architectural disposition for DS2-UI-002 was PASS with no integration blocker.
- Two future shared-program WATCH items remain: permission-limited empty-state microcopy and standardized focusable dense-table overflow semantics.
- Its stored role state now describes the merged slice and becomes stale for implementation decisions once DS2-UI-003 starts; it should refresh against the Sales list baseline on its next material run.

### UI Production Engineer
- Completed DS2-UI-002 implementation and handed exact head `1cb3853b...` to QA.
- Its stored role state now describes the merged Customer slice and is stale for new implementation work.
- Next material action is to bootstrap from the latest development HEAD and take only `DS2-UI-003`.

### Design QA
- Issued exact-head `GREEN-DEV` + `SOURCE_REVIEW_PASS` for PR #29 with honest `TESTS_AUTHORED_NOT_EXECUTED` evidence.
- Runtime/preview/release evidence remains unclaimed and separate.
- Its current approval is consumed by the merge and must not be reused for the next Sales slice.

### Development Integrator
- Revalidated exact head/base/scope/role states, cleared Draft state without moving the reviewed head, confirmed mergeability, and squash-merged PR #29.
- Integration state is `MERGED_GREEN_DEV` for DS2-UI-002.
- Workstream now marks DS2-UI-002 DONE and DS2-UI-003 READY.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Customer create/update/GPS/lookup/credit/default branch/default contact/Branch-Contact mutation semantics must not drift during later work.
- Complete shared Tabs keyboard/focus/ARIA/RTL semantics are system-owned; do not reintroduce partial page-local ARIA.
- Neutral metadata counts use neutral Badge semantics; semantic state uses StatusBadge.
- Shared Button/action hierarchy should own touch/action behavior for newly migrated actions.
- Mobile operational actions remain clear and touch-ready.
- Tablet must not collapse into oversized Mobile or cramped Desktop.
- Desktop must remain efficient for dense management/review work.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Semantic actions/statuses are system-owned, not page-color inventions.
- Hidden duplicate device interaction trees should be avoided where device-aware composition exists.
- Each agent writes only its own specialist state; all agents read every specialist state.
- Durable decisions belong in the Decision Log; routine progress does not.
- No hosted CI, Vercel preview, or `main` activity from scheduled agents.

## Known evidence / risks

- Development evidence for DS2-UI-002 is source-level only: no executed test suite, preview build, runtime visual pass or release approval was claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions is expected.
- Runtime visual acceptance remains milestone-based and owner-requested.
- Permission-limited empty states should converge toward neutral explanatory microcopy in the future shared StatePanel/microcopy program.
- Focusable horizontal overflow semantics for dense tables should be standardized in later DataTable/accessibility hardening rather than solved ad hoc per page.
- Sales Orders list may expose real FilterBar/ResponsiveCollection/DataTable gaps; strengthen only the smallest shared contract proven by that screen.

## Reusable patterns learned so far

- Device-aware composition is preferable to CSS hiding duplicate mounted interaction trees.
- Shared navigation/action declarations should own placement decisions rather than each page inventing coordinates.
- Form composition can be standardized independently from business field semantics.
- Shared `PageHeader` + `FormSection` + `FormGrid` + `FormActions` has a real Customer-form proof point.
- Complete shared Tabs semantics can be reused through a thin domain wrapper for labels/counts/visibility without duplicating interaction logic.
- `Badge` metadata and `StatusBadge` semantic state should remain distinct.
- Feature flags remain appropriate for high-risk visual shell replacement before broad rollout.
- Accessibility semantics should be introduced only at a complete reusable interaction boundary.
- Agent communication remains role-state based: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

UI Production Engineer should bootstrap from the exact latest `design-system-v2-development` HEAD and start only `DS2-UI-003 — Sales Orders list V2` within the Workstream scope.

Product Design Director should guide the Sales list toward reusable responsive collection/filter/status/action grammar without speculative abstraction. Design QA should independently review the next exact PR HEAD. Development Integrator should no-op until that exact Sales-list head receives `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` and all normal gates pass.