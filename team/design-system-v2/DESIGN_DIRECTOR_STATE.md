# Design Director State

## Reviewed baseline

- Review date: `2026-09-17`
- Development branch: `design-system-v2-development`
- Exact Development HEAD independently inspected: `45cf7998c90254e022258d91a6debfe7179d935d`
- Product UI integrated through: `DS2-FIN-001`
- Current single READY slice: `DS2-FIN-002`
- Open implementation PRs targeting Development at review: none.
- Current Product Design disposition: `READY — FIN002 BOUNDED TO PAYMENT RECEIPT TRANSACTION-DETAIL HEADER/ACTION FOUNDATION`
- Evidence level: source inspection only; no build/test/lint/runtime/preview PASS claimed.

## Independent professional judgment

**The smallest dependency-safe FIN002 concern is the live `PaymentReceiptDetail` transaction header and review-action surface, not a broad Finance detail-page rewrite.**

`PaymentReceiptDetail` is the strongest representative next proof because it already contains real Finance status, amount/context, output tools, guarded confirm/reject actions and two existing responsive review modals, while the current top-of-page composition is still a local mini-system: ad-hoc sticky header styles, generic `Badge` for workflow status, a local back button, and a peer action row outside the already-proven shared `TransactionHeader + AppAction + resolveActionSet` grammar.

The shared `TransactionHeader` is already integrated and proven in Sales. Reusing it here advances one cross-module product language without moving any financial eligibility, posting, receipt confirmation/rejection or destination-selection truth into presentation.

The rest of the receipt page is intentionally not pulled into this slice. The page still has local `SectionHead` / `InfoRow` / card styling, proof/evidence presentation, amount hero and review-modal composition debt, but migrating all of that now would turn a safe representative concern into a broad Finance detail redesign.

## DS2-FIN-002 READY boundary

### Implement in one PR only

1. **Thin Finance adapter over shared `TransactionHeader`** for `PaymentReceiptDetail`.
   - Keep receipt number as the transaction identity.
   - Keep customer + created-at context as subtitle/context; preserve existing links and date formatting.
   - Use shared `StatusBadge` for `pending / confirmed / rejected` with the existing Arabic labels and semantic tones; status mapping remains Finance-owned.
   - Use shared `Button` for the back action with RTL-native cue and touch-safe target.

2. **Canonical review actions through `AppAction + resolveActionSet`.**
   - Preserve the existing page-owned predicates exactly: `isSelfCashCustody`, `isAdmin`, `canConfirm`, receipt `pending` state and `finance.payments.confirm` permission.
   - Preserve the existing callbacks exactly: confirm opens the current confirm modal; reject opens the current reject modal and clears the current rejection reason as it does today.
   - Confirm remains the primary operational review action when it exists; reject remains destructive and only exists for the current admin predicate.
   - Mobile: max one direct review action; Tablet: max two; Desktop: shared registry limits apply. Any additional authorized review action remains in shared overflow rather than disappearing.

3. **Keep `DocumentActions` as output tooling, not Finance review eligibility.**
   - Pass the existing `DocumentActions kind="payment-receipt" entityId={receipt.id}` through the header tools slot without changing its capability logic or output behavior.
   - Do not duplicate print/PDF capabilities inside `AppAction`.

4. **Focused source/test protection.**
   - Finance status mapping -> `StatusBadge` semantic tone/label.
   - Existing action predicates/callback wiring remain page-owned and unchanged.
   - Mobile/Tablet placement is resolved by the shared action registry, not page-local breakpoints.
   - `DocumentActions` remains present as output tooling.
   - Back navigation still targets `/finance/payments`.

### Explicit exclusions

Do **not** include in FIN002:

