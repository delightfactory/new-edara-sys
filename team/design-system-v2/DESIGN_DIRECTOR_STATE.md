# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-18`.
- Authoritative branch: `design-system-v2-development`.
- Development HEAD inspected before Director writes: `530ad16afb589d318c3c31f6ae67d4f6d109a7e1`.
- Latest integrated product slice: `DS2-WORK-002`, merged via `add39ea8ee76b61d9a5a5938aa6cd03e2cc13456`.
- Open implementation PRs targeting Development at decision time: none.
- Active/next slice: `DS2-WORK-003 — Supervisor operational summary metric convergence`.
- Slice state: `READY` for one UI implementation PR.
- Product Design disposition: `READY — dependency-safe bounded presentation slice; no functional semantics authorized`.
- Workstream scope commit created this run: `7df1227cb93b48a65ce39387ec4b776651019004`.

## Independent Product Design judgment

The next safe Work step is not a broad Work Detail redesign. `WorkDetailCorePage` and `WorkDetailAdministration` are dense with responsibility, acknowledgement, lifecycle, permission, mutation, escalation, due-date and state-version semantics; entering those surfaces before isolating a proven presentation concern would couple Design System work to business truth.

The safer proof is the four-metric operational summary on `/work/team`. `SupervisorWorkPage` currently recomputes `active`, `overdue`, `blocked` and `atRisk` correctly from `overview.data` but renders them through the Work-local `.work-summary-grid` / `.work-summary-card` mini-system. V2 already has stable shared `MetricGrid` and `StatCard` contracts whose stated responsibility is exactly responsive KPI composition and semantic presentation while leaving metric calculation/meaning caller-owned.

This is a system-pattern migration, not page beautification: it exercises the established metric grammar on a management surface while deliberately leaving Work lifecycle/state-machine semantics untouched.

## Bounded WORK003 contract

### In scope

- Target only `src/pages/work/SupervisorWorkPage.tsx` summary metrics.
- Preserve the exact four rendered metrics and existing calculations from `overview.data`: `active`, `overdue`, `blocked`, `atRisk`.
- Preserve exact Arabic labels and existing icons.
- Replace the page-local summary layout/cards with shared `MetricGrid columns={4}` + `StatCard`.
- Fixed semantic presentation mapping for this proof: active=`neutral`, overdue=`danger`, blocked=`danger`, atRisk=`warning`.
- Keep a text-readable accessible summary grouping; color must never carry meaning alone.
- Add focused tests/source assertions for shared adoption, metric order/labels/values and preserved supervisor filter/query ownership.

### Device / RTL / accessibility acceptance

- **Mobile (`<=768px`)**: canonical `MetricGrid` one-column layout; no horizontal page overflow, clipping or Arabic truncation.
- **Tablet (`769–1024px`)**: canonical two-column metric layout.
- **Desktop (`>=1025px`)**: four equal-width dense metrics in one row, subordinate to the page header and before filters/list content.
- **RTL/Arabic**: no physical left/right layout dependency; exact labels remain wrapping-safe.
- **Accessibility**: metrics remain non-interactive, labels/values remain readable without semantic color, and `StatCard` decorative icons remain hidden from assistive technology.

### Explicit exclusions

Do not change:
- `useSupervisorOverview`, `assignee`, `attentionOnly`, `people`, metric calculations or status/flag derivation;
- header/back action, filter select/checkbox, loading/error/empty states, work-item cards, badges, next-action content, due/follow-up text or navigation;
- Work Hub summary cards or completed WORK001/WORK002 surfaces;
- Work Detail/Core/Administration/Extensions/DueGovernance, Submit Request or management/configuration flows;
- shared `MetricGrid`, `StatCard`, tokens or global responsive contracts unless a verified defect makes this exact slice impossible; in that case mark `BLOCKED` instead of widening scope;
- `.work-summary-*` CSS globally because Work Hub still uses that legacy family;
- backend, services, queries/cache, permissions, ownership/responsibility, validation, workflow, state-machine, RBAC/RLS, preview/deployment/hosted CI/`main`.

## Evidence / system fit

- `SupervisorWorkPage.tsx` has a local four-card operational summary and derives metrics from `overview.data`; the summary itself is presentation-only.
- Shared `MetricGrid` owns canonical 4-column Desktop -> 2-column Tablet -> 1-column Mobile KPI composition and does not calculate metrics.
- Shared `StatCard` owns label/value/icon hierarchy and semantic tone while explicitly leaving KPI meaning to the caller.
- Existing Work local summary CSS is broader and still used by Work Hub, so WORK003 must not perform global cleanup.
- `WorkDetailAdministration` contains permission-gated mutations, state-versioned actions, delegation/transfer/escalation/due/subtask semantics; it is intentionally excluded from this slice.

## Peer-state synthesis

The Product Design judgment above was formed from current source and shared V2 contracts before peer comparison.

- **Development Integrator:** current and aligned on lifecycle: WORK002 is merged and exactly one WORK003 placeholder was queued for Product Design boundary selection. This state now supplies that boundary.
- **Design QA:** its last exact-head approval concerns completed WORK002; it is informative but not approval evidence for WORK003.
- **UI Production Engineer:** last implementation state concerns WORK002; no WORK003 implementation PR exists yet.
- **Team Memory:** current integration truth remains valid; no overall North-Star or long-lived design direction changed, so no Director mutation is warranted.
- **Decision Log:** no durable rule changed; no update warranted.

No current cross-role `BLOCKING` contradiction exists. The only active requirement is strict scope discipline when WORK003 implementation begins.

## What changed since previous Director state

- WORK002 moved from reviewed-open to integrated/DONE through the Integrator lane.
- Product Design inspected the new Development baseline, representative Work Detail/Administration risk, Supervisor/Team surface, shared metric contracts and current Work-local CSS.
- The broad WORK003 placeholder is now reduced to one dependency-safe concern: Supervisor operational summary metrics only.
- No product code, peer specialist state, Team Memory, Decision Log, GitHub Actions, Vercel, preview branch, `main`, deployment or merge action was performed.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA and Development Integrator observe until an exact stable PR HEAD exists.
- **What changed:** `DS2-WORK-003` is now implementation-ready and bounded exclusively to `/work/team` four-metric summary convergence onto shared `MetricGrid + StatCard`.
- **Preserve:** exact metric calculations/labels/order, supervisor query/filter/permission/routing truth, non-interactive metric semantics, canonical Mobile/Tablet/Desktop shared metric layout, all Work lifecycle/state-machine behavior, and the one-active-slice rule.
- **Need from you:** UI Production Engineer opens exactly one PR from latest `design-system-v2-development`, implements only the documented WORK003 boundary, authors focused tests without using hosted CI, and records the exact PR HEAD for independent QA/Director review. If shared metric contracts cannot support the slice without wider functional/global changes, mark it `BLOCKED` rather than expanding scope.
- **Blocker level:** `NONE`.
- **Baseline:** Product Design source decision on Development `530ad16afb589d318c3c31f6ae67d4f6d109a7e1`; bounded Workstream scope commit `7df1227cb93b48a65ce39387ec4b776651019004`.
