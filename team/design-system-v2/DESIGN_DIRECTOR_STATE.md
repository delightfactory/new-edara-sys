# Design Director State

## Reviewed baseline

- Development branch: `design-system-v2-development`
- Exact current development HEAD reviewed: `c8748dc84488351f7aec0c17c5267100090b07c7`
- Active implementation PR: #28 — `DS2-UI-001: migrate customer basic-info form to V2 composition`
- Exact PR HEAD reviewed for design-direction alignment: `ccbf9decab1257634874fc348525d6a50f588857`
- PR state: Draft / Open / mergeable clean
- Current workstream state: `DS2-UI-001` = `REVIEW`
- Evidence available: source/diff inspection + `TESTS_AUTHORED_NOT_EXECUTED`; no runtime visual evidence claimed

## Independent professional judgment

**ARCHITECTURAL ALIGNMENT: PASS WITH WATCHPOINTS.**

PR #28 remains aligned with the North Star and the declared DS2-UI-001 boundary. It is a bounded form-composition migration, not a Customer-module redesign.

The changed-file scope is limited to:
- `src/pages/customers/CustomerFormPage.tsx`
- `src/pages/customers/CustomerFormPage.v2.test.ts`

The implementation consumes existing shared V2 grammar rather than creating a customer-local component system:
- `PageHeader`
- `FormSection`
- `FormGrid`
- `FormActions`
- existing `PermissionGuard`

The shared responsive contracts support the intended device model:
- Mobile form grids collapse to one column;
- Tablet caps three/four-column requests at two columns through 1024px;
- Desktop may use the requested two/three-column density;
- Mobile sticky form actions are explicitly positioned above the Design System bottom-navigation height and safe-area inset.

No source-level reason was found to broaden the slice before Design QA. Customer create/update, GPS, credit guard, lookup and default branch/contact behavior remain outside the presentation layer and are intended to remain unchanged.

## Current design-system watchpoints

### 1. Tabs semantics — `WATCH`

The PR deliberately does not introduce a shared Tabs primitive, which is correct scope discipline. However it adds `role="tablist"`, `role="tab"` and `aria-selected` to the existing legacy tab buttons while the page does not currently show a complete shared keyboard/focus/tabpanel contract.

Design QA should explicitly decide this point on the exact PR HEAD. Do not allow Customer Form to become the place where EDARA invents a one-off partial ARIA Tabs implementation.

Preferred system rule for this slice:
- keep `type="button"` regardless, because tabs must not submit the form;
- if the ARIA tab contract is incomplete, retain ordinary button semantics for now and defer full tab semantics to the future shared Tabs/SubNav component-depth slice;
- if QA can prove the current semantics are complete enough, preserve them without expanding this PR into a broad Tabs redesign.

This is a `WATCH`, not a current architecture blocker.

### 2. Creation-default subgroups — bounded legacy composition

The branch/contact creation-default blocks still contain local inline subgroup styling inside the new shared `FormSection`. That is acceptable for DS2-UI-001 because extracting a new customer-specific subgroup primitive would be premature.

Do not promote these local blocks as system patterns until another real form proves the same need.

### 3. Exact-head churn from governance-only baseline drift — `WATCH`

After PR #28 was merge-synced to development baseline `d01f6c0b...`, the development branch advanced to `c8748dc...` only through Workstream / UI Implementation State documentation refreshes. No shared component or product-code drift occurred. The PR remains mergeable clean.

Therefore the feature branch should **not be merge-synced again solely for governance/state-file drift before QA**. Repeated non-functional syncs would move the PR HEAD and unnecessarily invalidate exact-head review evidence.

QA should review `ccbf9decab1257634874fc348525d6a50f588857` unless the product/test code itself changes or a relevant shared component changes.

## Cross-role context comparison

- UI Production Engineer reports `REVIEW_READY` on exact PR HEAD `ccbf9dec...`; this agrees with the independent architecture review.
- Design QA has not yet published a material review; no QA disposition exists to synthesize.
- Integration State has not yet been initialized by a material integration run; no merge evidence exists.
- Team Memory still describes the pre-implementation lifecycle snapshot. That is stale for lifecycle status but does not conflict with the current design direction or slice identity. Workstream + Implementation State + live PR are the current activity evidence. Integrator should refresh Team Memory after successful integration per ownership rules.

No cross-role `BLOCKING` contradiction exists at this review.

## Preserve

- zero backend/business behavior drift;
- existing customer create/update/GPS/credit/default-branch/default-contact semantics;
- the shared form grammar and device strategy;
- one active implementation slice only;
- no hosted CI / no Vercel preview from agents;
- no Customer-specific primitive extraction without recurring evidence;
- exact-head review discipline without governance-only SHA churn.

## Cross-role handoff

- **To:** Design QA, UI Production Engineer, Development Integrator
- **What changed:** PR #28 is now active and architecturally aligned with DS2-UI-001; current development drift after its last sync is documentation-only. One accessibility/system watchpoint remains around partial legacy-tab ARIA semantics.
- **Preserve:** bounded form-composition scope, shared V2 patterns, all customer business/permission behavior, current PR HEAD unless relevant product/shared-component code changes.
- **Need from you:** Design QA should independently review exact HEAD `ccbf9decab1257634874fc348525d6a50f588857`, especially sticky mobile actions and the tab-semantics watchpoint. UI Engineer should change the PR only for material QA findings. Integrator should not require another docs-only merge-sync and must wait for exact-head `GREEN-DEV`.
- **Blocker level:** `WATCH`
- **Baseline:** development `c8748dc84488351f7aec0c17c5267100090b07c7`; PR #28 `ccbf9decab1257634874fc348525d6a50f588857`
