# Design Director State

## Reviewed baseline

- Review date: `2026-09-17`
- Development branch: `design-system-v2-development`
- Exact Development HEAD independently inspected before this state write: `1314f5c63ab5ffb996c3b3177de584f7cb70fd88`
- Current Development drift from the FIN001 slice baseline is governance-only: `dcee85d8b23488bcf3339a0db4818e95b78ba148 -> 1314f5c63ab5ffb996c3b3177de584f7cb70fd88` changes only `team/design-system-v2/DESIGN_QA_STATE.md`.
- Active slice: `DS2-FIN-001 — Finance lists and summaries`
- Active implementation PR: `#38 — DS2-FIN-001: establish vault overview V2 presentation`
- PR base: `design-system-v2-development`
- Slice baseline / PR base SHA: `dcee85d8b23488bcf3339a0db4818e95b78ba148`
- Exact PR HEAD independently inspected: `96cc3c4f76b4f8ab506b40b7623759a50c8f0816`
- PR state at review: `OPEN / DRAFT`; live PR metadata currently reports `mergeable: false`, which is not treated as a design conclusion and must be re-evaluated after the blocked product head moves.
- Current Product Design disposition: `BLOCKED — FIN001 VAULT OVERVIEW INCOMPLETE + SEMANTIC-TONE + MOBILE/TABLET ACTION-HIERARCHY P2`
- Evidence level: source inspection only; `TESTS_AUTHORED_NOT_EXECUTED`; no runtime/build/lint/preview PASS claimed.

## Independent professional judgment

**The chosen FIN001 boundary is correct: `VaultsPage` is an appropriate smallest representative Finance surface, and the new shared `MetricGrid` is a sound system addition. PR #38 is not yet acceptable for integration because the live page is not wired and the current card adapter would carry two avoidable Finance mini-system defects into V2: semantic coloring of categorical metadata and an unbounded Mobile/Tablet action cluster.**

I formed this judgment from the exact PR source/diff plus the unchanged live `VaultsPage` before comparing peer conclusions.

The positive architecture is worth preserving:

- `MetricGrid` owns layout only and gives `3 Desktop / 2 Tablet / 1 Mobile` for this summary without absorbing financial meaning or calculations.
- `VaultSummary` / `VaultCard` are thin Finance-domain compositions over shared `StatCard`, `Card`, `KeyValueList`, `Badge`, `StatusBadge` and `Button`.
- Finance calculations, balances, permissions, opening-balance eligibility, service/query/cache behavior and modal workflows remain page/domain-owned on the reviewed head.
- The slice remains narrow enough to prove summary + collection + action grammar without entering posting, ledger or accounting semantics.

## Blocking P2 corrections on the same PR

### 1. Live `VaultsPage` wiring / device-state completeness

`src/pages/finance/VaultsPage.tsx` is absent from the current PR diff. The live surface therefore still mounts the legacy Desktop DataTable tree and separate Mobile card tree, toggled by CSS, with no deliberate Tablet renderer and no single `ResponsiveCollection<Vault>` boundary.

The same PR must wire the live overview to:

- `VaultSummary` for the existing three page-owned values;
- one `ResponsiveCollection<Vault>` capability boundary;
- dense Desktop DataTable parity;
- deliberate two-column Tablet cards when the available width supports that composition;
- one-column Mobile operational cards;
- the existing loading, empty and create-action behavior.

Focused live-page protection must prove renderer selection, state composition and permission/action parity.

### 2. Semantic tone must remain system-owned, not inferred from Finance categories/counts

The exact PR adapter exposes `typeVariant` and the focused test explicitly locks `cash -> badge-success` while describing vault type as categorical metadata. That is a direct semantic contradiction. `cash`, `bank` and `mobile_wallet` are categories, not success/info/primary states.

Required correction:

- Vault type uses neutral generic `Badge` treatment only; remove/constrain the semantic `typeVariant` escape hatch.
- Active/inactive remains semantic `StatusBadge`.
- `VaultSummary` must not hardcode `tone="success"` for `activeCount`. The adapter's own contract says tone decisions are caller-owned, and the live legacy summary does not assign success meaning to that factual count. Keep the count neutral unless a page-owned semantic reason is explicitly supplied.
- Existing page-owned positive/negative balance emphasis may remain; do not invent new finance meaning.

### 3. Mobile/Tablet vault actions require canonical priority + overflow

The exact adapter renders every supplied callback as a peer-visible Button. The live page predicates make the worst case source-provable: a user with `finance.vaults.transact` + `finance.vaults.update` on a zero-balance vault can receive **five simultaneous actions** — statement, opening balance, deposit, withdrawal and edit.

That is below the North Star for Mobile/Tablet action clarity even if every button is individually touch-safe. It also recreates placement logic outside the already-integrated action grammar.

Required correction is presentation-only and bounded to the same PR:

- keep every existing permission predicate, callback and opening-balance rule exactly page-owned;
- express eligible card actions through the canonical `AppAction` / `resolveActionSet` semantics, or the smallest shared renderer consuming that same contract — **do not create a Finance-specific parallel action model**;
- Mobile: at most one direct visible action, remaining authorized actions in an accessible, touch-safe RTL overflow;
- Tablet: at most two direct visible actions, remaining authorized actions in overflow;
- Desktop DataTable may retain its current dense direct action presentation in this slice;
- no authorized action may disappear, and no new business priority/eligibility rule may be invented merely to style the card.

