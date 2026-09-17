# Design Director State

## Reviewed baseline

- Review date: `2026-09-17`
- Development branch: `design-system-v2-development`
- Exact Development HEAD inspected before architecture write: `a44ce6e14a6a1fbbfd6d8663294daef3af5628b9`
- Current coordination HEAD after Workstream boundary write: `212b2ca93608c2a853e7b4c7c2832858fde12844`
- Latest integrated product slice: `DS2-FIELD-001`, squash `cac61006d5c6ac402a509c2f15fb09ce51bafd50`.
- Open implementation PRs targeting Development at review: `NONE`.
- Current single READY slice: `DS2-FIELD-002 — Activity create/edit form composition foundation`.
- Representative surface: live `src/pages/activities/ActivityForm.tsx`, normal create/edit path only.
- Product Design disposition: `READY — DEPENDENCY-SAFE / PRESENTATION-ONLY`.
- Blocker: `NONE`.

## Independent professional judgment

**FIELD002 should begin with the normal Activity create/edit form composition, not with a broad Activity/Visit/Call/Target redesign and not with ActivityDetail.**

The source already exposes the recurring system gap we need to solve: the live `ActivityForm` owns a large page-local form shell (`edara-card act-form`, local timing grid, local action row and inline CSS) while the Design System already has proven `FormSection + FormGrid + FormActions + Button` contracts. At the same time, this page contains high-risk GPS, query, validation, customer, target/history, sales-linking and call-detail semantics. The correct Design-System move is therefore a narrow composition extraction around the existing task flow, leaving every functional rule where it is.

This advances the North Star more than a cosmetic ActivityDetail restyle because it proves the shared create/edit grammar on a mobile-primary Field workflow without inventing Field-specific primitives.

## Architecture boundary

### In scope

1. Replace the normal create/edit path's local outer form-shell composition with shared V2 `FormSection` composition. Section boundaries must follow the existing user task sequence; no functional step may be reordered around conditional target/history/link/call surfaces.
2. Use shared `FormGrid` only for safe field groupings. The date/start/end area is the clearest proof: Mobile one column, Tablet deliberately capped at two columns, Desktop may retain efficient density. GPS and complex conditional surfaces may remain full-width.
3. Replace the local `act-form-actions` presentation with shared `FormActions + Button`, preserving exact cancel/submit callbacks, labels, save loading copy, `saving` disabled truth and `gpsBlocking` submit suppression. `stickyOnMobile` is explicitly **not** part of this slice.
4. Preserve native/raw control semantics and values. Do not opportunistically convert the customer selector, select/input/textarea fields or call-direction controls to new primitives in FIELD002. For composition-touched controls, visible Arabic labels must be programmatically associated and existing required/disabled semantics retained.
5. Retire only page-local CSS made dead by shared form composition. Consumer-owned tokenized logical spacing may separate shared sections; do not add global external margins to `FormSection`.
6. Author focused test/source contracts protecting shared-form adoption and the existing functional boundaries. Normal evidence remains `TESTS_AUTHORED_NOT_EXECUTED` unless an approved execution environment actually runs them.

### Explicit exclusions

- visit-plan guard/blocker screen and its routing behavior;
- `GPSStatusIndicator` internals, acquisition/verification/distance/permission semantics;
- target-gamification alert and customer recent-history queries/content;
- order/collection linking sections and their navigation;
- call-detail data, direction controls, callback/recording behavior and `useSaveCallDetail` semantics;
- toast/validation-message convergence or any validation-rule change;
- payload construction, Supabase queries, services/mutations, query-cache semantics;
- customer-selector / AsyncCombobox work or broad Input/Select primitive migration;
- sticky mobile actions;
- `ActivityDetail`, visit/call plan forms/details, targets, checklists or a broad Field framework;
- DB/migration/RPC/RBAC/RLS/permissions/business/workflow/routes/deployment/preview/`main` changes.

## Acceptance contract

