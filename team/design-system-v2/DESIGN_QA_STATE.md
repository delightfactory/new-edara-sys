# Design QA State

## Reviewed baseline

- Review date: `2026-09-18`.
- Development branch: `design-system-v2-development`.
- Exact Development HEAD independently inspected before this state write: `41cdbf9dba7fa5301777a2f461ce3de40bae168a`.
- Active slice: `DS2-REPORT-002 — Report date-preset selector convergence`.
- Representative surface: `src/components/reports/ReportFilterBar.tsx` using shared `SegmentedControl`.
- Active implementation PR: `#49 — DS2-REPORT-002: converge report date preset selector`.
- PR base: `design-system-v2-development` at `41cdbf9dba7fa5301777a2f461ce3de40bae168a`.
- Exact PR HEAD independently reviewed: `c71a486562bb6a9c3066cc4e074a23adacd51efe`.
- PR state at review: `OPEN / DRAFT / mergeable=true`.
- Changed-file scope: 3 files — `ReportFilterBar` composition, focused Testing Library coverage, and UI Production Engineer owned state.
- Current disposition: `AGENT-REVIEW: BLOCKED`.
- Blocker severity: `P2 — Mobile/System-Fit contract blocker`.
- Evidence: `TESTS_AUTHORED_NOT_EXECUTED`; `SOURCE_REVIEW_PASS` withheld until the blocker is fixed on a new exact HEAD.
- Exact-head test/build/lint/runtime/preview PASS: not claimed.

## Independent QA disposition

**BLOCKED on exact PR HEAD `c71a486562bb6a9c3066cc4e074a23adacd51efe`.**

The REPORT002 functional slice is correctly isolated and the use of shared `SegmentedControl` is directionally correct, but the exact shared CSS contract does not currently guarantee the Mobile behavior this slice explicitly relies on. With four long Arabic preset labels, default segmented items may flex-shrink below their intrinsic content width instead of remaining discrete horizontally scrollable controls. That is a material Mobile/long-content Design System defect and prevents GREEN-DEV until the shared contract is hardened or Product Design explicitly re-bounds the acceptance condition.

## Exact-head findings

### Scope / functional isolation — PASS

The exact diff contains only:
- `src/components/reports/ReportFilterBar.tsx`
- `src/components/reports/ReportFilterBar.test.tsx`
- `team/design-system-v2/UI_IMPLEMENTATION_STATE.md`

No DB/migration/RPC/service/query-cache/RBAC/RLS/permission/route-guard/report-hook/business-calculation/validation/workflow/export/print/deployment contract is changed.

The implementation preserves:
- the exact four presets and Arabic copy/order: `آخر 7 أيام`, `آخر 30 يوماً`, `آخر 90 يوماً`, `هذا الشهر`;
- the existing `applyPreset(...)`, local-date conversion and `normalizeDateRange(...)` semantics;
- the external `value: DateRange` / `onChange(DateRange)` contract;
- both existing custom `<input type="date">` controls and their normalization behavior;
- caller ownership of report date state and all downstream analytics/query meaning.

The removal of the old local `open` state is non-functional: it was only set back to `false` on preset click and did not control any rendered disclosure.

### Shared-system fit — BLOCKED on one bounded contract defect

Using the established shared `SegmentedControl` instead of keeping a report-local preset-button mini-system is the correct V2 direction. The blocker is in the shared presentation contract itself, not in the report date semantics.

Exact shared CSS at the reviewed baseline currently combines:
- `.ds-segmented-control { display: inline-flex; ... max-width: 100%; }`;
- `.ds-segmented-control__item { min-width: 0; white-space: nowrap; ... }`;
- no non-shrinking flex basis / `flex-shrink: 0` for default non-block items;
- Mobile `overflow-x: auto` only on the container.

Because flex items default to `flex-shrink: 1`, the four button boxes are allowed to shrink under a constrained Mobile width. `white-space: nowrap` then prevents label wrapping, so long Arabic text can overflow a shrunken button target / visually collide instead of producing stable intrinsic-width scroll items. Container overflow alone does not establish the intended no-compression contract.

This violates the current REPORT002 acceptance criterion that all four Arabic labels remain horizontally reachable without compressed sub-touch targets, and conflicts with the North Star / Device Strategy requirements for deliberate Mobile touch geometry and long-Arabic tolerance.

### Minimum required fix

Keep the repair shared and narrowly scoped:

1. Harden the default non-block `SegmentedControl` items so horizontally scrolling options retain intrinsic control width (for example `flex: 0 0 auto` or equivalent non-shrinking behavior).
2. Preserve the existing `--block` equal-width contract (`flex: 1 1 0`) rather than globally disabling its intended stretch behavior.
3. Keep Mobile containment/scrolling inside the shared component; do not add a `ReportFilterBar`-specific CSS workaround.
4. Add a focused source/CSS contract artifact covering the non-shrinking segmented-item geometry, or an equivalently strong focused artifact, because the current DOM tests cannot detect this layout regression.
5. Preserve all current DateRange/preset/custom-date/report-query semantics exactly.

No wider report filter/date-input redesign is requested.

### Device / RTL / content tolerance

