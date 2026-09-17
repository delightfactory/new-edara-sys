# Design QA State

## Reviewed baseline

- Review date: `2026-09-17`
- Development branch: `design-system-v2-development`
- Exact Development HEAD inspected before this review/state write: `dcee85d8b23488bcf3339a0db4818e95b78ba148`
- Active slice: `DS2-FIN-001 — Finance lists and summaries`
- Active implementation PR: `#38 — DS2-FIN-001: establish vault overview V2 presentation`
- PR base: `design-system-v2-development`
- PR base SHA: `dcee85d8b23488bcf3339a0db4818e95b78ba148`
- Exact PR HEAD reviewed: `96cc3c4f76b4f8ab506b40b7623759a50c8f0816`
- Live PR state at disposition: `OPEN / DRAFT`
- Changed-file scope at reviewed HEAD: 7 files — shared `MetricGrid` + test, V2 surfaces CSS, Finance `VaultOverviewPresentation` + test, Workstream state, and UI Implementation state.
- Current disposition: `AGENT-REVIEW: BLOCKED`
- Test evidence: `TESTS_AUTHORED_NOT_EXECUTED`
- `SOURCE_REVIEW_PASS`: withheld while P2 blockers remain.
- Exact-head build/test/lint/runtime/preview evidence: not claimed.

## Independent QA disposition

**BLOCKED on exact HEAD `96cc3c4f76b4f8ab506b40b7623759a50c8f0816`.**

I formed this judgment from the exact PR diff, the unchanged live `VaultsPage`, the new Finance adapters, shared `ResponsiveCollection`, `StatCard`, `Badge`, `StatusBadge`, `Button`, and the already-integrated Inventory card grammar before comparing peer states.

The direction is broadly correct and functionally isolated, but the current head is not review-complete and also introduces one semantic-color contradiction that would fragment the V2 language if wired as authored.

## Exact-head findings

### P2 — implementation completeness / live responsive composition — BLOCKING

`src/pages/finance/VaultsPage.tsx` is not part of the PR diff. The live Finance surface therefore still uses:

- legacy `edara-stats-row` / `stat-card` summary presentation;
- a Desktop `DataTable` tree and a separate Mobile card tree mounted together then toggled by CSS;
- no deliberate Tablet collection composition;
- no single `ResponsiveCollection<Vault>` boundary;
- legacy Mobile card/actions rather than the new `VaultCard` adapter.

The PR body and UI Implementation state both explicitly say live wiring remains pending on this same PR. This fails the slice-completeness, Device and State gates and does not yet prove FIN001 on a live product surface.

**Minimum required fix:** on the same PR, wire the live `VaultsPage` to `VaultSummary` and one `ResponsiveCollection<Vault>` while preserving:

- dense Desktop `DataTable` information/actions;
- deliberate Tablet card composition, expected to be two-column/touch-first where the live layout supports it;
- one-column Mobile operational cards;
- existing loading, empty and create-action behavior;
- exact `finance.vaults.create`, `finance.vaults.transact`, `finance.vaults.update` permission predicates;
- opening-balance eligibility `current_balance === 0`;
- statement/deposit/withdrawal/edit callbacks and all current modal workflows;
- total/balance calculations, services/query/cache/invalidation/validation/routes unchanged.

Focused live-page tests/source contracts must protect renderer selection, permission/action parity and state composition.

### P2 — categorical type is using semantic color — BLOCKING

`src/components/finance/VaultOverviewPresentation.tsx` exposes `typeVariant` with `success | info | primary | neutral`, and the focused test explicitly locks `cash -> badge-success` while describing vault type as categorical metadata.

This conflicts with the current V2 system invariant already proven in Inventory: categorical direction/type metadata stays visually neutral; semantic success/info/warning/danger belongs to actual operational/workflow state. `active/inactive` correctly uses `StatusBadge`; vault kind should not visually impersonate success/info state.

**Minimum required fix:** keep vault type as neutral categorical `Badge` treatment and keep active/inactive on `StatusBadge`; remove or constrain the semantic `typeVariant` API and update focused coverage accordingly. Do not infer business state from vault type.

### Shared MetricGrid — source-level PASS

The new shared `MetricGrid` is appropriately presentation-only:

- requested dense Desktop columns;
- 3/4-column grids cap to 2 on Tablet `769–1024px`;
- 2/3/4-column grids collapse to 1 on Mobile `<=768px`;
- no business meaning/calculation is owned by the pattern;
- CSS uses `minmax(0, 1fr)` and shared spacing tokens.

The authored test protects the requested class/data contract, although no execution evidence exists.

### Functional isolation / scope — PASS on current diff

