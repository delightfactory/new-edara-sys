# Design QA State

## Reviewed baseline

- Review date: `2026-09-18`.
- Development branch: `design-system-v2-development`.
- Exact Development HEAD independently inspected before this state write: `6f009031e86e0bb4f0062637f8608d3daf687681`.
- Active slice: `DS2-REPORT-002 — Report date-preset selector convergence`.
- Representative surface: `src/components/reports/ReportFilterBar.tsx` using shared `SegmentedControl`.
- Active implementation PR: `#49 — DS2-REPORT-002: converge report date preset selector`.
- Feature-branch base: `41cdbf9dba7fa5301777a2f461ce3de40bae168a` on `design-system-v2-development`.
- Exact PR HEAD independently reviewed: `3e0f11d52de77f07953dd2a226c82ff19ec2f75f`.
- PR state at review: `OPEN / DRAFT / mergeable=true`.
- Changed-file scope: 5 files — Reports composition/test, shared navigation CSS/contract test, and UI Production Engineer owned state.
- Current disposition: `AGENT-REVIEW: GREEN-DEV`.
- Evidence: `SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- Exact-head build/test/lint/runtime/preview PASS: not claimed.

## Independent QA disposition

**GREEN-DEV on exact PR HEAD `3e0f11d52de77f07953dd2a226c82ff19ec2f75f`.**

The previous P2 Mobile/System-Fit blocker on `c71a486562bb6a9c3066cc4e074a23adacd51efe` is closed. The repair is shared, bounded and matches the minimum requested contract: default/non-block `SegmentedControl` items now retain intrinsic width through `flex: 0 0 auto`; `--block` retains its equal-width override `flex: 1 1 0`; Mobile horizontal containment remains owned by the shared component through `overflow-x: auto`; and focused source/CSS contract coverage protects those invariants.

REPORT002 remains functionally isolated and moves Reports toward the established shared V2 single-choice grammar without introducing a Reports-local primitive or changing report/date business truth.

## Exact-head findings

### Scope / functional isolation — PASS

The exact PR diff contains only:
- `src/components/reports/ReportFilterBar.tsx`
- `src/components/reports/ReportFilterBar.test.tsx`
- `src/styles/design-system-v2-navigation.css`
- `src/components/patterns/NavigationPatterns.test.tsx`
- `team/design-system-v2/UI_IMPLEMENTATION_STATE.md`

No DB/migration/RPC/service/query-cache/RBAC/RLS/permission/route-guard/report-hook/business-calculation/validation/workflow/export/print/deployment contract is changed.

The implementation preserves:
- the exact four presets and Arabic copy/order: `آخر 7 أيام`, `آخر 30 يوماً`, `آخر 90 يوماً`, `هذا الشهر`;
- existing `applyPreset(...)`, local-date conversion, `normalizeDateRange(...)`, and current-month first/last-day semantics;
- the external `value: DateRange` / `onChange(DateRange)` contract;
- both existing custom `<input type="date">` controls and their normalization behavior;
- caller ownership of report date state and all downstream analytics/query meaning;
- all report query/cache/service/calculation/chart/table/metric/export/print/permission/routing/`AnalyticsGate` truth.

The earlier removal of the unused local `open` state remains presentation-only and does not change rendered behavior.

### Shared-system fit — PASS

Using shared `SegmentedControl` is the correct V2 direction for this compact single-choice filter. The previous shared gap is now corrected centrally rather than patched in `ReportFilterBar`.

Exact shared contract on the reviewed HEAD:
- default `.ds-segmented-control__item` has `flex: 0 0 auto`;
- `.ds-segmented-control--block .ds-segmented-control__item` retains `flex: 1 1 0`;
- Mobile `.ds-segmented-control` retains `overflow-x: auto`;
- long labels remain `white-space: nowrap`, now paired with stable non-shrinking default item geometry.

No new SegmentedControl variant, Reports-local CSS escape hatch or page-local mini design system was introduced.

### Device / RTL / long-content — PASS at source level

- **Mobile (`<=768px`) — PASS:** default segmented items cannot flex-shrink below their intended control width; all four long Arabic presets can use the shared contained horizontal scroll track while retaining touch-height geometry.
- **Tablet (`769–1024px`) — PASS:** the surrounding `ReportFilterBar` wrapping remains unchanged and touch-first control height remains first-class; no accidental compressed-Desktop change is introduced.
- **Desktop (`>=1025px`) — PASS:** the selector remains compact beside the existing custom-date controls and preserves useful report-review density.
- **RTL/Arabic — PASS:** exact Arabic labels/order and logical shared layout are preserved.
- **Long-content tolerance — PASS for the assigned selector contract:** the previous nowrap + shrink collision risk is removed by the shared non-shrinking default item rule.

No runtime visual PASS is claimed.

### Accessibility / interaction — PASS at DOM/source level

- Shared control remains a named `role="group"` with `aria-label="اختصارات الفترة"`.
- Choices remain native `type="button"` controls with `aria-pressed` and shared visible `:focus-visible` treatment.
- Active state retains surface/elevation treatment and is not conveyed only by raw color.
- Matching preset state is derived from the caller-owned range; a custom range correctly leaves every preset unselected.
- No tab semantics or hidden duplicate device interaction tree was introduced.

### Relevant states — PASS for assigned semantics

- Matching preset selected state is preserved.
- Custom ranges leave all presets unselected while the two custom date inputs remain the editor.
- No new loading/empty/error/disabled/read-only/permission/offline/sync semantics are introduced by this bounded selector migration.
- Wider report loading/empty/error/permission/query/export states remain outside scope and untouched.

## Test Artifact Gate / evidence honesty

Focused authored coverage now protects both material layers:
- Reports behavior/composition: exact Arabic preset order/copy, all four existing emitted ranges at a frozen date, parent callback ownership, matching `aria-pressed`, and custom-range no-selection.
- Shared geometry contract: default non-shrinking `flex: 0 0 auto`, preserved block override `flex: 1 1 0`, and Mobile `overflow-x: auto` containment.

Evidence is **`TESTS_AUTHORED_NOT_EXECUTED`**. Design QA did not execute tests, build, lint, runtime inspection or preview. No GitHub Actions/hosted CI or Vercel preview was triggered. No execution PASS is claimed. No known source-visible build/type blocker remains on the reviewed HEAD.

PR inline review threads are empty. The prior QA BLOCKED review is anchored to superseded HEAD `c71a486...`; a fresh `AGENT-REVIEW: GREEN-DEV` review is recorded on exact current HEAD `3e0f11d...`.

## Peer-state comparison / contradiction handling

This judgment was formed from the exact current PR diff, current shared `SegmentedControl` implementation/CSS, tests and product contracts before applying peer conclusions.

- **Product Design Director:** its current repository state is anchored to old HEAD `c71a486...` and therefore stale for approval purposes, but it explicitly prescribed the same bounded repair now present. There is no remaining design contradiction on the repaired source; fresh Product Design exact-head acceptance is still required before Integration.
- **UI Production Engineer:** current PR-head state is aligned and accurately records the bounded shared repair plus `TESTS_AUTHORED_NOT_EXECUTED` evidence.
- **Development Integrator:** current Development state is anchored to the superseded blocked HEAD and remains lifecycle-stale for the repaired PR; it must wait for fresh Product Design exact-head acceptance, then revalidate base/drift/threads/mergeability.
- **Team Memory / Workstream / Decision Log:** shared-system-first, Mobile-primary, touch, RTL/Arabic, functional-isolation and evidence-honesty rules remain satisfied. No durable rule changed.

No same-head material peer contradiction remains. Product Design closeout is **pending**, not a QA blocker.

## Development drift judgment

Development advanced from the feature-branch merge base `41cdbf9...` to `6f009031...` only through peer governance state files (`DESIGN_DIRECTOR_STATE.md`, `DESIGN_QA_STATE.md`, `INTEGRATION_STATE.md`). There is no product/shared-code overlap with the five REPORT002 PR files. This governance-only drift does not invalidate the exact-head source review; Integration must still perform its normal final drift/mergeability check after all same-head gates are current.

## System-fit judgment

REPORT002 now fits the North Star and shared V2 grammar at source level. The real long-Arabic Mobile defect exposed by this consumer was repaired once in the shared system, while Reports retains ownership of all date/query meaning. The slice remains appropriately bounded and should not widen into custom-date, report-table, chart, metric or general FilterBar redesign.

### Cross-role handoff
- **To:** Product Design Director first; Development Integrator after same-head Product Design closeout.
- **What changed:** Design QA re-reviewed repaired PR #49 exact HEAD `3e0f11d52de77f07953dd2a226c82ff19ec2f75f`, closed the prior P2 geometry blocker, and issued `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`.
- **Preserve:** exact four preset labels/order/range outputs; external `DateRange value/onChange`; both custom date inputs; all report query/cache/service/calculation/chart/table/metric/export/print/permission/routing/`AnalyticsGate` truth; shared default non-shrinking geometry; `--block` equal-width behavior; shared Mobile containment.
- **Need from you:** Product Design Director should independently accept or block this same exact HEAD. If accepted and the HEAD remains unchanged, Development Integrator should revalidate base/drift/reviews/threads/mergeability and may integrate only if all gates remain green.
- **Blocker level:** `NONE` from Design QA; Product Design exact-head gate pending.
- **Baseline:** Development before this state write `6f009031e86e0bb4f0062637f8608d3daf687681`; reviewed PR #49 HEAD `3e0f11d52de77f07953dd2a226c82ff19ec2f75f`.
- **Evidence:** `SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`; no executed build/test/lint/runtime/preview/release PASS claimed.
