# Design QA State

## Reviewed baseline

- Review date: `2026-09-15`
- Development branch: `design-system-v2-development`
- Exact development HEAD observed before this QA state write: `af94736ef03e2abdf764ec806e4e3294013ccb58`
- Active implementation PR: `#28 — DS2-UI-001: migrate customer basic-info form to V2 composition`
- Exact PR HEAD reviewed: `b6bfceeb8327437e274222c7e2f75e83c4a65061`
- PR base branch: `design-system-v2-development`
- Live PR state at review: `OPEN / DRAFT / mergeable_state=clean`
- Changed-file scope: `src/pages/customers/CustomerFormPage.tsx`, `src/pages/customers/CustomerFormPage.v2.test.ts`
- Current disposition: `AGENT-REVIEW: GREEN-DEV`

## Independent QA disposition

**GREEN-DEV** on exact HEAD `b6bfceeb8327437e274222c7e2f75e83c4a65061`.

Evidence:
- `SOURCE_REVIEW_PASS`
- `TESTS_AUTHORED_NOT_EXECUTED`

The single blocker from the previous exact-head review is resolved without broadening DS2-UI-001. The retained legacy Customer section-switch controls remain ordinary non-submitting buttons, the incomplete ARIA Tabs widget roles are removed, and the focused test now prevents partial `tablist` / `tab` / `aria-selected` semantics from being reintroduced.

Complete Tabs/SubNav keyboard, focus and panel semantics remain correctly deferred to the shared component-depth program.

`GREEN-DEV` authorizes controlled integration into the isolated Design System development branch only. It is not runtime, preview, main or release approval.

## Functional isolation / scope

**PASS.**

The live PR still changes only:
- `src/pages/customers/CustomerFormPage.tsx`
- `src/pages/customers/CustomerFormPage.v2.test.ts`

No DB, migration, RPC, service, RBAC/RLS, permission definition, route guard, query/cache semantic, validation semantic, workflow state, business calculation, workflow file or Vercel configuration change is present.

Preserved source wiring includes:
- existing `createCustomer(form)` and `updateCustomer(id!, form)` submit paths;
- default branch/contact creation side effects;
- GPS capture behavior;
- `finance.credit.manage` disabled guard;
- `customers.credit.update` credit-tab visibility;
- geography / price-list / representative lookup flows;
- out-of-scope branches, contacts, credit-history behavior and responsive modals.

## Previously blocking finding — resolved

### P2 — Accessibility semantics / shared-system contract

Previous blocked HEAD: `ccbf9decab1257634874fc348525d6a50f588857`.

Required correction was:
1. retain `type="button"` for the legacy section-switch controls;
2. remove partial `role="tablist"`, `role="tab"`, `aria-selected` semantics;
3. protect that bounded behavior in the focused test;
4. defer full Tabs/SubNav semantics to the shared component-depth slice.

Current exact HEAD `b6bfceeb...` satisfies all four points.

Source confirmation:
- all four retained edit section-switch controls are `type="button"`;
- no `role="tablist"`, `role="tab"`, or `aria-selected` remains in the migrated surface;
- `CustomerFormPage.v2.test.ts` asserts non-submit behavior and negative assertions for the incomplete ARIA widget contract;
- no Tabs redesign or new page-local Tabs abstraction was introduced.

Verdict: **RESOLVED**.

## System-fit / composition judgment

**PASS.**

The implementation strengthens the shared V2 language rather than creating a Customer-specific mini design system. It consumes:
- `PageHeader`
- `FormSection`
- `FormGrid`
- `FormActions`
- existing `PermissionGuard`

The existing V2 form contracts remain coherent:
- `FormSection` owns presentation grouping only;
- `FormGrid` owns responsive form density;
- `FormActions` owns consistent action placement and optional Mobile sticky behavior;
- business calculations and validation semantics remain page/domain owned.

Creation-default subgroups still contain some bounded local inline layout. That remains acceptable in this slice because recurring evidence does not yet justify a new shared subgroup primitive.

## Device / state / RTL / interaction review

### Mobile
**PASS at source level.**
- V2 `FormGrid` collapses multi-column layouts to one column at `<=768px`.
- `FormActions stickyOnMobile` uses the shared bottom-navigation height + safe-area bottom offset.
- action buttons stretch through the shared form-actions contract while primary/secondary styling remains distinct.
- retained section-switch buttons cannot accidentally submit the form.
- no source-level ordinary horizontal-overflow regression was identified in the migrated info composition.

### Tablet
**PASS at source level.**
- 3/4-column form grids cap at two columns through `769–1024px`.
- the migration does not fall back to a compressed Desktop 3-column layout.

### Desktop
**PASS at source level.**
- requested 2/3-column form density remains available for efficient master-data entry.

