# UI Implementation State

## Reviewed baseline

- Run date: `2026-09-15`
- Development branch: `design-system-v2-development`
- Exact development HEAD observed before this state write: `4c4c23a97e0de06a6789e78fd6c7bd27af973dcb`
- Feature branch: `ds2/customer-form-basic-info-v2`
- Draft PR: #28 — `DS2-UI-001: migrate customer basic-info form to V2 composition`
- Previously QA-blocked PR HEAD: `ccbf9decab1257634874fc348525d6a50f588857`
- Exact current PR HEAD handed back to Design QA: `b6bfceeb8327437e274222c7e2f75e83c4a65061`
- Active slice: `DS2-UI-001 — Customer Form: basic-info composition`
- Implementation disposition: `REVIEW_READY_AFTER_QA_FIX`

## What changed this run

Design QA identified one bounded P2 accessibility/system-contract blocker on the retained legacy Customer tabs. The fix was intentionally limited to that finding and did not broaden the slice into a Tabs redesign.

Applied on the existing feature branch:

1. `9b332b0cb61f92777801582b9551a47cc75ee18f` — `fix(ds2): remove incomplete legacy tab ARIA roles`
   - retained every legacy tab control as `type="button"`;
   - removed the newly introduced `role="tablist"`, `role="tab"`, and `aria-selected` contract;
   - preserved tab classes, click handlers, active visual state, counts, and credit-tab permission visibility;
   - no Customer business/action wiring changed.

2. `b6bfceeb8327437e274222c7e2f75e83c4a65061` — `test(ds2): protect bounded legacy tab semantics`
   - updated the focused source-contract test to assert non-submitting tab buttons;
   - added negative assertions so this slice cannot reintroduce the incomplete ARIA widget contract;
   - preserved all existing tests for V2 form composition, submit wiring, credit permission boundaries, creation side effects, and GPS wiring.

Compare from blocked HEAD `ccbf9dec...` to current HEAD `b6bfceeb...` is exactly two commits and exactly the same two product/test files already in PR #28. No unrelated file entered the diff.

## Files changed in the active PR

- `src/pages/customers/CustomerFormPage.tsx`
- `src/pages/customers/CustomerFormPage.v2.test.ts`

No service, query, database, permission definition, RBAC/RLS, route guard, validation rule, workflow-state, cache semantic, business calculation, workflow file, Vercel configuration, or GitHub Actions workflow was changed.

## Shared patterns preserved

- `PageHeader`
- `FormSection`
- `FormGrid`
- `FormActions`
- existing `PermissionGuard`
- existing `ResponsiveModal` for out-of-scope secondary surfaces

No new page-local primitive was introduced. Full Tabs/SubNav semantics remain correctly deferred to the shared component-depth program.

## Functional invariants preserved in source

- edit continues through `updateCustomer(id!, form)`;
- create continues through `createCustomer(form)`;
- default branch creation remains `saveCustomerBranch(created.id, ...)`;
- optional default contact creation remains `saveCustomerContact(created.id, ...)`;
- customer GPS wiring remains unchanged;
- `finance.credit.manage` continues to disable the credit-limit control through `PermissionGuard`;
- credit-history visibility remains guarded by `can('customers.credit.update')`;
- geography, price-list, and representative lookup behavior is unchanged;
- branches, contacts, credit-history content and responsive modals remain outside this slice.

## Device / state coverage

Unchanged from the accepted composition direction:
- Mobile: shared grids collapse to one column; long-form actions use the shared mobile-sticky contract; retained legacy section-switch buttons are explicitly non-submitting.
- Tablet: shared FormGrid caps requested 3-column layouts at two columns.
- Desktop: two/three-column density remains preserved where intended.
- RTL/Arabic: existing Arabic content and LTR handling for phone/email/GPS/numeric values remain unchanged.
- Saving/GPS disabled/loading states and credit permission-disabled state remain delegated to their existing controls/contracts.

## Test / execution evidence

Focused contract test:
`src/pages/customers/CustomerFormPage.v2.test.ts`

Current evidence label: `TESTS_AUTHORED_NOT_EXECUTED`.

No GitHub Actions/hosted CI was triggered. No approved local repository runtime executed the suite in this run, so no test/build PASS is claimed. No known TypeScript/build failure has been introduced or recorded by this bounded correction.

## Current judgment

The exact QA blocker has been implemented at the minimum safe boundary. From the UI Production Engineer perspective there is no remaining implementation blocker on DS2-UI-001, but the slice is **not approved** until Design QA independently re-reviews exact HEAD `b6bfceeb8327437e274222c7e2f75e83c4a65061`.

Do not merge-sync the feature branch merely for governance/state-file drift; only relevant product/shared-component drift should move the review HEAD.

## Cross-role handoff

- **To:** Design QA, Product Design Director, Development Integrator
- **What changed:** the single QA P2 blocker was fixed narrowly: legacy Customer section-switch buttons remain `type="button"`, the incomplete ARIA tab widget roles were removed, and the focused test now prevents their partial reintroduction. Exact new PR HEAD is `b6bfceeb8327437e274222c7e2f75e83c4a65061`.
- **Preserve:** all Customer create/update/GPS/lookup/credit/default branch/contact behavior; shared PageHeader/FormSection/FormGrid/FormActions composition; no broad Tabs redesign; no hosted CI/Vercel; no governance-only review-head churn.
- **Need from you:** Design QA should independently re-review exact HEAD `b6bfceeb8327437e274222c7e2f75e83c4a65061`. If GREEN-DEV, Integrator may proceed under the normal exact-head gates. Design Director should keep complete Tabs/SubNav keyboard/tabpanel semantics in the future shared component-depth slice.
- **Blocker level:** `NONE` from implementation; QA approval still required.
- **Baseline:** development observed `4c4c23a97e0de06a6789e78fd6c7bd27af973dcb`; PR #28 HEAD `b6bfceeb8327437e274222c7e2f75e83c4a65061`
