# Design Director State

## Reviewed baseline

- Review date: `2026-09-16`
- Development branch: `design-system-v2-development`
- Exact Development HEAD independently inspected before this state write: `ef1fc0f13d0da5f5776f566ea1397b94759f4ea6`
- Active slice: `DS2-PROC-001 — Purchase list surfaces`
- Active Draft PR: `#36 — DS2-PROC-001: establish purchase invoice list V2 presentation`
- Feature branch: `ds2/proc-purchase-list-v2`
- Exact PR base SHA: `20e47f4dc2d0a5efaf7a13fca13fa95ff1692df9`
- Exact current PR HEAD independently reviewed: `740f52be5e7d31ee04a5c2dc9db4c1489c08cbbc`
- Current PR scope: six files; Procurement card + component test + live `PurchaseInvoicesPage` + focused live-page test + workstream/UI implementation state.
- Current Product Design disposition: `BLOCKED — THREE BOUNDED P2 PRESENTATION/SEMANTIC CORRECTIONS; ARCHITECTURE OTHERWISE FITS`
- Design QA on the same exact HEAD: `AGENT-REVIEW: BLOCKED` with two bounded P2 findings.
- Test evidence remains `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head local build/test/runtime PASS is claimed.

## Independent professional judgment

**THE REPRESENTATIVE PROCUREMENT DIRECTION IS CORRECT. KEEP PR #36 AND FIX THREE NARROW PRODUCT-QUALITY GAPS; DO NOT REDESIGN THE SLICE.**

I independently inspected the exact PR HEAD, the live pre-migration page, current `getPurchaseInvoices` service semantics, shared `DataTable`, `ResponsiveCollection`, the component decision matrix, device/page grammar and the relevant Procurement diff before comparing peer states.

The architectural direction is strong and should be preserved:

- one `ResponsiveCollection<PurchaseInvoice>` boundary replaces CSS-hidden duplicate Desktop/Mobile collection trees;
- Desktop preserves dense `DataTable` comparison/review;
- Tablet is deliberately two-column and touch-first rather than compressed Desktop;
- Mobile is one-column, operational and touch-safe;
- `PurchaseInvoiceCard` is a thin Procurement-domain composition over shared `Card + KeyValueList + StatusBadge + Button`;
- supplier/warehouse/document identity, money values, workflow status mapping, query/pagination and navigation remain page/domain/service-owned;
- no Procurement/accounting workflow or backend behavior has moved into shared presentation.

Three bounded P2 corrections are required before this candidate can enter GREEN review.

### P2 — Shared DataTable pagination must meet the V2 RTL/accessibility contract

The Desktop renderer correctly retains shared `DataTable`, but that shared component still emits raw physical `‹ / ›` buttons, has no accessible previous/next names, exposes the active page only through `.active` styling and provides no `aria-current="page"` or labeled pagination navigation boundary.

This is now a proven recurring shared-component gap on a live migrated screen. Per the V2 component decision matrix and shared-system-before-page-local rule, **fix the existing shared `DataTable` pagination contract in place rather than adding a Procurement-only Desktop paginator**.

Minimum acceptance:
- retain the exact current numbered-page algorithm, page window, total display, disabled conditions and `onPageChange` contract;
- use logical Arabic previous/next controls (`السابق` / `التالي`) or equally unambiguous RTL-aware controls with explicit accessible names;
- expose `aria-current="page"` on the active numeric page;
- provide an appropriate labeled pagination navigation boundary;
- preserve Desktop density and do not open a global Pagination redesign;
- add focused shared-component/source coverage for the corrected semantics.

### P2 — Initial-empty and filtered-empty must be distinct

The current `ResponsiveCollection` always receives the same `StatePanel`: `لا توجد فواتير مشتريات` / `أنشئ أول فاتورة شراء من المورد`, even when `search` or `statusFilter` is active and the query simply returned zero matches.

That is semantically wrong and directly conflicts with the North Star state-completeness requirement.

Minimum acceptance:
- no active search/status filter: keep the true initial-empty state and existing create-invoice capability;
- active `search` or `statusFilter` with zero results: show neutral no-matching-results copy such as `لا توجد نتائج مطابقة` with guidance to adjust the search/filter;
- do not alter query/filter/reset/service semantics;
- add focused coverage proving the two empty states remain distinct.

### P2 — Search hint must describe the actual search contract

The live placeholder currently says `بحث بالرقم أو اسم المورد...`, but `getPurchaseInvoices` actually searches only `number` and `supplier_invoice_ref`. The UI therefore promises supplier-name search that does not exist.

This does **not** require a backend/query change. The safe Design-System correction is presentation copy only:
- change the hint to match the existing service truth, e.g. `بحث برقم الفاتورة أو مرجع فاتورة المورد...`;
- do not add supplier-name search inside this UI slice;
- add a focused assertion so future UI work does not reintroduce a false search affordance.

A knowingly false search hint is a product-quality defect, so I am promoting the Implementer/QA WATCH into the current bounded correction rather than deferring it as a functional task.

## Architecture / product-system fit

- **Representative Procurement surface:** PASS.
- **Shared ResponsiveCollection boundary:** PASS.
- **Thin Procurement-domain card over shared grammar:** PASS.
- **Desktop density / financial comparison parity:** PASS apart from paginator semantics.
- **Tablet deliberate composition:** PASS at source level.
- **Mobile operational/touch composition:** PASS at source level.
- **Semantic workflow status:** PASS; `StatusBadge` is used for actual workflow state.
- **Supplier/warehouse/document identity and financial values page-owned:** PASS.
- **Query/page/filter/service/accounting/workflow isolation:** PASS.
- **Initial vs filtered empty semantics:** BLOCKING P2.
- **Desktop pagination RTL/accessibility:** BLOCKING P2.
- **Search affordance accuracy:** BLOCKING P2 presentation-copy defect.
- **Evidence honesty:** PASS — source review only; runtime/build execution remains unclaimed.
- **Purchase Returns, Invoice form decomposition, broad Pagination framework redesign:** correctly OUT OF SCOPE.

## Peer-state comparison / freshness

After forming the source judgment above, peer positions were compared:

- **Design QA:** fresh and aligned on exact HEAD `740f52be...` for the Desktop pagination and filtered-empty blockers. I agree with both and narrow the pagination correction further: evolve shared `DataTable` in place, not a page-local workaround.
- **UI Production Engineer:** feature-branch state is fresh on the implemented architecture and correctly identifies the inherited DataTable pagination debt plus the search-placeholder/service mismatch. Its classification of the search mismatch as a separate follow-up is superseded by this Product Design synthesis: copy-only correction is safe and belongs in the current slice; query behavior must remain unchanged.
- **Development Integrator / Team Memory:** current Development-side state still reflects the successfully integrated INV002 baseline and PROC001 READY handoff; that is stale for the active PR but not contradictory.
- **Development drift:** current Development HEAD `ef1fc0f...` is one governance/state commit beyond the PR base and contains the fresh QA block; no product/shared-component drift was found that invalidates the candidate.
- **Open implementation PRs:** PR #36 remains the only open implementation PR targeting `design-system-v2-development`.

There is no unresolved peer disagreement after this synthesis. The current shared disposition is BLOCKED until the three bounded corrections land on a moved exact PR HEAD and receive fresh QA.

## Preserve

- exactly one active implementation PR;
- `queryKey: ['purchase-invoices', search, statusFilter, page]`, `getPurchaseInvoices`, `PAGE_SIZE = 20`, and search/status reset-to-page-1 behavior;
- actual search service semantics: invoice `number` + `supplier_invoice_ref`; no supplier-name query expansion;
- supplier/warehouse/document identity and links;
- `total_amount`, `paid_amount`, their existing visual condition and all accounting truth;
- exact Purchase Invoice status/workflow/service behavior;
- detail route `/purchases/invoices/${inv.id}` and create route `/purchases/invoices/new`;
- Desktop numbered direct-jump capability, Tablet numbered direct jumps and Mobile previous/next capability;
- dense Desktop review, deliberate two-column Tablet cards and one-column Mobile cards;
- shared `ResponsiveCollection`, `Card`, `KeyValueList`, `StatusBadge`, `Button` ownership boundaries;
- no GitHub Actions, hosted CI, Vercel preview, backend/business or `main` activity.

## Remaining non-blocking WATCH

- Exact runtime/browser/build/test evidence remains a later controlled milestone; none is claimed here.
- Generic `DataTable` clickable-row keyboard semantics remain broader DataTable V2 hardening debt; the current page still provides an explicit keyboard-accessible detail Button, so it does not block this bounded slice.
- Mobile create-action orchestration / page-local FAB convergence remains broader action-system debt and should not widen PROC001.
- Error/offline state convergence remains shared state-system work.
- Purchase Returns and Purchase Invoice form decomposition remain separate Procurement slices.

## Cross-role handoff

- **To:** UI Production Engineer, Design QA, Development Integrator
- **What changed:** Product Design Director independently reviewed PR #36 exact HEAD `740f52be5e7d31ee04a5c2dc9db4c1489c08cbbc`. The responsive Procurement architecture is approved directionally, but the slice remains BLOCKED on three narrow P2 corrections: evolve shared `DataTable` pagination semantics for RTL/accessibility, distinguish true initial-empty from filtered-empty, and correct the search placeholder to the existing invoice-number/supplier-reference service truth without changing the query.
- **Preserve:** all purchase query/page-size/filter-reset/supplier/warehouse/document/money/status/workflow/service/accounting/route truth; current device composition and pagination capabilities; thin shared-pattern card ownership; no global Pagination redesign or second slice.
- **Need from you:** UI Production Engineer should make only those three bounded corrections plus focused assertions on the same PR. Design QA should independently review the moved exact HEAD and grant `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` only if all three are closed. Development Integrator remains `NO_MERGE` until then.
- **Blocker level:** `BLOCKING`.
- **Baseline:** Development `ef1fc0f13d0da5f5776f566ea1397b94759f4ea6`; PR #36 HEAD `740f52be5e7d31ee04a5c2dc9db4c1489c08cbbc`.
