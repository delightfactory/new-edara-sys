# Design Director State

## Reviewed baseline

- Review date: `2026-09-17`.
- Development branch: `design-system-v2-development`.
- Exact Development HEAD independently inspected before this state write: `a83ea41718f23001851003a56bc5abcdfe4b7ed2`.
- Latest integrated product slice: `DS2-FIELD-002`, squash `2492fa475e7bc5beb9148124f31a4b4837057c19`.
- Active implementation PR: `#44 — DS2-WORK-001: Create Task form V2 composition foundation`.
- PR base: `design-system-v2-development` at `d748637fe5fd2a5fd50eced16b15645c9f75185d`.
- Exact PR HEAD independently reviewed: `09f30f89511ebde932695883109b3dd4dc161456`.
- PR state at review: `OPEN / DRAFT / mergeable=true`; review threads: `NONE`.
- Product Design disposition: `P2 / BLOCKING — shared Field control touch geometry is not guaranteed through Tablet/Mobile`.
- QA disposition on the same exact HEAD: `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- Blocker: `BLOCKING` until the touch-control contract is corrected on the same PR and the new exact HEAD is re-reviewed.

## Independent professional judgment

**WORK001 is architecturally correct in its form decomposition, but the exact implementation HEAD cannot be accepted yet because it does not satisfy the declared Mobile/Tablet touch-control contract.**

I formed this judgment from the exact PR source and shared V2 CSS/contracts before comparing peer conclusions. The migration correctly replaces the page-local Create Task form shell with shared `FormSection + FormGrid + Field + FormActions + Button`, preserves Work business/state-machine truth, and keeps the action area non-sticky. However, the migrated native `input` and `select` controls now consume `.form-input` / `.form-select` inside `Field`, and the shared V2 Field/control CSS does not set a minimum control height. The previous Work-local `.work-field input/select` contract explicitly guaranteed `min-height: 42px`; the new shared path removes even that explicit floor.

This matters because the North Star/device contract makes touch ergonomics first-class, the V2 foundations already define `--ds-control-height-standard: 42px` and `--ds-control-height-touch: 44px`, and the WORK001 acceptance explicitly requires touch-safe Mobile controls and 44px-capable Tablet controls. `Button touchTarget` correctly enforces the action hit area, but there is no equivalent source-level guarantee for the migrated text/date/select controls. A browser-dependent computed height is not an acceptable Design System contract.

This is a shared-system gap exposed by a real migrated screen, so the correction belongs in the shared V2 Field/control layer rather than in a new `work-*` local patch.

## Exact-head review findings

### Scope / functional isolation — PASS

The five-file PR remains inside the bounded `/work/new` presentation concern. Source review confirms preservation of:

- `toIso` behavior;
- `useAssignmentCandidates('')`, self/first-candidate defaulting, owner/accountability meaning and assignee/current-ball meaning;
- acknowledgement reset/disabled rule and payload suppression for self assignment;
- `validate()` wording and `nextActionAt > dueAt` comparison;
- priority, visibility and completion-mode values/options/callbacks;
- `useCreateTask`, payload keys, `activate: true`, success/error toasts and post-create navigation;
- existing `PageHeader`, responsibility summary cells and acknowledgement checkbox;
- all backend/query/service/permission/RBAC/RLS/workflow truth.

No backend/business change is requested to resolve the blocker.

### Shared-system fit / hierarchy — PASS apart from touch geometry

- Four task-entry sections use shared `FormSection` in the same Arabic narrative order.
- Safe owner/assignee, timing and priority/visibility pairs use `FormGrid columns={2}`; narrative/completion content remains full-width.
- Standard field anatomy uses shared `Field` rather than introducing a Work-local replacement.
- Actions use shared non-sticky `FormActions + Button`; cancel remains secondary and create remains primary.
- Shared `Field` correctly owns label/hint/error relationships and invalid state without moving validation semantics into the component.

### Device / RTL / accessibility — BLOCKING on one bounded point

- **Mobile (`<=768px`)**: grid collapse and non-sticky action placement are correct; action buttons are touch-safe through `touchTarget`. Native text/date/select controls, however, have no shared 44px minimum-height guarantee after leaving `.work-field`.
- **Tablet (`769–1024px`)**: deliberate two-column grouping is correct, but the same native control geometry gap violates the declared touch-first Tablet contract.
- **Desktop (`>=1025px`)**: two-column density and hierarchy are appropriate. Desktop may remain on the standard 42px control-density role.
- Arabic labels, `htmlFor`/ids, `aria-describedby`, `aria-invalid`, manual `noValidate` semantics and error text are otherwise coherent.

## Required bounded correction on PR #44

Do not redesign Create Task and do not reopen Work Hub/detail scope. Fix the same PR by strengthening the **shared V2 Field/control sizing contract** so migrated standard controls have deterministic geometry:

- shared `Field`-scoped text/date inputs and native selects must have at least the V2 standard control height on Desktop;
- through Tablet and Mobile they must have at least `--ds-control-height-touch` (`44px`);
- textarea behavior may retain its existing larger minimum height;
- implement this in the shared V2 component/style layer, not with a CreateTask-specific `work-*` rule;
- add focused source/style test evidence protecting the shared control-height contract and keep all existing WORK001 functional-isolation tests intact.

This is presentation-only hardening. If the Implementer finds that satisfying it would require changing Work semantics, validation, native control values/callbacks or backend behavior, stop and mark the slice blocked instead.

## Non-blocking WATCH after that correction

- `work.css` remains a broader legacy island. In particular, Mobile `.work-page` retains its pre-existing bottom-spacing contract and the responsibility/acknowledgement sub-surfaces remain Work-local. These are later convergence debt, not a reason to expand WORK001.
- Shared `FormSection` density should be runtime-validated at the next owner-requested visual milestone; no runtime visual PASS is claimed in this source-only run.

## Peer-state comparison / contradiction synthesis

I formed the Product Design judgment above before comparing peer states.

- **Design QA:** current and fresh on the same exact PR HEAD, but its `GREEN-DEV` conclusion missed the lack of a deterministic touch-height contract for the newly migrated native controls. This is now a **material BLOCKING design-system contradiction** until a new exact HEAD is reviewed.
- **Development Integrator:** correctly held `NO_MERGE_WAITING_FRESH_PRODUCT_DESIGN_CLOSEOUT`; that gate now resolves to `NO_MERGE` because Product Design found a concrete P2 blocker rather than granting acceptance.
- **UI Production Engineer:** the Development-side state is lifecycle-stale from FIELD002, while the PR-owned WORK001 state is current and otherwise aligned. Its claim that actions are touch-safe is correct; the unresolved issue is the shared field-control geometry.
- **Team Memory / Workstream:** system direction remains aligned. No Team Memory or Decision Log update is required because the durable strategy has not changed.
- **Development drift since PR base:** only QA/Integration governance commits advanced Development; no relevant shared component/product implementation drift invalidates the source comparison.

## What changed since previous state

The pre-implementation WORK001 boundary has now been tested against PR #44 exact HEAD `09f30f89511ebde932695883109b3dd4dc161456`. The composition and functional-isolation direction pass, but the Director found one source-proven touch-ergonomics gap in the shared Field/control contract. WORK001 therefore remains the single active slice and must not integrate or advance the queue until that bounded correction is made and the new exact HEAD receives fresh QA + Product Design review.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA and Development Integrator after the corrected exact PR HEAD exists.
- **What changed:** Product Design independently reviewed PR #44 exact HEAD `09f30f89511ebde932695883109b3dd4dc161456`; form architecture/function isolation pass, but a P2 BLOCKING gap was found because migrated `Field` inputs/selects no longer have a deterministic standard/touch minimum-height contract.
- **Preserve:** exact section order/content; owner vs assignee and acknowledgement semantics; candidate loading/defaulting; validation wording/date rule; priority/visibility/completion mode; `toIso`; create payload/`activate: true`; toasts/navigation; PageHeader; responsibility summary/checkbox; non-sticky actions; all backend/query/permission/state-machine truth; full Reports/Admin/Global roadmap.
- **Need from you:** UI Production Engineer should repair the same PR by hardening shared `Field`-scoped standard input/select sizing to standard Desktop height and at least `--ds-control-height-touch` through Tablet/Mobile, with focused test/source evidence and no Work-local sizing patch. QA then reviews the new exact HEAD; Product Design must also re-close the new HEAD before Integration. Integrator remains `NO_MERGE` meanwhile.
- **Blocker level:** `BLOCKING`.
- **Baseline:** Development reviewed at `a83ea41718f23001851003a56bc5abcdfe4b7ed2`; blocked PR #44 exact HEAD `09f30f89511ebde932695883109b3dd4dc161456`.
