# UI Implementation State

## Reviewed baseline

- Run date: `2026-09-16`
- Development branch: `design-system-v2-development`
- Exact development baseline used for this slice: `a6c9705ab56442c7c1d1722b442aa374a7556e81`
- Exact development HEAD observed this run: `a8e4533073f5ed5e217f76189109240b58c7b1a2`
- Feature branch: `ds2/sales-order-form-v2`
- Draft PR: `#31 — DS2-UI-004: establish Sales Order form V2 presentation foundation`
- Exact source HEAD before this state write: `02ae4b656ae95c8f14d2cbd5b0c0e88186d4c39e`
- Active slice: `DS2-UI-004 — Sales Order form V2 foundation`
- Implementation disposition: `REVIEW`
- Evidence: `TESTS_AUTHORED_NOT_EXECUTED`

## Independent implementation judgment

**THE BOUNDED OUTER-FORM COMPOSITION SLICE IS IMPLEMENTED AND READY FOR DESIGN DIRECTOR / DESIGN QA REVIEW.**

This PR now proves the shared V2 wizard/form/action grammar on the live Sales Order create/edit surface without migrating Sales business truth into presentation components. The earlier duplicate-Stepper blocker is resolved through a backward-compatible shared `Stepper` evolution, and the live page now delegates step presentation, the first form section, and bottom actions to shared V2 composition while retaining all existing customer/product/pricing/discount/tax/validation/save behavior in `SalesOrderForm.tsx`.

The deferred customer/product lookup and line-item redesign remains intentionally outside this first sub-slice.

## Material progress this run

1. Re-ran the mandatory shared-memory bootstrap, inspected issue #27, current development HEAD, PR #31, and peer role states before modification.
2. Wired `SalesOrderStepNavigator` into the live page; it remains only a thin projection over shared `Stepper`.
3. Preserved exact direct-step reachability in page code:
   - current/earlier steps remain reachable;
   - step 0 remains directly reachable;
   - step 1 requires customer validity;
   - step 2 requires customer validity + at least one valid line;
   - review step 3 remains unavailable by direct future-step click and is reached through existing `goNext` progression.
4. Preserved existing `goNext` validation/toasts and page-owned submit validation.
5. Migrated the step-0 outer grouping to `SalesOrderFormSection` (`FormSection` + responsive `FormGrid`) without moving any field state, customer behavior or permission truth.
6. Replaced the legacy page-local bottom navigation with `SalesOrderFormActions`, preserving cancel/back/next/save callbacks and the existing submit-disabled condition.
7. Removed the legacy squeezed page stepper markup, legacy `.stepper-label` mobile hiding, hard-coded rotated directional cue and obsolete local `grid2` layout constant.
8. Added focused page source-contract coverage in `SalesOrderForm.v2.test.ts` for shared wiring, exact reachability, forward validation, submit sequence, pricing/permission truth, copy/edit behavior and the existing Mobile add-product modal boundary.
9. Independently inspected the resulting commit diff: the live-page commit changes presentation wiring only (`+41/-68`) and does not alter service/query/cache/RBAC/RLS/validation/business calculations/workflow state.
10. No GitHub Actions, hosted CI, Vercel or `main` activity occurred.

## Changed-file scope

Current PR #31 contains eight files:

- `src/components/ui/Stepper.tsx`
- `src/components/ui/Stepper.test.tsx`
- `src/components/sales/SalesOrderFormPresentation.tsx`
- `src/components/sales/SalesOrderFormPresentation.test.tsx`
- `src/components/sales/sales-order-form-v2.css`
- `src/pages/sales/SalesOrderForm.tsx`
- `src/pages/sales/SalesOrderForm.v2.test.ts`
- this role-state file

No Sales service, query/cache implementation, database/migration/RPC, RBAC/RLS, permission definition, route guard, validation meaning, workflow transition, pricing/discount/tax/total calculation or deployment configuration is changed.

## Preserved functional contracts

Source review confirms the page still owns and preserves:

- create vs edit mode and `copyFrom` behavior;
- customer selection/clear, branch loading, credit presentation and rep read-only/assignment behavior;
- product search, unit selection, quantity, stock warning and line add/remove behavior;
- customer-aware price resolution and manual-price override guards;
- `sales.orders.edit_price` and `sales.discounts.override` permission checks;
- discount limits, taxes, shipping and total calculations;
- minimum-order blocking;
- `goNext` validation/toasts and exact step progression truth;
- `createSalesOrder` / `updateSalesOrder` / `saveSalesOrderItems` / `recalcOrderTotals` submit sequence;
- route navigation after save and cancel/back behavior;
- existing ResponsiveModal Mobile add-product flow.

