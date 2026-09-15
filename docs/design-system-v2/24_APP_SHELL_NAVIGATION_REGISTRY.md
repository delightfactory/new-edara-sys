# 24 — App Shell & Navigation Registry

## Purpose
Create one authoritative navigation model before changing the visible shell.

## Current problem
Navigation responsibilities are currently split across `Sidebar`, `BottomNav`, and `FAB`. Each layer maintains its own routes, permissions, labels, priorities, and presentation rules. That creates drift and makes Mobile / Tablet / Desktop behavior hard to reason about.

## V2 direction
- Keep route protection in `App.tsx` unchanged.
- Introduce a presentation-only navigation registry as the single source for shell navigation metadata.
- The registry may describe labels, icons, paths, permission visibility, grouping, high-frequency mobile destinations, and creation actions.
- Permission evaluation remains delegated to the existing auth store; the registry does not grant access.
- Bottom navigation is task-frequency driven, not a mirror of the desktop sidebar.
- Tablet gets an explicit compact shell instead of inheriting the full desktop sidebar at 769px.

## Device roles
### Mobile
- 4 high-frequency destinations + Menu maximum by default.
- BottomNav is the primary global navigation surface.
- Full navigation opens as a drawer/menu.
- Only high-value context actions should become floating/sticky actions.

### Tablet
- Compact/collapsible navigation.
- Preserve touch-sized targets.
- Avoid consuming 260px permanently at common portrait widths.
- Support more visible context than mobile without forcing desktop density.

### Desktop
- Grouped sidebar remains appropriate.
- Dense navigation and management destinations may be visible.
- Secondary groups remain permission-filtered.

## Guardrails
- No route, permission, RBAC/RLS, workflow, database, or service behavior changes.
- Registry metadata cannot be used as an authorization boundary.
- Existing routes and labels are preserved during the first extraction.
- Visual redesign happens only after registry parity is proven.

## First extraction slice
1. Define shared navigation types and permission metadata.
2. Define mobile-primary destinations separately from full section navigation.
3. Define route-scoped creation actions in the same metadata family.
4. Add unit tests for permission filtering and longest-path matching.
5. Do not replace `Sidebar`, `BottomNav`, or `FAB` in the same PR.
