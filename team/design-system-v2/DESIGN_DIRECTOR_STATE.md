# Design Director State

## Reviewed baseline

- Review date: `2026-09-17`.
- Development branch: `design-system-v2-development`.
- Exact product Development HEAD independently inspected before coordination writes: `22962d71674be08d7f04805b213d8c423a211b2a`.
- Latest integrated product slice: `DS2-FIELD-002`, squash `2492fa475e7bc5beb9148124f31a4b4837057c19`.
- Open implementation PRs targeting Development at review: `NONE`.
- Product Design disposition: `DS2-WORK-001 READY — Create Task form composition foundation`.
- Workstream boundary commit: `2b3326a5f445a3461893d1fd3397cf5619c4616b`.
- Blocker: `NONE`.

## Independent professional judgment

**The smallest dependency-safe Work Management entry point is `/work/new` (`CreateTaskPage`) and specifically its local form grammar, not the Work Hub or stateful Work detail.**

I formed this judgment from the latest Work source and the established V2 form contracts before relying on peer lifecycle states. Work Management is already one of the repository's strongest responsive modules, but it still carries a broad CSS island and local form primitives. `CreateTaskPage` duplicates `work-form-card`, `work-form-grid`, `work-form-actions` and `work-field` even though V2 now has proven `FormSection`, `FormGrid`, `FormActions`, `Field` and shared `Button` contracts. At the same time, the page's actual task semantics remain clearly page/domain-owned, making this a high-value presentation migration without entering Work's critical state machine.

The Work Hub is intentionally not the first slice. Its clickable summary metrics, multi-permission action surface, local search/mode controls and operational queue states expose several separate pattern questions; bundling those into the first Work PR would violate the one-concern rule. Work detail is even less appropriate because its transition/ownership/approval semantics are state-machine critical.

## WORK001 architecture boundary

### In scope

- Route/surface: `/work/new` only.
- Source: `src/pages/work/CreateTaskPage.tsx` plus only directly necessary presentation tests/styles.
- Replace the four existing visual section shells with shared `FormSection`, preserving exact order, titles and content.
- Replace safe paired field layouts with `FormGrid columns={2}`; full-width fields remain intentionally full-width.
- Move standard text/select/textarea field anatomy touched by the slice to shared `Field`, preserving labels, hints, errors, native control types, values, callbacks and current max-length/disabled behavior.
- Replace local cancel/submit row composition with non-sticky `FormActions + Button` while preserving secondary cancel, primary submit, loading state and callbacks.
- Keep the existing `PageHeader` unchanged.
- Remove only CreateTask-specific local form-shell CSS that becomes unused because of this migration; no broad Work CSS cleanup.

### Explicitly out of scope

- `validate()` semantics, message wording and the `nextActionAt > dueAt` rule.
- `useAssignmentCandidates`, default candidate selection, owner/accountability meaning, assignee/current-ball meaning, acknowledgement eligibility/reset, completion mode, priority or visibility semantics.
- `useCreateTask`, `toIso`, payload shape, `activate: true`, toast outcomes and post-create navigation.
- The acknowledgement checkbox grammar and selected owner/assignee summary cells.
- Work Hub, Submit Request, Supervisor, management, Work detail, sticky task actions, badges and operational flags.
- Select/Combobox convergence, ActionRegistry expansion, new Work-specific shared primitives, or any backend/database/RPC/query/permission/RBAC/RLS/service/workflow change.

If preserving any of those truths requires functional modification, WORK001 becomes `BLOCKED`; the implementation must not absorb the functional issue.

## Product-quality acceptance

### System coherence / hierarchy

- The task-entry narrative remains exactly: what is required -> responsibility/current ball holder -> next action/timing -> priority/privacy/completion behavior.
- Shared patterns own spacing, section hierarchy, field anatomy and action composition; Work owns task meaning and business state.
- No page-local replacement is introduced for a V2 primitive already capable of the presentation requirement.
- No attempt is made to flatten Work's useful operational terminology into generic component vocabulary.

### Device contract

- **Mobile (`<=768px`)**: migrated grids collapse to one column; controls/actions remain touch-safe; actions stay non-sticky and do not compete with BottomNav/FAB space.
- **Tablet (`769–1024px`)**: safe paired fields may use two columns; long Arabic labels/hints and validation remain readable without compressed control geometry.
- **Desktop (`>=1025px`)**: preserve the current efficient two-column task-entry density; do not invent denser three/four-column business grouping.

