# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-18`.
- Authoritative branch: `design-system-v2-development`.
- Development HEAD immediately before this Director-state write: `0d131d58936e0a895beb0eb6a126482a5c638eb8`.
- Latest integrated product slice: `DS2-REPORT-001 — Report route sub-navigation convergence`, PR #48, squash merge `5d2c57d9a502a4bbb2d355d94634bcf8b53075d2`.
- Active slice: `DS2-REPORT-002 — Report date-preset selector convergence`.
- Active implementation PR: `#49 — DS2-REPORT-002: converge report date preset selector`.
- Exact PR HEAD independently reviewed: `c71a486562bb6a9c3066cc4e074a23adacd51efe`.
- PR state at review: `OPEN / DRAFT / mergeable=true`.
- Product Design disposition: `BLOCKING — P2 SHARED MOBILE/LONG-CONTENT GEOMETRY DEFECT`.
- Evidence remains source-level only; no runtime visual, build, test, lint, preview or release PASS is claimed.

## Independent Product Design judgment

**PR #49 is directionally correct and functionally isolated, but it is not yet acceptable for integration on exact HEAD `c71a486562bb6a9c3066cc4e074a23adacd51efe`.**

The REPORT002 composition itself is right: the four Reports presets should use the shared V2 `SegmentedControl`, while `ReportFilterBar` and its callers continue to own `DateRange`, preset calculations, normalization and report-query meaning. The implementation preserves that boundary.

However, my previous planning assumption that the existing shared `SegmentedControl` contract already guaranteed Mobile horizontal reachability **without compressed targets** was incorrect. Independent inspection of the exact shared CSS confirms the defect identified by Design QA:

- `.ds-segmented-control` is `inline-flex` with `max-width: 100%`;
- default `.ds-segmented-control__item` uses `min-width: 0` and does not disable flex shrinking;
- flex items therefore retain the default `flex-shrink: 1`;
- labels are `white-space: nowrap`;
- Mobile adds `overflow-x: auto` only to the container.

For the four long Arabic report labels, container overflow alone does not establish a non-compression contract. The item boxes are allowed to shrink before horizontal overflow becomes the containment mechanism, while their nowrap text can spill beyond the shrunken target. That fails the explicit REPORT002 acceptance condition that all four labels remain reachable as discrete, touch-safe controls without compressed sub-touch targets.

This is a **shared-component contract defect proven by a real migrated surface**, not a Reports-local styling problem. Product Design therefore aligns with QA on the blocker.

## Required bounded repair

The active slice remains REPORT002; no competing slice is opened. UI Production Engineer may revise **the same PR #49** with one narrowly bounded shared hardening:

1. Default/non-block `SegmentedControl` items must retain intrinsic control width under constrained horizontal space rather than flex-shrinking. `flex: 0 0 auto` or an equivalent non-shrinking contract is acceptable.
2. The existing `SegmentedControl --block` equal-width behavior must remain intact (`flex: 1 1 0` or equivalent). The repair must not accidentally disable block stretching.
3. Mobile containment/scrolling remains owned by shared `SegmentedControl`; no `ReportFilterBar`-specific CSS escape hatch is acceptable.
4. Add focused contract coverage/evidence for the shared non-shrinking default-item geometry. Existing DOM tests are useful for selection semantics but do not prove this layout contract.
5. Preserve all existing preset/date/report semantics exactly.

This repair is authorized because it closes a real shared primitive gap exposed by the current consumer and strengthens the system-wide grammar. It does **not** authorize broader navigation CSS cleanup, a new SegmentedControl variant, custom-date redesign, or unrelated Reports work.

## Scope / semantic review — PASS

On the reviewed PR HEAD, the following remain correct and must not drift during repair:

- exactly four presets in the same order and Arabic copy: `آخر 7 أيام`, `آخر 30 يوماً`, `آخر 90 يوماً`, `هذا الشهر`;
- existing `applyPreset(...)`, local-date conversion and `normalizeDateRange(...)` behavior;
- external `value: DateRange` / `onChange(DateRange)` ownership;
- both custom native date inputs and their normalization behavior;
- a custom range matching no preset leaves every preset unselected;
- shared `SegmentedControl` remains presentation-only and does not absorb report date/business logic;
- no query/cache/service/hook/calculation/chart/table/metric/export/print/permission/routing/`AnalyticsGate`, DB/RPC, RBAC/RLS, workflow or business-semantic change.

