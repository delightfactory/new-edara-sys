# 03 — Component System

## Layer 1: primitives
Owned by the design system and domain-agnostic:
- Button / IconButton
- Input / Textarea
- Select / Combobox / AsyncCombobox
- Checkbox / Radio / Switch
- Badge / Avatar
- Tooltip / Popover / DropdownMenu
- Modal / ResponsiveSheet / ConfirmDialog
- Spinner / Skeleton / Divider

## Layer 2: form composites
- Field
- MoneyField
- QuantityField
- PercentageField
- DateField / DateTimeField
- SearchField
- FormSection
- InlineValidation
- StickyFormActions

All form composites standardize label, help, validation, required state, read-only state and spacing.

## Layer 3: data display and application patterns
- DataTable
- MobileDataCard
- Pagination
- FilterBar
- StatusBadge
- StatCard / Metric
- KeyValueList
- Timeline / ActivityFeed
- EmptyState / ErrorState / PermissionState / LoadingState
- EntityHeader
- TransactionHeader
- FinancialSummary
- InventorySummary
- ApprovalPanel
- AuditTimeline
- BulkActionBar / CommandBar

## Layer 4: domain components
Sales, credit, HR, inventory, finance, visits, work-management etc. may compose shared components but must not duplicate primitives.

## Migration rules
1. Existing components are audited before replacement.
2. A component that already has a sound contract is evolved in place.
3. Overloaded shared components are decomposed instead of receiving more boolean props.
4. New page-local primitives are prohibited when a system primitive exists.
5. Business rules remain outside visual primitives.
6. Variants are semantic (`primary`, `destructive`, `warning`) rather than page-specific (`salesBlue`, `hrGreen`).

## First component priorities
1. Button/action hierarchy
2. Field system
3. StatusBadge semantics
4. Card/Section/StatCard
5. Dialog/ResponsiveSheet/ConfirmDialog
6. DataTable + MobileDataCard
7. FilterBar decomposition
8. PageHeader / EntityHeader / TransactionHeader
9. Loading/empty/error/permission states
10. Timeline/audit patterns
