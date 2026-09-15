# 15 — Control & Form Contracts

These contracts govern every button, field, selector, badge, dialog, stepper and evidence-upload control migrated to Design System V2. The objective is consistent interaction without changing domain rules.

## 1. Button

### Semantic variants
- `primary` — the main forward action in the current context.
- `secondary` — supporting action of meaningful but lower priority.
- `ghost` — low-emphasis utility/navigation action.
- `danger` — destructive or materially reversing action only.
- `success` — explicit positive completion/accept/receive/confirm action when this semantic distinction is operationally useful.

Do not pick a color because a module historically uses it. Variant is determined by action meaning.

### Hierarchy rules
- Prefer one visually dominant primary action per local action area.
- Multiple primary buttons beside each other require an explicit workflow reason.
- Destructive actions are separated from routine actions when possible.
- `warning` content does **not** automatically imply a danger button. A warning confirmation may still have a primary/secondary confirm action if the operation is not destructive.

### Size / touch contract
Desktop visual density may use `sm`, `md`, `lg`, but on touch surfaces the interactive hit area remains at least 44px even when the visible icon/text is compact.

- compact desktop: visual 32–36px allowed
- standard: ~40–44px
- touch/mobile operational: minimum 44px hit area
- large primary mobile task action: 48px+ or purpose-built task control

### States
Every button defines:
- default
- hover where hover exists
- focus-visible
- active/pressed
- loading
- disabled

Loading retains the action width when practical to avoid layout shift.

### Icon-only buttons
- accessible label/title is mandatory;
- icon-only destructive action requires confirm/undo according to business consequence;
- small icon does not mean small hit target.

## 2. Field

`Field` becomes the common wrapper. Native/input primitives remain reusable internals.

### Standard anatomy
1. label
2. required/optional/read-only indication when relevant
3. control
4. hint/help text
5. validation/error message
6. optional unit/prefix/suffix

### Required states
- default
- focused
- filled
- disabled
- read-only
- error
- warning where the value is accepted but deserves attention
- loading/lookup where applicable

### Accessibility
- label is programmatically associated with the control;
- hint/error uses unique ids and `aria-describedby`;
- required is programmatically represented;
- error is not communicated only by border color.

### Mobile
- all operational fields use 44px minimum interaction height;
- keyboard/inputMode is chosen deliberately;
- form controls do not trigger accidental browser zoom from tiny text;
- sticky actions must not cover the active field or validation message.

## 3. Specialized fields

### MoneyField
- numeric entry with clear currency context;
- tabular digits;
- domain precision remains unchanged;
- formatting must not mutate the underlying accounting rule.

### QuantityField
- unit displayed or selected adjacent to the value;
- supports available/required quantity context;
- stock warnings use semantic warning/danger state plus text.

### PercentageField
- explicit `%` affordance;
- permission/read-only state clearly visible for protected discounts/rates.

### PhoneField
- `inputMode=tel`;
- LTR number rendering inside RTL form;
- optional call action is separate from edit control.

### Date / DateTime
- readable Arabic label/context with LTR/native date input where needed;
- display formatting and storage semantics stay separate.

### SearchField
- clear affordance with 44px touch target on mobile;
- Escape/clear behavior where appropriate;
- loading state for remote search.

## 4. Select / Combobox / AsyncCombobox

### Approved strategy
- native `Select` for small stable option sets;
- `AsyncCombobox` for large/remote searchable entities;
- retire page-local customer/product/supplier combobox implementations after parity is proven.

### Desktop
Searchable combobox uses anchored popover/listbox.

### Mobile
Searchable combobox uses a bottom sheet/full-width selection surface with keyboard-friendly search.

### Keyboard / accessibility requirements
- ArrowDown/ArrowUp move active option;
- Enter selects;
- Escape closes;
- active option is reflected with `aria-activedescendant` or equivalent robust combobox pattern;
- clear is a real accessible button, not a pseudo-button nested inside another button;
- focus returns to trigger after closing;
- unique listbox/dialog ids.

### Result rows
Support primary label, secondary metadata and optional code/state. Product/customer lookup should not create a new row style per module.

## 5. Checkbox / Radio / Switch

- minimum 44px touchable label/control area on mobile;
- label click toggles control;
- `Switch` is for immediate binary setting/state, not a replacement for every boolean form value;
- important financial/permission booleans include explanatory text where consequence is non-obvious.

## 6. Badge and StatusBadge

### Badge
Generic low-level visual label.

### StatusBadge
Maps domain status to semantic presentation:
- neutral
- info
- success
- warning
- danger

Domain values remain unchanged. Example: `pending`, `draft`, `in_transit`, `confirmed`, `overdue` remain business statuses; V2 only maps their visual treatment.

### Rules
- color never carries the status alone;
- label is always present;
- icon may reinforce meaning;
- statuses must use a central mapping per domain instead of inline hex colors.

## 7. StatCard / Metric

Standard anatomy:
- label
- value
- optional supporting context/trend
- optional next action
- optional semantic emphasis

