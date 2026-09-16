# UI Implementation State

## Reviewed baseline

- Run date: `2026-09-16`
- Development branch: `design-system-v2-development`
- Exact development baseline used for this slice: `e78de5d71002b9718fa7d760b3cc7bc933ff6cba`
- Exact development HEAD observed this run before state write: `8dbc13992f91c293d02b3e57fb5191e40b6efe6f`
- Feature branch: `ds2/sales-orders-list-v2`
- Draft PR: `#30 — DS2-UI-003: migrate Sales Orders list to shared V2 grammar`
- Exact current feature HEAD: `bfd54e578a7b63bd7abfa567e197db0043cc8a13`
- Active slice: `DS2-UI-003 — Sales Orders list V2`
- Implementation disposition: `IN_PROGRESS`

## Independent implementation judgment

The existing Sales Orders list already contains valuable behavior that must remain untouched: URL-synchronized filters, separate Desktop numbered pagination and Mobile infinite loading, global sales KPIs, status/payment mappings, customer map/call actions, Smart Transfer entry points, permissions, and order navigation.

The page still has concentrated presentation debt: page-local KPI cards/styles, semantic statuses rendered through generic `Badge`, a CSS-hidden Desktop/Mobile dual render tree, legacy `DataCard`, raw custom Smart Transfer controls, and a large page-local style block.

The safest migration remains incremental. Shared-system boundaries should be prepared before page wiring so the final page diff mostly replaces legacy composition rather than mixing redesign and data behavior changes in one step. I am not starting a speculative DataTable or FilterBar rewrite.

## Material progress this run

1. Re-ran the mandatory shared-memory bootstrap and revalidated issue #27, live development HEAD and the only open implementation PR (#30).
2. Re-read `SalesOrdersPage.tsx` and the existing shared `ResponsiveCollection`, `DataTable`, `Button`, `Card` and `KeyValueList` contracts.
3. Confirmed a concrete reusable gap for the current Sales screen: Mobile/Tablet need one deliberate operational card composition that does not reuse the legacy clickable `DataCard` pattern or duplicate hidden interaction trees.
4. Extended `src/components/sales/SalesOrdersListPresentation.tsx` with `SalesOrderCard`:
   - domain-specific composition only; business/query/calculation truth remains page-owned and is passed as already-projected values;
   - shared `Card`, `KeyValueList`, `Button`, `StatusBadge` and semantic token contracts own visual/interaction behavior;
   - explicit Mobile versus Tablet density via `mode`;
   - touch-safe `عرض الطلب` / map / call actions;
   - semantic payment progress uses a real labelled `progressbar` contract;
   - Arabic hierarchy keeps order/customer codes LTR without making the card itself a fake button.
5. Extended focused tests for mobile action callbacks, semantic status, progress accessibility, tablet density and optional-action absence.
6. Retried repository-local GitHub access from the sandbox; DNS still fails with `Could not resolve host: github.com`, therefore no local test/build execution is claimed.

## Changed-file scope

Current PR #30 still changes only two Sales presentation/test files:

- `src/components/sales/SalesOrdersListPresentation.tsx`
- `src/components/sales/SalesOrdersListPresentation.test.tsx`

No service, hook/query, cache, database, RPC, RBAC/RLS, permission definition, route guard, validation semantic, workflow state, pricing/calculation, GitHub workflow, Vercel config or `main` file changed.

## Functional boundary to preserve

Upcoming page wiring must preserve exactly:

- existing `useFilterState(..., urlSync: true)` behavior;
- governorate -> city reset behavior;
- current `useSalesOrders` filter parameters and query calls;
- Desktop numbered pagination semantics;
- Mobile infinite-list accumulation/reset/load-more semantics;
- `useSalesStats` values and business meaning;
- current status values/labels and payment-term meaning;
- all order/customer monetary calculations currently owned by `SalesOrdersPage`;
- `sales.orders.create` visibility for Smart Transfer and new-order actions;
- order detail route destinations;
- Smart Transfer dialog behavior;
- map/call destinations;
- all Sales business-state transitions and backend behavior.

`SalesOrderCard` intentionally accepts already-projected totals/outstanding/paid-percent values so moving the UI does not move or reinterpret Sales business calculations.

## Device / system direction

