# UI Implementation State

## Reviewed baseline

- Run date: `2026-09-16`
- Development branch: `design-system-v2-development`
- Exact development baseline used for this slice: `e78de5d71002b9718fa7d760b3cc7bc933ff6cba`
- Feature branch: `ds2/sales-orders-list-v2`
- Draft PR: `#30 — DS2-UI-003: migrate Sales Orders list to shared V2 grammar`
- Exact current feature HEAD: `6608f33ed60be06f0c9165dee9a5104e8c5c5b4b`
- Active slice: `DS2-UI-003 — Sales Orders list V2`
- Implementation disposition: `IN_PROGRESS`

## Independent implementation judgment

The existing Sales Orders list already contains valuable business behavior that must remain untouched: URL-synchronized filters, separate Desktop numbered pagination and Mobile infinite loading, global sales KPIs, status/payment mappings, customer location/call actions, Smart Transfer entry points, permissions, and order navigation.

The presentation debt is concentrated in the UI layer: page-local KPI cards/styles, semantic statuses rendered through generic `Badge`, a CSS-hidden Desktop/Mobile dual render tree, legacy `DataCard`, raw custom Smart Transfer buttons/FAB, and a large page-local style block. The safe migration path is therefore incremental: first establish thin Sales-domain presentation adapters over existing V2 patterns, then wire them into the page without changing data/query/pagination/business semantics.

I am not starting a speculative DataTable/FilterBar rewrite. `ResponsiveCollection`, `StatCard`, `StatusBadge`, shared `Button`, `StatePanel` and existing FilterBar/DataTable contracts should be proven/reused first. Any shared hardening must be earned by a concrete Sales-list need.

## Material progress this run

1. Revalidated repository shared memory, role states, Decision Log, Workstream, issue #27, exact development HEAD and open PR set. There was no open implementation PR targeting development.
2. Reused the already-created clean feature branch `ds2/sales-orders-list-v2`, which was still exactly at development baseline `e78de5d...` with no product drift.
3. Added `src/components/sales/SalesOrdersListPresentation.tsx` as a thin domain presentation layer:
   - `SalesOrderStatusBadge` maps the existing Sales order statuses to shared V2 `StatusBadge` semantic tones without changing status values or meaning;
   - `SalesOrdersKpiGrid` projects the existing `useSalesStats` truth through shared `StatCard` surfaces;
   - the KPI composition uses canonical `useDeviceMode` boundaries and has explicit Mobile/Tablet/Desktop grid behavior instead of page-local media-query identity.
4. Added focused `SalesOrdersListPresentation.test.tsx` covering semantic status mapping, KPI truth projection and canonical Mobile/Tablet device-mode composition.
5. Opened Draft PR #30 targeting only `design-system-v2-development`.

## Changed-file scope

Current PR #30 changes exactly two presentation/test files:

- `src/components/sales/SalesOrdersListPresentation.tsx`
- `src/components/sales/SalesOrdersListPresentation.test.tsx`

No service, hook/query, cache, database, RPC, RBAC/RLS, permission definition, route guard, validation semantic, workflow state, pricing/calculation, GitHub workflow, Vercel config or `main` file changed.

## Functional boundary to preserve

The upcoming page wiring must preserve exactly:

- existing `useFilterState(..., urlSync: true)` behavior;
- governorate -> city reset behavior;
- current `useSalesOrders` filter parameters and query calls;
- Desktop numbered pagination semantics;
- Mobile infinite-list accumulation/reset/load-more semantics;
- `useSalesStats` values and business meaning;
- current status values/labels and payment-term meaning;
- order/customer monetary calculations already present in the page;
- `sales.orders.create` visibility for Smart Transfer and new-order actions;
- order detail route destinations;
- Smart Transfer dialog behavior;
- map/call destinations;
- all Sales business-state transitions and backend behavior.

## Device / system direction

- **Mobile:** one operational card composition must be mounted for the collection, with explicit order/customer/status/financial hierarchy and touch-safe map/call/detail actions; no ordinary page horizontal overflow.
- **Tablet:** deliberate intermediate composition is required; do not inherit the old binary `>768px = Desktop table` assumption.
- **Desktop:** retain comparison density and numbered pagination.
- **Statuses:** semantic state belongs to shared `StatusBadge`; generic metadata may remain neutral `Badge` where appropriate.
- **KPIs:** shared `StatCard` owns metric hierarchy; the page only supplies the existing metric truth.
- **Filters:** keep existing FilterBar data/state contract unless the real page proves a minimal shared gap.
- **Collection:** use existing `ResponsiveCollection` where wiring can preserve current data/query/pagination semantics and avoid duplicate mounted interaction trees.

## Test / execution evidence

Current evidence: `TESTS_AUTHORED_NOT_EXECUTED`.

Focused tests have been authored for the new presentation boundary. A repository-local execution attempt is not currently possible because the sandbox cannot resolve `github.com`, so no `npm test`, `npm run build`, or `npm run lint` PASS is claimed. No GitHub Actions/hosted CI and no Vercel preview were triggered. No known TypeScript/build failure is currently recorded from source review.

## Peer-state comparison

- **Product Design Director:** stored state is for merged DS2-UI-002 and is stale for current Sales implementation decisions. Its durable direction remains aligned: reuse shared grammar, preserve density/device intent, avoid speculative abstraction.
- **Design QA:** current stored approval is consumed by merged PR #29 and is stale for this new slice; no approval applies to PR #30.
- **Development Integrator:** current state correctly marks DS2-UI-002 merged and hands only DS2-UI-003 to the UI Engineer.
- **Team Memory / Workstream:** both designate DS2-UI-003 as the single READY slice; PR #30 now makes the implementation materially active and the Workstream should reflect `IN_PROGRESS` on the next synchronization.

No current peer-state `BLOCKING` contradiction applies.

## Next implementation action

Continue only PR #30. Inspect/wire `SalesOrdersPage.tsx` in bounded steps: replace local KPI/status presentation first, then migrate the Desktop/Mobile/Tablet collection boundary toward shared V2 composition while preserving current query and pagination semantics. Do not start Sales Order form/detail work.

## Cross-role handoff

- **To:** Product Design Director, Design QA, Development Integrator
- **What changed:** DS2-UI-003 is now materially `IN_PROGRESS` on Draft PR #30. A thin reusable Sales presentation boundary now maps existing status truth to shared `StatusBadge` and existing KPI truth to shared responsive `StatCard` composition. Exact feature HEAD is `6608f33ed60be06f0c9165dee9a5104e8c5c5b4b`.
- **Preserve:** all Sales query/filter/pagination/infinite-loading/navigation/permission/status/payment/Smart Transfer/map/call/business semantics; canonical device boundaries; shared V2 ownership; quota/deployment/main restrictions.
- **Need from you:** Product Design Director may review this WIP direction for system-fit only; Design QA and Integrator must no-op because page wiring is incomplete and no review-ready handoff exists yet.
- **Blocker level:** `NONE`; execution evidence remains `TESTS_AUTHORED_NOT_EXECUTED`.
- **Baseline:** development `e78de5d71002b9718fa7d760b3cc7bc933ff6cba`; PR #30 current HEAD `6608f33ed60be06f0c9165dee9a5104e8c5c5b4b`
