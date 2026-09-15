# 23 — Form Composition Patterns

## Purpose
Standardize how forms are visually grouped before migrating any domain workflow.

## Added patterns
- `FormSection`: shared card + section header + body/footer composition.
- `FormGrid`: canonical responsive field grid.
- `FormActions`: shared action row with explicit optional sticky-mobile behavior.

## Device behavior
- Mobile: form grids collapse to one column.
- Tablet: three/four-column desktop grids are capped at two columns.
- Desktop: requested density from one to four columns is respected.
- Sticky mobile actions are opt-in only.

## Guardrails
- Presentation only.
- No validation or workflow behavior is moved into these components.
- No current page consumes these patterns yet.
- No database, RPC, permissions, RBAC/RLS, inventory, finance or HR changes.

## Intended consumers
- Customer and product forms.
- Sales order and purchase invoice forms.
- Inventory transfer/adjustment forms.
- HR administrative forms after lower-risk migrations prove the pattern.
