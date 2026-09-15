# 27 — Sidebar V2 Renderer

## Purpose
Build the new Sidebar presentation on top of the extracted navigation model without replacing the production Sidebar yet.

## Implemented
- New `SidebarV2` renderer consumes `getVisibleSidebarSections` instead of owning route/permission metadata.
- Semantic Design System tokens replace the legacy hard-coded light/dark palette.
- Current-route groups auto-expand.
- Notification unread count, theme toggle, profile context and sign-out are retained.
- Navigation closes the drawer after selection at Mobile and Tablet widths (≤1024px).
- Drawer controls and child links use touch-sized targets on Mobile/Tablet.
- Reduced-motion behavior and focus-visible states are defined.
- Focused tests cover route-driven expansion, unread context, and drawer close behavior.

## Guardrails
- `SidebarV2` is not mounted by `AppLayout` in this slice.
- The existing production Sidebar remains the active renderer.
- No route, permission, database, RPC, workflow or business behavior changes.
- No Vercel deployment is required for this isolated slice.

## Activation gate
Before replacing the legacy Sidebar, validate the new renderer visually in:
- Desktop light + dark
- Tablet portrait + landscape drawer
- Mobile drawer
- long Arabic labels
- admin/full-permission navigation
- restricted-permission navigation
- unread notification badge