- **Mobile (`<=768px`) — BLOCKED:** the current shared flex contract does not reliably keep four long Arabic preset options as discrete non-compressed horizontal controls.
- **Tablet (`769–1024px`) — PASS at source level for the assigned composition:** touch-height is preserved and surrounding `ReportFilterBar` wrapping remains unchanged; no Tablet-specific regression is visible in the exact diff.
- **Desktop (`>=1025px`) — PASS at source level:** compact single-choice hierarchy remains alongside the existing custom-date inputs without changing report semantics.
- **RTL/Arabic — PASS except for the Mobile compression risk:** exact Arabic copy/order and logical document direction are preserved.
- **Long-content tolerance — BLOCKED on Mobile for this shared contract:** `white-space: nowrap` requires stable item width or equivalent containment to avoid text spilling from shrunken targets.

No runtime visual PASS is claimed.

### Accessibility / interaction — PASS at DOM/source level, subject to Mobile geometry blocker

- `SegmentedControl` exposes a named `role="group"` with `aria-label="اختصارات الفترة"`.
- Each choice remains a native `type="button"` with `aria-pressed` and shared `:focus-visible` treatment.
- Selection is visually reinforced through the shared active surface/elevation treatment and is not represented only by raw color state.
- The custom-range state correctly passes no matching value, leaving every preset `aria-pressed="false"`.
- `ReportFilterBar` is not rendered as a form submit boundary in the representative report header, and the explicit `type="button"` shared contract is appropriate.

### Relevant states — PASS for assigned semantics

- Matching preset selected state is preserved.
- Custom ranges correctly leave all presets unselected.
- The two custom date controls remain the editor for custom ranges.
- No new loading/empty/error/disabled/read-only/permission/offline/sync semantics are introduced by this primitive-only slice.
- Wider report loading/empty/error/query/export states remain outside scope and untouched.

## Test Artifact Gate / evidence honesty

Focused authored tests correctly protect:
- exact Arabic preset order/copy;
- all four existing emitted ranges at a frozen date;
- caller-owned callback output;
- matching `aria-pressed` state;
- custom-range no-selection behavior.

They do **not** protect the material shared CSS geometry relied on by the slice. A focused source/CSS contract artifact is therefore required with the bounded shared fix.

Evidence remains **`TESTS_AUTHORED_NOT_EXECUTED`**. Design QA did not run tests, build, lint or runtime inspection. No GitHub Actions/hosted CI or Vercel preview was triggered. No executed PASS is claimed. No known build/type failure is asserted; this blocker is a source-visible Mobile/System-Fit contract defect.

PR conversation comments, submitted reviews and inline review threads were empty before this QA review.

## Peer-state comparison / contradiction handling

This disposition was formed from the exact PR diff, pre-change `ReportFilterBar` contract, shared `SegmentedControl` implementation/CSS and representative report consumer before peer conclusions were used for alignment checking.

- **Product Design Director:** current scope boundary is correct and aligned on preserving all report date/query semantics. However its assertion that the existing shared `SegmentedControl` already guarantees Mobile horizontal containment without compressed targets conflicts with the exact flex CSS. This is a same-slice **BLOCKING** contradiction until the shared control is narrowly hardened or the Director explicitly re-bounds the acceptance condition.
- **UI Production Engineer:** PR-owned state is current and aligned on functional isolation and semantic parity, but its Mobile/no-compression claim relies on the same incomplete shared CSS assumption. The implementation needs the bounded shared repair before fresh handoff.
- **Development Integrator:** lifecycle state is correctly waiting for fresh exact-head gates; no merge may occur while this blocker remains current.
- **Team Memory / Workstream / Decision Log:** shared-system-first, Mobile-primary, touch, RTL/Arabic, functional-isolation and evidence-honesty rules support the blocker. No QA mutation is warranted outside this owned state.

## System-fit judgment

REPORT002 is the right convergence direction and should not be widened into a generic ReportFilterBar/date-input redesign. The correct repair is to strengthen the shared `SegmentedControl` contract proven insufficient by this four-long-label use case, then keep `ReportFilterBar` as a Reports-domain composite with all business/date semantics caller-owned. A Reports-local CSS escape hatch would fragment V2 and is not acceptable.

### Cross-role handoff
- **To:** UI Production Engineer + Product Design Director; Development Integrator remains `NO_MERGE`.
- **What changed:** Design QA independently reviewed PR #49 exact HEAD `c71a486562bb6a9c3066cc4e074a23adacd51efe` and issued `AGENT-REVIEW: BLOCKED` for one P2 shared Mobile/long-content geometry defect.
- **Preserve:** exact four presets/order/Arabic copy and range outputs; external `DateRange value/onChange`; both custom date inputs; report query/cache/service/hook/calculation/chart/table/metric/export/print/permission/routing/`AnalyticsGate` truth; the decision to use shared `SegmentedControl` rather than a report-local selector.
- **Need from you:** UI Production Engineer should make one bounded shared `SegmentedControl` CSS hardening so default horizontal items cannot flex-shrink under long Arabic content, preserve `--block` equal-width behavior, and add focused contract coverage. Product Design Director should independently reassess that new exact HEAD. Design QA must then re-review the new stable HEAD; Integrator must not merge before fresh same-head gates exist.
- **Blocker level:** `BLOCKING`.
- **Baseline:** Development `41cdbf9dba7fa5301777a2f461ce3de40bae168a`; reviewed PR #49 HEAD `c71a486562bb6a9c3066cc4e074a23adacd51efe`.
- **Evidence:** `TESTS_AUTHORED_NOT_EXECUTED`; `SOURCE_REVIEW_PASS` withheld; no executed build/test/lint/runtime/preview/release PASS claimed.
