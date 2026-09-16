# Design QA State

## Reviewed baseline

- Review date: `2026-09-16`
- Development branch: `design-system-v2-development`
- Exact Development HEAD inspected before review: `27437916d5afd047e794dd5bf86a2ddbf2becbdb`
- Active slice: `DS2-INV-002 — Transfer/adjustment operational flows`
- Active implementation PR: `#35 — DS2-INV-002: establish transfer flow V2 presentation`
- PR base: `design-system-v2-development`
- Exact PR base SHA: `27437916d5afd047e794dd5bf86a2ddbf2becbdb`
- Exact PR HEAD reviewed: `69a18c6a6abe4cdecc17156877a766a83e152517`
- Live PR state at review: `OPEN / DRAFT / mergeable`
- Changed-file scope: 4 files (new transfer presentation + focused test + workstream/UI implementation state)
- Current disposition: `AGENT-REVIEW: BLOCKED`
- Blocking severity: `P2 — incomplete live integration / review-completeness gate`
- Source evidence: `SOURCE_REVIEW_PASS` **withheld** because the live operational surface is not wired on this HEAD.
- Test evidence: `TESTS_AUTHORED_NOT_EXECUTED`
- Exact-head runtime/build evidence: not claimed.

## Independent QA disposition

**BLOCKED on exact HEAD `69a18c6a6abe4cdecc17156877a766a83e152517`.**

The new `TransferCard` foundation is directionally correct and fits the existing V2 grammar: it composes shared `Card + KeyValueList + StatusBadge + Button`, keeps transfer number/direction/status/warehouse/date as presentation inputs, accepts page-owned actions rather than inferring workflow truth, and uses an explicit touch-safe detail action instead of making the neutral Card itself interactive.

However, the PR is not yet review-complete. `src/pages/inventory/TransfersPage.tsx` is absent from the diff. The live page therefore still owns the legacy CSS-switched `.tr-table-view` / `.tr-card-view` trees, page-local Mobile card markup, and duplicated ship / approve-and-ship / receive / cancel eligibility rendering. Because the new card is not used by the live operational surface, QA cannot verify the required Mobile/Tablet/Desktop renderer selection, workflow-action parity, loading/empty/pagination parity or real system-fit of the migration.

This is an implementation-completeness blocker, not a request for broader redesign.

## Scope / functional isolation — PASS for current foundation

Current PR scope is bounded to:

- `src/components/inventory/TransferListPresentation.tsx`
- `src/components/inventory/TransferListPresentation.test.tsx`
- `docs/design-system-v2/31_AGENT_TEAM_WORKSTREAM.md`
- `team/design-system-v2/UI_IMPLEMENTATION_STATE.md`

No DB, migration, RPC, service, query/cache, RBAC/RLS, permission definition, route guard, stock movement, reservation, approval, validation, workflow, deployment, preview or `main` file is changed.

The new presentation component contains no business calculations or workflow eligibility logic.

## System fit / design quality — partial PASS, live proof incomplete

### Foundation that passes source review

- Thin Inventory-domain composition over shared V2 patterns rather than a new primitive family.
- Status and direction semantic tones remain caller/page supplied.
- Transfer number is explicit LTR and long-value tolerant through `overflowWrap: anywhere`.
- Warehouse/date metadata uses shared `KeyValueList` and deliberate 3-column Tablet / 1-column Mobile density.
- Detail navigation uses shared `Button + touchTarget` with an explicit accessible name.
- Status/direction meaning is textual, not color-only.
- Action group appears only when page-owned actions/detail entry exist.

### Blocking completeness gap

The current exact HEAD does not modify `TransfersPage`, so the intended V2 boundary is not active. The North-Star requirement of responsive composition rather than responsive hiding cannot be verified until the live page moves to a single `ResponsiveCollection<StockTransfer>` boundary.

On the unchanged live page, the important business contracts that must be preserved during wiring include:

- `useTransfers` query/filter/page behavior and `pageSize: 25`;
- Desktop dense table and expanded item/cost review behavior;
- `finance.view_costs` visibility;
- `inventory.read_all` / warehouse ownership / creator ownership checks;
- pending push + source manager => ship;
- pending pull + source manager => approve-and-ship;
- in-transit + destination manager + `approved_by !== userId` => receive;
- pending + creator => cancel;
- in-transit + source manager => cancel;
- confirmation-dialog behavior and callbacks;
- transfer detail navigation;
- create modal and all stock/reservation/service/validation semantics.

These contracts are still present in the live source, but parity cannot be accepted until the new renderer is wired and focused tests protect the live composition.

## Device / state / accessibility review

### Desktop

`WATCH / not yet reviewable in migrated form.` The required target is to preserve the current dense table, expanded item rows and authorized cost visibility exactly.

