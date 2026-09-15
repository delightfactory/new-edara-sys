# 32 — Design System V2 North Star

## Why this workstream exists

The goal is not to make EDARA merely look newer.

The goal is to turn EDARA into a coherent, premium, Arabic-first operational product whose interface feels intentionally designed as one system across every module, device, state and role.

The completed result should be credible beside high-quality modern enterprise software while remaining faster, clearer and more practical for the real daily work of distribution, sales, inventory, finance, HR and field teams.

Every Design System agent must judge its work against this end state, not only against the immediate file or ticket.

## Product identity

EDARA should feel:

- operational, not decorative
- modern and premium, not trendy for its own sake
- calm and trustworthy around money, inventory, credit and approvals
- fast and action-oriented on Mobile
- dense but legible on Desktop
- deliberately balanced on Tablet
- Arabic-first and RTL-native, never an LTR product mirrored at the end
- consistent enough that users can predict how a new screen behaves before learning it

The visual language should communicate hierarchy through typography, spacing, surface, semantic tone and action priority rather than excessive color or ornament.

## Core experience principles

### 1. Action clarity

Every screen answers:

- Where am I?
- What is the important state?
- What should I do next?
- What is secondary?
- What is dangerous or irreversible?

Primary, secondary, destructive and overflow actions must never compete visually.

### 2. Semantic consistency

The same meaning must look and behave the same everywhere.

Examples:

- success/warning/danger/info
- active/inactive
- approved/pending/rejected
- money/quantity/percentage/date
- loading/empty/error/offline/sync
- primary/secondary/destructive actions

No module may invent its own color language for an existing meaning.

### 3. Progressive disclosure

Operational users should see what is required for the current task first. Advanced information and low-frequency controls appear when needed, not all at once.

### 4. Responsive composition, not responsive shrinking

The same business capability may use different compositions by device:

- Desktop table -> Mobile operational card list
- filter toolbar -> Mobile filter sheet
- centered modal -> Mobile bottom sheet
- dense multi-column form -> grouped single-column task form
- multi-action command area -> primary action + overflow

Business meaning, permissions and available capability must remain equivalent.

### 5. Strong hierarchy

Every page must have an obvious hierarchy:

Page -> section -> group -> field/data -> action -> supporting detail.

Avoid card walls where every object has equal visual weight.

### 6. State completeness

A component or screen is not complete if only the happy state is designed.

Where relevant, explicitly cover:

- loading
- initial empty
- filtered empty
- error
- offline
- syncing
- disabled
- read-only
- permission-limited
- long Arabic content
- large currency values
- partial data
- destructive confirmation

### 7. Accessibility as interaction quality

Accessibility is part of product quality:

- keyboard and focus behavior
- meaningful labels
- non-color-only status meaning
- touch targets
- readable contrast
- reduced motion
- screen-reader-compatible control semantics where applicable

## Device identity

### Mobile — primary operational surface

Many daily EDARA users work from Mobile.

Mobile design optimizes for:

- rapid task completion
- one-hand reach where practical
- one clear primary action
- short scanning distance
- touch-safe controls
- camera/upload/GPS/phone actions when relevant
- safe-area awareness
- no ordinary horizontal scrolling
- minimal modal nesting

Mobile is not a reduced Desktop experience.

### Tablet — hybrid operational/management surface

Tablet must deliberately balance touch and information density.

It must not inherit a fixed Desktop sidebar or simply enlarge a Mobile screen.

### Desktop — dense management surface

Desktop optimizes for:

- cross-record comparison
- tables and dense lists
- reporting
- review/approval
- management workflows
- efficient keyboard/mouse navigation

## Full-system coverage requirement

Design System V2 is not finished after Dashboard, Customers and Sales.

The system must eventually define and migrate the full interface grammar, including at minimum:

### Foundations
- Arabic typography roles
- semantic colors
- spacing
- radius
- elevation
- motion
- density
- focus
- dark mode
- RTL behavior
- device breakpoints

