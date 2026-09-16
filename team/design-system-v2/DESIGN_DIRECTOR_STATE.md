# Design Director State

## Reviewed baseline

- Review date: `2026-09-16`
- Development branch: `design-system-v2-development`
- Exact Development HEAD independently inspected before this state write: `81876ad036c7c03d8c7fab36c381790b9d690da1`
- Active slice: `DS2-INV-001 — Inventory list surfaces`
- Active Draft PR: `#34 — DS2-INV-001: establish Inventory stock list V2 presentation`
- Feature branch: `ds2/inventory-stock-list-v2`
- Exact PR base SHA: `61c2fcac8152550d72f4b94be5e85fd9979dd94d`
- Exact current PR HEAD independently reviewed: `9f3a2c4237b233bad468fa766971558caa09a5d6`
- Live PR state: `OPEN / DRAFT / mergeable`
- Current disposition: `BLOCKED — one bounded P2 Tablet pagination touch/accessibility/RTL correction`
- Current evidence: `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head runtime/build PASS is claimed and `SOURCE_REVIEW_PASS` remains withheld by Design QA on this head.

## Independent professional judgment

**THE INVENTORY LIST DIRECTION IS SYSTEM-FIT. DO NOT REDESIGN OR EXPAND THE SLICE. FIX THE TABLET PAGINATION INTERACTION BOUNDARY, THEN RE-REVIEW THE SAME PR.**

I independently reviewed the live PR source against the North Star, device strategy and component decision matrix.

The main migration direction is correct and advances the system rather than creating another Inventory island:

- one `ResponsiveCollection<Stock>` now owns the Desktop/Tablet/Mobile collection boundary instead of mounting separate CSS-hidden device trees;
- Desktop retains the dense paged `DataTable` comparison/review surface;
- Tablet receives a deliberate two-column stock-card composition rather than inheriting cramped Desktop;
- Mobile receives a one-column operational card composition;
- `StockBalanceCard` remains a thin Inventory-domain composition over shared `Card + KeyValueList + StatusBadge` rather than a new primitive family;
- stock health, quantities, valuation, cost permission, review calculations, filters, query semantics and page transitions remain page/domain-owned.

The candidate is not yet GREEN because the newly introduced Tablet pagination path reuses legacy raw `.pagination-btn` controls. Current shared legacy CSS fixes those buttons at `32px × 32px`, which conflicts with the documented 44px practical touch target for touch-first Tablet operation. The selected page is visual-only through `.active`, and previous/next are symbol-only without explicit accessible names.

There is one additional RTL requirement that should be resolved in the same bounded correction: the visible `‹` / `›` cues are physical LTR-style arrows. In an Arabic-first RTL product, previous/next direction must not be visually ambiguous or reversed. The correction should use clear Arabic text labels or direction-aware logical icons while preserving exactly the same page movement semantics.

This does **not** justify opening a broad Pagination framework now. The codebase clearly has shared Pagination debt, but a global convergence task would require auditing DataTable and other existing consumers and would unnecessarily widen this Inventory slice. The right move here is a local composition correction using existing shared Button/touch semantics, with full shared Pagination convergence remaining a dedicated component-depth slice.

## Current architecture / product-system fit

- **Representative Inventory list choice:** PASS.
- **ResponsiveCollection single device boundary:** PASS.
- **Desktop density / review efficiency:** PASS.
- **Tablet card composition / valuation parity:** PASS except pagination interaction treatment.
- **Mobile operational card composition:** PASS at source level.
- **Shared Card / KeyValueList / StatusBadge reuse:** PASS.
- **Functional isolation:** PASS at source level; no backend/query/permission/calculation/workflow meaning moved.
- **Arabic wrapping / logical spacing:** PASS at source level for the new stock cards.
- **Tablet pagination touch target:** BLOCKING P2 on current head.
- **Tablet pagination accessible naming/current-page semantics:** BLOCKING P2 on current head.
- **Tablet pagination RTL directional cue:** BLOCKING within the same bounded correction.
- **Global shared Pagination convergence:** WATCH / future component-depth work, not required to clear PR #34.

## Required correction before REVIEW can become GREEN-DEV

### P2 — harden only the Tablet numbered pagination boundary

Preserve all current query/page/direct-jump behavior and make the minimum presentation correction:

1. every Tablet pagination control has a practical minimum `44px × 44px` hit target; use the existing shared `Button`/touch contract where practical and guarantee minimum inline size for numeric controls;
2. previous/next controls expose explicit accessible names;
3. the selected numeric page exposes `aria-current="page"` or an equivalent complete current-page semantic;
4. previous/next visual direction is RTL-native and unambiguous — Arabic text labels or direction-aware logical icons are acceptable; do not leave physical LTR-only arrows as the sole cue;
5. focused tests protect the corrected Tablet touch/accessibility/RTL contract rather than asserting legacy `.pagination-btn` markup;
6. do not change the pagination algorithm, query shape, page size, direct-jump capability, Desktop DataTable behavior or Mobile paging semantics.

Do not widen this correction into stock filters, summary cards, transfer/adjustment flows, global DataTable/Pagination replacement or any functional change.

## Peer-state comparison / freshness

After forming the current-source judgment above, peer positions were compared:

- **Design QA:** fresh exact-head state on `9f3a2c4...` reaches the same P2 BLOCKED conclusion for Tablet touch/accessibility. I agree with QA and add only the RTL directional-cue requirement to the same correction boundary.
- **UI Production Engineer:** feature-branch state is fresh for PR #34 and correctly preserves information/query parity, but its assumption that reusing legacy numbered pagination markup is sufficient is not acceptable for the new touch-first Tablet V2 renderer. This is a material but tightly bounded contradiction.
- **Development Integrator:** Development-side state is still the consumed DS2-UI-005 merge state. Its merge policy remains authoritative: PR #34 must stay `NO_MERGE` until a corrected exact HEAD receives fresh `GREEN-DEV + SOURCE_REVIEW_PASS` and no blocking role-state contradiction remains.
- **Team Memory / Workstream:** Development-side shared memory still labels DS2-INV-001 READY while the active feature branch is already in REVIEW/BLOCKED. That lag is expected during an active slice; no second slice should start.

## Preserve

- one active implementation slice only;
- all existing stock query/filter/page/page-size semantics;
- warehouse/product navigation;
- `finance.view_costs` gating and valuation truth;
- stock-health/minimum-stock calculations;
- local review mode and no-save/no-adjustment meaning;
- Desktop dense table and direct navigation;
- Tablet two-column cards, valuation parity and direct page jumps;
- Mobile one-column cards and compact paging;
- shared `ResponsiveCollection`, `Card`, `KeyValueList`, `StatusBadge`, `Button` grammar;
- no GitHub Actions, hosted CI, Vercel preview, backend/business or `main` activity.

## Cross-role handoff

- **To:** UI Production Engineer, Design QA, Development Integrator
- **What changed:** Product Design Director independently reviewed PR #34 exact HEAD `9f3a2c4237b233bad468fa766971558caa09a5d6` and confirms the Inventory collection/card architecture is sound. The slice remains BLOCKED only on the Tablet numbered-pagination interaction boundary: 32px legacy targets, missing explicit previous/next names, missing current-page semantic, plus an RTL directional-cue requirement for the symbol-only arrows.
- **Preserve:** all stock/query/filter/page/valuation/permission/review/link truth; Desktop density; Tablet direct page jumps and valuation; Mobile paging; current shared collection/card/status architecture; bounded Inventory-list scope.
- **Need from you:** UI Production Engineer should correct only the Tablet pagination presentation using touch-safe shared action semantics, complete accessibility/current-page semantics and RTL-native directional cues, update the focused test, and hand off one new stable exact HEAD. Design QA should re-review that exact head. Integrator remains `NO_MERGE` until the corrected head has `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and the blocking contradiction is closed.
- **Blocker level:** `BLOCKING` — P2 Tablet touch/accessibility/RTL pagination treatment only.
- **Baseline:** Development `81876ad036c7c03d8c7fab36c381790b9d690da1`; PR #34 HEAD `9f3a2c4237b233bad468fa766971558caa09a5d6`
