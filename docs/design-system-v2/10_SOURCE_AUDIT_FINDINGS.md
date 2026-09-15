# 10 — Source-Backed UI Findings

This document records concrete findings from the current Edara source. It is evidence for Design System V2 decisions, not permission to change business behavior.

## Evidence sampled
- App shell: `AppLayout`, `Sidebar`, `BottomNav`, `FAB`
- Core UI: `Button`, `Input`, `Select`, `Badge`, `ResponsiveModal`, `DataCard`
- Shared patterns: `PageHeader`, `DataTable`, `FilterBar`
- Golden flows: Dashboard, Customers list/form, Sales Orders list/form
- Global styling: `tokens.css`, `components.css`

## P1 — Tablet is currently a breakpoint gap
The shell is effectively binary: mobile at `<=768px`, desktop above it. The desktop shell reserves the full sidebar width while the sidebar becomes a drawer only under 768px. This means tablet/intermediate widths do not have a deliberately designed shell.

V2 decision: introduce an explicit tablet/intermediate behavior. Do not treat 769–1024/1180 widths as small desktop by default. Validate portrait and landscape tablet separately.

## P1 — Mobile touch-target intent is not consistently enforced
The token layer defines a 44px touch target, but several current controls are smaller: small/icon buttons, pagination buttons, FilterBar clear buttons and mobile filter controls. Some mobile CSS also shrinks controls further on very small screens.

V2 decision: operational mobile actions must meet a practical 44px target. Visual icon size may remain small while the hit area stays large.

## P1 — Responsive collection behavior is good but duplicated
Customers and Sales already use the right conceptual model:
- desktop: table + numbered pagination
- mobile: prioritized cards + infinite loading + direct field actions

However each page independently reimplements loading skeletons, empty states, mobile wrappers, sentinel/end states and desktop/mobile split CSS. `DataTable` already contains a partial `dataCardMapping` path, but these pages bypass it and maintain two separate collection presentations.

There is also a performance concern: the desktop and mobile queries are both declared in the same mounted page, so viewport-specific rendering does not inherently prevent both query paths from running. This is a frontend performance issue to address separately with regression evidence; it must not be mixed into a purely visual PR.

V2 decision: create a shared `ResponsiveCollection` pattern that owns presentation/state behavior while allowing the data layer to remain behavior-preserving until a separately tested performance change is approved.

## P1 — Floating actions are not centrally orchestrated
The App Shell has a route-aware global FAB. Sales Orders also adds a page-local Smart Transfer FAB, and comments in the global FAB acknowledge more page-local exceptions.

V2 decision: introduce one action-surface contract/registry. A screen declares primary, secondary and overflow actions; the shell decides whether they render as desktop toolbar buttons, mobile FAB, sticky action or overflow item. There must not be competing floating buttons with independent positioning rules.

## P1 — Design-system adoption is incomplete in critical forms
Shared `Input`, `Select` and `AsyncCombobox` primitives exist, but high-value forms such as Sales Order and Customer management frequently use raw `form-input/form-select`, local labels, local buttons and custom controls. Sales Order also defines its own Combobox, stepper, section headings, product-line editing UI and review summaries.

This is a primary cause of visual inconsistency: the shared components exist but critical workflows are not composed from them.

V2 decision: preserve the workflow and business rules, but extract presentation into shared form patterns: `Field`, `FormSection`, `Combobox`, `Stepper`, `StickyFormActions`, `ProductLineEditor` presentation shell and `ReviewSummary` patterns.

## P1 — Accessibility debt exists in otherwise useful shared components
### DataCard
A clickable `article` is given `role=button` and `tabIndex=0`, while its action area may contain real buttons. Nested interactive semantics should be avoided. Keyboard activation currently handles Enter but not Space.

### ResponsiveModal
It focuses the dialog and supports Escape/body lock, but source inspection does not show a full focus trap or explicit focus restoration to the trigger. A static `rmodal-title` id is also reused.

### FilterBar
The header is a `div role=button` that can contain a real reset button. Several clear affordances are far below the 44px touch target. The body id is static. These should be corrected without changing filter semantics.

V2 decision: accessibility behavior is part of component contracts, not a later polish phase.

## P1 — Sidebar is both IA and presentation implementation
`Sidebar.tsx` combines route grouping, permissions, expansion state, user/footer actions, theme behavior and a large local CSS block. It also defines its own hard-coded light/dark palette despite existing sidebar/theme tokens.

V2 decision: separate navigation model from rendering. Permission resolution stays unchanged; V2 introduces a navigation configuration/model consumed by DesktopSidebar, TabletNavigation and MobileDrawer renderers using semantic tokens.

## P2 — Styling is fragmented across global CSS and page-local style blocks
Dashboard, AppLayout, Sidebar, ResponsiveModal, FilterBar, Customers and Sales all contain substantial local/inline styling while `components.css` also defines related global patterns. This makes the cascade difficult to reason about and encourages local visual exceptions.

V2 layering target:
1. foundations/tokens
2. primitive component styles
3. shared pattern styles
4. domain composition
5. minimal page-local exceptions

## P2 — Global mobile selectors are too broad
`components.css` contains responsive rules that target generic utility combinations such as `.flex.gap-2/.gap-3/.gap-4` and selectors based on inline-style text such as `.edara-card[style*="padding"]`. These rules can change unrelated components unintentionally.

V2 decision: responsive behavior belongs to named components/patterns. Avoid global selectors that infer semantics from generic utility classes or inline-style strings.

## P2 — Dashboard duplicates concepts that already belong in the system
Dashboard defines local `KpiCard` and `SectionHead` components and many direct visual values while the global stylesheet already has stat-card concepts.

V2 decision: consolidate Dashboard onto shared `StatCard`, `SectionHeader`, `AlertPanel` and `ActionRow` patterns. Mobile Dashboard should be action-first; desktop may expose more analytics density.

## P2 — PageHeader needs a stronger device contract
The current PageHeader is a useful base, but title/subtitle are always single-line ellipsis and actions rely on page-specific classes such as `desktop-only-btn` when mobile actions move elsewhere.

V2 decision: PageHeader should own responsive title/action policy and integrate with the shared action registry rather than relying on page-specific hiding.

## What should NOT be rewritten
- Existing business flows and permission checks
- URL-synced filter state behavior
- Mobile direct actions such as call/maps where they are operationally useful
- Infinite-scroll behavior where it is the accepted mobile workflow
- Current light/dark capability
- Existing semantic concepts already represented by tokens

The refactor should consolidate the implementation around these strengths rather than replace them blindly.
