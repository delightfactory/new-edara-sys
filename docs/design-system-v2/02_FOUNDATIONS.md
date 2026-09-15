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
Retain the existing spacing scale as the base. Define three intentional density modes only when needed:
- comfortable: forms/details
- standard: default application density
- compact: high-volume tables/queues

Do not allow arbitrary per-page spacing systems.

## Shape and elevation
Use a constrained radius/elevation scale. Borders and surface contrast carry hierarchy first; shadows are secondary.

## Interaction states
Every interactive primitive must specify default, hover, focus-visible, active, disabled and loading. Fields additionally specify error, warning and read-only states.

## RTL
RTL is foundational. Verify directional icons, chevrons, timeline direction, table alignment, mixed Arabic/Latin content, phone numbers, codes, dates and monetary values.

## Responsive tiers
Components own responsive behavior. Pages compose it. Default tiers:
- mobile ≤ 768px
- tablet/intermediate
- desktop management layout
Avoid module-specific breakpoints unless a real content constraint requires them.

## Accessibility baseline
- visible focus
- labels and accessible names
- status not conveyed by color alone
- minimum practical touch target based on the existing 44px token
- sufficient contrast
- keyboard-operable dialogs/menus/selects
- logical focus return after modal/sheet close
