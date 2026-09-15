# 09 — Device Strategy

## Product reality
Edara is not a desktop application with responsive fallbacks. It is a multi-device operational product. A large share of daily user activity happens on mobile, while tablet and desktop serve complementary operational and management needs.

## Device roles
### Mobile — primary operational surface
Optimize for speed, reachability and completion of frequent tasks:
- customer lookup and quick customer context
- sales/order capture where permitted
- visits, calls, targets and field activities
- attendance and employee self-service
- approvals and action queues
- quick transaction/detail review
- evidence/photo/file upload and GPS-dependent workflows where relevant

Principles:
- one obvious primary action
- no hover dependency
- no normal horizontal scrolling for lists/details
- 44px minimum practical touch targets
- single-column forms by default
- sticky or persistent primary action where safe
- filters use compact chips + expandable sheet/drawer rather than desktop toolbars
- tables transform into prioritized cards/rows instead of compressing every column
- respect safe areas and BottomNav/FAB overlap
- support long Arabic copy, large amounts and mixed Arabic/Latin values
- performance matters under mobile networks and lower-powered devices

### Tablet — hybrid operational/management surface
Tablet should use its extra space deliberately:
- touch-first controls remain
- denser lists can be shown than mobile
- master/detail or split-pane patterns may be used where justified
- forms can become two-column only when field grouping remains clear
- portrait and landscape both require deliberate QA on tablet-sensitive workflows

### Desktop — management and high-density surface
Desktop prioritizes:
- wide comparative tables
- reports and analytics
- reconciliation and review
- bulk operations where safe
- configuration and administration
- complex finance/inventory/HR management

Desktop may expose denser context and secondary actions, but it must use the same semantic tokens, components, status system and page grammar as mobile/tablet.

## Same capability, adaptive composition
Device adaptation may change presentation and interaction pattern, but must not silently change business meaning, permission checks, calculations, workflow states or available authorized actions.

Examples:
- DataTable → MobileDataCard
- horizontal filter toolbar → filter sheet
- centered modal → bottom sheet
- action toolbar → primary action + overflow menu
- multi-column form → grouped single-column form
- dashboard analytics grid → action-first stacked dashboard

## Navigation
The full route and permission model is shared. Navigation presentation adapts:
- desktop: grouped sidebar/navigation
- tablet: compact or collapsible navigation depending on width/task
- mobile: small high-frequency BottomNav/shortcut set + full menu/drawer

The mobile shortcut set should be validated by role/task frequency; it must not simply mirror the first desktop destinations.

## Component contract
Every shared V2 component must document:
- desktop behavior
- tablet behavior
- mobile behavior
- touch/keyboard behavior
- RTL behavior
- loading/empty/error/disabled states
- long-content handling

## Definition of done impact
A screen is not considered migrated when only desktop looks correct. For operational screens, mobile acceptance is mandatory and carries equal or greater weight than desktop visual acceptance.
