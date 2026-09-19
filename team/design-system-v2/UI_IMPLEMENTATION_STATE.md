# UI Implementation State

## Reviewed baseline

- Run date: `2026-09-19`.
- Development branch: `design-system-v2-development`.
- Exact branch-creation baseline: `25167e84b4e7603e2069630bd395184f959823af`.
- Feature branch: `design-system-v2/report-008-receivables-chart-panel`.
- Draft PR: not opened yet.
- Active slice: `DS2-REPORT-008 — Receivables AR chart-panel convergence`.
- Representative surface: `src/pages/reports/ReceivablesPage.tsx` → chart section `تحصيلات AR مجمّعة بتاريخ البيع الأصلي` only.
- Disposition: `IN_PROGRESS — BOUNDED IMPLEMENTATION STARTED`.
- Evidence: source inspection only at this progress checkpoint; focused tests still to be authored before review.

## Independent implementation judgment

The bounded REPORT008 concern is a direct fit for the existing shared V2 `ChartPanel` contract. The Receivables AR chart currently duplicates the same neutral analytical card/header shell that REPORT005 already converged on Sales. No shared API/CSS change is needed: `ChartPanel` already provides `Card + SectionHeader`, semantic `h2`, wrap-capable action placement and caller-owned chart/state content.

The correct implementation is therefore intentionally narrow: replace only this local shell, pass the existing title/description and trust/freshness cluster into `ChartPanel`, and leave every blocked/loading/empty/data branch plus all AR/Recharts/report truth unchanged.

## Material progress

- Completed the mandatory shared-memory bootstrap and inspected issue #27, exact Development HEAD and open PRs targeting Development.
- Confirmed there was no active implementation PR targeting `design-system-v2-development`.
- Created `design-system-v2/report-008-receivables-chart-panel` from exact Development HEAD `25167e84b4e7603e2069630bd395184f959823af`.
- Inspected the current `ReceivablesPage.tsx`, shared `ChartPanel.tsx`, and the proven Sales chart consumer/test pattern.
- Confirmed the existing `ChartPanel` contract is sufficient without API/CSS widening.

## Preserve / implementation boundary

- Preserve `range`, `filters`, `useARDailyTotals`, `useARSummary`, `useSystemTrustState`, `arTrust`, `isBlocked` and all trust/freshness sources.
- Preserve `chartData` mapping of `sale_date`, `receipt_amount`, `refund_amount`, `net_cohort`.
- Preserve exact title/description and `TrustStateBadge + FreshnessIndicator` content/sources.
- Preserve blocked copy `بيانات AR محجوبة` + `يحتاج إلى اكتمال تشغيل محرك AR أولاً`.
- Preserve empty copy `لا توجد بيانات تحصيل في هذه الفترة`.
- Preserve `SkeletonCard height={260}` and successful `ResponsiveContainer height={260}`.
- Preserve exact `BarChart` margins/grid/axes/tooltip/formatters and all three series names/colors/radii/maxBarSize.
- Do not touch the three `MetricCard`s, `report-grid`, page header, `ReportFilterBar`, `SystemHealthBar`, `CustomTooltip`, any second report/chart, or shared `ChartPanel` API/CSS.
- No DB/migration/RPC/service/query-cache/RBAC/RLS/permission/routing/calculation/validation/workflow/export/print/business behavior changes.
- No GitHub Actions, Vercel/preview or `main` activity.

## Device / Arabic / accessibility intent

- Desktop must retain the current compact analytical rhythm under shared Card/SectionHeader spacing.
- Tablet/Mobile action metadata must remain wrap-capable without ordinary page-level horizontal overflow.
- Exact Arabic title/description/state copy remains unchanged and RTL-safe.
- Dark-mode surface/border/text presentation should come from existing shared semantic tokens through `ChartPanel`.
- The section must use the shared default semantic `h2`, preserving page `h1 -> h2` hierarchy.

## Current risk

No implementation blocker is known. Remaining work in this slice is the bounded source change, focused Vitest/Testing Library coverage, exact diff self-review, Draft PR creation and then fresh Design QA + Product Design exact-head review.

### Cross-role handoff
- **To:** Design QA + Product Design Director after a stable Draft PR HEAD exists.
- **What changed:** REPORT008 implementation branch now exists from exact Development HEAD and source inspection confirms the existing `ChartPanel` contract is sufficient.
- **Preserve:** one-chart/one-page presentation-only scope; exact AR title/description/action/state/chart contracts; all report-domain/business truth; no shared API widening; no Actions/Vercel/`main` activity.
- **Need from you:** no review yet; wait for the stable implementation PR HEAD and then review that exact head only.
- **Blocker level:** `NONE`.
- **Baseline:** `25167e84b4e7603e2069630bd395184f959823af`.
