# UI Implementation State

## Reviewed baseline

- Run date/time: `2026-09-30`.
- Development branch: `design-system-v2-development`.
- Exact feature baseline / Development HEAD: `186db3679f08e00550959cedf64cddaf4af65ac2`.
- Active slice: `DS2-REPORT-051 — Churn Risk shared chart-tooltip adoption`.
- Feature branch: `ds2-report-051-churn-risk-chart-tooltip-adoption-r2`.
- Exact implementation/test HEAD before this owned-state write: `e42b46b3c0eaac99e2a24d6dcffe62c64d18b6ef`.
- Disposition: `READY FOR DRAFT PR / FRESH EXACT-HEAD REVIEW REQUIRED`.
- Evidence: `TESTS_AUTHORED_NOT_EXECUTED`.
- Build/test/lint/runtime/preview/release PASS: not claimed.

## Independent implementation judgment

REPORT051 is correctly bounded to the Churn Risk Pie chart in `توزيع تصنيف العملاء`. The page keeps ownership of Recharts payload interpretation and all domain truth while the existing shared `ChartTooltip` owns only neutral presentation/anatomy.

The implementation does not require any shared-tooltip API/CSS/token/breakpoint widening and does not change query, trust, permission, validation, routing, cache, backend or business semantics.

## Material progress

- Revalidated the mandatory shared-memory bootstrap, issue #27, current Development baseline and open PRs before resuming the existing REPORT051 branch.
- Confirmed there was no open implementation PR targeting `design-system-v2-development` and the branch remained exactly based on Development HEAD `186db3679f08e00550959cedf64cddaf4af65ac2`.
- Preserved the existing product implementation in `src/pages/reports/ChurnRiskPage.tsx`: local `CustomTooltip` delegates presentation to shared `ChartTooltip`, keeps inactive/empty-payload gating, category heading, exact row label `عملاء`, `FMT` count formatting, caller color and explicit LTR numeric direction.
- Fixed the stale test harness in `src/pages/reports/ChurnRiskPage.test.tsx` that still asserted the removed Recharts `formatter` contract.
- Added focused coverage for:
  - inactive / empty-payload adapter guards;
  - exact category heading, one-row `عملاء` label, `FMT` count formatting and caller color;
  - CSSOM-normalized `#f59e0b -> rgb(245, 158, 11)`;
  - shared RTL/passive tooltip anatomy with long Arabic at 390 / 900 / 1440;
  - explicit LTR numeric value direction;
  - no chart/tooltip leakage while stats are loading or every pie value is zero;
  - unchanged 260px responsive geometry, filtered pie data/order, keys, center/radii/padding, exact five colors, shared tooltip wiring and Legend.

## Scope / files touched

Product/test scope:
- `src/pages/reports/ChurnRiskPage.tsx`
- `src/pages/reports/ChurnRiskPage.test.tsx`
- `team/design-system-v2/UI_IMPLEMENTATION_STATE.md` — owned lifecycle/handoff state only.

Explicitly unchanged:
- shared `ChartTooltip` implementation/API/tests/CSS/tokens/breakpoints;
- `ChartPanel`, `MetricGrid`, `ResponsiveCollection`, `StatePanel`, `Card`, `KeyValueList` and other shared patterns;
- Target Attainment and every other report tooltip;
- Churn Risk filters, KPI semantics, detail collection/table/cards, export/print/navigation;
- hooks/query/cache/RPC/Supabase/calculations/trust/permissions/RBAC/RLS/routing/validation/backend/business semantics.

## Device / state / accessibility coverage

- Mobile 390 / Tablet 900 / Desktop 1440 use the same shared RTL tooltip grammar with no breakpoint fork.
- Long Arabic category text is exercised through shared tooltip anatomy.
- Count remains bidi-safe with `dir="ltr"`.
- Tooltip remains passive/informational: no focus target, tab stop, role, aria-live or keyboard/action semantics.
- Exact chart presence rule remains `!statsLoading && pieData.length > 0`; no new loading/empty chart surface is introduced.
- Exact `ResponsiveContainer width="100%" height={260}`, Pie data/order/keys/center/radii/padding, five colors, Legend and Trust/Freshness presence rules remain preserved.

## Evidence / execution honesty

Evidence is `TESTS_AUTHORED_NOT_EXECUTED`.

The current sandbox has no project checkout/runtime, so `npm test`, `npm run build` and `npm run lint` were not executed. Hosted GitHub Actions were not triggered or used. No Vercel/preview deployment and no `main` activity occurred.

Source review found no known source-visible TypeScript/build blocker in the bounded diff. This is not an executed PASS claim.

## Risks / blocker status

- Fresh independent Design QA and Product Design review are required on the exact final Draft PR HEAD.
- Runtime/build/test evidence remains intentionally unclaimed.
- If exact review finds that preserving current Pie semantics requires shared-tooltip widening or functional change, REPORT051 must be marked `BLOCKED` rather than broadening scope.

### Cross-role handoff
- **To:** Design QA and Product Design Director; Development Integrator only after exact-head approvals.
- **What changed:** Churn Risk's Pie tooltip delegates neutral presentation to shared `ChartTooltip`, and the stale formatter-based test harness is replaced with focused adapter/device/state/chart-contract coverage.
- **Preserve:** ready-only chart presence; 260px geometry; exact Pie data/order/keys/radii/padding/colors; Legend; Trust/Freshness; caller-owned category/`عملاء`/FMT/color/LTR semantics; every header/KPI/detail/query/permission/backend/business contract.
- **Need from you:** independently review the exact Draft PR HEAD after PR creation; QA should issue or withhold `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`, and Product Design should independently accept or block the same exact HEAD.
- **Blocker level:** `NONE`.
- **Baseline:** Development / feature baseline `186db3679f08e00550959cedf64cddaf4af65ac2`; implementation/test HEAD before state write `e42b46b3c0eaac99e2a24d6dcffe62c64d18b6ef`.
