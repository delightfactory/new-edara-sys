# 25 — Tablet Shell Slice

## Purpose
Fix the current binary shell behavior where 769px immediately becomes full desktop with a persistent 260px sidebar.

## Implemented behavior
- Desktop remains persistent-sidebar only above 1024px.
- Tablet (769–1024px) uses the top App Bar and a 44px menu trigger.
- On tablet, the existing Sidebar becomes an on-demand drawer with overlay and close control.
- Tablet content uses the full viewport width while the drawer is closed.
- Mobile (≤768px) keeps the existing App Bar + BottomNav model.
- The mobile App Bar does not show a redundant menu button because BottomNav already provides the Menu shortcut.

## Guardrails
- No route or permission changes.
- No Sidebar navigation-content rewrite in this slice.
- No BottomNav or FAB visual redesign.
- No business/data/service/database changes.
- Breakpoint behavior is aligned with `useDeviceMode`: mobile ≤768, tablet 769–1024, desktop >1024.

## Runtime acceptance targets
- 768px: BottomNav visible, no App Bar menu button.
- 769px: BottomNav hidden, App Bar menu button visible, Sidebar closed by default.
- 1024px: tablet drawer behavior remains active.
- 1025px: persistent desktop Sidebar resumes.
- Opening the tablet menu must show the existing permission-filtered Sidebar without changing destinations or actions.
