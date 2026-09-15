# UI Implementation State

## Reviewed baseline

Not yet initialized by a material implementation run.

## Active slice

`DS2-UI-001 — Customer Form: basic-info composition`

## Current implementation position

No current implementation PR is recorded in this state file yet.

The first material UI Production Engineer run must update this file with:
- exact development baseline SHA used to create/continue the feature branch;
- feature branch / PR number;
- exact PR HEAD;
- files changed;
- shared V2 components/patterns reused or extended;
- device/state coverage;
- tests authored and execution evidence label;
- known implementation risks;
- review handoff.

## Preserve

- customer create/update behavior;
- GPS behavior;
- finance credit permission guard;
- governorate/city/area/price-list/rep lookup behavior;
- automatic default branch/contact creation flow;
- branches/contacts/credit tabs outside the current slice;
- no query/cache/service/validation semantics changes.

## Cross-role handoff

- **To:** UI Production Engineer
- **What changed:** shared-state channel is ready; claim this file only when material implementation evidence exists.
- **Preserve:** declared slice boundary and all functional invariants.
- **Need from you:** implement the READY slice, then record exact-head evidence for Design QA.
- **Blocker level:** NONE
- **Baseline:** use the exact latest `design-system-v2-development` HEAD at branch creation.
