# 16 — Current Component Inventory & Gaps

This inventory is grounded in the current `main` source. It distinguishes what already exists from what Design System V2 must formalize or consolidate.

## A. Current core UI (`src/components/ui`)

| Component | Current role | V2 decision | Primary gap |
|---|---|---|---|
| `Button` | Shared action primitive | Evolve | semantic hierarchy + touch hit-area enforcement + consistent icon-only behavior |
| `Input` | Shared text input wrapper | Evolve under Field | adoption is low in critical forms; missing full field anatomy |
| `Select` | Shared native select wrapper | Evolve under Field | same adoption/validation/accessibility standardization gap |
| `Badge` | Generic badge | Retain + add StatusBadge | domain statuses often reimplement maps/colors locally |
| `AsyncCombobox` | Remote searchable selector; mobile sheet / desktop dropdown | Evolve | full keyboard navigation, clear-button semantics, focus return, approved row patterns |
| `Modal` | Legacy/basic modal | Audit consumers | overlaps with ResponsiveModal; should not survive as parallel modal language without a justified use case |
| `ResponsiveModal` | Desktop dialog / mobile bottom sheet | Evolve as main dialog primitive | focus trap/restore, unique ids, full-screen-task variant, footer conventions |
| `ConfirmDialog` | Confirmation surface | Evolve | separate warning tone from destructive action semantics |
| `DataCard` | Mobile collection card | Evolve | nested-interactive semantics, standardized metadata/action/navigation structure |
| `ProofUploadButton` | Camera/gallery/file evidence control | Evolve | 44px targets, non-blocking validation, preview lifecycle, local-vs-uploaded state |
| `Skeleton` | Loading primitive | Retain/Evolve | need system-level collection/form state compositions |
| `Spinner` | Loading indicator | Retain | integrate into Button/State contracts consistently |
| `Stepper` | Multi-step visual indicator | Evolve | compact phone strategy, accessibility/state semantics, broad adoption |

### Core conclusion
The current core library is useful but too narrow for the application size. It contains solid foundations for actions, input, modal, async selection, mobile cards and progress; it does **not** yet cover the full application grammar.

---

## B. Current shared/application patterns (`src/components/shared` and feature components)

Confirmed source includes patterns such as:
- `PageHeader`
- `DataTable`
- `FilterBar`
- `EmptyState`
- `DetailRow`
- `EntityLink`
- `ErrorBoundary`
- `ActivityStatusBadge`
- `ActivityTimeline`
- `ChecklistForm`
- `CustomerCreditChip`
- `CustomerSearchCard`
- GPS / geolocation status and permission components
- feature-level Work components (`WorkItemCard`, `WorkBadges`)

These are valuable, but the repository does not formally distinguish:
1. generic design primitives;
2. reusable application patterns;
3. domain-specific components.

V2 must establish that ownership boundary so a domain component does not accidentally become a universal UI primitive.

---

## C. Missing or informal primitives that should become formal V2 components

### Input / control layer
- `Textarea`
- `Checkbox`
- `RadioGroup`
- `Switch`
- `IconButton` as an explicit contract rather than Button inference alone
- `Tooltip`
- `Popover`
- `DropdownMenu`
- `Tabs`
- `SegmentedControl`
- `SubNav`
- `Divider`
- `Avatar` / identity primitive where useful

### Form layer
- `Field`
- `MoneyField`
- `QuantityField`
- `PercentageField`
- `PhoneField`
- `DateField`
- `DateTimeField`
- `SearchField`
- `FormSection`
- `FormGrid`
- `StickyFormActions`
- `InlineValidation`

### Surface / hierarchy layer
- `Card`
- `Section`
- `Panel`
- `StatCard`
- `Metric`
- `SectionHeader`
- `EntityHeader`
- `TransactionHeader`
- `KeyValueList`
- `FinancialSummary`
- `InventorySummary`

### Status / feedback layer
- `StatusBadge`
- `AlertPanel`
- `LoadingState`
- `ErrorState`
- `PermissionState`
- `OfflineState`
- `SyncState`
- standardized success/completion feedback

