# Design QA State

## Reviewed baseline

- Review date: `2026-09-17`
- Development branch: `design-system-v2-development`
- Exact Development HEAD inspected before this review/state write: `1f6ee3226c1364b72ea2a2defc7879a3325fa505`
- Active slice: `DS2-HR-001 — Attendance Check-in operational task controls`
- Active implementation PR: `#40 — DS2-HR-001: Attendance operational task controls`
- PR base: `design-system-v2-development`
- PR base SHA: `1f6ee3226c1364b72ea2a2defc7879a3325fa505`
- Exact PR HEAD reviewed: `37197361cb351a53b461f8d8ebaf62b1aff7a6d2`
- Live PR state at disposition: `OPEN / DRAFT / mergeable=true`
- Changed-file scope at reviewed HEAD: 5 files — shared `ProcessProgress`, shared `PrimaryTaskAction`, shared operational-task CSS, focused shared-pattern tests, and UI Implementation owned state.
- Current disposition: `AGENT-REVIEW: BLOCKED`
- Severity: `P2 — implementation completeness / live-slice proof missing`
- Source evidence: `SOURCE_REVIEW_PASS` **not granted**.
- Test evidence: `TESTS_AUTHORED_NOT_EXECUTED`.
- Exact-head build/test/lint/runtime/preview evidence: not claimed.

## Independent QA disposition

**BLOCKED on exact HEAD `37197361cb351a53b461f8d8ebaf62b1aff7a6d2`.**

I formed this judgment from the exact PR diff, the unchanged live `AttendanceCheckin` contract, shared `Button` / `AlertPanel` behavior and the HR001 Workstream boundary before comparing peer states.

The new shared presentation direction is sound: `ProcessProgress` is caller-driven and domain-agnostic, exposes readable completed/current/pending text plus `aria-current="step"`, and `PrimaryTaskAction` is a thin composition over the existing shared `Button` rather than a parallel action registry or workflow engine. The current diff is presentation/test/owned-state only and introduces no visible DB/RPC/service/query/cache/RBAC/RLS/route/business/workflow change.

However, the actual live slice is still incomplete. `src/pages/hr/attendance/AttendanceCheckin.tsx` is absent from the changed-file set. The live screen therefore still renders its page-local `SmartActionButton`, local `ProgressSteps`, and local success/error feedback cards. The PR body explicitly records live wiring as the next concern.

Because the migrated surface itself is not yet wired, Design QA cannot verify the required end-to-end presentation parity for the HR001 slice and cannot grant `SOURCE_REVIEW_PASS`.

## Exact-head findings

### Scope / functional isolation — PASS for the current partial diff

The changed files are confined to shared presentation, focused tests and the Implementer-owned state file. No backend/business contract file is changed.

The new shared components do not import or infer Attendance `FlowState`, GPS permissions, RPC result codes, services, query/cache, tracking, timing or eligibility rules. This is aligned with the hard functional-isolation boundary.

### Shared-system fit — PASS provisionally

- `PrimaryTaskAction` composes shared `Button` with `variant="primary"`, large/touch-safe sizing, loading/disabled handling and caller-owned callback/label.
- It does not route the single operational task through `AppAction/resolveActionSet`, matching the Director's action-hierarchy decision.
- It does not treat `إنهاء الدوام` as destructive.
- `ProcessProgress` accepts explicit caller-owned step state and exposes non-color textual state plus current-step semantics.
- CSS uses logical sizing/spacing and avoids HR/Attendance-specific selectors or domain rules.

These shared artifacts can support the intended North-Star operational-task grammar, but system fit is not complete until the real Attendance surface consumes them without behavior drift.

### Live implementation completeness — BLOCKING P2

Specific location: `src/pages/hr/attendance/AttendanceCheckin.tsx` is not changed on this HEAD.

The live page still owns:
- custom `SmartActionButton` / `ci-action-*` ring/pulse presentation;
- local `ProgressSteps` / `ci-progress` / `ci-step*` presentation;
- local success/error feedback-card presentation.

Required HR001 migration work therefore remains unapplied to the production screen.

This blocks the HR001 Review Gate and North-Star page-migration requirement that a real migrated surface replace page-local mini-system behavior with shared V2 grammar while preserving business truth.

### Device / state / accessibility evidence — INCOMPLETE for the live slice

The shared components are source-reasonable for RTL, long Arabic labels, touch sizing and current-step accessibility. But without live wiring this HEAD does not yet prove:

- Mobile one obvious eligible task action in the current Attendance composition;
- Tablet constrained touch-first placement;
- Desktop capability equivalence;
- exact `idle -> locating -> submitting -> success/error` visual parity;
- no ordinary overflow in the real Attendance column;
- preservation of the terminal day-done no-action state;
- dynamic success/error announcement through `AlertPanel`;
- safe retention of current GPS/offline suppression and callbacks.

