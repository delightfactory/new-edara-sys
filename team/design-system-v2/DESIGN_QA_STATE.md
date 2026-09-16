# Design QA State

## Reviewed baseline

- Review date: `2026-09-16`
- Development branch: `design-system-v2-development`
- Exact Development HEAD inspected for this review: `20e47f4dc2d0a5efaf7a13fca13fa95ff1692df9`
- Active slice: `DS2-PROC-001 — Purchase list surfaces`
- Active implementation PR: `#36 — DS2-PROC-001: establish purchase invoice list V2 presentation`
- PR base: `design-system-v2-development`
- Exact PR base SHA: `20e47f4dc2d0a5efaf7a13fca13fa95ff1692df9`
- Exact PR HEAD independently reviewed and revalidated before disposition: `740f52be5e7d31ee04a5c2dc9db4c1489c08cbbc`
- Live PR state at review: `OPEN / DRAFT / mergeable`
- Changed-file scope: 6 files (Procurement card + component test + live PurchaseInvoicesPage + focused live-page test + workstream/UI implementation state)
- Current disposition: `AGENT-REVIEW: BLOCKED`
- Source evidence: `SOURCE_REVIEW_PASS` **not granted while blockers remain**.
- Test evidence: `TESTS_AUTHORED_NOT_EXECUTED`
- Exact-head local build/test/lint evidence: not claimed.
- Runtime/preview/release evidence: not claimed.

## Independent QA disposition

**BLOCKED on exact HEAD `740f52be5e7d31ee04a5c2dc9db4c1489c08cbbc`.**

The representative Procurement migration is directionally sound and functionally isolated, but two bounded P2 quality gates remain open on the live migrated surface.

### P2 — Desktop pagination RTL/accessibility semantics

`PurchaseInvoicesPage` preserves Desktop density by continuing to use shared `DataTable`, but that shared pagination currently renders physical `‹ / ›` controls without accessible previous/next names, represents the active numeric page only through visual `.active` styling, and exposes no current-page `aria-current` semantic.

That is below the V2 Arabic-first/accessibility bar and would leave this newly migrated Procurement Desktop surface inconsistent with interaction quality already established in recent Inventory migrations.

Minimum required fix:
- preserve the exact numbered pagination algorithm, current page behavior, Desktop density and `onPageChange` contract;
- narrowly harden the existing shared DataTable pagination contract, or an equally shared existing layer, with logical Arabic previous/next controls, explicit accessible names, `aria-current="page"` on the active page and an appropriate pagination navigation label/semantic boundary;
- do not open a speculative global Pagination redesign;
- add focused test coverage for the corrected semantics.

### P2 — Initial-empty and filtered-empty are conflated

The live `ResponsiveCollection` always receives the same empty `StatePanel`: `لا توجد فواتير مشتريات` / `أنشئ أول فاتورة شراء من المورد` plus the create action. When a non-empty search or status filter returns zero rows, that message incorrectly implies there are no purchase invoices at all and presents first-time creation guidance.

The North Star explicitly treats initial empty and filtered empty as distinct relevant states.

Minimum required fix:
- when no filters are active, retain the existing initial-empty/create-invoice state;
- when `search` or `statusFilter` is active and the result is empty, show neutral no-matching-results guidance instead of first-invoice messaging;
- preserve the exact query/filter/reset semantics and do not change service behavior;
- add a focused assertion protecting the distinction.

## Scope / functional isolation — PASS

The PR remains bounded to:

- `src/components/purchases/PurchaseInvoiceListPresentation.tsx`
- `src/components/purchases/PurchaseInvoiceListPresentation.test.tsx`
- `src/pages/purchases/PurchaseInvoicesPage.tsx`
- `src/pages/purchases/PurchaseInvoicesPage.v2.test.ts`
- `docs/design-system-v2/31_AGENT_TEAM_WORKSTREAM.md`
- `team/design-system-v2/UI_IMPLEMENTATION_STATE.md`

No DB, migration, RPC, service, query/cache, RBAC/RLS, permission, route-guard, accounting calculation, approval, validation, workflow, deployment, preview or `main` file is changed.

Source inspection confirms preservation of:
- `getPurchaseInvoices` and `queryKey: ['purchase-invoices', search, statusFilter, page]`;
- `PAGE_SIZE = 20`;
- search/status changes resetting page to 1;
- supplier, warehouse and document identity;
- total/paid source values and their existing visual condition;
- Purchase Invoice workflow status values and service/accounting behavior;
- detail route `/purchases/invoices/${inv.id}` and create route `/purchases/invoices/new`.

## System fit / device judgment

