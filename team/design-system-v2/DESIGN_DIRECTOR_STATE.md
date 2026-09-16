# Design Director State

## Reviewed baseline

- Review date: `2026-09-16`
- Development branch: `design-system-v2-development`
- Exact current development HEAD reviewed before this state write: `68030bf9064ef1c4540f2e1dc3ef60a34bd46642`
- Active slice: `DS2-UI-003 — Sales Orders list V2`
- Active Draft PR: `#30 — DS2-UI-003: migrate Sales Orders list to shared V2 grammar`
- Feature branch: `ds2/sales-orders-list-v2`
- Starting baseline: `e78de5d71002b9718fa7d760b3cc7bc933ff6cba`
- Exact current PR HEAD independently reviewed: `bfd54e578a7b63bd7abfa567e197db0043cc8a13`
- Live PR state: `OPEN / DRAFT / mergeable`
- Current implementation disposition: `IN_PROGRESS`
- Current evidence: `TESTS_AUTHORED_NOT_EXECUTED`
- Exact-head QA approval for PR #30: not yet expected / not present

## Independent professional judgment

**WIP DIRECTION PASS — CONTINUE THE SAME SLICE. NO SCOPE EXPANSION.**

The current PR is still correctly bounded to Sales-list presentation infrastructure and is not review-ready yet. The emerging `SalesOrderCard` boundary is directionally strong and consistent with the North Star:

- Sales business/query/calculation truth remains page-owned;
- shared `Card`, `KeyValueList`, `Button`, `StatusBadge` and semantic tokens own visual/interaction behavior;
- the card is an explicit operational record surface rather than a fake whole-card button;
- Mobile actions are touch-ready and explicit;
- Tablet has a deliberately denser card mode instead of inheriting a shrunken Desktop table;
- status is mapped through the shared semantic status grammar;
- payment progress now has an explicit labelled accessibility contract;
- focused tests cover the new presentation boundary;
- no service/query/cache/permission/workflow/business mutation is present in the current two-file PR.

The correct next step remains bounded page wiring through `ResponsiveCollection`; do not start Sales Order form/detail work and do not open a speculative DataTable/FilterBar redesign.

## Two required system-boundary corrections before REVIEW

### 1. Tablet presentation must not silently inherit Mobile query semantics

**Required direction before review.**

The current Sales page has an explicit historical breakpoint: only `<=768px` uses the Mobile card/infinite-loading surface; widths above 768 currently use the Desktop paged table. Therefore, under the V2 canonical device split, Tablet (`769–1024px`) may change **presentation** to the new denser `SalesOrderCard`, but this slice must not silently change its data/pagination behavior to Mobile infinite loading.

For DS2-UI-003:

- Desktop: existing `desktopOrders` + numbered pagination + Desktop table.
- Tablet: deliberate `SalesOrderCard` composition, but retain the existing paged dataset / numbered-pagination semantics unless a separately approved functional change exists.
- Mobile: existing accumulated `mobileOrders` + infinite-load/sentinel semantics + Mobile card composition.

`ResponsiveCollection` should own the one-renderer-at-a-time presentation boundary. The page may choose the device-appropriate already-existing dataset, but it must not redefine either query contract.

Focused wiring tests should make this invariant explicit so Tablet visual improvement cannot accidentally become a pagination behavior change.

### 2. Presentation must not normalize away projected financial truth

**Required direction before review.**

`SalesOrderCard` currently receives `summary.paidPercent` as an already-projected value, then rounds and clamps it internally to `0..100`. That conflicts with the component's own stated boundary that business/calculation truth is page-owned and can also change the existing visible behavior: the current page clamps the progress-bar width, but the visible percentage is `Math.round(paidRatio * 100)` and may differ from the normalized bar value in edge cases.

Keep financial truth ownership outside the visual component:

- preserve the existing page-owned `collected`, `outstanding`, ratio and displayed-percentage semantics;
- do not move those calculations into `SalesOrderCard`;
- do not silently replace an already-projected display value with a normalized value;
- if the visual bar requires a bounded `0..100` geometry/ARIA value, separate that presentation normalization from the displayed projected percentage rather than overwriting the projected value.

This is a small component-contract correction, not permission to redesign payment accounting or Sales calculations.

## North Star fit

### Shared-system coherence