### RTL / Arabic
**PASS at source level.**
- Arabic labels remain first-class;
- phone/email/GPS/numeric values retain their existing LTR treatment;
- no new bidi or wrapping defect is evident from the source change.

### States
**PASS for preserved scope.**
- saving disabled/loading behavior is unchanged;
- GPS loading/disabled behavior is unchanged;
- finance credit permission-disabled state is unchanged;
- no new business loading/error state is introduced by the composition migration.

### Accessibility
**PASS for this slice at source level.**
- the incomplete ARIA Tabs semantics are removed;
- notes textarea has an explicit accessible name;
- existing broader form-label association debt was not materially widened by this slice;
- full shared Tabs/SubNav accessibility remains a future component-depth responsibility.

## Test / execution evidence

Focused artifact:
`src/pages/customers/CustomerFormPage.v2.test.ts`

It protects material source contracts for:
- V2 form composition imports/use;
- existing submit wiring;
- credit permission boundary;
- customer creation branch/contact side effects;
- GPS wiring;
- retained non-submitting section-switch controls;
- negative protection against the previously blocked partial ARIA Tabs contract.

Evidence label: **`TESTS_AUTHORED_NOT_EXECUTED`**.

No GitHub Actions/hosted CI was triggered or relied upon. No approved local repository runtime executed tests/build/lint for this exact HEAD, so no `LOCAL_EXECUTION_PASS` is claimed. No known TypeScript/build failure is currently recorded or identified by source review.

## Development drift / freshness

The live development branch has advanced beyond the PR's recorded base only through Design System Workstream / role-state documentation. Compare from PR base `d01f6c0b891fa8b1615993a675555bb365454460` to observed development HEAD `af94736ef03e2abdf764ec806e4e3294013ccb58` changes only:
- `docs/design-system-v2/31_AGENT_TEAM_WORKSTREAM.md`
- the four role-state files under `team/design-system-v2/`

No relevant shared component or product-code drift exists. The raw live PR reports `mergeable=true`, `rebaseable=true`, `mergeable_state=clean`.

Do not move the feature HEAD merely to absorb governance-only drift. Integrator should revalidate freshness immediately before merge as normal.

## Cross-role context comparison

- **UI Production Engineer:** current and aligned; hands exact fixed HEAD `b6bfceeb...` back to QA with `TESTS_AUTHORED_NOT_EXECUTED`.
- **Product Design Director:** its last material state targets old HEAD `ccbf9dec...` and treated partial tab semantics as `WATCH`; that watchpoint is now resolved by the bounded fix. No current design contradiction remains.
- **Development Integrator:** its last state is stale by PR HEAD and correctly blocked the old `ccbf9dec...` baseline. It must now re-evaluate the new exact `GREEN-DEV` HEAD.
- **Team Memory / Workstream metadata:** lifecycle/head references remain behind the live PR/Implementation State. This is a coordination `WATCH`, not a source-acceptance blocker; Integrator owns synchronization of integrated truth after successful merge.

No current peer-state `BLOCKING` contradiction applies to exact HEAD `b6bfceeb...`.

## Runtime / release boundary

Not claimed in this review:
- `LOCAL_EXECUTION_PASS`
- `MANUAL_PREVIEW_BUILD_PASS`
- `RUNTIME_VISUAL_PASS`
- main/release readiness

Those remain deliberate milestone/release gates under `33_TEST_AND_VALIDATION_POLICY.md`.

## Cross-role handoff

- **To:** Development Integrator, Product Design Director, UI Production Engineer
- **What changed:** the bounded QA accessibility blocker is resolved and exact PR #28 HEAD `b6bfceeb8327437e274222c7e2f75e83c4a65061` now has `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS`; evidence remains `TESTS_AUTHORED_NOT_EXECUTED`.
- **Preserve:** Customer create/update/GPS/lookup/credit/default branch/contact behavior; shared `PageHeader` / `FormSection` / `FormGrid` / `FormActions` composition; ordinary non-submitting legacy section-switch semantics until the future shared Tabs/SubNav slice; no hosted CI or Vercel; no governance-only feature-HEAD churn.
- **Need from you:** Integrator should revalidate the live exact HEAD/base/peer states and merge only if its normal gates remain satisfied, then refresh Workstream/Team Memory/integration truth. Design Director should keep complete Tabs/SubNav semantics in the shared component-depth roadmap. UI Engineer should no-op unless a new material finding appears.
- **Blocker level:** `WATCH` only for stale lifecycle metadata; no source/integration blocker identified on the exact reviewed HEAD.
- **Baseline:** development observed `af94736ef03e2abdf764ec806e4e3294013ccb58`; PR #28 HEAD `b6bfceeb8327437e274222c7e2f75e83c4a65061`