- **Mobile:** one operational Sales card renderer should be mounted through `ResponsiveCollection`; explicit customer/order/status/financial hierarchy and touch-safe actions; no ordinary horizontal overflow.
- **Tablet:** use the same shared-domain card anatomy at a denser information layout, not the old `>768px = Desktop table` assumption.
- **Desktop:** retain dense `DataTable` comparison and numbered pagination.
- **Statuses:** semantic state belongs to shared `StatusBadge`.
- **KPIs:** shared `StatCard` owns hierarchy; page supplies existing KPI truth.
- **Filters:** keep the current FilterBar state/data contract unless the real wiring proves a minimal shared gap.
- **Collection:** existing `ResponsiveCollection` is the intended one-renderer-at-a-time boundary. Page wiring must choose current Desktop page data versus existing accumulated Mobile data without changing their query contracts.

## Test / execution evidence

Current evidence: `TESTS_AUTHORED_NOT_EXECUTED`.

Focused tests now cover:
- semantic status mapping;
- KPI truth projection;
- canonical Mobile/Tablet KPI composition;
- mobile Sales card hierarchy and map/call/open callbacks;
- labelled payment progress semantics;
- denser Tablet card composition;
- absence of optional actions when callbacks are not supplied.

Actual sandbox retry this run:
- command: `git ls-remote https://github.com/delightfactory/new-edara-sys.git HEAD`
- result: failed before repository access with `Could not resolve host: github.com`.

Therefore no `npm test`, `npm run build`, `npm run lint` or `LOCAL_EXECUTION_PASS` is claimed. No GitHub Actions/hosted CI or Vercel preview were triggered. No known TypeScript/build failure is currently recorded from source review.

## Peer-state comparison

- **Product Design Director:** stored state still targets completed DS2-UI-002 and is stale for current Sales implementation. Durable direction remains aligned: strengthen shared grammar only where proven, preserve device intent and density, avoid speculative abstraction.
- **Design QA:** stored `GREEN-DEV` applies only to merged PR #29 and is stale for PR #30; no Sales approval exists.
- **Development Integrator:** current state is fresh enough to confirm normal `NO_MERGE_IN_PROGRESS` at earlier PR #30 HEAD `6608f33e...`; that exact-head observation is now stale because implementation advanced to `bfd54e57...`, but its no-merge conclusion remains aligned until a review-ready handoff exists.
- **Team Memory / Workstream:** both correctly identify DS2-UI-003 as the single active slice.

No current peer-state `BLOCKING` contradiction applies.

## Next implementation action

Continue only PR #30. Wire the already-prepared presentation layer into `SalesOrdersPage.tsx` in bounded steps:

1. replace page-local KPI/status presentation with `SalesOrdersKpiGrid` / `SalesOrderStatusBadge`;
2. adopt `ResponsiveCollection` so only one Desktop/Tablet/Mobile interaction tree is mounted;
3. feed existing Desktop paged data to the Desktop table, existing Mobile accumulated data to Mobile cards, and a deliberate Tablet card composition without changing query semantics;
4. migrate raw Smart Transfer action controls to shared `Button` while preserving permission/dialog behavior;
5. remove only the legacy style/dead presentation code proven unused after wiring.

Do not start Sales Order form/detail work.

## Cross-role handoff

- **To:** Product Design Director, Design QA, Development Integrator
- **What changed:** DS2-UI-003 advanced on Draft PR #30 from initial KPI/status adapters to a reusable Mobile/Tablet `SalesOrderCard` composition over shared V2 primitives. Exact feature HEAD is `bfd54e578a7b63bd7abfa567e197db0043cc8a13`; PR remains intentionally WIP because `SalesOrdersPage` wiring is not yet complete.
- **Preserve:** all Sales query/filter/pagination/infinite-loading/navigation/permission/status/payment/Smart Transfer/map/call/business semantics; page ownership of monetary calculations; canonical device boundaries; shared V2 ownership; quota/deployment/main restrictions.
- **Need from you:** Product Design Director may review the WIP component boundary for system-fit. Design QA and Integrator should no-op until the page is wired and a stable review-ready exact HEAD is handed off.
- **Blocker level:** `NONE`; execution evidence remains `TESTS_AUTHORED_NOT_EXECUTED`.
- **Baseline:** development baseline `e78de5d71002b9718fa7d760b3cc7bc933ff6cba`; development observed `8dbc13992f91c293d02b3e57fb5191e40b6efe6f`; PR #30 current HEAD `bfd54e578a7b63bd7abfa567e197db0043cc8a13`
