# UI Implementation State

## Reviewed baseline

- Development baseline used to create the feature branch: `9acb9b7582c97709f69b6acec68d864762f8802e`
- Feature branch: `ds2/customer-form-basic-info-v2`
- Draft PR: #28 — `DS2-UI-001: migrate customer basic-info form to V2 composition`
- Exact implementation/test HEAD handed to review: `8daaf6a3df1ced8a6a5e6c04fad251ae802710cc`
- Active slice: `DS2-UI-001 — Customer Form: basic-info composition`
- Implementation disposition: `REVIEW_READY`

## What changed

The Customer Form `info` composition was migrated onto the existing V2 grammar without intentionally changing business behavior:

- legacy page heading replaced by shared `PageHeader` with the existing Customers back destination;
- Basic Information, Address, Payment/Credit, Creation Defaults and Notes now compose through shared `FormSection`;
- field layouts now use `FormGrid`, preserving one-column Mobile, capped two-column Tablet and requested Desktop density;
- save/cancel now use shared `FormActions` with explicit Mobile sticky behavior for this long form;
- existing edit tabs remain on the established tab styling because no shared Tabs primitive is currently present in the proven V2 layer; their buttons are now explicitly `type="button"` and expose `tablist`/`tab`/`aria-selected` semantics;
- creation-default contact fields also use the shared responsive FormGrid instead of a page-local grid declaration.

## Files changed

- `src/pages/customers/CustomerFormPage.tsx`
- `src/pages/customers/CustomerFormPage.v2.test.ts`

No service, query, database, permission definition, route guard, validation rule or business workflow file was changed.

## Shared patterns reused

- `PageHeader`
- `FormSection`
- `FormGrid`
- `FormActions`
- existing `PermissionGuard`
- existing `ResponsiveModal` remains untouched for out-of-scope secondary tabs/modals

No new page-local primitive was introduced.

## Functional invariants preserved in source

- edit submits through existing `updateCustomer(id!, form)` path;
- create submits through existing `createCustomer(form)` path;
- default branch creation still uses `saveCustomerBranch(created.id, ...)`;
- optional default contact creation still uses `saveCustomerContact(created.id, ...)`;
- customer GPS still uses existing `captureGPS` / location persistence behavior;
- finance credit limit remains wrapped by `PermissionGuard permission="finance.credit.manage" mode="disable"`;
- credit-history tab visibility remains guarded by `can('customers.credit.update')`;
- governorate/city/area, price-list and representative loading/selection logic was not altered;
- branches, contacts, credit-history surfaces and their responsive modals were not redesigned in this slice.

## Device / state coverage

- Mobile: shared grids collapse to one column; long-form action surface opts into `stickyOnMobile`; tabs are non-submitting controls.
- Tablet: shared FormGrid contract caps layout at two columns even where Desktop requests three.
- Desktop: basic fields remain two-column; address/payment sections request three-column density; commercial assignment remains two-column.
- RTL/Arabic: existing Arabic labels/content and LTR treatment for phone/email/numeric coordinates are preserved.
- Saving/GPS disabled/loading states remain on the existing controls.
- Credit disabled/permission state remains delegated to the existing PermissionGuard.

## Test evidence

Focused contract test added:
`src/pages/customers/CustomerFormPage.v2.test.ts`

It protects:
- shared V2 composition imports/usages;
- existing form submit wiring;
- finance credit permission boundary;
- credit-tab visibility permission;
- customer creation + default branch/contact side effects;
- GPS action wiring;
- tab non-submit/accessibility semantics.

Evidence label: `TESTS_AUTHORED_NOT_EXECUTED`.

Hosted GitHub Actions were not triggered. No approved local repository runtime is available in this run, so no executed test/build PASS is claimed.

## Known review watchpoints

- Runtime visual evidence is intentionally absent until an owner-requested preview milestone.
- Design QA should specifically judge whether Mobile sticky actions coexist correctly with the app shell/bottom navigation under the shared `FormActions` CSS contract.
- The existing edit-tab visual component remains legacy because a proven shared Tabs primitive is not present; this is deliberate scope control, not a claim that tabs are globally migrated.
- Secondary Customer tabs and modals remain legacy/out of scope for DS2-UI-001.

## Cross-role handoff

- **To:** Design QA
- **What changed:** PR #28 migrates the Customer basic-info form composition to shared V2 PageHeader/FormSection/FormGrid/FormActions while preserving existing handlers and permission boundaries; focused source-contract tests were added.
- **Preserve:** all customer create/update, GPS, lookup, credit guard, default branch/contact and secondary-tab behavior; no backend/query/validation expansion.
- **Need from you:** independently review exact PR HEAD `8daaf6a3df1ced8a6a5e6c04fad251ae802710cc` for functional isolation, shared-system fit, RTL/accessibility and Mobile/Tablet/Desktop composition. Give special attention to Mobile sticky actions and the deliberate retention of legacy tab visuals.
- **Blocker level:** `NONE`
- **Baseline:** feature branch created from `9acb9b7582c97709f69b6acec68d864762f8802e`; review the live PR HEAD for freshness before disposition.
