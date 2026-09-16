# Design Director State

## Reviewed baseline

- Review date: `2026-09-17`
- Development branch: `design-system-v2-development`
- Exact Development HEAD independently inspected before this state write: `18f76d616be87e29d321822b601b1ec2f2687825`
- Active slice: `DS2-PROC-002 — Purchase Invoice form decomposition`
- Active implementation PR: `#37 — DS2-PROC-002: establish purchase invoice form V2 shell`
- PR base: `design-system-v2-development`
- Slice baseline: `e4866c9350c507bce260beb07d880fbce55718f3`
- Exact PR HEAD independently inspected: `751d54278b120ad560981b9f019ec0a0135b3061`
- Current Product Design disposition: `BLOCKED — P2 INTER-SECTION SPACING / HIERARCHY REGRESSION`
- Evidence level: source inspection only; `TESTS_AUTHORED_NOT_EXECUTED`; no runtime/build/lint/preview PASS claimed.

## Independent professional judgment

**PR #37 is architecturally aligned with the PROC002 shell boundary, but it is not yet acceptable for integration because the migrated basic-information `FormSection` loses required sibling separation.**

I independently inspected the exact PR HEAD before comparing peer conclusions. The shell direction itself is correct:

- `PurchaseInvoiceDraftStepper` is a thin adapter over shared `Stepper` and preserves page-owned reachability, including no newly invented direct-forward access to review.
- **بيانات الفاتورة** uses shared `FormSection + FormGrid columns={3}`, yielding the intended `3 Desktop / 2 Tablet / 1 Mobile` composition.
- editable wizard navigation uses shared `FormActions + Button` with unchanged cancel/back/next/save callbacks and RTL-native previous/next cues.
- workflow status now uses shared semantic `StatusBadge` with the already-integrated Purchase vocabulary.
- supplier/product/warehouse identity, calculations, tax/discount/landed-cost/WAC, receive/bill/cancel workflow, permissions, services/query/cache, routes, `DocumentActions` and mobile item-entry truth remain outside presentation ownership.

The remaining defect is real and PR-introduced:

1. The legacy basic-information wrapper used `sCard`, whose contract includes `marginBottom: 16`.
2. Shared `FormSection` composes shared `Card` and intentionally owns **internal** section spacing only; it has no external sibling margin.
3. `.page-container` owns padding but no vertical stack/gap contract.
4. On exact PR HEAD, the migrated `FormSection` therefore sits immediately before:
   - `FormActions` on editable step 0; and
   - the following items card in `showReceivePanel`, `bill` and `readonly` modes.

That removes a deliberate visual boundary between major transactional groups. It conflicts with the North Star requirement for strong hierarchy, controlled spacing and deliberate device/state composition. This is not a reason to change shared `FormSection` globally; external flow spacing belongs to the Purchase Invoice composition boundary in this slice.

## Director synthesis of peer-state disagreement

After forming the judgment above, I compared peer states and PR review evidence:

- **Design QA:** current exact-head P2 blocker is valid. QA correctly distinguishes internal `FormSection` spacing from external sibling rhythm and identifies the regression across editable and simultaneous multi-section modes.
- **UI Production Engineer:** the statement that the bounded shell is otherwise complete is correct, but its `NONE` blocker disposition is stale/incomplete with respect to the exact-head spacing regression exposed by QA.
- **Development Integrator:** its state is stale on an earlier PR HEAD and should remain `NO_MERGE`; the fresh QA blocker supersedes that older completeness-only view.
- **Material contradiction:** resolved by this Director synthesis in favor of **BLOCKING until the local spacing regression is corrected**. No business/backend ambiguity exists.

## Required minimum correction

Keep the same PR and the same shell scope. Restore one token-based logical block separation at the Purchase Invoice composition boundary so **بيانات الفاتورة** is separated from whichever sibling follows it.

Acceptable implementation intent:

- a narrow Purchase Invoice/Procurement shell wrapper or class around the migrated basic-information section;
- use shared spacing tokens, preferably `var(--space-4)`, via logical block spacing / local composition ownership;
- protect that local ownership in the focused source contract.

Do **not**:

- add global external margin to shared `FormSection` or `Card`;
- create a Procurement-specific primitive;
- change shared density rules;
- alter Purchase Invoice mode/workflow/business behavior;
- widen into Combobox, items table/cards, receive panel, mobile add-item sheet, accounting, calculations, validation semantics or broader Procurement cleanup.

## Device / state / accessibility acceptance after the correction

- **Desktop:** retain 3-column basic-info density and dense downstream transaction review; major sections/actions must keep clear vertical separation.
- **Tablet:** retain the shared 2-column cap and touch-safe controls; section rhythm must remain deliberate, not compressed Desktop.
- **Mobile:** retain one-column basic-info, wrapped Arabic Stepper labels and touch-target actions; the basic-info card must not visually merge into the action bar.
- **Receive / bill / readonly:** where multiple sections are visible together, the basic-info card must remain visually distinct from the items surface.
- **Accessibility/RTL/status:** current shared Stepper/Button/StatusBadge direction and semantics are otherwise acceptable and should not be reopened by this fix.

## Preserve

- exactly one implementation PR/slice at a time;
- exact current Purchase Invoice step reachability, `goNext`, cancel/back/save and disabled truth;
- all supplier/warehouse/product selection behavior;
- all quantities, pricing, discounts, taxes, totals, landed-cost/WAC/accounting/payment logic;
- receive/bill/cancel transitions, permissions, services/query/cache and routes;
- current mobile item-add flow, `ResponsiveModal` and `DocumentActions`;
- semantic Purchase status vocabulary already integrated in the list;
- no GitHub Actions/hosted CI, Vercel preview, backend/business, `main` or deployment activity.

## Remaining non-blocking WATCH

- `InlineCombobox` / product chooser keyboard-accessibility debt remains separately bounded future work.
- products table/cards, receive panel and wider transaction-form composition remain later slices.
- runtime visual/build/lint/test evidence remains unclaimed by policy and current execution availability.
- full form-field convergence should not be pulled into this spacing repair.

## What changed since previous state

The bounded PROC002 implementation is now live on PR #37, closing the prior completeness concern. Exact-head review exposed one new, narrow presentation regression: migration from legacy `sCard` to shared `FormSection` dropped the external section separation previously supplied by `marginBottom: 16`. I independently verified the source geometry and accept Design QA's P2 blocker. Overall system direction, Team Memory and durable decisions do not change.

### Cross-role handoff
- **To:** UI Production Engineer, Design QA, Development Integrator
- **What changed:** Product Design Director independently confirms PR #37 exact HEAD `751d54278b120ad560981b9f019ec0a0135b3061` is architecturally sound except for one BLOCKING P2 inter-section spacing regression at the migrated **بيانات الفاتورة** boundary.
- **Preserve:** the entire already-approved shell architecture and all Purchase/accounting/workflow/permission/service truth; fix only local external spacing ownership and focused protection.
- **Need from you:** UI Production Engineer should correct the spacing on the same PR with a token-based local composition boundary and focused assertion; Design QA must review the moved exact HEAD; Integrator remains `NO_MERGE` until fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` exists.
- **Blocker level:** `BLOCKING`.
- **Baseline:** Development `18f76d616be87e29d321822b601b1ec2f2687825`; PR #37 exact reviewed HEAD `751d54278b120ad560981b9f019ec0a0135b3061`.
