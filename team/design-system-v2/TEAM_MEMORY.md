# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Last synchronized development baseline before this memory write: `c48d588b2307ae35cbe45db235b6793fcd300c7c`.
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
- Sidebar TypeScript projection fix
- Design System agent governance / North Star / test policy
- agent team communication protocol
- role-owned Design Director / Implementation / Design QA / Integration state files
- durable Design System decision log

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
- Cross-role disagreements are evidence to synthesize, not a vote.

### UI Production Engineer
- Role state exists and awaits the first material scheduled implementation run.
- Must write exact branch/PR/head, shared patterns used/extended, device/state coverage and honest test evidence.

### Design QA
- Role state exists and awaits the first material exact-head review.
- Must judge both behavioral isolation and system-level design quality.

### Development Integrator
- Role state exists and awaits the first material merge disposition.
- Merge only exact-head `GREEN-DEV` work with no current BLOCKING peer contradiction.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Mobile operational actions remain clear and touch-ready.
- Tablet must not collapse into either oversized mobile or cramped desktop.
- Desktop must remain efficient for dense management/review work.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Semantic actions/statuses are system-owned, not page-color inventions.
- Hidden duplicate device interaction trees should be avoided where device-aware composition exists.
- Existing good operational patterns (attendance, visit execution, work responsiveness) should be learned from rather than flattened.
- Each agent writes only its own specialist state; all agents read every specialist state.
- Durable decisions belong in the Decision Log, routine progress does not.

## Known evidence / risks

- A manual Vercel preview previously exposed a real TypeScript issue in the Sidebar model; it was fixed on the development branch.
- Hosted CI quota is exhausted/limited; absence of GitHub Actions is expected and must not be misreported as test success or failure.
- Runtime visual acceptance is milestone-based and requires user-requested preview.
- State freshness must be checked against the exact development/PR HEAD before another role relies on it.

## Reusable patterns learned so far

- Device-aware composition is preferable to CSS hiding two fully mounted interaction trees.
- Shared navigation/action declarations should own placement decisions rather than each page inventing coordinates.
- Form composition should be standardized independently from business field semantics.
- Feature flags are appropriate for high-risk visual shell replacement before broad rollout.
- Agent communication is role-state based: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

UI Production Engineer should execute `DS2-UI-001` from the exact latest development HEAD, update `UI_IMPLEMENTATION_STATE.md`, and hand off the exact PR HEAD to Design QA.

All roles must read `34_AGENT_TEAM_COMMUNICATION_PROTOCOL.md`, Team Memory, all four peer states and relevant durable decisions before acting.
