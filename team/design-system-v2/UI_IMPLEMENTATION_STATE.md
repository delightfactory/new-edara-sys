# UI Implementation State

## Reviewed baseline

- Run date/time: `2026-09-24 09:24 Africa/Cairo`.
- Development branch: `design-system-v2-development`.
- Exact feature baseline / Development HEAD at branch creation: `44c4324a2733d770d031862b4f207fcc18a9f2e9`.
- Active slice: `DS2-REPORT-047 — Sales shared chart-tooltip adoption`.
- Representative surface: `src/pages/reports/SalesPage.tsx` → existing page-local `CustomTooltip` used by both ready Sales charts.
- Feature branch: `ds2-report-047-sales-chart-tooltip-adoption`.
- Draft PR: `#95 — DS2-REPORT-047: adopt shared Sales chart tooltip`, base `design-system-v2-development`.
- Exact implementation/test PR HEAD before this owned-state write: `2a3ee9decb69a6d5763a408bb33d7f98ed38aca8`.
- Disposition: `REVIEW — FRESH EXACT-HEAD DESIGN QA + PRODUCT DESIGN REVIEW REQUIRED`.
- Evidence: `TESTS_AUTHORED_NOT_EXECUTED`.
- Build/test/lint/runtime/preview/release PASS: not claimed.

## Independent implementation judgment

Sales still carried a local tooltip surface/anatomy that duplicated the shared `ChartTooltip` proven in REPORT046. The correct bounded move is adoption only: keep the Sales Recharts adapter and all report truth in `SalesPage`, while delegating neutral tooltip presentation/anatomy to the existing shared pattern.

No shared API widening is required. The existing `ChartTooltip` contract already expresses Sales' label, ordered rows, caller series colors, formatted values and explicit value direction, so changing shared CSS/tokens/breakpoints or adjacent report consumers would be unnecessary scope expansion.

## Material implementation progress

- Completed the mandatory shared-memory bootstrap in the prescribed order and inspected issue #27, exact Development HEAD and all open PRs targeting Development.
- Independently inspected current Sales source/tests and the shared `ChartTooltip`, then compared the result against Product Design, QA, Integration and Team Memory state.
- Confirmed REPORT047 is fresh `READY — BOUNDED`, no competing implementation PR existed, and Development remained exactly `44c4324a2733d770d031862b4f207fcc18a9f2e9` at branch creation and again before PR creation.
- Created `ds2-report-047-sales-chart-tooltip-adoption` from that exact SHA.
- Replaced only the page-local tooltip markup with shared `ChartTooltip`; the local `CustomTooltip` remains the Recharts adapter and keeps the existing `active` / `payload?.length` guard.
- Preserved caller-owned payload order, `p.name`, `p.color`, `fmt(p.value) + ' ج.م'` output and explicit LTR value direction.
- Preserved both existing `Tooltip content={<CustomTooltip />}` integrations.
- Exported the local `CustomTooltip` adapter solely so focused tests can inspect the adapter contract directly; runtime chart behavior is unchanged.
- Extended Sales test artifacts to inspect both Sales payload shapes and shared tooltip anatomy at 390 / 900 / 1440 widths, plus both ready chart tooltip consumers at those widths.
- Kept existing regression coverage for MetricGrid/KPIs, first/second chart state precedence, blocked/empty/loading isolation, 240px/200px geometry, chart data mapping/margins and exact Area/Bar series contracts.
- Opened Draft PR #95 targeting only `design-system-v2-development`.

## Scope / files / shared patterns touched

Product/test files:
- `src/pages/reports/SalesPage.tsx` — Sales tooltip presentation adoption only; no shared component changes.
- `src/pages/reports/SalesPage.test.tsx` — focused adapter/device/state regression coverage.

Governance:
- `team/design-system-v2/UI_IMPLEMENTATION_STATE.md` (owned file only).

Explicitly unchanged:
- shared `ChartTooltip` implementation/API/CSS;
- `ChartPanel`, `StatePanel`, `MetricGrid`, tokens and canonical breakpoints;
- Treasury, Product Performance, Rep Performance and every other tooltip consumer;
- ReportFilterBar/date/query/cache semantics;
- chart data mapping, calculations, axes, margins, palettes, gradients, series identity, Trust/Freshness and business meaning;
- DB/migrations/RPC/services/RBAC/RLS/route guards/permissions/validation/export/print/workflow/backend semantics.

