# Design QA State

## Reviewed baseline

- Review date: `2026-09-16`
- Development branch: `design-system-v2-development`
- Exact Development HEAD independently inspected before this QA write: `61c2fcac8152550d72f4b94be5e85fd9979dd94d`
- Active slice: `DS2-INV-001 — Inventory list surfaces`
- Active implementation PR: `#34 — DS2-INV-001: establish Inventory stock list V2 presentation`
- PR base: `design-system-v2-development`
- Exact PR base SHA: `61c2fcac8152550d72f4b94be5e85fd9979dd94d`
- Exact PR HEAD reviewed: `9f3a2c4237b233bad468fa766971558caa09a5d6`
- Live PR state at review: `OPEN / DRAFT / mergeable`
- Changed-file scope: 6 files (Inventory presentation/tests, live `StockPage` wiring/parity test, workstream/UI implementation state)
- Current disposition: `AGENT-REVIEW: BLOCKED`
- Blocking severity: `P2`
- Evidence: `TESTS_AUTHORED_NOT_EXECUTED`; `SOURCE_REVIEW_PASS` is withheld while the Device/Accessibility gate below remains open.
- Exact-head runtime/build evidence: not claimed.

## Independent QA disposition

**BLOCKED on exact HEAD `9f3a2c4237b233bad468fa766971558caa09a5d6` for one bounded Tablet pagination defect.**

The Inventory collection migration is otherwise strong and directionally correct: one `ResponsiveCollection<Stock>` replaces CSS-hidden duplicate device trees; Desktop retains the dense paged `DataTable`; Tablet becomes a deliberate two-column card surface; Mobile becomes a one-column operational card surface; `StockBalanceCard` composes shared `Card + KeyValueList + StatusBadge`; stock/query/filter/permission/valuation/review calculations remain page-owned.

The current candidate cannot receive GREEN-DEV yet because the newly introduced Tablet renderer copies the legacy numbered pagination markup with raw `.pagination-btn` controls. The existing shared CSS defines those controls as exactly `32px × 32px`, while Tablet touch remains first-class under the North Star. The previous/next controls also expose only `‹` / `›` as their accessible text and the active page is communicated only through the `.active` class/color rather than `aria-current="page"`.

This is not a request to build a full shared Pagination system in this slice. Shared Pagination convergence may remain a later WATCH. The blocker is narrower: the new V2 Tablet composition itself must not ship with sub-touch-target, weakly-labelled page controls.

## Scope / functional isolation — PASS

The exact compare is bounded to:

- `src/components/inventory/StockListPresentation.tsx`
- `src/components/inventory/StockListPresentation.test.tsx`
- `src/pages/inventory/StockPage.tsx`
- `src/pages/inventory/StockPage.v2.test.ts`
- `docs/design-system-v2/31_AGENT_TEAM_WORKSTREAM.md`
- `team/design-system-v2/UI_IMPLEMENTATION_STATE.md`

No DB, migration, RPC, service, query/cache, RBAC/RLS, permission definition, route guard, workflow semantic, business calculation, validation, deployment, preview or `main` file is changed.

The existing `useStock` query shape, `pageSize: 25`, page reset, low-stock search suppression, warehouse/status filters, stock-health/minimum-stock logic, `finance.view_costs` gate, local-only review mode, Product/Warehouse links and valuation semantics remain page/domain-owned.

## System fit / design quality — PASS except the Tablet pagination blocker

- `ResponsiveCollection` is the correct single device boundary; hidden duplicate interaction trees are removed.
- `StockBalanceCard` is a thin Inventory-domain composition over established V2 surfaces rather than a new generic primitive.
- Shared `StatusBadge` replaces local list-status Badge usage without moving stock-status truth.
- Long product identity is allowed to wrap and logical spacing is RTL-safe.
- Desktop information density is preserved.
- Tablet keeps authorized weighted cost + total value and direct page-jump capability.
- Mobile preserves its compact paged-query behavior and uses shared `Button touchTarget` for previous/next actions.

`WATCH`, non-blocking: the codebase still lacks a shared numbered Pagination pattern. Do not broaden PR #34 into a global Pagination convergence task merely to clear this review; fix the current Tablet controls locally through existing shared Button/touch semantics or an equivalently bounded treatment, then leave full convergence for the dedicated component-depth slice.

## Device / state review

### Desktop — PASS

Dense `DataTable` comparison/review remains intact, including review columns, cost/value columns and numbered pagination.

### Tablet — BLOCKING P2

Location: `src/pages/inventory/StockPage.tsx`, `renderCardPagination('tablet')`.

The new Tablet path renders raw `.pagination-btn` elements. Current shared legacy CSS in `src/styles/components.css` defines `.pagination-btn { width: 32px; height: 32px; }`. That is below the V2 touch target expected for touch-first Tablet interaction. In addition:

