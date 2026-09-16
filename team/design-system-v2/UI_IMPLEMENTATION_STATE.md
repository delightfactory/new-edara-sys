# UI Implementation State

## Reviewed baseline

- Run date: `2026-09-16`
- Development branch: `design-system-v2-development`
- Exact slice baseline: `8a0c34751344ca466754d06980093c501b536cd9`
- Exact Development HEAD observed this run: `fc547af68356aaef15a8339723c3066658cbdb4a`
- Feature branch: `ds2/sales-order-detail-v2`
- Draft PR: `#32 — DS2-UI-005: establish Sales transaction detail V2 header pattern`
- Exact product/test HEAD before this state write: `a3cef97879d76c6417298311ca058afc9be80fae`
- Active slice: `DS2-UI-005 — Sales transaction detail V2`
- Implementation disposition: `REVIEW — LIVE HERO/ACTION REGION WIRED; EXACT-HEAD QA REQUIRED`
- Evidence: `TESTS_AUTHORED_NOT_EXECUTED`

## Independent implementation judgment

The Design QA completeness blocker on exact old HEAD `9e9871fe03d32db45ac2e2daa71d82c749364761` was valid and narrowly actionable. The corrected shared `TransactionHeader` architecture already passed QA at source level; the remaining work was to connect the real Sales permission/status/callback truth to that surface without redesigning any other part of the transaction detail page.

The live hero/action region is now wired. `SalesOrderDetail.tsx` remains the sole owner of action eligibility and callbacks; it builds `AppAction[]` only after the existing page-owned permission/status predicates resolve. Shared `ActionRegistry` remains the sole placement truth, so primary workflow actions win the single Mobile visible slot, Tablet exposes at most two actions, Desktop up to four, and the rest remain available through shared overflow. The legacy local status map, sticky hero, horizontal action strip and `ActionBtn` presentation have been removed only from this region.

## Material progress this run

1. Re-ran the mandatory shared-memory bootstrap in the required order and inspected issue #27, Development HEAD, all open PRs targeting Development, PR #32, reviewer feedback and the exact live page source.
2. Independently confirmed the current blocker was implementation completeness rather than a new shared-architecture defect. Design QA and Integrator states agreed: wire only the live hero/action region, preserve exact behavior, then hand off a stable head.
3. Wired `SalesOrderDetail.tsx` to the thin `SalesOrderDetailHeader` adapter and existing shared `AppAction` contract.
4. Preserved all seven existing action gates exactly:
   - edit: draft + `sales.orders.update`;
   - confirm: draft + `sales.orders.confirm`;
   - deliver: confirmed + `sales.orders.deliver`;
   - due-date adjustment: unchanged `customers.credit.update` + delivered/partially-delivered + credit/mixed + remaining balance + delivered-at predicate;
   - return: delivered/completed + `sales.returns.create`;
   - copy: `sales.orders.create`;
   - cancel: draft/confirmed + `sales.orders.cancel`.
5. Preserved the exact existing callbacks and routes, including the confirm action's cached/server warehouse fallback, confirm modal initialization and stock check.
6. Preserved the legacy `actionLoading` disabled truth for confirm, deliver, due-date adjustment and cancel; edit, return and copy remain available exactly as before.
7. Kept `DocumentActions kind="sales-order" entityId={id!}` capability behavior intact through the shared `tools` slot; output logic was not reimplemented or changed.
8. Removed only superseded hero presentation: local `statusLabels`/`statusColors`, raw back button, horizontal action strip and local `ActionBtn` helper. Financial summary, receipts, items, notes and all modals remain untouched.
9. Added `SalesOrderDetail.v2.test.ts` source-contract coverage for shared wiring, exact permission/status gates, callback/routes/warehouse fallback, loading guards, action hierarchy/tone and untouched business/service surfaces.
10. Compared slice baseline to current Development: Development drift is limited to the three peer role-state files; there is no product/shared-component drift requiring merge-sync or exact-head churn.
11. Direct sandbox GitHub access was rechecked and still fails DNS (`Could not resolve host: github.com`), so no local npm command was possible. No GitHub Actions/hosted CI or Vercel was triggered.

## Changed-file / pattern scope

PR #32 is now bounded to ten UI/test/workstream/owned-state files:

- `src/components/patterns/TransactionHeader.tsx`
- `src/components/patterns/TransactionHeader.test.tsx`
- `src/components/sales/SalesOrderDetailPresentation.tsx`
- `src/components/sales/SalesOrderDetailPresentation.test.tsx`
- `src/styles/design-system-v2-transaction.css`
- `src/styles/main.css`
- `src/pages/sales/SalesOrderDetail.tsx`
- `src/pages/sales/SalesOrderDetail.v2.test.ts`
- `docs/design-system-v2/31_AGENT_TEAM_WORKSTREAM.md`
- `team/design-system-v2/UI_IMPLEMENTATION_STATE.md`

No DB, migration, RPC, service, query/cache, RBAC/RLS, route guard, business calculation, validation, workflow or deployment file is changed.

## Preserved functional contracts

The completed header wiring does not modify or relocate:

