# UI Implementation State

## Reviewed baseline

- Run date: `2026-09-16`
- Development branch: `design-system-v2-development`
- Exact development baseline used for this slice: `a6c9705ab56442c7c1d1722b442aa374a7556e81`
- Feature branch: `ds2/sales-order-form-v2`
- Draft PR: `#31 — DS2-UI-004: establish Sales Order form V2 presentation foundation`
- Exact current feature HEAD before this state write: `fbe21e32713c3702eb89a08ad666d67f37ac66ce`
- Active slice: `DS2-UI-004 — Sales Order form V2 foundation`
- Implementation disposition: `IN_PROGRESS`
- Evidence: `TESTS_AUTHORED_NOT_EXECUTED`

## Independent implementation judgment

**CONTINUE THE SAME BOUNDED SLICE.**

The live `SalesOrderForm.tsx` confirms the correct first migration boundary is presentation composition, not Sales business logic. The page currently owns customer selection, product lookup, price resolution, permissions, discounts, tax/totals, step reachability, save/update behavior and routing. Those contracts must remain page-owned.

The first WIP commit therefore introduces only a domain-local presentation layer over already-proven V2 primitives. It does not yet replace the live page render tree.

## Material progress this run

1. Revalidated the mandatory shared memory, issue #27, open PR state and current development HEAD after DS2-UI-003 integration.
2. Inspected the live `SalesOrderForm.tsx` create/edit flow and identified the smallest safe foundation: step navigation, shared form-section/grid composition and action hierarchy.
3. Created branch `ds2/sales-order-form-v2` from exact development HEAD `a6c9705...` and opened Draft PR #31.
4. Added `SalesOrderStepNavigator`:
   - controlled by page-owned `canActivate` / `onChange` callbacks;
   - current step uses `aria-current="step"`;
   - shared `Button` owns interaction/touch semantics;
   - Mobile uses a two-column wrapped layout rather than ordinary horizontal overflow;
   - Tablet/Desktop retain linear progression.
5. Added `SalesOrderFormSection` over shared `FormSection` + `FormGrid`; it owns no validation or domain state.
6. Added `SalesOrderFormActions` over shared `FormActions` + `Button`; the page remains authoritative for cancel/previous/next/submit decisions, loading and disabled state.
7. Added focused Testing Library/Vitest artifacts for reachability, section/grid reuse, action callbacks and loading semantics.
8. No hosted CI, GitHub Actions, Vercel or `main` activity occurred.

## Changed-file scope

Current PR #31 changes only:

- `src/components/sales/SalesOrderFormPresentation.tsx`
- `src/components/sales/SalesOrderFormPresentation.test.tsx`
- `src/components/sales/sales-order-form-v2.css`
- this role-state file after the present write

No Sales service, query/cache implementation, database/migration/RPC, RBAC/RLS, permission definition, route guard, validation meaning, workflow transition, pricing/discount/tax/total calculation or deployment configuration is changed.

## Functional truth to preserve during wiring

The next implementation pass must preserve exactly:

- create vs edit mode and `copyFrom` behavior;
- customer selection/clear, branch loading and credit presentation;
- sales-rep assignment/read-only behavior;
- product search, unit selection, quantity, stock warning and add/remove behavior;
- price-edit permission and discount-override limits;
- tax, discount, shipping and total calculations;
- step validation (`customer` before items; at least one valid line before delivery/review);
- minimum-order blocking;
- `createSalesOrder` / `updateSalesOrder` / `saveSalesOrderItems` / `recalcOrderTotals` submit sequence;
- route navigation after save and cancel/back behavior;
- ResponsiveModal add-product flow.

The product-line editor and async lookup behavior are not authorized for broad redesign in this sub-slice.

## Device / system direction

- **Mobile:** no ordinary horizontal stepper overflow; touch-safe shared buttons; sticky shared form actions are available for the eventual page wiring.
- **Tablet:** deliberate linear step navigation with shared form grids capped by the existing V2 Tablet contract.
- **Desktop:** preserve efficient form density while moving outer grouping/actions to shared V2 patterns.
- **RTL / accessibility:** semantic `nav` + `aria-current`, native disabled state, shared Button focus/touch contract; no partial custom ARIA widget is introduced.

## Test / execution evidence

Current evidence: **`TESTS_AUTHORED_NOT_EXECUTED`**.

The sandbox still has no repository checkout and direct terminal GitHub access fails DNS (`Could not resolve host: github.com`). No `npm test`, `npm run build` or `npm run lint` result is claimed. No known source-level TypeScript/build failure is recorded from the inspected files, but execution evidence is intentionally not implied.

## Peer-state comparison

- Workstream/Team Memory place `DS2-UI-004` as the next single READY slice; this run has now begun that slice on Draft PR #31.
- Stored Product Design Director state still targets completed DS2-UI-003 and is stale for this new form slice; no conflicting fresh design direction exists.
- Stored Design QA/Integrator state contains no blocker for starting DS2-UI-004.
- No peer-state `BLOCKING` contradiction applies.

## Next action

Continue only PR #31. Wire the new presentation contracts into `SalesOrderForm.tsx` in the smallest safe render-only diff, then add page-wiring regression tests. Do not move customer/product/price/discount/tax/validation/save truth into the presentation component and do not open a separate line-item/combobox redesign unless a concrete blocker proves it necessary.

## Cross-role handoff

- **To:** Product Design Director, Design QA, Development Integrator
- **What changed:** DS2-UI-004 has started on Draft PR #31. The first bounded WIP establishes Sales Order step/section/action presentation over existing shared V2 patterns without touching the live business contract yet.
- **Preserve:** all current Sales Order customer/product/pricing/discount/tax/validation/permission/service/query/save/route semantics; one active slice; no hosted CI/Vercel/`main` activity.
- **Need from you:** no QA/integration action yet. Product Design Director may inspect the WIP system boundary; UI Production Engineer will continue the same PR to page wiring before REVIEW.
- **Blocker level:** `NONE`; evidence remains `TESTS_AUTHORED_NOT_EXECUTED`.
- **Baseline:** development `a6c9705ab56442c7c1d1722b442aa374a7556e81`; PR #31 WIP HEAD before this state write `fbe21e32713c3702eb89a08ad666d67f37ac66ce`