The shared component implementation also confirms that button clicks call `onValueChange(item.value)` without suppressing a click on the currently selected item; no selected-item interaction blocker is present in the exact source.

## Blueprint / system-fit synthesis

The V2 component architecture requires domain surfaces to compose shared primitives and prohibits page-local primitive forks, while business rules stay outside visual primitives. The component decision matrix explicitly favors evolving sound shared contracts and decomposing `FilterBar` internally rather than replacing domain behavior. The migration matrix places Reports/Analytics in the filter-grammar wave. REPORT002 remains aligned with all three principles.

The newly proven geometry gap does not invalidate use of `SegmentedControl`; it is exactly the kind of shared depth defect that should be corrected once at the system layer when a real consumer exposes it.

## Device / RTL / accessibility disposition

- **Mobile (`<=768px`) — BLOCKING until repair:** four long Arabic presets require stable intrinsic-width touch controls plus contained horizontal scrolling; current shared CSS does not guarantee that.
- **Tablet (`769–1024px`) — PASS at source/composition level:** surrounding ReportFilterBar wrapping and 44px minimum height remain appropriate.
- **Desktop (`>=1025px`) — PASS at source/composition level:** compact single-choice hierarchy is appropriate beside custom dates.
- **RTL/Arabic — PASS except the shared Mobile compression risk:** exact copy/order and logical structure remain correct.
- **Accessibility — PASS at DOM/source level subject to geometry repair:** named group, native buttons, `aria-pressed`, focus-visible treatment and non-color-only active surface are appropriate.
- **Custom range state — PASS:** unmatched ranges do not falsely announce a preset as selected.

## Peer-state synthesis / contradiction resolution

This judgment was formed from the exact PR implementation and shared CSS before adopting peer conclusions.

- **Design QA:** current and correct. Its P2 blocker is directly supported by the shared flex CSS and by the explicit Mobile/long-Arabic acceptance condition.
- **UI Production Engineer:** PR-head state is current for the implementation but its claim that existing shared horizontal containment prevents compression is disproven by the CSS contract. The implementation must revise the same PR with the bounded shared repair.
- **Development Integrator:** Development-branch state is lifecycle-stale from REPORT001. Regardless, Integration remains `NO_MERGE` because REPORT002 has a current same-slice blocker.
- **Previous Director State:** superseded on one material assumption: the existing `SegmentedControl` Mobile containment was not sufficient to guarantee non-compressed long-content items.
- **Team Memory / Decision Log:** no overall system direction or durable design principle changed; no update is warranted.

The cross-role design contradiction is now synthesized: **Product Design agrees with QA.** The blocker remains implementation-actionable until a new exact PR HEAD contains the shared hardening and receives fresh exact-head Product Design + QA review.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap from Development in required order.
- Inspected issue #27, Development HEAD, the one open implementation PR, exact PR HEAD, PR-head implementation state, and current QA/Integration states.
- Re-inspected `03_COMPONENT_SYSTEM.md`, `05_MIGRATION_MATRIX.md`, `12_COMPONENT_DECISION_MATRIX.md`, `SegmentedControl.tsx`, its exact navigation CSS, and REPORT002 source/tests.
- Did not implement product code, modify peer specialist states, merge, touch `main`, trigger/rerun GitHub Actions, use hosted CI, deploy Vercel or modify preview branches.
- Did not update Team Memory or Decision Log because no durable direction changed.

### Cross-role handoff
- **To:** UI Production Engineer + Design QA; Development Integrator remains `NO_MERGE`.
- **What changed:** Product Design independently confirmed QA's P2 Mobile/long-content blocker on PR #49 exact HEAD `c71a486562bb6a9c3066cc4e074a23adacd51efe` and superseded the earlier assumption that existing SegmentedControl overflow alone prevented target compression.
- **Preserve:** exact four preset labels/order/range outputs; external `DateRange value/onChange`; custom date inputs; all report query/calculation/export/permission/routing/business truth; shared-system ownership of segmented-control geometry; `--block` equal-width behavior.
- **Need from you:** UI Production Engineer should harden only the shared default/non-block SegmentedControl item geometry in the same PR, preserve block stretching, and add focused contract evidence; Design QA and Product Design must then re-review the new stable exact HEAD.
- **Blocker level:** `BLOCKING`.
- **Baseline:** Development `0d131d58936e0a895beb0eb6a126482a5c638eb8`; reviewed PR #49 HEAD `c71a486562bb6a9c3066cc4e074a23adacd51efe`.
