# Design Director State

## Reviewed baseline

- Review date: `2026-09-16`
- Development branch: `design-system-v2-development`
- Exact current development HEAD reviewed: `62d173cbb6f6cf7dcf8215fcc4efff0dcaaad66e`
- Active implementation slice: `DS2-UI-002 — Customer detail secondary tabs/patterns`
- Active Draft PR: `#29 — DS2-UI-002: migrate customer secondary surfaces to shared V2 patterns`
- Feature branch: `ds2/customer-secondary-tabs-v2`
- Starting baseline: `d05a1d06a4214d5a4e0b222c5e7586155a9841f2`
- Exact current PR HEAD reviewed: `b61970556f93a2a7f068ce4e3843aed691661ec7`
- PR state: `OPEN / DRAFT / mergeable`
- Current implementation disposition: `IN_PROGRESS`
- Current evidence: `TESTS_AUTHORED_NOT_EXECUTED`
- Runtime/preview/release evidence: not claimed

## Independent professional judgment

**ARCHITECTURAL DIRECTION: PASS, WITH TWO REQUIRED SYSTEM-FIT CORRECTIONS BEFORE REVIEW HANDOFF.**

The implementation direction is correct and should continue on the same PR/slice.

The strongest architectural decision in the current WIP is to **adopt the existing shared `Tabs` contract rather than invent another Customer-local navigation primitive**. The repository already has a complete controlled content-tabs pattern with `tablist` / `tab` / `tabpanel` relationships, roving focus, Home/End navigation, disabled handling and RTL-aware arrow behavior. `CustomerDetailTabs` is therefore appropriately thin: Customer labels, counts, permission visibility and panel composition are domain-owned while keyboard/focus/ARIA mechanics remain shared-system owned.

The extracted branches / contacts / credit-history panels also move in the right direction by reusing shared `Card`, `SectionHeader`, `KeyValueList`, `StatePanel` and semantic primary-marker treatment instead of preserving the old page-local card/empty-state markup.

No backend/business/query/permission/validation/workflow scope expansion is present in the current four-file WIP.

## Required system-fit corrections before `REVIEW`

### 1. New V2 actions must consume the shared `Button` primitive — `REQUIRED BEFORE REVIEW`

`CustomerSecondaryPanels.tsx` currently creates new action controls with raw legacy markup such as:

- `button.btn.btn-primary...`
- `button.btn.btn-secondary...`
- `button.btn.btn-ghost...`
- `button.btn.btn-danger...`

This reproduces the CSS implementation detail directly inside newly migrated V2 presentation code even though `src/components/ui/Button.tsx` already owns the shared semantic action contract, including variant, size, icon-only behavior and touch-target semantics.

Direction:
- migrate newly introduced Add/Edit/Delete/empty-state actions in the extracted V2 panels to the shared `Button` primitive;
- preserve the exact existing callbacks, permission visibility and accessible labels;
- use `touchTarget` where the current WIP intends `btn-touch`;
- do **not** redesign the branch/contact ResponsiveModal footer in this slice; those legacy modal internals remain explicitly out of scope.

If raw new action markup remains at review handoff, Design QA should treat it as a System Fit failure because the slice would be migrating visual surfaces while bypassing an already-proven shared primitive.

### 2. Tab record counts are neutral metadata, not domain statuses — `REQUIRED BEFORE REVIEW`

`CustomerDetailTabs.countBadge()` currently uses `StatusBadge` for branch/contact/credit record counts.

The shared contract explicitly defines `StatusBadge` as the visual mapping for **domain statuses**. A numeric record count is metadata, not status truth. The repository already has the neutral `Badge` primitive for this class of compact label/count.

Direction:
- use the neutral shared `Badge` primitive for tab counts;
- retain the accessible count label;
- keep `StatusBadge` for actual semantic state such as the branch/contact `أساسي` marker where status-like emphasis is justified.

This distinction matters because Design System V2 must make semantic components predictable across modules; visual similarity alone is not enough reason to overload `StatusBadge`.

## Explicit non-expansion boundary

### Credit history table — preserve, do not invent DataTable in this slice

The credit-history WIP intentionally retains the existing `data-table` presentation and the existing displayed difference arithmetic (`limit_after - limit_before`). Source comparison confirms that arithmetic and table content already exist in the Customer page; this extraction is not creating a new business calculation.

Although the North Star includes a future DataTable V2 contract, there is no implemented shared `DataTable` pattern in the current V2 patterns directory. Therefore DS2-UI-002 should **not** expand into a speculative DataTable build merely to remove this legacy table now.