### Shell and navigation
- Sidebar
- App Bar
- Bottom Navigation
- contextual create action
- page title/context
- module/sub navigation
- notification entry points
- responsive drawers

### Actions
- Button
- IconButton
- split/overflow actions when needed
- command/action bars
- sticky mobile actions
- destructive confirmation

### Forms
- Field
- Input
- Textarea
- Select
- Combobox/AsyncCombobox
- Checkbox/Radio/Switch
- Money/Quantity/Percentage fields
- Date/DateTime fields
- phone/email/numeric input behavior
- help/error/read-only/required states
- FormSection/FormGrid/FormActions
- long forms and stepped flows

### Collections and data
- DataTable
- MobileDataCard
- ResponsiveCollection
- pagination
- infinite loading where intentionally retained
- filtering/search
- sorting where present
- bulk selection/action where present
- empty/error/loading states

### Information surfaces
- Card
- SectionHeader
- StatCard
- KeyValueList
- status badges
- financial summaries
- inventory summaries
- credit indicators
- timelines/audit history
- approval panels

### Navigation/content controls
- Tabs
- SubNav
- SegmentedControl
- breadcrumbs/back navigation

### Overlays and feedback
- Modal
- ResponsiveSheet/bottom sheet
- drawer
- ConfirmDialog
- toast
- alert
- tooltip/popover/dropdown

### Operational/device capabilities
- upload/proof attachment
- camera input
- GPS/location
- offline/sync states
- PWA install/update states
- call/map shortcuts

### Analytics/reports
- metric grids
- report navigation
- filter grammar
- charts and legends
- dense financial/report tables
- printable/readable management views

## Component quality bar

A shared component must have:

1. one clear responsibility
2. semantic variants instead of page-specific variants
3. documented responsive behavior
4. RTL-safe layout
5. keyboard/touch expectations
6. relevant states
7. long-content tolerance
8. no business/domain calculations inside visual primitives
9. stable enough API for reuse across modules
10. migration path from legacy usage

## Page migration quality bar

A migrated page must:

- use shared V2 language rather than create a local mini-design-system
- preserve all business behavior
- reduce unnecessary inline composition
- expose an obvious page/section/action hierarchy
- intentionally handle Mobile/Tablet/Desktop
- preserve role/permission visibility
- preserve important states
- avoid visual or interaction dead ends
- fit the same product identity as previously migrated screens

A page is not considered complete merely because it compiles or uses new components.

## Professional-polish review

The Design Architect and Quality Reviewer must actively look for:

- inconsistent padding and alignment
- awkward Arabic wrapping
- weak information hierarchy
- excessive borders/cards
- redundant labels
- inconsistent icon sizes
- conflicting actions
- unclear destructive actions
- tiny touch targets
- modal/sheet misuse
- noisy status colors
- horizontal overflow
- desktop density loss
- tablet layouts that feel accidental
- Mobile screens that feel like shrunken Desktop pages
- duplicate local implementations of an existing shared pattern

## Migration strategy

Prefer this progression:

1. strengthen shared primitive/pattern if required
2. migrate one representative screen
3. prove the pattern
4. reuse it in adjacent screens
5. remove legacy implementation only after no consumers remain

Do not redesign twenty pages independently and try to unify them afterward.

## Definition of Design System V2 completion

The workstream can be considered complete only when:

- shared foundations and component grammar cover the application's recurring UI needs
- all major modules have migrated to the common grammar
- Mobile, Tablet and Desktop experiences are deliberate
- legacy one-off patterns are materially reduced or removed
- status/action/form/list/dialog/navigation behavior is consistent across modules
- dark/RTL/responsive/state handling is coherent
- a final controlled runtime visual review passes on representative golden flows
- no Design System work has altered business truth

The target is one product language across EDARA, not a collection of individually improved pages.
