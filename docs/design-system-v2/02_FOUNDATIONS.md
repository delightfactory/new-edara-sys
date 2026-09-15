# 02 — Design Foundations

## Typography
Use Cairo as the Arabic-first interface family unless runtime review reveals a legibility problem. Define roles rather than arbitrary sizes:
- page-title
- section-title
- card-title
- body
- body-strong
- label
- helper
- caption
- numeric-kpi
- numeric-tabular

Financial and quantity-heavy surfaces should use tabular numerals where supported.

## Color architecture
Keep the existing token layer for compatibility and add semantic aliases:
- surface/app, surface/default, surface/subtle, surface/elevated
- text/primary, text/secondary, text/muted, text/inverse
- border/default, border/subtle, border/strong
- action/primary, action/secondary, action/destructive
- status/neutral, info, success, warning, danger
- focus/ring, selection/background

Business statuses map to this small semantic vocabulary. A page must not invent a new color because a domain has a new status.

## Spacing and density
Retain the existing spacing scale as the base. Define intentional density by task and device rather than by module:
- comfortable: forms/details and touch-heavy surfaces
- standard: default application density
- compact: desktop/tablet high-volume tables and review queues

Mobile must never inherit compact desktop density simply because the same data is shown. Do not allow arbitrary per-page spacing systems.

## Shape and elevation
Use a constrained radius/elevation scale. Borders and surface contrast carry hierarchy first; shadows are secondary.

## Interaction states
Every interactive primitive must specify default, hover, focus-visible, active, disabled and loading. Fields additionally specify error, warning and read-only states. Hover may enhance desktop UX but must never be required to discover or execute an action.

## RTL
RTL is foundational. Verify directional icons, chevrons, timeline direction, table alignment, mixed Arabic/Latin content, phone numbers, codes, dates and monetary values.

## Device strategy
Edara is intentionally multi-device:
- **Mobile**: primary operational surface for frequent daily actions, field work, quick sales/customer activity, attendance, visits, approvals and transaction capture where permissions allow.
- **Tablet**: hybrid operational/management surface; touch-first but able to carry more context, split layouts and denser data.
- **Desktop**: management/review surface for dense tables, reporting, reconciliation, setup and complex multi-record work.

This is adaptive design, not one desktop layout scaled down.

## Responsive tiers
Components own responsive behavior. Pages compose it. Default tiers:
- mobile ≤ 768px
- tablet/intermediate
- desktop management layout
Avoid module-specific breakpoints unless a real content constraint requires them.

Patterns may transform across tiers while preserving task meaning. Examples: table → data cards, filter toolbar → filter sheet, side action panel → sticky action footer, multi-column form → single-column flow.

## Mobile operational baseline
- minimum practical touch target uses the existing 44px token; critical high-frequency actions may require larger targets
- respect safe-area insets
- avoid hover-only affordances
- primary action stays reachable without excessive scrolling where appropriate
- destructive actions require explicit separation/confirmation
- long lists must remain performant and scannable
- use appropriate mobile keyboard/input modes for phone, numeric, money, quantity and search fields
- camera/file upload, geolocation and connectivity states must be designed where the workflow depends on them
- avoid horizontal scrolling as a normal list/detail interaction

## Accessibility baseline
- visible focus
- labels and accessible names
- status not conveyed by color alone
- adequate touch targets
- sufficient contrast
- keyboard-operable dialogs/menus/selects
- logical focus return after modal/sheet close
- reduced-motion behavior where animation is non-essential
