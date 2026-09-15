# 11 — Golden Flow Acceptance

The first implementation proof must validate the Design System across real operational workflows, not isolated components.

## Device validation set
Minimum visual/interaction QA widths:
- phone compact: 360–390px
- phone large: 430px
- tablet portrait: ~768/834px
- tablet landscape: ~1024px
- desktop: 1280px
- wide desktop: 1440px+

Exact CSS breakpoints remain implementation decisions; these widths are acceptance evidence points.

## Flow A — App Shell & Navigation
### Mobile
- BottomNav exposes a small role-relevant high-frequency set.
- Full route tree remains reachable through the menu/drawer.
- No FAB or sticky action overlaps BottomNav, safe area or modal/sheet.
- Notification, title and navigation remain usable one-handed where practical.

### Tablet
- Do not show the 260px desktop sidebar by default merely because width exceeds 768px.
- Use a deliberate compact/collapsible navigation mode appropriate to portrait/landscape.
- Touch targets remain mobile-grade.

### Desktop
- Grouped sidebar supports the full IA with clear hierarchy.
- Navigation model is permission-aware but presentation is separate from permission logic.
- Content width and gutters remain coherent when navigation expands/collapses.

## Flow B — Dashboard
### Mobile
- Action/exception content appears before decorative analytics.
- KPIs remain readable without tiny labels or compressed cards.
- No essential information depends on hover.
- Alerts expose an obvious next action when a destination exists.

### Tablet
- Use available space for a denser but touch-friendly grid.
- Avoid simply stretching the mobile stack or shrinking desktop cards.

### Desktop
- Management metrics, exceptions and trends can use higher density.
- `StatCard`, `SectionHeader`, `AlertPanel` and `ActionRow` are shared system patterns rather than dashboard-local variants.

## Flow C — Customers List & Detail
### Mobile
- Customer list remains card-based, not a compressed table.
- Name, code, state, credit context and the most useful operational metadata are prioritized.
- Call and map actions remain immediately reachable when data exists.
- Infinite loading, end state, empty state and filtering are consistent system states.
- Customer detail actions do not require horizontal scrolling.

### Tablet
- Evaluate card grid versus compact table/master-detail based on usable width.
- Customer detail can use two-pane composition only when touch targets and reading order remain clear.

### Desktop
- Table preserves dense comparative data, sorting/filter context and pagination.
- Actions are predictable and use the same semantic hierarchy as mobile.

## Flow D — Customer Create/Edit
### Mobile
- Default to one logical column.
- Sections are chunked into understandable groups.
- Numeric/phone/email fields use appropriate keyboard/input modes.
- GPS capture and permission feedback are obvious and touch-friendly.
- Save action remains clear without covering content.
- Branch/contact creation defaults are understandable without creating a visually overwhelming first screen.

### Tablet/Desktop
- Two/three-column forms are allowed only for related fields and only when reading order remains obvious.
- Credit-sensitive inputs visibly reflect permission/read-only state.

## Flow E — Sales Orders List
### Mobile
- Preserve card + infinite-scroll workflow.
- Customer, order number, status, amount and outstanding balance are prioritized.
- Call/map actions remain available without opening the order when useful.
- There is exactly one coordinated primary floating/sticky action surface.
- Smart Transfer becomes a declared secondary action rather than an independently positioned FAB.

### Tablet/Desktop
- Dense table remains available with payment progress and status clarity.
- KPI summary is built from shared metrics rather than page-specific KPI markup.

## Flow F — Sales Order Create/Edit
### Mobile
- Preserve the multi-step operational workflow.
- Stepper is readable at phone widths and does not rely on tiny targets.
- Product search/add uses a bottom-sheet pattern optimized for thumb reach.
- Product line fields use system Field components and numeric input conventions.
- Stock warnings, credit warnings and price/discount permission states are visually semantic and never color-only.
- Previous/Next/Save actions are stable and easy to reach.

### Tablet
- Product editing may use additional columns, but the flow remains step-based unless runtime testing proves a different layout materially improves use.

### Desktop
- Use available width for product-line editing and order context without creating a separate workflow from mobile.

## Cross-flow mandatory states
Every golden flow must be reviewed for:
- loading
- empty
- error
- permission-restricted/read-only
- validation error
- long Arabic content
- large monetary/quantity values
- dark mode
- RTL mixed with LTR codes/phone/SKU/numbers
- keyboard focus where relevant
- safe mobile touch targets

## Acceptance rule
A Golden Flow is not accepted because one desktop screenshot looks polished. It is accepted only when the same business capability has a coherent Mobile, Tablet and Desktop composition and no business/permission regression is introduced.