This is not a request for a global CommandBar rewrite. It is the minimum system-fit correction needed so the first Finance card proves the existing V2 action language rather than normalizing a five-button mobile cluster.

## Functional isolation / truths to preserve

Do not alter:

- `totalBalance`, `activeCount`, per-vault balances or any calculation;
- `finance.vaults.create`, `finance.vaults.transact`, `finance.vaults.update` predicates;
- opening-balance eligibility `current_balance === 0`;
- statement paging (`pageSize: 25`) or statement loading semantics;
- create/update/manual adjustment/transfer services, invalidation, validation or toast behavior;
- statement, create/edit, deposit, withdrawal, opening-balance or transfer modal workflows;
- routes, queries, cache semantics, accounting/posting truth, DB/RPC/RBAC/RLS or backend contracts.

Do not broaden FIN001 into Finance forms, statements redesign, transaction modals, ledger/journal work, reports/charts, or a speculative financial framework.

## Device / state / accessibility acceptance after correction

- **Desktop:** three-metric summary remains dense and legible; the DataTable preserves name/type/balance/branch/responsible/status/action comparison and existing direct actions.
- **Tablet:** summary caps at two columns; collection uses deliberate touch-first two-column cards; no five-button peer action row.
- **Mobile:** summary stacks to one column; vault cards prioritize identity, semantic status and balance, keep practical 44px targets, and expose one direct action + accessible overflow without horizontal scrolling.
- **RTL / Arabic:** long vault/branch/responsible names and large monetary values must wrap safely; overflow trigger/menu semantics must remain RTL-native.
- **States:** existing loading, true-empty and permission-limited create/action behavior remains equivalent; only one device interaction tree is mounted through `ResponsiveCollection`.
- **Semantic system:** vault kind is neutral category metadata; active/inactive is workflow/operational status; balance tone remains caller/page-owned.

## Director synthesis after peer-state comparison

After forming the judgment above, I compared the repository peer states and exact PR discussion:

- **Design QA:** both exact-head blockers are valid: live wiring is incomplete and vault type semantic coloring contradicts the V2 invariant. I adopt both.
- **Design QA action-hierarchy WATCH:** I elevate this to **BLOCKING for the same FIN001 head** because the exact adapter plus live predicates already prove the five-action Mobile/Tablet case; waiting for runtime wiring would knowingly carry a page-local action cluster into the first Finance migration. The correction can reuse existing V2 action semantics without changing Finance truth.
- **UI Production Engineer:** the PR-head state correctly says the Vault overview is the intended narrow boundary and that financial predicates remain page-owned. However, its statement that vault type is neutral conflicts with the exact code/test, and its claim that touch-safe buttons are sufficient does not address multi-action priority/overflow.
- **Development Integrator:** its state is correctly consumed by the PROC002 merge and provides no FIN001 approval. It must remain `NO_MERGE` while this exact-head Director/QA block is current.
- **No durable-direction contradiction:** the corrections reinforce existing Team Memory / North Star rules; no Team Memory or Decision Log change is needed.

## Remaining non-blocking WATCH

- The legacy page-local smart create FAB remains broader action-orchestration debt; do not turn this FIN001 repair into a global FAB retirement unless the live wiring cannot preserve a clear create path otherwise.
- Finance form/modal field convergence is later work.
- Runtime visual stress for dark mode, large currency values, long Arabic content and browser overflow remains milestone/release evidence and is not claimed from source.
- PR mergeability must be rechecked after a corrected head exists; do not create governance-only SHA churn solely to chase the current mergeability flag.

## What changed since previous state

PROC002 is already integrated and the previous Director state was stale. FIN001 is now active on PR #38. This state validates the Vault overview as the correct narrow Finance boundary, accepts shared `MetricGrid`, adopts QA's two P2 blockers, and adds one system-fit requirement: the source-proven five-action Mobile/Tablet card cluster must converge on the existing canonical action-priority/overflow grammar before Finance establishes it as precedent.

### Cross-role handoff
- **To:** UI Production Engineer, Design QA, Development Integrator
- **What changed:** Product Design Director validates the `VaultsPage` overview as the correct FIN001 boundary but blocks PR #38 exact HEAD `96cc3c4f76b4f8ab506b40b7623759a50c8f0816` until live `ResponsiveCollection` wiring, neutral category/summary tone ownership, and canonical Mobile/Tablet action priority + overflow are corrected on the same PR.
- **Preserve:** all vault balances/calculations, permissions, `current_balance === 0` opening rule, callbacks/modal flows, statement paging, services/query/cache/validation/routes/accounting truth; keep `MetricGrid` presentation-only and Desktop review density intact.
- **Need from you:** UI Production Engineer should make only these bounded overview corrections + focused parity/action/semantic tests on PR #38; Design QA must independently review the moved exact HEAD; Integrator remains `NO_MERGE` until fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` and normal gates pass.
- **Blocker level:** `BLOCKING`.
- **Baseline:** Development `1314f5c63ab5ffb996c3b3177de584f7cb70fd88`; PR #38 exact reviewed HEAD `96cc3c4f76b4f8ab506b40b7623759a50c8f0816`.
