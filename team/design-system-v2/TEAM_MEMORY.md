# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- `main` is frozen for this workstream until explicit user approval.
- Vercel preview is user-requested only.
- GitHub Actions / hosted CI are not to be triggered for Design System development PRs.
- Product target: one deep, premium Arabic-first operational Design System across the entire EDARA interface.
- Mobile is the primary daily operational surface; Tablet is deliberate; Desktop preserves management density and speed.

## Current integrated baseline

Development HEAD before this communication-system initialization includes:
- semantic foundations and V2 primitives/patterns
- responsive collection/action/form composition foundations
- navigation registry and deliberate tablet shell
- Sidebar V2 behind a feature flag
- Dashboard V2 migration
- Customers List V2 migration
- Sidebar TypeScript projection fix
- Design System agent governance / North Star / test policy

## Current active direction

Current READY slice:
`DS2-UI-001 — Customer Form: basic-info composition`

Intent:
- migrate presentation composition only
- preserve all customer create/update, GPS, credit permission, lookup and default branch/contact behavior
- use shared V2 patterns rather than create page-local primitives

## Latest role positions

### Design Director
- Build the Design System as a product language, not as page-by-page beautification.
- Shared patterns should mature whenever a recurring need is proven by a real screen.
- No module should become a visual island.

### UI Production Engineer
- No current role-owned state yet. First scheduled run should claim/continue the current READY slice and initialize `UI_IMPLEMENTATION_STATE.md` only when material work occurs.

### Design QA
- No current role-owned state yet. First material review should initialize exact-head disposition and evidence level.

### Development Integrator
- No current role-owned state yet. Merge only exact-head `GREEN-DEV` PRs into development.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Mobile operational actions remain clear and touch-ready.
- Tablet must not collapse into either oversized mobile or cramped desktop.
- Desktop must remain efficient for dense management/review work.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Semantic actions/statuses are system-owned, not page-color inventions.
- Hidden duplicate device interaction trees should be avoided where device-aware composition exists.
- Existing good operational patterns (attendance, visit execution, work responsiveness) should be learned from rather than flattened.

## Known evidence / risks

- A manual Vercel preview previously exposed a real TypeScript issue in the Sidebar model; it was fixed on the development branch.
- Hosted CI quota is exhausted/limited; absence of GitHub Actions is expected and must not be misreported as test success or failure.
- Runtime visual acceptance is milestone-based and requires user-requested preview.

## Reusable patterns learned so far

- Device-aware composition is preferable to CSS hiding two fully mounted interaction trees.
- Shared navigation/action declarations should own placement decisions rather than each page inventing coordinates.
- Form composition should be standardized independently from business field semantics.
- Feature flags are appropriate for high-risk visual shell replacement before broad rollout.

## Next handoff

UI Production Engineer should execute `DS2-UI-001` from the exact latest development HEAD, then hand off the exact PR HEAD to Design QA.

All roles must read the communication protocol and all role states before acting.
