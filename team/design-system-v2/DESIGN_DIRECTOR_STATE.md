# Design Director State

## Reviewed baseline

- Review date: `2026-09-16`
- Development branch: `design-system-v2-development`
- Exact development HEAD independently inspected before this state write: `267d6a894d06f8cae12add7e7dc86f94f96a9477`
- Active slice: `DS2-UI-005 — Sales transaction detail V2`
- Active Draft PR: `#32 — DS2-UI-005: establish Sales transaction detail V2 header pattern`
- Feature branch: `ds2/sales-order-detail-v2`
- Slice baseline / merge-base with current Development: `8a0c34751344ca466754d06980093c501b536cd9`
- Exact current PR HEAD independently reviewed: `3f370e02d60bbf6dfa5978c1dadc2f9454210f08`
- Live PR state: `OPEN / DRAFT / mergeable`
- Current disposition: `BLOCKED — exact PR HEAD still contains the preview-proven TypeScript failures already fixed on Development`
- Current evidence: `TESTS_AUTHORED_NOT_EXECUTED`; no `SOURCE_REVIEW_PASS` may be carried onto this exact head while the known type failure remains.

## Independent professional judgment

**THE DESIGN / ACTION ARCHITECTURE IS NOW SOUND. DO NOT REDESIGN THE SLICE AGAIN. THE ONLY CURRENT BLOCKER IS BASELINE FRESHNESS AGAINST A REAL BUILD FIX.**

I independently re-reviewed the current PR rather than carrying forward the prior Director blocker.

The earlier architecture objection is resolved. `TransactionHeader` now consumes the canonical shared `AppAction[]` contract, resolves placement through `useDeviceMode()` + `resolveActionSet()`, and renders the established one-visible Mobile / two-visible Tablet / four-visible Desktop action hierarchy with overflow. The live Sales page owns action eligibility/callback truth and the shared header owns presentation. That is exactly the system direction required by the Component Decision Matrix and North Star.

The live `SalesOrderDetail.tsx` wiring also remains correctly bounded. Existing edit / confirm / deliver / due-date / return / copy / cancel predicates stay page-owned; `DocumentActions` is preserved as a separate tools capability; only the legacy local hero/status/action presentation was replaced. Financial summary, receipts, items, notes, modals, queries, services and calculations remain outside this slice.

The current candidate is nevertheless not integratable because its branch still carries source that the owner-requested manual preview proved cannot pass `tsc -b`. This is not a speculative QA concern:

- PR HEAD still uses unsupported jest-dom matcher typings (`toBeInTheDocument`, `toHaveAttribute`, `toBeDisabled`) in the Sales Order form / Stepper tests while the package does not include the corresponding jest-dom typing extension;
- PR HEAD still has the pre-fix Customer detail conditional-tab inference that widened `value` beyond `CustomerDetailTab`;
- current Development contains the already-reviewed three-file hotfix for those exact failures;
- Git comparison from PR HEAD to current Development shows only those three code fixes plus specialist-state documentation on the Development side.

Therefore the correct next move is a narrow branch synchronization, not another design iteration.

## Current architecture / product-system fit

- **TransactionHeader as first Sales-detail pattern:** PASS.
- **Canonical ActionRegistry reuse:** PASS. No parallel action taxonomy remains.
- **Mobile progressive disclosure:** PASS at source level — one visible workflow action plus overflow.
- **Tablet action density:** PASS at source level — up to two visible actions plus overflow.
- **Desktop review density:** PASS at source level — up to four visible actions before overflow.
- **Shared Button / semantic status reuse:** PASS.
- **RTL / Arabic wrapping / logical spacing:** PASS at source level.
- **Action accessibility boundary:** PASS directionally — labelled action group plus native disclosure; no incomplete menu ARIA is invented.
- **Live Sales functional isolation:** PASS at source level. Permission/status/workflow/query/service/calculation/modal truth remains page/domain-owned.
- **DocumentActions preservation:** PASS; keep it outside this bounded pattern migration.
- **Exact-head build/type gate:** BLOCKING until PR #32 inherits the already-integrated Development hotfix and receives fresh exact-head review.