Raw arbitrary color props from pages are deprecated. Emphasis uses semantic meaning.

Mobile dashboard cards must not reduce labels/values below readable size simply to preserve a desktop grid.

## 8. AlertPanel

Variants: info / success / warning / danger.

An AlertPanel has:
- icon
- optional title
- body
- optional next action

Use for operational warnings such as stock, credit, overpayment, GPS, upload/sync and permission context. Replaces local `AlertBanner` variants after parity.

## 9. Modal / ResponsiveModal / Sheet

### Desktop
Centered dialog with constrained width/height.

### Mobile
Bottom sheet or full-screen task surface depending content complexity.

### Required behavior
- unique title/description ids;
- focus trap while modal is active;
- Escape behavior when safe;
- focus restored to trigger/meaningful element after close;
- background interaction blocked;
- safe-area padding;
- sticky footer only when it improves completion and does not hide content;
- unsaved-data close policy explicitly supported.

A large multi-section form should not be forced into a tiny bottom sheet merely because a ResponsiveModal exists.

## 10. ConfirmDialog

Confirmation tone and action consequence are separate concepts.

Examples:
- delete/cancel irreversible → danger confirm
- receive/approve → success/primary confirm
- informational acknowledgement → primary/secondary confirm
- warning about a non-destructive consequence → warning content but not automatically danger action

Buttons use stable order across the product. Loading disables repeat submission.

## 11. Stepper

Current shared Stepper is retained/evolved.

### Contract
- current / completed / upcoming semantics;
- labels remain understandable at phone width;
- descriptions appear only where space allows;
- status is not color-only;
- step circles themselves are not falsely interactive unless navigation is actually permitted;
- multi-step business transition logic remains in the domain page, not Stepper.

### Mobile
For 4+ steps, prioritize current step and progress clarity over squeezing long labels into equal narrow columns. Horizontal/compact alternatives may be used after runtime testing.

## 12. Proof / Evidence Upload

Preserve the useful device behavior:
- mobile: camera / gallery / supported file choice
- desktop: normal file picker

### V2 requirements
- 44px touch targets;
- file size/type errors render through system validation/toast, not blocking `alert()`;
- preview lifecycle does not leak object URLs;
- selected file state shows name, size, type/preview and remove/replace action;
- required evidence is programmatically and visually explicit;
- upload/sync state is distinct from local-selection state;
- offline workflows may expose local/sync status without changing their underlying sync logic.

## 13. DataCard

Mobile operational collection item.

### Anatomy
- primary identity
- secondary identity/context
- StatusBadge
- prioritized metadata
- optional direct actions
- optional navigation affordance

### Accessibility
Do not make a container with `role=button` contain nested buttons. Prefer a real detail link/overlay navigation target plus independent action buttons, or another valid non-nested interaction structure.

Keyboard activation supports standard link/button semantics rather than custom Enter-only behavior.

## 14. DataTable

Desktop/tablet dense comparison surface.

- visible column hierarchy;
- numeric columns aligned/readable with tabular digits;
- sortable/filterable states clear;
- sticky headers only when useful;
- pagination standardized;
- mobile does not receive a squeezed wide table by default.

Device orchestration belongs to `ResponsiveCollection`.

## 15. FilterBar

The current compound behavior is preserved while implementation is decomposed.

Sub-parts:
- FilterSearch
- FilterSelect / AsyncFilterSelect
- DateRangeFilter
- FilterToggle
- FilterStats
- MobileFilterSheet
- ClearFiltersAction

Mobile clear/filter/toggle actions obey 44px touch targets. No nested interactive elements. Expansion ids are unique.

## 16. Page / Section / Entity / Transaction headers

### PageHeader
Page purpose + optional subtitle/context + page-level actions.

### EntityHeader
Identity + status + core metadata + actions.

### TransactionHeader
Transaction number/status + parties/context + amount/quantity summary + lifecycle actions.

### SectionHeader
Section title/icon/help + optional local action.

Device-specific action placement is handled through ActionRegistry rather than hiding duplicated buttons with local CSS.

## 17. ActionRegistry / ActionSlot

Pages declare actions, not floating-button geometry.

Minimum declaration:
- stable action id
- label/icon
- semantic priority
- disabled/loading
- handler/navigation target
- optional device preference

Existing permission logic remains where it already lives; V2 does not redefine authorization.

Renderer examples:
- desktop → PageHeader/toolbar
- tablet → toolbar + overflow
- mobile → single primary FAB/sticky action + secondary overflow

There must be no independent overlapping FAB systems.

## 18. State components

Every collection/form/task pattern uses the same state vocabulary:
- LoadingState / Skeleton
- EmptyState
- ErrorState
- PermissionState
- OfflineState where relevant
- SyncState where relevant
- Success feedback

State components must communicate what happened and, where possible, the next safe action.

## Enforcement
A migrated screen fails Design System V2 review if it introduces a local replacement for an approved primitive/pattern without documenting a real missing capability.
