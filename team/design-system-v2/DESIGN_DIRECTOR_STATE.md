# Design Director State

## Reviewed baseline

- Review date: `2026-09-18`.
- Development branch: `design-system-v2-development`.
- Exact Development HEAD independently inspected before this state write: `eaf3cb34c2d405afe96a4d13c9335f1ea8892270`.
- Latest integrated product slice: `DS2-FIELD-002`, squash `2492fa475e7bc5beb9148124f31a4b4837057c19`.
- Active implementation PR: `#44 — DS2-WORK-001: Create Task form V2 composition foundation`.
- PR base: `design-system-v2-development` at feature-branch creation SHA `d748637fe5fd2a5fd50eced16b15645c9f75185d`.
- Exact current PR HEAD independently reviewed: `fb83ac8eba9087fdfe579669b171d88f5aaa3e8d`.
- Corrected product/test commit inside that HEAD: `a5abec4fd903f1cc84492e64eb4d50b6bfbdfb71`.
- PR state at review: `OPEN / DRAFT`; the HEAD remained unchanged across the final recheck.
- Design QA disposition on this exact HEAD: `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- Product Design disposition: `P2 / BLOCKING — semantic control-height tokens are now correct, but the new sizing contract is applied through unscoped global .form-* selectors rather than the shared Field boundary requested for WORK001`.
- Blocker: `BLOCKING` until the same PR narrows the shared sizing rule to the V2 `Field` contract and the new exact HEAD is re-reviewed.

## Independent professional judgment

**The previous touch-height defect is technically fixed, but WORK001 still cannot be accepted because the fix currently changes the geometry contract for every consumer of the generic `.form-input`, `.form-select` and `.form-textarea` classes, not only controls that have migrated to V2 `Field`.**

I formed this judgment from the exact PR source, loaded stylesheet cascade and shared component contracts before comparing peer conclusions.

The positive part is clear: `--control-height-md` is gone; the corrected CSS now uses the declared V2 semantic roles, with `--ds-control-height-standard` on Desktop/default and `--ds-control-height-touch` through `<=1024px`, while textarea keeps the larger 80px floor. That closes the original token-resolution/touch-geometry defect for the Create Task controls.

The remaining problem is **ownership and blast radius**. `design-system-v2-forms.css` is imported globally after `components.css`, and the new selectors are plain `.form-input`, `.form-select` and `.form-textarea`. Those are generic legacy/application classes defined globally in `components.css`; they are not proof that a consumer has adopted V2 `Field`. Therefore this WORK001 correction can alter control height on unrelated legacy surfaces outside the bounded Work slice without those surfaces being reviewed. That is broader than the assigned proof and weakens the migration discipline of `shared contract -> explicit consumer adoption`.

The V2 `Field` component already exposes a stable `.ds-field` wrapper and the prior Director requirement explicitly called for a **shared Field-scoped control sizing contract**. The safe architecture is therefore to keep the semantic sizing rules in the shared V2 form layer, but scope them through the V2 Field boundary. A future deliberate primitive/global-control convergence slice may choose a broader contract after representative validation; WORK001 should not make that product-wide decision incidentally.

## Exact-head review findings

### Scope / functional isolation — PASS

The six-file PR remains UI/Test/Governance-only. Source review confirms preservation of:

- `toIso` behavior;
- `useAssignmentCandidates('')`, self/first-candidate defaulting, owner/accountability meaning and assignee/current-ball meaning;
- acknowledgement reset/disabled rule and payload suppression for self assignment;
- exact `validate()` messages and `nextActionAt > dueAt` comparison;
- priority, visibility and completion-mode values/options/callbacks;
- `useCreateTask`, payload keys, `activate: true`, success/error toasts and post-create navigation;
- existing `PageHeader`, responsibility summary cells and acknowledgement checkbox;
- all backend/query/service/permission/RBAC/RLS/workflow truth.

No backend/business change is needed to resolve the current blocker.

### Shared-system fit / hierarchy — PASS apart from selector ownership

- Four task-entry sections use shared `FormSection` in the same Arabic narrative order.
- Safe owner/assignee, timing and priority/visibility pairs use `FormGrid columns={2}`; narrative/completion content remains full-width.
- Standard field anatomy uses shared `Field` rather than a new Work-local primitive.
- Actions use shared non-sticky `FormActions + Button`; cancel remains secondary and create remains primary.
- Shared `Field` correctly owns label/hint/error relationships and invalid state without absorbing validation semantics.
- The semantic standard/touch control-height roles themselves are correct.

### Device / RTL / accessibility — PASS for the intended Field consumer

- **Mobile (`<=768px`)**: grid collapse and non-sticky actions are correct; the corrected token contract provides the required 44px control floor.
- **Tablet (`769–1024px`)**: deliberate two-column grouping is correct; the same 44px touch role is applied.
- **Desktop (`>=1025px`)**: two-column density remains appropriate; the 42px standard role is suitable.
- Arabic labels, `htmlFor`/ids, `aria-describedby`, `aria-invalid`, manual `noValidate` semantics and error text are coherent.

The blocker is not the resulting geometry on `/work/new`; it is that the implementation currently grants that geometry to unreviewed generic-class consumers outside the V2 Field boundary.

## Required bounded correction on PR #44

Do not redesign Create Task, do not reopen Work Hub/detail, and do not revert the semantic token fix. Correct only the selector ownership on the same PR:

- keep `--ds-control-height-standard` for Desktop/default and `--ds-control-height-touch` through Tablet/Mobile;
- keep textarea's existing larger minimum floor;
- scope the shared rules through the V2 `Field` wrapper, e.g. `.ds-field .form-input`, `.ds-field .form-select`, `.ds-field .form-textarea` (or an equivalently precise Field-owned selector);
- apply the same Field scoping inside the `<=1024px` touch override;
- update the focused source/style contract to protect the **Field-scoped** standard/touch sizing contract and continue rejecting `--control-height-md`;
- do not add a `work-*` sizing exception and do not change any Work validation, values, callbacks, payloads, queries, services, permissions or workflow semantics.

If a product-wide canonical `.form-*` sizing change is desired later, it should be opened as a separately bounded shared/global component-depth slice with representative consumer validation, not smuggled into WORK001.

## Non-blocking WATCH after that correction

- `work.css` remains a broader legacy island. Mobile `.work-page` bottom spacing and the responsibility/acknowledgement sub-surfaces remain later convergence debt.
- Shared `FormSection` density and the wider control-height system should receive runtime visual validation at the next owner-requested milestone; no runtime visual PASS is claimed here.

## Peer-state comparison / contradiction synthesis

I formed the Product Design judgment above before comparing peer states.

- **Design QA:** fresh on the same exact PR HEAD and correctly confirms the invalid token is gone and touch geometry is deterministic. However, QA treats the global `.form-*` blast radius as a non-blocking WATCH. Product Design considers that broader selector ownership a **material BLOCKING scope/system contradiction** because the active slice proved V2 `Field`, not every legacy generic class consumer.
- **UI Production Engineer:** PR-owned state is current and correct about the semantic token repair, but it likewise assumes global `.form-*` ownership. The requested follow-up is only selector scoping plus focused contract adjustment.
- **Development Integrator:** Development-side state is stale to the prior blocked HEAD, but its `NO_MERGE` posture remains procedurally correct while this fresh Product Design contradiction is BLOCKING.
- **Team Memory / Workstream / Decision Log:** durable direction is unchanged. No Team Memory or Decision Log mutation is warranted; WORK001 remains the only active slice.
- **Development drift:** current Development HEAD movement since the feature baseline is governance-only for this concern; no product/shared implementation overlap invalidates the exact-head source review.

## What changed since previous state

The original P2 on missing deterministic control height is source-fixed on PR #44 exact HEAD `fb83ac8eba9087fdfe579669b171d88f5aaa3e8d`. Fresh review found a narrower second-order issue: the fix is technically correct but globally unscoped, so it exceeds the V2 Field ownership boundary and can change unrelated generic `.form-*` consumers. WORK001 remains the single active slice and must not integrate until this selector scope is narrowed and the new exact HEAD receives fresh QA + Product Design review.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA and Development Integrator after the corrected exact PR HEAD exists.
- **What changed:** Product Design independently reviewed PR #44 exact HEAD `fb83ac8eba9087fdfe579669b171d88f5aaa3e8d`; the semantic standard/touch token fix works, but its global `.form-*` selectors create an unreviewed product-wide blast radius, so WORK001 remains `P2 / BLOCKING` until the shared sizing contract is scoped to V2 `Field`.
- **Preserve:** `--ds-control-height-standard` on Desktop/default; `--ds-control-height-touch` through Tablet/Mobile; textarea larger floor; exact four-section Create Task hierarchy; responsive FormGrid; non-sticky actions; labels/hints/errors; assignment/defaulting; owner/assignee/acknowledgement; exact validation/date rule; `toIso`; priority/visibility/completion mode; payload/`activate: true`; toasts/navigation; all backend/query/permission/state-machine truth; full Reports/Admin/Global roadmap.
- **Need from you:** UI Production Engineer should narrow the existing shared V2 form sizing selectors to `.ds-field`-owned controls and update the focused source/style contract on the same PR, without a Work-local patch or functional change. Design QA must review the new exact HEAD, and Product Design must re-close that same HEAD. Integrator remains `NO_MERGE` meanwhile.
- **Blocker level:** `BLOCKING`.
- **Baseline:** Development reviewed at `eaf3cb34c2d405afe96a4d13c9335f1ea8892270`; blocked PR #44 exact HEAD `fb83ac8eba9087fdfe579669b171d88f5aaa3e8d`.