**PASS for current WIP.** The component is a legitimate Layer-4 Sales composition over shared V2 primitives. No Sales-local primitive is being invented where a system primitive already exists.

### Mobile

**PASS direction.** Explicit identity/status/financial hierarchy and touch-safe open/map/call actions are stronger than the legacy clickable `DataCard` pattern. Keep ordinary horizontal overflow out of the card surface.

### Tablet

**PASS presentation direction with the data-semantics constraint above.** A denser card anatomy is appropriate, but device composition must not alter the existing paged-vs-infinite behavior contract.

### Desktop

**PASS direction.** Retain dense `DataTable` comparison and numbered pagination. When wiring, do not use `DataTable.dataCardMapping`; `ResponsiveCollection` should prevent duplicate mounted Desktop/Mobile interaction trees.

### Accessibility / RTL

**PASS direction.** Semantic status text, labelled progress, explicit buttons and LTR order/customer identifiers fit the shared grammar. QA should still review the final wired page and state transitions on the exact review-ready HEAD.

## Freshness / development drift

The feature branch started at `e78de5d71002b9718fa7d760b3cc7bc933ff6cba`.

Current development HEAD `68030bf9064ef1c4540f2e1dc3ef60a34bd46642` is four commits ahead of that baseline. Compare shows development drift is limited to:

- `docs/design-system-v2/31_AGENT_TEAM_WORKSTREAM.md`
- `team/design-system-v2/INTEGRATION_STATE.md`
- `team/design-system-v2/UI_IMPLEMENTATION_STATE.md`

No product/shared-component drift exists after the feature baseline. Do not merge-sync the WIP branch merely to absorb governance/state updates.

## Cross-role context comparison

- **UI Production Engineer:** current and aligned on exact WIP HEAD `bfd54e57...`; its next step is the correct bounded page wiring. The two Director constraints above refine that handoff before REVIEW.
- **Design QA:** stored state still belongs to merged PR #29 and is stale for Sales. No Sales QA approval or contradiction exists yet.
- **Development Integrator:** stored state targets earlier PR #30 WIP HEAD `6608f33e...`; its `NO_MERGE_IN_PROGRESS` conclusion remains correct and is naturally stale by HEAD. No contradiction.
- **Team Memory / Workstream:** correctly identify DS2-UI-003 as the single active slice and preserve one-slice WIP discipline.

No current peer-state `BLOCKING` contradiction applies.

## Preserve

- Sales URL-synchronized filters and governorate/city reset behavior;
- current Sales query parameters and service/cache contracts;
- Desktop numbered pagination semantics;
- Mobile accumulated/infinite-loading semantics;
- existing KPI business meaning;
- existing status/payment labels and business meaning;
- page ownership of all monetary/outstanding/payment-ratio calculations;
- `sales.orders.create` permission behavior and Smart Transfer entry point;
- order/customer navigation plus map/call destinations;
- shared V2 ownership of visual/action/status grammar;
- exact evidence honesty; no hosted CI, Vercel preview or `main` activity;
- one active implementation slice only.

## Cross-role handoff

- **To:** UI Production Engineer, Design QA, Development Integrator
- **What changed:** Product Design Director independently reviewed PR #30 WIP HEAD `bfd54e578a7b63bd7abfa567e197db0043cc8a13`. The Sales card/presentation direction is approved to continue, with two bounded system-contract constraints before REVIEW: Tablet may use card presentation but must preserve the existing paged dataset/pagination semantics, and `SalesOrderCard` must not clamp/round away page-projected financial display truth.
- **Preserve:** all existing Sales query/filter/pagination/infinite-loading/navigation/permission/status/payment/Smart Transfer/map/call/business semantics; shared `ResponsiveCollection` one-renderer boundary; Desktop density; Mobile operational clarity; quota/deployment/main restrictions.
- **Need from you:** UI Production Engineer should continue only PR #30, apply these two boundaries while wiring `SalesOrdersPage`, and author focused coverage for device-specific dataset/pagination selection plus preserved payment-progress projection. Design QA and Integrator should continue to no-op until a stable review-ready exact HEAD is handed off.
- **Blocker level:** `WATCH` during WIP, but both constraints are required before `REVIEW` / `GREEN-DEV`.
- **Baseline:** development `68030bf9064ef1c4540f2e1dc3ef60a34bd46642`; PR #30 HEAD `bfd54e578a7b63bd7abfa567e197db0043cc8a13`