No DB/migration/RPC/service/query/cache/RBAC/RLS/permission/route/accounting calculation/posting/workflow-transition/validation/deployment file is changed. Current PR work is UI/Test/Governance-only.

No GitHub Actions/hosted CI, Vercel preview, `main` or deployment activity was used.

## Device / state / accessibility judgment

- **Desktop:** proposed summary density is sound, but live table parity has not yet been migrated/proven.
- **Tablet:** shared metric grid is deliberate; live Vault collection remains unimplemented and therefore not accepted.
- **Mobile:** proposed `VaultCard` uses touch-target Buttons and long-value wrapping, but live page still uses legacy cards and CSS-hidden dual trees.
- **RTL/Arabic:** new primitives use logical/shared layout and Arabic labels; no source-level bidi blocker found in the new adapters.
- **Status semantics:** active/inactive treatment is correct; vault type semantic coloring is not.
- **Loading/empty/permission:** existing live behavior remains unchanged for now, but parity must be proven when `ResponsiveCollection` wiring lands.
- **Accessibility:** native Buttons and group labels are acceptable in the adapter. Exact live renderer/focus behavior remains pending because the page is not wired.
- **Action hierarchy WATCH:** `VaultCard` can display up to five simultaneous actions (`statement/opening/deposit/withdrawal/edit`). Once real page predicates are injected, re-check Mobile/Tablet visual priority and overflow; do not let success/danger/secondary/ghost controls compete equally.

## Test / execution evidence

Evidence is **`TESTS_AUTHORED_NOT_EXECUTED`**.

Focused artifacts currently cover:

- shared MetricGrid class/column contract;
- Finance summary projection without calculation ownership;
- callback execution and omission for injected actions;
- touch-target class on rendered card actions;
- active/inactive `StatusBadge` tone.

However, current coverage also encodes the incorrect semantic coloring of categorical vault type and no live `VaultsPage` wiring tests exist yet.

No approved environment executed `npm test`, `npm run build` or `npm run lint`; no executed PASS is claimed. No known real build/type failure is recorded for this exact head.

## Peer-state comparison / contradiction handling

The independent disposition above was formed first, then compared with peer states.

- **UI Production Engineer:** its feature-head state correctly identifies the PR as `IN_PROGRESS` and says the live `VaultsPage` wiring is still pending, so QA's completeness blocker aligns with the implementer's own handoff. However, that state also describes vault type as neutral/categorical while the exact code/test lock semantic `success/info/primary` badge variants. This is a **BLOCKING implementation-state/code contradiction** until the exact source and test are aligned with the V2 invariant.
- **Product Design Director:** Development state is stale on completed PROC002 and has not yet published a Finance-specific judgment. This is a `WATCH`, not approval evidence and not a reason to expand scope.
- **Development Integrator:** current state correctly marks FIN001 as the next slice and provides no merge approval for PR #38. Integrator remains `NO_MERGE` while this QA blocker is current.
- **Team Memory / Decision Log:** functional isolation, device strategy and semantic consistency rules support the blocker; no durable decision update is required.

## Remaining WATCH / release boundary

- Mobile/Tablet action priority after real permission predicates are injected.
- Runtime visual geometry, long currency stress, dark mode and actual browser overflow remain milestone/release evidence and are not inferred from source review.
- Broader Finance forms, statements, transaction/transfer modals, posting/accounting flows and other Finance pages remain outside this bounded concern.

### Cross-role handoff
- **To:** UI Production Engineer, Product Design Director, Development Integrator
- **What changed:** Design QA independently reviewed PR #38 exact HEAD `96cc3c4f76b4f8ab506b40b7623759a50c8f0816` and blocks it on two P2 items: missing live `VaultsPage`/`ResponsiveCollection` wiring and semantic coloring of categorical vault type.
- **Preserve:** all Finance calculations/balances, permission predicates, opening-balance rule, services/query/cache, modal/workflow/validation/route truth; keep shared `MetricGrid` presentation-only and do not broaden FIN001 beyond the Vault overview.
- **Need from you:** UI Production Engineer should complete live wiring plus parity tests and neutralize vault-type presentation on the same PR; Product Design Director may validate the narrow Finance boundary without expanding it; Integrator remains `NO_MERGE`. Any moved PR HEAD requires fresh exact-head QA.
- **Blocker level:** `BLOCKING`.
- **Baseline:** Development `dcee85d8b23488bcf3339a0db4818e95b78ba148`; PR #38 exact reviewed HEAD `96cc3c4f76b4f8ab506b40b7623759a50c8f0816`.
- **Evidence:** `TESTS_AUTHORED_NOT_EXECUTED`; `SOURCE_REVIEW_PASS` withheld.
