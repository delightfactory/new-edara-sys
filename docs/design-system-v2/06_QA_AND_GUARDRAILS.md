# 06 — QA Gates & No-Functional-Change Contract

## Forbidden in UI-refactor PRs
- Supabase migrations or RPC changes
- financial/accounting calculations
- inventory/credit/payroll calculations
- workflow/status transition behavior
- RBAC/RLS/permission semantics
- API/data contracts
- ownership/responsibility rules
- notification trigger semantics

If a UI change reveals a functional defect, open a separate issue/PR. Do not hide a business change inside visual work.

## Every migrated screen must pass
### Functional preservation
- existing successful actions still complete
- existing validation/business errors still occur under the same conditions
- permission-restricted actions remain restricted
- no new mutation route is introduced merely for UI convenience

### Responsive/UI
- desktop
- tablet/intermediate
- mobile
- RTL
- long Arabic labels/names
- large monetary and quantity values
- no unintended horizontal overflow

### State coverage
- loading
- empty
- error
- validation error
- disabled/read-only
- permission restricted
- success/confirmation when relevant

### Interaction/accessibility
- primary action is clear
- destructive actions are distinct and confirmed
- visible keyboard focus
- adequate touch targets
- accessible names/labels
- status is not color-only
- dialogs/sheets restore focus sensibly

### Engineering evidence
- typecheck
- relevant tests
- build
- before/after screenshots for materially changed screens
- changed-file check proving forbidden backend categories were untouched

## PR size
Prefer small migration batches. A shared-component PR should not simultaneously restyle many unrelated modules unless required for compatibility.