- `getPaymentReceipt`, `confirmPaymentReceipt`, `rejectPaymentReceipt` service/query semantics;
- the direct custody lookup/query or self-cash-custody rule;
- vault filtering, destination selection, cheque/custody handling, validation, invalidation or toast behavior;
- confirm/reject modal field/content/action redesign;
- receipt amount calculation/formatting or the current amount hero;
- proof image/PDF/file rendering or upload/output subsystem changes;
- local detail cards / `SectionHead` / `InfoRow` convergence, financial summary patterns, timelines or audit redesign;
- Payments list migration, statements, journals, ledger, expenses, approval rules, reports or broad Finance framework work;
- DB/migration/RPC/RBAC/RLS/route/cache/business/accounting/posting/workflow changes;
- Vercel, preview branches, GitHub Actions or `main`.

## Device / state / accessibility acceptance

- **Mobile (`<=768px`):** sticky transaction identity/status remains readable with long Arabic customer names and mixed Latin receipt number; one direct review action maximum; secondary authorized review action goes to accessible RTL overflow; back and action controls remain practical 44px targets; no horizontal header overflow.
- **Tablet (`769–1024px`):** deliberate wrapped transaction header with up to two direct review actions; tools remain secondary to review action hierarchy.
- **Desktop (`>=1025px`):** preserve efficient review by exposing eligible actions through the shared header without changing the existing body/modal workflow. This slice does not claim to solve the page's broader 640px body-density debt.
- **RTL / Arabic:** back direction, receipt number directionality, Arabic status labels, customer/date wrapping and overflow placement must remain correct.
- **Loading / not found:** preserve the existing loading skeleton and not-found behavior exactly; do not force the shared header into states where no receipt exists.
- **Permission / workflow:** no unauthorized confirm/reject action appears; no authorized action disappears.
- **Accessibility:** shared button labels/focus/touch semantics apply; header has a meaningful banner label; status meaning is text + semantic tone, not color-only.

## System-pattern intent

FIN002 is a cross-module reuse proof: Sales and Finance transaction detail headers should consume the same `TransactionHeader` and canonical action-placement grammar while each domain keeps its own status vocabulary, permissions, workflow eligibility and callbacks. If the implementation needs a Finance-specific action model or business-aware shared primitive, stop and mark BLOCKED instead.

This slice is intentionally a header/action foundation, not a declaration that the entire Payment Receipt detail page is migrated. Remaining local detail-card, evidence, amount-summary and modal composition debt stays visible for later Finance/global convergence.

## Peer-state comparison / freshness synthesis

After forming the judgment above, I compared the current repository states:

- **Team Memory / Integrator:** current integrated truth is FIN001 DONE and FIN002 is the sole READY slice. This state is current and aligned.
- **UI Production Engineer:** its latest state describes the already-merged FIN001 feature head and is consumed/stale for FIN002; there is no current implementation PR.
- **Design QA:** its GREEN-DEV record targets merged FIN001 exact head and is consumed for FIN002; no approval is carried forward.
- **Previous Design Director state:** the FIN001 BLOCKING record was stale after PR #38 corrections/merge and is superseded by this state.
- **No material contradiction:** there is no current BLOCKING peer-state disagreement for FIN002.

## What changed since previous state

FIN001 has been integrated and its prior Director blocker is consumed. FIN002 is now explicitly bounded from the exact latest Development baseline to `PaymentReceiptDetail` header/review-action convergence only, with the rest of Finance detail presentation held outside the implementation slice.

### Cross-role handoff
- **To:** UI Production Engineer, Design QA, Development Integrator
- **What changed:** `DS2-FIN-002` is now dependency-safe and explicitly bounded to the `PaymentReceiptDetail` transaction header/status/review-action foundation using shared `TransactionHeader + StatusBadge + AppAction/resolveActionSet`; no implementation PR is currently open.
- **Preserve:** every payment receipt query/service, self-custody/admin predicate, confirm/reject callback and modal, destination/vault rule, output capability, invalidation/validation/toast/route/accounting/posting/workflow semantic; keep loading/not-found behavior unchanged.
- **Need from you:** UI Production Engineer should open exactly one FIN002 PR from the latest Development HEAD and implement only this bounded concern + focused tests; Design QA should review the stable exact PR HEAD independently; Integrator remains no-op until exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` exists.
- **Blocker level:** `NONE`.
- **Baseline:** Development `45cf7998c90254e022258d91a6debfe7179d935d`; active PR: none.
