# 13 — Module UI Audit Matrix

This matrix turns the source audit into module-level implementation guidance. `Deep` means representative source screens were inspected in detail; `Mapped` means routes/files are inventoried but representative screens still need a deeper source/runtime pass before migration.

| Module / Surface | Coverage | Device priority | Current strengths | Main UI debt | V2 target | Refactor risk |
|---|---|---|---|---|---|---|
| App Shell / Navigation | Deep | Mobile + Tablet + Desktop | Existing Sidebar, AppBar, BottomNav, FAB, RTL/PWA tokens | Binary 768px shell, large mixed-responsibility Sidebar, hard-coded sidebar palette, competing action surfaces | Navigation model + DesktopSidebar + TabletNav + MobileDrawer + ActionRegistry | High visual / critical navigation |
| Dashboard | Deep | Mobile + Desktop | Useful operational KPIs/alerts and mobile KPI grid | Local KpiCard/SectionHead/CSS, raw color props, page-specific hierarchy | StatCard, SectionHeader, AlertPanel, ActionRow, role-aware dashboard composition | Medium |
| Customers | Deep | Mobile primary | Desktop table + mobile cards, direct call/map actions, URL filters | Duplicated responsive collection state/CSS, large form with local controls | ResponsiveCollection + EntityHeader + Field/FormSection + coordinated actions | Medium |
| Credit | Mapped | Mobile + Desktop | Strong domain linkage to customers/sales | Must align status/risk/monetary presentation with shared semantics | CreditSummary, RiskStatus, FinancialMetric, shared collection/detail grammar | High financial meaning |
| Products | Mapped | Desktop/Tablet + lookup on Mobile | Mature master-data routes | Needs shared master-data form/list/detail grammar | MasterDataList, EntityDetail, Field system, StatusBadge | Medium |
| Suppliers | Mapped | Desktop/Tablet; Mobile lookup/action | Standard list/detail/form route family | Likely same duplicated master-data composition as other modules | Reuse Product/Customer entity patterns with supplier-specific content only | Medium |
| Sales Orders | Deep | Mobile primary | Device-aware list, infinite mobile cards, sophisticated 4-step order flow | Local KPIs, local Combobox/Stepper/form primitives, local Smart Transfer FAB | ResponsiveCollection, Stepper, Field, ProductLineEditor shell, ReviewSummary, ActionRegistry | High regression sensitivity |
| Sales Returns / Shipping | Mapped | Mobile + Desktop | Existing dedicated flows | Must inherit Sales V2 patterns instead of creating another family | Transaction list/detail/form patterns + shared action/status semantics | High |
| Inventory — Transfers | Deep | Mobile + Tablet + Desktop | Clear push/pull workflow, status actions, responsive modal/card mode | Local product combo, local FAB, raw fields, inline card actions, binary breakpoint | InventoryTransactionCard, Field, approved Combobox, ActionRegistry, ResponsiveCollection | Critical operational |
| Inventory — Stock / Adjustments / Movements / Valuation | Mapped | Tablet/Desktop dense; Mobile review/action | Clear separate operational views | High table/data density; must avoid squeezed tables and visual ambiguity of quantities/costs | InventorySummary, quantity semantics, compact desktop tables, mobile prioritized cards | Critical inventory |
| Procurement — Purchase Invoices | Deep | Tablet/Desktop primary; Mobile approval/review | Rich 4-step procurement workflow and landed-cost logic | `PurchaseInvoiceForm` ~101KB; local Stepper, StatusBadge, Combobox, product picker, cards/grids/fields | Reuse Sales transaction primitives without sharing domain logic; Stepper, Field, LineEditor shell, StatusBadge | Critical procurement |
| Procurement — Returns | Mapped | Tablet/Desktop + Mobile review | Dedicated return flow | Should not develop a third independent transaction visual language | Shared transaction form/detail grammar | High |
| Finance — Payments | Deep | Mobile collection + Desktop review | Strong mobile cards, filters, proof upload, custody/vault context, AsyncCombobox already used | Local InfoCard/AlertBanner, local FAB, raw form controls, duplicate mobile collection | FinancialSummary, AlertPanel, Field/MoneyField, ResponsiveCollection, ActionRegistry | Critical financial |
| Finance — Vaults / Custody / Expenses | Mapped | Mobile action + Desktop management | Dedicated operational routes | Monetary/action semantics need strict consistency; local modal/FAB patterns likely repeated | MoneyField, FinancialMetric, ApprovalPanel, ActionRegistry, TransactionCard | Critical financial |
| Finance — Accounts / Journals / Ledger / Balance Sheet | Mapped | Desktop/Tablet primary | Separate accounting surfaces | Dense tabular accounting information; mobile should prioritize review, not shrink desktop | AccountingTable, FinancialSummary, Report/ledger shell, explicit debit/credit semantics | Critical accounting |
| HR — Attendance Check-in | Deep | Mobile primary | True mobile-first task flow, GPS/online status, progress/success/error, safe-area awareness | ~48KB page-local component/CSS island | Preserve workflow; extract OperationalTaskScreen, ProcessProgress, ConnectionStatus, PrimaryTaskAction | High operational, low business-change tolerance |
| HR — Attendance Admin | Mapped | Desktop/Tablet primary | Dedicated admin route | Dense monitoring/admin state must differ from employee check-in UI | Responsive admin collection + status/filter patterns | High permissions/state |
| HR — Employees | Mapped | Desktop/Tablet primary; Mobile profile/self-service | Rich employee profile/form domain | EmployeeProfile ~118KB; EmployeeForm ~55KB indicate likely page-level composition overload | EntityProfile shell, tab/section grammar, Field/FormSection, ActivityTimeline | High |
| HR — Self-service / Leaves / Advances / Delegations / Adjustments / Payroll | Mapped | Mobile self-service + Desktop approval/payroll | Good route separation by responsibility | Multiple approval/list/form patterns risk visual drift | ApprovalQueue, RequestForm, StatusBadge, MoneyField, ResponsiveCollection | High permissions/payroll |
| Field Activities — Visit Execution | Deep | Mobile primary | Purpose-built mobile flow, offline/IndexedDB/photo sync/GPS, sticky local action, checklist preservation | Very large workflow UI with many local status/action components | Preserve atomic/offline behavior; extract OperationalTaskScreen, SyncStatus, StickyTaskAction, EvidenceStatus patterns | Critical field workflow |
| Field Activities — Activities / Visit Plans / Call Plans / Targets | Mapped | Mobile + Desktop planning | Strong breadth and flow tests in target/activity areas | Multiple forms/details may have their own visual grammar | PlanList/PlanDetail, Stepper/FormSection, Timeline, StatusBadge, responsive planning collections | High |
| Work Management | Deep | Mobile action + Desktop/Tablet management | One of the most mature responsive areas; explicit 1024/768 layouts, sticky mobile actions, feature components | Separate CSS island and its own summary/form/panel primitives | Use as reference; migrate good patterns into shared V2 without changing work state-machine logic | Critical state-machine |
| Reports / Analytics | Deep (shell) | Desktop/Tablet primary; Mobile summary | ReportsLayout already handles 1024/768, chart/table overflow, 44px tabs | Very large horizontal sub-nav, local report shell/filter/grid CSS, many report pages can drift | ReportShell, ReportNav, ReportFilterBar, MetricGrid, ChartPanel, mobile summary policy | Medium–High data density |
| Settings / Users / Roles / Company / Audit | Mapped | Desktop primary | Routes and permission boundaries are clear | Admin forms/tables require consistency and should not inherit field-mobile assumptions blindly | AdminTable, PermissionMatrix, Field/FormSection, AuditTable | High permissions |
| Notifications | Mapped | Mobile + Desktop | Dedicated route + global notification panel/bell | Needs consistent read/unread/action treatment across shell and page | NotificationItem/Feed, status/action semantics | Medium |
| Document Preview / Output | Mapped | All | Separate output feature | Must visually integrate without altering printable/export artifacts | Document viewer shell/actions; keep document rendering domain separate | Medium |