Keep the bounded horizontal-scroll wrapper / existing table semantics for this Customer slice, then let the later shared DataTable component-depth program own cross-module convergence.

### Local layout styles — WATCH, not a blocker

The tokenized `collectionGridStyle`, action-row layout and spacing wrappers are bounded local composition, not new semantic primitives. They may remain for this slice if wiring stays contained. Do not create a speculative generic grid/action-row abstraction solely to eliminate a few local layout declarations.

However, continue avoiding growth into a large Customer-only style subsystem; recurring evidence in later screens should drive shared layout extraction.

## Device / interaction direction

- **Mobile:** shared Tabs horizontal navigation and touch behavior are directionally correct; branch/contact cards should remain single-column friendly and action targets touch-safe through shared Button semantics.
- **Tablet:** preserve deliberate card density rather than compressing a Desktop table/grid.
- **Desktop:** cards may use available width efficiently; credit history may retain dense table presentation.
- **RTL / Arabic:** Tabs inherits shared RTL keyboard direction; phone/email/GPS/numeric facts stay explicitly LTR where appropriate.
- **States:** shared `StatePanel` empty states are the correct direction; permission-limited branches/contacts must expose no mutation actions.

## Freshness / branch drift

The feature branch started from `d05a1d06...`. Current development HEAD `62d173cbb...` is three commits ahead, but compare shows only:

- `docs/design-system-v2/31_AGENT_TEAM_WORKSTREAM.md`
- `team/design-system-v2/UI_IMPLEMENTATION_STATE.md`

No shared component or product-code drift occurred after the feature baseline. **Do not merge-sync PR #29 merely to absorb governance/state drift.** Preserve exact feature-head stability while implementation is active; normal freshness revalidation happens before review/integration.

## Cross-role context comparison

- **UI Production Engineer:** current and aligned on the primary architectural direction: existing complete shared Tabs is adopted, not reinvented; PR remains intentionally WIP and not QA-ready.
- **Design QA:** its stored state belongs to completed PR #28 and is stale for DS2-UI-002. Correct behavior is no-op until an explicit review-ready #29 HEAD is handed off.
- **Development Integrator:** correctly records DS2-UI-001 merged and DS2-UI-002 next. It must no-op while #29 remains WIP/Draft without exact-head GREEN-DEV.
- **Team Memory / Workstream:** current enough on active slice identity and Tabs direction.

No peer-state `BLOCKING` contradiction exists. The two System Fit corrections above are implementation guidance that must be resolved before the slice is handed to QA, not a reason to stop the active WIP.

## Preserve

- complete existing shared Tabs keyboard/focus/ARIA/RTL contract;
- one Customer-domain composition over Tabs, not another navigation implementation;
- completed DS2-UI-001 basic-info composition;
- all Customer CRUD/GPS/lookup/credit/count/permission behavior;
- caller-owned mutation callbacks and existing permission booleans;
- branch/contact modal and destructive-confirmation redesign remains out of scope;
- credit-history arithmetic remains display-equivalent to legacy behavior;
- no backend/business/query/permission/validation/workflow changes;
- no GitHub Actions, Vercel preview or `main` activity;
- no governance-only feature-HEAD churn.

## Cross-role handoff

- **To:** UI Production Engineer, Design QA, Development Integrator
- **What changed:** Design Director independently reviewed active PR #29 WIP HEAD `b61970556f93a2a7f068ce4e3843aed691661ec7`; Tabs adoption and panel extraction are architecturally sound, but newly introduced V2 panel actions must use shared `Button` and neutral tab counts must use shared `Badge` rather than `StatusBadge` before review handoff.
- **Preserve:** existing shared Tabs contract, Customer behavior/permissions/counts, completed basic-info composition, existing credit-history semantics, deferred overlay/DataTable programs and exact feature-head discipline.
- **Need from you:** UI Engineer should complete CustomerFormPage wiring/removal of duplicate legacy secondary markup and resolve the two shared-component System Fit corrections above before marking #29 REVIEW-ready. Design QA and Integrator should continue to no-op until that exact review-ready HEAD is explicitly handed off.
- **Blocker level:** `WATCH` during active WIP; becomes `BLOCKING` for `REVIEW` if either shared-component correction remains unresolved.
- **Baseline:** development `62d173cbb6f6cf7dcf8215fcc4efff0dcaaad66e`; PR #29 HEAD `b61970556f93a2a7f068ce4e3843aed691661ec7`
