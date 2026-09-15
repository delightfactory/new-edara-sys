# 04 — Page Patterns & Information Architecture

## Shared page grammar
### Entity list
PageHeader → optional operational summary → search/filter bar → table/list → pagination → safe bulk actions.

### Entity detail
Context/back → entity identity/status → primary actions → summary metrics → sections/tabs → related transactions → activity/audit history.

### Transaction detail
Transaction identity/status → parties/location/context → line items → financial/inventory effect → evidence/attachments → lifecycle timeline → guarded actions.

### Create/edit
Context → grouped form sections → inline validation → consistent/sticky action area → safe cancel/back behavior.

### Operational queue
Queue scope → ownership/priority/status filters → records → obvious next action → optional bulk action.

### Dashboard
Role-relevant KPIs → exceptions requiring action → operational queues → trends/context → shortcuts. Avoid decorative metrics.

### Report
Purpose/title → date/scope filters → summary → visualization/table → drill-down/export where supported.

## Navigation direction
The current sidebar contains many domain groups and nested routes. V2 should organize by user mental model rather than database/module history.

Proposed top-level IA to validate in runtime audit:
- Home / Action Center
- Operations: Sales, Procurement, Inventory, future Manufacturing
- Commercial: Customers, Credit, Products/Pricing, Targets/Field Activity
- Finance: Vaults, Payments, Expenses, Accounting
- People: Employee self-service + HR administration
- Management: Work, Reports/Analytics
- Administration: Branches, permissions/settings, system configuration

## Rules
- Permission behavior is preserved; IA changes visibility/presentation only.
- Avoid duplicate destinations across multiple groups unless there is a deliberate shortcut.
- Keep labels business-oriented and Arabic-first.
- Mobile primary navigation must expose only frequent field actions; the full IA remains available through the menu/drawer.
- Future Manufacturing plugs into Operations using the same grammar, not a separate visual application.