### Tablet

`BLOCKED by incomplete wiring.` The new card has an intentional Tablet metadata density and touch-safe detail action, but there is no live Tablet renderer on this HEAD. The eventual wiring must not inherit the old binary Mobile/Desktop CSS split.

### Mobile

`BLOCKED by incomplete wiring.` The card foundation improves interaction semantics by avoiding a generic clickable Card and exposing a real detail button, but the legacy live Mobile tree remains unchanged and duplicated.

### Loading / empty / pagination / permission / destructive states

Not yet reviewable through the new V2 boundary. They remain page-owned in the unchanged live page. Exact preservation must be proven at wiring time.

## Test / execution evidence

Current focused component tests protect:

- transfer identity / warehouse / date composition;
- page-supplied status and direction semantic tones;
- page-owned injected workflow actions;
- explicit detail callback and accessible name;
- absence of invented actions when none are supplied.

Evidence is **`TESTS_AUTHORED_NOT_EXECUTED`**.

No approved local runtime executed `npm test`, `npm run build` or `npm run lint`; no GitHub Actions/hosted CI or Vercel was used. No executed PASS is claimed.

Before GREEN-DEV, focused tests must also protect the live renderer selection and material action/permission/state/pagination parity introduced by the `TransfersPage` wiring.

## Peer-state comparison / contradiction handling

The independent source judgment above was formed from the exact PR diff and live `TransfersPage` contracts first, then compared with peer state:

- **UI Production Engineer:** feature-branch state is fresh and explicitly says `IN_PROGRESS`; it identifies live `ResponsiveCollection` wiring as the next step and already preserves the same business invariants. This aligns with QA; there is no design contradiction.
- **Product Design Director:** Development-side state still targets the completed INV001 candidate and is stale for INV002. Team Memory/Workstream direction nevertheless requires the next slice to remain a bounded transfer/adjustment presentation concern, which this PR does.
- **Development Integrator:** its consumed INV001 state says the next slice must remain presentation-only and no merge may occur without a fresh exact-head GREEN review. Current PR must remain `NO_MERGE`.
- **Team Memory / Workstream:** Development marks DS2-INV-002 as the single next slice; the feature branch advances it to IN_PROGRESS. No second slice should start.

No peer-state `BLOCKING` contradiction exists; the blocker is simply incomplete implementation on the reviewed HEAD.

## Minimum required fix

Keep the correction inside the already-declared collection slice:

1. Wire only the live `TransfersPage` collection region to one `ResponsiveCollection<StockTransfer>` boundary.
2. Preserve the existing dense Desktop table plus expanded item/cost review behavior.
3. Use `TransferCard` for deliberate Tablet/Mobile composition with touch-safe controls and no ordinary overflow.
4. Centralize only page-owned action rendering; preserve exact ship / approve-and-ship / receive / cancel predicates and callbacks, including ownership and `approved_by !== userId` guards.
5. Preserve query/filter/pageSize/pagination, loading/empty states, create modal, confirmation flow, routes, service calls, stock/reservation and validation semantics exactly.
6. Add/update focused tests for device renderer selection and material action/permission/state/pagination parity.
7. Do not widen into Transfer Detail, Adjustments, create-flow redesign or backend/business changes.

## Runtime / release boundary

No release/runtime evidence is claimed. GitHub Actions, hosted CI and Vercel remain forbidden in the normal loop. A later GREEN-DEV would still be a Development integration decision only, not release approval.

## Cross-role handoff

- **To:** UI Production Engineer, Development Integrator, Product Design Director
- **What changed:** Design QA independently reviewed PR #35 exact HEAD `69a18c6a6abe4cdecc17156877a766a83e152517`. The new `TransferCard` foundation is system-fit, but the live `TransfersPage` is not yet wired, so the candidate is `AGENT-REVIEW: BLOCKED` on a P2 implementation-completeness gate and cannot receive `SOURCE_REVIEW_PASS` / `GREEN-DEV` yet.
- **Preserve:** every transfer query/filter/page/permission/ownership/action/confirmation/create/stock/reservation/service/validation/route contract; dense Desktop review behavior; bounded collection-only scope; no CI/Vercel/main/backend drift.
- **Need from you:** UI Production Engineer should complete only the declared live `ResponsiveCollection` wiring and focused parity tests, then hand off one stable exact HEAD for fresh QA. Integrator remains `NO_MERGE` until that moved HEAD receives fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- **Blocker level:** `BLOCKING` — P2 implementation completeness only.
- **Baseline:** Development `27437916d5afd047e794dd5bf86a2ddbf2becbdb`; PR #35 HEAD `69a18c6a6abe4cdecc17156877a766a83e152517`.
