# Design QA State

## Reviewed baseline

- Review date: `2026-09-16`
- Development branch: `design-system-v2-development`
- Exact development HEAD observed before this QA write: `a8e4533073f5ed5e217f76189109240b58c7b1a2`
- Active slice: `DS2-UI-004 — Sales Order form V2 foundation`
- Active implementation PR: `#31 — DS2-UI-004: establish Sales Order form V2 presentation foundation`
- PR base: `design-system-v2-development`
- Slice starting baseline: `a6c9705ab56442c7c1d1722b442aa374a7556e81`
- Exact PR HEAD reviewed: `6841ceb3094ec6f85a14d4e9bdfb77869fc4444c`
- Live PR state: `OPEN / DRAFT / mergeable`
- Changed-file scope: 8 files (shared Stepper, Sales presentation/page wiring, focused tests, implementation state)
- Current disposition: `AGENT-REVIEW: BLOCKED`
- Evidence: `TESTS_AUTHORED_NOT_EXECUTED`

## Independent QA disposition

**BLOCKED** on exact HEAD `6841ceb3094ec6f85a14d4e9bdfb77869fc4444c` by one bounded P2 Design System regression.

The overall direction is strong and the previous duplicate-Stepper architecture blocker is visibly resolved. Functional isolation passes; shared Stepper/FormSection/FormActions ownership is correct; exact legacy step reachability remains page-owned; RTL directional cues are corrected; Mobile step labels are no longer hidden; tests exist for the material contracts.

However, the migrated Step 0 form grouping introduces a Desktop information-density regression that conflicts with the North Star and this slice's own acceptance direction.

## Blocking finding

### P2 — Desktop form density regression

Location: `src/pages/sales/SalesOrderForm.tsx` — `<SalesOrderFormSection title="بيانات الطلب" ... columns={2}>`.

Source comparison against the slice baseline shows the prior Step 0 grid used:

`repeat(auto-fill, minmax(220px, 1fr))`

After the two intentionally full-width customer/credit rows, the three related controls — representative, order date, and delivery branch — could occupy one Desktop row when width allowed. The new V2 composition hard-caps the section to two columns, forcing an extra row and reducing management/data-entry density.

This is not a request for redesign. The shared `FormGrid` already has the needed responsive contract:
- 3 columns on Desktop;
- 2 columns on Tablet for `cols-3`;
- 1 column on Mobile.

Minimum correction:
1. change this migrated section to `columns={3}`;
2. add/update focused composition/source-contract coverage so the Desktop/Tablet/Mobile density intent is protected;
3. keep all field/business semantics unchanged.

No other scope expansion is justified.

## Scope / functional isolation

**PASS.**

No DB/migration/RPC/service/query-cache/RBAC/RLS/permission-definition/route-guard/business-calculation/workflow-state/validation-semantic/deployment change is present.

Preserved source contracts include:
- create/edit and `copyFrom` behavior;
- customer/branch/rep and credit presentation;
- product/unit/quantity/stock/add-remove flow;
- customer-aware pricing and manual price override behavior;
- `sales.orders.edit_price` and `sales.discounts.override` permission checks;
- discount/tax/shipping/total/minimum-order rules;
- existing `goNext` validation/toasts;
- create/update/items/recalculate save sequence;
- save/cancel navigation;
- existing Mobile add-product `ResponsiveModal` flow.

## Shared-system / Stepper review

**PASS at source level.**

The Product Design Director's previous shared-Stepper blocker on older head `da8af948...` is resolved on this reviewed head:
- shared `src/components/ui/Stepper.tsx` is evolved backward-compatibly;
- read-only behavior remains the default;
- page/domain code projects reachability through `disabled`;
- Sales uses a thin `SalesOrderStepNavigator` adapter rather than a parallel primitive;
- current/completed/upcoming semantics remain system-owned;
- review step 3 is not freely future-clickable;
- current/earlier-step behavior matches the legacy source contract;
- Mobile can opt into wrapped labels without hiding Arabic meaning;
- RTL forward/back cues use native left/right chevrons rather than transforms.

No current Stepper source blocker was identified.

## Device / interaction judgment

