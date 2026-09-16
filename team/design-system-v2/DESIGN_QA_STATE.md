# Design QA State

## Reviewed baseline

- Review date: `2026-09-16`
- Development branch: `design-system-v2-development`
- Exact development HEAD observed before this QA write: `1f6c184df1a5609ca47417e0287991b4c069791a`
- Active slice: `DS2-UI-005 — Sales transaction detail V2`
- Active implementation PR: `#32 — DS2-UI-005: establish Sales transaction detail V2 header pattern`
- PR base: `design-system-v2-development`
- Slice starting baseline: `8a0c34751344ca466754d06980093c501b536cd9`
- Exact PR HEAD reviewed: `3f370e02d60bbf6dfa5978c1dadc2f9454210f08`
- Live PR state at review: `OPEN / DRAFT / mergeable`
- Changed-file scope: 10 files (TransactionHeader pattern/tests, thin Sales adapter/tests, live SalesOrderDetail wiring/parity test, transaction CSS/import, workstream/UI implementation state)
- Current disposition: `AGENT-REVIEW: BLOCKED — KNOWN EXACT-HEAD BUILD/TYPE FAILURE INHERITED FROM STALE BASELINE`
- Slice evidence: `TESTS_AUTHORED_NOT_EXECUTED`; no exact-head `SOURCE_REVIEW_PASS` is issued while the known type failure remains on this PR HEAD.

## Independent QA disposition

**BLOCKED for integration on exact HEAD `3f370e02d60bbf6dfa5978c1dadc2f9454210f08`.**

The previous completeness blocker is closed. The live `SalesOrderDetail.tsx` hero/action region is now wired through the shared `SalesOrderDetailHeader` / `TransactionHeader` contract, and source review confirms that the existing edit / confirm / deliver / due-date / return / copy / cancel eligibility predicates and callbacks remain page-owned and materially unchanged.

The shared action architecture remains correct: `TransactionHeader` consumes the canonical `AppAction[]`, `useDeviceMode()` and `resolveActionSet()` contract; Mobile exposes one visible workflow action, Tablet two and Desktop up to four, with remaining eligible actions in shared overflow. `DocumentActions` remains a separate tools capability rather than being reimplemented.

However, the exact current PR HEAD is based on the pre-preview-fix development baseline and still contains a **known real TypeScript build failure** that was exposed by the owner-requested manual preview. The test policy is explicit: a known build/type failure blocks GREEN until fixed, and execution evidence from another HEAD cannot be transferred to this one.

Therefore this candidate cannot receive `GREEN-DEV` or `SOURCE_REVIEW_PASS` yet even though the DS2-UI-005 slice itself passes the bounded source/design review.

## Slice source review

### Scope / functional isolation — PASS

The PR remains presentation-only and bounded to the Sales transaction header concern:
- shared `TransactionHeader` pattern and focused tests;
- thin Sales status/header adapter and tests;
- live `SalesOrderDetail.tsx` hero/action wiring;
- focused page-level parity contract;
- transaction-specific V2 CSS and main stylesheet import;
- workstream / UI-implementation coordination state.

No DB, migration, RPC, service, query/cache, RBAC/RLS, permission definition, route guard, business calculation, workflow state, validation semantic or deployment file is changed.

### Functional parity — PASS at source level

Compared with the slice baseline, the live page preserves:
- edit: `draft + sales.orders.update`;
- confirm: `draft + sales.orders.confirm`;
- deliver: `confirmed + sales.orders.deliver`;
- due-date adjustment: existing `customers.credit.update` + delivered/partially-delivered + credit/mixed + remaining balance + delivered-at predicate;
- return: delivered/completed + `sales.returns.create`;
- copy: `sales.orders.create`;
- cancel: draft/confirmed + `sales.orders.cancel`;
- confirm warehouse cache/server fallback, default warehouse assignment, modal initialization and stock check;
- `actionLoading` disabled truth on confirm, deliver, due-date adjustment and cancel;
- `DocumentActions kind="sales-order" entityId={id!}` capability behavior;
- financial summary, receipts, items, notes, modals, queries, services, calculations, invalidation and workflow semantics outside the header.

The local legacy status map, sticky hero, horizontal action strip and `ActionBtn` helper are removed only from the migrated presentation region.

### System fit / action hierarchy — PASS at source level

- No parallel Sales-only action registry exists.
- Existing shared `ActionRegistry` remains the single placement truth.
- Confirm/Deliver are primary when eligible; Cancel remains tertiary + danger; secondary/tertiary actions progressively disclose through overflow.
- Shared `Button` owns migrated workflow-action tone, loading/disabled and touch-target behavior.
- Existing shared Sales status semantics are reused via `SalesOrderStatusBadge`.
- Customer identity remains a `CustomerLink`.
- The header tolerates wrapped Arabic/long identity content and uses logical RTL-safe spacing.

### Device composition — PASS at source level

- **Mobile:** one visible workflow action + overflow; no horizontal action strip; header/action layout becomes single-column and overflow becomes in-flow.
- **Tablet:** two visible workflow actions + overflow with deliberate wrapped tools composition.
- **Desktop:** up to four visible workflow actions before overflow, preserving dense review behavior.

`WATCH` only: `DocumentActions` remains a legacy shared feature component with its own compact/split-button styling. Its capability behavior is correctly preserved, but final Mobile sticky-header density/touch polish should be observed in the next controlled runtime visual review rather than expanded inside this bounded slice.

### Accessibility / RTL — PASS at source level

- Action region has explicit `role="group"` + Arabic label.
- Native `<details>/<summary>` supplies keyboard-toggle behavior for overflow without inventing incomplete menu ARIA.
- Migrated workflow buttons use shared touch targets and accessible labels.
- Status meaning is not color-only.
- Title/subtitle wrapping and logical CSS properties are RTL-safe.

