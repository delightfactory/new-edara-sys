# 18 — Implementation Epics & PR Boundaries

The refactor is deliberately split into small, reviewable PRs. A PR may be divided further if changed-file count or risk grows beyond easy review.

## Global rule for every implementation PR

Must state:
- exact UI surfaces/components changed;
- business/backend categories explicitly untouched;
- device states checked;
- tests/typecheck/build evidence;
- before/after runtime visual evidence when the PR changes rendered UI materially;
- separate issues for any discovered functional defect.

Automatic Vercel Git deployments are disabled. Preview deployments are created manually only at planned visual-review checkpoints.

---

## Epic 0 — Runtime baseline & visual evidence

**Purpose:** capture current product before broad visual change.

Evidence set:
- shell/navigation
- dashboard
- customers list/detail/form
- sales list/detail/form
- inventory transfer
- finance payment
- purchase invoice
- attendance
- visit execution
- work hub/detail
- reports
- representative admin screen

Device evidence follows `11_GOLDEN_FLOW_ACCEPTANCE.md`.

**No product code changes.**

---

## Epic 1 — Foundations & semantic tokens

### PR 1A — Semantic aliases
Scope:
- add semantic surface/text/border/action/status/focus aliases over current tokens;
- no broad recoloring;
- retain old tokens during migration.

Forbidden:
- page rewrites;
- business/permission logic;
- removing legacy variables.

### PR 1B — Device/density/type rules
Scope:
- typography roles;
- tabular numeric rules;
- spacing/density contracts;
- explicit mobile/tablet/desktop layout tokens where useful;
- 44px operational touch-target contract;
- reduced-motion/focus baselines.

**Checkpoint:** no manual Vercel deploy required unless rendered output is materially changed.

---

## Epic 2 — Primitive hardening

### PR 2A — Button + IconButton
- action hierarchy;
- consistent loading/disabled/focus;
- touch-area enforcement;
- icon-only accessible labels.

### PR 2B — Field foundation
- Field wrapper;
- Input/Select/Textarea;
- help/error/read-only/required;
- MoneyField / QuantityField / PercentageField / PhoneField / DateField / SearchField.

### PR 2C — Status and feedback
- Badge retain;
- StatusBadge;
- AlertPanel;
- loading/empty/error/permission/offline/sync state family.

### PR 2D — Overlay controls
- ResponsiveModal focus trap/restore/unique ids;
- ConfirmDialog semantics;
- Tooltip/Popover/Dropdown where necessary;
- evaluate/deprecate legacy Modal only after consumer inventory.

### PR 2E — Selectors & upload
- AsyncCombobox full keyboard interaction and clear semantics;
- ProofUpload control touch/validation/lifecycle improvements;
- no changes to entity lookup or upload backend semantics.

**Manual Preview checkpoint:** yes, after Epic 2 is stable, to visually inspect primitive states on all devices.

---

## Epic 3 — Shared application patterns

### PR 3A — Structural surfaces
- Card / Section / Panel;
- SectionHeader;
- PageHeader evolution;
- EntityHeader;
- TransactionHeader;
- KeyValueList.

### PR 3B — Forms
- FormSection;
- FormGrid;
- StickyFormActions;
- Stepper evolution;
- ReviewSummary shell.

### PR 3C — Metrics and summaries
- StatCard / Metric;
- FinancialSummary;
- InventorySummary;
- domain values remain supplied by domain logic.

### PR 3D — Tabs and navigation sub-patterns
- Tabs;
- SegmentedControl;
- SubNav;
- consistent sticky/scroll behavior.

### PR 3E — Responsive collections
- ResponsiveCollection;
- DataTable evolution;
- DataCard evolution;
- shared pagination/infinite/loading/end/empty state presentation.

Important: initial PR does not silently change query strategy. Any duplicate-query optimization is a separate tested performance change.

### PR 3F — FilterBar decomposition
- preserve public behavior;
- split search/select/date/toggle/stats/mobile sheet internally;
- fix nested interaction and touch targets.

### PR 3G — Action orchestration
- ActionRegistry / ActionSlot;
- render to desktop toolbar, tablet toolbar/overflow, mobile FAB/sticky/overflow;
- no authorization redesign.

**Manual Preview checkpoint:** yes. This is the first full V2 pattern library checkpoint.

---

## Epic 4 — App Shell & navigation

Prerequisite: runtime baseline for shell and tablet widths.

### PR 4A — Navigation model extraction
- move route labels/groups/icons/permission visibility into a navigation model/configuration;
- preserve exact destinations and permission behavior.

### PR 4B — Desktop shell
- DesktopSidebar renderer using semantic tokens;
- consistent collapse/expand/gutters/content width;
- remove local hard-coded sidebar palette.

### PR 4C — Tablet shell
- deliberate intermediate navigation for portrait/landscape;
- no automatic full 260px sidebar at 769px;
- maintain touch-grade interaction targets.

### PR 4D — Mobile shell
- configurable BottomNav shortcuts;
- MobileDrawer full IA;
- AppBar/title/notification alignment;
- ActionRegistry integration;
- safe-area/keyboard/overlay collision checks.

**Manual Preview checkpoint:** mandatory, reviewed at all target device widths before merge wave is considered complete.

---

## Epic 5 — Golden Flow: Dashboard

- replace local KpiCard with StatCard;
- SectionHeader / AlertPanel / ActionRow;
- mobile action-first hierarchy;
- desktop management density;
- no KPI calculation change.

**Manual Preview:** mandatory.

---

## Epic 6 — Golden Flow: Customers & Credit shell

### PR 6A — Customers collection
- ResponsiveCollection;
- direct phone/maps preserved;
- filters/state/pagination/infinite presentation standardized.

