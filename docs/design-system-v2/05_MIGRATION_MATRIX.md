# 05 — Page/Module Migration Matrix

| Wave | Surface | Primary refactor target | Risk |
|---|---|---|---|
| 0 | Baseline | Runtime screenshots, route/component inventory, guardrails | Low |
| 1 | Foundations | tokens, type, spacing, status semantics, focus states | Medium/shared |
| 2 | Core primitives | buttons, fields, badges, cards, dialogs, states | Medium/shared |
| 3 | Data patterns | tables/cards, filters, headers, metrics, timelines | Medium/shared |
| 4 | App shell | Sidebar IA, AppBar, BottomNav, gutters, responsive navigation | High visual / low functional |
| 5 | Dashboard | hierarchy, KPIs, action center, responsive layout | Medium |
| 6 | Customers & Credit | list/detail grammar, credit state visibility, filters | Medium |
| 7 | Products & Suppliers | master-data list/detail/forms | Low–Medium |
| 8 | Sales | order list/detail/create, returns, shipping | High regression sensitivity |
| 9 | Inventory | warehouse/stock/transfer/adjustment/movement/valuation | High regression sensitivity |
| 10 | Procurement | invoices/orders/returns | High regression sensitivity |
| 11 | Finance | vaults/custody/payments/expenses/accounts/journals/ledger | Critical regression sensitivity |
| 12 | HR | employees, attendance, payroll, adjustments, self-service | High permissions/state sensitivity |
| 13 | Activities/Targets | plans, visits, calls, targets, checklists | High mobile sensitivity |
| 14 | Work Management | workspace/team/manage/approval/workflow surfaces | High state-machine sensitivity |
| 15 | Reports/Analytics | filter grammar, visualization hierarchy, drilldown | Medium |
| 16 | Settings/Admin | settings, permissions, branches and remaining surfaces | High permissions sensitivity |
| 17 | Cleanup | remove legacy styles/components only after usage proof | Medium |

## Batch rule
Each wave is independently testable and reversible. Shared primitives are stabilized before high-risk financial/inventory pages consume them.

## Priority rationale
The first visible implementation after foundations should be App Shell + Dashboard + one representative entity flow (Customers) and one transaction flow (Sales). This provides enough coverage to validate the language before broad migration.
