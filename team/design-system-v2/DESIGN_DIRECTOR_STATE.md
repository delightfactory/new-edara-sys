# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-18`.
- Authoritative branch: `design-system-v2-development`.
- Latest integrated product slice: `DS2-REPORT-001 — Report route sub-navigation convergence`, PR #48, squash merge `5d2c57d9a502a4bbb2d355d94634bcf8b53075d2`.
- Development slice-definition HEAD before this Director-state write: `e181c904c521110d000538552007565b9d0a02ed`.
- Open implementation PRs targeting Development at slice selection: `0`.
- Current single READY slice: `DS2-REPORT-002 — Report date-preset selector convergence`.
- Product Design disposition: `READY — DEPENDENCY-SAFE / NO DESIGN-SYSTEM BLOCKER`.
- No runtime visual, build, test, lint, preview or release PASS is claimed in this Director planning run.

## Independent Product Design judgment

**REPORT002 should converge only the four preset date-range buttons inside the domain-local `ReportFilterBar` to the existing shared `SegmentedControl`.**

This is the smallest system-advancing Reports slice after REPORT001. The current `ReportFilterBar` still owns valid Reports-domain semantics: it receives a `{ from, to }` value, calculates preset ranges, normalizes dates and emits the resulting `DateRange` back to each page. Those semantics should stay domain-owned. The duplicated visual primitive is the preset selector itself: four local buttons independently recreate single-choice selected state, border/background hierarchy, focus behavior and touch geometry despite a shared V2 single-choice control already existing.

The source supports a presentation-only convergence. `SegmentedControl` accepts an externally owned string selection, exposes native buttons with `aria-pressed`, a named group and visible shared focus treatment, and its CSS already guarantees `var(--ds-control-height-touch)` plus mobile horizontal containment. The Reports component can derive which preset is currently active by comparing the caller range with the existing preset calculations, map a selected preset back to the existing `DateRange`, and leave a custom range with no preset selected. No report query or business meaning has to move into the shared layer.

I do **not** approve migrating the custom date inputs or making the whole `ReportFilterBar` a generic shared `FilterBar` in this slice. The component decision matrix explicitly calls for FilterBar decomposition, not premature replacement, and the report date inputs are part of the domain composite that feeds analytics hooks. Broadening now would mix primitive convergence with date-control and report-query concerns.

## Source / blueprint evidence

### Component architecture — aligned

- The component-system rules require domain surfaces to compose shared components rather than duplicate primitives, while business rules remain outside visual primitives.
- The component decision matrix says `FilterBar` should be decomposed internally and preserve compound behavior initially.
- The Reports/Analytics migration wave explicitly targets filter grammar, visualization hierarchy and drilldown, so the preset selector is an appropriate system-depth step before chart/table redesign.

### Current ReportFilterBar — bounded recurring gap

`src/components/reports/ReportFilterBar.tsx` currently:
- defines exactly four presets: `آخر 7 أيام`, `آخر 30 يوماً`, `آخر 90 يوماً`, `هذا الشهر`;
- calculates their date ranges locally through `applyPreset(...)` and `normalizeDateRange(...)`;
- marks a preset active only when both `from` and `to` equal the caller value;
- renders each preset as a local styled `<button>` with approximately 32px-class visual geometry rather than the V2 practical 44px touch target;
- keeps two custom native date inputs alongside the presets;
- exposes only `value: DateRange` and `onChange(DateRange)` to report pages.

Representative consumers confirm that date state is functional input, not presentation state: `OverviewPage` passes `range.from/range.to` into sales, treasury and AR hooks and uses `range.to` for customer health; `SalesPage` passes the same range into sales daily/summary hooks. Therefore REPORT002 must preserve the external `DateRange` contract exactly.

### Shared SegmentedControl — correct primitive

`src/components/patterns/SegmentedControl.tsx` is explicitly documented as a compact single-choice control for filters/view modes. It does not claim tab-panel or route semantics. Its shared contract provides:
- caller-owned `value` and `onValueChange`;
- native button keyboard behavior;
- `role="group"` plus required `ariaLabel`;
- `aria-pressed` selection semantics;
- shared active/hover/focus treatment;
- minimum touch height through `--ds-control-height-touch`;
- mobile horizontal overflow containment.

No Reports-specific shared variant is needed.

## REPORT002 approved boundary

### In scope

- Replace only the preset-button group inside `ReportFilterBar` with shared `SegmentedControl`.
- Preserve the exact four presets, order, Arabic copy and calculated range meaning.
- Derive the selected preset from the current `{ from, to }` range using the existing preset calculations.
- Allow a custom range that matches no preset to render with no preset falsely selected.
- On preset selection, continue emitting the same normalized `DateRange` through the unchanged `onChange` contract.
- Add/update focused source-level tests for exact preset order/copy, emitted range parity, `aria-pressed` selected semantics and custom-range no-selection behavior.

