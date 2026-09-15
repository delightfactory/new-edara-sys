# 01 — Current UI Audit

## Evidence inspected
- `src/styles/tokens.css`
- `src/components/ui/*`
- `src/components/shared/*`
- `src/components/layout/*`
- `src/pages/*`
- `src/App.tsx`

## Confirmed strengths
- A real token layer already exists for color, typography, spacing, radius, shadows, transitions, z-index and mobile shell.
- Light/dark themes are tokenized.
- Touch target and responsive-shell concepts already exist.
- Shared primitives exist: Button, Input, Select, Badge, Modal, ResponsiveModal, ConfirmDialog, AsyncCombobox, DataCard, Skeleton, Spinner, Stepper and upload control.
- Shared higher-level components exist: DataTable, FilterBar, EmptyState, EntityLink, DetailRow, status components and timelines.
- The app already distinguishes desktop and mobile navigation with Sidebar, AppBar, BottomNav and FAB.

## Confirmed debt
### P1 — Navigation complexity
`src/components/layout/Sidebar.tsx` is a very large navigation/permission surface. It mixes information architecture, permission visibility, visual grouping, interaction state and presentation in one component. The current grouping has grown organically and is now too dense for the product size.

### P1 — Component responsibility growth
Some shared components are already large enough to signal over-responsibility. `FilterBar.tsx` and `AsyncCombobox.tsx`, for example, should be reviewed for smaller composable contracts rather than becoming universal components with many modes.

### P1 — Styling location inconsistency
`AppLayout.tsx` contains substantial inline `<style>` definitions while other styling lives in token/global/component layers. Design System V2 needs one explicit layering rule: tokens → primitives → patterns → page composition.

### P1 — Two component layers without a formal boundary
The repository has both `components/ui` and `components/shared`. That is reasonable, but the distinction is implicit. V2 must define:
- primitives (`ui`)
- composites/patterns (`shared` or a renamed patterns layer)
- domain components (feature/module-owned)

### P1 — Page grammar inconsistency risk
The page tree covers sales, customers, credit, purchases, inventory, finance, HR, activities, products, reports, work and settings. At this scale, independent page composition creates visible inconsistency even when individual controls are acceptable.

### P2 — Token semantics need a second layer
The existing token file is a strong starting point, but many roles still describe physical styling (`bg-surface`, `color-primary`) rather than product semantics. V2 should add semantic aliases for actions, status, financial values, risk, selection, focus and interactive states without breaking existing tokens during migration.

## Audit conclusion
Edara does not need a visual rewrite from zero. It needs consolidation: preserve the strong foundations, reduce one-off page composition, formalize component ownership, redesign navigation/information architecture, and migrate every module onto a shared page grammar.

## Runtime audit status
Static findings are code-grounded. Visual hierarchy, actual density, contrast, overflow and interaction feel still require a running-product screenshot audit before final visual decisions are frozen.