### Collection / navigation layer
- `ResponsiveCollection`
- `Pagination`
- `InfiniteListState`
- `BulkActionBar`
- `CommandBar`
- `ActionRegistry` / `ActionSlot`
- `DesktopSidebar`
- `TabletNavigation`
- `MobileDrawer`
- configurable `BottomNav`

### Complex reusable application patterns
- `ApprovalPanel` / `ApprovalQueue`
- `AuditTimeline`
- `PermissionMatrix`
- `OperationalTaskScreen`
- `ProcessProgress`
- `ConnectionStatus`
- `SyncStatus`
- `StickyTaskAction`
- `EvidenceStatus`
- `ProductLineEditor` presentation shell
- `ReviewSummary`
- `ReportShell`
- `ReportNav`
- `ReportFilterBar`
- `MetricGrid`
- `ChartPanel`

---

## D. Concepts currently repeated locally and therefore high-value consolidation targets

| Concept | Current repeated examples | V2 target |
|---|---|---|
| KPI card | Dashboard local KpiCard, Work summary cards, report metrics, filter stats | `StatCard` / `Metric` |
| Section heading | Dashboard SectionHead, Purchase SectionHead, Work section header, local h2 blocks | `SectionHeader` |
| Alert/banner | Finance AlertBanner, stock/credit/GPS/sync warnings | `AlertPanel` |
| Info summary card | Finance InfoCard, supplier summary chips, transaction review summaries | `KeyValueList` / `FinancialSummary` / `ReviewSummary` |
| Tabs/sub-nav | Suppliers tabs, Notifications tabs, Reports nav, Visit Execution tabs | `Tabs` / `SubNav` / `SegmentedControl` |
| Remote selector | Shared AsyncCombobox plus local Sales/Purchase/Inventory comboboxes | approved `AsyncCombobox` family |
| Multi-step flow | Shared Stepper plus Sales/Purchase local step displays | approved `Stepper` + page-owned workflow |
| Mobile list | Customers, Sales, Payments, Transfers and others | `ResponsiveCollection` + `DataCard` |
| Floating action | global FAB plus Sales/Payments/Transfers/other local FABs | `ActionRegistry` |
| Form section/grid | Product, Supplier, Customer, Sales, Purchase, Work-specific versions | `FormSection` / `FormGrid` |
| Sticky action bar | Work, Visit Execution, local mobile forms | `StickyFormActions` / `StickyTaskAction` |
| Permission selection | RoleForm local permission matrix | `PermissionMatrix` |
| Offline/sync state | Visit execution, PWA/offline components | `OfflineState` / `SyncState` pattern family |

---

## E. Ownership model for V2

### `components/ui`
Only domain-agnostic primitives and low-level composites. They must not know about customers, warehouses, credit, payroll, visits, etc.

### `components/patterns` (recommended new layer)
Reusable application patterns such as Field, ResponsiveCollection, EntityHeader, TransactionHeader, StatusBadge, AlertPanel, ActionRegistry renderers, PermissionMatrix and operational state surfaces.

### `features/<domain>/components`
Components with real domain vocabulary or business presentation: CustomerCreditChip, WorkItemCard, visit checklist/evidence structures, inventory-specific summaries, finance-specific transaction views.

### Pages
Pages orchestrate data, permissions and domain state and compose approved patterns. They should contain minimal visual-system implementation.

---

## F. Migration / compatibility policy

1. Do not rename/move the whole component tree in one PR.
2. Add V2 primitives/patterns with compatibility where practical.
3. Migrate Golden Flows first.
4. Only deprecate a legacy component after repository search proves its consumers have moved.
5. `Modal` vs `ResponsiveModal` must be resolved by consumer audit, not deletion by assumption.
6. Local components are retired only after the replacement has functional and device parity.
7. A component is not considered V2 merely because its colors changed; its interaction contract, states, RTL, accessibility and device behavior must pass the contracts in `15_CONTROL_AND_FORM_CONTRACTS.md`.

## G. Primary architectural goal
At the end of the refactor, adding a new Manufacturing screen should primarily involve composing existing V2 primitives and patterns—not creating a new visual language for manufacturing. That is the test that the Design System has become real product infrastructure.
