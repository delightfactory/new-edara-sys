# 21 — Responsive Collection Slice

## Purpose
Introduce one canonical device-mode contract and one collection-orchestration pattern before migrating domain pages.

## Scope
- `useDeviceMode` centralizes Mobile / Tablet / Desktop thresholds.
- `ResponsiveCollection` mounts exactly one device presentation at a time.
- Tablet composition can be explicit, or deliberately fall back to mobile/desktop.
- Loading and empty states are handled before device-specific rendering.
- No existing page is migrated in this slice.

## Guardrails
- No business logic changes.
- No data-fetching changes.
- No route/permission/RBAC/RLS changes.
- No database/RPC changes.
- No current page visual changes.
- No Vercel deployment is required.

## Intended first consumers
Customers and Sales list screens after runtime visual evidence, followed by Inventory / Finance list screens.
