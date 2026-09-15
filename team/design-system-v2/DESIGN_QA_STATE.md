# Design QA State

## Reviewed baseline

- Review date: `2026-09-15`
- Development branch: `design-system-v2-development`
- Exact current development HEAD observed during review: `06137f53190a704d23f06c045cfc21906a1966c4`
- Active implementation PR: `#28 — DS2-UI-001: migrate customer basic-info form to V2 composition`
- Exact PR HEAD reviewed: `ccbf9decab1257634874fc348525d6a50f588857`
- PR base at review: `design-system-v2-development`
- PR state: `OPEN / DRAFT / MERGEABLE`
- Changed-file scope: `src/pages/customers/CustomerFormPage.tsx`, `src/pages/customers/CustomerFormPage.v2.test.ts`
- Development drift after the PR base is documentation/state only; no relevant shared-component/product-code drift was found.

## Independent QA disposition

**AGENT-REVIEW: BLOCKED** on exact HEAD `ccbf9decab1257634874fc348525d6a50f588857`.

The form-composition migration is otherwise well bounded and aligned with the North Star, but the PR introduces an incomplete ARIA Tabs contract into the retained legacy tab surface. Because this accessibility semantic change is introduced by this PR and the test artifact explicitly locks it in, the exact HEAD cannot receive `GREEN-DEV` yet.

## Functional isolation / scope

**PASS.**

The PR changes only the Customer Form presentation file and one focused test artifact. Source review found no DB/migration/RPC/service/RBAC/RLS/permission-definition/route-guard/query-cache/business-calculation/workflow-state/validation-semantic change.

Preserved source wiring includes:
- existing `createCustomer(form)` and `updateCustomer(id!, form)` submit paths;
- default branch/contact creation side effects;
- GPS capture behavior;
- `finance.credit.manage` disabled guard;
- `customers.credit.update` credit-tab visibility;
- geography / price-list / representative lookup flows;
- out-of-scope branches, contacts, credit-history data behavior and responsive modals.

## System-fit / composition judgment

**PASS outside the tab-semantics blocker.**

The implementation correctly consumes shared V2 grammar instead of creating a Customer-local design system:
- `PageHeader`
- `FormSection`
- `FormGrid`
- `FormActions`
- existing `PermissionGuard`

Device composition is source-coherent with the shared contracts:
- Mobile FormGrid collapses to one column;
- Tablet caps 3/4-column form grids at two columns;
- Desktop preserves two/three-column density;
- `FormActions stickyOnMobile` uses the shared bottom-navigation height + safe-area offset and remains an explicit opt-in pattern.

The creation-default subgroups retain some local inline styling, but that is acceptable within this bounded slice and should not be promoted into a new shared primitive without recurring evidence.

## BLOCKING finding

### P2 — Accessibility semantics / shared-system contract — BLOCKING

**Location:** `src/pages/customers/CustomerFormPage.tsx`, legacy Customer edit tabs around the `tabs` container and four tab buttons.

The PR adds:
- `role="tablist"`
- `role="tab"`
- `aria-selected`

but the same page does not provide the rest of a coherent ARIA tab interaction contract:
- no tab -> panel ID / `aria-controls` / `aria-labelledby` relationship;
- the rendered panels remain ordinary form/card/table containers rather than associated `tabpanel` regions;
- no roving tab focus model;
- no Arrow/Home/End keyboard navigation handling for the declared tab widget.

The previous controls were ordinary buttons. Adding partial widget roles changes the accessibility contract without implementing the behavior/relationships implied by those roles. This conflicts with the North Star requirements for predictable keyboard/focus semantics and with the rule against inventing a one-off partial shared pattern inside one page.

The focused test `CustomerFormPage.v2.test.ts` currently asserts the partial `role="tab"` markup, so it would preserve the problem instead of protecting the intended bounded behavior.

### Minimum required fix

For this slice, prefer the smallest safe correction:
1. keep the legacy tab buttons explicitly `type="button"` so they cannot submit;
2. remove the newly introduced `role="tablist"`, `role="tab"`, and `aria-selected` semantics;
3. update the focused test to protect non-submit behavior and the existing credit permission boundary without requiring the partial ARIA roles;
4. defer a complete tabs keyboard/tabpanel contract to the planned shared `Tabs/SubNav/SegmentedControl` component-depth work.

Alternative: implement a complete accessible tab contract, but that would broaden DS2-UI-001 and is not recommended for this PR.

## Device / state / RTL / interaction review

- **Mobile:** source-level form layout and sticky actions are coherent with the shared V2 contracts; no source-level ordinary horizontal-overflow regression identified in the migrated info composition.
- **Tablet:** deliberate two-column cap exists in shared FormGrid CSS; no compressed three-column tablet grid in the migrated sections.
- **Desktop:** two/three-column density remains appropriate for master-data entry.
- **RTL / Arabic:** Arabic labels and LTR treatment for phone/email/GPS/numeric fields are preserved; no new source-level bidi defect identified.
- **States:** existing saving/GPS disabled/loading behavior and credit permission-disabled state are preserved. No new loading/error business state was introduced by this presentation slice.
- **Accessibility:** tab semantic blocker above. Notes textarea gains an accessible name via `aria-label`. Existing form-label association debt was not materially widened by this slice.
- **Runtime visual:** not executed/claimed; preview remains owner-requested only.

## Test / execution evidence

- Focused test artifact exists: `src/pages/customers/CustomerFormPage.v2.test.ts`.
- Evidence label: `TESTS_AUTHORED_NOT_EXECUTED`.
- No GitHub Actions/hosted CI was triggered or relied upon.
- No approved local execution evidence is present for this exact HEAD.
- No known build/type failure is currently recorded.
- Source review evidence cannot be labeled `SOURCE_REVIEW_PASS` while the accessibility blocker above remains.

## Cross-role context comparison

- UI Production Engineer reports the exact HEAD as `REVIEW_READY`; this remains valid for review but not acceptance.
- Product Design Director independently marked the tab semantics as a `WATCH` and explicitly asked QA to decide whether the partial ARIA contract is complete enough. QA resolves that watchpoint as **BLOCKING** for the exact current HEAD because the panel relationships and keyboard widget behavior are absent.
- Development Integrator is correctly in `WAITING_QA / NO_MERGE`.
- No disagreement exists on functional isolation or the shared form-composition direction.

## Cross-role handoff

- **To:** UI Production Engineer, Product Design Director, Development Integrator
- **What changed:** exact-head QA found one narrow blocking accessibility/system-contract defect: PR #28 introduces partial ARIA tab roles on the retained legacy tabs without a complete tab widget/panel keyboard contract, and the test currently locks those partial semantics in.
- **Preserve:** all Customer business behavior and permissions; shared `PageHeader` / `FormSection` / `FormGrid` / `FormActions` composition; Mobile/Tablet/Desktop form strategy; current UI-only scope; no hosted CI or preview.
- **Need from you:** UI Production Engineer should make the minimum bounded fix by retaining `type="button"` but removing the partial ARIA tab roles/selection semantics and adjusting the test. Design Director should keep complete Tabs/SubNav semantics deferred to shared component-depth work. Integrator must not merge until QA re-reviews the new exact HEAD and issues `GREEN-DEV`.
- **Blocker level:** `BLOCKING`
- **Baseline:** development `06137f53190a704d23f06c045cfc21906a1966c4`; PR #28 HEAD `ccbf9decab1257634874fc348525d6a50f588857`
