# 29 — Dashboard V2 Migration

## Purpose
Make Dashboard the first real page migration onto the shared Design System V2 grammar while preserving all existing data and permission behavior.

## Preserved without change
- `fetchOverviewStats` queries and the `get_low_stock` RPC usage.
- `fetchSalesStats` calculations and query filters.
- React Query keys and stale times.
- `sales.read`, `finance.read`, `finance.view_costs`, and `inventory.read` visibility checks.
- `GoalCommandCenter` behavior and placement near the top of the dashboard.
- Existing KPI meaning and pending-operation counts.

## Presentation migration
- Shared `PageHeader` replaces local page-header composition.
- Shared `StatCard` replaces the local `KpiCard` implementation.
- Shared `SectionHeader` replaces the local section-heading implementation.
- Shared `Card` becomes the section surface.
- Shared `AlertPanel` + `StatusBadge` represent low-stock risk.
- Shared `StatePanel` represents the limited-permission welcome state.
- Page-local inline styles and embedded dashboard CSS are replaced by `dashboard-v2.css`.

## Device composition
- Mobile: 2-column KPI/metric grids by default; single column at very narrow widths (≤390px).
- Tablet: 3-column primary KPI grid and 2-column sales grid.
- Desktop: auto-fit dense management grid.

## Guardrails
- No DB/RPC/service/query/permission/business logic changes.
- No action behavior changes.
- No route changes.
- No Vercel deployment required for this branch.

## Tests
Focused render-contract tests protect:
1. full-access visibility of the main operational information;
2. permission-driven hiding of sales/inventory sections and the limited-access welcome state.

## Runtime visual gate
Before using Dashboard as the visual reference for Customers/Sales, validate at mobile, tablet and desktop widths when controlled preview access is available.