- previous/next buttons have only symbol text (`‹` / `›`) and no explicit accessible label;
- the current page uses only `.active` styling and does not expose `aria-current="page"`;
- the focused source test currently asserts the legacy pagination class/algorithm but does not protect Tablet touch/accessibility semantics.

Minimum required correction:

1. preserve the same page/query/direct-jump behavior;
2. make every Tablet pagination control touch-safe (44px minimum target, preferably through existing shared `Button` + `touchTarget` where practical);
3. give previous/next controls explicit accessible names;
4. expose the selected numeric page with `aria-current="page"` (or an equivalent complete pagination-current semantic);
5. update the focused test artifact so the corrected Tablet interaction contract is protected rather than locking the legacy 32px markup.

No query, pagination algorithm, new shared framework or business change is required.

### Mobile — PASS

One-column stock cards retain the existing numbered-page query semantics via shared touch-safe previous/next Buttons. No ordinary horizontal overflow is introduced.

### Loading / empty / permission / review — PASS at source level

- loading/empty are mutually exclusive through shared `ResponsiveCollection` / `StatePanel`;
- cost/value card fields remain page-gated by `finance.view_costs`;
- Tablet retains former table valuation visibility for authorized users;
- Mobile does not gain total stock value and preserves weighted-cost visibility conditions;
- review input is controlled, explicitly labelled and at least 44px high;
- local review remains no-save/no-adjustment and comparison math remains page-owned.

## Test / execution evidence

Focused tests exist for card identity/status hierarchy, permission-controlled valuation, controlled review input/callback, one responsive collection boundary, device renderers, query/filter/page-reset truth, pagination capability, review math, links and shared presentation wiring.

Evidence for exact HEAD `9f3a2c4237b233bad468fa766971558caa09a5d6` is **`TESTS_AUTHORED_NOT_EXECUTED`**.

No approved local runtime executed `npm test`, `npm run build` or `npm run lint`; no GitHub Actions/hosted CI or Vercel was used. No known TypeScript/build failure is visible from source review, but no executed PASS is claimed.

The test-artifact gate remains materially incomplete only for the blocking Tablet pagination interaction contract described above.

## Peer-state comparison / contradiction handling

The independent exact-head judgment above was formed from the PR diff/current product contracts first, then compared with peer state:

- **UI Production Engineer:** current PR-branch state is fresh and explicitly treats shared Pagination convergence as deferred while considering Tablet direct-jump parity sufficient. QA agrees that global convergence may remain deferred, but disagrees that the current Tablet controls meet the V2 interaction bar. Because the new renderer uses 32×32 touch targets and lacks explicit previous/next/current-page semantics, this is a **BLOCKING contradiction** limited to the Tablet pagination treatment.
- **Product Design Director:** Development role state still targets the already-completed Sales slice and is stale for PR #34; no fresh Inventory-specific contradiction exists yet.
- **Development Integrator:** current state correctly requires a fresh exact-head QA result for the Inventory slice; with this BLOCKED result it must remain `NO_MERGE`.
- **Team Memory / Workstream:** Development-side shared memory still shows DS2-INV-001 as READY because the implementation handoff lives on the feature PR. This is expected state lag, not a product contradiction.

## Runtime / release boundary

This review does not claim exact-head local build/test execution, manual preview build, runtime visual/device acceptance, release readiness or permission to merge Development into `main`.

## Cross-role handoff

- **To:** UI Production Engineer, Product Design Director, Development Integrator
- **What changed:** Design QA independently reviewed PR #34 exact HEAD `9f3a2c4237b233bad468fa766971558caa09a5d6`. Scope isolation, Inventory behavior parity, shared collection/card/status composition, Desktop density, Mobile behavior and state handling pass at source level. GREEN-DEV is blocked only because the new Tablet pagination uses legacy 32×32 raw buttons with weak previous/next/current-page accessibility semantics.
- **Preserve:** exact stock/query/filter/page/valuation/permission/review/link behavior; Tablet direct page jumps; Desktop dense table; Mobile compact paging; bounded Inventory-list scope; no CI/Vercel/main/backend drift.
- **Need from you:** UI Production Engineer should harden only the Tablet pagination interaction boundary (44px touch targets, explicit previous/next names, current-page semantic) and update the focused test, then hand off one new stable exact HEAD. Product Design Director should treat global shared Pagination convergence as optional future work, not required scope expansion. Integrator remains `NO_MERGE` until the corrected exact HEAD is re-reviewed.
- **Blocker level:** `BLOCKING` — P2 Tablet touch/accessibility gate only.
- **Baseline:** Development `61c2fcac8152550d72f4b94be5e85fd9979dd94d`; PR #34 HEAD `9f3a2c4237b233bad468fa766971558caa09a5d6`.