## Device / state / accessibility coverage

- **Mobile 390:** same shared RTL tooltip grammar; caller values remain LTR/bidi-isolated; no device-specific tooltip fork.
- **Tablet 900:** same touch-first shared tooltip presentation with no accidental Desktop-only fallback or breakpoint addition.
- **Desktop 1440:** compact analytical density and existing Recharts trigger contract remain unchanged.
- **First chart states:** exact `isBlocked -> dailyLoading -> empty -> ready`; 240px geometry; exact blocked/empty Arabic copy; Trust/Freshness unchanged.
- **Second chart states:** exact `dailyLoading -> empty -> ready`; 200px geometry; exact empty Arabic copy; no new BLOCKED/trust semantics.
- **Accessibility:** tooltip remains informational/passive. No action, click target, focus target, tab stop, role, live region or keyboard-only interaction was introduced.

## Evidence / execution honesty

Evidence is `TESTS_AUTHORED_NOT_EXECUTED`.

A sandbox filesystem check found no project `package.json` under `/mnt/data`, `/home/oai/share`, `/workspace`, `/workspaces` or `/tmp`; therefore no approved local project runtime was available to execute `npm test`, `npm run build` or `npm run lint`.

No GitHub Actions/hosted CI was triggered or used as evidence. No Vercel deployment, preview-branch activity or `main` activity occurred. Source-level self-review found no known TypeScript/build blocker in the bounded change, but no executed test/build/lint/runtime PASS is claimed.

## Preserve / risks

Preserve exactly:
- shared `ChartTooltip` remains presentation-only;
- Sales remains owner of Recharts payload interpretation, row order, labels, colors, currency formatting, value direction and all chart/business/trust semantics;
- first chart 240px state/ready contract and second chart 200px state/ready contract;
- all non-Sales tooltip consumers unchanged;
- no shared-contract widening in REPORT047.

Remaining risk is independent exact-head Design QA/Product Design review plus unexecuted local/runtime evidence. Any later PR-head movement invalidates exact-head approvals.

## Peer-state comparison

- **Product Design Director:** fresh and aligned; REPORT047 is explicitly bounded to Sales adoption of existing `ChartTooltip` for both current charts with no shared-contract widening.
- **Design QA:** Development state is lifecycle-historical through REPORT046; no REPORT047 exact-head disposition exists yet.
- **Development Integrator:** current through REPORT046 and records no competing REPORT047 integration blocker.
- **Team Memory:** current through REPORT046 and identifies duplicated page-local chart tooltips as bounded adoption debt; its unbounded REPORT047 placeholder is superseded by the fresher Product Design boundary/workstream update.
- **Decision Log / North Star:** aligned with shared-system-before-page-local invention, Arabic-first responsive composition and strict UI-only functional isolation.

Current contradiction classification: `NONE` from UI Production.

### Cross-role handoff
- **To:** Design QA and Product Design Director; Development Integrator only after fresh exact-head approvals.
- **What changed:** REPORT047 migrates the existing Sales `CustomTooltip` presentation onto shared `ChartTooltip` for both Sales charts; Draft PR #95 is open.
- **Preserve:** caller-owned payload interpretation/order/labels/colors/`fmt(value) + ' ج.م'`/LTR direction; first chart `isBlocked -> dailyLoading -> empty -> ready` with 240px geometry and Trust/Freshness; second chart `dailyLoading -> empty -> ready` with 200px geometry and no BLOCKED/trust semantics; all chart data/axes/margins/series and all non-Sales tooltip consumers unchanged.
- **Need from you:** independently review the exact current PR #95 HEAD after this owned-state write. Design QA should issue or withhold fresh `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`; Product Design should independently accept or block that same exact HEAD. Any later PR-head movement invalidates those gates.
- **Blocker level:** `NONE` from UI Production; independent review pending.
- **Baseline:** Development/feature baseline `44c4324a2733d770d031862b4f207fcc18a9f2e9`; implementation/test PR HEAD before this state write `2a3ee9decb69a6d5763a408bb33d7f98ed38aca8`; Draft PR `#95`; feature branch `ds2-report-047-sales-chart-tooltip-adoption`.
