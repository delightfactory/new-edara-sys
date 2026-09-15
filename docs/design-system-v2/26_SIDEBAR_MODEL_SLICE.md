# 26 — Sidebar Model Extraction

## Purpose
Separate Sidebar information architecture and permission projection from its current presentation-heavy React component.

## Implemented
- `SIDEBAR_SECTIONS` defines the existing high-level groups and nested destination membership using shared navigation-registry IDs.
- `getVisibleSidebarSections` resolves permission-filtered visible sections without rendering concerns.
- The model is independent from theme, expansion state, CSS, icons, profile/footer UI and drawer state.
- Tests ensure every referenced destination exists, destinations are not duplicated across groups, high-level section order remains stable, and empty unauthorized groups disappear.

## Guardrails
- The current `Sidebar.tsx` is not replaced in this slice.
- No route or permission semantics are changed.
- No visual change is introduced.
- No database, RPC, workflow or business behavior is touched.

## Next slice
Build the V2 Sidebar renderer on top of this model and semantic tokens, then validate Desktop + Tablet Drawer + Mobile Menu behavior before replacing the legacy presentation.
