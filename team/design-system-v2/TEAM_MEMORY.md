# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product integration completed through `DS2-UI-001` on squash merge commit `cdcc1a57cc3367fdd161fddb3d9e5b42e92e4829`.
- Last synchronized development baseline before this Team Memory write: `0f0098480817082eceb2c393a8af0d84cbe80470`.
- `main` is frozen for this workstream until explicit user approval.
- Vercel preview is user-requested only.
- GitHub Actions / hosted CI are not to be triggered for Design System development PRs.
- Product target: one deep, premium Arabic-first operational Design System across the entire EDARA interface.
- Mobile is the primary daily operational surface; Tablet is deliberate; Desktop preserves management density and speed.
- Repository-native shared memory is active: all scheduled DS2 roles read Team Memory + all peer role states before acting.

## Current integrated baseline

The development branch includes:
- semantic foundations and V2 primitives/patterns
- responsive collection/action/form composition foundations
- navigation registry and deliberate tablet shell
- Sidebar V2 behind a feature flag
- Dashboard V2 migration
- Customers List V2 migration
- Customer basic-info form V2 composition (`DS2-UI-001`)
- Sidebar TypeScript projection fix
- Design System agent governance / North Star / test policy
- repository-native team communication protocol and role-state system
- durable Design System decision log

## Latest completed slice

`DS2-UI-001 — Customer Form: basic-info composition`

Result:
- PR #28 exact reviewed head `b6bfceeb8327437e274222c7e2f75e83c4a65061` received `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS`.
- Test evidence remained honestly labeled `TESTS_AUTHORED_NOT_EXECUTED`.
- PR #28 was squash-merged as `cdcc1a57cc3367fdd161fddb3d9e5b42e92e4829`.
- Customer basic-info composition now uses shared `PageHeader`, `FormSection`, `FormGrid`, and `FormActions`.
- Existing create/update, GPS, credit permission, lookup, default branch/contact and secondary Customer behavior remains preserved.
- The previous partial ARIA Tabs blocker was resolved before merge: legacy section-switch controls remain ordinary non-submitting buttons; incomplete `tablist` / `tab` / `aria-selected` semantics are absent.
- No hosted CI, Vercel preview, backend/business behavior change, or `main` change occurred.

## Current READY direction

Current single READY slice:
`DS2-UI-002 — Customer detail secondary tabs/patterns`

Intent:
- continue the Customer golden flow without reopening the completed basic-info slice
- migrate branches / contacts / credit secondary surfaces into the shared V2 language
- use the real Customer section-switch need to establish/adopt a reusable complete Tabs/SubNav contract if semantics are introduced
- preserve existing section visibility, counts, handlers, permissions and business behavior
- keep dialogs/destructive-confirmation redesign deferred until shared overlay contracts are ready
- avoid a Customer-local mini design system

## Latest role positions

### Product Design Director
- Exact PR #28 GREEN-DEV head was independently revalidated as architectural PASS before merge.
- The previous partial-tab-semantics watchpoint is resolved.
- Shared Tabs/SubNav remains a proven future component-depth need and should be implemented at a complete reusable semantic boundary rather than piecemeal.

### UI Production Engineer
- Completed the bounded QA fix on PR #28 and handed exact head `b6bfceeb...` to QA.
- Its state file still describes the now-merged PR lifecycle; the next material run should refresh implementation state against the latest development head and `DS2-UI-002`.

### Design QA
- Issued `AGENT-REVIEW: GREEN-DEV` on exact PR #28 head `b6bfceeb...` with `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`.
- Runtime/preview/release evidence remains unclaimed and separate.
- Its next material state should target the next implementation PR/head, not reopen the merged slice without new evidence.

### Development Integrator
- Revalidated all merge gates, transitioned the reviewed Draft PR to Ready for Review without moving its head, and squash-merged it.
- Integration state is `MERGED_GREEN_DEV` for DS2-UI-001.
- Workstream now marks DS2-UI-001 DONE and DS2-UI-002 READY.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Customer create/update/GPS/lookup/credit/default branch/default contact semantics must not drift during secondary-surface migration.
- Mobile operational actions remain clear and touch-ready.
- Tablet must not collapse into either oversized mobile or cramped desktop.
- Desktop must remain efficient for dense management/review work.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Semantic actions/statuses are system-owned, not page-color inventions.
- Hidden duplicate device interaction trees should be avoided where device-aware composition exists.
- Existing good operational patterns should be learned from rather than flattened.
- Each agent writes only its own specialist state; all agents read every specialist state.
- Durable decisions belong in the Decision Log, routine progress does not.
- Do not reintroduce a partial ARIA Tabs widget contract. If shared Tabs/SubNav semantics are introduced, keyboard/focus/panel relationships must be complete enough for the shared component contract.

## Known evidence / risks

- Development evidence for DS2-UI-001 is source-level only: no executed test suite, preview build, runtime visual pass or release approval was claimed.
- Hosted CI quota protection remains active; absence of GitHub Actions is expected.
- Runtime visual acceptance is milestone-based and requires user-requested preview.
- `DS2-UI-002` can expose shared Tabs/SubNav and overlay-pattern gaps; solve only the reusable UI contract proven by the real Customer flow and avoid speculative broad redesign.
- Role-state freshness must be checked against the exact current development/PR HEAD before relying on older lifecycle text.

## Reusable patterns learned so far

- Device-aware composition is preferable to CSS hiding two fully mounted interaction trees.
- Shared navigation/action declarations should own placement decisions rather than each page inventing coordinates.
- Form composition can be standardized independently from business field semantics.
- Shared `PageHeader` + `FormSection` + `FormGrid` + `FormActions` now has a real Customer-form proof point.
- Feature flags are appropriate for high-risk visual shell replacement before broad rollout.
- Accessibility semantics should be introduced only when the full shared interaction contract is supportable; partial ARIA roles are worse than honest ordinary-button semantics.
- Agent communication remains role-state based: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

UI Production Engineer should bootstrap from the exact latest `design-system-v2-development` HEAD, refresh `UI_IMPLEMENTATION_STATE.md`, and execute only `DS2-UI-002` within the documented scope. It should preserve the completed basic-info form and establish/adopt shared Tabs/SubNav semantics only at a reusable complete boundary.

Product Design Director should keep the Tabs/SubNav requirement coherent and prevent speculative Customer-only navigation abstractions. Design QA should independently review the next exact PR HEAD. Development Integrator should no-op until a new exact `GREEN-DEV` head exists.
