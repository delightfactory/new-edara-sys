# Design Director State

## Reviewed baseline

- Review date: `2026-09-16`
- Development branch: `design-system-v2-development`
- Exact Development HEAD independently inspected before this state write: `1ebb31f9d68677b29667a93edf240b097eefa365`
- Active slice: `DS2-INV-002 — Transfer/adjustment operational flows`
- Active Draft PR: `#35 — DS2-INV-002: establish transfer flow V2 presentation`
- Feature branch: `ds2/inventory-transfer-flow-v2`
- Exact PR base SHA: `27437916d5afd047e794dd5bf86a2ddbf2becbdb`
- Exact current PR HEAD independently reviewed: `69a18c6a6abe4cdecc17156877a766a83e152517`
- Current PR scope: four files; `TransfersPage.tsx` is not yet in the diff.
- Current disposition: `BLOCKED — P2 live integration completeness + one same-pass semantic-boundary correction before wiring`
- Current evidence: `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head runtime/build PASS is claimed and `SOURCE_REVIEW_PASS` is correctly withheld by Design QA on this head.

## Independent professional judgment

**THE SELECTED TRANSFER COLLECTION BOUNDARY IS CORRECT. KEEP PR #35 AS THE ONLY ACTIVE SLICE, WIRE THE LIVE PAGE, AND DO NOT EXPAND INTO TRANSFER DETAIL, ADJUSTMENTS OR CREATE-FLOW REDESIGN.**

I independently reviewed the active PR, the live `TransfersPage`, `ResponsiveCollection`, the shared component decision matrix and the current Inventory grammar before comparing peer states.

The architectural direction is sound:

- `TransfersPage` is the right first representative Inventory operational surface after the stock-list proof;
- one `ResponsiveCollection<StockTransfer>` should replace the current CSS-switched `.tr-table-view` / `.tr-card-view` collection trees so only one device renderer is mounted;
- Desktop should retain the dense transfer table, expand/collapse item review and authorized unit-cost visibility;
- Tablet should become a deliberate touch-first card collection rather than inheriting the current binary Desktop/Mobile split;
- Mobile should use the thin `TransferCard` with an explicit touch-safe detail entry instead of making the neutral Card itself an interactive control;
- transfer query, page, ownership, permission, workflow eligibility, confirmation callbacks, create flow, stock/reservation/service/validation truth must remain page/domain-owned.

Design QA's current P2 implementation-completeness blocker is valid: the new card foundation cannot receive slice-level acceptance while the live page still runs the legacy duplicated trees.

There is one additional design-system correction that should be made in the same bounded implementation pass before live wiring: **transfer direction (`إرسال` / `طلب`) is categorical metadata, not a workflow/status state.** `StatusBadge` is explicitly the shared mapping for domain statuses, so `TransferCard` should not expose `directionTone: SemanticTone` or render direction through `StatusBadge`. Keep the actual transfer status on `StatusBadge`; render direction as a neutral generic `Badge`/metadata treatment with textual and/or Send/Download icon distinction. This preserves semantic-color discipline and prevents another domain-specific status taxonomy from leaking into the shared language.

This does not justify a new primitive or wider visual redesign.

## Required bounded completion before REVIEW can become GREEN-DEV

1. Wire only the live `TransfersPage` collection region through one `ResponsiveCollection<StockTransfer>`.
2. Preserve the current dense Desktop table exactly in business capability, including expansion, item rows, notes/shipped/received context and `finance.view_costs` gating.
3. Use `TransferCard` for Tablet/Mobile, with deliberate Tablet density and touch-safe Mobile operation.
4. Centralize repeated transfer-action presentation at page level only; preserve the exact current predicates/callbacks for ship, approve-and-ship, receive and cancel, including source/destination/creator ownership and `approved_by !== userId`.
5. Preserve current `useTransfers` filter/page behavior and `pageSize: 25`. Do **not** invent StockPage-style numbered direct jumps here: this live flow currently has previous/next paging only. Tablet may adopt the proven touch-safe V2 Button treatment while keeping the same page semantics.
6. Preserve loading, empty, create modal, confirmation dialog, route navigation and create-FAB/header capability without opening those surfaces for redesign in this slice.
7. Correct the card semantic boundary: direction uses neutral generic Badge/metadata; workflow status alone uses `StatusBadge` semantic tones.
8. Add focused live-page tests for single renderer selection, Desktop expansion/cost parity, Tablet/Mobile card selection, action-predicate parity, paging/state parity and the direction-vs-status badge contract.
9. Do not change DB/RPC/service/query/cache/RBAC/RLS/permission/stock-movement/reservation/validation/workflow semantics.

## Architecture / product-system fit

- **Representative transfer surface:** PASS.
- **Thin Inventory-domain card over shared primitives:** PASS with direction-badge correction required.
- **ResponsiveCollection target:** PASS; live wiring still incomplete.
- **Desktop density / expanded review parity:** REQUIRED / not yet reviewable on current head.
- **Tablet deliberate composition:** REQUIRED / not yet live on current head.
- **Mobile touch/detail interaction:** directionally PASS in card foundation; live parity not yet reviewable.
- **Workflow/action truth page-owned:** PASS in foundation; must remain so during wiring.
- **Direction semantic treatment:** BLOCKING within the same bounded pass — categorical direction must not masquerade as StatusBadge state.
- **Functional isolation:** PASS for current four-file foundation; must be rechecked after live wiring.
- **Global Pagination, Transfer Detail, Adjustments, create-flow/Combobox redesign:** OUT OF SCOPE.

## Peer-state comparison / freshness

After forming the source judgment above, peer positions were compared:

- **Design QA:** fresh exact-head state on `69a18c6...` blocks only because the live `TransfersPage` is not wired. I agree with that blocker and add the direction/status semantic-boundary correction before the card becomes live.
- **UI Production Engineer:** feature-branch state is fresh and already labels implementation `IN_PROGRESS`; its selected `ResponsiveCollection` boundary, preserved business invariants and no-second-surface discipline align with this direction. Its use of `StatusBadge` for direction is the one system-fit assumption that must change.
- **Development Integrator:** Development-side state is the consumed INV001 merge state and is stale for the active INV002 implementation. Its merge rule remains authoritative: PR #35 stays `NO_MERGE` until a moved exact HEAD receives fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and no current BLOCKING contradiction remains.
- **Team Memory / Development workstream:** still describe INV002 as the next READY slice because implementation state/workstream updates currently live in the Draft PR. That is expected; no second implementation slice may start.
- **Development drift:** current Development is one QA-state commit ahead of the PR base and does not change product/shared-component code. Do not create SHA churn solely for governance drift while implementation is still incomplete; synchronize only if a real merge/conflict/product dependency requires it before final review.

## Preserve

- one active implementation PR only;
- all transfer query/filter/page/page-size semantics;
- `inventory.read_all`, warehouse ownership/creator ownership and `finance.view_costs` truth;
- exact ship / approve-and-ship / receive / cancel eligibility and callbacks;
- confirmation behavior and service calls;
- create-transfer stock/availability/reservation/validation behavior;
- Desktop dense review + expanded items/costs;
- Mobile/Tablet task orientation and 44px practical touch behavior;
- shared `ResponsiveCollection`, `Card`, `KeyValueList`, `Button`, generic `Badge` and `StatusBadge` ownership boundaries;
- no GitHub Actions, hosted CI, Vercel preview, backend/business or `main` activity.

## Cross-role handoff

- **To:** UI Production Engineer, Design QA, Development Integrator
- **What changed:** Product Design Director independently reviewed PR #35 exact HEAD `69a18c6a6abe4cdecc17156877a766a83e152517`. The selected transfer collection/card architecture is correct, but the slice remains BLOCKED because the live `TransfersPage` is not wired. One same-pass semantic correction is added: `إرسال/طلب` direction is categorical metadata and must use neutral generic Badge/metadata treatment; only transfer workflow status uses `StatusBadge`.
- **Preserve:** every transfer query/page/permission/ownership/action/create/confirm/stock/reservation/service/validation/route contract; dense Desktop expansion/cost review; bounded collection-only scope; current page semantics for paging; no second slice.
- **Need from you:** UI Production Engineer should complete only the declared live `ResponsiveCollection` wiring, correct the direction/status badge boundary, preserve exact action/paging/state behavior and add focused live-parity tests, then hand off one stable exact HEAD. Design QA should re-review that exact head. Integrator remains `NO_MERGE` until fresh `GREEN-DEV + SOURCE_REVIEW_PASS` closes all blocking conditions.
- **Blocker level:** `BLOCKING` — P2 live integration completeness plus same-boundary semantic badge correction.
- **Baseline:** Development `1ebb31f9d68677b29667a93edf240b097eefa365`; PR #35 HEAD `69a18c6a6abe4cdecc17156877a766a83e152517`.