## Cross-module conclusions

### 1. The largest debt is not missing CSS
The repository already contains many good controls and responsive ideas. The core debt is **multiple independent implementations of the same UI concept**: fields, comboboxes, KPI cards, status badges, alert banners, product pickers, action FABs, mobile collections and section headers.

### 2. There are three legitimate screen families
V2 must not force one layout onto everything:
- **Operational Task** — mobile-first, one next action, GPS/photo/offline/progress aware. Examples: attendance, visit execution.
- **Operational Transaction** — mobile capture + desktop/tablet review. Examples: sales, transfer, payment, purchase invoice.
- **Management / Analysis** — desktop/tablet dense with mobile summary/review. Examples: accounting, reports, admin settings.

### 3. Good local patterns become system patterns
Work's 1024px adaptation, Attendance's task focus, Visit Execution's offline/status handling, Customers/Sales card collections, and Reports overflow protections are sources for V2 patterns. The project should standardize its own strongest solutions before importing new abstractions.

### 4. High-risk modules migrate later
Finance, inventory, procurement, HR/payroll and Work state-machine views must consume stabilized V2 primitives first. Their UI PRs require explicit functional-regression evidence.

## Audit completion rule
A module marked `Mapped` is not visually approved yet. Before its implementation wave starts, inspect representative list/detail/form/task screens and capture runtime evidence at the device widths defined in `11_GOLDEN_FLOW_ACCEPTANCE.md`.