- `getSalesOrder` or payment-receipt query semantics;
- warehouse lookup, stock availability, confirmation or delivery service behavior;
- customer-credit checks, payment-option selection, proof upload or delivery RPC arguments;
- cancellation or due-date update service behavior;
- remaining balance, paid ratio, credit amount, minimum-cash or any other financial calculation;
- any permission definition or permission meaning;
- modal workflows, toasts, invalidation keys or navigation destinations;
- `DocumentActions` output capabilities;
- Financial Summary, Payment Receipts, Items, Notes or any modal presentation/logic below the header.

## Device / state coverage

- **Mobile:** the real Sales action set now flows through the shared one-visible-action contract. Confirm/Deliver are declared primary, so when eligible they occupy the visible workflow position; other eligible actions remain reachable in shared overflow. No horizontal action strip remains.
- **Tablet:** the same real action set resolves through the canonical two-visible-action limit, with deliberate wrapped header/tools composition.
- **Desktop:** up to four eligible workflow actions remain visible for dense review; remaining actions move to overflow rather than disappearing.
- **Permission/status states:** all seven legacy action gates remain page-owned and are protected by focused source-contract tests.
- **Loading/disabled:** confirm, deliver, due-date and cancel preserve `actionLoading` disablement; shared Button owns touch/focus rendering.
- **Destructive:** cancel retains danger tone while placement remains registry-owned.
- **RTL/accessibility:** shared logical spacing, labelled action group, native disclosure, touch targets and existing Sales status semantics are used. Customer identity remains a `CustomerLink`.
- **Loading/not-found page states:** unchanged by this slice.

## Test / execution evidence

Evidence is **`TESTS_AUTHORED_NOT_EXECUTED`**.

Focused authored coverage now spans:
- shared TransactionHeader / ActionRegistry device resolution and overflow behavior;
- thin Sales status/header adapter behavior;
- live page use of `SalesOrderDetailHeader` and absence of the legacy hero/action presentation;
- exact permission/status action gates;
- exact edit/confirm/deliver/due-date/return/copy/cancel callbacks and routes;
- confirm warehouse fallback behavior;
- four existing `actionLoading` guards;
- primary/destructive action semantics;
- preservation of query/service/financial/modal boundaries.

No local checkout exists in the sandbox, and `git ls-remote https://github.com/delightfactory/new-edara-sys.git HEAD` failed this run with `Could not resolve host: github.com`. Therefore `npm test`, `npm run build` and `npm run lint` were not executed. No hosted CI was triggered and no PASS is claimed. Source/diff inspection exposes no known TypeScript/build blocker.

## Peer-state comparison / freshness

- **Product Design Director:** its blocking state targets superseded head `97b3da7c...` and the parallel action taxonomy. That architecture defect was already corrected on `9e9871f...`; Design QA independently confirmed the correction. No new Director blocker exists on the wired candidate yet.
- **Design QA:** exact-head review of `9e9871f...` explicitly passes the corrected shared architecture and blocks only because the live page was unwired. This run implements precisely that required completion step. A fresh exact-head review is now required; the old BLOCKED verdict must not be reused as approval.
- **Development Integrator:** remains correctly `NO_MERGE` until fresh Design QA records `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` for the completed exact head.
- **Development drift:** `8a0c347... -> fc547af...` changes only `DESIGN_DIRECTOR_STATE.md`, `DESIGN_QA_STATE.md` and `INTEGRATION_STATE.md`; no product/shared-component merge-sync is justified.

## Risks / deferred work

- Runtime/browser evidence is still unavailable; final Mobile sticky density with real `DocumentActions` must be judged from source until an owner-requested runtime preview exists.
- FinancialSummary, receipt, line-item, note and modal redesign remain explicitly outside this bounded concern and must not be pulled into PR #32 during review.
- `DocumentActions` retains its current capability/output implementation rather than being redesigned as part of this slice.
- Do not broaden or merge-sync this branch solely for governance-state drift while exact-head review is pending.

## Cross-role handoff

- **To:** Product Design Director, Design QA, Development Integrator
- **What changed:** PR #32 now contains the previously missing live `SalesOrderDetail.tsx` wiring. The page builds shared `AppAction[]` from the exact legacy permission/status predicates and callbacks, passes them through `SalesOrderDetailHeader` / `TransactionHeader`, preserves `actionLoading` and `DocumentActions`, and removes only the superseded local hero/status/action presentation. Focused page-level parity coverage was added.
- **Exact product/test HEAD before this state write:** `a3cef97879d76c6417298311ca058afc9be80fae`.
- **Preserve:** all Sales query/service/RBAC/RLS/permission/workflow/calculation/modal/output truth; corrected shared ActionRegistry architecture; bounded header-only scope.
- **Need:** Design QA should perform a fresh exact-head source review of the completed candidate, including real action ordering/visibility across Mobile/Tablet/Desktop and exact permission/callback parity. Product Design Director should intervene only if a system-level design contradiction is found. Integrator remains `NO_MERGE` until exact-head `GREEN-DEV` + `SOURCE_REVIEW_PASS`.
- **Blocker level:** `NONE` from UI implementation; `AWAITING_EXACT_HEAD_REVIEW`.
- **Evidence:** `TESTS_AUTHORED_NOT_EXECUTED`.