No unresolved PR review thread exists.

## Blocking build/type evidence

### P1 Gate — exact PR HEAD still contains known preview-discovered TypeScript failures

The owner-requested manual preview build failed on the development snapshot immediately preceding the hotfix with real `tsc -b` errors in:
- `src/components/sales/SalesOrderFormPresentation.test.tsx` — unsupported jest-dom matcher typings (`toBeInTheDocument`, `toHaveAttribute`, `toBeDisabled`);
- `src/components/ui/Stepper.test.tsx` — same unsupported matcher typings;
- `src/pages/customers/CustomerDetailTabs.tsx` — conditional `credit` tab widens `value` to `string`, violating `CustomerDetailTab`.

Those failures were fixed on current Development by hotfix merge `1f6c184df1a5609ca47417e0287991b4c069791a`, and a subsequent owner-requested preview built successfully from that corrected development baseline plus preview-only switches.

But exact PR HEAD `3f370e02...` still contains the pre-fix versions. Direct source verification shows the failing jest-dom matcher calls remain in `SalesOrderFormPresentation.test.tsx`, and the pre-fix `CustomerDetailTabs` inference remains present. Git compare shows the PR and current Development diverged at slice baseline `8a0c347...`; Development has exactly the three build-hotfix files plus role-state changes that the PR lacks.

Per `33_TEST_AND_VALIDATION_POLICY.md`, this is a current blocker for exact-head GREEN. The successful preview on the corrected development/preview baseline is **not** exact-head execution evidence for PR `3f370e02...`.

### Minimum required fix

Sync the current `design-system-v2-development` baseline into `ds2/sales-order-detail-v2` without force rewriting the reviewed slice, so PR #32 inherits the already-integrated three-file TypeScript hotfix. Do not reimplement or broaden those fixes. Preserve the DS2-UI-005 product/test diff and hand off one new stable exact HEAD for re-review.

No new preview or hosted CI is required merely to satisfy this review; the known failing code must simply no longer exist on the exact candidate HEAD. A fresh source review is then required because the HEAD will move.

## Test / execution evidence

Focused DS2-UI-005 tests are authored for:
- shared `AppAction` contract and canonical device resolution;
- Mobile one-visible-plus-overflow behavior;
- hidden/device eligibility;
- tone mapping, callbacks, loading/disabled and touch targets;
- labelled action grouping and sticky composition;
- Sales status/header adapter behavior;
- live page shared-header wiring and removal of legacy header presentation;
- exact permission/status gates and callbacks/routes;
- confirm warehouse fallback;
- four legacy `actionLoading` guards;
- untouched query/service/financial/modal boundaries.

For **this PR HEAD**, evidence remains `TESTS_AUTHORED_NOT_EXECUTED` and no `SOURCE_REVIEW_PASS` is issued because a known TypeScript failure is outstanding.

The manual preview evidence belongs to different baselines:
- failed preview: established the real TypeScript blocker;
- later READY preview: verifies the hotfix on corrected Development/preview baseline, not on PR HEAD `3f370e02...`.

No GitHub Actions/hosted CI was triggered or relied upon.

## Peer-state comparison / freshness

After forming the exact-head source judgment above, peer states were compared:
- **Product Design Director:** its `BLOCKING` state targets old head `97b3da7c...` and the removed parallel action taxonomy. That architectural blocker is stale/consumed for the current candidate.
- **UI Production Engineer:** feature-branch state correctly records the live wiring and requests exact-head QA, but its statement that Development drift is only role-state files became stale after the manual-preview hotfix merged to Development. The three TypeScript-fix files are now material integration drift for this candidate.
- **Development Integrator:** its `BLOCKING` completeness state targets old unwired head `9e9871f...`. Completeness is now resolved, but integration must still remain `NO_MERGE` because the current exact head contains known build/type failures.
- **Team Memory / Workstream:** still identify DS2-UI-005 as the only active Sales-detail slice; no competing implementation slice exists.

There is no current design-system architecture contradiction. The only current `BLOCKING` condition is exact-head build/type evidence freshness.

## Runtime / release boundary

Not claimed for PR HEAD `3f370e02...`:
- `SOURCE_REVIEW_PASS`
- `LOCAL_EXECUTION_PASS`
- `MANUAL_PREVIEW_BUILD_PASS`
- `RUNTIME_VISUAL_PASS`
- `main` / release readiness

## Cross-role handoff

- **To:** UI Production Engineer, Product Design Director, Development Integrator
- **What changed:** Design QA independently reviewed completed PR #32 HEAD `3f370e02d60bbf6dfa5978c1dadc2f9454210f08`. The prior completeness blocker is closed and the Sales header/action migration passes bounded source/design review, but exact-head GREEN is blocked because this branch still contains the three preview-discovered TypeScript failures that were already fixed on current Development.
- **Preserve:** live Sales permission/status/workflow/query/service/calculation/modal/output truth; shared `AppAction` / `resolveActionSet` architecture; bounded header-only scope; existing `DocumentActions` capabilities; no hosted CI/Vercel/main activity from scheduled agents.
- **Need from you:** UI Production Engineer should sync current `design-system-v2-development` into PR #32 so the already-integrated TypeScript hotfix is present, avoid unrelated scope changes, and hand off the new exact HEAD. Integrator must remain `NO_MERGE` until fresh QA on that new head records `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS`.
- **Blocker level:** `BLOCKING` — known exact-head build/type failure inherited from stale baseline.
- **Baseline:** Development `1f6c184df1a5609ca47417e0287991b4c069791a`; reviewed PR HEAD `3f370e02d60bbf6dfa5978c1dadc2f9454210f08`.
