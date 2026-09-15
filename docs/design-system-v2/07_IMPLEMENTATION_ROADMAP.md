# 07 — Implementation Roadmap

## Phase A — Audit freeze
1. Finish static route/page/component inventory.
2. Capture representative runtime screens/flows.
3. Record UI debt by P1/P2/P3 severity.
4. Freeze V2 visual/interaction direction before broad implementation.

## Phase B — Foundations
1. Add semantic aliases over existing tokens; preserve compatibility.
2. Standardize typography roles, density, focus, status and responsive rules.
3. Define component ownership/layering.

## Phase C — Component V2
1. Action hierarchy/Button.
2. Field system.
3. Badge/StatusBadge.
4. Card/Section/StatCard.
5. Modal/ResponsiveSheet/ConfirmDialog.
6. Empty/Error/Loading/Permission states.
7. DataTable/MobileDataCard.
8. FilterBar decomposition.
9. PageHeader/EntityHeader/TransactionHeader.

## Phase D — Shell proof
Refactor Sidebar/AppBar/BottomNav/layout using the new foundations. Do not change route permissions or business destinations.

## Phase E — Golden-flow proof
Migrate and visually validate:
- Dashboard
- Customer list + detail
- Sales list + detail/create
These screens exercise KPIs, filters, tables, forms, statuses, transaction details and responsive behavior.

## Phase F — Controlled module rollout
Follow `05_MIGRATION_MATRIX.md`, with high-risk domains (inventory/finance/HR/workflow) only after shared patterns prove stable.

## Phase G — Legacy cleanup
Remove old CSS/components only when repository search proves no remaining consumers and regression checks pass.

## First implementation target
Do not start by recoloring every page. Start with foundations + a thin V2 component slice + app shell + golden flows. This produces a coherent demonstrable product early while keeping regression blast radius small.