No runtime visual evidence is claimed.

## Test / execution evidence

Evidence is **`TESTS_AUTHORED_NOT_EXECUTED`**.

Current focused tests protect the shared primitives only:
- `ProcessProgress` caller-owned states, Arabic labels, non-color state text, accuracy metadata and `aria-current="step"`;
- `PrimaryTaskAction` shared Button classes, callback, loading/busy and disabled behavior.

The Test Artifact Gate remains incomplete for the material live-slice risks. The next exact HEAD must add focused live-page/source-contract protection for at least:
- existing check-in/check-out eligibility and no-action completed-day truth;
- current IDs/labels/disabled/loading parity where relied upon;
- existing `handleAction` callback path and offline/GPS suppression;
- `AlertPanel` success/error copy, optional location and polite/assertive announcement;
- preservation of `SUCCESS_RESET_MS = 2500` lifecycle;
- preservation of attendance/GPS service/query/tracking/RPC boundaries.

No approved environment executed `npm test`, `npm run build` or `npm run lint`; no executed PASS is claimed. No GitHub Actions or Vercel preview/deploy was used. No known real build/type failure was found by source inspection, which is not a build PASS claim.

## Minimum required fix

Without broadening the slice:

1. Wire the existing two Attendance steps into `ProcessProgress` with page-owned explicit state mapping only.
2. Replace only the eligible in-flow local ring action with `PrimaryTaskAction`, preserving exactly `بدء الدوام` / `إنهاء الدوام`, existing disabled/loading truth, current IDs where relied upon and the existing `handleAction` path.
3. Reuse existing `AlertPanel` for the same transient success/error content and the same 2500ms reset lifecycle; success polite, error assertive.
4. Remove only local visual CSS/classes proven dead after wiring.
5. Add focused live-page/source-contract protection for the material behavior/state boundaries above.

Do not add confirmation, sticky/fixed behavior, destructive semantics, `AppAction`, new eligibility, or any GPS/RPC/query/cache/tracking/device/business logic to shared presentation.

## Peer-state comparison / contradiction handling

The independent disposition above was formed first, then compared with current repository states.

- **Product Design Director:** current HR001 boundary is fresh and aligned; it explicitly requires the live Attendance action/progress/feedback migration and records blocker `NONE` at the start boundary. No design contradiction.
- **UI Production Engineer:** the PR-owned state/body explicitly marks this HEAD `IN_PROGRESS`, shared-pattern-first, with live Attendance integration still next. This aligns with QA's completeness blocker rather than contradicting it.
- **Development Integrator / Team Memory:** both still reflect the pre-implementation HR001 handoff and are lifecycle-stale now that PR #40 exists, but neither grants merge approval or contradicts the HR001 boundary. Freshness: `WATCH`, not a blocking disagreement.
- **Review threads/comments:** no prior inline review thread existed on PR #40 before this QA review.

No separate current cross-role `BLOCKING` contradiction exists. The blocker is the candidate's incomplete implementation itself.

## System-fit judgment

The shared operational-task primitives are a good direction and do not fragment the Design System. Design QA is blocking only because the representative live proof and its focused protection are not present yet. The fix should remain exactly within the already-approved HR001 boundary.

### Cross-role handoff
- **To:** UI Production Engineer, Product Design Director, Development Integrator
- **What changed:** Design QA reviewed PR #40 exact HEAD `37197361cb351a53b461f8d8ebaf62b1aff7a6d2`; shared patterns are directionally sound, but HR001 is `AGENT-REVIEW: BLOCKED` P2 because live `AttendanceCheckin` wiring and live-slice test protection are not yet present.
- **Preserve:** every attendance/time/GPS permission/RPC/query/cache/tracking/timing/error-code/service/device-capability/workflow rule; keep the action in-flow, primary/non-destructive, no confirmation, no `AppAction`, no sticky behavior.
- **Need from you:** UI Production Engineer should finish only the bounded live action/progress/AlertPanel wiring + dead-visual cleanup + focused live contract tests on the same PR. Any new HEAD requires fresh QA. Integrator remains `NO_MERGE` until exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` exists.
- **Blocker level:** `BLOCKING` for integration until the incomplete live slice is finished and re-reviewed.
- **Baseline:** Development / PR base `1f6ee3226c1364b72ea2a2defc7879a3325fa505`; exact reviewed PR HEAD `37197361cb351a53b461f8d8ebaf62b1aff7a6d2`.
- **Evidence:** `TESTS_AUTHORED_NOT_EXECUTED`; no source/build/test/lint/runtime/preview PASS beyond the partial source findings above.