- **Shared collection boundary:** PASS — one `ResponsiveCollection<PurchaseInvoice>` replaces CSS-hidden duplicate Desktop/Mobile trees and mounts only the active device renderer.
- **Desktop density:** PASS except for the pagination accessibility/RTL blocker; dense `DataTable` comparison/review is retained.
- **Tablet:** PASS — deliberate two-column Procurement cards with touch-safe controls and numbered direct jumps.
- **Mobile:** PASS — one-column operational cards with full-width touch-safe detail action and logical previous/next paging.
- **Domain card architecture:** PASS — `PurchaseInvoiceCard` is a thin Procurement composition over shared `Card + KeyValueList + StatusBadge + Button`, with business/status/navigation truth page-owned.
- **Semantic status:** PASS — workflow states use shared `StatusBadge` tones while domain mapping remains page-owned.
- **Arabic/RTL and long values:** PASS for the new card/Tablet/Mobile boundary; invoice number is explicit LTR monospace with wrapping tolerance. Desktop paginator remains blocked as noted above.
- **Detail action accessibility:** PASS — Desktop icon action has an invoice-specific accessible name; card action is explicit and touch-safe; the neutral card is not a pseudo-button.
- **Loading:** PASS at source level through one shared responsive collection loading boundary.
- **Empty state:** BLOCKED only for filtered-vs-initial state semantics.

## Test / execution evidence

Evidence is **`TESTS_AUTHORED_NOT_EXECUTED`**.

Focused artifacts currently protect:
- Procurement card identity/financial/warehouse composition;
- page-supplied semantic workflow status tone;
- neutral non-interactive card anatomy and touch-safe detail callback;
- one live responsive renderer boundary;
- exact purchase query key, filter reset and `PAGE_SIZE = 20` contract;
- Tablet numbered direct jumps and Mobile previous/next capability;
- supplier/warehouse/money/status/navigation ownership;
- shared empty-state use and preserved create capability;
- removal of legacy `DataCard` / CSS-hidden duplicate collection trees.

The two blocker corrections need additional assertions for Desktop paginator semantics and filtered-empty distinction. No approved local runtime executed `npm test`, `npm run build` or `npm run lint`; no GitHub Actions/hosted CI or Vercel was used. No executed PASS is claimed. No known build/type failure is currently recorded for this exact HEAD.

## Peer-state comparison / contradiction handling

The source judgment above was formed independently from the exact PR diff, current live page/service contracts and shared V2 patterns, then compared against peer state.

- **UI Production Engineer:** feature-branch state is fresh and aligned on scope/functional isolation and already flags the inherited Desktop `DataTable` pagination debt for QA judgment. It does not contradict this blocker; filtered-empty completeness was not previously called out.
- **Product Design Director:** Development-side state still records the completed INV002 candidate and is stale for Procurement. Its pending instruction was to bound the smallest representative purchase-list concern. There is no fresh Procurement approval or conflicting current judgment yet, so this is not a BLOCKING peer contradiction by itself.
- **Development Integrator / Team Memory:** aligned that PROC001 is the sole next Procurement slice and that accounting/query/permission/workflow truth must remain unchanged.
- **Previous Design QA state:** consumed INV002 GREEN evidence and is superseded by this PROC001 review.
- **Review threads:** none were open before this review.

There is no separate material peer contradiction beyond the two QA blockers above. Integrator must remain `NO_MERGE` until a moved exact HEAD closes them and receives fresh review.

## Remaining WATCH / release boundary

- The pre-existing search placeholder says supplier name while the service query searches invoice number / supplier invoice reference. Query semantics must not be changed inside this UI PR; treat the mismatch as separate product/functional follow-up unless the Design Director bounds a presentation-only copy correction.
- Error/offline state convergence remains broader shared state-system debt; it is not a reason to widen this bounded collection migration now.
- Exact-head runtime/browser/build/test evidence remains unclaimed.
- Purchase Returns, Purchase Invoice form decomposition and a global Pagination abstraction remain out of scope.

## Cross-role handoff

- **To:** UI Production Engineer, Product Design Director, Development Integrator
- **What changed:** Design QA independently reviewed PR #36 exact HEAD `740f52be5e7d31ee04a5c2dc9db4c1489c08cbbc` and found two bounded P2 blockers: inherited Desktop DataTable pagination lacks complete RTL/accessibility semantics, and the live empty state does not distinguish filtered-empty from true initial-empty.
- **Preserve:** exact `getPurchaseInvoices` query/filter/page behavior, `PAGE_SIZE = 20`, supplier/warehouse/document identity, total/paid values, status/workflow truth, create/detail routes, service/accounting behavior, dense Desktop review, two-column Tablet cards, one-column Mobile cards and thin shared-pattern Procurement card ownership.
- **Need from you:** UI Production Engineer should make only the narrow pagination-semantic and filtered-empty corrections plus focused assertions, then hand off a new stable exact HEAD. Product Design Director may synthesize the Procurement direction independently. Development Integrator remains `NO_MERGE` until fresh exact-head QA grants `GREEN-DEV`.
- **Blocker level:** `BLOCKING`.
- **Baseline:** Development `20e47f4dc2d0a5efaf7a13fca13fa95ff1692df9`; PR #36 HEAD `740f52be5e7d31ee04a5c2dc9db4c1489c08cbbc`.
- **Evidence:** `TESTS_AUTHORED_NOT_EXECUTED`.
