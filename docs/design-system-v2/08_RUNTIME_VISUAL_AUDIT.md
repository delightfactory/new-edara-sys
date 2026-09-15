# 08 — Runtime Visual Audit Plan

Static source inspection establishes architecture and reuse debt; it does not prove visual quality. Before the visual direction is frozen, capture the running product.

## Product usage assumption to validate
Edara is actively used on desktop, tablet and mobile, with mobile carrying a large share of daily operational work. Runtime evidence must therefore treat mobile as a primary product surface, not a secondary responsive check.

## Representative evidence set
1. Login
2. App shell + Sidebar desktop
3. App shell + tablet navigation/intermediate layout
4. App shell + BottomNav/FAB mobile
5. Dashboard
6. Customer list/detail
7. Sales order list/detail/create
8. Inventory transfer/adjustment
9. Finance payment/voucher
10. Procurement transaction
11. HR employee/attendance
12. Field visit execution
13. Work Management workspace
14. Reports
15. Settings/admin representative page

## Required viewport/device matrix
For every high-frequency operational flow, capture at minimum:
- representative phone portrait
- representative tablet portrait or landscape as appropriate
- desktop management viewport

For mobile-critical workflows also inspect a smaller phone width and safe-area behavior where possible.

## Capture states
For each applicable flow:
- default populated
- loading
- empty/error if reachable safely
- modal/sheet/dialog
- validation state
- permission/read-only state where relevant
- desktop
- tablet
- mobile

## Evaluate on every device
- hierarchy and primary action
- information density
- typography and number readability
- spacing consistency
- component reuse
- status semantics
- RTL correctness
- table/list transformation
- overflow
- touch ergonomics
- action reachability
- input keyboard/type suitability
- safe-area handling
- modal vs bottom-sheet behavior
- destructive-action clarity
- visible focus/accessibility signals

## Mobile-specific evaluation
- can the user complete the main daily task one-handed without hunting through menus?
- are frequent actions reachable without horizontal scrolling or tiny tap targets?
- does important context remain visible when tables become cards?
- do forms remain understandable when reduced to one column?
- are sticky actions obscured by BottomNav, browser chrome or safe areas?
- do GPS/camera/upload/offline states communicate clearly where relevant?
- does the screen remain usable under long Arabic labels, large values and real business data?

## Tablet-specific evaluation
- avoid treating tablet as oversized mobile or cramped desktop
- validate touch targets with increased information density
- use additional width for context, split panes or multi-column forms only when it improves the task
- verify both portrait and landscape on tablet-sensitive workflows

## Evidence rule
No visual defect is marked confirmed unless grounded in source evidence or a captured runtime screen. Accessibility compliance is never claimed from screenshots alone; keyboard/DOM/contrast checks are separate.

## Output
The runtime pass updates `01_CURRENT_UI_AUDIT.md` with screen-specific findings and turns draft design choices into accepted V2 decisions.