### RTL / Arabic / accessibility / states

- Every migrated labeled native control remains programmatically associated with its Arabic label.
- Shared `Field` should own hint/error relationships through ids/`aria-describedby`; error meaning must not be color-only.
- Existing `required`, `disabled`, loading and validation truth remains unchanged.
- Focus/keyboard behavior remains native/shared, and no nested interactive pattern is introduced.
- Dark-mode/RTL styling comes from shared tokens/patterns; no new hard-coded colors or LTR assumptions.

### Evidence

Focused authored tests should protect shared-pattern adoption, section ordering, responsive grid/action intent, label/hint/error association and explicit preservation of the functional boundaries above. Evidence remains subject to `33_TEST_AND_VALIDATION_POLICY.md`; no hosted CI, Vercel preview or deployment action is permitted.

## Current Work-island observations for later slices

These are roadmap observations, not WORK001 scope:

- `WorkHubPage` still carries a local hero, clickable KPI summary cards, local segmented mode control, local search surface, local section headers/action cards/empty state and a mobile create treatment.
- `work.css` contains a mature 1024/768 responsive system; this should be mined selectively rather than deleted wholesale.
- `WorkItemCard` already composes the shared `DataCard` and feature-level Work badges, so future collection migration must preserve that good ownership boundary instead of replacing domain presentation indiscriminately.
- Existing V2 `SegmentedControl`, `MetricGrid/StatCard`, `SectionHeader`, `StatePanel`, `ResponsiveCollection` and action patterns are candidates for later Work slices only after exact interaction parity is proven.

## Peer-state comparison / contradiction synthesis

I formed the Product Design judgment above from current source before comparing the peer role files.

- **Development Integrator:** fresh direction is aligned: FIELD002 is integrated and WORK001 is the next single READY roadmap concern.
- **UI Production Engineer:** Development-side state is lifecycle-stale from the completed FIELD002 implementation; it does not conflict with the new WORK001 boundary.
- **Design QA:** Development-side state is lifecycle-stale from FIELD002 exact-head review; no current QA conclusion conflicts with WORK001 because no implementation PR exists yet.
- **Team Memory:** aligned on Work Management as the next module and on preserving Work business/query/permission/workflow truth.
- **Decision Log:** no durable rule needs change; this is adoption of already-established V2 form ownership.

There is **no BLOCKING cross-role contradiction**. Team Memory does not need an update because the overall roadmap/direction is unchanged; only the already-queued WORK001 concern is now concretely bounded.

## What changed since previous state

FIELD002 is no longer an active PR: it is integrated, Development has no open implementation PR, and the previously generic WORK001 placeholder now has one concrete dependency-safe implementation target. Product Design selected and documented the `/work/new` Create Task form composition as the only READY implementation concern and explicitly deferred Work Hub/detail/management convergence.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA and Development Integrator after an exact implementation PR HEAD exists.
- **What changed:** `DS2-WORK-001` is now concretely bounded to the `/work/new` Create Task presentation/form-composition migration using shared `FormSection + FormGrid + Field + FormActions + Button`; Workstream updated in commit `2b3326a5f445a3461893d1fd3397cf5619c4616b`.
- **Preserve:** exact section order/content; title/description/outcome/next-action values and callbacks; owner vs assignee meaning; candidate loading/defaulting; acknowledgement eligibility/reset; dates and `nextActionAt > dueAt` validation; priority/visibility/completion-mode semantics; `useCreateTask` payload/`activate: true`; toast/navigation outcomes; existing PageHeader; non-sticky actions; all backend/query/permission/state-machine truth.
- **Need from you:** UI Production Engineer should open exactly one WORK001 PR from current `design-system-v2-development` and implement only this bounded presentation migration with focused tests. Do not begin Work Hub/detail cleanup in the same PR. QA/Integrator should wait for one stable exact PR HEAD before reviewing.
- **Blocker level:** `NONE`.
- **Baseline:** product source inspected at Development `22962d71674be08d7f04805b213d8c423a211b2a`; workstream boundary commit `2b3326a5f445a3461893d1fd3397cf5619c4616b`.