## Required next correction

### P1 — synchronize the already-integrated TypeScript hotfix into PR #32

**BLOCKING for GREEN-DEV / integration; not a new product-design task.**

Minimum acceptable direction:
- merge/sync current `design-system-v2-development` into `ds2/sales-order-detail-v2` without force-rewriting the reviewed slice;
- inherit the existing fixes in:
  - `src/components/sales/SalesOrderFormPresentation.test.tsx`;
  - `src/components/ui/Stepper.test.tsx`;
  - `src/pages/customers/CustomerDetailTabs.tsx`;
- do not reimplement those fixes differently inside PR #32;
- do not broaden Sales detail scope;
- preserve the current `TransactionHeader` / `AppAction` / live page wiring exactly unless the sync creates a real merge conflict requiring evidence-based reconciliation;
- hand off one new stable exact HEAD for fresh Design QA review.

No new Vercel preview or hosted CI is required merely to clear this source-level blocker. The known failing code simply must not remain on the exact candidate HEAD.

## Peer-state comparison / freshness

After forming the independent current-source judgment above, peer positions were compared:

- **Design QA:** current state on exact head `3f370e02...` matches this judgment. It independently passes the bounded Sales header/action migration at source level and blocks only on the stale baseline's real preview-proven TypeScript failure.
- **UI Production Engineer:** its PR-branch state correctly records the completed live wiring and shared action architecture, but its earlier claim that Development drift was role-state-only became stale after hotfix merge `1f6c184...`. The Development drift now materially includes the three TypeScript-fix files.
- **Development Integrator:** its stored state targets older unwired head `9e9871f...` and is stale on completeness. Its `NO_MERGE` result remains correct, now for the stronger exact-head type-failure reason.
- **Previous Product Design Director state:** the prior ActionRegistry architecture blocker targeted old head `97b3da7c...` and is fully consumed. It must not be treated as a current contradiction.

There is no current Design System architecture disagreement. There is one objective integration blocker: exact candidate build/type cleanliness.

## Preserve

- every existing Sales detail permission/status/workflow decision and callback;
- all queries, services, calculations, modal state, invalidation, routes and business transitions;
- existing `DocumentActions` capability behavior;
- existing Sales status semantic mapping;
- canonical `AppAction` / `resolveActionSet` device-placement contract;
- Mobile-primary / deliberate Tablet / dense Desktop strategy;
- bounded header-only scope for this PR;
- one active implementation slice only;
- no GitHub Actions, hosted CI, Vercel preview, backend/business or `main` activity.

## Cross-role handoff

- **To:** UI Production Engineer, Design QA, Development Integrator
- **What changed:** Product Design Director re-reviewed PR #32 exact HEAD `3f370e02d60bbf6dfa5978c1dadc2f9454210f08`. The earlier action-architecture blocker is closed and the bounded Sales transaction-header migration is system-fit PASS at source level. The only current blocker is that this exact PR HEAD predates the three-file TypeScript hotfix already integrated on Development and therefore still contains the preview-proven build failures.
- **Preserve:** canonical `AppAction` / `resolveActionSet` architecture; current live Sales action predicates/callbacks/loading truth; `DocumentActions`; bounded header-only scope; no CI/Vercel/main or business/backend drift.
- **Need from you:** UI Production Engineer should sync current `design-system-v2-development` into the existing PR #32 branch without broadening scope, then hand off one new stable exact HEAD. Design QA should re-review that exact synced head and may issue `GREEN-DEV` / `SOURCE_REVIEW_PASS` only if no known build/type blocker remains. Integrator stays `NO_MERGE` until that fresh evidence exists.
- **Blocker level:** `BLOCKING` — exact-head known TypeScript/build failure from stale baseline; architecture/design direction itself is unblocked.
- **Baseline:** development `267d6a894d06f8cae12add7e7dc86f94f96a9477`; PR #32 HEAD `3f370e02d60bbf6dfa5978c1dadc2f9454210f08`
