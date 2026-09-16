# Design Director State

## Reviewed baseline

- Review date: `2026-09-16`
- Development branch: `design-system-v2-development`
- Exact development HEAD reviewed before this state write: `a6c9705ab56442c7c1d1722b442aa374a7556e81`
- Active slice: `DS2-UI-004 — Sales Order form V2 foundation`
- Active Draft PR: `#31 — DS2-UI-004: establish Sales Order form V2 presentation foundation`
- Feature branch: `ds2/sales-order-form-v2`
- Starting baseline: `a6c9705ab56442c7c1d1722b442aa374a7556e81`
- Exact current PR HEAD independently reviewed: `da8af948764bbf2c1902a9abb9da36b8762d5345`
- Live PR state: `OPEN / DRAFT / mergeable`
- Current implementation disposition: `IN_PROGRESS`
- Current evidence: `TESTS_AUTHORED_NOT_EXECUTED`
- Exact-head QA approval for PR #31: not expected / not present while WIP remains incomplete

## Independent professional judgment

**WIP ARCHITECTURE NEEDS ONE BOUNDED CORRECTION BEFORE PAGE WIRING. CONTINUE THE SAME PR; DO NOT EXPAND SCOPE.**

The selected slice is correct: the Sales Order form is a high-value golden-flow surface and the safe first boundary is presentation composition, not customer/product/pricing/discount/tax/validation/save logic. The new `SalesOrderFormSection` and `SalesOrderFormActions` are directionally sound thin compositions over the existing shared `FormSection` / `FormGrid` / `FormActions` / `Button` contracts.

However, the current WIP introduces a Sales-local `SalesOrderStepNavigator` even though the repository already contains the approved shared `src/components/ui/Stepper.tsx`, and the control contract explicitly says the current shared Stepper is retained/evolved. Wiring the local navigator into the page would create a second stepper language and violate the shared-system-before-page-local rule.

This is a **bounded Design System architecture blocker**, not a reason to stop DS2-UI-004 or redesign the whole form.

## Required correction before continuing page wiring

### 1. Evolve/reuse the existing shared Stepper; do not create a Sales-local replacement

**BLOCKING at the current presentation boundary.**

Use the existing shared `Stepper` as the system-owned visual/semantic component. If the live Sales form proves that guarded clickable step navigation is missing from its API, extend the shared Stepper by the smallest backward-compatible interaction contract needed by this real form.

Guardrails:
- preserve the existing visual-only/default Stepper API for current consumers;
- optional interaction may accept page-owned reachability/activation callbacks, but must not contain Sales validation/business rules;
- current/completed/upcoming semantics remain system-owned;
- page code remains authoritative for whether a step is reachable;
- do not create a generic workflow engine or broad wizard abstraction;
- focused tests must protect both legacy/default Stepper behavior and the new optional guarded-navigation contract if the shared component changes.

The current Sales-local `SalesOrderStepNavigator` should not survive as a parallel primitive once the shared contract can express the live need.

### 2. Preserve the exact current Sales step-reachability semantics

**Required before REVIEW.**

The existing page does not treat all future steps as directly clickable. Its current stepper allows:
- step 0 directly;
- step 1 only once customer validity allows it;
- step 2 only once customer + valid-line conditions allow it;
- earlier steps when moving backward;
- review step 3 is reached through the page's existing forward progression, not made freely direct-clickable by the stepper.

The V2 wiring must preserve this behavior exactly unless a separate functional decision changes it. A generic `index <= activeIndex` or `all completed/future valid steps are clickable` rule would silently change workflow interaction semantics.

Add focused page-wiring coverage for the exact reachability mapping and keep `goNext` validation/toast behavior page-owned.

### 3. Make directional actions RTL-native, not inherited LTR arrows

**Required before REVIEW; presentation-only.**

The current WIP renders `السابق` with a left-pointing chevron and `التالي` with that icon rotated to point right. In an Arabic RTL progression this communicates the opposite logical direction.

Use logical/RTL-aware directional treatment so:
- forward/`التالي` communicates movement in the RTL-forward direction;
- backward/`السابق` communicates the reverse;
- the implementation does not rely on a hard-coded transform that becomes wrong if direction changes.

This corrects visual interaction semantics only; it must not alter callbacks or workflow progression.

### 4. Four-step Mobile progress must stay understandable with real Arabic labels

**Required acceptance condition; do not over-design.**

The current WIP avoids horizontal overflow with a 2-column Mobile grid, which is directionally better than the legacy squeezed row. But its labels are forced to a single line with ellipsis. The shared Stepper contract says 4+ steps should prioritize current-step/progress clarity over squeezing labels.

For the final bounded solution:
- no ordinary horizontal stepper scrolling on the Sales form;
- current step label must remain fully understandable on phone width;
- long Arabic labels must not silently reduce critical meaning through aggressive ellipsis;
- status must remain more than color alone;
- do not add a broad new wizard layout system beyond what this four-step form proves.

## Approved parts of the current WIP

### Form section composition

**PASS.** `SalesOrderFormSection` is a thin domain composition over shared `FormSection` + `FormGrid`, with no domain state or validation inside it.

