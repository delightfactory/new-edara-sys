# UI Implementation State

## Reviewed baseline

- Run date: `2026-09-18`
- Development branch: `design-system-v2-development`
- Exact Development baseline / branch creation HEAD: `41cdbf9dba7fa5301777a2f461ce3de40bae168a`
- Feature branch: `ds2/report-002-date-presets`
- Draft PR: `#49 — DS2-REPORT-002: converge report date preset selector`
- Product/test HEAD before this owned-state write: `f6187f83a89ab5556fe542517602594f0d8b1270`
- Active slice: `DS2-REPORT-002 — Report date-preset selector convergence`
- Representative surface: `src/components/reports/ReportFilterBar.tsx` inherited by Reports consumers
- Disposition: `REVIEW — FRESH EXACT-HEAD PRODUCT DESIGN + DESIGN QA REQUIRED`
- Evidence: `TESTS_AUTHORED_NOT_EXECUTED`

## Independent implementation judgment

The Product Design boundary remains dependency-safe. `ReportFilterBar` owns the four report date-range meanings and the external `DateRange` callback contract; the duplicated concern was only the local preset-button presentation. Existing shared V2 `SegmentedControl` provides the needed single-choice semantics, named grouping, `aria-pressed`, focus-visible behavior, touch geometry and contained mobile overflow without taking ownership of report date calculations.

The implementation therefore consumes the existing shared primitive only for the four presets while preserving the exact preset order/copy, `applyPreset`/`normalizeDateRange` behavior, custom date inputs and caller-owned `value/onChange` contract.

## Material implementation progress

- Replaced the report-local `report-filter-presets` button renderer with shared `SegmentedControl`.
- Preserved exactly: `آخر 7 أيام`, `آخر 30 يوماً`, `آخر 90 يوماً`, `هذا الشهر`, in the same order.
- Preserved `applyPreset(...)`, local-date conversion, normalization and current-month first/last-day meaning.
- Derived the selected preset by comparing each existing calculated range with caller-owned `value`; a custom range now intentionally passes an empty shared selection so every preset exposes `aria-pressed="false"`.
- Preserved the external `value: DateRange` / `onChange(DateRange)` API and both custom `<input type="date">` controls unchanged.
- Removed only the obsolete local preset-only state/imports that had no functional consumer after the shared renderer replacement.
- Authored focused Testing Library coverage for exact Arabic preset order/copy, all four emitted range outputs, callback ownership, matching `aria-pressed` selection and custom-range no-selection.
- During source review, caught and fixed an implementation-only TypeScript/API mismatch before handoff: `SegmentedControl` is a default export and accepts `items`, not a named export with `options`. The branch now consumes the canonical shared API without modifying the primitive.
- Opened one Draft PR #49 targeting `design-system-v2-development`; no second slice was started.

Files/patterns touched before this state write:
- `src/components/reports/ReportFilterBar.tsx`
- `src/components/reports/ReportFilterBar.test.tsx`

## Preserve / verified boundaries

- Exact `DateRange` external contract remains `value` + `onChange`.
- Exact preset labels/order and range outputs remain domain-owned and unchanged.
- Manual date inputs and their normalization behavior remain unchanged.
- Shared `SegmentedControl` remains presentation-only; no report calculation or eligibility logic moved into it.
- No query/cache/service/hook/calculation/chart/table/metric/export/print/permission/routing/`AnalyticsGate` behavior changed.
- No REPORT001 `SubNav`, report-page layout, DB/RPC, RBAC/RLS, route guard, workflow, validation or business-semantic change.
- No shared token/component CSS modification was required.

## Device / state coverage

- **Mobile (`<=768px`)**: shared `SegmentedControl` horizontal containment keeps all four Arabic labels reachable without page-level overflow or compressed local buttons.
- **Tablet (`769–1024px`)**: shared practical touch-height geometry remains first-class inside the existing wrapping report filter bar.
- **Desktop (`>=1025px`)**: compact single-choice hierarchy remains beside the existing custom-date controls; surrounding filter composition is unchanged.
- **RTL/Arabic**: exact Arabic copy/order are preserved and the shared logical layout is reused.
- **Accessibility**: `ariaLabel="اختصارات الفترة"`, native buttons, shared `:focus-visible`, and `aria-pressed`; selection is not color-only through the shared active class contract.
- **Custom range state**: values matching no preset intentionally leave every preset unselected while the existing date inputs remain the editor.
- **Other report states**: loading/empty/error/permission/query/export states are outside this primitive-only slice and remain untouched.

## Test / execution evidence

Evidence: **`TESTS_AUTHORED_NOT_EXECUTED`**.

Focused Vitest/Testing Library tests protect exact preset order/copy, all four preset output ranges at a fixed local date, callback ownership, selected-state semantics and custom-range no-selection. No approved executable repository checkout/package runtime was available in the sandbox, so `npm test`, `npm run build` and `npm run lint` were not executed. No local/build/test/lint/runtime/preview PASS is claimed. Hosted GitHub Actions/CI and Vercel were not used.

No known source-visible TypeScript/build blocker remains after correcting the shared component import/prop API mismatch described above.

## Peer-state comparison / current risk

- **Product Design Director:** current and aligned; REPORT002 is explicitly bounded to preset-selector convergence onto existing shared `SegmentedControl`, with custom date inputs and broader filter/report redesign excluded.
- **Design QA:** lifecycle-stale from REPORT001; fresh exact-head review is required for PR #49.
- **Development Integrator:** lifecycle authority confirms REPORT001 is integrated; Development HEAD remained the branch baseline `41cdbf9d...` through PR creation.
- **Team Memory / Decision Log:** shared-system-first, functional-isolation, device and evidence rules remain aligned; no UI Production mutation is warranted.
- Residual risk is execution/runtime evidence only: focused tests are authored but not executed in the available environment.

### Cross-role handoff
- **To:** Product Design Director + Design QA for fresh exact-head review; Development Integrator only after both gates are current.
- **What changed:** the four report date presets now use shared V2 `SegmentedControl` while all preset/date/report semantics remain owned by `ReportFilterBar` and its callers.
- **Preserve:** exact four labels/order/range calculations; external `DateRange` API; custom date inputs; all report query/cache/service/calculation/chart/table/metric/export/print/permission/routing/`AnalyticsGate` truth; REPORT001 SubNav and broader REPORT003/Admin/Global backlog.
- **Need from you:** review the final exact PR #49 HEAD after this owned-state write. QA should issue `SOURCE_REVIEW_PASS + AGENT-REVIEW: GREEN-DEV` only on that same head; Product Design should independently close the same exact head. Integrator remains `NO_MERGE` until both are fresh.
- **Blocker level:** `NONE` from implementation.
- **Baseline:** `41cdbf9dba7fa5301777a2f461ce3de40bae168a`.
- **Product/test HEAD before state write:** `f6187f83a89ab5556fe542517602594f0d8b1270`.
- **PR:** `#49` / `ds2/report-002-date-presets` -> `design-system-v2-development`.
- **Evidence:** `TESTS_AUTHORED_NOT_EXECUTED`.