### Mobile
**PASS at source level for the bounded migrated contracts.**
- Stepper has opt-in wrapped compact-phone composition with full Arabic labels.
- Step 0 collapses through shared FormGrid.
- action buttons use shared touch-target semantics.
- sticky actions are offset by the shared Mobile bottom-nav/safe-area contract.
- existing Mobile product-entry modal remains unchanged.

Runtime visual validation of sticky-action coverage remains a milestone gate, not claimed here.

### Tablet
**PASS conditional on the density fix.**
- shared FormGrid already converts `cols-3` to two columns at Tablet width, which is the desired deliberate hybrid composition.
- touch-first step/action behavior is retained.

### Desktop
**BLOCKED only by the current two-column Step 0 cap.**
- shared form composition is correct, but the chosen column count unnecessarily loses the density that the baseline already supported.

## Accessibility / RTL

**PASS for the reviewed source contracts.**
- interactive Stepper buttons expose `aria-current="step"`, native disabled state, and workflow-specific labels;
- read-only Stepper behavior remains backward-compatible;
- status is not color-only;
- focus-visible treatment is present;
- forward/backward Arabic directional cues are corrected;
- no partial page-local ARIA workflow contract was introduced.

## Test / execution evidence

Focused tests are authored for:
- legacy/default shared Stepper behavior;
- guarded Stepper reachability and disabled state;
- wrapped Mobile Stepper mode;
- Sales adapter projection;
- FormSection/FormGrid composition;
- RTL action cues and shared Button loading state;
- live-page V2 wiring;
- direct-step reachability / review-step protection;
- forward validation/toasts;
- submit sequence and disabled truth;
- pricing/discount permission ownership;
- copy/edit and Mobile add-product boundaries.

Evidence remains **`TESTS_AUTHORED_NOT_EXECUTED`**. No approved local checkout executed `npm test`, `npm run build`, or `npm run lint`. No GitHub Actions/hosted CI or Vercel was triggered or relied upon. No known TypeScript/build failure was identified by source review.

## Cross-role comparison

- **UI Production Engineer:** feature-branch state is fresh and hands this exact review candidate; its implementation claim is aligned except for the Desktop density judgment above.
- **Product Design Director:** development-side state is stale by feature HEAD and its prior BLOCKING Stepper contradiction is resolved in current source. Its explicit invariant that Desktop preserve efficient data-entry density supports this QA blocker rather than conflicts with it.
- **Development Integrator:** current `NO_MERGE_IN_PROGRESS` remains correct until a new exact head is reviewed.
- **Team Memory / Workstream:** still label DS2-UI-004 as READY while the active PR is in REVIEW. This is stale lifecycle metadata, but there is no competing slice and no ambiguity about the single active implementation. Treat as `WATCH`; Integrator/Director should reconcile during the normal state transition, not by opening new work.

No unresolved functional/product-truth contradiction exists. The only current integration blocker is the bounded Desktop density regression above.

## Runtime / release boundary

Not claimed:
- `LOCAL_EXECUTION_PASS`
- `MANUAL_PREVIEW_BUILD_PASS`
- `RUNTIME_VISUAL_PASS`
- `main` / release readiness

## Cross-role handoff

- **To:** UI Production Engineer, Product Design Director, Development Integrator
- **What changed:** Design QA independently reviewed PR #31 exact HEAD `6841ceb3094ec6f85a14d4e9bdfb77869fc4444c` and blocked it on one P2 presentation regression: Step 0 is hard-capped to two Desktop columns, reducing baseline data-entry density. All prior shared-Stepper/RTL/reachability concerns pass on this head.
- **Preserve:** all Sales customer/product/pricing/discount/tax/validation/permission/query/service/save/route/workflow truth; shared Stepper/FormSection/FormActions ownership; Mobile add-product flow; no lookup/product-line scope expansion; no hosted CI/Vercel/`main` activity.
- **Need from you:** UI Production Engineer should make the minimum correction `columns={3}` for the migrated Step 0 section and protect that responsive density contract in focused test/source coverage, then hand off a new exact HEAD. Design QA must re-review that exact HEAD. Integrator remains NO_MERGE until GREEN-DEV.
- **Blocker level:** `BLOCKING`.
- **Baseline:** development `a8e4533073f5ed5e217f76189109240b58c7b1a2`; reviewed PR #31 HEAD `6841ceb3094ec6f85a14d4e9bdfb77869fc4444c`
