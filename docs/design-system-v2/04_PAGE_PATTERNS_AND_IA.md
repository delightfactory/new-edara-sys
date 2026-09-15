# 04 — Page Patterns & Information Architecture

## Shared page grammar
### Entity list
PageHeader → optional operational summary → search/filter bar → table/list → pagination → safe bulk actions.

Device adaptation:
- desktop/tablet may use dense DataTable when comparison across columns matters
- mobile defaults to scan-friendly DataCard/list patterns that surface identity, status, owner, amount/date and the next action without horizontal scrolling

### Entity detail
Context/back → entity identity/status → primary actions → summary metrics → sections/tabs → related transactions → activity/audit history.

On mobile, identity/status and the most frequent next action must appear before secondary history. Secondary actions move into an overflow/action sheet rather than crowding the header.

### Transaction detail
Transaction identity/status → parties/location/context → line items → financial/inventory effect → evidence/attachments → lifecycle timeline → guarded actions.

On mobile, transaction status, amount/quantity, customer/supplier/warehouse context and actionable state take priority. Large line-item grids transform into stacked rows/cards while preserving totals and audit meaning.

### Create/edit
Context → grouped form sections → inline validation → consistent/sticky action area → safe cancel/back behavior.

Mobile uses touch-friendly single-column composition by default, appropriate input modes and persistent access to save/submit where safe. Desktop/tablet may use multiple columns when this improves comparison without harming readability.

### Operational queue
Queue scope → ownership/priority/status filters → records → obvious next action → optional bulk action.

Mobile optimizes for one-record-at-a-time action and fast scanning. Desktop may expose safe multi-select/bulk operations.

### Dashboard
Role-relevant KPIs → exceptions requiring action → operational queues → trends/context → shortcuts. Avoid decorative metrics.

Mobile dashboard prioritizes "what needs my action now" above broad analytics. Desktop can expose more comparative context and charts.

### Report
Purpose/title → date/scope filters → summary → visualization/table → drill-down/export where supported.

Reports remain usable on mobile for summary and drilldown, but desktop/tablet are the preferred surfaces for wide comparative analysis.

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

## Mobile navigation rule
The current BottomNav proves the product already supports a mobile shell, but fixed universal tabs should be reviewed against real role frequency. V2 may use permission-aware/task-aware primary shortcuts while preserving the full route/permission model behind the menu.

Mobile primary navigation must expose only a small set of high-frequency destinations/actions. It must not become a miniature copy of the desktop sidebar.

## Rules
- Permission behavior is preserved; IA changes visibility/presentation only.
- Avoid duplicate destinations across multiple groups unless there is a deliberate shortcut.
- Keep labels business-oriented and Arabic-first.
- Mobile primary navigation exposes frequent operational tasks; the full IA remains available through the menu/drawer.
- Tablet navigation may use a compact/collapsible navigation model depending on available width and task density.
- Future Manufacturing plugs into Operations using the same grammar, not a separate visual application.