### PR 6B — Customer detail
- EntityHeader;
- status/credit context;
- responsive sections/tabs.

### PR 6C — Customer create/edit
- Field/FormSection/FormGrid;
- GPS/location and credit permission behavior preserved;
- mobile sticky action policy.

### PR 6D — Credit surfaces
- shared financial/risk/status patterns;
- no credit-rule change.

**Manual Preview:** mandatory after Customers, before Sales migration expands blast radius.

---

## Epic 7 — Golden Flow: Sales

### PR 7A — Sales list
- ResponsiveCollection;
- StatCard summary;
- ActionRegistry including Smart Transfer as secondary action.

### PR 7B — Sales order form presentation extraction
- approved AsyncCombobox;
- Field/FormSection;
- Stepper;
- ProductLineEditor presentation shell;
- stock/credit/discount warnings via AlertPanel/Status patterns.

Business calculations, stock reservation, pricing, credit checks and permissions remain untouched.

### PR 7C — Sales detail
- TransactionHeader;
- FinancialSummary;
- lifecycle/timeline/action hierarchy.

### PR 7D — Returns/shipping
- consume proven Sales transaction/master-data patterns.

**Manual Preview:** mandatory for list + create + detail across devices.

---

## Epic 8 — Products & Suppliers

- migrate master-data list/detail/form patterns;
- Product units use Field/FormSection and touch-safe checkbox/action patterns;
- Supplier tabs use shared Tabs;
- contacts/reminders use shared dialog/status/confirm patterns;
- replace native `window.confirm` in UI with ConfirmDialog without altering delete semantics.

---

## Epic 9 — Inventory

Order:
1. Transfers
2. Adjustments
3. Stock
4. Movements
5. Warehouses
6. Valuation

Key patterns:
- TransactionHeader;
- InventorySummary;
- QuantityField;
- approved product selector;
- ActionRegistry;
- ResponsiveCollection.

**Regression gate is strict:** no stock calculation, warehouse authorization or workflow-state changes.

**Manual Preview:** mandatory.

---

## Epic 10 — Procurement

Order:
1. Purchase invoice list
2. Purchase invoice lifecycle/form
3. Purchase returns

Reuse Sales V2 presentation infrastructure where contracts match, but **do not merge procurement business logic with sales logic**.

The large PurchaseInvoiceForm should be decomposed into presentation subcomponents while preserving the current lifecycle and calculations.

**Manual Preview:** mandatory.

---

## Epic 11 — Finance

Order:
1. Payments
2. Expenses
3. Vaults
4. Custody
5. Accounts/Journals/Ledger
6. Balance sheet
7. Approval rules

Key patterns:
- MoneyField;
- FinancialSummary;
- AlertPanel;
- ApprovalPanel;
- ResponsiveCollection;
- accounting table/report patterns.

**Critical rule:** no accounting posting, receipt confirmation, vault/custody routing or balance logic changes inside UI PRs.

**Manual Preview:** mandatory.

---

## Epic 12 — HR

### 12A — Employee/self-service collections and forms
- Entity/Profile shell;
- Tabs/sections;
- Request/approval patterns.

### 12B — Attendance check-in extraction
Preserve its mobile-first workflow. Extract reusable visual task patterns without changing GPS/tracking logic.

### 12C — Attendance admin
Dense tablet/desktop monitoring with mobile review support.

### 12D — Payroll/commissions/adjustments
Use financial HR patterns with strict permission/state regression checks.

**Manual Preview:** mandatory for attendance task + one admin flow.

---

## Epic 13 — Activities / Field Operations

- planning lists/forms first;
- targets/calls/activities details;
- Visit Execution last within the epic because it is a reliability-sensitive mobile/offline workflow.

Visit Execution changes are presentation extraction only:
- OperationalTaskScreen;
- SyncStatus;
- EvidenceStatus;
- StickyTaskAction;
- Tabs/sections.

IndexedDB, atomic operations, photo sync, conflict handling and GPS rules remain untouched.

**Manual Preview:** mandatory on real phone-size viewport and offline/sync visual states.

---

## Epic 14 — Work Management

Use the existing Work responsive behavior as a reference rather than replacing it blindly.

- move shared panel/metric/form/action patterns into V2 where generally reusable;
- retain work-specific WorkItemCard/badges/state vocabulary in the feature domain;
- converge `work.css` with shared foundations gradually.

**Critical rule:** no Work state-machine, assignment, due-governance or approval semantics change.

---

## Epic 15 — Reports / Analytics

- ReportShell;
- ReportNav replacing oversized ad-hoc horizontal tab implementation;
- ReportFilterBar;
- MetricGrid;
- ChartPanel;
- shared table overflow/drilldown patterns;
- mobile summary/review rather than squeezed desktop dashboards.

Preserve analytics calculations and permission gates.

---

## Epic 16 — Settings / Admin / Notifications

- Users and roles;
- PermissionMatrix;
- company settings;
- audit log;
- notification Tabs/Feed/Preferences;
- shared admin form/list patterns.

Role permission keys and authorization semantics are immutable within UI migration.

---

## Epic 17 — Legacy cleanup

Only after all consumers are migrated:
- remove unused page-local visual helpers;
- remove deprecated CSS classes/selectors;
- remove obsolete modal/FAB implementations;
- eliminate broad semantic-by-guessing responsive CSS;
- keep compatibility only where still consumed.

Repository search and tests must prove each removal is safe.

---

## Epic 18 — Manufacturing readiness check

Before integrating the Manufacturing Domain:
- confirm V2 has patterns for production order list/detail/form;
- BOM/formula editing;
- batch/lot status;
- inventory consumption/receipt summaries;
- QC status/hold/release;
- manufacturing mobile task surfaces where needed.

Manufacturing must enter as a consumer of Edara V2—not as a visually separate application.
