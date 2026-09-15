# 30 — Customers List V2 Migration

## Purpose
Move the Customers list onto the shared responsive collection grammar without changing its established desktop pagination or mobile infinite-scroll data behavior.

## Preserved without change
- `useFilterState` URL-synced filter behavior.
- Governorate → city dependent filtering.
- Desktop/Tablet `useCustomers` path with numbered pagination.
- Mobile `useCustomers` path with `useMobileInfiniteList` accumulation.
- Filter reset behavior and server-derived `totalCount` summary.
- Customer active/inactive toggle service and confirmation flow.
- Customer row/card navigation.
- Mobile call and Google Maps shortcuts.
- Credit display through `CustomerCreditChip`.
- Existing create/update permission checks.

## Presentation migration
- `ResponsiveCollection` now decides which collection presentation mounts for the active device mode.
- Mobile mounts only the card/infinite-scroll presentation.
- Tablet and Desktop mount only the paged table presentation.
- Previous CSS show/hide orchestration is removed.
- Shared `StatePanel` handles the empty collection state.
- Shared `Card` wraps the paged table and loading surfaces.
- Customers-specific composition styling moves to `customers-v2.css`.

## Important architectural choice
Both existing data hooks remain mounted in this slice. This intentionally avoids changing fetch/cache behavior while the UI migration is still being validated. A future performance-only optimization may conditionally fetch by device, but that is outside this no-functional-change migration.

## Device behavior
- Mobile ≤768px: DataCard list + existing infinite-scroll sentinel/loading/end states.
- Tablet 769–1024px: paged DataTable inside an overflow-safe surface.
- Desktop >1024px: paged DataTable.

## Tests
Focused tests protect the key migration invariant:
- Desktop mounts the table presentation and not mobile cards.
- Mobile mounts cards and not the table.
- The existing two data hooks remain invoked during this migration slice.

## Guardrails
- No service, RPC, DB, route, permission, filter, pagination, or toggle behavior changes.
- No Sidebar rollout change.
- No Vercel deployment required.