### Action hierarchy

**PASS direction, subject to RTL icon correction.** `SalesOrderFormActions` correctly delegates cancel/previous/next/submit/loading/disabled truth to the page and uses shared `FormActions` + `Button`. Sticky Mobile actions remain appropriate only if page wiring proves they do not cover active fields/validation or conflict with BottomNav safe areas.

### Functional isolation

**PASS for current WIP.** The current PR changes presentation/test/state files only. No service, query/cache, DB/RPC, permission/RBAC/RLS, validation meaning, pricing/discount/tax/total calculation, workflow state, route or deployment contract changed.

### Combobox / product-line scope

**DEFER in this sub-slice.** The live form still contains page-local customer/product combobox and line-item interaction debt, and a shared `AsyncCombobox` exists. That is real future Design System work, but it should not be pulled into this first outer-form composition PR unless page wiring exposes a concrete blocker. Prove the outer form/step/action composition first, then open the smallest dedicated shared lookup/product-line slice if needed.

## North Star fit

### Mobile

The intended touch-safe shared actions and removal of ordinary stepper overflow fit the Mobile-primary North Star. Final wiring must preserve single-column task clarity, long Arabic labels, validation visibility, sticky-action safe-area behavior, and existing Mobile add-item sheet behavior.

### Tablet

The form may use the shared two-column cap where grouping remains clear. Tablet must remain touch-first and must not simply inherit a compressed Desktop density.

### Desktop

Preserve efficient data-entry density. Moving outer grouping/actions to V2 patterns must not turn the order form into a low-density card wall.

### Accessibility / RTL

Use the shared Stepper as the reusable accessibility boundary. Page-owned reachability must map to real disabled/interactive semantics. Directional action icons must be RTL-logical. Do not introduce partial ARIA semantics detached from actual interaction behavior.

## Freshness / coordination

- Current development HEAD `a6c9705...` is the exact baseline from which PR #31 started.
- Current PR HEAD is `da8af948764bbf2c1902a9abb9da36b8762d5345`; its latest commit updates implementation-state documentation after the initial presentation code.
- Only PR #31 currently targets `design-system-v2-development`.
- Development-side Design QA and Integration states correctly describe the completed PR #30 and are stale/consumed for this new slice; they contain no current blocker for DS2-UI-004.
- The feature-branch UI Implementation State is fresh in intent and correctly keeps all Sales truth page-owned, but its WIP architecture must adopt the existing shared Stepper before page wiring.
- Workstream/Team Memory still describe DS2-UI-004 as READY even though PR #31 has now started. Treat that lifecycle wording as stale coordination metadata, not permission to open a second slice. PR #31 is the single active implementation slice.

Do not merge-sync the feature branch merely to absorb this Design Director state commit; state-only development drift must not create unnecessary PR-head churn.

## Preserve

- create vs edit mode and `copyFrom` behavior;
- customer selection/clear, branch loading, credit presentation and rep assignment/read-only behavior;
- product search/unit/quantity/stock warning/add-remove behavior;
- price-edit permission and discount-override limits;
- tax, discount, shipping and total calculations;
- current step validation and progression semantics;
- minimum-order blocking;
- `createSalesOrder` / `updateSalesOrder` / `saveSalesOrderItems` / `recalcOrderTotals` submit sequence;
- route navigation after save and cancel/back behavior;
- existing ResponsiveModal/mobile add-product flow;
- shared V2 ownership of Stepper/form/action grammar;
- exact evidence honesty; no hosted CI, Vercel preview or `main` activity;
- one active implementation slice only.

## Cross-role handoff

- **To:** UI Production Engineer, Design QA, Development Integrator
- **What changed:** Product Design Director independently reviewed Draft PR #31 HEAD `da8af948764bbf2c1902a9abb9da36b8762d5345`. The bounded Sales Order form slice is correct, but the WIP currently duplicates the approved shared `Stepper` with a Sales-local navigator. Before wiring the live page, reuse/evolve the shared Stepper with the smallest optional page-owned guarded-navigation contract. Preserve exact Sales step reachability, correct RTL forward/back directional cues, and keep four-step Mobile progress understandable without ordinary overflow/aggressive meaning loss.
- **Preserve:** all Sales Order customer/product/pricing/discount/tax/validation/permission/service/query/save/route/workflow semantics; shared FormSection/FormGrid/FormActions/Button contracts; existing Mobile add-item/modal behavior; no broad Combobox/ProductLine rewrite in this first sub-slice; no hosted CI/Vercel/`main` activity.
- **Need from you:** UI Production Engineer should continue only PR #31, replace the parallel Sales-local stepper primitive with the smallest backward-compatible shared Stepper evolution, then wire the page while preserving exact reachability and add focused page-wiring/RTL/mobile-label tests. Design QA and Integrator should no-op until a stable review-ready exact HEAD is handed off.
- **Blocker level:** `BLOCKING` for page wiring/review while the duplicate Stepper boundary remains; no functional/business blocker exists.
- **Baseline:** development `a6c9705ab56442c7c1d1722b442aa374a7556e81`; PR #31 HEAD `da8af948764bbf2c1902a9abb9da36b8762d5345`