- **Mobile (`<=768px`):** single-column operational flow; no ordinary horizontal overflow; shared action controls remain touch-safe and stretch cleanly; no new sticky surface competes with BottomNav/FAB; long Arabic labels/values wrap safely.
- **Tablet (`769–1024px`):** deliberate two-column composition only for safe field groups; GPS/complex conditional content can remain full-width; touch remains first-class; no compressed Desktop three-column layout.
- **Desktop (`>=1025px`):** preserve the current bounded efficient form width, field capability and task order; grouped fields may use shared-grid density without reducing readability.
- **States:** create/edit labels, customer-loading fallback, outcome disabled before activity type, conditional customer/outcome/reason/call/link surfaces, GPS-required warning, save loading/disabled state, cancel/navigation and current validation outcomes remain semantically unchanged.
- **Accessibility / RTL:** Arabic-first logical layout; labels for touched controls are associated with controls; native required/disabled semantics remain; shared Buttons retain keyboard/focus behavior; no new color-only meaning.
- **Functional isolation:** activity query/service/route/GPS/validation/payload/mutation/workflow truth remains exactly page/domain-owned.

## Stop condition

If adopting the shared form composition requires changing routing, GPS truth, validation meaning, query/service behavior, payload construction or workflow semantics, FIELD002 is `BLOCKED`; isolate that functional defect instead of absorbing it into Design System scope.

## Peer-state comparison / contradiction synthesis

I formed the architecture judgment above before comparing the peer states.

- **Team Memory:** aligned on FIELD002 as the sole next Field create/detail slice, but intentionally broad; this state/workstream now provides the required implementation boundary.
- **Development Integrator:** fresh for the FIELD001 merge and explicitly hands FIELD002 boundary ownership to Product Design. Aligned.
- **UI Production Engineer:** lifecycle-stale from FIELD001 implementation. It is informative only and contains no current competing FIELD002 implementation.
- **Design QA:** lifecycle-stale from FIELD001 exact-head review. No FIELD002 disposition exists yet.
- **Previous Product Design state:** lifecycle-stale after FIELD001 merge and superseded by this state.
- **Open PR inspection:** no implementation PR targets `design-system-v2-development`, so defining this one READY concern does not create a competing slice.

There is **no current BLOCKING cross-role contradiction**. No Team Memory change is necessary because overall system direction and durable invariants did not change; only the already-READY Field slice was bounded for execution. No Decision Log entry is warranted because no new long-lived rule was introduced.

## What changed since previous state

FIELD001 review/merge work is consumed. Product Design has now converted the broad FIELD002 placeholder into one implementation-safe concern: ActivityForm normal create/edit composition using the established shared V2 form grammar, with strict functional exclusions and explicit Mobile/Tablet/Desktop/state/accessibility acceptance.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA after a stable implementation HEAD; Development Integrator after fresh GREEN-DEV.
- **What changed:** `DS2-FIELD-002` is now concretely bounded to the live ActivityForm normal create/edit composition foundation using existing `FormSection + FormGrid + FormActions + Button`; no other Field create/detail surface is part of this PR.
- **Preserve:** visit-plan guard/routing; activity type/customer/outcome/date/time values and ordering; GPS requirement/acquisition/coordinates/distance/blocking truth; target/history behavior; order/collection links; call-detail behavior; validation rules; payload construction; create/update/save-call-detail mutations; queries/cache; permissions/workflow/routes; existing cancel/navigation outcomes.
- **Need from you:** UI Production Engineer should branch from the exact latest Development HEAD and open exactly one PR for this bounded concern, with focused authored regression contracts and no functional expansion. Design QA should independently review the exact stable PR HEAD. Integrator should no-op until fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and normal gates exist.
- **Blocker level:** `NONE`.
- **Baseline:** architecture inspected on Development `a44ce6e14a6a1fbbfd6d8663294daef3af5628b9`; Workstream boundary commit/current coordination baseline before this state write `212b2ca93608c2a853e7b4c7c2832858fde12844`; no active PR.