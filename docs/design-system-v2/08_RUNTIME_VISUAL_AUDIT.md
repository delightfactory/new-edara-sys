# 08 — Runtime Visual Audit Plan

Static source inspection establishes architecture and reuse debt; it does not prove visual quality. Before the visual direction is frozen, capture the running product.

## Representative evidence set
1. Login
2. App shell + Sidebar desktop
3. App shell + BottomNav/FAB mobile
4. Dashboard
5. Customer list/detail
6. Sales order list/detail/create
7. Inventory transfer/adjustment
8. Finance payment/voucher
9. Procurement transaction
10. HR employee/attendance
11. Field visit execution
12. Work Management workspace
13. Reports
14. Settings/admin representative page

## Capture states
For each applicable flow:
- default populated
- loading
- empty/error if reachable safely
- modal/sheet/dialog
- desktop
- mobile

## Evaluate
- hierarchy and primary action
- information density
- typography and number readability
- spacing consistency
- component reuse
- status semantics
- RTL correctness
- table/list responsiveness
- overflow
- mobile touch ergonomics
- destructive-action clarity
- visible focus/accessibility signals

## Evidence rule
No visual defect is marked confirmed unless grounded in source evidence or a captured runtime screen. Accessibility compliance is never claimed from screenshots alone; keyboard/DOM/contrast checks are separate.

## Output
The runtime pass updates `01_CURRENT_UI_AUDIT.md` with screen-specific findings and turns draft design choices into accepted V2 decisions.