### Explicit exclusions

- No redesign/shared migration of the two custom `<input type="date">` controls.
- No external `ReportFilterBar` API change.
- No change to `applyPreset`, normalization, month-boundary meaning or page default ranges except a strictly mechanical refactor that produces identical values.
- No report query/cache/service/hook/calculation/chart/table/metric/export/print/permission/routing/`AnalyticsGate` change.
- No REPORT001 SubNav change, broad report-page redesign, unrelated inline-style cleanup, backend/business change, preview/deploy, hosted CI or `main` work.

### Device / RTL / accessibility acceptance

- **Desktop (`>=1025px`)**: four presets remain compact and legible beside the existing custom-date controls without unnecessary hierarchy or wrapping regressions.
- **Tablet (`769–1024px`)**: selector remains touch-first with shared practical 44px control height; surrounding filter-bar wrapping remains intact.
- **Mobile (`<=768px`)**: all four Arabic labels remain reachable through the shared horizontal containment contract without viewport overflow or compressed sub-touch targets; no hover dependency.
- **RTL/Arabic**: preserve exact Arabic order/copy and logical direction; no clipped or abbreviated labels.
- **Accessibility**: concise Arabic group label, native button keyboard operation, shared `:focus-visible`, `aria-pressed` state and a selected treatment that is not communicated by color alone.
- **Custom range state**: if no existing preset equals the caller range, no preset may be announced selected; the existing date inputs remain the custom-range editor.

## BLOCK rule

If consuming `SegmentedControl` cannot preserve the current four preset range outputs and the external `DateRange` contract without changing report functional/query semantics, REPORT002 becomes `BLOCKED`; the implementation must not widen the slice or move analytics/date business logic into the shared primitive.

## Peer-state synthesis

The judgment above was formed from the current source and V2 architecture/device/migration/component-decision documents before comparing peer conclusions.

- **Integration State:** current lifecycle authority confirms REPORT001 is merged and no implementation PR is active; aligned with handing the queue back to Product Design.
- **Team Memory:** confirms REPORT001 integration and explicitly carries report date/scope convergence as remaining debt; aligned.
- **Design QA State:** lifecycle-stale by design after the REPORT001 merge, but its last exact-head QA conclusion does not contradict the new planning state.
- **UI Implementation State:** lifecycle-stale after the completed prior slice; no active product-code claim conflicts with REPORT002.
- **Previous Director State:** lifecycle-stale because it still handed REPORT001 to Integration; this file now supersedes that state.
- **Decision Log:** no durable design/system rule changed in this run, so no update is warranted.

No current cross-role `BLOCKING` contradiction exists.

## Repository actions this run

- Inspected current Development HEAD, issue #27, open PRs and the mandatory shared-memory chain.
- Inspected V2 component architecture, migration matrix, device strategy and component decision matrix.
- Inspected `ReportFilterBar`, representative Overview/Sales consumers, shared `SegmentedControl` and its navigation CSS contract.
- Updated `31_AGENT_TEAM_WORKSTREAM.md` to make REPORT002 the one exact dependency-safe READY slice and moved metrics/charts/tables to `DS2-REPORT-003` backlog.
- Did not modify product code, peer specialist states, Team Memory, Decision Log, GitHub Actions, preview branches, Vercel, `main`, deployment or merge state.

## Cross-role Handoff
- From: Product Design Director
- To: UI Production Engineer; Design QA and Development Integrator observe until an exact stable implementation PR HEAD exists
- Artifact: `DS2-REPORT-002 — Report date-preset selector convergence`; authoritative scope in `docs/design-system-v2/31_AGENT_TEAM_WORKSTREAM.md`
- Exact HEAD: `e181c904c521110d000538552007565b9d0a02ed` (slice-definition baseline immediately before this Director-state governance write)
- Status: `READY — DEPENDENCY-SAFE / NO DESIGN-SYSTEM BLOCKER`
- Evidence: current `ReportFilterBar` source; representative `OverviewPage`/`SalesPage` consumers; shared `SegmentedControl` source and CSS; V2 component/migration/device/component-decision blueprints; zero open implementation PRs at selection time
- Caveats: preserve exact DateRange/preset semantics; custom date inputs and all report query/business/chart/table/export/permission behavior are out of scope; no runtime/test/build/preview PASS is claimed; branch from the latest Development HEAD, which includes this governance-only state update
- Next action: UI Production Engineer opens exactly one REPORT002 implementation PR from the latest `design-system-v2-development` HEAD and changes only the preset-selector boundary; Product Design and QA wait for one stable exact PR HEAD before review