## Device / state coverage

- **Mobile:** shared Stepper uses its opt-in two-column wrapped composition with full Arabic labels and no ordinary horizontal stepper overflow; form step 0 is one-column through shared FormGrid; shared actions are touch-targeted and sticky-mobile capable; existing add-product bottom-sheet/modal flow is preserved.
- **Tablet:** shared Stepper remains linear; FormGrid caps the migrated section at two columns; actions remain touch-safe without inheriting Mobile-only item-entry behavior.
- **Desktop:** linear compact stepper and two-column step-0 form grouping preserve efficient data-entry density; existing Desktop product table remains unchanged in this bounded sub-slice.
- **Loading:** existing page loading surface is unchanged; save loading delegates to shared Button semantics through `SalesOrderFormActions`.
- **Disabled / permission:** unreachable steps are native disabled buttons; save disabled truth remains page-owned; price/discount permissions are unchanged.
- **RTL / accessibility:** current step uses `aria-current="step"`; the workflow nav has an Arabic accessible label; forward `التالي` uses the RTL-forward leftward cue and backward `السابق` uses the rightward cue; no hard-coded rotation remains.

## Test / execution evidence

Current evidence: **`TESTS_AUTHORED_NOT_EXECUTED`**.

Focused authored tests cover:
- legacy/default shared Stepper read-only behavior;
- guarded Stepper interaction and disabled-step semantics;
- shared wrapped Mobile Stepper mode;
- Sales adapter delegation to shared Stepper;
- shared FormSection/FormGrid composition;
- RTL-native action cues and shared Button loading semantics;
- live-page shared V2 wiring;
- exact direct-step reachability including no direct review-step access;
- existing forward validation/toasts;
- page-owned submit sequence and disabled truth;
- pricing/discount permission ownership;
- copy/edit and Mobile add-product boundaries.

No approved local checkout/runtime was available: direct sandbox access to GitHub remains unavailable, so `npm test`, `npm run build` and `npm run lint` were not executed. No hosted CI was used. No PASS is claimed. Source inspection found no known TypeScript/build blocker.

## Peer-state comparison / freshness

- **Product Design Director:** development-side state reviewed old PR head `da8af948...` and required shared Stepper reuse, exact reachability, RTL-native arrows and understandable Mobile labels. Those four requirements are now represented in source and live-page wiring on this review candidate; Director exact-head revalidation is requested.
- **Design QA:** prior state belongs to the completed PR #30; no exact-head approval exists for PR #31 yet. QA should review only the new exact review head after this state write.
- **Development Integrator:** must remain `NO_MERGE` until exact-head `GREEN-DEV` and source review are recorded.
- **Development drift:** current development HEAD `a8e4533...` differs from the slice baseline only through coordination/state work observed during this run; no product/shared-component merge-sync was required before this handoff.

## Risks / deferred work

- Runtime visual/build/test evidence is unavailable in this environment; evidence is intentionally limited to authored tests + source/diff inspection.
- The customer combobox, product lookup/line-item interaction and remaining local Sales form surfaces still contain legacy presentation debt. They are deliberately deferred to later dependency-safe sub-slices and must not be pulled into this PR without a concrete reviewer blocker.
- Sticky Mobile actions should be visually revalidated when a real local/browser runtime becomes available; no functional callback or safe-area contract was changed here.

## Cross-role handoff

- **To:** Product Design Director, Design QA, Development Integrator
- **What changed:** PR #31 now wires the shared Stepper/form-section/action contracts into live `SalesOrderForm.tsx` while retaining page-owned Sales truth. Exact source HEAD before this state write: `02ae4b656ae95c8f14d2cbd5b0c0e88186d4c39e`.
- **Preserve:** all customer/product/pricing/discount/tax/validation/permission/query/service/save/route/workflow semantics; exact reachability; existing Mobile add-product flow; deferred lookup/product-line scope; no hosted CI/Vercel/`main` activity.
- **Need from you:** Product Design Director should revalidate architecture/RTL/Mobile intent on the exact review candidate; Design QA should perform source/contract review and issue `GREEN-DEV` only for the exact reviewed HEAD if acceptable. Integrator must no-op until those gates are satisfied.
- **Blocker level:** `NONE` from implementation; `AWAITING_REVIEW`.
- **Evidence:** `TESTS_AUTHORED_NOT_EXECUTED`.
- **Baseline:** development baseline `a6c9705ab56442c7c1d1722b442aa374a7556e81`; development observed `a8e4533073f5ed5e217f76189109240b58c7b1a2`; source HEAD before state write `02ae4b656ae95c8f14d2cbd5b0c0e88186d4c39e`.
